extends IntegrationSuite
## The Ogre King (plan §3.12 design 2, decision 27, §4.4): data and scene; every attack telegraphed
## behind a long windup; phases exactly once [§15]; the phase-1 alternation and the phase-2 charge
## every third decision (the sequence brain, as a pure object); the two-hit combo chain; the §4.4
## damage table on a stage-2 giant; the slam and the charge through a block, the combo blocked and
## parried (and Titan Surge's +25 % poise on that parry: the M2-gate follow-up); the charge's 1.4 s
## recovery when it meets no wall; poise x3.5 in its recoveries.

const KING := "res://scenes/enemies/ogre_king.tscn"
const COMBO_1 := "ability.boss_combo_1"
const COMBO_2 := "ability.boss_combo_2"
const SLAM := "ability.boss_slam"
const CHARGE := "ability.boss_charge"
const WALL := "ability.boss_wall_recover"
const ROAR := "ability.boss_phase_roar"
const S := EnemyBrain.AIState
const CS := CombatController.State

var phase_events: Array = []


func before_each() -> void:
	await super()
	phase_events.clear()
	Events.boss_phase_changed.connect(_on_phase_changed)


func after_each() -> void:
	if Events.boss_phase_changed.is_connected(_on_phase_changed):
		Events.boss_phase_changed.disconnect(_on_phase_changed)
	await super()


func _on_phase_changed(tick: int, boss_id: String, phase: int) -> void:
	phase_events.append([tick, boss_id, phase])


func _king(pos: Vector3, id := "test.king", ai := false, yaw := 0.0) -> OgreBoss:
	return TestSpawn.enemy(world, KING, pos, id, ai, yaw) as OgreBoss


func _profile(stage: int) -> Dictionary:
	for rec: Dictionary in GameData.records_of_type("growth_profile"):
		if int(rec.get("stage", 0)) == stage:
			return rec
	return {}


func _giant(stage := 1, pos := Vector3(0, 0.05, 0), yaw := 0.0) -> GiantPlayer:
	var p := spawn_player(pos, yaw)
	if stage != 1:
		p.set_profile(_profile(stage))
	await TestWait.until(self, func() -> bool: return p.is_on_floor(), 40)
	await step_ticks(1)
	return p


## A synthetic hit of `amount` health damage on the king (armor 30; an attacker of 1.8 m, no crit).
func _damage(target: CombatEntity, amount: float, poise := 0.0, height := 1.8) -> void:
	var e := HitEvent.new()
	e.tick = Sim.tick
	e.instance_id = Sim.new_instance_id()
	e.attacker_id = "test.hitter"
	e.target_id = target.entity_id
	var armor := target.combatant.armor_total()
	e.power = amount * (100.0 + armor) / 100.0 / 1.15
	e.attacker_stat = 10.0
	e.attacker_height_m = height
	e.damage_split = {"physical": 1.0}
	e.poise_damage = poise
	e.tags = PackedStringArray(["Melee"])
	e.attacker_position = target.actor.global_position + Vector3(0, 0, -3)
	Sim.queue_hit(e)


func _hits_by(action_id: String, target_id := "player") -> Array[HitResult]:
	var out: Array[HitResult] = []
	for r in hits:
		if r.event.action_id == action_id and r.event.target_id == target_id:
			out.append(r)
	return out


func _started_count(actor_id: String, action_id: String) -> int:
	return started.count("%s:%s" % [actor_id, action_id])


# --------------------------------------------------------------------------- data and scene

