extends Node
## The skinned giant, rendered (P43; plan M10 §3.3 tests, §1.7 rule 6, §2.13): tests/slow/test_skinned_rig_render.gd
## (stage 1) and tests/gate/test_skinned_rig_stages.gd (stages 4 and 6, the pressed-close camera) run this scene
## (tests/support/skinned_rig_probe.tscn: a main scene, so the autoloads exist) in a child Godot under Xvfb with
## the Compatibility renderer (the headless runner draws nothing):
##
##   LP_NUM_THREADS=2 xvfb-run -a -s "-screen 0 1280x720x24" godot --path . --rendering-driver opengl3 \
##     --resolution 320x240 --audio-driver Dummy res://tests/support/skinned_rig_probe.tscn -- --giant-tier=web \
##     [--probe-stage=N] [--probe-mode=frames|passage] [--probe-out=user://m10_frames/]
##
## The real scenes/player/giant.tscn (the skinned layers on: a display) stands on a lit floor and is driven
## through its InputRouter like the soak drives it; the probe draws a frame only when it captures one (the render
## loop is off in between). Mode "frames" (the default): idle, a walk (side and game camera), a heavy's windup,
## active and recovery (the swing measured against the tested segment in SkinnedRig.posed: the visible weapon's
## outer half against the capsule, its direction, the fist), a jump in the air, first person looking down and
## looking ahead (the crosshair: the centre pixels drawn with and without the giant must match). Mode "passage":
## the growth course's low passage (8.6 m ceiling) at stage 3, the third-person camera pressed close behind the
## head: the frame, and whether the giant covers the crosshair. Frames go to --probe-out (PNG, <stage>_<name>).
## Prints one line
##   SKIN_RENDER {"stage", "mode", "frames": {name: {"lit": share of pixels off the clear colour, "path"}},
##                "swing": {"samples", "outer_max_radii", "angle_max_deg", "fist_max_m"}, "crosshair": {...},
##                "frame_ms", "validate", "errors": [...]}
## and quits (a watchdog quits it after WATCHDOG_S).

const GIANT := "res://scenes/player/giant.tscn"
const COURSE := "res://scenes/test/growth_course.tscn"
const CLEAR := Color(0.36, 0.45, 0.56)
const WATCHDOG_S := 150.0
## The low passage of the growth course (tests/slow/test_growth_route.gd: z from -20 to -30, 8.6 m high).
const PASSAGE_POINT := Vector3(0.0, 0.05, -25.0)
## The crosshair: the centre block of pixels compared with and without the giant.
const CROSSHAIR_PX := 3

var stage := 1
var mode := "frames"
var out_dir := "user://m10_frames/"
var _root3d: Node3D
var _cam: Camera3D
var _p: GiantPlayer
var _out := {}
var _swing := {"samples": 0, "outer_max_radii": 0.0, "angle_max_deg": 0.0, "fist_max_m": 0.0, "outer_sum_radii": 0.0}


func _ready() -> void:
	get_tree().create_timer(WATCHDOG_S).timeout.connect(func() -> void:
		print("SKIN_RENDER {\"error\": \"the probe timed out\"}")
		get_tree().quit(3))
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--probe-stage="):
			stage = clampi(int(a.substr(14)), 1, 6)
		elif a.begins_with("--probe-mode="):
			mode = a.substr(13)
		elif a.begins_with("--probe-out="):
			out_dir = a.substr(12)
	DirAccess.make_dir_recursive_absolute(out_dir)
	RenderingServer.set_default_clear_color(CLEAR)
	_out = {"stage": stage, "mode": mode, "frames": {}, "adapter": RenderingServer.get_video_adapter_name()}
	_run.call_deferred()


func _run() -> void:
	if mode == "passage":
		await _passage()
	else:
		await _frames_mode()
	_out["swing"] = _swing
	var rig := _p.rig as SkinnedRig if _p != null else null
	if rig != null and rig.model() != null:
		_out["validate"] = Array(GiantLook.validate(rig.model(), rig.model().index, GiantLook.applied_look(rig.model())))
		_out["layers"] = rig.layers_on()
		_out["skin_stats"] = rig.skin_stats()
	print("SKIN_RENDER " + JSON.stringify(_out))
	get_tree().quit(0)


# --------------------------------------------------------------------------- the stage-N frames

