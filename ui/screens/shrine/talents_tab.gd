extends ShrineTab
## Shrine screen tab "Talents" (P33, plan M6-M9 §3.17, §5.12, decision 22): the three talent trees
## side by side - Destroyer (melee, grabs and stagger), Guardian (protection and poise), Primordial
## (magic and fury) - each a ladder of two columns over tiers 1-4 with its capstone (the tree's
## crown) below. A talent is drawn learned (green), ready to learn (bright) or not yet (grey).
##
## The detail box under the trees explains the talent the focus is on (a click focuses): its tree, tier
## and the level the tier opens at, its cost, everything it does (Talents.effect_lines: each passive
## and each ability it teaches, with what the ability does and costs) and whether it can be learned
## now - or exactly why not ("opens at level 8", "needs Heavy Hands first", "costs 1 talent point").
## Pressing a talent (A / Enter / click) selects it and puts the focus on "Learn <name>"; Learn
## spends the point (PlayerProgression.learn_talent: permanent) and gives the focus back to the
## talent. The bottom line adds up every passive the talents and the ancestry give now.
##
## Shown at every shrine whenever the giant has a progression component (P33: "Talents (always)").
## Pad and keyboard: one row per tier (left / right across the columns and trees, up / down between
## tiers; the capstones' row last), then Learn; every direction wraps (UiNav).
##
## M8 gate (F17): the passives line shows at most PASSIVE_LINES lines (the most passives a level-20
## giant can gather fill four), ending in an ellipsis past them with the whole list as its tooltip, so
## the shrine panel stays inside a 1280 x 720 window at any level (shrine_screen.gd).

const STATE_COLORS := {"learned": UiKit.GOOD, "available": UiKit.TEXT, "locked": UiKit.MUTED}
## M8 gate (F17): the passives line's most lines.
const PASSIVE_LINES := 4
## The tree headers' colours (Destroyer red, Guardian stone, Primordial violet).
const TREE_COLORS := {"destroyer": Color(1.0, 0.62, 0.5), "guardian": Color(0.78, 0.82, 0.9),
	"primordial": Color(0.78, 0.62, 1.0)}

## Talent id -> its Button.
var buttons: Dictionary = {}
## The talent shown in the detail box ("" before any).
var selected := ""
var learn_button: Button
var _rows: Array = []
var _points: Label
var _detail_title: Label
var _detail_body: Label
var _detail_state: Label
var _result: Label
var _passives: Label


func tab_title() -> String:
	return "Talents"


func available() -> bool:
	var p := player()
	return p != null and p.progression != null and p.progression.has_method("learn_talent")


