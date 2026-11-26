extends IntegrationSuite
## A4: the Character menu (CharacterScreen, ScreenStack SCREENS["character"]): opened at any time in play with its
## own binding (C / pad Y: HOTKEYS) or the pause menu's Character entry, pausing the game; six tabs (Giant,
## Attributes, Equipment, Titans, Materials, C4's Settlements) by click, focus, LB / RB (wrapping); the tab row and Close wrap; the
## binding or Esc / B closes it; the footer names the binding by the device in use. Its content: the level, XP and
## height in feet and metres, the growth track of ten stages (7-10 locked beyond the rim, heights only), the
## read-only attributes with where to change them, the weapon's numbers and seven armour slots (B1: empty here; the
## Equipment tab's own suite is test_equipment_tab), the ten
## titans (Stoneback by name and state, the others "???"), the titans' materials. Every tab fits 1280 x 720 above
## the footer at level 20.

const VIEW := Vector2(1280, 720)

var stack: ScreenStack
var frame: Control


func before_each() -> void:
	await super()
	InputBindings.reset_device()
	var layer := CanvasLayer.new()
	layer.layer = 10
	world.add_child(layer)
	frame = Control.new()
	frame.size = VIEW
	layer.add_child(frame)
	stack = ScreenStack.new()
	frame.add_child(stack)
	GameSession.expansion = ExpansionState.defaults()
	await get_tree().process_frame


func after_each() -> void:
	if is_instance_valid(stack):
		stack.close_all()
	get_tree().paused = false
	InputRouter.set_context(InputRouter.Context.GAMEPLAY)
	InputBindings.reset_device()
	GameSession.expansion = ExpansionState.defaults()
	await super()


func _player(level := 9) -> GiantPlayer:
	var p := spawn_player(Vector3(0, 0.05, 0))
	await step_ticks(1)
	var st := CharacterState.world_start(Progression.record(), GameData.get_record("player.giant"))
	st["level"] = level
	st["xp"] = Progression.xp_for_level(level) + 40
	st["talent_points"] = Talents.points_at_level(level)
	p.apply_character_state(CharacterState.normalize(st))
	await step_ticks(1)
	return p


func _open(p: GiantPlayer) -> CharacterScreen:
	var screen := stack.open("character", {"player": p}) as CharacterScreen
	await get_tree().process_frame
	await get_tree().process_frame
	return screen


func _rect(c: Control) -> Rect2:
	return Rect2(c.get_global_rect().position - frame.get_global_rect().position, c.size)


func _key(code: Key) -> void:
	var e := InputEventKey.new()
	e.keycode = code
	e.physical_keycode = code
	e.pressed = true
	Input.parse_input_event(e)
	await get_tree().process_frame
	var r := InputEventKey.new()
	r.keycode = code
	r.physical_keycode = code
	r.pressed = false
	Input.parse_input_event(r)
	await get_tree().process_frame


func _pad(button: JoyButton) -> void:
	var e := InputEventJoypadButton.new()
	e.button_index = button
	e.pressed = true
	Input.parse_input_event(e)
	await get_tree().process_frame
	var r := InputEventJoypadButton.new()
	r.button_index = button
	r.pressed = false
	Input.parse_input_event(r)
	await get_tree().process_frame


