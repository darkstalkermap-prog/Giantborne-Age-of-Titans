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
##   GIVE_WAY (P22, plan M6-M9 §2.12, decision 31): a civilian of a faction whose record has
##         civilians_give_way, at peace with the giant (not warned, hostile or stood down), does not
##         flee a giant rushing by: it steps out of the giant's path to give_way_m plus the giant's
##         height to the side of its line of travel, watching it, then stands (IDLE) and watches.
##         Combat noise and its faction's news still send it running. Thornwick (faction.village)
##         keeps fleeing: the Valley is unchanged.
## A talker (role "talker": the elder) never flees: it stays to talk.

enum State { IDLE, FLEE, SAFE, DEAD, GIVE_WAY }
const STATE_NAMES := ["Idle", "Flee", "Safe", "Dead", "GiveWay"]
const TICK_RATE := 60
## The giant scares a civilian only when it moves faster than this (m/s, horizontal).
const SCARY_SPEED_MPS := 3.0
## A fleeing civilian has arrived this close to its destination (horizontal metres).
const ARRIVE_M := 1.0
## With nowhere to run, the civilian asks again this often.
const REPICK_S := 2.0
## An idle civilian turns toward a giant this close.
const WATCH_M := 20.0
## Giving way (P22): the giant's line of travel is recomputed this often; the step ends this close
## to its point, or when the civilian already stands clear of the line by this much more.
const GIVE_WAY_REPLAN_S := 0.5
const GIVE_WAY_MARGIN_M := 0.5

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
## P22 give-way: the faction (from the actor's CombatEntity, read once), where the giant was at the
## previous perception, and the side step's point.
var faction := ""
var give_way_point := Vector3.INF
var _faction_read := false
var _giant_prev := Vector3.INF
var _giant_prev_tick := -1
var _giant_dir := Vector3.ZERO
var _give_way_tick := -1000000


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
	_track_giant(tick, snapshot)
	if state == State.GIVE_WAY:
		if bool(snapshot.get("hostile", false)) or bool(snapshot.get("stood_down", false)):
			_set_state(State.IDLE)   # the news ends the courtesy: fall through and run
		else:
			return
	if state != State.IDLE:
		return
	if bool(snapshot.get("hostile", false)):
		start_fleeing("hostile")
	elif bool(snapshot.get("stood_down", false)):
		start_fleeing("stood_down")
	elif bool(snapshot.get("exists", false)) and flee_trigger_radius_m > 0.0 \
			and float(snapshot.get("distance", INF)) <= flee_trigger_radius_m \
			and float(snapshot.get("speed", 0.0)) > SCARY_SPEED_MPS:
		if give_way_m() > 0.0:
			start_giving_way()
		else:
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
		State.GIVE_WAY:
			_decide_give_way(my_position)
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


## The path toward the destination made no progress: pick again, skipping the failed marker (a
## side step that cannot be reached is given up: the civilian stands and watches).
func on_path_failed(my_position: Vector3) -> void:
	if state == State.FLEE:
		_pick(my_position, true)
	elif state == State.GIVE_WAY:
		give_way_point = Vector3.INF
		_set_state(State.IDLE)


func _pick(my_position: Vector3, skip_failed: bool) -> void:
	_last_pick_tick = now
	picks += 1
	destination = safe_resolver.call(my_position, skip_failed) if safe_resolver.is_valid() else Vector3.INF


static func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


# --------------------------------------------------------------------------- giving way (P22)

## The faction of this civilian (its CombatEntity's, which reads the actor's `faction`), read once.
func faction_of() -> String:
	if not _faction_read:
		var e := Sim.get_entity(actor_id)
		if e != null:
			faction = e.faction
			_faction_read = true
	return faction


## How far it steps aside (m, before the giant's height is added): its faction record's give_way_m
## while the faction is at peace with the giant (not warned, hostile or stood down); 0 = it flees.
func give_way_m() -> float:
	if not can_flee():
		return 0.0
	var f := faction_of()
	if f == "" or FactionState.is_warned(f) or FactionState.is_hostile(f) or FactionState.is_stood_down(f):
		return 0.0
	return FactionState.give_way_m(f)


