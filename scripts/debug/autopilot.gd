class_name Autopilot
extends Node
## Seeded bot for soak runs and a scripted screenshot tour.
##
## It drives the player only through the InputRouter injection API (the same intent path as
## a keyboard) and by turning the camera like a mouse would - never by editing combat state.
## State lives in static variables so a run survives sandbox resets (scene reloads).
## Prints one "AUTOPILOT_RESULT {json}" line, then quits.
##
## Every tool run (--autoplay, --scenario) installs an ErrorCounter: the result carries
## "errors", "warnings" and "error_samples" (the first five), and the process exits with code
## EXIT_ERRORS when any engine or script error was logged during the run (0 otherwise).
##
## P14 scenarios (each in its own file; the Autopilot only dispatches, times and reports them):
##   --scenario=stress       the stress route (StressScenario in scenes/test/stress_arena.tscn; run
##                           with --level=res://scenes/test/stress_arena.tscn): the bot loops the
##                           route for --autoplay seconds. --stress-stage=N grows the giant to N
##                           first (default 2).
##   --scenario=valley_walk  the Valley walk (ValleyWalk; run with --mode=valley --new-game): first
##                           the AI LOD tier comparison (tiers 2, 1, 0) from the Cradle, then every
##                           district at stage 1; the run ends when the walk does (--autoplay stays
##                           the hard limit).
##                           --walk-teleport skips the walking (stops and views only; for slow
##                           software-rendered draw-call captures).
## Both add a PerfProbe (as does --perf for any other run): "PERF_RESULT {json}" is printed before
## AUTOPILOT_RESULT, whose "perf" key repeats the CPU-per-tick summary and the budget verdicts.
## A scenario's own checks go to "scenario_failures"; any failure exits with EXIT_SCENARIO_FAILED
## (errors still win: EXIT_ERRORS).
##
## P17a: --scenario=valley  the Valley bot (ValleyBot; run with --mode=valley --new-game): it plays
##                          the quest line until the slice is complete (or, with --bot-loop, until
##                          --autoplay ends, starting a new game with the next village policy after
##                          each completion). Options: --bot-village=help_cache|help_ogre|intimidate|
##                          force, --bot-skill=novice|expert, --bot-assist, --bot-loop, --bot-seed=N.
##                          It adds a PerfProbe; AUTOPILOT_RESULT's "valley_bot" key holds the run's
##                          metrics (plan §5.1). Exit codes: EXIT_SCENARIO_FAILED (2) on a watchdog
##                          breach (a loop run: only on a world_blocked one), EXIT_INVARIANT (3) on an
##                          invariant failure; errors still win (EXIT_ERRORS). The Autopilot runs
##                          PROCESS_MODE_ALWAYS for it (the bot closes pausing screens itself), and
##                          --autoplay counts simulated (unpaused) seconds as everywhere else.
##
## P38: --scenario=world  the world bot (WorldBot; run with --mode=world --new-game, or --continue from a
##                          bot's save): it plays quest.world_main from world_start to the Stone Throne
##                          under an oath policy (--bot-preset=peaceful|conqueror|mixed, --bot-oaths=
##                          march:help,wood:drive,..., --bot-oath-count=2|3, --bot-champion=, --bot-corvane=,
##                          --bot-explore=) with the Valley bot's skill, assist, seed, loop and trace options.
##                          --scenario=valley --bot-campaign plays the Valley first and hands over at
##                          slice.completed. AUTOPILOT_RESULT's "world_bot" key holds the run (the Valley
##                          bot's metrics, the world's, the outcomes); exit codes as for --scenario=valley
##                          (a single run fails on a breach or an unfinished campaign, a loop only on a
##                          world_blocked breach; invariants 3; errors 1).
##
## P24a: --scenario=world_walk  the streaming walk (WorldWalk) on a streamed world (WorldRoot: the
##                          test world with --level=res://scenes/test/test_world.tscn; the real world
##                          from P25 with --mode=world --new-game): the giant follows --route= (default
##                          the level's Markers/Route), walking or carried at --walk-speed=M, grown
##                          to --walk-stage=N, --walk-laps=N times; the run ends with the walk. It adds
##                          a PerfProbe (sections: the chunk the giant is in); AUTOPILOT_RESULT's
##                          "world_walk" key holds the walk's report and its check failures.

