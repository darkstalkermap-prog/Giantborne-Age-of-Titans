class_name ValleyProbe
extends RefCounted
## Helpers for the Valley's slow suites (P10b, plan §3.11): load the level, wait for its navigation
## map, path queries per navigation layer, the blocking props' links, and a giant that walks a
## navigation path with the stick.

const VALLEY := "res://scenes/world/valley.tscn"
const LAYOUT := "res://tools/data/valley_layout.json"
const BUILDER := "res://tools/builders/valley.gd"
## Navigation layers (plan §2.2).
const HUMAN := 1
const LARGE := 2
const GIANT := 4
const SMALL_GIANT := 8
const ALL_LAYERS := [HUMAN, LARGE, GIANT, SMALL_GIANT]
## The props whose nav links open a road when they break (or open).
const LINK_PROPS := ["valley.village.barricade", "valley.ruins.practice_gate", "valley.forest.deadfall"]
## A waypoint counts as reached this close (horizontally).
const WAYPOINT_M := 1.2


## The Valley, instantiated (not yet in the tree). no_director: its EncounterDirector is removed
## first, so nothing spawns (navigation and walking tests).
static func instance(no_director := true) -> LevelRoot:
	var lv := (load(VALLEY) as PackedScene).instantiate() as LevelRoot
	if no_director:
		var d := lv.get_node_or_null("EncounterDirector")
		if d != null:
			lv.remove_child(d)
			d.free()
	return lv


## The layout table the Valley was built from.
static func layout() -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(LAYOUT))
	return parsed if typeof(parsed) == TYPE_DICTIONARY else {}


static func flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


static func v3(a: Variant) -> Vector3:
	return Vector3(float(a[0]), float(a[1]), float(a[2]))


## A shrine of the level by world id (Shrines/<world id as a node name>).
static func shrine(level: LevelRoot, world_id: String) -> Shrine:
	return level.get_node_or_null("Shrines/" + world_id.validate_node_name()) as Shrine


## A placed prop by world id (Props/<world id as a node name>).
static func prop(level: LevelRoot, world_id: String) -> Node3D:
	return level.get_node_or_null("Props/" + world_id.validate_node_name()) as Node3D


## Steps ticks until the level's navigation map answers a path on every layer (at most max_ticks).
static func wait_for_navigation(suite: TestSuite, level: LevelRoot, max_ticks := 180) -> bool:
	var a := (level.get_node("Spawns/PlayerSpawn") as Node3D).global_position
	var b := shrine(level, "valley.shrine.hollow").growth_pad_position()
	var map := level.nav_map()
	return await TestWait.until(suite, func() -> bool:
		if NavigationServer3D.map_get_iteration_id(map) <= 0:
			return false
		for layer: int in ALL_LAYERS:
			if not reaches(level, a, b, layer):
				return false
		return true, max_ticks)


static func path(level: LevelRoot, from: Vector3, to: Vector3, layer: int) -> PackedVector3Array:
	return NavigationServer3D.map_get_path(level.nav_map(), from, to, true, layer)


## True when a path on `layer` from `from` ends within `tolerance` m of `to` (horizontally).
static func reaches(level: LevelRoot, from: Vector3, to: Vector3, layer: int, tolerance := 1.5) -> bool:
	var p := path(level, from, to, layer)
	return p.size() > 0 and flat(p[p.size() - 1], to) <= tolerance


## Opens (or closes) the nav links of the barricade, the practice gate and the Deadfall, then
## waits for the navigation map to publish an iteration that has them (map iterations are built
## asynchronously: queries meanwhile still see the old one).
static func set_links(suite: TestSuite, level: LevelRoot, open: bool, ids: Array = LINK_PROPS) -> bool:
	for id: String in ids:
		var p := prop(level, id) as BreakableProp
		if p != null:
			p.set_nav_links_enabled(open)
	return await wait_for_map_update(suite, level)


## Steps ticks until the level's navigation map has published a new iteration, at most max_ticks.
## (An iteration already being built may predate the change: use settle() for the answer.)
static func wait_for_map_update(suite: TestSuite, level: LevelRoot, max_ticks := 120) -> bool:
	var map := level.nav_map()
	var start := NavigationServer3D.map_get_iteration_id(map)
	return await TestWait.until(suite, func() -> bool:
		return NavigationServer3D.map_get_iteration_id(map) > start, max_ticks)


## Whether a path on `layer` reaches `to`, polled until it gives the `expected` answer (at most
## max_ticks): the map may still serve an iteration from before the last link change. Returns
## the final answer (a test asserts it equals `expected`).
static func settle(suite: TestSuite, level: LevelRoot, from: Vector3, to: Vector3, layer: int, expected: bool,
		max_ticks := 60) -> bool:
	await TestWait.until(suite, func() -> bool: return reaches(level, from, to, layer) == expected, max_ticks)
	return reaches(level, from, to, layer)


## Walks `p` along the waypoints of `points` (a navigation path) with the stick, looking along
## each segment; a waypoint must be reached within 5 s plus 0.5 s per metre of its segment.
## Returns {"reached": waypoints reached, "total", "ticks", "stuck_at"}.
static func walk(suite: TestSuite, p: GiantPlayer, points: PackedVector3Array) -> Dictionary:
	var out := {"reached": 0, "total": 0, "ticks": 0, "stuck_at": Vector3.INF}
	var waypoints: Array[Vector3] = []
	for q in points:
		if waypoints.is_empty() and flat(q, p.global_position) < WAYPOINT_M:
			continue
		waypoints.append(q)
	out.total = waypoints.size()
	var prev := p.global_position
	for wp in waypoints:
		var seg := wp - prev
		seg.y = 0.0
		prev = wp
		var ok := false
		for i in 300 + int(seg.length() * 30.0):
			var to := wp - p.global_position
			to.y = 0.0
			if to.length() < WAYPOINT_M:
				ok = true
				break
			var yaw := TargetingRules.yaw_of(seg if seg.length() > 0.5 else to)
			p.camera_rig.yaw = yaw
			p.router.set_injected_move(stick_toward(to, yaw))
			await suite.step_ticks(1)
			out.ticks = int(out.ticks) + 1
		if not ok:
			out.stuck_at = p.global_position
			break
		out.reached = int(out.reached) + 1
	p.router.set_injected_move(Vector2.ZERO)
	return out


## The stick input (x right, y forward) that walks along the flat vector `to` while the camera
## looks along `yaw` (Godot convention, 0 = -Z).
static func stick_toward(to: Vector3, yaw: float) -> Vector2:
	var flat_to := Vector3(to.x, 0.0, to.z)
	if flat_to.length_squared() < 1e-6:
		return Vector2.ZERO
	var d := flat_to.normalized()
	var forward := Vector3(-sin(yaw), 0.0, -cos(yaw))
	var right := Vector3(cos(yaw), 0.0, -sin(yaw))
	return Vector2(d.dot(right), d.dot(forward)).normalized()
