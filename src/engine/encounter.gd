class_name Encounter
extends RefCounted
## One turn-based fight on the current map (Pathfinder 1e rounds and initiative).
## Created by game.start_combat(group). Flow: roll initiative -> rounds -> each combatant's turn ->
## a CONTROLLER returns actions until the turn ends -> "victory", "defeat" or "stalemate"
## (nobody could act for three rounds; the fight simply breaks off).
##
## A controller is any object with:   func decide(ent: Ent, enc: Encounter) -> Dictionary
##   {"type": "move", "path": [Vector2i, ...]}            tiles to walk, in order
##   {"type": "attack", "target": Ent, "attack": index}   index into stats.attacks
##   {"type": "cast", "spell": id, "target": Ent, "cell": Vector2i}
##   {"type": "item", "item": id, "target": Ent}
##   {"type": "defend"}  /  {"type": "end"}
## Monsters use CombatAI. Party members use game.player_controller (the UI) or CombatAI when it is null.
##
## Per-combatant state lives in ent.combat:
##   init, moveLeft (squares), standard (bool), moved (squares this turn), aoo (bool, may still make
##   an attack of opportunity this round), acted (false = still flat-footed), stable (bool)
##
## Simplifications versus the tabletop rules (documented in docs/RULES.md):
##   - movement may be split around a standard action; a single 1-square step never provokes
##   - allies can be walked through, bodies never block (see "Who may walk where" below)
##   - one attack per standard action (no full attacks yet), no reach weapons, no cover
##   - spells are cast from per-level slots without preparation

var game
var world: World
var group_id := ""
var def: Dictionary = {}
var combatants: Array = []
var round_no := 0
var active: Ent = null
var result := ""
var surprise := ""
var ai: CombatAI
var _activity := false          # did anyone move or act this round?
var _idle_rounds := 0


func _init(g, group: String, foes: Array, surprise_side := "") -> void:
	game = g
	world = g.world
	group_id = group
	surprise = surprise_side
	def = g.campaign.get("encounters", {}).get(group, {})
	ai = CombatAI.new(g)
	for e in world.party_ents():
		if not e.dead:
			combatants.append(e)
	for e in foes:
		combatants.append(e)


# ----------------------------------------------------------------------------------------------
# Main loop
# ----------------------------------------------------------------------------------------------

func run() -> String:
	game.encounter = self
	game.mode = "combat"
	world.pending = null
	world.pending_door = null
	for e in combatants:
		e.path = []
		e.set_cell(world.free_cell_near(e.cell(), e))
		e.combat = {"init": 0, "moveLeft": 0.0, "standard": false, "moved": 0.0, "aoo": true, "acted": false, "stable": false}
		if e.can_act():
			e.set_anim("idle")
	game.mode_changed.emit()
	game.journal("combat", "Combat begins%s" % (": " + str(def.name) if def.has("name") else "!"))
	game.io.sfx("combat")
	game.note_foes(combatants.filter(func(e): return e.side == "enemy"))
	game.io.banner("Roll for initiative!", def.get("name", ""))
	await _roll_initiative()
	if def.has("onStart"):
		await game.scripts.run(def.onStart, {})
	_check_end()
	while result == "":
		round_no += 1
		_activity = false
		game.journal("combat", "Round %d" % round_no)
		for hook in def.get("onRound", []):
			if int(hook.get("round", 0)) == round_no:
				await game.scripts.run(hook.get("do", []), {})
		for c in combatants.duplicate():
			if result != "":
				break
			if not c.alive() or not (c in combatants):
				continue
			if round_no == 1 and surprise != "" and c.side != surprise:
				continue
			await _take_turn(c)
			_check_end()
		# Nobody could reach anybody for three rounds (a locked door between the sides, say):
		# the fight breaks off instead of trapping the player in combat forever.
		_idle_rounds = 0 if _activity else _idle_rounds + 1
		if result == "" and (_idle_rounds >= 3 or round_no >= 100):
			result = "stalemate"
	await _finish()
	return result


