class_name Formation
extends RefCounted
## An organised group of an encounter's human members (plan M6-M9 §2.10, decision 19; P30): ranks x
## files of slots around one pivot that turns to face the giant, a banner that steadies the
## members' morale, and one brace for the whole front rank. The EncounterDirector owns one per
## `formations` entry of an active encounter (built from data with from_record()), attaches the
## spawned members (add_member / set_banner) and calls update() ten times a second; tests may build
## one by hand. Pure enough to unit-test: the slot grid, the facing, the band and the fan-out points
## are geometry; update() reads the members' brains and starts the brace through one of them.
##
## The grid. Slot s is rank s / files, file s % files: rank 0 is the front rank, file 0 its left
## end seen from behind. In the formation's own frame (forward = -Z, yaw facing_yaw) slot (r, f)
## sits at x = (f - (files - 1) / 2) * file_spacing_m, z = (r - (ranks - 1) / 2) * rank_spacing_m,
## so the pivot is the block's centre; the banner stands one rank behind the last one, centred.
## anchor() is the front rank's centre at chest height: the lock point of the group (decision 19).
##
## States (Events.formation_changed with the formation's id):
##   formed     it stands at its pivot (turning to face the giant once a member is aware of it);
##   advancing  aware, the giant beyond brace_m: the pivot walks toward it at advance_mps along one
##              navigation path (NavQuery, one query per re-path, the director's budget), never
##              farther than advance_m from home;
##   braced     the giant within brace_m of the front rank: the pivot stops and, every brace cycle,
##              the focus member nearest the giant in the front rank runs brace_action (a band_pulse:
##              one band along front_band(), one telegraph, one hit per target per pulse) holding one
##              of the target's melee tokens for its duration; the others only pose;
##   broken     fewer than BROKEN_COHESION of its members stand (living, not fleeing): they fight on
##              their own until enough regroup;
##   routed     none stands and at least one fled: over for good.
## banner_fell is announced once when the banner dies (its members take it as their commander's
## death: EnemyActor's P30 section). While the banner lives its members lose half the morale of awe
## and ally deaths and regroup to their slots (EnemyBrain's P30 section); every rally_interval_s it
## rallies them (+morale within its radius).
##
## Routed members spread over flee_points (marker ids resolved by the director) or, without them,
## over FAN_POINTS points FAN_MIN_M..FAN_MAX_M away across a FAN_DEG fan facing away from the giant,
## so a breached gate does not jam (rout_point()).

signal state_changed(formation: Formation, new_state: String)

const KINDS := ["line", "pike", "shield", "crew"]
const STATES := ["formed", "advancing", "braced", "broken", "routed"]
## The lock line's name by kind when the record names none.
const KIND_NAMES := {"line": "Line", "pike": "Pike Regiment", "shield": "Shield Wall", "crew": "Crew"}
const BANNER_SLOT := -1
const DEFAULT_MORALE := 90.0
const DEFAULT_BRACE_HEIGHT_M := 5.0
const DEFAULT_TURN_DEG_S := 40.0
const DEFAULT_BANNER_COLOR := Color(0.62, 0.12, 0.10)
## The lock point's height over the pivot (a soldier's chest).
const CHEST_HEIGHT_M := 1.15
## Below this share of standing members the formation is broken.
const BROKEN_COHESION := 0.4
## update() runs this often (10 Hz at 60 ticks a second).
const UPDATE_TICKS := 6
## Seconds between the end of one brace and the next one's windup.
const BRACE_PAUSE_S := 0.6
## The fan routed members spread over when the formation names no flee points.
const FAN_DEG := 140.0
const FAN_MIN_M := 30.0
const FAN_MAX_M := 60.0
const FAN_POINTS := 5
## A pivot path is asked for again after this long, or when its goal moved this far.
const PIVOT_REPATH_TICKS := 60
const PIVOT_REPATH_MOVE_M := 2.0
## The pivot stops advancing once the giant is this far inside the brace distance (it braces, then
## holds). M7 gate: it stopped this far outside it - gap > brace_m + slack - and a giant standing in
## that half metre was never braced against (the toll fort's pikes stood "formed" 6.6 m from a still
## giant, brace_m 6).
const ADVANCE_SLACK_M := 0.5
## Outmatched soldiers join a formation of their faction within this distance (EnemyActor, P30).
const JOIN_RADIUS_M := 40.0
## An enemy's targets keep the formation aware for this long after the last aware member.
const AWARE_HOLD_TICKS := 60

