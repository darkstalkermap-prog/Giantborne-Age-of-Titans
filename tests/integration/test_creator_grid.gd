extends TestSuite
## The creator II's rows and option grids (P55; plan M11 §2.7, §3.8): every row built from the sets' data - today's
## (P54's wardrobe), an empty set of the test's own (an empty grid) and the test catalogue at the target's size
## (tests/fixtures/appearance/creator_catalogue.json, about 190 options; CreatorCatalogue) - so P54's and P56's sets
## need no edit here; at most 4 pad moves from a category to any option, computed from each grid's geometry (the
## row, A to open, the page presses with the wrap, the cell); the material and name filters with the pad and the
## keys; a grid puts on by moving and closes with A; the build sliders' step, snap and rear view; a design on the
## giant's left framed from his left. Elsewhere (the default tier's share is small): the thumbnails' scheduling and
## their rendered pictures (tests/slow/test_creator_thumbnails.gd); every option with the pad, the keys and the
## mouse, 200 scripted moves and Randomize by slot (tests/slow/test_creator_controls.gd, test_creator_mouse.gd); Undo
## over grid picks and sliders (test_creator_screen.gd); the grid's layout at five sizes (test_creator_layout.gd).

## Plan M11 §2.7: any option at most this many pad moves from its category.
const MAX_PAD_MOVES := 4

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
	if is_instance_valid(stack):
		stack.close_all()
	if is_instance_valid(layer):
		layer.queue_free()
	get_tree().paused = false
	InputRouter.set_context(InputRouter.Context.GAMEPLAY)
	InputBindings.reset_device()
	await get_tree().process_frame


func _open() -> CreatorScreen:
	var c := stack.open("creator", {"context": "new_game", "start": {"mode": "valley", "options": {"new_game": true}}}) \
		as CreatorScreen
	assert_true(c != null, "the creator opens")
	return c


func _grid_rows(c: CreatorScreen) -> Array:
	var out: Array = []
	for r: OptionRows.Row in c.rows():
		if r is OptionRows.GridRow:
			out.append(r)
	return out


func _key(code: Key, unicode := 0) -> void:
	for pressed in [true, false]:
		var e := InputEventKey.new()
		e.keycode = code
		e.physical_keycode = code
		e.unicode = unicode
		e.pressed = pressed
		Input.parse_input_event(e)
		Input.flush_buffered_events()


func _pad(button: JoyButton) -> void:
	for pressed in [true, false]:
		var e := InputEventJoypadButton.new()
		e.button_index = button
		e.pressed = pressed
		e.device = 0
		Input.parse_input_event(e)
		Input.flush_buffered_events()


# --------------------------------------------------------------------------- built from data

