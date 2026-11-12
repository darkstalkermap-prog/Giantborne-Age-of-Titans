class_name WorldWalk
extends Node
## The streaming walk (P24a; plan M6-M9 §3.6, §6.3): the giant follows a route through a streamed
## world while the probe and the streamer measure it. The Autopilot runs it for
## --scenario=world_walk on a WorldRoot level (the test world: --level=res://scenes/test/
## test_world.tscn; the real world from P25: --mode=world --new-game) and ends the run when `done`.
##
## Options (after "--"):
##   --route=x:z;x:z;...   the waypoints (world x and z; the ground gives y). Default: the level's
##                         Markers/Route children in order (the test world's loop with four seam
##                         crossings, the town's street, the east, the 35-degree plateau, the pond;
##                         M7 polish: the real world's from tools/data/world/world.json's walk_route,
##                         about 400 m from the Crownmarch through the Drowned Steps and the
##                         Greywood's edge and back, four region changes and three seams). A level
##                         with neither is a usage error (NO_ROUTE), not an unfinished walk.
##   --walk-speed=M        carry the giant along the route at M m/s (16: a stage-6 sprint, the
##                         streaming budget's case) instead of walking it with the stick (sprinting).
##   --walk-stage=N        grow the giant to stage N first (M8 gate, F21: the growth is retried every
##                         STAGE_RETRY_TICKS while the just-placed giant is not yet on the floor and free,
##                         for at most STAGE_WAIT_TICKS; a giant that never reaches stage N fails the walk,
##                         "stage N not reached", and walks nothing).
##   --walk-laps=N         walk the route N times (default 1).
##   --walk-travel=<id>    P39f (plan §6.3, §6.6: tools/web/world_check.mjs): fast travel to this waystone
##                         or shrine first, once a run, the map's way (Events.travel_requested,
##                         "fast_travel"). On the level the run starts in (a Continue from the title, or
##                         --mode=world) the walk waits TRAVEL_SETTLE_TICKS, then asks for the travel as
##                         soon as GameSession.travel_refusal allows it; the travel reloads the level, and
##                         on the level it arrives in the walk sets off from where the travel put the giant,
##                         along the route (arrival -> the route's points). The run's travel lives in
##                         travel_run (a static: the reload frees this node). A refusal no wait can end
##                         (the place not visited, not open, too narrow, unknown; no campaign), or one
##                         still holding after TRAVEL_WAIT_TICKS, fails the walk alone ("fast travel to X
##                         refused: why", travel_error), which then walks nothing; so does an arrival more
##                         than ARRIVAL_SLACK_M from the place.
## The giant carries the hidden status.debug_invulnerable (as in the Valley walk): encounters it
## passes engage it, and a death would end the measurement.
##
## It prints "WORLD_WALK_LEVEL {...}" when a walk starts on a level (its level, respawn, the giant's
## stage and place, and the travel: "none", "pending" or "arrived"), "WORLD_TRAVEL {...}" when the travel
## is asked for, "WORLD_WALK_START {...}" when the walk sets off (after the starting ring) and
## "WORLD_WALK_END {...}" when it ends: tools/web/stream_check.mjs times the page's frames between the
## last two, tools/web/world_check.mjs also the Continue's and the travel's loads.
## Per tick it records the margin to unloaded ground (the distance from the giant to the nearest grid
## chunk that is not loaded), the most chunks loaded, chunk and region changes, and (walking) ticks
## with the feet more than UNDER_TERRAIN_M under the ground; the probe's section is the chunk the
## giant stands in. The streamer's statistics (loads, unloads, thrash, work per frame p50 / p99 /
## max) are reset when the walk starts, after the starting ring. result() is the report;
## check_failures holds: a margin under MARGIN_REQUIRED_M, thrash, more than MAX_LOADED chunks,
## ticks under the terrain, a route not finished - or, alone, the usage error of a walk with no
## route (usage_error; the Autopilot's run then fails with it, and tools/web/stream_check.mjs exits 2),
## or the stage not reached (stage_error, M8 gate F21). The report names the stage the giant walked at.

