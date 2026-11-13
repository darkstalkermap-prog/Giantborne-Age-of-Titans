class_name EnemyBrain
extends RefCounted
## Finite-state AI shared by every enemy archetype (spec section 10, plan §2.7.3).
##
## Perception runs at 5 Hz and tactical decisions at 10 Hz (driven by the owning EnemyActor);
## movement is applied every tick by the actor. The brain only decides: a move target and
## speed, a point to face, and which attack to request. Engine queries (line of sight,
## distances) arrive as a perception snapshot from the actor, so a brain is a pure object
## that unit tests can drive directly.
##
## The base handles the life cycle every archetype shares - idle, patrol, noticing and
## investigating, fleeing, stagger and death - and delegates the engaged states (approach,
## attack, recover, reposition) to _decide_engaged(), whose default is the melee approach:
## close to the target's legs, take one of the target's attack tokens, strike, pause, repeat;
## without a token, circle. Archetype brains override _decide_engaged() and _choose_attack().
## Losing sight leads to investigating the last known position for memory_s, then patrol.
##
## Morale and size tactics (P04, below its anchor): ally deaths (debounced), commander deaths,
## morale damage from hits and scripted events lower morale; it recovers when nothing is lost
## for a while. Below flee_morale a unit flees to a reachable point and regroups only with a
## leader, or routs. A unit facing a target much taller than itself (tactics.outmatched_ratio)
## switches to its outmatched behaviour: formation (HOLD at a marker or in a line), harass
## (WolfBrain), or the spread / kite / retreat hooks ranged brains fill in (P09).

## The first ten keep their M1 indices (SoldierBrain.AIState.* still resolves); later states
## are appended: HOLD (P04 formations), STAND_DOWN (P11b), RETURN (P10a leash), ROUTED (P04).
enum AIState { IDLE, PATROL, ALERT, APPROACH, ATTACK, RECOVER, REPOSITION, FLEE, STAGGERED, DEAD,
	HOLD, STAND_DOWN, RETURN, ROUTED }
const STATE_NAMES := ["Idle", "Patrol", "Alert", "Approach", "Attack", "Recover", "Reposition",
	"Flee", "Staggered", "Dead", "Hold", "Stand down", "Return", "Routed"]
const TICK_RATE := 60
const ATTACK_FACING_DEG := 35.0

var state: int = AIState.IDLE
var state_tick := 0
var now := 0
var ai: Dictionary = {}
var attacks: Array = []
var attack_weights: Array = []
var patrol_points: Array[Vector3] = []
var patrol_index := 0
var perception: Dictionary = {}
## True while the brain knows where its target is; GameSession (P06) checks it to defer
## checkpoints while enemies nearby are aware of the player.
var aware := false
var investigating := false
var last_known := Vector3.ZERO
var last_seen_tick := -100000
var strike_ready_tick := 0
var holds_token := false
var target_id := ""
var morale := 70.0
var reposition_sign := 1.0
var rng := RandomNumberGenerator.new()
var actor_id := ""
## The actor's CombatController.State at the last decide().
var controller_state: int = CombatController.State.LOCOMOTION

# Outputs, read by the actor every tick.
var move_target := Vector3.INF
var move_speed := 0.0
var face_point := Vector3.INF
var attack_request := ""


## seed_value: the actor passes Sim.DEFAULT_SEED ^ hash(entity_id), so every brain has its own
## deterministic stream and never draws from Sim.rng (which the crit rolls own).
func _init(p_actor_id: String, record: Dictionary, seed_value: int) -> void:
	actor_id = p_actor_id
	ai = record.get("ai", {})
	attacks = record.get("attacks", [])
	attack_weights = record.get("attack_weights", [])
	morale = float(record.get("morale", 70.0))
	rng.seed = seed_value
	_p04_init(record)


func state_name() -> String:
	return STATE_NAMES[state] if state >= 0 and state < STATE_NAMES.size() else "State %d" % state


func _ticks(seconds: float) -> int:
	return int(roundf(seconds * TICK_RATE))


func _set_state(s: int) -> void:
	if s == state:
		return
	state = s
	state_tick = now


func _in_state_s() -> float:
	return float(now - state_tick) / TICK_RATE


# --------------------------------------------------------------------------- perception

## snapshot: {"exists", "target_id", "alive", "position", "distance", "visible", "facing_deg",
## "target_radius", "target_forward", "target_height", "target_stage", "target_state",
## "self_health_frac"} (see EnemyActor._sense).
func perceive(tick: int, snapshot: Dictionary) -> void:
	now = tick
	perception = snapshot
	if state == AIState.ROUTED:
		aware = false   # out of the fight for good (P04): never defers a checkpoint again
		return
	if _p11b_perceive(tick, snapshot):
		return   # P11b: awe; a faction member at peace watches without becoming aware
	if snapshot.get("exists", false) and snapshot.get("alive", false) and snapshot.get("visible", false):
		target_id = snapshot.target_id
		last_known = snapshot.position
		last_seen_tick = tick
		if not aware:
			aware = true
			if state in [AIState.IDLE, AIState.PATROL]:
				_set_state(AIState.ALERT)
		investigating = false


## Hearing (an attack within hearing range) or being hit reveals the position.
func on_noise(tick: int, position: Vector3, source_id: String, certain: bool) -> void:
	now = tick
	if state in [AIState.DEAD, AIState.FLEE, AIState.ROUTED]:
		if state == AIState.ROUTED and certain:
			_reflee_from = position   # a routed unit that is hit flees again (P04)
		return
	if _p11b_heard_in_peace(tick, position, source_id, certain):
		return   # P11b: a faction member at peace notes it and stays calm
	last_known = position
	target_id = source_id
	if certain:
		last_seen_tick = tick
		aware = true
	if state in [AIState.IDLE, AIState.PATROL]:
		investigating = not certain
		_set_state(AIState.ALERT)


## A same-team death nearby (the actor checks ai.ally_death_radius_m): -10 morale, at most once
## per ai.morale_debounce_s (three deaths within 2 s cost -10 once), x1.5 while outmatched.
## tick < 0 uses the brain's last known tick.
func on_ally_died(tick: int = -1) -> void:
	var t := tick if tick >= 0 else now
	if _last_ally_loss_tick != NO_TICK and t - _last_ally_loss_tick < _ticks(float(ai.get("morale_debounce_s", 2.0))):
		return
	_last_ally_loss_tick = t
	apply_morale(-ALLY_DEATH_MORALE * _loss_mult(), "ally_died", t)


# --------------------------------------------------------------------------- decisions

## controller_state: CombatController.State of the actor. request_token() -> bool asks Sim for
## one of the target's attack tokens; release_token() gives it back.
func decide(tick: int, p_controller_state: int, my_position: Vector3, request_token: Callable,
		release_token: Callable) -> void:
	now = tick
	controller_state = p_controller_state
	attack_request = ""
	if controller_state == CombatController.State.DEAD:
		_release(release_token)
		_set_state(AIState.DEAD)
		_stop()
		return
	if controller_state == CombatController.State.STAGGERED:
		_release(release_token)
		if state in [AIState.FLEE, AIState.ROUTED]:
			_resume_after_stagger = state
		_set_state(AIState.STAGGERED)
		_stop()
		return
	if state == AIState.STAGGERED:
		if _resume_after_stagger >= 0:
			_set_state(_resume_after_stagger)
			_resume_after_stagger = -1
		else:
			_set_state(AIState.APPROACH if aware else AIState.PATROL)
	_recover_morale()
	if _p11b_decide(my_position, release_token):
		return   # P11b: neutral (HOLD) and stood-down (STAND_DOWN) faction members
	if not (state in [AIState.FLEE, AIState.ROUTED]) and not ignores_morale \
			and morale < float(ai.get("flee_morale", 25.0)) and aware:
		_release(release_token)
		_begin_flee()
	var memory_ok := (now - last_seen_tick) <= _ticks(float(ai.get("memory_s", 3.0)))
	var target_alive: bool = perception.get("alive", false)
	# Only what the enemy can see is used: while the target is hidden the brain works from the
	# last known position (memory), never from the target's live position.
	var seen: bool = perception.get("visible", false)
	var target_pos: Vector3 = perception.get("position", last_known) if seen else last_known
	var distance: float = perception.get("distance", INF) if seen else _flat_distance(my_position, last_known)
	if _p32_decide(my_position, memory_ok, target_pos, release_token):
		return   # P32: a siege crew serves its engine, or runs once it has none
	if _p30_decide(my_position, memory_ok, target_alive, release_token):
		return   # P30: a formation member holds its slot; an outmatched soldier joins a formation or flees
	match state:
		AIState.IDLE:
			_stop()
			if _in_state_s() >= float(ai.get("patrol_wait_s", 1.5)) and not patrol_points.is_empty():
				_set_state(AIState.PATROL)
		AIState.PATROL:
			face_point = Vector3.INF
			if patrol_points.is_empty():
				_set_state(AIState.IDLE)
				return
			var p := patrol_points[patrol_index % patrol_points.size()]
			move_target = p
			move_speed = 0.0  # actor maps 0 -> walk speed
			if _flat_distance(my_position, p) < 0.8:
				patrol_index = (patrol_index + 1) % patrol_points.size()
				_set_state(AIState.IDLE)
		AIState.ALERT:
			face_point = last_known
			if _in_state_s() < float(ai.get("notice_s", 0.6)):
				_stop_moving()
				return
			if aware and memory_ok and target_alive:
				_set_state(AIState.APPROACH)
				return
			# Investigate the last known position, then give up and patrol.
			move_target = last_known
			move_speed = 0.0
			if _flat_distance(my_position, last_known) < 1.5 or _in_state_s() > 8.0:
				aware = false
				investigating = false
				_set_state(AIState.PATROL)
		AIState.FLEE:
			_release(release_token)
			_decide_flee(my_position, target_pos, distance, seen)
		AIState.ROUTED:
			_release(release_token)
			_decide_routed(my_position, target_pos)
		AIState.DEAD:
			_stop()
		_:
			_decide_engaged(my_position, target_pos, distance, seen, memory_ok, target_alive,
				request_token, release_token)


