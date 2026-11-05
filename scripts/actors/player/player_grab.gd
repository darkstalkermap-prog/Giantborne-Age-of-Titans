class_name PlayerGrab
extends PlayerComponent
## Grab, hold, throw and Crushing Grip (spec §8, plan §3.7, decision 16), plus Boulder Hurl's
## precheck and landing preview: the `grab` component of GiantPlayer.COMPONENTS.
##
## Eligibility (find_candidate / check_target) applies the spec's grab rules and the attachment
## profile in this order, each refusal with its reason code:
##   nothing_in_reach    no enemy within grab_reach_m + grab_lunge_m (horizontal, centre to centre)
##   no_los              the eye cannot see its grab point (WORLD | BREAKABLE)
##   too_tall            it is taller than half the giant
##   too_heavy           its mass class is above the stage's grab_capacity ...
##   too_heavy_to_crush  ... or above the crushing action's grab.max_mass (Crushing Grip: small)
##   immune              "Grab" is in its immunities (the Ogre King)
##   no_attach_profile   its grab_attach is "none" or not one of the stage's grab_attach
##   not_grabbable       actor.can_be_grabbed() is false (dead, already held, dormant)
##   not_staggered       a living target must be STAGGERED (its poise is broken)
## Every grab is a controller request with this check as its precheck, so a refused grab spends
## nothing and reports its code (request_rejected, Events.action_rejected and a HUD warning). The
## check runs again when the hand closes on the first active tick, with the reach alone.
##
## Inputs (edge priority 10, before PlayerInteract's 50):
## - E on a candidate: ability.grab_hold (EXECUTING: a 0.25 s windup whose lunge - the action's
##   motion speed x k - covers at most grab_lunge_m and stops at 0.8 x grab_reach_m; the hand
##   closes on the first active tick; no cost). E while holding puts the body down. With nothing
##   to grab E is left to PlayerInteract (shrines, NPCs); with something that cannot be grabbed
##   and no interactable around, E is refused with the reason.
## - Light or heavy while holding: ability.throw_held, a projectile (visual thrown_body) aimed
##   like Boulder Hurl from the body's centre; the projectile system carries the body
##   (ProjectileSystem.carry_body) and its hits are the throw's ordinary hits.
## - A slot whose action is a crush (Crushing Grip): crush the held body, or grab and crush in
##   one move; then let go (grab.release_after). Every other ability is refused while holding
##   ("holding"), and Boulder Hurl needs throw_boulder in the stage's interaction_permissions.
## - A grab or a throw pressed while the giant is busy (a heavy's recovery) waits QUEUE_TICKS.
##
## While holding: controller.holding_id, a HOLD_SPEED_MULT speed multiplier, a hold_timeout_s
## timeout, the body placed in the hand every tick (SOCKETS: low and to the left in first person)
## and the rig's poses. It lets go when the holder is staggered, grabbed or killed, the target
## dies, the scene unloads, or a growth or a checkpoint is refused because of the hold.
## Boulder Hurl and the throw show their landing point during the windup (ability_effect
## "aim_preview", the splash wide).

const GRAB_ID := "ability.grab_hold"
const THROW_ID := "ability.throw_held"
const HURL_ID := "ability.boulder_hurl"
const HURL_PERMISSION := "throw_boulder"
const MASS_ORDER := ["small", "medium", "large", "immovable"]
## Grab refusals in check order (find_candidate / check_target).
const REASONS := ["nothing_in_reach", "no_los", "too_tall", "too_heavy", "too_heavy_to_crush", "immune",
	"no_attach_profile", "not_grabbable", "not_staggered"]
## The other refusals of this component's prechecks.
const OTHER_REASONS := ["holding", "not_holding", "no_permission"]
const LUNGE_STOP_FRACTION := 0.8
const HOLD_SPEED_MULT := 0.6
const HOLD_TIMEOUT_S := 5.0
const LOS_MASK := HitQueryAdapter.LAYER_WORLD | HitQueryAdapter.LAYER_BREAKABLE
## A grab or throw pressed while the controller is busy is retried this long (the controller
## itself buffers a request for 9 ticks only, shorter than a heavy's recovery).
const QUEUE_TICKS := 36
## The cached candidates (interact prompt, hotbar) are refreshed this often.
const CACHE_TICKS := 3
const PREVIEW_STEP_S := 0.1
const PREVIEW_MAX_S := 5.0
## Release fallbacks beside the giant are this far beyond the two capsules.
const RELEASE_GAP_M := 0.6
## Hand sockets per attachment profile, [third person, first person], in the stage-1 giant's own
## space (x k). One-hand holds use the off (left) hand: the club stays in the right. two_hand
## holds in front with both hands in third person. In first person every hold is low and to the
## left of the view (the camera looks along the giant's facing there), so the held body never
## covers the crosshair.
const SOCKETS := {
	"torso_fist": [Vector3(-0.95, 2.05, -1.35), Vector3(-1.05, 1.75, -1.0)],
	"scruff": [Vector3(-0.95, 2.1, -1.35), Vector3(-1.05, 1.75, -1.0)],
	"two_hand": [Vector3(0.0, 2.3, -1.25), Vector3(-1.05, 1.75, -1.0)],
}
## Where a throw's windup carries the body: above and just behind the off shoulder (two hands:
## overhead).
const THROW_BACK_ONE_HAND := Vector3(-1.0, 4.3, 0.2)
const THROW_BACK_TWO_HAND := Vector3(0.0, 4.6, 0.3)
## A wolf held by the scruff hangs nose up.
const SCRUFF_PITCH_DEG := 55.0

