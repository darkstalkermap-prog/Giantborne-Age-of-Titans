extends IntegrationSuite
## Spec 15: "First-person testing must include downward attacks against humans."


func test_first_person_downward_attacks_hit_a_human() -> void:
	var p := spawn_player(Vector3(0, 0.05, 0), 0.0)
	var s := spawn_soldier(Vector3(0.4, 0.05, -2.4), PI)
	await step_ticks(8)
	p.router.inject_edge(&"camera_toggle")
	await step_ticks(1)
	assert_true(p.camera_rig.is_first_person(), "first person")
	p.camera_rig.pitch = deg_to_rad(-60.0)  # looking down at the soldier at the giant's feet
	await step_ticks(1)
	var aim := p.camera_rig.aim_forward()
	assert_true(aim.y < -0.8, "camera aims steeply down (%.2f)" % aim.y)
	for i in 3:
		p.router.inject_light_attack()
		await step_ticks(40)
	var on := hits_on("soldier_01")
	assert_eq(on.size(), 3, "all three chained light attacks land on the human in first person")
	if on.size() == 3:
		assert_eq(on[0].event.action_id, "ability.light_1", "chain 1")
		assert_eq(on[1].event.action_id, "ability.light_2", "chain 2")
		assert_eq(on[2].event.action_id, "ability.light_3", "chain 3")
	# The light hits knocked the soldier back; put it at the giant's feet again for the heavy.
	await step_ticks(60)
	s.global_position = Vector3(0.4, 0.05, -2.4)
	await step_ticks(2)
	p.router.set_injected_hold(&"heavy_modifier", true)
	p.router.inject_light_attack()
	await step_ticks(2)
	p.router.set_injected_hold(&"heavy_modifier", false)
	await step_ticks(80)
	assert_eq(hits_on("soldier_01").size(), 4, "the overhead heavy also reaches a human at the giant's feet")
	assert_true(p.camera_rig.is_first_person(), "still first person; attack range unchanged by the camera")
