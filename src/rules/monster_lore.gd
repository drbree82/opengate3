class_name MonsterLore
extends RefCounted
## Turns a monster stat block (data/monsters.json) into a readable creature sheet: the numbers, plus
## plain-English notes on what the creature is good at, where it is weak and what it can do.
## Shown by the journal's Creatures tab and by the "You face: ..." line (src/ui/journal_panel.gd).
## Pure rules code: no nodes, no game state.
##
## describe(id, db) -> {
##   id, name, kind ("CR 1/3 - medium undead"), desc,
##   stats: [[label, value], ...]       the readout, in display order
##   strengths, weaknesses, powers: [String, ...]   one sentence each
## }
## The notes are worked out from the stat block, so a new monster gets them for free. To add a note
## the numbers cannot express, give the monster a "lore" entry in its JSON:
##   "lore": {"strengths": ["..."], "weaknesses": ["..."], "powers": ["..."]}
## Those sentences are listed first. To teach the generator a new rule, add it to _strengths(),
## _weaknesses() or _powers() and a check to tests/test_rules.gd (test_monster_lore).

const SAVE_NAMES := {"fort": "Fortitude", "ref": "Reflex", "will": "Will"}
const DAMAGE_NAMES := {"B": "bludgeoning", "S": "slashing", "P": "piercing"}
const WEAPON_HINTS := {"B": "maces, hammers, staves", "S": "swords, axes", "P": "spears, arrows, daggers"}
## What each immunity tag means in play (tags are the ones spells carry in data/spells.json).
const IMMUNITY_NAMES := {"mind": "mind-affecting magic", "sleep": "sleep", "fear": "fear", "poison": "poison"}


static func describe(monster_id: String, db: Dictionary) -> Dictionary:
	var b: Dictionary = db.monsters.get(monster_id, {})
	if b.is_empty():
		return {}
	var lore: Dictionary = b.get("lore", {})
	var out := {
		"id": monster_id, "name": str(b.get("name", monster_id)), "kind": _kind(b), "desc": str(b.get("desc", "")),
		"stats": _stats(b, db),
		"strengths": lore.get("strengths", []).duplicate(),
		"weaknesses": lore.get("weaknesses", []).duplicate(),
		"powers": lore.get("powers", []).duplicate(),
	}
	out.strengths.append_array(_strengths(b, db))
	out.weaknesses.append_array(_weaknesses(b, db))
	out.powers.append_array(_powers(b, db))
	return out


## The whole sheet as plain text lines (used by tests and by anything that cannot show rich text).
static func text(monster_id: String, db: Dictionary) -> String:
	var d := describe(monster_id, db)
	if d.is_empty():
		return ""
	var lines: Array = ["%s (%s)" % [d.name, d.kind]]
	if d.desc != "":
		lines.append(d.desc)
	for row in d.stats:
		lines.append("%s: %s" % [row[0], row[1]])
	for section in [["Strengths", d.strengths], ["Weaknesses", d.weaknesses], ["Attacks and powers", d.powers]]:
		if section[1].is_empty():
			continue
		lines.append(section[0] + ":")
		for s in section[1]:
			lines.append("  - " + s)
	return "\n".join(lines)


## Challenge rating as a number ("1/3" -> 0.33).
static func cr_value(b: Dictionary) -> float:
	var cr := str(b.get("cr", "1"))
	if cr.contains("/"):
		var parts := cr.split("/")
		return float(parts[0]) / maxf(1.0, float(parts[1]))
	return float(cr)


static func _signed(n: int) -> String:
	return "+%d" % n if n >= 0 else str(n)


static func _kind(b: Dictionary) -> String:
	var types: Array = []
	for tag in b.get("tags", []):
		if tag != "living":
			types.append(str(tag))
	return "CR %s - %s %s" % [str(b.get("cr", "?")), str(b.get("size", "medium")), " ".join(types) if not types.is_empty() else "creature"]


static func _stats(b: Dictionary, db: Dictionary) -> Array:
	var hp := str(b.get("hp", 1))
	if typeof(b.get("hp")) == TYPE_STRING:
		hp = "%d (%s)" % [Dice.average(b.hp), b.hp]
	var sv: Dictionary = b.get("saves", {})
	var ab: Dictionary = b.get("abilities", {})
	var scores: Array = []
	for id in CharRules.ABILITIES:
		scores.append("%s %d" % [str(id).capitalize(), int(ab.get(id, 10))])
	var speed := int(b.get("speed", 30))
	var rows: Array = [
		["Hit points", "%s  (%d hit %s)" % [hp, int(b.get("hd", 1)), "die" if int(b.get("hd", 1)) == 1 else "dice"]],
		["Armor class", "%d  (touch %d, flat-footed %d)" % [int(b.get("ac", 10)), int(b.get("touch", b.get("ac", 10))), int(b.get("flatFooted", b.get("ac", 10)))]],
		["Saves", "Fortitude %s, Reflex %s, Will %s" % [_signed(int(sv.get("fort", 0))), _signed(int(sv.get("ref", 0))), _signed(int(sv.get("will", 0)))]],
		["Initiative", _signed(int(b.get("init", 0)))],
		["Speed", "%d ft (%d squares a turn)" % [speed, maxi(1, floori(speed / 5.0))]],
		["Abilities", ", ".join(scores)],
	]
	var skills: Array = []
	for sid in b.get("skills", {}):
		skills.append("%s %s" % [str(db.get("skills", {}).get(sid, {}).get("name", str(sid).capitalize())), _signed(int(b.skills[sid]))])
	if not skills.is_empty():
		rows.append(["Skills", ", ".join(skills)])
	return rows


