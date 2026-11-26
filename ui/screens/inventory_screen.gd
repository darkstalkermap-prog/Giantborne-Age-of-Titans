class_name InventoryScreen
extends UiScreen
## The inventory (P12; C3 rebuilt it, decision C3-5): ScreenStack SCREENS["inventory"], opened with I / pad Back
## (ScreenStack.HOTKEYS) when no other screen is open; it pauses the game. What the giant wears and what he carries:
##   * Worn: the giant himself in the middle (the creator's GiantPreview in his worn look, where a display draws it)
##     between his eight slots - head, shoulders, chest, arms on the left; weapon, waist, legs, trinket on the
##     right - each a tile with its piece's drawn icon (ItemIcon) and name, or the slot's outline when empty. A slot
##     chosen lists what he owns for it (its pieces, or his weapons) to put on, Take off, and his armour's numbers
##     (CharacterScreen.slot_options, compare_lines, apply_option: the Character menu's own rules - the same
##     GameSession.expansion.equipment, out of combat only - and PlayerEquipment.equip_weapon).
##   * The stats: health, stamina, his height, armour (the share of a blow it turns), poise, weight, the weapon's
##     damage.
##   * The bag: a grid of BAG_COLS x at least BAG_MIN_ROWS cells, one a kind of thing he carries, with its drawn icon
##     and count - weapons and armour not worn first, then trophies, quest items, keys and materials
##     (WorldState.inventory, the equipment's owned pieces, PlayerEquipment.owned) - and "NEW" on what came since the
##     bag was last looked at (loot lands there). A cell chosen shows its name, count, kind, words and, for a piece,
##     its numbers before -> after; chosen again (or Put on), a weapon or a piece is put on.
##   * Attributes (the Attributes screen on top) and Character (the Character menu on top, at its Equipment tab)
##     buttons; the loadout and the talent points under the bag.
## I and C (decision C3-5): I opens this screen, C the Character menu (Giant, Attributes, Equipment, Titans,
## Materials); both read and write the same state, and this one opens the other. In combat
## (ResourcePool.in_combat()) it refuses to open: "Not during combat" as a HUD warning, and it closes itself at
## once. I again closes it. args: {"player": GiantPlayer} (else group "player").
## Pad and keyboard: rows - the top buttons; the four rows of slots, each with the bag's row beside it; the rest of
## the bag; the chosen thing's buttons; Close. Every direction wraps (UiNav). Mouse: a click chooses, a second click
## on the chosen cell puts it on.
## Read API (tests): bag_entries(), worn_tiles(), slot_choices(), character_text(), stats_text(), item_rows(),
## item_line(), weapon_rows(), loadout_text(), talent_text(), press_equip(), choose_cell(), choose_slot(),
## press_option(), press_cell_action(), detail_text(), cell_ids(), fresh_ids().

const COMBAT_MESSAGE := "Not during combat"
const PANEL_SIZE := Vector2(1180, 650)
const BAG_COLS := 8
const BAG_MIN_ROWS := 5
const CELL_PX := 58
const TILE_W := 118
const LEFT_SLOTS := ["head", "shoulders", "chest", "arms"]
const RIGHT_SLOTS := ["weapon", "waist", "legs", "trinket"]
const SLOT_NAMES := {"head": "Head", "shoulders": "Shoulders", "chest": "Chest", "arms": "Arms", "waist": "Waist",
	"legs": "Legs", "trinket": "Trinket", "weapon": "Weapon"}
## The bag's order by kind.
const KIND_ORDER := ["weapon", "armour", "trophy", "quest", "key", "material"]
const KIND_NAMES := {"weapon": "Weapon", "armour": "Armour", "trophy": "Trophy", "quest": "Quest item", "key": "Key",
	"material": "Material"}
const GOLD := Color(1.0, 0.86, 0.45)

## What the bag held when it was last looked at (id -> count), for the "NEW" marks (this session; not saved).
static var _seen: Dictionary = {}
static var _seen_init := false