## "<encounter short id>.<local id>", e.g. "crownmarch_toll_fort.pikes".
var id := ""
var local_id := ""
var encounter_id := ""
var kind := "line"
var display_name := ""
var banner_name := ""
var banner_color := DEFAULT_BANNER_COLOR
var ranks := 1
var files := 1
var rank_spacing_m := 2.0
var file_spacing_m := 1.5
## "threat" (turn toward the giant once aware) or "fixed".
var facing_mode := "threat"
var turn_deg_s := DEFAULT_TURN_DEG_S
var advance_mps := 0.0
var advance_m := 0.0
var brace_m := 0.0
var brace_action := ""
var brace_height_m := DEFAULT_BRACE_HEIGHT_M
var morale_start := DEFAULT_MORALE
## Flee point marker ids (the record's) and their resolved positions.
var flee_point_ids := PackedStringArray()
var flee_points: Array[Vector3] = []
## The faction its members fight under ("" = the always-hostile default), from its first member.
var faction := ""
## The level it stands in (NavQuery's), and the director's path budget: budget_left() -> int,
## spend_budget(n: int). Unset (tests): the pivot walks straight.
var level: Node = null
var budget_left := Callable()
var spend_budget := Callable()

## Rank-and-file members in the order they joined; slot_of[entity id] is each one's slot.
var members: Array[EnemyActor] = []
var slot_of: Dictionary = {}
## The banner (a member with slot -1), or null.
var banner: EnemyActor = null
## The banner's entity id from data (it may not have spawned yet).
var banner_id := ""

var pivot := Vector3.ZERO
var facing_yaw := 0.0
var home_pivot := Vector3.ZERO
var home_yaw := 0.0
var state := "formed"
var aware := false
## Where the threat stood at the last update (Vector3.INF when none is known) and its entity id.
var threat_pos := Vector3.INF
var threat_id := ""
## How many brace pulses it began (tests, debug, metrics) and when the last one began.
var brace_count := 0
var last_brace_tick := -1
## Rally pulses the banner gave (tests, debug).
var rally_count := 0
## The most rank-and-file members it had at once (cohesion's denominator).
var peak_members := 0
## Every formation_changed it emitted, oldest first: [tick, state] (tests, debug).
var history: Array = []

var _brace_holder: EnemyActor = null
var _brace_instance := -1
var _brace_ready_tick := 0
var _banner_seen_alive := false
var _banner_fell_emitted := false
var _routed_emitted := false
var _last_aware_tick := -100000
var _last_update_tick := -1
var _next_rally_tick := 0
var _path := PackedVector3Array()
var _path_i := 0
var _path_goal := Vector3.INF
var _path_tick := -100000

static var _registry: Array = []   # WeakRef to every live Formation (joining, lookups)


# --------------------------------------------------------------------------- construction

