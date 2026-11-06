class_name WorldIndexWriter
extends RefCounted
## The world's index (P25; plan M6-M9 §2.6, decision 14): assets/world/index_world.res, written
## by the world builder from what it placed. Its tables (WorldIndex):
##   checkpoints  every shrine, waystone and plain checkpoint of the chunk parts (display names,
##                kind, chunk, region, the layout's max_stage, fast travel for shrines and waystones)
##   markers, areas, exits   from the chunk parts (each with its chunk)
##   props        every scripted prop with a world id (seals, caches, cairns, gates, pines) and every
##                static layout element with an id that is a landmark, a quest target or
##                quest-critical: {"position", "chunk", "landmark", "quest_target", "quest_critical",
##                "indestructible", "kind"}
##   pois         from the poi records of level.world (position from the record, its chunk)
##   encounters   the encounter records of level.world (centre, chunk, faction)
##   roads        the staged road graph: a node every NODE_EVERY_M along every road (each polyline
##                vertex a node, so junctions meet), loose road ends joined to the nearest other road
##                within ROAD_LINK_M, connectors from every POI, checkpoint, exit and green to the
##                nearest node (their min_stage from the POI that needs a stage), the layout's
##                extra edges (the Needle's direct edge with max_stage 4, the Grove's rockfall route
##                with min_stage 5)
##   region grid  64 m cells, each its region's 1-based index (the region tables' bounds)
##   map          map_image (the picture) and map_bounds (the world's rectangle)
## Tools only.

const NODE_EVERY_M := 40.0
const ROAD_LINK_M := 26.0
## A point within this of a road node needs no connector.
const CONNECT_WITHIN_M := 30.0
const CELL_M := 64.0


## The index of the built world: `root` holds every chunk part at its chunk origin (built in
## memory); `statics` are the static elements with ids ([{"el", "position": Vector3}]).
static func build(root: Node3D, layout: Dictionary, feats: WorldFeatures, field: HeightField, statics: Array,
		map_path: String) -> WorldIndex:
	var idx := WorldIndex.build_from_scene(root, feats.level_id)
	var items: Array = layout.get("items", [])
	var by_id := {}
	for it: Dictionary in items:
		if str(it.get("id", "")) != "":
			by_id[str(it.id)] = it
	for id: String in idx.checkpoints:
		var e: Dictionary = idx.checkpoints[id]
		var pos: Vector3 = e.position
		e["chunk"] = feats.chunk_id_of(pos.x, pos.z)
		e["region"] = feats.region_id_at(pos.x, pos.z)
		var it: Dictionary = by_id.get(id, {})
		e["max_stage"] = int(it.get("max_stage", WorldIndex.ANY_STAGE))
		if str(e.get("display_name", "")) == "" and it.has("display_name"):
			e["display_name"] = str(it.display_name)
		if str(it.get("_section", "")) == "checkpoints":
			e["fast_travel"] = false
	for table: String in ["markers", "areas", "props"]:
		var t: Dictionary = idx.get(table)
		for id: String in t:
			var p: Vector3 = (t[id] as Dictionary).position
			(t[id] as Dictionary)["chunk"] = feats.chunk_id_of(p.x, p.z)
	for id: String in idx.props:
		var it: Dictionary = by_id.get(id, {})
		var e: Dictionary = idx.props[id]
		e["landmark"] = bool(it.get("landmark", false))
		e["quest_target"] = bool(it.get("quest_target", false))
		e["quest_critical"] = bool(it.get("quest_critical", false))
		e["indestructible"] = bool(it.get("indestructible", false))
		e["kind"] = str(it.get("kind", it.get("seal", it.get("_section", ""))))
	for s: Dictionary in statics:
		var el: Dictionary = s.el
		var pos: Vector3 = s.position
		idx.props[str(el.id)] = {"position": pos, "chunk": feats.chunk_id_of(pos.x, pos.z),
			"landmark": bool(el.get("landmark", false)), "quest_target": bool(el.get("quest_target", false)),
			"quest_critical": bool(el.get("quest_critical", false)),
			# a static structure takes no hits: indestructible by construction
			"indestructible": true, "kind": str(el.get("kind", ""))}
	for id: String in idx.encounters:
		var c: Vector3 = (idx.encounters[id] as Dictionary).center
		(idx.encounters[id] as Dictionary)["chunk"] = feats.chunk_id_of(c.x, c.z)
	_pois(idx, feats, field)
	_roads(idx, layout, feats, field)
	_region_grid(idx, feats)
	idx.map_image = map_path
	idx.map_bounds = feats.world_rect()
	return idx


static func _v3(a: Variant, field: HeightField) -> Vector3:
	var arr: Array = a
	if arr.size() >= 3:
		return Vector3(float(arr[0]), float(arr[1]), float(arr[2]))
	return Vector3(float(arr[0]), field.sample(float(arr[0]), float(arr[1])), float(arr[1]))


## The POI records of the level: their positions (the record's x and z on the built ground).
static func _pois(idx: WorldIndex, feats: WorldFeatures, field: HeightField) -> void:
	var ids := GameData.ids_of_type("poi")
	ids.sort()
	for id: String in ids:
		var r := GameData.get_record(id)
		if str(r.get("level", "")) != feats.level_id:
			continue
		var p: Array = r.position_m
		var pos := Vector3(float(p[0]), field.sample(float(p[0]), float(p[2])), float(p[2]))
		idx.pois[id] = {"position": pos, "radius": float(r.radius_m), "kind": str(r.kind), "region": str(r.get("region", "")),
			"display_name": str(r.get("display_name", "")), "chunk": feats.chunk_id_of(pos.x, pos.z),
			"min_stage": int(r.get("min_stage", 0))}


