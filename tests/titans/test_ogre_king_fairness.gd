extends IntegrationSuite
## B2: the Ogre King's fight stays the first boss a new player meets (docs/BALANCE_LOG.md, "B2"; decision B2-2). Bot
## duels on the boss arena test level (P11a's Kingsfall arena at the origin), his AI on, a stage-2 giant readied as the
## Valley readies it (TitanDuel.prepare: the stage's level, the bots' attribute spending, the campaign's weapon), one
## attempt each, no respawn:
##   * the novice (BotCombat's novice: no titan rules, the lock's own pick - his bell at stage 2) keeps P11a's band:
##     against the King with his trophies it wins as often as against the same King with no plates (P11a's King:
##     the plates taken off, the lock back on his knees), in a like time and taking a like share of its health;
##   * aimed play is rewarded: the expert with the titan rules (the lock-switch's trophy struck in his recoveries,
##     his telegraphs evaded, heavies while he is down; not round to his back - he turns on it faster than it gets
##     there) wins, breaks a trophy in most duels and takes well under the novice's share of its health.
## Every duel is printed as one B2_DUEL line (the log's table). The titans' tier (B4; --gate runs it): minutes of simulated fighting.

const ARENA := "res://scenes/test/boss_arena_test.tscn"
const SEEDS := [1, 2, 3]
const STAGE := 2


func _duel(skill: String, aimed: bool, seed_value: int, plates: bool, max_s: float) -> Dictionary:
	await TestWait.duel_start(self)   # (B5: the same duel whatever ran before it)
	WorldState.clear()
	GameSession.expansion = ExpansionState.defaults()
	var level := (load(ARENA) as PackedScene).instantiate() as Node3D
	world.add_child(level)
	var p := level.get_node("Player") as GiantPlayer
	await TestWait.until(self, func() -> bool: return p.is_on_floor(), 60)
	TitanDuel.prepare(p, STAGE)
	await TestWait.until(self, func() -> bool: return Sim.tick % 60 == 59, 70)
	Sim.reseed(Sim.DEFAULT_SEED)
	var prep := TitanDuel.prepare(p, STAGE)
	var t := level.get_node("OgreKing") as TitanEnemy
	t.brain.rng.seed = seed_value
	if not plates:
		t.entity.plates = null   # (P11a's King: no trophies, the lock on his knees)
	p.global_position = Vector3(0, 0.05, -10)
	var arena := level.get_node("BossArena") as BossArena
	arena.engage()
	var bot := TitanDuelBot.new()
	bot.titan_rules = aimed
	bot.bait = aimed
	bot.round_to_back = false   # (he turns on a giant going round him faster than it gets there)
	bot.setup(p, t, skill, seed_value, aimed)
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
	var bot_ticks := {"flank": bot.flank_ticks, "evade": bot.evade_ticks, "down": bot.down_ticks, "baits": bot.baits}
	var blows := 0
	for r in hits:
		if r.event.target_id == p.entity.entity_id and r.health_damage > 0:
			blows += 1
	var out := {"skill": skill, "aimed": aimed, "plates": plates, "seed": seed_value, "level": int(prep.level),
		"weapon": str(prep.weapon), "giant_health": giant_hp,
		"giant_died_s": snappedf(died_at / 60.0, 0.1) if died_at >= 0 else -1.0,
		"king_killed_s": snappedf(killed_at / 60.0, 0.1) if killed_at >= 0 else -1.0,
		"blows_taken": blows, "king_left": snappedf(t.entity.combatant.pools.ratio("health"), 0.001),
		"broken": t.plate_breaks.duplicate(), "bot_ticks": bot_ticks, "topples": t.topples, "phase": t.brain.boss_phase(),
		"damage_taken": int(giant_hp - p.entity.combatant.pools.health) if p.entity.is_alive() else int(giant_hp)}
	print("B2_DUEL " + JSON.stringify(out))
	GameSession.expansion = ExpansionState.defaults()
	level.queue_free()
	await step_ticks(2)
	return out


func _sum(rows: Array) -> Dictionary:
	var won := 0
	var time := 0.0
	var taken := 0.0
	for d: Dictionary in rows:
		if float(d.king_killed_s) > 0.0:
			won += 1
			time += float(d.king_killed_s)
		taken += float(d.damage_taken) / maxf(float(d.giant_health), 1.0)
	return {"won": won, "time": time / maxf(float(won), 1.0), "taken": taken / maxf(float(rows.size()), 1.0)}


func test_a_novice_keeps_the_valley_fights_band() -> void:
	var with_rows: Array = []
	var without_rows: Array = []
	for seed_value: int in SEEDS:
		with_rows.append(await _duel("novice", false, seed_value, true, 240.0))
		without_rows.append(await _duel("novice", false, seed_value, false, 240.0))
	var a := _sum(with_rows)
	var b := _sum(without_rows)
	print("B2_BAND " + JSON.stringify({"with_trophies": a, "without": b}))
	assert_true(int(a.won) >= int(b.won), "the novice wins as often with his trophies (%d) as without (%d)" % [
		int(a.won), int(b.won)])
	if int(a.won) > 0 and int(b.won) > 0:
		assert_true(float(a.time) <= float(b.time) * 1.3 and float(a.time) >= float(b.time) * 0.6,
			"in a like time: %.0f s against %.0f s" % [float(a.time), float(b.time)])
	assert_true(float(a.taken) <= float(b.taken) * 1.3 + 0.05,
		"taking a like share of its health: %.2f against %.2f" % [float(a.taken), float(b.taken)])


func test_aimed_play_breaks_his_trophies_and_wins() -> void:
	var rows: Array = []
	var broke_in := 0
	var broken := 0
	var downs := 0
	for seed_value: int in SEEDS:
		var d := await _duel("expert", true, seed_value, true, 240.0)
		rows.append(d)
		broken += (d.broken as Array).size()
		broke_in += 1 if not (d.broken as Array).is_empty() else 0
		downs += int(d.topples)
	var s := _sum(rows)
	print("B2_AIMED " + JSON.stringify({"summary": s, "broken": broken, "downs": downs}))
	assert_true(int(s.won) >= 2, "the aimed expert wins most duels (%d of %d)" % [int(s.won), SEEDS.size()])
	assert_true(broke_in >= 2, "it breaks a trophy in most duels (%d of %d)" % [broke_in, SEEDS.size()])
	assert_true(float(s.taken) < 0.6, "it takes well under the novice's share of its health: %.2f" % float(s.taken))
