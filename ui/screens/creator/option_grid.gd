class_name OptionGrid
extends VBoxContainer
## The creator II's option grid (P55; plan M11 §2.7, §3.8 item 2): the options of one grid row (a clothing or an
## accessory slot, the outfits, a hair or beard style, beads, a tattoo region, a war paint place) a page at a time,
## in the options panel in place of the rows while it is open.
##
##   * A page holds up to PER_PAGE options, COLS x ROWS cells (4 x 3 at 1280x720), "None" first where the row is
##     optional. A cell shows the option's thumbnail (ThumbnailCache) and its name until the thumbnail arrives; the
##     focused option's name (and its material, or why it is locked) reads under the grid; the chosen option has a
##     gold border.
##   * Pages: LT and RT, the mouse wheel over the grid, PageUp and PageDown, or the < and > buttons; they wrap.
##   * The material filter (All, Cloth, Leather, Fur, Metal: only the materials the row's options have) on X or F,
##     or a click on its buttons; the name filter: on the keyboard, typing (or "/") goes into the box above the
##     grid, which matches names anywhere in them; Backspace takes a letter off.
##   * Moving the focus from one cell to another with the pad or the keyboard puts that option on (as a swatch
##     does: moving previews and keeps; the focus entering the cells from elsewhere lands and changes nothing); a click puts it on and keeps the grid open; A or Enter puts it on and closes the grid;
##     Done, B or Esc close it. A page turn or a filter moves the focus without putting anything on.
## Nothing here touches the record: the grid emits `chosen` and CreatorScreen makes the change.

## An option was put on (`close`: A or Enter - the grid closes after it).
signal chosen(id: String, close: bool)
## The page shown changed (its option ids, for the thumbnails).
signal page_shown(ids: Array)
## Done (or A on a cell): CreatorScreen closes the grid.
signal close_requested
## The focus moved to a cell.
signal cell_focused(id: String)

const COLS := 4
const ROWS := 3
const PER_PAGE := COLS * ROWS
const CELL_PX := 104
const CELL_MIN_PX := 84
const CELL_MAX_PX := 150
const GAP := 6
const MATERIALS := ["all", "cloth", "leather", "fur", "metal"]
const MATERIAL_NAMES := {"all": "All", "cloth": "Cloth", "leather": "Leather", "fur": "Fur", "metal": "Metal"}
const FILTER_HINT := "Type to find"
const NOTHING := "Nothing to choose here yet."
const NO_MATCH := "No option matches."
const SELECTED_BORDER := Color(1.0, 0.86, 0.5)

## The row whose options are shown (null while closed), its choices, and those the filters keep.
var row: OptionRows.GridRow = null
var choices: Array = []
var shown: Array = []
var page := 0
var material_filter := "all"
var query := ""
## The option the record has now (the gold border).
var selected := ""
## option id -> its thumbnail (null: the name shows)
var thumbnails: Dictionary = {}
var cells: Array = []          ## Button x PER_PAGE
var cell_ids: Array = []       ## the option id of each cell on this page ("" for an unused cell)
var filter_box: LineEdit
var material_buttons: Dictionary = {}
var prev_button: Button
var next_button: Button
var done_button: Button
var page_label: Label
var name_label: Label
var empty_label: Label
var _filters: HBoxContainer
var _grid: GridContainer
var _quiet := false
var _mouse_press := false
var _cell_px := CELL_PX
var _cell_left_frame := -1   ## the frame a cell last lost the focus (a move between cells applies)


