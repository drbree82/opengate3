extends RefCounted
## Tests for the Pathfinder rules in src/rules/. The four test characters match the companions of the
## starter campaign, so these numbers double as a regression check for campaign balance.

var db: Dictionary = RulesDB.load_base()


func _kaelen() -> Dictionary:
	return CharRules.create({
		"id": "kaelen", "name": "Kaelen", "race": "human", "cls": "fighter", "racialChoice": "str",
		"abilities": {"str": 15, "dex": 13, "con": 14, "int": 10, "wis": 12, "cha": 8},
		"feats": ["weapon_focus:longsword", "dodge", "toughness"],
		"skillRanks": {"intimidate": 1, "climb": 1, "perception": 1},
	}, db)


func _pip() -> Dictionary:
	return CharRules.create({
		"id": "pip", "name": "Pip", "race": "halfling", "cls": "rogue",
		"abilities": {"str": 10, "dex": 16, "con": 12, "int": 13, "wis": 10, "cha": 10},
		"feats": ["weapon_finesse"],
		"skillRanks": {"stealth": 1, "perception": 1, "disable_device": 1},
	}, db)


func _brunhild() -> Dictionary:
	return CharRules.create({
		"id": "brunhild", "name": "Brunhild", "race": "dwarf", "cls": "cleric",
		"abilities": {"str": 13, "dex": 11, "con": 12, "int": 10, "wis": 15, "cha": 12},
		"feats": ["toughness"], "skillRanks": {"heal": 1, "knowledge_religion": 1},
	}, db)


func _thessaly() -> Dictionary:
	return CharRules.create({
		"id": "thessaly", "name": "Thessaly", "race": "elf", "cls": "wizard",
		"abilities": {"str": 8, "dex": 14, "con": 12, "int": 16, "wis": 10, "cha": 10},
		"feats": ["toughness"], "skillRanks": {"knowledge_arcana": 1, "spellcraft": 1},
		"spells": ["acid_splash", "ray_of_frost", "daze", "magic_missile", "burning_hands", "sleep", "mage_armor"],
	}, db)


func test_basics(t) -> void:
	t.eq(CharRules.ability_mod(10), 0, "mod 10")
	t.eq(CharRules.ability_mod(18), 4, "mod 18")
	t.eq(CharRules.ability_mod(7), -2, "mod 7 rounds down")
	t.eq(CharRules.bab_for("medium", 3), 2, "3/4 BAB at level 3")
	t.eq(CharRules.base_save(true, 1), 2, "good save level 1")
	t.eq(CharRules.base_save(false, 3), 1, "poor save level 3")
	t.eq(CharRules.bonus_spells(4, 1), 1, "bonus 1st-level spell with +4")
	t.eq(CharRules.point_buy_total({"str": 15, "dex": 13, "con": 14, "int": 10, "wis": 12, "cha": 8}), 15, "15 point buy")


func test_stacking(t) -> void:
	var st := Mods.stack([
		{"type": "armor", "value": 2, "label": "Leather"}, {"type": "armor", "value": 4, "label": "Mage Armor"},
		{"type": "dodge", "value": 1}, {"type": "dodge", "value": 1}, {"value": -2},
	])
	t.eq(st.total, 4, "armor does not stack, dodge does, penalties apply")


func test_fighter(t) -> void:
	var c := _kaelen()
	var s := CharRules.derive(c, db)
	t.eq(s.abilities.str.score, 17, "human +2 Str")
	t.eq(s.hpMax, 15, "10 + Con 2 + Toughness 3")
	t.eq(c.hp, 15, "starts at full hp")
	t.eq(s.ac, 19, "AC: scale 5 + shield 2 + Dex 1 + dodge 1")
	t.eq(s.touch, 12, "touch AC")
	t.eq(s.flatFooted, 17, "flat-footed AC")
	t.eq(s.attacks[0].bonus, 5, "longsword: BAB 1 + Str 3 + focus 1")
	t.eq(s.attacks[0].damage, "1d8+3", "longsword damage")
	t.eq(s.attacks[1].bonus, 2, "shortbow: BAB 1 + Dex 1")
	t.eq(s.saves.fort.total, 4, "Fort")
	t.eq(s.saves.will.total, 1, "Will")
	t.eq(s.speed, 20, "medium armor slows to 20 ft")
	t.eq(s.skills.intimidate.total, 3, "Intimidate: rank 1 + class 3 + Cha -1")
	t.eq(s.skills.climb.total, 1, "Climb: 1 + 3 + Str 3 + armor check -6")