func test_boss_data_and_scene() -> void:
	var rec: Dictionary = GameData.get_record("enemy.ogre_king")
	assert_eq(str(rec.archetype), "boss", "archetype boss")
	assert_near(float(rec.height_m), 8.5, 1e-6, "8.5 m tall")
	assert_near(float(rec.capsule_radius_m), 2.0, 1e-6, "radius 2.0")
	assert_near(float(rec.health), 1500.0, 1e-6, "1,500 health")
	assert_near(float(rec.armor), 30.0, 1e-6, "armor 30")
	assert_near(float(rec.poise.threshold), 150.0, 1e-6, "poise 150")
	assert_near(float(rec.poise.recovery_mult), 3.5, 1e-6, "x3.5 in its recoveries")
	assert_eq(int(rec.nav_layers), 4, "giant nav layer")
	assert_near(float(rec.threat), 1.0, 1e-6, "threat 1.0")
	assert_true(bool(rec.grants_fury), "grants fury")
	assert_eq(int(rec.xp_reward), 300, "300 XP")
	assert_eq(str(rec.loot_table), "loot.ogre_king", "P12's loot table")
	assert_true((rec.immunities as Array).has("Grab"), "immune to Grab")
	assert_eq(str(rec.grab_attach), "none", "no attachment profile")
	assert_true((rec.status_immunities as Array).has("Fear"), "immune to Fear")
	assert_true(bool(rec.ignores_morale), "ignores morale")
	var phases: Array = rec.boss.phases
	assert_eq(phases.size(), 2, "two phases")
	assert_eq(Array(phases[0].sequence), [COMBO_1, SLAM], "phase 1 alternates combo and slam")
	assert_eq(Array(phases[1].sequence), [COMBO_1, SLAM, CHARGE], "phase 2 adds the charge")
	assert_near(float(phases[1].health_frac_below), 0.5, 1e-6, "phase 2 at 50 %")
	assert_eq(str(phases[1].enter_action), ROAR, "entered with the roar")
	assert_eq(str(GameData.get_action(COMBO_1).chain_next), COMBO_2, "the combo chains")
	var k := _king(Vector3(0, 0.05, -10))
	await step_ticks(2)
	assert_true(k is OgreBoss and k.brain is OgreBossBrain, "OgreBoss with an OgreBossBrain")
	assert_true(k.is_in_group("bosses"), "group bosses")
	assert_eq(k.agent.navigation_layers, 4, "agent on the giant layer")
	assert_near(k.entity.combatant.height_m, 8.5, 1e-6, "combatant height")
	for n: String in ["Anchors/Torso", "Anchors/KneeL", "Anchors/KneeR", "Visual/Body", "Visual/LodProxy",
			"Hurtboxes/Head", "Hurtboxes/Torso", "Hurtboxes/Legs", "NavAgent", "BodyShape"]:
		assert_true(k.has_node(n), "the king has %s" % n)
	assert_false(k.has_node("Anchors/Grab"), "and no grab anchor")
	assert_false(k.can_be_grabbed(), "never grabbable")
	for id: String in [COMBO_1, COMBO_2, SLAM, CHARGE, ROAR]:
		assert_true(k.controller.library.has(id), "%s is in its library" % id)
	assert_eq(k.boss_phase(), 1, "starts in phase 1")
	assert_eq(k.phase_count(), 2, "of two")
	assert_eq(DataValidator.validate_record(rec, "test").errors.size(), 0, "the record validates")


func test_boss_schema_rejects_bad_phases() -> void:
	var rec: Dictionary = (GameData.get_record("enemy.ogre_king") as Dictionary).duplicate(true)
	(rec.boss.phases as Array).reverse()
	var errs: PackedStringArray = DataValidator.validate_record(rec, "test").errors
	assert_true(Array(errs).any(func(e: String) -> bool: return e.contains("descending health_frac_below")),
		"phases must be sorted by descending health_frac_below")
	rec = (GameData.get_record("enemy.ogre_king") as Dictionary).duplicate(true)
	rec.boss.phases[0]["sequence"] = [COMBO_1, CHARGE]
	errs = DataValidator.validate_record(rec, "test").errors
	assert_true(Array(errs).any(func(e: String) -> bool: return e.contains("is not one of the phase's attacks")),
		"a sequence entry must be one of the phase's attacks")
	rec = (GameData.get_record("enemy.ogre_king") as Dictionary).duplicate(true)
	rec.boss.phases[0]["attack_weights"] = [1.0]
	errs = DataValidator.validate_record(rec, "test").errors
	assert_true(Array(errs).any(func(e: String) -> bool: return e.contains("one entry per attack")),
		"weights match their attacks")
	rec = (GameData.get_record("enemy.ogre_king") as Dictionary).duplicate(true)
	rec.boss.phases[1]["id"] = "phase_1"
	errs = DataValidator.validate_record(rec, "test").errors
	assert_true(Array(errs).any(func(e: String) -> bool: return e.contains("duplicate phase id")), "unique phase ids")
	rec = (GameData.get_record("enemy.ogre_king") as Dictionary).duplicate(true)
	rec.boss["phases"] = []
	errs = DataValidator.validate_record(rec, "test").errors
	assert_true(Array(errs).any(func(e: String) -> bool: return e.contains("at least one phase")), "at least one phase")


