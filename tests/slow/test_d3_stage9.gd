extends IntegrationSuite
## D3: stage 9 (116 ft, 35.4 m) in play, in a test arena - the growth at a stone as an event (the body swells over a
## few seconds, the camera rides it, the ground's dust; GrowthMoment, presentation only); what only a stage-9 giant
## does: Colossus Stride over a 16 m tower a stage-8 giant cannot clear (half of 35.4 m is 17.7), the Fallen King's
## crown-iron on a ledge only a stage-9 giant reaches, and the small things breaking before him (a troll, a rimkin,
## a dire wolf flee and rout at the sight of him; before a stage-8 giant they fight).

const RIMSTONE := "shrine.world_rimstone"
const TROLL := "res://scenes/enemies/troll.tscn"
const RIMKIN := "res://scenes/enemies/rimkin_giant.tscn"
const DIRE_WOLF := "res://scenes/enemies/dire_wolf.tscn"


func _profile(stage: int) -> Dictionary:
	return PlayerGrowth.find_profile(GameData.records_of_type("growth_profile"), stage)


func _colossus(stage: int, level := 17) -> GiantPlayer:
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


func _spawn(path: String, id: String, pos: Vector3) -> EnemyActor:
	var e := (load(path) as PackedScene).instantiate() as EnemyActor
	e.entity_id = id
	e.ai_enabled = true
	e.position = pos
	e.rotation.y = PI   # (facing the giant at the origin)
	world.add_child(e)
	return e


func test_the_growth_to_9_at_a_stone_is_an_event() -> void:
	var p := await _colossus(8)
	WorldState.set_flag("act.two.begun", true)
	WorldState.set_flag("boss.stormcaller.defeated", true)
	var shrine := FakeShrine.make("world.shrine.rimstone", RIMSTONE, Vector3(0, 0, -12))
	world.add_child(shrine)
	var k8 := PlayerGrowth.body_scale_for(_profile(8))
	var k9 := PlayerGrowth.body_scale_for(_profile(9))
	var r: Dictionary = p.growth.grow_to(9, shrine)
	assert_true(bool(r.ok), "stage 9 at the stone (%s)" % r)
	assert_eq(p.growth_stage, 9, "the growth itself is at once (the capsule, the numbers)")
	assert_near(p.rig.body_scale, k9, 1e-4, "the rig's lengths are stage 9's at once")
	var m := p.get_node_or_null("GrowthMoment") as GrowthMoment
	assert_true(m != null, "and the moment starts")
	if m == null:
		return
	assert_near(p.rig.scale.x, k8 / k9, 0.01, "the body shows its old size first (%.3f)" % p.rig.scale.x)
	assert_true(m.seconds >= 3.0, "a colossus's growth takes seconds (%.1f s)" % m.seconds)
	assert_true(m.dust_raised > 0, "the dust rises at its feet")
	var halfway := 0.0
	var frames := 0
	var seconds := m.seconds
	while frames < 2000 and is_instance_valid(m) and not m.settled:
		await get_tree().process_frame
		frames += 1
		if halfway == 0.0 and is_instance_valid(m) and m.elapsed >= seconds * 0.5:
			halfway = p.rig.scale.x
	assert_true(frames >= int(seconds * 60.0 * 0.9), "it takes its seconds of frames (%d)" % frames)
	assert_true(halfway > k8 / k9 + 0.02 and halfway < 1.0, "it swells through its sizes (%.3f halfway)" % halfway)
	await get_tree().process_frame
	assert_near(p.rig.scale.x, 1.0, 1e-6, "and ends at the new size")
	assert_near(p.camera_rig.view_scale, 1.0, 1e-6, "the camera rides the body and ends on the new pivot")
	assert_true(p.camera_rig.desired_distance >= float(_profile(9).camera_zoom_min_m) - 1e-3
		and p.camera_rig.desired_distance <= float(_profile(9).camera_zoom_max_m) + 1e-3, "the arm within stage 9's zoom")
	# the debug keys and a save's restore do not play it
	p.growth.debug_set_stage(8)
	await step_ticks(2)
	assert_true(p.get_node_or_null("GrowthMoment") == null, "a debug growth has no moment")


func test_colossus_stride_clears_a_tower_only_at_stage_9() -> void:
	var p := await _colossus(8)
	if not p.known_abilities.has("ability.colossus_stride"):
		p.progression.learn_ability("ability.colossus_stride", "test")
	var a := GameData.get_action("ability.colossus_stride")
	# a tower 16 m tall (Fort Aldmere's towers and gate bastions stand 16 m) 20 m ahead
	add_box(Vector3(40, 16, 4), Vector3(0, 8, -20))
	await step_ticks(2)
	assert_eq(str(p.motor.plan_vault(a.param("vault")).reason), "too_high", "stage 8 (half of 29.3 m is 14.6): too high")
	p.growth.debug_set_stage(9)
	await TestWait.until(self, func() -> bool: return p.is_on_floor(), 60)
	await step_ticks(5)
	var plan: Dictionary = p.motor.plan_vault(a.param("vault"))
	assert_true(bool(plan.ok), "stage 9 (half of 35.4 m is 17.7): the stride plans (%s)" % plan)
	var start := p.global_position
	p.controller.force_action(a)
	await TestWait.until(self, func() -> bool: return p.motor.vault_end_reason != "", 150)
	assert_eq(p.motor.vault_end_reason, "landed", "it lands")
	await step_ticks(30)
	assert_true(p.global_position.z < -24.0, "over the tower (z %.1f from %.1f)" % [p.global_position.z, start.z])
	assert_true(p.is_on_floor(), "standing on the far side")


