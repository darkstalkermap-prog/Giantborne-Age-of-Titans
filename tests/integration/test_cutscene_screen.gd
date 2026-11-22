extends IntegrationSuite
## A4: the cutscene player (CutsceneScreen) in a level: it pauses the game, takes the camera, places its actors,
## shows the skip hint by device, skips at once on any confirm or cancel (the camera given back, its actors freed),
## and GameSession counts a cutscene once closed (seen: never again for this game).

const FLOW := "res://scenes/test/flow_test_level.tscn"

var level: Node3D
var stack: ScreenStack


func before_each() -> void:
	await super()
	level = (load(FLOW) as PackedScene).instantiate() as Node3D
	world.add_child(level)
	var layer := CanvasLayer.new()
	layer.layer = 10
	world.add_child(layer)
	stack = ScreenStack.new()
	layer.add_child(stack)
	GameSession.expansion = ExpansionState.defaults()
	await get_tree().process_frame


func after_each() -> void:
	GameSession.loading_gate = null
	GameSession.intro_due = false
	if is_instance_valid(stack):
		stack.close_all()
	get_tree().paused = false
	InputRouter.set_context(InputRouter.Context.GAMEPLAY)
	GameSession.expansion = ExpansionState.defaults()
	await super()


func _open() -> CutsceneScreen:
	var s := stack.open("cutscene", {"cutscene": ExpansionState.INTRO_ID, "level": level}) as CutsceneScreen
	await get_tree().process_frame
	return s


func test_it_plays_pauses_and_takes_the_camera() -> void:
	var before := get_viewport().get_camera_3d()
	var s := await _open()
	assert_true(s != null, "the cutscene screen opens")
	var result := {}
	s.closed.connect(func(r: Dictionary) -> void: result.merge(r))
	assert_true(get_tree().paused, "the game is paused")
	assert_true(s.camera != null and s.camera.is_current(), "its camera is the view")
	assert_eq(s.actors.size(), (s.rec.actors as Array).size(), "its actors are placed")
	assert_true(s.nav_hint(true).contains("skip") and s.nav_hint(true).contains("A"), "the pad's skip hint")
	assert_true(s.nav_hint(false).contains("Esc"), "the keyboard's")
	for i in 70:
		await get_tree().physics_frame
	assert_true(s.tick > 30, "the timeline runs while the game is paused (tick %d)" % s.tick)
	assert_eq(s.subtitle(), CutsceneRules.line_at(s.rec, s.tick), "the subtitle of its tick")
	assert_true(s.cues_played.size() >= 1, "its first cue")
	var ev := InputEventAction.new()
	ev.action = "ui_accept"
	ev.pressed = true
	Input.parse_input_event(ev)
	await get_tree().process_frame
	await get_tree().process_frame
	assert_false(stack.any_open(), "a confirm skips it at once")
	assert_true(bool(result.get("skipped", false)), "skipped (%s)" % str(result))
	assert_false(get_tree().paused, "the game runs again")
	assert_true(before == null or get_viewport().get_camera_3d() == before, "the camera given back")
	assert_false(level.has_node("Cutscene"), "its actors are freed")


func test_esc_skips_it_and_the_session_notes_it_seen() -> void:
	var s := GameSession.play_cutscene(ExpansionState.INTRO_ID)
	if s == null:
		s = await _open()
		s.closed.connect(GameSession._on_cutscene_closed.bind(ExpansionState.INTRO_ID))
	await get_tree().process_frame
	assert_true(s is CutsceneScreen, "the intro opens")
	var ev := InputEventKey.new()
	ev.keycode = KEY_ESCAPE
	ev.physical_keycode = KEY_ESCAPE
	ev.pressed = true
	Input.parse_input_event(ev)
	await get_tree().process_frame
	await get_tree().process_frame
	assert_false(stack.any_open(), "Esc skips it")
	assert_true(ExpansionState.seen(GameSession.expansion, ExpansionState.INTRO_ID), "this game has seen it")
	var doc := ExpansionState.write_into({}, GameSession.expansion)
	assert_true((doc.cinematics_seen as Array).has(ExpansionState.INTRO_ID), "the next checkpoint keeps it")


## B1 (the milestone A gate's row): the intro does not open while the loading screen is up - level_entered comes
## inside main's loading gate; the intro waits until the gate lets go, then opens.
class LoadingStub extends Node:
	var loading := true

	func is_loading() -> bool:
		return loading


func test_the_intro_waits_for_the_loading_gate() -> void:
	var gate := LoadingStub.new()
	world.add_child(gate)
	GameSession.loading_gate = gate
	GameSession.intro_due = true
	var played := GameSession.cutscenes_played.size()
	GameSession._on_level_entered_cutscene(Sim.tick, GameSession.WORLD_LEVEL_ID, "test")
	for i in 4:
		await get_tree().process_frame
	assert_false(stack.any_open(), "not while the loading screen is up")
	assert_eq(GameSession.cutscenes_played.size(), played, "nothing played")
	assert_false(GameSession.intro_due, "but it is on its way (due no more)")
	gate.loading = false
	for i in 3:
		await get_tree().process_frame
	assert_eq(GameSession.cutscenes_played.size(), played + 1, "the gate let go: the intro opens")
	assert_true(stack.any_open() and stack.top() is CutsceneScreen, "over the level")
	# skipped as a player would: the camera and the tree given back (a suite after this one hears and draws by them)
	var cam := (stack.top() as CutsceneScreen).camera
	var ev := InputEventKey.new()
	ev.keycode = KEY_ESCAPE
	ev.physical_keycode = KEY_ESCAPE
	ev.pressed = true
	Input.parse_input_event(ev)
	await get_tree().process_frame
	await get_tree().process_frame
	assert_false(stack.any_open(), "Esc skips it")
	assert_false(get_tree().paused, "the game runs again")
	assert_true(not is_instance_valid(cam) or not cam.is_current(), "its camera given back")

