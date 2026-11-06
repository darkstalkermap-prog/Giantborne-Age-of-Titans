class_name WorldRoot
extends LevelRoot
## The root of a streamed world level (P24a; plan M6-M9 §2.8, decisions 12 and 14): a LevelRoot
## whose ground comes in chunks. Groups world_root and level_root. Children (§2.15): Environment,
## Sun, Streamer (ChunkStreamer), Skyline, Chunks (the loaded TerrainChunks), Navigation (P24b),
## Spawned, Player, EncounterDirector, DebrisPool.
##
## At _ready it reads the level record's `world` block (merged over ChunkStreamer.DEFAULTS),
## configures the streamer, the skyline (its meshes from world.skyline / skyline_landmarks) and the
## depth fog (world.fog_m from / to, world.fog_max its density), then LevelRoot's _ready (lookups,
## the render preset - with P24a's camera far plane and terrain visibility - and the runtime nodes).
## Every frame it focuses the streamer on the player, keeps the skyline's mask of the chunks that are
## loaded and drawn (their terrain AABB centre within terrain_visibility_end_m of the camera: the
## renderer's own visibility-range test) and follows the region the player stands in:
## Events.region_changed(tick, region, previous) once the player is REGION_HYSTERESIS_M inside a new
## region (the first region is announced at once, previous "").
##
## Lookups for the loaded ground: height_at() (the triangles the giant stands on), surface_at()
## (soft / hard / wet), water_at() (a water surface height), all NaN or "" where no chunk is
## loaded; region_at() from the world index's region grid (any distance). is_ready() / loading_
## progress(): the starting ring around the player (main.gd's loading screen and GameSession's
## level_entered wait for it).

const WORLD_GROUP := "world_root"
const REGION_HYSTERESIS_M := 15.0
## The skyline mask is worked out again when the camera moved this far (or the loaded set changed).
const MASK_MOVE_M := 4.0

var streamer: ChunkStreamer = null
var skyline: Skyline = null
## The record's world block merged over ChunkStreamer.DEFAULTS.
var world: Dictionary = {}
## The region the player stands in (hysteresis applied); "" before the first.
var region_id := ""
## Region changes seen (tests, debug): [{"tick", "region", "previous"}].
var region_log: Array = []

var _region_started := false
var _mask_camera := Vector3.INF
var _mask_loaded := -1


func _enter_tree() -> void:
	super()
	add_to_group(WORLD_GROUP)


func _ready() -> void:
	world = world_settings()
	streamer = get_node_or_null("Streamer") as ChunkStreamer
	if streamer == null:
		streamer = ChunkStreamer.new()
		streamer.name = "Streamer"
		add_child(streamer)
	streamer.configure(world, self)
	var idx := index()
	if idx != null:
		streamer.region_ids = idx.region_ids
	skyline = get_node_or_null("Skyline") as Skyline
	if skyline != null:
		skyline.setup(_load_mesh(str(world.get("skyline", ""))), _load_mesh(str(world.get("skyline_landmarks", ""))),
			streamer.grid, Vector2(streamer.origin.x, streamer.origin.z), streamer.chunk_size)
	_apply_fog()
	super()
	streamer.chunk_loaded.connect(_on_chunk_changed)
	streamer.chunk_unloaded.connect(_on_chunk_changed)


## The level record's world block, merged over ChunkStreamer.DEFAULTS.
func world_settings() -> Dictionary:
	var out := ChunkStreamer.DEFAULTS.duplicate(true)
	var w: Variant = level_record().get("world")
	if typeof(w) == TYPE_DICTIONARY:
		out.merge(w, true)
	return out


func _load_mesh(path: String) -> Mesh:
	if path == "" or not ResourceLoader.exists(path):
		return null
	return load(path) as Mesh


## The depth fog of the world block: from fog_m[0] to fog_m[1] metres, at most fog_max.
func _apply_fog() -> void:
	var we := get_node_or_null("Environment") as WorldEnvironment
	var fog: Variant = world.get("fog_m")
	if we == null or we.environment == null or typeof(fog) != TYPE_ARRAY or (fog as Array).size() != 2:
		return
	var env := we.environment
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_DEPTH
	env.fog_depth_begin = float(fog[0])
	env.fog_depth_end = float(fog[1])
	env.fog_density = clampf(float(world.get("fog_max", 1.0)), 0.0, 1.0)


## LevelRoot's render preset (P24a's terrain visibility and camera far plane included), and the
## streamer told the preset's distances, so chunks made later get them too.
func apply_graphics() -> Dictionary:
	var out := super()
	if streamer != null:
		streamer.terrain_visibility_end_m = float(out.get("terrain_visibility_end_m", 0.0))
		streamer.scenery_visibility_end_m = float(out.get("scenery_visibility_end_m", 0.0))
	_mask_loaded = -1
	return out


func _process(_delta: float) -> void:
	var p := player()
	if p != null:
		streamer.focus(p.global_position)
		update_region(p.global_position)
	update_mask()


# --------------------------------------------------------------------------- loading

## Where the starting ring is loaded: the player, else the start checkpoint of the index, else the
## world's centre.
func ring_center() -> Vector3:
	var p := player()
	if p != null:
		return p.global_position
	var idx := index()
	var start := str(level_record().get("start_checkpoint", ""))
	if idx != null and start != "":
		var pos := idx.position_of(start)
		if pos.is_finite():
			return pos
	return streamer.origin + Vector3(streamer.grid.x, 0.0, streamer.grid.y) * streamer.chunk_size * 0.5


