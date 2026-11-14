extends IntegrationSuite
## P25 (plan M6-M9 §3.8, §5.5): the world can be walked everywhere it should be. On the titan layer
## (the stage-4 to stage-6 giant's), with the gate regions a stage opens (bit 32 at stage 4, 64 at
## 5, 128 at 6; NavMaps joins them to the titan map) and the seals' links open, every shrine,
## waystone, checkpoint, exit, settlement green and POI centre is reachable from the start
## checkpoint (world.cp.kingsgate_shelf) at the stage it needs: 4 unless its POI needs more, the
## sealed places' caches through their seals at 5 or 6. The Needle's side is walked: a stage-3 giant
## goes through the 5 m slot into the Hidden Grove on the streamed world (WorldWalk, the stick; M8 gate,
## F21: the walk grows the giant to stage 3 first and the test checks it walked at stage 3).
## Below their stage the gates hold: the Moot's ring and the Giant's Stair (a stage-5 giant goes
## round by the Ironway), and the vaults while their rockfalls stand.
##
## Every interactable of the region tables (caches, cairns, seals, great pines) is reached too, at
## the stage its POI or its own record needs (the builder check of §3.8, run here: the navigation
## server's maps are a test's, not the offline bake's).
##
## Exceptions by design (M7): Fort Aldmere's bailey stays shut behind its indestructible gate until
## P36 (its green outside the gate is checked instead), and the two ledge caches (the Titan's
## shoulder, the ridge eyrie) are taken from the ground below their spires at stage 6.

const LEVEL := "level.world"
const START := "world.cp.kingsgate_shelf"
const TITAN := 16
const GATE_BITS := {4: 32, 5: 64, 6: 128}
## A target counts as reached when the path ends this close to it on the ground plane (a stage-4
## giant's reach and the titan agent's 4 m radius around props and pads) and within this height.
const REACH_M := 15.0
const REACH_UP_M := 12.0
## The caches inside sealed places, reached through their seals at the stage the seal needs.
const SEALED := {"world.crownmarch.statue_cache": 5, "world.crownmarch.vault_cache": 5, "world.greywood.old_root_cache": 5,
	"world.drowned.vault_cache": 5, "world.aldmere.armoury_cache": 5, "world.greywood.grove_cache": 5,
	"world.drowned.shoulder_cache": 6, "world.aldmere.eyrie_cache": 6}
## The caches inside vaults behind rockfalls (walls on three sides).
const VAULTS := ["world.crownmarch.vault_cache", "world.drowned.vault_cache", "world.aldmere.armoury_cache"]
## POI centres that are not titan ground: checked by a stand-in ("green": the POI's green; else an
## index id). Fort Aldmere's bailey is shut in M7; the Needle's centre is the 5 m slot (walked below
## by the stage-3 giant), its mouth's cache stands in.
const STAND_INS := {"poi.fort_aldmere": "green", "poi.the_needle": "world.greywood.needle_cache"}
## How close a path must come to a cache inside a sealed place (the titan's 4 m radius inside a
## vault's walls): reaching it means being in the vault, not beside its back wall.
const INSIDE_M := 6.0
## The Needle: its outer mouth to the Hidden Grove's floor (WorldWalk waypoints, x:z).
const NEEDLE_ROUTE := [Vector2(-398, 76), Vector2(-412, 60), Vector2(-436, 36), Vector2(-458, 14), Vector2(-476, -4)]
const GROVE_CENTRE := Vector2(-480, -10)
const GROVE_FLOOR_R := 42.0
## The region tables and their sections of interactables (each entry's "poi" and "requires_stage").
const LAYOUT_DIR := "res://tools/data/world/"
const LAYOUT_REGIONS := ["crownmarch", "greywood", "drowned_steps", "aldmere", "stonehold"]
const INTERACTABLES := ["caches", "cairns", "secrets", "pines"]

var _nav: NavMaps = null
var _links: Array = []


func after_each() -> void:
	for l: RID in _links:
		NavigationServer3D.free_rid(l)
	_links.clear()
	if _nav != null:
		_nav.free_all()
		_nav = null
	await super()


static func mask_for(stage: int) -> int:
	var m := TITAN
	for s: int in GATE_BITS:
		if stage >= s:
			m |= int(GATE_BITS[s])
	return m


