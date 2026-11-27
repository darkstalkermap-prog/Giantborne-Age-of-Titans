extends IntegrationSuite
## D2: the Stormcaller's fight in the flooded steps test arena (scenes/test/stormcaller_test.tscn): his scene
## (TitanEnemy, his bronze's hurtboxes and anchors following the kneel), asleep until a blow wakes him (his wake action:
## no blow until he has raised the rod and roared); his call brings bolts down round the giant, each telegraphed before
## it strikes; a bolt on the water shocks a giant standing in it - by how deep it stands - and not one on dry ground;
## standing deep in the water himself, his own lightning grounds him (a down, Events.titan_grounded), not again until
## his cooldown; his gale throws a smaller giant further; his bell's fall unbalances him, his greaves topple him; his
## death drops his parts. Scripted blows through the ordinary resolution.

const STEPS := "res://scenes/test/stormcaller_test.tscn"
## The deep pool's middle and a dry spot (the arena's pools: titans.gd STEPS_POOLS).
const DEEP := Vector3(-38, 0.05, 2)
const SHALLOW := Vector3(42, 0.05, -12)
const DRY := Vector3(40, 0.05, 50)

var level: Node3D
var counts := {}
var grounded: Array = []
var shocks: Array = []
var telegraphs: Array = []


func before_each() -> void:
	await super()
	counts.clear()
	grounded.clear()
	shocks.clear()
	telegraphs.clear()
	WorldState.clear()
	Events.loot_awarded.connect(_on_loot_count)
	Events.titan_grounded.connect(_on_grounded)
	Events.storm_shock.connect(_on_shock)
	Events.telegraph_started.connect(_on_telegraph)


func after_each() -> void:
	for sig: Signal in [Events.loot_awarded, Events.titan_grounded, Events.storm_shock, Events.telegraph_started]:
		for c: Dictionary in sig.get_connections():
			if (c.callable as Callable).get_object() == self:
				sig.disconnect(c.callable)
	PersonRig.reset_for_tests()
	await super()


func _on_loot_count(_t: int, _w: String, item: String, c: int, _r: String) -> void:
	counts[item] = int(counts.get(item, 0)) + c


func _on_grounded(t: int, id: String, _at: Vector3) -> void:
	grounded.append([t, id])


func _on_shock(t: int, _id: String, at: Vector3, _r: float, hits: int) -> void:
	shocks.append([t, at, hits])


func _on_telegraph(t: int, key: String, action_id: String, _target: String, _shape: String, origin: Vector3,
		_yaw: float, _radius: float, _length: float, duration: float) -> void:
	telegraphs.append([t, key, action_id, origin, duration])


func _load(stage := 8) -> Dictionary:
	level = (load(STEPS) as PackedScene).instantiate() as Node3D
	level.set("stage", 0)
	world.add_child(level)
	var p := level.get_node("Player") as GiantPlayer
	p.router.use_injection = true
	await TestWait.until(self, func() -> bool: return p.is_on_floor(), 30)
	TitanDuel.prepare(p, stage)
	var t := level.get_node("Stormcaller") as TitanEnemy
	return {"player": p, "titan": t}


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


## Puts the giant at `at` (on the floor) and lets PlayerStorm read its water.
func _place(p: GiantPlayer, at: Vector3) -> void:
	p.global_position = at
	p.velocity = Vector3.ZERO
	await step_ticks(3)


func test_his_scene_and_record() -> void:
	var rec := GameData.get_record("enemy.stormcaller")
	assert_near(float(rec.height_m), 34.0, 1e-6, "111.5 ft: over a stage-8 giant (29.3 m), under stage 9 (35.4 m)")
	assert_true(bool(rec.dormant), "he waits in the storm")
	assert_false((rec.get("storm", {}) as Dictionary).is_empty(), "his storm")
	var scene := (load("res://scenes/enemies/stormcaller.tscn") as PackedScene).instantiate()
	assert_true(scene is TitanEnemy, "a TitanEnemy")
	for n: String in ["Head", "ShoulderL", "ShoulderR", "Back", "Chest", "BracerR", "ShinL", "ShinR", "ArmL", "Torso",
			"Legs"]:
		var hb := scene.get_node_or_null("Hurtboxes/" + n) as Node3D
		assert_true(hb != null, "a hurtbox %s" % n)
		if hb != null:
			assert_true(hb.has_meta(TitanEnemy.KNEEL_META), "%s follows the kneel" % n)
	for n: String in ["PlateCrown", "PlateShoulderL", "PlateShoulderR", "PlateBack", "PlateLodestone", "PlateBracer",
			"PlateShinL", "PlateShinR", "Torso", "KneeL", "KneeR"]:
		assert_true(scene.get_node_or_null("Anchors/" + n) != null, "an anchor %s" % n)
	var head := scene.get_node("Hurtboxes/Head") as Node3D
	assert_true(head.position.y > 29.3, "his crown over a stage-8 giant's head (%.1f m)" % head.position.y)
	var k: Vector3 = head.get_meta(TitanEnemy.KNEEL_META)
	assert_true(k.y < head.position.y - 5.0, "his crown comes down when he kneels (%.1f m)" % k.y)
	scene.free()


