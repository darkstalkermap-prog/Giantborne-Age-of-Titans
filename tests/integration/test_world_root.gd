extends IntegrationSuite
## P24a (plan M6-M9 §2.7, §2.8, §3.6): WorldRoot - the lookups on loaded ground (height_at,
## surface_at, water_at; NaN or "" where nothing is loaded), region_at from the world index (any
## distance), region_changed with its 15 m hysteresis, the depth fog from the world block, the far
## plane and the terrain distance following the level's render preset, and main.gd's loading
## screen holding the tree paused until the starting ring and the samples are ready.

const MainScript := preload("res://scripts/main.gd")
const TINY_SCENE := "user://p24a_tiny_world_root.tscn"

var _saved_quality: Variant
var _regions: Array = []


func before_each() -> void:
	await super()
	_saved_quality = Settings.values.get("graphics_quality", Settings.GRAPHICS_DEFAULT)
	_regions.clear()
	Events.region_changed.connect(_on_region)


func after_each() -> void:
	for c: Dictionary in Events.region_changed.get_connections():
		if (c.callable as Callable).get_object() == self:
			Events.region_changed.disconnect(c.callable)
	Settings.values["graphics_quality"] = _saved_quality
	await super()


func _on_region(tick: int, region: String, previous: String) -> void:
	_regions.append([tick, region, previous])


## A tiny WorldRoot in the test world, its ring loaded around `at` (deterministic slices).
func _tiny_root(at: Vector3, giant := false) -> WorldRoot:
	TinyWorld.write(Vector2i(4, 4))
	TinyWorld.install_record(Vector2i(4, 4))
	var root := TinyWorld.make_root(giant, at)
	world.add_child(root)
	root.streamer.deterministic = true
	var guard := 0
	while not root.streamer.ring_ready(at) and guard < 60:
		root.streamer.load_ring_slice(at)
		guard += 1
	return root


func test_lookups_on_loaded_ground() -> void:
	var root := _tiny_root(Vector3(-40.0, 0.0, -40.0))
	assert_true(root.streamer.ring_ready(Vector3(-40.0, 0.0, -40.0)), "the ring loaded")
	var worst := 0.0
	for p: Vector2 in [Vector2(-40.0, -40.0), Vector2(-12.5, -70.25), Vector2(1.0, -1.0), Vector2(-90.0, -5.0)]:
		var h := root.height_at(Vector3(p.x, 99.0, p.y))
		assert_false(is_nan(h), "a height at %s" % p)
		worst = maxf(worst, absf(h - TinyWorld.height(p.x, p.y)))
	assert_true(worst < 0.05, "the ground is the world's height within its 4 m facets (worst %.3f)" % worst)
	assert_true(is_nan(root.height_at(Vector3(100.0, 0.0, 100.0))), "NaN over a chunk that is not loaded")
	assert_true(is_nan(root.height_at(Vector3(1000.0, 0.0, 0.0))), "NaN outside the world")
	assert_eq(root.surface_at(Vector3(-40.0, 0.0, -40.0)), "soft", "a soft cell")
	assert_eq(root.surface_at(Vector3(20.0, 0.0, -40.0)), "hard", "a hard one")
	assert_eq(root.surface_at(Vector3(100.0, 0.0, 100.0)), "", "nothing where no chunk is loaded")
	assert_near(root.water_at(Vector3(-110.0, 0.0, -110.0)), 50.0, 1e-4, "the water of c0_0")
	assert_true(is_nan(root.water_at(Vector3(-40.0, 0.0, -40.0))), "no water elsewhere")
	assert_eq(root.chunk_at(Vector3(-40.0, 0.0, -40.0)), "c1_1", "chunk_at")
	# Without an index the chunks' region cells answer (the level's region list).
	root.streamer.region_ids = PackedStringArray(["region.tiny_west", "region.tiny_east"])
	assert_eq(root.region_at(Vector3(-40.0, 0.0, -40.0)), "region.tiny_west", "the chunk's region cell")
	assert_eq(root.region_at(Vector3(20.0, 0.0, -40.0)), "region.tiny_east", "its east half")
	assert_eq(root.region_at(Vector3(100.0, 0.0, 100.0)), "", "no region where nothing is loaded")


func test_regions_from_the_index_and_their_hysteresis() -> void:
	var root := WorldRoot.new()
	root.name = "RegionWorld"
	root.level_id = "level.test_world"
	world.add_child(root)
	assert_eq(root.region_at(Vector3(-300.0, 0.0, 400.0)), "region.test_west", "the index's grid answers far away")
	assert_eq(root.region_at(Vector3(300.0, 0.0, -400.0)), "region.test_east", "east of the origin")
	assert_eq(root.region_at(Vector3(900.0, 0.0, 0.0)), "", "outside the grid")
	root.update_region(Vector3(-40.0, 0.0, 10.0))
	assert_eq(_regions.size(), 1, "the first region is announced at once")
	assert_eq([_regions[0][1], _regions[0][2]], ["region.test_west", ""], "with no previous region")
	var switched_at := INF
	for k in 81:
		var x := -40.0 + k
		root.update_region(Vector3(x, 0.0, 10.0))
		if _regions.size() == 2 and switched_at == INF:
			switched_at = x
	assert_eq(_regions.size(), 2, "one change crossing x = 0")
	assert_near(switched_at, WorldRoot.REGION_HYSTERESIS_M, 0.01, "only once 15 m inside the new region")
	assert_eq([_regions[1][1], _regions[1][2]], ["region.test_east", "region.test_west"], "east, from west")
	# Back and forth across the border within 15 m: nothing.
	for x: float in [10.0, -5.0, 14.0, -14.0, 3.0]:
		root.update_region(Vector3(x, 0.0, 10.0))
	assert_eq(_regions.size(), 2, "dithering at the border changes nothing")
	root.update_region(Vector3(-15.5, 0.0, 10.0))
	assert_eq(_regions.size(), 3, "15 m into the west it changes back")
	assert_eq(root.region_log.size(), 3, "region_log keeps them")


