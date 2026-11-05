extends IntegrationSuite
## P17a (plan §3.19 tests, §5.1): the Valley bot's smoke test (slow; runs with --slow).
##   * In the real Valley from New Game, the novice bot with the assist status plays the first two
##     objectives of quest.main (leave_hollow, wolves) within 120 s of simulated time - the optional
##     Hollow tutorial on the way - with no error, no watchdog breach and no invariant failure; its
##     result carries every metric key of §5.1 (with the Autopilot's own keys: errors, warnings,
##     error samples and the PerfProbe's CPU per tick).
##   * The diagnosis on a small test level built here (two navmesh islands on the small-giant
##     layer, joined only by a closed "breakable" nav link): a marker on the far island with the
##     link gone is world_blocked (no path); with the closed link it counts as reachable (breaking
##     the prop is the bot's job: bot_failed); a reachable marker is bot_failed; a condition that
##     can no longer hold (a kill target that exists nowhere) is world_blocked.
##   * The bot's command-line options, the Autopilot's exit codes (3 for an invariant failure, 2 for
##     a breach; in a loop run only a world_blocked breach fails) and the invariants' checks.

const ISLAND_A := Vector3(5, 0, 5)
const ISLAND_B := Vector3(25, 0, 5)

var level: Node3D
var bot: ValleyBot


func before_each() -> void:
	await super()
	ValleyBot.reset()
	level = null
	bot = null


func after_each() -> void:
	if bot != null and is_instance_valid(bot):
		bot.queue_free()
	bot = null
	if level != null and is_instance_valid(level):
		level.queue_free()
	level = null
	ValleyBot.reset()
	await super()


# --------------------------------------------------------------------------- the first objectives

## The Valley from New Game, loaded as main.gd does (GameSession in Valley mode, the level added,
## on_level_ready), then the bot.
func test_the_novice_bot_plays_the_first_two_objectives_in_two_minutes() -> void:
	GameSession.start_new_valley()
	var lv := ValleyProbe.instance(false)
	level = lv
	world.add_child(lv)
	var player := lv.player()
	GameSession.on_level_ready(lv, player)
	assert_true(await ValleyProbe.wait_for_navigation(self, lv), "the Valley's navigation is ready")
	var probe := PerfProbe.new()
	probe.warmup_ticks = 10
	world.add_child(probe)
	ValleyBot.configure({"policy": "help_cache", "skill": "novice", "assist": true, "seed": 1})
	bot = ValleyBot.new()
	world.add_child(bot)
	var start := Sim.tick
	var done: bool = await TestWait.until(self, func() -> bool:
		return Quests.stage_of("quest.main") not in ["leave_hollow", "wolves"] or ValleyBot.run.finished, 7200)
	var seconds := float(Sim.tick - start) / 60.0
	print("    bot smoke: quest.main at %s after %.1f s (tutorial %s)" % [Quests.stage_of("quest.main"), seconds,
		Quests.quest_state("quest.tutorial")])
	assert_true(done, "the bot left the Hollow and beat the wolves within 120 s (at %s)" % Quests.stage_of("quest.main"))
	assert_eq(Quests.stage_of("quest.main"), "ogre", "quest.main moved on to the ogre")
	assert_true(WorldState.has_flag("reward.main.leave_hollow") and WorldState.has_flag("reward.main.wolves"),
		"both objectives rewarded")
	assert_false(ValleyBot.run.finished, "no breach or invariant failure ended the run")
	assert_true(ValleyBot.run.breaches.is_empty(), "no watchdog breach (%s)" % [ValleyBot.run.breaches])
	assert_true(ValleyBot.run.invariant_failures.is_empty(), "no invariant failure (%s)" % [ValleyBot.run.invariant_failures])
	assert_true(player.entity.combatant.statuses.has(ValleyBot.ASSIST_STATUS), "the assisted giant carries status.bot_assist")
	probe.finish()
	var vb := ValleyBot.result(Sim.tick)
	var result := Autopilot.build_result({"ticks": Sim.tick - start}, seconds, [], [], {})
	result["valley_bot"] = vb
	var perf := probe.result()
	result["perf"] = {"cpu_tick_ms": perf.cpu_tick_ms, "budgets": perf.budgets}
	_assert_metric_keys(result)
	var actions: Dictionary = vb.actions
	assert_true(int(actions.light) > 0, "it attacked (%d lights)" % int(actions.light))
	var wolves := 0
	for id: String in WorldState.deltas:
		if id.begins_with("valley.forest.wolf_a") and bool((WorldState.deltas[id] as Dictionary).get("killed", false)):
			wolves += 1
	assert_true(wolves >= 1 or WorldState.has_flag("encounter.forest_wolves_a.cleared"), "the wolf pack was beaten")
	var objectives: Array = vb.objectives
	assert_true(objectives.any(func(o: Dictionary) -> bool: return str(o.id) == "quest.main:leave_hollow" and int(o.end_tick) > 0),
		"leave_hollow is a closed objective record")
	assert_eq(str((vb.segments as Array)[0].id), "1_hollow", "segments follow §4.9")
	assert_true(float((vb.segments as Array)[0].raw_s) > 0.0, "the Hollow segment has time")
	assert_true(float(vb.human_estimate_s) > float(vb.segment_raw_s), "the human estimate adds reading and screens")
	print("    bot smoke: %s" % JSON.stringify({"segments": vb.segments.slice(0, 2), "actions": vb.actions,
		"readability": vb.readability, "deaths": (vb.deaths as Array).size()}))


