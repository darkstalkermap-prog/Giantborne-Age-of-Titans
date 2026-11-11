extends IntegrationSuite
## P34's slow battery (plan M6-M9 §3.18; budget 20 s): what takes real seconds of the simulation.
##   * a rival giant's shoulder charge runs straight and ends against stone in the 2.5 s recovery;
##   * dire wolves harass a stage-4 giant that outmatches them;
##   * the Matriarch's whelp throw flies a whelp of her brood at the giant (a thrown_body launched by an
##     enemy) and the whelp lands and fights on;
##   * a burning whelp the giant grabs and throws into her sets her burning and burns her for 300;
##   * the disengage rule at its full 5 s;
##   * the battle's web composition: fewer units, a smaller aggregate, the same phases; the attempt
##     reset brings the fallen back and the phases begin again once each;
##   * Harrok's stones in real time: two circles 1.6 s before they strike, then the next wave.

const RIVAL := "res://scenes/enemies/rival_giant.tscn"
const DIRE_WOLF := "res://scenes/enemies/dire_wolf.tscn"
const DEN := "res://scenes/test/troll_den_test.tscn"
const MOOT := "res://scenes/test/moot_test.tscn"
const BAILEY := "res://scenes/test/bailey_test.tscn"
const BB := preload("res://tools/builders/big.gd")

var gone: Array = []


func before_each() -> void:
	await super()
	gone.clear()
	WorldState.clear()
	Events.boss_disengaged.connect(_on_disengaged)


func after_each() -> void:
	if Events.boss_disengaged.is_connected(_on_disengaged):
		Events.boss_disengaged.disconnect(_on_disengaged)
	LevelRoot.force_web_for_tests = false
	Quests.end_dialogue()
	await super()


func _on_disengaged(_t: int, id: String, reason: String) -> void:
	gone.append([id, reason])


func _scene(path: String) -> Node3D:
	var level := (load(path) as PackedScene).instantiate() as Node3D
	world.add_child(level)
	var p := level.get_node("Player") as GiantPlayer
	p.router.use_injection = true
	await step_ticks(2)
	return level


func _kill(id: String) -> void:
	var e := Sim.get_entity(id)
	if e == null or not e.is_alive():
		return
	var h := HitEvent.new()
	h.tick = Sim.tick
	h.instance_id = Sim.new_instance_id()
	h.attacker_id = "player"
	h.target_id = id
	h.power = 1.0e6
	h.size_policy = "none"
	h.damage_split = {"physical": 1.0}
	h.tags = PackedStringArray(["Melee", "Unblockable", "Unparryable"])
	h.attacker_position = e.actor.global_position + Vector3(0, 0, 4)
	Sim.queue_hit(h)


func test_the_shoulder_charge_ends_against_stone() -> void:
	add_box(Vector3(40, 12, 2), Vector3(0, 6, -16))
	var p := spawn_player(Vector3(30, 0.05, 20))
	var g := (load(RIVAL) as PackedScene).instantiate() as RivalGiantEnemy
	g.entity_id = "test.rival_1"
	g.ai_enabled = false
	g.position = Vector3(0, 0.05, 6)
	world.add_child(g)
	await step_ticks(2)
	g.brain.target_id = p.entity.entity_id
	var a := GameData.get_action("ability.giant_shoulder_charge")
	assert_eq(a.hit_shape, "body_sweep", "the charge is a body sweep")
	g.controller.force_action(a)
	var ended := await TestWait.until(self, func() -> bool: return g.wall_stops > 0, a.windup_ticks + 160)
	assert_true(ended, "the charge ends against the wall")
	assert_eq(g.controller.action_id(), "ability.giant_charge_recover", "in its punishable recovery")
	assert_true(g.get_rig_state().get("staggered", false), "reeling (shown like a stagger)")
	assert_true(g.global_position.z > -16.0 + 2.2 - 0.5, "stopped at the stone, not through it")
	assert_near(float(GameData.get_action("ability.giant_charge_recover").recovery_ticks) / 60.0, 2.45, 0.02,
		"2.5 s to punish")


