class_name ForgeScreen
extends UiScreen
## The forge screen (plan §2.10.2, §3.14 design 6; P12; B1): ScreenStack SCREENS["forge"], opened when a Forge is used
## (Events.ui_screen_requested("forge", {"forge": forge})). It pauses the game. Three tabs (B1), switched by their
## buttons, Enter on a focused one, the mouse or pad LB / RB:
##   * Weapons: the weapon in hand and what the forge would make of it (P12's one reforge: its damage multiplier and the
##     stage it fits, the cost against what the giant carries, Reforge enabled only when Forge.can_upgrade passes), then
##     the titan weapons the forge's recipes make (B1: the Quarry Maul from Stoneback's slabs) - each a row; the chosen
##     row's detail and its button (Reforge / Forge it).
##   * Armour: every armour recipe by set (Quarry, Iron, Hide) - made here, owned already, or refused with the reason
##     (another forge works titan stone, the settlement is not ready, the materials) - its numbers at tier 1, its set's
##     bonuses, its cost against what the giant carries; Make it (Forge.craft: owned, put on in the Character menu).
##   * Reforge: every armour piece owned - its tier now and the next one's numbers, Reforge to the next tier
##     (Forge.refit: P31's forge tiers and the set's refit steps), and its authored perks, one chosen (Forge.set_perk:
##     never rolled; the set's perk cost).
## Leave (or Esc / pad B) closes it. args: {"forge": Forge, "player": GiantPlayer}.
## Focus (P16): the tab row, then the list's rows, then the chosen row's buttons, then Leave; every direction wraps.
## Read API for tests: show_tab(i), select(i), rows_text(), detail_text(), info_text(), status_text(), result_text(),
## press_reforge(), press_action(), press_perk(id).

const TABS := ["Weapons", "Armour", "Reforge"]
const PANEL_SIZE := Vector2(980, 610)
const LIFT_PX := 14.0
const GOLD := Color(1.0, 0.86, 0.45)
const LIST_W := 340.0
const DETAIL_W := 590.0
const WEAPON_ROW := "weapon"

var forge: Forge
var player: GiantPlayer
var _title: Label
var _info: Label
var _cost: VBoxContainer
var _status: Label
var _result: Label
## The Weapons tab's Reforge (P12's) - also every tab's action button (its text says what it does).
var reforge_button: Button
var leave_button: Button
var _tab_buttons: Array[Button] = []
var _current := 0
var _list: VBoxContainer
var _scroll: ScrollContainer
var _detail: VBoxContainer
var _actions: HBoxContainer
var row_buttons: Array[Button] = []
var perk_buttons: Array[Button] = []
var _rows: Array = []        ## per row: {"kind": weapon | recipe | piece, "id"}
var _chosen := 0
var _detail_lines := PackedStringArray()


func _ready() -> void:
	forge = args.get("forge") as Forge
	player = args.get("player") as GiantPlayer
	if player == null and is_inside_tree():
		player = get_tree().get_first_node_in_group("player") as GiantPlayer
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.5)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(shade)
	var frame := UiKit.panel(Color(0.09, 0.07, 0.06, 0.97))
	frame.name = "Frame"
	frame.mouse_filter = Control.MOUSE_FILTER_STOP
	frame.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	frame.offset_left = -PANEL_SIZE.x * 0.5
	frame.offset_right = PANEL_SIZE.x * 0.5
	frame.offset_top = -PANEL_SIZE.y * 0.5 - LIFT_PX
	frame.offset_bottom = PANEL_SIZE.y * 0.5 - LIFT_PX
	add_child(frame)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	frame.add_child(v)
	_title = UiKit.label(forge.display_name if forge != null else "Forge", 26)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(_title)
	var bar := HBoxContainer.new()
	bar.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_child(bar)
	for i in TABS.size():
		var b := UiKit.button(str(TABS[i]), 17)
		b.pressed.connect(show_tab.bind(i))
		bar.add_child(b)
		_tab_buttons.append(b)
	var row := HBoxContainer.new()
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 14)
	v.add_child(row)
	_scroll = ScrollContainer.new()
	_scroll.custom_minimum_size = Vector2(LIST_W, 0)
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.follow_focus = true
	row.add_child(_scroll)
	_list = VBoxContainer.new()
	_list.custom_minimum_size = Vector2(LIST_W - 14, 0)
	_list.add_theme_constant_override("separation", 3)
	_scroll.add_child(_list)
	var right := VBoxContainer.new()
	right.custom_minimum_size = Vector2(DETAIL_W, 0)
	right.add_theme_constant_override("separation", 6)
	row.add_child(right)
	_detail = VBoxContainer.new()
	_detail.add_theme_constant_override("separation", 2)
	right.add_child(_detail)
	_info = UiKit.label("", 15)
	_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_info.custom_minimum_size = Vector2(DETAIL_W, 0)
	right.add_child(_info)
	_cost = VBoxContainer.new()
	right.add_child(_cost)
	_status = UiKit.label("", 14, UiKit.WARN)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size = Vector2(DETAIL_W, 0)
	right.add_child(_status)
	_actions = HBoxContainer.new()
	_actions.add_theme_constant_override("separation", 10)
	right.add_child(_actions)
	reforge_button = UiKit.button("Reforge", 18)
	reforge_button.pressed.connect(_on_action)
	_actions.add_child(reforge_button)
	_result = UiKit.label("", 14, UiKit.GOOD)
	_result.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_result.custom_minimum_size = Vector2(PANEL_SIZE.x - 40, 0)
	v.add_child(_result)
	leave_button = UiKit.button("Leave", 18)
	leave_button.pressed.connect(cancel)
	var bottom := HBoxContainer.new()
	bottom.alignment = BoxContainer.ALIGNMENT_CENTER
	bottom.add_child(leave_button)
	v.add_child(bottom)
	show_tab(0)


