extends IntegrationSuite
## D2: the balance evidence for the Stormcaller (docs/BALANCE_LOG.md, "D2"): bot duels in the flooded steps test arena
## (scenes/test/stormcaller_test.tscn: the storm's water - a deep pool and two shallow ones - on a wet stone floor), his
## AI on (the arena wakes him: his intro first), a giant readied for each stage (TitanDuel.prepare; stage 9 by its
## numbers: TitanDuel.prepare_stage9, the growth track has no stage 9) and played by TitanDuelBot - the expert's
## fighting with the titans' rules and the storm's (out of the water when a bolt is coming down on it, unless he stands
## deep in it within the shock's reach - then it stays near and lets his own lightning ground him; braced against his
## gale; his greaves for the topple; his downs - the grounding's too). One attempt each, no respawn. The owner's
## claims ("a titan that can kill you until you max out in the area"):
##   * stage 7: deadly - the giant dies in most duels (at least two of three), never more than one win;
##   * stage 8: a real fight won more often than lost - at least two wins of three, each a fight of minutes with his
##     blows landing;
##   * stage 9 (by its numbers): clearly won - every duel, faster than stage 8's.
## And the fight repeats: the same seed fights the same first minute tick for tick, another seed differs.
## Every duel is printed as one D2_DUEL line (the log's table). The titans' tier (--titans; --gate runs it).
##
## One duel alone (a probe while tuning; nothing else runs):
##   tools/run_tests.sh --titans --suite=res://tests/titans/test_stormcaller_balance.gd --d2-duel=<stage>:<seed>[:<max s>[:trace]]
## (a fourth field prints a D2_TRACE line a second: the distance, both healths, his action, the water, the bot's rule;
## --d2-film with a display and --write-movie films it through the giant's camera).

const STEPS := "res://scenes/test/stormcaller_test.tscn"
const SEEDS := [1, 2, 3]
const PROBE := "--d2-duel="
## With a display and --write-movie: the duel's own viewport drawn full screen (the giant's camera), to film a duel.
const FILM := "--d2-film"


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


func _setup(stage: int, seed_value: int) -> Dictionary:
	await TestWait.duel_start(self)   # (B5: the same duel whatever ran before it)
	WorldState.clear()
	GameSession.expansion = ExpansionState.defaults()
	var level := (load(STEPS) as PackedScene).instantiate() as Node3D
	level.set("stage", 0)
	var host := TestWait.duel_host(world)
	host.add_child(level)   # (B5: its own physics space)
	if OS.get_cmdline_user_args().has(FILM):
		_film(host)
	var p := level.get_node("Player") as GiantPlayer
	await TestWait.until(self, func() -> bool: return p.is_on_floor(), 30)
	_prepare(p, stage)
	await TestWait.until(self, func() -> bool: return Sim.tick % 60 == 59, 70)   # (each duel on a whole second)
	Sim.reseed(Sim.DEFAULT_SEED)
	_prepare(p, stage)
	var t := level.get_node("Stormcaller") as TitanEnemy
	t.brain.rng.seed = seed_value
	p.global_position = Vector3(0, 0.05, 30)
	var arena := level.get_node("BossArena") as BossArena
	arena.disengage_s = 1.0e9   # (the duel is one attempt)
	arena.engage()
	var bot := TitanDuelBot.new()
	bot.see_obstacles = true   # (the standing stones at its edge)
	bot.setup(p, t, "expert", seed_value, true)
	return {"level": level, "player": p, "titan": t, "bot": bot}


## Stage 1-8 by the growth track; 9 by its numbers (TitanDuel.prepare_stage9).
func _prepare(p: GiantPlayer, stage: int) -> void:
	if stage >= 9:
		TitanDuel.prepare_stage9(p)
	else:
		TitanDuel.prepare(p, stage)


