class_name Autopilot
extends Node
## Seeded bot for soak runs and a scripted screenshot tour.
##
## It drives the player only through the InputRouter injection API (the same intent path as
## a keyboard) and by turning the camera like a mouse would - never by editing combat state.
## State lives in static variables so a run survives sandbox resets (scene reloads).
## Prints one "AUTOPILOT_RESULT {json}" line, then quits.

static var _started := false
static var _elapsed := 0.0
static var _duration := 0.0
static var _scenario := ""
static var _capture_dir := ""
static var _stats: Dictionary = {}
static var _frame_ms: Array[float] = []
static var _step := 0
static var _rng := RandomNumberGenerator.new()

var player: GiantPlayer
var _decision_left := 0.0
var _block_left := 0.0
var _heavy_pending := false
var _dead_time := 0.0
var _no_soldier_time := 0.0
var _step_time := 0.0
var _busy := false
var _stuck_time := 0.0
var _strafe_left := 0.0
var _strafe_sign := 1.0
var _shots: Array[String] = []


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
		"max_debris": 0, "rejections": 0}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS if _scenario == "capture" else Node.PROCESS_MODE_PAUSABLE
	# Method callables (not lambdas): they disconnect automatically when this node is freed
	# by a sandbox reset, so counts are never duplicated.
	Events.hit_resolved.connect(_on_hit_resolved)
	Events.entity_died.connect(_on_entity_died)
	Events.object_destroyed.connect(_on_object_destroyed)
	Events.action_rejected.connect(_on_action_rejected)


func _on_hit_resolved(_t: int, r: HitResult) -> void:
	_stats.hits_resolved += 1
	if r.outcome == HitResult.Outcome.PARRIED:
		_stats.parries += 1


func _on_entity_died(_t: int, id: String, _k: String) -> void:
	if id.begins_with("soldier"):
		_stats.soldier_kills += 1


func _on_object_destroyed(_t: int, _id: String, _by: String) -> void:
	_stats.fence_breaks += 1


func _on_action_rejected(_t: int, _a: String, _id: String, _r: String) -> void:
	_stats.rejections += 1


func _process(delta: float) -> void:
	if _frame_ms.size() < 200000:
		_frame_ms.append(delta * 1000.0)


func _physics_process(dt: float) -> void:
	if get_tree().paused and _scenario != "capture":
		return
	_elapsed += dt
	_stats.ticks += 1
	if _duration > 0.0 and _elapsed >= _duration:
		_finish()
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
	_run_soak(dt)


# --------------------------------------------------------------------------- soak

func _alive_soldier() -> SoldierEnemy:
	for n in get_tree().get_nodes_in_group("enemies"):
		var s := n as SoldierEnemy
		if s != null and s.entity.is_alive():
			return s
	return null


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
	var soldier := _alive_soldier()
	var target: Node3D = soldier
	if soldier == null:
		_no_soldier_time += dt
		if _no_soldier_time > 12.0:
			_no_soldier_time = -1000.0
			_stats.resets += 1
			Events.sandbox_reset_requested.emit("autopilot_respawn_soldier")
			return
		var fence := get_tree().get_first_node_in_group("breakables") as BreakableProp
		target = fence if fence != null and not fence.destroyed else get_tree().get_first_node_in_group("dummies") as Node3D
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
	var sorted := _frame_ms.duplicate()
	sorted.sort()
	var result := _stats.duplicate()
	result["simulated_s"] = snappedf(_elapsed, 0.01)
	result["frames"] = sorted.size()
	if not sorted.is_empty():
		result["frame_ms_p50"] = snappedf(sorted[int(sorted.size() * 0.5)], 0.01)
		result["frame_ms_p95"] = snappedf(sorted[int((sorted.size() - 1) * 0.95)], 0.01)
		result["frame_ms_p99"] = snappedf(sorted[int((sorted.size() - 1) * 0.99)], 0.01)
	result["shots"] = _shots
	print("AUTOPILOT_RESULT " + JSON.stringify(result))
	get_tree().quit(0)


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
