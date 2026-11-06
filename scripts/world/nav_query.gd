class_name NavQuery
extends RefCounted
## The one way to ask for a path (P24b; plan M6-M9 §2.8, decision 13; open_world_tech.md §5.3).
## Static. `level` is the LevelRoot the asker belongs to (or, with no level, any Node3D in a world:
## its world's default map and today's parameters).
##
## The map: level.nav_map(the lowest bit of `layers` the level has): a streamed world's own map per
## layer (titan gate bits ride on the titan map), the default map for every layer elsewhere.
##
## The parameters (level.nav_query_settings(), the level record's `nav_query`): a query runs through
## NavigationServer3D.query_path with a NavigationPathQueryParameters3D answered in the same call -
## navigation_layers = `layers`, path_search_max_polygons = max_polygons (0 = unlimited) and
## path_search_max_distance by purpose ("chase" chase_distance_m, 120 m; "far" far_distance_m,
## 300 m). Unlimited polygons with a distance cap never hit Godot 4.6.3's "most reachable polygon"
## error and cost 1-3 ms (brief §5.3); the default 4,096-polygon search stops short across a
## world. Without settings (the Valley, test levels) the parameters are map_get_path's own
## (4,096 polygons, no distance cap, the corridor funnel), so the Valley's paths do not change.
##
## The goal: the query snaps it itself - its end polygon is the one of the mask's polygons closest to
## the goal (a giant wading the river is chased to the bank) - so path() does not pay a second scan
## of the map (a map_get_closest_point costs about 1.2 ms on sixteen human chunks, measured);
## closest_point() is there for callers that need the point (flee, safe and spawn points).
##
## The budget: a level with nav_query.queries_per_tick lets that many queries run per Sim tick.
## path() and closest_point() always answer and count (fleeing must have a reachable point);
## callers that can wait (an agent's re-path, the director) ask budget_left() first and spend() what
## they use, the rest waiting a tick. Without the setting the budget is unlimited.

const PURPOSE_CHASE := "chase"
const PURPOSE_FAR := "far"
## The parameters a level without nav_query settings gets: NavigationPathQueryParameters3D's (and
## map_get_path's) defaults.
const DEFAULT_MAX_POLYGONS := 4096
## Defaults of the settings' keys (plan §2.7's level_world record).
const DEFAULTS := {"max_polygons": 0, "chase_distance_m": 120.0, "far_distance_m": 300.0, "repath_min_ticks": 6,
	"repath_min_move_m": 2.0, "queries_per_tick": 8}
## budget_left() without a limit.
const UNLIMITED := 1 << 30

static var _budget_tick := -1
static var _budget_used := {}   # level instance id -> queries this tick
## Queries run (path() and closest_point()) since the process started, for tests and stats.
static var queries_total := 0


# --------------------------------------------------------------------------- the level's settings

## The level record's nav_query block merged over DEFAULTS, or {} when the level has none (the
## Valley's queries keep today's parameters).
static func settings(level: Node) -> Dictionary:
	if level == null or not level.has_method("nav_query_settings"):
		return {}
	var s: Variant = level.call("nav_query_settings")
	if typeof(s) != TYPE_DICTIONARY or (s as Dictionary).is_empty():
		return {}
	var out := DEFAULTS.duplicate()
	out.merge(s, true)
	return out


## {"max_polygons", "max_distance"} of a purpose under a level's settings: map_get_path's defaults
## (4,096, no cap) without settings.
static func params_for(level: Node, purpose := PURPOSE_CHASE) -> Dictionary:
	var s := settings(level)
	if s.is_empty():
		return {"max_polygons": DEFAULT_MAX_POLYGONS, "max_distance": 0.0}
	var dist := float(s.far_distance_m) if purpose == PURPOSE_FAR else float(s.chase_distance_m)
	return {"max_polygons": int(s.max_polygons), "max_distance": dist}


## True when the level keeps one map per layer (a streamed world): its maps hold one layer each, so
## a map's closest point is a point of that layer.
static func uses_layer_maps(level: Node) -> bool:
	return level != null and level.has_method("nav_layers") and level.has_method("nav_map") \
		and _world_map(level).is_valid() and _level_map(level, 0) != _world_map(level)


# --------------------------------------------------------------------------- maps

## The map a query on `layers` uses: the level's map of the lowest of those bits it has (its own
## map, or the world's default map). Invalid when there is none.
static func map_for(level: Node, layers: int) -> RID:
	if level == null:
		return RID()
	if level.has_method("nav_map"):
		var bit := 1
		while bit <= layers and bit > 0:
			if (layers & bit) != 0:
				var m := _level_map(level, bit)
				if m.is_valid():
					return m
			bit <<= 1
		return _level_map(level, 0) if layers == 0 else RID()
	return _world_map(level)


## True when the map for `layers` has synced at least once (queries before that fail).
static func is_synced(level: Node, layers: int) -> bool:
	var m := map_for(level, layers)
	return m.is_valid() and NavigationServer3D.map_get_iteration_id(m) > 0


## True when there is navigation to ask on `layers`: a synced map that holds a region of them (a
## level without any - a bare test floor - steers without navigation).
static func has_navigation(level: Node, layers: int) -> bool:
	if not is_synced(level, layers):
		return false
	if uses_layer_maps(level):
		return not NavigationServer3D.map_get_regions(map_for(level, layers)).is_empty()
	return _layer_region(level, layers).is_valid()


