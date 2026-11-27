extends IntegrationSuite
## D3 in the real world (scenes/world/world.tscn, deterministic streaming): stage 9 (116 ft, 35.4 m).
##   * the Rimstone grows a stage-8 giant of level 17 to stage 9 once the Stormcaller has fallen - with room for him
##     at the stone - and refuses it before, saying what is still needed;
##   * a stage-9 giant fits at every checkpoint of the world its respawn may use (as C1's stage-8 check), so the
##     elder colossus never wakes inside a house, a hall or Last Hearth's ring - at a shrine stepped out clear of its
##     stone (PlayerGrowth.shrine_spot: the pad 6.5 m in front of it is narrower than his 6.9 m capsule);
##   * the Fallen King's crown-iron stands on his left shin's top, about 35 m up, a pickup only a stage-9 giant takes.

const SCENE := "res://scenes/world/world.tscn"
const RIMSTONE_PAD := Vector2(-78.0, -1461.5)
const SHIN_ID := "world.hoarfell.fallen_king_shin"


func after_each() -> void:
	get_tree().paused = false
	for f in Formation.live():
		f.dissolve()
	FactionState.reset_for_tests()
	WanderDirector.reset_for_tests()
	GameSession.expansion = ExpansionState.defaults()
	await super()


func _world(xz: Vector2, stage: int) -> WorldRoot:
	GameSession.start_world_for_tests("world.cp.cairnlands")
	GameSession.level_id = GameSession.WORLD_LEVEL_ID
	var w := (load(SCENE) as PackedScene).instantiate() as WorldRoot
	world.add_child(w)
	w.streamer.deterministic = true
	var p := w.player()
	p.router.use_injection = true
	p.entity.apply_status("status.debug_invulnerable", NAN, -1.0, "test")
	GameSession.on_level_ready(w, p)
	await _place(w, xz)
	TitanDuel.prepare(p, stage)
	await step_ticks(10)
	assert_eq(p.current_growth_stage(), stage, "the giant is stage %d" % stage)
	return w


func _place(w: WorldRoot, xz: Vector2) -> void:
	var p := w.player()
	var at := Vector3(xz.x, 300.0, xz.y)
	p.process_mode = Node.PROCESS_MODE_DISABLED
	p.global_position = at
	var guard := 0
	while not w.streamer.ring_ready(at) and guard < 900:
		w.streamer.load_ring_slice(at)
		await step_ticks(1)
		guard += 1
	var y := w.height_at(at)
	p.global_position = Vector3(xz.x, (y if not is_nan(y) else 100.0) + 0.3, xz.y)
	p.velocity = Vector3.ZERO
	p.process_mode = Node.PROCESS_MODE_INHERIT


func _node_by_world_id(id: String, group := "interactables") -> Node:
	for n in get_tree().get_nodes_in_group(group):
		if str(n.get("world_id")) == id or str(n.get("interact_id")) == id:
			return n
	return null


func test_the_rimstone_grows_stage_9_once_the_storm_is_broken() -> void:
	var w := await _world(RIMSTONE_PAD, 8)
	var p := w.player()
	p.progression.add_xp(Progression.xp_for_level(17) - int(p.progression.xp), "test")
	p.controller.level = int(p.progression.level)
	assert_eq(int(p.progression.level), 17, "level 17")
	WorldState.set_flag("act.two.begun", true)
	WorldState.set_flag("visited.world.shrine.rimstone", true)
	await TestWait.until(self, func() -> bool: return p.is_on_floor(), 120)
	await step_ticks(30)
	var shrine := _node_by_world_id("world.shrine.rimstone", "shrines") as Node3D
	assert_true(shrine != null, "the Rimstone's shrine is loaded")
	if shrine == null:
		return
	var r: Dictionary = p.growth.grow_to(9, shrine)
	assert_eq([r.ok, r.reason], [false, "requirement"], "the Stormcaller alive: refused")
	assert_true(str(r.message).contains("Stormcaller"), "naming what is still needed: %s" % r.message)
	WorldState.set_flag("boss.stormcaller.defeated", true)
	r = p.growth.grow_to(9, shrine)
	assert_true(bool(r.ok), "his fall: the Rimstone grows stage 9 here, with room for him (%s)" % r)
	await step_ticks(240)
	assert_eq(p.growth_stage, 9, "stage 9 at the stone")
	assert_true(p.is_on_floor(), "standing at the stone")
	assert_near(p.rig.scale.x, 1.0, 1e-4, "the growth's swell has settled")


func test_a_stage_9_giant_fits_where_its_respawn_may_wake_it() -> void:
	var w := await _world(RIMSTONE_PAD, 9)
	var p := w.player()
	var idx := w.index()
	var prof := PlayerGrowth.find_profile(GameData.records_of_type("growth_profile"), 9)
	var cap := CapsuleShape3D.new()
	cap.radius = float(prof.capsule_radius_m)
	cap.height = float(prof.capsule_total_height_m)
	var tight: Array = []
	var checked := 0
	for id: String in idx.checkpoint_ids():
		if idx.max_stage_of(id) < 9:
			continue
		var at := idx.position_of(id)
		if not at.is_finite():
			continue
		if str(idx.checkpoint(id).get("kind", "")) == "shrine":
			# where the respawn puts him: clear of the shrine's stone (GameSession.respawn_transform)
			at = PlayerGrowth.shrine_spot(idx.spawn_transform(id), float(prof.capsule_radius_m)).origin
		await _place(w, Vector2(at.x, at.z))
		await step_ticks(2)
		var y := w.height_at(at)
		var q := PhysicsShapeQueryParameters3D.new()
		q.shape = cap
		q.transform = Transform3D(Basis(), Vector3(at.x, y + cap.height * 0.5 + 0.3, at.z))
		q.collision_mask = PlayerGrowth.CLEARANCE_MASK & ~HitQueryAdapter.LAYER_ACTORS
		q.exclude = [p.get_rid()]
		checked += 1
		if not p.get_world_3d().direct_space_state.intersect_shape(q, 1).is_empty():
			tight.append(id)
	print("    test_d3_world: %d checkpoints a stage-9 giant may wake at, tight: %s" % [checked, tight])
	assert_true(checked >= 20, "the world's checkpoints (%d)" % checked)
	assert_eq(tight, [], "a stage-9 giant fits at every checkpoint whose max_stage lets it wake there")


func test_the_fallen_kings_crown_iron_waits_on_his_shin() -> void:
	var w := await _world(Vector2(60.0, -1380.0), 8)
	await step_ticks(10)
	var pickup := _node_by_world_id(SHIN_ID) as ItemPickup
	assert_true(pickup != null, "the crown-iron's pickup is in its chunk")
	if pickup == null:
		return
	assert_eq(pickup.requires_stage, 9, "for a stage-9 giant")
	assert_eq([pickup.item_id, pickup.count], ["item.titan_iron", 4], "four titan iron")
	var chest := pickup.get_node_or_null("Visual/Chest") as MeshInstance3D
	assert_true(chest != null, "its chest")
	if chest != null:
		var ground := w.height_at(pickup.global_position)
		var top := (chest.global_transform * chest.get_aabb()).end.y
		assert_true(top - ground > 30.0, "on the shin's top, %.1f m over the ground" % (top - ground))
	assert_eq(pickup.stage_reason(8).contains("Grow to stage 9"), true, "a stage-8 giant is told to grow")
	assert_eq(pickup.stage_reason(9), "", "a stage-9 giant takes it")
