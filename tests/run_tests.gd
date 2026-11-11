extends SceneTree
## Headless test runner.  Usage (from the project folder):
##   ./check.sh                          # import + all tests
##   godot --headless --path . -s res://tests/run_tests.gd
##   godot --headless --path . -s res://tests/run_tests.gd -- test_rules   # only files containing "test_rules"
##
## Every tests/test_*.gd file is loaded; each method named test_* is called with this runner as `t`.
## Use t.eq(actual, expected, "message") and t.ok(condition, "message").

var checks := 0
var failures := 0
var current := ""


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var only := ""
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		only = args[0]
	var files := Array(DirAccess.get_files_at("res://tests"))
	files.sort()
	for f in files:
		if not (f.begins_with("test_") and f.ends_with(".gd")):
			continue
		if only != "" and not f.contains(only):
			continue
		var script = load("res://tests/" + f)
		if script == null or not script.can_instantiate():
			failures += 1
			printerr("FAIL  could not load tests/%s (script error?)" % f)
			continue
		var inst = script.new()
		for m in inst.get_method_list():
			if not str(m.name).begins_with("test_"):
				continue
			current = "%s :: %s" % [f, m.name]
			var before := failures
			await inst.call(m.name, self)
			print("%s  %s" % ["ok  " if failures == before else "FAIL", current])
	print("\n%d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)


func eq(actual, expected, msg := "") -> void:
	checks += 1
	if typeof(actual) != typeof(expected) or actual != expected:
		failures += 1
		printerr("    FAIL [%s] %s: expected %s but got %s" % [current, msg, str(expected), str(actual)])


func ok(cond, msg := "") -> void:
	checks += 1
	if not cond:
		failures += 1
		printerr("    FAIL [%s] %s" % [current, msg])
