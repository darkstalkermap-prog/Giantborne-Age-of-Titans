class_name BotRoute
extends RefCounted
## The world bot's route planner (P38; plan M6-M9 §6.1 "Routing", decision 13): how a giant crosses
## the streamed 2 km world without a navmesh of the whole of it.
##
##   1. The road graph of the level's world index (WorldIndex.roads): A* from the road node nearest
##      the giant to the node nearest the goal, over the edges the giant's growth stage may use
##      (min_stage / max_stage: the Giant's Stair's edges need stage 6, the Needle's stage 4 or
##      less). A `direct` edge (the Needle: no titan navmesh, a 5 m slot) is walked in a straight
##      line. A goal within LEG_MAX_M takes no road at all, unless the road there has a direct edge.
##   2. Local legs on the titan map: the leg's target is the farthest route point at most LEG_MAX_M
##      along the route from the giant, and a NavQuery path (the stage's titan query mask: 16 and
##      the gate bits it has reached) leads there. A target in a chunk that is not loaded and ready
##      yet is not asked for: the leg waits for it (`waiting_chunk`) by aiming at a nearer route
##      point. A path that ends short of its target is tried again on a nearer point.
##   3. Replanning: the leg is asked again every REPLAN_S, when the giant strays OFF_PATH_M from it
##      or when the leg's target changes; the road route is planned again when the goal moves or
##      the stage changes (BotRoute.goal_changed).
##   4. Fast travel (fast_travel_point): a goal more than FAST_TRAVEL_MIN_M away with a visited
##      waystone or shrine within FAST_TRAVEL_NEAR_M of it (one the giant's stage may arrive at,
##      open to fast travel, nearer the goal than the giant): the bot travels there through the
##      map's way (GameSession.travel_to "fast_travel"), unless the session refuses it (mid-fight:
##      "Not in the middle of a fight.").
##
## Pure enough to test without a giant: plan() and the static helpers take positions; steer()
## needs a level (NavQuery) and, for chunk readiness, a WorldRoot.

const LEG_MAX_M := 250.0
const REPLAN_S := 2.0
const OFF_PATH_M := 3.0
## A route point counts as passed this close (horizontally).
const NODE_REACHED_M := 8.0
## A leg reaches its target when its path ends this close to it.
const LEG_REACH_TOL_M := 5.0
## The next point of a leg's path counts as reached this close.
const WAYPOINT_M := 2.5
const FAST_TRAVEL_MIN_M := 600.0
const FAST_TRAVEL_NEAR_M := 200.0
## A goal this close is walked to without the road graph.
const NEAR_GOAL_M := LEG_MAX_M
## How many route points ahead the giant's place along the route is looked for, and how much nearer
## a later segment must be to pass the points before it.
const ADVANCE_LOOKAHEAD := 6
const ADVANCE_MARGIN_M := 2.0

var index: WorldIndex = null
var level: Node = null
var stage := 3
## The titan query mask (PlayerGrowth.nav_query_mask) or, in the Valley, the giant's nav layers.
var layers := 16

## The goal of the current route (Vector3.INF: none).
var goal := Vector3.INF
## The route's points: the road nodes in order, then the goal.
var points := PackedVector3Array()
## direct[i] = 1 when the way into points[i] is a direct edge (walked in a straight line).
var direct := PackedByteArray()
## The road edges the route uses (index of WorldIndex.roads.edges pairs), for the diagnosis.
var edges := PackedInt32Array()
## The next route point to reach.
var step := 0
## The leg being followed: a NavQuery path toward leg_target.
var leg := PackedVector3Array()
var leg_index := 0
var leg_target := Vector3.INF
var leg_direct := false
## The chunk the leg waits for ("" = none).
var waiting_chunk := ""
## Counters for the metrics.
var plans := 0
var leg_queries := 0
var short_legs := 0
var _plan_stage := -1
var _leg_tick := -1000000


func _init(p_index: WorldIndex = null, p_level: Node = null) -> void:
	index = p_index
	level = p_level


