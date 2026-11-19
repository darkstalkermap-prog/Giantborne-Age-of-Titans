extends TestSuite
## The creator with a mouse (M10 gate, findings LA-1 and LA-2): real events through Input.parse_input_event,
## a press, some frames, then the release, as a hand clicks; the pointer may move a little while the button
## is held. No other suite sends a mouse event to the creator (they call pressed.emit()), so these two were
## missed:
##   * a click on a preset below the focused one was lost when the pointer moved at all while held, because
##     the focused preset's description closed on the press and every button under it jumped up 40 px;
##   * the first click on a swatch was swallowed whenever the focus was outside its row, because the row sent
##     the focus back to its chosen swatch while the button was held.
## Checked here: every preset is put on by one click with the focus on the first preset, and no preset button
## moves when the focus moves; the first click on a swatch of every swatch row applies it with the focus on
## the category's first row; entering a swatch row with the keyboard still lands on the chosen swatch.

var layer: CanvasLayer
var stack: ScreenStack


func before_each() -> void:
	InputBindings.reset_device()
	layer = CanvasLayer.new()
	layer.layer = 10
	add_child(layer)
	stack = ScreenStack.new()
	stack.name = "ScreenStack"
	layer.add_child(stack)
	await get_tree().process_frame


func after_each() -> void:
	_button(Vector2(-10, -10), false)   # never leave the left button held for the next suite
	if is_instance_valid(stack):
		stack.close_all()
	if is_instance_valid(layer):
		layer.queue_free()
	get_tree().paused = false
	InputRouter.set_context(InputRouter.Context.GAMEPLAY)
	InputBindings.reset_device()
	await get_tree().process_frame


func _open_creator() -> CreatorScreen:
	var c := stack.open("creator", {"context": "new_game", "start": {"mode": "valley", "options": {"new_game": true}}}) \
		as CreatorScreen
	assert_true(c != null, "the creator opens")
	return c


func _focus() -> Control:
	return get_viewport().gui_get_focus_owner()


## The window position of a control's middle.
func _pos(c: Control) -> Vector2:
	var r := c.get_global_rect()
	return get_viewport().get_final_transform() * (r.position + r.size * 0.5)


func _motion(pos: Vector2) -> void:
	var mm := InputEventMouseMotion.new()
	mm.position = pos
	mm.global_position = pos
	Input.parse_input_event(mm)
	Input.flush_buffered_events()


func _button(pos: Vector2, pressed: bool) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = pressed
	e.position = pos
	e.global_position = pos
	if pressed:
		e.button_mask = MOUSE_BUTTON_MASK_LEFT
	Input.parse_input_event(e)
	Input.flush_buffered_events()


## A hand's click on the middle of `c`: the pointer moves there, the press, three frames, a motion event at
## the same spot when `jitter` (a hand rarely holds the pointer perfectly still), the release, two frames.
func _click(c: Control, jitter := true) -> void:
	var pos := _pos(c)
	_motion(pos)
	await get_tree().process_frame
	_button(pos, true)
	for i in 3:
		await get_tree().process_frame
	if jitter:
		_motion(pos)
	_button(pos, false)
	await get_tree().process_frame
	await get_tree().process_frame


func _key(action: String) -> void:
	for pressed in [true, false]:
		var e := InputEventAction.new()
		e.action = action
		e.pressed = pressed
		Input.parse_input_event(e)
		Input.flush_buffered_events()
	await get_tree().process_frame