## A formation from an encounter's `formations` entry (see encounter_schema.gd).
static func from_record(p_encounter_id: String, rec: Dictionary) -> Formation:
	var f := Formation.new()
	f.encounter_id = p_encounter_id
	f.local_id = str(rec.get("id", ""))
	f.id = formation_id(p_encounter_id, f.local_id)
	f.kind = str(rec.get("kind", "line"))
	f.display_name = str(rec.get("display_name", KIND_NAMES.get(f.kind, "Formation")))
	f.banner_id = str(rec.get("banner", ""))
	f.banner_name = str(rec.get("banner_name", ""))
	var c: Variant = rec.get("banner_color")
	if typeof(c) == TYPE_ARRAY and (c as Array).size() == 3:
		f.banner_color = Color(float(c[0]), float(c[1]), float(c[2]))
	f.ranks = maxi(1, int(rec.get("ranks", 1)))
	f.files = maxi(1, int(rec.get("files", 1)))
	f.rank_spacing_m = float(rec.get("rank_spacing_m", 2.0))
	f.file_spacing_m = float(rec.get("file_spacing_m", 1.5))
	f.facing_mode = str(rec.get("facing", "threat"))
	f.turn_deg_s = float(rec.get("turn_deg_s", DEFAULT_TURN_DEG_S))
	f.advance_mps = float(rec.get("advance_mps", 0.0))
	f.advance_m = float(rec.get("advance_m", 0.0))
	f.brace_m = float(rec.get("brace_m", 0.0))
	f.brace_action = str(rec.get("brace_action", ""))
	f.brace_height_m = float(rec.get("brace_height_m", DEFAULT_BRACE_HEIGHT_M))
	f.morale_start = float(rec.get("morale_start", DEFAULT_MORALE))
	f.flee_point_ids = PackedStringArray(rec.get("flee_points", []))
	if rec.has("yaw_deg"):
		f.home_yaw = deg_to_rad(float(rec.yaw_deg))
		f.facing_yaw = f.home_yaw
	register(f)
	return f


## The formation id of entry `local_id` in an encounter: "<encounter id without 'encounter.'>.<local_id>".
static func formation_id(p_encounter_id: String, p_local_id: String) -> String:
	return "%s.%s" % [p_encounter_id.trim_prefix("encounter."), p_local_id]


## Places the formation (its home): the pivot and the facing.
func place(p_pivot: Vector3, yaw: float) -> void:
	pivot = p_pivot
	home_pivot = p_pivot
	facing_yaw = wrapf(yaw, -PI, PI)
	home_yaw = facing_yaw


## Keeps `f` in the registry of live formations (from_record does it; hand-made ones may).
static func register(f: Formation) -> void:
	for w: WeakRef in _registry:
		if w.get_ref() == f:
			return
	_registry.append(weakref(f))


## Every live formation (the registry, pruned of freed and dissolved ones).
static func live() -> Array[Formation]:
	var out: Array[Formation] = []
	var keep: Array = []
	for w: WeakRef in _registry:
		var f := w.get_ref() as Formation
		if f == null or f.dissolved:
			continue
		keep.append(w)
		out.append(f)
	_registry = keep
	return out


## The director dissolves a formation when its encounter deactivates (its members leave the world).
var dissolved := false


func dissolve() -> void:
	dissolved = true
	_finish_brace()
	for m in members.duplicate():
		if is_instance_valid(m):
			m.call("p30_leave_formation", self)
	if banner != null and is_instance_valid(banner):
		banner.call("p30_leave_formation", self)
	members.clear()
	slot_of.clear()
	banner = null


# --------------------------------------------------------------------------- members

func slot_count() -> int:
	return ranks * files


## Adds `actor` to slot `slot` (BANNER_SLOT makes it the banner). False when the slot is taken or
## out of the grid. Tells the actor (EnemyActor.p30_join_formation); `fresh`: it joins as it spawns
## (its morale becomes morale_start), else it joins mid-fight (try_join) and keeps its morale.
func add_member(actor: EnemyActor, slot: int, fresh := true) -> bool:
	if actor == null:
		return false
	if slot == BANNER_SLOT:
		set_banner(actor)
		return true
	if slot < 0 or slot >= slot_count() or slot_taken(slot):
		return false
	if members.has(actor):
		return false
	if members.is_empty() and banner == null:
		faction = actor.faction
	members.append(actor)
	slot_of[actor.entity_id] = slot
	peak_members = maxi(peak_members, members.size())
	actor.call("p30_join_formation", self, slot, fresh)
	return true


func set_banner(actor: EnemyActor) -> void:
	if members.is_empty() and banner == null:
		faction = actor.faction
	banner = actor
	banner_id = actor.entity_id
	_banner_seen_alive = actor.entity != null and actor.entity.is_alive()
	actor.call("p30_join_formation", self, BANNER_SLOT, true)