func test_dire_wolves_harass_a_giant_that_outmatches_them() -> void:
	var p := spawn_player(Vector3(0, 0.05, 14))
	await TestWait.until(self, func() -> bool: return p.is_on_floor(), 30)
	assert_true(p.growth.debug_set_stage(4).ok, "stage 4")
	var w := (load(DIRE_WOLF) as PackedScene).instantiate() as EnemyActor
	w.entity_id = "test.dire_wolf_1"
	w.position = Vector3(0, 0.05, -4)
	world.add_child(w)
	var rec := GameData.get_record("enemy.dire_wolf")
	assert_eq(float(rec.height_m), 1.8, "a 1.8 m dire wolf")
	assert_eq(float(rec.health), 260.0, "health 260")
	await TestWait.until(self, func() -> bool: return w.brain.is_outmatched(), 60)
	assert_true(w.brain.is_outmatched(), "a stage-4 giant outmatches it (10.97 / 1.8 = 6.1)")
	assert_eq(w.brain.outmatched_behavior(), "harass", "it harasses")
	await step_ticks(90)
	assert_true(w.brain.state != EnemyBrain.AIState.FLEE and w.brain.state != EnemyBrain.AIState.ROUTED,
		"it does not run: it harasses")
	assert_true(w.entity.is_alive(), "and lives")


func test_the_whelp_throw_flies_a_whelp_at_the_giant() -> void:
	var level := await _scene(DEN)
	var p := level.get_node("Player") as GiantPlayer
	var m := level.get_node("TrollMatriarch") as TrollEnemy
	(level.get_node("BossArena") as BossArena).engage()
	p.global_position = m.global_position + Vector3(0, 0, 22)
	m.brain.target_id = p.entity.entity_id
	m.ai_enabled = false
	var a := GameData.get_action("ability.troll_throw_whelp")
	m.controller.force_action(a)
	var thrown := await TestWait.until(self, func() -> bool: return m.whelp_throws > 0, a.windup_ticks + 6)
	assert_true(thrown, "the throw carries a whelp")
	var system := ProjectileSystem.instance(get_tree())
	assert_eq(system.carried_count(), 1, "a thrown body in the air")
	var w: TrollEnemy = null
	for node in get_tree().get_nodes_in_group("enemies"):
		var t := node as TrollEnemy
		if t != null and t.entity.definition_id == "enemy.troll_whelp" and t.is_held():
			w = t
	assert_true(w != null, "the whelp rides it")
	var landed := await TestWait.until(self, func() -> bool: return not w.is_held(), 120)
	assert_true(landed, "it lands")
	assert_true(w.entity.is_alive(), "and lives to fight on")
	assert_true(w.global_position.distance_to(p.global_position) < 22.0, "near the giant, not at her feet")


func test_a_burning_whelp_thrown_into_her() -> void:
	var level := await _scene(DEN)
	var p := level.get_node("Player") as GiantPlayer
	var m := level.get_node("TrollMatriarch") as TrollEnemy
	m.ai_enabled = false
	await TestWait.until(self, func() -> bool: return p.is_on_floor(), 30)
	assert_true(p.growth.debug_set_stage(3).ok, "stage 3 (a whelp is 3.5 m)")
	var w := Sim.get_entity(str(BB.DEN_WHELPS[0][0])).actor as TrollEnemy
	w.ai_enabled = false
	p.global_position = m.global_position + Vector3(0, 0, 16)
	p.rotation.y = 0.0
	p.camera_rig.yaw = 0.0
	await step_ticks(2)
	w.global_position = p.global_position + Vector3(0, 0, -3)
	await step_ticks(2)
	w.controller.apply_stagger(3.0, "poise_broken")
	p.grab.try_grab()
	var held := await TestWait.until(self, func() -> bool: return p.grab.is_holding(), 60)
	assert_true(held, "the giant holds the whelp")
	w.p34_ignite(10.0, "test")
	p.lock.target_id = m.entity.entity_id
	p.targeting.sync_lock(m.entity.entity_id, "test")
	var before := m.entity.combatant.pools.health
	var thrown := await TestWait.until(self, func() -> bool:
		if p.grab.is_holding():
			p.grab.try_throw()   # (buffered while the grab's own action ends)
		return not p.grab.is_holding(), 120)
	assert_true(thrown, "the giant throws it at her")
	var burnt := await TestWait.until(self, func() -> bool: return m.p34_has_status_tag("Burning"), 120)
	assert_true(burnt, "the burning whelp sets her burning")
	assert_true(m.entity.combatant.statuses.remaining_s("status.burning", Sim.tick) > 9.5, "for 10 s")
	await step_ticks(1)
	var fire := 0.0
	for r in hits_on(BB.DEN_ID):
		if r.event.action_id == "fire.thrown_body":
			fire += r.health_damage
			assert_eq(r.event.attacker_id, p.entity.entity_id, "the fire is the giant's")
	assert_true(fire >= 300.0, "300 fire on impact (a troll's skin burns worse): %.0f" % fire)
	assert_true(before - m.entity.combatant.pools.health >= fire - 0.01, "she lost it")


