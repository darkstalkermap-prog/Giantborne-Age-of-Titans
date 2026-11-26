class_name CharacterScreen
extends UiScreen
## The Character menu (A4): ScreenStack SCREENS["character"], opened at any time in play with the `character`
## action (C / pad Y by default; remappable as every binding: InputBindings) or from the pause menu's Character
## entry; it pauses the game like every screen. Read-only: what the giant is, where it can grow, what it carries.
## Six tabs (TABS; C4 added Settlements), switched by their buttons, Enter on a focused one, the mouse, or pad LB / RB:
##   * Giant: the level, the XP to the next, the growth stage and the height in feet and metres, and the growth
##     track of stages 1-10 (heights 12-140 ft at levels 1-20): reached, next (what it needs: the level, and where
##     the world's shrines grow it with their conditions where the data says so) and to come; stages 7-10 as
##     locked "beyond the rim" with their heights only. Beside it the giant itself (the creator's GiantPreview,
##     where a display draws it).
##   * Attributes: the attributes, the unspent points, the ancestry and the talents (read-only: the shrine's
##     Attributes, Talents and Ancestry tabs change them, and the tab says so).
##   * Equipment (B1): the weapon in hand and its numbers, and the seven armour slots (head, shoulders, chest, arms,
##     waist, legs, trinket: GameSession.expansion.equipment, Armour) - each slot a row with what it wears (its tier
##     and perk) and a Shown / Hidden toggle (a hidden piece still counts: the look keeps the giant's own clothes
##     there); choosing a slot lists the pieces owned for it and Take off, each with its numbers before -> after
##     (armour and the share of a blow it turns, poise, stamina recovery, weight, resistances); the set bonuses worn
##     and the totals. Out of combat only (Armour.change_blocked: armour goes on and off anywhere a checkpoint could
##     be taken; forges make and reforge it). The giant beside it in the armour shown.
##   * Titans: the ten signature titans (the roster, data/titans/titan_roster.json) as a trophy list - Stoneback
##     with his state (unseen, sighted, slain), the most plates broken in a fight, his kills and what he dropped;
##     every other titan "???" beside a dark silhouette until met (nothing of it named).
##   * Materials: the titans' materials held (his heart-stone, slabs and quarry iron) and the other crafting items.
##   * Settlements (C4): every settlement the giant has found - its tier and what is being earned, each project with what
##     it still needs (SettlementScreen.summary_lines); a button per settlement opens its panel (giving and trading
##     work from here too, out of combat).
## A5: in the open world a "Watch the intro" button beside Close plays the intro cutscene over the live world (the
## menu and the pause menu below it close first; GameSession.play_cutscene), when a checkpoint could be taken now
## (no fight engaged, no enemy hunting the giant: GameSession.checkpoint_blockers) - else it is shown disabled.
## Pad and keyboard (P16): the tab row, then Close (and the intro's button); every direction wraps. The content fits 1280 x 720 at any level
## (test_character_screen). Read API for tests: tab_names(), show_tab(i), lines() (the shown tab as text) and the
## static content builders (giant_info, growth_track, attribute_lines, equipment_rows, titan_rows, material_rows).

const TABS := ["Giant", "Attributes", "Equipment", "Titans", "Materials", "Settlements"]
const PANEL_SIZE := Vector2(940, 600)
const LIFT_PX := 16.0
const GOLD := Color(1.0, 0.86, 0.45)
const FT_PER_M := 3.28084
## The approved story's stages beyond the six built (docs/DECISIONS.md section 2.7): [stage, height ft, level].
## C1: a stage with a growth profile is shown from it; only the rest (9 and 10 now) as these locked rows.
const BEYOND := [[7, 78, 13], [8, 96, 15], [9, 116, 17], [10, 140, 20]]
const BEYOND_TEXT := "Beyond the rim"
## The materials the titans leave, shown first in the Materials tab: A4's Stoneback three (kept for the tests that name
## them); B4: every titan of the roster's now (titan_materials: B2 and B3 left the King's and the Rootwarden's among
## "Other materials", without their words).
const TITAN_MATERIALS := ["item.stoneback_heart_stone", "item.stoneback_slab", "item.quarry_iron"]
const SLOT_NAMES := {"head": "Head", "shoulders": "Shoulders", "chest": "Chest", "arms": "Arms", "waist": "Waist",
	"legs": "Legs", "trinket": "Trinket"}
const NOT_YET := "not yet available"
## B1: an empty armour slot's row; a slot's own row (EQUIP_SLOT_W px) and its toggle's words.
const EMPTY_SLOT := "empty"
const SHOWN := "Shown"
const HIDDEN := "Hidden"
const TAKE_OFF := "Take off"
## B1: the Equipment tab's right column (the chosen slot's options and their numbers).
const EQ_RIGHT_W := 352
const STATE_TEXT := {"unseen": "Not yet seen", "sighted": "Sighted", "slain": "Slain"}
const WATCH_INTRO := "Watch the intro"
const WATCH_INTRO_BLOCKED := "Watch the intro (not in a fight)"

