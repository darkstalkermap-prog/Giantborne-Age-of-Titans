extends Node
## D3: the size line-up of the growth track's nine stages (12 to 116 ft) beside a man, a cottage and milestone D's two
## titans (the Frostbound, 92 ft; the Stormcaller, 111.5 ft), orthographic so the heights read true, front and side, at
## 1280 x 720 in a studio's grey light; and the stage-9 giant alone, close on the head and the hands (hair, beard,
## the skin's texture at its scale). The evidence for docs/systems/D3.md.
##
##   LP_NUM_THREADS=2 xvfb-run -a -s "-screen 0 1280x720x24" tools/gd.sh --path . --rendering-driver opengl3 \
##     --resolution 1280x720 --audio-driver Dummy res://tools/d3_stills.tscn -- --out=<dir> [--shots=a,b,...]
##
## Prints D3_STILLS {"shots": [paths], "ms"} and quits (a watchdog quits it after WATCHDOG_S).

const WATCHDOG_S := 900.0
const PREFIX := "D3_STILLS "
const GIANT_MODEL_SCENE := "res://scenes/player/giant_model.tscn"
const MAN_H := 1.8
const HOUSE := Vector3(9.0, 4.5, 7.0)

var out_dir := ""
var only: PackedStringArray = []
var _giants: Array[GiantModel] = []
var _heights: Array[float] = []
var _frost: FrostboundModel
var _storm: StormcallerModel
var _man: Node3D
var _house: Node3D
var _cam: Camera3D
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
		out_dir = ProjectSettings.globalize_path("user://d3_stills")
	DirAccess.make_dir_recursive_absolute(out_dir)
	_make_stage()
	await get_tree().process_frame
	_run.call_deferred()


static func shots() -> Array:
	return [{"name": "lineup_front", "view": "front"}, {"name": "lineup_side", "view": "side"},
		{"name": "stage9_head", "view": "head"}, {"name": "stage9_hands", "view": "hands"}]


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
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.56, 0.57, 0.58)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.66, 0.66, 0.68)
	env.ambient_light_energy = 0.6
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-42, 28, 0)
	sun.light_energy = 1.2
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 200.0
	add_child(sun)
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(600, 600)
	ground.mesh = plane
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.47, 0.46, 0.44)
	gm.roughness = 0.95
	ground.material_override = gm
	add_child(ground)
	for rec: Dictionary in GameData.records_of_type("growth_profile"):
		_heights.append(float(rec.height_m))
	_heights.sort()
	for h: float in _heights:
		var g := (load(GIANT_MODEL_SCENE) as PackedScene).instantiate() as GiantModel
		add_child(g)
		GiantLook.build_materials(g, g.index, "auto")
		g.apply_defaults()
		g.pose_relaxed()
		g.scale = Vector3.ONE * (h / GiantPreview.STAGE1_HEIGHT_M)
		g.rotation.y = PI
		_giants.append(g)
	_frost = FrostboundModel.new()
	add_child(_frost)
	_storm = StormcallerModel.new()
	add_child(_storm)
	_man = _box_figure(Color(0.32, 0.26, 0.20))
	add_child(_man)
	_house = _cottage()
	add_child(_house)
	_cam = Camera3D.new()
	_cam.near = 0.1
	_cam.far = 1200.0
	add_child(_cam)
	_cam.current = true


func _box_figure(c: Color) -> Node3D:
	var n := Node3D.new()
	var mat := StandardMaterial3D.new()
	mat.albedo_color = c
	for spec: Array in [[Vector3(0.0, 0.45, 0.0), Vector3(0.36, 0.9, 0.24)], [Vector3(0.0, 1.22, 0.0),
			Vector3(0.46, 0.64, 0.26)], [Vector3(0.0, 1.66, 0.0), Vector3(0.22, 0.26, 0.24)]]:
		var mi := MeshInstance3D.new()
		var b := BoxMesh.new()
		b.size = spec[1]
		mi.mesh = b
		mi.position = spec[0]
		mi.material_override = mat
		n.add_child(mi)
	return n


func _cottage() -> Node3D:
	var n := Node3D.new()
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
	return n


func _render(shot: Dictionary) -> void:
	var view := str(shot.view)
	_frost.pose("idle", 0.0)
	_storm.pose("idle", 0.0)
	var lineup := view == "front" or view == "side"
	for g in _giants:
		g.visible = lineup
	_giants[_giants.size() - 1].visible = true
	_frost.visible = lineup
	_storm.visible = lineup
	_man.visible = lineup
	_house.visible = lineup
	if lineup:
		# left to right: the man, the cottage, stages 1-9 each a body's width apart, the Frostbound, the Stormcaller
		var x := -150.0
		var order: Array[Node3D] = [_man, _house]
		var widths: Array[float] = [3.0, 12.0]
		for i in _giants.size():
			order.append(_giants[i])
			widths.append(maxf(3.0, _heights[i] * 0.5))
		order.append(_frost)
		widths.append(26.0)
		order.append(_storm)
		widths.append(30.0)
		for i in order.size():
			x += widths[i] * 0.5
			order[i].position = Vector3(0.0, 0.0, -x) if view == "side" else Vector3(x, 0.0, 0.0)
			x += widths[i] * 0.5 + 2.0
		var mid := (-150.0 + x) * 0.5
		_cam.projection = Camera3D.PROJECTION_ORTHOGONAL
		_cam.size = 64.0
		var look := Vector3(mid, 26.0, 0.0) if view != "side" else Vector3(0.0, 26.0, -mid)
		var dir := Vector3(0.0, 0.0, 1.0) if view != "side" else Vector3(1.0, 0.0, 0.0)
		_cam.size = 2.0 * maxf(36.0, (x + 150.0) * 0.5 * 720.0 / 1280.0 + 4.0)
		_cam.global_position = look + dir * 300.0
		_cam.look_at(look, Vector3.UP)
	else:
		var g := _giants[_giants.size() - 1]
		g.position = Vector3.ZERO
		var h := _heights[_heights.size() - 1]
		_cam.projection = Camera3D.PROJECTION_PERSPECTIVE
		_cam.fov = 40.0
		var look := Vector3(0.0, h * (0.92 if view == "head" else 0.5), 0.0)
		var dir := Vector3(0.35, 0.05, 1.0).normalized() if view == "head" else Vector3(0.9, 0.1, 0.6).normalized()
		_cam.global_position = look + dir * (h * (0.32 if view == "head" else 0.55))
		_cam.look_at(look, Vector3.UP)
	for i in 3:
		await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := out_dir.path_join("%s.png" % str(shot.name))
	if img.save_png(path) == OK:
		_written.append(path)
