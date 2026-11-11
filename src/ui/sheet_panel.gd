class_name SheetPanel
extends PanelContainer
## TOP-LEFT pane: the character sheet of one party member.
##   row 1  party tabs (click to view a character) + "Lead" to steer that character
##   row 2  portrait, name, hit points, experience, level-up button
##   row 3  tabs: Stats | Skills | Gear | Spells | Traits
## The body is BBCode with [url=...] links. Clicking a link calls _on_link("kind:argument"):
##   ability:str  save:will  skill:perception  init  attack:0   -> roll it in the dice tray
##   equip:<item>  use:<item>  unequip:<slot>                   -> manage gear
##   spell:<id>                                                 -> cast a helpful spell outside combat

var game: Game
var main
var char_id := ""
var tab := "Stats"
var party_row: HBoxContainer
var portrait: TextureRect
var name_label: Label
var sub_label: Label
var hp_holder: VBoxContainer
var level_btn: Button
var body: RichTextLabel
var popup: PopupMenu
var _dirty := true
var _pending_spell := ""


func setup(g: Game, main_node) -> void:
	game = g
	main = main_node
	custom_minimum_size = Vector2(500, 400)
	var v := UiKit.vbox(6)
	add_child(v)
	party_row = UiKit.hbox(4)
	v.add_child(party_row)

	var head := UiKit.hbox(10)
	v.add_child(head)
	var frame := UiKit.panel(UiKit.BG, UiKit.BORDER, 2)
	portrait = TextureRect.new()
	portrait.custom_minimum_size = Vector2(72, 72)
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	frame.clip_contents = true
	frame.add_child(portrait)
	head.add_child(frame)
	var info := UiKit.vbox(2)
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(info)
	var top := UiKit.hbox(8)
	name_label = UiKit.label("", 20, UiKit.GOLD)
	top.add_child(name_label)
	top.add_child(UiKit.spacer())
	level_btn = UiKit.button("Level up!", func(): main.open_level_up(char_id))
	level_btn.add_theme_color_override("font_color", UiKit.GOLD)
	level_btn.visible = false
	top.add_child(level_btn)
	info.add_child(top)
	sub_label = UiKit.label("", 13, UiKit.DIM)
	info.add_child(sub_label)
	hp_holder = UiKit.vbox(3)
	info.add_child(hp_holder)

	v.add_child(UiKit.tabs(["Stats", "Skills", "Gear", "Spells", "Traits"], _set_tab))
	body = UiKit.rich(14)
	body.meta_clicked.connect(_on_link)
	body.meta_underlined = false
	v.add_child(body)
	popup = PopupMenu.new()
	popup.id_pressed.connect(_on_popup)
	add_child(popup)

	game.state_changed.connect(func(): _dirty = true)
	game.map_loaded.connect(func(): _dirty = true)
	game.combat_changed.connect(_follow_combat)


func _process(_delta: float) -> void:
	if _dirty:
		_dirty = false
		refresh()


func _set_tab(tab_name: String) -> void:
	tab = tab_name
	_dirty = true


## Shows the sheet of this party member.
func show_character(cid: String) -> void:
	char_id = cid
	_dirty = true


## During a fight the sheet follows whichever party member is acting.
func _follow_combat() -> void:
	if game.encounter != null and game.encounter.active != null and game.encounter.active.side == "party":
		char_id = game.encounter.active.char_id
	_dirty = true


func current() -> Dictionary:
	var roster: Dictionary = game.state.get("roster", {})
	if not roster.has(char_id) or not (char_id in game.state.party):
		char_id = game.state.get("leader", "")
	return roster.get(char_id, {})


