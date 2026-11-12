class_name JournalPanel
extends PanelContainer
## BOTTOM-LEFT pane: the story so far, the player's choices, the quest log, the creatures met so far
## and the roll/combat log.
## It listens to game.journal_added; choices are shown by UiIO.choose() through show_choices().
##
## Journal entry kinds (game.journal(kind, text, extra)) and how they are drawn:
##   narration (italic) | speech (speaker name + text) | choice (what the player picked) |
##   system / quest (coloured notices) | combat (story + log) | roll (log only) |
##   foes ("You face: ..." with one hover link per creature)
##
## Creature sheets: the Creatures tab lists every creature the party has fought (game.state.bestiary).
## Hovering a creature's name there - or in a "You face" line of the story - opens a tooltip with its
## numbers and plain-English notes on strengths, weaknesses and powers. The text comes from
## MonsterLore.describe() (src/rules/monster_lore.gd); this file only lays it out (_creature_bbcode).
## Links are RichTextLabel [url] tags whose meta is "creature:<monster id>".

signal choice_made(index)

const MAX_LINES := 220

var game: Game
var audio: AudioBank
var tab := "Story"
var tab_row: HBoxContainer
var story: RichTextLabel
var quests: RichTextLabel
var creatures: RichTextLabel
var log_view: RichTextLabel
var tip_layer: CanvasLayer
var tip: PanelContainer
var tip_text: RichTextLabel
var tip_id := ""                # monster id the tooltip is showing ("" = hidden)
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
	tab_row = UiKit.tabs(["Story", "Quests", "Creatures", "Log"], _pick_tab)
	v.add_child(tab_row)
	story = UiKit.rich(16)
	story.scroll_following = true
	v.add_child(story)
	quests = UiKit.rich(15)
	quests.visible = false
	v.add_child(quests)
	creatures = UiKit.rich(15)
	creatures.visible = false
	v.add_child(creatures)
	for view in [story, creatures]:
		view.meta_underlined = true
		view.meta_hover_started.connect(_on_meta_hover)
		view.meta_hover_ended.connect(_on_meta_leave)
	_build_tip()
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
		elif tab == "Creatures":
			_draw_creatures()
	if tip.visible:
		_place_tip()


func _pick_tab(tab_name: String) -> void:
	tab = tab_name
	story.visible = tab == "Story"
	quests.visible = tab == "Quests"
	creatures.visible = tab == "Creatures"
	log_view.visible = tab == "Log"
	choices_box.visible = tab == "Story"
	hide_creature()
	if tab == "Quests":
		_draw_quests()
	elif tab == "Creatures":
		_draw_creatures()
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
		"foes":
			var names: Array = []
			for cr in e.get("creatures", []):
				var label := UiKit.esc(game.db.monsters.get(cr.id, {}).get("name", cr.id))
				if int(cr.get("count", 1)) > 1:
					label = "%d x %s" % [int(cr.count), label]
				names.append(_creature_link(str(cr.id), label))
			_story_lines.append("%s %s  %s" % [UiKit.c("You face:", UiKit.DIM), ", ".join(names), UiKit.c("(point at a name for its strengths and weaknesses)", UiKit.DIM)])
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


# ----------------------------------------------------------------------------------------------
# Creatures: the list of creatures met so far, and the hover tooltip with a creature's sheet
# ----------------------------------------------------------------------------------------------

## BBCode for a creature name that opens the creature tooltip when the mouse points at it.
func _creature_link(monster_id: String, label: String) -> String:
	return "[url=creature:%s]%s[/url]" % [monster_id, UiKit.c(label, UiKit.GOLD)]


