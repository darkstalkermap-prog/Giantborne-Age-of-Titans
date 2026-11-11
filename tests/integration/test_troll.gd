extends IntegrationSuite
## Trolls and dire wolves (plan M6-M9 §2.10, §3.18; P34): a hurt troll regenerates every second and
## shows the green pulse - not while it burns (the orange flicker instead); a 5.5 m troll can be grabbed
## by a stage-5 giant but is too tall for stage 4; the 9 m Matriarch is too tall at stage 5 and the
## refused grab spends nothing; a fire-tagged prop broken near a troll sets it burning; a troll or whelp
## set down in the fire pit comes out burning. (Dire wolves harassing a giant that outmatches them: the
## slow battery, tests/slow/test_big_battery.)

const TROLL := "res://scenes/enemies/troll.tscn"
const WHELP := "res://scenes/enemies/troll_whelp.tscn"
const MATRIARCH := "res://scenes/enemies/troll_matriarch.tscn"


func _spawn(path: String, id: String, pos: Vector3, ai := false) -> EnemyActor:
	var e := (load(path) as PackedScene).instantiate() as EnemyActor
	e.entity_id = id
	e.ai_enabled = ai
	e.position = pos
	world.add_child(e)
	return e


func test_a_hurt_troll_regenerates_unless_it_burns() -> void:
	var t := _spawn(TROLL, "test.troll_1", Vector3(0, 0.05, 0)) as TrollEnemy
	await step_ticks(2)
	var pools := t.entity.combatant.pools
	assert_eq(pools.health_max, 1100.0, "1,100 health")
	pools.health = 500.0
	var tick := Sim.tick + 120
	t.p34_regen_step(tick)
	assert_near(pools.health, 512.0, 0.01, "12 hp in a second")
	assert_eq(t.regen_heals, 1, "one heal")
	assert_true(t.p34_regenerating(), "the regeneration marker is on")
	t.p34_regen_step(tick + 30)
	assert_near(pools.health, 512.0, 0.01, "at most once a second")
	assert_true(t.p34_ignite(8.0, "test"), "set burning")
	t.p34_regen_step(tick + 60)
	assert_near(pools.health, 512.0, 0.01, "no regeneration while it burns")
	assert_true(t.p34_regen_blocked(), "Burning blocks it")
	t.entity.combatant.statuses.remove("status.burning")
	t.p34_regen_step(tick + 120)
	assert_near(pools.health, 524.0, 0.01, "it regenerates again once the fire is out")
	pools.health = pools.health_max
	var before := t.regen_heals
	t.p34_regen_step(tick + 180)
	assert_eq(t.regen_heals, before, "an unhurt troll does not regenerate")


func test_the_regeneration_tint_pulses_green_and_burning_flickers_orange() -> void:
	var t := _spawn(TROLL, "test.troll_1", Vector3(0, 0.05, 0)) as TrollEnemy
	await step_ticks(2)
	t.entity.combatant.pools.health = 600.0
	t.p34_regen_step(Sim.tick + 60)
	t._process(0.2)
	assert_true(t.tint.a > 0.05, "a tint shows while it regenerates")
	assert_true(t.tint.g > t.tint.r and t.tint.g > t.tint.b, "green")
	assert_true(t.rig.status_tint().is_equal_approx(t.tint), "painted on the rig")
	var a0 := t.tint.a
	t._process(0.4)
	assert_true(absf(t.tint.a - a0) > 0.001, "it pulses")
	t.p34_ignite(8.0)
	t._process(0.05)
	assert_true(t.tint.r > t.tint.g, "orange while it burns")
	t.entity.combatant.statuses.clear()
	t._process(0.05)
	assert_eq(t.tint.a, 0.0, "no tint without regeneration or fire")


func test_a_troll_is_grabbed_at_stage_5_not_4_and_the_matriarch_never() -> void:
	var p := spawn_player(Vector3(0, 0.05, 10))
	await step_ticks(2)
	var t := _spawn(TROLL, "test.troll_1", Vector3(0, 0.05, 4)) as TrollEnemy
	var m := _spawn(MATRIARCH, "test.matriarch_1", Vector3(14, 0.05, 6)) as TrollEnemy
	await step_ticks(2)
	t.controller.apply_stagger(3.0, "poise_broken")
	m.controller.apply_stagger(3.0, "poise_broken")
	assert_true(p.growth.debug_set_stage(4).ok, "stage 4")
	assert_eq(p.grab.check_target(t.entity, "hold", "", 50.0), "too_tall", "5.5 m is more than half of 10.97 m")
	assert_true(p.growth.debug_set_stage(5).ok, "stage 5")
	assert_eq(p.grab.check_target(t.entity, "hold", "", 50.0), "", "a stage-5 giant can grab a troll with both hands")
	assert_eq(t.grab_attach(), "two_hand", "two hands")
	assert_eq(p.grab.check_target(m.entity, "hold", "", 50.0), "too_tall", "the 9 m Matriarch is too tall at stage 5")
	assert_false(m.can_be_grabbed(), "and never grabbable")
	# The refused grab spends nothing (P26): only the Matriarch in reach.
	t.queue_free()
	await step_ticks(1)
	m.global_position = p.global_position + Vector3(0, 0, -6)
	var stamina := p.entity.combatant.pools.stamina
	p.grab.try_grab()
	await step_ticks(2)
	assert_eq(p.entity.combatant.pools.stamina, stamina, "no stamina spent")
	assert_false(p.grab.is_holding(), "nothing held")
	assert_eq(p.controller.action_id(), "", "no grab action ran")


func test_fire_from_a_brazier_and_the_pit() -> void:
	var t := _spawn(TROLL, "test.troll_1", Vector3(0, 0.05, 0)) as TrollEnemy
	var w := _spawn(WHELP, "test.whelp_1", Vector3(20, 0.05, 0)) as TrollEnemy
	var brazier := spawn_fence(Vector3(5, 0, 0), "test.brazier_1")
	var far := spawn_fence(Vector3(-30, 0, 0), "test.brazier_2")
	var pit := Node3D.new()
	pit.add_to_group(TrollEnemy.FIRE_PIT_GROUP)
	pit.set_meta("radius_m", 4.0)
	world.add_child(pit)
	pit.global_position = Vector3(30, 0, 20)
	await step_ticks(2)
	for b: BreakableProp in [brazier, far]:
		b.record = b.record.duplicate(true)
		b.record["prop_tags"] = ["fire"]
	Events.object_destroyed.emit(Sim.tick, "test.brazier_2", "player")
	assert_false(t.p34_has_status_tag("Burning"), "a brazier 30 m away does nothing")
	Events.object_destroyed.emit(Sim.tick, "test.brazier_1", "player")
	assert_true(t.p34_has_status_tag("Burning"), "a brazier broken within 8 m sets it burning")
	assert_near(t.entity.combatant.statuses.remaining_s("status.burning", Sim.tick), 8.0, 0.05, "for 8 s")
	# A whelp set down in the fire pit comes out burning.
	assert_true(w.controller.enter_grabbed("player"), "held")
	w.on_grabbed("player")
	w.carry(Vector3(30, 1.0, 20), Basis(), w.body_centre_local())
	w.on_released("thrown", [Vector3(30, 0.05, 20)])
	assert_true(w.p34_has_status_tag("Burning"), "out of the pit burning")
