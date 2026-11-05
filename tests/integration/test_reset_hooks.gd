extends IntegrationSuite
## ResetHooks (plan §2.13): present entries run in order (coroutines awaited), missing autoloads,
## scripts and methods are skipped without errors, a positive leftover count becomes a failure
## message; the shipped lists resolve; TestFixtures overrides are undone after every test.

const PROBE_SCRIPT := "res://tests/support/reset_hook_probe.gd"


class AutoloadProbe:
	extends Node

	func reset_for_tests() -> void:
		ResetHookProbe.calls.append("autoload.reset")   # one log for both kinds of entries


var _autoload: AutoloadProbe


func before_each() -> void:
	await super()
	ResetHookProbe.calls.clear()
	_autoload = AutoloadProbe.new()
	_autoload.name = "ResetHookProbeAutoload"
	get_tree().root.add_child(_autoload)


func after_each() -> void:
	if is_instance_valid(_autoload):
		_autoload.queue_free()
	await super()


func _calls() -> Array[String]:
	return ResetHookProbe.calls


func test_present_entries_run_in_order_and_missing_ones_are_skipped() -> void:
	var list := [
		["script", PROBE_SCRIPT, "first"],
		["autoload", "NoSuchAutoload", "reset_for_tests"],
		["autoload", "ResetHookProbeAutoload", "reset_for_tests"],
		["script", "res://tests/support/no_such_script.gd", "restore_all"],
		["script", PROBE_SCRIPT, "no_such_method"],
		["autoload", "ResetHookProbeAutoload", "no_such_method"],
		["script", PROBE_SCRIPT, "waits"],
		["script", PROBE_SCRIPT, "leftovers", "probe left 2 things"],
		["script", PROBE_SCRIPT, "first", "no leftovers reported for a void hook"],
		["broken"],
	]
	var problems: PackedStringArray = await ResetHooks.run(list, get_tree())
	assert_eq(_calls(), ["script.first", "autoload.reset", "script.waits.begin", "script.waits.end",
		"script.leftovers", "script.first"] as Array[String], "present entries run in order; coroutines are awaited")
	assert_eq(problems, PackedStringArray(["probe left 2 things (2)"]), "a positive leftover count is reported")


func test_shipped_lists_resolve() -> void:
	for entry: Array in ResetHooks.BEFORE_EACH + ResetHooks.AFTER_EACH:
		assert_true(entry.size() >= 3 and str(entry[0]) in ["autoload", "script"], "well-formed entry %s" % [entry])
		var target := ResetHooks.resolve(entry, get_tree())
		var expected_present := false
		if entry[0] == "script":
			expected_present = ResourceLoader.exists(str(entry[1]))
		else:
			expected_present = get_tree().root.has_node(NodePath(str(entry[1])))
		assert_eq(target != null, expected_present, "%s resolves exactly when it exists" % entry[1])
		if target != null:
			assert_true(ResetHooks.has_callable(target, str(entry[2])), "%s.%s exists" % [entry[1], entry[2]])
	var problems: PackedStringArray = await ResetHooks.run(ResetHooks.BEFORE_EACH, get_tree())
	assert_eq(problems.size(), 0, "BEFORE_EACH runs cleanly here")


func test_fixture_overrides_are_restored() -> void:
	var original: Dictionary = GameData.get_record("ability.light_1").duplicate(true)
	var original_power := GameData.get_action("ability.light_1").power
	TestFixtures.record_override("ability.light_1", {"power": 99, "movement": {"windup_speed_mult": 0.75}})
	assert_near(float(GameData.get_record("ability.light_1").power), 99.0, 1e-9, "record patched")
	assert_near(GameData.get_action("ability.light_1").power, 99.0, 1e-9, "the cached ActionDef follows")
	var movement: Dictionary = GameData.get_record("ability.light_1").movement
	assert_near(float(movement.windup_speed_mult), 0.75, 1e-9, "nested keys merge")
	assert_eq(movement.size(), (original.movement as Dictionary).size(), "other nested keys stay")
	TestFixtures.record_override("ability.light_1", {"power": 12})
	assert_near(GameData.get_action("ability.light_1").power, 12.0, 1e-9, "a second override stacks")
	assert_eq(TestFixtures.pending_count(), 2, "two overrides pending")
	var restored := TestFixtures.restore_all()
	assert_eq(restored, 2, "restore_all undoes both, newest first")
	assert_eq(GameData.get_record("ability.light_1"), original, "the record is back, nested keys included")
	assert_near(GameData.get_action("ability.light_1").power, original_power, 1e-9, "and the cached ActionDef")
	assert_eq(TestFixtures.pending_count(), 0, "nothing pending")


func test_the_after_each_list_restores_fixtures() -> void:
	var shipped := GameData.get_action("ability.heavy_1").power
	TestFixtures.record_override("ability.heavy_1", {"power": 1})
	assert_near(GameData.get_action("ability.heavy_1").power, 1.0, 1e-9, "patched")
	var problems: PackedStringArray = await ResetHooks.run(ResetHooks.AFTER_EACH, get_tree())
	assert_eq(problems.size(), 0, "restoring overrides is not a leftover failure")
	assert_near(GameData.get_action("ability.heavy_1").power, shipped, 1e-9, "the runner's AFTER_EACH restores it")


func test_runner_folders_and_discovery() -> void:
	assert_eq(TestRunner.suite_dirs(false), PackedStringArray(["res://tests/unit", "res://tests/integration"]),
		"default run: unit and integration")
	assert_eq(TestRunner.suite_dirs(true), PackedStringArray(["res://tests/unit", "res://tests/integration",
		"res://tests/slow"]), "--slow adds tests/slow")
	assert_eq(TestRunner.list_suites("res://tests/no_such_folder"), PackedStringArray(), "a missing folder is empty")
	var unit := TestRunner.list_suites("res://tests/unit")
	assert_true(unit.has("res://tests/unit/test_anchors.gd"), "suites are found")
	var sorted := unit.duplicate()
	sorted.sort()
	assert_eq(unit, sorted, "in sorted order")
	assert_false(TestRunner.suite_dirs(true).has("res://tests/support"), "support helpers are never run as suites")
