class_name PauseMenu
extends Modal
## In-game menu (Esc): save, load, settings, quit. Also used as the "game over / the end" screen.

var main


func setup(main_node) -> void:
	main = main_node
	var game: Game = main.game
	build_frame("Menu", Vector2(420, 0))
	content.add_child(UiKit.button("Resume", close))
	var can_save: bool = game.mode == "explore" and game.busy == 0 and not game.over
	var save_btn := UiKit.button("Save game", _save_and_close)
	save_btn.disabled = not can_save
	save_btn.tooltip_text = "" if can_save else "You can save while exploring (not mid-conversation or in a fight)."
	content.add_child(save_btn)
	content.add_child(UiKit.label("Load", 14, UiKit.DIM))
	var any := false
	for s in SaveGame.list():
		if s.campaignId != game.state.get("campaignId", ""):
			continue
		any = true
		var b := UiKit.button("%s  -  %s" % [s.slot, s.summary], main.load_game.bind(s.slot))
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		content.add_child(b)
	if not any:
		content.add_child(UiKit.label("   no saves yet", 13, UiKit.DIM))

	content.add_child(UiKit.label("Settings", 14, UiKit.DIM))
	var dc := CheckBox.new()
	dc.text = "Show difficulty (DC) on choices"
	dc.button_pressed = game.settings.get("show_dc", true)
	dc.toggled.connect(func(on): game.settings["show_dc"] = on)
	content.add_child(dc)
	var fast := CheckBox.new()
	fast.text = "Fast dice"
	fast.button_pressed = float(game.settings.get("dice_speed", 1.0)) > 1.5
	fast.toggled.connect(func(on): game.settings["dice_speed"] = 2.5 if on else 1.0)
	content.add_child(fast)
	var mute := CheckBox.new()
	mute.text = "Mute sound"
	mute.button_pressed = main.audio.muted
	mute.toggled.connect(func(on): main.audio.muted = on)
	content.add_child(mute)

	content.add_child(UiKit.button("Licences", main.open_licenses.bind(main.open_menu), "Licences and third-party notices"))
	content.add_child(UiKit.button("Quit to title", func(): main.show_title()))
	content.add_child(UiKit.button("Quit game", func(): main.get_tree().quit()))


## The campaign ended: victory text or defeat, with a way back.
func setup_game_over(main_node, victory: bool, text: String) -> void:
	main = main_node
	escapable = false
	build_frame("The End" if victory else "Defeat", Vector2(520, 0), 0.85)
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	heading.add_theme_font_size_override("font_size", 40)
	if not victory:
		heading.add_theme_color_override("font_color", UiKit.RED)
	var body := UiKit.label(text if text != "" else ("Your adventure is complete." if victory else "Your party has fallen."), 17, UiKit.TEXT)
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content.add_child(body)
	if not victory:
		for s in SaveGame.list():
			if s.campaignId == main.game.state.get("campaignId", ""):
				content.add_child(UiKit.button("Load: %s  -  %s" % [s.slot, s.summary], main.load_game.bind(s.slot)))
				break
	else:
		content.add_child(UiKit.button("Keep exploring", _keep_exploring))
	content.add_child(UiKit.button("Back to title", func(): main.show_title()))


func _save_and_close() -> void:
	main.save_game("save")
	close()


func _keep_exploring() -> void:
	main.game.over = false
	close()
