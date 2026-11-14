extends IntegrationSuite
## A look changed at a real shrine is saved (P44; plan M10 §2.10, the M8 gate's F15 rule): the Kingsgate shrine
## in the world (saving on), its screen opened by interact(), the Appearance tab's "Change your look...", a
## change in the creator and Keep this look: the shrine's checkpoint is re-taken and written at once (the save
## holds the look while the shrine screen is still open), a death reload keeps it, and Quit to title then
## Continue restore it; Cancel restores the look without a write. In the slow tier: a world start and a shrine
## scene cost more than the default tier's cap allows (tests/integration/test_shrine_appearance.gd covers the
## tab and the creator over it in the default tier).

const SHRINE := "res://scenes/world/shrine.tscn"
const SHRINE_ID := "world.shrine.kingsgate"

var stack: ScreenStack


func before_each() -> void:
	await super()
	InputBindings.reset_device()
	var layer := CanvasLayer.new()
	layer.layer = 10
	world.add_child(layer)
	stack = ScreenStack.new()
	layer.add_child(stack)
	await get_tree().process_frame


func after_each() -> void:
	if is_instance_valid(stack):
		stack.close_all()
	get_tree().paused = false
	get_tree().root.disable_3d = false
	InputRouter.set_context(InputRouter.Context.GAMEPLAY)
	InputBindings.reset_device()
	SaveSlots.delete_slot(true)
	GameSession.persist = false
	await super()


## The campaign in level.world with saving on, the giant at the Kingsgate shrine.
func _start() -> Dictionary:
	GameSession.persist = true
	GameSession.start_world_for_tests("world.cp.kingsgate_shelf")
	GameSession.level_id = "level.world"
	var p := spawn_player(Vector3(0, 0.05, 0), 0.0)
	GameSession.on_level_ready(world, p)
	p.global_position = Vector3(0, 0.05, 0)
	p.velocity = Vector3.ZERO
	await step_ticks(2)
	var s: Shrine = (load(SHRINE) as PackedScene).instantiate()
	s.world_id = SHRINE_ID
	s.shrine_id = "shrine.world_kingsgate"
	s.position = Vector3(0, 0, -6)
	world.add_child(s)
	await step_ticks(2)
	return {"player": p, "shrine": s}


## interact(): GameSession checkpoints, the stack opens the shrine screen; then the Appearance tab.
func _appearance_tab(s: Shrine, p: GiantPlayer) -> ShrineTab:
	s.interact(p)
	await get_tree().process_frame
	await get_tree().process_frame
	var screen := stack.top() as ShrineScreen
	assert_true(screen != null, "the shrine screen opened")
	if screen == null:
		return null
	var tab := screen.tab("Appearance")
	screen.show_tab(screen.tabs.find(tab))
	return tab


func _saved_look() -> Dictionary:
	var doc := SaveSlots.read()
	assert_true(doc.ok, "the save slot reads (%s)" % doc.message)
	var ch: Dictionary = doc.data.get("character", {}) if doc.ok else {}
	return ch.get("appearance", {}) if typeof(ch.get("appearance")) == TYPE_DICTIONARY else {}


## Opens the creator from the tab and gives the hair `color`.
func _change(tab: ShrineTab, color: String) -> CreatorScreen:
	var c := tab.call("press_change") as CreatorScreen
	assert_true(c != null, "Change your look... opens the creator")
	if c != null:
		c.show_category("Hair")
		assert_true(c.pick("hair.color", color), "a new hair colour (%s)" % color)
	return c


func test_keep_at_a_shrine_is_saved_at_once_and_survives_a_death() -> void:
	var st := await _start()
	var p: GiantPlayer = st.player
	var tab := await _appearance_tab(st.shrine, p)
	if tab == null:
		return
	var taken := GameSession.checkpoints_taken
	var c := _change(tab, "haircolor.white")
	c.begin_button.pressed.emit()
	await get_tree().process_frame
	await get_tree().process_frame
	assert_true(GameSession.checkpoints_taken > taken, "Keep re-takes the shrine's checkpoint")
	assert_eq(str((_saved_look().get("hair", {}) as Dictionary).get("color", "")), "haircolor.white",
		"the save holds the new look while the shrine screen is still open")
	assert_true(stack.is_open("shrine"), "(the shrine screen is open)")
	(stack.top() as ShrineScreen).cancel()   # Leave
	await step_ticks(2)
	GameSession.reload_checkpoint("death")
	p.queue_free()
	await step_ticks(2)
	var q := spawn_player(Vector3(5, 0.05, 0))
	GameSession.on_level_ready(world, q)
	await step_ticks(2)
	assert_eq(str(q.appearance.record().hair.color), "haircolor.white", "a death reload keeps the look")
	assert_true(q.appearance.has_record(), "as the giant's own record")


func test_cancel_writes_nothing_and_continue_restores_a_kept_look() -> void:
	var st := await _start()
	var p: GiantPlayer = st.player
	var tab := await _appearance_tab(st.shrine, p)
	if tab == null:
		return
	var taken := GameSession.checkpoints_taken
	var saved := _saved_look()
	var c := _change(tab, "haircolor.red")
	c.back_button.pressed.emit()
	assert_true(c.question_open(), "Cancel after a change asks")
	c.discard_button.pressed.emit()
	await get_tree().process_frame
	await get_tree().process_frame
	assert_eq(GameSession.checkpoints_taken, taken, "Cancel takes no checkpoint")
	assert_true(OptionRows.same(_saved_look(), saved), "and writes nothing")
	assert_true(str(p.appearance.record().hair.color) != "haircolor.red", "the look is restored")
	c = _change(tab, "haircolor.copper")
	c.begin_button.pressed.emit()
	await get_tree().process_frame
	await get_tree().process_frame
	(stack.top() as ShrineScreen).cancel()
	await step_ticks(1)
	GameSession.go_to_title()
	p.queue_free()
	await step_ticks(2)
	var r := GameSession.continue_valley()
	assert_true(bool(r.ok), "Continue loads the save (%s)" % r.message)
	var q := spawn_player(Vector3(5, 0.05, 0))
	GameSession.on_level_ready(world, q)
	await step_ticks(2)
	assert_eq(str(q.appearance.record().hair.color), "haircolor.copper", "Continue after quitting restores the look")
