class_name TitleScreen
extends UiScreen
## The title screen (plan §2.9, §3.6, decision 15): New Game, Continue, Sandbox, Settings,
## Controls and Quit (Quit is hidden on the web, where the browser closes the tab). It is what
## main.tscn shows without --mode (the play link); --autoplay and --scenario boot the sandbox.
##
## New Game and Continue need the Valley: while level.valley does not exist (until P10b) both
## are disabled with the note "Valley not built yet" (a --level=... scene stands in for it).
## Continue is enabled when SaveSlots.read() loads a save whose level exists, and the note shows
## what the read reported (a recovery from the backup, a newer-version file kept aside, dropped
## ids). New Game asks once more before it replaces a saved game. The buttons emit
## Events.mode_change_requested; GameSession changes the mode (a scene reload) and reports
## failures in last_mode_result, shown here. On the web the click that starts a mode also
## captures the mouse (browsers grant pointer lock only inside a click).
##
## The screen does not pause the game (nothing runs under it) and never closes on Esc / pad B:
## cancel() only leaves the Settings or Controls page.
##
## Pad and keyboard (P16; the play link opens here): the menu is one column and a page is Back
## followed by its rows (focus_rows), wrapping at both ends; the first focus is Continue, New Game
## or Sandbox on the menu and Back on a page. Disabled entries are skipped.
##
## P20 (plan M6-M9 §2.6): the save line names the checkpoint by its display name from the level's
## world index ("Saved game: level 3, stage 2, at the Grove Shrine, ..."), never by its id. When
## the saved game has finished the prologue (slice.completed) and the world exists, New Game asks
## "Play the prologue" (the default) or "Skip to the Old Kingdom" (a New Game from world_start in
## level.world); either replaces the saved game. Without the world the choice is hidden.
##
## M10 (P44, plan M10 §2.10): every New Game passes through the character creator. After the confirm and the
## prologue or skip choice, New Game opens the creator (ScreenStack SCREENS["creator"], {"context": "new_game",
## "start": {"mode", "options"}}) over the title; its Begin closes it with the record and the title starts the
## game at once with options + {"appearance": record} - in the same call stack as the click (start_game: the
## pointer lock is granted inside it). Back leaves the title as it was (the confirm, the skip choice) and the
## save untouched. GameSession.creator_start (the launcher's --mode=world --creator) opens the creator as soon
## as the title opens. The warm-up: with a display, a hidden 64x64 SubViewport (GiantPreview.WarmUp) draws the
## giant's materials under the preview's and a level's lighting before New Game and Continue enable
## ("Preparing...", at most WARMUP_LIMIT_S); without a display (headless tests) there is none and the buttons
## are enabled at once. The warm-up is freed when a game starts (start_game) or with the title.

const VALLEY_MISSING := "Valley not built yet"
const PAGES := ["Settings", "Controls"]
const PLAY_PROLOGUE := "Play the prologue"
const SKIP_PROLOGUE := "Skip to the Old Kingdom"
const SKIP_NOTE := "Starting over replaces your saved game. You finished the prologue: begin it again, or start in the Old Kingdom."
## M10 (P44): the creator's screen name, the warm-up's note and its time limit.
const CREATOR := "creator"
const PREPARING := "Preparing..."
const WARMUP_LIMIT_S := 6.0

## M10 (P44): tests run the warm-up without a display (it counts frames then). Reset it after use.
static var force_warmup := false

var _new_game: Button
var _prologue: Button
var _skip: Button
var _continue: Button
var _sandbox: Button
var _settings_button: Button
var _controls_button: Button
var _quit: Button
var _menu: VBoxContainer
var _page_box: VBoxContainer
var _back: Button
var _pages: Dictionary = {}
var _note: Label
var _save_label: Label
var _confirm_new := false
var _save: Dictionary = {}
var _settings_pages := SettingsPages.new()
var _valley_ok := false
var _continue_ok := false
## M10 (P44): the warm-up viewport (null when there is none), when it gives up, the creator open over the
## title and the button that opened it (the focus goes back there after Back).
var _warmup: SubViewport = null
var _warm_until_ms := 0
var _warm_pending := false
var _creator: UiScreen = null
var _creator_from: Control = null


