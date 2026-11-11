extends RefCounted
## Every campaign in campaigns/ must pass the validator, and must survive a headless "smoke run":
## every hero can start, every dialogue, cutscene, trigger and fight runs to the end without
## script errors or getting stuck. Add a campaign folder and it is covered automatically.


func _ids() -> Array:
	var out: Array = []
	for d in DirAccess.get_directories_at("res://campaigns"):
		if FileAccess.file_exists("res://campaigns/%s/campaign.json" % d):
			out.append(d)
	return out


func _game(campaign_id: String, seed_value := 1) -> Game:
	var g := Game.new(null, seed_value)
	g.instant = true
	g.load_campaign(campaign_id)
	return g


func _hero(g: Game, hero_id := "") -> Dictionary:
	var comps: Dictionary = g.campaign.get("companions", {})
	if comps.has(hero_id):
		var s: Dictionary = comps[hero_id].duplicate(true)
		s["id"] = hero_id
		return s
	return {"name": "Tester", "race": "human", "cls": "fighter", "racialChoice": "str",
		"abilities": {"str": 15, "dex": 13, "con": 14, "int": 10, "wis": 12, "cha": 8}, "feats": ["toughness"], "skillRanks": {"perception": 1}}


## A started game with a full party that cannot lose (so content is tested, not luck).
func _started(campaign_id: String, seed_value := 1) -> Game:
	var g := _game(campaign_id, seed_value)
	await g.new_game(_hero(g))
	for cid in g.campaign.get("companions", {}):
		if g.state.party.size() < g.max_party():
			Party.add(g, cid)
	_buff(g)
	return g


func _buff(g: Game) -> void:
	for cid in g.state.roster:
		g.state.roster[cid].hp = 500


## Opens every door and walks the party up to a monster group, as a player would before a fight.
func _approach(g: Game, group: String) -> void:
	var m: MapData = g.world.map
	for y in m.h:
		for x in m.w:
			if m.door(x, y) != null:
				m.open_door(x, y)
	var foes: Array = g.world.ents_in_group(group)
	if foes.is_empty():
		return
	var spot := Vector2i(-1, -1)
	var reach := Grid.reachable(foes[0].cell(), 4.0, func(c: Vector2i): return m.blocks_move(c.x, c.y))
	for c in reach:
		if float(reach[c].cost) >= 2.5 and g.world.ent_at(c) == null:
			spot = c
			break
	if spot.x < 0:
		spot = g.world.free_cell_near(foes[0].cell())
	for e in g.world.party_ents():
		e.set_cell(g.world.free_cell_near(spot, e))


func test_campaigns_pass_validation(t) -> void:
	t.ok(_ids().size() >= 2, "campaigns found")
	for id in _ids():
		var g := _game(id)
		var report := CampaignValidator.check(g)
		t.eq(report.errors.size(), 0, "campaign '%s' has errors: %s" % [id, " | ".join(report.errors)])


func test_validator_catches_mistakes(t) -> void:
	var g := _game("_template")
	g.campaign.dialogues.guide.nodes.hello["goto"] = "nowhere"
	g.campaign.start["do"].append({"op": "quest.strat", "id": "first_steps"})
	g.campaign.start["do"].append({"op": "item.give", "id": "sword_of_typos"})
	g.campaign.maps.room.legend["G"]["entity"] = "nobody"
	var errors: Array = CampaignValidator.check(g).errors
	var text := " | ".join(errors)
	t.ok(text.contains("nowhere"), "missing dialogue node reported")
	t.ok(text.contains("quest.strat"), "unknown op reported")
	t.ok(text.contains("sword_of_typos"), "unknown item reported")
	t.ok(text.contains("nobody"), "unknown entity reported")


func test_every_hero_can_start(t) -> void:
	for id in _ids():
		var probe := _game(id)
		var heroes: Array = probe.campaign.get("companions", {}).keys()
		heroes.append("")
		for hero in heroes:
			var g := _game(id)
			await g.new_game(_hero(g, hero))
			t.eq(g.busy, 0, "%s/%s: start script finished" % [id, hero])
			t.eq(g.mode, "explore", "%s/%s: exploring" % [id, hero])
			t.ok(g.world.leader_ent() != null, "%s/%s: leader placed on the map" % [id, hero])
			t.ok(not g.world.map.blocks_move(g.world.leader_ent().cell().x, g.world.leader_ent().cell().y), "%s/%s: leader stands on open ground" % [id, hero])


