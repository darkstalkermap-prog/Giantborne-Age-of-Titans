extends IntegrationSuite
## B3: the balance evidence for the Rootwarden (docs/BALANCE_LOG.md, "B3"): bot duels in the grove test arena, his AI
## on (the arena wakes him), a giant readied for each stage (TitanDuel.prepare) and played by TitanDuelBot - the expert's
## fighting with the titans' rules (his shins in his recoveries; his downs; his knot first; a brazier smashed while a
## wound of his is open, so it is seared and never regrows; out of his telegraphs). One attempt each, no respawn.
## The owner's claims:
##   * stage 4: deadly - the giant dies in most duels, far from bringing him down, never winning;
##   * stage 5: a hard fight - it wins at least one duel of three, in minutes, his blows landing;
##   * stage 6: fair - it wins most duels.
## And the fight repeats: the same seed fights the same first minute tick for tick (the regrowth, the fire, his
## phase and the falling trees included), another seed differs.
## Every duel is printed as one B3_DUEL line (the log's table). The titans' tier (B4; --gate runs it): 3 seeds at stages 4, 5 and 6.

const GROVE := "res://scenes/test/grove_test.tscn"
const SEEDS := [1, 2, 3]


func _setup(stage: int, seed_value: int) -> Dictionary:
	await TestWait.duel_start(self)   # (B5: the same duel whatever ran before it)
	WorldState.clear()   # (the braziers of an earlier duel would come back broken)
	GameSession.expansion = ExpansionState.defaults()
	var level := (load(GROVE) as PackedScene).instantiate() as Node3D
	level.set("stage", 0)
	world.add_child(level)
	var p := level.get_node("Player") as GiantPlayer
	await TestWait.until(self, func() -> bool: return p.is_on_floor(), 30)
	TitanDuel.prepare(p, stage)
	await TestWait.until(self, func() -> bool: return Sim.tick % 60 == 59, 70)   # (each duel on a whole second)
	Sim.reseed(Sim.DEFAULT_SEED)
	TitanDuel.prepare(p, stage)
	var t := level.get_node("Rootwarden") as TitanEnemy
	t.brain.rng.seed = seed_value
	p.global_position = Vector3(0, 0.05, 30)
	var arena := level.get_node("BossArena") as BossArena
	arena.disengage_s = 1.0e9   # (the duel is one attempt)
	arena.engage()
	var bot := TitanDuelBot.new()
	bot.see_obstacles = true   # (B5: his grove's trunks, braziers and resin pots)
	bot.setup(p, t, "expert", seed_value, true)
	return {"level": level, "player": p, "titan": t, "bot": bot}


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
	var by_action := {}
	var by_plate := {}
	for r in hits:
		if r.event.target_id == p.entity.entity_id and r.health_damage > 0:
			blows += 1
			var k := r.event.action_id.trim_prefix("ability.rootwarden_")
			by_action[k] = int(by_action.get(k, 0)) + r.health_damage
		elif r.event.target_id == t.entity_id and r.health_damage > 0:
			dealt += r.health_damage
			var key := "%s:%s" % [r.event.plate_id, r.event.plate_state]
			by_plate[key] = int(by_plate.get(key, 0)) + r.health_damage
	var regrown := 0
	var seared := 0
	for e: Array in t.regrow_log:
		regrown += 1 if str(e[1]) == "regrown" else 0
		seared += 1 if str(e[1]) == "seared" else 0
	var out := {"stage": stage, "seed": seed_value, "giant_health": giant_hp,
		"giant_died_s": snappedf(died_at / 60.0, 0.1) if died_at >= 0 else -1.0,
		"titan_killed_s": snappedf(killed_at / 60.0, 0.1) if killed_at >= 0 else -1.0,
		"blows_taken": blows, "titan_left": snappedf(t.entity.combatant.pools.ratio("health"), 0.001),
		"plates": Array(t.plates().ever_broken), "regrown": regrown, "seared": seared, "fires": t.fire_ignitions,
		"phase": t.brain.boss_phase(), "dealt": dealt, "dealt_by": by_plate, "hit_by": by_action,
		"topples": t.topples, "down_heavies": bot.down_heavies, "fire_s": snappedf(bot.fire_ticks / 60.0, 0.1),
		"evade_s": snappedf(bot.evade_ticks / 60.0, 0.1), "hugs": (t.brain as TitanBrain).hug_answers,
		"damage_taken": int(giant_hp - p.entity.combatant.pools.health) if p.entity.is_alive() else int(giant_hp)}
	print("B3_DUEL " + JSON.stringify(out))
	GameSession.expansion = ExpansionState.defaults()
	(s.level as Node).queue_free()
	await step_ticks(2)
	return out


