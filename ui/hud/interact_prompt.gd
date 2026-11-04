extends HudWidget
## "[E] Talk": the interact prompt for the best candidate around the player (PlayerInteract),
## centred 100-136 px below the crosshair. The key label follows the last input device: pad
## glyphs after a controller input, keyboard otherwise (P16 refines the device tracking).

var _panel: PanelContainer
var _label: Label
var _pad := false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_panel = UiKit.panel(Color(0.05, 0.06, 0.08, 0.78))
	_panel.anchor_left = 0.5
	_panel.anchor_right = 0.5
	_panel.anchor_top = 0.5
	_panel.anchor_bottom = 0.5
	_panel.offset_left = -200
	_panel.offset_right = 200
	_panel.offset_top = 100
	_panel.offset_bottom = 136
	add_child(_panel)
	_label = UiKit.label("", 17)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_panel.add_child(_label)
	_panel.visible = false


func _input(event: InputEvent) -> void:
	if event is InputEventJoypadButton:
		_pad = true
	elif event is InputEventJoypadMotion:
		if absf((event as InputEventJoypadMotion).axis_value) > 0.5:
			_pad = true
	elif event is InputEventKey or event is InputEventMouseButton:
		_pad = false


func _process(_delta: float) -> void:
	var text := prompt_for(player(), _pad)
	_label.text = text
	_panel.visible = text != ""


## The text shown for `p` ("" = hidden): "[<interact binding>] <prompt>".
static func prompt_for(p: GiantPlayer, pad: bool) -> String:
	if p == null or p.interact == null or p.controller == null \
			or p.controller.state == CombatController.State.DEAD:
		return ""
	var prompt := p.interact.current_prompt()
	if prompt == "":
		return ""
	return "[%s] %s" % [InputBindings.describe_action("interact", pad), prompt]


## What the widget shows right now ("" when hidden).
func visible_text() -> String:
	return _label.text if _panel != null and _panel.visible else ""