var player: GiantPlayer
var attributes_button: Button
var character_button: Button
var close_button: Button
## Equip buttons by weapon id (tests press them): the bag's cells of the weapons not in hand.
var equip_buttons: Dictionary = {}
var preview: GiantPreview = null
var _character: Label
var _stats: Label
var _loadout: Label
var _talents: Label
var _result: Label
var _detail_title: Label
var _detail: Label
var _detail_buttons: HBoxContainer
var _bag: GridContainer
var _left: VBoxContainer
var _right: VBoxContainer
var _slot_buttons: Dictionary = {}     ## slot -> Button
var _cells: Array[Button] = []
var _cell_ids: Array = []
var _option_buttons: Array[Button] = []
var _chosen_cell := ""
var _chosen_slot := ""
var _fresh: Dictionary = {}


func _ready() -> void:
	player = args.get("player") as GiantPlayer
	if player == null and is_inside_tree():
		player = get_tree().get_first_node_in_group("player") as GiantPlayer
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.55)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(shade)
	var frame := UiKit.panel(Color(0.07, 0.08, 0.10, 0.97))
	frame.name = "Frame"
	frame.mouse_filter = Control.MOUSE_FILTER_STOP
	frame.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	frame.offset_left = -PANEL_SIZE.x * 0.5
	frame.offset_right = PANEL_SIZE.x * 0.5
	frame.offset_top = -PANEL_SIZE.y * 0.5 - 12
	frame.offset_bottom = PANEL_SIZE.y * 0.5 - 12
	add_child(frame)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	frame.add_child(v)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 12)
	v.add_child(top)
	top.add_child(UiKit.label("Inventory", 26))
	_character = UiKit.label("", 14, UiKit.MUTED)
	_character.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_character.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	top.add_child(_character)
	attributes_button = UiKit.button("Attributes", 15)
	attributes_button.pressed.connect(_on_attributes)
	top.add_child(attributes_button)
	character_button = UiKit.button("Character", 15)
	character_button.pressed.connect(_on_character)
	top.add_child(character_button)
	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 14)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(body)
	# the worn column: slots | the giant | slots, his numbers under them
	var worn := VBoxContainer.new()
	worn.add_theme_constant_override("separation", 4)
	body.add_child(worn)
	worn.add_child(UiKit.label("Worn", 18, GOLD))
	var doll := HBoxContainer.new()
	doll.add_theme_constant_override("separation", 6)
	worn.add_child(doll)
	_left = VBoxContainer.new()
	_left.add_theme_constant_override("separation", 6)
	doll.add_child(_left)
	var middle := Control.new()
	middle.custom_minimum_size = Vector2(210, 390)
	middle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	doll.add_child(middle)
	var silhouette := Silhouette.new()
	silhouette.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	silhouette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	middle.add_child(silhouette)
	if CharacterScreen.wants_preview():
		preview = GiantPreview.new()
		preview.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		middle.add_child(preview)
		silhouette.visible = false
	_right = VBoxContainer.new()
	_right.add_theme_constant_override("separation", 6)
	doll.add_child(_right)
	for slot: String in LEFT_SLOTS:
		_left.add_child(_make_slot(slot))
	for slot: String in RIGHT_SLOTS:
		_right.add_child(_make_slot(slot))
	_stats = UiKit.label("", 13)
	_stats.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_stats.custom_minimum_size = Vector2(470, 0)
	worn.add_child(_stats)
	# the bag column
	var bagcol := VBoxContainer.new()
	bagcol.add_theme_constant_override("separation", 4)
	bagcol.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(bagcol)
	bagcol.add_child(UiKit.label("Bag", 18, GOLD))
	_bag = GridContainer.new()
	_bag.columns = BAG_COLS
	_bag.add_theme_constant_override("h_separation", 4)
	_bag.add_theme_constant_override("v_separation", 4)
	bagcol.add_child(_bag)
	_detail_title = UiKit.label("", 17, GOLD)
	bagcol.add_child(_detail_title)
	_detail = UiKit.label("", 13)
	_detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail.custom_minimum_size = Vector2(480, 0)
	bagcol.add_child(_detail)
	_detail_buttons = HBoxContainer.new()
	_detail_buttons.add_theme_constant_override("separation", 8)
	bagcol.add_child(_detail_buttons)
	_loadout = UiKit.label("", 12, UiKit.MUTED)
	_loadout.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_loadout.custom_minimum_size = Vector2(480, 0)
	bagcol.add_child(_loadout)
	_talents = UiKit.label("", 12, UiKit.MUTED)
	_talents.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	bagcol.add_child(_talents)
	var bottom := HBoxContainer.new()
	bottom.add_theme_constant_override("separation", 16)
	v.add_child(bottom)
	_result = UiKit.label("", 14, UiKit.GOOD)
	_result.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_result.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	bottom.add_child(_result)
	close_button = UiKit.button("Close", 18)
	close_button.pressed.connect(cancel)
	bottom.add_child(close_button)