## Takes `actor` out (it died and was freed, despawned, or broke away for good).
func remove_member(actor: EnemyActor) -> void:
	if actor == banner:
		banner = null
	var i := members.find(actor)
	if i >= 0:
		members.remove_at(i)
	if actor != null and is_instance_valid(actor) and actor.entity != null:
		slot_of.erase(actor.entity_id)
	if actor == _brace_holder:
		_finish_brace()
	if actor != null and is_instance_valid(actor):
		actor.call("p30_leave_formation", self)


func slot_taken(slot: int) -> bool:
	for m in members:
		if is_instance_valid(m) and int(slot_of.get(m.entity_id, -2)) == slot and _alive(m):
			return true
	return false


## The free slots, front rank first.
func free_slots() -> Array[int]:
	var out: Array[int] = []
	for s in slot_count():
		if not slot_taken(s):
			out.append(s)
	return out


## The slot of `actor` (-1 for the banner, -2 when it is not a member).
func slot_for(actor: EnemyActor) -> int:
	if actor == null or not is_instance_valid(actor):
		return -2
	if actor == banner:
		return BANNER_SLOT
	return int(slot_of.get(actor.entity_id, -2))


## An outmatched soldier of this formation's faction takes the free slot nearest the front (plan
## §2.10). False when it is full, broken or routed, of another faction, or the actor is not alive.
func try_join(actor: EnemyActor) -> bool:
	if actor == null or not _alive(actor) or not is_intact() or members.has(actor) or actor == banner:
		return false
	if actor.faction != faction:
		return false
	var free := free_slots()
	if free.is_empty():
		return false
	return add_member(actor, free[0], false)


## Every member (the banner last), as listed.
func all_members() -> Array[EnemyActor]:
	var out: Array[EnemyActor] = []
	for m in members:
		if is_instance_valid(m):
			out.append(m)
	if banner != null and is_instance_valid(banner):
		out.append(banner)
	return out


## Members (rank-and-file and banner) that are in the world and alive.
func member_count() -> int:
	var n := 0
	for m in all_members():
		if _alive(m):
			n += 1
	return n


## Living rank-and-file members that have not routed (the lock line's count).
func living_count() -> int:
	var n := 0
	for m in members:
		if _alive(m) and not _routed(m):
			n += 1
	return n


## The living, non-fleeing share of its members (of the most it had at once).
func cohesion() -> float:
	if peak_members <= 0:
		return 0.0
	return float(_standing().size()) / float(peak_members)


func banner_alive() -> bool:
	return banner != null and is_instance_valid(banner) and _alive(banner)


## True while it holds its slots (formed, advancing or braced).
func is_intact() -> bool:
	return state in ["formed", "advancing", "braced"] and not dissolved


## The living, non-fleeing rank-and-file member nearest `from` (the group lock's focus, the
## brace's striker); the banner instead when `prefer_banner` and it lives; null when none stands.
func focus_member(from: Vector3, prefer_banner := false) -> EnemyActor:
	if prefer_banner and banner_alive():
		return banner
	var best: EnemyActor = null
	var best_d := INF
	for m in _standing():
		var d := m.global_position.distance_squared_to(from)
		if d < best_d - 1e-6 or (absf(d - best_d) <= 1e-6 and best != null and m.entity_id < best.entity_id):
			best = m
			best_d = d
	return best


## The living, non-routed rank-and-file member nearest `from` (fleeing ones included); null when
## none is left.
func nearest_living(from: Vector3) -> EnemyActor:
	var best: EnemyActor = null
	var best_d := INF
	for m in members:
		if not _alive(m) or _routed(m):
			continue
		var d := m.global_position.distance_squared_to(from)
		if d < best_d:
			best = m
			best_d = d
	return best


## The lock line's text: "Pike Regiment (8)".
func lock_label() -> String:
	return "%s (%d)" % [display_name, living_count()]