# --------------------------------------------------------------------------- the road graph

## A* over the road edges a giant of `stage` may use, from the node nearest `from` that the stage
## may leave (one of its edges allowed) to the node nearest `to`: {"nodes": PackedInt32Array (both
## ends), "edges": PackedInt32Array (one per step), "length": float}; empty arrays when either end has
## no node or no allowed path joins them. The start skips nodes the stage may not leave: the giant
## stands where it walked, and the nearest node there can be a stage-closed spur's (the Ballista
## Ridge's east end at stage 5: its two nodes' only edges are stage-limited, so no road left it and
## the bot walked toward the Standing Stones on the navmesh alone). The goal's end keeps the nearest
## node: a goal only a closed edge reaches has no road at that stage (a diagnosis's world_blocked).
static func road_path(idx: WorldIndex, from: Vector3, to: Vector3, p_stage: int) -> Dictionary:
	var out := {"nodes": PackedInt32Array(), "edges": PackedInt32Array(), "length": 0.0}
	if idx == null:
		return out
	var start := nearest_leavable_node(idx, from, p_stage)
	var target := idx.nearest_road_node(to)
	if start < 0 or target < 0:
		return out
	var nodes := idx.road_nodes()
	if start == target:
		out.nodes = PackedInt32Array([start])
		return out
	var adj := _adjacency(idx)
	var g := {start: 0.0}
	var came := {}       # node -> [previous node, edge]
	var open := [start]
	var closed := {}
	while not open.is_empty():
		var best_i := 0
		var best_f := INF
		for k in open.size():
			var n: int = open[k]
			var f: float = float(g[n]) + nodes[n].distance_to(nodes[target])
			if f < best_f:
				best_f = f
				best_i = k
		var cur: int = open[best_i]
		open.remove_at(best_i)
		if cur == target:
			var path := PackedInt32Array([target])
			var path_edges := PackedInt32Array()
			while came.has(path[0]):
				var prev: Array = came[path[0]]
				path_edges.insert(0, int(prev[1]))
				path.insert(0, int(prev[0]))
			out.nodes = path
			out.edges = path_edges
			out.length = float(g[target])
			return out
		closed[cur] = true
		for pair: Array in adj.get(cur, []):
			var nb: int = pair[0]
			var e: int = pair[1]
			if closed.has(nb) or not idx.edge_allowed(e, p_stage):
				continue
			var cost: float = float(g[cur]) + nodes[cur].distance_to(nodes[nb])
			if not g.has(nb) or cost < float(g[nb]):
				g[nb] = cost
				came[nb] = [cur, e]
				if not open.has(nb):
					open.append(nb)
	return out


## node -> [[neighbour, edge], ...] of an index (cached on the index's own table).
static func _adjacency(idx: WorldIndex) -> Dictionary:
	return idx._adjacency_table()


## The road node nearest `pos` on the ground plane with an edge a giant of `p_stage` may use; the
## nearest node of all when none has one (-1 when there are no roads).
static func nearest_leavable_node(idx: WorldIndex, pos: Vector3, p_stage: int) -> int:
	var nodes := idx.road_nodes()
	var adj := _adjacency(idx)
	var best := -1
	var best_d := INF
	for i in nodes.size():
		var d := Vector2(nodes[i].x - pos.x, nodes[i].z - pos.z).length_squared()
		if d >= best_d:
			continue
		for pair: Array in adj.get(i, []):
			if idx.edge_allowed(int(pair[1]), p_stage):
				best_d = d
				best = i
				break
	return best if best >= 0 else idx.nearest_road_node(pos)


## True when road edge `e` of `idx` is walked in a straight line (direct = 1).
static func edge_direct(idx: WorldIndex, e: int) -> bool:
	var di: PackedByteArray = idx.roads.get("direct", PackedByteArray())
	return e >= 0 and e < di.size() and int(di[e]) == 1


# --------------------------------------------------------------------------- planning

