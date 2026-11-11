class_name ViewPanel
extends PanelContainer
## BOTTOM-RIGHT pane (the largest): the 3D room view plus everything drawn over it.
##   svc/sv   a SubViewport rendered at 1/SHRINK resolution and scaled up with nearest filtering,
##            which gives the chunky 16-bit picture. It contains the WorldView (src/render).
##   hud      mouse input + overlays: location, party portraits, buttons, minimap, turn order,
##            combat bar, hover name tag, floating numbers, banner, subtitles, letterbox, fade.
## UiIO calls the public methods at the bottom (fade, banner, float_text, show_subtitle...).

const SHRINK := 3

var game: Game
var main
var svc: SubViewportContainer
var sv: SubViewport
var world: WorldView
var hud: Control
var combat: CombatHud
var minimap: Minimap
var location: Label
var hint: Label
var hover_tag: Label
var party_box: VBoxContainer
var turn_strip: HBoxContainer
var camp_btn: Button
var banner_box: VBoxContainer
var banner_main: Label
var banner_sub: Label
var subtitle_panel: PanelContainer
var subtitle_text: RichTextLabel
var bar_top: ColorRect
var bar_bottom: ColorRect
var fade_rect: ColorRect
var card: ColorRect
var card_main: Label
var card_sub: Label
var floats: Array = []
var _party_dirty := true
var _letterbox := 0.0
var _letterbox_goal := 0.0
var _banner_tween: Tween


