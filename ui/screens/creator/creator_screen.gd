class_name CreatorScreen
extends UiScreen
## The character creator (P44; plan M10 §2.10, decisions 13-18): ScreenStack SCREENS["creator"]. One screen,
## three doors:
##   open("creator", {"context": "new_game", "start": {"mode": "valley" | "world", "options": {...}}})
##       the title's New Game (after its confirm and the prologue or skip choice) and the launcher's world start
##       (--creator); "Begin your journey" / "Begin in the Old Kingdom" closes with
##       {"appearance": record, "begin": true} from the button's own pressed handler, and the title starts the
##       game in that same call stack (browsers grant the pointer lock only inside the click);
##   open("creator", {"context": "shrine", "player": GiantPlayer, "shrine": Shrine, "appearance": record})
##       the shrine's Appearance tab; "Keep this look" closes with {"appearance": record}.
## Back / Cancel, Esc and pad B close with {"cancelled": true} at once while the record equals the one the
## screen opened with; otherwise they ask "Discard your changes?" (Keep editing, where the focus starts, or
## Discard). It writes nothing itself: the title and the tab do what the result says.
##
## Layout (1280x720; larger windows grow the panels): a title row; the category tabs (OptionRows.CATEGORIES);
## the preview (GiantPreview, 720x544) at the left with Full / Face / Back / Game view, the options panel
## (512x544) at the right; Randomize, Randomize all, Undo, Reset, Presets..., then Back and Begin (Cancel and
## Keep at a shrine); the stack's footer shows this screen's own nav_hint() (cached: the stack reads it every
## frame).
##
## Controls (the P16 focus rules): focus_rows() = [the tabs] + the category's rows + [the actions]; LB and RB,
## or PageUp and PageDown, change the category; swatch rows and cyclers apply the focused value at once,
## sliders move the greys, toggles the scars (OptionRows). The preview turns with the right stick, a mouse drag
## or Q and E, zooms with LT and RT, the wheel or + and -; X or V cycles its view; Y or R randomizes the open
## category; "Randomize all" keeps the outfit unless Clothing is open; Undo (the button, Ctrl+Z, the pad's View
## button) steps back through HISTORY_MAX changes - swatches, Randomize, presets and Reset included; Reset
## returns to the look the screen opened with (a shrine) or the default preset (New Game); Ctrl+Enter is
## Begin or Keep. Randomize draws from the screen's own generator, seeded from the clock: never Sim.rng.
##
## Reading in play (decision 18): a design row whose region the outfit covers says "Hidden by your clothing",
## and while it has the focus the covering garments fade in the preview; Tattoos and Scars frame the focused
## design's region, War paint its design's, Hair the three-quarter view from behind, Beard and Eyes the face,
## the other categories the whole giant. While this screen is on top the root viewport's 3D is off (the world
## behind a shrine's screens is not drawn); it is back on when the creator closes or another screen covers it.

const TITLE := "Shape your giant"
const SUB_NEW := "New Game  -  you can change all of this later at any shrine."
const SUB_SHRINE := "Changes are free, at this shrine and at every other."
const BEGIN_VALLEY := "Begin your journey"
const BEGIN_WORLD := "Begin in the Old Kingdom"
const KEEP := "Keep this look"
const QUESTION := "Discard your changes?"
const QUESTION_NOTE := "The look you made here will be lost."
const KEEP_EDITING := "Keep editing"
const DISCARD := "Discard"
## Undo steps back through at least this many changes.
const HISTORY_MAX := 64
## Q / E turn the preview this far per press (held: repeats).
const TURN_STEP_DEG := 15.0
## The stick's dead zone and how fast the triggers zoom (steps a second at full pull).
const AXIS_DEADZONE := 0.2
const TRIGGER_ZOOM_S := 4.0
## A Randomize that draws the same look tries again, at most this often.
const RANDOM_TRIES := 8
## The room kept under the Presets list for the focused preset's description (lines of its 12 px text).
const PRESET_NOTE_LINES := 3
const HINT_PAD := "LB/RB: category   D-pad: choose   A: select   Y: randomize   X: view   R-stick, LT/RT: turn, zoom   View: undo   B: back"
const HINT_KEYS := "PgUp/PgDn: category   Arrows: choose   R: randomize   V: view   Q/E, +/-: turn, zoom   Ctrl+Z: undo   Ctrl+Enter: %s   Esc: back"

