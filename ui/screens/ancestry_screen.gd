class_name AncestryScreen
extends UiScreen
## The ancestry screen (P33, plan M6-M9 §2.14, §3.17, §5.12, decision 22): ScreenStack
## SCREENS["ancestry"], where the giant's ancestry is chosen - once, for good. The shrine's Ancestry
## tab opens it ("Choose Stoneblood..." preselects that ancestry); it also opens on its own
## (Events.ui_screen_requested("ancestry", {})). It pauses the game.
##
## A row of the three ancestries picks the one shown; the panel says everything it gives
## (Talents.ancestry_summary): what the line is, the attribute points it adds, its lasting strengths,
## its signature ability with what it does and costs, and the peoples who answer to it, then that
## the choice is permanent. "Choose <name>" calls PlayerProgression.choose_ancestry and closes with
## {"choice": result}; a refusal (the Old Kingdom not reached yet, in combat) stays on screen with its
## reason. Back (or Esc / pad B) closes with {"cancelled": true}. Once an ancestry is chosen the
## screen names it and only Back works.
##
## args: {"ancestry": id to show first (else the first choosable one), "player": GiantPlayer (else
## the first node in group "player")}.
## Pad and keyboard (P16): the ancestries are one row (left / right: moving shows each), then Choose
## and Back; every direction wraps. The focus starts on the ancestry shown, never on Choose, so a
## permanent choice always takes a deliberate second press.

## Ancestry id -> its button in the top row.
var ancestry_buttons: Dictionary = {}
## The ancestry shown now ("" when there is none to choose).
var selected := ""
var player: GiantPlayer
var confirm_button: Button
var back_button: Button
var _name: Label
var _description: Label
var _gives: Label
var _signature: Label
var _peoples: Label
var _warning: Label
var _status: Label


func _ready() -> void:
	player = args.get("player") as GiantPlayer
	if player == null and is_inside_tree():
		player = get_tree().get_first_node_in_group("player") as GiantPlayer
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.55)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(shade)
	var frame := UiKit.panel(Color(0.07, 0.09, 0.10, 0.97))
	frame.mouse_filter = Control.MOUSE_FILTER_STOP
	frame.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	frame.offset_left = -330
	frame.offset_right = 330
	frame.offset_top = -250
	frame.offset_bottom = 250
	add_child(frame)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	frame.add_child(v)
	var title := UiKit.label("The Blood of the Old Kings", 26)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(title)
	var intro := UiKit.label("Choose the line of giants you come from. It raises two attributes at once, gives you lasting strengths and a signature ability, and some peoples of the Old Kingdom will treat you differently.", 13, UiKit.MUTED)
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(intro)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 10)
	v.add_child(row)
	for id: Variant in Talents.ancestry_ids():
		var b := UiKit.button(Talents.ancestry_summary(str(id)).name, 17)
		b.custom_minimum_size = Vector2(150, 0)
		b.pressed.connect(select.bind(str(id)))
		b.focus_entered.connect(select.bind(str(id)))   # moving along the row shows each in turn
		row.add_child(b)
		ancestry_buttons[str(id)] = b
	var detail := UiKit.panel(UiKit.BG_LIGHT)
	detail.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(detail)
	var dv := VBoxContainer.new()
	dv.add_theme_constant_override("separation", 5)
	detail.add_child(dv)
	_name = UiKit.label("", 21)
	dv.add_child(_name)
	_description = _wrapped(13, UiKit.MUTED)
	dv.add_child(_description)
	_gives = _wrapped(14, UiKit.TEXT)
	dv.add_child(_gives)
	_signature = _wrapped(14, UiKit.TEXT)
	dv.add_child(_signature)
	_peoples = _wrapped(13, UiKit.MUTED)
	dv.add_child(_peoples)
	_warning = UiKit.label("This choice is permanent: your ancestry cannot be changed later.", 14, UiKit.WARN)
	_warning.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(_warning)
	_status = _wrapped(14, UiKit.WARN)
	v.add_child(_status)
	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 16)
	v.add_child(buttons)
	confirm_button = UiKit.button("Choose", 18)
	confirm_button.pressed.connect(confirm)
	buttons.add_child(confirm_button)
	back_button = UiKit.button("Back", 18)
	back_button.pressed.connect(cancel)
	buttons.add_child(back_button)
	var want := str(args.get("ancestry", ""))
	if not ancestry_buttons.has(want):
		want = str(ancestry_buttons.keys()[0]) if not ancestry_buttons.is_empty() else ""
	select(want)


