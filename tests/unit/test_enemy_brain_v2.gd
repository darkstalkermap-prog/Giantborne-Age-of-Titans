extends TestSuite
## P04 EnemyBrain and WolfBrain as pure objects (plan §3.4, spec 10, decision 26): morale
## (debounce, x1.5 while outmatched, unscaled sources, commander, scripted events, bosses,
## recovery), FLEE for at least 4 s, regroup only with a leader, the 20 s rout, ROUTED
## behaviour, stagger during flight, ATTACK through CASTING, outmatched thresholds, formation
## HOLD (slot, reach, hold_attack, leaving it), attack choice by range band, and the wolf's
## flank geometry and harassing from behind.

const S := EnemyBrain.AIState
const CS := CombatController.State
const STAGE_1_H := 3.6576
const STAGE_2_H := 5.4864

var releases := 0
var token_ok := true


func before_each() -> void:
	releases = 0
	token_ok = true


func _req() -> bool:
	return token_ok


func _rel() -> void:
	releases += 1


func _record(id: String, patch := {}) -> Dictionary:
	var rec: Dictionary = (GameData.get_record(id) as Dictionary).duplicate(true)
	TestFixtures.deep_merge(rec, patch)
	return rec


func _soldier(patch := {}) -> EnemyBrain:
	return EnemyBrain.new("test.unit", _record("enemy.soldier", patch), 1234)


func _wolf(patch := {}) -> WolfBrain:
	return WolfBrain.new("test.wolf", _record("enemy.wolf", patch), 99)


## A perception snapshot of the giant at `target` seen from `me` (facing it unless facing_deg).
func _snap(me: Vector3, target: Vector3, height := STAGE_1_H, leader := false, visible := true,
		facing_deg := 0.0, target_forward := Vector3.FORWARD) -> Dictionary:
	var to := target - me
	to.y = 0.0
	return {"exists": true, "target_id": "player", "alive": true, "position": target,
		"distance": to.length(), "visible": visible, "facing_deg": facing_deg, "target_radius": 0.85,
		"target_forward": target_forward, "target_height": height, "target_stage": 1,
		"target_state": CS.LOCOMOTION, "self_health_frac": 1.0, "has_leader": leader}


func _decide(b: EnemyBrain, tick: int, me: Vector3, controller_state := CS.LOCOMOTION) -> void:
	b.decide(tick, controller_state, me, _req, _rel)


## Perceive + decide every 6 ticks from `from_tick` up to `to_tick` (inclusive).
func _run(b: EnemyBrain, from_tick: int, to_tick: int, me: Vector3, snap: Dictionary) -> void:
	var t := from_tick
	while t <= to_tick:
		b.perceive(t, snap)
		_decide(b, t, me)
		t += 6


## A soldier brain that has seen the giant and is engaged (APPROACH) at tick 100.
func _engaged(b: EnemyBrain, me: Vector3, snap: Dictionary) -> int:
	b.perceive(40, snap)
	_decide(b, 40, me)
	_decide(b, 100, me)   # notice_s has passed
	return 100


# --------------------------------------------------------------------------- morale

func test_ally_deaths_are_debounced() -> void:
	var b := _soldier()
	var changes: Array = []
	b.morale_changed.connect(func(m: float, d: float, r: String) -> void: changes.append([m, d, r]))
	b.on_ally_died(100)
	b.on_ally_died(130)
	b.on_ally_died(219)
	assert_near(b.morale, 60.0, 1e-6, "three deaths within 2 s cost -10 once")
	b.on_ally_died(220)
	assert_near(b.morale, 50.0, 1e-6, "2 s after the first counted death the next one costs -10")
	assert_eq(changes, [[60.0, -10.0, "ally_died"], [50.0, -10.0, "ally_died"]], "each change reported once")
	var tuned := _soldier({"ai": {"morale_debounce_s": 0.5}})
	tuned.on_ally_died(100)
	tuned.on_ally_died(131)
	assert_near(tuned.morale, 50.0, 1e-6, "ai.morale_debounce_s sets the window")


