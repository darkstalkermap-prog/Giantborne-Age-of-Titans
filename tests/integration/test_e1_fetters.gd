extends IntegrationSuite
## E1 (decision E1-2): the fetters' rules - PlayerFetter and the fetter-winch, without Orrik. A winch's harpoon that
## strikes the giant binds its chain (not a blocked one); one chain slows him, two bind his legs (no dodge, jump or
## sprint), three pin him (Events.giant_pinned); the chain holds him to its circle; his pull against it strains it by his
## size and tears it (a stage-9 colossus fastest, stage 7 slowly); a heavy begun while bound heaves the tautest chain
## (torn at once from stage 8, half at 7); a torn winch's chain wrenches it out of the ground; a winch holds its fire
## while its chain is on him; a destroyed winch lets its chain go; death frees him. The Fetterer set's passive strains
## faster.

const WINCH := "res://scenes/world/fetter_winch.tscn"


func before_each() -> void:
	await super()
	GameSession.expansion = ExpansionState.defaults()


func after_each() -> void:
	GameSession.expansion = ExpansionState.defaults()
	await super()


func _player(stage := 8) -> GiantPlayer:
	var p := spawn_player(Vector3(0, 0.05, 0), 0.0)
	await TestWait.until(self, func() -> bool: return p.is_on_floor(), 30)
	TitanDuel.prepare(p, stage)
	p.router.use_injection = true
	await step_ticks(2)
	return p


func _winch(at: Vector3, id := "test.e1.winch_a") -> FetterWinch:
	var w := (load(WINCH) as PackedScene).instantiate() as FetterWinch
	w.world_id = id
	w.position = at
	world.add_child(w)
	return w


func _harpoon(p: GiantPlayer, w: FetterWinch, blocked := false) -> void:
	var h := HitEvent.new()
	h.tick = Sim.tick
	h.instance_id = Sim.new_instance_id()
	h.attacker_id = w.entity.entity_id
	h.target_id = p.entity.entity_id
	h.action_id = "ability.fetter_harpoon"
	h.power = 45.0
	h.size_policy = "none"
	h.category = "siege"
	h.from_projectile = true
	h.tags = PackedStringArray(["Ranged", "Projectile", "Siege", "Unparryable"])
	h.attacker_position = w.global_position
	h.hit_point = p.global_position + Vector3.UP * 3.0
	if blocked:
		p.controller.call("_finish_action", true)
	Sim.queue_hit(h)
	await step_ticks(2)


func test_a_harpoon_binds_its_chain_and_the_count_decides() -> void:
	var p := await _player(8)
	var a := _winch(Vector3(0, 0, -60), "test.e1.winch_a")
	var b := _winch(Vector3(60, 0, 0), "test.e1.winch_b")
	var c := _winch(Vector3(-60, 0, 0), "test.e1.winch_c")
	await step_ticks(2)
	await _harpoon(p, a)
	assert_eq(p.fetter.count(), 1, "the harpoon bit: one chain")
	assert_true(p.fetter.holds(a.entity.entity_id), "its chain runs to its winch")
	assert_near(p.motor.speed_mult_sources().get(&"fetter", 1.0), PlayerFetter.SLOW_BY_COUNT[1], 1e-6, "one chain slows him")
	assert_false(p.fetter.is_bound(), "one chain does not bind his legs")
	assert_false(a.can_shoot(), "a winch holds its fire while its chain is on him")
	assert_true(b.can_shoot(), "another winch may shoot")
	await _harpoon(p, a)
	assert_eq(p.fetter.count(), 1, "one chain a winch")
	await _harpoon(p, b)
	assert_true(p.fetter.is_bound(), "two chains bind his legs")
	assert_true(p.fetter.handle_edge(&"dodge"), "bound: no dodge")
	assert_true(p.fetter.handle_edge(&"jump"), "bound: no jump")
	var pinned := []
	Events.giant_pinned.connect(func(_t: int, _id: String, on: bool) -> void: pinned.append(on))
	await _harpoon(p, c)
	assert_true(p.fetter.is_pinned(), "three chains pin him")
	assert_eq(pinned, [true], "Events.giant_pinned")
	assert_near(p.motor.speed_mult_sources().get(&"fetter", 1.0), PlayerFetter.SLOW_BY_COUNT[3], 1e-6, "pinned: barely moving")
	p.entity.combatant.pools.health = 0.0
	p.entity.combatant.dead = true
	Events.entity_died.emit(Sim.tick, p.entity.entity_id, "")
	assert_eq(p.fetter.count(), 0, "death frees him")


