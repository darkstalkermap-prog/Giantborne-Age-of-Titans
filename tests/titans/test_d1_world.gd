extends IntegrationSuite
## D1 in the real open world (scenes/world/world.tscn, deterministic streaming), on the Rimeglass over the Hoarwatch:
##   * the Frostbound Titan is at home kneeling in the tarn's ice, asleep; the shelf's edge (the warning post) does not
##     wake him; a giant walking out onto the ice does (engaged) and the Rimeglass is discovered; his intro plays;
##   * the shelf is reached from the Hoarwatch: no wall where the two lands join, the bounds walls standing north of the
##     Hoarfell's east edge and the shelf's west edge elsewhere; the shelf's west face is a cliff over the Hoarfell;
##   * the tarn's ice (IceSheet) is loaded over the tarn's bed; the watchers' balefires are dark before Maera's lead and
##     lit (warming) after it; Last Hearth's forge and the Colossus Anvil work his ice;
##   * the walk from the Colossus Steps' waystone up the Steps and onto the shelf has lesser life on it (rimkin, trolls,
##     wolves within a few hundred metres of the path).
## The titans' tier (--titans; --gate runs it): it loads the world, as the Rootwarden's grove duel does.

const SCENE := "res://scenes/world/world.tscn"
const HOME := Vector2(638.0, -1612.0)
const SHELF_EDGE := Vector2(540.0, -1600.0)
const ICE := Vector2(612.0, -1590.0)
const HOARWATCH := Vector2(452.0, -1615.0)


func after_each() -> void:
	get_tree().paused = false
	for f in Formation.live():
		f.dissolve()
	FactionState.reset_for_tests()
	WanderDirector.reset_for_tests()
	GameSession.expansion = ExpansionState.defaults()
	await super()


func _world(xz: Vector2, stage := 7) -> WorldRoot:
	GameSession.start_world_for_tests("world.cp.breach_top")
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
	var at := Vector3(xz.x, 300.0, xz.y)
	p.process_mode = Node.PROCESS_MODE_DISABLED
	p.global_position = at
	var guard := 0
	while not w.streamer.ring_ready(at) and guard < 900:
		w.streamer.load_ring_slice(at)
		await step_ticks(1)
		guard += 1
	var y := w.height_at(at)
	p.global_position = Vector3(xz.x, (y if not is_nan(y) else 262.0) + 0.3, xz.y)
	p.velocity = Vector3.ZERO
	p.process_mode = Node.PROCESS_MODE_INHERIT


func _titan() -> TitanEnemy:
	for n in get_tree().root.find_children("*", "TitanEnemy", true, false):
		var t := n as TitanEnemy
		if t.entity != null and t.entity.definition_id == "enemy.frostbound":
			return t
	return null


func _territory() -> TitanTerritory:
	for n in get_tree().get_nodes_in_group(BossArena.GROUP):
		if n is TitanTerritory and (n as TitanTerritory).boss_id == "world.hoarfell.frostbound":
			return n
	return null


func test_he_sleeps_in_the_ice_until_a_giant_walks_out_onto_it() -> void:
	var w := await _world(SHELF_EDGE)
	await step_ticks(40)
	var t := _titan()
	var terr := _territory()
	assert_true(t != null, "the Frostbound is spawned at the tarn")
	assert_true(terr != null, "his territory is loaded")
	if t == null or terr == null:
		return
	var home := Vector2(t.global_position.x, t.global_position.z)
	assert_true(home.distance_to(HOME) < 3.0, "at home in the tarn's ice (%s)" % home)
	var ground := w.height_at(t.global_position)
	assert_true(absf(t.global_position.y - ground) < 1.0, "on the tarn's bed (%.1f m, the ground %.1f)" % [
		t.global_position.y, ground])
	assert_true(t.dormant, "asleep")
	assert_false(terr.wake_on_sight, "sight does not wake him")
	await step_ticks(120)
	assert_true(t.dormant, "a giant at the shelf's edge does not wake him")
	var sheet := IceSheet.sheet_at(get_tree(), Vector3(ICE.x, ground, ICE.y))
	assert_true(sheet != null, "the tarn's ice is loaded")
	if sheet != null:
		assert_true(absf(sheet.global_position.y - ground) < 1.5, "its ice on the tarn's bed")
	await _place(w, ICE)
	await step_ticks(40)
	assert_false(t.dormant, "a giant out on the ice wakes him")
	assert_eq(t.wake_reason, "engaged", "engaged by his territory")
	assert_true(QuestConditions.truthy(WorldState.get_flag(Discovery.discovered_flag("poi.rimeglass"))),
		"the Rimeglass discovered")


