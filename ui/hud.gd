class_name Hud
extends Control
## In-game HUD: health/stamina/essence/fury, the 8-slot hotbar plus ultimate (cost, cooldown,
## key binding, unavailable reason, and the selected target of projectile slots), crosshair,
## lock-on marker and target frame, messages, death overlay and the F1 controls overlay. Reads
## state; never changes gameplay.
##
## Hotbar reasons come from CombatController.preview_reason (P03), the same evaluation a request
## gets, so the HUD can never disagree with the controller. A player component may add request
## parameters for a slot (a grab's precheck, P07) with preview_params(slot_key, def, params);
## the HUD passes them to preview_reason.
##
## P16 (UX pass):
## - Glyphs follow the last input device (InputBindings.last_device_is_pad): each hotbar slot shows
##   that device's binding large and the other one small; the mode line, the lock hint and the
##   F1 overlay name the device's buttons; the "click the game" hint only shows for a mouse player.
## - The F1 controls overlay is built from the live loadout (help_rows: movement and combat, every
##   filled slot and the ultimate, interact, inventory, pause, the overlay itself) as a table with a
##   keyboard and a controller column, the column of the device in use highlighted.
## - Layout: layout_regions(view) lists every fixed HUD region (this node's and each widget's) for a
##   screen size; at 1280 x 720 and 1920 x 1080 none overlap except where designed (test_hud_layout).
##   While the boss bar shows, the target frame of another locked target sits below it.
## M4 gate: the edge overlays (threat arrows, objective marker) are the last widgets, so they draw
## over every panel (under the death and help overlays), and they slide along the screen edge clear
## of the panels drawn now (overlay_keep_out, HudEdge.clear_of).
##
## P27 (plan M6-M9 §2.14, §3.10; FOLLOWUPS: the HUD's draw calls):
## - Every part is drawn by HudKit's rules - panels and bars as rectangles, text with a drop shadow
##   and no outline in three sizes, nothing clipped, absolute z layers (the HUD itself on
##   HudKit.Z_BACK, so whatever its widgets add without a layer of their own joins the rectangles) -
##   so a view's HUD costs one batch of rectangles and one per text size, not about 120 draw calls.
## - The compass sits at the top centre (4..28), so the target frame and the boss bar sit 30 px lower
##   (44..104; 94..154 under the bar) and the ability notice at 162..200.
## - The lock line shows PlayerTargeting.lock_label() (P30): "Pike Regiment (8)" for a formation, a
##   drawn flag before "Banner of the Toll-Riders" for its banner (the label's "⚑" is not in the
##   HUD's font), else the target's name; with the distance.
## - track_next (T / D-pad Left) tracks the next active quest (Quests.track_next) and says which.

const MESSAGE_LIFETIME := 2.6
## The target frame's top edge, and its top edge while the boss bar shows (below the bar's 88).
## P27: 30 px lower than P16's 14 / 64, under the compass.
const TARGET_FRAME_TOP := 44.0
const TARGET_FRAME_TOP_UNDER_BOSS := 94.0
const TARGET_FRAME_HEIGHT := 60.0
const HELP_TITLE := "CONTROLS  (rebind in Pause > Controls)"
## The banner mark P30's lock_label() puts before a banner's name (drawn as a flag instead).
const BANNER_MARK := "⚑"
const BANNER_FLAG_COLOR := Color(0.95, 0.72, 0.30)

var player: GiantPlayer
var _bars: Dictionary = {}
var _bar_labels: Dictionary = {}
var _slots: Array[Dictionary] = []
var _crosshair: Control
var _capture_hint: PanelContainer
var _marker: Control
var _target_frame: PanelContainer
var _target_name: Label
var _target_flag: Control
var _target_bar: ProgressBar
var _target_hint: Label
var _messages: VBoxContainer
var _death: Control
var _death_hint: Label
var _help: PanelContainer
var _help_label: Label
var _help_grid: GridContainer
var _help_rows: Array = []                 ## the rows shown now (help_rows())
var _help_signature := ""                  ## _help_key() when the overlay was built
var _mode_label: Label
var _loot_label: Label
var _hotbar: HBoxContainer
var _resources_panel: PanelContainer
var _labels_dirty := true
var _device_serial := -1
var _slot_states: Array[Dictionary] = []   ## per slot: {"id", "reason_code", "reason", "target"}
var _last_message := ""
var _last_message_time := -10.0
var _time := 0.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# P27: the HUD's base layer; every child that names no layer of its own draws with the rectangles.
	HudKit.set_z(self, HudKit.Z_BACK)
	_build_resources()
	_build_hotbar()
	_build_center()
	_build_target_frame()
	_build_messages()
	# Widgets from ui/hud/ (HudWidgets.WIDGETS; missing files skipped), under the death and
	# help overlays.
	HudWidgets.create_all(self)
	_build_death()
	_build_help()
	Events.hud_message.connect(show_message)
	Events.loot_awarded.connect(_on_loot)
	Events.object_destroyed.connect(_on_object_destroyed)
	Events.camera_mode_changed.connect(_on_camera_mode_changed)
	Events.growth_changed.connect(_on_growth_changed)
	Events.action_rejected.connect(_on_action_rejected)
	Settings.changed.connect(_on_settings_changed)


