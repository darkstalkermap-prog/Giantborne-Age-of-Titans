extends Node
## E3: stills of the Hollow Titan (HollowModel: his harness on the Stormcaller's skeleton, his clips and the
## Stormcaller's; no actor), one PNG a shot at 1280 x 720 in a cold grey studio light: the turnaround (front, side, back,
## three-quarter; close on the helm and its crown, the breastplate, the oath-knot bare, a pauldron, the Kingsword's hilt,
## the greaves and sabatons), the scale line-up (a man, a house, a stage-9 giant, the Cinder Titan and him: orthographic,
## so the heights are honest), his clips' keys, a plate split and plates torn off (the empty inside), his echo. The
## evidence for docs/systems/E3.md and the look's own check.
##
##   LP_NUM_THREADS=2 xvfb-run -a -s "-screen 0 1280x720x24" tools/gd.sh --path . --rendering-driver opengl3 \
##     --resolution 1280x720 --audio-driver Dummy res://tools/e3_stills.tscn -- --out=<dir> [--shots=a,b,...]
##
## Prints E3_STILLS {"shots": [paths], "ms"} and quits (a watchdog quits it after WATCHDOG_S).

const SIZE := Vector2i(1280, 720)
const WATCHDOG_S := 900.0
const PREFIX := "E3_STILLS "
const GIANT_MODEL_SCENE := "res://scenes/player/giant_model.tscn"
const STAGE9_H := 35.3568
const TITAN_H := 39.6
const HOUSE := Vector3(9.0, 4.5, 7.0)

var out_dir := ""
var only: PackedStringArray = []
var _titan: HollowModel
var _cinder: CinderModel
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
		out_dir = ProjectSettings.globalize_path("user://hollow_stills")
	DirAccess.make_dir_recursive_absolute(out_dir)
	_make_stage()
	await get_tree().process_frame
	_run.call_deferred()


## The shots: {name, clip, t (s), view, ortho, lineup (the scale line-up), hidden (plates torn off), cracks {plate:
## amount}, focus (a bone or a piece), dir, dist, lift, bare (the knot bare), resonance}.
static func shots() -> Array:
	var out: Array = []
	for v: String in ["front", "side", "back"]:
		out.append({"name": "turn_%s" % v, "view": v, "ortho": true, "solo": true})
	out.append({"name": "turn_three_quarter", "view": "three_quarter"})
	out.append({"name": "turn_back_quarter", "view": "back_quarter"})
	out.append({"name": "lineup_front", "view": "front", "ortho": true, "lineup": true})
	out.append({"name": "close_helm", "focus": "head", "dir": Vector3(0.35, 0.05, 1.0), "dist": 16.0, "lift": 1.0})
	out.append({"name": "close_helm_side", "focus": "head", "dir": Vector3(-1.0, 0.15, 0.3), "dist": 16.0, "lift": 1.0})
	out.append({"name": "close_breast", "focus": "cuirass", "dir": Vector3(0.25, 0.1, 1.0), "dist": 19.0})
	out.append({"name": "close_knot_bare", "focus": "knot", "dir": Vector3(0.25, 0.08, 1.0), "dist": 17.0,
		"hidden": ["cuirass"], "bare": true})
	out.append({"name": "close_pauldron", "focus": "pauldron_l", "dir": Vector3(1.0, 0.3, 0.6), "dist": 15.0})
	out.append({"name": "close_hilt", "focus": "hand_r", "dir": Vector3(-0.5, 0.1, 1.0), "dist": 16.0})
	out.append({"name": "close_legs", "focus": "calf_r", "dir": Vector3(-0.35, 0.1, 1.0), "dist": 22.0})
	out.append({"name": "close_feet", "focus": "foot_r", "dir": Vector3(0.6, 0.35, 1.0), "dist": 14.0})
	out.append({"name": "plate_cracked", "focus": "cuirass", "dir": Vector3(0.3, 0.1, 1.0), "dist": 19.0,
		"cracks": {"cuirass": StormcallerModel.BADLY_CRACKED, "pauldron_l": StormcallerModel.CRACKED}})
	out.append({"name": "plates_torn", "view": "three_quarter", "hidden": ["helm", "pauldron_l", "cuirass", "greave_r"],
		"bare": true})
	out.append({"name": "plates_torn_close", "focus": "head", "dir": Vector3(0.6, 0.2, 1.0), "dist": 22.0, "lift": -3.0,
		"hidden": ["helm", "pauldron_l", "cuirass"], "bare": true})
	out.append({"name": "echo_full", "view": "three_quarter", "resonance": 1.0})
	for c: Array in [["idle", 0.0], ["dormant", 0.0], ["walk", 0.0], ["walk", 0.5], ["wake", 0.9], ["wake", 1.9],
			["wake", 2.8], ["slam", 1.2], ["slam", 1.65], ["sweep", 0.9], ["sweep", 1.25], ["chain", 1.1], ["chain", 1.5],
			["call", 1.2], ["roar2", 1.45], ["draw", 0.6], ["draw", 1.45], ["draw", 1.9], ["embrace", 0.6], ["embrace", 0.95],
			["echo", 1.4], ["echo", 1.65], ["reel", 0.85], ["kneel", 0.8], ["death", 0.9], ["death", 2.9]]:
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
	_env.background_color = Color(0.42, 0.44, 0.47)
	_env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	_env.ambient_light_color = Color(0.62, 0.6, 0.6)
	_env.ambient_light_energy = 0.45
	_env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	we.environment = _env
	add_child(we)
	_sun = DirectionalLight3D.new()
	_sun.rotation_degrees = Vector3(-42, 28, 0)
	_sun.light_energy = 0.9
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
	_titan = HollowModel.new()
	_titan.name = "Hollow"
	add_child(_titan)
	_titan.scale = Vector3.ONE * HollowModel.SCALE
	_cinder = CinderModel.new()
	_cinder.name = "Cinder"
	add_child(_cinder)
	_cinder.scale = Vector3.ONE * CinderModel.SCALE
	_cinder.visible = false
	for h: float in [STAGE9_H]:
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
	_titan.set_resonance(float(shot.get("resonance", 0.0)))
	_titan.set_knot_bare(bool(shot.get("bare", false)))
	for n: String in _titan.plate_names():
		_titan.set_plate_crack(n, float((shot.get("cracks", {}) as Dictionary).get(n, 0.0)))
	for n: Variant in shot.get("hidden", []):
		_titan.set_plate_visible(str(n), false)
	var lineup := bool(shot.get("lineup", false))
	var view := str(shot.get("view", "close"))
	for g in _giants:
		g.visible = lineup
	_cinder.visible = lineup
	_man.visible = lineup
	_house.visible = lineup
	_titan.position = Vector3.ZERO
	_titan.rotation.y = 0.0
	if lineup:
		_cinder.pose("idle", 0.0)
		_cinder.rotation.y = 0.0
		# left to right (front view): the man, the house, the stage-9 giant, the Cinder Titan, him
		var xs := [-52.0, -44.0, -26.0, 0.0, 30.0]
		var nodes: Array[Node3D] = [_man, _house, _giants[0], _cinder, _titan]
		for i in nodes.size():
			nodes[i].position = Vector3(xs[i], 0.0, 0.0)
	if lineup:
		for i in 4:
			_cinder.update_fire(0.05)
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
		_cam.size = 56.0
		var look := Vector3(0.0, 25.0, 0.0)
		# (the line-up about 100 m wide - the man at -50 m to his brand beyond +38 m - and 50 m high)
		if lineup:
			_cam.size = 58.0
			look = Vector3(-6.0, 26.0, 0.0)
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
