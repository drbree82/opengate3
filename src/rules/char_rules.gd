class_name CharRules
extends RefCounted
## Pathfinder 1e player-character maths. Pure logic - covered by tests/test_rules.gd.
##
## A CHARACTER is a plain Dictionary (so it can be saved as JSON):
##   id, name, race, cls, level, abilities {str..cha} (base scores BEFORE racial modifiers),
##   racialChoice (ability getting the flexible +2), abilityIncreases [ability ids from levels 4, 8...],
##   skillRanks {skill_id: ranks}, feats ["toughness", "weapon_focus:longsword"], spells [spell ids],
##   equipped {mainHand, offHand, armor, ranged, accessory}, hpRolls [hit die result per level],
##   hp (current), xp, effects [...], used {slots: {"1": n}, pools: {"channel": n}}, look {...}, bio
##
## derive(character, db) returns the STATS Dictionary every other system reads (same shape for monsters,
## see monster_rules.gd):
##   kind, name, level, hd, size, tags, immunities, abilities {id: {score, mod}}, hpMax,
##   ac, touch, flatFooted, acParts, bab, cmb, cmd, init, initParts, speed, squares,
##   saves {fort|ref|will: {total, parts}}, skills {id: {total, parts, ranks, usable, classSkill}},
##   attacks [{id, name, bonus, parts, damage, critRange, critMult, dtype, ranged, range, touch, targets}],
##   sneakDice, dr, casting {ability, mod, casterLevel, slots {"1": n}, known [ids], classId} or null,
##   pools {id: max uses}, classAbilities [spell ids], mods [all modifiers]

const ABILITIES := ["str", "dex", "con", "int", "wis", "cha"]
const ABILITY_NAMES := {"str": "Strength", "dex": "Dexterity", "con": "Constitution", "int": "Intelligence", "wis": "Wisdom", "cha": "Charisma"}
const ABILITY_SHORT := {"str": "Str", "dex": "Dex", "con": "Con", "int": "Int", "wis": "Wis", "cha": "Cha"}
const POINT_BUY_COST := {7: -4, 8: -2, 9: -1, 10: 0, 11: 1, 12: 2, 13: 3, 14: 5, 15: 7, 16: 10, 17: 13, 18: 17}
const POINT_BUY_BUDGET := 15
const SMALL_DAMAGE := {"1d2": "1", "1d3": "1d2", "1d4": "1d3", "1d6": "1d4", "1d8": "1d6", "1d10": "1d8", "1d12": "1d10", "2d4": "1d6", "2d6": "1d10", "2d8": "2d6"}
const SAVE_ABILITY := {"fort": "con", "ref": "dex", "will": "wis"}
const SAVE_NAMES := {"fort": "Fortitude", "ref": "Reflex", "will": "Will"}


static func ability_mod(score: int) -> int:
	return floori((score - 10) / 2.0)


static func bab_for(progression: String, level: int) -> int:
	match progression:
		"full":
			return level
		"medium":
			return floori(level * 0.75)
	return floori(level / 2.0)


static func base_save(good: bool, level: int) -> int:
	return 2 + floori(level / 2.0) if good else floori(level / 3.0)


static func bonus_spells(mod: int, spell_level: int) -> int:
	if spell_level <= 0 or mod < spell_level:
		return 0
	return floori((mod - spell_level) / 4.0) + 1


## "weapon_focus:longsword" -> {id: "weapon_focus", param: "longsword"}
static func parse_feat(f) -> Dictionary:
	var bits: PackedStringArray = str(f).split(":")
	return {"id": bits[0], "param": bits[1] if bits.size() > 1 else ""}


static func has_feat(c: Dictionary, feat_id: String) -> bool:
	for f in c.get("feats", []):
		if parse_feat(f).id == feat_id:
			return true
	return false


static func point_buy_total(abilities: Dictionary) -> int:
	var total := 0
	for a in ABILITIES:
		total += int(POINT_BUY_COST.get(int(abilities.get(a, 10)), 99))
	return total


