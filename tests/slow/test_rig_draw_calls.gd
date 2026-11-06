extends TestSuite
## P22 (plan M6-M9 §3.4 design 1, "a rendered draw-call check"): the merged rigs, rendered. The
## headless runner draws nothing, so this runs tests/support/rig_draw_probe.gd in a child Godot
## process under Xvfb (software OpenGL, the gl_compatibility renderer the game ships with): the
## stress arena's twelve combatants (4 soldiers, 3 wolves, 2 archers, a mage, 2 ogres), all in view
## at full detail, the `low` look (no sun shadows). Without xvfb-run it is skipped with a note.
##
## At the base of P22 the same probe counted BASE_DRAWS draw calls for the twelve (18.4 each); the
## plan asks for a drop of at least 40 % (decision 9: "rigs at about 7 draw calls"). The stress
## arena's whole view drops less, because the rigs are only part of it (docs/PERFORMANCE.md, the
## P22 results).

const PROBE := "res://tests/support/rig_draw_probe.gd"
const PREFIX := "RIG_DRAWS "
## The twelve at the base of P22 (commit ae6e143, before the merge), measured with this probe.
const BASE_DRAWS := 221
const MAX_SHARE := 0.6
const MAX_PER_ACTOR := 8.0


static func _have(tool: String) -> bool:
	var out: Array = []
	return OS.execute("sh", ["-c", "command -v %s" % tool], out, true) == 0


func test_the_twelve_rigs_draw_at_least_40_percent_less() -> void:
	if not _have("xvfb-run"):
		print("    test_rig_draw_calls: skipped - xvfb-run is not installed (the rendered check needs a display)")
		return
	var args := PackedStringArray(["-a", "-s", "-screen 0 640x360x24", OS.get_executable_path(),
		"--path", ProjectSettings.globalize_path("res://"), "--resolution", "640x360", "--audio-driver", "Dummy",
		"-s", PROBE])
	var output: Array = []
	var code := OS.execute("xvfb-run", args, output, true)
	var text := "\n".join(output)
	var line := ""
	for l in text.split("\n"):
		if l.begins_with(PREFIX):
			line = l.substr(PREFIX.length()).strip_edges()
	assert_eq(code, 0, "the probe ran (exit %d)" % code)
	var r: Variant = JSON.parse_string(line)
	assert_true(typeof(r) == TYPE_DICTIONARY, "it reported: %s" % (line if line != "" else text.right(600)))
	if typeof(r) != TYPE_DICTIONARY:
		return
	var rigs := int(r.with) - int(r.empty)
	assert_eq(int(r.actors), 12, "the twelve combatants")
	assert_true(rigs > 0, "they draw (%d)" % rigs)
	assert_true(rigs <= int(BASE_DRAWS * MAX_SHARE),
		"%d draw calls for the twelve, at least 40 %% under the base's %d (%.0f %% less)" % [rigs, BASE_DRAWS,
			100.0 * (1.0 - float(rigs) / BASE_DRAWS)])
	assert_true(float(r.per_actor) <= MAX_PER_ACTOR, "about 7 per rig (%.1f)" % float(r.per_actor))
	print("    test_rig_draw_calls: %d draw calls for the twelve (%.1f each; base %d, %.0f %% less) on %s" % [rigs,
		float(r.per_actor), BASE_DRAWS, 100.0 * (1.0 - float(rigs) / BASE_DRAWS), str(r.get("adapter", "?"))])