func test_losses_count_x1_5_while_outmatched() -> void:
	var b := _soldier()
	b.perceive(10, _snap(Vector3(0, 0, -10), Vector3.ZERO, STAGE_1_H))
	assert_false(b.is_outmatched(), "a stage-1 giant (2.03x) does not outmatch a 1.8 m soldier")
	b.on_morale_delta(-20.0, "player", 10)
	assert_near(b.morale, 50.0, 1e-6, "Thunder Roar's -20 as given")
	b.perceive(20, _snap(Vector3(0, 0, -10), Vector3.ZERO, STAGE_2_H))
	assert_true(b.is_outmatched(), "a stage-2 giant (3.05x >= 2.5) does")
	b.on_morale_delta(-20.0, "player", 20)
	assert_near(b.morale, 20.0, 1e-6, "-20 lands as -30")
	b.on_ally_died(400)
	assert_near(b.morale, 5.0, 1e-6, "an ally death -10 lands as -15")
	var c := _soldier()
	c.perceive(10, _snap(Vector3(0, 0, -10), Vector3.ZERO, STAGE_2_H))
	c.on_morale_delta(-35.0, "awe", 10)
	assert_near(c.morale, 35.0, 1e-6, "awe is absolute (P11b): never scaled")
	c.on_commander_died(20)
	assert_near(c.morale, 0.0, 1e-6, "a commander's death -25 lands as -37.5 (clamped at 0)")
	c.on_morale_delta(150.0, "script", 30)
	assert_near(c.morale, 100.0, 1e-6, "morale is clamped to 100")


func test_commander_death_and_siege_event() -> void:
	var b := _soldier()
	b.on_commander_died(100)
	assert_near(b.morale, 45.0, 1e-6, "commander death -25")
	b.on_ally_died(110)
	assert_near(b.morale, 45.0, 1e-6, "ordinary deaths in the same 2 s cost nothing more")
	assert_true(b.on_morale_event(&"siege_destroyed", 300), "siege_destroyed is a known event")
	assert_near(b.morale, 25.0, 1e-6, "siege_destroyed -20")
	assert_false(b.on_morale_event(&"dragon_sighted", 310), "an unknown event is refused")
	assert_near(b.morale, 25.0, 1e-6, "and changes nothing")


func test_bosses_ignore_morale() -> void:
	var b := _soldier({"ignores_morale": true})
	b.on_morale_delta(-80.0, "player", 10)
	b.on_ally_died(20)
	b.on_commander_died(30)
	b.on_morale_event(&"siege_destroyed", 40)
	assert_near(b.morale, 70.0, 1e-6, "no loss of any kind")
	b.morale = 5.0
	var me := Vector3(0, 0, -6)
	_engaged(b, me, _snap(me, Vector3.ZERO))
	_decide(b, 106, me)
	assert_false(b.state in [S.FLEE, S.ROUTED], "and never flees (%s)" % b.state_name())


func test_morale_recovers_2_per_s_after_6_s_up_to_the_start() -> void:
	var b := _soldier()
	_decide(b, 0, Vector3.ZERO)
	b.on_morale_delta(-20.0, "player", 0)
	var t := 6
	while t <= 360:
		_decide(b, t, Vector3.ZERO)
		t += 6
	assert_near(b.morale, 50.0, 1e-6, "nothing comes back in the first 6 s")
	while t <= 420:
		_decide(b, t, Vector3.ZERO)
		t += 6
	assert_near(b.morale, 52.0, 1e-6, "then +2 per second")
	while t <= 1500:
		_decide(b, t, Vector3.ZERO)
		t += 6
	assert_near(b.morale, 70.0, 1e-6, "up to the record's starting morale, never beyond")
	b.on_morale_delta(-10.0, "player", t)
	var lost_at := t
	while t <= lost_at + 300:
		_decide(b, t, Vector3.ZERO)
		t += 6
	assert_near(b.morale, 60.0, 1e-6, "a new loss restarts the 6 s delay")


# --------------------------------------------------------------------------- flight