func _ready() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.05, 0.06, 0.08, 1.0)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	var panel := UiKit.panel(Color(0.08, 0.09, 0.11, 0.97))
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	panel.offset_left = -380
	panel.offset_right = 380
	panel.offset_top = -320
	panel.offset_bottom = 320
	add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	panel.add_child(v)
	var title := UiKit.label("GIANTBORN", 44)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(title)
	var subtitle := UiKit.label("Age of Titans", 20, UiKit.MUTED)
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(subtitle)
	_menu = VBoxContainer.new()
	_menu.add_theme_constant_override("separation", 10)
	_menu.alignment = BoxContainer.ALIGNMENT_CENTER
	_menu.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(_menu)
	_new_game = _menu_button("New Game", _on_new_game)
	# P20: the skip-prologue choice, shown under New Game when it is pressed with a finished save.
	_prologue = _menu_button(PLAY_PROLOGUE, _on_play_prologue)
	_skip = _menu_button(SKIP_PROLOGUE, _on_skip_prologue)
	_prologue.visible = false
	_skip.visible = false
	_continue = _menu_button("Continue", _on_continue)
	_sandbox = _menu_button("Sandbox", _on_sandbox)
	_settings_button = _menu_button("Settings", _show_page.bind("Settings"))
	_controls_button = _menu_button("Controls", _show_page.bind("Controls"))
	_quit = _menu_button("Quit", _on_quit)
	_quit.visible = not OS.has_feature("web")
	_page_box = VBoxContainer.new()
	_page_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_page_box.visible = false
	v.add_child(_page_box)
	_back = UiKit.button("Back", 16)
	_back.pressed.connect(_show_page.bind(""))
	_page_box.add_child(_back)
	_pages["Settings"] = _settings_pages.build_settings()
	_pages["Controls"] = _settings_pages.build_controls()
	for page: Control in _pages.values():
		page.visible = false
		page.size_flags_vertical = Control.SIZE_EXPAND_FILL
		_page_box.add_child(page)
	_note = UiKit.label("", 15, UiKit.WARN)
	_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(_note)
	_save_label = UiKit.label("", 13, UiKit.MUTED)
	_save_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_save_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(_save_label)
	var info := UiKit.label("Prototype %s  -  Godot %s" % [
		ProjectSettings.get_setting("application/config/version"), Engine.get_version_info().string], 12, UiKit.MUTED)
	info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(info)
	_start_warmup()
	if stack == null:
		refresh()   # inside a stack, on_open() refreshes


func _menu_button(text: String, handler: Callable) -> Button:
	var b := UiKit.button(text, 22)
	b.custom_minimum_size = Vector2(320, 0)
	b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	b.pressed.connect(handler)
	_menu.add_child(b)
	return b


# --------------------------------------------------------------------------- UiScreen

func pauses_game() -> bool:
	return false


## Continue when it is available, else New Game, else Sandbox; Back on a page.
func first_focus() -> Control:
	if current_page() != "":
		return _back
	for b: Button in [_continue, _new_game, _sandbox]:
		if b != null and not b.disabled and b.visible:
			return b
	return _sandbox


## The menu column, or Back and the page's rows (P16).
func focus_rows() -> Array:
	match current_page():
		"Settings":
			return [[_back]] + _settings_pages.settings_rows()
		"Controls":
			return [[_back]] + _settings_pages.controls_rows()
	var rows: Array = []
	for b: Button in [_new_game, _prologue, _skip, _continue, _sandbox, _settings_button, _controls_button, _quit]:
		if b == _prologue or b == _skip:
			if not b.visible:
				continue
		rows.append([b])
	return rows


func on_open() -> void:
	refresh()
	# M10 (P44): the launcher's world start (--mode=world --creator) opens the creator at once.
	if not GameSession.creator_start.is_empty():
		var cs: Dictionary = GameSession.creator_start
		GameSession.creator_start = {}
		_open_creator.call_deferred(str(cs.get("mode", "valley")),
			cs.get("options", {}) if typeof(cs.get("options")) == TYPE_DICTIONARY else {})


