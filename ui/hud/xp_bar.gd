extends HudWidget
## The XP bar (plan §2.10.1; P12): bottom-left, (16..340, -166..-152), just above the resource
## panel. A thin bar filled with the XP earned inside the current level, and the line
## "Lv 3  120 / 200 XP" ("Lv 20  MAX" at the level cap). For a moment after each gain it adds
## "+60" to the line. Reads player.progression; hidden when the giant has no progression component.

const GAIN_SHOW_S := 2.0

var _bar: ProgressBar
var _label: Label
var _text := ""
var _gain := 0
var _gain_left := 0.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_bar = UiKit.bar(Color(0.86, 0.74, 0.30), 14)
	_bar.anchor_top = 1.0
	_bar.anchor_bottom = 1.0
	_bar.offset_left = 16
	_bar.offset_right = 340
	_bar.offset_top = -166
	_bar.offset_bottom = -152
	add_child(_bar)
	_label = UiKit.label("", 11)
	_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.offset_left = 6
	_label.clip_text = true
	_bar.add_child(_label)
	_bar.visible = false
	Events.xp_gained.connect(_on_xp_gained)


## "Lv 3  120 / 200 XP" for a level and its progress ([into, needed]; needed 0 = the cap).
static func bar_text(level: int, progress: Array) -> String:
	if int(progress[1]) <= 0:
		return "Lv %d  MAX" % level
	return "Lv %d  %d / %d XP" % [level, int(progress[0]), int(progress[1])]


## The fill (0..1) of the bar for a level's progress.
static func fill_for(progress: Array) -> float:
	var needed := int(progress[1])
	return 1.0 if needed <= 0 else clampf(float(progress[0]) / float(needed), 0.0, 1.0)


## What the bar shows now ("" while hidden).
func visible_text() -> String:
	return _text if _bar != null and _bar.visible else ""


func _on_xp_gained(_tick: int, amount: int, _source: String, _total: int) -> void:
	_gain = _gain + amount if _gain_left > 0.0 else amount
	_gain_left = GAIN_SHOW_S


func _process(delta: float) -> void:
	var p := player()
	var prog: Variant = p.progression if p != null else null
	if prog == null:
		_bar.visible = false
		_text = ""
		return
	_bar.visible = true
	var progress: Array = prog.level_progress()
	_bar.value = fill_for(progress)
	_text = bar_text(int(prog.level), progress)
	if _gain_left > 0.0:
		_gain_left -= minf(delta, 0.1)
		_text += "   +%d" % _gain
	_label.text = _text


func layout_controls() -> Dictionary:
	return {"xp_bar": _bar}
