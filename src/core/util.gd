class_name Util
extends RefCounted
## Small shared helpers: JSON loading, number formatting, dictionary utilities.
## Pure logic - safe to use from headless tests.


## Loads a JSON file. Returns `fallback` when the file is missing or invalid (and logs the error).
## Whole-number floats are converted to int, so `dc == 15` and array indexing work as expected.
static func load_json(path: String, fallback = null):
	if not FileAccess.file_exists(path):
		return fallback
	var text := FileAccess.get_file_as_string(path)
	var json := JSON.new()
	if json.parse(text) != OK:
		push_error("Invalid JSON in %s (line %d): %s" % [path, json.get_error_line(), json.get_error_message()])
		return fallback
	return intify(json.data)


## Recursively converts floats that hold whole numbers into ints (Godot parses all JSON numbers as float).
static func intify(v):
	match typeof(v):
		TYPE_FLOAT:
			return int(v) if v == floorf(v) and absf(v) < 9.0e15 else v
		TYPE_ARRAY:
			for i in v.size():
				v[i] = intify(v[i])
		TYPE_DICTIONARY:
			for k in v.keys():
				v[k] = intify(v[k])
	return v


static func save_json(path: String, data) -> bool:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_error("Cannot write %s" % path)
		return false
	f.store_string(JSON.stringify(data, "\t"))
	f.close()
	return true


## "+3", "-1", "+0"
static func signed(n) -> String:
	return ("+%d" % int(n)) if int(n) >= 0 else str(int(n))


## Deep copy of a Dictionary/Array (other values are returned unchanged).
static func deep(v):
	if typeof(v) == TYPE_DICTIONARY or typeof(v) == TYPE_ARRAY:
		return v.duplicate(true)
	return v


## Sum of the `value` fields of a parts array: [{label, value}, ...]
static func sum_parts(parts: Array) -> int:
	var total := 0
	for p in parts:
		total += int(p.value)
	return total


## "a_b_c" -> "A B C"
static func title(id: String) -> String:
	return id.replace("_", " ").capitalize()


static func color(hex, fallback := Color.WHITE) -> Color:
	if typeof(hex) == TYPE_COLOR:
		return hex
	if typeof(hex) == TYPE_STRING and Color.html_is_valid(hex):
		return Color.html(hex)
	return fallback
