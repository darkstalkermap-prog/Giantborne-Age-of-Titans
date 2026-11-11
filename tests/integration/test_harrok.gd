extends IntegrationSuite
## Harrok the Unbowed in the Moot's ring (plan M6-M9 §5.13 boss 3; P34) on scenes/test/moot_test.tscn:
## his second phase begins after two poise breaks (before 50 %), with the roar, exactly once in the
## attempt; its stones are hazards of his brain - two telegraphed circles at a time, 5-26 m from the
## giant and at least 14 m apart, announced with the giant as their target (the threat cues play at the
## stones) - that strike as his hits; the clans watching from outside the ring are neutral and deal
## nothing.

const MOOT := "res://scenes/test/moot_test.tscn"
const BB := preload("res://tools/builders/big.gd")

var level: Node3D
var phases: Array = []
var circles: Array = []


func before_each() -> void:
	await super()
	phases.clear()
	circles.clear()
	Events.boss_phase_changed.connect(_on_phase)
	Events.telegraph_started.connect(_on_tel)


func after_each() -> void:
	for sig: Signal in [Events.boss_phase_changed, Events.telegraph_started]:
		for c: Dictionary in sig.get_connections():
			if (c.callable as Callable).get_object() == self:
				sig.disconnect(c.callable)
	await super()


func _on_phase(_t: int, id: String, phase: int) -> void:
	phases.append([id, phase])


func _on_tel(_t: int, actor_id: String, action_id: String, target_id: String, shape: String, origin: Vector3,
		_yaw: float, radius: float, _length: float, duration_s: float) -> void:
	circles.append({"actor": actor_id, "action": action_id, "target": target_id, "shape": shape, "origin": origin,
		"radius": radius, "duration": duration_s})


func _load() -> Dictionary:
	level = (load(MOOT) as PackedScene).instantiate() as Node3D
	world.add_child(level)
	var p := level.get_node("Player") as GiantPlayer
	p.router.use_injection = true
	await step_ticks(2)
	return {"player": p, "arena": level.get_node("BossArena") as BossArena,
		"harrok": level.get_node("Harrok") as RivalGiantEnemy}


