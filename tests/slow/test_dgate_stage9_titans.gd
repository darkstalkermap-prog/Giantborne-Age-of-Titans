extends IntegrationSuite
## Dgate (task f): at 116 ft a stage-9 giant stands over the 28 m Frostbound and level with the 34 m Stormcaller - the
## titans of stages 7 and 8, outgrown on purpose. Neither fight may break at stage 9: in each titan's test arena
## (TitanDuel.prepare at stage 9: growth.09, level 17, the greatforged club) the lock takes him from across his arena,
## the aim indicator (PlayerAttack.next_swing_plan) names him and one of his plates and the swing strikes what it
## named, a press is a swing - never C3b's stamp or stomp (a titan has plates: they are for what stands at the feet) -
## a stage-9 heavy takes only a small share of his health, and his own blows still reach and hurt the giant.

const TARN := "res://scenes/test/frostbound_test.tscn"
const STEPS := "res://scenes/test/stormcaller_test.tscn"

var level: Node3D


func _load(scene: String, titan: String) -> Dictionary:
	level = (load(scene) as PackedScene).instantiate() as Node3D
	level.set("stage", 0)
	world.add_child(level)
	var p := level.get_node("Player") as GiantPlayer
	p.router.use_injection = true
	await TestWait.until(self, func() -> bool: return p.is_on_floor(), 30)
	var r := TitanDuel.prepare(p, 9)
	assert_true(bool(r.ok) and int(r.level) == 17, "a stage-9 giant at level 17 (%s)" % str(r))
	await step_ticks(150)   # (the camera's arm restores to stage 9's length)
	var t := level.get_node(titan) as TitanEnemy
	t.wake("test")
	await step_ticks(1)
	if t.controller.action != null:
		t.controller.call("_finish_action", true)
	t.ai_enabled = false
	await step_ticks(2)
	return {"player": p, "titan": t}


func _face(p: GiantPlayer, t: TitanEnemy, distance: float) -> void:
	var dir := t.global_transform.basis.z * -1.0
	dir.y = 0.0
	var at := t.global_position + dir.normalized() * distance
	p.global_position = Vector3(at.x, p.global_position.y, at.z)
	p.velocity = Vector3.ZERO
	var to := t.global_position - p.global_position
	p.facing_yaw = TargetingRules.yaw_of(Vector3(to.x, 0.0, to.z))
	p.rotation.y = p.facing_yaw
	p.camera_rig.yaw = p.facing_yaw
	await step_ticks(6)


func _idle(p: GiantPlayer) -> void:
	await TestWait.until(self, func() -> bool: return p.controller.state == CombatController.State.LOCOMOTION, 240)
	await step_ticks(45)


func _check(scene: String, titan: String, name: String) -> void:
	var n := await _load(scene, titan)
	var p: GiantPlayer = n.player
	var t: TitanEnemy = n.titan
	var h9 := float(p.profile.height_m)
	var ht := float(t.record.height_m)
	print("    Dgate: stage 9 (%.1f m) against the %s (%.1f m)" % [h9, name, ht])
	# the lock from across his arena
	await _face(p, t, 60.0)
	p.targeting.try_lock()
	await step_ticks(2)
	assert_true(p.targeting.locked_entity() == t.entity, "%s: locked from 60 m" % name)
	# the aim indicator names him and a plate within the swing's reach, and the swing strikes what it named
	await _face(p, t, float(p.profile.melee_reach_m) * 0.6)
	p.targeting.try_lock()
	await _idle(p)
	for heavy: bool in [false, true]:
		var plan: Dictionary = p.attack.next_swing_plan(heavy)
		var tag := "%s, %s" % [name, "heavy" if heavy else "light"]
		assert_true(plan.get("entity") == t.entity, "%s: the indicator aims at him (%s)" % [tag, plan.get("source", "")])
		assert_eq(str(plan.get("strike", "")), "swing", "%s: a swing, not a stamp or a stomp" % tag)
		assert_true(bool(plan.get("reaches", false)) and plan.get("primary") == t.entity, "%s: in reach, him struck" % tag)
		var region := ""
		for s: Dictionary in plan.get("struck", []):
			if s.entity == t.entity:
				region = str(s.region)
		assert_true(region != "", "%s: on a plate or part of him (%s)" % [tag, region])
		var health := float(t.entity.combatant.pools.health)
		var before := hits.size()
		p.router.inject_edge(&"heavy" if heavy else &"light")
		await step_ticks(2)
		var instance := p.controller.instance_id
		await TestWait.until(self, func() -> bool: return p.controller.state == CombatController.State.LOCOMOTION, 240)
		await step_ticks(4)
		var struck := false
		for i in range(before, hits.size()):
			var e := hits[i].event
			if e.attacker_id == p.entity.entity_id and e.instance_id == instance and e.target_id == t.entity_id:
				struck = true
		assert_true(struck, "%s: the swing struck him" % tag)
		var share := (health - float(t.entity.combatant.pools.health)) / float(t.entity.combatant.pools.health_max)
		print("    Dgate: %s on %s: %.2f %% of his health" % [tag, region, share * 100.0])
		assert_true(share > 0.0 and share < 0.05, "%s: a blow takes a small share of his health (%.2f %%)" % [tag, share * 100.0])
		await _idle(p)
	# his blows still reach and hurt a giant this size
	p.targeting.release_lock("test")
	await _face(p, t, ht * 0.45)
	var giant_hp := float(p.entity.combatant.pools.health)
	var his := 0
	var start := hits.size()
	t.brain.target_id = p.entity.entity_id
	t.ai_enabled = true
	for i in 60 * 25:
		await step_ticks(1)
		p.entity.combatant.pools.stamina = p.entity.combatant.pools.stamina_max
		if p.entity.combatant.pools.health < giant_hp * 0.6:
			break
	for i in range(start, hits.size()):
		var e := hits[i].event
		if e.attacker_id == t.entity_id and e.target_id == p.entity.entity_id:
			his += 1
	t.ai_enabled = false
	var lost := giant_hp - float(p.entity.combatant.pools.health)
	print("    Dgate: the %s's blows on a stage-9 giant in 25 s: %d, %.0f of %.0f health" % [name, his, lost, giant_hp])
	assert_true(his >= 2 and lost > 0.0, "%s: his blows reach a stage-9 giant and hurt him (%d blows, %.0f)" % [name, his, lost])


func test_the_frostbound_at_stage_9() -> void:
	await _check(TARN, "Frostbound", "Frostbound")


func test_the_stormcaller_at_stage_9() -> void:
	await _check(STEPS, "Stormcaller", "Stormcaller")
