extends IntegrationSuite
## M8 gate (F7): the review's own case, in wall-clock time with the prompt's own clock and nothing
## but real input events on the real ScreenStack (no test hooks, so it runs on any version of the
## prompt): from the moment the boss yields, the fight's buttons are mashed - the ability keys 1 and 2
## (also the dialogue's old choice keys) and pad A and B - one tap every 100 ms for 1.5 s. Nothing may
## be decided: before the M8 gate fix, 1/2 confirmed Strike and killed Corvane, and A/B spared him.
## Then every button let go: the prompt arms ARM_S later and waits.

const CORVANE := "res://scenes/enemies/corvane.tscn"
const HARROK := "res://scenes/enemies/harrok.tscn"
const RUNS := [[CORVANE, "test.corvane", [KEY_1, KEY_2]], [CORVANE, "test.corvane", [JOY_BUTTON_A, JOY_BUTTON_B]],
	[HARROK, "test.harrok", [KEY_2, KEY_1]], [HARROK, "test.harrok", [JOY_BUTTON_A, JOY_BUTTON_B]]]
const MASH_MS := 1500
const GAP_MS := 100
## The prompt's arm time (YieldPrompt.ARM_S) and a margin.
const ARM_WAIT_MS := 900

var stack: ScreenStack


func before_each() -> void:
	await super()
	WorldState.clear()
	Quests.end_dialogue()
	var layer := CanvasLayer.new()
	world.add_child(layer)
	stack = ScreenStack.new()
	layer.add_child(stack)


func after_each() -> void:
	Quests.end_dialogue()
	get_tree().paused = false
	await super()


func _tap(code: int) -> void:
	for pressed: bool in [true, false]:
		var e: InputEvent
		if code <= JOY_BUTTON_DPAD_RIGHT:
			var j := InputEventJoypadButton.new()
			j.device = 0
			j.button_index = code as JoyButton
			j.pressed = pressed
			j.pressure = 1.0 if pressed else 0.0
			e = j
		else:
			var k := InputEventKey.new()
			k.keycode = code as Key
			k.physical_keycode = code as Key
			k.pressed = pressed
			e = k
		Input.parse_input_event(e)
		await get_tree().process_frame


func test_mashing_from_the_yield_decides_nothing() -> void:
	spawn_player(Vector3(0, 0.05, 24), 0.0)
	for run: Array in RUNS:
		var boss := (load(str(run[0])) as PackedScene).instantiate() as EnemyActor
		boss.entity_id = str(run[1])
		boss.ai_enabled = false
		boss.position = Vector3(0, 0.05, 0)
		world.add_child(boss)
		await step_ticks(2)
		boss.p34_yield("health")
		var pattern: Array = run[2]
		var start := Time.get_ticks_msec()
		var taps := 0
		while Time.get_ticks_msec() - start < MASH_MS and boss.yield_decided == "":
			await _tap(int(pattern[taps % pattern.size()]))
			taps += 1
			OS.delay_msec(GAP_MS)
		var what := "%s, %s mashed for %.1f s (%d taps)" % [run[1], pattern, MASH_MS / 1000.0, taps]
		var prompt := stack.top() as YieldPrompt
		assert_true(prompt != null, "%s: the prompt is open" % what)
		assert_eq(boss.yield_decided, "", "%s: nothing decided" % what)
		var flag := str((boss.record.get("boss_outcome", {}) as Dictionary).get("flag", ""))
		assert_false(WorldState.has_flag(flag), "%s: no outcome written" % what)
		if prompt != null:
			assert_false(prompt.armed(), "%s: never armed" % what)
			OS.delay_msec(ARM_WAIT_MS)
			await get_tree().process_frame
			await get_tree().process_frame
			assert_true(prompt.armed(), "%s: armed once the hands were off" % run[1])
			assert_eq(boss.yield_decided, "", "%s: and still waiting" % run[1])
		stack.close_all()
		get_tree().paused = false
		Quests.end_dialogue()
		boss.queue_free()
		await step_ticks(2)
