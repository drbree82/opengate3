class_name JournalPanel
extends PanelContainer
## BOTTOM-LEFT pane: the story so far, the player's choices, the quest log and the roll/combat log.
## It listens to game.journal_added; choices are shown by UiIO.choose() through show_choices().
##
## Journal entry kinds (game.journal(kind, text, extra)) and how they are drawn:
##   narration (italic) | speech (speaker name + text) | choice (what the player picked) |
##   system / quest (coloured notices) | combat (story + log) | roll (log only)

signal choice_made(index)

const MAX_LINES := 220

var game: Game
var audio: AudioBank
var tab := "Story"
var tab_row: HBoxContainer
var story: RichTextLabel
var quests: RichTextLabel
var log_view: RichTextLabel
var choices_box: VBoxContainer
var speaker_bar: HBoxContainer
var speaker_pic: TextureRect
var speaker_name: Label
var _story_lines: Array = []
var _log_lines: Array = []
var _choices: Array = []
var _dirty := false


func setup(g: Game, audio_bank: AudioBank) -> void:
	game = g
	audio = audio_bank
	var v := UiKit.vbox(6)
	add_child(v)
	tab_row = UiKit.tabs(["Story", "Quests", "Log"], _pick_tab)
	v.add_child(tab_row)
	story = UiKit.rich(16)
	story.scroll_following = true
	v.add_child(story)
	quests = UiKit.rich(15)
	quests.visible = false
	v.add_child(quests)
	log_view = UiKit.rich(13)
	log_view.scroll_following = true
	log_view.visible = false
	v.add_child(log_view)
	# who is speaking (portrait + name), shown during conversations
	speaker_bar = UiKit.hbox(10)
	speaker_bar.visible = false
	var pframe := UiKit.panel(UiKit.BG, UiKit.GOLD.darkened(0.3), 2)
	pframe.clip_contents = true
	speaker_pic = TextureRect.new()
	speaker_pic.custom_minimum_size = Vector2(84, 84)
	speaker_pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pframe.add_child(speaker_pic)
	speaker_bar.add_child(pframe)
	speaker_name = UiKit.label("", 20, UiKit.GOLD)
	speaker_name.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	speaker_bar.add_child(speaker_name)
	v.add_child(speaker_bar)
	choices_box = UiKit.vbox(4)
	v.add_child(choices_box)
	game.mode_changed.connect(_on_mode_changed)
	game.journal_added.connect(_on_entry)
	game.state_changed.connect(func(): _dirty = true)
	game.map_loaded.connect(reload)


func _process(_delta: float) -> void:
	if _dirty:
		_dirty = false
		if tab == "Quests":
			_draw_quests()


func _pick_tab(tab_name: String) -> void:
	tab = tab_name
	story.visible = tab == "Story"
	quests.visible = tab == "Quests"
	log_view.visible = tab == "Log"
	choices_box.visible = tab == "Story"
	if tab == "Quests":
		_draw_quests()
	if audio != null:
		audio.sfx("page")


func _select_tab(tab_name: String) -> void:
	for b in tab_row.get_children():
		if b is Button and b.text == tab_name:
			b.button_pressed = true
	_pick_tab(tab_name)


## Rebuilds both text views from game.state.journal (after loading a save or starting a game).
func reload() -> void:
	_story_lines.clear()
	_log_lines.clear()
	for e in game.state.get("journal", []):
		_format(e)
	_flush()


func _on_entry(e: Dictionary) -> void:
	_format(e)
	_flush()
	if e.get("kind", "") == "speech" and game.in_dialogue and str(e.get("speakerId", "")) != "":
		Portraits.apply(speaker_pic, game, str(e.speakerId))
		speaker_name.text = str(e.get("speaker", ""))
		speaker_bar.visible = speaker_pic.texture != null and tab == "Story"


func _on_mode_changed() -> void:
	if not game.in_dialogue:
		speaker_bar.visible = false