func test_phase_two_after_two_poise_breaks_once_with_his_stones() -> void:
	var n := await _load()
	var p: GiantPlayer = n.player
	var h: RivalGiantEnemy = n.harrok
	var arena: BossArena = n.arena
	assert_eq(h.entity_id, BB.MOOT_ID, "Harrok stands in the ring")
	assert_true(h.brain is HarrokBrain, "his brain places the stones")
	assert_false(h.can_be_grabbed(), "never grabbable")
	arena.engage()
	assert_true(arena.is_engaged(), "engaged")
	for i in 2:
		if h.controller.state == CombatController.State.STAGGERED:
			h.controller.call("_end_stagger")
		h.entity.combatant.poise.immunity_left = 0.0
		var e := HitEvent.new()
		e.tick = Sim.tick
		e.instance_id = Sim.new_instance_id()
		e.attacker_id = p.entity.entity_id
		e.target_id = h.entity_id
		e.power = 1.0
		e.poise_damage = 1.0e5
		e.size_policy = "none"
		e.tags = PackedStringArray(["Melee"])
		e.attacker_position = h.global_position + Vector3(0, 0, 8)
		Sim.queue_hit(e)
		await step_ticks(1)
	assert_eq(h.poise_breaks, 2, "two poise breaks")
	assert_eq(h.brain.boss_phase(), 1, "not while he reels: the roar never cuts the stagger short")
	h.controller.call("_end_stagger")
	await step_ticks(2)
	assert_eq(h.brain.boss_phase(), 2, "phase 2 after two poise breaks")
	assert_true(h.entity.combatant.pools.ratio("health") > 0.9, "long before 50 %")
	assert_eq(h.attempt_phases, [2] as Array[int], "entered once")
	assert_eq(phases, [[BB.MOOT_ID, 2]], "announced once")
	assert_eq(h.controller.action_id(), "ability.harrok_roar", "with the roar")
	h.entity.combatant.pools.health = 1000.0
	await step_ticks(2)
	assert_eq(h.attempt_phases, [2] as Array[int], "never again in this attempt")
	assert_eq(h.brain.phase_hazard(), "ability.moot_stones", "phase 2's hazard")
	# The stones: frozen in time (his own step paused), driven tick by tick.
	h.process_mode = Node.PROCESS_MODE_DISABLED
	var hb := h.brain as HarrokBrain
	hb.p34_clear_hazards()
	hb.target_id = p.entity.entity_id
	p.global_position = Vector3(0, 0.05, 0)
	await step_ticks(1)
	circles.clear()
	var t0 := Sim.tick + 1000
	h._hazard_step(t0)
	assert_eq(circles.size(), 0, "the first stones wait for the roar")
	h._hazard_step(t0 + 96)
	assert_eq(circles.size(), 2, "two telegraphed circles at a time")
	var pts: Array = []
	for c: Dictionary in circles:
		assert_true(str(c.actor).begins_with(BB.MOOT_ID + "#stone"), "keyed to the stone, his")
		assert_eq(str(c.action), "ability.moot_stones", "the Moot's stones")
		assert_eq(str(c.target), p.entity.entity_id, "the giant is their target (threat cues)")
		assert_eq(str(c.shape), "circle", "circles")
		assert_near(float(c.radius), 6.0, 0.01, "6 m")
		assert_near(float(c.duration), 1.6, 0.01, "1.6 s of warning")
		var d := Vector2((c.origin as Vector3).x - p.global_position.x, (c.origin as Vector3).z - p.global_position.z).length()
		assert_true(d >= 5.0 - 0.01 and d <= 26.0 + 0.01, "5-26 m from the giant")
		pts.append(c.origin)
	assert_true((pts[0] as Vector3).distance_to(pts[1]) >= 14.0 - 0.01, "at least 14 m apart")
	h._hazard_step(t0 + 120)
	assert_eq(circles.size(), 2, "no more while two are up")
	var before := h.hazard_pulses
	h._hazard_step(t0 + 192)
	assert_eq(h.hazard_pulses - before, 2, "both strike when due")
	# A stone on the giant is Harrok's hit.
	hits.clear()
	h.runner.p34_hazard_pulse(GameData.get_action("ability.moot_stones"), p.global_position, Sim.tick)
	await step_ticks(1)
	var on_p := hits_on(p.entity.entity_id)
	assert_eq(on_p.size(), 1, "a stone on the giant hits it")
	assert_eq(on_p[0].event.attacker_id, BB.MOOT_ID, "credited to Harrok")
	assert_eq(on_p[0].event.action_id, "ability.moot_stones", "with the stones")
	h.process_mode = Node.PROCESS_MODE_INHERIT


func test_the_watching_clans_deal_nothing() -> void:
	var n := await _load()
	var h: RivalGiantEnemy = n.harrok
	var watchers: Array = []
	for spec: Array in BB.MOOT_WATCHERS:
		var e := Sim.get_entity(str(spec[0]))
		assert_true(e != null, "%s watches" % spec[0])
		watchers.append(e)
		assert_eq(e.team, CombatEntity.Team.NEUTRAL, "neutral")
		assert_false(e.actor.ai_enabled, "they only watch")
		var d := Vector2(e.actor.global_position.x, e.actor.global_position.z).length()
		assert_true(d > BB.MOOT_RADIUS, "outside the ring")
	(n.arena as BossArena).engage()
	hits.clear()
	h.runner.p34_hazard_pulse(GameData.get_action("ability.moot_stones"), (watchers[0] as CombatEntity).actor.global_position, Sim.tick)
	await step_ticks(30)
	for r in hits:
		for w: CombatEntity in watchers:
			assert_true(r.event.attacker_id != w.entity_id, "no hit by a watcher")
			assert_true(r.event.target_id != w.entity_id, "and the stones spare them")
