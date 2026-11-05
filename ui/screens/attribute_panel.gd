class_name AttributePanel
extends VBoxContainer
## Attribute allocation with a derived preview (plan §3.14 design 5; P12), shared by the Attributes
## screen and the shrine's Attributes tab. One row per attribute (name, value, [-], the points
## planned for it, [+], its effect), the unspent points, the derived values now -> with the planned
## points (health, stamina, essence, poise, attack recovery, elemental resistance, damage), Confirm
## (PlayerProgression.allocate) and Reset, the ancestry line "Ancestry: Unaligned — no modifiers in
## the prototype", the talent points and the prototype pacing label.
##
## Reads and changes the game only through player.progression. Call setup(player) before it enters
## the tree; refresh() re-reads everything. Tests use add_point / remove_point / confirm / reset and
## the text getters.

## After a successful confirm() (the points were spent): hosts refresh what they show.
signal allocated(result: Dictionary)

var player: GiantPlayer
## attribute -> points planned (not spent yet).
var pending: Dictionary = {}
var _points: Label
var _rows: Dictionary = {}       ## attribute -> {"value": Label, "plan": Label, "minus": Button, "plus": Button}
var _preview: Label
var _result: Label
var _ancestry: Label
var _talents: Label
var confirm_button: Button
var reset_button: Button


func setup(p: GiantPlayer) -> void:
	player = p


func _ready() -> void:
	add_theme_constant_override("separation", 6)
	_points = UiKit.label("", 17)
	add_child(_points)
	var grid := GridContainer.new()
	grid.columns = 6
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 4)
	add_child(grid)
	for key: String in Progression.ATTRIBUTE_KEYS:
		var name_label := UiKit.label(Progression.attribute_name(key), 16)
		name_label.custom_minimum_size = Vector2(120, 0)
		grid.add_child(name_label)
		var value := UiKit.label("", 16)
		value.custom_minimum_size = Vector2(30, 0)
		grid.add_child(value)
		var minus := UiKit.button("-", 15)
		minus.custom_minimum_size = Vector2(32, 0)
		minus.pressed.connect(remove_point.bind(key))
		grid.add_child(minus)
		var plan := UiKit.label("", 15, UiKit.GOOD)
		plan.custom_minimum_size = Vector2(30, 0)
		grid.add_child(plan)
		var plus := UiKit.button("+", 15)
		plus.custom_minimum_size = Vector2(32, 0)
		plus.pressed.connect(add_point.bind(key))
		grid.add_child(plus)
		var effect := UiKit.label(Progression.attribute_effect(key), 12, UiKit.MUTED)
		grid.add_child(effect)
		_rows[key] = {"value": value, "plan": plan, "minus": minus, "plus": plus}
	_preview = UiKit.label("", 14)
	_preview.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_preview)
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 10)
	add_child(buttons)
	confirm_button = UiKit.button("Confirm", 17)
	confirm_button.pressed.connect(_on_confirm)
	buttons.add_child(confirm_button)
	reset_button = UiKit.button("Reset", 17)
	reset_button.pressed.connect(reset)
	buttons.add_child(reset_button)
	_result = UiKit.label("", 14, UiKit.GOOD)
	_result.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_result)
	_ancestry = UiKit.label("", 14, UiKit.MUTED)
	add_child(_ancestry)
	_talents = UiKit.label("", 13, UiKit.MUTED)
	_talents.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_talents)
	refresh()


func _progression() -> Variant:
	if player == null or not is_instance_valid(player):
		return null
	return player.progression


## Points planned but not spent yet.
func planned_total() -> int:
	var n := 0
	for key: Variant in pending:
		n += int(pending[key])
	return n


func unspent() -> int:
	var prog: Variant = _progression()
	return int(prog.unspent_attribute_points) if prog != null else 0


## Plans one more point for `key` (when a point is left). True when it was planned.
func add_point(key: String) -> bool:
	if _progression() == null or not Progression.ATTRIBUTE_KEYS.has(key) or planned_total() >= unspent():
		return false
	pending[key] = int(pending.get(key, 0)) + 1
	refresh()
	return true


