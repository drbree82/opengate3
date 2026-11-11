class_name BuilderScreen
extends Modal
## Character creation, shown after "New game":
##   step 1  choose a pre-made hero (the campaign's companions, like origin characters) or "Create your own"
##   step 2  the custom builder: name, race, class, 15-point-buy abilities, skills, feats, spells, looks
## The result is a "spec" Dictionary handed to main.start_new_game() -> Game.new_game() -> CharRules.create().
## Rules questions (how many feats, valid builds) are answered by src/rules (Progression, CharRules).

const SKIN := ["#f1c9a5", "#e0ac82", "#c98f66", "#a5673f", "#7a4a2a", "#5a3620", "#6f9440", "#9aa8c8"]
const HAIR := ["#1a1410", "#3b2a1a", "#6b4a2a", "#a8742a", "#d9b45a", "#b8452a", "#d8d8d8", "#5a6a9a"]
const CLOTH := ["#8a8f98", "#7a2a2a", "#2a4a7a", "#3d5a3a", "#5a3a7a", "#8a6a2a", "#3a3a40", "#c9c2a8"]
const HAIR_STYLES := ["short", "long", "wavy", "ponytail", "bun", "braids", "curly", "topknot", "mohawk", "bald", "hood", "helm", "hat"]
const BODIES := ["masculine", "feminine"]
## Builds offered per body type ("" = the usual build of the chosen race). See docs/SPRITES.md.
const BUILDS := {
	"masculine": ["", "heroic", "slim", "rustic", "heavy"],
	"feminine": ["", "curvy", "slender", "athletic", "rustic", "heavy"],
}

var main
var game: Game
var campaign_id := ""
var spec: Dictionary = {}
var page: Control
var ability_box: VBoxContainer
var choice_box: VBoxContainer
var identity_box: VBoxContainer
var summary: RichTextLabel
var preview: TextureRect
var errors: Label


func setup(main_node, campaign: String) -> void:
	main = main_node
	game = main.game
	campaign_id = campaign
	game.load_campaign(campaign)
	build_frame("", Vector2(1240, 760), 0.92)
	_show_heroes()


func _swap(title: String) -> void:
	UiKit.clear(content)
	heading = UiKit.label(title, 26, UiKit.GOLD)
	content.add_child(heading)


# ----------------------------------------------------------------------------------------------
# Step 1: pre-made heroes
# ----------------------------------------------------------------------------------------------

func _show_heroes() -> void:
	_swap("Choose your hero")
	content.add_child(UiKit.label("Play one of the campaign's heroes - the others can join you along the way - or create your own.", 15, UiKit.DIM))
	var sc := ScrollContainer.new()
	sc.custom_minimum_size = Vector2(1200, 560)
	sc.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	content.add_child(sc)
	var row := UiKit.hbox(10)
	sc.add_child(row)
	var comps: Dictionary = game.campaign.get("companions", {})
	for cid in comps:
		var comp: Dictionary = comps[cid]
		if comp.get("playable", true):
			row.add_child(_hero_card(cid, comp))
	var own := UiKit.panel(UiKit.PANEL_2, UiKit.BORDER, 12)
	own.custom_minimum_size = Vector2(226, 0)
	var ov := UiKit.vbox(8)
	own.add_child(ov)
	ov.add_child(UiKit.label("Create your own", 20, UiKit.GOLD))
	var t := UiKit.label("Pick a race and class, spend ability points, and choose skills, feats and looks.", 14, UiKit.TEXT)
	t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	ov.add_child(t)
	ov.add_child(UiKit.spacer())
	ov.add_child(UiKit.button("Create a character", _show_custom))
	row.add_child(own)
	content.add_child(UiKit.button("Back", func(): main.show_title()))


func _hero_card(cid: String, comp: Dictionary) -> Control:
	var card := UiKit.panel(UiKit.PANEL_2, UiKit.BORDER, 12)
	card.custom_minimum_size = Vector2(226, 0)
	var v := UiKit.vbox(6)
	card.add_child(v)
	var pic := TextureRect.new()
	pic.custom_minimum_size = Vector2(0, 226)
	pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pic.clip_contents = true
	var with_id: Dictionary = comp.duplicate()
	with_id["id"] = cid
	Portraits.apply(pic, game, with_id)
	v.add_child(pic)
	v.add_child(UiKit.label(comp.get("name", cid), 20, UiKit.GOLD))
	v.add_child(UiKit.label("%s %s" % [game.db.races[comp.race].name, game.db.classes[comp.cls].name], 14, UiKit.DIM))
	var st := CharRules.derive(CharRules.create(comp, game.db), game.db)
	v.add_child(UiKit.label("HP %d   AC %d   %s %s" % [int(st.hpMax), int(st.ac), st.attacks[0].name, Util.signed(st.attacks[0].bonus)], 13, UiKit.TEXT))
	var bio := UiKit.label(comp.get("bio", ""), 14, UiKit.TEXT)
	bio.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	bio.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(bio)
	v.add_child(UiKit.button("Play as %s" % str(comp.get("name", cid)).get_slice(" ", 0), _pick_hero.bind(cid)))
	return card


