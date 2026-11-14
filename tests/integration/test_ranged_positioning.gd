extends IntegrationSuite
## P22 (plan M6-M9 §3.4 design 8): ranged units keep to the camera's side. An archer or mage
## (tactics.front_arc_deg 150) takes a new firing point in front of the giant's camera - its
## bearing from the target within 75 degrees of the camera's yaw - before the P09 search; it gives
## up a held point that left the arc once the camera has turned (at most every 3 s); and a shot
## drawn from outside the camera's view aims for tactics.off_camera_aim_s (1.2 s) instead of its
## windup (0.9 s for the archer), under the same action id.

const ARCHER := "res://scenes/enemies/archer.tscn"
const SHOT := "ability.archer_shot"


func _archer(pos: Vector3, id := "test.archer") -> ArcherEnemy:
	var a := (load(ARCHER) as PackedScene).instantiate() as ArcherEnemy
	a.entity_id = id
	a.ai_enabled = false
	a.position = pos
	world.add_child(a)
	return a


static func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


func test_the_front_arc_is_the_cameras_side_of_the_target() -> void:
	var t := Vector3(5, 0, 5)
	# Camera yaw 0 looks toward -Z: the arc is the half-space in front of the target, 75 deg each way.
	assert_true(EnemyBrain.in_front_arc(t + Vector3(0, 0, -20), t, 0.0, 150.0), "straight ahead")
	assert_true(EnemyBrain.in_front_arc(t + Vector3(10, 0, -10), t, 0.0, 150.0), "45 deg off")
	assert_false(EnemyBrain.in_front_arc(t + Vector3(20, 0, -5), t, 0.0, 150.0), "76 deg off")
	assert_false(EnemyBrain.in_front_arc(t + Vector3(0, 0, 20), t, 0.0, 150.0), "behind")
	assert_true(EnemyBrain.in_front_arc(t + Vector3(-20, 0, 0), t, PI * 0.5, 150.0), "the camera turned left")
	assert_true(EnemyBrain.in_front_arc(t, t, 0.0, 150.0), "on the target")


func test_an_archer_behind_the_camera_takes_a_point_in_front() -> void:
	var p := spawn_player(Vector3(0, 0.05, 0))
	var a := _archer(Vector3(3, 0.05, 18))
	await step_ticks(2)
	var view := a.camera_view()
	assert_false(view.is_empty(), "the giant's camera is seen")
	if view.is_empty():
		return
	assert_near(float(view.yaw), 0.0, 0.05, "it looks along -Z")
	assert_false(bool(view.on_camera), "the archer behind the giant is off camera")
	var cam := p.camera_rig.camera
	assert_true(EnemyActor.in_camera_view(cam, Vector3(0, 0, -20)), "ahead of the camera: in view")
	assert_false(EnemyActor.in_camera_view(cam, Vector3(0, 0, 40)), "behind it: not")
	var band := Vector2(12, 20)
	var target := p.global_position
	var pt := a.front_arc_firing_point(a.global_position, target, band, 6.0, false)
	assert_true(pt != Vector3.INF, "a point in the arc")
	if pt != Vector3.INF:
		assert_true(EnemyBrain.in_front_arc(pt, target, float(view.yaw), 150.0), "in front of the camera (%s)" % pt)
		var d := _flat(pt, target)
		assert_true(d >= band.x and d <= band.y, "in the band (%.1f m)" % d)
		assert_true(pt.x > 0.0, "on the archer's own side, nearest its bearing (%s)" % pt)
	# A record without front_arc_deg (or no camera) leaves the P09 search to it.
	var tactics: Dictionary = a.record.tactics
	var arc: Variant = tactics.get("front_arc_deg")
	tactics.erase("front_arc_deg")
	assert_true(a.front_arc_firing_point(a.global_position, target, band, 6.0, false) == Vector3.INF,
		"no front_arc_deg: no arc point")
	tactics["front_arc_deg"] = arc


func test_a_shot_drawn_off_camera_aims_longer() -> void:
	var a := _archer(Vector3(0, 0.05, -12))
	await step_ticks(1)
	var base := GameData.get_action(SHOT)
	assert_eq(base.windup_ticks, 54, "the archer's shot winds up 0.9 s")
	a.prepare_shot(SHOT, true)
	var off: ActionDef = a.controller.library[SHOT]
	assert_eq(off.windup_ticks, 72, "drawn off camera: off_camera_aim_s 1.2 s")
	assert_eq(off.id, SHOT, "the same action id (cooldowns, cues, metrics)")
	assert_near(float(off.params.get("tracking_fraction", 0.0)), float(base.params.get("tracking_fraction", 0.0)), 1e-6,
		"the aim still locks at its tracking fraction")
	a.prepare_shot(SHOT, false)
	assert_true(a.controller.library[SHOT] == base, "on camera: the record's own shot")
	# Through the brain: no camera (no giant here) reads as on camera.
	a.brain.prepare_ranged_shot(SHOT)
	assert_true(a.controller.library[SHOT] == base, "no camera: the record's own shot")


func test_a_held_point_out_of_the_arc_is_given_up_once_the_camera_turned() -> void:
	var b := ArcherBrain.new("test.archer_brain", GameData.get_record("enemy.archer"), 7)
	var yaw := [0.0]
	b.view_probe = func() -> Dictionary: return {"yaw": yaw[0], "on_camera": true}
	var released := [0]
	b.firing_point_release = func() -> void: released[0] += 1
	b.last_known = Vector3.ZERO
	b.state = EnemyBrain.AIState.APPROACH
	var held := Vector3(0, 0, 16)   # behind the target for yaw 0
	b.now = 1000
	b.firing_point = held
	b.keep_front_arc(Vector3.INF)   # a new pick: remembered with the camera's yaw
	assert_eq(b.firing_point, held, "a new point is kept")
	b.now = 1000 + 120
	b.keep_front_arc(held)
	assert_eq(b.firing_point, held, "within 3 s of the pick: kept")
	b.now = 1000 + 200
	b.keep_front_arc(held)
	assert_eq(b.firing_point, held, "the camera has not turned since the pick: kept (no better place)")
	yaw[0] = deg_to_rad(30.0)
	b.state = EnemyBrain.AIState.ATTACK
	b.keep_front_arc(held)
	assert_eq(b.firing_point, held, "not during a shot")
	b.state = EnemyBrain.AIState.APPROACH
	b.keep_front_arc(held)
	assert_eq(b.firing_point, Vector3.INF, "the camera turned 30 deg: the point out of the arc is given up")
	assert_eq(released[0], 1, "and released")
	var front := Vector3(0, 0, -16)
	b.firing_point = front
	b.keep_front_arc(Vector3.INF)
	b.now += 400
	yaw[0] = deg_to_rad(60.0)
	b.keep_front_arc(front)
	assert_eq(b.firing_point, front, "a point still in the arc is kept")
