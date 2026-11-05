class_name DialogueScreen
extends UiScreen
## The dialogue screen (plan §2.10.2, §3.15 design 3; P13): ScreenStack SCREENS["dialogue"],
## opened by Quests when an NpcTalker is used (Events.ui_screen_requested("dialogue",
## {"session": DialogueSession})). It pauses the game and shows the speaker, the current line and
## one numbered button per choice the session offers; keys 1-4 (and pad focus + A) choose.
## A choice that ends the conversation closes the screen; Esc / pad B leaves without choosing
## (the session ends). It is only a view: the choices are DialogueSession.choose(), which the
## Valley bot and tests call directly without the screen. args: {"session"} (else
## Quests.dialogue).
## P16: the choices are one focus column that wraps (pad D-pad / stick, keyboard arrows); after a
## choice the rebuilt buttons are wired again and the first one takes the focus.

const MAX_KEYED_CHOICES := 4

var session: DialogueSession
var choice_buttons: Array[Button] = []
var _speaker: Label
var _text: Label
var _choices: VBoxContainer
var _closing := false


func _ready() -> void:
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.35)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shade)
	var frame := UiKit.panel(Color(0.08, 0.07, 0.06, 0.96))
	frame.mouse_filter = Control.MOUSE_FILTER_STOP
	frame.anchor_left = 0.5
	frame.anchor_right = 0.5
	frame.anchor_top = 1.0
	frame.anchor_bottom = 1.0
	frame.offset_left = -400
	frame.offset_right = 400
	frame.offset_top = -330
	frame.offset_bottom = -40
	add_child(frame)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	frame.add_child(v)
	_speaker = UiKit.label("", 22, Color(1.0, 0.86, 0.45))
	v.add_child(_speaker)
	_text = UiKit.label("", 18)
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text.custom_minimum_size = Vector2(760, 0)
	v.add_child(_text)
	_choices = VBoxContainer.new()
	_choices.add_theme_constant_override("separation", 6)
	v.add_child(_choices)


func on_open() -> void:
	session = args.get("session") as DialogueSession
	if session == null:
		session = Quests.dialogue
	if session != null and not session.ended.is_connected(_on_session_ended):
		session.ended.connect(_on_session_ended)
	refresh()
	if session == null or not session.is_active():
		_close_deferred({"ended": true})


func on_close() -> void:
	if session != null:
		if session.ended.is_connected(_on_session_ended):
			session.ended.disconnect(_on_session_ended)
		if session.is_active():
			# Closed without an ending choice (Esc, close_all): the conversation is over.
			if Quests.dialogue == session:
				Quests.end_dialogue()
			else:
				session.end("closed")


func first_focus() -> Control:
	return choice_buttons[0] if not choice_buttons.is_empty() else null


## One row per choice, top to bottom (P16).
func focus_rows() -> Array:
	var rows: Array = []
	for b in choice_buttons:
		if is_instance_valid(b):
			rows.append([b])
	return rows


## Esc / pad B: leave the conversation without choosing.
func cancel() -> void:
	close({"cancelled": true})


## Rebuilds the speaker, the line and the choice buttons from the session.
func refresh() -> void:
	_update_lines()
	_rebuild_choices()


func _update_lines() -> void:
	if _text == null:
		return
	var live := session != null and session.is_active()
	_speaker.text = session.speaker() if live else ""
	_text.text = session.text() if live else ""


func _rebuild_choices() -> void:
	if _choices == null:
		return
	for b in choice_buttons:
		if is_instance_valid(b):
			_choices.remove_child(b)
			b.queue_free()
	choice_buttons.clear()
	if session == null or not session.is_active():
		return
	for c: Dictionary in session.choices():
		var b := UiKit.button(choice_label(int(c.index), str(c.text)), 17)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.pressed.connect(press_choice.bind(int(c.index)))
		_choices.add_child(b)
		choice_buttons.append(b)
	if is_open():
		refresh_focus()
		var f := first_focus()
		if f != null and f.is_visible_in_tree():
			f.grab_focus()


## "1. I'll bring back your stolen supplies." (only the first four are numbered keys).
static func choice_label(index: int, text: String) -> String:
	return "%d. %s" % [index + 1, text] if index < MAX_KEYED_CHOICES else text


## Takes choice `index` (the buttons, keys 1-4, the bot's screen path): DialogueSession.choose.
## The screen closes when the conversation ends.
func press_choice(index: int) -> Dictionary:
	if session == null:
		return {"ok": false, "reason": "no_session"}
	var r := session.choose(index)
	if not session.is_active():
		_close_deferred({"ended": true, "outcome": str(r.get("outcome", ""))})
	else:
		# The line changes at once; the buttons (one of which may be emitting `pressed` right now)
		# are disabled and rebuilt at the end of the frame, so a double press cannot pick a choice
		# of the next node.
		_update_lines()
		for b in choice_buttons:
			if is_instance_valid(b):
				b.disabled = true
		_rebuild_choices.call_deferred()
	return r


func _unhandled_input(event: InputEvent) -> void:
	if not is_open() or not (event is InputEventKey):
		return
	var k := event as InputEventKey
	if not k.pressed or k.echo:
		return
	var n := choice_key(k.keycode)
	if n < 0:
		n = choice_key(k.physical_keycode)
	if n >= 0 and n < choice_buttons.size() and not choice_buttons[n].disabled:
		press_choice(n)
		get_viewport().set_input_as_handled()


## The choice index of a number key (1-4 on the top row or the keypad), -1 for any other key.
static func choice_key(keycode: int) -> int:
	if keycode >= KEY_1 and keycode <= KEY_4:
		return keycode - KEY_1
	if keycode >= KEY_KP_1 and keycode <= KEY_KP_4:
		return keycode - KEY_KP_1
	return -1


func _on_session_ended(_s: DialogueSession) -> void:
	_close_deferred({"ended": true})


## Closes at the end of the frame (never from inside a button's or the session's signal).
func _close_deferred(result: Dictionary) -> void:
	if _closing:
		return
	_closing = true
	_finish_close.call_deferred(result)


func _finish_close(result: Dictionary) -> void:
	if is_open():
		close(result)


## The speaker and the line shown now ("" when none).
func visible_text() -> String:
	if _text == null or _text.text == "":
		return ""
	return "%s: %s" % [_speaker.text, _text.text]


## The labels of the choice buttons shown now.
func choice_texts() -> PackedStringArray:
	var out := PackedStringArray()
	for b in choice_buttons:
		if is_instance_valid(b):
			out.append(b.text)
	return out
