extends TestSuite
## P43 (plan M10 decision 5, §3.3 "test_giant_determinism"): the skinned giant is presentation only. Each
## run is its own child Godot process (this project, this user:// folder through the environment
## tools/gd.sh exported), with 0 errors, 0 warnings and nothing left behind at exit:
##   * the seeded 120 s sandbox soak three times - --no-skin; --skin --skin-stats with the Wanderer's look;
##     --skin --skin-stats with the Ash Raider's - prints byte-identical AUTOPILOT_RESULT lines, while the
##     two SKIN_STATS lines show the layers on, more than 1,000 posed frames and modifier runs, the brain's
##     footfalls, and different looks and meshes shown (the positive control: the skin and the look ran);
##   * P50: those SKIN_STATS also show the flinches played (above 0) and the secondary motion's frames: above
##     1,000 with the Wanderer's long hair and full beard, none with the Ash Raider's, whose look hangs on no chain;
##   * a seeded Valley bot run (intimidate, novice, seed 3, 150 s: it grabs and throws) with --skin
##     --skin-stats and with --no-skin prints the same result but for the PerfProbe's timings and the
##     engine's node and memory samples, with grabs and throws in its metrics and held-visual writes in
##     SKIN_STATS (the skin's one write into another actor, exercised).
## Gate tier: tools/check.sh --gate (about three minutes).

const SOAK_S := 120
const VALLEY_S := 150
const RESULT_PREFIX := "AUTOPILOT_RESULT "
const SKIN_PREFIX := "SKIN_STATS "
const SAVE_ROOT := "user://gate_giant_determinism"
const LOOKS := ["appearance_preset.wanderer", "appearance_preset.ash_raider"]
const EXIT_MARKERS := ["instances leaked at exit", "still in use at exit", "RID allocations", "Leaked instance"]


## One child run: {"code", "result", "skin", "output"} (the AUTOPILOT_RESULT and SKIN_STATS lines' JSON).
static func run_child(args: PackedStringArray) -> Dictionary:
	var cmd := PackedStringArray(["--headless", "--path", ProjectSettings.globalize_path("res://"),
		"--fixed-fps", "60", "--", "--no-user-settings", "--no-audio"])
	cmd.append_array(args)
	var output: Array = []
	var code := OS.execute(OS.get_executable_path(), cmd, output, true)
	var text := "\n".join(output)
	var out := {"code": code, "result": "", "skin": "", "output": text}
	for line in text.split("\n"):
		if line.begins_with(RESULT_PREFIX) and str(out.result) == "":
			out.result = line.substr(RESULT_PREFIX.length()).strip_edges()
		elif line.begins_with(SKIN_PREFIX):
			out.skin = line.substr(SKIN_PREFIX.length()).strip_edges()
	return out


## A Valley result without what may differ with the skin on: the PerfProbe's block and the node and
## memory samples (the skinned layers add nodes). "" when it does not parse.
static func comparable(result: String) -> String:
	var parsed: Variant = JSON.parse_string(result)
	if typeof(parsed) != TYPE_DICTIONARY:
		return ""
	var r: Dictionary = parsed
	r.erase("perf")
	var vb: Variant = r.get("valley_bot")
	if typeof(vb) == TYPE_DICTIONARY:
		for key in ["nodes", "load_nodes"]:
			(vb as Dictionary).erase(key)
	return JSON.stringify(r, "", true)


## The first differing key paths of two parsed results (for the failure message).
static func first_differences(a: Variant, b: Variant, path := "", out: Array = []) -> Array:
	if out.size() >= 6:
		return out
	if typeof(a) != typeof(b):
		out.append("%s: %s / %s" % [path, str(a).left(60), str(b).left(60)])
	elif typeof(a) == TYPE_DICTIONARY:
		for k: Variant in a:
			if not (b as Dictionary).has(k):
				out.append("%s/%s: missing" % [path, k])
			else:
				first_differences(a[k], b[k], "%s/%s" % [path, k], out)
	elif typeof(a) == TYPE_ARRAY:
		if (a as Array).size() != (b as Array).size():
			out.append("%s: %d / %d entries" % [path, (a as Array).size(), (b as Array).size()])
		else:
			for i in (a as Array).size():
				first_differences(a[i], b[i], "%s[%d]" % [path, i], out)
	elif a != b:
		out.append("%s: %s / %s" % [path, str(a).left(60), str(b).left(60)])
	return out


func _clean(label: String, r: Dictionary) -> void:
	assert_true(str(r.result) != "", "%s reports (exit %d): %s" % [label, int(r.code), str(r.output).right(400)])
	assert_true(str(r.result).contains("\"errors\":0") and str(r.result).contains("\"warnings\":0"),
		"%s: no errors or warnings (%s)" % [label, str(r.result).left(200)])
	for marker: String in EXIT_MARKERS:
		assert_false(str(r.output).contains(marker), "%s exits cleanly (no \"%s\")" % [label, marker])


func _skin(label: String, r: Dictionary) -> Dictionary:
	var parsed: Variant = JSON.parse_string(str(r.skin))
	assert_true(typeof(parsed) == TYPE_DICTIONARY, "%s printed SKIN_STATS: %s" % [label, str(r.skin).left(160)])
	return parsed if typeof(parsed) == TYPE_DICTIONARY else {}