## P27: track_next (T / D-pad Left without LT) follows the next active quest and says which.
func _unhandled_input(event: InputEvent) -> void:
	if not InputMap.has_action("track_next") or not event.is_action_pressed("track_next"):
		return
	var text := track_next_now()
	if text != "":
		get_viewport().set_input_as_handled()


## Tracks the next active quest (Quests.track_next) and shows "Tracking: <quest>" (only one quest:
## "Tracking: <quest> (no other quest)"). Returns the line shown ("" when no quest is active).
func track_next_now() -> String:
	if not Quests.is_active():
		return ""
	var before := Quests.tracked_id()
	var id := Quests.track_next()
	if id == "":
		return ""
	var title := str(Quests.quest_record(id).get("display_name", id))
	var text := "Tracking: %s" % title + ("" if id != before else " (no other quest)")
	show_message(text, "info")
	return text


func _on_settings_changed(key: String) -> void:
	if key == "bindings":
		_labels_dirty = true
		_refresh_mode_label()


func _on_object_destroyed(_tick: int, world_id: String, _by: String) -> void:
	show_message("Destroyed: %s" % destroyed_name(world_id), "info")


## The name a destroyed prop's message shows (P18): its record's display name ("Practice Gate"),
## else the last part of its world id ("valley.forest.fence_pen" -> "fence pen"). The M1 text took
## the id's second part, which in the Valley is the district ("Destroyed: ruins").
func destroyed_name(world_id: String) -> String:
	for n in get_tree().get_nodes_in_group("breakables"):
		if str(n.get("world_id")) == world_id:
			var rec: Variant = n.get("record")
			if rec is Dictionary and str((rec as Dictionary).get("display_name", "")) != "":
				return str((rec as Dictionary).display_name)
	return world_id.get_slice(".", world_id.get_slice_count(".") - 1).replace("_", " ")


func _on_camera_mode_changed(_mode: int) -> void:
	_refresh_mode_label()


func _on_growth_changed(_tick: int, _entity_id: String, _old_stage: int, _new_stage: int) -> void:
	_refresh_mode_label()


## Notices for the rejection reasons GiantPlayer does not announce itself (it covers stamina,
## cooldown, empty slots and growth locks).
func _on_action_rejected(_tick: int, actor_id: String, action_id: String, reason: String) -> void:
	if player == null or not is_instance_valid(player) or actor_id != player.entity.entity_id:
		return
	var def := GameData.get_action(action_id)
	var label := def.display_name if def != null else action_id
	match reason:
		"essence":
			show_message("Not enough essence for %s" % label, "warn")
		"fury":
			show_message("%s needs %d fury" % [label, int(def.fury_cost) if def != null else 100], "warn")
		"level_locked":
			show_message("%s unlocks at level %d" % [label, def.unlock_level if def != null else 1], "warn")
		"out_of_range":
			show_message("%s: the target is out of range (%d m)" % [label,
				roundi(float(Projectile.spec_for(def).range_m)) if def != null else 0], "warn")
		"no_target":
			show_message("No target for %s" % label, "warn")


func _build_resources() -> void:
	var p := HudKit.panel()
	p.position = Vector2(16, 0)
	p.anchor_top = 1.0
	p.anchor_bottom = 1.0
	p.offset_top = -150
	p.offset_bottom = -16
	p.offset_left = 16
	p.offset_right = 340
	add_child(p)
	_resources_panel = p
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 5)
	p.add_child(v)
	for spec: Array in [["health", "Health", UiKit.HEALTH, 18], ["stamina", "Stamina", UiKit.STAMINA, 14],
			["essence", "Essence", UiKit.ESSENCE, 10], ["fury", "Fury", UiKit.FURY, 10]]:
		var row := HBoxContainer.new()
		var name_label := HudKit.label(spec[1], HudKit.TEXT, UiKit.MUTED)
		name_label.custom_minimum_size = Vector2(62, 0)
		row.add_child(name_label)
		var stack := Control.new()
		stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		stack.custom_minimum_size = Vector2(0, spec[3])
		var b := HudKit.bar(spec[2], spec[3])
		b.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		stack.add_child(b)
		var value := HudKit.label("", HudKit.SMALL)
		value.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		value.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		stack.add_child(value)
		row.add_child(stack)
		v.add_child(row)
		_bars[spec[0]] = b
		_bar_labels[spec[0]] = value
	_mode_label = HudKit.label("", HudKit.SMALL, UiKit.MUTED)
	_mode_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	v.add_child(_mode_label)