## True when the ring around the player (or the respawn point) is ready.
func is_ready() -> bool:
	return streamer != null and streamer.ring_ready(ring_center())


## One loading-screen slice of the starting ring; its progress 0..1.
func loading_progress() -> float:
	if streamer == null:
		return 1.0
	return streamer.load_ring_slice(ring_center())


# --------------------------------------------------------------------------- lookups

## The id of the chunk holding `pos` ("" outside the world).
func chunk_at(pos: Vector3) -> String:
	return streamer.chunk_at(pos) if streamer != null else ""


## The loaded ChunkData under `pos` (null when that chunk is not loaded).
func chunk_data_at(pos: Vector3) -> ChunkData:
	return streamer.data_at(pos) if streamer != null else null


## The ground height under `pos` on the triangles the giant stands on; NaN where no chunk is loaded.
func height_at(pos: Vector3) -> float:
	var d := chunk_data_at(pos)
	if d == null:
		return NAN
	return d.ground_at_local(pos.x - d.origin.x, pos.z - d.origin.z)


## "soft", "hard" or "wet" under `pos`; "" where no chunk is loaded.
func surface_at(pos: Vector3) -> String:
	var d := chunk_data_at(pos)
	if d == null:
		return ""
	return d.surface_name_at_local(pos.x - d.origin.x, pos.z - d.origin.z)


## The water surface height over `pos`, or NaN where there is none (or no chunk is loaded).
func water_at(pos: Vector3) -> float:
	var d := chunk_data_at(pos)
	if d == null:
		return NAN
	return d.water_at_local(pos.x - d.origin.x, pos.z - d.origin.z)


## The region at `pos`: the world index's region grid; without one, the loaded chunk's region
## cells; "" outside every region.
func region_at(pos: Vector3) -> String:
	var idx := index()
	if idx != null and idx.grid_size.x > 0:
		return idx.region_at(pos)
	var d := chunk_data_at(pos)
	if d == null:
		return ""
	var k := d.region_index_at_local(pos.x - d.origin.x, pos.z - d.origin.z)
	return streamer.region_ids[k - 1] if k > 0 and k <= streamer.region_ids.size() else ""


## The region the player is taken to stand in at `pos` (15 m hysteresis): a new region counts once
## `pos` is REGION_HYSTERESIS_M inside it (the four points that far around it are in it too).
## Emits Events.region_changed when it changes.
func update_region(pos: Vector3) -> void:
	var r := region_at(pos)
	if not _region_started:
		_region_started = true
		_set_region(r)
		return
	if r == region_id:
		return
	for off: Vector3 in [Vector3(REGION_HYSTERESIS_M, 0, 0), Vector3(-REGION_HYSTERESIS_M, 0, 0),
			Vector3(0, 0, REGION_HYSTERESIS_M), Vector3(0, 0, -REGION_HYSTERESIS_M)]:
		if region_at(pos + off) != r:
			return
	_set_region(r)


func _set_region(r: String) -> void:
	var previous := region_id
	region_id = r
	if r == previous and previous != "":
		return
	if r == "" and previous == "":
		return
	region_log.append({"tick": Sim.tick, "region": r, "previous": previous})
	Events.region_changed.emit(Sim.tick, r, previous)


# --------------------------------------------------------------------------- the skyline mask

## The camera the mask is worked out for (the viewport's, else the player's position).
func _view_position() -> Vector3:
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	if cam != null:
		return cam.global_position
	var p := player()
	return p.global_position if p != null else Vector3.INF


## One byte per chunk: 1 when it is loaded and its terrain is drawn from `view` (the AABB centre
## within the preset's terrain_visibility_end_m; 0 = every loaded chunk is drawn).
func drawn_mask(view: Vector3) -> PackedByteArray:
	var out := PackedByteArray()
	if streamer == null:
		return out
	out.resize(streamer.grid.x * streamer.grid.y)
	var limit := streamer.terrain_visibility_end_m
	for id in streamer.loaded_chunks():
		var c := ChunkData.coords_for(id)
		if not streamer.in_grid(c):
			continue
		var node := streamer.chunk_node(id)
		if node == null or node.terrain == null:
			continue
		if limit > 0.0 and view.is_finite() and node.aabb_center.is_finite() and view.distance_to(node.aabb_center) > limit:
			continue
		out[c.y * streamer.grid.x + c.x] = 1
	return out


## Updates the skyline's mask when the camera moved MASK_MOVE_M or the loaded set changed (`force`:
## now). Returns true when the mask changed.
func update_mask(force := false) -> bool:
	if skyline == null or streamer == null:
		return false
	var view := _view_position()
	var moved := not _mask_camera.is_finite() or not view.is_finite() or view.distance_to(_mask_camera) > MASK_MOVE_M
	if not force and not moved and _mask_loaded == streamer.loads + streamer.unloads:
		return false
	_mask_camera = view
	_mask_loaded = streamer.loads + streamer.unloads
	return skyline.set_mask(drawn_mask(view))


func _on_chunk_changed(_chunk_id: String) -> void:
	_mask_loaded = -1