func test_the_binding_opens_it_pausing_the_game_and_closes_it() -> void:
	await _player()
	assert_true(InputMap.has_action("character"), "the action exists (remappable: InputBindings.ACTIONS)")
	assert_true(InputBindings.ACTIONS.has("character"), "among the remappable actions")
	assert_eq(InputBindings.describe_action("character", false), "C", "C on the keyboard")
	assert_eq(InputBindings.short_pad_label("character"), "Y", "Y on a pad")
	await _key(KEY_C)
	await get_tree().process_frame
	var screen := stack.top() as CharacterScreen
	assert_true(screen != null, "C opens the Character menu")
	assert_true(get_tree().paused, "it pauses the game")
	assert_eq(screen.current_tab(), "Giant", "on the Giant tab")
	await _key(KEY_C)
	await get_tree().process_frame
	assert_false(stack.any_open(), "C closes it again")
	assert_false(get_tree().paused, "and the game runs")
	await _pad(JOY_BUTTON_Y)
	await get_tree().process_frame
	assert_true(stack.top() is CharacterScreen, "pad Y opens it")
	await _pad(JOY_BUTTON_B)
	await get_tree().process_frame
	assert_false(stack.any_open(), "B closes it")
	# A5: with LT held, Y is ability 4 (a combo the input router takes) and opens no menu
	var lt := InputEventJoypadMotion.new()
	lt.axis = JOY_AXIS_TRIGGER_LEFT
	lt.axis_value = 1.0
	Input.parse_input_event(lt)
	await get_tree().process_frame
	await _pad(JOY_BUTTON_Y)
	await get_tree().process_frame
	var opened := stack.any_open()
	var lt_off := InputEventJoypadMotion.new()
	lt_off.axis = JOY_AXIS_TRIGGER_LEFT
	lt_off.axis_value = 0.0
	Input.parse_input_event(lt_off)
	await get_tree().process_frame
	assert_false(opened, "LT + Y casts ability 4 and opens no Character menu")


func test_the_pause_menu_opens_it_above_itself() -> void:
	await _player()
	var menu := stack.open("pause") as PauseMenu
	await get_tree().process_frame
	assert_true(menu.item("Character") != null, "the pause menu has a Character entry")
	menu.item("Character").pressed.emit()
	await get_tree().process_frame
	assert_true(stack.top() is CharacterScreen, "it opens the Character menu on top")
	(stack.top() as CharacterScreen).cancel()
	await get_tree().process_frame
	assert_eq(stack.top(), menu, "closing it comes back to the pause menu")


func test_tabs_by_pad_and_the_focus_wraps() -> void:
	var p := await _player()
	var screen := await _open(p)
	assert_eq(Array(screen.tab_names()), ["Giant", "Attributes", "Equipment", "Titans", "Materials", "Settlements"],
		"six tabs (C4: Settlements)")
	for want: String in ["Attributes", "Equipment", "Titans", "Materials", "Settlements", "Giant"]:
		await _pad(JOY_BUTTON_RIGHT_SHOULDER)
		assert_eq(screen.current_tab(), want, "RB: %s" % want)
	await _pad(JOY_BUTTON_LEFT_SHOULDER)
	assert_eq(screen.current_tab(), "Settlements", "LB wraps back")
	var rows := screen.focus_rows()
	assert_eq(rows.size(), 2, "the tab row, then Close")
	var tabs := screen.tab_buttons()
	assert_eq(tabs[0].focus_neighbor_left, tabs[0].get_path_to(tabs[tabs.size() - 1]), "left of the first tab wraps")
	assert_true(tabs.any(func(b: Button) -> bool: return screen.close_button.focus_neighbor_bottom == screen.close_button.get_path_to(b)),
		"below Close the focus wraps to the tab row")
	assert_true(UiNav.focusable(screen.first_focus()), "a focus to start from")
	tabs[2].pressed.emit()
	assert_eq(screen.current_tab(), "Equipment", "a click or Enter on a tab opens it")
	assert_true(UiKit.is_tab_open(tabs[2]) and not UiKit.is_tab_open(tabs[0]), "the open tab is marked")
	assert_true(screen.nav_hint(true).contains("LB / RB") and screen.nav_hint(true).contains("Y"), "the pad's footer: %s" % screen.nav_hint(true))
	assert_true(screen.nav_hint(false).contains("Esc or C"), "the keyboard's: %s" % screen.nav_hint(false))


