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
			if distance <= attack_range:
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
		flee_point = Vector3.INF
		_set_state(AIState.APPROACH if aware else AIState.ALERT)
		return
	if needs_leader and not leader \
			and now - _no_leader_since >= _ticks(float(ai.get("rout_after_s", 20.0))):
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
		var p: Vector3 = flee_resolver.call(my_position, threat, dist)
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
		var close := _close_attack_for(edge)
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
	if repick:
		firing_point = _pick_firing_point(my_position, target_pos, distance, band, spread, far)
		_firing_tick = now
		_firing_blocked = false
	var d := _flat_distance(my_position, firing_point) if firing_point != Vector3.INF else 0.0
	if firing_point == Vector3.INF or d <= FIRING_ARRIVE_M:
		_stop_moving()
	else:
		move_target = firing_point
		move_speed = -1.0 if d > FIRING_RUN_M or distance < band.x else 0.0


func _pick_firing_point(my_position: Vector3, target_pos: Vector3, distance: float, band: Vector2,
		spread: float, far: bool) -> Vector3:
	if firing_point_resolver.is_valid():
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
		_stop_moving()
		_entry_since = NO_TICK
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
