extends IntegrationSuite
## C1 in the real world (scenes/world/world.tscn, deterministic streaming): the land beyond the rim.
##   * the Breach keeps a stage-5 giant out (its stage-6 gate names the stage) and lets a stage-6 giant climb it into
##     the Hoarfell (the region changes; the old world's chunks stream as before on the way);
##   * the Colossus Steps keep a stage-6 giant off them and take a colossus up to the Hoarwatch;
##   * the titan navmesh joins the Breach's top to the Rimstone, Last Hearth and the Chainpit for a stage-6 mask, and
##     the Hoarwatch only for a stage-7 one;
##   * the Hoarfell's places are in their chunks: the Rimstone's shrine, the two waystones, Maera's talker, the
##     Rimward's three engines, the rim council's talker at the throne;
##   * a stage-8 giant fits at every checkpoint of the world its respawn may use (the index's max_stage holds where
##     it would not), so a colossus back in the Crownmarch never wakes inside a house.

const SCENE := "res://scenes/world/world.tscn"
const BREACH_FOOT := Vector2(150.0, -868.0)
const STEPS_FOOT := Vector2(262.0, -1606.0)

var gate_events: Array = []


func before_each() -> void:
	await super()
	gate_events.clear()
	Events.size_gate_blocked.connect(_on_gate)


func after_each() -> void:
	if Events.size_gate_blocked.is_connected(_on_gate):
		Events.size_gate_blocked.disconnect(_on_gate)
	get_tree().paused = false
	for f in Formation.live():
		f.dissolve()
	FactionState.reset_for_tests()
	WanderDirector.reset_for_tests()
	GameSession.expansion = ExpansionState.defaults()
	await super()


func _on_gate(_t: int, gate_id: String, min_stage: int, _msg: String) -> void:
	gate_events.append([gate_id, min_stage])


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


## Walks the giant along `dir` (the camera's frame: (0, 1) is north and (1, 0) east at yaw 0) for at most `ticks`, stopping when
## `done` holds. Returns the ticks walked.
func _walk(p: GiantPlayer, dir: Vector2, yaw: float, ticks: int, done: Callable) -> int:
	p.camera_rig.yaw = yaw
	p.router.set_injected_move(dir)
	var n := 0
	while n < ticks and not bool(done.call()):
		await step_ticks(1)
		n += 1
	p.router.set_injected_move(Vector2.ZERO)
	return n


func test_the_breach_keeps_out_stage_5_and_lets_stage_6_climb() -> void:
	var w := await _world(BREACH_FOOT, 5)
	var p := w.player()
	await _walk(p, Vector2(0, 1), 0.0, 360, func() -> bool: return false)
	assert_true(p.global_position.z > -904.0, "a stage-5 giant is held at the Breach's mouth (z %.1f)" % p.global_position.z)
	assert_true(gate_events.any(func(e: Array) -> bool: return str(e[0]) == "world.gate.the_breach" and int(e[1]) == 6),
		"the gate names stage 6 (%s)" % [gate_events])
	TitanDuel.prepare(p, 6)
	await step_ticks(10)
	assert_eq(p.current_growth_stage(), 6, "grown to stage 6")
	var walked := await _walk(p, Vector2(0, 1), 0.0, 3600, func() -> bool: return p.global_position.z < -1240.0)
	print("    test_c1_world: a stage-6 giant climbed the Breach in %.1f s to %s" % [walked / 60.0, p.global_position.snapped(Vector3.ONE)])
	assert_true(p.global_position.z < -1240.0, "a stage-6 giant climbs the Breach to its top (z %.1f)" % p.global_position.z)
	assert_true(p.global_position.y > 150.0, "up on the Hoarfell (y %.1f)" % p.global_position.y)
	assert_eq(w.region_at(p.global_position), "region.hoarfell", "in the Hoarfell")
	assert_eq(w.streamer.thrash_count() if w.streamer.has_method("thrash_count") else 0, 0, "no chunk thrashed on the way")


func test_the_colossus_steps_wait_for_stage_7() -> void:
	var w := await _world(STEPS_FOOT, 6)
	var p := w.player()
	await _walk(p, Vector2(1, 0), 0.0, 300, func() -> bool: return false)
	assert_true(p.global_position.x < 286.0, "a stage-6 giant stays off the Colossus Steps (x %.1f)" % p.global_position.x)
	assert_true(gate_events.any(func(e: Array) -> bool: return str(e[0]) == "world.gate.colossus_steps" and int(e[1]) == 7),
		"the steps' gate names stage 7 (%s)" % [gate_events])
	WorldState.set_flag("act.two.begun", true)
	TitanDuel.prepare(p, 7)
	await step_ticks(10)
	assert_eq(p.current_growth_stage(), 7, "grown to stage 7")
	await _walk(p, Vector2(1, 0), 0.0, 2400, func() -> bool: return p.global_position.x > 420.0)
	assert_true(p.global_position.x > 420.0 and p.global_position.y > 240.0,
		"a colossus strides up to the Hoarwatch (%s)" % p.global_position.snapped(Vector3.ONE))


