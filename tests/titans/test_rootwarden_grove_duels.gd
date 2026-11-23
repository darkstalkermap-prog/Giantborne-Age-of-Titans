extends IntegrationSuite
## B4 (the milestone B gate; B3's FOLLOWUPS row "the duels are on the grove test arena's flat floor"): the Rootwarden's
## duels once in his real grove (scenes/world/world.tscn, deterministic streaming, the deep Greywood): the woodfolk's
## call set, a giant readied for stage 5 and for stage 6 (TitanDuel.prepare) walks into his hollow from the root arch's
## side, which wakes him (his territory engages), and TitanDuelBot fights him as in the arena (the titans' rules: his
## knot first, his shins, the grove's braziers and resin pots, his telegraphs). One attempt each, no respawn. Every duel
## is printed as one B4_GROVE line (docs/BALANCE_LOG.md, "B4").
## What the real grove must not change (the arena's numbers are B3's balance; the grove adds its trunks, its dead
## trees, its slope and its pool): he wakes and fights; he never leaves his territory (110 + 20 m of his grove) nor
## falls through the ground; the giant neither; nothing of the fight errs; the fire is found; the fight ends in the
## arena's band (stage 5: a hard fight - his bark broken, his blows landing; stage 6: his knot broken and him uprooted,
## or him at rest).

const SCENE := "res://scenes/world/world.tscn"
const GROVE := Vector2(-790.0, 200.0)
const ENTER := Vector2(-770.0, 208.0)
## His territory's hunting line (TitanTerritory: 110 m and the 20 m margin) from his grove's centre.
const TERRITORY_M := 130.0


func after_each() -> void:
	get_tree().paused = false
	for f in Formation.live():
		f.dissolve()
	FactionState.reset_for_tests()
	WanderDirector.reset_for_tests()
	GameSession.expansion = ExpansionState.defaults()
	await super()


func _warden() -> TitanEnemy:
	for n in get_tree().root.find_children("*", "TitanEnemy", true, false):
		var t := n as TitanEnemy
		if t.entity != null and t.entity.definition_id == "enemy.rootwarden":
			return t
	return null