static func _cell_style(b: Button, base: Color) -> void:
	b.add_theme_stylebox_override("normal", UiKit.box(base))
	b.add_theme_stylebox_override("hover", UiKit.box(base.lightened(0.12)))
	b.add_theme_stylebox_override("focus", UiKit.open_tab_box())
	b.add_theme_stylebox_override("pressed", UiKit.box(base.lightened(0.2)))
	b.add_theme_stylebox_override("disabled", UiKit.box(base.darkened(0.25)))


func _make_slot(slot: String) -> Button:
	var b := Button.new()
	b.name = "Slot_" + slot
	b.custom_minimum_size = Vector2(TILE_W, 92)
	b.focus_mode = Control.FOCUS_ALL
	_cell_style(b, UiKit.BG_LIGHT)
	b.pressed.connect(choose_slot.bind(slot))
	var col := VBoxContainer.new()
	col.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_theme_constant_override("separation", 0)
	b.add_child(col)
	var cap := UiKit.label(str(SLOT_NAMES.get(slot, slot)), 11, UiKit.MUTED)
	cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(cap)
	var icon := ItemIcon.of_slot("club" if slot == "weapon" else slot)
	icon.name = "Icon"
	icon.custom_minimum_size = Vector2(TILE_W, 46)
	col.add_child(icon)
	var nm := UiKit.label("", 11)
	nm.name = "Name"
	nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	nm.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	nm.custom_minimum_size = Vector2(TILE_W - 6, 0)
	nm.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(nm)
	_slot_buttons[slot] = b
	return b


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
	_fresh = fresh_ids()
	refresh()
	if preview != null and player != null and is_instance_valid(player):
		preview.set_game_profile(player.profile)
		_refresh_preview()


func on_close() -> void:
	if blocked_reason(player) == "":
		mark_seen()


func first_focus() -> Control:
	return _cells[0] if not _cells.is_empty() else close_button


func _unhandled_input(event: InputEvent) -> void:
	if stack == null or stack.top() != self:
		return
	if event.is_action_pressed("inventory") and not MapScreen.is_ui_direction(event):
		close({"closed": "inventory"})
		get_viewport().set_input_as_handled()


# --------------------------------------------------------------------------- the "new" marks

## The ids whose count grew since the bag was last looked at ({} the first time this session: nothing is marked).
static func fresh_ids() -> Dictionary:
	var out := {}
	if not _seen_init:
		return out
	for e: Dictionary in bag_entries(null):
		if int(e.count) > int(_seen.get(str(e.id), 0)):
			out[str(e.id)] = true
	return out


## What the bag holds now is seen (the marks clear the next time it opens).
static func mark_seen() -> void:
	_seen.clear()
	for e: Dictionary in bag_entries(null):
		_seen[str(e.id)] = int(e.count)
	_seen_init = true


## Tests: forget what was seen (as at the session's start); `seen_all` marks what the bag holds now as seen.
static func reset_seen(seen_all := false) -> void:
	_seen.clear()
	_seen_init = false
	if seen_all:
		mark_seen()


# --------------------------------------------------------------------------- building