## Plans a route from `from` to `to` at the planner's stage: the road nodes (trimmed where the giant
## is already past the first or the goal lies before the last), then the goal. True when a road
## route (or a near goal) exists; false when the road graph joins nothing (the route is then the goal
## alone: walked as far as the navmesh leads).
func plan(from: Vector3, to: Vector3) -> bool:
	goal = to
	points = PackedVector3Array()
	direct = PackedByteArray()
	edges = PackedInt32Array()
	step = 0
	leg = PackedVector3Array()
	leg_index = 0
	leg_target = Vector3.INF
	waiting_chunk = ""
	plans += 1
	_plan_stage = stage
	_leg_tick = -1000000
	var ok := true
	if flat_dist(from, to) > NODE_REACHED_M * 2.0 and index != null:
		var rp := road_path(index, from, to, stage)
		var nodes: PackedInt32Array = rp.nodes
		# A near goal is walked on the navmesh - unless the road there takes a direct edge (the
		# Needle's slot has no titan navmesh: its straight steps are the only way through).
		var near := flat_dist(from, to) <= NEAR_GOAL_M
		if near and not _has_direct(rp.edges):
			pass
		elif nodes.is_empty():
			ok = near
		else:
			var pos := index.road_nodes()
			var route_edges: PackedInt32Array = rp.edges
			for i in nodes.size():
				points.append(pos[nodes[i]])
				# The way into node i: the edge before it (none into the first node: walked on the navmesh).
				direct.append(1 if i > 0 and edge_direct(index, route_edges[i - 1]) else 0)
			edges = route_edges
			_trim_ends(from, to)
	points.append(to)
	# The way into the goal: direct when the last road edge was (the goal lies beyond the slot).
	direct.append(1 if direct.size() > 0 and direct[direct.size() - 1] == 1 and points.size() > 1 \
		and flat_dist(points[points.size() - 2], to) < NODE_REACHED_M * 2.0 else 0)
	return ok


func _has_direct(route_edges: PackedInt32Array) -> bool:
	for e in route_edges:
		if edge_direct(index, e):
			return true
	return false


## Drops a first node the giant is already past (the second lies nearer the giant than the first
## does to it) and a last node beyond the goal (the goal lies nearer the node before it).
func _trim_ends(from: Vector3, to: Vector3) -> void:
	while points.size() >= 2 and direct[1] == 0 and flat_dist(from, points[1]) < flat_dist(points[0], points[1]):
		points.remove_at(0)
		direct.remove_at(0)
		if edges.size() > 0:
			edges.remove_at(0)
		direct[0] = 0
	while points.size() >= 2 and direct[points.size() - 1] == 0 \
			and flat_dist(points[points.size() - 2], to) < flat_dist(points[points.size() - 2], points[points.size() - 1]):
		points.remove_at(points.size() - 1)
		direct.remove_at(direct.size() - 1)
		if edges.size() > 0:
			edges.remove_at(edges.size() - 1)


## True when the route should be planned again: another goal (more than `tol` m from the planned
## one), another stage, or none planned.
func goal_changed(to: Vector3, tol := 6.0) -> bool:
	return points.is_empty() or not goal.is_finite() or flat_dist(goal, to) > tol or _plan_stage != stage


## The route's length from `pos` along its remaining points (metres).
func remaining_m(pos: Vector3) -> float:
	if points.is_empty():
		return 0.0
	var total := flat_dist(pos, points[mini(step, points.size() - 1)])
	for i in range(step, points.size() - 1):
		total += flat_dist(points[i], points[i + 1])
	return total


# --------------------------------------------------------------------------- following

