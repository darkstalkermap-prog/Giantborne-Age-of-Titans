class_name ValleyWalk
extends Node
## The scripted Valley walk (P14; plan §3.16 item 4, §5.4): first it measures what the AI LOD tier-2
## one-box proxy saves on distant enemies (draw calls when rendered, CPU per tick always), then a
## stage-1 giant walks through every district of the Valley with the EncounterDirector running, so
## the PerfProbe sees the Valley's CPU per tick, draw calls and node counts along the way. The
## Autopilot runs it for --scenario=valley_walk (with --mode=valley --new-game) and ends the run
## when `done`.
##
## The walk: LEGS in order, each to an objective marker. A leg follows a navigation path on the
## giant's own layers (stage 1: the small-giant layer) with the stick, sprinting, looking along
## each segment; a leg whose path does not reach its marker (behind the Deadfall, the cart
## barricade or the practice gate at stage 1) is teleported instead, as is a waypoint the giant
## makes no progress toward for STUCK_S (a wolf in the way). --walk-teleport teleports every leg
## (stops and views only: software-rendered draw-call captures are slow). At the end of each leg
## the camera turns a full circle (PAN_TICKS), so "any view" of the district is sampled. The
## PerfProbe's section is the district the giant stands in.
##
## The giant carries the hidden status.debug_invulnerable (as in the stress route): the
## encounters it passes engage it, and a death would end the capture.
##
## The LOD comparison (first, from the Cradle, while every encounter is dormant and far away):
## every dormant encounter without a boss whose centre is beyond the director's mid_m is
## force-activated (as the budget allows: 12 of the 15 members), so its members spawn at tier 2
## (dormant, the one-box Visual/LodProxy shown); every member on tier 2 beyond mid_m is followed.
## The camera faces them and the probe samples LOD_SAMPLE_TICKS
## ticks (section "lod_tier2"); then the director's distances put every member on tier 1 (reduced
## AI rates, full rig; "lod_tier1"), then on tier 0 (full rates; "lod_tier0"), each for the same
## number of ticks after LOD_SETTLE_TICKS; then they are put back. The sections give the CPU per
## tick of the same members at each tier and, when rendered, the draw calls (N/A headless); the
## tier of every member is checked either way. The forced encounters deactivate on their own
## (10 s unaware, the giant beyond their radius) while the walk begins.

const STAGE := 1
const STATUS_INVULNERABLE := "status.debug_invulnerable"
const LEVEL_SCHEMA := preload("res://scripts/core/schemas/level_schema.gd")
## [label, objective marker id]: every district (hollow, forest, village, quarry, barrow, ruins,
## kingsfall), the gated ones last.
const LEGS := [
	["Giant's Hollow", "valley.marker.dummies"],
	["forest trail", "valley.marker.forest_trail"],
	["wolf clearing", "valley.marker.wolves_a"],
	["hunters' camp", "valley.marker.hunters"],
	["ogre clearing", "valley.marker.ogre_clearing"],
	["Grove", "valley.marker.grove_shrine"],
	["village gate", "valley.marker.village_gate"],
	["village square", "valley.marker.elder"],
	["north fields", "valley.marker.field_ogre"],
	["quarry", "valley.marker.quarry_cache"],
	["Barrow", "valley.marker.crown"],
	["bridge", "valley.marker.bridge"],
	["ruins courtyard", "valley.marker.ruins_courtyard"],
	["causeway", "valley.marker.causeway"],
	["Kingsfall", "valley.marker.kingsfall_shrine"],
	["Kingsfall oak", "valley.marker.kingsfall_oak"],
]
## A path reaches a leg's marker when it ends this close to it (horizontally).
const REACH_TOLERANCE_M := 3.0
const WAYPOINT_M := 1.5
## No 0.5 m of progress toward a waypoint for this long: teleport to it.
const STUCK_S := 4.0
const PAN_TICKS := 120
const NAV_WAIT_TICKS := 240
const LOD_SETTLE_TICKS := 20
const LOD_SAMPLE_TICKS := 60
## A director distance beyond the map: near_m and mid_m set to it put every member on tier 0;
## mid_m alone (near_m 0), on tier 1.
const LOD_OFF_M := 100000.0