func _init() -> void:
	name = "OptionGrid"
	visible = false
	add_theme_constant_override("separation", GAP)
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mouse_filter = Control.MOUSE_FILTER_STOP
	_filters = HBoxContainer.new()
	_filters.name = "Filters"
	_filters.add_theme_constant_override("separation", 4)
	add_child(_filters)
	filter_box = LineEdit.new()
	filter_box.name = "Find"
	filter_box.placeholder_text = FILTER_HINT
	filter_box.custom_minimum_size = Vector2(150, 30)
	filter_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	filter_box.clear_button_enabled = true
	filter_box.add_theme_font_size_override("font_size", 14)
	filter_box.text_changed.connect(_on_query)
	filter_box.focus_mode = Control.FOCUS_ALL
	_filters.add_child(filter_box)
	for m: String in MATERIALS:
		var b := UiKit.button(str(MATERIAL_NAMES[m]), 13)
		b.name = "Material_" + m
		b.focus_mode = Control.FOCUS_ALL
		b.pressed.connect(set_material_filter.bind(m))
		_filters.add_child(b)
		material_buttons[m] = b
	_grid = GridContainer.new()
	_grid.name = "Cells"
	_grid.columns = COLS
	_grid.add_theme_constant_override("h_separation", GAP)
	_grid.add_theme_constant_override("v_separation", GAP)
	_grid.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN   # the cells keep their places when a filter hides some
	_grid.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(_grid)
	for i in PER_PAGE:
		var cell := _make_cell(i)
		_grid.add_child(cell)
		cells.append(cell)
		cell_ids.append("")
	empty_label = UiKit.label("", 14, UiKit.MUTED)
	empty_label.name = "Empty"
	empty_label.visible = false
	add_child(empty_label)
	name_label = UiKit.label("", 15)
	name_label.name = "OptionName"
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_label.custom_minimum_size = Vector2(0, 22)
	add_child(name_label)
	var pager := HBoxContainer.new()
	pager.name = "Pager"
	pager.add_theme_constant_override("separation", 8)
	add_child(pager)
	prev_button = UiKit.button("<", 15)
	prev_button.name = "PrevPage"
	prev_button.tooltip_text = "Previous page (LT, PageUp, the wheel)"
	prev_button.pressed.connect(step_page.bind(-1))
	pager.add_child(prev_button)
	page_label = UiKit.label("", 14, UiKit.MUTED)
	page_label.name = "Page"
	page_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	pager.add_child(page_label)
	next_button = UiKit.button(">", 15)
	next_button.name = "NextPage"
	next_button.tooltip_text = "Next page (RT, PageDown, the wheel)"
	next_button.pressed.connect(step_page.bind(1))
	pager.add_child(next_button)
	var gap := Control.new()
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pager.add_child(gap)
	done_button = UiKit.button("Done", 15)
	done_button.name = "Done"
	done_button.pressed.connect(func() -> void: close_requested.emit())
	pager.add_child(done_button)


func _make_cell(i: int) -> Button:
	var b := Button.new()
	b.name = "Cell%d" % i
	b.focus_mode = Control.FOCUS_ALL
	b.mouse_filter = Control.MOUSE_FILTER_PASS   # the wheel reaches the grid (pages)
	b.custom_minimum_size = Vector2(CELL_PX, CELL_PX)
	var tex := TextureRect.new()
	tex.name = "Thumb"
	tex.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	tex.offset_left = 4
	tex.offset_top = 4
	tex.offset_right = -4
	tex.offset_bottom = -4
	tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(tex)
	var caption := Label.new()
	caption.name = "Caption"
	caption.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	caption.offset_left = 5
	caption.offset_right = -5
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	caption.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	caption.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	caption.add_theme_font_size_override("font_size", 14)
	caption.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	caption.add_theme_constant_override("outline_size", 4)
	caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(caption)
	var lock := Label.new()
	lock.name = "Lock"
	lock.text = "locked"
	lock.add_theme_font_size_override("font_size", 11)
	lock.add_theme_color_override("font_color", OptionRows.NOTE_COLOR)
	lock.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	lock.offset_top = -18
	lock.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lock.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lock.visible = false
	b.add_child(lock)
	b.focus_entered.connect(_on_cell_focus.bind(i))
	b.focus_exited.connect(func() -> void: _cell_left_frame = Engine.get_process_frames())
	b.gui_input.connect(_on_cell_input.bind(i))
	b.pressed.connect(_on_cell_pressed.bind(i))
	b.add_theme_stylebox_override("focus", OptionRows.focus_box())
	return b


# --------------------------------------------------------------------------- opening, pages, filters

