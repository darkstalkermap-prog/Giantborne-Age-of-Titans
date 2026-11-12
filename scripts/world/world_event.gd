class_name WorldEvent
extends RefCounted
## One world event of a level (P37; plan M6-M9 §2.13, §5.10, decision 27): a `world_event` record and its
## run - a raid on a settlement to defend, an army column on the march. The WanderDirector owns one per
## record of its level, asks each whether it may start (at most one runs at a time) and updates the one
## that runs ten times a second. Pure where it can be (can_start_with, objective_text, route geometry), so
## tests check the rules without a world.
##
## The rules:
##   * start (can_start_with): the giant's stage within the trigger's range, its requires_flags truthy and
##     forbids_flags not, its conditions holding (quest conditions), fewer than max_runs runs so far, the
##     cooldown since the last run over (cooldown_from "end", the default, or "start"; measured in play
##     time: WanderDirector.clock_s()), the event's centre chunk loaded and ready and the giant within
##     start_radius_m (200) of the centre. Starting counts a run (<id>.runs) and its time (<id>.last_start_s),
##     makes copies of its encounters' templates where they are drawn up (a moving event's at the start of
##     its route), sends the faction folk its raiders hunt to shelter, says start_text on the HUD, puts its
##     objective in the tracker, the compass, the map and the journal (Quests' P37 section; it is tracked
##     at once and the player's choice comes back when it ends) and emits Events.world_event_started.
##   * streaming: while its centre chunk is not loaded and ready its timer stops (suspended) - its copies
##     are despawned with the chunk anyway (P24b) and come back when it loads; after abandon_after_s of that
##     it is given up with no outcome. A moving event (route) marches on as a path parameter whatever is
##     loaded; its copy is in the world only while its point lies on loaded, ready ground (the director
##     despawns it back into the abstract when its point leaves).
##   * success: every copy defeated (each member dead or routed) - success_outcome ("defended");
##     fail: the protect objective lost (lost_to_fail of its targets destroyed or killed) or its timer
##     (fail.timer_s) run out - fail_outcome; a moving event that completes its route - end_outcome.
##   * an outcome sets <id>.done and <id>.outcome (the event_done condition), its set_flags (first write
##     wins), pays its XP and items once (reward.<short>.<outcome>), burns `burn` of the protected targets
##     at least (the raiders' fire), says its text, emits Events.world_event_ended, records the end time
##     (<id>.last_end_s), routs the copies' survivors (they leave) and asks for a checkpoint, so the outcome
##     outlives a reload.
##   * the giant's death resets the attempt (reset_attempt): its copies go, its timer and losses start again,
##     and it waits for its start rule to begin again (outcomes already won stay; the death reload rolls the
##     world back to the last checkpoint). The WanderDirector carries a running event across level reloads
##     (deaths, travel) so a respawn near it moves away and it resumes.
##   * M8 gate (F2): "at most one at a time" holds for the events in play (WanderDirector.in_play: its copies
##     in the world, or its place within its start radius of the giant). A running event left behind - one
##     WAITING or SUSPENDED far off, a column marching the abstract - keeps nobody else from starting; it
##     waits (its attempt begins again) while another is in play. Its abandonment clock (unloaded_s) is not
##     the attempt's: a death or a reload keeps it (the carry, and the save through the flag
##     <id>.unloaded_since_s, the play time its centre was left at; false while it is loaded).
##   * M8 gate (F12): fail.within_m (> 0) makes the fail timer run only while the giant stands within that
##     many metres of the centre (the siege of Skarn: its clock pauses beyond 200 m, plan §5.10).
##   * M8 gate (F19): a run counted in a save (its last_start_s after its last_end_s) and no longer carried
##     (a quit to the title and a continue) is resumed by the next load of the level: its attempt begins
##     again, its run is not counted twice.
## Kill XP of its members is paid for its first xp_full_runs runs (default 3) only: nothing is farmable.

const IDLE := "idle"
const WAITING := "waiting"       ## running, its encounters not in the world yet (its start rule must hold)
const RUNNING := "running"
const SUSPENDED := "suspended"   ## running, its centre chunk not loaded and ready: timers stop
const DEFAULT_START_RADIUS_M := 200.0
const DEFAULT_SUCCESS := "defended"
const DEFAULT_ABANDON_S := 600.0
const DEFAULT_XP_FULL_RUNS := 3
const DEFAULT_SPEED_MPS := 1.2
## The folk of the factions its raiders hunt, within this of its centre, run for shelter when it starts.
const SHELTER_RADIUS_M := 160.0

