extends IntegrationSuite
## E3: the balance evidence for the Hollow Titan (docs/BALANCE_LOG.md, "E3"): bot duels in the Kingsward test arena
## (scenes/test/hollow_test.tscn: frost-bitten ground in a ring of rock, three oath-stones at its edge), his AI on, a giant
## readied for each stage (TitanDuel.prepare: the stage's required level, the bots' attribute spending, the campaign's
## weapon) and played by TitanDuelBot - the expert's fighting with the titans' rules and the hollow's (his breastplate
## first and then the oath-knot, a torn plate stamped or hurled back before the chains draw it back on, out of his draw's
## cone and his echo's ring, an oath-stone brought down while he is not striking). One attempt each, no respawn. The
## brief's claims ("a titan that can kill you until you max out in the area"):
##   * stage 8: deadly - the giant dies in every duel;
##   * stage 9 (the bot at stage 9's required level 17; the guaranteed path's giant is 19): won with effort - at least two
##     wins of three, each a fight of nearly two minutes or more (100 s) in which his blows landed and the oath-knot was
##     struck.
## And the fight repeats: the same seed fights the same first 100 s tick for tick, another seed differs.
##
## The six duels run as child processes, three at a time (ChildRuns: the same suite with --e3-duel=..., each printing
## its E3_DUEL line). One duel alone (a probe while tuning):
##   tools/run_tests.sh --titans --suite=res://tests/titans/test_e3_balance.gd --e3-duel=<stage>:<seed>[:<max s>[:trace[:staked]]]
## ("staked": the preparation done - the Oath-stake pulled: the BALANCE_LOG's prepared runs).

const ARENA := "res://scenes/test/hollow_test.tscn"
const SEEDS := [1, 2, 3]
const PROBE := "--e3-duel="
const FILM := "--e3-film"
const LINE := "E3_DUEL "
const AT_ONCE := 3
const STAKE_FLAG := "world.kingsward.stake_pulled"


static func probe_arg() -> PackedStringArray:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with(PROBE):
			return arg.substr(PROBE.length()).split(":")
	return PackedStringArray()


func _film(host: SubViewport) -> void:
	host.size = Vector2i(1280, 720)
	host.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	var layer := CanvasLayer.new()
	layer.name = "DuelFilm"
	var view := TextureRect.new()
	view.texture = host.get_texture()
	view.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(view)
	host.get_parent().add_child(layer)


func _setup(stage: int, seed_value: int, staked := false) -> Dictionary:
	await TestWait.duel_start(self)
	WorldState.clear()
	GameSession.expansion = ExpansionState.defaults()
	if staked:
		WorldState.set_flag(STAKE_FLAG, true)
	var level := (load(ARENA) as PackedScene).instantiate() as Node3D
	level.set("stage", 0)
	var arena := level.get_node("BossArena") as BossArena
	arena.disengage_s = 1.0e9   # (the duel is one attempt)
	var host := TestWait.duel_host(world)
	host.add_child(level)
	if OS.get_cmdline_user_args().has(FILM):
		_film(host)
	var p := level.get_node("Player") as GiantPlayer
	await TestWait.until(self, func() -> bool: return p.is_on_floor(), 30)
	TitanDuel.prepare(p, stage)
	await TestWait.until(self, func() -> bool: return Sim.tick % 60 == 59, 70)
	Sim.reseed(Sim.DEFAULT_SEED)
	TitanDuel.prepare(p, stage)
	var t := level.get_node("Hollow") as HollowEnemy
	t.brain.rng.seed = seed_value
	p.global_position = Vector3(0, 0.05, 60)
	t.wake("duel")
	var bot := TitanDuelBot.new()
	bot.see_obstacles = true
	bot.setup(p, t, "expert", seed_value, true)
	return {"level": level, "player": p, "titan": t, "bot": bot, "arena": arena}