func refresh() -> void:
	var c := current()
	if c.is_empty():
		UiKit.clear(party_row)
		name_label.text = "No character"
		sub_label.text = ""
		body.text = ""
		portrait.texture = null
		level_btn.visible = false
		UiKit.clear(hp_holder)
		return
	var s: Dictionary = game.stats(c)
	UiKit.clear(party_row)
	for cid in game.state.party:
		var pc: Dictionary = game.state.roster[cid]
		var b := UiKit.button(("★ " if cid == game.state.leader else "") + str(pc.name).get_slice(" ", 0), show_character.bind(cid), "Show %s's sheet" % pc.name)
		b.toggle_mode = true
		b.button_pressed = cid == char_id
		if int(pc.hp) <= 0:
			b.add_theme_color_override("font_color", UiKit.RED)
		party_row.add_child(b)
	party_row.add_child(UiKit.spacer())
	if char_id != game.state.leader and game.encounter == null:
		party_row.add_child(UiKit.button("Lead", func(): Party.set_leader(game, char_id), "Steer this character"))
	party_row.add_child(UiKit.label("%d gp" % int(game.state.gold), 14, UiKit.GOLD))

	Portraits.apply(portrait, game, c)
	name_label.text = c.name
	sub_label.text = "%s %s  ·  Level %d" % [game.db.races[c.race].name, game.db.classes[c.cls].name, int(c.level)]
	level_btn.visible = Progression.can_level_up(c) and game.encounter == null
	UiKit.clear(hp_holder)
	var hp_row := UiKit.hbox(6)
	var hp_frac := float(maxi(0, int(c.hp))) / float(s.hpMax)
	hp_row.add_child(UiKit.label("HP %d / %d" % [int(c.hp), int(s.hpMax)], 13, UiKit.RED if hp_frac < 0.34 else UiKit.TEXT))
	hp_row.add_child(UiKit.bar(maxi(0, int(c.hp)), s.hpMax, UiKit.RED if hp_frac < 0.34 else UiKit.GREEN, 9))
	hp_holder.add_child(hp_row)
	var xp_row := UiKit.hbox(6)
	var lo: int = Progression.XP_TABLE[int(c.level) - 1]
	var hi: int = Progression.xp_for_next(int(c.level))
	xp_row.add_child(UiKit.label("XP %d / %d" % [int(c.xp), hi], 13, UiKit.DIM))
	xp_row.add_child(UiKit.bar(int(c.xp) - lo, hi - lo, UiKit.BLUE, 5))
	hp_holder.add_child(xp_row)

	match tab:
		"Skills":
			body.text = _skills(c, s)
		"Gear":
			body.text = _gear(c, s)
		"Spells":
			body.text = _spells(c, s)
		"Traits":
			body.text = _traits(c, s)
		_:
			body.text = _stats(c, s)


static func _link(target: String, text: String, color: Color = UiKit.TEXT) -> String:
	return "[url=%s]%s[/url]" % [target, UiKit.c(text, color)]


func _stats(c: Dictionary, s: Dictionary) -> String:
	var out := "[table=3]"
	for a in CharRules.ABILITIES:
		var ab: Dictionary = s.abilities[a]
		out += "[cell]%s  [b]%d[/b] %s    [/cell]" % [_link("ability:" + a, a.to_upper(), UiKit.GOLD), int(ab.score), UiKit.c("(%s)" % Util.signed(ab.mod), UiKit.DIM)]
	out += "[/table]\n"
	out += "%s [b]%d[/b] %s     %s [b]%s[/b]     %s %d ft\n" % [
		UiKit.c("AC", UiKit.GOLD), int(s.ac), UiKit.c("(touch %d, flat-footed %d)" % [int(s.touch), int(s.flatFooted)], UiKit.DIM),
		_link("init", "Initiative", UiKit.GOLD), Util.signed(s.init), UiKit.c("Speed", UiKit.GOLD), int(s.speed)]
	var saves: Array = []
	for sv in ["fort", "ref", "will"]:
		saves.append("%s [b]%s[/b]" % [_link("save:" + sv, CharRules.SAVE_NAMES[sv], UiKit.GOLD), Util.signed(s.saves[sv].total)])
	out += "     ".join(saves) + "\n"
	out += UiKit.c("BAB %s   CMB %s   CMD %d" % [Util.signed(s.bab), Util.signed(s.cmb), int(s.cmd)], UiKit.DIM) + "\n\n"
	for i in s.attacks.size():
		var atk: Dictionary = s.attacks[i]
		var crit := ("%d-20" % int(atk.critRange)) if int(atk.critRange) < 20 else "20"
		out += "%s %s  [b]%s[/b]   %s  %s\n" % ["➶" if atk.ranged else "⚔", _link("attack:%d" % i, atk.name, UiKit.TEXT), Util.signed(atk.bonus), atk.damage, UiKit.c("(%s/x%d)" % [crit, int(atk.critMult)], UiKit.DIM)]
	if int(s.sneakDice) > 0:
		out += UiKit.c("Sneak attack +%dd6\n" % int(s.sneakDice), UiKit.DIM)
	var effects: Array = []
	for e in c.get("effects", []):
		effects.append(str(e.get("name", e.get("id", "effect"))))
	if not effects.is_empty():
		out += "\n%s %s\n" % [UiKit.c("Effects:", UiKit.PURPLE), UiKit.esc(", ".join(effects))]
	out += "\n" + UiKit.c("Click a gold name to roll it.", UiKit.DIM)
	return out


