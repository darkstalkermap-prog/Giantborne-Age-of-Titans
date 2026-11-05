extends HudWidget
## The quest tracker (plan §2.10.1, §3.15 design 6; P13): top-right, (-356..-16, 14..132). The
## main quest's title and current objective, then one side quest - the first of Quests'
## side-quest order: the active village branch, otherwise quest.village, otherwise another (the
## Hollow tutorial). For a few seconds after quest or dialogue XP it adds "+110 XP - Prototype
## pacing: accelerated quest XP" (decision 7). Hidden while quests are inactive (the sandbox) or
## nothing is tracked. Read API: lines_now(), visible_text().

const PACING_SHOW_S := 4.0
const MAX_FRAME_S := 0.1
const GOLD := Color(1.0, 0.86, 0.45)

var _panel: PanelContainer
var _main_title: Label
var _main_text: Label
var _side_title: Label
var _side_text: Label
var _pacing: Label
var _pacing_left := 0.0
var _lines: Dictionary = {}


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_panel = UiKit.panel(Color(0.05, 0.06, 0.08, 0.72))
	_panel.anchor_left = 1.0
	_panel.anchor_right = 1.0
	_panel.offset_left = -356
	_panel.offset_right = -16
	_panel.offset_top = 14
	_panel.offset_bottom = 132
	_panel.clip_contents = true
	add_child(_panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 1)
	_panel.add_child(v)
	_main_title = _line(v, 12, GOLD)
	_main_text = _line(v, 15, UiKit.TEXT, 2)
	_side_title = _line(v, 12, UiKit.MUTED)
	_side_text = _line(v, 13, UiKit.TEXT, 1)
	_pacing = _line(v, 11, GOLD)
	_panel.visible = false
	Events.xp_gained.connect(_on_xp_gained)


func _line(parent: Control, size: int, color: Color, max_lines := 1) -> Label:
	var l := UiKit.label("", size, color)
	l.custom_minimum_size = Vector2(324, 0)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART if max_lines > 1 else TextServer.AUTOWRAP_OFF
	l.max_lines_visible = max_lines
	l.clip_text = max_lines == 1
	l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	parent.add_child(l)
	return l


## What the tracker shows for a list of objectives (Quests.objectives(): main first) and whether
## the main quest is complete: {"main_title", "main_text", "side_title", "side_text"} ("" = none).
static func lines_for(objectives: Array, main_done := false, main_title := "") -> Dictionary:
	var out := {"main_title": "", "main_text": "", "side_title": "", "side_text": ""}
	var side: Dictionary = {}
	for o: Dictionary in objectives:
		if bool(o.get("main", false)) and out.main_text == "":
			out.main_title = str(o.get("title", ""))
			out.main_text = str(o.get("text", ""))
		elif not bool(o.get("main", false)) and side.is_empty():
			side = o
	if out.main_text == "" and main_done:
		out.main_title = main_title
		out.main_text = "Complete. The valley is yours to explore."
	if not side.is_empty():
		out.side_title = str(side.get("title", ""))
		out.side_text = str(side.get("text", ""))
	return out


func _on_xp_gained(_tick: int, amount: int, source: String, _total: int) -> void:
	if not Quests.is_active() or not Quests.paced_source(source):
		return
	_pacing.text = "+%d XP  -  %s" % [amount, Quests.pacing_label()]
	_pacing_left = PACING_SHOW_S


func _process(delta: float) -> void:
	if not Quests.is_active():
		_panel.visible = false
		_lines = {}
		return
	var main_rec := Quests.quest_record(Quests.main_quest_id)
	_lines = lines_for(Quests.objectives(), Quests.is_complete(Quests.main_quest_id),
		str(main_rec.get("display_name", "")))
	_main_title.text = str(_lines.main_title)
	_main_text.text = str(_lines.main_text)
	_side_title.text = str(_lines.side_title)
	_side_text.text = str(_lines.side_text)
	_main_title.visible = _main_title.text != ""
	_main_text.visible = _main_text.text != ""
	_side_title.visible = _side_title.text != ""
	_side_text.visible = _side_text.text != ""
	if _pacing_left > 0.0:
		_pacing_left -= minf(delta, MAX_FRAME_S)
	_pacing.visible = _pacing_left > 0.0
	_panel.visible = _main_text.visible or _side_text.visible or _pacing.visible


## The tracker's lines now ({} while hidden).
func lines_now() -> Dictionary:
	return _lines if _panel != null and _panel.visible else {}


## Everything the tracker shows now, one line each ("" while hidden).
func visible_text() -> String:
	if _panel == null or not _panel.visible:
		return ""
	var parts := PackedStringArray()
	for l: Label in [_main_title, _main_text, _side_title, _side_text, _pacing]:
		if l.visible and l.text != "":
			parts.append(l.text)
	return "\n".join(parts)