## A road polyline's nodes: every vertex, and points every NODE_EVERY_M between them (on the ground).
static func road_points(pts: PackedVector2Array, field: HeightField) -> PackedVector3Array:
	var out := PackedVector3Array()
	for k in pts.size() - 1:
		var a := pts[k]
		var b := pts[k + 1]
		var n := maxi(1, int(ceil(a.distance_to(b) / NODE_EVERY_M)))
		for i in n:
			var p := a.lerp(b, float(i) / n)
			out.append(Vector3(p.x, field.sample(p.x, p.y), p.y))
	var last := pts[pts.size() - 1]
	out.append(Vector3(last.x, field.sample(last.x, last.y), last.y))
	return out


static func _add_polyline(idx: WorldIndex, pts: PackedVector3Array, width: float, min_stage: int, max_stage: int,
		direct: bool) -> void:
	for k in pts.size() - 1:
		idx.add_road(pts[k], pts[k + 1], width, min_stage, max_stage, direct, 0.5)


static func _roads(idx: WorldIndex, layout: Dictionary, feats: WorldFeatures, field: HeightField) -> void:
	var ends: Array = []   # [node position, road id]
	for road: Dictionary in feats.roads:
		var pts := road_points(road.points, field)
		_add_polyline(idx, pts, float(road.width), int(road.min_stage), int(road.max_stage), bool(road.direct))
		ends.append([pts[0], str(road.id)])
		ends.append([pts[pts.size() - 1], str(road.id)])
	# the layout's extra edges (rides, the Needle, the Grove's rockfall route)
	for extra: Dictionary in layout.world.get("index_edges", []):
		var p2 := PackedVector2Array()
		for p: Array in extra.points:
			p2.append(Vector2(float(p[0]), float(p[1])))
		var pts := road_points(p2, field)
		_add_polyline(idx, pts, float(extra.get("width_m", 12.0)), int(extra.get("min_stage", 0)),
			int(extra.get("max_stage", WorldIndex.ANY_STAGE)), bool(extra.get("direct", false)))
		ends.append([pts[0], str(extra.get("id", ""))])
		ends.append([pts[pts.size() - 1], str(extra.get("id", ""))])
	# loose ends: joined to the nearest node within ROAD_LINK_M that is not right next to them
	for e: Array in ends:
		var p: Vector3 = e[0]
		var nodes := idx.road_nodes()
		var own := idx.nearest_road_node(p)
		var degree := _degree(idx, own)
		if degree != 1:
			continue
		var best := -1
		var best_d := ROAD_LINK_M
		for i in nodes.size():
			if i == own or _adjacent(idx, own, i):
				continue
			var d := Vector2(nodes[i].x - p.x, nodes[i].z - p.z).length()
			if d < best_d:
				best_d = d
				best = i
		if best >= 0:
			idx.add_road(nodes[own], nodes[best], 10.0)
	# connectors: every POI, checkpoint, exit and green to the nearest road node
	var points: Array = []   # [position, min_stage]
	for id: String in idx.pois:
		points.append([(idx.pois[id] as Dictionary).position, int((idx.pois[id] as Dictionary).get("min_stage", 0))])
	for id: String in idx.checkpoints:
		points.append([(idx.checkpoints[id] as Dictionary).position, 0])
	for id: String in idx.exits:
		points.append([(idx.exits[id] as Dictionary).position, 0])
	for id: String in idx.props:
		if id.ends_with("_green"):
			points.append([(idx.props[id] as Dictionary).position, 0])
	for pt: Array in points:
		var p: Vector3 = pt[0]
		var n := idx.nearest_road_node(p)
		if n < 0:
			continue
		var q := idx.road_nodes()[n]
		if Vector2(q.x - p.x, q.z - p.z).length() <= CONNECT_WITHIN_M:
			continue
		var line := road_points(PackedVector2Array([Vector2(q.x, q.z), Vector2(p.x, p.z)]), field)
		_add_polyline(idx, line, 10.0, int(pt[1]), WorldIndex.ANY_STAGE, false)


static func _degree(idx: WorldIndex, node: int) -> int:
	var edges := idx.road_edges()
	var n := 0
	for k in range(edges.size()):
		if edges[k] == node:
			n += 1
	return n


static func _adjacent(idx: WorldIndex, a: int, b: int) -> bool:
	var edges := idx.road_edges()
	for e in range(edges.size() / 2):
		if (edges[2 * e] == a and edges[2 * e + 1] == b) or (edges[2 * e] == b and edges[2 * e + 1] == a):
			return true
	return false


## The region grid: CELL_M cells over the world, each its region's index (the cell's centre,
## clamped into the interior: the rim takes the region beside it).
static func _region_grid(idx: WorldIndex, feats: WorldFeatures) -> void:
	var r := feats.world_rect()
	idx.region_ids = feats.region_ids.duplicate()
	idx.cell_m = CELL_M
	idx.grid_origin = r.position
	idx.grid_size = Vector2i(int(r.size.x / CELL_M), int(r.size.y / CELL_M))
	var grid := PackedByteArray()
	grid.resize(idx.grid_size.x * idx.grid_size.y)
	for j in idx.grid_size.y:
		for i in idx.grid_size.x:
			grid[j * idx.grid_size.x + i] = feats.region_index(r.position.x + (i + 0.5) * CELL_M,
				r.position.y + (j + 0.5) * CELL_M)
	idx.region_grid = grid
