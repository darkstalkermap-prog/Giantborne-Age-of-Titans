extends TestSuite
## P03: the projectile's pure parts - spec defaults, launch velocity (straight shots, the low
## ballistic arc through the aim point, range clamping, unreachable aims), exact per-tick
## kinematics and expiry - plus the action schema's P03 fields (projectile, sector, radius by
## stage, statuses, morale).

const DT := 1.0 / 60.0


func _bolt_spec(extra: Dictionary = {}) -> Dictionary:
	var d: Dictionary = GameData.get_record("ability.runic_bolt").duplicate(true)
	d["id"] = "ability.test_spec"
	(d["projectile"] as Dictionary).merge(extra, true)
	return Projectile.spec_for(ActionDef.from_dict(d))


## Steps a projectile launched from `origin` with `velocity` until it passes `distance`
## metres horizontally; returns its height there (linear between the two ticks around it).
func _height_at(origin: Vector3, velocity: Vector3, gravity: float, distance: float) -> float:
	var p := Projectile.new()
	p.position = origin
	p.velocity = velocity
	p.gravity = gravity
	var prev := origin
	for i in 2000:
		var to := p.next_position(DT)
		var d_prev := Vector2(prev.x - origin.x, prev.z - origin.z).length()
		var d_next := Vector2(to.x - origin.x, to.z - origin.z).length()
		if d_next >= distance:
			var t := (distance - d_prev) / maxf(d_next - d_prev, 1e-9)
			return lerpf(prev.y, to.y, t)
		p.advance_to(to, DT)
		prev = to
	return NAN


func test_spec_defaults_and_runic_bolt() -> void:
	var s := Projectile.spec_for(GameData.get_action("ability.runic_bolt"))
	assert_near(float(s.speed_mps), 35.0, 1e-9, "speed")
	assert_near(float(s.radius_m), 0.3, 1e-9, "radius")
	assert_near(float(s.range_m), 25.0, 1e-9, "range")
	assert_near(float(s.gravity_mps2), 0.0, 1e-9, "no gravity")
	assert_eq(s.aim, "lock_or_camera", "aim")
	assert_false(bool(s.arc_to_target), "straight")
	assert_true((s.launch_offset as Vector3).is_equal_approx(Vector3(0.6, 2.9, -0.8)), "launch offset")
	assert_eq(s.visual, "bolt", "visual")
	assert_near(float(s.impact_radius_m), 0.0, 1e-9, "no splash")
	assert_near(float(s.impact_height_m), 2.0, 1e-9, "default splash height")
	assert_false(bool(s.pierce), "stops at its first hit")
	var bare := Projectile.spec_for(GameData.get_action("ability.light_1"))
	assert_eq(bare.launch_offset, Vector3.INF, "no launch offset: the attack origin is used")
	assert_eq(bare.aim, "lock_or_camera", "default aim")


func test_straight_launch_velocity() -> void:
	var s := _bolt_spec()
	var v := Projectile.launch_velocity(Vector3(0, 2, 0), Vector3(3, 2, -4), s)
	assert_near(v.length(), 35.0, 1e-4, "at speed")
	assert_true(v.normalized().is_equal_approx(Vector3(0.6, 0.0, -0.8)), "along the line to the aim")
	var down := Projectile.launch_velocity(Vector3(0, 3, 0), Vector3(0, 0, -4), s)
	assert_true(down.y < 0.0, "straight shots aim down at a point below")
	var same := Projectile.launch_velocity(Vector3.ONE, Vector3.ONE, s)
	assert_near(same.length(), 35.0, 1e-4, "a zero-length aim still launches (forward)")


