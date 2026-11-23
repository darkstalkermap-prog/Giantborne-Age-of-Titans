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
##       the shrine's Appearance tab; "Keep this look" closes with {"appearance": record}. A record made by a
##       later build of the game is not edited: the screen starts from the default look (what the giant shows
##       for it) and only a kept change replaces it (`later_build`).
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
## or Q and E, zooms with the right stick's up and down (P57; LT and RT jump five rows), the wheel or + and -; X or V cycles its view; Y or R randomizes the open
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
##
## The creator II (P55; plan M11 §2.7, §3.8): eleven categories (OptionRows.CATEGORIES: Presets, Body, Face, Hair,
## Beard, Tattoos, War paint, Scars, Clothing, Accessories, Colours), every row built from the sets' data. A grid row
## (a clothing or accessory slot, the outfits, a style, beads, a tattoo region, a war paint place) opens its option
## grid (OptionGrid) in the options panel: pages of 4 x 3 thumbnails, "None" first, LT / RT, the wheel or PageUp /
## PageDown for pages, the material filter on X or F, the name filter by typing; B, Esc or Done close it, LB / RB
## change the category. Thumbnails (ThumbnailCache, this screen's child) are made one a frame for the page shown
## only, never while the screen opens. The build sliders show the stage-1 rear Game view while they have the focus;
## a design on the giant's left is framed from his left (the index's `side`). Randomize dresses by slot
## (OptionRows.random_record). Undo, the discard question and Reset cover every row; a grid's browsing (the
## focus moving over its cells) is one change, as one slider's drag is.

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
## How fast the right stick's up and down zooms (steps a second at full tilt; P57: the triggers jump rows now).
const TRIGGER_ZOOM_S := 4.0
## P57: LT / RT with no grid open move the focus this many rows along the screen's rows (the tabs, the category's
## rows and the actions, wrapping), so with the D-pad any row of Clothing's eleven is at most two presses away.
const ROW_JUMP := 5
## A Randomize that draws the same look tries again, at most this often.
const RANDOM_TRIES := 8
## The room kept under the Presets list for the focused preset's description (lines of its 12 px text).
const PRESET_NOTE_LINES := 3
const HINT_PAD := "LB/RB: category   D-pad, LT/RT: choose   A: open   Y: randomize   X: view   R-stick: turn, zoom   View: undo   B: back"
const HINT_KEYS := "PgUp/PgDn: category   Arrows: choose   Enter: open   R: randomize   V: view   Q/E, +/-: turn, zoom   Ctrl+Z: undo   Ctrl+Enter: %s   Esc: back"
## While an option grid is open (P55).
const HINT_GRID_PAD := "D-pad: choose   A: done   LT/RT: page   X: material   LB/RB: category   View: undo   B: back"
const HINT_GRID_KEYS := "Arrows: choose   Enter: done   PgUp/PgDn or wheel: page   Type or /: find   F: material   Ctrl+Z: undo   Esc: back"
## A trigger past this counts as a page press while a grid is open (it falls back under GRID_TRIGGER_RELEASE).
const GRID_TRIGGER_PRESS := 0.6
const GRID_TRIGGER_RELEASE := 0.3

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
## True when the giant's own record was made by a later build of the game (Appearance.is_future): the screen
## shows and edits the default look instead, Keep with a change stores this build's record in its place, and
## Keep without one, like Cancel, leaves the later build's record as it was (plan M10 §2.2: kept untouched;
## Appearance.NOTE_FUTURE: "the default look is shown until you change it").
var later_build := false
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
## B5 (B4's FOLLOWUPS row): at a shrine, the giant's worn armour drawn over the preview (the Armour toggle beside the
## views; mouse only, as they are). The record edited is still the giant's own clothes: the armour is drawn over them
## in the world as it was before; this only shows the two together. Off when it opens; null when nothing is worn.
var armour_button: Button
var show_armour := false
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
## P55: the option grid (in the options panel, in place of the rows while open), its row, and the thumbnails.
var grid: OptionGrid
var thumbnails: ThumbnailCache
## Gate B: the pictures the page shown asked for, key (ThumbnailCache.key_of) -> option id.
var _thumbs_wanted: Dictionary = {}
var _grid_row: OptionRows.GridRow = null
var _grid_session := 0
var _triggers := {}                   ## JoyAxis -> true while a trigger is held past GRID_TRIGGER_PRESS
var _colours_signature := ""          ## OptionRows.dye_signature of the record the Colours rows were built for


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
	# A later build's record (v above this build's) is never edited: the screen starts from the default look,
	# which is what the giant shows for it, and only a kept change replaces it (M10 gate, LB-1).
	later_build = Appearance.is_future(base)
	if later_build:
		base = Appearance.default_record()
	record = Appearance.sanitize(base, ancestry).record
	opened_with = record.duplicate(true)
	_build()
	if context == "shrine" and player != null:
		preview.set_game_profile(player.profile)
		var k := GiantPreview.stage_scale(player.profile)
		preview.set_weapon(player.current_weapon(), player.current_weapon_scale() / k)
	var keys_end := "keep" if context == "shrine" else "begin"
	_hints = {true: HINT_PAD, false: HINT_KEYS % keys_end, "question_pad": UiNav.hint_text(true),
		"question_keys": UiNav.hint_text(false), "grid_pad": HINT_GRID_PAD, "grid_keys": HINT_GRID_KEYS}
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
	if grid_open():
		return str(_hints.get("grid_pad" if pad else "grid_keys", ""))
	return str(_hints.get(pad, ""))