func test_the_chain_holds_him_to_its_circle() -> void:
	var p := await _player(8)
	var w := _winch(Vector3(0, 0, -40))
	await step_ticks(2)
	await _harpoon(p, w)
	var length := float((p.fetter.fetters[0] as Dictionary).length)
	assert_near(length, 40.0 + PlayerFetter.SLACK_M, 0.6, "the chain paid out to where he stood, and its slack")
	# walk straight away from the winch for 6 s
	p.router.set_injected_move(Vector2(0, -1))
	for i in 360:
		await step_ticks(1)
		if p.fetter.count() == 0:
			break
	var d := Vector2(p.global_position.x, p.global_position.z + 40.0).length()
	assert_true(d <= length + 0.8, "held to the circle (%.1f m of %.1f)" % [d, length])
	p.router.set_injected_move(Vector2.ZERO)


func test_his_pull_tears_a_chain_by_his_size() -> void:
	var times := {}
	for stage: int in [7, 8, 9]:
		var p := await _player(stage)
		var w := _winch(Vector3(0, 0, -30), "test.e1.pull_%d" % stage)
		await step_ticks(2)
		await _harpoon(p, w)
		var start := Sim.tick
		p.router.set_injected_move(Vector2(0, -1))
		while p.fetter.count() > 0 and Sim.tick - start < 60 * 12:
			await step_ticks(1)
		p.router.set_injected_move(Vector2.ZERO)
		times[stage] = (Sim.tick - start) / 60.0
		assert_eq(p.fetter.count(), 0, "stage %d tore it by pulling" % stage)
		assert_eq(p.fetter.torn_pull, 1, "stage %d: a pull" % stage)
		await step_ticks(2)
		assert_true(w.destroyed, "stage %d: the torn chain wrenched its winch out of the ground" % stage)
		p.queue_free()
		w.queue_free()
		await step_ticks(2)
	assert_true(float(times[9]) < float(times[8]) and float(times[8]) < float(times[7]),
		"a bigger colossus tears it sooner (%s)" % str(times))
	assert_true(float(times[8]) < 3.0, "stage 8 within about two seconds of pulling (%.2f s)" % float(times[8]))
	assert_true(float(times[7]) > 3.0, "stage 7 strains for longer (%.2f s)" % float(times[7]))


func test_a_heave_tears_the_tautest_chain() -> void:
	var p := await _player(8)
	var a := _winch(Vector3(0, 0, -50), "test.e1.heave_a")
	var b := _winch(Vector3(50, 0, 0), "test.e1.heave_b")
	await step_ticks(2)
	await _harpoon(p, a)
	await _harpoon(p, b)
	var heavy := GameData.get_action(str(p.controller.loadout.get("heavy", "")))
	assert_true(heavy != null and heavy.has_tag("Heavy"), "his heavy")
	p.fetter.on_action_started(heavy, 1)
	assert_eq(p.fetter.count(), 1, "stage 8: a heave tears a chain at once")
	assert_eq(p.fetter.torn_heave, 1, "a heave")
	p.fetter.release_all("cut")
	p.queue_free()
	await step_ticks(2)
	var p7 := await _player(7)
	var c := _winch(Vector3(0, 0, 50), "test.e1.heave_c")
	await step_ticks(2)
	await _harpoon(p7, c)
	p7.fetter.on_action_started(heavy, 2)
	assert_eq(p7.fetter.count(), 1, "stage 7: one heave is half a chain")
	assert_near(p7.fetter.max_strain(), 0.5, 1e-6, "half strained")
	p7.fetter.on_action_started(heavy, 3)
	assert_eq(p7.fetter.count(), 0, "the second heave tears it")


func test_a_destroyed_winch_lets_its_chain_go_and_the_set_strains_faster() -> void:
	var p := await _player(8)
	var w := _winch(Vector3(0, 0, -40), "test.e1.broken")
	await step_ticks(2)
	await _harpoon(p, w)
	assert_eq(p.fetter.count(), 1, "bound")
	w.chain_torn(p)   # (the winch broken by another hand: the chain goes with it)
	await step_ticks(3)
	assert_true(w.destroyed, "the winch broken")
	assert_eq(p.fetter.count(), 0, "its chain went")
	assert_near(p.fetter.strain_rate(), float(PlayerFetter.STRAIN_PER_S_BY_STAGE[8]), 1e-6, "his stage's pull")
	p.entity.combatant.set_passives({"fetter_strain_mult": 1.35})
	assert_near(p.fetter.strain_rate(), float(PlayerFetter.STRAIN_PER_S_BY_STAGE[8]) * 1.35, 1e-6,
		"the Fetterer set's passive strains faster")
