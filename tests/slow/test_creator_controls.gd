extends TestSuite
## The creator with a pad and a keyboard (P44; plan M10 §2.10, §3.4's test_creator_screen controls, moved to the
## slow tier because walking every category and row costs more than the default tier's cap): RB and LB through
## every category (wrapping), the D-pad through every row of every category (moving through rows changes
## nothing: entering a swatch row lands on its chosen swatch), a swatch applied on focus along its row, Y
## randomizes, the pad's View button undoes, X cycles the view, B asks when changed (Keep editing, then
## Discard) and closes at once when not, and the focus is never lost; with a keyboard, PageUp / PageDown, Q / E,
## + / -, V, R, Ctrl+Z and Ctrl+Enter (Begin).
##
## P55 (plan M11 §3.8): with the test catalogue at the target's size (CreatorCatalogue), every option of every grid
## row reached and put on with the pad (A on the row, LT / RT for its page, the D-pad to its cell, A) and with the
## keyboard (Enter, PageUp / PageDown, the arrows, Enter), every swatch of every swatch row along its row; the focus
## never lost through 200 scripted pad moves over the grids, the rows and the question; Randomize by slot (never an
## armour over a bare chest unless the outfit it started from wore one so); Undo back through 64 changes of grids,
## sliders and swatches.

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
	assert_eq(c.current_category(), OptionRows.CATEGORIES[-1], "LB goes back, wrapping")
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
	assert_eq(c.current_category(), "Body", "PageDown: the next category (P55: Body holds the skin)")
	await _key(KEY_PAGEUP)
	await _key(KEY_PAGEUP)
	assert_eq(c.current_category(), OptionRows.CATEGORIES[-1], "PageUp twice: back past Presets, wrapping")
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


# --------------------------------------------------------------------------- P55: every option with the pad and the keys

func _trigger(axis: JoyAxis) -> void:
	for v: float in [1.0, 0.0]:
		var e := InputEventJoypadMotion.new()
		e.axis = axis
		e.axis_value = v
		e.device = 0
		Input.parse_input_event(e)
		Input.flush_buffered_events()


## Sends the pad's (or the keyboard's) presses that take the focus from the grid's landing cell to uid=0(root) gid=0(root) groups=0(root)'s cell: the
## page presses the shorter way round, then the D-pad (right within the line, down across the lines). No frame.
func _go_to(c: CreatorScreen, id: String, pad: bool) -> void:
	var g := c.grid
	var pages := g.pages()
	var d := (g.page_of(id) - g.page + pages) % pages
	for i in (d if d <= pages - d else pages - d):
		if pad:
			_trigger(JOY_AXIS_TRIGGER_RIGHT if d <= pages - d else JOY_AXIS_TRIGGER_LEFT)
		else:
			_send_key(KEY_PAGEDOWN if d <= pages - d else KEY_PAGEUP)
	var at := g.cells.find(_focus())
	var want := g.index_on_page(id)
	var lines := want / OptionGrid.COLS - at / OptionGrid.COLS   # within the page's lines: no wrap past the pager
	for i in absi(lines):
		if pad:
			_send_pad(JOY_BUTTON_DPAD_DOWN if lines > 0 else JOY_BUTTON_DPAD_UP)
		else:
			_send_key(KEY_DOWN if lines > 0 else KEY_UP)
	for i in (want % OptionGrid.COLS - g.cells.find(_focus()) % OptionGrid.COLS + OptionGrid.COLS) % OptionGrid.COLS:
		if pad:
			_send_pad(JOY_BUTTON_DPAD_RIGHT)
		else:
			_send_key(KEY_RIGHT)


func _send_pad(button: JoyButton) -> void:
	for pressed in [true, false]:
		var e := InputEventJoypadButton.new()
		e.button_index = button
		e.pressed = pressed
		e.device = 0
		Input.parse_input_event(e)
		Input.flush_buffered_events()


func _send_key(code: Key) -> void:
	for pressed in [true, false]:
		var e := InputEventKey.new()
		e.keycode = code
		e.physical_keycode = code
		e.pressed = pressed
		Input.parse_input_event(e)
		Input.flush_buffered_events()


