extends Node
## B3: stills of the Rootwarden as the asset pipeline made him (RootwardenModel, his clips; no actor), one PNG a shot
## at 1280 x 720 in a studio's neutral light: the turnaround beside a stage-5 and a stage-6 giant (orthographic, so the
## heights are honest), the three titans side by side (Stoneback, the Ogre King, the Rootwarden: their silhouettes),
## the bark plates, the knot and the crown close up, his clips' keys, a plate cracked, broken (the sapwood), regrowing
## and seared. The evidence for docs/systems/B3.md and the look's own check.
##
##   LP_NUM_THREADS=2 xvfb-run -a -s "-screen 0 1280x720x24" tools/gd.sh --path . --rendering-driver opengl3 \
##     --resolution 1280x720 --audio-driver Dummy res://tools/rootwarden_stills.tscn -- --out=<dir> [--shots=a,b,...]
##
## Prints ROOTWARDEN_STILLS {"shots": [paths], "ms"} and quits (a watchdog quits it after WATCHDOG_S).

const SIZE := Vector2i(1280, 720)
const WATCHDOG_S := 900.0
const PREFIX := "ROOTWARDEN_STILLS "
const GIANT_MODEL_SCENE := "res://scenes/player/giant_model.tscn"
const STAGE5_H := 14.6304
const STAGE6_H := 18.8976
const WARDEN_H := 21.3

var out_dir := ""
var only: PackedStringArray = []
var _warden: RootwardenModel
var _stone: StonebackRig
var _king: OgreKingModel
var _giants: Array[GiantModel] = []
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
		out_dir = ProjectSettings.globalize_path("user://rootwarden_stills")
	DirAccess.make_dir_recursive_absolute(out_dir)
	_make_stage()
	await get_tree().process_frame
	_run.call_deferred()


## The shots: {name, clip, t (s), view, ortho, giants (stage-5 and stage-6 giants beside him), trio (the three titans),
## hidden (plates broken off), cracks {plate: amount}, grows {plate: amount}, chars {plate: amount}, tree (shown),
## focus (a bone or a piece), dir, dist, lift}.
static func shots() -> Array:
	var out: Array = []
	for v: String in ["front", "side", "back"]:
		out.append({"name": "sheet_%s" % v, "view": v, "ortho": true, "giants": true})
	out.append({"name": "titans_trio", "view": "front", "ortho": true, "trio": true})
	out.append({"name": "titans_trio_side", "view": "side", "ortho": true, "trio": true})
	out.append({"name": "three_quarter", "view": "three_quarter"})
	out.append({"name": "back_quarter", "view": "back_quarter"})
	out.append({"name": "dormant", "clip": "dormant", "t": 0.0, "view": "three_quarter"})
	out.append({"name": "close_shoulder", "focus": "bark_shoulder_l", "dir": Vector3(0.8, 0.35, 0.6), "dist": 7.0})
	out.append({"name": "close_back", "focus": "bark_back", "dir": Vector3(-0.3, 0.25, -1.0), "dist": 9.0})
	out.append({"name": "close_knot", "focus": "bark_knot", "dir": Vector3(0.9, 0.2, 0.3), "dist": 5.5})
	out.append({"name": "close_shin", "focus": "bark_shin_r", "dir": Vector3(-0.4, 0.15, 1.0), "dist": 7.0})
	out.append({"name": "close_brow", "focus": "head", "dir": Vector3(0.35, 0.15, 1.0), "dist": 7.5, "lift": 0.6})
	out.append({"name": "close_roots", "focus": "hand_l", "dir": Vector3(0.8, 0.1, 0.7), "dist": 11.0, "lift": -3.0})
	out.append({"name": "plate_cracked", "focus": "bark_shoulder_l", "dir": Vector3(0.8, 0.35, 0.6), "dist": 7.0,
		"cracks": {"bark_shoulder_l": RootwardenModel.BADLY_CRACKED}})
	out.append({"name": "plate_broken", "focus": "bark_shoulder_l", "dir": Vector3(0.8, 0.35, 0.6), "dist": 7.0,
		"hidden": ["bark_shoulder_l"]})
	out.append({"name": "plate_regrowing", "focus": "bark_shoulder_l", "dir": Vector3(0.8, 0.35, 0.6), "dist": 7.0,
		"hidden": ["bark_shoulder_l"], "grows": {"bark_shoulder_l": 0.55}})
	out.append({"name": "plate_seared", "focus": "bark_shoulder_l", "dir": Vector3(0.8, 0.35, 0.6), "dist": 7.0,
		"hidden": ["bark_shoulder_l"], "chars": {"bark_shoulder_l": 1.0}})
	out.append({"name": "knot_broken", "focus": "bark_knot", "dir": Vector3(0.9, 0.2, 0.3), "dist": 5.5,
		"hidden": ["bark_knot"]})
	out.append({"name": "broken_all", "view": "three_quarter", "hidden": RootwardenModel.PLATES})
	for c: Array in [["walk", 0.0], ["walk", 0.5], ["run", 0.3], ["roar", 1.1], ["uproot", 0.6], ["uproot", 1.1],
			["lash", 0.7], ["lash", 1.0], ["lash", 1.3], ["erupt", 0.75], ["erupt", 1.05], ["snare", 0.55],
			["snare", 0.8], ["rip", 0.7], ["rip", 1.2], ["hurl", 0.55], ["hurl", 0.8], ["stomp", 0.5], ["stomp", 0.75],
			["reel", 0.85], ["kneel", 0.8], ["rise", 0.6], ["death", 1.3], ["death", 3.2]]:
		var shot := {"name": "clip_%s_%02d" % [str(c[0]), int(round(float(c[1]) * 10.0))], "clip": c[0], "t": c[1],
			"view": "clip"}
		if str(c[0]) in ["rip", "hurl"]:
			shot["tree"] = true
		out.append(shot)
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
	_sun.directional_shadow_max_distance = 120.0
	add_child(_sun)
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(300, 300)
	ground.mesh = plane
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.47, 0.46, 0.44)
	gm.roughness = 0.95
	ground.material_override = gm
	add_child(ground)
	_warden = RootwardenModel.new()
	_warden.name = "Rootwarden"
	add_child(_warden)
	_stone = StonebackRig.new()
	_stone.name = "Stoneback"
	add_child(_stone)
	_stone.visible = false
	_king = OgreKingModel.new()
	_king.name = "OgreKing"
	add_child(_king)
	_king.visible = false
	for h: float in [STAGE5_H, STAGE6_H]:
		var g := (load(GIANT_MODEL_SCENE) as PackedScene).instantiate() as GiantModel
		add_child(g)
		GiantLook.build_materials(g, g.index, "auto")
		g.apply_defaults()
		g.pose_relaxed()
		g.scale = Vector3.ONE * (h / GiantPreview.STAGE1_HEIGHT_M)
		g.rotation.y = PI
		g.visible = false
		_giants.append(g)
	_cam = Camera3D.new()
	_cam.fov = 38.0
	_cam.near = 0.1
	_cam.far = 800.0
	add_child(_cam)
	_cam.current = true


