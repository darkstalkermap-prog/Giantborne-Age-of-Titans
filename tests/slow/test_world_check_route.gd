extends IntegrationSuite
## P39f (plan M6-M9 §6.3, §6.6): the web world check's walk (tools/web/world_check.json, read by
## tools/web/world_check.mjs) on the real world, as the check makes it after its fast travel: the giant
## at the King's Road waystone's respawn point (where the travel puts him), grown to the fixture's
## stage, walked with the stick (deterministic streaming, AI off) from there along the route - WorldWalk
## told the travel has arrived, so its first leg is the arrival's. The walk finishes with no check failure
## and no stuck teleport, lasts the check's least walk, crosses region borders and keeps 200 m of loaded
## ground ahead. Before P39f the web checks walked only from New Game's start and nothing walked from a
## fast travel's arrival.

const CONFIG := "res://tools/web/world_check.json"
const WORLD_SCENE := "res://scenes/world/world.tscn"
const MAX_TICKS := 60 * 150


func after_each() -> void:
	WorldWalk.reset_run()
	await super()


func test_the_check_walks_from_the_waystone_across_borders() -> void:
	var cfg: Dictionary = JsonIO.read_file(CONFIG).data
	var to := str(cfg.travel_to)
	var doc: Dictionary = JsonIO.read_file("res://" + str(cfg.fixture)).data
	var stage := int((doc.character as Dictionary).growth_stage)
	var idx := WorldIndex.for_level("level.world")
	var place := idx.spawn_transform(to)
	assert_true(place.origin.is_finite(), "the index knows %s" % to)
	var w := (load(WORLD_SCENE) as PackedScene).instantiate() as WorldRoot
	world.add_child(w)
	w.streamer.deterministic = true
	TestSpawn.disable_all_ai(w)
	var p := w.player()
	var guard := 0
	while not w.streamer.ring_ready(place.origin) and guard < 600:
		w.streamer.load_ring_slice(place.origin)
		guard += 1
	# where the travel puts the giant: the waystone's node (loaded with its chunk), else its index entry
	var marker := GameSession.find_checkpoint(to)
	var t := marker.spawn_transform() if marker != null else place
	var y := w.height_at(t.origin)
	GameSession.place_player(p, Transform3D(t.basis, Vector3(t.origin.x, (y if not is_nan(y) else t.origin.y) + 0.3, t.origin.z)))
	var route := PackedVector3Array()
	for q: Array in cfg.route:
		route.append(Vector3(float(q[0]), 0.0, float(q[1])))
	WorldWalk.travel_run = {"to": to}   # the travel has arrived: the walk sets off from the giant
	var walk := WorldWalk.new()
	walk.name = "WorldWalk"
	add_child(walk)
	walk.start(p, w, null, {"route": route, "speed": 0.0, "stage": stage, "travel": to})
	var ticks := 0
	while not walk.done and ticks < MAX_TICKS:
		await step_ticks(1)
		ticks += 1
	var r := walk.result()
	print("    test_world_check_route: %s" % JSON.stringify({"metres": r.metres, "seconds": r.seconds, "stage": r.stage,
		"min_margin_m": r.min_margin_m, "loads": r.loads, "regions": (r.region_changes as Array).map(func(c: Dictionary) -> String: return c.region),
		"seams": r.seam_crossings, "stuck": r.stuck_teleports, "work_ms_max": r.work_ms_max, "over_budget": r.work_over_budget}))
	assert_true(walk.done and bool(r.finished), "the walk finished (%d ticks)" % ticks)
	assert_eq(int(r.stage), stage, "a stage-%d giant walked it (the fixture's)" % stage)
	assert_eq((r.check_failures as PackedStringArray).size(), 0, "no check failed: %s" % [r.check_failures])
	assert_eq(int(r.stuck_teleports), 0, "never stuck (every leg is clear for a stage-%d giant)" % stage)
	assert_true(float(r.seconds) >= float(cfg.walk_min_s), "it lasts the check's least walk (%.1f s of %s)" % [r.seconds, cfg.walk_min_s])
	assert_true((r.region_changes as Array).size() >= int(cfg.min_borders), "it crosses region borders (%s)" % [r.region_changes])
	assert_true(float(r.min_margin_m) >= WorldWalk.MARGIN_REQUIRED_M, "200 m of loaded ground ahead (%.1f m)" % r.min_margin_m)
	assert_true(float((r.travel as Dictionary).get("arrival_m", 99.0)) < 1.0, "from the waystone's respawn point")
	walk.queue_free()
	w.queue_free()
	await get_tree().process_frame