func _duel(stage: int, seed_value: int, max_s: float, trace := false, staked := false) -> Dictionary:
	var s := await _setup(stage, seed_value, staked)
	var p: GiantPlayer = s.player
	var t: HollowEnemy = s.titan
	var bot: TitanDuelBot = s.bot
	hits.clear()
	var start := Sim.tick
	var limit := int(max_s * Sim.TICK_RATE)
	var giant_hp := p.entity.combatant.pools.health_max
	var died_at := -1
	var killed_at := -1
	var open_ticks := 0
	while Sim.tick - start < limit:
		bot.step(Sim.tick)
		await step_ticks(1)
		if t.knot_open:
			open_ticks += 1
		if trace and (Sim.tick - start) % 60 == 0:
			var rel := p.global_position - t.global_position
			rel.y = 0.0
			print("E3_TRACE t=%.0f d=%.1f st=%.0f giant=%.0f him=%.0f act=%s knot=%s echo=%.0f shards=%s stones=%d phase=%d rule=%s lock=%s" % [
				(Sim.tick - start) / 60.0, rel.length(), p.entity.combatant.pools.stamina, p.entity.combatant.pools.health,
				t.entity.combatant.pools.health, t.controller.action_id(), "BARE" if t.knot_open else "cov", t.resonance,
				str(t.lying_shards()), t.standing_stones().size(), t.brain.boss_phase(), bot.last_rule, t.lock_choice])
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
	var by_region := {}
	for r in hits:
		if r.event.target_id == p.entity.entity_id and r.health_damage > 0:
			blows += 1
			var k := r.event.action_id.trim_prefix("ability.")
			by_action[k] = int(by_action.get(k, 0)) + r.health_damage
		elif r.event.target_id == t.entity_id and r.health_damage > 0:
			dealt += r.health_damage
			by_region[r.event.region] = int(by_region.get(r.event.region, 0)) + r.health_damage
	var out := {"stage": stage, "seed": seed_value, "staked": staked, "giant_health": giant_hp,
		"giant_died_s": snappedf(died_at / 60.0, 0.1) if died_at >= 0 else -1.0,
		"titan_killed_s": snappedf(killed_at / 60.0, 0.1) if killed_at >= 0 else -1.0,
		"blows_taken": blows, "titan_left": snappedf(t.entity.combatant.pools.ratio("health"), 0.001),
		"plates": Array(t.plates().ever_broken), "phase": t.brain.boss_phase(), "dealt": dealt, "hit_by": by_action,
		"dealt_by_region": by_region, "knot_open_s": snappedf(open_ticks / 60.0, 0.1), "knot_hits": t.knot_hits,
		"crushes": t.crushes, "hurls": t.hurls, "reforms": t.reforms, "echoes": t.echoes, "echo_peak": t.echo_peak,
		"draws": t.draws_landed, "stones_felled": t.stones_felled, "topples": t.topples,
		"crush_runs": bot.shard_runs, "stone_runs": bot.stone_runs,
		"damage_taken": int(giant_hp - p.entity.combatant.pools.health) if p.entity.is_alive() else int(giant_hp)}
	print(LINE + JSON.stringify(out))
	WorldState.clear()
	GameSession.expansion = ExpansionState.defaults()
	(s.level as Node).get_parent().queue_free()
	await step_ticks(2)
	return out


## The probe: one duel (--e3-duel=stage:seed[:max s[:trace[:staked]]]); the other tests do nothing while it is given.
func test_probe_duel() -> void:
	var a := probe_arg()
	if a.is_empty():
		return
	await _duel(int(a[0]) if a.size() > 0 else 9, int(a[1]) if a.size() > 1 else 1,
		float(a[2]) if a.size() > 2 else 720.0, a.size() > 3 and a[3] == "trace", a.size() > 4 and a[4] == "staked")


static var _results: Dictionary = {}


func _all_duels() -> Dictionary:
	if not _results.is_empty():
		return _results
	var keys: Array = []
	for stage: int in [8, 9]:
		for seed_value: int in SEEDS:
			keys.append("%d:%d" % [stage, seed_value])
	var i := 0
	while i < keys.size():
		var lists: Array = []
		var batch: Array = keys.slice(i, i + AT_ONCE)
		for k: String in batch:
			lists.append(PackedStringArray(["--headless", "--path", ProjectSettings.globalize_path("res://"),
				"--fixed-fps", "60", "res://tests/run_tests.tscn", "--", "--no-user-settings", "--no-audio", "--titans",
				"--suite=res://tests/titans/test_e3_balance.gd", PROBE + k + ":600"]))
		var results := ChildRuns.run_all(lists)
		for j in batch.size():
			var text := str((results[j] as Dictionary).output)
			var duel := {}
			for line in text.split("\n"):
				if line.begins_with(LINE):
					duel = JSON.parse_string(line.substr(LINE.length()))
			if duel.is_empty():
				print("E3_CHILD_FAILED %s code %d\n%s" % [batch[j], int((results[j] as Dictionary).code), text.right(2000)])
			else:
				print(LINE + JSON.stringify(duel))
			_results[batch[j]] = duel
		i += AT_ONCE
	return _results