func _duel(stage: int, seed_value: int, max_s: float) -> Dictionary:
	var s := await _setup(stage, seed_value)
	var p: GiantPlayer = s.player
	var t: TitanEnemy = s.titan
	var bot: TitanDuelBot = s.bot
	hits.clear()
	var start := Sim.tick
	var limit := int(max_s * Sim.TICK_RATE)
	var giant_hp := p.entity.combatant.pools.health_max
	var died_at := -1
	var killed_at := -1
	var trace := not probe_arg().is_empty() and probe_arg().size() > 3
	var wet_ticks := 0
	var deep_ticks := 0
	var titan_wet_ticks := 0
	while Sim.tick - start < limit:
		bot.step(Sim.tick)
		await step_ticks(1)
		if p.storm.in_water():
			wet_ticks += 1
		if p.storm.wet >= 0.15:
			deep_ticks += 1
		if t.storm_depth() >= float(t.storm.get("ground_depth_m", 3.0)):
			titan_wet_ticks += 1
		if trace and (Sim.tick - start) % 60 == 0:
			var rel := p.global_position - t.global_position
			rel.y = 0.0
			print("D2_TRACE t=%.0f d=%.1f stamina=%.0f giant=%.0f him=%.0f act=%s wet=%.2f his=%.1f%s phase=%d rule=%s" % [
				(Sim.tick - start) / 60.0, rel.length(), p.entity.combatant.pools.stamina, p.entity.combatant.pools.health,
				t.entity.combatant.pools.health, t.controller.action_id(), p.storm.wet, t.storm_depth(),
				" DOWN" if t.is_down() else "", t.brain.boss_phase(), bot.last_rule])
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
	var by_plate := {}
	for r in hits:
		if r.event.target_id == p.entity.entity_id and r.health_damage > 0:
			blows += 1
			var k := r.event.action_id.trim_prefix("ability.stormcaller_")
			by_action[k] = int(by_action.get(k, 0)) + r.health_damage
		elif r.event.target_id == t.entity_id:
			if r.health_damage > 0:
				dealt += r.health_damage
				var key := "%s:%s" % [r.event.plate_id, r.event.plate_state]
				by_plate[key] = int(by_plate.get(key, 0)) + r.health_damage
	var n := float(maxi(1, Sim.tick - start))
	var out := {"stage": stage, "seed": seed_value, "giant_health": giant_hp,
		"giant_died_s": snappedf(died_at / 60.0, 0.1) if died_at >= 0 else -1.0,
		"titan_killed_s": snappedf(killed_at / 60.0, 0.1) if killed_at >= 0 else -1.0,
		"blows_taken": blows, "titan_left": snappedf(t.entity.combatant.pools.ratio("health"), 0.001),
		"plates": Array(t.plates().ever_broken), "phase": t.brain.boss_phase(),
		"topples": t.topples, "grounds": t.grounds, "dealt": dealt, "dealt_by": by_plate,
		"hit_by": by_action, "flank_s": snappedf(bot.flank_ticks / 60.0, 0.1),
		"evade_s": snappedf(bot.evade_ticks / 60.0, 0.1), "down_heavies": bot.down_heavies,
		"hugs": (t.brain as TitanBrain).hug_answers, "flanks": (t.brain as TitanBrain).flank_answers,
		"bolts": t.bolts_called, "bolts_in_water": t.bolts_in_water, "shocks": p.storm.shocks,
		"shock_damage": p.storm.shock_damage, "gusts": p.storm.gusts, "wet_share_s": snappedf(wet_ticks / 60.0, 0.1),
		"deep_s": snappedf(deep_ticks / 60.0, 0.1), "titan_deep_s": snappedf(titan_wet_ticks / 60.0, 0.1),
		"wet_frac": snappedf(wet_ticks / n, 0.01), "storm_outs": bot.storm_outs, "baits": bot.storm_baits,
		"braces": bot.braces,
		"damage_taken": int(giant_hp - p.entity.combatant.pools.health) if p.entity.is_alive() else int(giant_hp)}
	print("D2_DUEL " + JSON.stringify(out))
	GameSession.expansion = ExpansionState.defaults()
	(s.level as Node).get_parent().queue_free()
	await step_ticks(2)
	return out


