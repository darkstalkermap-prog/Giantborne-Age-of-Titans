extends IntegrationSuite
## P38 (plan M6-M9 §6.1 "Routing", decision 13): the world bot's route planner (BotRoute) on the real
## world - its index's road graph and its streamed titan navmesh (deterministic streaming, AI off).
## The planner's pure rules on graphs built in code: tests/unit/test_bot_route_rules.gd.
##   * the road graph by stage: the Giant's Stair's edges (min stage 6) carry a stage-6 road from its
##     foot to its top and are closed to stage 5; the Needle's slot (direct edges, stage 4 at most) is a
##     stage-4 route's straight steps and is closed to stage 5;
##   * local legs on the titan mask: a stage-4 giant moved along BotRoute's steering from the Brannock
##     waystone to the Drowned Steps' shrine (about 470 m, across two chunk seams, the ring streamed in
##     as it goes) arrives; every leg aims at a route point at most LEG_MAX_M along the route, in a ready
##     chunk, and its path ends within reach of it;
##   * replanning across chunk loads: with only the giant's chunk loaded, the leg stops at the last
##     route point before the next chunk and names it (waiting_chunk); once the ring is ready the next
##     steer asks a new leg into it.

const LEVEL := "level.world"
const START := "world.cp.brannock"
const GOAL := "world.shrine.steps"
const STAGE := 4
const MOVE_M := 10.0
const MAX_MOVES := 300
const ARRIVE_M := 6.0


func _world() -> WorldRoot:
	var w := (load(str(GameData.get_record(LEVEL).scene)) as PackedScene).instantiate() as WorldRoot
	world.add_child(w)
	w.streamer.deterministic = true
	TestSpawn.disable_all_ai(w)
	return w


## Streams the ring around `at` in (loading-screen slices) until it is ready.
func _load_ring(w: WorldRoot, at: Vector3) -> void:
	var guard := 0
	while not w.streamer.ring_ready(at) and guard < 600:
		w.streamer.load_ring_slice(at)
		await step_ticks(1)
		guard += 1


## Puts the giant on the ground at `pos` (its chunk loaded); the grounded position.
func _place(w: WorldRoot, pos: Vector3) -> Vector3:
	pos.y = w.height_at(pos) + 0.5
	w.player().global_position = pos
	return pos


func _route(w: WorldRoot) -> BotRoute:
	var r := BotRoute.new(WorldIndex.for_level(LEVEL), w)
	r.stage = STAGE
	r.layers = PlayerGrowth.nav_query_mask_for_stage(STAGE)
	return r


## The distance from `pos` along the route to its point `i` (from the next point to reach).
static func _along(r: BotRoute, pos: Vector3, i: int) -> float:
	var m := BotRoute.flat_dist(pos, r.points[r.step])
	for k in range(r.step, i):
		m += BotRoute.flat_dist(r.points[k], r.points[k + 1])
	return m


static func _point_index(r: BotRoute, p: Vector3) -> int:
	for i in range(r.step, r.points.size()):
		if r.points[i].is_equal_approx(p):
			return i
	return -1


func test_the_road_graph_by_stage() -> void:
	var idx := WorldIndex.for_level(LEVEL)
	# the Giant's Stair: from below its foot (0, -421) to above its top (0, -530)
	var foot := Vector3(0.0, 0.0, -405.0)
	var top := Vector3(0.0, 0.0, -560.0)
	var up6 := BotRoute.road_path(idx, foot, top, 6)
	var stair := 0
	for e: int in up6.edges:
		assert_true(idx.edge_allowed(e, 6), "every edge of the stage-6 road is open at stage 6")
		if not idx.edge_allowed(e, 5):
			stair += 1
	assert_true(stair >= 3, "the stage-6 road climbs the Giant's Stair (%d of its edges closed below stage 6)" % stair)
	var up5 := BotRoute.road_path(idx, foot, top, 5)
	for e: int in up5.edges:
		assert_true(idx.edge_allowed(e, 5), "a stage-5 road takes no edge closed to stage 5")
	assert_true((up5.nodes as PackedInt32Array).is_empty() or float(up5.length) > 2.0 * float(up6.length),
		"stage 5 has no way up the Stair: no road, or a long way round (%.0f m against %.0f m)" % [up5.length, up6.length])
	# the Needle: from its waystone through the slot to the grove's far side
	var needle := idx.position_of("world.cp.needle")
	var beyond := Vector3(-480.0, 27.0, -10.0)
	var r4 := BotRoute.new(idx, null)
	r4.stage = 4
	r4.plan(needle, beyond)
	var direct4 := 0
	for d in r4.direct:
		direct4 += int(d)
	assert_true(direct4 >= 4, "a stage-4 route walks the Needle's slot in straight steps (%d direct)" % direct4)
	for e: int in r4.edges:
		assert_true(idx.edge_allowed(e, 4), "every edge of it is open at stage 4")
	var r5 := BotRoute.new(idx, null)
	r5.stage = 5
	r5.plan(needle, beyond)
	assert_false(r5.direct.has(1), "the slot is closed to a stage-5 giant: no direct step")
	print("    test_bot_route: the Stair at stage 6 %.0f m (%d stair edges), stage 5 %s; the Needle %d direct steps at stage 4" % [
		up6.length, stair, "no road" if (up5.nodes as PackedInt32Array).is_empty() else "%.0f m" % up5.length, direct4])


