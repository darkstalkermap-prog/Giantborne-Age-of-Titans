extends IntegrationSuite
## Breakable fence and loot, debris cap, death, stamina floor, input routing and contexts,
## and soldier AI engagement/attack tokens.


func test_fence_breaks_once_and_loot_once() -> void:
	var p := spawn_player(Vector3(0, 0.05, 0), 0.0)
	var f := spawn_fence(Vector3(0, 0, -2.8))
	await step_ticks(2)
	p.router.set_injected_hold(&"heavy_modifier", true)
	p.router.inject_light_attack()
	await step_ticks(2)
	p.router.set_injected_hold(&"heavy_modifier", false)
	await step_ticks(80)
	assert_true(f.destroyed, "heavy (83) breaks the 80 hp fence")
	assert_eq(destroyed, ["test.fence_01"] as Array[String], "ObjectDestroyed emitted once")
	assert_eq(loot.size(), 1, "loot awarded once")
	assert_false(is_instance_valid(f.get_node_or_null("BlockShape")), "blocking collision removed")
	p.router.inject_light_attack()
	await step_ticks(50)
	assert_eq(destroyed.size(), 1, "hitting the wreck does not destroy it again")
	assert_eq(loot.size(), 1, "and never awards loot again")
	f.queue_free()  # simulate a reload: the old instance is gone, the world delta remains
	await step_ticks(2)
	var again := spawn_fence(Vector3(10, 0, 0), "test.fence_01")
	await step_ticks(2)
	assert_true(again.destroyed, "a reloaded fence with the same world id starts broken")
	assert_eq(loot.size(), 1, "reload does not respawn loot")


func test_debris_pool_caps_and_cleans_up() -> void:
	var pool := DebrisPool.new()
	world.add_child(pool)
	await step_ticks(1)
	var ts: Array[Transform3D] = []
	var vs: Array[Vector3] = []
	for i in 60:
		ts.append(Transform3D(Basis(), Vector3(i % 10, 3 + i / 10, 0)))
		vs.append(Vector3.UP)
	pool.spawn(ts, vs)
	assert_true(pool.active_count() <= DebrisPool.MAX_ACTIVE, "never more than 40 active pieces")
	await step_ticks(int(DebrisPool.LIFETIME_S * 60) + 5)
	assert_eq(pool.active_count(), 0, "all debris removed after 5 s")


func test_player_death_is_final_until_reset() -> void:
	var p := spawn_player(Vector3(0, 0.05, 0), 0.0)
	await step_ticks(2)
	p.entity.combatant.pools.health = 5.0
	queue_hit("tester", "player", Vector3(0, 0, -2), 40.0)
	await step_ticks(1)
	assert_eq(p.controller.state, CombatController.State.DEAD, "dead")
	assert_eq(deaths.count("player"), 1, "EntityDied once")
	queue_hit("tester", "player", Vector3(0, 0, -2), 40.0)
	await step_ticks(1)
	assert_eq(deaths.count("player"), 1, "a dead target dies only once")
	assert_eq(hits.size(), 1, "hits on a dead target are ignored (no events, no resources)")
	var stamina := p.entity.combatant.pools.stamina
	p.router.inject_light_attack()
	p.router.inject_edge(&"dodge")
	await step_ticks(3)
	assert_eq(p.controller.state, CombatController.State.DEAD, "inputs ignored while dead")
	assert_near(p.entity.combatant.pools.stamina, stamina, 1e-9, "nothing spent while dead")


func test_stamina_never_negative_in_play() -> void:
	var p := spawn_player(Vector3(0, 0.05, 0), 0.0)
	await step_ticks(2)
	p.router.set_injected_move(Vector2(0, 1))
	p.router.set_injected_hold(&"sprint", true)
	var min_seen := 100.0
	for i in 600:
		if i % 7 == 0:
			p.router.inject_light_attack()
		if i % 23 == 0:
			p.router.inject_edge(&"dodge")
		if i % 41 == 0:
			p.router.inject_edge(&"slot_1")
		await step_ticks(1)
		min_seen = minf(min_seen, p.entity.combatant.pools.stamina)
	assert_true(min_seen >= 0.0, "stamina stayed >= 0 (min %.3f)" % min_seen)
	assert_true(min_seen < 10.0, "the test really exhausted stamina (min %.3f)" % min_seen)


func test_input_feedback_on_next_tick() -> void:
	var p := spawn_player(Vector3(0, 0.05, 0), 0.0)
	await step_ticks(2)
	var t0 := Sim.tick
	p.router.inject_light_attack()
	await step_ticks(1)
	assert_eq(Sim.tick, t0 + 1, "one tick later")
	assert_true(started.has("player:ability.light_1"), "AbilityStarted on the next tick")
	assert_eq(p.controller.state, CombatController.State.ATTACKING, "attacking on the next tick")


