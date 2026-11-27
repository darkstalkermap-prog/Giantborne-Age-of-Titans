extends IntegrationSuite
## E1 in the real open world (scenes/world/world.tscn, deterministic streaming), at the Moot:
##   * before the rumour of Harrok's banner (lead.harrok.hearth) the Moot is as act one left it: no Orrik, no winches'
##     crews; from it Orrik stands before the Stone Throne, the warband at its fetter-winches inside the ring;
##   * the preparation: the reserve winches and their crews are not there once the winch camp is broken
##     (world.moot.camp_broken), the west winch not once Skarn stands with the giant (world.skarn.saved);
##   * both branches run from the lead to the aftermath: the look-in at the Moot (quest.harrok_lead, then
##     quest.harrok_return), the giant entering the ring engages the fight, the bot fights it to Orrik's fall (stage 9:
##     the run's measure is the story's path, the curve is the test arena's duels), then the Moot settles - with Harrok
##     slain the clan kneels at the oath-stone (the sworn clans at the stones), with Harrok spared Harrok fights beside
##     the giant, holds the Moot (his banner, him by the throne) and gives his oath-ring - and the rumour of the burning
##     road is heard (quest.cinder_lead);
##   * one stage-8 duel in the real ring each branch, printed as an E1_WORLD line (docs/BALANCE_LOG.md, "E1").
## The titans' tier (--titans; --gate runs it).

const SCENE := "res://scenes/world/world.tscn"
const FOOT := Vector2(-70.0, -650.0)
const RING := Vector2(-10.0, -730.0)
const ORRIK_ID := "world.stonehold.orrik"


func after_each() -> void:
	get_tree().paused = false
	for f in Formation.live():
		f.dissolve()
	FactionState.reset_for_tests()
	WanderDirector.reset_for_tests()
	GameSession.expansion = ExpansionState.defaults()
	await super()


func _world(xz: Vector2, stage: int, harrok: String, lead := true, extra: Dictionary = {}) -> WorldRoot:
	WorldState.clear()
	GameSession.start_world_for_tests("world.cp.moot_foot")
	GameSession.level_id = GameSession.WORLD_LEVEL_ID
	for f: String in ["act.two.begun", "campaign.completed", "boss.frostbound.defeated", "boss.stormcaller.defeated"]:
		WorldState.try_set_flag(f, true)
	WorldState.try_set_flag("boss.harrok.outcome", harrok)
	WorldState.try_set_flag("boss.harrok.defeated", true)
	if harrok == "slain":
		WorldState.try_set_flag("world.moot.empty", true)
	if lead:
		WorldState.try_set_flag("lead.harrok.hearth", true)
	for k: String in extra:
		WorldState.try_set_flag(k, extra[k])
	var w := (load(SCENE) as PackedScene).instantiate() as WorldRoot
	world.add_child(w)
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
	var at := Vector3(xz.x, 140.0, xz.y)
	p.process_mode = Node.PROCESS_MODE_DISABLED
	p.global_position = at
	var guard := 0
	while not w.streamer.ring_ready(at) and guard < 900:
		w.streamer.load_ring_slice(at)
		await step_ticks(1)
		guard += 1
	var y := w.height_at(at)
	p.global_position = Vector3(xz.x, (y if not is_nan(y) else 95.0) + 0.3, xz.y)
	p.velocity = Vector3.ZERO
	p.process_mode = Node.PROCESS_MODE_INHERIT


func _orrik() -> HeirEnemy:
	var e := Sim.get_entity(ORRIK_ID)
	return e.actor as HeirEnemy if e != null and is_instance_valid(e.actor) else null


func _arena() -> ThroneChallenge:
	for n in get_tree().get_nodes_in_group(BossArena.GROUP):
		if n is ThroneChallenge:
			return n
	return null


func _winches() -> Array:
	var out: Array = []
	for n in get_tree().get_nodes_in_group("fetter_winches"):
		var wi := n as FetterWinch
		if wi != null and wi.world_id.begins_with("world.stonehold.fetter_winch"):
			out.append(wi)
	return out


func _alive(prefix: String) -> int:
	var n := 0
	for e: CombatEntity in Sim.entities():
		if e.entity_id.begins_with(prefix) and e.is_alive():
			n += 1
	return n


## The living members of `prefix` still in the fight (not routed nor fleeing).
func _fighting(prefix: String) -> int:
	var n := 0
	for e: CombatEntity in Sim.entities():
		if e.entity_id.begins_with(prefix) and e.is_alive() and e.actor is EnemyActor:
			var a := e.actor as EnemyActor
			if not a.is_routed() and not (a.brain.state_name() in ["Flee", "Routed"]):
				n += 1
	return n


