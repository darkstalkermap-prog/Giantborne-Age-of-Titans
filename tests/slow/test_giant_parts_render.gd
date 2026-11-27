extends TestSuite
## P48 (plan M11 §3.1 tests; §1.7 rule 4): the giant's parts, the shadow proxy and the leaf chains, rendered.
## The headless runner draws nothing, so this runs tests/support/giant_parts_probe.tscn in a child Godot
## under Xvfb with the Compatibility renderer (opengl3, two llvmpipe threads, 320x240):
##   * every part (a glTF of its own) loads, binds to the model's skeleton and draws: shown alone it changes
##     the frame;
##   * the cards follow their chains and the cape its own: bending the leaf bones moves pixels;
##   * the shadow proxy casts the giant's shadow; without it nothing casts (the other meshes cast none);
##     the free cape casts its own;
##   * the mesh buffers of the default look and of the fullest look are under plan §2.12's 4.5 MB, and well
##     under every part resident (M10);
##   * a part's first load is quick; the look validates.
## Without xvfb-run it is skipped with a note (tools/check.sh --require turns that into a failure).

const PROBE := "res://tests/support/giant_parts_probe.tscn"
const CHILD_TIMEOUT_S := 120
const PREFIX := "GIANT_PARTS "
## A part draws when at least this many of the 76,800 pixels change (the smallest, the pauldron, changes
## about 200).
const MIN_PART_PX := 60
## P51: a shell style is the skin it grows on, a little lifted: the crop covers the top of the head, about 30
## pixels of this full-figure frame (its cards stood off the head before).
const MIN_SHELL_PX := 15
## P54: an accessory (a torc, a ring, a trophy: at most 400 triangles) covers a few pixels of the full figure.
const MIN_ACCESSORY_PX := 2
const SHELLS := ["Hair_crop", "Beard_short"]
const MESH_BUDGET_MB := 4.5


static func _have(tool: String) -> bool:
	var out: Array = []
	return OS.execute("sh", ["-c", "command -v %s" % tool], out, true) == 0


func test_every_part_draws_and_the_proxy_casts_the_shadow() -> void:
	if not _have("xvfb-run"):
		print("    test_giant_parts_render: skipped - xvfb-run is not installed (the rendered check needs a display)")
		return
	var args := PackedStringArray(["LP_NUM_THREADS=2", "timeout", str(CHILD_TIMEOUT_S), "xvfb-run", "-a", "-s",
		"-screen 0 1280x720x24", OS.get_executable_path(), "--path", ProjectSettings.globalize_path("res://"),
		"--rendering-driver", "opengl3", "--resolution", "320x240", "--audio-driver", "Dummy", PROBE])
	var output: Array = []
	var code := OS.execute("env", args, output, true)
	var text := "\n".join(output)
	var line := ""
	var errors := PackedStringArray()
	for l in text.split("\n"):
		if l.begins_with(PREFIX):
			line = l.substr(PREFIX.length()).strip_edges()
		elif l.contains("SHADER ERROR") or l.contains("SCRIPT ERROR"):
			errors.append(l.strip_edges())
	assert_eq(code, 0, "the probe ran (exit %d)" % code)
	assert_eq(errors, PackedStringArray(), "no shader or script error")
	var r: Variant = JSON.parse_string(line)
	assert_true(typeof(r) == TYPE_DICTIONARY and not (r as Dictionary).has("error"), "it reported: %s" % (line if line != "" else text.right(800)))
	if typeof(r) != TYPE_DICTIONARY or (r as Dictionary).has("error"):
		return
	var parts: Dictionary = r.parts
	assert_eq(parts.size(), 103, "every part was shown (P54: 36 more; P56: nine styles and three bead sets; P61: the rival giants' three; B1: the nasal helm and the Quarry set's four; B2: the other sets' ten; B3: the Warden set's four; C2: the Bastion set's six; D1: the Frostbound set's six)")
	for id: String in parts:
		assert_true(int(parts[id]) >= (MIN_SHELL_PX if id in SHELLS else (MIN_ACCESSORY_PX if id.begins_with("Accessory_") or id.begins_with("Beads_") or id.begins_with("Armour_") else MIN_PART_PX)), "%s loads, binds and draws (%d pixels)" % [
			id, int(parts[id])])
	assert_true(int(r.chain.hair_and_beard) >= 20, "the cards follow their chains (%d pixels move)" % int(r.chain.hair_and_beard))
	assert_true(int(r.chain.cape) >= 100, "the cape follows its chains (%d pixels move)" % int(r.chain.cape))
	var sh: Dictionary = r.shadow
	assert_true(int(sh.proxy) >= 200, "the proxy casts the giant's shadow (%d pixels)" % int(sh.proxy))
	assert_true(int(sh.none) <= 8, "without the proxy nothing casts: no other mesh draws into the shadow passes (%d pixels)" % int(sh.none))
	assert_true(int(sh.cape_alone) >= 40, "the free cape casts its own shadow (%d pixels)" % int(sh.cape_alone))
	var mb: Dictionary = r.mesh_mb
	assert_true(float(mb.fullest) <= MESH_BUDGET_MB, "the fullest look: %.2f MB of mesh buffers, at most %.1f" % [float(mb.fullest), MESH_BUDGET_MB])
	assert_true(float(mb["default"]) < float(mb.fullest) and float(mb.fullest) < float(mb.all_loaded) - 1.5,
		"parts on demand: %.2f MB the default look, %.2f the fullest, %.2f with every part loaded" % [float(mb["default"]),
		float(mb.fullest), float(mb.all_loaded)])
	for id: String in r.load_ms:
		assert_true(float(r.load_ms[id].read_bind) < 50.0, "%s: read and bound in %.1f ms" % [id, float(r.load_ms[id].read_bind)])
	assert_eq(r.validate, [], "the look validates")
	print("    test_giant_parts_render: %d parts drawn; shadow %d px by the proxy (%d triangles), %d without; mesh buffers %.2f / %.2f / %.2f MB (default, fullest, all); a part's first load %.1f ms on %s" % [parts.size(), 
		int(sh.proxy), int(sh.proxy_tris), int(sh.none), float(mb["default"]), float(mb.fullest), float(mb.all_loaded),
		float(r.load_ms.values()[0].read_bind), str(r.adapter)])
