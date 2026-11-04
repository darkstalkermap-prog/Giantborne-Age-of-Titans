class_name Hud
extends Control
## In-game HUD: health/stamina/essence/fury, the 8-slot hotbar plus ultimate (cost, cooldown,
## key binding, unavailable reason), crosshair, lock-on marker and target frame, messages,
## death overlay and the F1 controls overlay. Reads state; never changes gameplay.

const MESSAGE_LIFETIME := 2.6

var player: GiantPlayer
var _bars: Dictionary = {}
var _bar_labels: Dictionary = {}
var _slots: Array[Dictionary] = []
var _crosshair: Control
var _marker: Control
var _target_frame: PanelContainer
var _target_name: Label
var _target_bar: ProgressBar
var _target_hint: Label
var _messages: VBoxContainer
var _death: Control
var _help: PanelContainer
var _help_label: Label
var _mode_label: Label
var _loot_label: Label
var _last_message := ""
var _last_message_time := -10.0
var _time := 0.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_resources()
	_build_hotbar()
	_build_center()
	_build_target_frame()
	_build_messages()
	_build_death()
	_build_help()
	Events.hud_message.connect(show_message)
	Events.loot_awarded.connect(_on_loot)
	Events.object_destroyed.connect(_on_object_destroyed)
	Events.camera_mode_changed.connect(_on_camera_mode_changed)


func _on_object_destroyed(_tick: int, world_id: String, _by: String) -> void:
	show_message("Destroyed: %s" % world_id.get_slice(".", 1).replace("_", " "), "info")


func _on_camera_mode_changed(_mode: int) -> void:
	_refresh_mode_label()


func _build_resources() -> void:
	var p := UiKit.panel()
	p.position = Vector2(16, 0)
	p.anchor_top = 1.0
	p.anchor_bottom = 1.0
	p.offset_top = -150
	p.offset_bottom = -16
	p.offset_left = 16
	p.offset_right = 340
	add_child(p)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 5)
	p.add_child(v)
	for spec: Array in [["health", "Health", UiKit.HEALTH, 18], ["stamina", "Stamina", UiKit.STAMINA, 14],
			["essence", "Essence", UiKit.ESSENCE, 10], ["fury", "Fury", UiKit.FURY, 10]]:
		var row := HBoxContainer.new()
		var name_label := UiKit.label(spec[1], 13, UiKit.MUTED)
		name_label.custom_minimum_size = Vector2(62, 0)
		row.add_child(name_label)
		var stack := Control.new()
		stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		stack.custom_minimum_size = Vector2(0, spec[3])
		var b := UiKit.bar(spec[2], spec[3])
		b.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		stack.add_child(b)
		var value := UiKit.label("", 11)
		value.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		value.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		stack.add_child(value)
		row.add_child(stack)
		v.add_child(row)
		_bars[spec[0]] = b
		_bar_labels[spec[0]] = value
	_mode_label = UiKit.label("", 12, UiKit.MUTED)
	v.add_child(_mode_label)


func _build_hotbar() -> void:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 6)
	h.anchor_left = 0.5
	h.anchor_right = 0.5
	h.anchor_top = 1.0
	h.anchor_bottom = 1.0
	h.offset_left = -284
	h.offset_right = 284
	h.offset_top = -92
	h.offset_bottom = -16
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(h)
	for i in 9:
		var slot := _make_slot(i)
		h.add_child(slot.root)
		_slots.append(slot)
	_loot_label = UiKit.label("", 13, UiKit.MUTED)
	_loot_label.anchor_left = 1.0
	_loot_label.anchor_right = 1.0
	_loot_label.anchor_top = 1.0
	_loot_label.anchor_bottom = 1.0
	_loot_label.offset_left = -260
	_loot_label.offset_right = -16
	_loot_label.offset_top = -40
	_loot_label.offset_bottom = -16
	_loot_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	add_child(_loot_label)


