extends IntegrationSuite
## The Quests autoload (plan §3.15 design 1, §4.5, §4.6) on fixture quests: stages run in order and
## grant their rewards once (also across re-evaluations and a checkpoint reload, with the real
## giant on the flow test level); a goal reached early completes as soon as its stage comes up; a
## quest with start_conditions starts when they hold, and abandon_when ends it without rewards
## (quest_abandoned); hits_on counts the player's connected blows per action; objectives list the
## main quest first, then the side quests (a village branch before quest.village before the
## tutorial), with marker or target positions; slice_completed opens the end screen with the
## village outcome line; the quest tracker (main + side, the prototype pacing label on quest XP)
## and the objective marker, which clamps to the screen edge.

const FLOW := "res://scenes/test/flow_test_level.tscn"
const Fx := preload("res://tests/support/quest_fixtures.gd")

var quest_events: Array = []
var xp_requests: Array = []
var slices := 0
var level: Node3D


func before_each() -> void:
	await super()
	quest_events.clear()
	xp_requests.clear()
	slices = 0
	for pair: Array in _signals():
		(pair[0] as Signal).connect(pair[1])


func after_each() -> void:
	for pair: Array in _signals():
		if (pair[0] as Signal).is_connected(pair[1]):
			(pair[0] as Signal).disconnect(pair[1])
	if level != null and is_instance_valid(level):
		level.queue_free()
	level = null
	await super()


func _signals() -> Array:
	return [[Events.quest_started, _on_quest_started], [Events.quest_stage_changed, _on_quest_stage],
		[Events.quest_completed, _on_quest_completed], [Events.quest_abandoned, _on_quest_abandoned],
		[Events.xp_award_requested, _on_xp_request], [Events.slice_completed, _on_slice_done]]


func _on_quest_started(_t: int, id: String) -> void:
	quest_events.append("started:" + id)


func _on_quest_stage(_t: int, id: String, stage: String) -> void:
	quest_events.append("stage:%s:%s" % [id, stage])


func _on_quest_completed(_t: int, id: String) -> void:
	quest_events.append("completed:" + id)


func _on_quest_abandoned(_t: int, id: String) -> void:
	quest_events.append("abandoned:" + id)


func _on_xp_request(amount: int, source: String) -> void:
	xp_requests.append([amount, source])


func _on_slice_done(_t: int) -> void:
	slices += 1


func _hit(attacker: String, target: String, action_id: String, outcome := HitResult.Outcome.HIT) -> void:
	var ev := HitEvent.new()
	ev.attacker_id = attacker
	ev.target_id = target
	ev.action_id = action_id
	var r := HitResult.new()
	r.event = ev
	r.outcome = outcome
	Events.hit_resolved.emit(Sim.tick, r)


func _marker(id: String, pos: Vector3) -> LevelMarker:
	var m := LevelMarker.new()
	m.marker_id = id
	m.position = pos
	world.add_child(m)
	return m


func _area(id: String, pos: Vector3) -> AreaTrigger:
	var a := AreaTrigger.new()
	a.area_id = id
	a.position = pos
	var cs := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = 4.0
	shape.height = 6.0
	cs.shape = shape
	cs.position.y = 3.0
	a.add_child(cs)
	world.add_child(a)
	return a


func _stack() -> ScreenStack:
	var layer := CanvasLayer.new()
	world.add_child(layer)
	var stack := ScreenStack.new()
	layer.add_child(stack)
	return stack


func _hud() -> Hud:
	var layer := CanvasLayer.new()
	world.add_child(layer)
	var hud := Hud.new()
	layer.add_child(hud)
	return hud


# --------------------------------------------------------------------------- stages and rewards

