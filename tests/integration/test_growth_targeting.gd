extends IntegrationSuite
## Targeting across growth (plan §3.5): the lock range and half-angle follow the stage (35 / 40 /
## 45 m, 60 / 55 / 50 degrees); at stage 2 a target 38 m away is lockable and the lock lets go
## beyond 50 m (1.25 x the range); switching the camera at stage 3 in the middle of a heavy keeps
## the giant's position, resources, lock target and the attack's timing; soft targeting reaches
## as far as the stage's melee reach (+ 1.5 m).


func _grounded_player(pos: Vector3, yaw := 0.0) -> GiantPlayer:
	var p := spawn_player(pos, yaw)
	await TestWait.until(self, func() -> bool: return p.is_on_floor(), 30)
	await step_ticks(1)
	return p


func _lock(p: GiantPlayer) -> String:
	p.router.inject_edge(&"lock_press")
	await step_ticks(1)
	return p.lock.target_id


func _release(p: GiantPlayer) -> void:
	if p.lock.is_locked():
		p.targeting.release_lock("manual")
	await step_ticks(1)


func test_lock_range_follows_the_stage() -> void:
	var p := await _grounded_player(Vector3(0, 0.05, 0))
	var d := spawn_dummy(Vector3(0, 0, -38), "test.far_dummy")
	p.camera_rig.yaw = 0.0
	await step_ticks(3)
	assert_eq(await _lock(p), "", "stage 1 (35 m): a target 38 m away is out of range")
	assert_true(p.growth.debug_set_stage(2).ok, "stage 2")
	await step_ticks(2)
	assert_eq(await _lock(p), "test.far_dummy", "stage 2 (40 m): the target 38 m away locks")
	d.global_position = Vector3(0, 0, -49)
	await step_ticks(3)
	assert_eq(p.lock.target_id, "test.far_dummy", "still held at 49 m (release beyond 1.25 x 40 = 50 m)")
	var released := false
	for e: Array in lock_events:
		if e[3] == "out_of_range":
			released = true
	assert_false(released, "no out-of-range release yet")
	d.global_position = Vector3(0, 0, -51.5)
	await step_ticks(3)
	assert_eq(p.lock.target_id, "", "released beyond 50 m")
	assert_eq(lock_events.back()[3], "out_of_range", "as out of range")
	assert_true(p.growth.debug_set_stage(3).ok, "stage 3")
	d.global_position = Vector3(0, 0, -43)
	await step_ticks(3)
	assert_eq(await _lock(p), "test.far_dummy", "stage 3 (45 m): 43 m locks")
	await _release(p)
	assert_true(p.growth.debug_set_stage(1).ok, "back to stage 1")
	await step_ticks(2)
	assert_eq(await _lock(p), "", "and 43 m is out of a stage-1 giant's range again")


func test_lock_half_angle_follows_the_stage() -> void:
	var p := await _grounded_player(Vector3(0, 0.05, 0))
	var bearing := deg_to_rad(57.0)   # inside stage 1's 60 degrees, outside 55 and 50
	spawn_dummy(Vector3(-10.0 * sin(bearing), 0, -10.0 * cos(bearing)), "test.side_dummy")
	p.camera_rig.yaw = 0.0
	await step_ticks(3)
	assert_eq(await _lock(p), "test.side_dummy", "stage 1 (60 degrees) locks a target 57 degrees off the aim")
	await _release(p)
	for stage in [2, 3]:
		assert_true(p.growth.debug_set_stage(stage).ok, "stage %d" % stage)
		p.camera_rig.yaw = 0.0
		await step_ticks(3)
		assert_near(p.lock.half_angle_deg, float(p.profile.lock_half_angle_deg), 1e-6, "stage %d half-angle" % stage)
		assert_eq(await _lock(p), "", "stage %d (%.0f degrees) does not" % [stage, p.lock.half_angle_deg])