func _skills(c: Dictionary, s: Dictionary) -> String:
	var ids: Array = s.skills.keys()
	ids.sort()
	var out := "[table=2]"
	for sid in ids:
		var sk: Dictionary = s.skills[sid]
		var label: String = game.db.skills[sid].name
		if not sk.usable:
			out += "[cell]%s    [/cell]" % UiKit.c("%s  -" % label, UiKit.DIM.darkened(0.25))
			continue
		var col := UiKit.GOLD if int(sk.ranks) > 0 else UiKit.TEXT
		out += "[cell]%s  [b]%s[/b]%s    [/cell]" % [_link("skill:" + sid, label, col), Util.signed(sk.total), UiKit.c(" •", UiKit.BLUE) if sk.classSkill else ""]
	out += "[/table]\n" + UiKit.c("Gold = trained.  • = class skill.  Click to roll.", UiKit.DIM)
	return out


func _gear(c: Dictionary, _s: Dictionary) -> String:
	var out := UiKit.c("Equipped", UiKit.GOLD) + "\n"
	var names := {"mainHand": "Main hand", "offHand": "Off hand", "armor": "Armor", "ranged": "Ranged", "accessory": "Accessory"}
	for slot in names:
		var item_id = c.equipped.get(slot)
		if item_id == null:
			out += UiKit.c("   %s: -\n" % names[slot], UiKit.DIM)
		else:
			out += "   %s: %s\n" % [UiKit.c(names[slot], UiKit.DIM), _link("unequip:" + slot, game.db.items[item_id].name)]
	out += "\n%s %s\n" % [UiKit.c("Party pack", UiKit.GOLD), UiKit.c("(shared)   %d gp" % int(game.state.gold), UiKit.DIM)]
	if game.state.inventory.is_empty():
		out += UiKit.c("   empty\n", UiKit.DIM)
	for it in game.state.inventory:
		var item: Dictionary = game.db.items.get(it.id, {})
		var qty := (" x%d" % int(it.qty)) if int(it.qty) > 1 else ""
		var kind: String = item.get("type", "")
		if kind == "consumable":
			out += "   %s%s  %s\n" % [_link("use:" + str(it.id), item.get("name", it.id), UiKit.GREEN), qty, UiKit.c(item.get("desc", ""), UiKit.DIM)]
		elif game.slot_for(item) != "":
			out += "   %s%s  %s\n" % [_link("equip:" + str(it.id), item.get("name", it.id), UiKit.BLUE), qty, UiKit.c(_item_summary(item), UiKit.DIM)]
		else:
			out += "   %s%s  %s\n" % [item.get("name", it.id), qty, UiKit.c(item.get("desc", ""), UiKit.DIM)]
	out += "\n" + UiKit.c("Click: equipped item = take off, blue = equip, green = use.", UiKit.DIM)
	return out


static func _item_summary(item: Dictionary) -> String:
	match item.get("type", ""):
		"weapon":
			return "%s %s" % [item.get("damage", ""), "ranged" if item.get("ranged", false) else ("two-handed" if int(item.get("hands", 1)) == 2 else "")]
		"armor":
			return "+%d armor (%s)" % [int(item.get("ac", 0)), item.get("armorClass", "light")]
		"shield":
			return "+%d shield" % int(item.get("ac", 0))
	return str(item.get("desc", ""))


func _spells(c: Dictionary, s: Dictionary) -> String:
	var out := ""
	for pid in s.pools:
		out += "%s %d / %d\n" % [UiKit.c(Util.title(pid) + " uses:", UiKit.GOLD), int(s.pools[pid]) - int(c.used.get("pools", {}).get(pid, 0)), int(s.pools[pid])]
	for sid in s.classAbilities:
		var sp: Dictionary = game.db.spells.get(sid, {})
		out += "   %s  %s\n" % [_link("spell:" + sid, sp.get("name", sid), UiKit.GREEN if sp.has("heal") else UiKit.TEXT), UiKit.c(sp.get("desc", ""), UiKit.DIM)]
	if s.casting == null:
		return out if out != "" else UiKit.c("%s does not cast spells." % c.name, UiKit.DIM)
	var by_level := {}
	for sid in s.casting.known:
		var lv := SpellRules.level_of(game.db.spells[sid], s)
		if not by_level.has(lv):
			by_level[lv] = []
		by_level[lv].append(sid)
	var levels: Array = by_level.keys()
	levels.sort()
	for lv in levels:
		if lv == 0:
			out += UiKit.c("\nCantrips (at will)\n", UiKit.GOLD)
		else:
			var slots: int = s.casting.slots.get(str(lv), 0)
			out += UiKit.c("\nLevel %d   %d / %d slots\n" % [lv, slots - int(c.used.get("slots", {}).get(str(lv), 0)), slots], UiKit.GOLD)
		for sid in by_level[lv]:
			var sp: Dictionary = game.db.spells[sid]
			var helpful: bool = sp.get("target", "") in ["ally", "self", "allies_burst"]
			out += "   %s  %s\n" % [_link("spell:" + sid, sp.name, UiKit.GREEN if helpful else UiKit.TEXT), UiKit.c(sp.get("desc", ""), UiKit.DIM)]
	out += "\n" + UiKit.c("Green spells can be cast here; the rest only in combat.", UiKit.DIM)
	return out


