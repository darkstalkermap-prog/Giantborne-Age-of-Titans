extends IntegrationSuite
## D1: the Frostbound Titan's fight in the frozen tarn test arena (scenes/test/frostbound_test.tscn): his scene
## (TitanEnemy, his ice's hurtboxes and anchors following the kneel), asleep kneeling until a blow wakes him (his wake
## action: no blow until he has risen and roared); his breath rimes a giant before him and not one behind; the tarn's
## ice: cracked ice gives under his step, open water he steps into takes him to the knee (a down, his blows' bonus,
## Events.titan_fell_through), not again until his cooldown; his second phase's cold aura rimes a giant near him; his
## serac's break unbalances him, his greaves topple him; his death drops his parts. Scripted blows through the ordinary
## resolution.

const TARN := "res://scenes/test/frostbound_test.tscn"

var level: Node3D
var counts := {}
var falls: Array = []


func before_each() -> void:
	await super()
	counts.clear()
	falls.clear()
	WorldState.clear()
	Events.loot_awarded.connect(_on_loot_count)
	Events.titan_fell_through.connect(_on_fell)


func after_each() -> void:
	for sig: Signal in [Events.loot_awarded, Events.titan_fell_through]:
		for c: Dictionary in sig.get_connections():
			if (c.callable as Callable).get_object() == self:
				sig.disconnect(c.callable)
	PersonRig.reset_for_tests()
	await super()


func _on_loot_count(_t: int, _w: String, item: String, c: int, _r: String) -> void:
	counts[item] = int(counts.get(item, 0)) + c


func _on_fell(t: int, id: String, _at: Vector3) -> void:
	falls.append([t, id])


func _load(stage := 7) -> Dictionary:
	level = (load(TARN) as PackedScene).instantiate() as Node3D
	level.set("stage", 0)
	world.add_child(level)
	var p := level.get_node("Player") as GiantPlayer
	p.router.use_injection = true
	await TestWait.until(self, func() -> bool: return p.is_on_floor(), 30)
	TitanDuel.prepare(p, stage)
	var t := level.get_node("Frostbound") as TitanEnemy
	return {"player": p, "titan": t, "ice": level.get_node("Ice") as IceSheet}


func _blow(p: GiantPlayer, t: TitanEnemy, region: String, power: float, from: Vector3, heavy := false) -> void:
	var e := HitEvent.new()
	e.tick = Sim.tick
	e.instance_id = Sim.new_instance_id()
	e.attacker_id = p.entity.entity_id
	e.target_id = t.entity_id
	e.power = power
	e.attacker_stat = 0.0
	e.size_policy = "none"
	e.poise_damage = 1.0
	e.attacker_height_m = float(t.record.height_m)
	e.tags = PackedStringArray(["Melee", "BasicAttack", "Heavy"] if heavy else ["Melee", "BasicAttack", "Light"])
	e.region = region
	e.attacker_position = from
	Sim.queue_hit(e)


func _around(t: TitanEnemy, right: float, ahead: float) -> Vector3:
	var b := t.global_transform.basis
	return t.global_position + b.x * right - b.z * ahead


func _stone(t: TitanEnemy, id: String) -> float:
	return float(t.plates().plate(id).health) * 2.0


func _awake(t: TitanEnemy) -> void:
	t.wake("test")
	await step_ticks(1)
	if t.controller.action != null:
		t.controller.call("_finish_action", true)
	t.ai_enabled = false
	await step_ticks(2)


func test_his_scene_and_record() -> void:
	var rec := GameData.get_record("enemy.frostbound")
	assert_near(float(rec.height_m), 28.0, 1e-6, "92 ft: over a stage-7 giant, under a stage-8")
	assert_true(bool(rec.dormant), "he sleeps")
	var scene := (load("res://scenes/enemies/frostbound.tscn") as PackedScene).instantiate()
	assert_true(scene is TitanEnemy, "a TitanEnemy")
	for n: String in ["Head", "ShoulderL", "ShoulderR", "Back", "Chest", "FistR", "ShinL", "ShinR", "ArmL", "Torso",
			"Legs"]:
		var hb := scene.get_node_or_null("Hurtboxes/" + n) as Node3D
		assert_true(hb != null, "a hurtbox %s" % n)
		if hb != null:
			assert_true(hb.has_meta(TitanEnemy.KNEEL_META), "%s follows the kneel" % n)
	for n: String in ["PlateCrown", "PlateShoulderL", "PlateShoulderR", "PlateBack", "PlateHeart", "PlateFist",
			"PlateShinL", "PlateShinR", "Torso", "KneeL", "KneeR"]:
		assert_true(scene.get_node_or_null("Anchors/" + n) != null, "an anchor %s" % n)
	var head := scene.get_node("Hurtboxes/Head") as Node3D
	assert_true(head.position.y > 23.0, "his crown over a stage-7 giant's head (%.1f m)" % head.position.y)
	var k: Vector3 = head.get_meta(TitanEnemy.KNEEL_META)
	assert_true(k.y < head.position.y - 4.0, "his crown comes down when he kneels (%.1f m)" % k.y)
	scene.free()