## Every chunk's navmeshes on the level's maps (the titan map with its gate regions) and every
## props part's links, open (the seals heaved), on the titan map.
func _build_maps() -> void:
	var w: Dictionary = GameData.get_record(LEVEL).world
	_nav = NavMaps.new()
	_nav.setup(w.nav_layers, (w.gate_bits as Dictionary).values(), TITAN, true)
	for z in int(w.grid[1]):
		for x in int(w.grid[0]):
			var d := load("%s/c%d_%d.res" % [w.chunk_dir, x, z]) as ChunkData
			for bit: int in d.nav:
				if bit == TITAN or GATE_BITS.values().has(bit):
					_nav.add_region(d.chunk_id, bit, load(str(d.nav[bit])) as NavigationMesh, Transform3D(Basis(), d.origin))
			for path: String in d.props_scenes:
				var part := (load(path) as PackedScene).instantiate() as Node3D
				for link: NavigationLink3D in part.find_children("*", "NavigationLink3D", true, false):
					if (link.navigation_layers & TITAN) == 0:
						continue
					var xf := Transform3D(Basis(), d.origin) * _local_to(part, link)
					var rid := NavigationServer3D.link_create()
					NavigationServer3D.link_set_map(rid, _nav.map_for(TITAN))
					NavigationServer3D.link_set_navigation_layers(rid, TITAN)
					NavigationServer3D.link_set_bidirectional(rid, true)
					NavigationServer3D.link_set_start_position(rid, xf * link.start_position)
					NavigationServer3D.link_set_end_position(rid, xf * link.end_position)
					NavigationServer3D.link_set_enabled(rid, true)
					_links.append(rid)
				part.free()
	await get_tree().physics_frame
	await get_tree().physics_frame


## A node's transform relative to an ancestor (outside the tree).
static func _local_to(ancestor: Node3D, node: Node3D) -> Transform3D:
	var xf := Transform3D.IDENTITY
	var n: Node = node
	while n != null and n != ancestor:
		if n is Node3D:
			xf = (n as Node3D).transform * xf
		n = n.get_parent()
	return xf


## The titan path from `from` to `to` with the mask of `stage`.
func _path(from: Vector3, to: Vector3, stage: int) -> PackedVector3Array:
	# the world's queries search every polygon (NavQuery, max_polygons 0): map_get_path stops at
	# 4,096 and a kingdom-long path needs more
	var q := NavigationPathQueryParameters3D.new()
	q.map = _nav.map_for(TITAN)
	q.start_position = from
	q.target_position = to
	q.navigation_layers = mask_for(stage)
	q.path_search_max_polygons = 0
	q.path_search_max_distance = 0.0
	var res := NavigationPathQueryResult3D.new()
	NavigationServer3D.query_path(q, res)
	return res.path


## [reached, the path's end] from the start to `to` with the titan mask of `stage`: the path ends
## within `within` metres of `to` on the ground plane.
func _reach(from: Vector3, to: Vector3, stage: int, within := REACH_M) -> Array:
	var path := _path(from, to, stage)
	if path.is_empty():
		return [false, Vector3.INF]
	var end := path[path.size() - 1]
	var ok := Vector2(end.x - to.x, end.z - to.z).length() <= within and absf(end.y - to.y) <= REACH_UP_M
	return [ok, end]


## The length of the titan path from `from` to `to` at `stage` (INF when it does not reach `to`).
func _length(from: Vector3, to: Vector3, stage: int) -> float:
	var path := _path(from, to, stage)
	if path.is_empty() or not bool(_reach(from, to, stage)[0]):
		return INF
	var m := 0.0
	for i in range(1, path.size()):
		m += path[i - 1].distance_to(path[i])
	return m


func test_every_place_is_reachable_on_the_titan_layer_at_its_stage() -> void:
	await _build_maps()
	var idx := WorldIndex.for_level(LEVEL)
	var start := idx.position_of(START)
	assert_true(start != Vector3.INF, "the start checkpoint is in the index")
	var targets := {}   # name -> [position, stage]
	var poi_stage := {}   # POI id -> the stage it needs (4 at least)
	for id: String in idx.checkpoints:
		targets[id] = [idx.checkpoints[id].position, 4]
	for id: String in idx.exits:
		targets[id] = [idx.exits[id].position, 4]
	for poi: Dictionary in GameData.records_of_type("poi"):
		if str(poi.get("level", "")) != LEVEL:
			continue
		var stage := maxi(4, int(poi.get("min_stage", 0)))
		poi_stage[str(poi.id)] = stage
		if poi.has("green_m"):
			var g: Array = poi.green_m
			targets[str(poi.id) + " green"] = [Vector3(float(g[0]), float(g[1]), float(g[2])), stage]
		if str(poi.kind) == "secret":
			continue
		if STAND_INS.has(str(poi.id)):
			var stand := str(STAND_INS[str(poi.id)])
			if stand != "green":
				targets[str(poi.id) + " (" + stand + ")"] = [idx.position_of(stand), stage]
			continue
		targets[str(poi.id)] = [idx.pois[str(poi.id)].position, stage]
	for id: String in SEALED:
		targets[id] = [idx.props[id].position, int(SEALED[id]), INSIDE_M if VAULTS.has(id) else REACH_M]
	var interactables := 0
	for region: String in LAYOUT_REGIONS:
		var table: Variant = JSON.parse_string(FileAccess.get_file_as_string(LAYOUT_DIR + region + ".json"))
		assert_true(typeof(table) == TYPE_DICTIONARY, "the %s table reads" % region)
		if typeof(table) != TYPE_DICTIONARY:
			continue
		for section: String in INTERACTABLES:
			for it: Dictionary in (table as Dictionary).get(section, []):
				var id := str(it.id)
				interactables += 1
				if targets.has(id):
					continue
				var stage := maxi(int(poi_stage.get(str(it.get("poi", "")), 4)), int(it.get("requires_stage", 4)))
				targets[id] = [idx.position_of(id), stage]
	assert_true(interactables >= 45, "the caches, cairns, seals and great pines are among them (%d)" % interactables)
	var failures := PackedStringArray()
	for name: String in targets:
		var t: Array = targets[name]
		var r := _reach(start, t[0], int(t[1]), float(t[2]) if t.size() > 2 else REACH_M)
		if not bool(r[0]):
			failures.append("%s at %s (stage %d; the path ends at %s)" % [name, t[0], t[1], r[1]])
	assert_eq(failures, PackedStringArray(), "every place is reachable at its stage from the shelf (%d checked)" % targets.size())
	print("    test_world_reachability: %d places reachable on the titan layer" % (targets.size() - failures.size()))


