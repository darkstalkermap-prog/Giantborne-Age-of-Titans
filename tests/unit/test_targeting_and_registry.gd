extends TestSuite
## Lock-on scoring and release rules, target switching, hit de-duplication, geometry.


func _cand(id: String, dir: Vector3, dist: float, threat := 0.5, visible := true, alive := true) -> Dictionary:
	return {"id": id, "direction": dir.normalized(), "distance": dist, "threat": threat,
		"visible": visible, "alive": alive, "lockable": true}


func test_score_formula() -> void:
	var q := TargetingRules.score(Vector3.FORWARD, Vector3.FORWARD, 0.0, 35.0, 1.0)
	assert_near(q, 1.0, 1e-9, "perfect candidate scores 1")
	q = TargetingRules.score(Vector3.FORWARD, Vector3.FORWARD, 17.5, 35.0, 0.0)
	assert_near(q, 0.55 + 0.15, 1e-9, "half range, no threat")
	q = TargetingRules.score(Vector3.FORWARD, Vector3.BACK, 70.0, 35.0, 0.6)
	assert_near(q, 0.15 * 0.6, 1e-9, "behind and out of range: threat only")


func test_acquire_respects_range_cone_visibility() -> void:
	var lock := LockOnTracker.new()
	var fwd := Vector3(0, 0, -1)
	var cands := [
		_cand("behind", Vector3(0, 0, 1), 5.0),
		_cand("far", fwd, 36.0),
		_cand("hidden", fwd, 10.0, 1.0, false),
		_cand("wide", Vector3(sin(deg_to_rad(61.0)), 0, -cos(deg_to_rad(61.0))), 5.0),
		_cand("ok", Vector3(sin(deg_to_rad(30.0)), 0, -cos(deg_to_rad(30.0))), 20.0),
	]
	assert_eq(lock.acquire(cands, fwd), "ok", "only the visible in-cone in-range target")
	lock.release()
	assert_eq(lock.acquire([_cand("dead", fwd, 5.0, 0.5, true, false)], fwd), "", "dead targets are not eligible")


func test_release_rules() -> void:
	var lock := LockOnTracker.new()
	var info := {"exists": true, "alive": true, "lockable": true, "visible": true, "distance": 10.0}
	lock.target_id = "a"
	info.distance = 35.0 * 1.25
	assert_eq(lock.update(1.0 / 60.0, info), "", "exactly 1.25x range holds")
	info.distance = 35.0 * 1.25 + 0.01
	assert_eq(lock.update(1.0 / 60.0, info), "out_of_range", "beyond 1.25x range releases")
	lock.target_id = "a"
	info.distance = 10.0
	info.visible = false
	for i in 45:
		assert_eq(lock.update(1.0 / 60.0, info), "", "obstructed %d/45 ticks holds" % i)
	assert_eq(lock.update(1.0 / 60.0, info), "obstructed", "continuous obstruction above 0.75 s releases")
	lock.target_id = "a"
	info.visible = true
	info.alive = false
	assert_eq(lock.update(1.0 / 60.0, info), "target_died", "death releases")
	assert_eq(lock.target_id, "", "no stale target")
	assert_eq(lock.update(1.0 / 60.0, info), "", "no automatic re-acquisition")
	assert_eq(lock.target_id, "", "still unlocked")


func test_obstruction_timer_resets_when_visible() -> void:
	var lock := LockOnTracker.new()
	lock.target_id = "a"
	var hidden := {"exists": true, "alive": true, "lockable": true, "visible": false, "distance": 5.0}
	var seen := hidden.duplicate()
	seen.visible = true
	for i in 40:
		lock.update(1.0 / 60.0, hidden)
	lock.update(1.0 / 60.0, seen)
	for i in 40:
		assert_eq(lock.update(1.0 / 60.0, hidden), "", "timer restarted after a visible tick")


func test_switch_side_and_debounce() -> void:
	var lock := LockOnTracker.new()
	lock.target_id = "mid"
	var fwd := Vector3(0, 0, -1)
	var cands := [
		_cand("left_far", fwd, 10.0), _cand("left_near", fwd, 10.0), _cand("right", fwd, 10.0),
		_cand("mid", fwd, 10.0)]
	cands[0]["screen"] = Vector2(100, 300)
	cands[1]["screen"] = Vector2(500, 300)
	cands[2]["screen"] = Vector2(900, 300)
	cands[3]["screen"] = Vector2(640, 300)
	assert_true(lock.switch_target(-1, cands, Vector2(640, 300), fwd, 10.0), "switch left")
	assert_eq(lock.target_id, "left_near", "nearest on the left")
	assert_false(lock.switch_target(1, cands, Vector2(500, 300), fwd, 10.1), "debounced within 0.20 s")
	assert_true(lock.switch_target(1, cands, Vector2(500, 300), fwd, 10.2), "allowed after 0.20 s")
	assert_eq(lock.target_id, "mid", "nearest on the right of left_near")


