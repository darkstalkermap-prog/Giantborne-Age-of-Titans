class_name InventoryScreen
extends UiScreen
## The inventory (plan §2.10.2, §3.14 design 4; P12): ScreenStack SCREENS["inventory"], opened with
## I / pad Back (ScreenStack.HOTKEYS) when no other screen is open. It pauses the game and shows
##   * the character: level and XP, growth stage, unspent attribute points with an Attributes
##     button (the Attributes screen), and "Prototype pacing: accelerated quest XP";
##   * the items (name, count, description, a [quest] tag for quest items);
##   * the weapons owned: the equipped one marked, an Equip button for the others
##     (PlayerEquipment.equip_weapon), "(too small)" where the giant has outgrown one;
##   * the current loadout (changed at shrines) and the talent points ("talent trees are a
##     full-game feature").
## In combat (ResourcePool.in_combat()) it refuses to open: "Not during combat" as a HUD warning,
## and the screen closes itself at once. args: {"player": GiantPlayer} (else group "player").
## P16: focus rows Attributes, every Equip button, Close (wrapping); the list scrolls with the focus.

const COMBAT_MESSAGE := "Not during combat"

var player: GiantPlayer
var _character: Label
var _items: VBoxContainer
var _weapons: VBoxContainer
var _loadout: Label
var _talents: Label
var _result: Label
var attributes_button: Button
var close_button: Button
## Equip buttons by weapon id (tests press them).
var equip_buttons: Dictionary = {}
var _equip_order: Array[Button] = []   ## the Equip buttons in weapon order (P16 focus rows)


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
	frame.offset_top = -300
	frame.offset_bottom = 300
	add_child(frame)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	frame.add_child(v)
	var title := UiKit.label("Inventory", 28)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(title)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 12)
	v.add_child(top)
	_character = UiKit.label("", 15)
	_character.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_character.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	top.add_child(_character)
	attributes_button = UiKit.button("Attributes", 16)
	attributes_button.pressed.connect(_on_attributes)
	top.add_child(attributes_button)
	var pacing := UiKit.label(str(Progression.record().get("prototype_xp_label", "")), 12, UiKit.MUTED)
	v.add_child(pacing)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	v.add_child(scroll)
	var body := VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 6)
	scroll.add_child(body)
	body.add_child(UiKit.label("Items", 19))
	_items = VBoxContainer.new()
	body.add_child(_items)
	body.add_child(UiKit.label("Weapons", 19))
	_weapons = VBoxContainer.new()
	body.add_child(_weapons)
	body.add_child(UiKit.label("Abilities (change them at a shrine)", 19))
	_loadout = UiKit.label("", 14)
	_loadout.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(_loadout)
	_talents = UiKit.label("", 14, UiKit.MUTED)
	_talents.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(_talents)
	_result = UiKit.label("", 14, UiKit.GOOD)
	_result.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(_result)
	close_button = UiKit.button("Close", 18)
	close_button.pressed.connect(cancel)
	v.add_child(close_button)


## Why the inventory cannot open for `p` now ("" = it can): in combat.
static func blocked_reason(p: GiantPlayer) -> String:
	if p != null and is_instance_valid(p) and p.entity != null and p.entity.combatant != null \
			and p.entity.combatant.pools.in_combat():
		return COMBAT_MESSAGE
	return ""


func on_open() -> void:
	var why := blocked_reason(player)
	if why != "":
		Events.hud_message.emit(why, "warn")
		close({"refused": why})
		return
	refresh()


func first_focus() -> Control:
	return close_button


func refresh() -> void:
	if _character == null:
		return
	_character.text = character_text()
	attributes_button.disabled = player == null or player.progression == null
	for c in _items.get_children():
		_items.remove_child(c)
		c.queue_free()
	var items := item_rows()
	if items.is_empty():
		_items.add_child(UiKit.label("Nothing yet.", 14, UiKit.MUTED))
	for row: Dictionary in items:
		var l := UiKit.label(item_line(row), 14)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_items.add_child(l)
	for c in _weapons.get_children():
		_weapons.remove_child(c)
		c.queue_free()
	equip_buttons.clear()
	_equip_order.clear()
	for row: Dictionary in weapon_rows():
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 10)
		var l := UiKit.label(str(row.label) + ("  (equipped)" if row.equipped else ""), 15,
			UiKit.WARN if row.too_small else UiKit.TEXT)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(l)
		if not row.equipped:
			var b := UiKit.button("Equip", 14)
			b.pressed.connect(_on_equip.bind(str(row.id)))
			h.add_child(b)
			equip_buttons[str(row.id)] = b
			_equip_order.append(b)
		_weapons.add_child(h)
	_loadout.text = loadout_text()
	_talents.text = talent_text()
	if is_inside_tree():
		refresh_focus()