const EXIT_OK := 0
const EXIT_ERRORS := 1
## P14: a scenario's own check failed (stress, valley_walk); P17a: a Valley bot watchdog breach.
const EXIT_SCENARIO_FAILED := 2
## P17a: a Valley bot invariant failed (plan §5.2).
const EXIT_INVARIANT := 3
const RESULT_SAMPLES := 5
## The scenarios dispatched to their own files (P14).
const SCENARIO_STRESS := "stress"
const SCENARIO_VALLEY_WALK := "valley_walk"
## P17a: the Valley bot.
const SCENARIO_VALLEY := "valley"
## P24a: the streaming walk.
const SCENARIO_WORLD_WALK := "world_walk"
## P38: the world bot.
const SCENARIO_WORLD := "world"
const WORLD_NEEDED := "--scenario=world needs the campaign: add --mode=world --new-game (or --continue)"
const WORLD_WALK_NEEDED := "--scenario=world_walk needs a streamed world: add --level=res://scenes/test/test_world.tscn"
const VALLEY_NEEDED := "--scenario=valley needs the Valley: add --mode=valley --new-game"
const STRESS_ARENA := "res://scenes/test/stress_arena.tscn"
const VALLEY_LEVEL_ID := "level.valley"
## Soak target order (pick_soak_target, M2 gate): enemies the giant is already fighting (within
## ENGAGE_RADIUS_M of it) or that guard the M1 arena (within ARENA_RADIUS_M of its centre: the
## soldier's patrol) come first, then an intact breakable (the fence: the breakable, debris and
## loot path of the M1 soak), then any other living enemy (the P04 wolf pack in the far corner),
## then a dummy. Without it the bot crossed to the wolves as soon as the soldier died, and the
## fence was never broken again.
const ENGAGE_RADIUS_M := 10.0
const ARENA_RADIUS_M := 40.0

static var _started := false
static var _elapsed := 0.0
static var _duration := 0.0
static var _scenario := ""
static var _capture_dir := ""
static var _stats: Dictionary = {}
static var _frame_ms: Array[float] = []
static var _step := 0
static var _rng := RandomNumberGenerator.new()
static var _error_counter: ErrorCounter = null
static var _finished := false
## Options of the P14 scenarios and the probe (parse_options()).
static var _options: Dictionary = {}
## P17a: the Valley bot run's PerfProbe (under the tree root: it outlives level loads).
static var _valley_probe: PerfProbe = null

var player: GiantPlayer
var _decision_left := 0.0
var _block_left := 0.0
var _heavy_pending := false
var _dead_time := 0.0
var _no_enemy_time := 0.0
var _step_time := 0.0
var _busy := false
var _stuck_time := 0.0
var _strafe_left := 0.0
var _strafe_sign := 1.0
var _shots: Array[String] = []
var _probe: PerfProbe = null
var _stress: StressScenario = null
var _walk: ValleyWalk = null
var _bot: ValleyBot = null
var _world_walk: WorldWalk = null
var _scenario_failures := PackedStringArray()


func configure(seconds: float, scenario: String, capture_dir: String) -> void:
	if _started:
		return
	_started = true
	_duration = seconds
	_scenario = scenario
	_capture_dir = capture_dir if capture_dir != "" else "user://captures"
	_rng.seed = 424242
	_stats = {"ticks": 0, "attacks": 0, "heavies": 0, "dodges": 0, "blocks": 0, "footfalls": 0,
		"jumps": 0, "resets": 0, "player_deaths": 0, "soldier_kills": 0, "camera_toggles": 0,
		"lock_presses": 0, "fence_breaks": 0, "hits_resolved": 0, "parries": 0,
		"max_debris": 0, "rejections": 0, "enemy_kills": 0, "loot_awards": 0}
	_options = parse_options(OS.get_cmdline_user_args())
	# Count every engine/script error of the run (the logger lives as long as the process).
	_error_counter = ErrorCounter.new()
	OS.add_logger(_error_counter)
	if is_world_bot_run(_scenario, OS.get_cmdline_user_args()):
		WorldBot.configure_world(OS.get_cmdline_user_args())   # P38
	elif _scenario == SCENARIO_VALLEY:
		ValleyBot.configure(ValleyBot.parse_options(OS.get_cmdline_user_args()))


