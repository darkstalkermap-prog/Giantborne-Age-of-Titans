extends IntegrationSuite
## Hit correctness in the real engine: entity de-duplication across hurtboxes, crowd hits,
## walls stopping attacks, worked-example numbers on the dummy, Heavy Footfall.


func _expected(r: HitResult, normal: int, crit: int) -> int:
	return crit if r.crit else normal


func test_one_sweep_three_hurtboxes_one_hit() -> void:
	var p := spawn_player(Vector3(0, 0.05, 0), 0.0)
	spawn_soldier(Vector3(0, 0.05, -2.8), PI)
	await step_ticks(3)
	var space := p.get_world_3d().direct_space_state
	var cands := HitQueryAdapter.sweep_capsule(space, p.entity, Vector3(0, 2.6, 0),
		Vector3(0, 0.1, -2.8), Vector3(0, 1.9, -2.8), Vector3(0, 0.1, -2.8), Vector3(0, 1.9, -2.8), 0.3)
	var regions := {}
	for c: Dictionary in cands:
		regions[(c.hurtbox as Hurtbox).region] = true
	assert_eq(regions.size(), 3, "one query overlaps head, torso and legs of one soldier")
	p.router.inject_light_attack()
	await step_ticks(45)
	var on := hits_on("soldier_01")
	assert_eq(on.size(), 1, "one light attack lands exactly one hit")
	if on.size() == 1:
		assert_eq(on[0].health_damage, _expected(on[0], 40, 60), "46 raw vs armor 15 = 40 (60 on a crit)")


func test_two_enemies_each_hit_once() -> void:
	var p := spawn_player(Vector3(0, 0.05, 0), 0.0)
	var a_pos := Vector3(2.8 * sin(deg_to_rad(25.0)), 0.05, -2.8 * cos(deg_to_rad(25.0)))
	var b_pos := Vector3(-a_pos.x, 0.05, a_pos.z)
	spawn_soldier(a_pos, yaw_towards(a_pos, Vector3.ZERO), "soldier_a")
	spawn_soldier(b_pos, yaw_towards(b_pos, Vector3.ZERO), "soldier_b")
	await step_ticks(3)
	p.router.inject_light_attack()
	await step_ticks(45)
	assert_eq(hits_on("soldier_a").size(), 1, "right-hand soldier hit once")
	assert_eq(hits_on("soldier_b").size(), 1, "left-hand soldier hit once")
	assert_near(p.entity.combatant.pools.fury, 4.0, 1e-6, "crowd hits by one basic attack award fury once (4)")


func test_wall_stops_attack() -> void:
	var p := spawn_player(Vector3(0, 0.05, 0), 0.0)
	spawn_dummy(Vector3(0, 0, -2.6), "dummy_open")
	await step_ticks(2)
	p.router.inject_light_attack()
	await step_ticks(45)
	assert_eq(hits_on("dummy_open").size(), 1, "control: the same swing hits without a wall")
	world.queue_free()
	await get_tree().process_frame
	hits.clear()
	world = Node3D.new()
	add_child(world)
	add_box(Vector3(120, 1, 120), Vector3(0, -0.5, 0))
	var p2 := spawn_player(Vector3(0, 0.05, 0), 0.0)
	add_box(Vector3(6, 5, 0.4), Vector3(0, 2.5, -1.2))
	spawn_dummy(Vector3(0, 0, -2.6), "dummy_walled")
	await step_ticks(2)
	p2.router.inject_light_attack()
	await step_ticks(45)
	assert_eq(hits_on("dummy_walled").size(), 0, "a wall between attacker and target stops the hit")
	assert_true(clanks >= 1, "the swing reports a clank on the wall")


func test_dummy_shows_worked_example_numbers() -> void:
	var p := spawn_player(Vector3(0, 0.05, 0), 0.0)
	spawn_dummy(Vector3(0, 0, -2.6))
	await step_ticks(2)
	p.router.inject_light_attack()
	await step_ticks(60)
	p.router.set_injected_hold(&"heavy_modifier", true)
	p.router.inject_light_attack()
	await step_ticks(2)
	p.router.set_injected_hold(&"heavy_modifier", false)
	await step_ticks(80)
	var on := hits_on("dummy_01")
	assert_eq(on.size(), 2, "light then heavy both land")
	if on.size() == 2:
		assert_eq(on[0].health_damage, _expected(on[0], 37, 55), "light vs armor 25 = 37")
		assert_eq(on[1].health_damage, _expected(on[1], 66, 99), "heavy vs armor 25 = 66")
		assert_eq(on[1].event.action_id, "ability.heavy_1", "Shift + light produced a heavy")
	assert_eq(started.count("player:ability.light_1"), 1, "Shift + light never also issues a light attack")


func test_heavy_footfall_area() -> void:
	var p := spawn_player(Vector3(0, 0.05, 0), 0.0)
	spawn_dummy(Vector3(0, 0, -2.2), "in_front")
	spawn_dummy(Vector3(1.5, 0, 1.8), "behind")
	spawn_dummy(Vector3(-4.2, 0, 0), "outside")
	spawn_dummy(Vector3(0, 0, 2.8), "walled")
	add_box(Vector3(3, 4, 0.3), Vector3(0, 2, 2.15))
	await step_ticks(2)
	var stamina := p.entity.combatant.pools.stamina
	p.router.inject_edge(&"slot_1")
	await step_ticks(40)
	assert_eq(hits_on("in_front").size(), 1, "front dummy hit once")
	assert_eq(hits_on("behind").size(), 1, "dummy behind the giant hit once (area)")
	assert_eq(hits_on("outside").size(), 0, "dummy outside 3 m not hit")
	assert_eq(hits_on("walled").size(), 0, "dummy behind a wall not hit")
	if hits_on("in_front").size() == 1:
		assert_eq(hits_on("in_front")[0].health_damage, 44, "55.2 raw vs armor 25 = 44")
	assert_near(stamina - p.entity.combatant.pools.stamina, 20.0, 0.5, "costs 20 stamina once")
	assert_near(p.controller.cooldowns.remaining_s("ability.heavy_footfall", Sim.tick), 8.0 - 40.0 / 60.0, 0.05, "8 s cooldown started on acceptance")
	p.router.inject_edge(&"slot_1")
	await step_ticks(40)
	assert_eq(hits_on("in_front").size(), 1, "cooldown prevents a second activation")