## "new_game" or "shrine".
var context := "new_game"
## New Game: {"mode", "options"} the title starts with Begin.
var start: Dictionary = {}
var player: GiantPlayer = null
var shrine: Node = null
## The line whose locks apply ("" at New Game: no line yet).
var ancestry := ""
## The record shown now, and the one the screen opened with (Back asks when they differ).
var record: Dictionary = {}
var opened_with: Dictionary = {}
## The records before each change, the newest last (Undo).
var history: Array = []
var preview: GiantPreview
var begin_button: Button
var back_button: Button
var randomize_button: Button
var randomize_all_button: Button
var undo_button: Button
var reset_button: Button
var presets_button: Button
var keep_editing_button: Button
var discard_button: Button
## Category -> its tab button.
var tab_buttons: Dictionary = {}
## View name ("full", "face", "back", "game") -> its button.
var view_buttons: Dictionary = {}
var _category := ""
var _rows: Array = []                 ## OptionRows.Row of the open category
var _category_boxes: Dictionary = {}  ## category -> the VBoxContainer of its rows (built on first open)
var _category_rows: Dictionary = {}   ## category -> its OptionRows.Row
var _rows_box: VBoxContainer
var _scroll: ScrollContainer
var _category_label: Label
var _status: Label
var _question: Control
var _rng := RandomNumberGenerator.new()
var _merge_key := ""
var _root_3d_off := false
var _axes := {}                       ## JoyAxis -> value (the right stick and the triggers)
var _hints := {}
var _focused_row: OptionRows.Row = null
var _preset_note: Label = null        ## the focused preset's description, under the Presets list


func _ready() -> void:
	_rng.seed = hash([Time.get_ticks_usec(), Time.get_unix_time_from_system(), get_instance_id()])
	context = "shrine" if str(args.get("context", "new_game")) == "shrine" else "new_game"
	start = args.get("start", {}) if typeof(args.get("start")) == TYPE_DICTIONARY else {}
	player = args.get("player") as GiantPlayer
	shrine = args.get("shrine") as Node
	if context == "shrine" and player == null and is_inside_tree():
		player = get_tree().get_first_node_in_group("player") as GiantPlayer
	ancestry = _player_ancestry()
	var given: Variant = args.get("appearance")
	var base: Dictionary = given if typeof(given) == TYPE_DICTIONARY and not (given as Dictionary).is_empty() \
		else (player.appearance.record() if _has_appearance() else Appearance.default_record())
	record = Appearance.sanitize(base, ancestry).record
	opened_with = record.duplicate(true)
	_build()
	if context == "shrine" and player != null:
		preview.set_game_profile(player.profile)
		var k := GiantPreview.stage_scale(player.profile)
		preview.set_weapon(player.current_weapon(), player.current_weapon_scale() / k)
	var keys_end := "keep" if context == "shrine" else "begin"
	_hints = {true: HINT_PAD, false: HINT_KEYS % keys_end, "question_pad": UiNav.hint_text(true),
		"question_keys": UiNav.hint_text(false)}
	_apply()
	show_category(str(args.get("category", OptionRows.CATEGORIES[0])))


func _has_appearance() -> bool:
	return player != null and is_instance_valid(player) and player.appearance != null


func _player_ancestry() -> String:
	if _has_appearance():
		return player.appearance.ancestry()
	return str(args.get("ancestry", ""))


# --------------------------------------------------------------------------- UiScreen

## At a shrine the creator opens over the paused shrine screen; at the title nothing runs under it.
func pauses_game() -> bool:
	return context == "shrine"


## M9's footer reads this every frame: cached lines.
func nav_hint(pad: bool) -> String:
	if question_open():
		return str(_hints.get("question_pad" if pad else "question_keys", ""))
	return str(_hints.get(pad, ""))


func first_focus() -> Control:
	if question_open():
		return keep_editing_button
	for row: OptionRows.Row in _rows:
		var c := row.main_control()
		if UiNav.focusable(c):
			return c
	var tab: Button = tab_buttons.get(_category)
	return tab if tab != null else begin_button


