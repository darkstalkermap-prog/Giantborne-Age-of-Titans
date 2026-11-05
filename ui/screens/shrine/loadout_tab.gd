extends ShrineTab
## Shrine screen tab "Loadout" (P12, plan §3.14 design 2): the eight ability slots and the ultimate,
## each with a list of the known abilities that fit it ("(empty)" first). Choosing one calls
## PlayerProgression.set_slot(slot, id, shrine): allowed only at a shrine whose record has loadout
## true, outside combat; an ability already in another slot swaps places. Shown when the record
## allows it and the giant has a progression component.
##
## P16: one focus row per slot list (slot 1 to 8, then the ultimate); the slot titles name the
## key or the pad combo of the device used last ("Slot 6 [6]" / "Slot 6 [LT+Rt]").

const EMPTY_LABEL := "(empty)"

var _rows: Dictionary = {}    ## slot key -> OptionButton
var _titles: Dictionary = {}  ## slot key -> its title Label
var _info: Label
var _result: Label
var _first: Control = null


func tab_title() -> String:
	return "Loadout"


func available() -> bool:
	var p := player()
	return bool(record().get("loadout", true)) and p != null and p.progression != null


func _ready() -> void:
	add_theme_constant_override("separation", 6)
	_info = UiKit.label("Choose the ability on each key. Abilities can be changed only at a shrine, outside combat.", 14, UiKit.MUTED)
	_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_info)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 4)
	add_child(grid)
	for key: String in GiantPlayer.SLOT_KEYS:
		var label := UiKit.label(slot_title(key, InputBindings.last_device_is_pad()), 15)
		label.custom_minimum_size = Vector2(150, 0)
		grid.add_child(label)
		_titles[key] = label
		var opt := OptionButton.new()
		opt.custom_minimum_size = Vector2(260, 0)
		opt.focus_mode = Control.FOCUS_ALL
		opt.item_selected.connect(_on_selected.bind(key))
		grid.add_child(opt)
		_rows[key] = opt
		if _first == null:
			_first = opt
	_result = UiKit.label("", 14, UiKit.GOOD)
	_result.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_result)


## "Slot 6 [6]" / "Ultimate [R]"; with pad (P16) the pad combo: "Slot 6 [LT+Rt]" / "Ultimate
## [LT+RT]" (the key when the slot has no pad binding).
static func slot_title(key: String, pad := false) -> String:
	var title := "Ultimate" if key == "ultimate" else "Slot %s" % key.trim_prefix("slot_")
	var label := Progression.slot_key_label(key)
	if pad:
		var combo := InputBindings.short_pad_label("ultimate" if key == "ultimate" else key.replace("slot_", "ability_"))
		if combo != "":
			label = combo
	return "%s [%s]" % [title, label]


func first_focus() -> Control:
	return _first


## One row per slot list, slot 1 to 8 then the ultimate (P16).
func focus_rows() -> Array:
	var rows: Array = []
	for key: String in GiantPlayer.SLOT_KEYS:
		if _rows.has(key):
			rows.append([_rows[key]])
	return rows


func refresh() -> void:
	var p := player()
	if p == null or p.progression == null or _rows.is_empty():
		return
	var pad := InputBindings.last_device_is_pad()
	for key: String in _titles:
		(_titles[key] as Label).text = slot_title(key, pad)
	for key: String in GiantPlayer.SLOT_KEYS:
		var opt: OptionButton = _rows[key]
		opt.clear()
		var current := str(p.controller.loadout.get(key, ""))
		var selected := 0
		var i := 0
		for id: String in p.progression.slot_options(key):
			opt.add_item(_label_for(id))
			opt.set_item_metadata(i, id)
			if id == current:
				selected = i
			i += 1
		opt.select(selected)
	var check: Dictionary = p.progression.can_change_loadout(shrine())
	for key: String in GiantPlayer.SLOT_KEYS:
		(_rows[key] as OptionButton).disabled = not check.ok
	if not check.ok:
		_set_result(str(check.message), UiKit.WARN)


static func _label_for(id: String) -> String:
	if id == "":
		return EMPTY_LABEL
	var def := GameData.get_action(id)
	return def.display_name if def != null else id


## The ids offered for `key` (tests).
func options_for(key: String) -> PackedStringArray:
	var p := player()
	return p.progression.slot_options(key) if p != null and p.progression != null else PackedStringArray()


## Puts `action_id` ("" = empty) into `key` through PlayerProgression.set_slot; shows the result.
func assign(key: String, action_id: String) -> Dictionary:
	var p := player()
	if p == null or p.progression == null:
		return {"ok": false, "reason": "no_player", "message": ""}
	var out: Dictionary = p.progression.set_slot(key, action_id, shrine())
	if out.ok:
		_set_result("%s: %s" % [slot_title(key), _label_for(action_id)], UiKit.GOOD)
	else:
		_set_result(str(out.message), UiKit.WARN)
	screen.notify_changed()
	return out


func _on_selected(index: int, key: String) -> void:
	var opt: OptionButton = _rows[key]
	assign(key, str(opt.get_item_metadata(index)))


func result_text() -> String:
	return _result.text if _result != null else ""


func _set_result(text: String, color: Color) -> void:
	if _result == null:
		return
	_result.text = text
	_result.add_theme_color_override("font_color", color)
