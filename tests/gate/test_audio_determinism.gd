extends TestSuite
## P19 (plan M6-M9 decision 1, §3.1 gate test): audio is presentation only. The seeded 120 s
## sandbox soak runs twice in its own process - with the audio engine (and --audio-stats, which
## prints one AUDIO_STATS line at exit, proving that it played) and with --no-audio - and the two
## AUTOPILOT_RESULT lines must be byte-identical: the engine never touches Sim.rng or the global
## RNG, never emits a gameplay signal, and the loading gate's extra paused frames run no
## simulation tick. The audio run also exits cleanly: no playback, stream or ObjectDB entry is left
## at exit. Gate tier: tools/check.sh --gate (about 30 s).

const SOAK_S := 120
const RESULT_PREFIX := "AUTOPILOT_RESULT "
const STATS_PREFIX := "AUDIO_STATS "


## Runs the soak in a child Godot process (this project, this user:// folder through the
## environment tools/gd.sh exported): {"code", "result", "stats", "output"}.
static func run_soak(audio_on: bool, seconds: int) -> Dictionary:
	var args := PackedStringArray(["--headless", "--path", ProjectSettings.globalize_path("res://"),
		"--fixed-fps", "60", "--", "--no-user-settings", "--autoplay=%d" % seconds])
	args.append("--audio-stats" if audio_on else "--no-audio")
	var output: Array = []
	var code := OS.execute(OS.get_executable_path(), args, output, true)
	var text := "\n".join(output)
	var out := {"code": code, "result": "", "stats": "", "output": text}
	for line in text.split("\n"):
		if line.begins_with(RESULT_PREFIX) and str(out.result) == "":
			out.result = line.strip_edges()
		elif line.begins_with(STATS_PREFIX):
			out.stats = line.substr(STATS_PREFIX.length()).strip_edges()
	return out


func test_the_seeded_soak_is_identical_with_and_without_audio() -> void:
	var off := run_soak(false, SOAK_S)
	var on := run_soak(true, SOAK_S)
	assert_eq(int(off.code), 0, "the silent soak exits cleanly")
	assert_eq(int(on.code), 0, "the soak with audio exits cleanly")
	assert_true(str(off.result) != "", "the silent soak reports")
	assert_true(str(on.result) != "", "the soak with audio reports")
	assert_true(str(off.result).contains("\"errors\":0"), "no errors without audio")
	assert_true(str(on.result).contains("\"errors\":0") and str(on.result).contains("\"warnings\":0"),
		"no errors or warnings with audio")
	assert_eq(str(on.result), str(off.result), "AUTOPILOT_RESULT byte-identical with and without audio")
	assert_eq(str(off.stats), "", "the silent soak played nothing (no stats line)")
	# Quitting while sounds play leaves nothing behind (Audio stops its players at exit and waits
	# for the mixing thread to drop their playbacks).
	for marker: String in ["instances leaked at exit", "still in use at exit"]:
		assert_false(str(on.output).contains(marker), "the audio run exits cleanly (no \"%s\")" % marker)
	var stats: Variant = JSON.parse_string(str(on.stats))
	assert_true(typeof(stats) == TYPE_DICTIONARY, "the audio run printed its stats: %s" % str(on.stats).left(200))
	if typeof(stats) == TYPE_DICTIONARY:
		assert_true(int(stats.get("played", 0)) > 100, "the audio run really played (%d cues)" % int(stats.get("played", 0)))
		assert_true(int(stats.get("registered", 0)) > 0, "its samples were registered behind the loading gate")
		assert_eq((stats.get("missing", {}) as Dictionary).size(), 0, "every request resolved: %s" % [stats.get("missing")])
