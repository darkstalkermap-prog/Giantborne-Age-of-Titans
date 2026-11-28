extends IntegrationSuite
## E2 in the real open world (scenes/world/world.tscn, deterministic streaming), in the Ashfell beyond the rim east of the
## Hoarfell:
##   * before his fall: the Cinder Titan stands at home at the Ember Hollow's east side, asleep (dormant) and on the
##     ground; the burned road (CinderRoad) burns along his way in, Thornstead's fires burn, the refugees' camp stands on
##     the Ash Road with Ysolde; the Ashbeck's pools are about 3 m deep, the Ash-pit dry; a giant he sees wakes him;
##   * the preparation: the Grey Spur will not move for a stage-8 giant; a stage-9 giant heaves it over, it dams the Cut
##     (world.ashfell.dammed) and the pit's water is 6.5 m deep;
##   * one duel in his real hollow (stage 9, seed 1, no preparation: the guaranteed path's fight): he fights, stays in his
##     territory and never sinks into the ground, nor the giant; his fire burns the ground and reaches the giant; the
##     water quenches him; no checkpoint and no fast travel while it lasts. Printed as an E2_WORLD line
##     (docs/BALANCE_LOG.md, "E2"; the probe --e2-world=<stage>:<seed>[:dammed] runs one duel alone);
##   * the aftermath: his fall puts the road's fires out (the char stays) and Thornstead's; once his fire is out
##     (world.ashfell.cooled) the camp is struck and Thornstead's folk are home; Ysolde closes quest.cinder and tells the
##     Hollow Titan's rumour (lead.hollow.heard, 0 XP).
## The titans' tier (--titans; --gate runs it): it loads the world, as the other titans' world suites do.

const SCENE := "res://scenes/world/world.tscn"
const HOME := Vector2(750.0, -1246.0)
const CAMP := Vector2(548.0, -1296.0)
const WEST_EDGE := Vector2(624.0, -1250.0)
const FORD := Vector2(692.0, -1250.0)
const PIT := Vector2(638.0, -1202.0)
const SPUR := Vector2(612.0, -1196.0)
const CENTRE := Vector2(700.0, -1240.0)
## His territory's hunting line (TitanTerritory: 115 m and the 20 m margin) from the hollow's centre.
const TERRITORY_M := 140.0
const PROBE := "--e2-world="


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
	var at := Vector3(xz.x, 260.0, xz.y)
	p.process_mode = Node.PROCESS_MODE_DISABLED
	p.global_position = at
	var guard := 0
	while not w.streamer.ring_ready(at) and guard < 900:
		w.streamer.load_ring_slice(at)
		await step_ticks(1)
		guard += 1
	var y := w.height_at(at)
	p.global_position = Vector3(xz.x, (y if not is_nan(y) else 190.0) + 0.3, xz.y)
	p.velocity = Vector3.ZERO
	p.process_mode = Node.PROCESS_MODE_INHERIT


func _titan() -> CinderEnemy:
	for n in get_tree().root.find_children("*", "CinderEnemy", true, false):
		var t := n as CinderEnemy
		if t.entity != null and t.entity.is_alive():
			return t
	return null


func _territory() -> TitanTerritory:
	for n in get_tree().get_nodes_in_group(BossArena.GROUP):
		if n is TitanTerritory and (n as TitanTerritory).boss_id == "world.ashfell.cinder":
			return n
	return null


func _named(id: String) -> Node:
	var found := get_tree().root.find_children(id.validate_node_name(), "", true, false)
	return found[0] if not found.is_empty() else null