func first_focus() -> Control:
	if question_open():
		return keep_editing_button
	if grid_open():
		var cell := grid.landing_cell()
		return cell if cell != null else grid.done_button
	for row: OptionRows.Row in _rows:
		var c := row.main_control()
		if UiNav.focusable(c):
			return c
	var tab: Button = tab_buttons.get(_category)
	return tab if tab != null else begin_button


## The tabs, the category's rows (the grid's filters, cells and pager while a grid is open), then the actions (only
## the question's two buttons while it is open).
func focus_rows() -> Array:
	if question_open():
		return [[keep_editing_button, discard_button]]
	if grid_open():
		return [_tab_list()] + grid.focus_rows() + [[randomize_button, randomize_all_button, undo_button, reset_button,
			presets_button, back_button, begin_button]]
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
	if grid_open():
		close_grid()
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
	if Appearance.is_future(new_record):
		return false   # a later build's record is never shown or edited here
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


## Randomizes the open category (Y, R); undoable. The screen's own generator only (OptionRows.random_record:
## the clothing by slot).
func randomize_category() -> bool:
	return _randomize(str(OptionRows.RANDOM_SCOPE.get(_category, "all")), true)


## "Randomize all": everything but the clothing and accessories, unless the Clothing category is open.
func randomize_all() -> bool:
	return _randomize("all", _category != "Clothing")


func _randomize(scope: String, keep_outfit: bool) -> bool:
	_merge_key = ""
	for i in RANDOM_TRIES:
		var r := OptionRows.random_record(_rng, scope, keep_outfit, ancestry, record)
		if set_record(r):
			_set_status("Randomized: %s." % ("everything" if scope == "all" else _category.to_lower()))
			return true
	_set_status("Nothing to randomize here.")
	return false


## The generator Randomize draws from (tests check it is not Sim's).
func rng() -> RandomNumberGenerator:
	return _rng


## Begin (New Game) or Keep this look (a shrine): closes with the record. The title starts the game in this
## call stack, from the button's own pressed handler. At a shrine, Keep without a change on a later build's
## look closes as Cancel does (`later_build`).
func begin() -> void:
	if question_open():
		return
	if later_build and context == "shrine" and not is_changed():
		close({"cancelled": true})   # nothing was changed: the later build's record stays as it is
		return
	var out: Dictionary = Appearance.sanitize(record, ancestry).record
	if context == "shrine":
		close({"appearance": out})
	else:
		close({"appearance": out, "begin": true})


## The look drawn now: the record for the line, on the preview (B5: with the worn armour over it while the toggle is on).
func _apply() -> void:
	if preview != null:
		preview.apply_look(Armour.look_of(record, worn_equipment(), ancestry) if show_armour \
			else Appearance.to_look(record, ancestry))
	_show_values()


