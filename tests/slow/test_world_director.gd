extends IntegrationSuite
## P24b (plan M6-M9 §2.8, decision 15): the encounter director and the actors in the streamed test
## world (scenes/test/test_world.tscn with its navmeshes; deterministic streaming):
##   * a wolf pack and a soldier band chase the giant across a chunk seam (x = -256 and x = 0) on the
##     per-chunk navmeshes of their layer's map without a path failure (a soldier's failures are read
##     when it reaches the giant: crowding round it afterwards, without avoidance, is not navigation);
##   * a member standing in a chunk that unloads is despawned before the chunk goes (not killed), and
##     an encounter centred in it deactivates at once; the member comes back at home, at full health,
##     on its encounter's next activation;
##   * no member spawns on a chunk that is not loaded and ready: it waits, and spawns once its ground
##     streams in;
##   * spawn entries' min_stage / max_stage sit members out of an activation by the giant's stage, and
##     a member sitting one out does not keep its encounter from being cleared.

const SCENE := "res://scenes/test/test_world.tscn"
const WOLVES := "encounter.test_world_wolves"
const BAND := "encounter.test_world_soldiers"
const POND := "encounter.test_world_pond"


## The test world with the giant at (x, z) on the ground and the ring around it ready.
func _world(xz: Vector2) -> WorldRoot:
	var w := (load(SCENE) as PackedScene).instantiate() as WorldRoot
	world.add_child(w)
	w.streamer.deterministic = true
	await _go(w, xz)
	return w


## Puts the giant at (x, z) - held still above the ground until the ring around it has streamed in
## (slices and ticks, so the maps sync; WorldRoot focuses the streamer on the giant meanwhile) - then
## on the ground there.
func _go(w: WorldRoot, xz: Vector2) -> void:
	var p := w.player()
	var at := Vector3(xz.x, 200.0, xz.y)
	p.process_mode = Node.PROCESS_MODE_DISABLED
	p.global_position = at
	var guard := 0
	while not w.streamer.ring_ready(at) and guard < 300:
		w.streamer.load_ring_slice(at)
		await step_ticks(1)
		guard += 1
	var y := w.height_at(at)
	p.global_position = Vector3(xz.x, (y if not is_nan(y) else 20.0) + 0.3, xz.y)
	p.velocity = Vector3.ZERO
	p.process_mode = Node.PROCESS_MODE_INHERIT


## Walks the giant (stick, no sprint) toward (x, z) until it is within 2 m or `max_ticks` passed.
func _walk_to(w: WorldRoot, xz: Vector2, max_ticks: int) -> void:
	var p := w.player()
	p.router.use_injection = true
	for i in max_ticks:
		var to := Vector3(xz.x - p.global_position.x, 0.0, xz.y - p.global_position.z)
		if to.length() < 2.0:
			break
		p.camera_rig.yaw = TargetingRules.yaw_of(to)
		p.router.set_injected_move(Vector2(0, 1))
		p.router.set_injected_hold(&"sprint", false)
		await step_ticks(1)
	p.router.set_injected_move(Vector2.ZERO)


func _members(d: EncounterDirector, enc: String) -> Array[EnemyActor]:
	var out: Array[EnemyActor] = []
	for id in d.members_of(enc):
		var n := d.spawned(id) as EnemyActor
		if n != null and n.entity.is_alive():
			out.append(n)
	return out


func _path_failures(d: EncounterDirector, enc: String) -> int:
	var n := 0
	for m in _members(d, enc):
		n += m.path_failures
	return n


func _wait(cond: Callable, max_ticks: int) -> bool:
	for i in max_ticks:
		if cond.call():
			return true
		await step_ticks(1)
	return bool(cond.call())


