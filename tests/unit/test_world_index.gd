extends TestSuite
## The world index (P20; plan M6-M9 §2.6, decision 14): WorldIndex answers positions, display names
## and arrival limits by id without the nodes. The Valley's index (assets/world/index_valley.res,
## written by tools/builders/valley.gd) names every shrine by its record and every waystone by its
## layout name, and knows every marker, area, prop, encounter and district the quests name, and the
## roads; lookups, the region grid, A* routes with stage limits, the cache and build_from_scene work
## on indexes built in code; Quests.objective_position falls back to the index when a marker is not
## loaded (freed with its chunk).

const VALLEY := "level.valley"
const TEST_LEVEL := "level.test_p20_index"
const SHRINE_SCENE := "res://scenes/world/shrine.tscn"
const FENCE_SCENE := "res://scenes/world/fence_wood.tscn"

const SHRINES := {"valley.shrine.hollow": "Hollow Shrine", "valley.shrine.grove": "Grove Shrine",
	"valley.shrine.thornwick": "Thornwick Shrine", "valley.shrine.kingsfall": "Kingsfall Shrine"}
const WAYSTONES := {"valley.cp.forest_road": "Forest road waystone", "valley.cp.ruins_gate": "Ruins gate waystone",
	"valley.cp.barrow_gap": "Barrow gap waystone"}


func after_each() -> void:
	GameSession.mode = GameSession.Mode.SANDBOX
	GameSession.level_id = ""
	Quests.refresh_positions()


func _valley() -> WorldIndex:
	var idx := WorldIndex.for_level(VALLEY)
	assert_true(idx != null, "level.valley names its index and the file exists")
	return idx


## Every condition of `c` and below it (all / any / not / count).
static func _conditions(c: Variant, out: Array) -> void:
	if typeof(c) != TYPE_DICTIONARY:
		return
	out.append(c)
	var of: Variant = (c as Dictionary).get("of")
	if typeof(of) == TYPE_ARRAY:
		for sub: Variant in of:
			_conditions(sub, out)
	elif typeof(of) == TYPE_DICTIONARY:
		_conditions(of, out)


# --------------------------------------------------------------------------- the Valley's index

func test_the_valley_index_names_its_shrines_and_waystones() -> void:
	var idx := _valley()
	assert_eq(idx.level_id, VALLEY, "the index knows its level")
	assert_eq(idx.checkpoint_ids().size(), SHRINES.size() + WAYSTONES.size(), "four shrines and three waystones")
	for id: String in SHRINES:
		var e := idx.checkpoint(id)
		assert_eq(str(e.get("display_name", "")), SHRINES[id], "%s takes its record's name" % id)
		assert_eq(str(e.get("kind", "")), "shrine", "%s is a shrine" % id)
		assert_eq(SHRINES[id], str(GameData.get_record("shrine." + id.get_slice(".", 2)).display_name),
			"%s: the name is the shrine record's" % id)
	for id: String in WAYSTONES:
		var e := idx.checkpoint(id)
		assert_eq(str(e.get("display_name", "")), WAYSTONES[id], "%s is named from the layout" % id)
		assert_eq(str(e.get("kind", "")), "waystone", "%s is a waystone" % id)
		assert_eq((e.get("requires_flags", PackedStringArray()) as PackedStringArray).size(), 1,
			"%s keeps the flag that opens it" % id)
	for id in idx.checkpoint_ids():
		var e := idx.checkpoint(id)
		assert_true((e.position as Vector3).is_finite(), "%s has a position" % id)
		assert_eq(idx.max_stage_of(id), WorldIndex.ANY_STAGE, "%s: every Valley checkpoint takes any stage (placeholder 10)" % id)
		assert_true(bool(e.fast_travel), "%s is a fast travel point" % id)
		assert_true(str(e.district) != "", "%s lies in a district (%s)" % [id, e.district])
		var t := idx.spawn_transform(id)
		assert_true(t.origin.is_equal_approx(e.position), "%s: the spawn transform is at its position" % id)
		assert_near(t.basis.get_euler().y, float(e.yaw), 1e-4, "%s: turned to its yaw" % id)
	assert_eq(str(idx.checkpoint("valley.shrine.grove").district), "forest", "the Grove Shrine is in the Old Wood")
	assert_eq(WorldIndex.display_name_in(VALLEY, "valley.shrine.grove"), "Grove Shrine", "display_name_in")
	assert_eq(WorldIndex.display_name_in(VALLEY, "valley.cp.no_such_stone"), "", "an unknown id has no name")
	assert_eq(WorldIndex.display_name_in("level.no_such_level", "valley.shrine.grove"), "", "nor a level without an index")


