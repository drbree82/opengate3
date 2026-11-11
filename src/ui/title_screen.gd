class_name TitleScreen
extends Modal
## First screen: pick a campaign, then start a new game or continue from a save.

var main
var campaigns: Array = []
var selected := 0
var list_box: VBoxContainer
var info: RichTextLabel
var saves_box: VBoxContainer


func setup(main_node) -> void:
	main = main_node
	escapable = false
	build_frame("", Vector2(980, 600), 1.0)
	var title := UiKit.label("OpenGate", 54, UiKit.GOLD)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content.add_child(title)
	var tag := UiKit.label("An open Pathfinder adventure framework", 16, UiKit.DIM)
	tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content.add_child(tag)

	var row := UiKit.hbox(18)
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(row)
	var left := UiKit.vbox(6)
	left.custom_minimum_size = Vector2(300, 0)
	left.add_child(UiKit.label("Campaigns", 15, UiKit.DIM))
	list_box = UiKit.vbox(4)
	left.add_child(list_box)
	row.add_child(left)

	var right := UiKit.vbox(8)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info = UiKit.rich(15)
	info.custom_minimum_size = Vector2(0, 150)
	info.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	info.fit_content = true
	right.add_child(info)
	var buttons := UiKit.hbox(8)
	var new_btn := UiKit.button("  New game  ", _new_game)
	new_btn.add_theme_font_size_override("font_size", 18)
	new_btn.add_theme_color_override("font_color", UiKit.GOLD)
	buttons.add_child(new_btn)
	buttons.add_child(UiKit.spacer())
	buttons.add_child(UiKit.button("Quit", func(): main.get_tree().quit()))
	right.add_child(buttons)
	right.add_child(UiKit.label("Saved games", 15, UiKit.DIM))
	var sl := Modal.scroll_list(Vector2(0, 200))
	saves_box = sl[1]
	right.add_child(sl[0])
	row.add_child(right)

	campaigns = Campaign.list()
	_draw()


func _draw() -> void:
	UiKit.clear(list_box)
	if campaigns.is_empty():
		list_box.add_child(UiKit.label("No campaigns found in campaigns/.", 14, UiKit.RED))
		info.text = "Create one with tools/new_campaign.sh"
		return
	for i in campaigns.size():
		var b := UiKit.button(campaigns[i].name, _select.bind(i))
		b.toggle_mode = true
		b.button_pressed = i == selected
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		list_box.add_child(b)
	var c: Dictionary = campaigns[selected]
	info.text = "[b]%s[/b]\n%s\n\n%s" % [UiKit.c(UiKit.esc(c.name), UiKit.GOLD), UiKit.c("by " + UiKit.esc(c.author), UiKit.DIM) if c.author != "" else "", UiKit.esc(c.description)]
	UiKit.clear(saves_box)
	var any := false
	for s in SaveGame.list():
		if s.campaignId != c.id:
			continue
		any = true
		var when := Time.get_datetime_string_from_unix_time(int(s.time), true)
		var b := UiKit.button("%s   -   %s   (%s)" % [s.slot, s.summary, when], main.load_game.bind(s.slot))
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		saves_box.add_child(b)
	if not any:
		saves_box.add_child(UiKit.label("No saves for this campaign yet.", 14, UiKit.DIM))


func _select(i: int) -> void:
	selected = i
	_draw()


func _new_game() -> void:
	if campaigns.is_empty():
		return
	main.open_builder(campaigns[selected].id)
