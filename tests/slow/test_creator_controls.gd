extends TestSuite
## The creator with a pad and a keyboard (P44; plan M10 §2.10, §3.4's test_creator_screen controls, moved to the
## slow tier because walking every category and row costs more than the default tier's cap): RB and LB through
## every category (wrapping), the D-pad through every row of every category (moving through rows changes
## nothing: entering a swatch row lands on its chosen swatch), a swatch applied on focus along its row, Y
## randomizes, the pad's View button undoes, X cycles the view, B asks when changed (Keep editing, then
## Discard) and closes at once when not, and the focus is never lost; with a keyboard, PageUp / PageDown, Q / E,
## + / -, V, R, Ctrl+Z and Ctrl+Enter (Begin).

var layer: CanvasLayer
var stack: ScreenStack
var results: Array = []


func before_each() -> void:
	InputBindings.reset_device()
	layer = CanvasLayer.new()
	layer.layer = 10
	add_child(layer)
	stack = ScreenStack.new()
	stack.name = "ScreenStack"
	layer.add_child(stack)
	results.clear()
	await get_tree().process_frame


func after_each() -> void:
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
	if c != null:
		c.closed.connect(func(r: Dictionary) -> void: results.append(r))
	return c


func _focus() -> Control:
	return get_viewport().gui_get_focus_owner()


func _pad(button: JoyButton) -> void:
	for pressed in [true, false]:
		var e := InputEventJoypadButton.new()
		e.button_index = button
		e.pressed = pressed
		e.device = 0
		Input.parse_input_event(e)
		Input.flush_buffered_events()
	await get_tree().process_frame


func _key(code: Key, ctrl := false) -> void:
	for pressed in [true, false]:
		var e := InputEventKey.new()
		e.keycode = code
		e.physical_keycode = code
		e.pressed = pressed
		e.ctrl_pressed = ctrl
		Input.parse_input_event(e)
		Input.flush_buffered_events()
	await get_tree().process_frame


func _in_creator(c: CreatorScreen, what: String) -> void:
	var f := _focus()
	assert_true(f != null and c.is_ancestor_of(f) and UiNav.focusable(f), "the focus is on the creator %s (%s)" % [what,
		f.name if f != null else "none"])


func test_a_pad_goes_through_every_category_and_row_and_backs_out() -> void:
	results.clear()
	var c := _open_creator()
	await get_tree().process_frame
	assert_eq(c.current_category(), "Presets", "it opens on Presets")
	_in_creator(c, "at first")
	assert_true(c.nav_hint(true).begins_with("LB/RB: category"), "the footer names the creator's pad controls: %s" % c.nav_hint(true))
	var seen: Array = [c.current_category()]
	for i in OptionRows.CATEGORIES.size():
		await _pad(JOY_BUTTON_RIGHT_SHOULDER)
		seen.append(c.current_category())
		_in_creator(c, "after RB to %s" % c.current_category())
	assert_eq(seen, OptionRows.CATEGORIES + ["Presets"], "RB visits every category and wraps")
	await _pad(JOY_BUTTON_LEFT_SHOULDER)
	assert_eq(c.current_category(), "Clothing", "LB goes back, wrapping")
	# The D-pad through every row of every category: each row's control takes the focus in turn.
	for cat: String in OptionRows.CATEGORIES:
		c.show_category(cat)
		await get_tree().process_frame
		var before := c.current_record()
		var rows := c.rows()
		for i in rows.size():
			var r: OptionRows.Row = rows[i]
			var f := _focus()
			assert_true(f != null and r.is_ancestor_of(f), "%s: the D-pad reaches the %s row" % [cat, r.key])
			await _pad(JOY_BUTTON_DPAD_DOWN)
			await get_tree().process_frame
		assert_true([c.randomize_button, c.randomize_all_button, c.undo_button, c.reset_button, c.presets_button,
			c.back_button, c.begin_button].has(_focus()), "%s: down from the last row reaches the actions" % cat)
		assert_true(OptionRows.same(c.current_record(), before), "%s: moving through the rows changes nothing" % cat)
	# A swatch applies on focus: right along the hair colours.
	c.show_category("Hair")
	await get_tree().process_frame
	await _pad(JOY_BUTTON_DPAD_DOWN)
	await get_tree().process_frame
	var colors := c.row("hair.color") as OptionRows.SwatchRow
	assert_eq(_focus(), colors.buttons["haircolor.chestnut"], "entering the colours lands on the chosen swatch")
	await _pad(JOY_BUTTON_DPAD_RIGHT)
	assert_eq(_focus(), colors.buttons["haircolor.auburn"], "right: the next swatch")
	assert_eq(str(c.current_record().hair.color), "haircolor.auburn", "applied on focus")
	assert_eq(colors.name_label.text, "Auburn", "and named")
	await _pad(JOY_BUTTON_Y)
	_in_creator(c, "after Y (Randomize)")
	await _pad(JOY_BUTTON_BACK)
	_in_creator(c, "after View (Undo)")
	assert_eq(str(c.current_record().hair.color), "haircolor.auburn", "View undid the randomize")
	await _pad(JOY_BUTTON_X)
	assert_eq(c.preview.view, "full", "X cycles the view: Full")
	await _pad(JOY_BUTTON_X)
	assert_eq(c.preview.view, "face", "then Face")
	await _pad(JOY_BUTTON_B)
	assert_true(c.question_open(), "B with a change asks")
	assert_eq(_focus(), c.keep_editing_button, "on Keep editing")
	await _pad(JOY_BUTTON_B)
	assert_false(c.question_open(), "B on the question is Keep editing")
	_in_creator(c, "after Keep editing")
	await _pad(JOY_BUTTON_B)
	await _pad(JOY_BUTTON_DPAD_RIGHT)
	assert_eq(_focus(), c.discard_button, "right: Discard")
	await _pad(JOY_BUTTON_A)
	assert_false(is_instance_valid(c) and stack.has_screen(c), "A on Discard leaves")
	assert_eq(results, [{"cancelled": true}], "with no look")
	results.clear()
	c = _open_creator()
	await get_tree().process_frame
	await _pad(JOY_BUTTON_B)
	assert_false(is_instance_valid(c) and stack.has_screen(c), "B with no change closes at once")


