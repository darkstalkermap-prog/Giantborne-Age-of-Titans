extends IntegrationSuite
## M8 gate (F26; plan M6-M9 §5.2: streaming work at most 4 ms a frame, its steps under about 3 ms on
## desktop): the world's runtime scripts and the shared scenes its chunks' props sub-scenes use are
## loaded when the world is built - inside main.gd's level build, behind the loading screen - from
## level.world's `preload` list (WorldRoot.warm_preload()), as the EncounterDirector loads its enemy
## scenes. Before, each was loaded the first time a chunk that uses it streamed in, in a TerrainChunk
## "props_dep" step of its own: fort_battle.gd 19-27 ms, stone_throne.gd and forge_fire.gd 12-14 ms,
## the toppled statue's and the rockfall's scenes 7-12 ms (headless desktop; on the web build, with no
## loader thread, up to 41.7 ms in the frame).
##   * once the world is built, every path of the list is in the resource cache, and no chunk's props
##     sub-scene has a dependency left to load;
##   * streaming every chunk that has props, one after another (deterministic streaming), runs no
##     "props_dep" step at all.

const WORLD_SCENE := "res://scenes/world/world.tscn"
const LEVEL := "level.world"
const CHUNK_DIR := "res://assets/world/chunks"


## The world scene added to the test tree (deterministic streaming, AI off) with the ring around the
## giant loaded.
func _world() -> WorldRoot:
	var w := (load(WORLD_SCENE) as PackedScene).instantiate() as WorldRoot
	world.add_child(w)
	w.streamer.deterministic = true
	TestSpawn.disable_all_ai(w)
	var p := w.player()
	var guard := 0
	while not w.streamer.ring_ready(p.global_position) and guard < 600:
		w.streamer.load_ring_slice(p.global_position)
		guard += 1
	return w


## The chunks with props sub-scenes -> their props scenes, row by row (west to east, then back), so
## each next chunk is near the last.
static func _props_chunks() -> Dictionary:
	var out := {}
	for z in 8:
		for k in 8:
			var x := k if z % 2 == 0 else 7 - k
			var id := "c%d_%d" % [x, z]
			var path := CHUNK_DIR.path_join(id + ".res")
			if not ResourceLoader.exists(path):
				continue
			var data := load(path) as ChunkData
			if data != null and not data.props_scenes.is_empty():
				out[id] = data.props_scenes.duplicate()
	return out


func test_the_world_holds_its_preload_list_once_built() -> void:
	var w := _world()
	print("    test_world_preload: the world's _ready loaded %d preload paths in %.1f ms (0: an earlier world of this run had)" % [
		w.preload_loaded, w.preload_ms])
	var listed: Array = GameData.get_record(LEVEL).get("preload", [])
	assert_true(listed.size() >= 40, "level.world preloads the chunks' shared resources (%d)" % listed.size())
	var not_cached: Array = []
	for p: Variant in listed:
		if not ResourceLoader.has_cached(str(p)):
			not_cached.append(str(p).get_file())
	assert_eq(not_cached, [], "every preloaded path is in the resource cache once the world is built")
	var chunks := _props_chunks()
	assert_true(chunks.size() >= 40, "most chunks have props (%d)" % chunks.size())
	var left := {}
	for id: String in chunks:
		for scene: String in chunks[id]:
			for dep in TerrainChunk.missing_dependencies(scene):
				left[dep.get_file()] = id
	assert_eq(left, {}, "no chunk's props sub-scene has a dependency left to load during play")
	w.queue_free()
	await get_tree().process_frame


func test_streaming_every_chunk_with_props_runs_no_dependency_step() -> void:
	var w := _world()
	var s := w.streamer
	# The streamer follows this test's focus, not the giant (which stays put at the start, still).
	w.set_process(false)
	w.player().process_mode = Node.PROCESS_MODE_DISABLED
	s.reset_stats()
	var chunks := _props_chunks()
	var t0 := Time.get_ticks_msec()
	for id: String in chunks:
		var at := s.chunk_center(id)
		var guard := 0
		while not s.is_loaded(id) and guard < 4000:
			s.focus(at)
			s.update()
			guard += 1
		assert_true(s.is_loaded(id), "%s streamed in" % id)
		# the chunks unloaded on the way are freed before any of them streams in again
		await get_tree().process_frame
	var kinds := s.step_breakdown()
	var st := s.stats()
	print("    test_world_preload: %s" % JSON.stringify({"chunks": chunks.size(), "loads": st.loads,
		"wall_ms": Time.get_ticks_msec() - t0, "work_ms_max": st.work_ms_max,
		"props_load": kinds.get("props_load", {}), "props_add": kinds.get("props_add", {}),
		"props_dep": kinds.get("props_dep", {})}))
	assert_true(int(st.loads) >= chunks.size(), "every chunk with props was loaded (%d loads)" % st.loads)
	assert_true(kinds.has("props_load") and int(kinds.props_load.n) >= chunks.size(), "their props sub-scenes streamed in")
	assert_false(kinds.has("props_dep"), "no step loaded a props dependency during play: %s" % [kinds.get("props_dep")])
	w.queue_free()
	await get_tree().process_frame