const STATUS_INVULNERABLE := "status.debug_invulnerable"
const WAYPOINT_M := 4.0
## No 0.5 m of progress toward a waypoint for this long while walking: teleport to it.
const STUCK_S := 5.0
const MARGIN_REQUIRED_M := 200.0
const MAX_LOADED := 25
const UNDER_TERRAIN_M := 0.25
## The longest the walk waits for the ring at its first point (a --route starting elsewhere on a slow
## machine: about 9 chunks of steps at a few a frame) before it sets off anyway.
const RING_WAIT_TICKS := 3600
## The check failure of a walk without a route of at least two points (M7 polish): a usage error.
const NO_ROUTE := "usage: no route to walk - the level has no Markers/Route and no --route=x:z;x:z;... of two or more points was given"
## M8 gate (F21): the growth to --walk-stage waits this long at most (the giant just placed falls to the
## floor first: PlayerGrowth refuses a giant that is not on the floor and free, "busy"), asking again this
## often (each refusal prints a line).
const STAGE_WAIT_TICKS := 600
const STAGE_RETRY_TICKS := 15
## P39f (--walk-travel): the level's first ticks pass before the travel is asked for (the giant lands,
## the load's checkpoint is taken); a travel the blockers hold back is asked again each tick for at most
## TRAVEL_WAIT_TICKS; the giant must arrive within ARRIVAL_SLACK_M of the place (its respawn point).
const TRAVEL_SETTLE_TICKS := 30
const TRAVEL_WAIT_TICKS := 3600
const ARRIVAL_SLACK_M := 30.0

## P39f: the run's travel (--walk-travel), kept across the reload it makes: {} until it is asked for, then
## {"to", "from", "level", "requested_tick", "waited_ticks", "refusals", "last_refusal"} and, once the walk
## starts on the level it arrived in, "arrived_tick", "arrived_at" ([x, z]) and "arrival_m" (from the place).
static var travel_run := {}

var done := false
var player: GiantPlayer = null
var world: WorldRoot = null
var probe: PerfProbe = null
## The waypoints (world positions; y from the ground when loaded).
var route := PackedVector3Array()
## > 0: carried at this speed (m/s); 0: walked with the stick.
var speed_mps := 0.0
var stage := 0
var laps := 1
var ticks := 0
var walked_m := 0.0
var min_margin_m := INF
var max_loaded := 0
var under_terrain_ticks := 0
var worst_sink_m := 0.0
var stuck_teleports := 0
var seam_crossings := 0
var chunks_visited := {}
var region_changes: Array = []
var finished_route := false
## NO_ROUTE when the walk had no route to follow ("" otherwise).
var usage_error := ""
## M8 gate (F21): "stage N not reached (...)" when the giant could not be grown to --walk-stage ("" otherwise).
var stage_error := ""
## How long the growth may wait (STAGE_WAIT_TICKS; tests shorten it).
var stage_wait_ticks := STAGE_WAIT_TICKS
## P39f: the --walk-travel checkpoint ("" = none) and why its travel failed ("" otherwise).
var travel_to := ""
var travel_error := ""
## How long a held-back travel may wait (TRAVEL_WAIT_TICKS; tests shorten it).
var travel_wait_ticks := TRAVEL_WAIT_TICKS
## The place's respawn point on the level the walk starts on (INF while unknown: no travel, or before it).
var travel_place := Vector3.INF

var _state := "wait_ring"
var _state_ticks := 0
var _wp := 0
var _lap := 0
var _last_pos := Vector3.INF
var _last_chunk := ""
var _best := INF
var _since := 0
var _carry_s := 0.0
var _seg_lengths := PackedFloat32Array()
var _travel_refusals := 0
var _last_refusal := ""


## The walk's options from the user args: {"route": PackedVector3Array (empty = the level's),
## "speed": float, "stage": int, "laps": int, "travel": String ("" = no fast travel first)}.
static func parse_options(args: PackedStringArray) -> Dictionary:
	var out := {"route": PackedVector3Array(), "speed": 0.0, "stage": 0, "laps": 1, "travel": ""}
	for arg in args:
		if arg.begins_with("--route="):
			out.route = parse_route(arg.substr(8))
		elif arg.begins_with("--walk-speed="):
			out.speed = maxf(0.0, float(arg.substr(13)))
		elif arg.begins_with("--walk-stage="):
			out.stage = clampi(int(arg.substr(13)), 0, 10)
		elif arg.begins_with("--walk-laps="):
			out.laps = maxi(1, int(arg.substr(12)))
		elif arg.begins_with("--walk-travel="):
			out.travel = arg.substr(14).strip_edges()
	return out


## Forgets the run's travel (tests; a process runs one walk).
static func reset_run() -> void:
	travel_run = {}


