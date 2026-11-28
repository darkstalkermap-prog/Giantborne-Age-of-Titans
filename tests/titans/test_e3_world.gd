extends IntegrationSuite
## E3 in the real open world (scenes/world/world.tscn, deterministic streaming), in the Kingsward beyond the Hoarfell's west
## rim:
##   * the road to him: the Empty Stand on the high grazing north of the Breach (Brann at his shieling), the King's Track
##     west with the empty king's tracks; the lead starts quest.hollow and the Empty Stand completes its first stage;
##   * before his fall: the Hollow Titan keeps his vigil at the King's Field's north side, asleep (dormant) and on the
##     ground; the three oath-stones stand round the field; a giant he sees wakes him;
##   * the preparation: the Oath-stake will not move for a stage-8 giant; a stage-9 giant heaves it out of the rock
##     (world.kingsward.stake_pulled) and his torn plates come back half as fast;
##   * one duel in his real field (stage 9, seed 1, no preparation: the guaranteed path's fight): he fights, stays in his
##     territory and never sinks into the ground, nor the giant; his breastplate comes off and the knot is struck; no
##     checkpoint and no fast travel while it lasts. Printed as an E3_WORLD line (docs/BALANCE_LOG.md, "E3"; the probe
##     --e3-world=<stage>:<seed>[:staked] runs one duel alone);
##   * the aftermath: his fall; once the giant has gone (world.kingsward.at_rest) the herders' barrow stands over his
##     armour and Brann is at it; Brann closes quest.hollow (level 20 on the guaranteed path) and tells the Worldbreaker's
##     rumour (lead.worldbreaker.heard, 0 XP).
## The titans' tier (--titans; --gate runs it): it loads the world, as the other titans' world suites do.

const SCENE := "res://scenes/world/world.tscn"
const HOME := Vector2(-700.0, -1504.0)
const STAND := Vector2(104.0, -1596.0)
const GATE := Vector2(-600.0, -1500.0)
const STAKE := Vector2(-576.0, -1428.0)
const CENTRE := Vector2(-700.0, -1460.0)
## His territory's hunting line (TitanTerritory: 115 m and the 20 m margin) from the field's centre.
const TERRITORY_M := 140.0
const PROBE := "--e3-world="


func after_each() -> void:
	get_tree().paused = false
	for f in Formation.live():
		f.dissolve()
	FactionState.reset_for_tests()
	WanderDirector.reset_for_tests()
	GameSession.expansion = ExpansionState.defaults()
	await super()


static func probe_arg() -> PackedStringArray:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with(PROBE):
			return arg.substr(PROBE.length()).split(":")
	return PackedStringArray()


func _world(xz: Vector2, stage := 9, host: Node = null, flags := {}) -> WorldRoot:
	WorldState.clear()
	GameSession.start_world_for_tests("world.cp.breach_top")
	GameSession.level_id = GameSession.WORLD_LEVEL_ID
	WorldState.try_set_flag("act.two.begun", true)
	for f: String in flags:
		WorldState.set_flag(f, flags[f])
	var w := (load(SCENE) as PackedScene).instantiate() as WorldRoot
	(host if host != null else world).add_child(w)
	w.streamer.deterministic = true
	var p := w.player()
	p.router.use_injection = true
	GameSession.on_level_ready(w, p)
	await _place(w, xz)
	TitanDuel.prepare(p, stage)
	await step_ticks(2)
	return w


func _place(w: WorldRoot, xz: Vector2) -> void:
	var p := w.player()
	var at := Vector3(xz.x, 280.0, xz.y)
	p.process_mode = Node.PROCESS_MODE_DISABLED
	p.global_position = at
	var guard := 0
	while not w.streamer.ring_ready(at) and guard < 900:
		w.streamer.load_ring_slice(at)
		await step_ticks(1)
		guard += 1
	var y := w.height_at(at)
	p.global_position = Vector3(xz.x, (y if not is_nan(y) else 200.0) + 0.3, xz.y)
	p.velocity = Vector3.ZERO
	p.process_mode = Node.PROCESS_MODE_INHERIT


func _titan() -> HollowEnemy:
	for n in get_tree().root.find_children("*", "HollowEnemy", true, false):
		var t := n as HollowEnemy
		if t.entity != null and t.entity.is_alive():
			return t
	return null


func _territory() -> TitanTerritory:
	for n in get_tree().get_nodes_in_group(BossArena.GROUP):
		if n is TitanTerritory and (n as TitanTerritory).boss_id == "world.kingsward.hollow":
			return n
	return null


func _named(id: String) -> Node:
	var found := get_tree().root.find_children(id.validate_node_name(), "", true, false)
	return found[0] if not found.is_empty() else null


