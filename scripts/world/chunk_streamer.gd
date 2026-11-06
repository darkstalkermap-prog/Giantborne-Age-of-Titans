class_name ChunkStreamer
extends Node
## Streams the chunks of a world level around a focus point (P24a; plan M6-M9 §2.8, decision 12,
## open_world_tech.md §3): the child "Streamer" of WorldRoot (group chunk_streamer,
## PROCESS_MODE_ALWAYS, so the starting ring keeps loading behind the paused loading screen).
##
## Hysteresis: chunks load within Chebyshev distance `load_ring` (1: the 3 x 3 ring) of the focus
## chunk, nearest first, and unload only at distance `unload_at` (3) or more, so at most 25 are
## loaded and walking along a border never reloads a chunk. A queued chunk that leaves the ring
## before its turn is dropped; one that is loading finishes (it stays until distance unload_at),
## unless it is already that far, when the load is abandoned.
##
## Work: one TerrainChunk step at a time (see terrain_chunk.gd) until the frame's budget is spent -
## `budget_ms` of wall time (a started step always finishes), or in deterministic streaming a fixed
## quota of `steps_per_frame_headless` steps and no clock, so headless runs and tests stream the same
## way every time. A heavy step (TerrainChunk.HEAVY_STEPS: a props sub-scene's dependency, its load,
## its instancing) runs alone in its frame, outside the loading screen's ring slices. An unload is two steps: chunk_unloading (also Events.world_chunk_unloading; the
## director despawns its members there) and the props freed, then the rest of the chunk freed and
## chunk_unloaded. Unloads go before loads. A threaded load that is not finished ends the frame's
## work (desktop); in deterministic streaming the load is taken at once.
##
## Thrash: a chunk loaded again within THRASH_WINDOW_S of its unload (the streamer's own clock: the
## sum of its frame deltas, deterministic under --fixed-fps). stats() reports it with the loads,
## unloads, steps, the most chunks ever loaded and the work per frame (p50 / p99 / max, frames that
## did work only).
##
## Navigation (P24b) extends the steps (a navmesh's load and its region's add in different frames)
## and is_ready() (every layer map's iteration past the chunk's last region add).

signal chunk_loaded(chunk_id: String)
## Before any node of the chunk is freed.
signal chunk_unloading(chunk_id: String)
signal chunk_unloaded(chunk_id: String)

const GROUP := "chunk_streamer"
const THRASH_WINDOW_S := 10.0
## The starting ring behind the loading screen: a slice is this many times the frame's quota
## (deterministic) or RING_SLICE_MS of work.
const RING_SLICE_STEPS_FACTOR := 4
const RING_SLICE_MS := 12.0
const MAX_WORK_SAMPLES := 200000
## World-block defaults (plan §2.7; the level record's "world" overrides them).
const DEFAULTS := {"chunk_size_m": 256.0, "grid": [8, 8], "origin_m": [-1024.0, 0.0, -1024.0],
	"height_spacing_m": 4.0, "load_ring": 1, "unload_at": 3, "budget_ms": 4.0, "steps_per_frame_headless": 6,
	"chunk_dir": "", "nav_dir": ""}
const DETERMINISTIC_ARG := "--deterministic-streaming"
const TERRAIN_ROUGHNESS := 1.0
const WATER_COLOR := Color(0.2, 0.33, 0.42, 0.78)

## Fixed step quota per frame and no clock (headless runs, tests); P24b also turns navigation's
## async iterations off when this is set.
var deterministic := false
var configured := false
var chunk_size := 256.0
var grid := Vector2i(8, 8)
var origin := Vector3(-1024.0, 0.0, -1024.0)
var load_ring := 1
var unload_at := 3
var budget_ms := 4.0
var steps_per_frame := 6
var chunk_dir := ""
var nav_dir := ""
## The render preset's distances (WorldRoot keeps them in step; 0 = no limit).
var terrain_visibility_end_m := 0.0
var scenery_visibility_end_m := 0.0
## The level's region list (the world index's region_ids): ChunkData.region_cells index it.
var region_ids := PackedStringArray()
var level_root: Node3D = null
var chunks_parent: Node3D = null

var loads := 0
var unloads := 0
var thrash := 0
var steps := 0
var aborted_loads := 0
var max_loaded := 0
## Chunk id -> how many times it was loaded.
var load_counts := {}