func test_stages_run_in_order_and_grant_their_rewards_once() -> void:
	var q := Fx.quest("quest.test_a", [
		Fx.stage("one", Fx.flag_cond("test.flag.go"), 10, {"set_flags": {"test.flag.one_done": true},
			"items": [{"item": "item.wood_scrap", "count": 2}]}),
		Fx.stage("two", {"type": "has_item", "item": "item.iron_ingot", "count": 1}, 20),
		Fx.stage("three", {"type": "killed", "targets": ["test.target"]}, 30)],
		{"on_complete_flags": {"test.flag.finished": true}})
	Fx.install([q])
	assert_eq(Quests.quest_state("quest.test_a"), Quests.INACTIVE, "nothing runs while quests are off")
	Quests.evaluate_now()
	assert_eq(Quests.quest_state("quest.test_a"), Quests.INACTIVE, "evaluate_now does nothing while inactive")
	Fx.activate(["quest.test_a"])
	Quests.evaluate_now()
	assert_eq(quest_events, ["started:quest.test_a"], "auto_start: started at once (no stage change for the first stage)")
	assert_eq(Quests.stage_of("quest.test_a"), "one", "stage one")
	assert_eq(WorldState.get_flag("quest.test_a.stage"), "one", "kept in the quest's stage flag")
	for i in 3:
		Quests.evaluate_now()
	assert_eq(quest_events.size(), 1, "re-evaluating changes nothing")
	WorldState.set_flag("test.flag.go", true)
	await step_ticks(1)
	assert_eq(Quests.stage_of("quest.test_a"), "two", "the hook evaluates on the next tick after a flag change")
	assert_eq(xp_requests, [[10, "quest:quest.test_a:one"]], "the stage's XP")
	assert_eq(WorldState.count_of("item.wood_scrap"), 2, "its items")
	assert_eq(WorldState.get_flag("test.flag.one_done"), true, "its set_flags")
	assert_eq(WorldState.get_flag("reward.test_a.one"), true, "its once-flag reward.test_a.one")
	for i in 3:
		Quests.evaluate_now()
	await step_ticks(12)
	assert_eq(xp_requests.size(), 1, "granted once across re-evaluations")
	WorldState.add_item("item.iron_ingot", 1)
	await step_ticks(1)
	assert_eq(Quests.stage_of("quest.test_a"), "three", "an item completes stage two")
	Events.entity_died.emit(Sim.tick, "test.target", "player")
	await step_ticks(1)
	assert_true(Quests.is_complete("quest.test_a"), "a death seen completes the last stage")
	assert_eq(Quests.quest_state("quest.test_a"), Quests.COMPLETED, "completed")
	assert_eq(WorldState.get_flag("quest.test_a.done"), true, "its done flag")
	assert_eq(Quests.stage_of("quest.test_a"), "three", "the stage flag keeps the last stage")
	assert_eq(WorldState.get_flag("test.flag.finished"), true, "on_complete_flags")
	assert_eq(quest_events, ["started:quest.test_a", "stage:quest.test_a:two", "stage:quest.test_a:three",
		"completed:quest.test_a"], "the events in order")
	assert_eq(xp_requests, [[10, "quest:quest.test_a:one"], [20, "quest:quest.test_a:two"],
		[30, "quest:quest.test_a:three"]], "each stage's XP once")
	assert_true(Quests.objectives().is_empty(), "no objective once complete")
	assert_false(Quests.start_quest("quest.test_a"), "a completed quest does not start again")


## [§4.5] Every condition reads world state: goals reached early complete as soon as their stage
## comes up, in the same evaluation.
func test_goals_reached_early_complete_when_their_stage_comes_up() -> void:
	var q := Fx.quest("quest.test_b", [Fx.stage("a", Fx.flag_cond("test.flag.a"), 1),
		Fx.stage("b", Fx.flag_cond("test.flag.b"), 2), Fx.stage("c", Fx.flag_cond("test.flag.c"), 4)])
	Fx.install([q])
	Fx.activate(["quest.test_b"])
	WorldState.set_flag("test.flag.b", true)
	WorldState.set_flag("test.flag.c", true)
	Quests.evaluate_now()
	assert_eq(Quests.stage_of("quest.test_b"), "a", "waiting at the first stage")
	WorldState.set_flag("test.flag.a", true)
	var tick := Sim.tick
	Quests.evaluate_now()
	assert_true(Quests.is_complete("quest.test_b"), "all three stages in one evaluation")
	assert_eq(Sim.tick, tick, "in the same tick")
	assert_eq(xp_requests.size(), 3, "every stage rewarded once")