func test_the_giant_tab_shows_the_level_the_height_and_the_growth_track() -> void:
	var p := await _player(9)
	TitanDuel.prepare(p, 5)
	await step_ticks(1)
	var g := CharacterScreen.giant_info(p)
	assert_eq(int(g.stage), 5, "stage 5")
	assert_eq(int(g.height_ft), 48, "48 ft")
	assert_near(float(g.height_m), 14.63, 0.01, "14.6 m")
	assert_true(str(g.xp_text).contains("to level"), "the XP to the next level: %s" % g.xp_text)
	var track := CharacterScreen.growth_track(p)
	assert_eq(track.size(), 10, "ten stages")
	var ft: Array = track.map(func(r: Dictionary) -> int: return int(r.height_ft))
	assert_eq(ft, [12, 18, 26, 36, 48, 62, 78, 96, 116, 140], "the heights in feet")
	var lv: Array = track.map(func(r: Dictionary) -> int: return int(r.level))
	assert_eq(lv, [1, 3, 5, 7, 9, 11, 13, 15, 17, 20], "at levels 1-20")
	var states: Array = track.map(func(r: Dictionary) -> String: return str(r.state))
	# C1: stages 7 and 8 have profiles: "later" with what they ask, told plainly; 9 and 10 beyond the rim
	assert_eq(states, ["reached", "reached", "reached", "reached", "reached", "next", "later", "later", "beyond",
		"beyond"], "reached, next, later (the colossi), beyond the rim")
	var nxt: Dictionary = track[5]
	assert_true(str(nxt.text).contains("level 11"), "the next stage's level: %s" % nxt.text)
	assert_true(str(nxt.text).contains("Shrine of the Standing Stones"), "where it grows: %s" % nxt.text)
	assert_true(str(nxt.text).contains("oaths"), "and what the shrine waits for: %s" % nxt.text)
	assert_true(str((track[6] as Dictionary).text).contains("standing stone beyond the rim"), "stage 7 says where: %s" % track[6].text)
	assert_true(str((track[7] as Dictionary).text).contains("Last Hearth"), "stage 8 says what it asks: %s" % track[7].text)
	for r: Dictionary in track.slice(8):
		assert_eq(str(r.text), "Beyond the rim (locked)", "stage %d: locked, nothing more" % int(r.stage))
	var screen := await _open(p)
	var text := "\n".join(screen.lines())
	assert_true(text.contains("48 ft (14.6 m)"), "the height in feet and metres on the tab")
	assert_false(text.contains("Frostbound") or text.contains("Worldbreaker"), "no titan of the later acts named")