var _focus := Vector3.INF
var _focus_cell := Vector2i(-1000000, -1000000)
var _loaded := {}                 # id -> TerrainChunk (finished)
var _loading: TerrainChunk = null
var _queue := PackedStringArray() # ids to load, nearest first
var _unloading: Array = []        # [{"id", "node", "stage"}]
var _missing := {}                # ids without chunk data (reported once)
var _meshes := {}                 # shared mesh path -> Mesh
var _kept := {}                   # props dependencies kept for the level's life (path -> Resource)
var _terrain_material: StandardMaterial3D = null
var _water_material: StandardMaterial3D = null
var _clock := 0.0
var _unloaded_at := {}            # id -> _clock at its last unload
var _work_us := PackedInt64Array()
var _step_us := {}                # step name -> [count, total us, max us]
var _dirty := true


func _enter_tree() -> void:
	add_to_group(GROUP)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


## Reads the level record's world block (`cfg`, merged over DEFAULTS) and the node chunks join
## (`root`'s child "Chunks", made when missing). Deterministic streaming starts on in headless runs
## (and with --deterministic-streaming); tests may set `deterministic` afterwards.
func configure(cfg: Dictionary, root: Node3D) -> void:
	var c := DEFAULTS.duplicate(true)
	c.merge(cfg, true)
	chunk_size = float(c.chunk_size_m)
	var g: Variant = c.grid
	grid = Vector2i(int(g[0]), int(g[1])) if typeof(g) == TYPE_ARRAY and (g as Array).size() == 2 else Vector2i(8, 8)
	var o: Variant = c.origin_m
	origin = Vector3(float(o[0]), float(o[1]), float(o[2])) if typeof(o) == TYPE_ARRAY and (o as Array).size() == 3 \
		else Vector3.ZERO
	load_ring = maxi(0, int(c.load_ring))
	unload_at = maxi(load_ring + 1, int(c.unload_at))
	budget_ms = maxf(0.1, float(c.budget_ms))
	steps_per_frame = maxi(1, int(c.steps_per_frame_headless))
	chunk_dir = str(c.chunk_dir)
	nav_dir = str(c.nav_dir)
	level_root = root
	chunks_parent = root.get_node_or_null("Chunks") as Node3D if root != null else null
	if chunks_parent == null and root != null:
		chunks_parent = Node3D.new()
		chunks_parent.name = "Chunks"
		root.add_child(chunks_parent)
	deterministic = DisplayServer.get_name() == "headless" or OS.get_cmdline_user_args().has(DETERMINISTIC_ARG)
	configured = true
	_dirty = true


# --------------------------------------------------------------------------- the grid

## The chunk cell holding `pos` (may lie outside the grid).
func cell_at(pos: Vector3) -> Vector2i:
	return Vector2i(int(floor((pos.x - origin.x) / chunk_size)), int(floor((pos.z - origin.z) / chunk_size)))


func in_grid(c: Vector2i) -> bool:
	return c.x >= 0 and c.y >= 0 and c.x < grid.x and c.y < grid.y


## The id of the chunk holding `pos` ("" outside the grid).
func chunk_at(pos: Vector3) -> String:
	var c := cell_at(pos)
	return ChunkData.id_for(c) if in_grid(c) else ""


## The world position of a chunk's centre (y 0).
func chunk_center(id: String) -> Vector3:
	var c := ChunkData.coords_for(id)
	return origin + Vector3((c.x + 0.5) * chunk_size, 0.0, (c.y + 0.5) * chunk_size)


## The Chebyshev distance between two cells.
static func chebyshev(a: Vector2i, b: Vector2i) -> int:
	return maxi(absi(a.x - b.x), absi(a.y - b.y))


## The ids of the chunks within `ring` of the cell holding `pos` (in the grid), nearest first.
func ring_ids(pos: Vector3, ring := -1) -> PackedStringArray:
	var r := load_ring if ring < 0 else ring
	var c := cell_at(pos)
	var out: Array = []
	for dz in range(-r, r + 1):
		for dx in range(-r, r + 1):
			var cc := c + Vector2i(dx, dz)
			if in_grid(cc):
				out.append(ChunkData.id_for(cc))
	return _sorted_by_distance(PackedStringArray(out), pos)


func chunk_path(id: String) -> String:
	return chunk_dir.path_join(id + ".res")


# --------------------------------------------------------------------------- state

