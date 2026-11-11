extends IntegrationSuite
## M7 polish (the M7 gate review): the world walk on the real world needs no --route. Before, the
## real world had no Markers/Route and "--mode=world --new-game --scenario=world_walk" ended at once,
## "the route was not finished (waypoint 1 of 0, lap 1 of 1)"; tools/web/stream_check.mjs --world
## failed the same way. The world builder now writes tools/data/world/world.json's walk_route as
## Markers/Route, and a walk with no route is a usage error.
##   * the real world (deterministic streaming, AI off) walked with the stick by a stage-3 giant along
##     its default route: finished, the four region changes and three seams, no check failure, no
##     stuck teleport (every leg clears the trunks), 200 m of loaded ground ahead;
##   * a streamed level without a route (the test world with its Markers/Route taken out): the walk
##     reports the usage error alone and ends at once.

const WORLD_SCENE := "res://scenes/world/world.tscn"
const TEST_WORLD := "res://scenes/test/test_world.tscn"
const MAX_TICKS := 60 * 120


## A world scene added to the test tree with deterministic streaming, AI off and the ring around the
## giant loaded.
func _world(scene: String) -> WorldRoot:
	var w := (load(scene) as PackedScene).instantiate() as WorldRoot
	world.add_child(w)
	w.streamer.deterministic = true
	TestSpawn.disable_all_ai(w)
	var p := w.player()
	var guard := 0
	while not w.streamer.ring_ready(p.global_position) and guard < 600:
		w.streamer.load_ring_slice(p.global_position)
		guard += 1
	return w


## Runs a WorldWalk with `opts` on `w` until it is done; its report (with "done" and "ticks").
func _walk(w: WorldRoot, opts: Dictionary) -> Dictionary:
	var walk := WorldWalk.new()
	walk.name = "WorldWalk"
	add_child(walk)
	walk.start(w.player(), w, null, opts)
	var ticks := 0
	while not walk.done and ticks < MAX_TICKS:
		await step_ticks(1)
		ticks += 1
	var r := walk.result()
	r["done"] = walk.done
	r["ticks"] = ticks
	walk.queue_free()
	return r


func test_the_real_world_walks_its_default_route() -> void:
	var w := _world(WORLD_SCENE)
	assert_eq(WorldWalk.level_route(w).size(), 6, "the real world has its route (Markers/Route)")
	var r := await _walk(w, {"stage": 3})
	print("    test_world_walk_real: %s" % JSON.stringify({"metres": r.metres, "seconds": r.seconds,
		"min_margin_m": r.min_margin_m, "loads": r.loads, "regions": (r.region_changes as Array).size(),
		"seams": r.seam_crossings, "stuck": r.stuck_teleports, "work_ms_p99": r.work_ms_p99}))
	assert_true(bool(r.done) and bool(r.finished), "the walk finished (%d ticks)" % r.ticks)
	assert_eq(str(r.usage_error), "", "no usage error")
	assert_eq((r.check_failures as PackedStringArray).size(), 0, "no check failed: %s" % [r.check_failures])
	assert_eq(int(r.route_points), 6, "the six points of the layout's walk_route")
	# (the first change names the start's region when the walk sets off before WorldRoot had one)
	var crossed: Array = (r.region_changes as Array).filter(func(c: Dictionary) -> bool: return str(c.previous) != "") \
		.map(func(c: Dictionary) -> String: return str(c.region))
	assert_eq(crossed, ["region.drowned_steps", "region.greywood", "region.drowned_steps", "region.crownmarch"],
		"across four region borders")
	assert_true(int(r.seam_crossings) >= 3 and int(r.loads) >= 3, "across seams, chunks streaming in (%d seams, %d loads)" % [
		r.seam_crossings, r.loads])
	assert_eq(int(r.stuck_teleports), 0, "never stuck: every leg clears the trunks")
	assert_true(float(r.min_margin_m) >= WorldWalk.MARGIN_REQUIRED_M, "200 m of loaded ground ahead (%.1f m)" % r.min_margin_m)
	assert_true(float(r.metres) > 350.0 and float(r.metres) < 450.0, "about 400 m (%.0f m in %.1f s)" % [r.metres, r.seconds])
	w.queue_free()
	await get_tree().process_frame


func test_a_level_without_a_route_is_a_usage_error() -> void:
	var w := _world(TEST_WORLD)
	var markers := w.get_node("Markers/Route")
	markers.get_parent().remove_child(markers)
	markers.free()
	var r := await _walk(w, {})
	assert_true(bool(r.done), "the walk ends at once (%d ticks)" % r.ticks)
	assert_true(int(r.ticks) <= 2, "without walking")
	assert_eq(str(r.usage_error), WorldWalk.NO_ROUTE, "a usage error")
	assert_eq(Array(r.check_failures), [WorldWalk.NO_ROUTE], "and only it - not \"the route was not finished\"")
	assert_false(bool(r.finished), "nothing was walked")
	w.queue_free()
	await get_tree().process_frame