func test_the_shelf_joins_the_hoarwatch_and_nothing_else() -> void:
	var w := await _world(HOARWATCH)
	await step_ticks(20)
	var space := w.get_world_3d().direct_space_state
	var mask := SceneKit.L_BLOCKER
	# across the join (the Hoarwatch's shelf onto the Rimeglass): no wall
	var y := w.height_at(Vector3(500, 0, -1615))
	var q := PhysicsRayQueryParameters3D.create(Vector3(480, y + 8.0, -1615), Vector3(520, y + 8.0, -1615), mask)
	assert_true(space.intersect_ray(q).is_empty(), "no wall where the Hoarwatch's shelf runs onto the Rimeglass")
	# south of the join, the Hoarfell's east wall stands (no walking up the cliff from the Hoarfell)
	for z: float in [-1520.0, -1470.0]:
		var gy := w.height_at(Vector3(495, 0, z))
		var q2 := PhysicsRayQueryParameters3D.create(Vector3(490, gy + 6.0, z), Vector3(512, gy + 6.0, z), mask)
		assert_false(space.intersect_ray(q2).is_empty(), "the Hoarfell's east wall stands at z %.0f" % z)
	var hoarfell := w.height_at(Vector3(470, 0, -1520))
	var shelf := w.height_at(Vector3(530, 0, -1520))
	assert_true(shelf - hoarfell > 40.0, "the shelf stands sheer over the Hoarfell (%.0f m over %.0f m)" % [shelf,
		hoarfell])


func test_the_watchers_fires_are_lit_by_maeras_lead() -> void:
	var w := await _world(Vector2(560.0, -1540.0))
	await step_ticks(20)
	var at := Vector3(556.0, w.height_at(Vector3(556, 0, -1566)), -1566.0)
	assert_false(WarmthSource.warm_at(get_tree(), at), "before the lead: no fire on the shore")
	WorldState.set_flag("lead.frostbound.hearth", true)
	await step_ticks(5)
	assert_true(WarmthSource.warm_at(get_tree(), at), "after it: the watchers' balefire warms him")


func test_lesser_life_on_the_walk() -> void:
	var near := {}
	for id: String in ["encounter.hoarfell_rime_rimkin", "encounter.hoarfell_serac_trolls",
			"encounter.hoarfell_shelf_wolves"]:
		var rec := GameData.get_record(id)
		assert_false(rec.is_empty(), "%s exists" % id)
		var c: Array = rec.center_m
		near[id] = Vector2(float(c[0]), float(c[2])).distance_to(SHELF_EDGE)
		assert_true(float(near[id]) < 260.0, "%s within reach of the walk (%.0f m)" % [id, float(near[id])])
	var w := await _world(Vector2(570.0, -1500.0))
	await step_ticks(90)
	var kinds := {}
	for n in get_tree().root.find_children("*", "", true, false):
		var e: Variant = n.get("entity")
		if e is CombatEntity and (e as CombatEntity).is_alive():
			kinds[(e as CombatEntity).definition_id] = int(kinds.get((e as CombatEntity).definition_id, 0)) + 1
	assert_true(int(kinds.get("enemy.rimkin_giant", 0)) >= 2, "rimkin on the shelf (%s)" % str(kinds))
	assert_true(w != null, "the world")
