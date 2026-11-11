class_name Stats
extends RefCounted
## One entry point to get the derived STATS of any actor (player character or monster).


static func of(actor: Dictionary, db: Dictionary) -> Dictionary:
	if actor.has("monsterId"):
		return MonsterRules.derive(actor, db)
	return CharRules.derive(actor, db)


## Sum of the SITUATIONAL modifiers (those with a `when` tag) matching targets + tags.
## Always-on modifiers are already baked into the stats numbers.
static func cond(stats: Dictionary, targets: Array, tags: Array) -> int:
	if tags.is_empty():
		return 0
	return Mods.total(stats.get("mods", []), targets, tags)


static func skill_total(stats: Dictionary, skill_id: String) -> int:
	var sk = stats.skills.get(skill_id)
	return int(sk.total) if sk != null else 0


static func is_pc(actor: Dictionary) -> bool:
	return not actor.has("monsterId")
