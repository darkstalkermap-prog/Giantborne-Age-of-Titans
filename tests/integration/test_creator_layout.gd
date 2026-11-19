extends TestSuite
## The creator's layout (P44; plan M10 §2.10): at 1280x720, 1366x768, 1600x900, 1920x1080 and 2560x1440 the title
## row, every category tab, the preview and its view buttons, the options panel and every action button lie
## inside the window and above the stack's footer hint, and none of them overlaps another; the discard question
## too. At 1280x720 the preview is about 720x544 and the options panel about 512x544 (the creator brief's
## mock-up). The stack sits in a control of each size (the headless window is not the player's).

const SIZES := [Vector2(1280, 720), Vector2(1366, 768), Vector2(1600, 900), Vector2(1920, 1080), Vector2(2560, 1440)]

var frame: Control
var stack: ScreenStack


func before_each() -> void:
	InputBindings.reset_device()
	var layer := CanvasLayer.new()
	layer.name = "LayoutLayer"
	add_child(layer)
	frame = Control.new()
	frame.size = SIZES[0]
	layer.add_child(frame)
	stack = ScreenStack.new()
	frame.add_child(stack)
	await get_tree().process_frame


func after_each() -> void:
	if is_instance_valid(stack):
		stack.close_all()
	if is_instance_valid(frame):
		frame.get_parent().queue_free()
	await get_tree().process_frame


func _rect(c: Control) -> Rect2:
	return Rect2(c.get_global_rect().position - frame.get_global_rect().position, c.size)


## The window above the footer hint (the stack's NavHint; its top edge).
func _room(view: Vector2) -> Rect2:
	var hint := stack.get_node("NavHint") as Control
	return Rect2(Vector2.ZERO, Vector2(view.x, view.y + hint.offset_top))


func test_every_panel_and_button_fits_at_five_sizes() -> void:
	CreatorCatalogue.install()   # P55: the outfits' grid full (twelve)
	var c := stack.open("creator", {"context": "new_game"}) as CreatorScreen
	assert_true(c != null, "the creator opens")
	if c == null:
		return
	c.show_category("Tattoos")   # the tallest category
	for view: Vector2 in SIZES:
		frame.size = view
		await get_tree().process_frame
		var size_text := "%dx%d" % [int(view.x), int(view.y)]
		var room := _room(view).grow(0.5)
		var parts := {"title": c.find_child("Head", true, false), "tabs": c.find_child("Tabs", true, false),
			"preview": c.preview.get_parent(), "options": c.find_child("Options", true, false),
			"actions": c.find_child("Actions", true, false), "views": c.find_child("Views", true, false)}
		var bad := PackedStringArray()
		for key: String in parts:
			var r := _rect(parts[key] as Control)
			if not room.encloses(r):
				bad.append("%s %s" % [key, r])
		var buttons: Array = c.tab_buttons.values() + [c.randomize_button, c.randomize_all_button, c.undo_button,
			c.reset_button, c.presets_button, c.back_button, c.begin_button] + c.view_buttons.values()
		for b: Button in buttons:
			if not room.encloses(_rect(b)):
				bad.append("%s %s" % [b.text, _rect(b)])
		assert_eq(bad, PackedStringArray(), "everything inside the window and above the footer at %s" % size_text)
		var regions := ["title", "tabs", "preview", "options", "actions"]
		var overlaps := PackedStringArray()
		for i in regions.size():
			for j in range(i + 1, regions.size()):
				if _rect(parts[regions[i]]).intersects(_rect(parts[regions[j]])):
					overlaps.append("%s / %s" % [regions[i], regions[j]])
		for i in buttons.size():
			for j in range(i + 1, buttons.size()):
				if _rect(buttons[i]).intersects(_rect(buttons[j])):
					overlaps.append("%s / %s" % [(buttons[i] as Button).text, (buttons[j] as Button).text])
		assert_eq(overlaps, PackedStringArray(), "nothing overlaps at %s" % size_text)
		var rows_box := c.find_child("Rows", true, false) as Control
		assert_true(_rect(rows_box).size.x <= _rect(parts.options).size.x, "the rows fit the options panel's width at %s" % size_text)
		if view == SIZES[0]:
			var pv := _rect(parts.preview)
			var op := _rect(parts.options)
			assert_true(absf(pv.size.x - 720.0) <= 12.0 and absf(pv.size.y - 544.0) <= 24.0,
				"the preview is about 720x544 at 1280x720 (%s)" % pv.size)
			assert_true(absf(op.size.x - 512.0) <= 12.0 and absf(op.size.y - 544.0) <= 24.0,
				"the options panel about 512x544 (%s)" % op.size)
		# the discard question
		if not c.is_changed():
			c.set_record(OptionRows.with_value(c.current_record(), "skin", "skin.tan"))
		c.cancel()
		await get_tree().process_frame
		var q := _rect(c.question_panel())
		assert_true(c.question_open() and room.encloses(q), "the discard question lies inside at %s (%s)" % [size_text, q])
		assert_true(room.encloses(_rect(c.keep_editing_button)) and room.encloses(_rect(c.discard_button)),
			"with both its buttons at %s" % size_text)
		assert_false(_rect(c.keep_editing_button).intersects(_rect(c.discard_button)), "apart at %s" % size_text)
		c.keep_editing()
		# P55: an option grid of the test catalogue's (filters, twelve cells, the name, the pager) inside the options
		# panel and the window
		c.show_category("Clothing")
		c.open_grid(c.row("outfit.set") as OptionRows.GridRow)
		await get_tree().process_frame
		var panel := _rect(parts.options).grow(0.5)
		var g := c.grid
		var grid_bad := PackedStringArray()
		for ctl: Control in [g.filter_box, g.done_button, g.name_label] + g.cells.filter(func(x: Button) -> bool: return x.visible):
			if not (panel.encloses(_rect(ctl)) and room.encloses(_rect(ctl))):
				grid_bad.append("%s %s" % [ctl.name, _rect(ctl)])
		assert_eq(grid_bad, PackedStringArray(), "the grid inside the options panel at %s" % size_text)
		assert_true(g.cell_px() >= OptionGrid.CELL_MIN_PX, "cells of %d px at %s" % [g.cell_px(), size_text])
		c.close_grid()
		c.show_category("Tattoos")