func refresh() -> void:
	if _character == null:
		return
	_character.text = character_text()
	attributes_button.disabled = player == null or player.progression == null
	_stats.text = stats_text()
	_loadout.text = loadout_text()
	_talents.text = talent_text()
	_refresh_slots()
	_refresh_bag()
	_refresh_detail()
	if is_inside_tree():
		refresh_focus()


func _refresh_slots() -> void:
	for t: Dictionary in worn_tiles(player):
		var b: Button = _slot_buttons.get(str(t.slot))
		if b == null:
			continue
		var icon := b.find_child("Icon", true, false) as ItemIcon
		var nm := b.find_child("Name", true, false) as Label
		if str(t.id) != "":
			icon.set_thing(str(t.id))
		else:
			icon.kind = "club" if str(t.slot) == "weapon" else str(t.slot)
			icon.tint = Color(1, 1, 1, 0.22)
			icon.empty = true
			icon.queue_redraw()
		nm.text = str(t.text)
		nm.add_theme_color_override("font_color", UiKit.TEXT if str(t.id) != "" else UiKit.MUTED)
		_cell_style(b, Color(0.24, 0.22, 0.16, 0.97) if str(t.slot) == _chosen_slot else UiKit.BG_LIGHT)


func _refresh_bag() -> void:
	for c in _bag.get_children():
		_bag.remove_child(c)
		c.queue_free()
	_cells.clear()
	_cell_ids.clear()
	equip_buttons.clear()
	var entries := bag_entries(player)
	var n := maxi(BAG_COLS * BAG_MIN_ROWS, ceili(float(entries.size()) / BAG_COLS) * BAG_COLS)
	for i in n:
		var b := Button.new()
		b.custom_minimum_size = Vector2(CELL_PX, CELL_PX)
		b.focus_mode = Control.FOCUS_ALL
		if i < entries.size():
			var e: Dictionary = entries[i]
			_cell_style(b, Color(0.24, 0.22, 0.16, 0.97) if str(e.id) == _chosen_cell else Color(0.12, 0.13, 0.16, 0.95))
			b.name = "Cell_" + str(e.id).replace(".", "_")
			var icon := ItemIcon.of(str(e.id), int(e.count), _fresh.has(str(e.id)))
			icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			icon.offset_left = 4
			icon.offset_top = 4
			icon.offset_right = -4
			icon.offset_bottom = -4
			b.add_child(icon)
			b.tooltip_text = str(e.name)
			b.pressed.connect(_on_cell.bind(str(e.id)))
			if str(e.kind) == "weapon":
				equip_buttons[str(e.id)] = b
			_cells.append(b)
			_cell_ids.append(str(e.id))
		else:
			_cell_style(b, Color(0.10, 0.11, 0.13, 0.9))
			b.name = "Cell_empty_%d" % i
			b.focus_mode = Control.FOCUS_NONE
			b.disabled = true
		_bag.add_child(b)


func _refresh_detail() -> void:
	for c in _detail_buttons.get_children():
		_detail_buttons.remove_child(c)
		c.queue_free()
	_option_buttons.clear()
	if _chosen_slot != "":
		_detail_title.text = "%s: %s" % [str(SLOT_NAMES.get(_chosen_slot, _chosen_slot)), _worn_text(_chosen_slot)]
		var opts := slot_choices(player, _chosen_slot)
		var lines := PackedStringArray()
		if opts.is_empty():
			lines.append("Nothing for this slot yet: a forge makes armour from iron, hide and the titans' stone.")
		for o: Dictionary in opts:
			var b := UiKit.button(str(o.label) + ("  (worn)" if bool(o.current) else ""), 13)
			b.disabled = bool(o.current)
			b.pressed.connect(press_option.bind(str(o.id)))
			_detail_buttons.add_child(b)
			_option_buttons.append(b)
		if _chosen_slot != "weapon":
			lines.append_array(CharacterScreen.compare_lines(player, _chosen_slot, ""))
		_detail.text = "\n".join(lines)
		return
	if _chosen_cell == "":
		_detail_title.text = ""
		_detail.text = "Choose a slot to change what he wears, or a thing in the bag to see it." \
			if not _cell_ids.is_empty() else "The bag is empty: loot from fights, titans' plates and quests lands here."
		return
	var e := _entry(_chosen_cell)
	if e.is_empty():
		_chosen_cell = ""
		_refresh_detail()
		return
	_detail_title.text = str(e.name) + ("  x%d" % int(e.count) if int(e.count) > 1 else "")
	var lines2 := PackedStringArray()
	lines2.append(str(KIND_NAMES.get(str(e.kind), str(e.kind).capitalize())) + ("  - new" if _fresh.has(str(e.id)) else ""))
	if str(e.description) != "":
		lines2.append(str(e.description))
	if str(e.kind) == "armour":
		lines2.append_array(CharacterScreen.compare_lines(player, str(Armour.piece(str(e.id)).get("slot", "")), str(e.id)))
	_detail.text = "\n".join(lines2)
	if str(e.kind) in ["armour", "weapon"]:
		var b := UiKit.button("Put on", 14)
		b.pressed.connect(press_cell_action.bind(str(e.id)))
		_detail_buttons.add_child(b)
		_option_buttons.append(b)