func _roll_initiative() -> void:
	for c in combatants:
		var r := Checks.initiative(game.stats(c.actor), game.rng)
		c.combat.init = int(r.total) + int(r.modifier) * 0.01
		await game.show_roll(r, c.side != "party")
	combatants.sort_custom(func(a, b): return float(a.combat.init) > float(b.combat.init))
	game.combat_changed.emit()


## Adds a creature that arrives mid-fight (reinforcements spawned by a script).
func add_combatant(e: Ent) -> void:
	if e in combatants:
		return
	e.combat = {"init": 0, "moveLeft": 0.0, "standard": false, "moved": 0.0, "aoo": true, "acted": false, "stable": false}
	var r := Checks.initiative(game.stats(e.actor), game.rng)
	e.combat.init = int(r.total) + int(r.modifier) * 0.01
	await game.show_roll(r, true)
	combatants.append(e)
	combatants.sort_custom(func(a, b): return float(a.combat.init) > float(b.combat.init))
	game.combat_changed.emit()


func _take_turn(c: Ent) -> void:
	active = c
	var cs: Dictionary = c.combat
	var stats: Dictionary = game.stats(c.actor)
	cs.moveLeft = float(stats.squares)
	cs.standard = true
	cs.moved = 0.0
	cs.aoo = true
	world.highlights.clear()
	game.combat_changed.emit()

	if c.down():
		await _dying_turn(c, stats)
		cs.acted = true
		return
	var flags := Effects.flags(c.actor, game.db)
	for name in Effects.tick(c.actor):
		game.journal("combat", "%s: %s wears off." % [c.name, name])
	if "skipTurn" in flags:
		game.journal("combat", "%s cannot act." % c.name)
		game.io.float_text(c, "Cannot act", "info")
		await game.delay(0.6)
		cs.acted = true
		game.state_changed.emit()
		return
	if "noMove" in flags:
		cs.moveLeft = 0.0

	var controller = ai
	if c.side == "party" and game.player_controller != null:
		controller = game.player_controller
	var steps := 0
	while result == "" and steps < 16 and c.can_act():
		steps += 1
		if not cs.standard and cs.moveLeft < 1.0:
			break
		var action: Dictionary = await controller.decide(c, self)
		if action.get("type", "end") == "end":
			break
		var ok: bool = await execute(c, action)
		if ok:
			_activity = true
		elif controller == ai:
			break
		_check_end()
	cs.acted = true
	world.highlights.clear()
	game.combat_changed.emit()


func _dying_turn(c: Ent, stats: Dictionary) -> void:
	if c.side != "party" or c.combat.stable or int(c.actor.hp) >= 0:
		return
	var r := CombatRules.stabilize_roll(c.actor, stats, game.rng)
	await game.show_roll(r, true)
	if r.success:
		c.combat.stable = true
		game.journal("combat", "%s stabilizes." % c.name)
	else:
		c.actor.hp = int(c.actor.hp) - 1
		game.journal("combat", "%s is bleeding out (%d hp)." % [c.name, c.actor.hp])
		if CombatRules.life_state(c.actor, stats) == "dead":
			c.dead = true
			c.actor["dead"] = true
			game.journal("combat", "%s dies." % c.name)
	game.state_changed.emit()


func _check_end() -> void:
	if result != "":
		return
	var party_up := false
	var foes_up := false
	for c in combatants:
		if not c.can_act():
			continue
		if c.side == "party":
			party_up = true
		elif c.side == "enemy":
			foes_up = true
	if not foes_up:
		result = "victory"
	elif not party_up:
		result = "defeat"


