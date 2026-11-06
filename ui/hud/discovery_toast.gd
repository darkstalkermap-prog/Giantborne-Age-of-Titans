extends HudWidget
## The discovery toast (P27; plan M6-M9 §2.14, §3.10 design 1): top left under the checkpoint toast,
## (12..352, 92..126). One line for each Events.poi_discovered - "Discovered: Hollowmere  +40 XP"
## (a vista adds how many places it put on the map) - and for each sealed place first seen (the flag
## sealed.<poi>.seen) - "Sealed: The Toppled King (grow to stage 5)", in the warning colour. Lines
## queue and show one at a time for SHOW_S, then fade over FADE_S; the HUD pauses with the game, so a
## line waits while a screen is open. Drawn by HudKit's rules. Read API: visible_text(),
## pending_count(); line_for() and sealed_line() are pure.

const SHOW_S := 3.0
const FADE_S := 0.5
const MAX_FRAME_S := 0.1
const MAX_QUEUE := 8
const FOUND := Color(0.95, 0.88, 0.55)

var _panel: PanelContainer
var _label: Label
var _queue: Array = []   ## [{"text", "color"}], oldest first
var _left := 0.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_panel = HudKit.panel(Color(0.05, 0.06, 0.08, 0.82))
	_panel.offset_left = 12
	_panel.offset_right = 352
	_panel.offset_top = 92
	_panel.offset_bottom = 126
	add_child(_panel)
	_label = HudKit.label("", HudKit.TEXT, FOUND)
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_panel.add_child(_label)
	_panel.visible = false
	Events.poi_discovered.connect(_on_poi_discovered)
	Events.flag_changed.connect(_on_flag_changed)


## "Discovered: Hollowmere  +40 XP" for a POI record (its xp; "" without a record); `revealed` places
## a vista put on the map are added: "  (6 places on your map)".
static func line_for(poi_id: String, revealed := 0) -> String:
	var rec := GameData.get_record(poi_id)
	if str(rec.get("type", "")) != "poi":
		return ""
	var text := "Discovered: %s" % str(rec.get("display_name", poi_id))
	var xp := int(rec.get("xp", 0))
	if xp > 0:
		text += "  +%d XP" % xp
	if revealed > 0:
		text += "  (%d place%s on your map)" % [revealed, "" if revealed == 1 else "s"]
	return text


## "Sealed: The Toppled King (grow to stage 5)" for a sealed place ("" when it is not one).
static func sealed_line(poi_id: String) -> String:
	var rec := GameData.get_record(poi_id)
	if str(rec.get("type", "")) != "poi" or str(rec.get("kind", "")) != "secret":
		return ""
	return "Sealed: %s (grow to stage %d)" % [str(rec.get("display_name", poi_id)), int(rec.get("min_stage", 0))]


func push(text: String, color: Color) -> void:
	if text == "":
		return
	_queue.append({"text": text, "color": color})
	while _queue.size() > MAX_QUEUE:
		_queue.pop_front()


func _on_poi_discovered(_tick: int, poi_id: String) -> void:
	var revealed := 0
	var d := Discovery.of_tree(get_tree()) if is_inside_tree() else null
	if d != null:
		for e: Dictionary in d.found_log:
			if str(e.how) == "reveal" and str(e.get("by", "")) == poi_id:
				revealed += 1
	push(line_for(poi_id, revealed), FOUND)


func _on_flag_changed(_tick: int, flag_id: String, _value: Variant) -> void:
	if flag_id.begins_with("sealed.") and flag_id.ends_with(".seen"):
		push(sealed_line("poi." + flag_id.trim_prefix("sealed.").trim_suffix(".seen")), UiKit.WARN)


func _process(delta: float) -> void:
	if _panel.visible:
		_left -= minf(delta, MAX_FRAME_S)
		if _left <= 0.0:
			_panel.visible = false
		elif _left < FADE_S:
			_panel.modulate.a = _left / FADE_S
		return
	if _queue.is_empty():
		return
	var next: Dictionary = _queue.pop_front()
	_label.text = str(next.text)
	_label.add_theme_color_override("font_color", next.color)
	_left = SHOW_S + FADE_S
	_panel.modulate.a = 1.0
	_panel.visible = true


## What the toast shows now ("" while hidden).
func visible_text() -> String:
	return _label.text if _panel != null and _panel.visible else ""


## Lines waiting behind the one on screen.
func pending_count() -> int:
	return _queue.size()


func layout_controls() -> Dictionary:
	return {"discovery_toast": _panel}
