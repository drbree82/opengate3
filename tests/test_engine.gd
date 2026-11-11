extends RefCounted
## Headless tests for the game engine (src/engine) using the tiny campaign in campaigns/_template.
## The game runs with the base GameIO: no screen, instant waits, automatic choices.


func _game(seed_value := 7) -> Game:
	var g := Game.new(null, seed_value)
	g.instant = true
	g.io.policy = "first"
	return g


func _hero() -> Dictionary:
	return {"name": "Tester", "race": "human", "cls": "fighter", "racialChoice": "str",
		"abilities": {"str": 15, "dex": 13, "con": 14, "int": 10, "wis": 12, "cha": 8},
		"feats": ["toughness", "weapon_focus:longsword", "dodge"], "skillRanks": {"perception": 1}}


func test_map_parsing(t) -> void:
	var g := _game()
	t.ok(g.load_campaign("_template"), "template campaign loads")
	var m := MapData.parse(g.campaign.maps.room, "room")
	t.eq(m.errors.size(), 0, "no map errors: %s" % str(m.errors))
	t.eq(m.w, 15, "width")
	t.eq(m.h, 9, "height")
	t.ok(m.is_solid(0, 0), "wall is solid")
	t.ok(not m.is_solid(1, 1), "floor is open")
	t.ok(m.is_solid(8, 4), "closed door is solid")
	t.ok(m.door(8, 4) != null, "door found")
	m.open_door(8, 4)
	t.ok(not m.is_solid(8, 4), "opened door is passable")
	t.eq(m.marker_pos("start"), Vector2(2.5, 6.5), "start marker")
	t.eq(m.cameras.size(), 1, "one room camera")
	t.eq(m.trigger_at(5, 7), "tripwire", "trigger tile")
	t.ok(m.placements.size() >= 6, "entities placed from the legend")


func test_grid(t) -> void:
	var g := _game()
	g.load_campaign("_template")
	var m := MapData.parse(g.campaign.maps.room, "room")
	var blocked := func(c: Vector2i): return m.blocks_move(c.x, c.y)
	var path := Grid.find_path(Vector2i(2, 6), Vector2i(6, 2), blocked)
	t.ok(path.size() > 0, "path found in the open room")
	t.eq(path[path.size() - 1], Vector2i(6, 2), "path ends at the goal")
	t.eq(Grid.find_path(Vector2i(2, 6), Vector2i(11, 4), blocked).size(), 0, "locked door blocks the path")
	t.ok(not Grid.line_of_sight(m, Vector2i(2, 4), Vector2i(11, 4)), "door blocks sight")
	t.ok(Grid.line_of_sight(m, Vector2i(1, 1), Vector2i(6, 6)), "clear sight across the room")
	t.eq(Grid.dist(Vector2i(0, 0), Vector2i(4, 4)), 6, "4 diagonals = 6 squares")
	var reach := Grid.reachable(Vector2i(2, 6), 3.0, blocked)
	t.ok(reach.has(Vector2i(5, 6)), "3 squares straight")
	t.ok(not reach.has(Vector2i(6, 6)), "4 squares is too far")
	t.ok(reach.has(Vector2i(4, 4)), "two diagonals cost 3")


