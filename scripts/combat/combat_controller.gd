class_name CombatController
extends RefCounted
## One actor's combat state machine (spec section 6).
##
## Owns action state, validation, cost/cooldown commitment, timelines, cancel windows, the
## one-slot input buffer, block/parry timing, dodge invulnerability, stagger and death. It
## never touches the engine: actors read its state to drive movement, hit queries and
## presentation, and feed it requests. Everything advances in whole 60 Hz ticks.
##
## Per tick the owner calls begin_tick(now) first (advances timelines, may consume the
## buffered request), then request(...) for new inputs.
##
## States: ATTACKING (light/heavy/enemy_attack), CASTING (ability/ultimate), EXECUTING (actions
## whose hit_shape is "grab"; advances like CASTING), DODGING, BLOCKING, STAGGERED, GRABBED
## (held by another actor: no timeline, no stagger; leaves only via release_grabbed or death)
## and DEAD.

enum State { LOCOMOTION, ATTACKING, BLOCKING, DODGING, CASTING, STAGGERED, GRABBED, EXECUTING, DEAD }
const STATE_NAMES := ["Locomotion", "Attacking", "Blocking", "Dodging", "Casting", "Staggered",
	"Grabbed", "Executing", "Dead"]
## States whose action timeline advances in begin_tick.
const TIMELINE_STATES := [State.ATTACKING, State.CASTING, State.DODGING, State.EXECUTING]

enum Verdict { ACCEPT, RETRY, REJECT }

signal action_started(action: ActionDef, instance_id: int)
signal action_ended(action: ActionDef, instance_id: int, interrupted: bool)
signal request_rejected(kind: StringName, action_id: String, reason: String)
signal state_changed(old_state: int, new_state: int)
signal staggered(duration_s: float, reason: String)
## Emitted whenever phase() changes while an action runs, including the first phase on accept
## (after action_started). Not emitted when an action finishes (see action_ended).
signal phase_entered(action: ActionDef, instance_id: int, phase: int)

var actor_id := ""
var combatant: Combatant
var state: int = State.LOCOMOTION
var action: ActionDef = null
var instance_id := 0
var elapsed := 0                    ## ticks since the current action was accepted
var now := 0
var growth_stage := 1
var on_floor := true
## Dexterity: multiplies the recovery ticks of attack kinds (light, heavy, ability, ultimate,
## enemy_attack) only. Windup, active, parry and dodge timing never change.
var recovery_scale := 1.0
## Character level for unlock_level gating. 99 = gating off (sandbox, tests).
var level := 99
## Action id -> true: taught early by a reward; skips the unlock_level check.
var level_exempt := {}
var held_by := ""                   ## holder id while GRABBED
var holding_id := ""                ## target id while this actor holds something (PlayerGrab)

var cooldowns := Cooldowns.new()
var buffer := InputBuffer.new()
var hit_registry := HitRegistry.new()

## Loadout: "light" (chain start), "heavy", "dodge", "block", "jump", "slot_1".."slot_8",
## "ultimate" -> action id ("" = empty). Library: every ActionDef this actor may run.
var loadout: Dictionary = {}
var library: Dictionary = {}

var chain_next_id := ""
var chain_expire_tick := -1

var block_def: ActionDef = null
var block_start_tick := -1
var block_held := false
var parry_available := false
var min_block_ticks := 12           ## a tapped block still gets its full parry window

var stagger_ticks_left := 0
var stagger_reason := ""
var last_reject_reason := ""
var last_reject_tick := -1

var _instance_source: Callable = Callable()
var _local_instance_counter := 0
var _timeline_recovery := 0         ## recovery ticks of the running action after Dexterity


func _init(p_actor_id: String, p_combatant: Combatant) -> void:
	actor_id = p_actor_id
	combatant = p_combatant
	if combatant != null:
		recovery_scale = combatant.recovery_scale()


func set_instance_source(source: Callable) -> void:
	_instance_source = source


func add_action(def: ActionDef) -> void:
	if def != null:
		library[def.id] = def


func set_growth_stage(stage: int) -> void:
	growth_stage = stage


# --------------------------------------------------------------------------- queries

func phase() -> int:
	if action == null:
		return ActionDef.Phase.NONE
	if elapsed < action.windup_ticks:
		return ActionDef.Phase.WINDUP
	if elapsed < action.windup_ticks + action.active_ticks:
		return ActionDef.Phase.ACTIVE
	if elapsed < _total_ticks():
		return ActionDef.Phase.RECOVERY
	return ActionDef.Phase.DONE


