extends IntegrationSuite
## Fix (council; docs/systems/fix_council.md): the owner's report played as a player plays it, in the real world
## (scenes/world/world.tscn, deterministic streaming) with cutscenes on as in the Web build and a screen stack:
##   * a stage-6 giant at the Stone Throne's marker takes the throne by E for each of Harrok's ends (slain: the finale
##     played through; spared and the talk ending: skipped), the act-one finale plays, the "Act One" end screen's
##     Continue, and act two's first stage - "Hear the oath-holders at the Stone Throne" - leads, its marker before the
##     throne. There, where E used to say only "The Stone Throne is yours", the prompt is the council's; E opens it on
##     the dialogue screen, Esc leaves it unheard (the stage stays, the prompt comes back), and heard out through the
##     screen's buttons the stage completes and the Breach is next;
##   * Continue from the save act two's start wrote (the act_two checkpoint): the same prompt at the marker, and E
##     opens the council;
##   * a colossus (stages 7, 8 and 9) walking to the marker from the ring's middle, from its east side and from the
##     council's stone gets the council's prompt on arriving, facing the way it walked, and E opens it.

const SCENE := "res://scenes/world/world.tscn"
const MARKER := Vector2(0.0, -786.0)
const THRONE := "world.stonehold.stone_throne"
const PROMPT := "Hear the oath-holders at the throne"

var stack: ScreenStack
var level: Node3D
var huds: Array = []


func before_each() -> void:
	await super()
	huds.clear()
	Events.hud_message.connect(_on_hud)


func after_each() -> void:
	if Events.hud_message.is_connected(_on_hud):
		Events.hud_message.disconnect(_on_hud)
	if is_instance_valid(stack):
		stack.close_all()
	get_tree().paused = false
	Quests.end_dialogue()
	InputRouter.set_context(InputRouter.Context.GAMEPLAY)
	if level != null and is_instance_valid(level):
		level.queue_free()
	level = null
	await get_tree().process_frame
	for f in Formation.live():
		f.dissolve()
	FactionState.reset_for_tests()
	WanderDirector.reset_for_tests()
	SaveSlots.delete_slot(true)
	GameSession.persist = false
	GameSession.cutscenes_on = false
	GameSession.expansion = ExpansionState.defaults()
	await super()


func _on_hud(text: String, _kind: String) -> void:
	huds.append(text)


func _stack() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 10
	world.add_child(layer)
	stack = ScreenStack.new()
	layer.add_child(stack)


## The real world at the Moot with a giant of `stage` (grown with cutscenes off: no growth film over the test).
func _world(xz: Vector2, stage: int) -> GiantPlayer:
	GameSession.start_world_for_tests("world.cp.moot_foot")
	GameSession.level_id = GameSession.WORLD_LEVEL_ID
	GameSession.cutscenes_on = false
	WanderDirector.view_probe = func(_p: Vector3) -> bool: return false
	var w := (load(SCENE) as PackedScene).instantiate() as WorldRoot
	level = w
	world.add_child(w)
	w.streamer.deterministic = true
	var p := w.player()
	p.router.use_injection = true
	p.entity.apply_status("status.debug_invulnerable", NAN, -1.0, "test")
	GameSession.on_level_ready(w, p)
	await _place(p, xz, xz + Vector2(0, -10))
	TitanDuel.prepare(p, stage)
	await TestWait.until(self, func() -> bool: return p.current_growth_stage() == stage, 600)
	await step_ticks(200)   # (the growth settles)
	_stack()   # (after the growth: its screens are not this test's)
	return p


func _place(p: GiantPlayer, xz: Vector2, toward: Vector2) -> void:
	var w := level as WorldRoot
	var at := Vector3(xz.x, 300.0, xz.y)
	p.process_mode = Node.PROCESS_MODE_DISABLED
	p.global_position = at
	var guard := 0
	while not w.streamer.ring_ready(at) and guard < 900:
		w.streamer.load_ring_slice(at)
		await step_ticks(1)
		guard += 1
	var y := w.height_at(at)
	p.global_position = Vector3(xz.x, (y if not is_nan(y) else 100.0) + 0.3, xz.y)
	p.velocity = Vector3.ZERO
	_face(p, toward)
	p.process_mode = Node.PROCESS_MODE_INHERIT
	await step_ticks(PlayerInteract.REFRESH_TICKS + 2)


func _face(p: GiantPlayer, toward: Vector2) -> void:
	var d := toward - Vector2(p.global_position.x, p.global_position.z)
	p.facing_yaw = atan2(-d.x, -d.y)
	p.rotation.y = p.facing_yaw
	p.camera_rig.yaw = p.facing_yaw