func test_every_boss_and_ogre_attack_is_telegraphed_behind_a_long_windup() -> void:
	var used := {}
	for enemy_id: String in ["enemy.ogre", "enemy.ogre_king"]:
		var rec: Dictionary = GameData.get_record(enemy_id)
		for id: Variant in rec.attacks:
			used[str(id)] = enemy_id
		var boss: Variant = rec.get("boss")
		if typeof(boss) == TYPE_DICTIONARY:
			for p: Dictionary in boss.phases:
				for id: Variant in p.attacks:
					used[str(id)] = enemy_id
				if str(p.get("enter_action", "")) != "":
					used[str(p.enter_action)] = enemy_id
	assert_eq(used.size(), 7, "the ogre's two strikes, the king's four attacks and its roar")
	for id: String in used:
		var a := GameData.get_action(id)
		assert_true(a.windup_ticks >= ActionDef.seconds_to_ticks(0.8), "%s winds up for at least 0.8 s" % id)
		assert_true(typeof(a.param("telegraph")) == TYPE_DICTIONARY, "%s has a telegraph" % id)
	# The wall recovery is forced, hits nothing and is the punish window.
	var wall := GameData.get_action(WALL)
	assert_eq(wall.hit_shape, "none", "the wall recovery has no hit")
	assert_near(float(wall.windup_ticks + wall.active_ticks + wall.recovery_ticks) / 60.0, 2.5, 1e-6, "2.5 s")
	assert_eq(str(GameData.get_action(CHARGE).param("motion").on_wall_action), WALL, "a wall forces it")
	assert_near(float(GameData.get_action(CHARGE).recovery_ticks) / 60.0, 1.4, 1e-6, "1.4 s without a wall")
	assert_near(float(GameData.get_action(CHARGE).active_ticks) / 60.0, 6.0, 1e-6, "a charge runs at most 6 s")
	assert_eq(str(GameData.get_action(SLAM).param("telegraph").shape), "circle", "slam: circle")
	assert_near(float(GameData.get_action(SLAM).param("telegraph").radius_m), 5.0, 1e-6, "r 5")
	assert_near(float(GameData.get_action(SLAM).windup_ticks) / 60.0, 1.3, 1e-6, "1.3 s windup")
	assert_eq(str(GameData.get_action(CHARGE).param("telegraph").shape), "line", "charge: line")
	assert_eq(str(GameData.get_action(COMBO_1).param("telegraph").shape), "cone", "combo: cone")
	assert_eq(str(GameData.get_action(ROAR).param("telegraph").shape), "circle", "roar: circle")
	assert_near(float(GameData.get_action(ROAR).windup_ticks + GameData.get_action(ROAR).active_ticks
		+ GameData.get_action(ROAR).recovery_ticks) / 60.0, 1.5, 1e-6, "a 1.5 s roar")
	for id: String in [SLAM, CHARGE]:
		assert_true(GameData.get_action(id).has_tag("Unblockable") and GameData.get_action(id).has_tag("Unparryable"),
			"%s is unblockable and unparryable" % id)
	for id: String in [COMBO_1, COMBO_2]:
		var a := GameData.get_action(id)
		assert_true(a.has_tag("Parryable") and not a.has_tag("Unblockable") and not a.has_tag("Unparryable"),
			"%s can be blocked and parried" % id)
	assert_eq(GameData.call("_untelegraphed_enemy_attacks"), PackedStringArray(), "the post-pass agrees")


