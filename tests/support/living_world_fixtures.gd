class_name LivingWorldFixtures
extends RefCounted
## P37's tiny living world for the default-tier tests (tests/integration/test_wander_director.gd,
## test_world_events.gd and test_event_streaming.gd): TinyWorld's 4 x 4 grid of 64 m chunks (256 m
## square: the ring of chunks around the giant streams in a few deterministic slices), a world index of
## its own (a road along z = 0 with a node every 16 m, one region over the whole grid, markers and two
## checkpoints), an EncounterDirector and a WanderDirector under the WorldRoot, and test records: a
## template of two soldiers (their AI off: they stand where they come), a wander table of the region and
## two world events of the level - a raid (its centre at the west end, a protect objective over two
## props; it waits for the flag p37.raid.on) and a column marching the road from the west end to the east
## end and back (it waits for p37.column.on). Records go through
## TestFixtures (undone after each test), the index through WorldIndex.put_cached (cleared after each
## test); call reset() in after_each for the WanderDirector's statics.
##
## Ground: the giant at x = -96, z = 16 stands in chunk c0_2, so the ring loads x in [-128, 0) and z in
## [-64, 128): road nodes west of x = 0 are on loaded ground, the rest are not.

const GRID := Vector2i(4, 4)
const LEVEL := TinyWorld.LEVEL_ID
const REGION := "region.p37_tiny"
const TABLE := "wander.p37_tiny"
const PACK := "encounter.p37_tpl_pack"
const RAIDERS := "encounter.p37_tpl_raiders"
const MARCHERS := "encounter.p37_tpl_column"
const RAID := "event.p37_raid"
const COLUMN := "event.p37_column"
const NEAR_CP := "p37.cp.west"
const FAR_CP := "p37.cp.east"
const ROAD_STEP_M := 16.0
## Where the giant stands by default (chunk c0_2).
const GIANT_AT := Vector3(-96.0, 0.0, 16.0)


static func height(x: float, z: float) -> float:
	return TinyWorld.height(x, z)


static func ground(x: float, z: float) -> Vector3:
	return Vector3(x, height(x, z), z)


## The tiny world's index: the road, the region grid, two markers (the road's ends) and two checkpoints.
static func make_index() -> WorldIndex:
	var idx := WorldIndex.new()
	idx.level_id = LEVEL
	var nodes := PackedVector3Array()
	var edges := PackedInt32Array()
	var x := -112.0
	while x <= 112.0:
		if not nodes.is_empty():
			edges.append(nodes.size() - 1)
			edges.append(nodes.size())
		nodes.append(ground(x, 0.0))
		x += ROAD_STEP_M
	idx.roads = {"nodes": nodes, "edges": edges, "widths": PackedFloat32Array(), "min_stage": PackedByteArray(),
		"max_stage": PackedByteArray(), "direct": PackedByteArray()}
	idx.grid_origin = Vector2(-128.0, -128.0)
	idx.cell_m = 64.0
	idx.grid_size = GRID
	var grid := PackedByteArray()
	grid.resize(GRID.x * GRID.y)
	grid.fill(1)
	idx.region_grid = grid
	idx.region_ids = PackedStringArray([REGION])
	idx.markers = {"p37.marker.west": {"position": ground(-112.0, 0.0), "kind": "objective", "chunk": "c0_2"},
		"p37.marker.east": {"position": ground(112.0, 0.0), "kind": "objective", "chunk": "c3_2"}}
	idx.checkpoints = {NEAR_CP: {"position": ground(-100.0, 30.0), "yaw": 0.0, "display_name": "West stone", "kind": "waystone",
			"chunk": "c0_2", "fast_travel": true, "requires_flags": PackedStringArray(), "region": REGION, "district": "", "max_stage": 10},
		FAR_CP: {"position": ground(100.0, 100.0), "yaw": 0.0, "display_name": "East stone", "kind": "waystone",
			"chunk": "c3_3", "fast_travel": true, "requires_flags": PackedStringArray(), "region": REGION, "district": "", "max_stage": 10}}
	return idx


