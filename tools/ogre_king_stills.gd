extends Node
## B2: stills of the Ogre King as the asset pipeline made him (OgreKingModel, his clips; no actor), one PNG a shot at
## 1280 x 720, in a studio's neutral light or the world's: the turnaround beside a stage-3 giant (orthographic, so the
## heights are honest), the trophies close up, his clips' keys, a trophy cracked and broken. The evidence for
## docs/systems/B2.md and the look's own check.
##
##   LP_NUM_THREADS=2 xvfb-run -a -s "-screen 0 1280x720x24" tools/gd.sh --path . --rendering-driver opengl3 \
##     --resolution 1280x720 --audio-driver Dummy res://tools/ogre_king_stills.tscn -- --out=<dir> [--shots=a,b,...]
##
## Prints OGRE_KING_STILLS {"shots": [paths], "ms"} and quits (a watchdog quits it after WATCHDOG_S).

const SIZE := Vector2i(1280, 720)
const WATCHDOG_S := 600.0
const PREFIX := "OGRE_KING_STILLS "
const GIANT_MODEL_SCENE := "res://scenes/player/giant_model.tscn"
const STAGE3_H := 7.9248
const KING_H := 8.5

var out_dir := ""
var only: PackedStringArray = []
var _king: OgreKingModel
var _giant: GiantModel
var _cam: Camera3D
var _sun: DirectionalLight3D
var _env: Environment
var _written := PackedStringArray()


func _ready() -> void:
	get_tree().create_timer(WATCHDOG_S).timeout.connect(func() -> void:
		print(PREFIX + JSON.stringify({"error": "timed out", "shots": Array(_written)}))
		get_tree().quit(3))
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out_dir = arg.substr(6)
		elif arg.begins_with("--shots="):
			only = arg.substr(8).split(",", false)
	if out_dir == "":
		out_dir = ProjectSettings.globalize_path("user://ogre_king_stills")
	DirAccess.make_dir_recursive_absolute(out_dir)
	_make_stage()
	await get_tree().process_frame
	_run.call_deferred()


## The shots: {name, clip, t (s) or phase (0..1 of the clip), view (front, side, back, three_quarter, close ...),
## ortho (the turnaround: an orthographic camera framing both figures whole), giant (a stage-3 giant beside him),
## hidden (trophies broken off), cracks {trophy: amount}, focus (a bone or a piece) dir, dist, lift}.
static func shots() -> Array:
	var out: Array = []
	for v: String in ["front", "side", "back"]:
		out.append({"name": "sheet_%s" % v, "view": v, "ortho": true, "giant": true})
	out.append({"name": "three_quarter", "view": "three_quarter"})
	out.append({"name": "back_quarter", "view": "back_quarter"})
	out.append({"name": "close_crown", "focus": "trophy_crown", "dir": Vector3(0.35, 0.25, 1.0), "dist": 3.2})
	out.append({"name": "close_bell", "focus": "trophy_bell", "dir": Vector3(-0.3, 0.1, 1.0), "dist": 4.6})
	out.append({"name": "close_wheel", "focus": "trophy_wheel_l", "dir": Vector3(1.0, 0.35, 0.4), "dist": 4.0})
	out.append({"name": "close_keg", "focus": "trophy_keg", "dir": Vector3(-0.3, 0.15, -1.0), "dist": 4.6})
	out.append({"name": "close_belt", "focus": "chain_belt", "dir": Vector3(0.5, 0.0, 1.0), "dist": 4.4})
	out.append({"name": "close_ram", "focus": "hand_r", "dir": Vector3(-0.8, 0.3, 0.6), "dist": 6.5})
	out.append({"name": "crack_bell_cracked", "focus": "trophy_bell", "dir": Vector3(-0.2, 0.1, 1.0), "dist": 4.6,
		"cracks": {"trophy_bell": OgreKingModel.CRACKED}})
	out.append({"name": "crack_bell_badly", "focus": "trophy_bell", "dir": Vector3(-0.2, 0.1, 1.0), "dist": 4.6,
		"cracks": {"trophy_bell": OgreKingModel.BADLY_CRACKED}})
	out.append({"name": "crack_wheel_badly", "focus": "trophy_wheel_l", "dir": Vector3(1.0, 0.35, 0.4), "dist": 4.0,
		"cracks": {"trophy_wheel_l": OgreKingModel.BADLY_CRACKED, "trophy_crown": OgreKingModel.BADLY_CRACKED}})
	out.append({"name": "broken_bell", "view": "front", "hidden": ["trophy_bell"]})
	out.append({"name": "broken_all", "view": "three_quarter", "hidden": OgreKingModel.TROPHIES})
	for c: Array in [["walk", 0.0], ["walk", 0.5], ["roar", 0.6], ["combo_a", 0.5], ["combo_a", 0.8], ["combo_a", 1.0],
			["combo_b", 0.5], ["combo_b", 0.8], ["combo_b", 1.0], ["slam", 0.55], ["slam", 1.2], ["slam", 1.5],
			["slam", 2.4], ["charge", 0.9], ["charge_run", 0.3], ["reel", 0.8], ["kneel", 0.8], ["rise", 0.5],
			["death", 0.5], ["death", 1.3], ["death", 3.2]]:
		out.append({"name": "clip_%s_%02d" % [str(c[0]), int(round(float(c[1]) * 10.0))], "clip": c[0], "t": c[1],
			"view": "clip"})
	return out


