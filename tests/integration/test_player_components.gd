extends IntegrationSuite
## GiantPlayer components (plan §2.7.1): the registry (missing files skipped), edge dispatch
## by priority before the default mapping, component hooks, character state apply/capture with
## passthrough keys, ensure_action / set_loadout_slot, the motor's speed multipliers and the
## duck-typed actor API the AttackRunner uses.


class FakeComponent:
	extends PlayerComponent
	var priority := 5
	var consume: Array[StringName] = []
	var seen: Array[StringName] = []
	var events: Array[String] = []
	var value: Variant = null

	func edge_priority() -> int:
		return priority

	func handle_edge(edge: StringName) -> bool:
		seen.append(edge)
		return edge in consume

	func pre_actions(_intents: Dictionary, _dt: float) -> void:
		events.append("pre")

	func post_movement(_tick: int, _dt: float) -> void:
		events.append("post")

	func on_action_started(action: ActionDef, _instance_id: int) -> void:
		events.append("started:" + action.id)

	func on_action_ended(action: ActionDef, _instance_id: int, _interrupted: bool) -> void:
		events.append("ended:" + action.id)

	func apply_state(state: Dictionary) -> void:
		if state.has("fake"):
			value = state.fake

	func capture_state(out: Dictionary) -> void:
		if value != null:
			out["fake"] = value

	func rig_state(out: Dictionary) -> void:
		out["fake_rig"] = true

	func debug_info(out: Dictionary) -> void:
		out["fake_debug"] = 1


class ProbeInteractable:
	extends Interactable
	var uses := 0

	func interact(_player: GiantPlayer) -> void:
		uses += 1


func _fake(p: GiantPlayer, component_name: String, priority: int, consume: Array[StringName] = []) -> FakeComponent:
	var f := FakeComponent.new()
	f.priority = priority
	f.consume = consume
	p.add_component(StringName(component_name), f)
	return f


func test_registry_loads_present_components_and_skips_missing_ones() -> void:
	var p := spawn_player(Vector3(0, 0.05, 0), 0.0)
	await step_ticks(2)
	assert_true(p.motor is PlayerMotor, "motor")
	assert_true(p.targeting is PlayerTargeting, "targeting")
	assert_true(p.attack is PlayerAttack, "attack")
	assert_true(p.interact is PlayerInteract, "interact")
	for entry: Array in GiantPlayer.COMPONENTS:
		var exists := ResourceLoader.exists(str(entry[1]))
		var c := p.component(StringName(str(entry[0])))
		assert_eq(c != null, exists, "%s is loaded exactly when its file exists" % entry[0])
		assert_true(p.get(str(entry[0])) == c, "member %s mirrors the registry" % entry[0])
	p.load_components([["probe", "res://tests/support/no_such_component.gd"],
		["probe2", "res://scripts/actors/player/player_not_written_yet.gd"]])
	assert_true(p.component(&"probe") == null and p.component(&"probe2") == null,
		"missing component files are skipped (silently: any error would fail this test)")
	assert_eq(p.components().size(), 4 + _optional_present(), "nothing extra was registered")


func _optional_present() -> int:
	var n := 0
	for entry: Array in GiantPlayer.COMPONENTS.slice(4):
		if ResourceLoader.exists(str(entry[1])):
			n += 1
	return n


func test_fake_component_consumes_interact_before_the_default() -> void:
	var p := spawn_player(Vector3(0, 0.05, 0), 0.0)
	var probe := ProbeInteractable.new()
	probe.position = Vector3(0, 0, -2.5)
	world.add_child(probe)
	var fake := _fake(p, "fake", 5, [&"interact"] as Array[StringName])
	await step_ticks(2)
	p.router.inject_edge(&"interact")
	await step_ticks(1)
	assert_true(fake.seen.has(&"interact"), "the fake component was offered the edge first")
	assert_eq(probe.uses, 0, "a consumed edge never reaches PlayerInteract")
	fake.consume.clear()
	p.router.inject_edge(&"interact")
	await step_ticks(1)
	assert_eq(probe.uses, 1, "unconsumed, PlayerInteract (priority 50) uses the interactable")
	var late := _fake(p, "late", 60)
	p.router.inject_edge(&"interact")
	await step_ticks(1)
	assert_eq(probe.uses, 2, "used again")
	assert_false(late.seen.has(&"interact"), "a priority-60 component never sees an edge interact consumed")