## Small top-down map in the corner. Click it to walk (or to pick a tile in combat).
class Minimap extends Control:
	var game: Game
	var view
	var big := false
	var _t := 0.0

	func _process(delta: float) -> void:
		_t += delta
		if _t > 0.12:
			_t = 0.0
			queue_redraw()

	func scale_px() -> float:
		var map: MapData = game.world.map
		if map == null:
			return 4.0
		var room := 330.0 if big else 170.0
		return clampf(floorf(room / maxi(map.w, map.h)), 3.0, 14.0)

	func _draw() -> void:
		var map: MapData = game.world.map
		if map == null:
			return
		var s := scale_px()
		custom_minimum_size = Vector2(map.w * s, map.h * s)
		size = custom_minimum_size
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.03, 0.03, 0.05, 0.78))
		var seen: PackedByteArray = game.world.seen
		for y in map.h:
			for x in map.w:
				if seen.size() != map.w * map.h or seen[y * map.w + x] == 0:
					continue
				var col := Color(0.42, 0.4, 0.46)
				if map.is_solid(x, y):
					col = Color(0.85, 0.7, 0.3) if map.has_door(x, y) else Color(0.16, 0.15, 0.2)
				elif map.exit_at(x, y) != null:
					col = Color(0.3, 0.8, 0.4)
				elif map.entry(x, y).get("blocked", false):
					col = Color(0.2, 0.35, 0.6)
				draw_rect(Rect2(x * s, y * s, s, s), col)
		var hl: Dictionary = game.world.highlights
		for cell in hl:
			var hc: Color = hl[cell]
			draw_rect(Rect2(cell.x * s, cell.y * s, s, s), Color(hc.r, hc.g, hc.b, 0.55))
		for e in game.world.ents:
			if e.hidden or e.kind == "prop":
				continue
			var c: Vector2i = e.cell()
			if seen.size() == map.w * map.h and map.in_bounds(c.x, c.y) and seen[c.y * map.w + c.x] == 0:
				continue
			var col := Color(0.95, 0.85, 0.3)
			if e.kind == "party":
				col = Color(0.4, 0.75, 1.0)
			elif e.kind == "monster":
				col = Color(0.5, 0.5, 0.5) if (e.dead or e.down()) else (Color(1.0, 0.25, 0.2) if e.hostile else Color(0.9, 0.6, 0.2))
			draw_circle(Vector2(e.x, e.y) * s, maxf(2.0, s * 0.38), col)
		var cam: CamRig = game.cam
		var cp := Vector2(cam.px, cam.py) * s
		var dir := Vector2(cam.tx - cam.px, cam.ty - cam.py).normalized()
		draw_line(cp, cp + dir.rotated(0.45) * s * 2.5, Color(1, 1, 1, 0.5), 1.0)
		draw_line(cp, cp + dir.rotated(-0.45) * s * 2.5, Color(1, 1, 1, 0.5), 1.0)
		draw_rect(Rect2(Vector2.ZERO, size), UiKit.BORDER, false, 1.0)

	func _gui_input(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			var s := scale_px()
			var cell := Vector2i(floori(ev.position.x / s), floori(ev.position.y / s))
			view.click_cell(cell)
			accept_event()


func setup(g: Game, main_node) -> void:
	game = g
	main = main_node
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_theme_stylebox_override("panel", UiKit.box(Color.BLACK, UiKit.BORDER, 1, 6, 2, 2))
	var root := Control.new()
	root.clip_contents = true
	add_child(root)

	svc = SubViewportContainer.new()
	svc.stretch = true
	svc.stretch_shrink = SHRINK
	svc.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	svc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	svc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(svc)
	sv = SubViewport.new()
	sv.own_world_3d = true
	sv.handle_input_locally = false
	sv.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	svc.add_child(sv)
	world = WorldView.new()
	sv.add_child(world)
	world.setup(game)

	hud = Control.new()
	hud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hud.mouse_filter = Control.MOUSE_FILTER_STOP
	hud.gui_input.connect(_on_hud_input)
	hud.mouse_exited.connect(func(): hover_tag.visible = false)
	root.add_child(hud)

	location = UiKit.label("", 15, UiKit.GOLD)
	location.position = Vector2(12, 8)
	_shadow(location)
	hud.add_child(location)

	party_box = UiKit.vbox(6)
	party_box.position = Vector2(10, 40)
	hud.add_child(party_box)

	var right := UiKit.vbox(6)
	_pin(right, 1.0, 0.0, -10, 8)
	right.alignment = BoxContainer.ALIGNMENT_BEGIN
	hud.add_child(right)
	var buttons := UiKit.hbox(4)
	buttons.alignment = BoxContainer.ALIGNMENT_END
	camp_btn = UiKit.button("Camp", func(): main.go_camp(), "Travel to your camp (G)")
	buttons.add_child(camp_btn)
	buttons.add_child(UiKit.button("Camera", func(): toggle_camera(), "Switch between room camera and chase camera (C)"))
	buttons.add_child(UiKit.button("Map", func(): toggle_minimap(), "Bigger / smaller minimap (M)"))
	buttons.add_child(UiKit.button("Menu", func(): main.open_menu(), "Save, load, settings (Esc)"))
	right.add_child(buttons)
	minimap = Minimap.new()
	minimap.game = game
	minimap.view = self
	minimap.size_flags_horizontal = Control.SIZE_SHRINK_END
	minimap.mouse_filter = Control.MOUSE_FILTER_STOP
	right.add_child(minimap)

	turn_strip = UiKit.hbox(4)
	_pin(turn_strip, 0.5, 0.0, 0, 44)
	hud.add_child(turn_strip)

	combat = CombatHud.new()
	combat.setup(game, self)
	_pin(combat, 0.5, 1.0, 0, -10)
	hud.add_child(combat)

	hint = UiKit.label("", 13, Color(1, 1, 1, 0.6))
	_pin(hint, 0.0, 1.0, 12, -8)
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_shadow(hint)
	hud.add_child(hint)

	hover_tag = UiKit.label("", 14, UiKit.TEXT)
	hover_tag.add_theme_stylebox_override("normal", UiKit.box(Color(0.05, 0.04, 0.08, 0.85), UiKit.BORDER, 1, 4, 6, 2))
	hover_tag.visible = false
	hover_tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(hover_tag)

	banner_box = UiKit.vbox(0)
	_pin(banner_box, 0.5, 0.0, 0, 70)
	banner_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	banner_box.modulate.a = 0.0
	banner_main = UiKit.label("", 34, UiKit.GOLD)
	banner_main.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_shadow(banner_main)
	banner_sub = UiKit.label("", 17, UiKit.TEXT)
	banner_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_shadow(banner_sub)
	banner_box.add_child(banner_main)
	banner_box.add_child(banner_sub)
	hud.add_child(banner_box)

	bar_top = ColorRect.new()
	bar_top.color = Color.BLACK
	bar_top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(bar_top)
	bar_bottom = ColorRect.new()
	bar_bottom.color = Color.BLACK
	bar_bottom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(bar_bottom)

	subtitle_panel = UiKit.panel(Color(0.03, 0.03, 0.05, 0.82), UiKit.BORDER, 10)
	subtitle_panel.anchor_left = 0.14
	subtitle_panel.anchor_right = 0.86
	subtitle_panel.anchor_top = 1.0
	subtitle_panel.anchor_bottom = 1.0
	subtitle_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	subtitle_panel.offset_bottom = -16
	subtitle_panel.visible = false
	subtitle_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	subtitle_text = UiKit.rich(18)
	subtitle_text.fit_content = true
	subtitle_text.scroll_active = false
	subtitle_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	subtitle_panel.add_child(subtitle_text)
	hud.add_child(subtitle_panel)

	fade_rect = ColorRect.new()
	fade_rect.color = Color(0, 0, 0, 0)
	fade_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	fade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(fade_rect)

	card = ColorRect.new()
	card.color = Color(0, 0, 0, 0.88)
	card.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.visible = false
	var cv := UiKit.vbox(8)
	cv.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	cv.alignment = BoxContainer.ALIGNMENT_CENTER
	card_main = UiKit.label("", 46, UiKit.GOLD)
	card_main.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	card_sub = UiKit.label("", 20, UiKit.TEXT)
	card_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cv.add_child(card_main)
	cv.add_child(card_sub)
	card.add_child(cv)
	hud.add_child(card)

	game.state_changed.connect(func(): _party_dirty = true)
	game.map_loaded.connect(func(): _party_dirty = true)
	game.combat_changed.connect(_draw_turn_strip)
	game.mode_changed.connect(_draw_turn_strip)


## Pins a control to a point of its parent: (ax, ay) are 0..1 anchors (0 = left/top, 0.5 = centre,
## 1 = right/bottom), (ox, oy) pixel offsets from that point. The control grows away from the edge.
static func _pin(ctrl: Control, ax: float, ay: float, ox: float, oy: float) -> void:
	ctrl.anchor_left = ax
	ctrl.anchor_right = ax
	ctrl.anchor_top = ay
	ctrl.anchor_bottom = ay
	ctrl.offset_left = ox
	ctrl.offset_right = ox
	ctrl.offset_top = oy
	ctrl.offset_bottom = oy
	ctrl.grow_horizontal = Control.GROW_DIRECTION_BEGIN if ax > 0.9 else (Control.GROW_DIRECTION_BOTH if ax > 0.1 else Control.GROW_DIRECTION_END)
	ctrl.grow_vertical = Control.GROW_DIRECTION_BEGIN if ay > 0.9 else (Control.GROW_DIRECTION_BOTH if ay > 0.1 else Control.GROW_DIRECTION_END)


static func _shadow(l: Label) -> void:
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	l.add_theme_constant_override("shadow_offset_x", 2)
	l.add_theme_constant_override("shadow_offset_y", 2)


# ----------------------------------------------------------------------------------------------
# Per-frame
# ----------------------------------------------------------------------------------------------

func _process(delta: float) -> void:
	if game == null or game.world.map == null or game.mode == "menu":
		return
	location.text = game.world.map.name
	camp_btn.visible = game.campaign.has("camp")
	camp_btn.disabled = not (game.mode == "explore" and game.busy == 0)
	camp_btn.text = "Leave camp" if game.world.map.id == game.campaign.get("camp", {}).get("map", "") else "Camp"
	if _party_dirty:
		_party_dirty = false
		_draw_party()
	_update_hint()
	_update_floats(delta)
	_letterbox = move_toward(_letterbox, _letterbox_goal, delta * 2.5)
	var bh := hud.size.y * 0.11 * _letterbox
	bar_top.position = Vector2.ZERO
	bar_top.size = Vector2(hud.size.x, bh)
	bar_bottom.position = Vector2(0, hud.size.y - bh)
	bar_bottom.size = Vector2(hud.size.x, bh)
	var hud_on: bool = not game.in_cutscene
	party_box.visible = hud_on
	minimap.get_parent().visible = hud_on
	location.visible = hud_on
	hint.visible = hud_on and not (game.mode == "combat" and combat.waiting())
	turn_strip.visible = hud_on


func _update_hint() -> void:
	if game.over:
		hint.text = ""
	elif game.in_dialogue:
		hint.text = "Pick a reply in the journal (or press its number)  ·  Space: hurry"
	elif game.mode == "combat":
		hint.text = "Your turn: click a tile to move, an enemy to attack" if combat.waiting() else "Enemy turn  ·  click to hurry the dice"
	elif game.busy > 0:
		hint.text = "Space: continue"
	else:
		hint.text = "Click: move / talk / use   ·   WASD: walk   ·   Q/E or right-drag: turn camera   ·   C: camera mode"


func _draw_party() -> void:
	UiKit.clear(party_box)
	for cid in game.state.get("party", []):
		var c: Dictionary = game.state.roster[cid]
		var s: Dictionary = game.stats(c)
		var b := Button.new()
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(150, 46)
		b.tooltip_text = "Show %s's sheet (double-click: take the lead)" % c.name
		b.add_theme_stylebox_override("normal", UiKit.box(Color(0.06, 0.05, 0.09, 0.8), UiKit.GOLD if cid == game.state.leader else UiKit.BORDER, 1, 5, 4, 3))
		var hrow := UiKit.hbox(6)
		hrow.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		hrow.offset_left = 4
		hrow.offset_right = -6
		hrow.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var tr := TextureRect.new()
		tr.custom_minimum_size = Vector2(40, 40)
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.clip_contents = true
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		Portraits.apply(tr, game, c)
		hrow.add_child(tr)
		var col := UiKit.vbox(2)
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		col.alignment = BoxContainer.ALIGNMENT_CENTER
		col.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var frac := float(maxi(0, int(c.hp))) / float(s.hpMax)
		col.add_child(UiKit.label(str(c.name).get_slice(" ", 0), 13, UiKit.RED if int(c.hp) <= 0 else UiKit.TEXT))
		col.add_child(UiKit.bar(maxi(0, int(c.hp)), s.hpMax, UiKit.RED if frac < 0.34 else UiKit.GREEN, 6))
		col.add_child(UiKit.label("%d / %d" % [int(c.hp), int(s.hpMax)], 11, UiKit.DIM))
		hrow.add_child(col)
		b.add_child(hrow)
		b.gui_input.connect(func(ev):
			if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
				main.sheet.show_character(cid)
				if ev.double_click and game.encounter == null:
					Party.set_leader(game, cid))
		party_box.add_child(b)


func _draw_turn_strip() -> void:
	UiKit.clear(turn_strip)
	var enc = game.encounter
	if enc == null:
		return
	for c in enc.combatants:
		if not c.alive():
			continue
		var is_active: bool = c == enc.active
		var col := UiKit.BLUE if c.side == "party" else UiKit.RED
		var short: String = str(c.name).get_slice(" ", 0) if c.side == "party" else str(c.name).left(12)
		var l := UiKit.label(short, 13 if not is_active else 15, Color.WHITE if is_active else col)
		l.add_theme_stylebox_override("normal", UiKit.box(col.darkened(0.45) if is_active else Color(0.05, 0.04, 0.08, 0.8), UiKit.GOLD if is_active else col.darkened(0.3), 2 if is_active else 1, 4, 7, 3))
		if c.down():
			l.modulate.a = 0.45
		turn_strip.add_child(l)


# ----------------------------------------------------------------------------------------------
# Mouse
# ----------------------------------------------------------------------------------------------

func _on_hud_input(ev: InputEvent) -> void:
	if ev is InputEventMouseMotion:
		if ev.button_mask & MOUSE_BUTTON_MASK_RIGHT:
			game.cam.prefer_chase = true
			game.cam.rotate(ev.relative.x * 0.007)
			return
		_hover(ev.position)
	elif ev is InputEventMouseButton and ev.pressed:
		if ev.button_index == MOUSE_BUTTON_WHEEL_UP:
			game.cam.chase_dist = clampf(game.cam.chase_dist - 0.25, 1.4, 5.0)
		elif ev.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			game.cam.chase_dist = clampf(game.cam.chase_dist + 0.25, 1.4, 5.0)
		elif ev.button_index == MOUSE_BUTTON_LEFT:
			_click(ev.position)


func _pick(pos: Vector2) -> Dictionary:
	return world.pick(pos / float(SHRINK))


func _hover(pos: Vector2) -> void:
	if game.world.map == null or game.in_cutscene:
		hover_tag.visible = false
		return
	var p := _pick(pos)
	if game.mode == "combat":
		combat.on_hover(p)
	var e: Ent = p.ent
	if e == null or (e.kind == "prop" and not game.world.can_interact(e)):
		hover_tag.visible = false
		return
	var text := e.name
	if e.actor != null:
		if e.kind == "party":
			text += "   %d/%d hp" % [int(e.actor.hp), int(game.stats(e.actor).hpMax)]
		elif e.kind == "monster":
			var frac := float(int(e.actor.hp)) / float(maxi(1, int(e.actor.get("hpMax", 1))))
			text += "   (%s)" % ("dead" if e.dead else ("unhurt" if frac >= 1.0 else ("wounded" if frac > 0.5 else "badly wounded")))
	hover_tag.text = text
	hover_tag.add_theme_color_override("font_color", UiKit.RED if (e.kind == "monster" and e.hostile) else (UiKit.GOLD if game.world.can_interact(e) else UiKit.TEXT))
	hover_tag.visible = true
	hover_tag.position = pos + Vector2(16, 12)


func _click(pos: Vector2) -> void:
	if game.world.map == null or game.over:
		return
	if game.in_cutscene or (game.busy > 0 and game.mode != "combat"):
		main.io.request_skip()
		return
	var p := _pick(pos)
	if game.mode == "combat":
		if combat.waiting():
			combat.on_pick(p)
		else:
			main.io.request_skip()
		return
	# Companions walk right behind the hero and their sprites often cover the spot you want to
	# walk to. A click on a companion only means "talk" when the floor under the cursor is near them.
	if p.ent != null and p.ent.kind == "party" and p.cell != null:
		if Vector2(p.cell.x + 0.5, p.cell.y + 0.5).distance_to(p.ent.pos()) > 2.5:
			p.ent = null
	if p.ent != null and game.world.can_interact(p.ent):
		game.world.click_ent(p.ent)
	elif p.cell != null:
		game.world.click_cell(p.cell)
	elif p.ent != null:
		game.world.click_cell(game.world.free_cell_near(p.ent.cell()))


## A tile was clicked on the minimap.
func click_cell(cell: Vector2i) -> void:
	if game.mode == "combat":
		if combat.waiting():
			combat.on_pick({"ent": null, "cell": cell})
	elif game.busy == 0:
		var e: Ent = game.world.ent_at(cell)
		if e != null and game.world.can_interact(e):
			game.world.click_ent(e)
		else:
			game.world.click_cell(cell)


func toggle_camera() -> void:
	game.cam.prefer_chase = not game.cam.prefer_chase
	var lead := game.world.leader_ent()
	if game.cam.prefer_chase and lead != null:
		game.cam.yaw = lead.facing
	game.journal("system", "Camera: %s." % ("chase camera (Q/E to turn)" if game.cam.prefer_chase else "room camera"))


func toggle_minimap() -> void:
	minimap.big = not minimap.big
	minimap.queue_redraw()


## Direction on the map that "forward on screen" points to (for camera-relative WASD).
func camera_forward() -> Vector2:
	var f := Vector2(game.cam.tx - game.cam.px, game.cam.ty - game.cam.py)
	return f.normalized() if f.length() > 0.001 else Vector2(0, -1)


# ----------------------------------------------------------------------------------------------
# Effects used by UiIO
# ----------------------------------------------------------------------------------------------

func fade(to_black: bool, seconds: float) -> void:
	var goal := 1.0 if to_black else 0.0
	if seconds <= 0.0:
		fade_rect.color.a = goal
		return
	var tw := create_tween()
	tw.tween_property(fade_rect, "color:a", goal, seconds)
	await tw.finished


func banner(text: String, sub := "") -> void:
	banner_main.text = text
	banner_sub.text = sub
	banner_sub.visible = sub != ""
	if _banner_tween != null:
		_banner_tween.kill()
	_banner_tween = create_tween()
	_banner_tween.tween_property(banner_box, "modulate:a", 1.0, 0.35)
	_banner_tween.tween_interval(2.0)
	_banner_tween.tween_property(banner_box, "modulate:a", 0.0, 0.8)


func float_text(e: Ent, text: String, kind := "info") -> void:
	if e == null:
		return
	var colors := {"damage": Color("#ff6a5a"), "crit": Color("#ffd040"), "heal": Color("#7af07a"), "miss": Color("#c8c8d0"), "info": Color("#e8e0ff")}
	var l := UiKit.label(text, 26 if kind == "crit" else (22 if kind in ["damage", "heal"] else 17), colors.get(kind, Color.WHITE))
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_shadow(l)
	hud.add_child(l)
	hud.move_child(l, subtitle_panel.get_index())
	var stagger := 0.0
	for f in floats:
		if f.ent == e and float(f.t) < 0.4:
			stagger += 0.35
	floats.append({"label": l, "ent": e, "t": -stagger, "x": e.x, "y": e.y, "h": float(e.sprite.get("height", 0.9))})
	l.visible = stagger == 0.0


func _update_floats(delta: float) -> void:
	for f in floats.duplicate():
		f.t = float(f.t) + delta
		var l: Label = f.label
		if float(f.t) < 0.0:
			continue
		if float(f.t) > 1.3:
			l.queue_free()
			floats.erase(f)
			continue
		var wp := Vector3(f.x, float(f.h) * 0.85 + float(f.t) * 0.35, f.y)
		l.visible = not world.is_behind(wp)
		var sp := world.world_to_screen(wp) * float(SHRINK)
		l.position = sp - Vector2(l.size.x / 2.0, l.size.y)
		l.modulate.a = clampf((1.3 - float(f.t)) * 2.5, 0.0, 1.0)


func show_subtitle(speaker: String, text: String) -> void:
	var line := "[center]"
	if speaker != "":
		line += "[b]%s[/b]\n" % UiKit.c(UiKit.esc(speaker), UiKit.GOLD)
		line += UiKit.esc(text)
	else:
		line += "[i]%s[/i]" % UiKit.c(UiKit.esc(text), Color("#d8d0c0"))
	subtitle_text.text = line + "[/center]"
	subtitle_panel.visible = true


func hide_subtitle() -> void:
	subtitle_panel.visible = false


func letterbox(on: bool) -> void:
	_letterbox_goal = 1.0 if on else 0.0


func title_card(text: String, sub: String, seconds: float) -> void:
	card_main.text = text
	card_sub.text = sub
	card.modulate.a = 0.0
	card.visible = true
	var tw := create_tween()
	tw.tween_property(card, "modulate:a", 1.0, 0.6)
	tw.tween_interval(seconds)
	tw.tween_property(card, "modulate:a", 0.0, 0.6)
	await tw.finished
	card.visible = false