## Names of the spells in db that pass `test` (a Callable taking the spell Dictionary), at most `limit`.
static func _spell_names(db: Dictionary, test: Callable, limit := 4) -> Array:
	var names: Array = []
	for sid in db.get("spells", {}):
		var sp = db.spells[sid]
		if typeof(sp) != TYPE_DICTIONARY or not test.call(sp):
			continue
		if names.size() < limit:
			names.append(str(sp.get("name", sid)))
	return names


## Would this spell be stopped by the monster's immunities, type or hit dice? (Mirrors SpellRules.)
static func _shrugs_off(b: Dictionary, sp: Dictionary) -> bool:
	if sp.has("only") and not (sp.only in b.get("tags", [])):
		return true
	for tag in sp.get("tags", []):
		if tag in b.get("immunities", []):
			return true
	return sp.has("hdLimit") and int(b.get("hd", 1)) > int(sp.hdLimit)


static func _is_offensive(sp: Dictionary) -> bool:
	return not sp.has("heal") and str(sp.get("target", "")) in ["enemy", "enemies_burst", "burst", "cone"]


static func _strengths(b: Dictionary, db: Dictionary) -> Array:
	var out: Array = []
	var dr = b.get("dr")
	if dr != null:
		var bypass := str(dr.get("bypass", "-"))
		if DAMAGE_NAMES.has(bypass):
			out.append("Shrugs off weapons: every hit does %d less damage unless the weapon is %s." % [int(dr.amount), DAMAGE_NAMES[bypass]])
		else:
			out.append("Shrugs off weapons: every weapon hit does %d less damage." % int(dr.amount))
	var immune: Array = b.get("immunities", [])
	if not immune.is_empty():
		var names: Array = []
		for tag in immune:
			names.append(str(IMMUNITY_NAMES.get(tag, tag)))
		var wasted := _spell_names(db, func(sp): return _is_offensive(sp) and _tagged(sp, immune))
		var line := "Immune to %s." % _list(names)
		if not wasted.is_empty():
			line += " %s will do nothing." % _list(wasted)
		out.append(line)
	var ac := int(b.get("ac", 10))
	if ac >= _expected_ac(b) + 3:
		out.append("Well protected (armor class %d): expect to miss often." % ac)
	var strong := _saves(b, true)
	if not strong.is_empty():
		out.append("Strong %s: effects that allow %s often fail." % [_save_list(b, strong), "that save" if strong.size() == 1 else "those saves"])
	if int(b.get("init", 0)) >= 4:
		out.append("Quick off the mark (initiative %s): it usually acts before you do." % _signed(int(b.init)))
	if int(b.get("speed", 30)) >= 40:
		out.append("Fast: it covers %d squares a turn, so you cannot outrun it." % floori(int(b.speed) / 5.0))
	return out


