extends IntegrationSuite
## Ten seeded runs per boss (plan M6-M9 §5.13, §3.18 gate tier; P34). Each run reseeds the boss's brain
## and plays its fight with the AI on against a giant of the boss's stage who stands, takes no damage
## (status debug_invulnerable) and wears the boss down with regular blows. Every run checks:
##   * each boss phase happens exactly once per attempt - for the Matriarch and Harrok over a second
##     attempt after the disengage rule, for the battle over its three phases;
##   * no unseen instant damage: every blow that lands on the giant from an action with a windup of
##     0.8 s or more was announced by a telegraph of the same action (by the same actor, or for an arena
##     hazard at the same stone) before it struck;
##   * the endings: Harrok and Corvane yield and the prompt decides (Spare on even seeds, Strike on odd);
##     the Matriarch's second phase calls her whelps.
## Gate tier: tools/check.sh --gate (budget 8 minutes).

const DEN := "res://scenes/test/troll_den_test.tscn"
const MOOT := "res://scenes/test/moot_test.tscn"
const BAILEY := "res://scenes/test/bailey_test.tscn"
const BB := preload("res://tools/builders/big.gd")
const SEEDS := [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]
const TELEGRAPH_MIN_WINDUP_TICKS := 48

var telegraphs: Array = []   # [tick, actor_id, action_id, origin]


func before_each() -> void:
	await super()
	telegraphs.clear()
	WorldState.clear()
	Events.telegraph_started.connect(_on_tel)


func after_each() -> void:
	if Events.telegraph_started.is_connected(_on_tel):
		Events.telegraph_started.disconnect(_on_tel)
	Quests.end_dialogue()
	await super()


func _on_tel(tick: int, actor_id: String, action_id: String, _t: String, _s: String, origin: Vector3,
		_y: float, _r: float, _l: float, _d: float) -> void:
	telegraphs.append([tick, actor_id, action_id, origin])


## The level with its giant at `stage` (the boss's own: the Matriarch 5, Harrok 6, the battle 5),
## standing on the floor and taking no damage.
func _level(path: String, stage: int) -> Node3D:
	var level := (load(path) as PackedScene).instantiate() as Node3D
	world.add_child(level)
	var p := level.get_node("Player") as GiantPlayer
	p.router.use_injection = true
	await TestWait.until(self, func() -> bool: return p.is_on_floor(), 30)
	assert_true(p.growth.debug_set_stage(stage).ok, "%s: the giant at stage %d" % [path.get_file(), stage])
	p.entity.apply_status("status.debug_invulnerable", NAN, 3600.0, "test")
	return level


func _blow(target: EnemyActor, amount: float) -> void:
	var h := HitEvent.new()
	h.tick = Sim.tick
	h.instance_id = Sim.new_instance_id()
	h.attacker_id = "player"
	h.target_id = target.entity_id
	h.power = amount
	h.attacker_stat = 0.0
	h.size_policy = "none"
	h.damage_split = {"fire": 1.0}   # (no armour in the way: the amount is what the giant meant)
	h.tags = PackedStringArray(["Melee", "Unblockable", "Unparryable"])
	h.attacker_position = target.global_position + Vector3(0, 0, 6)
	Sim.queue_hit(h)


## Every blow that landed on the giant (actor in `actors`) from an action with a long windup was
## telegraphed before it struck; returns how many were checked.
func _check_telegraphed(p: GiantPlayer, actors: Array, label: String) -> int:
	var checked := 0
	for r in hits_on(p.entity.entity_id):
		var a := GameData.get_action(r.event.action_id)
		if a == null or not actors.has(r.event.attacker_id) or a.windup_ticks < TELEGRAPH_MIN_WINDUP_TICKS:
			continue
		checked += 1
		var seen := false
		for t: Array in telegraphs:
			if str(t[2]) != a.id or int(t[0]) > r.event.tick:
				continue
			if r.event.tick - int(t[0]) > a.windup_ticks + a.active_ticks + 6:
				continue
			if str(t[1]) == r.event.attacker_id or str(t[1]).begins_with(r.event.attacker_id + "#"):
				seen = true
				break
		assert_true(seen, "%s: %s's %s at tick %d was telegraphed" % [label, r.event.attacker_id, a.id, r.event.tick])
	return checked