var teleport_only := false
var done := false
var player: GiantPlayer
var level: LevelRoot
var probe: PerfProbe
var legs: Array = []          ## per leg: {"label", "marker", "district", "mode", "seconds", "waypoints", "stuck_teleports"}
var teleports := 0
var stuck_teleports := 0
var player_deaths := 0
var walked_m := 0.0
var lod_compare: Dictionary = {}
var ticks := 0
## Encounters the director activated during the walk: [{"tick", "s", "id"}] (spawns cost a hitch).
var activations: Array = []

var _state := "wait_nav"
var _state_ticks := 0
var _leg := -1
var _leg_start_tick := 0
var _path := PackedVector3Array()
var _wp := 0
var _wp_best := INF
var _wp_since := 0
var _pan_yaw := 0.0
var _last_pos := Vector3.INF
var _was_dead := false
var _districts: Dictionary = {}
var _lod_members: Array = []
var _lod_saved := {}


func start(p: GiantPlayer, lv: LevelRoot, perf: PerfProbe = null) -> void:
	player = p
	level = lv
	probe = perf
	if not Events.encounter_activated.is_connected(_on_encounter_activated):
		Events.encounter_activated.connect(_on_encounter_activated)
	p.router.use_injection = true
	_keep_invulnerable()
	if p.growth != null and p.current_growth_stage() != STAGE:
		p.growth.debug_set_stage(STAGE)
	_set_state("wait_nav")


func _on_encounter_activated(tick: int, encounter_id: String) -> void:
	activations.append({"tick": tick, "s": snappedf(float(ticks) / float(Sim.TICK_RATE), 0.01), "id": encounter_id})


func _physics_process(_delta: float) -> void:
	if done or player == null or not is_instance_valid(player) or level == null or not is_instance_valid(level):
		return
	ticks += 1
	_state_ticks += 1
	if player.controller.state == CombatController.State.DEAD:
		if not _was_dead:
			player_deaths += 1
		_was_dead = true
		return
	_was_dead = false
	_keep_invulnerable()
	var pos := player.global_position
	if _last_pos != Vector3.INF:
		walked_m += _flat(pos, _last_pos)
	_last_pos = pos
	var district := level.district_at(pos)
	if district != "":
		_districts[district] = true
	if probe != null and not _state.begins_with("lod"):
		probe.section = district if district != "" else "outside"
	match _state:
		"wait_nav":
			_wait_for_navigation()
		"leg":
			_walk_leg()
		"pan":
			_pan()
		"lod_spawn", "lod_tier2", "lod_tier1", "lod_tier0":
			_lod_step()


func _set_state(s: String) -> void:
	_state = s
	_state_ticks = 0


func _keep_invulnerable() -> void:
	var e := player.entity
	if e.is_alive() and (not e.combatant.statuses.has(STATUS_INVULNERABLE)
			or e.combatant.statuses.remaining_s(STATUS_INVULNERABLE, Sim.tick) < 60.0):
		e.apply_status(STATUS_INVULNERABLE, NAN, -1.0, "valley_walk")


func _layers() -> int:
	return int(player.profile.get("nav_layers", 8))


func _wait_for_navigation() -> void:
	player.router.set_injected_move(Vector2.ZERO)
	var map := level.nav_map()
	# The probe leaves its first ticks out (start-up): the LOD comparison starts after them.
	var ready := NavigationServer3D.map_get_iteration_id(map) > 0 \
		and (probe == null or probe.ticks_seen > probe.warmup_ticks)
	if ready:
		var first := _leg_target(0)
		var path := NavigationServer3D.map_get_path(map, player.global_position, first, true, _layers())
		ready = path.size() > 0
	if ready or _state_ticks >= NAV_WAIT_TICKS:
		_begin_lod()


# --------------------------------------------------------------------------- legs

## Where leg i ends: its marker, snapped to the giant's navigation layer when that layer has a
## point within 3 m (a marker on a ledge stays where it is).
func _leg_target(i: int) -> Vector3:
	var m := level.marker(str(LEGS[i][1]))
	var at := m.global_position if m != null else player.global_position
	var region := level.nav_region(_lowest_bit(_layers()))
	if region.is_valid():
		var on := NavigationServer3D.region_get_closest_point(region, at)
		if _flat(on, at) <= 3.0:
			return on
	return at


