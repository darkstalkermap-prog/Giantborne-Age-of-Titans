extends IntegrationSuite
## The ogre (plan §3.12 design 1, §4.4; the fifth role): data and scene; its strikes keep going
## through light blows and even a broken poise (super armour) but not through its recovery, where
## poise counts x3.5 - one stage-1 heavy staggers it there (35 x 1.08 x 3.5 = 132 >= 120) and not
## outside it; its strikes match their telegraphs (the smash all round, the sweep in front); the
## brain smashes a target beside it; and a stage-3 giant grabs a staggered ogre and throws it.

const OGRE := "res://scenes/enemies/ogre.tscn"
const SMASH := "ability.ogre_smash"
const SWEEP := "ability.ogre_sweep"
const CS := CombatController.State


func _ogre(pos: Vector3, id: String, yaw := 0.0, ai := false) -> OgreEnemy:
	return TestSpawn.enemy(world, OGRE, pos, id, ai, yaw) as OgreEnemy


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


func _hits(attacker_id: String, target_id: String, action_id := "") -> Array[HitResult]:
	var out: Array[HitResult] = []
	for r in hits:
		if r.event.attacker_id == attacker_id and r.event.target_id == target_id \
				and (action_id == "" or r.event.action_id == action_id):
			out.append(r)
	return out


## A hit with this much poise from an attacker of `height` m (no damage worth mentioning).
func _poise_hit(target: CombatEntity, poise: float, height: float, attacker_id := "test.hitter") -> void:
	var e := HitEvent.new()
	e.tick = Sim.tick
	e.instance_id = Sim.new_instance_id()
	e.attacker_id = attacker_id
	e.target_id = target.entity_id
	e.power = 1.0
	e.attacker_stat = 10.0
	e.attacker_height_m = height
	e.damage_split = {"physical": 1.0}
	e.poise_damage = poise
	e.tags = PackedStringArray(["Melee"])
	e.attacker_position = target.actor.global_position + Vector3(0, 0, -2)
	Sim.queue_hit(e)


func _staggered_count(id: String) -> int:
	return staggers.count(id)


var staggers: Array[String] = []


func before_each() -> void:
	await super()
	staggers.clear()
	Events.staggered.connect(_on_staggered)


func after_each() -> void:
	if Events.staggered.is_connected(_on_staggered):
		Events.staggered.disconnect(_on_staggered)
	await super()


func _on_staggered(_tick: int, entity_id: String, _seconds: float, _reason: String) -> void:
	staggers.append(entity_id)


# --------------------------------------------------------------------------- data and scene

