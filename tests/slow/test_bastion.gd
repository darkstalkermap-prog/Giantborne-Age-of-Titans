extends IntegrationSuite
## C2: the Broken Warden's fight in the yard test arena (scenes/test/bastion_test.tscn): his scene (TitanEnemy, his
## shield's turned box and his plates' hurtboxes and anchors following the kneel), asleep until a blow or the arena
## wakes him; his guard (a blow from before him lands on the shield whatever it struck and does little, one from
## behind lands where it struck; heavies fill the meter and break the guard: a stagger and an open guard); the
## shield's break disarms him (phase 2 at once, its re-arm, no guard after); a crumbling tower smashed beside him
## falls on him (a stagger, his guard open, every blow's poise more); his greaves topple him; his death drops his
## parts. Scripted blows through the ordinary resolution.

const YARD := "res://scenes/test/bastion_test.tscn"

var level: Node3D
var events: Array = []
var counts := {}


func before_each() -> void:
	await super()
	events.clear()
	counts.clear()
	Events.loot_awarded.connect(_on_loot_count)
	Events.titan_guard_broken.connect(_on_guard)
	Events.titan_disarmed.connect(_on_disarmed)
	Events.titan_rubble.connect(_on_rubble)
	Events.titan_woke.connect(_on_woke)


func after_each() -> void:
	for sig: Signal in [Events.titan_guard_broken, Events.titan_disarmed, Events.titan_rubble, Events.titan_woke,
			Events.loot_awarded]:
		for c: Dictionary in sig.get_connections():
			if (c.callable as Callable).get_object() == self:
				sig.disconnect(c.callable)
	PersonRig.reset_for_tests()
	await super()


func _on_loot_count(_t: int, _w: String, item: String, c: int, _r: String) -> void:
	counts[item] = int(counts.get(item, 0)) + c


func _on_guard(t: int, id: String, plate: String) -> void:
	events.append([t, "guard_broken", id, plate])


func _on_disarmed(t: int, id: String, plate: String) -> void:
	events.append([t, "disarmed", id, plate])


func _on_rubble(t: int, id: String, world_id: String) -> void:
	events.append([t, "rubble", id, world_id])


func _on_woke(t: int, id: String, reason: String) -> void:
	events.append([t, "woke", id, reason])


func _kinds() -> Array:
	var out: Array = []
	for e: Array in events:
		out.append(str(e[1]) + ":" + str(e[3]))
	return out


func _load(stage := 5) -> Dictionary:
	level = (load(YARD) as PackedScene).instantiate() as Node3D
	level.set("stage", 0)
	world.add_child(level)
	var p := level.get_node("Player") as GiantPlayer
	p.router.use_injection = true
	await TestWait.until(self, func() -> bool: return p.is_on_floor(), 30)
	TitanDuel.prepare(p, stage)
	var t := level.get_node("Bastion") as TitanEnemy
	return {"player": p, "titan": t}


## A scripted blow from `from` (world position) on `region`.
func _blow(p: GiantPlayer, t: TitanEnemy, region: String, power: float, from: Vector3, heavy := false,
		poise := 1.0) -> void:
	var e := HitEvent.new()
	e.tick = Sim.tick
	e.instance_id = Sim.new_instance_id()
	e.attacker_id = p.entity.entity_id
	e.target_id = t.entity_id
	e.power = power
	e.attacker_stat = 0.0
	e.size_policy = "none"
	e.poise_damage = poise
	e.attacker_height_m = float(t.record.height_m)
	e.tags = PackedStringArray(["Melee", "BasicAttack", "Heavy"] if heavy else ["Melee", "BasicAttack", "Light"])
	e.region = region
	e.attacker_position = from
	Sim.queue_hit(e)


## A point `d` metres from him in his own frame (x: his right, z: before him).
func _around(t: TitanEnemy, right: float, ahead: float) -> Vector3:
	var b := t.global_transform.basis
	return t.global_position + b.x * right - b.z * ahead


## Enough of a heavy's power to break plate `id` in one blow (its stone twice over).
func _stone(t: TitanEnemy, id: String) -> float:
	return float(t.plates().plate(id).health) * 2.0


func _woken(t: TitanEnemy) -> void:
	t.wake("test")
	t.ai_enabled = false
	await step_ticks(2)