var player: GiantPlayer
## C4: the Settlements tab's buttons (each opens a settlement's panel).
var settlement_buttons: Array[Button] = []
## A5: the intro again (in the open world only; disabled while a checkpoint could not be taken).
var intro_button: Button
var close_button: Button
var preview: GiantPreview = null
var _tab_buttons: Array[Button] = []
var _current := 0
var _body: VBoxContainer
var _side: Control
var _lines: PackedStringArray = []
## B1: the Equipment tab - the slot chosen, its rows' buttons, the options of the slot chosen and the status line.
var eq_slot := "head"
var slot_buttons: Array[Button] = []
var show_buttons: Array[Button] = []
var option_buttons: Array[Button] = []
var _option_ids: Array = []
var _compare: VBoxContainer
var _eq_status: Label


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
	frame.offset_top = -PANEL_SIZE.y * 0.5 - LIFT_PX
	frame.offset_bottom = PANEL_SIZE.y * 0.5 - LIFT_PX
	add_child(frame)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	frame.add_child(v)
	var title := UiKit.label("Character", 28)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(title)
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
	row.add_theme_constant_override("separation", 12)
	v.add_child(row)
	_body = VBoxContainer.new()
	_body.name = "Body"
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.add_theme_constant_override("separation", 3)
	row.add_child(_body)
	_side = Control.new()
	_side.name = "Side"
	_side.custom_minimum_size = Vector2(250, 0)
	_side.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(_side)
	if wants_preview():
		preview = GiantPreview.new()
		preview.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_side.add_child(preview)
	var bottom := HBoxContainer.new()
	bottom.alignment = BoxContainer.ALIGNMENT_CENTER
	bottom.add_theme_constant_override("separation", 16)
	v.add_child(bottom)
	intro_button = UiKit.button(WATCH_INTRO, 18)
	intro_button.name = "WatchIntro"
	intro_button.pressed.connect(_on_watch_intro)
	bottom.add_child(intro_button)
	close_button = UiKit.button("Close", 18)
	close_button.pressed.connect(cancel)
	bottom.add_child(close_button)
	_refresh_intro_button()
	show_tab(0)


## The live giant beside the Giant tab only where a display draws it (headless runs and tests have none: the
## preview's model would load for nothing).
static func wants_preview() -> bool:
	return DisplayServer.get_name() != "headless"


func on_open() -> void:
	_refresh_intro_button()
	show_tab(_current)
	if preview != null and player != null and is_instance_valid(player):
		preview.set_game_profile(player.profile)
		_refresh_preview()


func first_focus() -> Control:
	return _tab_buttons[_current] if _current < _tab_buttons.size() else close_button


## The tab row, then Close (and the intro's button where it shows; P16 rows, wrapping). B1: on the Equipment tab
## between them each slot's row (the slot, its Shown / Hidden toggle) and the chosen slot's options.
func focus_rows() -> Array:
	var rows: Array = [_tab_buttons.duplicate()]
	if current_tab() == "Equipment":
		for i in slot_buttons.size():
			rows.append([slot_buttons[i], show_buttons[i]])
		if not option_buttons.is_empty():
			rows.append(option_buttons.duplicate())
	if current_tab() == "Settlements":
		for b in settlement_buttons:
			rows.append([b])
	if intro_button != null and intro_button.visible:
		rows.append([intro_button, close_button])
	else:
		rows.append([close_button])
	return rows


## A5: whether the intro can be replayed from here at all: in play in the open world (not in the cutscene-only
## session, where the title's button plays it) with its record.
static func intro_place_ok() -> bool:
	return GameSession.level_id == GameSession.WORLD_LEVEL_ID and not GameSession.cinematic_only \
		and GameSession.current_level() is WorldRoot and not GameData.get_record(ExpansionState.INTRO_ID).is_empty()


## A5: why the intro cannot play now ("" when it can): only while a checkpoint could be taken (this menu aside).
static func intro_blocked() -> String:
	for b: String in GameSession.checkpoint_blockers():
		if b != "screen":
			return b
	return ""


func _refresh_intro_button() -> void:
	if intro_button == null:
		return
	intro_button.visible = intro_place_ok()
	var blocked := intro_blocked() != "" if intro_button.visible else true
	intro_button.disabled = blocked
	intro_button.text = WATCH_INTRO_BLOCKED if blocked and intro_button.visible else WATCH_INTRO


func _on_watch_intro() -> void:
	if not intro_place_ok() or intro_blocked() != "":
		_refresh_intro_button()
		return
	var st := stack
	if st != null:
		st.close_all()
	GameSession.play_cutscene(ExpansionState.INTRO_ID)


## The footer line: how to move, switch tabs and close with the device in use, the Character binding's own glyph
## among them (it follows a remapping: InputBindings).
func nav_hint(pad: bool) -> String:
	if pad:
		var b := InputBindings.short_pad_label("character")
		return "D-pad / left stick: move     LB / RB: tabs     A: select     B%s: close" % (" or " + b if b != "" else "")
	var k := InputBindings.describe_action("character", false)
	return "Arrows / Tab: move     Enter: select     Esc%s: close     (or use the mouse)" % (
		" or " + k if k != "-" else "")


func tab_names() -> PackedStringArray:
	return PackedStringArray(TABS)


func tab_buttons() -> Array[Button]:
	return _tab_buttons.duplicate()


func current_tab() -> String:
	return str(TABS[_current])


## C4: shows the tab named `tab_name` (the tour's shots, the Settlements entry).
func show_tab_named(tab_name: String) -> void:
	show_tab(TABS.find(tab_name))


## Shows tab `i` (TABS order) and rebuilds its content.
func show_tab(i: int) -> void:
	if i < 0 or i >= TABS.size():
		return
	_current = i
	for k in _tab_buttons.size():
		UiKit.set_tab_open(_tab_buttons[k], k == i)
	_rebuild()
	if _side != null:
		_side.visible = (TABS[i] == "Giant" or TABS[i] == "Equipment") and preview != null
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
		return
	if event.is_action_pressed("character") and not MapScreen.is_ui_direction(event):
		close({"closed": "character"})
		get_viewport().set_input_as_handled()


## The shown tab as text lines ("# Heading" for a heading; tests).
func lines() -> PackedStringArray:
	return _lines