func test_ogre_data_and_scene() -> void:
	var rec: Dictionary = GameData.get_record("enemy.ogre")
	assert_eq(str(rec.archetype), "ogre", "archetype ogre")
	assert_near(float(rec.height_m), 3.4, 1e-6, "3.4 m")
	assert_near(float(rec.capsule_radius_m), 0.9, 1e-6, "radius 0.9")
	assert_near(float(rec.health), 600.0, 1e-6, "600 health")
	assert_near(float(rec.armor), 20.0, 1e-6, "armor 20")
	assert_near(float(rec.poise.threshold), 120.0, 1e-6, "poise 120")
	assert_near(float(rec.poise.recovery_mult), 3.5, 1e-6, "x3.5 during its recovery")
	assert_near(float(rec.turn_rate_deg_s), 90.0, 1e-6, "turns 90 degrees/s")
	assert_near(float(rec.walk_speed_mps), 2.2, 1e-6, "walks 2.2 m/s")
	assert_near(float(rec.run_speed_mps), 4.5, 1e-6, "runs 4.5 m/s")
	assert_eq(int(rec.nav_layers), 2, "large nav layer")
	assert_eq(str(rec.mass_class), "medium", "mass medium")
	assert_eq(str(rec.grab_attach), "two_hand", "two_hand")
	assert_near(float(rec.threat), 0.9, 1e-6, "threat 0.9")
	assert_true(bool(rec.grants_fury), "grants fury")
	assert_eq(int(rec.xp_reward), 60, "60 XP")
	assert_true(bool(rec.ignores_morale) and (rec.status_immunities as Array).has("Fear"), "ignores fear")
	for id: String in [SMASH, SWEEP]:
		var a := GameData.get_action(id)
		assert_eq(a.interrupt_policy, "super_armor", "%s has super armour" % id)
		assert_true(a.windup_ticks >= ActionDef.seconds_to_ticks(0.9), "%s winds up >= 0.9 s" % id)
		assert_true(a.recovery_ticks >= ActionDef.seconds_to_ticks(1.1), "%s recovers >= 1.1 s (the punish window)" % id)
		assert_true(typeof(a.param("telegraph")) == TYPE_DICTIONARY, "%s is telegraphed" % id)
	var smash := GameData.get_action(SMASH)
	assert_near(float(smash.windup_ticks + 0) / 60.0, 1.0, 1e-6, "smash 1.0 s windup")
	assert_near(float(smash.recovery_ticks) / 60.0, 1.2, 1e-6, "smash 1.2 s recovery")
	assert_eq(str(smash.param("telegraph").shape), "circle", "smash: circle")
	assert_near(float(smash.param("telegraph").radius_m), 3.5, 1e-6, "r 3.5")
	assert_near(smash.radius_m, 3.5, 1e-6, "its pulse matches the telegraph")
	var sweep := GameData.get_action(SWEEP)
	assert_eq(str(sweep.param("telegraph").shape), "cone", "sweep: cone")
	assert_near(float(sweep.param("telegraph").arc_deg), 120.0, 1e-6, "120 degrees")
	assert_near(float(sweep.param("sector_deg")), 120.0, 1e-6, "its sector matches the telegraph")
	var o := _ogre(Vector3(0, 0.05, -8), "test.ogre_scene")
	await step_ticks(2)
	assert_true(o is OgreEnemy and o.brain is OgreBrain, "OgreEnemy with an OgreBrain")
	assert_eq(o.agent.navigation_layers, 2, "agent on the large layer")
	assert_eq(o.collision_mask, SceneKit.ACTOR_MASK, "the actor mask")
	for n: String in ["Anchors/Torso", "Anchors/KneeL", "Anchors/KneeR", "Anchors/Grab", "Visual/Body",
			"Visual/LodProxy", "Hurtboxes/Head", "Hurtboxes/Torso", "Hurtboxes/Legs", "NavAgent", "BodyShape"]:
		assert_true(o.has_node(n), "the ogre has %s" % n)
	assert_eq(o.grab_attach(), "two_hand", "held with both hands")
	assert_true(o.can_be_grabbed(), "grabbable by the actor's own rules")
	assert_near(o.entity.combatant.poise.recovery_mult, 3.5, 1e-6, "the poise meter's recovery_mult")
	assert_true(o.get_rig_state().has("armored"), "the rig state says when it is armoured")


# --------------------------------------------------------------------------- super armour and the punish

func test_super_armor_keeps_the_strike_through_light_hits() -> void:
	var p := await _giant(1, Vector3(0, 0.05, 0), 0.0)
	var o := _ogre(Vector3(0, 0.05, -3.2), "test.ogre_armor", PI)
	await step_ticks(2)
	o.controller.request(&"attack", {"action_id": SMASH})
	var instance := o.controller.instance_id
	await step_ticks(2)
	p.router.inject_light_attack()
	await step_ticks(22)
	p.router.inject_light_attack()
	await step_ticks(20)
	var lights := _hits("player", "test.ogre_armor")
	assert_true(lights.size() >= 2, "light blows land during the windup (%d)" % lights.size())
	assert_eq(o.controller.state, CS.ATTACKING, "still striking")
	assert_eq(o.controller.phase(), ActionDef.Phase.WINDUP, "in its windup")
	# Even a broken poise does not stop it: the meter resets and the strike goes on.
	_poise_hit(o.entity, 500.0, 3.6576)
	await step_ticks(1)
	assert_eq(o.controller.state, CS.ATTACKING, "a poise break during the windup does not stagger it")
	assert_eq(o.controller.instance_id, instance, "the same strike")
	assert_near(o.entity.combatant.poise.value, 0.0, 1e-6, "the poise meter reset")
	assert_eq(_staggered_count("test.ogre_armor"), 0, "no stagger")
	await step_ticks(o.controller.action.windup_ticks - o.controller.elapsed + 3)
	assert_eq(_hits("test.ogre_armor", "player", SMASH).size(), 1, "the smash lands on the giant")
	assert_eq(o.controller.instance_id, instance, "the same strike to the end")