## Esc / pad B leave the Settings or Controls page; the title itself never closes.
func cancel() -> void:
	if current_page() != "":
		_show_page("")


func on_close() -> void:
	_settings_pages.cancel_capture()
	Settings.flush()


# --------------------------------------------------------------------------- state

## Re-reads what can start: the Valley (or the --level scene) and the save slot.
func refresh() -> void:
	if _new_game == null:
		return
	_confirm_new = false
	_new_game.text = "New Game"
	_prologue.visible = false
	_skip.visible = false
	var valley := GameSession.valley_available()
	_save = {}
	var save_text := ""
	var can_continue := false
	if not GameSession.persist:
		save_text = "Saving is off for this run (--no-user-settings)."
	elif SaveSlots.exists():
		_save = SaveSlots.read()
		if _save.ok:
			can_continue = GameSession.save_level_available(_save.data)
			save_text = describe_save(_save.data)
			if not can_continue:
				save_text += "  (its level is not in this build)"
		if str(_save.message) != "":
			save_text = (save_text + "\n" if save_text != "" else "") + str(_save.message)
	else:
		save_text = "No saved game yet."
	_valley_ok = valley
	_continue_ok = can_continue
	_note.text = "" if valley else VALLEY_MISSING
	_update_buttons()
	_save_label.text = save_text
	if is_inside_tree():
		refresh_focus()


## New Game and Continue: enabled when they can start and the warm-up is done (M10, P44); "Preparing..." meanwhile.
func _update_buttons() -> void:
	var warm := warming()
	_new_game.disabled = not _valley_ok or warm
	_continue.disabled = not _continue_ok or warm
	if warm:
		_note.text = PREPARING
	elif _note.text == PREPARING:
		_note.text = "" if _valley_ok else VALLEY_MISSING


## A short line about a save document: "Saved game: level 3, stage 2, at the Grove Shrine,
## 2026-11-05 14:02" (P20: the checkpoint's display name from its level's world index; a
## checkpoint the index does not name is left out - never its id - and a level other than the
## Valley is named: "in the Old Kingdom"). M8 release (R2): the place is where Continue wakes the
## giant (GameSession.save_respawn: the saved respawn unless a respawn blocker refuses it - hostile
## guards there - and then the stone the load moves it to), not the saved respawn as such.
## P39f (FOLLOWUPS: "the saved-game line writes 'in The Old Kingdom'"): a name that begins with "The" takes
## a small "the" mid-sentence (mid_sentence), as the warning above and the menu button write it: "in the Old
## Kingdom", "at the Kings' Door" (it read "in The Old Kingdom" and "at The Kings' Door").
static func describe_save(doc: Dictionary) -> String:
	var c: Dictionary = doc.get("character", {})
	var parts := PackedStringArray(["level %d" % int(c.get("level", 1)), "stage %d" % int(c.get("growth_stage", 1))])
	var lv := str(doc.get("level", GameSession.VALLEY_LEVEL_ID))
	var place := WorldIndex.display_name_in(lv, GameSession.save_respawn(doc))
	if place != "":
		parts.append("at %s" % mid_sentence(place))
	if lv != GameSession.VALLEY_LEVEL_ID:
		var level_name := str(GameData.get_record(lv).get("display_name", ""))
		if level_name != "":
			parts.append("in %s" % mid_sentence(level_name))
	var when := int(doc.get("saved_at_unix", 0))
	if when > 0:
		var local := when + int(Time.get_time_zone_from_system().get("bias", 0)) * 60
		parts.append(Time.get_datetime_string_from_unix_time(local, true).substr(0, 16))
	return "Saved game: " + ", ".join(parts)


## P39f: a place or level name as it reads after "at" or "in": "The Old Kingdom" -> "the Old Kingdom", and a
## name without an article takes one - "Grove Shrine" -> "the Grove Shrine".
static func mid_sentence(display_name: String) -> String:
	return TextUtil.with_the(display_name)


