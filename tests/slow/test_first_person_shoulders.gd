extends TestSuite
## The M10 gate's LC-3 (plan M10 decision 8; docs/systems/P46.md "The M10 gate"): first person looking down. The
## camera stands inside the head and only the limbs draw; past a pitch of about -55 degrees the arms' shoulder
## ends came into the frame's lower corners as flat, saw-toothed slabs (the caps that close the limb mesh at the
## shoulder cuts: 86 % and 73 % of the two corner blocks at -70 degrees, all of both at -85). The giant's skin and
## cloth shaders now fade the limbs out towards the shoulders while the camera is inside the head
## (assets/shaders/giant_first_person.gdshaderinc). This runs tests/support/skinned_rig_probe.tscn in mode
## "fp_down" in a child Godot under Xvfb (the Compatibility renderer, 480x270) at stages 1 and 6: at rest at
## pitches -55, -70 and -85, and walking and sprinting at -70 (the camera bobs, the body leans: the worst of
## four moments of each), the frame's two bottom corner blocks are the same with the giant and without him,
## while his arms and legs still draw elsewhere in the frame; no shader error; the look validates. Without xvfb-run it is
## skipped with a note (tools/check.sh --require turns that into a failure).
##
## Gate A2: the same runs then stand at rest looking ahead (pitch 0) with a club, a sword and a hammer: the weapon
## sits low at the right edge like a carried weapon (fp_rest's forearm turned so the handle lies out to the right),
## covering at most FP_REST_SHARE_MAX of the frame inside the lower right (its box's left edge right of
## FP_REST_LEFT_MIN, its top below FP_REST_TOP_MIN), and is not hidden (at least FP_REST_SHARE_MIN). At m11-gate-a the
## club stood upright over the right third (0.183 of the frame, its box from the top edge to the bottom); 0.10 drew
## no weapon there.

## The share of a corner block's pixels the giant may change (the dither's last pixels at the fade's edge: at
## most 0.007 measured, in the stage-1 sprint).
const CORNER_MAX := 0.02
## The share of the whole frame the giant must still change (his forearms, hands and legs: 0.08-0.13 measured).
const DRAWN_MIN := 0.04
const STAGES := [1, 6]
## The game's 16:9 (the corner blocks are a share of the frame; at 4:3 the forearms cross them).
const RESOLUTION := "480x270"
## Gate A2 (fixed / m11-gate-a, stage 1 club, sword, hammer; stage 6 the same, unreforged): share 0.032-0.058 /
## 0.083-0.183, box left 0.72-0.76 / 0.42-0.69, top 0.64-0.75 / 0.0-0.62; the thinnest, stage 6's sword, 0.006.
const FP_REST_SHARE_MAX := 0.1
const FP_REST_SHARE_MIN := 0.003
const FP_REST_LEFT_MIN := 0.6
const FP_REST_TOP_MIN := 0.4


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
		assert_eq(corners.size(), SkinnedRigProbe.FP_DOWN_PITCHES.size() + 2, "stage %d: every pitch, the walk and the sprint were drawn: %s" % [stage,
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
		var rest: Dictionary = rep.get("fp_rest", {})
		assert_eq(rest.size(), 3, "stage %d: first person at rest drawn with three weapons" % stage)
		for frame: String in rest:
			var w: Dictionary = rest[frame]
			var box: Array = w.get("box", [0.0, 0.0, 0.0, 0.0])
			assert_true(float(w.share) >= FP_REST_SHARE_MIN and float(w.share) <= FP_REST_SHARE_MAX,
				"stage %d %s: the weapon shows, low (%.3f of the frame, %.3f-%.2f)" % [stage, frame, float(w.share), FP_REST_SHARE_MIN, FP_REST_SHARE_MAX])
			assert_true(float(box[0]) >= FP_REST_LEFT_MIN and float(box[1]) >= FP_REST_TOP_MIN,
				"stage %d %s: in the lower right (its box from x %.2f, y %.2f; at least %.2f, %.2f)" % [stage, frame, float(box[0]),
				float(box[1]), FP_REST_LEFT_MIN, FP_REST_TOP_MIN])
			assert_true(float(w.get("fp_weight", 0.0)) > 0.99, "stage %d %s: at rest (fp_rest whole)" % [stage, frame])
			notes.append("s%d %s %.3f [%.2f, %.2f]" % [stage, frame, float(w.share), float(box[0]), float(box[1])])
	print("    test_first_person_shoulders: corner shares left/right - %s" % ", ".join(notes))
