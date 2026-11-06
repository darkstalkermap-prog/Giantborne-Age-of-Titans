extends IntegrationSuite
## Physics layer 6 "blockers" (decision 21) and the AI LOD tiers (plan §2.7.3, §3.4): actor
## bodies with SceneKit.ACTOR_MASK stop at an invisible wall that only that layer holds, while
## the camera sweep, attack sweeps and enemy sight pass through it; a tier-2 enemy is dormant
## (no processing, body hidden, proxy shown); a tier-1 enemy re-paths at most once per second
## and only after a path failure; the navigation agent takes the record's nav_layers.

const WOLF := "res://scenes/enemies/wolf.tscn"


func _blocker(size: Vector3, pos: Vector3) -> StaticBody3D:
	return add_box(size, pos, SceneKit.L_BLOCKER)


# --------------------------------------------------------------------------- blockers

func test_actor_bodies_stop_at_a_blocker_wall() -> void:
	_blocker(Vector3(12, 6, 0.6), Vector3(0, 3, -6))
	var p := spawn_player(Vector3(0, 0.05, 0), 0.0)
	var s := spawn_soldier(Vector3(4, 0.05, -2), 0.0, "test.walker")
	var w := TestSpawn.enemy(world, WOLF, Vector3(-4, 0.05, -2), "test.runner", false)
	var plain := CharacterBody3D.new()   # the M1 actor mask (19): no blockers layer
	plain.collision_layer = SceneKit.L_ACTORS
	plain.collision_mask = SceneKit.L_WORLD | SceneKit.L_ACTORS | SceneKit.L_BREAKABLE
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.35
	cap.height = 1.8
	cs.shape = cap
	cs.position = Vector3(0, 0.9, 0)
	plain.add_child(cs)
	plain.position = Vector3(2, 0.05, -2)
	world.add_child(plain)
	await step_ticks(2)
	for body: CollisionObject3D in [s, w]:
		assert_eq(body.collision_mask, SceneKit.ACTOR_MASK, "%s uses ACTOR_MASK (51)" % body.name)
	# P26 (plan M6-M9 §2.2): the giant also collides with the size-gate walls above its stage (layers
	# 7-9: 448 at stage 1); the actor layers stay ACTOR_MASK.
	assert_eq(p.collision_mask, SceneKit.ACTOR_MASK | PlayerGrowth.size_gate_mask_for_stage(1),
		"%s uses ACTOR_MASK (51) and the size gates above stage 1 (448)" % p.name)
	s.brain.move_target = Vector3(4, 0, -14)
	w.brain.move_target = Vector3(-4, 0, -14)
	w.brain.move_speed = -1.0
	for i in 180:
		p.camera_rig.yaw = 0.0
		p.router.set_injected_move(Vector2(0, 1))   # straight ahead (-Z), into the wall
		plain.velocity = Vector3(0, 0, -4)
		plain.move_and_slide()
		await step_ticks(1)
	p.router.set_injected_move(Vector2.ZERO)
	assert_true(p.global_position.z > -6.0, "the giant stops at the blocker (z=%.2f)" % p.global_position.z)
	assert_true(s.global_position.z > -6.0, "so does a soldier (z=%.2f)" % s.global_position.z)
	assert_true(w.global_position.z > -6.0, "and a wolf (z=%.2f)" % w.global_position.z)
	assert_true(p.global_position.z < -3.0, "the giant did walk up to it (z=%.2f)" % p.global_position.z)
	assert_true(plain.global_position.z < -7.0, "a body without the blockers bit walks through (z=%.2f)" % plain.global_position.z)