var id := ""
var record: Dictionary = {}
var level_id := ""
var centre := Vector3.ZERO           ## level space
var state := IDLE                    ## IDLE, or one of WAITING / RUNNING / SUSPENDED while it runs
var elapsed_s := 0.0                 ## the fail timer's count (only while RUNNING)
var unloaded_s := 0.0                ## how long its centre has been unloaded while it runs
var copies := PackedStringArray()    ## the encounter copies of this run
var route: Route = null              ## a moving event's route (null otherwise)
var runs_this_load := 0
## Every run's ending: [{"tick", "outcome"}] (tests, debug, metrics).
var log: Array = []
## The tracked quest before it took the tracker ("" = none chosen).
var tracked_before := ""
## M8 gate fix-up 1 (N4.4): the director gave the tracker back while this run was out of play (it takes it
## again when the run comes back into play).
var tracker_given_back := false
## W23 (P39f; FOLLOWUPS "From the M8 gate review"): the tracker is on this event because the director put it
## there (start_event, an attempt, back in play) and nobody has moved it since. Only such a tracker is given
## back while the run is out of play: the player's own Track (the journal's, after a load included) stands.
## Kept across a reload in the carry and across a save in the flag <id>.tracker_held.
var holds_tracker := false
## M8 gate (F2): whether <id>.unloaded_since_s holds this run's unloaded clock (written once as its
## centre is left, cleared once it is loaded again).
var unloaded_marked := false


