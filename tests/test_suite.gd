class_name TestSuite
extends Node
## Minimal test base (no plugins). Methods named test_* run in order; they may await.
## Integration suites can spawn scenes under themselves and step real physics ticks.

var failures: Array[String] = []
var current_test := ""
var checks := 0


func before_each() -> void:
	pass


func after_each() -> void:
	pass


func fail(message: String) -> void:
	failures.append("%s: %s" % [current_test, message])


func assert_true(cond: bool, message: String) -> void:
	checks += 1
	if not cond:
		fail(message)


func assert_false(cond: bool, message: String) -> void:
	assert_true(not cond, message)


func assert_eq(actual: Variant, expected: Variant, message: String) -> void:
	checks += 1
	if typeof(actual) != typeof(expected) and not (_num(actual) and _num(expected)):
		fail("%s (expected %s [%s], got %s [%s])" % [message, expected, type_string(typeof(expected)),
			actual, type_string(typeof(actual))])
	elif actual != expected:
		fail("%s (expected %s, got %s)" % [message, expected, actual])


func assert_near(actual: float, expected: float, tolerance: float, message: String) -> void:
	checks += 1
	if absf(actual - expected) > tolerance:
		fail("%s (expected %s +/- %s, got %s)" % [message, expected, tolerance, actual])


func _num(v: Variant) -> bool:
	return typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT


## Waits until Sim has advanced exactly n more ticks. Runs with --fixed-fps 60, so each frame
## performs one physics tick; process_frame fires after that frame's tick has completed.
func step_ticks(n: int) -> void:
	var target := Sim.tick + n
	var guard := 0
	while Sim.tick < target:
		await get_tree().process_frame
		guard += 1
		if guard > n * 4 + 20:
			fail("step_ticks timed out waiting for %d ticks" % n)
			return


## Builds an ActionDef from the real data, so unit tests exercise the shipped numbers.
func action(id: String) -> ActionDef:
	var a := GameData.get_action(id)
	if a == null:
		fail("missing action %s" % id)
	return a
