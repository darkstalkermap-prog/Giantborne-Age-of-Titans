extends IntegrationSuite
## M8 gate (F7): the yield prompt against the fight's own inputs, through real input events
## (Input.parse_input_event: Input's state, the real ScreenStack, the prompt's input handlers and its
## buttons) and YieldPrompt.test_clock (tests/support/yield_input.gd), so its arm and hold times pass
## without waiting. Mashed ability keys 1-4, pad buttons and mouse clicks never arm it, a trigger
## held as it opens keeps it unarmed until let go, the number keys never choose, and it is still
## answered on purpose with the pad, the keyboard and the mouse: "No - let me think again" comes first
## on the confirm line, and every choice of a deciding line is held, never tapped. The full matrix
## (every order of keys 1-4 and of the face buttons, both bosses, wall-clock mashes) is
## tests/slow/test_yield_prompt_mashing.gd. M8 gate fix-up 1 (N3.1): a stick resting between the move and
## look actions' dead zone (0.2) and the prompt's touch threshold (AXIS_TOUCH, 0.5) - a pad's drift - is
## not touching the controls: the prompt arms, while a key held from before it opened still holds it.

const CORVANE := "res://scenes/enemies/corvane.tscn"
const HARROK := "res://scenes/enemies/harrok.tscn"

var io: YieldInput
var stack: ScreenStack


func before_each() -> void:
	await super()
	WorldState.clear()
	Quests.end_dialogue()
	InputBindings.reset_device(false)
	io = YieldInput.new(self)
	io.install()
	var layer := CanvasLayer.new()
	world.add_child(layer)
	stack = ScreenStack.new()
	layer.add_child(stack)


func after_each() -> void:
	io.release_all()
	io.uninstall()
	InputBindings.reset_device(false)
	Quests.end_dialogue()
	get_tree().paused = false
	await super()


func _boss(path: String, id: String) -> EnemyActor:
	spawn_player(Vector3(0, 0.05, 24), 0.0)
	var e := (load(path) as PackedScene).instantiate() as EnemyActor
	e.entity_id = id
	e.ai_enabled = false
	e.position = Vector3(0, 0.05, 0)
	world.add_child(e)
	await step_ticks(2)
	return e


## Yields `boss` and returns its prompt once the stack has opened it.
func _yield(boss: EnemyActor) -> YieldPrompt:
	boss.p34_yield("health")
	await io.frame()
	await io.frame()
	var p := stack.top() as YieldPrompt
	assert_true(p != null, "the yield prompt opens")
	return p


func _texts(p: YieldPrompt) -> Array:
	return Array(p.choice_texts())


func _focused(p: YieldPrompt) -> String:
	var f := UiNav.focus_owner(p)
	return (f as Button).text if f is Button and p.is_ancestor_of(f) else ""


## Lets every button go and waits out the arm time.
func _settle(p: YieldPrompt) -> void:
	io.release_all()
	await io.wait_ms(int(YieldPrompt.ARM_S * 1000.0) + 100)
	assert_true(p.armed(), "armed once every button was let go for %.2f s" % YieldPrompt.ARM_S)


func test_fight_inputs_never_arm_or_decide_it() -> void:
	var c := await _boss(CORVANE, "test.corvane")
	var p := await _yield(c)
	assert_eq(_texts(p), ["Spare him. Stand down, warlord.", "Strike him down."], "no numbers on its choices")
	var undecided := func() -> bool: return c.yield_decided != ""
	for pattern: Array in [[KEY_1, KEY_2], [KEY_2, KEY_1], [JOY_BUTTON_A, JOY_BUTTON_B], ["mouse", "rt"]]:
		var taps := await io.mash(pattern, 2000, YieldInput.PATTERN_GAP_MS, undecided)
		assert_false(p.armed(), "%s mashed for 2 s (%d taps): never armed" % [pattern, taps])
		assert_eq(c.yield_decided, "", "%s: nothing decided" % [pattern])
		assert_true(Quests.dialogue != null and Quests.dialogue.find_choice("spare") >= 0, "%s: still the first line" % [pattern])
		assert_true(p.choice_buttons.all(func(b: Button) -> bool: return b.disabled), "%s: its choices disabled" % [pattern])
		assert_eq(p.hint_text(), "Let go of every button to choose.", "%s: the line says how to arm it" % [pattern])
	# Armed, the number keys still take nothing.
	await _settle(p)
	for k: Key in [KEY_1, KEY_2, KEY_KP_1, KEY_KP_2]:
		await io.tap(k)
	assert_eq(c.yield_decided, "", "keys 1 and 2 never choose")
	assert_true(Quests.dialogue.find_choice("spare") >= 0, "still the first line")
	assert_false(WorldState.has_flag("boss.corvane.outcome"), "no outcome written")
	assert_true(c.entity.is_alive(), "Corvane alive")


func test_a_trigger_held_as_it_opens_keeps_it_unarmed_until_let_go() -> void:
	var h := await _boss(HARROK, "test.harrok")
	await io.axis(JOY_AXIS_TRIGGER_RIGHT, 1.0)   # the heavy attack, held through the yield
	var p := await _yield(h)
	await io.wait_ms(2000)
	assert_false(p.armed(), "RT held for 2 s: not armed")
	await io.axis(JOY_AXIS_TRIGGER_RIGHT, 0.0)
	await io.wait_ms(500)
	assert_false(p.armed(), "0.5 s after letting go: not yet")
	await io.wait_ms(350)
	assert_true(p.armed(), "0.85 s after letting go: armed")
	assert_eq(_focused(p), "Spare him. The duel is won.", "the focus starts on Spare")