## IDLE -> GIVE_WAY (civilians of a give-way faction only).
func start_giving_way() -> void:
	if state != State.IDLE or not can_flee():
		return
	give_way_point = Vector3.INF
	_give_way_tick = -1000000
	_set_state(State.GIVE_WAY)


## How far to the side of the giant's line of travel a civilian stands clear: give_way_m plus the
## giant's height (perception "height" when the actor reports it, else the PLAYER entity's).
func give_way_clearance() -> float:
	return give_way_m() + _giant_height()


## The point `my_position` steps to so that it stands `clearance` (+ GIVE_WAY_MARGIN_M) to the side
## of the line through `giant` along `dir` (flat; it keeps the side it is on); Vector3.INF when it
## already stands clear, or the giant is past it (more than 2 m behind its line). Pure.
static func side_step(my_position: Vector3, giant: Vector3, dir: Vector3, clearance: float) -> Vector3:
	var d := Vector3(dir.x, 0.0, dir.z)
	var rel := Vector3(my_position.x - giant.x, 0.0, my_position.z - giant.z)
	if d.length_squared() < 1e-6:
		d = rel.normalized() if rel.length_squared() > 1e-6 else Vector3.FORWARD
		# Standing giant: step straight away to the clearance.
		var away := clearance + GIVE_WAY_MARGIN_M - rel.length()
		return my_position + d * away if away > 0.0 else Vector3.INF
	d = d.normalized()
	if rel.dot(d) < -2.0:
		return Vector3.INF
	var side := Vector3(-d.z, 0.0, d.x)
	var lateral := rel.dot(side)
	if absf(lateral) >= clearance:
		return Vector3.INF
	var sgn := 1.0 if lateral >= 0.0 else -1.0
	return my_position + side * sgn * (clearance + GIVE_WAY_MARGIN_M - absf(lateral))


func _decide_give_way(my_position: Vector3) -> void:
	var giant: Vector3 = perception.get("position", Vector3.INF)
	if giant == Vector3.INF or not bool(perception.get("exists", false)):
		give_way_point = Vector3.INF
		_set_state(State.IDLE)
		return
	face_point = giant
	if give_way_point == Vector3.INF or now - _give_way_tick >= int(GIVE_WAY_REPLAN_S * TICK_RATE):
		_give_way_tick = now
		var p := side_step(my_position, giant, _giant_dir, give_way_clearance())
		if p == Vector3.INF and give_way_point == Vector3.INF:
			move_target = Vector3.INF
			_set_state(State.IDLE)   # already clear: stand and watch
			return
		if p != Vector3.INF:
			give_way_point = Vector3(p.x, my_position.y, p.z)
	if _flat(my_position, give_way_point) <= ARRIVE_M * 0.5:
		move_target = Vector3.INF
		give_way_point = Vector3.INF
		_set_state(State.IDLE)
		return
	move_target = give_way_point
	move_speed = -1.0


## The giant's direction of travel, from two perceptions (flat; ZERO while it stands).
func _track_giant(tick: int, snapshot: Dictionary) -> void:
	if not bool(snapshot.get("exists", false)):
		_giant_prev = Vector3.INF
		return
	var pos: Vector3 = snapshot.get("position", Vector3.INF)
	if pos == Vector3.INF:
		return
	if _giant_prev != Vector3.INF and tick > _giant_prev_tick:
		var v := Vector3(pos.x - _giant_prev.x, 0.0, pos.z - _giant_prev.z)
		var dt := float(tick - _giant_prev_tick) / TICK_RATE
		_giant_dir = v.normalized() if v.length() > 0.2 * dt else Vector3.ZERO
	_giant_prev = pos
	_giant_prev_tick = tick


func _giant_height() -> float:
	if perception.has("height"):
		return float(perception.height)
	for e: CombatEntity in Sim.entities():
		if e.team == CombatEntity.Team.PLAYER and e.combatant != null:
			return e.combatant.height_m
	return 3.6576