func test_rogue(t) -> void:
	var s := CharRules.derive(_pip(), db)
	t.eq(s.abilities.dex.score, 18, "halfling +2 Dex")
	t.eq(s.ac, 17, "AC: leather 2 + Dex 4 + size 1")
	t.eq(s.attacks[0].bonus, 5, "finesse short sword: Dex 4 + size 1")
	t.eq(s.attacks[0].damage, "1d4-1", "small short sword, Str 8")
	t.eq(s.skills.stealth.total, 12, "Stealth: 1 + Dex 4 + class 3 + size 4")
	t.eq(s.skills.perception.total, 6, "Perception: 1 + class 3 + racial 2")
	t.eq(s.skills.disable_device.total, 9, "Disable Device: 1 + Dex 4 + class 3 + trapfinding 1")
	t.eq(s.saves.ref.total, 7, "Reflex: 2 + Dex 4 + luck 1")
	t.eq(s.sneakDice, 1, "sneak attack 1d6")
	t.eq(s.squares, 4, "20 ft = 4 squares")


func test_cleric(t) -> void:
	var s := CharRules.derive(_brunhild(), db)
	t.eq(s.abilities.wis.score, 17, "dwarf +2 Wis")
	t.eq(s.hpMax, 13, "8 + Con 2 + Toughness 3")
	t.eq(s.ac, 17, "scale + shield")
	t.eq(s.speed, 20, "dwarves keep 20 ft in armor")
	t.eq(s.saves.will.total, 5, "Will")
	t.eq(s.casting.slots["1"], 3, "1 + domain 1 + bonus 1")
	t.eq(s.pools.channel, 3, "channel energy uses")
	t.ok("cure_light_wounds" in s.casting.known, "clerics know their whole list")
	t.ok(not ("cure_moderate_wounds" in s.casting.known), "no 2nd-level spells at level 1")


func test_wizard(t) -> void:
	var c := _thessaly()
	var s := CharRules.derive(c, db)
	t.eq(s.abilities.int.score, 18, "elf +2 Int")
	t.eq(s.hpMax, 9, "6 + Toughness 3")
	t.eq(s.ac, 13, "Dex only")
	t.eq(s.attacks[0].damage, "1d6-1", "staff with Str 8")
	t.eq(s.casting.slots["1"], 2, "1 + bonus 1")
	t.ok("mind" not in s.immunities and "sleep" in s.immunities, "elves are immune to sleep")
	Effects.add(c, SpellRules.build_effect(db.spells.mage_armor, 1))
	var buffed := CharRules.derive(c, db)
	t.eq(buffed.ac, 17, "mage armor +4")
	t.eq(buffed.touch, 13, "armor bonus does not help touch AC")


func test_checks(t) -> void:
	var s := CharRules.derive(_pip(), db)
	var r := Checks.skill(s, "perception", 15, Rng.fixed([9]), db)
	t.eq(r.total, 15, "9 + 6")
	t.ok(r.success, "meets DC")
	var untrained := Checks.skill(CharRules.derive(_kaelen(), db), "disable_device", 10, Rng.fixed([20]), db)
	t.ok(not untrained.success, "trained-only skill without ranks fails automatically")
	var sv := Checks.save(s, "will", 30, Rng.fixed([20]))
	t.ok(sv.success, "natural 20 always saves")
	var traps := Checks.skill(s, "perception", 10, Rng.fixed([1]), db, ["traps"])
	t.eq(traps.total, 8, "trapfinding adds +1 against traps: 1 + 6 + 1")


