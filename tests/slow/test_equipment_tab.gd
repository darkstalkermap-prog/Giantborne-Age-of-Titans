extends IntegrationSuite
## B1: the Character menu's Equipment tab and the forge's three tabs, as a player meets them: the seven slots with what
## each wears and its Shown / Hidden toggle; choosing a slot lists the pieces owned for it with their numbers before
## -> after; putting one on and taking it off; the set bonuses and the totals; the pad's way through it (the tab row,
## each slot's row, the slot's options, Close); the forge's Weapons, Armour and Reforge tabs (LB / RB) with their rows,
## details and actions. Every tab of both fits 1280 x 720 above the footer.

const VIEW := Vector2(1280, 720)
const FORGE := "res://scenes/world/forge.tscn"

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
	WorldState.clear()
	await get_tree().process_frame


func after_each() -> void:
	if is_instance_valid(stack):
		stack.close_all()
	get_tree().paused = false
	InputRouter.set_context(InputRouter.Context.GAMEPLAY)
	InputBindings.reset_device()
	GameSession.expansion = ExpansionState.defaults()
	WorldState.clear()
	await super()


func _player() -> GiantPlayer:
	var p := spawn_player(Vector3(0, 0.05, 0))
	await step_ticks(1)
	return p


func _pad(button: JoyButton) -> void:
	for pressed in [true, false]:
		var e := InputEventJoypadButton.new()
		e.button_index = button
		e.pressed = pressed
		e.device = 0
		Input.parse_input_event(e)
		await get_tree().process_frame
	await get_tree().process_frame


func _focus() -> Control:
	return get_viewport().gui_get_focus_owner()


func _rect(c: Control) -> Rect2:
	return Rect2(c.get_global_rect().position - frame.get_global_rect().position, c.size)


func _owns(ids: Array) -> void:
	for id: Variant in ids:
		Armour.grant(GameSession.expansion.equipment, str(id))


func test_the_equipment_tab_puts_armour_on_and_off() -> void:
	var p := await _player()
	_owns(["armour.iron_hauberk", "armour.iron_greaves", "armour.quarry_greaves", "armour.quarry_pauldrons"])
	var screen := stack.open("character", {"player": p}) as CharacterScreen
	await get_tree().process_frame
	screen.show_tab(CharacterScreen.TABS.find("Equipment"))
	await get_tree().process_frame
	assert_eq(screen.slot_buttons.size(), 7, "a row a slot")
	assert_true(screen.lines().has("Head: empty"), "the head empty: %s" % [screen.lines()])
	screen._choose_slot("legs")
	await get_tree().process_frame
	var labels := screen.option_buttons.map(func(b: Button) -> String: return b.text)
	assert_eq(labels, ["Iron Greaves", "Quarry Greaves"], "the legs' pieces owned, the sets in order")
	var cmp := CharacterScreen.compare_lines(p, "legs", "armour.quarry_greaves")
	assert_true(Array(cmp).any(func(l: String) -> bool: return l.begins_with("Armour 0 -> 8") and l.ends_with("better")),
		"before -> after: %s" % [cmp])
	assert_true(Array(cmp).any(func(l: String) -> bool: return l.contains("Weight 0.0 -> 3.0: worse")), "its weight")
	screen._choose_option("armour.quarry_greaves")
	await get_tree().process_frame
	assert_eq(str(GameSession.expansion.equipment.slots.legs), "armour.quarry_greaves", "put on")
	assert_true(screen.lines().has("Legs: Quarry Greaves"), "the row says so")
	assert_true(screen.lines().has("- Take off"), "and offers Take off")
	screen._choose_slot("shoulders")
	screen._choose_option("armour.quarry_pauldrons")
	await get_tree().process_frame
	var worn := "\n".join(screen.lines())
	assert_true(worn.contains("Quarry set, 2 pieces - Quarried: Poise +10"), "the 2-piece bonus earned: %s" % worn)
	assert_true(worn.contains("Not yet: Quarry set, 4 pieces (2 worn) - Stonebound"), "the 4-piece not yet")
	assert_true(worn.contains("In all: armour 17"), "the totals")
	# the toggle: hidden still counts
	var i := Armour.SLOTS.find("shoulders")
	screen.show_buttons[i].pressed.emit()
	await get_tree().process_frame
	assert_true(Armour.is_hidden(GameSession.expansion.equipment, "shoulders"), "hidden")
	assert_eq(screen.show_buttons[i].text, CharacterScreen.HIDDEN, "the toggle says so")
	assert_true("\n".join(screen.lines()).contains("In all: armour 17"), "and it still counts")
	assert_false((p.appearance.look().accessories as Array).has("Armour_quarry_pauldrons"), "not drawn")
	# take it off
	screen._choose_slot("legs")
	screen._choose_option("-")
	assert_eq(str(GameSession.expansion.equipment.slots.legs), "", "taken off")
	assert_true(Armour.owns(GameSession.expansion.equipment, "armour.quarry_greaves"), "and still owned")


