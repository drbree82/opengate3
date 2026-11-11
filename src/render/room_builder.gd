class_name RoomBuilder
extends RefCounted
## Turns a 2D MapData grid into 3D geometry, Doom-style: every wall tile becomes a block, every open
## tile gets a floor (and a ceiling unless it is open to the sky). One mesh surface per texture.
##
## Lighting is BAKED into vertex colours (no realtime lights): compute_light() floods light outwards
## from every light source through open tiles, so walls cast "shadows" and torches glow. The same
## light grid tints the sprites (world_view.gd). This keeps the retro look and runs on any GPU.
##
## Coordinates: tile (x, y) covers world X in [x, x+1], Z in [y, y+1]; Y is up; floor at Y = 0.


## Per-tile light colour for the whole map (index = y * w + x).
static func compute_light(map: MapData, ents: Array) -> PackedColorArray:
	var light := PackedColorArray()
	light.resize(map.w * map.h)
	var base := Color(map.ambient_color.r * map.ambient, map.ambient_color.g * map.ambient, map.ambient_color.b * map.ambient)
	light.fill(base)
	for e in ents:
		if e.light == null or e.hidden:
			continue
		var radius: float = float(e.light.get("radius", 5))
		var col := Util.color(e.light.get("color", "#ffd0a0"))
		var power: float = float(e.light.get("power", 1.0))
		var start: Vector2i = e.cell()
		if not map.in_bounds(start.x, start.y):
			continue
		var dist := {start: 0.0}
		var frontier: Array = [start]
		while not frontier.is_empty():
			var cur: Vector2i = frontier.pop_front()
			var d: float = dist[cur]
			var k := pow(1.0 - d / radius, 1.4) * power
			var i := cur.y * map.w + cur.x
			var c := light[i]
			light[i] = Color(minf(1.25, c.r + col.r * k), minf(1.25, c.g + col.g * k), minf(1.25, c.b + col.b * k))
			if map.is_solid(cur.x, cur.y) and cur != start:
				continue   # light reaches a wall face but does not pass through it
			for dir in Grid.DIRS:
				var nb: Vector2i = cur + dir
				if not map.in_bounds(nb.x, nb.y):
					continue
				var nd := d + (1.4 if (dir.x != 0 and dir.y != 0) else 1.0)
				if nd >= radius or (dist.has(nb) and float(dist[nb]) <= nd):
					continue
				dist[nb] = nd
				frontier.append(nb)
	return light


static func light_at(map: MapData, light: PackedColorArray, x: int, y: int) -> Color:
	if not map.in_bounds(x, y) or light.is_empty():
		return Color(map.ambient, map.ambient, map.ambient)
	return light[y * map.w + x]


## Light at a tile CORNER = average of the open tiles touching it (gives smooth gradients on floors).
static func _corner(map: MapData, light: PackedColorArray, cx: int, cy: int) -> Color:
	var sum := Color(0, 0, 0)
	var n := 0
	for off in [Vector2i(-1, -1), Vector2i(0, -1), Vector2i(-1, 0), Vector2i(0, 0)]:
		var x: int = cx + off.x
		var y: int = cy + off.y
		if map.in_bounds(x, y) and _open(map, x, y):
			sum += light[y * map.w + x]
			n += 1
	if n == 0:
		return Color(map.ambient, map.ambient, map.ambient)
	return Color(sum.r / n, sum.g / n, sum.b / n)


## Open for rendering purposes: has a floor (doors count, open or closed).
static func _open(map: MapData, x: int, y: int) -> bool:
	return map.in_bounds(x, y) and map.floor_tex(x, y) != ""