func _draw_creatures() -> void:
	var book: Dictionary = game.state.get("bestiary", {})
	var lines: Array = []
	if book.is_empty():
		lines.append(UiKit.c("No creatures yet. Everything you fight is written down here.", UiKit.DIM))
	else:
		lines.append(UiKit.c("Point at a name to read what your party knows about it.", UiKit.DIM))
		lines.append("")
	var ids: Array = book.keys()
	ids.sort_custom(func(a, b): return str(game.db.monsters.get(a, {}).get("name", a)) < str(game.db.monsters.get(b, {}).get("name", b)))
	for mid in ids:
		var d := MonsterLore.describe(str(mid), game.db)
		if d.is_empty():
			continue
		var rec: Dictionary = book[mid]
		lines.append("[b]%s[/b]  %s" % [_creature_link(str(mid), UiKit.esc(d.name)), UiKit.c("%s  -  fought %d, slain %d" % [UiKit.esc(d.kind), int(rec.get("met", 0)), int(rec.get("slain", 0))], UiKit.DIM)])
		if d.desc != "":
			lines.append("   [i]%s[/i]" % UiKit.c(UiKit.esc(d.desc), Color("#cfc6b4")))
	creatures.text = "\n".join(lines)


## The creature sheet as BBCode: description, numbers, then strengths / weaknesses / powers.
func _creature_bbcode(monster_id: String) -> String:
	var d := MonsterLore.describe(monster_id, game.db)
	if d.is_empty():
		return ""
	var lines: Array = ["[b]%s[/b]   %s" % [UiKit.c(UiKit.esc(d.name), UiKit.GOLD), UiKit.c(UiKit.esc(d.kind), UiKit.DIM)]]
	if d.desc != "":
		lines.append("[i]%s[/i]" % UiKit.c(UiKit.esc(d.desc), Color("#cfc6b4")))
	lines.append("")
	for row in d.stats:
		lines.append("%s  %s" % [UiKit.c(UiKit.esc(row[0]), UiKit.DIM), UiKit.esc(row[1])])
	for section in [["Strengths", d.strengths, UiKit.RED], ["Weaknesses", d.weaknesses, UiKit.GREEN], ["Attacks and powers", d.powers, UiKit.BLUE]]:
		if section[1].is_empty():
			continue
		lines.append("")
		lines.append("[b]%s[/b]" % UiKit.c(section[0], section[2]))
		for sentence in section[1]:
			lines.append(" • " + UiKit.esc(sentence))
	return "\n".join(lines)


func _build_tip() -> void:
	tip_layer = CanvasLayer.new()
	tip_layer.layer = 60
	add_child(tip_layer)
	tip = UiKit.panel(UiKit.BG, UiKit.GOLD.darkened(0.2), 12)
	tip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tip.visible = false
	tip_text = UiKit.rich(14)
	tip_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tip_text.scroll_active = false
	tip_text.fit_content = true
	tip_text.custom_minimum_size = Vector2(520, 0)
	tip_text.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	tip.add_child(tip_text)
	tip_layer.add_child(tip)


func _on_meta_hover(meta) -> void:
	if str(meta).begins_with("creature:"):
		show_creature(str(meta).substr(9))


func _on_meta_leave(_meta) -> void:
	hide_creature()


## Opens the creature tooltip next to the mouse (also called by the developer tours).
func show_creature(monster_id: String) -> void:
	var text := _creature_bbcode(monster_id)
	if text == "":
		return
	tip_id = monster_id
	tip_text.text = text
	tip.visible = true
	tip.reset_size()
	_place_tip()


func hide_creature() -> void:
	tip_id = ""
	if tip != null:
		tip.visible = false


## Keeps the tooltip beside the mouse and inside the window.
func _place_tip() -> void:
	var screen := get_viewport_rect().size
	var mouse := get_viewport().get_mouse_position()
	tip.size = tip.get_combined_minimum_size()
	var pos := mouse + Vector2(22, -tip.size.y * 0.5)
	if pos.x + tip.size.x > screen.x - 8.0:
		pos.x = mouse.x - tip.size.x - 22.0
	pos.x = clampf(pos.x, 8.0, maxf(8.0, screen.x - tip.size.x - 8.0))
	pos.y = clampf(pos.y, 8.0, maxf(8.0, screen.y - tip.size.y - 8.0))
	tip.position = pos