## Every key of plan §5.1's metric list.
func _assert_metric_keys(result: Dictionary) -> void:
	for key: String in ["errors", "warnings", "error_samples", "perf", "valley_bot"]:
		assert_true(result.has(key), "AUTOPILOT_RESULT has %s" % key)
	var vb: Dictionary = result.valley_bot
	for key: String in ["bot", "simulated_s", "human_estimate_s", "completed", "village_outcome", "flags_hash",
			"segments", "objectives", "deaths", "damage_taken_by_archetype", "damage_taken_by_action",
			"readability", "ttk", "engagement_distance", "ai_states", "abilities", "actions", "xp_timeline",
			"growth_ticks", "stuck_events", "rewards", "max_active_enemies", "max_debris", "diagnosis",
			"breaches", "invariant_failures", "nodes"]:
		assert_true(vb.has(key), "valley_bot has %s" % key)
	for key: String in ["policy", "skill", "assist", "seed"]:
		assert_true((vb.bot as Dictionary).has(key), "the run's %s" % key)
	var seg: Dictionary = (vb.segments as Array)[0]
	for key: String in ["raw_s", "human_estimate_s", "combat_s", "traversal_s", "deaths", "damage_taken",
			"min_health_frac", "checkpoints", "rests"]:
		assert_true(seg.has(key), "a segment has %s" % key)
	var obj: Dictionary = (vb.objectives as Array)[0]
	for key: String in ["id", "start_tick", "end_tick", "seconds", "deaths", "damage_taken", "damage_dealt"]:
		assert_true(obj.has(key), "an objective has %s" % key)
	for key: String in ["hits_taken", "off_camera", "late_telegraph", "off_camera_share", "late_telegraph_share"]:
		assert_true((vb.readability as Dictionary).has(key), "readability has %s" % key)
	for key: String in ["uses", "damage_share", "used_when_ready"]:
		assert_true((vb.abilities as Dictionary).has(key), "abilities have %s" % key)
	for key: String in ["light", "heavy", "blocks", "parries", "dodges", "grabs", "throws"]:
		assert_true((vb.actions as Dictionary).has(key), "actions have %s" % key)
	for key: String in ["granted", "duplicates"]:
		assert_true((vb.rewards as Dictionary).has(key), "rewards have %s" % key)
	var cpu: Variant = (result.perf as Dictionary).get("cpu_tick_ms")
	assert_true(typeof(cpu) == TYPE_DICTIONARY and (cpu as Dictionary).has("p95") and (cpu as Dictionary).has("p99"),
		"CPU per tick p95 / p99 (%s)" % [cpu])


# --------------------------------------------------------------------------- the diagnosis