## Takes back one planned point of `key` (spent points stay spent). True when one was taken back.
func remove_point(key: String) -> bool:
	if int(pending.get(key, 0)) <= 0:
		return false
	pending[key] = int(pending[key]) - 1
	if int(pending[key]) == 0:
		pending.erase(key)
	refresh()
	return true


func reset() -> void:
	pending.clear()
	_set_result("", UiKit.GOOD)
	refresh()


## Spends the planned points (PlayerProgression.allocate). Its result.
func confirm() -> Dictionary:
	var prog: Variant = _progression()
	if prog == null:
		return {"ok": false, "reason": "no_player", "message": ""}
	var out: Dictionary = prog.allocate(pending.duplicate())
	_set_result(str(out.get("message", "")), UiKit.GOOD if out.ok else UiKit.WARN)
	if out.ok:
		pending.clear()
	refresh()
	if out.ok:
		allocated.emit(out)
	return out


func _on_confirm() -> void:
	confirm()


func refresh() -> void:
	if _points == null:
		return
	var prog: Variant = _progression()
	if prog == null:
		_points.text = "No attributes to show."
		return
	var attrs: Dictionary = prog.attributes()
	var left := unspent() - planned_total()
	_points.text = "Unspent attribute points: %d" % left if planned_total() == 0 \
		else "Unspent attribute points: %d (%d planned)" % [left, planned_total()]
	for key: String in Progression.ATTRIBUTE_KEYS:
		var row: Dictionary = _rows[key]
		var plan := int(pending.get(key, 0))
		(row.value as Label).text = str(int(attrs[key]))
		(row.plan as Label).text = "+%d" % plan if plan > 0 else ""
		(row.minus as Button).disabled = plan <= 0
		(row.plus as Button).disabled = left <= 0
	_preview.text = preview_text()
	confirm_button.disabled = planned_total() <= 0
	reset_button.disabled = planned_total() <= 0
	_ancestry.text = str(prog.ancestry_line())
	_talents.text = "Talent points: %d (talent trees are a full-game feature)" % int(prog.talent_points)


## "Health 530 -> 545   Stamina ..." (now -> with the planned points; a value without a change
## shows once).
func preview_text() -> String:
	var prog: Variant = _progression()
	if prog == null:
		return ""
	var now: Dictionary = prog.derived_preview({})
	var then: Dictionary = prog.derived_preview(pending)
	var parts := PackedStringArray()
	parts.append(_pair("Health", now.health, then.health, "%d"))
	parts.append(_pair("Stamina", now.stamina, then.stamina, "%d"))
	parts.append(_pair("Essence", now.essence, then.essence, "%d"))
	parts.append(_pair("Poise", now.poise, then.poise, "%d"))
	parts.append(_pair("Attack recovery", -100.0 * float(now.recovery_reduction), -100.0 * float(then.recovery_reduction), "%+.1f%%"))
	parts.append(_pair("Elemental resistance", 100.0 * float(now.elemental_resistance), 100.0 * float(then.elemental_resistance), "+%.1f"))
	parts.append(_pair("Damage", float(now.damage_scale), float(then.damage_scale), "x%.3f"))
	return "   ".join(parts)


static func _pair(label: String, a: Variant, b: Variant, fmt: String) -> String:
	var sa := _fmt(fmt, float(a))
	if is_equal_approx(float(a), float(b)):
		return "%s %s" % [label, sa]
	return "%s %s -> %s" % [label, sa, _fmt(fmt, float(b))]


static func _fmt(fmt: String, v: float) -> String:
	if fmt == "%d":
		return "%d" % roundi(v)
	return fmt % v


func result_text() -> String:
	return _result.text if _result != null else ""


func ancestry_text() -> String:
	return _ancestry.text if _ancestry != null else ""


func talent_text() -> String:
	return _talents.text if _talents != null else ""


func points_text() -> String:
	return _points.text if _points != null else ""


func first_focus() -> Control:
	for key: String in Progression.ATTRIBUTE_KEYS:
		var b: Button = _rows[key].plus
		if not b.disabled:
			return b
	return confirm_button if confirm_button != null and not confirm_button.disabled else reset_button


func _set_result(text: String, color: Color) -> void:
	if _result == null:
		return
	_result.text = text
	_result.add_theme_color_override("font_color", color)