func _attempt_once(phases: Array[int], label: String) -> void:
	var seen := {}
	for ph in phases:
		assert_false(seen.has(ph), "%s: phase %d only once in the attempt" % [label, ph])
		seen[ph] = true


func test_the_matriarch_ten_seeds() -> void:
	var checked := 0
	for seed_value: int in SEEDS:
		var level := await _level(DEN, 5)
		var p := level.get_node("Player") as GiantPlayer
		var m := level.get_node("TrollMatriarch") as TrollEnemy
		var arena := level.get_node("BossArena") as BossArena
		m.brain.rng.seed = seed_value
		p.global_position = Vector3(0, 0.05, 2)
		arena.disengage_s = 0.25
		hits.clear()
		telegraphs.clear()
		for attempt_no in 2:
			arena.engage()
			for i in 7:
				_blow(m, 300.0)   # (375 fire to a troll's skin, less her regeneration: to about a quarter)
				await step_ticks(45)
			assert_true(m.entity.is_alive(), "seed %d attempt %d: alive" % [seed_value, attempt_no + 1])
			assert_eq(m.attempt_phases, [2] as Array[int], "seed %d attempt %d: the second phase once" % [seed_value, attempt_no + 1])
			_attempt_once(m.attempt_phases, "seed %d" % seed_value)
			assert_true(m.summoned.size() >= 1, "seed %d: her roar called whelps" % seed_value)
			if attempt_no == 0:
				p.global_position = Vector3(0, 0.05, 60)
				await step_ticks(25)
				assert_eq(m.attempt, 2, "seed %d: the disengage rule began a new attempt" % seed_value)
				p.global_position = Vector3(0, 0.05, 2)
		var actors: Array = [BB.DEN_ID]
		for node in get_tree().get_nodes_in_group("enemies"):
			actors.append((node as EnemyActor).entity_id)
		checked += _check_telegraphed(p, actors, "matriarch seed %d" % seed_value)
		level.queue_free()
		await step_ticks(2)
	assert_true(checked > 0, "the Matriarch's telegraphed blows did land on the giant (%d checked)" % checked)


func test_harrok_ten_seeds() -> void:
	var checked := 0
	for seed_value: int in SEEDS:
		var level := await _level(MOOT, 6)
		var p := level.get_node("Player") as GiantPlayer
		var h := level.get_node("Harrok") as RivalGiantEnemy
		var arena := level.get_node("BossArena") as BossArena
		h.brain.rng.seed = seed_value
		p.global_position = Vector3(0, 0.05, 0)
		arena.disengage_s = 0.25
		hits.clear()
		telegraphs.clear()
		# Each blow is 8 % of his health (P34's 400 of 5,000: P39's balance pass took his health to 3,400, and
		# seven blows of 400 then reached his yield), so the fight keeps its length and his blows their time.
		var amount := 400.0 * h.entity.combatant.pools.health_max / 5000.0
		# Attempt 1: down to phase 2, then away.
		arena.engage()
		for i in 7:
			_blow(h, amount)
			await step_ticks(50)
		assert_false(h.yielded, "seed %d: phase 2 before his yield" % seed_value)
		assert_eq(h.attempt_phases, [2] as Array[int], "seed %d: phase 2 once in attempt 1" % seed_value)
		p.global_position = Vector3(0, 0.05, 100)
		await step_ticks(25)
		assert_eq(h.attempt, 2, "seed %d: a new attempt" % seed_value)
		assert_eq(h.brain.boss_phase(), 1, "seed %d: back at phase 1" % seed_value)
		p.global_position = Vector3(0, 0.05, 0)
		# Attempt 2: to the yield.
		arena.engage()
		var guard := 0
		while not h.yielded and guard < 30:
			_blow(h, amount)
			await step_ticks(40)
			guard += 1
		assert_true(h.yielded, "seed %d: he yields" % seed_value)
		assert_eq(h.attempt_phases, [2] as Array[int], "seed %d: phase 2 once in attempt 2" % seed_value)
		assert_true(h.entity.combatant.pools.ratio("health") >= 0.25 - 1e-4, "seed %d: never below his yield" % seed_value)
		checked += _check_telegraphed(p, [BB.MOOT_ID], "harrok seed %d" % seed_value)
		if seed_value % 2 == 0:
			assert_true(h.p34_decide("spare"), "seed %d: Spare" % seed_value)
			await step_ticks(2)
			assert_eq(WorldState.get_flag("boss.harrok.outcome"), "spared", "seed %d: spared" % seed_value)
			assert_true(arena.is_defeated(), "seed %d: the duel is won" % seed_value)
		else:
			assert_true(h.p34_decide("strike"), "seed %d: Strike" % seed_value)
			_blow(h, 1.0e7)
			await step_ticks(2)
			assert_false(h.entity.is_alive(), "seed %d: fought to the death" % seed_value)
			assert_eq(WorldState.get_flag("boss.harrok.outcome"), "slain", "seed %d: slain" % seed_value)
		level.queue_free()
		await step_ticks(2)
		WorldState.clear()
	assert_true(checked > 0, "Harrok's telegraphed blows did land on the giant (%d checked)" % checked)