func test_edges_go_by_priority_then_to_the_default_mapping() -> void:
	var p := spawn_player(Vector3(0, 0.05, 0), 0.0)
	var second := _fake(p, "second", 20, [&"slot_1"] as Array[StringName])
	var first := _fake(p, "first", 10, [&"slot_1"] as Array[StringName])
	await step_ticks(2)
	p.router.inject_edge(&"slot_1")
	await step_ticks(1)
	assert_true(first.seen.has(&"slot_1"), "priority 10 is offered the edge")
	assert_false(second.seen.has(&"slot_1"), "priority 20 never sees an edge priority 10 consumed")
	assert_false(started.has("player:ability.heavy_footfall"), "a consumed action edge is not requested")
	first.consume.clear()
	second.consume.clear()
	p.router.inject_edge(&"slot_1")
	await step_ticks(1)
	assert_true(started.has("player:ability.heavy_footfall"), "unconsumed, the default mapping requests slot 1")
	assert_true(second.seen.has(&"slot_1"), "and every component was offered it on the way")
	# Meta edges are offered (and handled) before action edges of the same tick.
	first.seen.clear()
	p.router.inject_light_attack()
	p.router.inject_edge(&"camera_toggle")
	await step_ticks(1)
	assert_eq(first.seen, [&"camera_toggle", &"light"] as Array[StringName], "meta edges first, then actions")
	assert_true(p.camera_rig.is_first_person(), "camera toggled by the default meta mapping")


func test_component_hooks_run_each_tick_and_on_actions() -> void:
	var p := spawn_player(Vector3(0, 0.05, 0), 0.0)
	var fake := _fake(p, "fake", 100)
	await step_ticks(2)
	fake.events.clear()
	await step_ticks(3)
	assert_eq(fake.events.count("pre"), 3, "pre_actions every tick while alive")
	assert_eq(fake.events.count("post"), 3, "post_movement every tick")
	p.router.inject_light_attack()
	await step_ticks(45)
	assert_true(fake.events.has("started:ability.light_1"), "on_action_started")
	assert_true(fake.events.has("ended:ability.light_1"), "on_action_ended")
	assert_true(bool(p.get_rig_state().get("fake_rig", false)), "rig_state adds keys for the ActorRig")
	assert_eq(int(p.get_debug_info().get("fake_debug", 0)), 1, "debug_info adds keys for the F3 panel")
	assert_true(p.get_debug_info().has("interact"), "PlayerInteract reports its prompt")