# --------------------------------------------------------------------------- building a tab

func _rebuild() -> void:
	if _body == null:
		return
	for c in _body.get_children():
		_body.remove_child(c)
		c.queue_free()
	_lines = PackedStringArray()
	match str(TABS[_current]):
		"Giant":
			_build_giant()
		"Attributes":
			_build_attributes()
		"Equipment":
			_build_equipment()
		"Titans":
			_build_titans()
		"Materials":
			_build_materials()
		"Settlements":
			_build_settlements()


func _heading(text: String) -> void:
	_body.add_child(UiKit.label(text, 18, GOLD))
	_lines.append("# " + text)


func _line(text: String, color := UiKit.TEXT, size := 14) -> Label:
	var l := UiKit.label(text, size, color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(620, 0)
	_body.add_child(l)
	_lines.append(text)
	return l


func _build_giant() -> void:
	var g := giant_info(player)
	_heading("Your giant")
	_line("Level %d    %s" % [int(g.level), str(g.xp_text)])
	_line("Stage %d: %s    %d ft (%.1f m)" % [int(g.stage), str(g.stage_name), int(g.height_ft), float(g.height_m)])
	_heading("Growth")
	for r: Dictionary in growth_track(player):
		var color := UiKit.GOOD if str(r.state) == "reached" else (GOLD if str(r.state) == "next" else UiKit.MUTED)
		var text := "Stage %d   %d ft   level %d   %s" % [int(r.stage), int(r.height_ft), int(r.level), str(r.text)]
		_line(text, color, 13)


## C4: the Settlements tab - each settlement the giant has found (its POI discovered, or work begun there), its tier,
## what is being earned and what each project still needs; a button opens its panel.
func _build_settlements() -> void:
	settlement_buttons.clear()
	var any := false
	for r: Dictionary in known_settlements():
		any = true
		for l: String in SettlementScreen.summary_lines(r):
			if l.begins_with("# "):
				_heading(l.substr(2))
			else:
				_line(l, UiKit.TEXT, 13)
		var b := UiKit.button("Open %s's panel" % str(r.display_name), 14)
		b.pressed.connect(_open_settlement.bind(str(r.id)))
		_body.add_child(b)
		settlement_buttons.append(b)
	if not any:
		_line("No settlement asks anything of you yet.", UiKit.MUTED)


## C4: the settlements the giant has found: its POI discovered, its tier above 0, or a project begun.
static func known_settlements() -> Array:
	var out: Array = []
	for r: Dictionary in SettlementRules.records():
		var st: Variant = (GameSession.expansion.get("settlements", {}) as Dictionary).get(str(r.poi))
		var begun := typeof(st) == TYPE_DICTIONARY and (int(st.get("level", 0)) > 0 or not (st.get("projects", {}) as Dictionary).is_empty())
		var found := QuestConditions.truthy(WorldState.get_flag(Discovery.discovered_flag(str(r.poi)))) \
			if str(r.get("level", "")) == "level.world" else false   # (the Valley's: once its first tier has come)
		if begun or found or SettlementRules.tier_from_flags(r, WorldState.flags) > 0:
			out.append(r)
	return out


func _open_settlement(id: String) -> void:
	if stack != null and is_instance_valid(stack):
		stack.open("settlement", {"settlement": id, "player": player})


func _build_attributes() -> void:
	_heading("Attributes")
	for l: String in attribute_lines(player):
		_line(l, UiKit.MUTED if l.begins_with("Change") else UiKit.TEXT)


func _build_equipment() -> void:
	slot_buttons.clear()
	show_buttons.clear()
	option_buttons.clear()
	_option_ids.clear()
	var e := equipment_rows(player)
	_line("Weapon: " + weapon_summary(player), UiKit.TEXT, 13)
	_heading("Armour")
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 14)
	_body.add_child(cols)
	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(286, 0)
	left.add_theme_constant_override("separation", 2)
	cols.add_child(left)
	for r: Dictionary in e.slots:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		var b := UiKit.button("%s: %s" % [str(r.name), str(r.text)], 13)
		b.custom_minimum_size = Vector2(226, 0)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		# B2 (B1's last-pass row): a long reforged name and its perk wrap onto a second line, never cut short
		b.clip_text = false
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		b.tooltip_text = b.text
		b.pressed.connect(_choose_slot.bind(str(r.slot)))
		UiKit.set_tab_open(b, str(r.slot) == eq_slot)
		row.add_child(b)
		var t := UiKit.button(("-" if str(r.item) == "" else (HIDDEN if bool(r.hidden) else SHOWN)), 13)
		t.custom_minimum_size = Vector2(54, 0)
		t.disabled = str(r.item) == ""
		t.tooltip_text = "Show or hide this piece on your giant (a hidden piece still counts)"
		t.pressed.connect(_toggle_shown.bind(str(r.slot)))
		row.add_child(t)
		left.add_child(row)
		slot_buttons.append(b)
		show_buttons.append(t)
		_lines.append("%s: %s%s" % [str(r.name), str(r.text), " (hidden)" if bool(r.hidden) else ""])
	var right := VBoxContainer.new()
	right.custom_minimum_size = Vector2(EQ_RIGHT_W, 0)
	right.add_theme_constant_override("separation", 3)
	cols.add_child(right)
	var opts := slot_options(eq_slot)
	var head := UiKit.label("%s: what you have for it" % str(Armour.SLOT_NAMES.get(eq_slot, eq_slot)), 15, GOLD)
	right.add_child(head)
	_lines.append("# " + head.text)
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 6)
	flow.add_theme_constant_override("v_separation", 4)
	right.add_child(flow)
	for o: Dictionary in opts:
		var b := UiKit.button(str(o.label), 13)
		b.disabled = bool(o.current)
		b.pressed.connect(_choose_option.bind(str(o.id)))
		b.focus_entered.connect(_show_compare.bind(str(o.id)))
		b.mouse_entered.connect(_show_compare.bind(str(o.id)))
		flow.add_child(b)
		option_buttons.append(b)
		_option_ids.append(str(o.id))
		_lines.append("- " + str(o.label) + (" (worn)" if bool(o.current) else ""))
	if opts.is_empty():
		var none := UiKit.label("Nothing for this slot yet: a forge makes armour from iron, hide and the titans' stone.", 12,
			UiKit.MUTED)
		none.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		none.custom_minimum_size = Vector2(EQ_RIGHT_W, 0)
		right.add_child(none)
		_lines.append(none.text)
	_compare = VBoxContainer.new()
	_compare.add_theme_constant_override("separation", 1)
	right.add_child(_compare)
	_eq_status = UiKit.label("", 12, UiKit.WARN)
	_eq_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_eq_status.custom_minimum_size = Vector2(EQ_RIGHT_W, 0)
	right.add_child(_eq_status)
	var blocked := Armour.change_blocked()
	if blocked != "":
		_eq_status.text = blocked
	_show_compare(_option_ids[0] if not _option_ids.is_empty() and option_buttons[0].disabled == false else "")
	_heading("Worn")
	for l: String in worn_lines(player):
		_line(l, UiKit.MUTED if l.begins_with("(") else UiKit.TEXT, 13)