func _every_grid_option(pad: bool) -> PackedStringArray:
	var missed := PackedStringArray()
	var c := _open_creator()
	await get_tree().process_frame
	var n := 0
	for cat: String in OptionRows.CATEGORIES:
		c.show_category(cat)
		await get_tree().process_frame
		var keys: Array = []
		for r: OptionRows.Row in c.rows():
			if r is OptionRows.GridRow:
				keys.append(r.key)
		for key: String in keys:
			var gr := c.row(key) as OptionRows.GridRow
			if gr == null:
				missed.append("%s %s: no row" % [cat, key])
				continue
			for ch: Dictionary in gr.choices:
				if bool(ch.locked):
					continue
				gr.button.grab_focus()
				if pad:
					_send_pad(JOY_BUTTON_A)
				else:
					_send_key(KEY_ENTER)
				if not c.grid_open():
					missed.append("%s: the grid did not open" % gr.key)
					break
				_go_to(c, str(ch.id), pad)
				var on := _focus()
				if pad:
					_send_pad(JOY_BUTTON_A)
				else:
					_send_key(KEY_ENTER)
				n += 1
				var got := str(OptionRows.value_of(c.current_record(), gr.key))
				var want := str(ch.id)
				if gr.key == "outfit.set" and want != "":
					got = str(c.current_record().outfit.set)
				if got != want or c.grid_open():
					missed.append("%s %s (got %s, focus %s)" % [gr.key, want, got, on.name if on != null else "none"])
			await get_tree().process_frame
	assert_true(n >= 140, "%s: every grid option tried (%d)" % ["the pad" if pad else "the keyboard", n])
	c.close({"cancelled": true})
	return missed


func test_every_option_with_the_pad_and_with_the_keyboard() -> void:
	CreatorCatalogue.install()
	var by_pad := await _every_grid_option(true)
	assert_eq(by_pad, PackedStringArray(), "the pad reaches and puts on every grid option")
	var by_keys := await _every_grid_option(false)
	assert_eq(by_keys, PackedStringArray(), "the keyboard too")
	# every swatch along its row (moving the focus applies), every slider's step
	var c := _open_creator()
	await get_tree().process_frame
	var missed := PackedStringArray()
	for cat: String in OptionRows.CATEGORIES:
		c.show_category(cat)
		await get_tree().process_frame
		for r: OptionRows.Row in c.rows():
			if r is OptionRows.SwatchRow:
				var sw := r as OptionRows.SwatchRow
				(sw.focus_controls()[0] as Control).grab_focus()
				await get_tree().process_frame
				for i in sw.choices.size():
					var ch: Dictionary = sw.choices[(sw.focus_controls().find(_focus()) + 0) % sw.choices.size()]
					if not bool(ch.locked) and str(OptionRows.value_of(c.current_record(), sw.key)) != str(ch.id):
						missed.append("%s %s" % [sw.key, ch.id])
					_send_pad(JOY_BUTTON_DPAD_RIGHT)
			elif r is OptionRows.SliderRow:
				var sl := r as OptionRows.SliderRow
				sl.slider.grab_focus()
				var v := float(OptionRows.value_of(c.current_record(), sl.key))
				_send_pad(JOY_BUTTON_DPAD_RIGHT)
				if float(OptionRows.value_of(c.current_record(), sl.key)) <= v and v < sl.slider.max_value:
					missed.append(sl.key)
	assert_eq(missed, PackedStringArray(), "every swatch along its row and every slider's step")