## Seconds until a hold lets go by itself (tests may shorten it).
var hold_timeout_s := HOLD_TIMEOUT_S
var _target: CombatEntity = null
var _target_id := ""
var _attach := ""
var _hold_tick := -1
var _pending: CombatEntity = null
var _lunge_origin := Vector3.INF
var _lunge_set := false
var _queued := &""
var _queued_until := -1
var _cache: Dictionary = {}
var _cache_tick := -1000000
var _base_resolver := Callable()


func setup(p: GiantPlayer) -> void:
	super(p)
	player.ensure_action(GRAB_ID)
	player.ensure_action(THROW_ID)
	var runner := player.attack.runner
	runner.register_shape("grab", _run_grab_shape)
	_base_resolver = runner.launch_resolver
	runner.launch_resolver = _resolve_launch
	player.controller.state_changed.connect(_on_holder_state_changed)
	player.controller.request_rejected.connect(_on_request_rejected)
	Events.entity_died.connect(_on_entity_died)
	Events.projectile_spawned.connect(_on_projectile_spawned)
	Events.growth_blocked.connect(_on_growth_blocked)


# --------------------------------------------------------------------------- queries

func is_holding() -> bool:
	return _target != null and is_instance_valid(_target)


func held_entity() -> CombatEntity:
	return _target if is_holding() else null


func held_id() -> String:
	return _target_id if is_holding() else ""


## The held body's attachment profile ("" when the hand is empty).
func held_attach() -> String:
	return _attach if is_holding() else ""


## Ticks since the hand closed (-1 when it is empty).
func hold_ticks() -> int:
	return Sim.tick - _hold_tick if is_holding() else -1


## The stage's size relative to the stage-1 giant (the sockets scale with it).
func body_scale() -> float:
	return float(player.profile.get("height_m", CombatRules.REFERENCE_HEIGHT_M)) / CombatRules.REFERENCE_HEIGHT_M


func grab_reach() -> float:
	return float(player.profile.get("grab_reach_m", float(player.profile.get("melee_reach_m", 3.5)) + 0.5))


func grab_lunge() -> float:
	return float(player.profile.get("grab_lunge_m", 0.0))


func grab_capacity() -> String:
	return str(player.profile.get("grab_capacity", "small"))


func attach_profiles() -> Array:
	var a: Variant = player.profile.get("grab_attach", ["torso_fist", "scruff"])
	return a if typeof(a) == TYPE_ARRAY else []


static func mass_rank(mass_class: String) -> int:
	return maxi(0, MASS_ORDER.find(mass_class))


## True for actions that crush (hit_shape "grab", grab.mode "crush").
static func is_crush(a: ActionDef) -> bool:
	return a != null and a.hit_shape == "grab" and str(_grab_block(a).get("mode", "")) == "crush"


## A crush action's grab.max_mass ("" = only the stage's capacity limits it).
static func max_mass_of(a: ActionDef) -> String:
	return str(_grab_block(a).get("max_mass", ""))


static func _grab_block(a: ActionDef) -> Dictionary:
	var g: Variant = a.param("grab") if a != null else null
	return g if typeof(g) == TYPE_DICTIONARY else {}


static func _mode_of(a: ActionDef) -> String:
	return "crush" if is_crush(a) else "hold"