func test_flee_lasts_4_s_and_regroups_only_with_a_leader() -> void:
	var b := _soldier()
	var me := Vector3(0, 0, -6)
	var with_leader := _snap(me, Vector3.ZERO, STAGE_1_H, true)
	var t := _engaged(b, me, with_leader)
	b.morale = 10.0
	b.perceive(t + 6, with_leader)
	_decide(b, t + 6, me)
	assert_eq(b.state, S.FLEE, "below flee_morale (25) while aware: FLEE")
	assert_true(b.flee_point != Vector3.INF and b.flee_point.z < me.z - 11.0,
		"it runs straight away from the giant, flee_distance_m (12) far: %s" % b.flee_point)
	assert_eq(b.move_speed, -1.0, "at run speed")
	b.morale = 60.0
	_run(b, t + 12, t + 6 + 234, me, with_leader)
	assert_eq(b.state, S.FLEE, "morale back above 45 and a leader, but not before 4 s")
	_run(b, t + 6 + 240, t + 6 + 246, me, with_leader)
	assert_eq(b.state, S.APPROACH, "after 4 s with a leader it regroups (%s)" % b.state_name())


func test_without_a_leader_it_routs_after_20_s() -> void:
	var b := _soldier()
	var me := Vector3(0, 0, -6)
	var alone := _snap(me, Vector3.ZERO, STAGE_1_H, false)
	var t := _engaged(b, me, alone)
	var routs := [0]   # lambdas capture locals by value: count in an array
	b.routed.connect(func() -> void: routs[0] += 1)
	b.morale = 10.0
	t += 6
	b.perceive(t, alone)
	_decide(b, t, me)
	assert_eq(b.state, S.FLEE, "flees")
	var fled_at := t
	b.morale = 60.0
	_run(b, t + 6, fled_at + 20 * 60 - 6, me, alone)
	assert_eq(b.state, S.FLEE, "morale above 45 does not end the flight without a leader (%s)" % b.state_name())
	assert_eq(routs[0], 0, "not routed before 20 s")
	_run(b, fled_at + 20 * 60, fled_at + 20 * 60, me, alone)
	assert_eq(b.state, S.ROUTED, "routed 20 s (ai default rout_after_s) after the leader was missing")
	assert_eq(routs[0], 1, "routed emitted once")
	assert_false(b.aware, "out of the fight: not aware")
	assert_true(b.is_outmatched() == false and b.state_name() == "Routed", "state name")
	# ROUTED: never regroups, attacks nothing, ignores sight; a hit sends it running again.
	var spot := b.flee_point
	_run(b, fled_at + 20 * 60 + 6, fled_at + 20 * 60 + 600, me, _snap(me, me + Vector3(0, 0, 1.5), STAGE_1_H, true))
	assert_eq(b.state, S.ROUTED, "even with a leader again it stays routed")
	assert_eq(b.attack_request, "", "and requests no attack with the giant beside it")
	assert_false(b.aware, "perception does not make it aware again")
	b.on_noise(fled_at + 20 * 60 + 606, me + Vector3(3, 0, 0), "player", true)
	_decide(b, fled_at + 20 * 60 + 612, me)
	assert_true(b.flee_point.distance_to(spot) > 1.0, "hit: it picks a new flee point")
	assert_true(b.flee_point.x < me.x - 6.0, "away from where the hit came from: %s" % b.flee_point)
	assert_eq(routs[0], 1, "routed is not emitted again")


func test_regroup_needs_leader_can_be_turned_off() -> void:
	var b := _soldier({"ai": {"regroup_needs_leader": false}})
	var me := Vector3(0, 0, -6)
	var alone := _snap(me, Vector3.ZERO, STAGE_1_H, false)
	var t := _engaged(b, me, alone)
	b.morale = 10.0
	b.perceive(t + 6, alone)
	_decide(b, t + 6, me)
	b.morale = 60.0
	_run(b, t + 12, t + 6 + 246, me, alone)
	assert_eq(b.state, S.APPROACH, "regroups after 4 s without a leader when the record allows it")


func test_a_stagger_during_flight_resumes_the_flight() -> void:
	var b := _soldier()
	var me := Vector3(0, 0, -6)
	var snap := _snap(me, Vector3.ZERO)
	var t := _engaged(b, me, snap)
	b.morale = 10.0
	_decide(b, t + 6, me)
	assert_eq(b.state, S.FLEE, "flees")
	_decide(b, t + 12, me, CS.STAGGERED)
	assert_eq(b.state, S.STAGGERED, "staggered")
	_decide(b, t + 72, me)
	assert_eq(b.state, S.FLEE, "and back to FLEE afterwards, not APPROACH")