func test_rows_follow_the_sets_and_an_empty_set_shows_an_empty_grid() -> void:
	assert_eq(OptionRows.CATEGORIES, ["Presets", "Body", "Face", "Hair", "Beard", "Tattoos", "War paint", "Scars",
		"Clothing", "Accessories", "Colours"], "the eleven categories of plan M11 §2.7")
	var c := _open()
	c.show_category("Clothing")
	var keys: Array = []
	for r: OptionRows.Row in c.rows():
		keys.append(r.key)
	assert_eq(keys.size(), 1 + Appearance.SLOTS.size(), "the outfits and the ten slot rows")
	for slot: String in Appearance.SLOTS:
		var r := c.row("outfit.slots.%s.item" % slot) as OptionRows.GridRow
		var want := 0
		for id: String in Appearance.option_ids("garment"):
			if str(Appearance.option(id).get("slot", "")) == slot:
				want += 1
		assert_true(r != null and r.option_count() == want and str(r.choices[0].name) == OptionRows.NONE,
			"%s: None and the set's %d garments of the slot" % [slot, want])
	# the accessory rows follow the real set (P54's: three a slot), each with "None" first
	c.show_category("Accessories")
	assert_eq(c.rows().size(), Appearance.ACCESSORY_SLOTS.size(), "three accessory rows")
	for slot: String in Appearance.ACCESSORY_SLOTS:
		var r := c.row("outfit.accessories.%s" % slot) as OptionRows.GridRow
		var want := 0
		for id: String in Appearance.option_ids("accessory"):
			if str(Appearance.option(id).get("slot", "")) == slot:
				want += 1
		assert_true(r != null and r.option_count() == want and str(r.choices[0].name) == OptionRows.NONE,
			"%s: None and the set's %d accessories of the slot" % [slot, want])
	stack.close_all()
	# an empty set (the test's own, whatever the game's data holds): three rows whose grids hold "None" alone
	CreatorCatalogue.install_empty("accessory")
	c = _open()
	c.show_category("Accessories")
	assert_eq(c.rows().size(), Appearance.ACCESSORY_SLOTS.size(), "an empty set: still three accessory rows")
	var neck := c.row("outfit.accessories.neck") as OptionRows.GridRow
	assert_eq(neck.option_count(), 0, "an empty set: no accessory")
	assert_eq(neck.count_label.text, "none yet", "the row says so")
	c.open_grid(neck)
	assert_true(c.grid_open(), "its grid opens")
	assert_eq(c.grid.visible_ids(), [], "with no option on its page")
	assert_true((c.grid.cells[0] as Button).visible and not (c.grid.cells[1] as Button).visible, "only None")
	assert_true(c.grid.empty_label.visible and c.grid.empty_label.text == OptionGrid.NOTHING, "and the note: %s" %
		c.grid.empty_label.text)
	c.close_grid()
	stack.close_all()
	# the catalogue at the target's size: the same screen, no edit
	var total := CreatorCatalogue.install()
	assert_true(total >= 180, "the test catalogue holds about 190 options (%d)" % total)
	c = _open()
	c.show_category("Accessories")
	neck = c.row("outfit.accessories.neck") as OptionRows.GridRow
	assert_eq(neck.option_count(), 3, "the catalogue's three neck pieces")
	c.show_category("Face")
	assert_eq(c.rows().size(), 1 + Appearance.option_ids("face").size(), "the eye colour and a slider per face key")
	c.show_category("Hair")
	assert_true(c.row("hair.beads") != null, "a beads row once the bead set exists")
	c.show_category("Tattoos")
	assert_eq((c.row("tattoos.legs") as OptionRows.GridRow).option_count(), 4, "the legs' four tattoos")
	var offered := 0
	for cat: String in OptionRows.CATEGORIES:
		for spec: Dictionary in OptionRows.row_specs(cat, c.current_record()):
			match str(spec.kind):
				"grid", "swatch", "cycler":
					for ch: Dictionary in OptionRows.choices(spec, ""):
						if str(ch.id) != "" and str(ch.id) != Appearance.BEAD_NONE and str(ch.id).contains("."):
							offered += 1
				"slider", "toggle", "preset":
					offered += 1
	assert_true(offered >= 180, "the creator offers them all (%d choices in its rows)" % offered)


# --------------------------------------------------------------------------- pad moves

