class_name Checks
extends RefCounted
## d20 checks: skills, saves, ability checks, initiative. Pure logic.
## Every function returns a roll-result Dictionary (see dice.gd) ready for the dice tray.


static func d20(rng: Rng, kind: String, label: String, actor: String, parts: Array, dc = null, note := "") -> Dictionary:
	var nat := rng.die(20)
	var modifier := Util.sum_parts(parts)
	var r := {
		"kind": kind, "label": label, "actor": actor, "dice": [{"sides": 20, "value": nat}], "natural": nat,
		"parts": parts, "modifier": modifier, "total": nat + modifier, "note": note,
	}
	if dc != null:
		r["dc"] = int(dc)
		r["success"] = nat + modifier >= int(dc)
	return r


## Skill check. Skill checks have no automatic success/failure on a natural 20/1.
## A trained-only skill with no ranks cannot be attempted: the result is an automatic failure.
static func skill(stats: Dictionary, skill_id: String, dc, rng: Rng, db: Dictionary, tags: Array = []) -> Dictionary:
	var sk: Dictionary = stats.skills.get(skill_id, {"total": 0, "parts": [], "usable": true})
	var label: String = db.skills.get(skill_id, {}).get("name", Util.title(skill_id))
	if not sk.get("usable", true):
		var r := {"kind": "check", "label": label, "actor": stats.name, "dice": [], "parts": [], "modifier": 0, "total": 0, "note": "untrained - cannot attempt", "success": false}
		if dc != null:
			r["dc"] = int(dc)
		return r
	var parts: Array = sk.parts.duplicate()
	var extra := Stats.cond(stats, ["skill", "skill." + skill_id], tags)
	if extra != 0:
		parts.append({"label": "Situational", "value": extra})
	return d20(rng, "check", label, stats.name, parts, dc)


## Saving throw. A natural 1 always fails and a natural 20 always succeeds.
static func save(stats: Dictionary, save_id: String, dc, rng: Rng, tags: Array = []) -> Dictionary:
	var sv: Dictionary = stats.saves[save_id]
	var parts: Array = sv.parts.duplicate()
	var extra := Stats.cond(stats, ["save", "save." + save_id], tags)
	if extra != 0:
		parts.append({"label": "Situational", "value": extra})
	var r := d20(rng, "save", CharRules.SAVE_NAMES[save_id] + " save", stats.name, parts, dc)
	if dc != null:
		if r.natural == 1:
			r.success = false
		elif r.natural == 20:
			r.success = true
	return r


static func ability(stats: Dictionary, ability_id: String, dc, rng: Rng) -> Dictionary:
	var parts: Array = [{"label": CharRules.ABILITY_SHORT[ability_id], "value": stats.abilities[ability_id].mod}]
	return d20(rng, "check", CharRules.ABILITY_NAMES[ability_id] + " check", stats.name, parts, dc)


static func initiative(stats: Dictionary, rng: Rng) -> Dictionary:
	return d20(rng, "initiative", "Initiative", stats.name, stats.initParts.duplicate())
