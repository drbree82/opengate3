class_name MapData
extends RefCounted
## A parsed map. Maps are drawn as text rows where every character is looked up in a legend
## (see docs/CAMPAIGN_FORMAT.md, "Maps"). Pure logic - no nodes.
##
## Legend entry keys understood here:
##   wall: "<texture>"        solid wall block
##   floor / ceiling          textures for an open tile (fall back to map defaults; ceiling "sky" = open)
##   door: "<texture>"        closed door (solid until opened). locked: {dc, key, break, text}
##   void: true               nothing here (solid, not drawn)
##   blocked: true            open tile that cannot be walked on (water, pit edge)
##   entity: "<template id>"  spawn an entity here; other keys in the entry override the template
##   marker: "<name>"         named position scripts can refer to
##   trigger: "<id>"          run map.triggers[id] when the party leader steps here
##   exit: {map, marker}      walk here to travel
##   camera: true             a fixed "room camera" position

const VOID := {"void": true}
const MAP_KEYS := ["wall", "floor", "ceiling", "door", "locked", "void", "blocked", "entity", "marker", "trigger", "exit", "camera"]

var id := ""
var name := ""
var raw: Dictionary = {}
var w := 0
var h := 0
var wall_height := 1.0
var outdoor := false
var sky := ""
var ambient := 0.3
var ambient_color := Color.WHITE
var fog_color := Color.BLACK
var fog_dist := 14.0
var defaults: Dictionary = {}
var legend: Dictionary = {}
var rows: Array = []
var solid := PackedByteArray()
var opened: Dictionary = {}       # Vector2i -> true for doors that have been opened
var markers: Dictionary = {}      # name -> Array[Vector2i]
var placements: Array = []        # [{x, y, entity, overrides}]
var cameras: Array = []           # Array[Vector2i]
var errors: Array = []


static func parse(data: Dictionary, map_id: String) -> MapData:
	var m := MapData.new()
	m.id = map_id
	m.raw = data
	m.name = data.get("name", Util.title(map_id))
	m.wall_height = float(data.get("wallHeight", 1.0))
	m.outdoor = data.get("outdoor", false)
	m.sky = data.get("sky", "day" if m.outdoor else "")
	m.ambient = float(data.get("ambient", 0.9 if m.outdoor else 0.3))
	m.ambient_color = Util.color(data.get("ambientColor", "#ffffff"))
	var fog: Dictionary = data.get("fog", {})
	m.fog_color = Util.color(fog.get("color", "#000000"), Color.BLACK)
	m.fog_dist = float(fog.get("distance", 16))
	m.defaults = data.get("defaults", {})
	m.legend = data.get("legend", {}).duplicate(true)
	if not m.legend.has("#"):
		m.legend["#"] = {"wall": m.defaults.get("wall", "stone")}
	if not m.legend.has("."):
		m.legend["."] = {}
	if not m.legend.has(" "):
		m.legend[" "] = VOID
	var src: Array = data.get("rows", [])
	m.h = src.size()
	for r in src:
		m.w = maxi(m.w, str(r).length())
	for i in src.size():
		var r := str(src[i])
		if r.length() != m.w:
			m.errors.append("row %d is %d characters long, expected %d" % [i, r.length(), m.w])
		m.rows.append(r.rpad(m.w, " "))
	if m.w == 0 or m.h == 0:
		m.errors.append("map has no rows")
	m.solid.resize(m.w * m.h)
	for y in m.h:
		for x in m.w:
			var ch: String = m.rows[y][x]
			if not m.legend.has(ch):
				m.errors.append("unknown map character '%s' at x=%d y=%d (add it to the legend)" % [ch, x, y])
				m.legend[ch] = VOID
			var e: Dictionary = m.legend[ch]
			m._refresh_solid(x, y)
			if e.has("entity"):
				var overrides := {}
				for k in e:
					if not (k in MAP_KEYS):
						overrides[k] = e[k]
				m.placements.append({"x": x, "y": y, "entity": e.entity, "overrides": overrides})
			if e.has("marker"):
				if not m.markers.has(e.marker):
					m.markers[e.marker] = []
				m.markers[e.marker].append(Vector2i(x, y))
			if e.get("camera", false):
				m.cameras.append(Vector2i(x, y))
	# Optional extras by coordinate: "markers": {"name": [x, y]} and "cameras": [[x, y], ...].
	# Prefer legend characters (they move with the map when rows are edited).
	var extra: Dictionary = data.get("markers", {})
	for mk in extra:
		if not m.markers.has(mk):
			m.markers[mk] = []
		m.markers[mk].append(Vector2i(int(extra[mk][0]), int(extra[mk][1])))
	for c in data.get("cameras", []):
		m.cameras.append(Vector2i(int(c[0]), int(c[1])))
	return m