## The engaged states (APPROACH, ATTACK, RECOVER, REPOSITION, and any state the base does not
## handle itself). Default: the melee approach - run to the engage point beside the target,
## strike with a token when in range and facing it, pause between strikes, circle without one.
func _decide_engaged(my_position: Vector3, target_pos: Vector3, distance: float, seen: bool,
		memory_ok: bool, target_alive: bool, request_token: Callable, release_token: Callable) -> void:
	if _decide_outmatched(outmatched_behavior(), my_position, target_pos, distance, seen, memory_ok,
			target_alive, request_token, release_token):
		return
	match state:
		AIState.APPROACH:
			if not target_alive and perception.get("exists", false):
				_release(release_token)
				aware = false
				_set_state(AIState.PATROL)
				return
			if not memory_ok:
				_release(release_token)
				investigating = true
				aware = false
				_set_state(AIState.ALERT)
				return
			face_point = target_pos
			var attack_range := float(ai.get("attack_range_m", 1.2)) + float(perception.get("target_radius", 0.85))
			var facing_ok := absf(float(perception.get("facing_deg", 180.0))) <= ATTACK_FACING_DEG
			if distance <= attack_range and _sight_blocked(seen):
				_regain_sight(my_position, target_pos)   # M8 gate (F36): no waiting for a sight line
			elif distance <= attack_range:
				_stop_moving()
				if seen and now >= strike_ready_tick and facing_ok:
					if holds_token or request_token.call():
						holds_token = true
						attack_request = _choose_attack()
						_set_state(AIState.ATTACK)
					else:
						reposition_sign = 1.0 if rng.randf() < 0.5 else -1.0
						_set_state(AIState.REPOSITION)
			else:
				move_target = _engage_point(my_position, target_pos)
				move_speed = -1.0  # actor maps -1 -> run speed
		AIState.ATTACK:
			face_point = target_pos
			_stop_moving()
			if _attack_finished() and _in_state_s() > 0.05:
				var pause := rng.randf_range(float(ai.get("strike_pause_min_s", 0.8)),
					float(ai.get("strike_pause_max_s", 1.4)))
				strike_ready_tick = now + _ticks(pause)
				_set_state(AIState.RECOVER)
		AIState.RECOVER:
			# Pause between strikes; give ground slightly so the giant can punish or step in.
			face_point = target_pos
			var away := my_position - target_pos
			away.y = 0.0
			if away.length() < float(ai.get("attack_range_m", 1.2)) + float(perception.get("target_radius", 0.85)) - 0.2 and away.length() > 0.01:
				move_target = my_position + away.normalized() * 1.0
				move_speed = 0.0
			else:
				_stop_moving()
			if now >= strike_ready_tick:
				_release(release_token)
				_set_state(AIState.APPROACH)
		AIState.REPOSITION:
			face_point = target_pos
			var offset := my_position - target_pos
			offset.y = 0.0
			if offset.length() < 0.1:
				offset = Vector3.FORWARD
			var radius := float(ai.get("reposition_radius_m", 5.0))
			var tangent := offset.normalized().rotated(Vector3.UP, 0.6 * reposition_sign)
			move_target = target_pos + tangent * radius
			move_speed = 0.0
			if _in_state_s() > 1.5:
				_set_state(AIState.APPROACH)


## True once the requested attack is over: the controller is neither ATTACKING nor CASTING
## (enemy actions of kind "ability" run in CASTING).
func _attack_finished() -> bool:
	return controller_state != CombatController.State.ATTACKING \
		and controller_state != CombatController.State.CASTING


## Called by the actor when a path makes no progress for path_fail_s: pick a new destination.
func on_path_failed(_my_position: Vector3) -> void:
	match state:
		AIState.PATROL:
			patrol_index = (patrol_index + 1) % maxi(1, patrol_points.size())
		AIState.APPROACH, AIState.REPOSITION:
			reposition_sign = -reposition_sign
			_set_state(AIState.REPOSITION)
		AIState.ALERT:
			aware = false
			_set_state(AIState.PATROL)
		AIState.FLEE, AIState.ROUTED:
			_flee_blocked = true   # P04: pick another reachable flee point
		AIState.HOLD:
			_hold_slot_tick = NO_TICK   # P04: ask for the slot again
		_:
			_stop_moving()


## Weighted pick from the record's attacks (own RNG). Archetypes override to choose by range.
func _choose_attack() -> String:
	if attacks.is_empty():
		return ""
	if attack_weights.size() != attacks.size():
		return str(attacks[0])
	var total := 0.0
	for w: float in attack_weights:
		total += w
	var roll := rng.randf() * total
	for i in attacks.size():
		roll -= float(attack_weights[i])
		if roll <= 0.0:
			return str(attacks[i])
	return str(attacks[attacks.size() - 1])


## Approach the target's legs from the side we are already on.
func _engage_point(my_position: Vector3, target_pos: Vector3) -> Vector3:
	var from_target := my_position - target_pos
	from_target.y = 0.0
	if from_target.length() < 0.1:
		from_target = Vector3.FORWARD
	var r := float(ai.get("engage_distance_m", 1.0)) + float(perception.get("target_radius", 0.85))
	return target_pos + from_target.normalized() * r


func _release(release_token: Callable) -> void:
	if holds_token:
		holds_token = false
		release_token.call()


func _stop_moving() -> void:
	move_target = Vector3.INF
	move_speed = 0.0


func _stop() -> void:
	_stop_moving()
	face_point = Vector3.INF


static func _flat_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


# --------------------------------------------------------------------------- package extensions
# Later packages add their members directly below their own anchor (plan §1.5).

## @anchor P04
# --- morale, flight and size tactics (P04) --------------------------------------------------

## Morale changed by `delta` (after scaling and clamping). reason: the attacker's entity id,
## "ally_died", "commander_died", "awe", "siege_destroyed", "recover", ...
signal morale_changed(morale: float, delta: float, reason: String)
## Emitted once, when the unit routs (it fled without a leader for ai.rout_after_s).
signal routed

const NO_TICK := -1000000000
const ALLY_DEATH_MORALE := 10.0
const COMMANDER_DEATH_MORALE := 25.0
## Morale losses from attackers and ally deaths count this much more while outmatched.
const OUTMATCHED_LOSS_MULT := 1.5
const MORALE_RECOVERY_PER_S := 2.0
const MORALE_RECOVERY_DELAY_S := 6.0
const MIN_FLEE_S := 4.0
const FLEE_ARRIVE_M := 1.2
const FLEE_REPICK_S := 2.0
## A fleeing unit that has arrived moves on when its target comes this close.
const FLEE_THREAT_M := 5.0
## A holding unit walks to its slot until it is this close, and steps out again only once the
## slot is HOLD_LEAVE_M away (hysteresis: no shuffling on the spot, yet a tidy line).
const HOLD_ARRIVE_M := 0.3
const HOLD_LEAVE_M := 0.8
const HOLD_SLOT_REFRESH_S := 0.5
## Scripted morale events (on_morale_event): event -> morale change. No slice content raises
## "siege_destroyed" (siege equipment is deferred); the hook is unit-tested.
const MORALE_EVENTS := {"siege_destroyed": -20.0}
## Morale-loss sources that are applied as given, never x1.5 while outmatched (P11b's awe and
## the scripted events are absolute).
const UNSCALED_MORALE_SOURCES := ["awe", "siege_destroyed", "script"]

## The record's morale (recovery stops there).
var start_morale := 70.0
## Bosses ignore morale: no losses, no flight.
var ignores_morale := false
## The record's tactics block (outmatched_ratio, outmatched_behavior, flank_angle_deg, ...).
var tactics: Dictionary = {}
var own_height_m := 1.8
## Where a fleeing or routed unit runs to (INF = not chosen yet).
var flee_point := Vector3.INF
## Engine-side helpers the actor installs (unit tests leave them unset; pure fallbacks apply):
## flee_resolver(from: Vector3, threat: Vector3, distance: float) -> Vector3 - a reachable flee
## destination, or Vector3.INF when there is none;
var flee_resolver := Callable()
## formation_resolver(my_position: Vector3, target_pos: Vector3) -> Vector3 - this unit's HOLD
## slot (a claimed formation marker, or its place in an ad-hoc line), INF = hold where it is;
var formation_resolver := Callable()
## formation_release() -> void - gives a claimed formation marker back.
var formation_release := Callable()

var _last_loss_tick := NO_TICK
var _last_ally_loss_tick := NO_TICK
var _last_recover_tick := NO_TICK
var _recover_accum := 0.0
var _no_leader_since := NO_TICK
var _last_flee_pick_tick := NO_TICK
var _flee_blocked := false
var _reflee_from := Vector3.INF
var _resume_after_stagger := -1
var _routed_emitted := false
var _hold_mode := false
var _hold_moving := false
var _hold_slot := Vector3.INF
var _hold_slot_tick := NO_TICK
## action id -> Vector2(ai_min_range_m, ai_max_range_m), measured from the target's capsule.
var _attack_ranges: Dictionary = {}


func _p04_init(record: Dictionary) -> void:
	start_morale = morale
	ignores_morale = bool(record.get("ignores_morale", false))
	var t: Variant = record.get("tactics", {})
	tactics = t if typeof(t) == TYPE_DICTIONARY else {}
	own_height_m = float(record.get("height_m", 1.8))
	for id: Variant in attacks:
		_cache_attack_range(str(id))
	var hold := str(tactics.get("hold_attack", ""))
	if hold != "":
		_cache_attack_range(hold)


func _cache_attack_range(id: String) -> void:
	var rec: Dictionary = GameData.get_record(id)
	_attack_ranges[id] = Vector2(float(rec.get("ai_min_range_m", 0.0)), float(rec.get("ai_max_range_m", INF)))


# ---- morale

## Changes morale by `delta` (clamped to 0..100) and reports the change. Ignored by bosses and
## the dead. tick < 0 uses the brain's last known tick.
func apply_morale(delta: float, reason: String, tick: int = -1) -> void:
	if ignores_morale or state == AIState.DEAD or delta == 0.0:
		return
	delta = _p30_morale_scale(delta, reason)   # P30: a living banner halves awe and ally-death losses
	var t := tick if tick >= 0 else now
	var before := morale
	morale = clampf(morale + delta, 0.0, 100.0)
	if delta < 0.0:
		_last_loss_tick = t
		_recover_accum = 0.0
	if not is_equal_approx(morale, before):
		morale_changed.emit(morale, morale - before, reason)


## Morale damage from a hit (Thunder Roar's -20) or another source. source_id is the attacker's
## entity id, or a reason such as "awe". Losses from an attacker count x1.5 while outmatched.
func on_morale_delta(delta: float, source_id: String, tick: int = -1) -> void:
	if delta < 0.0 and not UNSCALED_MORALE_SOURCES.has(source_id):
		delta *= _loss_mult()
	apply_morale(delta, source_id, tick)


## The encounter's commander (or a commander nearby) died: -25, x1.5 while outmatched. Not
## debounced; ordinary deaths in the next ai.morale_debounce_s cost nothing more.
func on_commander_died(tick: int = -1) -> void:
	var t := tick if tick >= 0 else now
	_last_ally_loss_tick = t
	apply_morale(-COMMANDER_DEATH_MORALE * _loss_mult(), "commander_died", t)


## Scripted morale events (MORALE_EVENTS, e.g. "siege_destroyed" -20). Returns false (and
## changes nothing) for an unknown event.
func on_morale_event(event: StringName, tick: int = -1) -> bool:
	var key := String(event)
	if not MORALE_EVENTS.has(key):
		return false
	if _p32_debounced(key, tick):
		return true   # P32: a siege engine's fall costs a unit once per SIEGE_DEBOUNCE_S
	apply_morale(float(MORALE_EVENTS[key]), key, tick)
	return true


func _loss_mult() -> float:
	return OUTMATCHED_LOSS_MULT if is_outmatched() else 1.0


## +2 morale per second once MORALE_RECOVERY_DELAY_S have passed without a loss, up to the
## record's starting morale (so FLEE can end). Runs in every decide().
func _recover_morale() -> void:
	var last := _last_recover_tick
	_last_recover_tick = now
	if ignores_morale or state == AIState.ROUTED or morale >= start_morale or last == NO_TICK:
		_recover_accum = 0.0
		return
	var from := maxi(last, _last_loss_tick + _ticks(MORALE_RECOVERY_DELAY_S))
	if now <= from:
		return
	_recover_accum += MORALE_RECOVERY_PER_S * float(now - from) / TICK_RATE
	if _recover_accum >= 1.0:
		var whole := floorf(_recover_accum)
		_recover_accum -= whole
		apply_morale(minf(whole, start_morale - morale), "recover", now)


