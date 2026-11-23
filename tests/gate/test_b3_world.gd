extends IntegrationSuite
## B3 in the real open world (scenes/world/world.tscn, deterministic streaming), in the deep Greywood:
##   * the Rootwarden is at home in his grove, asleep and rooted; his territory sleeps (wake_on_sight off): a giant on
##     the warden ride's lookout and one walking into his hollow do not wake him - the grove is discovered; before the
##     woodfolk's call the hollow's engage trigger does nothing, after it the giant entering wakes him (engaged);
##   * the grove's pieces: the ring of trunks and the root arch (solid), the dead trees standing till he is at rest and
##     the saplings after it (FlagVisibility on the greening), the resin pots only once the woodfolk laid them;
##   * Hollowmere: Wren's woodworks works warden wood, shut while he stands, then the Warden Mantle from his bark and
##     heartwood; the woodfolk's heartwood stacked by her benches after his rest.

const SCENE := "res://scenes/world/world.tscn"
const GROVE := Vector2(-790.0, 200.0)
const LOOKOUT := Vector2(-712.0, 140.0)
const HOLLOWMERE := Vector2(-592.0, -24.0)


func after_each() -> void:
	get_tree().paused = false
	for f in Formation.live():
		f.dissolve()
	FactionState.reset_for_tests()
	WanderDirector.reset_for_tests()
	GameSession.expansion = ExpansionState.defaults()
	await super()


func _world(xz: Vector2, stage := 5) -> WorldRoot:
	GameSession.start_world_for_tests("world.cp.hollowmere")
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
	p.global_position = Vector3(xz.x, (y if not is_nan(y) else 20.0) + 0.3, xz.y)
	p.velocity = Vector3.ZERO
	p.process_mode = Node.PROCESS_MODE_INHERIT


func _warden() -> TitanEnemy:
	for n in get_tree().root.find_children("*", "TitanEnemy", true, false):
		var t := n as TitanEnemy
		if t.entity != null and t.entity.definition_id == "enemy.rootwarden":
			return t
	return null


func _territory() -> TitanTerritory:
	for n in get_tree().get_nodes_in_group(BossArena.GROUP):
		if n is TitanTerritory and (n as TitanTerritory).boss_id == "world.greywood.rootwarden":
			return n
	return null


func _flag_node(id: String) -> FlagVisibility:
	for n in get_tree().get_nodes_in_group(FlagVisibility.GROUP):
		if str(n.name) == id.validate_node_name() or str(n.name) == (id + "_shown").validate_node_name():
			return n as FlagVisibility
	return null


func _node_by_id(group: String, id: String) -> Node:
	for n in get_tree().get_nodes_in_group(group):
		if str(n.get("world_id")) == id:
			return n
	return null


func test_he_sleeps_at_home_until_the_call() -> void:
	var w := await _world(LOOKOUT)
	await step_ticks(30)
	var t := _warden()
	var terr := _territory()
	assert_true(t != null, "the Rootwarden is spawned in his grove")
	assert_true(terr != null, "his territory is loaded")
	if t == null or terr == null:
		return
	var home := Vector2(t.global_position.x, t.global_position.z)
	assert_true(home.distance_to(Vector2(-796.0, 186.0)) < 3.0, "at home (%s)" % home)
	assert_true(t.global_position.y > 15.0 and t.global_position.y < 20.0, "on the hollow's floor (%.1f m)" % t.global_position.y)
	assert_true(t.dormant and t.is_rooted(), "asleep and rooted")
	assert_false(terr.wake_on_sight, "sight does not wake him")
	assert_eq(terr.state_name(), "waiting", "his territory waits")
	print("    test_b3_world: from the lookout %.0f m to him, seen %s" % [
		Vector2(LOOKOUT).distance_to(home), terr.sees(w.player().global_position)])
	# into his hollow before the call: the grove discovered, he sleeps on
	await _place(w, GROVE + Vector2(20.0, 8.0))
	await step_ticks(120)
	assert_true(t.dormant, "a giant in his hollow does not wake him")
	assert_eq(terr.state_name(), "waiting", "nor engages his territory")
	assert_true(terr.seen_asleep >= 1, "seen asleep")
	assert_true(QuestConditions.truthy(WorldState.get_flag(Discovery.discovered_flag("poi.rootwarden_grove"))),
		"the grove discovered")
	# the woodfolk's call: walking into the hollow now wakes him
	await _place(w, LOOKOUT)
	await step_ticks(10)
	WorldState.try_set_flag("world.rootwarden.called", true)
	WorldState.try_set_flag("world.rootwarden.resin_laid", true)
	await _place(w, GROVE + Vector2(20.0, 8.0))
	await step_ticks(30)
	assert_false(t.dormant, "after the call the hollow wakes him")
	assert_eq(t.wake_reason, "engaged", "engaged by his territory")
	assert_eq(terr.state_name(), "engaged", "his territory engaged")
	var resin := _flag_node("world.greywood.rootwarden_resin_1")
	assert_true(resin != null and resin.visible, "the woodfolk's resin pot laid among his watch-fires")