## The best target for a grab of `mode` ("hold" or "crush"; max_mass "" = no extra cap) within
## max_distance (default grab_reach_m + grab_lunge_m): {"ok", "reason", "target", "distance"}.
## Candidates are the grabbable actors in reach - the locked target first, then the living
## nearest first, then the dead; the first one check_target passes wins, otherwise the first
## one's reason ("nothing_in_reach" when there is none).
func find_candidate(mode := "hold", max_mass := "", max_distance := -1.0) -> Dictionary:
	var reach := max_distance if max_distance >= 0.0 else grab_reach() + grab_lunge()
	var locked := player.lock.target_id if player.lock.is_locked() else ""
	var cands: Array = []
	for e: CombatEntity in Sim.entities():
		if e == player.entity or not _grabbable_kind(e):
			continue
		var d := _flat_distance(e)
		if d > reach + 1e-4:
			continue
		cands.append({"entity": e, "distance": d, "rank": 0 if e.entity_id == locked else (1 if e.is_alive() else 2)})
	if cands.is_empty():
		return {"ok": false, "reason": "nothing_in_reach", "target": null, "distance": INF}
	cands.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if int(a.rank) != int(b.rank):
			return int(a.rank) < int(b.rank)
		if not is_equal_approx(float(a.distance), float(b.distance)):
			return float(a.distance) < float(b.distance)
		return (a.entity as CombatEntity).entity_id < (b.entity as CombatEntity).entity_id)
	var first := {}
	for c: Dictionary in cands:
		var why := check_target(c.entity, mode, max_mass, reach)
		if why == "":
			return {"ok": true, "reason": "", "target": c.entity, "distance": c.distance}
		if first.is_empty():
			first = {"ok": false, "reason": why, "target": c.entity, "distance": c.distance}
	return first


## "" when `target` may be grabbed now by an action of `mode` within max_distance (horizontal,
## centre to centre; default grab_reach_m + grab_lunge_m), otherwise the reason (REASONS order).
func check_target(target: CombatEntity, mode := "hold", max_mass := "", max_distance := -1.0) -> String:
	if target == null or not is_instance_valid(target) or not _grabbable_kind(target):
		return "nothing_in_reach"
	var reach := max_distance if max_distance >= 0.0 else grab_reach() + grab_lunge()
	if _flat_distance(target) > reach + 1e-4:
		return "nothing_in_reach"
	if not _can_see(target):
		return "no_los"
	if target.combatant.height_m > 0.5 * player.entity.combatant.height_m + 1e-6:
		return "too_tall"
	var mass := mass_rank(target.combatant.mass_class)
	if mass > mass_rank(grab_capacity()):
		return "too_heavy"
	if mode == "crush" and max_mass != "" and mass > mass_rank(max_mass):
		return "too_heavy_to_crush"
	if target.combatant.is_immune_to("Grab"):
		return "immune"
	var attach := _attach_of(target)
	if attach == "none" or not attach_profiles().has(attach):
		return "no_attach_profile"
	if not bool(target.actor.call("can_be_grabbed")):
		return "not_grabbable"
	if target.is_alive() and (target.controller == null
			or target.controller.state != CombatController.State.STAGGERED):
		return "not_staggered"
	return ""


## Why this component refuses `def` now ("" = no objection). While holding: everything but a
## crush ("holding"), and a crush needs the held body within its max_mass. A crush with an empty
## hand needs a grab candidate (`cached`: the candidate refreshed every CACHE_TICKS, for the HUD).
## Boulder Hurl needs the stage's throw_boulder permission.
func ability_reason(def: ActionDef, cached := false) -> String:
	if def == null:
		return ""
	if is_crush(def):
		if is_holding():
			var mm := max_mass_of(def)
			if mm != "" and mass_rank(_target.combatant.mass_class) > mass_rank(mm):
				return "too_heavy_to_crush"
			return ""
		var c := _candidate_cached("crush", max_mass_of(def)) if cached else find_candidate("crush", max_mass_of(def))
		return str(c.reason)
	if is_holding():
		return "holding"
	if def.id == HURL_ID and not (player.profile.get("interaction_permissions", []) as Array).has(HURL_PERMISSION):
		return "no_permission"
	return ""


## Player-facing text of a refusal.
static func reason_text(reason: String) -> String:
	match reason:
		"nothing_in_reach":
			return "Nothing in reach to grab."
		"no_los":
			return "You cannot reach it from here."
		"too_tall":
			return "Too big to grab: it must be half your height or less."
		"too_heavy":
			return "Too heavy for you to lift yet."
		"too_heavy_to_crush":
			return "Too big to crush in your fist."
		"immune":
			return "It cannot be grabbed."
		"no_attach_profile":
			return "You cannot get a grip on that."
		"not_grabbable":
			return "It cannot be grabbed right now."
		"not_staggered":
			return "Stagger it first: break its poise with a heavy blow."
		"holding":
			return "Your hands are full: throw it, crush it or put it down."
		"not_holding":
			return "You are not holding anything."
		"no_permission":
			return "You are too small to hurl boulders yet."
	return reason.capitalize()


# --------------------------------------------------------------------------- requests

## E on a grab candidate (and the Valley bot): ability.grab_hold with the eligibility check as
## its precheck. Returns the controller's verdict; a refusal spends nothing
## (controller.last_reject_reason holds the reason).
func try_grab() -> int:
	return player.controller.request(&"attack", {"action_id": GRAB_ID, "precheck": _grab_precheck})


## Light or heavy while holding (and the bot): ability.throw_held; refused "not_holding" with an
## empty hand.
func try_throw() -> int:
	return player.controller.request(&"attack", {"action_id": THROW_ID, "precheck": _throw_precheck})