func _finish() -> void:
	active = null
	world.highlights.clear()
	game.cam.focus = null
	var xp := int(def.get("xp", 0))
	for c in combatants:
		if c.actor != null:
			Effects.clear(c.actor, "encounter")
		if c.side == "enemy" and (c.dead or c.down()) and result == "victory":
			xp += int(game.stats(c.actor).get("xp", 0))
			c.dead = true
			c.blocking = false
			world.mark_removed(c)
		c.combat = null
	game.encounter = null
	if result == "victory":
		game.mode = "explore"
		game.journal("combat", "Victory!")
		game.io.sfx("victory")
		# House rule (campaign.rules.reviveAfterCombat, default on): the fallen get back up with 1 hp.
		if game.campaign.get("rules", {}).get("reviveAfterCombat", true):
			for e in world.party_ents():
				if e.down() or e.dead:
					e.actor.hp = 1
					e.actor.erase("dead")
					e.dead = false
					e.blocking = true
					e.set_anim("idle")
					game.journal("combat", "%s staggers back to their feet." % e.name)
		game.mode_changed.emit()
		game.combat_changed.emit()
		if xp > 0:
			await game.give_xp(maxi(1, xp / maxi(1, game.state.party.size())))
		if def.has("gold"):
			game.add_gold(int(def.gold))
		for it in def.get("loot", []):
			game.add_item(it.id, int(it.get("qty", 1)), true)
		game.state_changed.emit()
		if def.has("onVictory"):
			await game.scripts.run(def.onVictory, {})
	elif result == "stalemate":
		game.mode = "explore"
		game.journal("combat", "Neither side can reach the other. The fight breaks off.")
		game.mode_changed.emit()
		game.combat_changed.emit()
	else:
		game.mode = "explore"
		game.mode_changed.emit()
		game.combat_changed.emit()
		if def.has("onDefeat"):
			await game.scripts.run(def.onDefeat, {})
		else:
			await game.end_campaign(false, "Your party has fallen.")


# ----------------------------------------------------------------------------------------------
# Queries (used by the AI and by the player's combat UI)
# ----------------------------------------------------------------------------------------------

func enemies_of(c: Ent) -> Array:
	var out: Array = []
	for o in combatants:
		if o.can_act() and o.side != c.side and o.side != "neutral":
			out.append(o)
	return out


func allies_of(c: Ent, include_down := false) -> Array:
	var out: Array = []
	for o in combatants:
		if o.side == c.side and not o.dead and (include_down or o.can_act()):
			out.append(o)
	return out


## --- Who may walk where (Pathfinder movement, simplified) -----------------------------------------
##   walls, closed doors, props (pillars...)  nobody passes
##   a standing enemy                          blocks its tile
##   a standing ally                           you may walk THROUGH the tile but not stop on it
##   a body (dead or unconscious, any side)    never blocks: walk over it, stop on it
## A diagonal step may not cut the corner of a wall or prop, but may slip past a creature.

## May `c` walk through this tile?
func can_pass(c: Ent, cell: Vector2i) -> bool:
	if world.map.blocks_move(cell.x, cell.y):
		return false
	var o: Ent = world.ent_at(cell, c)
	return o == null or (o.actor != null and o.side == c.side)


## May `c` end its movement on this tile?
func can_stop(c: Ent, cell: Vector2i) -> bool:
	return not world.map.blocks_move(cell.x, cell.y) and world.ent_at(cell, c) == null


## Walls and props: the corners a diagonal step may not cut.
func is_hard(cell: Vector2i) -> bool:
	if world.map.blocks_move(cell.x, cell.y):
		return true
	var o: Ent = world.ent_at(cell)
	return o != null and o.actor == null


## Callable for Grid: true where `c` cannot walk (see can_pass).
func blocked_for(c: Ent) -> Callable:
	return func(cell: Vector2i): return not can_pass(c, cell)


## Movement budget this turn: remaining move, plus a second move if the standard action is unused.
func move_budget(c: Ent) -> float:
	var cs: Dictionary = c.combat
	if is_single_action(c):
		return float(cs.moveLeft) if cs.standard else 0.0
	return float(cs.moveLeft) + (float(game.stats(c.actor).squares) if cs.standard else 0.0)


