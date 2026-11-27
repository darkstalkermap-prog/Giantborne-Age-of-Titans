extends IntegrationSuite
## E1: the balance evidence for Orrik the Fetterer (docs/BALANCE_LOG.md, "E1"): bot duels in the Moot test arena
## (scenes/test/throne_test.tscn: the ring, the throne, five fetter-winches and their Skarn crews), his AI on, a giant
## readied for each stage (TitanDuel.prepare) and played by TitanDuelBot - the expert with the titans' rules and the
## fetters' (a heave when a chain bites, a pull when no heavy is ready, out of the Throne-breaker's line once free, a
## winch's harpoon side-stepped after its aim lock, a winch in the fight broken while Orrik is not swinging). Both
## branches (decision E1-4): "vengeance" (Harrok slain: the giant alone) and "ally" (Harrok spared: Harrok beside him,
## cutting chains, going for the winches, striking Orrik's legs). One attempt each, no respawn. The claims (the brief: deadly
## to a giant below stage 8, fair at 8-9):
##   * stage 7: deadly - the giant dies in at least two duels of three, never more than one win, in either branch;
##   * stage 8: a real fight won more often than lost - at least two wins of three in each branch, each a fight of
##     minutes with his blows landing and the chains biting;
##   * stage 9: won - every duel of both branches.
## And the fight repeats: the same seed fights the same first minute tick for tick.
##
## The eighteen duels run as child processes, three at a time (ChildRuns: the same suite with --e1-duel=..., each
## printing its E1_DUEL line), so the titans' tier gains minutes, not an hour. One duel alone (a probe while tuning):
##   tools/run_tests.sh --titans --suite=res://tests/titans/test_e1_balance.gd --e1-duel=<branch>:<stage>:<seed>[:<max s>[:trace]]

const ARENA := "res://scenes/test/throne_test.tscn"
const SEEDS := [1, 2, 3]
const PROBE := "--e1-duel="
const FILM := "--e1-film"
const LINE := "E1_DUEL "
const AT_ONCE := 3


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


func _setup(branch: String, stage: int, seed_value: int) -> Dictionary:
	await TestWait.duel_start(self)
	WorldState.clear()
	GameSession.expansion = ExpansionState.defaults()
	var level := (load(ARENA) as PackedScene).instantiate() as Node3D
	var arena := level.get_node("BossArena") as ThroneChallenge
	arena.branch_override = branch
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
	var t := level.get_node("Orrik") as HeirEnemy
	t.brain.rng.seed = seed_value
	p.global_position = Vector3(0, 0.05, 36)
	arena.engage()
	var bot := TitanDuelBot.new()
	bot.see_obstacles = true
	bot.setup(p, t, "expert", seed_value, true)
	return {"level": level, "player": p, "titan": t, "bot": bot, "arena": arena}


