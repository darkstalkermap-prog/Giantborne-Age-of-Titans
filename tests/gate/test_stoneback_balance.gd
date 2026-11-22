extends IntegrationSuite
## A2: the balance evidence for Stoneback (docs/BALANCE_LOG.md, "A2"): bot-driven duels in the quarry test arena, the
## titan's AI on, a giant readied for each stage (TitanDuel.prepare: the stage's required level, the bots' attribute
## spending, the campaign's weapon) and played by TitanDuelBot - BotCombat's expert (its dodges and parries, the
## lock, the light chain and heavies, the abilities by rule) plus the one titan rule a skilled player follows (round
## to his back while he reels or recovers). One attempt each, no respawn:
##   * stages 3 and 4: the giant dies in most duels, in a few of his blows, having barely scratched him (the claim:
##     deadly to an under-grown giant);
##   * stage 6: the giant wins most duels in about three minutes, breaking plates on the way;
##   * stage 5: the bot breaks plates and wears him down but does not win (an honest limit: docs/BALANCE_LOG.md).
## Every duel is printed as one A2_DUEL line (the log's table). Gate tier: minutes of simulated fighting.

const QUARRY := "res://scenes/test/quarry_test.tscn"

const SEEDS := [1, 2, 3]


func _duel(stage: int, skill: String, flank: bool, seed_value: int, max_s: float) -> Dictionary:
	WorldState.clear()   # (the palisades of an earlier duel would come back broken)
	var level := (load(QUARRY) as PackedScene).instantiate() as Node3D
	level.set("stage", 0)
	world.add_child(level)
	var p := level.get_node("Player") as GiantPlayer
	await TestWait.until(self, func() -> bool: return p.is_on_floor(), 30)
	TitanDuel.prepare(p, stage)
	await TestWait.until(self, func() -> bool: return Sim.tick % 60 == 59, 70)   # (each duel on a whole second)
	Sim.reseed(Sim.DEFAULT_SEED)
	var prep := TitanDuel.prepare(p, stage)
	var t := level.get_node("Stoneback") as TitanEnemy
	t.brain.rng.seed = seed_value
	p.global_position = Vector3(0, 0.05, 22)
	(level.get_node("BossArena") as BossArena).engage()
	var bot := TitanDuelBot.new()
	bot.setup(p, t, skill, seed_value, flank)
	hits.clear()
	var start := Sim.tick
	var limit := int(max_s * Sim.TICK_RATE)
	var giant_hp := p.entity.combatant.pools.health_max
	var died_at := -1
	var killed_at := -1
	while Sim.tick - start < limit:
		bot.step(Sim.tick)
		await step_ticks(1)
		if not p.entity.is_alive():
			died_at = Sim.tick - start
			break
		if not t.entity.is_alive():
			killed_at = Sim.tick - start
			break
	bot.teardown()
	var blows := 0
	var dealt := 0
	var by_state := {}
	var by_action := {}
	for r in hits:
		if r.event.target_id == p.entity.entity_id and r.health_damage > 0:
			blows += 1
			by_action[r.event.action_id.trim_prefix("ability.stoneback_")] = "%s+%d" % [
				str(by_action.get(r.event.action_id.trim_prefix("ability.stoneback_"), "")), r.health_damage]
		elif r.event.target_id == t.entity_id and r.health_damage > 0:
			dealt += r.health_damage
			var key := "%s:%s:%s" % [r.event.plate_id, r.event.plate_state, r.event.action_id.get_slice(".", 1)]
			by_state[key] = int(by_state.get(key, 0)) + r.health_damage
	var out := {"stage": stage, "skill": skill, "flank": flank, "seed": seed_value, "level": int(prep.level),
		"weapon": str(prep.weapon), "giant_health": giant_hp,
		"giant_died_s": snappedf(died_at / 60.0, 0.1) if died_at >= 0 else -1.0,
		"titan_killed_s": snappedf(killed_at / 60.0, 0.1) if killed_at >= 0 else -1.0,
		"blows_taken": blows, "titan_left": snappedf(t.entity.combatant.pools.ratio("health"), 0.001),
		"plates": t.plate_breaks.duplicate(), "phase": t.brain.boss_phase(), "dealt": dealt, "dealt_by": by_state,
		"reels": t.wall_stops, "flank_s": snappedf(bot.flank_ticks / 60.0, 0.1),
		"evade_s": snappedf(bot.evade_ticks / 60.0, 0.1), "hit_by": by_action}
	print("A2_DUEL " + JSON.stringify(out))
	level.queue_free()
	await step_ticks(2)
	return out


func test_stage_3_and_4_giants_die_fast() -> void:
	for stage: int in [3, 4]:
		var died := 0
		for seed_value: int in SEEDS:
			var d := await _duel(stage, "expert", true, seed_value, 240.0)
			if float(d.giant_died_s) > 0.0:
				died += 1
				assert_true(int(d.blows_taken) <= 8, "stage %d seed %d: in a few of his blows (%d)" % [stage, seed_value,
					int(d.blows_taken)])
			assert_true(float(d.titan_left) > 0.8, "stage %d seed %d: having barely scratched him (%.2f left)" % [stage,
				seed_value, float(d.titan_left)])
			assert_true((d.plates as Array).is_empty(), "stage %d seed %d: no plate in its reach broken" % [stage, seed_value])
		assert_true(died >= 2, "stage %d: the giant dies in most duels (%d of %d)" % [stage, died, SEEDS.size()])


func test_stage_6_giants_win_in_about_three_minutes() -> void:
	var won := 0
	for seed_value: int in SEEDS:
		var d := await _duel(6, "expert", true, seed_value, 600.0)
		if float(d.titan_killed_s) > 0.0:
			won += 1
			assert_true(float(d.titan_killed_s) >= 100.0 and float(d.titan_killed_s) <= 330.0,
				"stage 6 seed %d: in about 2-5 minutes (%.0f s)" % [seed_value, float(d.titan_killed_s)])
		else:
			assert_true(float(d.titan_left) < 0.5, "stage 6 seed %d: a lost duel still took most of him (%.2f)" % [
				seed_value, float(d.titan_left)])
		assert_true((d.plates as Array).size() >= 1, "stage 6 seed %d: breaking plates on the way" % seed_value)
	assert_true(won >= 2, "stage 6: the giant wins most duels (%d of %d)" % [won, SEEDS.size()])


## Stage 5: the bot's measure only (it does not win: docs/BALANCE_LOG.md, A2) - it breaks a plate and wears him
## down far more than a stage-4 giant does, without the win the claim makes for a skilled player.
func test_stage_5_giants_break_plates_and_wear_him_down() -> void:
	var best := 1.0
	var broke := 0
	for seed_value: int in SEEDS:
		var d := await _duel(5, "expert", true, seed_value, 600.0)
		best = minf(best, float(d.titan_left))
		broke += (d.plates as Array).size()
	assert_true(broke >= 1, "stage 5: plates broken over the seeds (%d)" % broke)
	assert_true(best < 0.7, "stage 5: at best he is worn below 70 %% (%.2f)" % best)