## A LevelRoot with two 10 x 10 m navmesh islands on the small-giant layer (8), 10 m apart, a closed
## nav link between them (a breakable prop's), and the giant on island A.
func _islands() -> LevelRoot:
	var lv := LevelRoot.new()
	lv.level_id = "level.test_islands"
	lv.name = "Islands"
	var nav := Node3D.new()
	nav.name = "Navigation"
	lv.add_child(nav)
	var region := NavigationRegion3D.new()
	region.name = "SmallGiant"
	region.navigation_layers = 8
	var nm := NavigationMesh.new()
	nm.cell_size = 0.25
	nm.cell_height = 0.25
	nm.vertices = PackedVector3Array([Vector3(0, 0, 0), Vector3(10, 0, 0), Vector3(10, 0, 10), Vector3(0, 0, 10),
		Vector3(20, 0, 0), Vector3(30, 0, 0), Vector3(30, 0, 10), Vector3(20, 0, 10)])
	nm.add_polygon(PackedInt32Array([0, 3, 2, 1]))
	nm.add_polygon(PackedInt32Array([4, 7, 6, 5]))
	region.navigation_mesh = nm
	nav.add_child(region)
	var link := NavigationLink3D.new()
	link.name = "NavLinkGap"
	link.navigation_layers = 8
	link.start_position = Vector3(9.5, 0, 5)
	link.end_position = Vector3(20.5, 0, 5)
	link.enabled = false
	lv.add_child(link)
	return lv


func test_the_diagnosis_tells_a_softlock_from_a_bot_failure() -> void:
	var lv := _islands()
	level = lv
	world.add_child(lv)
	var p := spawn_player(ISLAND_A + Vector3(0, 0.05, 0))
	await step_ticks(3)
	assert_eq(p.nav_layers, 8, "a stage-1 giant paths on the small-giant layer")
	var map := lv.nav_map()
	var synced: bool = await TestWait.until(self, func() -> bool:
		return NavigationServer3D.map_get_path(map, ISLAND_A, ISLAND_A + Vector3(3, 0, 3), true, 8).size() > 0, 60)
	assert_true(synced, "the islands' navmesh is in the map")
	var near := {"quest_id": "quest.test", "stage_id": "near", "position": ISLAND_A + Vector3(3, 0, 3)}
	var d := BotDiagnosis.diagnose(near, p, lv, "timeout")
	assert_eq(str(d.classification), BotDiagnosis.BOT_FAILED, "a reachable marker: the bot failed (%s)" % [d.evidence])
	assert_true(bool(d.path.direct), "a direct path")
	var far := {"quest_id": "quest.test", "stage_id": "far", "position": ISLAND_B + Vector3(2, 0, 0)}
	d = BotDiagnosis.diagnose(far, p, lv, "stuck")
	assert_eq(str(d.classification), BotDiagnosis.BOT_FAILED,
		"across a closed breakable link the marker counts as reachable (%s)" % [d.evidence])
	assert_false(bool(d.path.direct), "not directly")
	assert_true(str(d.path.via_link).ends_with("NavLinkGap"), "through the closed link (%s)" % d.path.via_link)
	lv.get_node("NavLinkGap").free()
	d = BotDiagnosis.diagnose(far, p, lv, "stuck")
	assert_eq(str(d.classification), BotDiagnosis.WORLD_BLOCKED, "without the link the marker is unreachable: a softlock")
	assert_false(bool(d.path.reachable), "no path")
	assert_true(str(d.evidence).contains("no path"), "the evidence says so (%s)" % [d.evidence])
	var off := {"quest_id": "quest.test", "stage_id": "off", "position": Vector3(15, 0, 40)}
	d = BotDiagnosis.diagnose(off, p, lv, "timeout")
	assert_eq(str(d.classification), BotDiagnosis.WORLD_BLOCKED, "a marker off every navmesh is unreachable")
	var ghost := {"quest_id": "quest.test", "stage_id": "ghost", "position": ISLAND_A + Vector3(3, 0, 3),
		"complete_when": {"type": "killed", "targets": ["test.nobody"]}}
	d = BotDiagnosis.diagnose(ghost, p, lv, "timeout")
	assert_eq(str(d.classification), BotDiagnosis.WORLD_BLOCKED,
		"a kill target that exists nowhere can never die: a softlock (%s)" % [d.condition])
	assert_false(bool(d.condition.satisfiable), "the condition cannot hold")


# --------------------------------------------------------------------------- options, codes, invariants

