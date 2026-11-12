class_name CombatHud
extends PanelContainer
## The player's controls during a fight. It is ALSO the "player controller" the Encounter asks for
## decisions (game.player_controller = this): decide() shows the bar, waits for the player to click,
## and returns one action Dictionary (see src/engine/encounter.gd for the action shapes).
##
## Click rules while it is your turn:
##   blue tile    walk there (orange = further, uses your action as a second move)
##   enemy        attack with the selected attack (walks next to it first if needed)
##   Spells       pick a spell, then click its target (Esc cancels)
##   Space        end turn

signal action_chosen(action)

const MOVE := Color(0.25, 0.55, 1.0, 0.30)
const DASH := Color(1.0, 0.6, 0.15, 0.24)
const FOE := Color(1.0, 0.2, 0.15, 0.42)
const ALLY := Color(0.3, 1.0, 0.4, 0.36)
const SELF := Color(1.0, 0.9, 0.4, 0.42)
const HOVER := Color(1.0, 1.0, 1.0, 0.45)

var game: Game
var view
var ent: Ent = null          # the party member waiting for orders (null = not our turn)
var enc = null
var mode := "move"           # "move" | "spell"
var attack_index := 0
var spell_id := ""
var reach: Dictionary = {}
var hover = null
var info: Label
var row: HBoxContainer
var popup: PopupMenu
var _popup_ids: Array = []
var _popup_kind := ""


func setup(g: Game, view_panel) -> void:
	game = g
	view = view_panel
	add_theme_stylebox_override("panel", UiKit.box(Color(0.07, 0.06, 0.1, 0.9), UiKit.GOLD.darkened(0.35), 1, 6, 10, 6))
	var v := UiKit.vbox(4)
	add_child(v)
	info = UiKit.label("", 14, UiKit.GOLD)
	info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(info)
	row = UiKit.hbox(6)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_child(row)
	popup = PopupMenu.new()
	popup.id_pressed.connect(_on_popup)
	add_child(popup)
	visible = false
	game.combat_changed.connect(_on_combat_changed)
	game.mode_changed.connect(_on_combat_changed)


func _on_combat_changed() -> void:
	if game.encounter == null:
		visible = false
		return
	visible = true
	if ent == null:
		UiKit.clear(row)
		var a: Ent = game.encounter.active
		info.text = "Round %d  ·  %s" % [int(game.encounter.round_no), ("%s is acting..." % a.name) if a != null else "..."]


# ----------------------------------------------------------------------------------------------
# Controller interface (called by the Encounter)
# ----------------------------------------------------------------------------------------------

func decide(c: Ent, encounter) -> Dictionary:
	ent = c
	enc = encounter
	mode = "move"
	spell_id = ""
	hover = null
	var stats: Dictionary = game.stats(c.actor)
	if attack_index >= stats.attacks.size():
		attack_index = 0
	_refresh()
	var action: Dictionary = await action_chosen
	ent = null
	game.world.highlights = {}
	UiKit.clear(row)
	info.text = "Round %d  ·  %s..." % [int(enc.round_no), c.name]
	return action


func _choose(action: Dictionary) -> void:
	if ent != null:
		action_chosen.emit(action)


func waiting() -> bool:
	return ent != null


# ----------------------------------------------------------------------------------------------
# Bar
# ----------------------------------------------------------------------------------------------