func test_a_pad_goes_through_the_equipment_tab() -> void:
	var p := await _player()
	_owns(["armour.hide_hooded_mantle"])
	var screen := stack.open("character", {"player": p}) as CharacterScreen
	await get_tree().process_frame
	await get_tree().process_frame
	screen.show_tab(CharacterScreen.TABS.find("Equipment"))
	await get_tree().process_frame
	assert_true(screen.tab_buttons().has(_focus()), "the tab row has the focus")
	await _pad(JOY_BUTTON_DPAD_DOWN)
	assert_eq(_focus(), screen.slot_buttons[0], "down: the head's row")
	await _pad(JOY_BUTTON_DPAD_RIGHT)
	assert_eq(_focus(), screen.slot_buttons[0], "right: an empty slot's toggle (disabled) is skipped")
	await _pad(JOY_BUTTON_DPAD_DOWN)
	assert_eq(_focus(), screen.slot_buttons[1], "down: the shoulders' row")
	await _pad(JOY_BUTTON_A)
	assert_eq(screen.eq_slot, "shoulders", "A chooses it")
	assert_true(screen.option_buttons.has(_focus()), "and the focus goes to its options")
	await _pad(JOY_BUTTON_A)
	assert_eq(str(GameSession.expansion.equipment.slots.shoulders), "armour.hide_hooded_mantle", "A puts it on")
	assert_eq(_focus(), screen.slot_buttons[1], "and the focus is back on the slot")
	await _pad(JOY_BUTTON_RIGHT_SHOULDER)
	assert_eq(screen.current_tab(), "Titans", "RB: the next tab")


func test_the_forge_tabs() -> void:
	var p := await _player()
	var f := (load(FORGE) as PackedScene).instantiate() as Forge
	f.world_id = "test.b1_forge_tabs"
	f.position = Vector3(10, 0, 0)
	world.add_child(f)
	await step_ticks(1)
	WorldState.add_item("item.hide", 9, "test")
	var screen := stack.open("forge", {"forge": f, "player": p}) as ForgeScreen
	await get_tree().process_frame
	assert_eq(Array(screen.tab_names()), ["Weapons", "Armour", "Reforge"], "three tabs")
	assert_true(screen.rows_text().has("Oak Club"), "Weapons: the weapon in hand: %s" % [screen.rows_text()])
	assert_true(Array(screen.rows_text()).any(func(t: String) -> bool: return t.begins_with("Quarry Maul")), "and the titan weapon")
	await _pad(JOY_BUTTON_RIGHT_SHOULDER)
	assert_eq(screen.current_tab(), "Armour", "RB: Armour")
	assert_eq(screen.row_buttons.size(), 40,
		"every piece's recipe (B2: the Kingsfall set's four; B3: the Warden set's four; C2: the Bastion set's seven; D1: the Frostbound set's seven; D2: the Stormcaller set's seven)")
	assert_true(screen.rows_text()[0].begins_with("Bastion Helm") and screen.rows_text()[0].ends_with("elsewhere"),
		"the titan sets first (C2: the Bastion set's, B2: the Kingsfall set's, then the Quarry set's), made elsewhere: %s"
		% screen.rows_text()[0])
	assert_true(screen.rows_text()[7].begins_with("Rime Crown") and screen.rows_text()[7].ends_with("elsewhere"),
		"D1: the Frostbound set after it, made elsewhere: %s" % screen.rows_text()[7])
	assert_true(screen.rows_text()[14].begins_with("Crown-iron Helm") and screen.rows_text()[14].ends_with("elsewhere"),
		"the Kingsfall set after it, made elsewhere: %s" % screen.rows_text()[14])
	assert_true(screen.rows_text()[18].begins_with("Quarry Pauldrons") and screen.rows_text()[18].ends_with("elsewhere"),
		"the Quarry set after it, made elsewhere: %s" % screen.rows_text()[18])
	var hood := -1
	for k in screen.row_buttons.size():
		if screen.rows_text()[k].begins_with("Hooded Hide Mantle"):
			hood = k
	screen.select(hood)
	assert_true(screen.detail_text().contains("Armour 2"), "its numbers: %s" % screen.detail_text())
	assert_false(screen.reforge_button.disabled, "three hides: Make it")
	assert_eq(screen.reforge_button.text, "Make it", "the action says what it does")
	assert_true(screen.press_action().ok, "made")
	assert_true(Armour.owns(GameSession.expansion.equipment, "armour.hide_hooded_mantle"), "owned")
	screen.show_tab(2)
	assert_eq(screen.rows_text(), PackedStringArray(["Hooded Hide Mantle  (tier 1 of 3)"]), "Reforge: the piece owned")
	screen.select(0)
	assert_eq(screen.reforge_button.text, "Reforge to tier 2", "its next tier")
	assert_eq(screen.perk_buttons.size(), 3, "its three perks to choose from")
	var out := screen.press_perk("armour_perk.frostproof")
	assert_true(out.ok, "a perk chosen: %s" % out.message)
	assert_eq(Armour.perk_of(GameSession.expansion.equipment, "armour.hide_hooded_mantle"), "armour_perk.frostproof", "kept")
	assert_true(screen.press_action().ok, "two hides: tier 2")
	assert_eq(screen.rows_text()[0], "Reforged Hooded Hide Mantle  (tier 2 of 3)", "the row follows")


