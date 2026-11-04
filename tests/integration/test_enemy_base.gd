extends IntegrationSuite
## EnemyActor / EnemyBrain (plan §2.7.3): the soldier keeps its names and behaviour on the new
## base, the appended AI states keep the old indices, the perception snapshot carries the new
## keys, soldier hits go through HitFactory, a non-soldier EnemyActor works on the base alone,
## and the F3 debug panel lists any enemy (capped) plus debug_info_providers.


class Provider:
	extends Node

	func _ready() -> void:
		add_to_group("debug_info_providers")

	func debug_lines() -> PackedStringArray:
		return PackedStringArray(["PROVIDER line one", "PROVIDER line two"])


func test_soldier_is_built_on_the_base() -> void:
	var s := spawn_soldier(Vector3(0, 0.05, -6), PI)
	await step_ticks(2)
	assert_true(s is EnemyActor, "SoldierEnemy extends EnemyActor")
	assert_true(s.brain is SoldierBrain and s.brain is EnemyBrain, "SoldierBrain extends EnemyBrain")
	assert_eq(s.entity_id, "soldier_01", "entity id")
	assert_true(s.runner is AttackRunner, "the soldier queries hits through an AttackRunner")
	assert_false(s.runner.emit_clank, "enemies never report clanks")
	assert_true(s.runner.has_shape("weapon_arc") and s.runner.has_shape("cylinder_pulse"), "P02 shapes")
	assert_true(s.home_position.is_equal_approx(Vector3(0, 0.05, -6)), "home = spawn point")
	assert_eq(s.faction, "", "always hostile by default")
	assert_eq(s.encounter_id, "", "no encounter")
	assert_false(s.persist_death, "deaths not persisted by default")
	assert_false(s.commander, "not a commander")
	assert_eq(s.loot_table, "", "record loot table")
	assert_eq(s.current_growth_stage(), 1, "enemies attack at growth stage 1")
	var arena: Node3D = (load("res://scenes/world/sandbox_arena.tscn") as PackedScene).instantiate()
	TestSpawn.disable_all_ai(arena)
	assert_false((arena.get_node("Soldier01") as SoldierEnemy).ai_enabled, "disable_all_ai works before add_child")
	arena.free()


func test_ai_states_keep_their_indices() -> void:
	var names := ["IDLE", "PATROL", "ALERT", "APPROACH", "ATTACK", "RECOVER", "REPOSITION", "FLEE",
		"STAGGERED", "DEAD", "HOLD", "STAND_DOWN", "RETURN", "ROUTED"]
	for i in names.size():
		assert_eq(int(SoldierBrain.AIState[names[i]]), i, "SoldierBrain.AIState.%s == %d" % [names[i], i])
		assert_eq(int(EnemyBrain.AIState[names[i]]), i, "EnemyBrain.AIState.%s == %d" % [names[i], i])
	assert_eq(SoldierBrain.AIState.RECOVER, EnemyBrain.AIState.RECOVER, "inherited enum")
	assert_eq(EnemyBrain.STATE_NAMES.size(), names.size(), "a name per state")
	var brain := SoldierBrain.new("soldier_x", GameData.get_record("enemy.soldier"), 7)
	brain.state = SoldierBrain.AIState.ROUTED
	assert_eq(brain.state_name(), "Routed", "appended states have names")


func test_snapshot_carries_the_new_keys() -> void:
	var p := spawn_player(Vector3(0, 0.05, 0), PI / 2.0)
	var s := spawn_soldier(Vector3(0, 0.05, -6), 0.0)
	await step_ticks(3)
	s.entity.combatant.pools.health = s.entity.combatant.pools.health_max * 0.5
	var snap: Dictionary = s._sense()
	for key in ["exists", "target_id", "alive", "position", "distance", "visible", "facing_deg",
			"target_radius", "target_forward", "target_height", "target_stage", "target_state",
			"self_health_frac"]:
		assert_true(snap.has(key), "snapshot has '%s'" % key)
	var fwd: Vector3 = snap.target_forward
	assert_true(fwd.is_equal_approx(Vector3(-1, 0, 0)), "target_forward is the giant's flat forward (%s)" % fwd)
	assert_near(float(snap.target_height), 3.6576, 1e-4, "target_height")
	assert_near(float(snap.target_radius), 0.85, 1e-6, "target_radius from the growth profile")
	assert_eq(int(snap.target_stage), 1, "target_stage")
	assert_eq(int(snap.target_state), CombatController.State.LOCOMOTION, "target_state")
	assert_near(float(snap.self_health_frac), 0.5, 1e-6, "self_health_frac")
	p.router.inject_light_attack()
	await step_ticks(2)
	assert_eq(int(s._sense().target_state), CombatController.State.ATTACKING, "target_state follows the controller")