func test_he_wakes_rises_and_roars_before_he_strikes() -> void:
	var n := await _load()
	var p: GiantPlayer = n.player
	var t: TitanEnemy = n.titan
	assert_true(t.dormant, "asleep in the ice")
	p.global_position = _around(t, 0.0, 18.0)
	await step_ticks(60)
	assert_true(t.dormant, "still asleep")
	_blow(p, t, "torso", 30.0, p.global_position)
	await step_ticks(2)
	assert_false(t.dormant, "a blow wakes him")
	assert_eq(t.controller.action_id(), "ability.frostbound_wake", "his intro: he rises out of the ice")
	var struck := false
	for i in int(3.5 * 60.0):
		await step_ticks(1)
		var a := t.controller.action
		if a != null and a.id != "ability.frostbound_wake" and a.is_attack():
			struck = true
	assert_false(struck, "no blow until he has risen and roared")


func test_his_breath_rimes_a_giant_before_him_and_not_one_behind() -> void:
	var n := await _load()
	var p: GiantPlayer = n.player
	var t: TitanEnemy = n.titan
	await _awake(t)
	p.global_position = _around(t, 0.0, 20.0)
	await step_ticks(2)
	t.controller.force_action(GameData.get_action("ability.frostbound_breath"))
	await step_ticks(int(3.2 * 60.0))
	assert_true(p.rime.rime > 30.0, "the breath rimed him heavily (%.1f)" % p.rime.rime)
	p.rime.shed_rime(200.0, "test")
	p.global_position = _around(t, 0.0, -18.0)
	await step_ticks(2)
	t.controller.force_action(GameData.get_action("ability.frostbound_breath"))
	await step_ticks(int(3.2 * 60.0))
	assert_true(p.rime.rime < 1.0, "behind him it never reached him (%.1f)" % p.rime.rime)


func test_open_water_takes_him_to_the_knee() -> void:
	var n := await _load()
	var p: GiantPlayer = n.player
	var t: TitanEnemy = n.titan
	var ice: IceSheet = n.ice
	await _awake(t)
	p.global_position = _around(t, 0.0, 60.0)
	var here := ice.cell_of(t.global_position)
	var ahead := _around(t, 0.0, ice.cell_m * 1.2)
	var k := ice.cell_of(ahead)
	assert_true(k >= 0 and k != here, "ice ahead of him")
	ice.weaken(k, 1, "test")
	t.global_position = ahead
	await step_ticks(2)
	assert_eq(ice.state(k), IceSheet.OPEN, "cracked ice gave under his step: open water")
	assert_false(t.is_down(), "he caught himself")
	t.global_position = _around(t, 0.0, ice.cell_m * 1.2)
	ice.break_open(ice.cell_of(t.global_position), "test")
	await step_ticks(3)
	assert_true(t.is_down(), "into open water: down to the knee")
	assert_eq(t.down_plate, "ice", "the ice's down")
	assert_eq(t.ice_falls, 1, "one fall")
	assert_eq(falls.size(), 1, "Events.titan_fell_through")
	await step_ticks(int(t.down_total_s() * 60.0) + 5)
	assert_false(t.is_down(), "he rises")
	t.global_position = _around(t, 0.0, ice.cell_m * 1.2)
	ice.break_open(ice.cell_of(t.global_position), "test")
	await step_ticks(3)
	assert_false(t.is_down(), "not again until his cooldown")


func test_his_second_phase_cold_rimes_a_giant_near_him() -> void:
	var n := await _load()
	var p: GiantPlayer = n.player
	var t: TitanEnemy = n.titan
	await _awake(t)
	p.global_position = _around(t, 0.0, 22.0)
	t.entity.combatant.pools.health = t.entity.combatant.pools.health_max * 0.6
	t.update_boss_phase()
	await step_ticks(2)
	assert_eq(t.brain.boss_phase(), 2, "his second phase")
	var before: float = p.rime.rime
	await step_ticks(120)
	assert_true(t.aura_rime > 0.0, "his cold aura rimed him")
	assert_true(p.rime.rime > before, "rime on the giant near him (%.1f)" % p.rime.rime)


func test_his_serac_unbalances_and_his_greaves_topple_him() -> void:
	var n := await _load()
	var p: GiantPlayer = n.player
	var t: TitanEnemy = n.titan
	await _awake(t)
	var mult := t.plates().poise_taken_mult
	_blow(p, t, "back", _stone(t, "serac"), _around(t, 0.0, -16.0), true)
	await step_ticks(2)
	assert_true(t.plates().is_broken("serac"), "his serac broken")
	assert_true(t.plates().poise_taken_mult > mult, "it unbalances him")
	_blow(p, t, "shin_l", _stone(t, "greave_l"), _around(t, 0.0, 14.0), true)
	await step_ticks(2)
	assert_true(t.is_down(), "a greave broken: down on a knee")


func test_his_death_drops_his_parts() -> void:
	var n := await _load()
	var p: GiantPlayer = n.player
	var t: TitanEnemy = n.titan
	await _awake(t)
	_blow(p, t, "head", _stone(t, "crown"), _around(t, 0.0, 16.0), true)
	await step_ticks(2)
	assert_true(t.plates().is_broken("crown"), "his crown broken")
	t.entity.combatant.pools.health = 10.0
	_blow(p, t, "torso", 8000.0, _around(t, 0.0, 16.0), true)
	await step_ticks(3)
	assert_false(t.entity.is_alive(), "dead")
	assert_eq(int(counts.get("item.frostbound_heart", 0)), 1, "the Heart-ice")
	assert_eq(int(counts.get("item.hoarfrost_shard", 0)), 7, "seven shards")
	assert_eq(int(counts.get("item.cairn_capstone", 0)), 3, "two capstones and the crown's")
