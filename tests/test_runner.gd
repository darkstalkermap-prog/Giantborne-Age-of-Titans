class_name TestRunner
extends Node
## Headless test runner. Usage (from the project folder):
##   tools/gd.sh --headless --path . --fixed-fps 60 res://tests/run_tests.tscn -- --no-user-settings
##       [--no-audio] [--filter=unit] [--slow] [--gate] [--titans] [--no-titans] [--with-audio]
## --filter= keeps the suites whose path contains it; several, comma-separated, keep the suites that match any of
## them, in the runner's usual order (one process: to find which earlier suites change a later one's outcome).
## Runs every test_*.gd in tests/unit and tests/integration (flat folders, sorted), plus
## tests/slow with --slow and tests/gate with --gate (P19: walkthroughs, oath combinations,
## seeded boss runs and soaks; plan M6-M9 decision 34). Exit code 0 when every check passes, 1
## otherwise. One line per suite.
## B4 (the milestone B gate): the titans' balance duels (each signature titan's bot duels, at minutes of simulated
## fighting each) are their own tier, tests/titans, run with --titans and by --gate (--no-titans leaves them out:
## tools/check.sh runs them as a second process, so each tier keeps its own time budget and its own time limit).
##
## B5: --suite=res://<folder>/test_<name>.gd runs that one suite file wherever it lives (a tool's probe written as a
## suite, such as tools/duel_leak/test_duel_leak.gd, the titans' duel bisection harness), and nothing else.
##
## Audio (P19): the run is silent by default - the Audio autoload is switched off for the whole run
## (as with --no-audio, which tools/check.sh also passes), and audio suites turn it on for their
## own tests with Audio.enable_for_tests(); ResetHooks puts it back off before every test.
## --with-audio leaves it on for every suite.
##
## Per test: Sim.reseed -> ResetHooks.BEFORE_EACH -> suite.before_each -> the test ->
## suite.after_each -> ResetHooks.AFTER_EACH -> every engine/script error logged meanwhile
## becomes a failure. A test that deliberately raises errors drains them with
## TestRunner.take_logged_errors() before it returns.

const SUITE_DIRS := ["res://tests/unit", "res://tests/integration"]
const SLOW_DIR := "res://tests/slow"
## P19: the gate tier (decision 34), run with --gate at milestone gates and the W18, W21, W22 merges.
const GATE_DIR := "res://tests/gate"
## B4: the titans' duels (with --titans, and with --gate unless --no-titans).
const TITANS_DIR := "res://tests/titans"

static var _logger: TestErrorLogger = null


## The folders to run, in order.
static func suite_dirs(slow: bool, gate := false, titans := false) -> PackedStringArray:
	var dirs := PackedStringArray(SUITE_DIRS)
	if slow:
		dirs.append(SLOW_DIR)
	if gate:
		dirs.append(GATE_DIR)
	if titans:
		dirs.append(TITANS_DIR)
	return dirs


## The test tier of a suite folder: "slow", "gate", "titans" or "default" (unit and integration).
static func tier_of(dir_path: String) -> String:
	if dir_path == SLOW_DIR:
		return "slow"
	if dir_path == GATE_DIR:
		return "gate"
	if dir_path == TITANS_DIR:
		return "titans"
	return "default"


## Removes and returns the errors logged since the last check (for tests that provoke errors
## on purpose; anything left is reported as a failure of the running test).
static func take_logged_errors() -> Array[String]:
	if _logger == null:
		return [] as Array[String]
	return _logger.take()


