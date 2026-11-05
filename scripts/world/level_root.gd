class_name LevelRoot
extends Node3D
## The root node of a level built for encounters (the Valley, the director test level; plan
## §2.7.4, §2.12). It names the level's `level` record and answers the lookups gameplay needs:
## markers, checkpoints, area triggers and patrol routes by id, the district at a point, the
## player, and the navigation map and regions. Group "level_root": ProjectileSystem parents
## its projectiles here, EnemyActor snaps flee points to nav_region(), and GameSession reads
## the start checkpoint of the level record named by level_id.
##
## Expected children (the builders make them): Navigation/{Human,Large,Giant,SmallGiant}
## (NavigationRegion3D on nav layers 1/2/4/8), Markers/<kind>/<marker> (LevelMarker),
## Markers/Patrol/<route>/<n> (a route node whose Node3D children are its points; the node is
## named after the route id with dots as underscores, String.validate_node_name()), Triggers/
## (AreaTrigger), Spawns/PlayerSpawn, Spawned (the EncounterDirector's actors), Player and
## EncounterDirector.
##
## Lookups are built once at _ready from the groups (descendants of this root only) and
## rebuilt when an id is not found, so nodes added later (tests) are found too.

const GROUP := "level_root"
## Navigation layer bit -> the child of Navigation that holds it (plan §2.2).
const NAV_REGION_NAMES := {1: "Human", 2: "Large", 4: "Giant", 8: "SmallGiant"}

## The id of this level's `level` record (budget, AI LOD, districts, start checkpoint).
@export var level_id := "level.valley"

var _markers: Dictionary = {}       # marker_id -> LevelMarker
var _checkpoints: Dictionary = {}   # checkpoint_id -> CheckpointMarker
var _areas: Dictionary = {}         # area_id -> AreaTrigger
var _player_ref: WeakRef = null


func _enter_tree() -> void:
	add_to_group(GROUP)


func _ready() -> void:
	rebuild_lookups()


## The level record named by level_id ({} when there is none, e.g. a level without data).
func level_record() -> Dictionary:
	var rec := GameData.get_record(level_id)
	return rec if str(rec.get("type", "")) == "level" else {}


## Re-reads the groups (called at _ready and when a lookup misses).
func rebuild_lookups() -> void:
	_markers.clear()
	_checkpoints.clear()
	_areas.clear()
	if not is_inside_tree():
		return
	var tree := get_tree()
	for n in tree.get_nodes_in_group(LevelMarker.GROUP):
		var m := n as LevelMarker
		if m != null and m.marker_id != "" and _owns(m) and not _markers.has(m.marker_id):
			_markers[m.marker_id] = m
	for n in tree.get_nodes_in_group("checkpoints"):
		var c := n as CheckpointMarker
		if c != null and c.checkpoint_id != "" and _owns(c) and not _checkpoints.has(c.checkpoint_id):
			_checkpoints[c.checkpoint_id] = c
	for n in tree.get_nodes_in_group(AreaTrigger.GROUP):
		var a := n as AreaTrigger
		if a != null and a.area_id != "" and _owns(a) and not _areas.has(a.area_id):
			_areas[a.area_id] = a


## The LevelMarker with this marker_id (null when there is none).
func marker(id: String) -> Node3D:
	return _lookup(_markers, id) as Node3D


## The checkpoint marker (CheckpointMarker, Waystone or a shrine's SpawnPoint) with this id.
func checkpoint(id: String) -> Node3D:
	return _lookup(_checkpoints, id) as Node3D


## The AreaTrigger with this area_id (null when there is none).
func area(id: String) -> AreaTrigger:
	return _lookup(_areas, id) as AreaTrigger