func test_real_input_events_and_contexts() -> void:
	var router := InputRouter.new()
	world.add_child(router)
	await get_tree().process_frame
	var press := InputEventAction.new()
	press.action = "attack_light"
	press.pressed = true
	Input.parse_input_event(press)
	await get_tree().process_frame
	assert_eq(router.consume().edges, [&"light"] as Array, "LMB alone -> one light attack")
	Input.action_press("heavy_modifier")
	Input.parse_input_event(press)
	await get_tree().process_frame
	assert_eq(router.consume().edges, [&"heavy"] as Array, "Shift + LMB -> exactly one heavy, no light")
	Input.action_release("heavy_modifier")
	InputRouter.set_context(InputRouter.Context.MENU)
	Input.parse_input_event(press)
	await get_tree().process_frame
	assert_eq(router.consume().edges, [] as Array, "pause/menu context suppresses gameplay input")
	InputRouter.set_context(InputRouter.Context.GAMEPLAY)
	Input.action_press("ability_modifier")
	var b := InputEventJoypadButton.new()
	b.button_index = JOY_BUTTON_B
	b.pressed = true
	Input.parse_input_event(b)
	await get_tree().process_frame
	assert_eq(router.consume().edges, [&"slot_2"] as Array, "LT + B uses slot 2 and does not dodge")
	var up := InputEventJoypadButton.new()
	up.button_index = JOY_BUTTON_DPAD_UP
	up.pressed = true
	Input.parse_input_event(up)
	await get_tree().process_frame
	assert_eq(router.consume().edges, [&"slot_5"] as Array, "LT + Up uses slot 5 and does not switch camera")
	var rt := InputEventJoypadMotion.new()
	rt.axis = JOY_AXIS_TRIGGER_RIGHT
	rt.axis_value = 1.0
	Input.parse_input_event(rt)
	await get_tree().process_frame
	assert_eq(router.consume().edges, [&"ultimate"] as Array, "LT + RT is the ultimate, not a heavy attack")
	Input.action_release("ability_modifier")
	rt.axis_value = 0.0
	Input.parse_input_event(rt)
	b.pressed = false
	Input.parse_input_event(b)
	up.pressed = false
	Input.parse_input_event(up)
	var b2 := InputEventJoypadButton.new()
	b2.button_index = JOY_BUTTON_B
	b2.pressed = true
	Input.parse_input_event(b2)
	await get_tree().process_frame
	assert_eq(router.consume().edges, [&"dodge"] as Array, "B alone dodges")
	b2.pressed = false
	Input.parse_input_event(b2)
	press.pressed = false
	Input.parse_input_event(press)
	await get_tree().process_frame


func test_soldier_engages_with_readable_attacks() -> void:
	var p := spawn_player(Vector3(0, 0.05, 0), 0.0)
	var s := spawn_soldier(Vector3(0, 0.05, -12), PI, "soldier_01", true)
	await step_ticks(2)
	var saw_attack := false
	var windup_ticks := 0
	var yaw_at_commit := INF
	var turned_after_commit := false
	# Phase 1: the giant strafes during the soldier's first strike; the soldier may track only
	# during the early windup and must not rotate after committing.
	for i in 600:
		await step_ticks(1)
		var a := s.controller.action
		if a == null:
			if saw_attack:
				break
			continue
		saw_attack = true
		windup_ticks = a.windup_ticks
		p.router.set_injected_move(Vector2(1, 0))
		var track_end := int(a.windup_ticks * a.tracking_fraction)
		if s.controller.elapsed == track_end:
			yaw_at_commit = s.rotation.y
		elif s.controller.elapsed > track_end and yaw_at_commit != INF \
				and absf(angle_difference(yaw_at_commit, s.rotation.y)) > 0.001:
			turned_after_commit = true
	p.router.set_injected_move(Vector2.ZERO)
	assert_true(saw_attack, "soldier noticed, approached and attacked within 10 s")
	assert_true(windup_ticks >= 27, "melee windup at least 0.45 s (%d ticks)" % windup_ticks)
	assert_false(turned_after_commit, "no rotation after committing to the strike")
	# Phase 2: the giant stands still; a later strike connects.
	for i in 900:
		await step_ticks(1)
		if hits_on("player").size() > 0:
			break
	assert_true(hits_on("player").size() >= 1, "the soldier's attack lands on a stationary giant")


