extends IntegrationSuite
## D2 in the real open world (scenes/world/world.tscn, deterministic streaming), on the Stormstair at the top of the
## Drowned Steps:
##   * from act two the Stormcaller stands at home on the Bellmere's north shore, asleep; before it he is not there;
##     the warning post does not wake him; a giant climbing into his pools does (engaged) and the Stormstair is
##     discovered;
##   * the storm's water (StormWater) lies over the pools' basins: the Bellmere 6 m deep, its shore dry; the storm over
##     the Steps (StormWeather) stands from act two and clears after his fall; the Steps' rain plays while it stands;
##   * one duel in his real pools (stage 8, seed 1): he wakes and fights; he stays in his territory and never sinks
##     into the ground, nor the giant; his blows and his bolts land; his own lightning grounds him in his water. Printed
##     as a D2_WORLD line (docs/BALANCE_LOG.md, "D2").
## The titans' tier (--titans; --gate runs it): it loads the world, as the Frostbound's world suite does.

const SCENE := "res://scenes/world/world.tscn"
const HOME := Vector2(-96.0, -428.0)
const WARNING := Vector2(-104.0, -272.0)
const BELLMERE := Vector2(-100.0, -392.0)
const LOWER := Vector2(-96.0, -330.0)
const POOLS_IN := Vector2(-60.0, -312.0)
## His territory's hunting line (TitanTerritory: 150 m and the 20 m margin) from the pools' centre.
const CENTRE := Vector2(-96.0, -356.0)
const TERRITORY_M := 170.0


func after_each() -> void:
	get_tree().paused = false
	for f in Formation.live():
		f.dissolve()
	FactionState.reset_for_tests()
	WanderDirector.reset_for_tests()
	GameSession.expansion = ExpansionState.defaults()
	await super()


func _world(xz: Vector2, stage := 8, act_two := true, host: Node = null) -> WorldRoot:
	WorldState.clear()
	GameSession.start_world_for_tests("world.cp.bell_tower")
	GameSession.level_id = GameSession.WORLD_LEVEL_ID
	if act_two:
		WorldState.try_set_flag("act.two.begun", true)
	var w := (load(SCENE) as PackedScene).instantiate() as WorldRoot
	(host if host != null else world).add_child(w)
	w.streamer.deterministic = true
	var p := w.player()
	p.router.use_injection = true
	GameSession.on_level_ready(w, p)
	await _place(w, xz)
	TitanDuel.prepare(p, stage)
	await step_ticks(2)
	return w


func _place(w: WorldRoot, xz: Vector2) -> void:
	var p := w.player()
	var at := Vector3(xz.x, 120.0, xz.y)
	p.process_mode = Node.PROCESS_MODE_DISABLED
	p.global_position = at
	var guard := 0
	while not w.streamer.ring_ready(at) and guard < 900:
		w.streamer.load_ring_slice(at)
		await step_ticks(1)
		guard += 1
	var y := w.height_at(at)
	p.global_position = Vector3(xz.x, (y if not is_nan(y) else 20.0) + 0.3, xz.y)
	p.velocity = Vector3.ZERO
	p.process_mode = Node.PROCESS_MODE_INHERIT


func _titan() -> TitanEnemy:
	for n in get_tree().root.find_children("*", "TitanEnemy", true, false):
		var t := n as TitanEnemy
		if t.entity != null and t.entity.definition_id == "enemy.stormcaller" and t.entity.is_alive():
			return t
	return null


func _territory() -> TitanTerritory:
	for n in get_tree().get_nodes_in_group(BossArena.GROUP):
		if n is TitanTerritory and (n as TitanTerritory).boss_id == "world.drowned.stormcaller":
			return n
	return null


