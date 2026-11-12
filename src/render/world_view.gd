class_name WorldView
extends Node3D
## Draws game.world in 3D. Lives inside the low-resolution SubViewport of the view panel, which is
## what gives the picture its chunky 16-bit look.
##   - the room mesh comes from RoomBuilder (rebuilt when world.rebuilt fires)
##   - every Ent gets a billboard Sprite3D that always faces the camera (synced on world.ents_changed)
##   - the Camera3D copies game.cam (CamRig) every frame
## It also answers "what is under the mouse?" (pick) for the UI. No game rules live here.

var game: Game
var camera: Camera3D
var env: Environment
var room: MeshInstance3D
var doors: Node3D
var sprites_root: Node3D
var highlight_mi: MeshInstance3D
var sky_mi: MeshInstance3D
var light := PackedColorArray()
var nodes: Dictionary = {}        # Ent -> {sprite: Sprite3D, shadow: MeshInstance3D, key: String, set: Dictionary}
var _room_dirty := true
var _hl_key := ""
var _shadow_mat: StandardMaterial3D
var _glow_tex: ImageTexture
static var _sky_cache: Dictionary = {}


func setup(g: Game) -> void:
	game = g
	camera = Camera3D.new()
	camera.near = 0.05
	camera.far = 150.0
	add_child(camera)
	camera.current = true
	var we := WorldEnvironment.new()
	env = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color.BLACK
	we.environment = env
	add_child(we)
	sprites_root = Node3D.new()
	sprites_root.name = "Sprites"
	add_child(sprites_root)
	highlight_mi = MeshInstance3D.new()
	var hm := StandardMaterial3D.new()
	hm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	hm.vertex_color_use_as_albedo = true
	hm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	hm.cull_mode = BaseMaterial3D.CULL_DISABLED
	hm.disable_fog = true
	highlight_mi.material_override = hm
	add_child(highlight_mi)
	_shadow_mat = StandardMaterial3D.new()
	_shadow_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_shadow_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_shadow_mat.albedo_texture = _blob_texture(Color(0, 0, 0, 0.55))
	_shadow_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	_glow_tex = _blob_texture(Color(1, 1, 1, 1))
	game.world.rebuilt.connect(func(): _room_dirty = true)
	game.world.ents_changed.connect(_sync)
	game.map_loaded.connect(_on_map_loaded)


func _on_map_loaded() -> void:
	_room_dirty = true
	_sync()


func _process(_delta: float) -> void:
	if game == null or game.world.map == null:
		return
	if _room_dirty:
		_rebuild()
	_update_camera()
	_update_sprites()
	_update_highlights()


# ----------------------------------------------------------------------------------------------
# Room
# ----------------------------------------------------------------------------------------------

func _rebuild() -> void:
	_room_dirty = false
	var map: MapData = game.world.map
	TexFactory.campaign_dir = game.campaign.get("dir", "")
	SpriteFactory.campaign_dir = game.campaign.get("dir", "")
	light = RoomBuilder.compute_light(map, game.world.ents)
	if room != null:
		room.queue_free()
	room = RoomBuilder.build_mesh(map, light)
	add_child(room)
	if doors != null:
		doors.queue_free()
	doors = RoomBuilder.build_doors(map, light)
	add_child(doors)
	env.fog_enabled = true
	env.fog_light_color = map.fog_color
	env.fog_light_energy = 1.0
	env.fog_sun_scatter = 0.0
	env.fog_density = 2.0 / maxf(4.0, map.fog_dist)
	env.fog_sky_affect = 0.0
	env.background_color = map.fog_color
	if sky_mi != null:
		sky_mi.queue_free()
		sky_mi = null
	if map.sky != "":
		_build_sky(map.sky)


func _build_sky(kind: String) -> void:
	var cyl := CylinderMesh.new()
	cyl.top_radius = 90.0
	cyl.bottom_radius = 90.0
	cyl.height = 90.0
	cyl.radial_segments = 24
	cyl.cap_top = false
	cyl.cap_bottom = false
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_texture = _sky_texture(kind)
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.disable_fog = true
	m.uv1_scale = Vector3(2, 1, 1)
	cyl.material = m
	sky_mi = MeshInstance3D.new()
	sky_mi.mesh = cyl
	add_child(sky_mi)