func _pick_hero(cid: String) -> void:
	var s: Dictionary = game.campaign.companions[cid].duplicate(true)
	s["id"] = cid
	main.start_new_game(campaign_id, s)


# ----------------------------------------------------------------------------------------------
# Step 2: custom character
# ----------------------------------------------------------------------------------------------

func _show_custom() -> void:
	if spec.is_empty():
		spec = {
			"id": "player", "name": "", "race": "human", "cls": "fighter", "racialChoice": "str",
			"abilities": {"str": 15, "dex": 13, "con": 14, "int": 10, "wis": 12, "cha": 8},
			"skillRanks": {}, "feats": [], "spells": [],
			"look": {"body": "masculine", "build": "", "skin": SKIN[1], "hair": HAIR[1], "hairStyle": "short", "top": CLOTH[0]},
		}
	_swap("Create your character")
	var cols := UiKit.hbox(16)
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(cols)
	identity_box = UiKit.vbox(6)
	identity_box.custom_minimum_size = Vector2(380, 600)
	cols.add_child(identity_box)
	var mid := UiKit.vbox(8)
	mid.custom_minimum_size = Vector2(380, 0)
	cols.add_child(mid)
	ability_box = UiKit.vbox(4)
	mid.add_child(ability_box)
	summary = UiKit.rich(14)
	mid.add_child(summary)
	choice_box = UiKit.vbox(6)
	choice_box.custom_minimum_size = Vector2(400, 0)
	choice_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cols.add_child(choice_box)

	errors = UiKit.label("", 14, UiKit.RED)
	errors.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(errors)
	var buttons := UiKit.hbox(8)
	buttons.add_child(UiKit.button("Back", _show_heroes))
	buttons.add_child(UiKit.spacer())
	var go := UiKit.button("   Begin adventure   ", _begin)
	go.add_theme_font_size_override("font_size", 18)
	go.add_theme_color_override("font_color", UiKit.GOLD)
	buttons.add_child(go)
	content.add_child(buttons)
	_draw_identity()
	_draw_abilities()
	_draw_choices()
	_update_summary()


func _option(items: Array, labels: Array, current, on_pick: Callable) -> OptionButton:
	var ob := OptionButton.new()
	ob.focus_mode = Control.FOCUS_NONE
	for i in items.size():
		ob.add_item(labels[i])
		if items[i] == current:
			ob.selected = i
	ob.item_selected.connect(func(i): on_pick.call(items[i]))
	return ob


