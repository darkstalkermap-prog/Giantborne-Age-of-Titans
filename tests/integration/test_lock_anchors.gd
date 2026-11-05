extends IntegrationSuite
## Lock anchors (plan §3.12 design 3, spec 5): the ogre and the Ogre King carry
## Anchors/{Torso,KneeL,KneeR} on one CombatEntity; lock_anchor_position(viewer height) is the
## lowest of them for a target at least 1.3 x as tall as the giant, else the torso. Lock framing
## (the camera), the lock's line of sight and candidates, and the HUD's lock marker all use it: at
## stage 2 the camera frames a knee of the 8.5 m king and never looks steeply up; a soldier locked at
## stage 1 is still framed at its torso. The boss bar (name, health, phase pips) shows the engaged or
## locked boss, and the HUD hides its own target frame meanwhile.

const KING := "res://scenes/enemies/ogre_king.tscn"
const OGRE := "res://scenes/enemies/ogre.tscn"


func _profile(stage: int) -> Dictionary:
	for rec: Dictionary in GameData.records_of_type("growth_profile"):
		if int(rec.get("stage", 0)) == stage:
			return rec
	return {}


func _giant(stage := 1, pos := Vector3(0, 0.05, 0), yaw := 0.0) -> GiantPlayer:
	var p := spawn_player(pos, yaw)
	if stage != 1:
		p.set_profile(_profile(stage))
	await TestWait.until(self, func() -> bool: return p.is_on_floor(), 40)
	await step_ticks(1)
	return p


func _hud(p: GiantPlayer) -> Hud:
	var layer := CanvasLayer.new()
	world.add_child(layer)
	var hud := Hud.new()
	hud.player = p
	layer.add_child(hud)
	return hud


func _lowest(nodes: Array) -> Node3D:
	var low: Node3D = null
	for n: Node3D in nodes:
		if low == null or n.global_position.y < low.global_position.y - 1e-4:
			low = n
	return low


func test_the_anchor_rule() -> void:
	var king := TestSpawn.enemy(world, KING, Vector3(0, 0.05, -20), "test.king_anchor", false)
	var ogre := TestSpawn.enemy(world, OGRE, Vector3(10, 0.05, -20), "test.ogre_anchor", false)
	var soldier := spawn_soldier(Vector3(-10, 0.05, -20), 0.0, "test.soldier_anchor")
	await step_ticks(2)
	var ka := king.entity.lock_anchors()
	assert_eq(ka.size(), 3, "the king's torso and both knees")
	assert_eq(ka[0], king.get_node("Anchors/Torso"), "the torso first")
	assert_true(ka.has(king.get_node("Anchors/KneeL")) and ka.has(king.get_node("Anchors/KneeR")), "the knees")
	assert_eq(ogre.entity.lock_anchors().size(), 3, "the ogre's three")
	assert_eq(soldier.entity.lock_anchors().size(), 1, "a soldier has only its torso")
	var knee := _lowest(ka).global_position
	assert_true(knee.y < king.entity.anchor_position().y - 2.0, "a knee sits well below the torso")
	# 8.5 m >= 1.3 x 5.49 m: the stage-2 giant frames a knee; the stage-3 one (7.92 m) the torso.
	assert_true(king.entity.lock_anchor_position(3.6576).is_equal_approx(knee), "stage 1: a knee of the king")
	assert_true(king.entity.lock_anchor_position(5.4864).is_equal_approx(knee), "stage 2: a knee of the king")
	assert_true(king.entity.lock_anchor_position(7.9248).is_equal_approx(king.entity.anchor_position()),
		"stage 3: the king's torso")
	assert_true(ogre.entity.lock_anchor_position(3.6576).is_equal_approx(ogre.entity.anchor_position()),
		"the 3.4 m ogre at stage 1: its torso")
	assert_true(soldier.entity.lock_anchor_position(3.6576).is_equal_approx(soldier.entity.anchor_position()),
		"a soldier: its torso")
	# The knees share the king's one health pool: the lock anchors are not entities.
	assert_eq(Sim.get_entity("test.king_anchor"), king.entity, "one entity")


func test_stage_2_lock_frames_a_knee_of_the_king() -> void:
	var p := await _giant(2, Vector3(0, 0.05, 0), 0.0)
	var king := TestSpawn.enemy(world, KING, Vector3(0, 0.05, -14), "test.king_lock", false, 0.0)
	await step_ticks(3)
	p.targeting.try_lock()
	assert_eq(p.lock.target_id, "test.king_lock", "the giant locks the king")
	var knee := _lowest(king.entity.lock_anchors()).global_position
	assert_true(p.targeting.lock_point(king.entity).is_equal_approx(knee), "the lock point is a knee")
	assert_true(p.camera_rig.lock_focus_point().is_equal_approx(knee), "the camera frames that knee")
	assert_true(p.targeting.is_visible(king.entity), "line of sight to the knee")
	for i in 30:
		await get_tree().process_frame
		await step_ticks(1)
	var pitch_deg := rad_to_deg(p.camera_rig.pitch)
	assert_true(pitch_deg <= CameraRig.LOCK_PITCH_MAX + 0.5, "the camera never looks steeply up (%.1f deg)" % pitch_deg)
	assert_true(pitch_deg < 0.0, "it looks down at the knee from the giant's pivot (%.1f deg)" % pitch_deg)
	# A knee hidden behind a low wall breaks line of sight even though the torso shows over it.
	add_box(Vector3(8, 3.4, 1), Vector3(0, 1.7, -10))
	await step_ticks(2)
	assert_false(p.targeting.is_visible(king.entity), "the low wall hides the knee: the lock's sight is the knee's")
	var space := p.get_world_3d().direct_space_state
	assert_true(HitQueryAdapter.line_clear(space, p.targeting.eye(), king.entity.anchor_position(),
		HitQueryAdapter.LAYER_WORLD, king.entity.occlusion_rids), "(the torso itself is still in sight)")