## B5: the giant's equipment at a shrine when it wears a piece of armour, else {}.
func worn_equipment() -> Dictionary:
	if context != "shrine" or typeof(GameSession.expansion) != TYPE_DICTIONARY:
		return {}
	var eq: Variant = GameSession.expansion.get("equipment", {})
	if typeof(eq) != TYPE_DICTIONARY or Armour.worn(eq).is_empty():
		return {}
	return eq


## B5: the Armour toggle - the worn armour drawn over the preview, or not.
func set_show_armour(on: bool) -> void:
	show_armour = on and not worn_equipment().is_empty()
	if armour_button != null:
		UiKit.set_tab_open(armour_button, show_armour)
	_apply()


func _show_values() -> void:
	if _category == "Colours" and OptionRows.dye_signature(record) != _colours_signature and _category_boxes.has("Colours"):
		_rebuild_colours()
		return
	if grid_open():
		grid.show_selected(str(OptionRows.value_of(record, _grid_row.key)))
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


## Opens a category: its rows, its framing, the focus on its first row (an open grid closes). M10's names
## ("Skin", "Eyes") open the category that has their rows now (OptionRows.CATEGORY_ALIASES).
func show_category(category: String) -> void:
	category = str(OptionRows.CATEGORY_ALIASES.get(category, category))
	if not category in OptionRows.CATEGORIES:
		category = OptionRows.CATEGORIES[0]
	if grid_open():
		_close_grid_quietly()
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


## LB / RB, PageUp / PageDown: the previous (-1) or next (+1) category, wrapping (an open grid closes).
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


## Picks `value` on the row `key`, as the player would (tests, the sheet tool): on the open category's row, else
## on the category that has it (opened first). M10's paths (outfit.primary, paint.design) still work.
func pick(key: String, value: Variant) -> bool:
	var r := row(key)
	if r == null:
		var category := OptionRows.category_of_key(key)
		if category != "" and category != _category:
			show_category(category)
			r = row(key)
	if r == null and (OptionRows.LEGACY_KEYS.has(key) or key == OptionRows.PAINT_ROW):
		return set_record(OptionRows.with_value(record, key, value))
	if r == null:
		return false
	return _on_picked(r, value)


## The open category's rows: built the first time it opens, kept (hidden) while another is open.
func _build_rows() -> void:
	_focused_row = null
	for c: String in _category_boxes:
		(_category_boxes[c] as Control).visible = c == _category
	if _category == "Colours" and _category_boxes.has("Colours") and OptionRows.dye_signature(record) != _colours_signature:
		var old := _category_boxes["Colours"] as Control
		_category_boxes.erase("Colours")
		_category_rows.erase("Colours")
		old.queue_free()
	if not _category_boxes.has(_category):
		var box := VBoxContainer.new()
		box.name = "Rows_" + _category.replace(" ", "_")
		box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		box.add_theme_constant_override("separation", 8 if _category in ["Clothing", "Accessories", "Tattoos"] else 12)
		var built: Array = []
		for r: OptionRows.Row in OptionRows.build_rows(_category, ancestry, record):
			box.add_child(r)
			r.picked.connect(_on_picked)
			r.focused.connect(_on_row_focused)
			if r is OptionRows.GridRow:
				(r as OptionRows.GridRow).open_requested.connect(open_grid)
			built.append(r)
		if _category == "Colours":
			_colours_signature = OptionRows.dye_signature(record)
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


## The Colours category's rows follow the worn garments (a slot's own dye for each that takes one): rebuilt when
## they change while it is open.
func _rebuild_colours() -> void:
	_build_rows()
	if is_inside_tree():
		refresh_focus()


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
			if changed and r.key.begins_with("build."):
				_set_status("%s: %s." % [str(r.spec.get("label", "")), (r as OptionRows.SliderRow).value_label.text.to_lower()])
			return changed
		"preset":
			changed = set_record(OptionRows.with_value(record, r.key, value))
			if changed:
				_set_status("Preset: %s." % str(r.spec.get("label", "")))
		_:
			changed = set_record(OptionRows.with_value(record, r.key, value))
	if r.key == OptionRows.PAINT_ROW or OptionRows.PAINT_ROWS.has(r.key) or r.key.begins_with("tattoos.") \
			or r.key.begins_with("scar."):
		_frame_for(r)
	return changed