func test_every_dialogue_runs(t) -> void:
	for id in _ids():
		var probe := _game(id)
		for did in probe.campaign.get("dialogues", {}):
			for seed_value in [1, 2, 3, 4]:
				var g: Game = await _started(id, seed_value)
				await g.run_dialogue(did, {})
				t.ok(g.busy == 0 and not g.in_dialogue and g.encounter == null, "%s dialogue '%s' (seed %d) ended cleanly" % [id, did, seed_value])


func test_every_cutscene_runs(t) -> void:
	for id in _ids():
		var probe := _game(id)
		for cid in probe.campaign.get("cutscenes", {}):
			var g: Game = await _started(id)
			await Cutscene.play(g, cid)
			t.ok(g.busy == 0 and not g.in_cutscene, "%s cutscene '%s' ended cleanly" % [id, cid])
			t.eq(g.cam.mode, "auto", "%s cutscene '%s' gave the camera back" % [id, cid])


func test_every_map_trigger_and_fight(t) -> void:
	for id in _ids():
		var probe := _game(id)
		for mid in probe.campaign.get("maps", {}):
			var g: Game = await _started(id)
			await g.travel(mid, null)
			t.eq(g.busy, 0, "%s map '%s': onEnter finished" % [id, mid])
			t.ok(g.world.party_ents().size() > 0, "%s map '%s': party arrived" % [id, mid])
			for tid in g.world.map.raw.get("triggers", {}):
				var g2: Game = await _started(id)
				g2.world.load_map(mid, null)
				_buff(g2)
				g2.world.fire_trigger(tid)
				t.ok(g2.busy == 0 and g2.encounter == null, "%s map '%s': trigger '%s' finished" % [id, mid, tid])
			var groups := {}
			for e in g.world.ents:
				if e.kind == "monster":
					groups[e.group] = true
			for group in groups:
				var g3: Game = await _started(id)
				g3.world.load_map(mid, null)
				_buff(g3)
				_approach(g3, group)
				var res: String = await g3.start_combat(group)
				t.eq(res, "victory", "%s map '%s': fight '%s'" % [id, mid, group])
				t.ok(g3.busy == 0 and g3.encounter == null and g3.mode == "explore", "%s map '%s': fight '%s' cleaned up" % [id, mid, group])
			for e in g.world.ents.duplicate():
				if e.interact != null:
					var g4: Game = await _started(id)
					g4.world.load_map(mid, null)
					var twin: Ent = g4.world.by_id(e.id)
					if twin != null:
						await g4.run_actions(twin.interact, {"ent": twin})
						t.eq(g4.busy, 0, "%s map '%s': using '%s' finished" % [id, mid, e.id])


## Every open tile of a map should be reachable from its start marker once all doors are open
## (catches rooms sealed off by a typo in the map rows).
func test_maps_are_connected(t) -> void:
	for id in _ids():
		var probe := _game(id)
		for mid in probe.campaign.get("maps", {}):
			var m := MapData.parse(probe.campaign.maps[mid], mid)
			for y in m.h:
				for x in m.w:
					if m.has_door(x, y):
						m.open_door(x, y)
			var start = m.marker_pos("start")
			if start == null and not m.markers.is_empty():
				start = m.marker_pos(m.markers.keys()[0])
			if start == null:
				start = m.any_open()
			var reach := Grid.reachable(Vector2i(floori(start.x), floori(start.y)), 9999.0, func(c: Vector2i): return m.blocks_move(c.x, c.y))
			var open := 0
			var missing: Array = []
			for y in m.h:
				for x in m.w:
					if not m.blocks_move(x, y):
						open += 1
						if not reach.has(Vector2i(x, y)) and missing.size() < 5:
							missing.append(Vector2i(x, y))
			t.ok(missing.is_empty(), "%s map '%s': %d open tiles, unreachable ones e.g. %s" % [id, mid, open, str(missing)])