## Moves the focus (WorldRoot calls it every frame with the player's position).
func focus(pos: Vector3) -> void:
	if not pos.is_finite():
		return
	_focus = pos
	var c := cell_at(pos)
	if c != _focus_cell:
		_focus_cell = c
		_dirty = true


func focus_position() -> Vector3:
	return _focus


## True when the chunk's terrain, ground body, scenery, solids and props are in the tree.
func is_loaded(chunk_id: String) -> bool:
	var n: Variant = _loaded.get(chunk_id)
	return n != null and is_instance_valid(n)


## True when the chunk is loaded and usable (P24b adds: every nav region added and every layer
## map's iteration past that add).
func is_ready(chunk_id: String) -> bool:
	return is_loaded(chunk_id)


## The loaded chunk's node (null when it is not loaded).
func chunk_node(chunk_id: String) -> TerrainChunk:
	var n: Variant = _loaded.get(chunk_id)
	return n as TerrainChunk if n != null and is_instance_valid(n) else null


## The loaded chunk's data (null when it is not loaded).
func chunk_data(chunk_id: String) -> ChunkData:
	var n := chunk_node(chunk_id)
	return n.data if n != null else null


## The data of the loaded chunk holding `pos` (null when that chunk is not loaded).
func data_at(pos: Vector3) -> ChunkData:
	return chunk_data(chunk_at(pos))


## The ids of the loaded chunks, sorted.
func loaded_chunks() -> PackedStringArray:
	var out := PackedStringArray()
	for id: String in _loaded:
		if is_loaded(id):
			out.append(id)
	out.sort()
	return out


## The id of the chunk being loaded ("" when none).
func loading_chunk() -> String:
	return _loading.chunk_id if _loading != null and is_instance_valid(_loading) else ""


## The ids waiting to load, in order.
func queued_chunks() -> PackedStringArray:
	return _queue.duplicate()


## One slice of the starting ring around `pos` behind the loading screen (a larger slice than a
## frame's work). Returns the ring's progress, 0..1.
func load_ring_slice(pos: Vector3) -> float:
	focus(pos)
	update(true)
	return ring_progress(pos)


## The ring around `pos`: 0..1 of its chunks ready (a loading chunk counts by its steps).
func ring_progress(pos: Vector3) -> float:
	var ids := ring_ids(pos)
	if ids.is_empty():
		return 1.0
	var sum := 0.0
	for id in ids:
		if is_ready(id):
			sum += 1.0
		elif _loading != null and is_instance_valid(_loading) and _loading.chunk_id == id:
			sum += _loading.progress()
	return clampf(sum / float(ids.size()), 0.0, 1.0)


## True when every chunk of the ring around `pos` is ready.
func ring_ready(pos: Vector3) -> bool:
	for id in ring_ids(pos):
		if not is_ready(id):
			return false
	return true


## Loads, unloads, thrash, the steps run, the loaded count (now and at most), the queue and the
## work per frame that did work (ms: p50, p99, max).
func stats() -> Dictionary:
	var sorted := _work_us.duplicate()
	sorted.sort()
	var n := sorted.size()
	return {"loads": loads, "unloads": unloads, "thrash": thrash, "steps": steps, "aborted": aborted_loads,
		"loaded": loaded_chunks().size(), "max_loaded": max_loaded, "queue": _queue.size(),
		"loading": loading_chunk(), "work_frames": n,
		"work_ms_p50": snappedf(sorted[int(n * 0.5)] / 1000.0, 0.001) if n > 0 else 0.0,
		"work_ms_p99": snappedf(sorted[int((n - 1) * 0.99)] / 1000.0, 0.001) if n > 0 else 0.0,
		"work_ms_max": snappedf(sorted[n - 1] / 1000.0, 0.001) if n > 0 else 0.0,
		"deterministic": deterministic, "steps_by_kind": step_breakdown()}


## Per step kind: {"n", "total_ms", "max_ms"} (the work's breakdown; the heaviest single steps).
func step_breakdown() -> Dictionary:
	var out := {}
	for k: String in _step_us:
		var row: Array = _step_us[k]
		out[k] = {"n": int(row[0]), "total_ms": snappedf(int(row[1]) / 1000.0, 0.01),
			"max_ms": snappedf(int(row[2]) / 1000.0, 0.01)}
	return out