func test_the_other_tabs() -> void:
	var p := await _player(9)
	var screen := await _open(p)
	screen.show_tab(1)
	var attrs := "\n".join(screen.lines())
	assert_true(attrs.contains("Strength") and attrs.contains("Constitution"), "the attributes")
	assert_true(attrs.contains("Change them at a shrine"), "and where to change them")
	screen.show_tab(2)
	var e := CharacterScreen.equipment_rows(p)
	assert_true((e.weapon as PackedStringArray).size() >= 2, "the weapon and its numbers: %s" % e.weapon)
	assert_true(str(e.weapon[1]).contains("Damage x"), "its damage")
	var slots: Array = (e.slots as Array).map(func(r: Dictionary) -> String: return str(r.slot))
	assert_eq(slots, ["head", "shoulders", "chest", "arms", "waist", "legs", "trinket"], "the seven armour slots")
	for r: Dictionary in e.slots:
		assert_eq(str(r.text), CharacterScreen.EMPTY_SLOT, "%s: empty (B1: nothing worn yet)" % r.slot)
	# the titans
	screen.show_tab(3)
	var rows := CharacterScreen.titan_rows(GameSession.expansion)
	assert_eq(rows.size(), 10, "the ten signature titans")
	assert_true(str(rows[0].text).begins_with("Stoneback"), "Stoneback first, by name: %s" % rows[0].text)
	assert_true(str(rows[0].text).contains("Not yet seen"), "unseen")
	assert_true(str(rows[1].text).begins_with("The Ogre King") and str(rows[1].text).contains("Not yet seen"),
		"B2: the Ogre King second, by name (in the game now): %s" % rows[1].text)
	assert_true(str(rows[2].text).begins_with("The Rootwarden") and str(rows[2].text).contains("Not yet seen"),
		"B3: the Rootwarden third, by name (in the game now): %s" % rows[2].text)
	assert_true(str(rows[3].text).begins_with("The Bastion Titan") and str(rows[3].text).contains("Not yet seen"),
		"C2: the Bastion Titan fourth, by name (in the game now): %s" % rows[3].text)
	for r: Dictionary in rows.slice(4):
		assert_eq(str(r.text), "???", "an unmet titan is unknown")
		assert_false(bool(r.known), "and not named")
	ExpansionState.note_sighted(GameSession.expansion, "titan.stoneback", 100.0, 1)
	ExpansionState.note_plates(GameSession.expansion, "titan.stoneback", 3)
	assert_true(str(CharacterScreen.titan_rows(GameSession.expansion)[0].text).contains("Sighted"), "sighted")
	ExpansionState.note_slain(GameSession.expansion, "titan.stoneback")
	var slain := str(CharacterScreen.titan_rows(GameSession.expansion)[0].text)
	assert_true(slain.contains("Slain") and slain.contains("Kills: 1") and slain.contains("plates broken in a fight: 3"),
		"slain: %s" % slain)
	assert_true(slain.contains("Stoneback's Slab x4"), "and what he dropped: %s" % slain)
	# the materials
	WorldState.add_item("item.stoneback_slab", 4, "test")
	WorldState.add_item("item.iron_ingot", 2, "test")
	var m := CharacterScreen.material_rows()
	assert_eq((m.titan as Array).map(func(r: Dictionary) -> String: return str(r.id)), ["item.stoneback_slab"],
		"the titan's material held")
	assert_false(str(m.titan[0].text).begins_with("A2"), "in the player's words: %s" % m.titan[0].text)
	assert_true((m.other as Array).any(func(r: Dictionary) -> bool: return str(r.id) == "item.iron_ingot"),
		"and the other crafting items")
	# B4: every signature titan's materials among the titans' (B2's and B3's were "other", without their words)
	var all := CharacterScreen.titan_materials()
	for id: String in ["item.stoneback_heart_stone", "item.stoneback_slab", "item.quarry_iron", "item.ogre_hide",
			"item.ogre_crown_iron", "item.kings_bell_bronze", "item.warden_heartwood", "item.warden_bark", "item.amber_sap"]:
		assert_true(all.has(id), "%s is a titan's material" % id)
	for id: String in ["item.iron_ingot", "item.wood_scrap", "item.ogre_tusk", "item.hide"]:
		assert_false(all.has(id), "%s is not" % id)
	assert_true(all.find("item.stoneback_slab") < all.find("item.ogre_hide") and all.find("item.ogre_hide")
		< all.find("item.warden_bark"), "in the roster's order")
	WorldState.add_item("item.ogre_hide", 4, "test")
	var m2 := CharacterScreen.material_rows()
	var hide: Array = (m2.titan as Array).filter(func(r: Dictionary) -> bool: return str(r.id) == "item.ogre_hide")
	assert_eq(hide.size(), 1, "the King's hide among the titans' materials")
	assert_true(not hide.is_empty() and str(hide[0].text).contains("Ogre King"), "with its words")


func test_every_tab_fits_1280_by_720_at_level_20() -> void:
	var p := await _player(20)
	TitanDuel.prepare(p, 6)
	await step_ticks(1)
	ExpansionState.note_slain(GameSession.expansion, "titan.stoneback")
	ExpansionState.note_plates(GameSession.expansion, "titan.stoneback", 8)
	for id: String in CharacterScreen.titan_materials():   # (B4: every titan's, the longest list)
		WorldState.add_item(id, 9, "test")
	for id: String in ["item.iron_ingot", "item.titan_iron", "item.wood_scrap"]:
		WorldState.add_item(id, 12, "test")
	var screen := await _open(p)
	var room := Rect2(Vector2.ZERO, Vector2(VIEW.x, _rect(stack.get_node("NavHint") as Control).position.y))
	var bad := PackedStringArray()
	var panel := screen.get_node("Frame") as Control
	for i in CharacterScreen.TABS.size():
		screen.show_tab(i)
		await get_tree().process_frame
		await get_tree().process_frame
		for c: Control in [panel, screen.close_button]:
			if not room.grow(0.5).encloses(_rect(c)):
				bad.append("%s on %s: %s" % [c.name, CharacterScreen.TABS[i], _rect(c)])
	assert_eq(bad, PackedStringArray(), "every tab fits the window above the footer hint")