## For every option of every grid row of every category: the pad moves from the category (its rows shown) to
## the option, from the grid's geometry (a real OptionGrid holding the row's choices, as the screen opens it) - the
## row (one move), A (one), the page presses (the shorter way round: pages wrap), the cell (none when the focus
## lands on it, else one). Also the literal presses (the D-pad to the row along the focus rows, which wrap; A; the
## pages; the D-pad from the landing cell, the wrap within a line), reported.
func _pad_moves(record: Dictionary) -> Dictionary:
	var worst := {"moves": 0, "presses": 0, "what": "", "presses_what": "", "most_pages": 1}
	var total_presses := 0
	var n := 0
	var g := OptionGrid.new()
	for cat: String in OptionRows.CATEGORIES:
		var rows: Array = OptionRows.build_rows(cat, "", record)
		for ri in rows.size():
			var r: OptionRows.Row = rows[ri]
			if not r is OptionRows.GridRow:
				continue
			g.open(r as OptionRows.GridRow, str(OptionRows.value_of(record, r.key)))
			var pages := g.pages()
			worst.most_pages = maxi(int(worst.most_pages), pages)
			var land := g.index_on_page(g.selected) if g.page_of(g.selected) >= 0 else 0
			var land_page := maxi(g.page_of(g.selected), 0)
			var to_row := mini(ri + 1, rows.size() + 2 - (ri + 1))   # from the tabs, the focus rows wrapping
			for ch: Dictionary in (r as OptionRows.GridRow).choices:
				var id := str(ch.id)
				var p := g.page_of(id)
				var d := absi(p - land_page)
				var page_presses := mini(d, pages - d)
				var cell := g.index_on_page(id)
				var moves := 1 + 1 + page_presses + (0 if page_presses == 0 and cell == land else 1)
				var dc := absi(cell % OptionGrid.COLS - land % OptionGrid.COLS)
				var dr := absi(cell / OptionGrid.COLS - land / OptionGrid.COLS)
				var presses := to_row + 1 + page_presses + mini(dc, OptionGrid.COLS - dc) + dr
				total_presses += presses
				n += 1
				if moves > int(worst.moves):
					worst.moves = moves
					worst.what = "%s %s (page %d of %d, cell %d)" % [cat, id, p + 1, pages, cell]
				if presses > int(worst.presses):
					worst.presses = presses
					worst.presses_what = "%s %s" % [cat, id]
			g.close()
		for r: OptionRows.Row in rows:
			r.free()
	g.free()
	worst["options"] = n
	worst["mean_presses"] = float(total_presses) / maxf(1.0, float(n))
	return worst


func test_any_option_is_at_most_four_pad_moves_from_its_category() -> void:
	var today := _pad_moves(Appearance.default_record())
	assert_true(int(today.moves) <= MAX_PAD_MOVES, "today's data: at most %d moves (%d: %s)" % [MAX_PAD_MOVES,
		int(today.moves), str(today.what)])
	CreatorCatalogue.install()
	var full := _pad_moves(Appearance.default_record())
	assert_true(int(full.options) >= 140, "every grid option of the catalogue counted (%d)" % int(full.options))
	assert_true(int(full.moves) <= MAX_PAD_MOVES, "the catalogue: at most %d moves (%d: %s)" % [MAX_PAD_MOVES,
		int(full.moves), str(full.what)])
	# a set three times the target's still keeps it (three pages: the wrap makes every page one press away)
	var hair: Array = []
	for i in 35:
		hair.append({"key": "extra_%d" % i, "name": "Extra style %d" % i, "mesh": "", "scalp_tint": 0.0})
	TestFixtures.record_override(Appearance.SET_PREFIX + "hair", {"options": hair})
	var big := _pad_moves(Appearance.default_record())
	assert_eq(int(big.most_pages), 3, "35 styles: three pages of twelve")
	assert_true(int(big.moves) <= MAX_PAD_MOVES, "35 styles: still at most %d moves (%d: %s)" % [MAX_PAD_MOVES,
		int(big.moves), str(big.what)])
	print("    test_creator_grid: pad moves - today %d (of %d options), catalogue %d (of %d); literal presses at most %d (%s), mean %.1f" %
		[int(today.moves), int(today.options), int(full.moves), int(full.options), int(full.presses), str(full.presses_what),
		float(full.mean_presses)])


# --------------------------------------------------------------------------- the filters and the keys

