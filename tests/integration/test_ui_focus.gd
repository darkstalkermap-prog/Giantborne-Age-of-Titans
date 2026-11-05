extends IntegrationSuite
## P16 (plan §3.18, §5.5): every menu is usable with a controller alone. Synthetic joypad events
## (D-pad = ui_up / ui_down / ui_left / ui_right, A = ui_accept, B = ui_cancel, LB / RB = pages)
## move the focus through Title, Pause, Shrine, Dialogue, Inventory, Attributes, Forge and End,
## wrap around at both ends, skip disabled entries, and press the focused button; B backs out.
## Rebinding keeps Esc as its cancel. Glyph switching: the prompts, the hotbar keys, the mode line,
## the controls overlay and the menu footer follow the last device (and the Button prompts
## setting). The real pad is NOT RUN here (docs/USABILITY_SCRIPT.md has its checklist).

const Fx := preload("res://tests/support/quest_fixtures.gd")
const SHRINE := "res://scenes/world/shrine.tscn"
const FORGE := "res://scenes/world/forge.tscn"
const STORY := "dialogue.test_story"

var stack: ScreenStack
var rested: Array[String] = []


func before_each() -> void:
	await super()
	InputBindings.reset_device()
	rested.clear()
	Events.shrine_rested.connect(_on_rested)
	var layer := CanvasLayer.new()
	layer.layer = 10
	world.add_child(layer)
	stack = ScreenStack.new()
	stack.name = "ScreenStack"
	layer.add_child(stack)
	await get_tree().process_frame


func after_each() -> void:
	if Events.shrine_rested.is_connected(_on_rested):
		Events.shrine_rested.disconnect(_on_rested)
	if is_instance_valid(stack):
		stack.close_all()
	get_tree().paused = false
	InputRouter.set_context(InputRouter.Context.GAMEPLAY)
	InputBindings.reset_device()
	Settings.set_value("prompt_device", "auto", false)
	await super()


func _on_rested(_t: int, shrine_id: String) -> void:
	rested.append(shrine_id)


# --------------------------------------------------------------------------- helpers

## One press and release of a pad button (the device the real game reads through main.gd).
func _pad(button: JoyButton) -> void:
	for pressed in [true, false]:
		var e := InputEventJoypadButton.new()
		e.button_index = button
		e.pressed = pressed
		e.device = 0
		Input.parse_input_event(e)
		await get_tree().process_frame
	await get_tree().process_frame


func _down() -> void:
	await _pad(JOY_BUTTON_DPAD_DOWN)


func _up() -> void:
	await _pad(JOY_BUTTON_DPAD_UP)


func _right() -> void:
	await _pad(JOY_BUTTON_DPAD_RIGHT)


func _accept() -> void:
	await _pad(JOY_BUTTON_A)


func _back() -> void:
	await _pad(JOY_BUTTON_B)


func _key(keycode: Key) -> void:
	for pressed in [true, false]:
		var k := InputEventKey.new()
		k.keycode = keycode
		k.physical_keycode = keycode
		k.pressed = pressed
		Input.parse_input_event(k)
		await get_tree().process_frame
	await get_tree().process_frame


func _focus() -> Control:
	return get_viewport().gui_get_focus_owner()


## Presses up (or down) until cond() holds, at most 12 times. True when it held.
func _up_until(cond: Callable) -> bool:
	for i in 12:
		if cond.call():
			return true
		await _up()
	return bool(cond.call())


func _down_until(cond: Callable) -> bool:
	for i in 12:
		if cond.call():
			return true
		await _down()
	return bool(cond.call())


## Opens a screen and waits two frames (the stack wires its focus rows again after the layout).
func _open(screen_name: String, args := {}) -> UiScreen:
	var s := stack.open(screen_name, args)
	await get_tree().process_frame
	await get_tree().process_frame
	return s


func _name(c: Control) -> String:
	if c == null:
		return "<none>"
	return (c as Button).text if c is Button else str(c.name)