## Panorama strip: sky gradient, stars or clouds, and a silhouette of far hills along the horizon.
static func _sky_texture(kind: String) -> ImageTexture:
	if _sky_cache.has(kind):
		return _sky_cache[kind]
	var w := 256
	var h := 128
	var top := Color("#3f78c8")
	var low := Color("#a8d0f0")
	var hills := Color("#4a6a58")
	var stars := 0.0
	var clouds := 0.5
	match kind:
		"dusk":
			top = Color("#2a2450")
			low = Color("#e8854a")
			hills = Color("#2a2030")
			stars = 0.35
			clouds = 0.3
		"night":
			top = Color("#070a1c")
			low = Color("#1c2a4a")
			hills = Color("#0a0c14")
			stars = 1.0
			clouds = 0.0
		"overcast":
			top = Color("#5a6068")
			low = Color("#9aa0a4")
			hills = Color("#3c4448")
			clouds = 0.0
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var horizon := h / 2 + 6
	for y in h:
		var t := clampf(float(y) / horizon, 0.0, 1.0)
		var row := top.lerp(low, t * t)
		img.fill_rect(Rect2i(0, y, w, 1), row if y < horizon else hills.darkened(0.3))
	var rng := RandomNumberGenerator.new()
	rng.seed = kind.hash()
	for i in int(220 * stars):
		var sy := rng.randi_range(0, horizon - 12)
		img.set_pixel(rng.randi_range(0, w - 1), sy, Color(1, 1, 0.9, 1).darkened(rng.randf() * 0.5))
	if kind == "night" or kind == "dusk":
		var mx := 60
		var my := 22
		for dy in range(-5, 6):
			for dx in range(-5, 6):
				if dx * dx + dy * dy <= 25 and (dx + 2) * (dx + 2) + (dy - 1) * (dy - 1) > 16:
					img.set_pixel(mx + dx, my + dy, Color("#f0ecd0"))
	for i in int(14 * clouds):
		var cx := rng.randi_range(0, w - 1)
		var cy := rng.randi_range(8, horizon - 22)
		var cw := rng.randi_range(14, 34)
		for k in 3:
			var ww := cw - k * 8
			if ww > 0:
				var c := low.lerp(Color.WHITE, 0.55)
				c.a = 1.0
				for x in range(cx - ww / 2, cx + ww / 2):
					img.fill_rect(Rect2i(posmod(x, w), cy - k * 2, 1, 2), c)
	var hill := 0.0
	for x in w:
		hill = 9.0 + 5.0 * sin(x * TAU / w * 3.0) + 3.0 * sin(x * TAU / w * 7.0 + 1.3) + 2.0 * sin(x * TAU / w * 13.0)
		img.fill_rect(Rect2i(x, horizon - int(hill), 1, int(hill) + 1), hills)
	var tex := ImageTexture.create_from_image(img)
	_sky_cache[kind] = tex
	return tex


static func _blob_texture(c: Color) -> ImageTexture:
	var s := 16
	var img := Image.create(s, s, false, Image.FORMAT_RGBA8)
	for y in s:
		for x in s:
			var d := Vector2(x - 7.5, y - 7.5).length() / 7.5
			img.set_pixel(x, y, Color(c.r, c.g, c.b, c.a * clampf(1.2 - d * d * 1.3, 0.0, 1.0) if d <= 1.0 else 0.0))
	return ImageTexture.create_from_image(img)


# ----------------------------------------------------------------------------------------------
# Camera
# ----------------------------------------------------------------------------------------------

func _update_camera() -> void:
	var c: CamRig = game.cam
	var pos := Vector3(c.px, c.pz, c.py)
	var target := Vector3(c.tx, c.tz, c.ty)
	if c.shake_t > 0.0:
		pos += Vector3(randf() - 0.5, randf() - 0.5, randf() - 0.5) * 0.08
	if pos.distance_to(target) > 0.02 and absf((target - pos).normalized().y) < 0.98:
		camera.look_at_from_position(pos, target, Vector3.UP)
	camera.fov = clampf(c.fov, 10.0, 100.0)
	if sky_mi != null:
		sky_mi.position = Vector3(pos.x, 6.0, pos.z)