## The banner's lock line: "⚑ Banner of the Toll-Riders" (its banner_name, else "Banner").
func banner_label() -> String:
	return "⚑ %s" % (banner_name if banner_name != "" else "Banner")


# --------------------------------------------------------------------------- geometry

## Forward (the facing) on the ground plane.
static func forward_of(yaw: float) -> Vector3:
	return Vector3(-sin(yaw), 0.0, -cos(yaw))


## Right of the facing on the ground plane.
static func right_of(yaw: float) -> Vector3:
	return Vector3(cos(yaw), 0.0, -sin(yaw))


## Slot `slot`'s offset in the formation's own frame (x right, z back; see the class notes). The
## geometry is FormationRules.slot_offset's, which the data's leash check uses too.
func slot_local(slot: int) -> Vector3:
	return FormationRules.slot_offset(ranks, files, rank_spacing_m, file_spacing_m, slot)


## Where slot `slot` stands now (BANNER_SLOT: the banner's place behind the last rank).
func slot_position(slot: int) -> Vector3:
	return pivot + Basis(Vector3.UP, facing_yaw) * slot_local(slot)


## The front rank's centre on the ground.
func front_center() -> Vector3:
	return pivot + forward_of(facing_yaw) * (float(ranks - 1) * 0.5 * rank_spacing_m)


## The group's lock point: the front rank's centre at chest height.
func anchor() -> Vector3:
	return front_center() + Vector3.UP * CHEST_HEIGHT_M


## Half the front rank's width, out to its outer members' shoulders.
func half_width() -> float:
	return float(files - 1) * 0.5 * file_spacing_m + file_spacing_m * 0.5


## How deep the brace band reaches in front of the front rank: the brace action's radius_m, else
## brace_m (at least 1 m).
func band_depth() -> float:
	var a := GameData.get_action(brace_action) if brace_action != "" else null
	if a != null and a.radius_m > 0.0:
		return a.radius_m
	return maxf(brace_m, 1.0)


## The brace band: {"center" (on the ground), "near" (the front rank's centre), "half_width",
## "depth", "yaw"} - a rectangle from the front rank `depth` metres forward, as wide as the rank.
func front_band() -> Dictionary:
	var near := front_center()
	var depth := band_depth()
	return {"center": near + forward_of(facing_yaw) * (depth * 0.5), "near": near,
		"half_width": half_width(), "depth": depth, "yaw": facing_yaw}


## How far `point` lies in front of the front rank (negative behind it), along the facing.
func front_gap(point: Vector3) -> float:
	var to := point - front_center()
	to.y = 0.0
	return to.dot(forward_of(facing_yaw))


## True when `point` is within `reach` metres in front of the front rank and within the rank's
## width (plus `margin` either side).
func in_front(point: Vector3, reach: float, margin := 0.0) -> bool:
	var to := point - front_center()
	to.y = 0.0
	var ahead := to.dot(forward_of(facing_yaw))
	var side := absf(to.dot(right_of(facing_yaw)))
	return ahead >= -margin and ahead <= reach and side <= half_width() + margin


## The yaw that turns `from` toward `target` by at most `max_rad`.
static func turn_toward(from: float, target: float, max_rad: float) -> float:
	return wrapf(from + clampf(wrapf(target - from, -PI, PI), -max_rad, max_rad), -PI, PI)


## The flee point routed member number `index` runs to: the index-th of the formation's flee
## points (in turn), else a point on the fan away from `threat` (see the class notes). Pure.
func rout_point(from: Vector3, threat: Vector3, index: int) -> Vector3:
	if not flee_points.is_empty():
		return flee_points[posmod(index, flee_points.size())]
	return fan_point(from, threat, index)


