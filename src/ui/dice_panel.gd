class_name DicePanel
extends PanelContainer
## TOP-RIGHT pane: the dice tray. Every roll in the game arrives here as a "roll result" Dictionary
## (shape documented in src/rules/dice.gd) through UiIO.show_roll() -> play().
##   left   animated dice tumbling into place (Arena, drawn with _draw)
##   middle the result: total, success/failure, and the modifier breakdown
##   right  history of recent rolls
## The small buttons under the dice let the player roll any die by hand.

signal finished

const KIND_COLORS := {
	"check": Color("#2f5fa8"), "attack": Color("#a83a34"), "damage": Color("#b8662a"), "save": Color("#3f8a4a"),
	"initiative": Color("#6a4aa8"), "heal": Color("#2f8f8a"), "raw": Color("#5a5a66"),
}
const MAX_HISTORY := 30

var game: Game
var audio: AudioBank
var arena: Arena
var title: Label
var total: Label
var outcome: Label
var detail: RichTextLabel
var history: RichTextLabel
var _lines: Array = []
var _busy := false
var skip_requested := false


## The animated dice area.
class Arena extends Control:
	var dice: Array = []
	var clock := 0.0
	var duration := 1.0
	var running := false
	var rng := RandomNumberGenerator.new()

	func start(result: Dictionary, base: Color, seconds: float) -> void:
		dice.clear()
		clock = 0.0
		duration = seconds
		running = true
		var list: Array = result.get("dice", [])
		var n := mini(list.size(), 12)
		var sz := clampf(minf(size.y * 0.5, (size.x - 40.0) / maxf(1.0, n) * 0.8), 34.0, 86.0)
		for i in n:
			var d: Dictionary = list[i]
			var slot := Vector2(size.x / 2.0 + (i - (n - 1) / 2.0) * sz * 1.25, size.y * 0.46)
			var col := base
			if int(d.sides) == 20 and n == 1 and int(d.value) == 20:
				col = Color("#c9a02a")
			elif int(d.sides) == 20 and n == 1 and int(d.value) == 1:
				col = Color("#2a1a1e")
			dice.append({
				"sides": int(d.sides), "value": int(d.value), "shown": int(d.value), "slot": slot, "size": sz, "color": col,
				"start": Vector2(rng.randf_range(-40.0, size.x * 0.3), rng.randf_range(-30.0, size.y + 30.0)),
				"spin": rng.randf_range(6.0, 12.0) * (1.0 if rng.randf() < 0.5 else -1.0), "phase": rng.randf() * 3.0,
				"minus": int(d.get("sign", 1)) < 0,
			})
		queue_redraw()

	func finish() -> void:
		clock = duration + 1.0

	func _process(delta: float) -> void:
		if not running and clock > duration + 0.4:
			return
		clock += delta
		if clock >= duration + 0.4:
			running = false
		for d in dice:
			if clock < duration * 0.82:
				if int(clock * 18.0) != int((clock - delta) * 18.0):
					d.shown = rng.randi_range(1, int(d.sides))
			else:
				d.shown = d.value
		queue_redraw()

	func _draw() -> void:
		var font := get_theme_default_font()
		for d in dice:
			var k := clampf(clock / duration, 0.0, 1.0)
			var e := 1.0 - pow(1.0 - k, 3.0)
			var pos: Vector2 = d.start.lerp(d.slot, e)
			pos.y -= absf(sin((k * 3.2 + float(d.phase)) * PI)) * 46.0 * (1.0 - k)
			var rot: float = float(d.spin) * pow(1.0 - k, 2.0)
			var pop := 1.0 + 0.22 * clampf(1.0 - absf(clock - duration) / 0.14, 0.0, 1.0)
			var r: float = float(d.size) * 0.5 * pop
			var col: Color = d.color
			draw_set_transform(pos + Vector2(3, 5), rot, Vector2.ONE)
			draw_colored_polygon(_shape(int(d.sides), r), Color(0, 0, 0, 0.35))
			draw_set_transform(pos, rot, Vector2.ONE)
			var pts := _shape(int(d.sides), r)
			draw_colored_polygon(pts, col)
			var inner := _shape(int(d.sides), r * 0.55)
			draw_colored_polygon(inner, col.lightened(0.14))
			for i in pts.size():
				draw_line(pts[i], inner[i % inner.size()], col.darkened(0.35), 1.5)
			var closed := pts.duplicate()
			closed.append(pts[0])
			draw_polyline(closed, col.lightened(0.45), 2.0, true)
			draw_set_transform(pos, 0.0, Vector2.ONE)
			var fs := int(r * (0.82 if int(d.sides) < 100 else 0.6))
			var text := ("-" if d.minus else "") + str(d.shown)
			var tcol := Color.WHITE
			if clock >= duration and int(d.sides) == 20 and dice.size() == 1:
				tcol = Color("#fff2b0") if int(d.value) == 20 else (Color("#ff5a50") if int(d.value) == 1 else Color.WHITE)
			draw_string(font, Vector2(-r, fs * 0.36) + Vector2(1, 2), text, HORIZONTAL_ALIGNMENT_CENTER, r * 2.0, fs, Color(0, 0, 0, 0.6))
			draw_string(font, Vector2(-r, fs * 0.36), text, HORIZONTAL_ALIGNMENT_CENTER, r * 2.0, fs, tcol)
			draw_string(font, Vector2(-r, r + 15.0), "d%d" % int(d.sides), HORIZONTAL_ALIGNMENT_CENTER, r * 2.0, 11, Color(1, 1, 1, 0.45))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	## Outline of each die type as seen from above.
	static func _shape(sides: int, r: float) -> PackedVector2Array:
		var pts := PackedVector2Array()
		match sides:
			4:
				for i in 3:
					pts.append(Vector2(0, -r * 1.1).rotated(i * TAU / 3.0))
			6:
				for i in 4:
					pts.append(Vector2(r * 0.95, 0).rotated(PI / 4.0 + i * TAU / 4.0))
			8:
				pts = PackedVector2Array([Vector2(0, -r * 1.1), Vector2(r * 0.85, 0), Vector2(0, r * 1.1), Vector2(-r * 0.85, 0)])
			10, 100:
				pts = PackedVector2Array([Vector2(0, -r * 1.1), Vector2(r * 0.9, -r * 0.15), Vector2(r * 0.55, r * 0.75), Vector2(0, r * 1.05), Vector2(-r * 0.55, r * 0.75), Vector2(-r * 0.9, -r * 0.15)])
			12:
				for i in 5:
					pts.append(Vector2(0, -r * 1.05).rotated(i * TAU / 5.0))
			20:
				for i in 6:
					pts.append(Vector2(0, -r * 1.05).rotated(i * TAU / 6.0))
			_:
				for i in 12:
					pts.append(Vector2(0, -r).rotated(i * TAU / 12.0))
		return pts