## The tabs, the category's rows, then the actions (only the question's two buttons while it is open).
func focus_rows() -> Array:
	if question_open():
		return [[keep_editing_button, discard_button]]
	var rows: Array = [_tab_list()]
	for row: OptionRows.Row in _rows:
		rows.append(row.focus_controls())
	rows.append([randomize_button, randomize_all_button, undo_button, reset_button, presets_button, back_button,
		begin_button])
	return rows


func on_open() -> void:
	preview.render_live()
	_sync_root_3d()


func on_close() -> void:
	_restore_root_3d()


func _exit_tree() -> void:
	_restore_root_3d()


## Esc, pad B, Back / Cancel: closes at once when nothing changed, else asks; with the question open, it is
## "Keep editing".
func cancel() -> void:
	if question_open():
		keep_editing()
		return
	if is_changed():
		_ask_discard()
		return
	close({"cancelled": true})


# --------------------------------------------------------------------------- the record

## The record shown now (a copy).
func current_record() -> Dictionary:
	return record.duplicate(true)


## True when the record differs from the one the screen opened with.
func is_changed() -> bool:
	return not OptionRows.same(record, opened_with)


## Puts `new_record` on (sanitized for the line), entering the old one into the undo history; the changes of
## one slider in a row (`merge_key`) are one step. False when nothing changed.
func set_record(new_record: Dictionary, merge_key := "") -> bool:
	var r: Dictionary = Appearance.sanitize(new_record, ancestry).record
	if OptionRows.same(r, record):
		return false
	if merge_key == "" or merge_key != _merge_key or history.is_empty():
		history.append(record.duplicate(true))
		while history.size() > HISTORY_MAX:
			history.pop_front()
	_merge_key = merge_key
	record = r
	_apply()
	return true


## Steps back one change. False when there is nothing to undo.
func undo() -> bool:
	_merge_key = ""
	if history.is_empty():
		_set_status("Nothing to undo.")
		return false
	record = history.pop_back()
	_apply()
	_set_status("Undone.")
	return true


## Back to the look the screen opened with (a shrine) or the default preset (New Game); undoable.
func reset() -> bool:
	_merge_key = ""
	var target: Dictionary = opened_with if context == "shrine" else Appearance.default_record()
	var changed := set_record(target)
	_set_status("Reset." if changed else "Nothing to reset.")
	return changed


## Randomizes the open category (Y, R); undoable. The screen's own generator only.
func randomize_category() -> bool:
	return _randomize(str(OptionRows.RANDOM_SCOPE.get(_category, "all")), true)


## "Randomize all": everything but the outfit, unless the Clothing category is open.
func randomize_all() -> bool:
	return _randomize("all", _category != "Clothing")


func _randomize(scope: String, keep_outfit: bool) -> bool:
	_merge_key = ""
	for i in RANDOM_TRIES:
		var r := Appearance.random_record(_rng, scope, keep_outfit, ancestry, record)
		if set_record(r):
			_set_status("Randomized: %s." % ("everything" if scope == "all" else _category.to_lower()))
			return true
	return false


## The generator Randomize draws from (tests check it is not Sim's).
func rng() -> RandomNumberGenerator:
	return _rng


## Begin (New Game) or Keep this look (a shrine): closes with the record. The title starts the game in this
## call stack, from the button's own pressed handler.
func begin() -> void:
	if question_open():
		return
	var out: Dictionary = Appearance.sanitize(record, ancestry).record
	if context == "shrine":
		close({"appearance": out})
	else:
		close({"appearance": out, "begin": true})


## The look drawn now: the record for the line, on the preview.
func _apply() -> void:
	if preview != null:
		preview.apply_look(Appearance.to_look(record, ancestry))
	_show_values()


func _show_values() -> void:
	var index := preview.index() if preview != null else {}
	var no_line := not Appearance.line_chosen(ancestry)
	var cover := OptionRows.coverage(record, index, ancestry)
	for row: OptionRows.Row in _rows:
		row.show_value(OptionRows.value_of(record, row.key))
		var note := ""
		if OptionRows.row_hidden(row.spec, record, index, ancestry, cover):
			note = OptionRows.HIDDEN_NOTE
		elif row.key == "mark" and no_line:
			note = OptionRows.MARK_NO_LINE
		row.set_note(note)
	_update_fade()