func _refresh() -> void:
	if ent == null:
		return
	var cs: Dictionary = ent.combat
	var stats: Dictionary = game.stats(ent.actor)
	reach = enc.reach_for(ent)
	info.text = "%s  ·  Move %d/%d  ·  Action %s%s" % [ent.name, int(cs.moveLeft), int(stats.squares), "ready" if cs.standard else "used",
		("  ·  Choose a target for %s (Esc cancels)" % game.db.spells[spell_id].name) if mode == "spell" else ""]
	UiKit.clear(row)
	for i in stats.attacks.size():
		var atk: Dictionary = stats.attacks[i]
		var b := UiKit.button("%s %s %s" % ["➶" if atk.ranged else "⚔", atk.name, Util.signed(atk.bonus)], _select_attack.bind(i), "%s damage. Click an enemy to attack." % atk.damage)
		b.toggle_mode = true
		b.button_pressed = mode == "move" and i == attack_index
		b.disabled = not cs.standard
		row.add_child(b)
	var spells := _spell_list(stats)
	if not spells.is_empty():
		var sb := UiKit.button("Spells ▾", _open_spells, "Cast a spell or use a class power")
		sb.disabled = not cs.standard
		row.add_child(sb)
	var potions := _potion_list()
	if not potions.is_empty():
		var ib := UiKit.button("Items ▾", _open_items, "Drink a potion")
		ib.disabled = not cs.standard
		row.add_child(ib)
	var db := UiKit.button("Defend", func(): _choose({"type": "defend"}), "Total defense: +4 AC until your next turn")
	db.disabled = not cs.standard
	row.add_child(db)
	var eb := UiKit.button("End turn  [Space]", func(): _choose({"type": "end"}))
	eb.add_theme_color_override("font_color", UiKit.GOLD)
	row.add_child(eb)
	_paint()


func _select_attack(i: int) -> void:
	attack_index = i
	mode = "move"
	spell_id = ""
	_refresh()


func _spell_list(stats: Dictionary) -> Array:
	var out: Array = stats.get("classAbilities", []).duplicate()
	if stats.casting != null:
		out.append_array(stats.casting.known)
	return out


func _potion_list() -> Array:
	var out: Array = []
	for it in game.state.inventory:
		if game.db.items.get(it.id, {}).get("type", "") == "consumable":
			out.append(it.id)
	return out


func _open_spells() -> void:
	var stats: Dictionary = game.stats(ent.actor)
	popup.clear()
	_popup_ids = _spell_list(stats)
	_popup_kind = "spell"
	for i in _popup_ids.size():
		var sp: Dictionary = game.db.spells[_popup_ids[i]]
		var left := SpellRules.uses_left(ent.actor, stats, sp, game.db)
		popup.add_item("%s   %s" % [sp.name, "at will" if left < 0 else "%d left" % left], i)
		popup.set_item_disabled(i, left == 0)
		popup.set_item_tooltip(i, sp.get("desc", ""))
	popup.position = Vector2i(get_viewport().get_mouse_position()) - Vector2i(0, 24 * _popup_ids.size() + 20)
	popup.popup()


func _open_items() -> void:
	popup.clear()
	_popup_ids = _potion_list()
	_popup_kind = "item"
	for i in _popup_ids.size():
		popup.add_item("%s  x%d" % [game.db.items[_popup_ids[i]].name, game.count_item(_popup_ids[i])], i)
	popup.position = Vector2i(get_viewport().get_mouse_position()) - Vector2i(0, 24 * _popup_ids.size() + 20)
	popup.popup()


func _on_popup(id: int) -> void:
	if ent == null or id >= _popup_ids.size():
		return
	if _popup_kind == "item":
		_choose({"type": "item", "item": _popup_ids[id], "target": ent})
		return
	var sp: Dictionary = game.db.spells[_popup_ids[id]]
	if sp.get("target", "") in ["self", "allies_burst", "enemies_burst"]:
		_choose({"type": "cast", "spell": sp.id, "target": ent})
		return
	mode = "spell"
	spell_id = sp.id
	_refresh()


## Esc: leave spell targeting. Returns true when it did something.
func cancel() -> bool:
	if ent != null and mode == "spell":
		mode = "move"
		spell_id = ""
		_refresh()
		return true
	return false


func end_turn() -> void:
	_choose({"type": "end"})


# ----------------------------------------------------------------------------------------------
# Floor highlights
# ----------------------------------------------------------------------------------------------