## Shows the options of `p_row` (its choices), the page of `p_selected`, the filters cleared.
func open(p_row: OptionRows.GridRow, p_selected: String) -> void:
	row = p_row
	choices = p_row.choices.duplicate()
	selected = p_selected
	material_filter = "all"
	query = ""
	_quiet = true
	filter_box.text = ""
	_quiet = false
	var mats := materials()
	for m: String in material_buttons:
		(material_buttons[m] as Button).visible = mats.size() > 1 and (m == "all" or mats.has(m))
	_refilter()
	page = page_of(selected) if page_of(selected) >= 0 else 0
	visible = true
	_show_page()


func close() -> void:
	visible = false
	row = null


func is_open() -> bool:
	return visible and row != null


## The materials the row's options have (garments and accessories), in MATERIALS order.
func materials() -> Array:
	var out: Array = []
	for m: String in MATERIALS:
		for c: Dictionary in choices:
			if str(c.get("material", "")) == m and not out.has(m):
				out.append(m)
	return out


## The number of pages of the options the filters keep (at least 1).
func pages() -> int:
	return maxi(1, ceili(float(shown.size()) / float(PER_PAGE)))


## The page an option is on with the filters as they are (-1 when they hide it).
func page_of(id: String) -> int:
	for i in shown.size():
		if str(shown[i].id) == id:
			return i / PER_PAGE
	return -1


## The position (0 to PER_PAGE - 1) of an option on its page (-1 when hidden).
func index_on_page(id: String) -> int:
	for i in shown.size():
		if str(shown[i].id) == id:
			return i % PER_PAGE
	return -1


## The ids on the page shown.
func visible_ids() -> Array:
	var out: Array = []
	for i in PER_PAGE:
		if (cells[i] as Button).visible and str(cell_ids[i]) != "":
			out.append(str(cell_ids[i]))
	return out


## The next (+1) or previous (-1) page, wrapping; the focus moves to the same place on it without putting anything on.
func step_page(dir: int) -> void:
	if not is_open() or pages() <= 1:
		return
	var at := _focused_index()
	page = (page + dir + pages()) % pages()
	_show_page(at if at >= 0 else 0)


func set_page(p: int) -> void:
	page = clampi(p, 0, pages() - 1)
	_show_page()


## The material filter ("all", "cloth", ...); X or F cycle it (cycle_material).
func set_material_filter(m: String) -> void:
	if not m in MATERIALS:
		m = "all"
	material_filter = m
	_refilter()
	page = 0
	_show_page(0)


func cycle_material() -> void:
	var mats := ["all"] + materials()
	if mats.size() <= 1:
		return
	set_material_filter(str(mats[(mats.find(material_filter) + 1) % mats.size()]))


## The name filter (case does not matter; anywhere in the name).
func set_query(text: String) -> void:
	if filter_box.text != text:
		_quiet = true
		filter_box.text = text
		filter_box.caret_column = text.length()
		_quiet = false
	_apply_query(text)


func _on_query(text: String) -> void:
	if not _quiet:
		_apply_query(text)


func _apply_query(text: String) -> void:
	query = text.strip_edges()
	var at := _focused_index()
	_refilter()
	page = 0
	_show_page(-1 if filter_box.has_focus() else (0 if at >= 0 else -1))


## The choices the filters keep: "None" always (it takes the piece off), then the matches in data order.
func _refilter() -> void:
	shown.clear()
	var q := query.to_lower()
	for c: Dictionary in choices:
		var none := str(c.name) == OptionRows.NONE
		if not none and material_filter != "all" and str(c.get("material", "")) != material_filter:
			continue
		if not none and q != "" and not str(c.name).to_lower().contains(q):
			continue
		shown.append(c)