func _build_hotbar() -> void:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 6)
	h.anchor_left = 0.5
	h.anchor_right = 0.5
	h.anchor_top = 1.0
	h.anchor_bottom = 1.0
	# 9 slots of 58 px and 8 gaps of 6 px: 570 px (P16: the old 568 let the row grow 2 px right).
	h.offset_left = -285
	h.offset_right = 285
	h.offset_top = -92
	h.offset_bottom = -16
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(h)
	_hotbar = h
	for i in 9:
		var slot := _make_slot(i)
		h.add_child(slot.root)
		_slots.append(slot)
		_slot_states.append({"id": "", "reason_code": "", "reason": "", "target": "", "key": "", "alt_key": ""})
	_loot_label = HudKit.label("", HudKit.TEXT, UiKit.MUTED)
	_loot_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
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
	root.add_theme_stylebox_override("panel", HudKit.box(UiKit.BG))
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	HudKit.set_z(root, HudKit.Z_BACK)
	var stack := Control.new()
	stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(stack)
	var cooldown := HudKit.rect(Color(0, 0, 0, 0.6))
	cooldown.anchor_right = 1.0
	cooldown.anchor_top = 1.0
	cooldown.anchor_bottom = 1.0
	stack.add_child(cooldown)
	var key := HudKit.label("", HudKit.SMALL, UiKit.TEXT)
	key.position = Vector2(0, -4)
	stack.add_child(key)
	var pad := HudKit.label("", HudKit.SMALL, UiKit.MUTED)
	pad.anchor_left = 1.0
	pad.anchor_right = 1.0
	pad.offset_left = -40
	pad.offset_top = -4
	pad.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	stack.add_child(pad)
	var title := HudKit.label("", HudKit.SMALL)
	title.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	stack.add_child(title)
	var cost := HudKit.label("", HudKit.SMALL, UiKit.STAMINA)
	cost.anchor_top = 1.0
	cost.anchor_bottom = 1.0
	cost.anchor_right = 1.0
	cost.offset_top = -14
	cost.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cost.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	stack.add_child(cost)
	var timer := HudKit.label("", HudKit.BIG)
	timer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	timer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	timer.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	stack.add_child(timer)
	var reason := HudKit.label("", HudKit.SMALL, UiKit.BAD)
	reason.anchor_top = 1.0
	reason.anchor_bottom = 1.0
	reason.anchor_right = 1.0
	reason.offset_top = 8
	reason.offset_bottom = 22
	reason.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	# P16: a reason wider than the slot ("Out of range") grows to both sides, staying centred.
	reason.grow_horizontal = Control.GROW_DIRECTION_BOTH
	stack.add_child(reason)
	# Selected target of projectile slots ("» Soldier" when locked, otherwise "aim"), above the slot.
	var target := HudKit.label("", HudKit.SMALL, UiKit.TEXT)
	target.anchor_right = 1.0
	target.offset_left = -10
	target.offset_right = 10
	target.offset_top = -16
	target.offset_bottom = -4
	target.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	target.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	stack.add_child(target)
	return {"root": root, "cooldown": cooldown, "key": key, "pad": pad, "title": title, "cost": cost,
		"timer": timer, "reason": reason, "target": target, "index": index}


func _build_center() -> void:
	_capture_hint = HudKit.panel(Color(0.05, 0.06, 0.08, 0.85))
	_capture_hint.anchor_left = 0.5
	_capture_hint.anchor_right = 0.5
	_capture_hint.anchor_top = 0.5
	_capture_hint.anchor_bottom = 0.5
	_capture_hint.offset_left = -190
	_capture_hint.offset_right = 190
	_capture_hint.offset_top = 40
	_capture_hint.offset_bottom = 84
	var hint := HudKit.label("Click the game to control the camera", HudKit.BIG)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_capture_hint.add_child(hint)
	_capture_hint.visible = false
	add_child(_capture_hint)
	_crosshair = Crosshair.new()
	_crosshair.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_crosshair.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_crosshair)
	_marker = LockMarker.new()
	_marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_marker.visible = false
	add_child(_marker)


func _build_target_frame() -> void:
	_target_frame = HudKit.panel()
	_target_frame.anchor_left = 0.5
	_target_frame.anchor_right = 0.5
	_target_frame.offset_left = -170
	_target_frame.offset_right = 170
	_target_frame.offset_top = TARGET_FRAME_TOP
	_target_frame.offset_bottom = TARGET_FRAME_TOP + TARGET_FRAME_HEIGHT
	_target_frame.visible = false
	add_child(_target_frame)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 2)
	_target_frame.add_child(v)
	# P27: the lock line - a drawn flag before a banner's name (BannerFlag), then the label.
	var line := HBoxContainer.new()
	line.alignment = BoxContainer.ALIGNMENT_CENTER
	line.add_theme_constant_override("separation", 6)
	v.add_child(line)
	_target_flag = BannerFlag.new()
	_target_flag.custom_minimum_size = Vector2(12, 16)
	_target_flag.visible = false
	line.add_child(_target_flag)
	_target_name = HudKit.label("", HudKit.TEXT)
	_target_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_target_name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_target_name.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	line.add_child(_target_name)
	_target_bar = HudKit.bar(UiKit.HEALTH, 10)
	v.add_child(_target_bar)
	_target_hint = HudKit.label("", HudKit.SMALL, UiKit.MUTED)
	_target_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_target_hint.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
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
	HudKit.set_z(_death, HudKit.Z_DEATH)
	add_child(_death)
	var v := VBoxContainer.new()
	v.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	v.offset_left = -300
	v.offset_right = 300
	v.offset_top = -60
	v.offset_bottom = 60
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	_death.add_child(v)
	var title := HudKit.label("DEFEATED", 48, UiKit.BAD, HudKit.Z_DEATH_TEXT)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(title)
	_death_hint = HudKit.label(death_hint(false, OS.is_debug_build()), HudKit.BIG, UiKit.TEXT, HudKit.Z_DEATH_TEXT)
	_death_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(_death_hint)


