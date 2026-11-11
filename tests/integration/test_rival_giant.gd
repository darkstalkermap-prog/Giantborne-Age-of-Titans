extends IntegrationSuite
## Rival giants (plan M6-M9 §2.10, §3.18; P34): the axe combo is a weapon arc through AttackRunner that
## hits the giant in front; the boulder is a lob whose landing circle is committed at the giant's feet
## when its windup begins; rival giants are never grabbable and their lobs do not set the archers'
## launch gaps. (The shoulder charge ending against stone: the slow battery, tests/slow/test_big_battery.)

const RIVAL := "res://scenes/enemies/rival_giant.tscn"


func _rival(pos: Vector3, yaw := 0.0) -> RivalGiantEnemy:
	var g := (load(RIVAL) as PackedScene).instantiate() as RivalGiantEnemy
	g.entity_id = "test.rival_1"
	g.ai_enabled = false
	g.position = pos
	g.rotation.y = yaw
	world.add_child(g)
	return g


func test_the_axe_sweeps_as_a_weapon_arc() -> void:
	var p := spawn_player(Vector3(0, 0.05, -6), PI)
	var g := _rival(Vector3(0, 0.05, 0))
	await step_ticks(2)
	assert_false(g.can_be_grabbed(), "a rival giant is never grabbable")
	assert_true(g.brain is RivalGiantBrain and not (g.brain is HarrokBrain), "a plain rival giant's brain")
	var a := GameData.get_action("ability.giant_axe_combo_1")
	assert_eq(a.hit_shape, "weapon_arc", "the combo is a weapon arc")
	g.brain.target_id = p.entity.entity_id
	g.controller.force_action(a)
	var hit := await TestWait.until(self, func() -> bool: return not hits_on(p.entity.entity_id).is_empty(),
		a.windup_ticks + a.active_ticks + 4)
	assert_true(hit, "the sweep hits the giant in front")
	var r: HitResult = hits_on(p.entity.entity_id)[0]
	assert_eq(r.event.attacker_id, "test.rival_1", "the rival's hit")
	assert_eq(r.event.action_id, "ability.giant_axe_combo_1", "with the combo")
	assert_eq(EnemyActor.max_ranged_windup_ticks(), 60, "the giants' and trolls' lobs leave the launch gaps alone")
	# The boulder lands where its circle was committed.
	p.global_position = Vector3(0, 0.05, -30)
	await step_ticks(1)
	var circles: Array = []
	var on_tel := func(_t: int, actor_id: String, action_id: String, _tg: String, shape: String, origin: Vector3,
			_y: float, radius: float, _l: float, _d: float) -> void:
		if actor_id == g.entity_id:
			circles.append([action_id, shape, origin, radius])
	Events.telegraph_started.connect(on_tel)
	g.brain.target_id = p.entity.entity_id
	var boulder := GameData.get_action("ability.giant_boulder")
	assert_true(bool(boulder.param("indirect", false)), "the boulder is indirect")
	g.controller.force_action(boulder)
	await step_ticks(1)
	Events.telegraph_started.disconnect(on_tel)
	assert_eq(circles.size(), 1, "one telegraph")
	assert_eq(str(circles[0][1]), "circle", "a circle")
	assert_true(Vector2((circles[0][2] as Vector3).x - p.global_position.x, (circles[0][2] as Vector3).z - p.global_position.z).length() < 0.5,
		"at the giant's feet, not round the thrower")
	assert_near(float(circles[0][3]), 5.0, 0.01, "5 m")
	assert_true(g.runner.aim_point.distance_to(circles[0][2]) < 0.01, "the throw aims at the committed point")
	assert_true(boulder.windup_ticks >= 48, "a windup of 0.8 s or more is telegraphed")
