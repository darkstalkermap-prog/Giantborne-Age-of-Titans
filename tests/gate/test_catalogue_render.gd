extends TestSuite
## The catalogue II, rendered (P56; plan M11 §3.9's tests; §1.7 rule 6): tests/support/catalogue_render_probe.tscn in a
## child Godot under Xvfb at 320x240 (the Compatibility renderer, two llvmpipe threads), the web tier's maps:
##   * every new hair and beard style is drawn (its framing changes against no style by at least MIN_DRAWN of the
##     frame), sways (the hair shader's head_motion moves its cards' tips: MIN_SWAY) and wears its beads (a bead set
##     changes the frame: MIN_BEADS), with GiantLook.validate() empty;
##   * every face key at -1 and +1 leaves no patch darker than the same shape blended on the CPU by more than
##     MAX_DARK_PATCH (8/255, the plan's; the renderer's blend lost the tangent's sign and drew a black quad between the
##     brows until the skin shader rebuilt its binormal);
##   * every preset is valid and drawn distinct from every other (at least MIN_PRESET_DIFF of the frame differs).
## The beard roots' 2 mm against the keyed skin and the base shape are the tools' tests (tools/giant/test_giant_tools.py
## CatalogueTest, FreezeTest). Without xvfb-run it is skipped with a note.
## P57 (plan M11 §1.7 rule 3: rendered option checks run in the gate tier): moved from tests/slow/, unchanged (about
## 12 s, over the slow tier's 5 s a suite); run it with `--gate --filter=_render` before merging a change of the looks.

const PROBE := "res://tests/support/catalogue_render_probe.tscn"
const CHILD_TIMEOUT_S := 150
const PREFIX := "CATALOGUE_RENDER "
const MIN_DRAWN := 0.03
const MIN_SWAY := 0.005
const MIN_BEADS := 0.0005
const MAX_DARK_PATCH := -8.0
const MIN_PRESET_DIFF := 0.02


static func _have(tool: String) -> bool:
	var out: Array = []
	return OS.execute("sh", ["-c", "command -v %s" % tool], out, true) == 0


func test_the_catalogue_draws_sways_wears_beads_and_keys_its_face_cleanly() -> void:
	if not _have("xvfb-run"):
		print("    test_catalogue_render: skipped - xvfb-run is not installed (the rendered check needs a display)")
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
		elif l.contains("SHADER ERROR") or l.contains("SCRIPT ERROR") or (l.contains("ERROR") and l.contains("giant")):
			errors.append(l.strip_edges())
	assert_eq(code, 0, "the probe ran (exit %d)" % code)
	assert_eq(errors, PackedStringArray(), "every shader and part loads without an error")
	var r: Variant = JSON.parse_string(line)
	assert_true(typeof(r) == TYPE_DICTIONARY and not (r as Dictionary).has("error"), "it reported: %s" % (line if line != ""
		else text.right(800)))
	if typeof(r) != TYPE_DICTIONARY or (r as Dictionary).has("error"):
		return
	assert_eq((r.styles as Dictionary).size(), 9, "the catalogue II's nine styles")
	for k: String in r.styles:
		var s: Dictionary = r.styles[k]
		assert_true(float(s.drawn) >= MIN_DRAWN, "%s is drawn (%.4f of the frame)" % [k, float(s.drawn)])
		assert_true(float(s.sway) >= MIN_SWAY, "%s sways (%.4f)" % [k, float(s.sway)])
		assert_true(float(s.beads) >= MIN_BEADS, "%s wears its beads (%.4f)" % [k, float(s.beads)])
		assert_eq(s.validate, [], "%s with beads: validate() empty" % k)
	assert_eq((r.head_keys as Array).size(), 6, "the head carries the six face keys")
	assert_eq((r.face as Dictionary).size(), 12, "each at -1 and +1")
	for k: String in r.face:
		assert_true(float(r.face[k]) >= MAX_DARK_PATCH, "%s: the darkest patch %.1f/255 against the CPU's blend" % [k,
			float(r.face[k])])
	assert_eq((r.presets as Dictionary).size(), 14, "fourteen presets")
	for id: String in r.presets:
		assert_true(bool(r.presets[id].valid), "%s is valid" % id)
		assert_eq(r.presets[id].validate, [], "%s: validate() empty" % id)
	assert_true(float(r.preset_least.share) >= MIN_PRESET_DIFF, "the two likest presets differ in %.3f of the frame (%s)" %
		[float(r.preset_least.share), str(r.preset_least.pair)])
	print("    test_catalogue_render: worst dark patch %.1f/255; likest presets %s (%.3f)" % [_worst(r.face),
		str(r.preset_least.pair), float(r.preset_least.share)])


static func _worst(face: Dictionary) -> float:
	var w := 0.0
	for k: String in face:
		w = minf(w, float(face[k]))
	return w
