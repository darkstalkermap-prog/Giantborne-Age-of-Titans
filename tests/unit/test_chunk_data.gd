extends TestSuite
## P24a (plan M6-M9 §2.7, §3.6): ChunkData - chunk ids and positions, the 16-bit heights (a round
## trip within 4 mm, the apron, the two height lookups), the surface and region cells and the water.


## A chunk of `m` inner samples at 4 m spacing whose every sample (apron included) is fn(x, z) in
## chunk-local metres.
func _chunk(m: int, fn: Callable) -> ChunkData:
	var d := ChunkData.new()
	d.chunk_id = "c1_2"
	d.coords = Vector2i(1, 2)
	d.origin = Vector3(256.0, 0.0, 512.0)
	d.spacing_m = 4.0
	d.size_m = (m - 1) * 4.0
	d.samples = m + 2
	d.height_min = HeightField.QUANT_MIN_M
	d.height_step = HeightField.QUANT_STEP_M
	var values := PackedFloat32Array()
	values.resize(d.samples * d.samples)
	for j in d.samples:
		for i in d.samples:
			values[j * d.samples + i] = float(fn.call((i - 1) * 4.0, (j - 1) * 4.0))
	d.heights = HeightField.encode(values)
	return d


func test_chunk_ids_and_coordinates() -> void:
	assert_eq(ChunkData.id_for(Vector2i(2, 7)), "c2_7", "c<x>_<z>")
	assert_eq(ChunkData.coords_for("c2_7"), Vector2i(2, 7), "and back")
	assert_eq(ChunkData.coords_for("c10_0"), Vector2i(10, 0), "two digits")
	for bad: String in ["", "c2", "x2_7", "c2_x", "c_7", "chunk"]:
		assert_eq(ChunkData.coords_for(bad), Vector2i(-1, -1), "'%s' is no chunk id" % bad)


func test_chunk_id_from_a_position() -> void:
	var s := ChunkStreamer.new()
	s.configure({"chunk_size_m": 256.0, "grid": [8, 8], "origin_m": [-1024.0, 0.0, -1024.0], "chunk_dir": "res://x"}, null)
	assert_eq(s.chunk_at(Vector3(-1024.0, 0.0, -1024.0)), "c0_0", "the min corner is chunk 0, 0")
	assert_eq(s.chunk_at(Vector3(-768.1, 50.0, -1023.0)), "c0_0", "up to its far edge")
	assert_eq(s.chunk_at(Vector3(-768.0, 0.0, -1024.0)), "c1_0", "x runs west to east")
	assert_eq(s.chunk_at(Vector3(-300.0, 0.0, 920.0)), "c2_7", "the Kingsgate shelf is in c2_7 (plan §5.2)")
	assert_eq(s.chunk_at(Vector3(1023.9, 0.0, 1023.9)), "c7_7", "the last chunk")
	assert_eq(s.chunk_at(Vector3(1024.0, 0.0, 0.0)), "", "beyond the grid")
	assert_eq(s.chunk_at(Vector3(0.0, 0.0, -1025.0)), "", "north of it")
	assert_eq(s.chunk_center("c2_7"), Vector3(-384.0, 0.0, 896.0), "a chunk's centre")
	assert_eq(ChunkStreamer.chebyshev(Vector2i(1, 1), Vector2i(3, 2)), 2, "Chebyshev distance")
	s.free()


func test_quantisation_round_trip_within_4_mm() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 2414
	var values := PackedFloat32Array()
	for k in 400:
		values.append(rng.randf_range(-31.9, 229.9))
	var bytes := HeightField.encode(values)
	assert_eq(bytes.size(), values.size() * 2, "two bytes a height")
	var worst := 0.0
	for k in values.size():
		var back := HeightField.dequantise(bytes.decode_u16(2 * k))
		worst = maxf(worst, absf(back - values[k]))
	assert_true(worst <= 0.004, "every height comes back within 4 mm (worst %.4f m)" % worst)
	assert_true(worst <= HeightField.QUANT_STEP_M * 0.5 + 1e-5, "half a step at most")
	assert_eq(HeightField.quantise(-100.0), 0, "below the range clamps to 0")
	assert_eq(HeightField.quantise(400.0), HeightField.QUANT_MAX, "above it to the top")
	assert_near(HeightField.dequantise(HeightField.QUANT_MAX), 230.14, 0.001, "the range ends at about +230 m (plan §5.3)")


func test_the_grid_and_its_apron() -> void:
	var d := _chunk(5, func(x: float, z: float) -> float: return 10.0 + 0.5 * x - 0.25 * z)
	assert_eq(d.inner(), 5, "five inner samples")
	assert_eq(d.index_of(-1, -1), 0, "the apron's corner is the first value")
	assert_eq(d.index_of(0, 0), d.samples + 1, "inner sample (0, 0) follows one apron row and column")
	assert_near(d.sample(-1, 0), 10.0 - 2.0, 0.004, "the west apron (x -4)")
	assert_near(d.sample(5, 2), 10.0 + 10.0 - 2.0, 0.004, "the east apron (x 20)")
	var f := d.decode_heights()
	assert_eq(f.size(), d.samples * d.samples, "decode_heights gives every sample")
	assert_near(f[d.index_of(3, 4)], d.sample(3, 4), 1e-5, "the decoded copy matches sample()")
	var hr := d.height_range()
	assert_near(hr.x, 10.0 - 4.0, 0.004, "the lowest inner sample (z 16)")
	assert_near(hr.y, 10.0 + 8.0, 0.004, "the highest (x 16)")


