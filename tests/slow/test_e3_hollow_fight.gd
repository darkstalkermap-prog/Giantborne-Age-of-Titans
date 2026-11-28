extends IntegrationSuite
## E3: the Hollow Titan's fight in the Kingsward test arena (scenes/test/hollow_test.tscn): his scene (HollowEnemy,
## 39.6 m, the Stormcaller's hurtboxes carried up, his breastplate's box and the oath-knot's inside it, following the
## kneel; his rig HollowRig), asleep on his vigil until a blow wakes him (his intro: no blow until he has risen and drawn
## his sword); every blow of his telegraphed - the cleave's and the thrust's lines, the reap's and the draw's cones, the
## embrace's and the echo's circles, the lash's circles along the oath-chains from each standing stone; his phases (the
## call wakes his echo, the unbinding throws off his breastplate); his fall drops his parts. And his look in play (with
## the people's layers on): the harness on his bones, the oath-chains drawn to each standing stone, a torn plate drawn
## lying where the sim lays it, his collapse. Scripted blows through the ordinary resolution.

const ARENA := "res://scenes/test/hollow_test.tscn"

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


func _load(stage := 9, layers := false) -> Dictionary:
	if layers:
		PersonRig.enable_for_tests()
	level = (load(ARENA) as PackedScene).instantiate() as Node3D
	level.set("stage", 0)
	world.add_child(level)
	var p := level.get_node("Player") as GiantPlayer
	p.router.use_injection = true
	await TestWait.until(self, func() -> bool: return p.is_on_floor(), 30)
	TitanDuel.prepare(p, stage)
	var t := level.get_node("Hollow") as HollowEnemy
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


func _strike(t: HollowEnemy, p: GiantPlayer, action_id: String, max_ticks := 400) -> void:
	if t.controller.action != null:
		t.controller.call("_finish_action", true)
	t.brain.target_id = p.entity.entity_id
	t.controller.force_action(GameData.get_action(action_id))
	var guard := 0
	while t.controller.action != null and guard < max_ticks:
		await step_ticks(1)
		guard += 1
	await step_ticks(150)


func test_his_scene_his_vigil_and_his_intro() -> void:
	var s := await _load()
	var t: HollowEnemy = s.titan
	var p: GiantPlayer = s.player
	assert_eq(str(t.entity.definition_id), "enemy.hollow", "the Hollow Titan")
	assert_near(float(t.record.height_m), 39.6, 0.01, "39.6 m (130 ft): over a stage-9 giant")
	assert_true(t.get_node("Visual") is HollowRig, "his rig")
	assert_true(t.get_node("Hurtboxes").get_child_count() >= 12, "his plates', breast's, knot's, back's and body's hurtboxes")
	assert_true(t.get_node_or_null("Anchors/PlateKnot") != null, "the knot's lock anchor")
	assert_eq(t.standing_stones().size(), 3, "three oath-stones round the arena")
	assert_true(t.dormant, "on his vigil")
	await _blow(p, t, "shin_l", 10.0)
	await step_ticks(4)
	assert_false(t.dormant, "a blow wakes him")
	assert_eq(t.controller.action_id(), "ability.hollow_wake", "his intro first")


func test_every_blow_of_his_is_telegraphed() -> void:
	var s := await _load()
	var t: HollowEnemy = s.titan
	var p: GiantPlayer = s.player
	t.wake("test")
	await step_ticks(260)
	t.ai_enabled = false
	for pair: Array in [["ability.hollow_cleave", "line"], ["ability.hollow_thrust", "line"], ["ability.hollow_reap", "cone"],
			["ability.hollow_draw", "cone"], ["ability.hollow_embrace", "circle"], ["ability.hollow_echo", "circle"]]:
		telegraphs.clear()
		await _strike(t, p, str(pair[0]))
		var shown := telegraphs.filter(func(x: Array) -> bool: return str(x[2]) == str(pair[0]))
		assert_false(shown.is_empty(), "%s telegraphed" % pair[0])
		if not shown.is_empty():
			assert_eq(str(shown[0][3]), str(pair[1]), "%s: a %s on the ground" % [pair[0], pair[1]])
			assert_true(float(shown[0][5]) >= 0.9, "%s: warned %.1f s ahead" % [pair[0], float(shown[0][5])])
	telegraphs.clear()
	t.ai_enabled = true   # (his chains come down as his brain's hazards: they fall while his AI runs)
	await _strike(t, p, "ability.hollow_lash")
	var lash := telegraphs.filter(func(x: Array) -> bool: return str(x[2]) == "ability.hollow_lash_strike")
	assert_eq(lash.size(), 3 * 4, "the lash: four circles along each of the three oath-chains")
	if not lash.is_empty():
		assert_true(float(lash[0][5]) >= 1.7, "each 1.8 s before it whips down")


