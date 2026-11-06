extends HudWidget
## The quest tracker (plan §2.10.1, §3.15 design 6; P13): top-right, (-356..-16, 14..132). The
## main quest's title and current objective, then one side quest - the first of Quests'
## side-quest order: the active village branch, otherwise quest.village, otherwise another (the
## Hollow tutorial). For a few seconds after quest or dialogue XP it adds "+110 XP - Prototype
## pacing: accelerated quest XP" (decision 7). Hidden while quests are inactive (the sandbox) or
## nothing is tracked. Read API: lines_now(), visible_text().
## P27 (plan M6-M9 §2.12, §3.10 design 4): the first line follows the tracked quest
## (Quests.tracked_id(): the main quest unless the player tracks another with T / D-pad Left or the
## journal); the second is then the main quest, else the first other quest. Drawn by HudKit's rules
## (no clipping: the lines trim with an ellipsis and the panel fits its region).

const PACING_SHOW_S := 4.0
const MAX_FRAME_S := 0.1
const GOLD := Color(1.0, 0.86, 0.45)
const COMPLETE_TEXT := "Complete. The valley is yours to explore."

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
	_panel = HudKit.panel(Color(0.05, 0.06, 0.08, 0.72))
	_panel.anchor_left = 1.0
	_panel.anchor_right = 1.0
	_panel.offset_left = -356
	_panel.offset_right = -16
	_panel.offset_top = 14
	_panel.offset_bottom = 132
	add_child(_panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 0)
	_panel.add_child(v)
	_main_title = _line(v, HudKit.SMALL, GOLD)
	_main_text = _line(v, HudKit.TEXT, UiKit.TEXT, 2)
	_side_title = _line(v, HudKit.SMALL, UiKit.MUTED)
	_side_text = _line(v, HudKit.TEXT, UiKit.TEXT, 1)
	_pacing = _line(v, HudKit.SMALL, GOLD)
	_panel.visible = false
	Events.xp_gained.connect(_on_xp_gained)


func _line(parent: Control, size: int, color: Color, max_lines := 1) -> Label:
	var l := HudKit.label("", size, color)
	l.custom_minimum_size = Vector2(324, 0)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART if max_lines > 1 else TextServer.AUTOWRAP_OFF
	l.max_lines_visible = max_lines
	l.add_theme_constant_override("line_spacing", 0)
	l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	parent.add_child(l)
	return l


## What the tracker shows for a list of objectives (Quests.objectives(): main first), whether the
## main quest is complete and (P27) the tracked quest: {"main_title", "main_text", "side_title",
## "side_text"} ("" = none). The first line is the tracked quest's objective (else the main
## quest's; else, the main quest done, COMPLETE_TEXT); the second the main quest's when another is
## tracked, else the first other quest's.
static func lines_for(objectives: Array, main_done := false, main_title := "", tracked_id := "") -> Dictionary:
	var out := {"main_title": "", "main_text": "", "side_title": "", "side_text": ""}
	var main: Dictionary = {}
	var tracked: Dictionary = {}
	for o: Dictionary in objectives:
		if main.is_empty() and bool(o.get("main", false)):
			main = o
		if tracked.is_empty() and tracked_id != "" and str(o.get("quest_id", "")) == tracked_id:
			tracked = o
	var first: Dictionary = tracked if not tracked.is_empty() else main
	if not first.is_empty():
		out.main_title = str(first.get("title", ""))
		out.main_text = str(first.get("text", ""))
	elif main_done:
		out.main_title = main_title
		out.main_text = COMPLETE_TEXT
	var side: Dictionary = {}
	if not first.is_empty() and not is_same(first, main) and not main.is_empty():
		side = main
	else:
		for o: Dictionary in objectives:
			if not bool(o.get("main", false)) and not is_same(o, first):
				side = o
				break
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
		str(main_rec.get("display_name", "")), Quests.tracked_id())
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


func layout_controls() -> Dictionary:
	return {"quest_tracker": _panel}
