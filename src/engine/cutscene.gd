class_name Cutscene
extends RefCounted
## Plays cutscenes (campaigns/<id>/cutscenes/*.json): scripted camera moves and sprite "actors" in
## the same 3D room the game is played in. Full reference with examples: docs/CUTSCENES.md.
##
##   {"map": "town",                 optional: switch to this map first
##    "steps": [
##      {"op": "fade", "to": "black", "seconds": 0},
##      {"op": "camera.set", "at": [4, 9], "z": 0.8, "look": "reeve"},
##      {"op": "fade", "to": "clear", "seconds": 1.2},
##      {"op": "parallel", "steps": [
##          {"op": "camera.move", "at": [6, 9], "look": "reeve", "seconds": 4},
##          {"op": "actor.move", "id": "reeve", "to": "square"}]},
##      {"op": "say", "speaker": "reeve", "text": "You came."},
##      {"op": "flag.set", "flag": "met_reeve"}]}       any normal script op also works
##
## Positions ("at", "to", "look") are a marker name, an entity id, or [x, y] tile coordinates.
## While a cutscene plays the player can press Space/click to skip a line, or Esc to skip the scene
## (game.skip_cutscene): remaining steps still RUN, just instantly, so flags and quests stay correct.


static func play(game, cutscene_id: String) -> void:
	var cs = game.campaign.get("cutscenes", {}).get(cutscene_id)
	if cs == null:
		push_warning("Unknown cutscene '%s'" % cutscene_id)
		return
	game.busy += 1
	game.in_cutscene = true
	game.skip_cutscene = false
	game.mode_changed.emit()
	if cs.has("map") and (game.world.map == null or game.world.map.id != cs.map):
		game.world.store_state()
		game.world.load_map(cs.map, cs.get("marker", "start"))
	for e in game.world.ents:
		e.path = []
		if e.anim == "walk":
			e.set_anim("idle")
	game.cam.mode = "script"
	game.cam.focus = null
	game.io.letterbox(true)
	var ctx := {"cutscene": cutscene_id}
	await run_steps(game, cs.get("steps", []), ctx)
	for e in game.world.ents.duplicate():
		if e.temp:
			game.world.remove(e, false)
	game.anims.finish_all()
	game.cam.mode = "auto"
	game.cam.focus = null
	game.cam.snap()
	game.io.letterbox(false)
	await game.io.fade(false, 0.0 if game.skip_cutscene else 0.3)
	game.set_flag("cutscene." + cutscene_id, true)
	game.in_cutscene = false
	game.skip_cutscene = false
	game.busy -= 1
	game.mode_changed.emit()


static func run_steps(game, steps: Array, ctx: Dictionary) -> void:
	for s in steps:
		if typeof(s) == TYPE_DICTIONARY:
			await run_step(game, s, ctx)


