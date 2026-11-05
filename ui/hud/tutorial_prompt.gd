extends HudWidget
## The tutorial prompt (plan §2.10.1, §3.15 design 5; P13): left-centre, (16..396, -70..70 around
## the vertical centre). The prompt the tutorial director shows now (Quests.current_tutorial()),
## its {placeholders} resolved to key or button names for the last input device (TutorialText):
## pad names after a controller input, keyboard and mouse otherwise (P16 refines the device
## tracking). Hidden while no prompt is shown. Read API: visible_text(), shown_id().

const TITLE := "TIP"

var _panel: PanelContainer
var _title: Label
var _label: Label
var _pad := false
var _id := ""


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_panel = UiKit.panel(Color(0.05, 0.07, 0.09, 0.82))
	_panel.anchor_top = 0.5
	_panel.anchor_bottom = 0.5
	_panel.offset_left = 16
	_panel.offset_right = 396
	_panel.offset_top = -70
	_panel.offset_bottom = 70
	_panel.clip_contents = true
	add_child(_panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	_panel.add_child(v)
	_title = UiKit.label(TITLE, 12, Color(0.55, 0.85, 1.0))
	v.add_child(_title)
	_label = UiKit.label("", 16)
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label.custom_minimum_size = Vector2(364, 0)
	_label.max_lines_visible = 5
	v.add_child(_label)
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
	var t: Dictionary = Quests.current_tutorial() if Quests.is_active() else {}
	if t.is_empty():
		_panel.visible = false
		_id = ""
		return
	_id = str(t.get("id", ""))
	_label.text = TutorialText.resolve(str(t.get("text", "")), _pad)
	_panel.visible = true


## The prompt's text as shown now ("" while hidden).
func visible_text() -> String:
	return _label.text if _panel != null and _panel.visible else ""


## The id of the prompt shown now ("" while hidden).
func shown_id() -> String:
	return _id if _panel != null and _panel.visible else ""