# ---- size

## The perceived target's height over this unit's height (0 without a perception).
func size_ratio() -> float:
	if own_height_m <= 0.0:
		return 0.0
	return float(perception.get("target_height", 0.0)) / own_height_m


## True when the perceived target is at least tactics.outmatched_ratio times this unit's height
## (decision 26: a stage-2 giant outmatches soldiers, 5.49 / 1.8 = 3.05 >= 2.5).
func is_outmatched() -> bool:
	var ratio := float(tactics.get("outmatched_ratio", 0.0))
	return ratio > 0.0 and bool(perception.get("exists", false)) and size_ratio() >= ratio - 1e-6


## tactics.outmatched_behavior while outmatched, otherwise "none".
func outmatched_behavior() -> String:
	if not is_outmatched():
		return "none"
	return str(tactics.get("outmatched_behavior", "none"))


## True while a leader remains to regroup around (the actor fills "has_leader" in every
## perception snapshot: a living commander of the encounter, or - when the encounter has no
## commander - a living ally within ai.leader_radius_m that is not fleeing).
func has_leader() -> bool:
	return bool(perception.get("has_leader", false))


## True while the unit holds a formation slot (HOLD and its strikes).
func in_formation() -> bool:
	return _hold_mode


# ---- attack choice by range

## The attacks whose ai range band (ai_min_range_m..ai_max_range_m, from the target's capsule
## surface; an action without one fits any range) contains `edge_m`.
func attacks_in_range(edge_m: float) -> Array[String]:
	var out: Array[String] = []
	for id: Variant in attacks:
		var r: Vector2 = _attack_ranges.get(str(id), Vector2(0.0, INF))
		if edge_m >= r.x - 1e-6 and edge_m <= r.y + 1e-6:
			out.append(str(id))
	return out


## Weighted pick (own RNG, the record's attack_weights) among attacks_in_range(edge_m); "" when
## none fits.
func choose_attack_in_range(edge_m: float) -> String:
	var fits := attacks_in_range(edge_m)
	if fits.size() <= 1:
		return fits[0] if fits.size() == 1 else ""
	var weights: Array[float] = []
	var total := 0.0
	for id in fits:
		var i := attacks.find(id)
		var w := float(attack_weights[i]) if attack_weights.size() == attacks.size() and i >= 0 else 1.0
		weights.append(w)
		total += w
	var roll := rng.randf() * total
	for i in fits.size():
		roll -= weights[i]
		if roll <= 0.0:
			return fits[i]
	return fits[fits.size() - 1]


# ---- outmatched behaviours

## Runs the outmatched behaviour of this decision. Returns true when it handled it; otherwise
## the unit fights normally (leaving a formation it held).
func _decide_outmatched(behavior: String, my_position: Vector3, target_pos: Vector3, distance: float,
		seen: bool, memory_ok: bool, target_alive: bool, request_token: Callable, release_token: Callable) -> bool:
	var handled := false
	match behavior:
		"formation":
			handled = _decide_formation(my_position, target_pos, distance, seen, memory_ok, target_alive,
				request_token, release_token)
		"harass":
			handled = _decide_harass(my_position, target_pos, distance, seen, memory_ok, target_alive,
				request_token, release_token)
		"spread":
			handled = _decide_spread(my_position, target_pos, distance, seen, memory_ok, target_alive,
				request_token, release_token)
		"kite":
			handled = _decide_kite(my_position, target_pos, distance, seen, memory_ok, target_alive,
				request_token, release_token)
		"retreat":
			handled = _decide_retreat(my_position, target_pos, distance, seen, memory_ok, target_alive,
				request_token, release_token)
	if not handled:
		if _hold_mode:
			_leave_hold()
		if state == AIState.HOLD:
			_set_state(AIState.APPROACH)
	return handled


## Outmatched hooks; true = handled. The base handles none of them (the unit fights normally):
## WolfBrain fills harass, the ranged brains (P09) spread, kite and retreat.
func _decide_harass(_my_position: Vector3, _target_pos: Vector3, _distance: float, _seen: bool,
		_memory_ok: bool, _target_alive: bool, _request_token: Callable, _release_token: Callable) -> bool:
	return false


func _decide_spread(_my_position: Vector3, _target_pos: Vector3, _distance: float, _seen: bool,
		_memory_ok: bool, _target_alive: bool, _request_token: Callable, _release_token: Callable) -> bool:
	return false


func _decide_kite(_my_position: Vector3, _target_pos: Vector3, _distance: float, _seen: bool,
		_memory_ok: bool, _target_alive: bool, _request_token: Callable, _release_token: Callable) -> bool:
	return false


func _decide_retreat(_my_position: Vector3, _target_pos: Vector3, _distance: float, _seen: bool,
		_memory_ok: bool, _target_alive: bool, _request_token: Callable, _release_token: Callable) -> bool:
	return false


## Formation (outmatched soldiers, decision 26): HOLD at the slot formation_resolver gives (a
## formation marker, or a place in an ad-hoc line), facing the target with the guard up; strike
## only when the target's capsule is within reach - with tactics.hold_attack when set (P11b's
## brace counter) - holding one of the target's melee tokens; then back to HOLD.
func _decide_formation(my_position: Vector3, target_pos: Vector3, distance: float, seen: bool,
		memory_ok: bool, target_alive: bool, request_token: Callable, release_token: Callable) -> bool:
	if not target_alive and perception.get("exists", false):
		_leave_hold()
		_release(release_token)
		aware = false
		_set_state(AIState.PATROL)
		return true
	if not memory_ok:
		_leave_hold()
		_release(release_token)
		investigating = true
		aware = false
		_set_state(AIState.ALERT)
		return true
	if not _hold_mode:
		_hold_moving = true   # a fresh hold: walk all the way to the slot
	_hold_mode = true
	face_point = target_pos
	match state:
		AIState.ATTACK:
			_stop_moving()
			if _attack_finished() and _in_state_s() > 0.05:
				strike_ready_tick = now + _ticks(rng.randf_range(float(ai.get("strike_pause_min_s", 0.8)),
					float(ai.get("strike_pause_max_s", 1.4))))
				_set_state(AIState.RECOVER)
			return true
		AIState.RECOVER:
			_stop_moving()
			if now >= strike_ready_tick:
				_release(release_token)
				_set_state(AIState.HOLD)
			return true
	_set_state(AIState.HOLD)
	var slot := _current_hold_slot(my_position, target_pos)
	var to_slot := _flat_distance(my_position, slot) if slot != Vector3.INF else 0.0
	if to_slot > HOLD_LEAVE_M:
		_hold_moving = true
	if _hold_moving and to_slot > HOLD_ARRIVE_M:
		move_target = slot
		move_speed = -1.0 if to_slot > 4.0 else 0.0
	else:
		_hold_moving = false
		_stop_moving()
	var facing_ok := absf(float(perception.get("facing_deg", 180.0))) <= ATTACK_FACING_DEG
	if seen and facing_ok and now >= strike_ready_tick and distance <= hold_reach():
		if holds_token or request_token.call():
			holds_token = true
			var hold_attack := str(tactics.get("hold_attack", ""))
			attack_request = hold_attack if hold_attack != "" else _choose_attack()
			_set_state(AIState.ATTACK)
	return true


## How close (centre to centre) the target must come before a holding unit strikes: the hold
## attack's ai_max_range_m, or ai.attack_range_m, plus the target's capsule radius.
func hold_reach() -> float:
	var radius := float(perception.get("target_radius", 0.85))
	var hold := str(tactics.get("hold_attack", ""))
	if hold != "" and _attack_ranges.has(hold) and (_attack_ranges[hold] as Vector2).y < INF:
		return (_attack_ranges[hold] as Vector2).y + radius
	return float(ai.get("attack_range_m", 1.2)) + radius


func _current_hold_slot(my_position: Vector3, target_pos: Vector3) -> Vector3:
	if _hold_slot_tick == NO_TICK or now - _hold_slot_tick >= _ticks(HOLD_SLOT_REFRESH_S):
		_hold_slot_tick = now
		_hold_slot = Vector3.INF
		if formation_resolver.is_valid():
			_hold_slot = formation_resolver.call(my_position, target_pos)
	return _hold_slot


func _leave_hold() -> void:
	if _hold_mode and formation_release.is_valid():
		formation_release.call()
	_hold_mode = false
	_hold_moving = false
	_hold_slot = Vector3.INF
	_hold_slot_tick = NO_TICK


# ---- flight and rout

func _begin_flee() -> void:
	_leave_hold()
	_set_state(AIState.FLEE)
	flee_point = Vector3.INF
	_no_leader_since = NO_TICK
	_flee_blocked = false


## FLEE (spec 10): run to a reachable point ai.flee_distance_m away for at least MIN_FLEE_S;
## regroup above regroup_morale only with a leader (unless ai.regroup_needs_leader is false);
## with no leader for ai.rout_after_s the unit routs.
func _decide_flee(my_position: Vector3, target_pos: Vector3, distance: float, seen: bool) -> void:
	face_point = Vector3.INF
	var repick := flee_point == Vector3.INF or _flee_blocked
	if not repick and seen and distance < FLEE_THREAT_M \
			and _flat_distance(my_position, flee_point) <= FLEE_ARRIVE_M \
			and now - _last_flee_pick_tick >= _ticks(FLEE_REPICK_S):
		repick = true
	if repick:
		flee_point = _pick_flee_point(my_position, target_pos)
	_go_to(my_position, flee_point)
	var needs_leader := bool(ai.get("regroup_needs_leader", true))
	var leader := has_leader()
	if leader:
		_no_leader_since = NO_TICK
	elif _no_leader_since == NO_TICK:
		_no_leader_since = now
	if _in_state_s() >= MIN_FLEE_S and morale > float(ai.get("regroup_morale", 45.0)) \
			and (leader or not needs_leader):
		if routs_when_outmatched():
			_rout()   # M6 gate: a broken pack does not come back to a giant that outmatches it
			return
		flee_point = Vector3.INF
		_set_state(AIState.APPROACH if aware else AIState.ALERT)
		return
	if needs_leader and not leader \
			and now - _no_leader_since >= _ticks(float(ai.get("rout_after_s", 20.0))):
		_rout()


## M6 gate (the Barrow's wardens at stage 3): true when this unit would regroup but the giant
## outmatches it (is_outmatched) and its record has tactics.outmatched_rout - it routs instead.
## Wolves have it: broken by a stage-2 or stage-3 giant's roar or its blows, a harassing pack ran
## twelve metres, came back as soon as its morale recovered and broke again, for minutes, while the
## giant could neither catch nor end it (the expert bot's crown stage ran out its 240 s watchdog).
func routs_when_outmatched() -> bool:
	return bool(tactics.get("outmatched_rout", false)) and is_outmatched()


## FLEE -> ROUTED: out of the fight for good (routed emitted once).
func _rout() -> void:
	_set_state(AIState.ROUTED)
	aware = false
	if not _routed_emitted:
		_routed_emitted = true
		routed.emit()


