extends TestSuite
## The M10 gate's LC-3 (plan M10 decision 8; docs/systems/P46.md "The M10 gate"): first person looking down. The
## camera stands inside the head and only the limbs draw; past a pitch of about -55 degrees the arms' shoulder
## ends came into the frame's lower corners as flat, saw-toothed slabs (the caps that close the limb mesh at the
## shoulder cuts: 89 % and 78 % of the two corner blocks at -70 degrees, all of both at -85). The giant's skin and
## cloth shaders now fade the limbs out towards the shoulders while the camera is inside the head
## (assets/shaders/giant_first_person.gdshaderinc). This runs tests/support/skinned_rig_probe.tscn in mode
## "fp_down" in a child Godot under Xvfb (the Compatibility renderer, 480x270) at stages 1 and 6: at pitches
## -55, -70 and -85 the frame's two bottom corner blocks are the same with the giant and without him, while his
## arms and legs still draw elsewhere in the frame; no shader error; the look validates. Without xvfb-run it is
## skipped with a note (tools/check.sh --require turns that into a failure).

## The share of a corner block's pixels the giant may change (the dither's last pixels at the fade's edge).
const CORNER_MAX := 0.02
## The share of the whole frame the giant must still change (his forearms, hands and legs: 0.08-0.13 measured).
const DRAWN_MIN := 0.04
const STAGES := [1, 6]
## The game's 16:9 (the corner blocks are a share of the frame; at 4:3 the forearms cross them).
const RESOLUTION := "480x270"


func test_the_shoulders_stay_out_of_the_lower_corners() -> void:
	if not SkinnedRigProbe.have_xvfb():
		print("    test_first_person_shoulders: skipped - xvfb-run is not installed (the rendered check needs a display)")
		return
	var notes := PackedStringArray()
	for stage: int in STAGES:
		var r := SkinnedRigProbe.run(PackedStringArray(["--probe-stage=%d" % stage, "--probe-mode=fp_down"]), RESOLUTION)
		var rep: Dictionary = r.report
		assert_eq(int(r.code), 0, "stage %d: the probe ran (exit %d)" % [stage, int(r.code)])
		assert_false(str(r.output).contains("SHADER ERROR"), "stage %d: no shader error" % stage)
		var corners: Dictionary = rep.get("fp_corners", {})
		assert_eq(corners.size(), SkinnedRigProbe.FP_DOWN_PITCHES.size(), "stage %d: every pitch was drawn: %s" % [stage,
			str(r.output).right(400) if corners.is_empty() else ""])
		assert_eq(rep.get("validate", ["?"]), [], "stage %d: the look validates" % stage)
		for frame: String in corners:
			var c: Dictionary = corners[frame]
			assert_true(float(c.left) <= CORNER_MAX, "stage %d %s: the lower left corner shows no shoulder (%.3f of it changed)" % [
				stage, frame, float(c.left)])
			assert_true(float(c.right) <= CORNER_MAX, "stage %d %s: the lower right corner shows no shoulder (%.3f of it changed)" % [
				stage, frame, float(c.right)])
			assert_true(float(c.drawn) >= DRAWN_MIN, "stage %d %s: the arms and legs still draw (%.3f of the frame)" % [stage, frame,
				float(c.drawn)])
			notes.append("s%d %s %.3f/%.3f" % [stage, frame.trim_prefix("fp_down"), float(c.left), float(c.right)])
	print("    test_first_person_shoulders: corner shares left/right - %s" % ", ".join(notes))
