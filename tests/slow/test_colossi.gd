extends IntegrationSuite
## C1: the colossi in play on the test floor - growth to stages 7 and 8 through the Rimstone's record and each stage's
## own requirement (act two, the Rimstone reached, the Colossus's Trials), every field following the profile (capsule,
## camera, lock, weapon, masks), Colossus Stride learned and vaulting a wall half the giant's height (and refused by a
## taller one, by a greater stage's size gate and with no ground beyond), the scenery's trunks passed through at
## stage 7 but not at 6, the stage 7 and 8 evolutions taking their bases' slots, and a soldier breaking before a
## colossus (the awe tier) where stage 6 only shakes him. The slow tier (a 120 m floor, stage-8 bodies).

const RIMSTONE := "shrine.world_rimstone"

var blocked: Array[Array] = []


func before_each() -> void:
	await super()
	blocked.clear()
	Events.growth_blocked.connect(_on_blocked)


func after_each() -> void:
	if Events.growth_blocked.is_connected(_on_blocked):
		Events.growth_blocked.disconnect(_on_blocked)
	await super()


func _on_blocked(_t: int, _id: String, reason: String, message: String) -> void:
	blocked.append([reason, message])


func _profile(stage: int) -> Dictionary:
	return PlayerGrowth.find_profile(GameData.records_of_type("growth_profile"), stage)


func _colossus(stage: int, level := 15) -> GiantPlayer:
	var p := spawn_player(Vector3(0, 0.05, 0))
	await TestWait.until(self, func() -> bool: return p.is_on_floor(), 30)
	var guard := 0
	while int(p.progression.level) < level and guard < 40:
		p.progression.add_xp(CombatRules.xp_to_next_level(int(p.progression.level)), "test")
		guard += 1
	p.controller.level = level
	assert_true(bool(p.growth.debug_set_stage(stage).ok), "debug growth to stage %d" % stage)
	await TestWait.until(self, func() -> bool: return p.is_on_floor(), 60)
	await step_ticks(5)
	return p


func test_growth_to_7_and_8_at_the_rimstone_asks_each_stages_requirement() -> void:
	var p := await _colossus(6)
	var shrine := FakeShrine.make("world.shrine.rimstone", RIMSTONE, Vector3(0, 0, -6))
	world.add_child(shrine)
	var r: Dictionary = p.growth.grow_to(7, shrine)
	assert_eq([r.ok, r.reason], [false, "requirement"], "act one not done: the Rimstone refuses stage 7")
	WorldState.set_flag("act.two.begun", true)
	WorldState.set_flag("visited.world.shrine.rimstone", true)
	p.controller.level = 12
	r = p.growth.grow_to(7, shrine)
	assert_eq([r.ok, r.reason], [false, "level"], "below level 13: refused by level")
	p.controller.level = 15
	r = p.growth.grow_to(7, shrine)
	assert_true(bool(r.ok), "act two, the Rimstone, level 15: stage 7 (%s)" % r)
	await step_ticks(2)
	var g7 := _profile(7)
	assert_eq(p.growth_stage, 7, "stage 7")
	var cap := p.body_shape.shape as CapsuleShape3D
	assert_near(cap.radius, float(g7.capsule_radius_m), 1e-6, "the colossus's capsule")
	assert_near(p.entity.combatant.height_m, float(g7.height_m), 1e-6, "its height (23.8 m)")
	assert_near(p.lock.range_m, float(g7.lock_range_m), 1e-6, "its lock range")
	assert_eq(p.growth.size_gate_mask(), PlayerGrowth.size_gate_mask_for_stage(7), "stage 7's size gates")
	assert_eq(p.collision_mask, PlayerGrowth.ACTOR_MASK | PlayerGrowth.size_gate_mask_for_stage(7), "its body's mask")
	assert_true(p.known_abilities.has("ability.colossus_stride"), "Colossus Stride learned")
	r = p.growth.grow_to(8, shrine)
	assert_eq([r.ok, r.reason], [false, "requirement"], "stage 8 waits for the Colossus's Trials")
	assert_true(str(r.message).contains("Last Hearth"), "and says so: %s" % r.message)
	Quests.reset_for_tests()
	WorldState.set_flag(Quests.done_flag("quest.rim_colossus"), true)
	r = p.growth.grow_to(8, shrine)
	assert_true(bool(r.ok), "the trials done: stage 8 (%s)" % r)
	await step_ticks(2)
	assert_eq(p.growth_stage, 8, "stage 8, 96 ft")
	assert_near(p.camera_rig.desired_distance, clampf(p.camera_rig.desired_distance, float(_profile(8).camera_zoom_min_m),
		float(_profile(8).camera_zoom_max_m)), 1e-4, "the camera's arm within stage 8's zoom")
	assert_true(p.camera_rig.desired_distance <= CameraRig.MAX_ARM_M, "and the rig's longest arm")
	r = p.growth.grow_to(9, shrine)
	assert_eq(r.reason, "no_profile", "no stage 9 yet (milestone D)")