func test_the_material_and_name_filters_with_the_pad_and_the_keys() -> void:
	CreatorCatalogue.install()
	var c := _open()
	c.show_category("Clothing")
	var armour := c.row("outfit.slots.armour.item") as OptionRows.GridRow
	armour.button.grab_focus()
	_key(KEY_ENTER)
	assert_true(c.grid_open() and c.grid_row() == armour, "Enter on a slot row opens its grid")
	assert_true(c.is_ancestor_of(get_viewport().gui_get_focus_owner()), "the focus is in the grid")
	var g := c.grid
	assert_eq(g.materials(), ["leather", "metal"], "the armour's materials")
	assert_true((g.material_buttons.metal as Button).visible and not (g.material_buttons.fur as Button).visible,
		"only the materials it has are offered")
	_pad(JOY_BUTTON_X)
	assert_eq(g.material_filter, "leather", "X: the next material")
	_key(KEY_F, 102)
	assert_eq(g.material_filter, "metal", "F: the next")
	var names: Array = []
	for ch: Dictionary in g.shown:
		names.append(str(ch.name))
	assert_eq(names, ["None", "Mail hauberk", "Scale coat", "Bronze breastplate"], "metal only, None kept first")
	_key(KEY_F, 102)
	assert_eq(g.material_filter, "all", "and round to All")
	# the name filter: typing goes into the box
	_key(KEY_S, 115)
	_key(KEY_C, 99)
	assert_eq(g.query, "sc", "typing filters by name")
	names.clear()
	for ch: Dictionary in g.shown:
		names.append(str(ch.name))
	assert_eq(names, ["None", "Scale coat"], "a match anywhere in the name")
	_key(KEY_BACKSPACE)
	assert_eq(g.query, "s", "Backspace takes a letter off")
	g.set_query("zzz")
	assert_true(g.empty_label.visible and g.empty_label.text == OptionGrid.NO_MATCH, "no match says so")
	g.set_query("")
	_key(KEY_SLASH)
	assert_true(g.filter_box.has_focus(), "/ goes to the box")
	_key(KEY_R, 114)
	await get_tree().process_frame   # LineEdit tells its text change at the frame's end
	assert_eq(g.query, "r", "where every letter types, the creator's own keys too")
	_key(KEY_DOWN)
	assert_true(g.cells.has(get_viewport().gui_get_focus_owner()), "Down goes back to the cells")
	var before := c.current_record()
	assert_true(OptionRows.same(c.current_record(), before), "filtering changed nothing")
	c.cancel()
	assert_false(c.grid_open(), "Esc closes the grid")
	assert_eq(get_viewport().gui_get_focus_owner(), armour.button, "the focus back on its row")
	assert_true(stack.has_screen(c), "and the creator stays")


func test_a_grid_puts_on_by_moving_and_closes_with_a() -> void:
	var c := _open()
	c.show_category("Clothing")
	var chest := c.row("outfit.slots.chest.item") as OptionRows.GridRow
	c.open_grid(chest)
	var g := c.grid
	assert_eq(get_viewport().gui_get_focus_owner(), g.cells[0], "the focus lands on the chosen cell (None)")
	assert_eq(str(c.current_record().outfit.slots.chest.item), "", "landing changes nothing")
	var steps := c.history.size()
	(g.cells[1] as Button).grab_focus()   # as the D-pad's right does: a move from cell to cell
	assert_eq(str(c.current_record().outfit.slots.chest.item), "garment.tunic", "moving onto a cell puts it on")
	(g.cells[0] as Button).grab_focus()
	(g.cells[1] as Button).grab_focus()
	assert_eq(c.history.size(), steps + 1, "browsing a grid is one change")
	assert_eq(str(c.current_record().outfit.set), "", "the outfit is custom now")
	_key(KEY_ENTER)
	assert_false(c.grid_open(), "Enter (A) on a cell closes the grid")
	assert_eq(chest.button.text, "Tunic", "the row names the piece")
	c.show_category("Clothing")
	assert_eq((c.row("outfit.set") as OptionRows.GridRow).button.text, OptionRows.CUSTOM, "Outfit: custom")
	assert_true(c.undo(), "Undo")
	assert_eq(str(c.current_record().outfit.slots.chest.item), "", "takes the grid's change off in one step")
	# left and right on a grid row step through its choices as M10's cyclers did
	chest.button.grab_focus()
	_key(KEY_RIGHT)
	assert_eq(str(c.current_record().outfit.slots.chest.item), "garment.tunic", "Right steps to the next piece")
	# LB closes the grid and changes the category
	c.open_grid(chest)
	_pad(JOY_BUTTON_RIGHT_SHOULDER)
	assert_false(c.grid_open(), "RB closes the grid")
	assert_eq(c.current_category(), "Accessories", "and goes to the next category")