func test_start_conditions_start_a_quest_and_abandon_when_ends_it_without_rewards() -> void:
	var start := [Fx.flag_cond("quest.village.offer", "cache")]
	var abandon := {"type": "all", "of": [{"type": "flag", "flag": "quest.village.outcome"},
		{"type": "not", "of": Fx.flag_cond("quest.village.outcome", "help_cache")}]}
	var branch := Fx.quest("quest.test_cache", [
		Fx.stage("get_cache", {"type": "has_item", "item": "item.supply_cache", "count": 1}, 10),
		Fx.stage("return_cache", Fx.flag_cond("quest.village.outcome", "help_cache"), 50)],
		{"auto_start": false, "start_conditions": start, "abandon_when": abandon})
	Fx.install([branch])
	Fx.activate(["quest.test_cache"])
	Quests.evaluate_now()
	assert_eq(Quests.quest_state("quest.test_cache"), Quests.INACTIVE, "not started without the offer")
	WorldState.set_flag("quest.village.offer", "ogre")
	Quests.evaluate_now()
	assert_eq(Quests.quest_state("quest.test_cache"), Quests.INACTIVE, "another offer does not start it")
	WorldState.set_flag("quest.village.offer", "cache")
	Quests.evaluate_now()
	assert_eq(Quests.quest_state("quest.test_cache"), Quests.ACTIVE, "the offer starts it")
	assert_eq(quest_events, ["started:quest.test_cache"], "started")
	assert_eq(Quests.stage_of("quest.test_cache"), "get_cache", "at its first stage")
	WorldState.add_item("item.supply_cache", 1)
	Quests.evaluate_now()
	assert_eq(Quests.stage_of("quest.test_cache"), "return_cache", "the cache found")
	assert_eq(xp_requests.size(), 1, "its reward")
	WorldState.try_set_flag("quest.village.outcome", "intimidate")
	Quests.evaluate_now()
	assert_eq(Quests.quest_state("quest.test_cache"), Quests.ABANDONED, "another outcome abandons it")
	assert_eq(WorldState.get_flag("quest.test_cache.done"), false, "done = false")
	assert_true(quest_events.has("abandoned:quest.test_cache"), "quest_abandoned")
	assert_false(quest_events.has("completed:quest.test_cache"), "not completed")
	assert_eq(xp_requests.size(), 1, "no reward for the abandoned stage")
	assert_false(Quests.is_complete("quest.test_cache"), "not complete")
	for i in 3:
		Quests.evaluate_now()
	assert_eq(Quests.quest_state("quest.test_cache"), Quests.ABANDONED, "it never restarts")
	assert_true(Quests.objectives().is_empty(), "and lists no objective")
	# The same branch with the help outcome completes.
	WorldState.clear()
	quest_events.clear()
	WorldState.set_flag("quest.village.offer", "cache")
	WorldState.add_item("item.supply_cache", 1)
	Quests.evaluate_now()
	WorldState.try_set_flag("quest.village.outcome", "help_cache")
	Quests.evaluate_now()
	assert_true(Quests.is_complete("quest.test_cache"), "the help outcome completes it")
	assert_false(quest_events.has("abandoned:quest.test_cache"), "and does not abandon it")


func test_hits_on_counts_the_players_connected_blows_per_action() -> void:
	var q := Fx.quest("quest.test_train", [Fx.stage("train", {"type": "all", "of": [
		{"type": "hits_on", "targets": ["test.dummy_1", "test.dummy_2"], "count": 3, "action_kind": "light"},
		{"type": "hits_on", "targets": ["test.dummy_1", "test.dummy_2"], "count": 1, "action_kind": "heavy"},
		{"type": "hits_on", "targets": ["test.dummy_1", "test.dummy_2"], "count": 1, "action_id": "ability.heavy_footfall"}]}, 10)])
	Fx.install([q])
	Fx.activate(["quest.test_train"])
	Quests.evaluate_now()
	_hit("player", "test.dummy_1", "ability.light_1")
	_hit("player", "test.dummy_2", "ability.light_2")
	_hit("soldier_01", "test.dummy_1", "ability.light_1")
	_hit("player", "test.dummy_1", "ability.light_1", HitResult.Outcome.EVADED)
	_hit("player", "test.elsewhere", "ability.light_1")
	_hit("player", "test.dummy_1", "ability.heavy_1")
	_hit("player", "test.dummy_2", "ability.heavy_footfall")
	Quests.evaluate_now()
	assert_eq(Quests.stage_of("quest.test_train"), "train", "two lights that count: not yet")
	var ctx := Quests.condition_context()
	assert_eq(QuestConditions.hit_count(ctx, ["test.dummy_1", "test.dummy_2"], "light", ""), 2,
		"another attacker's, an evaded and a blow on another target do not count")
	_hit("player", "test.dummy_1", "ability.light_3", HitResult.Outcome.BLOCKED)
	Quests.evaluate_now()
	assert_true(Quests.is_complete("quest.test_train"), "a blocked blow still connected: light x3, heavy, Footfall")


