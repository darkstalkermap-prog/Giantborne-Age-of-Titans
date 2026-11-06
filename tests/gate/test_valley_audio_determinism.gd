extends TestSuite
## M6 gate (plan M6-M9 decision 1: audio has no effect on the simulation): the Valley half of P19's
## soak test. Seeded Valley bot runs play twice, each in its own process - with the audio engine (and
## --audio-stats, proving it played) and with --no-audio - and their AUTOPILOT_RESULT lines must be
## identical but for the PerfProbe's timings ("perf") and the engine's own node and memory samples
## (valley_bot "nodes" and "load_nodes": the audio engine's players are nodes too).
##   * New Game: the intimidate novice, seed 3, for RUN_S simulated seconds (the Hollow, its
##     tutorial, the wolves). Before the gate, the bot bound and planned in the loading gate's extra
##     paused frames with audio on and acted one tick earlier: every seeded run diverged from its
##     first objective (quest.main:leave_hollow started at tick 1 with audio, 2 without).
##   * Continue from the pre-crown save (a stage-3 giant at the Barrow's waystone; the wardens' wolves
##     and the crown): a load next to an encounter. Before the gate, the navigation map synced on a
##     worker thread, ready at the first tick only when the audio gate had held long enough - a silent
##     run's first ticks steered without it, and the runs parted after every load and link change.
## Gate tier: tools/check.sh --gate (about three minutes).

const RESULT_PREFIX := "AUTOPILOT_RESULT "
const STATS_PREFIX := "AUDIO_STATS "
const RUN_S := 150
const CONTINUE_S := 120
const FIXTURE := "res://tests/fixtures/saves/v1_pre_crown.json"
const SAVE_ROOT := "user://gate_valley_determinism"


## Runs the Valley bot in a child Godot process (this project, this user:// folder through the
## environment tools/gd.sh exported): {"code", "result", "stats", "output"}.
static func run_valley(audio_on: bool, args: PackedStringArray) -> Dictionary:
	var cmd := PackedStringArray(["--headless", "--path", ProjectSettings.globalize_path("res://"),
		"--fixed-fps", "60", "--", "--no-user-settings", "--scenario=valley"])
	cmd.append_array(args)
	cmd.append("--audio-stats" if audio_on else "--no-audio")
	var output: Array = []
	var code := OS.execute(OS.get_executable_path(), cmd, output, true)
	var text := "\n".join(output)
	var out := {"code": code, "result": "", "stats": "", "output": text}
	for line in text.split("\n"):
		if line.begins_with(RESULT_PREFIX) and str(out.result) == "":
			out.result = line.substr(RESULT_PREFIX.length()).strip_edges()
		elif line.begins_with(STATS_PREFIX):
			out.stats = line.substr(STATS_PREFIX.length()).strip_edges()
	return out


## A result without what may differ with the engine on: the PerfProbe's block and the node and memory
## samples. "" when it does not parse.
static func comparable(result: String) -> String:
	var parsed: Variant = JSON.parse_string(result)
	if typeof(parsed) != TYPE_DICTIONARY:
		return ""
	var r: Dictionary = parsed
	r.erase("perf")
	var vb: Variant = r.get("valley_bot")
	if typeof(vb) == TYPE_DICTIONARY:
		(vb as Dictionary).erase("nodes")
		(vb as Dictionary).erase("load_nodes")
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


func _compare(label: String, args_for: Callable) -> void:
	var on := run_valley(true, args_for.call("on"))
	var off := run_valley(false, args_for.call("off"))
	for pair: Array in [[on, "with audio"], [off, "without audio"]]:
		var r: Dictionary = pair[0]
		assert_true(str(r.result) != "", "%s %s reports (exit %d): %s" % [label, pair[1], int(r.code),
			str(r.output).right(300)])
		assert_true(str(r.result).contains("\"errors\":0"), "%s %s: no errors" % [label, pair[1]])
	var a := comparable(str(on.result))
	var b := comparable(str(off.result))
	assert_true(a != "" and b != "", "%s: both results parse" % label)
	assert_true(a == b, "%s: the runs are identical with and without audio%s" % [label,
		"" if a == b else (": %s" % [first_differences(JSON.parse_string(a), JSON.parse_string(b))])])
	var stats: Variant = JSON.parse_string(str(on.stats))
	assert_true(typeof(stats) == TYPE_DICTIONARY and int((stats as Dictionary).get("played", 0)) > 0,
		"%s: the audio run really played (%s)" % [label, str(on.stats).left(120)])
	assert_eq(str(off.stats), "", "%s: the silent run played nothing" % label)
	var vb: Variant = (JSON.parse_string(a) as Dictionary).get("valley_bot") if a != "" else null
	if typeof(vb) == TYPE_DICTIONARY:
		print("    %s: %.1f s simulated, %d objectives, %d deaths, %s with and without audio" % [label,
			float((vb as Dictionary).get("simulated_s", 0.0)), ((vb as Dictionary).get("objectives", []) as Array).size(),
			((vb as Dictionary).get("deaths", []) as Array).size(), "identical" if a == b else "DIFFERENT"])


func test_a_seeded_new_game_plays_the_same_with_and_without_audio() -> void:
	_compare("New Game", func(mode: String) -> PackedStringArray:
		return PackedStringArray(["--save-dir=%s/new_%s" % [SAVE_ROOT, mode], "--mode=valley", "--new-game",
			"--autoplay=%d" % RUN_S, "--bot-village=intimidate", "--bot-skill=novice", "--bot-seed=3"]))


func test_a_continue_next_to_an_encounter_plays_the_same_with_and_without_audio() -> void:
	var fixture := FileAccess.get_file_as_string(FIXTURE)
	assert_true(fixture != "", "the pre-crown save fixture reads")
	for mode: String in ["on", "off"]:
		var dir := "%s/continue_%s" % [SAVE_ROOT, mode]
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
		for f: String in ["valley_1.json", "valley_1.json.bak"]:
			DirAccess.remove_absolute(ProjectSettings.globalize_path(dir.path_join(f)))
		var file := FileAccess.open(dir.path_join("valley_1.json"), FileAccess.WRITE)
		file.store_string(fixture)
		file.close()
	_compare("Continue at the Barrow", func(mode: String) -> PackedStringArray:
		return PackedStringArray(["--save-dir=%s/continue_%s" % [SAVE_ROOT, mode], "--mode=valley", "--continue",
			"--autoplay=%d" % CONTINUE_S, "--bot-village=intimidate", "--bot-skill=novice", "--bot-seed=1"]))