func _duel(stage: int, seed_value: int, max_s: float) -> Dictionary:
	WorldState.clear()
	GameSession.start_world_for_tests("world.cp.hollowmere")
	GameSession.level_id = GameSession.WORLD_LEVEL_ID
	var w := (load(SCENE) as PackedScene).instantiate() as WorldRoot
	world.add_child(w)
	w.streamer.deterministic = true
	var p := w.player()
	p.router.use_injection = true
	GameSession.on_level_ready(w, p)
	WorldState.try_set_flag("world.rootwarden.called", true)
	WorldState.try_set_flag("world.rootwarden.resin_laid", true)
	var at := Vector3(ENTER.x, 200.0, ENTER.y)
	p.process_mode = Node.PROCESS_MODE_DISABLED
	p.global_position = at
	var guard := 0
	while not w.streamer.ring_ready(at) and guard < 900:
		w.streamer.load_ring_slice(at)
		await step_ticks(1)
		guard += 1
	p.global_position = Vector3(at.x, w.height_at(at) + 0.3, at.z)
	p.velocity = Vector3.ZERO
	p.process_mode = Node.PROCESS_MODE_INHERIT
	TitanDuel.prepare(p, stage)
	await step_ticks(30)
	var t := _warden()
	assert_true(t != null, "stage %d: he is in his grove" % stage)
	if t == null:
		w.queue_free()
		await step_ticks(2)
		return {}
	t.brain.rng.seed = seed_value
	var bot := TitanDuelBot.new()
	bot.setup(p, t, "expert", seed_value, true)
	hits.clear()
	var start := Sim.tick
	var limit := int(max_s * Sim.TICK_RATE)
	var giant_hp := p.entity.combatant.pools.health_max
	var died_at := -1
	var killed_at := -1
	var far_m := 0.0
	var sank_m := 0.0
	var giant_sank_m := 0.0
	var home := Vector2(t.global_position.x, t.global_position.z)
	while Sim.tick - start < limit:
		bot.step(Sim.tick)
		await step_ticks(1)
		if (Sim.tick - start) % 30 == 0:
			far_m = maxf(far_m, Vector2(t.global_position.x, t.global_position.z).distance_to(GROVE))
			var g := w.height_at(t.global_position)
			if not is_nan(g):
				sank_m = maxf(sank_m, g - t.global_position.y)
			var gp := w.height_at(p.global_position)
			if not is_nan(gp):
				giant_sank_m = maxf(giant_sank_m, gp - p.global_position.y)
		if not p.entity.is_alive():
			died_at = Sim.tick - start
			break
		if not t.entity.is_alive():
			killed_at = Sim.tick - start
			break
	bot.teardown()
	var blows := 0
	var dealt := 0
	var by_action := {}
	for r in hits:
		if r.event.target_id == p.entity.entity_id and r.health_damage > 0:
			blows += 1
			var k := r.event.action_id.trim_prefix("ability.rootwarden_")
			by_action[k] = int(by_action.get(k, 0)) + r.health_damage
		elif r.event.target_id == t.entity_id and r.health_damage > 0:
			dealt += r.health_damage
	var out := {"stage": stage, "seed": seed_value, "giant_health": giant_hp, "woke": t.wake_reason,
		"giant_died_s": snappedf(died_at / 60.0, 0.1) if died_at >= 0 else -1.0,
		"titan_killed_s": snappedf(killed_at / 60.0, 0.1) if killed_at >= 0 else -1.0,
		"blows_taken": blows, "titan_left": snappedf(t.entity.combatant.pools.ratio("health"), 0.001),
		"plates": Array(t.plates().ever_broken), "fires": t.fire_ignitions, "phase": t.brain.boss_phase(),
		"topples": t.topples, "dealt": dealt, "hit_by": by_action, "evade_s": snappedf(bot.evade_ticks / 60.0, 0.1), "fire_s": snappedf(bot.fire_ticks / 60.0, 0.1),
		"home_m": snappedf(home.distance_to(GROVE), 0.1), "farthest_m": snappedf(far_m, 0.1),
		"sank_m": snappedf(sank_m, 0.01), "giant_sank_m": snappedf(giant_sank_m, 0.01),
		"damage_taken": int(giant_hp - p.entity.combatant.pools.health) if p.entity.is_alive() else int(giant_hp)}
	print("B4_GROVE " + JSON.stringify(out))
	GameSession.expansion = ExpansionState.defaults()
	w.queue_free()
	await step_ticks(2)
	return out


func _check_grove(d: Dictionary) -> void:
	var s := int(d.stage)
	assert_eq(str(d.woke), "engaged", "stage %d: the hollow woke him" % s)
	assert_true(float(d.farthest_m) <= TERRITORY_M, "stage %d: he stays in his territory (%.0f m)" % [s, float(d.farthest_m)])
	assert_true(float(d.sank_m) < 2.0, "stage %d: he never sinks into the ground (%.2f m)" % [s, float(d.sank_m)])
	assert_true(float(d.giant_sank_m) < 1.0, "stage %d: nor the giant (%.2f m)" % [s, float(d.giant_sank_m)])
	assert_true(int(d.blows_taken) >= 3, "stage %d: his blows land among the trunks (%d)" % [s, int(d.blows_taken)])
	assert_true((d.plates as Array).size() >= 1, "stage %d: his bark broken" % s)


func test_stage_5_in_his_grove() -> void:
	var d := await _duel(5, 1, 480.0)
	if d.is_empty():
		return
	_check_grove(d)


func test_stage_6_in_his_grove() -> void:
	var d := await _duel(6, 1, 480.0)
	if d.is_empty():
		return
	_check_grove(d)
	assert_true(int(d.phase) == 2 or float(d.titan_killed_s) > 0.0, "stage 6: he is uprooted or at rest")
	assert_true(int(d.fires) >= 1, "stage 6: the grove's fire found (%d)" % int(d.fires))
