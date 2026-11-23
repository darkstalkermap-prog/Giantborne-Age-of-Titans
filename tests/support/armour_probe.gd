extends Node
## B1: the functional armour, rendered. tests/gate/test_armour_render.gd runs this scene in a child Godot under Xvfb with
## the Compatibility renderer (the headless runner draws nothing):
##
##   LP_NUM_THREADS=2 xvfb-run -a -s "-screen 0 1280x720x24" godot --path . --rendering-driver opengl3 \
##     --resolution 400x400 --audio-driver Dummy res://tests/support/armour_probe.tscn
##
## It instances the giant's model (scenes/player/giant_model.tscn) with GiantLook's materials, scaled to stages 1, 5
## and 6 (the model is scaled whole in play), the camera framing him from his front-left at the same share of the frame,
## and for every armour piece, in three poses (the idle, a walk's stride, the stomp's raised arms and knee), reports in
## one line `ARMOUR_PROBE {...}`:
##   pieces {piece id: {stage: {pose: [shown, alone, meshes]}}} - the piece's own meshes glow magenta (the shaders'
##          `flash`): `shown` counts its magenta pixels over the default look (it draws), `alone` with the body, the
##          hair and the look's clothes hidden (all of it). shown / alone is the share of the piece the body does not
##          cover: a piece sunk into the body (clipping) scores low
##   hidden {piece id: its magenta pixels with its slot hidden (0: nothing of it drawn)}

const MODEL := "res://scenes/player/giant_model.tscn"
const CLEAR := Color(0.18, 0.2, 0.24)
const WATCHDOG_S := 300.0
const BODY := ["Body_Head", "Body_Torso", "Body_Limbs", "Eyes"]
const STAGES := [1, 5, 6]
const POSES := {"idle": ["idle", 0.5], "walk": ["walk", 0.3], "stomp": ["stomp_r", 0.45]}

var _model: GiantModel
var _cam: Camera3D
var _player: AnimationPlayer


func _ready() -> void:
	get_tree().create_timer(WATCHDOG_S).timeout.connect(func() -> void:
		print("ARMOUR_PROBE {\"error\": \"the probe timed out\"}")
		get_tree().quit(3))
	RenderingServer.set_default_clear_color(CLEAR)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = CLEAR
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.55, 0.58, 0.62)
	env.environment.ambient_light_energy = 0.7
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48, 150, 0)
	add_child(sun)
	_cam = Camera3D.new()
	_cam.fov = 30.0
	add_child(_cam)
	_cam.make_current()
	_model = (load(MODEL) as PackedScene).instantiate() as GiantModel
	add_child(_model)
	GiantLook.build_materials(_model, _model.index, "web")
	var sk := _model.skeleton()
	_player = AnimationPlayer.new()
	_model.add_child(_player)
	_player.root_node = _player.get_path_to(sk.get_parent().get_parent())
	_player.add_animation_library(SkinnedRig.LIBRARY, SkinnedRig.clip_library())
	await get_tree().process_frame
	_run.call_deferred()