## ROUTED: stay at the flee point, attack nothing, flee again when hit. Never regroups.
func _decide_routed(my_position: Vector3, target_pos: Vector3) -> void:
	face_point = Vector3.INF
	aware = false
	if _reflee_from != Vector3.INF:
		flee_point = _pick_flee_point(my_position, _reflee_from)
		_reflee_from = Vector3.INF
	elif _flee_blocked or flee_point == Vector3.INF:
		flee_point = _pick_flee_point(my_position, target_pos)
	_go_to(my_position, flee_point)


func _pick_flee_point(my_position: Vector3, threat: Vector3) -> Vector3:
	_last_flee_pick_tick = now
	_flee_blocked = false
	var dist := float(ai.get("flee_distance_m", 12.0))
	if flee_resolver.is_valid():
		nav_search_pending = false
		var p: Vector3 = flee_resolver.call(my_position, threat, dist)
		if p == Vector3.INF and nav_search_pending:
			return Vector3.INF   # M7 gate: the search waits for the budget; asked again next decision
		# Nowhere reachable to run to (cornered): stand rather than run into a wall.
		return p if p != Vector3.INF else my_position
	var away := my_position - threat
	away.y = 0.0
	if away.length() < 0.1:
		away = Vector3.BACK
	return my_position + away.normalized() * dist


func _go_to(my_position: Vector3, point: Vector3) -> void:
	if point == Vector3.INF or _flat_distance(my_position, point) <= FLEE_ARRIVE_M:
		_stop_moving()
	else:
		move_target = point
		move_speed = -1.0
## @anchor P07
## @anchor P09
# --- ranged fighting shared by archers and mages (P09) ------------------------------------------
# Plan §3.9, decisions 24 and 25. A ranged unit fights from a band of distances (tactics
# preferred_min_m..preferred_max_m, centre to centre; x1.3 while outmatched) at a firing point it
# holds: the actor's firing_point_resolver picks elevation or cover markers that see the target,
# spread from the other ranged allies, else a point on a ring around the target (a pure ring
# point when no actor installed one). It retreats to the band when the target comes closer,
# answers up close with its close attack (the archer's kick, the mage's staff) holding one of the
# two melee tokens, and shoots only when settled at its point, in the band, seeing the target,
# holding one of the target's two ranged tokens and a launch slot. The ranged token goes back
# when the shot's recovery is over (any state but ATTACK releases it). ArcherBrain and MageBrain
# run _decide_ranged() from _decide_engaged() and their outmatched hooks.

## Outmatched ranged units widen their band and keep farther apart (plan §3.9: x1.3, 10 m).
const OUTMATCHED_BAND_MULT := 1.3
const OUTMATCHED_SPREAD_M := 10.0
## A unit this close to its firing point is settled there (it may shoot); it stops moving within
## FIRING_ARRIVE_M and runs when farther than FIRING_RUN_M (or when retreating).
const FIRING_SETTLE_M := 1.5
const FIRING_ARRIVE_M := 0.6
const FIRING_RUN_M := 4.0
## A held firing point is checked again this often while the target is not seen from it.
const FIRING_REPICK_S := 3.0
## Shots are allowed this far outside the band; a held point this far out of it is replaced.
const BAND_TOLERANCE_M := 0.75
## Ring points (the pure fallback) sit this far inside the band.
const RING_MARGIN_M := 1.0
## A shot starts only when the target is within this angle of the unit's facing (the draw then
## tracks it until the aim lock).
const RANGED_FACING_DEG := 45.0

## Engine-side helpers the ranged actor installs (EnemyActor.install_ranged_helpers; unit tests
## leave them unset and pure fallbacks apply):
## ranged_token_request() -> bool: one of the target's ranged tokens (target_id + ":ranged");
var ranged_token_request := Callable()
## ranged_token_release() -> void;
var ranged_token_release := Callable()
## launch_slot_request(action_id: String) -> bool: Sim.request_launch_slot for that shot;
var launch_slot_request := Callable()
## firing_point_resolver(my_position, target_pos, band: Vector2, spread_m: float, far: bool)
## -> Vector3: the firing point to hold (Vector3.INF = none);
var firing_point_resolver := Callable()
## firing_point_release() -> void: the held point (and its marker) is given up;
var firing_point_release := Callable()
## action_ready(action_id: String) -> bool: its cooldown and costs allow it now (unset = always).
var action_ready := Callable()

## M7 polish: the band of a unit holding a post (EnemyActor's posts, P09 section: a tower's top it
## spawned on, which its navmesh does not reach) - Vector2(0, its shot's reach), centre to centre;
## ZERO = none. On its post a unit keeps the post as its firing point (no search), shoots at whatever
## that band holds, and never kicks.
var post_band := Vector2.ZERO
## True from a granted ranged token until the shot's recovery is over.
var holds_ranged_token := false
## The firing point this unit holds (Vector3.INF = none).
var firing_point := Vector3.INF
## Who the last ally cast (the mage's barrier) is meant for: an ally's entity id, or this unit's.
var ally_target_id := ""
var _firing_tick := NO_TICK
var _firing_blocked := false
var _ranged_ids_cached := false
var _ranged_attack_ids: Array[String] = []
var _close_attack_ids: Array[String] = []
var _ally_cast_ids: Array[String] = []


## The band (flat, centre to centre) this unit fights from: tactics preferred_min_m ..
## preferred_max_m, x OUTMATCHED_BAND_MULT when `outmatched`.
func ranged_band(outmatched: bool = false) -> Vector2:
	if post_band != Vector2.ZERO:
		return post_band   # M7 polish: on a post, whatever its shot reaches
	var b := Vector2(float(tactics.get("preferred_min_m", 0.0)), float(tactics.get("preferred_max_m", 0.0)))
	return b * OUTMATCHED_BAND_MULT if outmatched else b


## How far apart ranged allies keep: tactics.spread_m, at least OUTMATCHED_SPREAD_M when outmatched.
func ranged_spread_m(outmatched: bool = false) -> float:
	var s := float(tactics.get("spread_m", 0.0))
	return maxf(s, OUTMATCHED_SPREAD_M) if outmatched else s


## The record's shots: projectile attacks (they need a ranged token and a launch slot).
func ranged_attacks() -> Array[String]:
	_cache_ranged_ids()
	return _ranged_attack_ids


## The record's close attacks: every other attack with a hit (kick, staff strike).
func close_attacks() -> Array[String]:
	_cache_ranged_ids()
	return _close_attack_ids


## The record's casts on allies (targets_ally: the barrier).
func ally_casts() -> Array[String]:
	_cache_ranged_ids()
	return _ally_cast_ids


func _cache_ranged_ids() -> void:
	if _ranged_ids_cached:
		return
	_ranged_ids_cached = true
	for id: Variant in attacks:
		var rec: Dictionary = GameData.get_record(str(id))
		if is_same(rec.get("targets_ally", false), true):
			_ally_cast_ids.append(str(id))
		elif str(rec.get("hit_shape", "none")) == "projectile":
			_ranged_attack_ids.append(str(id))
		elif str(rec.get("hit_shape", "none")) != "none":
			_close_attack_ids.append(str(id))


## True while the state is one the ranged rules run (other states belong to other packages:
## RETURN, P10a; STAND_DOWN, P11b).
func is_ranged_state() -> bool:
	return state in [AIState.APPROACH, AIState.ATTACK, AIState.RECOVER, AIState.REPOSITION, AIState.HOLD]


func _action_ready(action_id: String) -> bool:
	return action_ready.call(action_id) if action_ready.is_valid() else true


## A ranged turn for `action_id`: one of the target's ranged tokens, then a launch slot. A refused
## slot gives the token straight back (nothing waits holding it). Unset helpers grant.
func _take_ranged_turn(action_id: String) -> bool:
	var token_ok: bool = ranged_token_request.call() if ranged_token_request.is_valid() else true
	if not token_ok:
		return false
	holds_ranged_token = true
	var slot_ok: bool = launch_slot_request.call(action_id) if launch_slot_request.is_valid() else true
	if not slot_ok:
		_release_ranged()
	return slot_ok


func _release_ranged() -> void:
	if holds_ranged_token:
		holds_ranged_token = false
		if ranged_token_release.is_valid():
			ranged_token_release.call()


func _drop_firing_point() -> void:
	firing_point = Vector3.INF
	_firing_tick = NO_TICK
	_firing_retry_tick = NO_TICK
	if firing_point_release.is_valid():
		firing_point_release.call()


## The first close attack whose range band (from the target's capsule surface) holds `edge_m`.
func _close_attack_for(edge_m: float) -> String:
	for id in close_attacks():
		var r: Vector2 = _attack_ranges.get(id, Vector2(0.0, INF))
		if edge_m >= r.x - 1e-6 and edge_m <= r.y + 1e-6:
			return id
	return ""


## Archetype hook: an attack that is not aimed at the target (the mage's barrier), or "".
func _ranged_special_attack(_my_position: Vector3, _target_pos: Vector3, _distance: float) -> String:
	return ""


## Archetype hook: the shot to take now (default: the first ranged attack).
func _ranged_shot() -> String:
	var shots := ranged_attacks()
	return shots[0] if not shots.is_empty() else ""


## True when the unit stands at its firing point (or holds none).
func is_settled(my_position: Vector3) -> bool:
	return firing_point == Vector3.INF or _flat_distance(my_position, firing_point) <= FIRING_SETTLE_M


## The engaged states of a ranged unit: APPROACH (hold a firing point in the band, retreat to it
## when the target comes closer, strike up close, shoot when allowed), ATTACK (the shot, cast or
## strike runs; afterwards a pause) and RECOVER (the pause; the unit keeps its band). `outmatched`
## widens the band and the spread; `far` keeps the unit at the band's far edge (kiting).
func _decide_ranged(my_position: Vector3, target_pos: Vector3, distance: float, seen: bool,
		memory_ok: bool, target_alive: bool, request_token: Callable, release_token: Callable,
		outmatched: bool, far: bool) -> void:
	if not target_alive and perception.get("exists", false):
		_release(release_token)
		_release_ranged()
		_drop_firing_point()
		aware = false
		_set_state(AIState.PATROL)
		return
	if not memory_ok:
		_release(release_token)
		_release_ranged()
		_drop_firing_point()
		investigating = true
		aware = false
		_set_state(AIState.ALERT)
		return
	face_point = target_pos
	var band := ranged_band(outmatched)
	var spread := ranged_spread_m(outmatched)
	match state:
		AIState.ATTACK:
			_stop_moving()
			if _attack_finished() and _in_state_s() > 0.05:
				strike_ready_tick = now + _ticks(rng.randf_range(float(ai.get("strike_pause_min_s", 0.8)),
					float(ai.get("strike_pause_max_s", 1.4))))
				_release(release_token)
				_release_ranged()
				_set_state(AIState.RECOVER)
			return
		AIState.RECOVER:
			_keep_band(my_position, target_pos, distance, band, spread, far)
			if now >= strike_ready_tick:
				_set_state(AIState.APPROACH)
			return
	if state != AIState.APPROACH:
		_set_state(AIState.APPROACH)
	if seen and now >= strike_ready_tick:
		var edge := distance - float(perception.get("target_radius", 0.85))
		var close := _close_attack_for(edge) if post_band == Vector2.ZERO else ""   # M7 polish: no kick from a post
		var facing_ok := absf(float(perception.get("facing_deg", 180.0))) <= ATTACK_FACING_DEG
		if close != "" and facing_ok and _action_ready(close) and (holds_token or request_token.call()):
			holds_token = true
			attack_request = close
			_stop_moving()
			_set_state(AIState.ATTACK)
			return
		var special := _ranged_special_attack(my_position, target_pos, distance)
		if special != "":
			attack_request = special
			_stop_moving()
			_set_state(AIState.ATTACK)
			return
	_keep_band(my_position, target_pos, distance, band, spread, far)
	if not seen or now < strike_ready_tick or not is_settled(my_position):
		return
	if distance < band.x - BAND_TOLERANCE_M or distance > band.y + BAND_TOLERANCE_M:
		return
	if absf(float(perception.get("facing_deg", 180.0))) > RANGED_FACING_DEG:
		return
	var shot := _ranged_shot()
	if shot == "" or not _action_ready(shot) or not _take_ranged_turn(shot):
		return
	attack_request = shot
	_stop_moving()
	_set_state(AIState.ATTACK)


