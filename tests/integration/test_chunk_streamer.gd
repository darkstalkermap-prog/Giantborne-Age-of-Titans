extends IntegrationSuite
## P24a (plan M6-M9 §2.8, decision 12): the ChunkStreamer on tiny worlds of 64 m chunks
## (tests/support/tiny_world.gd) - the step quota of deterministic streaming, nearest first, the
## ring following a moving focus, chunk_unloading before any node of the chunk is freed (and the
## Events), hysteresis (20 walks across a border load each chunk once: no thrash, where unloading
## one ring nearer would thrash), at most 25 chunks loaded in a zigzag, the starting ring's
## progress, and a streamer leaving the tree taking the chunk it was loading with it.

const GRID := Vector2i(6, 6)

var _events: Array = []


func before_each() -> void:
	await super()
	_events.clear()
	Events.world_chunk_loaded.connect(_on_loaded)
	Events.world_chunk_unloading.connect(_on_unloading)
	Events.world_chunk_unloaded.connect(_on_unloaded)


func after_each() -> void:
	for sig: Signal in [Events.world_chunk_loaded, Events.world_chunk_unloading, Events.world_chunk_unloaded]:
		for c: Dictionary in sig.get_connections():
			if (c.callable as Callable).get_object() == self:
				sig.disconnect(c.callable)
	await super()


func _on_loaded(id: String) -> void:
	_events.append("loaded:" + id)


func _on_unloading(id: String) -> void:
	_events.append("unloading:" + id)


func _on_unloaded(id: String) -> void:
	_events.append("unloaded:" + id)


## A deterministic streamer over the tiny 6 x 6 world (written once for every test), driven by
## hand (update()).
func _streamer(grid: Vector2i, extra := {}) -> ChunkStreamer:
	var cfg := TinyWorld.write(grid)
	cfg.merge(extra, true)
	var s := ChunkStreamer.new()
	s.name = "Streamer"
	world.add_child(s)
	s.process_mode = Node.PROCESS_MODE_DISABLED
	s.configure(cfg, world)
	s.deterministic = true
	return s


## Runs update() until nothing is left to do (at most `cap` calls); returns the calls made.
func _settle(s: ChunkStreamer, cap := 200) -> int:
	var n := 0
	while n < cap:
		n += 1
		if s.update() == 0:
			break
	return n


## The world position of the centre of chunk (x, z) of a tiny grid, shifted by `off`.
func _center(s: ChunkStreamer, x: int, z: int, off := Vector2.ZERO) -> Vector3:
	return s.origin + Vector3((x + 0.5) * s.chunk_size + off.x, 0.0, (z + 0.5) * s.chunk_size + off.y)


func test_a_fixed_quota_nearest_first() -> void:
	var s := _streamer(GRID, {"steps_per_frame_headless": 3})
	s.focus(_center(s, 1, 1, Vector2(20, 20)))
	assert_eq(s.queued_chunks().size(), 0, "nothing is queued before the first update")
	var ran := s.update()
	assert_eq(ran, 3, "a frame runs exactly the quota (3 steps)")
	assert_eq(s.loading_chunk(), "c1_1", "the focus chunk loads first")
	var queue := s.queued_chunks()
	assert_eq(queue.size(), 8, "the rest of the ring waits")
	assert_eq([queue[0], queue[1]], ["c1_2", "c2_1"], "nearest next (ties by id)")
	assert_true(queue[queue.size() - 1] in ["c0_0"], "the far corner last (%s)" % queue[queue.size() - 1])
	_settle(s)
	assert_eq(s.loaded_chunks(), PackedStringArray(["c0_0", "c0_1", "c0_2", "c1_0", "c1_1", "c1_2", "c2_0", "c2_1", "c2_2"]),
		"the 3 x 3 ring around c1_1")
	var st := s.stats()
	assert_eq(int(st.loads), 9, "nine loads")
	assert_true(int(st.work_frames) > 0 and float(st.work_ms_max) >= float(st.work_ms_p50), "work recorded per frame")
	assert_eq(_events.filter(func(e: String) -> bool: return e.begins_with("loaded:")).size(), 9, "Events.world_chunk_loaded for each")
	assert_true(s.ring_ready(_center(s, 1, 1)), "the ring is ready")
	assert_true(s.is_ready("c0_0") and not s.is_loaded("c3_3"), "is_ready / is_loaded")
	assert_true(s.chunk_data("c1_1") != null and s.data_at(_center(s, 1, 1)) == s.chunk_data("c1_1"), "the loaded data")


func test_the_ring_follows_a_moving_focus() -> void:
	var s := _streamer(GRID)
	s.focus(_center(s, 1, 1))
	_settle(s)
	assert_eq(s.loaded_chunks().size(), 9, "the first ring")
	# One chunk east: the new column loads, nothing unloads yet (it is only 2 away).
	s.focus(_center(s, 2, 1))
	_settle(s)
	for z in range(0, 3):
		assert_true(s.is_loaded("c3_%d" % z), "c3_%d loaded with the move" % z)
	assert_true(s.is_loaded("c0_1"), "c0_1 stays: distance 2 is not far enough to unload")
	# Two more east: column 0 is now 3 away and goes.
	s.focus(_center(s, 3, 1))
	_settle(s)
	s.focus(_center(s, 4, 1))
	_settle(s)
	for z in range(0, 3):
		assert_false(s.is_loaded("c0_%d" % z), "c0_%d unloaded at distance 4" % z)
		assert_false(s.is_loaded("c1_%d" % z), "c1_%d unloaded at distance 3" % z)
		assert_true(s.is_loaded("c2_%d" % z), "c2_%d kept at distance 2" % z)
		assert_true(s.is_loaded("c5_%d" % z), "c5_%d loaded" % z)
	assert_true(s.ring_ready(_center(s, 4, 1)), "the ring around the new focus is ready")
	await get_tree().process_frame
	assert_eq(s.chunks_parent.get_child_count(), s.loaded_chunks().size(), "unloaded chunks are freed")