## B1: the comparison block for option `id` of the chosen slot ("" = the totals worn now; TAKE_OFF's id is "-").
func _show_compare(id: String) -> void:
	if _compare == null or not is_instance_valid(_compare):
		return
	for c in _compare.get_children():
		_compare.remove_child(c)
		c.queue_free()
	for l: String in compare_lines(player, eq_slot, id):
		var good := l.contains(": better")
		var bad := l.contains(": worse")
		var lab := UiKit.label(l, 12, UiKit.GOOD if good and not bad else (UiKit.WARN if bad and not good else UiKit.TEXT))
		lab.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		lab.custom_minimum_size = Vector2(EQ_RIGHT_W, 0)
		_compare.add_child(lab)


func _choose_slot(slot: String) -> void:
	eq_slot = slot
	var i := Armour.SLOTS.find(slot)
	_rebuild()
	if is_inside_tree():
		refresh_focus()
		if not option_buttons.is_empty() and option_buttons.any(func(b: Button) -> bool: return not b.disabled):
			for b in option_buttons:
				if not b.disabled:
					b.grab_focus()
					break
		elif i >= 0 and i < slot_buttons.size():
			slot_buttons[i].grab_focus()


func _toggle_shown(slot: String) -> void:
	var eq := _equipment()
	Armour.set_hidden(eq, slot, not Armour.is_hidden(eq, slot))
	Armour.refresh_player(player)
	Events.armour_changed.emit(Sim.tick, "hidden" if Armour.is_hidden(eq, slot) else "shown", str(eq.slots.get(slot, "")))
	var i := Armour.SLOTS.find(slot)
	_rebuild()
	_refresh_preview()
	if is_inside_tree():
		refresh_focus()
		if i >= 0 and i < show_buttons.size():
			show_buttons[i].grab_focus()


## Puts on piece `id` (or takes off the slot's piece for "-"), when not in a fight.
func _choose_option(id: String) -> void:
	var r := apply_option(player, eq_slot, id)
	_rebuild()
	_refresh_preview()
	if _eq_status != null:
		_eq_status.text = str(r.message)
		_eq_status.add_theme_color_override("font_color", UiKit.GOOD if bool(r.ok) else UiKit.WARN)
	if is_inside_tree():
		refresh_focus()
		var i := Armour.SLOTS.find(eq_slot)
		if i >= 0 and i < slot_buttons.size():
			slot_buttons[i].grab_focus()


## The giant beside the tab in its look and the armour shown.
func _refresh_preview() -> void:
	if preview == null or player == null or not is_instance_valid(player):
		return
	var rec: Dictionary = player.appearance.record() if player.appearance != null else Appearance.resolve(GameSession.character)
	var anc: String = player.appearance.ancestry() if player.appearance != null else ""
	preview.apply_look(Armour.look_of(rec, _equipment(), anc))


static func _equipment() -> Dictionary:
	var eq: Variant = GameSession.expansion.get("equipment")
	if typeof(eq) != TYPE_DICTIONARY:
		GameSession.expansion["equipment"] = Armour.empty()
	for k: String in ["slots", "pieces", "hidden"]:
		if typeof((GameSession.expansion.equipment as Dictionary).get(k)) != TYPE_DICTIONARY:
			GameSession.expansion.equipment[k] = Armour.empty()[k]
	return GameSession.expansion.equipment


func _build_titans() -> void:
	_heading("The signature titans")
	for r: Dictionary in titan_rows(GameSession.expansion):
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		var mark := ColorRect.new()
		mark.custom_minimum_size = Vector2(16, 22)
		mark.color = Color(0.02, 0.02, 0.03) if not bool(r.known) else (
			Color(0.62, 0.42, 0.25) if str(r.state) == "slain" else Color(0.45, 0.43, 0.40))
		mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(mark)
		var l := UiKit.label(str(r.text), 14, UiKit.TEXT if bool(r.known) else UiKit.MUTED)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size = Vector2(600, 0)
		row.add_child(l)
		_body.add_child(row)
		_lines.append(str(r.text))


