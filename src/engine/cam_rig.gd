class_name CamRig
extends RefCounted
## Where the 3D camera is and what it looks at. Pure numbers (tile coordinates + height);
## src/render/world_view.gd copies them onto the real Camera3D every frame.
##
## mode "auto":   the rig positions itself each frame:
##     "room"  - the map has camera tiles (legend entry with camera: true): the camera sits on the
##               best one, like a camera mounted in the room, turns to track the party and zooms.
##     "chase" - no camera tile sees the party (or the player pressed C): follows behind the leader.
##     "frame" - during dialogue: over-the-shoulder shot of the person being spoken to.
## mode "script": cutscenes own the camera (src/engine/cutscene.gd tweens px..fov directly).

var game
var mode := "auto"
var prefer_chase := false
var px := 0.0
var py := 0.0
var pz := 0.7
var tx := 0.0
var ty := 0.0
var tz := 0.4
var fov := 60.0
var yaw := -PI / 2.0          # chase camera: direction the camera looks (0 = east, PI/2 = south)
var chase_dist := 2.7
var focus: Ent = null         # follow this entity instead of the leader / active combatant
var frame_other: Ent = null   # dialogue partner
var anchor = null             # current room-camera tile (Vector2i) or null
var kind := "chase"
var shake_t := 0.0


func _init(g) -> void:
	game = g


func focus_ent() -> Ent:
	if focus != null:
		return focus
	if game.encounter != null and game.encounter.active != null:
		return game.encounter.active
	return game.world.leader_ent()


func update(delta: float) -> void:
	shake_t = maxf(0.0, shake_t - delta)
	if mode != "auto" or game.world.map == null:
		return
	var before := kind
	var d := desired()
	if d.is_empty():
		return
	var cut: bool = d.cut or (before != kind and (before == "room" or kind == "room"))
	if cut:
		_apply(d, 1.0)
	else:
		_apply(d, 1.0 - exp(-delta * 5.5))


## Jump straight to where the camera wants to be (after loading a map or ending a cutscene).
func snap() -> void:
	if game.world.map == null:
		return
	var d := desired()
	if not d.is_empty():
		_apply(d, 1.0)


func rotate(amount: float) -> void:
	yaw = wrapf(yaw + amount, -PI, PI)


func _apply(d: Dictionary, k: float) -> void:
	px = lerpf(px, d.px, k)
	py = lerpf(py, d.py, k)
	pz = lerpf(pz, d.pz, k)
	tx = lerpf(tx, d.tx, k)
	ty = lerpf(ty, d.ty, k)
	tz = lerpf(tz, d.tz, k)
	fov = lerpf(fov, d.fov, k)


func desired() -> Dictionary:
	var f := focus_ent()
	if f == null:
		return {}
	var map: MapData = game.world.map
	if frame_other != null and frame_other != f:
		var a := f.pos()
		var b := frame_other.pos()
		var dir := (a - b).normalized() if a.distance_to(b) > 0.05 else Vector2(0, 1)
		var side := Vector2(-dir.y, dir.x)
		var p := _pull(a, a + dir * 2.3 + side * 1.2)
		kind = "frame"
		return {"px": p.x, "py": p.y, "pz": 0.72, "tx": lerpf(a.x, b.x, 0.75), "ty": lerpf(a.y, b.y, 0.75), "tz": 0.42, "fov": 50.0, "cut": false}
	if not prefer_chase and not map.cameras.is_empty():
		var best = _pick_anchor(f)
		if best != null:
			var cut: bool = anchor == null or anchor != best
			anchor = best
			kind = "room"
			var p := Vector2(best.x + 0.5, best.y + 0.5)
			var dist := maxf(p.distance_to(f.pos()), 0.5)
			var fv := clampf(rad_to_deg(2.0 * atan(2.1 / dist)), 24.0, 62.0)
			return {"px": p.x, "py": p.y, "pz": clampf(map.wall_height * 0.82, 0.6, 1.5), "tx": f.x, "ty": f.y, "tz": 0.38, "fov": fv, "cut": cut}
	anchor = null
	kind = "chase"
	var fwd := Vector2(cos(yaw), sin(yaw))
	var cp := _pull(f.pos(), f.pos() - fwd * chase_dist)
	return {"px": cp.x, "py": cp.y, "pz": minf(0.8, map.wall_height * 0.85), "tx": f.x + fwd.x * 0.8, "ty": f.y + fwd.y * 0.8, "tz": 0.34, "fov": 62.0, "cut": false}


func _pick_anchor(f: Ent):
	var map: MapData = game.world.map
	var fc := f.cell()
	var best = null
	var best_score := 1.0e9
	for c in map.cameras:
		var d := Vector2(c.x + 0.5, c.y + 0.5).distance_to(f.pos())
		if d < 2.0 or d > 13.0:
			continue   # too close fills the screen with one sprite; too far is unreadable
		if not Grid.line_of_sight(map, c, fc):
			continue
		var score := absf(d - 4.5)
		if anchor != null and c == anchor:
			score -= 2.5
		if score < best_score:
			best = c
			best_score = score
	return best


## Walks from `from` towards `to` and stops before the first wall, so the camera never ends up inside one.
func _pull(from: Vector2, to: Vector2) -> Vector2:
	var map: MapData = game.world.map
	var total := from.distance_to(to)
	if total < 0.01:
		return to
	var dir := (to - from) / total
	var ok := 0.0
	var d := 0.1
	while d <= total + 0.001:
		var p := from + dir * (d + 0.2)
		if map.is_solid(floori(p.x), floori(p.y)):
			break
		ok = d
		d += 0.1
	return from + dir * maxf(ok, 0.35)


## Screen shake for `seconds` (the view adds a small random offset while shake_t > 0).
func shake(seconds: float) -> void:
	shake_t = maxf(shake_t, seconds)
