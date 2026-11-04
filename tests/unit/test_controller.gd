extends TestSuite
## CombatController: timelines, combo chain, cancel rules, input buffer, costs and cooldowns,
## dodge invulnerability boundaries, block entry, stagger and death.

var c: CombatController
var t := 0


func before_each() -> void:
	var player := Combatant.from_record("player", GameData.get_record("player.giant"), 3.6576)
	c = CombatController.new("player", player)
	for id: String in GameData.ids_of_type("action"):
		c.add_action(GameData.get_action(id))
	c.loadout = {"light": "ability.light_1", "heavy": "ability.heavy_1", "dodge": "action.dodge",
		"block": "action.block", "jump": "action.jump", "slot_1": "ability.heavy_footfall",
		"slot_2": "", "ultimate": ""}
	t = 100
	c.begin_tick(t)


func _advance(n: int) -> void:
	for i in n:
		t += 1
		c.begin_tick(t)


func _stamina() -> float:
	return c.combatant.pools.stamina


func test_light_timeline_and_cost() -> void:
	assert_eq(c.request(&"light"), CombatController.Verdict.ACCEPT, "light accepted")
	assert_eq(c.action_id(), "ability.light_1", "chain starts at light_1")
	assert_near(_stamina(), 92.0, 1e-9, "light costs 8")
	assert_eq(c.phase(), ActionDef.Phase.WINDUP, "windup at tick 0")
	_advance(11)
	assert_eq(c.phase(), ActionDef.Phase.WINDUP, "windup through tick 11 (0.20 s = 12 ticks)")
	_advance(1)
	assert_eq(c.phase(), ActionDef.Phase.ACTIVE, "active from tick 12")
	_advance(8)
	assert_eq(c.phase(), ActionDef.Phase.ACTIVE, "active through tick 20 (0.15 s = 9 ticks)")
	_advance(1)
	assert_eq(c.phase(), ActionDef.Phase.RECOVERY, "recovery from tick 21")
	_advance(17)
	assert_eq(c.state, CombatController.State.ATTACKING, "still recovering at tick 38")
	_advance(1)
	assert_eq(c.state, CombatController.State.LOCOMOTION, "done after 39 ticks (0.65 s)")


func test_three_hit_chain_and_reset() -> void:
	var expected := ["ability.light_1", "ability.light_2", "ability.light_3", "ability.light_1"]
	for i in expected.size():
		assert_eq(c.request(&"light"), CombatController.Verdict.ACCEPT, "chain hit %d accepted" % i)
		assert_eq(c.action_id(), expected[i], "chain position %d" % i)
		_advance(39)
	_advance(40)  # let the chain window lapse
	c.request(&"light")
	assert_eq(c.action_id(), "ability.light_1", "chain restarts after the window")


func test_heavy_cannot_be_cancelled_during_active() -> void:
	c.request(&"heavy")
	assert_near(_stamina(), 78.0, 1e-9, "heavy costs 22")
	_advance(30)  # heavy active starts at tick 30
	assert_eq(c.phase(), ActionDef.Phase.ACTIVE, "heavy active")
	assert_eq(c.request(&"dodge"), CombatController.Verdict.RETRY, "dodge during active strike is only buffered")
	_advance(9)   # buffer window passes while still in the active strike
	assert_eq(c.state, CombatController.State.ATTACKING, "still attacking: no cancel during active")
	assert_near(_stamina(), 78.0, 1e-9, "the expired request spent nothing")
	_advance(3 + 15)  # recovery starts at 42; dodge-cancel opens 0.25 s (15 ticks) in
	assert_eq(c.request(&"dodge"), CombatController.Verdict.ACCEPT, "dodge allowed late in heavy recovery")
	assert_eq(c.state, CombatController.State.DODGING, "now dodging")


func test_input_buffer_expires_after_015s() -> void:
	# Light_1 recovery (where a chained light may cancel in) begins at tick 21.
	c.request(&"light")
	_advance(12)   # tick 12: request 9 ticks before the window -> still live when it opens
	assert_eq(c.request(&"light"), CombatController.Verdict.RETRY, "queued during active")
	_advance(9)
	assert_eq(c.action_id(), "ability.light_2", "queued request consumed at exactly 0.15 s")
	before_each()
	c.request(&"light")
	_advance(11)   # tick 11: 10 ticks before the window -> expires first
	c.request(&"light")
	_advance(10)
	assert_eq(c.action_id(), "ability.light_1", "request older than 0.15 s expired")
	assert_near(_stamina(), 92.0, 1e-9, "expired request spent nothing")


func test_dodge_invulnerability_boundaries() -> void:
	c.request(&"dodge")
	assert_near(_stamina(), 82.0, 1e-9, "dodge costs 18")
	var expected := {0: false, 5: false, 6: true, 12: true, 17: true, 18: false, 30: false}
	var last := 0
	for tick_index: int in [0, 5, 6, 12, 17, 18, 30]:
		_advance(tick_index - last)
		last = tick_index
		assert_eq(c.is_invulnerable(), expected[tick_index], "invulnerable at dodge tick %d" % tick_index)
	_advance(45 - last)
	assert_eq(c.state, CombatController.State.LOCOMOTION, "dodge lasts 0.75 s (45 ticks)")


