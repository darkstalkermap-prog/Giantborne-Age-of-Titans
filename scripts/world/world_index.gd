class_name WorldIndex
extends Resource
## A level's world index (P20; plan M6-M9 §2.6, decision 14): a builder-written resource that
## answers positions, display names and arrival limits by id when the nodes are not loaded - a
## world chunk that is streamed out, a marker in another district, a checkpoint the player is
## travelling to. Quests, the map, the compass, fast travel, respawns, civilians and the title
## fall back to it. The Valley builder writes assets/world/index_valley.res; the world builder
## (P25) assets/world/index_world.res. The level record names it ("index"); for_level() loads it
## once per level id (cached; ResetHooks.AFTER_EACH clears the cache).
##
## Every position is in level space (the level root sits at the origin). Entries:
##   checkpoints  id -> {"position": Vector3, "yaw": float, "display_name": String,
##                       "kind": "shrine" | "waystone" | "checkpoint", "chunk": String,
##                       "fast_travel": bool, "requires_flags": PackedStringArray, "region": String,
##                       "district": String, "max_stage": int (ANY_STAGE = any)}
##   markers      id -> {"position", "kind" (objective | cover | elevation | formation | safe |
##                       patrol | bot_route), "chunk"}
##   areas        id -> {"position", "radius" (cylinder) | "size" (Vector3, box), "chunk"}
##   pois         id -> {"position", "radius", "kind", "region", "display_name", "chunk", "min_stage"}
##   exits        id -> {"position", "to_level", "to_checkpoint", "display_name"}
##   encounters   id -> {"center", "chunk", "faction"}
##   props        world id -> {"position", "chunk"} (quest targets and destroyable landmarks)
##   districts    [{"id", "display_name", "min": Vector2 (x, z), "max": Vector2 (x, z)}] (the Valley)
##   roads        a graph: nodes (positions), edges (pairs of node indices), and per edge its width,
##                min_stage and max_stage (the stages that may use it) and direct (1 = walk it in a
##                straight line, e.g. the Needle, which has no titan navmesh)
##   region grid  region_at(): cell (x, z) of cell_m metres from grid_origin; a byte k > 0 is
##                region_ids[k - 1], 0 is no region
##   map_image    the map picture (res:// path; "" = a vector map from districts and roads) and
##                map_bounds, the level-space rectangle (x, z) it covers.

## An arrival limit that never refuses (every stage up to 10 may arrive).
const ANY_STAGE := 10
## The entry dictionaries position_of() searches, in order.
const POSITION_TABLES := ["checkpoints", "markers", "areas", "pois", "exits", "props"]
## LevelMarker.Kind -> its name in the index.
const MARKER_KIND_NAMES := ["objective", "cover", "elevation", "formation", "safe", "patrol", "bot_route"]

@export var level_id := ""
@export var checkpoints := {}
@export var markers := {}
@export var areas := {}
@export var pois := {}
@export var exits := {}
@export var encounters := {}
@export var props := {}
@export var districts := []
@export var roads := {"nodes": PackedVector3Array(), "edges": PackedInt32Array(), "widths": PackedFloat32Array(),
	"min_stage": PackedByteArray(), "max_stage": PackedByteArray(), "direct": PackedByteArray()}
@export var region_grid := PackedByteArray()
@export var region_ids := PackedStringArray()
@export var grid_origin := Vector2()
@export var cell_m := 64.0
@export var grid_size := Vector2i()
@export var map_image := ""
@export var map_bounds := Rect2()

## level id -> WorldIndex, or null when the level has no index (for_level).
static var _cache: Dictionary = {}

var _adjacency: Dictionary = {}   ## node index -> [[neighbour, edge index], ...] (built by route())


# --------------------------------------------------------------------------- loading

