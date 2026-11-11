class_name LicensesScreen
extends Modal
## "Licences" screen, opened from the title screen and the pause menu (main.open_licenses).
## It shows the notices a distributed game has to show: this game's own licence, the Open Game License
## for the Pathfinder rules (OGL.txt), Godot Engine's licence and the third-party code built into the
## engine. Keep a way to reach this screen in every build.
## All of the text comes from Notices (src/core/notices.gd). Background: docs/LICENSING.md.

const TABS := ["This game", "Game rules", "Godot Engine", "Third-party", "Licence texts"]

var tab := "This game"
var tab_row: HBoxContainer
var body: RichTextLabel
var picker: OptionButton


func setup(_main_node) -> void:
	build_frame("Licences", Vector2(1040, 640))
	var top := UiKit.hbox(10)
	tab_row = UiKit.tabs(TABS, _pick_tab, tab)
	top.add_child(tab_row)
	# which licence text to show (only on the "Licence texts" tab)
	picker = OptionButton.new()
	picker.focus_mode = Control.FOCUS_NONE
	for id in Notices.license_ids():
		picker.add_item(str(id))
	picker.item_selected.connect(_pick_license)
	picker.visible = false
	top.add_child(picker)
	content.add_child(top)
	body = UiKit.rich(14)
	body.bbcode_enabled = false
	body.selection_enabled = true
	body.custom_minimum_size = Vector2(0, 470)
	content.add_child(body)
	var row := UiKit.hbox(8)
	row.add_child(UiKit.label("These notices also ship as a file: see docs/LICENSING.md", 13, UiKit.DIM))
	var gap := UiKit.spacer()
	gap.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(gap)
	row.add_child(UiKit.button("   Back   ", close))
	content.add_child(row)
	_draw()


## Shows one of TABS from code (the buttons call _pick_tab themselves).
func select_tab(tab_name: String) -> void:
	for b in tab_row.get_children():
		if b is Button and b.text == tab_name:
			b.button_pressed = true
	_pick_tab(tab_name)


func _pick_tab(tab_name: String) -> void:
	tab = tab_name
	_draw()


func _pick_license(_index: int) -> void:
	_draw()


func _draw() -> void:
	picker.visible = tab == "Licence texts"
	match tab:
		"Game rules":
			body.text = Notices.rules_license()
		"Godot Engine":
			body.text = Notices.engine()
		"Third-party":
			body.text = Notices.components_text()
		"Licence texts":
			var id := picker.get_item_text(picker.selected) if picker.selected >= 0 else ""
			body.text = Notices.license_text(id) if id != "" else "This engine build lists no separate licence texts."
		_:
			body.text = "%s\n\n%s\n\n%s" % [Notices.project(), Notices.RULE, Notices.project_notices()]
	body.scroll_to_line(0)