func _grounded_player(pos := Vector3(0, 0.05, 0)) -> GiantPlayer:
	var p := spawn_player(pos, 0.0)
	await TestWait.until(self, func() -> bool: return p.is_on_floor(), 30)
	await step_ticks(1)
	return p


func _shrine(pos: Vector3) -> Shrine:
	var s: Shrine = (load(SHRINE) as PackedScene).instantiate()
	s.world_id = "test.ui_shrine"
	s.shrine_id = "shrine.sandbox"
	s.position = pos
	world.add_child(s)
	return s


func _hud() -> Hud:
	var layer := CanvasLayer.new()
	world.add_child(layer)
	var hud := Hud.new()
	layer.add_child(hud)
	return hud


func _pad_event(button: JoyButton) -> InputEventJoypadButton:
	var e := InputEventJoypadButton.new()
	e.button_index = button
	e.pressed = true
	return e


func _key_event(keycode: Key) -> InputEventKey:
	var k := InputEventKey.new()
	k.keycode = keycode
	k.physical_keycode = keycode
	k.pressed = true
	return k


# --------------------------------------------------------------------------- the menus

func test_pad_actions_are_in_the_menu_input_map() -> void:
	assert_true(UiNav.has_pad_button("ui_accept", JOY_BUTTON_A), "pad A accepts")
	assert_true(UiNav.has_pad_button("ui_cancel", JOY_BUTTON_B), "pad B cancels")
	assert_true(InputMap.action_get_events("ui_accept").size() >= 2, "Enter still accepts")
	UiNav.ensure_pad_actions()
	var n := 0
	for e: InputEvent in InputMap.action_get_events("ui_cancel"):
		if e is InputEventJoypadButton:
			n += 1
	assert_eq(n, 1, "adding them again changes nothing")


## The title (the play link's first screen): the menu column wraps and skips the disabled
## Continue; A opens Settings (Back focused), B returns to its menu entry, A on Sandbox starts it.
func test_title_screen_with_a_pad() -> void:
	GameSession.mode = GameSession.Mode.TITLE
	var title := await _open("title") as TitleScreen
	assert_true(title != null, "the title opened")
	assert_eq(_focus(), title.button("New Game"), "New Game has the focus (no save: Continue is off)")
	var expected := ["Sandbox", "Settings", "Controls"]
	if title.button("Quit").visible:
		expected.append("Quit")
	expected.append("New Game")
	var seen: Array = []
	for i in expected.size():
		await _down()
		seen.append(_name(_focus()))
	assert_eq(seen, expected, "down walks the menu, skips the disabled Continue and wraps")
	await _up()
	assert_eq(_name(_focus()), str(expected[expected.size() - 2]), "up from the first entry wraps to the last")
	assert_true(await _up_until(func() -> bool: return _name(_focus()) == "Settings"), "up reaches Settings")
	await _accept()
	assert_eq(title.current_page(), "Settings", "A opens the Settings page")
	assert_eq(_name(_focus()), "Back", "focused on Back")
	var rows: Array = title.settings_pages().settings_rows()
	await _down()
	assert_eq(_focus(), rows[0][0], "down reaches the first setting")
	await _up()
	await _up()
	assert_true(_focus() is OptionButton and _focus() != rows[0][0], "up from Back wraps to the last setting row")
	await _back()
	assert_eq(title.current_page(), "", "B leaves the page")
	assert_eq(_name(_focus()), "Settings", "back on its menu entry")
	assert_true(title.is_open(), "B never closes the title")
	assert_eq(stack.hint_text(), UiNav.hint_text(false), "the footer names the keyboard before any pad input")
	assert_true(await _up_until(func() -> bool: return _name(_focus()) == "Sandbox"), "up reaches Sandbox")
	await _accept()
	assert_eq(GameSession.last_mode_result.get("ok", false), true, "A on Sandbox starts the sandbox")
	assert_eq(GameSession.scene_reloads.back(), "sandbox", "a reload into the sandbox")
	stack.close_all()