## Keeps the unit at a firing point in the band: a new one when it holds none, when the target
## moved it out of the band (or, kiting, into the band's near half), after a path failure, and
## every FIRING_REPICK_S while the target is not seen; then it walks there (runs when far or
## retreating), facing the target.
func _keep_band(my_position: Vector3, target_pos: Vector3, distance: float, band: Vector2, spread: float,
		far: bool) -> void:
	var repick := firing_point == Vector3.INF or _firing_blocked
	if not repick:
		var pd := _flat_distance(firing_point, target_pos)
		repick = pd < band.x - BAND_TOLERANCE_M or pd > band.y + BAND_TOLERANCE_M \
			or (far and pd < (band.x + band.y) * 0.5)
	if not repick and not bool(perception.get("visible", false)) and now - _firing_tick >= _ticks(FIRING_REPICK_S):
		repick = true
	if repick and firing_point == Vector3.INF and not _firing_blocked and _firing_retry_tick != NO_TICK \
			and now < _firing_retry_tick:
		repick = false   # M7 gate: the last search found nothing; hold until it may run again
	if post_band != Vector2.ZERO and firing_point != Vector3.INF and not _firing_blocked:
		repick = false   # M7 polish: a post is the one point it holds, whatever the target does
	if repick:
		firing_point = _pick_firing_point(my_position, target_pos, distance, band, spread, far)
		_firing_tick = now
		_firing_blocked = false
		_firing_retry_tick = now + _ticks(FIRING_REPICK_S) if firing_point == Vector3.INF and not nav_search_pending \
			else NO_TICK
	var d := _flat_distance(my_position, firing_point) if firing_point != Vector3.INF else 0.0
	if firing_point == Vector3.INF or d <= FIRING_ARRIVE_M:
		_stop_moving()
	else:
		move_target = firing_point
		move_speed = -1.0 if d > FIRING_RUN_M or distance < band.x else 0.0


func _pick_firing_point(my_position: Vector3, target_pos: Vector3, distance: float, band: Vector2,
		spread: float, far: bool) -> Vector3:
	if firing_point_resolver.is_valid():
		nav_search_pending = false
		return firing_point_resolver.call(my_position, target_pos, band, spread, far)
	return ring_point(my_position, target_pos, distance, band, far)


## The pure fallback firing point: on the ring around the target in this unit's direction, at its
## own distance clamped RING_MARGIN_M inside the band (at the far edge when `far`).
static func ring_point(my_position: Vector3, target_pos: Vector3, distance: float, band: Vector2,
		far: bool) -> Vector3:
	var away := my_position - target_pos
	away.y = 0.0
	away = away.normalized() if away.length() > 0.1 else Vector3.BACK
	var lo := band.x + RING_MARGIN_M
	var hi := maxf(lo, band.y - RING_MARGIN_M)
	var r := hi if far else clampf(distance, lo, hi)
	return Vector3(target_pos.x + away.x * r, my_position.y, target_pos.z + away.z * r)


## A path toward the firing point failed: pick another one (ranged states), otherwise the base rule.
func _ranged_path_failed(my_position: Vector3) -> bool:
	if not is_ranged_state():
		return false
	_firing_blocked = true
	_stop_moving()
	return true
## @anchor P10a
# --- leash return (P10a) ------------------------------------------------------------------------
# RETURN: a leashed unit runs home and ignores every target on the way. EnemyActor's leash
# return drives it (perception and decisions are paused meanwhile, so decide() never sees the
# state): begin_return() when it starts, return_step() every tick, end_return() at home.

## The unit starts walking home: target, awareness, attack request, formation slot and flight
## are dropped (the actor gives its attack tokens back), state RETURN.
func begin_return(tick: int) -> void:
	now = tick
	_leave_hold()
	holds_token = false
	_forget_target()
	flee_point = Vector3.INF
	_resume_after_stagger = -1
	_set_state(AIState.RETURN)


## One tick of the way home: run to `home`, facing the way it runs, still ignoring targets.
func return_step(tick: int, home: Vector3) -> void:
	now = tick
	_forget_target()
	if state != AIState.RETURN:
		_set_state(AIState.RETURN)
	move_target = home
	move_speed = -1.0
	face_point = Vector3.INF


## Home (or dead): stop; IDLE, so patrol resumes and the unit may engage again; DEAD when it
## died on the way. The old perception is dropped: the next perceive() starts afresh.
func end_return(tick: int, alive: bool) -> void:
	now = tick
	_stop()
	_forget_target()
	perception = {}
	_set_state(AIState.IDLE if alive else AIState.DEAD)


func _forget_target() -> void:
	aware = false
	investigating = false
	target_id = ""
	attack_request = ""
## @anchor P11a
# --- boss phases and attack sequences (P11a) -----------------------------------------------------
# Plan §3.12 and §2.8.2: an enemy record's `boss` block lists phases by descending
# health_frac_below; a phase applies at or below its fraction, and phases only ever advance
# (update_boss_phase: a healed boss never returns to an earlier phase's behaviour). A phase's
# `sequence` is cycled in order and its weights are ignored; without one, the phase's attacks are
# a weighted pick. _decide_sequence() runs the engaged states of such a brain: it strikes with the
# current sequence entry when the target lies inside that action's ai band (ai_min_range_m ..
# ai_max_range_m, from the target's capsule surface, as every band) and the entry's facing rule
# allows it; otherwise it closes in or backs off for at most SEQUENCE_PATIENCE_S and then skips the
# entry (a target far beyond the band is simply walked up to: nothing is skipped on the way in).
# Every consumed entry (struck or skipped) is one decision of sequence_log. OgreBossBrain
# runs it; boss_phase_entered reaches the actor (EnemyActor.install_boss_hooks), which announces
# the phase and forces its enter_action.

## A new boss phase began: its number (1-based), the record's phase id and its enter_action ("").
signal boss_phase_entered(phase: int, phase_id: String, enter_action: String)

## How long an out-of-band sequence entry is chased (closing in or backing off) before it is skipped.
const SEQUENCE_PATIENCE_S := 2.0
## The facing a sequence entry needs before it starts, by its telegraph shape: a circle hits all
## round (no facing), a line (the charge, which turns during its windup) 45 degrees, a cone or an
## attack without a telegraph ATTACK_FACING_DEG.
const SEQUENCE_LINE_FACING_DEG := 45.0
## Closing-in and backing-off goals sit this far inside an entry's band.
const SEQUENCE_BAND_MARGIN_M := 1.0
## Patience only runs while the target is at most this far beyond an entry's band; farther off the
## brain is simply closing in (a boss walking up to the giant skips nothing).
const SEQUENCE_CHASE_M := 6.0
## Entries kept in sequence_log.
const SEQUENCE_LOG_SIZE := 64

## The record's boss phases, by descending health_frac_below ([] for an ordinary enemy).
var boss_phases: Array = []
## The current phase (0-based index into boss_phases); it never decreases.
var phase_index := 0
## How far the current phase's sequence has got (entries consumed in this phase).
var sequence_index := 0
## The decisions taken by the sequence, oldest first: the action id of each entry it struck with,
## "skip:<action id>" for each entry it skipped (tests, debug).
var sequence_log: Array[String] = []
var _entry_since := NO_TICK
var _own_radius_m := 0.0
var _weighted_pick := ""


## Reads the record's boss phases (archetype brains call it from _init): sorted by descending
## health_frac_below, the range bands of every phase attack cached, the first phase current.
func init_boss_phases(record: Dictionary) -> void:
	boss_phases = []
	var boss: Variant = record.get("boss")
	if typeof(boss) == TYPE_DICTIONARY and typeof(boss.get("phases")) == TYPE_ARRAY:
		for p: Variant in boss.phases:
			if typeof(p) == TYPE_DICTIONARY:
				boss_phases.append(p)
	boss_phases.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a.get("health_frac_below", 1.0)) > float(b.get("health_frac_below", 1.0)))
	for p: Dictionary in boss_phases:
		for key: String in ["attacks", "sequence"]:
			for id: Variant in p.get(key, []):
				if not _attack_ranges.has(str(id)):
					_cache_attack_range(str(id))
	phase_index = 0
	sequence_index = 0
	_entry_since = NO_TICK
	_own_radius_m = float(record.get("capsule_radius_m", 0.4))


func has_boss_phases() -> bool:
	return not boss_phases.is_empty()


## The current boss phase, 1-based (0 for an enemy without phases).
func boss_phase() -> int:
	return phase_index + 1 if has_boss_phases() else 0


func boss_phase_count() -> int:
	return boss_phases.size()


## The current phase's record ({} without phases).
func phase_record() -> Dictionary:
	return boss_phases[phase_index] if has_boss_phases() else {}


## The current phase's attacks (the record's attacks without phases).
func phase_attacks() -> Array:
	return phase_record().get("attacks", attacks) if has_boss_phases() else attacks


## The current phase's sequence ([] when it has none).
func phase_sequence() -> Array:
	var s: Variant = phase_record().get("sequence", [])
	return s if typeof(s) == TYPE_ARRAY else []


## Advances the boss phase for a health fraction (0..1): the deepest phase whose
## health_frac_below the fraction is at or below. Phases never go back, so each is entered at most
## once. On a change the sequence restarts, a pending request is dropped, the brain waits in
## ATTACK for the phase's enter_action (the actor forces it) and boss_phase_entered is emitted.
## Returns the newly entered phase (1-based), or 0. tick < 0 keeps the brain's last tick.
func update_boss_phase(health_frac: float, tick: int = -1) -> int:
	if not has_boss_phases() or state == AIState.DEAD:
		return 0
	if tick >= 0:
		now = tick
	var deepest := phase_index
	for i in range(phase_index + 1, boss_phases.size()):
		if health_frac <= float((boss_phases[i] as Dictionary).get("health_frac_below", 0.0)) + 1e-6:
			deepest = i
	if deepest == phase_index:
		return 0
	phase_index = deepest
	sequence_index = 0
	_entry_since = NO_TICK
	_weighted_pick = ""
	attack_request = ""
	var p: Dictionary = boss_phases[phase_index]
	var enter := str(p.get("enter_action", ""))
	if enter != "":
		_stop_moving()
		_set_state(AIState.ATTACK)   # wait for the forced enter action, then pause and go on
	boss_phase_entered.emit(phase_index + 1, str(p.get("id", "")), enter)
	return phase_index + 1