## Where to steer now (one tick of the route): advances past reached points, picks the leg's target
## (the farthest point within LEG_MAX_M along the route whose chunk is ready; a direct step is
## steered at straight) and follows its navigation path. `world` (a WorldRoot, or null) answers chunk
## readiness. Returns the point to steer toward (the goal itself when the route is done).
func steer(pos: Vector3, tick: int, world: Node = null) -> Vector3:
	if points.is_empty():
		return goal
	_advance(pos)
	if step >= points.size():
		return goal
	if direct[step] == 1:
		leg_direct = true
		leg = PackedVector3Array()
		leg_target = points[step]
		waiting_chunk = ""
		return points[step]
	leg_direct = false
	var target_i := _leg_target_index(pos, world)
	var target := points[target_i]
	var due := tick - _leg_tick >= ActionDef.seconds_to_ticks(REPLAN_S)
	if leg.is_empty() or flat_dist(target, leg_target) > 1.0 or due or _off_leg(pos):
		_query_leg(pos, target_i, tick, world)
	while leg_index < leg.size() and flat_dist(leg[leg_index], pos) < WAYPOINT_M:
		leg_index += 1
	if leg_index < leg.size():
		return leg[leg_index]
	return leg_target if leg_target.is_finite() else points[step]


## Passes every route point within NODE_REACHED_M, then finds the giant's place along the route: when
## a later segment (within ADVANCE_LOOKAHEAD points, not past a direct step) lies clearly nearer the
## giant than the one it is on, the points before that segment are passed. A navigation path does
## not keep to the road's line - it rounds a hill or a house the road crosses - and a point it never
## comes within NODE_REACHED_M of must not hold the route back (the leg window is measured from the
## next point: a point left behind shrinks it and the giant turns back).
func _advance(pos: Vector3) -> void:
	while step < points.size() - 1 and flat_dist(pos, points[step]) < NODE_REACHED_M:
		step += 1
	if step < points.size() - 1 and direct[step] == 0:
		var best := step
		var best_d := _segment_dist(pos, step)
		for i in range(step + 1, mini(points.size(), step + 1 + ADVANCE_LOOKAHEAD)):
			if direct[i] == 1:
				break
			var d := _segment_dist(pos, i)
			if d < best_d - ADVANCE_MARGIN_M:
				best_d = d
				best = i
		step = best
	if step == points.size() - 1 and flat_dist(pos, points[step]) < 0.5:
		step = points.size()


## The distance from `pos` to the route's segment into point `i` (from the point before it; the
## first point alone for i = 0), on the ground plane.
func _segment_dist(pos: Vector3, i: int) -> float:
	var b := Vector3(points[i].x, 0.0, points[i].z)
	var p := Vector3(pos.x, 0.0, pos.z)
	if i == 0:
		return p.distance_to(b)
	var a := Vector3(points[i - 1].x, 0.0, points[i - 1].z)
	return p.distance_to(Geometry3D.get_closest_point_to_segment(p, a, b))


## The index of the farthest route point within LEG_MAX_M along the route from `pos` (not past a
## direct step, nor into a chunk that is not ready); at least `step`.
func _leg_target_index(pos: Vector3, world: Node) -> int:
	var best := step
	var along := flat_dist(pos, points[step])
	var i := step
	waiting_chunk = ""
	while i + 1 < points.size():
		if direct[i + 1] == 1:
			break
		along += flat_dist(points[i], points[i + 1])
		if along > LEG_MAX_M:
			break
		var c := chunk_waiting(world, points[i + 1])
		if c != "":
			waiting_chunk = c
			break
		i += 1
		best = i
	if best == step:
		var c := chunk_waiting(world, points[step])
		if c != "":
			waiting_chunk = c
	return best


## The id of the chunk under `p` when `world` streams and that chunk is not ready ("" otherwise).
static func chunk_waiting(world: Node, p: Vector3) -> String:
	if world == null or not is_instance_valid(world) or not ("streamer" in world):
		return ""
	var s: Variant = world.get("streamer")
	if s == null or not (s is ChunkStreamer):
		return ""
	var c := (s as ChunkStreamer).chunk_at(p)
	if c == "":
		return ""
	return "" if (s as ChunkStreamer).is_ready(c) else c