## Pause: the main items wrap through the page tabs, LB / RB switch pages, A starts a rebinding
## capture that Esc cancels without closing the menu, B resumes.
func test_pause_menu_with_a_pad_and_esc_cancels_a_capture() -> void:
	var menu := await _open("pause") as PauseMenu
	assert_eq(_name(_focus()), "Resume", "Resume has the focus")
	var walk: Array = []
	for i in 4:
		await _down()
		walk.append(_name(_focus()))
	var expected := ["Restart sandbox", "Quit to title"]
	if menu.item("Quit to desktop").visible:
		expected.append("Quit to desktop")
	assert_eq(walk.slice(0, expected.size()), expected, "down walks the sandbox items (no checkpoint item)")
	var tabs := [menu.tab_button("Main"), menu.tab_button("Settings"), menu.tab_button("Controls")]
	assert_true(await _down_until(func() -> bool: return tabs.has(_focus())), "down reaches the tab row")
	await _down()
	assert_eq(_name(_focus()), "Resume", "past the last item the focus wraps through the page tabs to Resume")
	await _up()
	assert_true(tabs.has(_focus()), "up from Resume reaches the tab row")
	var first_tab := _focus()
	for i in 3:
		await _right()
	assert_eq(_focus(), first_tab, "right walks the three tabs and wraps")
	await _pad(JOY_BUTTON_RIGHT_SHOULDER)
	await _pad(JOY_BUTTON_RIGHT_SHOULDER)
	assert_eq(menu.current_page(), "Controls", "RB twice: Controls")
	await _pad(JOY_BUTTON_RIGHT_SHOULDER)
	assert_eq(menu.current_page(), "Main", "RB wraps to Main")
	await _pad(JOY_BUTTON_LEFT_SHOULDER)
	assert_eq(menu.current_page(), "Controls", "LB goes back to Controls")
	assert_eq(_focus(), menu.tab_button("Controls"), "with its tab focused")
	var pages := menu.settings_pages()
	await _down()
	var row0: Array = pages.controls_rows()[0]
	assert_true(row0.has(_focus()), "down reaches the first binding row")
	await _accept()
	assert_true(pages.is_capturing(), "A starts a rebinding capture")
	await _key(KEY_ESCAPE)
	assert_false(pages.is_capturing(), "Esc cancels the capture")
	assert_true(menu.is_open(), "and does not close the menu")
	pages.begin_capture("jump", true)
	assert_false(pages.update_capture(Time.get_ticks_msec() + 1000), "a capture waits")
	assert_true(pages.update_capture(Time.get_ticks_msec() + int(SettingsPages.CAPTURE_TIMEOUT_S * 1000.0) + 10),
		"and gives up by itself (a controller has no Esc)")
	assert_false(pages.is_capturing(), "nothing bound")
	await _back()
	assert_false(stack.any_open(), "B resumes")
	assert_false(get_tree().paused, "the game runs again")