# --------------------------------------------------------------------------- categories

func categories() -> Array:
	return OptionRows.CATEGORIES.duplicate()


func current_category() -> String:
	return _category


## Opens a category: its rows, its framing, the focus on its first row.
func show_category(category: String) -> void:
	if not category in OptionRows.CATEGORIES:
		category = OptionRows.CATEGORIES[0]
	_category = category
	for c: String in tab_buttons:
		if UiKit.is_tab_open(tab_buttons[c]) != (c == category) or not (tab_buttons[c] as Button).has_meta("tab_open"):
			UiKit.set_tab_open(tab_buttons[c], c == category)
	if _category_label != null:
		_category_label.text = category
	_build_rows()
	_merge_key = ""
	preview.view = ""
	_frame_for(null)
	_update_view_buttons()
	if is_inside_tree():
		refresh_focus()
		var f := first_focus()
		if UiNav.focusable(f):
			f.grab_focus()


## LB / RB, PageUp / PageDown: the previous (-1) or next (+1) category, wrapping.
func step_category(step: int) -> void:
	var i := OptionRows.CATEGORIES.find(_category)
	show_category(str(OptionRows.CATEGORIES[(i + step + OptionRows.CATEGORIES.size()) % OptionRows.CATEGORIES.size()]))


## The open category's row of record path `key` (null when it has none).
func row(key: String) -> OptionRows.Row:
	for r: OptionRows.Row in _rows:
		if r.key == key:
			return r
	return null


func rows() -> Array:
	return _rows.duplicate()


## Picks `value` on the row `key` of the open category, as the player would (tests, the sheet tool).
func pick(key: String, value: Variant) -> bool:
	var r := row(key)
	if r == null:
		return false
	return _on_picked(r, value)


## The open category's rows: built the first time it opens, kept (hidden) while another is open.
func _build_rows() -> void:
	_focused_row = null
	for c: String in _category_boxes:
		(_category_boxes[c] as Control).visible = c == _category
	if not _category_boxes.has(_category):
		var box := VBoxContainer.new()
		box.name = "Rows_" + _category.replace(" ", "_")
		box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		box.add_theme_constant_override("separation", 12)
		var built: Array = []
		for r: OptionRows.Row in OptionRows.build_rows(_category, ancestry):
			box.add_child(r)
			r.picked.connect(_on_picked)
			r.focused.connect(_on_row_focused)
			built.append(r)
		if _category == "Presets":
			_preset_note = _build_preset_note()
			box.add_child(_preset_note)
		_rows_box.add_child(box)
		_category_boxes[_category] = box
		_category_rows[_category] = built
	_rows = (_category_rows[_category] as Array).duplicate()
	_show_values()
	if _scroll != null:
		_scroll.scroll_vertical = 0


## The focused preset's description: one label under the list, of a fixed height, so that no preset button
## moves when the focus does (M10 gate, LA-1: a press moves the focus, and a button that jumps under the
## pointer before the release loses the click).
func _build_preset_note() -> Label:
	var note := UiKit.label("", 12, UiKit.MUTED)
	note.name = "PresetNote"
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.custom_minimum_size = Vector2(0, PRESET_NOTE_LINES * (note.get_theme_font("font").get_height(12) + 3.0))
	return note


## The preset description shown under the Presets list ("" before a preset has had the focus).
func preset_description() -> String:
	return _preset_note.text if _preset_note != null else ""


func _on_picked(r: OptionRows.Row, value: Variant) -> bool:
	var changed := false
	match r.spec.get("kind", ""):
		"toggle":
			var scar := str(r.spec.get("id", ""))
			var next := OptionRows.with_scar(record, scar, bool(value))
			if bool(value) and OptionRows.same(next, record):
				_set_status("At most %d scars." % Appearance.MAX_SCARS)
				_show_values()
				return false
			changed = set_record(next)
		"slider":
			changed = set_record(OptionRows.with_value(record, r.key, value), r.key)
			return changed
		"preset":
			changed = set_record(OptionRows.with_value(record, r.key, value))
			if changed:
				_set_status("Preset: %s." % str(r.spec.get("label", "")))
		_:
			changed = set_record(OptionRows.with_value(record, r.key, value))
	if r.key == "paint.design" or r.key.begins_with("tattoos.") or r.key.begins_with("scar."):
		_frame_for(r)
	return changed