func test_he_wakes_raises_the_rod_and_roars_before_he_strikes() -> void:
	var n := await _load()
	var p: GiantPlayer = n.player
	var t: TitanEnemy = n.titan
	assert_true(t.dormant, "waiting in the storm")
	p.global_position = _around(t, 0.0, 24.0)
	await step_ticks(60)
	assert_true(t.dormant, "still waiting")
	_blow(p, t, "torso", 30.0, p.global_position)
	await step_ticks(2)
	assert_false(t.dormant, "a blow wakes him")
	assert_eq(t.controller.action_id(), "ability.stormcaller_wake", "his intro")
	var struck := false
	for i in int(3.6 * 60.0):
		await step_ticks(1)
		var a := t.controller.action
		if a != null and a.id != "ability.stormcaller_wake" and a.is_attack():
			struck = true
	assert_false(struck, "no blow until he has raised the rod and roared")


func test_his_call_telegraphs_each_bolt_before_it_strikes() -> void:
	var n := await _load()
	var p: GiantPlayer = n.player
	var t: TitanEnemy = n.titan
	await _awake(t)
	await _place(p, DRY)
	t.brain.target_id = p.entity.entity_id
	# (his brain keeps and strikes his hazards while his AI is on: his bolts come down as in a fight)
	t.ai_enabled = true
	t.controller.force_action(GameData.get_action("ability.stormcaller_call"))
	await step_ticks(int(1.4 * 60.0))
	var bolts := telegraphs.filter(func(x: Array) -> bool: return str(x[2]) == "ability.stormcaller_bolt")
	assert_eq(bolts.size(), 3, "three bolts called, each a telegraph")
	for b: Array in bolts:
		assert_true(float(b[4]) >= 1.6, "telegraphed at least 1.6 s before it strikes (%.2f)" % float(b[4]))
	var first: Vector3 = (bolts[0] as Array)[3]
	assert_true(Vector2(first.x - p.global_position.x, first.z - p.global_position.z).length() < 12.0,
		"the first where the giant stands")
	assert_eq(t.bolts_called, 3, "his count")
	hits.clear()
	await step_ticks(int(3.0 * 60.0))
	var struck := hits.filter(func(r: HitResult) -> bool:
		return r.event.action_id == "ability.stormcaller_bolt" and r.event.target_id == p.entity.entity_id)
	assert_true(struck.size() >= 1, "a bolt it stood under struck it")
	assert_eq(t.bolts_in_water, 0, "on dry ground no shock runs")


func test_a_bolt_on_the_water_shocks_the_giant_in_it_by_its_depth_and_not_on_dry_ground() -> void:
	var n := await _load(7)
	var p: GiantPlayer = n.player
	var t: TitanEnemy = n.titan
	await _awake(t)
	t.global_position = Vector3(0, 0.05, -70)   # (dry: not grounded)
	await _place(p, DEEP + Vector3(6, 0, 0))
	assert_true(p.storm.in_water(), "the giant stands in the deep pool")
	var wet7: float = p.storm.wet
	var hp := p.entity.combatant.pools.health
	t.storm_strike(DEEP + Vector3(-14, 0, 0), Sim.tick)
	await step_ticks(3)
	var lost7 := hp - p.entity.combatant.pools.health
	assert_true(lost7 > 0.0, "the shock ran through the water to it (%.0f)" % lost7)
	assert_eq(p.storm.shocks, 1, "one shock")
	assert_eq(shocks.size(), 1, "Events.storm_shock")
	await _place(p, DRY)
	hp = p.entity.combatant.pools.health
	t.storm_strike(DEEP + Vector3(-14, 0, 0), Sim.tick)
	await step_ticks(3)
	assert_eq(p.entity.combatant.pools.health, hp, "on dry ground it takes none")
	# the same pool, a bigger body: less of it under water, much less of the shock
	TitanDuel.prepare(p, 8)
	await _place(p, DEEP + Vector3(6, 0, 0))
	assert_true(p.storm.wet < wet7, "a stage-8 giant stands higher out of the same pool (%.3f < %.3f)" % [p.storm.wet,
		wet7])
	assert_true(PlayerStorm.shock_scale(p.storm.wet) < PlayerStorm.shock_scale(wet7) * 0.8,
		"and takes much less of the shock")


