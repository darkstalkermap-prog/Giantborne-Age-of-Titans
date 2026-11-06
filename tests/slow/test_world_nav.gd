extends IntegrationSuite
## P24b (plan M6-M9 §3.7, decision 13; open_world_tech.md §5.2): navigation across the generated test
## world's chunks with its baked navmeshes (tools/world/nav_bake.gd) - every chunk loaded and ready:
##   * 40 random cross-chunk paths per layer (human, large, titan) reach their goal (seeded pairs up to
##     150 m apart in x and z, in different chunks, away from the ford; the far purpose's 300 m cap);
##   * the gated ford across the x = 256 seam: a stage-3 titan mask never enters its gate-4 region, a
##     stage-4 mask wades straight across; humans keep out of its deep water;
##   * the town's north gate: its links joined their layer maps; breaking it shortens the human path
##     from outside the gate to inside the wall from a detour by a gateway to a walk through the gate.

const SCENE := "res://scenes/test/test_world.tscn"
const TW := preload("res://tools/builders/test_world.gd")
const PAIRS := 40
const SEED := 2407


## The test world with every chunk loaded and ready, no director (navigation only).
func _world_all() -> WorldRoot:
	var w := (load(SCENE) as PackedScene).instantiate() as WorldRoot
	var d := w.get_node_or_null("EncounterDirector")
	if d != null:
		w.remove_child(d)
		d.free()
	world.add_child(w)
	TestSpawn.disable_all_ai(w)
	var s := w.streamer
	s.deterministic = true
	s.load_ring = 3
	s.unload_at = 6
	var at := Vector3(-128.0, 0.0, -128.0)
	w.player().global_position = at + Vector3.UP * 20.0
	var guard := 0
	while not s.ring_ready(at) and guard < 200:
		s.load_ring_slice(at)
		await step_ticks(1)
		guard += 1
	return w


## True when the straight segment a-b passes within `margin` m of the ford's water.
static func _crosses_ford(a: Vector3, b: Vector3, margin: float) -> bool:
	for i in 41:
		var p := a.lerp(b, i / 40.0)
		if TW.ford_distance(p.x, p.z) < TW.FORD_HALF_M + TW.FORD_BANK_M + margin:
			return true
	return false


## True when the path crosses the ford's axis (the segment FORD_A..FORD_B, z constant).
static func _crosses_axis(p: PackedVector3Array) -> bool:
	var z := TW.FORD_A.y
	for i in range(1, p.size()):
		var a := p[i - 1]
		var b := p[i]
		if (a.z - z) * (b.z - z) < 0.0:
			var t := (z - a.z) / (b.z - a.z)
			var x := lerpf(a.x, b.x, t)
			if x >= TW.FORD_A.x and x <= TW.FORD_B.x:
				return true
	return false


static func _length(p: PackedVector3Array) -> float:
	var total := 0.0
	for i in range(1, p.size()):
		total += p[i - 1].distance_to(p[i])
	return total


func test_random_cross_chunk_paths_on_every_layer() -> void:
	var w: WorldRoot = await _world_all()
	assert_eq(w.streamer.loaded_chunks().size(), 16, "every chunk loaded")
	assert_true(w.streamer.ring_ready(Vector3(-128.0, 0.0, -128.0)), "and ready")
	var rng := RandomNumberGenerator.new()
	for layer: int in [1, 2, 16]:
		rng.seed = SEED + layer
		var ok := 0
		var tried := 0
		var misses: Array = []
		var guard := 0
		var t0 := Time.get_ticks_usec()
		while tried < PAIRS and guard < 5000:
			guard += 1
			var a := Vector3(rng.randf_range(-430.0, 430.0), 0.0, rng.randf_range(-430.0, 430.0))
			var b := a + Vector3(rng.randf_range(-150.0, 150.0), 0.0, rng.randf_range(-150.0, 150.0))
			if absf(b.x) > 430.0 or absf(b.z) > 430.0 or w.chunk_at(a) == w.chunk_at(b) or _crosses_ford(a, b, 10.0):
				continue
			var sa := NavQuery.closest_point(w, a + Vector3.UP * 30.0, layer)
			var sb := NavQuery.closest_point(w, b + Vector3.UP * 30.0, layer)
			if not sa.is_finite() or not sb.is_finite() or Vector2(sa.x - a.x, sa.z - a.z).length() > 6.0 \
					or Vector2(sb.x - b.x, sb.z - b.z).length() > 6.0:
				continue   # under a tree, a house, in the water: another pair
			tried += 1
			var p := NavQuery.path(w, sa, sb, layer, NavQuery.PURPOSE_FAR)
			if p.size() > 0 and p[p.size() - 1].distance_to(sb) <= 1.0:
				ok += 1
			elif misses.size() < 3:
				misses.append("%s -> %s ends %s" % [sa, sb, p[p.size() - 1] if p.size() > 0 else Vector3.INF])
		var ms := (Time.get_ticks_usec() - t0) / 1000.0
		print("    layer %d: %d / %d cross-chunk paths reach (%.1f ms for the pairs and their queries)" % [layer, ok, tried, ms])
		assert_eq(tried, PAIRS, "layer %d: %d pairs tried" % [layer, PAIRS])
		assert_eq(ok, PAIRS, "layer %d: every cross-chunk path reaches its goal: %s" % [layer, misses])


