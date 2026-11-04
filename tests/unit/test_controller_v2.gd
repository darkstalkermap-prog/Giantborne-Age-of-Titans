extends TestSuite
## P01 CombatController additions: precheck, preview_reason (one code path with request),
## level gating, recovery_scale, phase_entered, GRABBED, EXECUTING, force_action and slows.

const V := CombatController.Verdict
const S := CombatController.State

var c: CombatController
var t := 0
var reasons: Array = []
var phases: Array = []
var ended: Array = []
var started: Array = []


func before_each() -> void:
	var player := Combatant.from_record("player", GameData.get_record("player.giant"), 3.6576)
	c = CombatController.new("player", player)
	for id: String in GameData.ids_of_type("action"):
		c.add_action(GameData.get_action(id))
	c.loadout = {"light": "ability.light_1", "heavy": "ability.heavy_1", "dodge": "action.dodge",
		"block": "action.block", "jump": "action.jump", "slot_1": "ability.heavy_footfall",
		"slot_2": "", "ultimate": ""}
	reasons = []
	phases = []
	ended = []
	started = []
	c.request_rejected.connect(_on_rejected)
	c.phase_entered.connect(_on_phase)
	c.action_ended.connect(_on_ended)
	c.action_started.connect(_on_started)
	t = 100
	c.begin_tick(t)


func _on_rejected(_kind: StringName, _id: String, reason: String) -> void:
	reasons.append(reason)


func _on_phase(a: ActionDef, _instance: int, p: int) -> void:
	phases.append([a.id, t, p])


func _on_ended(a: ActionDef, _instance: int, interrupted: bool) -> void:
	ended.append([a.id, interrupted])


func _on_started(a: ActionDef, _instance: int) -> void:
	started.append(a.id)


func _advance(n: int) -> void:
	for i in n:
		t += 1
		c.begin_tick(t)


func _stamina() -> float:
	return c.combatant.pools.stamina


func _ability(id: String, extra: Dictionary = {}) -> ActionDef:
	var d := {"id": id, "type": "action", "kind": "ability", "power": 0, "damage_type": "physical",
		"ability_multiplier": 1.0, "stamina_cost": 5, "cooldown_s": 0, "windup_s": 0.1, "active_s": 0.05,
		"recovery_s": 0.2, "poise_damage": 0, "max_hits_per_target": 1, "tags": ["Ability"], "hit_shape": "none"}
	d.merge(extra, true)
	var a := ActionDef.from_dict(d)
	c.add_action(a)
	return a


# --------------------------------------------------------------------------- precheck

func test_precheck_rejection_spends_nothing() -> void:
	var calls: Array[int] = [0]
	var no_target := func() -> String:
		calls[0] += 1
		return "no_target"
	assert_eq(c.request(&"heavy", {"precheck": no_target}), V.REJECT, "precheck rejects")
	assert_eq(reasons, ["no_target"], "request_rejected carries the precheck's reason")
	assert_eq(c.last_reject_reason, "no_target", "last reject reason")
	assert_near(_stamina(), 100.0, 1e-9, "no stamina spent")
	assert_eq(c.state, S.LOCOMOTION, "no action started")
	assert_eq(started, [], "no action_started")
	assert_eq(c.request(&"slot", {"slot": 1, "precheck": no_target}), V.REJECT, "ability precheck rejects")
	assert_true(c.cooldowns.is_ready("ability.heavy_footfall", t), "no cooldown started")
	assert_eq(calls[0], 2, "evaluated once per request")
	assert_eq(c.request(&"slot", {"slot": 1, "precheck": func() -> String: return ""}), V.ACCEPT, "\"\" accepts")
	assert_near(_stamina(), 80.0, 1e-9, "and pays once")


func test_precheck_runs_last() -> void:
	var calls: Array[int] = [0]
	var counting := func() -> String:
		calls[0] += 1
		return ""
	c.combatant.pools.stamina = 0.0
	assert_eq(c.request(&"heavy", {"precheck": counting}), V.REJECT, "rejected for stamina")
	assert_eq(reasons, ["stamina"], "earlier checks win")
	assert_eq(calls[0], 0, "precheck not evaluated when an earlier check fails")
	c.combatant.pools.stamina = 100.0
	c.request(&"heavy")
	assert_eq(c.request(&"light", {"precheck": counting}), V.RETRY, "busy -> buffered")
	assert_eq(calls[0], 0, "precheck not evaluated while the request waits")


