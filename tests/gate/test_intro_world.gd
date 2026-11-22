extends IntegrationSuite
## A5: the intro cutscene over the real open world (scenes/world/world.tscn, deterministic streaming), replayed from
## the Character menu (its Watch the intro button):
##   * beside the quarry, with the real Stoneback at home in his pit, the cutscene's own Stoneback is the only one
##     shown while it plays (the level's titans are hidden), and he is shown again after, where he stood;
##   * in a fight (a checkpoint blocked) the button is disabled and plays nothing;
##   * from Stonehold, 1.5 km from the intro's focus (whose ring moves the streamer's focus far enough to unload the
##     giant's own chunks), the cutscene streams the giant's ring back in behind black before it closes: the giant
##     stands on its ground, the HUD's world runs and the game is not paused.

const SCENE := "res://scenes/world/world.tscn"
const STONEBACK := "world.crownmarch.stoneback"
const NEAR_QUARRY := Vector2(-380.0, 625.0)   # Millford's green: in his activation radius, out of his sight
const FAR := Vector2(400.0, -560.0)           # by the Skarn waystone, in Stonehold

var stack: ScreenStack


func after_each() -> void:
	if is_instance_valid(stack):
		stack.close_all()
	get_tree().paused = false
	InputRouter.set_context(InputRouter.Context.GAMEPLAY)
	for f in Formation.live():
		f.dissolve()
	FactionState.reset_for_tests()
	WanderDirector.reset_for_tests()
	GameSession.expansion = ExpansionState.defaults()
	await super()


func _world(xz: Vector2) -> WorldRoot:
	GameSession.start_world_for_tests("world.cp.millford")
	GameSession.level_id = GameSession.WORLD_LEVEL_ID
	var w := (load(SCENE) as PackedScene).instantiate() as WorldRoot
	world.add_child(w)
	w.streamer.deterministic = true
	var p := w.player()
	p.router.use_injection = true
	GameSession.on_level_ready(w, p)
	var layer := CanvasLayer.new()
	layer.layer = 10
	world.add_child(layer)
	stack = ScreenStack.new()
	layer.add_child(stack)
	await _place(w, xz)
	TitanDuel.prepare(p, 3)
	await step_ticks(2)
	return w


func _place(w: WorldRoot, xz: Vector2) -> void:
	var p := w.player()
	var at := Vector3(xz.x, 200.0, xz.y)
	p.process_mode = Node.PROCESS_MODE_DISABLED
	p.global_position = at
	var guard := 0
	while not w.streamer.ring_ready(at) and guard < 900:
		w.streamer.load_ring_slice(at)
		await step_ticks(1)
		guard += 1
	var y := w.height_at(at)
	p.global_position = Vector3(xz.x, (y if not is_nan(y) else 20.0) + 0.3, xz.y)
	p.velocity = Vector3.ZERO
	p.process_mode = Node.PROCESS_MODE_INHERIT


func _director(w: WorldRoot) -> EncounterDirector:
	return w.get_tree().get_first_node_in_group(EncounterDirector.GROUP) as EncounterDirector


## The Character menu opened, its Watch the intro pressed: the cutscene it opened (null when none).
func _replay_from_menu() -> CutsceneScreen:
	var menu := stack.open("character") as CharacterScreen
	await get_tree().process_frame
	assert_true(menu != null and menu.intro_button.visible, "the Character menu shows Watch the intro in the world")
	if menu == null or menu.intro_button.disabled:
		return null
	menu.intro_button.pressed.emit()
	await get_tree().process_frame
	return stack.top() as CutsceneScreen


func _frames_until(done: Callable, limit: int) -> bool:
	for i in limit:
		if bool(done.call()):
			return true
		await get_tree().physics_frame
	return bool(done.call())


func test_the_replay_beside_his_quarry_shows_one_stoneback() -> void:
	WanderDirector.test_active = false
	var w: WorldRoot = await _world(NEAR_QUARRY)
	var d := _director(w)
	assert_true(await TestWait.until(self, func() -> bool: return d.spawned(STONEBACK) != null, 600), "he is at home")
	var titan := d.spawned(STONEBACK) as TitanEnemy
	var home := titan.global_position
	assert_true(titan.visible, "(shown before)")
	var cs := await _replay_from_menu()
	assert_true(cs != null, "the intro plays")
	assert_true(get_tree().paused, "over the paused world")
	assert_false(stack.is_open("character"), "the menu closed first")
	assert_true(await _frames_until(func() -> bool: return cs.tick >= 1100, 2400), "the pit's shot (tick %d)" % cs.tick)
	assert_false(titan.visible, "the real Stoneback hidden while it plays: its own is the only one in the pit")
	assert_true((cs.actors.get("stoneback") as Node3D).visible, "its Stoneback shown")
	cs.skip()
	await get_tree().process_frame
	assert_false(stack.any_open(), "skipped")
	assert_true(titan.visible, "the real Stoneback shown again")
	assert_true(titan.global_position.distance_to(home) < 0.01, "where he stood")
	assert_false(get_tree().paused, "the game runs")
	assert_eq(w.find_children("Cutscene", "", true, false).size(), 0, "nothing of the cutscene left")
	w.queue_free()
	await step_ticks(2)


func test_in_a_fight_the_replay_is_refused() -> void:
	WanderDirector.test_active = false
	var w: WorldRoot = await _world(NEAR_QUARRY)
	var p := w.player()
	var was := p.controller.state
	p.controller.state = CombatController.State.GRABBED   # (a checkpoint blocked: as in a fight)
	var menu := stack.open("character") as CharacterScreen
	await get_tree().process_frame
	assert_true(menu.intro_button.visible and menu.intro_button.disabled, "disabled while a checkpoint is blocked")
	assert_eq(menu.intro_button.text, CharacterScreen.WATCH_INTRO_BLOCKED, "and says why")
	menu._on_watch_intro()
	await get_tree().process_frame
	assert_false(stack.top() is CutsceneScreen, "nothing plays")
	p.controller.state = was
	stack.close_all()
	w.queue_free()
	await step_ticks(2)


func test_from_far_away_the_giants_ground_comes_back_before_play() -> void:
	WanderDirector.test_active = false
	var w: WorldRoot = await _world(FAR)
	var p := w.player()
	var at := p.global_position
	var own := w.streamer.chunk_at(at)
	var cs := await _replay_from_menu()
	assert_true(cs != null, "the intro plays from Stonehold")
	assert_true(await _frames_until(func() -> bool: return cs.tick >= 60, 3000), "its focus streamed and its first second played")
	assert_true(await _frames_until(func() -> bool: return not w.streamer.is_loaded(own), 1200),
		"the intro's ring unloaded the giant's own chunk %s" % own)
	var closed := {}
	cs.closed.connect(func(r: Dictionary) -> void: closed.merge(r))
	cs.skip()
	await get_tree().physics_frame
	assert_true(stack.top() == cs and closed.is_empty(), "skipped, it waits behind black for the giant's ground")
	assert_true(await _frames_until(func() -> bool: return not stack.any_open(), 1200), "then closes")
	assert_true(w.streamer.ring_ready(p.global_position), "the giant's ring is loaded as play resumes")
	await step_ticks(90)
	var ground := w.height_at(p.global_position)
	assert_true(not is_nan(ground) and absf(p.global_position.y - ground) < 1.0 and p.global_position.distance_to(at) < 3.0,
		"the giant stands on its ground where it was (%.1f m above it, %.1f m away)" % [
			p.global_position.y - ground, p.global_position.distance_to(at)])
	assert_false(get_tree().paused, "the game runs")
	w.queue_free()
	await step_ticks(2)
