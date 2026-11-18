class_name SkinnedRigProbe
extends Node
## The skinned giant, rendered (P43; plan M10 §3.3 tests, §1.7 rule 6, §2.13): tests/slow/test_skinned_rig_render.gd
## (stage 1) and tests/gate/test_skinned_rig_stages.gd (stages 4 and 6, the pressed-close camera) run this scene
## (tests/support/skinned_rig_probe.tscn: a main scene, so the autoloads exist) in a child Godot under Xvfb with
## the Compatibility renderer (the headless runner draws nothing):
##
##   LP_NUM_THREADS=2 xvfb-run -a -s "-screen 0 1280x720x24" godot --path . --rendering-driver opengl3 \
##     --resolution 320x240 --audio-driver Dummy res://tests/support/skinned_rig_probe.tscn -- --giant-tier=web \
##     [--probe-stage=N] [--probe-mode=frames|passage|fp_down] [--probe-out=user://m10_frames/] [--probe-weapon=ID]
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
##                "frame_ms", "validate", "captures", "capture_ticks_max" (the simulation ticks a draw let
##                through: 0, the tree is paused while a frame is drawn), "errors": [...]}
## and quits (a watchdog quits it after WATCHDOG_S).

const SCENE := "res://tests/support/skinned_rig_probe.tscn"
const PREFIX := "SKIN_RENDER "
const OUT := "user://m10_frames/"
## A frame counts as drawn when this share of its pixels differs from the clear colour.
const MIN_LIT := 0.05
## The frames of mode "frames".
const FRAME_NAMES := ["idle", "walk_side", "walk_game", "heavy_windup", "heavy_active", "heavy_recovery", "jump", "fp_down", "fp_ahead"]
const GIANT := "res://scenes/player/giant.tscn"
const COURSE := "res://scenes/test/growth_course.tscn"
const CLEAR := Color(0.36, 0.45, 0.56)
const WATCHDOG_S := 150.0
## The low passage of the growth course (tests/slow/test_growth_route.gd: z from -20 to -30, 8.6 m high).
const PASSAGE_POINT := Vector3(0.0, 0.05, -25.0)
## The crosshair: the centre block of pixels compared with and without the giant.
const CROSSHAIR_PX := 3
## Mode "fp_down": the pitches drawn, and the size of a bottom corner block (a share of the frame each way).
const FP_DOWN_PITCHES := [-55.0, -70.0, -85.0]
const FP_CORNER := Vector2(0.16, 0.24)
const FP_MOVE_FRAMES := 4

var stage := 1
var mode := "frames"
var out_dir := "user://m10_frames/"
var weapon_id := ""
var _root3d: Node3D
var _cam: Camera3D
var _p: GiantPlayer
var _out := {}
var _swing := {"samples": 0, "outer_max_radii": 0.0, "angle_max_deg": 0.0, "fist_max_m": 0.0, "outer_sum_radii": 0.0}


## True when xvfb-run is installed (the rendered suites skip with a note otherwise).
static func have_xvfb() -> bool:
	var out: Array = []
	return OS.execute("sh", ["-c", "command -v xvfb-run"], out, true) == 0


## Runs the probe in a child Godot under Xvfb (opengl3, LP_NUM_THREADS=2, 320x240 unless `resolution` says
## otherwise - mode "fp_down" wants the game's 16:9 -, the web tier's maps), its
## frames under OUT: {"code", "report" (the parsed SKIN_RENDER line or {}), "output"}.
static func run(extra: PackedStringArray, resolution := "320x240") -> Dictionary:
	var args := PackedStringArray(["-a", "-s", "-screen 0 1280x720x24", "env", "LP_NUM_THREADS=2", OS.get_executable_path(),
		"--path", ProjectSettings.globalize_path("res://"), "--rendering-driver", "opengl3", "--resolution", resolution,
		"--audio-driver", "Dummy", SCENE, "--", "--no-user-settings", "--giant-tier=web",
		"--probe-out=" + ProjectSettings.globalize_path(OUT)])
	args.append_array(extra)
	var output: Array = []
	var code := OS.execute("xvfb-run", args, output, true)
	var text := "\n".join(output)
	var line := ""
	for l in text.split("\n"):
		if l.begins_with(PREFIX):
			line = l.substr(PREFIX.length()).strip_edges()
	var parsed: Variant = JSON.parse_string(line) if line != "" else null
	return {"code": code, "report": parsed if typeof(parsed) == TYPE_DICTIONARY else {}, "output": text}


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
		elif a.begins_with("--probe-weapon="):
			weapon_id = a.substr(15)
	DirAccess.make_dir_recursive_absolute(out_dir)
	RenderingServer.set_default_clear_color(CLEAR)
	_out = {"stage": stage, "mode": mode, "frames": {}, "adapter": RenderingServer.get_video_adapter_name()}
	_run.call_deferred()


func _run() -> void:
	if mode == "passage":
		await _passage()
	elif mode == "fp_down":
		await _fp_down_mode()
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
	if weapon_id != "":
		_out["weapon"] = _p.equipment.grant_weapon(weapon_id, true)
		await _ticks(4)
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


