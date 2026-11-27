extends IntegrationSuite
## D3: milestone D's titans at stage 9 (the real growth.09, not D2's stand-in profile) and the Stormcaller in his real
## pools (docs/BALANCE_LOG.md, "D3").
##   * the Stormcaller on the world's Stormstair (scenes/world/world.tscn, deterministic streaming), the bot climbing in
##     from the lower terraces as D2's world duel: a stage-9 giant (seed 1) clearly wins in his real pools (the
##     stage-8 world duel, seed 1, is D2's own: tests/titans/test_d2_world.gd; seeds 2-3 and stage 7 are probes - the
##     titans' tier keeps under its 25 minutes);
##   * the Frostbound on his tarn test arena at stage 9 (seed 1): outgrown - won, never near death.
## Every duel prints one D3_DUEL line. The other seeds of the BALANCE_LOG's tables are probes, one duel alone:
##   tools/gd.sh --headless --path . --fixed-fps 60 res://tests/run_tests.tscn -- --no-user-settings --no-audio --titans \
##     --suite=res://tests/titans/test_d3_titans.gd --d3-duel=<storm_world|frost>:<stage>:<seed>[:<max s>]

const SCENE := "res://scenes/world/world.tscn"
const FROST_ARENA := "res://scenes/test/frostbound_test.tscn"
const LOWER := Vector2(-96.0, -330.0)
const CENTRE := Vector2(-96.0, -356.0)
const TERRITORY_M := 170.0
const PROBE := "--d3-duel="


static func probe_arg() -> PackedStringArray:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with(PROBE):
			return arg.substr(PROBE.length()).split(":")
	return PackedStringArray()


func after_each() -> void:
	get_tree().paused = false
	for f in Formation.live():
		f.dissolve()
	FactionState.reset_for_tests()
	WanderDirector.reset_for_tests()
	GameSession.expansion = ExpansionState.defaults()
	await super()


func _world(xz: Vector2, stage: int, host: Node) -> WorldRoot:
	WorldState.clear()
	GameSession.start_world_for_tests("world.cp.bell_tower")
	GameSession.level_id = GameSession.WORLD_LEVEL_ID
	WorldState.try_set_flag("act.two.begun", true)
	var w := (load(SCENE) as PackedScene).instantiate() as WorldRoot
	host.add_child(w)
	w.streamer.deterministic = true
	var p := w.player()
	p.router.use_injection = true
	GameSession.on_level_ready(w, p)
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
	TitanDuel.prepare(p, stage)
	await step_ticks(2)
	return w


func _titan(def_id: String) -> TitanEnemy:
	for n in get_tree().root.find_children("*", "TitanEnemy", true, false):
		var t := n as TitanEnemy
		if t.entity != null and t.entity.definition_id == def_id and t.entity.is_alive():
			return t
	return null


## Runs the fight to its end (or `max_s`): the duel's numbers as D2's world duel reports them.
func _fight(p: GiantPlayer, t: TitanEnemy, bot: TitanDuelBot, max_s: float, w: WorldRoot) -> Dictionary:
	hits.clear()
	var start := Sim.tick
	var limit := int(max_s * Sim.TICK_RATE)
	var giant_hp := p.entity.combatant.pools.health_max
	var died_at := -1
	var killed_at := -1
	var far_m := 0.0
	var low_hp := 1.0
	while Sim.tick - start < limit:
		bot.step(Sim.tick)
		await step_ticks(1)
		if (Sim.tick - start) % 30 == 0:
			far_m = maxf(far_m, Vector2(t.global_position.x, t.global_position.z).distance_to(CENTRE)) if w != null else 0.0
			low_hp = minf(low_hp, p.entity.combatant.pools.ratio("health"))
		if not p.entity.is_alive():
			died_at = Sim.tick - start
			break
		if not t.entity.is_alive():
			killed_at = Sim.tick - start
			break
	bot.teardown()
	var blows := 0
	for r in hits:
		if r.event.target_id == p.entity.entity_id and r.health_damage > 0:
			blows += 1
	return {"giant_health": giant_hp,
		"giant_died_s": snappedf(died_at / 60.0, 0.1) if died_at >= 0 else -1.0,
		"titan_killed_s": snappedf(killed_at / 60.0, 0.1) if killed_at >= 0 else -1.0,
		"blows_taken": blows, "titan_left": snappedf(t.entity.combatant.pools.ratio("health"), 0.001),
		"giant_low": snappedf(low_hp, 0.001), "plates": Array(t.plates().ever_broken), "phase": t.brain.boss_phase(),
		"farthest_m": snappedf(far_m, 0.1),
		"damage_taken": int(giant_hp - p.entity.combatant.pools.health) if p.entity.is_alive() else int(giant_hp)}


