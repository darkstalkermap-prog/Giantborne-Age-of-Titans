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

const VALLEY_MISSING := "Valley not built yet"
const PAGES := ["Settings", "Controls"]

var _new_game: Button
var _continue: Button
var _sandbox: Button
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
	_continue = _menu_button("Continue", _on_continue)
	_sandbox = _menu_button("Sandbox", _on_sandbox)
	_menu_button("Settings", _show_page.bind("Settings"))
	_menu_button("Controls", _show_page.bind("Controls"))
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
	refresh()


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


## Continue when it is available, else New Game, else Sandbox.
func first_focus() -> Control:
	for b: Button in [_continue, _new_game, _sandbox]:
		if b != null and not b.disabled and b.visible:
			return b
	return _sandbox


func on_open() -> void:
	refresh()


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
	_new_game.disabled = not valley
	_continue.disabled = not can_continue
	_note.text = "" if valley else VALLEY_MISSING
	_save_label.text = save_text


## A short line about a save document: "Saved game: level 3, stage 2, at valley.shrine.grove,
## 2026-11-05 14:02".
static func describe_save(doc: Dictionary) -> String:
	var c: Dictionary = doc.get("character", {})
	var cp: Dictionary = doc.get("checkpoint", {})
	var parts := PackedStringArray(["level %d" % int(c.get("level", 1)), "stage %d" % int(c.get("growth_stage", 1))])
	if str(cp.get("respawn", "")) != "":
		parts.append("at %s" % cp.respawn)
	var when := int(doc.get("saved_at_unix", 0))
	if when > 0:
		parts.append(Time.get_datetime_string_from_unix_time(when, true).substr(0, 16))
	return "Saved game: " + ", ".join(parts)


## What the screen shows now (tests): {"new_game", "continue", "sandbox", "quit"} enabled flags,
## "note", "save" and "page".
func state() -> Dictionary:
	return {"new_game": not _new_game.disabled, "continue": not _continue.disabled,
		"sandbox": not _sandbox.disabled, "quit": _quit.visible, "note": _note.text,
		"save": _save_label.text, "page": current_page()}


## The button of a menu entry ("New Game", "Continue", "Sandbox", "Quit"), or null.
func button(label: String) -> Button:
	match label:
		"New Game":
			return _new_game
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


func _show_page(page_name: String) -> void:
	_settings_pages.cancel_capture()
	for key: String in _pages:
		(_pages[key] as Control).visible = key == page_name
	_menu.visible = page_name == ""
	_page_box.visible = page_name != ""
	if page_name == "Controls":
		_settings_pages.refresh_bindings()
	if not is_inside_tree():
		return
	var f: Control = first_focus() if page_name == "" else _back
	if f != null and f.is_visible_in_tree():
		f.grab_focus()


# --------------------------------------------------------------------------- actions

func _on_new_game() -> void:
	if _new_game.disabled:
		return
	if _save.get("ok", false) and not _confirm_new:
		_confirm_new = true
		_new_game.text = "New Game: replace the saved game?"
		_note.text = "Press New Game again to start over. Your saved game will be replaced."
		return
	_start("valley", {"new_game": true})


func _on_continue() -> void:
	if not _continue.disabled:
		_start("valley", {"continue": true})


func _on_sandbox() -> void:
	_start("sandbox", {})


func _on_quit() -> void:
	Settings.flush()
	get_tree().quit()


func _start(mode_name: String, options: Dictionary) -> void:
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
