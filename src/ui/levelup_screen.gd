class_name LevelUpScreen
extends Modal
## Level-up choices for one character: hit point roll, skill ranks, feats, ability increase, new spells.
## What may be chosen comes from Progression.requirements(); the result is applied by
## Progression.level_up(). "Choose for me" uses Game.auto_level().

var main
var game: Game
var c: Dictionary
var req: Dictionary
var choices := {"skillRanks": {}, "feats": [], "spells": [], "ability": "", "hpRoll": 0}
var hp_label: Label
var skill_head: Label
var feat_head: Label
var spell_head: Label
var skill_box: VBoxContainer
var problem: Label


func setup(main_node, character: Dictionary) -> void:
	main = main_node
	game = main.game
	c = character
	req = Progression.requirements(c, game.db)
	build_frame("%s reaches level %d" % [c.name, int(req.newLevel)], Vector2(760, 0))

	var hp_row := UiKit.hbox(8)
	hp_label = UiKit.label("Hit points: roll your d%d (or take the average, %d)" % [int(req.hitDie), int(req.hitDie) / 2 + 1], 15)
	hp_row.add_child(hp_label)
	hp_row.add_child(UiKit.spacer())
	hp_row.add_child(UiKit.button("Roll d%d" % int(req.hitDie), _roll_hp))
	hp_row.add_child(UiKit.button("Take %d" % (int(req.hitDie) / 2 + 1), _take_average))
	content.add_child(hp_row)

	var cols := UiKit.hbox(14)
	content.add_child(cols)
	var left := UiKit.vbox(4)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cols.add_child(left)
	skill_head = UiKit.label("", 15, UiKit.GOLD)
	left.add_child(skill_head)
	var sl := Modal.scroll_list(Vector2(340, 300))
	skill_box = sl[1]
	left.add_child(sl[0])
	_draw_skills()

	var right := UiKit.vbox(4)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cols.add_child(right)
	var stats: Dictionary = game.stats(c)
	if int(req.feats) > 0:
		feat_head = UiKit.label("", 15, UiKit.GOLD)
		right.add_child(feat_head)
		var fl := Modal.scroll_list(Vector2(340, 150))
		right.add_child(fl[0])
		for fid in game.db.feats:
			var feat: Dictionary = game.db.feats[fid]
			if CharRules.has_feat(c, fid) or feat.has("param"):
				continue
			var cb := CheckBox.new()
			cb.focus_mode = Control.FOCUS_NONE
			cb.text = feat.name
			cb.tooltip_text = feat.get("desc", "")
			cb.disabled = not Progression.feat_available(c, feat, game.db, stats)
			cb.toggled.connect(_toggle.bind(fid, cb, "feats", int(req.feats)))
			fl[1].add_child(cb)
	if req.abilityIncrease:
		right.add_child(UiKit.label("+1 to an ability score", 15, UiKit.GOLD))
		var ob := OptionButton.new()
		for a in CharRules.ABILITIES:
			ob.add_item(CharRules.ABILITY_NAMES[a])
		ob.item_selected.connect(func(i): choices["ability"] = CharRules.ABILITIES[i])
		choices.ability = CharRules.ABILITIES[0]
		right.add_child(ob)
	if int(req.spells) > 0:
		spell_head = UiKit.label("", 15, UiKit.GOLD)
		right.add_child(spell_head)
		var pl := Modal.scroll_list(Vector2(340, 130))
		right.add_child(pl[0])
		var max_level := ceili(int(req.newLevel) / 2.0)
		for sid in game.db.spells:
			var lv = game.db.spells[sid].get("levels", {}).get(c.cls)
			if lv == null or int(lv) < 1 or int(lv) > max_level or sid in c.spells:
				continue
			var cb := CheckBox.new()
			cb.focus_mode = Control.FOCUS_NONE
			cb.text = "%s (level %d)" % [game.db.spells[sid].name, int(lv)]
			cb.tooltip_text = game.db.spells[sid].get("desc", "")
			cb.toggled.connect(_toggle.bind(sid, cb, "spells", int(req.spells)))
			pl[1].add_child(cb)
	_heads()

	problem = UiKit.label("", 14, UiKit.RED)
	content.add_child(problem)
	var buttons := UiKit.hbox(8)
	buttons.add_child(UiKit.button("Later", close))
	buttons.add_child(UiKit.button("Choose for me", _auto))
	buttons.add_child(UiKit.spacer())
	var ok := UiKit.button("   Confirm   ", _confirm)
	ok.add_theme_color_override("font_color", UiKit.GOLD)
	buttons.add_child(ok)
	content.add_child(buttons)


