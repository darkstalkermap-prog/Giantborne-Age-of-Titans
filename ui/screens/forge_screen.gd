class_name ForgeScreen
extends UiScreen
## The forge screen (plan §2.10.2, §3.14 design 6; P12): ScreenStack SCREENS["forge"], opened when a
## Forge is used (Events.ui_screen_requested("forge", {"forge": forge})). It pauses the game and
## shows the equipped weapon, what the forge would make of it (its damage multiplier and the stage
## it fits), the cost against what the giant carries, and a Reforge button enabled only when
## Forge.can_upgrade passes; pressing it calls Forge.upgrade (the one upgrade interaction) and shows
## the result. Leave (or Esc / pad B) closes it. args: {"forge": Forge, "player": GiantPlayer}.
## P16: focus rows Reforge (left out while disabled) and Leave, wrapping; after a reforge the
## focus moves to Leave.

var forge: Forge
var player: GiantPlayer
var _title: Label
var _info: Label
var _cost: VBoxContainer
var _status: Label
var _result: Label
var reforge_button: Button
var leave_button: Button


func _ready() -> void:
	forge = args.get("forge") as Forge
	player = args.get("player") as GiantPlayer
	if player == null and is_inside_tree():
		player = get_tree().get_first_node_in_group("player") as GiantPlayer
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.5)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(shade)
	var frame := UiKit.panel(Color(0.09, 0.07, 0.06, 0.97))
	frame.mouse_filter = Control.MOUSE_FILTER_STOP
	frame.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	frame.offset_left = -340
	frame.offset_right = 340
	frame.offset_top = -220
	frame.offset_bottom = 220
	add_child(frame)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	frame.add_child(v)
	_title = UiKit.label(forge.display_name if forge != null else "Forge", 28)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(_title)
	_info = UiKit.label("", 16)
	_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(_info)
	_cost = VBoxContainer.new()
	v.add_child(_cost)
	_status = UiKit.label("", 15, UiKit.WARN)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(_status)
	reforge_button = UiKit.button("Reforge", 20)
	reforge_button.pressed.connect(_on_reforge)
	v.add_child(reforge_button)
	_result = UiKit.label("", 15, UiKit.GOOD)
	_result.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(_result)
	leave_button = UiKit.button("Leave", 18)
	leave_button.pressed.connect(cancel)
	v.add_child(leave_button)


func on_open() -> void:
	refresh()


func first_focus() -> Control:
	return reforge_button if reforge_button != null and not reforge_button.disabled else leave_button


## Reforge (left out while disabled), then Leave (P16).
func focus_rows() -> Array:
	return [[reforge_button], [leave_button]]


func refresh() -> void:
	_refresh_content()
	if is_inside_tree():
		refresh_focus()


func _refresh_content() -> void:
	if _info == null:
		return
	for c in _cost.get_children():
		_cost.remove_child(c)
		c.queue_free()
	if forge == null or not is_instance_valid(forge):
		_info.text = "There is no forge here."
		reforge_button.disabled = true
		return
	var check := forge.can_upgrade(player)
	_info.text = info_text_for(check)
	for c: Dictionary in check.cost:
		var met := int(c.held) >= int(c.count)
		_cost.add_child(UiKit.label("%s %s x%d (you have %d)" % ["[x]" if met else "[ ]", str(c.name),
			int(c.count), int(c.held)], 15, UiKit.TEXT if met else UiKit.WARN))
	_status.text = "" if check.ok else str(check.message)
	reforge_button.disabled = not check.ok


## The offer as text: "Oak Club -> Reinforced Club: x1.15 damage, fits a stage-3 giant."
static func info_text_for(check: Dictionary) -> String:
	if str(check.get("from", "")) == "":
		return "You carry no weapon to reforge."
	if str(check.get("to", "")) == "":
		return "%s: it cannot be reforged any further." % str(check.from_name)
	return "%s -> %s: x%.2f damage, fits a stage-%d giant." % [str(check.from_name), str(check.to_name),
		float(check.to_multiplier), int(check.to_fit)]


## The Reforge button (also used by tests and the bot's screen path): Forge.upgrade.
func press_reforge() -> Dictionary:
	if forge == null or not is_instance_valid(forge):
		return {"ok": false, "reason": "no_forge", "message": ""}
	var out := forge.upgrade(player)
	_result.text = str(out.get("message", ""))
	_result.add_theme_color_override("font_color", UiKit.GOOD if out.ok else UiKit.WARN)
	refresh()
	return out


func _on_reforge() -> void:
	press_reforge()


func info_text() -> String:
	return _info.text if _info != null else ""


func status_text() -> String:
	return _status.text if _status != null else ""


func result_text() -> String:
	return _result.text if _result != null else ""