## Builds a new level-1 (or higher) character from a spec (builder output or a companion definition).
static func create(spec: Dictionary, db: Dictionary) -> Dictionary:
	var cls: Dictionary = db.classes[spec.cls]
	var c := {
		"id": spec.get("id", "pc"), "name": spec.get("name", "Hero"), "race": spec.race, "cls": spec.cls, "level": 1,
		"abilities": spec.get("abilities", {}).duplicate(), "racialChoice": spec.get("racialChoice", ""), "abilityIncreases": [],
		"skillRanks": spec.get("skillRanks", {}).duplicate(), "feats": spec.get("feats", []).duplicate(),
		"spells": spec.get("spells", []).duplicate(),
		"equipped": {"mainHand": null, "offHand": null, "armor": null, "ranged": null, "accessory": null},
		"hpRolls": [int(cls.hitDie)], "hp": 1, "xp": 0, "effects": [], "used": {"slots": {}, "pools": {}},
		"look": spec.get("look", {}).duplicate(true), "bio": spec.get("bio", ""), "voice": spec.get("voice", ""),
	}
	for a in ABILITIES:
		if not c.abilities.has(a):
			c.abilities[a] = 10
	var kit: Dictionary = spec.get("equipped", cls.get("startingKit", {}).get("equipped", {}))
	for slot in kit:
		c.equipped[slot] = kit[slot]
	var target_level: int = spec.get("level", 1)
	while int(c.level) < target_level:
		c.level = int(c.level) + 1
		c.hpRolls.append(int(cls.hitDie) / 2 + 1)
	c.xp = Progression.XP_TABLE[int(c.level) - 1]
	c.hp = derive(c, db).hpMax
	return c


## Every always-on and situational modifier that applies to this character.
static func collect_mods(c: Dictionary, db: Dictionary) -> Array:
	var out: Array = []
	var level: int = c.get("level", 1)
	var race: Dictionary = db.races.get(c.race, {})
	_push(out, race.get("name", ""), race.get("modifiers", []), level, "")
	for f in c.get("feats", []):
		var pf := parse_feat(f)
		var feat: Dictionary = db.feats.get(pf.id, {})
		_push(out, feat.get("name", pf.id), feat.get("modifiers", []), level, pf.param)
	var cls: Dictionary = db.classes.get(c.cls, {})
	for feature in cls.get("features", []):
		if int(feature.get("level", 1)) <= level:
			_push(out, feature.get("name", ""), feature.get("modifiers", []), level, "")
	var eq: Dictionary = c.get("equipped", {})
	for slot in eq:
		var item = _item(db, eq[slot])
		if item != null:
			_push(out, item.get("name", ""), item.get("modifiers", []), level, "")
	out.append_array(Effects.mods(c, db))
	return out


static func _push(out: Array, label: String, mods: Array, level: int, param: String) -> void:
	for m in mods:
		var target: String = m.target
		if param != "":
			target = target.replace("$param", param)
		var e := {"target": target, "value": Mods.scaled_value(m, level), "type": m.get("type", "untyped"), "label": m.get("label", label)}
		if m.has("when"):
			e["when"] = m.when
		out.append(e)


static func _item(db: Dictionary, item_id):
	if item_id == null or str(item_id) == "":
		return null
	return db.items.get(item_id)


