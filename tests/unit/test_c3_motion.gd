extends TestSuite
## C3 (decision C3-7): the giant's turns ease in and out, and an unlocked swing turns into its blow through the
## windup and faces it by the windup's last tick.

const Motor := preload("res://scripts/actors/player/player_motor.gd")


func test_a_turn_builds_and_settles() -> void:
	var max_rate := deg_to_rad(300.0)
	var dt := 1.0 / 60.0
	var r := Motor.eased_turn(0.0, PI, max_rate, dt)
	assert_true(r > 0.0 and r < max_rate * 0.2, "it starts with weight (%.2f rad/s)" % r)
	var yaw := 0.0
	var rate := 0.0
	var target := deg_to_rad(120.0)
	var ticks := 0
	var peak := 0.0
	while absf(target - yaw) > deg_to_rad(0.5) and ticks < 600:
		rate = Motor.eased_turn(rate, target - yaw, max_rate, dt)
		yaw += minf(rate * dt, target - yaw)
		peak = maxf(peak, rate)
		ticks += 1
	assert_true(ticks < 120, "120 degrees in under 2 s at 300 deg/s (%d ticks)" % ticks)
	assert_near(peak, max_rate, 1e-3, "it reaches the stage's rate")
	assert_true(Motor.eased_turn(max_rate, deg_to_rad(2.0), max_rate, dt) < deg_to_rad(20.0), "and slows as it closes")


func test_a_swing_faces_its_blow_by_the_windup_end() -> void:
	var dt := 1.0 / 60.0
	for spec: Array in [[deg_to_rad(170.0), 12, deg_to_rad(160.0)], [deg_to_rad(-90.0), 12, deg_to_rad(540.0)],
			[deg_to_rad(10.0), 24, deg_to_rad(160.0)]]:
		var yaw := 0.0
		var target := float(spec[0])
		var windup := int(spec[1])
		var halfway := 0.0
		for e in windup:
			yaw = Motor.turn_into_swing(yaw, target, e, windup, float(spec[2]), dt)
			if e == windup / 2:
				halfway = yaw
		assert_near(yaw, target, 1e-4, "faces the blow by the windup's end (%.0f deg)" % rad_to_deg(target))
		assert_true(absf(halfway) > 0.0 and absf(halfway) < absf(target) + 1e-4, "turning through it on the way")