func _begin_leg(i: int) -> void:
	if i >= LEGS.size():
		_finish()
		return
	_leg = i
	_leg_start_tick = ticks
	var target := _leg_target(i)
	var entry := {"label": LEGS[i][0], "marker": LEGS[i][1], "district": "", "mode": "walked",
		"seconds": 0.0, "waypoints": 0, "stuck_teleports": 0}
	legs.append(entry)
	_path = PackedVector3Array()
	if not teleport_only:
		var path := NavigationServer3D.map_get_path(level.nav_map(), player.global_position, target, true, _layers())
		if path.size() > 0 and _flat(path[path.size() - 1], target) <= REACH_TOLERANCE_M:
			_path = path
	if _path.is_empty():
		entry.mode = "teleported"
		teleports += 1
		_teleport(target)
		_end_leg()
		return
	entry.waypoints = _path.size()
	_wp = 0
	_skip_reached_waypoints()
	_wp_best = INF
	_wp_since = ticks
	_set_state("leg")


func _skip_reached_waypoints() -> void:
	while _wp < _path.size() and _flat(_path[_wp], player.global_position) < WAYPOINT_M:
		_wp += 1


func _walk_leg() -> void:
	var r := player.router
	var before := _wp
	_skip_reached_waypoints()
	if _wp != before:
		_wp_best = INF   # progress is measured per waypoint
		_wp_since = ticks
	if _wp >= _path.size():
		_end_leg()
		return
	var wp := _path[_wp]
	var to := wp - player.global_position
	to.y = 0.0
	var d := to.length()
	if d < _wp_best - 0.5:
		_wp_best = d
		_wp_since = ticks
	elif ticks - _wp_since > int(STUCK_S * Sim.TICK_RATE):
		stuck_teleports += 1
		legs[legs.size() - 1].stuck_teleports = int(legs[legs.size() - 1].stuck_teleports) + 1
		_teleport(wp)
		_wp += 1
		_wp_best = INF
		_wp_since = ticks
		return
	var yaw := TargetingRules.yaw_of(to)
	player.camera_rig.yaw = yaw
	r.set_injected_move(Vector2(0, 1))
	r.set_injected_hold(&"sprint", d > 4.0)


func _end_leg() -> void:
	var entry: Dictionary = legs[legs.size() - 1]
	entry.seconds = snappedf(float(ticks - _leg_start_tick) / float(Sim.TICK_RATE), 0.01)
	entry.district = level.district_at(player.global_position)
	player.router.set_injected_move(Vector2.ZERO)
	player.router.set_injected_hold(&"sprint", false)
	_pan_yaw = player.camera_rig.yaw
	_set_state("pan")


func _pan() -> void:
	player.router.set_injected_move(Vector2.ZERO)
	player.camera_rig.yaw = _pan_yaw + TAU * float(_state_ticks) / float(PAN_TICKS)
	if _state_ticks >= PAN_TICKS:
		player.camera_rig.yaw = _pan_yaw
		_begin_leg(_leg + 1)


func _teleport(at: Vector3) -> void:
	var t := Transform3D(Basis(Vector3.UP, player.camera_rig.yaw), at + Vector3.UP * 0.1)
	GameSession.place_player(player, t)
	_last_pos = Vector3.INF


# --------------------------------------------------------------------------- the LOD comparison

func _begin_lod() -> void:
	player.router.set_injected_move(Vector2.ZERO)
	var d := level.director()
	if d == null:
		lod_compare = {"skipped": "no EncounterDirector"}
		_begin_leg(0)
		return
	var forced := PackedStringArray()
	var ppos := player.global_position
	for id in d.encounter_ids():
		if d.encounter_state(id) != EncounterDirector.DORMANT or _has_boss(id):
			continue
		var rec := GameData.get_record(id)
		var c: Variant = rec.get("center_m")
		if typeof(c) != TYPE_ARRAY or (c as Array).size() != 3:
			continue
		var centre := level.global_transform * Vector3(float(c[0]), float(c[1]), float(c[2]))
		if _flat(centre, ppos) <= d.mid_m + 10.0:
			continue
		d.force_activate(id)
		forced.append(id)
	d.update_now()
	lod_compare = {"forced": forced, "members": 0}
	_lod_saved = {"near_m": d.near_m, "mid_m": d.mid_m}
	_set_state("lod_spawn")