## The probe: one duel (--d2-duel=stage:seed[:max s]); the other tests do nothing while it is given.
func test_probe_duel() -> void:
	var a := probe_arg()
	if a.is_empty():
		return
	await _duel(int(a[0]), int(a[1]) if a.size() > 1 else 1, float(a[2]) if a.size() > 2 else 600.0)


func test_stage_7_giants_mostly_die() -> void:
	if not probe_arg().is_empty():
		return
	var died := 0
	var won := 0
	for seed_value: int in SEEDS:
		var d := await _duel(7, seed_value, 600.0)
		if float(d.giant_died_s) > 0.0:
			died += 1
		if float(d.titan_killed_s) > 0.0:
			won += 1
		assert_true(int(d.blows_taken) >= 4, "stage 7 seed %d: his blows land (%d)" % [seed_value, int(d.blows_taken)])
	assert_true(died >= 2, "stage 7: deadly - the giant dies in most duels (%d of %d)" % [died, SEEDS.size()])
	assert_true(won <= 1, "stage 7: at most a lucky win (%d of %d)" % [won, SEEDS.size()])


func test_stage_8_giants_win_more_than_they_lose() -> void:
	if not probe_arg().is_empty():
		return
	var won := 0
	for seed_value: int in SEEDS:
		var d := await _duel(8, seed_value, 720.0)
		if float(d.titan_killed_s) > 0.0:
			won += 1
			assert_true(float(d.titan_killed_s) >= 120.0, "stage 8 seed %d: a fight of minutes (%.0f s)" % [seed_value,
				float(d.titan_killed_s)])
			assert_true(int(d.blows_taken) >= 4, "stage 8 seed %d: his blows land (%d)" % [seed_value,
				int(d.blows_taken)])
		assert_true(int(d.phase) >= 2 or float(d.titan_killed_s) > 0.0, "stage 8 seed %d: his second phase" % seed_value)
	assert_true(won >= 2, "stage 8: won more often than lost (%d of %d)" % [won, SEEDS.size()])


func test_stage_9_numbers_outgrow_him() -> void:
	if not probe_arg().is_empty():
		return
	var won := 0
	for seed_value: int in SEEDS:
		var d := await _duel(9, seed_value, 720.0)
		if float(d.titan_killed_s) > 0.0:
			won += 1
		assert_true(float(d.giant_died_s) < 0.0, "stage 9 seed %d: never killed" % seed_value)
	assert_eq(won, SEEDS.size(), "stage 9: clearly won - every duel (%d of %d)" % [won, SEEDS.size()])


## The same seed fights the same first minute (every hit, the plates, his bolts' points, his sequence), another seed
## another.
func test_a_seeded_duel_repeats() -> void:
	if not probe_arg().is_empty():
		return
	var a := await _record(2)
	var b := await _record(2)
	var c := await _record(5)
	assert_true((a.hits as Array).size() > 10, "a real fight (%d hits)" % (a.hits as Array).size())
	assert_eq(a, b, "the same seed: the same fight, tick for tick")
	assert_true(a.hits != c.hits or a.log != c.log or a.bolts != c.bolts, "another seed: another fight")


func _record(seed_value: int) -> Dictionary:
	var s := await _setup(8, seed_value)
	var p: GiantPlayer = s.player
	var t: TitanEnemy = s.titan
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
			r.event.plate_id, r.event.guarded, r.outcome, r.health_damage])
	var bolts: Array = []
	for e: Array in (t.brain as HarrokBrain).hazard_log:
		bolts.append([int(e[0]) - start, (e[1] as Vector3).snapped(Vector3.ONE * 0.001)])
	var out := {"hits": rec, "plates": t.plates().snapshot(), "log": Array((t.brain as TitanBrain).sequence_log),
		"bolts": bolts, "grounds": t.grounds, "shocks": p.storm.shocks,
		"titan_at": t.global_position.snapped(Vector3.ONE * 0.001),
		"giant_at": p.global_position.snapped(Vector3.ONE * 0.001)}
	GameSession.expansion = ExpansionState.defaults()
	(s.level as Node).get_parent().queue_free()
	await step_ticks(2)
	return out