## A slot ("slot_1".."slot_8") or the ultimate, requested with ability_reason() as its precheck.
func try_slot(slot_key: String) -> int:
	var params := {"precheck": _slot_precheck.bind(slot_key)}
	if slot_key == "ultimate":
		return player.controller.request(&"ultimate", params)
	params["slot"] = int(slot_key.substr(5))
	return player.controller.request(&"slot", params)


## E while holding: put the body down in front (release "dropped").
func drop() -> bool:
	if not is_holding():
		return false
	release("dropped")
	return true


## Lets go (reason: dropped, crushed, interrupted, holder_died, target_died, timeout, unloaded;
## "thrown" when the projectile system took the body). The body is set down where it is held,
## else beside the giant (front, left, right, behind) or on the giant's own spot
## (EnemyActor.on_released). Emits grab_ended.
func release(reason: String) -> void:
	if _target == null:
		return
	var t := _target
	var id := _target_id
	_target = null
	_target_id = ""
	_attach = ""
	_hold_tick = -1
	_queued = &""
	player.controller.holding_id = ""
	player.motor.set_speed_mult(&"grab", 1.0)
	if reason != "thrown" and is_instance_valid(t) and t.actor != null and is_instance_valid(t.actor):
		t.actor.call("on_released", reason, _release_fallbacks(t))
	Events.grab_ended.emit(Sim.tick, player.entity.entity_id, id, reason)


# --------------------------------------------------------------------------- component hooks

func edge_priority() -> int:
	return 10


func handle_edge(edge: StringName) -> bool:
	match edge:
		&"interact":
			return _on_interact()
		&"light", &"heavy":
			if not (is_holding() or _grab_running()):
				return false
			_queue(&"throw")
			return true
	var s := String(edge)
	if edge == &"ultimate" or s.begins_with("slot_"):
		var key := "ultimate" if edge == &"ultimate" else s
		if not handles_slot(key):
			return false
		try_slot(key)
		return true
	return false


## Whether a slot's request goes through this component: while holding or grabbing, and for
## crush actions and Boulder Hurl.
func handles_slot(slot_key: String) -> bool:
	if is_holding() or _grab_running():
		return true
	var def := _slot_action(slot_key)
	return def != null and (is_crush(def) or def.id == HURL_ID)


## HUD hotbar (P03's hook): the slot's precheck, from the cached candidates (no physics
## queries outside the simulation tick).
func preview_params(slot_key: String, def: ActionDef, params: Dictionary) -> void:
	if def != null and handles_slot(slot_key):
		params["precheck"] = _preview_precheck.bind(def.id)


func pre_actions(_intents: Dictionary, _dt: float) -> void:
	_lunge_step()
	_retry_queued()


func post_movement(tick: int, _dt: float) -> void:
	if _target != null:
		if not _held_ok():
			_lose_target()
		else:
			_place_held()
			if not _throw_or_crush_running():
				if tick - _hold_tick >= ActionDef.seconds_to_ticks(hold_timeout_s):
					release("timeout")
				elif _checkpoint_waits_for_hold():
					release("interrupted")
	_emit_aim_preview(tick)
	if tick - _cache_tick >= CACHE_TICKS:
		_refresh_cache()


func on_action_started(action: ActionDef, _instance_id: int) -> void:
	if action.id == GRAB_ID or action.id == THROW_ID:
		_queued = &""
	if action.hit_shape != "grab":
		return
	_lunge_origin = Vector3.INF
	_lunge_set = false
	if is_holding():
		_pending = _target if is_crush(action) else null   # a crush squeezes what is held
		return
	var c := find_candidate(_mode_of(action), max_mass_of(action))
	_pending = c.target if bool(c.ok) else null
	if _pending != null:
		_lunge_origin = player.global_position
		_face(_pending)
		_lunge_step()


func on_action_ended(action: ActionDef, _instance_id: int, _interrupted: bool) -> void:
	if action.hit_shape == "grab":
		_pending = null
		_lunge_origin = Vector3.INF
		_stop_lunge()


func on_profile_changed(_old_profile: Dictionary, _new_profile: Dictionary) -> void:
	_cache_tick = -1000000


func interact_candidate() -> Dictionary:
	if is_holding():
		return {"priority": 10, "prompt": "Put down", "distance": 0.0, "call": drop, "id": ""}
	var c := _candidate_cached("hold", "")
	if bool(c.ok):
		return {"priority": 10, "prompt": "Grab %s" % (c.target as CombatEntity).display_name(),
			"distance": float(c.distance), "call": try_grab, "id": ""}
	return {}