func test_hit_registry_dedups_by_entity() -> void:
	var reg := HitRegistry.new()
	var hits := 0
	for collider in ["head", "torso", "legs"]:
		if reg.try_register(7, 0, "soldier_01", 1):
			hits += 1
	assert_eq(hits, 1, "three colliders on one enemy -> one hit")
	assert_true(reg.try_register(7, 0, "soldier_02", 1), "second enemy gets its own hit")
	assert_false(reg.try_register(7, 0, "soldier_02", 1), "but only one")
	assert_true(reg.try_register(7, 1, "soldier_01", 1), "a separate pulse id may hit again")
	assert_true(reg.try_register(8, 0, "soldier_01", 1), "a new attack instance may hit again")


func test_attack_geometry() -> void:
	assert_true(AttackGeometry.local_direction(0, 0).is_equal_approx(Vector3(0, 0, -1)), "forward")
	assert_true(AttackGeometry.local_direction(90, 0).is_equal_approx(Vector3(1, 0, 0)), "positive yaw is right")
	assert_true(AttackGeometry.local_direction(0, 90).y > 0.99, "pitch up")
	var p := AttackGeometry.closest_point_on_segment(Vector3.ZERO, Vector3(10, 0, 0), Vector3(4, 3, 0))
	assert_true(p.is_equal_approx(Vector3(4, 0, 0)), "closest point")
	var b := HitQueryAdapter.basis_y_to(Vector3(1, 1, 0))
	assert_true(b.y.is_equal_approx(Vector3(1, 1, 0).normalized()), "capsule axis aligned")
	assert_near(b.determinant(), 1.0, 1e-5, "right-handed orthonormal basis")
	assert_near(TargetingRules.yaw_of(Vector3(-1, 0, 0)), PI / 2.0, 1e-6, "yaw convention")


## M2 gate: an arc with pitch_mid_deg follows the quadratic through its start, middle and end
## pitch (so a swing can dip through the front), the rig poses the arm on the same curve, and an
## arc without it stays linear. The schema accepts the key within -89..89 degrees.
func test_attack_geometry_mid_pitch() -> void:
	var arc := {"windup_yaw_deg": 90, "windup_pitch_deg": 20, "yaw_start_deg": 60, "yaw_end_deg": -60,
		"pitch_start_deg": -10, "pitch_end_deg": -30}
	var linear := ActionDef.from_dict({"id": "ability.arc_linear", "arc": arc})
	var mid_arc := arc.duplicate()
	mid_arc["pitch_mid_deg"] = -40
	var dipped := ActionDef.from_dict({"id": "ability.arc_mid", "arc": mid_arc})
	assert_true(AttackGeometry.arc_point(linear, 0.25).is_equal_approx(Vector2(30.0, -15.0)), "no mid key: linear")
	for spec: Array in [[0.0, Vector2(60.0, -10.0)], [0.5, Vector2(0.0, -40.0)], [1.0, Vector2(-60.0, -30.0)]]:
		assert_true(AttackGeometry.arc_point(dipped, spec[0]).is_equal_approx(spec[1]),
			"the mid-pitch arc passes through %s at f=%.1f (got %s)" % [spec[1], spec[0], AttackGeometry.arc_point(dipped, spec[0])])
	assert_near(AttackGeometry.arc_point(dipped, 0.25).x, 30.0, 1e-4, "yaw stays linear")
	assert_true(AttackGeometry.arc_point(dipped, 0.6).y < -40.0, "the dip bottoms out after the middle when the end is lower")
	for f: float in [0.0, 0.2, 0.5, 0.8, 1.0]:
		assert_true(AttackGeometry.pose_for(dipped, ActionDef.Phase.ACTIVE, f, Vector2.ZERO).is_equal_approx(
			AttackGeometry.arc_point(dipped, f)), "the rig's active pose is the swept arc at f=%.1f" % f)
		assert_true(AttackGeometry.pose_for(linear, ActionDef.Phase.ACTIVE, f, Vector2.ZERO).is_equal_approx(
			AttackGeometry.arc_point(linear, f)), "also without a mid key at f=%.1f" % f)
	var rec: Dictionary = GameData.get_record("ability.light_1").duplicate(true)
	rec["id"] = "ability.arc_probe"
	assert_eq(DataValidator.validate_record(rec, "probe.json").errors, PackedStringArray(),
		"the shipped light 1 (with pitch_mid_deg) validates")
	(rec.arc as Dictionary)["pitch_mid_deg"] = -95
	assert_true("\n".join(DataValidator.validate_record(rec, "probe.json").errors).contains("pitch_mid_deg: must be >= -89"),
		"pitch_mid_deg is range checked")