func test_a_drifting_stick_does_not_keep_it_unarmed() -> void:
	var h := await _boss(HARROK, "test.harrok")
	var p := await _yield(h)
	await io.axis(JOY_AXIS_LEFT_X, 0.3)   # the left stick at rest a little off centre (drift)
	await io.axis(JOY_AXIS_RIGHT_Y, -0.25)
	assert_true(Input.is_action_pressed("move_right"), "past move_right's own dead zone (0.2)")
	assert_false(p.touching_now(), "but under the prompt's touch threshold: not touching")
	await io.wait_ms(int(YieldPrompt.ARM_S * 1000.0) + 100)
	assert_true(p.armed(), "armed with the stick drifting at 0.3 (%s)" % p.hint_text())
	assert_eq(_focused(p), "Spare him. The duel is won.", "the focus starts on Spare")
	# A stick pushed past AXIS_TOUCH on a new line still touches the controls.
	await io.axis(JOY_AXIS_LEFT_X, 0.8)
	assert_true(p.touching_now(), "a stick pushed to 0.8 touches the controls")
	await io.axis(JOY_AXIS_LEFT_X, 0.3)


func test_a_key_held_from_before_it_opened_keeps_it_unarmed() -> void:
	var h := await _boss(HARROK, "test.harrok")
	await io.key_down(KEY_W)   # walking into the yield
	var p := await _yield(h)
	await io.axis(JOY_AXIS_LEFT_X, 0.3)
	await io.wait_ms(1500)
	assert_true(p.touching_now(), "W held since before the prompt opened touches the controls")
	assert_false(p.armed(), "W held for 1.5 s (a drifting stick too): not armed")
	await io.key_up(KEY_W)
	await io.wait_ms(int(YieldPrompt.ARM_S * 1000.0) + 100)
	assert_true(p.armed(), "let go: armed")


func test_answered_on_purpose_with_the_pad() -> void:
	InputBindings.reset_device(true)
	var c := await _boss(CORVANE, "test.corvane")
	var p := await _yield(c)
	await _settle(p)
	assert_true(p.line_decides(), "the first line decides")
	assert_eq(p.hint_text(), YieldPrompt.hint_for(true, true, false, true), "the pad's line: hold A")
	assert_true(p.hint_text().begins_with("Hold A"), "it says to hold A")
	await io.tap(JOY_BUTTON_A)
	assert_eq(c.yield_decided, "", "a tap of A on Spare takes nothing")
	await io.tap(JOY_BUTTON_DPAD_DOWN)
	assert_eq(_focused(p), "Strike him down.", "D-pad down moves to Strike")
	await io.hold(JOY_BUTTON_A, int(YieldPrompt.HOLD_S * 1000.0) + 100)
	assert_true(Quests.dialogue.find_choice("strike") >= 0, "held: the confirm line")
	assert_eq(_texts(p)[0], "No - let me think again.", "the confirm line offers No first")
	assert_false(p.armed(), "the confirm line waits for the hands to be off again")
	await _settle(p)
	assert_eq(_focused(p), "No - let me think again.", "and the focus is on No")
	assert_true(p.hint_text().ends_with("B: back"), "B goes back here: %s" % p.hint_text())
	await io.tap(JOY_BUTTON_B)
	assert_true(Quests.dialogue.find_choice("spare") >= 0, "B: back to the first line")
	await _settle(p)
	await io.tap(JOY_BUTTON_DPAD_DOWN)
	await io.hold(JOY_BUTTON_A, int(YieldPrompt.HOLD_S * 1000.0) + 100)
	await _settle(p)
	await io.tap(JOY_BUTTON_DPAD_DOWN)
	assert_eq(_focused(p), "Strike. (There is no taking it back.)", "down to Strike")
	await io.hold(JOY_BUTTON_A, int(YieldPrompt.HOLD_S * 500.0))
	assert_eq(c.yield_decided, "", "let go halfway: nothing")
	assert_eq(p.held_choice(), -1, "the hold ended")
	await io.hold(JOY_BUTTON_A, int(YieldPrompt.HOLD_S * 1000.0) + 100)
	assert_eq(c.yield_decided, "strike", "held to the end: Strike")
	stack.close_all()
	get_tree().paused = false
	await step_ticks(3)
	assert_false(c.entity.is_alive(), "the confirmed strike kills him")
	assert_eq(WorldState.get_flag("boss.corvane.outcome"), "slain", "slain")


func test_answered_on_purpose_with_the_keyboard_and_the_mouse() -> void:
	var h := await _boss(HARROK, "test.harrok")
	var p := await _yield(h)
	await _settle(p)
	assert_true(p.hint_text().begins_with("Hold Enter, or hold the mouse button"), "the keyboard's line: %s" % p.hint_text())
	await io.tap(KEY_DOWN)
	await io.hold(KEY_ENTER, int(YieldPrompt.HOLD_S * 1000.0) + 100)
	assert_true(Quests.dialogue.find_choice("strike") >= 0, "Down, Enter held: the confirm line")
	await _settle(p)
	assert_true(p.hint_text().ends_with("Esc: back"), "Esc goes back here: %s" % p.hint_text())
	await io.tap(KEY_ESCAPE)
	assert_true(Quests.dialogue.find_choice("spare") >= 0, "Esc: back to the first line")
	await _settle(p)
	var spare := p.choice_buttons[0]
	await io.mouse_move(YieldInput.centre_of(spare))
	await io.tap("mouse")
	assert_eq(h.yield_decided, "", "a click on Spare takes nothing")
	await io.hold("mouse", int(YieldPrompt.HOLD_S * 1000.0) + 100)
	assert_eq(h.yield_decided, "spare", "the mouse held on Spare: spared")
	assert_eq(WorldState.get_flag("boss.harrok.outcome"), "spared", "the outcome")
	assert_true(h.entity.is_alive(), "alive")