## "x:z;x:z;..." -> waypoints (y 0 until the ground is known). Malformed pairs are skipped.
static func parse_route(text: String) -> PackedVector3Array:
	var out := PackedVector3Array()
	for pair in text.split(";", false):
		var xz := pair.split(":")
		if xz.size() == 2 and xz[0].strip_edges().is_valid_float() and xz[1].strip_edges().is_valid_float():
			out.append(Vector3(float(xz[0]), 0.0, float(xz[1])))
	return out


## The level's own route: Markers/Route children in order ([] when it has none).
static func level_route(lv: Node) -> PackedVector3Array:
	var out := PackedVector3Array()
	var r := lv.get_node_or_null("Markers/Route") if lv != null else null
	if r == null:
		return out
	for c in r.get_children():
		if c is Node3D:
			out.append((c as Node3D).global_position)
	return out


## The distance (on the ground plane) from `pos` to the nearest chunk of the grid that is not
## loaded; INF when every chunk is.
static func margin_to_unloaded(s: ChunkStreamer, pos: Vector3) -> float:
	var best := INF
	for z in s.grid.y:
		for x in s.grid.x:
			var id := ChunkData.id_for(Vector2i(x, z))
			if s.is_loaded(id):
				continue
			var x0 := s.origin.x + x * s.chunk_size
			var z0 := s.origin.z + z * s.chunk_size
			var q := Vector2(clampf(pos.x, x0, x0 + s.chunk_size), clampf(pos.z, z0, z0 + s.chunk_size))
			best = minf(best, q.distance_to(Vector2(pos.x, pos.z)))
	return best


func start(p: GiantPlayer, w: WorldRoot, perf: PerfProbe, opts: Dictionary) -> void:
	player = p
	world = w
	probe = perf
	route = opts.get("route", PackedVector3Array())
	if route.is_empty():
		route = level_route(w)
	speed_mps = float(opts.get("speed", 0.0))
	stage = int(opts.get("stage", 0))
	laps = maxi(1, int(opts.get("laps", 1)))
	travel_to = str(opts.get("travel", ""))
	p.router.use_injection = true
	_keep_invulnerable()
	if not Events.region_changed.is_connected(_on_region_changed):
		Events.region_changed.connect(_on_region_changed)
	usage_error = NO_ROUTE if route.size() < 2 else ""
	# P39f: --walk-travel - the travel first (the level the run starts in), or the walk from where it arrived.
	var travel := "none"
	if travel_to != "" and usage_error == "":
		if travel_run.is_empty() or str(travel_run.get("to", "")) != travel_to:
			travel = "pending"
		else:
			travel = "arrived"
			_arrive()
	_seg_lengths = PackedFloat32Array()
	for i in route.size() - 1:
		_seg_lengths.append(Vector2(route[i + 1].x - route[i].x, route[i + 1].z - route[i].z).length())
	if usage_error != "":
		_state = "done"
	elif travel == "pending":
		_state = "travel"
	else:
		_state = "wait_ring"
	_print_level(travel)


## P39f: the walk starts on the level the travel arrived in - from where the travel put the giant (the
## route's first leg is arrival -> its first point), the arrival noted in travel_run.
func _arrive() -> void:
	var at := player.global_position
	route.insert(0, Vector3(at.x, 0.0, at.z))
	travel_place = GameSession.respawn_transform(travel_to).origin
	var arrival_m := Vector2(at.x - travel_place.x, at.z - travel_place.z).length() if travel_place.is_finite() else INF
	travel_run["arrived_tick"] = Sim.tick
	travel_run["arrived_at"] = [snappedf(at.x, 0.1), snappedf(at.z, 0.1)]
	travel_run["arrival_m"] = snappedf(arrival_m, 0.1) if arrival_m != INF else -1.0
	travel_run["respawn"] = GameSession.respawn_id


## P39f: one line when a walk starts on a level (tools/web/world_check.mjs times the Continue's and the
## travel's loads by it): the level, the respawn, how the level was entered (GameSession.entered_log's
## last reason, when it has one), the giant's stage and place, and the travel ("none", "pending", "arrived").
func _print_level(travel: String) -> void:
	var entered: Dictionary = GameSession.entered_log.back() if not GameSession.entered_log.is_empty() else {}
	var at := player.global_position
	print("WORLD_WALK_LEVEL %s" % JSON.stringify({"level": GameSession.current_level_id(), "respawn": GameSession.respawn_id,
		"entered": str(entered.get("reason", "")), "stage": player.current_growth_stage(),
		"at": [snappedf(at.x, 0.1), snappedf(at.z, 0.1)], "travel": travel, "travel_to": travel_to}))


