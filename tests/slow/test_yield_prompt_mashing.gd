extends IntegrationSuite
## M8 gate (F7): the yield prompt against every fight input mashed, for Corvane (Strike kills) and
## Harrok (Strike: he rises and fights to the death), through real input events on the real
## ScreenStack (tests/support/yield_input.gd; the default tier's test_yield_prompt_input.gd holds the
## lean cases). Every run checks that nothing is decided, Strike above all:
##   * the ability keys 1-4 in all 24 orders, the face buttons A/B/X/Y in all 24 orders, the D-pad
##     with A and B, the shoulders and triggers, the sticks, and the mouse's left button over each
##     choice - from the moment the boss yields (the prompt never arms) and again on an armed prompt,
##     on the first line and on the confirm line (taps never take a deciding choice: it is held);
##   * bursts with pauses long enough to arm it (move-and-press pairs, a second apart);
##   * a key, a pad button, the mouse button or a stick already held as it opens: never armed while
##     held, armed ARM_S after the last let go.
## The review's own mashes in wall-clock time are tests/slow/test_yield_prompt_wall_clock.gd.

const CORVANE := "res://scenes/enemies/corvane.tscn"
const HARROK := "res://scenes/enemies/harrok.tscn"
const BOSSES := [[CORVANE, "test.corvane"], [HARROK, "test.harrok"]]
## Fake-clock length of each mashed pattern.
const MASH_MS := 1200

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


static func permutations(items: Array) -> Array:
	if items.size() <= 1:
		return [items.duplicate()]
	var out: Array = []
	for i in items.size():
		var rest := items.duplicate()
		var head: Variant = rest.pop_at(i)
		for p: Array in permutations(rest):
			out.append([head] + p)
	return out


func _spawn(path: String, id: String) -> EnemyActor:
	var e := (load(path) as PackedScene).instantiate() as EnemyActor
	e.entity_id = id
	e.ai_enabled = false
	e.position = Vector3(0, 0.05, 0)
	world.add_child(e)
	await step_ticks(2)
	return e


func _prompt_for(boss: EnemyActor) -> YieldPrompt:
	boss.p34_yield("health")
	await io.frame()
	await io.frame()
	return stack.top() as YieldPrompt


## Nothing decided, the outcome unwritten, the boss alive (and, with `unarmed`, never armed).
func _undecided(boss: EnemyActor, p: YieldPrompt, what: String, unarmed := false) -> void:
	assert_eq(boss.yield_decided, "", "%s: nothing decided" % what)
	assert_true(boss.entity.is_alive() and boss.yielded, "%s: still yielded and alive" % what)
	var flag := str(boss.record.get("boss_outcome", {}).get("flag", ""))
	assert_false(WorldState.has_flag(flag), "%s: no outcome written" % what)
	if unarmed:
		assert_false(p.armed(), "%s: never armed" % what)


func _settle(p: YieldPrompt) -> void:
	io.release_all()
	await io.wait_ms(int(YieldPrompt.ARM_S * 1000.0) + 100)


## The fight's taps for one boss: from the yield on (unarmed), then on the armed first line and on the
## armed confirm line.
func test_every_order_of_the_fight_buttons_decides_nothing() -> void:
	spawn_player(Vector3(0, 0.05, 24), 0.0)
	var keys := permutations([KEY_1, KEY_2, KEY_3, KEY_4])
	var faces := permutations([JOY_BUTTON_A, JOY_BUTTON_B, JOY_BUTTON_X, JOY_BUTTON_Y])
	var others: Array = [[JOY_BUTTON_DPAD_DOWN, JOY_BUTTON_A], [JOY_BUTTON_DPAD_UP, JOY_BUTTON_A, JOY_BUTTON_B],
		[JOY_BUTTON_DPAD_LEFT, JOY_BUTTON_DPAD_RIGHT, JOY_BUTTON_A], [JOY_BUTTON_RIGHT_SHOULDER, "rt"],
		[JOY_BUTTON_LEFT_SHOULDER, "lt", JOY_BUTTON_A], ["stick_down", JOY_BUTTON_A], ["stick_up", JOY_BUTTON_A],
		[KEY_SPACE, KEY_F, KEY_E, KEY_R, KEY_TAB], [KEY_DOWN, KEY_ENTER], [KEY_5, KEY_6, KEY_7, KEY_8]]
	for b: Array in BOSSES:
		var boss := await _spawn(b[0], b[1])
		var p := await _prompt_for(boss)
		assert_true(p != null, "%s: the prompt opens" % b[1])
		var n := 0
		for pattern: Array in keys + faces + others:
			n += await io.mash(pattern, MASH_MS)
			_undecided(boss, p, "%s, unarmed, %s" % [b[1], pattern], true)
		# The mouse's left button over each choice.
		for i in p.choice_buttons.size():
			await io.mouse_move(YieldInput.centre_of(p.choice_buttons[i]))
			n += await io.mash(["mouse"], MASH_MS)
			_undecided(boss, p, "%s, unarmed, clicks on choice %d" % [b[1], i + 1], true)
		# Armed: on the first line, then on the confirm line - taps take no deciding choice.
		for line in 2:
			for pattern: Array in keys + faces + others:
				await _settle(p)
				assert_true(p.armed(), "%s: armed after the hands are off" % b[1])
				n += await io.mash(pattern, MASH_MS)
				_undecided(boss, p, "%s, armed line %d, %s" % [b[1], line + 1, pattern])
				if line == 1 and Quests.dialogue.find_choice("strike") < 0:
					await _to_confirm_line(p)
			for i in p.choice_buttons.size():
				await _settle(p)
				await io.mouse_move(YieldInput.centre_of(p.choice_buttons[i]))
				n += await io.mash(["mouse"], MASH_MS)
				_undecided(boss, p, "%s, armed line %d, clicks on choice %d" % [b[1], line + 1, i + 1])
			if line == 0:
				await _to_confirm_line(p)
				assert_true(Quests.dialogue.find_choice("strike") >= 0, "%s: on the confirm line" % b[1])
		print("    %s: %d taps, nothing decided" % [b[1], n])
		stack.close_all()
		Quests.end_dialogue()
		boss.queue_free()
		await step_ticks(2)