func _worn_text(slot: String) -> String:
	for t: Dictionary in worn_tiles(player):
		if str(t.slot) == slot:
			return str(t.text)
	return ""


func _entry(id: String) -> Dictionary:
	for e: Dictionary in bag_entries(player):
		if str(e.id) == id:
			return e
	return {}


func _refresh_preview() -> void:
	if preview == null or player == null or not is_instance_valid(player):
		return
	var rec: Dictionary = player.appearance.record() if player.appearance != null else Appearance.resolve(GameSession.character)
	var anc: String = player.appearance.ancestry() if player.appearance != null else ""
	preview.apply_look(Armour.look_of(rec, CharacterScreen._equipment(), anc))


## Rows: the top buttons; the four rows of slots, each with its bag row; the rest of the bag; the chosen thing's
## buttons; Close.
func focus_rows() -> Array:
	var rows: Array = [[attributes_button, character_button]]
	var bag_rows: Array = []
	for i in range(0, _cells.size(), BAG_COLS):
		bag_rows.append(_cells.slice(i, mini(i + BAG_COLS, _cells.size())))
	for k in 4:
		var row: Array = [_slot_buttons[LEFT_SLOTS[k]], _slot_buttons[RIGHT_SLOTS[k]]]
		if k < bag_rows.size():
			row.append_array(bag_rows[k])
		rows.append(row)
	for k in range(4, bag_rows.size()):
		rows.append(bag_rows[k])
	if not _option_buttons.is_empty():
		rows.append(_option_buttons.duplicate())
	rows.append([close_button])
	return rows


## The bag's cells' ids in order (tests).
func cell_ids() -> Array:
	return _cell_ids.duplicate()


# --------------------------------------------------------------------------- content (static: tests read it)

## The worn slots: [{"slot", "id" ("" empty), "text"}] - the seven armour slots and the weapon.
static func worn_tiles(p: GiantPlayer) -> Array:
	var out: Array = []
	var eq: Dictionary = GameSession.expansion.get("equipment", {})
	var held: Dictionary = eq.get("slots", {})
	for slot: String in LEFT_SLOTS + RIGHT_SLOTS:
		if slot == "weapon":
			var wid := str(p.equipment.weapon_id()) if p != null and is_instance_valid(p) and p.equipment != null else ""
			out.append({"slot": slot, "id": wid, "text": p.equipment.weapon_name(wid) if wid != "" else CharacterScreen.EMPTY_SLOT})
			continue
		var item := str(held.get(slot, ""))
		var ok := item != "" and not Armour.piece(item).is_empty()
		out.append({"slot": slot, "id": item if ok else "",
			"text": Armour.piece_name(item, Armour.tier_of(eq, item)) if ok else CharacterScreen.EMPTY_SLOT})
	return out