func _ready() -> void:
	# Tests never read or write the player's user://settings.json, whatever the flags.
	Settings.persist = false
	Settings.values = Settings.DEFAULTS.duplicate(true)
	Settings.load_message = ""
	Settings.apply_bindings()
	_logger = TestErrorLogger.new()
	OS.add_logger(_logger)
	await get_tree().process_frame
	_logger.take()  # discard anything logged during startup
	var filter := ""
	var slow := false
	var gate := false
	var titans := false
	var no_titans := false
	var with_audio := false
	var only_suite := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--filter="):
			filter = arg.substr(9)
		elif arg.begins_with("--suite="):
			only_suite = arg.substr(8)
		elif arg == "--slow":
			slow = true
		elif arg == "--gate":
			gate = true
		elif arg == "--titans":
			titans = true
		elif arg == "--no-titans":
			no_titans = true
		elif arg == "--with-audio":
			with_audio = true
	titans = (titans or gate) and not no_titans
	# P19: silent by default; audio suites enable it per test (Audio.enable_for_tests).
	var audio := get_node_or_null("/root/Audio")
	if audio != null and audio.has_method("set_process_default"):
		audio.call("set_process_default", with_audio)
	var total_checks := 0
	var total_failures: Array[String] = []
	var suites := 0
	var tier_ms := {}   # P19: wall time per tier (folder), printed as the TIMES line check.sh records
	print("Giantborn tests | Godot %s | data errors: %d%s%s%s%s" % [Engine.get_version_info().string,
		GameData.errors.size(), " | with slow suites" if slow else "", " | with gate suites" if gate else "",
		" | with the titans' duels" if titans else "", " | audio on" if with_audio else ""])
	for e in GameData.errors:
		total_failures.append("data: " + e)
	var dirs := suite_dirs(slow, gate, titans) if only_suite == "" else PackedStringArray([only_suite.get_base_dir()])
	for dir_path: String in dirs:
		var tier_started := Time.get_ticks_msec()
		for path in list_suites(dir_path):
			if not filter_keeps(filter, path) or (only_suite != "" and path != only_suite):
				continue
			var made := instantiate_suite(path)
			if made.suite == null:
				# A suite that does not compile is a failure of its own, never a stall (P17a,
				# FOLLOWUPS): its parse errors are reported with it, not with the next test.
				suites += 1
				total_failures.append(str(made.error))
				for err in _logger.take():
					total_failures.append("%s: engine/script error: %s" % [path, err])
				print("  %-40s FAILED TO LOAD" % path.get_file().get_basename())
				continue
			var suite: TestSuite = made.suite
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
				var before_problems: PackedStringArray = await ResetHooks.run(ResetHooks.BEFORE_EACH, get_tree())
				for problem in before_problems:
					suite.fail("before_each hook: " + problem)
				await suite.before_each()
				await suite.call(method_name)
				await suite.after_each()
				var after_problems: PackedStringArray = await ResetHooks.run(ResetHooks.AFTER_EACH, get_tree())
				for problem in after_problems:
					suite.fail(problem)
				for err in _logger.take():
					suite.failures.append("%s: engine/script error: %s" % [suite.current_test, err])
			total_checks += suite.checks
			total_failures.append_array(suite.failures)
			print("  %-40s %4d checks  %3d failures  (%d ms)" % [suite.name, suite.checks,
				suite.failures.size(), Time.get_ticks_msec() - started])
			suite.queue_free()
			await get_tree().process_frame
		var tier := tier_of(dir_path)
		tier_ms[tier] = int(tier_ms.get(tier, 0)) + Time.get_ticks_msec() - tier_started
	print("")
	print("TIMES: default %.1f s | slow %.1f s | gate %.1f s | titans %.1f s" % [int(tier_ms.get("default", 0)) / 1000.0,
		int(tier_ms.get("slow", 0)) / 1000.0, int(tier_ms.get("gate", 0)) / 1000.0,
		int(tier_ms.get("titans", 0)) / 1000.0])
	for f in total_failures:
		print("FAIL  " + f)
	# M9 gate (final): the wall-clock budgets measured over budget on a loaded machine (BudgetRule), for check.sh
	for w in BudgetRule.warnings:
		print(w)
	print("WARNINGS: %d" % BudgetRule.warnings.size())
	print("RESULT: %d suites, %d checks, %d failures" % [suites, total_checks, total_failures.size()])
	OS.remove_logger(_logger)
	get_tree().quit(1 if not total_failures.is_empty() else 0)


## Whether --filter=`filter` keeps the suite at `path`: no filter keeps every suite; otherwise the path contains one
## of its comma-separated parts.
static func filter_keeps(filter: String, path: String) -> bool:
	if filter == "":
		return true
	for part in filter.split(",", false):
		if path.contains(part):
			return true
	return false


## The suite in the script at `path`, ready to add: {"suite": TestSuite, "error": ""}, or
## {"suite": null, "error": "<path>: <why>"} when the script does not load, does not compile (a
## parse error: GDScript.can_instantiate() is false, and new() would fail) or is not a TestSuite.
## The runner used to call new() on a broken script; the error stopped its coroutine and the run
## stalled until check.sh's time limit (P17a, FOLLOWUPS).
static func instantiate_suite(path: String) -> Dictionary:
	var script := load(path) as GDScript
	if script == null:
		return {"suite": null, "error": "%s: failed to load" % path}
	if not script.can_instantiate():
		return {"suite": null, "error": "%s: does not compile (parse error)" % path}
	var instance: Variant = script.new()
	if not (instance is TestSuite):
		if instance is Node:
			(instance as Node).free()
		return {"suite": null, "error": "%s: is not a TestSuite" % path}
	return {"suite": instance, "error": ""}


## test_*.gd files directly in dir_path (no recursion), sorted. A missing folder is empty.
static func list_suites(dir_path: String) -> PackedStringArray:
	var out := PackedStringArray()
	if not DirAccess.dir_exists_absolute(dir_path):
		return out
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return out
	for f in dir.get_files():
		if f.begins_with("test_") and f.ends_with(".gd"):
			out.append(dir_path.path_join(f))
	out.sort()
	return out