func _cam_forward() -> Vector2:
	var c: CamRig = game.cam
	var f := Vector2(c.tx - c.px, c.ty - c.py)
	return f.normalized() if f.length() > 0.001 else Vector2(0, -1)


# ----------------------------------------------------------------------------------------------
# Sprites
# ----------------------------------------------------------------------------------------------

func _sync() -> void:
	if game.world.map == null:
		return
	var alive := {}
	for e in game.world.ents:
		alive[e] = true
		var key := JSON.stringify(e.sprite)
		if nodes.has(e) and nodes[e].key == key:
			continue
		if nodes.has(e):
			_free_node(nodes[e])
		nodes[e] = _make_node(e, key)
	for e in nodes.keys():
		if not alive.has(e):
			_free_node(nodes[e])
			nodes.erase(e)
	var lights := false
	for e in game.world.ents:
		if e.light != null:
			lights = true
	if lights:
		_room_dirty = true


func _free_node(n: Dictionary) -> void:
	n.sprite.queue_free()
	if n.shadow != null:
		n.shadow.queue_free()


func _make_node(e: Ent, key: String) -> Dictionary:
	var sset: Dictionary = SpriteFactory.get_set(e.sprite if not e.sprite.is_empty() else {"template": "crate", "height": 0.4})
	var s := Sprite3D.new()
	s.texture = sset.texture
	s.hframes = int(sset.cols)
	s.vframes = int(sset.rows)
	s.pixel_size = float(sset.height) / float(sset.fh)
	s.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	s.shaded = false
	s.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	s.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	s.centered = true
	s.offset = Vector2(0, float(sset.fh) / 2.0)
	sprites_root.add_child(s)
	var shadow: MeshInstance3D = null
	if e.actor != null:
		var pm := PlaneMesh.new()
		var r := float(sset.height) * 0.55
		pm.size = Vector2(r, r * 0.8)
		pm.material = _shadow_mat
		shadow = MeshInstance3D.new()
		shadow.mesh = pm
		sprites_root.add_child(shadow)
	return {"sprite": s, "shadow": shadow, "key": key, "set": sset}


func _update_sprites() -> void:
	var map: MapData = game.world.map
	var c: CamRig = game.cam
	var fwd := _cam_forward()
	var right := Vector2(-fwd.y, fwd.x)
	for e in nodes:
		var n: Dictionary = nodes[e]
		var s: Sprite3D = n.sprite
		s.visible = not e.hidden
		if n.shadow != null:
			n.shadow.visible = not e.hidden and not e.dead and not e.down()
			n.shadow.position = Vector3(e.x, 0.015, e.y)
		if e.hidden:
			continue
		s.position = Vector3(e.x, 0.0, e.y)
		var sset: Dictionary = n.set
		var a: Dictionary = sset.anims.get(e.anim, sset.anims.get("idle", {"row": 0, "frames": 1, "fps": 1.0, "loop": true}))
		var fr := int(e.anim_t * float(a.fps))
		fr = fr % int(a.frames) if a.loop else mini(fr, int(a.frames) - 1)
		var row: int = a.row
		var flip := false
		var face := Vector2(cos(e.facing), sin(e.facing))
		if int(sset.views) == 3:
			var to_cam := atan2(c.py - e.y, c.px - e.x)
			var rel := absf(wrapf(e.facing - to_cam, -PI, PI))
			if rel > PI * 0.72:
				row += 1
			elif rel > PI * 0.28:
				row += 2
				flip = face.dot(right) < 0.0
		elif e.actor != null:
			flip = face.dot(right) < 0.0
		s.frame_coords = Vector2i(fr, row)
		s.flip_h = flip
		var l := Color.WHITE
		if e.light == null:
			l = RoomBuilder.light_at(map, light, floori(e.x), floori(e.y))
			# characters and props are lit a little brighter than the walls so they read clearly
			l = Color(clampf(l.r * 1.3 + 0.08, 0.2, 1.0), clampf(l.g * 1.3 + 0.08, 0.2, 1.0), clampf(l.b * 1.3 + 0.08, 0.2, 1.0))
		if e.flash > 0.0:
			l = l.lerp(Color(1.0, 0.35, 0.3), clampf(e.flash * 5.0, 0.0, 1.0))
		s.modulate = l