func test_camera_attacks_and_sight_ignore_blockers() -> void:
	var p := spawn_player(Vector3(0, 0.05, 0), 0.0)
	_blocker(Vector3(10, 10, 0.4), Vector3(0, 4, 2.0))   # right behind the giant, across the camera arm
	_blocker(Vector3(6, 5, 0.4), Vector3(0, 2.5, -1.2))   # between the giant and the dummy
	spawn_dummy(Vector3(0, 0, -2.6), "dummy_beyond_blocker")
	var s := spawn_soldier(Vector3(0, 0.05, -8), PI, "test.watcher")
	await step_ticks(30)
	assert_false(p.camera_rig.obstructed, "the camera arm sweeps through the blocker wall")
	var space := p.get_world_3d().direct_space_state
	var pivot := p.global_position + Vector3.UP * 3.3
	assert_near(p.camera_rig._sweep(space, pivot, pivot + Vector3(0, 0, 6)), 1.0, 1e-6,
		"the camera's sphere cast does not stop at it")
	var none: Array[RID] = []
	assert_true(HitQueryAdapter.line_clear(space, pivot, pivot + Vector3(0, -1, -6),
		HitQueryAdapter.OCCLUDER_MASK, none), "attack occlusion rays pass through it")
	p.router.inject_light_attack()
	await step_ticks(45)
	assert_eq(hits_on("dummy_beyond_blocker").size(), 1, "a light swing lands through the blocker")
	var seen: Dictionary = s._sense()
	assert_true(bool(seen.visible), "an enemy sees the giant through it (sight is WORLD | BREAKABLE)")
	# Control: the same walls on the world layer stop all three.
	var wall := add_box(Vector3(10, 10, 0.4), Vector3(0, 4, 2.0))
	add_box(Vector3(6, 5, 0.4), Vector3(0, 2.5, -1.2))
	add_box(Vector3(6, 5, 0.4), Vector3(0, 2.5, -5.0))
	await step_ticks(90)   # past the light chain window: the next swing is light 1 again
	assert_true(p.camera_rig.obstructed, "control: a world wall obstructs the camera arm")
	assert_true(p.camera_rig._sweep(space, pivot, pivot + Vector3(0, 0, 6)) < 0.5, "control: the sphere cast stops")
	hits.clear()
	p.router.inject_light_attack()
	await step_ticks(45)
	assert_eq(hits_on("dummy_beyond_blocker").size(), 0, "control: a world wall stops the swing")
	assert_eq(started.filter(func(x: String) -> bool: return x == "player:ability.light_1").size(), 2,
		"both swings were the same light 1")
	assert_false(bool(s._sense().visible), "control: and blocks sight")
	assert_true(wall != null, "wall placed")


# --------------------------------------------------------------------------- LOD tiers

func test_tier_2_is_dormant_and_shows_the_proxy() -> void:
	var s := spawn_soldier(Vector3(0, 0.05, -4), PI, "test.far_soldier", true)
	var w := TestSpawn.enemy(world, WOLF, Vector3(3, 0.05, -4), "test.far_wolf", true)
	await step_ticks(2)
	for e: EnemyActor in [s, w]:
		var body := e.get_node("Visual/Body") as Node3D
		var proxy := e.get_node("Visual/LodProxy") as Node3D
		assert_true(e.can_process() and body.visible and not proxy.visible, "%s starts at tier 0, rig shown" % e.entity_id)
		e.set_lod_tier(2)
		assert_eq(e.lod_tier, 2, "%s at tier 2" % e.entity_id)
		assert_false(e.can_process(), "%s: can_process() is false (process_mode DISABLED)" % e.entity_id)
		assert_false(body.visible, "%s: Visual/Body hidden" % e.entity_id)
		assert_true(proxy.visible, "%s: Visual/LodProxy shown" % e.entity_id)
	var brain_tick := s.brain.now
	s.brain.move_target = Vector3(0, 0, -20)
	var at := s.global_position
	await step_ticks(30)
	assert_eq(s.brain.now, brain_tick, "Sim skips a dormant actor: its brain does not run")
	assert_true(s.global_position.distance_to(at) < 0.01, "and it does not move")
	var hurtbox := s.get_node("Hurtboxes/Torso") as Area3D
	assert_false(PhysicsServer3D.body_get_space(s.get_rid()).is_valid(), "its body has left physics")
	assert_false(PhysicsServer3D.area_get_space(hurtbox.get_rid()).is_valid(), "and so have its hurtboxes")
	for e: EnemyActor in [s, w]:
		e.set_lod_tier(0)
		assert_true(e.can_process(), "%s: back to tier 0, processing again" % e.entity_id)
		assert_true((e.get_node("Visual/Body") as Node3D).visible, "%s: rig shown" % e.entity_id)
		assert_false((e.get_node("Visual/LodProxy") as Node3D).visible, "%s: proxy hidden" % e.entity_id)
	await step_ticks(12)
	assert_true(s.brain.now > brain_tick, "the brain runs again")
	assert_true(PhysicsServer3D.body_get_space(s.get_rid()).is_valid(), "the body is back in physics")
	assert_true(PhysicsServer3D.area_get_space(hurtbox.get_rid()).is_valid(), "and its hurtboxes too")


func test_going_dormant_gives_the_attack_token_back() -> void:
	var s := spawn_soldier(Vector3(0, 0.05, -4), PI, "test.sleeper")
	await step_ticks(1)
	s.brain.target_id = "player"
	assert_true(s._request_token(), "it takes one of the giant's tokens")
	s.brain.holds_token = true
	assert_true(Sim.token_holders("player").has("test.sleeper"), "holder")
	s.set_lod_tier(2)
	assert_false(Sim.token_holders("player").has("test.sleeper"), "a dormant actor holds no token")
	assert_false(s.brain.holds_token, "and its brain knows it")