static func derive(c: Dictionary, db: Dictionary) -> Dictionary:
	var race: Dictionary = db.races[c.race]
	var cls: Dictionary = db.classes[c.cls]
	var level: int = c.level
	var mods := collect_mods(c, db)
	var s := {
		"kind": "pc", "name": c.name, "level": level, "hd": level, "size": race.get("size", "medium"),
		"tags": ["humanoid", "living"], "immunities": race.get("immunities", []).duplicate(), "mods": mods, "dr": null,
	}

	# --- ability scores ---
	var ab := {}
	for a in ABILITIES:
		var score: int = int(c.abilities.get(a, 10)) + int(race.get("abilityMods", {}).get(a, 0))
		if race.get("flexibleBonus", false) and c.get("racialChoice", "") == a:
			score += 2
		score += c.get("abilityIncreases", []).count(a)
		score += Mods.total(mods, ["ability." + a])
		ab[a] = {"score": score, "mod": ability_mod(score)}
	s["abilities"] = ab
	var small: bool = s.size == "small"
	var bab := bab_for(cls.bab, level)
	s["bab"] = bab

	# --- equipment ---
	var eq: Dictionary = c.get("equipped", {})
	var armor = _item(db, eq.get("armor"))
	var main = _item(db, eq.get("mainHand"))
	var off = _item(db, eq.get("offHand"))
	var ranged = _item(db, eq.get("ranged"))
	var shield = null
	if off != null and off.get("type", "") == "shield" and not (main != null and int(main.get("hands", 1)) == 2):
		shield = off
	var training := 0
	for lv in cls.get("armorTrainingLevels", []):
		if int(lv) <= level:
			training += 1
	var acp := 0
	var max_dex := 99
	var nonprof := 0
	var prof: Array = cls.get("armorProf", [])
	if armor != null:
		var a_acp: int = mini(0, int(armor.get("acp", 0)) + training)
		acp += a_acp
		max_dex = int(armor.get("maxDex", 99)) + training
		if not (armor.get("armorClass", "light") in prof):
			nonprof += a_acp
	if shield != null:
		acp += int(shield.get("acp", 0))
		if not ("shield" in prof):
			nonprof += int(shield.get("acp", 0))
	s["acp"] = acp

	# --- hit points ---
	var hp := 0
	for r in c.get("hpRolls", []):
		hp += int(r)
	hp += ab.con.mod * level + Mods.total(mods, ["hp"])
	s["hpMax"] = maxi(level, hp)

	# --- armor class ---
	var ac_mods: Array = []
	if armor != null:
		ac_mods.append({"type": "armor", "value": int(armor.get("ac", 0)) + int(armor.get("enhancement", 0)), "label": armor.name})
	if shield != null:
		ac_mods.append({"type": "shield", "value": int(shield.get("ac", 0)) + int(shield.get("enhancement", 0)), "label": shield.name})
	ac_mods.append({"type": "dex", "value": mini(ab.dex.mod, max_dex), "label": "Dex"})
	if small:
		ac_mods.append({"type": "size", "value": 1, "label": "Size"})
	ac_mods.append_array(Mods.pick(mods, ["ac"]))
	var ac_all := Mods.stack(ac_mods)
	s["ac"] = 10 + ac_all.total
	s["acParts"] = ac_all.parts
	s["touch"] = 10 + Mods.stack(ac_mods.filter(func(m): return not (m.type in ["armor", "shield", "natural"]))).total
	s["flatFooted"] = 10 + Mods.stack(ac_mods.filter(func(m): return m.type != "dodge" and not (m.type == "dex" and m.value > 0))).total

	# --- saves ---
	var saves := {}
	for sv in ["fort", "ref", "will"]:
		var parts: Array = [
			{"label": "Base", "value": base_save(sv in cls.get("goodSaves", []), level)},
			{"label": ABILITY_SHORT[SAVE_ABILITY[sv]], "value": ab[SAVE_ABILITY[sv]].mod},
		]
		parts.append_array(Mods.stack(Mods.pick(mods, ["save", "save." + sv])).parts)
		saves[sv] = {"total": Util.sum_parts(parts), "parts": parts}
	s["saves"] = saves

	# --- initiative, manoeuvres, speed ---
	var init_parts: Array = [{"label": "Dex", "value": ab.dex.mod}]
	init_parts.append_array(Mods.stack(Mods.pick(mods, ["init"])).parts)
	s["init"] = Util.sum_parts(init_parts)
	s["initParts"] = init_parts
	var size_cm := -1 if small else 0
	s["cmb"] = bab + ab.str.mod + size_cm + Mods.total(mods, ["cmb"])
	s["cmd"] = 10 + bab + ab.str.mod + ab.dex.mod + size_cm + Mods.total(mods, ["cmd"])
	var speed: int = race.get("speed", 30)
	if armor != null and armor.get("armorClass", "light") in ["medium", "heavy"] and not race.get("steadySpeed", false):
		speed = 20 if speed >= 30 else 15
	speed += Mods.total(mods, ["speed"])
	s["speed"] = speed
	s["squares"] = maxi(1, floori(speed / 5.0))

	# --- skills ---
	var skills := {}
	var class_skills: Array = cls.get("classSkills", [])
	for sid in db.skills:
		var sk: Dictionary = db.skills[sid]
		var ranks: int = c.get("skillRanks", {}).get(sid, 0)
		var parts: Array = []
		if ranks > 0:
			parts.append({"label": "Ranks", "value": ranks})
		parts.append({"label": ABILITY_SHORT[sk.ability], "value": ab[sk.ability].mod})
		var is_class: bool = sid in class_skills
		if is_class and ranks > 0:
			parts.append({"label": "Class skill", "value": 3})
		if sk.get("acp", false) and acp != 0:
			parts.append({"label": "Armor", "value": acp})
		if small and sid == "stealth":
			parts.append({"label": "Size", "value": 4})
		parts.append_array(Mods.stack(Mods.pick(mods, ["skill", "skill." + sid])).parts)
		skills[sid] = {
			"total": Util.sum_parts(parts), "parts": parts, "ranks": ranks, "classSkill": is_class,
			"usable": ranks > 0 or not sk.get("trained", false),
		}
	s["skills"] = skills

	# --- attacks ---
	var attacks: Array = []
	if main != null and main.get("type", "") == "weapon":
		attacks.append(_weapon_attack(c, db, s, main, mods, nonprof))
	else:
		attacks.append(_weapon_attack(c, db, s, {"id": "unarmed", "name": "Unarmed strike", "category": "simple", "damage": "1d3", "crit": [20, 2], "dtype": "B", "light": true}, mods, nonprof))
	if ranged != null and ranged.get("type", "") == "weapon":
		attacks.append(_weapon_attack(c, db, s, ranged, mods, nonprof))
	s["attacks"] = attacks

	# --- class features with numbers ---
	s["sneakDice"] = 0
	if cls.has("sneakAttack"):
		s["sneakDice"] = Mods.scaled_value({"scale": cls.sneakAttack}, level)
	var pools := {}
	for pid in cls.get("pools", {}):
		var pool: Dictionary = cls.pools[pid]
		pools[pid] = maxi(0, int(pool.get("base", 0)) + (ab[pool.ability].mod if pool.has("ability") else 0))
	s["pools"] = pools
	s["classAbilities"] = cls.get("classAbilities", []).duplicate()

	# --- spellcasting ---
	s["casting"] = null
	if cls.has("casting"):
		var cast: Dictionary = cls.casting
		var cmod: int = ab[cast.ability].mod
		var table: Array = cast.slots
		var row: Array = table[mini(level, table.size()) - 1]
		var slots := {}
		for sl in range(1, row.size()):
			if int(ab[cast.ability].score) < 10 + sl:
				continue
			slots[str(sl)] = int(row[sl]) + (1 if cast.get("domainSlot", false) else 0) + bonus_spells(cmod, sl)
		var known: Array = []
		if cast.get("knowsAll", false):
			for spid in db.spells:
				var lv = db.spells[spid].get("levels", {}).get(c.cls)
				if lv != null and (int(lv) == 0 or slots.has(str(lv))):
					known.append(spid)
		else:
			for spid in c.get("spells", []):
				if not db.spells.has(spid):
					continue
				var lv = db.spells[spid].get("levels", {}).get(c.cls)
				if lv != null and (int(lv) == 0 or slots.has(str(lv))):
					known.append(spid)
		s["casting"] = {"ability": cast.ability, "mod": cmod, "casterLevel": level, "slots": slots, "known": known, "classId": c.cls}
	return s