## Switching to first person and back at stage 3 in the middle of a heavy changes nothing about
## the fight: the hit lands on the same tick with the same damage, the giant has not moved, the
## stamina is the same and the lock stays on its target.
func test_camera_switch_at_stage_3_keeps_position_resources_target_and_timing() -> void:
	var runs: Array[Dictionary] = []
	for switch in [false, true]:
		Settings.session["camera_mode"] = 0
		var p := await _grounded_player(Vector3(0, 0.05, 0))
		assert_true(p.growth.debug_set_stage(3).ok, "stage 3")
		var id := "test.switch_dummy_%d" % runs.size()
		var dummy := spawn_dummy(Vector3(0, 0, -3.9), id)
		p.camera_rig.yaw = 0.0
		await step_ticks(3)
		assert_eq(await _lock(p), id, "locked")
		hits.clear()
		var pos := p.global_position
		p.router.inject_edge(&"heavy")
		await step_ticks(1)
		var start := Sim.tick
		var stamina_after_cost := p.entity.combatant.pools.stamina
		assert_eq(p.controller.action_id(), "ability.heavy_1", "the heavy started")
		await step_ticks(10)
		if switch:
			p.router.inject_edge(&"camera_toggle")
			await step_ticks(1)
			assert_true(p.camera_rig.is_first_person(), "first person mid-windup")
		await TestWait.until(self, func() -> bool: return not hits_on(id).is_empty(), 60)
		var landed := hits_on(id)
		var out := {"hit_tick": landed[0].event.tick - start if not landed.is_empty() else -1,
			"damage": landed[0].health_damage if not landed.is_empty() else -1.0,
			"moved": p.global_position.distance_to(pos), "locked_on_hit": p.lock.target_id == id,
			"stamina": stamina_after_cost}
		if switch:
			p.router.inject_edge(&"camera_toggle")
			await step_ticks(1)
			assert_false(p.camera_rig.is_first_person(), "back to third person in the recovery")
		var ended: bool = await TestWait.until(self, func() -> bool: return p.controller.action == null, 90)
		assert_true(ended, "the heavy finishes")
		out["end_tick"] = Sim.tick - start
		out["locked_after"] = p.lock.target_id == id
		runs.append(out)
		p.queue_free()
		dummy.queue_free()
		await step_ticks(2)
	var a: Dictionary = runs[0]
	var b: Dictionary = runs[1]
	assert_true(int(a.hit_tick) > 0, "the heavy lands on the dummy (tick %d)" % a.hit_tick)
	assert_eq(b.hit_tick, a.hit_tick, "the camera switch keeps the attack timing (hit on the same tick)")
	assert_eq(b.end_tick, a.end_tick, "and the recovery ends on the same tick")
	assert_near(float(b.damage), float(a.damage), 1e-6, "same damage")
	assert_near(float(b.moved), float(a.moved), 1e-3, "the giant has not moved (%.4f m)" % b.moved)
	assert_near(float(b.stamina), float(a.stamina), 1e-6, "same resources")
	assert_true(a.locked_on_hit and b.locked_on_hit, "the lock is kept through the switch")
	assert_true(a.locked_after and b.locked_after, "and through switching back")


## Soft targeting looks for targets within melee_reach_m + 1.5 m: a stage-3 giant (6.5 m)
## turns its windup toward a soldier 7 m away and 25 degrees off; a stage-1 giant (3.5 m) does
## not.
func test_soft_target_reach_follows_the_stage() -> void:
	var offsets: Array[float] = []
	for stage in [1, 3]:
		var p := await _grounded_player(Vector3(0, 0.05, 0))
		if stage != 1:
			assert_true(p.growth.debug_set_stage(stage).ok, "stage %d" % stage)
		var t := deg_to_rad(25.0)
		var soldier := spawn_soldier(Vector3(-7.0 * sin(t), 0.05, -7.0 * cos(t)), 0.0, "test.soft_%d" % stage)
		p.camera_rig.yaw = 0.0
		await step_ticks(3)
		p.router.inject_light_attack()
		await step_ticks(1)
		await TestWait.until(self, func() -> bool: return p.controller.phase() != ActionDef.Phase.WINDUP, 30)
		offsets.append(absf(rad_to_deg(angle_difference(0.0, p.facing_yaw))))
		p.queue_free()
		soldier.queue_free()
		await step_ticks(30)
	assert_true(offsets[0] < 0.5, "stage 1: no nudge toward a soldier 7 m away (%.1f degrees)" % offsets[0])
	assert_true(offsets[1] > 5.0, "stage 3: the windup turns toward it (%.1f degrees)" % offsets[1])
