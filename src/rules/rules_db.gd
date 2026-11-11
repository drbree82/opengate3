class_name RulesDB
extends RefCounted
## Loads the rules data tables from res://data/*.json into one Dictionary called `db`:
##   db.skills, db.races, db.classes, db.feats, db.items, db.spells, db.monsters, db.conditions, db.props
## Every entry gets its key copied into an "id" field. Keys starting with "_" are comments and removed.
## A campaign may add or override entries by shipping files with the same names (see with_campaign).

const TABLES := ["skills", "races", "classes", "feats", "items", "spells", "monsters", "conditions", "props"]


static func load_base() -> Dictionary:
	var db := {}
	for t in TABLES:
		var table = Util.load_json("res://data/%s.json" % t, {})
		if typeof(table) != TYPE_DICTIONARY:
			push_error("data/%s.json must be a JSON object" % t)
			table = {}
		db[t] = _clean(table)
	return db


## Returns a copy of the base db with the campaign's own tables layered on top.
static func with_campaign(db: Dictionary, campaign_dir: String) -> Dictionary:
	var out := {}
	for t in TABLES:
		var merged: Dictionary = db[t].duplicate(true)
		var extra = Util.load_json("%s/%s.json" % [campaign_dir, t], {})
		if typeof(extra) == TYPE_DICTIONARY:
			merged.merge(_clean(extra), true)
		out[t] = merged
	return out


static func _clean(table: Dictionary) -> Dictionary:
	for k in table.keys():
		if str(k).begins_with("_") or typeof(table[k]) != TYPE_DICTIONARY:
			table.erase(k)
		else:
			table[k]["id"] = k
	return table