## The P14 options of the user args: {"perf": bool (--perf), "stress_stage": int
## (--stress-stage=N, default StressScenario.DEFAULT_STAGE), "walk_teleport": bool
## (--walk-teleport)}.
static func parse_options(args: PackedStringArray) -> Dictionary:
	var out := {"perf": false, "stress_stage": StressScenario.DEFAULT_STAGE, "walk_teleport": false}
	for arg in args:
		if arg == "--perf":
			out.perf = true
		elif arg.begins_with("--stress-stage="):
			out.stress_stage = clampi(int(arg.substr(15)), 1, 3)
		elif arg == "--walk-teleport":
			out.walk_teleport = true
	return out


## True for the scenarios that run their own driver and a PerfProbe.
static func is_perf_scenario(scenario: String) -> bool:
	return scenario == SCENARIO_STRESS or scenario == SCENARIO_VALLEY_WALK or scenario == SCENARIO_VALLEY \
		or scenario == SCENARIO_WORLD_WALK or scenario == SCENARIO_WORLD


## P38: true for a world bot run: --scenario=world, or --scenario=valley with --bot-campaign.
static func is_world_bot_run(scenario: String, args: PackedStringArray) -> bool:
	return scenario == SCENARIO_WORLD or (scenario == SCENARIO_VALLEY and args.has("--bot-campaign"))


## P38: the bot scenarios (the Valley bot and the world bot): PROCESS_MODE_ALWAYS, one probe per run.
static func is_bot_scenario(scenario: String) -> bool:
	return scenario == SCENARIO_VALLEY or scenario == SCENARIO_WORLD


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS if _scenario in ["capture", SCENARIO_VALLEY, SCENARIO_WORLD] else Node.PROCESS_MODE_PAUSABLE
	# Method callables (not lambdas): they disconnect automatically when this node is freed
	# by a sandbox reset, so counts are never duplicated.
	Events.hit_resolved.connect(_on_hit_resolved)
	Events.entity_died.connect(_on_entity_died)
	Events.object_destroyed.connect(_on_object_destroyed)
	Events.action_rejected.connect(_on_action_rejected)
	Events.loot_awarded.connect(_on_loot_awarded)
	if is_perf_scenario(_scenario) or bool(_options.get("perf", false)):
		if is_bot_scenario(_scenario) and is_instance_valid(_valley_probe):
			_probe = _valley_probe   # P17a: one probe for the whole bot run, across level loads
		else:
			_probe = PerfProbe.new()
			_probe.name = "PerfProbe"
			_probe.label = _scenario if _scenario != "" else "soak"
			if is_bot_scenario(_scenario):
				# A death, a checkpoint load or a loop's new game replaces this node with the level;
				# the probe stays (under the root) so PERF_RESULT covers the whole run.
				_valley_probe = _probe
				get_tree().root.add_child.call_deferred(_probe)
			else:
				add_child(_probe)


func _on_hit_resolved(_t: int, r: HitResult) -> void:
	_stats.hits_resolved += 1
	if r.outcome == HitResult.Outcome.PARRIED:
		_stats.parries += 1


func _on_entity_died(_t: int, id: String, _k: String) -> void:
	if id.begins_with("soldier"):
		_stats.soldier_kills += 1
	var e := Sim.get_entity(id)
	if e != null and e.actor != null and e.actor.is_in_group("enemies"):
		_stats.enemy_kills += 1


func _on_object_destroyed(_t: int, _id: String, _by: String) -> void:
	_stats.fence_breaks += 1


func _on_action_rejected(_t: int, _a: String, _id: String, _r: String) -> void:
	_stats.rejections += 1


func _on_loot_awarded(_t: int, _world_id: String, _item: String, _count: int, _recipient: String) -> void:
	_stats.loot_awards += 1


func _process(delta: float) -> void:
	if level_loading():
		return
	if _frame_ms.size() < 200000:
		_frame_ms.append(delta * 1000.0)


## True while main's loading gate holds the tree paused behind "Loading..." (main.gd is_loading();
## false where no main is the parent). The autopilot does nothing meanwhile (M6 gate): the gate holds
## for extra frames with audio on, and the Valley bot, started and bound in those paused frames (the
## autopilot and the bot run PROCESS_MODE_ALWAYS), acted one tick earlier than in a silent run, so
## every seeded Valley run diverged from its --no-audio twin. Now the bot starts on the first tick
## after the gate in both, as the pausable soak always did.
func level_loading() -> bool:
	var main := get_parent()
	return main != null and main.has_method("is_loading") and bool(main.call("is_loading"))