## P39f: the travel's state - once the level has settled, the travel is asked for the map's way as soon as
## GameSession allows it; a refusal of the place itself (no blocker holds the giant back), or one that
## outlasts travel_wait_ticks, ends the walk with travel_error. The travel's reload then frees this node.
func _travel_step() -> void:
	if _state_ticks < TRAVEL_SETTLE_TICKS:
		return
	if not GameSession.is_campaign():
		travel_error = "fast travel to %s refused: not in the campaign (a Continue or --mode=world)" % travel_to
		_finish()
		return
	var lv := GameSession.current_level_id()
	var why := GameSession.travel_refusal(lv, travel_to, "fast_travel")
	if why == "":
		travel_run = {"to": travel_to, "from": GameSession.respawn_id, "level": lv, "requested_tick": Sim.tick,
			"waited_ticks": _state_ticks, "refusals": _travel_refusals, "last_refusal": _last_refusal}
		print("WORLD_TRAVEL %s" % JSON.stringify(travel_run))
		_set_state("travelling")
		Events.travel_requested.emit(lv, travel_to, "fast_travel")
		var r: Dictionary = GameSession.last_travel_result
		if not bool(r.get("ok", false)):
			travel_error = "fast travel to %s refused: %s" % [travel_to, str(r.get("message", "?"))]
			_finish()
		return
	_travel_refusals += 1
	_last_refusal = why
	if GameSession.travel_blockers("fast_travel").is_empty() or _state_ticks > travel_wait_ticks:
		travel_error = "fast travel to %s refused: %s" % [travel_to, why]
		_finish()


func _on_region_changed(_tick: int, region_id: String, previous_id: String) -> void:
	region_changes.append({"s": snappedf(ticks / float(Sim.TICK_RATE), 0.01), "region": region_id, "previous": previous_id})


func _keep_invulnerable() -> void:
	if player == null or player.entity == null or player.entity.combatant == null:
		return
	var e := player.entity
	if e.is_alive() and (not e.combatant.statuses.has(STATUS_INVULNERABLE)
			or e.combatant.statuses.remaining_s(STATUS_INVULNERABLE, Sim.tick) < 60.0):
		e.apply_status(STATUS_INVULNERABLE, NAN, -1.0, "world_walk")


func _physics_process(_delta: float) -> void:
	if done or player == null or not is_instance_valid(player) or world == null or not is_instance_valid(world):
		return
	_state_ticks += 1
	match _state:
		"done":
			_finish()
			return
		"travel":
			_travel_step()
			return
		"travelling":
			return   # the travel's reload frees this node
		"wait_ring":
			# The giant waits at the route's first point (the start, or where a --route begins: held
			# there until the ring around it is loaded) before it sets off.
			var first := route[0]
			var ground := world.height_at(first)
			var at := player.global_position
			if Vector2(at.x - first.x, at.z - first.z).length() > WAYPOINT_M or not is_nan(ground) and at.y < ground - 1.0:
				GameSession.place_player(player, Transform3D(Basis(Vector3.UP, player.facing_yaw),
					Vector3(first.x, (ground + 0.3) if not is_nan(ground) else at.y, first.z)))
			if world.streamer.ring_ready(first) and not is_nan(ground) or _state_ticks > RING_WAIT_TICKS:
				if stage > 0 and player.current_growth_stage() != stage:
					_set_state("grow")
				else:
					_set_off()
			return
		"grow":
			# M8 gate (F21): grow the giant once it stands on the floor and is free; never walk at another stage.
			if player.current_growth_stage() == stage:
				_set_off()
			elif player.growth == null or _state_ticks > stage_wait_ticks:
				var why := "no growth" if player.growth == null else str(player.growth.last_result.get("reason", "?"))
				stage_error = "stage %d not reached (the giant stays at stage %d: %s)" % [stage, player.current_growth_stage(), why]
				_finish()
			elif _state_ticks % STAGE_RETRY_TICKS == 0 and player.is_on_floor() and player.controller != null \
					and player.controller.state == CombatController.State.LOCOMOTION:
				player.growth.debug_set_stage(stage)
			return
	_keep_invulnerable()
	ticks += 1
	var pos := player.global_position
	if _last_pos.is_finite():
		walked_m += Vector2(pos.x - _last_pos.x, pos.z - _last_pos.z).length()
	_last_pos = pos
	_measure(pos)
	if speed_mps > 0.0:
		_carry(1.0 / float(Sim.TICK_RATE))
	else:
		_walk()


