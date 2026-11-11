class_name Party
extends RefCounted
## Party and companion management. Companions are pre-made characters from a campaign's
## companions.json. They double as the "origin" characters the player may pick as their own hero.
##   game.state.roster      every character that exists (player + recruited companions)
##   game.state.party       ids of the characters currently travelling together (max campaign.maxPartySize)
##   game.state.leader      id of the character the player steers
##   game.state.companions  id -> "absent" (not recruited) | "party" | "camp" | "player" (is the hero)


static func add(game, char_id: String) -> bool:
	var state: Dictionary = game.state
	if not state.roster.has(char_id):
		var spec = game.campaign.get("companions", {}).get(char_id)
		if spec == null:
			push_warning("Unknown companion '%s'" % char_id)
			return false
		var s: Dictionary = spec.duplicate(true)
		s["id"] = char_id
		var c := CharRules.create(s, game.db)
		# Companions catch up to the hero's level so nobody joins hopelessly behind.
		while int(c.level) < int(game.leader().level):
			Progression.level_up(c, game.db)
		c.xp = maxi(int(c.xp), int(game.leader().xp))
		state.roster[char_id] = c
	if char_id in state.party:
		return true
	if state.party.size() >= game.max_party():
		state.companions[char_id] = "camp"
		game.journal("system", "%s will wait at camp (the party is full)." % state.roster[char_id].name)
	else:
		state.party.append(char_id)
		state.companions[char_id] = "party"
		game.journal("system", "%s joins the party." % state.roster[char_id].name)
		game.io.sfx("join")
	# The recruitable NPC version disappears from the map.
	for e in game.world.ents.duplicate():
		if e.kind == "npc" and e.char_id == char_id:
			game.world.ents.erase(e)
	game.world.sync_party()
	game.world.refresh_companions()
	game.state_changed.emit()
	return true


static func send_to_camp(game, char_id: String) -> void:
	var state: Dictionary = game.state
	if not (char_id in state.party) or char_id == state.playerId:
		return
	state.party.erase(char_id)
	state.companions[char_id] = "camp"
	if state.leader == char_id:
		state.leader = state.playerId
	game.journal("system", "%s heads back to camp." % state.roster[char_id].name)
	game.world.sync_party()
	game.world.refresh_companions()
	game.state_changed.emit()


static func set_leader(game, char_id: String) -> void:
	if char_id in game.state.party and int(game.state.roster[char_id].hp) > 0:
		game.state.leader = char_id
		game.cam.focus = null
		game.state_changed.emit()


static func add_approval(game, char_id: String, amount: int) -> void:
	var ap: Dictionary = game.state.approval
	ap[char_id] = int(ap.get(char_id, 0)) + amount
	var who: String = game.state.roster.get(char_id, game.campaign.get("companions", {}).get(char_id, {})).get("name", char_id)
	game.journal("system", "%s %s." % [who, "approves" if amount > 0 else "disapproves"])
	game.state_changed.emit()