func _physics_process(dt: float) -> void:
	if level_loading():
		return
	if is_bot_scenario(_scenario):
		if _bot == null:
			_start_valley_bot()
		# The run may end while a pausing screen is up (the end screen after the crown).
		if ValleyBot.run != null and ValleyBot.run.finished:
			_finish()
			return
	if get_tree().paused and _scenario != "capture":
		return
	_elapsed += dt
	_stats.ticks += 1
	if _duration > 0.0 and _elapsed >= _duration:
		_finish()
		return
	if is_bot_scenario(_scenario):
		return
	if player == null or not is_instance_valid(player):
		player = get_tree().get_first_node_in_group("player") as GiantPlayer
		if player == null:
			return
	player.router.use_injection = true
	var pool := get_tree().get_first_node_in_group("debris_pool") as DebrisPool
	if pool != null:
		_stats.max_debris = maxi(_stats.max_debris, pool.active_count())
	if _scenario == "capture":
		if not _busy:
			_run_capture(dt)
		return
	if _scenario == SCENARIO_STRESS:
		_run_stress()
		return
	if _scenario == SCENARIO_VALLEY_WALK:
		_run_valley_walk()
		return
	if _scenario == SCENARIO_WORLD_WALK:
		_run_world_walk()
		return
	_run_soak(dt)


# --------------------------------------------------------------------------- P17a: the Valley bot

## --scenario=valley: one ValleyBot per level (its run lives in ValleyBot.run, a static, so deaths,
## checkpoint loads and new games keep it); it needs the Valley (or a level with a LevelRoot).
func _start_valley_bot() -> void:
	if not is_inside_tree():
		return
	var lv := get_tree().get_first_node_in_group(LevelRoot.GROUP) as LevelRoot
	var needed := WORLD_NEEDED if _scenario == SCENARIO_WORLD else VALLEY_NEEDED
	if lv == null:
		if _stats.ticks > 120 and not _scenario_failures.has(needed):
			_scenario_failures.append(needed)
			_finish()
		return
	# P38: the world bot (its run carries the world's state) or the Valley bot
	if ValleyBot.run != null and ValleyBot.run.world != null:
		_bot = WorldBot.new()
		_bot.name = "WorldBot"
	else:
		_bot = ValleyBot.new()
		_bot.name = "ValleyBot"
	add_child(_bot)


# --------------------------------------------------------------------------- P14 scenarios

## --scenario=stress: starts the arena's StressScenario bot once; it drives the player itself.
func _run_stress() -> void:
	if _stress != null:
		return
	_stress = get_tree().get_first_node_in_group(StressScenario.GROUP) as StressScenario
	if _stress == null:
		_scenario_failures.append("--scenario=stress needs the stress arena: add --level=%s" % STRESS_ARENA)
		_finish()
		return
	_stress.start_bot(player, int(_options.get("stress_stage", StressScenario.DEFAULT_STAGE)))


## --scenario=valley_walk: starts a ValleyWalk once; the run ends when the walk is done.
func _run_valley_walk() -> void:
	if _walk == null:
		var lv := get_tree().get_first_node_in_group(LevelRoot.GROUP) as LevelRoot
		if lv == null or lv.level_id != VALLEY_LEVEL_ID:
			_scenario_failures.append("--scenario=valley_walk needs the Valley: add --mode=valley --new-game")
			_finish()
			return
		_walk = ValleyWalk.new()
		_walk.name = "ValleyWalk"
		_walk.teleport_only = bool(_options.get("walk_teleport", false))
		add_child(_walk)
		_walk.start(player, lv, _probe)
	if _walk.done:
		_finish()


## --scenario=world_walk (P24a): starts a WorldWalk once on the streamed world; the run ends with it.
func _run_world_walk() -> void:
	if _world_walk == null:
		var w := get_tree().get_first_node_in_group(WorldRoot.WORLD_GROUP) as WorldRoot
		if w == null:
			_scenario_failures.append(WORLD_WALK_NEEDED)
			_finish()
			return
		_world_walk = WorldWalk.new()
		_world_walk.name = "WorldWalk"
		add_child(_world_walk)
		_world_walk.start(player, w, _probe, WorldWalk.parse_options(OS.get_cmdline_user_args()))
	if _world_walk.done:
		_finish()


