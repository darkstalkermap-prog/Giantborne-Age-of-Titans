extends IntegrationSuite
## A2: Stoneback, the first signature titan, in the quarry test arena (scenes/test/quarry_test.tscn), the lean
## cases (the charge into a rock, the trampled props, the flank answer and the seeded runs are in
## tests/slow/test_stoneback_battery.gd and tests/gate/test_stoneback_seeded.gd):
##   * a plate takes blows (the armoured share reaches the body), breaks once - Events.plate_broken, the stagger,
##     the mesh hidden - and its region is a weak point from then on;
##   * HitFactory strikes a titan in one region a pulse (the deepest contact), a real swing included;
##   * each attack is telegraphed as its windup begins and lands; the smash's shock line strikes once;
##   * phase 2 after two plates (with the rage) and at half health; a new attempt makes every plate whole;
##   * the lock frames the nearest plate the giant can reach, a broken one first;
##   * he dies, and leaves his loot.

const QUARRY := "res://scenes/test/quarry_test.tscn"
const TB := preload("res://tools/builders/titans.gd")

var level: Node3D
var tels: Array = []
var broken: Array = []
var phases: Array = []


func before_each() -> void:
	await super()
	tels.clear()
	broken.clear()
	phases.clear()
	Events.telegraph_started.connect(_on_tel)
	Events.plate_broken.connect(_on_broken)
	Events.boss_phase_changed.connect(_on_phase)


func after_each() -> void:
	for sig: Signal in [Events.telegraph_started, Events.plate_broken, Events.boss_phase_changed]:
		for c: Dictionary in sig.get_connections():
			if (c.callable as Callable).get_object() == self:
				sig.disconnect(c.callable)
	PersonRig.reset_for_tests()
	await super()


func _on_tel(tick: int, actor_id: String, action_id: String, target_id: String, shape: String, origin: Vector3,
		_yaw: float, radius: float, length: float, _d: float) -> void:
	tels.append({"tick": tick, "actor": actor_id, "action": action_id, "target": target_id, "shape": shape,
		"origin": origin, "radius": radius, "length": length})


func _on_broken(tick: int, id: String, plate: String) -> void:
	broken.append([tick, id, plate])


func _on_phase(_t: int, id: String, phase: int) -> void:
	phases.append([id, phase])


func _load(stage := 5, skinned := false) -> Dictionary:
	if skinned:
		PersonRig.enable_for_tests()
	level = (load(QUARRY) as PackedScene).instantiate() as Node3D
	level.set("stage", 0)
	world.add_child(level)
	var p := level.get_node("Player") as GiantPlayer
	p.router.use_injection = true
	await TestWait.until(self, func() -> bool: return p.is_on_floor(), 30)
	TitanDuel.prepare(p, stage)
	var t := level.get_node("Stoneback") as TitanEnemy
	t.ai_enabled = false
	t.brain.target_id = p.entity.entity_id
	return {"player": p, "arena": level.get_node("BossArena") as BossArena, "titan": t}


func _blow(p: GiantPlayer, t: TitanEnemy, region: String, power: float, heavy := false) -> void:
	var e := HitEvent.new()
	e.tick = Sim.tick
	e.instance_id = Sim.new_instance_id()
	e.attacker_id = p.entity.entity_id
	e.target_id = t.entity_id
	e.power = power
	e.attacker_stat = 0.0
	e.size_policy = "none"
	e.poise_damage = 1.0
	e.tags = PackedStringArray(["Melee", "Heavy"] if heavy else ["Melee"])
	e.region = region
	e.attacker_position = p.global_position
	Sim.queue_hit(e)