## [§3.15 tests] Rewards are granted once across three re-evaluations and a checkpoint reload, with
## the real giant (its progression receives the XP) on the flow test level.
func test_rewards_are_granted_once_across_reevaluations_and_a_checkpoint_reload() -> void:
	GameSession.level_override = FLOW
	GameSession.start_new_valley()
	Fx.install([Fx.quest("quest.test_c", [Fx.stage("one", Fx.flag_cond("test.flag.go"), 60),
		Fx.stage("two", Fx.flag_cond("test.flag.never"), 30)])])
	Fx.activate(["quest.test_c"])
	Quests.test_active = false
	assert_true(Quests.is_active(), "the Valley mode turns quests on")
	level = (load(FLOW) as PackedScene).instantiate() as Node3D
	world.add_child(level)
	var p := level.get_node("Player") as GiantPlayer
	p.router.use_injection = true
	GameSession.on_level_ready(level, p)
	await step_ticks(2)
	assert_eq(Quests.stage_of("quest.test_c"), "one", "started by the hook")
	WorldState.set_flag("test.flag.go", true)
	await step_ticks(2)
	assert_eq(Quests.stage_of("quest.test_c"), "two", "stage one done")
	assert_eq(p.progression.xp, 60, "the giant got 60 XP")
	var taken: Dictionary = GameSession.take_checkpoint("test")
	assert_true(taken.ok, "a checkpoint (%s)" % taken)
	for i in 3:
		Quests.evaluate_now()
	assert_eq(p.progression.xp, 60, "still 60 after three re-evaluations")
	GameSession.reload_checkpoint("debug")
	level.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	level = (load(FLOW) as PackedScene).instantiate() as Node3D
	world.add_child(level)
	p = level.get_node("Player") as GiantPlayer
	p.router.use_injection = true
	GameSession.on_level_ready(level, p)
	await step_ticks(3)
	for i in 3:
		Quests.evaluate_now()
	assert_eq(p.progression.xp, 60, "after the reload: 60 XP, not 120")
	assert_eq(Quests.stage_of("quest.test_c"), "two", "the stage came back with the checkpoint")
	assert_eq(WorldState.get_flag("reward.test_c.one"), true, "and the reward flag")
	assert_eq(xp_requests, [[60, "quest:quest.test_c:one"]], "XP requested once in all")


# --------------------------------------------------------------------------- objectives