# --------------------------------------------------------------------------- soak

## Every living enemy of any archetype (duck typed: an "enemies" node with a CombatEntity).
func _alive_enemies() -> Array[Node3D]:
	var out: Array[Node3D] = []
	for n in get_tree().get_nodes_in_group("enemies"):
		var e: Variant = n.get("entity")
		if n is Node3D and e is CombatEntity and (e as CombatEntity).is_alive():
			out.append(n)
	return out


## The first breakable that is still intact, or null.
func _intact_breakable() -> Node3D:
	for n in get_tree().get_nodes_in_group("breakables"):
		if n is BreakableProp and not (n as BreakableProp).destroyed:
			return n
	return null


## The arena's centre: the sandbox root's position (the world origin without one).
func _arena_centre() -> Vector3:
	var arena := get_tree().get_first_node_in_group("sandbox") as Node3D
	return arena.global_position if arena != null else Vector3.ZERO


## The soak's target (order: see ENGAGE_RADIUS_M): the nearest living enemy within
## ENGAGE_RADIUS_M of the giant or ARENA_RADIUS_M of the arena centre, else the intact
## breakable, else the nearest other living enemy, else the dummy (null when there is none).
## `enemies` holds living enemies only; distances are measured on the ground plane.
static func pick_soak_target(giant_pos: Vector3, centre: Vector3, enemies: Array, breakable: Node3D,
		dummy: Node3D) -> Node3D:
	var near: Node3D = null
	var far: Node3D = null
	var near_d := INF
	var far_d := INF
	for n: Node3D in enemies:
		var d := _flat_distance(giant_pos, n.global_position)
		if d <= ENGAGE_RADIUS_M or _flat_distance(centre, n.global_position) <= ARENA_RADIUS_M:
			if d < near_d:
				near = n
				near_d = d
		elif d < far_d:
			far = n
			far_d = d
	if near != null:
		return near
	if breakable != null:
		return breakable
	if far != null:
		return far
	return dummy


static func _flat_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


func _face(point: Vector3, dt: float, rate := 6.0) -> float:
	var to := point - player.global_position
	to.y = 0.0
	if to.length_squared() > 0.01:
		var want := TargetingRules.yaw_of(to)
		player.camera_rig.yaw = lerp_angle(player.camera_rig.yaw, want, 1.0 - exp(-rate * dt))
	return to.length()


func _run_soak(dt: float) -> void:
	var r := player.router
	if player.controller.state == CombatController.State.DEAD:
		_dead_time += dt
		if _dead_time > 1.5:
			_dead_time = -1000.0
			_stats.player_deaths += 1
			_stats.resets += 1
			Events.sandbox_reset_requested.emit("autopilot_after_death")
		return
	var enemies := _alive_enemies()
	if enemies.is_empty():
		_no_enemy_time += dt
		if _no_enemy_time > 12.0:
			_no_enemy_time = -1000.0
			_stats.resets += 1
			Events.sandbox_reset_requested.emit("autopilot_respawn_soldier")
			return
	var target := pick_soak_target(player.global_position, _arena_centre(), enemies,
		_intact_breakable(), get_tree().get_first_node_in_group("dummies") as Node3D)
	if target == null:
		return
	var dist := _face(target.global_position, dt)
	var move := Vector2.ZERO
	if dist > 3.2:
		move = Vector2(0, 1)
		r.set_injected_hold(&"sprint", dist > 14.0)
		# Simple unsticking: walking into a dummy/pillar/wall -> sidestep for a moment.
		var speed := Vector2(player.velocity.x, player.velocity.z).length()
		_stuck_time = _stuck_time + dt if speed < 0.5 and player.controller.state == CombatController.State.LOCOMOTION else 0.0
		if _stuck_time > 0.5:
			_stuck_time = 0.0
			_strafe_left = 1.2
			_strafe_sign = 1.0 if _rng.randf() < 0.5 else -1.0
	else:
		r.set_injected_hold(&"sprint", false)
		move = Vector2(sin(_elapsed * 0.7) * 0.4, 0.0)
	if _strafe_left > 0.0:
		_strafe_left -= dt
		move = Vector2(_strafe_sign, 0.3)
	r.set_injected_move(move)
	if _block_left > 0.0:
		_block_left -= dt
		if _block_left <= 0.0:
			r.set_injected_hold(&"block", false)
			r.inject_edge(&"block_release")
	if _heavy_pending:
		_heavy_pending = false
		r.set_injected_hold(&"heavy_modifier", false)
	_decision_left -= dt
	if _decision_left > 0.0 or dist > 6.0:
		return
	_decision_left = _rng.randf_range(0.25, 0.8)
	var roll := _rng.randf()
	if roll < 0.42:
		r.inject_light_attack()
		_stats.attacks += 1
	elif roll < 0.54:
		r.set_injected_hold(&"heavy_modifier", true)
		r.inject_light_attack()   # Shift + light = one heavy
		_heavy_pending = true
		_stats.heavies += 1
	elif roll < 0.66:
		r.set_injected_hold(&"block", true)
		r.inject_edge(&"block_press")
		_block_left = _rng.randf_range(0.15, 0.9)
		_stats.blocks += 1
	elif roll < 0.76:
		r.set_injected_move(Vector2(_rng.randf_range(-1, 1), _rng.randf_range(-1, 1)))
		r.inject_edge(&"dodge")
		_stats.dodges += 1
	elif roll < 0.83:
		r.inject_edge(&"slot_1")
		_stats.footfalls += 1
	elif roll < 0.86:
		r.inject_edge(&"jump")
		_stats.jumps += 1
	elif roll < 0.92:
		r.inject_edge(&"lock_press")
		_stats.lock_presses += 1
	elif roll < 0.95:
		r.inject_edge(&"camera_toggle")
		_stats.camera_toggles += 1
	else:
		r.inject_edge(&"target_right")