func _ready() -> void:
	add_theme_constant_override("separation", 5)
	_points = UiKit.label("", 16)
	add_child(_points)
	var intro := UiKit.label("You gain a talent point with every level. A talent needs the one above it in its column, and a tree's crown needs both talents of its tier 4. Talents are permanent. Green: learned · white: ready to learn · grey: not yet (select one to see why).", 12, UiKit.MUTED)
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(intro)
	var trees := HBoxContainer.new()
	trees.add_theme_constant_override("separation", 12)
	add_child(trees)
	var tier_rows: Array = []
	for tier in range(1, Talents.TIER_COUNT + 1):
		tier_rows.append([])
	for tree: String in Talents.TREES:
		var col := VBoxContainer.new()
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		col.add_theme_constant_override("separation", 3)
		trees.add_child(col)
		var info: Array = Talents.TREE_INFO.get(tree, [tree.capitalize(), ""])
		var header := UiKit.label(str(info[0]).to_upper(), 14, TREE_COLORS.get(tree, UiKit.TEXT))
		header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		col.add_child(header)
		var sub := UiKit.label(str(info[1]), 11, UiKit.MUTED)
		sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		col.add_child(sub)
		var grid := GridContainer.new()
		grid.columns = 2
		grid.add_theme_constant_override("h_separation", 4)
		grid.add_theme_constant_override("v_separation", 3)
		col.add_child(grid)
		for tier in range(1, Talents.TIER_COUNT):
			var ids := Talents.at_tier(tree, tier)
			for i in 2:
				if i < ids.size():
					var b := _talent_button(str(ids[i]))
					grid.add_child(b)
					(tier_rows[tier - 1] as Array).append(b)
				else:
					grid.add_child(Control.new())
		var crown := HBoxContainer.new()
		crown.alignment = BoxContainer.ALIGNMENT_CENTER
		col.add_child(crown)
		for id: Variant in Talents.at_tier(tree, Talents.TIER_COUNT):
			var b := _talent_button(str(id))
			b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
			b.custom_minimum_size = Vector2(130, 26)
			crown.add_child(b)
			(tier_rows[Talents.TIER_COUNT - 1] as Array).append(b)
	_rows = tier_rows
	var detail := UiKit.panel(UiKit.BG_LIGHT)
	add_child(detail)
	var dv := VBoxContainer.new()
	dv.add_theme_constant_override("separation", 3)
	detail.add_child(dv)
	_detail_title = UiKit.label("", 15)
	dv.add_child(_detail_title)
	_detail_body = UiKit.label("", 12)
	_detail_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail_body.custom_minimum_size = Vector2(0, 32)
	dv.add_child(_detail_body)
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 10)
	dv.add_child(line)
	_detail_state = UiKit.label("", 13, UiKit.MUTED)
	_detail_state.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_detail_state.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	line.add_child(_detail_state)
	learn_button = UiKit.button("Learn", 15)
	learn_button.pressed.connect(learn_selected)
	line.add_child(learn_button)
	_result = UiKit.label("", 13, UiKit.GOOD)
	_result.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_result)
	_passives = UiKit.label("", 12, UiKit.MUTED)
	_passives.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_passives.max_lines_visible = PASSIVE_LINES
	_passives.text_overrun_behavior = TextServer.OVERRUN_TRIM_WORD_ELLIPSIS
	_passives.mouse_filter = Control.MOUSE_FILTER_PASS   # its tooltip holds the whole list
	add_child(_passives)
	refresh()


func _talent_button(id: String) -> Button:
	var b := UiKit.button(Talents.display_name(id), 12)
	b.custom_minimum_size = Vector2(0, 26)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.clip_text = true
	b.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	b.tooltip_text = Talents.display_name(id)
	b.pressed.connect(press_talent.bind(id))
	b.focus_entered.connect(show_detail.bind(id))   # a click focuses too: the detail follows the focus
	buttons[id] = b
	return b


func _progression() -> Variant:
	var p := player()
	return p.progression if p != null and is_instance_valid(p) else null


## "learned", "available" (can be learned now) or "locked" (not yet: level, requirement or points).
func state_of(id: String) -> String:
	var prog: Variant = _progression()
	if prog == null:
		return "locked"
	if prog.knows_talent(id):
		return "learned"
	return "available" if bool(prog.can_learn_talent(id).ok) else "locked"


func first_focus() -> Control:
	for row: Array in _rows:
		for b: Button in row:
			if state_of(_id_of(b)) == "available":
				return b
	return _rows[0][0] if not _rows.is_empty() and not (_rows[0] as Array).is_empty() else null


## One row per tier (the capstones last), then Learn (P16 conventions).
func focus_rows() -> Array:
	var rows: Array = []
	for row: Array in _rows:
		rows.append(row.duplicate())
	rows.append([learn_button])
	return rows


func _id_of(b: Button) -> String:
	for id: Variant in buttons:
		if buttons[id] == b:
			return str(id)
	return ""