func test_a_blocked_flight_picks_a_new_point() -> void:
	var b := _soldier()
	var calls: Array = []
	b.flee_resolver = func(from: Vector3, threat: Vector3, dist: float) -> Vector3:
		calls.append([from, threat, dist])
		return from + Vector3(0, 0, -dist) if calls.size() == 1 else from + Vector3(dist, 0, 0)
	var me := Vector3(0, 0, -6)
	var t := _engaged(b, me, _snap(me, Vector3.ZERO))
	b.morale = 10.0
	_decide(b, t + 6, me)
	assert_eq(calls.size(), 1, "the actor's resolver picks the flee point")
	assert_near(float(calls[0][2]), 12.0, 1e-6, "ai.flee_distance_m (default 12)")
	b.on_path_failed(me)
	_decide(b, t + 12, me)
	assert_eq(calls.size(), 2, "a path failure asks for another point")
	assert_true(b.flee_point.is_equal_approx(me + Vector3(12, 0, 0)), "and runs there")
	var cornered := _soldier()
	cornered.flee_resolver = func(_f: Vector3, _t: Vector3, _d: float) -> Vector3: return Vector3.INF
	t = _engaged(cornered, me, _snap(me, Vector3.ZERO))
	cornered.morale = 10.0
	_decide(cornered, t + 6, me)
	assert_eq(cornered.move_target, Vector3.INF, "nowhere reachable: it stands rather than run into a wall")


# --------------------------------------------------------------------------- attacks

func test_attack_lasts_through_casting() -> void:
	var b := _soldier()
	var me := Vector3(0, 0, -1.6)
	var snap := _snap(me, Vector3.ZERO)
	var t := _engaged(b, me, snap)
	assert_eq(b.state, S.APPROACH, "engaged")
	b.perceive(t + 6, snap)
	_decide(b, t + 6, me)
	assert_eq(b.state, S.ATTACK, "in reach with a token: ATTACK")
	assert_true(b.attack_request in ["ability.soldier_slash", "ability.soldier_chop"], "requests one of its attacks")
	_decide(b, t + 12, me, CS.CASTING)
	assert_eq(b.state, S.ATTACK, "an enemy ability runs in CASTING: still attacking")
	_decide(b, t + 18, me, CS.ATTACKING)
	assert_eq(b.state, S.ATTACK, "and in ATTACKING")
	_decide(b, t + 24, me, CS.LOCOMOTION)
	assert_eq(b.state, S.RECOVER, "the attack is over once the controller is back in LOCOMOTION")


func test_outmatched_thresholds() -> void:
	var b := _soldier()
	var me := Vector3(0, 0, -10)
	b.perceive(1, _snap(me, Vector3.ZERO, 4.5))
	assert_near(b.size_ratio(), 2.5, 1e-6, "4.5 / 1.8")
	assert_true(b.is_outmatched(), "exactly the outmatched_ratio counts")
	assert_eq(b.outmatched_behavior(), "formation", "soldiers hold formation")
	b.perceive(2, _snap(me, Vector3.ZERO, 4.4))
	assert_false(b.is_outmatched(), "below it does not")
	assert_eq(b.outmatched_behavior(), "none", "and fights normally")
	var w := _wolf()
	w.perceive(1, _snap(me, Vector3.ZERO, STAGE_2_H))
	assert_true(w.is_outmatched(), "a stage-2 giant outmatches a wolf (6.1 >= 6.0)")
	assert_eq(w.outmatched_behavior(), "harass", "wolves harass")
	w.perceive(2, _snap(me, Vector3.ZERO, STAGE_1_H))
	assert_false(w.is_outmatched(), "a stage-1 giant (4.1x) does not")
	var none := _soldier({"tactics": {"outmatched_ratio": 0.0, "outmatched_behavior": "none"}})
	none.perceive(1, _snap(me, Vector3.ZERO, 50.0))
	assert_false(none.is_outmatched(), "ratio 0 = never outmatched")
	var blind := _soldier()
	assert_false(blind.is_outmatched(), "no perception yet: not outmatched")