func _paint() -> void:
	var hl := {}
	if ent == null:
		game.world.highlights = hl
		return
	var cs: Dictionary = ent.combat
	hl[ent.cell()] = SELF
	if mode == "spell":
		var sp: Dictionary = game.db.spells[spell_id]
		for o in enc.combatants:
			if not o.alive():
				continue
			var kind: String = sp.get("target", "enemy")
			if kind in ["enemy", "ally"]:
				if enc.cast_problem(ent, sp, o, null) == "":
					hl[o.cell()] = FOE if o.side != ent.side else ALLY
			elif o.side != ent.side and enc.cast_problem(ent, sp, o, o.cell()) == "":
				hl[o.cell()] = FOE
	else:
		for cell in reach:
			if cell == ent.cell() or not Encounter.reach_stop(reach, cell):
				continue
			hl[cell] = MOVE if float(reach[cell].cost) <= float(cs.moveLeft) + 0.001 else DASH
		for o in enc.enemies_of(ent):
			if enc.attack_problem(ent, o, attack_index) == "":
				hl[o.cell()] = FOE
	if hover != null and hl.has(hover):
		var c: Color = hl[hover]
		hl[hover] = c.lerp(HOVER, 0.5)
	game.world.highlights = hl


## The mouse moved over a tile / entity.
func on_hover(p: Dictionary) -> void:
	if ent == null:
		return
	var cell = p.ent.cell() if p.ent != null else p.cell
	if cell != hover:
		hover = cell
		_paint()


# ----------------------------------------------------------------------------------------------
# Clicks in the 3D view or on the minimap
# ----------------------------------------------------------------------------------------------

func on_pick(p: Dictionary) -> void:
	if ent == null:
		return
	var target: Ent = p.ent
	# No creature under the cursor, or only a body: whoever STANDS on the clicked tile is meant.
	if (target == null or not target.can_act()) and p.cell != null:
		for o in enc.combatants:
			if o.can_act() and o.cell() == p.cell:
				target = o
		if target == null:
			for o in enc.combatants:
				if o.alive() and o.cell() == p.cell:
					target = o
	if mode == "spell":
		var sp: Dictionary = game.db.spells[spell_id]
		var kind: String = sp.get("target", "enemy")
		var cell = target.cell() if target != null else p.cell
		if kind in ["enemy", "ally"] and (target == null or target.actor == null):
			return
		var problem: String = enc.cast_problem(ent, sp, target, cell)
		if problem != "":
			game.io.float_text(ent, problem, "info")
			return
		_choose({"type": "cast", "spell": spell_id, "target": target, "cell": cell})
		return
	if target != null and target.side == "enemy" and target.can_act():
		var problem: String = enc.attack_problem(ent, target, attack_index)
		if problem == "":
			_choose({"type": "attack", "target": target, "attack": attack_index})
			return
		if problem == "Too far away":
			var best = null
			var best_cost := 1.0e9
			for cell in reach:
				if Grid.cheb(cell, target.cell()) <= 1 and float(reach[cell].cost) < best_cost and (cell == ent.cell() or game.world.ent_at(cell, ent) == null):
					best = cell
					best_cost = float(reach[cell].cost)
			if best == null:
				# cannot get next to the enemy this turn: close the distance as far as possible
				var best_d := Grid.dist(ent.cell(), target.cell())
				for cell in reach:
					var d := Grid.dist(cell, target.cell())
					if d < best_d and game.world.ent_at(cell, ent) == null:
						best = cell
						best_d = d
			if best != null and best != ent.cell():
				_choose({"type": "move", "path": Grid.path_from(reach, best)})
				return
		game.io.float_text(ent, problem, "info")
		return
	if p.cell != null and Encounter.reach_stop(reach, p.cell) and p.cell != ent.cell():
		_choose({"type": "move", "path": Grid.path_from(reach, p.cell)})