func _finish() -> void:
	if _finished:
		return
	_finished = true
	var counted := {}
	if _error_counter != null:
		counted = _error_counter.take()
		OS.remove_logger(_error_counter)
		_error_counter = null
	var result := build_result(_stats, _elapsed, _frame_ms, _shots, counted)
	var failures := _scenario_failures.duplicate()
	if _stress != null:
		_stress.stop_bot()
		var sr := _stress.result(_elapsed)
		failures.append_array(sr.check_failures)
		result["stress"] = sr
	if _walk != null:
		var wr := _walk.result()
		failures.append_array(wr.check_failures)
		result["valley_walk"] = wr
	if _world_walk != null:
		var ww := _world_walk.result()
		failures.append_array(ww.check_failures)
		result["world_walk"] = ww
	if is_bot_scenario(_scenario) and ValleyBot.run != null:
		if ValleyBot.run.world != null:
			# P38: the world bot's run (the campaign's, or the world's alone)
			var wb := WorldBot.result(Sim.tick)
			result["world_bot"] = wb
			failures.append_array(world_failures(wb))
			result["invariants_ok"] = (wb.get("invariant_failures", []) as Array).is_empty()
		else:
			var vb := ValleyBot.result(Sim.tick)
			result["valley_bot"] = vb
			failures.append_array(valley_failures(vb))
			result["invariants_ok"] = (vb.get("invariant_failures", []) as Array).is_empty()
	if is_perf_scenario(_scenario):
		result["scenario"] = _scenario
		result["scenario_failures"] = failures
		result["scenario_ok"] = failures.is_empty()
	if _probe != null:
		_probe.finish()
		var perf := _probe.result()
		print("PERF_RESULT " + JSON.stringify(perf))
		result["perf"] = {"cpu_tick_ms": perf.cpu_tick_ms, "sim_ms": perf.sim_ms, "budgets": perf.budgets,
			"quality": perf.quality}
	print("AUTOPILOT_RESULT " + JSON.stringify(result))
	write_result_file(result_file_arg(OS.get_cmdline_user_args()), result)
	get_tree().quit(exit_code(result))


## P17a: --result-file=<path> (user:// or absolute): where the run also writes its result as JSON
## (tools/run_bots.sh). "" when not given.
static func result_file_arg(args: PackedStringArray) -> String:
	for arg in args:
		if arg.begins_with("--result-file="):
			return arg.substr(14).strip_edges()
	return ""


## Writes `result` as JSON to `path` (folders made); nothing for "". False when it cannot.
static func write_result_file(path: String, result: Dictionary) -> bool:
	if path == "":
		return false
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_warning("Autopilot: cannot write %s" % path)
		return false
	f.store_string(JSON.stringify(result, "\t"))
	f.close()
	return true


