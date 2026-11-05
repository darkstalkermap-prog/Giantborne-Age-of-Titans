extends IntegrationSuite
## Dexterity (spec §9, plan §3.14): at Dexterity 40 the real giant's light and heavy recovery is x0.85
## (light 18 -> 15 ticks, heavy 33 -> 28), while the windup and active ticks, the 0.20 s parry
## window, the dodge i-frames (0.10-0.30 s) and the 0.75 s dodge are exactly those of Dexterity 10.
## Attributes go through the giant's progression (apply_state), as a loaded character's would.

var phase_log: Array = []


func _player_with_dexterity(dex: int, pos := Vector3(0, 0.05, 0)) -> GiantPlayer:
	var p := spawn_player(pos)
	await TestWait.until(self, func() -> bool: return p.is_on_floor(), 30)
	await step_ticks(1)
	var attrs := Progression.attributes_of({"dexterity": dex})
	p.apply_character_state({"attributes": attrs})
	return p


func _on_phase(action: ActionDef, _instance: int, phase: int) -> void:
	phase_log.append([action.id, Sim.tick, phase])


func _on_ended(action: ActionDef, _instance: int, _interrupted: bool) -> void:
	phase_log.append([action.id, Sim.tick, -1])


## Ticks spent in WINDUP, ACTIVE and RECOVERY by the next run of `kind` ([windup, active, recovery]).
func _phase_ticks(p: GiantPlayer, kind: StringName) -> Array:
	phase_log.clear()
	p.controller.phase_entered.connect(_on_phase)
	p.controller.action_ended.connect(_on_ended)
	assert_eq(p.controller.request(kind), CombatController.Verdict.ACCEPT, "%s accepted" % kind)
	await TestWait.until(self, func() -> bool: return p.controller.state == CombatController.State.LOCOMOTION, 200)
	p.controller.phase_entered.disconnect(_on_phase)
	p.controller.action_ended.disconnect(_on_ended)
	var starts := {}
	var end_tick := -1
	for e: Array in phase_log:
		if int(e[2]) == -1:
			end_tick = int(e[1])
		elif not starts.has(int(e[2])):
			starts[int(e[2])] = int(e[1])
	var w := int(starts.get(ActionDef.Phase.WINDUP, -1))
	var a := int(starts.get(ActionDef.Phase.ACTIVE, -1))
	var r := int(starts.get(ActionDef.Phase.RECOVERY, -1))
	await step_ticks(30)
	return [a - w, r - a, end_tick - r]


func test_dexterity_shortens_attack_recovery_only() -> void:
	var p10 := await _player_with_dexterity(10)
	assert_near(p10.controller.recovery_scale, 1.0, 1e-9, "Dexterity 10: no change")
	var light10: Array = await _phase_ticks(p10, &"light")
	var heavy10: Array = await _phase_ticks(p10, &"heavy")
	assert_eq(light10, [12, 9, 18], "light at Dexterity 10: 12 / 9 / 18 ticks")
	assert_eq(heavy10, [30, 12, 33], "heavy at Dexterity 10: 30 / 12 / 33 ticks")
	p10.queue_free()
	await step_ticks(2)
	var p40 := await _player_with_dexterity(40)
	assert_near(p40.controller.recovery_scale, 0.85, 1e-9, "Dexterity 40: recovery x0.85 (the 15% cap)")
	var light40: Array = await _phase_ticks(p40, &"light")
	var heavy40: Array = await _phase_ticks(p40, &"heavy")
	assert_eq([light40[0], light40[1]], [light10[0], light10[1]], "the light's windup and active are unchanged")
	assert_eq(light40[2], roundi(18 * 0.85), "its recovery is x0.85 (18 -> 15)")
	assert_eq([heavy40[0], heavy40[1]], [heavy10[0], heavy10[1]], "the heavy's windup and active are unchanged")
	assert_eq(heavy40[2], roundi(33 * 0.85), "its recovery is x0.85 (33 -> 28)")
	p40.queue_free()
	await step_ticks(2)
	var p60 := await _player_with_dexterity(60)
	assert_near(p60.controller.recovery_scale, 0.85, 1e-9, "Dexterity 60 is capped at x0.85 too")


## The 0.20 s parry window: with the block held, a hit resolved 11 ticks after the press is parried
## and one resolved 12 ticks after it is blocked; the dodge's i-frames run 12 of its 45 ticks - all
## identical at Dexterity 10 and 40.
func test_parry_window_and_dodge_are_unchanged_by_dexterity() -> void:
	var results := {}
	for dex: int in [10, 40]:
		var p := await _player_with_dexterity(dex)
		var outcomes: Array = []
		for delay: int in [10, 11]:
			p.router.set_injected_hold(&"block", true)
			assert_eq(p.controller.request(&"block"), CombatController.Verdict.ACCEPT, "block (Dexterity %d)" % dex)
			await step_ticks(delay)
			queue_hit("tester", "player", p.global_position + Vector3(0, 1, -3), 10.0)
			await step_ticks(1)   # resolved delay + 1 ticks after the press
			var on := hits_on("player")
			outcomes.append(on.back().outcome if not on.is_empty() else -1)
			p.router.set_injected_hold(&"block", false)
			p.controller.request(&"block_release")
			await step_ticks(30)
		var inv: Array = []
		var dodge_ticks := 0
		assert_eq(p.controller.request(&"dodge"), CombatController.Verdict.ACCEPT, "dodge (Dexterity %d)" % dex)
		for i in 60:
			if p.controller.state == CombatController.State.DODGING:
				dodge_ticks += 1
			inv.append(p.controller.is_invulnerable())
			await step_ticks(1)
		results[dex] = {"outcomes": outcomes, "first_iframe": inv.find(true), "last_iframe": inv.rfind(true),
			"dodge_ticks": dodge_ticks}
		hits.clear()
		p.queue_free()
		await step_ticks(2)
	assert_eq(results[10].outcomes, [HitResult.Outcome.PARRIED, HitResult.Outcome.BLOCKED],
		"Dexterity 10: parried 11 ticks into the block, blocked at 12 (the 0.20 s window)")
	assert_eq(results[40], results[10], "Dexterity 40: the same parry window, i-frames and dodge length (%s)" % results[40])
	assert_eq(int(results[10].dodge_ticks), 45, "the dodge lasts 0.75 s")
	assert_eq(int(results[10].last_iframe) - int(results[10].first_iframe) + 1, 12, "twelve i-frame ticks (0.10-0.30 s)")