func test_the_disengage_rule_at_five_seconds() -> void:
	var level := await _scene(DEN)
	var p := level.get_node("Player") as GiantPlayer
	var arena := level.get_node("BossArena") as BossArena
	var m := level.get_node("TrollMatriarch") as TrollEnemy
	arena.engage()
	m.entity.combatant.pools.health = 1000.0
	p.global_position = Vector3(0, 0.05, 60)
	await step_ticks(290)
	assert_eq(gone, [], "not before 5 s")
	assert_true(arena.is_engaged(), "still engaged at 4.8 s")
	await step_ticks(20)
	assert_eq(gone, [[BB.DEN_ID, "left"]], "after 5 s: boss_disengaged(left)")
	assert_eq(m.entity.combatant.pools.health, m.entity.combatant.pools.health_max, "home at full health")


func test_the_battle_on_the_web_and_a_new_attempt() -> void:
	LevelRoot.force_web_for_tests = true
	var level := await _scene(BAILEY)
	var battle := level.get_node("BattleBoss") as BattleBoss
	var d := level.get_node("EncounterDirector") as EncounterDirector
	(level.get_node("Player") as GiantPlayer).global_position = Vector3(0, 0.05, 30)
	battle.engage()
	await step_ticks(2)
	var planned := battle.planned()
	assert_eq(planned.size(), 16, "the web's composition: 8 shields and the banner, 4 riders, 2 guards, Corvane")
	assert_near(battle.total_health(), 9 * 260.0 + 4 * 400.0 + 2 * 300.0 + 600.0, 0.01, "a smaller aggregate")
	var spawned := 0
	for id in d.members_of("encounter.bailey_test_wall"):
		if Sim.get_entity(id) != null:
			spawned += 1
	assert_eq(spawned, 9, "what actually spawned is what the bar counts")
	for id in d.members_of("encounter.bailey_test_wall"):
		_kill(id)
	await step_ticks(3)
	assert_eq(battle.phase_log, [1, 2] as Array[int], "The Charge at the web's 60 %")
	# Leave: the battle resets; come back: the phases begin again, once each.
	battle.disengage_s = 0.25
	(level.get_node("Player") as GiantPlayer).global_position = Vector3(0, 0.05, 90)
	await step_ticks(20)
	assert_eq(gone, [[BB.BAILEY_ID, "left"]], "boss_disengaged(battle.iron_regiment, left)")
	assert_eq(battle.phase_log, [] as Array[int], "the phases start again")
	assert_eq(d.encounter_state("encounter.bailey_test_wall"), "dormant", "the wall is reset")
	await step_ticks(2)
	(level.get_node("Player") as GiantPlayer).global_position = Vector3(0, 0.05, 30)
	battle.engage()
	await step_ticks(3)
	assert_eq(battle.phase_log, [1] as Array[int], "a new attempt at The Wall")
	var back := 0
	for id in d.members_of("encounter.bailey_test_wall"):
		var e := Sim.get_entity(id)
		if e != null and e.is_alive():
			back += 1
	assert_eq(back, 9, "the fallen are back for the new attempt")
	assert_near(battle.aggregate_fraction(), 1.0, 1e-6, "the full aggregate")


func test_harroks_stones_in_real_time() -> void:
	var level := await _scene(MOOT)
	var p := level.get_node("Player") as GiantPlayer
	var h := level.get_node("Harrok") as RivalGiantEnemy
	(level.get_node("BossArena") as BossArena).engage()
	p.global_position = Vector3(0, 0.05, 20)
	h.entity.combatant.pools.health = h.entity.combatant.pools.health_max * 0.45
	var hb := h.brain as HarrokBrain
	var entered := await TestWait.until(self, func() -> bool: return hb.boss_phase() == 2, 10)
	assert_true(entered, "phase 2 at 50 %")
	hb.target_id = p.entity.entity_id
	var up := await TestWait.until(self, func() -> bool: return hb.hazards.size() == 2, 140)
	assert_true(up, "two stones announced")
	var struck := await TestWait.until(self, func() -> bool: return h.hazard_pulses >= 2, 110)
	assert_true(struck, "they strike 1.6 s later")
	var next := await TestWait.until(self, func() -> bool: return hb.hazard_log.size() >= 4, 260)
	assert_true(next, "and the next two come")