func _frames_mode() -> void:
	_world()
	_spawn(Vector3(0, 0.05, 0))
	await _ticks(20)
	if stage > 1:
		var r: Dictionary = _p.growth.debug_set_stage(stage)
		_out["grown"] = bool(r.get("ok", false))
		await _ticks(30)
	var k := (_p.rig as ActorRig).body_scale
	_view(Vector3(3.4, 2.7, -5.0), Vector3(0, 1.9, 0))
	await _ticks(8)
	await _capture("idle")
	await _timed()
	# a walk (the camera keeps the yaw: the giant walks along -Z)
	_p.camera_rig.yaw = 0.0
	_p.router.set_injected_move(Vector2(0, 1))
	await _ticks(50)
	_view_follow(Vector3(5.0, 2.4, -1.0), Vector3(0, 1.7, -0.5))
	await _capture("walk_side")
	_p.camera_rig.camera.make_current()
	await _capture("walk_game")
	_p.router.set_injected_move(Vector2.ZERO)
	await _ticks(45)
	# the heavy: windup, active (measured every frame), recovery
	_view_follow(Vector3(5.6, 3.1, -2.0), Vector3(0, 2.4, -0.8))
	var a := GameData.get_action(str(_p.controller.loadout.get("heavy", "ability.heavy_1")))
	_p.entity.combatant.pools.stamina = _p.entity.combatant.pools.stamina_max
	_p.controller.request(&"heavy")
	var rig := _p.rig as SkinnedRig
	var on_posed := func() -> void: _measure(a)
	rig.posed.connect(on_posed)
	var got := {"windup": false, "active": false, "recovery": false}
	for i in 240:
		await _ticks(1)
		var c := _p.controller
		if c.action == null:
			if got.active:
				break
			continue
		var f := c.phase_fraction()
		if c.phase() == ActionDef.Phase.WINDUP and f > 0.6 and not got.windup:
			got.windup = true
			await _capture("heavy_windup")
		elif c.phase() == ActionDef.Phase.ACTIVE and f >= 0.4 and not got.active:
			got.active = true
			await _capture("heavy_active")
		elif c.phase() == ActionDef.Phase.RECOVERY and f > 0.2 and not got.recovery:
			got.recovery = true
			await _capture("heavy_recovery")
	rig.posed.disconnect(on_posed)
	await _ticks(40)
	# a jump: the airborne pose
	_view_follow(Vector3(5.0, 2.0, -1.5), Vector3(0, 2.2, 0))
	_p.router.inject_edge(&"jump")
	var airborne := false
	for i in 60:
		await _ticks(1)
		if not _p.is_on_floor() and _p.velocity.y < 1.5:
			airborne = true
			break
	_out["airborne"] = airborne
	await _capture("jump")
	await _ticks(60)
	# first person: looking down past the weapon, looking ahead (the crosshair)
	_p.camera_rig.set_mode(CameraRig.Mode.FIRST_PERSON)
	_p.camera_rig.yaw = 0.0
	_p.camera_rig.pitch = deg_to_rad(-60.0)
	_p.camera_rig.camera.make_current()
	await _ticks(4)
	await _capture("fp_down")
	_p.camera_rig.pitch = 0.0
	await _ticks(4)
	_out["crosshair"] = await _crosshair("fp_ahead")
	_p.camera_rig.set_mode(CameraRig.Mode.THIRD_PERSON)
	_out["k"] = k


## The swing in SkinnedRig.posed against the tested segment of this tick (plan §2.13: phase_fraction()).
func _measure(a: ActionDef) -> void:
	var c := _p.controller
	if c.action == null or c.action.id != a.id or c.phase() != ActionDef.Phase.ACTIVE:
		return
	var rig := _p.rig as SkinnedRig
	var seg := _p.weapon_segment_global(a, c.phase_fraction())
	var vis: Array = rig.visible_weapon_segment()
	if vis.size() < 2 or seg.size() < 2:
		return
	var vdir := ((vis[1] as Vector3) - (vis[0] as Vector3)).normalized()
	var length := (vis[1] as Vector3).distance_to(vis[0])
	var outer := TipMatching.outer_half_deviation(vis[0], vdir, length, seg[0], seg[1])
	var r := _p.weapon_hit_radius()
	_swing.samples = int(_swing.samples) + 1
	_swing.outer_max_radii = maxf(float(_swing.outer_max_radii), outer / r)
	_swing.outer_sum_radii = float(_swing.outer_sum_radii) + outer / r
	_swing.angle_max_deg = maxf(float(_swing.angle_max_deg), TipMatching.angle_deg(vdir, seg[1] - seg[0]))
	_swing.fist_max_m = maxf(float(_swing.fist_max_m), float(rig.modifier().stats.get("fist_error_m", 0.0)))


# --------------------------------------------------------------------------- the pressed-close camera

