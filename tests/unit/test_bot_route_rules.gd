extends TestSuite
## P38 (plan M6-M9 §6.1 "Routing"): the world bot's route planner (BotRoute) on road graphs built in
## code - no level, no navigation (the real world's routes and legs: tests/slow/test_bot_route.gd):
##   * plan(): road nodes then the goal, by stage (a min_stage edge closed below it, a max_stage edge
##     above it); a direct edge marks its steps direct; the first node is dropped when the giant is
##     already past it, the last when the goal lies before it; a near goal takes no road unless the
##     road there has a direct edge; no road joining far ends: false, the goal alone; the road starts
##     at the nearest node the giant's stage may leave (not a stage-closed spur's end);
##   * steer(): a direct step is steered at straight; passed points are left behind;
##   * fast_travel_point(): a far goal (over FAST_TRAVEL_MIN_M) with a visited checkpoint within
##     FAST_TRAVEL_NEAR_M of it, open to fast travel, whose flags hold and whose max_stage admits the
##     giant, nearer the goal than the giant: the nearest such to the goal; else "".


## A straight road along x at z = 0 from x = 0 to x = 1200 (nodes every 100 m), a branch to (600, 400)
## that only stage 6 may climb, and a slot (direct, stage 4 at most) from (1200, 0) to (1200, -60).
func _index() -> WorldIndex:
	var idx := WorldIndex.new()
	for i in 12:
		idx.add_road(Vector3(i * 100.0, 0, 0), Vector3((i + 1) * 100.0, 0, 0), 8.0)
	idx.add_road(Vector3(600, 0, 0), Vector3(600, 0, 200), 8.0, 6)
	idx.add_road(Vector3(600, 0, 200), Vector3(600, 0, 400), 8.0, 6)
	idx.add_road(Vector3(1200, 0, 0), Vector3(1200, 0, -30), 4.0, 0, 4, true)
	idx.add_road(Vector3(1200, 0, -30), Vector3(1200, 0, -60), 4.0, 0, 4, true)
	return idx


func _route(idx: WorldIndex, stage: int) -> BotRoute:
	var r := BotRoute.new(idx, null)
	r.stage = stage
	return r


func test_a_far_goal_follows_the_road_nodes_then_the_goal() -> void:
	var r := _route(_index(), 4)
	assert_true(r.plan(Vector3(-20, 0, 5), Vector3(1100, 0, 10)), "a road joins the ends")
	assert_eq(r.points[0], Vector3(0, 0, 0), "from the node nearest the giant")
	assert_eq(r.points[r.points.size() - 1], Vector3(1100, 0, 10), "to the goal")
	assert_eq(r.points.size(), 13, "the twelve nodes up to x = 1100, then the goal")
	assert_false(r.direct.has(1), "no direct step on an open road")
	assert_near(r.remaining_m(Vector3(-20, 0, 5)), 1130.6, 1.0, "the route's length (to the first node, 1100 m, 10 m off)")


func test_the_first_node_behind_the_giant_and_the_last_beyond_the_goal_are_dropped() -> void:
	var r := _route(_index(), 4)
	r.plan(Vector3(140, 0, 3), Vector3(960, 0, 3))
	assert_eq(r.points[0], Vector3(200, 0, 0), "the node at x = 100 is behind the giant")
	assert_eq(r.points[r.points.size() - 2], Vector3(900, 0, 0), "the node at x = 1000 lies beyond the goal")


func test_a_min_stage_edge_is_closed_below_its_stage() -> void:
	var idx := _index()
	var from := Vector3(0, 0, 0)
	var to := Vector3(600, 0, 400)
	var rp6 := BotRoute.road_path(idx, from, to, 6)
	assert_eq((rp6.nodes as PackedInt32Array).size(), 9, "stage 6 climbs the branch (7 nodes along, 2 up)")
	for e: int in rp6.edges:
		assert_true(idx.edge_allowed(e, 6), "every edge of the route is open at stage 6")
	var rp5 := BotRoute.road_path(idx, from, to, 5)
	assert_eq((rp5.nodes as PackedInt32Array).size(), 0, "stage 5 has no road up the branch")
	var r := _route(idx, 5)
	assert_false(r.plan(from, to), "a far goal without a road: false")
	assert_eq(r.points, PackedVector3Array([to]), "the route is the goal alone")


func test_a_direct_edge_is_walked_straight_and_closed_above_its_stage() -> void:
	var idx := _index()
	var r := _route(idx, 4)
	r.plan(Vector3(1160, 0, 0), Vector3(1200, 0, -60))
	assert_eq(r.points, PackedVector3Array([Vector3(1200, 0, 0), Vector3(1200, 0, -30), Vector3(1200, 0, -60),
		Vector3(1200, 0, -60)]), "a near goal through the slot takes the road (the slot has no navmesh)")
	assert_eq(r.direct, PackedByteArray([0, 1, 1, 1]), "the slot's steps and the goal beyond it are direct")
	# steering: a direct step is steered at straight, without a navigation query
	r.step = 1
	assert_eq(r.steer(Vector3(1200, 0, -2), 0, null), Vector3(1200, 0, -30), "straight at the slot's next node")
	assert_true(r.leg_direct and r.leg_queries == 0, "a direct leg asks no path")
	assert_eq(r.steer(Vector3(1200, 0, -25), 0, null), Vector3(1200, 0, -60), "the node within reach is passed")
	var r5 := _route(idx, 5)
	r5.plan(Vector3(1160, 0, 0), Vector3(1200, 0, -60))
	assert_false(r5.direct.has(1), "stage 5 may not use the slot: no direct step")
	assert_eq(r5.points, PackedVector3Array([Vector3(1200, 0, -60)]), "the near goal alone (the navmesh decides)")