## The index of a level: the resource its level record names ("index"), loaded once and cached.
## null when the level has none (no record, no "index", or the file is missing).
static func for_level(p_level_id: String) -> WorldIndex:
	if p_level_id == "":
		return null
	if _cache.has(p_level_id):
		return _cache[p_level_id] as WorldIndex
	var idx: WorldIndex = null
	var rec := GameData.get_record(p_level_id)
	var path := str(rec.get("index", "")) if str(rec.get("type", "")) == "level" else ""
	if path != "" and ResourceLoader.exists(path):
		idx = load(path) as WorldIndex
		if idx == null:
			push_warning("WorldIndex: %s is not a WorldIndex resource" % path)
	_cache[p_level_id] = idx
	return idx


## Forgets every cached index (ResetHooks.AFTER_EACH; a rebuilt index in a tool).
static func clear_cache() -> void:
	_cache.clear()


## Puts `index` in the cache for `p_level_id` (tests and tools: an index built in code).
static func put_cached(p_level_id: String, index: WorldIndex) -> void:
	_cache[p_level_id] = index


## The display name of `id` in the level's index ("" when there is no index or no name).
static func display_name_in(p_level_id: String, id: String) -> String:
	var idx := for_level(p_level_id)
	return idx.display_name(id) if idx != null else ""


# --------------------------------------------------------------------------- lookups

func is_empty() -> bool:
	for table: String in POSITION_TABLES:
		if not (get(table) as Dictionary).is_empty():
			return false
	return encounters.is_empty() and districts.is_empty()


## The position of any id the index knows (checkpoints, markers, areas, POIs, exits, props, then
## encounter centres); Vector3.INF when it is unknown.
func position_of(id: String) -> Vector3:
	if id == "":
		return Vector3.INF
	for table: String in POSITION_TABLES:
		var e: Variant = (get(table) as Dictionary).get(id)
		if typeof(e) == TYPE_DICTIONARY and typeof((e as Dictionary).get("position")) == TYPE_VECTOR3:
			return e.position
	var enc: Variant = encounters.get(id)
	if typeof(enc) == TYPE_DICTIONARY and typeof((enc as Dictionary).get("center")) == TYPE_VECTOR3:
		return enc.center
	return Vector3.INF


## The player-facing name of a checkpoint, POI, exit or district ("" when it has none).
func display_name(id: String) -> String:
	for table: String in ["checkpoints", "pois", "exits"]:
		var e: Variant = (get(table) as Dictionary).get(id)
		if typeof(e) == TYPE_DICTIONARY:
			return str((e as Dictionary).get("display_name", ""))
	for d: Variant in districts:
		if typeof(d) == TYPE_DICTIONARY and str(d.get("id", "")) == id:
			return str(d.get("display_name", ""))
	return ""


## The checkpoint entry ({} when the index does not know the id).
func checkpoint(id: String) -> Dictionary:
	var e: Variant = checkpoints.get(id)
	return e if typeof(e) == TYPE_DICTIONARY else {}


func has_checkpoint(id: String) -> bool:
	return checkpoints.has(id)


## The highest growth stage that may arrive at (travel to, respawn at) a checkpoint: its
## max_stage, ANY_STAGE when it has none or the index does not know it.
func max_stage_of(checkpoint_id: String) -> int:
	return int(checkpoint(checkpoint_id).get("max_stage", ANY_STAGE))


## Where a respawn at a checkpoint puts the player: its position, turned to its yaw.
## Transform3D with an INF origin when the checkpoint is unknown.
func spawn_transform(checkpoint_id: String) -> Transform3D:
	var e := checkpoint(checkpoint_id)
	if typeof(e.get("position")) != TYPE_VECTOR3:
		return Transform3D(Basis(), Vector3.INF)
	return Transform3D(Basis(Vector3.UP, float(e.get("yaw", 0.0))), e.position)


## The ids of the checkpoints, sorted.
func checkpoint_ids() -> PackedStringArray:
	var out := PackedStringArray(checkpoints.keys())
	out.sort()
	return out


