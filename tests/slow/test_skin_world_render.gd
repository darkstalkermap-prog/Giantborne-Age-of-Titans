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
##
## Gate A2: the shell hair (the crop, the short beard) in the world's light, for dark, greying, red, fair and grey
## hair: its mean colour near the same look's card style's (the cards set the hair's colour and grey), and not flat.
## At m11-gate-a every case missed the colour (the Storm Herald's black beard drew one flat black, lum 0.1, spread 0.2;
## the Iron Veteran's greying crop 62 against the cards' 129) and it fails 5 of these checks; fixed, the shells read
## 0.67-0.90 of the cards' luminance (the probe prints both).

const PROBE := "res://tests/support/skin_world_probe.tscn"
const PREFIX := "SKIN_WORLD "
const SHOTS := "user://m11_frames/GateA/skin_world"
const CHILD_TIMEOUT_S := 150
## Ceilings of the near-white share of the lit skin, both framings (fixed / wave-30: Wanderer 0.00 / 0.88-0.90,
## Storm Herald 0.13-0.47 / 0.94-0.99, Iron Veteran 0.00 / 0.00).
const WHITE_MAX := {"wanderer": 0.15, "storm_herald": 0.65, "iron_veteran": 0.15}
## Ceilings of the hard steps' share at the face framing (fixed / wave-30: 0.0060 / 0.0116, 0.0087 / 0.0156,
## 0.0070 / 0.0095).
## W33frame: re-derived on the reproportioned body (W33body). The face's own steps did not change (the Wanderer's in
## the head's rows 125 on the M10 body, 131 on this one), but the share's denominator did: at the face framing the
## narrower, lower shoulders and chest leave 22,537 skin pixels in the frame, not 29,670, and the upper arms' outlines
## now fall inside it - the fixed skin reads 0.0106 / 0.0170 / 0.0067. Wave-30's terminator on this body (its
## subsurface lookup, the cause of the hard edge, put back on this tree) reads 0.0154 / 0.0217 / 0.0080; the ceilings
## sit halfway (the Iron Veteran's stands: 0.0067 under it, and wave-30's full build also had the pale grade).
const STEP_MAX := {"wanderer": 0.013, "storm_herald": 0.0194, "iron_veteran": 0.0085}
## Floors of the shade's warmth, red minus blue of the darkest 15 %, both framings (fixed / wave-30: 16.8-26.6 /
## 12.1-21.3, 4.6-4.9 / -5.5 to -3.5, 16.7-26.1 / 13.3-14.5).
const WARM_MIN := {"wanderer": 10.0, "storm_herald": 1.5, "iron_veteran": 10.0}
## Gate A2: a shell's mean luminance within SHELL_LUM_TOL of the card style's (or SHELL_LUM_ABS, for black hair),
## each channel within SHELL_RGB_TOL (or SHELL_RGB_ABS); its spread (90th less 10th percentile of luminance) at least
## SHELL_SPREAD_MIN and SHELL_SPREAD_SHARE of its mean (fixed / m11-gate-a: Storm Herald 12.0 / 0.2). W33frame: the card
## style's colour is its pixels where the shell draws too: the card beards grew with the reproportioned head and their
## longer, lighter tips over the lit chest moved the whole style's mean (the Northern Chieftain's blue 34.8 to 37.1,
## the shell's 23.6 to 23.7) while the card's colour in the shell's area held (31.4 to 31.1).
const SHELL_LUM_TOL := 0.3
const SHELL_LUM_ABS := 6.0
const SHELL_RGB_TOL := 0.35
const SHELL_RGB_ABS := 10.0
const SHELL_SPREAD_MIN := 8.0
const SHELL_SPREAD_SHARE := 0.25
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
	var shells: Dictionary = r.get("shells", {})
	assert_eq(shells.size(), 5, "the probe drew the five shell cases")
	for case_name: String in shells:
		var sh: Dictionary = shells[case_name].get("shell", {})
		# W33frame: the card style's colour is read where the shell draws (the probe's `card`), its presence on the whole
		# style (`card_all`)
		var card: Dictionary = shells[case_name].get("card", {})
		var card_all: Dictionary = shells[case_name].get("card_all", {})
		assert_true(int(sh.get("pixels", 0)) > 1000 and int(card_all.get("pixels", 0)) > 1000,
			"%s: the shell and the card style are in the frame (%d, %d px)" % [case_name, int(sh.get("pixels", 0)), int(card_all.get("pixels", 0))])
		if not sh.has("rgb") or not card.has("rgb"):
			continue
		var ls := float(sh.lum)
		var lc := float(card.lum)
		assert_true(absf(ls - lc) <= maxf(SHELL_LUM_ABS, SHELL_LUM_TOL * lc),
			"%s: the shell's luminance %.1f near the card style's %.1f (within %.1f)" % [case_name, ls, lc, maxf(SHELL_LUM_ABS, SHELL_LUM_TOL * lc)])
		for i in 3:
			var a := float(sh.rgb[i])
			var b := float(card.rgb[i])
			assert_true(absf(a - b) <= maxf(SHELL_RGB_ABS, SHELL_RGB_TOL * b),
				"%s: the shell's channel %d %.1f near the card style's %.1f" % [case_name, i, a, b])
		var spread := float(sh.p90) - float(sh.p10)
		assert_true(spread >= maxf(SHELL_SPREAD_MIN, SHELL_SPREAD_SHARE * ls),
			"%s: the shell is not flat (luminance spread %.1f, at least %.1f)" % [case_name, spread, maxf(SHELL_SPREAD_MIN, SHELL_SPREAD_SHARE * ls)])
		line.append("%s shell %.0f / card %.0f, spread %.0f" % [case_name, ls, lc, spread])
	assert_true(float(r.get("fp_shadow", 0.0)) >= FP_SHADOW_MIN,
		"first person: the giant casts his shadow on the ground (%.3f of the frame, at least %.2f)" % [float(r.get("fp_shadow", 0.0)), FP_SHADOW_MIN])
	print("    test_skin_world_render: %s; first-person shadow %.3f; %s" % ["; ".join(line), float(r.get("fp_shadow", 0.0)),
		str(r.get("adapter", "?"))])