func _passage() -> void:
	var course := (load(COURSE) as PackedScene).instantiate() as Node3D
	add_child(course)
	_root3d = course
	_p = course.get_node("Player") as GiantPlayer
	_p.router.use_injection = true
	await _ticks(10)
	var r: Dictionary = _p.growth.debug_set_stage(3)
	_out["grown"] = bool(r.get("ok", false))
	await _ticks(20)
	_p.global_position = PASSAGE_POINT
	_p.camera_rig.yaw = 0.0
	_p.camera_rig.pitch = deg_to_rad(-12.0)
	await _ticks(90)
	_p.camera_rig.camera.make_current()
	_out["passage"] = {"arm_m": _p.camera_rig.current_distance, "head_hidden": _p.camera_rig.head_hidden,
		"cull_mask": _p.camera_rig.camera.cull_mask}
	_out["crosshair"] = await _crosshair("passage")


# --------------------------------------------------------------------------- the world, the camera, frames

func _world() -> void:
	_root3d = Node3D.new()
	add_child(_root3d)
	var ground := StaticBody3D.new()
	ground.collision_layer = HitQueryAdapter.LAYER_WORLD
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(400, 1, 400)
	cs.shape = box
	ground.add_child(cs)
	ground.position = Vector3(0, -0.5, 0)
	var gm := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = box.size
	gm.mesh = bm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.36, 0.42, 0.27)
	mat.roughness = 0.95
	gm.material_override = mat
	ground.add_child(gm)
	_root3d.add_child(ground)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, -35, 0)
	sun.light_energy = 1.3
	_root3d.add_child(sun)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = CLEAR
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.6, 0.64, 0.7)
	e.ambient_light_energy = 0.7
	env.environment = e
	_root3d.add_child(env)
	_cam = Camera3D.new()
	_cam.fov = 50.0
	_cam.far = 500.0
	_root3d.add_child(_cam)


func _spawn(at: Vector3) -> void:
	_p = (load(GIANT) as PackedScene).instantiate() as GiantPlayer
	_p.position = at
	_root3d.add_child(_p)
	_p.router.use_injection = true


## The probe camera at `from` looking at `at` (both in the giant's own space, x k).
func _view(from_local: Vector3, at_local: Vector3) -> void:
	var k := (_p.rig as ActorRig).body_scale
	_cam.global_position = _p.to_global(from_local * k)
	_cam.look_at(_p.to_global(at_local * k), Vector3.UP)
	_cam.make_current()


func _view_follow(from_local: Vector3, at_local: Vector3) -> void:
	_view(from_local, at_local)


func _ticks(n: int) -> void:
	for i in n:
		await get_tree().physics_frame
	await get_tree().process_frame


## Draws one frame (the loop is off otherwise), saves it and counts its pixels off the clear colour.
func _capture(frame_name: String) -> Dictionary:
	var img := await _draw()
	var path := "%s/s%d_%s.png" % [out_dir.trim_suffix("/"), stage, frame_name]
	img.save_png(path)
	var lit := 0
	var n := 0
	for y in range(0, img.get_height(), 2):
		for x in range(0, img.get_width(), 2):
			n += 1
			var c := img.get_pixel(x, y)
			if absf(c.r - CLEAR.r) + absf(c.g - CLEAR.g) + absf(c.b - CLEAR.b) > 0.06:
				lit += 1
	var rec := {"lit": float(lit) / maxf(1.0, float(n)), "path": ProjectSettings.globalize_path(path)}
	_out.frames[frame_name] = rec
	return rec


func _draw() -> Image:
	RenderingServer.render_loop_enabled = true
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	RenderingServer.render_loop_enabled = false
	return img


## The crosshair: the centre pixels of a frame with the giant and of the same frame without him (his Visual
## hidden) - the same when the giant's body does not cover the centre.
func _crosshair(frame_name: String) -> Dictionary:
	var with_giant := await _capture(frame_name)
	var img := Image.load_from_file(str(with_giant.path))
	var vis := _p.get_node("Visual") as Node3D
	vis.visible = false
	var img2 := await _draw()
	vis.visible = true
	var cx := img.get_width() / 2
	var cy := img.get_height() / 2
	var diff := 0.0
	for dy in range(-CROSSHAIR_PX, CROSSHAIR_PX + 1):
		for dx in range(-CROSSHAIR_PX, CROSSHAIR_PX + 1):
			var a := img.get_pixel(cx + dx, cy + dy)
			var b := img2.get_pixel(cx + dx, cy + dy)
			diff = maxf(diff, absf(a.r - b.r) + absf(a.g - b.g) + absf(a.b - b.b))
	return {"covered": diff > 0.1, "diff": diff, "frame": frame_name}


## The cost of a frame of the whole giant (wall time, the loop on for TIMED frames).
func _timed() -> void:
	RenderingServer.render_loop_enabled = true
	await RenderingServer.frame_post_draw
	var t0 := Time.get_ticks_usec()
	for i in 8:
		await RenderingServer.frame_post_draw
	_out["frame_ms"] = float(Time.get_ticks_usec() - t0) / 8000.0
	RenderingServer.render_loop_enabled = false
