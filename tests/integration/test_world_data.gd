extends TestSuite
## P25 (plan M6-M9 §2.7, §3.8, §5): the world's data - level.world and its five regions tiling the
## interior, the 48 POIs (their regions, landmarks inside their radii, the nine sealed places and
## their seals), the five world shrines, the 17 waystones, the caches' loot and the seven cairns,
## the index (region grid, staged road graph), the chunk files, the map picture, the world's data
## budget and the flag-shown elements (the Broken Stair's rubble; FlagVisibility on bare nodes).
## Files and records only (no scene is instanced): the default tier's budget.

const LEVEL := "level.world"
const INDEX := "res://assets/world/index_world.res"
const MAP := "res://assets/world/map_world.png"
const INTERIOR := 896.0
## The world's files and their budget (plan §5.2: 5.0 MB of world data; the map picture 300 KB).
const DATA_BUDGET := 5.0 * 1024.0 * 1024.0
const MAP_BUDGET := 300 * 1024
const DATA_DIRS := ["res://assets/world/chunks", "res://assets/world/nav", "res://assets/world/structures",
	"res://assets/world/shared", "res://scenes/world/chunks"]
const DATA_FILES := ["res://assets/world/index_world.res", "res://assets/world/map_world.png",
	"res://assets/world/skyline.res", "res://assets/world/skyline_landmarks.res", "res://scenes/world/world.tscn"]
const REGIONS := ["region.crownmarch", "region.greywood", "region.drowned_steps", "region.aldmere", "region.stonehold"]
## POIs per region (plan §5.4: 15 + 8 + 8 + 8 + 9).
const POIS_PER_REGION := {"region.crownmarch": 15, "region.greywood": 8, "region.drowned_steps": 8,
	"region.aldmere": 8, "region.stonehold": 9}
const SECRETS := ["poi.kingsgate_statue", "poi.barrow_vault", "poi.old_root", "poi.sunken_vault", "poi.bones_shoulder",
	"poi.kings_armoury", "poi.ridge_eyrie"]
const WAYSTONES := ["world.cp.kingsgate_shelf", "world.cp.millford", "world.cp.brannock", "world.cp.kings_road",
	"world.cp.shepherds_watch", "world.cp.hollowmere", "world.cp.needle", "world.cp.troll_den", "world.cp.mere_south",
	"world.cp.bell_tower", "world.cp.aldmere_road", "world.cp.fort_gate", "world.cp.ironway", "world.cp.ironway_top",
	"world.cp.cairnlands", "world.cp.skarn", "world.cp.moot_foot"]
## World shrine -> [record, max_stage, growth flags] (plan §3.8: Kingsgate needs its beacon lit).
const SHRINES := {"world.shrine.kingsgate": ["shrine.world_kingsgate", 4, ["world.kingsgate.lit"]],
	"world.shrine.greywood": ["shrine.world_greywood", 5, []], "world.shrine.steps": ["shrine.world_steps", 5, []],
	"world.shrine.aldmere": ["shrine.world_aldmere", 5, []], "world.shrine.stones": ["shrine.world_stones", 6, []]}
## The seven world cairns that need no seal (plan §3.8; the six sealed ones come with their regions).
const CAIRNS := {"world.crownmarch.barrow_cairn": "barrow_fields", "world.crownmarch.falls_cairn": "wend_falls",
	"world.greywood.grove_cairn": "hidden_grove", "world.drowned.circle_cairn": "ancestral_circle",
	"world.aldmere.mill_cairn": "deserters_mill", "world.stonehold.cairnlands_cairn": "cairnlands",
	"world.stonehold.stair_top_cairn": "stair_top"}

const LAYOUT_DIR := "res://tools/data/world/"
const LAYOUT_REGIONS := ["crownmarch", "greywood", "drowned_steps", "aldmere", "stonehold"]

var _idx: WorldIndex = null


func _index() -> WorldIndex:
	if _idx == null:
		_idx = load(INDEX) as WorldIndex
	return _idx