func setup(g: Game, audio_bank: AudioBank) -> void:
	game = g
	audio = audio_bank
	custom_minimum_size = Vector2(0, 215)
	var row := UiKit.hbox(10)
	add_child(row)

	var left := UiKit.vbox(4)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.size_flags_stretch_ratio = 1.5
	row.add_child(left)
	arena = Arena.new()
	arena.size_flags_vertical = Control.SIZE_EXPAND_FILL
	arena.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	arena.clip_contents = true
	arena.mouse_filter = Control.MOUSE_FILTER_STOP
	arena.gui_input.connect(func(ev):
		if ev is InputEventMouseButton and ev.pressed:
			skip_requested = true)
	left.add_child(arena)
	var buttons := UiKit.hbox(4)
	buttons.add_child(UiKit.label("Roll:", 13, UiKit.DIM))
	for sides in [4, 6, 8, 10, 12, 20, 100]:
		var b := UiKit.button("d%d" % sides, func(): free_roll(sides), "Roll a d%d" % sides)
		b.add_theme_font_size_override("font_size", 13)
		buttons.add_child(b)
	left.add_child(buttons)

	var mid := UiKit.vbox(2)
	mid.custom_minimum_size = Vector2(290, 0)
	row.add_child(mid)
	title = UiKit.label("Dice tray", 16, UiKit.GOLD)
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	mid.add_child(title)
	var trow := UiKit.hbox(12)
	total = UiKit.label("", 54, UiKit.TEXT)
	trow.add_child(total)
	outcome = UiKit.label("", 22, UiKit.DIM)
	outcome.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	trow.add_child(outcome)
	mid.add_child(trow)
	detail = UiKit.rich(14)
	detail.text = UiKit.c("Every check, attack and saving throw is rolled here.", UiKit.DIM)
	mid.add_child(detail)

	var right := UiKit.vbox(2)
	right.custom_minimum_size = Vector2(300, 0)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(right)
	right.add_child(UiKit.label("Recent rolls", 13, UiKit.DIM))
	history = UiKit.rich(13)
	history.scroll_following = true
	right.add_child(history)