func test_new_game_and_script_ops(t) -> void:
	var g := _game()
	g.load_campaign("_template")
	await g.new_game(_hero())
	t.eq(g.mode, "explore", "exploring after the intro")
	t.eq(g.busy, 0, "nothing left running")
	t.ok(g.state.flags.get("cutscene.intro", false), "intro cutscene played")
	t.eq(g.state.quests.first_steps.stage, "talk", "quest started")
	t.ok(g.world.leader_ent() != null, "leader is on the map")
	t.eq(g.world.leader_ent().cell(), Vector2i(2, 6), "leader at the start marker")
	t.eq(g.world.by_id("guide").cell(), Vector2i(4, 4), "cutscene moved the guide to the marker")
	t.eq(g.state.gold, 30, "class gold 20 + campaign 10")
	await g.run_actions([
		{"op": "flag.set", "flag": "a"}, {"op": "flag.inc", "flag": "n", "by": 2},
		{"op": "item.give", "id": "dagger"}, {"op": "gold.add", "amount": 5, "if": {"flag": "a"}},
		{"op": "gold.add", "amount": 500, "if": {"flag": "nope"}},
	])
	t.eq(g.state.gold, 35, "conditional gold")
	t.eq(g.count_item("dagger"), 1, "item given")
	t.ok(g.scripts.test({"all": [{"flag": "a"}, {"flag": "n", "equals": 2}, {"not": {"flag": "zzz"}}, {"hasItem": "dagger"}]}), "conditions")
	t.ok(not g.scripts.test({"quest": "first_steps", "stage": "rats"}), "quest stage condition")


func test_dialogue_and_party(t) -> void:
	var g := _game()
	g.load_campaign("_template")
	await g.new_game(_hero())
	await g.run_dialogue("guide", {"ent": g.world.by_id("guide")})
	t.ok(g.state.flags.get("met_guide", false), "dialogue set a flag")
	t.eq(g.state.quests.first_steps.stage, "rats", "dialogue advanced the quest")
	t.ok(not g.in_dialogue and g.busy == 0, "dialogue finished cleanly")
	var ally := g.world.by_id("ally")
	t.ok(ally != null and ally.kind == "npc", "recruitable companion stands in the room")
	Party.add(g, "ally")
	t.eq(g.state.party.size(), 2, "companion joined")
	t.eq(g.world.party_ents().size(), 2, "companion walks with the party")
	t.eq(g.state.companions.ally, "party", "companion state")
	Party.send_to_camp(g, "ally")
	t.eq(g.state.party.size(), 1, "companion sent away")


func test_combat(t) -> void:
	var g := _game(11)
	g.load_campaign("_template")
	await g.new_game(_hero())
	Party.add(g, "ally")
	g.world.open_door(Vector2i(8, 4))
	var res: String = await g.start_combat("rats")
	t.ok(res in ["victory", "defeat"], "combat finished: %s" % res)
	t.eq(g.encounter, null, "encounter cleared")
	t.eq(g.mode, "explore", "back to exploring")
	if res == "victory":
		t.eq(g.world.ents_in_group("rats").size(), 0, "no rats left")
		t.eq(g.state.quests.first_steps.stage, "report", "onVictory script ran")
		t.ok(int(g.leader().xp) > 0, "xp awarded")


func test_triggers_doors_and_save(t) -> void:
	var g := _game(3)
	g.load_campaign("_template")
	await g.new_game(_hero())
	var hp_before: int = g.leader().hp
	g.world.fire_trigger("tripwire")
	t.ok("tripwire" in g.world.map_state().fired, "trigger recorded as fired")
	t.ok(int(g.leader().hp) <= hp_before, "trap resolved")
	g.world.click_ent(g.world.by_id("supply_chest"))
	for i in 400:
		g.update(0.05)
	t.eq(g.count_item("potion_clw"), 3, "walked to the chest and looted it (1 from kit + 2)")
	var data := g.save_data()
	var json = JSON.parse_string(JSON.stringify(data))
	var g2 := _game()
	t.ok(g2.load_data(Util.intify(json)), "save loads")
	t.eq(g2.count_item("potion_clw"), 3, "inventory restored")
	t.eq(g2.state.gold, g.state.gold, "gold restored")
	t.ok(g2.world.by_id("supply_chest").interact == null, "looted chest stays looted")
	t.eq(g2.world.leader_ent().cell(), g.world.leader_ent().cell(), "position restored")
	await g2.rest()
	t.eq(g2.leader().hp, g2.stats(g2.leader()).hpMax, "rest heals")
