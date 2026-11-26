extends Node
## D1: stills of the Frostbound Titan as the asset pipeline made him (FrostboundModel, his clips; no actor), one PNG a
## shot at 1280 x 720 in a studio's cold light: the turnaround (front, side, back, three-quarter; close on the head, the
## crest, the fist, the heart), the scale line-up (a man, a house, stage-6, -7 and -8 giants, the Broken Warden and him:
## orthographic, so the heights are honest), his clips' keys, a plate fractured and broken. The evidence for
## docs/systems/D1.md and the look's own check.
##
##   LP_NUM_THREADS=2 xvfb-run -a -s "-screen 0 1280x720x24" tools/gd.sh --path . --rendering-driver opengl3 \
##     --resolution 1280x720 --audio-driver Dummy res://tools/frostbound_stills.tscn -- --out=<dir> [--shots=a,b,...]
##
## Prints FROSTBOUND_STILLS {"shots": [paths], "ms"} and quits (a watchdog quits it after WATCHDOG_S).

const SIZE := Vector2i(1280, 720)
const WATCHDOG_S := 900.0
const PREFIX := "FROSTBOUND_STILLS "
const GIANT_MODEL_SCENE := "res://scenes/player/giant_model.tscn"
const STAGE6_H := 18.8976
const STAGE7_H := 23.7744
const STAGE8_H := 29.2608
const TITAN_H := 28.0
const MAN_H := 1.8
const HOUSE := Vector3(9.0, 4.5, 7.0)

var out_dir := ""
var only: PackedStringArray = []
var _titan: FrostboundModel
var _warden: BastionModel
var _giants: Array[GiantModel] = []
var _man: Node3D
var _house: Node3D
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
		out_dir = ProjectSettings.globalize_path("user://frostbound_stills")
	DirAccess.make_dir_recursive_absolute(out_dir)
	_make_stage()
	await get_tree().process_frame
	_run.call_deferred()


## The shots: {name, clip, t (s), view, ortho, lineup (the scale line-up), hidden (plates broken off), cracks {plate:
## amount}, focus (a bone or a piece), dir, dist, lift}.
static func shots() -> Array:
	var out: Array = []
	for v: String in ["front", "side", "back"]:
		out.append({"name": "turn_%s" % v, "view": v, "ortho": true, "solo": true})
	out.append({"name": "turn_three_quarter", "view": "three_quarter"})
	out.append({"name": "turn_back_quarter", "view": "back_quarter"})
	out.append({"name": "lineup_front", "view": "front", "ortho": true, "lineup": true})
	out.append({"name": "lineup_side", "view": "side", "ortho": true, "lineup": true})
	out.append({"name": "close_head", "focus": "head", "dir": Vector3(0.35, 0.10, 1.0), "dist": 9.0, "lift": 0.3})
	out.append({"name": "close_head_side", "focus": "head", "dir": Vector3(-1.0, 0.1, 0.25), "dist": 9.0, "lift": 0.3})
	out.append({"name": "close_crest", "focus": "serac", "dir": Vector3(-0.6, 0.35, -1.0), "dist": 16.0, "lift": 3.0})
	out.append({"name": "close_fist", "focus": "gauntlet", "dir": Vector3(-0.9, 0.2, 0.6), "dist": 12.0})
	out.append({"name": "close_heart", "focus": "heart", "dir": Vector3(0.2, 0.1, 1.0), "dist": 9.0})
	out.append({"name": "close_pauldron", "focus": "pauldron_l", "dir": Vector3(0.8, 0.35, 0.6), "dist": 9.0})
	out.append({"name": "close_greaves", "focus": "greave_r", "dir": Vector3(-0.4, 0.15, 1.0), "dist": 10.0})
	out.append({"name": "plate_cracked", "focus": "heart", "dir": Vector3(0.2, 0.1, 1.0), "dist": 9.0,
		"cracks": {"heart": FrostboundModel.BADLY_CRACKED}})
	out.append({"name": "plate_broken", "focus": "heart", "dir": Vector3(0.2, 0.1, 1.0), "dist": 9.0,
		"hidden": ["heart"]})
	out.append({"name": "dormant", "clip": "dormant", "t": 0.0, "view": "three_quarter"})
	for c: Array in [["walk", 0.0], ["walk", 0.5], ["run", 0.3], ["wake", 1.4], ["wake", 2.7], ["rake", 0.62],
			["rake", 1.05], ["rake", 1.35], ["fist", 1.15], ["fist", 1.55], ["breath", 1.25], ["breath", 1.9],
			["stamp", 0.5], ["stamp", 0.78], ["sweep", 0.85], ["sweep", 1.2], ["sweep", 1.6], ["roar2", 0.7],
			["roar2", 1.5], ["hurl", 0.95], ["hurl", 1.45], ["hurl", 1.9], ["nova", 1.1], ["nova", 1.7],
			["nova", 2.2], ["reel", 0.85], ["kneel", 0.8], ["rise", 0.6], ["death", 1.4], ["death", 3.6]]:
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
	_sun.directional_shadow_max_distance = 140.0
	add_child(_sun)
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(400, 400)
	ground.mesh = plane
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.47, 0.46, 0.44)
	gm.roughness = 0.95
	ground.material_override = gm
	add_child(ground)
	_titan = FrostboundModel.new()
	_titan.name = "Frostbound"
	add_child(_titan)
	_warden = BastionModel.new()
	_warden.name = "BrokenWarden"
	add_child(_warden)
	_warden.visible = false
	for h: float in [STAGE6_H, STAGE7_H, STAGE8_H]:
		var g := (load(GIANT_MODEL_SCENE) as PackedScene).instantiate() as GiantModel
		add_child(g)
		GiantLook.build_materials(g, g.index, "auto")
		g.apply_defaults()
		g.pose_relaxed()
		g.scale = Vector3.ONE * (h / GiantPreview.STAGE1_HEIGHT_M)
		g.rotation.y = PI
		g.visible = false
		_giants.append(g)
	_man = _make_man()
	add_child(_man)
	_house = _make_house()
	add_child(_house)
	_cam = Camera3D.new()
	_cam.fov = 38.0
	_cam.near = 0.1
	_cam.far = 900.0
	add_child(_cam)
	_cam.current = true