func _duel(branch: String, stage: int, seed_value: int, max_s: float) -> Dictionary:
	var s := await _setup(branch, stage, seed_value)
	var p: GiantPlayer = s.player
	var t: HeirEnemy = s.titan
	var bot: TitanDuelBot = s.bot
	var arena: ThroneChallenge = s.arena
	hits.clear()
	var start := Sim.tick
	var limit := int(max_s * Sim.TICK_RATE)
	var giant_hp := p.entity.combatant.pools.health_max
	var died_at := -1
	var killed_at := -1
	var trace := probe_arg().size() > 4
	var bound_ticks := 0
	var pinned_ticks := 0
	var max_chains := 0
	while Sim.tick - start < limit:
		bot.step(Sim.tick)
		await step_ticks(1)
		var n: int = p.fetter.count()
		max_chains = maxi(max_chains, n)
		if n > 0:
			bound_ticks += 1
		if p.fetter.is_pinned():
			pinned_ticks += 1
		if trace and (Sim.tick - start) % 60 == 0:
			var rel := p.global_position - t.global_position
			rel.y = 0.0
			print("E1_TRACE t=%.0f d=%.1f st=%.0f giant=%.0f him=%.0f act=%s chains=%d strain=%.2f phase=%d rule=%s ally=%s" % [
				(Sim.tick - start) / 60.0, rel.length(), p.entity.combatant.pools.stamina, p.entity.combatant.pools.health,
				t.entity.combatant.pools.health, t.controller.action_id(), n, p.fetter.max_strain(), t.brain.boss_phase(),
				bot.last_rule, (arena.ally.get("task") if arena.ally != null and is_instance_valid(arena.ally) else "-")])
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
			var k := r.event.action_id.trim_prefix("ability.")
			by_action[k] = int(by_action.get(k, 0)) + r.health_damage
		elif r.event.target_id == t.entity_id and r.health_damage > 0:
			dealt += r.health_damage
	var winches_broken := 0
	for w in level_winches(s.level):
		winches_broken += 1 if (w as FetterWinch).destroyed else 0
	var ally: Node = arena.ally if arena.ally != null and is_instance_valid(arena.ally) else null
	var out := {"branch": branch, "stage": stage, "seed": seed_value, "giant_health": giant_hp,
		"giant_died_s": snappedf(died_at / 60.0, 0.1) if died_at >= 0 else -1.0,
		"titan_killed_s": snappedf(killed_at / 60.0, 0.1) if killed_at >= 0 else -1.0,
		"blows_taken": blows, "titan_left": snappedf(t.entity.combatant.pools.ratio("health"), 0.001),
		"plates": Array(t.plates().ever_broken), "phase": t.brain.boss_phase(), "dealt": dealt, "hit_by": by_action,
		"chains": p.fetter.bound, "torn_heave": p.fetter.torn_heave, "torn_pull": p.fetter.torn_pull,
		"freed": p.fetter.freed, "pins": p.fetter.pins, "max_chains": max_chains,
		"bound_s": snappedf(bound_ticks / 60.0, 0.1), "pinned_s": snappedf(pinned_ticks / 60.0, 0.1),
		"hooks": t.hooks_bit, "hauls": t.hauls, "yanks": t.yanks, "breakers": t.breakers,
		"winches_broken": winches_broken, "heaves": bot.heaves, "harpoon_dodges": bot.harpoon_dodges,
		"breaker_dodges": bot.breaker_dodges, "winch_runs": bot.winch_runs,
		"ally_cuts": int(ally.get("chains_cut")) if ally != null else 0,
		"ally_winch_blows": int(ally.get("winch_blows")) if ally != null else 0,
		"ally_heir_blows": int(ally.get("heir_blows")) if ally != null else 0,
		"damage_taken": int(giant_hp - p.entity.combatant.pools.health) if p.entity.is_alive() else int(giant_hp)}
	print(LINE + JSON.stringify(out))
	GameSession.expansion = ExpansionState.defaults()
	(s.level as Node).get_parent().queue_free()
	await step_ticks(2)
	return out


static func level_winches(level: Node) -> Array:
	var out: Array = []
	for n in level.get_node("Props").get_children():
		if n is FetterWinch:
			out.append(n)
	return out


## The probe: one duel (--e1-duel=branch:stage:seed[:max s]); the other tests do nothing while it is given.
func test_probe_duel() -> void:
	var a := probe_arg()
	if a.is_empty():
		return
	await _duel(a[0], int(a[1]) if a.size() > 1 else 8, int(a[2]) if a.size() > 2 else 1,
		float(a[3]) if a.size() > 3 else 720.0)


## The eighteen duels, three at a time as child processes; {"<branch>:<stage>:<seed>": duel}.
static var _results: Dictionary = {}


func _all_duels() -> Dictionary:
	if not _results.is_empty():
		return _results
	var keys: Array = []
	for branch: String in ["vengeance", "ally"]:
		for stage: int in [7, 8, 9]:
			for seed_value: int in SEEDS:
				keys.append("%s:%d:%d" % [branch, stage, seed_value])
	var i := 0
	while i < keys.size():
		var lists: Array = []
		var batch: Array = keys.slice(i, i + AT_ONCE)
		for k: String in batch:
			lists.append(PackedStringArray(["--headless", "--path", ProjectSettings.globalize_path("res://"),
				"--fixed-fps", "60", "res://tests/run_tests.tscn", "--", "--no-user-settings", "--no-audio", "--titans",
				"--suite=res://tests/titans/test_e1_balance.gd", PROBE + k + ":720"]))
		var results := ChildRuns.run_all(lists)
		for j in batch.size():
			var text := str((results[j] as Dictionary).output)
			var duel := {}
			for line in text.split("\n"):
				if line.begins_with(LINE):
					duel = JSON.parse_string(line.substr(LINE.length()))
			if duel.is_empty():
				print("E1_CHILD_FAILED %s code %d\n%s" % [batch[j], int((results[j] as Dictionary).code), text.right(2000)])
			else:
				print(LINE + JSON.stringify(duel))
			_results[batch[j]] = duel
		i += AT_ONCE
	return _results


