class_name UiIO
extends GameIO
## The windowed implementation of GameIO: connects the engine to the four panes.
## Every method here overrides a headless default in src/engine/game_io.gd.
## Waiting is done by polling once per frame so that the player can always hurry things along
## (request_skip: Space, Enter or a click) and cutscenes can be skipped with Esc.

var main
var _skip := false


## The player wants the current text / dice animation to finish now.
func request_skip() -> void:
	_skip = true
	main.dice.skip_requested = true


func _frame() -> void:
	await main.get_tree().process_frame


## Waits `seconds`, or less if the player hurries or the cutscene is being skipped.
func _pause(seconds: float) -> void:
	_skip = false
	var t := 0.0
	while t < seconds and not _skip and not (game.in_cutscene and game.skip_cutscene):
		await _frame()
		t += main.get_process_delta_time()
	_skip = false


## Plays the voice clip for a line if one exists; otherwise waits a reading pause.
func _voice_or_pause(voice: String, seconds: float) -> void:
	if voice != "" and main.audio.play_voice(game.campaign.get("dir", ""), voice):
		_skip = false
		while main.audio.voice_playing() and not _skip and not (game.in_cutscene and game.skip_cutscene):
			await _frame()
		main.audio.stop_voice()
		_skip = false
		await _pause(0.15)
	else:
		await _pause(seconds)


func say(entry: Dictionary) -> void:
	var text: String = entry.get("text", "")
	await _voice_or_pause(entry.get("voice", ""), clampf(0.3 + text.length() * 0.012, 0.5, 2.2))


func choose(choices: Array) -> int:
	main.journal.show_choices(choices)
	var index: int = await main.journal.choice_made
	choice_log.append(choices[index].get("text", ""))
	return index


func show_roll(result: Dictionary, quick := false) -> void:
	await main.dice.play(result, quick)


func delay(seconds: float) -> void:
	var t := 0.0
	while t < seconds and not (game.in_cutscene and game.skip_cutscene):
		await _frame()
		t += main.get_process_delta_time()


func fade(to_black: bool, seconds: float) -> void:
	await main.view.fade(to_black, seconds)


func banner(text: String, sub := "") -> void:
	main.view.banner(text, sub)


func float_text(ent, text: String, kind := "info") -> void:
	main.view.float_text(ent, text, kind)


func subtitle(speaker: String, text: String, voice := "") -> void:
	main.view.show_subtitle(speaker, text)
	await _voice_or_pause(voice, clampf(0.8 + text.length() * 0.045, 1.6, 7.0))
	main.view.hide_subtitle()


func letterbox(on: bool) -> void:
	main.view.letterbox(on)


func sfx(sound: String) -> void:
	main.audio.sfx(sound)


func music(track: String) -> void:
	main.audio.music(game.campaign.get("dir", ""), track)


func spell_fx(from_ent, to, color: String) -> void:
	if from_ent == null:
		return
	var a := Vector3(from_ent.x, float(from_ent.sprite.get("height", 0.9)) * 0.6, from_ent.y)
	var b := a
	if to is Ent:
		b = Vector3(to.x, float(to.sprite.get("height", 0.9)) * 0.5, to.y)
	elif typeof(to) == TYPE_VECTOR2:
		b = Vector3(to.x, 0.3, to.y)
	await main.view.world.spell_fx(a, b, Util.color(color))


func title_card(text: String, sub: String, seconds: float) -> void:
	await main.view.title_card(text, sub, seconds)


func open_shop(shop_id: String) -> void:
	await main.open_shop(shop_id)


## Level-ups are made by the player on the character sheet; just announce it once.
func level_up(character: Dictionary) -> void:
	var note := "levelnote.%s.%d" % [character.get("id", ""), int(character.level)]
	if game.state.flags.get(note, false):
		return
	game.state.flags[note] = true
	game.journal("system", "%s can level up! Press the Level up button on the character sheet." % character.name)
	sfx("levelup")


func game_over(victory: bool, text: String) -> void:
	await main.show_game_over(victory, text)
