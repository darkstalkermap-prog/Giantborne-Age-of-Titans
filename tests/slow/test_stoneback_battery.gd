extends IntegrationSuite
## A2: Stoneback's cases that take simulated seconds (tests/integration/test_stoneback.gd keeps the lean ones):
##   * the shoulder charge runs into a rock and he reels (stoneback_reel, 3.5 s) with his back to the giant, who
##     dodged aside - the charge's telegraph first, the reel a wall stop;
##   * the charge tramples the palisades in its way (BreakableProp.trample) and goes on;
##   * circling his flank is answered by the sweep (TitanBrain), and not again before its cooldown;
##   * the capture tour runs every beat headless (each telegraph and strike, both plates, his rage, his death, the
##     loot) with nothing refused.

const QUARRY := "res://scenes/test/quarry_test.tscn"

var level: Node3D


func _load(stage := 5) -> Dictionary:
	level = (load(QUARRY) as PackedScene).instantiate() as Node3D
	level.set("stage", 0)
	world.add_child(level)
	var p := level.get_node("Player") as GiantPlayer
	p.router.use_injection = true
	await TestWait.until(self, func() -> bool: return p.is_on_floor(), 30)
	TitanDuel.prepare(p, stage)
	p.entity.apply_status("status.debug_invulnerable", NAN, 600.0, "test")
	var t := level.get_node("Stoneback") as TitanEnemy
	t.ai_enabled = false
	t.brain.target_id = p.entity.entity_id
	return {"player": p, "titan": t}


func _face(n: Node3D, to: Vector3) -> void:
	var d := to - n.global_position
	var yaw := atan2(-d.x, -d.z)
	n.rotation.y = yaw
	n.set("facing_yaw", yaw)


func test_the_charge_into_a_rock_reels_him_with_his_back_to_the_giant() -> void:
	var n := await _load()
	var p: GiantPlayer = n.player
	var t: TitanEnemy = n.titan
	t.global_position = Vector3(-14, 0.05, -6)
	p.global_position = Vector3(12, 0.05, -6)
	_face(t, Vector3(40, 0, -6))   # RockEast beyond the giant
	# (A3: his brain told where the giant now stands - its charge turns on the brain's point through the windup, and
	# in a run where he had already seen the giant at its start (0, 58) he charged south after that old place)
	t.brain.face_point = Vector3(40, 0, -6)
	t.brain.on_noise(Sim.tick, p.global_position, p.entity.entity_id, true)
	await step_ticks(2)
	t.controller.force_action(GameData.get_action("ability.stoneback_charge"))
	# (the windup - he turns on the giant to its end -, then aside as his rush begins; A3: aside at a fixed 70 ticks,
	# inside the 84-tick windup, let him turn after the giant in some runs)
	await TestWait.until(self, func() -> bool: return t.controller.phase() == ActionDef.Phase.ACTIVE, 120)
	for i in 12:   # (held aside a few ticks: a giant still settling from its growth snaps back otherwise)
		p.global_position = Vector3(12, 0.05, 14)
		p.velocity = Vector3.ZERO
		await step_ticks(1)
	await TestWait.until(self, func() -> bool: return t.controller.action_id() == "ability.stoneback_reel", 300)
	assert_eq(t.controller.action_id(), "ability.stoneback_reel", "the rock stops him: he reels")
	assert_eq(t.wall_stops, 1, "a wall stop")
	assert_true(t.global_position.x > 20.0, "he ran the line to the rock (x %.1f)" % t.global_position.x)
	assert_true(bool(t.get_rig_state().get("reeling", false)), "the rig is told he reels")
	var to_p := p.global_position - t.global_position
	to_p.y = 0.0
	var fwd := -t.global_transform.basis.z
	assert_true(rad_to_deg(Vector3(fwd.x, 0, fwd.z).angle_to(to_p)) > 90.0, "his back is to the giant")
	var reel := GameData.get_action("ability.stoneback_reel")
	assert_near(float(reel.windup_ticks + reel.active_ticks + reel.recovery_ticks) / 60.0, 3.5, 0.02, "3.5 s of it")
	assert_true(hits_on(p.entity.entity_id).is_empty(), "the giant was not in the line")


