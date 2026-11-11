class_name Rng
extends RefCounted
## Random numbers for the whole game. Every dice roll goes through an Rng so tests can be deterministic.
##   var rng := Rng.new()            # random seed
##   var rng := Rng.new(1234)        # fixed seed
##   var rng := Rng.fixed([20, 3])   # die() returns 20, then 3, then `fallback` forever (for tests)

var _rng := RandomNumberGenerator.new()
var _queue: Array = []
var _fallback := 10
var scripted := false


func _init(seed_value: int = -1) -> void:
	if seed_value >= 0:
		_rng.seed = seed_value
	else:
		_rng.randomize()


static func fixed(values: Array, fallback := 10) -> Rng:
	var r := Rng.new(1)
	r.scripted = true
	r._queue = values.duplicate()
	r._fallback = fallback
	return r


## Roll one die with the given number of sides (1..sides).
func die(sides: int) -> int:
	if scripted:
		var v: int = _fallback
		if not _queue.is_empty():
			v = _queue.pop_front()
		return clampi(v, 1, sides)
	return _rng.randi_range(1, sides)


func randf() -> float:
	return 0.5 if scripted else _rng.randf()


func range_i(a: int, b: int) -> int:
	return a if scripted else _rng.randi_range(a, b)


func pick(arr: Array):
	if arr.is_empty():
		return null
	return arr[0] if scripted else arr[_rng.randi_range(0, arr.size() - 1)]


func chance(p: float) -> bool:
	return self.randf() < p