## The sequence entry the brain works on now ("" when the phase has no sequence).
func current_sequence_entry() -> String:
	var seq := phase_sequence()
	if seq.is_empty():
		return ""
	return str(seq[sequence_index % seq.size()])


## Consumes the current sequence entry: struck with (performed) or skipped.
func advance_sequence(performed: bool) -> void:
	var id := current_sequence_entry()
	if id == "":
		return
	sequence_log.append(id if performed else "skip:" + id)
	while sequence_log.size() > SEQUENCE_LOG_SIZE:
		sequence_log.pop_front()
	sequence_index += 1
	_entry_since = NO_TICK


## The attack the current phase would pick now: its sequence entry, otherwise a weighted pick
## (own RNG) among its attacks.
func choose_phase_attack() -> String:
	var id := current_sequence_entry()
	if id != "":
		return id
	var list := phase_attacks()
	if list.is_empty():
		return ""
	var weights: Variant = phase_record().get("attack_weights", attack_weights)
	if typeof(weights) != TYPE_ARRAY or (weights as Array).size() != list.size():
		return str(list[0])
	var total := 0.0
	for w: Variant in weights:
		total += float(w)
	var roll := rng.randf() * total
	for i in list.size():
		roll -= float(weights[i])
		if roll <= 0.0:
			return str(list[i])
	return str(list[list.size() - 1])


## The ai band of an action (from the target's capsule surface; Vector2(0, INF) without one).
func sequence_band(action_id: String) -> Vector2:
	if not _attack_ranges.has(action_id):
		_cache_attack_range(action_id)
	return _attack_ranges.get(action_id, Vector2(0.0, INF))


## The facing (degrees either side) an action needs before it starts: 180 for a circle telegraph,
## SEQUENCE_LINE_FACING_DEG for a line, otherwise ATTACK_FACING_DEG.
static func entry_facing_deg(action_id: String) -> float:
	var t: Variant = GameData.get_record(action_id).get("telegraph")
	if typeof(t) == TYPE_DICTIONARY:
		match str(t.get("shape", "")):
			"circle":
				return 180.0
			"line":
				return SEQUENCE_LINE_FACING_DEG
	return ATTACK_FACING_DEG


## The engaged states of a sequence brain (boss phases): APPROACH works the current entry (strike
## inside its band with a token, else close in or back off, skipped after SEQUENCE_PATIENCE_S),
## ATTACK waits for the strike (and any chained follow-up or forced action) to end, RECOVER pauses
## ai.strike_pause_min_s..max_s. Any other engaged state is treated as APPROACH.
func _decide_sequence(my_position: Vector3, target_pos: Vector3, distance: float, seen: bool,
		memory_ok: bool, target_alive: bool, request_token: Callable, release_token: Callable) -> void:
	if state == AIState.ATTACK:
		face_point = target_pos
		_stop_moving()
		if _attack_finished() and _in_state_s() > 0.05:
			strike_ready_tick = now + _ticks(rng.randf_range(float(ai.get("strike_pause_min_s", 0.5)),
				float(ai.get("strike_pause_max_s", 1.0))))
			_set_state(AIState.RECOVER)
		return
	if not target_alive and perception.get("exists", false):
		_release(release_token)
		aware = false
		_set_state(AIState.PATROL)
		return
	if not memory_ok:
		_release(release_token)
		investigating = true
		aware = false
		_set_state(AIState.ALERT)
		return
	face_point = target_pos
	if state == AIState.RECOVER:
		_stop_moving()
		if now >= strike_ready_tick:
			_release(release_token)
			_set_state(AIState.APPROACH)
		return
	if state != AIState.APPROACH:
		_set_state(AIState.APPROACH)
	var id := current_sequence_entry()
	if id == "":
		# A phase without a sequence: one weighted pick, kept until it is struck with.
		if _weighted_pick == "":
			_weighted_pick = choose_phase_attack()
		id = _weighted_pick
	if id == "":
		_stop_moving()
		return
	var band := sequence_band(id)
	var radius := float(perception.get("target_radius", 0.85))
	var edge := distance - radius
	var away := my_position - target_pos
	away.y = 0.0
	away = away.normalized() if away.length() > 0.1 else Vector3.BACK
	if edge > band.y:
		# Close in to just inside the band (never into the target's capsule).
		var goal := maxf(maxf(band.x, band.y - SEQUENCE_BAND_MARGIN_M), _own_radius_m + 0.25)
		move_target = target_pos + away * (radius + goal)
		move_speed = -1.0
	elif edge < band.x:
		move_target = target_pos + away * (radius + band.x + SEQUENCE_BAND_MARGIN_M)
		move_speed = -1.0
	else:
		_entry_since = NO_TICK
		if _sight_blocked(seen):
			_regain_sight(my_position, target_pos)   # M8 gate (F36): no waiting for a sight line
			return
		_stop_moving()
		var facing_ok := absf(float(perception.get("facing_deg", 180.0))) <= entry_facing_deg(id)
		if seen and facing_ok and now >= strike_ready_tick and (holds_token or request_token.call()):
			holds_token = true
			attack_request = id
			_weighted_pick = ""
			if current_sequence_entry() != "":
				advance_sequence(true)
			_set_state(AIState.ATTACK)
		return
	# Out of the entry's band: chase it for at most SEQUENCE_PATIENCE_S, then skip it. A target
	# farther than SEQUENCE_CHASE_M beyond the band is just walked up to: nothing is skipped on the
	# way in.
	if current_sequence_entry() == "":
		return
	if edge > band.y + SEQUENCE_CHASE_M:
		_entry_since = NO_TICK
		return
	if _entry_since == NO_TICK:
		_entry_since = now
	elif now - _entry_since >= _ticks(SEQUENCE_PATIENCE_S):
		advance_sequence(false)


## A path failure while chasing a sequence entry's band skips the entry (its range cannot be
## reached from here). Returns true when it handled the failure.
func sequence_path_failed() -> bool:
	if state != AIState.APPROACH or current_sequence_entry() == "" or _entry_since == NO_TICK:
		return false
	advance_sequence(false)
	_stop_moving()
	return true
## @anchor P11b
# --- faction members at peace, and awe (P11b) ---------------------------------------------------
# Plan §3.13 designs 2, 3 and 5. A unit with a faction (Thornwick's guards) follows its faction's
# standing, which the actor passes in with set_faction_mode() (EnemyActor's P11b section):
#   ""            hostile, or no faction: the normal AI;
#   "neutral"     HOLD at its post (post_resolver: a formation marker of its faction beside its
#                 home, else home), facing the giant while it sees it (guard up: the actor's
#                 is_guarding), no attacks, no tokens, never aware - so it never defers a checkpoint,
#                 never alerts its encounter and is never leashed;
#   "stood_down"  STAND_DOWN: walks to its post, guard down, faces the way its post faces; never
#                 aware, no attacks.
# Noises and blows do not wake a unit at peace (the faction's standing decides, FactionState);
# a blow only turns it toward the attacker. Morale still recovers; a unit at peace never flees.
# Awe (decision 26): the first time a unit perceives a target at least tactics.awe_ratio times
# its own height it loses tactics.awe_morale_loss morale, once per life (source "awe", applied as
# given: never x1.5). A stage-3 giant (7.92 m) awes soldiers (1.8 m: 4.4 >= 4.0); stage 2 does not.
# M9 gate: tactics.awe_tiers ([{"ratio", "morale_loss"}]) cost more before a larger target
# (awe_loss_at): a soldier's tier at 6.0x makes it flee a stage-4 giant on sight (plan §5.14).

## A unit at peace stands within POST_ARRIVE_M of its post; it walks back once farther than
## POST_LEAVE_M (hysteresis, as HOLD's).
const POST_ARRIVE_M := 0.4
const POST_LEAVE_M := 1.0
## The post is asked for again this often (a claimed marker can be freed by a death).
const POST_REFRESH_S := 1.0

## "" (normal AI), "neutral" or "stood_down" (set_faction_mode).
var faction_mode := ""
## post_resolver() -> {"post": Vector3, "face": Vector3}: where a faction member stands at peace
## and a point to face there (Vector3.INF = keep its facing). The actor installs it; without one
## the unit stays where it was when it made peace.
var post_resolver := Callable()
## True once awe cost this unit morale (once per life).
var awed := false
var _post: Dictionary = {}
var _post_tick := NO_TICK
var _post_moving := false


## Switches the faction behaviour: "" (hostile: the normal AI), "neutral" or "stood_down".
## Making peace drops the target, awareness, tokens (the actor gives them back), a formation
## slot and any flight, and holds (or stands down) from the next decision. Leaving peace returns
## to IDLE, from where a noise - the actor reports the giant - wakes the normal AI.
func set_faction_mode(mode: String, tick: int = -1) -> void:
	if tick >= 0:
		now = tick
	if mode == faction_mode:
		return
	faction_mode = mode
	_post = {}
	_post_tick = NO_TICK
	_post_moving = true
	if mode == "":
		if state in [AIState.HOLD, AIState.STAND_DOWN]:
			_set_state(AIState.IDLE)
		return
	_leave_hold()
	holds_token = false
	_forget_target()
	flee_point = Vector3.INF
	_resume_after_stagger = -1
	_stop()
	if state != AIState.DEAD:
		_set_state(AIState.HOLD if mode == "neutral" else AIState.STAND_DOWN)


## True while the unit is a faction member at peace (neutral or stood down).
func at_peace() -> bool:
	return faction_mode != ""


## The post a unit at peace holds ({} before its first decision at peace).
func peace_post() -> Dictionary:
	return _post.duplicate()


## perceive(): awe for every unit; a unit at peace remembers where the target is (to face it)
## and stays unaware. True when it handled the perception.
func _p11b_perceive(tick: int, snapshot: Dictionary) -> bool:
	_check_awe(snapshot)
	if faction_mode == "":
		return false
	if snapshot.get("exists", false) and snapshot.get("alive", false) and snapshot.get("visible", false):
		target_id = str(snapshot.get("target_id", ""))
		last_known = snapshot.get("position", last_known)
		last_seen_tick = tick
	aware = false
	return true


## Awe: the first perception of a target at least tactics.awe_ratio times this unit's height
## costs tactics.awe_morale_loss morale, once per life - or, M9 gate, the loss of the tactics.awe_tiers
## entry with the largest ratio the target meets (awe_loss_at).
func _check_awe(snapshot: Dictionary) -> void:
	if awed or ignores_morale or state == AIState.DEAD:
		return
	var ratio := float(tactics.get("awe_ratio", 0.0))
	var loss := float(tactics.get("awe_morale_loss", 0.0))
	if ratio <= 0.0 or loss <= 0.0:
		return
	if not (snapshot.get("exists", false) and snapshot.get("alive", false) and snapshot.get("visible", false)):
		return
	var r := size_ratio()
	if r < ratio - 1e-6:
		return
	awed = true
	on_morale_delta(-awe_loss_at(r), "awe", now)