func test_he_is_not_there_before_act_two() -> void:
	var w := await _world(WARNING, 8, false)
	await step_ticks(40)
	assert_true(_titan() == null, "before the throne's fall the Stormstair is empty")
	var weather := get_tree().get_first_node_in_group(StormWeather.GROUP) as StormWeather
	assert_true(weather != null, "the storm's node is loaded with the Steps")
	if weather != null:
		assert_eq(weather.strength_at(Vector3(BELLMERE.x, 24.0, BELLMERE.y)), 0.0, "no storm before act two")
	assert_true(w != null, "the world")


func test_he_stands_in_the_storm_until_a_giant_climbs_into_his_pools() -> void:
	var w := await _world(WARNING)
	await step_ticks(40)
	var t := _titan()
	var terr := _territory()
	assert_true(t != null, "the Stormcaller is spawned on the Stormstair")
	assert_true(terr != null, "his territory is loaded")
	if t == null or terr == null:
		return
	var home := Vector2(t.global_position.x, t.global_position.z)
	assert_true(home.distance_to(HOME) < 3.0, "at home on the Bellmere's north shore (%s)" % home)
	var ground := w.height_at(t.global_position)
	assert_true(absf(t.global_position.y - ground) < 1.0, "on the ground (%.1f m, the ground %.1f)" % [
		t.global_position.y, ground])
	assert_true(t.dormant, "waiting in the storm")
	assert_false(terr.wake_on_sight, "sight does not wake him")
	await step_ticks(120)
	assert_true(t.dormant, "a giant at the warning post does not wake him")
	await _place(w, POOLS_IN)
	await step_ticks(40)
	assert_false(t.dormant, "a giant in his pools wakes him")
	assert_eq(t.wake_reason, "engaged", "engaged by his territory")
	assert_true(QuestConditions.truthy(WorldState.get_flag(Discovery.discovered_flag("poi.stormstair"))),
		"the Stormstair discovered")


func test_the_pools_water_and_the_storm_over_them() -> void:
	var w := await _world(LOWER)
	await step_ticks(20)
	var deep := Vector3(BELLMERE.x, w.height_at(Vector3(BELLMERE.x, 0, BELLMERE.y)), BELLMERE.y)
	assert_true(StormWater.depth_at(get_tree(), deep) > 5.5, "the Bellmere 6 m deep (%.1f)" % StormWater.depth_at(
		get_tree(), deep))
	var surf := w.water_at(deep)
	assert_false(is_nan(surf), "the world's water there")
	var shore := Vector3(HOME.x, w.height_at(Vector3(HOME.x, 0, HOME.y)), HOME.y)
	assert_eq(StormWater.depth_at(get_tree(), shore), 0.0, "his shore is dry")
	var step := Vector3(-48.0, w.height_at(Vector3(-48, 0, -308)), -308.0)
	var d2 := StormWater.depth_at(get_tree(), step)
	assert_true(d2 > 2.5 and d2 < 4.0, "the Stepmere a step down, 3 m deep (%.1f)" % d2)
	var weather := get_tree().get_first_node_in_group(StormWeather.GROUP) as StormWeather
	assert_true(weather != null, "the storm's node")
	if weather != null:
		assert_eq(weather.strength_at(deep), 1.0, "the storm stands over the pools")
		WorldState.set_flag("boss.stormcaller.defeated", true)
		assert_true(weather.calm(), "his fall: it clears")
		assert_eq(StormWater.depth_at(get_tree(), deep), 0.0, "and the water is only water")
		WorldState.set_flag("boss.stormcaller.defeated", false)
	var set: Dictionary = GameData.get_record("ambience.drowned_steps")
	var rain: Array = (set.emitters as Array).filter(func(e: Dictionary) -> bool: return str(e.cue) == "amb.storm_rain_loop")
	assert_eq(rain.size(), 1, "the storm's rain on the Steps' ambience")
	if not rain.is_empty():
		WorldState.set_flag("boss.stormcaller.defeated", false)
		assert_true(AmbienceDirector.emitter_flags_allow(rain[0]), "it rains while the storm stands")
		WorldState.set_flag("boss.stormcaller.defeated", true)
		assert_false(AmbienceDirector.emitter_flags_allow(rain[0]), "not after his fall")
		WorldState.set_flag("boss.stormcaller.defeated", false)


