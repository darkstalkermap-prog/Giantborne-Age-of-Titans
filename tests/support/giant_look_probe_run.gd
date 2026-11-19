extends RefCounted
## One run of tests/support/giant_look_probe.tscn shared by the look's rendered suites (P51): the test runner runs
## every suite in one process, so tests/slow/test_skin_tone_render.gd and tests/slow/test_hair_render.gd read the
## same child's report instead of drawing the giant twice. result() runs the child (Xvfb, the Compatibility
## renderer, two llvmpipe threads, a 320x240 window, `--giant-tier=` the tier asked) the first time a tier is asked
## for and keeps its report: {"report": the GIANT_LOOK dictionary or {}, "errors": shader and script errors,
## "code": the child's exit, "text": the tail of its output, "skipped": a reason or ""}.

const PROBE := "res://tests/support/giant_look_probe.tscn"
const PREFIX := "GIANT_LOOK "
const CHILD_TIMEOUT_S := 300

static var _runs := {}


static func _have(tool: String) -> bool:
	var out: Array = []
	return OS.execute("sh", ["-c", "command -v %s" % tool], out, true) == 0


## The report of the probe on `tier` ("web" or "hi"), with `only` (the probe's --only=, "" for everything).
static func result(tier := "web", only := "") -> Dictionary:
	var key := tier + "|" + only
	if _runs.has(key):
		return _runs[key]
	var out := {"report": {}, "errors": PackedStringArray(), "code": -1, "text": "", "skipped": ""}
	if not _have("xvfb-run"):
		out.skipped = "xvfb-run is not installed (the rendered check needs a display)"
		_runs[key] = out
		return out
	var args := PackedStringArray(["LP_NUM_THREADS=2", "timeout", str(CHILD_TIMEOUT_S), "xvfb-run", "-a", "-s",
		"-screen 0 1280x720x24", OS.get_executable_path(), "--path", ProjectSettings.globalize_path("res://"),
		"--rendering-driver", "opengl3", "--resolution", "320x240", "--audio-driver", "Dummy", PROBE, "--",
		"--giant-tier=" + tier])
	if only != "":
		args.append("--only=" + only)
	var output: Array = []
	out.code = OS.execute("env", args, output, true)
	var text := "\n".join(output)
	for l in text.split("\n"):
		if l.begins_with(PREFIX):
			var r: Variant = JSON.parse_string(l.substr(PREFIX.length()).strip_edges())
			if typeof(r) == TYPE_DICTIONARY:
				out.report = r
		elif l.contains("SHADER ERROR") or l.begins_with("SCRIPT ERROR") or (l.begins_with("ERROR") and l.contains("giant")):
			(out.errors as PackedStringArray).append(l.strip_edges())
	out.text = text.right(800)
	_runs[key] = out
	return out