func test_the_moot_is_quiet_before_the_rumour() -> void:
	var w := await _world(FOOT, 8, "slain", false)
	await step_ticks(60)
	assert_true(_orrik() == null, "no Orrik before Harrok's banner is rumoured")
	assert_eq(_winches().size(), 0, "no winches staked in the ring before it")
	assert_eq(_alive("world.stonehold.winch_hand"), 0, "no warband")
	# (the gate's main thread: act one's Moot - the giant stepping into the ring engages no challenge and its
	# checkpoints are not held back by it)
	await _place(w, RING)
	await step_ticks(60)
	assert_true(_orrik() == null, "stepping into the ring calls no Orrik before the rumour")
	assert_true(_arena() != null and _arena().state != BossArena.State.ENGAGED, "and engages no challenge")
	assert_false(Array(GameSession.checkpoint_blockers()).any(func(b: String) -> bool: return b.contains("orrik")),
		"nor holds back a checkpoint (%s)" % GameSession.checkpoint_blockers())


func test_the_challenge_stands_at_the_moot_and_the_preparation_thins_it() -> void:
	var w := await _world(FOOT, 8, "slain")
	await _place(w, Vector2(-40, -700))
	await step_ticks(120)
	var t := _orrik()
	assert_true(t != null, "Orrik stands at the Moot")
	if t != null:
		assert_true(Vector2(t.global_position.x, t.global_position.z).distance_to(Vector2(0, -764)) < 15.0,
			"at his post before the Stone Throne (he turns and shifts toward a giant he sees; %s)" % t.global_position)
		var ground := w.height_at(t.global_position)
		assert_true(absf(t.global_position.y - ground) < 1.0, "on the ground")
	assert_eq(_winches().size(), 5, "five fetter-winches staked in the ring")
	assert_true(_arena() != null and _arena().branch() == "vengeance", "Harrok slain: the vengeance branch")
	var w2 := w
	w2.queue_free()
	await step_ticks(3)
	var w3 := await _world(FOOT, 8, "slain", true, {"world.moot.camp_broken": true, "world.skarn.saved": true})
	await _place(w3, Vector2(-40, -700))
	await step_ticks(120)
	assert_eq(_winches().size(), 2, "the camp broken and Skarn with the giant: two winches (%d)" % _winches().size())
	assert_eq(_alive("world.stonehold.winch_hand"), 2, "and two crews")


## The bot fights Orrik in the real ring until he falls (or `max_s`); {"won", "s", "chains", "ally"}.
func _fight(w: WorldRoot, max_s: float) -> Dictionary:
	var p := w.player()
	await _place(w, RING)
	var t: HeirEnemy = null
	var guard := 0
	while t == null and guard < 300:
		await step_ticks(1)
		t = _orrik()
		guard += 1
	var arena := _arena()
	await step_ticks(30)
	if arena != null and arena.state != BossArena.State.ENGAGED:
		arena.engage()
	var bot := TitanDuelBot.new()
	bot.see_obstacles = true
	bot.setup(p, t, "expert", 1, true)
	var start := Sim.tick
	var blocked_cp := false
	var blocked_travel := false
	while Sim.tick - start < int(max_s * Sim.TICK_RATE) and p.entity.is_alive() and t.entity.is_alive():
		bot.step(Sim.tick)
		await step_ticks(1)
		if Sim.tick - start == 600:
			# mid-fight (R1's lesson): no checkpoint is taken and no fast travel is allowed while it is engaged
			blocked_cp = not GameSession.checkpoint_blockers().is_empty()
			blocked_travel = not GameSession.travel_blockers("fast_travel").is_empty()
	bot.teardown()
	var ally: Node = arena.ally if arena != null and arena.ally != null and is_instance_valid(arena.ally) else null
	var out := {"won": not t.entity.is_alive(), "died": not p.entity.is_alive(), "s": snappedf((Sim.tick - start) / 60.0, 0.1),
		"chains": p.fetter.bound, "titan_left": snappedf(t.entity.combatant.pools.ratio("health"), 0.001),
		"giant_left": snappedf(p.entity.combatant.pools.ratio("health"), 0.001), "hooks": t.hooks_bit,
		"ally": ally != null, "ally_heir_blows": int(ally.get("heir_blows")) if ally != null else 0,
		"ally_cuts": int(ally.get("chains_cut")) if ally != null else 0,
		"ally_winch_blows": int(ally.get("winch_blows")) + int(ally.get("crew_blows")) if ally != null else 0,
		"blocked_checkpoint": blocked_cp, "blocked_travel": blocked_travel}
	return out


