class_name Grid
extends RefCounted
## Grid maths on a MapData: pathfinding (A*), movement range, line of sight, distances. Pure logic.
## Tiles are Vector2i. One tile = one 5-ft square. Diagonal steps cost 1.5 (the Pathfinder
## "every second diagonal counts double" rule, averaged) and may not cut wall corners.
## `blocked` arguments are Callables: func(cell: Vector2i) -> bool.
## `corner` (optional, same shape) says which tiles are HARD corners that a diagonal step may not cut.
## Leave it out and every blocked tile is a hard corner. Combat passes "walls and props only", so a
## creature can step diagonally past another creature but never through the corner of a wall.

const DIRS := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1)]


## Chebyshev distance (adjacent = 1, including diagonals).
static func cheb(a: Vector2i, b: Vector2i) -> int:
	return maxi(absi(a.x - b.x), absi(a.y - b.y))


## Distance in squares using Pathfinder diagonal counting.
static func dist(a: Vector2i, b: Vector2i) -> int:
	var dx := absi(a.x - b.x)
	var dy := absi(a.y - b.y)
	return maxi(dx, dy) + floori(mini(dx, dy) / 2.0)


static func step_cost(a: Vector2i, b: Vector2i) -> float:
	return 1.5 if (a.x != b.x and a.y != b.y) else 1.0


static func path_cost(from: Vector2i, path: Array) -> float:
	var total := 0.0
	var prev := from
	for c in path:
		total += step_cost(prev, c)
		prev = c
	return total


static func _can_step(a: Vector2i, d: Vector2i, blocked: Callable, corner := Callable()) -> bool:
	var b := a + d
	if blocked.call(b):
		return false
	if d.x != 0 and d.y != 0:
		var hard: Callable = corner if corner.is_valid() else blocked
		if hard.call(Vector2i(a.x + d.x, a.y)) or hard.call(Vector2i(a.x, a.y + d.y)):
			return false
	return true


## A* path from `from` to `to`. Returns the tiles to walk (excluding `from`), or [] if unreachable.
## adjacent_ok = stop on any tile next to `to` (use when `to` is occupied, e.g. walking up to an NPC).
static func find_path(from: Vector2i, to: Vector2i, blocked: Callable, adjacent_ok := false, max_nodes := 3000, corner := Callable()) -> Array:
	if from == to or (adjacent_ok and cheb(from, to) <= 1):
		return []
	var open: Array = [[0.0, from]]
	var g := {from: 0.0}
	var prev := {}
	var closed := {}
	var visited := 0
	while not open.is_empty() and visited < max_nodes:
		var cur: Vector2i = open.pop_front()[1]
		if closed.has(cur):
			continue
		closed[cur] = true
		visited += 1
		if cur == to or (adjacent_ok and cheb(cur, to) <= 1):
			var path: Array = []
			var c := cur
			while c != from:
				path.push_front(c)
				c = prev[c]
			return path
		for d in DIRS:
			var nb: Vector2i = cur + d
			if closed.has(nb):
				continue
			if not _can_step(cur, d, blocked, corner):
				continue
			var ng: float = float(g[cur]) + step_cost(cur, nb)
			if not g.has(nb) or ng < float(g[nb]):
				g[nb] = ng
				prev[nb] = cur
				var f := ng + _heuristic(nb, to)
				var entry := [f, nb]
				open.insert(open.bsearch_custom(entry, func(a, b): return a[0] < b[0]), entry)
	return []


static func _heuristic(a: Vector2i, b: Vector2i) -> float:
	var dx := absi(a.x - b.x)
	var dy := absi(a.y - b.y)
	return maxi(dx, dy) + 0.5 * mini(dx, dy)


## Every tile reachable within `budget` movement. Returns {cell: {cost: float, prev: Vector2i}}.
static func reachable(from: Vector2i, budget: float, blocked: Callable, corner := Callable()) -> Dictionary:
	var out := {from: {"cost": 0.0, "prev": from}}
	var frontier: Array = [from]
	while not frontier.is_empty():
		var cur: Vector2i = frontier.pop_front()
		var base: float = out[cur].cost
		for d in DIRS:
			if not _can_step(cur, d, blocked, corner):
				continue
			var nb: Vector2i = cur + d
			var cost := base + step_cost(cur, nb)
			if cost > budget + 0.001:
				continue
			if not out.has(nb) or cost < float(out[nb].cost) - 0.001:
				out[nb] = {"cost": cost, "prev": cur}
				frontier.append(nb)
	return out


## Turns a reachable() result into the list of tiles to walk to reach `to`.
static func path_from(reach: Dictionary, to: Vector2i) -> Array:
	var path: Array = []
	if not reach.has(to):
		return path
	var c := to
	var guard := 0
	while reach[c].prev != c and guard < 500:
		path.push_front(c)
		c = reach[c].prev
		guard += 1
	return path


## True when no wall or closed door lies between the two tiles (their own tiles are ignored).
static func line_of_sight(map: MapData, a: Vector2i, b: Vector2i) -> bool:
	var x0 := a.x
	var y0 := a.y
	var dx := absi(b.x - a.x)
	var dy := -absi(b.y - a.y)
	var sx := 1 if a.x < b.x else -1
	var sy := 1 if a.y < b.y else -1
	var err := dx + dy
	while true:
		if not (x0 == a.x and y0 == a.y) and not (x0 == b.x and y0 == b.y):
			if map.is_solid(x0, y0):
				return false
		if x0 == b.x and y0 == b.y:
			break
		var e2 := 2 * err
		if e2 >= dy:
			err += dy
			x0 += sx
		if e2 <= dx:
			err += dx
			y0 += sy
	return true