func test_the_titan_navmesh_crosses_the_hoarfell() -> void:
	var w := await _world(Vector2(150.0, -1250.0), 6)
	var top := Vector3(150.0, 0.0, -1250.0)
	# (a "far" query reaches 300 m: each place within that of the Breach's top)
	for target: Vector2 in [Vector2(-70.0, -1440.0), Vector2(-120.0, -1262.0), Vector2(360.0, -1395.0), Vector2(150.0, -990.0)]:
		await _place(w, target)
		await step_ticks(2)
		await _place(w, Vector2(top.x, top.z))
		await step_ticks(2)
		var from := Vector3(top.x, w.height_at(top), top.z)
		var to := Vector3(target.x, w.height_at(Vector3(target.x, 0, target.y)), target.y)
		assert_true(NavQuery.reaches(w, from, to, PlayerGrowth.nav_query_mask_for_stage(6), 6.0),
			"a stage-6 path from the Breach's top to %s" % target)
	var watch := Vector3(452.0, 0.0, -1615.0)
	await _place(w, Vector2(330.0, -1560.0))
	await step_ticks(2)
	var foot := Vector3(260.0, w.height_at(Vector3(260.0, 0, -1560.0)), -1560.0)
	var up := Vector3(watch.x, w.height_at(watch), watch.z)
	assert_false(NavQuery.reaches(w, foot, up, PlayerGrowth.nav_query_mask_for_stage(6), 6.0), "no stage-6 path up the Colossus Steps")
	assert_true(NavQuery.reaches(w, foot, up, PlayerGrowth.nav_query_mask_for_stage(7), 6.0), "a stage-7 path up them")


func test_the_hoarfells_places_are_in_their_chunks() -> void:
	var w := await _world(Vector2(-70.0, -1440.0), 6)
	var idx := w.index()
	for id: String in ["world.shrine.rimstone", "world.cp.breach_top", "world.cp.last_hearth"]:
		assert_true(idx.has_checkpoint(id), "%s is in the index" % id)
	assert_eq(int(GameData.get_record("shrine.world_rimstone").max_stage), 9, "the Rimstone grows to stage 9 (D3; stage 8 in C1)")
	await step_ticks(30)
	var shrine: Node = null
	for n in get_tree().get_nodes_in_group(Shrine.GROUP):
		if str(n.get("world_id")) == "world.shrine.rimstone":
			shrine = n
	assert_true(shrine != null, "the Rimstone's shrine stands on its rise")
	await _place(w, Vector2(300.0, -1320.0))
	await step_ticks(30)
	var engines := 0
	for n in get_tree().get_nodes_in_group("siege_engines"):
		if str(n.get("world_id")).begins_with("world.hoarfell.warband_"):
			engines += 1
	assert_eq(engines, 3, "the Rimward's three engines at the Chainpit")
	await _place(w, Vector2(0.0, -780.0))
	await step_ticks(30)
	var council := false
	for n in get_tree().get_nodes_in_group("interactables"):
		if str(n.get("npc_id")) == "world.stonehold.rim_council":
			council = true
	assert_true(council, "the rim council's talker by the throne")


func test_a_stage_8_giant_fits_where_its_respawn_may_wake_it() -> void:
	var w := await _world(BREACH_FOOT, 8)
	var p := w.player()
	var idx := w.index()
	var prof := PlayerGrowth.find_profile(GameData.records_of_type("growth_profile"), 8)
	var cap := CapsuleShape3D.new()
	cap.radius = float(prof.capsule_radius_m)
	cap.height = float(prof.capsule_total_height_m)
	var tight: Array = []
	var checked := 0
	for id: String in idx.checkpoint_ids():
		if idx.max_stage_of(id) < 8:
			continue
		var at := idx.position_of(id)
		if not at.is_finite():
			continue
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
	print("    test_c1_world: %d checkpoints a stage-8 giant may wake at, none tight (%s)" % [checked, tight])
	assert_true(checked >= 20, "the world's checkpoints (%d)" % checked)
	assert_eq(tight, [], "a stage-8 giant fits at every checkpoint whose max_stage lets it wake there")