func test_buffered_request_reruns_precheck() -> void:
	var calls: Array[int] = [0]
	var ok := func() -> String:
		calls[0] += 1
		return ""
	c.request(&"light")
	_advance(12)   # light_1 active strike
	assert_eq(c.request(&"light", {"precheck": ok}), V.RETRY, "queued during the active strike")
	assert_eq(calls[0], 0, "not evaluated yet")
	_advance(9)    # recovery opens the cancel window; the buffer is retried
	assert_eq(calls[0], 1, "the buffered request re-ran its precheck")
	assert_eq(c.action_id(), "ability.light_2", "and was accepted")
	before_each()
	var refuse := func() -> String: return "no_target"
	c.request(&"light")
	_advance(12)
	c.request(&"light", {"precheck": refuse})
	_advance(9)
	assert_eq(reasons, ["no_target"], "a buffered request whose precheck fails is rejected")
	assert_eq(c.action_id(), "ability.light_1", "the chain did not advance")
	assert_near(_stamina(), 92.0, 1e-9, "only the first light was paid")
	assert_false(c.buffer.has_pending(), "and the buffer is cleared")


# --------------------------------------------------------------------------- preview_reason

## preview_reason now, then the real request; both must give the same reason code.
func _check_preview(kind: StringName, params: Dictionary, expected: String, label: String) -> void:
	var stamina := _stamina()
	var buffered := c.buffer.has_pending()
	var preview := c.preview_reason(kind, params)
	assert_near(_stamina(), stamina, 1e-9, "%s: preview spends nothing" % label)
	assert_eq(c.buffer.has_pending(), buffered, "%s: preview buffers nothing" % label)
	var before := reasons.size()
	var v := c.request(kind, params)
	var actual := ""
	match v:
		V.RETRY:
			actual = "busy"
		V.REJECT:
			actual = str(reasons.back()) if reasons.size() > before else "<no rejection emitted>"
	assert_eq(preview, actual, "%s: preview matches request" % label)
	assert_eq(preview, expected, "%s: reason code" % label)


func test_preview_reason_matches_request_for_every_reason() -> void:
	_check_preview(&"light", {}, "", "accept")
	before_each()
	_check_preview(&"slot", {"slot": 2}, "empty_slot", "empty slot")
	_check_preview(&"ultimate", {}, "empty_slot", "no ultimate")
	_check_preview(&"attack", {"action_id": "ability.nope"}, "unknown_action", "unknown action")
	var hurl := _ability("ability.test_hurl", {"unlock_stage": 2})
	c.loadout["slot_3"] = hurl.id
	_check_preview(&"slot", {"slot": 3}, "locked", "stage locked")
	var bolt := _ability("ability.test_bolt", {"unlock_level": 3})
	c.loadout["slot_4"] = bolt.id
	c.level = 2
	_check_preview(&"slot", {"slot": 4}, "level_locked", "level locked")
	var cast := _ability("ability.test_cast", {"essence_cost": 30})
	c.loadout["slot_5"] = cast.id
	c.combatant.pools.essence = 10.0
	_check_preview(&"slot", {"slot": 5}, "essence", "essence")
	var ult := _ability("ability.test_ult", {"kind": "ultimate", "fury_cost": 100})
	c.loadout["ultimate"] = ult.id
	_check_preview(&"ultimate", {}, "fury", "fury")
	_check_preview(&"heavy", {"precheck": func() -> String: return "no_target"}, "no_target", "precheck")
	c.combatant.pools.stamina = 3.0
	_check_preview(&"heavy", {}, "stamina", "stamina")
	before_each()
	c.on_floor = false
	_check_preview(&"jump", {}, "airborne", "airborne jump")
	_check_preview(&"dodge", {}, "busy", "airborne dodge waits (buffered)")
	before_each()
	_check_preview(&"slot", {"slot": 1}, "", "footfall accepted")
	_advance(1)
	_check_preview(&"slot", {"slot": 1}, "cooldown", "cooldown")
	_check_preview(&"light", {}, "busy", "busy while casting")
	before_each()
	_check_preview(&"block", {}, "", "block")
	_check_preview(&"block", {}, "already_blocking", "already blocking")
	_check_preview(&"block_release", {}, "", "block release")
	before_each()
	c.kill()
	_check_preview(&"light", {}, "dead", "dead")


