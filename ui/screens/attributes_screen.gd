class_name AttributesScreen
extends UiScreen
## The Attributes screen (plan §2.10.2, §3.14 design 5; P12): ScreenStack SCREENS["attributes"],
## opened from the inventory (or Events.ui_screen_requested("attributes", {})). It pauses the game
## and holds an AttributePanel: allocation with a derived preview, the ancestry line ("Ancestry:
## Unaligned — no modifiers in the prototype"), the talent points. Close (or Esc / pad B) closes it.
## args: {"player": GiantPlayer} (else the first node in group "player").

var player: GiantPlayer
var panel_ui: AttributePanel
var _close: Button


func _ready() -> void:
	player = args.get("player") as GiantPlayer
	if player == null and is_inside_tree():
		player = get_tree().get_first_node_in_group("player") as GiantPlayer
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.5)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(shade)
	var frame := UiKit.panel(Color(0.07, 0.09, 0.10, 0.97))
	frame.mouse_filter = Control.MOUSE_FILTER_STOP
	frame.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	frame.offset_left = -400
	frame.offset_right = 400
	frame.offset_top = -270
	frame.offset_bottom = 270
	add_child(frame)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	frame.add_child(v)
	var title := UiKit.label("Attributes", 28)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(title)
	var level := UiKit.label(level_line(player), 15, UiKit.MUTED)
	level.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(level)
	panel_ui = AttributePanel.new()
	panel_ui.setup(player)
	v.add_child(panel_ui)
	_close = UiKit.button("Close", 18)
	_close.pressed.connect(cancel)
	v.add_child(_close)


## "Level 3   XP 268 (18 / 200 to level 4)" for the giant's progression ("" without one).
static func level_line(p: GiantPlayer) -> String:
	if p == null or not is_instance_valid(p) or p.progression == null:
		return ""
	var prog: Variant = p.progression
	var progress: Array = prog.level_progress()
	if int(progress[1]) <= 0:
		return "Level %d (the level cap)   XP %d" % [int(prog.level), int(prog.xp)]
	return "Level %d   XP %d (%d / %d to level %d)" % [int(prog.level), int(prog.xp), int(progress[0]),
		int(progress[1]), int(prog.level) + 1]


func first_focus() -> Control:
	var f := panel_ui.first_focus() if panel_ui != null else null
	return f if f != null else _close


func on_open() -> void:
	if panel_ui != null:
		panel_ui.refresh()