## Tiles the combatant can get to with `budget` movement: {cell: {cost, prev, pass?}} (see
## Grid.reachable). Tiles marked "pass": true hold a standing ally: fine to walk through, not to
## stop on. Use reach_stop() before offering a tile as a destination.
func reach_within(c: Ent, budget: float) -> Dictionary:
	var out: Dictionary = Grid.reachable(c.cell(), budget, blocked_for(c), is_hard)
	for cell in out:
		if cell != c.cell() and not can_stop(c, cell):
			out[cell]["pass"] = true
	return out


## Tiles the combatant can reach this turn (see reach_within).
func reach_for(c: Ent) -> Dictionary:
	return reach_within(c, move_budget(c))


## Is `cell` in a reach_within() result AND a tile to stop on?
static func reach_stop(reach: Dictionary, cell: Vector2i) -> bool:
	return reach.has(cell) and not reach[cell].get("pass", false)


func is_single_action(c: Ent) -> bool:
	if c.actor.has("monsterId") and game.db.monsters[c.actor.monsterId].get("staggered", false):
		return true
	return Effects.has_flag(c.actor, game.db, "singleAction")


## Enemies of `c` that threaten `cell` (adjacent, conscious, able to act, has a melee attack).
func threateners(c: Ent, cell: Vector2i) -> Array:
	var out: Array = []
	for o in enemies_of(c):
		if Grid.cheb(o.cell(), cell) > 1 or not o.combat.acted:
			continue
		if "skipTurn" in Effects.flags(o.actor, game.db):
			continue
		if melee_attack_index(o) >= 0:
			out.append(o)
	return out


func melee_attack_index(c: Ent) -> int:
	var attacks: Array = game.stats(c.actor).attacks
	for i in attacks.size():
		if not attacks[i].ranged:
			return i
	return -1


func is_flanking(att: Ent, target: Ent) -> bool:
	var a := att.cell()
	var t := target.cell()
	if Grid.cheb(a, t) != 1:
		return false
	var opposite := Vector2i(2 * t.x - a.x, 2 * t.y - a.y)
	for o in allies_of(att):
		if o != att and o.cell() == opposite and melee_attack_index(o) >= 0:
			return true
	return false


## Why this attack cannot be made right now ("" = it can).
func attack_problem(c: Ent, target: Ent, attack_index: int) -> String:
	if target == null or not target.alive() or target.down():
		return "No target"
	var attacks: Array = game.stats(c.actor).attacks
	if attack_index < 0 or attack_index >= attacks.size():
		return "No such attack"
	if not c.combat.standard:
		return "No action left"
	var atk: Dictionary = attacks[attack_index]
	var d := Grid.cheb(c.cell(), target.cell())
	if atk.ranged:
		if Grid.dist(c.cell(), target.cell()) > int(atk.range) * 5:
			return "Out of range"
		if not Grid.line_of_sight(world.map, c.cell(), target.cell()):
			return "No line of sight"
	elif d > 1:
		return "Too far away"
	return ""


## Entities a spell would affect. `target` for single-target spells, `cell` to aim cones and bursts.
func spell_targets(c: Ent, spell: Dictionary, target: Ent, cell) -> Array:
	var out: Array = []
	var kind: String = spell.get("target", "enemy")
	var area: int = spell.get("area", 1)
	match kind:
		"self":
			out.append(c)
		"enemy", "ally":
			if target != null:
				out.append(target)
		"allies_burst":
			for o in allies_of(c, true):
				if Grid.dist(c.cell(), o.cell()) <= area:
					out.append(o)
		"enemies_burst":
			for o in enemies_of(c):
				if Grid.dist(c.cell(), o.cell()) <= area:
					out.append(o)
		"burst":
			var centre: Vector2i = cell if cell != null else (target.cell() if target != null else c.cell())
			for o in combatants:
				if not o.alive() or Grid.dist(centre, o.cell()) > area:
					continue
				if spell.get("enemiesOnly", false) and o.side == c.side:
					continue
				out.append(o)
		"cone":
			var aim_cell: Vector2i = cell if cell != null else (target.cell() if target != null else c.cell())
			var aim := Vector2(aim_cell - c.cell())
			if aim.length() < 0.1:
				return out
			aim = aim.normalized()
			for o in combatants:
				if o == c or not o.alive():
					continue
				var v := Vector2(o.cell() - c.cell())
				if Grid.dist(c.cell(), o.cell()) <= area and v.normalized().dot(aim) >= 0.7:
					out.append(o)
	return out