func _build_materials() -> void:
	var m := material_rows()
	_heading("Titan materials")
	if (m.titan as Array).is_empty():
		_line("None yet: the titans leave stone and iron that later forges will work.", UiKit.MUTED)
	for r: Dictionary in m.titan:
		_line("%s  x%d   %s" % [str(r.name), int(r.count), str(r.text)])
	_heading("Other materials")
	if (m.other as Array).is_empty():
		_line("None.", UiKit.MUTED)
	# D1: the other materials on shared lines (the Frostbound's three made the titans' list too long for the window)
	var others := PackedStringArray()
	for r: Dictionary in m.other:
		others.append("%s  x%d" % [str(r.name), int(r.count)])
	if not others.is_empty():
		_line("     ".join(others))


# --------------------------------------------------------------------------- content (static: tests read it)

## {"level", "xp_text", "stage", "stage_name", "height_m", "height_ft"} of the giant (the player, else the
## session's character).
static func giant_info(p: GiantPlayer) -> Dictionary:
	var level := int(GameSession.character.get("level", 1))
	var xp_text := ""
	var stage := int(GameSession.character.get("growth_stage", 1))
	if p != null and is_instance_valid(p) and p.progression != null:
		level = int(p.progression.level)
		stage = int(p.growth.stage()) if p.growth != null else int(p.profile.get("stage", stage))
		if p.progression.at_level_cap():
			xp_text = "the highest level"
		else:
			xp_text = "XP %d / %d to level %d" % [p.progression.xp_into_level(), p.progression.xp_needed(), level + 1]
	var prof := TitanDuel.profile(stage)
	var h := float(prof.get("height_m", 3.66))
	return {"level": level, "xp_text": xp_text, "stage": stage,
		"stage_name": str(prof.get("display_name", "")).get_slice(" (", 0), "height_m": h,
		"height_ft": int(round(h * FT_PER_M))}


## The growth track, stages 1-10: [{"stage", "height_ft", "level", "state": reached | next | later | beyond,
## "text"}]. Stages 1-6 come from the growth profiles (their heights and required levels); the next stage says
## what it needs - the level, and the shrines that grow a giant to it with their conditions; 7-10 are BEYOND.
static func growth_track(p: GiantPlayer) -> Array:
	var info := giant_info(p)
	var stage := int(info.stage)
	var level := int(info.level)
	var out: Array = []
	var built := 0   # C1: every stage with a growth profile (1-8), not six
	for rec: Dictionary in GameData.records_of_type("growth_profile"):
		built = maxi(built, int(rec.get("stage", 0)))
	for s in range(1, built + 1):
		var prof := TitanDuel.profile(s)
		if prof.is_empty():
			continue
		var need := int(prof.get("required_level", 1))
		var row := {"stage": s, "height_ft": int(round(float(prof.get("height_m", 0.0)) * FT_PER_M)), "level": need,
			"state": "reached" if s <= stage else ("next" if s == stage + 1 else "later"), "text": ""}
		if s <= stage:
			row.text = "reached" if s < stage else "you are here"
		elif s == stage + 1:
			row.text = "next: " + needs_text(s, level, need)
		else:
			row.text = "later"
			var req: Variant = prof.get("growth_requirement")   # C1: what a later stage asks, told plainly
			if typeof(req) == TYPE_DICTIONARY and str((req as Dictionary).get("track_text", "")) != "":
				row.text = "later: " + str(req.track_text)
		out.append(row)
	for b: Array in BEYOND:
		if int(b[0]) <= built:
			continue
		out.append({"stage": int(b[0]), "height_ft": int(b[1]), "level": int(b[2]), "state": "beyond",
			"text": "%s (locked)" % BEYOND_TEXT})
	return out


## What growing to `stage` needs at `level`: the required level, and where (the shrines whose max_stage is that
## stage, with the first of their conditions' texts).
static func needs_text(stage: int, level: int, need: int) -> String:
	var parts := PackedStringArray()
	parts.append("level %d (you are %d)" % [need, level] if level < need else "level %d (met)" % need)
	var names := PackedStringArray()
	var cond := ""
	for rec: Dictionary in GameData.records_of_type("shrine"):
		if str(rec.id) == "shrine.sandbox" or not bool(rec.get("allows_growth", false)) \
				or int(rec.get("max_stage", 0)) != stage:
			continue
		names.append(str(rec.get("display_name", rec.id)))
		var texts: Variant = rec.get("growth_conditions_text", [])
		if cond == "" and typeof(texts) == TYPE_ARRAY and not (texts as Array).is_empty():
			cond = str(texts[0])
	names.sort()
	# C1: a stage's own requirement (its profile's growth_requirement) says where and what in its track_text
	var req: Variant = TitanDuel.profile(stage).get("growth_requirement")
	if typeof(req) == TYPE_DICTIONARY and str((req as Dictionary).get("track_text", "")) != "":
		parts.append(str(req.track_text))
		return "; ".join(parts)
	if not names.is_empty():
		parts.append("grow at " + " or ".join(names))
	if cond != "":
		parts.append(cond.left(1).to_lower() + cond.substr(1).trim_suffix("."))
	return "; ".join(parts)


## The Attributes tab's lines (read-only: where to change them last).
static func attribute_lines(p: GiantPlayer) -> PackedStringArray:
	var out := PackedStringArray()
	if p == null or not is_instance_valid(p) or p.progression == null:
		out.append("No giant in play.")
		return out
	var attrs: Dictionary = p.progression.attributes()
	for key: String in Progression.ATTRIBUTE_KEYS:
		var info: Array = Progression.ATTRIBUTE_INFO.get(key, [key.capitalize(), ""])
		out.append("%s %d   %s" % [str(info[0]), int(attrs.get(key, 0)), str(info[1])])
	out.append("Unspent attribute points: %d" % int(p.progression.unspent_attribute_points))
	out.append(p.progression.ancestry_line())
	out.append(p.progression.talent_line())
	out.append("Change them at a shrine: its Attributes, Talents and Ancestry tabs.")
	return out