func test_a_stage_1_heavy_staggers_it_in_its_recovery_and_not_outside() -> void:
	var p := await _giant(1, Vector3(0, 0.05, 0), 0.0)
	# Outside any recovery: the heavy's 35 x 1.08 = 38 poise does nothing to a poise of 120.
	var calm := _ogre(Vector3(0, 0.05, -3.0), "test.ogre_calm", 0.0)
	await step_ticks(2)
	p.router.inject_edge(&"heavy")
	await TestWait.until(self, func() -> bool: return _hits("player", "test.ogre_calm").size() > 0, 60)
	var first := _hits("player", "test.ogre_calm")
	assert_eq(first.size(), 1, "the heavy hits the idle ogre")
	if first.size() == 1:
		assert_near(first[0].poise_damage, 35.0 * 3.6576 / 3.4, 0.05, "38 poise")
		assert_false(first[0].poise_broken, "not broken")
	await step_ticks(2)
	assert_eq(calm.controller.state, CS.LOCOMOTION, "no stagger outside its recovery")
	calm.queue_free()
	await TestWait.until(self, func() -> bool: return p.controller.action == null, 90)
	await step_ticks(5)
	# In its recovery: x3.5 = 132 >= 120. The ogre sweeps away from the giant (it faces -Z).
	var o := _ogre(Vector3(0, 0.05, -3.0), "test.ogre_punish", 0.0)
	await step_ticks(2)
	o.controller.request(&"attack", {"action_id": SWEEP})
	await TestWait.until(self, func() -> bool: return o.controller.phase() == ActionDef.Phase.RECOVERY, 120)
	assert_eq(_hits("test.ogre_punish", "player").size(), 0, "the sweep missed the giant behind it")
	p.router.inject_edge(&"heavy")
	await TestWait.until(self, func() -> bool: return _hits("player", "test.ogre_punish").size() > 0, 60)
	var punish := _hits("player", "test.ogre_punish")
	assert_eq(punish.size(), 1, "the heavy lands in the recovery")
	if punish.size() == 1:
		assert_near(punish[0].poise_damage, 35.0 * 3.6576 / 3.4 * 3.5, 0.2, "132 poise (x3.5)")
		assert_true(punish[0].poise_broken, "breaks its poise")
	await step_ticks(1)
	assert_eq(o.controller.state, CS.STAGGERED, "a stage-1 heavy in the recovery staggers it")
	assert_eq(_staggered_count("test.ogre_punish"), 1, "one stagger")


func test_its_strikes_match_their_telegraphs() -> void:
	var p := await _giant(1, Vector3(0, 0.05, 0), 0.0)
	var got: Array = []
	var cb := func(_t: int, actor: String, action_id: String, _target: String, shape: String, _o: Vector3,
			_yaw: float, radius: float, length: float, _d: float) -> void:
		got.append([actor, action_id, shape, radius, length])
	Events.telegraph_started.connect(cb)
	# Behind the ogre (it faces -Z, away from the giant): the sweep misses, the smash hits all round.
	var o := _ogre(Vector3(0, 0.05, -3.2), "test.ogre_shapes", 0.0)
	await step_ticks(2)
	o.controller.request(&"attack", {"action_id": SWEEP})
	await TestWait.until(self, func() -> bool: return o.controller.action == null, 200)
	assert_eq(_hits("test.ogre_shapes", "player", SWEEP).size(), 0, "the sweep only hits in front")
	o.controller.request(&"attack", {"action_id": SMASH})
	await TestWait.until(self, func() -> bool: return o.controller.phase() == ActionDef.Phase.RECOVERY, 200)
	assert_eq(_hits("test.ogre_shapes", "player", SMASH).size(), 1, "the smash hits all round")
	Events.telegraph_started.disconnect(cb)
	assert_eq(got.size(), 2, "both announced")
	if got.size() == 2:
		assert_eq([got[0][1], got[0][2]], [SWEEP, "cone"], "the sweep: a cone")
		assert_near(float(got[0][3]), 4.0, 1e-6, "r 4")
		assert_eq([got[1][1], got[1][2]], [SMASH, "circle"], "the smash: a circle")
		assert_near(float(got[1][3]), 3.5, 1e-6, "r 3.5")
	assert_true(p.entity.is_alive(), "the giant lives")


