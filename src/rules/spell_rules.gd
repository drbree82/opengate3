class_name SpellRules
extends RefCounted
## Spell and special-ability resolution. Pure logic. Spells are data (data/spells.json):
##   name, school, levels {class_id: level}, range (squares, 0 = touch/self), tags [..]
##   target   "enemy" | "ally" | "self" | "cone" | "burst" | "allies_burst" | "enemies_burst"
##   area     size in squares for cone/burst shapes
##   attack   "ranged_touch" | "melee_touch"  (needs an attack roll against touch AC)
##   save     {type: "fort|ref|will", effect: "negates|half"}
##   damage / heal   {dice, scale: {per, offset, max}, bonusScale: {per, max}, type}
##   effect   {name, modifiers, conditions, duration: {rounds | roundsPerLevel | encounter | rest}}
##   only     tag the target must have (e.g. "undead");  hdLimit  max hit dice affected
##   pool     class-ability pool it spends (e.g. "channel") instead of a spell slot
##   special  engine-handled extras: "stabilize"
## Simplification: casters spend a slot of the spell's level to cast ANY spell they know of that
## level (no per-slot preparation). Level 0 spells are at will.


static func level_of(spell: Dictionary, caster: Dictionary) -> int:
	var levels: Dictionary = spell.get("levels", {})
	var casting = caster.get("casting")
	if casting != null and levels.has(casting.classId):
		return int(levels[casting.classId])
	var lowest := 9
	for k in levels:
		lowest = mini(lowest, int(levels[k]))
	return lowest if not levels.is_empty() else 0


static func caster_level(caster: Dictionary) -> int:
	var casting = caster.get("casting")
	return int(casting.casterLevel) if casting != null else int(caster.get("level", 1))


static func dc_of(spell: Dictionary, caster: Dictionary) -> int:
	if spell.has("pool"):
		return 10 + floori(caster_level(caster) / 2.0) + int(caster.abilities.cha.mod)
	var casting = caster.get("casting")
	return 10 + level_of(spell, caster) + (int(casting.mod) if casting != null else 0)


## How many more times can this actor use the spell/ability today? (-1 = unlimited)
static func uses_left(actor: Dictionary, stats: Dictionary, spell: Dictionary, db: Dictionary) -> int:
	var used: Dictionary = actor.get("used", {})
	if spell.has("pool"):
		return int(stats.pools.get(spell.pool, 0)) - int(used.get("pools", {}).get(spell.pool, 0))
	if actor.has("monsterId"):
		for sp in db.monsters[actor.monsterId].get("spells", []):
			if sp.id == spell.id:
				var uses: int = sp.get("uses", -1)
				return -1 if uses < 0 else uses - int(used.get("spells", {}).get(spell.id, 0))
		return 0
	var lv := level_of(spell, stats)
	if lv == 0:
		return -1
	var casting = stats.get("casting")
	if casting == null:
		return 0
	return int(casting.slots.get(str(lv), 0)) - int(used.get("slots", {}).get(str(lv), 0))


static func can_use(actor: Dictionary, stats: Dictionary, spell: Dictionary, db: Dictionary) -> bool:
	return uses_left(actor, stats, spell, db) != 0


static func spend(actor: Dictionary, stats: Dictionary, spell: Dictionary) -> void:
	if not actor.has("used"):
		actor["used"] = {}
	var used: Dictionary = actor.used
	for k in ["slots", "pools", "spells"]:
		if not used.has(k):
			used[k] = {}
	if spell.has("pool"):
		used.pools[spell.pool] = int(used.pools.get(spell.pool, 0)) + 1
	elif actor.has("monsterId"):
		used.spells[spell.id] = int(used.spells.get(spell.id, 0)) + 1
	else:
		var lv := level_of(spell, stats)
		if lv > 0:
			used.slots[str(lv)] = int(used.slots.get(str(lv), 0)) + 1