func _on_row_focused(r: OptionRows.Row) -> void:
	_focused_row = r
	if r is OptionRows.PresetRow and _preset_note != null:
		_preset_note.text = (r as OptionRows.PresetRow).description
	_frame_for(r)
	_update_fade()


## The category's framing; for Tattoos, Scars and War paint the region of the focused (or first) design row, for
## a build slider the stage-1 rear Game view, for an open grid its row's framing. A framing already shown is
## left as it is (the user's turn and zoom stay).
func _frame_for(r: OptionRows.Row) -> void:
	if preview == null or preview.view != "":
		return
	var want := category_framing(_category, r)
	if want != preview.framing:
		preview.frame(want)


## The preview framing of a category (and its focused row): see the class notes.
func category_framing(category: String, r: OptionRows.Row = null) -> String:
	category = str(OptionRows.CATEGORY_ALIASES.get(category, category))
	if r != null and r.spec.has("framing") and (r is OptionRows.SliderRow or (grid_open() and r == _grid_row)):
		return str(r.spec.framing)
	match category:
		"Hair":
			return "hair"
		"Beard", "Face":
			return "face"
		"Tattoos", "Scars", "War paint":
			var spec: Dictionary = r.spec if r != null else (_rows[0].spec if not _rows.is_empty() else {})
			var region := OptionRows.row_region(spec, record, preview.index(), ancestry)
			if region == "":
				return "face"
			return GiantPreview.region_framing(region, OptionRows.row_side(spec, record, preview.index(), ancestry))
	return "full"


## The covering garments fade while a "Hidden by your clothing" row has the focus.
func _update_fade() -> void:
	if preview == null:
		return
	var hidden := _focused_row != null and is_instance_valid(_focused_row) and _focused_row.note_text() == OptionRows.HIDDEN_NOTE
	var want := 0.7 if hidden else 0.0
	if not is_equal_approx(preview.fade(), want):
		preview.set_fade(want)


# --------------------------------------------------------------------------- the option grid (P55)

## True while an option grid is open (in the options panel, in place of the rows).
func grid_open() -> bool:
	return grid != null and grid.is_open()


## The row whose grid is open (null when none).
func grid_row() -> OptionRows.GridRow:
	return _grid_row if grid_open() else null


## Opens the option grid of a grid row of the open category (A, Enter or a click on the row): its page with the
## record's value, the focus on that cell, the preview at the row's framing; the page's thumbnails are asked for.
func open_grid(r: OptionRows.GridRow) -> void:
	if r == null or not _rows.has(r) or question_open():
		return
	_ensure_grid()
	_grid_row = r
	_grid_session += 1
	_merge_key = ""
	_scroll.visible = false
	grid.fit_cells(_grid_room())
	grid.open(r, str(OptionRows.value_of(record, r.key)))
	_category_label.text = "%s  >  %s" % [_category, str(r.spec.get("label", r.key))]
	_focused_row = r
	_frame_for(r)
	_update_fade()
	if is_inside_tree():
		refresh_focus()
		var f := first_focus()
		if UiNav.focusable(f):
			f.grab_focus()


## Closes the open grid (Done, B, Esc, A on a cell): the rows again, the focus back on the grid's row.
func close_grid() -> void:
	if not grid_open():
		return
	var r := _grid_row
	_close_grid_quietly()
	_show_values()
	_frame_for(r)
	if is_inside_tree():
		refresh_focus()
		if r != null and UiNav.focusable(r.button):
			r.button.grab_focus()


## The option grid is made on the first grid row opened, never while the screen opens (its first frame draws no
## more than M10's did: creator_check.mjs's GL counts).
func _ensure_grid() -> void:
	if grid != null:
		return
	grid = OptionGrid.new()
	grid.chosen.connect(_on_grid_chosen)
	grid.close_requested.connect(close_grid)
	grid.page_shown.connect(_on_grid_page)
	_scroll.get_parent().add_child(grid)
	_scroll.get_parent().move_child(grid, _scroll.get_index() + 1)


