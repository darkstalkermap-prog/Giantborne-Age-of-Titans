extends IntegrationSuite
## Regressions found by the independent review: hidden-target memory, the soldier's frontal
## guard, and navigation when a breakable loads already destroyed.


func test_brain_uses_last_known_position_when_target_hidden() -> void:
	var brain := SoldierBrain.new("soldier_x", GameData.get_record("enemy.soldier"), 7)
	var me := Vector3(0, 0, 0)
	brain.perceive(100, {"exists": true, "target_id": "player", "alive": true, "visible": true,
		"position": Vector3(0, 0, 15), "distance": 15.0, "facing_deg": 0.0, "target_radius": 0.85})
	brain.state = SoldierBrain.AIState.APPROACH
	brain.perceive(112, {"exists": true, "target_id": "player", "alive": true, "visible": false,
		"position": Vector3(14, 0, 15), "distance": 20.5, "facing_deg": 40.0, "target_radius": 0.85})
	brain.decide(112, CombatController.State.LOCOMOTION, me, func() -> bool: return true, func() -> void: pass)
	assert_true(brain.face_point.is_equal_approx(Vector3(0, 0, 15)), "faces the last known position, not the hidden live one")
	assert_true(brain.move_target.x < 1.0, "moves toward the last known position (x=%.2f)" % brain.move_target.x)


func test_soldier_guard_blocks_front_flank_and_heavy_break_it() -> void:
	var s := spawn_soldier(Vector3(0, 0.05, -3), 0.0)   # facing -Z, i.e. away from the origin
	await step_ticks(3)
	s.brain.aware = true
	s.brain.state = SoldierBrain.AIState.RECOVER
	assert_true(s.is_guarding(), "aware and not attacking: guard raised")
	var front := s.global_position + Vector3(0, 0, -3)
	var back := s.global_position + Vector3(0, 0, 3)
	queue_hit("player", "soldier_01", front, 40.0, PackedStringArray(["Melee", "Parryable"]), 3.6576)
	await step_ticks(1)
	assert_eq(hits[-1].outcome, HitResult.Outcome.BLOCKED, "frontal hit is blocked")
	queue_hit("player", "soldier_01", back, 40.0, PackedStringArray(["Melee", "Parryable"]), 3.6576)
	await step_ticks(1)
	assert_eq(hits[-1].outcome, HitResult.Outcome.HIT, "a flanking hit lands")
	s.entity.combatant.poise.immunity_left = 0.0
	s.entity.combatant.pools.stamina = 12.0
	queue_hit("player", "soldier_01", front, 72.0, PackedStringArray(["Melee", "Parryable", "Heavy"]), 3.6576)
	await step_ticks(1)
	assert_eq(hits[-1].outcome, HitResult.Outcome.GUARD_BROKEN, "a heavy breaks a worn guard")
	assert_eq(s.controller.state, CombatController.State.STAGGERED, "a broken guard staggers the soldier")
	assert_false(s.is_guarding(), "no guard while staggered")


func test_destroyed_breakable_at_load_is_not_a_nav_obstacle() -> void:
	WorldState.record_destroyed("sandbox.fence_01")
	var arena: Node3D = (load("res://scenes/world/sandbox_arena.tscn") as PackedScene).instantiate()
	(arena.get_node("Soldier01") as SoldierEnemy).ai_enabled = false
	world.add_child(arena)
	var map := arena.get_world_3d().navigation_map
	# The navigation map syncs asynchronously; wait for a synced map that yields a path.
	var path := PackedVector3Array()
	for i in 120:
		await step_ticks(1)
		if NavigationServer3D.map_get_iteration_id(map) > 0:
			path = NavigationServer3D.map_get_path(map, Vector3(10, 0, 34), Vector3(14, 0, 34), true)
			if path.size() >= 2:
				break
	var length := 0.0
	for i in range(1, path.size()):
		length += path[i - 1].distance_to(path[i])
	assert_true(path.size() >= 2, "a path exists")
	assert_true(length < 5.0, "walks straight through where the fence was (%.2f m)" % length)
	arena.queue_free()
	await step_ticks(2)
