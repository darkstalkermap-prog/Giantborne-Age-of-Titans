extends TestSuite
## The skin in the world's light (Gate A; docs/systems/P51.md "Gate A"). After W30 the sunlit skin read near white
## with a hard, ragged edge (snow on the shoulders) and the shade grey-mauve: the subsurface lookup's flat rows were
## Lambert's hard terminator (the giant's skin is nearly flat at the profile's scale) and the albedo's grade, made for
## the creator's light, was pale and grey. And first person cast no shadow: the shadow proxy sat on the head's layer,
## which the first-person camera culls (a shadows-only mesh is still culled by the camera's mask).
##
## tests/support/skin_world_probe.tscn (a child: Xvfb, the Compatibility renderer, two llvmpipe threads, 320x240)
## draws the skin alone in the world's light for three looks (the default ruddy Wanderer, the palest preset, Storm
## Herald, and the darkest, Iron Veteran's bronze) at the face and full framings, and first person. The bounds come
## from the fixed build with a margin and fail on the wave-30 build (measured, the same renderer; the system doc
## lists both): the near-white share of the lit skin, the share of hard luminance steps at the face framing, the
## shade's warmth, and the giant's shadow on the ground in first person. Without xvfb-run it is skipped with a note.

const PROBE := "res://tests/support/skin_world_probe.tscn"
const PREFIX := "SKIN_WORLD "
const SHOTS := "user://m11_frames/GateA/skin_world"
const CHILD_TIMEOUT_S := 150
## Ceilings of the near-white share of the lit skin, both framings (fixed / wave-30: Wanderer 0.00 / 0.88-0.90,
## Storm Herald 0.13-0.47 / 0.94-0.99, Iron Veteran 0.00 / 0.00).
const WHITE_MAX := {"wanderer": 0.15, "storm_herald": 0.65, "iron_veteran": 0.15}
## Ceilings of the hard steps' share at the face framing (fixed / wave-30: 0.0060 / 0.0116, 0.0087 / 0.0156,
## 0.0070 / 0.0095).
const STEP_MAX := {"wanderer": 0.009, "storm_herald": 0.012, "iron_veteran": 0.0085}
## Floors of the shade's warmth, red minus blue of the darkest 15 %, both framings (fixed / wave-30: 16.8-26.6 /
## 12.1-21.3, 4.6-4.9 / -5.5 to -3.5, 16.7-26.1 / 13.3-14.5).
const WARM_MIN := {"wanderer": 10.0, "storm_herald": 1.5, "iron_veteran": 10.0}
## The floor of the share of the first-person frame the giant's shadow darkens (fixed 0.041, wave-30 0).
const FP_SHADOW_MIN := 0.02


static func _have(tool: String) -> bool:
	var out: Array = []
	return OS.execute("sh", ["-c", "command -v %s" % tool], out, true) == 0


func test_the_skin_holds_its_colour_in_the_worlds_light() -> void:
	if not _have("xvfb-run"):
		print("    test_skin_world_render: skipped - xvfb-run is not installed (the rendered check needs a display)")
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SHOTS))
	var args := PackedStringArray(["LP_NUM_THREADS=2", "timeout", str(CHILD_TIMEOUT_S), "xvfb-run", "-a", "-s",
		"-screen 0 1280x720x24", OS.get_executable_path(), "--path", ProjectSettings.globalize_path("res://"),
		"--rendering-driver", "opengl3", "--resolution", "320x240", "--audio-driver", "Dummy", PROBE, "--",
		"--out=" + ProjectSettings.globalize_path(SHOTS)])
	var output: Array = []
	var code := OS.execute("env", args, output, true)
	var text := "\n".join(output)
	var r := {}
	for l in text.split("\n"):
		if l.begins_with(PREFIX):
			var v: Variant = JSON.parse_string(l.substr(PREFIX.length()).strip_edges())
			if typeof(v) == TYPE_DICTIONARY:
				r = v
		elif l.contains("SHADER ERROR") or l.begins_with("SCRIPT ERROR"):
			assert_true(false, "no shader or script error: %s" % l.strip_edges())
	assert_eq(code, 0, "the probe ran (exit %d)" % code)
	assert_true(r.has("looks"), "the probe reported: %s" % text.right(600))
	if not r.has("looks"):
		return
	var line := PackedStringArray()
	for look: String in WHITE_MAX:
		var per: Dictionary = r.looks.get(look, {})
		for f: String in ["face", "full"]:
			var m: Dictionary = per.get(f, {})
			assert_true(int(m.get("pixels", 0)) > 2000, "%s %s: the skin is in the frame (%d px)" % [look, f, int(m.get("pixels", 0))])
			assert_true(float(m.get("white", 1.0)) <= float(WHITE_MAX[look]),
				"%s %s: the lit skin is not white (near-white share %.3f, at most %.2f)" % [look, f, float(m.get("white", 1.0)), WHITE_MAX[look]])
			assert_true(float(m.get("shade_warm", -99.0)) >= float(WARM_MIN[look]),
				"%s %s: the shade keeps its warmth (red - blue %.1f, at least %.1f)" % [look, f, float(m.get("shade_warm", -99.0)), WARM_MIN[look]])
		var step := float((per.get("face", {}) as Dictionary).get("step", 1.0))
		assert_true(step <= float(STEP_MAX[look]), "%s face: no hard, ragged terminator (hard steps %.4f, at most %.4f)" % [
			look, step, STEP_MAX[look]])
		line.append("%s white %.2f/%.2f step %.4f warm %.1f" % [look, float(per.face.white), float(per.full.white), step,
			float(per.face.shade_warm)])
	assert_true(float(r.get("fp_shadow", 0.0)) >= FP_SHADOW_MIN,
		"first person: the giant casts his shadow on the ground (%.3f of the frame, at least %.2f)" % [float(r.get("fp_shadow", 0.0)), FP_SHADOW_MIN])
	print("    test_skin_world_render: %s; first-person shadow %.3f; %s" % ["; ".join(line), float(r.get("fp_shadow", 0.0)),
		str(r.get("adapter", "?"))])