func _branch_claims(branch: String) -> void:
	var all := _all_duels()
	var died7 := 0
	var won7 := 0
	var won8 := 0
	var won9 := 0
	for seed_value: int in SEEDS:
		var d7: Dictionary = all.get("%s:7:%d" % [branch, seed_value], {})
		var d8: Dictionary = all.get("%s:8:%d" % [branch, seed_value], {})
		var d9: Dictionary = all.get("%s:9:%d" % [branch, seed_value], {})
		assert_false(d7.is_empty() or d8.is_empty() or d9.is_empty(), "%s seed %d: the duels ran" % [branch, seed_value])
		if d7.is_empty() or d8.is_empty() or d9.is_empty():
			continue
		died7 += 1 if float(d7.giant_died_s) > 0.0 else 0
		won7 += 1 if float(d7.titan_killed_s) > 0.0 else 0
		assert_true(int(d7.blows_taken) >= 4, "%s stage 7 seed %d: his blows land (%d)" % [branch, seed_value, int(d7.blows_taken)])
		if float(d8.titan_killed_s) > 0.0:
			won8 += 1
			assert_true(float(d8.titan_killed_s) >= 120.0, "%s stage 8 seed %d: a fight of minutes (%.0f s)" % [branch,
				seed_value, float(d8.titan_killed_s)])
		assert_true(int(d8.blows_taken) >= 4, "%s stage 8 seed %d: his blows land (%d)" % [branch, seed_value, int(d8.blows_taken)])
		assert_true(int(d8.chains) >= 1, "%s stage 8 seed %d: the chains bit (%d)" % [branch, seed_value, int(d8.chains)])
		won9 += 1 if float(d9.titan_killed_s) > 0.0 else 0
		assert_true(float(d9.giant_died_s) < 0.0, "%s stage 9 seed %d: never killed" % [branch, seed_value])
	assert_true(died7 >= 2, "%s stage 7: deadly - the giant dies in most duels (%d of 3)" % [branch, died7])
	assert_true(won7 <= 1, "%s stage 7: at most a lucky win (%d of 3)" % [branch, won7])
	assert_true(won8 >= 2, "%s stage 8: won more often than lost (%d of 3)" % [branch, won8])
	assert_eq(won9, 3, "%s stage 9: won every duel (%d of 3)" % [branch, won9])


func test_vengeance_curve() -> void:
	if not probe_arg().is_empty():
		return
	_branch_claims("vengeance")


func test_ally_curve() -> void:
	if not probe_arg().is_empty():
		return
	_branch_claims("ally")
	var all := _all_duels()
	var cuts := 0
	for k: String in all:
		if k.begins_with("ally:"):
			cuts += int((all[k] as Dictionary).get("ally_cuts", 0)) + int((all[k] as Dictionary).get("ally_winch_blows", 0))
	assert_true(cuts > 0, "Harrok fought beside the giant (%d chains cut and blows at winches)" % cuts)


## The same seed fights the same first minute (every hit, his sequence, the chains), another seed another.
func test_a_seeded_duel_repeats() -> void:
	if not probe_arg().is_empty():
		return
	var a := await _record(2)
	var b := await _record(2)
	var c := await _record(5)
	assert_true((a.hits as Array).size() > 10, "a real fight (%d hits)" % (a.hits as Array).size())
	assert_eq(a, b, "the same seed: the same fight, tick for tick")
	assert_true(a.hits != c.hits or a.log != c.log, "another seed: another fight")


func _record(seed_value: int) -> Dictionary:
	var s := await _setup("ally", 8, seed_value)
	var p: GiantPlayer = s.player
	var t: HeirEnemy = s.titan
	var bot: TitanDuelBot = s.bot
	hits.clear()
	var start := Sim.tick
	while Sim.tick - start < 60 * 60 and p.entity.is_alive() and t.entity.is_alive():
		bot.step(Sim.tick)
		await step_ticks(1)
	bot.teardown()
	var rec: Array = []
	for r in hits:
		rec.append([r.event.tick - start, r.event.attacker_id, r.event.action_id, r.event.target_id, r.event.region,
			r.event.plate_id, r.outcome, r.health_damage])
	var out := {"hits": rec, "plates": t.plates().snapshot(), "log": Array((t.brain as TitanBrain).sequence_log),
		"chains": p.fetter.bound, "titan_at": t.global_position.snapped(Vector3.ONE * 0.001),
		"giant_at": p.global_position.snapped(Vector3.ONE * 0.001)}
	GameSession.expansion = ExpansionState.defaults()
	(s.level as Node).get_parent().queue_free()
	await step_ticks(2)
	return out