static func weapon_proficient(c: Dictionary, db: Dictionary, item: Dictionary) -> bool:
	var prof: Array = db.classes[c.cls].get("weaponProf", []) + db.races[c.race].get("weaponProf", [])
	return item.get("category", "simple") in prof or item.get("id", "") in prof


static func _weapon_attack(c: Dictionary, db: Dictionary, s: Dictionary, item: Dictionary, mods: Array, nonprof: int) -> Dictionary:
	var ab: Dictionary = s.abilities
	var is_ranged: bool = item.get("ranged", false)
	var two_handed: bool = int(item.get("hands", 1)) == 2
	var finesse: bool = has_feat(c, "weapon_finesse") and (item.get("finesse", false) or item.get("light", false))
	var use_dex: bool = is_ranged or (finesse and int(ab.dex.mod) > int(ab.str.mod))
	var parts: Array = [{"label": "BAB", "value": s.bab}]
	parts.append({"label": "Dex" if use_dex else "Str", "value": ab.dex.mod if use_dex else ab.str.mod})
	if s.size == "small":
		parts.append({"label": "Size", "value": 1})
	var enh: int = item.get("enhancement", 0)
	if enh != 0:
		parts.append({"label": "Enhancement", "value": enh})
	if not weapon_proficient(c, db, item):
		parts.append({"label": "Not proficient", "value": -4})
	if nonprof != 0:
		parts.append({"label": "Armor (not proficient)", "value": nonprof})
	var kind := "ranged" if is_ranged else "melee"
	var targets := ["attack", "attack." + kind, "attack.weapon." + str(item.id)]
	parts.append_array(Mods.stack(Mods.pick(mods, targets)).parts)

	var dice: String = item.get("damage", "1d3")
	if s.size == "small":
		dice = SMALL_DAMAGE.get(dice, dice)
	var dmg := 0
	if not is_ranged or item.get("strDamage", false):
		var sm: int = ab.str.mod
		dmg = floori(sm * 1.5) if (two_handed and sm > 0) else sm
	var dmg_targets := ["damage", "damage." + kind, "damage.weapon." + str(item.id)]
	dmg += enh + Mods.total(mods, dmg_targets)
	var crit: Array = item.get("crit", [20, 2])
	return {
		"id": item.id, "name": item.name, "bonus": Util.sum_parts(parts), "parts": parts,
		"damage": Dice.add_flat(dice, dmg), "critRange": int(crit[0]), "critMult": int(crit[1]),
		"dtype": item.get("dtype", "B"), "ranged": is_ranged, "range": int(item.get("range", 0)),
		"touch": false, "targets": targets, "damageTargets": dmg_targets,
	}


