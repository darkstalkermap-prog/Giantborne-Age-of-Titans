extends TestSuite
## The build sliders, rendered (P53; plan M11 §2.4, §3.6, decision 7; §1.7 rule 6): tests/support/build_render_probe.tscn
## in a child Godot under Xvfb at 320x240 (the Compatibility renderer, two llvmpipe threads). The real model from
## behind at the stage-1 rear Game view's height, in the Wanderer's look and the warrior's, at build (0, 0), (1, 1)
## and (-1, -1): the push changes the rear silhouette - more of it at +1, less at -1, the clothed body as much as the
## bare one - and moves no joint (every bone's pose and the index's landmarks as they were); the shadow proxy takes
## the push's material once the build leaves zero, and the shadow on the ground grows and shrinks with the body;
## GiantLook.validate() stays empty. Without xvfb-run it is skipped
## with a note. Frames: user://m11_frames/P53/build_*.png.

const PROBE := "res://tests/support/build_render_probe.tscn"
const CHILD_TIMEOUT_S := 180
const PREFIX := "BUILD_RENDER "
## A slider at its end changes at least this share of the 320x240 rear frame (the giant fills about a fifth of it;
## the push is up to 9.9 cm at stage 1).
const MIN_CHANGED := 0.004
## Plan M11 §0.3: no joint moves by more than 1 mm.
const MAX_BONE_M := 0.001


static func _have(tool: String) -> bool:
	var out: Array = []
	return OS.execute("sh", ["-c", "command -v %s" % tool], out, true) == 0


## The child Godot's arguments (for env).
static func _child_args() -> PackedStringArray:
	return PackedStringArray(["LP_NUM_THREADS=2", "timeout", str(CHILD_TIMEOUT_S), "xvfb-run", "-a", "-s",
		"-screen 0 1280x720x24", OS.get_executable_path(), "--path", ProjectSettings.globalize_path("res://"),
		"--rendering-driver", "opengl3", "--resolution", "320x240", "--audio-driver", "Dummy", PROBE, "--",
		"--giant-tier=web"])


## Dgate: the runner starts this suite's child ahead (ChildRuns), while the suites before it run.
static func prefetch_children() -> Array:
	return [["env", _child_args()]] if _have("xvfb-run") else []


func test_the_build_changes_the_rear_silhouette_and_moves_no_joint() -> void:
	if not _have("xvfb-run"):
		print("    test_build_render: skipped - xvfb-run is not installed (the rendered check needs a display)")
		return
	var args := _child_args()
	var output: Array = []
	var code := ChildRuns.execute("env", args, output)   # (Dgate: prefetched by the runner)
	var text := "\n".join(output)
	var line := ""
	var errors := PackedStringArray()
	for l in text.split("\n"):
		if l.begins_with(PREFIX):
			line = l.substr(PREFIX.length()).strip_edges()
		elif l.contains("SHADER ERROR") or (l.contains("ERROR") and l.contains("giant")):
			errors.append(l.strip_edges())
	assert_eq(code, 0, "the probe ran (exit %d)" % code)
	assert_eq(errors, PackedStringArray(), "every shader compiles without an error")
	var r: Variant = JSON.parse_string(line)
	assert_true(typeof(r) == TYPE_DICTIONARY and not (r as Dictionary).has("error"), "it reported: %s" % (line if line != ""
		else text.right(800)))
	if typeof(r) != TYPE_DICTIONARY or (r as Dictionary).has("error"):
		return
	assert_eq(r.validate, [], "GiantLook.validate() is empty at every build")
	assert_true(float(r.build_max_m) > 0.05, "the index carries build_max_m (%.4f m)" % float(r.build_max_m))
	assert_true(float(r.bones_moved_m) <= MAX_BONE_M, "no joint moves (%.6f m at most)" % float(r.bones_moved_m))
	assert_true(bool(r.landmarks_same), "the landmarks are the index's, unchanged")
	assert_true(bool(r.proxy_material), "the shadow proxy pushes with the build")
	var f: Dictionary = r.frames
	for look_name: String in ["wanderer", "warrior"]:
		var zero := float(f["%s_zero" % look_name].lit)
		assert_true(zero > 0.02, "%s: the giant is in the rear frame (%.3f)" % [look_name, zero])
		assert_true(float(f["%s_plus" % look_name].lit) > zero, "%s: the silhouette grows at +1 (%.4f > %.4f)" % [look_name,
			float(f["%s_plus" % look_name].lit), zero])
		assert_true(float(f["%s_minus" % look_name].lit) < zero, "%s: and shrinks at -1 (%.4f < %.4f)" % [look_name,
			float(f["%s_minus" % look_name].lit), zero])
		var shadow := [float(f["%s_minus" % look_name].shadow), float(f["%s_zero" % look_name].shadow),
			float(f["%s_plus" % look_name].shadow)]
		assert_true(shadow[0] < shadow[1] and shadow[1] < shadow[2], "%s: the shadow follows the build (%s)" % [look_name,
			shadow])
		for b: String in ["plus", "minus"]:
			var changed := float(r.changed["%s_%s" % [look_name, b]])
			assert_true(changed >= MIN_CHANGED, "%s at %s: %.4f of the rear frame changed" % [look_name, b, changed])
	var lines := PackedStringArray()
	for k: Variant in f:
		lines.append("%s %.4f (shadow %.4f)" % [k, float(f[k].lit), float(f[k].get("shadow", 0.0))])
	print("    test_build_render: %s; changed %s; bones moved %.6f m; on %s" % [", ".join(lines), str(r.changed),
		float(r.bones_moved_m), str(r.adapter)])