## A man (1.8 m): a plain figure for scale (the people's models are posed under their actors).
func _make_man() -> Node3D:
	var n := Node3D.new()
	n.name = "Man"
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.32, 0.26, 0.20)
	for spec: Array in [[Vector3(0.0, 0.45, 0.0), Vector3(0.36, 0.9, 0.24)], [Vector3(0.0, 1.22, 0.0),
			Vector3(0.46, 0.64, 0.26)], [Vector3(0.0, 1.66, 0.0), Vector3(0.22, 0.26, 0.24)]]:
		var mi := MeshInstance3D.new()
		var b := BoxMesh.new()
		b.size = spec[1]
		mi.mesh = b
		mi.position = spec[0]
		mi.material_override = mat
		n.add_child(mi)
	n.visible = false
	return n


## A cottage: stone walls and a pitched thatch roof, 8 m to the ridge.
func _make_house() -> Node3D:
	var n := Node3D.new()
	n.name = "House"
	var wall := StandardMaterial3D.new()
	wall.albedo_color = Color(0.62, 0.58, 0.52)
	var roof := StandardMaterial3D.new()
	roof.albedo_color = Color(0.45, 0.36, 0.22)
	var w := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = HOUSE
	w.mesh = b
	w.position = Vector3(0.0, HOUSE.y * 0.5, 0.0)
	w.material_override = wall
	n.add_child(w)
	var r := MeshInstance3D.new()
	var p := PrismMesh.new()
	p.size = Vector3(HOUSE.x + 1.0, 3.5, HOUSE.z + 1.0)
	r.mesh = p
	r.position = Vector3(0.0, HOUSE.y + 1.75, 0.0)
	r.material_override = roof
	n.add_child(r)
	n.visible = false
	return n


func _render(shot: Dictionary) -> void:
	var clip := str(shot.get("clip", "idle"))
	_titan.pose(clip, float(shot.get("t", 0.0)))
	_titan.set_plates(true)
	for n: String in FrostboundModel.PLATES:
		_titan.set_plate_crack(n, float((shot.get("cracks", {}) as Dictionary).get(n, 0.0)))
	for n: Variant in shot.get("hidden", []):
		_titan.set_plate_visible(str(n), false)
	var lineup := bool(shot.get("lineup", false))
	var view := str(shot.get("view", "close"))
	for g in _giants:
		g.visible = lineup
	_warden.visible = lineup
	_man.visible = lineup
	_house.visible = lineup
	_titan.position = Vector3.ZERO
	_titan.rotation.y = 0.0
	if lineup:
		_warden.pose("idle", 0.0)
		_warden.rotation.y = 0.0
		var side := view == "side"
		# left to right (front view): the man, the house, the stage-6, -7 and -8 giants, the Broken Warden, him
		var xs := [-52.0, -45.0, -33.0, -19.0, -3.0, 13.0, 31.0]
		var nodes: Array[Node3D] = [_man, _house, _giants[0], _giants[1], _giants[2], _warden, _titan]
		for i in nodes.size():
			nodes[i].position = Vector3(0.0, 0.0, -xs[i]) if side else Vector3(xs[i], 0.0, 0.0)
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
		# every figure whole, the camera level at about half their height (no foreshortening: the heights read true)
		_cam.size = 34.0 if lineup else 32.0
		var look := Vector3(0.0, 15.5, 0.0)
		if lineup and view != "side":
			_cam.size = 50.0
			look = Vector3(-10.0, 17.0, 0.0)
		elif lineup:
			_cam.size = 50.0
			look = Vector3(0.0, 17.0, 10.0)
		_cam.global_position = look + dir * 140.0
		_cam.look_at(look, Vector3.UP)
	else:
		var look := Vector3(0.0, TITAN_H * 0.5, 0.0)
		var dist := TITAN_H * 1.9
		if shot.has("focus"):
			var f := str(shot.focus)
			look = _titan.piece_centre(f) if _titan.piece(f) != null else _titan.bone_position(f)
			look += Vector3(0.0, float(shot.get("lift", 0.0)), 0.0)
			dir = shot.get("dir", dir)
			dist = float(shot.get("dist", 6.0))
		elif view == "clip":
			var pel := _titan.bone_position("pelvis")
			look = Vector3(pel.x, TITAN_H * 0.45, pel.z)
			dist = TITAN_H * 2.3
		_cam.global_position = look + dir.normalized() * dist
		_cam.look_at(look, Vector3.UP)
	for i in 3:
		await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := out_dir.path_join("%s.png" % str(shot.name))
	if img.save_png(path) == OK:
		_written.append(path)
