class_name Anims
extends RefCounted
## Minimal tween runner that works on plain RefCounted objects (entities, the camera rig).
## The engine never uses Godot's SceneTreeTween so that all game logic can run headless:
## when game.instant is true (tests) or a cutscene is being skipped, values are applied immediately.
##
##   await game.anims.run(ent, {"x": 4.5, "y": 2.5}, 0.3)     # move over 0.3 s, then continue


class Item extends RefCounted:
	signal done
	var target
	var from: Dictionary = {}
	var to: Dictionary = {}
	var t := 0.0
	var dur := 1.0
	var ease_kind := "inout"


var game
var items: Array = []


func _init(g) -> void:
	game = g


func run(target, props: Dictionary, dur: float, ease_kind := "inout") -> void:
	if game.instant or dur <= 0.0 or (game.in_cutscene and game.skip_cutscene):
		for p in props:
			target.set(p, props[p])
		return
	var it := Item.new()
	it.target = target
	it.to = props
	for p in props:
		it.from[p] = target.get(p)
	it.dur = dur
	it.ease_kind = ease_kind
	items.append(it)
	await it.done


func update(delta: float) -> void:
	if items.is_empty():
		return
	for it in items.duplicate():
		it.t += delta
		var k := clampf(it.t / it.dur, 0.0, 1.0)
		var e := _ease(k, it.ease_kind)
		for p in it.to:
			it.target.set(p, lerp(it.from[p], it.to[p], e))
		if k >= 1.0:
			items.erase(it)
			it.done.emit()


## Completes every running animation right now (used when a cutscene is skipped).
func finish_all() -> void:
	for it in items.duplicate():
		for p in it.to:
			it.target.set(p, it.to[p])
		items.erase(it)
		it.done.emit()


static func _ease(k: float, kind: String) -> float:
	match kind:
		"linear":
			return k
		"in":
			return k * k
		"out":
			return 1.0 - (1.0 - k) * (1.0 - k)
	return k * k * (3.0 - 2.0 * k)