## Fills the cells with the page's options; `focus_at` >= 0 moves the focus to that cell (or the page's last).
func _show_page(focus_at := -1) -> void:
	var first := page * PER_PAGE
	for i in PER_PAGE:
		var cell: Button = cells[i]
		var k := first + i
		if k < shown.size():
			var c: Dictionary = shown[k]
			cell_ids[i] = str(c.id)
			cell.visible = true
			cell.tooltip_text = str(c.name) + (" (%s)" % c.reason if bool(c.locked) else "")
			(cell.get_node("Lock") as Label).visible = bool(c.locked)
			_paint_cell(i)
		else:
			cell_ids[i] = ""
			cell.visible = false
	var n := shown.size()
	page_label.text = "Page %d of %d" % [page + 1, pages()]
	prev_button.visible = pages() > 1
	next_button.visible = pages() > 1
	var only_none := n <= 1 and (n == 0 or str(shown[0].name) == OptionRows.NONE)
	empty_label.visible = only_none
	empty_label.text = NOTHING if query == "" and material_filter == "all" else NO_MATCH
	_update_name(_focused_id() if _focused_id() != "" else selected)
	for m: String in material_buttons:
		UiKit.set_tab_open(material_buttons[m], m == material_filter)
	if focus_at >= 0 and is_inside_tree():
		var target := mini(focus_at, maxi(0, mini(n - first, PER_PAGE) - 1))
		_quiet = true
		if UiNav.focusable(cells[target]):
			(cells[target] as Button).grab_focus()
		_quiet = false
	page_shown.emit(visible_ids())


## The cell of an option on the page shown (null when it is not there).
func cell_of(id: String) -> Button:
	var i := cell_ids.find(id)
	return cells[i] if i >= 0 and (cells[i] as Button).visible else null


## The cell the focus lands on when the grid opens: the chosen option's, else the first.
func landing_cell() -> Button:
	var c := cell_of(selected)
	return c if c != null else (cells[0] if (cells[0] as Button).visible else null)


## The grid's focus rows (CreatorScreen.focus_rows while it is open): the filters, the cells by line, the pager.
func focus_rows() -> Array:
	var out: Array = []
	var top: Array = [filter_box]
	for m: String in MATERIALS:
		top.append(material_buttons[m])
	out.append(top)
	for r in ROWS:
		var line: Array = []
		for c in COLS:
			line.append(cells[r * COLS + c])
		out.append(line)
	out.append([prev_button, next_button, done_button])
	return out


## P57: the visible cells' lines wrap up and down among themselves (CreatorScreen.refresh_focus calls it after the
## screen's rows are linked): Up from the first line goes to the last, Down from the last to the first.
func wrap_cell_lines() -> void:
	var lines: Array = []
	for r in ROWS:
		var line: Array = []
		for c in COLS:
			var b: Button = cells[r * COLS + c]
			if UiNav.focusable(b):
				line.append(b)
		if not line.is_empty():
			lines.append(line)
	if lines.size() < 2:
		return
	var top: Array = lines[0]
	var bottom: Array = lines[lines.size() - 1]
	for i in top.size():
		var b: Button = top[i]
		b.focus_neighbor_top = b.get_path_to(bottom[mini(i, bottom.size() - 1)])
	for i in bottom.size():
		var b: Button = bottom[i]
		b.focus_neighbor_bottom = b.get_path_to(top[mini(i, top.size() - 1)])


## Shows the record's value (the gold border) without moving anything.
func show_selected(id: String) -> void:
	selected = id
	for i in PER_PAGE:
		if (cells[i] as Button).visible:
			_paint_cell(i)


## A thumbnail arrived (ThumbnailCache): shown at once if its option is on the page.
func set_thumbnail(id: String, tex: Texture2D) -> void:
	thumbnails[id] = tex
	var i := cell_ids.find(id)
	if i >= 0 and (cells[i] as Button).visible:
		_paint_cell(i)


## True when the cell of `id` on the page shows a thumbnail (not its name).
func shows_thumbnail(id: String) -> bool:
	var c := cell_of(id)
	return c != null and (c.get_node("Thumb") as TextureRect).texture != null