func test_the_brain_smashes_a_target_beside_it() -> void:
	var b := OgreBrain.new("test.ogre_brain", GameData.get_record("enemy.ogre"), 3)
	var snap := {"exists": true, "target_id": "player", "alive": true, "position": Vector3(3, 0, 0),
		"distance": 3.0, "visible": true, "facing_deg": 90.0, "target_radius": 0.85,
		"target_forward": Vector3.FORWARD, "target_height": 3.66, "target_stage": 1,
		"target_state": CS.LOCOMOTION, "self_health_frac": 1.0, "has_leader": false}
	b.perceive(10, snap)
	b.decide(10, CS.LOCOMOTION, Vector3.ZERO, func() -> bool: return true, func() -> void: pass)
	b.decide(70, CS.LOCOMOTION, Vector3.ZERO, func() -> bool: return true, func() -> void: pass)
	b.decide(76, CS.LOCOMOTION, Vector3.ZERO, func() -> bool: return true, func() -> void: pass)
	assert_eq(b.attack_request, SMASH, "beside it, in reach: the smash (it needs no facing)")
	var front := snap.duplicate()
	front["facing_deg"] = 0.0
	var b2 := OgreBrain.new("test.ogre_brain2", GameData.get_record("enemy.ogre"), 3)
	b2.perceive(10, front)
	b2.decide(10, CS.LOCOMOTION, Vector3.ZERO, func() -> bool: return true, func() -> void: pass)
	b2.decide(70, CS.LOCOMOTION, Vector3.ZERO, func() -> bool: return true, func() -> void: pass)
	b2.decide(76, CS.LOCOMOTION, Vector3.ZERO, func() -> bool: return true, func() -> void: pass)
	assert_true(b2.attack_request in [SMASH, SWEEP], "in front: either strike (%s)" % b2.attack_request)
	assert_false(b2.ignores_morale == false, "ogres ignore morale")


# --------------------------------------------------------------------------- stage 3 grabs it

func test_stage_3_grabs_a_staggered_ogre_and_throws_it() -> void:
	var p := await _giant(3, Vector3(0, 0.05, 0), 0.0)
	var o := _ogre(Vector3(0, 0.05, -4.2), "test.ogre_grab", PI)
	await step_ticks(2)
	assert_eq(p.grab.check_target(o.entity), "not_staggered", "an ogre on its feet cannot be grabbed")
	# Two stage-3 heavies' worth of poise: 35 x 2.0 (clamped) twice = 140 >= 120.
	_poise_hit(o.entity, 35.0, 7.9248, "player")
	await step_ticks(1)
	assert_eq(o.controller.state, CS.LOCOMOTION, "one heavy is not enough")
	_poise_hit(o.entity, 35.0, 7.9248, "player")
	await step_ticks(1)
	assert_eq(o.controller.state, CS.STAGGERED, "two heavies stagger the ogre")
	assert_near(float(o.controller.stagger_ticks_left) / 60.0, 2.0, 0.05, "2 s against a giant twice its height")
	assert_eq(p.grab.check_target(o.entity), "", "a staggered ogre is grabbable at stage 3")
	assert_eq(p.grab.try_grab(), CombatController.Verdict.ACCEPT, "the grab is accepted")
	var held: bool = await TestWait.until(self, func() -> bool: return p.grab.is_holding(), 40)
	assert_true(held, "the stage-3 giant holds the ogre")
	assert_eq(p.grab.held_attach(), "two_hand", "with both hands")
	await TestWait.until(self, func() -> bool:
		return p.controller.state == CS.LOCOMOTION and p.controller.action == null, 90)
	p.camera_rig.pitch = deg_to_rad(-20.0)
	p.router.inject_light_attack()
	var thrown: bool = await TestWait.until(self, func() -> bool: return not p.grab.is_holding(), 40)
	assert_true(thrown, "and throws it")
	var landed: bool = await TestWait.until(self, func() -> bool: return not o.is_held(), 150)
	assert_true(landed, "it lands")
	await step_ticks(1)
	assert_eq(_hits("player", "test.ogre_grab", "ability.throw_held").size(), 1, "and takes its landing hit")
	assert_true(o.controller.state != CS.GRABBED, "it is free again")