func test_soldier_hits_carry_factory_fields() -> void:
	var p := spawn_player(Vector3(0, 0.05, 0), 0.0)
	var s := spawn_soldier(Vector3(0, 0.05, -1.9), PI)
	await step_ticks(3)
	s.controller.request(&"attack", {"action_id": "ability.soldier_slash"})
	var ok: bool = await TestWait.until(self, func() -> bool: return hits_on("player").size() > 0, 90)
	assert_true(ok, "the slash lands")
	if ok:
		var e: HitEvent = hits_on("player")[0].event
		assert_eq(e.attacker_id, "soldier_01", "from the soldier")
		assert_eq(e.attacker_growth_stage, 1, "attacker growth stage set")
		assert_eq(e.pulse_id, 0, "weapon arcs use pulse 0")
		assert_near(e.attacker_height_m, 1.8, 1e-6, "soldier height")
		assert_true(e.attacker_position.is_equal_approx(s.global_position), "attacker position")
		assert_eq(hits_on("player")[0].health_damage, 35, "the M1 number (30 x 1.15 -> 35) is unchanged")
	assert_eq(clanks, 0, "no clank events from enemies")
	assert_near(p.entity.combatant.pools.health, 465.0, 1e-6, "500 - 35")


func test_a_stub_enemy_fights_on_the_base_alone() -> void:
	spawn_player(Vector3(0, 0.05, 0), 0.0)
	var stub := TestSpawn.stub_enemy(world, Vector3(0, 0.05, -9), "stub_01", true, "enemy.soldier", PI)
	await step_ticks(2)
	assert_true(stub is StubEnemy and not stub is SoldierEnemy, "a non-soldier EnemyActor")
	assert_true(stub.brain is EnemyBrain and not stub.brain is SoldierBrain, "the default melee brain")
	assert_true((stub as StubEnemy).calls.has("make_brain"), "_make_brain() was used")
	assert_false(stub.is_guarding(), "no guard on the base")
	var attacked: bool = await TestWait.until(self, func() -> bool:
		return started.has("stub_01:ability.soldier_slash") or started.has("stub_01:ability.soldier_chop"), 600)
	assert_true(attacked, "the base brain approaches and attacks")
	assert_true((stub as StubEnemy).sense_count > 0, "_sense_extra() saw every snapshot")
	assert_true(bool(stub.brain.perception.get("stub", false)), "and its keys reached the brain")


func test_debug_panel_lists_any_enemy_capped_and_providers() -> void:
	var p := spawn_player(Vector3(0, 0.05, 0), 0.0)
	spawn_soldier(Vector3(0, 0.05, -12), PI)
	for i in 7:
		TestSpawn.stub_enemy(world, Vector3(-12 + 3 * i, 0.05, 14), "stub_%02d" % i)
	var provider := Provider.new()
	world.add_child(provider)
	var panel := DebugPanel.new()
	world.add_child(panel)
	await step_ticks(2)
	var lines := panel.build_lines()
	var text := "\n".join(lines)
	assert_true(text.contains("soldier_01  AI="), "the soldier is listed")
	assert_true(text.contains("stub_"), "non-soldier enemies are listed (duck typed)")
	var enemy_lines := 0
	for l in lines:
		if l.contains("  AI="):
			enemy_lines += 1
	assert_eq(enemy_lines, DebugPanel.MAX_ENEMY_LINES, "at most 6 enemy lines")
	assert_true(text.contains("+2 more enemies"), "the rest is summarised")
	assert_true(text.contains("PROVIDER line one") and text.contains("PROVIDER line two"),
		"debug_info_providers add their lines")
	assert_true(lines[1].begins_with("PLAYER"), "the player block comes first")
	assert_true(lines[4].begins_with("soldier_01"), "nearest enemy first")
	p.queue_free()
	await step_ticks(1)
	assert_false("\n".join(panel.build_lines()).contains("PLAYER"), "works without a player")