func test_low_arc_passes_through_the_aim_point() -> void:
	var s := _bolt_spec({"arc_to_target": true, "gravity_mps2": 9.8, "speed_mps": 28.0})
	var origin := Vector3(0, 3.2, 0)
	for aim: Vector3 in [Vector3(0, 0, -18), Vector3(10, 4, -12), Vector3(-6, -2, 9)]:
		var v := Projectile.launch_velocity(origin, aim, s)
		assert_near(v.length(), 28.0, 1e-4, "launched at speed (%s)" % aim)
		var flat := Vector2(aim.x - origin.x, aim.z - origin.z)
		assert_true(Vector2(v.x, v.z).normalized().is_equal_approx(flat.normalized()), "toward the aim (%s)" % aim)
		var pitch := rad_to_deg(atan2(v.y, Vector2(v.x, v.z).length()))
		assert_true(pitch < 45.0, "the low solution (%.1f deg)" % pitch)
		assert_near(_height_at(origin, v, 9.8, flat.length()), aim.y, 0.05, "passes through the aim point %s" % aim)


func test_arc_aims_beyond_range_clamp_and_unreachable_aims_use_45_degrees() -> void:
	var s := _bolt_spec({"arc_to_target": true, "gravity_mps2": 9.8, "speed_mps": 28.0, "range_m": 25.0})
	var origin := Vector3(0, 0, 0)
	var far := Projectile.launch_velocity(origin, Vector3(0, 0, -40), s)
	assert_near(_height_at(origin, far, 9.8, 25.0), 0.0, 0.05, "a 40 m aim lands at the 25 m range")
	var slow := _bolt_spec({"arc_to_target": true, "gravity_mps2": 9.8, "speed_mps": 5.0, "range_m": 25.0})
	var v := Projectile.launch_velocity(origin, Vector3(0, 0, -20), slow)
	var pitch := rad_to_deg(atan2(v.y, Vector2(v.x, v.z).length()))
	assert_near(pitch, 45.0, 1e-4, "out of reach: the longest (45 degree) throw")
	var straight := _bolt_spec({"gravity_mps2": 9.8})
	var sv := Projectile.launch_velocity(origin, Vector3(0, 0, -10), straight)
	assert_near(sv.y, 0.0, 1e-9, "without arc_to_target a gravity shot is launched straight at the aim")


func test_kinematics_are_exact_per_tick() -> void:
	var p := Projectile.new()
	p.position = Vector3(1, 10, 2)
	p.velocity = Vector3(3, 4, -5)
	p.gravity = 9.8
	var n := 90
	for i in n:
		p.advance_to(p.next_position(DT), DT)
	var t := n * DT
	var expected := Vector3(1, 10, 2) + Vector3(3, 4, -5) * t + Vector3.DOWN * (0.5 * 9.8 * t * t)
	assert_true(p.position.is_equal_approx(expected), "x0 + v t - g t^2 / 2 (%s vs %s)" % [p.position, expected])
	assert_true(p.velocity.is_equal_approx(Vector3(3, 4 - 9.8 * t, -5)), "v0 - g t")
	assert_eq(p.age_ticks, n, "one age tick per step")


func test_expiry() -> void:
	var p := Projectile.new()
	p.range_m = 25.0
	p.velocity = Vector3(0, 0, -35)
	for i in 42:
		p.advance_to(p.next_position(DT), DT)
	assert_eq(p.expiry_reason(), "", "still flying after 24.5 m")
	p.advance_to(p.next_position(DT), DT)
	assert_eq(p.expiry_reason(), "range", "a straight shot ends at its range")
	var arc := Projectile.new()
	arc.gravity = 9.8
	arc.range_m = 5.0
	arc.position = Vector3(0, 100, 0)
	arc.velocity = Vector3(0, 0, -20)
	for i in 30:
		arc.advance_to(arc.next_position(DT), DT)
	assert_eq(arc.expiry_reason(), "", "arcs ignore the range (they end on the ground)")
	arc.age_ticks = Projectile.MAX_AGE_TICKS
	assert_eq(arc.expiry_reason(), "timeout", "everything ends after 5 s")
	var low := Projectile.new()
	low.gravity = 9.8
	low.position = Vector3(0, Projectile.KILL_Y - 1.0, 0)
	assert_eq(low.expiry_reason(), "fell", "below the world")


