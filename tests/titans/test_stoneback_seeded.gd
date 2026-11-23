extends IntegrationSuite
## A2: Stoneback's fight is deterministic. A seeded duel (the titan's AI on, a stage-5 giant played by
## TitanDuelBot, 60 simulated seconds) run twice gives the same record tick for tick: every hit (tick, attacker,
## action, target, region, plate, outcome, damage), every plate's stone, the plates' break order, the brain's
## sequence log and both bodies' places. A different brain seed is a different fight (the record is not empty or
## constant). And, as test_bosses_seeded does for the other bosses, every blow of his that landed with a windup of
## 0.8 s or more was telegraphed by his own telegraph before it struck.
## B5 (G11): the same duel run after another titan's fight in the same process (the Ogre King's, in his arena) is
## still the same fight tick for tick - nothing of an earlier fight survives into the next (TestWait.duel_start; the
## aim deferral's stale swings, HitFactory._prune_deferred). A2's warm-up duel is gone: the first duel of the process
## is the fight the later ones are.

const QUARRY := "res://scenes/test/quarry_test.tscn"
const KING_ARENA := "res://scenes/test/boss_arena_test.tscn"
const SECONDS := 60.0
const TELEGRAPH_MIN_WINDUP_TICKS := 48

var tels: Array = []


func _on_tel(tick: int, actor_id: String, action_id: String, _t: String, _s: String, _o: Vector3, _y: float,
		_r: float, _l: float, _d: float) -> void:
	tels.append([tick, actor_id, action_id])


func _run(seed_value: int) -> Dictionary:
	await TestWait.duel_start(self)   # (B5: the same duel whatever ran before it)
	WorldState.clear()   # (a palisade broken in an earlier run would come back broken)
	var level := (load(QUARRY) as PackedScene).instantiate() as Node3D
	level.set("stage", 0)
	world.add_child(level)
	var p := level.get_node("Player") as GiantPlayer
	await TestWait.until(self, func() -> bool: return p.is_on_floor(), 30)
	TitanDuel.prepare(p, 5)
	var t := level.get_node("Stoneback") as TitanEnemy
	# (the actors perceive and decide on ticks of their own phase: each run starts on a whole second of Sim's clock)
	await TestWait.until(self, func() -> bool: return Sim.tick % 60 == 59, 70)
	Sim.reseed(Sim.DEFAULT_SEED)
	TitanDuel.prepare(p, 5)
	t.brain.rng.seed = seed_value
	p.global_position = Vector3(0, 0.05, 22)
	(level.get_node("BossArena") as BossArena).engage()
	var bot := TitanDuelBot.new()
	bot.setup(p, t, "expert", seed_value, true)
	hits.clear()
	tels.clear()
	var start := Sim.tick
	while Sim.tick - start < int(SECONDS * 60.0) and p.entity.is_alive() and t.entity.is_alive():
		bot.step(Sim.tick)
		await step_ticks(1)
	bot.teardown()
	var rec: Array = []
	for r in hits:
		rec.append([r.event.tick - start, r.event.attacker_id, r.event.action_id, r.event.target_id, r.event.region,
			r.event.plate_id, r.outcome, r.health_damage, snappedf(r.poise_damage, 0.001)])
	var telegraphed := 0
	for r in hits_on(p.entity.entity_id):
		var a := GameData.get_action(r.event.action_id)
		if a == null or a.windup_ticks < TELEGRAPH_MIN_WINDUP_TICKS or r.event.attacker_id != t.entity_id:
			continue
		var seen := false
		for tl: Array in tels:
			if str(tl[1]) == t.entity_id and str(tl[2]) == a.id and int(tl[0]) <= r.event.tick \
					and r.event.tick - int(tl[0]) <= a.windup_ticks + a.active_ticks + 400:
				seen = true
				break
		assert_true(seen, "seed %d: his %s at tick %d was telegraphed" % [seed_value, a.id, r.event.tick])
		telegraphed += 1
	var out := {"hits": rec, "plates": t.plates().snapshot(), "breaks": Array(t.plate_breaks),
		"log": Array(t.brain.sequence_log), "titan": [snappedf(t.global_position.x, 0.001), snappedf(t.global_position.z, 0.001)],
		"giant": [snappedf(p.global_position.x, 0.001), snappedf(p.global_position.z, 0.001)],
		"health": [t.entity.combatant.pools.health, p.entity.combatant.pools.health], "telegraphed": telegraphed}
	level.queue_free()
	await step_ticks(2)
	return out