## The id of the region whose grid cell holds `pos` ("" outside the grid or in a cell of none).
func region_at(pos: Vector3) -> String:
	if grid_size.x <= 0 or grid_size.y <= 0 or cell_m <= 0.0:
		return ""
	var cx := int(floor((pos.x - grid_origin.x) / cell_m))
	var cz := int(floor((pos.z - grid_origin.y) / cell_m))
	if cx < 0 or cz < 0 or cx >= grid_size.x or cz >= grid_size.y:
		return ""
	var i := cz * grid_size.x + cx
	if i >= region_grid.size():
		return ""
	var k := int(region_grid[i])
	return region_ids[k - 1] if k > 0 and k <= region_ids.size() else ""


## The id of the district whose rectangle holds `pos` ("" when none does; the Valley).
func district_at(pos: Vector3) -> String:
	for d: Variant in districts:
		if typeof(d) != TYPE_DICTIONARY:
			continue
		var lo: Variant = d.get("min")
		var hi: Variant = d.get("max")
		if typeof(lo) == TYPE_VECTOR2 and typeof(hi) == TYPE_VECTOR2 and pos.x >= lo.x and pos.x <= hi.x \
				and pos.z >= lo.y and pos.z <= hi.y:
			return str(d.get("id", ""))
	return ""


# --------------------------------------------------------------------------- roads

func road_nodes() -> PackedVector3Array:
	return roads.get("nodes", PackedVector3Array())


func road_edges() -> PackedInt32Array:
	return roads.get("edges", PackedInt32Array())


## The road node nearest `pos` on the ground plane, or -1 when there are no roads.
func nearest_road_node(pos: Vector3) -> int:
	var nodes := road_nodes()
	var best := -1
	var best_d := INF
	for i in nodes.size():
		var d := Vector2(nodes[i].x - pos.x, nodes[i].z - pos.z).length_squared()
		if d < best_d:
			best_d = d
			best = i
	return best


## True when road edge `e` may be used by a giant of `stage` (min_stage <= stage <= max_stage).
func edge_allowed(e: int, stage: int) -> bool:
	var lo: PackedByteArray = roads.get("min_stage", PackedByteArray())
	var hi: PackedByteArray = roads.get("max_stage", PackedByteArray())
	var min_s := int(lo[e]) if e < lo.size() else 0
	var max_s := int(hi[e]) if e < hi.size() else ANY_STAGE
	if max_s <= 0:
		max_s = ANY_STAGE
	return stage >= min_s and stage <= max_s


## The road route between the nodes nearest `from` and `to` over the edges a giant of `stage` may
## use (A*, straight-line costs): the positions of its nodes, both ends included. Empty when either
## end has no road node or no allowed path joins them. Callers walk their own short legs from
## `from` to the first node and from the last node to `to`.
func route(from: Vector3, to: Vector3, stage: int) -> PackedVector3Array:
	var out := PackedVector3Array()
	var start := nearest_road_node(from)
	var goal := nearest_road_node(to)
	if start < 0 or goal < 0:
		return out
	var nodes := road_nodes()
	if start == goal:
		out.append(nodes[start])
		return out
	var adj := _adjacency_table()
	var g := {start: 0.0}
	var came := {}
	var open := [start]
	var closed := {}
	while not open.is_empty():
		var best_i := 0
		var best_f := INF
		for k in open.size():
			var n: int = open[k]
			var f: float = float(g[n]) + nodes[n].distance_to(nodes[goal])
			if f < best_f:
				best_f = f
				best_i = k
		var cur: int = open[best_i]
		open.remove_at(best_i)
		if cur == goal:
			var path: Array = [goal]
			while came.has(path[0]):
				path.push_front(came[path[0]])
			for n: int in path:
				out.append(nodes[n])
			return out
		closed[cur] = true
		for pair: Array in adj.get(cur, []):
			var nb: int = pair[0]
			if closed.has(nb) or not edge_allowed(int(pair[1]), stage):
				continue
			var cost: float = float(g[cur]) + nodes[cur].distance_to(nodes[nb])
			if not g.has(nb) or cost < float(g[nb]):
				g[nb] = cost
				came[nb] = cur
				if not open.has(nb):
					open.append(nb)
	return out