## Rolls a damage/heal amount spec. Returns a roll result.
static func roll_amount(spec: Dictionary, cl: int, rng: Rng, kind: String, label: String, actor_name: String) -> Dictionary:
	var times := 1
	if spec.has("scale"):
		var sc: Dictionary = spec.scale
		times = floori((cl + int(sc.get("offset", 0))) / float(sc.get("per", 1)))
		times = clampi(times, 1, int(sc.get("max", 20)))
	var rolled := Dice.roll(spec.dice, rng, times)
	var bonus := 0
	if spec.has("bonusScale"):
		var bs: Dictionary = spec.bonusScale
		bonus = mini(int(bs.get("max", 20)), floori(cl / float(bs.get("per", 1))))
	var r := Dice.as_result(rolled, kind, label, actor_name)
	if bonus != 0:
		r.parts.append({"label": "Caster level", "value": bonus})
		r.modifier = int(r.modifier) + bonus
		r.total = int(r.total) + bonus
	return r


## Resolves a spell against ONE target.
##   caster, target  STATS dictionaries;  shared  a pre-rolled amount for area spells (rolled once).
## Returns {affected, hit, saved, damage, heal, effect (Dictionary or null), note, rolls: [...]}
static func resolve_on_target(caster: Dictionary, spell: Dictionary, target: Dictionary, rng: Rng, shared = null) -> Dictionary:
	var out := {"affected": true, "hit": true, "saved": false, "damage": 0, "heal": 0, "effect": null, "note": "", "rolls": []}
	var immune: Array = target.get("immunities", [])
	if spell.has("only") and not (spell.only in target.get("tags", [])):
		out.affected = false
		out.note = "unaffected"
		return out
	if spell.id in immune:
		out.affected = false
		out.note = "immune"
		return out
	for tag in spell.get("tags", []):
		if tag in immune:
			out.affected = false
			out.note = "immune"
			return out
	if spell.has("hdLimit") and int(target.get("hd", 1)) > int(spell.hdLimit):
		out.affected = false
		out.note = "too powerful to be affected"
		return out

	if spell.has("attack"):
		var is_ranged: bool = spell.attack == "ranged_touch"
		var parts: Array = [{"label": "BAB", "value": caster.bab}]
		parts.append({"label": "Dex" if is_ranged else "Str", "value": caster.abilities.dex.mod if is_ranged else caster.abilities.str.mod})
		if caster.get("size", "medium") == "small":
			parts.append({"label": "Size", "value": 1})
		var ac: int = target.touch
		var roll := Checks.d20(rng, "attack", spell.name, caster.name, parts, ac, "touch attack vs AC %d" % ac)
		var hit: bool = roll.natural != 1 and (roll.natural == 20 or int(roll.total) >= ac)
		roll["success"] = hit
		out.rolls.append(roll)
		if not hit:
			out.hit = false
			out.affected = false
			out.note = "miss"
			return out

	var half := false
	if spell.has("save"):
		var tags: Array = ["vs_spell", "vs_" + str(spell.get("school", ""))]
		for tag in spell.get("tags", []):
			tags.append("vs_" + str(tag))
		var sv := Checks.save(target, spell.save.type, dc_of(spell, caster), rng, tags)
		out.rolls.append(sv)
		if sv.success:
			out.saved = true
			if spell.save.get("effect", "negates") == "negates":
				out.affected = false
				out.note = "resisted"
				return out
			half = true

	var cl := caster_level(caster)
	if spell.has("damage"):
		var dr: Dictionary = shared if shared != null else roll_amount(spell.damage, cl, rng, "damage", spell.name + " damage", caster.name)
		if shared == null:
			out.rolls.append(dr)
		out.damage = maxi(1, floori(int(dr.total) / 2.0)) if half else int(dr.total)
	if spell.has("heal"):
		var hr: Dictionary = shared if shared != null else roll_amount(spell.heal, cl, rng, "heal", spell.name, caster.name)
		if shared == null:
			out.rolls.append(hr)
		out.heal = int(hr.total)
	if spell.has("effect") and not out.saved:
		out.effect = build_effect(spell, cl)
	return out


static func build_effect(spell: Dictionary, cl: int) -> Dictionary:
	var e: Dictionary = spell.effect.duplicate(true)
	if not e.has("id"):
		e["id"] = spell.id
	if not e.has("name"):
		e["name"] = spell.name
	var d: Dictionary = e.get("duration", {"encounter": true})
	if d.has("roundsPerLevel"):
		d = {"rounds": int(d.roundsPerLevel) * cl}
	e["duration"] = d
	e["source"] = spell.id
	return e