## One duel in his real pools at stage 8 (seed 1): the bot climbs in from the lower terraces.
func test_a_stage_8_duel_in_his_pools() -> void:
	await TestWait.duel_start(self)
	var host := TestWait.duel_host(world)
	var w := await _world(LOWER, 8, true, host)
	await step_ticks(30)
	var p := w.player()
	var t := _titan()
	assert_true(t != null, "he is on the Stormstair")
	if t == null:
		w.get_parent().queue_free()
		await step_ticks(2)
		return
	TitanDuel.prepare(p, 8)
	t.brain.rng.seed = 1
	t.wake("engaged")
	var bot := TitanDuelBot.new()
	bot.see_obstacles = true
	bot.setup(p, t, "expert", 1, true)
	hits.clear()
	var start := Sim.tick
	var limit := int(720.0 * Sim.TICK_RATE)
	var giant_hp := p.entity.combatant.pools.health_max
	var died_at := -1
	var killed_at := -1
	var far_m := 0.0
	var sank_m := 0.0
	var giant_sank_m := 0.0
	while Sim.tick - start < limit:
		bot.step(Sim.tick)
		await step_ticks(1)
		if (Sim.tick - start) % 30 == 0:
			far_m = maxf(far_m, Vector2(t.global_position.x, t.global_position.z).distance_to(CENTRE))
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
			var k := r.event.action_id.trim_prefix("ability.stormcaller_")
			by_action[k] = int(by_action.get(k, 0)) + r.health_damage
		elif r.event.target_id == t.entity_id and r.health_damage > 0:
			dealt += r.health_damage
	var out := {"stage": 8, "seed": 1, "giant_health": giant_hp, "woke": t.wake_reason,
		"giant_died_s": snappedf(died_at / 60.0, 0.1) if died_at >= 0 else -1.0,
		"titan_killed_s": snappedf(killed_at / 60.0, 0.1) if killed_at >= 0 else -1.0,
		"blows_taken": blows, "titan_left": snappedf(t.entity.combatant.pools.ratio("health"), 0.001),
		"plates": Array(t.plates().ever_broken), "phase": t.brain.boss_phase(), "topples": t.topples,
		"grounds": t.grounds, "bolts": t.bolts_called, "bolts_in_water": t.bolts_in_water, "shocks": p.storm.shocks,
		"dealt": dealt, "hit_by": by_action, "farthest_m": snappedf(far_m, 0.1), "sank_m": snappedf(sank_m, 0.01),
		"giant_sank_m": snappedf(giant_sank_m, 0.01), "storm_outs": bot.storm_outs, "lure_s": snappedf(
			bot.storm_lure_ticks / 60.0, 0.1),
		"damage_taken": int(giant_hp - p.entity.combatant.pools.health) if p.entity.is_alive() else int(giant_hp)}
	print("D2_WORLD " + JSON.stringify(out))
	assert_true(float(out.farthest_m) <= TERRITORY_M, "he stays in his territory (%.0f m)" % float(out.farthest_m))
	assert_true(float(out.sank_m) < 2.0, "he never sinks into the ground (%.2f m)" % float(out.sank_m))
	assert_true(float(out.giant_sank_m) < 1.0, "nor the giant (%.2f m)" % float(out.giant_sank_m))
	assert_true(int(out.blows_taken) >= 4, "his blows land on his own ground (%d)" % int(out.blows_taken))
	assert_true(int(out.bolts) >= 3, "his bolts come down (%d)" % int(out.bolts))
	assert_true(int(out.dealt) > 2000, "a real fight: the giant hurts him (%d)" % int(out.dealt))
	GameSession.expansion = ExpansionState.defaults()
	w.get_parent().queue_free()
	await step_ticks(2)