func test_the_ashfell_before_his_fall_and_the_grey_spur() -> void:
	if not probe_arg().is_empty():
		return
	var w := await _world(CAMP, 8)
	await step_ticks(40)
	var t := _titan()
	var terr := _territory()
	assert_true(t != null and terr != null, "the Cinder Titan and his territory are loaded from the camp")
	if t == null or terr == null:
		return
	var home := Vector2(t.global_position.x, t.global_position.z)
	assert_true(home.distance_to(HOME) < 3.0, "at home at the hollow's east side (%s)" % home)
	assert_true(absf(t.global_position.y - w.height_at(t.global_position)) < 1.0, "on the ground")
	assert_true(t.dormant, "burning where he stopped, asleep")
	assert_true(terr.wake_on_sight, "a giant he sees wakes him")
	var road := get_tree().get_first_node_in_group(CinderRoad.GROUP) as CinderRoad
	assert_true(road != null and not road.cooled(), "the burned road is there and burning")
	assert_true(_named("world.ashfell.ysolde_talk") != null, "Ysolde at the camp")
	var ford := Vector3(FORD.x, w.height_at(Vector3(FORD.x, 0, FORD.y)), FORD.y)
	var d := StormWater.depth_at(get_tree(), ford)
	assert_true(d > 2.5 and d < 3.6, "the Ashbeck's ford about 3 m deep (%.1f)" % d)
	await _place(w, SPUR + Vector2(-14.0, 0.0))
	await step_ticks(10)
	var pit := Vector3(PIT.x, w.height_at(Vector3(PIT.x, 0, PIT.y)), PIT.y)
	assert_eq(StormWater.depth_at(get_tree(), pit), 0.0, "the Ash-pit dry")
	var spur := _named("world.ashfell.grey_spur") as BreakableProp
	assert_true(spur != null, "the Grey Spur stands over the Cut")
	if spur == null:
		return
	var r: Dictionary = spur.heave(w.player())
	assert_false(bool(r.ok), "a stage-8 giant cannot move it (%s)" % str(r.reason))
	TitanDuel.prepare(w.player(), 9)
	await step_ticks(2)
	r = spur.heave(w.player())
	assert_true(bool(r.ok), "a stage-9 giant heaves it over")
	await step_ticks(4)
	assert_true(QuestConditions.truthy(WorldState.get_flag("world.ashfell.dammed")), "it dams the Cut")
	var deep := StormWater.depth_at(get_tree(), pit)
	assert_true(deep > 6.0, "the pit filled, 6.5 m deep (%.1f)" % deep)


func _duel(stage: int, seed_value: int, dammed: bool, max_s: float) -> Dictionary:
	await TestWait.duel_start(self)
	var host := TestWait.duel_host(world)
	var w := await _world(WEST_EDGE + Vector2(-20.0, 0.0), stage, host,
		{"world.ashfell.dammed": true} if dammed else {})
	await step_ticks(30)
	var p := w.player()
	var t := _titan()
	if t == null:
		w.get_parent().queue_free()
		await step_ticks(2)
		return {}
	TitanDuel.prepare(p, stage)
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
			var k := r.event.action_id.trim_prefix("ability.cinder_")
			by_action[k] = int(by_action.get(k, 0)) + r.health_damage
		elif r.event.target_id == t.entity_id and r.health_damage > 0:
			dealt += r.health_damage
	var out := {"stage": stage, "seed": seed_value, "dammed": dammed, "giant_health": giant_hp, "woke": t.wake_reason,
		"giant_died_s": snappedf(died_at / 60.0, 0.1) if died_at >= 0 else -1.0,
		"titan_killed_s": snappedf(killed_at / 60.0, 0.1) if killed_at >= 0 else -1.0,
		"blows_taken": blows, "titan_left": snappedf(t.entity.combatant.pools.ratio("health"), 0.001),
		"plates": Array(t.plates().ever_broken), "phase": t.brain.boss_phase(), "topples": t.topples,
		"quenches": t.quenches, "quench_downs": t.quench_downs, "patches_laid": t.patches_laid,
		"ignitions": p.heat.ignitions, "scorches": t.scorches, "dealt": dealt, "hit_by": by_action,
		"farthest_m": snappedf(far_m, 0.1), "sank_m": snappedf(sank_m, 0.01), "giant_sank_m": snappedf(giant_sank_m, 0.01),
		"cool_runs": bot.cool_runs, "lure_s": snappedf(bot.quench_lure_ticks / 60.0, 0.1),
		"blocked_checkpoint": blocked_cp, "blocked_travel": blocked_travel,
		"damage_taken": int(giant_hp - p.entity.combatant.pools.health) if p.entity.is_alive() else int(giant_hp)}
	print("E2_WORLD " + JSON.stringify(out))
	GameSession.expansion = ExpansionState.defaults()
	w.get_parent().queue_free()
	await step_ticks(2)
	return out


