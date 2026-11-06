extends IntegrationSuite
## P30 (plan M6-M9 §2.10, §3.13 tests, decision 19): formations in play, on hand-made formations
## (no director; the test calls Formation.update as the director does, ten times a second).
##   * The banner: while it lives a member loses half the morale of ally deaths and awe; its death
##     is the commander's death for the members only (a soldier outside the formation is untouched)
##     and the formation announces banner_fell once.
##   * The brace: a braced front rank of five files runs one band pulse at a stage-4 giant in front
##     of it - one band telegraph, one melee token on the giant held by the one striker, at most one
##     hit per pulse whatever the band overlaps - and the other members only pose.
##   * Shields block lights and break on heavies and on stomps and sweeps (AoE).
##   * At stage 4 an outmatched soldier joins a formation of its faction with a free slot within
##     40 m, and one with no formation in reach flees and routs.

const PIKEMAN := "res://scenes/enemies/pikeman.tscn"
const SHIELDMAN := "res://scenes/enemies/shieldman.tscn"
const BANNERMAN := "res://scenes/enemies/bannerman.tscn"

var changes: Array = []


func before_each() -> void:
	await super()
	changes.clear()
	Events.formation_changed.connect(_on_formation_changed)


func after_each() -> void:
	if Events.formation_changed.is_connected(_on_formation_changed):
		Events.formation_changed.disconnect(_on_formation_changed)
	for f in Formation.live():
		f.dissolve()
	await super()


func _on_formation_changed(_tick: int, formation_id: String, state: String) -> void:
	changes.append([formation_id, state])


## A formation of `files` x `ranks` pikemen (`count` of them, slots 0..count-1) facing +Z at
## `pivot`, AI off; with a bannerman when `with_banner`.
func _formation(id: String, pivot: Vector3, files: int, ranks: int, count: int, with_banner: bool,
		scene := PIKEMAN) -> Formation:
	var f := Formation.new()
	f.id = id
	f.kind = "pike"
	f.display_name = "Pike Regiment"
	f.ranks = ranks
	f.files = files
	f.rank_spacing_m = 1.6
	f.file_spacing_m = 1.4
	f.brace_m = 7.0
	f.brace_action = "ability.formation_brace_pike"
	f.place(pivot, PI)
	Formation.register(f)
	for i in count:
		f.add_member(TestSpawn.enemy(world, scene, f.slot_position(i), "%s_%d" % [id, i], false, PI), i)
	if with_banner:
		f.set_banner(TestSpawn.enemy(world, BANNERMAN, f.slot_position(Formation.BANNER_SLOT), "%s_banner" % id, false, PI))
	return f


## A stage-4 giant at `pos`, facing -Z.
func _stage_4_giant(pos: Vector3) -> GiantPlayer:
	var p := spawn_player(pos, 0.0)
	await TestWait.until(self, func() -> bool: return p.is_on_floor(), 30)
	assert_true(bool(p.growth.debug_set_stage(4).ok), "a stage-4 giant")
	return p


func _update(f: Formation, threat: Node3D) -> void:
	f.update(Sim.tick, threat)


func test_the_banner_halves_losses_and_its_death_breaks_morale_for_members_only() -> void:
	var f := _formation("test.banner", Vector3(0, 0, -10), 3, 1, 3, true)
	var outsider := TestSpawn.enemy(world, PIKEMAN, Vector3(30, 0.05, -10), "test.outsider", false)
	await step_ticks(1)
	_update(f, null)
	var m: EnemyActor = f.members[0]
	assert_near(m.brain.morale, Formation.DEFAULT_MORALE, 0.01, "a member starts at the formation's 90")
	m.brain.apply_morale(-10.0, "ally_died", Sim.tick)
	assert_near(m.brain.morale, Formation.DEFAULT_MORALE - 5.0, 0.01, "the banner halves an ally-death loss")
	m.brain.apply_morale(-10.0, "awe", Sim.tick)
	assert_near(m.brain.morale, Formation.DEFAULT_MORALE - 10.0, 0.01, "and an awe loss")
	var others := {}
	for e: EnemyActor in f.members:
		others[e.entity_id] = e.brain.morale
	var outsider_before := outsider.brain.morale
	queue_hit("player", f.banner.entity_id, Vector3(0, 0, 10), 100000.0)
	await step_ticks(1)
	assert_false(f.banner_alive(), "the banner fell")
	for e: EnemyActor in f.members:
		assert_true(e.brain.morale < float(others[e.entity_id]) - 20.0,
			"%s takes it as its commander's death (%.1f -> %.1f)" % [e.entity_id, others[e.entity_id], e.brain.morale])
	assert_near(outsider.brain.morale, outsider_before, 0.01, "a soldier outside the formation is untouched")
	_update(f, null)
	_update(f, null)
	var fell := 0
	for c: Array in changes:
		if c[0] == "test.banner" and c[1] == "banner_fell":
			fell += 1
	assert_eq(fell, 1, "banner_fell is announced once")
	m.brain.apply_morale(-10.0, "ally_died", Sim.tick)
	var before := m.brain.morale + 10.0
	assert_near(m.brain.morale, before - 10.0, 0.01, "without its banner a member loses the whole")