func ticks_in_phase() -> int:
	match phase():
		ActionDef.Phase.WINDUP:
			return elapsed
		ActionDef.Phase.ACTIVE:
			return elapsed - action.windup_ticks
		ActionDef.Phase.RECOVERY:
			return elapsed - action.windup_ticks - action.active_ticks
	return 0


## Progress through the current phase, 0..1 (for presentation).
func phase_fraction() -> float:
	if action == null:
		return 0.0
	match phase():
		ActionDef.Phase.WINDUP:
			return float(elapsed) / maxf(1.0, action.windup_ticks)
		ActionDef.Phase.ACTIVE:
			return float(elapsed - action.windup_ticks + 1) / maxf(1.0, action.active_ticks)
		ActionDef.Phase.RECOVERY:
			return float(elapsed - action.windup_ticks - action.active_ticks) / maxf(1.0, _timeline_recovery)
	return 1.0


## Fraction of the active arc reached by the END of the current tick (0 at its start).
func active_fraction() -> float:
	if action == null or action.active_ticks <= 0:
		return 0.0
	return clampf(float(elapsed - action.windup_ticks + 1) / action.active_ticks, 0.0, 1.0)


func active_fraction_prev() -> float:
	if action == null or action.active_ticks <= 0:
		return 0.0
	return clampf(float(elapsed - action.windup_ticks) / action.active_ticks, 0.0, 1.0)


func is_first_active_tick() -> bool:
	return action != null and elapsed == action.windup_ticks and action.active_ticks > 0


func is_invulnerable() -> bool:
	return state == State.DODGING and action != null \
		and elapsed >= action.iframe_start_tick and elapsed < action.iframe_end_tick


func block_elapsed_ticks() -> int:
	return now - block_start_tick if state == State.BLOCKING else -1


func is_committed() -> bool:
	return state in [State.ATTACKING, State.CASTING, State.DODGING, State.STAGGERED,
		State.GRABBED, State.EXECUTING, State.DEAD]


func can_rotate() -> bool:
	match state:
		State.LOCOMOTION, State.BLOCKING:
			return true
		State.ATTACKING, State.CASTING, State.EXECUTING:
			return phase() == ActionDef.Phase.WINDUP
	return false


## The state's own multiplier times the combatant's slow multiplier (1.0 without statuses).
func move_speed_multiplier() -> float:
	var base := 0.0
	match state:
		State.LOCOMOTION:
			base = 1.0
		State.BLOCKING:
			base = float(block_def.param("move_speed_mult", 0.4)) if block_def != null else 0.4
		State.ATTACKING, State.CASTING, State.EXECUTING:
			base = action.move_mult(phase()) if action != null else 0.0
	if combatant != null and base != 0.0:
		base *= combatant.move_mult()
	return base


## Stamina regeneration pauses while sprinting, blocking, or committed to an attack/cast/grab.
func stamina_regen_allowed(sprinting: bool) -> bool:
	return not sprinting and not (state in [State.BLOCKING, State.ATTACKING, State.CASTING,
		State.EXECUTING])


func state_name() -> String:
	return STATE_NAMES[state]


func action_id() -> String:
	return action.id if action != null else ""


## The action a light-attack request would start right now (HUD / tests).
func next_light_id() -> String:
	var def := _resolve(&"light", {})
	return def.id if def != null else ""


# --------------------------------------------------------------------------- per tick

func begin_tick(p_now: int) -> void:
	now = p_now
	match state:
		State.ATTACKING, State.CASTING, State.DODGING, State.EXECUTING:
			var before := phase()
			elapsed += 1
			if elapsed >= _total_ticks():
				_finish_action(false)
			else:
				var after := phase()
				if after != before:
					phase_entered.emit(action, instance_id, after)
		State.STAGGERED:
			stagger_ticks_left -= 1
			if stagger_ticks_left <= 0:
				_end_stagger()
		State.BLOCKING:
			if not block_held and now - block_start_tick >= min_block_ticks:
				_set_state(State.LOCOMOTION)
	buffer.expire(now)
	if buffer.has_pending():
		_try_buffered()


func _try_buffered() -> void:
	var kind := buffer.kind
	var params := buffer.params
	var v := _evaluate(kind, params)
	match v.verdict:
		Verdict.ACCEPT:
			buffer.clear()
			_accept(v.action, kind, params)
		Verdict.REJECT:
			buffer.clear()
			_reject(kind, v.action_id, v.reason)
		Verdict.RETRY:
			pass


