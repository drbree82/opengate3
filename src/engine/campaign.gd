class_name Campaign
extends RefCounted
## Finds and loads campaigns. A campaign is a folder (format: docs/CAMPAIGN_FORMAT.md):
##   campaigns/<id>/campaign.json     name, start, camp, voices...
##   campaigns/<id>/maps/*.json       one file per map (file name = map id)
##   campaigns/<id>/dialogues/*.json  one file per conversation
##   campaigns/<id>/cutscenes/*.json  one file per cutscene
##   campaigns/<id>/entities.json, quests.json, encounters.json, companions.json, shops.json
##   campaigns/<id>/items.json, monsters.json, spells.json ... (optional rules overrides)
## Campaigns are looked up in the project (res://campaigns) and in the user folder (user://campaigns).

const ROOTS := ["res://campaigns", "user://campaigns"]


static func list() -> Array:
	var out: Array = []
	for root in ROOTS:
		if not DirAccess.dir_exists_absolute(root):
			continue
		for d in DirAccess.get_directories_at(root):
			if d.begins_with("_"):
				continue  # folders starting with "_" (like _template) are hidden from the menu
			var info = Util.load_json("%s/%s/campaign.json" % [root, d])
			if typeof(info) == TYPE_DICTIONARY:
				out.append({"id": d, "dir": "%s/%s" % [root, d], "name": info.get("name", d), "description": info.get("description", ""), "author": info.get("author", "")})
	return out


static func dir_of(campaign_id: String) -> String:
	for root in ROOTS:
		var d := "%s/%s" % [root, campaign_id]
		if FileAccess.file_exists(d + "/campaign.json"):
			return d
	return ""


## Loads a whole campaign into one Dictionary. Problems are collected in the "errors" array.
static func load_campaign(campaign_id: String) -> Dictionary:
	var dir := dir_of(campaign_id)
	if dir == "":
		return {"id": campaign_id, "errors": ["campaign '%s' not found" % campaign_id]}
	var c = Util.load_json(dir + "/campaign.json", {})
	if typeof(c) != TYPE_DICTIONARY or c.is_empty():
		return {"id": campaign_id, "errors": ["campaign.json is missing or invalid"]}
	c["id"] = campaign_id
	c["dir"] = dir
	c["errors"] = []
	for sub in ["maps", "dialogues", "cutscenes"]:
		var table := {}
		var files := Array(DirAccess.get_files_at("%s/%s" % [dir, sub]))
		files.sort()
		for f in files:
			if not f.ends_with(".json"):
				continue
			var data = Util.load_json("%s/%s/%s" % [dir, sub, f])
			if typeof(data) != TYPE_DICTIONARY:
				c.errors.append("%s/%s is not valid JSON" % [sub, f])
				continue
			table[f.get_basename()] = data
		c[sub] = table
	for name in ["entities", "quests", "encounters", "companions", "shops"]:
		var data = Util.load_json("%s/%s.json" % [dir, name], {})
		if typeof(data) != TYPE_DICTIONARY:
			c.errors.append("%s.json must be a JSON object" % name)
			data = {}
		for k in data.keys():
			if str(k).begins_with("_") or typeof(data[k]) != TYPE_DICTIONARY:
				data.erase(k)
			else:
				data[k]["id"] = k
		c[name] = data
	_assign_voice_keys(c)
	return c


## Every spoken line gets a stable voice key (= the name of its audio file in the voice/ folder):
##   dialogue node  ->  "dlg.<dialogue id>.<node id>"
##   cutscene line  ->  "cs.<cutscene id>.<n>"   (n = running number of say/narrate steps, depth first)
## tools/gen_voices.mjs uses exactly the same rule. An explicit "voice" field overrides the key.
static func _assign_voice_keys(c: Dictionary) -> void:
	for did in c.dialogues:
		var nodes: Dictionary = c.dialogues[did].get("nodes", {})
		for nid in nodes:
			if typeof(nodes[nid]) == TYPE_DICTIONARY and nodes[nid].has("text") and not nodes[nid].has("voice"):
				nodes[nid]["voice"] = "dlg.%s.%s" % [did, nid]
	for cid in c.cutscenes:
		var counter := [0]
		_number_steps(c.cutscenes[cid].get("steps", []), "cs.%s" % cid, counter)


static func _number_steps(steps: Array, prefix: String, counter: Array) -> void:
	for s in steps:
		if typeof(s) != TYPE_DICTIONARY:
			continue
		if s.get("op", "") in ["say", "narrate"]:
			counter[0] += 1
			if not s.has("voice"):
				s["voice"] = "%s.%d" % [prefix, counter[0]]
		if s.has("steps"):
			_number_steps(s.steps, prefix, counter)
