class_name CombatAI
extends RefCounted
## Decides combat actions for monsters (and for party members when no player is driving them).
## decide() returns ONE action Dictionary per call (see encounter.gd); it is called again until the
## turn is over, so keep each decision simple and always make progress or return {"type": "end"}.
##
## Styles (monster "ai" field):  melee   close in and hit the nearest foe
##                               ranged  shoot when there is a clear line, otherwise approach
##                               caster  use spells first (heals for hurt allies, then attacks)
## To add a style: add a branch in decide().
##
## Movement (_approach): walk to the nearest FREE tile next to any foe; allies and bodies on the floor
## are not obstacles (Encounter.can_pass / can_stop). If the front line fills every such tile, queue up
## behind it (_path_closer) rather than stand still.

## Movement budget used to look for a way to the enemy across the whole map (in squares).
const FAR := 80.0

var game


func _init(g) -> void:
	game = g


func decide(c: Ent, enc) -> Dictionary:
	var stats: Dictionary = game.stats(c.actor)
	var cs: Dictionary = c.combat
	var foes: Array = enc.enemies_of(c)
	if foes.is_empty():
		return {"type": "end"}
	var style := _style(c, stats)
	if cs.standard:
		if style == "caster":
			var cast := _pick_spell(c, stats, foes, enc)
			if not cast.is_empty():
				return cast
		var atk := _pick_attack(c, stats, foes, enc, style)
		if not atk.is_empty():
			return atk
	if float(cs.moveLeft) >= 1.0 or (cs.standard and enc.move_budget(c) >= 1.0):
		var path := _approach(c, stats, foes, enc, style)
		if not path.is_empty():
			return {"type": "move", "path": path}
	return {"type": "end"}


func _style(c: Ent, stats: Dictionary) -> String:
	if c.actor.has("monsterId"):
		return game.db.monsters[c.actor.monsterId].get("ai", "melee")
	if stats.casting != null:
		return "caster"
	return "melee"


func _nearest(c: Ent, list: Array) -> Ent:
	var best: Ent = null
	var best_d := 1.0e9
	for o in list:
		var d := c.dist_to(o)
		if d < best_d:
			best_d = d
			best = o
	return best


func _weakest(list: Array) -> Ent:
	var best: Ent = null
	for o in list:
		if best == null or int(o.actor.hp) < int(best.actor.hp):
			best = o
	return best


func _pick_attack(c: Ent, stats: Dictionary, foes: Array, enc, style: String) -> Dictionary:
	var adjacent: Array = foes.filter(func(f): return Grid.cheb(c.cell(), f.cell()) <= 1)
	var melee: int = enc.melee_attack_index(c)
	var ranged := -1
	for i in stats.attacks.size():
		if stats.attacks[i].ranged:
			ranged = i
	if not adjacent.is_empty() and melee >= 0:
		return {"type": "attack", "target": _weakest(adjacent), "attack": melee}
	if ranged >= 0 and (style == "ranged" or adjacent.is_empty()):
		var shots: Array = foes.filter(func(f): return enc.attack_problem(c, f, ranged) == "")
		if not shots.is_empty() and (style == "ranged" or not _can_reach_melee(c, foes, enc)):
			return {"type": "attack", "target": _weakest(shots), "attack": ranged}
	return {}


func _can_reach_melee(c: Ent, foes: Array, enc) -> bool:
	if enc.melee_attack_index(c) < 0:
		return false
	var reach: Dictionary = enc.reach_within(c, float(c.combat.moveLeft))
	for cell in reach:
		if not Encounter.reach_stop(reach, cell):
			continue
		for f in foes:
			if Grid.cheb(cell, f.cell()) <= 1:
				return true
	return false