func _set_state(s: String) -> void:
	_state = s
	_state_ticks = 0


## The walk sets off from the route's first point (the ring ready, the giant at its stage).
func _set_off() -> void:
	world.streamer.reset_stats()
	_set_state("walk")
	# The web stream check times the page's frames between these two lines.
	print("WORLD_WALK_START %s" % JSON.stringify({"route_points": route.size(), "speed_mps": speed_mps,
		"stage": player.current_growth_stage()}))


func _measure(pos: Vector3) -> void:
	var s := world.streamer
	min_margin_m = minf(min_margin_m, margin_to_unloaded(s, pos))
	max_loaded = maxi(max_loaded, s.loaded_chunks().size())
	var chunk := s.chunk_at(pos)
	if chunk != "":
		chunks_visited[chunk] = true
		if _last_chunk != "" and chunk != _last_chunk:
			seam_crossings += 1
		_last_chunk = chunk
	if probe != null:
		probe.section = chunk if chunk != "" else "outside"
	if speed_mps <= 0.0 and player.is_on_floor():
		var ground := world.height_at(pos)
		if not is_nan(ground):
			var sink := ground - pos.y
			worst_sink_m = maxf(worst_sink_m, sink)
			if sink > UNDER_TERRAIN_M:
				under_terrain_ticks += 1


## Walking: the stick toward the next waypoint (sprinting), the camera along the segment.
func _walk() -> void:
	var target := route[_wp]
	var pos := player.global_position
	var to := Vector3(target.x - pos.x, 0.0, target.z - pos.z)
	var d := to.length()
	if d < WAYPOINT_M:
		_next_waypoint()
		return
	if d < _best - 0.5:
		_best = d
		_since = 0
	else:
		_since += 1
		if _since > int(STUCK_S * Sim.TICK_RATE):
			var y := world.height_at(target)
			GameSession.place_player(player, Transform3D(Basis(Vector3.UP, player.facing_yaw),
				Vector3(target.x, (y if not is_nan(y) else pos.y) + 0.3, target.z)))
			stuck_teleports += 1
			_next_waypoint()
			return
	var yaw := TargetingRules.yaw_of(to)
	player.camera_rig.yaw = yaw
	player.router.set_injected_move(Vector2(0, 1))
	player.router.set_injected_hold(&"sprint", d > 12.0)


func _next_waypoint() -> void:
	_wp += 1
	_best = INF
	_since = 0
	if _wp >= route.size():
		_lap += 1
		if _lap >= laps:
			finished_route = true
			_finish()
			return
		_wp = 1 if route.size() > 1 else 0


## Carried: the giant is put on the route `speed_mps` further each tick (y from the loaded ground).
func _carry(dt: float) -> void:
	_carry_s += speed_mps * dt
	var total := 0.0
	for l in _seg_lengths:
		total += l
	if total <= 0.0:
		finished_route = true
		_finish()
		return
	if _carry_s >= total * laps:
		finished_route = true
		_finish()
		return
	var s := fmod(_carry_s, total)
	var i := 0
	while i < _seg_lengths.size() - 1 and s > _seg_lengths[i]:
		s -= _seg_lengths[i]
		i += 1
	var a := route[i]
	var b := route[i + 1]
	var t := clampf(s / maxf(_seg_lengths[i], 0.001), 0.0, 1.0)
	var p := Vector3(lerpf(a.x, b.x, t), 0.0, lerpf(a.z, b.z, t))
	var y := world.height_at(p)
	p.y = (y if not is_nan(y) else player.global_position.y) + 0.2
	var yaw := TargetingRules.yaw_of(Vector3(b.x - a.x, 0.0, b.z - a.z))
	GameSession.place_player(player, Transform3D(Basis(Vector3.UP, yaw), p))
	player.router.set_injected_move(Vector2.ZERO)


