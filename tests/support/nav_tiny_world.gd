class_name NavTinyWorld
extends RefCounted
## P24b's tests: a tiny streamed world of three 64 m chunks in a row (c0_0, c1_0, c2_0; x from -96 to
## 96 m, z from -32 to 32 m) on flat ground with hand-made navmeshes - quads, no bake - so a test
## streams it in a few steps and knows every polygon. Written once per process under user://.
##
## Every chunk has a navmesh per layer (human 1, large 2, titan 16; each with its layer's cell size
## and height, as NavBake.LAYERS):
##   c0_0   one quad over the chunk;
##   c1_0   the ford: x in FORD (local 24..40 m) is deep water - the human and large meshes leave it
##          out, the titan mesh keeps the strips either side and the ford itself is a separate
##          gate-4 navmesh (bit 32), sharing its border vertices with them;
##   c2_0   the wall: every layer's mesh is a north quad (z local 0..28) and a south quad (36..64);
##          a fortified gate (a props sub-scene) stands in the gap at local (32, 0, 32) with one
##          closed NavLink per layer through it (NavLinkHuman, NavLinkLarge, NavLinkTitan).
## c0_0 and c1_0 meet along x = -32 on every layer (the same edge in both meshes).

const DIR := "user://p24b_nav_tiny_world"
const LEVEL_ID := "level.p24b_nav_tiny_world"
const CHUNK_M := 64.0
const SPACING := 4.0
const GRID := Vector2i(3, 1)
const ORIGIN := Vector3(-96.0, 0.0, -32.0)
const FORD := Vector2(24.0, 40.0)
const WALL := Vector2(28.0, 36.0)
const GATE_LOCAL := Vector3(32.0, 0.0, 32.0)
const GATE_SCENE := "res://scenes/world/gate_fortified.tscn"
const GATE_WORLD_ID := "p24b_nav_tiny_world.gate"
## The navmeshes' height over the flat ground (y 0).
const NAV_Y := 0.1

static var _written := false


## The world block of the tiny nav world.
static func config() -> Dictionary:
	return {"chunk_size_m": CHUNK_M, "grid": [GRID.x, GRID.y], "origin_m": [ORIGIN.x, ORIGIN.y, ORIGIN.z],
		"height_spacing_m": SPACING, "load_ring": 1, "unload_at": 3, "budget_ms": 4.0, "steps_per_frame_headless": 6,
		"chunk_dir": DIR, "nav_dir": DIR, "nav_layers": [1, 2, 16], "gate_bits": {"4": 32, "5": 64, "6": 128},
		"fog_m": [400, 1800], "fog_max": 0.85}


## The world position of chunk-local point `local` of chunk (x, 0).
static func at(chunk_x: int, local: Vector3) -> Vector3:
	return ORIGIN + Vector3(chunk_x * CHUNK_M, 0.0, 0.0) + local


## Writes the chunks, their navmeshes and the gate part (once per process); returns the config.
static func write() -> Dictionary:
	var cfg := config()
	if _written and ResourceLoader.exists(DIR.path_join("c2_0.res")):
		return cfg
	DirAccess.make_dir_recursive_absolute(DIR)
	var cells := int(CHUNK_M / SPACING)
	var field := HeightField.make(Vector2(ORIGIN.x - SPACING, ORIGIN.z - SPACING), SPACING,
		Vector2i(GRID.x * cells + 3, GRID.y * cells + 3), 0.0)
	for cx in GRID.x:
		var d := ChunkWriter.chunk_from_field(field, Vector2i(cx, 0), CHUNK_M, ORIGIN, Vector2i(1, 1))
		d.surface_cells = ChunkWriter.cells(d, ChunkData.SURFACE_CELLS, func(_x: float, _z: float) -> int:
			return ChunkData.SURFACE_SOFT)
		var meshes := {}
		for spec: Dictionary in NavBake.LAYERS:
			var bit := int(spec.layer)
			match cx:
				0:
					meshes[bit] = quads(spec, [Rect2(0.0, 0.0, CHUNK_M, CHUNK_M)])
				1:
					var west := Rect2(0.0, 0.0, FORD.x, CHUNK_M)
					var east := Rect2(FORD.y, 0.0, CHUNK_M - FORD.y, CHUNK_M)
					meshes[bit] = quads(spec, [west, east])
					if bit == NavBake.TITAN_LAYER:
						meshes[32] = quads(spec, [Rect2(FORD.x, 0.0, FORD.y - FORD.x, CHUNK_M)])
				2:
					meshes[bit] = quads(spec, [Rect2(0.0, 0.0, CHUNK_M, WALL.x), Rect2(0.0, WALL.y, CHUNK_M, CHUNK_M - WALL.y)])
		for bit: int in meshes:
			var path := NavBake.nav_path(DIR, d.chunk_id, bit)
			ResourceSaver.save(meshes[bit], path)
			d.nav[bit] = path
		if cx == 2:
			d.props_scenes.append(_save_gate_part(d.coords))
		ChunkWriter.save(d, DIR.path_join(d.chunk_id + ".res"))
	_written = true
	return cfg


