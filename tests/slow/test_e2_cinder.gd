extends IntegrationSuite
## E2: the Cinder Titan's fight in the burnt hollow test arena (scenes/test/cinder_test.tscn): his scene (CinderEnemy,
## 41.0 m, the Stormcaller's hurtboxes carried up, following the kneel; his rig CinderRig), asleep until a blow wakes
## him (his intro: no blow until he has raised the brand and roared); every heavy blow of his telegraphed - the
## brand-slam's line, the sweep's and the blast's cones, the stamp's circle - and each lays its burning ground where it
## strikes; his embers fall in telegraphed circles and burn where they land; his roar (the second phase) melts a
## quenched crust; his last phase's ground burns until he falls; his fall puts every fire out and drops his parts.
## Scripted blows through the ordinary resolution.

const ARENA := "res://scenes/test/cinder_test.tscn"

var level: Node3D
var counts := {}
var telegraphs: Array = []


func before_each() -> void:
	await super()
	counts.clear()
	telegraphs.clear()
	WorldState.clear()
	Events.loot_awarded.connect(_on_loot_count)
	Events.telegraph_started.connect(_on_telegraph)


func after_each() -> void:
	for sig: Signal in [Events.loot_awarded, Events.telegraph_started]:
		for c: Dictionary in sig.get_connections():
			if (c.callable as Callable).get_object() == self:
				sig.disconnect(c.callable)
	PersonRig.reset_for_tests()
	await super()


func _on_loot_count(_t: int, _w: String, item: String, c: int, _r: String) -> void:
	counts[item] = int(counts.get(item, 0)) + c


func _on_telegraph(t: int, key: String, action_id: String, _target: String, shape: String, origin: Vector3,
		_yaw: float, _radius: float, _length: float, duration: float) -> void:
	telegraphs.append([t, key, action_id, shape, origin, duration])


func _load(stage := 9) -> Dictionary:
	level = (load(ARENA) as PackedScene).instantiate() as Node3D
	level.set("stage", 0)
	world.add_child(level)
	var p := level.get_node("Player") as GiantPlayer
	p.router.use_injection = true
	await TestWait.until(self, func() -> bool: return p.is_on_floor(), 30)
	TitanDuel.prepare(p, stage)
	var t := level.get_node("Cinder") as CinderEnemy
	return {"player": p, "titan": t}


func _blow(p: GiantPlayer, t: TitanEnemy, region: String, power: float) -> void:
	var e := HitEvent.new()
	e.tick = Sim.tick
	e.instance_id = Sim.new_instance_id()
	e.attacker_id = p.entity.entity_id
	e.target_id = t.entity_id
	e.action_id = "ability.light_1"
	e.power = power
	e.damage_split = {"physical": 1.0}
	e.category = "melee"
	e.region = region
	e.attacker_position = p.global_position
	e.hit_point = t.global_position + Vector3.UP * 20.0
	Sim.queue_hit(e)
	await step_ticks(2)


func _strike(t: CinderEnemy, p: GiantPlayer, action_id: String, max_ticks := 400) -> void:
	if t.controller.action != null:
		t.controller.call("_finish_action", true)
	t.brain.target_id = p.entity.entity_id
	t.controller.force_action(GameData.get_action(action_id))
	var guard := 0
	while t.controller.action != null and guard < max_ticks:
		await step_ticks(1)
		guard += 1
	await step_ticks(150)


func test_his_scene_his_sleep_and_his_intro() -> void:
	var s := await _load()
	var t: CinderEnemy = s.titan
	var p: GiantPlayer = s.player
	assert_eq(str(t.entity.definition_id), "enemy.cinder", "the Cinder Titan")
	assert_near(float(t.record.height_m), 41.0, 0.01, "41.0 m (134.5 ft): over a stage-9 giant")
	assert_true(t.get_node("Visual") is CinderRig, "his rig")
	assert_true(t.get_node("Hurtboxes").get_child_count() >= 11, "his plates', back's and body's hurtboxes")
	assert_true(t.dormant, "asleep where he stopped")
	await _blow(p, t, "shin_l", 10.0)
	await step_ticks(4)
	assert_false(t.dormant, "a blow wakes him")
	assert_eq(t.controller.action_id(), "ability.cinder_wake", "his intro first")


func test_his_blows_are_telegraphed_and_burn_where_they_strike() -> void:
	var s := await _load()
	var t: CinderEnemy = s.titan
	var p: GiantPlayer = s.player
	t.wake("test")
	await step_ticks(260)
	t.ai_enabled = false
	for pair: Array in [["ability.cinder_slam", "line"], ["ability.cinder_sweep", "cone"], ["ability.cinder_blast", "cone"],
			["ability.cinder_stamp", "circle"]]:
		telegraphs.clear()
		var laid := t.patches_laid
		await _strike(t, p, str(pair[0]))
		var shown := telegraphs.filter(func(x: Array) -> bool: return str(x[2]) == str(pair[0]))
		assert_false(shown.is_empty(), "%s telegraphed" % pair[0])
		if not shown.is_empty():
			assert_eq(str(shown[0][3]), str(pair[1]), "%s: a %s on the ground" % [pair[0], pair[1]])
		if str(pair[0]) != "ability.cinder_stamp":
			assert_true(t.patches_laid > laid, "%s burns the ground it strikes (%d)" % [pair[0], t.patches_laid - laid])
	telegraphs.clear()
	var laid := t.patches_laid
	t.ai_enabled = true   # (his called fire comes down as his brain's hazards: they fall while his AI runs)
	await _strike(t, p, "ability.cinder_embers")
	var embers := telegraphs.filter(func(x: Array) -> bool: return str(x[2]) == "ability.cinder_ember")
	assert_eq(embers.size(), 4, "the ember-rain: four circles on the ground")
	if not embers.is_empty():
		assert_true(float(embers[0][5]) >= 2.0, "each 2 s or more before it falls")
	assert_true(t.patches_laid >= laid + 3, "and the ground burns where they fall (%d)" % (t.patches_laid - laid))


func test_his_phases_his_fire_and_his_fall() -> void:
	var s := await _load()
	var t: CinderEnemy = s.titan
	var p: GiantPlayer = s.player
	t.wake("test")
	await step_ticks(260)
	t.quench(false)
	assert_true(t.is_quenched(), "quenched")
	t.ai_enabled = false
	await _strike(t, p, "ability.cinder_roar")
	assert_false(t.is_quenched(), "his roar melts the crust at once")
	# his last phase: the ground burns until he falls
	t.brain.update_boss_phase(0.2, Sim.tick)
	await step_ticks(2)
	t.lay_burn(t.global_position + Vector3(0, 0, 30), 6.0, 5.0)
	assert_eq(int((t.patches.back() as Dictionary).until), -1, "the last phase's fire does not go out by itself")
	assert_false(t.patches.is_empty(), "his ground burns")
	t.entity.combatant.pools.health = 1.0
	await _blow(p, t, "torso", 99999.0)
	await step_ticks(10)
	assert_false(t.entity.is_alive(), "he falls")
	assert_true(t.patches.is_empty(), "every fire of his goes out")
	assert_eq(int(counts.get("item.cinder_heart", 0)), 1, "the Heart-coal")
	assert_true(int(counts.get("item.cinder_slag", 0)) >= 7, "his quenched crust")
	assert_true(int(counts.get("item.cinder_horn", 0)) >= 2, "his crown's horns")