func _adjacency_table() -> Dictionary:
	if not _adjacency.is_empty():
		return _adjacency
	var edges := road_edges()
	var n_nodes := road_nodes().size()
	for e in range(edges.size() / 2):
		var a := edges[2 * e]
		var b := edges[2 * e + 1]
		if a < 0 or b < 0 or a >= n_nodes or b >= n_nodes:
			continue
		if not _adjacency.has(a):
			_adjacency[a] = []
		if not _adjacency.has(b):
			_adjacency[b] = []
		(_adjacency[a] as Array).append([b, e])
		(_adjacency[b] as Array).append([a, e])
	return _adjacency


## Adds an edge between two positions (merging nodes closer than merge_m). Builders and tests. A
## segment shorter than merge_m adds nothing (no stray node).
func add_road(a: Vector3, b: Vector3, width: float, min_stage := 0, max_stage := ANY_STAGE,
		direct := false, merge_m := 0.5) -> void:
	if a.distance_to(b) <= merge_m:
		return
	var ia := _road_node(a, merge_m)
	var ib := _road_node(b, merge_m)
	if ia == ib:
		return
	var edges: PackedInt32Array = roads.get("edges", PackedInt32Array())
	edges.append(ia)
	edges.append(ib)
	roads["edges"] = edges
	var widths: PackedFloat32Array = roads.get("widths", PackedFloat32Array())
	widths.append(width)
	roads["widths"] = widths
	for key: String in ["min_stage", "max_stage", "direct"]:
		var arr: PackedByteArray = roads.get(key, PackedByteArray())
		match key:
			"min_stage":
				arr.append(clampi(min_stage, 0, 255))
			"max_stage":
				arr.append(clampi(max_stage, 0, 255))
			"direct":
				arr.append(1 if direct else 0)
		roads[key] = arr
	_adjacency.clear()


func _road_node(p: Vector3, merge_m: float) -> int:
	var nodes: PackedVector3Array = roads.get("nodes", PackedVector3Array())
	for i in nodes.size():
		if nodes[i].distance_to(p) <= merge_m:
			return i
	nodes.append(p)
	roads["nodes"] = nodes
	return nodes.size() - 1


# --------------------------------------------------------------------------- building

## Fills the checkpoint, marker, area, exit and prop tables from a built level scene (`root`, in or
## out of the tree), in level space; shrines take their record's display name, waystones and exits
## their display_name property. Encounters come from the encounter records of `level_id`, districts
## from its level record. Builders call it, then add what the scene does not hold (roads, POIs,
## the region grid, max_stage limits) and save the resource.
static func build_from_scene(root: Node3D, p_level_id: String) -> WorldIndex:
	var idx := WorldIndex.new()
	idx.level_id = p_level_id
	idx._scan(root, root)
	var rec := GameData.get_record(p_level_id)
	if typeof(rec.get("districts")) == TYPE_ARRAY:
		for d: Variant in rec.districts:
			if typeof(d) != TYPE_DICTIONARY or typeof(d.get("min_m")) != TYPE_ARRAY or typeof(d.get("max_m")) != TYPE_ARRAY:
				continue
			idx.districts.append({"id": str(d.get("id", "")), "display_name": str(d.get("display_name", "")),
				"min": Vector2(float(d.min_m[0]), float(d.min_m[2])), "max": Vector2(float(d.max_m[0]), float(d.max_m[2]))})
	for c: String in idx.checkpoints:
		(idx.checkpoints[c] as Dictionary)["district"] = idx.district_at((idx.checkpoints[c] as Dictionary).position)
	var ids := GameData.ids_of_type("encounter")
	ids.sort()
	for id: String in ids:
		var e := GameData.get_record(id)
		if str(e.get("level", "")) != p_level_id or typeof(e.get("center_m")) != TYPE_ARRAY:
			continue
		var faction := ""
		for sp: Variant in e.get("spawns", []):
			if typeof(sp) == TYPE_DICTIONARY and str(sp.get("faction", "")) != "":
				faction = str(sp.faction)
				break
		idx.encounters[id] = {"center": _vec3(e.center_m), "chunk": "", "faction": faction}
	return idx