func rig_state(out: Dictionary) -> void:
	var c := player.controller
	var a := c.action
	var phase := ""
	if a != null and a.id == THROW_ID:
		phase = "throw"
	elif is_holding():
		phase = "crush" if is_crush(a) else "hold"
	elif a != null and a.hit_shape == "grab" and c.phase() == ActionDef.Phase.WINDUP:
		phase = "reach"
	out["holding"] = held_attach()
	out["grab_phase"] = phase
	if phase == "" or player.rig == null:
		return
	out["pose_override"] = ActorRig.grab_pose(phase, held_attach(), socket_local(), player.weapon_pivot,
		player.rig.idle_arm_pose, player.rig.off_idle_pose, c.phase(), c.phase_fraction(),
		float(Sim.tick) * Sim.DT)


func debug_info(out: Dictionary) -> void:
	if is_holding():
		out["grab"] = "holding %s (%s) %.1f s" % [_target_id, _attach, float(hold_ticks()) / Sim.TICK_RATE]


func on_exit() -> void:
	_stop_lunge()
	_pending = null
	if _target != null:
		release("unloaded")
	for pair: Array in [[Events.entity_died, _on_entity_died], [Events.projectile_spawned, _on_projectile_spawned],
			[Events.growth_blocked, _on_growth_blocked]]:
		var sig: Signal = pair[0]
		if sig.is_connected(pair[1]):
			sig.disconnect(pair[1])


# --------------------------------------------------------------------------- holding

## The hand socket in the giant's own space now: the attachment profile's (SOCKETS; first person:
## low and to the left) x k; during a throw's windup it travels to the wind-back point.
func socket_local() -> Vector3:
	var fp := player.camera_rig != null and player.camera_rig.is_first_person()
	var pair: Array = SOCKETS.get(_attach, SOCKETS.torso_fist)
	var s: Vector3 = pair[1 if fp else 0]
	var c := player.controller
	if c.action != null and c.action.id == THROW_ID and c.phase() == ActionDef.Phase.WINDUP:
		var back := THROW_BACK_TWO_HAND if _attach == "two_hand" and not fp else THROW_BACK_ONE_HAND
		var f := clampf(float(c.elapsed + 1) / maxf(1.0, float(c.action.windup_ticks)), 0.0, 1.0)
		s = s.lerp(back, f * f * (3.0 - 2.0 * f))
	return s * body_scale()


## The held body's orientation: it faces the giant; a wolf held by the scruff hangs nose up.
func held_basis() -> Basis:
	var b := player.global_transform.basis.orthonormalized() * Basis(Vector3.UP, PI)
	if _attach == "scruff":
		b = b * Basis(Vector3.RIGHT, deg_to_rad(SCRUFF_PITCH_DEG))
	return b


## The held body's grab point sits in the hand (EnemyActor.carry).
func _place_held() -> void:
	var actor := _target.actor
	actor.call("carry", player.to_global(socket_local()), held_basis(), actor.call("grab_anchor_local"))


## Closes the hand on `target` for action `a` (the first active tick): checked again with the
## reach alone, then GRABBED (enter_grabbed + on_grabbed), holding_id, the speed multiplier, no
## lock on it, grab_started.
func _attach_target(target: CombatEntity, a: ActionDef) -> bool:
	var why := check_target(target, _mode_of(a), max_mass_of(a), grab_reach())
	if why != "":
		Events.hud_message.emit(reason_text(why), "warn")
		return false
	if target.controller == null or not target.controller.enter_grabbed(player.entity.entity_id):
		return false
	_target = target
	_target_id = target.entity_id
	_attach = _attach_of(target)
	_hold_tick = Sim.tick
	target.actor.call("on_grabbed", player.entity.entity_id)
	player.controller.holding_id = target.entity_id
	player.motor.set_speed_mult(&"grab", HOLD_SPEED_MULT)
	if player.lock.is_locked() and player.lock.target_id == target.entity_id:
		player.targeting.release_lock("grabbed")
	_place_held()
	Events.grab_started.emit(Sim.tick, player.entity.entity_id, target.entity_id)
	return true


## The "grab" hit shape (AttackRunner; every ACTIVE tick of a grab action): the hand closes on the
## first one. A crush then squeezes the held body with the action's own hit (HitFactory) and lets
## go when grab.release_after is set.
func _run_grab_shape(a: ActionDef, tick: int) -> void:
	if not player.controller.is_first_active_tick():
		return
	_stop_lunge()
	var target := _pending
	_pending = null
	if not is_holding():
		if target == null or not is_instance_valid(target) or not _attach_target(target, a):
			return
	elif target != _target:
		return
	if is_crush(a):
		_crush(a, tick)


func _crush(a: ActionDef, tick: int) -> void:
	var t := _target
	HitFactory.queue(player.attack.runner.context(), a, [{"entity": t, "hurtbox": null,
		"point": t.anchor_position(), "substep": 0, "distance": 0.0, "weak_point": false}], 1, tick)
	if bool(_grab_block(a).get("release_after", false)):
		release("crushed")


