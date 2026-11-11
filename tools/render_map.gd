extends SceneTree
## Renders a map of a campaign to PNG files so you can LOOK at it without playing (needs a display).
##   godot --path . -s res://tools/render_map.gd -- <campaign> <map> <out_folder> [marker ...]
## Example:
##   godot --path . -s res://tools/render_map.gd -- hollowmere town /tmp/shots start market
## One picture is taken with the party standing on each marker (default: "start"), using the same
## automatic camera as the game, plus one chase-camera picture. Sprite sheets of every entity on the
## map are saved as <out_folder>/sprites.png for a quick art check.

var game: Game
var sv: SubViewport
var view: WorldView


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() < 3:
		printerr("usage: -- <campaign> <map> <out_folder> [marker ...]")
		quit(2)
		return
	var out_dir: String = args[2]
	DirAccess.make_dir_recursive_absolute(out_dir)
	game = Game.new()
	game.instant = true
	game.tree = self
	if not game.load_campaign(args[0]):
		printerr("cannot load campaign " + args[0])
		quit(1)
		return
	var comps: Dictionary = game.campaign.get("companions", {})
	var spec := {"name": "Hero", "race": "human", "cls": "fighter", "racialChoice": "str", "abilities": {"str": 15, "dex": 13, "con": 14, "int": 10, "wis": 12, "cha": 8}}
	game.state = game._blank_state(args[0])
	var pc := CharRules.create(spec, game.db)
	pc["id"] = "player"
	game.state.playerId = "player"
	game.state.leader = "player"
	game.state.roster["player"] = pc
	game.state.party = ["player"]
	for cid in comps:
		if game.state.party.size() < 4:
			var s: Dictionary = comps[cid].duplicate(true)
			s["id"] = cid
			game.state.roster[cid] = CharRules.create(s, game.db)
			game.state.party.append(cid)
			game.state.companions[cid] = "party"
	game.mode = "explore"

	sv = SubViewport.new()
	sv.size = Vector2i(480, 270)
	sv.own_world_3d = true
	sv.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(sv)
	view = WorldView.new()
	sv.add_child(view)
	view.setup(game)

	var markers: Array = []
	for i in range(3, args.size()):
		markers.append(args[i])
	if markers.is_empty():
		markers.append("start")
	for m in markers:
		game.world.load_map(args[1], m)
		# spread the party out a little so every sprite is visible
		var i := 0
		for e in game.world.party_ents():
			e.set_cell(game.world.free_cell_near(e.cell() + Vector2i(i % 2, i / 2), e))
			i += 1
		game.cam.prefer_chase = false
		game.cam.snap()
		await _shot("%s/%s_%s_room.png" % [out_dir, args[1], m])
		game.cam.prefer_chase = true
		game.cam.yaw = -PI / 2.0
		game.cam.snap()
		await _shot("%s/%s_%s_chase.png" % [out_dir, args[1], m])
	_save_sprites(out_dir + "/sprites.png")
	print("done: pictures written to " + out_dir)
	quit(0)


func _shot(path: String) -> void:
	for i in 4:
		await process_frame
	await RenderingServer.frame_post_draw
	var img := sv.get_texture().get_image()
	img.resize(img.get_width() * 3, img.get_height() * 3, Image.INTERPOLATE_NEAREST)
	img.save_png(path)
	print("saved " + path)


func _save_sprites(path: String) -> void:
	var sets: Array = []
	var seen := {}
	for e in game.world.ents:
		var key := JSON.stringify(e.sprite)
		if e.sprite.is_empty() or seen.has(key):
			continue
		seen[key] = true
		sets.append(SpriteFactory.get_set(e.sprite))
	var w := 0
	var h := 0
	for s in sets:
		var im: Image = s.texture.get_image()
		w += im.get_width() + 4
		h = maxi(h, im.get_height())
	if w == 0:
		return
	var sheet := Image.create(w, h, false, Image.FORMAT_RGBA8)
	sheet.fill(Color("#30283c"))
	var x := 0
	for s in sets:
		var im: Image = s.texture.get_image()
		im.convert(Image.FORMAT_RGBA8)
		sheet.blend_rect(im, Rect2i(0, 0, im.get_width(), im.get_height()), Vector2i(x, 0))
		x += im.get_width() + 4
	sheet.resize(w * 2, h * 2, Image.INTERPOLATE_NEAREST)
	sheet.save_png(path)
	print("saved " + path)