## {"weapon": [lines], "slots": [{"slot", "name", "item", "text", "hidden"}]}: the weapon in hand and its numbers, and
## the seven armour slots (B1: what each wears - its name with its tier, and its perk - or EMPTY_SLOT).
static func equipment_rows(p: GiantPlayer) -> Dictionary:
	var weapon := PackedStringArray()
	if p != null and is_instance_valid(p) and p.equipment != null:
		var id := str(p.equipment.weapon_id())
		var rec := GameData.get_record(id)
		weapon.append("%s%s" % [p.equipment.weapon_name(id), "  (too small for you now)" if p.equipment.is_too_small() else ""])
		weapon.append("Damage x%.2f    Length %.1f m (x%.1f at your size)    Fits up to stage %d" % [
			float(rec.get("damage_multiplier", 1.0)), float(rec.get("length_m", 0.0)), p.equipment.effective_weapon_scale(),
			int(rec.get("fit_max_stage", 6))])
		var light := GameData.get_action(str(p.controller.loadout.get("light", "")))
		var heavy := GameData.get_action(str(p.controller.loadout.get("heavy", "")))
		if light != null and heavy != null:
			weapon.append("Light: %s (power %d)    Heavy: %s (power %d)" % [light.display_name, int(light.power),
				heavy.display_name, int(heavy.power)])
		var perk: Variant = rec.get("perk", {})
		if typeof(perk) == TYPE_DICTIONARY and str(perk.get("text", "")) != "":
			weapon.append("Perk: " + str(perk.text))
	else:
		weapon.append("No weapon in hand.")
	var slots: Array = []
	var eq: Dictionary = GameSession.expansion.get("equipment", {})
	var held: Dictionary = eq.get("slots", {})
	for s: String in ExpansionState.ARMOUR_SLOTS:
		var item := str(held.get(s, ""))
		var text := EMPTY_SLOT
		if item != "" and not Armour.piece(item).is_empty():
			text = Armour.piece_name(item, Armour.tier_of(eq, item))
			var pk := Armour.perk(Armour.perk_of(eq, item))
			if not pk.is_empty():
				text += " (%s)" % str(pk.get("display_name", ""))
		slots.append({"slot": s, "name": str(SLOT_NAMES.get(s, s.capitalize())), "item": item, "text": text,
			"hidden": Armour.is_hidden(eq, s)})
	return {"weapon": weapon, "slots": slots}


## B1: the weapon in hand on one line (the Equipment tab): its name, damage, fit, heavy and perk.
static func weapon_summary(p: GiantPlayer) -> String:
	if p == null or not is_instance_valid(p) or p.equipment == null:
		return "No weapon in hand."
	var id := str(p.equipment.weapon_id())
	var rec := GameData.get_record(id)
	var parts := PackedStringArray()
	parts.append("%s%s" % [p.equipment.weapon_name(id), " (too small for you now)" if p.equipment.is_too_small() else ""])
	parts.append("damage x%.2f, fits up to stage %d" % [float(rec.get("damage_multiplier", 1.0)), int(rec.get("fit_max_stage", 6))])
	var heavy := GameData.get_action(str(p.controller.loadout.get("heavy", "")))
	if heavy != null:
		parts.append("heavy: %s" % heavy.display_name)
	var perk: Variant = rec.get("perk", {})
	if typeof(perk) == TYPE_DICTIONARY and str(perk.get("text", "")) != "":
		parts.append(str(perk.text))
	return " - ".join(parts)


## B1: the options of armour slot `slot`: [{"id", "label", "current"}] - each piece owned for it (its name with its
## tier; the one worn current) and, when it wears one, Take off ("-").
static func slot_options(slot: String) -> Array:
	var eq: Dictionary = GameSession.expansion.get("equipment", {})
	var worn := str((eq.get("slots", {}) as Dictionary).get(slot, ""))
	var out: Array = []
	for id: Variant in Armour.pieces_for_slot(slot):
		if Armour.owns(eq, str(id)):
			out.append({"id": str(id), "label": Armour.piece_name(str(id), Armour.tier_of(eq, str(id))),
				"current": str(id) == worn})
	if worn != "":
		out.append({"id": "-", "label": TAKE_OFF, "current": false})
	return out