## Why this spell cannot be cast right now ("" = it can).
func cast_problem(c: Ent, spell: Dictionary, target: Ent, cell) -> String:
	var stats: Dictionary = game.stats(c.actor)
	if not c.combat.standard:
		return "No action left"
	if not SpellRules.can_use(c.actor, stats, spell, game.db):
		return "No uses left"
	var kind: String = spell.get("target", "enemy")
	var reach: int = maxi(1, int(spell.get("range", 1)))
	if kind in ["enemy", "ally"]:
		if target == null or not target.alive():
			return "Choose a target"
		if kind == "enemy" and target.side == c.side:
			return "Choose an enemy"
		if kind == "ally" and target.side != c.side:
			return "Choose an ally"
		if target != c:
			if Grid.dist(c.cell(), target.cell()) > reach:
				return "Out of range"
			if not Grid.line_of_sight(world.map, c.cell(), target.cell()):
				return "No line of sight"
	elif kind == "burst":
		var centre: Vector2i = cell if cell != null else (target.cell() if target != null else c.cell())
		if Grid.dist(c.cell(), centre) > reach:
			return "Out of range"
	return ""


# ----------------------------------------------------------------------------------------------
# Executing actions
# ----------------------------------------------------------------------------------------------

func execute(c: Ent, action: Dictionary) -> bool:
	match action.get("type", ""):
		"move":
			return await _do_move(c, action.get("path", []))
		"attack":
			return await _do_attack(c, action.get("target"), int(action.get("attack", 0)))
		"cast":
			return await _do_cast(c, str(action.get("spell", "")), action.get("target"), action.get("cell"))
		"item":
			return await _do_item(c, str(action.get("item", "")), action.get("target"))
		"defend":
			return _do_defend(c)
	return false


func _do_move(c: Ent, path: Array) -> bool:
	var cs: Dictionary = c.combat
	var stats: Dictionary = game.stats(c.actor)
	var budget := move_budget(c)
	var walk: Array = []
	var cost := 0.0
	var prev := c.cell()
	for step in path:
		var sc := Grid.step_cost(prev, step)
		if Grid.cheb(prev, step) != 1 or not can_pass(c, step) or cost + sc > budget + 0.001:
			break
		cost += sc
		walk.append(step)
		prev = step
	# never end the move on a tile where an ally is standing
	while not walk.is_empty() and not can_stop(c, walk[-1]):
		cost -= Grid.step_cost(walk[-2] if walk.size() > 1 else c.cell(), walk[-1])
		walk.pop_back()
	if walk.is_empty():
		return false
	if cost > float(cs.moveLeft) + 0.001:
		cs.standard = false
		cs.moveLeft = float(cs.moveLeft) + float(stats.squares)
	var careful: bool = walk.size() == 1 and float(cs.moved) == 0.0
	world.highlights.clear()
	for step in walk:
		var from := c.cell()
		if not careful:
			for foe in threateners(c, from):
				if not foe.combat.aoo or not c.can_act():
					continue
				foe.combat.aoo = false
				game.journal("combat", "%s provokes an attack of opportunity from %s." % [c.name, foe.name])
				await _strike(foe, c, melee_attack_index(foe))
		if not c.can_act():
			break
		var sc := Grid.step_cost(from, step)
		await world.walk(c, Vector2(step.x + 0.5, step.y + 0.5), 5.0)
		cs.moveLeft = float(cs.moveLeft) - sc
		cs.moved = float(cs.moved) + sc
	if c.can_act():
		c.set_anim("idle")
	if is_single_action(c):
		cs.standard = false
		cs.moveLeft = 0.0
	game.combat_changed.emit()
	return true