func _held_ok() -> bool:
	if not is_instance_valid(_target) or _target.actor == null or not is_instance_valid(_target.actor) \
			or not _target.actor.is_inside_tree():
		return false
	var s := _target.controller.state if _target.controller != null else CombatController.State.DEAD
	return s == CombatController.State.GRABBED or s == CombatController.State.DEAD


## The held body vanished (freed, left the tree) or something else let it go: forget it.
func _lose_target() -> void:
	var t := _target
	var id := _target_id
	_target = null
	_target_id = ""
	_attach = ""
	_hold_tick = -1
	player.controller.holding_id = ""
	player.motor.set_speed_mult(&"grab", 1.0)
	if is_instance_valid(t) and t.actor != null and is_instance_valid(t.actor) and t.actor.is_inside_tree():
		t.actor.call("on_released", "interrupted", _release_fallbacks(t))
	Events.grab_ended.emit(Sim.tick, player.entity.entity_id, id, "unloaded")


func _release_fallbacks(t: CombatEntity) -> Array:
	var p := player.global_position
	var fwd := -player.global_transform.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized() if fwd.length_squared() > 1e-6 else Vector3.FORWARD
	var right := Vector3(-fwd.z, 0.0, fwd.x)
	var d := float(player.profile.get("capsule_radius_m", 0.85)) + EnemyActor.entity_radius(t) + RELEASE_GAP_M
	return [p + fwd * d, p - right * d, p + right * d, p - fwd * d, p]


## True when a pending checkpoint waits only because of this hold (GameSession's blockers are the
## hold itself and the held enemy's own awareness): then the hold gives way.
func _checkpoint_waits_for_hold() -> bool:
	var gs := player.get_node_or_null("/root/GameSession")
	if gs == null or not gs.has_method("checkpoint_blockers") or not gs.has_method("pending_checkpoint"):
		return false
	if gs.has_method("checkpoints_enabled") and not bool(gs.call("checkpoints_enabled")):
		return false
	var pending: Variant = gs.call("pending_checkpoint")
	if typeof(pending) != TYPE_DICTIONARY or (pending as Dictionary).is_empty():
		return false
	var blockers: PackedStringArray = gs.call("checkpoint_blockers")
	if not blockers.has("holding"):
		return false
	for b: String in blockers:
		if b != "holding" and b != "aware:%s" % _target_id:
			return false
	return true


# --------------------------------------------------------------------------- lunge and queue

## The grab windup's lunge (the action's motion): toward the pending target at up to
## motion.speed_mps x k, at most grab_lunge_m in all, stopping LUNGE_STOP_FRACTION x
## grab_reach_m from it (centre to centre). It drives the motor's knockback channel, which
## update_movement integrates this tick (set pre-compensated for its decay).
func _lunge_step() -> void:
	var c := player.controller
	var a := c.action
	if _lunge_origin == Vector3.INF or _pending == null or not is_instance_valid(_pending) or a == null \
			or a.hit_shape != "grab" or c.state != CombatController.State.EXECUTING \
			or c.phase() != ActionDef.Phase.WINDUP or is_holding():
		_stop_lunge()
		return
	var to := _pending.actor.global_position - player.global_position
	to.y = 0.0
	var travelled := Vector2(player.global_position.x - _lunge_origin.x,
		player.global_position.z - _lunge_origin.z).length()
	var dist := minf(to.length() - LUNGE_STOP_FRACTION * grab_reach(), grab_lunge() - travelled)
	if dist <= 0.01 or to.length_squared() < 1e-6:
		_stop_lunge()
		return
	var motion: Variant = a.param("motion")
	var cap := float((motion as Dictionary).get("speed_mps", 9.0)) if typeof(motion) == TYPE_DICTIONARY else 9.0
	var speed := minf(dist / Sim.DT, cap * body_scale())
	_face(_pending)
	player.knockback_velocity = to.normalized() * (speed + PlayerMotor.KNOCKBACK_DECEL * Sim.DT)
	_lunge_set = true


func _stop_lunge() -> void:
	if _lunge_set:
		player.knockback_velocity = Vector3.ZERO
		_lunge_set = false


func _face(target: CombatEntity) -> void:
	player.facing_yaw = player.motor.yaw_to(target.actor.global_position)
	player.rotation.y = player.facing_yaw


## Requests the grab or the throw now; while the controller is busy (RETRY) it is retried every
## tick for QUEUE_TICKS (the controller's own buffer keeps a request for 9 ticks only).
func _queue(kind: StringName) -> void:
	_queued = kind
	_queued_until = Sim.tick + QUEUE_TICKS
	var v := try_grab() if kind == &"grab" else try_throw()
	if v != CombatController.Verdict.RETRY:
		_queued = &""