# --------------------------------------------------------------------------- schema

func _errors(patch: Dictionary, base_id := "ability.runic_bolt") -> String:
	var d: Dictionary = GameData.get_record(base_id).duplicate(true)
	d["id"] = "ability.schema_probe"
	for k: Variant in patch:
		if patch[k] == null:
			d.erase(k)
		else:
			d[k] = patch[k]
	return "\n".join(DataValidator.validate_record(d, "probe.json").errors)


func test_schema_p03_action_fields() -> void:
	assert_eq(_errors({}), "", "the shipped Runic Bolt validates")
	assert_eq(_errors({}, "ability.sweeping_blow"), "", "Sweeping Blow validates")
	assert_eq(_errors({}, "ability.thunder_roar"), "", "Thunder Roar validates")
	assert_eq(_errors({}, "ability.stone_skin"), "", "Stone Skin validates")
	assert_true(_errors({"projectile": null}).contains("'projectile' is required for hit_shape 'projectile'"),
		"a projectile action needs its projectile block")
	assert_true(_errors({"projectile": {"speed_mps": 10, "radius_m": 0.2}}).contains("missing required key 'range_m'"),
		"speed, radius and range are required")
	assert_true(_errors({"projectile": {"speed_mps": 10, "radius_m": 0.2, "range_m": 5, "aim": "psychic"}}).contains("unknown value 'psychic'"),
		"aim is an AIM_MODES value")
	assert_true(_errors({"projectile": {"speed_mps": 10, "radius_m": 0.2, "range_m": 5, "spin": 2}}).contains("unknown key 'spin'"),
		"unknown projectile keys are errors")
	assert_true(_errors({"projectile": {"speed_mps": 10, "radius_m": 0.2, "range_m": 5, "visual": "laser"}}).contains("unknown value 'laser'"),
		"visual is a PROJECTILE_VISUALS value")
	assert_true(_errors({"sector_deg": null}, "ability.sweeping_blow").contains("'sector_deg' is required for hit_shape 'sector_pulse'"),
		"a sector pulse needs its angle")
	assert_true(_errors({"sector_deg": 400}, "ability.sweeping_blow").contains("must be <= 360"), "at most 360 degrees")
	assert_true(_errors({"radius_from": null}, "ability.sweeping_blow").contains("needs 'radius_m', 'radius_by_stage_m' or radius_from 'melee_reach'"),
		"a sector pulse needs a radius")
	assert_true(_errors({"radius_from": "arm"}, "ability.sweeping_blow").contains("unknown value 'arm'"), "radius_from enum")
	assert_true(_errors({"radius_by_stage_m": [3, 0]}, "ability.heavy_footfall").contains("radius_by_stage_m[1]: must be > 0"),
		"stage radii are positive")
	assert_true(_errors({"radius_by_stage_m": []}, "ability.heavy_footfall").contains("must list at least one radius"),
		"and there is at least one")
	assert_true(_errors({"self_statuses": [{"magnitude": 1}]}, "ability.stone_skin").contains("missing required key 'status'"),
		"a self status names its status")
	assert_true(_errors({"on_hit_statuses": [{"status": "status.slow", "when": "always"}]}, "ability.thunder_roar").contains("unknown key 'when'"),
		"on-hit status entries are strict")
	assert_true(_errors({"morale_damage": -1}, "ability.thunder_roar").contains("must be >= 0"), "morale damage >= 0")
	var refs: Array = DataValidator.validate_record(GameData.get_record("ability.thunder_roar"), "roar.json").refs
	var targets: Array = []
	for r: Dictionary in refs:
		targets.append(r.id)
	assert_true(targets.has("status.slow"), "on-hit statuses are status_effect references")