func on_open() -> void:
	refresh()


## The chosen row's action when it can be done, else Leave (P12: Reforge first on the Weapons tab).
func first_focus() -> Control:
	if reforge_button != null and not reforge_button.disabled:
		return reforge_button
	return leave_button


## The tab row, the list's rows, the chosen row's buttons (its action, its perks), Leave (P16 rows, wrapping).
func focus_rows() -> Array:
	var rows: Array = [_tab_buttons.duplicate()]
	for b in row_buttons:
		rows.append([b])
	var acts: Array = [reforge_button]
	acts.append_array(perk_buttons)
	rows.append(acts)
	rows.append([leave_button])
	return rows


func nav_hint(pad: bool) -> String:
	if pad:
		return "D-pad / left stick: move     LB / RB: tabs     A: select     B: leave"
	return "Arrows / Tab: move     Enter: select     Esc: leave     (or use the mouse)"


func tab_names() -> PackedStringArray:
	return PackedStringArray(TABS)


func current_tab() -> String:
	return str(TABS[_current])


func tab_buttons() -> Array[Button]:
	return _tab_buttons.duplicate()


## Shows tab `i` (TABS order): its rows, the first chosen.
func show_tab(i: int) -> void:
	if i < 0 or i >= TABS.size():
		return
	_current = i
	_chosen = 0
	for k in _tab_buttons.size():
		UiKit.set_tab_open(_tab_buttons[k], k == i)
	refresh()
	if is_inside_tree():
		refresh_focus()
		if _tab_buttons[i].is_visible_in_tree():
			_tab_buttons[i].grab_focus()


func _unhandled_input(event: InputEvent) -> void:
	if stack == null or stack.top() != self:
		return
	var step := UiNav.page_step(event)
	if step != 0:
		show_tab((_current + step + TABS.size()) % TABS.size())
		get_viewport().set_input_as_handled()


## Chooses row `i` of the list (its detail and buttons).
func select(i: int) -> void:
	if i < 0 or i >= _rows.size():
		return
	_chosen = i
	_refresh_detail()
	for k in row_buttons.size():
		UiKit.set_tab_open(row_buttons[k], k == i)
	if is_inside_tree():
		refresh_focus()


func refresh() -> void:
	_build_rows()
	_refresh_detail()
	if is_inside_tree():
		refresh_focus()


# --------------------------------------------------------------------------- the rows