# --------------------------------------------------------------------------- queries

## A path on `layers` from `from` toward `to` (see the header): [] when there is no synced map.
static func path(level: Node, from: Vector3, to: Vector3, layers: int, purpose := PURPOSE_CHASE) -> PackedVector3Array:
	var m := map_for(level, layers)
	if not m.is_valid() or NavigationServer3D.map_get_iteration_id(m) <= 0:
		return PackedVector3Array()
	var p := params_for(level, purpose)
	var q := NavigationPathQueryParameters3D.new()
	q.map = m
	q.start_position = from
	q.target_position = to
	q.navigation_layers = layers
	q.path_search_max_polygons = int(p.max_polygons)
	q.path_search_max_distance = float(p.max_distance)
	var r := NavigationPathQueryResult3D.new()
	NavigationServer3D.query_path(q, r)
	spend(level)
	return r.path


## The point of `layers`' navigation nearest `pos`: on a streamed world the closest point of the
## layer's map (a gate region of the titan map counts only when `layers` has its bit); elsewhere the
## closest point of the level's region for the lowest of the bits (LevelRoot.nav_region, as the
## actors snapped before), else of the first region of the map on those layers. Vector3.INF when
## there is no navigation.
static func closest_point(level: Node, pos: Vector3, layers: int) -> Vector3:
	if not is_synced(level, layers):
		return Vector3.INF
	if uses_layer_maps(level):
		var m := map_for(level, layers)
		spend(level)
		var owner := NavigationServer3D.map_get_closest_point_owner(m, pos)
		if not owner.is_valid() or (NavigationServer3D.region_get_navigation_layers(owner) & layers) != 0:
			return NavigationServer3D.map_get_closest_point(m, pos)
		# The nearest polygon is a gate region the mask lacks: the nearest of the mask's own regions.
		var best := Vector3.INF
		var best_d := INF
		for r: RID in NavigationServer3D.map_get_regions(m):
			if (NavigationServer3D.region_get_navigation_layers(r) & layers) == 0:
				continue
			var p := NavigationServer3D.region_get_closest_point(r, pos)
			var d := p.distance_squared_to(pos)
			if d < best_d:
				best_d = d
				best = p
		return best
	var region := _layer_region(level, layers)
	if not region.is_valid():
		return Vector3.INF
	return NavigationServer3D.region_get_closest_point(region, pos)


## True when a path on `layers` from `from` ends within `tolerance` m (horizontally) of `to`.
static func reaches(level: Node, from: Vector3, to: Vector3, layers: int, tolerance := 1.0,
		purpose := PURPOSE_FAR) -> bool:
	var p := path(level, from, to, layers, purpose)
	if p.is_empty():
		return false
	var end := p[p.size() - 1]
	return Vector2(end.x - to.x, end.z - to.z).length() <= tolerance


# --------------------------------------------------------------------------- the budget

## Queries left this Sim tick under the level's nav_query.queries_per_tick (UNLIMITED without it);
## 0 = defer to the next tick.
static func budget_left(level: Node) -> int:
	var s := settings(level)
	var cap := int(s.get("queries_per_tick", 0))
	if cap <= 0:
		return UNLIMITED
	return maxi(0, cap - _used(level))


## Counts `n` queries of this tick against the level's budget (path() and closest_point() count
## their own; an agent's re-path calls it).
static func spend(level: Node, n := 1) -> void:
	queries_total += n
	if level == null:
		return
	_roll()
	var key := level.get_instance_id()
	_budget_used[key] = int(_budget_used.get(key, 0)) + n


## Queries counted this tick for the level.
static func used_this_tick(level: Node) -> int:
	return _used(level)


## Forgets the per-tick counts (tests).
static func reset_budget() -> void:
	_budget_tick = -1
	_budget_used.clear()


static func _used(level: Node) -> int:
	if level == null:
		return 0
	_roll()
	return int(_budget_used.get(level.get_instance_id(), 0))


static func _roll() -> void:
	if _budget_tick != Sim.tick:
		_budget_tick = Sim.tick
		_budget_used.clear()


# --------------------------------------------------------------------------- helpers

static func _level_map(level: Node, bit: int) -> RID:
	var v: Variant = level.call("nav_map", bit)
	return v if v is RID else RID()


static func _world_map(level: Node) -> RID:
	var n := level as Node3D
	if n == null or not n.is_inside_tree() or n.get_world_3d() == null:
		return RID()
	return n.get_world_3d().navigation_map


## The region a Valley-style level snaps `layers` to: LevelRoot.nav_region(lowest bit), else the
## first region of the map on those layers. Invalid when there is none.
static func _layer_region(level: Node, layers: int) -> RID:
	if level != null and level.has_method("nav_region"):
		var r: Variant = level.call("nav_region", layers & -layers)
		if r is RID and (r as RID).is_valid():
			return r
	var m := map_for(level, layers)
	if not m.is_valid():
		return RID()
	for r: RID in NavigationServer3D.map_get_regions(m):
		if (NavigationServer3D.region_get_navigation_layers(r) & layers) != 0:
			return r
	return RID()