func test_every_tab_of_both_fits_1280_by_720() -> void:
	var p := await _player()
	for sid: String in Armour.set_ids():
		_owns(Armour.set_pieces(sid))
	for id: Variant in Armour.set_pieces("armour_set.quarry"):
		Armour.equip(GameSession.expansion.equipment, str(id))
	Armour.equip(GameSession.expansion.equipment, "armour.iron_hauberk")
	Armour.equip(GameSession.expansion.equipment, "armour.iron_nasal_helm")
	Armour.equip(GameSession.expansion.equipment, "armour.hide_kilt")
	var screen := stack.open("character", {"player": p}) as CharacterScreen
	await get_tree().process_frame
	var room := Rect2(Vector2.ZERO, Vector2(VIEW.x, _rect(stack.get_node("NavHint") as Control).position.y))
	var bad := PackedStringArray()
	screen.show_tab(CharacterScreen.TABS.find("Equipment"))
	for s: String in Armour.SLOTS:
		screen._choose_slot(s)
		await get_tree().process_frame
		await get_tree().process_frame
		for c: Control in [screen.get_node("Frame") as Control, screen.close_button]:
			if not room.grow(0.5).encloses(_rect(c)):
				bad.append("Equipment (%s): %s %s" % [s, c.name, _rect(c)])
		for b: Button in screen.option_buttons:
			if not _rect(screen.get_node("Frame") as Control).grow(0.5).encloses(_rect(b)):
				bad.append("Equipment (%s): option %s outside the panel %s" % [s, b.text, _rect(b)])
	stack.close_all()
	var f := (load(FORGE) as PackedScene).instantiate() as Forge
	f.world_id = "test.b1_forge_fit"
	world.add_child(f)
	await step_ticks(1)
	var fs := stack.open("forge", {"forge": f, "player": p}) as ForgeScreen
	await get_tree().process_frame
	room = Rect2(Vector2.ZERO, Vector2(VIEW.x, _rect(stack.get_node("NavHint") as Control).position.y))
	for i in ForgeScreen.TABS.size():
		fs.show_tab(i)
		for k in mini(fs.row_buttons.size(), 12):
			fs.select(k)
			await get_tree().process_frame
			await get_tree().process_frame
			for c: Control in [fs.get_node("Frame") as Control, fs.leave_button, fs.reforge_button]:
				if not room.grow(0.5).encloses(_rect(c)):
					bad.append("forge %s row %d: %s %s" % [ForgeScreen.TABS[i], k, c.name, _rect(c)])
	assert_eq(bad, PackedStringArray(), "every tab of both screens fits above the footer")