func test_a_stage_4_giant_follows_its_legs_across_the_streamed_world() -> void:
	var w := _world()
	var idx := WorldIndex.for_level(LEVEL)
	var start := idx.position_of(START)
	var goal := idx.position_of(GOAL)
	await _load_ring(w, start)
	var pos := _place(w, start)
	var r := _route(w)
	assert_true(r.plan(pos, goal), "a road joins the Brannock waystone to the Steps' shrine")
	var planned_m := r.remaining_m(pos)
	var targets := 0
	var last_target := Vector3.INF
	var worst_along := 0.0
	var off_ready := PackedStringArray()
	var too_far := PackedStringArray()
	var moves := 0
	var walked := 0.0
	var chunks := {}
	var tick := 0
	while moves < MAX_MOVES and BotRoute.flat_dist(pos, goal) > ARRIVE_M:
		var aim := r.steer(pos, tick, w)
		if r.leg_target.is_finite() and not r.leg_target.is_equal_approx(last_target):
			targets += 1
			last_target = r.leg_target
			var i := _point_index(r, r.leg_target)
			var along := _along(r, pos, maxi(i, r.step))
			if i > r.step:
				worst_along = maxf(worst_along, along)
				if along > BotRoute.LEG_MAX_M + 0.5:
					too_far.append("%s: %.0f m along" % [r.leg_target, along])
			if BotRoute.chunk_waiting(w, r.leg_target) != "":
				off_ready.append(str(r.leg_target))
		var d := aim - pos
		d.y = 0.0
		var step_m := minf(MOVE_M, d.length())
		if step_m < 0.05:
			break
		pos = _place(w, pos + d.normalized() * step_m)
		walked += step_m
		chunks[w.streamer.chunk_at(pos)] = true
		moves += 1
		tick += 20
		if not w.streamer.ring_ready(pos):
			await _load_ring(w, pos)
	var left := BotRoute.flat_dist(pos, goal)
	print("    test_bot_route: %.0f m planned, %.0f m walked in %d moves, %d leg targets (farthest %.0f m along), %d queries, %d short legs, chunks %s" % [
		planned_m, walked, moves, targets, worst_along, r.leg_queries, r.short_legs, chunks.keys()])
	assert_true(left <= ARRIVE_M, "the giant arrives at the shrine (%.1f m left after %d moves)" % [left, moves])
	assert_true(chunks.size() >= 3, "across chunk seams (%d chunks)" % chunks.size())
	assert_true(targets >= 3, "the route is walked in several legs (%d)" % targets)
	assert_eq(too_far, PackedStringArray(), "no leg aims past LEG_MAX_M along the route")
	assert_eq(off_ready, PackedStringArray(), "no leg aims into a chunk that is not ready")
	assert_eq(r.short_legs, 0, "every leg's path ends within reach of its target")
	assert_true(walked < planned_m * 1.3, "the legs keep to the route (%.0f m walked, %.0f m planned)" % [walked, planned_m])
	w.queue_free()
	await get_tree().process_frame


func test_a_leg_waits_for_the_next_chunk_and_is_asked_again_once_it_is_ready() -> void:
	var w := _world()
	var idx := WorldIndex.for_level(LEVEL)
	var start := idx.position_of(START)
	var goal := idx.position_of(GOAL)
	w.streamer.load_ring = 0
	await _load_ring(w, start)
	var pos := _place(w, start)
	var own := w.streamer.chunk_at(pos)
	var r := _route(w)
	r.plan(pos, goal)
	r.steer(pos, 0, w)
	var next := ""
	for i in range(r.step, r.points.size()):
		var c := w.streamer.chunk_at(r.points[i])
		if c != own:
			next = c
			break
	assert_true(next != "", "the route leaves the giant's chunk (%s)" % own)
	assert_eq(r.waiting_chunk, next, "the leg waits for the next chunk")
	assert_eq(w.streamer.chunk_at(r.leg_target), own, "and aims at the last route point before it")
	var first_target := r.leg_target
	var queries := r.leg_queries
	var along_before := _along(r, pos, _point_index(r, first_target))
	w.streamer.load_ring = 1
	await _load_ring(w, pos)
	assert_true(w.streamer.is_ready(next), "the next chunk is ready")
	r.steer(pos, 1, w)
	assert_true(r.leg_queries > queries, "a new leg is asked at once (not at the next replan)")
	assert_true(w.streamer.chunk_at(r.leg_target) != own, "beyond the giant's chunk (%s)" % w.streamer.chunk_at(r.leg_target))
	assert_true(_along(r, pos, _point_index(r, r.leg_target)) > along_before, "farther along the route")
	assert_true(r.waiting_chunk != next, "no longer waiting for it")
	w.queue_free()
	await get_tree().process_frame