func _make_slot(index: int) -> Dictionary:
	var root := PanelContainer.new()
	root.custom_minimum_size = Vector2(58, 60)
	root.add_theme_stylebox_override("panel", UiKit.box(UiKit.BG, 6))
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var stack := Control.new()
	stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(stack)
	var cooldown := ColorRect.new()
	cooldown.color = Color(0, 0, 0, 0.6)
	cooldown.anchor_right = 1.0
	cooldown.anchor_top = 1.0
	cooldown.anchor_bottom = 1.0
	cooldown.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stack.add_child(cooldown)
	var key := UiKit.label("", 11, UiKit.MUTED)
	key.position = Vector2(0, -2)
	stack.add_child(key)
	var title := UiKit.label("", 10)
	title.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	stack.add_child(title)
	var cost := UiKit.label("", 10, UiKit.STAMINA)
	cost.anchor_top = 1.0
	cost.anchor_bottom = 1.0
	cost.anchor_right = 1.0
	cost.offset_top = -14
	cost.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	stack.add_child(cost)
	var timer := UiKit.label("", 18)
	timer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	timer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	timer.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	stack.add_child(timer)
	var reason := UiKit.label("", 10, UiKit.BAD)
	reason.anchor_top = 1.0
	reason.anchor_bottom = 1.0
	reason.anchor_right = 1.0
	reason.offset_top = 2
	reason.offset_bottom = 16
	reason.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stack.add_child(reason)
	return {"root": root, "cooldown": cooldown, "key": key, "title": title, "cost": cost,
		"timer": timer, "reason": reason, "index": index}


func _build_center() -> void:
	_crosshair = Crosshair.new()
	_crosshair.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_crosshair.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_crosshair)
	_marker = LockMarker.new()
	_marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_marker.visible = false
	add_child(_marker)


func _build_target_frame() -> void:
	_target_frame = UiKit.panel()
	_target_frame.anchor_left = 0.5
	_target_frame.anchor_right = 0.5
	_target_frame.offset_left = -170
	_target_frame.offset_right = 170
	_target_frame.offset_top = 14
	_target_frame.offset_bottom = 74
	_target_frame.visible = false
	add_child(_target_frame)
	var v := VBoxContainer.new()
	_target_frame.add_child(v)
	_target_name = UiKit.label("", 15)
	_target_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(_target_name)
	_target_bar = UiKit.bar(UiKit.HEALTH, 10)
	v.add_child(_target_bar)
	_target_hint = UiKit.label("", 11, UiKit.MUTED)
	_target_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(_target_hint)


func _build_messages() -> void:
	_messages = VBoxContainer.new()
	_messages.anchor_left = 0.5
	_messages.anchor_right = 0.5
	_messages.anchor_top = 1.0
	_messages.anchor_bottom = 1.0
	_messages.offset_left = -300
	_messages.offset_right = 300
	_messages.offset_top = -200
	_messages.offset_bottom = -116
	_messages.alignment = BoxContainer.ALIGNMENT_END
	_messages.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_messages)


func _build_death() -> void:
	_death = ColorRect.new()
	(_death as ColorRect).color = Color(0.15, 0.0, 0.0, 0.55)
	_death.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_death.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_death.visible = false
	add_child(_death)
	var v := VBoxContainer.new()
	v.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	v.offset_left = -300
	v.offset_right = 300
	v.offset_top = -60
	v.offset_bottom = 60
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	_death.add_child(v)
	var title := UiKit.label("DEFEATED", 48, UiKit.BAD)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(title)
	var hint_text := "Press Enter to restart the sandbox"
	if OS.is_debug_build():
		hint_text += "   |   F5 debug reset"
	var hint := UiKit.label(hint_text, 18)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(hint)


func _build_help() -> void:
	_help = UiKit.panel(Color(0.05, 0.06, 0.08, 0.92))
	_help.anchor_left = 0.5
	_help.anchor_right = 0.5
	_help.anchor_top = 0.5
	_help.anchor_bottom = 0.5
	_help.offset_left = -330
	_help.offset_right = 330
	_help.offset_top = -270
	_help.offset_bottom = 270
	_help.visible = false
	add_child(_help)
	_help_label = UiKit.label("", 14)
	_help.add_child(_help_label)


func toggle_help() -> void:
	_help.visible = not _help.visible
	if _help.visible:
		_help_label.text = _controls_text()