# --------------------------------------------------------------------------- phases [§15]

func test_phases_happen_exactly_once() -> void:
	var k := _king(Vector3(0, 0.05, -12))
	await step_ticks(2)
	var hp := k.entity.combatant.pools
	_damage(k.entity, hp.health_max * 0.51)   # 1500 -> 735 (49 %)
	await step_ticks(3)
	assert_near(hp.health / hp.health_max, 0.49, 0.002, "damaged to 49 %")
	assert_eq(phase_events.size(), 1, "phase 2 announced")
	if phase_events.size() == 1:
		assert_eq(phase_events[0][1], "test.king", "by the king")
		assert_eq(int(phase_events[0][2]), 2, "phase 2")
	assert_eq(k.controller.action_id(), ROAR, "the roar is forced at once")
	assert_eq(_started_count("test.king", ROAR), 1, "one roar")
	assert_true((k.brain as OgreBossBrain).phase2_entered, "phase2_entered")
	assert_eq(k.boss_phase(), 2, "phase 2")
	assert_eq(k.brain.current_sequence_entry(), COMBO_1, "the phase-2 sequence starts over")
	# The roar runs its 1.5 s under super armour: a poise break does not stop it.
	_damage(k.entity, 1.0, 1000.0, 8.0)
	await step_ticks(2)
	assert_eq(k.controller.action_id(), ROAR, "super armour keeps the roar")
	await TestWait.until(self, func() -> bool: return k.controller.action == null, 120)
	k.entity.heal(hp.health_max * 0.8 - hp.health, "test")
	await step_ticks(3)
	assert_near(hp.health / hp.health_max, 0.8, 0.002, "healed to 80 %")
	assert_eq(k.boss_phase(), 2, "never back to phase 1")
	_damage(k.entity, hp.health - hp.health_max * 0.3)
	await step_ticks(3)
	assert_near(hp.health / hp.health_max, 0.3, 0.002, "damaged to 30 %")
	await step_ticks(60)
	assert_eq(phase_events.size(), 1, "one boss_phase_changed in all")
	assert_eq(_started_count("test.king", ROAR), 1, "one roar in all")
	assert_eq(k.phase_changes, 1, "the actor announced one phase")


# --------------------------------------------------------------------------- the sequence brain

## A snapshot of the giant `edge` metres from the king's centre's reach (from its capsule surface),
## straight ahead.
func _snap(edge: float, radius := 1.2, facing_deg := 0.0) -> Dictionary:
	var d := edge + radius
	return {"exists": true, "target_id": "player", "alive": true, "position": Vector3(0, 0, -d),
		"distance": d, "visible": true, "facing_deg": facing_deg, "target_radius": radius,
		"target_forward": Vector3.BACK, "target_height": 5.49, "target_stage": 2,
		"target_state": CS.LOCOMOTION, "self_health_frac": 1.0, "has_leader": false}


## Drives a pure OgreBossBrain through `count` decisions with a cooperative target (it stands in
## the band of whatever entry is current) and a controller that runs each requested attack for
## 30 ticks. Returns the requested ids in order.
func _decisions(b: OgreBossBrain, count: int, start_tick: int) -> Array[String]:
	var out: Array[String] = []
	var t := start_tick
	var running := 0
	var guard := 0
	while out.size() < count and guard < 4000:
		guard += 1
		var entry := b.current_sequence_entry()
		var band := b.sequence_band(entry)
		var edge := (band.x + minf(band.y, band.x + 6.0)) * 0.5
		b.perceive(t, _snap(edge))
		var cs := CS.ATTACKING if running > 0 else CS.LOCOMOTION
		b.decide(t, cs, Vector3.ZERO, func() -> bool: return true, func() -> void: pass)
		if b.attack_request != "":
			out.append(b.attack_request)
			b.attack_request = ""
			running = 30
		running = maxi(0, running - 6)
		t += 6
	return out


