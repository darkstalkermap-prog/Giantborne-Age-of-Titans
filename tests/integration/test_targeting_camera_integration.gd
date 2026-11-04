extends IntegrationSuite
## Lock-on acquisition/release, camera switching, camera collision, first-person eye height.


func test_lock_releases_on_death_same_tick() -> void:
	var p := spawn_player(Vector3(0, 0.05, 0), 0.0)
	var s := spawn_soldier(Vector3(0, 0.05, -6), PI)
	spawn_soldier(Vector3(3, 0.05, -8), PI, "soldier_other")
	await step_ticks(3)
	p.router.inject_edge(&"lock_press")
	await step_ticks(1)
	assert_eq(p.lock.target_id, "soldier_01", "locks the best-scored target (straight ahead)")
	s.entity.combatant.pools.health = 1.0
	queue_hit("player", "soldier_01", p.global_position, 40.0)
	await step_ticks(1)
	assert_true(deaths.has("soldier_01"), "target died")
	assert_eq(p.lock.target_id, "", "lock released immediately - no stale target")
	var released := false
	for e: Array in lock_events:
		if e[2] == "" and e[3] == "target_died":
			released = true
	assert_true(released, "lock_target_changed reports target_died")
	await step_ticks(30)
	assert_eq(p.lock.target_id, "", "no automatic re-acquisition of another target")


func test_lock_release_out_of_range_and_obstructed() -> void:
	var p := spawn_player(Vector3(0, 0.05, 0), 0.0)
	var s := spawn_soldier(Vector3(0, 0.05, -10), PI)
	await step_ticks(3)
	p.router.inject_edge(&"lock_press")
	await step_ticks(1)
	assert_eq(p.lock.target_id, "soldier_01", "locked")
	s.global_position = Vector3(0, 0.05, -44.5)
	await step_ticks(2)
	assert_eq(p.lock.target_id, "", "released beyond 1.25 x 35 m")
	s.global_position = Vector3(0, 0.05, -10)
	await step_ticks(2)
	p.router.inject_edge(&"lock_press")
	await step_ticks(1)
	assert_eq(p.lock.target_id, "soldier_01", "locked again on request")
	add_box(Vector3(8, 8, 0.5), Vector3(0, 4, -5))
	await step_ticks(44)
	assert_eq(p.lock.target_id, "soldier_01", "brief obstruction (< 0.75 s) keeps the lock")
	await step_ticks(4)
	assert_eq(p.lock.target_id, "", "continuous obstruction above 0.75 s releases")


func test_camera_switch_preserves_state() -> void:
	var p := spawn_player(Vector3(0, 0.05, 0), 0.0)
	spawn_soldier(Vector3(0, 0.05, -8), PI)
	await step_ticks(3)
	p.router.inject_edge(&"lock_press")
	await step_ticks(1)
	p.router.set_injected_hold(&"heavy_modifier", true)
	p.router.inject_light_attack()
	await step_ticks(5)
	p.router.set_injected_hold(&"heavy_modifier", false)
	var before := {"pos": p.global_position, "stamina": p.entity.combatant.pools.stamina,
		"instance": p.controller.instance_id, "elapsed": p.controller.elapsed,
		"target": p.lock.target_id, "action": p.controller.action_id()}
	p.router.inject_edge(&"camera_toggle")
	await step_ticks(1)
	assert_true(p.camera_rig.is_first_person(), "now first person")
	assert_true(p.global_position.distance_to(before.pos) < 0.05, "position preserved")
	assert_near(p.entity.combatant.pools.stamina, before.stamina, 1e-6, "resources preserved")
	assert_eq(p.controller.instance_id, before.instance, "same attack instance")
	assert_eq(p.controller.elapsed, before.elapsed + 1, "attack timing continues tick for tick")
	assert_eq(p.lock.target_id, before.target, "target identity preserved")
	assert_eq(p.controller.action_id(), before.action, "same action")
	p.router.inject_edge(&"camera_toggle")
	await step_ticks(1)
	assert_false(p.camera_rig.is_first_person(), "back to third person")


func test_third_person_camera_does_not_enter_wall() -> void:
	var p := spawn_player(Vector3(0, 0.05, 0), 0.0)
	add_box(Vector3(12, 8, 0.6), Vector3(0, 4, 2.3))
	await step_ticks(30)
	var cam := p.camera_rig.camera.global_position
	assert_true(cam.z < 2.0 - 0.3, "camera stays in front of the wall face (z=%.2f)" % cam.z)
	assert_true(p.camera_rig.obstructed, "arm reports an obstruction")
	var pivot := p.global_position + Vector3.UP * 3.35
	var clear := HitQueryAdapter.line_clear(p.get_world_3d().direct_space_state, pivot, cam,
		HitQueryAdapter.OCCLUDER_MASK, [])
	assert_true(clear, "line from pivot to camera is clear")


func test_first_person_eye_and_head_hidden() -> void:
	var p := spawn_player(Vector3(0, 0.05, 0), 0.0)
	await step_ticks(2)
	p.router.inject_edge(&"camera_toggle")
	await step_ticks(2)
	var eye_y := p.camera_rig.camera.global_position.y - p.global_position.y
	assert_near(eye_y, 3.6576 * 0.92, 0.1, "first-person eye at 92% of height")
	assert_eq(p.camera_rig.camera.cull_mask & 2, 0, "head render layer hidden in first person")