func test_unloading_comes_before_any_node_is_freed() -> void:
	var s := _streamer(GRID)
	s.focus(_center(s, 0, 0))
	_settle(s)
	var node := s.chunk_node("c0_0")
	assert_true(node != null, "c0_0 is loaded")
	var seen := {}
	s.chunk_unloading.connect(func(id: String) -> void:
		if id == "c0_0":
			seen["valid"] = is_instance_valid(node) and node.is_inside_tree() and not node.is_queued_for_deletion()
			seen["terrain"] = node.terrain != null and is_instance_valid(node.terrain)
			seen["ground"] = node.ground != null and is_instance_valid(node.ground))
	s.chunk_unloaded.connect(func(id: String) -> void:
		if id == "c0_0":
			seen["unloaded_queued"] = not is_instance_valid(node) or node.is_queued_for_deletion())
	_events.clear()
	s.focus(_center(s, 3, 0))
	_settle(s)
	assert_true(bool(seen.get("valid", false)), "chunk_unloading: the chunk is still whole and in the tree")
	assert_true(bool(seen.get("terrain", false)) and bool(seen.get("ground", false)), "its terrain and ground still there")
	assert_true(bool(seen.get("unloaded_queued", false)), "chunk_unloaded: it is on its way out")
	var a := _events.find("unloading:c0_0")
	var b := _events.find("unloaded:c0_0")
	assert_true(a >= 0 and b > a, "Events: unloading, then unloaded (%s)" % [_events])
	assert_false(s.is_loaded("c0_0"), "no longer loaded")
	await get_tree().process_frame
	assert_false(is_instance_valid(node), "freed by the end of the frame")


func test_walking_a_border_twenty_times_loads_each_chunk_once() -> void:
	var s := _streamer(GRID)
	var west := _center(s, 3, 1, Vector2(24, 0))   # 8 m west of the x border between c3 and c4
	var east := _center(s, 4, 1, Vector2(-24, 0))  # 8 m east of it
	s.focus(west)
	_settle(s)
	for k in 20:
		s.focus(east)
		_settle(s)
		s.focus(west)
		_settle(s)
	var st := s.stats()
	assert_eq(int(st.thrash), 0, "no chunk reloaded (thrash 0)")
	assert_eq(int(st.unloads), 0, "nothing unloaded along the border")
	for id: String in s.load_counts:
		assert_eq(int(s.load_counts[id]), 1, "%s loaded once" % id)
	assert_eq(s.load_counts.size(), 12, "the two rings' 4 x 3 chunks")
	# Without the hysteresis (unloading one ring nearer) the same walk reloads chunks.
	var t := _streamer(GRID, {"unload_at": 2})
	t.name = "NoHysteresis"
	t.focus(west)
	_settle(t)
	for k in 3:
		t.focus(east)
		_settle(t)
		t.focus(west)
		_settle(t)
	assert_true(int(t.stats().thrash) > 0, "unload_at 2 would thrash (%d)" % t.stats().thrash)


func test_at_most_25_chunks_in_a_zigzag() -> void:
	var s := _streamer(GRID)
	var path: Array[Vector2i] = [Vector2i(1, 1), Vector2i(2, 2), Vector2i(3, 1), Vector2i(4, 2), Vector2i(5, 1),
		Vector2i(5, 3), Vector2i(4, 4), Vector2i(5, 5), Vector2i(3, 5), Vector2i(2, 4), Vector2i(1, 5), Vector2i(3, 3)]
	var worst := 0
	for c in path:
		s.focus(_center(s, c.x, c.y))
		for i in 200:
			var ran := s.update()
			worst = maxi(worst, s.loaded_chunks().size())
			if ran == 0:
				break
	assert_true(worst <= 25, "never more than 25 loaded (%d)" % worst)
	assert_true(worst > 9, "the zigzag keeps more than one ring (%d)" % worst)
	assert_eq(s.max_loaded, worst, "max_loaded reports it")


func test_a_streamer_leaving_frees_the_chunk_it_was_loading() -> void:
	var s := _streamer(GRID, {"steps_per_frame_headless": 2})
	s.focus(_center(s, 1, 1))
	assert_eq(s.update(), 2, "two steps: the request and the data")
	var c := s.get("_loading") as TerrainChunk
	assert_true(c != null and not c.is_inside_tree(), "the chunk being loaded is not in the tree before its mesh")
	world.remove_child(s)
	assert_false(is_instance_valid(c), "the streamer leaving frees it (nothing left behind when a level goes or the game quits)")
	s.free()


func test_the_starting_ring_in_slices() -> void:
	var s := _streamer(GRID)
	var at := _center(s, 2, 2)
	var last := -1.0
	var slices := 0
	while not s.ring_ready(at) and slices < 50:
		var p := s.load_ring_slice(at)
		assert_true(p >= last - 1e-6, "progress never goes back (%.2f after %.2f)" % [p, last])
		last = p
		slices += 1
	assert_true(s.ring_ready(at), "the ring is ready")
	assert_near(s.ring_progress(at), 1.0, 1e-6, "progress 1")
	assert_true(slices >= 2, "it took several slices (%d)" % slices)
	assert_eq(s.ring_ids(at).size(), 9, "nine chunks in the ring")
	assert_eq(s.ring_ids(_center(s, 0, 0)).size(), 4, "a corner's ring is cut by the grid")