func test_one_click_puts_on_any_preset_and_the_list_keeps_still() -> void:
	var c := _open_creator()
	await get_tree().process_frame
	await get_tree().process_frame
	assert_eq(c.current_category(), "Presets", "it opens on Presets")
	var ids := Appearance.preset_ids()
	var first := c.row("preset." + str(ids[0])) as OptionRows.PresetRow
	for jitter: bool in [true, false]:
		var lost := PackedStringArray()
		var moved := PackedStringArray()
		for id: String in ids:
			# as the screen opens: the focus on the first preset, a look that is not this preset's
			c.show_category("Presets")
			c.set_record(Appearance.preset_record(str(ids[1] if id == str(ids[0]) else ids[0])))
			await get_tree().process_frame
			await get_tree().process_frame
			assert_eq(_focus(), first.button, "the focus starts on the first preset")
			var pr := c.row("preset." + id) as OptionRows.PresetRow
			var before := pr.button.get_global_rect()
			var pos := _pos(pr.button)
			_motion(pos)
			await get_tree().process_frame
			_button(pos, true)
			for i in 3:
				await get_tree().process_frame
			if not pr.button.get_global_rect().is_equal_approx(before):
				moved.append("%s: y %.0f -> %.0f" % [id.get_slice(".", 1), before.position.y, pr.button.get_global_rect().position.y])
			if jitter:
				_motion(pos)
			_button(pos, false)
			await get_tree().process_frame
			await get_tree().process_frame
			if str(c.current_record().preset) != id:
				lost.append(id.get_slice(".", 1))
			assert_eq(_focus(), pr.button, "the clicked preset has the focus (%s)" % id)
		var how := "the pointer moving while held" if jitter else "the pointer still"
		assert_eq(moved, PackedStringArray(), "no preset button moves while the mouse button is held (%s)" % how)
		assert_eq(lost, PackedStringArray(), "one click puts on every preset with the focus on the first (%s)" % how)
	# every preset's description can be read: the focused preset's is shown, in a place that does not move the list
	for id: String in ids:
		var pr := c.row("preset." + id) as OptionRows.PresetRow
		pr.button.grab_focus()
		await get_tree().process_frame
		var want := str(GameData.get_record(id).get("description", ""))
		assert_true(want != "" and c.preset_description() == want, "the focused preset's description is shown (%s): %s" % [id,
			c.preset_description()])


func test_the_first_click_on_a_swatch_applies_it_from_any_focus() -> void:
	var c := _open_creator()
	await get_tree().process_frame
	var cases := [["Hair", "hair.color", "haircolor.black"], ["Beard", "beard.color", "haircolor.white"],
		["Tattoos", "tattoos.ink", "ink.soot"], ["War paint", "paint.color", "paintcolor.blood"],
		["Clothing", "outfit.dyes.cloth", "dye.madder"], ["Clothing", "outfit.dyes.leather", "dye.bone"],   # P53: the record v2's paths
		["Skin", "skin", "skin.tan"], ["Eyes", "eyes", "eyes.blue"]]
	for jitter: bool in [false, true]:
		var lost := PackedStringArray()
		for case: Array in cases:
			c.set_record(Appearance.default_record())
			c.show_category(case[0])
			await get_tree().process_frame
			await get_tree().process_frame
			var row := c.row(case[1]) as OptionRows.SwatchRow
			var b: Button = row.buttons[case[2]]
			assert_true(str(OptionRows.value_of(c.current_record(), case[1])) != case[2], "%s starts on another swatch" % case[1])
			var presses := [0]
			var count := func() -> void: presses[0] += 1
			b.pressed.connect(count)
			await _click(b, jitter)
			b.pressed.disconnect(count)
			var got := str(OptionRows.value_of(c.current_record(), case[1]))
			if got != case[2] or presses[0] != 1 or _focus() != b:
				lost.append("%s (got %s, pressed %d, focus %s)" % [case[1], got, presses[0], _focus().name if _focus() != null else "none"])
			assert_eq(row.name_label.text, str(row.choice(case[2]).name), "%s: the clicked swatch is named" % case[1])
		assert_eq(lost, PackedStringArray(), "the first click on a swatch applies it, the focus on the category's first row (%s)" %
			("the pointer moving while held" if jitter else "the pointer still"))
	# after a click on a button outside the rows (Skin and Eyes failed this way): Undo, then a swatch
	c.show_category("Skin")
	c.set_record(Appearance.default_record())
	c.pick("skin", "skin.deep")
	await get_tree().process_frame
	await _click(c.undo_button)
	assert_eq(str(c.current_record().skin), str(Appearance.default_record().skin), "a click on Undo undoes")
	var skin := c.row("skin") as OptionRows.SwatchRow
	await _click(skin.buttons["skin.tan"])
	assert_eq(str(c.current_record().skin), "skin.tan", "and the next click on a swatch applies it at once")
	# one click is one step of the undo history
	var steps := c.history.size()
	await _click(skin.buttons["skin.pale"])
	assert_eq(c.history.size(), steps + 1, "one click on a swatch is one change")
	# the keyboard and the pad still enter a swatch row on its chosen swatch and change nothing
	c.show_category("Hair")
	c.set_record(Appearance.default_record())
	await get_tree().process_frame
	await get_tree().process_frame
	var colors := c.row("hair.color") as OptionRows.SwatchRow
	var chosen := str(c.current_record().hair.color)
	await _key("ui_down")
	await get_tree().process_frame
	assert_eq(_focus(), colors.buttons[chosen], "down from the style lands on the chosen colour")
	assert_eq(str(c.current_record().hair.color), chosen, "and changes nothing")
