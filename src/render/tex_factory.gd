class_name TexFactory
extends RefCounted
## Procedural 64x64 wall / floor / ceiling textures in a 16-bit style, so campaigns need no art files.
## Maps refer to textures by name ("stone", "cobble", "door_wood"...). A campaign can also ship its own
## PNG: put it in campaigns/<id>/textures/<name>.png and it wins over the built-in one.
##
## To add a texture: add its name to NAMES and a branch in _pixel() returning the colour at (x, y).
## Keep patterns tileable: use x % 64 / y % 64 arithmetic and _n() (tileable noise).

const SIZE := 64
const NAMES := [
	"stone", "stone_mossy", "brick", "crypt", "crypt_skull", "cave", "timber", "timber_window", "wood_wall", "plaster",
	"palisade", "hedge", "canvas", "bookshelf_wall", "door_wood", "door_iron",
	"flagstone", "cobble", "plank", "dirt", "grass", "road", "carpet", "water", "moss_floor", "crypt_floor", "thatch", "rock_ceiling",
]

static var _textures: Dictionary = {}
static var _materials: Dictionary = {}
static var campaign_dir := ""


static func has(tex_name: String) -> bool:
	return tex_name in NAMES or (campaign_dir != "" and FileAccess.file_exists("%s/textures/%s.png" % [campaign_dir, tex_name]))


static func texture(tex_name: String) -> ImageTexture:
	if _textures.has(tex_name):
		return _textures[tex_name]
	var img: Image = null
	var custom := "%s/textures/%s.png" % [campaign_dir, tex_name]
	if campaign_dir != "" and FileAccess.file_exists(custom):
		img = Image.load_from_file(custom)
	if img == null:
		img = _generate(tex_name)
	var tex := ImageTexture.create_from_image(img)
	_textures[tex_name] = tex
	return tex


## Unshaded material: brightness comes from the vertex colours baked by RoomBuilder (per-tile light).
static func material(tex_name: String) -> StandardMaterial3D:
	if _materials.has(tex_name):
		return _materials[tex_name]
	var m := StandardMaterial3D.new()
	m.albedo_texture = texture(tex_name)
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.vertex_color_use_as_albedo = true
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	_materials[tex_name] = m
	return m


static func clear_cache() -> void:
	_textures.clear()
	_materials.clear()


static func _generate(tex_name: String) -> Image:
	var known: bool = tex_name in NAMES
	if not known:
		push_warning("Unknown texture '%s' (showing a checkerboard)" % tex_name)
	var data := PackedByteArray()
	data.resize(SIZE * SIZE * 4)
	var i := 0
	for y in SIZE:
		for x in SIZE:
			var c: Color = _pixel(tex_name, x, y) if known else (Color.MAGENTA if (x / 8 + y / 8) % 2 == 0 else Color.BLACK)
			data[i] = int(clampf(c.r, 0.0, 1.0) * 255.0)
			data[i + 1] = int(clampf(c.g, 0.0, 1.0) * 255.0)
			data[i + 2] = int(clampf(c.b, 0.0, 1.0) * 255.0)
			data[i + 3] = 255
			i += 4
	return Image.create_from_data(SIZE, SIZE, false, Image.FORMAT_RGBA8, data)


## Tileable value noise in 0..1 (integer hash of the wrapped coordinates).
static func _n(x: int, y: int, s: int = 0) -> float:
	var h: int = (posmod(x, SIZE) * 374761393 + posmod(y, SIZE) * 668265263 + s * 982451653) & 0x7fffffff
	h = ((h ^ (h >> 13)) * 1274126177) & 0x7fffffff
	return float((h ^ (h >> 16)) & 0xffff) / 65535.0


## Chunky noise: the same value across cell x cell pixel blocks (keeps the pixel-art look).
static func _nb(x: int, y: int, cell: int, s: int = 0) -> float:
	return _n(posmod(x, SIZE) / cell, posmod(y, SIZE) / cell, s + 17)


static func _mix(a: Color, b: Color, t: float) -> Color:
	return a.lerp(b, clampf(t, 0.0, 1.0))


## Blocks laid in rows: returns [edge (0..1, 1 = mortar line), block id noise].
static func _blocks(x: int, y: int, bw: int, bh: int, stagger: bool, s: int) -> Array:
	var row := y / bh
	var xo := x + (bw / 2 if (stagger and row % 2 == 1) else 0)
	var bx := posmod(xo, SIZE) / bw
	var lx := posmod(xo, bw)
	var ly := y % bh
	var edge := 1.0 if (lx == 0 or ly == 0) else (0.45 if (lx == 1 or ly == 1) else 0.0)
	return [edge, _n(bx, row, s)]