## Act one's last stage reached the way the champion `ending` leaves it (two oaths, the Moot entered).
func _to_the_throne(p: GiantPlayer, ending: String) -> void:
	for f: String in ["world.kingsgate.lit", "oath.march.done", "oath.crown.done"]:
		WorldState.set_flag(f, true)
	WorldState.set_flag("oath.march.outcome", "help")
	WorldState.set_flag("oath.crown.outcome", "parley")
	WorldState.set_flag("boss.harrok.outcome", ending)
	Events.area_entered.emit(Sim.tick, "world.area.moot", p.entity.entity_id)
	assert_true(await TestWait.until(self, func() -> bool: return Quests.stage_of("quest.world_main") == "throne", 900),
		"%s: act one's last stage, the throne" % ending)


func _frames_until(done: Callable, limit: int) -> bool:
	for i in limit:
		if bool(done.call()):
			return true
		await get_tree().physics_frame
	return bool(done.call())


## The council stage's marker, the giant there and its prompt: the council's, from the throne.
func _assert_council_prompt(p: GiantPlayer, why: String) -> void:
	assert_eq(Quests.stage_of(ActTwo.MAIN_QUEST), "council", "%s: act two's first stage" % why)
	var obj := Quests.current_objective()
	assert_eq(str(obj.get("marker_id", "")), "world.marker.stone_throne", "%s: its marker, before the throne" % why)
	p.interact.refresh()
	assert_eq(p.interact.current_prompt(), PROMPT, "%s: the council's prompt (%s)" % [why, p.interact.current_candidate()])


## E, and the dialogue screen on the rim council.
func _press_e(p: GiantPlayer, why: String) -> DialogueScreen:
	huds.clear()
	p.router.inject_edge(&"interact")
	await _frames_until(func() -> bool: return stack.top() is DialogueScreen, 30)
	var ds := stack.top() as DialogueScreen
	assert_true(ds != null and ds.session != null and ds.session.dialogue_id == "dialogue.rim_council",
		"%s: E opens the rim council (%s, %s)" % [why, stack.top(), huds])
	assert_false(huds.has("The Stone Throne is yours. The Old Kingdom has its Giant King."), "%s: not 'the throne is yours'" % why)
	return ds


func _flow(ending: String, play_through: bool) -> void:
	var p := await _world(MARKER, 6)
	await _to_the_throne(p, ending)
	GameSession.persist = true
	GameSession.cutscenes_on = true
	await _place(p, MARKER, Vector2(0, -800))
	assert_eq(p.interact.current_prompt(), StoneThrone.DEFAULT_PROMPT, "%s: at the marker, the throne to take" % ending)
	p.router.inject_edge(&"interact")
	assert_true(await _frames_until(func() -> bool: return stack.top() is CutsceneScreen, 30), "%s: the act-one finale plays" % ending)
	var cs := stack.top() as CutsceneScreen
	if play_through:
		var cs_id := cs.get_instance_id()
		assert_true(await _frames_until(func() -> bool: return stack.top() == null or stack.top().get_instance_id() != cs_id, 2400),
			"%s: played to its end" % ending)
	else:
		await _frames_until(func() -> bool: return cs.tick >= 120, 600)
		cs.skip()
	assert_true(await _frames_until(func() -> bool: return stack.top() is EndScreen, 30), "%s: the Act One end screen" % ending)
	assert_true(ActTwo.begun(WorldState.flags), "%s: act two has begun" % ending)
	(stack.top() as EndScreen).press_continue()
	await _frames_until(func() -> bool: return not get_tree().paused, 30)
	await step_ticks(Quests.EVALUATE_EVERY_TICKS * 3)
	_assert_council_prompt(p, ending)
	# Esc mid-way: nothing heard, nothing stranded
	var ds := await _press_e(p, ending)
	if ds == null:
		return
	ds.press_choice(0)
	await get_tree().process_frame
	ds.cancel()
	await _frames_until(func() -> bool: return not stack.any_open(), 30)
	await step_ticks(Quests.EVALUATE_EVERY_TICKS * 2)
	assert_false(QuestConditions.truthy(WorldState.get_flag("act_two.council_heard")), "%s: left early, not heard" % ending)
	_assert_council_prompt(p, "%s, after leaving early" % ending)
	# heard out through the screen's buttons
	ds = await _press_e(p, "%s, again" % ending)
	var guard := 0
	while ds != null and is_instance_valid(ds) and ds.is_open() and guard < 20:
		ds.press_choice(0)
		await get_tree().process_frame
		await get_tree().process_frame
		guard += 1
	await _frames_until(func() -> bool: return not stack.any_open(), 30)
	await step_ticks(Quests.EVALUATE_EVERY_TICKS * 3)
	assert_true(QuestConditions.truthy(WorldState.get_flag("act_two.council_heard")), "%s: the council heard" % ending)
	assert_eq(Quests.stage_of(ActTwo.MAIN_QUEST), "breach", "%s: the Breach is next" % ending)


