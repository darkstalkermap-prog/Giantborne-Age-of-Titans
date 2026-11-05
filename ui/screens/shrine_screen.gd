class_name ShrineScreen
extends UiScreen
## The shrine screen (P05, plan §2.10.2): opened by ScreenStack as SCREENS["shrine"] when a
## Shrine is used (Events.ui_screen_requested("shrine", {"shrine": shrine})). It pauses the
## game. A header names the shrine and shows the giant's stage and pools; a row of tab buttons
## switches between the tabs of TABS whose file exists and whose available() is true; Leave
## (or Esc / pad B) closes it.
##
## TABS is pre-declared: P12 adds the Loadout and Attributes tabs by creating their files
## (ShrineTab subclasses), without editing this list.

## [title, path]; a missing file is skipped (its package has not landed yet).
const TABS := [
	["Rest", "res://ui/screens/shrine/rest_tab.gd"],               # P05
	["Grow", "res://ui/screens/shrine/grow_tab.gd"],               # P05
	["Loadout", "res://ui/screens/shrine/loadout_tab.gd"],         # P12
	["Attributes", "res://ui/screens/shrine/attributes_tab.gd"],   # P12
]

var shrine: Shrine
var player: GiantPlayer
## The tabs in TABS order (only those available).
var tabs: Array[ShrineTab] = []
var _buttons: Array[Button] = []
var _holder: MarginContainer
var _header: Label
var _current := -1
var _leave: Button


func _ready() -> void:
	shrine = args.get("shrine") as Shrine
	player = args.get("player") as GiantPlayer
	if player == null and is_inside_tree():
		player = get_tree().get_first_node_in_group("player") as GiantPlayer
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.5)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(shade)
	var panel := UiKit.panel(Color(0.07, 0.09, 0.10, 0.97))
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	panel.offset_left = -380
	panel.offset_right = 380
	panel.offset_top = -290
	panel.offset_bottom = 290
	add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	panel.add_child(v)
	var title := UiKit.label(shrine.display_name() if shrine != null else "Shrine", 28)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(title)
	_header = UiKit.label("", 14, UiKit.MUTED)
	_header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(_header)
	var bar := HBoxContainer.new()
	bar.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_child(bar)
	_holder = MarginContainer.new()
	_holder.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(_holder)
	for entry: Array in TABS:
		var tab := _make_tab(str(entry[1]))
		if tab == null:
			continue
		tab.name = str(entry[0])
		tab.setup(self)
		if not tab.available():
			tab.free()
			continue
		tab.visible = false
		_holder.add_child(tab)
		tabs.append(tab)
		var b := UiKit.button(tab.tab_title(), 17)
		b.pressed.connect(show_tab.bind(tabs.size() - 1))
		bar.add_child(b)
		_buttons.append(b)
	_leave = UiKit.button("Leave", 18)
	_leave.pressed.connect(cancel)
	v.add_child(_leave)
	if not tabs.is_empty():
		show_tab(0)


static func _make_tab(path: String) -> ShrineTab:
	if not ResourceLoader.exists(path):
		return null
	var script := load(path) as Script
	if script == null:
		return null
	var t: Variant = script.new()
	if not t is ShrineTab:
		push_warning("ShrineScreen: %s is not a ShrineTab" % path)
		if t is Node:
			(t as Node).free()
		return null
	return t


func first_focus() -> Control:
	if _current >= 0 and _current < tabs.size():
		var f := tabs[_current].first_focus()
		if f != null:
			return f
	return _buttons[0] if not _buttons.is_empty() else _leave


func on_open() -> void:
	notify_changed()


## Shows tab `index` (TABS order among the available ones) and refreshes it.
func show_tab(index: int) -> void:
	if index < 0 or index >= tabs.size():
		return
	_current = index
	for i in tabs.size():
		tabs[i].visible = i == index
	tabs[index].refresh()
	var f := tabs[index].first_focus()
	if f != null and f.is_inside_tree() and f.is_visible_in_tree():
		f.grab_focus()


## The tab titled `title` ("Rest", "Grow", ...), or null.
func tab(title: String) -> ShrineTab:
	for t in tabs:
		if t.tab_title() == title:
			return t
	return null


func current_tab() -> ShrineTab:
	return tabs[_current] if _current >= 0 and _current < tabs.size() else null


## A tab changed the game (rested, grew, ...): refresh the header and every tab.
func notify_changed() -> void:
	if _header != null and player != null and is_instance_valid(player):
		var pools := player.entity.combatant.pools
		_header.text = "Stage %d  %s    Health %d / %d" % [player.growth_stage,
			str(player.profile.get("display_name", "")), roundi(pools.health), roundi(pools.health_max)]
	for t in tabs:
		t.refresh()