func test_the_focus_is_never_lost_through_200_scripted_moves() -> void:
	CreatorCatalogue.install()
	var c := _open_creator()
	await get_tree().process_frame
	c.pick("skin", "skin.tan")   # a change: B asks instead of closing
	var rng := RandomNumberGenerator.new()
	rng.seed = 200
	var moves := [JOY_BUTTON_DPAD_UP, JOY_BUTTON_DPAD_DOWN, JOY_BUTTON_DPAD_LEFT, JOY_BUTTON_DPAD_RIGHT,
		JOY_BUTTON_DPAD_DOWN, JOY_BUTTON_DPAD_RIGHT, JOY_BUTTON_A, JOY_BUTTON_A, JOY_BUTTON_B, JOY_BUTTON_LEFT_SHOULDER,
		JOY_BUTTON_RIGHT_SHOULDER, JOY_BUTTON_X, JOY_BUTTON_Y, JOY_BUTTON_BACK, -1, -2]
	var lost := PackedStringArray()
	var opened := 0
	for i in 200:
		var m: int = moves[rng.randi_range(0, moves.size() - 1)]
		if i % 10 == 0 and not c.grid_open() and not c.question_open():
			# every tenth move starts from a grid row of a category with grids (so the walk goes through them)
			c.show_category(["Clothing", "Hair", "Tattoos", "Accessories", "War paint"][(i / 10) % 5])
			for r: OptionRows.Row in c.rows():
				if r is OptionRows.GridRow and rng.randf() < 0.5:
					(r as OptionRows.GridRow).button.grab_focus()
					break
			m = JOY_BUTTON_A
		var f := _focus()
		if m == JOY_BUTTON_A and f in [c.begin_button, c.back_button, c.discard_button]:
			m = JOY_BUTTON_DPAD_LEFT   # A there leaves the screen: not a move inside it
		if m == -1:
			_trigger(JOY_AXIS_TRIGGER_RIGHT)
		elif m == -2:
			_trigger(JOY_AXIS_TRIGGER_LEFT)
		else:
			_send_pad(m as JoyButton)
		await get_tree().process_frame
		if c.grid_open():
			opened += 1
		f = _focus()
		if f == null or not c.is_ancestor_of(f) or not UiNav.focusable(f):
			lost.append("move %d (%d): %s" % [i, m, f.name if f != null else "none"])
	assert_true(is_instance_valid(c) and stack.has_screen(c), "the creator is still open")
	assert_eq(lost, PackedStringArray(), "the focus is never lost")
	assert_true(opened > 25, "the moves went through the grids too (%d moves with one open)" % opened)


func test_randomize_dresses_by_slot_and_never_leaves_armour_on_a_bare_chest() -> void:
	CreatorCatalogue.install()
	var outfits: Array = []
	for o: Dictionary in CreatorCatalogue.document().sets.outfit:
		var slots: Dictionary = o.slots
		if not (slots.has("armour") and not slots.has("chest")):
			outfits.append(o)
	TestFixtures.record_override(Appearance.SET_PREFIX + "outfit", {"options": outfits})
	var rng := RandomNumberGenerator.new()
	rng.seed = 55
	var base := Appearance.default_record()
	var bare := 0
	var custom := 0
	var seen_slots := {}
	for i in 120:
		var r := OptionRows.random_clothing(rng, base, "")
		for slot: String in Appearance.SLOTS:
			var item := str(r.outfit.slots[slot].item)
			if item != "":
				assert_eq(str(Appearance.option(item).get("slot", "")), slot, "%s fits its slot" % item)
				seen_slots[item] = true
		if str(r.outfit.slots.armour.item) != "" and str(r.outfit.slots.chest.item) == "":
			bare += 1
		if str(r.outfit.set) == "":
			custom += 1
		if i % 20 == 0:
			assert_true(Appearance.is_valid(r), "a valid record")
	assert_eq(bare, 0, "never an armour over a bare chest from outfits that wear none so")
	assert_true(custom > 30, "dressed by slot: most draws are no outfit's (%d of 120)" % custom)
	assert_true(seen_slots.size() >= 25, "and reach most pieces (%d)" % seen_slots.size())
	# an outfit that wears its armour on a bare chest may be drawn so
	TestFixtures.record_override(Appearance.SET_PREFIX + "outfit", {"options": [{"key": "bare", "name": "Bare",
		"slots": {"armour": "garment.leather_cuirass", "waist": "garment.belt", "legs": "garment.braies"}}]})
	var kept := 0
	for i in 20:
		var r := OptionRows.random_clothing(rng, base, "")
		if str(r.outfit.slots.armour.item) != "" and str(r.outfit.slots.chest.item) == "":
			kept += 1
	assert_true(kept > 0, "the outfit it started from did, so it may (%d of 20)" % kept)
	# Randomize of a category changes only its part
	var c := _open_creator()
	await get_tree().process_frame
	var before := c.current_record()
	c.show_category("Accessories")
	c.randomize_category()
	assert_true(OptionRows.same(c.current_record().outfit.slots, before.outfit.slots), "Accessories leaves the slots")
	c.show_category("Body")
	var after_acc := c.current_record()
	assert_true(c.randomize_category(), "Body randomizes")
	assert_true(OptionRows.same(c.current_record().outfit, after_acc.outfit) and OptionRows.same(c.current_record().hair,
		after_acc.hair), "the skin and the build only")
	c.show_category("Colours")
	var after_body := c.current_record()
	assert_true(c.randomize_category(), "Colours randomizes")
	var r2 := c.current_record()
	for slot: String in Appearance.SLOTS:
		assert_eq(str(r2.outfit.slots[slot].item), str(after_body.outfit.slots[slot].item), "%s keeps its piece" % slot)