func test_stage_3_and_a_soldier_are_framed_at_the_torso() -> void:
	var p := await _giant(1, Vector3(0, 0.05, 0), 0.0)
	var s := spawn_soldier(Vector3(0, 0.05, -6), PI, "test.soldier_lock")
	await step_ticks(3)
	p.targeting.try_lock()
	assert_eq(p.lock.target_id, "test.soldier_lock", "the giant locks the soldier")
	assert_true(p.camera_rig.lock_focus_point().is_equal_approx(s.entity.anchor_position()),
		"a locked soldier at stage 1 is framed at its torso")
	p.targeting.release_lock("manual")
	s.queue_free()
	p.set_profile(_profile(3))
	await step_ticks(3)
	var king := TestSpawn.enemy(world, KING, Vector3(0, 0.05, -16), "test.king_tall", false, 0.0)
	await step_ticks(3)
	p.targeting.try_lock()
	assert_eq(p.lock.target_id, "test.king_tall", "the stage-3 giant locks the king")
	assert_true(p.camera_rig.lock_focus_point().is_equal_approx(king.entity.anchor_position()),
		"at stage 3 the king (1.07 x as tall) is framed at its torso")


func test_hud_marker_boss_bar_and_target_frame() -> void:
	var p := await _giant(2, Vector3(0, 0.05, 0), 0.0)
	var hud := _hud(p)
	var king := TestSpawn.enemy(world, KING, Vector3(0, 0.05, -14), "test.king_hud", false, 0.0) as OgreBoss
	var s := spawn_soldier(Vector3(6, 0.05, -6), 0.0, "test.soldier_hud")
	await step_ticks(3)
	await get_tree().process_frame
	var bar := hud.get_node_or_null("BossBar")
	assert_true(bar != null, "the boss bar widget is on the HUD")
	assert_eq(bar.call("visible_text"), "", "hidden without a boss in the fight")
	p.camera_rig.yaw = 0.0
	p.targeting.try_lock()
	assert_eq(p.lock.target_id, "test.king_hud", "locked on the king")
	await get_tree().process_frame
	await get_tree().process_frame
	assert_true(bool(bar.call("shows_entity", king.entity)), "the boss bar shows the locked king")
	assert_true(str(bar.call("visible_text")).begins_with("Ogre King  1500 / 1500  phase 1/2"),
		"name, health and phase: %s" % bar.call("visible_text"))
	assert_eq(bar.call("phase_pips"), [true, false] as Array[bool], "two pips, the first lit")
	assert_false(hud.target_frame_visible(), "the HUD hides its target frame for the boss")
	var cam := p.camera_rig.camera
	var knee := _lowest(king.entity.lock_anchors()).global_position
	if not cam.is_position_behind(knee):
		assert_true(hud.lock_marker_point().distance_to(cam.unproject_position(knee)) < 1.0,
			"the lock marker sits on the knee")
	# Phase 2 lights the second pip.
	king.entity.combatant.pools.health = 700.0
	await step_ticks(2)
	await get_tree().process_frame
	assert_eq(bar.call("phase_pips"), [true, true] as Array[bool], "phase 2: both pips lit")
	# A soldier gets the ordinary target frame.
	p.targeting.release_lock("manual")
	p.camera_rig.yaw = TargetingRules.yaw_of(s.global_position - p.global_position)
	await get_tree().process_frame
	p.targeting.try_lock()
	assert_eq(p.lock.target_id, "test.soldier_hud", "locked on the soldier")
	await get_tree().process_frame
	await get_tree().process_frame
	assert_true(hud.target_frame_visible(), "the target frame shows for a soldier")
	assert_eq(bar.call("visible_text"), "", "and the boss bar hides (no fight engaged)")
	# An engaged boss keeps its bar while another target is locked.
	Events.boss_engaged.emit(Sim.tick, "test.king_hud")
	await get_tree().process_frame
	assert_true(str(bar.call("visible_text")).begins_with("Ogre King"), "the engaged boss shows its bar")
	assert_true(hud.target_frame_visible(), "beside the soldier's target frame")
	Events.boss_defeated.emit(Sim.tick, "test.king_hud")
	await get_tree().process_frame
	assert_eq(bar.call("visible_text"), "", "defeated: the bar hides")
	assert_eq(BossBarProbe.thresholds(), [0.5] as Array[float], "a notch at the phase-2 threshold")


class BossBarProbe:
	static func thresholds() -> Array[float]:
		var script: GDScript = load("res://ui/hud/boss_bar.gd")
		return script.phase_thresholds(GameData.get_record("enemy.ogre_king"))
