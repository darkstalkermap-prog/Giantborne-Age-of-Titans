extends ShrineTab
## Shrine screen tab "Appearance" (P44; plan M10 §2.10, decisions 15 and 16): the giant's look in words
## (Appearance.summary_lines for the giant's line: "Hair: long, combed back, chestnut, a little grey", ...)
## and "Change your look...", which opens the creator (ScreenStack SCREENS["creator"]) over the paused shrine
## screen with {"context": "shrine", "player", "shrine", "appearance"}. Changes are free, at any shrine, at any
## stage, any number of times.
##
##   * Keep this look -> player.appearance.set_record(record): the live giant changes, Events.appearance_changed
##     fires and GameSession re-takes and writes the shrine's checkpoint (the F15 list).
##   * Cancel -> the look is restored in memory (PlayerAppearance.restore_record), without a write or an event.
## The tab's button reads "Appearance (new)" until the tab is first opened in a save: opening it sets the flag
## appearance.tab_seen (which also dismisses the one-time tutorial.appearance_shrines). The tab's own title
## stays "Appearance" (ShrineScreen.tab() and the tests find it by that).

const TITLE := "Appearance"
const NEW_MARK := " (new)"
const SEEN_FLAG := "appearance.tab_seen"
const INTRO := "How your giant looks: hair and beard, skin and eyes, tattoos, war paint, scars and clothing. Changes are free, here and at every shrine."
const CHANGE := "Change your look..."
const KEPT := "Your new look is kept."
const UNCHANGED := "Your look is unchanged."

var change_button: Button
## The creator this tab opened (null when none is open).
var creator: UiScreen = null
var _summary: Label
var _result: Label
var _previous: Dictionary = {}
var _had_record := false


func tab_title() -> String:
	return TITLE


## Every giant with a look component (all of them since M10).
func available() -> bool:
	var p := player()
	return p != null and p.appearance != null


func _ready() -> void:
	add_theme_constant_override("separation", 10)
	var intro := UiKit.label(INTRO, 13, UiKit.MUTED)
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(intro)
	var panel := UiKit.panel(UiKit.BG_LIGHT)
	add_child(panel)
	_summary = UiKit.label("", 15)
	_summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	panel.add_child(_summary)
	change_button = UiKit.button(CHANGE, 18)
	change_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	change_button.pressed.connect(press_change)
	add_child(change_button)
	_result = UiKit.label("", 14, UiKit.GOOD)
	_result.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_result)
	visibility_changed.connect(_note_seen)
	refresh()


func first_focus() -> Control:
	return change_button


func refresh() -> void:
	var p := player()
	if _summary == null or p == null or p.appearance == null:
		return
	_summary.text = "\n".join(summary())
	_note_seen()
	_update_button()


## The look in words (one line per part), for the giant's line.
func summary() -> PackedStringArray:
	var p := player()
	if p == null or p.appearance == null:
		return PackedStringArray()
	return Appearance.summary_lines(p.appearance.record(), p.appearance.ancestry())


## True once the tab has been opened in this save (the flag appearance.tab_seen).
static func seen() -> bool:
	return QuestConditions.truthy(WorldState.get_flag(SEEN_FLAG))


## The tab's button text: "Appearance (new)" until the tab is first opened.
func button_text() -> String:
	return TITLE if seen() else TITLE + NEW_MARK


func _note_seen() -> void:
	if is_visible_in_tree() and not seen():
		WorldState.set_flag(SEEN_FLAG, true)
	_update_button()


func _update_button() -> void:
	if screen == null or not is_instance_valid(screen):
		return
	var i := screen.tabs.find(self)
	var buttons := screen.tab_buttons()
	if i >= 0 and i < buttons.size() and buttons[i].text != button_text():
		buttons[i].text = button_text()


## "Change your look...": opens the creator over the shrine (or returns null when there is no stack).
func press_change() -> UiScreen:
	var p := player()
	if p == null or p.appearance == null:
		return null
	var stack: ScreenStack = screen.stack if screen != null and is_instance_valid(screen.stack) else null
	if stack == null:
		return null
	_had_record = p.appearance.has_record()
	_previous = p.appearance.record() if _had_record else {}
	creator = stack.open("creator", {"context": "shrine", "player": p, "shrine": shrine(),
		"appearance": p.appearance.record()})
	if creator != null:
		creator.closed.connect(_on_creator_closed)
		_result.text = ""
	return creator


func _on_creator_closed(result: Dictionary) -> void:
	creator = null
	var p := player()
	if p == null or not is_instance_valid(p) or p.appearance == null:
		return
	if typeof(result.get("appearance")) == TYPE_DICTIONARY:
		p.appearance.set_record(result.appearance)
		_set_result(KEPT)
	else:
		p.appearance.restore_record(_previous if _had_record else {})
		_set_result(UNCHANGED)
	if screen != null and is_instance_valid(screen):
		screen.notify_changed()
	else:
		refresh()


func result_text() -> String:
	return _result.text if _result != null else ""


func summary_text() -> String:
	return _summary.text if _summary != null else ""


func _set_result(text: String) -> void:
	if _result != null:
		_result.text = text