func test_the_curve() -> void:
	if not probe_arg().is_empty():
		return
	var all := _all_duels()
	var died8 := 0
	var won9 := 0
	for seed_value: int in SEEDS:
		var d8: Dictionary = all.get("8:%d" % seed_value, {})
		var d9: Dictionary = all.get("9:%d" % seed_value, {})
		assert_false(d8.is_empty() or d9.is_empty(), "seed %d: the duels ran" % seed_value)
		if d8.is_empty() or d9.is_empty():
			continue
		died8 += 1 if float(d8.giant_died_s) > 0.0 else 0
		assert_true(int(d8.blows_taken) >= 4, "stage 8 seed %d: his blows land (%d)" % [seed_value, int(d8.blows_taken)])
		if float(d9.titan_killed_s) > 0.0:
			won9 += 1
			assert_true(float(d9.titan_killed_s) >= 100.0, "stage 9 seed %d: a fight of minutes (%.0f s)" % [seed_value,
				float(d9.titan_killed_s)])
			assert_true(int(d9.knot_hits) >= 1, "stage 9 seed %d: won through the oath-knot (%d)" % [seed_value,
				int(d9.knot_hits)])
		assert_true(int(d9.blows_taken) >= 4, "stage 9 seed %d: his blows landed (%d)" % [seed_value, int(d9.blows_taken)])
	assert_eq(died8, 3, "stage 8: deadly - the giant dies in every duel (%d of 3)" % died8)
	assert_true(won9 >= 2, "stage 9: won with effort - at least two of three (%d of 3)" % won9)


## The same seed fights the same first 100 s (every hit, his sequence, his shards), another seed another.
func test_a_seeded_duel_repeats() -> void:
	if not probe_arg().is_empty():
		return
	var a := await _record(2)
	var b := await _record(2)
	var c := await _record(5)
	assert_true((a.hits as Array).size() > 10, "a real fight (%d hits)" % (a.hits as Array).size())
	if a != b:
		for k: String in a:
			if a[k] != b[k]:
				print("E3_REPEAT_DIFF %s" % k)
				if typeof(a[k]) == TYPE_ARRAY:
					for i in mini((a[k] as Array).size(), (b[k] as Array).size()):
						if a[k][i] != b[k][i]:
							print("  first at %d: %s vs %s" % [i, str(a[k][i]), str(b[k][i])])
							break
	assert_eq(a, b, "the same seed: the same fight, tick for tick")
	assert_true(a.hits != c.hits or a.log != c.log, "another seed: another fight")


func _record(seed_value: int) -> Dictionary:
	var s := await _setup(9, seed_value)
	var p: GiantPlayer = s.player
	var t: HollowEnemy = s.titan
	var bot: TitanDuelBot = s.bot
	hits.clear()
	var start := Sim.tick
	while Sim.tick - start < 100 * 60 and p.entity.is_alive() and t.entity.is_alive():
		bot.step(Sim.tick)
		await step_ticks(1)
	bot.teardown()
	var rec: Array = []
	for r in hits:
		rec.append([r.event.tick - start, r.event.attacker_id, r.event.action_id, r.event.target_id, r.event.region,
			r.event.plate_id, r.outcome, r.health_damage])
	var shards: Array = []
	for id: String in t.shards:
		shards.append([id, str(t.shards[id].state), (t.shards[id].p as Vector3).snapped(Vector3.ONE * 0.01),
			int(t.shards[id].since) - start])
	var out := {"hits": rec, "plates": t.plates().snapshot(), "log": Array((t.brain as TitanBrain).sequence_log),
		"shards": shards, "echo": snappedf(t.resonance, 0.01), "titan_at": t.global_position.snapped(Vector3.ONE * 0.001),
		"giant_at": p.global_position.snapped(Vector3.ONE * 0.001)}
	WorldState.clear()
	GameSession.expansion = ExpansionState.defaults()
	(s.level as Node).get_parent().queue_free()
	await step_ticks(2)
	return out