## Installs the records and the index (call before make_root()). `extra` overrides records by id.
static func install(extra := {}) -> void:
	TinyWorld.write(GRID)
	TinyWorld.install_record(GRID, {"regions": [REGION], "max_active_enemies": 12})
	WorldIndex.put_cached(LEVEL, make_index())
	var recs := {
		REGION: {"schema_version": 1, "id": REGION, "type": "region", "level": LEVEL, "display_name": "Tiny"},
		PACK: _template(PACK, [-112.0, 0.0, 0.0], [["p37.pack_a", -2.0, 0.0, ""], ["p37.pack_b", 2.0, 0.0, ""]], 40.0),
		RAIDERS: _template(RAIDERS, [-104.0, 0.0, -8.0], [["p37.raider_a", -2.0, 0.0, ""], ["p37.raider_b", 2.0, 0.0, ""]], 40.0),
		MARCHERS: _template(MARCHERS, [-112.0, 0.0, 0.0], [["p37.marcher_a", -2.0, 0.0, ""], ["p37.marcher_b", 2.0, 0.0, ""]], 40.0),
		TABLE: {"schema_version": 1, "id": TABLE, "type": "wander_table", "region": REGION, "max_active": 2,
			"interval_s": [60, 120], "min_distance_m": 40, "max_distance_m": 120, "anchors": "roads", "xp_full_spawns": 3, "patrol_m": 20,
			"entries": [{"id": "pack", "weight": 1, "min_stage": 1, "max_stage": 10, "template": PACK}]},
		RAID: {"schema_version": 1, "id": RAID, "type": "world_event", "display_name": "Tiny raid", "level": LEVEL,
			"centre_m": [-104.0, 0.0, -8.0], "start_radius_m": 200,
			"trigger": {"min_stage": 1, "max_stage": 10, "requires_flags": ["p37.raid.on"], "cooldown_s": 600, "max_runs": 2},
			"encounters": [RAIDERS],
			"objective": {"kind": "protect", "targets": ["p37.prop_a", "p37.prop_b"], "lost_to_fail": 2,
				"text": "Hold: {standing} of {total} stand"},
			"fail": {"timer_s": 0}, "success_outcome": "defended", "fail_outcome": "fell", "start_text": "Raid!",
			"respawn_text": "The raid goes on there.", "abandon_after_s": 20,
			"outcomes": {"defended": {"set_flags": {"p37.tiny.defended": true}, "xp": 100, "text": "Saved."},
				"fell": {"set_flags": {"p37.tiny.fell": true}, "burn": 1, "text": "Lost."}}},
		COLUMN: {"schema_version": 1, "id": COLUMN, "type": "world_event", "display_name": "Tiny column", "level": LEVEL,
			"centre_m": [-112.0, 0.0, 0.0], "start_radius_m": 200,
			"trigger": {"min_stage": 1, "max_stage": 10, "requires_flags": ["p37.column.on"], "cooldown_s": 900, "cooldown_from": "start"},
			"encounters": [MARCHERS],
			"objective": {"kind": "defeat", "targets": [], "text": "A column marches"},
			"route": {"from": "p37.marker.west", "to": "p37.marker.east", "round_trip": true}, "speed_mps": 40.0,
			"success_outcome": "broken", "end_outcome": "passed", "abandon_after_s": 0, "xp_full_runs": 1,
			"outcomes": {"broken": {"text": "Broken."}, "passed": {"text": "Passed."}}},
	}
	for id: String in recs:
		var rec: Dictionary = recs[id]
		if extra.has(id):
			TestFixtures.deep_merge(rec, extra[id])
		TestFixtures.record_override(id, rec)


static func _template(id: String, centre: Array, members: Array, leash: float) -> Dictionary:
	var spawns: Array = []
	for m: Array in members:
		var x := float(centre[0]) + float(m[1])
		var z := float(centre[2]) + float(m[2])
		spawns.append({"entity_id": str(m[0]), "definition": "enemy.soldier", "position_m": [x, height(x, z), z], "yaw_deg": 0,
			"patrol": "", "faction": str(m[3]), "commander": false, "ai_enabled": false, "persist_death": false, "loot_table": ""})
	return {"schema_version": 1, "id": id, "type": "encounter", "template": true, "level": LEVEL,
		"center_m": [float(centre[0]), height(float(centre[0]), float(centre[2])), float(centre[2])],
		"activate_radius_m": 120, "deactivate_radius_m": 200, "leash_radius_m": leash, "alert_group": true,
		"requires_flags": [], "forbids_flags": [], "counts_toward_budget": true, "spawns": spawns}


## The tiny WorldRoot with the giant at `at` (on the ground), its EncounterDirector and WanderDirector, the
## ring around the giant loaded (deterministic slices); the living world on (test_active), nothing in view;
## the suite's floor taken away. Returns [root, wander director].
static func make(parent: Node, at := GIANT_AT) -> Array:
	# IntegrationSuite's own floor (a 120 m box, its top at y 0) stands over the tiny world's ground where
	# that dips below 0 (its west half): only the tiny world's terrain is ground here (M8 gate, F18: the
	# wanderers' footprint check sees any other body as an obstacle).
	for n in parent.get_children():
		if n is StaticBody3D:
			parent.remove_child(n)
			n.queue_free()
	var root := TinyWorld.make_root(true, Vector3(at.x, height(at.x, at.z) + 0.3, at.z))
	var director := EncounterDirector.new()
	director.name = "EncounterDirector"
	root.add_child(director)
	var wd := WanderDirector.new()
	wd.name = "WanderDirector"
	root.add_child(wd)
	WanderDirector.test_active = true
	WanderDirector.view_probe = func(_p: Vector3) -> bool: return false
	parent.add_child(root)
	root.streamer.deterministic = true
	load_ring(root, at)
	var p := root.player()
	if p != null:
		p.router.use_injection = true
	return [root, wd]


static func load_ring(root: WorldRoot, at: Vector3) -> void:
	var guard := 0
	while not root.streamer.ring_ready(at) and guard < 60:
		root.streamer.load_ring_slice(at)
		guard += 1


## Moves the giant to (x, z) on the ground, loads the ring around it and lets the streamer unload what
## lies unload_at (3) chunks or more from it (TinyWorld's hysteresis).
static func move_giant(root: WorldRoot, x: float, z: float) -> void:
	var p := root.player()
	p.global_position = Vector3(x, height(x, z) + 0.3, z)
	p.velocity = Vector3.ZERO
	load_ring(root, p.global_position)
	for i in 12:
		root.streamer.update(true)


## The statics the tests change (WanderDirector's switches and carried events).
static func reset() -> void:
	WanderDirector.reset_for_tests()
