extends SceneTree
## Writes every licence notice the game needs into ONE text file, to ship next to an exported build
## (this game's licence, Godot Engine's licence, and the third-party components inside the engine).
##   godot --headless --path . -s res://tools/write_notices.gd                          -> build/THIRD_PARTY_NOTICES.txt
##   godot --headless --path . -s res://tools/write_notices.gd -- dist/NOTICES.txt      (path relative to the project, or absolute)
## The text is built by src/core/notices.gd from the engine that runs this script, so run it with the
## same Godot version that the build was exported with. Background: docs/LICENSING.md.


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var out: String = args[0] if args.size() > 0 else "build/THIRD_PARTY_NOTICES.txt"
	if out.is_relative_path():
		out = ProjectSettings.globalize_path("res://").path_join(out)
	DirAccess.make_dir_recursive_absolute(out.get_base_dir())
	var f := FileAccess.open(out, FileAccess.WRITE)
	if f == null:
		printerr("Could not write %s (error %d)" % [out, FileAccess.get_open_error()])
		quit(1)
		return
	var text := Notices.full_text()
	f.store_string(text)
	f.close()
	print("Wrote %s (%d characters: Godot %s, %d components, %d licence texts)" % [
		out, text.length(), Notices.godot_version(), Notices.components().size(), Notices.license_ids().size()])
	quit(0)
