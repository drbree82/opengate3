class_name ScriptRunner
extends RefCounted
## Runs the little JSON "scripts" campaigns are made of. A script is a list of ACTIONS:
##     [{"op": "quest.start", "id": "rats"}, {"op": "gold.add", "amount": 25, "if": {"flag": "paid"}}]
## Any action may carry an "if" CONDITION; the action is skipped when the condition is false.
## Every op and condition is listed with examples in docs/SCRIPTING.md - keep that file in sync!
##
## To add a new op:        ops["my.op"] = func(a, ctx): ...      (see _register_ops below)
## To add a new condition: conds["myKey"] = func(c, ctx): return true/false
## ctx is a Dictionary shared by the actions of one script run (who, ent, deferred, ...).

var game
var ops: Dictionary = {}
var conds: Dictionary = {}


func _init(g) -> void:
	game = g
	_register_conds()
	_register_ops()


## Runs a list of actions in order (await it).
func run(actions, ctx: Dictionary = {}) -> void:
	if typeof(actions) != TYPE_ARRAY:
		return
	for a in actions:
		if typeof(a) != TYPE_DICTIONARY:
			continue
		if a.has("if") and not test(a["if"], ctx):
			continue
		var op_name: String = a.get("op", "")
		if not ops.has(op_name):
			push_warning("Unknown script op '%s'" % op_name)
			continue
		# Inside a dialogue, scene-changing ops wait until the conversation has closed.
		if ctx.has("deferred") and op_name in ["combat.start", "map.goto", "dialogue.start", "camp.go", "camp.leave", "campaign.end"]:
			ctx.deferred.append(a)
			continue
		await ops[op_name].call(a, ctx)
		if ctx.get("stop", false):
			break


## Evaluates a condition Dictionary. All keys present must hold (so {"flag": "a", "gold": 10} = both).
func test(cond, ctx: Dictionary = {}) -> bool:
	if cond == null:
		return true
	if typeof(cond) != TYPE_DICTIONARY:
		return bool(cond)
	for key in cond:
		if key in ["equals", "stage", "status", "atLeast", "qty", "state", "min"]:
			continue  # parameters of another key
		if not conds.has(key):
			push_warning("Unknown condition '%s'" % key)
			return false
		if not conds[key].call(cond, ctx):
			return false
	return true


func _register_conds() -> void:
	conds["flag"] = func(c, _ctx):
		var v = game.state.flags.get(c.flag)
		if c.has("equals"):
			return v == c.equals
		return v != null and v != false and (typeof(v) != TYPE_INT or v != 0)
	conds["not"] = func(c, ctx): return not test(c["not"], ctx)
	conds["all"] = func(c, ctx):
		for sub in c.all:
			if not test(sub, ctx):
				return false
		return true
	conds["any"] = func(c, ctx):
		for sub in c.any:
			if test(sub, ctx):
				return true
		return false
	conds["quest"] = func(c, _ctx):
		var q = game.state.quests.get(c.quest)
		if c.has("status"):
			return (q.status if q != null else "none") == c.status
		if q == null:
			return false
		if c.has("stage"):
			return q.status == "active" and q.stage == c.stage
		if c.has("atLeast"):
			return c.atLeast in q.seen
		return q.status == "active"
	conds["hasItem"] = func(c, _ctx): return game.count_item(c.hasItem) >= int(c.get("qty", 1))
	conds["inParty"] = func(c, _ctx): return c.inParty in game.state.party
	conds["companion"] = func(c, _ctx): return game.state.companions.get(c.companion, "absent") == c.get("state", "party")
	conds["gold"] = func(c, _ctx): return int(game.state.gold) >= int(c.gold)
	conds["cls"] = func(c, _ctx): return game.leader().cls == c.cls
	conds["race"] = func(c, _ctx): return game.leader().race == c.race
	conds["partyCls"] = func(c, _ctx):
		for ch in game.party():
			if ch.cls == c.partyCls:
				return true
		return false
	conds["level"] = func(c, _ctx): return int(game.leader().level) >= int(c.level)
	conds["skill"] = func(c, _ctx): return Stats.skill_total(game.stats(game.leader()), c.skill) >= int(c.get("min", 0))
	conds["partySize"] = func(c, _ctx): return game.state.party.size() >= int(c.partySize)
	conds["partyFull"] = func(c, _ctx): return (game.state.party.size() >= game.max_party()) == bool(c.partyFull)
	conds["inCombat"] = func(c, _ctx): return (game.encounter != null) == bool(c.inCombat)
	conds["map"] = func(c, _ctx): return game.state.mapId == c.map