func test_tier_set_before_ready_applies_on_ready() -> void:
	var s: SoldierEnemy = (load(SOLDIER) as PackedScene).instantiate()
	s.entity_id = "test.early_lod"
	s.position = Vector3(0, 0.05, -4)
	s.set_lod_tier(2)
	world.add_child(s)
	await step_ticks(1)
	assert_eq(s.lod_tier, 2, "the director may set the tier before adding the actor")
	assert_false(s.can_process(), "dormant from the start")
	assert_true((s.get_node("Visual/LodProxy") as Node3D).visible, "proxy shown")


func test_tier_1_reduces_rates_and_repaths_only_after_failures() -> void:
	var s := spawn_soldier(Vector3(0, 0.05, 0), 0.0, "test.mid_soldier")
	await step_ticks(2)
	assert_eq(s.perception_interval, 12, "tier 0: perception at 5 Hz")
	assert_eq(s.decision_interval, 6, "tier 0: decisions at 10 Hz")
	# Tier 0: a goal that keeps moving gets a new path whenever it moved more than 0.5 m.
	s.brain.move_speed = 0.0
	var base := s.repath_count
	for i in 60:
		s.brain.move_target = Vector3(10.0 + 0.1 * i, 0, -20)
		await step_ticks(1)
	assert_true(s.repath_count - base >= 4, "tier 0 follows a moving goal (%d re-paths)" % (s.repath_count - base))
	s.set_lod_tier(1)
	assert_eq(s.perception_interval, 60, "tier 1: perception at 1 Hz")
	assert_eq(s.decision_interval, 30, "tier 1: decisions at 2 Hz")
	s.request_repath()
	await step_ticks(70)   # the pending re-path is taken once a second has passed since the last
	base = s.repath_count
	for i in 120:
		s.brain.move_target = Vector3(-10.0 - 0.1 * i, 0, -20)
		await step_ticks(1)
	assert_eq(s.repath_count - base, 0, "tier 1 keeps its path while the goal moves (no path failure)")
	# Path failures every tick: still at most one re-path per second.
	base = s.repath_count
	for i in 180:
		s.request_repath()
		await step_ticks(1)
	var n := s.repath_count - base
	assert_true(n >= 2 and n <= 3, "at most once per second after failures (%d re-paths in 3 s)" % n)
	s.set_lod_tier(0)
	assert_eq(s.perception_interval, 12, "back to tier 0 rates")


func test_tier_1_repaths_after_a_real_path_failure() -> void:
	add_box(Vector3(8, 4, 0.6), Vector3(0, 2, -3))   # no navmesh here: the soldier walks into the wall
	var s := spawn_soldier(Vector3(0, 0.05, 0), 0.0, "test.stuck")
	await step_ticks(2)
	s.set_lod_tier(1)
	# A patrolling brain keeps its goal when a path fails (it only advances its patrol index);
	# with the AI off the goal stays the point behind the wall.
	s.brain.state = EnemyBrain.AIState.PATROL
	s.brain.move_target = Vector3(0, 0, -20)
	s.brain.move_speed = 0.0
	await step_ticks(2)
	var base := s.repath_count
	var failures := s.path_failures
	await step_ticks(7 * 60 + 10)   # walks 1.5 s to the wall, then fails at about 4 s and 6 s
	assert_true(s.path_failures - failures >= 2, "no progress for 2 s counts as a path failure (%d)" % (s.path_failures - failures))
	assert_eq(s.repath_count - base, s.path_failures - failures,
		"one re-path after each failure, none in between (%d re-paths)" % (s.repath_count - base))


func test_agent_navigation_layers_come_from_the_record() -> void:
	var s := spawn_soldier(Vector3(0, 0.05, -4), PI, "test.nav_soldier")
	var w := TestSpawn.enemy(world, WOLF, Vector3(3, 0.05, -4), "test.nav_wolf", false)
	await step_ticks(1)
	assert_eq(s.agent.navigation_layers, int(GameData.get_record("enemy.soldier").nav_layers), "soldier: the record's layers")
	assert_eq(w.agent.navigation_layers, int(GameData.get_record("enemy.wolf").nav_layers), "wolf: the record's layers")
	TestFixtures.record_override("enemy.wolf", {"nav_layers": 2})
	var big := TestSpawn.enemy(world, WOLF, Vector3(-3, 0.05, -4), "test.nav_large", false)
	await step_ticks(1)
	assert_eq(big.agent.navigation_layers, 2, "a record on the large layer gives the agent layer 2")