func test_a_wolf_pack_and_a_soldier_band_chase_the_giant_across_a_seam() -> void:
	var w: WorldRoot = await _world(Vector2(-228.0, -200.0))
	var d := w.director()
	var p := w.player()
	assert_true(await _wait(func() -> bool: return _members(d, WOLVES).size() == 5, 120), "the wolf pack spawned")
	assert_true(await _wait(func() -> bool:
		for m in _members(d, WOLVES):
			if not m.brain.aware:
				return false
		return true, 300), "the pack noticed the giant")
	var hits_before := hits_on(p.entity.entity_id).size()
	await _walk_to(w, Vector2(-290.0, -200.0), 900)
	assert_true(p.global_position.x < -256.0, "the giant walked west over the x = -256 seam (x %.1f)" % p.global_position.x)
	await step_ticks(300)
	var west := 0
	for m in _members(d, WOLVES):
		if m.global_position.x < -256.0:
			west += 1
	assert_true(west >= 3, "the wolves followed it into the next chunk (%d of %d west of the seam)" % [west, _members(d, WOLVES).size()])
	assert_true(hits_on(p.entity.entity_id).size() > hits_before, "and attacked it there")
	assert_eq(_path_failures(d, WOLVES), 0, "no wolf had a path failure")
	for m in _members(d, WOLVES):
		assert_eq(m.agent.get_navigation_map(), w.nav_map(1), "%s paths on the human layer's own map" % m.entity_id)
	# The soldier band across x = 0: the giant shows itself on the east side (c2_2), in front of them,
	# then walks into the west chunk (c1_2); the soldiers follow it over the seam, the two whose homes
	# are east of it (soldier_3 and soldier_4) on a navmesh that lies up to 0.8 m over their feet there.
	await _go(w, Vector2(24.0, 86.0))
	assert_true(await _wait(func() -> bool: return _members(d, BAND).size() >= 4, 240), "the soldier band spawned")
	assert_true(await _wait(func() -> bool:
		for m in _members(d, BAND):
			if m.brain.aware:
				return true
		return false, 300), "the band noticed the giant")
	await step_ticks(60)
	await _walk_to(w, Vector2(-36.0, 100.0), 900)
	assert_true(p.global_position.x < -30.0, "the giant walked west over the x = 0 seam (x %.1f)" % p.global_position.x)
	var arrived := {}   # entity id -> its path failures when it first stood within 6 m of the giant
	for i in 600:
		for m in _members(d, BAND):
			if not arrived.has(m.entity_id) and Vector2(m.global_position.x - p.global_position.x,
					m.global_position.z - p.global_position.z).length() < 6.0:
				arrived[m.entity_id] = m.path_failures
		if arrived.size() >= _members(d, BAND).size():
			break
		await step_ticks(1)
	var band := _members(d, BAND)
	var east := 0
	for m in band:
		if float(m.home_position.x) > 0.0 and arrived.has(m.entity_id):
			east += 1
	assert_eq(arrived.size(), band.size(), "every soldier reached the giant beyond the seam (%s)" % [arrived.keys()])
	assert_eq(east, 2, "the two from the east chunk among them")
	var failures := 0
	for id: String in arrived:
		failures += int(arrived[id])
	assert_eq(failures, 0, "no soldier had a path failure on the way (%s)" % [arrived])
	for m in band:
		assert_eq(m.agent.get_navigation_map(), w.nav_map(1), "%s paths on the human layer's own map" % m.entity_id)


func test_members_in_an_unloading_chunk_despawn_and_come_back_at_home() -> void:
	var w: WorldRoot = await _world(Vector2(-228.0, -200.0))
	var d := w.director()
	d.unaware_deactivate_s = 0.5
	assert_true(await _wait(func() -> bool: return _members(d, WOLVES).size() == 5, 120), "the wolf pack spawned")
	# One wolf strays into c0_1; the giant goes far east (c3_1): c0_1 unloads, the pack's own chunk does not.
	var stray := d.spawned("test_world.wolves.wolf_3") as EnemyActor
	stray.ai_enabled = false
	stray.global_position = Vector3(-300.0, w.height_at(Vector3(-300, 0, -200)) + 0.3, -200.0)
	stray.entity.combatant.pools.health = stray.entity.combatant.pools.health_max * 0.5
	var events: Array = []
	w.streamer.chunk_unloading.connect(func(id: String) -> void: events.append([id, d.member_status("test_world.wolves.wolf_3")]))
	await _go(w, Vector2(300.0, -200.0))
	assert_true(await _wait(func() -> bool: return not w.streamer.is_loaded("c0_1"), 120), "c0_1 unloaded")
	assert_eq(d.member_status("test_world.wolves.wolf_3"), "despawned", "the stray wolf was despawned, not killed")
	assert_true(d.spawned("test_world.wolves.wolf_3") == null, "its node is gone")
	assert_false(WorldState.is_killed("test_world.wolves.wolf_3"), "no kill recorded")
	assert_true(w.streamer.is_loaded("c1_1"), "the pack's own chunk is still loaded")
	# The pack deactivates (the giant far away) and comes back with the stray at home and healthy.
	assert_true(await _wait(func() -> bool: return d.encounter_state(WOLVES) == "dormant", 1200), "the pack deactivated")
	await _go(w, Vector2(-228.0, -200.0))
	assert_true(await _wait(func() -> bool: return d.member_status("test_world.wolves.wolf_3") == "spawned", 240),
		"the stray came back on the next activation")
	var back := d.spawned("test_world.wolves.wolf_3") as EnemyActor
	assert_true(back != null and Vector2(back.global_position.x + 248.0, back.global_position.z + 200.0).length() < 3.0,
		"at its home (%s)" % (back.global_position if back != null else Vector3.INF))
	assert_near(back.entity.combatant.pools.health, back.entity.combatant.pools.health_max, 0.01, "at full health")
	# An encounter centred in an unloading chunk deactivates at once (the pond watch, c0_2).
	await _go(w, Vector2(-300.0, 120.0))
	assert_true(await _wait(func() -> bool: return d.encounter_state(POND) == "active", 120), "the pond watch activated")
	d.unaware_deactivate_s = 1000.0   # only the unload may end it now
	await _go(w, Vector2(300.0, 120.0))
	assert_true(await _wait(func() -> bool: return not w.streamer.is_loaded("c0_2"), 120), "c0_2 unloaded")
	assert_eq(d.encounter_state(POND), "dormant", "the pond watch deactivated with its chunk")
	assert_eq(_members(d, POND).size(), 0, "its members are gone")