func _draw_identity() -> void:
	UiKit.clear(identity_box)
	var top := UiKit.hbox(10)
	identity_box.add_child(top)
	var pframe := UiKit.panel(UiKit.BG, UiKit.BORDER, 4)
	preview = TextureRect.new()
	preview.custom_minimum_size = Vector2(120, 120)
	preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	preview.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	pframe.add_child(preview)
	top.add_child(pframe)
	var tv := UiKit.vbox(6)
	tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(tv)
	tv.add_child(UiKit.label("Name", 13, UiKit.DIM))
	var name_edit := LineEdit.new()
	name_edit.text = spec.name
	name_edit.placeholder_text = "Your hero's name"
	name_edit.max_length = 24
	name_edit.text_changed.connect(func(t): spec["name"] = t)
	tv.add_child(name_edit)
	var race_ids: Array = game.db.races.keys()
	var cls_ids: Array = game.db.classes.keys()
	var rrow := UiKit.hbox(6)
	rrow.add_child(_option(race_ids, race_ids.map(func(r): return game.db.races[r].name), spec.race, _set_race))
	rrow.add_child(_option(cls_ids, cls_ids.map(func(c): return game.db.classes[c].name), spec.cls, _set_class))
	tv.add_child(rrow)

	var race: Dictionary = game.db.races[spec.race]
	var cls: Dictionary = game.db.classes[spec.cls]
	var text := UiKit.rich(13)
	text.custom_minimum_size = Vector2(0, 200)
	var t := "[b]%s[/b]  %s\n" % [UiKit.c(race.name, UiKit.GOLD), UiKit.c(race.get("desc", ""), UiKit.DIM)]
	for tr in race.get("traits", []):
		t += "  • %s\n" % tr
	t += "\n[b]%s[/b]  %s\n" % [UiKit.c(cls.name, UiKit.GOLD), UiKit.c(cls.get("desc", ""), UiKit.DIM)]
	t += "  • Hit die d%d, %s attack bonus, %d + Int skill ranks\n" % [int(cls.hitDie), cls.bab, int(cls.skillRanks)]
	for f in cls.get("features", []):
		if int(f.get("level", 1)) == 1:
			t += "  • %s\n" % f.name
	text.text = t
	identity_box.add_child(text)

	identity_box.add_child(UiKit.label("Appearance", 13, UiKit.DIM))
	var body: String = spec.look.get("body", "masculine")
	var builds: Array = BUILDS[body]
	var brow := UiKit.hbox(6)
	brow.add_child(UiKit.label("Body", 13))
	brow.add_child(_option(BODIES, BODIES.map(func(b): return b.capitalize()), body, _set_body))
	brow.add_child(UiKit.label("Build", 13))
	brow.add_child(_option(builds, builds.map(func(b): return "Default" if b == "" else b.capitalize()), spec.look.get("build", ""), _set_look.bind("build")))
	identity_box.add_child(brow)
	var hrow := UiKit.hbox(6)
	hrow.add_child(UiKit.label("Hair style", 13))
	hrow.add_child(_option(HAIR_STYLES, HAIR_STYLES.map(func(h): return h.capitalize()), spec.look.get("hairStyle", "short"), _set_look.bind("hairStyle")))
	if body == "masculine":
		var beard := CheckBox.new()
		beard.text = "Beard"
		beard.focus_mode = Control.FOCUS_NONE
		beard.button_pressed = spec.look.get("beard", false) == true
		beard.toggled.connect(func(on): _set_look(on, "beard"))
		hrow.add_child(beard)
	identity_box.add_child(hrow)
	identity_box.add_child(_swatches("Skin", "skin", SKIN))
	identity_box.add_child(_swatches("Hair", "hair", HAIR))
	identity_box.add_child(_swatches("Outfit", "top", CLOTH))
	_update_preview()


func _swatches(label: String, key: String, colors: Array) -> Control:
	var row := UiKit.hbox(4)
	var l := UiKit.label(label, 13)
	l.custom_minimum_size = Vector2(70, 0)
	row.add_child(l)
	for hex in colors:
		var b := Button.new()
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(26, 24)
		var picked: bool = spec.look.get(key, "") == hex
		b.add_theme_stylebox_override("normal", UiKit.box(Color.html(hex), UiKit.GOLD if picked else UiKit.BORDER, 3 if picked else 1, 3, 0, 0))
		b.add_theme_stylebox_override("hover", UiKit.box(Color.html(hex).lightened(0.15), UiKit.GOLD, 2, 3, 0, 0))
		b.pressed.connect(_set_look.bind(hex, key))
		row.add_child(b)
	return row


## Called as _set_look(value, key) (the key is bound, so it arrives last).
func _set_look(value, key: String) -> void:
	spec.look[key] = value
	_draw_identity()


func _set_body(body: String) -> void:
	spec.look["body"] = body
	spec.look["build"] = ""
	spec.look.erase("beard")
	_draw_identity()


func _update_preview() -> void:
	if preview != null:
		preview.texture = SpriteFactory.portrait(game.world.sprite_for_spec(spec))


func _set_race(race_id: String) -> void:
	spec.race = race_id
	if not game.db.races[race_id].get("flexibleBonus", false):
		spec.racialChoice = ""
	elif spec.racialChoice == "":
		spec.racialChoice = "str"
	_reset_choices()


func _set_class(cls_id: String) -> void:
	spec.cls = cls_id
	spec.look["top"] = game.db.classes[cls_id].get("look", {}).get("top", spec.look.get("top", CLOTH[0]))
	_reset_choices()


func _reset_choices() -> void:
	spec.skillRanks = {}
	spec.feats = []
	spec.spells = []
	_draw_identity()
	_draw_abilities()
	_draw_choices()
	_update_summary()