func _scan(node: Node, root: Node3D) -> void:
	for child in node.get_children():
		if child is Shrine:
			_add_shrine(child as Shrine, root)
		elif child is CheckpointMarker:
			_add_checkpoint(child as CheckpointMarker, root)
		elif child is LevelMarker:
			var m := child as LevelMarker
			if m.marker_id != "":
				markers[m.marker_id] = {"position": rel_transform(m, root).origin,
					"kind": MARKER_KIND_NAMES[int(m.kind)] if int(m.kind) < MARKER_KIND_NAMES.size() else "objective",
					"chunk": ""}
		elif child is AreaTrigger:
			_add_area(child as AreaTrigger, root)
		elif child is LevelExit:
			var x := child as LevelExit
			if x.exit_id != "":
				exits[x.exit_id] = {"position": rel_transform(x, root).origin, "to_level": x.to_level,
					"to_checkpoint": x.to_checkpoint, "display_name": x.display_name}
		elif "world_id" in child and str(child.get("world_id")) != "" and child is Node3D:
			props[str(child.get("world_id"))] = {"position": rel_transform(child as Node3D, root).origin, "chunk": ""}
		_scan(child, root)


func _add_shrine(s: Shrine, root: Node3D) -> void:
	if s.world_id == "":
		return
	var spawn := s.get_node_or_null("SpawnPoint") as CheckpointMarker
	var t := rel_transform(spawn if spawn != null else s, root)
	var rec := GameData.get_record(s.shrine_id)
	checkpoints[s.world_id] = _checkpoint_entry(t, str(rec.get("display_name", "Shrine")), "shrine",
		PackedStringArray())


func _add_checkpoint(c: CheckpointMarker, root: Node3D) -> void:
	if c.checkpoint_id == "" or checkpoints.has(c.checkpoint_id):
		return
	var kind := "waystone" if c is Waystone else "checkpoint"
	var flags := PackedStringArray()
	var title := ""
	if c is Waystone:
		flags = (c as Waystone).requires_flags.duplicate()
		title = (c as Waystone).display_name
	checkpoints[c.checkpoint_id] = _checkpoint_entry(rel_transform(c, root), title, kind, flags)


static func _checkpoint_entry(t: Transform3D, title: String, kind: String, flags: PackedStringArray) -> Dictionary:
	var fwd := -t.basis.z
	fwd.y = 0.0
	var yaw := 0.0 if fwd.length_squared() < 1e-8 else TargetingRules.yaw_of(fwd)
	return {"position": t.origin, "yaw": yaw, "display_name": title, "kind": kind, "chunk": "",
		"fast_travel": kind != "checkpoint", "requires_flags": flags, "region": "", "district": "",
		"max_stage": ANY_STAGE}


func _add_area(a: AreaTrigger, root: Node3D) -> void:
	if a.area_id == "":
		return
	var entry := {"position": rel_transform(a, root).origin, "chunk": ""}
	for child in a.get_children():
		var cs := child as CollisionShape3D
		if cs == null or cs.shape == null:
			continue
		if cs.shape is CylinderShape3D:
			entry["radius"] = (cs.shape as CylinderShape3D).radius
		elif cs.shape is SphereShape3D:
			entry["radius"] = (cs.shape as SphereShape3D).radius
		elif cs.shape is BoxShape3D:
			entry["size"] = (cs.shape as BoxShape3D).size
		break
	areas[a.area_id] = entry


## The transform of `node` relative to `root` (works outside the scene tree: builders).
static func rel_transform(node: Node3D, root: Node3D) -> Transform3D:
	var t := Transform3D.IDENTITY
	var n: Node = node
	while n != null and n != root:
		if n is Node3D:
			t = (n as Node3D).transform * t
		n = n.get_parent()
	return t


static func _vec3(a: Variant) -> Vector3:
	if typeof(a) != TYPE_ARRAY or (a as Array).size() < 3:
		return Vector3.INF
	return Vector3(float(a[0]), float(a[1]), float(a[2]))