## Asks a path toward points[target_i]; a path that ends short of it is asked again toward the
## points before it (down to `step`); the longest-reaching answer is kept.
func _query_leg(pos: Vector3, target_i: int, tick: int, world: Node) -> void:
	_leg_tick = tick
	var best := PackedVector3Array()
	var best_target := Vector3.INF
	var best_gap := INF
	var i := target_i
	var tries := 0
	while i >= step and tries < 3:
		var t := points[i]
		var p := NavQuery.path(level, pos, t, layers, NavQuery.PURPOSE_FAR) if level != null else PackedVector3Array()
		leg_queries += 1
		tries += 1
		if p.size() > 0:
			var gap := flat_dist(p[p.size() - 1], t)
			if gap <= LEG_REACH_TOL_M:
				best = p
				best_target = t
				best_gap = gap
				break
			if gap < best_gap:
				best = p
				best_target = t
				best_gap = gap
		i -= 1
	if best_gap > LEG_REACH_TOL_M:
		short_legs += 1
	leg = best
	leg_target = best_target if best_target.is_finite() else points[target_i]
	leg_index = 1 if leg.size() > 1 else 0


func _off_leg(pos: Vector3) -> bool:
	if leg.size() < 2:
		return false
	var i := clampi(leg_index, 1, leg.size() - 1)
	var a := leg[i - 1]
	var b := leg[i]
	var seg := Geometry3D.get_closest_point_to_segment(Vector3(pos.x, 0, pos.z), Vector3(a.x, 0, a.z), Vector3(b.x, 0, b.z))
	return seg.distance_to(Vector3(pos.x, 0, pos.z)) > OFF_PATH_M


## Forgets the leg (a stuck recovery or a teleport): the next steer asks again.
func reset_leg() -> void:
	leg = PackedVector3Array()
	leg_index = 0
	_leg_tick = -1000000


## True once the giant has passed every route point (the goal is the last one left, within reach).
func at_last_point() -> bool:
	return step >= points.size() - 1


# --------------------------------------------------------------------------- fast travel

## The checkpoint to fast-travel to for a goal at `to` from `from`, or "": the goal is more than
## FAST_TRAVEL_MIN_M away and a checkpoint of the index lies within FAST_TRAVEL_NEAR_M of it - one
## the giant has visited (`visited` answers visited.<id>), open to fast travel, whose requires_flags
## hold (`flag_ok`), whose max_stage admits `p_stage` - and nearer the goal than the giant is. The
## nearest such checkpoint to the goal wins (ties by id).
static func fast_travel_point(idx: WorldIndex, from: Vector3, to: Vector3, p_stage: int,
		visited: Callable, flag_ok: Callable) -> String:
	if idx == null or not to.is_finite() or flat_dist(from, to) <= FAST_TRAVEL_MIN_M:
		return ""
	var best := ""
	var best_d := INF
	for id in idx.checkpoint_ids():
		var c := idx.checkpoint(id)
		var p: Variant = c.get("position")
		if typeof(p) != TYPE_VECTOR3:
			continue
		var d := flat_dist(p, to)
		if d > FAST_TRAVEL_NEAR_M or d >= flat_dist(from, to) - 1.0:
			continue
		if not bool(c.get("fast_travel", true)) or idx.max_stage_of(id) < p_stage:
			continue
		if visited.is_valid() and not bool(visited.call(id)):
			continue
		var flags_hold := true
		for f: Variant in c.get("requires_flags", PackedStringArray()):
			if flag_ok.is_valid() and not bool(flag_ok.call(str(f))):
				flags_hold = false
				break
		if not flags_hold:
			continue
		if d < best_d - 1e-3 or (absf(d - best_d) <= 1e-3 and id < best):
			best = id
			best_d = d
	return best


# --------------------------------------------------------------------------- helpers

static func flat_dist(a: Vector3, b: Vector3) -> float:
	if not a.is_finite() or not b.is_finite():
		return INF
	return Vector2(a.x - b.x, a.z - b.z).length()


## A short line for traces and the diagnosis.
func describe() -> String:
	return "route %d point(s), step %d, leg %d pt%s%s" % [points.size(), step, leg.size(),
		" direct" if leg_direct else "", (" waiting %s" % waiting_chunk) if waiting_chunk != "" else ""]