func test_the_soak_is_identical_with_the_skin_off_and_with_two_looks() -> void:
	var off := run_child(PackedStringArray(["--autoplay=%d" % SOAK_S, "--no-skin"]))
	_clean("the soak without the skin", off)
	assert_eq(str(off.skin), "", "without --skin-stats no SKIN_STATS line")
	var stats: Array[Dictionary] = []
	for look: String in LOOKS:
		var on := run_child(PackedStringArray(["--autoplay=%d" % SOAK_S, "--skin", "--skin-stats", "--appearance=" + look]))
		var label := "the soak with the skin and %s" % look
		_clean(label, on)
		assert_eq(str(on.result), str(off.result), "%s: AUTOPILOT_RESULT byte-identical to the run without the skin" % label)
		var s := _skin(label, on)
		stats.append(s)
		assert_true(bool(s.get("layers", false)), "%s: the layers ran" % label)
		assert_true(int(s.get("posed_frames", 0)) > 1000 and int(s.get("modifier_runs", 0)) > 1000,
			"%s: posed frames and modifier runs (%s, %s)" % [label, s.get("posed_frames"), s.get("modifier_runs")])
		assert_true(int(s.get("rig_footfalls", 0)) > 0, "%s: the brain's footfalls (%s)" % [label, s.get("rig_footfalls")])
		assert_eq(str(s.get("look", "")), look, "%s: the look named" % label)
		# P50 (plan M11 §3.3): the secondary motion and the flinches ran, and nothing played differently for it
		if (s.get("chains", []) as Array).is_empty():
			assert_eq(int(s.get("secondary_frames", -1)), 0, "%s: a look with no long hair, beard or cape runs no springs" % label)
		else:
			assert_true(int(s.get("secondary_frames", 0)) > 1000, "%s: secondary motion frames (%s)" % [label, s.get("secondary_frames")])
		assert_true(int(s.get("flinches", 0)) > 0, "%s: the giant flinched (%s)" % [label, s.get("flinches")])
	if stats.size() == 2:
		print("    test_giant_determinism: the soak, %s posed frames and %s footfalls with the skin; looks %s / %s" % [
			stats[0].get("posed_frames"), stats[0].get("rig_footfalls"), stats[0].get("look"), stats[1].get("look")])
		assert_true(stats[0].get("look") != stats[1].get("look"), "the two runs had different looks")
		assert_true(stats[0].get("shown_meshes") != stats[1].get("shown_meshes"), "and showed different meshes (%s / %s)" % [
			stats[0].get("shown_meshes"), stats[1].get("shown_meshes")])
		assert_true(int(stats[0].get("secondary_frames", 0)) + int(stats[1].get("secondary_frames", 0)) > 1000,
			"the secondary motion ran in one of them")


func test_a_seeded_valley_run_that_grabs_plays_the_same_with_and_without_the_skin() -> void:
	var runs := {}
	for mode: String in ["skin", "noskin"]:
		var args := PackedStringArray(["--scenario=valley", "--save-dir=%s/%s" % [SAVE_ROOT, mode], "--mode=valley", "--new-game",
			"--autoplay=%d" % VALLEY_S, "--bot-village=intimidate", "--bot-skill=novice", "--bot-seed=3"])
		args.append_array(["--skin", "--skin-stats"] if mode == "skin" else ["--no-skin"])
		runs[mode] = run_child(args)
		_clean("the Valley run (%s)" % mode, runs[mode])
	var a := comparable(str(runs.skin.result))
	var b := comparable(str(runs.noskin.result))
	assert_true(a != "" and b != "", "both results parse")
	assert_true(a == b, "the Valley run is identical with and without the skin%s" % ["" if a == b else
		(": %s" % [first_differences(JSON.parse_string(a), JSON.parse_string(b))])])
	var vb: Dictionary = (JSON.parse_string(a) as Dictionary).get("valley_bot", {}) if a != "" else {}
	var actions: Dictionary = vb.get("actions", {})
	assert_true(int(actions.get("grabs", 0)) > 0 and int(actions.get("throws", 0)) > 0,
		"the run grabbed and threw (%s grabs, %s throws)" % [actions.get("grabs"), actions.get("throws")])
	var s := _skin("the Valley run with the skin", runs.skin)
	assert_true(bool(s.get("layers", false)) and int(s.get("posed_frames", 0)) > 1000, "the skin ran (%s)" % str(runs.skin.skin).left(160))
	assert_true(int(s.get("held_visual_writes", 0)) > 0, "the held body's visual was moved (%s writes)" % s.get("held_visual_writes"))
	print("    test_giant_determinism: the Valley run, %s grabs, %s throws, %s held-visual writes, %s posed frames; %s" % [
		actions.get("grabs"), actions.get("throws"), s.get("held_visual_writes"), s.get("posed_frames"),
		"identical" if a == b else "DIFFERENT"])
	assert_eq(str(runs.noskin.skin), "", "the run without the skin printed no SKIN_STATS")
