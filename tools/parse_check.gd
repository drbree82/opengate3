extends SceneTree
## Loads every GDScript file in the project and reports the ones that fail to compile.
## Run through ./check.sh, or directly:
##   godot --headless --path . -s res://tools/parse_check.gd
## Godot prints the exact "Parse Error" lines (file + line number) above the summary.

const FOLDERS := ["res://src", "res://tests", "res://tools"]


func _initialize() -> void:
	var files: Array = []
	for folder in FOLDERS:
		_collect(folder, files)
	files.sort()
	var bad: Array = []
	for f in files:
		var script = load(f)
		if script == null or not (script is GDScript) or not script.can_instantiate():
			bad.append(f)
	if bad.is_empty():
		print("parse check: %d scripts OK" % files.size())
	else:
		printerr("parse check: %d of %d scripts FAILED to compile:" % [bad.size(), files.size()])
		for f in bad:
			printerr("   " + f)
	quit(1 if not bad.is_empty() else 0)


func _collect(folder: String, out: Array) -> void:
	for f in DirAccess.get_files_at(folder):
		if f.ends_with(".gd"):
			out.append(folder + "/" + f)
	for d in DirAccess.get_directories_at(folder):
		_collect(folder + "/" + d, out)