## The index-th of FAN_POINTS points FAN_MIN_M..FAN_MAX_M from `from`, spread over FAN_DEG facing
## away from `threat` (alternating near and far so neighbours do not share a lane).
static func fan_point(from: Vector3, threat: Vector3, index: int) -> Vector3:
	var away := from - threat
	away.y = 0.0
	if away.length_squared() < 1e-4:
		away = Vector3.BACK
	var base := TargetingRules.yaw_of(away)
	var i := posmod(index, FAN_POINTS)
	var t := float(i) / float(maxi(1, FAN_POINTS - 1))
	var yaw := base + deg_to_rad(lerpf(-FAN_DEG * 0.5, FAN_DEG * 0.5, t))
	var dist := FAN_MIN_M if i % 2 == 0 else FAN_MAX_M
	return from + forward_of(yaw) * dist


# --------------------------------------------------------------------------- web compositions

## The spawns of one formation that a web build keeps at `scale` (front rank and banner first; see
## FormationRules.web_kept_slots). Pure.
static func web_kept_slots(slots: Array, scale: float) -> Array:
	return FormationRules.web_kept_slots(slots, scale)


# --------------------------------------------------------------------------- the update

## One update (the director's, ten times a second): drops the dead, follows the banner, the
## awareness and the threat, decides the state, turns and moves the pivot, runs the brace and the
## rally, and tells every member what to do (EnemyActor.p30_formation_update).
func update(tick: int, threat: Node3D) -> void:
	if dissolved:
		return
	var dt := float(UPDATE_TICKS) / float(Sim.TICK_RATE) if _last_update_tick < 0 \
		else float(clampi(tick - _last_update_tick, 1, 60)) / float(Sim.TICK_RATE)
	_last_update_tick = tick
	_prune()
	_follow_banner(tick)
	_follow_threat(tick, threat)
	var next := _decide_state()
	if facing_mode == "threat" and threat_pos != Vector3.INF and next != "broken" and next != "routed":
		var to := threat_pos - pivot
		to.y = 0.0
		if to.length_squared() > 1e-4:
			facing_yaw = turn_toward(facing_yaw, TargetingRules.yaw_of(to), deg_to_rad(turn_deg_s) * dt)
	if next == "advancing":
		_advance(tick, dt)
	_set_state(tick, next)
	if state == "braced":
		_brace_step(tick)
	else:
		_check_brace_done(tick)
	_rally_step(tick)
	for m in all_members():
		m.call("p30_formation_update", self)


func _decide_state() -> String:
	if state == "routed":
		return "routed"
	var standing := _standing()
	if standing.is_empty():
		for m in all_members():
			if _routed(m) or _fleeing(m):
				return "routed"
		return "broken" if peak_members > 0 else "formed"
	if cohesion() < BROKEN_COHESION:
		return "broken"
	if not aware or threat_pos == Vector3.INF:
		return "formed"
	var gap := front_gap(threat_pos)
	if brace_action != "" and brace_m > 0.0 and gap <= brace_m and in_front(threat_pos, brace_m, _threat_radius()):
		return "braced"
	if advance_mps > 0.0 and _can_advance() and gap > maxf(0.0, brace_m - ADVANCE_SLACK_M):
		return "advancing"
	return "formed"


func _set_state(tick: int, next: String) -> void:
	if next == state:
		return
	state = next
	if next == "routed":
		if _routed_emitted:
			return
		_routed_emitted = true
	_emit(tick, next)


func _emit(tick: int, what: String) -> void:
	history.append([tick, what])
	if Events.has_signal(&"formation_changed"):
		Events.formation_changed.emit(tick, id, what)
	state_changed.emit(self, what)


func _follow_banner(tick: int) -> void:
	var alive := banner_alive()
	if alive:
		_banner_seen_alive = true
	elif _banner_seen_alive and not _banner_fell_emitted:
		_banner_fell_emitted = true
		_emit(tick, "banner_fell")


## Awareness: any member aware of its target (kept AWARE_HOLD_TICKS after the last); the threat:
## `threat`'s position while aware.
func _follow_threat(tick: int, threat: Node3D) -> void:
	var any := false
	for m in all_members():
		var b := m.brain
		if b != null and b.aware and _alive(m):
			any = true
			break
	if any:
		_last_aware_tick = tick
	aware = any or tick - _last_aware_tick <= AWARE_HOLD_TICKS
	if aware and threat != null and is_instance_valid(threat) and threat.is_inside_tree():
		threat_pos = threat.global_position
		var e: Variant = threat.get("entity")
		threat_id = (e as CombatEntity).entity_id if e is CombatEntity else ""
	elif not aware:
		threat_pos = Vector3.INF
		threat_id = ""