func test_a_braced_front_rank_strikes_once_per_pulse_with_one_token_and_one_band() -> void:
	# a quicker brace than the shipped one (the default tier's time budget): the counts are the test
	TestFixtures.record_override("ability.formation_brace_pike", {"windup_s": 0.2, "recovery_s": 0.2})
	var p := await _stage_4_giant(Vector3(0, 0.05, 6))
	var f := _formation("test.brace", Vector3(0, 0, 0), 5, 1, 5, false)
	for e: EnemyActor in f.members:
		e.brain.aware = true
	var pid := p.entity.entity_id
	var telegraphs: Array = []
	var on_tele := func(_t: int, actor_id: String, action_id: String, _target: String, shape: String,
			_origin: Vector3, _yaw: float, _w: float, _l: float, _d: float) -> void:
		if action_id == f.brace_action:
			telegraphs.append([actor_id, shape])
	Events.telegraph_started.connect(on_tele)
	await step_ticks(1)
	_update(f, p)
	assert_eq(f.state, "braced", "the giant 6 m in front of the rank: braced")
	var striker := f.brace_holder()
	assert_true(striker != null, "one member runs the brace")
	assert_eq(f.slot_for(striker) / f.files, 0, "from the front rank")
	assert_eq(Sim.token_holders(pid), [striker.entity_id], "holding one of the giant's melee tokens")
	var brace_hits := 0
	var most_tokens := 0
	var token_after := -1
	for i in 36:
		await step_ticks(1)
		if i % Formation.UPDATE_TICKS == 0:
			_update(f, p)
		for r: HitResult in hits:
			if r.event.target_id == pid and r.event.attacker_id == striker.entity_id:
				brace_hits += 1
		hits.clear()
		if f.brace_count == 1:
			most_tokens = maxi(most_tokens, Sim.token_holders(pid).size())
			if not f.brace_running() and token_after < 0:
				_update(f, p)   # the formation gives the token back at its next update
				token_after = Sim.token_holders(pid).size()
	Events.telegraph_started.disconnect(on_tele)
	assert_eq(most_tokens, 1, "never more than the one token during the pulse")
	assert_eq(token_after, 0, "given back when the pulse ends")
	assert_eq(f.brace_count, 1, "one brace pulse")
	assert_eq(telegraphs.size(), 1, "one band telegraph (%s)" % [telegraphs])
	assert_eq(str(telegraphs[0][1]) if not telegraphs.is_empty() else "", "line", "along the band")
	assert_eq(brace_hits, 1, "one hit on the giant for the pulse")
	for e: EnemyActor in f.members:
		if e != striker:
			assert_true(e.controller.action == null, "%s only poses" % e.entity_id)


func test_shields_block_lights_and_break_on_heavies_stomps_and_sweeps() -> void:
	var cases := [["light", PackedStringArray(["Melee", "Parryable"]), HitResult.Outcome.BLOCKED],
		["heavy", PackedStringArray(["Melee", "Parryable", "Heavy"]), HitResult.Outcome.GUARD_BROKEN],
		["stomp", PackedStringArray(["Ability", "AoE", "Unparryable"]), HitResult.Outcome.GUARD_BROKEN]]
	var shields: Array[EnemyActor] = []
	for i in cases.size():
		var s := TestSpawn.enemy(world, SHIELDMAN, Vector3(i * 6.0, 0.05, 0), "test.shield_%d" % i, false)
		shields.append(s)
	await step_ticks(2)
	for i in cases.size():
		var s := shields[i]
		s.brain.aware = true
		s.brain.state = SoldierBrain.AIState.RECOVER
		assert_true(s.is_guarding(), "%s: the shield is up" % s.entity_id)
		assert_true(s.entity.combatant.pools.stamina >= 60.0, "with its stamina")
		queue_hit("player", s.entity_id, s.global_position + Vector3(0, 0, -3), 40.0, cases[i][1], 10.97)
		await step_ticks(1)
		assert_eq(hits[-1].outcome, cases[i][2], "a %s from the front: %s" % [cases[i][0],
			HitResult.OUTCOME_NAMES[cases[i][2]]])


func test_outmatched_soldiers_join_a_formation_within_40_m_or_flee() -> void:
	var p := await _stage_4_giant(Vector3(0, 0.05, 30))
	var f := _formation("test.join", Vector3(0, 0, 0), 3, 1, 2, false)
	var joiner := TestSpawn.enemy(world, PIKEMAN, Vector3(15, 0.05, 5), "test.joiner", true)
	var loner := TestSpawn.enemy(world, PIKEMAN, Vector3(60, 0.05, 40), "test.loner", true)
	await step_ticks(2)
	for e: EnemyActor in [joiner, loner]:
		e.brain.on_noise(Sim.tick, p.global_position, p.entity.entity_id, true)
	for i in 12:
		await step_ticks(1)
		if i % Formation.UPDATE_TICKS == 0:
			_update(f, p)
	assert_eq(joiner.formation, f, "the soldier 15 m away joined the formation")
	assert_eq(f.slot_for(joiner), 2, "in its free slot")
	assert_near(joiner.brain.morale, float(joiner.record.get("morale", 90)), 15.0, "keeping its own morale")
	assert_true(loner.formation == null, "the one 60 m away found none")
	assert_true(loner.brain.state in [EnemyBrain.AIState.FLEE, EnemyBrain.AIState.ROUTED],
		"and flees (%s)" % loner.brain.state_name())
