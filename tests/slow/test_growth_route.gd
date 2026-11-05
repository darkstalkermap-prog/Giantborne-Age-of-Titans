extends IntegrationSuite
## The 3-size route (plan §3.5, spec §15 camera/growth): in the growth course
## (scenes/test/growth_course.tscn) the giant at stages 1, 2 and 3, in third and in first
## person, walks every waypoint of Route/WP01.. (a 5 m doorway, an 8.6 m passage, a 20 degree
## ramp over a 4 m platform, a wall lane 1 m beside the path). Every tick the camera must be
## outside world geometry, and the crosshair probe (tests/support/crosshair_probe.gd) must never
## report more than 30 consecutive ticks in which the giant's own body is the first thing the
## screen-centre ray meets. In third person the wall lane must make the follow arm retract.

const COURSE := "res://scenes/test/growth_course.tscn"
const MAX_OBSCURED_TICKS := 30
const WAYPOINT_TIMEOUT_TICKS := 15 * 60
## The wall lane's waypoints (Route/WP09 .. WP10) run from z = -84 to -106.
const LANE_Z := Vector2(-104.0, -86.0)
## The low passage (8.6 m ceiling) runs from z = -20 to -30.
const PASSAGE_Z := Vector2(-29.0, -21.0)


func _run_route(stage: int, first_person: bool) -> Dictionary:
	# P08 caps weapons at their fit stage; the route swings nothing, but keep the club full size.
	TestFixtures.record_override("weapon.club", {"fit_max_stage": 3})
	var course: Node3D = (load(COURSE) as PackedScene).instantiate()
	world.add_child(course)
	var p := course.get_node("Player") as GiantPlayer
	p.router.use_injection = true
	await step_ticks(5)
	var grown := true
	if stage != 1:
		grown = bool(p.growth.debug_set_stage(stage).ok)
		await step_ticks(30)
	if first_person:
		p.router.inject_edge(&"camera_toggle")
		await step_ticks(1)
	var waypoints: Array[Vector3] = []
	for m in course.get_node("Route").get_children():
		waypoints.append((m as Node3D).global_position)
	var space := p.get_world_3d().direct_space_state
	var q := PhysicsPointQueryParameters3D.new()
	q.collision_mask = HitQueryAdapter.OCCLUDER_MASK
	var probe := CrosshairProbe.new(p.camera_rig.camera, [p])
	var inside_ticks := 0
	var reached := 0
	var note := ""
	var lane_min_arm := INF
	var lane_full_arm := 0.0
	var passage_head_hidden := 0
	var prev := p.global_position
	for wp in waypoints:
		var ok := false
		# Look along the path segment and steer toward the waypoint with the stick, like a player
		# walking down a corridor. (A camera aimed straight at a waypoint that a big giant cannot
		# reach - the wall lane's, 1 m from the wall - would swing its arm away from the wall.)
		var seg := wp - prev
		seg.y = 0.0
		prev = wp
		for i in WAYPOINT_TIMEOUT_TICKS:
			var to := wp - p.global_position
			to.y = 0.0
			if to.length() < 1.2 and absf(wp.y - p.global_position.y) < 1.0:
				ok = true
				break
			var yaw := TargetingRules.yaw_of(seg if seg.length() > 0.5 else to)
			p.camera_rig.yaw = yaw
			p.router.set_injected_move(stick_toward(to, yaw))
			await step_ticks(1)
			q.position = p.camera_rig.camera.global_position
			if not space.intersect_point(q, 1).is_empty():
				inside_ticks += 1
				note = "camera inside geometry near %s" % q.position
			probe.sample()
			var z := p.global_position.z
			if not first_person and z < LANE_Z.y and z > LANE_Z.x:
				lane_min_arm = minf(lane_min_arm, p.camera_rig.current_distance)
				lane_full_arm = Vector2(float(p.profile.camera_shoulder_offset_m), p.camera_rig.desired_distance).length()
			if not first_person and z < PASSAGE_Z.y and z > PASSAGE_Z.x and p.camera_rig.head_hidden:
				passage_head_hidden += 1
		if not ok:
			note = "could not reach %s (stuck at %s)" % [wp, p.global_position]
			break
		reached += 1
	p.router.set_injected_move(Vector2.ZERO)
	var out := {"grown": grown, "stage": p.growth_stage, "reached": reached, "total": waypoints.size(),
		"inside": inside_ticks, "max_obscured": probe.max_consecutive, "obscured": probe.obscured_ticks,
		"blocker": probe.worst_blocker, "samples": probe.samples, "lane_min_arm": lane_min_arm,
		"lane_full_arm": lane_full_arm, "passage_head_hidden": passage_head_hidden, "note": note}
	course.queue_free()
	await step_ticks(2)
	return out


## The stick input (x right, y forward) that walks along the flat vector `to` while the camera
## looks along `yaw` (Godot convention, 0 = -Z).
static func stick_toward(to: Vector3, yaw: float) -> Vector2:
	var flat := Vector3(to.x, 0.0, to.z)
	if flat.length_squared() < 1e-6:
		return Vector2.ZERO
	var d := flat.normalized()
	var forward := Vector3(-sin(yaw), 0.0, -cos(yaw))
	var right := Vector3(cos(yaw), 0.0, -sin(yaw))
	return Vector2(d.dot(right), d.dot(forward)).normalized()


func _check(r: Dictionary, stage: int, mode: String) -> void:
	var what := "stage %d, %s" % [stage, mode]
	assert_true(r.grown and int(r.stage) == stage, "%s: the giant is stage %d (%s)" % [what, stage, r.stage])
	assert_eq(r.reached, r.total, "%s: every waypoint reached (%s)" % [what, r.note])
	assert_eq(r.inside, 0, "%s: the camera is never inside geometry (%s)" % [what, r.note])
	assert_true(int(r.max_obscured) <= MAX_OBSCURED_TICKS,
		"%s: never more than %d consecutive obscured ticks (worst %d, by %s; %d of %d ticks obscured)" % [
		what, MAX_OBSCURED_TICKS, r.max_obscured, r.blocker, r.obscured, r.samples])
	if mode == "third person":
		assert_true(float(r.lane_min_arm) < float(r.lane_full_arm) - 0.5,
			"%s: the wall lane makes the follow arm retract (min %.2f of %.2f m)" % [what, r.lane_min_arm, r.lane_full_arm])
	if mode == "third person" and stage == 3:
		# Under the 8.6 m ceiling the stage-3 arm is cut to about 3.3 m, right behind the head:
		# the camera hides the head (layer 2), so the crosshair stays clear.
		assert_true(int(r.passage_head_hidden) > 0, "%s: the camera hides the head under the low ceiling" % what)


func test_stage_1_third_person() -> void:
	_check(await _run_route(1, false), 1, "third person")


func test_stage_1_first_person() -> void:
	_check(await _run_route(1, true), 1, "first person")


func test_stage_2_third_person() -> void:
	_check(await _run_route(2, false), 2, "third person")


func test_stage_2_first_person() -> void:
	_check(await _run_route(2, true), 2, "first person")


func test_stage_3_third_person() -> void:
	_check(await _run_route(3, false), 3, "third person")


func test_stage_3_first_person() -> void:
	_check(await _run_route(3, true), 3, "first person")
