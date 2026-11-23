extends IntegrationSuite
## A look changed at a real shrine is saved (P44; plan M10 §2.10, the M8 gate's F15 rule): the Kingsgate shrine
## in the world (saving on), its screen opened by interact(), the Appearance tab's "Change your look...", a
## change in the creator and Keep this look: the shrine's checkpoint is re-taken and written at once (the save
## holds the look while the shrine screen is still open), a death reload keeps it, and Quit to title then
## Continue restore it; Cancel restores the look without a write. In the slow tier: a world start and a shrine
## scene cost more than the default tier's cap allows (tests/integration/test_shrine_appearance.gd covers the
## tab and the creator over it in the default tier).
##
## A save whose look a later build made (tests/fixtures/saves/v2_appearance_v3_future.json; M10 gate, LB-1):
## Continue says the default look is shown until it is changed; Keep without a change writes nothing and the
## save's record stays the later build's, byte for byte; a kept change writes this build's record, the giant
## wears it and the next load no longer carries the note. Cancel after a change and Reset never touch or show
## the later build's record, and a later build's record of shapes this build does not know opens every
## category without an engine error.

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


func test_a_later_builds_look_in_a_save_is_replaced_by_a_kept_change() -> void:
	GameSession.persist = true
	var doc: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/saves/v2_appearance_v3_future.json"))
	var later := JSON.stringify((doc.character as Dictionary).appearance)
	SaveSlots.write(doc)
	assert_true(GameSession.continue_valley().ok, "Continue")
	assert_true(str(GameSession.last_load_message).contains(Appearance.NOTE_FUTURE), "the load says the default look is shown until it is changed")
	var p := spawn_player(Vector3(0, 0.05, 0), 0.0)
	GameSession.on_level_ready(world, p)
	await step_ticks(2)
	assert_eq(str(p.appearance.look().hair_mesh), str(GiantLook.DEFAULT_LOOK.hair_mesh), "the default look is shown")
	var screen := stack.open("shrine", {"player": p}) as ShrineScreen
	assert_true(screen != null, "the shrine screen opens")
	if screen == null:
		return
	var tab := screen.tab("Appearance")
	screen.show_tab(screen.tabs.find(tab))
	# Keep without a change: the save still holds the later build's record.
	var c := tab.call("press_change") as CreatorScreen
	c.begin_button.pressed.emit()
	await get_tree().process_frame
	await get_tree().process_frame
	assert_eq(JSON.stringify(p.appearance.record()), later, "Keep without a change: the later build's record in memory, untouched")
	assert_eq(JSON.stringify(_saved_look()), later, "and in the save")
	# A kept change: this build's record, in memory and in the save.
	c = _change(tab, "haircolor.red")
	assert_true(c.pick("hair.style", "hair.shaved"), "and a new style")
	c.begin_button.pressed.emit()
	await get_tree().process_frame
	await get_tree().process_frame
	var rec: Dictionary = p.appearance.record()
	assert_false(Appearance.is_future(rec), "after a kept change the record is this build's")
	assert_eq(str(p.appearance.look().hair_mesh), str(Appearance.option("hair.shaved").get("mesh", "")), "the giant wears the hair chosen")
	var saved := _saved_look()
	assert_eq(int(saved.get("v", 0)), Appearance.RECORD_VERSION, "the save holds this build's record")
	assert_eq(str((saved.get("hair", {}) as Dictionary).get("style", "")), "hair.shaved", "with the look chosen")
	assert_false(saved.has("horns"), "and nothing of the later build's record under this build's version")
	assert_false(str(SaveSlots.read().message).contains(Appearance.NOTE_FUTURE), "the next load no longer says the default look is shown")