func _pois() -> Array:
	return GameData.records_of_type("poi").filter(func(r: Dictionary) -> bool: return str(r.get("level", "")) == LEVEL)


## A layout table (tools/data/world/<name>.json).
static func _layout(file: String) -> Dictionary:
	var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(LAYOUT_DIR + file + ".json"))
	return d if typeof(d) == TYPE_DICTIONARY else {}


static func _rect(bounds: Array) -> Rect2:
	return Rect2(Vector2(float(bounds[0][0]), float(bounds[0][1])),
		Vector2(float(bounds[1][0]) - float(bounds[0][0]), float(bounds[1][1]) - float(bounds[0][1])))


static func _xz(v: Variant) -> Vector2:
	if v is Vector3:
		return Vector2((v as Vector3).x, (v as Vector3).z)
	var a: Array = v
	return Vector2(float(a[0]), float(a[2]))


# --------------------------------------------------------------------------- level and regions

func test_the_level_and_its_regions_tile_the_interior() -> void:
	var level := GameData.get_record(LEVEL)
	assert_eq(str(level.get("type", "")), "level", "level.world ships")
	assert_true(ResourceLoader.exists(str(level.scene)), "its scene exists")
	assert_true(ResourceLoader.exists(str(level.index)), "its index exists")
	assert_eq(str(level.start_checkpoint), "world.cp.kingsgate_shelf", "it starts on the Kingsgate shelf")
	assert_eq(Array(level.regions), REGIONS, "its five regions in order")
	assert_eq(int(level.max_formation_members), 40, "40 formation members on the desktop")
	assert_eq(int(level.web_overrides.max_formation_members), 20, "20 on the web")
	var area := 0.0
	var rects: Array = []
	for id: String in REGIONS:
		var r := GameData.get_record(id)
		assert_eq(str(r.get("level", "")), LEVEL, "%s is level.world's" % id)
		var rect := _rect(r.bounds_m)
		assert_true(Rect2(-INTERIOR, -INTERIOR, 2.0 * INTERIOR, 2.0 * INTERIOR).encloses(rect), "%s lies in the interior" % id)
		for other: Rect2 in rects:
			assert_false(other.intersection(rect).get_area() > 0.0, "%s overlaps no other region" % id)
		rects.append(rect)
		area += rect.get_area()
	assert_near(area, 4.0 * INTERIOR * INTERIOR, 0.5, "the five regions tile the interior")


func test_the_region_grid_matches_the_region_records() -> void:
	var idx := _index()
	assert_eq(Array(idx.region_ids), REGIONS, "the grid's region list is the level's")
	assert_eq(idx.cell_m, 64.0, "64 m cells")
	assert_eq(idx.grid_size, Vector2i(32, 32), "over the whole 2 x 2 km")
	var wrong := 0
	for j in idx.grid_size.y:
		for i in idx.grid_size.x:
			var c := idx.grid_origin + Vector2((i + 0.5) * idx.cell_m, (j + 0.5) * idx.cell_m)
			var p := Vector2(clampf(c.x, -INTERIOR + 0.01, INTERIOR - 0.01), clampf(c.y, -INTERIOR + 0.01, INTERIOR - 0.01))
			var expected := ""
			for id: String in REGIONS:
				if _rect(GameData.get_record(id).bounds_m).has_point(p):
					expected = id
					break
			if idx.region_at(Vector3(c.x, 0.0, c.y)) != expected:
				wrong += 1
	assert_eq(wrong, 0, "every cell holds the region whose bounds hold its centre (the rim: the region beside it)")


# --------------------------------------------------------------------------- POIs