func refresh() -> void:
	var prog: Variant = _progression()
	if prog == null or _points == null:
		return
	var levels := Talents.tier_levels()
	_points.text = "Talent points: %d      Tiers open at levels %s" % [int(prog.talent_points),
		", ".join(PackedStringArray(levels.map(func(v: Variant) -> String: return str(v))))]
	for id: Variant in buttons:
		var b: Button = buttons[id]
		var color: Color = STATE_COLORS[state_of(str(id))]
		for key: String in ["font_color", "font_hover_color", "font_focus_color", "font_pressed_color"]:
			b.add_theme_color_override(key, color)
	if selected == "" and first_focus() != null:
		selected = _id_of(first_focus() as Button)
	show_detail(selected)
	var lines: PackedStringArray = prog.passive_lines()
	_passives.text = "Your talents and ancestry now: " + ("none yet" if lines.is_empty() else "  ·  ".join(lines))
	_passives.tooltip_text = "\n".join(lines) if not lines.is_empty() else ""


## Shows talent `id` in the detail box (the focus calls it): tree, tier, level, cost, effects
## and whether it can be learned now; Learn names it and works only when it can.
func show_detail(id: String) -> void:
	if _detail_title == null or id == "" or Talents.record(id).is_empty():
		return
	selected = id
	var prog: Variant = _progression()
	var tree := Talents.tree_of(id)
	var tier := Talents.tier_of(id)
	var cost := Talents.cost_of(id)
	var info: Array = Talents.TREE_INFO.get(tree, [tree.capitalize(), ""])
	_detail_title.text = "%s — %s, %s (level %d), %d point%s" % [Talents.display_name(id), str(info[0]),
		"crown" if tier == Talents.TIER_COUNT else "tier %d" % tier, Talents.level_needed(id), cost,
		"" if cost == 1 else "s"]
	var body := PackedStringArray()
	var desc := str(Talents.record(id).get("description", ""))
	if desc != "":
		body.append(desc)
	body.append_array(Talents.effect_lines(id))
	_detail_body.text = "\n".join(body)
	var state := state_of(id)
	learn_button.text = "Learn %s" % Talents.display_name(id)
	learn_button.disabled = state != "available"
	match state:
		"learned":
			_set_label(_detail_state, "Learned.", UiKit.GOOD)
		"available":
			_set_label(_detail_state, "Ready to learn. Talents last for good.", UiKit.TEXT)
		_:
			var why: Dictionary = prog.can_learn_talent(id) if prog != null else {"message": ""}
			_set_label(_detail_state, str(why.get("message", "")), UiKit.WARN)


## A press on talent `id`: it is selected, and when it can be learned the focus moves to Learn.
func press_talent(id: String) -> void:
	show_detail(id)
	if not learn_button.disabled and learn_button.is_inside_tree():
		learn_button.grab_focus()


## Learns the selected talent (PlayerProgression.learn_talent), shows the result, refreshes the
## screen and gives the focus back to the talent. Its result ({ok, reason, message, ...}).
func learn_selected() -> Dictionary:
	var prog: Variant = _progression()
	if prog == null or selected == "":
		return {"ok": false, "reason": "unknown", "message": ""}
	var id := selected
	var out: Dictionary = prog.learn_talent(id)
	_set_label(_result, str(out.get("message", "")), UiKit.GOOD if out.ok else UiKit.WARN)
	if out.ok and not (out.get("learned", []) as Array).is_empty():
		_result.text += ". " + str(prog.slot_hint(str(out.learned[0])))   # "It is on slot 8." / the Loadout tab
	if screen != null:
		screen.notify_changed()
	else:
		refresh()
	var b: Button = buttons.get(id)
	if b != null and b.is_inside_tree():
		b.grab_focus()
	return out


## Selects and learns `id` (tests and tools): press_talent then learn_selected.
func learn(id: String) -> Dictionary:
	press_talent(id)
	return learn_selected()


func detail_text() -> String:
	if _detail_title == null:
		return ""
	return "%s\n%s\n%s" % [_detail_title.text, _detail_body.text, _detail_state.text]


func points_text() -> String:
	return _points.text if _points != null else ""


func passives_text() -> String:
	return _passives.text if _passives != null else ""


func result_text() -> String:
	return _result.text if _result != null else ""


func _set_label(l: Label, text: String, color: Color) -> void:
	if l == null:
		return
	l.text = text
	l.add_theme_color_override("font_color", color)
