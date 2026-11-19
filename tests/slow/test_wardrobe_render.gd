extends TestSuite
## The wardrobe, rendered (P54; plan M11 §2.6, §2.12, §3.7; §1.7 rule 6): tests/support/wardrobe_render_probe.tscn in
## a child Godot under Xvfb at 320x240 (the Compatibility renderer, two llvmpipe threads). The fullest slot look (the
## huscarl's outfit - a garment in each of the ten slots - with a torc, an arm ring and a trophy, long hair and a full
## beard) from the front and from behind in the world's light:
##   * no z-fighting: each garment and accessory drawn in a flat colour of its own, twice with the camera moved by
##     half a millimetre, flips the colour of at most MAX_FLICKER of the giant's interior pixels (two surfaces at one
##     depth flip where the slots' shells would share a surface; a moved silhouette changes edge pixels only);
##   * the slots show: from the front and behind together every garment of the look is seen;
##   * at most 24 meshes drawn (plan §2.12 counts a draw call a mesh: the body's three, the eyes, the hair, the beard,
##     two bead sets, up to twelve garment meshes, three accessories) and the giant's own primitives at most 70,000;
##     the renderer's own count of the main pass's draw calls is reported and kept at most MAX_DRAWS: it adds the hair's
##     and the beard's depth pre-passes (alpha-scissored cards draw twice) to the meshes;
##   * GiantLook.validate() empty.
## Without xvfb-run it is skipped with a note. The flat-colour frames: user://m11_frames/P54/.

const PROBE := "res://tests/support/wardrobe_render_probe.tscn"
const CHILD_TIMEOUT_S := 120
const PREFIX := "WARDROBE_RENDER "
const OUT := "user://m11_frames/P54/"
const MAX_FLICKER := 0.002
const MAX_MESHES := 24
const MAX_DRAWS := 28
const MAX_PRIMITIVES := 70000


static func _have(tool: String) -> bool:
	var out: Array = []
	return OS.execute("sh", ["-c", "command -v %s" % tool], out, true) == 0


func test_the_fullest_slot_look_draws_without_z_fighting_within_its_budget() -> void:
	if not _have("xvfb-run"):
		print("    test_wardrobe_render: skipped - xvfb-run is not installed (the rendered check needs a display)")
		return
	DirAccess.make_dir_recursive_absolute(OUT)
	var args := PackedStringArray(["LP_NUM_THREADS=2", "timeout", str(CHILD_TIMEOUT_S), "xvfb-run", "-a", "-s",
		"-screen 0 1280x720x24", OS.get_executable_path(), "--path", ProjectSettings.globalize_path("res://"),
		"--rendering-driver", "opengl3", "--resolution", "320x240", "--audio-driver", "Dummy", PROBE, "--",
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
	assert_eq(r.validate, [], "GiantLook.validate() is empty")
	assert_true(int(r.meshes) <= MAX_MESHES, "%d meshes drawn (the shadow proxy aside), at most %d" % [int(r.meshes), MAX_MESHES])
	var seen := {}
	for view: String in ["front", "back"]:
		var v: Dictionary = r.views[view]
		assert_true(int(v.pixels) > 2000, "%s: the giant fills the frame (%d pixels)" % [view, int(v.pixels)])
		assert_true(float(v.flicker) <= MAX_FLICKER, "%s: no z-fighting (%.4f of the giant's pixels flip, %d)" % [view,
			float(v.flicker), int(v.flips)])
		assert_true(int(v.draws) <= MAX_DRAWS, "%s: the giant's draw calls %d, at most %d" % [view, int(v.draws), MAX_DRAWS])
		assert_true(int(v.primitives) <= MAX_PRIMITIVES, "%s: the giant's primitives %d, at most %d" % [view,
			int(v.primitives), MAX_PRIMITIVES])
		for k: Variant in v.seen:
			seen[str(k)] = true
	for g: String in ["Garment_iron_helm", "Garment_iron_pauldrons", "Garment_mail_hauberk", "Garment_iron_vambraces",
			"Garment_long_cloak", "Garment_greaves", "Garment_boots", "Garment_trousers_limbs", "Garment_shirt_limbs"]:
		assert_true(seen.has(g), "%s shows from the front or behind" % g)
	print("    test_wardrobe_render: %d meshes; front %s; back %s; on %s" % [int(r.meshes), _brief(r.views.front),
		_brief(r.views.back), str(r.adapter)])


static func _brief(v: Dictionary) -> String:
	return "flicker %.4f (%d of %d px), %d draws, %d primitives" % [float(v.flicker), int(v.flips), int(v.pixels),
		int(v.draws), int(v.primitives)]