func test_the_gated_ford_and_the_town_gate() -> void:
	var w: WorldRoot = await _world_all()
	var north := NavQuery.closest_point(w, Vector3(256.0, 30.0, -428.0), 16 | 32)
	var south := NavQuery.closest_point(w, Vector3(256.0, 30.0, -336.0), 16 | 32)
	assert_true(TW.ford_distance(north.x, north.z) > TW.FORD_GATE_M and TW.ford_distance(south.x, south.z) > TW.FORD_GATE_M,
		"two points on the titan layer either side of the ford (%s, %s)" % [north, south])
	assert_true(w.chunk_at(north) == "c3_0", "on the seam's east side")
	var wade := NavQuery.path(w, north, south, 16 | 32, NavQuery.PURPOSE_FAR)
	assert_true(wade.size() > 0 and wade[wade.size() - 1].distance_to(south) <= 1.0, "a stage-4 mask (16 + 32) reaches the far bank")
	assert_true(_length(wade) < 120.0, "straight across the ford (%.0f m)" % _length(wade))
	var in_ford := 0
	for q in wade:
		if TW.ford_distance(q.x, q.z) < TW.FORD_GATE_M:
			in_ford += 1
	assert_true(in_ford > 0, "through its gate-4 region")
	assert_true(_crosses_axis(wade), "the stage-4 path crosses the ford's axis")
	var round := NavQuery.path(w, north, south, 16, NavQuery.PURPOSE_FAR)
	assert_false(_crosses_axis(round), "a stage-3 mask (16) never crosses the ford (its gate-4 region is closed to it)")
	var nearest := INF
	for q in round:
		nearest = minf(nearest, TW.ford_distance(q.x, q.z))
	assert_true(nearest > TW.FORD_HALF_M, "nor walks its bed (nearest %.1f m from the axis)" % nearest)
	var deep := NavQuery.closest_point(w, Vector3(256.0, 30.0, -380.0), 1)
	assert_true(TW.ford_distance(deep.x, deep.z) > TW.FORD_HALF_M + 4.0,
		"no human navmesh in the deep water (the nearest is %.1f m from the axis)" % TW.ford_distance(deep.x, deep.z))
	# The town's north gate (c2_2): closed, its links on their maps; broken, the path goes through it.
	var gate: BreakableProp = null
	for n in get_tree().get_nodes_in_group("breakables"):
		if n is BreakableProp and (n as BreakableProp).world_id == "test_world.town.gate_north":
			gate = n
	assert_true(gate != null, "the north gate streamed in")
	for link: NavigationLink3D in gate.nav_links():
		var layer := int(link.navigation_layers) & -int(link.navigation_layers)
		assert_eq(NavigationServer3D.link_get_map(link.get_rid()), w.nav_map(layer), "%s joined its layer's map" % link.name)
	var outside := NavQuery.closest_point(w, Vector3(128.0, 30.0, 44.0), 1)
	var inside := NavQuery.closest_point(w, Vector3(128.0, 30.0, 70.0), 1)
	var before := NavQuery.path(w, outside, inside, 1, NavQuery.PURPOSE_FAR)
	var marks := {}
	for layer: int in [1, 2, 16]:
		marks[layer] = NavigationServer3D.map_get_iteration_id(w.nav_map(layer))
	assert_true(gate.force_open("test"), "the gate breaks")
	var synced := false
	for i in 10:
		await step_ticks(1)
		synced = NavigationServer3D.map_get_iteration_id(w.nav_map(1)) > int(marks[1])
		if synced:
			break
	assert_true(synced, "the human map synced the opened links")
	var after := NavQuery.path(w, outside, inside, 1, NavQuery.PURPOSE_FAR)
	assert_true(after.size() > 0 and after[after.size() - 1].distance_to(inside) <= 1.0, "inside the wall through the gate")
	assert_true(_length(after) < 40.0, "a short walk through the broken gate (%.0f m)" % _length(after))
	assert_true(before.is_empty() or before[before.size() - 1].distance_to(inside) > 1.0 or _length(before) > 3.0 * _length(after),
		"before, only a detour by a gateway (%.0f m)" % _length(before))