func _threat_radius() -> float:
	var e := Sim.get_entity(threat_id) if threat_id != "" else null
	return EnemyActor.entity_radius(e) if e != null else 0.85


func _can_advance() -> bool:
	return advance_m <= 0.0 or _flat(pivot - home_pivot) < advance_m - 0.05


## Moves the pivot toward the threat along one path (NavQuery on the human layer, re-asked every
## PIVOT_REPATH_TICKS or when the goal moved PIVOT_REPATH_MOVE_M, within the director's budget).
func _advance(tick: int, dt: float) -> void:
	if threat_pos == Vector3.INF:
		return
	var goal := threat_pos - forward_of(facing_yaw) * (brace_m * 0.5 + float(ranks - 1) * 0.5 * rank_spacing_m)
	if level != null and NavQuery.has_navigation(level, 1) and (_path.is_empty() or tick - _path_tick >= PIVOT_REPATH_TICKS
			or _flat(goal - _path_goal) >= PIVOT_REPATH_MOVE_M):
		var allowed: bool = int(budget_left.call()) > 0 if budget_left.is_valid() else true
		if allowed:
			_path = NavQuery.path(level, pivot, goal, 1)
			_path_i = 0
			_path_goal = goal
			_path_tick = tick
			if spend_budget.is_valid():
				spend_budget.call(1)
	var step := advance_mps * dt
	var target := goal
	while _path_i < _path.size() and _flat(_path[_path_i] - pivot) < 0.3:
		_path_i += 1
	if _path_i < _path.size():
		target = _path[_path_i]
	var to := target - pivot
	to.y = 0.0
	var d := to.length()
	if d < 1e-3:
		return
	var moved := pivot + to / d * minf(step, d)
	if advance_m > 0.0 and _flat(moved - home_pivot) > advance_m:
		var off := moved - home_pivot
		off.y = 0.0
		moved = home_pivot + off.normalized() * advance_m
		moved.y = pivot.y
	pivot = Vector3(moved.x, pivot.y, moved.z)


# --------------------------------------------------------------------------- the brace

## Braced: when no brace runs and the pause is over, the front-rank member nearest the threat that
## is free to act takes one of the target's melee tokens and runs brace_action (the band pulse).
func _brace_step(tick: int) -> void:
	_check_brace_done(tick)
	if _brace_holder != null or tick < _brace_ready_tick or threat_id == "" or brace_action == "":
		return
	var striker := _brace_striker()
	if striker == null:
		return
	var max_attackers := int((striker.record.get("ai", {}) as Dictionary).get("max_attackers", 2))
	if not Sim.request_token(threat_id, striker.entity_id, max_attackers):
		return
	if not bool(striker.call("p30_run_action", brace_action)):
		Sim.release_token(threat_id, striker.entity_id)
		return
	_brace_holder = striker
	_brace_instance = striker.controller.instance_id
	brace_count += 1
	last_brace_tick = tick


## The brace's striker: the front-rank member nearest the threat that stands, is free to act and is
## awake; else any standing member that is.
func _brace_striker() -> EnemyActor:
	var best: EnemyActor = null
	var best_d := INF
	var best_front := false
	for m in _standing():
		if not bool(m.call("p30_can_act")):
			continue
		var front := slot_for(m) >= 0 and slot_for(m) < files
		var d := m.global_position.distance_squared_to(threat_pos)
		if (front and not best_front) or (front == best_front and (d < best_d - 1e-6
				or (absf(d - best_d) <= 1e-6 and best != null and m.entity_id < best.entity_id))):
			best = m
			best_d = d
			best_front = front
	return best