func _close_grid_quietly() -> void:
	if grid != null:
		grid.close()
	thumbnails.request([])
	_thumbs_wanted = {}
	_grid_row = null
	_merge_key = ""
	_scroll.visible = true
	if _category_label != null:
		_category_label.text = _category


## The grid's cell size: the options panel's room under its label (4 x 3 cells and the filters, name and pager).
func _grid_room() -> Vector2:
	var panel := _scroll.get_parent().get_parent() as Control
	var w := panel.size.x - 24.0 if panel != null and panel.size.x > 0.0 else 480.0
	var h := panel.size.y - 30.0 - 30.0 - 22.0 - 34.0 - 22.0 - 6.0 * 6.0 if panel != null and panel.size.y > 0.0 else 330.0
	return Vector2(w, h)


## A cell was chosen (moving the focus onto it, a click, A): the change, one undo step for the grid's browsing.
func _on_grid_chosen(id: String, close_after: bool) -> void:
	var r := _grid_row
	if r == null:
		return
	var changed := set_record(OptionRows.with_value(record, r.key, id), "grid:%d" % _grid_session)
	r.show_value(OptionRows.value_of(record, r.key))
	if changed:
		_set_status("%s: %s." % [str(r.spec.get("label", "")), r.value_name()])
	if close_after:
		close_grid()


## The page shown changed: its thumbnails (cached ones at once, the rest one a frame).
func _on_grid_page(ids: Array) -> void:
	if not grid_open():
		return
	if is_inside_tree():
		refresh_focus()   # the cells shown changed: the focus neighbours with them
	# P57: the pictures at the cells' own size in window pixels (a 1920x1080 window draws a cell about 210 px wide)
	var k := get_viewport().get_final_transform().get_scale().x if is_inside_tree() else 1.0
	thumbnails.set_cell_pixels((grid.cell_px() - 8) * absf(k))
	var items: Array = []
	_thumbs_wanted = {}
	for id: String in ids:
		var item := thumb_item(_grid_row.spec, id)
		if not item.is_empty():
			items.append(item)
			_thumbs_wanted[thumbnails.key_of(item)] = id
	thumbnails.request(items)


## Gate B: only a picture the page shown asked for (its option id and key); one still in flight for another grid
## (the hair's beads when the beard's open) or for other dyes is dropped.
func _on_thumbnail(id: String, tex: Texture2D, key: String) -> void:
	if grid_open() and str(_thumbs_wanted.get(key, "")) == id:
		grid.set_thumbnail(id, tex)


