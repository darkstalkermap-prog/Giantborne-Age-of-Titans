extends IntegrationSuite
## P27 (plan M6-M9 §2.14, §3.10 design 4): the journal on fixture quests and the stub level of
## tests/support/world_ux_fixtures.gd. JournalScreen.sections() lists the active quests with their
## step, objective and region, the waiting ones with their waiting_text, the completed ones, the
## oaths settled, the sealed places seen with the stage they need (gone once the seal opens) and the
## regions' journal notes; "Track" tracks a quest (Quests.track); and the screen with a pad: the Track
## buttons top to bottom, A tracks, B closes - and J closes it from a keyboard. M8 gate (F22): the
## shipped world's Regions section describes all five regions (each record's journal_note; m7_note is
## only the M7 rule's "still waiting for its package" now).

const Fx := preload("res://tests/support/quest_fixtures.gd")
const Wux := preload("res://tests/support/world_ux_fixtures.gd")

var stack: ScreenStack


func before_each() -> void:
	await super()
	InputBindings.reset_device()
	var layer := CanvasLayer.new()
	layer.layer = 10
	world.add_child(layer)
	stack = ScreenStack.new()
	stack.name = "ScreenStack"
	layer.add_child(stack)


func after_each() -> void:
	if is_instance_valid(stack):
		stack.close_all()
	get_tree().paused = false
	InputRouter.set_context(InputRouter.Context.GAMEPLAY)
	GameSession.mode = GameSession.Mode.SANDBOX
	await super()


func _pad(button: JoyButton) -> void:
	for pressed in [true, false]:
		var e := InputEventJoypadButton.new()
		e.button_index = button
		e.pressed = pressed
		e.device = 0
		Input.parse_input_event(e)
		await get_tree().process_frame
	await get_tree().process_frame


func _marker(id: String, pos: Vector3) -> void:
	var m := LevelMarker.new()
	m.marker_id = id
	m.position = pos
	world.add_child(m)


## The stub level as the campaign level, and four quests: the main one (two steps, on the second,
## its marker in the north), a side quest in the south, one waiting for stage 5 and one completed.
func _quests() -> void:
	Wux.install()
	GameSession.mode = GameSession.Mode.VALLEY
	GameSession.level_id = Wux.LEVEL
	_marker("test.m.town", Vector3(0, 0, -100))
	_marker("test.m.vista", Vector3(100, 0, 100))
	Fx.install([
		Fx.quest("quest.test_main", [Fx.stage("first", Fx.flag_cond("test.flag.first")),
			Fx.stage("north", Fx.flag_cond("test.flag.never"), 0, {"objective": "Climb to the town", "marker": "test.m.town"})],
			{"display_name": "The Main Thread"}),
		Fx.quest("quest.test_side_a", [Fx.stage("go", Fx.flag_cond("test.flag.never"), 0,
			{"objective": "Look out from the vista", "marker": "test.m.vista"})], {"display_name": "Side A"}),
		Fx.quest("quest.test_side_b", [Fx.stage("wait", Fx.flag_cond("test.flag.never"), 0,
			{"objective": "Open the sealed place", "waiting_text": "Waiting: stage 5"})], {"display_name": "Side B"}),
		Fx.quest("quest.test_done", [Fx.stage("go", Fx.flag_cond("test.flag.never"))],
			{"display_name": "An Old Errand", "auto_start": false}),
	])
	Fx.activate(["quest.test_main", "quest.test_side_a", "quest.test_side_b", "quest.test_done"], [], "quest.test_main")
	WorldState.set_flag("test.flag.first", true)
	WorldState.set_flag(Quests.stage_flag("quest.test_done"), "go")
	WorldState.set_flag(Quests.done_flag("quest.test_done"), true)


