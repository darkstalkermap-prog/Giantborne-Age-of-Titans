extends Node
## Headless test runner. Usage (from the project folder):
##   godot --headless --fixed-fps 60 res://tests/run_tests.tscn -- --no-user-settings [--filter=unit]
## Exit code 0 when every check passes, 1 otherwise. Prints one line per suite.

const SUITE_DIRS := ["res://tests/unit", "res://tests/integration"]


func _ready() -> void:
	await get_tree().process_frame
	var filter := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--filter="):
			filter = arg.substr(9)
	var total_checks := 0
	var total_failures: Array[String] = []
	var suites := 0
	print("Giantborn tests | Godot %s | data errors: %d" % [Engine.get_version_info().string, GameData.errors.size()])
	for e in GameData.errors:
		total_failures.append("data: " + e)
	for dir_path: String in SUITE_DIRS:
		for path in _list_suites(dir_path):
			if filter != "" and not path.contains(filter):
				continue
			var script: GDScript = load(path)
			if script == null:
				total_failures.append("%s: failed to load (parse error?)" % path)
				continue
			var suite: TestSuite = script.new()
			suite.name = path.get_file().get_basename()
			add_child(suite)
			suites += 1
			var started := Time.get_ticks_msec()
			for m: Dictionary in suite.get_method_list():
				var method_name: String = m.name
				if not method_name.begins_with("test_"):
					continue
				suite.current_test = "%s.%s" % [suite.name, method_name]
				Sim.reseed(Sim.DEFAULT_SEED)
				await suite.before_each()
				await suite.call(method_name)
				await suite.after_each()
			total_checks += suite.checks
			total_failures.append_array(suite.failures)
			print("  %-40s %4d checks  %3d failures  (%d ms)" % [suite.name, suite.checks,
				suite.failures.size(), Time.get_ticks_msec() - started])
			suite.queue_free()
			await get_tree().process_frame
	print("")
	for f in total_failures:
		print("FAIL  " + f)
	print("RESULT: %d suites, %d checks, %d failures" % [suites, total_checks, total_failures.size()])
	get_tree().quit(1 if not total_failures.is_empty() else 0)


func _list_suites(dir_path: String) -> PackedStringArray:
	var out := PackedStringArray()
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return out
	for f in dir.get_files():
		if f.begins_with("test_") and f.ends_with(".gd"):
			out.append(dir_path.path_join(f))
	out.sort()
	return out