func test_phase_1_alternates_and_phase_2_charges_every_third_decision() -> void:
	var b := OgreBossBrain.new("test.king_brain", GameData.get_record("enemy.ogre_king"), 77)
	b.perceive(10, _snap(2.0))
	b.decide(10, CS.LOCOMOTION, Vector3.ZERO, func() -> bool: return true, func() -> void: pass)
	b.decide(60, CS.LOCOMOTION, Vector3.ZERO, func() -> bool: return true, func() -> void: pass)
	var p1 := _decisions(b, 20, 66)
	assert_eq(p1.size(), 20, "20 phase-1 decisions")
	for i in range(1, p1.size()):
		assert_true(p1[i] != p1[i - 1], "phase 1 never repeats an attack (decision %d: %s)" % [i, p1[i]])
	assert_eq(p1.count(COMBO_1), 10, "ten combos")
	assert_eq(p1.count(SLAM), 10, "and ten slams")
	assert_false(p1.has(CHARGE), "no charge in phase 1")
	assert_eq(b.update_boss_phase(0.45, 2000), 2, "phase 2 at 45 %")
	assert_eq(b.update_boss_phase(0.45, 2001), 0, "entered once")
	assert_eq(b.state, S.ATTACK, "waits for the roar")
	var p2 := _decisions(b, 21, 2006)
	assert_eq(p2.size(), 21, "21 phase-2 decisions")
	for i in range(0, p2.size() - 2):
		assert_true(p2.slice(i, i + 3).has(CHARGE), "a charge within decisions %d..%d" % [i, i + 2])
	assert_eq(p2.count(CHARGE), 7, "seven charges")
	assert_true(b.phase2_entered, "phase 2 entered")
	assert_eq(b.update_boss_phase(0.9, 3000), 0, "healed: no phase change")
	assert_eq(b.boss_phase(), 2, "and no way back to phase 1")


func test_an_entry_out_of_reach_is_chased_then_skipped() -> void:
	var b := OgreBossBrain.new("test.king_brain2", GameData.get_record("enemy.ogre_king"), 5)
	b.perceive(10, _snap(25.0))
	b.decide(10, CS.LOCOMOTION, Vector3.ZERO, func() -> bool: return true, func() -> void: pass)
	b.decide(60, CS.LOCOMOTION, Vector3.ZERO, func() -> bool: return true, func() -> void: pass)
	assert_eq(b.state, S.APPROACH, "engaged")
	# Walking up to a giant 25 m away skips nothing, however long it takes.
	for t in range(66, 66 + 6 * 40, 6):
		b.perceive(t, _snap(25.0))
		b.decide(t, CS.LOCOMOTION, Vector3.ZERO, func() -> bool: return true, func() -> void: pass)
	assert_true(b.move_target != Vector3.INF and b.move_target.z < 0.0, "it closes in")
	assert_eq(b.current_sequence_entry(), COMBO_1, "4 s on the way in and the combo is still next")
	assert_true(b.sequence_log.is_empty(), "nothing skipped")
	b.perceive(306, _snap(4.5))
	b.decide(306, CS.LOCOMOTION, Vector3.ZERO, func() -> bool: return true, func() -> void: pass)
	assert_eq(b.attack_request, COMBO_1, "the combo reaches 4.5 m")
	b.attack_request = ""
	b.decide(312, CS.ATTACKING, Vector3.ZERO, func() -> bool: return true, func() -> void: pass)
	b.decide(348, CS.LOCOMOTION, Vector3.ZERO, func() -> bool: return true, func() -> void: pass)
	assert_eq(b.state, S.RECOVER, "a pause after the strike")
	# The slam (band 0..3.5 m) is next; the giant stays 4.5 m away.
	var t := 390
	var chased := false
	while t < 390 + 6 * 30 and b.current_sequence_entry() == SLAM:
		b.perceive(t, _snap(4.5))
		b.decide(t, CS.LOCOMOTION, Vector3.ZERO, func() -> bool: return true, func() -> void: pass)
		if b.move_target != Vector3.INF and b.move_target.z < 0.0:
			chased = true
		assert_eq(b.attack_request, "", "no slam out of its band (tick %d)" % t)
		t += 6
	assert_true(chased, "it closes in on the giant")
	assert_eq(b.current_sequence_entry(), COMBO_1, "then the slam is skipped")
	assert_true(t - 390 >= 120 and t - 390 <= 150, "after about 2 s (%d ticks)" % (t - 390))
	assert_eq(b.sequence_log.back(), "skip:" + SLAM, "logged as a skip")
	# The charge (8 m and more) backs off from a giant too close.
	b.update_boss_phase(0.4, 700)
	b.sequence_index = 2
	b.state = S.APPROACH
	b.perceive(710, _snap(3.0))
	b.decide(710, CS.LOCOMOTION, Vector3.ZERO, func() -> bool: return true, func() -> void: pass)
	assert_eq(b.current_sequence_entry(), CHARGE, "the charge is current")
	assert_true(b.move_target != Vector3.INF and b.move_target.z > 0.0, "it backs away from the giant")
	b.perceive(716, _snap(9.0))
	b.decide(716, CS.LOCOMOTION, Vector3.ZERO, func() -> bool: return true, func() -> void: pass)
	assert_eq(b.attack_request, CHARGE, "and charges from 9 m")