## The death overlay's hint (P06): where checkpoints exist (the Valley, a test level) the
## confirm loads the last checkpoint, elsewhere it restarts the sandbox (main.gd handles the
## keys: Enter or pad A).
static func death_hint(checkpoints: bool, debug_build: bool) -> String:
	if checkpoints:
		return "Enter / A: load last checkpoint"
	var text := "Press Enter / A to restart the sandbox"
	if debug_build:
		text += "   |   F5 debug reset"
	return text


## The death overlay's hint text right now (tests).
func death_hint_text() -> String:
	return _death_hint.text if _death_hint != null else ""


func _build_help() -> void:
	_help = HudKit.panel(Color(0.05, 0.06, 0.08, 0.94))
	HudKit.set_z(_help, HudKit.Z_HELP)
	_help.anchor_left = 0.5
	_help.anchor_right = 0.5
	_help.anchor_top = 0.5
	_help.anchor_bottom = 0.5
	_help.offset_left = -330
	_help.offset_right = 330
	_help.offset_top = -270
	_help.offset_bottom = 270
	_help.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_help.grow_vertical = Control.GROW_DIRECTION_BOTH
	_help.visible = false
	add_child(_help)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	_help.add_child(v)
	_help_label = HudKit.label(HELP_TITLE, HudKit.TEXT, UiKit.TEXT, HudKit.Z_HELP_TEXT)
	v.add_child(_help_label)
	_help_grid = GridContainer.new()
	_help_grid.columns = 3
	_help_grid.add_theme_constant_override("h_separation", 18)
	_help_grid.add_theme_constant_override("v_separation", 1)
	v.add_child(_help_grid)


func toggle_help() -> void:
	_help.visible = not _help.visible
	if _help.visible:
		_rebuild_help()


## True while the F1 controls overlay is open.
func help_visible() -> bool:
	return _help != null and _help.visible


## The controls overlay's rows for the current loadout (P16): [action label, keyboard / mouse,
## controller]. Movement and combat first, then interact, every filled slot and the ultimate, the
## inventory, pause and the overlay itself.
func help_rows() -> Array:
	var loadout: Dictionary = player.controller.loadout if player != null and is_instance_valid(player) else {}
	return help_rows_for(loadout)


## help_rows() for a controller loadout (slot_1..slot_8, ultimate -> action id).
static func help_rows_for(loadout: Dictionary) -> Array:
	var rows: Array = [
		["Move", _move_keys(), "Left stick"],
		["Look / aim", "Mouse", "Right stick"],
		_help_row("Light attack (3-hit chain)", "attack_light"),
		["Heavy attack", TutorialText.label_for("heavy_attack", false), TutorialText.label_for("heavy_attack", true)],
		_help_row("Block (tap to parry)", "block"),
		_help_row("Dodge", "dodge"),
		_help_row("Jump", "jump"),
		_help_row("Sprint", "sprint"),
		_help_row("Lock target", "lock_target"),
		["Switch target (locked)", "%s / %s" % [InputBindings.describe_action("target_prev", false),
			InputBindings.describe_action("target_next", false)], "Flick the right stick"],
		_help_row("Camera: first / third person", "camera_toggle"),
		_help_row("Interact / grab / talk", "interact"),
	]
	for i in 8:
		var id := str(loadout.get("slot_%d" % (i + 1), ""))
		var def := GameData.get_action(id) if id != "" else null
		if def != null:
			rows.append(_help_row("%s (slot %d)" % [def.display_name, i + 1], "ability_%d" % (i + 1)))
	var ult_id := str(loadout.get("ultimate", ""))
	var ult := GameData.get_action(ult_id) if ult_id != "" else null
	rows.append(_help_row("Ultimate: %s (%d fury)" % [ult.display_name, int(ult.fury_cost)] if ult != null
		else "Ultimate (none equipped)", "ultimate"))
	rows.append(_help_row("Inventory", "inventory"))
	# P27: the map (with its pin), the journal and the tracked quest.
	rows.append(_help_row("Map", "map"))
	rows.append(_help_row("Map: pin here / clear the pin", "map_pin"))
	rows.append(_help_row("Journal", "journal"))
	rows.append(_help_row("Track the next quest", "track_next"))
	rows.append(_help_row("Pause / settings / rebind", "pause"))
	rows.append(_help_row("This overlay", "help"))
	return rows


static func _help_row(label: String, action_name: String) -> Array:
	return [label, InputBindings.describe_action(action_name, false), InputBindings.describe_action(action_name, true)]


static func _move_keys() -> String:
	var keys := PackedStringArray()
	for a: String in ["move_forward", "move_left", "move_back", "move_right"]:
		keys.append(InputBindings.describe_action(a, false))
	return " ".join(keys)


