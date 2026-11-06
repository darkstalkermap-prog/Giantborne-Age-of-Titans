extends HudWidget
## The region banner (P27; plan M6-M9 §2.14, §3.10 design 1): on Events.region_changed (WorldRoot,
## 15 m hysteresis; the first region as the world loads) the region's name, and under it
## "Recommended stage 4-5" - in the warning colour while the giant is below the region's
## recommended_stage, muted otherwise - for SHOW_S, then a FADE_S fade. Top centre,
## (-HALF_WIDTH..HALF_WIDTH, TOP..TOP + HEIGHT): below the ability notice (the plan's 150..196 met the
## notice's 162..200). Drawn by HudKit's rules (its band a rectangle, the two lines shadowed labels).
## Read API: visible_text(), shown_region(); banner_lines() is pure.

const HALF_WIDTH := 320.0
const TOP := 206.0
const HEIGHT := 46.0
const SHOW_S := 3.0
const FADE_S := 0.5
const MAX_FRAME_S := 0.1
const TITLE_COLOR := Color(1.0, 0.88, 0.55)

var _panel: Control
var _title: Label
var _subtitle: Label
var _region := ""
var _left := 0.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_panel = HudKit.rect(Color(0.04, 0.05, 0.07, 0.62))
	_panel.anchor_left = 0.5
	_panel.anchor_right = 0.5
	_panel.offset_left = -HALF_WIDTH
	_panel.offset_right = HALF_WIDTH
	_panel.offset_top = TOP
	_panel.offset_bottom = TOP + HEIGHT
	_panel.visible = false
	add_child(_panel)
	_title = HudKit.label("", HudKit.BIG, TITLE_COLOR)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_title.position = Vector2(8, 2)
	_title.size = Vector2(2.0 * HALF_WIDTH - 16.0, 24)
	_panel.add_child(_title)
	_subtitle = HudKit.label("", HudKit.SMALL, UiKit.MUTED)
	_subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_subtitle.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_subtitle.position = Vector2(8, 26)
	_subtitle.size = Vector2(2.0 * HALF_WIDTH - 16.0, 16)
	_panel.add_child(_subtitle)
	Events.region_changed.connect(_on_region_changed)


## The banner's lines for a region and the giant's stage: {"title", "subtitle", "warn" (below the
## recommended stage)}; {} for no region (or one without a record).
static func banner_lines(region_id: String, stage: int) -> Dictionary:
	var rec := GameData.get_record(region_id)
	if region_id == "" or str(rec.get("type", "")) != "region":
		return {}
	var out := {"title": str(rec.get("display_name", region_id)), "subtitle": "", "warn": false}
	var rs: Variant = rec.get("recommended_stage")
	if typeof(rs) == TYPE_ARRAY and (rs as Array).size() == 2:
		var lo := int(rs[0])
		var hi := int(rs[1])
		out.subtitle = "Recommended stage %d" % lo if lo == hi else "Recommended stage %d-%d" % [lo, hi]
		out.warn = stage < lo
	return out


## Shows the banner for a region now (also what region_changed does).
func show_region(region_id: String, stage: int) -> void:
	var lines := banner_lines(region_id, stage)
	if lines.is_empty():
		return
	_region = region_id
	_title.text = str(lines.title).to_upper()
	_subtitle.text = str(lines.subtitle)
	_subtitle.add_theme_color_override("font_color", UiKit.WARN if bool(lines.warn) else UiKit.MUTED)
	_left = SHOW_S + FADE_S
	_panel.modulate.a = 1.0
	_panel.visible = true


func _on_region_changed(_tick: int, region_id: String, _previous: String) -> void:
	var p := player()
	show_region(region_id, p.current_growth_stage() if p != null else GameSession.current_stage())


func _process(delta: float) -> void:
	if not _panel.visible:
		return
	_left -= minf(delta, MAX_FRAME_S)
	if _left <= 0.0:
		_panel.visible = false
	elif _left < FADE_S:
		_panel.modulate.a = _left / FADE_S


## "THE GREYWOOD | Recommended stage 4-5" while shown ("" while hidden).
func visible_text() -> String:
	if _panel == null or not _panel.visible:
		return ""
	return "%s | %s" % [_title.text, _subtitle.text] if _subtitle.text != "" else _title.text


## The region shown now ("" while hidden).
func shown_region() -> String:
	return _region if _panel != null and _panel.visible else ""


## True while the recommended stage shows in the warning colour.
func warns() -> bool:
	return _panel != null and _panel.visible and _subtitle.get_theme_color("font_color") == UiKit.WARN


func layout_controls() -> Dictionary:
	return {"region_banner": _panel}