func test_the_valley_index_knows_every_place_the_quests_name() -> void:
	var idx := _valley()
	var named := 0
	for rec: Dictionary in GameData.records_of_type("quest"):
		for s: Dictionary in rec.get("stages", []):
			for m in Quests.stage_markers(s):
				named += 1
				assert_true(idx.position_of(m).is_finite(), "%s/%s: marker %s" % [rec.id, s.id, m])
			var conds: Array = []
			_conditions(s.get("complete_when"), conds)
			for c: Dictionary in conds:
				match str(c.get("type", "")):
					"entered":
						named += 1
						assert_true(idx.areas.has(str(c.area)), "%s/%s: area %s" % [rec.id, s.id, c.area])
					"destroyed":
						named += 1
						assert_true(idx.props.has(str(c.world_id)), "%s/%s: prop %s" % [rec.id, s.id, c.world_id])
					"encounter_cleared":
						named += 1
						assert_true(idx.position_of(str(c.encounter)).is_finite(), "%s/%s: encounter %s" % [rec.id, s.id, c.encounter])
	assert_true(named >= 30, "the quests name %d places" % named)
	for id in GameData.ids_of_type("encounter"):
		if str(GameData.get_record(id).get("level", "")) == VALLEY:
			assert_true(idx.encounters.has(id), "encounter %s is indexed" % id)
	var districts := {}
	for d: Dictionary in idx.districts:
		districts[str(d.id)] = str(d.display_name)
	for d: Dictionary in GameData.get_record(VALLEY).get("districts", []):
		assert_eq(str(districts.get(str(d.id), "")), str(d.display_name), "district %s with its name" % d.id)
		assert_eq(idx.display_name(str(d.id)), str(d.display_name), "display_name() of district %s" % d.id)
	assert_eq(idx.district_at(idx.position_of("valley.marker.elder")), "village", "the elder is in Thornwick")
	assert_true(idx.map_bounds.size.x > 0.0 and idx.map_bounds.has_point(Vector2(0, 0)), "the map covers the Valley")


func test_the_valley_roads_join_the_hollow_to_kingsfall() -> void:
	var idx := _valley()
	var nodes := idx.road_nodes()
	var edges := idx.road_edges()
	assert_true(nodes.size() >= 10, "the road graph has nodes (%d)" % nodes.size())
	assert_eq(edges.size() % 2, 0, "edges are pairs")
	for k in edges.size():
		assert_true(edges[k] >= 0 and edges[k] < nodes.size(), "edge end %d names a node" % k)
	var from := idx.position_of("valley.shrine.hollow")
	var to := idx.position_of("valley.shrine.kingsfall")
	var route := idx.route(from, to, 1)
	assert_true(route.size() >= 3, "a route from the Hollow to Kingsfall (%d nodes)" % route.size())
	if route.size() >= 2:
		assert_true(route[0].is_equal_approx(nodes[idx.nearest_road_node(from)]), "it starts at the road nearest the Hollow")
		assert_true(route[route.size() - 1].is_equal_approx(nodes[idx.nearest_road_node(to)]), "and ends nearest Kingsfall")
	var reversed := idx.route(to, from, 1)
	assert_eq(reversed.size(), route.size(), "the way back has as many nodes")


# --------------------------------------------------------------------------- an index built in code

