extends IntegrationSuite
## The quest system in the real Valley (P13, plan §3.15 with P10b's scene; slow, runs with --slow):
## a New Game turns quests on by itself (Valley mode); a fixture main quest starts on the first
## ticks, finds its objective markers through the Valley's LevelRoot, and completes its first
## stage when the giant walks into valley.area.forest_edge (its 60 XP reach the giant once); a
## fixture prompt triggered by valley.area.hollow_start shows at the Cradle where New Game wakes
## the giant, and two camera toggles dismiss it; the HUD tracker and objective marker follow.

const Fx := preload("res://tests/support/quest_fixtures.gd")
const QUEST := "quest.test_valley"
const PROMPT := "tutorial.test_camera"

var level: LevelRoot


func after_each() -> void:
	if level != null and is_instance_valid(level):
		level.queue_free()
	level = null
	await super()


func _hud() -> Hud:
	var layer := CanvasLayer.new()
	world.add_child(layer)
	var hud := Hud.new()
	layer.add_child(hud)
	return hud


func test_a_new_game_runs_quests_and_prompts_on_the_valleys_markers_and_areas() -> void:
	GameSession.start_new_valley()
	Fx.install([
		Fx.quest(QUEST, [
			Fx.stage("leave_hollow", {"type": "entered", "area": "valley.area.forest_edge"}, 60,
				{"marker": "valley.marker.forest_trail", "objective": "Follow the trail north into the Old Wood"}),
			Fx.stage("wolves", {"type": "encounter_cleared", "encounter": "encounter.forest_wolves_a"}, 30,
				{"marker": "valley.marker.wolves_a", "objective": "Survive the wolf pack"})],
			{"display_name": "The Valley of Broken Kings"}),
		Fx.prompt(PROMPT, {"type": "entered", "area": "valley.area.hollow_start"},
			{"type": "event", "event": "camera_mode_changed", "count": 2},
			{"text": "Press {camera_toggle} to see through the giant's eyes. Press it again to step back."})])
	Fx.activate([QUEST], [PROMPT], QUEST)
	Quests.test_active = false
	level = ValleyProbe.instance(true)
	world.add_child(level)
	var p := level.player()
	p.router.use_injection = true
	GameSession.on_level_ready(level, p)
	var hud := _hud()
	await step_ticks(3)
	assert_true(Quests.is_active(), "the Valley mode turns quests on")
	assert_eq(Quests.stage_of(QUEST), "leave_hollow", "the main quest started on New Game")
	var obj := Quests.current_objective()
	var trail := level.marker("valley.marker.forest_trail")
	assert_true(trail != null, "the Valley has the forest trail marker")
	if trail != null:
		assert_true((obj.position as Vector3).is_equal_approx(trail.global_position), "the objective is at its marker")
	var start_area := level.area("valley.area.hollow_start")
	assert_true(start_area != null, "the Valley has the hollow_start trigger")
	await TestWait.until(self, func() -> bool: return start_area != null and start_area.player_inside, 30)
	await step_ticks(2)
	assert_eq(str(Quests.current_tutorial().get("id", "")), PROMPT, "the camera prompt shows at the Cradle")
	await get_tree().process_frame
	var prompt_widget := hud.get_node_or_null("TutorialPrompt")
	assert_true(prompt_widget != null and str(prompt_widget.call("visible_text")).begins_with("Press %s" %
		InputBindings.describe_action("camera_toggle", false)), "its text with the key")
	var tracker := hud.get_node_or_null("QuestTracker")
	assert_true(tracker != null and str(tracker.call("visible_text")).contains("Follow the trail north"),
		"the tracker shows the objective")
	var marker_widget := hud.get_node_or_null("ObjectiveMarker")
	assert_true(marker_widget != null and str(marker_widget.call("visible_text")).ends_with(" m"),
		"the objective marker shows its distance")
	for i in 2:
		p.router.inject_edge(&"camera_toggle")
		await step_ticks(3)
	assert_true(Quests.current_tutorial().is_empty(), "two camera toggles dismiss it")
	assert_eq(WorldState.get_flag(PROMPT + ".done"), true, "its lesson is done")
	var edge := level.area("valley.area.forest_edge")
	assert_true(edge != null, "the Valley has the forest_edge trigger")
	if edge == null:
		return
	GameSession.place_player(p, Transform3D(Basis(), edge.global_position + Vector3(0, 0.1, 0)))
	await TestWait.until(self, func() -> bool: return Quests.stage_of(QUEST) == "wolves", 60)
	assert_eq(Quests.stage_of(QUEST), "wolves", "walking into forest_edge completes the stage")
	assert_eq(p.progression.xp, 60, "its 60 XP reached the giant once")
	var wolves := level.marker("valley.marker.wolves_a")
	if wolves != null:
		assert_true((Quests.current_objective().position as Vector3).is_equal_approx(wolves.global_position),
			"the next objective is at the wolves' marker")
	WorldState.set_flag(EncounterDirector.cleared_flag("encounter.forest_wolves_a"), true)
	await step_ticks(2)
	assert_true(Quests.is_complete(QUEST), "the director's cleared flag completes the last stage")
	assert_eq(p.progression.xp, 90, "and its 30 XP")
