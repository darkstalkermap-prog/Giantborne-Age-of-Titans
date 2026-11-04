extends IntegrationSuite
## Dodge, block, parry and guard break through the real resolution path and a real soldier.


func _wait_until(cond: Callable, max_ticks: int) -> bool:
	for i in max_ticks:
		if cond.call():
			return true
		await step_ticks(1)
	return cond.call()


func test_dodge_invulnerability_in_engine() -> void:
	for k in [5, 6, 17, 18]:
		var p := spawn_player(Vector3(0, 0.05, 0), 0.0)
		await step_ticks(8)  # settle onto the floor (dodge requires ground contact)
		p.router.inject_edge(&"dodge")
		await step_ticks(1)
		assert_eq(p.controller.state, CombatController.State.DODGING, "dodge accepted on the next tick")
		var ok: bool = await _wait_until(func() -> bool: return p.controller.elapsed >= k - 1, 30)
		assert_true(ok and p.controller.elapsed == k - 1, "reached dodge tick %d" % (k - 1))
		hits.clear()
		queue_hit("tester", "player", p.global_position + Vector3(0, 0, -2))
		await step_ticks(1)
		var expected := HitResult.Outcome.EVADED if (k >= 6 and k < 18) else HitResult.Outcome.HIT
		assert_true(hits.size() == 1 and hits[0].outcome == expected,
			"hit at dodge tick %d -> %s" % [k, HitResult.OUTCOME_NAMES[expected]])
		p.queue_free()
		await step_ticks(2)


func _setup_duel() -> Array:
	var p := spawn_player(Vector3(0, 0.05, 0), 0.0)
	var s := spawn_soldier(Vector3(0, 0.05, -1.9), PI)
	await step_ticks(3)
	return [p, s]


func test_parry_real_soldier_slash() -> void:
	var duel: Array = await _setup_duel()
	var p: GiantPlayer = duel[0]
	var s: SoldierEnemy = duel[1]
	s.controller.request(&"attack", {"action_id": "ability.soldier_slash"})
	var ok: bool = await _wait_until(func() -> bool: return s.controller.elapsed >= 31, 60)
	assert_true(ok, "soldier windup progressing")
	p.router.set_injected_hold(&"block", true)
	p.router.inject_edge(&"block_press")
	await step_ticks(30)
	var on := hits_on("player")
	assert_eq(on.size(), 1, "the slash connects once")
	if on.size() == 1:
		assert_eq(on[0].outcome, HitResult.Outcome.PARRIED, "block pressed just before the strike parries")
		assert_eq(on[0].health_damage, 0, "parry negates damage")
	assert_near(p.entity.combatant.pools.stamina, 90.0, 0.5, "5 entry + 5 parry")
	assert_near(p.entity.combatant.pools.fury, 6.0, 1e-6, "parry grants 6 fury")
	assert_eq(s.controller.state, CombatController.State.STAGGERED, "40 parry poise staggers a soldier (threshold 40)")


func test_late_block_is_ordinary_block() -> void:
	var duel: Array = await _setup_duel()
	var p: GiantPlayer = duel[0]
	var s: SoldierEnemy = duel[1]
	s.controller.request(&"attack", {"action_id": "ability.soldier_slash"})
	await _wait_until(func() -> bool: return s.controller.elapsed >= 12, 30)
	p.router.set_injected_hold(&"block", true)
	p.router.inject_edge(&"block_press")
	await step_ticks(40)
	var on := hits_on("player")
	assert_eq(on.size(), 1, "the slash connects once")
	if on.size() == 1:
		assert_eq(on[0].outcome, HitResult.Outcome.BLOCKED, "blocked outside the parry window")
		assert_eq(on[0].health_damage, 9, "34.5 * 0.25 = 8.6 -> 9")
		assert_near(on[0].stamina_damage, 9.0, 1e-6, "impact stamina ceil(8.625) = 9")
	assert_near(p.entity.combatant.pools.stamina, 100.0 - 5.0 - 9.0, 0.5, "entry 5 + impact 9")
	assert_eq(s.controller.state, CombatController.State.ATTACKING, "an ordinary block does not stagger the attacker")


func test_unblocked_slash_and_poise_scale() -> void:
	var duel: Array = await _setup_duel()
	var p: GiantPlayer = duel[0]
	var s: SoldierEnemy = duel[1]
	s.controller.request(&"attack", {"action_id": "ability.soldier_slash"})
	await step_ticks(60)
	var on := hits_on("player")
	assert_eq(on.size(), 1, "slash hits")
	if on.size() == 1:
		assert_eq(on[0].outcome, HitResult.Outcome.HIT, "unblocked")
		assert_eq(on[0].health_damage, 35, "30 * 1.15 = 34.5 -> 35 (player armor 0)")
		assert_near(on[0].poise_damage, 20.0 * 1.8 / 3.6576, 1e-4, "human vs giant poise scales by height ratio")
	assert_near(p.entity.combatant.pools.health, 465.0, 1e-6, "500 - 35")


func test_block_does_not_cover_back() -> void:
	var p := spawn_player(Vector3(0, 0.05, 0), 0.0)
	await step_ticks(2)
	p.router.set_injected_hold(&"block", true)
	p.router.inject_edge(&"block_press")
	await step_ticks(20)
	queue_hit("tester", "player", p.global_position + Vector3(0, 0, 3), 40.0)
	await step_ticks(1)
	assert_true(hits.size() == 1 and hits[0].outcome == HitResult.Outcome.HIT, "hit from behind is not blocked")


func test_guard_break_staggers() -> void:
	var p := spawn_player(Vector3(0, 0.05, 0), 0.0)
	await step_ticks(2)
	p.router.set_injected_hold(&"block", true)
	p.router.inject_edge(&"block_press")
	await step_ticks(20)
	p.entity.combatant.pools.stamina = 4.0
	queue_hit("tester", "player", p.global_position + Vector3(0, 0, -3), 60.0)
	await step_ticks(1)
	assert_true(hits.size() == 1 and hits[0].outcome == HitResult.Outcome.GUARD_BROKEN, "guard broken")
	assert_near(p.entity.combatant.pools.stamina, 0.0, 1e-9, "remaining stamina consumed, never negative")
	assert_eq(p.controller.state, CombatController.State.STAGGERED, "1.0 s stagger")
	await step_ticks(61)
	assert_eq(p.controller.state, CombatController.State.LOCOMOTION, "recovers after 1.0 s")
