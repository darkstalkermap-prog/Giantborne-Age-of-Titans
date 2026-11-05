extends IntegrationSuite
## First person while holding (plan §3.7, §0.2 "camera/growth": no obscured crosshair): a giant
## holding a soldier turns a full circle in first person, looking ahead and then down, and the
## crosshair probe (tests/support/crosshair_probe.gd, P05) never finds the giant's arm or the
## held body covering the screen centre for more than 30 consecutive ticks. The hold socket keeps
## the body low and to the left of the view at every stage.

const TURN_TICKS := 90


func _profile(stage: int) -> Dictionary:
	for rec: Dictionary in GameData.records_of_type("growth_profile"):
		if int(rec.get("stage", 0)) == stage:
			return rec
	return {}


## Holds a soldier in first person at `stage` and turns 360 degrees at each pitch, sampling the
## probe every tick. Returns the probe.
func _turn_while_holding(stage: int) -> CrosshairProbe:
	var p := spawn_player(Vector3(0, 0.05, 0), 0.0)
	if stage != 1:
		p.set_profile(_profile(stage))
	await TestWait.until(self, func() -> bool: return p.is_on_floor(), 40)
	var s := spawn_soldier(Vector3(0, 0.05, -0.55 * float(p.profile.grab_reach_m)), PI, "test.fp_held_%d" % stage)
	await step_ticks(1)
	s.entity.stagger(3.0, "test")
	p.grab.hold_timeout_s = 60.0
	assert_eq(p.grab.try_grab(), CombatController.Verdict.ACCEPT, "stage %d: grab" % stage)
	var held: bool = await TestWait.until(self, func() -> bool: return p.grab.is_holding(), 40)
	assert_true(held, "stage %d: holding a soldier" % stage)
	p.camera_rig.set_mode(CameraRig.Mode.FIRST_PERSON)
	await TestWait.until(self, func() -> bool: return p.controller.action == null, 40)
	await step_ticks(12)   # the arm settles into the first-person hold
	var probe := CrosshairProbe.new(p.camera_rig.camera, [p, s])
	var max_x := -INF   # the grab point's right-most position in the camera's view (x < 0: left)
	for pitch_deg in [0.0, -40.0]:
		p.camera_rig.pitch = deg_to_rad(pitch_deg)
		for i in TURN_TICKS:
			p.camera_rig.yaw = wrapf(p.camera_rig.yaw + TAU / TURN_TICKS, -PI, PI)
			await step_ticks(1)
			probe.sample()
			var local := p.camera_rig.camera.to_local((s.get_node("Anchors/Grab") as Node3D).global_position)
			max_x = maxf(max_x, local.x)
	assert_true(max_x < -0.5, "stage %d: the held body stays left of the view (camera x at most %.2f)" % [stage, max_x])
	assert_true(p.grab.is_holding(), "stage %d: still holding after the turns" % stage)
	assert_eq(probe.samples, TURN_TICKS * 2, "stage %d: sampled every tick" % stage)
	p.grab.drop()
	p.camera_rig.set_mode(CameraRig.Mode.THIRD_PERSON, false)
	return probe


func test_first_person_while_holding_never_covers_the_crosshair() -> void:
	for stage in [1, 3]:
		var probe := await _turn_while_holding(stage)
		assert_true(probe.max_consecutive <= 30,
			"stage %d: at most 30 consecutive obscured ticks (worst %d, by %s)" % [
				stage, probe.max_consecutive, probe.worst_blocker])
		assert_eq(probe.obscured_ticks, 0, "stage %d: the body and the arm stay out of the centre (%s)" % [
			stage, probe.worst_blocker])
		for n in world.get_children():
			if n is GiantPlayer or n is EnemyActor:
				n.queue_free()
		await step_ticks(2)