func test_no_member_spawns_on_ground_that_is_not_ready() -> void:
	var w: WorldRoot = await _world(Vector2(130.0, -200.0))
	var d := w.director()
	assert_false(w.streamer.is_loaded("c0_1"), "c0_1 is not loaded (the giant is two chunks east)")
	assert_true(w.streamer.is_ready("c1_1"), "the pack's centre chunk is ready")
	d.force_activate(WOLVES)
	d.update_now()
	assert_eq(d.encounter_state(WOLVES), "active", "the pack activated")
	for id: String in ["test_world.wolves.wolf_1", "test_world.wolves.wolf_2"]:
		assert_eq(d.member_status(id), "unspawned", "%s waits: its spawn point is in c0_1" % id)
	for id: String in ["test_world.wolves.wolf_3", "test_world.wolves.wolf_4", "test_world.wolves.wolf_runt"]:
		assert_eq(d.member_status(id), "spawned", "%s spawned on ready ground (c1_1)" % id)
	for n in get_tree().get_nodes_in_group("enemies"):
		var c := w.chunk_at((n as Node3D).global_position)
		assert_true(c == "" or w.streamer.is_ready(c), "%s stands on a ready chunk (%s)" % [n.name, c])
	await _go(w, Vector2(-200.0, -200.0))
	assert_true(await _wait(func() -> bool: return w.streamer.is_ready("c0_1"), 60), "c0_1 streamed in")
	assert_true(await _wait(func() -> bool: return d.member_status("test_world.wolves.wolf_1") == "spawned" \
		and d.member_status("test_world.wolves.wolf_2") == "spawned", 120), "the waiting wolves spawned once their ground was ready")


func test_spawn_entries_follow_the_giants_stage() -> void:
	var w: WorldRoot = await _world(Vector2(-228.0, -200.0))
	var d := w.director()
	var p := w.player()
	assert_eq(p.current_growth_stage(), 1, "a stage-1 giant")
	assert_true(await _wait(func() -> bool: return d.member_status("test_world.wolves.wolf_runt") == "spawned", 120),
		"the runt (max_stage 2) runs with a stage-1 giant")
	d.force_activate(BAND)
	d.update_now()
	assert_true(d.stage_skipped("test_world.band.sergeant"), "the sergeant (min_stage 3) sits this activation out")
	assert_eq(d.member_status("test_world.band.sergeant"), "unspawned", "and does not spawn")
	var band := _members(d, BAND)
	assert_eq(band.size(), 4, "the other four did")
	for m in band:
		queue_hit("player", m.entity_id, m.global_position + Vector3(0, 0, 2), 99999.0, PackedStringArray(["Melee"]))
	await step_ticks(2)
	assert_eq(d.encounter_state(BAND), "cleared", "the band is cleared without the sergeant who sat out")
	# A stage-3 giant: the pack comes back without its runt. The giant leaves for c2_1 (the pack's
	# chunk stays loaded); the pack loses it first (an alert group keeps itself aware while one is).
	d.unaware_deactivate_s = 0.5
	for m in _members(d, WOLVES):
		m.ai_enabled = false
		m.brain.aware = false
	await _go(w, Vector2(200.0, -200.0))
	assert_true(await _wait(func() -> bool: return d.encounter_state(WOLVES) == "dormant", 1200), "the pack deactivated")
	p.growth.debug_set_stage(3)
	assert_eq(p.current_growth_stage(), 3, "grown to stage 3")
	await _go(w, Vector2(-228.0, -200.0))
	assert_true(await _wait(func() -> bool: return d.encounter_state(WOLVES) == "active", 120), "the pack activated again")
	d.update_now()
	assert_true(d.stage_skipped("test_world.wolves.wolf_runt"), "the runt sits out a stage-3 giant")
	assert_eq(d.member_status("test_world.wolves.wolf_runt"), "unspawned", "it does not spawn")
	assert_eq(_members(d, WOLVES).size(), 4, "the other four do")