func test_colossus_stride_vaults_a_wall_half_its_height() -> void:
	var p := await _colossus(7)
	var h := float(_profile(7).height_m)
	# a wall 10 m tall (under half of 23.8 m) 14 m ahead (the giant faces -z)
	add_box(Vector3(40, 10, 2), Vector3(0, 5, -14))
	p.controller.level = 15
	if not p.known_abilities.has("ability.colossus_stride"):
		p.progression.learn_ability("ability.colossus_stride", "test")
	var a := GameData.get_action("ability.colossus_stride")
	var plan: Dictionary = p.motor.plan_vault(a.param("vault"))
	assert_true(bool(plan.ok), "a 10 m wall: the stride plans (%s)" % plan)
	assert_true(float(plan.top) >= 9.9, "the highest thing on the way is the wall's top (%.1f m)" % float(plan.top))
	var start := p.global_position
	p.controller.force_action(a)
	await TestWait.until(self, func() -> bool: return p.motor.vault_end_reason != "", 120)
	assert_eq(p.motor.vault_end_reason, "landed", "it lands")
	await step_ticks(30)
	var moved := Vector2(p.global_position.x - start.x, p.global_position.z - start.z)
	assert_true(moved.y < -1.0 * h, "it carried the giant over the wall, about 1.3 x its height ahead (%.1f m)" % moved.length())
	assert_true(bool(WorldState.get_flag(PlayerMotor.STRIDE_DONE_FLAG, false)), "the first stride sets player.stride.done")
	assert_true(p.is_on_floor(), "standing again on the far side")


func test_colossus_stride_is_refused_by_a_tall_wall_a_greater_gate_and_no_ground() -> void:
	var p := await _colossus(7)
	var a := GameData.get_action("ability.colossus_stride")
	var v: Dictionary = a.param("vault")
	var wall := add_box(Vector3(40, 16, 2), Vector3(0, 8, -14))
	assert_eq(str(p.motor.plan_vault(v).reason), "too_high", "a 16 m wall is more than half of 23.8 m")
	wall.queue_free()
	await step_ticks(2)
	var gate := add_box(Vector3(40, 30, 2), Vector3(0, 15, -14), 1024)   # stage 8's size-gate layer
	assert_eq(str(p.motor.plan_vault(v).reason), "gate", "a stage-8 gate cannot be stridden past")
	gate.queue_free()
	await step_ticks(2)
	var own := add_box(Vector3(40, 30, 2), Vector3(0, 15, -14), 512)   # stage 7's own gate: it passes those
	assert_true(bool(p.motor.plan_vault(v).ok), "its own stage's gate does not stop it")
	own.queue_free()
	await step_ticks(2)
	p.global_position = Vector3(0, 0.05, -45)
	p.facing_yaw = 0.0
	await step_ticks(5)
	assert_eq(str(p.motor.plan_vault(v).reason), "no_ground", "off the floor's edge there is nothing to land on")


func test_a_colossus_strides_through_trunks_a_titan_does_not() -> void:
	var trunk := StaticBody3D.new()
	trunk.collision_layer = 1
	trunk.add_to_group(TerrainChunk.TRUNKS_GROUP)
	var cs := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = 0.6
	cyl.height = 12.0
	cs.shape = cyl
	trunk.add_child(cs)
	trunk.position = Vector3(0, 6, -12)
	world.add_child(trunk)
	var p := await _colossus(6)
	assert_false(p.motor.strides_through_trees(), "stage 6 meets the trees")
	p.router.set_injected_move(Vector2(0, -1))
	await step_ticks(150)
	var blocked_z := p.global_position.z
	p.router.set_injected_move(Vector2.ZERO)
	p.growth.debug_set_stage(7)
	await step_ticks(40)
	assert_true(p.motor.strides_through_trees(), "stage 7 strides through them")
	assert_true(p.get_collision_exceptions().has(trunk), "the trunk's body is an exception of the colossus's")
	p.growth.debug_set_stage(6)
	await step_ticks(2)
	assert_false(p.get_collision_exceptions().has(trunk), "shrunk to stage 6, it meets the trunk again")
	assert_true(blocked_z > -20.0, "(stage 6 did not walk through it: z %.1f)" % blocked_z)


func test_the_colossi_evolutions_take_their_bases_slots() -> void:
	var p := await _colossus(6, 15)
	for id: String in ["ability.titan_stomp", "ability.earthquake", "ability.crag_hurl", "ability.titan_roar"]:
		p.progression.learn_ability(id, "test")
	WorldState.set_flag("act.two.begun", true)
	p.growth.debug_set_stage(7)
	await step_ticks(2)
	assert_true(p.known_abilities.has("ability.shattering_tread"), "stage 7: Shattering Tread")
	p.growth.debug_set_stage(8)
	await step_ticks(2)
	for id: String in ["ability.mountain_hurl", "ability.worldshaking_roar"]:
		assert_true(p.known_abilities.has(id), "stage 8: %s" % id)


func test_a_soldier_breaks_before_a_colossus() -> void:
	var s := spawn_soldier(Vector3(0, 0.05, -30), 0.0, "c1_soldier", false)
	await step_ticks(2)
	var brain: EnemyBrain = s.brain
	var stage6 := float(_profile(6).height_m) / 1.8
	var stage7 := float(_profile(7).height_m) / 1.8
	assert_eq(brain.awe_loss_at(stage6), 50.0, "a stage-6 giant costs a soldier 50 morale (M9 gate's tier)")
	assert_eq(brain.awe_loss_at(stage7), 200.0, "a colossus (%.1fx) all of it: he breaks and runs" % stage7)
	var guard := GameData.get_record("enemy.iron_guard")
	assert_eq(float((guard.tactics.awe_tiers as Array)[0].ratio), 14.5, "an iron guard holds before stage 7 and breaks before stage 8")
