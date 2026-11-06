extends IntegrationSuite
## P24b (plan M6-M9 §2.8, §6.3; the risk of unthrottled unlimited-polygon re-paths): 20 humans chase
## a giant that wades in the test world's deep water - the pond (c0_2), where no human navmesh lies
## deeper than 1 m - for 20 s, and the simulation keeps its CPU per tick p95 at most 8 ms (headless
## desktop; PerfProbe's cpu_tick_ms, the physics tick measured from inside) with the tier-0 re-path
## throttle and the per-tick query budget of the level's nav_query block:
##   * no tick re-paths more agents than queries_per_tick (8) - the rest wait a tick: when all twenty
##     ask at once (request_repath, as after a path failure), eight a tick are served;
##   * an agent re-paths at most once every repath_min_ticks (6) unless it was asked to (a failure);
##   * the soldiers come down to the bank and stand there: their chase goal is the end of their path
##     (the bank), none walks into the deep water (the human navmesh ends at the 1 m contour, cut on a
##     2 m grid: half a metre of slack).
## No director: the soldiers are spawned round the pond and kept aware as an alert group keeps its
## members (a shout every half second with the giant's position).

const SCENE := "res://scenes/test/test_world.tscn"
const TW := preload("res://tools/builders/test_world.gd")
const SOLDIERS := 20
const RING_M := 47.0           # their start, round the pond's centre (its water reaches 50 m)
const RUN_TICKS := 1200
const SHOUT_TICKS := 30
## The tick of the run at which every soldier is asked to re-path at once.
const ASK_ALL_AT := 600
## The giant wades back and forth here, 15 m east of the pond's centre (about 5 m of water).
const WADE_A := Vector2(-365.0, 110.0)
const WADE_B := Vector2(-365.0, 130.0)


## The test world without its director, the giant on the pond's bed at `xz`, the ring ready.
func _world(xz: Vector2) -> WorldRoot:
	var w := (load(SCENE) as PackedScene).instantiate() as WorldRoot
	var d := w.get_node_or_null("EncounterDirector")
	if d != null:
		w.remove_child(d)
		d.free()
	world.add_child(w)
	w.streamer.deterministic = true
	var p := w.player()
	var at := Vector3(xz.x, 200.0, xz.y)
	p.process_mode = Node.PROCESS_MODE_DISABLED
	p.global_position = at
	var guard := 0
	while not w.streamer.ring_ready(at) and guard < 300:
		w.streamer.load_ring_slice(at)
		await step_ticks(1)
		guard += 1
	p.global_position = Vector3(xz.x, w.height_at(at) + 0.3, xz.y)
	p.velocity = Vector3.ZERO
	p.process_mode = Node.PROCESS_MODE_INHERIT
	return w


