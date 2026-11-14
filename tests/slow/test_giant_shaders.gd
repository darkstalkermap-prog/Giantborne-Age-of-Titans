extends TestSuite
## The giant's shaders, rendered (P42; plan M10 §1.7 rule 6, §2.8, §2.13): tests/support/giant_shader_probe.tscn
## in a child Godot under Xvfb with the Compatibility renderer (opengl3), an explicit --giant-tier, two
## llvmpipe threads, 320x240, the render loop off between captured frames. Every giant shader compiles
## without an error; one frame per material category (skin, hair, eye, cloth) is not blank - on the real
## model when scenes/player/giant_model.tscn exists, else on a stand-in of spheres and a card; GiantLook's
## validate() is empty there; on the real model the long hair and full beard are framed as the creator's
## Face and Hair views (§4.2's hair bar); the cost of a frame at 320x240 is recorded for P43's caps. The
## frames are saved to user://m10_frames/. Without xvfb-run it is skipped with a note.

const PROBE := "res://tests/support/giant_shader_probe.tscn"
## The child never runs longer than this (seconds; the probe has its own watchdog too).
const CHILD_TIMEOUT_S := 180
const PREFIX := "GIANT_SHADERS "
const KINDS := ["skin", "hair", "eye", "cloth"]
## A frame is not blank when at least this share of its pixels is off the clear colour.
const MIN_LIT := 0.004


static func _have(tool: String) -> bool:
	var out: Array = []
	return OS.execute("sh", ["-c", "command -v %s" % tool], out, true) == 0


func test_the_giant_shaders_compile_and_draw() -> void:
	if not _have("xvfb-run"):
		print("    test_giant_shaders: skipped - xvfb-run is not installed (the rendered check needs a display)")
		return
	var args := PackedStringArray(["LP_NUM_THREADS=2", "timeout", str(CHILD_TIMEOUT_S), "xvfb-run", "-a", "-s",
		"-screen 0 1280x720x24", OS.get_executable_path(), "--path", ProjectSettings.globalize_path("res://"),
		"--rendering-driver", "opengl3", "--resolution", "320x240", "--audio-driver", "Dummy", PROBE, "--",
		"--giant-tier=web"])
	var output: Array = []
	var code := OS.execute("env", args, output, true)
	var text := "\n".join(output)
	var line := ""
	var errors := PackedStringArray()
	for l in text.split("\n"):
		if l.begins_with(PREFIX):
			line = l.substr(PREFIX.length()).strip_edges()
		elif l.contains("SHADER ERROR") or (l.contains("ERROR") and l.contains("giant_")):
			errors.append(l.strip_edges())
	assert_eq(code, 0, "the probe ran (exit %d)" % code)
	assert_eq(errors, PackedStringArray(), "every giant shader compiles without an error")
	var r: Variant = JSON.parse_string(line)
	assert_true(typeof(r) == TYPE_DICTIONARY, "it reported: %s" % (line if line != "" else text.right(800)))
	if typeof(r) != TYPE_DICTIONARY:
		return
	assert_eq(r.validate, [], "GiantLook.validate() is empty on the %s" % ("model" if bool(r.model) else "stand-in"))
	for kind: String in KINDS:
		var f: Dictionary = (r.frames as Dictionary).get(kind, {})
		assert_true(float(f.get("lit", 0.0)) >= MIN_LIT, "the %s frame is not blank (%.1f %% of its pixels drawn)" % [kind,
			100.0 * float(f.get("lit", 0.0))])
	if bool(r.model):
		for frame: String in ["face_long_hair_full_beard", "hair_back"]:
			var f: Dictionary = (r.frames as Dictionary).get(frame, {})
			assert_true(float(f.get("lit", 0.0)) >= MIN_LIT, "the %s frame is drawn (%s)" % [frame, f.get("path", "")])
	assert_true(float(r.frame_ms) > 0.0, "a frame's cost is measured")
	var lits := PackedStringArray()
	for kind: Variant in r.frames:
		lits.append("%s %.0f %%" % [kind, 100.0 * float(r.frames[kind].get("lit", 0.0))])
	print("    test_giant_shaders: %s, tier %s, %.1f ms a frame at 320x240 on %s; frames drawn: %s" % [
		"the real model" if bool(r.model) else "the stand-in (no giant_model.tscn yet)", str(r.tier), float(r.frame_ms),
		str(r.adapter), ", ".join(lits)])