func _on_row_focused(r: OptionRows.Row) -> void:
	_focused_row = r
	if r is OptionRows.PresetRow and _preset_note != null:
		_preset_note.text = (r as OptionRows.PresetRow).description
	_frame_for(r)
	_update_fade()


## The category's framing; for Tattoos, Scars and War paint the region of the focused (or first) design row.
func _frame_for(r: OptionRows.Row) -> void:
	if preview == null or preview.view != "":
		return
	preview.frame(category_framing(_category, r))


## The preview framing of a category (and its focused row): see the class notes.
func category_framing(category: String, r: OptionRows.Row = null) -> String:
	match category:
		"Hair":
			return "hair"
		"Beard", "Eyes":
			return "face"
		"Tattoos", "Scars", "War paint":
			var spec: Dictionary = r.spec if r != null else (_rows[0].spec if not _rows.is_empty() else {})
			var region := OptionRows.row_region(spec, record, preview.index(), ancestry)
			return GiantPreview.region_framing(region) if region != "" else "face"
	return "full"


## The covering garments fade while a "Hidden by your clothing" row has the focus.
func _update_fade() -> void:
	if preview == null:
		return
	var hidden := _focused_row != null and is_instance_valid(_focused_row) and _focused_row.note_text() == OptionRows.HIDDEN_NOTE
	var want := 0.7 if hidden else 0.0
	if not is_equal_approx(preview.fade(), want):
		preview.set_fade(want)


# --------------------------------------------------------------------------- views

## The view buttons (Full / Face / Back / Game view): `view_name` "" returns to the category's framing.
func set_view(view_name: String) -> void:
	preview.view = view_name if view_name in GiantPreview.VIEWS else ""
	if preview.view == "":
		preview.view = ""
		_frame_for(_focused_row)
	else:
		preview.frame(preview.view)
	_update_view_buttons()


## X / V: the next view.
func cycle_view() -> void:
	set_view(preview.next_view())


func _update_view_buttons() -> void:
	for v: String in view_buttons:
		var open := preview != null and preview.view == v
		if UiKit.is_tab_open(view_buttons[v]) != open or not (view_buttons[v] as Button).has_meta("tab_open"):
			UiKit.set_tab_open(view_buttons[v], open)


# --------------------------------------------------------------------------- the discard question

func question_open() -> bool:
	return _question != null and _question.visible


func _ask_discard() -> void:
	_question.visible = true
	refresh_focus()
	keep_editing_button.grab_focus()


## "Keep editing": the question closes, the focus goes back to the screen.
func keep_editing() -> void:
	if not question_open():
		return
	_question.visible = false
	refresh_focus()
	var f := first_focus()
	if UiNav.focusable(back_button):
		f = back_button
	if UiNav.focusable(f):
		f.grab_focus()


## "Discard": closes without the changes.
func discard() -> void:
	_question.visible = false
	close({"cancelled": true})


# --------------------------------------------------------------------------- the root viewport's 3D

## While this screen is on top the root viewport draws no 3D (the world behind a shrine's screens).
func _sync_root_3d() -> void:
	if not is_inside_tree():
		return
	var want := stack != null and is_instance_valid(stack) and stack.top() == self
	if want != _root_3d_off:
		_root_3d_off = want
		get_tree().root.disable_3d = want


func _restore_root_3d() -> void:
	if _root_3d_off and is_inside_tree():
		get_tree().root.disable_3d = false
	_root_3d_off = false


## True while the root viewport's 3D is off because of this screen.
func root_3d_off() -> bool:
	return _root_3d_off


# --------------------------------------------------------------------------- input

func _on_top() -> bool:
	return is_inside_tree() and stack != null and is_instance_valid(stack) and stack.top() == self


func _process(delta: float) -> void:
	_sync_root_3d()
	if not _on_top() or question_open() or preview == null:
		return
	var rx := float(_axes.get(JOY_AXIS_RIGHT_X, 0.0))
	if absf(rx) > AXIS_DEADZONE:
		preview.turn(-rx * GiantPreview.TURN_DEG_S * delta)
	var zoom := float(_axes.get(JOY_AXIS_TRIGGER_RIGHT, 0.0)) - float(_axes.get(JOY_AXIS_TRIGGER_LEFT, 0.0))
	if absf(zoom) > AXIS_DEADZONE:
		preview.zoom(zoom * TRIGGER_ZOOM_S * delta)