## The overlay as plain text, one row per line (tests, logs).
func help_text() -> String:
	var lines := PackedStringArray([HELP_TITLE])
	for r: Array in _help_rows:
		lines.append("%s: %s | %s" % [r[0], r[1], r[2]])
	return "\n".join(lines)


func _rebuild_help() -> void:
	_help_rows = help_rows()
	for c in _help_grid.get_children():
		_help_grid.remove_child(c)
		c.queue_free()
	var pad := InputBindings.last_device_is_pad()
	var on := UiKit.TEXT
	var off := UiKit.MUTED
	for h: Array in [["Action", on], ["Keyboard / mouse", off if pad else on], ["Controller", on if pad else off]]:
		_help_grid.add_child(HudKit.label(str(h[0]), HudKit.TEXT, Color(0.55, 0.85, 1.0) if h[1] == on else off,
			HudKit.Z_HELP_TEXT))
	for r: Array in _help_rows:
		_help_grid.add_child(HudKit.label(str(r[0]), HudKit.TEXT, on, HudKit.Z_HELP_TEXT))
		_help_grid.add_child(HudKit.label(str(r[1]), HudKit.TEXT, off if pad else on, HudKit.Z_HELP_TEXT))
		_help_grid.add_child(HudKit.label(str(r[2]), HudKit.TEXT, on if pad else off, HudKit.Z_HELP_TEXT))
	var notes := PackedStringArray()
	if OS.is_debug_build():
		notes.append("Debug: F3 panel, F5 reset sandbox, F6 / F7 grow / shrink, F8 +100 XP, F9 reload checkpoint")
	if OS.has_feature("web"):
		notes.append("Browser: the first Esc frees the mouse and pauses; click the game to resume.")
	_help_label.text = HELP_TITLE + ("\n" + "\n".join(notes) if not notes.is_empty() else "")
	_help_signature = _help_key()


## What the open overlay depends on: the loadout, the saved bindings and the device the prompts
## follow.
func _help_key() -> String:
	var loadout: Dictionary = player.controller.loadout if player != null and is_instance_valid(player) else {}
	return "%s|%s|%d" % [str(loadout), str(Settings.values.get("bindings", {})), InputBindings.device_serial]


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
	var l := HudKit.label(text, HudKit.BIG, color)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	l.set_meta("born", _time)
	_messages.add_child(l)
	while _messages.get_child_count() > 3:
		var old := _messages.get_child(0)
		_messages.remove_child(old)
		old.queue_free()


## The message lines on screen now, oldest first (tests).
func message_texts() -> PackedStringArray:
	var out := PackedStringArray()
	if _messages == null:
		return out
	for c in _messages.get_children():
		if c is Label and not c.is_queued_for_deletion():
			out.append((c as Label).text)
	return out


func _on_loot(_tick: int, _world_id: String, item_id: String, count: int, _who: String) -> void:
	var item := GameData.get_record(item_id)
	show_message("+%d %s" % [count, item.get("display_name", item_id)], "good")


func _refresh_mode_label() -> void:
	if player == null:
		return
	_mode_label.text = mode_line(player.camera_rig.is_first_person(), player.growth_stage,
		InputBindings.last_device_is_pad())


## The line under the resource bars (P16: the buttons of the device in use): "Third person  [V]
## Stage 1   |   F1 / H: controls" on a keyboard, "Third person  [Up]   Stage 1   |   Start:
## menu and controls" on a pad (the overlay has no pad button; the pause menu lists the controls).
static func mode_line(first_person: bool, stage: int, pad: bool) -> String:
	var camera := "First person" if first_person else "Third person"
	if pad:
		var toggle := InputBindings.short_pad_label("camera_toggle")
		var menu := InputBindings.short_pad_label("pause")
		return "%s  [%s]   Stage %d   |   %s: menu and controls" % [camera, toggle if toggle != "" else "-",
			stage, menu if menu != "" else "Start"]
	return "%s  [%s]   Stage %d   |   %s: controls" % [camera, InputBindings.describe_action("camera_toggle", false),
		stage, InputBindings.describe_action("help", false)]


## The mode line shown now (tests).
func mode_line_text() -> String:
	return _mode_label.text if _mode_label != null else ""


func _process(delta: float) -> void:
	_time += delta
	if player == null or not is_instance_valid(player):
		player = get_tree().get_first_node_in_group("player") as GiantPlayer
		if player == null:
			return
		_refresh_mode_label()
	if InputBindings.device_serial != _device_serial:
		_device_serial = InputBindings.device_serial
		_labels_dirty = true
		_refresh_mode_label()
	_update_resources()
	_update_hotbar()
	_update_target()
	_update_messages()
	if _help.visible and _help_key() != _help_signature:
		_rebuild_help()
	var dead := player.controller.state == CombatController.State.DEAD
	if dead and not _death.visible:
		_death_hint.text = death_hint(GameSession.checkpoints_enabled(), OS.is_debug_build())
	_death.visible = dead
	_crosshair.visible = not _death.visible
	# Without a captured mouse there is no mouse look; tell the player how to get it back (P16:
	# not a controller player, whose right stick looks around anyway).
	_capture_hint.visible = not _death.visible and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED \
		and DisplayServer.get_name() != "headless" and not get_tree().paused \
		and not InputBindings.last_device_is_pad()
	var parts := PackedStringArray()
	for item_id: String in WorldState.inventory:
		parts.append("%s x%d" % [GameData.get_record(item_id).get("display_name", item_id), WorldState.inventory[item_id]])
	_loot_label.text = ("Loot: " + ", ".join(parts)) if not parts.is_empty() else ""