func test_a_plate_takes_blows_breaks_once_and_leaves_a_weak_point() -> void:
	var n := await _load(5, true)
	var p: GiantPlayer = n.player
	var t: TitanEnemy = n.titan
	assert_eq(t.entity_id, TB.STONEBACK_ID, "Stoneback stands in the quarry")
	assert_true(t.entity.plates != null and t.entity.plates.plates.size() == 10, "his ten plates (four breakable, six armour only)")
	assert_false(t.can_be_grabbed(), "never grabbable")
	var rig := t.rig as TitanRig
	assert_true(rig != null and rig.has_model(), "his model is drawn (StonebackRig)")
	var pools := t.entity.combatant.pools
	var hp0 := pools.health
	_blow(p, t, "shoulder_l", 400.0)
	await step_ticks(1)
	var r := hits_on(t.entity_id).back() as HitResult
	assert_eq(r.event.plate_state, PlateRules.STATE_ARMOURED, "the plate is struck: armoured")
	var armour := 100.0 / (100.0 + float(t.record.armor))
	assert_eq(r.health_damage, CombatRules.round_damage(400.0 * armour * 0.15), "15 % of the blow reaches him")
	assert_near(hp0 - pools.health, float(r.health_damage), 1e-4, "his health")
	var stone := float(t.plates().plate("shoulder_l").health)
	assert_near(t.plates().health_frac("shoulder_l"), 1.0 - 400.0 / stone, 1e-4, "the stone took the raw blow")
	assert_true(broken.is_empty(), "not broken yet")
	_blow(p, t, "shoulder_l", stone, true)   # a heavy: x1.5 - more than the stone left
	await step_ticks(1)
	assert_eq(broken.size(), 1, "it breaks: Events.plate_broken")
	assert_eq(broken[0][2], "shoulder_l", "the shoulder's")
	assert_eq(t.plate_breaks, ["shoulder_l"] as Array[String], "once")
	assert_eq(t.controller.state, CombatController.State.STAGGERED, "the break staggers him")
	await step_ticks(2)
	assert_false(rig.model.plate_visible("plate_shoulder_l"), "the plate's mesh is gone")
	assert_true(rig.model.plate_visible("plate_shoulder_r"), "the other shoulder's stays")
	assert_true(rig.plates_shown_broken.has("shoulder_l"), "the rig threw its stone")
	var before := pools.health
	_blow(p, t, "shoulder_l", 400.0)
	await step_ticks(1)
	var w := hits_on(t.entity_id).back() as HitResult
	assert_eq(w.event.plate_state, PlateRules.STATE_WEAK, "now a weak point")
	assert_eq(w.health_damage, CombatRules.round_damage(400.0 * armour * 2.2), "x2.2")
	assert_near(before - pools.health, float(w.health_damage), 1e-4, "his health")
	assert_eq(broken.size(), 1, "it never breaks twice")
	# the torso has no plate; an armour-only shin never breaks
	_blow(p, t, "torso", 400.0)
	_blow(p, t, "shin_l", 3000.0, true)
	await step_ticks(1)
	var hs := hits_on(t.entity_id)
	assert_eq(hs[hs.size() - 2].event.plate_id, "hide_torso", "the torso: his hide (armour only)")
	assert_eq(hs[hs.size() - 1].event.plate_state, PlateRules.STATE_ARMOURED, "the shin is armoured")
	assert_false(t.plates().is_broken("shin_l"), "and never breaks")


func test_a_real_swing_strikes_one_region_by_contact() -> void:
	var n := await _load(5)
	var p: GiantPlayer = n.player
	var t: TitanEnemy = n.titan
	var front := t.global_position + Vector3(0, 0, 9.5)
	p.global_position = Vector3(front.x, 0.05, front.z)
	p.facing_yaw = 0.0
	p.rotation.y = 0.0
	p.camera_rig.yaw = 0.0
	await step_ticks(2)
	p.entity.combatant.pools.stamina = p.entity.combatant.pools.stamina_max
	p.router.inject_edge(&"light")
	await TestWait.until(self, func() -> bool: return not hits_on(t.entity_id).is_empty(), 90)
	var hs := hits_on(t.entity_id)
	assert_eq(hs.size(), 1, "one hit on the titan for the swing (hits are per entity)")
	assert_true(hs[0].event.region != "", "it struck a region (%s)" % hs[0].event.region)
	# the same candidates always pick the same region, whatever their order
	var cands: Array = []
	for hb: Hurtbox in t.entity.hurtboxes:
		cands.append({"entity": t.entity, "hurtbox": hb, "point": hb.global_position + Vector3(0, 0, 0.4) * float(cands.size()),
			"substep": 1, "distance": 10.0, "weak_point": false})
	var a := cands.duplicate()
	var b := cands.duplicate()
	b.reverse()
	HitFactory.pick_titan_regions(a)
	HitFactory.pick_titan_regions(b)
	assert_eq(a.size(), 1, "one candidate a titan")
	assert_eq((a[0].hurtbox as Hurtbox).region, (b[0].hurtbox as Hurtbox).region, "the order does not matter")
	assert_eq((a[0].hurtbox as Hurtbox).region, (cands[0].hurtbox as Hurtbox).region, "the deepest contact wins")