func _draw_abilities() -> void:
	UiKit.clear(ability_box)
	var race: Dictionary = game.db.races[spec.race]
	var spent := CharRules.point_buy_total(spec.abilities)
	var left := CharRules.POINT_BUY_BUDGET - spent
	ability_box.add_child(UiKit.label("Ability scores   -   %d points left" % left, 15, UiKit.GOLD if left >= 0 else UiKit.RED))
	for a in CharRules.ABILITIES:
		var row := UiKit.hbox(6)
		var base: int = spec.abilities[a]
		var l := UiKit.label(CharRules.ABILITY_NAMES[a], 14)
		l.custom_minimum_size = Vector2(110, 0)
		row.add_child(l)
		var minus := UiKit.button(" - ", _bump.bind(a, -1))
		minus.disabled = base <= 7
		row.add_child(minus)
		var val := UiKit.label(str(base), 16, UiKit.TEXT)
		val.custom_minimum_size = Vector2(26, 0)
		val.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		row.add_child(val)
		var plus := UiKit.button(" + ", _bump.bind(a, 1))
		var next_cost: int = int(CharRules.POINT_BUY_COST.get(base + 1, 99)) - int(CharRules.POINT_BUY_COST.get(base, 0))
		plus.disabled = base >= 18 or next_cost > left
		row.add_child(plus)
		var bonus: int = int(race.get("abilityMods", {}).get(a, 0)) + (2 if (race.get("flexibleBonus", false) and spec.racialChoice == a) else 0)
		var total := base + bonus
		row.add_child(UiKit.label(("%s racial" % Util.signed(bonus)) if bonus != 0 else "", 12, UiKit.DIM))
		row.add_child(UiKit.spacer())
		row.add_child(UiKit.label("%d  (%s)" % [total, Util.signed(CharRules.ability_mod(total))], 15, UiKit.GOLD))
		ability_box.add_child(row)
	if race.get("flexibleBonus", false):
		var frow := UiKit.hbox(6)
		frow.add_child(UiKit.label("+2 racial bonus to", 13))
		frow.add_child(_option(CharRules.ABILITIES, CharRules.ABILITIES.map(func(a): return CharRules.ABILITY_NAMES[a]), spec.racialChoice, _set_flexible))
		ability_box.add_child(frow)


func _bump(ability: String, by: int) -> void:
	spec.abilities[ability] = clampi(int(spec.abilities[ability]) + by, 7, 18)
	_draw_abilities()
	_draw_choices()
	_update_summary()


func _set_flexible(ability: String) -> void:
	spec.racialChoice = ability
	_draw_abilities()
	_draw_choices()
	_update_summary()


func _draw_choices() -> void:
	UiKit.clear(choice_box)
	var req := Progression.requirements_at_level_one(spec, game.db)
	var cls: Dictionary = game.db.classes[spec.cls]
	# trim choices that no longer fit (e.g. Int was lowered)
	while spec.skillRanks.size() > int(req.skillPoints):
		spec.skillRanks.erase(spec.skillRanks.keys()[spec.skillRanks.size() - 1])

	var skill_head := UiKit.label("", 15, UiKit.GOLD)
	choice_box.add_child(skill_head)
	var sl := Modal.scroll_list(Vector2(0, 220))
	choice_box.add_child(sl[0])
	var ids: Array = game.db.skills.keys()
	ids.sort()
	ids.sort_custom(func(a, b): return (a in cls.classSkills) and not (b in cls.classSkills))
	for sid in ids:
		var cb := CheckBox.new()
		cb.focus_mode = Control.FOCUS_NONE
		var is_class: bool = sid in cls.classSkills
		cb.text = "%s%s" % [game.db.skills[sid].name, "   (class skill +3)" if is_class else ""]
		cb.button_pressed = spec.skillRanks.has(sid)
		if is_class:
			cb.add_theme_color_override("font_color", UiKit.GOLD)
		cb.toggled.connect(_toggle_skill.bind(sid, cb, skill_head))
		sl[1].add_child(cb)
	_skill_head(skill_head)

	var temp := CharRules.derive(CharRules.create(spec, game.db), game.db)
	var feat_head := UiKit.label("", 15, UiKit.GOLD)
	choice_box.add_child(feat_head)
	var fl := Modal.scroll_list(Vector2(0, 170))
	choice_box.add_child(fl[0])
	for fid in game.db.feats:
		var feat: Dictionary = game.db.feats[fid]
		var entry := _feat_entry(fid)
		var cb := CheckBox.new()
		cb.focus_mode = Control.FOCUS_NONE
		cb.text = feat.name + ((" (%s)" % Util.title(entry.get_slice(":", 1))) if entry.contains(":") else "")
		cb.tooltip_text = feat.get("desc", "")
		cb.button_pressed = entry in spec.feats
		cb.disabled = not Progression.feat_available(spec, feat, game.db, temp)
		cb.toggled.connect(_toggle_feat.bind(entry, cb, feat_head))
		fl[1].add_child(cb)
	_feat_head(feat_head)

	if int(req.spells) > 0:
		var spell_head := UiKit.label("", 15, UiKit.GOLD)
		choice_box.add_child(spell_head)
		var pl := Modal.scroll_list(Vector2(0, 120))
		choice_box.add_child(pl[0])
		for sid in game.db.spells:
			var sp: Dictionary = game.db.spells[sid]
			if int(sp.get("levels", {}).get(spec.cls, -1)) != 1:
				continue
			var cb := CheckBox.new()
			cb.focus_mode = Control.FOCUS_NONE
			cb.text = sp.name
			cb.tooltip_text = sp.get("desc", "")
			cb.button_pressed = sid in spec.spells
			cb.toggled.connect(_toggle_spell.bind(sid, cb, spell_head))
			pl[1].add_child(cb)
		_spell_head(spell_head)