static func _weaknesses(b: Dictionary, db: Dictionary) -> Array:
	var out: Array = []
	var dr = b.get("dr")
	if dr != null and DAMAGE_NAMES.has(str(dr.get("bypass", "-"))):
		var bypass := str(dr.bypass)
		out.append("Use %s weapons (%s): they do full damage." % [DAMAGE_NAMES[bypass], WEAPON_HINTS[bypass]])
	for tag in b.get("tags", []):
		var bane := _spell_names(db, func(sp): return str(sp.get("only", "")) == tag and not _shrugs_off(b, sp))
		if not bane.is_empty():
			out.append("Being %s, it can be targeted by %s - made for exactly this kind of creature." % [_article(str(tag)) if tag != "undead" else "undead", _list(bane)])
	if b.get("staggered", false):
		out.append("Slow: each turn it can move OR attack, not both. Step back and it wastes its turn walking.")
	var unused: Array = []
	for worst in _saves(b, false):
		var useful := _spell_names(db, func(sp): return _is_offensive(sp) and sp.get("save", {}).get("type", "") == worst and not _shrugs_off(b, sp))
		if useful.is_empty():
			unused.append(worst)
		else:
			out.append("Weak %s: %s should work well." % [_save_list(b, [worst]), _list(useful)])
	if not unused.is_empty():
		out.append("Weak %s: anything that makes it roll %s is likely to work." % [_save_list(b, unused), "that save" if unused.size() == 1 else "those saves"])
	var ac := int(b.get("ac", 10))
	var touch := int(b.get("touch", ac))
	if ac <= _expected_ac(b):
		out.append("Easy to hit (armor class %d)." % ac)
	if ac - touch >= 3:
		var rays := _spell_names(db, func(sp): return str(sp.get("attack", "")).contains("touch") and not _shrugs_off(b, sp), 3)
		out.append("Its protection is mostly armor or hide: touch attacks only need to beat %d%s." % [touch, (" (%s)" % _list(rays)) if not rays.is_empty() else ""])
	if ac - int(b.get("flatFooted", ac)) >= 3:
		out.append("Relies on dodging: catch it before it has acted and its armor class drops to %d." % int(b.flatFooted))
	var limited := _spell_names(db, func(sp): return sp.has("hdLimit") and _is_offensive(sp) and not _shrugs_off(b, sp))
	if not limited.is_empty():
		out.append("Only %d hit %s, so %s can take it out of the fight." % [int(b.get("hd", 1)), "die" if int(b.get("hd", 1)) == 1 else "dice", _list(limited, "or")])
	return out


static func _powers(b: Dictionary, db: Dictionary) -> Array:
	var out: Array = []
	for atk in b.get("attacks", []):
		var crit: Array = atk.get("crit", [20, 2])
		var threat := "20" if int(crit[0]) >= 20 else "%d-20" % int(crit[0])
		var line := "%s: %s to hit, %s %s damage, critical on %s (x%d)" % [str(atk.get("name", "Attack")), _signed(int(atk.get("bonus", 0))),
			str(atk.get("damage", "1d4")), str(DAMAGE_NAMES.get(atk.get("dtype", "B"), atk.get("dtype", ""))), threat, int(crit[1])]
		if atk.get("ranged", false):
			line += ", ranged (up to %d squares)" % int(atk.get("range", 0))
		out.append(line + ".")
	for entry in b.get("spells", []):
		var sp: Dictionary = db.get("spells", {}).get(entry.get("id", ""), {})
		if sp.is_empty():
			continue
		var uses := int(entry.get("uses", 1))
		var how := "at will" if uses < 0 else ("once" if uses == 1 else "%d times" % uses)
		out.append("Casts %s (%s): %s" % [str(sp.get("name", entry.id)), how, str(sp.get("desc", ""))])
	if int(b.get("sneakDice", 0)) > 0:
		out.append("Sneak attack: +%dd6 damage against a flanked or unready target." % int(b.sneakDice))
	match str(b.get("ai", "melee")):
		"ranged":
			out.append("Tactics: keeps its distance and shoots while it has a clear line.")
		"caster":
			out.append("Tactics: opens with its spells and only then fights hand to hand.")
		_:
			out.append("Tactics: closes in and attacks whoever is nearest.")
	return out


## Armor class that counts as ordinary for this challenge rating (a rough yardstick, not a rule):
## 3 or more above it is "well protected", at or below it is "easy to hit".
static func _expected_ac(b: Dictionary) -> int:
	return 12 + floori(cr_value(b))


## Save ids that stand out for a creature of this many hit dice: the strong ones or the weak ones.
static func _saves(b: Dictionary, strong: bool) -> Array:
	var hd := int(b.get("hd", 1))
	var out: Array = []
	for id in ["fort", "ref", "will"]:
		if not b.get("saves", {}).has(id):
			continue
		var v := int(b.saves[id])
		if (strong and v >= 3 + ceili(hd / 2.0)) or (not strong and v <= 1 + floori(hd / 3.0)):
			out.append(id)
	return out


## "Will save (+1)" / "Fortitude and Reflex saves (+0, +0)".
static func _save_list(b: Dictionary, ids: Array) -> String:
	var names: Array = []
	var values: Array = []
	for id in ids:
		names.append(SAVE_NAMES[id])
		values.append(_signed(int(b.saves[id])))
	return "%s %s (%s)" % [_list(names), "save" if ids.size() == 1 else "saves", ", ".join(values)]


static func _tagged(sp: Dictionary, tags: Array) -> bool:
	for tag in sp.get("tags", []):
		if tag in tags:
			return true
	return false


static func _article(word: String) -> String:
	return ("an " if word.substr(0, 1) in ["a", "e", "i", "o", "u"] else "a ") + word


## "A", "A and B", "A, B and C".
static func _list(items: Array, joiner := "and") -> String:
	if items.size() <= 1:
		return str(items[0]) if items.size() == 1 else ""
	var head: Array = items.slice(0, items.size() - 1)
	return "%s %s %s" % [", ".join(head), joiner, str(items[-1])]