func _build_rows() -> void:
	if _list == null:
		return
	for c in _list.get_children():
		_list.remove_child(c)
		c.queue_free()
	row_buttons.clear()
	_rows.clear()
	match current_tab():
		"Weapons":
			_section("Your weapon")
			_row(_weapon_row_text(), {"kind": WEAPON_ROW, "id": ""})
			_section("Titan weapons")
			for r: Dictionary in _recipes("weapon"):
				_row(_recipe_row_text(r), {"kind": "recipe", "id": str(r.recipe)})
		"Armour":
			var by_set := {}
			for r: Dictionary in _recipes("armour"):
				var sid := str(r.get("set", ""))
				if not by_set.has(sid):
					by_set[sid] = []
				(by_set[sid] as Array).append(r)
			for sid: String in _set_order(by_set.keys()):
				_section(str(Armour.set_record(sid).get("display_name", sid)))
				for r: Dictionary in by_set[sid]:
					_row(_recipe_row_text(r), {"kind": "recipe", "id": str(r.recipe)})
		"Reforge":
			var eq := Forge._equipment()
			var any := false
			for sid: String in Armour.set_ids():
				for id: Variant in Armour.set_pieces(sid):
					if Armour.owns(eq, str(id)):
						if not any:
							_section("Your armour")
						any = true
						var t := Armour.tier_of(eq, str(id))
						_row("%s  (tier %d of %d)" % [Armour.piece_name(str(id), t), t, Armour.MAX_TIER],
							{"kind": "piece", "id": str(id)})
			if not any:
				var none := UiKit.label("You have no armour to reforge: make a piece on the Armour tab first.", 14,
					UiKit.MUTED)
				none.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
				none.custom_minimum_size = Vector2(LIST_W - 20, 0)
				_list.add_child(none)
	_chosen = clampi(_chosen, 0, maxi(0, _rows.size() - 1))
	for k in row_buttons.size():
		UiKit.set_tab_open(row_buttons[k], k == _chosen)


## The sets in the screen's order: titan sets (they need a titan's settlement) first, then by id.
static func _set_order(ids: Array) -> Array:
	var out: Array = ids.duplicate()
	out.sort_custom(func(a: Variant, b: Variant) -> bool:
		var wa := str(Armour.set_record(str(a)).get("works", "")) != ""
		var wb := str(Armour.set_record(str(b)).get("works", "")) != ""
		return wa and not wb or (wa == wb and str(a) < str(b)))
	return out


func _section(text: String) -> void:
	_list.add_child(UiKit.label(text, 15, GOLD))


func _row(text: String, data: Dictionary) -> void:
	var b := UiKit.button(text, 14)
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.clip_text = true
	b.custom_minimum_size = Vector2(LIST_W - 20, 0)
	var i := _rows.size()
	b.pressed.connect(_on_row.bind(i))
	b.focus_entered.connect(_on_row_focus.bind(i))
	_list.add_child(b)
	row_buttons.append(b)
	_rows.append(data)


func _on_row(i: int) -> void:
	select(i)
	if reforge_button != null and not reforge_button.disabled and is_inside_tree():
		reforge_button.grab_focus()


func _on_row_focus(i: int) -> void:
	if i != _chosen:
		_chosen = i
		_refresh_detail()
		for k in row_buttons.size():
			UiKit.set_tab_open(row_buttons[k], k == i)


func _recipes(tab: String) -> Array:
	if forge == null or not is_instance_valid(forge):
		return []
	return forge.recipes(player, tab)


func _weapon_row_text() -> String:
	if player == null or not is_instance_valid(player) or player.equipment == null:
		return "No weapon"
	return player.equipment.weapon_name()


static func _recipe_row_text(r: Dictionary) -> String:
	var mark := ""
	match str(r.get("reason", "")):
		"":
			mark = "  - ready"
		"owned":
			mark = "  - owned"
		"works", "locked":
			mark = "  - elsewhere"
		"missing_items":
			mark = "  - needs materials"
	var slot := str(r.get("slot", ""))
	return "%s%s%s" % [str(r.name), " (%s)" % str(Armour.SLOT_NAMES.get(slot, slot)).to_lower() if slot != "" else "", mark]


# --------------------------------------------------------------------------- the detail

func _refresh_detail() -> void:
	if _detail == null:
		return
	for c in _detail.get_children():
		_detail.remove_child(c)
		c.queue_free()
	for c in _cost.get_children():
		_cost.remove_child(c)
		c.queue_free()
	for b in perk_buttons:
		_actions.remove_child(b)
		b.queue_free()
	perk_buttons.clear()
	_detail_lines = PackedStringArray()
	_info.text = ""
	_status.text = ""
	reforge_button.disabled = true
	if forge == null or not is_instance_valid(forge):
		_info.text = "There is no forge here."
		return
	if _rows.is_empty():
		reforge_button.text = "Reforge"
		return
	var row: Dictionary = _rows[_chosen]
	match str(row.kind):
		WEAPON_ROW:
			_detail_weapon()
		"recipe":
			_detail_recipe(str(row.id))
		"piece":
			_detail_piece(str(row.id))