func _retry_queued() -> void:
	if _queued == &"":
		return
	if Sim.tick > _queued_until:
		_queued = &""
		return
	var buf := player.controller.buffer
	if buf.has_pending():
		var mine := GRAB_ID if _queued == &"grab" else THROW_ID
		if not (buf.kind == &"attack" and str(buf.params.get("action_id", "")) == mine):
			_queued = &""   # a newer input replaced it
		return              # the controller retries it itself while it is live
	var v := try_grab() if _queued == &"grab" else try_throw()
	if v != CombatController.Verdict.RETRY:
		_queued = &""


# --------------------------------------------------------------------------- input helpers

func _on_interact() -> bool:
	if _throw_or_crush_running():
		return true   # the body is leaving the hand
	if is_holding():
		drop()
		return true
	var c := find_candidate("hold")
	if bool(c.ok):
		_queue(&"grab")
		return true
	if str(c.reason) == "nothing_in_reach":
		return false
	# Something is in reach that cannot be grabbed: unless E has another use here (a shrine, an
	# NPC), the grab is refused through the controller (its reason is reported, nothing spent).
	if player.interact != null:
		player.interact.refresh()
		if not player.interact.current_candidate().is_empty():
			return false
	try_grab()
	return true


func _grab_precheck() -> String:
	return "holding" if is_holding() else str(find_candidate("hold").reason)


func _throw_precheck() -> String:
	return "" if is_holding() else "not_holding"


func _slot_precheck(slot_key: String) -> String:
	return ability_reason(_slot_action(slot_key))


## The hotbar's version: the cached candidates, and an empty reach is the HUD's "no_grab_target"
## ("No target"); the other codes are shown as they are.
func _preview_precheck(action_id: String) -> String:
	var why := ability_reason(player.controller.library.get(action_id), true)
	return "no_grab_target" if why == "nothing_in_reach" else why


func _slot_action(slot_key: String) -> ActionDef:
	var id := str(player.controller.loadout.get(slot_key, ""))
	return player.controller.library.get(id) if id != "" else null


func _grab_running() -> bool:
	var a := player.controller.action
	return a != null and a.hit_shape == "grab"


func _throw_or_crush_running() -> bool:
	var a := player.controller.action
	return a != null and (a.id == THROW_ID or is_crush(a))


# --------------------------------------------------------------------------- candidates

## Grabbable actors: they implement the EnemyActor grab hooks.
static func _grabbable_kind(e: CombatEntity) -> bool:
	return e != null and e.actor != null and is_instance_valid(e.actor) and e.actor.has_method("can_be_grabbed") \
		and e.actor.has_method("on_grabbed") and e.actor.has_method("on_released") and e.actor.has_method("carry")


static func _attach_of(e: CombatEntity) -> String:
	if e.actor.has_method("grab_attach"):
		return str(e.actor.call("grab_attach"))
	return str(GameData.get_record(e.definition_id).get("grab_attach", "none"))


func _flat_distance(e: CombatEntity) -> float:
	var d := e.actor.global_position - player.global_position
	return Vector2(d.x, d.z).length()


## The eye sees the target's grab point (WORLD | BREAKABLE; the target's own bodies excluded).
func _can_see(e: CombatEntity) -> bool:
	var point := e.anchor_position()
	if e.actor.has_method("grab_anchor_local"):
		point = e.actor.to_global(e.actor.call("grab_anchor_local"))
	return HitQueryAdapter.line_clear(player.get_world_3d().direct_space_state, player.targeting.eye(),
		point, LOS_MASK, e.occlusion_rids)


func _refresh_cache() -> void:
	_cache_tick = Sim.tick
	_cache = {"hold": find_candidate("hold")}
	for key: String in GiantPlayer.SLOT_KEYS:
		var def := _slot_action(key)
		if def != null and is_crush(def) and not _cache.has("crush:" + max_mass_of(def)):
			_cache["crush:" + max_mass_of(def)] = find_candidate("crush", max_mass_of(def))


func _candidate_cached(mode: String, max_mass: String) -> Dictionary:
	var c: Dictionary = _cache.get("hold" if mode == "hold" else "crush:" + max_mass, {})
	if c.is_empty() or (bool(c.ok) and not is_instance_valid(c.target)):
		return {"ok": false, "reason": "nothing_in_reach", "target": null, "distance": INF}
	return c


# --------------------------------------------------------------------------- events

func _on_holder_state_changed(_old_state: int, new_state: int) -> void:
	if not is_holding():
		return
	match new_state:
		CombatController.State.DEAD:
			release("holder_died")
		CombatController.State.STAGGERED, CombatController.State.GRABBED:
			release("interrupted")


func _on_entity_died(_tick: int, id: String, _killer_id: String) -> void:
	if is_holding() and id == _target_id:
		release("target_died")
	if _pending != null and is_instance_valid(_pending) and _pending.entity_id == id:
		_pending = null