func _index() -> WorldIndex:
	var idx := WorldIndex.new()
	idx.level_id = TEST_LEVEL
	idx.checkpoints = {
		"test.cp.low": {"position": Vector3(10, 0, 0), "yaw": PI / 2, "display_name": "Low stone", "kind": "waystone",
			"fast_travel": true, "requires_flags": PackedStringArray(["test.flag.open"]), "max_stage": 3},
		"test.cp.any": {"position": Vector3(-10, 1, 5), "yaw": 0.0, "display_name": "The Any Gate", "kind": "shrine"}}
	idx.markers = {"test.marker.m": {"position": Vector3(1, 2, 3), "kind": "objective"}}
	idx.areas = {"test.area.a": {"position": Vector3(4, 0, 4), "radius": 6.0}}
	idx.pois = {"test.poi.p": {"position": Vector3(50, 0, 50), "radius": 30.0, "display_name": "Hollowmere"}}
	idx.exits = {"test.exit.e": {"position": Vector3(0, 0, -40), "to_level": "level.x", "to_checkpoint": "x.cp",
		"display_name": "The Door"}}
	idx.props = {"test.prop.p": {"position": Vector3(7, 0, 7)}}
	idx.encounters = {"encounter.test_p20": {"center": Vector3(-30, 0, -30), "faction": ""}}
	idx.districts = [{"id": "test_district", "display_name": "Test District", "min": Vector2(-20, -20), "max": Vector2(20, 20)}]
	return idx


func test_lookups_by_id() -> void:
	var idx := _index()
	assert_false(idx.is_empty(), "not empty")
	assert_true(WorldIndex.new().is_empty(), "a new index is empty")
	assert_eq(idx.position_of("test.cp.low"), Vector3(10, 0, 0), "a checkpoint's position")
	assert_eq(idx.position_of("test.marker.m"), Vector3(1, 2, 3), "a marker's")
	assert_eq(idx.position_of("test.area.a"), Vector3(4, 0, 4), "an area's")
	assert_eq(idx.position_of("test.poi.p"), Vector3(50, 0, 50), "a POI's")
	assert_eq(idx.position_of("test.exit.e"), Vector3(0, 0, -40), "an exit's")
	assert_eq(idx.position_of("test.prop.p"), Vector3(7, 0, 7), "a prop's")
	assert_eq(idx.position_of("encounter.test_p20"), Vector3(-30, 0, -30), "an encounter's centre")
	assert_false(idx.position_of("test.unknown").is_finite(), "an unknown id: INF")
	assert_false(idx.position_of("").is_finite(), "no id: INF")
	assert_eq(idx.display_name("test.cp.low"), "Low stone", "a checkpoint's name")
	assert_eq(idx.display_name("test.poi.p"), "Hollowmere", "a POI's")
	assert_eq(idx.display_name("test.exit.e"), "The Door", "an exit's")
	assert_eq(idx.display_name("test_district"), "Test District", "a district's")
	assert_eq(idx.display_name("test.marker.m"), "", "markers have no names")
	assert_eq(idx.checkpoint("test.unknown"), {}, "an unknown checkpoint: {}")
	assert_true(idx.has_checkpoint("test.cp.any") and not idx.has_checkpoint("test.marker.m"), "has_checkpoint")
	assert_eq(idx.max_stage_of("test.cp.low"), 3, "an arrival limit")
	assert_eq(idx.max_stage_of("test.cp.any"), WorldIndex.ANY_STAGE, "none: any stage")
	assert_eq(idx.max_stage_of("test.unknown"), WorldIndex.ANY_STAGE, "an unknown checkpoint never refuses")
	assert_eq(idx.checkpoint_ids(), PackedStringArray(["test.cp.any", "test.cp.low"]), "ids, sorted")
	var t := idx.spawn_transform("test.cp.low")
	assert_eq(t.origin, Vector3(10, 0, 0), "spawn position")
	assert_near(t.basis.get_euler().y, PI / 2, 1e-5, "spawn yaw")
	assert_false(idx.spawn_transform("test.unknown").origin.is_finite(), "an unknown spawn: INF origin")
	assert_eq(idx.district_at(Vector3(0, 0, 0)), "test_district", "inside the district")
	assert_eq(idx.district_at(Vector3(30, 0, 0)), "", "outside every district")