func test_a_later_builds_look_survives_cancel_reset_and_unknown_shapes() -> void:
	var p := spawn_player(Vector3(0, 0.05, 0))
	await step_ticks(1)
	var doc: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/saves/v2_appearance_v3_future.json"))
	var later: Dictionary = (doc.character as Dictionary).appearance
	p.appearance.restore_record(later)
	var stored := JSON.stringify(p.appearance.record())
	var events := [0]
	var count := func(_tick: int, _id: String) -> void: events[0] += 1
	Events.appearance_changed.connect(count)
	var screen := stack.open("shrine", {"player": p}) as ShrineScreen
	var tab := screen.tab("Appearance")
	screen.show_tab(screen.tabs.find(tab))
	# Cancel after a change: untouched.
	var c := tab.call("press_change") as CreatorScreen
	c.show_category("Skin")
	assert_true(c.pick("skin", "skin.deep"), "a pick")
	c.back_button.pressed.emit()
	assert_true(c.question_open(), "Cancel after a change asks")
	c.discard_button.pressed.emit()
	assert_eq(JSON.stringify(p.appearance.record()), stored, "Cancel leaves the later build's record untouched")
	assert_eq(events[0], 0, "no event")
	# Reset and Undo never bring the later build's record into the screen.
	c = tab.call("press_change") as CreatorScreen
	c.show_category("Hair")
	c.pick("hair.color", "haircolor.red")
	c.reset()
	assert_false(Appearance.is_future(c.current_record()), "Reset returns to the default look shown, not the later build's record")
	assert_false(c.is_changed(), "which is the look the screen opened with")
	c.undo()
	c.undo()
	assert_false(Appearance.is_future(c.current_record()), "nor does Undo")
	c.back_button.pressed.emit()
	if c.question_open():
		c.discard_button.pressed.emit()
	# A later build's record of shapes this build does not know: every category opens (an engine error fails
	# the test), and a kept pick stores a clean record of this build.
	p.appearance.restore_record({"v": 3, "skin": {"tone": "#a0785a"}, "hair": "braids", "tattoos": ["a", "b"], "scars": {"k": 1},
		"outfit": null})
	screen.notify_changed()
	c = tab.call("press_change") as CreatorScreen
	for cat: String in OptionRows.CATEGORIES:
		c.show_category(cat)
		await get_tree().process_frame
	c.show_category("Scars")
	var scar := str(Appearance.option_ids("scar")[0])
	assert_true(c.pick("scar." + scar.get_slice(".", 1), true), "a scar on")
	c.begin_button.pressed.emit()
	var rec: Dictionary = p.appearance.record()
	assert_true(Appearance.is_valid(rec, p.appearance.ancestry()) and (rec.scars as Array).has(scar), "kept as a valid record of this build: %s" % [rec])
	assert_eq(events[0], 1, "appearance_changed fired once")
	Events.appearance_changed.disconnect(count)


## B5 (B4's FOLLOWUPS row): at a shrine the creator's Armour toggle draws the armour the giant wears over the preview -
## off when it opens (the giant's own clothes, the record edited), on: the look as the world draws it (its armour's
## meshes over the record); the record kept is the giant's own either way.
func test_the_creator_shows_the_worn_armour_on_its_toggle() -> void:
	var st := await _start()
	var p: GiantPlayer = st.player
	GameSession.expansion.equipment = Armour.equipment_with(Armour.set_pieces("armour_set.quarry"))
	Armour.refresh_player(p)
	var tab := await _appearance_tab(st.shrine, p)
	if tab == null:
		return
	var c := tab.call("press_change") as CreatorScreen
	assert_true(c != null and c.armour_button != null, "the creator at a shrine has the Armour toggle")
	if c == null or c.armour_button == null:
		return
	var eq: Dictionary = GameSession.expansion.equipment
	var bare := Appearance.to_look(c.record, c.ancestry)
	var dressed := Armour.look_of(c.record, eq, c.ancestry)
	assert_true(JSON.stringify(bare) != JSON.stringify(dressed), "(the armour changes the look)")
	assert_eq(JSON.stringify(c.preview.last_look), JSON.stringify(bare), "it opens on the giant's own clothes")
	c.armour_button.pressed.emit()
	assert_true(c.show_armour, "the toggle on")
	assert_eq(JSON.stringify(c.preview.last_look), JSON.stringify(dressed), "the preview wears the armour")
	assert_true(c.pick("hair.color", "haircolor.white"), "a change with the armour shown")
	assert_eq(JSON.stringify(c.preview.last_look), JSON.stringify(Armour.look_of(c.record, eq, c.ancestry)),
		"drawn with the armour still on")
	assert_false(JSON.stringify(c.record).contains("quarry"), "the record edited holds no armour")
	c.armour_button.pressed.emit()
	assert_eq(JSON.stringify(c.preview.last_look), JSON.stringify(Appearance.to_look(c.record, c.ancestry)), "off again")
	GameSession.expansion = ExpansionState.defaults()
