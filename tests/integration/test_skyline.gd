extends IntegrationSuite
## P24a (plan M6-M9 §2.8, decision 12, risk 23): the skyline - its mask hides the coarse mesh over
## the chunks that are loaded and drawn (within the preset's terrain distance from the camera) and
## shows it everywhere else; the three global shader parameters it reads; lit beacons by flag; and,
## on the generated test world, the coarse terrain stays under the fine heights.

const SKYLINE := "res://assets/test_world/skyline.res"
const CHUNK_DIR := "res://assets/test_world/chunks/"


func _tiny_world_with_skyline(extra := {}) -> WorldRoot:
	TinyWorld.write(Vector2i(4, 4))
	TinyWorld.install_record(Vector2i(4, 4), extra)
	var root := TinyWorld.make_root(false)
	var sky := Skyline.new()
	sky.name = "Skyline"
	sky.beacon_positions = PackedVector3Array([Vector3(10.0, 20.0, -30.0)])
	sky.beacon_flags = PackedStringArray(["test.p24a.beacon"])
	root.add_child(sky)
	world.add_child(root)
	root.streamer.deterministic = true
	var at := Vector3(-40.0, 0.0, -40.0)
	while not root.streamer.ring_ready(at):
		root.streamer.load_ring_slice(at)
	return root


func test_the_mask_follows_the_drawn_chunks() -> void:
	var root := _tiny_world_with_skyline()
	var sky := root.skyline
	assert_true(sky != null and sky.material != null, "the skyline has its shader material")
	assert_eq(sky.grid, Vector2i(4, 4), "a mask cell per chunk")
	assert_true(root.update_mask(true), "the first mask")
	for id in ["c0_0", "c1_1", "c2_2", "c2_0"]:
		var c := ChunkData.coords_for(id)
		assert_eq(int(sky.mask[c.y * 4 + c.x]), Skyline.MASK_DRAWN, "%s is loaded and drawn" % id)
	assert_eq(int(sky.mask[3 * 4 + 3]), 0, "c3_3 is not loaded")
	assert_false(sky.visible_at(Vector3(-40.0, 0.0, -40.0)), "no skyline over a drawn chunk")
	assert_true(sky.visible_at(Vector3(100.0, 0.0, 100.0)), "the skyline where no chunk is drawn")
	assert_true(sky.visible_at(Vector3(5000.0, 0.0, 0.0)), "and beyond the grid")
	assert_false(root.update_mask(), "nothing changed, nothing to update")
	# Chunks loaded but beyond the terrain distance from the camera are not drawn: the skyline shows.
	var view := Vector3(-90.0, 30.0, -90.0)
	var mask := root.drawn_mask(view)
	assert_eq(int(mask[0]), 1, "c0_0 is near the camera")
	root.streamer.terrain_visibility_end_m = 60.0
	mask = root.drawn_mask(view)
	assert_eq(int(mask[0]), 1, "c0_0 within 60 m")
	assert_eq(int(mask[2 * 4 + 2]), 0, "c2_2 is loaded but 60 m is too short to draw it")
	sky.set_mask(mask)
	assert_true(sky.visible_at(Vector3(40.0, 0.0, 40.0)), "so the skyline shows over it")
	assert_false(sky.visible_at(Vector3(-100.0, 0.0, -100.0)), "and not over c0_0")


func test_the_shader_reads_three_global_parameters() -> void:
	Skyline.ensure_globals()
	var shader := load(Skyline.SHADER_PATH) as Shader
	assert_true(shader != null, "the skyline shader loads")
	var code := shader.code
	for p: String in ["world_loaded_mask", "world_grid_origin", "world_chunk_size"]:
		assert_true(code.contains("global uniform") and code.contains(p), "it reads the global %s" % p)
	assert_true(code.contains("discard"), "and discards over drawn chunks")
	var root := _tiny_world_with_skyline()
	assert_eq(root.skyline.grid_origin, Vector2(-128.0, -128.0), "the grid's origin")
	assert_near(root.skyline.chunk_size, 64.0, 1e-4, "and chunk size")
	assert_eq(root.skyline.mask.size(), 16, "one byte a chunk")


func test_beacons_light_by_flag() -> void:
	var root := _tiny_world_with_skyline()
	var sky := root.skyline
	assert_eq(sky.lit_beacons().size(), 0, "no beacon lit yet")
	assert_true(sky.beacons == null or not sky.beacons.visible, "no column shown")
	WorldState.set_flag("test.p24a.beacon", true)
	assert_eq(sky.lit_beacons().size(), 1, "the flag lights it")
	assert_true(sky.beacons != null and sky.beacons.visible, "its column shows")
	assert_eq(sky.beacons.multimesh.instance_count, 1, "one column")
	var mat := (sky.beacons.multimesh.mesh as CylinderMesh).material as StandardMaterial3D
	assert_true(mat.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED and mat.disable_fog, "unshaded and fog-free")
	assert_eq(sky.beacons.cast_shadow, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "no shadow")
	WorldState.set_flag("test.p24a.beacon", false)
	assert_false(sky.beacons.visible, "unlit again")


func test_the_test_worlds_skyline_stays_under_its_terrain() -> void:
	var mesh := load(SKYLINE) as ArrayMesh
	assert_true(mesh != null, "the test world has its skyline mesh")
	if mesh == null:
		return
	var verts: PackedVector3Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	assert_eq(verts.size(), 33 * 33, "a vertex every 32 m over 1,024 m")
	var origin := {}
	var heights := {}
	for z in 4:
		for x in 4:
			var d := load(CHUNK_DIR + "c%d_%d.res" % [x, z]) as ChunkData
			origin[Vector2i(x, z)] = d.origin
			heights[Vector2i(x, z)] = d.decode_heights()
	var worst := -INF
	var checked := 0
	for k in range(0, verts.size(), 5):
		var v := verts[k]
		var lo := INF
		for dz in range(-8, 9):
			for dx in range(-8, 9):
				var x := v.x + dx * 4.0
				var zz := v.z + dz * 4.0
				var c := Vector2i(int(floor((x + 512.0) / 256.0)), int(floor((zz + 512.0) / 256.0)))
				if not heights.has(c):
					continue
				var o: Vector3 = origin[c]
				var i := clampi(int(roundf((x - o.x) / 4.0)), 0, 64)
				var j := clampi(int(roundf((zz - o.z) / 4.0)), 0, 64)
				lo = minf(lo, (heights[c] as PackedFloat32Array)[(j + 1) * 67 + i + 1])
		if lo != INF:
			worst = maxf(worst, v.y - lo)
			checked += 1
	assert_true(checked > 100, "checked %d vertices" % checked)
	assert_true(worst <= -SkylineWriter.DROP_M + 0.01, "every coarse vertex sits 2 m under the fine heights within 32 m (worst %.3f)" % worst)
