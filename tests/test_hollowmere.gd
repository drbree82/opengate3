extends RefCounted
## A scripted play-through of the starter campaign from the first cutscene to the ending:
## all five missions, recruiting the companions, camp, the dungeon and the boss.
## It drives the engine headless. Dialogue choices are picked by text (see `prefer`).
## If you change the campaign's story, update the matching step here.

var prefer: Array = []


func _pick(choices: Array) -> int:
	for want in prefer:
		for i in choices.size():
			if str(choices[i].get("text", "")).contains(want) and not choices[i].get("disabled", false):
				return i
	return 0


func _buff(g: Game) -> void:
	for cid in g.state.roster:
		g.state.roster[cid].hp = 500


## Opens the doors and walks the party up to a monster group, as a player would before a fight.
func _approach(g: Game, group: String) -> void:
	var m: MapData = g.world.map
	for y in m.h:
		for x in m.w:
			if m.door(x, y) != null:
				m.open_door(x, y)
	var foes: Array = g.world.ents_in_group(group)
	if foes.is_empty():
		return
	var spot: Vector2i = g.world.free_cell_near(foes[0].cell())
	var reach := Grid.reachable(foes[0].cell(), 4.0, func(c: Vector2i): return m.blocks_move(c.x, c.y))
	for c in reach:
		if float(reach[c].cost) >= 2.5 and g.world.ent_at(c) == null:
			spot = c
			break
	for e in g.world.party_ents():
		e.set_cell(g.world.free_cell_near(spot, e))
	_buff(g)


func _talk(g: Game, dialogue_id: String, wanted: Array) -> void:
	prefer = wanted
	await g.run_dialogue(dialogue_id, {"ent": g.world.by_id(dialogue_id)})


func _new(hero_id: String, seed_value: int) -> Game:
	var g := Game.new(null, seed_value)
	g.instant = true
	g.io.policy = _pick
	g.load_campaign("hollowmere")
	var hero: Dictionary = g.campaign.companions[hero_id].duplicate(true)
	hero["id"] = hero_id
	await g.new_game(hero)
	return g


func test_full_playthrough(t) -> void:
	var g: Game = await _new("kaelen", 5)
	t.eq(g.world.map.id, "town", "starts in town")
	t.ok(g.state.flags.get("cutscene.intro", false), "intro played")
	t.eq(g.state.quests.a_cold_welcome.stage, "meet", "mission 1 started")
	t.eq(g.world.by_id("kaelen_town"), null, "the hero's own companion NPC is not in town")
	t.ok(g.world.by_id("pip_town") != null, "other companions wait in town")

	# --- Mission 1: A Cold Welcome ---
	await _talk(g, "reeve", ["What does the town pay", "That will do", "I will look into it"])
	t.eq(g.state.quests.a_cold_welcome.stage, "camp", "the Reeve sends us to make camp")
	await _talk(g, "pip", ["open doors", "fair share"])
	await _talk(g, "brunhild", ["Will you help me"])
	t.eq(g.state.party.size(), 3, "Pip and Brunhild joined")
	await g.go_to_camp()
	t.eq(g.world.map.id, "camp", "at camp")
	t.eq(g.state.quests.a_cold_welcome.status, "completed", "mission 1 complete")
	t.eq(g.state.quests.into_the_barrow.stage, "enter", "mission 4 offered")
	await _talk(g, "thessaly", ["unsensible distance"])
	t.eq(g.state.party.size(), 4, "Thessaly joined: full party")
	g.leader().hp = 3
	prefer = ["Rest until morning"]
	await g.run_actions(g.world.by_id("camp_fire").interact, {})
	t.eq(g.leader().hp, g.stats(g.leader()).hpMax, "resting at the campfire heals")
	t.eq(g.state.day, 2, "a day passed")
	await g.leave_camp()
	t.eq(g.world.map.id, "town", "back in town")

	# --- Mission 2: Rats in the Cellar ---
	await _talk(g, "bram", ["Rats?", "I will deal with them"])
	t.eq(g.count_item("cellar_key"), 1, "Bram gave the key")
	prefer = ["Unlock it"]
	await g.world.try_door(Vector2i(9, 6))
	t.ok(not g.world.map.is_solid(9, 6), "cellar door unlocked with the key")
	_approach(g, "cellar_rats")
	t.eq(await g.start_combat("cellar_rats"), "victory", "rats defeated")
	t.eq(g.state.quests.rats_in_the_cellar.stage, "report", "told to report")
	await _talk(g, "bram", [])
	t.eq(g.state.quests.rats_in_the_cellar.status, "completed", "mission 2 complete")

	# --- Mission 3: The Smith's Shipment ---
	await _talk(g, "tova", ["You look troubled", "I will get your crate back"])
	t.eq(g.state.quests.smiths_shipment.stage, "find", "mission 3 started")
	_approach(g, "orchard_goblins")
	await _talk(g, "snagrot", ["Blood it is"])
	t.eq(g.count_item("tova_crate"), 1, "crate recovered after the fight")
	t.eq(g.world.ents_in_group("orchard_goblins").size(), 0, "goblins gone")
	await _talk(g, "tova", [])
	t.eq(g.state.quests.smiths_shipment.status, "completed", "mission 3 complete")
	t.eq(g.count_item("warhammer"), 1, "reward: warhammer")

	# --- Mission 4: Into the Barrow ---
	await g.travel("barrow", "entrance")
	t.ok(g.state.flags.get("cutscene.barrow_enter", false), "barrow cutscene played")
	t.eq(g.state.quests.into_the_barrow.stage, "explore", "exploring the barrow")
	_buff(g)
	prefer = ["Step carefully"]
	g.world.fire_trigger("blade_trap")
	t.eq(g.busy, 0, "trap resolved")
	_approach(g, "hall_dead")
	t.eq(await g.start_combat("hall_dead"), "victory", "skeletons defeated")
	await g.run_actions(g.world.by_id("barrow_chest").interact, {})
	t.eq(g.count_item("barrow_key"), 1, "found the iron key")
	prefer = ["Unlock it"]
	await g.world.try_door(Vector2i(15, 9))
	t.ok(not g.world.map.is_solid(15, 9), "iron door opened")
	_approach(g, "cult")
	t.eq(await g.start_combat("cult"), "victory", "cultists defeated")
	t.ok(g.state.flags.get("cult_dead", false), "captive can be freed")
	await _talk(g, "edrin", ["Go home"])
	t.eq(g.state.quests.into_the_barrow.status, "completed", "mission 4 complete")
	t.eq(g.world.by_id("edrin"), null, "Edrin went home")

	# --- Mission 5: The Hollow King ---
	t.eq(g.state.quests.hollow_king.stage, "confront", "mission 5 started")
	_approach(g, "king")
	prefer = ["Enough. This ends now"]
	g.world.fire_trigger("king_chamber")
	t.ok(g.state.flags.get("cutscene.king_reveal", false), "boss intro played")
	t.ok(g.state.flags.get("cutscene.king_falls", false), "boss defeated")
	t.eq(g.state.quests.hollow_king.stage, "return", "told to return to the Reeve")
	t.eq(g.count_item("hollow_crown"), 1, "the crown is loot")
	t.ok(int(g.leader().level) >= 2 or Progression.can_level_up(g.leader()), "the party has earned level 2 by the end")

	await g.travel("town", "from_barrow")
	var gold_before: int = g.state.gold
	await _talk(g, "reeve", [])
	t.eq(g.state.quests.hollow_king.status, "completed", "mission 5 complete")
	t.eq(int(g.state.gold) - gold_before, 150, "the Reeve pays 150 gold")
	t.ok(g.over, "campaign ended")
	prefer = []
	await g.run_dialogue("elsbeth", {})
	t.eq(g.count_item("cloak_of_resistance"), 1, "Elsbeth's gift for saving Edrin")

	# --- the whole adventure survives a save / load round trip ---
	var json = JSON.parse_string(JSON.stringify(g.save_data()))
	var g2 := Game.new(null, 1)
	g2.instant = true
	t.ok(g2.load_data(Util.intify(json)), "final save loads")
	t.eq(g2.state.party.size(), 4, "party restored")
	t.eq(g2.state.quests.hollow_king.status, "completed", "quests restored")


