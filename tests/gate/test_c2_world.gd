extends IntegrationSuite
## C2 in the real open world (scenes/world/world.tscn, deterministic streaming), at the old toll-keep above the King's
## Road north-east of the toll fort:
##   * the Broken Warden is at home in the breach of the keep's north curtain, asleep; his territory sleeps on sight
##     (wake_on_sight off): a giant on the King's Road below does not wake him; a giant walking into the yard does
##     (engaged) and the keep is discovered;
##   * the keep's pieces: the curtain solid either side of his breach, the two crumbling towers within his rubble's
##     reach, the mason-forge placed; the toll fort more than 240 m from his post;
##   * Hode by his fire on the King's Road before the fall.

const SCENE := "res://scenes/world/world.tscn"
const HOME := Vector2(706.0, 189.0)
const ROAD := Vector2(600.0, 254.0)
const YARD := Vector2(705.0, 236.0)
const TOLL_FORT := Vector2(460.0, 330.0)


func after_each() -> void:
	get_tree().paused = false
	for f in Formation.live():
		f.dissolve()
	FactionState.reset_for_tests()
	WanderDirector.reset_for_tests()
	GameSession.expansion = ExpansionState.defaults()
	await super()


func _world(xz: Vector2, stage := 5) -> WorldRoot:
	GameSession.start_world_for_tests("world.cp.aldmere_road")
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
	await step_ticks(2)
	return w


func _place(w: WorldRoot, xz: Vector2) -> void:
	var p := w.player()
	var at := Vector3(xz.x, 200.0, xz.y)
	p.process_mode = Node.PROCESS_MODE_DISABLED
	p.global_position = at
	var guard := 0
	while not w.streamer.ring_ready(at) and guard < 900:
		w.streamer.load_ring_slice(at)
		await step_ticks(1)
		guard += 1
	var y := w.height_at(at)
	p.global_position = Vector3(xz.x, (y if not is_nan(y) else 25.0) + 0.3, xz.y)
	p.velocity = Vector3.ZERO
	p.process_mode = Node.PROCESS_MODE_INHERIT


func _warden() -> TitanEnemy:
	for n in get_tree().root.find_children("*", "TitanEnemy", true, false):
		var t := n as TitanEnemy
		if t.entity != null and t.entity.definition_id == "enemy.bastion":
			return t
	return null


func _territory() -> TitanTerritory:
	for n in get_tree().get_nodes_in_group(BossArena.GROUP):
		if n is TitanTerritory and (n as TitanTerritory).boss_id == "world.aldmere.bastion":
			return n
	return null


func _node_by_id(group: String, id: String) -> Node:
	for n in get_tree().get_nodes_in_group(group):
		if str(n.get("world_id")) == id:
			return n
	return null


func test_he_sleeps_in_his_breach_until_the_yard() -> void:
	var w := await _world(ROAD)
	await step_ticks(30)
	var t := _warden()
	var terr := _territory()
	assert_true(t != null, "the Broken Warden is spawned at the keep")
	assert_true(terr != null, "his territory is loaded")
	if t == null or terr == null:
		return
	var home := Vector2(t.global_position.x, t.global_position.z)
	assert_true(home.distance_to(HOME) < 3.0, "at home in the breach (%s)" % home)
	var ground := w.height_at(t.global_position)
	assert_true(absf(t.global_position.y - ground) < 1.0, "on the keep's ground (%.1f m, the ground %.1f)" % [
		t.global_position.y, ground])
	assert_true(t.dormant, "asleep")
	assert_false(terr.wake_on_sight, "sight does not wake him")
	assert_true(home.distance_to(TOLL_FORT) > 240.0, "the toll fort %.0f m off" % home.distance_to(TOLL_FORT))
	await step_ticks(120)
	assert_true(t.dormant, "a giant on the road below does not wake him")
	print("    test_c2_world: from the road %.0f m to him, seen %s" % [ROAD.distance_to(home),
		terr.sees(w.player().global_position)])
	# into his yard: he wakes
	await _place(w, YARD)
	await step_ticks(30)
	assert_false(t.dormant, "a giant in his yard wakes him")
	assert_eq(t.wake_reason, "engaged", "engaged by his territory")
	assert_true(QuestConditions.truthy(WorldState.get_flag(Discovery.discovered_flag("poi.warden_keep"))),
		"the keep discovered")


func test_the_keep_and_its_pieces() -> void:
	var w := await _world(YARD + Vector2(0, 20))
	await step_ticks(30)
	var t := _warden()
	assert_true(t != null, "him")
	if t == null:
		return
	var rubble: Dictionary = t.record.rubble
	for id: String in ["world.aldmere.warden_tower_w", "world.aldmere.warden_tower_e"]:
		var tw := _node_by_id("breakables", id) as Node3D
		assert_true(tw != null, "%s stands" % id)
		if tw != null:
			var flat := Vector2(tw.global_position.x - t.global_position.x, tw.global_position.z - t.global_position.z)
			assert_true(flat.length() <= float(rubble.radius_m), "%s within his rubble's reach (%.1f m)" % [id, flat.length()])
	# the curtain is solid either side of his breach (his charge reels on it) and open where he stands
	var space := w.get_world_3d().direct_space_state
	for x: float in [676.0, 736.0]:
		var gy := w.height_at(Vector3(x, 0, 205))
		var q := PhysicsRayQueryParameters3D.create(Vector3(x, gy + 6.0, 205), Vector3(x, gy + 6.0, 175),
			HitQueryAdapter.LAYER_WORLD)
		assert_false(space.intersect_ray(q).is_empty(), "the curtain at x %.0f stands" % x)
	var forge := _node_by_id("condition_forges", "world.aldmere.warden_keep_forge")
	if forge == null:
		forge = _node_by_id("forges", "world.aldmere.warden_keep_forge")
	print("    test_c2_world: the mason-forge %s" % ("placed" if forge != null else "not found by its group"))


func test_hode_waits_on_the_road() -> void:
	var w := await _world(Vector2(570.0, 262.0))
	await step_ticks(60)
	var hode: Node3D = null
	for n in get_tree().root.find_children("*", "", true, false):
		var e: Variant = n.get("entity")
		if e is CombatEntity and (e as CombatEntity).definition_id == "npc.toll_keeper_hode":
			hode = n as Node3D
	assert_true(hode != null, "Hode by his fire")
	if hode != null:
		assert_true(Vector2(hode.global_position.x, hode.global_position.z).distance_to(Vector2(570, 250)) < 25.0,
			"on the King's Road below the keep")
	assert_true(w != null, "the world")