## What a thumbnail of option `id` of a grid row shows, and its cache key (plan M11 §2.7: by option id, skin tone
## and dyes): a garment, an accessory or an outfit on the giant as built (the record's skin, hair and dyes, nothing
## else worn), in the slot's framing (P57: an accessory aimed at its own mesh, an outfit head to knees); a hair or
## beard style in the record's colour; a design (a tattoo, a war paint) alone on the giant in the record's ink or
## paint colour, at its region's framing from its side (P57; no beard over a face design). {} for "None".
func thumb_item(spec: Dictionary, id: String) -> Dictionary:
	if id == "" or id == Appearance.BEAD_NONE or Appearance.option(id).is_empty():
		return {}
	var set_name := str(spec.get("set", ""))
	var dyes: Dictionary = record.outfit.dyes
	var dye_key := "%s|%s|%s" % [dyes.get("cloth", ""), dyes.get("leather", ""), dyes.get("metal", "")]
	var skin_id := str(record.skin)
	var base := Appearance.default_record()
	base["skin"] = record.skin
	base["hair"] = (record.hair as Dictionary).duplicate(true)
	base["beard"] = (record.beard as Dictionary).duplicate(true)
	base["tattoos"] = (record.tattoos as Dictionary).duplicate(true)
	base["paint"] = (record.paint as Dictionary).duplicate(true)
	var outfit: Dictionary = (base.outfit as Dictionary).duplicate(true)
	outfit["set"] = ""
	outfit["slots"] = Appearance.empty_slots()
	outfit["accessories"] = {"neck": "", "arm_ring": "", "belt": ""}
	outfit["dyes"] = dyes.duplicate(true)
	base["outfit"] = outfit
	var key := "%s|%s|%s" % [id, skin_id, dye_key]
	var framing := str(spec.get("thumb", spec.get("framing", "full")))
	var aim: Array = []
	match set_name:
		"tattoo", "paint":
			# P57: a design on the giant, alone, at its region's framing from its side (the flat picture of its layer
			# showed the other designs of its channel and every island of the UV map); no beard over a face design
			var design := str(Appearance.option(id).get("design", ""))
			if not (preview.index().get("designs", {}) as Dictionary).has(design):
				return {}
			for k: String in OptionRows.TATTOO_ROWS:
				base = OptionRows.with_value(base, k, "")
			for k: String in OptionRows.PAINT_ROWS:
				base = OptionRows.with_value(base, k, "")
			base = OptionRows.with_value(base, str(spec.key), id)
			var region := OptionRows.row_region(spec, base, preview.index(), ancestry)
			if region == "face":
				base.beard["style"] = "beard.none"
			framing = GiantPreview.region_framing(region, OptionRows.design_side(design, preview.index()))
			var colour_id := str(record.tattoos.ink) if set_name == "tattoo" else str(record.paint.color)
			key = "%s|%s|%s|%s" % [id, skin_id, colour_id, base.beard.style]
		"garment":
			base.outfit.slots[str(spec.slot)] = {"item": id, "dye": ""}
			# Gate B: a garment's picture by the one dye it is drawn in (its material's, or its own), not all three
			key = "%s|%s|%s" % [id, skin_id, Appearance.slot_dye_id(base.outfit.slots[str(spec.slot)], dyes)]
		"accessory":
			base.outfit.accessories[str(spec.slot)] = id
			aim = [str(Appearance.option(id).get("mesh", ""))]
		"outfit":
			base = Appearance.with_outfit(base, id)
		"hair", "beard":
			base[set_name]["style"] = id
			key = "%s|%s|%s|%s" % [id, skin_id, base[set_name].color, base.hair.color]
		"bead":
			var part := "hair" if str(spec.key).begins_with("hair") else "beard"
			base[part]["beads"] = id
			key = "%s|%s|%s|%s" % [id, skin_id, base[part].style, base.hair.color]
	return {"id": id, "key": key, "kind": "render", "look": Appearance.to_look(base, ancestry), "framing": framing, "aim": aim}


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
	# P57: the right stick's up and down zoom (the triggers turn a grid's pages and jump rows: _trigger_page)
	var ry := float(_axes.get(JOY_AXIS_RIGHT_Y, 0.0))
	if absf(ry) > AXIS_DEADZONE:
		preview.zoom(-ry * TRIGGER_ZOOM_S * delta)


func _input(event: InputEvent) -> void:
	if not _on_top():
		return
	var motion := event as InputEventJoypadMotion
	if motion != null:
		if motion.axis in [JOY_AXIS_RIGHT_X, JOY_AXIS_RIGHT_Y, JOY_AXIS_TRIGGER_LEFT, JOY_AXIS_TRIGGER_RIGHT]:
			_axes[motion.axis] = motion.axis_value
		if motion.axis in [JOY_AXIS_TRIGGER_LEFT, JOY_AXIS_TRIGGER_RIGHT] and not question_open():
			_trigger_page(motion)
		return
	if question_open():
		return
	if _handle_key(event as InputEventKey) or _handle_pad(event as InputEventJoypadButton):
		# The root scene's _input (scripts/main.gd), which notes the device for the footer's hint and the
		# prompts, runs after this one and never sees an event consumed here (M10 gate, LA-4).
		InputBindings.note_device(event)
		get_viewport().set_input_as_handled()


## LT / RT: while a grid is open one page per pull, else (P57) ROW_JUMP rows up or down (the trigger must fall back
## before it counts again).
func _trigger_page(motion: InputEventJoypadMotion) -> void:
	var held := bool(_triggers.get(motion.axis, false))
	if not held and motion.axis_value > GRID_TRIGGER_PRESS:
		_triggers[motion.axis] = true
		if grid_open():
			grid.step_page(-1 if motion.axis == JOY_AXIS_TRIGGER_LEFT else 1)
		else:
			jump_rows(-1 if motion.axis == JOY_AXIS_TRIGGER_LEFT else 1)
		InputBindings.note_device(motion)
		get_viewport().set_input_as_handled()
	elif held and motion.axis_value < GRID_TRIGGER_RELEASE:
		_triggers[motion.axis] = false