func test_insufficient_stamina_rejects_without_spending() -> void:
	c.combatant.pools.stamina = 17.0
	var reasons: Array = []
	c.request_rejected.connect(func(_k, _id, reason): reasons.append(reason))
	assert_eq(c.request(&"dodge"), CombatController.Verdict.REJECT, "dodge needs 18")
	assert_near(_stamina(), 17.0, 1e-9, "nothing spent")
	assert_eq(reasons, ["stamina"], "reason reported")
	assert_eq(c.request(&"heavy"), CombatController.Verdict.REJECT, "heavy needs 22")
	assert_eq(c.request(&"light"), CombatController.Verdict.ACCEPT, "light (8) still fits")
	assert_near(_stamina(), 9.0, 1e-9, "light spent exactly 8")


func test_hundred_activations_charge_once_each() -> void:
	var accepted := 0
	var spent_total := 0.0
	var starts: Array[int] = [0]  # lambdas capture primitives by value; use a reference type
	c.action_started.connect(func(a: ActionDef, _i: int): if a.id == "ability.heavy_footfall": starts[0] += 1)
	for i in 100:
		c.combatant.pools.stamina = 100.0
		var verdict := c.request(&"slot", {"slot": 1})
		if verdict == CombatController.Verdict.ACCEPT:
			accepted += 1
		spent_total += 100.0 - _stamina()
		# Spam during the cooldown: rejected, nothing spent, cooldown not restarted.
		for j in 3:
			_advance(1)
			var before := _stamina()
			assert_eq(c.request(&"slot", {"slot": 1}), CombatController.Verdict.REJECT, "spam %d/%d rejected" % [i, j])
			assert_near(_stamina(), before, 1e-9, "spam spent nothing")
		_advance(8 * 60)
	assert_eq(accepted, 100, "100 activations accepted")
	assert_eq(starts[0], 100, "100 AbilityStarted")
	assert_near(spent_total, 2000.0, 1e-6, "exactly 20 stamina per activation")


func test_cooldown_measured_from_acceptance() -> void:
	c.request(&"slot", {"slot": 1})
	assert_near(c.cooldowns.remaining_s("ability.heavy_footfall", t), 8.0, 1e-9, "8 s cooldown")
	_advance(479)
	assert_false(c.cooldowns.is_ready("ability.heavy_footfall", t), "not ready at 7.98 s")
	_advance(1)
	assert_true(c.cooldowns.is_ready("ability.heavy_footfall", t), "ready at 8.00 s")


func test_block_entry_and_parry_window() -> void:
	assert_eq(c.request(&"block"), CombatController.Verdict.ACCEPT, "block accepted")
	assert_near(_stamina(), 95.0, 1e-9, "block entry costs 5")
	assert_eq(c.block_elapsed_ticks(), 0, "window starts on press")
	assert_true(c.parry_available, "one parry window per press")
	c.request(&"block_release")
	_advance(5)
	assert_eq(c.state, CombatController.State.BLOCKING, "a tap still holds the full parry window")
	_advance(7)
	assert_eq(c.state, CombatController.State.LOCOMOTION, "released block ends after the window")
	c.request(&"block")
	_advance(30)
	assert_eq(c.state, CombatController.State.BLOCKING, "held block persists")
	assert_eq(c.request(&"block"), CombatController.Verdict.REJECT, "holding does not reopen the window")
	assert_near(_stamina(), 90.0, 1e-9, "only two entries paid")


func test_stagger_interrupts_without_refund() -> void:
	c.request(&"heavy")
	_advance(10)
	c.apply_stagger(1.0, "test")
	assert_eq(c.state, CombatController.State.STAGGERED, "staggered")
	assert_eq(c.action, null, "heavy interrupted")
	assert_near(_stamina(), 78.0, 1e-9, "no refund")
	assert_eq(c.request(&"light"), CombatController.Verdict.RETRY, "inputs during stagger are buffered")
	_advance(60)
	assert_eq(c.state, CombatController.State.LOCOMOTION, "recovers after 1.0 s")
	assert_true(c.combatant.poise.is_immune(), "1.5 s stagger immunity after recovery")


func test_dead_rejects_everything() -> void:
	c.kill()
	for kind: StringName in [&"light", &"heavy", &"dodge", &"block", &"jump"]:
		assert_eq(c.request(kind), CombatController.Verdict.REJECT, "%s rejected when dead" % kind)
	assert_near(_stamina(), 100.0, 1e-9, "nothing spent")


func test_empty_slot_and_airborne() -> void:
	assert_eq(c.request(&"slot", {"slot": 2}), CombatController.Verdict.REJECT, "empty slot")
	assert_eq(c.last_reject_reason, "empty_slot", "reason")
	assert_eq(c.request(&"ultimate"), CombatController.Verdict.REJECT, "no ultimate equipped")
	c.on_floor = false
	assert_eq(c.request(&"jump"), CombatController.Verdict.REJECT, "no double jump")
	assert_eq(c.request(&"dodge"), CombatController.Verdict.RETRY, "dodge waits for landing")