## The entry stored in spec.feats: feats that need a choice get a sensible automatic one.
func _feat_entry(fid: String) -> String:
	var feat: Dictionary = game.db.feats[fid]
	match feat.get("param", ""):
		"weapon":
			return "%s:%s" % [fid, game.db.classes[spec.cls].startingKit.equipped.get("mainHand", "dagger")]
		"skill":
			return "%s:perception" % fid
	return fid


func _skill_head(l: Label) -> void:
	l.text = "Skills   %d / %d ranks" % [spec.skillRanks.size(), int(Progression.requirements_at_level_one(spec, game.db).skillPoints)]


func _feat_head(l: Label) -> void:
	l.text = "Feats   %d / %d" % [spec.feats.size(), int(Progression.requirements_at_level_one(spec, game.db).feats)]


func _spell_head(l: Label) -> void:
	l.text = "1st-level spells   %d / %d   (all cantrips are known)" % [spec.spells.size(), int(Progression.requirements_at_level_one(spec, game.db).spells)]


func _toggle_skill(on: bool, sid: String, cb: CheckBox, head: Label) -> void:
	if on and spec.skillRanks.size() >= int(Progression.requirements_at_level_one(spec, game.db).skillPoints):
		cb.set_pressed_no_signal(false)
		return
	if on:
		spec.skillRanks[sid] = 1
	else:
		spec.skillRanks.erase(sid)
	_skill_head(head)
	_update_summary()


func _toggle_feat(on: bool, entry: String, cb: CheckBox, head: Label) -> void:
	if on and spec.feats.size() >= int(Progression.requirements_at_level_one(spec, game.db).feats):
		cb.set_pressed_no_signal(false)
		return
	if on:
		spec.feats.append(entry)
	else:
		spec.feats.erase(entry)
	_feat_head(head)
	_update_summary()


func _toggle_spell(on: bool, sid: String, cb: CheckBox, head: Label) -> void:
	if on and spec.spells.size() >= int(Progression.requirements_at_level_one(spec, game.db).spells):
		cb.set_pressed_no_signal(false)
		return
	if on:
		spec.spells.append(sid)
	else:
		spec.spells.erase(sid)
	_spell_head(head)


func _update_summary() -> void:
	var c := CharRules.create(spec, game.db)
	var s := CharRules.derive(c, game.db)
	var t := UiKit.c("At level 1", UiKit.GOLD) + "\n"
	t += "Hit points [b]%d[/b]     Armor class [b]%d[/b]     Speed %d ft\n" % [int(s.hpMax), int(s.ac), int(s.speed)]
	t += "Fortitude %s   Reflex %s   Will %s   Initiative %s\n" % [Util.signed(s.saves.fort.total), Util.signed(s.saves.ref.total), Util.signed(s.saves.will.total), Util.signed(s.init)]
	for atk in s.attacks:
		t += "%s [b]%s[/b]  %s\n" % [atk.name, Util.signed(atk.bonus), atk.damage]
	if s.casting != null:
		t += "Spell slots: %s\n" % str(s.casting.slots).replace("\"", "")
	var kit: Dictionary = game.db.classes[spec.cls].get("startingKit", {})
	var gear: Array = []
	for slot in kit.get("equipped", {}):
		gear.append(game.db.items[kit.equipped[slot]].name)
	t += UiKit.c("\nStarting gear: " + ", ".join(gear), UiKit.DIM)
	summary.text = t
	errors.text = ""


func _begin() -> void:
	var problems := CharRules.validate_build(spec, game.db)
	if not problems.is_empty():
		errors.text = "  ".join(problems)
		return
	var final: Dictionary = spec.duplicate(true)
	if game.db.classes[spec.cls].has("spellbook"):
		for sid in game.db.spells:
			if int(game.db.spells[sid].get("levels", {}).get(spec.cls, -1)) == 0:
				final.spells.append(sid)
	main.start_new_game(campaign_id, final)