func _input(event: InputEvent) -> void:
	if not _on_top():
		return
	var motion := event as InputEventJoypadMotion
	if motion != null:
		if motion.axis in [JOY_AXIS_RIGHT_X, JOY_AXIS_TRIGGER_LEFT, JOY_AXIS_TRIGGER_RIGHT]:
			_axes[motion.axis] = motion.axis_value
		return
	if question_open():
		return
	if _handle_key(event as InputEventKey) or _handle_pad(event as InputEventJoypadButton):
		get_viewport().set_input_as_handled()


func _handle_key(k: InputEventKey) -> bool:
	if k == null or not k.pressed:
		return false
	if k.ctrl_pressed:
		if k.keycode in [KEY_ENTER, KEY_KP_ENTER] and not k.echo:
			begin()
			return true
		if k.keycode == KEY_Z:
			undo()
			return true
		return false
	if k.alt_pressed:
		return false
	match k.keycode:
		KEY_PAGEUP:
			step_category(-1)
		KEY_PAGEDOWN:
			step_category(1)
		KEY_Q:
			preview.turn(TURN_STEP_DEG)
		KEY_E:
			preview.turn(-TURN_STEP_DEG)
		KEY_PLUS, KEY_EQUAL, KEY_KP_ADD:
			preview.zoom(1)
		KEY_MINUS, KEY_KP_SUBTRACT:
			preview.zoom(-1)
		KEY_V:
			if not k.echo:
				cycle_view()
		KEY_R:
			if not k.echo:
				randomize_category()
		_:
			return false
	return true


func _handle_pad(b: InputEventJoypadButton) -> bool:
	if b == null or not b.pressed:
		return false
	match b.button_index:
		JOY_BUTTON_LEFT_SHOULDER:
			step_category(-1)
		JOY_BUTTON_RIGHT_SHOULDER:
			step_category(1)
		JOY_BUTTON_X:
			cycle_view()
		JOY_BUTTON_Y:
			randomize_category()
		JOY_BUTTON_BACK:
			undo()
		_:
			return false
	return true


# --------------------------------------------------------------------------- layout

func _tab_list() -> Array:
	var out: Array = []
	for c: String in OptionRows.CATEGORIES:
		out.append(tab_buttons[c])
	return out


func status_text() -> String:
	return _status.text if _status != null else ""


func _set_status(text: String) -> void:
	if _status != null:
		_status.text = text


