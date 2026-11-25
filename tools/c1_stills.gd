extends Node
## C1: the colossi's scale sheet - the giant at stages 6, 7 and 8 side by side on a neutral studio floor with a man
## (one of the people: a soldier's 1.8 m), a town house (the world's house kind, 9 x 5.5 x 8 m) and Stoneback and the
## Rootwarden, orthographic (the heights as they are), front and side; then the stage-8 giant in each armour set (the
## realistic giant is scaled whole in play: proportions, hair and cloth as at stage 1) and close-ups of his head and
## hands at stage 8 (the texture's detail where the camera is when it is far). One PNG a shot at 1280 x 720.
##
##   LP_NUM_THREADS=2 xvfb-run -a -s "-screen 0 1280x720x24" tools/gd.sh --path . --rendering-driver opengl3 \
##     --resolution 1280x720 --audio-driver Dummy res://tools/c1_stills.tscn -- --out=<dir> [--shots=a,b,...]
##
## Prints C1_STILLS {"shots": [paths], "ms"} and quits (a watchdog quits it after WATCHDOG_S).

const WATCHDOG_S := 900.0
const PREFIX := "C1_STILLS "
const GIANT_MODEL_SCENE := "res://scenes/player/giant_model.tscn"
const STAGES := [6, 7, 8]
const HOUSE := {"kind": "house", "style": "cottage", "size": [9, 5.5, 8]}

var out_dir := ""
var only: PackedStringArray = []
var _giants: Array[GiantModel] = []
var _stone: StonebackRig
var _warden: RootwardenModel
var _person: PersonModel
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
		out_dir = ProjectSettings.globalize_path("user://c1_stills")
	DirAccess.make_dir_recursive_absolute(out_dir)
	_make_stage()
	await get_tree().process_frame
	_run.call_deferred()


static func _height(stage: int) -> float:
	for rec: Dictionary in GameData.records_of_type("growth_profile"):
		if int(rec.get("stage", 0)) == stage:
			return float(rec.height_m)
	return 3.6576


func _make_stage() -> void:
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.56, 0.57, 0.58)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.66, 0.66, 0.68)
	env.ambient_light_energy = 0.42
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-42, 28, 0)
	sun.light_energy = 0.85
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 200.0
	add_child(sun)
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(400, 400)
	ground.mesh = plane
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.33, 0.32, 0.31)
	gm.roughness = 0.95
	ground.material_override = gm
	add_child(ground)
	for st: int in STAGES:
		var g := (load(GIANT_MODEL_SCENE) as PackedScene).instantiate() as GiantModel
		add_child(g)
		GiantLook.build_materials(g, g.index, "auto")
		g.apply_defaults()
		g.pose_relaxed()
		g.scale = Vector3.ONE * (_height(st) / GiantPreview.STAGE1_HEIGHT_M)
		g.rotation.y = PI
		_giants.append(g)
	_stone = StonebackRig.new()
	add_child(_stone)
	_stone.pose("idle", 0.0)
	_warden = RootwardenModel.new()
	add_child(_warden)
	_warden.pose("idle", 0.0)
	_warden.set_plates(true)
	_person = PersonModel.acquire("villager", "")
	if _person != null:
		if _person.get_parent() != null:
			_person.get_parent().remove_child(_person)
		add_child(_person)
		var anim := StringName(String(PersonModel.LIBRARY) + "/idle")
		if _person.player() != null and _person.player().has_animation(anim):
			_person.player().play(anim)
	var ctx := {"field": HeightField.make(Vector2(-50, -50), 4.0, Vector2i(26, 26)), "frame": Transform3D.IDENTITY}
	_house = WorldLayout.kind_build(null, HOUSE, ctx)
	if _house != null:
		add_child(_house)
	_cam = Camera3D.new()
	_cam.near = 0.1
	_cam.far = 1200.0
	add_child(_cam)
	_cam.current = true