## Checks a builder spec. Returns a list of human-readable problems (empty = valid).
static func validate_build(spec: Dictionary, db: Dictionary) -> Array:
	var errors: Array = []
	if str(spec.get("name", "")).strip_edges() == "":
		errors.append("Give your character a name.")
	if not db.races.has(spec.get("race", "")):
		errors.append("Choose a race.")
	if not db.classes.has(spec.get("cls", "")):
		errors.append("Choose a class.")
	if not errors.is_empty():
		return errors
	var race: Dictionary = db.races[spec.race]
	var cls: Dictionary = db.classes[spec.cls]
	var spent := point_buy_total(spec.get("abilities", {}))
	if spent > POINT_BUY_BUDGET:
		errors.append("Ability scores cost %d points (budget %d)." % [spent, POINT_BUY_BUDGET])
	if race.get("flexibleBonus", false) and not (spec.get("racialChoice", "") in ABILITIES):
		errors.append("Choose which ability gets your +2 racial bonus.")
	var req := Progression.requirements_at_level_one(spec, db)
	var ranks := 0
	for sid in spec.get("skillRanks", {}):
		var r: int = spec.skillRanks[sid]
		if r > 1:
			errors.append("At level 1 a skill can have at most 1 rank (%s)." % sid)
		ranks += r
	if ranks > int(req.skillPoints):
		errors.append("Too many skill ranks: %d of %d." % [ranks, req.skillPoints])
	if spec.get("feats", []).size() > int(req.feats):
		errors.append("Too many feats: %d of %d." % [spec.feats.size(), req.feats])
	return errors