func _register_ops() -> void:
	# ---- story text ----
	ops["narrate"] = func(a, _ctx): await game.narrate(a.text, a.get("voice", ""))
	ops["say"] = func(a, _ctx): await game.speak(a.get("speaker", ""), a.text, a.get("voice", ""))
	ops["log"] = func(a, _ctx): game.journal("system", game.fmt(a.text))
	ops["banner"] = func(a, _ctx): game.io.banner(game.fmt(a.text), game.fmt(a.get("sub", "")))
	ops["sfx"] = func(a, _ctx): game.io.sfx(a.get("name", ""))
	ops["music"] = func(a, _ctx): game.io.music(a.get("track", ""))
	ops["wait"] = func(a, _ctx): await game.delay(float(a.get("seconds", 1.0)))
	ops["fade"] = func(a, _ctx): await game.io.fade(a.get("to", "black") == "black", float(a.get("seconds", 0.6)))
	ops["shake"] = func(a, _ctx):
		game.cam.shake(float(a.get("seconds", 0.4)))
		game.io.shake(float(a.get("seconds", 0.4)))

	# ---- flags ----
	ops["flag.set"] = func(a, _ctx): game.set_flag(a.flag, a.get("value", true))
	ops["flag.inc"] = func(a, _ctx): game.set_flag(a.flag, int(game.state.flags.get(a.flag, 0)) + int(a.get("by", 1)))

	# ---- quests ----
	ops["quest.start"] = func(a, _ctx): Quests.start(game, a.id)
	ops["quest.stage"] = func(a, _ctx): Quests.set_stage(game, a.id, a.stage)
	ops["quest.complete"] = func(a, _ctx): Quests.complete(game, a.id)
	ops["quest.fail"] = func(a, _ctx): Quests.fail(game, a.id)

	# ---- items, money, experience ----
	ops["item.give"] = func(a, _ctx): game.add_item(a.id, int(a.get("qty", 1)), true)
	ops["item.take"] = func(a, _ctx): game.remove_item(a.id, int(a.get("qty", 1)), true)
	ops["gold.add"] = func(a, _ctx): game.add_gold(int(a.amount))
	ops["xp.add"] = func(a, _ctx): await game.give_xp(int(a.amount))

	# ---- party ----
	ops["party.add"] = func(a, _ctx): Party.add(game, a.id)
	ops["party.remove"] = func(a, _ctx): Party.send_to_camp(game, a.id)
	ops["approval.add"] = func(a, _ctx): Party.add_approval(game, a.id, int(a.get("amount", 1)))
	ops["heal"] = func(a, _ctx):
		for c in _who(a.get("who", "party")):
			var amount: int = 9999 if str(a.get("amount", "full")) == "full" else int(a.amount)
			game.heal_character(c, amount)
	ops["rest"] = func(_a, _ctx): await game.rest()
	ops["effect.add"] = func(a, _ctx):
		for c in _who(a.get("who", "party")):
			Effects.add(c, a.effect)
		game.state_changed.emit()
	ops["damage"] = func(a, ctx): await GM.hazard(game, a, ctx)

	# ---- checks and choices ----
	ops["check"] = func(a, ctx):
		var ok: bool = await GM.check(game, a, ctx)
		await run(a.get("success", []) if ok else a.get("failure", []), ctx)
	ops["choice"] = func(a, ctx):
		if a.has("text"):
			await game.narrate(a.text)
		var options: Array = []
		for o in a.get("options", []):
			if not o.has("if") or test(o["if"], ctx):
				options.append(o)
		if options.is_empty():
			return
		var shown: Array = []
		for o in options:
			shown.append({"text": game.fmt(o.text), "tag": GM.check_tag(game, o.get("check"))})
		var picked: Dictionary = options[await game.io.choose(shown)]
		game.journal("choice", game.fmt(picked.text))
		await run(picked.get("do", []), ctx)
		if picked.has("check"):
			var ok: bool = await GM.check(game, picked.check, ctx)
			await run(picked.get("success", []) if ok else picked.get("failure", []), ctx)

	# ---- travel, scenes ----
	ops["map.goto"] = func(a, _ctx): await game.travel(a.map, a.get("marker", "start"))
	ops["camp.go"] = func(_a, _ctx): await game.go_to_camp()
	ops["camp.leave"] = func(_a, _ctx): await game.leave_camp()
	ops["combat.start"] = func(a, _ctx): await game.start_combat(a.group, a.get("surprise", ""))
	ops["cutscene.play"] = func(a, _ctx): await Cutscene.play(game, a.id)
	ops["dialogue.start"] = func(a, ctx): await game.run_dialogue(a.id, {"ent": ctx.get("ent")})
	ops["shop.open"] = func(a, _ctx): await game.io.open_shop(a.id)
	ops["save"] = func(_a, _ctx): game.autosave()
	ops["campaign.end"] = func(a, _ctx): await game.end_campaign(a.get("victory", true), a.get("text", ""))

	# ---- map and entities ----
	ops["entity.remove"] = func(a, _ctx):
		var e: Ent = game.world.by_id(a.id)
		if e != null:
			game.world.remove(e)
	ops["entity.spawn"] = func(a, _ctx):
		var pos = _pos(a)
		if pos == null:
			push_warning("entity.spawn: no position for %s" % str(a.get("template", "")))
			return
		var overrides: Dictionary = a.get("set", {}).duplicate(true)
		if a.has("id"):
			overrides["id"] = a.id
		if a.has("group"):
			overrides["group"] = a.group
		var cell: Vector2i = game.world.free_cell_near(Vector2i(floori(pos.x), floori(pos.y)))
		var e: Ent = game.world.spawn(a.template, Vector2(cell.x + 0.5, cell.y + 0.5), overrides, a.get("persist", true))
		if game.encounter != null and e.kind == "monster" and e.hostile:
			await game.encounter.add_combatant(e)
	ops["entity.set"] = func(a, _ctx):
		var e: Ent = game.world.by_id(a.id)
		if e == null:
			return
		for k in a.get("set", {}):
			match k:
				"hidden": e.hidden = a.set[k]
				"dialogue": e.dialogue = a.set[k]
				"name": e.name = a.set[k]
				"blocking": e.blocking = a.set[k]
				"anim": e.set_anim(a.set[k])
				"facing": e.facing = Ent.facing_from(a.set[k])
		game.world.ents_changed.emit()
	ops["group.hostile"] = func(a, _ctx):
		for e in game.world.ents_in_group(a.group):
			e.hostile = a.get("hostile", true)
			e.side = "enemy" if e.hostile else "neutral"
	ops["group.remove"] = func(a, _ctx):
		for e in game.world.ents_in_group(a.group):
			game.world.remove(e)
	ops["tile.set"] = func(a, _ctx):
		var pos = _pos(a)
		if pos != null:
			game.world.set_tile(Vector2i(floori(pos.x), floori(pos.y)), a.char)
	ops["door.open"] = func(a, _ctx):
		var pos = _pos(a)
		if pos != null:
			game.world.open_door(Vector2i(floori(pos.x), floori(pos.y)))


## Characters an action applies to: "party" (default), "leader", "all" (whole roster) or a character id.
func _who(who: String) -> Array:
	match who:
		"party":
			return game.party()
		"leader":
			return [game.leader()]
		"all":
			return game.state.roster.values()
	if game.state.roster.has(who):
		return [game.state.roster[who]]
	return []


## Position of an action: {"at": "marker" | "entity id" | [x, y]} or {"x": n, "y": n}. Returns Vector2 or null.
func _pos(a: Dictionary):
	return game.resolve_pos(a.get("at", [a.get("x"), a.get("y")] if a.has("x") else null))