func test_the_region_grid() -> void:
	var idx := _index()
	assert_eq(idx.region_at(Vector3.ZERO), "", "no grid: no region")
	idx.grid_origin = Vector2(-100, -100)
	idx.cell_m = 50.0
	idx.grid_size = Vector2i(4, 4)
	idx.region_ids = PackedStringArray(["region.west", "region.east"])
	var grid := PackedByteArray()
	grid.resize(16)
	for z in 4:
		for x in 4:
			grid[z * 4 + x] = 1 if x < 2 else 2
	grid[0] = 0
	idx.region_grid = grid
	assert_eq(idx.region_at(Vector3(-60, 0, 30)), "region.west", "a west cell")
	assert_eq(idx.region_at(Vector3(60, 0, 30)), "region.east", "an east cell")
	assert_eq(idx.region_at(Vector3(-99, 0, -99)), "", "a cell of no region (0)")
	assert_eq(idx.region_at(Vector3(-101, 0, 0)), "", "outside the grid")
	assert_eq(idx.region_at(Vector3(0, 0, 100)), "", "past its far edge")


func test_road_routes_respect_the_stage_limits() -> void:
	var idx := WorldIndex.new()
	# A square A-B-C-D with a long detour: A (0,0) -> B (100,0) -> C (100,100), and A -> D (0,100) -> C.
	# A-B is only for stages up to 4 (a narrow old path); D-C only from stage 2.
	idx.add_road(Vector3(0, 0, 0), Vector3(100, 0, 0), 8.0, 0, 4)
	idx.add_road(Vector3(100, 0, 0), Vector3(100, 0, 100), 8.0)
	idx.add_road(Vector3(0.2, 0, 0), Vector3(0, 0, 150), 12.0)          # merges with A (within 0.5 m)
	idx.add_road(Vector3(0, 0, 150), Vector3(100, 0, 100), 12.0, 2, WorldIndex.ANY_STAGE, true)
	idx.add_road(Vector3(5, 0, 5), Vector3(5, 0, 5), 1.0)                # a zero-length road adds nothing
	assert_eq(idx.road_nodes().size(), 4, "four nodes: the near-duplicate merged")
	assert_eq(idx.road_edges().size(), 8, "four edges")
	assert_eq(int((idx.roads.direct as PackedByteArray)[3]), 1, "the direct flag is stored")
	assert_eq(idx.nearest_road_node(Vector3(90, 0, 10)), 1, "the nearest node")
	var a := Vector3(1, 0, 1)
	var c := Vector3(99, 0, 99)
	var short := idx.route(a, c, 3)
	assert_eq(short, PackedVector3Array([Vector3(0, 0, 0), Vector3(100, 0, 0), Vector3(100, 0, 100)]),
		"stage 3 takes the short way through B")
	var big := idx.route(a, c, 5)
	assert_eq(big, PackedVector3Array([Vector3(0, 0, 0), Vector3(0, 0, 150), Vector3(100, 0, 100)]),
		"stage 5 is too big for A-B and goes round by D")
	var small := idx.route(Vector3(0, 0, 140), c, 1)
	assert_eq(small, PackedVector3Array([Vector3(0, 0, 150), Vector3(0, 0, 0), Vector3(100, 0, 0), Vector3(100, 0, 100)]),
		"stage 1 may not use D-C (from stage 2) and goes back round by A and B")
	assert_true(idx.route(Vector3(0, 0, 140), c, 9).size() == 2, "a stage 9 giant walks D-C directly")
	assert_eq(idx.route(a, a, 3), PackedVector3Array([Vector3(0, 0, 0)]), "the same node: a one-node route")
	var island := WorldIndex.new()
	island.add_road(Vector3(0, 0, 0), Vector3(10, 0, 0), 4.0, 0, 2)
	assert_true(island.route(Vector3(0, 0, 0), Vector3(10, 0, 0), 3).is_empty(), "no allowed edge: no route")
	assert_true(WorldIndex.new().route(a, c, 1).is_empty(), "no roads: no route")


