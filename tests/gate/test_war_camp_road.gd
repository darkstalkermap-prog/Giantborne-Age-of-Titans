extends IntegrationSuite
## M9 gate (FOLLOWUPS "From the M9 confirmation": the war camp's shield wall stands across the King's Road where it enters
## the camp): on the real world (scenes/world/world.tscn, deterministic streaming), Aldmere at peace, a giant of stage 4
## and of stage 6 walks the King's Road through the war camp both ways - from the camp's south entrance (545, 232) through
## its middle (520, 120) and back - with the camp's shield wall and its banner in the world (neutral, watching), and the
## wall's posts keep clear of the road. W23's lane P39f moved the wall 4 m into the camp, out of a tent, onto the road's
## line (pivot (520, 163)): every one of these walks stood against its front rank at (522-524, 159-168) for the rest of its
## time (the M9 confirmation: 30 stuck moments there in the world runs). The wall now stands on open ground west of the
## road between the camp's tents (pivot (500, 163)).
## M9 gate (lane ironreg): and off the diagonal through the camp's south-west - the giant's own way from the road's
## south side (514, 192) to the Aldmere road's waystone (470, 60), the line the world bot walks toward that waystone
## and the shrine beyond it. The wall's east end at (503, 164) stood on it: a giant at peace was held there for the
## rest of the walk (lane aldmere's runs: 5-6 s each until the bot stepped aside). The wall now stands a few metres
## west, just outside the tents' ring (pivot (490, 167)).

const SCENE := "res://scenes/world/world.tscn"
const CAMP := "encounter.aldmere_war_camp"
## The King's Road through the camp (tools/data/world/world.json, kings_road): its points from the south entrance on.
const ROAD := [Vector2(545.0, 232.0), Vector2(522.0, 160.0), Vector2(520.0, 120.0)]
const ROAD_HALF_WIDTH_M := 9.0
## M9 gate (lane ironreg): the diagonal through the camp's south-west, from the road's south side to the Aldmere road's
## waystone (world.cp.aldmere_road).
const DIAGONAL := [Vector2(514.0, 192.0), Vector2(470.0, 60.0)]
## The wall's posts keep this far off the diagonal's straight line (its titan path bends 1-3 m west of it round the
## tents).
const DIAGONAL_CLEAR_M := 8.0


func after_each() -> void:
	for f in Formation.live():
		f.dissolve()
	FactionState.reset_for_tests()
	WanderDirector.reset_for_tests()
	await super()


static func _profile(stage: int) -> Dictionary:
	for rec: Dictionary in GameData.records_of_type("growth_profile"):
		if int(rec.get("stage", 0)) == stage:
			return rec
	return {}


static func _flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0.0, v.z)


func _world(xz: Vector2) -> WorldRoot:
	WanderDirector.test_active = true
	WanderDirector.view_probe = func(_p: Vector3) -> bool: return false
	var w := (load(SCENE) as PackedScene).instantiate() as WorldRoot
	world.add_child(w)
	w.streamer.deterministic = true
	w.player().router.use_injection = true
	await _move(w, xz)
	return w


## Puts the giant on the ground at `xz` once the ring around it is loaded.
func _move(w: WorldRoot, xz: Vector2) -> void:
	var p := w.player()
	var at := Vector3(xz.x, 300.0, xz.y)
	p.process_mode = Node.PROCESS_MODE_DISABLED
	p.global_position = at
	var guard := 0
	while not w.streamer.ring_ready(at) and guard < 800:
		w.streamer.load_ring_slice(at)
		await step_ticks(1)
		guard += 1
	var y := w.height_at(at)
	p.global_position = Vector3(xz.x, (y if not is_nan(y) else 80.0) + 0.3, xz.y)
	p.velocity = Vector3.ZERO
	p.process_mode = Node.PROCESS_MODE_INHERIT


## The distance (m) from `xz` to the road's line through the camp.
static func _road_distance(xz: Vector2) -> float:
	return _line_distance(xz, ROAD)


