class_name TinyWorld
extends RefCounted
## A tiny streamed world for P24a's tests (written once per process under user://): a grid of
## 64 m chunks at 4 m spacing (17 inner samples, 19 with the apron) on a smooth slope, each with a
## few solids and one scenery key, so a whole ring loads in a handful of steps. config() is its world
## block; install_record() adds a level record for it (TestFixtures: undone after the test);
## make_root() builds a WorldRoot over it (optionally with the giant).
##
## The heights: height(x, z) = 2 + 0.05 x + 1.5 sin(z / 10) (world metres) - every chunk shares its
## border samples with its neighbours.

const DIR := "user://p24a_tiny_world"
const LEVEL_ID := "level.p24a_tiny_world"
const CHUNK_M := 64.0
const SPACING := 4.0
const MESH_PATH := "user://p24a_tiny_world/box.res"
const GIANT := "res://scenes/player/giant.tscn"

static var _written := {}   # grid key -> true


static func height(x: float, z: float) -> float:
	return 2.0 + 0.05 * x + 1.5 * sin(z / 10.0)


## The world block of a tiny world of `grid` chunks centred on the origin.
static func config(grid: Vector2i) -> Dictionary:
	return {"chunk_size_m": CHUNK_M, "grid": [grid.x, grid.y], "origin_m": [-grid.x * CHUNK_M * 0.5, 0.0, -grid.y * CHUNK_M * 0.5],
		"height_spacing_m": SPACING, "load_ring": 1, "unload_at": 3, "budget_ms": 4.0, "steps_per_frame_headless": 6,
		"chunk_dir": chunk_dir(grid), "nav_dir": "", "fog_m": [400, 1800], "fog_max": 0.85}


static func chunk_dir(grid: Vector2i) -> String:
	return DIR.path_join("g%dx%d" % [grid.x, grid.y])


## Writes the chunks of a `grid` world (once per process) and returns its config.
static func write(grid: Vector2i) -> Dictionary:
	var cfg := config(grid)
	var key := "%dx%d" % [grid.x, grid.y]
	if _written.has(key) and ResourceLoader.exists(chunk_dir(grid).path_join("c0_0.res")):
		return cfg
	DirAccess.make_dir_recursive_absolute(chunk_dir(grid))
	if not ResourceLoader.exists(MESH_PATH):
		var bm := BoxMesh.new()
		ResourceSaver.save(bm, MESH_PATH)
	var origin := Vector3(float(cfg.origin_m[0]), 0.0, float(cfg.origin_m[2]))
	var cells := int(CHUNK_M / SPACING)
	var field := HeightField.make(Vector2(origin.x - SPACING, origin.z - SPACING), SPACING,
		Vector2i(grid.x * cells + 3, grid.y * cells + 3))
	field.fill(height)
	for cz in grid.y:
		for cx in grid.x:
			var d := ChunkWriter.chunk_from_field(field, Vector2i(cx, cz), CHUNK_M, origin, Vector2i(1, 1))
			d.surface_cells = ChunkWriter.cells(d, ChunkData.SURFACE_CELLS, func(x: float, _z: float) -> int:
				return ChunkData.SURFACE_HARD if x > 0.0 else ChunkData.SURFACE_SOFT)
			d.region_cells = ChunkWriter.cells(d, ChunkData.REGION_CELLS, func(x: float, _z: float) -> int:
				return 1 if x < 0.0 else 2)
			for k in 3:
				var p := Vector3(8.0 + 20.0 * k, 0.0, 12.0 + 16.0 * k)
				p.y = height(d.origin.x + p.x, d.origin.z + p.z) + 1.0
				ChunkWriter.add_solid(d.solids, k % 2 == 1, p, Vector3(1.0, 2.0, 1.0))
			d.scenery[MESH_PATH] = ChunkWriter.xform_buffer([Transform3D(Basis(), Vector3(32.0, height(d.origin.x + 32.0, d.origin.z + 32.0), 32.0))])
			if cx == 0 and cz == 0:
				ChunkWriter.add_water(d.water, Rect2(4.0, 4.0, 20.0, 20.0), 50.0)
			ChunkWriter.save(d, chunk_dir(grid).path_join(d.chunk_id + ".res"))
	_written[key] = true
	return cfg


## A level record for the tiny world (TestFixtures override, undone after the test).
static func install_record(grid: Vector2i, extra := {}) -> void:
	var rec := {"schema_version": 1, "type": "level", "display_name": "Tiny world", "scene": "",
		"start_checkpoint": "", "world": config(grid),
		"render": {"low": {"terrain_visibility_end_m": 700, "camera_far_m": 2400, "scenery_visibility_end_m": 220},
			"medium": {"terrain_visibility_end_m": 700, "camera_far_m": 2400, "scenery_visibility_end_m": 300}}}
	TestFixtures.deep_merge(rec, extra)
	TestFixtures.record_override(LEVEL_ID, rec)


## A WorldRoot over the tiny world (not in the tree): its Streamer, Chunks and, with `giant`, the
## giant at `at` (in the tree its _ready loads nothing until the streamer runs).
static func make_root(giant := false, at := Vector3.ZERO) -> WorldRoot:
	var root := WorldRoot.new()
	root.name = "TinyWorld"
	root.level_id = LEVEL_ID
	var streamer := ChunkStreamer.new()
	streamer.name = "Streamer"
	root.add_child(streamer)
	var chunks := Node3D.new()
	chunks.name = "Chunks"
	root.add_child(chunks)
	if giant:
		var p := (load(GIANT) as PackedScene).instantiate() as Node3D
		p.name = "Player"
		p.position = at
		root.add_child(p)
	return root