func test_a_route_starts_at_the_nearest_node_the_stage_may_leave() -> void:
	var idx := _index()
	# beyond the slot's far end: at stage 5 its two nodes, (1200, -60) and (1200, -30), have no edge the
	# stage may use (the slot is stage 4 at most), so the road starts at (1200, 0)
	var from := Vector3(1200, 0, -64)
	var road_end := idx.nearest_road_node(Vector3(1200, 0, 0))
	var slot_end := idx.nearest_road_node(Vector3(1200, 0, -60))
	assert_eq(idx.nearest_road_node(from), slot_end, "the nearest node of all is the slot's end")
	assert_eq(BotRoute.nearest_leavable_node(idx, from, 5), road_end, "stage 5 leaves from the road's end")
	assert_eq(BotRoute.nearest_leavable_node(idx, from, 4), slot_end, "stage 4 may leave from the slot's end")
	var r := _route(idx, 5)
	assert_true(r.plan(from, Vector3(0, 0, 10)), "a road joins it to a far goal at stage 5")
	assert_eq(r.points[0], Vector3(1200, 0, 0), "from the nearest node the stage may leave")
	assert_eq(BotRoute.nearest_leavable_node(WorldIndex.new(), from, 5), -1, "no roads: no node")


func test_a_near_goal_on_an_open_road_takes_no_road() -> void:
	var r := _route(_index(), 4)
	assert_true(r.plan(Vector3(10, 0, 0), Vector3(200, 0, 20)), "a near goal is planned")
	assert_eq(r.points, PackedVector3Array([Vector3(200, 0, 20)]), "walked on the navmesh, no road")
	assert_true(r.goal_changed(Vector3(220, 0, 20)), "a goal 20 m away is another goal")
	assert_false(r.goal_changed(Vector3(203, 0, 20)), "3 m is the same goal")
	r.stage = 5
	assert_true(r.goal_changed(Vector3(200, 0, 20)), "a new stage plans again")


func test_fast_travel_takes_the_nearest_open_visited_checkpoint_to_a_far_goal() -> void:
	var idx := WorldIndex.new()
	idx.checkpoints = {
		"cp.near": {"position": Vector3(1000, 0, 50), "fast_travel": true, "max_stage": 10},
		"cp.nearer": {"position": Vector3(1000, 0, 20), "fast_travel": true, "max_stage": 10},
		"cp.small_only": {"position": Vector3(1000, 0, 10), "fast_travel": true, "max_stage": 4},
		"cp.flagged": {"position": Vector3(1000, 0, 5), "fast_travel": true, "max_stage": 10,
			"requires_flags": PackedStringArray(["gate.open"])},
		"cp.no_travel": {"position": Vector3(1000, 0, 1), "fast_travel": false, "max_stage": 10},
		"cp.far": {"position": Vector3(1300, 0, 0), "fast_travel": true, "max_stage": 10},
	}
	var all := func(_id: String) -> bool: return true
	var none_set := func(_f: String) -> bool: return false
	var from := Vector3(0, 0, 0)
	var goal := Vector3(1000, 0, 0)
	assert_eq(BotRoute.fast_travel_point(idx, from, goal, 5, all, none_set), "cp.nearer",
		"the nearest open checkpoint the stage may arrive at, flags held")
	assert_eq(BotRoute.fast_travel_point(idx, from, goal, 4, all, none_set), "cp.small_only", "a stage-4 giant may use it")
	assert_eq(BotRoute.fast_travel_point(idx, from, goal, 5, all, func(_f: String) -> bool: return true), "cp.flagged",
		"its flags hold now")
	assert_eq(BotRoute.fast_travel_point(idx, from, goal, 5, func(id: String) -> bool: return id == "cp.near", none_set),
		"cp.near", "only visited checkpoints")
	assert_eq(BotRoute.fast_travel_point(idx, from, goal, 5, func(id: String) -> bool: return id == "cp.far", none_set),
		"", "nothing within FAST_TRAVEL_NEAR_M of the goal")
	assert_eq(BotRoute.fast_travel_point(idx, Vector3(500, 0, 0), goal, 5, all, none_set), "",
		"a goal within FAST_TRAVEL_MIN_M is walked")
	assert_eq(BotRoute.fast_travel_point(idx, Vector3(1000, 0, -700), Vector3(1000, 0, 100), 5, all, none_set), "cp.near",
		"the nearest to the goal (100 m away: the 50 m one)")