## A route of a moving column: road points (level space) walked from the first to the last at `speed`
## m/s, and back when round_trip. `s` is the distance walked (0 .. total()); a walk that began at `start`
## (begin_at: a column formed up part-way along) ends there again on a round trip. Pure geometry.
class Route extends RefCounted:
	var points := PackedVector3Array()
	var cum := PackedFloat32Array()
	var length := 0.0
	var round_trip := false
	var speed := DEFAULT_SPEED_MPS
	var s := 0.0
	var start := 0.0

	static func from_points(pts: PackedVector3Array, p_round_trip := false, p_speed := DEFAULT_SPEED_MPS) -> Route:
		var r := Route.new()
		for p in pts:
			if r.points.is_empty() or Vector2(p.x - r.points[r.points.size() - 1].x, p.z - r.points[r.points.size() - 1].z).length() > 0.01:
				r.points.append(p)
		r.cum.resize(r.points.size())
		var total := 0.0
		for i in r.points.size():
			if i > 0:
				total += _flat(r.points[i] - r.points[i - 1])
			r.cum[i] = total
		r.length = total
		r.round_trip = p_round_trip
		r.speed = p_speed
		return r

	func total() -> float:
		return length * (2.0 if round_trip else 1.0)

	func is_valid() -> bool:
		return points.size() >= 2 and length > 0.0

	## Starts the walk at `t` (clamped to the outbound leg).
	func begin_at(t: float) -> void:
		start = clampf(t, 0.0, length)
		s = start

	## Where the walk ends: the far end, or back at its start on a round trip.
	func end_s() -> float:
		return total() - start if round_trip else total()

	func done() -> bool:
		return s >= end_s() - 1e-3

	func advance(dt: float) -> void:
		s = minf(end_s(), s + speed * dt)

	## The distance along the outbound leg at walked distance `t` (the way back walks it in reverse).
	func leg_at(t: float) -> float:
		if round_trip and t > length:
			return clampf(2.0 * length - t, 0.0, length)
		return clampf(t, 0.0, length)

	## The point at walked distance `t` (default: now).
	func point_at(t := -1.0) -> Vector3:
		if points.is_empty():
			return Vector3.INF
		var d := leg_at(s if t < 0.0 else t)
		var i := _segment(d)
		if i < 0:
			return points[0]
		var seg := cum[i + 1] - cum[i]
		var k := 0.0 if seg <= 1e-6 else (d - cum[i]) / seg
		return points[i].lerp(points[i + 1], k)

	## The heading (yaw, the forward_of convention) of the walk at `t` (default: now).
	func yaw_at(t := -1.0) -> float:
		if points.size() < 2:
			return 0.0
		var tt := s if t < 0.0 else t
		var d := leg_at(tt)
		var i := maxi(0, _segment(d))
		var dir := points[i + 1] - points[i]
		if round_trip and tt > length:
			dir = -dir
		return TargetingRules.yaw_of(Vector3(dir.x, 0.0, dir.z))

	## The walked distance (outbound) of the route's point nearest `p` on the ground plane.
	func project(p: Vector3) -> float:
		var best := 0.0
		var best_d := INF
		for i in range(points.size() - 1):
			var a := Vector2(points[i].x, points[i].z)
			var b := Vector2(points[i + 1].x, points[i + 1].z)
			var ab := b - a
			var k := 0.0 if ab.length_squared() < 1e-9 else clampf((Vector2(p.x, p.z) - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
			var q := a + ab * k
			var dd := q.distance_squared_to(Vector2(p.x, p.z))
			if dd < best_d:
				best_d = dd
				best = cum[i] + k * (cum[i + 1] - cum[i])
		return best

	func _segment(d: float) -> int:
		if points.size() < 2:
			return -1
		for i in range(points.size() - 1):
			if d <= cum[i + 1] + 1e-6:
				return i
		return points.size() - 2

	static func _flat(v: Vector3) -> float:
		return Vector2(v.x, v.z).length()


static func make(rec: Dictionary) -> WorldEvent:
	var e := WorldEvent.new()
	e.id = str(rec.get("id", ""))
	e.record = rec
	e.level_id = str(rec.get("level", ""))
	e.centre = _vec3(rec.get("centre_m"))
	return e


# --------------------------------------------------------------------------- flags and numbers

## <event id>.done / .outcome / .runs / .last_start_s / .last_end_s (plan §2.3's event.<id>.* domain).
static func flag(event_id: String, key: String) -> String:
	return "%s.%s" % [event_id, key]


## The once-flag of an outcome's rewards: reward.<event short>.<outcome>.
static func reward_flag(event_id: String, outcome: String) -> String:
	return "reward.%s.%s" % [event_id.trim_prefix("event."), outcome]


func is_running() -> bool:
	return state != IDLE


func is_moving() -> bool:
	return typeof(record.get("route")) == TYPE_DICTIONARY or str(record.get("path", "")) != ""


func start_radius() -> float:
	return float(record.get("start_radius_m", DEFAULT_START_RADIUS_M))


func success_outcome() -> String:
	return str(record.get("success_outcome", DEFAULT_SUCCESS))


func fail_outcome() -> String:
	return str(record.get("fail_outcome", ""))


func end_outcome() -> String:
	return str(record.get("end_outcome", ""))


func display_name() -> String:
	return str(record.get("display_name", id))


## The fail timer's length (fail.timer_s; 0 = none).
func fail_timer_s() -> float:
	var fail: Variant = record.get("fail")
	return float((fail as Dictionary).get("timer_s", 0.0)) if typeof(fail) == TYPE_DICTIONARY else 0.0


## M8 gate (F12): the fail timer runs only while the giant is within this of the centre (fail.within_m;
## 0 = wherever the giant is, while the centre is loaded).
func fail_within_m() -> float:
	var fail: Variant = record.get("fail")
	return float((fail as Dictionary).get("within_m", 0.0)) if typeof(fail) == TYPE_DICTIONARY else 0.0


## M8 gate (F19): true when the saved flags say a run of this event was in progress - started after the
## last one ended (or none ever ended) and without an outcome since. Pure but for `flags`.
func run_in_progress(flags: Dictionary) -> bool:
	var started: Variant = flags.get(flag(id, "last_start_s"))
	if runs(flags) <= 0 or not SchemaUtil.is_number(started):
		return false
	var ended: Variant = flags.get(flag(id, "last_end_s"))
	return not SchemaUtil.is_number(ended) or float(ended) < float(started)


func runs(flags: Dictionary) -> int:
	return int(flags.get(flag(id, "runs"), 0)) if SchemaUtil.is_number(flags.get(flag(id, "runs"))) else 0


## The share of its members' kill XP this run pays: 1 for its first xp_full_runs runs, then 0.
func xp_scale_for_run(run: int) -> float:
	return 1.0 if run <= int(record.get("xp_full_runs", DEFAULT_XP_FULL_RUNS)) else 0.0


## Why it may not start now ("" = it may), from the facts in `ctx`: {"stage": int, "flags": Dictionary,
## "condition_ctx": Dictionary (quest conditions), "now_s": float (play time), "centre_ready": bool,
## "distance_m": float (the giant to its centre, horizontally)}. Pure.
func can_start_with(ctx: Dictionary) -> String:
	if state != IDLE:
		return "running"
	var trig: Dictionary = record.get("trigger", {}) if typeof(record.get("trigger")) == TYPE_DICTIONARY else {}
	var stage := int(ctx.get("stage", 0))
	if SchemaUtil.is_number(trig.get("min_stage")) and stage < int(trig.min_stage):
		return "stage"
	if SchemaUtil.is_number(trig.get("max_stage")) and stage > int(trig.max_stage):
		return "stage"
	var flags: Dictionary = ctx.get("flags", {})
	for f: Variant in trig.get("requires_flags", []):
		if not QuestConditions.truthy(flags.get(str(f))):
			return "flags"
	for f: Variant in trig.get("forbids_flags", []):
		if QuestConditions.truthy(flags.get(str(f))):
			return "flags"
	if typeof(trig.get("conditions")) == TYPE_ARRAY and not (trig.conditions as Array).is_empty():
		var cctx: Dictionary = ctx.get("condition_ctx", {})
		if cctx.is_empty():
			cctx = QuestConditions.empty_context()
			cctx["flags"] = flags
		if not QuestConditions.all_hold(trig.conditions, cctx):
			return "conditions"
	var max_runs := int(trig.get("max_runs", 0))
	if max_runs > 0 and runs(flags) >= max_runs:
		return "max_runs"
	var cooldown := float(trig.get("cooldown_s", 0.0))
	if cooldown > 0.0:
		var key := "last_start_s" if str(trig.get("cooldown_from", "end")) == "start" else "last_end_s"
		var last: Variant = flags.get(flag(id, key))
		if SchemaUtil.is_number(last) and float(ctx.get("now_s", 0.0)) - float(last) < cooldown:
			return "cooldown"
	if not bool(ctx.get("centre_ready", false)):
		return "unloaded"
	if float(ctx.get("distance_m", INF)) > start_radius():
		return "far"
	return ""


## The protect objective's targets (world ids of props or entity ids of people).
func targets() -> PackedStringArray:
	var obj: Variant = record.get("objective")
	if typeof(obj) != TYPE_DICTIONARY or typeof(obj.get("targets")) != TYPE_ARRAY:
		return PackedStringArray()
	return PackedStringArray(obj.targets)


## How many targets lose the objective (lost_to_fail, at most the number of targets; 0 = none can).
func lost_to_fail() -> int:
	var obj: Variant = record.get("objective")
	if typeof(obj) != TYPE_DICTIONARY:
		return 0
	return mini(int(obj.get("lost_to_fail", 0)), targets().size())


## The protected targets lost now (destroyed props, killed people), by the saved world and `dead` ({id:
## true}: deaths seen in this load). Pure but for WorldState.
func lost_targets(dead: Dictionary = {}) -> PackedStringArray:
	var out := PackedStringArray()
	for t in targets():
		if WorldState.is_destroyed(t) or WorldState.is_killed(t) or dead.has(t):
			out.append(t)
	return out


## The tracker's line: objective.text with {standing} and {total} (the protected targets still standing
## and listed), else the event's display name.
static func objective_text(text: String, standing: int, total: int) -> String:
	return text.replace("{standing}", str(standing)).replace("{total}", str(total))


static func _vec3(v: Variant) -> Vector3:
	if typeof(v) == TYPE_ARRAY and (v as Array).size() == 3:
		return Vector3(float(v[0]), float(v[1]), float(v[2]))
	return Vector3.ZERO


# --------------------------------------------------------------------------- data checks (GameData)

## The living world's cross-record checks (GameData's post-pass, anchor P37): {"errors", "warnings"}.
##   * every wander table entry's template is an encounter record with template true of the level of the
##     table's region, and every world event's encounters are templates of the event's level;
##   * a template is leashed (it walks a streamed world) and its spawns persist nothing of their own;
##   * a route's places (and an event's objective marker) are in the level's world index when it has one;
##   * warnings: a template no table or event uses; a protect target the index does not know. (A spawn's
##     `prefer` naming no record is no warning: it is a later package's archetype, and the copies use the
##     spawn's definition until it lands.)
static func data_problems(records: Dictionary, record_paths: Dictionary = {}) -> Dictionary:
	var errors := PackedStringArray()
	var warnings := PackedStringArray()
	var used := {}
	var indexes := {}
	var ids := records.keys()
	ids.sort()
	for id: Variant in ids:
		var rec: Variant = records[id]
		if typeof(rec) != TYPE_DICTIONARY:
			continue
		var ctx := "%s (%s)" % [record_paths.get(id, "?"), id]
		match str(rec.get("type", "")):
			"wander_table":
				var level := str((records.get(str(rec.get("region", "")), {}) as Dictionary).get("level", ""))
				var j := 0
				for e: Variant in rec.get("entries", []):
					if typeof(e) == TYPE_DICTIONARY:
						var t := str(e.get("template", ""))
						used[t] = true
						errors.append_array(_template_errors(records, t, level, "%s.entries[%d]" % [ctx, j]))
						errors.append_array(_route_errors(records, indexes, e.get("route"), level, "%s.entries[%d].route" % [ctx, j]))
					j += 1
			"world_event":
				var level := str(rec.get("level", ""))
				for t: Variant in rec.get("encounters", []):
					used[str(t)] = true
					errors.append_array(_template_errors(records, str(t), level, ctx + ".encounters"))
				errors.append_array(_route_errors(records, indexes, rec.get("route"), level, ctx + ".route"))
				var idx := _index_of(records, indexes, level)
				var obj: Variant = rec.get("objective")
				if idx != null and typeof(obj) == TYPE_DICTIONARY:
					if str(obj.get("marker", "")) != "" and not idx.position_of(str(obj.marker)).is_finite():
						errors.append("%s.objective.marker: '%s' is not in %s's world index" % [ctx, obj.marker, level])
					for t: Variant in obj.get("targets", []):
						if not idx.position_of(str(t)).is_finite():
							warnings.append("%s.objective.targets: '%s' is not in %s's world index (yet)" % [ctx, t, level])
	for id: Variant in ids:
		var rec: Variant = records[id]
		if typeof(rec) != TYPE_DICTIONARY or str(rec.get("type", "")) != "encounter" or not bool(rec.get("template", false)):
			continue
		var ctx := "%s (%s)" % [record_paths.get(id, "?"), id]
		if not used.has(str(id)):
			warnings.append("%s: a template no wander table or world event uses" % ctx)
		var i := 0
		for s: Variant in rec.get("spawns", []):
			if typeof(s) == TYPE_DICTIONARY:
				if bool(s.get("persist_death", false)):
					errors.append("%s.spawns[%d]: a template's spawn persists nothing (persist_death false): its copies are new every time" % [ctx, i])
				if str(s.get("loot_table", "")) != "":
					errors.append("%s.spawns[%d]: a template's spawn drops no loot (it would be farmable)" % [ctx, i])
			i += 1
	return {"errors": errors, "warnings": warnings}


static func _template_errors(records: Dictionary, template_id: String, level: String, ctx: String) -> PackedStringArray:
	var out := PackedStringArray()
	var t: Variant = records.get(template_id)
	if typeof(t) != TYPE_DICTIONARY or str(t.get("type", "")) != "encounter":
		return out   # the reference check reports a missing or mistyped one
	if not bool(t.get("template", false)):
		out.append("%s: %s is not a template (template: true): a placed encounter is never copied" % [ctx, template_id])
	elif level != "" and str(t.get("level", "")) != level:
		out.append("%s: the template %s belongs to %s, not %s" % [ctx, template_id, t.get("level", ""), level])
	elif not (SchemaUtil.is_number(t.get("leash_radius_m")) and float(t.leash_radius_m) > 0.0):
		out.append("%s: the template %s needs a leash_radius_m (its copies walk a streamed world)" % [ctx, template_id])
	return out


static func _route_errors(records: Dictionary, indexes: Dictionary, route: Variant, level: String, ctx: String) -> PackedStringArray:
	var out := PackedStringArray()
	if typeof(route) != TYPE_DICTIONARY:
		return out
	var idx := _index_of(records, indexes, level)
	if idx == null:
		return out
	for key: String in ["from", "to"]:
		var place := str((route as Dictionary).get(key, ""))
		if place != "" and not idx.position_of(place).is_finite():
			out.append("%s.%s: '%s' is not in %s's world index" % [ctx, key, place, level])
	return out


## The world index of `level` from its record (loaded once per check; null without one).
static func _index_of(records: Dictionary, indexes: Dictionary, level: String) -> WorldIndex:
	if indexes.has(level):
		return indexes[level]
	var idx: WorldIndex = null
	var path := str((records.get(level, {}) as Dictionary).get("index", ""))
	if path != "" and ResourceLoader.exists(path):
		idx = load(path) as WorldIndex
	indexes[level] = idx
	return idx