# --------------------------------------------------------------------------- P55: Undo over every new row

## Plan M11 §3.8: Undo through 64 changes, grid picks and sliders among them - each change one step, each step back
## the record as it was before it.
func test_undo_steps_back_through_64_changes_of_grids_sliders_and_swatches() -> void:
	var c := _open_creator()
	await get_tree().process_frame
	var before: Array = []
	var grid_keys := ["outfit.slots.chest.item", "outfit.slots.feet.item", "hair.style", "tattoos.arms", "paint.face"]
	var sliders := ["build.brawn", "build.girth", "hair.grey", "beard.grey"]
	var swatches := [["outfit.dyes.cloth", "dye.madder"], ["outfit.dyes.metal", "metal.bronze"], ["skin", "skin.tan"]]
	var i := 0
	while before.size() < CreatorScreen.HISTORY_MAX:
		var snapshot := c.current_record()
		var changed := false
		match i % 3:
			0:
				var key: String = grid_keys[(i / 3) % grid_keys.size()]
				c.show_category(OptionRows.category_of_key(key))
				var r := c.row(key) as OptionRows.GridRow
				c.open_grid(r)
				var g := c.grid
				var at := g.cells.find(get_viewport().gui_get_focus_owner())
				var next := (at + 1) % mini(g.visible_ids().size() + (1 if str(r.choices[0].id) == "" else 0), OptionGrid.PER_PAGE)
				(g.cells[next] as Button).grab_focus()   # one move: one change
				changed = not OptionRows.same(c.current_record(), snapshot)
				c.close_grid()
			1:
				var key: String = sliders[(i / 3) % sliders.size()]
				var v := float(OptionRows.value_of(snapshot, key))
				changed = c.pick(key, snappedf(v + 0.1 if v < 0.45 else v - 0.3, 0.01))
			2:
				var sw: Array = swatches[(i / 3) % swatches.size()]
				var v2 := str(OptionRows.value_of(snapshot, sw[0]))
				changed = c.pick(sw[0], sw[1] if v2 != sw[1] else str(OptionRows.choices({"key": sw[0], "set":
					Appearance.category_of(sw[1])}, "")[0].id))
		if changed:
			before.append(snapshot)
		i += 1
		if i > 400:
			break
	assert_eq(before.size(), CreatorScreen.HISTORY_MAX, "64 changes made (%d tries)" % i)
	assert_eq(c.history.size(), CreatorScreen.HISTORY_MAX, "64 in the history")
	var wrong := PackedStringArray()
	for k in range(before.size() - 1, -1, -1):
		c.undo()
		if not OptionRows.same(c.current_record(), before[k]):
			wrong.append("step %d" % k)
	assert_eq(wrong, PackedStringArray(), "every Undo gives back the look before its change")
	assert_false(c.undo(), "and then there is nothing more")
