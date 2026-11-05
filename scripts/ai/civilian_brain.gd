class_name CivilianBrain
extends RefCounted
## The small state machine of a villager (plan §3.13 design 1, spec 15 "fleeing NPCs have a
## reachable destination"). Pure: the Civilian actor feeds it perceptions, noises and faction
## news, installs the safe-point resolver and applies its outputs (move target, speed, facing).
##
##   IDLE  stands at home, turned toward the giant while it is near. It flees when
##         * the giant comes within flee_trigger_radius_m moving faster than SCARY_SPEED_MPS,
##         * combat starts within noise_radius_m (an attack begun, a blow landed: on_noise),
##         * its faction turns hostile or stands down (perceived flags, or on_faction()).
##   FLEE  asks the resolver once for the nearest reachable safe marker and runs there; only a
##         path failure (on_path_failed) makes it ask again (the failed marker is skipped). With
##         nowhere reachable it stands where it is and asks again every REPICK_S.
##   SAFE  arrived (within ARRIVE_M): the actor stops processing it.
##   DEAD  killed.
## A talker (role "talker": the elder) never flees: it stays to talk.

enum State { IDLE, FLEE, SAFE, DEAD }
const STATE_NAMES := ["Idle", "Flee", "Safe", "Dead"]
const TICK_RATE := 60
## The giant scares a civilian only when it moves faster than this (m/s, horizontal).
const SCARY_SPEED_MPS := 3.0
## A fleeing civilian has arrived this close to its destination (horizontal metres).
const ARRIVE_M := 1.0
## With nowhere to run, the civilian asks again this often.
const REPICK_S := 2.0
## An idle civilian turns toward a giant this close.
const WATCH_M := 20.0

var actor_id := ""
var role := "civilian"
var state: int = State.IDLE
var state_tick := 0
var now := 0
## Why it fled: "giant", "noise", "hostile", "stood_down" ("" while it has not).
var flee_reason := ""
## Where it runs (Vector3.INF until chosen, or when nothing is reachable).
var destination := Vector3.INF
## How many times its destination was chosen (1 = once: no re-path without a path failure).
var picks := 0
var flee_trigger_radius_m := 0.0
var noise_radius_m := 20.0
## The last perception: {"exists", "position", "distance", "speed", "hostile", "stood_down"}.
var perception: Dictionary = {}
## safe_resolver(from: Vector3, skip_failed: bool) -> Vector3: the nearest reachable safe point
## (Vector3.INF = none). The actor installs it; unset, the civilian has nowhere to go.
var safe_resolver := Callable()

# Outputs, read by the actor every tick.
var move_target := Vector3.INF
var move_speed := 0.0   ## 0 walk, -1 run (as EnemyBrain)
var face_point := Vector3.INF

var _last_pick_tick := -1000000


func _init(p_actor_id: String, record: Dictionary) -> void:
	actor_id = p_actor_id
	role = str(record.get("role", "civilian"))
	flee_trigger_radius_m = float(record.get("flee_trigger_radius_m", 0.0))
	noise_radius_m = float(record.get("flee_noise_radius_m", 20.0))


func state_name() -> String:
	return STATE_NAMES[state] if state >= 0 and state < STATE_NAMES.size() else "State %d" % state


func can_flee() -> bool:
	return role == "civilian"


func _set_state(s: int) -> void:
	if s == state:
		return
	state = s
	state_tick = now


## snapshot: {"exists": bool, "position": Vector3, "distance": float (horizontal), "speed": float
## (the giant's horizontal speed), "hostile": bool, "stood_down": bool}.
func perceive(tick: int, snapshot: Dictionary) -> void:
	now = tick
	perception = snapshot
	if state != State.IDLE:
		return
	if bool(snapshot.get("hostile", false)):
		start_fleeing("hostile")
	elif bool(snapshot.get("stood_down", false)):
		start_fleeing("stood_down")
	elif bool(snapshot.get("exists", false)) and flee_trigger_radius_m > 0.0 \
			and float(snapshot.get("distance", INF)) <= flee_trigger_radius_m \
			and float(snapshot.get("speed", 0.0)) > SCARY_SPEED_MPS:
		start_fleeing("giant")


## Combat at `distance` metres (an attack began, a blow landed).
func on_noise(tick: int, distance: float) -> void:
	now = tick
	if state == State.IDLE and distance <= noise_radius_m:
		start_fleeing("noise")


## Its faction's standing changed ("hostile" and "stood_down" send it running).
func on_faction(tick: int, standing: String) -> void:
	now = tick
	if state == State.IDLE and standing in ["hostile", "stood_down"]:
		start_fleeing(standing)


## IDLE -> FLEE (civilians only; once).
func start_fleeing(reason: String) -> void:
	if state != State.IDLE or not can_flee():
		return
	flee_reason = reason
	destination = Vector3.INF
	_set_state(State.FLEE)


func decide(tick: int, my_position: Vector3, alive: bool) -> void:
	now = tick
	if not alive:
		_set_state(State.DEAD)
	match state:
		State.IDLE:
			move_target = Vector3.INF
			move_speed = 0.0
			var near := bool(perception.get("exists", false)) and float(perception.get("distance", INF)) <= WATCH_M
			face_point = perception.get("position", Vector3.INF) if near else Vector3.INF
		State.FLEE:
			face_point = Vector3.INF
			if destination == Vector3.INF and now - _last_pick_tick >= int(REPICK_S * TICK_RATE):
				_pick(my_position, false)
			if destination == Vector3.INF:
				move_target = Vector3.INF
				return
			if _flat(my_position, destination) <= ARRIVE_M:
				move_target = Vector3.INF
				_set_state(State.SAFE)
				return
			move_target = destination
			move_speed = -1.0
		_:
			move_target = Vector3.INF
			face_point = Vector3.INF


## The path toward the destination made no progress: pick again, skipping the failed marker.
func on_path_failed(my_position: Vector3) -> void:
	if state == State.FLEE:
		_pick(my_position, true)


func _pick(my_position: Vector3, skip_failed: bool) -> void:
	_last_pick_tick = now
	picks += 1
	destination = safe_resolver.call(my_position, skip_failed) if safe_resolver.is_valid() else Vector3.INF


static func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()