## Sizes the cells to the room the panel gives (CELL_MIN_PX to CELL_MAX_PX): COLS across, ROWS down.
func fit_cells(room: Vector2) -> void:
	var by_w := floori((room.x - GAP * (COLS - 1)) / COLS)
	var by_h := floori((room.y - GAP * (ROWS - 1)) / ROWS)
	var px := clampi(mini(by_w, by_h), CELL_MIN_PX, CELL_MAX_PX)
	if px == _cell_px:
		return
	_cell_px = px
	for c: Button in cells:
		c.custom_minimum_size = Vector2(px, px)


func cell_px() -> int:
	return _cell_px


func _paint_cell(i: int) -> void:
	var cell: Button = cells[i]
	var id := str(cell_ids[i])
	var c := _choice(id)
	var tex: Texture2D = thumbnails.get(id)
	(cell.get_node("Thumb") as TextureRect).texture = tex
	var caption := cell.get_node("Caption") as Label
	caption.text = str(c.get("name", ""))
	# the name shows until the thumbnail arrives ("None" and a locked option always say so)
	caption.visible = tex == null
	var on := id == selected
	var col := Color(0.11, 0.12, 0.15) if tex == null else Color(0.07, 0.08, 0.10)
	for st: String in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
		cell.add_theme_stylebox_override(st, _cell_box(col, on, st == "hover"))


func _choice(id: String) -> Dictionary:
	for c: Dictionary in choices:
		if str(c.id) == id:
			return c
	return {}


static var _boxes := {}


static func _cell_box(col: Color, selected_cell: bool, hover: bool) -> StyleBoxFlat:
	var key := [col.to_rgba32(), selected_cell, hover]
	if _boxes.has(key):
		return _boxes[key]
	var sb := StyleBoxFlat.new()
	sb.bg_color = col.lightened(0.1) if hover else col
	sb.set_corner_radius_all(5)
	sb.border_color = SELECTED_BORDER if selected_cell else Color(1, 1, 1, 0.12)
	sb.set_border_width_all(3 if selected_cell else 1)
	_boxes[key] = sb
	return sb


func _update_name(id: String) -> void:
	var c := _choice(id)
	if c.is_empty():
		name_label.text = ""
		return
	var words := str(c.name)
	if str(c.get("material", "")) != "":
		words += "  -  " + str(MATERIAL_NAMES.get(str(c.material), c.material)).to_lower()
	if bool(c.get("locked", false)):
		words += "  -  " + str(c.reason)
	name_label.text = words
	name_label.add_theme_color_override("font_color", OptionRows.NOTE_COLOR if bool(c.get("locked", false)) else UiKit.TEXT)


func _focused_index() -> int:
	if not is_inside_tree():
		return -1
	var f := get_viewport().gui_get_focus_owner()
	return cells.find(f)


func _focused_id() -> String:
	var i := _focused_index()
	return str(cell_ids[i]) if i >= 0 else ""


# --------------------------------------------------------------------------- input

func _on_cell_focus(i: int) -> void:
	var id := str(cell_ids[i])
	_update_name(id)
	cell_focused.emit(id)
	if _quiet or Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		return   # a page turn or a filter moved it, or a click will press it
	if _cell_left_frame != Engine.get_process_frames():
		return   # the focus came into the cells from elsewhere (the grid opening, the filters, the pager): it lands
	_choose(i, false)


func _on_cell_input(event: InputEvent, i: int) -> void:
	var mb := event as InputEventMouseButton
	if mb != null and mb.button_index == MOUSE_BUTTON_LEFT:
		_mouse_press = true
	elif event.is_action_pressed("ui_accept") and not event is InputEventMouseButton:
		_mouse_press = false
	var _unused := i


func _on_cell_pressed(i: int) -> void:
	var by_mouse := _mouse_press
	_mouse_press = false
	_choose(i, not by_mouse)


func _choose(i: int, close_after: bool) -> void:
	var c := _choice(str(cell_ids[i]))
	if c.is_empty():
		return
	if bool(c.locked):
		_update_name(str(c.id))
		return
	chosen.emit(str(c.id), close_after)


func _gui_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb != null and mb.pressed:
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			step_page(-1)
			accept_event()
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			step_page(1)
			accept_event()