func test_the_iron_regiment_ten_seeds() -> void:
	for seed_value: int in SEEDS:
		var level := await _level(BAILEY, 5)
		var p := level.get_node("Player") as GiantPlayer
		var battle := level.get_node("BattleBoss") as BattleBoss
		var d := level.get_node("EncounterDirector") as EncounterDirector
		p.global_position = Vector3(0, 0.05, 30)
		hits.clear()
		telegraphs.clear()
		battle.engage()
		await step_ticks(30)
		var rng := RandomNumberGenerator.new()
		rng.seed = seed_value
		var guard := 0
		while not battle.surrendered and battle.state_name() == "engaged" and guard < 80:
			guard += 1
			var alive: Array = []
			for enc_id in ["encounter.bailey_test_wall", "encounter.bailey_test_charge", "encounter.bailey_test_stand"]:
				for id in d.members_of(enc_id):
					var e := Sim.get_entity(id)
					if e != null and e.is_alive() and id != "test.bailey.corvane":
						alive.append(id)
			if alive.is_empty():
				await step_ticks(10)
				continue
			var pick: String = alive[rng.randi_range(0, alive.size() - 1)]
			_blow(Sim.get_entity(pick).actor as EnemyActor, 1.0e6)
			await step_ticks(12)
		assert_eq(battle.phase_log, [1, 2, 3] as Array[int], "seed %d: each phase once" % seed_value)
		assert_true(battle.surrendered, "seed %d: Corvane yields when his guard breaks" % seed_value)
		var actors: Array = []
		for enc_id in ["encounter.bailey_test_wall", "encounter.bailey_test_charge", "encounter.bailey_test_stand"]:
			actors.append_array(d.members_of(enc_id))
		_check_telegraphed(p, actors, "battle seed %d" % seed_value)
		var c := Sim.get_entity("test.bailey.corvane").actor as EnemyActor
		if seed_value % 2 == 0:
			assert_true(c.p34_decide("spare"), "seed %d: Spare" % seed_value)
			await step_ticks(2)
			assert_eq(WorldState.get_flag("boss.corvane.outcome"), "spared", "seed %d: spared" % seed_value)
		else:
			assert_true(c.p34_decide("strike"), "seed %d: Strike" % seed_value)
			await step_ticks(2)
			assert_eq(WorldState.get_flag("boss.corvane.outcome"), "slain", "seed %d: slain" % seed_value)
		assert_true(battle.is_defeated(), "seed %d: the battle ends" % seed_value)
		level.queue_free()
		await step_ticks(2)
		WorldState.clear()
