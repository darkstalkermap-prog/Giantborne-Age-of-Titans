extends ShrineTab
## Shrine screen tab "Ancestry" (P33, plan M6-M9 §3.17, §5.12, decision 22): shown while the ancestry
## is still to be chosen and the Old Kingdom has opened (PlayerProgression.ancestry_offered; so a
## migrated prologue save is offered it too). An intro says what an ancestry is and that it is chosen
## once; the three ancestries stand side by side, each with what the line is, the attribute points it
## adds, its lasting strengths, its signature ability (what it does and costs) and the peoples who
## answer to it, and "Choose <name>...". That button opens the ancestry screen to confirm the
## permanent choice (PlayerProgression.choose_ancestry); afterwards this tab names the ancestry
## chosen and where its signature ability is set on a key, until the shrine screen closes.
## Pad and keyboard: the three Choose buttons are one row (left / right, wrapping).

## Ancestry id -> its Choose button.
var choose_buttons: Dictionary = {}
## The ancestry screen this tab opened (null when none is open).
var confirm_screen: UiScreen = null
var _intro: Label
var _cards: HBoxContainer
var _result: Label


func tab_title() -> String:
	return "Ancestry"


func available() -> bool:
	var p := player()
	return p != null and p.progression != null and p.progression.has_method("ancestry_offered") \
		and bool(p.progression.ancestry_offered())


func _ready() -> void:
	add_theme_constant_override("separation", 8)
	_intro = UiKit.label("The blood of the old giant kings wakes in you. Choose the line you come from: it raises two attributes, gives lasting strengths and a signature ability, and some peoples will speak to you differently. You choose once.", 13, UiKit.MUTED)
	_intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_intro)
	_cards = HBoxContainer.new()
	_cards.add_theme_constant_override("separation", 8)
	add_child(_cards)
	for id: Variant in Talents.ancestry_ids():
		_cards.add_child(_card(str(id)))
	_result = UiKit.label("", 14, UiKit.GOOD)
	_result.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_result)
	refresh()


## One ancestry's card: name, description, attributes, strengths, signature, peoples, Choose.
func _card(id: String) -> Control:
	var s := Talents.ancestry_summary(id)
	var panel := UiKit.panel(UiKit.BG_LIGHT)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	panel.add_child(v)
	v.add_child(UiKit.label(str(s.name), 19))
	for text: String in [str(s.description), "Attributes: " + str(s.attributes),
			"Lasting strengths: " + ", ".join(s.passives), "Signature ability: " + str(s.signature),
			str(s.peoples)]:
		if text.ends_with(": ") or text == "":
			continue
		var l := UiKit.label(text, 12, UiKit.TEXT if text.begins_with("Signature") else UiKit.MUTED)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size = Vector2(200, 0)
		v.add_child(l)
	var b := UiKit.button("Choose %s..." % str(s.name), 15)
	b.pressed.connect(press_choose.bind(id))
	v.add_child(b)
	choose_buttons[id] = b
	return panel


func first_focus() -> Control:
	for id: Variant in choose_buttons:
		var b: Button = choose_buttons[id]
		if UiNav.focusable(b):
			return b
	return null


func focus_rows() -> Array:
	var row: Array = []
	for id: Variant in choose_buttons:
		row.append(choose_buttons[id])
	return [row] if not row.is_empty() else []


func refresh() -> void:
	var p := player()
	if p == null or p.progression == null or _cards == null:
		return
	var chosen := bool(p.progression.ancestry_chosen)
	for id: Variant in choose_buttons:
		(choose_buttons[id] as Button).visible = not chosen
	if chosen:
		var sig := Talents.signature_of(str(p.progression.ancestry))
		var def := GameData.get_action(sig)
		_set_result("You are %s. %s" % [p.progression.ancestry_name(),
			("%s is yours: set it on a key in the Loadout tab." % def.display_name) if def != null else ""], UiKit.GOOD)


## "Choose <name>...": opens the ancestry screen to confirm (or, without a screen stack, chooses at
## once). Returns the screen opened (null when it chose directly).
func press_choose(id: String) -> UiScreen:
	var p := player()
	if p == null or p.progression == null:
		return null
	var stack: ScreenStack = screen.stack if screen != null and is_instance_valid(screen.stack) else null
	if stack == null:
		_after_choice(p.progression.choose_ancestry(id))
		return null
	confirm_screen = stack.open("ancestry", {"ancestry": id, "player": p, "shrine": shrine()})
	if confirm_screen != null:
		confirm_screen.closed.connect(_on_confirm_closed)
	return confirm_screen


func _on_confirm_closed(result: Dictionary) -> void:
	confirm_screen = null
	if result.has("choice"):
		_after_choice(result.choice)


func _after_choice(out: Dictionary) -> void:
	if not bool(out.get("ok", false)):
		_set_result(str(out.get("message", "")), UiKit.WARN)
	if screen != null and is_instance_valid(screen):
		screen.notify_changed()
	else:
		refresh()


func result_text() -> String:
	return _result.text if _result != null else ""


func _set_result(text: String, color: Color) -> void:
	if _result == null:
		return
	_result.text = text
	_result.add_theme_color_override("font_color", color)