func _build() -> void:
	var bg := ColorRect.new()
	bg.name = "Backdrop"
	bg.color = Color(0.05, 0.06, 0.08, 1.0)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(bg)
	var margin := MarginContainer.new()
	margin.name = "Layout"
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side: String in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, 16)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_bottom", 40)   # the stack's footer hint: the bottom 30 px
	add_child(margin)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	margin.add_child(v)
	var head := HBoxContainer.new()
	head.name = "Head"
	head.add_theme_constant_override("separation", 18)
	v.add_child(head)
	head.add_child(UiKit.label(TITLE, 26))
	var sub := UiKit.label(SUB_SHRINE if context == "shrine" else SUB_NEW, 13, UiKit.MUTED)
	sub.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(sub)
	var tabs := HBoxContainer.new()
	tabs.name = "Tabs"
	tabs.add_theme_constant_override("separation", 4)
	v.add_child(tabs)
	for c: String in OptionRows.CATEGORIES:
		var b := UiKit.button(c, 15)
		b.name = "Tab_" + c.replace(" ", "_")
		b.pressed.connect(show_category.bind(c))
		tabs.add_child(b)
		tab_buttons[c] = b
	var main := HBoxContainer.new()
	main.name = "Main"
	main.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main.add_theme_constant_override("separation", 16)
	v.add_child(main)
	var holder := Control.new()
	holder.name = "PreviewHolder"
	holder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	holder.size_flags_stretch_ratio = 720.0
	holder.clip_contents = true
	holder.mouse_filter = Control.MOUSE_FILTER_PASS
	main.add_child(holder)
	preview = GiantPreview.new()
	preview.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	holder.add_child(preview)
	var views := HBoxContainer.new()
	views.name = "Views"
	views.add_theme_constant_override("separation", 4)
	views.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	views.offset_left = 8
	views.offset_top = -42
	views.offset_bottom = -8
	views.grow_vertical = Control.GROW_DIRECTION_BEGIN
	holder.add_child(views)
	for view_name: String in GiantPreview.VIEWS:
		var b := UiKit.button(str(GiantPreview.VIEW_NAMES[view_name]), 14)
		b.name = "View_" + view_name
		b.focus_mode = Control.FOCUS_NONE   # mouse only; X / V cycle them
		b.pressed.connect(set_view.bind(view_name))
		views.add_child(b)
		view_buttons[view_name] = b
	var panel := UiKit.panel(UiKit.BG_LIGHT)
	panel.name = "Options"
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_stretch_ratio = 512.0
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	main.add_child(panel)
	var pv := VBoxContainer.new()
	pv.add_theme_constant_override("separation", 6)
	panel.add_child(pv)
	_category_label = UiKit.label("", 22)
	pv.add_child(_category_label)
	_scroll = ScrollContainer.new()
	_scroll.name = "Scroll"
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.follow_focus = true
	pv.add_child(_scroll)
	_rows_box = VBoxContainer.new()
	_rows_box.name = "Rows"
	_rows_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rows_box.add_theme_constant_override("separation", 12)
	_scroll.add_child(_rows_box)
	_status = UiKit.label("", 13, UiKit.MUTED)
	_status.name = "Status"
	pv.add_child(_status)
	var actions := HBoxContainer.new()
	actions.name = "Actions"
	actions.add_theme_constant_override("separation", 8)
	v.add_child(actions)
	randomize_button = _action(actions, "Randomize", randomize_category)
	randomize_all_button = _action(actions, "Randomize all", randomize_all)
	undo_button = _action(actions, "Undo", undo)
	reset_button = _action(actions, "Reset", reset)
	presets_button = _action(actions, "Presets...", show_category.bind("Presets"))
	var gap := Control.new()
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	actions.add_child(gap)
	back_button = _action(actions, "Cancel" if context == "shrine" else "Back", cancel)
	var begin_text := KEEP if context == "shrine" else (BEGIN_WORLD if str(start.get("mode", "valley")) == "world" else BEGIN_VALLEY)
	begin_button = _action(actions, begin_text, begin, 17)
	_build_question()


func _action(box: HBoxContainer, text: String, handler: Callable, font := 16) -> Button:
	var b := UiKit.button(text, font)
	b.name = "Action_" + text.replace(" ", "_").replace(".", "")
	b.pressed.connect(func() -> void: handler.call())
	box.add_child(b)
	return b


func _build_question() -> void:
	_question = Control.new()
	_question.name = "Question"
	_question.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_question.mouse_filter = Control.MOUSE_FILTER_STOP
	_question.visible = false
	add_child(_question)
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.6)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_STOP
	_question.add_child(shade)
	var box := UiKit.panel(Color(0.08, 0.09, 0.11, 0.98))
	box.name = "QuestionPanel"
	box.mouse_filter = Control.MOUSE_FILTER_STOP
	box.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	box.offset_left = -230
	box.offset_right = 230
	box.offset_top = -90
	box.offset_bottom = 70
	box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	box.grow_vertical = Control.GROW_DIRECTION_BOTH
	_question.add_child(box)
	var qv := VBoxContainer.new()
	qv.add_theme_constant_override("separation", 12)
	box.add_child(qv)
	var q := UiKit.label(QUESTION, 22)
	q.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	qv.add_child(q)
	var note := UiKit.label(QUESTION_NOTE, 14, UiKit.MUTED)
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	qv.add_child(note)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 18)
	qv.add_child(row)
	keep_editing_button = UiKit.button(KEEP_EDITING, 17)
	keep_editing_button.pressed.connect(keep_editing)
	row.add_child(keep_editing_button)
	discard_button = UiKit.button(DISCARD, 17)
	discard_button.pressed.connect(discard)
	row.add_child(discard_button)


## The discard question's panel (layout tests).
func question_panel() -> Control:
	return _question.get_node("QuestionPanel") as Control if _question != null else null
