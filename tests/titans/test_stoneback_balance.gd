extends IntegrationSuite
## A2: the balance evidence for Stoneback (docs/BALANCE_LOG.md, "A2", "A3", "A4"): bot-driven duels in the quarry test
## arena, the titan's AI on, a giant readied for each stage (TitanDuel.prepare: the stage's required level, the bots'
## attribute spending, the campaign's weapon) and played by TitanDuelBot - BotCombat's expert (its dodges and parries,
## the lock, the light chain and heavies, the abilities by rule) plus the titan rules a skilled player follows (round
## to his back while he reels or recovers; A3: bait his charge into stone; A4: strike his shins in his recoveries,
## and while he is down on a knee walk in and land heavies on his lowered plates, backing away as he rises). One
## attempt each, no respawn. A4's claims (the owner's):
##   * stage 3: never wins (dead in most duels, having barely hurt him);
##   * stage 4: at most a rare win (dead in most duels);
##   * stage 5: wins at least one duel of three, in a hard fight (minutes, his blows taken);
##   * stage 6: wins most duels, in about three to five minutes.
## Every duel is printed as one A2_DUEL line (the log's table). The titans' tier (B4; --gate runs it): minutes of simulated fighting.

const QUARRY := "res://scenes/test/quarry_test.tscn"

const SEEDS := [1, 2, 3]


func _duel(stage: int, skill: String, flank: bool, seed_value: int, max_s: float, armour: Array = []) -> Dictionary:
	await TestWait.duel_start(self)   # (B5: the same duel whatever ran before it)
	WorldState.clear()   # (the palisades of an earlier duel would come back broken)
	GameSession.expansion = ExpansionState.defaults()
	var level := (load(QUARRY) as PackedScene).instantiate() as Node3D
	level.set("stage", 0)
	TestWait.duel_host(world).add_child(level)   # (B5: its own physics space)
	var p := level.get_node("Player") as GiantPlayer
	await TestWait.until(self, func() -> bool: return p.is_on_floor(), 30)
	TitanDuel.prepare(p, stage)
	await TestWait.until(self, func() -> bool: return Sim.tick % 60 == 59, 70)   # (each duel on a whole second)
	Sim.reseed(Sim.DEFAULT_SEED)
	var prep := TitanDuel.prepare(p, stage)
	# B1: the armour worn for the duel (none: A4's and A5's duels exactly)
	if not armour.is_empty():
		GameSession.expansion.equipment = Armour.equipment_with(armour)
		Armour.refresh_player(p)
	var t := level.get_node("Stoneback") as TitanEnemy
	t.brain.rng.seed = seed_value
	p.global_position = Vector3(0, 0.05, 22)
	var arena := level.get_node("BossArena") as BossArena
	arena.disengage_s = 1.0e9   # (the duel is one attempt: a knock-back out of the bowl ends no attempt here)
	arena.engage()
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
		"attempts": t.attempt, "reels": t.wall_stops, "flank_s": snappedf(bot.flank_ticks / 60.0, 0.1),
		"evade_s": snappedf(bot.evade_ticks / 60.0, 0.1), "hit_by": by_action,
		"baited_s": snappedf(bot.baits / 60.0, 0.1), "topples": t.topples, "down_s": snappedf(bot.down_ticks / 60.0, 0.1),
		"down_heavies": bot.down_heavies, "armour": armour.size(),
		"damage_taken": int(giant_hp - p.entity.combatant.pools.health) if p.entity.is_alive() else int(giant_hp)}
	print("A2_DUEL " + JSON.stringify(out))
	GameSession.expansion = ExpansionState.defaults()
	level.get_parent().queue_free()
	await step_ticks(2)
	return out


func test_stage_3_and_4_giants_die_fast() -> void:
	for stage: int in [3, 4]:
		var died := 0
		var won := 0
		for seed_value: int in SEEDS:
			var d := await _duel(stage, "expert", true, seed_value, 600.0)
			if float(d.giant_died_s) > 0.0:
				died += 1
				assert_true(int(d.blows_taken) <= 8, "stage %d seed %d: in a few of his blows (%d)" % [stage, seed_value,
					int(d.blows_taken)])
			if float(d.titan_killed_s) > 0.0:
				won += 1
			if stage == 3:
				assert_true(float(d.titan_left) > 0.6, "stage 3 seed %d: having barely hurt him (%.2f left)" % [seed_value,
					float(d.titan_left)])
		assert_true(died >= 2, "stage %d: the giant dies in most duels (%d of %d)" % [stage, died, SEEDS.size()])
		if stage == 3:
			assert_eq(won, 0, "stage 3: never a win")
		else:
			assert_true(won <= 1, "stage 4: at most a rare win (%d of %d)" % [won, SEEDS.size()])


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


## A4: stage 5 wins by fighting like a giant - his shins broken, he goes down on a knee, the heavies land on his
## lowered plates - in at least one duel of three, a hard fight of minutes in which his blows still land.
func test_stage_5_giants_win_by_toppling_him() -> void:
	var won := 0
	var downs := 0
	for seed_value: int in SEEDS:
		var d := await _duel(5, "expert", true, seed_value, 600.0)
		downs += int(d.topples)
		if float(d.titan_killed_s) > 0.0:
			won += 1
			assert_true(float(d.titan_killed_s) >= 120.0, "stage 5 seed %d: a hard fight, not a rout (%.0f s)" % [
				seed_value, float(d.titan_killed_s)])
			assert_true(int(d.blows_taken) >= 3, "stage 5 seed %d: his blows still land (%d)" % [seed_value,
				int(d.blows_taken)])
		assert_true(int(d.topples) >= 1, "stage 5 seed %d: it drops him to a knee" % seed_value)
		assert_true((d.plates as Array).has("shin_l") or (d.plates as Array).has("shin_r"),
			"stage 5 seed %d: by a shin plate" % seed_value)
	assert_true(won >= 1, "stage 5: wins at least one duel of %d (%d)" % [SEEDS.size(), won])
	assert_true(downs >= SEEDS.size() * 3, "stage 5: he goes down again and again (%d downs)" % downs)


## B1: a stage-6 giant in the full Quarry set fights the same duels (he is dead by then in a real save: this measures
## the armour for the next titans' tuning, docs/BALANCE_LOG.md "B1"). The armour turns about a fifth of each blow and
## its poise keeps the giant on its feet more; its weight slows the stamina the bot's heavies spend. It must still
## win most duels, take no more blows' damage a blow than without it, and the fights stay minutes long.
func test_stage_6_in_the_quarry_set() -> void:
	var won := 0
	var per_blow_bare := 0.0
	var per_blow_quarry := 0.0
	for seed_value: int in SEEDS:
		var bare := await _duel(6, "expert", true, seed_value, 600.0)
		var d := await _duel(6, "expert", true, seed_value, 600.0, Armour.set_pieces("armour_set.quarry"))
		if float(d.titan_killed_s) > 0.0:
			won += 1
		per_blow_bare += float(bare.damage_taken) / maxf(1.0, float(bare.blows_taken))
		per_blow_quarry += float(d.damage_taken) / maxf(1.0, float(d.blows_taken))
	assert_true(won >= 2, "stage 6 in the Quarry set still wins most duels (%d of %d)" % [won, SEEDS.size()])
	assert_true(per_blow_quarry < per_blow_bare, "his blows land lighter on the armour (%.0f against %.0f a blow)" % [
		per_blow_quarry / SEEDS.size(), per_blow_bare / SEEDS.size()])