func _run() -> void:
	var out := {"pieces": {}, "hidden": {}, "adapter": RenderingServer.get_video_adapter_name()}
	var rec := Appearance.default_record()
	var ids: Array = []
	for sid: String in Armour.set_ids():
		ids.append_array(Armour.set_pieces(sid))
	for id: Variant in ids:
		out.pieces[str(id)] = {}
	# every piece's parts loaded once before anything is measured (a part's first frame may not draw it whole)
	for id: Variant in ids:
		_apply(rec, Armour.equipment_with([str(id)]), true)
		await _shot()
	for stage: int in STAGES:
		var k := GiantPreview.stage_scale(GiantPreview.stage_profile(stage))
		_model.scale = Vector3.ONE * k
		_aim(k)
		for pose: String in POSES:
			_pose(str(POSES[pose][0]), float(POSES[pose][1]))
			for id: Variant in ids:
				var eq := Armour.equipment_with([str(id)])
				_apply(rec, eq, true)
				var marked := _mark(rec, eq, true)
				var shown := _magenta(await _shot())
				_apply(rec, eq, false)
				_mark(rec, eq, true)
				var alone := _magenta(await _shot())
				_mark(rec, eq, false)
				if not (out.pieces[str(id)] as Dictionary).has(str(stage)):
					out.pieces[str(id)][str(stage)] = {}
				out.pieces[str(id)][str(stage)][pose] = [shown, alone, marked]
	# hidden: nothing of it drawn (the look's own clothes there instead)
	_model.scale = Vector3.ONE
	_aim(1.0)
	_pose("idle", 0.5)
	for id: Variant in ids:
		var eq := Armour.equipment_with([str(id)], [str(Armour.piece(str(id)).slot)])
		_apply(rec, eq, true)
		var marked := _mark(rec, Armour.equipment_with([str(id)]), true)
		out.hidden[str(id)] = _magenta(await _shot())
		_mark(rec, Armour.equipment_with([str(id)]), false)
	print("ARMOUR_PROBE " + JSON.stringify(out))
	get_tree().quit(0)


## The piece's own meshes glow magenta (the shaders' `flash`, an emission) or stop; returns how many it marked.
func _mark(rec: Dictionary, eq: Dictionary, on: bool) -> int:
	var n := 0
	for id: String in _own(rec, eq):
		var mi := _model.mesh(id)
		if mi == null:
			continue
		var mat := mi.material_override as ShaderMaterial
		if mat == null:
			continue
		mat.set_shader_parameter("flash", Vector3(3.0, 0.0, 3.0) if on else Vector3.ZERO)
		n += 1
	return n


## The meshes the piece adds to the default look: its wardrobe garments and its modelled stone.
func _own(rec: Dictionary, eq: Dictionary) -> Dictionary:
	var own := {}
	var mine := GiantLook.garment_meshes(_model.index, Armour.look_of(rec, eq, ""))
	var plain := GiantLook.garment_meshes(_model.index, Armour.look_of(rec, Armour.empty(), ""))
	for m: Variant in mine:
		if not plain.has(m) or (mine[m] as Dictionary).get("dye") != (plain[m] as Dictionary).get("dye"):
			own[str(m)] = true
	for m: Variant in Armour.look_meshes(eq):
		own[str(m)] = true
	return own


static func _magenta(img: Image) -> int:
	var d := img.get_data()
	var step := 4 if img.get_format() == Image.FORMAT_RGBA8 else 3
	var n := 0
	var i := 0
	while i + 2 < d.size():
		if d[i] > 200 and d[i + 2] > 200 and d[i + 1] < 140:
			n += 1
		i += step
	return n


func _apply(rec: Dictionary, eq: Dictionary, body: bool) -> void:
	var look := Armour.look_of(rec, eq, "")
	GiantLook.apply(_model, _model.index, look)
	if body:
		return
	# the piece alone: the body, the hair and every garment of the default look hidden; the piece's own kept
	var own := _own(rec, eq)
	for id: String in _model.index.meshes:
		var mi := _model.mesh(id)
		if mi != null and mi.visible and not own.has(id):
			mi.visible = false


func _pose(clip: String, t: float) -> void:
	_player.play(String(SkinnedRig.LIBRARY) + "/" + clip)
	_player.seek(t, true)
	_player.pause()


func _aim(k: float) -> void:
	var target := Vector3(0.0, 1.9 * k, 0.0)
	var dir := Vector3(-0.55, 0.12, -1.0).normalized()
	_cam.position = target + dir * 8.6 * k
	_cam.look_at(target, Vector3.UP)
	_cam.near = 0.05 * k
	_cam.far = 60.0 * k


func _shot() -> Image:
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	return get_viewport().get_texture().get_image()


