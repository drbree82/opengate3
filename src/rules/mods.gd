class_name Mods
extends RefCounted
## Modifier stacking (Pathfinder bonus types). Pure logic.
##
## A modifier is a Dictionary: {target, value, type?, when?, label?, scale?}
##   target  what it changes:
##             "ac", "init", "hp", "speed", "cmb", "cmd", "ability.<str|dex|con|int|wis|cha>"
##             "attack" (all attacks), "attack.melee", "attack.ranged", "attack.weapon.<item id>"
##             "damage" (all damage),  "damage.melee", "damage.ranged", "damage.weapon.<item id>"
##             "save" (all saves), "save.fort", "save.ref", "save.will"
##             "skill" (all skills), "skill.<skill id>"
##   type    bonus type ("armor", "shield", "dodge", "morale", "enhancement", "racial", ...).
##           Bonuses of the same type do not stack (highest wins) except dodge/circumstance/untyped.
##           Penalties (negative values) always stack.
##   when    optional situation tag. The modifier only counts when the roll carries that tag
##           (e.g. "vs_fear", "traps", "vs_melee", "close"). Modifiers without `when` are always on.
##   scale   optional level scaling {per, offset, min, max}: adds floor((level + offset) / per), clamped.

const ALWAYS_STACK := ["dodge", "circumstance", "untyped"]


static func scaled_value(m: Dictionary, level: int) -> int:
	var v: int = m.get("value", 0)
	if m.has("scale"):
		var sc: Dictionary = m.scale
		var x: int = floori((level + int(sc.get("offset", 0))) / float(sc.get("per", 1)))
		if sc.has("min"):
			x = maxi(int(sc.min), x)
		if sc.has("max"):
			x = mini(int(sc.max), x)
		v += x
	return v


## Applies the stacking rules. Returns {total: int, parts: [{label, value}]}.
static func stack(mods: Array) -> Dictionary:
	var total := 0
	var parts: Array = []
	var best := {}
	for m in mods:
		var value: int = m.get("value", 0)
		if value == 0:
			continue
		var btype: String = m.get("type", "untyped")
		if value < 0 or btype in ALWAYS_STACK:
			total += value
			parts.append({"label": m.get("label", btype), "value": value})
		elif not best.has(btype) or value > int(best[btype].value):
			best[btype] = m
	for btype in best:
		var m: Dictionary = best[btype]
		total += int(m.value)
		parts.append({"label": m.get("label", btype), "value": int(m.value)})
	return {"total": total, "parts": parts}


## Selects modifiers aimed at any of `targets`.
## tags == null  -> only always-on modifiers (no `when`)
## tags == [...] -> only situational modifiers whose `when` is in tags
static func pick(mods: Array, targets: Array, tags = null) -> Array:
	var out: Array = []
	for m in mods:
		if not (m.target in targets):
			continue
		if tags == null:
			if not m.has("when"):
				out.append(m)
		elif m.has("when") and m.when in tags:
			out.append(m)
	return out


static func total(mods: Array, targets: Array, tags = null) -> int:
	return stack(pick(mods, targets, tags)).total