func test_objectives_list_the_main_quest_first_then_side_quests_with_positions() -> void:
	var main := Fx.quest("quest.test_main", [Fx.stage("gate", Fx.flag_cond("test.flag.gate"), 0,
		{"marker": "test.marker.gate", "bot": {"action": "break", "target": "test.gate"}}),
		Fx.stage("crown", Fx.flag_cond("test.flag.crown"), 0)], {"display_name": "The Test of Kings"})
	var village := Fx.quest("quest.test_village", [Fx.stage("meet", {"type": "entered", "area": "test.area.square"})],
		{"auto_start": false})
	var branch := Fx.quest("quest.test_village_ogre", [Fx.stage("kill", {"type": "killed", "targets": ["test.ogre"]})],
		{"auto_start": false})
	var tutorial := Fx.quest("quest.test_tutorial", [Fx.stage("train", Fx.flag_cond("test.flag.train"))])
	Fx.install([main, village, branch, tutorial])
	Fx.activate(["quest.test_main", "quest.test_village", "quest.test_village_ogre", "quest.test_tutorial"],
		[], "quest.test_main")
	var gate := _marker("test.marker.gate", Vector3(10, 0, -20))
	var ogre := TestSpawn.stub_enemy(world, Vector3(5, 0.05, 5), "test.ogre")
	var square := _area("test.area.square", Vector3(-20, 0, 0))
	await step_ticks(2)
	var ids: Array = []
	for o: Dictionary in Quests.objectives():
		ids.append(o.quest_id)
	assert_eq(ids, ["quest.test_main", "quest.test_village_ogre", "quest.test_village", "quest.test_tutorial"],
		"main first; then quests started by conditions (the branch before quest.village), then auto-started ones")
	var cur := Quests.current_objective()
	assert_eq(cur.quest_id, "quest.test_main", "the current objective is the main quest's")
	assert_eq([cur.stage_id, cur.text, cur.kind, cur.marker_id], ["gate", "Objective gate", "flag", "test.marker.gate"],
		"stage, text, kind and marker")
	assert_true((cur.position as Vector3).is_equal_approx(gate.global_position), "its marker's position")
	assert_eq(cur.bot, {"action": "break", "target": "test.gate"}, "the bot hint")
	assert_eq([cur.title, cur.main, cur.stage_index, cur.stage_count], ["The Test of Kings", true, 0, 2], "title and progress")
	var by_id := {}
	for o: Dictionary in Quests.objectives():
		by_id[o.quest_id] = o
	assert_true((by_id["quest.test_village_ogre"].position as Vector3).is_equal_approx(ogre.global_position),
		"no marker: the living target's position")
	assert_eq(by_id["quest.test_village_ogre"].targets, PackedStringArray(["test.ogre"]), "its targets")
	assert_true((by_id["quest.test_village"].position as Vector3).is_equal_approx(square.global_position),
		"an area's position")
	assert_false((by_id["quest.test_tutorial"].position as Vector3).is_finite(), "a flag stage has no position")
	assert_false(bool(by_id["quest.test_village"].main), "a side quest")
	WorldState.set_flag("test.flag.gate", true)
	WorldState.set_flag("test.flag.crown", true)
	await step_ticks(1)
	assert_true(Quests.is_complete("quest.test_main"), "the main quest done")
	assert_eq(Quests.current_objective().quest_id, "quest.test_village_ogre", "the first side quest is current")
	assert_true(Quests.debug_lines().size() == 1 and Quests.debug_lines()[0].begins_with("QUESTS "), "a debug line")


# --------------------------------------------------------------------------- the end

func test_the_end_screen_opens_on_slice_completed_with_the_outcome_line() -> void:
	var stack := _stack()
	Fx.install([Fx.quest("quest.test_end", [Fx.stage("crown", Fx.flag_cond("test.flag.crown"), 50)],
		{"on_complete_flags": {"slice.completed": true}})])
	Fx.activate(["quest.test_end"], [], "quest.test_end")
	WorldState.try_set_flag("quest.village.outcome", "help_ogre")
	Quests.evaluate_now()
	assert_eq(slices, 0, "not yet")
	WorldState.set_flag("test.flag.crown", true)
	Quests.evaluate_now()
	assert_eq(WorldState.get_flag("slice.completed"), true, "slice.completed set on completion")
	assert_eq(slices, 1, "slice_completed once")
	await get_tree().process_frame
	assert_true(stack.is_open("end"), "the end screen opens")
	var screen := stack.top() as EndScreen
	assert_true(screen != null, "an EndScreen")
	if screen != null:
		var lines := screen.visible_lines()
		assert_true(lines.has("Thornwick: you drove off the ogre"), "the village outcome line (%s)" % [lines])
		assert_true(lines.has("Deaths: 0"), "deaths")
		assert_true(lines.has("Level 1, growth stage 1"), "level and stage")
		assert_true(get_tree().paused, "it pauses the game")
		assert_true(screen.first_focus() == screen.continue_button, "Continue exploring has the focus")
		screen.press_continue()
	assert_false(stack.any_open(), "Continue exploring closes it")
	assert_false(get_tree().paused, "play goes on")
	for i in 3:
		Quests.evaluate_now()
	assert_eq(slices, 1, "the end comes once")
	assert_eq(EndScreen.outcome_line("help_cache"), "Thornwick: you returned their stolen cache", "help_cache")
	assert_eq(EndScreen.outcome_line("help_ogre"), "Thornwick: you drove off the ogre", "help_ogre")
	assert_eq(EndScreen.outcome_line("intimidate"), "Thornwick: they opened the bridge in fear", "intimidate")
	assert_eq(EndScreen.outcome_line("force"), "Thornwick: you smashed your way through", "force")
	assert_eq(EndScreen.format_time(1453.4), "24:13", "minutes and seconds")
	assert_eq(EndScreen.format_time(3723.0), "1:02:03", "past an hour")
	Events.slice_completed.emit(Sim.tick)
	await get_tree().process_frame
	screen = stack.top() as EndScreen
	assert_true(screen != null, "slice_completed from anywhere opens it")
	if screen != null:
		screen.press_quit()
	assert_false(stack.any_open(), "Quit to title closes it")
	assert_true(GameSession.scene_reloads.has("title"), "and asks GameSession for the title")