## Forgets the work samples and the counters (a scenario's measured part starts).
func reset_stats() -> void:
	_work_us = PackedInt64Array()
	_step_us = {}
	loads = 0
	unloads = 0
	thrash = 0
	steps = 0
	aborted_loads = 0
	max_loaded = loaded_chunks().size()
	load_counts = {}


## The streamer's clock (seconds: the sum of its frame deltas).
func clock_s() -> float:
	return _clock


# --------------------------------------------------------------------------- shared resources

## The shared terrain material (vertex colours).
func terrain_material() -> Material:
	if _terrain_material == null:
		_terrain_material = StandardMaterial3D.new()
		_terrain_material.vertex_color_use_as_albedo = true
		_terrain_material.roughness = TERRAIN_ROUGHNESS
	return _terrain_material


func water_material() -> Material:
	if _water_material == null:
		_water_material = StandardMaterial3D.new()
		_water_material.albedo_color = WATER_COLOR
		_water_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_water_material.roughness = 0.2
		_water_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	return _water_material


## A shared scenery mesh by its res:// path (loaded once per streamer; null when missing).
func shared_mesh(path: String) -> Mesh:
	if _meshes.has(path):
		return _meshes[path] as Mesh
	var m: Mesh = null
	if ResourceLoader.exists(path):
		m = load(path) as Mesh
	if m == null:
		push_warning("ChunkStreamer: scenery mesh %s is missing" % path)
	_meshes[path] = m
	return m


## Keeps a props scene's dependency (a building's scene, a script) loaded for the level's life, so a
## chunk that streams in again does not parse it again.
func keep_resource(path: String, res: Resource) -> void:
	if res != null:
		_kept[path] = res


# --------------------------------------------------------------------------- work

func _process(delta: float) -> void:
	_clock += delta
	if configured:
		update()


## One frame's work: the wanted and unwanted chunks are worked out from the focus, then steps run
## until the budget is spent (ring: a loading-screen slice). Returns the steps run.
func update(ring := false) -> int:
	if not configured:
		return 0
	_refresh()
	var quota := steps_per_frame * (RING_SLICE_STEPS_FACTOR if ring else 1)
	var budget_us := int((RING_SLICE_MS if ring else budget_ms) * 1000.0)
	var t0 := Time.get_ticks_usec()
	var n := 0
	while true:
		if deterministic:
			if n >= quota:
				break
		elif n > 0 and Time.get_ticks_usec() - t0 >= budget_us:
			break
		# A heavy step (a props sub-scene's dependency, load or instancing) runs alone in a frame.
		if n > 0 and not ring and _next_is_heavy():
			break
		var s0 := Time.get_ticks_usec()
		var what := _one_step()
		if what == "" or what == "wait":
			break
		var us := Time.get_ticks_usec() - s0
		var row: Array = _step_us.get(what, [0, 0, 0])
		_step_us[what] = [int(row[0]) + 1, int(row[1]) + us, maxi(int(row[2]), us)]
		n += 1
		if not ring and TerrainChunk.HEAVY_STEPS.has(what):
			break
	if n > 0:
		steps += n
		if _work_us.size() < MAX_WORK_SAMPLES:
			_work_us.append(Time.get_ticks_usec() - t0)
	return n


## Works out the queue and the unloads from the focus cell.
func _refresh() -> void:
	if not _dirty or not _focus.is_finite():
		return
	_dirty = false
	var fc := _focus_cell
	# Unloads: loaded chunks at unload_at or more (hysteresis: nothing between load_ring and it).
	var gone: Array = []
	for id: String in _loaded:
		if chebyshev(ChunkData.coords_for(id), fc) >= unload_at:
			gone.append(id)
	gone.sort()
	for id: String in gone:
		_unloading.append({"id": id, "node": _loaded[id], "stage": 0})
		_loaded.erase(id)
	# A load in progress that is already that far is abandoned.
	if _loading != null and is_instance_valid(_loading) \
			and chebyshev(ChunkData.coords_for(_loading.chunk_id), fc) >= unload_at:
		_loading.abort()
		_loading = null
		aborted_loads += 1
	# The queue: the ring's chunks that are neither loaded nor loading, nearest first.
	var wanted: Array = []
	for dz in range(-load_ring, load_ring + 1):
		for dx in range(-load_ring, load_ring + 1):
			var c := fc + Vector2i(dx, dz)
			if not in_grid(c):
				continue
			var id := ChunkData.id_for(c)
			if _loaded.has(id) or _missing.has(id) or (_loading != null and is_instance_valid(_loading) and _loading.chunk_id == id):
				continue
			wanted.append(id)
	_queue = _sorted_by_distance(PackedStringArray(wanted), _focus)


