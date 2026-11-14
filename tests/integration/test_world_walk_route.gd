extends TestSuite
## M7 polish (the M7 gate review): the real world had no Markers/Route, so the world walk's default
## route was empty there - "--mode=world --new-game --scenario=world_walk" (and
## tools/web/stream_check.mjs --world without --route) ended at once with "the route was not finished
## (waypoint 1 of 0, lap 1 of 1)". The world builder now writes tools/data/world/world.json's
## walk_route into scenes/world/world.tscn as Markers/Route, and a walk with no route is a usage
## error. Reads the layout table, the root scene's state (nothing is instantiated) and the world's
## index; tests/slow/test_world_walk_real.gd walks it.

const SCENE := "res://scenes/world/world.tscn"
const LAYOUT := "res://tools/data/world/world.json"


## The scene's Markers/Route points in order (from the PackedScene's state, without instancing it).
static func scene_route() -> PackedVector3Array:
	var out := PackedVector3Array()
	var st := (load(SCENE) as PackedScene).get_state()
	for i in st.get_node_count():
		if not str(st.get_node_path(i, true)).ends_with("Markers/Route"):   # the node's parent
			continue
		for k in st.get_node_property_count(i):
			if st.get_node_property_name(i, k) == "transform":
				out.append((st.get_node_property_value(i, k) as Transform3D).origin)
	return out


func test_the_world_root_carries_the_layout_s_walk_route() -> void:
	var layout: Variant = JSON.parse_string(FileAccess.get_file_as_string(LAYOUT))
	var points: Array = (layout as Dictionary).get("walk_route", {}).get("points", []) if typeof(layout) == TYPE_DICTIONARY else []
	assert_true(points.size() >= 2, "world.json has a walk_route of at least two points (%d)" % points.size())
	var route := scene_route()
	assert_eq(route.size(), points.size(), "world.tscn's Markers/Route has one marker per point")
	for i in mini(route.size(), points.size()):
		assert_true(Vector2(route[i].x, route[i].z).is_equal_approx(Vector2(float(points[i][0]), float(points[i][1]))),
			"point %d at %s (the layout's %s)" % [i + 1, route[i], points[i]])
	# The walk crosses region borders (the world's index knows the regions), so the stream check's
	# --audio recording hears the music change, and seams (chunks of 256 m), so chunks stream.
	var idx := WorldIndex.for_level("level.world")
	var regions := PackedStringArray()
	var chunks := {}
	for p in route:
		var r := idx.region_at(p)
		if regions.is_empty() or regions[regions.size() - 1] != r:
			regions.append(r)
		chunks["%d_%d" % [floori((p.x + 1024.0) / 256.0), floori((p.z + 1024.0) / 256.0)]] = true
	assert_true(regions.size() >= 3, "it crosses region borders: %s" % [regions])
	assert_true(regions.has("region.crownmarch") and regions.has("region.drowned_steps") and regions.has("region.greywood"),
		"the Crownmarch, the Drowned Steps and the Greywood")
	assert_true(chunks.size() >= 3, "through several chunks: %s" % [chunks.keys()])
	var length := 0.0
	for i in route.size() - 1:
		length += Vector2(route[i + 1].x - route[i].x, route[i + 1].z - route[i].z).length()
	assert_true(length > 300.0 and length < 600.0, "about 400 m: walked in about 48 s, under --autoplay=60 (%.0f m)" % length)


func test_a_walk_without_a_route_is_a_usage_error() -> void:
	assert_true(WorldWalk.NO_ROUTE.begins_with("usage:"), "the walk names its own mistake: %s" % WorldWalk.NO_ROUTE)
	assert_eq(WorldWalk.parse_options(PackedStringArray(["--route=1:2"])).route.size(), 1, "a route of one point")
	assert_eq(WorldWalk.parse_options(PackedStringArray(["--route=a:b;c"])).route.size(), 0, "malformed pairs are skipped")


## P39 (plan §6.3's world walk row: "path queries per tick"): each walked tick's path queries are counted
## from NavQuery's running total (the first tick only sets the base) and reported as p50 / p95 / max.
func test_the_walk_counts_its_path_queries_a_tick() -> void:
	var walk := WorldWalk.new()
	for total in [100, 103, 103, 111, 112, 112, 112, 112, 112, 112, 112]:
		walk.note_queries(total)
	var q := walk.path_queries_per_tick()
	assert_eq(int(q.ticks), 10, "ten ticks counted after the base")
	assert_eq(int(q.max), 8, "the busiest tick ran eight")
	assert_eq(int(q.p50), 0, "most ticks ran none")
	assert_eq(int(q.p95), 8, "the 95th percentile is the busiest of ten")
	assert_eq(WorldWalk.hist_percentile({}, 0.95), 0, "an empty walk reports 0")
	walk.free()