# --------------------------------------------------------------------------- sliders, framing

func test_the_build_sliders_step_snap_and_show_the_rear_view() -> void:
	var c := _open()
	c.show_category("Body")
	var brawn := c.row("build.brawn") as OptionRows.SliderRow
	assert_true(brawn != null and brawn.signed, "a signed Brawn slider")
	assert_near(brawn.slider.max_value, OptionRows.BUILD_LIMIT, 1e-6, "reaching %.1f" % OptionRows.BUILD_LIMIT)
	brawn.slider.grab_focus()
	assert_eq(c.preview.framing, GiantPreview.GAME_STAGE1, "the stage-1 rear Game view while it has the focus")
	_key(KEY_RIGHT)
	assert_near(float(c.current_record().build.brawn), 0.1, 1e-6, "Right: one step of 0.1")
	_key(KEY_RIGHT)
	_key(KEY_LEFT)
	assert_near(float(c.current_record().build.brawn), 0.1, 1e-6, "Left back")
	var steps := c.history.size()
	brawn.slider.value = 0.03
	assert_near(float(c.current_record().build.brawn), 0.0, 1e-6, "a drag near the middle snaps to 0")
	brawn.slider.value = 0.27
	assert_near(float(c.current_record().build.brawn), 0.27, 1e-6, "and keeps its hundredths elsewhere")
	assert_eq(c.history.size(), steps, "one slider's moves are one change")
	assert_true(brawn.value_label.text.begins_with("Brawny"), "named by its end: %s" % brawn.value_label.text)
	(c.row("skin") as OptionRows.SwatchRow).main_control().grab_focus()
	assert_eq(c.preview.framing, "full", "the whole giant again when the focus leaves it")
	# W32: a record's grey under SNAP_ZERO (Randomize draws 0.04) is shown, never picked back as a change of its own
	var was := c.current_record()
	var r := was.duplicate(true)
	r.hair["grey"] = 0.04
	c.set_record(r)
	c.show_category("Hair")
	assert_true(c.row("hair.grey") is OptionRows.SliderRow, "a hair Grey slider")
	assert_near(float(c.current_record().hair.grey), 0.04, 1e-6, "showing a grey of 0.04 leaves the record as it is")
	c.undo()
	assert_true(OptionRows.same(c.current_record(), was), "and one Undo takes that change back")


func test_a_design_on_the_left_is_framed_from_the_left() -> void:
	var c := _open()
	var index := c.preview.index()
	assert_eq(OptionRows.design_side("scar_brow", index), "left", "the brow scar is on his left (the index)")
	c.show_category("Scars")
	var brow := c.row("scar.brow") as OptionRows.ToggleRow
	brow.check.grab_focus()
	assert_eq(c.preview.framing, "face" + GiantPreview.LEFT_SUFFIX, "framed from his left")
	var cheek := c.row("scar.cheek") as OptionRows.ToggleRow
	if cheek != null:
		cheek.check.grab_focus()
		assert_eq(c.preview.framing, "face", "the cheek scar (his right) from his right")
	# the eyes look toward the camera (P51's look): from his right at the face framing, ahead from behind
	c.preview.frame("face")
	var look := c.preview.eye_target()
	assert_true(look.x > 0.0 and look.x <= GiantPreview.EYE_LOOK_MAX, "the face framing: the eyes turn to his right, toward the camera (%s)" % look)
	c.preview.frame("back")
	assert_eq(c.preview.eye_target(), Vector2.ZERO, "from behind: straight ahead")
	var left := GiantPreview.framing_entry("chest_left")
	var right := GiantPreview.framing_entry("chest")
	assert_near(float(left.yaw), -float(right.yaw), 1e-6, "a left framing is the right one mirrored")