func test_the_keyboard_keys() -> void:
	results.clear()
	var c := _open_creator()
	await get_tree().process_frame
	assert_true(c.nav_hint(false).contains("Ctrl+Enter: begin"), "the footer names the keys: %s" % c.nav_hint(false))
	await _key(KEY_PAGEDOWN)
	assert_eq(c.current_category(), "Skin", "PageDown: the next category")
	await _key(KEY_PAGEUP)
	await _key(KEY_PAGEUP)
	assert_eq(c.current_category(), "Clothing", "PageUp twice: back past Presets, wrapping")
	var turn := c.preview.turn_deg
	await _key(KEY_Q)
	assert_near(c.preview.turn_deg, turn + CreatorScreen.TURN_STEP_DEG, 1e-3, "Q turns the giant")
	await _key(KEY_E)
	await _key(KEY_E)
	assert_near(c.preview.turn_deg, turn - CreatorScreen.TURN_STEP_DEG, 1e-3, "E turns him back")
	var zoom := c.preview.zoom_factor
	await _key(KEY_EQUAL)
	assert_true(c.preview.zoom_factor < zoom, "+ zooms in (%.2f)" % c.preview.zoom_factor)
	await _key(KEY_MINUS)
	assert_near(c.preview.zoom_factor, zoom, 1e-4, "- zooms out")
	await _key(KEY_V)
	assert_eq(c.preview.view, "full", "V cycles the view")
	c.show_category("Skin")
	c.pick("skin", "skin.deep")
	await _key(KEY_Z, true)
	assert_eq(str(c.current_record().skin), "skin.ruddy", "Ctrl+Z undoes")
	await _key(KEY_R)
	assert_true(c.history.size() == 1, "R randomizes the open category (one change)")
	await _key(KEY_ENTER, true)
	assert_false(is_instance_valid(c) and stack.has_screen(c), "Ctrl+Enter is Begin")
	assert_eq(results.size(), 1, "one result")
	if results.size() == 1:
		assert_true(bool((results[0] as Dictionary).get("begin", false)), "Begin")
		assert_true(typeof((results[0] as Dictionary).get("appearance")) == TYPE_DICTIONARY, "with the record")


## M10 gate, LA-4: the creator consumes its own keys and buttons in _input, before the root scene's _input
## (scripts/main.gd), the only other place that notes the device, can see them: the footer kept the other
## device's line until an unconsumed input arrived. The creator now notes the device of what it consumes.
func test_the_footer_follows_the_device_of_the_creators_own_buttons_and_keys() -> void:
	var c := _open_creator()
	await get_tree().process_frame
	await get_tree().process_frame
	assert_false(InputBindings.last_device_is_pad(), "the keyboard and mouse at first")
	assert_true(stack.hint_text().begins_with("PgUp/PgDn: category"), "the footer shows the keys: %s" % stack.hint_text())
	for button: JoyButton in [JOY_BUTTON_RIGHT_SHOULDER, JOY_BUTTON_LEFT_SHOULDER, JOY_BUTTON_X, JOY_BUTTON_Y, JOY_BUTTON_BACK]:
		InputBindings.reset_device()
		await _pad(button)
		await get_tree().process_frame
		assert_true(InputBindings.last_device_is_pad(), "pad button %d, one of the creator's own, is noted as the pad" % button)
		assert_true(stack.hint_text().begins_with("LB/RB: category"), "and the footer shows the pad's line: %s" % stack.hint_text())
	for key: Key in [KEY_PAGEDOWN, KEY_PAGEUP, KEY_Q, KEY_E, KEY_EQUAL, KEY_MINUS, KEY_V, KEY_R]:
		await _pad(JOY_BUTTON_RIGHT_SHOULDER)
		assert_true(InputBindings.last_device_is_pad(), "(the pad again)")
		await _key(key)
		await get_tree().process_frame
		assert_false(InputBindings.last_device_is_pad(), "key %s, one of the creator's own, is noted as the keyboard" % OS.get_keycode_string(key))
		assert_true(stack.hint_text().begins_with("PgUp/PgDn: category"), "and the footer shows the keys: %s" % stack.hint_text())
	await _pad(JOY_BUTTON_RIGHT_SHOULDER)
	await _key(KEY_Z, true)
	assert_false(InputBindings.last_device_is_pad(), "Ctrl+Z too")