## The AUTOPILOT_RESULT dictionary: the run's stats, timing, shots and the error counts
## (`counted` is an ErrorCounter.take() result; {} counts as no errors).
static func build_result(stats: Dictionary, elapsed: float, frame_ms: Array, shots: Array,
		counted: Dictionary) -> Dictionary:
	var sorted := frame_ms.duplicate()
	sorted.sort()
	var result := stats.duplicate()
	result["simulated_s"] = snappedf(elapsed, 0.01)
	result["frames"] = sorted.size()
	if not sorted.is_empty():
		result["frame_ms_p50"] = snappedf(sorted[int(sorted.size() * 0.5)], 0.01)
		result["frame_ms_p95"] = snappedf(sorted[int((sorted.size() - 1) * 0.95)], 0.01)
		result["frame_ms_p99"] = snappedf(sorted[int((sorted.size() - 1) * 0.99)], 0.01)
	result["shots"] = shots
	result["errors"] = int(counted.get("errors", 0))
	result["warnings"] = int(counted.get("warnings", 0))
	result["error_samples"] = (counted.get("error_samples", []) as Array).slice(0, RESULT_SAMPLES)
	return result


## Process exit code for a result: EXIT_ERRORS when the run logged any error, else EXIT_INVARIANT
## when a Valley bot invariant failed ("invariants_ok" false), else EXIT_SCENARIO_FAILED when a
## scenario's own check failed ("scenario_ok" false), else EXIT_OK.
static func exit_code(result: Dictionary) -> int:
	if int(result.get("errors", 0)) > 0:
		return EXIT_ERRORS
	if result.has("invariants_ok") and not bool(result.invariants_ok):
		return EXIT_INVARIANT
	if result.has("scenario_ok") and not bool(result.scenario_ok):
		return EXIT_SCENARIO_FAILED
	return EXIT_OK


## The Valley bot's scenario failures: a single run fails on any watchdog breach (and on not
## completing the slice before --autoplay ends); a loop run (the stability run) only on a
## world_blocked breach (a softlock) - bot_failed breaches are reported, not failures (plan §5.2).
static func valley_failures(vb: Dictionary) -> PackedStringArray:
	var out := PackedStringArray()
	var loop := bool((vb.get("bot", {}) as Dictionary).get("loop", false))
	for b: Dictionary in vb.get("breaches", []):
		if loop and str(b.get("classification", "")) != BotDiagnosis.WORLD_BLOCKED:
			continue
		out.append("breach %s on %s: %s (%s)" % [b.get("reason", "?"), b.get("objective", "?"),
			b.get("detail", ""), b.get("classification", "?")])
	if not loop and not bool(vb.get("completed", false)) and (vb.get("breaches", []) as Array).is_empty() \
			and (vb.get("invariant_failures", []) as Array).is_empty():
		out.append("the slice was not completed before --autoplay ended")
	return out


## P38: the world bot's scenario failures: valley_failures' rules on the world bot's result (a single
## run fails on any watchdog breach and on an unfinished campaign; a loop run only on a world_blocked
## breach).
static func world_failures(wb: Dictionary) -> PackedStringArray:
	var out := PackedStringArray()
	var loop := bool((wb.get("bot", {}) as Dictionary).get("loop", false))
	for b: Dictionary in wb.get("breaches", []):
		if loop and str(b.get("classification", "")) != BotDiagnosis.WORLD_BLOCKED:
			continue
		out.append("breach %s on %s: %s (%s)" % [b.get("reason", "?"), b.get("objective", "?"),
			b.get("detail", ""), b.get("classification", "?")])
	var until := str(wb.get("finish_reason", "")) == "until"   # --bot-until reached: the run's own end
	if not loop and not until and not bool(wb.get("campaign_completed", false)) and (wb.get("breaches", []) as Array).is_empty() \
			and (wb.get("invariant_failures", []) as Array).is_empty():
		out.append("the campaign was not completed before --autoplay ended (stage %s)" % str(wb.get("main_stage", "?")))
	return out


# --------------------------------------------------------------------------- screenshot tour

func _entity_node(id: String) -> Node3D:
	var e := Sim.get_entity(id)
	return e.actor if e != null else null