func _lod_step() -> void:
	var d := level.director()
	player.router.set_injected_move(Vector2.ZERO)
	if _state == "lod_spawn" and _state_ticks == 1:
		_lod_members = _distant_dormant_members(d)
		lod_compare.members = _lod_members.size()
		if _lod_members.is_empty():
			lod_compare["skipped"] = "no distant encounter could spawn"
			_begin_leg(0)
			return
		lod_compare["tier2_members"] = _count_tier(2)
		lod_compare["proxies_shown"] = _count_proxies(true)
	_face_members()
	if probe != null:
		probe.section = _state if _state_ticks > LOD_SETTLE_TICKS and _state != "lod_spawn" else "lod_settle"
	var phase_end := LOD_SETTLE_TICKS if _state == "lod_spawn" else LOD_SETTLE_TICKS + LOD_SAMPLE_TICKS
	if _state == "lod_spawn" and _state_ticks >= phase_end:
		_set_state("lod_tier2")
	elif _state == "lod_tier2" and _state_ticks >= phase_end:
		# Tier 1 for everyone: the tier-0 radius at 0, tier 1 out to beyond the map.
		d.near_m = 0.0
		d.mid_m = LOD_OFF_M
		d.update_now()
		lod_compare["tier1_members"] = _count_tier(1)
		_set_state("lod_tier1")
	elif _state == "lod_tier1" and _state_ticks >= phase_end:
		d.near_m = LOD_OFF_M
		d.mid_m = LOD_OFF_M
		d.update_now()
		lod_compare["tier0_members"] = _count_tier(0)
		lod_compare["bodies_shown"] = _count_proxies(false)
		_set_state("lod_tier0")
	elif _state == "lod_tier0" and _state_ticks >= phase_end:
		if probe != null:
			probe.section = "lod_done"
		d.near_m = float(_lod_saved.near_m)
		d.mid_m = float(_lod_saved.mid_m)
		d.update_now()
		lod_compare["restored_tier2_members"] = _count_tier(2)
		_record_lod_samples()
		_begin_leg(0)


## The per-tier numbers of the comparison from the probe's sections: CPU per tick (whole tick and
## Sim.step, means and p95) and, when rendered, the mean draw calls and what tier 2 saves.
func _record_lod_samples() -> void:
	if probe == null:
		return
	var r := probe.result()
	var secs: Dictionary = r.sections
	for tier: String in ["tier2", "tier1", "tier0"]:
		var sec: Dictionary = secs.get("lod_" + tier, {})
		var tick: Variant = sec.get("cpu_tick_ms")
		var sim: Variant = sec.get("sim_ms")
		if tick is Dictionary:
			lod_compare["cpu_tick_ms_%s" % tier] = {"mean": tick.mean, "p95": tick.p95}
		if sim is Dictionary:
			lod_compare["sim_ms_%s" % tier] = {"mean": sim.mean, "p95": sim.p95}
	if typeof(r.draw_calls) == TYPE_STRING:
		lod_compare["draw_calls"] = r.draw_calls
		return
	var t2: Variant = (secs.get("lod_tier2", {}) as Dictionary).get("draw_calls")
	var t1: Variant = (secs.get("lod_tier1", {}) as Dictionary).get("draw_calls")
	var t0: Variant = (secs.get("lod_tier0", {}) as Dictionary).get("draw_calls")
	if t2 is Dictionary and t0 is Dictionary:
		lod_compare["draw_calls_tier2_mean"] = t2.mean
		if t1 is Dictionary:
			lod_compare["draw_calls_tier1_mean"] = t1.mean
		lod_compare["draw_calls_tier0_mean"] = t0.mean
		lod_compare["draw_calls_saved"] = snappedf(float(t0.mean) - float(t2.mean), 0.1)


## The members the comparison follows: every spawned, living member of a non-boss encounter that
## is now on tier 2 beyond the director's mid_m (the forced encounters' and those still active
## from earlier legs; an engaged member stays on tier 0 and is left out).
func _distant_dormant_members(d: EncounterDirector) -> Array:
	var out: Array = []
	var ppos := player.global_position
	for id in d.encounter_ids():
		if _has_boss(id):
			continue
		for m in d.members_of(id):
			var n := d.spawned(m)
			if n == null or not is_instance_valid(n) or d.member_status(m) != EncounterDirector.SPAWNED:
				continue
			var e: Variant = n.get("entity")
			if not (e is CombatEntity) or not (e as CombatEntity).is_alive() or not ("lod_tier" in n):
				continue   # an actor without AI LOD (an NPC that is not an EnemyActor) is not compared
			if int(n.get("lod_tier")) == 2 and _flat(n.global_position, ppos) > d.mid_m:
				out.append(n)
	return out


func _count_tier(tier: int) -> int:
	var n := 0
	for m: Variant in _lod_members:
		if is_instance_valid(m) and int((m as Node).get("lod_tier")) == tier:
			n += 1
	return n