## M9 gate (plan M6-M9 §5.14: from stage 4 "single humans flee on sight (awe at 6.1x)"): the morale the
## awe of a target `ratio` times this unit's height costs - tactics.awe_morale_loss, or the morale_loss
## of the tactics.awe_tiers entry with the largest ratio the target meets. A lone soldier's 35 of its 70
## left it above its flee threshold of 25 before a stage-4 giant (10.97 m: 6.1x), so it fought to the end
## (the M9 confirmation: the melee lone humans fled 0 % of their engaged time at stages 4-6); its tier at
## 6.0x costs enough to send it running. Below the first tier (a stage-3 giant is 4.4x a soldier: the
## Valley) the base loss holds, so the Valley's stages 1-3 are as they were.
func awe_loss_at(ratio: float) -> float:
	var loss := float(tactics.get("awe_morale_loss", 0.0))
	var best := -INF
	var tiers: Variant = tactics.get("awe_tiers", [])
	if typeof(tiers) != TYPE_ARRAY:
		return loss
	for t: Variant in tiers:
		if typeof(t) != TYPE_DICTIONARY:
			continue
		var at := float((t as Dictionary).get("ratio", 0.0))
		if at > 0.0 and ratio >= at - 1e-6 and at > best:
			best = at
			loss = float((t as Dictionary).get("morale_loss", loss))
	return loss


## on_noise() at peace: a blow turns the unit toward the attacker; nothing makes it aware.
func _p11b_heard_in_peace(tick: int, position: Vector3, source_id: String, certain: bool) -> bool:
	if faction_mode == "":
		return false
	if certain:
		last_known = position
		target_id = source_id
		last_seen_tick = tick
	aware = false
	return true


## decide() at peace: walk to the post, then hold it (HOLD: facing the target while it is seen,
## otherwise the post's facing) or stand down (STAND_DOWN: the post's facing). True when handled.
func _p11b_decide(my_position: Vector3, release_token: Callable) -> bool:
	if faction_mode == "":
		return false
	_release(release_token)
	aware = false
	attack_request = ""
	var post := _current_post(my_position)
	var at: Vector3 = post.get("post", my_position)
	var d := _flat_distance(my_position, at)
	if d > POST_LEAVE_M:
		_post_moving = true
	if _post_moving and d > POST_ARRIVE_M:
		move_target = at
		move_speed = 0.0
	else:
		_post_moving = false
		_stop_moving()
	var face: Vector3 = post.get("face", Vector3.INF)
	if faction_mode == "neutral":
		_set_state(AIState.HOLD)
		var watching := last_seen_tick > NO_TICK and now - last_seen_tick <= _ticks(float(ai.get("memory_s", 3.0)))
		if watching:
			face_point = last_known
		else:
			face_point = Vector3.INF if _post_moving else face
	else:
		_set_state(AIState.STAND_DOWN)
		face_point = Vector3.INF if _post_moving else face
	return true


func _current_post(my_position: Vector3) -> Dictionary:
	if not _post.is_empty() and now - _post_tick < _ticks(POST_REFRESH_S):
		return _post
	_post_tick = now
	var resolved: Variant = post_resolver.call() if post_resolver.is_valid() else null
	if typeof(resolved) == TYPE_DICTIONARY and (resolved as Dictionary).has("post"):
		_post = resolved
	elif _post.is_empty():
		_post = {"post": my_position, "face": Vector3.INF}
	return _post


# --------------------------------------------------------------------------- package anchors (M6-M9)
# Written by P20 (plan M6-M9 §1.5): a package adds its code directly below its own anchor.

## @anchor P22
# --- ranged units keep to the camera's side; posts asked again (P22) -----------------------------
# Plan M6-M9 §3.4 design 8 (the M5 off-camera share: 22-24 % of hits against a target under 20 %).
# A ranged unit with tactics.front_arc_deg prefers firing points in front of the giant's camera
# (the actor's resolver, EnemyActor.front_arc_firing_point). keep_front_arc() lets it give up a held
# point that left the arc - at most every FRONT_ARC_REPICK_S, and only once the camera has turned
# FRONT_ARC_REPICK_YAW_DEG since its last pick (so a point with no better place in the arc is not
# searched again and again) - and prepare_ranged_shot() tells the actor whether a shot is drawn
# from outside the camera's view (its windup then lasts tactics.off_camera_aim_s).

const FRONT_ARC_REPICK_S := 3.0
const FRONT_ARC_REPICK_YAW_DEG := 20.0

## view_probe() -> {"yaw": the giant's camera yaw, "on_camera": this unit in its view} ({} = no
## camera). The actor installs it (EnemyActor.camera_view); unset, nothing changes.
var view_probe := Callable()
## shot_preparer(shot_id: String, off_camera: bool) -> void: the actor readies the shot's windup
## (EnemyActor.prepare_shot).
var shot_preparer := Callable()
var _arc_pick_tick := NO_TICK
var _arc_pick_yaw := INF


## True when `point`, seen from `target_pos`, lies within `arc_deg` / 2 of `cam_yaw`: the camera
## looks over the target toward it, so it is on screen. Pure.
static func in_front_arc(point: Vector3, target_pos: Vector3, cam_yaw: float, arc_deg: float) -> bool:
	var d := point - target_pos
	d.y = 0.0
	if d.length_squared() < 1e-4:
		return true
	return absf(angle_difference(cam_yaw, TargetingRules.yaw_of(d))) <= deg_to_rad(arc_deg) * 0.5 + 1e-4


## The giant's camera as the actor reports it ({} without one or without a probe).
func camera_view() -> Dictionary:
	var v: Variant = view_probe.call() if view_probe.is_valid() else {}
	return v if typeof(v) == TYPE_DICTIONARY else {}


## Before `shot_id` starts: the actor learns whether it is drawn from outside the camera's view.
func prepare_ranged_shot(shot_id: String) -> void:
	if shot_id == "" or not shot_preparer.is_valid():
		return
	var view := camera_view()
	shot_preparer.call(shot_id, not view.is_empty() and not bool(view.get("on_camera", true)))


## After decide() (ranged brains): a new firing point remembers the camera's yaw; a held point
## outside the front arc is given up (the next decision picks again, in the arc when it can) - not
## during a shot, at most every FRONT_ARC_REPICK_S, and only when the camera turned since the pick.
## `before` is the firing point before decide().
func keep_front_arc(before: Vector3) -> void:
	var arc := float(tactics.get("front_arc_deg", 0.0))
	if arc <= 0.0 or post_band != Vector2.ZERO:
		return   # M7 polish: a unit on its post has no other point to go to
	var view := camera_view()
	if view.is_empty():
		return
	var yaw := float(view.get("yaw", 0.0))
	if firing_point != before:
		if firing_point != Vector3.INF:
			_arc_pick_tick = now
			_arc_pick_yaw = yaw
		return
	if firing_point == Vector3.INF or not (state in [AIState.APPROACH, AIState.RECOVER]):
		return
	if now - _arc_pick_tick < _ticks(FRONT_ARC_REPICK_S) or in_front_arc(firing_point, last_known, yaw, arc):
		return
	if _arc_pick_yaw != INF and absf(rad_to_deg(angle_difference(_arc_pick_yaw, yaw))) < FRONT_ARC_REPICK_YAW_DEG:
		return
	_drop_firing_point()
	_arc_pick_tick = now
	_arc_pick_yaw = yaw


## Asks the post_resolver again at the next decision (a member at peace stepping back from a
## fight, or back to its post: EnemyActor's P22 section).
func refresh_post() -> void:
	_post_tick = NO_TICK

## @anchor P24b
# --- searches that wait for the path-query budget (M7 gate) ----------------------------------------
# In a streamed world a firing-point, flee or rout search spends NavQuery's per-tick budget a
# candidate at a time (EnemyActor's P24b section). A resolver that stopped for the budget returns
# Vector3.INF and sets nav_search_pending: the brain then waits where it stands and asks again at its
# next decision, where the search resumes - a flight is not taken for "cornered" meanwhile. A firing
# point search that found nothing (not pending) waits FIRING_REPICK_S before the next one (it used to
# run again at every decision: 32-34 queries a tick for a target 200 m away).

## True when the last resolver call (firing point, flee or rout point) stopped for this tick's
## path-query budget: it resumes at the next decision.
var nav_search_pending := false
## The firing point search found nothing: no new one before this tick (NO_TICK = none waits).
var _firing_retry_tick := NO_TICK

## @anchor P30
# --- formation members, the banner's morale, joining (P30) -----------------------------------------
# Plan M6-M9 §2.10, decision 19. Hook lines: decide() (_p30_decide, after the flight check, before
# the state machine) and apply_morale() (_p30_morale_scale). The actor (EnemyActor's P30 section)
# installs the resolvers and calls join_formation / leave_formation; the Formation sets
# formation_hold, formation_braced and banner_alive at every update.
#   * A member of an intact formation holds the slot formation_slot_resolver gives - walking to it
#     (running when it is more than 4 m away) with HOLD's hysteresis - facing the point
#     formation_face_resolver gives, and never asks for an attack of its own: the formation braces
#     through it. A member of a broken formation fights on its own (the rules above).
#   * While its banner lives a member loses half the morale of awe and ally deaths; its leader is the
#     banner (the actor's has_leader), so it regroups to its slot once its morale passes
#     ai.regroup_morale.
#   * An outmatched soldier (behaviour "formation") outside any formation asks formation_joiner every
#     JOIN_RETRY_S while aware; when no formation takes it and the giant is of stage
#     JOIN_OR_FLEE_STAGE or more (perception's target_stage), it flees and routs at once (plan
#     §5.14: single humans flee a stage-4 giant on sight); smaller giants leave it P04's line.

const BANNER_LOSS_MULT := 0.5
## The morale losses a living banner halves (P11b's awe and P04's ally deaths).
const BANNER_HALVED_SOURCES := ["ally_died", "awe"]
const JOIN_RETRY_S := 0.5
const JOIN_OR_FLEE_STAGE := 4

## The formation this unit belongs to ("" = none), whether it holds (formed, advancing, braced)
## and is braced, whether its banner lives, and whether this unit is that banner.
var formation_id := ""
var formation_hold := false
var formation_braced := false
var banner_alive := false
var is_banner := false
## formation_slot_resolver() -> Vector3: where this member stands (INF = none);
var formation_slot_resolver := Callable()
## formation_face_resolver() -> Vector3: the point it faces (the threat, else ahead; INF = keep);
var formation_face_resolver := Callable()
## formation_joiner() -> bool: an outmatched soldier joins a formation now (true when taken).
var formation_joiner := Callable()
var _p30_join_tick := NO_TICK
var _p30_slot_moving := false


## The actor puts this unit in formation `id` (as its banner when `banner`). `fresh` (it spawned
## into it): its morale becomes `morale_start`; otherwise it keeps its morale and recovers toward
## the higher of its own and the formation's.
func join_formation(id: String, banner: bool, morale_start: float, fresh: bool, tick: int = -1) -> void:
	if tick >= 0:
		now = tick
	formation_id = id
	is_banner = banner
	_leave_hold()
	if fresh:
		morale = morale_start
		start_morale = morale_start
	else:
		start_morale = maxf(start_morale, morale_start)
	_p30_slot_moving = true