func test_the_charge_tramples_the_palisades_in_its_way() -> void:
	var n := await _load()
	var p: GiantPlayer = n.player
	var t: TitanEnemy = n.titan
	var palisade := level.get_node("Props/Palisade3") as BreakableProp
	assert_true(palisade != null and not palisade.destroyed, "a palisade stands at (0, 10)")
	t.global_position = Vector3(0, 0.05, -20)
	p.global_position = Vector3(0, 0.05, 30)
	_face(t, Vector3(0, 0, 30))
	await step_ticks(2)
	t.controller.force_action(GameData.get_action("ability.stoneback_charge"))
	await TestWait.until(self, func() -> bool: return palisade.destroyed, 300)
	assert_true(palisade.destroyed, "trampled")
	assert_true(t.props_smashed >= 1, "his charge broke it")
	assert_true(destroyed.has("test.quarry.palisade_3"), "Events.object_destroyed")
	await step_ticks(30)
	assert_true(t.global_position.z > 12.0, "and he ran on through it (z %.1f)" % t.global_position.z)


func test_circling_his_flank_is_answered_by_the_sweep_then_cooldown() -> void:
	var n := await _load()
	var p: GiantPlayer = n.player
	var t: TitanEnemy = n.titan
	t.ai_enabled = true
	(level.get_node("BossArena") as BossArena).engage()
	t.global_position = Vector3(0, 0.05, -20)
	_face(t, Vector3(0, 0, 20))
	var tb := t.brain as TitanBrain
	tb.sequence_index = 2   # (the boulder next: the sequence's own sweep is not the one counted)
	# on his right flank, 11 m out, kept there
	var started := []
	var watch := func(_tk: int, actor: String, action: String, _i: int) -> void:
		if actor == t.entity_id:
			started.append(action)
	Events.ability_started.connect(watch)
	for i in 60 * 6:
		var right := t.global_transform.basis.x
		p.global_position = t.global_position + Vector3(right.x, 0, right.z).normalized() * 11.0 + Vector3(0, 0.05, 0)
		await step_ticks(1)
		if tb.flank_answers > 0:
			break
	Events.ability_started.disconnect(watch)
	assert_eq(tb.flank_answers, 1, "the sweep answered the flank (%s)" % [started])
	assert_true(started.has("ability.stoneback_sweep"), "his sweep")
	assert_true(tb.sequence_log.has("flank:ability.stoneback_sweep"), "logged as the answer")
	var at := tb.now
	await step_ticks(60 * 3)
	assert_true(tb.flank_answers == 1 or tb.now - at >= int(TitanBrain.FLANK_COOLDOWN_S * 60), "not again at once")


func test_the_capture_tour_runs_every_beat() -> void:
	level = (load(QUARRY) as PackedScene).instantiate() as Node3D
	level.set("stage", 0)
	world.add_child(level)
	var p := level.get_node("Player") as GiantPlayer
	await TestWait.until(self, func() -> bool: return p.is_on_floor(), 30)
	var tour := CaptureTitan.new(null)
	var guard := 0
	while not tour.step(p, 1.0 / 60.0) and guard < 60 * 90:
		await step_ticks(1)
		guard += 1
	var r := tour.result()
	assert_true(bool(r.complete), "the tour ended")
	assert_true((r.notes as PackedStringArray).is_empty(), "nothing refused (%s)" % [r.notes])
	assert_true((r.shots as Array).size() >= 12, "%d moments" % (r.shots as Array).size())
	var seen: Dictionary = r.seen
	assert_eq(seen.plates, ["back", "shoulder_l", "brow"], "three plates broke (A4: his rage after three)")
	assert_eq(seen.phases, [2], "his rage")
	assert_eq(int(seen.reels), 2, "the charge's reel, and the reel the plate breaks in")
	assert_true(bool(seen.died), "his death")
	for id: String in ["ability.stoneback_smash", "ability.stoneback_sweep", "ability.stoneback_boulder",
			"ability.stoneback_charge", "ability.stoneback_roar", "ability.stoneback_smash_rage", "ability.stoneback_sweep_rage"]:
		assert_true((seen.strikes as Array).has(id), "%s struck" % id)
	assert_true((seen.loot as Array).size() >= 3, "his loot (%s)" % [seen.loot])
	tour.dispose()