# --------------------------------------------------------------------------- requests

## kind: &"light", &"heavy", &"dodge", &"block", &"block_release", &"jump", &"slot"
## (params.slot = 1..8), &"ultimate", or &"attack" (params.action_id, used by AI).
## params may carry "precheck": Callable() -> String (a reject reason, "" = ok). It runs last,
## only when everything else would accept (also when a buffered request is retried); a
## non-empty reason rejects with that reason and nothing is spent.
func request(kind: StringName, params: Dictionary = {}) -> int:
	if kind == &"block_release":
		block_held = false
		if buffer.kind == &"block":
			buffer.clear()
		return Verdict.ACCEPT
	if kind == &"block":
		block_held = true
	var v := _evaluate(kind, params)
	match v.verdict:
		Verdict.ACCEPT:
			if buffer.has_pending():
				buffer.clear()
			_accept(v.action, kind, params)
		Verdict.RETRY:
			buffer.push(kind, params, now)
		Verdict.REJECT:
			_reject(kind, v.action_id, v.reason)
	return v.verdict


## Side-effect free: the reason request(kind, params) would be rejected with right now, "busy"
## if it would be buffered, "" if it would be accepted. Shares _evaluate() with request(), so
## the HUD can never disagree with the controller.
func preview_reason(kind: StringName, params: Dictionary = {}) -> String:
	if kind == &"block_release":
		return ""
	var v := _evaluate(kind, params)
	match v.verdict:
		Verdict.ACCEPT:
			return ""
		Verdict.RETRY:
			return "busy"
	return str(v.reason)


## Order: dead -> resolve -> unlock_stage ("locked") -> unlock_level ("level_locked", skipped
## for level_exempt ids) -> cooldown -> state ("busy" RETRY) -> airborne -> stamina -> essence
## -> fury -> precheck. RETRY is only for state or timing; everything else is REJECT.
func _evaluate(kind: StringName, params: Dictionary) -> Dictionary:
	var result := {"verdict": Verdict.REJECT, "action": null, "action_id": "", "reason": ""}
	if state == State.DEAD:
		result.reason = "dead"
		return result
	var def := _resolve(kind, params)
	if def == null:
		result.reason = "empty_slot" if kind == &"slot" or kind == &"ultimate" else "unknown_action"
		result.action_id = _slot_id(kind, params)
		return result
	result.action = def
	result.action_id = def.id
	if def.unlock_stage > growth_stage:
		result.reason = "locked"
		return result
	if def.unlock_level > level and not level_exempt.has(def.id):
		result.reason = "level_locked"
		return result
	if not cooldowns.is_ready(def.id, now):
		result.reason = "cooldown"
		return result
	match state:
		State.STAGGERED, State.GRABBED:
			result.verdict = Verdict.RETRY
			result.reason = "busy"
			return result
		State.ATTACKING, State.CASTING, State.DODGING, State.EXECUTING:
			if action == null or not action.allows_cancel(_cancel_group(kind), phase(), ticks_in_phase()):
				result.verdict = Verdict.RETRY
				result.reason = "busy"
				return result
		State.BLOCKING:
			if kind == &"block":
				result.reason = "already_blocking"
				return result
	if kind == &"jump" and not on_floor:
		result.reason = "airborne"
		return result
	if kind == &"dodge" and not on_floor:
		result.verdict = Verdict.RETRY
		result.reason = "airborne"
		return result
	if not combatant.pools.can_spend_stamina(def.stamina_cost):
		result.reason = "stamina"
		return result
	if def.essence_cost > combatant.pools.essence + 1e-6:
		result.reason = "essence"
		return result
	if def.fury_cost > combatant.pools.fury + 1e-6:
		result.reason = "fury"
		return result
	var precheck: Variant = params.get("precheck")
	if typeof(precheck) == TYPE_CALLABLE and (precheck as Callable).is_valid():
		var why := str((precheck as Callable).call())
		if why != "":
			result.reason = why
			return result
	result.verdict = Verdict.ACCEPT
	result.reason = ""
	return result


func _cancel_group(kind: StringName) -> String:
	match kind:
		&"light":
			return "light"
		&"heavy":
			return "heavy"
		&"dodge":
			return "dodge"
		&"block":
			return "block"
		&"jump":
			return "jump"
		&"slot", &"ultimate":
			return "ability"
	return "none"


