extends IntegrationSuite
## P33's shrine tabs and the ancestry screen with a pad (plan M6-M9 §2.14, §3.17; P16 conventions):
## the shrine shows Talents always and Ancestry once the Old Kingdom has opened and while it is still
## to choose. The Talents tab is one focus row per tier (the crowns last) and Learn, between the
## shrine's tab row and Leave, every direction wrapping; the detail follows the focus and says why a
## talent cannot be learned yet; A on a talent moves to Learn, A on Learn spends the point and gives
## the focus back; a grant is learned and goes into a free slot (or waits for the Loadout tab, and
## the tab says so). The Ancestry tab's Choose opens the ancestry screen on that ancestry: the focus
## starts on the ancestry, left / right browse, B backs out choosing nothing, a refusal stays on
## screen with its reason, Choose chooses and closes. Both fit a 1280 x 720 window. (One shrine
## screen for both tabs keeps the suite inside its time budget.)

const SHRINE := "res://scenes/world/shrine.tscn"

var stack: ScreenStack


func before_each() -> void:
	await super()
	InputBindings.reset_device()
	var layer := CanvasLayer.new()
	layer.layer = 10
	world.add_child(layer)
	stack = ScreenStack.new()
	layer.add_child(stack)
	await get_tree().process_frame


func after_each() -> void:
	if is_instance_valid(stack):
		stack.close_all()
	get_tree().paused = false
	InputRouter.set_context(InputRouter.Context.GAMEPLAY)
	InputBindings.reset_device()
	await super()


## One press and release of a pad button, dispatched at once (as the game reads it), then a frame
## for the stack's deferred focus wiring.
func _pad(button: JoyButton) -> void:
	for pressed in [true, false]:
		var e := InputEventJoypadButton.new()
		e.button_index = button
		e.pressed = pressed
		e.device = 0
		Input.parse_input_event(e)
		Input.flush_buffered_events()
	await get_tree().process_frame


func _focus() -> Control:
	return get_viewport().gui_get_focus_owner()


## A gated level-12 giant from the world start (eleven talent points, the Valley's loadout with slot
## 8 free), in the Old Kingdom, and the shrine screen of a shrine before it.
func _open_shrine() -> ShrineScreen:
	var p := spawn_player(Vector3(0, 0.05, 0))
	await step_ticks(1)
	var st := CharacterState.world_start(Progression.record(), GameData.get_record("player.giant"))
	st["level"] = 12
	st["xp"] = Progression.xp_for_level(12)
	st["talent_points"] = Talents.points_at_level(12)
	(st.loadout.slots as Array)[7] = ""
	p.apply_character_state(CharacterState.normalize(st))
	WorldState.set_flag(Talents.WORLD_FLAG, true)
	var s: Shrine = (load(SHRINE) as PackedScene).instantiate()
	s.world_id = "test.talent_shrine"
	s.shrine_id = "shrine.sandbox"
	s.position = Vector3(0, 0, -10)
	world.add_child(s)
	await step_ticks(1)
	var screen := stack.open("shrine", {"shrine": s, "player": p}) as ShrineScreen
	await get_tree().process_frame
	return screen


## The minimum size of a screen's panel (the shade is its first child, the panel its second).
static func _panel_size(screen: Control) -> Vector2:
	return (screen.get_child(1) as Control).get_combined_minimum_size()