func test_the_points_of_interest() -> void:
	var idx := _index()
	var pois := _pois()
	assert_eq(pois.size(), 48, "48 POIs (plan §5.4)")
	var per_region := {}
	var secrets := 0
	for poi: Dictionary in pois:
		var id := str(poi.id)
		per_region[str(poi.region)] = int(per_region.get(str(poi.region), 0)) + 1
		assert_true(idx.pois.has(id), "%s is in the index" % id)
		var pos := _xz(poi.position_m)
		assert_true(_rect(GameData.get_record(str(poi.region)).bounds_m).grow(64.0).has_point(pos), "%s lies in its region" % id)
		if str(poi.kind) != "shrine":
			assert_true(int(poi.xp) > 0, "%s gives discovery XP" % id)
		var landmark := str(poi.get("landmark", ""))
		var at: Vector3 = idx.position_of(landmark)
		assert_true(landmark != "" and at != Vector3.INF, "%s's landmark %s is in the index" % [id, landmark])
		if at != Vector3.INF:
			assert_true(Vector2(at.x, at.z).distance_to(pos) <= float(poi.radius_m),
				"%s's landmark %s stands inside its radius (%.0f m from its centre, radius %s)" % [id, landmark,
				Vector2(at.x, at.z).distance_to(pos), poi.radius_m])
		if str(poi.kind) == "secret":
			secrets += 1
			assert_true(int(poi.min_stage) >= 5, "the sealed place %s needs stage 5 or 6" % id)
			assert_true(idx.props.has(str(poi.get("seal", ""))), "%s's seal %s is in the index" % [id, poi.get("seal", "")])
		if str(poi.kind) == "vista" and float(poi.get("reveals_m", 0.0)) > 0.0:
			assert_true(float(poi.reveals_m) >= 400.0, "%s reveals at least 400 m" % id)
		if str(poi.kind) == "settlement":
			assert_true(int(poi.get("max_inner_stage", 0)) >= 4 and poi.has("green_m"), "%s has its green for big giants" % id)
	assert_eq(per_region, POIS_PER_REGION, "15 + 8 + 8 + 8 + 9 POIs by region")
	assert_eq(secrets, SECRETS.size(), "seven sealed places of kind secret (the Ancestral Circle and the Moot need stages too)")
	for id: String in SECRETS:
		assert_eq(str(GameData.get_record(id).get("kind", "")), "secret", "%s is a sealed place" % id)
	var skyline := pois.filter(func(r: Dictionary) -> bool: return bool(r.get("skyline", false)))
	assert_true(skyline.size() >= 10 and skyline.size() <= 14, "about twelve skyline landmarks (%d)" % skyline.size())


# --------------------------------------------------------------------------- shrines, waystones, cairns, caches

func test_the_world_shrines_and_waystones() -> void:
	var idx := _index()
	for id: String in SHRINES:
		var spec: Array = SHRINES[id]
		assert_true(idx.has_checkpoint(id), "%s is in the index" % id)
		assert_eq(str(idx.checkpoint(id).get("kind", "")), "shrine", "%s is a shrine" % id)
		var rec := GameData.get_record(str(spec[0]))
		assert_eq(int(rec.get("max_stage", 0)), int(spec[1]), "%s grows to stage %d" % [spec[0], spec[1]])
		assert_eq(Array(rec.get("growth_requires_flags", [])), spec[2], "%s's growth condition" % spec[0])
	for id: String in WAYSTONES:
		assert_true(idx.has_checkpoint(id), "%s is in the index" % id)
		assert_true(bool(idx.checkpoint(id).get("fast_travel", false)), "%s is a fast-travel destination" % id)
		assert_true(str(idx.checkpoint(id).get("display_name", "")) != "", "%s has a display name" % id)
	assert_true(idx.has_checkpoint("world.cp.broken_stair"), "the Broken Stair's arrival checkpoint")
	assert_false(bool(idx.checkpoint("world.cp.broken_stair").get("fast_travel", true)), "which is no fast-travel destination")
	var waystones := 0
	for id: String in idx.checkpoints:
		if str(idx.checkpoints[id].get("kind", "")) == "waystone":
			waystones += 1
	assert_eq(waystones, 17, "17 waystones (plan §5.4)")
	for id: String in ["world.exit.kingsgate", "world.exit.broken_stair"]:
		assert_true(idx.exits.has(id), "the exit %s" % id)
		assert_eq(str(idx.exits[id].get("to_level", "")), "level.valley", "%s leads to the Valley" % id)
	# The Kingsgate shrine waits for the beacon whose skyline column the same flag lights (P29 relights it).
	var beacons: Array = _layout("world").get("beacons", [])
	assert_true(beacons.any(func(b: Dictionary) -> bool: return str(b.flag) == "world.kingsgate.lit"),
		"the Kingsgate beacon's column burns on world.kingsgate.lit")


