extends SceneTree
## Renders example characters to one PNG so you can LOOK at the procedural sprite art.
##   godot --headless --path . -s res://tools/sprite_gallery.gd -- <out.png> [looks.json] [scale]
## Default looks file: data/sprite_samples.json  ({"name": {look...}, ...}).
## Each character is shown as: front, side, back, walking, attacking, casting. Names are printed in order.

const COLUMNS := 2
const SHOTS := [["idle", 0, 0], ["idle", 2, 0], ["idle", 1, 0], ["walk", 0, 0], ["attack", 0, 1], ["cast", 0, 1]]


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var out: String = args[0] if args.size() > 0 else "user://sprite_gallery.png"
	var file: String = args[1] if args.size() > 1 else "res://data/sprite_samples.json"
	var scale: int = int(args[2]) if args.size() > 2 else 4
	var looks = Util.load_json(file, {})
	var names: Array = []
	for k in looks:
		if not str(k).begins_with("_") and typeof(looks[k]) == TYPE_DICTIONARY:
			names.append(k)
	if names.is_empty():
		printerr("no looks found in " + file)
		quit(1)
		return
	var cell_w := 48 * SHOTS.size() + 8
	var cell_h := 52
	var rows := int(ceil(names.size() / float(COLUMNS)))
	var sheet := Image.create(cell_w * COLUMNS, cell_h * rows, false, Image.FORMAT_RGBA8)
	sheet.fill(Color("#3a3446"))
	for i in names.size():
		var look: Dictionary = looks[names[i]]
		var sset: Dictionary = SpriteFactory.get_set({"template": "humanoid", "height": 0.95, "look": look})
		var img: Image = sset.image
		var ox := (i % COLUMNS) * cell_w + 4
		var oy := (i / COLUMNS) * cell_h + 2
		sheet.fill_rect(Rect2i(ox - 2, oy + 47, cell_w - 4, 3), Color("#2a2634"))
		for s in SHOTS.size():
			var shot: Array = SHOTS[s]
			var row: int = int(sset.anims[shot[0]].row) + int(shot[1])
			sheet.blend_rect(img, Rect2i(int(shot[2]) * 48, row * 48, 48, 48), Vector2i(ox + s * 48, oy))
		print("%2d  row %d col %d  %s" % [i + 1, i / COLUMNS + 1, i % COLUMNS + 1, names[i]])
	sheet.resize(sheet.get_width() * scale, sheet.get_height() * scale, Image.INTERPOLATE_NEAREST)
	var err := sheet.save_png(out)
	print("saved %s (%dx%d)" % [out, sheet.get_width(), sheet.get_height()] if err == OK else "could not save " + out)
	quit(0 if err == OK else 1)