## Updates the resource bars, hotbar and target frame from the current state right away
## (normally once per frame in _process; tests call it to read slot_state() for this tick).
func refresh() -> void:
	if player == null or not is_instance_valid(player):
		return
	_update_resources()
	_update_hotbar()
	_update_target()


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
	_update_slots(c, pools)
	_labels_dirty = false


func _update_slots(c: CombatController, _pools: ResourcePool) -> void:
	var providers: Array = []
	for comp in player.components():
		if comp.has_method("preview_params"):
			providers.append(comp)
	for slot: Dictionary in _slots:
		var i: int = slot.index
		var is_ultimate := i == 8
		var id := str(c.loadout.get("ultimate" if is_ultimate else "slot_%d" % (i + 1), ""))
		var def: ActionDef = c.library.get(id) if id != "" else null
		if _labels_dirty:
			var keys := slot_keys(i, InputBindings.last_device_is_pad())
			(slot.key as Label).text = keys[0]
			(slot.pad as Label).text = keys[1]
		var key_text := (slot.key as Label).text
		var alt_text := (slot.pad as Label).text
		var root: PanelContainer = slot.root
		if def == null:
			(slot.title as Label).text = "ULT" if is_ultimate else ""
			(slot.cost as Label).text = ""
			(slot.timer as Label).text = ""
			(slot.reason as Label).text = ""
			(slot.target as Label).text = ""
			(slot.cooldown as ColorRect).offset_top = 0
			root.modulate = Color(1, 1, 1, 0.45)
			_slot_states[i] = {"id": "", "reason_code": "", "reason": "", "target": "", "key": key_text,
				"alt_key": alt_text}
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
		var slot_key := "ultimate" if is_ultimate else "slot_%d" % (i + 1)
		var params := _preview_params(slot_key, def, providers)
		var code := c.preview_reason(&"ultimate" if is_ultimate else &"slot", params)
		var reason := reason_text(code, def)
		(slot.reason as Label).text = reason
		var target := ""
		if def.hit_shape == "projectile":
			var locked := player.locked_entity()
			target = ("» %s" % locked.display_name()) if locked != null and locked.is_alive() else "aim"
		(slot.target as Label).text = target
		_slot_states[i] = {"id": def.id, "reason_code": code, "reason": reason, "target": target,
			"key": key_text, "alt_key": alt_text}


## A hotbar slot's two key labels (P16): [the binding of the device the prompts follow (large,
## top left), the other device's (small, top right)]. index 0-7 = slots 1-8, 8 = the ultimate.
## Keyboard: ["6", "LT+Rt"]; pad: ["LT+Rt", "6"] (a slot without a pad binding keeps its key).
static func slot_keys(index: int, pad: bool) -> Array[String]:
	var action_name := "ultimate" if index == 8 else "ability_%d" % (index + 1)
	var kb := InputBindings.describe_action(action_name, false)
	var combo := InputBindings.short_pad_label(action_name)
	if pad and combo != "":
		return [combo, kb] as Array[String]
	return [kb, combo] as Array[String]


## Request parameters for a slot's preview: {"slot": n} for slots 1-8, {} for the ultimate,
## plus whatever the player components in `providers` add through preview_params(slot_key,
## def, params).
func _preview_params(slot_key: String, def: ActionDef, providers: Array) -> Dictionary:
	var params := {} if slot_key == "ultimate" else {"slot": int(slot_key.substr(5))}
	for comp: Object in providers:
		comp.call("preview_params", slot_key, def, params)
	return params


## Hotbar text for a preview_reason code ("" = available): Dead, Stage N, Lv N, Cooldown,
## Stamina, Essence, Fury, Busy, No target, Out of range (P16: a projectile locked beyond its
## reach), and short texts for the grab codes (P16: P07's codes capitalised were too long for a
## slot); anything else is shown capitalised.
static func reason_text(code: String, def: ActionDef) -> String:
	match code:
		"":
			return ""
		"dead":
			return "Dead"
		"locked":
			return "Stage %d" % (def.unlock_stage if def != null else 1)
		"level_locked":
			return "Lv %d" % (def.unlock_level if def != null else 1)
		"cooldown":
			return "Cooldown"
		"stamina":
			return "Stamina"
		"essence":
			return "Essence"
		"fury":
			return "Fury"
		"busy", "airborne":
			return "Busy"
		"no_target", "no_grab_target", "nothing_in_reach":
			return "No target"
		"out_of_range":
			return "Out of range"
		"holding":
			return "Hands full"
		"not_holding":
			return "Hand empty"
		"not_staggered":
			return "Stagger it"
		"too_tall", "too_heavy_to_crush":
			return "Too big"
		"immune", "not_grabbable", "no_attach_profile":
			return "No grip"
		"no_los":
			return "No sight"
		"no_permission":
			return "Too small"
	return code.capitalize()


