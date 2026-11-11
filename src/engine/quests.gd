class_name Quests
extends RefCounted
## Quest log. Quests are defined in a campaign's quests.json:
##   "rats": {"name": "...", "type": "main|side", "summary": "...",
##            "stages": [{"id": "start", "text": "Clear the cellar."}, {"id": "report", "text": "..."}],
##            "rewards": {"xp": 200, "gold": 25, "items": [{"id": "potion_clw", "qty": 1}]}}
## Saved progress lives in game.state.quests[id] = {status: active|completed|failed, stage, seen: [stage ids]}.


static func def(game, quest_id: String) -> Dictionary:
	return game.campaign.get("quests", {}).get(quest_id, {})


static func start(game, quest_id: String) -> void:
	if game.state.quests.has(quest_id):
		return
	var q := def(game, quest_id)
	if q.is_empty():
		push_warning("Unknown quest '%s'" % quest_id)
		return
	var first: String = q.stages[0].id if q.get("stages", []).size() > 0 else ""
	game.state.quests[quest_id] = {"status": "active", "stage": first, "seen": [first]}
	game.journal("quest", "New quest: %s" % q.get("name", quest_id), {"quest": quest_id})
	game.io.sfx("quest")
	game.state_changed.emit()


static func set_stage(game, quest_id: String, stage_id: String) -> void:
	if not game.state.quests.has(quest_id):
		start(game, quest_id)
	var st = game.state.quests.get(quest_id)
	if st == null or st.status != "active" or st.stage == stage_id:
		return
	st.stage = stage_id
	if not (stage_id in st.seen):
		st.seen.append(stage_id)
	game.journal("quest", "Quest updated: %s" % def(game, quest_id).get("name", quest_id), {"quest": quest_id})
	game.io.sfx("quest")
	game.state_changed.emit()


static func complete(game, quest_id: String) -> void:
	if not game.state.quests.has(quest_id):
		start(game, quest_id)
	var st = game.state.quests.get(quest_id)
	if st == null or st.status == "completed":
		return
	st.status = "completed"
	var q := def(game, quest_id)
	game.journal("quest", "Quest completed: %s" % q.get("name", quest_id), {"quest": quest_id})
	game.io.sfx("quest_done")
	var rw: Dictionary = q.get("rewards", {})
	if rw.has("gold"):
		game.add_gold(int(rw.gold))
	for it in rw.get("items", []):
		game.add_item(it.id, int(it.get("qty", 1)), true)
	if rw.has("xp"):
		game.give_xp(int(rw.xp))
	game.state_changed.emit()


static func fail(game, quest_id: String) -> void:
	var st = game.state.quests.get(quest_id)
	if st == null or st.status != "active":
		return
	st.status = "failed"
	game.journal("quest", "Quest failed: %s" % def(game, quest_id).get("name", quest_id), {"quest": quest_id})
	game.state_changed.emit()


static func stage_text(game, quest_id: String, stage_id: String) -> String:
	for s in def(game, quest_id).get("stages", []):
		if s.id == stage_id:
			return s.get("text", "")
	return ""