## Members showing their LodProxy (proxy true) or their full Visual/Body (proxy false).
func _count_proxies(proxy: bool) -> int:
	var n := 0
	for m: Variant in _lod_members:
		if not is_instance_valid(m):
			continue
		var node := (m as Node).get_node_or_null("Visual/LodProxy" if proxy else "Visual/Body") as Node3D
		if node != null and node.visible:
			n += 1
	return n


func _face_members() -> void:
	var sum := Vector3.ZERO
	var n := 0
	for m: Variant in _lod_members:
		if is_instance_valid(m):
			sum += (m as Node3D).global_position
			n += 1
	if n == 0:
		return
	var to := sum / float(n) - player.global_position
	to.y = 0.0
	if to.length_squared() > 0.01:
		player.camera_rig.yaw = TargetingRules.yaw_of(to)


static func _has_boss(encounter_id: String) -> bool:
	for s: Variant in GameData.get_record(encounter_id).get("spawns", []):
		if typeof(s) == TYPE_DICTIONARY and GameData.get_record(str(s.get("definition", ""))).has("boss"):
			return true
	return false


func _finish() -> void:
	player.router.set_injected_move(Vector2.ZERO)
	player.router.set_injected_hold(&"sprint", false)
	_set_state("done")
	done = true


# --------------------------------------------------------------------------- the report

## The walk's report (Autopilot puts it into AUTOPILOT_RESULT under "valley_walk").
func result() -> Dictionary:
	var walked := 0
	for e: Dictionary in legs:
		if str(e.mode) == "walked":
			walked += 1
	var ids := _districts.keys()
	ids.sort()
	return {
		"stage": STAGE,
		"teleport_only": teleport_only,
		"done": done,
		"simulated_s": snappedf(float(ticks) / float(Sim.TICK_RATE), 0.01),
		"legs": legs,
		"legs_walked": walked,
		"legs_teleported": teleports,
		"stuck_teleports": stuck_teleports,
		"walked_m": snappedf(walked_m, 0.1),
		"districts": ids,
		"lod_compare": lod_compare,
		"activations": activations,
		"player_deaths": player_deaths,
		"check_failures": check_failures(),
	}


## The walk's own checks ([] = passed): it finished, saw every district of the level record, the
## giant never died, and the LOD comparison had distant members on tier 2 (proxies shown), then
## on tier 0 (bodies shown), then back on tier 2.
func check_failures() -> PackedStringArray:
	var out := PackedStringArray()
	if not done:
		out.append("the walk did not finish (leg %d of %d, state %s)" % [maxi(_leg + 1, 0), LEGS.size(), _state])
	if level != null and is_instance_valid(level):
		var missing := PackedStringArray()
		for id in LEVEL_SCHEMA.district_ids(level.level_record()):
			if not _districts.has(id):
				missing.append(id)
		if not missing.is_empty():
			out.append("districts never visited: %s" % ", ".join(missing))
	if player_deaths > 0:
		out.append("the giant died %d time(s)" % player_deaths)
	if done and not lod_compare.has("skipped"):
		var n := int(lod_compare.get("members", 0))
		if int(lod_compare.get("tier2_members", -1)) != n or int(lod_compare.get("proxies_shown", -1)) != n:
			out.append("LOD comparison: %d members, %d on tier 2, %d proxies shown" % [n,
				int(lod_compare.get("tier2_members", -1)), int(lod_compare.get("proxies_shown", -1))])
		if int(lod_compare.get("tier1_members", -1)) != n:
			out.append("LOD comparison: %d members, %d on tier 1" % [n, int(lod_compare.get("tier1_members", -1))])
		if int(lod_compare.get("tier0_members", -1)) != n or int(lod_compare.get("bodies_shown", -1)) != n:
			out.append("LOD comparison: %d members, %d on tier 0, %d bodies shown" % [n,
				int(lod_compare.get("tier0_members", -1)), int(lod_compare.get("bodies_shown", -1))])
		if int(lod_compare.get("restored_tier2_members", -1)) != n:
			out.append("LOD comparison: %d members, %d back on tier 2" % [n,
				int(lod_compare.get("restored_tier2_members", -1))])
	elif done and str(lod_compare.get("skipped", "")) != "":
		out.append("LOD comparison skipped: %s" % lod_compare.skipped)
	return out


static func _lowest_bit(mask: int) -> int:
	for i in 32:
		if mask & (1 << i):
			return 1 << i
	return 1


static func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()