func test_talking_the_goblins_down(t) -> void:
	var g: Game = await _new("pip", 9)
	g.rng = Rng.fixed([20, 20, 20, 20])
	prefer = ["Leave the crate and run"]
	await g.run_dialogue("snagrot", {})
	t.eq(g.count_item("tova_crate"), 1, "intimidation gets the crate without a fight")
	t.eq(g.world.ents_in_group("orchard_goblins").size(), 0, "the goblins ran off")
	t.eq(g.state.quests.smiths_shipment.stage, "return", "quest jumps to its return stage")


func test_unbinding_the_dead(t) -> void:
	var g: Game = await _new("brunhild", 3)
	await g.travel("barrow", "entrance")
	g.set_flag("knows_rite", true)
	_approach(g, "king")
	prefer = ["Say the words Edrin overheard"]
	g.world.fire_trigger("king_chamber")
	t.eq(g.world.by_id("zombie_a"), null, "the rite removed the first zombie")
	t.eq(g.world.by_id("zombie_b"), null, "and the second")
	t.eq(g.state.quests.hollow_king.stage, "return", "Varrek still had to be fought and beaten")


## The brief for the starter campaign: 1 town, 1 dungeon, 1 encampment and 5 missions.
func test_starter_campaign_shape(t) -> void:
	var g := Game.new(null, 1)
	g.instant = true
	t.ok(g.load_campaign("hollowmere"), "campaign loads")
	var c: Dictionary = g.campaign
	t.eq(c.maps.size(), 3, "three maps in total: town + dungeon + encampment")
	t.ok(c.maps.has("town") and c.maps.town.get("outdoor", false), "1 town: maps/town.json (outdoor, where the game starts)")
	t.eq(c.start.map, "town", "the adventure starts in the town")
	t.ok(c.maps.has("barrow") and not c.maps.barrow.get("outdoor", false), "1 dungeon: maps/barrow.json (indoor)")
	t.eq(c.camp.map, "camp", "1 encampment: maps/camp.json is the party camp")
	t.ok(JSON.stringify(c.entities.camp_fire).contains("rest"), "the encampment has a campfire to rest at")
	t.eq(c.quests.size(), 5, "5 missions: %s" % ", ".join(c.quests.keys()))
	var mains := 0
	for qid in c.quests:
		if c.quests[qid].type == "main":
			mains += 1
	t.eq(mains, 3, "three main missions and two side missions")
	t.eq(c.companions.size(), 4, "four pre-made heroes / companions")
	t.eq(c.cutscenes.size(), 5, "five cutscenes")
	var monsters := 0
	for p in MapData.parse(c.maps.barrow, "barrow").placements:
		if g.world.template(p.entity).get("kind", "") == "monster":
			monsters += 1
	t.ok(monsters >= 6, "the dungeon holds its three fights (%d monsters)" % monsters)