## What the bag holds: [{"id", "name", "count", "kind", "description"}] - the weapons owned but not in hand, the
## armour owned but not worn, then the items (WorldState.inventory) by kind (trophy, quest, key, material), each
## kind by name. `p` null: the player in the tree.
static func bag_entries(p: GiantPlayer) -> Array:
	var out: Array = []
	if p == null and Engine.get_main_loop() is SceneTree:
		p = (Engine.get_main_loop() as SceneTree).get_first_node_in_group("player") as GiantPlayer
	if p != null and is_instance_valid(p) and p.equipment != null:
		var hand := str(p.equipment.weapon_id())
		for id: String in p.equipment.owned():
			if id == hand:
				continue
			out.append({"id": id, "name": p.equipment.weapon_label(id), "count": 1, "kind": "weapon",
				"description": str(GameData.get_record(id).get("description", ""))})
	var eq: Dictionary = GameSession.expansion.get("equipment", {})
	var worn_ids := {}
	for s: Variant in (eq.get("slots", {}) as Dictionary).values():
		worn_ids[str(s)] = true
	for id: Variant in (eq.get("pieces", {}) as Dictionary).keys():
		if worn_ids.has(str(id)) or Armour.piece(str(id)).is_empty():
			continue
		var rec := Armour.piece(str(id))
		out.append({"id": str(id), "name": Armour.piece_name(str(id), Armour.tier_of(eq, str(id))), "count": 1,
			"kind": "armour", "description": str(rec.get("description", ""))})
	for row: Dictionary in item_rows():
		var kind := "quest" if bool(row.quest) else str(row.category)
		if not (kind in KIND_ORDER):
			kind = "material"
		out.append({"id": row.id, "name": row.name, "count": row.count, "kind": kind, "description": row.description})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var ka := KIND_ORDER.find(str(a.kind))
		var kb := KIND_ORDER.find(str(b.kind))
		if ka != kb:
			return ka < kb
		return str(a.name) < str(b.name))
	return out


## What `slot` can take: [{"id", "label", "current"}] - the armour pieces owned for it with Take off
## (CharacterScreen.slot_options), or, for the weapon, every weapon owned.
static func slot_choices(p: GiantPlayer, slot: String) -> Array:
	if slot != "weapon":
		return CharacterScreen.slot_options(slot)
	var out: Array = []
	if p == null or not is_instance_valid(p) or p.equipment == null:
		return out
	var hand := str(p.equipment.weapon_id())
	for id: String in p.equipment.owned():
		out.append({"id": id, "label": p.equipment.weapon_label(id), "current": id == hand})
	return out


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


## The giant's numbers: health, stamina, height; armour, poise, weight, the weapon's damage.
func stats_text() -> String:
	if player == null or not is_instance_valid(player) or player.entity == null:
		return ""
	var pools := player.entity.combatant.pools
	var eq: Dictionary = GameSession.expansion.get("equipment", {})
	var base: Dictionary = player.progression.base_passives() if player.progression != null else {}
	var st := Armour.stats(eq if not eq.is_empty() else Armour.empty(), base)
	var rec := GameData.get_record(str(player.equipment.weapon_id())) if player.equipment != null else {}
	var h := float(player.profile.get("height_m", 3.66))
	return "Health %d / %d    Stamina %d / %d    Height %d ft (%.1f m)\nArmour %d (blows %d%% lighter)    Poise +%d    Weight %s    Weapon damage x%.2f" % [
		roundi(pools.health), roundi(pools.health_max), roundi(pools.stamina), roundi(pools.stamina_max),
		roundi(h * CharacterScreen.FT_PER_M), h, roundi(st.armour), roundi(st.less_pct), roundi(st.poise),
		CharacterScreen._num(st.weight), float(rec.get("damage_multiplier", 1.0))]


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


## P33: the talent points and the talents learned (PlayerProgression.talent_line).
func talent_text() -> String:
	var prog: Variant = player.progression if player != null and is_instance_valid(player) else null
	if prog != null and prog.has_method("talent_line"):
		return str(prog.talent_line())
	return "Talent points: %d" % (int(prog.talent_points) if prog != null else 0)


func result_text() -> String:
	return _result.text if _result != null else ""