func test_twenty_humans_chase_a_giant_in_deep_water_within_the_tick_budget() -> void:
	var w: WorldRoot = await _world(WADE_A)
	var p := w.player()
	var gid := p.entity.entity_id
	var settings := NavQuery.settings(w)
	assert_eq(int(settings.queries_per_tick), 8, "the test world's query budget")
	var water := TW.WATER_Y - p.global_position.y
	assert_true(water > 3.0, "the giant stands in %.1f m of water" % water)
	assert_false(NavQuery.closest_point(w, p.global_position, 1).distance_to(p.global_position) < 10.0,
		"no human navmesh within 10 m of it")
	var soldiers: Array[EnemyActor] = []
	for i in SOLDIERS:
		var a := TAU * float(i) / float(SOLDIERS)
		var xz := TW.POND_CENTER + Vector2(cos(a), sin(a)) * RING_M
		var at := Vector3(xz.x, 0.0, xz.y)
		at.y = w.height_at(at) + 0.3
		var e := TestSpawn.enemy(w.spawn_parent(), TestSpawn.SOLDIER_SCENE, at, "p24b.chase.soldier_%02d" % i, true,
			TargetingRules.yaw_of(Vector3(TW.POND_CENTER.x - xz.x, 0.0, TW.POND_CENTER.y - xz.y)))
		soldiers.append(e)
	await step_ticks(1)
	var start := {}
	for e in soldiers:
		assert_eq(e.agent.get_navigation_map(), w.nav_map(1), "%s paths on the human map" % e.entity_id)
		start[e.entity_id] = e.global_position
	var probe := PerfProbe.new()
	probe.label = "unreachable_chase"
	w.add_child(probe)
	p.router.use_injection = true
	var to_b := true
	var last_repath := {}     # entity id -> tick of its last re-path
	var counts := {}          # entity id -> [repath_count, path_failures] last tick
	for e in soldiers:
		counts[e.entity_id] = [e.repath_count, e.path_failures]
	var max_per_tick := 0
	var min_gap := 1 << 30
	var deepest := -INF
	var deepest_at := ""
	var asked := {}           # entity id -> true until its re-path after request_repath()
	var served_by := {}       # entity id -> ticks after the request its re-path came
	for i in RUN_TICKS:
		if i == ASK_ALL_AT:
			for e in soldiers:
				e.request_repath()
				asked[e.entity_id] = true
		if i % SHOUT_TICKS == 0:
			for e in soldiers:
				if not e.brain.aware:
					e.brain.on_noise(Sim.tick, p.global_position, gid, true)
		var goal := WADE_B if to_b else WADE_A
		var to := Vector3(goal.x - p.global_position.x, 0.0, goal.y - p.global_position.z)
		if to.length() < 1.5:
			to_b = not to_b
		p.camera_rig.yaw = TargetingRules.yaw_of(to)
		p.router.set_injected_move(Vector2(0, 0.5))
		p.router.set_injected_hold(&"sprint", false)
		await step_ticks(1)
		var this_tick := 0
		for e in soldiers:
			var c: Array = counts[e.entity_id]
			var n := e.repath_count - int(c[0])
			if n > 0:
				this_tick += n
				if asked.has(e.entity_id):
					asked.erase(e.entity_id)
					served_by[e.entity_id] = i + 1 - ASK_ALL_AT
				elif e.path_failures == int(c[1]) and last_repath.has(e.entity_id):
					min_gap = mini(min_gap, Sim.tick - int(last_repath[e.entity_id]))
				last_repath[e.entity_id] = Sim.tick
			counts[e.entity_id] = [e.repath_count, e.path_failures]
			var depth := TW.WATER_Y - e.global_position.y
			if depth > deepest:
				deepest = depth
				deepest_at = "%s at %s" % [e.entity_id, e.global_position]
		max_per_tick = maxi(max_per_tick, this_tick)
	p.router.set_injected_move(Vector2.ZERO)
	probe.finish()
	var perf := probe.result()
	var repaths := 0
	var failures := 0
	var closer := 0
	var nearest := INF
	for e in soldiers:
		repaths += e.repath_count
		failures += e.path_failures
		var s: Vector3 = start[e.entity_id]
		var before := Vector2(s.x - p.global_position.x, s.z - p.global_position.z).length()
		var now := Vector2(e.global_position.x - p.global_position.x, e.global_position.z - p.global_position.z).length()
		nearest = minf(nearest, now)
		if now < before - 5.0:
			closer += 1
	var waits := {}           # ticks after the request -> soldiers served then
	for id: String in served_by:
		waits[served_by[id]] = int(waits.get(served_by[id], 0)) + 1
	print("    unreachable chase: %d soldiers, %d ticks, %d re-paths (at most %d in a tick, at least %d ticks apart; all asked at once: served %s by ticks after), %d path failures, deepest stand %.2f m (%s), nearest %.1f m; CPU per tick p50 %.2f p95 %.2f p99 %.2f max %.2f ms" % [
		SOLDIERS, RUN_TICKS, repaths, max_per_tick, min_gap, waits, failures, deepest, deepest_at, nearest,
		perf.cpu_tick_ms.p50, perf.cpu_tick_ms.p95, perf.cpu_tick_ms.p99, perf.cpu_tick_ms.max])
	assert_eq(max_per_tick, int(settings.queries_per_tick),
		"never more than %d re-paths in a tick, and that many when all ask (%d)" % [int(settings.queries_per_tick), max_per_tick])
	assert_true(served_by.size() >= SOLDIERS - 2 and asked.size() <= 2,
		"the soldiers asked at once were served (%d; waiting: %s)" % [served_by.size(), asked.keys()])
	assert_true(waits.keys().size() >= 3, "over several ticks (%s)" % [waits])
	assert_true(min_gap >= int(settings.repath_min_ticks),
		"an agent re-paths at most every %d ticks without a failure (%d)" % [int(settings.repath_min_ticks), min_gap])
	assert_true(repaths >= SOLDIERS, "every soldier asked for a path (%d)" % repaths)
	assert_true(deepest <= NavBake.MAX_WADE_M + 0.5, "no soldier walked into the deep water (deepest %.2f m: %s)" % [deepest, deepest_at])
	assert_true(closer >= SOLDIERS * 3 / 4, "they came down to the bank toward the giant (%d of %d closer by 5 m)" % [closer, SOLDIERS])
	assert_true(nearest > 8.0, "none reached it (nearest %.1f m)" % nearest)
	assert_true(float(perf.cpu_tick_ms.p95) <= PerfProbe.BUDGET_TICK_P95_MS,
		"CPU per tick p95 %.2f ms within %.1f ms" % [perf.cpu_tick_ms.p95, PerfProbe.BUDGET_TICK_P95_MS])