func test_the_grove_and_its_greening() -> void:
	var w := await _world(LOOKOUT)
	await _place(w, GROVE + Vector2(30.0, -6.0))
	await step_ticks(5)
	var dead := _flag_node("world.greywood.rootwarden_dead_trees")
	var saplings := _flag_node("world.greywood.rootwarden_saplings")
	var resin := _flag_node("world.greywood.rootwarden_resin_1")
	assert_true(dead != null and saplings != null and resin != null, "the grove's flagged pieces are placed")
	if dead == null or saplings == null or resin == null:
		return
	assert_true(dead.visible, "his dead trees stand")
	assert_false(saplings.visible, "no saplings yet")
	assert_false(resin.visible, "no resin before the call")
	# the ring's trunks are solid (12 of them, 4-6 m through, about 45 m out: a fifth of the rays from his spot)
	var space := (w as Node3D).get_world_3d().direct_space_state
	var hits := 0
	for k in 24:
		var a := TAU * float(k) / 24.0
		var from := Vector3(GROVE.x, 30.0, GROVE.y)
		var to := from + Vector3(cos(a), 0, sin(a)) * 70.0
		var q := PhysicsRayQueryParameters3D.create(from, to, SceneKit.L_WORLD)
		if not space.intersect_ray(q).is_empty():
			hits += 1
	assert_true(hits >= 4, "the ring of trunks stands round the hollow (%d of 24 rays)" % hits)
	WorldState.try_set_flag("boss.rootwarden.defeated", true)
	WorldState.try_set_flag("world.greywood.grove_greened", true)
	await step_ticks(2)
	assert_false(dead.visible, "greened: the dead trees gone")
	assert_true(saplings.visible, "young trees where they stood")


func test_wrens_woodworks_and_the_heartwood() -> void:
	var w := await _world(HOLLOWMERE)
	var p := w.player()
	await step_ticks(5)
	var forge := _node_by_id("forges", "world.greywood.hollowmere_woodwright") as Forge
	assert_true(forge != null, "Wren's woodworks is placed")
	var logs := _flag_node("world.greywood.hollowmere_heartwood")
	assert_true(logs != null and not logs.visible, "no heartwood yet")
	if forge == null:
		return
	assert_true(forge.does_work("warden_wood"), "it works warden wood")
	assert_false(forge.is_open(), "shut while he stands")
	WorldState.add_item("item.warden_bark", 4, "test")
	WorldState.add_item("item.warden_heartwood", 1, "test")
	assert_eq(str(forge.can_craft(p, "recipe.warden_mantle").reason), "closed", "so nothing is made")
	WorldState.try_set_flag("boss.rootwarden.defeated", true)
	await step_ticks(2)
	assert_true(forge.is_open(), "open once he is at rest")
	var made := forge.craft(p, "recipe.warden_mantle")
	assert_true(made.ok, "the Warden Mantle from his bark and heartwood: %s" % made.message)
	assert_true(Armour.owns(GameSession.expansion.equipment, "armour.warden_mantle"), "owned")
	if logs != null:
		assert_true(logs.visible, "the woodfolk's heartwood stacked by her benches")