## Attributes, every Equip button (weapon order), Close (P16).
func focus_rows() -> Array:
	var rows: Array = [[attributes_button]]
	for b: Button in _equip_order:
		if is_instance_valid(b) and not b.is_queued_for_deletion():
			rows.append([b])
	rows.append([close_button])
	return rows


# --------------------------------------------------------------------------- content

## "Level 3 (18 / 200 XP)   Stage 2   Unspent attribute points: 3".
func character_text() -> String:
	if player == null or not is_instance_valid(player):
		return ""
	var prog: Variant = player.progression
	var parts := PackedStringArray()
	if prog != null:
		var progress: Array = prog.level_progress()
		parts.append("Level %d (%s)" % [int(prog.level), "%d / %d XP" % [int(progress[0]), int(progress[1])]
			if int(progress[1]) > 0 else "max"])
	parts.append("Stage %d" % player.growth_stage)
	if prog != null:
		parts.append("Unspent attribute points: %d" % int(prog.unspent_attribute_points))
	return "   ".join(parts)


## The inventory as rows: [{"id", "name", "count", "description", "category", "quest"}], quest
## items first, then by name.
static func item_rows() -> Array:
	var out: Array = []
	for id: String in WorldState.inventory:
		var count := int(WorldState.inventory[id])
		if count <= 0:
			continue
		var rec := GameData.get_record(id)
		out.append({"id": id, "name": str(rec.get("display_name", id)), "count": count,
			"description": str(rec.get("description", "")), "category": str(rec.get("category", "material")),
			"quest": bool(rec.get("quest_item", false))})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if bool(a.quest) != bool(b.quest):
			return bool(a.quest)
		return str(a.name) < str(b.name))
	return out


## "Iron Ingot x2 [quest] — A bar of good iron..." for an item row.
static func item_line(row: Dictionary) -> String:
	var tag := "  [quest]" if bool(row.quest) else ""
	var desc := str(row.description)
	return "%s x%d%s%s" % [str(row.name), int(row.count), tag, (" — " + desc) if desc != "" else ""]


## The weapons owned: [{"id", "label" ("Oak Club (too small)"), "equipped", "too_small"}].
func weapon_rows() -> Array:
	var out: Array = []
	if player == null or not is_instance_valid(player) or player.equipment == null:
		return out
	var eq: Variant = player.equipment
	var current := str(eq.weapon_id())
	for id: String in eq.owned():
		var rec := GameData.get_record(id)
		out.append({"id": id, "label": str(eq.weapon_label(id)), "equipped": id == current,
			"too_small": PlayerEquipment.too_small_at(rec, player.growth_stage)})
	return out


## "1 Heavy Footfall   2 Sweeping Blow   3 —   ...   Ultimate: —".
func loadout_text() -> String:
	if player == null or not is_instance_valid(player):
		return ""
	var parts := PackedStringArray()
	for i in 8:
		parts.append("%d %s" % [i + 1, _action_name(str(player.controller.loadout.get("slot_%d" % (i + 1), "")))])
	parts.append("Ultimate: %s" % _action_name(str(player.controller.loadout.get("ultimate", ""))))
	return "   ".join(parts)


static func _action_name(id: String) -> String:
	if id == "":
		return "—"
	var def := GameData.get_action(id)
	return def.display_name if def != null else id


func talent_text() -> String:
	var prog: Variant = player.progression if player != null and is_instance_valid(player) else null
	var n := int(prog.talent_points) if prog != null else 0
	return "Talent points: %d (talent trees are a full-game feature)" % n


func result_text() -> String:
	return _result.text if _result != null else ""


# --------------------------------------------------------------------------- actions

## Equips an owned weapon (PlayerEquipment.equip_weapon) and shows the result.
func press_equip(weapon_id: String) -> Dictionary:
	if player == null or player.equipment == null:
		return {"ok": false, "reason": "no_player", "message": ""}
	var out: Dictionary = player.equipment.equip_weapon(weapon_id)
	_result.text = str(out.get("message", ""))
	_result.add_theme_color_override("font_color", UiKit.GOOD if out.ok else UiKit.WARN)
	refresh()
	return out


func _on_equip(weapon_id: String) -> void:
	press_equip(weapon_id)


## Opens the Attributes screen on top of this one.
func open_attributes() -> UiScreen:
	if stack == null or not is_instance_valid(stack):
		return null
	var s := stack.open("attributes", {"player": player})
	if s != null:
		s.closed.connect(_on_attributes_closed)
	return s


func _on_attributes() -> void:
	open_attributes()


func _on_attributes_closed(_result_dict: Dictionary) -> void:
	if is_inside_tree():
		refresh()