func _do_attack(c: Ent, target, attack_index: int) -> bool:
	if attack_problem(c, target, attack_index) != "":
		return false
	var cs: Dictionary = c.combat
	cs.standard = false
	if is_single_action(c):
		cs.moveLeft = 0.0
	var atk: Dictionary = game.stats(c.actor).attacks[attack_index]
	if atk.ranged:
		await _provoke(c, "shooting")
		if not c.can_act():
			return true
	await _strike(c, target, attack_index)
	game.combat_changed.emit()
	return true


## Everyone threatening `c` gets a free swing (used for ranged attacks and spellcasting in melee).
func _provoke(c: Ent, what: String) -> void:
	for foe in threateners(c, c.cell()):
		if not foe.combat.aoo or not c.can_act():
			continue
		foe.combat.aoo = false
		game.journal("combat", "%s provokes an attack of opportunity from %s by %s." % [c.name, foe.name, what])
		await _strike(foe, c, melee_attack_index(foe))


## One attack roll from att against target, shown in the dice tray, with damage applied.
func _strike(att: Ent, target: Ent, attack_index: int) -> void:
	var a: Dictionary = game.stats(att.actor)
	var d: Dictionary = game.stats(target.actor)
	var atk: Dictionary = a.attacks[attack_index]
	var ctx := {"tags": ["ranged" if atk.ranged else "melee"], "attack_mods": []}
	var squares := Grid.dist(att.cell(), target.cell())
	var tflags := Effects.flags(target.actor, game.db)
	var flanking := false
	if atk.ranged:
		if squares <= 6:
			ctx.tags.append("close")
		var increments := floori((squares - 1) / float(maxi(1, int(atk.range))))
		if increments > 0:
			ctx.attack_mods.append({"label": "Range", "value": -2 * increments})
	else:
		flanking = is_flanking(att, target)
		if flanking:
			ctx.tags.append("flanking")
			ctx.attack_mods.append({"label": "Flanking", "value": 2})
	if "helpless" in tflags or target.down():
		ctx["helpless"] = true
		if not atk.ranged:
			ctx.attack_mods.append({"label": "Helpless target", "value": 4})
	if target.combat != null and not target.combat.acted:
		ctx["flat_footed"] = true
	if int(a.sneakDice) > 0 and (flanking or ctx.get("flat_footed", false) or ctx.get("helpless", false)) and squares <= 6:
		ctx["sneak_dice"] = int(a.sneakDice)

	att.face_point(target.pos())
	att.set_anim("attack")
	game.io.sfx("swing")
	var res := CombatRules.resolve_attack(a, atk, d, ctx, game.rng)
	var quick: bool = att.side != "party"
	for r in res.rolls:
		await game.show_roll(r, quick)
	if att.can_act():
		att.set_anim("idle")
	if not res.hit:
		game.io.float_text(target, "Miss", "miss")
		game.io.sfx("miss")
		game.journal("combat", "%s misses %s with %s." % [att.name, target.name, str(atk.name).to_lower()])
		return
	var text := "%s %s %s with %s" % [att.name, "critically hits" if res.crit else "hits", target.name, str(atk.name).to_lower()]
	if int(res.damage) <= 0:
		game.journal("combat", text + " but deals no damage.")
		game.io.float_text(target, "0", "miss")
		return
	game.journal("combat", "%s for %d damage." % [text, res.damage])
	await game.damage_ent(target, int(res.damage), "crit" if res.crit else "damage")


func _do_cast(c: Ent, spell_id: String, target, cell) -> bool:
	var spell: Dictionary = game.db.spells.get(spell_id, {})
	if spell.is_empty() or cast_problem(c, spell, target, cell) != "":
		return false
	var cs: Dictionary = c.combat
	var stats: Dictionary = game.stats(c.actor)
	cs.standard = false
	if is_single_action(c):
		cs.moveLeft = 0.0
	SpellRules.spend(c.actor, stats, spell)
	if not spell.has("pool"):
		await _provoke(c, "casting a spell")
		if not c.can_act():
			game.journal("combat", "%s's spell is lost!" % c.name)
			return true
	await Encounter.cast_spell(game, c, spell, spell_targets(c, spell, target, cell), target, cell)
	game.combat_changed.emit()
	return true