func _dline(text: String, color := UiKit.TEXT, size := 14) -> void:
	var l := UiKit.label(text, size, color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(DETAIL_W, 0)
	_detail.add_child(l)
	_detail_lines.append(text)


func _costs(cost: Array) -> void:
	for c: Dictionary in cost:
		var met := int(c.held) >= int(c.count)
		_cost.add_child(UiKit.label("%s %s x%d (you have %d)" % ["[x]" if met else "[ ]", str(c.name), int(c.count),
			int(c.held)], 14, UiKit.TEXT if met else UiKit.WARN))


## P12: the weapon in hand and its reforge.
func _detail_weapon() -> void:
	var check := forge.can_upgrade(player)
	_dline(_weapon_row_text(), GOLD, 17)
	_info.text = info_text_for(check)
	if str(check.get("perk", "")) != "":
		_dline("Its perk: " + str(check.perk), UiKit.MUTED)
	_costs(check.cost)
	_status.text = "" if bool(check.ok) else str(check.message)
	reforge_button.text = "Reforge"
	reforge_button.disabled = not bool(check.ok)


## B1: a recipe - an armour piece or a titan weapon - and Make it / Forge it.
func _detail_recipe(recipe_id: String) -> void:
	var r := forge.can_craft(player, recipe_id)
	var makes := str(r.makes)
	var rec := GameData.get_record(makes)
	_dline(str(r.name), GOLD, 17)
	if makes.begins_with("weapon."):
		_dline(str(rec.get("description", "")))
		_dline("Damage x%.2f    Length %.1f m    Fits up to stage %d" % [float(rec.get("damage_multiplier", 1.0)),
			float(rec.get("length_m", 0.0)), int(rec.get("fit_max_stage", 6))], UiKit.MUTED)
		var heavy := GameData.get_action(str(rec.get("heavy", "")))
		if heavy != null:
			_dline("Heavy: %s - %s" % [heavy.display_name, str(heavy.param("description", "")).get_slice(": ", 1)], UiKit.MUTED, 13)
		reforge_button.text = "Forge it"
	else:
		for l: String in piece_lines(makes, 1):
			_dline(l, UiKit.MUTED, 13)
		reforge_button.text = "Make it"
	_costs(r.cost)
	_status.text = "" if bool(r.ok) else str(r.message)
	reforge_button.disabled = not bool(r.ok)


## B1: an owned piece - its tier, the next one's numbers and Reforge, and its perks.
func _detail_piece(id: String) -> void:
	var eq := Forge._equipment()
	var t := Armour.tier_of(eq, id)
	_dline("%s  (tier %d of %d)" % [Armour.piece_name(id, t), t, Armour.MAX_TIER], GOLD, 17)
	for l: String in piece_lines(id, t):
		_dline(l, UiKit.MUTED, 13)
	var r := forge.can_refit(player, id)
	if str(r.reason) != "max_tier":
		_dline("Reforged to tier %d: %s" % [t + 1, ", ".join(piece_lines(id, t + 1).slice(0, 1))], UiKit.TEXT, 13)
		_costs(r.cost)
	reforge_button.text = "Reforge to tier %d" % (t + 1) if str(r.reason) != "max_tier" else "Fully reforged"
	reforge_button.disabled = not bool(r.ok)
	_status.text = "" if bool(r.ok) else str(r.message)
	var cur := Armour.perk_of(eq, id)
	var pc := Forge.cost_lines(Armour.perk_cost(id))
	var cost_words := PackedStringArray()
	for c: Dictionary in pc:
		cost_words.append("%s x%d (you have %d)" % [str(c.name), int(c.count), int(c.held)])
	_dline("Perk (one at a time, chosen - each change costs %s):" % ", ".join(cost_words), UiKit.TEXT, 13)
	for pid: Variant in Armour.piece(id).get("perks", []):
		var pk := Armour.perk(str(pid))
		var b := UiKit.button("%s%s" % [str(pk.get("display_name", pid)), " (set)" if str(pid) == cur else ""], 13)
		b.tooltip_text = str(pk.get("text", ""))
		var can := forge.can_set_perk(player, id, str(pid))
		b.disabled = not bool(can.ok)
		b.pressed.connect(press_perk.bind(str(pid)))
		_actions.add_child(b)
		perk_buttons.append(b)
		_detail_lines.append("perk %s: %s%s" % [str(pk.get("display_name", pid)), str(pk.get("text", "")),
			" (set)" if str(pid) == cur else ""])
		_dline("  %s: %s" % [str(pk.get("display_name", pid)), str(pk.get("text", ""))], UiKit.MUTED, 12)


## An armour piece's numbers at `tier`: "Armour 9 (blows 8% lighter alone), poise +10, weight 3", its resistances and
## own modifiers, its set and the set's bonuses.
static func piece_lines(id: String, tier: int) -> PackedStringArray:
	var out := PackedStringArray()
	var rec := Armour.piece(id)
	if rec.is_empty():
		return out
	var eq := Armour.empty()
	eq.pieces[id] = {"tier": clampi(tier, 1, Armour.MAX_TIER), "perk": ""}
	eq.slots[str(rec.slot)] = id
	var m := Armour.modifiers(eq)
	var a := float((m.modifiers as Dictionary).get("armor_flat", 0.0))
	var parts := PackedStringArray()
	parts.append("Armour %d (blows %d%% lighter alone)" % [roundi(a), roundi((1.0 - 100.0 / (100.0 + a)) * 100.0)])
	var poise := float((m.modifiers as Dictionary).get("poise_threshold_add", 0.0))
	if poise > 0.0:
		parts.append("poise +%d" % roundi(poise))
	parts.append("weight %s" % CharacterScreen._num(float(rec.get("weight", 0.0))))
	out.append(", ".join(parts))
	var extra := PackedStringArray()
	for t: Variant in m.resistances:
		extra.append("%s resistance +%d%%" % [str(t).capitalize(), roundi(float(m.resistances[t]) * 100.0)])
	if typeof(rec.get("modifiers")) == TYPE_DICTIONARY:
		extra.append_array(Talents.modifier_lines(rec.modifiers))
	if not extra.is_empty():
		out.append(", ".join(extra))
	out.append(str(rec.get("description", "")))
	var srec := Armour.set_record(str(rec.get("set", "")))
	for b: Variant in srec.get("bonuses", []):
		if typeof(b) == TYPE_DICTIONARY:
			out.append("%s, %d pieces - %s: %s" % [str(srec.get("display_name", "")), int(b.pieces), str(b.name), str(b.text)])
	return out


## The offer as text: "Oak Club -> Reinforced Club: x1.15 damage, fits a stage-3 giant."
static func info_text_for(check: Dictionary) -> String:
	if str(check.get("from", "")) == "":
		return "You carry no weapon to reforge."
	if str(check.get("to", "")) == "":
		return "%s: it cannot be reforged any further." % str(check.from_name)
	return "%s -> %s: x%.2f damage, fits a stage-%d giant." % [str(check.from_name), str(check.to_name),
		float(check.to_multiplier), int(check.to_fit)]


# --------------------------------------------------------------------------- doing it

## The Reforge button (also used by tests and the bot's screen path): Forge.upgrade (the Weapons tab's weapon row).
func press_reforge() -> Dictionary:
	if forge == null or not is_instance_valid(forge):
		return {"ok": false, "reason": "no_forge", "message": ""}
	var out := forge.upgrade(player)
	_show_result(out)
	return out


## The chosen row's action: the weapon's reforge, a recipe's making, a piece's next tier.
func press_action() -> Dictionary:
	if forge == null or not is_instance_valid(forge) or _rows.is_empty():
		return {"ok": false, "reason": "no_forge", "message": ""}
	var row: Dictionary = _rows[_chosen]
	match str(row.kind):
		WEAPON_ROW:
			return press_reforge()
		"recipe":
			var out := forge.craft(player, str(row.id))
			_show_result(out)
			return out
		"piece":
			var out := forge.refit(player, str(row.id))
			_show_result(out)
			return out
	return {"ok": false, "reason": "unknown", "message": ""}


## Sets perk `perk_id` on the chosen piece (the Reforge tab).
func press_perk(perk_id: String) -> Dictionary:
	if forge == null or _rows.is_empty() or str((_rows[_chosen] as Dictionary).kind) != "piece":
		return {"ok": false, "reason": "unknown", "message": ""}
	var out := forge.set_perk(player, str(_rows[_chosen].id), perk_id)
	_show_result(out)
	return out


func _show_result(out: Dictionary) -> void:
	_result.text = str(out.get("message", ""))
	_result.add_theme_color_override("font_color", UiKit.GOOD if bool(out.get("ok", false)) else UiKit.WARN)
	var keep := _chosen
	refresh()
	select(keep)
	if bool(out.get("ok", false)) and is_inside_tree() and (reforge_button.disabled or not reforge_button.is_visible_in_tree()):
		leave_button.grab_focus()


func _on_action() -> void:
	press_action()


func info_text() -> String:
	return _info.text if _info != null else ""


func status_text() -> String:
	return _status.text if _status != null else ""


func result_text() -> String:
	return _result.text if _result != null else ""


## The list's rows as text (tests).
func rows_text() -> PackedStringArray:
	var out := PackedStringArray()
	for b in row_buttons:
		out.append(b.text)
	return out


## The chosen row's detail as text (tests).
func detail_text() -> String:
	return "\n".join(_detail_lines) + ("\n" + _info.text if _info != null and _info.text != "" else "") \
		+ ("\n" + _status.text if _status != null and _status.text != "" else "")