func test_the_journal_lists() -> void:
	_quests()
	await step_ticks(3)
	Quests.refresh_positions()
	var s := JournalScreen.sections()
	var active: Array = (s.active as Array).map(func(q: Dictionary) -> Array: return [q.id, q.step, q.steps, q.text, q.region, q.tracked])
	assert_eq(active, [["quest.test_main", 2, 2, "Climb to the town", "The North Test", true],
		["quest.test_side_a", 1, 1, "Look out from the vista", "The South Test", false]],
		"the active quests: step, objective and region; the main one tracked")
	assert_eq((s.waiting as Array).map(func(q: Dictionary) -> Array: return [q.id, q.waiting]),
		[["quest.test_side_b", "Waiting: stage 5"]], "the waiting quest with its waiting_text")
	assert_eq(s.completed, [{"id": "quest.test_done", "title": "An Old Errand"}], "the completed quest")
	assert_eq(s.oaths, [], "no oath settled yet")
	assert_eq(s.sealed, [], "no sealed place seen yet")
	var notes: Array = (s.regions as Array).filter(func(r: Dictionary) -> bool: return str(r.id).begins_with("region.test_p27"))
	assert_eq(notes, [{"id": Wux.NORTH, "name": "The North Test", "note": "The north comes later."}],
		"the region with a journal note (the south has none)")
	WorldState.set_flag("oath.march.outcome", "intimidate")
	WorldState.set_flag("sealed.test_p27_seal.seen", true)
	s = JournalScreen.sections()
	assert_eq(s.oaths, [{"oath": "march", "name": "Brannock's oath", "outcome": "intimidate"}], "an oath settled")
	assert_eq(s.sealed, [{"id": "poi.test_p27_seal", "name": "Seal", "stage": 5, "region": "The South Test"}],
		"a sealed place seen, with the stage it needs")
	var j := stack.open("journal") as JournalScreen
	assert_true(j != null and stack.is_open("journal"), "the journal opens")
	var page := "\n".join(j.lines())
	for want: String in ["# Quests", "* The Main Thread: Step 2 of 2: Climb to the town", "# Waiting",
			"Side B: Step 1 of 1: Open the sealed place  -  Waiting: stage 5", "# Completed", "An Old Errand", "# Oaths",
			"Brannock's oath: Intimidate", "# Sealed places", "Seal (The South Test)  -  Grow to stage 5", "# Regions",
			"The North Test: The north comes later."]:
		assert_true(page.contains(want), "the page shows '%s'" % want)
	assert_true(j.press_track("quest.test_side_a"), "Track a side quest")
	assert_eq(Quests.tracked_id(), "quest.test_side_a", "it is tracked")
	assert_eq(str(Quests.current_objective().quest_id), "quest.test_side_a", "the objective follows")
	assert_eq(j.track_button("quest.test_side_a").text, "Tracked", "its button says so")
	assert_eq(j.track_button("quest.test_main").text, "Track", "and the main quest's is free again")
	assert_true(j.lines().has("* Side A: Step 1 of 1: Look out from the vista"), "the page marks the tracked quest")
	assert_false(j.press_track("quest.test_done"), "a completed quest cannot be tracked")
	WorldState.record_destroyed(Wux.SEAL)
	j.rebuild()
	assert_false("\n".join(j.lines()).contains("# Sealed places"), "an opened seal leaves the list")
	j.close()


func test_the_journal_with_a_pad() -> void:
	_quests()
	await step_ticks(3)
	var j := stack.open("journal") as JournalScreen
	await get_tree().process_frame
	await get_tree().process_frame
	assert_true(j.track_button("quest.test_main").has_focus(), "the first Track button has the focus")
	await _pad(JOY_BUTTON_DPAD_DOWN)
	assert_true(j.track_button("quest.test_side_a").has_focus(), "D-pad Down: the next quest")
	await _pad(JOY_BUTTON_DPAD_DOWN)
	assert_true(j.track_button("quest.test_side_b").has_focus(), "and the waiting one")
	await _pad(JOY_BUTTON_A)
	assert_eq(Quests.tracked_id(), "quest.test_side_b", "A tracks it")
	assert_true(j.track_button("quest.test_side_b").has_focus(), "the focus stays on it after the page is rebuilt")
	await _pad(JOY_BUTTON_DPAD_DOWN)
	assert_true(j.close_button.has_focus(), "then Close")
	await _pad(JOY_BUTTON_DPAD_DOWN)
	assert_true(j.track_button("quest.test_main").has_focus(), "wrapping to the top")
	await _pad(JOY_BUTTON_B)
	assert_false(stack.is_open("journal"), "B closes the journal")
	stack.open("journal")
	await get_tree().process_frame
	var key := InputEventKey.new()
	key.physical_keycode = KEY_J
	key.pressed = true
	Input.parse_input_event(key)
	await get_tree().process_frame
	key = key.duplicate()
	key.pressed = false
	Input.parse_input_event(key)
	await get_tree().process_frame
	assert_false(stack.is_open("journal"), "J closes it again")


## M8 gate (F22): every region of the world has its line under Regions, from its journal_note.
func test_the_regions_section_describes_all_five_regions_of_the_world() -> void:
	var regions := GameData.records_of_type("region").filter(func(r: Dictionary) -> bool:
		return str(r.get("level", "")) == "level.world")
	assert_eq(regions.size(), 5, "the world's five regions")
	var s := JournalScreen.sections()
	var listed := {}
	for r: Dictionary in s.regions:
		listed[str(r.id)] = str(r.note)
	for rec: Dictionary in regions:
		var id := str(rec.id)
		assert_true(str(listed.get(id, "")) != "", "%s has its line under Regions (%s)" % [id, listed.keys()])
		assert_eq(str(listed.get(id, "")), str(rec.get("journal_note", "")), "%s's line is its journal_note" % id)
		assert_eq(str(rec.get("m7_note", "")), "", "%s no longer waits for its package (M8 ships them all)" % id)
	var j := stack.open("journal") as JournalScreen
	var page := j.lines()
	var at := page.find("# Regions")
	assert_true(at >= 0, "the page has its Regions section")
	for rec: Dictionary in regions:
		assert_true(page.has("%s: %s" % [rec.display_name, rec.get("journal_note", "")]), "the page describes %s" % rec.id)
	j.close()
