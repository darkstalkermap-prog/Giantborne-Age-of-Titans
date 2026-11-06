extends HudWidget
## The boss bar (plan §2.10.1, §3.12; P11a): top-centre, (-HALF_WIDTH..HALF_WIDTH, 44..88; P27). The
## boss's name, a wide health bar with a notch at each later phase's health threshold, and one pip
## per phase (filled up to the current one). It follows the boss of the last Events.boss_engaged
## while that boss lives; otherwise a locked target in group "bosses". Hud hides its own target
## frame while this bar shows the locked target (Hud.boss_bar_shows), and moves the frame of
## another locked target below the bar (P16). Reads state; never changes gameplay.
## Read API for tests: shows_entity(e), current_boss(), visible_text(), phase_pips(), bar_visible().
##
## P16 (FOLLOWUPS, wave 6 merge): the plan's 640 px bar overlapped the quest tracker (top right,
## 340 px wide) by 36 px at 1280 px; at 540 px (HALF_WIDTH 270) it keeps a 14 px gap from the
## tracker at 1280 x 720 and more at any wider screen, and clears the checkpoint toast (top left).
## P27 (plan M6-M9 §2.14): (-HALF_WIDTH..HALF_WIDTH, 44..88), 30 px lower, under the compass; drawn by
## HudKit's rules (rectangles: the panel, the bar, the pips and the notches are one batch).

const PIP_FILLED := Color(0.95, 0.72, 0.30)
const PIP_EMPTY := Color(0.30, 0.30, 0.34)
const BAR_COLOR := Color(0.72, 0.16, 0.14)
const MAX_PIPS := 6
const HALF_WIDTH := 270.0
## The bar's top edge (P27: 14 + 30, under the compass).
const TOP := 44.0

var _panel: PanelContainer
var _name: Label
var _bar: ProgressBar
var _notches: Control
var _pips: Array[ColorRect] = []
var _boss_id := ""
var _text := ""


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_panel = HudKit.panel(Color(0.06, 0.05, 0.06, 0.84))
	_panel.anchor_left = 0.5
	_panel.anchor_right = 0.5
	_panel.offset_left = -HALF_WIDTH
	_panel.offset_right = HALF_WIDTH
	_panel.offset_top = TOP
	_panel.offset_bottom = TOP + 44
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.visible = false
	add_child(_panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 3)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(v)
	var top := HBoxContainer.new()
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(top)
	_name = HudKit.label("", HudKit.TEXT, UiKit.TEXT)
	_name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(_name)
	var pips := HBoxContainer.new()
	pips.add_theme_constant_override("separation", 5)
	pips.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(pips)
	for i in MAX_PIPS:
		var pip := HudKit.rect(PIP_EMPTY)
		pip.custom_minimum_size = Vector2(12, 12)
		pip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		pip.visible = false
		pips.add_child(pip)
		_pips.append(pip)
	var stack := Control.new()
	stack.custom_minimum_size = Vector2(0, 12)
	stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(stack)
	_bar = HudKit.bar(BAR_COLOR, 12)
	_bar.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	stack.add_child(_bar)
	_notches = Notches.new()
	_notches.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_notches.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stack.add_child(_notches)
	Events.boss_engaged.connect(_on_boss_engaged)
	Events.boss_defeated.connect(_on_boss_defeated)


func _on_boss_engaged(_tick: int, boss_id: String) -> void:
	_boss_id = boss_id


func _on_boss_defeated(_tick: int, boss_id: String) -> void:
	if boss_id == _boss_id:
		_boss_id = ""


## The boss the bar follows now: the engaged boss while it lives, otherwise the player's locked
## target when it is a living member of group "bosses"; null when none.
func current_boss() -> CombatEntity:
	var e := Sim.get_entity(_boss_id) if _boss_id != "" else null
	if e != null and e.is_alive() and is_instance_valid(e.actor):
		return e
	var p := player()
	if p != null:
		var t := p.locked_entity()
		if t != null and t.is_alive() and is_instance_valid(t.actor) and t.actor.is_in_group("bosses"):
			return t
	return null


## True while the bar shows `e` (Hud hides its target frame then).
func shows_entity(e: CombatEntity) -> bool:
	return e != null and e == current_boss()


## True while the bar is on screen (P16: Hud puts the target frame below it then).
func bar_visible() -> bool:
	return _panel != null and _panel.visible


func layout_controls() -> Dictionary:
	return {"boss_bar": _panel}


## What the bar shows ("" while hidden): "Ogre King  1210 / 1500  phase 1/2".
func visible_text() -> String:
	return _text


## The phase pips: true for each phase reached ([] while hidden).
func phase_pips() -> Array[bool]:
	var out: Array[bool] = []
	if not _panel.visible:
		return out
	for pip in _pips:
		if pip.visible:
			out.append(pip.color == PIP_FILLED)
	return out


## The phase thresholds (health fractions below 1) of a boss record, for the bar's notches.
static func phase_thresholds(record: Dictionary) -> Array[float]:
	var out: Array[float] = []
	var boss: Variant = record.get("boss")
	if typeof(boss) == TYPE_DICTIONARY and typeof(boss.get("phases")) == TYPE_ARRAY:
		for p: Variant in boss.phases:
			if typeof(p) == TYPE_DICTIONARY:
				var f := float(p.get("health_frac_below", 1.0))
				if f < 1.0:
					out.append(f)
	return out


func _process(_delta: float) -> void:
	var b := current_boss()
	if b == null:
		_panel.visible = false
		_text = ""
		return
	_panel.visible = true
	var pools := b.combatant.pools
	_bar.value = pools.health / maxf(pools.health_max, 0.001)
	var phase := int(b.actor.call("boss_phase")) if b.actor.has_method("boss_phase") else 1
	var count := int(b.actor.call("phase_count")) if b.actor.has_method("phase_count") else 1
	for i in _pips.size():
		_pips[i].visible = i < count
		_pips[i].color = PIP_FILLED if i < phase else PIP_EMPTY
	(_notches as Notches).fractions = phase_thresholds(GameData.get_record(b.definition_id))
	_name.text = b.display_name()
	_text = "%s  %d / %d  phase %d/%d" % [b.display_name(), ceili(pools.health), int(pools.health_max),
		phase, count]


## Thin marks across the bar at each phase threshold.
class Notches:
	extends Control

	var fractions: Array[float] = []:
		set(value):
			if value != fractions:
				fractions = value
				queue_redraw()

	func _draw() -> void:
		for f in fractions:
			var x := size.x * clampf(f, 0.0, 1.0)
			draw_rect(Rect2(x - 1.0, 0.0, 2.0, size.y), Color(1.0, 0.92, 0.7, 0.9))