# --------------------------------------------------------------------------- first person, looking down

## Mode "fp_down" (the M10 gate's LC-3): first person at rest at each of FP_DOWN_PITCHES, then walking and
## sprinting at -70 degrees (the worst of FP_MOVE_FRAMES moments of each), each frame drawn with the giant and
## without him; "fp_corners" reports, per frame, the share of the pixels of the two bottom corner
## blocks (FP_CORNER of the frame each) that the giant changes. Before the fix the arms' shoulder caps filled
## them (flat, saw-toothed slabs); with it the limbs fade out towards the shoulders and the corners show the
## ground.
func _fp_down_mode() -> void:
	_world()
	_spawn(Vector3(0, 0.05, 0))
	await _ticks(20)
	if stage > 1:
		var r: Dictionary = _p.growth.debug_set_stage(stage)
		_out["grown"] = bool(r.get("ok", false))
		await _ticks(30)
	if weapon_id != "":
		_out["weapon"] = _p.equipment.grant_weapon(weapon_id, true)
		await _ticks(4)
	_p.camera_rig.set_mode(CameraRig.Mode.FIRST_PERSON)
	_p.camera_rig.yaw = 0.0
	var vis := _p.get_node("Visual") as Node3D
	var corners := {}
	for pitch: float in FP_DOWN_PITCHES:
		_p.camera_rig.pitch = deg_to_rad(pitch)
		_p.camera_rig.camera.make_current()
		await _ticks(4)
		var frame_name := "fp_down%d" % int(-pitch)
		var rec := await _capture(frame_name)
		var with_giant := Image.load_from_file(str(rec.path))
		vis.visible = false
		var without := await _draw()
		vis.visible = true
		corners[frame_name] = {"left": _block_diff(with_giant, without, false), "right": _block_diff(with_giant, without, true),
			"drawn": _block_diff(with_giant, without, false, Vector2(1.0, 1.0))}
	# on the move: a walk, then a sprint, at -70 degrees, at FP_MOVE_FRAMES moments of the stride (the camera bobs,
	# the body leans: the corners must stay clear)
	_p.camera_rig.pitch = deg_to_rad(-70.0)
	for gait: String in ["walk", "sprint"]:
		_p.router.set_injected_move(Vector2(0, 1))
		_p.router.set_injected_hold(&"sprint", gait == "sprint")
		await _ticks(40)
		var worst := {"left": 0.0, "right": 0.0, "drawn": 1.0}
		for i in FP_MOVE_FRAMES:
			await _ticks(7)
			var rec := await _capture("fp_%s70_%d" % [gait, i])
			var with_giant := Image.load_from_file(str(rec.path))
			vis.visible = false
			var without := await _draw()
			vis.visible = true
			worst.left = maxf(worst.left, _block_diff(with_giant, without, false))
			worst.right = maxf(worst.right, _block_diff(with_giant, without, true))
			worst.drawn = minf(worst.drawn, _block_diff(with_giant, without, false, Vector2(1.0, 1.0)))
		corners["fp_%s70" % gait] = worst
	_p.router.set_injected_hold(&"sprint", false)
	_p.router.set_injected_move(Vector2.ZERO)
	_out["fp_corners"] = corners
	_p.camera_rig.set_mode(CameraRig.Mode.THIRD_PERSON)


## The share of the pixels of a bottom block (`size` of the frame; the left one or the right one) that differ
## between two frames.
static func _block_diff(a: Image, b: Image, right: bool, size := FP_CORNER) -> float:
	var w := int(a.get_width() * size.x)
	var h := int(a.get_height() * size.y)
	var x0 := a.get_width() - w if right else 0
	var y0 := a.get_height() - h
	var n := 0
	for y in range(y0, y0 + h):
		for x in range(x0, x0 + w):
			var ca := a.get_pixel(x, y)
			var cb := b.get_pixel(x, y)
			if absf(ca.r - cb.r) + absf(ca.g - cb.g) + absf(ca.b - cb.b) > 0.1:
				n += 1
	return float(n) / maxf(1.0, float(w * h))


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


## M10 gate (LC-8): the simulation is held while the frame is drawn (the tree paused: Sim ticks only in an
## unpaused tree), so the pose captured is the pose of the tick that asked for it and no phase can pass
## behind a slow draw. Before, the three loop iterations of a draw ran up to 8 ticks each when a frame took
## long (a large window, one rasterizer thread, a loaded machine), and a heavy's ACTIVE phase went by while
## its windup frame was drawn. `capture_ticks_max` reports the most ticks any draw let through (0).
func _draw() -> Image:
	var was_paused := get_tree().paused
	var tick0 := Sim.tick
	get_tree().paused = true
	RenderingServer.render_loop_enabled = true
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	RenderingServer.render_loop_enabled = false
	get_tree().paused = was_paused
	_out["capture_ticks_max"] = maxi(int(_out.get("capture_ticks_max", 0)), Sim.tick - tick0)
	_out["captures"] = int(_out.get("captures", 0)) + 1
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