## The main quest's completion is a checkpoint too (GameSession checkpoints main stages): the end
## of the slice is saved in the same tick, before the end screen opens.
func test_completing_the_main_quest_saves_a_checkpoint_before_the_end_screen() -> void:
	var stack := _stack()
	GameSession.level_override = FLOW
	GameSession.start_new_valley()
	Fx.install([Fx.quest("quest.test_end", [Fx.stage("crown", Fx.flag_cond("slice.crown_claimed"), 50)],
		{"on_complete_flags": {"slice.completed": true}})])
	Fx.activate(["quest.test_end"], [], "quest.test_end")
	level = (load(FLOW) as PackedScene).instantiate() as Node3D
	world.add_child(level)
	var p := level.get_node("Player") as GiantPlayer
	p.router.use_injection = true
	GameSession.on_level_ready(level, p)
	await step_ticks(2)
	var before := GameSession.checkpoints_taken
	WorldState.try_set_flag("slice.crown_claimed", true)
	await step_ticks(1)
	assert_true(Quests.is_complete("quest.test_end"), "complete")
	assert_eq(GameSession.checkpoints_taken, before + 1, "a checkpoint in the same tick")
	var doc := GameSession.checkpoint_doc
	assert_eq(str(doc.checkpoint.reason), "quest_complete", "for the quest's completion")
	assert_eq(doc.world.flags.get("slice.completed"), true, "the save knows the slice is complete")
	assert_eq(doc.world.flags.get("quest.test_end.done"), true, "and the quest")
	assert_eq(int(doc.character.xp), 50, "with the last stage's XP")
	await get_tree().process_frame
	assert_true(stack.is_open("end"), "then the end screen")
	(stack.top() as EndScreen).press_continue()
	assert_false(stack.any_open(), "closed")


# --------------------------------------------------------------------------- HUD

func test_the_tracker_shows_main_and_side_objectives_and_the_pacing_label() -> void:
	var p := spawn_player(Vector3(0, 0.05, 0))
	var hud := _hud()
	var main := Fx.quest("quest.test_main", [Fx.stage("gate", Fx.flag_cond("test.flag.gate"), 60,
		{"objective": "Break the practice gate"}), Fx.stage("crown", Fx.flag_cond("test.flag.crown"), 0,
		{"objective": "Claim the crown"})], {"display_name": "The Test of Kings"})
	var side := Fx.quest("quest.test_village", [Fx.stage("meet", Fx.flag_cond("test.flag.met"), 0,
		{"objective": "Speak with the elder"})], {"auto_start": false, "display_name": "Thornwick"})
	Fx.install([main, side])
	var tracker := hud.get_node_or_null("QuestTracker")
	assert_true(tracker != null, "the tracker is on the HUD")
	if tracker == null:
		return
	await get_tree().process_frame
	assert_eq(tracker.call("visible_text"), "", "hidden while quests are off")
	Fx.activate(["quest.test_main", "quest.test_village"], [], "quest.test_main")
	await step_ticks(2)
	await get_tree().process_frame
	var lines: Dictionary = tracker.call("lines_now")
	assert_eq([lines.main_title, lines.main_text, lines.side_title, lines.side_text],
		["The Test of Kings", "Break the practice gate", "Thornwick", "Speak with the elder"], "main and side")
	WorldState.set_flag("test.flag.gate", true)
	await step_ticks(2)
	await get_tree().process_frame
	assert_eq(p.progression.xp, 60, "the stage's XP reached the giant")
	var text: String = tracker.call("visible_text")
	assert_true(text.contains("Claim the crown"), "the next objective")
	assert_true(text.contains("+60 XP  -  Prototype pacing: accelerated quest XP"), "the pacing label on quest XP (%s)" % text)
	assert_eq(Quests.pacing_label(), str(GameData.get_record("progression.default").prototype_xp_label), "from the record")
	assert_true(Quests.paced_source("dialogue:dialogue.elder"), "dialogue rewards are paced too")
	assert_false(Quests.paced_source("kill:soldier_01"), "kills are not")
	assert_eq(load("res://ui/hud/quest_tracker.gd").call("lines_for", [], true, "The Test of Kings").main_text,
		"Complete. The valley is yours to explore.", "after the slice the main line says so")