func test_slain_the_finale_played_through_then_the_council_at_the_marker() -> void:
	await _flow("slain", true)


func test_spared_the_finale_skipped_then_the_council_at_the_marker() -> void:
	await _flow("spared", false)


func test_the_talk_ending_then_the_council_and_continue_from_the_save_act_two_wrote() -> void:
	var p := await _world(MARKER, 6)
	await _to_the_throne(p, "yielded_talk")
	GameSession.persist = true
	GameSession.cutscenes_on = true
	await _place(p, MARKER, Vector2(0, -800))
	p.router.inject_edge(&"interact")
	assert_true(await _frames_until(func() -> bool: return stack.top() is CutsceneScreen, 30), "the finale plays")
	(stack.top() as CutsceneScreen).skip()
	assert_true(await _frames_until(func() -> bool: return stack.top() is EndScreen, 30), "the end screen")
	(stack.top() as EndScreen).press_continue()
	await _frames_until(func() -> bool: return not get_tree().paused, 30)
	assert_true(await TestWait.until(self, func() -> bool: return GameSession.pending_checkpoint().is_empty(), 240),
		"act two's start checkpointed")
	var doc := JsonIO.read_file(SaveSlots.path())
	var saved: Dictionary = ((doc.get("data", {}) as Dictionary).get("world", {}) as Dictionary).get("flags", {})
	assert_true(QuestConditions.truthy(saved.get("act.two.begun")), "the save holds act two's start")
	assert_false(QuestConditions.truthy(saved.get("act_two.council_heard")), "and not the council")
	stack.close_all()
	level.queue_free()
	level = null
	await get_tree().process_frame
	# Continue
	var r := GameSession.continue_valley()
	assert_true(r.ok, "Continue (%s)" % r.message)
	GameSession.cutscenes_on = true
	WanderDirector.view_probe = func(_p: Vector3) -> bool: return false
	var w := (load(SCENE) as PackedScene).instantiate() as WorldRoot
	level = w
	world.add_child(w)
	w.streamer.deterministic = true
	p = w.player()
	p.router.use_injection = true
	p.entity.apply_status("status.debug_invulnerable", NAN, -1.0, "test")
	GameSession.on_level_ready(w, p)
	await step_ticks(10)
	assert_false(stack.any_open(), "no finale and no end screen again")
	await _place(p, MARKER, Vector2(0, -800))
	await step_ticks(Quests.EVALUATE_EVERY_TICKS * 3)
	_assert_council_prompt(p, "after Continue")
	var ds := await _press_e(p, "after Continue")
	if ds != null:
		ds.cancel()


func test_a_colossus_walking_to_the_marker_gets_the_council() -> void:
	for stage: int in [7, 8, 9]:
		WorldState.clear()
		var p := await _world(Vector2(-25, -745), stage)
		WorldState.set_flag("boss.harrok.outcome", "spared")
		for f: String in ["world.kingsgate.lit", "oath.march.done", "oath.crown.done", "world.throne.claimed"]:
			WorldState.set_flag(f, true)
		WorldState.flags["campaign.completed"] = true   # (quietly: act one's end was played before)
		GameSession.begin_act_two()
		await step_ticks(Quests.EVALUATE_EVERY_TICKS * 3)
		# from the ring's middle (round the spared Harrok, who stands in the ring south of the marker), from its east
		# side (arriving facing west, the throne on the giant's right) and from the council's stone
		for from: Vector2 in [Vector2(-25, -745), Vector2(36, -780), Vector2(-22, -782)]:
			await _place(p, from, MARKER)
			var to := MARKER - from
			p.camera_rig.yaw = 0.0
			var dir := to.normalized()
			p.router.set_injected_move(Vector2(dir.x, -dir.y))
			var ticks := 0
			while ticks < 900 and Vector2(p.global_position.x, p.global_position.z).distance_to(MARKER) > 3.0:
				await step_ticks(1)
				ticks += 1
			p.router.set_injected_move(Vector2.ZERO)
			await step_ticks(PlayerInteract.REFRESH_TICKS + 2)
			var at := Vector2(p.global_position.x, p.global_position.z)
			assert_true(at.distance_to(MARKER) <= 3.5, "stage %d from %s: walked to the marker (%s, %d ticks)" % [stage, from, at, ticks])
			_assert_council_prompt(p, "stage %d arriving from %s" % [stage, from])
			var ds := await _press_e(p, "stage %d from %s" % [stage, from])
			if ds != null:
				ds.cancel()
			await _frames_until(func() -> bool: return not stack.any_open(), 30)
		stack.close_all()
		level.queue_free()
		level = null
		await step_ticks(3)