func test_fog_far_plane_terrain_distance_and_the_starting_ring() -> void:
	Settings.set_value("graphics_quality", "low", false)
	TinyWorld.write(Vector2i(4, 4))
	TinyWorld.install_record(Vector2i(4, 4), {"render": {"medium": {"camera_far_m": 2000, "terrain_visibility_end_m": 500}}})
	var root := TinyWorld.make_root(true, Vector3(30.0, 5.0, 30.0))
	var we := WorldEnvironment.new()
	we.name = "Environment"
	we.environment = Environment.new()
	root.add_child(we)
	world.add_child(root)
	root.streamer.deterministic = true
	root.streamer.process_mode = Node.PROCESS_MODE_DISABLED
	var p := root.player()
	assert_true(p != null, "the giant is in the world")
	assert_near(p.camera_rig.camera.far, 2400.0, 0.01, "the far plane is the preset's camera_far_m (2,400 m)")
	assert_near(float(root.applied_graphics.get("camera_far_m", 0.0)), 2400.0, 0.01, "reported")
	var env := we.environment
	assert_true(env.fog_enabled and env.fog_mode == Environment.FOG_MODE_DEPTH, "depth fog")
	assert_near(env.fog_depth_begin, 400.0, 0.01, "from 400 m")
	assert_near(env.fog_depth_end, 1800.0, 0.01, "to 1,800 m")
	assert_near(env.fog_density, 0.85, 0.001, "at most 85 %")
	# The starting ring: loading_progress() loads it a slice at a time until is_ready().
	assert_false(root.is_ready(), "nothing loaded yet")
	var last := -1.0
	var slices := 0
	while not root.is_ready() and slices < 30:
		var prog := root.loading_progress()
		assert_true(prog >= last - 1e-6, "progress grows (%.2f)" % prog)
		last = prog
		slices += 1
	assert_true(root.is_ready() and slices >= 2, "the ring around the giant is ready (%d slices)" % slices)
	assert_eq(root.streamer.ring_ids(root.ring_center()).size(), 9, "around the giant")
	var chunk := root.streamer.chunk_node("c2_2")
	assert_near(chunk.terrain.visibility_range_end, 700.0, 0.01, "chunks get the preset's terrain distance")
	Settings.set_value("graphics_quality", "medium", false)
	assert_near(p.camera_rig.camera.far, 2000.0, 0.01, "a quality change moves the far plane")
	assert_near(chunk.terrain.visibility_range_end, 500.0, 0.01, "and the loaded terrain's distance")
	assert_near(root.streamer.terrain_visibility_end_m, 500.0, 0.01, "and the streamer's, for chunks to come")


func test_a_level_without_camera_far_m_keeps_800_m() -> void:
	var lv := LevelRoot.new()
	lv.name = "ValleyLike"
	lv.level_id = "level.valley"
	var body := Node3D.new()
	body.name = "Giant"
	lv.add_child(body)
	var rig := CameraRig.new()
	var cam := Camera3D.new()
	cam.name = "Camera3D"
	rig.add_child(cam)
	rig.player = body
	world.add_child(lv)
	assert_near(lv.camera_far_m(), LevelRoot.DEFAULT_CAMERA_FAR_M, 0.01, "camera_far_m() falls back to 800 m")
	assert_near(rig.level_far_plane_m(), 800.0, 0.01, "the Valley keeps today's 800 m")
	var tw := LevelRoot.new()
	tw.name = "TestWorldLike"
	tw.level_id = "level.test_world"
	world.add_child(tw)
	body.reparent(tw)
	assert_near(rig.level_far_plane_m(), 2400.0, 0.01, "the test world's preset gives 2,400 m")
	rig.free()


func test_the_loading_screen_holds_until_the_ring_is_ready() -> void:
	TinyWorld.write(Vector2i(4, 4))
	TinyWorld.install_record(Vector2i(4, 4))
	var root := TinyWorld.make_root(true, Vector3(30.0, 5.0, 30.0))
	var packed := PackedScene.new()
	for c in root.get_children():
		c.owner = root
	packed.pack(root)
	root.free()
	assert_eq(ResourceSaver.save(packed, TINY_SCENE), OK, "the tiny world scene is saved")
	GameSession.level_override = TINY_SCENE
	var tick0 := Sim.tick
	var main := MainScript.new()
	add_child(main)
	await get_tree().process_frame
	var held := 0
	var level: WorldRoot = null
	while held < 120:
		level = main.level as WorldRoot
		if level != null and level.is_ready() and Audio.is_ready():
			break
		assert_true(get_tree().paused, "the tree stays paused while the ring loads (frame %d)" % held)
		assert_eq(Sim.tick, tick0, "no simulation tick before the ring is ready")
		held += 1
		await get_tree().process_frame
	assert_true(level != null and level.is_ready(), "the starting ring is ready")
	assert_true(held >= 1, "the screen held for the ring (%d frames)" % held)
	await get_tree().process_frame
	await get_tree().process_frame
	assert_false(get_tree().paused, "then the game runs")
	assert_true(Sim.tick > tick0, "and the simulation ticks")
	var p := level.player()
	var ground := level.height_at(p.global_position)
	assert_true(not is_nan(ground) and p.global_position.y > ground - 0.5, "the giant stands on loaded ground")
	main.queue_free()
	await get_tree().process_frame
	GameSession.level_override = ""
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TINY_SCENE))