func _on_growth_blocked(_tick: int, entity_id: String, reason: String, _message: String) -> void:
	if reason == "holding" and is_holding() and entity_id == player.entity.entity_id:
		release("interrupted")


func _on_request_rejected(_kind: StringName, action_id: String, reason: String) -> void:
	if action_id == GRAB_ID or action_id == THROW_ID:
		_queued = &""
	if reason != "not_holding" and (reason in REASONS or reason in OTHER_REASONS):
		Events.hud_message.emit(reason_text(reason), "warn")


## A throw's projectile was launched: hand it the held body (or drop the empty throw).
func _on_projectile_spawned(_tick: int, projectile_id: int, owner_id: String, _action_id: String,
		_position: Vector3, _velocity: Vector3, visual: String) -> void:
	if visual != "thrown_body" or player == null or owner_id != player.entity.entity_id:
		return
	var system := ProjectileSystem.instance(player.get_tree())
	if is_holding() and system.carry_body(projectile_id, _target_id, owner_id):
		release("thrown")
	else:
		system.discard(projectile_id)


## The runner's launch resolver, wrapped: a throw starts from the held body's centre and aims like
## any projectile (PlayerAttack.aim_point_for); every other launch is PlayerAttack's.
func _resolve_launch(a: ActionDef, spec: Dictionary) -> Dictionary:
	if a != null and a.id == THROW_ID and is_holding():
		var origin: Vector3 = _target.actor.to_global(_target.actor.call("body_centre_local"))
		return {"origin": origin, "aim": player.attack.aim_point_for(spec, origin)}
	if _base_resolver.is_valid():
		return _base_resolver.call(a, spec)
	return {}


# --------------------------------------------------------------------------- aim preview

## Boulder Hurl (and a throw) show where they will come down: every windup tick an
## ability_effect "aim_preview" at the predicted landing point, the splash wide.
func _emit_aim_preview(tick: int) -> void:
	var c := player.controller
	var a := c.action
	if a == null or a.hit_shape != "projectile" or c.phase() != ActionDef.Phase.WINDUP:
		return
	if a.id == THROW_ID and not is_holding():
		return
	var spec := Projectile.spec_for(a)
	if not bool(spec.arc_to_target) or float(spec.gravity_mps2) <= 0.0:
		return
	var point := predict_landing(a)
	if point == Vector3.INF:
		return
	Events.ability_effect.emit(tick, player.entity.entity_id, a.id, "aim_preview", point,
		float(spec.impact_radius_m), player.facing_yaw, 0.0)


## Where projectile action `a` would come down if it were launched now: the runner's launch
## (resolver origin and aim, Projectile.launch_velocity) traced in PREVIEW_STEP_S segments
## against the world; it lands at the first contact, or at the aim point when that is on or
## near the ground (a target), dropped onto the ground under it. INF when there is no launch.
func predict_landing(a: ActionDef) -> Vector3:
	var spec := Projectile.spec_for(a)
	var runner := player.attack.runner
	var launch: Dictionary = runner.launch_resolver.call(a, spec) if runner.launch_resolver.is_valid() else {}
	if not launch.has("origin") or not launch.has("aim"):
		return Vector3.INF
	var origin: Vector3 = launch.origin
	var aim: Vector3 = launch.aim
	var v := Projectile.launch_velocity(origin, aim, spec)
	var g := float(spec.gravity_mps2)
	var space := player.get_world_3d().direct_space_state
	var flat_v := Vector2(v.x, v.z).length()
	var flat_aim := minf(Vector2(aim.x - origin.x, aim.z - origin.z).length(), float(spec.range_m))
	var t_aim := flat_aim / maxf(flat_v, 0.01)
	var aim_ground := _ground_under(aim)
	var aim_low := aim.y - aim_ground.y <= 2.5
	var prev := origin
	var t := 0.0
	while t < PREVIEW_MAX_S:
		var next_t := minf(t + PREVIEW_STEP_S, PREVIEW_MAX_S)
		var at_aim := aim_low and t < t_aim and next_t >= t_aim
		if at_aim:
			next_t = t_aim
		var p := origin + v * next_t + Vector3.DOWN * (0.5 * g * next_t * next_t)
		var hit := HitQueryAdapter.first_world_hit(space, prev, p, [])
		if not hit.is_empty():
			return _ground_under(hit.position)
		if at_aim:
			return aim_ground
		prev = p
		t = next_t
	return _ground_under(prev)


func _ground_under(point: Vector3) -> Vector3:
	var q := PhysicsRayQueryParameters3D.create(point + Vector3.UP * 0.5, point + Vector3.DOWN * 60.0,
		HitQueryAdapter.OCCLUDER_MASK)
	q.collide_with_areas = false
	var hit := player.get_world_3d().direct_space_state.intersect_ray(q)
	return hit.position if not hit.is_empty() else point