## P57: the focus ROW_JUMP rows down (+1) or up (-1) along the screen's focus rows, wrapping; the control at the same
## place in the row (its last when the row is shorter). Returns the control that has the focus.
func jump_rows(dir: int) -> Control:
	var rows := UiNav.link_rows(focus_rows())
	var owner := get_viewport().gui_get_focus_owner() if is_inside_tree() else null
	for ri in rows.size():
		var at := (rows[ri] as Array).find(owner)
		if at < 0:
			continue
		var target: Array = rows[(ri + dir * ROW_JUMP + rows.size() * ROW_JUMP) % rows.size()]
		var c: Control = target[mini(at, target.size() - 1)]
		c.grab_focus()
		return c
	return owner


## P57: a grid's cell lines wrap up and down among themselves (the filters and the pager stay a press away from the
## tabs and the actions, and on X, F, "/", LT, RT and the keys), so any cell is at most three D-pad presses away.
func focus_linked() -> void:
	if grid_open():
		grid.wrap_cell_lines()


## The name filter's box takes the keys (Godot's LineEdit edits once asked to when the focus comes from code).
func _edit_filter() -> void:
	grid.filter_box.grab_focus()
	if grid.filter_box.has_method("edit"):
		grid.filter_box.call("edit")


## The keyboard while a grid is open (P55): pages, the material filter, the name filter. True when consumed.
func _handle_grid_key(k: InputEventKey) -> bool:
	var typing := grid.filter_box.has_focus()
	match k.keycode:
		KEY_PAGEUP:
			grid.step_page(-1)
			return true
		KEY_PAGEDOWN:
			grid.step_page(1)
			return true
	if typing:
		if k.keycode in [KEY_DOWN, KEY_ENTER, KEY_KP_ENTER] and not k.echo:
			var cell := grid.landing_cell() if grid.cell_of(grid.selected) != null else (grid.cells[0] as Button)
			if UiNav.focusable(cell):
				cell.grab_focus()
			return true
		return false   # letters, Backspace and the arrows edit the box
	if k.keycode == KEY_F and not k.echo:
		grid.cycle_material()
		return true
	if k.keycode == KEY_SLASH:
		_edit_filter()
		return true
	if k.keycode == KEY_BACKSPACE:
		if grid.query != "":
			grid.set_query(grid.query.left(-1))
		return true
	if k.keycode in [KEY_Q, KEY_E, KEY_R, KEY_V]:
		return false   # the creator's own keys
	var ch := char(k.unicode) if k.unicode >= 32 else ""
	if ch != "" and (ch.to_lower() != ch.to_upper() or ch.is_valid_int() or ch == " "):
		# Gate B: the first letter typed puts the focus in the box, so the rest of the name types there (Q, E, R, V
		# and F mid-word turned the preview, randomized the category and cycled the material filter)
		_edit_filter()
		grid.set_query(grid.query + ch)
		return true
	return false


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
	if grid_open() and _handle_grid_key(k):
		return true
	if grid_open() and grid.filter_box.has_focus():
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
			if grid_open() and grid.materials().size() > 1:
				grid.cycle_material()
			else:
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
	preview.window_pixels = true   # fills the holder at the window's resolution (GiantPreview.fit_window_pixels)
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
	if not worn_equipment().is_empty():
		armour_button = UiKit.button("Armour", 14)
		armour_button.name = "ArmourToggle"
		armour_button.focus_mode = Control.FOCUS_NONE   # mouse only, as the views
		armour_button.tooltip_text = "Show the armour the giant wears over its clothes"
		armour_button.pressed.connect(func() -> void: set_show_armour(not show_armour))
		views.add_child(armour_button)
		UiKit.set_tab_open(armour_button, false)
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
	thumbnails = ThumbnailCache.new()
	thumbnails.thumbnail_ready.connect(_on_thumbnail)
	add_child(thumbnails)
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