func test_heights_between_the_samples() -> void:
	var plane := _chunk(5, func(x: float, z: float) -> float: return 3.0 + 0.5 * x + 0.25 * z)
	for p: Vector2 in [Vector2(0, 0), Vector2(2.5, 7.25), Vector2(15.9, 0.1), Vector2(16, 16)]:
		var want := 3.0 + 0.5 * p.x + 0.25 * p.y
		assert_near(plane.height_at_local(p.x, p.y), want, 0.005, "bilinear on a plane at %s" % p)
		assert_near(plane.ground_at_local(p.x, p.y), want, 0.005, "the triangles on a plane at %s" % p)
	assert_near(plane.height_at_local(-2.0, 4.0), 3.0 - 1.0 + 1.0, 0.005, "the apron answers one sample beyond")
	assert_true(is_nan(plane.height_at_local(-6.0, 4.0)), "NaN beyond the apron")
	assert_true(is_nan(plane.ground_at_local(-1.0, 4.0)), "the ground only inside the chunk")
	# A saddle: the triangles (split along (i, j) - (i + 1, j + 1)) differ from the bilinear surface.
	var saddle := _chunk(3, func(x: float, z: float) -> float: return 4.0 if (x == 4.0 and z == 0.0) else 0.0)
	assert_near(saddle.ground_at_local(3.0, 1.0), 4.0 * 0.75 - 4.0 * 0.25, 0.005,
		"triangle (i, j), (i + 1, j), (i + 1, j + 1): h00 + (h10 - h00) tx + (h11 - h10) tz")
	assert_near(saddle.ground_at_local(1.0, 3.0), 0.0, 0.005, "the other triangle does not see that corner")
	assert_near(saddle.height_at_local(3.0, 1.0), 4.0 * 0.75 * 0.75, 0.005, "bilinear blends all four")


func test_cells_and_water() -> void:
	var d := ChunkData.new()
	d.size_m = 256.0
	d.surface_cells.resize(ChunkData.SURFACE_CELLS * ChunkData.SURFACE_CELLS)
	d.surface_cells[0] = ChunkData.SURFACE_HARD
	d.surface_cells[ChunkData.SURFACE_CELLS * 15 + 15] = ChunkData.SURFACE_WET
	d.region_cells.resize(ChunkData.REGION_CELLS * ChunkData.REGION_CELLS)
	d.region_cells[ChunkData.REGION_CELLS + 2] = 3
	assert_eq(d.surface_name_at_local(1.0, 15.9), "hard", "the 16 m cell (0, 0)")
	assert_eq(d.surface_name_at_local(16.1, 1.0), "soft", "its neighbour")
	assert_eq(d.surface_name_at_local(255.0, 250.0), "wet", "the last cell")
	assert_eq(d.surface_name_at_local(-1.0, 0.0), "", "nothing outside the chunk")
	assert_eq(d.region_index_at_local(130.0, 70.0), 3, "the 64 m cell (2, 1)")
	assert_eq(d.region_index_at_local(10.0, 10.0), 0, "no region")
	ChunkWriter.add_water(d.water, Rect2(10.0, 20.0, 30.0, 40.0), 6.5)
	ChunkWriter.add_water(d.water, Rect2(30.0, 50.0, 10.0, 10.0), 7.0)
	assert_near(d.water_at_local(15.0, 25.0), 6.5, 1e-5, "inside the first rectangle")
	assert_near(d.water_at_local(35.0, 55.0), 7.0, 1e-5, "the higher surface where two overlap")
	assert_true(is_nan(d.water_at_local(5.0, 25.0)), "NaN where there is no water")
	ChunkWriter.add_solid(d.solids, true, Vector3(1, 2, 3), Vector3(1, 4, 0))
	d.scenery["res://x.res"] = ChunkWriter.xform_buffer([Transform3D(), Transform3D()])
	assert_eq(d.counts(), {"solids": 1, "scenery": 2, "scenery_keys": 1, "props_scenes": 0, "water": 2}, "counts()")


func test_scenery_buffers_round_trip() -> void:
	var xforms: Array = [Transform3D(Basis(Vector3.UP, 0.7).scaled(Vector3(2, 3, 4)), Vector3(1, 2, 3)),
		Transform3D(Basis.from_scale(Vector3(0.5, 9, 0.5)), Vector3(-7, 0.25, 255))]
	var buf := ChunkWriter.xform_buffer(xforms)
	assert_eq(buf.size(), 24, "12 floats an instance")
	var back := ChunkWriter.buffer_xforms(buf)
	for i in xforms.size():
		assert_true(back[i].is_equal_approx(xforms[i]), "instance %d comes back" % i)
	# The layout is MultiMesh.buffer's (TRANSFORM_3D): basis row x then origin.x, and so on.
	assert_eq([buf[0], buf[1], buf[2], buf[3]], [xforms[0].basis.x.x, xforms[0].basis.y.x, xforms[0].basis.z.x, 1.0],
		"the first row: basis x components, then origin x")