## A NavigationMesh of `spec`'s settings made of one quad per rectangle (chunk-local x, z) at NAV_Y,
## wound as Recast winds its polygons; neighbouring rectangles share their corner vertices.
static func quads(spec: Dictionary, rects: Array) -> NavigationMesh:
	var nm := NavBake.new_mesh(spec)
	var verts := PackedVector3Array()
	var index := {}
	for r: Rect2 in rects:
		var poly := PackedInt32Array()
		for p: Vector2 in [r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]:
			if not index.has(p):
				index[p] = verts.size()
				verts.append(Vector3(p.x, NAV_Y, p.y))
			poly.append(int(index[p]))
		nm.add_polygon(poly)
	nm.set_vertices(verts)
	return nm


## The gate's props part (Chunk_2_0_0 with Props/Gate and its three links), saved under DIR.
static func _save_gate_part(c: Vector2i) -> String:
	var gate := (load(GATE_SCENE) as PackedScene).instantiate() as Node3D
	gate.name = "Gate"
	gate.set("world_id", GATE_WORLD_ID)
	gate.position = GATE_LOCAL
	var links: Array[Node] = []
	for spec: Dictionary in NavBake.LAYERS:
		var link := NavigationLink3D.new()
		link.name = "NavLink" + str(spec.name).capitalize()
		link.start_position = Vector3(0.0, NAV_Y, 6.0)
		link.end_position = Vector3(0.0, NAV_Y, -6.0)
		link.bidirectional = true
		link.navigation_layers = int(spec.layer)
		link.enabled = false
		gate.add_child(link)
		links.append(link)
	var root := ChunkWriter.part_scene(c, 0, [{"node": gate, "container": "Props"}])
	for n in root.get_children():
		n.owner = root
	gate.owner = root
	for link in links:
		link.owner = root
	var packed := PackedScene.new()
	packed.pack(root)
	root.free()
	var path := DIR.path_join("c%d_%d_0.tscn" % [c.x, c.y])
	ResourceSaver.save(packed, path)
	return path


## A level record for the tiny nav world (TestFixtures override, undone after the test), with the
## world's nav_query settings unless `nav_query` is false.
static func install_record(nav_query := true, extra := {}) -> void:
	var rec := {"schema_version": 1, "type": "level", "display_name": "Tiny nav world", "scene": "",
		"start_checkpoint": "", "world": config(), "player_nav_fallback": 16,
		"render": {"low": {"terrain_visibility_end_m": 700, "camera_far_m": 2400, "scenery_visibility_end_m": 220}}}
	if nav_query:
		rec["nav_query"] = {"max_polygons": 0, "chase_distance_m": 120, "far_distance_m": 300, "repath_min_ticks": 6,
			"repath_min_move_m": 2.0, "queries_per_tick": 8}
	TestFixtures.deep_merge(rec, extra)
	TestFixtures.record_override(LEVEL_ID, rec)


## A WorldRoot over the tiny nav world (not in the tree): Streamer and Chunks.
static func make_root() -> WorldRoot:
	var root := WorldRoot.new()
	root.name = "NavTinyWorld"
	root.level_id = LEVEL_ID
	var streamer := ChunkStreamer.new()
	streamer.name = "Streamer"
	root.add_child(streamer)
	var chunks := Node3D.new()
	chunks.name = "Chunks"
	root.add_child(chunks)
	return root
