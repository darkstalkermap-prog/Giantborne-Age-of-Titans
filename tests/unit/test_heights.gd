extends TestSuite
## P24a (plan M6-M9 §3.6, §5.3): the offline terrain library - neighbouring chunks agree at their
## seam (heights and the normals the apron gives), the border relaxation keeps every walkable face
## within 8 m of a border at 35 degrees or less (and names the place when it cannot), props parts
## stay within 150 nodes, and the coarse skyline never rises above the fine heights.

const CELLS := 16
const ORIGIN := Vector3(-64.0, 0.0, -64.0)


## A 2 x 2 world of 64 m chunks (16 cells of 4 m) from fn(x, z), with the one-sample margin.
func _field(fn: Callable, chunks := Vector2i(2, 2)) -> HeightField:
	var f := HeightField.make(Vector2(ORIGIN.x - 4.0, ORIGIN.z - 4.0), 4.0, Vector2i(chunks.x * CELLS + 3, chunks.y * CELLS + 3))
	f.fill(fn)
	return f


static func _rolling(x: float, z: float) -> float:
	return 10.0 + 3.0 * sin(x * 0.07) * cos(z * 0.05) + 0.02 * x * z / 10.0


func test_neighbours_share_their_seam_and_its_normals() -> void:
	var f := _field(_rolling)
	var a := ChunkWriter.chunk_from_field(f, Vector2i(0, 0), 64.0, ORIGIN, Vector2i(1, 1))
	var b := ChunkWriter.chunk_from_field(f, Vector2i(1, 0), 64.0, ORIGIN, Vector2i(1, 1))
	var c := ChunkWriter.chunk_from_field(f, Vector2i(0, 1), 64.0, ORIGIN, Vector2i(1, 1))
	assert_eq(a.samples, CELLS + 3, "17 inner samples and the apron")
	assert_eq(b.origin, ORIGIN + Vector3(64, 0, 0), "the east neighbour's origin")
	var ha := a.decode_heights()
	var hb := b.decode_heights()
	var hc := c.decode_heights()
	var arr_a := TerrainChunk.new_terrain_arrays(a.inner())
	var arr_b := TerrainChunk.new_terrain_arrays(b.inner())
	var arr_c := TerrainChunk.new_terrain_arrays(c.inner())
	var no_colors: Array[Color] = []
	TerrainChunk.fill_rows(arr_a, ha, a.samples, 4.0, 0, a.inner(), no_colors)
	TerrainChunk.fill_rows(arr_b, hb, b.samples, 4.0, 0, b.inner(), no_colors)
	TerrainChunk.fill_rows(arr_c, hc, c.samples, 4.0, 0, c.inner(), no_colors)
	var m := a.inner()
	var worst_h := 0.0
	var worst_n := 0.0
	for j in m:
		# a's east column (i = m - 1) is b's west column (i = 0)
		worst_h = maxf(worst_h, absf(a.sample(m - 1, j) - b.sample(0, j)))
		var na: Vector3 = (arr_a.nrm as PackedVector3Array)[j * m + m - 1]
		var nb: Vector3 = (arr_b.nrm as PackedVector3Array)[j * m]
		worst_n = maxf(worst_n, na.distance_to(nb))
		# a's south row (j = m - 1) is c's north row (j = 0)
		worst_h = maxf(worst_h, absf(a.sample(j, m - 1) - c.sample(j, 0)))
		var na2: Vector3 = (arr_a.nrm as PackedVector3Array)[(m - 1) * m + j]
		var nc: Vector3 = (arr_c.nrm as PackedVector3Array)[j]
		worst_n = maxf(worst_n, na2.distance_to(nc))
	assert_eq(worst_h, 0.0, "border samples are identical on both sides of the seams")
	assert_true(worst_n < 1e-6, "the apron gives the border vertices identical normals (worst %s)" % worst_n)
	assert_true(worst_n == 0.0 or worst_n < 1e-6, "no crease of light along a seam")
	# The apron is the neighbour's first inner sample.
	assert_eq(a.sample(m, 3), b.sample(1, 3), "a's east apron is b's second column")


func test_relaxation_flattens_a_steep_bump_at_a_border() -> void:
	# A sharp 6 m step 2 m wide right on the x = 0 seam: about 56 degrees across it.
	var f := _field(func(x: float, z: float) -> float:
		return 10.0 + (6.0 if x >= 0.0 and x < 4.0 and absf(z + 20.0) < 10.0 else 0.0))
	var before := f.border_report(Vector2i(1, 1), CELLS, Vector2i(2, 2))
	assert_true(float(before.deg) > 40.0, "the step starts steep (%.1f degrees)" % before.deg)
	assert_near(float(before.x), 0.0, 6.0, "and the report finds it at the seam (x %.0f)" % before.x)
	var r := f.relax_borders(Vector2i(1, 1), CELLS, Vector2i(2, 2))
	assert_true(bool(r.ok), "the relaxation succeeds (%s)" % r.get("message", ""))
	var after := f.border_report(Vector2i(1, 1), CELLS, Vector2i(2, 2))
	assert_true(float(after.deg) <= HeightField.BORDER_MAX_DEG + HeightField.SLOPE_EPS_DEG,
		"no border face over 35 degrees afterwards (%.2f)" % after.deg)
	assert_eq(int(after.cells), 0, "none over the rule")
	f.quantise_all()
	var q := f.border_report(Vector2i(1, 1), CELLS, Vector2i(2, 2))
	assert_true(float(q.deg) <= HeightField.BORDER_MAX_DEG + HeightField.SLOPE_EPS_DEG,
		"and still none once quantised to 4 mm (%.2f)" % q.deg)
	# Ground far from every border is left alone.
	assert_near(f.sample(-40.0, -40.0), 10.0, 0.004, "ground away from the seams keeps its height")