func detail_text() -> String:
	return (_detail_title.text + "\n" + _detail.text) if _detail != null else ""


# --------------------------------------------------------------------------- actions

## Chooses bag cell `id` (its details below the bag); chosen again, it is put on (a weapon or a piece).
func choose_cell(id: String) -> void:
	if _chosen_cell == id and _chosen_slot == "":
		press_cell_action(id)
		return
	_chosen_cell = id
	_chosen_slot = ""
	refresh()
	_focus_cell(id)


func _on_cell(id: String) -> void:
	choose_cell(id)


## Chooses slot `slot`: what can go there, below the bag.
func choose_slot(slot: String) -> void:
	_chosen_slot = slot
	_chosen_cell = ""
	refresh()
	var b: Button = _slot_buttons.get(slot)
	if b != null and b.is_visible_in_tree():
		b.grab_focus()


## Puts the chosen slot's option `id` on ("-": takes its piece off; a weapon id for the weapon slot).
func press_option(id: String) -> Dictionary:
	if _chosen_slot == "weapon":
		return press_equip(id)
	var out: Dictionary = CharacterScreen.apply_option(player, _chosen_slot, id)
	_show_result(out)
	_refresh_preview()
	refresh()
	return out


## Puts bag thing `id` on: a weapon in hand, an armour piece in its slot.
func press_cell_action(id: String) -> Dictionary:
	var rec := GameData.get_record(id)
	var out: Dictionary = {"ok": false, "message": ""}
	match str(rec.get("type", "")):
		"weapon":
			return press_equip(id)
		"armour":
			out = CharacterScreen.apply_option(player, str(rec.get("slot", "")), id)
	_show_result(out)
	if bool(out.get("ok", false)):
		_chosen_cell = ""
	_refresh_preview()
	refresh()
	return out


## Equips an owned weapon (PlayerEquipment.equip_weapon) and shows the result.
func press_equip(weapon_id: String) -> Dictionary:
	if player == null or player.equipment == null:
		return {"ok": false, "reason": "no_player", "message": ""}
	var out: Dictionary = player.equipment.equip_weapon(weapon_id)
	_show_result(out)
	if bool(out.get("ok", false)) and _chosen_cell == weapon_id:
		_chosen_cell = ""
	refresh()
	return out


func _show_result(out: Dictionary) -> void:
	_result.text = str(out.get("message", ""))
	_result.add_theme_color_override("font_color", UiKit.GOOD if bool(out.get("ok", false)) else UiKit.WARN)


func _focus_cell(id: String) -> void:
	var i := _cell_ids.find(id)
	if i >= 0 and _cells[i].is_visible_in_tree():
		_cells[i].grab_focus()


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


## Opens the Character menu on top of this one, at its Equipment tab (the same equipment).
func open_character() -> UiScreen:
	if stack == null or not is_instance_valid(stack):
		return null
	var s := stack.open("character", {"player": player})
	if s != null:
		if s.has_method("show_tab"):
			s.call("show_tab", CharacterScreen.TABS.find("Equipment"))
		s.closed.connect(_on_attributes_closed)
	return s


func _on_character() -> void:
	open_character()


## The giant's outline behind the slots where no live preview is drawn (headless runs, tests).
class Silhouette:
	extends Control

	func _draw() -> void:
		var c := Color(1, 1, 1, 0.07)
		var w := size.x
		var h := size.y
		var cx := w * 0.5
		draw_circle(Vector2(cx, h * 0.12), w * 0.11, c)
		draw_rect(Rect2(cx - w * 0.2, h * 0.2, w * 0.4, h * 0.34), c)
		draw_rect(Rect2(cx - w * 0.32, h * 0.22, w * 0.1, h * 0.32), c)
		draw_rect(Rect2(cx + w * 0.22, h * 0.22, w * 0.1, h * 0.32), c)
		draw_rect(Rect2(cx - w * 0.18, h * 0.54, w * 0.15, h * 0.42), c)
		draw_rect(Rect2(cx + w * 0.03, h * 0.54, w * 0.15, h * 0.42), c)
