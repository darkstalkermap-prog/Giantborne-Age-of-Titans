extends TestSuite
## ErrorCounter (the error/warning logger of tool runs) and the autopilot result built from it.


func _provoke_script_error() -> void:
	var d := {}
	var _missing: Variant = d.no_such_key   # SCRIPT ERROR: aborts this function only


func test_counts_errors_and_warnings_separately() -> void:
	var c := ErrorCounter.new()
	OS.add_logger(c)
	push_error("p02 counter probe: pushed error")
	push_warning("p02 counter probe: pushed warning")
	var n := Node.new()
	var _none := n.get_node_or_null("no/such/child")   # quiet lookup: no error
	n.get_node("no/such/child")                        # engine error (node not found)
	n.free()
	_provoke_script_error()
	OS.remove_logger(c)
	var drained := TestRunner.take_logged_errors()   # provoked on purpose: not test failures
	assert_true(drained.size() >= 3, "the runner's own logger saw them too (%d)" % drained.size())
	assert_eq(c.error_count(), 3, "push_error, an engine error and a script error count as errors")
	assert_eq(c.warning_count(), 1, "push_warning counts as a warning, not an error")
	var t := c.take()
	assert_eq(int(t.errors), 3, "take() reports the errors")
	assert_eq(int(t.warnings), 1, "take() reports the warnings")
	var samples: Array = t.error_samples
	assert_eq(samples.size(), 3, "one sample per error")
	assert_true(str(samples[0]).contains("p02 counter probe: pushed error"), "samples keep the message")
	assert_true(str(samples[0]).contains("test_error_counter.gd"), "and point at the script that raised it (%s)" % samples[0])
	assert_true(str(t.warning_samples[0]).contains("pushed warning"), "warning samples are separate")
	assert_eq(c.error_count(), 0, "take() empties the error count")
	assert_eq(c.warning_count(), 0, "take() empties the warning count")
	assert_eq((c.take().error_samples as Array).size(), 0, "and the samples")


func test_samples_are_capped() -> void:
	var c := ErrorCounter.new()
	for i in ErrorCounter.MAX_SAMPLES + 5:   # the engine's callback, called directly (no log noise)
		c._log_error("probe", "probe.gd", i, "code", "probe %d" % i, false, Logger.ERROR_TYPE_ERROR, [])
	c._log_error("probe", "probe.gd", 0, "code", "a warning", false, Logger.ERROR_TYPE_WARNING, [])
	var t := c.take()
	assert_eq(int(t.errors), ErrorCounter.MAX_SAMPLES + 5, "every error is counted")
	assert_eq((t.error_samples as Array).size(), ErrorCounter.MAX_SAMPLES, "samples are capped")
	assert_eq(str(t.error_samples[0]), "probe 0  (probe.gd:0 in probe)", "sample format: message (file:line in function)")
	assert_eq(int(t.warnings), 1, "warnings counted apart")


func test_autopilot_result_carries_the_error_counts() -> void:
	var counted := {"errors": 7, "warnings": 2,
		"error_samples": ["e1", "e2", "e3", "e4", "e5", "e6", "e7"], "warning_samples": ["w1"]}
	var r := Autopilot.build_result({"ticks": 5, "attacks": 2}, 12.345, [16.0, 17.0, 18.0], ["a.png"], counted)
	assert_eq(int(r.errors), 7, "errors")
	assert_eq(int(r.warnings), 2, "warnings")
	assert_eq(r.error_samples, ["e1", "e2", "e3", "e4", "e5"], "the first five error samples")
	assert_eq(int(r.ticks), 5, "the run's stats are kept")
	assert_near(float(r.simulated_s), 12.35, 1e-6, "simulated seconds")
	assert_eq(int(r.frames), 3, "frames")
	assert_eq(Autopilot.exit_code(r), Autopilot.EXIT_ERRORS, "errors make the run fail (exit code 1)")
	var clean := Autopilot.build_result({"ticks": 1}, 1.0, [], [], {})
	assert_eq(int(clean.errors), 0, "no counter result = no errors")
	assert_eq(int(clean.warnings), 0, "and no warnings")
	assert_eq(clean.error_samples, [], "and no samples")
	assert_eq(Autopilot.exit_code(clean), 0, "a clean run exits with 0")
	assert_true(JSON.stringify(r).contains("\"errors\":7"), "the printed JSON carries \"errors\"")