func test_attacks(t) -> void:
	var att := CharRules.derive(_kaelen(), db)
	var gob := MonsterRules.derive(MonsterRules.create_actor("goblin", db), db)
	var hit := CombatRules.resolve_attack(att, att.attacks[0], gob, {}, Rng.fixed([15, 5]))
	t.ok(hit.hit, "15 + 5 hits AC 16")
	t.eq(hit.damage, 8, "1d8(5) + 3")
	var miss := CombatRules.resolve_attack(att, att.attacks[0], gob, {}, Rng.fixed([1]))
	t.ok(not miss.hit and miss.fumble, "natural 1 always misses")
	var crit := CombatRules.resolve_attack(att, att.attacks[0], gob, {}, Rng.fixed([19, 12, 4, 6]))
	t.ok(crit.crit, "19 threatens, 12 + 5 confirms")
	t.eq(crit.damage, 16, "crit: (4 + 3) + (6 + 3)")
	t.eq(crit.rolls.size(), 3, "attack, confirm, damage rolls")
	var skel := MonsterRules.derive(MonsterRules.create_actor("skeleton", db), db)
	var slash := CombatRules.resolve_attack(att, att.attacks[0], skel, {}, Rng.fixed([15, 5]))
	t.eq(slash.damage, 3, "DR 5/bludgeoning absorbs slashing")
	var mace := CharRules.derive(_brunhild(), db)
	var bash := CombatRules.resolve_attack(mace, mace.attacks[0], skel, {}, Rng.fixed([18, 5]))
	t.eq(bash.damage, 6, "bludgeoning bypasses the DR")
	var rogue := CharRules.derive(_pip(), db)
	var sneak := CombatRules.resolve_attack(rogue, rogue.attacks[0], gob, {"sneak_dice": 1, "flat_footed": true}, Rng.fixed([10, 4, 6]))
	t.eq(sneak.ac, 14, "flat-footed AC used")
	t.eq(sneak.damage, 9, "1d4(4) - 1 + sneak 6")


func test_damage_and_dying(t) -> void:
	var c := _thessaly()
	var s := CharRules.derive(c, db)
	t.eq(CombatRules.apply_damage(c, s, 5), "ok", "still up")
	t.eq(CombatRules.apply_damage(c, s, 6), "down", "below 0 = down")
	t.eq(CombatRules.heal(c, s, 100), 11, "healing caps at max hp")
	t.eq(CombatRules.apply_damage(c, s, 30), "dead", "past negative Con = dead")
	var m := MonsterRules.create_actor("goblin", db)
	t.eq(CombatRules.apply_damage(m, MonsterRules.derive(m, db), 6), "dead", "monsters die at 0")


func test_spells(t) -> void:
	var caster := CharRules.derive(_thessaly(), db)
	var gob := MonsterRules.derive(MonsterRules.create_actor("goblin", db), db)
	var mm := SpellRules.resolve_on_target(caster, db.spells.magic_missile, gob, Rng.fixed([3]))
	t.eq(mm.damage, 4, "magic missile 1d4+1")
	t.eq(SpellRules.dc_of(db.spells.burning_hands, caster), 15, "DC 10 + level 1 + Int 4")
	var bh := SpellRules.resolve_on_target(caster, db.spells.burning_hands, gob, Rng.fixed([10, 3]))
	t.ok(not bh.saved, "goblin Reflex 10 + 2 fails DC 15")
	t.eq(bh.damage, 3, "burning hands 1d4 at level 1")
	var saved := SpellRules.resolve_on_target(caster, db.spells.burning_hands, gob, Rng.fixed([18, 4]))
	t.eq(saved.damage, 2, "half damage on a save")
	var skel := MonsterRules.derive(MonsterRules.create_actor("skeleton", db), db)
	t.ok(not SpellRules.resolve_on_target(caster, db.spells.daze, skel, Rng.fixed([1])).affected, "undead ignore mind-affecting spells")
	var elf := CharRules.derive(_thessaly(), db)
	t.ok(not SpellRules.resolve_on_target(caster, db.spells.sleep, elf, Rng.fixed([1])).affected, "elves ignore sleep")
	var dz := SpellRules.resolve_on_target(caster, db.spells.daze, gob, Rng.fixed([2]))
	t.ok(dz.effect != null and "dazed" in dz.effect.conditions, "failed save applies the dazed effect")
	var healer := CharRules.derive(_brunhild(), db)
	var clw := SpellRules.resolve_on_target(healer, db.spells.cure_light_wounds, caster, Rng.fixed([5]))
	t.eq(clw.heal, 6, "cure light wounds 1d8 + 1")


