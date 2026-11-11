class_name MonsterRules
extends RefCounted
## Monsters use ready-made stat blocks (data/monsters.json + campaign monsters.json) instead of
## class/race maths. derive() converts a block into the same STATS shape as CharRules.derive().
##
## A MONSTER ACTOR is: {monsterId, name, hp, hpMax, effects: [], used: {slots, pools, spells}}


static func create_actor(monster_id: String, db: Dictionary, rng: Rng = null) -> Dictionary:
	var b: Dictionary = db.monsters[monster_id]
	var hp: int = 1
	if typeof(b.hp) == TYPE_STRING:
		hp = Dice.roll(b.hp, rng).total if rng != null else Dice.average(b.hp)
	else:
		hp = int(b.hp)
	hp = maxi(1, hp)
	return {"monsterId": monster_id, "name": b.name, "hp": hp, "hpMax": hp, "effects": [], "used": {"slots": {}, "pools": {}, "spells": {}}}


static func derive(a: Dictionary, db: Dictionary) -> Dictionary:
	var b: Dictionary = db.monsters[a.monsterId]
	var mods := Effects.mods(a, db)
	var ab := {}
	for id in CharRules.ABILITIES:
		var score: int = int(b.get("abilities", {}).get(id, 10)) + Mods.total(mods, ["ability." + id])
		ab[id] = {"score": score, "mod": CharRules.ability_mod(score)}
	var ac_bonus := Mods.total(mods, ["ac"])
	var s := {
		"kind": "monster", "name": a.get("name", b.name), "level": int(b.get("hd", 1)), "hd": int(b.get("hd", 1)),
		"size": b.get("size", "medium"), "tags": b.get("tags", []).duplicate(), "immunities": b.get("immunities", []).duplicate(),
		"mods": mods, "abilities": ab, "hpMax": int(a.get("hpMax", a.hp)),
		"ac": int(b.ac) + ac_bonus, "touch": int(b.get("touch", b.ac)) + ac_bonus, "flatFooted": int(b.get("flatFooted", b.ac)) + ac_bonus,
		"acParts": [{"label": "Stat block", "value": int(b.ac) - 10}],
		"bab": int(b.get("bab", 0)), "cmb": int(b.get("cmb", 0)), "cmd": int(b.get("cmd", 10)),
		"init": int(b.get("init", 0)) + Mods.total(mods, ["init"]), "initParts": [{"label": "Init", "value": int(b.get("init", 0))}],
		"speed": int(b.get("speed", 30)), "squares": maxi(1, floori(int(b.get("speed", 30)) / 5.0)),
		"dr": b.get("dr"), "sneakDice": int(b.get("sneakDice", 0)), "pools": {}, "classAbilities": [], "acp": 0,
		"xp": int(b.get("xp", 0)),
	}
	var saves := {}
	for sv in ["fort", "ref", "will"]:
		var parts: Array = [{"label": "Base", "value": int(b.get("saves", {}).get(sv, 0))}]
		parts.append_array(Mods.stack(Mods.pick(mods, ["save", "save." + sv])).parts)
		saves[sv] = {"total": Util.sum_parts(parts), "parts": parts}
	s["saves"] = saves
	var skills := {}
	for sid in db.skills:
		var base = b.get("skills", {}).get(sid)
		var parts: Array = [{"label": "Base", "value": int(base) if base != null else int(ab[db.skills[sid].ability].mod)}]
		parts.append_array(Mods.stack(Mods.pick(mods, ["skill", "skill." + sid])).parts)
		skills[sid] = {"total": Util.sum_parts(parts), "parts": parts, "ranks": 0, "classSkill": false, "usable": true}
	s["skills"] = skills
	var attacks: Array = []
	for atk in b.get("attacks", []):
		var is_ranged: bool = atk.get("ranged", false)
		var kind := "ranged" if is_ranged else "melee"
		var targets := ["attack", "attack." + kind]
		var parts: Array = [{"label": "Attack", "value": int(atk.get("bonus", 0))}]
		parts.append_array(Mods.stack(Mods.pick(mods, targets)).parts)
		var crit: Array = atk.get("crit", [20, 2])
		var dmg_targets := ["damage", "damage." + kind]
		attacks.append({
			"id": atk.get("id", atk.name), "name": atk.name, "bonus": Util.sum_parts(parts), "parts": parts,
			"damage": Dice.add_flat(atk.get("damage", "1d4"), Mods.total(mods, dmg_targets)),
			"critRange": int(crit[0]), "critMult": int(crit[1]), "dtype": atk.get("dtype", "B"),
			"ranged": is_ranged, "range": int(atk.get("range", 0)), "touch": atk.get("touch", false),
			"targets": targets, "damageTargets": dmg_targets,
		})
	s["attacks"] = attacks
	s["casting"] = null
	if b.has("spells"):
		var known: Array = []
		for sp in b.spells:
			known.append(sp.id)
		var cab: String = b.get("castingAbility", "int")
		s["casting"] = {"ability": cab, "mod": ab[cab].mod, "casterLevel": int(b.get("casterLevel", b.get("hd", 1))), "slots": {}, "known": known, "classId": ""}
	return s