func test_formation_hold_slot_reach_and_hold_attack() -> void:
	var b := _soldier()
	var slot := Vector3(4, 0, -10)
	var released := [0]
	b.formation_resolver = func(_me: Vector3, _target: Vector3) -> Vector3: return slot
	b.formation_release = func() -> void: released[0] += 1
	var me := Vector3(0, 0, -12)
	var t := _engaged(b, me, _snap(me, Vector3.ZERO, STAGE_2_H))
	_decide(b, t + 6, me)
	assert_eq(b.state, S.HOLD, "outmatched: HOLD")
	assert_true(b.in_formation(), "in formation")
	assert_eq(b.move_target, slot, "walking to its slot")
	assert_eq(b.face_point, Vector3.ZERO, "facing the giant")
	assert_eq(b.attack_request, "", "the giant is out of reach: no strike")
	b.perceive(t + 12, _snap(slot + Vector3(0.2, 0, 0), Vector3.ZERO, STAGE_2_H))
	_decide(b, t + 12, slot + Vector3(0.2, 0, 0))
	assert_eq(b.move_target, Vector3.INF, "at the slot it stands")
	b.perceive(t + 18, _snap(slot + Vector3(0.6, 0, 0), Vector3.ZERO, STAGE_2_H))
	_decide(b, t + 18, slot + Vector3(0.6, 0, 0))
	assert_eq(b.move_target, Vector3.INF, "a small drift does not make it shuffle (hysteresis)")
	b.perceive(t + 24, _snap(slot + Vector3(1.0, 0, 0), Vector3.ZERO, STAGE_2_H))
	_decide(b, t + 24, slot + Vector3(1.0, 0, 0))
	assert_eq(b.move_target, slot, "pushed 1 m off its slot it walks back")
	b.perceive(t + 30, _snap(slot, slot + Vector3(0, 0, 1.9), STAGE_2_H))
	_decide(b, t + 30, slot)
	assert_eq(b.state, S.ATTACK, "the giant stepped within attack range + its radius (2.05 m): strike")
	assert_true(b.attack_request in ["ability.soldier_slash", "ability.soldier_chop"], "with its own attacks")
	_decide(b, t + 36, slot, CS.LOCOMOTION)
	assert_eq(b.state, S.RECOVER, "then a pause")
	_decide(b, t + 200, slot)
	assert_eq(b.state, S.HOLD, "and back to HOLD")
	# No longer outmatched (the giant shrank): it leaves the formation and fights normally.
	b.perceive(t + 206, _snap(slot, Vector3.ZERO, STAGE_1_H))
	_decide(b, t + 206, slot)
	assert_false(b.in_formation(), "a stage-1 giant: formation over")
	assert_eq(b.state, S.APPROACH, "it approaches")
	assert_eq(released[0], 1, "and gives its formation slot back")
	# The brace counter (P11b) as tactics.hold_attack.
	var brace := _soldier({"tactics": {"hold_attack": "ability.soldier_chop"}})
	brace.formation_resolver = func(_me: Vector3, _target: Vector3) -> Vector3: return slot
	var near := _snap(slot, slot + Vector3(0, 0, 1.8), STAGE_2_H)
	var bt := _engaged(brace, slot, near)
	brace.perceive(bt + 6, near)
	_decide(brace, bt + 6, slot)
	assert_eq(brace.state, S.ATTACK, "a holding unit with a hold_attack strikes too")
	assert_eq(brace.attack_request, "ability.soldier_chop", "with tactics.hold_attack instead of the normal pick")


# --------------------------------------------------------------------------- wolves

func test_wolf_attack_choice_by_range_band() -> void:
	var w := _wolf()
	assert_eq(w.attacks_in_range(0.5), ["ability.wolf_bite"] as Array[String], "up close: the bite")
	assert_eq(w.attacks_in_range(3.0), ["ability.wolf_lunge"] as Array[String], "in the lunge band (1.65-4.65 m)")
	assert_eq(w.choose_attack_in_range(1.3), "", "between the bands: nothing fits")
	assert_eq(w.choose_attack_in_range(6.0), "", "beyond the lunge: nothing fits")
	w.perceive(1, _snap(Vector3(0, 0, -2.5), Vector3.ZERO))
	assert_near(w.stand_off_m(), 0.85 + (1.65 + 4.65) * 0.5, 1e-6, "it circles in the middle of its lunge band")


