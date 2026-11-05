extends HudWidget
## "[E] Talk": the interact prompt for the best candidate around the player (PlayerInteract),
## centred 100-136 px below the crosshair. The key label follows the device the prompts follow
## (P16: InputBindings.last_device_is_pad, fed by main.gd and the "Button prompts" setting): the
## key on a keyboard ("[E] Talk"), the pad button on a controller ("[X] Talk").

var _panel: PanelContainer
var _label: Label


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
	_label.clip_text = true
	_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_panel.add_child(_label)
	_panel.visible = false


func _process(_delta: float) -> void:
	var text := prompt_for(player(), InputBindings.last_device_is_pad())
	_label.text = text
	_panel.visible = text != ""


## The text shown for `p` ("" = hidden): "[<interact binding>] <prompt>" - the key, or the pad
## button's short name with `pad` (the full name when it has no short one).
static func prompt_for(p: GiantPlayer, pad: bool) -> String:
	if p == null or p.interact == null or p.controller == null \
			or p.controller.state == CombatController.State.DEAD:
		return ""
	var prompt := p.interact.current_prompt()
	if prompt == "":
		return ""
	return "[%s] %s" % [key_label(pad), prompt]


## The interact binding as the prompt names it: the key ("E") or the pad button ("X").
static func key_label(pad: bool) -> String:
	if pad:
		var short := InputBindings.short_pad_label("interact")
		if short != "":
			return short
	return InputBindings.describe_action("interact", pad)


## What the widget shows right now ("" when hidden).
func visible_text() -> String:
	return _label.text if _panel != null and _panel.visible else ""


func layout_regions(view: Vector2) -> Dictionary:
	return {"interact_prompt": anchored_rect(_panel, view)}