func _render(shot: Dictionary) -> void:
	var clip := str(shot.get("clip", "idle"))
	_warden.pose(clip, float(shot.get("t", 0.0)))
	_warden.set_plates(true)
	_warden.set_tree(bool(shot.get("tree", false)))
	for n: String in RootwardenModel.PLATES:
		_warden.set_plate_crack(n, float((shot.get("cracks", {}) as Dictionary).get(n, 0.0)))
		_warden.set_plate_grow(n, 1.0)
		_warden.set_sap_char(n, float((shot.get("chars", {}) as Dictionary).get(n, 0.0)))
	for n: Variant in shot.get("hidden", []):
		_warden.set_plate_visible(str(n), false)
	for n: Variant in (shot.get("grows", {}) as Dictionary):
		# regrowing: the plate shown again, eaten away over its sapwood
		(_warden.piece(str(n)) as MeshInstance3D).visible = true
		_warden.set_plate_grow(str(n), float(shot.grows[n]))
	var with_giants := bool(shot.get("giants", false))
	var trio := bool(shot.get("trio", false))
	var view := str(shot.get("view", "close"))
	for g in _giants:
		g.visible = with_giants
	_stone.visible = trio
	_king.visible = trio
	_warden.position = Vector3.ZERO
	_warden.rotation.y = 0.0
	if with_giants:
		_warden.position = Vector3(8.0, 0.0, 0.0) if view != "side" else Vector3(0.0, 0.0, -6.0)
		_giants[0].position = Vector3(-14.0, 0.0, 0.0) if view != "side" else Vector3(0.0, 0.0, 12.0)
		_giants[1].position = Vector3(-3.0, 0.0, 0.0) if view != "side" else Vector3(0.0, 0.0, 4.0)
	if trio:
		_stone.pose("idle", 0.0)
		_king.pose("idle", 0.0)
		_stone.rotation.y = 0.0
		_king.rotation.y = 0.0
		if view == "side":
			_king.position = Vector3(0.0, 0.0, 18.0)
			_stone.position = Vector3(0.0, 0.0, 6.0)
			_warden.position = Vector3(0.0, 0.0, -10.0)
		else:
			_king.position = Vector3(-17.0, 0.0, 0.0)
			_stone.position = Vector3(-6.0, 0.0, 0.0)
			_warden.position = Vector3(9.0, 0.0, 0.0)
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
		# every figure whole, the camera level at half their height (no foreshortening: the heights read true)
		_cam.size = 27.0
		var look := Vector3(0.0, 12.6, 0.0)
		_cam.global_position = look + dir * 120.0
		_cam.look_at(look, Vector3.UP)
	else:
		var look := Vector3(0.0, WARDEN_H * 0.5, 0.0)
		var dist := WARDEN_H * 1.9
		if shot.has("focus"):
			var f := str(shot.focus)
			look = _warden.piece_centre(f) if _warden.piece(f) != null else _warden.bone_position(f)
			look += Vector3(0.0, float(shot.get("lift", 0.0)), 0.0)
			dir = shot.get("dir", dir)
			dist = float(shot.get("dist", 6.0))
		elif view == "clip":
			var pel := _warden.bone_position("pelvis")
			look = Vector3(pel.x, WARDEN_H * 0.45, pel.z)
			dist = WARDEN_H * 2.2
		_cam.global_position = look + dir.normalized() * dist
		_cam.look_at(look, Vector3.UP)
	for i in 3:
		await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := out_dir.path_join("%s.png" % str(shot.name))
	if img.save_png(path) == OK:
		_written.append(path)