func test_wolf_angle_from_facing() -> void:
	assert_near(WolfBrain.angle_from_facing(Vector3.FORWARD, Vector3(0, 0, -3)), 0.0, 1e-4, "in front")
	assert_near(absf(WolfBrain.angle_from_facing(Vector3.FORWARD, Vector3(3, 0, 0))), 90.0, 1e-4, "beside")
	assert_near(absf(WolfBrain.angle_from_facing(Vector3.FORWARD, Vector3(0, 0, 3))), 180.0, 1e-4, "behind")
	assert_near(WolfBrain.angle_from_facing(Vector3.FORWARD, Vector3(3, 0, 0)),
		-WolfBrain.angle_from_facing(Vector3.FORWARD, Vector3(-3, 0, 0)), 1e-4, "signed by side")


func test_wolf_flanks_before_lunging_unless_impatient() -> void:
	var w := _wolf()
	var front := Vector3(0, 0, -4.0)
	var snap := _snap(front, Vector3.ZERO)
	w.perceive(10, snap)
	_decide(w, 10, front)
	_decide(w, 40, front)   # after notice_s 0.4 s
	assert_eq(w.state, S.APPROACH, "engaged")
	w.perceive(46, snap)
	_decide(w, 46, front)
	assert_eq(w.attack_request, "", "in front of the giant (0 deg) it does not lunge yet")
	assert_true(w.move_target != Vector3.INF and absf(WolfBrain.angle_from_facing(Vector3.FORWARD, w.move_target)) > 20.0,
		"it circles toward a flank: %s" % w.move_target)
	var side := Vector3(-4.0, 0, 0)
	w.perceive(52, _snap(side, Vector3.ZERO))
	_decide(w, 52, side)
	assert_eq(w.attack_request, "ability.wolf_lunge", "flanked (90 deg > 60) in the lunge band: lunge")
	assert_eq(w.state, S.ATTACK, "attacking")
	var stubborn := _wolf()
	stubborn.perceive(10, snap)
	_decide(stubborn, 10, front)
	_decide(stubborn, 40, front)
	var t := 46
	var lunged := -1
	while t <= 40 + 4 * 60:
		stubborn.perceive(t, snap)
		_decide(stubborn, t, front)
		if stubborn.attack_request != "":
			lunged = t
			break
		t += 6
	assert_true(lunged >= 40 + 3 * 60 - 6, "without a flank it waits about 3 s (%d)" % lunged)
	assert_true(lunged > 0, "then attacks from where it is")


func test_outmatched_wolf_attacks_only_from_behind_then_backs_off() -> void:
	var w := _wolf()
	var front := Vector3(0, 0, -4.0)
	w.perceive(10, _snap(front, Vector3.ZERO, STAGE_2_H))
	_decide(w, 10, front)
	_decide(w, 40, front)
	var t := 46
	while t <= 46 + 6 * 60:
		w.perceive(t, _snap(front, Vector3.ZERO, STAGE_2_H))
		_decide(w, t, front)
		assert_eq(w.attack_request, "", "harassing: never from the front (tick %d)" % t)
		t += 6
	var side := Vector3(-4.0, 0, 0)
	w.perceive(t, _snap(side, Vector3.ZERO, STAGE_2_H))
	_decide(w, t, side)
	assert_eq(w.attack_request, "", "not from the side either (90 deg <= 100)")
	var behind := Vector3(-1.4, 0, 3.7)
	t += 6
	w.perceive(t, _snap(behind, Vector3.ZERO, STAGE_2_H))
	_decide(w, t, behind)
	assert_eq(w.attack_request, "ability.wolf_lunge", "from behind (%.0f deg) it lunges" % WolfBrain.angle_from_facing(Vector3.FORWARD, behind))
	_decide(w, t + 6, behind, CS.ATTACKING)
	_decide(w, t + 60, behind, CS.LOCOMOTION)
	assert_true(w.retreating, "after the attack it backs off")
	assert_eq(releases, 1, "giving its token back")
	_decide(w, t + 66, behind)
	assert_true(w.move_target.distance_to(Vector3.ZERO) >= 8.0, "to about 8 m from the giant: %s" % w.move_target)