func test_each_attack_is_telegraphed_and_lands_the_smash_once() -> void:
	var n := await _load(5)
	var p: GiantPlayer = n.player
	var t: TitanEnemy = n.titan
	p.entity.apply_status("status.debug_invulnerable", NAN, 600.0, "test")
	var specs := [["ability.stoneback_smash", 12.0, "line"], ["ability.stoneback_sweep", 10.0, "cone"],
		["ability.stoneback_boulder", 40.0, "circle"]]
	for s: Array in specs:
		t.global_position = Vector3(0, 0.05, -20)
		p.global_position = Vector3(0, 0.05, -20 + float(s[1]))
		p.velocity = Vector3.ZERO
		t.facing_yaw = PI
		t.rotation.y = PI
		await step_ticks(2)
		hits.clear()
		tels.clear()
		var a := GameData.get_action(str(s[0]))
		t.controller.force_action(a)
		await step_ticks(1)
		assert_eq(tels.size(), 1, "%s: telegraphed as its windup begins" % a.id)
		assert_eq(str(tels[0].shape), str(s[2]), "%s: a %s" % [a.id, s[2]])
		assert_eq(str(tels[0].target), p.entity.entity_id, "%s: at the giant" % a.id)
		await step_ticks(a.windup_ticks + a.active_ticks + 90)
		var on := hits_on(p.entity.entity_id)
		assert_eq(on.size(), 1, "%s: lands once on a giant standing in it (%d)" % [a.id, on.size()])
		if not on.is_empty():
			assert_eq(on[0].event.action_id, a.id, "%s: its blow" % a.id)
			assert_true(on[0].event.tick >= int(tels[0].tick) + a.windup_ticks, "%s: after its whole windup" % a.id)


func test_phase_two_after_two_plates_once_with_the_rage() -> void:
	var n := await _load(5)
	var p: GiantPlayer = n.player
	var t: TitanEnemy = n.titan
	(n.arena as BossArena).engage()
	assert_true(t.break_plate("back"), "the back breaks")
	assert_eq(t.brain.boss_phase(), 1, "one plate: still phase 1")
	t.controller.call("_end_stagger")
	await step_ticks(2)
	_blow(p, t, "shoulder_r", 5000.0)
	await step_ticks(1)
	assert_eq(t.plates().broken_count(), 2, "two plates")
	assert_eq(t.brain.boss_phase(), 1, "not while he reels from it")
	assert_true(t.entity.combatant.pools.ratio("health") > 0.5, "long before half his health")
	t.controller.call("_end_stagger")
	await step_ticks(2)
	assert_eq(t.brain.boss_phase(), 2, "phase 2 after two plates")
	assert_eq(phases, [[TB.STONEBACK_ID, 2]], "announced once")
	assert_eq(t.controller.action_id(), "ability.stoneback_roar", "with his rage")
	assert_near((t.brain as TitanBrain).strike_pause_scale(), 0.75, 1e-6, "and faster chains (A3: x0.75, was x0.6)")
	# a new attempt: every plate whole, phase 1 again
	t.p34_reset_attempt()
	await step_ticks(1)
	assert_eq(t.plates().broken_count(), 0, "a new attempt: every plate whole")
	assert_eq(t.brain.boss_phase(), 1, "phase 1 again")
	t.p34_stop_return()


func test_phase_two_at_half_health() -> void:
	var n := await _load(5)
	var t: TitanEnemy = n.titan
	t.entity.combatant.pools.health = t.entity.combatant.pools.health_max * 0.49
	await step_ticks(2)
	assert_eq(t.brain.boss_phase(), 2, "phase 2 at half his health")
	assert_eq(t.plates().broken_count(), 0, "(no plate broken)")


func test_the_lock_frames_the_nearest_reachable_plate_a_broken_one_first() -> void:
	var n := await _load(5)
	var p: GiantPlayer = n.player
	var t: TitanEnemy = n.titan
	var h := p.entity.combatant.height_m
	t.facing_yaw = PI   # (he faces +Z: the quarry's entrance)
	t.rotation.y = PI
	p.global_position = t.global_position + Vector3(0, 0.05, 14)   # before him
	await step_ticks(1)
	var front := t.entity.lock_anchor_position(h)
	var anchors := t.get_node("Anchors")
	var brow := (anchors.get_node("PlateBrow") as Node3D).global_position
	var shoulder_l := (anchors.get_node("PlateShoulderL") as Node3D).global_position
	assert_true(front.distance_to(brow) < 0.01 or front.distance_to(shoulder_l) < 0.01
		or front.distance_to((anchors.get_node("PlateShoulderR") as Node3D).global_position) < 0.01,
		"before him: a front plate (%s)" % front)
	p.global_position = t.global_position + Vector3(0, 0.05, -14)  # behind him
	await step_ticks(1)
	assert_true(t.entity.lock_anchor_position(h).distance_to((anchors.get_node("PlateBack") as Node3D).global_position) < 0.01,
		"behind him: the back")
	t.break_plate("shoulder_l")
	p.global_position = t.global_position + Vector3(0, 0.05, 14)
	await step_ticks(1)
	assert_true(t.entity.lock_anchor_position(h).distance_to(shoulder_l) < 0.5, "a broken plate first")
	# a stage-3 giant reaches none of them: his knee, as every tall boss
	var low := t.entity.lock_anchor_position(7.92)
	assert_true(low.y < 6.0, "a stage-3 giant locks his knee (%.1f m)" % low.y)