func test_the_road_the_field_and_the_oath_stake() -> void:
	if not probe_arg().is_empty():
		return
	var w := await _world(STAND, 8, null, {"lead.hollow.heard": true})
	await step_ticks(40)
	assert_true(Quests.quest_state("quest.hollow") != "inactive", "the lead starts quest.hollow (%s)" % Quests.quest_state("quest.hollow"))
	assert_true(_named("world.hoarfell.brann_talk") != null, "Brann at his shieling on the high grazing")
	await step_ticks(30)
	assert_eq(Quests.stage_of("quest.hollow"), "slay", "the Empty Stand reached: on to the Kingsward")
	await _place(w, GATE + Vector2(40.0, 30.0))
	await step_ticks(40)
	var t := _titan()
	var terr := _territory()
	assert_true(t != null and terr != null, "the Hollow Titan and his territory are loaded from the field's gate")
	if t == null or terr == null:
		return
	var home := Vector2(t.global_position.x, t.global_position.z)
	assert_true(home.distance_to(HOME) < 3.0, "on his vigil at the field's north side (%s)" % home)
	assert_true(absf(t.global_position.y - w.height_at(t.global_position)) < 1.0, "on the ground")
	assert_true(t.dormant, "asleep on his vigil")
	assert_true(terr.wake_on_sight, "a giant he sees wakes him")
	assert_eq(t.standing_stones().size(), 3, "three oath-stones stand round the field")
	assert_true(t.holds(), "the oath holds")
	await _place(w, STAKE + Vector2(18.0, 6.0))
	await step_ticks(10)
	var stake := _named("world.kingsward.oath_stake") as BreakableProp
	assert_true(stake != null, "the Oath-stake in its rock")
	if stake == null:
		return
	var r: Dictionary = stake.heave(w.player())
	assert_false(bool(r.ok), "a stage-8 giant cannot move it (%s)" % str(r.reason))
	TitanDuel.prepare(w.player(), 9)
	await step_ticks(2)
	r = stake.heave(w.player())
	assert_true(bool(r.ok), "a stage-9 giant heaves it out")
	await step_ticks(4)
	assert_true(QuestConditions.truthy(WorldState.get_flag("world.kingsward.stake_pulled")), "the chains go slack")
	t._apply_stake()
	assert_near(float((t.entity.plates.plate("helm").regrow as Dictionary).after_s),
		float(t._base_after.helm) * float(t.hollow.stake_regrow_mult), 0.01, "his plates come back half as fast")
	assert_true(Quests.quest_state("quest.hollow_stake") != "inactive", "the preparation's quest (%s)" % Quests.quest_state("quest.hollow_stake"))


func _duel(stage: int, seed_value: int, staked: bool, max_s: float) -> Dictionary:
	await TestWait.duel_start(self)
	var host := TestWait.duel_host(world)
	var w := await _world(GATE + Vector2(-20.0, 10.0), stage, host,
		{"world.kingsward.stake_pulled": true} if staked else {})
	await step_ticks(30)
	var p := w.player()
	var t := _titan()
	if t == null:
		w.get_parent().queue_free()
		await step_ticks(2)
		return {}
	TitanDuel.prepare(p, stage)
	t._apply_stake()
	t.brain.rng.seed = seed_value
	t.wake("engaged")
	var bot := TitanDuelBot.new()
	bot.see_obstacles = true
	bot.setup(p, t, "expert", seed_value, true)
	hits.clear()
	var start := Sim.tick
	var limit := int(max_s * Sim.TICK_RATE)
	var giant_hp := p.entity.combatant.pools.health_max
	var died_at := -1
	var killed_at := -1
	var far_m := 0.0
	var sank_m := 0.0
	var giant_sank_m := 0.0
	var blocked_cp := false
	var blocked_travel := false
	while Sim.tick - start < limit:
		bot.step(Sim.tick)
		await step_ticks(1)
		if (Sim.tick - start) % 30 == 0:
			far_m = maxf(far_m, Vector2(t.global_position.x, t.global_position.z).distance_to(CENTRE))
			var g := w.height_at(t.global_position)
			if not is_nan(g):
				sank_m = maxf(sank_m, g - t.global_position.y)
			var gp := w.height_at(p.global_position)
			if not is_nan(gp):
				giant_sank_m = maxf(giant_sank_m, gp - p.global_position.y)
		if Sim.tick - start == 600:
			blocked_cp = not GameSession.checkpoint_blockers().is_empty()
			blocked_travel = not GameSession.travel_blockers("fast_travel").is_empty()
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
			var k := r.event.action_id.trim_prefix("ability.hollow_")
			by_action[k] = int(by_action.get(k, 0)) + r.health_damage
		elif r.event.target_id == t.entity_id and r.health_damage > 0:
			dealt += r.health_damage
	var out := {"stage": stage, "seed": seed_value, "staked": staked, "giant_health": giant_hp, "woke": t.wake_reason,
		"giant_died_s": snappedf(died_at / 60.0, 0.1) if died_at >= 0 else -1.0,
		"titan_killed_s": snappedf(killed_at / 60.0, 0.1) if killed_at >= 0 else -1.0,
		"blows_taken": blows, "titan_left": snappedf(t.entity.combatant.pools.ratio("health"), 0.001),
		"plates": Array(t.plates().ever_broken), "phase": t.brain.boss_phase(), "topples": t.topples,
		"knot_hits": t.knot_hits, "crushes": t.crushes, "hurls": t.hurls, "reforms": t.reforms, "echoes": t.echoes,
		"draws": t.draws_landed, "stones_felled": t.stones_felled, "dealt": dealt, "hit_by": by_action,
		"farthest_m": snappedf(far_m, 0.1), "sank_m": snappedf(sank_m, 0.01), "giant_sank_m": snappedf(giant_sank_m, 0.01),
		"shard_runs": bot.shard_runs, "stone_runs": bot.stone_runs,
		"blocked_checkpoint": blocked_cp, "blocked_travel": blocked_travel,
		"damage_taken": int(giant_hp - p.entity.combatant.pools.health) if p.entity.is_alive() else int(giant_hp)}
	print("E3_WORLD " + JSON.stringify(out))
	GameSession.expansion = ExpansionState.defaults()
	w.get_parent().queue_free()
	await step_ticks(2)
	return out


