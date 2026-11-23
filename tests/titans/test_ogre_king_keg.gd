extends IntegrationSuite
## B4 (the milestone B gate): the Ogre King's keg broken from behind by a bot, as a player breaks it - the chain B2
## made (the keg bursts, he drops to a knee) measured in a real fight, not only by synthetic blows. Two earlier tries
## failed because every blow landed on his front; the gate found why (decision B4-2): an aimed swing that first touched
## anything of him within HitFactory.AIM_SNAP_M (4.5 m, set for Stoneback's 17.7 m) of the lock's point landed there,
## and on the 8.5 m King that is all of him - his torso's centre is 2 m from his keg's point and from his bell's - so a
## swing locked on his keg (or his bell) landed on his torso wherever it first touched him. His record now sets
## aim_snap_m 1.2 (his plates' hurtboxes lie within 0.8 m of their points, his torso's 2 m away), and a swing locked on
## a plate beyond his body from the giant (his keg from his front) is not held back for it.
##   * aim: a stage-3 giant behind him (he stands still), locked on his keg, strikes his back with a light at 3-4.5 m;
##     in front of him, locked on his bell, his belly; locked on his keg from his front, never his back;
##   * the fight: the expert duel bot at stage 3 (the titans' rules, and round to his back in his openings with his keg
##     its back plate - TitanDuelBot.back_plate) breaks the keg from behind and he goes down on his knee (seed 2).
## Its line: B4_KEG (docs/BALANCE_LOG.md, "B4").

const ARENA := "res://scenes/test/boss_arena_test.tscn"


func _setup(stage: int, ai: bool) -> Dictionary:
	await TestWait.duel_start(self)   # (B5: the same duel whatever ran before it)
	WorldState.clear()
	GameSession.expansion = ExpansionState.defaults()
	var level := (load(ARENA) as PackedScene).instantiate() as Node3D
	TestWait.duel_host(world).add_child(level)   # (B5: its own physics space)
	var p := level.get_node("Player") as GiantPlayer
	await TestWait.until(self, func() -> bool: return p.is_on_floor(), 60)
	TitanDuel.prepare(p, stage)
	p.router.use_injection = true
	var t := level.get_node("OgreKing") as TitanEnemy
	t.ai_enabled = ai
	return {"level": level, "player": p, "titan": t}


## One swing (`kind`) of the giant `side` (+1 behind him, -1 before him) `dist` m from his centre, locked on `plate`:
## the region it struck ("" none).
func _swing(n: Dictionary, side: float, dist: float, plate: String, kind: StringName) -> String:
	var p: GiantPlayer = n.player
	var t: TitanEnemy = n.titan
	t.entity.plates.reset()
	var at := t.global_position + t.global_transform.basis.z * side * dist
	p.global_position = Vector3(at.x, t.global_position.y + 0.05, at.z)
	var yaw := TargetingRules.yaw_of(t.global_position - p.global_position)
	p.facing_yaw = yaw
	p.rotation.y = yaw
	p.camera_rig.yaw = yaw
	await step_ticks(3)
	p.targeting.try_lock()
	await step_ticks(2)
	t.lock_choice = plate
	p.entity.combatant.pools.stamina = p.entity.combatant.pools.stamina_max
	hits.clear()
	p.router.inject_edge(kind)
	var got := ""
	for i in 150:
		await step_ticks(1)
		for r in hits:
			if r.event.target_id == t.entity.entity_id and got == "":
				got = str(r.event.region)
		if got != "" and p.controller.state == CombatController.State.LOCOMOTION:
			break
	await TestWait.until(self, func() -> bool: return p.controller.state == CombatController.State.LOCOMOTION, 200)
	return got


func test_a_swing_locked_on_a_trophy_lands_on_it_not_his_torso() -> void:
	var n := await _setup(3, false)
	(n.player as GiantPlayer).entity.apply_status("status.debug_invulnerable", NAN, -1.0, "test")
	assert_eq(await _swing(n, 1.0, 3.0, "keg", &"light"), "back", "behind him at 3 m, locked on his keg: his back")
	assert_eq(await _swing(n, 1.0, 4.5, "keg", &"light"), "back", "at 4.5 m: his back")
	assert_eq(await _swing(n, -1.0, 4.5, "bell", &"light"), "belly", "before him, locked on his bell: his belly")
	assert_eq(await _swing(n, -1.0, 6.0, "bell", &"heavy"), "belly", "a heavy: his belly")
	for d: float in [3.0, 4.5, 6.0]:
		assert_true(await _swing(n, -1.0, d, "keg", &"light") != "back",
			"before him at %.1f m, locked on his keg: never his back through his body" % d)
	(n.level as Node).get_parent().queue_free()
	await step_ticks(2)


func test_the_expert_breaks_his_keg_from_behind_and_he_kneels() -> void:
	var n := await _setup(3, true)
	var p: GiantPlayer = n.player
	var t: TitanEnemy = n.titan
	await TestWait.until(self, func() -> bool: return Sim.tick % 60 == 59, 70)
	Sim.reseed(Sim.DEFAULT_SEED)
	TitanDuel.prepare(p, 3)
	t.brain.rng.seed = 2
	p.global_position = Vector3(0, 0.05, -10)
	(n.level.get_node("BossArena") as BossArena).engage()
	var bot := TitanDuelBot.new()
	bot.round_to_back = true
	bot.back_plate = "keg"
	bot.setup(p, t, "expert", 2, true)
	hits.clear()
	var start := Sim.tick
	var keg_from := ""
	var broke_at := -1
	var knelt := false
	while Sim.tick - start < 240 * 60 and p.entity.is_alive() and t.entity.is_alive():
		bot.step(Sim.tick)
		await step_ticks(1)
		if broke_at < 0 and t.entity.plates.is_broken("keg"):
			broke_at = Sim.tick - start
			var rel := p.global_position - t.global_position
			rel.y = 0.0
			keg_from = "behind" if rel.normalized().dot(t.global_transform.basis.z) > 0.0 else "before"
		knelt = knelt or t.is_down()
		if broke_at >= 0 and knelt:
			break
	bot.teardown()
	print("B4_KEG " + JSON.stringify({"stage": 3, "seed": 2, "keg_broken_s": snappedf(broke_at / 60.0, 0.1),
		"from": keg_from, "knelt": knelt, "topples": t.topples, "broken": t.plate_breaks.duplicate(),
		"king_left": snappedf(t.entity.combatant.pools.ratio("health"), 0.001), "giant_alive": p.entity.is_alive()}))
	assert_true(broke_at >= 0, "the keg is broken in the fight")
	assert_eq(keg_from, "behind", "from behind him")
	assert_true(knelt, "and he goes down on his knee")
	(n.level as Node).get_parent().queue_free()
	await step_ticks(2)