## Resolves a spell on a list of targets. Static so Game.cast_outside_combat() can use it too.
static func cast_spell(game, c: Ent, spell: Dictionary, targets: Array, target = null, cell = null) -> void:
	var stats: Dictionary = game.stats(c.actor)
	game.journal("combat", "%s uses %s." % [c.name, spell.name])
	if target != null and target != c:
		c.face_point(target.pos())
	c.set_anim("cast")
	game.io.sfx("cast")
	var fx_to = target if target != null else (Vector2(cell.x + 0.5, cell.y + 0.5) if cell != null else c)
	await game.io.spell_fx(c, fx_to, spell.get("fx", "#ffffff"))
	var quick: bool = c.side != "party"
	var shared = null
	if targets.size() > 1 or spell.get("target", "") in ["cone", "burst", "allies_burst", "enemies_burst"]:
		var cl := SpellRules.caster_level(stats)
		if spell.has("damage"):
			shared = SpellRules.roll_amount(spell.damage, cl, game.rng, "damage", spell.name + " damage", c.name)
		elif spell.has("heal"):
			shared = SpellRules.roll_amount(spell.heal, cl, game.rng, "heal", spell.name, c.name)
		if shared != null:
			await game.show_roll(shared, quick)
	if targets.is_empty():
		game.journal("combat", "Nothing is affected.")
	for t in targets:
		if t.actor == null or t.dead:
			continue
		var out := SpellRules.resolve_on_target(stats, spell, game.stats(t.actor), game.rng, shared)
		for r in out.rolls:
			await game.show_roll(r, quick)
		if spell.get("special", "") == "stabilize":
			if t.down() and t.combat != null:
				t.combat.stable = true
				game.journal("combat", "%s is stabilized." % t.name)
				game.io.float_text(t, "Stable", "heal")
			continue
		if not out.affected:
			game.io.float_text(t, str(out.note).capitalize(), "miss")
			game.journal("combat", "%s: %s." % [t.name, out.note])
			continue
		if int(out.damage) > 0:
			game.journal("combat", "%s takes %d damage from %s." % [t.name, out.damage, spell.name])
			await game.damage_ent(t, int(out.damage), "damage")
		if int(out.heal) > 0:
			game.heal_ent(t, int(out.heal))
		if out.effect != null and not t.dead:
			Effects.add(t.actor, out.effect)
			game.io.float_text(t, out.effect.name, "info")
			game.journal("combat", "%s is affected by %s." % [t.name, out.effect.name])
	if c.can_act():
		c.set_anim("idle")
	game.state_changed.emit()


func _do_item(c: Ent, item_id: String, target) -> bool:
	var item: Dictionary = game.db.items.get(item_id, {})
	if item.get("type", "") != "consumable" or not c.combat.standard or game.count_item(item_id) <= 0:
		return false
	var t: Ent = target if target != null else c
	if t != c and Grid.cheb(c.cell(), t.cell()) > 1:
		return false
	c.combat.standard = false
	if is_single_action(c):
		c.combat.moveLeft = 0.0
	await game.use_item_on(c.actor, item_id, t)
	game.combat_changed.emit()
	return true


func _do_defend(c: Ent) -> bool:
	if not c.combat.standard:
		return false
	c.combat.standard = false
	Effects.add(c.actor, {"id": "defending", "name": "Total Defense", "conditions": ["defending"], "duration": {"rounds": 1}})
	game.journal("combat", "%s takes a defensive stance (+4 AC)." % c.name)
	game.io.float_text(c, "Defending", "info")
	game.state_changed.emit()
	game.combat_changed.emit()
	return true