func test_vengeance_from_the_lead_to_the_aftermath() -> void:
	var w := await _world(FOOT, 9, "slain")
	await step_ticks(10)
	assert_true(Quests.quest_state("quest.harrok_lead") == Quests.ACTIVE, "the lead: look in at the Moot")
	await _place(w, Vector2(-30, -720))
	await step_ticks(30)
	assert_true(QuestConditions.truthy(WorldState.get_flag("lead.harrok.seen")), "looked in at the Moot")
	assert_true(Quests.quest_state("quest.harrok_return") == Quests.ACTIVE, "Harrok's Return begins")
	var r := await _fight(w, 420.0)
	print("E1_WORLD_RUN " + JSON.stringify(r))
	assert_true(bool(r.won), "Orrik falls (%s)" % str(r))
	assert_false(bool(r.ally), "the giant fought alone")
	assert_true(bool(r.blocked_checkpoint), "no checkpoint mid-fight (a death or a quit goes back to before it)")
	assert_true(bool(r.blocked_travel), "no fast travel mid-fight")
	await step_ticks(30)
	assert_true(QuestConditions.truthy(WorldState.get_flag("boss.orrik.defeated")), "boss.orrik.defeated")
	assert_eq(_fighting("world.stonehold.winch_hand"), 0, "the warband has broken: gone or fleeing")
	assert_true(FactionState.is_reconciled("harrok_clan"), "the clan stands down")
	var s := Quests.start_dialogue("dialogue.moot_oath", "world.stonehold.throne_stone")
	assert_true(s != null and s.find_choice("moot_settled") >= 0, "the eldest offers the clan's oath")
	if s != null:
		s.choose_outcome("moot_settled")
	await step_ticks(10)
	assert_true(QuestConditions.truthy(WorldState.get_flag("world.moot.clan_knelt")), "the clan knelt")
	assert_true(Quests.is_complete("quest.harrok_return"), "Harrok's Return done")
	assert_true(Quests.quest_state("quest.cinder_lead") == Quests.ACTIVE or Quests.is_complete("quest.cinder_lead"),
		"the rumour of the burning road is heard")
	await _place(w, Vector2(-40, -700))
	await step_ticks(120)
	assert_true(_alive("world.stonehold.moot_sworn") >= 4, "the sworn clans stand at the Moot's stones")


func test_ally_from_the_lead_to_the_aftermath() -> void:
	var w := await _world(FOOT, 9, "spared")
	await _place(w, Vector2(-30, -720))
	await step_ticks(30)
	assert_true(Quests.quest_state("quest.harrok_return") == Quests.ACTIVE, "Harrok's Return begins")
	assert_true(_arena() != null and _arena().branch() == "ally", "Harrok spared: the ally branch")
	var r := await _fight(w, 420.0)
	print("E1_WORLD_RUN " + JSON.stringify(r))
	assert_true(bool(r.won), "Orrik falls (%s)" % str(r))
	assert_true(bool(r.ally), "Harrok stood beside the giant")
	assert_true(int(r.ally_heir_blows) + int(r.ally_cuts) + int(r.ally_winch_blows) > 0, "and fought (%s)" % str(r))
	await step_ticks(30)
	assert_true(QuestConditions.truthy(WorldState.get_flag("world.moot.harrok_holds")), "Harrok holds the Moot")
	var s := Quests.start_dialogue("dialogue.harrok", "world.stonehold.harrok")
	assert_true(s != null and s.find_choice("moot_settled") >= 0, "Harrok speaks after the fight")
	if s != null:
		s.choose_outcome("moot_settled")
	await step_ticks(10)
	assert_eq(int(WorldState.inventory.get("item.harrok_oath", 0)), 1, "his oath-ring given")
	assert_true(Quests.is_complete("quest.harrok_return"), "Harrok's Return done")
	await _place(w, Vector2(-40, -700))
	await step_ticks(120)
	assert_eq(_alive("world.stonehold.harrok_keeper"), 1, "Harrok stands by the Stone Throne")


## One stage-8 duel in the real ring each branch (the log's E1_WORLD lines): a real fight - the chains bite.
func test_a_stage_8_duel_in_the_real_ring_each_branch() -> void:
	for harrok: String in ["slain", "spared"]:
		var w := await _world(FOOT, 8, harrok)
		var r := await _fight(w, 600.0)
		r["branch"] = "vengeance" if harrok == "slain" else "ally"
		print("E1_WORLD " + JSON.stringify(r))
		assert_true(int(r.chains) >= 1, "%s: the chains bit (%s)" % [harrok, str(r)])
		assert_true(bool(r.won) or float(r.titan_left) < 0.8, "%s: a real fight (%s)" % [harrok, str(r)])
		w.queue_free()
		await step_ticks(3)