func test_spell_slots(t) -> void:
	var c := _thessaly()
	var s := CharRules.derive(c, db)
	t.eq(SpellRules.uses_left(c, s, db.spells.acid_splash, db), -1, "cantrips are at will")
	t.eq(SpellRules.uses_left(c, s, db.spells.magic_missile, db), 2, "two 1st-level slots")
	SpellRules.spend(c, s, db.spells.magic_missile)
	SpellRules.spend(c, s, db.spells.sleep)
	t.ok(not SpellRules.can_use(c, s, db.spells.burning_hands, db), "out of 1st-level slots")
	var b := _brunhild()
	var bs := CharRules.derive(b, db)
	SpellRules.spend(b, bs, db.spells.channel_heal)
	t.eq(SpellRules.uses_left(b, bs, db.spells.channel_harm, db), 2, "channel uses share one pool")


func test_effects(t) -> void:
	var c := _kaelen()
	Effects.add(c, {"id": "fear", "name": "Shaken", "conditions": ["shaken"], "duration": {"rounds": 2}})
	t.eq(CharRules.derive(c, db).attacks[0].bonus, 3, "shaken: -2 attack")
	t.eq(Effects.tick(c).size(), 0, "one round left")
	t.eq(Effects.tick(c).size(), 1, "effect ends")
	t.eq(CharRules.derive(c, db).attacks[0].bonus, 5, "back to normal")
	Effects.add(c, {"id": "sleep", "conditions": ["asleep"], "duration": {"encounter": true}})
	t.ok(Effects.has_flag(c, db, "helpless"), "sleeping creatures are helpless")
	Effects.clear(c, "encounter")
	t.eq(c.effects.size(), 0, "encounter effects cleared")


func test_progression(t) -> void:
	t.eq(Progression.level_for_xp(0), 1, "level 1")
	t.eq(Progression.level_for_xp(2000), 2, "level 2 at 2000 xp")
	t.eq(Progression.level_for_xp(8999), 3, "level 3 below 9000")
	var c := _kaelen()
	c.xp = 2100
	t.ok(Progression.can_level_up(c), "ready to level")
	var req := Progression.requirements(c, db)
	t.eq(req.feats, 1, "fighter bonus feat at level 2")
	t.eq(req.skillPoints, 3, "2 + Int 0 + human 1")
	var res := Progression.level_up(c, db, {"hpRoll": 6, "skillRanks": {"perception": 1}, "feats": ["improved_initiative"]})
	t.eq(res.hpGained, 8, "6 + Con 2")
	var s := CharRules.derive(c, db)
	t.eq(s.bab, 2, "BAB 2")
	t.eq(s.init, 5, "Improved Initiative")
	t.eq(c.skillRanks.perception, 2, "rank added")
	t.ok(not Progression.can_level_up(c), "needs 5000 xp for level 3")


func test_builder_validation(t) -> void:
	var good := {"name": "Test", "race": "human", "cls": "fighter", "racialChoice": "str", "abilities": {"str": 15, "dex": 13, "con": 14, "int": 10, "wis": 12, "cha": 8}, "skillRanks": {"climb": 1}, "feats": ["toughness"]}
	t.eq(CharRules.validate_build(good, db).size(), 0, "valid build")
	var bad: Dictionary = good.duplicate(true)
	bad.abilities.str = 18
	bad.racialChoice = ""
	t.eq(CharRules.validate_build(bad, db).size(), 2, "over budget and missing racial choice")
	t.eq(Progression.requirements_at_level_one(good, db).feats, 3, "human fighter: 3 feats at level 1")