func _controls_text() -> String:
	var rows := [
		["Move / look", "move_forward", "WASD + mouse; left / right stick"],
		["Light attack (3-hit chain)", "attack_light", ""],
		["Heavy attack", "heavy_modifier", "hold with light attack; pad RT"],
		["Block (tap = parry window)", "block", ""],
		["Dodge", "dodge", ""],
		["Jump", "jump", ""],
		["Sprint", "sprint", ""],
		["Lock target / switch", "lock_target", "wheel or right-stick flick while locked"],
		["Camera mode", "camera_toggle", "wheel zooms when not locked"],
		["Heavy Footfall (slot 1)", "ability_1", "pad: LT + A"],
		["Ultimate", "ultimate", "pad: LT + RT (none equipped in M1)"],
		["Pause / settings / rebind", "pause", ""],
		["Controls overlay", "help", ""],
	]
	var lines := PackedStringArray(["CONTROLS  (rebind in Pause > Controls)", ""])
	for r: Array in rows:
		var kb := InputBindings.describe_action(r[1], false)
		var pad := InputBindings.describe_action(r[1], true)
		var extra := ("   (%s)" % r[2]) if r[2] != "" else ""
		lines.append("%-30s %s  |  %s%s" % [r[0], kb, pad, extra])
	if OS.is_debug_build():
		lines.append("")
		lines.append("Debug: F3 panel, F5 reset sandbox")
	return "\n".join(lines)


func show_message(text: String, kind: String = "info") -> void:
	if text == _last_message and _time - _last_message_time < 0.6:
		return
	_last_message = text
	_last_message_time = _time
	var color := UiKit.TEXT
	match kind:
		"warn":
			color = UiKit.WARN
		"bad":
			color = UiKit.BAD
		"good":
			color = UiKit.GOOD
	var l := UiKit.label(text, 17, color)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.set_meta("born", _time)
	_messages.add_child(l)
	while _messages.get_child_count() > 3:
		var old := _messages.get_child(0)
		_messages.remove_child(old)
		old.queue_free()


func _on_loot(_tick: int, _world_id: String, item_id: String, count: int, _who: String) -> void:
	var item := GameData.get_record(item_id)
	show_message("+%d %s" % [count, item.get("display_name", item_id)], "good")


func _refresh_mode_label() -> void:
	if player == null:
		return
	_mode_label.text = "%s  [%s]   Stage %d   |   F1 controls" % [
		"First person" if player.camera_rig.is_first_person() else "Third person",
		InputBindings.describe_action("camera_toggle", false), player.growth_stage]


func _process(delta: float) -> void:
	_time += delta
	if player == null or not is_instance_valid(player):
		player = get_tree().get_first_node_in_group("player") as GiantPlayer
		if player == null:
			return
		_refresh_mode_label()
	_update_resources()
	_update_hotbar()
	_update_target()
	_update_messages()
	_death.visible = player.controller.state == CombatController.State.DEAD
	_crosshair.visible = not _death.visible
	var parts := PackedStringArray()
	for item_id: String in WorldState.inventory:
		parts.append("%s x%d" % [GameData.get_record(item_id).get("display_name", item_id), WorldState.inventory[item_id]])
	_loot_label.text = ("Loot: " + ", ".join(parts)) if not parts.is_empty() else ""


func _update_resources() -> void:
	var p := player.entity.combatant.pools
	var values := {"health": [p.health, p.health_max], "stamina": [p.stamina, p.stamina_max],
		"essence": [p.essence, p.essence_max], "fury": [p.fury, p.fury_max]}
	for key: String in values:
		var v: Array = values[key]
		(_bars[key] as ProgressBar).value = float(v[0]) / maxf(float(v[1]), 0.001)
		(_bar_labels[key] as Label).text = "%d / %d" % [ceili(v[0]) if key == "health" else floori(v[0]), int(v[1])]