func test_character_state_round_trips_unknown_keys() -> void:
	var p := spawn_player(Vector3(0, 0.05, 0), 0.0)
	var fake := _fake(p, "fake", 100)
	await step_ticks(2)
	var state := {
		"id": "char.valley_1", "definition_id": "player.giant", "ancestry": "ancestry.neutral",
		"xp": 268, "unspent_attribute_points": 3, "talent_points": 2,
		"attributes": {"strength": 12, "endurance": 13, "dexterity": 10, "intellect": 11,
			"willpower": 10, "constitution": 10},
		"growth_stage": 2, "weapon": "weapon.club", "weapons_owned": ["weapon.club"],
		"level_exempt": [], "fake": {"held": "x"},
		"p02_blob": {"nested": {"list": [1, 2, "three"], "flag": true}, "n": 4.5},
		"loadout": {"slots": ["ability.heavy_footfall", "ability.heavy_1", "", "", "", "", "", ""],
			"ultimate": ""},
		"known_abilities": ["ability.heavy_footfall", "ability.heavy_1"],
		"level": 3,
		"resources": {"health": 400.0, "stamina": 250.0, "essence": 30.0, "fury": 12.0},
	}
	p.apply_character_state(state)
	assert_eq(p.controller.loadout["slot_2"], "ability.heavy_1", "loadout applied")
	assert_true(p.controller.library.has("ability.heavy_1"), "slotted ids are in the library")
	assert_eq(fake.value, {"held": "x"}, "components read their own keys")
	var pools := p.entity.combatant.pools
	assert_near(pools.health, 400.0, 1e-6, "health restored")
	assert_near(pools.stamina, pools.stamina_max, 1e-6, "stamina clamped to its maximum")
	assert_near(pools.essence, 30.0, 1e-6, "essence restored")
	assert_near(pools.fury, 12.0, 1e-6, "fury restored")
	var out := p.capture_character_state()
	assert_eq(out.get("p02_blob"), state.p02_blob, "an unknown key round-trips unchanged, nested values included")
	# Keys a later component will own pass through only until that component exists.
	var owners := {"id": "", "definition_id": "", "ancestry": "progression", "xp": "progression",
		"unspent_attribute_points": "progression", "talent_points": "progression",
		"attributes": "progression", "level_exempt": "progression", "growth_stage": "growth",
		"weapon": "equipment", "weapons_owned": "equipment"}
	for key: String in owners:
		var owner: String = owners[key]
		if owner == "" or p.component(StringName(owner)) == null:
			assert_eq(out.get(key), state[key], "passthrough key '%s' round-trips unchanged" % key)
	assert_eq(out.fake, {"held": "x"}, "component keys are captured")
	assert_eq(out.loadout, state.loadout, "loadout captured")
	assert_eq(out.known_abilities, state.known_abilities, "known abilities captured")
	if "level" in p.controller:
		assert_eq(int(out.level), 3, "level applied to and read from the controller")
	else:
		assert_eq(int(out.level), 3, "level passes through until the controller has one (P01)")
	assert_near(float(out.resources.health), 400.0, 1e-6, "resources captured")
	assert_near(float(out.resources.stamina), pools.stamina_max, 1e-6, "clamped stamina captured")
	state["xp"] = 999
	assert_eq(int(p.capture_character_state().xp), 268, "the stored passthrough is a copy")
	p.queue_free()   # one player at a time: entity ids are unique
	await step_ticks(2)
	var again := spawn_player(Vector3(8, 0.05, 0), 0.0)
	await step_ticks(1)
	again.apply_character_state(out)
	assert_eq(again.capture_character_state(), out, "apply(capture()) on a fresh giant round-trips")


func test_fresh_capture_reflects_the_record() -> void:
	var p := spawn_player(Vector3(0, 0.05, 0), 0.0)
	await step_ticks(1)
	var out := p.capture_character_state()
	var lo: Dictionary = GameData.get_record("player.giant").loadout
	var expected_known: Array = []
	for id in (lo.slots as Array) + [lo.ultimate]:
		if str(id) != "" and not expected_known.has(str(id)):
			expected_known.append(str(id))
	assert_eq(out.loadout.slots, lo.slots, "slots from giant.json")
	assert_eq(out.loadout.ultimate, lo.ultimate, "ultimate from giant.json")
	assert_eq(out.known_abilities, expected_known, "what is slotted is known")
	var pools := p.entity.combatant.pools
	assert_near(float(out.resources.health), pools.health_max, 1e-6, "full health")


func test_ensure_action_and_set_loadout_slot() -> void:
	var p := spawn_player(Vector3(0, 0.05, 0), 0.0)
	await step_ticks(2)
	assert_false(p.controller.library.has("ability.soldier_slash"), "not in the giant's library yet")
	p.ensure_action("ability.soldier_slash")
	assert_true(p.controller.library.has("ability.soldier_slash"), "ensure_action adds it")
	p.controller.library.erase("ability.light_2")
	p.controller.library.erase("ability.light_3")
	p.ensure_action("ability.light_1")
	assert_true(p.controller.library.has("ability.light_1"), "already there")
	p.controller.library.erase("ability.light_1")
	p.ensure_action("ability.light_1")
	assert_true(p.controller.library.has("ability.light_2") and p.controller.library.has("ability.light_3"),
		"chain_next follow-ups are added too")
	p.set_loadout_slot("slot_3", "ability.heavy_footfall")
	assert_eq(p.controller.loadout["slot_3"], "ability.heavy_footfall", "slot written")
	p.set_loadout_slot("slot_9", "ability.heavy_footfall")
	assert_false(p.controller.loadout.has("slot_9"), "unknown slot keys are refused")
	p.router.inject_edge(&"slot_3")
	await step_ticks(1)
	assert_true(started.has("player:ability.heavy_footfall"), "the new slot fires through the default mapping")
	p.set_loadout_slot("ultimate", "")
	assert_eq(p.controller.loadout["ultimate"], "", "a slot can be emptied")