func test_the_cache_and_level_records() -> void:
	assert_true(WorldIndex.for_level("") == null, "no level: no index")
	assert_true(WorldIndex.for_level(TEST_LEVEL) == null, "a level without a record has none")
	TestFixtures.record_override(TEST_LEVEL + "_missing", {"schema_version": 1, "type": "level",
		"scene": "res://scenes/test/flow_test_level.tscn", "index": "res://assets/world/no_such_index.res"})
	assert_true(WorldIndex.for_level(TEST_LEVEL + "_missing") == null, "a missing index file: none, quietly")
	var idx := _index()
	WorldIndex.put_cached(TEST_LEVEL, idx)
	assert_true(WorldIndex.for_level(TEST_LEVEL) == idx, "put_cached serves an index built in code")
	assert_eq(WorldIndex.display_name_in(TEST_LEVEL, "test.cp.any"), "The Any Gate", "display_name_in reads it")
	assert_true(WorldIndex.for_level(VALLEY) == WorldIndex.for_level(VALLEY), "a level's index loads once")
	WorldIndex.clear_cache()
	assert_true(WorldIndex.for_level(TEST_LEVEL) == null, "clear_cache forgets it (ResetHooks.AFTER_EACH)")


func test_build_from_scene() -> void:
	var root := Node3D.new()
	root.position = Vector3(500, 0, 500)   # level space: the root's own transform is left out
	var shrine: Shrine = (load(SHRINE_SCENE) as PackedScene).instantiate()
	shrine.world_id = "test.shrine.p20"
	shrine.shrine_id = "shrine.grove"
	shrine.position = Vector3(10, 0, 0)
	root.add_child(shrine)
	var group := Node3D.new()
	group.position = Vector3(0, 0, 20)
	root.add_child(group)
	var stone := Waystone.new()
	stone.checkpoint_id = "test.cp.stone"
	stone.display_name = "Test stone"
	stone.requires_flags = PackedStringArray(["test.flag.open"])
	stone.position = Vector3(5, 0, 0)
	stone.rotation.y = PI / 2
	group.add_child(stone)
	var plain := CheckpointMarker.new()
	plain.checkpoint_id = "test.cp.plain"
	plain.position = Vector3(-5, 0, 0)
	root.add_child(plain)
	var marker := LevelMarker.new()
	marker.marker_id = "test.marker.goal"
	marker.kind = LevelMarker.Kind.SAFE
	marker.position = Vector3(1, 0, 1)
	group.add_child(marker)
	var area := AreaTrigger.new()
	area.area_id = "test.area.ring"
	area.position = Vector3(0, 0, -30)
	var shape := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = 7.0
	shape.shape = cyl
	area.add_child(shape)
	root.add_child(area)
	var exit := LevelExit.new()
	exit.exit_id = "test.exit.door"
	exit.to_level = "level.test_p20_b"
	exit.to_checkpoint = "test.b.arrive"
	exit.display_name = "The Test Door"
	exit.position = Vector3(0, 0, -50)
	root.add_child(exit)
	var fence: Node3D = (load(FENCE_SCENE) as PackedScene).instantiate()
	fence.set("world_id", "test.prop.fence")
	fence.position = Vector3(30, 0, 0)
	root.add_child(fence)
	var idx := WorldIndex.build_from_scene(root, TEST_LEVEL)
	assert_eq(idx.level_id, TEST_LEVEL, "the level id")
	var s := idx.checkpoint("test.shrine.p20")
	assert_eq(str(s.get("display_name", "")), "Grove Shrine", "a shrine takes its record's name")
	assert_eq(str(s.get("kind", "")), "shrine", "kind shrine")
	var spawn := shrine.get_node("SpawnPoint") as Node3D
	assert_true((s.position as Vector3).is_equal_approx(shrine.position + spawn.position),
		"at its SpawnPoint, in level space (%s)" % s.position)
	var w := idx.checkpoint("test.cp.stone")
	assert_eq(str(w.get("display_name", "")), "Test stone", "a waystone's display_name")
	assert_eq(str(w.get("kind", "")), "waystone", "kind waystone")
	assert_true((w.position as Vector3).is_equal_approx(Vector3(5, 0, 20)), "through its parent's offset")
	assert_eq(w.requires_flags, PackedStringArray(["test.flag.open"]), "its flags")
	assert_near(float(w.yaw), PI / 2, 1e-4, "its yaw")
	assert_eq(str(idx.checkpoint("test.cp.plain").get("kind", "")), "checkpoint", "a plain checkpoint")
	assert_false(bool(idx.checkpoint("test.cp.plain").get("fast_travel", true)), "is no fast travel point")
	assert_eq(idx.checkpoint_ids().size(), 3, "the shrine's own SpawnPoint is not counted twice")
	assert_true((idx.markers["test.marker.goal"].position as Vector3).is_equal_approx(Vector3(1, 0, 21)), "a marker")
	assert_eq(str(idx.markers["test.marker.goal"].kind), "safe", "with its kind")
	assert_near(float(idx.areas["test.area.ring"].get("radius", 0.0)), 7.0, 1e-6, "an area's radius")
	var x: Dictionary = idx.exits.get("test.exit.door", {})
	assert_eq([str(x.get("to_level", "")), str(x.get("to_checkpoint", "")), str(x.get("display_name", ""))],
		["level.test_p20_b", "test.b.arrive", "The Test Door"], "an exit's destination and name")
	assert_true(idx.props.has("test.prop.fence"), "a prop by its world id")
	assert_true(idx.encounters.is_empty() and idx.districts.is_empty(), "no records: no encounters, no districts")
	root.free()