func _update_hotbar() -> void:
	var c := player.controller
	var pools := player.entity.combatant.pools
	for slot: Dictionary in _slots:
		var i: int = slot.index
		var is_ultimate := i == 8
		var id := str(c.loadout.get("ultimate" if is_ultimate else "slot_%d" % (i + 1), ""))
		var def: ActionDef = c.library.get(id) if id != "" else null
		var kb := InputBindings.describe_action("ultimate" if is_ultimate else "ability_%d" % (i + 1), false)
		var pad: String = "LT+RT" if is_ultimate else "LT+" + str(["A", "B", "X", "Y", "Up", "Right", "Down", "Left"][i])
		(slot.key as Label).text = "%s  %s" % [kb, pad]
		var root: PanelContainer = slot.root
		if def == null:
			(slot.title as Label).text = "ULT" if is_ultimate else ""
			(slot.cost as Label).text = ""
			(slot.timer as Label).text = ""
			(slot.reason as Label).text = ""
			(slot.cooldown as ColorRect).offset_top = 0
			root.modulate = Color(1, 1, 1, 0.45)
			continue
		root.modulate = Color.WHITE
		(slot.title as Label).text = def.hotbar_label
		var costs := PackedStringArray()
		if def.stamina_cost > 0.0:
			costs.append("%d STA" % int(def.stamina_cost))
		if def.essence_cost > 0.0:
			costs.append("%d ESS" % int(def.essence_cost))
		if def.fury_cost > 0.0:
			costs.append("%d FUR" % int(def.fury_cost))
		(slot.cost as Label).text = " ".join(costs)
		var remaining := c.cooldowns.remaining_s(def.id, Sim.tick)
		var frac := c.cooldowns.remaining_fraction(def.id, Sim.tick)
		(slot.cooldown as ColorRect).offset_top = -60.0 * frac
		(slot.timer as Label).text = ("%.1f" % remaining) if remaining > 0.0 else ""
		var reason := ""
		if c.state == CombatController.State.DEAD:
			reason = "Dead"
		elif def.unlock_stage > c.growth_stage:
			reason = "Stage %d" % def.unlock_stage
		elif remaining > 0.0:
			reason = "Cooldown"
		elif pools.stamina + 1e-6 < def.stamina_cost:
			reason = "Stamina"
		elif pools.essence + 1e-6 < def.essence_cost:
			reason = "Essence"
		elif pools.fury + 1e-6 < def.fury_cost:
			reason = "Fury"
		elif c.is_committed():
			reason = "Busy"
		(slot.reason as Label).text = reason


func _update_target() -> void:
	var target := player.locked_entity()
	var cam := player.camera_rig.camera
	if target == null or not target.is_alive():
		_target_frame.visible = false
		_marker.visible = false
		return
	_target_frame.visible = true
	_target_name.text = "%s   %d m" % [target.display_name(), int(player.global_position.distance_to(target.actor.global_position))]
	var p := target.combatant.pools
	_target_bar.value = p.health / maxf(p.health_max, 0.001)
	_target_hint.text = "LOCKED  -  %s / %s to switch" % [InputBindings.describe_action("target_prev", false), "right stick"]
	var anchor := target.anchor_position()
	if cam != null and not cam.is_position_behind(anchor):
		_marker.visible = true
		_marker.position = cam.unproject_position(anchor) - Vector2(16, 16)
	else:
		_marker.visible = false


func _update_messages() -> void:
	for child in _messages.get_children():
		var age := _time - float(child.get_meta("born", _time))
		(child as Label).modulate.a = clampf((MESSAGE_LIFETIME - age) / 0.5, 0.0, 1.0)
		if age > MESSAGE_LIFETIME:
			child.queue_free()


class Crosshair:
	extends Control

	func _process(_delta: float) -> void:
		queue_redraw()

	func _draw() -> void:
		var c := size * 0.5
		draw_circle(c, 3.0, Color(1, 1, 1, 0.85))
		draw_arc(c, 9.0, 0.0, TAU, 24, Color(0, 0, 0, 0.45), 1.5)


class LockMarker:
	extends Control

	func _ready() -> void:
		size = Vector2(32, 32)

	func _draw() -> void:
		var c := Vector2(16, 16)
		var pts := PackedVector2Array([c + Vector2(0, -13), c + Vector2(13, 0), c + Vector2(0, 13), c + Vector2(-13, 0), c + Vector2(0, -13)])
		draw_polyline(pts, Color(1.0, 0.35, 0.25), 2.5)
		draw_circle(c, 2.5, Color(1.0, 0.35, 0.25))
