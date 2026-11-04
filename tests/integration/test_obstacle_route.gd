extends IntegrationSuite
## Fixed obstacle route through the real sandbox (narrow doorway, low 4.2 m arch, 20 degree
## ramp onto a platform, past the test wall) in both camera modes. Checks that the giant
## fits and that the camera never ends up inside world geometry.

const ARENA := "res://scenes/world/sandbox_arena.tscn"
const ROUTE := [
	Vector3(-25, 0, 18), Vector3(-25, 0, 10), Vector3(-25, 0, 3),     # doorway 2.6 m wide
	Vector3(10, 0, 16), Vector3(25, 0, 12), Vector3(25, 0, 6), Vector3(25, 0, -1),  # low arch
	Vector3(36, 0, -6), Vector3(36, 0, -14), Vector3(36, 3, -23),     # ramp to platform
	Vector3(36, 3, -26), Vector3(36, 0, -6),                           # back down
	Vector3(-12.4, 0, 30), Vector3(-12.4, 0, 41),                      # along the test wall
]


func _run_route(first_person: bool) -> Dictionary:
	var arena: Node3D = (load(ARENA) as PackedScene).instantiate()
	world.add_child(arena)
	var soldier := arena.get_node("Soldier01") as SoldierEnemy
	soldier.ai_enabled = false
	var p := arena.get_node("Player") as GiantPlayer
	p.router.use_injection = true
	await step_ticks(5)
	if first_person:
		p.router.inject_edge(&"camera_toggle")
		await step_ticks(1)
	var space := p.get_world_3d().direct_space_state
	var q := PhysicsPointQueryParameters3D.new()
	q.collision_mask = HitQueryAdapter.OCCLUDER_MASK
	var inside_ticks := 0
	var reached := 0
	var worst := ""
	for wp: Vector3 in ROUTE:
		var ok := false
		for i in 15 * 60:
			var to := wp - p.global_position
			to.y = 0.0
			if to.length() < 1.2 and absf(wp.y - p.global_position.y) < 1.0:
				ok = true
				break
			p.camera_rig.yaw = TargetingRules.yaw_of(to)
			p.router.set_injected_move(Vector2(0, 1))
			await step_ticks(1)
			q.position = p.camera_rig.camera.global_position
			if not space.intersect_point(q, 1).is_empty():
				inside_ticks += 1
				worst = "camera inside geometry near %s" % q.position
		if not ok:
			worst = "could not reach %s (stuck at %s)" % [wp, p.global_position]
			break
		reached += 1
	p.router.set_injected_move(Vector2.ZERO)
	arena.queue_free()
	await step_ticks(2)
	return {"reached": reached, "inside": inside_ticks, "note": worst}


func test_route_third_person() -> void:
	var r: Dictionary = await _run_route(false)
	assert_eq(r.reached, ROUTE.size(), "third person: every waypoint reached (%s)" % r.note)
	assert_eq(r.inside, 0, "third person: camera never inside geometry (%s)" % r.note)


func test_route_first_person() -> void:
	var r: Dictionary = await _run_route(true)
	assert_eq(r.reached, ROUTE.size(), "first person: every waypoint reached (%s)" % r.note)
	assert_eq(r.inside, 0, "first person: camera never inside geometry (%s)" % r.note)