## Shrine: tabs, Rest with A, a Loadout list opened with A and closed with B (the screen stays),
## points planned and confirmed on the Attributes tab, B leaves.
func test_shrine_screen_with_a_pad() -> void:
	var p := await _grounded_player()
	p.progression.unspent_attribute_points = 2
	var s := _shrine(Vector3(0, 0, -10))
	var screen := await _open("shrine", {"shrine": s, "player": p}) as ShrineScreen
	assert_true(screen != null, "the shrine screen opened")
	var rest_button: Button = (screen.tab("Rest") as Node).get("rest_button")
	assert_eq(_focus(), rest_button, "Rest has the focus")
	await _down()
	assert_eq(_focus(), screen.leave_button(), "down: Leave")
	await _down()
	assert_true(screen.tab_buttons().has(_focus()), "down again wraps to the tab row")
	await _down()
	assert_eq(_focus(), rest_button, "and back to Rest")
	await _accept()
	assert_eq(rested, ["test.ui_shrine"], "A rests")
	await _pad(JOY_BUTTON_RIGHT_SHOULDER)
	await _pad(JOY_BUTTON_RIGHT_SHOULDER)
	assert_eq(screen.current_tab().tab_title(), "Loadout", "RB twice: the Loadout tab")
	var rows: Array = screen.current_tab().focus_rows()
	assert_eq(rows.size(), 9, "eight slot lists and the ultimate")
	assert_eq(_focus(), rows[0][0], "the slot-1 list has the focus")
	await _down()
	var opt := rows[1][0] as OptionButton
	assert_eq(_focus(), opt, "down: the slot-2 list")
	await _accept()
	assert_true(opt.get_popup().visible, "A opens its list")
	await _back()
	assert_false(opt.get_popup().visible, "B closes the list")
	assert_true(stack.is_open("shrine"), "and only the list")
	await _pad(JOY_BUTTON_RIGHT_SHOULDER)
	assert_eq(screen.current_tab().tab_title(), "Attributes", "RB: the Attributes tab")
	var panel: AttributePanel = (screen.current_tab() as Node).get("panel_ui")
	var strength: Dictionary = panel.buttons_of("strength")
	var endurance: Dictionary = panel.buttons_of("endurance")
	assert_eq(_focus(), strength.plus, "the first + has the focus")
	var before: Dictionary = p.progression.attributes()
	await _accept()
	assert_eq(int(panel.pending.get("strength", 0)), 1, "A plans a Strength point")
	await _down()
	assert_eq(_focus(), endurance.plus, "down: Endurance's + (the column is kept)")
	await _accept()
	assert_eq(_focus(), panel.confirm_button, "no point left: the focus moves to Confirm")
	await _accept()
	var after: Dictionary = p.progression.attributes()
	assert_eq([int(after.strength) - int(before.strength), int(after.endurance) - int(before.endurance)], [1, 1],
		"A confirms both points")
	await _back()
	assert_false(stack.any_open(), "B leaves the shrine")


## Dialogue: the choices wrap; A takes the focused one (Goodbye ends the conversation).
func test_dialogue_with_a_pad() -> void:
	Fx.install([Fx.storyteller_dialogue(STORY)])
	var session := Quests.start_dialogue(STORY, "test.npc")
	assert_true(session != null and session.is_active(), "a conversation")
	var screen := await _open("dialogue", {"session": session}) as DialogueScreen
	assert_eq(_focus(), screen.choice_buttons[0], "the first choice has the focus")
	await _down()
	assert_eq(_focus(), screen.choice_buttons[1], "down: the second")
	await _down()
	assert_eq(_focus(), screen.choice_buttons[0], "and wraps")
	await _up()
	assert_eq(_name(_focus()), "2. Goodbye.", "up wraps to Goodbye")
	await _accept()
	await get_tree().process_frame
	assert_false(stack.is_open("dialogue"), "A on Goodbye ends it and the screen closes")
	assert_true(Quests.dialogue == null, "no conversation left")


## Inventory and Attributes: Close first, the column wraps over Attributes and Equip; A equips;
## A on Attributes opens that screen on top, where a point is planned, confirmed, then Close.
func test_inventory_and_attributes_with_a_pad() -> void:
	var p := await _grounded_player()
	p.progression.unspent_attribute_points = 1
	assert_true(bool(p.equipment.grant_weapon("weapon.sword").ok), "a sword in the bag")
	var inv := await _open("inventory", {"player": p}) as InventoryScreen
	assert_eq(_focus(), inv.close_button, "Close has the focus")
	await _down()
	assert_eq(_focus(), inv.attributes_button, "down wraps to Attributes")
	await _down()
	assert_eq(_focus(), inv.equip_buttons.get("weapon.sword"), "then the sword's Equip")
	await _accept()
	assert_eq(p.equipment.weapon_id(), "weapon.sword", "A equips it")
	assert_eq(_focus(), inv.close_button, "the list was rebuilt: the focus is back on Close")
	assert_true(await _up_until(func() -> bool: return _focus() == inv.attributes_button), "up reaches Attributes")
	await _accept()
	assert_true(stack.top() is AttributesScreen, "A opens the Attributes screen on top")
	var attrs := stack.top() as AttributesScreen
	await get_tree().process_frame
	assert_eq(_focus(), attrs.panel_ui.buttons_of("strength").plus, "its first + has the focus")
	var strength := int(p.progression.attributes().strength)
	await _accept()
	assert_eq(_focus(), attrs.panel_ui.confirm_button, "the point is planned: Confirm")
	await _accept()
	assert_eq(int(p.progression.attributes().strength), strength + 1, "confirmed")
	assert_eq(_focus(), attrs.close_button(), "nothing left to spend: Close")
	await _accept()
	assert_true(stack.top() == inv, "Close returns to the inventory")
	assert_eq(_focus(), inv.close_button, "with its focus")
	await _back()
	assert_false(stack.any_open(), "B closes the inventory")