# --------------------------------------------------------------------------- level gating

func test_level_gating_and_exemption() -> void:
	var bolt := _ability("ability.test_bolt", {"unlock_level": 3})
	c.loadout["slot_2"] = bolt.id
	assert_eq(c.level, 99, "level 99 = gating off (sandbox, tests)")
	assert_eq(c.request(&"slot", {"slot": 2}), V.ACCEPT, "no gating at level 99")
	before_each()
	bolt = _ability("ability.test_bolt", {"unlock_level": 3})
	c.loadout["slot_2"] = bolt.id
	c.level = 2
	assert_eq(c.request(&"slot", {"slot": 2}), V.REJECT, "below its level")
	assert_eq(reasons, ["level_locked"], "reason level_locked")
	assert_near(_stamina(), 100.0, 1e-9, "nothing spent")
	c.level_exempt[bolt.id] = true
	assert_eq(c.request(&"slot", {"slot": 2}), V.ACCEPT, "a level_exempt id is accepted below its level")
	before_each()
	bolt = _ability("ability.test_bolt", {"unlock_level": 3})
	c.loadout["slot_2"] = bolt.id
	c.level = 3
	assert_eq(c.request(&"slot", {"slot": 2}), V.ACCEPT, "accepted at its level")


func test_growth_stage_lock() -> void:
	var hurl := _ability("ability.test_hurl", {"unlock_stage": 2})
	c.loadout["slot_2"] = hurl.id
	assert_eq(c.request(&"slot", {"slot": 2}), V.REJECT, "stage 1 cannot hurl")
	assert_eq(reasons, ["locked"], "reason locked")
	c.set_growth_stage(2)
	assert_eq(c.growth_stage, 2, "set_growth_stage")
	assert_eq(c.request(&"slot", {"slot": 2}), V.ACCEPT, "stage 2 can")


# --------------------------------------------------------------------------- timing

## Ticks from acceptance until the controller is back in LOCOMOTION.
func _length_of(kind: StringName, params: Dictionary = {}) -> int:
	assert_eq(c.request(kind, params), V.ACCEPT, "%s accepted" % kind)
	var n := 0
	while c.state != S.LOCOMOTION and n < 400:
		_advance(1)
		n += 1
	return n


func test_recovery_scale_shortens_attack_recovery_only() -> void:
	assert_eq(_length_of(&"light"), 39, "light: 12 + 9 + 18 ticks")
	before_each()
	c.recovery_scale = 0.85
	assert_eq(_length_of(&"light"), 12 + 9 + 15, "light recovery 18 -> round(15.3) = 15")
	var light_phases := phases.duplicate()
	assert_eq(light_phases, [["ability.light_1", 100, ActionDef.Phase.WINDUP],
		["ability.light_1", 112, ActionDef.Phase.ACTIVE], ["ability.light_1", 121, ActionDef.Phase.RECOVERY]],
		"windup (12) and active (9) unchanged")
	assert_eq(_length_of(&"heavy"), 30 + 12 + 28, "heavy recovery 33 -> round(28.05) = 28")
	before_each()
	c.recovery_scale = 0.85
	assert_eq(_length_of(&"dodge"), 45, "dodge timing unchanged")
	before_each()
	c.recovery_scale = 0.85
	c.request(&"dodge")
	var inv: Array = []
	for i in 20:
		inv.append(c.is_invulnerable())
		_advance(1)
	assert_eq(inv.find(true), 6, "i-frames still start at tick 6")
	assert_eq(inv.rfind(true), 17, "and end after tick 17")
	before_each()
	c.recovery_scale = 0.85
	c.request(&"block")
	c.request(&"block_release")
	_advance(11)
	assert_eq(c.state, S.BLOCKING, "a tapped block still holds its 12-tick parry window")
	_advance(1)
	assert_eq(c.state, S.LOCOMOTION, "and ends on time")