## The distance (m) from `xz` to the polyline `points`.
static func _line_distance(xz: Vector2, points: Array) -> float:
	var best := INF
	for i in range(1, points.size()):
		var a: Vector2 = points[i - 1]
		var b: Vector2 = points[i]
		var ab := b - a
		var t := clampf((xz - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
		best = minf(best, (a + ab * t).distance_to(xz))
	return best


## The shield wall's members (rank and file and banner) standing in the world, alive.
func _wall_alive(w: WorldRoot) -> int:
	var d := w.director()
	var n := 0
	for id: String in d.members_of(CAMP):
		if not (id.contains("camp_shield") or id.contains("camp_banner")):
			continue
		var e := Sim.get_entity(id)
		if d.member_status(id) == EncounterDirector.SPAWNED and e != null and e.is_alive():
			n += 1
	return n


## Walks the giant along the road's points (its own titan path each leg) for at most `seconds`; returns the last
## position and the longest time (s) it stood still on the way.
func _walk_road(w: WorldRoot, points: Array, seconds: float) -> Dictionary:
	var p := w.player()
	var layers: int = p.growth.nav_query_mask()
	var pts: Array[Vector3] = []
	for q: Vector2 in points:
		var y := w.height_at(Vector3(q.x, 0.0, q.y))
		pts.append(Vector3(q.x, y if not is_nan(y) else 34.0, q.y))
	var leg := 1
	var path := NavQuery.path(w, p.global_position, pts[leg], layers, NavQuery.PURPOSE_FAR)
	var idx := 1
	var still := 0
	var longest := 0
	var last := p.global_position
	var done := false
	for t in int(seconds * 60.0):
		if _flat(pts[leg] - p.global_position).length() < 4.0:
			leg += 1
			if leg >= pts.size():
				done = true
				break
			path = NavQuery.path(w, p.global_position, pts[leg], layers, NavQuery.PURPOSE_FAR)
			idx = 1
		while idx < path.size() and _flat(path[idx] - p.global_position).length() < 2.5:
			idx += 1
		var next := pts[leg] if idx >= path.size() else path[idx]
		p.camera_rig.yaw = TargetingRules.yaw_of(_flat(next - p.global_position))
		p.router.injected_move = Vector2(0, 1)
		await step_ticks(1)
		if t % 60 == 59:
			if _flat(p.global_position - last).length() < 0.5:
				still += 1
				longest = maxi(longest, still)
			else:
				still = 0
			last = p.global_position
	p.router.injected_move = Vector2.ZERO
	return {"at": p.global_position, "done": done, "still_s": longest}


func test_the_shield_wall_stands_clear_of_the_kings_road() -> void:
	var rec := GameData.get_record(CAMP)
	var near := INF
	for sp: Dictionary in rec.get("spawns", []):
		if str(sp.get("formation", "")) != "shields":
			continue
		var at := Vector2(float(sp.position_m[0]), float(sp.position_m[2]))
		near = minf(near, _road_distance(at))
	print("    war camp road: the shield wall's nearest post %.1f m from the King's Road's line" % near)
	# The road is 18 m wide; a stage-6 giant (3.7 m) walking its edge passes a wall that keeps 6 m beyond it.
	assert_true(near >= ROAD_HALF_WIDTH_M + 6.0, "the wall's posts keep off the road (%.1f m from its line)" % near)
	# M9 gate (lane ironreg): and off the diagonal to the Aldmere road's waystone.
	var off_diagonal := INF
	for sp: Dictionary in rec.get("spawns", []):
		if str(sp.get("formation", "")) == "shields":
			off_diagonal = minf(off_diagonal, _line_distance(Vector2(float(sp.position_m[0]), float(sp.position_m[2])), DIAGONAL))
	print("    war camp road: the shield wall's nearest post %.1f m from the diagonal to the Aldmere road's waystone" % off_diagonal)
	assert_true(off_diagonal >= DIAGONAL_CLEAR_M, "the wall's posts keep off the diagonal (%.1f m from its line)" % off_diagonal)


func test_a_giant_of_stages_4_and_6_walks_the_kings_road_through_the_war_camp() -> void:
	for stage: int in [4, 6]:
		for south_to_north: bool in [true, false]:
			var points: Array = ROAD.duplicate()
			if not south_to_north:
				points.reverse()
			var w := await _world(points[0])
			var p := w.player()
			p.set_profile(_profile(stage))
			p.entity.apply_status("status.debug_invulnerable", NAN, -1.0, "test")
			await step_ticks(60)
			assert_false(FactionState.is_hostile("aldmere"), "Aldmere at peace")
			assert_eq(_wall_alive(w), 11, "stage %d: the camp's shield wall and its banner are in the world" % stage)
			var r := await _walk_road(w, points, 40.0)
			var at: Vector3 = r.at
			var way := "into the camp" if south_to_north else "out of the camp"
			print("    war camp road (stage %d, %s): the giant at (%.1f, %.1f), the road walked %s, stood still at most %d s" % [
				stage, way, at.x, at.z, r.done, int(r.still_s)])
			assert_true(bool(r.done), "stage %d: the giant walks the King's Road %s (at (%.1f, %.1f))" % [stage, way, at.x, at.z])
			assert_true(int(r.still_s) <= 1, "stage %d: never held up on the road %s (%d s still)" % [stage, way, int(r.still_s)])
			w.queue_free()
			await step_ticks(2)
			for f in Formation.live():
				f.dissolve()
			FactionState.reset_for_tests()
			WanderDirector.reset_for_tests()
			WorldState.clear()


## M9 gate (lane ironreg): Aldmere at peace, a giant of stage 4 and of stage 6 walks its own titan path along the
## diagonal through the camp's south-west both ways - from the road's south side to the Aldmere road's waystone and
## back - with the camp's shield wall in the world: never held up more than 1 s. On the wall's post at pivot
## (500, 163) its east end stood on the way: every walk out was held at (504, 166) for the rest of its time.
func test_a_giant_of_stages_4_and_6_walks_the_diagonal_to_the_aldmere_road_waystone() -> void:
	for stage: int in [4, 6]:
		for outward: bool in [true, false]:
			var points: Array = DIAGONAL.duplicate()
			if not outward:
				points.reverse()
			var w := await _world(points[0])
			var p := w.player()
			p.set_profile(_profile(stage))
			p.entity.apply_status("status.debug_invulnerable", NAN, -1.0, "test")
			await step_ticks(60)
			assert_false(FactionState.is_hostile("aldmere"), "Aldmere at peace")
			assert_eq(_wall_alive(w), 11, "stage %d: the camp's shield wall and its banner are in the world" % stage)
			var r := await _walk_road(w, points, 45.0)
			var at: Vector3 = r.at
			var way := "toward the waystone" if outward else "back to the road"
			print("    war camp diagonal (stage %d, %s): the giant at (%.1f, %.1f), walked %s, stood still at most %d s" % [
				stage, way, at.x, at.z, r.done, int(r.still_s)])
			assert_true(bool(r.done), "stage %d: the giant walks the diagonal %s (at (%.1f, %.1f))" % [stage, way, at.x, at.z])
			assert_true(int(r.still_s) <= 1, "stage %d: never held up on the diagonal %s (%d s still)" % [stage, way, int(r.still_s)])
			w.queue_free()
			await step_ticks(2)
			for f in Formation.live():
				f.dissolve()
			FactionState.reset_for_tests()
			WanderDirector.reset_for_tests()
			WorldState.clear()
