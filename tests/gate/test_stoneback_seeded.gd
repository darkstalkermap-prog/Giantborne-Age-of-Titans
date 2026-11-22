extends IntegrationSuite
## A2: Stoneback's fight is deterministic. A seeded duel (the titan's AI on, a stage-5 giant played by
## TitanDuelBot, 60 simulated seconds) run twice gives the same record tick for tick: every hit (tick, attacker,
## action, target, region, plate, outcome, damage), every plate's stone, the plates' break order, the brain's
## sequence log and both bodies' places. A different brain seed is a different fight (the record is not empty or
## constant). And, as test_bosses_seeded does for the other bosses, every blow of his that landed with a windup of
## 0.8 s or more was telegraphed by his own telegraph before it struck.

const QUARRY := "res://scenes/test/quarry_test.tscn"
const SECONDS := 60.0
const TELEGRAPH_MIN_WINDUP_TICKS := 48

var tels: Array = []


func _on_tel(tick: int, actor_id: String, action_id: String, _t: String, _s: String, _o: Vector3, _y: float,
		_r: float, _l: float, _d: float) -> void:
	tels.append([tick, actor_id, action_id])


func _run(seed_value: int) -> Dictionary:
	WorldState.clear()   # (a palisade broken in an earlier run would come back broken)
	Sim.reseed(Sim.DEFAULT_SEED)
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


func test_a_seeded_duel_repeats_tick_for_tick() -> void:
	Events.telegraph_started.connect(_on_tel)
	# A warm-up duel first: whatever the earlier suites left warm or cold (first-use prompts, loaded resources)
	# is spent before the two runs that are compared (alone the suite passes without it; in the gate tier the first
	# duel of the process differed).
	await _run(5)
	var a := await _run(3)
	var b := await _run(3)
	var c := await _run(7)
	Events.telegraph_started.disconnect(_on_tel)
	assert_true((a.hits as Array).size() > 10, "the duel struck blows (%d)" % (a.hits as Array).size())
	assert_eq(JSON.stringify(a), JSON.stringify(b), "the same seed, the same fight")
	assert_true(JSON.stringify(a) != JSON.stringify(c), "another seed, another fight")
	assert_true(int(a.telegraphed) + int(c.telegraphed) > 0, "his telegraphed blows landed (%d checked)" % [
		int(a.telegraphed) + int(c.telegraphed)])