func test_he_dies_and_leaves_his_loot() -> void:
	var n := await _load(5)
	var p: GiantPlayer = n.player
	var t: TitanEnemy = n.titan
	t.entity.combatant.pools.health = 10.0
	_blow(p, t, "torso", 5000.0)
	await step_ticks(3)
	assert_false(t.entity.is_alive(), "he falls")
	assert_eq(WorldState.get_flag("boss.stoneback.outcome"), "slain", "his outcome")
	for item: String in ["item.stoneback_heart_stone", "item.stoneback_slab", "item.quarry_iron"]:
		assert_true(loot.any(func(l: String) -> bool: return l.ends_with(":" + item)), "his loot: %s (%s)" % [item, loot])


## A3: a plate shows its cracks as its stone wears (whole above 60 %, cracked, badly cracked below 30 %; only that
## plate's material), the smash's blow raises dust and the trunk falls from his fist as he dies.
func test_a3_cracks_dust_and_the_falling_trunk() -> void:
	var n := await _load(5, true)
	var p: GiantPlayer = n.player
	var t: TitanEnemy = n.titan
	var rig := t.rig as TitanRig
	assert_true(rig != null and rig.has_model(), "his model is drawn")
	assert_eq(TitanRig.crack_for(1.0), 0.0, "whole stone: no cracks")
	assert_eq(TitanRig.crack_for(0.45), StonebackRig.CRACKED, "under 60 %: cracked")
	assert_eq(TitanRig.crack_for(0.2), StonebackRig.BADLY_CRACKED, "under 30 %: badly cracked")
	var stone := float(t.plates().plate("back").health)
	_blow(p, t, "back", stone * 0.55)
	await step_ticks(3)
	assert_true(t.plates().health_frac("back") < 0.6, "the back's stone at %.2f" % t.plates().health_frac("back"))
	assert_eq(rig.model.plate_crack("plate_back"), StonebackRig.CRACKED, "the back plate shows its cracks")
	assert_eq(rig.model.plate_crack("plate_shoulder_l"), 0.0, "the others stay whole")
	var m := (rig.model.piece("plate_back") as MeshInstance3D).material_override as ShaderMaterial
	assert_near(float(m.get_shader_parameter("crack")), StonebackRig.CRACKED, 1e-4, "its own material's crack")
	var other := (rig.model.piece("plate_shoulder_l") as MeshInstance3D).material_override as ShaderMaterial
	assert_true(other != m, "each breakable plate its own material")
	# the smash: dust where the root ball strikes
	var dust0 := rig.dust_raised
	t.controller.force_action(GameData.get_action("ability.stoneback_smash"))
	await TestWait.until(self, func() -> bool: return rig.smash_impacts > 0, 240)
	assert_eq(rig.smash_impacts, 1, "the blow lands once in the clip")
	assert_true(rig.dust_raised > dust0, "and raises dust")
	await step_ticks(200)
	# his death: the trunk leaves his fist and falls flat
	t.entity.combatant.pools.health = 10.0
	_blow(p, t, "torso", 5000.0)
	await TestWait.until(self, func() -> bool: return rig.club_fallen(), 240)
	assert_true(rig.fallen_club != null, "a fallen trunk in the world")
	assert_false(rig.model.piece("club").visible, "no longer in his hand")
	assert_true(rig.club_fallen(), "it has fallen flat")
	var ends := rig.fallen_club_ends()
	var ground := t.global_position.y
	assert_true(absf((ends[0] as Vector3).y - ground - 1.5) < 0.6, "its root ball on the ground (%.1f m up)" % ((ends[0] as Vector3).y - ground))
	assert_true((ends[1] as Vector3).y - ground < 2.5, "its handle end down too (%.1f m up)" % ((ends[1] as Vector3).y - ground))
