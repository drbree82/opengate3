extends RefCounted
## Campaign-only integration tests: full story, powers, party invariants and save persistence.
var prefer: Array = []
func pick(options: Array) -> int:
	for want in prefer:
		for i in options.size():
			if str(options[i].text).contains(want):
				return i
	return options.size() - 1
func talk(g: Game, id: String, wants: Array = []) -> void:
	prefer = wants
	await g.run_dialogue(id, {})
func fresh() -> Game:
	var g := Game.new(null, 7)
	g.instant = true
	g.io.policy = pick
	g.load_campaign("unwritten_oath")
	var hero: Dictionary = g.campaign.companions.witness.duplicate(true)
	hero.id = "witness"
	await g.new_game(hero)
	return g
func hearing(g: Game) -> void:
	await talk(g, "seris", ["cannot release"])
	await talk(g, "rowan", ["speak for yourself"])
	await talk(g, "ledger", ["Preserve"])
	await talk(g, "registrar", ["Petition"])
	await talk(g, "rowan", ["invite his testimony"])
func test_complete_story(t) -> void:
	for ending in ["Give him space", "Ask whether he wants"]:
		var g: Game = await fresh()
		await hearing(g)
		t.ok("seris" in g.state.party and "rowan" in g.state.party, "both are party characters")
		t.eq(g.state.party.size(), 4, "full party")
		t.ok(not g.over, "hearing is only the opening")
		await talk(g, "archive_exit", ["Travel"])
		await talk(g, "proof_clerk")
		await talk(g, "clerk", ["Ask directly", "documentary", "Hear the details"])
		t.ok(g.state.flags.get("info_clerk", false), "no charm required")
		await talk(g, "market_to_ferry", ["Continue"])
		await talk(g, "sister", ["memory"])
		await talk(g, "sister", ["recover the bell"])
		await talk(g, "bell_cache", ["Take it"])
		await talk(g, "sister", ["Return the bell"])
		await talk(g, "ferry_to_vault", ["Continue"])
		await talk(g, "counterseal_cache", ["Take it"])
		await talk(g, "register", ["Take it"])
		await talk(g, "lantern", ["Take it"])
		await g.go_to_camp()
		await talk(g, "camp_fire", ["Release Mara"])
		t.ok(not g.state.flags.get("free_testimony", false), "rescue is not purchased testimony")
		await talk(g, "mara", ["testify freely"])
		await talk(g, "camp_fire", ["Entrust"])
		await g.leave_camp()
		await talk(g, "vault_to_manor", ["Continue"])
		await talk(g, "family_seal", ["Blood, Obedience"])
		t.eq(g.count_item("original_grant"), 0, "wrong answer does not grant evidence")
		for id in ["stone_name", "stone_will", "stone_release"]:
			await talk(g, id)
		await talk(g, "family_seal", ["Name, Will"])
		await talk(g, "manor_to_court", ["Continue"])
		await talk(g, "envoy", ["Reject both", "Return to Rowan"])
		t.ok(g.state.flags.get("seris_free", false) and g.state.flags.get("rowan_free", false), "both free together")
		t.eq(g.state.flags.superior_claim, false, "superior lien cancelled")
		await talk(g, "camp_fire", ["Speak with Rowan", ending])
		t.ok(g.over, "ending reached")
		var saved = Util.intify(JSON.parse_string(JSON.stringify(g.save_data())))
		var restored := Game.new(null, 1)
		restored.instant = true
		t.ok(restored.load_data(saved), "final state reloads")
		t.eq(restored.state.flags.ending, g.state.flags.ending, "ending choice persisted")
func test_failed_checks_and_cloud(t) -> void:
	var g: Game = await fresh()
	await hearing(g)
	await g.travel("market")
	g.rng = Rng.fixed([1])
	await talk(g, "clerk", ["Succubus Spittle"])
	t.ok(not g.state.flags.get("info_clerk", false), "failed charm grants no information")
	g.rng = Rng.fixed([20])
	await talk(g, "clerk", ["Succubus Spittle"])
	t.ok(not g.state.flags.get("info_clerk", false), "cannot spam same contact")
	await talk(g, "proof_clerk")
	await talk(g, "clerk", ["Ask directly", "documentary", "Hear the details"])
	t.ok(g.state.flags.get("info_clerk", false), "document route survives failed charm")
	await g.travel("vault")
	var party_before: Array = g.state.party.duplicate()
	var approval_before: Dictionary = g.state.approval.duplicate()
	g.rng = Rng.fixed([20])
	await talk(g, "approach_vault", ["Cast Invisible"])
	t.eq(g.state.flags.cloud_steps, 10, "ten tile entries")
	for e in g.world.ents_in_group("vault_collectors"):
		t.ok(not e.hostile, "humanoid guard calmed")
	for e in g.world.ents_in_group("vault_dead"):
		t.ok(e.hostile, "undead immune")
	t.eq(g.state.party, party_before, "party unaffected")
	t.eq(g.state.approval, approval_before, "loyalty unaffected")
	var restored := Game.new(null, 1)
	restored.instant = true
	restored.load_data(Util.intify(JSON.parse_string(JSON.stringify(g.save_data()))))
	restored.world.fire_trigger("cloud_step")
	t.eq(restored.state.flags.cloud_steps, 9, "save retains duration")
	for i in 10:
		g.world.fire_trigger("cloud_step")
	t.eq(g.state.flags.cloud_active, false, "expires")
	for e in g.world.ents_in_group("vault_collectors"):
		t.ok(e.hostile, "guards alert again")
	await talk(g, "approach_vault", ["Cast Invisible"])
	t.eq(g.state.flags.cloud_active, false, "daily use spent")
	await g.go_to_camp()
	await talk(g, "camp_fire", ["Rest until"])
	t.eq(g.state.flags.cloud_used, false, "rest renews use")
	await g.leave_camp()
	g.rng = Rng.fixed([1])
	await talk(g, "approach_vault", ["Cast Invisible"])
	t.ok(g.state.flags.cloud_used and not g.state.flags.cloud_active, "failure spends daily use")
func test_early_verdict_and_portraits(t) -> void:
	var g: Game = await fresh()
	await g.travel("court")
	await talk(g, "envoy", ["Reject both"])
	t.ok(not g.state.flags.get("both_free", false), "cannot skip evidence")
	for id in ["seris", "rowan"]:
		var tex := Portraits.painted(g.campaign.dir, id)
		t.ok(tex != null, "portrait loads")
		if tex != null:
			t.eq(tex.get_width(), tex.get_height(), "square portrait")