## Out of its formation (dissolved, or broken away for good): the rules above again.
func leave_formation() -> void:
	formation_id = ""
	formation_hold = false
	formation_braced = false
	banner_alive = false
	is_banner = false
	if state == AIState.HOLD and not _hold_mode:
		_set_state(AIState.APPROACH if aware else AIState.IDLE)


## Flight and rout now (EnemyActor.p30_force_rout: tests, scripted routs).
func force_rout(tick: int = -1) -> void:
	if tick >= 0:
		now = tick
	if state == AIState.DEAD or ignores_morale:
		return
	holds_token = false
	attack_request = ""
	_begin_flee()
	_rout()


func _p30_morale_scale(delta: float, reason: String) -> float:
	if delta < 0.0 and banner_alive and formation_id != "" and not is_banner and BANNER_HALVED_SOURCES.has(reason):
		return delta * BANNER_LOSS_MULT
	return delta


## decide(): true when it handled the decision (see the section notes).
func _p30_decide(my_position: Vector3, memory_ok: bool, target_alive: bool, release_token: Callable) -> bool:
	if state in [AIState.FLEE, AIState.ROUTED, AIState.DEAD, AIState.STAGGERED, AIState.RETURN] or faction_mode != "":
		return false
	if formation_id != "":
		if not formation_hold:
			return false
		_p30_hold_slot(my_position, release_token)
		return true
	if not aware or not memory_ok or not target_alive or outmatched_behavior() != "formation":
		return false
	if formation_joiner.is_valid() and (_p30_join_tick == NO_TICK or now - _p30_join_tick >= _ticks(JOIN_RETRY_S)):
		_p30_join_tick = now
		if bool(formation_joiner.call()) and formation_id != "":
			_p30_hold_slot(my_position, release_token)
			return true
	if int(perception.get("target_stage", 0)) >= JOIN_OR_FLEE_STAGE and not ignores_morale and not is_banner:
		_release(release_token)
		_begin_flee()
		_rout()
		return true
	return false


## A formation member's decision: walk to its slot (run when far), face the formation's point, no
## attacks of its own; state HOLD.
func _p30_hold_slot(my_position: Vector3, release_token: Callable) -> void:
	_release(release_token)
	attack_request = ""
	if _hold_mode:
		_leave_hold()
	var slot: Vector3 = formation_slot_resolver.call() if formation_slot_resolver.is_valid() else Vector3.INF
	var to_slot := _flat_distance(my_position, slot) if slot != Vector3.INF else 0.0
	if to_slot > HOLD_LEAVE_M:
		_p30_slot_moving = true
	if _p30_slot_moving and to_slot > HOLD_ARRIVE_M:
		move_target = slot
		move_speed = -1.0 if to_slot > 4.0 else 0.0
	else:
		_p30_slot_moving = false
		_stop_moving()
	face_point = formation_face_resolver.call() if formation_face_resolver.is_valid() else Vector3.INF
	if state != AIState.HOLD:
		_set_state(AIState.HOLD)

## @anchor P32
# --- siege crews and the siege morale debounce (P32) ---------------------------------------------
# Plan M6-M9 §2.10, §3.16, §5.11, decision 21. Hook lines: decide() (_p32_decide, after the flight
# check, before P30's) and on_morale_event() (_p32_debounced). The actor (EnemyActor's P32 section)
# installs crew_slot_resolver and crew_face_resolver when an engine takes it (SiegeEngine.add_crew ->
# EnemyActor.p32_assign_engine) and calls crew_engine_lost() when that engine breaks or a giant seizes
# it.
#   * The siege morale event ("siege_destroyed", -20) counts once per SIEGE_DEBOUNCE_S per unit: two
#     engines breaking within 2 s cost a soldier 20 morale once.
#   * A siege crew (tactics.outmatched_behavior "crew": the enemy schema ties it to the record's role
#     "crew") serves its engine: it walks to its place beside it (running when that is more than 4 m
#     away, with HOLD's hysteresis), faces the giant while it knows where it is (else the point
#     crew_face_resolver gives: the engine's front) and asks for no attack and no token of its own -
#     its engine asks it to haul (EnemyActor.p32_crew_reload). State HOLD. Its morale can still break
#     (FLEE); regrouped, it walks back to its place.
#   * Without an engine - its engine broke or a giant seized it, or none took it within CREW_WAIT_S
#     of its first decision - it runs and routs: a crew without an engine is out of the fight.

const SIEGE_EVENT := "siege_destroyed"
const SIEGE_DEBOUNCE_S := 2.0
const CREW_BEHAVIOR := "crew"
## A crew member no engine took within this long after its first decision runs.
const CREW_WAIT_S := 3.0
## A crew member counts as at its place within this distance (the haul starts there).
const CREW_AT_SLOT_M := 1.0

## crew_slot_resolver() -> Vector3: the crew member's place beside its engine (INF = none);
var crew_slot_resolver := Callable()
## crew_face_resolver() -> Vector3: the point it faces while it does not know where the giant is
## (INF = keep its facing);
var crew_face_resolver := Callable()
## crew_engine_check() -> bool: its engine is still there (false: it vanished - freed or out of the
## tree - and the member runs as if it broke).
var crew_engine_check := Callable()
## True while an engine has it; crew_lost once that engine is gone (it routed).
var crew_serving := false
var crew_lost := false
var _p32_siege_tick := NO_TICK
var _p32_wait_since := NO_TICK
var _p32_slot_moving := false


## True for a siege crew member (see the section notes).
func is_crew() -> bool:
	return str(tactics.get("outmatched_behavior", "")) == CREW_BEHAVIOR


## An engine took this crew member (the actor has installed the resolvers): it serves it.
func crew_engine_assigned(tick: int = -1) -> void:
	if tick >= 0:
		now = tick
	crew_serving = true
	crew_lost = false
	_p32_slot_moving = true
	_p32_wait_since = NO_TICK


## Its engine broke or a giant seized it: it gives up its place, runs and routs (once).
func crew_engine_lost(tick: int = -1) -> void:
	if tick >= 0:
		now = tick
	crew_serving = false
	crew_lost = true
	crew_slot_resolver = Callable()
	crew_face_resolver = Callable()
	crew_engine_check = Callable()
	if state != AIState.ROUTED:
		force_rout(now)


## True while it stands at its place beside its engine (HOLD, within CREW_AT_SLOT_M; tests, the haul).
func crew_at_slot(my_position: Vector3) -> bool:
	if not crew_serving or state != AIState.HOLD or not crew_slot_resolver.is_valid():
		return false
	var slot: Vector3 = crew_slot_resolver.call()
	return slot != Vector3.INF and _flat_distance(my_position, slot) <= CREW_AT_SLOT_M


## on_morale_event(): true when this "siege_destroyed" falls within SIEGE_DEBOUNCE_S of the last one
## that counted (it costs nothing).
func _p32_debounced(key: String, tick: int) -> bool:
	if key != SIEGE_EVENT:
		return false
	var t := tick if tick >= 0 else now
	if _p32_siege_tick != NO_TICK and t - _p32_siege_tick < _ticks(SIEGE_DEBOUNCE_S):
		return true
	_p32_siege_tick = t
	return false


## decide(): true when it handled the decision (a crew member that is neither fleeing, routed,
## staggered, returning home nor at peace).
func _p32_decide(my_position: Vector3, memory_ok: bool, target_pos: Vector3, release_token: Callable) -> bool:
	if not is_crew() or faction_mode != "" \
			or state in [AIState.FLEE, AIState.ROUTED, AIState.DEAD, AIState.STAGGERED, AIState.RETURN]:
		return false
	_release(release_token)
	attack_request = ""
	var threat := target_pos if aware and memory_ok else Vector3.INF
	if crew_serving and crew_engine_check.is_valid() and not bool(crew_engine_check.call()):
		crew_engine_lost(now)   # its engine vanished (freed, or out of the tree): out of the fight
		return true
	if not crew_serving:
		if _p32_wait_since == NO_TICK:
			_p32_wait_since = now
		if crew_lost or now - _p32_wait_since >= _ticks(CREW_WAIT_S):
			crew_engine_lost(now)
			return true
		_stop_moving()
		face_point = threat
		if state != AIState.HOLD:
			_set_state(AIState.HOLD)
		return true
	var slot: Vector3 = crew_slot_resolver.call() if crew_slot_resolver.is_valid() else Vector3.INF
	var to_slot := _flat_distance(my_position, slot) if slot != Vector3.INF else 0.0
	if to_slot > HOLD_LEAVE_M:
		_p32_slot_moving = true
	if _p32_slot_moving and to_slot > HOLD_ARRIVE_M:
		move_target = slot
		move_speed = -1.0 if to_slot > 4.0 else 0.0
	else:
		_p32_slot_moving = false
		_stop_moving()
	face_point = threat if threat != Vector3.INF \
		else (crew_face_resolver.call() if crew_face_resolver.is_valid() else Vector3.INF)
	if state != AIState.HOLD:
		_set_state(AIState.HOLD)
	return true

## @anchor P34
# --- in reach but out of sight (M8 gate F36) -------------------------------------------------------
# A brain whose target stands inside its reach (the melee approach's attack range, a sequence entry's
# band) used to stop there and strike only once it could see the target. With something between its
# eye and the target - a scenery trunk in the Troll Den, a pillar, a stone of the Moot - that never came
# while blows kept its memory fresh: the Troll Matriarch stood still for a minute while the giant hit
# her. Now, only in that case (perception "occluded": in sight range and in the view cone, the sight
# line blocked), the brain walks round the target at its distance, the way reposition_sign says, and
# turns back after SIGHT_SWEEP_S without sight; the moment it sees the target it stops and strikes as
# before. A target out of the cone or out of range is not "occluded" (the brain turns to it, as ever).

## Seconds a search for sight goes one way round before it tries the other.
const SIGHT_SWEEP_S := 2.5
## How far round the target (radians, at the brain's distance) the search's walk goal lies.
const SIGHT_STEP_RAD := 0.6
## A search that was not stepped for this long is a new one.
const SIGHT_SEARCH_GAP_S := 0.5

var _sight_search_tick := NO_TICK
var _sight_step_tick := NO_TICK


## True when the target is in sight range and in the view cone but hidden (perception "occluded") and
## `seen` is false.
func _sight_blocked(seen: bool) -> bool:
	return not seen and bool(perception.get("occluded", false))


## One step of the search for sight: a walk goal round `target_pos` at the current distance.
func _regain_sight(my_position: Vector3, target_pos: Vector3) -> void:
	if _sight_search_tick == NO_TICK or now - _sight_step_tick > _ticks(SIGHT_SEARCH_GAP_S):
		_sight_search_tick = now
	elif now - _sight_search_tick >= _ticks(SIGHT_SWEEP_S):
		_sight_search_tick = now
		reposition_sign = -reposition_sign   # still hidden: the other way round
	_sight_step_tick = now
	var offset := my_position - target_pos
	offset.y = 0.0
	if offset.length() < 0.1:
		offset = Vector3.FORWARD
	move_target = target_pos + offset.rotated(Vector3.UP, SIGHT_STEP_RAD * reposition_sign)
	move_speed = 0.0   # walk

## @anchor P37