# --------------------------------------------------------------------------- combo, damage, block

func test_the_combo_chains_into_its_second_blow() -> void:
	var p := await _giant(2, Vector3(0, 0.05, 0))
	var k := _king(Vector3(0, 0.05, -6.5), "test.king_combo", false, PI)
	await step_ticks(2)
	k.controller.request(&"attack", {"action_id": COMBO_1})
	var gap := false
	var saw_second := false
	for i in 260:
		await step_ticks(1)
		if k.controller.action_id() == COMBO_2:
			saw_second = true
		elif saw_second and k.controller.action == null:
			break
		elif not saw_second and k.controller.action == null:
			gap = true
	assert_true(saw_second, "the second blow followed")
	assert_false(gap, "with no idle tick between the blows")
	assert_eq(_started_count("test.king_combo", COMBO_2), 1, "once")
	var first := _hits_by(COMBO_1)
	var second := _hits_by(COMBO_2)
	assert_eq(first.size(), 1, "the first blow hit the stage-2 giant")
	assert_eq(second.size(), 1, "and the second")
	if first.size() == 1 and second.size() == 1:
		assert_eq(first[0].health_damage, 76, "combo 1: 76 (plan §4.4)")
		assert_eq(second[0].health_damage, 92, "combo 2: 92 (plan §4.4)")
	assert_true(p.entity.is_alive(), "the giant lives")


func test_the_slam_deals_126_to_a_stage_2_giant() -> void:
	var p := await _giant(2, Vector3(0, 0.05, 0))
	assert_near(p.entity.combatant.armor_total(), 0.0, 1e-6, "armor 0")
	# The king faces away (yaw 0, -Z): the giant stands behind it, and the slam hits all round.
	var k := _king(Vector3(0, 0.05, -5.0), "test.king_slam")
	await step_ticks(2)
	k.controller.request(&"attack", {"action_id": SLAM})
	await step_ticks(GameData.get_action(SLAM).windup_ticks + 4)
	var on := _hits_by(SLAM)
	assert_eq(on.size(), 1, "the slam hit the giant behind the king, once")
	if on.size() == 1:
		assert_eq(on[0].outcome, HitResult.Outcome.HIT, "a hit")
		assert_near(float(on[0].health_damage), 126.0, 1.0, "126 +/- 1 (plan §4.4)")