func test_the_cairns_and_the_caches() -> void:
	var idx := _index()
	for id: String in CAIRNS:
		assert_true(idx.props.has(id), "the cairn %s is in the index" % id)
		assert_eq(str(idx.props.get(id, {}).get("kind", "")), "cairn", "%s is a cairn" % id)
		var dialogue := GameData.get_record("dialogue.cairn_" + str(CAIRNS[id]))
		assert_eq(Inscription.gift_flag(dialogue), "reward.cairn." + str(CAIRNS[id]), "%s gives its point once" % id)
	var cairns := 0
	var caches := 0
	for id: String in idx.props:
		match str(idx.props[id].get("kind", "")):
			"cairn":
				cairns += 1
			"cache", "ledge":
				caches += 1
	assert_eq(cairns, CAIRNS.size(), "seven cairns (the six sealed ones come with their regions)")
	assert_true(caches >= 25, "caches at ruins, vistas and the POIs that would hold nothing else (%d)" % caches)
	for region: String in LAYOUT_REGIONS:
		for it: Dictionary in _layout(region).get("caches", []):
			var loot := GameData.get_record(str(it.get("loot", "")))
			assert_eq(str(loot.get("type", "")), "loot_table", "%s's loot table %s" % [it.id, it.get("loot", "")])
	# Fort Aldmere's gate stays shut until P36 makes it the real gate; quest-critical props never break.
	assert_true(bool(idx.props.get("world.aldmere.fort_gate", {}).get("indestructible", false)), "the fort's gate is indestructible")
	for id: String in idx.props:
		if bool(idx.props[id].get("quest_critical", false)):
			assert_true(bool(idx.props[id].get("indestructible", false)), "the quest-critical %s is indestructible" % id)


# --------------------------------------------------------------------------- roads, chunks, map, budget

func test_the_road_graph_is_staged_and_joined() -> void:
	var idx := _index()
	var nodes := idx.road_nodes()
	var edges := idx.road_edges()
	assert_true(nodes.size() > 200 and edges.size() / 2 >= nodes.size() - 1, "a road graph (%d nodes)" % nodes.size())
	var direct: PackedByteArray = idx.roads.get("direct", PackedByteArray())
	var lo: PackedByteArray = idx.roads.get("min_stage", PackedByteArray())
	var hi: PackedByteArray = idx.roads.get("max_stage", PackedByteArray())
	var needle := 0
	var rockfall := 0
	for e in range(edges.size() / 2):
		if direct[e] == 1:
			needle += 1
			assert_eq(int(hi[e]), 4, "the Needle's direct edges end at stage 4")
		if int(lo[e]) == 5:
			rockfall += 1
	assert_true(needle > 0, "the Needle's edges are direct")
	assert_true(rockfall > 0, "the Grove's rockfall route needs stage 5")
	# every node joins the graph (ignoring the stages): the shelf's node reaches them all
	var adj := {}
	for e in range(edges.size() / 2):
		for k in 2:
			var a := edges[2 * e + k]
			if not adj.has(a):
				adj[a] = []
			(adj[a] as Array).append(edges[2 * e + 1 - k])
	var start := idx.nearest_road_node(idx.position_of("world.cp.kingsgate_shelf"))
	var seen := {start: true}
	var queue := [start]
	while not queue.is_empty():
		var n: int = queue.pop_back()
		for m: int in adj.get(n, []):
			if not seen.has(m):
				seen[m] = true
				queue.append(m)
	assert_eq(seen.size(), nodes.size(), "the shelf's road node reaches every road node")
	for poi: Dictionary in _pois():
		var at: Vector3 = idx.pois[str(poi.id)].position
		var q := nodes[idx.nearest_road_node(at)]
		assert_true(Vector2(q.x - at.x, q.z - at.z).length() <= 31.0, "%s has a road node within 30 m" % poi.id)