func test_the_fallen_kings_crown_iron_is_in_reach_only_at_stage_9() -> void:
	var p := await _colossus(8)
	var pickup := ItemPickup.new()
	pickup.name = "FallenKingShin"
	pickup.world_id = "world.hoarfell.fallen_king_shin"
	pickup.interact_id = "world.hoarfell.fallen_king_shin"
	pickup.item_id = "item.titan_iron"
	pickup.count = 4
	pickup.requires_stage = 9
	pickup.stage_message = "The Fallen King's crown-iron lies on the top of his standing shin, out of every lesser giant's reach. Grow to stage 9."
	pickup.radius_m = 14.0
	pickup.position = Vector3(0, 0.05, -12)
	world.add_child(pickup)
	await step_ticks(2)
	var messages: Array = []
	var on_msg := func(text: String, _kind: String) -> void: messages.append(text)
	Events.hud_message.connect(on_msg)
	var before := WorldState.count_of("item.titan_iron")
	p.interact.use_candidate({"node": pickup, "id": pickup.interact_id, "prompt": "", "priority": 0, "distance": 0.0})
	assert_eq(WorldState.count_of("item.titan_iron"), before, "stage 8: out of reach")
	assert_true(messages.any(func(t: String) -> bool: return t.contains("Grow to stage 9")), "and says so: %s" % [messages])
	p.growth.debug_set_stage(9)
	await step_ticks(5)
	p.interact.use_candidate({"node": pickup, "id": pickup.interact_id, "prompt": "", "priority": 0, "distance": 0.0})
	Events.hud_message.disconnect(on_msg)
	assert_eq(WorldState.count_of("item.titan_iron"), before + 4, "stage 9: the crown-iron taken (four titan iron)")
	var shipped := _shin_record()
	assert_eq(int(shipped.get("requires_stage", 0)), 9, "the world's ledge asks stage 9")
	assert_eq([str(shipped.get("item", "")), int(shipped.get("count", 0))], ["item.titan_iron", 4], "four titan iron")


## The world's ledge on the Fallen King's shin (tools/data/world/hoarfell.json's secrets).
func _shin_record() -> Dictionary:
	var table: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://tools/data/world/hoarfell.json"))
	for it: Dictionary in (table as Dictionary).get("secrets", []):
		if str(it.get("id", "")) == "world.hoarfell.fallen_king_shin":
			return it
	return {}


## A troll, a rimkin and a dire wolf facing a giant `stage` 40-60 m off: {id: [awe_broken, fled, routed]} after a while.
func _small_ones_before(stage: int) -> Dictionary:
	var p := await _colossus(stage)
	var ones := [_spawn(TROLL, "d3.troll", Vector3(-12, 0.05, -24)), _spawn(RIMKIN, "d3.rimkin", Vector3(20, 0.05, -45)),
		_spawn(DIRE_WOLF, "d3.wolf", Vector3(0, 0.05, -22))]
	var out := {}
	var fled := {}
	for t in 1500:   # (a flight without a leader routs after its 20 s: rout_after_s)
		await step_ticks(1)
		for e: EnemyActor in ones:
			if not is_instance_valid(e):
				continue
			if e.brain.state == EnemyBrain.AIState.FLEE:
				fled[e.entity_id] = true
	for e: EnemyActor in ones:
		out[e.entity_id] = [bool(e.brain.awe_broken), bool(fled.get(e.entity_id, false)),
			e.brain.state == EnemyBrain.AIState.ROUTED]
	p.queue_free()
	for e: EnemyActor in ones:
		e.queue_free()
	await step_ticks(2)
	return out


func test_the_small_things_break_before_a_stage_9_giant() -> void:
	var at8 := await _small_ones_before(8)
	for id: String in at8:
		assert_false(bool(at8[id][0]) or bool(at8[id][1]), "stage 8: %s stands (%s)" % [id, at8[id]])
	var at9 := await _small_ones_before(9)
	for id: String in at9:
		assert_true(bool(at9[id][0]), "stage 9: %s is awed past bearing (%s)" % [id, at9[id]])
		assert_true(bool(at9[id][1]), "and flees (%s)" % [at9[id]])
		assert_true(bool(at9[id][2]), "and routs: it does not come back (%s)" % [at9[id]])
