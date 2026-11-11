extends Control
## Root of the windowed game (scene: src/main.tscn). It only wires things together:
##   - creates the Game (engine) with a UiIO (screen/sound bridge)
##   - builds the four panes:   TOP-LEFT  character sheet   | TOP-RIGHT    dice tray
##                              BOTTOM-LEFT journal/choices | BOTTOM-RIGHT 3D view (largest)
##   - forwards keyboard input and ticks game.update() every frame
##   - opens the modal screens (title, builder, menu, shop, level-up, game over)
## Game rules never live here: see src/rules (maths) and src/engine (flow).

var game: Game
var io: UiIO
var audio: AudioBank
var sheet: SheetPanel
var journal: JournalPanel
var dice: DicePanel
var view: ViewPanel
var overlay: Modal = null
var dev: DevTools


func _ready() -> void:
	theme = UiKit.theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = UiKit.BG
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	audio = AudioBank.new()
	add_child(audio)
	io = UiIO.new()
	io.main = self
	game = Game.new(io)
	game.tree = get_tree()
	_build_layout()
	game.player_controller = view.combat
	dev = DevTools.new(self)
	if not dev.handle(OS.get_cmdline_user_args()):
		show_title()


func _build_layout() -> void:
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 6)
	add_child(margin)
	var cols := HSplitContainer.new()
	margin.add_child(cols)
	var left := VSplitContainer.new()
	left.custom_minimum_size = Vector2(500, 0)
	cols.add_child(left)
	var right := VSplitContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cols.add_child(right)

	sheet = SheetPanel.new()
	left.add_child(sheet)
	sheet.setup(game, self)
	journal = JournalPanel.new()
	journal.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left.add_child(journal)
	journal.setup(game, audio)

	dice = DicePanel.new()
	right.add_child(dice)
	dice.setup(game, audio)
	view = ViewPanel.new()
	right.add_child(view)
	view.setup(game, self)


# ----------------------------------------------------------------------------------------------
# Frame update and input
# ----------------------------------------------------------------------------------------------

func _process(delta: float) -> void:
	_read_movement(delta)
	game.update(delta)


func _typing() -> bool:
	var f := get_viewport().gui_get_focus_owner()
	return f is LineEdit or f is TextEdit


## WASD walks relative to the camera; Q/E turn the chase camera.
func _read_movement(delta: float) -> void:
	var mv := Vector2.ZERO
	if overlay == null and game.mode == "explore" and game.busy == 0 and not game.over and not _typing():
		var f := int(Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP)) - int(Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN))
		var r := int(Input.is_physical_key_pressed(KEY_D)) - int(Input.is_physical_key_pressed(KEY_A))
		if f != 0 or r != 0:
			var fwd := view.camera_forward()
			mv = fwd * f + Vector2(-fwd.y, fwd.x) * r
		var turn := int(Input.is_physical_key_pressed(KEY_E) or Input.is_physical_key_pressed(KEY_RIGHT)) - int(Input.is_physical_key_pressed(KEY_Q) or Input.is_physical_key_pressed(KEY_LEFT))
		if turn != 0:
			if not game.cam.prefer_chase:
				game.cam.prefer_chase = true
				var lead := game.world.leader_ent()
				if lead != null:
					game.cam.yaw = lead.facing
			game.cam.rotate(turn * 2.0 * delta)
	game.world.move_input = mv


func _unhandled_key_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	var key: int = event.physical_keycode
	if key == KEY_F11:
		var win := get_window()
		win.mode = Window.MODE_WINDOWED if win.mode == Window.MODE_FULLSCREEN else Window.MODE_FULLSCREEN
		return
	if overlay != null:
		if key == KEY_ESCAPE and overlay.escapable:
			close_overlay()
		return
	if game.mode == "menu":
		return
	match key:
		KEY_ESCAPE:
			if game.in_cutscene:
				game.skip_cutscene = true
				game.anims.finish_all()
				io.request_skip()
			elif not view.combat.cancel():
				open_menu()
		KEY_SPACE, KEY_ENTER, KEY_KP_ENTER:
			if view.combat.waiting():
				view.combat.end_turn()
			else:
				io.request_skip()
		KEY_C:
			view.toggle_camera()
		KEY_M, KEY_TAB:
			view.toggle_minimap()
		KEY_G:
			go_camp()
		KEY_F5:
			save_game("quicksave")
		KEY_F9:
			if SaveGame.exists("quicksave"):
				load_game("quicksave")
		_:
			if key >= KEY_1 and key <= KEY_9 and journal.has_choices():
				journal.pick(key - KEY_1)


# ----------------------------------------------------------------------------------------------
# Screens
# ----------------------------------------------------------------------------------------------

func set_overlay(m: Modal) -> void:
	if overlay != null and is_instance_valid(overlay):
		overlay.queue_free()
	overlay = m
	add_child(m)
	m.closed.connect(func():
		if overlay == m:
			overlay = null)


func close_overlay() -> void:
	if overlay != null and is_instance_valid(overlay):
		overlay.close()
	overlay = null


func show_title() -> void:
	game.mode = "menu"
	game.over = false
	var t := TitleScreen.new()
	set_overlay(t)
	t.setup(self)


func open_builder(campaign_id: String) -> void:
	var b := BuilderScreen.new()
	set_overlay(b)
	b.setup(self, campaign_id)


func open_menu() -> void:
	var m := PauseMenu.new()
	set_overlay(m)
	m.setup(self)


func open_level_up(char_id: String) -> void:
	var c = game.state.roster.get(char_id)
	if c == null or not Progression.can_level_up(c) or game.encounter != null:
		return
	var l := LevelUpScreen.new()
	set_overlay(l)
	l.setup(self, c)


## Opens a shop and returns when the player closes it (awaited by the "shop.open" script op).
func open_shop(shop_id: String) -> void:
	var s := ShopScreen.new()
	set_overlay(s)
	s.setup(self, shop_id)
	await s.closed


func show_game_over(victory: bool, text: String) -> void:
	var m := PauseMenu.new()
	set_overlay(m)
	m.setup_game_over(self, victory, text)


# ----------------------------------------------------------------------------------------------
# Game actions
# ----------------------------------------------------------------------------------------------

func start_new_game(campaign_id: String, spec: Dictionary) -> void:
	close_overlay()
	if not game.load_campaign(campaign_id):
		show_title()
		return
	TexFactory.clear_cache()
	Portraits.clear_cache()
	audio.set_campaign(game.campaign.get("dir", ""))
	journal.reload()
	game.new_game(spec)


func load_game(slot: String) -> void:
	var data = SaveGame.read(slot)
	if typeof(data) != TYPE_DICTIONARY:
		return
	close_overlay()
	TexFactory.clear_cache()
	if game.load_data(data):
		audio.set_campaign(game.campaign.get("dir", ""))
		journal.reload()
		game.journal("system", "Game loaded.")
	else:
		show_title()


func save_game(slot: String) -> void:
	if game.mode != "explore" or game.busy > 0 or game.over or game.world.map == null:
		game.journal("system", "You can only save while exploring.")
		return
	if SaveGame.write(game, slot):
		game.journal("system", "Game saved (%s)." % slot)


func go_camp() -> void:
	if game.mode != "explore" or game.busy > 0 or not game.campaign.has("camp"):
		return
	if game.world.map.id == game.campaign.camp.map:
		game.leave_camp()
	else:
		game.go_to_camp()