func test_his_scene_and_record() -> void:
	var rec := GameData.get_record("enemy.bastion")
	assert_near(float(rec.height_m), 22.4, 1e-6, "73 ft: over a stage-6 giant")
	assert_true(bool(rec.dormant), "he sleeps")
	var scene := (load("res://scenes/enemies/bastion.tscn") as PackedScene).instantiate()
	assert_true(scene is TitanEnemy, "a TitanEnemy")
	for n: String in ["Shield", "ShoulderL", "Back", "Head", "ShinL", "ShinR", "FlankR", "ArmR", "Torso", "Legs"]:
		var hb := scene.get_node_or_null("Hurtboxes/" + n) as Node3D
		assert_true(hb != null, "a hurtbox %s" % n)
		if hb != null:
			assert_true(hb.has_meta(TitanEnemy.KNEEL_META), "%s follows the kneel" % n)
	for n: String in ["PlateShield", "PlateShoulderL", "PlateBack", "PlateHelm", "PlateShinL", "PlateShinR", "PlateMend",
			"Torso", "KneeL", "KneeR"]:
		assert_true(scene.get_node_or_null("Anchors/" + n) != null, "an anchor %s" % n)
	var sh := scene.get_node("Hurtboxes/Shield") as Node3D
	assert_true(sh.position.x < -1.0, "the shield on his left (%.1f)" % sh.position.x)
	assert_true(sh.position.y > 5.0 and sh.position.y < 12.0, "held low: its middle at %.1f m" % sh.position.y)
	var head := scene.get_node("Hurtboxes/Head") as Node3D
	assert_true(head.position.y > 18.0, "his helm over the shield's top (%.1f m)" % head.position.y)
	var k: Vector3 = head.get_meta(TitanEnemy.KNEEL_META)
	assert_true(k.y < head.position.y - 3.0, "his helm comes down when he kneels (%.1f m)" % k.y)
	scene.free()


func test_he_sleeps_until_a_blow_wakes_him() -> void:
	var n := await _load()
	var p: GiantPlayer = n.player
	var t: TitanEnemy = n.titan
	assert_true(t.dormant, "asleep")
	assert_false(t.ai_enabled, "his AI off")
	p.global_position = _around(t, 0.0, 16.0)
	await step_ticks(90)
	assert_true(t.dormant, "still asleep before a giant")
	_blow(p, t, "torso", 40.0, p.global_position)
	await step_ticks(2)
	assert_false(t.dormant, "a blow wakes him")
	assert_eq(t.wake_reason, "struck", "struck")
	assert_true((level.get_node("BossArena") as BossArena).is_engaged(), "his ground engaged")


func test_the_guard_takes_what_comes_from_before_him() -> void:
	var n := await _load()
	var p: GiantPlayer = n.player
	var t: TitanEnemy = n.titan
	await _woken(t)
	assert_true(t.has_guard(), "a guard")
	assert_true(t.guard_raised(), "raised")
	var ps := t.plates()
	var before := t.entity.combatant.pools.health
	var front := _around(t, -2.0, 14.0)
	_blow(p, t, "shin_l", 400.0, front)
	await step_ticks(2)
	var r: HitResult = hits_on(t.entity_id).back()
	assert_true(r.event.guarded, "caught")
	assert_eq(r.event.region, "shield", "on the shield whatever it struck")
	var took := before - t.entity.combatant.pools.health
	assert_true(took < 400.0 * 0.15, "and little reaches him (%.1f of 400)" % took)
	assert_true(ps.health_frac("shield") < 1.0, "the shield's stone takes it")
	assert_near(ps.health_frac("greave_l"), 1.0, 1e-6, "not the greave it struck")
	# behind him: where it struck
	before = t.entity.combatant.pools.health
	_blow(p, t, "back", 400.0, _around(t, 0.0, -14.0))
	await step_ticks(2)
	r = hits_on(t.entity_id).back()
	assert_false(r.event.guarded, "from behind: not caught")
	assert_true(ps.health_frac("back") < 1.0, "his back's plate takes it")
	# his broken right side: outside the arc
	_blow(p, t, "flank_r", 400.0, _around(t, 14.0, -1.0))
	await step_ticks(2)
	assert_false((hits_on(t.entity_id).back() as HitResult).event.guarded, "from his right: not caught")


func test_heavies_break_the_guard_open() -> void:
	var n := await _load()
	var p: GiantPlayer = n.player
	var t: TitanEnemy = n.titan
	await _woken(t)
	var ps := t.plates()
	var front := _around(t, -1.0, 14.0)
	var meter := float(ps.guard.meter)
	var heavies := 0
	while t.guard_breaks == 0 and heavies < 40:
		_blow(p, t, "torso", 30.0, front, true, 60.0)
		heavies += 1
		await step_ticks(3)
	assert_eq(t.guard_breaks, 1, "the meter filled: broken (%d heavies of 60 poise, meter %.0f)" % [heavies, meter])
	assert_true(heavies >= 2, "not by one blow")
	assert_true(_kinds().has("guard_broken:shield"), "titan_guard_broken")
	assert_eq(t.controller.state, CombatController.State.STAGGERED, "he staggers")
	assert_eq(t.controller.stagger_reason, TitanEnemy.GUARD_REASON, "a guard break's stagger")
	assert_eq(str(t.get_rig_state().get("stagger_reason", "")), TitanEnemy.GUARD_REASON, "the rig is told (its clip)")
	assert_false(t.guard_raised(), "his guard open")
	_blow(p, t, "shin_l", 200.0, front, true)
	await step_ticks(2)
	var r: HitResult = hits_on(t.entity_id).back()
	assert_false(r.event.guarded, "a blow from before him now lands where it struck")
	assert_true(ps.health_frac("greave_l") < 1.0, "on the greave")
	await step_ticks(int(float(ps.guard.open_s) * 60.0) + 10)
	await TestWait.until(self, func() -> bool: return t.guard_raised(), 600)
	assert_true(t.guard_raised(), "it comes up again")