func in_bounds(x: int, y: int) -> bool:
	return x >= 0 and y >= 0 and x < w and y < h


func entry(x: int, y: int) -> Dictionary:
	if not in_bounds(x, y):
		return VOID
	return legend.get(rows[y][x], VOID)


func _refresh_solid(x: int, y: int) -> void:
	var e := entry(x, y)
	var s: bool = e.has("wall") or e.get("void", false) or (e.has("door") and not opened.has(Vector2i(x, y)))
	solid[y * w + x] = 1 if s else 0


## Walls, closed doors, void and everything outside the map.
func is_solid(x: int, y: int) -> bool:
	if not in_bounds(x, y):
		return true
	return solid[y * w + x] == 1


func blocks_move(x: int, y: int) -> bool:
	return is_solid(x, y) or entry(x, y).get("blocked", false)


func is_void(x: int, y: int) -> bool:
	return entry(x, y).get("void", false)


func wall_tex(x: int, y: int) -> String:
	return entry(x, y).get("wall", "")


func floor_tex(x: int, y: int) -> String:
	var e := entry(x, y)
	if e.has("wall") or e.get("void", false):
		return ""
	return e.get("floor", defaults.get("floor", "flagstone"))


func ceil_tex(x: int, y: int) -> String:
	var e := entry(x, y)
	if e.has("wall") or e.get("void", false):
		return ""
	var c: String = e.get("ceiling", defaults.get("ceiling", "" if outdoor else "plank"))
	return "" if c in ["sky", "none"] else c


## The closed door at this tile, or null.
func door(x: int, y: int):
	var e := entry(x, y)
	if e.has("door") and not opened.has(Vector2i(x, y)):
		return e
	return null


func has_door(x: int, y: int) -> bool:
	return entry(x, y).has("door")


func open_door(x: int, y: int) -> void:
	opened[Vector2i(x, y)] = true
	_refresh_solid(x, y)


## Replaces the character at a tile (e.g. turn a wall into floor). The new char must be in the legend.
func set_char(x: int, y: int, ch: String) -> void:
	if not in_bounds(x, y) or not legend.has(ch):
		return
	var r: String = rows[y]
	rows[y] = r.substr(0, x) + ch + r.substr(x + 1)
	_refresh_solid(x, y)


## Centre of the nth tile carrying this marker, or null.
func marker_pos(marker_name: String, index := 0):
	var list: Array = markers.get(marker_name, [])
	if list.is_empty():
		return null
	var c: Vector2i = list[mini(index, list.size() - 1)]
	return Vector2(c.x + 0.5, c.y + 0.5)


func trigger_at(x: int, y: int) -> String:
	return entry(x, y).get("trigger", "")


func exit_at(x: int, y: int):
	return entry(x, y).get("exit")


## First open tile (used when a start marker is missing).
func any_open() -> Vector2:
	for y in h:
		for x in w:
			if not blocks_move(x, y):
				return Vector2(x + 0.5, y + 0.5)
	return Vector2(0.5, 0.5)
