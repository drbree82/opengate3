class_name Progression
extends RefCounted
## Experience and levelling (Pathfinder 1e, medium advancement track). Pure logic.

## XP needed to BE each level: XP_TABLE[level - 1].
const XP_TABLE := [0, 2000, 5000, 9000, 15000, 23000, 35000, 51000, 75000, 105000, 155000, 220000, 315000, 445000, 635000, 890000, 1300000, 1800000, 2550000, 3600000]
const MAX_LEVEL := 20


static func level_for_xp(xp: int) -> int:
	var level := 1
	for i in XP_TABLE.size():
		if xp >= int(XP_TABLE[i]):
			level = i + 1
	return level


static func xp_for_next(level: int) -> int:
	return int(XP_TABLE[mini(level, MAX_LEVEL - 1)])


static func can_level_up(c: Dictionary) -> bool:
	return int(c.level) < MAX_LEVEL and int(c.xp) >= xp_for_next(int(c.level))


static func skill_points_per_level(c_or_spec: Dictionary, db: Dictionary, int_mod: int) -> int:
	var cls: Dictionary = db.classes[c_or_spec.cls]
	var race: Dictionary = db.races[c_or_spec.race]
	return maxi(1, int(cls.skillRanks) + int_mod) + (1 if race.get("bonusSkillRank", false) else 0)


## What a brand-new level 1 character may pick (used by the character builder).
static func requirements_at_level_one(spec: Dictionary, db: Dictionary) -> Dictionary:
	var race: Dictionary = db.races[spec.race]
	var cls: Dictionary = db.classes[spec.cls]
	var int_score: int = int(spec.get("abilities", {}).get("int", 10)) + int(race.get("abilityMods", {}).get("int", 0))
	if race.get("flexibleBonus", false) and spec.get("racialChoice", "") == "int":
		int_score += 2
	var feats := 1 + (1 if race.get("bonusFeat", false) else 0) + (1 if 1 in cls.get("bonusFeatLevels", []) else 0)
	var spells := 0
	if cls.has("spellbook"):
		spells = int(cls.spellbook.get("level1", 3)) + maxi(0, CharRules.ability_mod(int_score))
	return {"skillPoints": skill_points_per_level(spec, db, CharRules.ability_mod(int_score)), "feats": feats, "spells": spells}


## What the character gains when going from its current level to the next one.
static func requirements(c: Dictionary, db: Dictionary) -> Dictionary:
	var cls: Dictionary = db.classes[c.cls]
	var stats := CharRules.derive(c, db)
	var new_level: int = int(c.level) + 1
	var feats := 0
	if new_level % 2 == 1:
		feats += 1
	if new_level in cls.get("bonusFeatLevels", []):
		feats += 1
	return {
		"newLevel": new_level, "hitDie": int(cls.hitDie),
		"skillPoints": skill_points_per_level(c, db, int(stats.abilities.int.mod)),
		"feats": feats, "abilityIncrease": new_level % 4 == 0,
		"spells": int(cls.get("spellbook", {}).get("perLevel", 0)) if cls.has("spellbook") else 0,
	}


## Applies a level-up. choices = {skillRanks: {id: +n}, feats: [...], ability: "str", spells: [...], hpRoll: int}
## When hpRoll is missing the hit die is rolled with `rng` (or the average is used when rng is null).
## Returns {level, hpGained}.
static func level_up(c: Dictionary, db: Dictionary, choices: Dictionary = {}, rng: Rng = null) -> Dictionary:
	var req := requirements(c, db)
	var roll: int = choices.get("hpRoll", 0)
	if roll <= 0:
		roll = rng.die(int(req.hitDie)) if rng != null else int(req.hitDie) / 2 + 1
	var before: int = CharRules.derive(c, db).hpMax
	c.level = req.newLevel
	c.hpRolls.append(roll)
	for sid in choices.get("skillRanks", {}):
		c.skillRanks[sid] = mini(int(c.level), int(c.skillRanks.get(sid, 0)) + int(choices.skillRanks[sid]))
	for f in choices.get("feats", []):
		if not (f in c.feats):
			c.feats.append(f)
	if req.abilityIncrease and choices.get("ability", "") in CharRules.ABILITIES:
		c.abilityIncreases.append(choices.ability)
	for sp in choices.get("spells", []):
		if not (sp in c.spells):
			c.spells.append(sp)
	var gained: int = CharRules.derive(c, db).hpMax - before
	c.hp = int(c.hp) + maxi(0, gained)
	return {"level": c.level, "hpGained": gained}


## Feat prerequisites: {bab: n, ability: {dex: 13}, feats: ["dodge"], caster: true, cls: "fighter"}
static func feat_available(c_or_spec: Dictionary, feat: Dictionary, db: Dictionary, stats = null) -> bool:
	var pre: Dictionary = feat.get("prereq", {})
	if pre.is_empty():
		return true
	if stats == null:
		return true
	if int(stats.bab) < int(pre.get("bab", 0)):
		return false
	for a in pre.get("ability", {}):
		if int(stats.abilities[a].score) < int(pre.ability[a]):
			return false
	for f in pre.get("feats", []):
		if not CharRules.has_feat(c_or_spec, f):
			return false
	if pre.get("caster", false) and stats.get("casting") == null:
		return false
	return true
