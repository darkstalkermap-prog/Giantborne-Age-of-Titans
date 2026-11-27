extends TestSuite
## P62 (plan M11 §2.10, §2.12, §3.15 tests; slow, runs with --slow): the townsfolk, the riders and the rival giants
## rendered (tests/support/townsfolk_probe.gd --probe=town in a child process under Xvfb, the gl_compatibility
## renderer at the `low` preset; skipped with a note without xvfb-run):
##   * a rider adds three draw calls (the horse, the rider, the lance), a named character one;
##   * a town of fifteen people (seven villagers, the seven named talkers, Corvane) and two riders before a stage-1
##     giant: every skinned person in a clip with its arms hanging and its feet on the ground (no bind pose, no one
##     floating), the riders' standing hooves on the ground; the whole view within the settlements' 250 draw calls;
##   * the rival giant and Harrok drawn in their own looks.
## The settlements' own measurement (--probe=settlements: the six greens of the world and the Moot test level) is a
## minute's run on this machine: docs/systems/P62.md and docs/PERFORMANCE.md record it.

const PROBE := "res://tests/support/townsfolk_probe.gd"
const PREFIX := "TOWNSFOLK_PROBE "
const SETTLEMENT_CALLS := 250


func test_the_town_riders_and_giants_render_within_their_budgets() -> void:
	if not _have("xvfb-run"):
		print("    test_townsfolk_render: rendered check skipped - xvfb-run is not installed (it needs a display)")
		return
	var r := run_probe("town")
	assert_true(not r.is_empty(), "the probe reported")
	if r.is_empty():
		return
	assert_true(bool(r.rider_skinned), "the rider is skinned")
	assert_eq(int(r.rider_calls), 3, "a rider: the horse, the rider, the lance (%d calls)" % int(r.rider_calls))
	assert_eq(int(r.named_calls), 1, "a named character without gear: one call (%d)" % int(r.named_calls))
	assert_true(int(r.skinned) >= 15, "the town's people are skinned (%d)" % int(r.skinned))
	assert_eq(int(r.posed), int(r.skinned), "every one in a clip, arms hanging, feet on the ground (not: %s)" % [r.bad])
	assert_true(float(r.hoof_height_worst) < 0.03, "the riders' standing hooves on the ground (%.3f m)" % float(r.hoof_height_worst))
	assert_true(int(r.town_calls) <= SETTLEMENT_CALLS, "the town's view within %d calls (%d)" % [SETTLEMENT_CALLS, int(r.town_calls)])
	assert_eq(str(r.rival_look), "appearance_preset.npc_rival_giant", "the rival giant's look")
	assert_eq(str(r.harrok_look), "appearance_preset.npc_harrok", "Harrok's look")
	assert_true(int(r.rival_calls) > 5 and int(r.harrok_calls) > 5, "the giants drawn (%d, %d calls)" % [int(r.rival_calls),
		int(r.harrok_calls)])
	print("    test_townsfolk_render: a rider %d calls, a named character %d; the town %d calls, %d skinned; the rival giant %d, Harrok %d; the people's CPU %.2f ms a frame; %s" % [
		int(r.rider_calls), int(r.named_calls), int(r.town_calls), int(r.skinned), int(r.rival_calls), int(r.harrok_calls),
		float(r.people_cpu_ms), str(r.get("adapter", "?"))])


## The probe's arguments (for xvfb-run) in `mode`.
static func probe_args(mode: String) -> PackedStringArray:
	return PackedStringArray(["-a", "-s", "-screen 0 640x480x24", OS.get_executable_path(),
		"--path", ProjectSettings.globalize_path("res://"), "--rendering-driver", "opengl3", "--resolution", "640x480",
		"--audio-driver", "Dummy", "--fixed-fps", "60", "-s", PROBE, "--", "--no-user-settings", "--probe=" + mode])


## Dgate: the runner starts this suite's child ahead (ChildRuns), while the suites before it run.
static func prefetch_children() -> Array:
	return [["xvfb-run", probe_args("town")]] if _have("xvfb-run") else []


## townsfolk_probe.gd's result in `mode` ({} when it did not report).
static func run_probe(mode: String) -> Dictionary:
	var args := probe_args(mode)
	var output: Array = []
	ChildRuns.execute("xvfb-run", args, output)   # (Dgate: prefetched by the runner)
	for l in "\n".join(output).split("\n"):
		if l.begins_with(PREFIX):
			var parsed: Variant = JSON.parse_string(l.substr(PREFIX.length()).strip_edges())
			return parsed if typeof(parsed) == TYPE_DICTIONARY else {}
	return {}


static func _have(tool: String) -> bool:
	var out: Array = []
	return OS.execute("sh", ["-c", "command -v %s" % tool], out, true) == 0