## `ids` sorted by the distance from `pos` to their chunk centres (ties by id).
func _sorted_by_distance(ids: PackedStringArray, pos: Vector3) -> PackedStringArray:
	var rows: Array = []
	for id in ids:
		var c := chunk_center(id)
		rows.append([Vector2(c.x - pos.x, c.z - pos.z).length_squared(), id])
	rows.sort_custom(func(a: Array, b: Array) -> bool:
		return a[0] < b[0] or (a[0] == b[0] and str(a[1]) < str(b[1])))
	var out := PackedStringArray()
	for r: Array in rows:
		out.append(str(r[1]))
	return out


## True when the next step is a heavy one (the loading chunk's, when no unload goes first).
func _next_is_heavy() -> bool:
	if not _unloading.is_empty():
		return false
	return _loading != null and is_instance_valid(_loading) and _loading.next_is_heavy()


## Runs one step: an unload first, else the loading chunk's next step, else the next queued
## chunk's first. "" when there is nothing to do, "wait" while a threaded load is not finished.
func _one_step() -> String:
	if not _unloading.is_empty():
		return _unload_step()
	if _loading == null or not is_instance_valid(_loading):
		_loading = null
		while not _queue.is_empty():
			var id := _queue[0]
			_queue.remove_at(0)
			if not ResourceLoader.exists(chunk_path(id)):
				if not _missing.has(id):
					push_error("ChunkStreamer: no chunk data for %s (%s)" % [id, chunk_path(id)])
				_missing[id] = true
				continue
			_loading = TerrainChunk.new()
			_loading.begin(id, chunk_path(id), self, chunks_parent)
			break
		if _loading == null:
			return ""
	var chunk := _loading
	var what := chunk.step()
	if chunk.done:
		_finish_load(chunk)
		return what if what != "" else "done"
	if chunk.aborted:
		_loading = null
		_missing[chunk.chunk_id] = true
		chunk.abort()
		return "aborted"
	return what


func _finish_load(chunk: TerrainChunk) -> void:
	_loading = null
	var id := chunk.chunk_id
	_loaded[id] = chunk
	loads += 1
	load_counts[id] = int(load_counts.get(id, 0)) + 1
	if _unloaded_at.has(id) and _clock - float(_unloaded_at[id]) < THRASH_WINDOW_S:
		thrash += 1
	max_loaded = maxi(max_loaded, _loaded.size())
	_dirty = true
	chunk_loaded.emit(id)
	Events.world_chunk_loaded.emit(id)


func _unload_step() -> String:
	var u: Dictionary = _unloading[0]
	var id := str(u.id)
	var node: Variant = u.node
	if int(u.stage) == 0:
		u.stage = 1
		chunk_unloading.emit(id)
		Events.world_chunk_unloading.emit(id)
		if node != null and is_instance_valid(node):
			(node as TerrainChunk).free_props()
		return "unload_props"
	_unloading.remove_at(0)
	if node != null and is_instance_valid(node):
		(node as Node).queue_free()
	unloads += 1
	_unloaded_at[id] = _clock
	_dirty = true
	chunk_unloaded.emit(id)
	Events.world_chunk_unloaded.emit(id)
	return "unload"


## The chunk being loaded is not in the tree until its mesh step: it goes with the streamer (a
## level leaving, the game quitting) instead of being left behind.
func _exit_tree() -> void:
	if _loading != null and is_instance_valid(_loading) and not _loading.is_inside_tree():
		_loading.settle()
		_loading.free()
		_loading = null


## Frees every chunk now (tests; a level leaving needs nothing: the chunks are its children).
func clear() -> void:
	for id: String in _loaded:
		var n: Variant = _loaded[id]
		if n != null and is_instance_valid(n):
			(n as Node).queue_free()
	_loaded.clear()
	for u: Dictionary in _unloading:
		if u.node != null and is_instance_valid(u.node):
			(u.node as Node).queue_free()
	_unloading.clear()
	if _loading != null and is_instance_valid(_loading):
		_loading.abort()
	_loading = null
	_queue = PackedStringArray()
	_focus = Vector3.INF
	_focus_cell = Vector2i(-1000000, -1000000)
	_dirty = true