func test_the_talents_and_ancestry_tabs_with_a_pad() -> void:
	var screen := await _open_shrine()
	var p := screen.player
	var prog: PlayerProgression = p.progression
	var titles: Array = []
	for t in screen.tabs:
		titles.append(t.tab_title())
	assert_eq(titles, ["Rest", "Grow", "Loadout", "Attributes", "Talents", "Ancestry"],
		"Talents always, Ancestry in the Old Kingdom before the choice")
	# --- the Talents tab
	await _pad(JOY_BUTTON_LEFT_SHOULDER)
	await _pad(JOY_BUTTON_LEFT_SHOULDER)
	var tab := screen.current_tab()
	assert_eq(tab.tab_title(), "Talents", "LB twice from Rest: the Talents tab (wrapping)")
	var buttons: Dictionary = tab.get("buttons")
	var learn: Button = tab.get("learn_button")
	assert_eq(buttons.size(), 27, "a button per talent")
	var sizes: Array = tab.focus_rows().map(func(r: Array) -> int: return r.size())
	assert_eq(sizes, [6, 6, 6, 6, 3, 1], "a row per tier across the three trees, the crowns, then Learn")
	assert_eq(_focus(), buttons["talent.destroyer_heavy_hands"], "the first talent ready to learn has the focus")
	assert_true(str(tab.call("detail_text")).begins_with("Heavy Hands — Destroyer, tier 1 (level 6), 1 point"),
		"the detail names it (%s)" % tab.call("detail_text"))
	assert_true(str(tab.call("detail_text")).contains("Heavy attack damage +10%"), "and what it does")
	assert_true(str(tab.call("points_text")).begins_with("Talent points: 11"), "the points (%s)" % tab.call("points_text"))
	await _pad(JOY_BUTTON_DPAD_LEFT)
	assert_eq(_focus(), buttons["talent.primordial_kindled"], "left wraps to the row's end (Kindled)")
	await _pad(JOY_BUTTON_DPAD_RIGHT)
	await _pad(JOY_BUTTON_DPAD_RIGHT)
	assert_eq(_focus(), buttons["talent.destroyer_iron_grip"], "right twice: Iron Grip")
	await _pad(JOY_BUTTON_DPAD_DOWN)
	assert_eq(_focus(), buttons["talent.destroyer_bone_breaker"], "down: the talent below it")
	assert_true(str(tab.call("detail_text")).contains("Bone Breaker needs Iron Grip first."), "and why it waits")
	await _pad(JOY_BUTTON_DPAD_UP)
	assert_eq(_focus(), buttons["talent.destroyer_iron_grip"], "up: back to Iron Grip")
	await _pad(JOY_BUTTON_A)
	assert_eq(_focus(), learn, "A selects Iron Grip and moves to Learn")
	assert_eq(learn.text, "Learn Iron Grip", "Learn names it")
	await _pad(JOY_BUTTON_A)
	assert_true(prog.knows_talent("talent.destroyer_iron_grip"), "A learns it")
	assert_eq(prog.talent_points, 10, "for one point")
	assert_eq(_focus(), buttons["talent.destroyer_iron_grip"], "the focus goes back to the talent")
	assert_true(str(tab.call("detail_text")).ends_with("Learned."), "now learned")
	assert_true(str(tab.call("passives_text")).contains("Grab reach +1.5 m"), "the passives line adds it up")
	await _pad(JOY_BUTTON_DPAD_DOWN)
	assert_true(str(tab.call("detail_text")).ends_with("Ready to learn. Talents last for good."), "Bone Breaker is open now")
	await _pad(JOY_BUTTON_A)
	assert_eq(_focus(), learn, "A on Bone Breaker: Learn")
	await _pad(JOY_BUTTON_DPAD_DOWN)
	assert_eq(_focus(), screen.leave_button(), "down from Learn: the shrine's Leave")
	await _pad(JOY_BUTTON_DPAD_DOWN)
	assert_true(screen.tab_buttons().has(_focus()), "and down again wraps to the tab row")
	assert_false(prog.knows_talent("talent.destroyer_bone_breaker"), "moving away learned nothing")
	# Grants: into the free slot, then (none left) known and waiting for the Loadout tab.
	assert_true(bool(tab.call("learn", "talent.destroyer_heavy_hands").ok), "Heavy Hands")
	var r: Dictionary = tab.call("learn", "talent.destroyer_shoulder_charge")
	assert_eq(r.learned, ["ability.shoulder_charge"], "Shoulder Charge teaches its ability")
	assert_eq(str(p.controller.loadout.slot_8), "ability.shoulder_charge", "into the free slot")
	assert_eq(str(tab.call("result_text")),
		"Talent learned: Shoulder Charge (new ability: Shoulder Charge). It is on slot 8.", "and the tab says where")
	assert_true(bool(tab.call("learn", "talent.guardian_stone_hide").ok), "Stone Hide")
	tab.call("learn", "talent.guardian_bulwark")
	assert_true(prog.knows("ability.bulwark") and not p.controller.loadout.values().has("ability.bulwark"),
		"Bulwark is known; no slot is free")
	assert_true(str(tab.call("result_text")).ends_with("Put it on a key in the Loadout tab."), "and the tab says where it goes")
	assert_eq(str(tab.call("learn", "talent.guardian_mountains_heart").reason), "requires", "a crown waits for its tier 4")
	assert_true(_panel_size(screen).x <= 1280.0 and _panel_size(screen).y <= 700.0,
		"the shrine panel with the trees fits 1280 x 720 (%s)" % _panel_size(screen))
	# --- the Ancestry tab and the ancestry screen
	await _pad(JOY_BUTTON_RIGHT_SHOULDER)
	tab = screen.current_tab()
	assert_eq(tab.tab_title(), "Ancestry", "RB: the Ancestry tab")
	var choose: Dictionary = tab.get("choose_buttons")
	assert_eq(choose.size(), 3, "a Choose button per ancestry")
	assert_eq(_focus(), choose["ancestry.stoneblood"], "the first Choose has the focus")
	await _pad(JOY_BUTTON_DPAD_RIGHT)
	await _pad(JOY_BUTTON_A)
	var anc := stack.top() as AncestryScreen
	assert_true(anc != null and anc.screen_name == "ancestry", "A opens the ancestry screen")
	if anc == null:
		return
	assert_eq(anc.selected, "ancestry.stormborn", "on Stormborn")
	assert_eq(_focus(), anc.ancestry_buttons["ancestry.stormborn"], "the focus starts on the ancestry, not on Choose")
	assert_true(anc.detail_text().contains("Attributes at once: Intellect +3, Willpower +2"), "what it gives (%s)" % anc.detail_text())
	assert_true(anc.detail_text().contains("Signature ability: Thunderhead"), "its signature")
	await _pad(JOY_BUTTON_DPAD_RIGHT)
	assert_eq(anc.selected, "ancestry.wildheart", "right: Wildheart is shown")
	assert_eq(anc.confirm_button.text, "Choose Wildheart", "Choose names it")
	assert_true(anc.detail_text().contains("Movement speed +5%"), "with its strengths")
	await _pad(JOY_BUTTON_B)
	assert_false(stack.is_open("ancestry"), "B backs out")
	assert_false(prog.ancestry_chosen, "choosing nothing")
	assert_true(stack.top() == screen, "back on the shrine")
	await _pad(JOY_BUTTON_A)
	anc = stack.top() as AncestryScreen
	assert_true(anc != null and anc.selected == "ancestry.stoneblood", "A on the first Choose: Stoneblood")
	if anc == null:
		return
	await _pad(JOY_BUTTON_DPAD_DOWN)
	assert_eq(_focus(), anc.confirm_button, "down: Choose")
	await _pad(JOY_BUTTON_DPAD_RIGHT)
	await _pad(JOY_BUTTON_DPAD_RIGHT)
	assert_eq(_focus(), anc.confirm_button, "right twice: Back, then Choose again (wrapping)")
	p.entity.combatant.pools.mark_combat()
	await _pad(JOY_BUTTON_A)
	assert_true(stack.top() == anc, "a refusal keeps the screen open")
	assert_eq(anc.status_text(), "Not during combat.", "with its reason")
	p.entity.combatant.pools.since_combat = 999.0
	assert_true(_panel_size(anc).x <= 1280.0 and _panel_size(anc).y <= 700.0,
		"the ancestry screen fits 1280 x 720 (%s)" % _panel_size(anc))
	await _pad(JOY_BUTTON_A)
	assert_true(prog.ancestry_chosen and prog.ancestry == "ancestry.stoneblood", "Choose chooses Stoneblood")
	assert_true(stack.top() == screen, "and closes")
	assert_true(str(tab.call("result_text")).begins_with("You are Stoneblood. Bedrock Ward is yours"),
		"the tab says what came of it (%s)" % tab.call("result_text"))
	assert_false((choose["ancestry.stoneblood"] as Button).visible, "no more Choose buttons")
	assert_true(screen.is_ancestor_of(_focus()), "the focus stays on the shrine")
	var again := stack.open("ancestry", {"player": p}) as AncestryScreen
	assert_true(again.confirm_button.disabled, "opened later, the screen only names the ancestry")
	assert_eq(again.status_text(), "You are Stoneblood: an ancestry is chosen once.", "and says so")