func test_the_slam_ignores_a_block_and_the_combo_is_blocked() -> void:
	var p := await _giant(2, Vector3(0, 0.05, 0))
	p.router.set_injected_hold(&"block", true)
	p.router.inject_edge(&"block_press")
	await step_ticks(15)
	assert_eq(p.controller.state, CS.BLOCKING, "the giant blocks")
	var k := _king(Vector3(0, 0.05, -5.0), "test.king_block", false, PI)
	k.facing_yaw = PI
	await step_ticks(2)
	k.controller.request(&"attack", {"action_id": SLAM})
	await step_ticks(GameData.get_action(SLAM).windup_ticks + 4)
	var slam := _hits_by(SLAM)
	assert_eq(slam.size(), 1, "the slam lands")
	if slam.size() == 1:
		assert_eq(slam[0].outcome, HitResult.Outcome.HIT, "through the block")
		assert_near(float(slam[0].health_damage), 126.0, 1.0, "at full damage")
	await TestWait.until(self, func() -> bool: return k.controller.action == null, 200)
	await step_ticks(10)
	p.global_position = Vector3(0, 0.05, 0)   # the slam knocked it back out of the combo's reach
	p.knockback_velocity = Vector3.ZERO
	p.router.set_injected_hold(&"block", true)
	p.router.inject_edge(&"block_press")
	await TestWait.until(self, func() -> bool: return p.controller.state == CS.BLOCKING, 60)
	await step_ticks(15)
	k.controller.request(&"attack", {"action_id": COMBO_1})
	await step_ticks(GameData.get_action(COMBO_1).windup_ticks + 4)
	var combo := _hits_by(COMBO_1)
	assert_eq(combo.size(), 1, "the combo lands")
	if combo.size() == 1:
		assert_eq(combo[0].outcome, HitResult.Outcome.BLOCKED, "the combo is blocked")
		assert_true(combo[0].health_damage < 76, "for less (%d)" % combo[0].health_damage)


func test_a_parry_staggers_through_poise_and_titan_surge_adds_to_it() -> void:
	# The combo can be parried; the parry's 40 poise counts x1.25 under Titan Surge (P11a, the M2
	# gate follow-up: the surge's poise bonus never reached the parry before).
	for surged: bool in [false, true]:
		var p := await _giant(2, Vector3(0, 0.05, 0))
		if surged:
			assert_true(p.entity.apply_status("status.titan_surge"), "Titan Surge on")
		var id := "test.king_parry_%s" % ("surge" if surged else "plain")
		var k := _king(Vector3(0, 0.05, -5.0), id, false, PI)
		k.facing_yaw = PI
		await step_ticks(2)
		k.controller.request(&"attack", {"action_id": COMBO_1})
		var windup := GameData.get_action(COMBO_1).windup_ticks
		await TestWait.until(self, func() -> bool: return k.controller.elapsed >= windup - 6, 80)
		p.router.set_injected_hold(&"block", true)
		p.router.inject_edge(&"block_press")
		await step_ticks(12)
		var parried: Array[HitResult] = []
		for r in hits:
			if r.event.attacker_id == id and r.outcome == HitResult.Outcome.PARRIED:
				parried.append(r)
		assert_eq(parried.size(), 1, "the combo is parried (%s)" % ("surge" if surged else "plain"))
		var expected := 40.0 * (1.25 if surged else 1.0)
		if parried.size() == 1:
			assert_near(parried[0].attacker_poise_damage, expected, 1e-4,
				"the parry deals %.0f poise to the king" % expected)
			assert_eq(parried[0].health_damage, 0, "and no damage")
		assert_near(k.entity.combatant.poise.value, expected, 1e-4, "the king's poise took %.0f" % expected)
		p.router.set_injected_hold(&"block", false)
		p.router.inject_edge(&"block_release")
		k.queue_free()
		p.queue_free()
		await step_ticks(3)
		hits.clear()