## B1: what putting on `id` in `slot` (or "-": taking the slot's piece off; "": nothing) does to the giant's numbers:
## "Armour 16 -> 28 (blows 14% -> 22% lighter): better" ... the set bonuses it would make or break, and the piece's own
## words and perk.
static func compare_lines(p: GiantPlayer, slot: String, id: String) -> PackedStringArray:
	var out := PackedStringArray()
	var eq: Dictionary = (GameSession.expansion.get("equipment", {}) as Dictionary).duplicate(true)
	if eq.is_empty():
		eq = Armour.empty()
	var base: Dictionary = p.progression.base_passives() if p != null and is_instance_valid(p) and p.progression != null else {}
	var before := Armour.stats(eq, base)
	if id == "":
		out.append("Armour %d: blows %d%% lighter    Poise +%d" % [roundi(before.armour), roundi(before.less_pct),
			roundi(before.poise)])
		out.append("Stamina recovery x%.2f    Weight %s" % [before.stamina_regen, _num(before.weight)])
		return out
	var after_eq := eq.duplicate(true)
	if id == "-":
		Armour.unequip(after_eq, slot)
	else:
		Armour.equip(after_eq, id)
		var rec := Armour.piece(id)
		out.append("%s - %s, tier %d" % [str(rec.get("display_name", id)),
			str(Armour.set_record(str(rec.get("set", ""))).get("display_name", "")), maxi(1, Armour.tier_of(eq, id))])
		var pk := Armour.perk(Armour.perk_of(eq, id))
		if not pk.is_empty():
			out.append("Perk: %s - %s" % [str(pk.get("display_name", "")), str(pk.get("text", ""))])
	var after := Armour.stats(after_eq, base)
	var armour_line := "Armour %d -> %d (blows %d%% -> %d%% lighter)" % [roundi(before.armour), roundi(after.armour),
		roundi(before.less_pct), roundi(after.less_pct)]
	if roundi(before.armour) != roundi(after.armour):
		armour_line += ": better" if after.armour > before.armour else ": worse"
	out.append(armour_line)
	# the rest two to a line (each with its own better / worse)
	var more := PackedStringArray()
	for spec: Array in [["Poise", before.poise, after.poise, "+%d", true],
			["Weight", before.weight, after.weight, "%.1f", false],
			["Stamina recovery", before.stamina_regen, after.stamina_regen, "x%.2f", true],
			["Stamina costs", before.stamina_cost, after.stamina_cost, "x%.2f", false],
			["Movement", before.move, after.move, "x%.2f", true], ["Health", before.health, after.health, "+%d", true]]:
		if not is_equal_approx(float(spec[1]), float(spec[2])) or spec[0] == "Poise" or spec[0] == "Weight":
			more.append(_cmp(str(spec[0]), float(spec[1]), float(spec[2]), str(spec[3]), bool(spec[4])))
	for k in range(0, more.size(), 2):
		out.append("    ".join(more.slice(k, k + 2)))
	var types := {}
	for t: Variant in before.resist:
		types[t] = true
	for t: Variant in after.resist:
		types[t] = true
	for t: Variant in types:
		var b := float((before.resist as Dictionary).get(t, 0.0)) * 100.0
		var a := float((after.resist as Dictionary).get(t, 0.0)) * 100.0
		if roundi(a) != roundi(b):
			out.append(_cmp("%s resistance" % str(t).capitalize(), b, a, "%d%%", true))
	var was := {}
	for b: Dictionary in Armour.bonuses(eq):
		if bool(b.active):
			was[str(b.set) + str(b.pieces)] = true
	for b: Dictionary in Armour.bonuses(after_eq):
		var k := str(b.set) + str(b.pieces)
		if not bool(b.active):
			continue
		if not was.has(k):
			out.append("Completes %s (%d pieces): %s - better" % [str(b.name), int(b.pieces), str(b.text)])
		was.erase(k)
	for k: Variant in was:
		out.append("Breaks a set bonus - worse")
	return out


static func _cmp(label: String, a: float, b: float, fmt: String, higher_better: bool) -> String:
	var line := "%s %s -> %s" % [label, fmt % a, fmt % b]
	if is_equal_approx(a, b):
		return line
	return line + (": better" if (b > a) == higher_better else ": worse")


static func _num(v: float) -> String:
	return ("%d" % roundi(v)) if is_equal_approx(v, roundf(v)) else ("%.1f" % v)


## B1: the worn armour's set bonuses and totals ("(none)" lines when nothing is worn).
static func worn_lines(p: GiantPlayer) -> PackedStringArray:
	var out := PackedStringArray()
	var eq: Dictionary = GameSession.expansion.get("equipment", {})
	if Armour.worn(eq).is_empty():
		out.append("(No armour worn: a forge makes it from iron, wolf hide and the titans' stone.)")
		return out
	var next_shown := {}
	var next := PackedStringArray()
	for b: Dictionary in Armour.bonuses(eq):
		if not bool(b.active):
			if next_shown.has(str(b.set)):
				continue
			next_shown[str(b.set)] = true
			next.append("%s, %d pieces (%d worn) - %s" % [str(b.set_name), int(b.pieces), int(b.worn), str(b.name)])
		else:
			out.append("%s, %d pieces - %s: %s" % [str(b.set_name), int(b.pieces), str(b.name), str(b.text)])
	if not next.is_empty():
		out.append("Not yet: " + "; ".join(next))
	var base: Dictionary = p.progression.base_passives() if p != null and is_instance_valid(p) and p.progression != null else {}
	var st := Armour.stats(eq, base)
	out.append("In all: armour %d (blows %d%% lighter), poise +%d, stamina recovery x%.2f, weight %s" % [
		roundi(st.armour), roundi(st.less_pct), roundi(st.poise), st.stamina_regen, _num(st.weight)])
	return out


## B1: puts on armour piece `id` in `slot` ("-": takes the slot's piece off) for the giant `p`, when it is out of
## combat: {"ok", "message"}. Events.armour_changed; the giant's passives and look follow (Armour.refresh_player).
static func apply_option(p: GiantPlayer, slot: String, id: String) -> Dictionary:
	var blocked := Armour.change_blocked()
	if blocked != "":
		return {"ok": false, "message": blocked}
	var eq := _equipment()
	if id == "-":
		var old := str(eq.slots.get(slot, ""))
		if not Armour.unequip(eq, slot):
			return {"ok": false, "message": "Nothing to take off."}
		Armour.refresh_player(p)
		Events.armour_changed.emit(Sim.tick, "unequipped", old)
		return {"ok": true, "message": "Taken off: %s." % Armour.display_name(old)}
	if not Armour.equip(eq, id):
		return {"ok": false, "message": "You do not have it."}
	Armour.refresh_player(p)
	Events.armour_changed.emit(Sim.tick, "equipped", id)
	return {"ok": true, "message": "Put on: %s." % Armour.display_name(id)}