func test_phase_entered_on_accept_and_each_change() -> void:
	c.request(&"light")
	_advance(39)
	assert_eq(phases, [["ability.light_1", 100, ActionDef.Phase.WINDUP],
		["ability.light_1", 112, ActionDef.Phase.ACTIVE], ["ability.light_1", 121, ActionDef.Phase.RECOVERY]],
		"WINDUP on accept, ACTIVE, RECOVERY; nothing when it finishes")
	before_each()
	c.request(&"dodge")
	_advance(45)
	assert_eq(phases, [["action.dodge", 100, ActionDef.Phase.ACTIVE], ["action.dodge", 127, ActionDef.Phase.RECOVERY]],
		"a 0-windup action enters ACTIVE on accept")
	before_each()
	c.request(&"block")
	c.request(&"jump")
	assert_eq(phases, [], "block and jump have no timeline")


# --------------------------------------------------------------------------- GRABBED

func test_grabbed_state() -> void:
	assert_true(c.enter_grabbed("valley.forest.ogre"), "grabbed from locomotion")
	assert_eq(c.state, S.GRABBED, "GRABBED")
	assert_eq(c.held_by, "valley.forest.ogre", "held_by")
	assert_true(c.is_committed(), "committed")
	assert_near(c.move_speed_multiplier(), 0.0, 1e-9, "no movement while held")
	assert_false(c.apply_stagger(1.0, "test"), "apply_stagger returns false while GRABBED")
	assert_eq(c.state, S.GRABBED, "still GRABBED")
	assert_eq(c.request(&"light"), V.RETRY, "inputs wait while held")
	_advance(30)
	assert_eq(c.state, S.GRABBED, "no timeline advances while GRABBED")
	assert_false(c.enter_grabbed("other"), "cannot be grabbed twice")
	c.release_grabbed("thrown", 0.6)
	assert_eq(c.state, S.STAGGERED, "release -> STAGGERED")
	assert_eq(c.held_by, "", "held_by cleared")
	assert_eq(c.stagger_ticks_left, 36, "0.6 s recovery")
	_advance(36)
	assert_eq(c.state, S.LOCOMOTION, "then free")
	c.release_grabbed("thrown", 0.6)
	assert_eq(c.state, S.LOCOMOTION, "release is ignored unless GRABBED")


func test_grab_interrupts_without_refund_and_kill_releases() -> void:
	c.request(&"heavy")
	_advance(5)
	assert_true(c.enter_grabbed("holder"), "grabbed out of an attack")
	assert_eq(c.action, null, "the attack is interrupted")
	assert_eq(ended, [["ability.heavy_1", true]], "action_ended(interrupted)")
	assert_near(_stamina(), 78.0, 1e-9, "no refund")
	assert_false(c.buffer.has_pending(), "buffer cleared")
	before_each()
	c.apply_stagger(1.0, "poise_broken")
	assert_true(c.enter_grabbed("holder"), "a staggered target can be grabbed")
	assert_eq(c.stagger_ticks_left, 0, "the stagger ends")
	before_each()
	c.request(&"block")
	assert_true(c.enter_grabbed("holder"), "a blocking target can be grabbed")
	assert_false(c.parry_available, "the guard drops")
	before_each()
	c.request(&"dodge")
	assert_false(c.enter_grabbed("holder"), "a dodging target cannot be grabbed")
	before_each()
	c.enter_grabbed("holder")
	c.kill()
	assert_eq(c.state, S.DEAD, "kill from GRABBED -> DEAD")
	assert_eq(c.held_by, "", "and clears held_by")
	assert_false(c.enter_grabbed("holder"), "the dead cannot be grabbed")
	before_each()
	c.enter_grabbed("holder")
	c.release_grabbed("dropped", 0.0)
	assert_eq(c.state, S.LOCOMOTION, "a release with no recovery frees at once")


# --------------------------------------------------------------------------- EXECUTING

