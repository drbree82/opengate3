class_name CombatRules
extends RefCounted
## Attack and damage resolution (Pathfinder 1e). Pure logic - the encounter engine decides WHEN to
## call these, shows the returned rolls in the dice tray, then applies the damage.


## Resolves one attack.
##   att, def  STATS of attacker and defender (Stats.of)
##   attack    one entry of att.attacks
##   ctx       {tags: [situation tags], attack_mods: [{label, value}], flat_footed: bool,
##              helpless: bool, sneak_dice: int}
## Returns {hit, crit, fumble, ac, damage, dr, rolls: [roll results in display order]}
static func resolve_attack(att: Dictionary, attack: Dictionary, def: Dictionary, ctx: Dictionary, rng: Rng) -> Dictionary:
	var tags: Array = ctx.get("tags", [])
	var parts: Array = attack.parts.duplicate()
	var situational := Stats.cond(att, attack.get("targets", ["attack"]), tags)
	if situational != 0:
		parts.append({"label": "Situational", "value": situational})
	parts.append_array(ctx.get("attack_mods", []))

	var denied: bool = ctx.get("flat_footed", false) or ctx.get("helpless", false)
	var ac: int = def.touch if attack.get("touch", false) else (def.flatFooted if denied else def.ac)
	ac += Stats.cond(def, ["ac"], ["vs_ranged"] if attack.get("ranged", false) else ["vs_melee"])

	var roll := Checks.d20(rng, "attack", attack.name, att.name, parts, ac, "vs AC %d" % ac)
	var nat: int = roll.natural
	var hit: bool = nat != 1 and (nat == 20 or int(roll.total) >= ac)
	roll["success"] = hit
	roll["fumble"] = nat == 1
	var out := {"hit": hit, "crit": false, "fumble": nat == 1, "ac": ac, "damage": 0, "dr": 0, "rolls": [roll]}
	if not hit:
		return out

	if nat >= int(attack.get("critRange", 20)):
		var confirm := Checks.d20(rng, "attack", "Confirm critical", att.name, parts, ac, "vs AC %d" % ac)
		var confirmed: bool = confirm.natural != 1 and (confirm.natural == 20 or int(confirm.total) >= ac)
		confirm["success"] = confirmed
		out.rolls.append(confirm)
		out.crit = confirmed
		roll["crit"] = confirmed

	var dmg := roll_damage(att, attack, def, out.crit, ctx, rng)
	out.rolls.append(dmg.roll)
	out.damage = dmg.damage
	out.dr = dmg.dr
	return out


## Rolls weapon damage. Critical hits roll the weapon dice and bonus `critMult` times;
## sneak attack dice are never multiplied. A hit always deals at least 1 damage before DR.
static func roll_damage(att: Dictionary, attack: Dictionary, def: Dictionary, crit: bool, ctx: Dictionary, rng: Rng) -> Dictionary:
	var mult: int = int(attack.get("critMult", 2)) if crit else 1
	var rolled := Dice.roll(attack.damage, rng, mult)
	var dice: Array = rolled.dice
	var total: int = rolled.total
	var parts: Array = []
	if rolled.flat != 0:
		parts.append({"label": "Bonus", "value": rolled.flat})
	var situational := Stats.cond(att, attack.get("damageTargets", ["damage"]), ctx.get("tags", []))
	if situational != 0:
		parts.append({"label": "Situational", "value": situational})
		total += situational
	var notes: Array = []
	if crit:
		notes.append("Critical x%d" % mult)
	var sneak: int = ctx.get("sneak_dice", 0)
	if sneak > 0:
		var sr := Dice.roll("%dd6" % sneak, rng)
		dice = dice + sr.dice
		total += sr.total
		notes.append("Sneak attack +%dd6" % sneak)
	total = maxi(1, total)
	var reduced := 0
	var dr = def.get("dr")
	if dr != null and not _bypasses(str(attack.get("dtype", "")), str(dr.get("bypass", ""))):
		reduced = mini(total, int(dr.amount))
		notes.append("DR %d/%s absorbs %d" % [dr.amount, _dtype_name(str(dr.get("bypass", "-"))), reduced])
	var result := {
		"kind": "damage", "label": attack.name + " damage", "actor": att.name, "dice": dice, "parts": parts,
		"modifier": Util.sum_parts(parts), "total": total, "note": ", ".join(notes),
	}
	return {"roll": result, "damage": total - reduced, "dr": reduced}


static func _bypasses(dtype: String, bypass: String) -> bool:
	if bypass == "" or bypass == "-":
		return false
	for letter in dtype.split("/"):
		if letter == bypass:
			return true
	return false


static func _dtype_name(letter: String) -> String:
	return {"B": "bludgeoning", "S": "slashing", "P": "piercing"}.get(letter, letter)


## Alive / down / dead. Monsters die at 0 hp. Player characters fall unconscious at 0 or below and
## die at negative Constitution score. (Simplification: the "disabled at exactly 0" state is skipped.)
static func life_state(actor: Dictionary, stats: Dictionary) -> String:
	var hp: int = actor.hp
	if stats.kind == "monster":
		return "dead" if hp <= 0 else "ok"
	if hp <= -int(stats.abilities.con.score):
		return "dead"
	return "down" if hp <= 0 else "ok"


static func apply_damage(actor: Dictionary, stats: Dictionary, amount: int) -> String:
	actor.hp = int(actor.hp) - maxi(0, amount)
	return life_state(actor, stats)


## Heals up to hpMax. Returns the amount actually healed.
static func heal(actor: Dictionary, stats: Dictionary, amount: int) -> int:
	var before: int = actor.hp
	actor.hp = mini(int(stats.hpMax), before + maxi(0, amount))
	return int(actor.hp) - before


## A dying character rolls each turn: DC 10 Constitution check with a penalty equal to negative hp.
## Success = stable. Failure = lose 1 hp.
static func stabilize_roll(actor: Dictionary, stats: Dictionary, rng: Rng) -> Dictionary:
	var parts: Array = [{"label": "Con", "value": stats.abilities.con.mod}, {"label": "Negative hp", "value": mini(0, int(actor.hp))}]
	return Checks.d20(rng, "check", "Stabilize", stats.name, parts, 10)