func _slot_id(kind: StringName, params: Dictionary) -> String:
	match kind:
		&"slot":
			return str(loadout.get("slot_%d" % int(params.get("slot", 0)), ""))
		&"ultimate":
			return str(loadout.get("ultimate", ""))
		&"attack":
			return str(params.get("action_id", ""))
	return str(loadout.get(String(kind), ""))


func _resolve(kind: StringName, params: Dictionary) -> ActionDef:
	var id := ""
	match kind:
		&"light":
			id = str(loadout.get("light", ""))
			var in_light := (state == State.ATTACKING and action != null and action.kind == "light")
			if (in_light or now <= chain_expire_tick) and chain_next_id != "":
				id = chain_next_id
		&"heavy", &"dodge", &"block", &"jump", &"ultimate":
			id = str(loadout.get(String(kind), ""))
		&"slot":
			id = str(loadout.get("slot_%d" % int(params.get("slot", 0)), ""))
		&"attack":
			id = str(params.get("action_id", ""))
	if id == "":
		return null
	return library.get(id)


## Starts `def`. pay = false (force_action) skips costs and the cooldown.
func _accept(def: ActionDef, _kind: StringName, _params: Dictionary, pay := true) -> void:
	if action != null:
		_finish_action(false, true)
	# Costs and cooldown are committed exactly once, here.
	if pay:
		if def.stamina_cost > 0.0:
			combatant.pools.spend_stamina(def.stamina_cost)
		if def.essence_cost > 0.0:
			combatant.pools.spend_essence(def.essence_cost)
		if def.fury_cost > 0.0:
			combatant.pools.spend_fury(def.fury_cost)
		if def.cooldown_s > 0.0:
			cooldowns.start(def.id, def.cooldown_s, now)
	instance_id = _next_instance_id()
	match def.kind:
		"block":
			block_def = def
			block_start_tick = now
			block_held = true
			parry_available = true
			min_block_ticks = ActionDef.seconds_to_ticks(float(def.param("parry_window_s", 0.2)))
			_set_state(State.BLOCKING)
		"jump":
			if state == State.BLOCKING:
				_set_state(State.LOCOMOTION)
		_:
			action = def
			elapsed = 0
			_timeline_recovery = def.recovery_ticks
			if def.is_attack():
				_timeline_recovery = int(roundf(def.recovery_ticks * recovery_scale))
			_set_state(_timeline_state_for(def))
	if def.kind == "light":
		chain_next_id = def.chain_next if def.chain_next != "" else ""
		chain_expire_tick = -1
	elif def.is_attack():
		chain_next_id = ""
		chain_expire_tick = -1
	var started_id := instance_id
	action_started.emit(def, started_id)
	# A listener may already have replaced or ended the action; only report the phase it is in.
	if action == def and instance_id == started_id:
		var p := phase()
		if p == ActionDef.Phase.WINDUP or p == ActionDef.Phase.ACTIVE or p == ActionDef.Phase.RECOVERY:
			phase_entered.emit(def, started_id, p)


static func _timeline_state_for(def: ActionDef) -> int:
	if def.kind == "dodge":
		return State.DODGING
	if def.hit_shape == "grab":
		return State.EXECUTING
	if def.kind == "ability" or def.kind == "ultimate":
		return State.CASTING
	return State.ATTACKING


func _reject(kind: StringName, action_id_value: String, reason: String) -> void:
	last_reject_reason = reason
	last_reject_tick = now
	request_rejected.emit(kind, action_id_value, reason)


func _finish_action(interrupted: bool, canceled := false) -> void:
	if action == null:
		return
	var finished := action
	var finished_id := instance_id
	action = null
	elapsed = 0
	if finished.kind == "light" and not interrupted and not canceled:
		chain_expire_tick = now + finished.chain_window_ticks
	if interrupted:
		chain_next_id = ""
		chain_expire_tick = -1
	hit_registry.forget(finished_id)
	if state in TIMELINE_STATES:
		_set_state(State.LOCOMOTION)
	action_ended.emit(finished, finished_id, interrupted)


func _total_ticks() -> int:
	if action == null:
		return 0
	return action.windup_ticks + action.active_ticks + _timeline_recovery


func _next_instance_id() -> int:
	if _instance_source.is_valid():
		return int(_instance_source.call())
	_local_instance_counter += 1
	return _local_instance_counter


func _set_state(new_state: int) -> void:
	if new_state == state:
		return
	var old := state
	state = new_state
	if old == State.BLOCKING:
		parry_available = false
	state_changed.emit(old, new_state)