func test_options_exit_codes_and_invariants() -> void:
	var o := ValleyBot.parse_options(PackedStringArray(["--bot-village=force", "--bot-skill=expert", "--bot-assist",
		"--bot-loop", "--bot-seed=7"]))
	assert_eq(o, {"policy": "force", "skill": "expert", "assist": true, "loop": true, "seed": 7}, "every option")
	o = ValleyBot.parse_options(PackedStringArray([]))
	assert_eq(o, {"policy": "help_cache", "skill": "novice", "assist": false, "loop": false, "seed": 0}, "the defaults")
	o = ValleyBot.parse_options(PackedStringArray(["--bot-village=bribe", "--bot-skill=godlike"]))
	assert_eq([o.policy, o.skill], ["help_cache", "novice"], "unknown values fall back")
	assert_eq(Autopilot.exit_code({"errors": 0, "invariants_ok": false, "scenario_ok": false}), Autopilot.EXIT_INVARIANT,
		"an invariant failure exits 3")
	assert_eq(Autopilot.exit_code({"errors": 2, "invariants_ok": false}), Autopilot.EXIT_ERRORS, "errors still win")
	assert_eq(Autopilot.exit_code({"errors": 0, "invariants_ok": true, "scenario_ok": false}),
		Autopilot.EXIT_SCENARIO_FAILED, "a breach exits 2")
	assert_eq(Autopilot.EXIT_INVARIANT, 3, "code 3")
	var single := {"bot": {"loop": false}, "completed": false, "invariant_failures": [],
		"breaches": [{"reason": "timeout", "objective": "quest.main:ogre", "classification": BotDiagnosis.BOT_FAILED}]}
	assert_eq(Autopilot.valley_failures(single).size(), 1, "a single run fails on any breach")
	var loop := single.duplicate(true)
	loop.bot.loop = true
	assert_eq(Autopilot.valley_failures(loop).size(), 0, "a loop run reports a bot_failed breach without failing")
	(loop.breaches as Array).append({"reason": "stuck", "objective": "quest.main:bridge",
		"classification": BotDiagnosis.WORLD_BLOCKED})
	assert_eq(Autopilot.valley_failures(loop).size(), 1, "but fails on a softlock")
	var unfinished := {"bot": {"loop": false}, "completed": false, "breaches": [], "invariant_failures": []}
	assert_eq(Autopilot.valley_failures(unfinished).size(), 1, "a single run that never finished the slice fails")
	assert_eq(BotDiagnosis.node_growth_failure([[0, 1000], [1, 1050], [2, 1100], [3, 1150], [4, 1200], [5, 1260]]),
		"nodes grew at 5 consecutive loads: 1000 -> 1260", "steady growth over five reload cycles is a leak")
	assert_eq(BotDiagnosis.node_growth_failure([[0, 1000], [1, 1050], [2, 1040], [3, 1150], [4, 1200], [5, 1260]]), "",
		"a drop in between is not")
	assert_eq(BotDiagnosis.node_growth_failure([[0, 1000], [1, 1010], [2, 1020], [3, 1030], [4, 1040], [5, 1050]]), "",
		"nor is growth under 10 %")
	# The invariants on a calm scene hold; a lock on a dead target and a duplicate reward fail.
	var p := spawn_player(Vector3(0, 0.05, 0))
	var dummy := spawn_dummy(Vector3(0, 0, -6), "test.p17a.dummy")
	await step_ticks(3)
	var metrics := RunMetrics.new()
	var fails := BotDiagnosis.check_invariants(get_tree(), p, null, metrics, 0)
	assert_true(fails.is_empty(), "a calm scene holds every invariant (%s)" % [fails])
	p.lock.target_id = "test.p17a.gone"
	fails = BotDiagnosis.check_invariants(get_tree(), p, null, metrics, 0)
	assert_true(fails.size() == 1 and fails[0].contains("lock target test.p17a.gone"), "a lock on nothing fails (%s)" % [fails])
	p.lock.release()
	metrics.connect_events()
	WorldState.try_set_flag("reward.test.once", true)
	WorldState.flags.erase("reward.test.once")
	WorldState.try_set_flag("reward.test.once", true)
	metrics.disconnect_events()
	fails = BotDiagnosis.check_invariants(get_tree(), p, null, metrics, 0)
	assert_true(fails.size() == 1 and fails[0].contains("reward granted twice: reward.test.once"),
		"a once-flag granted twice fails (%s)" % [fails])
	metrics.rebuild_granted()
	assert_true(dummy != null, "the dummy stood by")