func _shot(file_name: String) -> void:
	if DisplayServer.get_name() == "headless":
		_shots.append(file_name + " (skipped: headless)")
		return
	_busy = true
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(_capture_dir)
	var path := _capture_dir.path_join(file_name)
	img.save_png(path)
	_shots.append(file_name)
	print("captured ", path)
	_busy = false


## Each step returns true when finished.
func _run_capture(dt: float) -> void:
	var r := player.router
	_step_time += dt
	var steps := [
		func() -> bool: return _step_time > 0.8,
		func() -> bool: _shot("01_third_person_spawn.png"); return true,
		func() -> bool: return _walk_to(_entity_node("dummy_01"), 2.9, dt),
		func() -> bool: r.inject_light_attack(); return true,
		func() -> bool: return _step_time > 0.30,
		func() -> bool: _shot("02_light_swing.png"); return true,
		func() -> bool: return _step_time > 0.5,
		func() -> bool: r.set_injected_hold(&"heavy_modifier", true); r.inject_light_attack(); return true,
		func() -> bool: r.set_injected_hold(&"heavy_modifier", false); return true,
		func() -> bool: return _step_time > 0.72,
		func() -> bool: _shot("03_heavy_impact_numbers.png"); return true,
		func() -> bool: return _step_time > 1.0,
		func() -> bool: r.inject_edge(&"camera_toggle"); return true,
		func() -> bool: return _step_time > 0.4,
		func() -> bool: r.inject_light_attack(); return true,
		func() -> bool: return _step_time > 0.30,
		func() -> bool: _shot("04_first_person_swing.png"); return true,
		func() -> bool: return _step_time > 0.8,
		func() -> bool: r.inject_edge(&"camera_toggle"); return true,
		func() -> bool: return _walk_to(_entity_node("sandbox.fence_01"), 4.0, dt),
		func() -> bool: r.set_injected_hold(&"heavy_modifier", true); r.inject_light_attack(); return true,
		func() -> bool: r.set_injected_hold(&"heavy_modifier", false); return true,
		func() -> bool: return _step_time > 0.85,
		func() -> bool: _shot("05_fence_broken.png"); return true,
		func() -> bool: return _step_time > 0.6,
		func() -> bool: return _walk_to(_entity_node("dummy_01"), 2.6, dt),
		func() -> bool: r.inject_edge(&"slot_1"); return true,
		func() -> bool: return _step_time > 0.47,
		func() -> bool: _shot("06_heavy_footfall.png"); return true,
		func() -> bool: return _step_time > 1.0,
		func() -> bool: return _walk_to(_entity_node("soldier_01"), 11.0, dt, 25.0),
		func() -> bool: r.inject_edge(&"lock_press"); return true,
		func() -> bool: return _step_time > 0.8,
		func() -> bool: _shot("07_lock_on_soldier.png"); return true,
		func() -> bool: return _walk_to(_entity_node("soldier_01"), 3.0, dt, 15.0),
		func() -> bool: r.set_injected_hold(&"block", true); r.inject_edge(&"block_press"); return true,
		func() -> bool: return _step_time > 0.4,
		func() -> bool: _shot("08_block_vs_soldier.png"); return true,
		func() -> bool: r.set_injected_hold(&"block", false); r.inject_edge(&"block_release"); return true,
		func() -> bool: r.inject_light_attack(); return true,
		func() -> bool: return _step_time > 0.32,
		func() -> bool: _shot("09_attack_soldier.png"); return true,
		func() -> bool: _toggle_debug_panel(); return true,
		func() -> bool: return _step_time > 0.4,
		func() -> bool: _shot("10_debug_panel.png"); return true,
		func() -> bool: _finish(); return true,
	]
	if _step >= steps.size():
		return
	if steps[_step].call():
		_step += 1
		_step_time = 0.0


func _toggle_debug_panel() -> void:
	var panel := get_tree().get_first_node_in_group("hud_debug") as DebugPanel
	if panel != null:
		panel.toggle()


func _walk_to(target: Node3D, stop_distance: float, dt: float, timeout := 12.0) -> bool:
	if target == null:
		return true
	var dist := _face(target.global_position, dt, 10.0)
	var done := dist <= stop_distance or _step_time > timeout
	player.router.set_injected_move(Vector2.ZERO if done else Vector2(0, 1))
	player.router.set_injected_hold(&"sprint", dist > 10.0 and not done)
	return done
