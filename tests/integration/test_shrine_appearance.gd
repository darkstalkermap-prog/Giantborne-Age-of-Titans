extends IntegrationSuite
## The shrine's Appearance tab (P44; plan M10 §2.10, decision 15): the seventh tab, last; its button reads
## "Appearance (new)" until the tab is first opened (the flag appearance.tab_seen); it shows the look in words
## for the giant's line and "Change your look...", which opens the creator over the shrine screen - with the
## root viewport's 3D off while the creator is on top and on again after; Keep this look puts the record on the
## player (PlayerAppearance.set_record) and emits Events.appearance_changed once; Cancel after a change asks,
## and Discard restores the look in memory without an event. The checkpoint re-taken and written at a real
## shrine, Continue after quitting and a death reload: tests/slow/test_shrine_appearance_saves.gd (a world
## start and a shrine scene cost more than the default tier's cap allows; P42 moved its shrine case likewise).

var stack: ScreenStack
var changed: Array = []   ## [tick, entity_id] of Events.appearance_changed


func before_each() -> void:
	await super()
	InputBindings.reset_device()
	var layer := CanvasLayer.new()
	layer.layer = 10
	world.add_child(layer)
	stack = ScreenStack.new()
	layer.add_child(stack)
	changed.clear()
	Events.appearance_changed.connect(_on_changed)
	await get_tree().process_frame


func after_each() -> void:
	if Events.appearance_changed.is_connected(_on_changed):
		Events.appearance_changed.disconnect(_on_changed)
	if is_instance_valid(stack):
		stack.close_all()
	get_tree().paused = false
	get_tree().root.disable_3d = false
	InputRouter.set_context(InputRouter.Context.GAMEPLAY)
	InputBindings.reset_device()
	await super()


func _on_changed(tick: int, entity_id: String) -> void:
	changed.append([tick, entity_id])


func test_the_appearance_tab_keeps_and_cancels_a_look() -> void:
	var p := spawn_player(Vector3(0, 0.05, 0))
	await step_ticks(1)
	var screen := stack.open("shrine", {"player": p}) as ShrineScreen
	assert_true(screen != null, "the shrine screen opens")
	if screen == null:
		return
	var titles: Array = screen.tabs.map(func(t: ShrineTab) -> String: return t.tab_title())
	assert_eq(titles.back() if not titles.is_empty() else "", "Appearance", "the Appearance tab is the last")
	var tab := screen.tab("Appearance")
	var button: Button = screen.tab_buttons()[screen.tabs.find(tab)]
	assert_eq(button.text, "Appearance (new)", "it reads (new) until first opened")
	screen.show_tab(screen.tabs.find(tab))
	assert_true(QuestConditions.truthy(WorldState.get_flag("appearance.tab_seen")), "opening it sets appearance.tab_seen")
	assert_eq(button.text, "Appearance", "and the mark goes")
	var summary: String = tab.call("summary_text")
	assert_true(summary.begins_with("Hair: long, combed back, chestnut, a little grey"), "the look in words: %s" % summary)
	assert_true(summary.contains("Clothing: wanderer's braies"), "every part: %s" % summary)
	assert_eq(UiNav.focus_owner(screen), tab.get("change_button"), "Change your look... has the focus")
	# Change -> the creator over the shrine, the world's 3D off while it is on top.
	var creator := tab.call("press_change") as CreatorScreen
	assert_true(creator != null and stack.top() == creator, "Change your look... opens the creator over the shrine")
	if creator == null:
		return
	assert_eq(creator.context, "shrine", "for the shrine")
	assert_eq(creator.begin_button.text, CreatorScreen.KEEP, "Keep this look")
	assert_eq(creator.back_button.text, "Cancel", "and Cancel")
	assert_true(get_tree().root.disable_3d, "the root viewport's 3D is off while the creator is on top")
	assert_true(creator.preview.weapon != null, "the preview holds the equipped weapon")
	assert_true(get_tree().paused, "the game stays paused")
	creator.show_category("Hair")
	assert_true(creator.pick("hair.color", "haircolor.copper"), "a new hair colour")
	creator.begin_button.pressed.emit()
	assert_false(stack.is_open("creator"), "Keep closes the creator")
	assert_false(get_tree().root.disable_3d, "and the 3D is on again")
	assert_eq(stack.top(), screen, "back on the shrine screen")
	assert_eq(str(p.appearance.record().hair.color), "haircolor.copper", "the player wears the new look")
	assert_true(p.appearance.has_record(), "as a record of his own")
	assert_eq(changed.size(), 1, "appearance_changed fired once")
	if changed.size() == 1:
		assert_eq(str(changed[0][1]), p.entity.entity_id, "for the player")
	assert_eq(str(tab.call("result_text")), "Your new look is kept.", "the tab says so")
	assert_true(str(tab.call("summary_text")).contains("copper"), "and the summary follows")
	# Cancel after a change asks; Discard restores the look without an event.
	var before: Dictionary = p.appearance.record()
	creator = tab.call("press_change") as CreatorScreen
	creator.show_category("Skin")
	creator.pick("skin", "skin.deep")
	creator.back_button.pressed.emit()
	assert_true(creator.question_open(), "Cancel after a change asks")
	creator.discard_button.pressed.emit()
	assert_false(stack.is_open("creator"), "Discard closes the creator")
	assert_true(OptionRows.same(p.appearance.record(), before), "the look is as it was")
	assert_eq(changed.size(), 1, "no event")
	assert_eq(str(tab.call("result_text")), "Your look is unchanged.", "the tab says so")
	assert_false(get_tree().root.disable_3d, "the 3D is on")
	screen.cancel()
	# A new shrine screen: the tab was seen in this save, no (new).
	screen = stack.open("shrine", {"player": p}) as ShrineScreen
	tab = screen.tab("Appearance")
	assert_eq((screen.tab_buttons()[screen.tabs.find(tab)] as Button).text, "Appearance", "no (new) once seen")
