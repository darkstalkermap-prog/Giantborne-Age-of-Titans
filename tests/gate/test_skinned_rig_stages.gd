extends TestSuite
## P43 (plan M10 §3.3 "test_skinned_rig_stages", §1.7 rule 6, decision 8): the skinned giant rendered at
## stages 4 and 6 (the frames of tests/slow/test_skinned_rig_render.gd, with a weapon that fits the stage:
## the reinforced club) and the pressed-close camera in the growth course's low passage (stage 3, the
## 8.6 m ceiling: the third-person arm pressed short behind the head). Each in a child Godot under Xvfb
## (tests/support/skinned_rig_probe.tscn; the frames go to user://m10_frames/ for the gate's review):
##   * stages 4 and 6: no frame blank; the heavy drawn keeps tip matching's contract (the visible weapon's
##     outer half inside the tested capsule, at most 15 degrees off it, the fist within 0.01 m x k); first
##     person at rest leaves the crosshair's pixels alone;
##   * the passage: the camera hides the head's layer (3), the torso stays drawn (CameraRig.PRESSED_CULLS_TORSO
##     is false: this render showed the torso below the crosshair, docs/systems/P43.md), and the giant does
##     not cover the crosshair.
## Without xvfb-run it is skipped with a note (--require fails it).

const WEAPON := "weapon.club_reinforced"


func _stage(stage: int) -> void:
	var r := SkinnedRigProbe.run(PackedStringArray(["--probe-stage=%d" % stage, "--probe-weapon=" + WEAPON]))
	var rep: Dictionary = r.report
	assert_eq(int(r.code), 0, "stage %d: the probe ran (exit %d)" % [stage, int(r.code)])
	assert_false(rep.is_empty(), "stage %d: it reported: %s" % [stage, str(r.output).right(600)])
	if rep.is_empty():
		return
	assert_true(bool(rep.get("grown", false)), "stage %d: grown" % stage)
	assert_true(bool((rep.get("weapon", {}) as Dictionary).get("ok", false)), "stage %d: %s equipped (%s)" % [stage, WEAPON, rep.get("weapon")])
	var k := float(rep.get("k", 1.0))
	var frames: Dictionary = rep.get("frames", {})
	for f: String in SkinnedRigProbe.FRAME_NAMES:
		var fr: Dictionary = frames.get(f, {})
		assert_true(float(fr.get("lit", 0.0)) >= SkinnedRigProbe.MIN_LIT, "stage %d: %s is drawn (%.2f)" % [stage, f, float(fr.get("lit", 0.0))])
	assert_eq(int(rep.get("capture_ticks_max", -1)), 0, "stage %d: the simulation is held while a frame is drawn (M10 gate, LC-8)" % stage)
	var swing: Dictionary = rep.get("swing", {})
	assert_true(int(swing.get("samples", 0)) > 0, "stage %d: the heavy was measured" % stage)
	assert_true(float(swing.get("outer_max_radii", 9.0)) <= 1.0, "stage %d: the outer half inside the capsule (%.2f radii)" % [stage, float(swing.get("outer_max_radii", 9.0))])
	assert_true(float(swing.get("angle_max_deg", 99.0)) <= TipMatching.MAX_ANGLE_DEG, "stage %d: within 15 degrees (%.1f)" % [stage, float(swing.get("angle_max_deg", 99.0))])
	assert_true(float(swing.get("fist_max_m", 9.0)) <= TipMatching.FIST_TOLERANCE_M * k, "stage %d: the fist on its target (%.4f m)" % [stage, float(swing.get("fist_max_m", 9.0))])
	assert_false(bool((rep.get("crosshair", {}) as Dictionary).get("covered", true)), "stage %d: first person leaves the crosshair alone" % stage)
	assert_eq(rep.get("validate", ["?"]), [], "stage %d: the look validates" % stage)


func test_stage_4_frames() -> void:
	if not SkinnedRigProbe.have_xvfb():
		print("    test_skinned_rig_stages: skipped - xvfb-run is not installed (the rendered check needs a display)")
		return
	_stage(4)


func test_stage_6_frames() -> void:
	if not SkinnedRigProbe.have_xvfb():
		print("    test_skinned_rig_stages: skipped - xvfb-run is not installed (the rendered check needs a display)")
		return
	_stage(6)


func test_the_pressed_close_passage() -> void:
	if not SkinnedRigProbe.have_xvfb():
		print("    test_skinned_rig_stages: skipped - xvfb-run is not installed (the rendered check needs a display)")
		return
	var r := SkinnedRigProbe.run(PackedStringArray(["--probe-mode=passage"]))
	var rep: Dictionary = r.report
	assert_eq(int(r.code), 0, "the probe ran (exit %d)" % int(r.code))
	assert_false(rep.is_empty(), "it reported: %s" % str(r.output).right(600))
	if rep.is_empty():
		return
	var passage: Dictionary = rep.get("passage", {})
	assert_true(bool(passage.get("head_hidden", false)), "the arm is pressed short: the head is hidden (arm %.2f m)" % float(passage.get("arm_m", -1.0)))
	assert_eq(int(passage.get("cull_mask", 0)), CameraRig.CULL_NO_HEAD, "the pressed-close mask")
	var torso_bit := 1 << (CameraRig.TORSO_LAYER - 1)
	assert_eq((int(passage.get("cull_mask", 0)) & torso_bit) == 0, CameraRig.PRESSED_CULLS_TORSO, "the torso as decided")
	assert_false(bool((rep.get("crosshair", {}) as Dictionary).get("covered", true)),
		"the giant does not cover the crosshair in the passage (diff %.3f)" % float((rep.get("crosshair", {}) as Dictionary).get("diff", -1.0)))