## Block is a held stance: if the block input is still held when the actor becomes free to
## block again (its press expired in the buffer, it attacked out of block, a stagger ended),
## resume blocking. The 5 stamina entry cost is charged again, but no parry window opens -
## only a fresh press does. Silent: never emits a rejection.
func resume_held_block() -> bool:
	if not block_held or state == State.BLOCKING or state == State.DEAD or buffer.has_pending():
		return false
	var v := _evaluate(&"block", {})
	if v.verdict != Verdict.ACCEPT:
		return false
	_accept(v.action, &"block", {})
	parry_available = false
	return true


# --------------------------------------------------------------------------- scripted actions

## Scripted follow-up (charge -> wall recovery, the boss phase roar): finishes the current action
## (not interrupted), leaves block, stagger or a grab, clears the buffer, and starts `def`
## without cost, cooldown or state checks. Ignored when dead.
func force_action(def: ActionDef) -> void:
	if def == null or state == State.DEAD:
		return
	_finish_action(false)
	buffer.clear()
	if state == State.STAGGERED:
		stagger_ticks_left = 0
		combatant.poise.end_stagger()
	elif state == State.GRABBED:
		held_by = ""
		combatant.poise.end_stagger()
	_set_state(State.LOCOMOTION)
	_accept(def, &"attack", {}, false)


## Another actor grabbed this one. Allowed from LOCOMOTION, ATTACKING, CASTING, STAGGERED and
## BLOCKING: interrupts the running action (no refund), clears the buffer, ends the stagger and
## enters GRABBED (no timeline, no stagger, poise locked). Returns false otherwise.
func enter_grabbed(holder_id: String) -> bool:
	if not (state in [State.LOCOMOTION, State.ATTACKING, State.CASTING, State.STAGGERED, State.BLOCKING]):
		return false
	if action != null:
		_finish_action(true)
	buffer.clear()
	stagger_ticks_left = 0
	stagger_reason = ""
	combatant.poise.begin_stagger()
	held_by = holder_id
	_set_state(State.GRABBED)
	return true


## The holder let go (thrown, dropped, crushed, interrupted ...): GRABBED -> STAGGERED for
## recovery_s (LOCOMOTION when recovery_s <= 0). Ignored unless GRABBED.
func release_grabbed(reason: String, recovery_s: float = 0.6) -> void:
	if state != State.GRABBED:
		return
	held_by = ""
	if recovery_s <= 0.0:
		combatant.poise.end_stagger()
		_set_state(State.LOCOMOTION)
		return
	stagger_ticks_left = maxi(1, ActionDef.seconds_to_ticks(recovery_s))
	stagger_reason = reason
	combatant.poise.begin_stagger()
	_set_state(State.STAGGERED)
	staggered.emit(recovery_s, reason)


# --------------------------------------------------------------------------- reactions

## A blocked parryable hit inside the parry window that did not parry consumes the window:
## later attacks cannot turn a failed parry into a free defense.
func on_block_impact(failed_parry: bool) -> void:
	if failed_parry:
		parry_available = false


## Hard stagger: interrupts ordinary attacks and casts. No refund for interrupted actions.
## Actions authored with interrupt_policy "super_armor" keep running through their windup and
## active phases (the poise meter still resets); returns false in that case. Their recovery is
## the punish window (P11a: the ogre's recovery punish), where a hard stagger interrupts them
## like any action. Returns false while GRABBED (only the holder's release or death leaves
## GRABBED).
func apply_stagger(seconds: float, reason: String) -> bool:
	if state == State.DEAD or state == State.GRABBED:
		return false
	if action != null and action.interrupt_policy == "super_armor" and phase() != ActionDef.Phase.RECOVERY:
		combatant.poise.value = 0.0
		return false
	if action != null:
		_finish_action(true)
	buffer.clear()
	stagger_ticks_left = maxi(1, ActionDef.seconds_to_ticks(seconds))
	stagger_reason = reason
	combatant.poise.begin_stagger()
	_set_state(State.STAGGERED)
	staggered.emit(seconds, reason)
	return true


func _end_stagger() -> void:
	stagger_ticks_left = 0
	combatant.poise.end_stagger()
	_set_state(State.LOCOMOTION)


func kill() -> void:
	if state == State.DEAD:
		return
	if action != null:
		_finish_action(true)
	buffer.clear()
	stagger_ticks_left = 0
	held_by = ""
	_set_state(State.DEAD)