func test_every_chunk_has_its_data() -> void:
	var w: Dictionary = GameData.get_record(LEVEL).world
	assert_eq([int(w.grid[0]), int(w.grid[1]), int(w.chunk_size_m)], [8, 8, 256], "an 8 x 8 grid of 256 m chunks")
	for z in 8:
		for x in 8:
			assert_true(ResourceLoader.exists("%s/c%d_%d.res" % [w.chunk_dir, x, z]), "c%d_%d's chunk data" % [x, z])
	assert_true(ResourceLoader.exists(str(w.skyline)), "the skyline's coarse terrain")
	assert_true(ResourceLoader.exists(str(w.skyline_landmarks)), "the skyline's landmarks")


func test_the_map_picture_and_the_data_budget() -> void:
	var idx := _index()
	assert_eq(idx.map_image, MAP, "the index names the map picture")
	assert_eq(idx.map_bounds, Rect2(-1024, -1024, 2048, 2048), "over the whole world")
	var bytes := FileAccess.get_file_as_bytes(MAP)
	assert_true(bytes.size() > 0 and bytes.size() <= MAP_BUDGET, "the map is at most 300 KB (%d bytes)" % bytes.size())
	var img := Image.new()
	assert_eq(img.load_png_from_buffer(bytes), OK, "it is a PNG")
	assert_eq(img.get_size(), Vector2i(1024, 1024), "1,024 x 1,024")
	var total := 0
	for f: String in DATA_FILES:
		total += FileAccess.get_file_as_bytes(f).size()
	for dir: String in DATA_DIRS:
		for f: String in DirAccess.get_files_at(dir):
			if not f.ends_with(".import") and not f.ends_with(".uid"):
				total += FileAccess.get_file_as_bytes(dir.path_join(f)).size()
	assert_true(total > 1024 * 1024 and total <= DATA_BUDGET, "the world's data is at most 5.0 MB (%.2f MB)" % (total / 1048576.0))


# --------------------------------------------------------------------------- flag-shown elements

func test_a_flag_shows_or_hides_a_layout_element() -> void:
	# the Broken Stair's rubble (c3_7's props part) stands until the Citadel is breached
	var part := load("res://scenes/world/chunks/c3_7_0.tscn") as PackedScene
	var state := part.get_state()
	var found := ""
	for i in state.get_node_count():
		for p in state.get_node_property_count(i):
			if str(state.get_node_property_name(i, p)) == "hidden_when_flag":
				found = str(state.get_node_property_value(i, p))
	assert_eq(found, "world.citadel.breached", "the Broken Stair's rubble hides once the Citadel is breached")
	# FlagVisibility: shown, hidden by its flag with its collision off, shown again when it clears
	var flag := "test.p25.rubble_cleared"
	var holder := FlagVisibility.new()
	holder.hidden_when_flag = flag
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 2
	holder.add_child(body)
	add_child(holder)
	assert_true(holder.visible and body.collision_layer == 1, "shown while the flag is unset")
	WorldState.set_flag(flag, true)
	assert_false(holder.visible, "hidden once the flag is set")
	assert_eq([body.collision_layer, body.collision_mask], [0, 0], "and its collision off")
	WorldState.set_flag(flag, false)
	assert_true(holder.visible, "shown again when the flag clears")
	assert_eq([body.collision_layer, body.collision_mask], [1, 2], "with its collision back")
	var shown := FlagVisibility.new()
	shown.visible_when_flag = flag
	add_child(shown)
	assert_false(shown.visible, "a visible_when_flag element waits for its flag")
	WorldState.set_flag(flag, true)
	assert_true(shown.visible, "and appears with it")
	holder.free()
	shown.free()
	WorldState.flags.erase(flag)