## Lays the line-up along x (front view) or z (side view): a man, a house, Stoneback, the Rootwarden, the giant at
## stages 6, 7 and 8.
func _line_up(side: bool) -> void:
	var xs := [-52.0, -44.0, -31.0, -14.0, 5.0, 25.0, 48.0]
	var items: Array = [_person, _house, _stone, _warden, _giants[0], _giants[1], _giants[2]]
	for i in items.size():
		var n: Node3D = items[i]
		if n == null:
			continue
		n.visible = true
		n.position = Vector3(0.0, 0.0, -xs[i]) if side else Vector3(xs[i], 0.0, 0.0)


func shots() -> Array:
	return [
		{"name": "c1_scale_front", "lineup": true, "dir": Vector3(0, 0, 1), "ortho": 62.0, "look_y": 25.0},
		{"name": "c1_scale_side", "lineup": true, "side": true, "dir": Vector3(1, 0, 0), "ortho": 62.0, "look_y": 25.0},
		{"name": "c1_scale_three_quarter", "lineup": true, "dir": Vector3(0.6, 0.25, 0.8), "fov": 40.0, "dist": 150.0, "look_y": 13.0},
		{"name": "c1_stage8_armour_iron", "armour": "armour_set.iron", "stage8": true},
		{"name": "c1_stage8_armour_quarry", "armour": "armour_set.quarry", "stage8": true},
		{"name": "c1_stage8_armour_warden", "armour": "armour_set.warden", "stage8": true},
		{"name": "c1_stage8_armour_kingsfall", "armour": "armour_set.kingsfall", "stage8": true},
		{"name": "c1_stage8_armour_hide", "armour": "armour_set.hide", "stage8": true},
		{"name": "c1_stage8_head", "stage8": true, "focus": 0.92, "dist": 9.0},
		{"name": "c1_stage8_hands", "stage8": true, "focus": 0.5, "dist": 12.0},
	]


func _run() -> void:
	var t0 := Time.get_ticks_msec()
	for shot: Dictionary in shots():
		if not only.is_empty() and not str(shot.name) in only:
			continue
		await _render(shot)
	print(PREFIX + JSON.stringify({"shots": Array(_written), "ms": Time.get_ticks_msec() - t0}))
	get_tree().quit(0)


func _render(shot: Dictionary) -> void:
	var look := Vector3(0.0, float(shot.get("look_y", 12.0)), 0.0)
	var dir: Vector3 = shot.get("dir", Vector3(0.3, 0.15, 1.0))
	if bool(shot.get("lineup", false)):
		_line_up(bool(shot.get("side", false)))
	else:
		for n: Node3D in [_person, _house, _stone, _warden, _giants[0], _giants[1]]:
			if n != null:
				n.visible = false
		var g := _giants[2]
		g.position = Vector3.ZERO
		g.visible = true
		var rec := Appearance.default_record()
		var eq := Armour.empty()
		var set_id := str(shot.get("armour", ""))
		if set_id != "" and Armour.set_ids().has(set_id):
			eq = Armour.equipment_with(Armour.set_pieces(set_id))
		GiantLook.apply(g, g.index, Armour.look_of(rec, eq, ""))
		var h := _height(8)
		look = Vector3(0.0, h * float(shot.get("focus", 0.5)), 0.0)
		dir = Vector3(0.35, 0.1, 1.0)
		if shot.has("focus"):
			dir = Vector3(0.5, 0.05, 1.0)
	_cam.projection = Camera3D.PROJECTION_ORTHOGONAL if shot.has("ortho") else Camera3D.PROJECTION_PERSPECTIVE
	if shot.has("ortho"):
		_cam.size = float(shot.ortho)
		_cam.global_position = look + dir.normalized() * 300.0
	else:
		_cam.fov = float(shot.get("fov", 36.0))
		var dist := float(shot.get("dist", _height(8) * 2.2))
		_cam.global_position = look + dir.normalized() * dist
	_cam.look_at(look, Vector3.UP)
	for i in 4:
		await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := out_dir.path_join("%s.png" % str(shot.name))
	if img.save_png(path) == OK:
		_written.append(path)