## Builds the room mesh. Returns a MeshInstance3D (walls, floors, ceilings).
static func build_mesh(map: MapData, light: PackedColorArray) -> MeshInstance3D:
	var tools := {}   # texture name -> SurfaceTool
	var wh := map.wall_height
	var st_for := func(tex: String) -> SurfaceTool:
		if not tools.has(tex):
			var st := SurfaceTool.new()
			st.begin(Mesh.PRIMITIVE_TRIANGLES)
			tools[tex] = st
		return tools[tex]

	for y in map.h:
		for x in map.w:
			if _open(map, x, y):
				var c00 := _corner(map, light, x, y)
				var c10 := _corner(map, light, x + 1, y)
				var c11 := _corner(map, light, x + 1, y + 1)
				var c01 := _corner(map, light, x, y + 1)
				_quad(st_for.call(map.floor_tex(x, y)),
					Vector3(x, 0, y), Vector3(x + 1, 0, y), Vector3(x + 1, 0, y + 1), Vector3(x, 0, y + 1),
					Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1), c00, c10, c11, c01)
				var ceil_name := map.ceil_tex(x, y)
				if ceil_name != "":
					_quad(st_for.call(ceil_name),
						Vector3(x, wh, y), Vector3(x + 1, wh, y), Vector3(x + 1, wh, y + 1), Vector3(x, wh, y + 1),
						Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1), c00 * 0.75, c10 * 0.75, c11 * 0.75, c01 * 0.75)
				continue
			var tex := map.wall_tex(x, y)
			if tex == "":
				continue
			var st: SurfaceTool = st_for.call(tex)
			var v0 := 1.0 - wh
			# north face (seen from y - 1)
			if _open(map, x, y - 1):
				_wall(st, Vector3(x + 1, 0, y), Vector3(x, 0, y), wh, v0, _corner(map, light, x + 1, y), _corner(map, light, x, y))
			# south face
			if _open(map, x, y + 1):
				_wall(st, Vector3(x, 0, y + 1), Vector3(x + 1, 0, y + 1), wh, v0, _corner(map, light, x, y + 1), _corner(map, light, x + 1, y + 1))
			# west face
			if _open(map, x - 1, y):
				_wall(st, Vector3(x, 0, y), Vector3(x, 0, y + 1), wh, v0, _corner(map, light, x, y), _corner(map, light, x, y + 1))
			# east face
			if _open(map, x + 1, y):
				_wall(st, Vector3(x + 1, 0, y + 1), Vector3(x + 1, 0, y), wh, v0, _corner(map, light, x + 1, y + 1), _corner(map, light, x + 1, y))

	var mesh := ArrayMesh.new()
	var names: Array = tools.keys()
	names.sort()
	for tex in names:
		tools[tex].commit(mesh)
		mesh.surface_set_material(mesh.get_surface_count() - 1, TexFactory.material(tex))
	var mi := MeshInstance3D.new()
	mi.name = "Room"
	mi.mesh = mesh
	return mi


## One wall face from bottom-left `a` to bottom-right `b` (as seen by the viewer), `wh` high.
static func _wall(st: SurfaceTool, a: Vector3, b: Vector3, wh: float, v0: float, ca: Color, cb: Color) -> void:
	var up := Vector3(0, wh, 0)
	_quad(st, a + up, b + up, b, a, Vector2(0, v0), Vector2(1, v0), Vector2(1, 1), Vector2(0, 1), ca * 0.82, cb * 0.82, cb, ca)


static func _quad(st: SurfaceTool, p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, u0: Vector2, u1: Vector2, u2: Vector2, u3: Vector2, c0: Color, c1: Color, c2: Color, c3: Color) -> void:
	var pts := [p0, p1, p2, p0, p2, p3]
	var uvs := [u0, u1, u2, u0, u2, u3]
	var cols := [c0, c1, c2, c0, c2, c3]
	for i in 6:
		var c: Color = cols[i]
		st.set_color(Color(c.r, c.g, c.b, 1.0))
		st.set_uv(uvs[i])
		st.add_vertex(pts[i])


## Closed doors are separate thin slabs so they can vanish when opened.
static func build_doors(map: MapData, light: PackedColorArray) -> Node3D:
	var root := Node3D.new()
	root.name = "Doors"
	for y in map.h:
		for x in map.w:
			var d = map.door(x, y)
			if d == null:
				continue
			var along_x: bool = map.is_solid(x - 1, y) and map.is_solid(x + 1, y) and not map.has_door(x - 1, y)
			var box := BoxMesh.new()
			box.size = Vector3(1.0, map.wall_height, 0.14) if along_x else Vector3(0.14, map.wall_height, 1.0)
			var mat: StandardMaterial3D = TexFactory.material(d.door).duplicate()
			mat.vertex_color_use_as_albedo = false
			var l := _door_light(map, light, x, y)
			mat.albedo_color = Color(minf(1.0, l.r), minf(1.0, l.g), minf(1.0, l.b))
			box.material = mat
			var mi := MeshInstance3D.new()
			mi.mesh = box
			mi.position = Vector3(x + 0.5, map.wall_height / 2.0, y + 0.5)
			root.add_child(mi)
	return root


static func _door_light(map: MapData, light: PackedColorArray, x: int, y: int) -> Color:
	var best := light_at(map, light, x, y)
	for dir in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var nx: int = x + dir.x
		var ny: int = y + dir.y
		if map.in_bounds(nx, ny) and not map.is_solid(nx, ny):
			var c := light_at(map, light, nx, ny)
			if c.v > best.v:
				best = c
	return best


## Translucent floor overlays (movement range, targets). cells: {Vector2i: Color}
static func build_highlights(cells: Dictionary) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	if cells.is_empty():
		return mesh
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for cell in cells:
		var c: Color = cells[cell]
		var m := 0.06
		var y := 0.02
		var pts := [Vector3(cell.x + m, y, cell.y + m), Vector3(cell.x + 1 - m, y, cell.y + m), Vector3(cell.x + 1 - m, y, cell.y + 1 - m), Vector3(cell.x + m, y, cell.y + 1 - m)]
		for i in [0, 1, 2, 0, 2, 3]:
			st.set_color(c)
			st.add_vertex(pts[i])
	st.commit(mesh)
	return mesh