## What hotbar slot `index` (0-7 = slots 1-8, 8 = ultimate) shows now: {"id", "reason_code"
## (the preview_reason code), "reason" (its text), "target" (projectile slots)}.
func slot_state(index: int) -> Dictionary:
	if index < 0 or index >= _slot_states.size():
		return {}
	return _slot_states[index].duplicate()


func _update_target() -> void:
	var target := player.locked_entity()
	var cam := player.camera_rig.camera
	if target == null or not target.is_alive():
		_target_frame.visible = false
		_marker.visible = false
		return
	# P11a: while the boss bar shows the locked boss, its bar replaces the target frame. P16: while
	# it shows another (engaged) boss, the frame of the locked target sits below the bar.
	_target_frame.visible = not boss_bar_shows(target)
	var top := TARGET_FRAME_TOP_UNDER_BOSS if boss_bar_visible() else TARGET_FRAME_TOP
	if _target_frame.offset_top != top:
		_target_frame.offset_top = top
		_target_frame.offset_bottom = top + TARGET_FRAME_HEIGHT
	# P27: the lock line - PlayerTargeting.lock_label() (P30: a formation's name and count, a banner's
	# name after a drawn flag), else the target's name; then the distance.
	var line := lock_line(_lock_label(target))
	_target_flag.visible = bool(line.banner)
	_target_name.text = "%s   %d m" % [str(line.text), int(player.global_position.distance_to(target.actor.global_position))]
	var p := target.combatant.pools
	_target_bar.value = p.health / maxf(p.health_max, 0.001)
	_target_hint.text = lock_hint(InputBindings.last_device_is_pad())
	# P11a: the marker sits on the lock point the camera frames (a knee of a much taller target).
	var anchor := target.lock_anchor_position(float(player.profile.get("height_m", 3.66)))
	if cam != null and not cam.is_position_behind(anchor):
		_marker.visible = true
		_marker.position = cam.unproject_position(anchor) - Vector2(16, 16)
	else:
		_marker.visible = false


## The lock label of the player's lock (PlayerTargeting.lock_label, P30), else `target`'s name.
func _lock_label(target: CombatEntity) -> String:
	if player.targeting != null and player.targeting.has_method("lock_label"):
		var label := str(player.targeting.call("lock_label"))
		if label != "":
			return label
	return target.display_name()


## The lock line for a lock label (P27): {"text", "banner"} - a banner's mark (BANNER_MARK) becomes
## a drawn flag ("banner": true) and leaves the text: "⚑ Banner of the Toll-Riders" ->
## {"text": "Banner of the Toll-Riders", "banner": true}.
static func lock_line(label: String) -> Dictionary:
	var t := label.strip_edges()
	if t.begins_with(BANNER_MARK):
		return {"text": t.trim_prefix(BANNER_MARK).strip_edges(), "banner": true}
	return {"text": t, "banner": false}


## The lock line shown now: {"text" (with the distance), "banner"} ({} while no frame shows; tests).
func lock_line_now() -> Dictionary:
	if _target_frame == null or not _target_frame.visible:
		return {}
	return {"text": _target_name.text, "banner": _target_flag.visible}


## True while the boss bar widget (ui/hud/boss_bar.gd, P11a) shows `target` (P11a: the target
## frame is hidden then, so the boss's health is not shown twice).
func boss_bar_shows(target: CombatEntity) -> bool:
	var bar := get_node_or_null("BossBar")
	return bar != null and bar.has_method("shows_entity") and bool(bar.call("shows_entity", target))


## True while the boss bar widget shows any boss (P16: the target frame then sits below it).
func boss_bar_visible() -> bool:
	var bar := get_node_or_null("BossBar")
	return bar != null and bar.has_method("bar_visible") and bool(bar.call("bar_visible"))


## The target frame's hint (P16: the device in use): "LOCKED  -  Wheel Up / Wheel Down to switch",
## "LOCKED  -  flick the right stick to switch".
static func lock_hint(pad: bool) -> String:
	if pad:
		return "LOCKED  -  flick the right stick to switch"
	return "LOCKED  -  %s / %s to switch" % [InputBindings.describe_action("target_prev", false),
		InputBindings.describe_action("target_next", false)]


## True while the lock-on target frame is showing (tests).
func target_frame_visible() -> bool:
	return _target_frame != null and _target_frame.visible


## The target frame's rect in this HUD (tests: it moves below the boss bar).
func target_frame_rect() -> Rect2:
	return _target_frame.get_rect() if _target_frame != null else Rect2()