func _spent() -> int:
	var n := 0
	for sid in choices.skillRanks:
		n += int(choices.skillRanks[sid])
	return n


func _heads() -> void:
	skill_head.text = "Skill ranks   %d / %d" % [_spent(), int(req.skillPoints)]
	if feat_head != null:
		feat_head.text = "Feats   %d / %d" % [choices.feats.size(), int(req.feats)]
	if spell_head != null:
		spell_head.text = "New spells   %d / %d" % [choices.spells.size(), int(req.spells)]


func _draw_skills() -> void:
	UiKit.clear(skill_box)
	var cls: Dictionary = game.db.classes[c.cls]
	var ids: Array = game.db.skills.keys()
	ids.sort()
	for sid in ids:
		var have: int = int(c.skillRanks.get(sid, 0)) + int(choices.skillRanks.get(sid, 0))
		var row := UiKit.hbox(4)
		var l := UiKit.label("%s  %d" % [game.db.skills[sid].name, have], 14, UiKit.GOLD if sid in cls.classSkills else UiKit.TEXT)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(l)
		var minus := UiKit.button("-", _rank.bind(sid, -1))
		minus.disabled = int(choices.skillRanks.get(sid, 0)) <= 0
		row.add_child(minus)
		var plus := UiKit.button("+", _rank.bind(sid, 1))
		plus.disabled = have >= int(req.newLevel) or _spent() >= int(req.skillPoints)
		row.add_child(plus)
		skill_box.add_child(row)


func _rank(sid: String, by: int) -> void:
	var v: int = int(choices.skillRanks.get(sid, 0)) + by
	if v <= 0:
		choices.skillRanks.erase(sid)
	else:
		choices.skillRanks[sid] = v
	_draw_skills()
	_heads()


func _toggle(on: bool, id: String, cb: CheckBox, key: String, limit: int) -> void:
	if on and choices[key].size() >= limit:
		cb.set_pressed_no_signal(false)
		return
	if on:
		choices[key].append(id)
	else:
		choices[key].erase(id)
	_heads()


func _roll_hp() -> void:
	if int(choices.hpRoll) > 0:
		return
	var rolled := Dice.roll("1d%d" % int(req.hitDie), game.rng)
	choices.hpRoll = int(rolled.total)
	hp_label.text = "Hit points: rolled %d" % int(rolled.total)
	game.show_roll(Dice.as_result(rolled, "raw", "Hit die", c.name))


func _take_average() -> void:
	if int(choices.hpRoll) > 0:
		return
	choices.hpRoll = int(req.hitDie) / 2 + 1
	hp_label.text = "Hit points: took %d" % int(choices.hpRoll)


func _auto() -> void:
	game.auto_level(c)
	close()


func _confirm() -> void:
	if int(choices.hpRoll) <= 0:
		problem.text = "Roll your hit die or take the average first."
		return
	var res := Progression.level_up(c, game.db, choices)
	game.journal("system", "%s reaches level %d! (+%d hp)" % [c.name, int(res.level), int(res.hpGained)])
	game.io.sfx("levelup")
	game.world.sync_party()
	game.state_changed.emit()
	close()