func _run() -> void:
	var t0 := Time.get_ticks_msec()
	for shot: Dictionary in shots():
		if not only.is_empty() and not str(shot.name) in only:
			continue
		await _render(shot)
	print(PREFIX + JSON.stringify({"shots": Array(_written), "ms": Time.get_ticks_msec() - t0}))
	get_tree().quit(0)


func _make_stage() -> void:
	var we := WorldEnvironment.new()
	_env = Environment.new()
	_env.background_mode = Environment.BG_COLOR
	_env.background_color = Color(0.56, 0.57, 0.58)
	_env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	_env.ambient_light_color = Color(0.66, 0.66, 0.68)
	_env.ambient_light_energy = 0.6
	_env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	we.environment = _env
	add_child(we)
	_sun = DirectionalLight3D.new()
	_sun.rotation_degrees = Vector3(-42, 28, 0)
	_sun.light_energy = 1.2
	_sun.shadow_enabled = true
	_sun.directional_shadow_max_distance = 40.0
	add_child(_sun)
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(120, 120)
	ground.mesh = plane
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.47, 0.46, 0.44)
	gm.roughness = 0.95
	ground.material_override = gm
	add_child(ground)
	_king = OgreKingModel.new()
	_king.name = "OgreKing"
	add_child(_king)
	_giant = (load(GIANT_MODEL_SCENE) as PackedScene).instantiate() as GiantModel
	add_child(_giant)
	GiantLook.build_materials(_giant, _giant.index, "auto")
	_giant.apply_defaults()
	_giant.pose_relaxed()
	_giant.scale = Vector3.ONE * (STAGE3_H / GiantPreview.STAGE1_HEIGHT_M)
	_giant.rotation.y = PI
	_giant.visible = false
	_cam = Camera3D.new()
	_cam.fov = 38.0
	_cam.near = 0.05
	add_child(_cam)
	_cam.current = true


func _render(shot: Dictionary) -> void:
	var clip := str(shot.get("clip", "idle"))
	_king.pose(clip, float(shot.get("t", 0.0)))
	_king.set_trophies(true)
	for n: String in OgreKingModel.TROPHIES:
		_king.set_trophy_crack(n, float((shot.get("cracks", {}) as Dictionary).get(n, 0.0)))
	for n: Variant in shot.get("hidden", []):
		_king.set_trophy_visible(str(n), false)
	var with_giant := bool(shot.get("giant", false))
	_giant.visible = with_giant
	_king.position = Vector3(3.2, 0.0, 0.0) if with_giant else Vector3.ZERO
	_giant.position = Vector3(-3.6, 0.0, 0.0) if str(shot.get("view", "")) != "side" else Vector3(0.0, 0.0, 6.0)
	if with_giant and str(shot.get("view", "")) == "side":
		_king.position = Vector3(0.0, 0.0, -4.0)
	var view := str(shot.get("view", "close"))
	var dir := Vector3(0.0, 0.0, 1.0)
	match view:
		"front":
			dir = Vector3(0.0, 0.0, 1.0)
		"side":
			dir = Vector3(1.0, 0.0, 0.0)
		"back":
			dir = Vector3(0.0, 0.0, -1.0)
		"three_quarter":
			dir = Vector3(0.75, 0.16, 0.7)
		"back_quarter":
			dir = Vector3(-0.7, 0.2, -0.75)
		"clip":
			dir = Vector3(0.85, 0.12, 0.6)
	var ortho := bool(shot.get("ortho", false))
	_cam.projection = Camera3D.PROJECTION_ORTHOGONAL if ortho else Camera3D.PROJECTION_PERSPECTIVE
	if ortho:
		# both figures whole, the camera level at half their height (no foreshortening: the heights read true)
		_cam.size = 10.4
		var look := Vector3(0.0, 4.9, 0.0)
		_giant.rotation.y = PI
		_cam.global_position = look + dir * 40.0
		_cam.look_at(look, Vector3.UP)
	else:
		var look := Vector3(0.0, KING_H * 0.5, 0.0)
		var dist := KING_H * 1.75
		if shot.has("focus"):
			var f := str(shot.focus)
			look = _king.piece_centre(f) if _king.piece(f) != null else _king.bone_position(f)
			look += Vector3(0.0, float(shot.get("lift", 0.0)), 0.0)
			dir = shot.get("dir", dir)
			dist = float(shot.get("dist", 4.0))
		elif view == "clip":
			var pel := _king.bone_position("pelvis")
			look = Vector3(pel.x, KING_H * 0.45, pel.z)
			dist = KING_H * 2.1
		_cam.global_position = look + dir.normalized() * dist
		_cam.look_at(look, Vector3.UP)
	for i in 3:
		await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := out_dir.path_join("%s.png" % str(shot.name))
	if img.save_png(path) == OK:
		_written.append(path)
