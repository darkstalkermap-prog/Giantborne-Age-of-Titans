extends IntegrationSuite
## P24b (plan M6-M9 §2.2, §2.8, decision 13): a streamed world's navigation on the tiny nav world
## (tests/support/nav_tiny_world.gd: three 64 m chunks with hand-made navmeshes) - one map per layer
## with the gate bits on the titan map, the streamer's navmesh steps (a load and its region's add in
## different frames), readiness one tick after a chunk's last region add with async iterations off,
## seams joining without edge connections, a stage-3 titan mask stopped by the gate-4 ford and a
## stage-4 mask crossing it, NavQuery's closest point keeping to the mask, and an unload freeing the
## chunk's regions.


func _root(extra := {}) -> WorldRoot:
	NavTinyWorld.write()
	NavTinyWorld.install_record(true, extra)
	var root := NavTinyWorld.make_root()
	world.add_child(root)
	root.streamer.deterministic = true
	root.streamer.process_mode = Node.PROCESS_MODE_DISABLED   # the tests drive it
	return root


## Loads the ring around `at` with loading-screen slices; true when every chunk of it is loaded.
func _load_ring(root: WorldRoot, at: Vector3) -> bool:
	for i in 40:
		var all := true
		for id in root.streamer.ring_ids(at):
			all = all and root.streamer.is_loaded(id)
		if all:
			return true
		root.streamer.load_ring_slice(at)
	return false


## Waits (ticks) until the ring around `at` is ready.
func _ready_ring(root: WorldRoot, at: Vector3, max_ticks := 10) -> bool:
	for i in max_ticks:
		if root.streamer.ring_ready(at):
			return true
		await step_ticks(1)
	return root.streamer.ring_ready(at)


func test_a_map_per_layer_and_the_gate_bits_on_the_titan_map() -> void:
	var root := _root()
	assert_eq(root.nav_layers(), PackedInt32Array([1, 2, 16]), "the world block's layers")
	var human := root.nav_map(1)
	var large := root.nav_map(2)
	var titan := root.nav_map(16)
	assert_true(human.is_valid() and large.is_valid() and titan.is_valid(), "a map per layer")
	assert_true(human != large and large != titan and human != root.get_world_3d().navigation_map, "their own maps")
	assert_eq(root.nav_map(), human, "layer 0: the human map")
	assert_eq(root.nav_map(32), titan, "gate-4 regions join the titan map")
	assert_false(root.nav_map(4).is_valid(), "no map for the Valley's giant layer")
	assert_eq(root.nav_layer_for(4), 16, "a stage-3 profile (giant layer 4) paths on the titan layer here")
	assert_true(NavQuery.uses_layer_maps(root), "NavQuery sees the layer maps")
	var at := NavTinyWorld.at(1, Vector3(32, 0, 32))
	assert_true(_load_ring(root, at), "the three chunks loaded")
	assert_true(await _ready_ring(root, at), "and ready (the server applies map and region settings at its sync)")
	var counts := root.streamer.nav_maps.region_counts()
	assert_eq(counts, {1: 3, 2: 3, 16: 4}, "a region per chunk and layer, the ford's gate region on the titan map")
	assert_eq(root.streamer.nav_maps.bit_counts().get(32, 0), 1, "one gate-4 region")
	for pair: Array in [[human, 0.25, 0.25], [large, 0.5, 0.5], [titan, 1.0, 0.5]]:
		assert_near(NavigationServer3D.map_get_cell_size(pair[0]), pair[1], 1e-6, "the map's cell size is its navmeshes'")
		assert_near(NavigationServer3D.map_get_cell_height(pair[0]), pair[2], 1e-6, "and its cell height")
		assert_false(NavigationServer3D.map_get_use_async_iterations(pair[0]), "deterministic: map async iterations off")
		assert_false(NavigationServer3D.map_get_use_edge_connections(pair[0]), "edge connections off")
	for r: Dictionary in root.streamer.nav_maps.chunk_regions("c1_0"):
		assert_false(NavigationServer3D.region_get_use_async_iterations(r.rid), "region async iterations off (bit %d)" % r.bit)
		assert_false(NavigationServer3D.region_get_use_edge_connections(r.rid), "no region edge connections (bit %d)" % r.bit)


func test_a_chunk_is_ready_one_tick_after_its_last_region_add() -> void:
	var root := _root()
	var s := root.streamer
	var at := NavTinyWorld.at(0, Vector3(20, 0, 32))
	s.focus(at)
	var frames: Array = []   # per update(): {kind: steps of that kind}
	var loaded_tick := -1
	var ready_tick := -1
	var map := root.nav_map(16)   # the titan region is the chunk's last add (bits ascending)
	var iteration_at_load := -1
	for i in 120:
		if not s.is_loaded("c0_0"):
			var before := s.step_breakdown()
			s.update()
			var after := s.step_breakdown()
			var frame := {}
			for k: String in after:
				var n := int(after[k].n) - (int(before[k].n) if before.has(k) else 0)
				if n > 0:
					frame[k] = n
			frames.append(frame)
			if s.is_loaded("c0_0"):
				loaded_tick = Sim.tick
				iteration_at_load = NavigationServer3D.map_get_iteration_id(map)
				assert_false(s.is_ready("c0_0"), "loaded (its regions added) but not ready before the map syncs")
		elif ready_tick < 0 and s.is_ready("c0_0"):
			ready_tick = Sim.tick
			break
		await step_ticks(1)
	assert_true(loaded_tick >= 0, "the chunk loaded")
	assert_eq(ready_tick - loaded_tick, 1, "ready one tick after its last region add (async off)")
	assert_true(NavigationServer3D.map_get_iteration_id(map) > iteration_at_load, "the titan map's iteration passed the add")
	var bd := s.step_breakdown()
	assert_eq(int(bd.get("nav_add", {}).get("n", 0)), 3, "three regions for c0_0 (human, large, titan)")
	assert_eq(int(bd.get("nav_load", {}).get("n", 0)), 3, "each navmesh loaded in a step of its own")
	var nav_frames := 0
	var mixed := 0
	for f: Dictionary in frames:
		if f.has("nav_load") or f.has("nav_add"):
			nav_frames += 1
			var total := 0
			for k: String in f:
				total += int(f[k])
			if total != 1:
				mixed += 1
	assert_eq(nav_frames, 6, "six frames of navigation steps (a load and an add per layer)")
	assert_eq(mixed, 0, "each navmesh load and each region add ran alone in its frame")
	# The loading screen's ring slices run them together (behind the screen, nothing waits).
	var root2 := _root()
	assert_true(_load_ring(root2, at), "a ring loads in slices with its navigation")
	assert_false(root2.streamer.is_ready("c0_0"), "not ready before a tick passed")
	await step_ticks(1)
	assert_true(root2.streamer.ring_ready(at), "the whole ring ready one tick later")