func test_executing_timeline() -> void:
	var grab := _ability("ability.test_grab", {"hit_shape": "grab", "windup_s": 0.2, "active_s": 0.1,
		"recovery_s": 0.3, "stamina_cost": 10,
		"movement": {"windup_speed_mult": 0.5, "active_speed_mult": 0.0, "recovery_speed_mult": 0.25}})
	c.loadout["slot_3"] = grab.id
	assert_eq(c.request(&"slot", {"slot": 3}), V.ACCEPT, "grab accepted")
	assert_eq(c.state, S.EXECUTING, "grab actions run in EXECUTING")
	assert_true(c.is_committed(), "committed")
	assert_false(c.stamina_regen_allowed(false), "stamina regeneration pauses")
	assert_true(c.can_rotate(), "may rotate during the windup")
	assert_near(c.move_speed_multiplier(), 0.5, 1e-9, "windup move multiplier")
	_advance(12)
	assert_eq(c.phase(), ActionDef.Phase.ACTIVE, "advances like CASTING")
	assert_false(c.can_rotate(), "no rotation once active")
	assert_near(c.move_speed_multiplier(), 0.0, 1e-9, "active move multiplier")
	_advance(6)
	assert_eq(c.phase(), ActionDef.Phase.RECOVERY, "recovery")
	assert_near(c.move_speed_multiplier(), 0.25, 1e-9, "recovery move multiplier")
	_advance(17)
	assert_eq(c.state, S.EXECUTING, "still executing at tick 35")
	_advance(1)
	assert_eq(c.state, S.LOCOMOTION, "back to LOCOMOTION when finished (36 ticks)")
	assert_eq(phases.size(), 3, "phase_entered for WINDUP, ACTIVE and RECOVERY")
	assert_eq(ended, [["ability.test_grab", false]], "finished, not interrupted")
	before_each()
	grab = _ability("ability.test_grab", {"hit_shape": "grab"})
	c.loadout["slot_3"] = grab.id
	c.request(&"slot", {"slot": 3})
	assert_true(c.apply_stagger(1.0, "hit"), "a hard stagger interrupts a grab")
	assert_eq(ended, [["ability.test_grab", true]], "interrupted")


# --------------------------------------------------------------------------- force_action

func test_force_action_skips_costs() -> void:
	var recover := _ability("ability.test_wall_recover", {"kind": "enemy_attack", "windup_s": 0.0,
		"active_s": 0.05, "recovery_s": 2.5, "stamina_cost": 30, "cooldown_s": 5})
	c.request(&"light")
	_advance(5)
	c.combatant.pools.stamina = 0.0
	c.force_action(recover)
	assert_eq(ended, [["ability.light_1", false]], "the current action finishes (not interrupted)")
	assert_eq(c.action_id(), "ability.test_wall_recover", "the forced action runs")
	assert_eq(c.state, S.ATTACKING, "in its kind's state")
	assert_eq(started.back(), "ability.test_wall_recover", "action_started emitted")
	assert_near(_stamina(), 0.0, 1e-9, "no stamina cost")
	assert_true(c.cooldowns.is_ready(recover.id, t), "no cooldown started")
	before_each()
	var roar := _ability("ability.test_phase_roar", {"windup_s": 1.5, "stamina_cost": 50})
	c.apply_stagger(1.0, "poise_broken")
	c.force_action(roar)
	assert_eq(c.state, S.CASTING, "a forced cast leaves a stagger")
	assert_false(c.combatant.poise.locked, "and unlocks poise")
	assert_eq(c.stagger_ticks_left, 0, "no stagger left")
	before_each()
	c.kill()
	c.force_action(roar)
	assert_eq(c.state, S.DEAD, "ignored when dead")
	assert_eq(c.action, null, "no action")


# --------------------------------------------------------------------------- slows

func test_slow_multiplies_movement_in_every_state() -> void:
	assert_near(c.move_speed_multiplier(), 1.0, 1e-9, "no statuses -> unchanged")
	var slow := StatusDef.from_dict({"id": "status.slow", "stacking": "strongest_wins", "duration_s": 3.0,
		"magnitude_key": "slow_fraction", "modifiers": {"slow_fraction": 0.3}, "tags": ["Debuff", "Slow"]})
	c.combatant.statuses.apply(slow, NAN, -1.0, "e", t, PackedStringArray())
	assert_near(c.move_speed_multiplier(), 0.7, 1e-9, "a 30% slow in locomotion")
	c.request(&"block")
	assert_near(c.move_speed_multiplier(), 0.4 * 0.7, 1e-9, "and while blocking")
	before_each()
	c.combatant.statuses.apply(slow, 0.5, -1.0, "e", t, PackedStringArray())
	c.request(&"light")
	assert_near(c.move_speed_multiplier(), 0.3 * 0.5, 1e-9, "and while attacking")
