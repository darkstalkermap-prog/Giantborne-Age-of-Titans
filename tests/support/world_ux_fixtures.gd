class_name WorldUxFixtures
extends RefCounted
## A small stub level for P27's tests (plan M6-M9 §3.10: "built on stub indexes and widgets, no
## level loads"): a level record with a 4 x 4 chunk grid of 100 m from (-200, -200), two regions
## (north z < 0, south z >= 0), seven POIs and a world index (checkpoints, an exit, the region grid,
## the map bounds) put in WorldIndex's cache. Records go through TestFixtures (restored after each
## test), the index through WorldIndex.put_cached (cleared after each test).
##
##   poi.test_p27_town     settlement (0, -100)  r 30  xp 40  north
##   poi.test_p27_vista    vista      (100, 100) r 20  xp 30  reveals 150 m (the ruin; not the far one)
##   poi.test_p27_ruin     ruin       (150, 0)   r 20  xp 25  (111 m from the vista)
##   poi.test_p27_far      landmark   (-180, -180) r 20 xp 10 skyline
##   poi.test_p27_seal     secret     (-100, 100) r 15  xp 20  min_stage 5, seal test.p27.rockfall
##   poi.test_p27_high     ruin       (100, -100) r 20  xp 15  min_stage 5
##   poi.test_p27_shrine   shrine     (-100, -50) r 25  xp 0   (its shrine checkpoint stands inside it)
##   checkpoints: test.p27.cp_start (waystone, (0, 150)), test.p27.cp_far (waystone, (150, -150)),
##                test.p27.cp_narrow (waystone, (-150, 150), max_stage 2), test.p27.cp_gated
##                (waystone, (50, 50), requires test.p27.gate_open), test.p27.shrine (shrine, (-100, -50))
##   exit: test.p27.exit (190, 0)

const LEVEL := "level.test_p27"
const STAND_IN := "res://scenes/test/flow_test_level.tscn"
const NORTH := "region.test_p27_north"
const SOUTH := "region.test_p27_south"
const POIS := {
	"poi.test_p27_town": ["settlement", Vector3(0, 0, -100), 30, 40, 0, 0, false, NORTH],
	"poi.test_p27_vista": ["vista", Vector3(100, 0, 100), 20, 30, 0, 150, false, SOUTH],
	"poi.test_p27_ruin": ["ruin", Vector3(150, 0, 0), 20, 25, 0, 0, false, SOUTH],
	"poi.test_p27_far": ["landmark", Vector3(-180, 0, -180), 20, 10, 0, 0, true, NORTH],
	"poi.test_p27_seal": ["secret", Vector3(-100, 0, 100), 15, 20, 5, 0, false, SOUTH],
	"poi.test_p27_high": ["ruin", Vector3(100, 0, -100), 20, 15, 5, 0, false, NORTH],
	"poi.test_p27_shrine": ["shrine", Vector3(-100, 0, -50), 25, 0, 0, 0, false, NORTH],
}
const SEAL := "test.p27.rockfall"


## Installs the level, region and POI records and caches the index. Returns the index.
static func install(level_id := LEVEL) -> WorldIndex:
	TestFixtures.record_override(level_id, {"schema_version": 1, "id": level_id, "type": "level",
		"display_name": "The Test March", "scene": STAND_IN, "start_checkpoint": "test.p27.cp_start",
		"world": {"chunk_size_m": 100, "grid": [4, 4], "origin_m": [-200, 0, -200]}})
	TestFixtures.record_override(NORTH, {"schema_version": 1, "id": NORTH, "type": "region",
		"display_name": "The North Test", "level": level_id, "bounds_m": [[-200, -200], [200, 0]],
		"recommended_stage": [4, 5], "discover_xp": 25, "m7_note": "The north comes later."})
	TestFixtures.record_override(SOUTH, {"schema_version": 1, "id": SOUTH, "type": "region",
		"display_name": "The South Test", "level": level_id, "bounds_m": [[-200, 0], [200, 200]],
		"recommended_stage": [1, 3], "discover_xp": 0})
	for id: String in POIS:
		var p: Array = POIS[id]
		var pos: Vector3 = p[1]
		var rec := {"schema_version": 1, "id": id, "type": "poi", "display_name": id.trim_prefix("poi.test_p27_").capitalize(),
			"level": level_id, "region": p[7], "kind": p[0], "position_m": [pos.x, pos.y, pos.z],
			"radius_m": p[2], "xp": p[3], "min_stage": p[4], "reveals_m": p[5], "skyline": p[6],
			"compass": p[0] != "secret", "map_icon": p[0]}
		if p[0] == "secret":
			rec["seal"] = SEAL
		TestFixtures.record_override(id, rec)
	var idx := index(level_id)
	WorldIndex.put_cached(level_id, idx)
	return idx


## The stub level's index.
static func index(level_id := LEVEL) -> WorldIndex:
	var idx := WorldIndex.new()
	idx.level_id = level_id
	idx.checkpoints = {
		"test.p27.cp_start": _cp(Vector3(0, 0, 150), "Start stone", "waystone"),
		"test.p27.cp_far": _cp(Vector3(150, 0, -150), "Far stone", "waystone"),
		"test.p27.cp_narrow": _cp(Vector3(-150, 0, 150), "Narrow stair", "waystone", 2),
		"test.p27.cp_gated": _cp(Vector3(50, 0, 50), "Gated stone", "waystone", WorldIndex.ANY_STAGE,
			PackedStringArray(["test.p27.gate_open"])),
		"test.p27.shrine": _cp(Vector3(-100, 0, -50), "Test Shrine", "shrine"),
	}
	idx.exits = {"test.p27.exit": {"position": Vector3(190, 0, 0), "to_level": "level.valley",
		"to_checkpoint": "valley.cp.kings_door", "display_name": "The test door"}}
	idx.grid_origin = Vector2(-200, -200)
	idx.cell_m = 100.0
	idx.grid_size = Vector2i(4, 4)
	idx.region_ids = PackedStringArray([NORTH, SOUTH])
	var grid := PackedByteArray()
	for z in 4:
		for x in 4:
			grid.append(1 if z < 2 else 2)
	idx.region_grid = grid
	idx.map_bounds = Rect2(-200, -200, 400, 400)
	return idx


static func _cp(pos: Vector3, title: String, kind: String, max_stage := WorldIndex.ANY_STAGE,
		flags := PackedStringArray()) -> Dictionary:
	return {"position": pos, "yaw": 0.0, "display_name": title, "kind": kind, "chunk": "", "fast_travel": true,
		"requires_flags": flags, "region": "", "district": "", "max_stage": max_stage}


## A Discovery node for the stub level, added under `parent`.
static func discovery(parent: Node, level_id := LEVEL) -> Discovery:
	var d := Discovery.new()
	d.level_id = level_id
	parent.add_child(d)
	return d