func test_standing_deep_in_the_water_his_own_lightning_grounds_him() -> void:
	var n := await _load()
	var p: GiantPlayer = n.player
	var t: TitanEnemy = n.titan
	await _awake(t)
	await _place(p, DRY)
	t.global_position = DEEP
	await step_ticks(3)
	assert_true(t.storm_depth() >= float(t.storm.ground_depth_m), "he stands deep in the pool (%.1f m)" % t.storm_depth())
	t.storm_strike(DEEP + Vector3(12, 0, 6), Sim.tick)
	await step_ticks(3)
	assert_true(t.is_down(), "grounded: down on a knee")
	assert_eq(t.down_plate, "storm", "the storm's down")
	assert_eq(t.grounds, 1, "one grounding")
	assert_eq(grounded.size(), 1, "Events.titan_grounded")
	await step_ticks(int(t.down_total_s() * 60.0) + 5)
	assert_false(t.is_down(), "he rises")
	t.storm_strike(DEEP + Vector3(12, 0, 6), Sim.tick)
	await step_ticks(3)
	assert_false(t.is_down(), "not again until his cooldown")
	# on dry ground, a bolt in the water near him does not ground him
	t.global_position = Vector3(0, 0.05, -70)
	await step_ticks(int(float(t.storm.cooldown_s) * 60.0) + 10)
	t.storm_strike(DEEP + Vector3(12, 0, 6), Sim.tick)
	await step_ticks(3)
	assert_false(t.is_down(), "dry, he is not grounded")


func test_his_gale_throws_a_smaller_giant_further() -> void:
	var far := {}
	for stage: int in [7, 8]:
		var n := await _load(stage)
		var p: GiantPlayer = n.player
		var t: TitanEnemy = n.titan
		await _awake(t)
		t.global_position = Vector3(0, 0.05, -40)
		t.rotation.y = PI
		await _place(p, Vector3(0, 0.05, -10))
		var from := p.global_position
		t.brain.target_id = p.entity.entity_id
		t.controller.force_action(GameData.get_action("ability.stormcaller_gust"))
		await step_ticks(int(2.4 * 60.0))
		far[stage] = Vector2(p.global_position.x - from.x, p.global_position.z - from.z).length()
		assert_true(float(far[stage]) > 1.0, "stage %d: the gale moved it (%.1f m)" % [stage, float(far[stage])])
		level.queue_free()
		await step_ticks(3)
	assert_true(float(far[7]) > float(far[8]), "a stage-7 giant is thrown further than a stage-8 (%.1f > %.1f m)" % [
		float(far[7]), float(far[8])])


func test_his_bell_unbalances_and_his_greaves_topple_him() -> void:
	var n := await _load()
	var p: GiantPlayer = n.player
	var t: TitanEnemy = n.titan
	await _awake(t)
	var mult := t.plates().poise_taken_mult
	_blow(p, t, "back", _stone(t, "bell"), _around(t, 0.0, -18.0), true)
	await step_ticks(2)
	assert_true(t.plates().is_broken("bell"), "his bell broken off")
	assert_true(t.plates().poise_taken_mult > mult, "it unbalances him")
	_blow(p, t, "shin_l", _stone(t, "greave_l"), _around(t, 0.0, 16.0), true)
	await step_ticks(2)
	assert_true(t.is_down(), "a greave broken: down on a knee")


func test_his_death_drops_his_parts() -> void:
	var n := await _load()
	var p: GiantPlayer = n.player
	var t: TitanEnemy = n.titan
	await _awake(t)
	_blow(p, t, "head", _stone(t, "crown"), _around(t, 0.0, 18.0), true)
	await step_ticks(2)
	assert_true(t.plates().is_broken("crown"), "his crown broken")
	t.entity.combatant.pools.health = 10.0
	_blow(p, t, "torso", 8000.0, _around(t, 0.0, 18.0), true)
	await step_ticks(3)
	assert_false(t.entity.is_alive(), "dead")
	assert_eq(int(counts.get("item.stormcaller_lodestone", 0)), 1, "the Lodestone")
	assert_eq(int(counts.get("item.drowned_bronze", 0)), 7, "seven plates of drowned bronze")
	assert_eq(int(counts.get("item.storm_tine", 0)), 3, "two tines and the crown's")
