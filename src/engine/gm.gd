class_name GM
extends RefCounted
## The computer Game Master: decides who rolls, calls for checks, runs hazards, and narrates results.
## Everything the GM rolls goes through game.show_roll() so the player sees it in the dice tray.
##
## A CHECK spec (used by the "check" script op, dialogue choices and triggers):
##   {"skill": "perception", "dc": 15}            skill check
##   {"save": "ref", "dc": 14}                    saving throw
##   {"ability": "str", "dc": 12}                 raw ability check
##   optional: "who": "leader" | "best" | "<character id>"   (default: ctx.who, else "leader")
##             "tags": ["traps"]   situational bonuses that apply (see src/rules/mods.gd)
##             "label": "Spot the tripwire"   text for the journal
##
## Future work: an LLM-driven GM can be added by replacing GM.narrate_result() and by feeding
## game.state.journal to a model. Keep all dice in the rules engine - never let a model invent rolls.


## Makes the roll, shows it, logs it and returns true on success.
static func check(game, spec: Dictionary, ctx: Dictionary = {}) -> bool:
	var roller := pick_roller(game, spec, ctx)
	var stats: Dictionary = game.stats(roller)
	var result: Dictionary
	var tags: Array = spec.get("tags", [])
	if spec.has("skill"):
		result = Checks.skill(stats, spec.skill, spec.get("dc"), game.rng, game.db, tags)
	elif spec.has("save"):
		result = Checks.save(stats, spec.save, spec.get("dc"), game.rng, tags)
	elif spec.has("ability"):
		result = Checks.ability(stats, spec.ability, spec.get("dc"), game.rng)
	else:
		push_warning("check needs skill, save or ability: %s" % str(spec))
		return false
	if spec.has("label"):
		result["note"] = spec.label
	await game.show_roll(result)
	return result.get("success", true)


## Who makes the roll. "best" = the conscious party member with the highest bonus (the GM lets the
## expert step forward); trained-only skills are only attempted by someone who has ranks.
static func pick_roller(game, spec: Dictionary, ctx: Dictionary = {}) -> Dictionary:
	var who: String = spec.get("who", ctx.get("who", "leader"))
	if game.state.roster.has(who):
		return game.state.roster[who]
	if who != "best":
		return game.leader()
	var best: Dictionary = game.leader()
	var best_score := -999
	for c in game.party():
		if int(c.hp) <= 0:
			continue
		var s: Dictionary = game.stats(c)
		var score := -999
		if spec.has("skill"):
			var sk: Dictionary = s.skills.get(spec.skill, {})
			score = int(sk.get("total", 0)) + Stats.cond(s, ["skill", "skill." + str(spec.skill)], spec.get("tags", [])) if sk.get("usable", true) else -500
		elif spec.has("save"):
			score = int(s.saves[spec.save].total)
		elif spec.has("ability"):
			score = int(s.abilities[spec.ability].mod)
		if score > best_score:
			best_score = score
			best = c
	return best


## "[Diplomacy DC 14]" style tag for a choice button, or "" when there is no check.
static func check_tag(game, spec) -> String:
	if typeof(spec) != TYPE_DICTIONARY:
		return ""
	var label := ""
	if spec.has("skill"):
		label = game.db.skills.get(spec.skill, {}).get("name", Util.title(spec.skill))
	elif spec.has("save"):
		label = CharRules.SAVE_NAMES.get(spec.save, spec.save)
	elif spec.has("ability"):
		label = CharRules.ABILITY_NAMES.get(spec.ability, spec.ability)
	if spec.has("dc") and game.settings.get("show_dc", true):
		return "%s DC %d" % [label, int(spec.dc)]
	return label


## The "damage" script op: traps and other hazards outside (or inside) combat.
##   {"op": "damage", "dice": "2d6", "who": "leader|party|<id>", "label": "Spike trap",
##    "save": {"type": "ref", "dc": 14, "half": true}, "tags": ["traps"]}
static func hazard(game, a: Dictionary, ctx: Dictionary = {}) -> void:
	var targets: Array = game.scripts._who(a.get("who", "leader"))
	var rolled := Dice.roll(a.get("dice", "1d6"), game.rng)
	var label: String = a.get("label", "Hazard")
	await game.show_roll(Dice.as_result(rolled, "damage", label, "Game Master"))
	for c in targets:
		if int(c.hp) <= 0:
			continue
		var amount: int = rolled.total
		if a.has("save"):
			var sv: Dictionary = a.save
			var res := Checks.save(game.stats(c), sv.type, sv.get("dc", 12), game.rng, a.get("tags", []))
			await game.show_roll(res)
			if res.success:
				amount = floori(amount / 2.0) if sv.get("half", false) else 0
		if amount > 0:
			game.damage_character(c, amount, label)
		else:
			game.journal("combat", "%s avoids the %s." % [c.name, label.to_lower()])