static func run_step(game, s: Dictionary, ctx: Dictionary) -> void:
	if s.has("if") and not game.scripts.test(s["if"], ctx):
		return
	var cam: CamRig = game.cam
	var world: World = game.world
	match s.get("op", ""):
		"wait":
			await game.delay(float(s.get("seconds", 1.0)))
		"parallel":
			var pending := [0]
			for sub in s.get("steps", []):
				pending[0] += 1
				_tracked(game, sub, ctx, pending)
			while pending[0] > 0 and game.tree != null:
				await game.tree.process_frame
		"sequence":
			await run_steps(game, s.get("steps", []), ctx)
		"camera.set":
			var c := _camera_goal(game, s)
			for k in c:
				cam.set(k, c[k])
		"camera.move":
			await game.anims.run(cam, _camera_goal(game, s), float(s.get("seconds", 2.0)), s.get("ease", "inout"))
		"camera.auto":
			cam.mode = "auto"
			cam.focus = world.by_id(s.focus) if s.has("focus") else null
			cam.snap()
		"camera.script":
			cam.mode = "script"
		"camera.shake":
			cam.shake(float(s.get("seconds", 0.4)))
		"actor.spawn":
			var pos = game.resolve_pos(s.get("at"))
			if pos == null:
				push_warning("actor.spawn: bad position %s" % str(s.get("at")))
				return
			var overrides: Dictionary = s.get("set", {}).duplicate(true)
			overrides["id"] = s.get("id", s.template)
			overrides["hostile"] = false
			var e := world.spawn(s.template, pos, overrides, false)
			e.temp = not s.get("keep", false)
			e.blocking = false
			if s.has("facing"):
				e.facing = Ent.facing_from(s.facing)
		"actor.remove":
			var e := world.by_id(s.id)
			if e != null:
				world.remove(e, s.get("permanent", false))
		"actor.teleport":
			var e := world.by_id(s.id)
			var pos = game.resolve_pos(s.get("to"))
			if e != null and pos != null:
				e.x = pos.x
				e.y = pos.y
		"actor.move":
			var e := world.by_id(s.id)
			var pos = game.resolve_pos(s.get("to"))
			if e == null or pos == null:
				push_warning("actor.move: unknown actor or position (%s -> %s)" % [str(s.get("id")), str(s.get("to"))])
				return
			var speed := float(s.get("speed", 2.4))
			var path: Array = Grid.find_path(e.cell(), Vector2i(floori(pos.x), floori(pos.y)), func(c): return world.map.blocks_move(c.x, c.y))
			if path.is_empty():
				await world.walk(e, pos, speed)
			else:
				for c in path:
					await world.walk(e, Vector2(c.x + 0.5, c.y + 0.5), speed)
			e.set_anim("idle")
		"actor.face":
			var e := world.by_id(s.id)
			if e != null:
				if s.has("toward"):
					var p = game.resolve_pos(s.toward)
					if p != null:
						e.face_point(p)
				else:
					e.facing = Ent.facing_from(s.get("angle", "S"))
		"actor.anim":
			var e := world.by_id(s.id)
			if e != null:
				if s.has("seconds"):
					await world.play_anim(e, s.anim, float(s.seconds))
				else:
					e.set_anim(s.anim)
		"actor.show", "actor.hide":
			var e := world.by_id(s.id)
			if e != null:
				e.hidden = s.op == "actor.hide"
				world.ents_changed.emit()
		"say":
			var speaker: String = s.get("speaker", "")
			var e := world.by_id(speaker) if speaker != "" else null
			var who: String = game.speaker_name(speaker)
			game.journal("speech", game.fmt(s.text), {"speaker": who, "voice": s.get("voice", "")})
			if e != null and e.can_act():
				e.set_anim("talk")
			if not game.skip_cutscene:
				await game.io.subtitle(who, game.fmt(s.text), s.get("voice", ""))
			if e != null and e.anim == "talk":
				e.set_anim("idle")
		"narrate":
			game.journal("narration", game.fmt(s.text), {"voice": s.get("voice", "")})
			if not game.skip_cutscene:
				await game.io.subtitle("", game.fmt(s.text), s.get("voice", ""))
		"title":
			if not game.skip_cutscene:
				await game.io.title_card(game.fmt(s.get("text", "")), game.fmt(s.get("sub", "")), float(s.get("seconds", 2.5)))
		"fade":
			await game.io.fade(s.get("to", "black") == "black", 0.0 if game.skip_cutscene else float(s.get("seconds", 0.6)))
		_:
			await game.scripts.run([s], ctx)


static func _tracked(game, step: Dictionary, ctx: Dictionary, pending: Array) -> void:
	await run_step(game, step, ctx)
	pending[0] -= 1


## Builds the camera values for camera.set / camera.move:
##   at   camera position;  z  camera height (default 0.75);  fov  field of view in degrees
##   look what to look at (position/entity) - or "angle" in degrees (0 = east, 90 = south)
##   lookZ height of the look target (default 0.45)
static func _camera_goal(game, s: Dictionary) -> Dictionary:
	var cam: CamRig = game.cam
	var out := {}
	var pos := Vector2(cam.px, cam.py)
	if s.has("at"):
		var p = game.resolve_pos(s.at)
		if p != null:
			pos = p
			out["px"] = p.x
			out["py"] = p.y
	if s.has("z"):
		out["pz"] = float(s.z)
	if s.has("look"):
		var t = game.resolve_pos(s.look)
		if t != null:
			out["tx"] = t.x
			out["ty"] = t.y
			out["tz"] = float(s.get("lookZ", 0.45))
	elif s.has("angle"):
		var a := deg_to_rad(float(s.angle))
		out["tx"] = pos.x + cos(a) * 3.0
		out["ty"] = pos.y + sin(a) * 3.0
		out["tz"] = float(s.get("lookZ", float(s.get("z", cam.pz)) - 0.25))
	if s.has("fov"):
		out["fov"] = float(s.fov)
	return out