## Animates a roll and shows its result. Await it: it returns when the player has seen the outcome.
func play(result: Dictionary, quick := false) -> void:
	while _busy:
		await finished
	_busy = true
	skip_requested = false
	var speed: float = float(game.settings.get("dice_speed", 1.0)) if game != null else 1.0
	var has_dice: bool = not result.get("dice", []).is_empty()
	var roll_time := (0.5 if quick else 1.1) / maxf(0.2, speed)
	var hold_time := (0.35 if quick else 0.9) / maxf(0.2, speed)
	title.text = "%s%s" % [(str(result.get("actor", "")) + " - ") if str(result.get("actor", "")) != "" else "", result.get("label", "Roll")]
	total.text = ""
	outcome.text = ""
	detail.text = ""
	var base: Color = KIND_COLORS.get(result.get("kind", "raw"), KIND_COLORS.raw)
	if has_dice:
		arena.start(result, base, roll_time)
		if audio != null:
			audio.sfx("dice")
		var t := 0.0
		while t < roll_time and not skip_requested:
			await get_tree().process_frame
			t += get_process_delta_time()
		arena.finish()
		if audio != null:
			audio.sfx("dice_land")
	_show_result(result)
	_add_history(result)
	var t2 := 0.0
	skip_requested = false
	while t2 < hold_time and not skip_requested:
		await get_tree().process_frame
		t2 += get_process_delta_time()
	_busy = false
	finished.emit()


func _show_result(r: Dictionary) -> void:
	total.text = str(int(r.get("total", 0))) if not r.get("dice", []).is_empty() else "-"
	var col := UiKit.TEXT
	var word := ""
	if r.has("success"):
		var attack: bool = r.get("kind", "") == "attack"
		if r.success:
			word = ("Critical!" if r.get("crit", false) else "Hit") if attack else "Success"
			col = UiKit.GREEN
		else:
			word = "Miss" if attack else "Failure"
			col = UiKit.RED
	elif r.get("kind", "") == "damage":
		word = "damage"
		col = Color("#f0a050")
	elif r.get("kind", "") == "heal":
		word = "healed"
		col = UiKit.GREEN
	var nat: int = int(r.get("natural", 0))
	if nat == 20:
		col = UiKit.GOLD
		if word == "":
			word = "Natural 20"
	elif nat == 1 and r.has("natural"):
		col = UiKit.RED
		if word == "":
			word = "Natural 1"
	total.add_theme_color_override("font_color", col)
	outcome.text = word
	outcome.add_theme_color_override("font_color", col)

	var lines: Array = []
	var faces: Array = []
	for d in r.get("dice", []):
		faces.append(("-" if int(d.get("sign", 1)) < 0 else "") + str(int(d.value)))
	var sides := "d%d" % int(r.dice[0].sides) if not r.get("dice", []).is_empty() else ""
	var line := ""
	if not faces.is_empty():
		line = "%s [b]%s[/b]" % [UiKit.c(sides if faces.size() == 1 else "dice", UiKit.DIM), " + ".join(faces)]
		if int(r.get("modifier", 0)) != 0:
			line += "  %s" % Util.signed(r.modifier)
		line += "  =  [b]%d[/b]" % int(r.total)
	if r.has("dc"):
		line += UiKit.c("   vs %s %d" % ["AC" if r.get("kind", "") == "attack" else "DC", int(r.dc)], UiKit.GOLD)
	if line != "":
		lines.append(line)
	var parts: Array = []
	for p in r.get("parts", []):
		if int(p.value) != 0:
			parts.append("%s %s" % [UiKit.esc(p.label), Util.signed(p.value)])
	if not parts.is_empty():
		lines.append(UiKit.c(" · ".join(parts), UiKit.DIM))
	if str(r.get("note", "")) != "" and not str(r.note).begins_with("vs AC"):
		lines.append(UiKit.c(UiKit.esc(r.note), UiKit.PURPLE))
	detail.text = "\n".join(lines)


func _add_history(r: Dictionary) -> void:
	var mark := ""
	if r.has("success"):
		mark = UiKit.c(" ✔", UiKit.GREEN) if r.success else UiKit.c(" ✘", UiKit.RED)
	var vs := UiKit.c(" vs %d" % int(r.dc), UiKit.DIM) if r.has("dc") else ""
	var line := "%s %s [b]%s[/b]%s%s" % [
		UiKit.c(UiKit.esc(r.get("actor", "")), UiKit.DIM), UiKit.esc(r.get("label", "Roll")),
		str(int(r.get("total", 0))) if not r.get("dice", []).is_empty() else "-", vs, mark]
	_lines.append(line)
	if _lines.size() > MAX_HISTORY:
		_lines = _lines.slice(_lines.size() - MAX_HISTORY)
	history.text = "\n".join(_lines)


## The player clicked one of the "roll a die" buttons.
func free_roll(sides: int) -> void:
	if _busy:
		return
	var rng: Rng = game.rng if game != null else Rng.new()
	var who := "You"
	if game != null and not game.state.get("roster", {}).is_empty():
		who = str(game.leader().get("name", "You"))
	var rolled := Dice.roll("1d%d" % sides, rng)
	var result := Dice.as_result(rolled, "raw", "d%d" % sides, who)
	if sides == 20:
		result["natural"] = rolled.total
	play(result)