func test_motor_speed_multipliers() -> void:
	var p := spawn_player(Vector3(0, 0.05, 0), 0.0)
	await step_ticks(8)
	p.router.set_injected_move(Vector2(0, 1))
	await step_ticks(30)
	var walk := float(p.profile.get("walk_speed_mps", 5.0))
	assert_near(p.move_velocity.length(), walk, 0.05, "walk speed")
	p.motor.set_speed_mult(&"test_a", 0.5)
	p.motor.set_speed_mult(&"test_b", 0.8)
	await step_ticks(30)
	assert_near(p.move_velocity.length(), walk * 0.5 * 0.8, 0.05, "sources multiply")
	p.motor.set_speed_mult(&"test_a", 1.0)
	assert_eq(p.motor.speed_mult_sources().keys(), [&"test_b"], "1.0 removes a source")
	p.motor.set_speed_mult(&"test_b", 1.0)
	assert_near(p.motor.speed_mult(), 1.0, 1e-9, "no sources: 1.0")
	await step_ticks(30)
	assert_near(p.move_velocity.length(), walk, 0.05, "back to full speed")
	p.router.set_injected_move(Vector2.ZERO)


func test_actor_api_for_the_attack_runner() -> void:
	var p := spawn_player(Vector3(0, 0.05, 0), 0.0)
	await step_ticks(2)
	assert_near(p.current_weapon_scale(), float(p.profile.get("weapon_scale", 1.0)), 1e-9, "profile weapon scale")
	assert_eq(p.current_weapon(), p.weapon, "current weapon")
	assert_eq(p.current_growth_stage(), 1, "stage 1")
	assert_true(p.attack_origin_global().is_equal_approx(p.to_global(p.attack_origin)), "attack origin")
	assert_near(p.weapon_hit_radius(), float(p.weapon.hit_radius_m) * p.current_weapon_scale(), 1e-6, "weapon radius")
	assert_near(p.weapon_length, float(p.weapon.length_m) * p.current_weapon_scale(), 1e-6, "weapon length")
	assert_true(p.attack.runner.emit_clank, "the player's runner reports clanks")
	assert_eq(p.prev_segment.size(), 0, "no segment outside an attack")
	p.router.inject_light_attack()
	var ok: bool = await TestWait.until(self, func() -> bool:
		return p.controller.phase() == ActionDef.Phase.ACTIVE, 30)
	assert_true(ok, "the light attack reached its active phase")
	await step_ticks(1)
	assert_eq(p.prev_segment.size(), 2, "the swept segment is kept between active ticks")


func test_set_profile_reapplies_geometry_and_lock_range() -> void:
	var p := spawn_player(Vector3(0, 0.05, 0), 0.0)
	await step_ticks(2)
	var stage2 := GameData.get_record("growth.02")
	p.set_profile(stage2)
	assert_eq(p.growth_stage, 2, "stage 2")
	assert_eq(p.controller.growth_stage, 2, "the controller's stage follows")
	var pivot: Array = stage2.weapon_pivot_m
	assert_true(p.weapon_pivot.is_equal_approx(Vector3(pivot[0], pivot[1], pivot[2])), "weapon pivot re-read")
	assert_near(p.arm_length, float(stage2.arm_length_m), 1e-6, "arm length re-read")
	assert_near(p.lock.range_m, float(stage2.get("lock_range_m", 35.0)), 1e-6, "lock range re-read")
	assert_near((p.body_shape.shape as CapsuleShape3D).radius, float(stage2.capsule_radius_m), 1e-6, "capsule re-applied")
	p.set_profile(GameData.get_record("growth.01"))
	assert_eq(p.growth_stage, 1, "back to stage 1")