## True when New Game offers the skip-prologue choice (P20): the saved game finished the prologue
## (slice.completed, or its progress says so) and the world exists.
func skip_available() -> bool:
	if not bool(_save.get("ok", false)) or not GameSession.world_available():
		return false
	return save_finished_prologue(_save.get("data", {}))


## True for a save document whose prologue is complete (the flag slice.completed, or progress).
static func save_finished_prologue(doc: Dictionary) -> bool:
	var prog: Variant = doc.get("progress")
	if typeof(prog) == TYPE_DICTIONARY and bool(prog.get("prologue_complete", false)):
		return true
	var world: Variant = doc.get("world")
	if typeof(world) == TYPE_DICTIONARY and typeof(world.get("flags")) == TYPE_DICTIONARY:
		return QuestConditions.truthy((world.flags as Dictionary).get("slice.completed"))
	return false


## What the screen shows now (tests): {"new_game", "continue", "sandbox", "quit"} enabled flags,
## "note", "save", "page" and (P20) "skip_choice" (the two prologue buttons are shown).
func state() -> Dictionary:
	return {"new_game": not _new_game.disabled, "continue": not _continue.disabled,
		"sandbox": not _sandbox.disabled, "quit": _quit.visible, "note": _note.text,
		"save": _save_label.text, "page": current_page(), "skip_choice": _skip.visible}


## The button of a menu entry ("New Game", "Continue", "Sandbox", "Quit", and P20's "Play the
## prologue" and "Skip to the Old Kingdom"), or null.
func button(label: String) -> Button:
	match label:
		"New Game":
			return _new_game
		PLAY_PROLOGUE:
			return _prologue
		SKIP_PROLOGUE:
			return _skip
		"Continue":
			return _continue
		"Sandbox":
			return _sandbox
		"Quit":
			return _quit
	return null


## "" on the main menu, else "Settings" or "Controls".
func current_page() -> String:
	for key: String in _pages:
		if (_pages[key] as Control).visible:
			return key
	return ""


func settings_pages() -> SettingsPages:
	return _settings_pages


## Shows a page ("Settings", "Controls") or the menu (""). Leaving a page puts the focus back on
## its menu entry; opening one focuses Back.
func show_page(page_name: String) -> void:
	_show_page(page_name)


func _show_page(page_name: String) -> void:
	var left := current_page()
	_settings_pages.cancel_capture()
	for key: String in _pages:
		(_pages[key] as Control).visible = key == page_name
	_menu.visible = page_name == ""
	_page_box.visible = page_name != ""
	if page_name == "Controls":
		_settings_pages.refresh_bindings()
	if not is_inside_tree():
		return
	refresh_focus()
	var f: Control = first_focus() if page_name == "" else _back
	if page_name == "" and left != "":
		f = _settings_button if left == "Settings" else _controls_button
	if UiNav.focusable(f):
		f.grab_focus()


func _process(_delta: float) -> void:
	_settings_pages.update_capture()
	if _warm_pending and not warming():
		_warm_pending = false
		_update_buttons()
		if is_inside_tree() and stack != null and is_instance_valid(stack) and stack.top() == self:
			refresh_focus()
			var f := first_focus()
			if UiNav.focusable(f):
				f.grab_focus()


# --------------------------------------------------------------------------- the warm-up (M10, P44)

## With a display (or force_warmup), the hidden viewport that compiles the giant's shaders before New Game.
func _start_warmup() -> void:
	if not force_warmup and DisplayServer.get_name() == "headless":
		return
	_warmup = GiantPreview.WarmUp.new()
	add_child(_warmup)
	_warm_until_ms = Time.get_ticks_msec() + int(WARMUP_LIMIT_S * 1000.0)
	_warm_pending = true


## True while the warm-up holds New Game and Continue: its frames are not drawn yet and its time is not up.
func warming() -> bool:
	if _warmup == null or not is_instance_valid(_warmup) or _warmup.is_queued_for_deletion():
		return false
	return not bool(_warmup.get("done")) and Time.get_ticks_msec() < _warm_until_ms