func test_the_gates_hold_below_their_stage() -> void:
	await _build_maps()
	var idx := WorldIndex.for_level(LEVEL)
	var start := idx.position_of(START)
	# the Moot's ring: its gate stones admit a giant of stage 6 only
	assert_false(bool(_reach(start, idx.position_of("world.marker.stone_throne"), 5)[0]), "the Stone Throne is out of reach at stage 5")
	assert_true(bool(_reach(start, idx.position_of("world.marker.stone_throne"), 6)[0]), "and in reach at stage 6")
	# the Giant's Stair: a stage-6 giant climbs it; below stage 6 the way up is the Ironway's
	var foot: Vector3 = idx.pois["poi.giants_stair"].position
	var top: Vector3 = idx.pois["poi.stair_top"].position
	var climb := _length(foot, top, 6)
	var round_way := _length(foot, top, 5)
	assert_true(climb < 250.0, "a stage-6 giant climbs the Giant's Stair (%.0f m)" % climb)
	assert_true(round_way > 4.0 * climb, "a stage-5 giant goes round by the Ironway (%.0f m)" % round_way)
	print("    test_world_reachability: the Giant's Stair climbed in %.0f m at stage 6, %.0f m round at stage 5" % [climb, round_way])
	# the sealed vaults stay shut while their seals hold (links closed: nothing but the open maps)
	for l: RID in _links:
		NavigationServer3D.link_set_enabled(l, false)
	await get_tree().physics_frame
	await get_tree().physics_frame
	for id: String in VAULTS:
		assert_false(bool(_reach(start, idx.props[id].position, 6, INSIDE_M)[0]), "%s is shut while its rockfall stands" % id)


func test_a_stage_3_giant_walks_through_the_needle() -> void:
	var w := (load(str(GameData.get_record(LEVEL).scene)) as PackedScene).instantiate() as WorldRoot
	world.add_child(w)
	w.streamer.deterministic = true
	TestSpawn.disable_all_ai(w)
	var p := w.player()
	var first := Vector3(NEEDLE_ROUTE[0].x, 0.0, NEEDLE_ROUTE[0].y)
	var guard := 0
	while not w.streamer.ring_ready(first) and guard < 400:
		w.streamer.load_ring_slice(first)
		guard += 1
	first.y = w.height_at(first) + 0.5
	p.global_position = first
	var route := PackedVector3Array()
	for q: Vector2 in NEEDLE_ROUTE:
		route.append(Vector3(q.x, 0.0, q.y))
	var walk := WorldWalk.new()
	walk.name = "WorldWalk"
	add_child(walk)
	walk.start(p, w, null, {"route": route, "speed": 0.0, "stage": 3})
	var ticks := 0
	while not walk.done and ticks < 60 * 90:
		await step_ticks(1)
		ticks += 1
	var r := walk.result()
	var end := Vector2(p.global_position.x, p.global_position.z)
	assert_eq(str(r.get("stage_error", "")), "", "the giant was grown to stage 3 (M8 gate, F21)")
	assert_eq(int(r.get("stage", 0)), 3, "the walk was a stage-3 giant's")
	assert_eq(p.current_growth_stage(), 3, "a stage-3 giant stands in the grove")
	assert_true(walk.done and bool(r.finished), "the walk ended (%d ticks)" % ticks)
	assert_eq(int(r.get("stuck_teleports", -1)), 0, "the stage-3 giant was never stuck in the slot")
	assert_true(end.distance_to(GROVE_CENTRE) <= GROVE_FLOOR_R, "it stands on the Hidden Grove's floor (%.0f m from its centre)" % end.distance_to(GROVE_CENTRE))
	walk.queue_free()
	w.queue_free()
	await get_tree().process_frame