## The probe: one duel in the world (--e2-world=stage:seed[:dammed]); the other tests do nothing while it is given.
func test_probe_world_duel() -> void:
	var a := probe_arg()
	if a.is_empty():
		return
	await _duel(int(a[0]), int(a[1]) if a.size() > 1 else 1, a.size() > 2 and a[2] == "dammed", 600.0)


## One duel in his real hollow at stage 9 (seed 1, no preparation).
func test_a_stage_9_duel_in_the_hollow() -> void:
	if not probe_arg().is_empty():
		return
	var out := await _duel(9, 1, false, 480.0)
	assert_false(out.is_empty(), "he is in the hollow")
	if out.is_empty():
		return
	assert_true(float(out.farthest_m) <= TERRITORY_M, "he stays in his territory (%.0f m)" % float(out.farthest_m))
	assert_true(float(out.sank_m) < 2.0, "he never sinks into the ground (%.2f m)" % float(out.sank_m))
	assert_true(float(out.giant_sank_m) < 1.0, "nor the giant (%.2f m)" % float(out.giant_sank_m))
	assert_true(int(out.blows_taken) >= 4 or int(out.ignitions) >= 1, "his fire reaches the giant")
	assert_true(int(out.patches_laid) >= 6, "the ground burns (%d)" % int(out.patches_laid))
	assert_true(int(out.quenches) >= 1, "his own beck quenches him (%d)" % int(out.quenches))
	assert_true(int(out.dealt) > 2000, "a real fight: the giant hurts him (%d)" % int(out.dealt))
	assert_true(bool(out.blocked_checkpoint), "no checkpoint mid-fight (a death or a quit goes back to before it)")
	assert_true(bool(out.blocked_travel), "no fast travel mid-fight")


func test_the_aftermath() -> void:
	if not probe_arg().is_empty():
		return
	var w := await _world(CAMP + Vector2(10.0, 0.0), 9)
	await step_ticks(30)
	var road := get_tree().get_first_node_in_group(CinderRoad.GROUP) as CinderRoad
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
	assert_true(QuestConditions.truthy(WorldState.get_flag("boss.cinder.defeated")), "he has fallen")
	assert_true(road != null and road.cooled(), "the road's fires go out")
	var fire := _named("world.ashfell.thornstead_fire_1")
	assert_true(fire == null or not (fire as Node3D).is_visible_in_tree(), "Thornstead no longer burns")
	assert_true(_named("world.ashfell.ysolde_talk") != null, "Ysolde still at the camp until the giant has gone")
	# the giant goes beyond his line (or a later load of the Ashfell): his fire is out, the folk go home
	WorldState.set_flag("world.ashfell.cooled", true)
	await step_ticks(4)
	var tent := _named("world.ashfell.camp_tent_1")
	assert_true(tent == null or not (tent as Node3D).is_visible_in_tree(), "the camp is struck")
	var ds := DialogueSession.new()
	assert_true(ds.begin(GameData.get_record("dialogue.ashfell_ysolde"), "world.ashfell.ysolde"), "Ysolde speaks")
	assert_eq(ds.node_id, "fallen", "Ysolde: his fire is out")
	ds.choose_outcome("cinder_fallen")
	await step_ticks(4)
	assert_true(QuestConditions.truthy(WorldState.get_flag("lead.hollow.heard")), "the empty king's rumour: a lead")
	assert_true(Quests.is_complete("quest.cinder"), "quest.cinder done: the fight and Ysolde's word")
	assert_true(w != null, "the world")
