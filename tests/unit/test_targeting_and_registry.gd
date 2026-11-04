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