func test_attack_tokens_limit_attackers() -> void:
	spawn_player(Vector3(0, 0.05, 0), 0.0)
	for i in 3:
		var pos := Vector3(cos(i * 2.1) * 5.0, 0.05, sin(i * 2.1) * 5.0)
		spawn_soldier(pos, yaw_towards(pos, Vector3.ZERO), "soldier_%02d" % i, true)
	await step_ticks(2)
	var max_holders := 0
	for i in 480:
		await step_ticks(1)
		max_holders = maxi(max_holders, Sim.token_holders("player").size())
	assert_true(max_holders >= 1, "soldiers took attack tokens")
	assert_true(max_holders <= 2, "never more than two melee attackers at once (saw %d)" % max_holders)


func test_hold_lock_follows_polled_key_state() -> void:
	Settings.set_value("lock_mode", "hold", false)
	var p := spawn_player(Vector3(0, 0.05, 0), 0.0)
	spawn_soldier(Vector3(0, 0.05, -8), PI)
	await step_ticks(3)
	p.router.set_injected_hold(&"lock", true)
	p.router.inject_edge(&"lock_press")
	await step_ticks(2)
	assert_eq(p.lock.target_id, "soldier_01", "hold mode: locked while held")
	# Release without any release edge (as when the key goes up during a pause or focus loss).
	p.router.set_injected_hold(&"lock", false)
	await step_ticks(1)
	assert_eq(p.lock.target_id, "", "hold mode: the lock ends as soon as the key is no longer held")
	Settings.set_value("lock_mode", "toggle", false)


func test_held_block_resumes_without_parry_window() -> void:
	var p := spawn_player(Vector3(0, 0.05, 0), 0.0)
	await step_ticks(8)
	p.router.inject_light_attack()
	await step_ticks(2)
	p.router.set_injected_hold(&"block", true)
	p.router.inject_edge(&"block_press")   # buffered during windup, expires before recovery
	await step_ticks(30)
	assert_eq(p.controller.state, CombatController.State.BLOCKING, "held block resumes once the attack allows it")
	assert_false(p.controller.parry_available, "a resumed (not pressed) block opens no parry window")
	assert_near(p.entity.combatant.pools.stamina, 100.0 - 8.0 - 5.0, 0.01, "light 8 + block entry 5, charged once")
	await step_ticks(30)
	assert_eq(p.controller.state, CombatController.State.BLOCKING, "stays blocking while held")
	assert_near(p.entity.combatant.pools.stamina, 87.0, 0.01, "no repeated entry cost while held")
	p.router.set_injected_hold(&"block", false)
	p.router.inject_edge(&"block_release")
	await step_ticks(2)
	assert_eq(p.controller.state, CombatController.State.LOCOMOTION, "released")


func test_pad_combos_are_remappable() -> void:
	var router := InputRouter.new()
	world.add_child(router)
	await get_tree().process_frame
	Settings.set_action_binding("ability_1", true, {"joy_button": "y"})
	assert_eq(InputBindings.short_pad_label("ability_1"), "LT+Y", "hotbar label follows the remap")
	Input.action_press("ability_modifier")
	var y := InputEventJoypadButton.new()
	y.button_index = JOY_BUTTON_Y
	y.pressed = true
	Input.parse_input_event(y)
	await get_tree().process_frame
	assert_eq(router.consume().edges, [&"slot_1"] as Array, "LT + Y now fires slot 1")
	y.pressed = false
	Input.parse_input_event(y)
	Input.action_release("ability_modifier")
	var a := InputEventJoypadButton.new()
	a.button_index = JOY_BUTTON_A
	a.pressed = true
	Input.parse_input_event(a)
	await get_tree().process_frame
	assert_eq(router.consume().edges, [&"jump"] as Array, "A alone still jumps")
	a.pressed = false
	Input.parse_input_event(a)
	await get_tree().process_frame
	Settings.reset_bindings()
	assert_eq(InputBindings.short_pad_label("ability_1"), "LT+A", "defaults restored")


func test_dodged_hits_keep_the_fight_in_combat() -> void:
	var p := spawn_player(Vector3(0, 0.05, 0), 0.0)
	await step_ticks(8)
	p.entity.combatant.pools.since_combat = 9.5
	p.router.inject_edge(&"dodge")
	await step_ticks(8)
	queue_hit("tester", "player", Vector3(0, 0, -2))
	await step_ticks(1)
	assert_true(hits.size() == 1 and hits[0].outcome == HitResult.Outcome.EVADED, "evaded")
	assert_true(p.entity.combatant.pools.since_combat < 0.1, "an evaded hit still counts as combat (fury does not decay)")