func test_relaxation_names_a_ramp_it_cannot_fix() -> void:
	# A long 40-degree ramp along x across the x = 0 seam: smoothing cannot bend a plane.
	var t40 := tan(deg_to_rad(40.0))
	var f := _field(func(x: float, _z: float) -> float: return 10.0 + clampf(x + 20.0, 0.0, 40.0) * t40)
	var r := f.relax_borders(Vector2i(1, 1), CELLS, Vector2i(2, 2), HeightField.BORDER_BAND_M,
		HeightField.BORDER_MAX_DEG, Callable(), 5)
	assert_false(bool(r.ok), "the builder must fail")
	assert_true(str(r.get("message", "")).contains("near ("), "naming the place: %s" % r.get("message", ""))
	assert_true(float(r.deg) > 35.0, "the slope it reports")


func test_relaxation_spares_unwalkable_ground() -> void:
	var f := _field(func(x: float, _z: float) -> float: return 10.0 + maxf(x + 8.0, 0.0) * 3.0)
	var walkable := func(x: float, _z: float) -> bool: return x < -12.0
	var r := f.relax_borders(Vector2i(1, 1), CELLS, Vector2i(2, 2), HeightField.BORDER_BAND_M,
		HeightField.BORDER_MAX_DEG, walkable)
	assert_true(bool(r.ok), "a cliff that is not walkable is no border problem")
	assert_near(f.sample(8.0, 0.0), 10.0 + 48.0, 0.01, "and it is left as it was")


func test_parts_stay_within_150_nodes() -> void:
	var elements: Array = []
	for k in 30:
		var n := Node3D.new()
		n.name = "Prop%d" % k
		for c in (k % 7) + 3:
			n.add_child(Node3D.new())
		elements.append({"node": n, "container": "Props" if k % 5 != 0 else "Markers/Safe"})
	var total := 0
	for e: Dictionary in elements:
		total += ChunkWriter.node_count(e.node as Node)
	var split := ChunkWriter.split_parts(elements, 60)
	assert_true(bool(split.ok), "the elements split")
	var parts: Array = split.parts
	assert_true(parts.size() >= 3, "into several parts (%d)" % parts.size())
	var placed := 0
	for i in parts.size():
		var root := ChunkWriter.part_scene(Vector2i(2, 5), i, parts[i])
		assert_eq(str(root.name), "Chunk_2_5_%d" % i, "the part's root name")
		for c: String in ChunkWriter.CONTAINERS:
			assert_true(root.has_node(c), "part %d has %s" % [i, c])
		var count := ChunkWriter.node_count(root)
		assert_true(count <= 60, "part %d has %d nodes (at most 60)" % [i, count])
		placed += (parts[i] as Array).size()
		root.free()
	assert_eq(placed, elements.size(), "every element is in a part, once")
	var big := Node3D.new()
	for c in 200:
		big.add_child(Node3D.new())
	var too_big := ChunkWriter.split_parts([{"node": big, "container": "Props"}])
	assert_false(bool(too_big.ok), "an element bigger than a part fails")
	big.free()


func test_the_test_worlds_parts_stay_within_150_nodes() -> void:
	var d := load("res://assets/test_world/chunks/c2_2.res") as ChunkData
	assert_true(d != null and d.props_scenes.size() >= 2, "the town chunk has several parts")
	if d == null:
		return
	for path in d.props_scenes:
		var root := (load(path) as PackedScene).instantiate()
		var n := ChunkWriter.node_count(root)
		assert_true(n <= ChunkWriter.MAX_PART_NODES, "%s: %d nodes" % [path.get_file(), n])
		assert_eq(str(root.name), path.get_file().get_basename().replace("c", "Chunk_"), "%s's root" % path.get_file())
		root.free()


func test_the_coarse_skyline_never_rises_above_the_fine_heights() -> void:
	var f := _field(func(x: float, z: float) -> float:
		return 20.0 + 8.0 * sin(x * 0.11) * cos(z * 0.13) + (15.0 if Vector2(x, z).length() < 12.0 else 0.0), Vector2i(2, 2))
	var coarse := SkylineWriter.coarse(f, Rect2(-64.0, -64.0, 128.0, 128.0))
	assert_eq(coarse.size, Vector2i(5, 5), "a vertex every 32 m")
	var worst := -INF
	for j in range(1, f.size.y - 2):
		for i in range(1, f.size.x - 2):
			var x := f.world_x(i)
			var z := f.world_z(j)
			var c := SkylineWriter.coarse_height(coarse, x, z)
			if is_nan(c):
				continue
			worst = maxf(worst, c - f.at(i, j))
	assert_true(worst <= -SkylineWriter.DROP_M + 1e-4, "the coarse surface stays 2 m under every fine sample (worst %.3f)" % worst)
	var mesh := SkylineWriter.terrain_mesh(coarse, func(_x: float, _z: float) -> Color: return Color.RED)
	assert_eq(mesh.get_surface_count(), 1, "one surface")
	var arrays := mesh.surface_get_arrays(0)
	assert_eq((arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size(), 25, "25 vertices")
	assert_eq((arrays[Mesh.ARRAY_INDEX] as PackedInt32Array).size(), 4 * 4 * 6, "two triangles a cell")