## Forge: Reforge and Leave wrap; A reforges, then the focus moves to Leave and A leaves.
func test_forge_with_a_pad() -> void:
	var p := await _grounded_player()
	WorldState.add_item("item.iron_ingot", 2, "test")
	var f := (load(FORGE) as PackedScene).instantiate() as Forge
	f.world_id = "test.ui_forge"
	f.position = Vector3(10, 0, 0)
	world.add_child(f)
	await step_ticks(1)
	var screen := await _open("forge", {"forge": f, "player": p}) as ForgeScreen
	assert_eq(_focus(), screen.reforge_button, "Reforge has the focus")
	await _down()
	assert_eq(_focus(), screen.leave_button, "down: Leave")
	await _down()
	assert_eq(_focus(), screen.reforge_button, "and wraps")
	await _accept()
	assert_eq(p.equipment.weapon_id(), "weapon.club_reinforced", "A reforges the club")
	assert_eq(_focus(), screen.leave_button, "Reforge is spent: the focus moves to Leave")
	await _accept()
	assert_false(stack.any_open(), "A on Leave closes the forge")


## End: Continue exploring and Quit to title wrap; A continues.
func test_end_screen_with_a_pad() -> void:
	var screen := await _open("end", {"time_s": 61.0, "deaths": 1, "level": 3, "stage": 2,
		"outcome": "help_ogre"}) as EndScreen
	assert_eq(_focus(), screen.continue_button, "Continue exploring has the focus")
	await _down()
	assert_eq(_focus(), screen.quit_button, "down: Quit to title")
	await _down()
	assert_eq(_focus(), screen.continue_button, "and wraps")
	await _accept()
	assert_false(stack.any_open(), "A continues exploring")


# --------------------------------------------------------------------------- glyphs

func test_the_last_device_decides_the_glyphs() -> void:
	assert_false(InputBindings.last_device_is_pad(), "keyboard and mouse by default")
	var serial := InputBindings.device_serial
	assert_true(InputBindings.note_device(_pad_event(JOY_BUTTON_A)), "a pad button switches to the pad")
	assert_true(InputBindings.last_device_is_pad(), "pad")
	assert_true(InputBindings.device_serial > serial, "readers see the change")
	assert_false(InputBindings.note_device(_pad_event(JOY_BUTTON_B)), "a second pad button changes nothing")
	var drift := InputEventMouseMotion.new()
	drift.relative = Vector2(2, 1)
	assert_false(InputBindings.note_device(drift), "a mouse twitch does not switch")
	var stick := InputEventJoypadMotion.new()
	stick.axis = JOY_AXIS_LEFT_X
	stick.axis_value = 0.2
	assert_true(InputBindings.note_device(_key_event(KEY_W)), "a key switches back")
	assert_false(InputBindings.note_device(stick), "stick drift does not switch to the pad")
	stick.axis_value = 0.9
	assert_true(InputBindings.note_device(stick), "a real stick push does")
	var move := InputEventMouseMotion.new()
	move.relative = Vector2(30, 0)
	assert_true(InputBindings.note_device(move), "a real mouse movement switches back")
	var up := InputEventJoypadButton.new()
	up.button_index = JOY_BUTTON_A
	up.pressed = false
	assert_false(InputBindings.note_device(up), "releases never switch")
	Settings.set_value("prompt_device", "pad", false)
	assert_true(InputBindings.last_device_is_pad(), "the Button prompts setting pins the pad")
	InputBindings.note_device(_key_event(KEY_W))
	assert_true(InputBindings.last_device_is_pad(), "whatever was used last")
	Settings.set_value("prompt_device", "keyboard", false)
	InputBindings.note_device(_pad_event(JOY_BUTTON_A))
	assert_false(InputBindings.last_device_is_pad(), "or the keyboard")
	Settings.set_value("prompt_device", "auto", false)
	assert_true(InputBindings.last_device_is_pad(), "auto follows the last device again")