func _update_highlights() -> void:
	var hl: Dictionary = game.world.highlights
	var key := str(hl.hash()) if not hl.is_empty() else ""
	if key == _hl_key:
		return
	_hl_key = key
	highlight_mi.mesh = RoomBuilder.build_highlights(hl)


# ----------------------------------------------------------------------------------------------
# Picking and projection (pixel coordinates are SubViewport pixels)
# ----------------------------------------------------------------------------------------------

func world_to_screen(p: Vector3) -> Vector2:
	return camera.unproject_position(p)


func is_behind(p: Vector3) -> bool:
	return camera.is_position_behind(p)


## Screen position above an entity's head (for floating text and name tags).
func head_pos(e: Ent) -> Vector2:
	var hgt := float(e.sprite.get("height", 0.9)) * 0.9
	return world_to_screen(Vector3(e.x, hgt, e.y))


## What is under this pixel? Returns {ent: Ent or null, cell: Vector2i or null}.
func pick(screen: Vector2) -> Dictionary:
	var out := {"ent": null, "cell": null}
	if game.world.map == null:
		return out
	var map: MapData = game.world.map
	var cam_cell := Vector2i(floori(game.cam.px), floori(game.cam.py))
	# A body on the floor never steals the click from someone standing on or behind it:
	# it is only picked when nothing upright is under the cursor.
	var best_d := 1.0e9
	var body: Ent = null
	var body_d := 1.0e9
	for e in nodes:
		if e.hidden:
			continue
		var lying: bool = e.dead or e.down()
		var feet_w := Vector3(e.x, 0.0, e.y)
		if camera.is_position_behind(feet_w):
			continue
		var n: Dictionary = nodes[e]
		var hgt := float(n.set.height) * (0.35 if (e.dead or e.down()) else 0.92)
		var feet := camera.unproject_position(feet_w)
		var head := camera.unproject_position(Vector3(e.x, hgt, e.y))
		var hh := absf(feet.y - head.y)
		var half_w := maxf(4.0, hh * 0.3 * float(n.set.fw) / float(n.set.fh) * (2.2 if (e.dead or e.down()) else 1.0))
		if screen.x < feet.x - half_w or screen.x > feet.x + half_w or screen.y < head.y or screen.y > feet.y + 2.0:
			continue
		var d := camera.global_position.distance_to(feet_w)
		if not Grid.line_of_sight(map, cam_cell, e.cell()):
			continue
		if lying:
			if d < body_d:
				body_d = d
				body = e
		elif d < best_d:
			best_d = d
			out.ent = e
	if out.ent == null:
		out.ent = body
	var origin := camera.project_ray_origin(screen)
	var dir := camera.project_ray_normal(screen)
	var t_floor := -origin.y / dir.y if dir.y < -0.0001 else 200.0
	var t := 0.0
	while t < minf(t_floor, 60.0):
		var p := origin + dir * t
		var cx := floori(p.x)
		var cz := floori(p.z)
		if p.y <= map.wall_height and map.is_solid(cx, cz) and Vector2i(cx, cz) != cam_cell:
			if map.door(cx, cz) != null:
				out.cell = Vector2i(cx, cz)
			return out
		t += 0.08
	if dir.y < -0.0001:
		var hit := origin + dir * t_floor
		var cell := Vector2i(floori(hit.x), floori(hit.z))
		if map.in_bounds(cell.x, cell.y) and not map.is_solid(cell.x, cell.y):
			out.cell = cell
	return out


# ----------------------------------------------------------------------------------------------
# Effects
# ----------------------------------------------------------------------------------------------

## A glowing bolt flying from one point to another, ending in a burst. Returns after `seconds`.
func spell_fx(from: Vector3, to: Vector3, color: Color, seconds := 0.35) -> void:
	var s := Sprite3D.new()
	s.texture = _glow_tex
	s.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	s.shaded = false
	s.no_depth_test = true
	s.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	s.pixel_size = 0.022
	s.modulate = color
	s.position = from
	add_child(s)
	var tw := create_tween()
	if from.distance_to(to) > 0.05:
		tw.tween_property(s, "position", to, seconds)
	tw.tween_property(s, "pixel_size", 0.07, 0.18)
	tw.parallel().tween_property(s, "modulate:a", 0.0, 0.18)
	tw.tween_callback(s.queue_free)
	await tw.finished
