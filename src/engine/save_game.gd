class_name SaveGame
extends RefCounted
## Save files: one JSON file per slot in user://saves/ (on Linux:
## ~/.local/share/godot/app_userdata/OpenGate/saves/). The content is Game.save_data().

const DIR := "user://saves"


static func path(slot: String) -> String:
	return "%s/%s.json" % [DIR, slot.validate_filename()]


static func write(game, slot: String) -> bool:
	return Util.save_json(path(slot), game.save_data())


static func read(slot: String):
	return Util.load_json(path(slot))


static func exists(slot: String) -> bool:
	return FileAccess.file_exists(path(slot))


## Newest first: [{slot, campaignId, time, summary}]
static func list() -> Array:
	var out: Array = []
	if not DirAccess.dir_exists_absolute(DIR):
		return out
	for f in DirAccess.get_files_at(DIR):
		if not f.ends_with(".json"):
			continue
		var data = Util.load_json("%s/%s" % [DIR, f])
		if typeof(data) == TYPE_DICTIONARY and data.has("state"):
			out.append({"slot": f.get_basename(), "campaignId": data.get("campaignId", ""), "time": int(data.get("savedAt", 0)), "summary": data.get("summary", "")})
	out.sort_custom(func(a, b): return a.time > b.time)
	return out