func test_data_integrity(t) -> void:
	for cid in db.classes:
		var cls: Dictionary = db.classes[cid]
		for sid in cls.classSkills:
			t.ok(db.skills.has(sid), "class %s lists unknown skill %s" % [cid, sid])
		for slot in cls.startingKit.equipped:
			t.ok(db.items.has(cls.startingKit.equipped[slot]), "class %s kit has unknown item" % cid)
		for it in cls.startingKit.inventory:
			t.ok(db.items.has(it.id), "class %s inventory has unknown item %s" % [cid, it.id])
		for ab in cls.get("classAbilities", []):
			t.ok(db.spells.has(ab), "class %s has unknown ability %s" % [cid, ab])
	for mid in db.monsters:
		var m: Dictionary = db.monsters[mid]
		t.ok(m.has("attacks") and m.attacks.size() > 0, "monster %s needs an attack" % mid)
		for sp in m.get("spells", []):
			t.ok(db.spells.has(sp.id), "monster %s has unknown spell %s" % [mid, sp.id])
		var actor := MonsterRules.create_actor(mid, db)
		t.ok(MonsterRules.derive(actor, db).ac >= 10, "monster %s derives" % mid)
	for sid in db.spells:
		var sp: Dictionary = db.spells[sid]
		for cond in sp.get("effect", {}).get("conditions", []):
			t.ok(db.conditions.has(cond), "spell %s uses unknown condition %s" % [sid, cond])


## Creature sheets for the journal (src/rules/monster_lore.gd): numbers plus plain-English notes.
func test_monster_lore(t) -> void:
	var sk := MonsterLore.describe("skeleton", db)
	t.eq(sk.name, "Skeleton", "name")
	t.eq(sk.kind, "CR 1/3 - medium undead", "challenge rating, size and type in one line")
	t.eq(sk.stats[1], ["Armor class", "16  (touch 12, flat-footed 14)"], "armor class row")
	t.eq(sk.stats[2], ["Saves", "Fortitude +0, Reflex +2, Will +2"], "saves row")
	var strengths := "\n".join(sk.strengths)
	var weaknesses := "\n".join(sk.weaknesses)
	t.ok(strengths.contains("5 less damage unless the weapon is bludgeoning"), "damage reduction is explained")
	t.ok(strengths.contains("Immune to mind-affecting magic, sleep, fear and poison"), "immunities are listed")
	t.ok(strengths.contains("Sleep"), "... with the spells that are wasted on it")
	t.ok(weaknesses.contains("Use bludgeoning weapons"), "the way round the damage reduction is a weakness")
	t.ok(weaknesses.contains("Disrupt Undead"), "spells made for undead are suggested")
	t.ok(not weaknesses.contains("Sleep") and not weaknesses.contains("Hold Person"), "no spell it is immune to is suggested")
	t.ok(weaknesses.contains("touch attacks only need to beat 12"), "low touch armor class is pointed out")
	t.ok("\n".join(sk.powers).contains("Rusty scimitar: +2 to hit, 1d6+2 slashing damage, critical on 18-20 (x2)."), "attacks are spelled out")
	var zombie := "\n".join(MonsterLore.describe("zombie", db).weaknesses)
	t.ok(zombie.contains("move OR attack"), "the zombie's single action is explained")
	var cultist := MonsterLore.describe("cultist", db)
	t.ok("\n".join(cultist.powers).contains("Casts Daze (at will)"), "spells are listed with their uses")
	t.ok("\n".join(cultist.powers).contains("Casts Cause Fear (once)"), "limited spells say how often")
	t.ok("\n".join(cultist.weaknesses).contains("Sleep"), "low hit dice: Sleep is suggested")
	t.ok("\n".join(MonsterLore.describe("goblin_archer", db).powers).contains("ranged (up to 12 squares)"), "ranged attacks show their range")
	t.eq(MonsterLore.cr_value({"cr": "1/3"}) < 0.5, true, "fractional challenge ratings are read")
	t.eq(MonsterLore.describe("no_such_monster", db), {}, "unknown id gives an empty sheet")
	# hand-written notes in the data come first
	var custom := {"monsters": {"x": {"name": "X", "hp": 4, "ac": 10, "attacks": [], "lore": {"weaknesses": ["Hates rain."]}}}, "spells": {}, "skills": {}}
	t.eq(MonsterLore.describe("x", custom).weaknesses[0], "Hates rain.", "\"lore\" notes from the data are listed first")
	# every monster in the base data gets a complete sheet
	for mid in db.monsters:
		var d := MonsterLore.describe(mid, db)
		t.ok(d.stats.size() >= 6 and not d.powers.is_empty(), "%s has a full sheet" % mid)
		t.ok(MonsterLore.text(mid, db).contains(d.name), "%s has a plain-text sheet" % mid)