func _finish() -> void:
	if done:
		return
	done = true
	var end := {"finished": finished_route, "ticks": ticks}
	if usage_error != "":
		end["usage_error"] = usage_error
	if stage_error != "":
		end["stage_error"] = stage_error
	if travel_error != "":
		end["travel_error"] = travel_error
	print("WORLD_WALK_END %s" % JSON.stringify(end))
	if player != null and is_instance_valid(player):
		player.router.set_injected_move(Vector2.ZERO)
		player.router.set_injected_hold(&"sprint", false)
	if probe != null:
		probe.context["world_walk"] = summary()


## The headline numbers (also the probe's context).
func summary() -> Dictionary:
	var st := world.streamer.stats() if world != null and is_instance_valid(world) else {}
	return {"mode": "carry" if speed_mps > 0.0 else "walk", "speed_mps": speed_mps, "metres": snappedf(walked_m, 0.1),
		"seconds": snappedf(ticks / float(Sim.TICK_RATE), 0.01),
		"min_margin_m": snappedf(min_margin_m, 0.1) if min_margin_m != INF else -1.0,
		"max_loaded": max_loaded, "loads": int(st.get("loads", 0)), "unloads": int(st.get("unloads", 0)),
		"thrash": int(st.get("thrash", 0)), "work_ms_p50": st.get("work_ms_p50", 0.0),
		"work_ms_p99": st.get("work_ms_p99", 0.0), "work_ms_max": st.get("work_ms_max", 0.0),
		"work_over_budget": int(st.get("over_budget", 0)),
		"stage": player.current_growth_stage() if player != null and is_instance_valid(player) else 0}


## The walk's report: the summary, the streamer's statistics, the chunks and regions passed, the
## seams crossed, the ticks under the terrain and the check failures.
func result() -> Dictionary:
	var out := summary()
	out["streaming"] = world.streamer.stats() if world != null and is_instance_valid(world) else {}
	out["route_points"] = route.size()
	out["laps"] = laps
	out["finished"] = finished_route
	var visited := PackedStringArray(chunks_visited.keys())
	visited.sort()
	out["chunks_visited"] = visited
	out["seam_crossings"] = seam_crossings
	out["region_changes"] = region_changes
	out["under_terrain_ticks"] = under_terrain_ticks
	out["worst_sink_m"] = snappedf(worst_sink_m, 0.001)
	out["stuck_teleports"] = stuck_teleports
	out["usage_error"] = usage_error
	out["stage_error"] = stage_error
	# P39f: the fast travel before the walk (--walk-travel): the run's travel_run, and why it failed
	out["travel_to"] = travel_to
	out["travel"] = travel_run.duplicate() if travel_to != "" else {}
	out["travel_error"] = travel_error
	if usage_error != "":
		out["check_failures"] = PackedStringArray([usage_error])
		return out
	if stage_error != "":
		out["check_failures"] = PackedStringArray([stage_error])   # (nothing was walked)
		return out
	if travel_error != "":
		out["check_failures"] = PackedStringArray([travel_error])   # (nothing was walked)
		return out
	var failures := PackedStringArray()
	if travel_to != "":
		var arrival := float(travel_run.get("arrival_m", -1.0)) if travel_run.has("arrived_tick") else -1.0
		if not travel_run.has("arrived_tick"):
			failures.append("the fast travel to %s never arrived" % travel_to)
		elif arrival < 0.0:
			failures.append("the fast travel to %s arrived on a level that does not know the place" % travel_to)
		elif arrival > ARRIVAL_SLACK_M:
			failures.append("the fast travel to %s put the giant %.1f m from it (at most %.0f m)" % [travel_to, arrival, ARRIVAL_SLACK_M])
	if not finished_route:
		failures.append("the route was not finished (waypoint %d of %d, lap %d of %d)" % [_wp + 1, route.size(), _lap + 1, laps])
	if min_margin_m < MARGIN_REQUIRED_M:
		failures.append("the giant came %.1f m from unloaded ground (at least %.0f m)" % [min_margin_m, MARGIN_REQUIRED_M])
	if int(out.thrash) > 0:
		failures.append("%d chunk(s) reloaded within %.0f s of their unload (thrash)" % [out.thrash, ChunkStreamer.THRASH_WINDOW_S])
	if max_loaded > MAX_LOADED:
		failures.append("%d chunks loaded at once (at most %d)" % [max_loaded, MAX_LOADED])
	if under_terrain_ticks > 0:
		failures.append("%d tick(s) with the feet more than %.2f m under the ground (worst %.2f m)" % [under_terrain_ticks,
			UNDER_TERRAIN_M, worst_sink_m])
	out["check_failures"] = failures
	return out