# --------------------------------------------------------------------------- Quests fall back to it

func test_objective_positions_fall_back_to_the_index_when_the_marker_is_gone() -> void:
	TestFixtures.record_override(TEST_LEVEL, {"schema_version": 1, "type": "level", "display_name": "Index test",
		"scene": "res://scenes/test/flow_test_level.tscn", "start_checkpoint": "test.cp.any"})
	var idx := _index()
	idx.markers["test.marker.goal"] = {"position": Vector3(30, 0, 40), "kind": "objective"}
	WorldIndex.put_cached(TEST_LEVEL, idx)
	var root := LevelRoot.new()
	root.level_id = TEST_LEVEL
	root.position = Vector3(5, 0, 0)
	add_child(root)
	var marker := LevelMarker.new()
	marker.marker_id = "test.marker.goal"
	marker.position = Vector3(31, 0, 41)
	root.add_child(marker)
	Quests.refresh_positions()
	assert_true(root.index() == idx, "LevelRoot.index() is the level's index")
	assert_true(Quests.level_index() == idx, "Quests reads the loaded level's index")
	assert_eq(Quests.objective_position("test.marker.goal"), Vector3(36, 0, 41), "the loaded marker wins")
	marker.free()
	Quests.refresh_positions()
	assert_eq(Quests.objective_position("test.marker.goal"), Vector3(35, 0, 40),
		"with the marker freed: its index entry, moved with the level root")
	assert_eq(Quests.objective_position("", PackedStringArray(["test.unknown", "test.prop.p"])), Vector3(12, 0, 7),
		"a target the index knows (a prop of a streamed-out chunk)")
	assert_false(Quests.objective_position("test.marker.nowhere").is_finite(), "nothing knows it: INF")
	root.free()
	# Without a loaded level root, the campaign level's index answers (in level space).
	GameSession.mode = GameSession.Mode.VALLEY
	GameSession.level_id = TEST_LEVEL
	Quests.refresh_positions()
	assert_true(Quests.level_index() == idx, "the campaign level's index")
	assert_eq(Quests.objective_position("test.marker.goal"), Vector3(30, 0, 40), "at its level-space position")