## The interact prompt, the hotbar keys, the mode line, the lock hint, the controls overlay and the
## menu footer switch with the device.
func test_hud_prompts_follow_the_device() -> void:
	var p := await _grounded_player()
	var hud := _hud()
	_shrine(Vector3(0, 0, -4))
	await step_ticks(8)
	await get_tree().process_frame
	var prompt := hud.get_node_or_null("InteractPrompt")
	assert_true(prompt != null, "the interact prompt widget")
	var kb_key := InputBindings.describe_action("interact", false)
	var pad_key := InputBindings.short_pad_label("interact")
	assert_eq(str(prompt.call("visible_text")), "[%s] %s" % [kb_key, p.interact.current_prompt()], "keyboard: [E]")
	assert_eq(hud.slot_state(0).key, InputBindings.describe_action("ability_1", false), "the hotbar shows the key")
	assert_eq(hud.slot_state(0).alt_key, InputBindings.short_pad_label("ability_1"), "and the pad combo small")
	assert_true(hud.mode_line_text().contains("controls"), "the mode line names the overlay key")
	assert_eq(Hud.lock_hint(false), "LOCKED  -  %s / %s to switch" % [InputBindings.describe_action("target_prev", false),
		InputBindings.describe_action("target_next", false)], "keyboard lock hint")
	InputBindings.note_device(_pad_event(JOY_BUTTON_A))
	await get_tree().process_frame
	await get_tree().process_frame
	assert_eq(str(prompt.call("visible_text")), "[%s] %s" % [pad_key, p.interact.current_prompt()], "pad: [X]")
	assert_eq(hud.slot_state(0).key, InputBindings.short_pad_label("ability_1"), "the hotbar shows the pad combo")
	assert_eq(hud.slot_state(0).alt_key, InputBindings.describe_action("ability_1", false), "and the key small")
	assert_eq(hud.mode_line_text(), Hud.mode_line(false, 1, true), "the mode line names the pad buttons")
	assert_true(hud.mode_line_text().contains("menu and controls"), "and points a pad player to the menu")
	assert_eq(Hud.lock_hint(true), "LOCKED  -  flick the right stick to switch", "pad lock hint")
	stack.open("pause")
	await get_tree().process_frame
	assert_eq(stack.hint_text(), UiNav.hint_text(true), "the menu footer names A and B")
	stack.close_all()
	await get_tree().process_frame
	hud.toggle_help()
	assert_true(hud.help_visible(), "the controls overlay opens")
	var labels: Array = hud.help_rows().map(func(r: Array) -> String: return str(r[0]))
	assert_true(labels.has("Interact / grab / talk"), "it lists interact")
	assert_true(labels.has("Inventory"), "and the inventory")
	assert_true(labels.has("Runic Bolt (slot 6)"), "and the loadout's abilities")
	p.set_loadout_slot("slot_6", "")
	await get_tree().process_frame
	labels = hud.help_rows().map(func(r: Array) -> String: return str(r[0]))
	assert_false(labels.has("Runic Bolt (slot 6)"), "built from the live loadout")
	assert_false(hud.help_text().contains("Runic Bolt"), "the open overlay follows the change")
	hud.toggle_help()
