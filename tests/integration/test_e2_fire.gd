extends IntegrationSuite
## E2 (decision E2-2): the Cinder Titan's fire, its rules without his AI - PlayerHeat (a bigger giant takes less; full,
## he is ablaze until he has cooled to ABLAZE_UNTIL; water cools him fast, time slowly; never saved), the burning
## ground (CinderEnemy.lay_burn: a giant standing in it heats; nothing burns on water; the oldest go out past
## burn_max; his fall puts them all out), his molten crust (PlateSet.heat_mult: hot every blow at hot_mult, quenched
## whole), the quench (water quench_depth_m deep at his feet: brittle and a reel; quench_down_depth_m deep: down on a
## knee; melting again after quench_s) and the scorch on an ablaze giant (his hit, every scorch_every_s).

const CINDER := "res://scenes/enemies/cinder.tscn"


func before_each() -> void:
	await super()
	GameSession.expansion = ExpansionState.defaults()


func after_each() -> void:
	GameSession.expansion = ExpansionState.defaults()
	await super()


func _player(stage := 9, at := Vector3(0, 0.05, 0)) -> GiantPlayer:
	var p := spawn_player(at, 0.0)
	await TestWait.until(self, func() -> bool: return p.is_on_floor(), 30)
	TitanDuel.prepare(p, stage)
	p.router.use_injection = true
	await step_ticks(2)
	return p


func _titan(at: Vector3) -> CinderEnemy:
	var t := (load(CINDER) as PackedScene).instantiate() as CinderEnemy
	t.entity_id = "test.e2.cinder"
	t.position = at
	t.ai_enabled = false
	world.add_child(t)
	await step_ticks(2)
	t.dormant = false
	return t


func _water(at: Vector3, r: float, depth: float) -> StormWater:
	var w := StormWater.new()
	w.pools = [[0.0, 0.0, r, r, depth]]
	w.position = Vector3(at.x, 0.0, at.z)
	world.add_child(w)
	await step_ticks(1)
	return w


func test_heat_by_size_ablaze_and_cooling() -> void:
	var p := await _player(9)
	assert_true(p.heat != null, "the giant carries the heat component")
	var took9: float = p.heat.add_heat(50.0, "test")
	assert_near(took9, 35.0, 0.01, "stage 9: 0.7 of it takes hold")
	p.heat.shed_heat(100.0)
	TitanDuel.prepare(p, 8)
	await step_ticks(2)
	var took8: float = p.heat.add_heat(50.0, "test")
	assert_near(took8, 50.0, 0.01, "stage 8: all of it")
	p.heat.add_heat(80.0, "test")
	assert_true(p.heat.is_ablaze(), "full: ablaze")
	await step_ticks(30)
	assert_true(p.heat.is_ablaze(), "it does not go out by itself at once")
	var w := await _water(p.global_position, 20.0, 3.0)
	await step_ticks(90)
	assert_false(p.heat.is_ablaze(), "water puts it out")
	assert_true(float(p.heat.heat) < PlayerHeat.ABLAZE_UNTIL, "and cools him (%.0f)" % float(p.heat.heat))
	assert_true(bool(p.heat.wading), "standing in it")
	w.queue_free()
	var st := p.capture_character_state() if p.has_method("capture_character_state") else {}
	assert_false(JSON.stringify(st).contains("\"heat\""), "the heat is never saved")


func test_the_burning_ground() -> void:
	var p := await _player(9, Vector3(0, 0.05, 30))
	var t := await _titan(Vector3(0, 0.05, -30))
	assert_true(t.lay_burn(Vector3(0, 0, 30), 6.0, 40.0), "a patch laid under the giant")
	var before: float = p.heat.heat
	for i in 60:
		t._heat_giants(Sim.tick, 1.0 / 60.0)
		await step_ticks(1)
	var gained: float = p.heat.heat - before
	assert_near(gained, 16.0 * 0.7, 1.0, "a second in it: burn_heat_per_s by his stage (%.1f)" % gained)
	var w := await _water(Vector3(40, 0, 0), 10.0, 1.0)
	assert_false(t.lay_burn(Vector3(40, 0, 0), 6.0, 40.0), "nothing burns on water")
	w.queue_free()
	for i in 45:
		t.lay_burn(Vector3(-60 + i * 2.0, 0, -80), 4.0, 0.0)
	assert_eq(t.patches.size(), int(t.cinder.burn_max), "the oldest go out past burn_max")
	assert_true(CinderEnemy.burn_at(get_tree(), Vector3(28.0, 0, -80)), "the static lookup sees his fire")
	t.clear_burn()
	assert_eq(t.patches.size(), 0, "his fall (or a new attempt) puts it all out")


func test_the_crust_and_the_quench() -> void:
	var p := await _player(9, Vector3(0, 0.05, 60))
	var t := await _titan(Vector3(0, 0.05, 0))
	assert_near(t.entity.plates.heat_mult, 0.45, 0.001, "hot: every blow at hot_mult")
	assert_false(t.is_quenched(), "hot at first")
	var w := await _water(Vector3(0, 0, 0), 15.0, 2.5)
	t.ai_enabled = true
	t._e2_step(Sim.tick, 1.0 / 60.0)
	t.ai_enabled = false
	assert_true(t.is_quenched(), "water 2.5 m deep at his feet quenches him")
	assert_near(t.entity.plates.heat_mult, 1.0, 0.001, "quenched: blows land whole")
	assert_eq(t.controller.stagger_reason, CinderEnemy.QUENCH_REASON, "and he reels in the steam")
	assert_false(t.is_down(), "not down: the beck is not deep enough")
	var left := t.quench_left_s()
	assert_near(left, float(t.cinder.quench_s), 0.1, "brittle quench_s")
	w.queue_free()
	await step_ticks(int((left + 0.2) * 60.0))
	t._e2_step(Sim.tick, 1.0 / 60.0)
	assert_false(t.is_quenched(), "the crust melts again")
	assert_near(t.entity.plates.heat_mult, 0.45, 0.001, "hot again")
	t._quench_ready = -1
	await step_ticks(int(float(t.cinder.quench_cooldown_s) * 60.0) + 2)
	assert_true(t.quench(true), "deep water: quenched again")
	assert_true(t.is_down(), "on a knee in the steam (the dammed water)")
	assert_eq(t.quench_downs, 1, "counted")
	assert_true(p != null, "the giant stood by")


func test_an_ablaze_giant_burns_by_his_hand() -> void:
	var p := await _player(8, Vector3(0, 0.05, 40))
	var t := await _titan(Vector3(0, 0.05, -40))
	hits.clear()
	p.heat.add_heat(200.0, "test")
	assert_true(p.heat.is_ablaze(), "ablaze")
	for i in 150:
		t._heat_giants(Sim.tick, 1.0 / 60.0)
		await step_ticks(1)
	var scorches := 0
	for r in hits:
		if r.event.action_id == "ability.cinder_scorch" and r.event.target_id == p.entity.entity_id:
			scorches += 1
			assert_eq(r.event.attacker_id, t.entity.entity_id, "his hit: a death by it is his kill")
	assert_true(scorches >= 2, "struck every scorch_every_s while ablaze (%d)" % scorches)
	assert_true(t != null, "the titan")