## [§3.15 tests] The objective marker clamps to the screen edge.
func test_the_objective_marker_projects_and_clamps_to_the_screen_edge() -> void:
	var p := spawn_player(Vector3(0, 0.05, 0), 0.0)   # faces -Z
	var hud := _hud()
	var ahead := _marker("test.marker.ahead", Vector3(0, 2, -40))
	var behind := _marker("test.marker.behind", Vector3(6, 2, 40))
	Fx.install([Fx.quest("quest.test_main", [
		Fx.stage("go", Fx.flag_cond("test.flag.go"), 0, {"marker": "test.marker.ahead"}),
		Fx.stage("back", Fx.flag_cond("test.flag.back"), 0, {"marker": "test.marker.behind"})])])
	Fx.activate(["quest.test_main"], [], "quest.test_main")
	var w := hud.get_node_or_null("ObjectiveMarker")
	assert_true(w != null, "the marker widget is on the HUD")
	if w == null:
		return
	await step_ticks(3)
	await get_tree().process_frame
	var view := hud.get_viewport_rect().size
	var place: Dictionary = w.call("placement_now")
	assert_false(place.is_empty(), "shown")
	if place.is_empty():
		return
	var cam := p.camera_rig.camera
	assert_true(bool(place.on_screen), "a marker ahead is on screen")
	assert_true((place.position as Vector2).distance_to(cam.unproject_position(ahead.global_position)) < 1.0,
		"at its projection")
	assert_eq(w.call("visible_text"), "40 m", "its distance")
	WorldState.set_flag("test.flag.go", true)
	await step_ticks(2)
	await get_tree().process_frame
	place = w.call("placement_now")
	assert_false(place.is_empty() or bool(place.on_screen), "a marker behind the camera is off screen")
	var pos: Vector2 = place.position
	var inset := minf(minf(pos.x, view.x - pos.x), minf(pos.y, view.y - pos.y))
	assert_near(inset, 36.0, 0.5, "clamped 36 px inside the screen edge")
	assert_true((place.direction as Vector2).y > 0.5, "on the bottom edge: behind")
	assert_true((place.direction as Vector2).x > 0.0, "toward the right, where it is")
	var right: Dictionary = load("res://ui/hud/objective_marker.gd").call("placement", cam,
		p.global_position + Vector3(200, 2, -5), view, 36.0)
	assert_false(bool(right.on_screen), "far to the right is off screen")
	assert_near((right.position as Vector2).x, view.x - 36.0, 0.5, "clamped to the right edge")
	var edge: Vector2 = load("res://ui/hud/objective_marker.gd").call("edge_point", Vector2(1280, 720), Vector2(-1, 0), 36.0)
	assert_eq(edge, Vector2(36, 360), "straight left: 36 px inside the left edge")
	behind.queue_free()
	await get_tree().process_frame
	Quests.refresh_positions()
	await step_ticks(1)
	await get_tree().process_frame
	assert_true((w.call("placement_now") as Dictionary).is_empty(), "no position: hidden")
