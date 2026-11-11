class_name Effects
extends RefCounted
## Temporary effects (buffs, debuffs, conditions) on an actor. Pure logic.
##
## An actor is a character or monster Dictionary; effects live in actor.effects:
##   {id, name, modifiers: [modifier...], conditions: ["shaken", ...], duration: {...}, source}
## duration is one of:  {"rounds": n}   counts down at the start of the actor's own turn
##                      {"encounter": true}  removed when combat ends
##                      {"rest": true}       removed by a long rest
## Conditions are defined in data/conditions.json (their modifiers and flags are added automatically).
## Condition flags used by the engine: skipTurn, helpless, wakeOnDamage, noMove, flatFooted.


## All modifiers currently granted by the actor's effects (including condition modifiers).
static func mods(actor: Dictionary, db: Dictionary) -> Array:
	var out: Array = []
	for e in actor.get("effects", []):
		for m in e.get("modifiers", []):
			var copy: Dictionary = m.duplicate()
			copy["label"] = m.get("label", e.get("name", "Effect"))
			if not copy.has("type"):
				copy["type"] = "untyped"
			out.append(copy)
		for cid in e.get("conditions", []):
			var cond: Dictionary = db.conditions.get(cid, {})
			for m in cond.get("modifiers", []):
				var copy: Dictionary = m.duplicate()
				copy["label"] = cond.get("name", cid)
				if not copy.has("type"):
					copy["type"] = "untyped"
				out.append(copy)
	return out


static func conditions(actor: Dictionary) -> Array:
	var out: Array = []
	for e in actor.get("effects", []):
		for cid in e.get("conditions", []):
			if not (cid in out):
				out.append(cid)
	return out


static func has_condition(actor: Dictionary, cond_id: String) -> bool:
	return cond_id in conditions(actor)


static func flags(actor: Dictionary, db: Dictionary) -> Array:
	var out: Array = []
	for cid in conditions(actor):
		for f in db.conditions.get(cid, {}).get("flags", []):
			if not (f in out):
				out.append(f)
	return out


static func has_flag(actor: Dictionary, db: Dictionary, flag: String) -> bool:
	return flag in flags(actor, db)


## Adds an effect. An effect with the same id replaces the old one (effects do not stack with themselves).
static func add(actor: Dictionary, effect: Dictionary) -> void:
	if not actor.has("effects"):
		actor["effects"] = []
	remove(actor, effect.get("id", ""))
	actor.effects.append(effect.duplicate(true))


static func remove(actor: Dictionary, effect_id: String) -> void:
	var keep: Array = []
	for e in actor.get("effects", []):
		if e.get("id", "") != effect_id:
			keep.append(e)
	actor["effects"] = keep


## Removes every effect that carries the given condition (e.g. waking a sleeper).
static func remove_condition(actor: Dictionary, cond_id: String) -> void:
	var keep: Array = []
	for e in actor.get("effects", []):
		if not (cond_id in e.get("conditions", [])):
			keep.append(e)
	actor["effects"] = keep


## Counts down round-based durations. Returns the names of effects that just ended.
static func tick(actor: Dictionary) -> Array:
	var ended: Array = []
	var keep: Array = []
	for e in actor.get("effects", []):
		var d: Dictionary = e.get("duration", {})
		if d.has("rounds"):
			d["rounds"] = int(d.rounds) - 1
			if int(d.rounds) <= 0:
				ended.append(e.get("name", e.get("id", "effect")))
				continue
		keep.append(e)
	actor["effects"] = keep
	return ended


## scope "encounter": drops round-based and encounter-long effects. scope "rest": drops everything.
static func clear(actor: Dictionary, scope: String) -> void:
	var keep: Array = []
	if scope != "rest":
		for e in actor.get("effects", []):
			var d: Dictionary = e.get("duration", {})
			if d.has("rest"):
				keep.append(e)
	actor["effects"] = keep