## The Stormcaller in his real pools: `stage`, `seed_value`.
func _storm_world(stage: int, seed_value: int, max_s := 720.0) -> Dictionary:
	await TestWait.duel_start(self)
	var host := TestWait.duel_host(world)
	var w := await _world(LOWER, stage, host)
	await step_ticks(30)
	var p := w.player()
	var t := _titan("enemy.stormcaller")
	if t == null:
		host.queue_free()
		await step_ticks(2)
		return {}
	TitanDuel.prepare(p, stage)
	t.brain.rng.seed = seed_value
	t.wake("engaged")
	var bot := TitanDuelBot.new()
	bot.see_obstacles = true
	bot.setup(p, t, "expert", seed_value, true)
	var out := await _fight(p, t, bot, max_s, w)
	out.merge({"duel": "storm_world", "stage": stage, "seed": seed_value, "grounds": t.grounds, "bolts": t.bolts_called,
		"bolts_in_water": t.bolts_in_water, "shocks": p.storm.shocks}, true)
	print("D3_DUEL " + JSON.stringify(out))
	GameSession.expansion = ExpansionState.defaults()
	host.queue_free()
	await step_ticks(2)
	return out


## The Frostbound on his tarn test arena (D1's): `stage`, `seed_value`.
func _frost(stage: int, seed_value: int, max_s := 600.0) -> Dictionary:
	await TestWait.duel_start(self)
	WorldState.clear()
	GameSession.expansion = ExpansionState.defaults()
	var level := (load(FROST_ARENA) as PackedScene).instantiate() as Node3D
	level.set("stage", 0)
	var host := TestWait.duel_host(world)
	host.add_child(level)
	var p := level.get_node("Player") as GiantPlayer
	await TestWait.until(self, func() -> bool: return p.is_on_floor(), 30)
	TitanDuel.prepare(p, stage)
	await TestWait.until(self, func() -> bool: return Sim.tick % 60 == 59, 70)
	Sim.reseed(Sim.DEFAULT_SEED)
	TitanDuel.prepare(p, stage)
	var t := level.get_node("Frostbound") as TitanEnemy
	t.brain.rng.seed = seed_value
	p.global_position = Vector3(0, 0.05, 30)
	var arena := level.get_node("BossArena") as BossArena
	arena.disengage_s = 1.0e9
	arena.engage()
	var bot := TitanDuelBot.new()
	bot.see_obstacles = true
	bot.setup(p, t, "expert", seed_value, true)
	var out := await _fight(p, t, bot, max_s, null)
	out.merge({"duel": "frost", "stage": stage, "seed": seed_value, "freezes": p.rime.freezes}, true)
	print("D3_DUEL " + JSON.stringify(out))
	host.queue_free()
	await step_ticks(2)
	return out


func test_a_probe_duel() -> void:
	var a := probe_arg()
	if a.size() < 3:
		return
	var max_s := float(a[3]) if a.size() > 3 else 720.0
	if a[0] == "frost":
		await _frost(int(a[1]), int(a[2]), max_s)
	else:
		await _storm_world(int(a[1]), int(a[2]), max_s)


func test_a_stage_9_giant_outgrows_the_stormcaller_in_his_real_pools() -> void:
	if not probe_arg().is_empty():
		return
	var nine := await _storm_world(9, 1)
	assert_false(nine.is_empty(), "he is on the Stormstair")
	if nine.is_empty():
		return
	assert_true(float(nine.titan_killed_s) > 0.0, "stage 9 wins in his real pools (%s)" % [nine])
	assert_true(float(nine.giant_died_s) < 0.0, "never killed")
	assert_true(float(nine.giant_low) >= 0.3, "never near death: %.0f %% at worst" % (float(nine.giant_low) * 100.0))
	assert_true(float(nine.farthest_m) <= TERRITORY_M, "he stays in his territory (%.0f m)" % float(nine.farthest_m))


func test_the_frostbound_is_outgrown_at_stage_9() -> void:
	if not probe_arg().is_empty():
		return
	var d := await _frost(9, 1)
	assert_true(float(d.titan_killed_s) > 0.0, "stage 9 beats him (%s)" % [d])
	assert_true(float(d.giant_low) >= 0.4, "never near death: %.0f %% at worst" % (float(d.giant_low) * 100.0))