## B5: a stage-2 giant's duel with the Ogre King in his arena (the novice; B2's fairness duel), to its end.
func _king_duel(seed_value: int) -> Dictionary:
	await TestWait.duel_start(self)
	WorldState.clear()
	var level := (load(KING_ARENA) as PackedScene).instantiate() as Node3D
	world.add_child(level)
	var p := level.get_node("Player") as GiantPlayer
	await TestWait.until(self, func() -> bool: return p.is_on_floor(), 60)
	TitanDuel.prepare(p, 2)
	await TestWait.until(self, func() -> bool: return Sim.tick % 60 == 59, 70)
	Sim.reseed(Sim.DEFAULT_SEED)
	TitanDuel.prepare(p, 2)
	var t := level.get_node("OgreKing") as TitanEnemy
	t.brain.rng.seed = seed_value
	p.global_position = Vector3(0, 0.05, -10)
	(level.get_node("BossArena") as BossArena).engage()
	var bot := TitanDuelBot.new()
	bot.round_to_back = false
	bot.setup(p, t, "novice", seed_value, false)
	hits.clear()
	var start := Sim.tick
	while Sim.tick - start < 120 * 60 and p.entity.is_alive() and t.entity.is_alive():
		bot.step(Sim.tick)
		await step_ticks(1)
	bot.teardown()
	var out := {"blows": hits.size(), "giant_alive": p.entity.is_alive(), "king_left": t.entity.combatant.pools.ratio("health")}
	level.queue_free()
	await step_ticks(2)
	return out


func test_a_seeded_duel_repeats_tick_for_tick() -> void:
	Events.telegraph_started.connect(_on_tel)
	var a := await _run(3)
	var b := await _run(3)
	# (A4: seeds 3 and 7 fight the same first minute - his downs set when he strikes next, not his pause's roll;
	# seed 4 does not)
	var c := await _run(4)
	Events.telegraph_started.disconnect(_on_tel)
	assert_true((a.hits as Array).size() > 10, "the duel struck blows (%d)" % (a.hits as Array).size())
	assert_eq(JSON.stringify(a), JSON.stringify(b), "the same seed, the same fight")
	assert_true(JSON.stringify(a) != JSON.stringify(c), "another seed, another fight")
	assert_true(int(a.telegraphed) + int(c.telegraphed) > 0, "his telegraphed blows landed (%d checked)" % [
		int(a.telegraphed) + int(c.telegraphed)])


## B5 (G11): Stoneback's seeded duel, then the Ogre King's fight to its end, then the same duel again: tick for tick the
## same (every hit, his plates, his sequence, both bodies' places). Before B5 the second differed from the first: the
## duel waited for its whole second after its level was loaded, so the earlier fight's length set how many ticks his
## AI hunted the giant before the duel began.
func test_the_same_duel_after_another_titans_fight() -> void:
	Events.telegraph_started.connect(_on_tel)
	var alone := await _run(3)
	var king := await _king_duel(2)
	var after := await _run(3)
	Events.telegraph_started.disconnect(_on_tel)
	assert_true(int(king.blows) > 10, "the King's fight was fought (%d blows; the giant %s, him at %.2f)" % [
		int(king.blows), "alive" if bool(king.giant_alive) else "dead", float(king.king_left)])
	assert_true((alone.hits as Array).size() > 10, "the duel struck blows (%d)" % (alone.hits as Array).size())
	assert_eq(JSON.stringify(after), JSON.stringify(alone), "after the King's fight, the same duel tick for tick")


## B5 (G11): the aim deferral keeps no swing of an earlier fight: a held-back swing older than its keep is dropped the
## next time one is held back (A2 cleared them all at 64, at a moment the earlier fights' stale swings decided).
func test_the_aim_deferral_drops_old_swings() -> void:
	var cand := {"entity": null, "hurtbox": null, "point": Vector3.ZERO, "substep": 0, "distance": 1.0, "weak_point": false}
	var far := {"aim": 99.0, "cand": cand}
	var t0 := Sim.tick + 100000   # (later than every swing the duels above held back)
	for i in 20:
		HitFactory._aimed_swing("test.b5.old", 900000 + i, t0, far)
	assert_eq(HitFactory.deferred_count(), 20, "twenty swings held back (the duels' older ones dropped)")
	var later := t0 + HitFactory.DEFERRED_KEEP_TICKS + 1
	HitFactory._aimed_swing("test.b5.new", 900100, later, far)
	assert_eq(HitFactory.deferred_count(), 1, "every older one dropped, the new one held (%d)" % HitFactory.deferred_count())
	assert_eq(HitFactory._aimed_swing("test.b5.new", 900100, later + HitFactory.AIM_DEFER_TICKS, far), cand,
		"it lands after its delay")
	assert_eq(HitFactory.deferred_count(), 0, "and is gone")