## Deliberately to the confirm line: let go, D-pad down to "Strike him down.", hold A.
func _to_confirm_line(p: YieldPrompt) -> void:
	if Quests.dialogue.find_choice("strike") >= 0:
		return
	await _settle(p)
	if Quests.dialogue.find_choice("spare") < 0:
		return
	var f := UiNav.focus_owner(p)
	if not (f is Button and (f as Button).text == "Strike him down."):
		await io.tap(JOY_BUTTON_DPAD_DOWN)
	await io.hold(JOY_BUTTON_A, int(YieldPrompt.HOLD_S * 1000.0) + 100)


## Move-and-press bursts a second apart (each pause arms the line): taps still decide nothing.
func test_bursts_with_pauses_decide_nothing() -> void:
	spawn_player(Vector3(0, 0.05, 24), 0.0)
	var bursts: Array = [["stick_up", JOY_BUTTON_A], ["stick_down", JOY_BUTTON_A], [JOY_BUTTON_DPAD_DOWN, JOY_BUTTON_A],
		[JOY_BUTTON_DPAD_UP, JOY_BUTTON_A, JOY_BUTTON_A], [KEY_DOWN, KEY_ENTER], [KEY_UP, KEY_SPACE], [KEY_2, KEY_1],
		["mouse", "mouse"]]
	for b: Array in BOSSES:
		var boss := await _spawn(b[0], b[1])
		var p := await _prompt_for(boss)
		for burst: Array in bursts:
			for i in 6:
				for t: Variant in burst:
					await io.tap(t)
				io.release_all()
				await io.wait_ms(1000)
			_undecided(boss, p, "%s, bursts of %s" % [b[1], burst])
		stack.close_all()
		Quests.end_dialogue()
		boss.queue_free()
		await step_ticks(2)


## A button already held as the prompt opens keeps it unarmed until ARM_S after the last let go.
func test_buttons_held_as_it_opens() -> void:
	spawn_player(Vector3(0, 0.05, 24), 0.0)
	var holds: Array = [KEY_1, JOY_BUTTON_RIGHT_SHOULDER, "mouse", "stick", "rt"]
	for b: Array in BOSSES:
		for what: Variant in holds:
			var boss := await _spawn(b[0], b[1])
			await _press(what)
			var p := await _prompt_for(boss)
			await io.wait_ms(2500)
			assert_false(p.armed(), "%s: %s held 2.5 s: not armed" % [b[1], what])
			await _let_go(what)
			await io.wait_ms(int(YieldPrompt.ARM_S * 1000.0) - 150)
			assert_false(p.armed(), "%s: %s let go %.2f s ago: not yet" % [b[1], what, YieldPrompt.ARM_S - 0.15])
			await io.wait_ms(250)
			assert_true(p.armed(), "%s: %s let go %.2f s ago: armed" % [b[1], what, YieldPrompt.ARM_S + 0.1])
			_undecided(boss, p, "%s, %s held as it opened" % [b[1], what])
			stack.close_all()
			Quests.end_dialogue()
			boss.queue_free()
			await step_ticks(2)


func _press(what: Variant) -> void:
	match str(what):
		"mouse":
			await io.mouse_down()
		"stick":
			await io.axis(JOY_AXIS_LEFT_Y, -1.0)
		"rt":
			await io.axis(JOY_AXIS_TRIGGER_RIGHT, 1.0)
		_:
			if int(what) <= JOY_BUTTON_DPAD_RIGHT:
				await io.pad_down(what)
			else:
				await io.key_down(what)


func _let_go(what: Variant) -> void:
	match str(what):
		"mouse":
			await io.mouse_up()
		"stick":
			await io.axis(JOY_AXIS_LEFT_Y, 0.0)
		"rt":
			await io.axis(JOY_AXIS_TRIGGER_RIGHT, 0.0)
		_:
			if int(what) <= JOY_BUTTON_DPAD_RIGHT:
				await io.pad_up(what)
			else:
				await io.key_up(what)