func test_seams_join_and_the_gated_ford() -> void:
	var root := _root()
	var mid := NavTinyWorld.at(1, Vector3(32, 0, 32))
	assert_true(_load_ring(root, mid), "loaded")
	assert_true(await _ready_ring(root, mid), "ready")
	# Across the c0_0 / c1_0 seam on every layer (the same edge in both chunks: no edge connections).
	var a := NavTinyWorld.at(0, Vector3(10, NavTinyWorld.NAV_Y, 20))
	var b := NavTinyWorld.at(1, Vector3(12, NavTinyWorld.NAV_Y, 50))
	for layer: int in [1, 2, 16]:
		assert_true(NavQuery.reaches(root, a, b, layer, 0.5), "layer %d crosses the seam" % layer)
	# The ford (c1_0, local x 24..40): a gate-4 region of the titan layer, deep water for the others.
	var west := NavTinyWorld.at(1, Vector3(8, NavTinyWorld.NAV_Y, 32))
	var east := NavTinyWorld.at(1, Vector3(56, NavTinyWorld.NAV_Y, 32))
	var stage3 := NavQuery.path(root, west, east, 16, NavQuery.PURPOSE_FAR)
	assert_true(stage3.size() > 0, "a stage-3 mask gets a path toward the ford")
	var end3 := stage3[stage3.size() - 1]
	assert_true(end3.x <= NavTinyWorld.at(1, Vector3(NavTinyWorld.FORD.x, 0, 0)).x + 0.01,
		"... that stops at the ford's west edge (ends at x %.2f)" % end3.x)
	assert_true(NavQuery.reaches(root, west, east, 16 | 32, 0.5), "a stage-4 mask (16 + 32) wades across")
	assert_false(NavQuery.reaches(root, west, east, 16 | 64, 0.5), "a gate-5 bit alone does not open a gate-4 ford")
	assert_true(NavQuery.reaches(root, west, east, 240, 0.5), "a rival giant's mask (240) crosses every gate")
	assert_false(NavQuery.reaches(root, west, east, 1, 0.5), "humans do not wade deep water")
	var ford := NavTinyWorld.at(1, Vector3(32, NavTinyWorld.NAV_Y, 32))
	var p16 := NavQuery.closest_point(root, ford, 16)
	var p48 := NavQuery.closest_point(root, ford, 48)
	var local16 := p16.x - NavTinyWorld.at(1, Vector3.ZERO).x
	assert_true(local16 <= NavTinyWorld.FORD.x + 0.01 or local16 >= NavTinyWorld.FORD.y - 0.01,
		"the closest point for a stage-3 mask is on the bank (x %.2f), not in the gate region" % local16)
	assert_true(p48.distance_to(ford) < 0.2, "for a stage-4 mask it is in the ford")


func test_an_unload_frees_the_chunks_regions() -> void:
	var root := _root({"world": {"load_ring": 0, "unload_at": 2}})
	var s := root.streamer
	var west := NavTinyWorld.at(0, Vector3(32, 0, 32))
	assert_true(_load_ring(root, west), "c0_0 loaded")
	assert_true(await _ready_ring(root, west), "and ready")
	var gone: Array = []
	for r: Dictionary in s.nav_maps.chunk_regions("c0_0"):
		gone.append(r.rid)
	assert_eq(gone.size(), 3, "its three regions")
	var east := NavTinyWorld.at(2, Vector3(32, 0, 32))
	assert_true(_load_ring(root, east), "c2_0 loaded")
	for i in 20:
		if not s.is_loaded("c0_0") and s.loading_chunk() == "":
			break
		s.update(true)
	assert_false(s.is_loaded("c0_0"), "c0_0 unloaded (two chunks away)")
	assert_eq(s.nav_maps.chunk_regions("c0_0").size(), 0, "its regions are gone from the maps' books")
	await step_ticks(2)
	for m: RID in [root.nav_map(1), root.nav_map(2), root.nav_map(16)]:
		var regions := NavigationServer3D.map_get_regions(m)
		for rid: RID in gone:
			assert_false(regions.has(rid), "a freed region left its map")
	assert_eq(s.nav_maps.region_counts(), {1: 1, 2: 1, 16: 1}, "only c2_0's regions remain")
	assert_eq(int(s.nav_maps.regions_removed), 3, "three removed")