func _format(e: Dictionary) -> void:
	var text := UiKit.esc(e.get("text", ""))
	match e.get("kind", "system"):
		"narration":
			_story_lines.append("[i]%s[/i]" % UiKit.c(text, Color("#cfc6b4")))
		"speech":
			_story_lines.append("[b]%s[/b]  %s" % [UiKit.c(UiKit.esc(e.get("speaker", "?")), UiKit.GOLD), text])
		"choice":
			_story_lines.append(UiKit.c("   ▸ " + text, UiKit.BLUE))
		"quest":
			_story_lines.append("[b]%s[/b]" % UiKit.c("✦ " + text, UiKit.GOLD))
		"system":
			_story_lines.append(UiKit.c("• " + text, UiKit.PURPLE))
		"combat":
			_story_lines.append(UiKit.c(text, UiKit.DIM))
			_log_lines.append(text)
		"roll":
			_log_lines.append(UiKit.c(text, UiKit.DIM))
			var r: Dictionary = e.get("roll", {})
			if r.has("dc") and r.get("kind", "") in ["check", "save"] and game.encounter == null:
				var ok: bool = r.get("success", false)
				_story_lines.append(UiKit.c("   [lb]%s - %s: %d vs DC %d - %s[rb]" % [UiKit.esc(r.get("actor", "")), UiKit.esc(r.get("label", "")), int(r.get("total", 0)), int(r.dc), "success" if ok else "failure"], UiKit.GREEN if ok else UiKit.RED))
		_:
			_story_lines.append(text)
	if _story_lines.size() > MAX_LINES:
		_story_lines = _story_lines.slice(_story_lines.size() - MAX_LINES)
	if _log_lines.size() > MAX_LINES:
		_log_lines = _log_lines.slice(_log_lines.size() - MAX_LINES)


func _flush() -> void:
	story.text = "\n".join(_story_lines)
	log_view.text = "\n".join(_log_lines)


# ----------------------------------------------------------------------------------------------
# Choices
# ----------------------------------------------------------------------------------------------

## Shows numbered choice buttons. choices: [{text, tag?, disabled?}]. choice_made(index) fires on click.
func show_choices(choices: Array) -> void:
	_choices = choices
	UiKit.clear(choices_box)
	_select_tab("Story")
	for i in choices.size():
		var ch: Dictionary = choices[i]
		var b := Button.new()
		b.focus_mode = Control.FOCUS_NONE
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		b.disabled = ch.get("disabled", false)
		var tag: String = ch.get("tag", "")
		b.text = "%d.  %s%s" % [i + 1, ("[%s]  " % tag) if tag != "" else "", ch.get("text", "")]
		if tag != "":
			b.add_theme_color_override("font_color", Color("#f0dca0"))
		b.pressed.connect(func(): pick(i))
		choices_box.add_child(b)


func has_choices() -> bool:
	return not _choices.is_empty()


## Picks choice `index` (button click or number key).
func pick(index: int) -> void:
	if index < 0 or index >= _choices.size() or _choices[index].get("disabled", false):
		return
	_choices = []
	UiKit.clear(choices_box)
	if audio != null:
		audio.sfx("click")
	choice_made.emit(index)


# ----------------------------------------------------------------------------------------------
# Quest log
# ----------------------------------------------------------------------------------------------

func _draw_quests() -> void:
	var lines: Array = []
	var active: Array = []
	var done: Array = []
	for qid in game.state.get("quests", {}):
		if game.state.quests[qid].status == "active":
			active.append(qid)
		else:
			done.append(qid)
	if active.is_empty() and done.is_empty():
		lines.append(UiKit.c("No quests yet. Talk to people.", UiKit.DIM))
	for qid in active:
		var q := Quests.def(game, qid)
		var st: Dictionary = game.state.quests[qid]
		lines.append("[b]%s[/b]  %s" % [UiKit.c(UiKit.esc(q.get("name", qid)), UiKit.GOLD), UiKit.c("(%s quest)" % q.get("type", "side"), UiKit.DIM)])
		if q.get("summary", "") != "":
			lines.append("[i]%s[/i]" % UiKit.c(UiKit.esc(game.fmt(q.summary)), UiKit.DIM))
		for s in q.get("stages", []):
			if s.id == st.stage:
				lines.append("   ➤ %s" % UiKit.esc(game.fmt(s.get("text", ""))))
			elif s.id in st.seen:
				lines.append(UiKit.c("   ✔ [s]%s[/s]" % UiKit.esc(game.fmt(s.get("text", ""))), UiKit.DIM))
		lines.append("")
	if not done.is_empty():
		lines.append(UiKit.c("Finished", UiKit.DIM))
		for qid in done:
			var q := Quests.def(game, qid)
			var failed: bool = game.state.quests[qid].status == "failed"
			lines.append(UiKit.c("   %s %s" % ["✘" if failed else "✔", UiKit.esc(q.get("name", qid))], UiKit.RED if failed else UiKit.GREEN))
	quests.text = "\n".join(lines)
