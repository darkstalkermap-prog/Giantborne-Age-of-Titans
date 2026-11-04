extends TestSuite
## ResourcePool and PoiseMeter: never negative, regen delays and pauses, fury rules, poise.


func _pool() -> ResourcePool:
	var p := ResourcePool.new()
	p.configure({"health": 500, "stamina": 100, "essence": 100, "fury_max": 100},
		{"stamina_per_s": 15, "stamina_delay_s": 1.0, "essence_per_s": 4, "essence_delay_s": 2.0,
		"fury_decay_per_s": 5, "fury_decay_delay_s": 10})
	return p


func test_spend_is_all_or_nothing() -> void:
	var p := _pool()
	assert_true(p.spend_stamina(60.0), "spend 60")
	assert_false(p.spend_stamina(41.0), "cannot overspend")
	assert_near(p.stamina, 40.0, 1e-9, "unchanged after refusal")
	assert_near(p.consume_stamina_up_to(1000.0), 40.0, 1e-9, "consume takes only what exists")
	assert_near(p.stamina, 0.0, 1e-9, "exactly zero, never negative")


func test_stamina_regen_delay_and_pause() -> void:
	var p := _pool()
	p.spend_stamina(50.0)
	for i in 59:
		p.tick(1.0 / 60.0, true)
	assert_near(p.stamina, 50.0, 1e-9, "no regen during the first second")
	for i in 61:
		p.tick(1.0 / 60.0, true)
	assert_true(p.stamina > 50.0 and p.stamina < 50.0 + 15.0 * 1.05, "15/s after the delay (got %s)" % p.stamina)
	var frozen := p.stamina
	for i in 60:
		p.tick(1.0 / 60.0, false)
	assert_near(p.stamina, frozen, 1e-9, "paused while blocking/sprinting/attacking")


func test_random_operations_never_go_negative() -> void:
	var p := _pool()
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in 20000:
		match rng.randi_range(0, 5):
			0:
				p.spend_stamina(rng.randf_range(0.0, 40.0))
			1:
				p.consume_stamina_up_to(rng.randf_range(0.0, 60.0))
			2:
				p.tick(rng.randf_range(0.0, 0.1), rng.randf() < 0.5)
			3:
				p.add_fury(rng.randf_range(-20.0, 20.0))
			4:
				p.spend_essence(rng.randf_range(0.0, 30.0))
			5:
				p.damage_health(rng.randf_range(0.0, 30.0))
		if p.stamina < 0.0 or p.essence < 0.0 or p.fury < 0.0 or p.health < 0.0:
			fail("negative resource after %d operations" % i)
			return
		if p.stamina > p.stamina_max + 1e-9 or p.fury > p.fury_max + 1e-9:
			fail("resource above max after %d operations" % i)
			return
	assert_true(true, "20000 random operations")


func test_fury_decay_outside_combat() -> void:
	var p := _pool()
	p.add_fury(30.0)
	p.mark_combat()
	for i in 599:
		p.tick(1.0 / 60.0, true)
	assert_near(p.fury, 30.0, 1e-9, "no decay within 10 s of combat")
	for i in 61:
		p.tick(1.0 / 60.0, true)
	assert_true(p.fury < 30.0, "decays at 5/s after 10 s")
	p.add_fury(500.0)
	assert_near(p.fury, 100.0, 1e-9, "capped at 100")


func test_essence_regen() -> void:
	var p := _pool()
	p.spend_essence(40.0)
	for i in 119:
		p.tick(1.0 / 60.0, true)
	assert_near(p.essence, 60.0, 1e-9, "2 s delay")
	for i in 61:
		p.tick(1.0 / 60.0, true)
	assert_near(p.essence, 64.0, 0.1, "4/s afterwards")


func test_poise_threshold_recovery_and_immunity() -> void:
	var m := PoiseMeter.new()
	m.configure({"threshold": 100, "recover_per_s": 20, "recover_delay_s": 3.0, "stagger_s": 1.0, "immunity_s": 1.5})
	for i in 8:
		assert_false(m.add(12.0), "light %d does not break" % i)
	assert_true(m.add(12.0), "9th light (108) breaks 100")
	assert_near(m.value, 0.0, 1e-9, "meter resets")
	m.begin_stagger()
	assert_false(m.add(500.0), "no poise damage while staggered")
	m.end_stagger()
	assert_false(m.add(500.0), "immune right after recovery")
	for i in 90:
		m.tick(1.0 / 60.0)
	assert_false(m.is_immune(), "immunity lasts 1.5 s")
	assert_false(m.add(35.0), "heavy adds 35")
	for i in 180:
		m.tick(1.0 / 60.0)
	assert_near(m.value, 35.0, 0.5, "no recovery for 3 s")
	for i in 60:
		m.tick(1.0 / 60.0)
	assert_near(m.value, 15.0, 0.5, "recovers 20/s afterwards")


func test_constitution_raises_threshold() -> void:
	var m := PoiseMeter.new()
	m.configure({"threshold": 100}, 14.0)
	assert_near(m.threshold, 112.0, 1e-9, "3 per point above 10")