func test_his_phases_and_his_fall() -> void:
	var s := await _load()
	var t: HollowEnemy = s.titan
	var p: GiantPlayer = s.player
	t.wake("test")
	await step_ticks(260)
	t.ai_enabled = false
	t.brain.update_boss_phase(0.2, Sim.tick)
	await _strike(t, p, "ability.hollow_unbinding")
	assert_true(t.unbound, "the unbinding")
	assert_true(t.knot_open, "his breastplate thrown off: the knot bare")
	assert_true(t.shards.has("cuirass"), "and lying where it fell")
	t.entity.combatant.pools.health = 1.0
	await _blow(p, t, "knot", 99999.0)
	await step_ticks(10)
	assert_false(t.entity.is_alive(), "he falls")
	assert_eq(int(counts.get("item.oath_knot", 0)), 1, "the Oath-knot")
	assert_true(int(counts.get("item.hollow_gilt", 0)) >= 7, "his gilt-iron")
	assert_true(int(counts.get("item.hollow_crown", 0)) >= 2, "his crown-iron")


func test_his_look_in_play() -> void:
	var s := await _load(9, true)
	var t: HollowEnemy = s.titan
	var p: GiantPlayer = s.player
	var rig := t.get_node("Visual") as HollowRig
	await step_ticks(10)
	assert_true(rig.has_model(), "his model is drawn")
	var m := rig.hollow_model()
	assert_false(m.body.visible, "nothing of the Stormcaller's body: the armour is empty")
	for piece: String in ["helm", "cuirass", "backplate", "pauldron_l", "pauldron_r", "greave_l", "greave_r", "kingsword",
			"knot", "mantle"]:
		assert_true(m.piece(piece) != null and m.piece(piece).visible, "his %s" % piece)
	assert_true(HollowClips.has(m, "dormant") and HollowClips.has(m, "draw") and HollowClips.has(m, "echo"),
		"his own clips")
	assert_eq(rig.current_clip(), "dormant", "on his vigil")
	assert_true(rig.chain_links > 20, "the oath-chains drawn to the stones (%d links)" % rig.chain_links)
	t.wake("test")
	await step_ticks(260)
	t.ai_enabled = false
	t.break_plate("pauldron_l")
	await step_ticks(90)
	assert_false(m.piece("pauldron_l").visible, "the torn plate is off him")
	assert_true(rig.shards_drawn.has("pauldron_l"), "and drawn where it fell")
	var node := rig.shards_drawn["pauldron_l"].node as MeshInstance3D
	var lie := node.global_transform * node.mesh.get_aabb().get_center()
	var sim_at: Vector3 = t.shards["pauldron_l"].p
	assert_true(Vector2(lie.x - sim_at.x, lie.z - sim_at.z).length() < 6.0, "where the sim lays it")
	t.entity.combatant.pools.health = 1.0
	await _blow(p, t, "torso", 99999.0)
	await step_ticks(int((HollowRig.COLLAPSE_FROM_S + 3.0) * 60.0))
	assert_true(rig.collapsed.size() >= 10, "his harness comes apart (%d pieces)" % rig.collapsed.size())
	assert_eq(rig.chain_links, 0, "the chains gone with him")