## The Titans tab: one row a roster titan, in the story's order - {"id", "known", "state", "text"}. Stoneback (the
## act's titan the hamlet warns of) always by name with his state; a titan with no record yet (the later ones)
## "???" (known false): nothing of it named.
static func titan_rows(state: Dictionary) -> Array:
	var out: Array = []
	var titans: Dictionary = state.get("titans", {})
	for t: Dictionary in ExpansionState.roster():
		var id := str(t.get("id", ""))
		var rec: Dictionary = titans.get(id, ExpansionState.titan_defaults())
		var playable := str(t.get("enemy", "")) != ""
		var st := str(rec.get("state", ExpansionState.STATE_UNSEEN))
		if not playable and st == ExpansionState.STATE_UNSEEN:
			out.append({"id": id, "known": false, "state": st, "text": "???"})
			continue
		var name := str(t.get("display_name", id))
		var epithet := str(t.get("epithet", ""))
		var text := "%s%s  -  %s" % [name, ", " + epithet if epithet != "" else "", str(STATE_TEXT.get(st, st))]
		if st == ExpansionState.STATE_UNSEEN and str(t.get("where", "")) != "":
			text += "; said to hold %s" % str(t.where)
		var plates := int(rec.get("plates_broken_best", 0))
		if plates > 0:
			text += "    Most plates broken in a fight: %d" % plates
		if st == ExpansionState.STATE_SLAIN:
			text += "    Kills: %d" % maxi(1, int(rec.get("kills", 1)))
			var drops := PackedStringArray()
			for d: Variant in rec.get("drops", []):
				if typeof(d) == TYPE_DICTIONARY:
					drops.append("%s x%d" % [str(GameData.get_record(str(d.item)).get("display_name", d.item)), int(d.count)])
			if not drops.is_empty():
				text += "    Dropped: " + ", ".join(drops)
		out.append({"id": id, "known": true, "state": st, "text": text})
	return out


## An item's description as the player reads it: the record's first sentence, without its package tag ("A2: ").
static func material_text(rec: Dictionary) -> String:
	var d := str(rec.get("description", ""))
	var colon := d.find(": ")
	if colon >= 0 and colon <= 4:
		d = d.substr(colon + 2)
	d = d.get_slice(". ", 0).trim_suffix(".")
	return d.left(1).to_upper() + d.substr(1) + "." if d != "" else ""


## B4: the titans' materials in the roster's order - each signature titan's loot table (its guaranteed drops) and his
## plates' own loot, the materials only (category "material", or worked by a recipe) and only those no other loot table
## gives (an iron ingot or wood scrap is anyone's).
static func titan_materials() -> PackedStringArray:
	var own_tables := {}
	for t: Dictionary in ExpansionState.roster():
		own_tables[str(t.get("loot_table", ""))] = true
	var common := {}
	for rec: Dictionary in GameData.records_of_type("loot_table"):
		if own_tables.has(str(rec.get("id", ""))):
			continue
		for list: String in ["guaranteed", "entries"]:
			for e: Variant in rec.get(list, []):
				if typeof(e) == TYPE_DICTIONARY:
					common[str(e.get("item", ""))] = true
	var worked := {}   # (an item a recipe works counts as a material whatever its category: his heart-stone)
	for rec: Dictionary in GameData.records_of_type("recipe"):
		for c: Variant in rec.get("cost", []):
			if typeof(c) == TYPE_DICTIONARY:
				worked[str(c.get("item", ""))] = true
	var out := PackedStringArray()
	for t: Dictionary in ExpansionState.roster():
		var ids: Array = []
		for g: Variant in GameData.get_record(str(t.get("loot_table", ""))).get("guaranteed", []):
			if typeof(g) == TYPE_DICTIONARY:
				ids.append(str(g.get("item", "")))
		for pl: Variant in GameData.get_record(str(t.get("enemy", ""))).get("plates", []):
			if typeof(pl) == TYPE_DICTIONARY:
				for l: Variant in pl.get("loot", []):
					if typeof(l) == TYPE_DICTIONARY:
						ids.append(str(l.get("item", "")))
		for id: String in ids:
			var rec := GameData.get_record(id)
			if id == "" or out.has(id) or common.has(id) or (str(rec.get("category", "")) != "material"
					and not worked.has(id)):
				continue
			out.append(id)
	return out


## The Materials tab: {"titan": [{"id", "name", "count", "text"}], "other": [...]} from the inventory (WorldState),
## the titans' materials first (titan_materials' order), then every other item of category material by name.
static func material_rows() -> Dictionary:
	var titan: Array = []
	var other: Array = []
	var titan_ids := titan_materials()
	for id: String in titan_ids:
		var n := WorldState.count_of(id)
		if n > 0:
			var rec := GameData.get_record(id)
			titan.append({"id": id, "name": str(rec.get("display_name", id)), "count": n,
				"text": material_text(rec)})
	var names: Array = []
	for id: Variant in WorldState.inventory:
		var sid := str(id)
		var rec := GameData.get_record(sid)
		if titan_ids.has(sid) or str(rec.get("category", "material")) != "material" or WorldState.count_of(sid) <= 0:
			continue
		names.append([str(rec.get("display_name", sid)), sid])
	names.sort()
	for pair: Array in names:
		other.append({"id": str(pair[1]), "name": str(pair[0]), "count": WorldState.count_of(str(pair[1])), "text": ""})
	return {"titan": titan, "other": other}