func test_stage_4_giants_die() -> void:
	var died := 0
	var won := 0
	for seed_value: int in SEEDS:
		var d := await _duel(4, seed_value, 480.0)
		if float(d.giant_died_s) > 0.0:
			died += 1
		if float(d.titan_killed_s) > 0.0:
			won += 1
		assert_true(float(d.titan_left) > 0.4, "stage 4 seed %d: far from bringing him down (%.2f left)" % [seed_value,
			float(d.titan_left)])
	assert_true(died >= 2, "stage 4: deadly - the giant dies in most duels (%d of %d)" % [died, SEEDS.size()])
	assert_eq(won, 0, "stage 4: never a win")


func test_stage_5_giants_win_a_hard_fight() -> void:
	var won := 0
	for seed_value: int in SEEDS:
		var d := await _duel(5, seed_value, 600.0)
		if float(d.titan_killed_s) > 0.0:
			won += 1
			assert_true(float(d.titan_killed_s) >= 120.0, "stage 5 seed %d: a hard fight, not a rout (%.0f s)" % [
				seed_value, float(d.titan_killed_s)])
			assert_true(int(d.blows_taken) >= 3, "stage 5 seed %d: his blows land (%d)" % [seed_value,
				int(d.blows_taken)])
		assert_true((d.plates as Array).size() >= 1, "stage 5 seed %d: breaking his bark" % seed_value)
	assert_true(won >= 1, "stage 5: wins at least one duel of %d (%d)" % [SEEDS.size(), won])


func test_stage_6_giants_win_a_fair_fight() -> void:
	var won := 0
	var regrown := 0
	var seared := 0
	for seed_value: int in SEEDS:
		var d := await _duel(6, seed_value, 600.0)
		regrown += int(d.regrown)
		seared += int(d.seared)
		if float(d.titan_killed_s) > 0.0:
			won += 1
			assert_true(float(d.titan_killed_s) >= 90.0, "stage 6 seed %d: a fight of minutes (%.0f s)" % [seed_value,
				float(d.titan_killed_s)])
		assert_true(int(d.phase) == 2 or float(d.titan_killed_s) > 0.0, "stage 6 seed %d: he is uprooted" % seed_value)
	assert_true(won >= 2, "stage 6: the giant wins most duels (%d of %d)" % [won, SEEDS.size()])
	assert_true(seared >= 1, "fire seared a wound in the duels (%d)" % seared)


## The same seed fights the same first minute (every hit, the plates' stone and wounds, his sequence, the fire),
## another seed another.
func test_a_seeded_duel_repeats() -> void:
	var a := await _record(2)
	var b := await _record(2)
	var c := await _record(5)
	assert_true((a.hits as Array).size() > 10, "a real fight (%d hits)" % (a.hits as Array).size())
	assert_eq(a, b, "the same seed: the same fight, tick for tick")
	assert_true(a.hits != c.hits or a.log != c.log, "another seed: another fight")


func _record(seed_value: int) -> Dictionary:
	var s := await _setup(5, seed_value)
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
			r.event.plate_id, r.outcome, r.health_damage])
	var regrow: Array = []
	for e: Array in t.regrow_log:
		regrow.append([int(e[0]) - start, str(e[1]), str(e[2])])
	var out := {"hits": rec, "plates": t.plates().snapshot(), "log": Array((t.brain as TitanBrain).sequence_log),
		"regrow": regrow, "fires": t.fire_ignitions, "titan_at": t.global_position.snapped(Vector3.ONE * 0.001),
		"giant_at": p.global_position.snapped(Vector3.ONE * 0.001)}
	GameSession.expansion = ExpansionState.defaults()
	(s.level as Node).queue_free()
	await step_ticks(2)
	return out