func _traits(c: Dictionary, _s: Dictionary) -> String:
	var race: Dictionary = game.db.races[c.race]
	var cls: Dictionary = game.db.classes[c.cls]
	var out := ""
	if str(c.get("bio", "")) != "":
		out += "[i]%s[/i]\n\n" % UiKit.c(UiKit.esc(c.bio), UiKit.DIM)
	out += UiKit.c(race.name, UiKit.GOLD) + "\n"
	for tr in race.get("traits", []):
		out += "   • %s\n" % tr
	out += "\n" + UiKit.c(cls.name, UiKit.GOLD) + "\n"
	for f in cls.get("features", []):
		if int(f.get("level", 1)) <= int(c.level):
			out += "   • [b]%s[/b]  %s\n" % [f.name, UiKit.c(f.get("desc", ""), UiKit.DIM)]
	out += "\n" + UiKit.c("Feats", UiKit.GOLD) + "\n"
	for f in c.get("feats", []):
		var pf := CharRules.parse_feat(f)
		var feat: Dictionary = game.db.feats.get(pf.id, {})
		var extra := (" (%s)" % Util.title(pf.param)) if pf.param != "" else ""
		out += "   • [b]%s%s[/b]  %s\n" % [feat.get("name", pf.id), extra, UiKit.c(feat.get("desc", ""), UiKit.DIM)]
	if game.state.approval.has(char_id):
		out += "\n%s %d\n" % [UiKit.c("Approval:", UiKit.GOLD), int(game.state.approval[char_id])]
	return out


func _on_link(meta) -> void:
	var bits := str(meta).split(":")
	var kind: String = bits[0]
	var arg: String = bits[1] if bits.size() > 1 else ""
	var c := current()
	if c.is_empty():
		return
	var s: Dictionary = game.stats(c)
	match kind:
		"ability", "save", "skill", "init", "attack":
			if game.busy > 0 or game.encounter != null:
				return
			var r: Dictionary
			if kind == "ability":
				r = Checks.ability(s, arg, null, game.rng)
			elif kind == "save":
				r = Checks.save(s, arg, null, game.rng)
			elif kind == "skill":
				r = Checks.skill(s, arg, null, game.rng, game.db)
			elif kind == "init":
				r = Checks.initiative(s, game.rng)
			else:
				var atk: Dictionary = s.attacks[int(arg)]
				r = Checks.d20(game.rng, "attack", atk.name, s.name, atk.parts.duplicate())
			game.show_roll(r)
		"unequip":
			game.unequip(c, arg)
		"equip":
			game.equip(c, arg)
		"use":
			if game.encounter == null and game.busy == 0:
				game.use_item_on(c, arg, game.ent_of(c))
		"spell":
			_pick_spell_target(c, arg)


func _pick_spell_target(c: Dictionary, spell_id: String) -> void:
	var sp: Dictionary = game.db.spells.get(spell_id, {})
	if game.encounter != null or game.busy > 0:
		return
	if sp.get("target", "") != "ally":
		game.cast_outside_combat(c, spell_id, c)
		return
	_pending_spell = spell_id
	popup.clear()
	for i in game.state.party.size():
		var t: Dictionary = game.state.roster[game.state.party[i]]
		popup.add_item("%s on %s (%d/%d hp)" % [sp.name, t.name, int(t.hp), int(game.stats(t).hpMax)], i)
	popup.position = Vector2i(get_viewport().get_mouse_position())
	popup.popup()


func _on_popup(id: int) -> void:
	var c := current()
	if _pending_spell == "" or c.is_empty() or id >= game.state.party.size():
		return
	game.cast_outside_combat(c, _pending_spell, game.state.roster[game.state.party[id]])
	_pending_spell = ""