## The probe: one duel in the world (--e3-world=stage:seed[:staked]); the other tests do nothing while it is given.
func test_probe_world_duel() -> void:
	var a := probe_arg()
	if a.is_empty():
		return
	await _duel(int(a[0]), int(a[1]) if a.size() > 1 else 1, a.size() > 2 and a[2] == "staked", 600.0)


## One duel in his real field at stage 9 (seed 1, no preparation).
func test_a_stage_9_duel_in_the_kings_field() -> void:
	if not probe_arg().is_empty():
		return
	var out := await _duel(9, 1, false, 420.0)
	assert_false(out.is_empty(), "he is in the field")
	if out.is_empty():
		return
	assert_true(float(out.farthest_m) <= TERRITORY_M, "he stays in his territory (%.0f m)" % float(out.farthest_m))
	assert_true(float(out.sank_m) < 2.0, "he never sinks into the ground (%.2f m)" % float(out.sank_m))
	assert_true(float(out.giant_sank_m) < 1.0, "nor the giant (%.2f m)" % float(out.giant_sank_m))
	assert_true(int(out.blows_taken) >= 4, "his blows land (%d)" % int(out.blows_taken))
	assert_true((out.plates as Array).has("cuirass"), "his breastplate comes off")
	assert_true(int(out.knot_hits) >= 1, "and the knot is struck (%d)" % int(out.knot_hits))
	assert_true(int(out.dealt) > 2000, "a real fight: the giant hurts him (%d)" % int(out.dealt))
	assert_true(bool(out.blocked_checkpoint), "no checkpoint mid-fight (a death or a quit goes back to before it)")
	assert_true(bool(out.blocked_travel), "no fast travel mid-fight")


func test_the_aftermath() -> void:
	if not probe_arg().is_empty():
		return
	var w := await _world(GATE + Vector2(20.0, 0.0), 9, null, {"lead.hollow.heard": true})
	await step_ticks(30)
	var t := _titan()
	assert_true(t != null, "he is there")
	if t != null:
		t.entity.combatant.pools.health = 1.0
		var e := HitEvent.new()
		e.tick = Sim.tick
		e.attacker_id = w.player().entity.entity_id
		e.target_id = t.entity.entity_id
		e.action_id = "ability.light_1"
		e.power = 999999.0
		e.damage_split = {"physical": 1.0}
		e.category = "melee"
		Sim.queue_hit(e)
	await step_ticks(10)
	assert_true(QuestConditions.truthy(WorldState.get_flag("boss.hollow.defeated")), "he has fallen")
	var barrow := _named("world.kingsward.kings_barrow")
	assert_true(barrow == null or not (barrow as Node3D).is_visible_in_tree(), "no barrow while the giant stands over him")
	# the giant goes beyond his line (or a later load of the Kingsward): the herders lay him to rest
	WorldState.set_flag("world.kingsward.at_rest", true)
	await step_ticks(4)
	barrow = _named("world.kingsward.kings_barrow")
	assert_true(barrow != null and (barrow as Node3D).is_visible_in_tree(), "the barrow over his armour")
	var talk := _named("world.kingsward.brann_field_talk")
	assert_true(talk != null and (talk as Node3D).is_visible_in_tree(), "Brann at the barrow")
	var p := w.player()
	p.progression.add_xp(27960 + 100 + 90 + 600 + 5600 - int(p.progression.xp), "test")
	var ds := DialogueSession.new()
	assert_true(ds.begin(GameData.get_record("dialogue.kingsward_brann"), "world.hoarfell.brann"), "Brann speaks")
	assert_eq(ds.node_id, "fallen", "Brann: the chains dropped")
	ds.choose_outcome("hollow_fallen")
	await step_ticks(4)
	assert_true(QuestConditions.truthy(WorldState.get_flag("lead.worldbreaker.heard")), "the Worldbreaker's rumour: a lead")
	assert_true(Quests.is_complete("quest.hollow"), "quest.hollow done: the fight and Brann's word")
	assert_eq(int(p.progression.level), 20, "level 20 on the guaranteed path (%d XP)" % int(p.progression.xp))
	assert_true(w != null, "the world")