## Markers/Patrol/<route> for a route id such as "valley.patrol.wolves_a" (the node's name is
## the id with dots as underscores; a route node may also carry the id as meta "route_id").
## Its Node3D children are the patrol points, in order. null when there is none.
func patrol_route(route_id: String) -> Node3D:
	if route_id == "":
		return null
	var routes := get_node_or_null("Markers/Patrol")
	if routes == null:
		return null
	var n := routes.get_node_or_null(NodePath(route_id.validate_node_name())) as Node3D
	if n != null:
		return n
	for child in routes.get_children():
		if child is Node3D and str(child.get_meta("route_id", "")) == route_id:
			return child as Node3D
	return null


## The id of the level record's district whose rectangle (x and z, level space) contains
## `pos` (a global position), or "" when none does.
func district_at(pos: Vector3) -> String:
	var local := to_local(pos) if is_inside_tree() else pos
	var districts: Variant = level_record().get("districts")
	if typeof(districts) != TYPE_ARRAY:
		return ""
	for d: Variant in districts:
		if typeof(d) != TYPE_DICTIONARY:
			continue
		var lo: Variant = d.get("min_m")
		var hi: Variant = d.get("max_m")
		if typeof(lo) != TYPE_ARRAY or typeof(hi) != TYPE_ARRAY or (lo as Array).size() != 3 \
				or (hi as Array).size() != 3:
			continue
		if local.x >= float(lo[0]) and local.x <= float(hi[0]) and local.z >= float(lo[2]) \
				and local.z <= float(hi[2]):
			return str(d.get("id", ""))
	return ""


## The player of this level: the giant in group "player" below this root (else any giant in
## the tree, e.g. a test that added its own). null when there is none.
func player() -> GiantPlayer:
	if _player_ref != null:
		var p := _player_ref.get_ref() as GiantPlayer
		if p != null and p.is_inside_tree():
			return p
	_player_ref = null
	if not is_inside_tree():
		return null
	var fallback: GiantPlayer = null
	for n in get_tree().get_nodes_in_group("player"):
		var g := n as GiantPlayer
		if g == null or not g.is_inside_tree():
			continue
		if _owns(g):
			_player_ref = weakref(g)
			return g
		if fallback == null:
			fallback = g
	return fallback


## The navigation map of this level's world (an invalid RID outside the tree).
func nav_map() -> RID:
	return get_world_3d().navigation_map if is_inside_tree() else RID()


## The navigation region that serves nav layer `layer` (a single bit: 1 human, 2 large,
## 4 giant, 8 small giant): Navigation/<Human|Large|Giant|SmallGiant>, else any region below
## Navigation whose navigation_layers include it. Invalid RID when the level has none (for
## NavigationServer3D.region_get_closest_point: flee and safe points).
func nav_region(layer: int) -> RID:
	var nav := get_node_or_null("Navigation")
	if nav == null:
		return RID()
	var named := nav.get_node_or_null(NodePath(str(NAV_REGION_NAMES.get(layer, "")))) as NavigationRegion3D
	if named != null and (named.navigation_layers & layer) != 0:
		return named.get_rid()
	for r in nav.find_children("*", "NavigationRegion3D", true, false):
		var region := r as NavigationRegion3D
		if (region.navigation_layers & layer) != 0:
			return region.get_rid()
	return RID()


## The node encounter actors are spawned under (LevelRoot/Spawned; made when missing).
func spawn_parent() -> Node3D:
	var s := get_node_or_null("Spawned") as Node3D
	if s == null:
		s = Node3D.new()
		s.name = "Spawned"
		add_child(s)
	return s


## The level's EncounterDirector (LevelRoot/EncounterDirector), or null.
func director() -> EncounterDirector:
	return get_node_or_null("EncounterDirector") as EncounterDirector


func _lookup(table: Dictionary, id: String) -> Node:
	if id == "":
		return null
	var n: Variant = table.get(id)
	if n == null or not is_instance_valid(n) or not (n as Node).is_inside_tree():
		rebuild_lookups()
		n = table.get(id)
	return n as Node if n != null and is_instance_valid(n) else null


func _owns(n: Node) -> bool:
	return n == self or is_ancestor_of(n)