func _pick_spell(c: Ent, stats: Dictionary, foes: Array, enc) -> Dictionary:
	var known: Array = stats.casting.known.duplicate() if stats.casting != null else []
	known.append_array(stats.get("classAbilities", []))
	# 1. Heal a badly hurt ally.
	var hurt: Array = enc.allies_of(c, true).filter(func(a): return int(a.actor.hp) * 2 < int(game.stats(a.actor).hpMax))
	if not hurt.is_empty():
		var patient := _weakest(hurt)
		for sid in known:
			var sp: Dictionary = game.db.spells.get(sid, {})
			if not sp.has("heal"):
				continue
			var tgt = patient if sp.get("target", "") == "ally" else null
			if enc.cast_problem(c, sp, tgt, null) == "":
				return {"type": "cast", "spell": sid, "target": tgt}
	# 2. Best offensive option: highest-level usable spell that can affect a foe right now.
	var best := {}
	var best_level := -1
	for sid in known:
		var sp: Dictionary = game.db.spells.get(sid, {})
		if sp.is_empty() or not (sp.has("damage") or sp.get("target", "") in ["enemy", "enemies_burst"]):
			continue
		if sp.has("heal"):
			continue
		var lv := SpellRules.level_of(sp, stats) + (2 if sp.has("pool") else 0)
		if lv < best_level:
			continue
		for f in foes:
			if sp.has("only") and not (sp.only in game.stats(f.actor).tags):
				continue
			var action := {"type": "cast", "spell": sid, "target": f, "cell": f.cell()}
			if enc.cast_problem(c, sp, f, f.cell()) != "":
				continue
			if sp.get("target", "") in ["cone", "burst"] and _hits_friends(c, sp, f, enc):
				continue
			if lv > best_level or (not best.is_empty() and int(f.actor.hp) < int(best.target.actor.hp)):
				best = action
				best_level = lv
	# Cantrips are a last resort: prefer a weapon when one is in reach.
	if best_level == 0 and not _pick_attack(c, stats, foes, enc, "melee").is_empty() and int(stats.bab) > 0:
		return {}
	return best


func _hits_friends(c: Ent, sp: Dictionary, target: Ent, enc) -> bool:
	for t in enc.spell_targets(c, sp, target, target.cell()):
		if t.side == c.side:
			return true
	return false


## Path towards the best foe, cut to this turn's movement. Uses a double move only when the
## foe cannot be reached with a single one.
func _approach(c: Ent, stats: Dictionary, foes: Array, enc, style: String) -> Array:
	if style == "ranged" or (style == "caster" and enc.melee_attack_index(c) >= 0 and stats.casting != null and int(stats.bab) == 0):
		for f in foes:
			if Grid.line_of_sight(enc.world.map, c.cell(), f.cell()) and Grid.dist(c.cell(), f.cell()) <= 8:
				return []
	for f in foes:
		if Grid.cheb(c.cell(), f.cell()) <= 1:
			return []
	var path := _path_to_melee(c, foes, enc)
	if path.is_empty():
		path = _path_closer(c, foes, enc)
	if path.is_empty():
		return []
	var budget: float = float(c.combat.moveLeft)
	if Grid.path_cost(c.cell(), path) > budget and c.combat.standard:
		budget = enc.move_budget(c)
	var out: Array = []
	var cost := 0.0
	var prev := c.cell()
	for step in path:
		cost += Grid.step_cost(prev, step)
		if cost > budget + 0.001:
			break
		out.append(step)
		prev = step
	# allies may be walked through but not stopped on: end the move on the last free tile
	while not out.is_empty() and not enc.can_stop(c, out[-1]):
		out.pop_back()
	return out


## The cheapest walk to a free tile next to any foe ([] if no such tile can be reached at all).
## Allies and bodies on the floor do not stop it (see "Who may walk where" in encounter.gd).
func _path_to_melee(c: Ent, foes: Array, enc) -> Array:
	var reach: Dictionary = enc.reach_within(c, FAR)
	var best = null
	var best_cost := 1.0e9
	for cell in reach:
		if not Encounter.reach_stop(reach, cell) or float(reach[cell].cost) >= best_cost:
			continue
		for f in foes:
			if Grid.cheb(cell, f.cell()) <= 1:
				best = cell
				best_cost = float(reach[cell].cost)
				break
	return Grid.path_from(reach, best) if best != null else []


## No free tile next to a foe (a doorway held by the front line, say): queue up behind the others.
## Plans the walk as if no creature were in the way, then follows it until an enemy blocks it.
func _path_closer(c: Ent, foes: Array, enc) -> Array:
	var target := _nearest(c, foes)
	if target == null:
		return []
	var plan: Array = Grid.find_path(c.cell(), target.cell(), enc.is_hard, true, 1500)
	var out: Array = []
	for step in plan:
		if not enc.can_pass(c, step):
			break
		out.append(step)
	return out
