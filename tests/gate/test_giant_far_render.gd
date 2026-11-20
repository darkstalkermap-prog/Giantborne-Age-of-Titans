extends TestSuite
## The giant beyond 120 m, rendered (the second W33 look lane; plan M11 §2.12: "at most 4,000 primitives beyond 120 m"):
## tests/support/giant_far_probe.tscn in a child Godot under Xvfb at 1920x1080 (the Compatibility renderer, two
## llvmpipe threads). The Wanderer and the fullest look of the data at 121, 130, 151 and 200 m from the giant's middle
## at stage 1 in the creator's lens:
##   * the giant's own primitives at most 4,000 at each of those distances (10,952 and 15,616 before the far levels:
##     the hair's cards had no level the renderer took);
##   * at 121 m and 151 m his silhouette at the far levels is his silhouette at full detail: as many pixels within
##     SILHOUETTE_SHARE and at least MIN_OVERLAP of them in common (nothing - the beard, the belt, a helm - vanishes);
##   * at 60 m he is still drawn finer than at 121 m (the far levels switch on past the creator's framings).
## Without xvfb-run it is skipped with a note. The frames: user://m11_frames/W33look2/.

const PROBE := "res://tests/support/giant_far_probe.tscn"
const CHILD_TIMEOUT_S := 180
const PREFIX := "GIANT_FAR "
const OUT := "user://m11_frames/W33look2/"
const MAX_FAR_PRIMITIVES := 4000
const SILHOUETTE_SHARE := 0.12
const MIN_OVERLAP := 0.8


static func _have(tool: String) -> bool:
	var out: Array = []
	return OS.execute("sh", ["-c", "command -v %s" % tool], out, true) == 0


func test_beyond_120_m_the_giant_draws_at_most_4000_primitives_and_keeps_his_shape() -> void:
	if not _have("xvfb-run"):
		print("    test_giant_far_render: skipped - xvfb-run is not installed (the rendered check needs a display)")
		return
	DirAccess.make_dir_recursive_absolute(OUT)
	var args := PackedStringArray(["LP_NUM_THREADS=2", "timeout", str(CHILD_TIMEOUT_S), "xvfb-run", "-a", "-s",
		"-screen 0 1920x1080x24", OS.get_executable_path(), "--path", ProjectSettings.globalize_path("res://"),
		"--rendering-driver", "opengl3", "--resolution", "1920x1080", "--audio-driver", "Dummy", PROBE, "--",
		"--giant-tier=web", "--out=" + ProjectSettings.globalize_path(OUT)])
	var output: Array = []
	var code := OS.execute("env", args, output, true)
	var text := "\n".join(output)
	var line := ""
	var errors := PackedStringArray()
	for l in text.split("\n"):
		if l.begins_with(PREFIX):
			line = l.substr(PREFIX.length()).strip_edges()
		elif l.contains("SHADER ERROR") or (l.contains("ERROR") and l.contains("giant")):
			errors.append(l.strip_edges())
	assert_eq(code, 0, "the probe ran (exit %d)" % code)
	assert_eq(errors, PackedStringArray(), "every shader and part loads without an error")
	var r: Variant = JSON.parse_string(line)
	assert_true(typeof(r) == TYPE_DICTIONARY and not (r as Dictionary).has("error"), "it reported: %s" % (line if line != ""
		else text.right(800)))
	if typeof(r) != TYPE_DICTIONARY or (r as Dictionary).has("error"):
		return
	for name: String in ["wanderer", "fullest"]:
		var look: Dictionary = r.looks[name]
		for d: String in ["121", "130", "151", "200"]:
			var p := int(look.primitives[d])
			assert_true(p > 0 and p <= MAX_FAR_PRIMITIVES, "%s at %s m: %d primitives, at most %d" % [name, d, p,
				MAX_FAR_PRIMITIVES])
		assert_true(int(look.primitives["60"]) > int(look.primitives["121"]), "%s: finer at 60 m (%d) than at 121 m (%d)" % [
			name, int(look.primitives["60"]), int(look.primitives["121"])])
		for d: String in look.silhouette:
			var s: Dictionary = look.silhouette[d]
			var full := float(s.full_pixels)
			assert_true(full > 100.0, "%s at %s m: the giant is in the frame (%d px)" % [name, d, int(full)])
			assert_true(absf(float(s.pixels) - full) <= SILHOUETTE_SHARE * full, "%s at %s m: %d px at the far levels, %d at full detail" % [
				name, d, int(s.pixels), int(full)])
			assert_true(float(s.overlap) >= MIN_OVERLAP, "%s at %s m: %.2f of the silhouette in common, at least %.2f" % [name, d,
				float(s.overlap), MIN_OVERLAP])
	print("    test_giant_far_render: wanderer %s; fullest %s; on %s" % [str(r.looks.wanderer.primitives),
		str(r.looks.fullest.primitives), str(r.adapter)])