## The HUD's fixed screen regions for a `view`-sized screen (P16 layout check): name -> Rect2,
## this node's (resources, hotbar with its key, target and reason lines, loot, capture hint,
## messages, the target frame at both of its heights) and every widget's (HudWidget.layout_regions).
## Full-screen overlays that draw at points (crosshair, lock marker, threat arrows, objective
## marker), the death and help overlays and the F3 debug panel are not regions.
func layout_regions(view: Vector2) -> Dictionary:
	var out := {
		"resources": HudWidget.anchored_rect(_resources_panel, view),
		"hotbar": HudWidget.anchored_rect(_hotbar, view).grow_individual(10.0, 16.0, 10.0, 16.0),
		"loot": HudWidget.anchored_rect(_loot_label, view),
		"capture_hint": HudWidget.anchored_rect(_capture_hint, view),
		"messages": HudWidget.anchored_rect(_messages, view),
	}
	var frame := HudWidget.anchored_rect(_target_frame, view)
	out["target_frame"] = Rect2(frame.position.x, TARGET_FRAME_TOP, frame.size.x, TARGET_FRAME_HEIGHT)
	out["target_frame_under_boss_bar"] = Rect2(frame.position.x, TARGET_FRAME_TOP_UNDER_BOSS, frame.size.x,
		TARGET_FRAME_HEIGHT)
	for c in get_children():
		if c is HudWidget:
			var regions: Dictionary = (c as HudWidget).layout_regions(view)
			for key: String in regions:
				out[key] = regions[key]
	return out


## The fixed panels drawn now - visible, with something in them - as rects on a `view`-sized screen
## (M4 gate): what the edge overlays (threat arrows, the off-screen objective marker) keep clear of
## through HudEdge.clear_of. Each is its layout region (layout_regions); the target frame's is where
## it is now (below the boss bar or not). An empty message stack, loot line or status row is none.
func overlay_keep_out(view: Vector2) -> Array[Rect2]:
	var out: Array[Rect2] = []
	var regions := layout_regions(view)
	var controls := layout_controls()
	for key: String in controls:
		var c := controls[key] as Control
		if c == null or not c.is_visible_in_tree() or not _shows_something(c):
			continue
		if key == "target_frame":
			out.append(HudWidget.anchored_rect(c, view))
		elif regions.has(key):
			out.append(regions[key])
	return out


## False for a label without text and a box without a visible child (nothing drawn there now).
static func _shows_something(c: Control) -> bool:
	if c is Label:
		return (c as Label).text != ""
	if c is BoxContainer:
		for child in c.get_children():
			if child is CanvasItem and (child as CanvasItem).visible:
				return true
		return false
	return true


## The Controls behind the regions that have one (tests compare their drawn rects with
## layout_regions at the real screen size): the HUD's panels and every widget's.
func layout_controls() -> Dictionary:
	var out := {"resources": _resources_panel, "hotbar": _hotbar, "loot": _loot_label,
		"capture_hint": _capture_hint, "messages": _messages, "target_frame": _target_frame}
	for c in get_children():
		if c is HudWidget:
			out.merge((c as HudWidget).layout_controls(), true)
	return out


## The screen point the lock marker is centred on (Vector2.INF while it is hidden; tests).
func lock_marker_point() -> Vector2:
	if _marker == null or not _marker.visible:
		return Vector2.INF
	return _marker.position + Vector2(16, 16)


func _update_messages() -> void:
	for child in _messages.get_children():
		var age := _time - float(child.get_meta("born", _time))
		(child as Label).modulate.a = clampf((MESSAGE_LIFETIME - age) / 0.5, 0.0, 1.0)
		if age > MESSAGE_LIFETIME:
			child.queue_free()


## P27: rectangles only (a dot and four ticks), so the crosshair joins the HUD's batch of rectangles
## (its circle and ring were two draw calls of their own every frame).
class Crosshair:
	extends Control

	func _notification(what: int) -> void:
		if what == NOTIFICATION_RESIZED:
			queue_redraw()

	func _draw() -> void:
		var c := (size * 0.5).round()
		var shade := Color(0, 0, 0, 0.45)
		HudKit.draw_dot(self, c, 2.5, shade)
		HudKit.draw_dot(self, c, 1.5, Color(1, 1, 1, 0.9))
		for d: Vector2 in [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]:
			var mid := c + d * 9.0
			var half := Vector2(absf(d.y), absf(d.x)) * 0.75 + Vector2(absf(d.x), absf(d.y)) * 2.0
			draw_rect(Rect2(mid - half, half * 2.0), shade)


## P27: the lock diamond as four turned rectangles and a dot (it was a polyline and a circle).
class LockMarker:
	extends Control

	func _ready() -> void:
		size = Vector2(32, 32)

	func _draw() -> void:
		var c := Vector2(16, 16)
		HudKit.draw_diamond_outline(self, c, 13.0, Color(1.0, 0.35, 0.25), 2.5)
		HudKit.draw_dot(self, c, 2.0, Color(1.0, 0.35, 0.25))


## P27: the banner's flag before its name on the lock line: a pole and a flag (two rectangles).
class BannerFlag:
	extends Control

	func _draw() -> void:
		var h := size.y
		draw_rect(Rect2(1, 1, 2, h - 2), Color(0.85, 0.8, 0.7))
		draw_rect(Rect2(3, 2, size.x - 4, h * 0.45), Hud.BANNER_FLAG_COLOR)
