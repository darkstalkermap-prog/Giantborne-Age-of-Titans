extends IntegrationSuite
## P30 (plan M6-M9 §2.10, §3.13 slow tests; slow, runs with --slow): routs fan out. On the formation
## test level encounter.formation_test_rout stands ten pikemen and a bannerman 10 m south of a wall
## whose 6 m gate leads north to three flee points (the formation's flee_points). A stage-4 giant
## comes from the south, the banner falls and the regiment routs: every routed member runs to one
## of the flee points (spread over at least two of them, so the gate does not jam), and all ten
## clear the gate within 8 s.

const LEVEL := "res://scenes/test/formation_test.tscn"
const ROUT := "encounter.formation_test_rout"
const GATE_Z := -40.0
const CLEAR_Z := GATE_Z - 1.5   # beyond the wall's far face
const LIMIT_S := 8.0


func test_ten_routed_members_clear_the_gate_within_8_s() -> void:
	var lv := (load(LEVEL) as PackedScene).instantiate() as LevelRoot
	world.add_child(lv)
	await step_ticks(2)
	var p := lv.player()
	for rec: Dictionary in GameData.records_of_type("growth_profile"):
		if int(rec.get("stage", 0)) == 4:
			p.set_profile(rec)
	p.entity.apply_status(StressScenario.STATUS_INVULNERABLE, NAN, -1.0, "test")
	p.global_position = Vector3(0, 0.05, -12)
	p.velocity = Vector3.ZERO
	var d := lv.director()
	d.force_activate(ROUT)
	d.update_now()
	await step_ticks(2)
	var f := d.formation(Formation.formation_id(ROUT, "rout"))
	assert_true(f != null, "the gate formation stands")
	if f == null:
		return
	assert_eq(f.members.size(), 10, "ten pikemen")
	assert_true(f.banner_alive(), "and its banner")
	assert_eq(f.flee_points.size(), 3, "three flee points beyond the gate")
	for m in f.all_members():
		m.brain.on_noise(Sim.tick, p.global_position, p.entity.entity_id, true)
	await step_ticks(30)
	# the banner falls; the regiment routs
	queue_hit(p.entity.entity_id, f.banner.entity_id, p.global_position, 100000.0)
	await step_ticks(1)
	var members: Array[EnemyActor] = f.members.duplicate()
	for m in members:
		m.p30_force_rout()
	var start := Sim.tick
	var limit := int(LIMIT_S * Sim.TICK_RATE)
	var cleared := {}
	var points := {}
	while Sim.tick - start < limit and cleared.size() < members.size():
		await step_ticks(6)
		for m in members:
			if not cleared.has(m.entity_id) and m.global_position.z < CLEAR_Z:
				cleared[m.entity_id] = float(Sim.tick - start) / Sim.TICK_RATE
			if m.brain.flee_point != Vector3.INF:
				points[Vector2i(roundi(m.brain.flee_point.x), roundi(m.brain.flee_point.z))] = true
	var stuck := PackedStringArray()
	for m in members:
		if not cleared.has(m.entity_id):
			stuck.append("%s at %s (%s)" % [m.entity_id, m.global_position.snapped(Vector3(0.1, 0.1, 0.1)), m.brain.state_name()])
	assert_eq(cleared.size(), 10, "all ten clear the gate within %.0f s (not: %s)" % [LIMIT_S, ", ".join(stuck)])
	assert_true(points.size() >= 2, "spread over the flee points (%d of them)" % points.size())
	var last := 0.0
	for id: String in cleared:
		last = maxf(last, float(cleared[id]))
	print("    test_formation_rout_gate: %d of 10 through the gate, the last after %.1f s, over %d flee points" % [
		cleared.size(), last, points.size()])