func test_the_shields_break_disarms_him() -> void:
	var n := await _load()
	var p: GiantPlayer = n.player
	var t: TitanEnemy = n.titan
	await _woken(t)
	t.ai_enabled = true
	t.brain.target_id = p.entity.entity_id
	_blow(p, t, "shield", _stone(t, "shield"), _around(t, 0.0, 14.0), true)
	await step_ticks(2)
	assert_true(t.plates().is_broken("shield"), "the shield broken")
	assert_true(t.disarmed, "thrown down")
	assert_true(_kinds().has("disarmed:shield"), "titan_disarmed")
	assert_false(t.guard_raised(), "no guard after")
	await TestWait.until(self, func() -> bool: return t.brain.boss_phase() == 2, 400)
	assert_eq(t.brain.boss_phase(), 2, "his second phase on the shield's break")
	await TestWait.until(self, func() -> bool: return started.has(t.entity_id + ":ability.bastion_rearm"), 400)
	assert_true(started.has(t.entity_id + ":ability.bastion_rearm"), "he takes the bar in both hands (%s)" % str(started))
	var before := t.entity.combatant.pools.health
	_blow(p, t, "torso", 200.0, _around(t, 0.0, 14.0), true)
	await step_ticks(2)
	assert_false((hits_on(t.entity_id).back() as HitResult).event.guarded, "nothing to catch a blow")
	assert_true(t.entity.combatant.pools.health < before, "it reaches him")


func test_a_tower_smashed_beside_him_falls_on_him() -> void:
	var n := await _load()
	var p: GiantPlayer = n.player
	var t: TitanEnemy = n.titan
	await _woken(t)
	var tower: BreakableProp = null
	for b in get_tree().get_nodes_in_group("breakables"):
		if str(b.get("world_id")) == "test.yard.tower_west":
			tower = b as BreakableProp
	assert_true(tower != null, "a crumbling tower in the yard")
	var flat := Vector2(tower.global_position.x - t.global_position.x, tower.global_position.z - t.global_position.z)
	assert_true(flat.length() <= float(t.record.rubble.radius_m), "within the rubble's reach (%.1f m)" % flat.length())
	var mult := t.plates().poise_taken_mult
	queue_hit(p.entity.entity_id, tower.entity.entity_id, tower.global_position + Vector3(0, 2, 4), 5000.0)
	await step_ticks(3)
	assert_eq(t.rubble_falls, 1, "the rubble fell on him")
	assert_true(_kinds().has("rubble:test.yard.tower_west"), "titan_rubble")
	assert_eq(t.controller.stagger_reason, TitanEnemy.RUBBLE_REASON, "a stagger of rubble")
	assert_false(t.guard_raised(), "his guard open")
	assert_true(t.rubble_dazed(), "dazed")
	assert_near(t.plates().poise_taken_mult, mult * float(t.record.rubble.poise_mult), 1e-4, "his poise weaker")
	await step_ticks(int(float(t.record.rubble.for_s) * 60.0) + 5)
	assert_near(t.plates().poise_taken_mult, mult, 1e-4, "for a while")


func test_his_greaves_topple_him() -> void:
	var n := await _load()
	var p: GiantPlayer = n.player
	var t: TitanEnemy = n.titan
	await _woken(t)
	_blow(p, t, "shin_r", _stone(t, "greave_r"), _around(t, 6.0, -10.0), true)
	await step_ticks(2)
	assert_true(t.plates().is_broken("greave_r"), "a greave broken")
	await TestWait.until(self, func() -> bool: return t.is_down(), 60)
	assert_true(t.is_down(), "toppled")


func test_his_death_drops_his_parts() -> void:
	var n := await _load()
	var p: GiantPlayer = n.player
	var t: TitanEnemy = n.titan
	await _woken(t)
	_blow(p, t, "back", _stone(t, "back"), _around(t, 0.0, -14.0), true)
	await step_ticks(2)
	assert_true(t.plates().is_broken("back"), "his back broken")
	t.entity.combatant.pools.health = 10.0
	_blow(p, t, "torso", 5000.0, _around(t, 0.0, -14.0), true)
	await step_ticks(3)
	assert_false(t.entity.is_alive(), "dead")
	assert_eq(int(counts.get("item.warden_keystone", 0)), 1, "his keystone")
	assert_eq(int(counts.get("item.warden_ashlar", 0)), 4, "four ashlar")
	assert_true(t.plates().ever_broken.has("shield"), "his shield thrown down on the way (phase 2 at 35 %)")
	assert_eq(int(counts.get("item.gate_iron", 0)), 8, "four of the gate's iron, the broken back's one, the shield's three")
