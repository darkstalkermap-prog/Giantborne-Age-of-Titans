class_name CharacterScreen
extends UiScreen
## The Character menu (A4): ScreenStack SCREENS["character"], opened at any time in play with the `character`
## action (C / pad Y by default; remappable as every binding: InputBindings) or from the pause menu's Character
## entry; it pauses the game like every screen. Read-only: what the giant is, where it can grow, what it carries.
## Five tabs (TABS), switched by their buttons, Enter on a focused one, the mouse, or pad LB / RB:
##   * Giant: the level, the XP to the next, the growth stage and the height in feet and metres, and the growth
##     track of stages 1-10 (heights 12-140 ft at levels 1-20): reached, next (what it needs: the level, and where
##     the world's shrines grow it with their conditions where the data says so) and to come; stages 7-10 as
##     locked "beyond the rim" with their heights only. Beside it the giant itself (the creator's GiantPreview,
##     where a display draws it).
##   * Attributes: the attributes, the unspent points, the ancestry and the talents (read-only: the shrine's
##     Attributes, Talents and Ancestry tabs change them, and the tab says so).
##   * Equipment: the weapon in hand and its numbers; the armour slots milestone B adds (head, shoulders, chest,
##     arms, waist, legs, trinket) as empty "not yet available" rows (save schema 3 keeps them, ExpansionState).
##   * Titans: the ten signature titans (the roster, data/titans/titan_roster.json) as a trophy list - Stoneback
##     with his state (unseen, sighted, slain), the most plates broken in a fight, his kills and what he dropped;
##     every other titan "???" beside a dark silhouette until met (nothing of it named).
##   * Materials: the titans' materials held (his heart-stone, slabs and quarry iron) and the other crafting items.
## Pad and keyboard (P16): the tab row, then Close; every direction wraps. The content fits 1280 x 720 at any level
## (test_character_screen). Read API for tests: tab_names(), show_tab(i), lines() (the shown tab as text) and the
## static content builders (giant_info, growth_track, attribute_lines, equipment_rows, titan_rows, material_rows).

const TABS := ["Giant", "Attributes", "Equipment", "Titans", "Materials"]
const PANEL_SIZE := Vector2(940, 600)
const LIFT_PX := 16.0
const GOLD := Color(1.0, 0.86, 0.45)
const FT_PER_M := 3.28084
## The approved story's stages beyond the six built (docs/DECISIONS.md section 2.7): [stage, height ft, level].
const BEYOND := [[7, 78, 13], [8, 96, 15], [9, 116, 17], [10, 140, 20]]
const BEYOND_TEXT := "Beyond the rim"
## The materials the titans leave, shown first in the Materials tab.
const TITAN_MATERIALS := ["item.stoneback_heart_stone", "item.stoneback_slab", "item.quarry_iron"]
const SLOT_NAMES := {"head": "Head", "shoulders": "Shoulders", "chest": "Chest", "arms": "Arms", "waist": "Waist",
	"legs": "Legs", "trinket": "Trinket"}
const NOT_YET := "not yet available"
const STATE_TEXT := {"unseen": "Not yet seen", "sighted": "Sighted", "slain": "Slain"}

var player: GiantPlayer
var close_button: Button
var preview: GiantPreview = null
var _tab_buttons: Array[Button] = []
var _current := 0
var _body: VBoxContainer
var _side: Control
var _lines: PackedStringArray = []


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
	close_button = UiKit.button("Close", 18)
	close_button.pressed.connect(cancel)
	v.add_child(close_button)
	show_tab(0)


## The live giant beside the Giant tab only where a display draws it (headless runs and tests have none: the
## preview's model would load for nothing).
static func wants_preview() -> bool:
	return DisplayServer.get_name() != "headless"


func on_open() -> void:
	show_tab(_current)
	if preview != null and player != null and is_instance_valid(player):
		var look: Variant = GameSession.character.get("appearance", {})
		preview.set_game_profile(player.profile)
		preview.apply_look(look if typeof(look) == TYPE_DICTIONARY else {})


func first_focus() -> Control:
	return _tab_buttons[_current] if _current < _tab_buttons.size() else close_button


## The tab row, then Close (P16 rows, wrapping).
func focus_rows() -> Array:
	return [_tab_buttons.duplicate(), [close_button]]


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


## Shows tab `i` (TABS order) and rebuilds its content.
func show_tab(i: int) -> void:
	if i < 0 or i >= TABS.size():
		return
	_current = i
	for k in _tab_buttons.size():
		UiKit.set_tab_open(_tab_buttons[k], k == i)
	_rebuild()
	if _side != null:
		_side.visible = TABS[i] == "Giant" and preview != null
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


func _build_attributes() -> void:
	_heading("Attributes")
	for l: String in attribute_lines(player):
		_line(l, UiKit.MUTED if l.begins_with("Change") else UiKit.TEXT)


func _build_equipment() -> void:
	var e := equipment_rows(player)
	_heading("Weapon")
	for l: String in e.weapon:
		_line(l)
	_heading("Armour")
	for r: Dictionary in e.slots:
		_line("%s:  %s" % [str(r.name), str(r.text)], UiKit.MUTED)
	_line("Armour and its slots come with the titans' forges (a later update).", UiKit.MUTED, 12)


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
	for r: Dictionary in m.other:
		_line("%s  x%d" % [str(r.name), int(r.count)])


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
	for s in range(1, 7):
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
		out.append(row)
	for b: Array in BEYOND:
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


## {"weapon": [lines], "slots": [{"slot", "name", "item", "text"}]}: the weapon in hand and its numbers, and the
## armour slots (all empty until milestone B: "not yet available").
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
	var held: Dictionary = (GameSession.expansion.get("equipment", {}) as Dictionary).get("slots", {})
	for s: String in ExpansionState.ARMOUR_SLOTS:
		var item := str(held.get(s, ""))
		slots.append({"slot": s, "name": str(SLOT_NAMES.get(s, s.capitalize())), "item": item,
			"text": NOT_YET if item == "" else str(GameData.get_record(item).get("display_name", item))})
	return {"weapon": weapon, "slots": slots}


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


## The Materials tab: {"titan": [{"id", "name", "count", "text"}], "other": [...]} from the inventory (WorldState),
## the titans' materials first (TITAN_MATERIALS order), then every other item of category material by name.
static func material_rows() -> Dictionary:
	var titan: Array = []
	var other: Array = []
	for id: String in TITAN_MATERIALS:
		var n := WorldState.count_of(id)
		if n > 0:
			var rec := GameData.get_record(id)
			titan.append({"id": id, "name": str(rec.get("display_name", id)), "count": n,
				"text": material_text(rec)})
	var names: Array = []
	for id: Variant in WorldState.inventory:
		var sid := str(id)
		var rec := GameData.get_record(sid)
		if TITAN_MATERIALS.has(sid) or str(rec.get("category", "material")) != "material" or WorldState.count_of(sid) <= 0:
			continue
		names.append([str(rec.get("display_name", sid)), sid])
	names.sort()
	for pair: Array in names:
		other.append({"id": str(pair[1]), "name": str(pair[0]), "count": WorldState.count_of(str(pair[1])), "text": ""})
	return {"titan": titan, "other": other}