static func _wrapped(font_size: int, color: Color) -> Label:
	var l := UiKit.label("", font_size, color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l


func _progression() -> PlayerProgression:
	return player.progression as PlayerProgression if player != null and is_instance_valid(player) else null


## True once the giant's ancestry is chosen (the screen then only names it).
func already_chosen() -> bool:
	var prog := _progression()
	return prog != null and prog.ancestry_chosen


## Shows ancestry `id` ("" or an unknown id shows nothing): its summary, the row's highlight and
## "Choose <name>" (disabled once an ancestry is chosen).
func select(id: String) -> void:
	if _name == null or not ancestry_buttons.has(id):
		return
	selected = id
	var s := Talents.ancestry_summary(id)
	for key: Variant in ancestry_buttons:
		var b: Button = ancestry_buttons[key]
		var color := UiKit.GOOD if str(key) == id else UiKit.TEXT
		for c: String in ["font_color", "font_hover_color", "font_focus_color", "font_pressed_color"]:
			b.add_theme_color_override(c, color)
	_name.text = str(s.name)
	_description.text = str(s.description)
	var gives := PackedStringArray()
	if str(s.attributes) != "":
		gives.append("Attributes at once: %s" % s.attributes)
	if not (s.passives as PackedStringArray).is_empty():
		gives.append("Lasting strengths: %s" % ", ".join(s.passives))
	_gives.text = "\n".join(gives)
	_signature.text = ("Signature ability: %s" % s.signature) if str(s.signature) != "" else ""
	_peoples.text = str(s.peoples)
	confirm_button.text = "Choose %s" % s.name
	var chosen := already_chosen()
	var changed := confirm_button.disabled != chosen
	confirm_button.disabled = chosen
	_warning.visible = not chosen
	if chosen:
		_set_status("You are %s: an ancestry is chosen once." % _progression().ancestry_name(), UiKit.GOOD)
	if changed and is_inside_tree():
		refresh_focus()   # Choose can no longer take the focus


## Chooses the ancestry shown (PlayerProgression.choose_ancestry). On success the screen closes with
## {"choice": result}; a refusal stays on screen with its reason. Returns the result.
func confirm() -> Dictionary:
	var prog := _progression()
	if prog == null or selected == "":
		return {"ok": false, "reason": "unknown", "message": "There is no giant to choose for."}
	var out: Dictionary = prog.choose_ancestry(selected)
	if bool(out.get("ok", false)):
		close({"choice": out})
	else:
		_set_status(str(out.get("message", "")), UiKit.WARN)
	return out


## The button of the ancestry shown (else Back): never Choose, so the permanent choice always takes
## a deliberate move and press.
func first_focus() -> Control:
	var b: Button = ancestry_buttons.get(selected)
	if UiNav.focusable(b):
		return b
	return back_button


## The ancestries' row, then Choose and Back (P16).
func focus_rows() -> Array:
	return [ancestry_buttons.values(), [confirm_button, back_button]]


## What the panel says now (tests): the name, the description, what it gives, the signature and
## the peoples, one per line.
func detail_text() -> String:
	if _name == null:
		return ""
	return "\n".join(PackedStringArray([_name.text, _description.text, _gives.text, _signature.text,
		_peoples.text]))


func status_text() -> String:
	return _status.text if _status != null else ""


func _set_status(text: String, color: Color) -> void:
	if _status == null:
		return
	_status.text = text
	_status.add_theme_color_override("font_color", color)
