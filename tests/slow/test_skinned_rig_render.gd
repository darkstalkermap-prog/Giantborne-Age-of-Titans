extends TestSuite
## P43 (plan M10 §3.3 "test_skinned_rig_render", §1.7 rule 6): the skinned giant, rendered at stage 1. The
## headless runner draws nothing, so this runs tests/support/skinned_rig_probe.tscn in a child Godot under
## Xvfb with the Compatibility renderer (opengl3, LP_NUM_THREADS=2, 320x240, the render loop off between the
## captured frames): idle, a walk, a heavy's windup, active and recovery, a jump, first person looking down
## and ahead. No frame is blank; the crosshair's pixels are the same with and without the giant (first
## person, at rest); the swing drawn keeps tip matching's contract (the visible weapon's outer half inside
## the tested capsule, at most 15 degrees off it, the fist on its target); the look validates; the frames are
## saved (user://m10_frames/s1_*.png) for the merges and the gate. Without xvfb-run it is skipped with a note
## (tools/check.sh --require turns that into a failure). Stages 4 and 6 and the pressed-close passage are the
## gate tier's tests/gate/test_skinned_rig_stages.gd.

func test_the_stage_1_frames() -> void:
	if not SkinnedRigProbe.have_xvfb():
		print("    test_skinned_rig_render: skipped - xvfb-run is not installed (the rendered check needs a display)")
		return
	var r := SkinnedRigProbe.run(PackedStringArray(["--probe-stage=1"]))
	var rep: Dictionary = r.report
	assert_eq(int(r.code), 0, "the probe ran (exit %d)" % int(r.code))
	assert_false(rep.is_empty(), "it reported: %s" % str(r.output).right(600))
	if rep.is_empty():
		return
	assert_true(bool(rep.get("layers", false)), "the skinned layers ran with a display")
	var frames: Dictionary = rep.get("frames", {})
	for f: String in SkinnedRigProbe.FRAME_NAMES:
		var fr: Dictionary = frames.get(f, {})
		assert_true(float(fr.get("lit", 0.0)) >= SkinnedRigProbe.MIN_LIT, "%s is drawn (%.2f of the pixels)" % [f, float(fr.get("lit", 0.0))])
		assert_true(FileAccess.file_exists(str(fr.get("path", ""))), "%s is saved" % f)
	var cross: Dictionary = rep.get("crosshair", {})
	assert_false(bool(cross.get("covered", true)), "first person: the giant at rest leaves the crosshair's pixels alone (diff %.3f)" % float(cross.get("diff", -1.0)))
	assert_true(bool(rep.get("airborne", false)), "the jump left the ground")
	var swing: Dictionary = rep.get("swing", {})
	assert_true(int(swing.get("samples", 0)) > 0, "the heavy's ACTIVE frames were measured (%d)" % int(swing.get("samples", 0)))
	assert_true(float(swing.get("outer_max_radii", 9.0)) <= 1.0, "the visible weapon's outer half inside the tested capsule (%.2f radii)" % float(swing.get("outer_max_radii", 9.0)))
	assert_true(float(swing.get("angle_max_deg", 99.0)) <= TipMatching.MAX_ANGLE_DEG, "within 15 degrees of the tested direction (%.1f)" % float(swing.get("angle_max_deg", 99.0)))
	assert_true(float(swing.get("fist_max_m", 1.0)) <= TipMatching.FIST_TOLERANCE_M, "the fist on its target (%.4f m)" % float(swing.get("fist_max_m", 1.0)))
	assert_eq(rep.get("validate", ["?"]), [], "the look validates")
	print("    test_skinned_rig_render: stage 1, %d frames, %.1f ms a frame of the whole giant on %s" % [frames.size(),
		float(rep.get("frame_ms", 0.0)), str(rep.get("adapter", "?"))])