func test_poise_counts_x3_5_in_the_kings_recovery() -> void:
	var k := _king(Vector3(0, 0.05, -12), "test.king_poise")
	await step_ticks(2)
	# A stage-2 heavy: 35 poise x (5.49 / 8.5) = 22.6, x3.5 in a recovery = 79 (plan §4.4).
	_damage(k.entity, 1.0, 35.0, 5.4864)
	await step_ticks(1)
	assert_near(k.entity.combatant.poise.value, 22.6, 0.1, "a heavy outside any recovery: 23")
	k.entity.combatant.poise.value = 0.0
	k.controller.force_action(GameData.get_action(WALL))
	await step_ticks(10)
	assert_eq(k.controller.phase(), ActionDef.Phase.RECOVERY, "the wall recovery")
	_damage(k.entity, 1.0, 35.0, 5.4864)
	await step_ticks(1)
	assert_near(k.entity.combatant.poise.value, 79.1, 0.2, "the same heavy in it: 79")
	_damage(k.entity, 1.0, 35.0, 5.4864)
	await step_ticks(1)
	assert_eq(k.controller.state, CS.STAGGERED, "two heavies in the 2.5 s wall recovery stagger the king")


# --------------------------------------------------------------------------- the charge

func test_a_charge_without_a_wall_ends_on_its_cap_with_the_short_recovery() -> void:
	add_box(Vector3(300, 1, 300), Vector3(0, -0.5, 0))
	var k := _king(Vector3(0, 0.05, 110), "test.king_open", false, 0.0)
	await step_ticks(3)
	var start := k.global_position
	k.brain.face_point = Vector3(0, 0, -100)
	k.controller.request(&"attack", {"action_id": CHARGE})
	var charge := GameData.get_action(CHARGE)
	await step_ticks(charge.windup_ticks - 2)
	assert_true(Vector2(k.global_position.x - start.x, k.global_position.z - start.z).length() < 0.1,
		"no run during the windup")
	var ended: bool = await TestWait.until(self, func() -> bool: return k.motion_end_reason != "", charge.active_ticks + 10)
	assert_true(ended, "the run ended")
	assert_eq(k.motion_end_reason, "phase", "on its 6 s cap")
	var ran := start.z - k.global_position.z
	assert_true(ran > 85.0 and ran < 92.0, "15 m/s for 6 s (%.1f m)" % ran)
	assert_eq(k.controller.action_id(), CHARGE, "in the charge's own recovery")
	assert_eq(k.controller.phase(), ActionDef.Phase.RECOVERY, "recovering")
	var left := 0
	while k.controller.action_id() == CHARGE and left < 200:
		await step_ticks(1)
		left += 1
	assert_true(absi(left - charge.recovery_ticks) <= 2, "a 1.4 s recovery (%d ticks)" % left)
	assert_eq(_started_count("test.king_open", WALL), 0, "no wall recovery")
	assert_eq(k.cap_stops, 1, "counted as a cap stop")
	assert_eq(k.wall_stops, 0, "not a wall stop")
	assert_eq(k.collision_mask, SceneKit.ACTOR_MASK, "it collides with actors again after the run")


func test_a_charge_hits_the_giant_once_through_its_block_and_shoves_it_aside() -> void:
	add_box(Vector3(200, 1, 200), Vector3(0, -0.5, 0))
	var p := await _giant(2, Vector3(0.6, 0.05, 0))
	p.router.set_injected_hold(&"block", true)
	p.router.inject_edge(&"block_press")
	var k := _king(Vector3(0, 0.05, -20), "test.king_run", false, PI)
	k.facing_yaw = PI
	await step_ticks(3)
	k.brain.target_id = "player"
	k.brain.face_point = p.global_position
	k.controller.request(&"attack", {"action_id": CHARGE})
	var passed: bool = await TestWait.until(self, func() -> bool: return k.global_position.z > 12.0, 240)
	assert_true(passed, "the king ran through where the giant stood")
	var on := _hits_by(CHARGE)
	assert_eq(on.size(), 1, "one hit per charge")
	if on.size() == 1:
		assert_eq(on[0].outcome, HitResult.Outcome.HIT, "unblockable")
		assert_near(float(on[0].health_damage), 101.0, 1.0, "101 (plan §4.4)")
	assert_true(absf(p.global_position.x - k.global_position.x) > 1.0,
		"the giant is shoved aside, off the charge line (%.2f m)" % absf(p.global_position.x - k.global_position.x))