## The warm-up viewport (null when there is none or it was freed).
func warmup_viewport() -> SubViewport:
	return _warmup if _warmup != null and is_instance_valid(_warmup) and not _warmup.is_queued_for_deletion() else null


func _free_warmup() -> void:
	if _warmup != null and is_instance_valid(_warmup):
		_warmup.queue_free()
	_warmup = null
	_warm_pending = false


# --------------------------------------------------------------------------- actions

func _on_new_game() -> void:
	if _new_game.disabled:
		return
	# P20: a finished prologue offers to skip it (each choice replaces the saved game).
	if skip_available():
		if not _skip.visible:
			_prologue.visible = true
			_skip.visible = true
			_note.text = SKIP_NOTE
			if is_inside_tree():
				refresh_focus()
				if UiNav.focusable(_prologue):
					_prologue.grab_focus()
		return
	if _save.get("ok", false) and not _confirm_new:
		_confirm_new = true
		_new_game.text = "New Game: replace the saved game?"
		_note.text = "Press New Game again to start over. Your saved game will be replaced."
		return
	_open_creator("valley", {"new_game": true})


## "Play the prologue" (P20): a New Game in the Valley, replacing the saved game (M10: through the creator).
func _on_play_prologue() -> void:
	if _prologue.visible:
		_open_creator("valley", {"new_game": true})


## "Skip to the Old Kingdom" (P20): a New Game in the world from world_start (M10: through the creator).
func _on_skip_prologue() -> void:
	if _skip.visible:
		_open_creator("world", {"new_game": true})


func _on_continue() -> void:
	if not _continue.disabled:
		start_game("valley", {"continue": true})


func _on_sandbox() -> void:
	start_game("sandbox", {})


## M10 (P44): the creator for a New Game of `mode_name` (its Begin starts it; Back leaves the title as it was).
## Without a screen stack (or a creator) the game starts at once, as before M10. Returns the creator.
func _open_creator(mode_name: String, options: Dictionary) -> UiScreen:
	if stack == null or not is_instance_valid(stack) or _creator != null:
		if _creator == null:
			start_game(mode_name, options)
		return _creator
	_creator_from = UiNav.focus_owner(self)
	_creator = stack.open(CREATOR, {"context": "new_game", "start": {"mode": mode_name, "options": options.duplicate(true)}})
	if _creator == null:
		start_game(mode_name, options)
		return null
	_creator.closed.connect(_on_creator_closed.bind(mode_name, options.duplicate(true)))
	return _creator


## The creator closed: Begin starts the game with its record in this same call stack; Back keeps the title.
func _on_creator_closed(result: Dictionary, mode_name: String, options: Dictionary) -> void:
	_creator = null
	if bool(result.get("begin", false)) and typeof(result.get("appearance")) == TYPE_DICTIONARY:
		var o := options.duplicate(true)
		o["appearance"] = (result.appearance as Dictionary).duplicate(true)
		start_game(mode_name, o)
		return
	if UiNav.focusable(_creator_from):
		_creator_from.grab_focus.call_deferred()


## The creator open over the title (null when none).
func creator() -> UiScreen:
	return _creator if _creator != null and is_instance_valid(_creator) else null


func _on_quit() -> void:
	Settings.flush()
	get_tree().quit()


## Starts a mode (Events.mode_change_requested), capturing the mouse on the web inside the click that called
## it. M10 (P44): public, so the creator's Begin starts the game in its own pressed handler; it frees the warm-up.
func start_game(mode_name: String, options: Dictionary) -> void:
	_free_warmup()
	var web := OS.has_feature("web")
	if web:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED   # pointer lock is granted inside this click
	GameSession.last_mode_result = {}
	Events.mode_change_requested.emit(mode_name, options)
	var r: Dictionary = GameSession.last_mode_result
	if not r.get("ok", false):
		if web:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		refresh()
		_note.text = str(r.get("message", "Could not start"))


func _input(event: InputEvent) -> void:
	if not is_open() or not _settings_pages.is_capturing():
		return
	if _settings_pages.handle_input(event):
		get_viewport().set_input_as_handled()