static func _pixel(tex_name: String, x: int, y: int) -> Color:
	var n := _n(x, y)
	match tex_name:
		"stone", "stone_mossy":
			var b := _blocks(x, y, 16, 16, true, 3)
			var c := _mix(Color("#6f6a66"), Color("#8f8982"), b[1]) * (0.9 + 0.2 * n)
			if tex_name == "stone_mossy" and _nb(x, y, 4, 5) + float(y) / 90.0 > 1.05:
				c = _mix(c, Color("#4f6b38"), 0.7)
			return _mix(c, Color("#3d3936"), b[0])
		"brick":
			var b := _blocks(x, y, 16, 8, true, 7)
			var c := _mix(Color("#8a4534"), Color("#a85a40"), b[1]) * (0.9 + 0.2 * n)
			return _mix(c, Color("#4a4038"), b[0])
		"crypt", "crypt_skull":
			var b := _blocks(x, y, 32, 16, true, 11)
			var c := _mix(Color("#4d4b55"), Color("#63606b"), b[1]) * (0.88 + 0.24 * n)
			if _nb(x, y, 2, 9) > 0.93:
				c = c.darkened(0.3)
			c = _mix(c, Color("#26242c"), b[0])
			if tex_name == "crypt_skull":
				var dx := x - 32
				var dy := y - 30
				if absi(dx) <= 13 and dy >= -15 and dy <= 17:
					c = Color("#1c1a22")
					if dx * dx + (dy + 2) * (dy + 2) <= 81 or (absi(dx) <= 5 and dy > 5 and dy <= 12):
						c = Color("#cfc8b4") * (0.9 + 0.15 * n)
						if (absi(absi(dx) - 4) <= 2 and absi(dy + 2) <= 2) or (absi(dx) <= 1 and dy >= 3 and dy <= 5):
							c = Color("#1c1a22")
						if dy > 7 and dy <= 12 and posmod(dx, 3) == 0:
							c = Color("#1c1a22")
			return c
		"cave", "rock_ceiling":
			var v := _nb(x, y, 8, 1) * 0.5 + _nb(x, y, 4, 2) * 0.3 + n * 0.2
			var c := _mix(Color("#3f3a36"), Color("#75695c"), v)
			return c.darkened(0.25) if tex_name == "rock_ceiling" else c
		"plaster":
			return _mix(Color("#cdbf9f"), Color("#ddd0b2"), _nb(x, y, 4, 3)) * (0.94 + 0.1 * n)
		"timber", "timber_window":
			var c := _mix(Color("#cdbf9f"), Color("#ddd0b2"), _nb(x, y, 4, 3)) * (0.94 + 0.1 * n)
			var beam: bool = x < 5 or x >= 59 or y < 5 or y >= 59 or absi(y - 32) < 3
			if tex_name == "timber" and absi((x - 32) - (y - 32) * (1 if y < 32 else -1)) < 3 and y > 5 and y < 59:
				beam = true
			if tex_name == "timber_window" and x >= 20 and x < 44 and y >= 12 and y < 30:
				c = Color("#ffd36a") * (0.85 + 0.2 * n) if (x != 31 and x != 32 and y != 20 and y != 21) else Color("#4b3220")
				if x == 20 or x == 43 or y == 12 or y == 29:
					c = Color("#4b3220")
				return c
			if beam:
				return _mix(Color("#4b3220"), Color("#6a4a2e"), _nb(x, y, 2, 4)) * (0.9 + 0.2 * n)
			return c
		"wood_wall", "plank":
			var horizontal: bool = tex_name == "plank"
			var u := y if horizontal else x
			var v2 := x if horizontal else y
			var board := u / 8
			var c := _mix(Color("#6b4a2c"), Color("#8a6238"), _n(board, 0, 21)) * (0.9 + 0.14 * _n(v2 / 3, board, 5) + 0.08 * n)
			if u % 8 == 0:
				c = Color("#3a2817")
			if posmod(v2 + board * 23, 64) == 0:
				c = Color("#3a2817")
			return c
		"palisade":
			var log_i := x / 8
			var lx := x % 8
			var c := _mix(Color("#5c3f24"), Color("#7a5632"), _n(log_i, 0, 31)) * (0.75 + 0.07 * (4 - absi(lx - 3)) + 0.1 * n)
			if y < 6 and absi(lx - 3) > (y / 2 + 1):
				return Color("#2a2420")
			return c
		"hedge":
			var v := _nb(x, y, 4, 41) * 0.6 + n * 0.4
			return _mix(Color("#24451f"), Color("#4f8a3a"), v)
		"canvas":
			var c := _mix(Color("#b9a67c"), Color("#d6c69c"), _nb(x, y, 8, 51)) * (0.93 + 0.1 * n)
			return c.darkened(0.25) if x % 16 == 0 else c
		"bookshelf_wall":
			var shelf := y % 16
			if shelf >= 14 or x % 32 == 0:
				return Color("#4b3220")
			var book := x / 3
			var cols := [Color("#7a2a2a"), Color("#2a4a7a"), Color("#3a6a3a"), Color("#8a6a2a"), Color("#5a3a6a"), Color("#3d3d3d")]
			var c: Color = cols[int(_n(book, y / 16, 61) * 5.99)]
			if shelf < int(_n(book, y / 16, 62) * 4.0):
				return Color("#2a1c12")
			return c.darkened(0.3) if x % 3 == 0 else c * (0.9 + 0.2 * n)
		"door_wood", "door_iron":
			var iron: bool = tex_name == "door_iron"
			var c := (_mix(Color("#5a5d66"), Color("#767a85"), _nb(x, y, 4, 71)) if iron else _mix(Color("#6a4526"), Color("#845a30"), _n(x / 10, 0, 72))) * (0.9 + 0.15 * n)
			if not iron and x % 10 == 0:
				c = Color("#3a2614")
			if y == 12 or y == 13 or y == 50 or y == 51:
				c = Color("#2e2e34") if not iron else Color("#3a3d44")
			if x < 3 or x > 60 or y < 3:
				c = Color("#2f2118") if not iron else Color("#33363d")
			if absi(x - 50) < 3 and absi(y - 34) < 3:
				c = Color("#d2b04a")
			if (x % 12 == 6) and (y == 12 or y == 51):
				c = Color("#9a9aa2")
			return c
		"flagstone", "crypt_floor":
			var b := _blocks(x, y, 32, 32, false, 81)
			var dark: bool = tex_name == "crypt_floor"
			var c := _mix(Color("#4a4852") if dark else Color("#77726b"), Color("#5c5a66") if dark else Color("#928c84"), b[1]) * (0.88 + 0.22 * n)
			if _nb(x, y, 2, 83) > 0.95:
				c = c.darkened(0.25)
			return _mix(c, Color("#24222a") if dark else Color("#45413d"), b[0])
		"cobble":
			var cxn := (x + (8 if (y / 8) % 2 == 1 else 0)) % 16 - 8
			var cyn := y % 8 - 4
			var d := float(cxn * cxn) / 56.0 + float(cyn * cyn) / 14.0
			var c := _mix(Color("#6e6a70"), Color("#8e8a8c"), _n((x + (8 if (y / 8) % 2 == 1 else 0)) / 16, y / 8, 91)) * (1.05 - 0.25 * d + 0.1 * n)
			return Color("#3a3638") if d > 1.0 else c
		"dirt", "road":
			var v := _nb(x, y, 4, 101) * 0.5 + n * 0.5
			var c := _mix(Color("#5a4630"), Color("#7a6040"), v)
			if tex_name == "road":
				c = _mix(Color("#6b5a44"), Color("#8a765a"), v)
				if _nb(x, y, 2, 103) > 0.92:
					c = Color("#9a9288")
			return c
		"grass":
			var v := _nb(x, y, 4, 111) * 0.45 + n * 0.55
			var c := _mix(Color("#35652c"), Color("#5a9440"), v)
			if _n(x, y, 113) > 0.94:
				c = Color("#8fbf5a")
			return c
		"moss_floor":
			var b := _blocks(x, y, 32, 32, false, 121)
			var c := _mix(Color("#5d5a55"), Color("#74706a"), b[1]) * (0.9 + 0.2 * n)
			if _nb(x, y, 4, 123) > 0.55:
				c = _mix(c, Color("#44663a"), 0.65)
			return _mix(c, Color("#33302d"), b[0])
		"carpet":
			var c := _mix(Color("#7a1f28"), Color("#96303a"), _nb(x, y, 2, 131)) * (0.94 + 0.1 * n)
			var edge := mini(mini(x, 63 - x), mini(y, 63 - y))
			if edge >= 4 and edge < 7:
				c = Color("#d2b04a")
			if (absi(x - 32) + absi(y - 32)) % 16 == 0 and edge > 10:
				c = Color("#c08a3a")
			return c
		"water":
			var wv := sin((x + _nb(x, y, 8, 141) * 10.0) * 0.4) * 0.5 + 0.5
			var c := _mix(Color("#1f4a78"), Color("#2f6ea8"), wv * 0.6 + n * 0.2)
			if (y + int(wv * 3.0)) % 12 == 0 and n > 0.4:
				c = Color("#9fd0f0")
			return c
		"thatch":
			var c := _mix(Color("#8a7434"), Color("#b89a48"), _n(x / 2, y / 6, 151)) * (0.88 + 0.2 * n)
			return c.darkened(0.3) if y % 12 == 0 else c
	return Color.MAGENTA