## True while the brace's striker still runs that brace.
func brace_running() -> bool:
	return _brace_holder != null and is_instance_valid(_brace_holder) and _alive(_brace_holder) \
		and _brace_holder.controller != null and _brace_holder.controller.action != null \
		and _brace_holder.controller.action.id == brace_action \
		and _brace_holder.controller.instance_id == _brace_instance


## The member running the brace now (null between braces).
func brace_holder() -> EnemyActor:
	return _brace_holder if brace_running() else null


func _check_brace_done(tick: int) -> void:
	if _brace_holder == null or brace_running():
		return
	_finish_brace()
	_brace_ready_tick = tick + ActionDef.seconds_to_ticks(BRACE_PAUSE_S)


func _finish_brace() -> void:
	if _brace_holder != null and is_instance_valid(_brace_holder) and _brace_holder.entity != null and threat_id != "":
		Sim.release_token(threat_id, _brace_holder.entity_id)
	_brace_holder = null
	_brace_instance = -1


# --------------------------------------------------------------------------- the rally

## The banner rallies (its record's `rally`) every interval while it lives and its formation is
## aware: it runs the rally action; when the action strikes, EnemyActor.p30_rally gives the members
## within radius_m their morale.
func _rally_step(tick: int) -> void:
	if not banner_alive() or not aware or tick < _next_rally_tick:
		return
	var rally: Variant = banner.record.get("rally")
	if typeof(rally) != TYPE_DICTIONARY:
		return
	if bool(banner.call("p30_run_action", str(rally.get("action", "")))):
		_next_rally_tick = tick + ActionDef.seconds_to_ticks(float(rally.get("interval_s", 10.0)))


## +`morale` to every living member within `radius_m` of `from` (the rally strikes). Returns how
## many it reached.
func rally(from: Vector3, morale: float, radius_m: float) -> int:
	var n := 0
	for m in members:
		if not _alive(m) or m.brain == null or _flat(m.global_position - from) > radius_m:
			continue
		m.brain.apply_morale(morale, "rally", Sim.tick)
		n += 1
	rally_count += 1
	return n


# --------------------------------------------------------------------------- helpers

func _prune() -> void:
	var keep: Array[EnemyActor] = []
	for m in members:
		if m != null and is_instance_valid(m) and m.is_inside_tree():
			keep.append(m)
		elif m != null and is_instance_valid(m) and m.entity != null:
			slot_of.erase(m.entity_id)
	members = keep
	if banner != null and (not is_instance_valid(banner) or not banner.is_inside_tree()):
		banner = null
	if _brace_holder != null and not is_instance_valid(_brace_holder):
		_brace_holder = null
	_update_pivot_height()


## The pivot rides at the members' mean height (the slots' y).
func _update_pivot_height() -> void:
	var sum := 0.0
	var n := 0
	for m in members:
		if _alive(m):
			sum += m.global_position.y
			n += 1
	if n > 0:
		pivot.y = sum / float(n)


## Living rank-and-file members that are not fleeing or routed.
func _standing() -> Array[EnemyActor]:
	var out: Array[EnemyActor] = []
	for m in members:
		if _alive(m) and not _fleeing(m) and not _routed(m):
			out.append(m)
	return out


static func _alive(m: EnemyActor) -> bool:
	return m != null and is_instance_valid(m) and m.is_inside_tree() and m.entity != null \
		and m.entity.combatant != null and m.entity.is_alive()


static func _fleeing(m: EnemyActor) -> bool:
	return m.brain != null and m.brain.state == EnemyBrain.AIState.FLEE


static func _routed(m: EnemyActor) -> bool:
	return m.brain != null and m.brain.state == EnemyBrain.AIState.ROUTED


static func _flat(v: Vector3) -> float:
	return Vector2(v.x, v.z).length()


## Debug lines (the director's F3 lines).
func debug_line() -> String:
	return "  formation %s [%s] %s: %d/%d standing, cohesion %.2f, banner %s, braces %d" % [id, kind, state,
		_standing().size(), peak_members, cohesion(), "up" if banner_alive() else "down", brace_count]
