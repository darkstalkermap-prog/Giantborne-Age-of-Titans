extends Node
## P48 (plan M11 §3.1 tests, §1.7 rule 4): the giant's parts, the shadow proxy and the leaf chains, rendered.
## tests/slow/test_giant_parts_render.gd runs this scene in a child Godot under Xvfb with the Compatibility
## renderer (the headless runner draws nothing):
##
##   LP_NUM_THREADS=2 xvfb-run -a -s "-screen 0 1280x720x24" godot --path . --rendering-driver opengl3 \
##     --resolution 320x240 --audio-driver Dummy res://tests/support/giant_parts_probe.tscn -- [--review]
##
## It instances scenes/player/giant_model.tscn with GiantLook's materials over a ground plane under one
## shadowed sun and reports, in one line `GIANT_PARTS {...}`:
##   parts     {mesh id: pixels that change when the part alone is shown, the body hidden}: every part
##             loads, binds and draws
##   chain     pixels that change when a long style's chain bones are bent (the cards follow their chains)
##             and when the cape's are
##   shadow    the pixels the sun's shadows darken with the proxy, without it (none: no other mesh
##             casts) and with the cape shown and no proxy (the free cape casts its own); with --review
##             also as M10 drew them (every mesh its own caster) and how many pixels of the lit body
##             differ between the proxy's shadows and M10's
##   mesh_mb   the renderer's buffer memory the giant adds: the body alone (with the eyes and the proxy),
##             the default look, the fullest look, and with every part loaded (what M10 kept resident)
##   load_ms   a part's first load (read, bind, the first frame that draws it)
## With --review it also saves, under user://m11_frames/P48/, the cape and the long styles from the side and
## behind and one frame of every new clip (side and front): the frames a reviewer looks at; the test never
## asks for them.

const MODEL := "res://scenes/player/giant_model.tscn"
const OUT_DIR := "user://m11_frames/P48/"
const CLEAR := Color(0.18, 0.2, 0.24)
const WATCHDOG_S := 150.0
const BODY := ["Body_Head", "Body_Torso", "Body_Limbs", "Eyes"]
const DEFAULT_PARTS := ["Hair_long_back", "Beard_full", "Garment_braies_core", "Garment_braies_limbs", "Garment_belt"]
const FULLEST := ["tunic", "jerkin", "belt", "bracers", "boots"]
const REVIEW_CLIPS := {"sprint": [0.0, 0.25, 0.5, 0.75], "turn_l": [0.25, 0.5, 0.75], "turn_r": [0.5],
	"stomp_r": [0.34, 0.6, 0.72, 0.9], "land": [0.3], "brace": [0.0], "roar": [0.5],
	"flinch_f": [0.3], "flinch_b": [0.3], "flinch_l": [0.3], "flinch_r": [0.3], "carry_two_hand": [0.0],
	"fp_rest": [0.0], "grip_club": [0.0], "grip_tree": [0.0], "grip_fist": [0.0]}

var _model: GiantModel
var _cam: Camera3D
var _sun: DirectionalLight3D
var _review := false


func _ready() -> void:
	get_tree().create_timer(WATCHDOG_S).timeout.connect(func() -> void:
		print("GIANT_PARTS {\"error\": \"the probe timed out\"}")
		get_tree().quit(3))
	_review = OS.get_cmdline_user_args().has("--review")
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	RenderingServer.set_default_clear_color(CLEAR)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = CLEAR
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.55, 0.58, 0.62)
	env.environment.ambient_light_energy = 0.6
	add_child(env)
	_sun = DirectionalLight3D.new()
	_sun.rotation_degrees = Vector3(-48, 150, 0)
	_sun.light_energy = 1.4
	_sun.shadow_enabled = false             # on for the shadow frames only (a shadowed frame costs four times one without)
	_sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	_sun.directional_shadow_max_distance = 40.0
	add_child(_sun)
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(40, 40)
	ground.mesh = plane
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.82, 0.82, 0.8)
	ground.material_override = mat
	add_child(ground)
	_cam = Camera3D.new()
	_cam.fov = 40.0
	add_child(_cam)
	_cam.current = true
	get_tree().process_frame.connect(_run, CONNECT_ONE_SHOT)


func _run() -> void:
	var out := {"adapter": RenderingServer.get_video_adapter_name(), "parts": {}, "chain": {}, "shadow": {},
		"mesh_mb": {}, "load_ms": {}}
	await _frames(2)
	var empty_mb := _buffer_mb()            # the ground and the renderer's own buffers, before the giant
	_model = (load(MODEL) as PackedScene).instantiate() as GiantModel
	add_child(_model)
	GiantLook.build_materials(_model, _model.index, "web")
	var idx: Dictionary = _model.index
	var parts: Array = []
	for id: String in idx.meshes:
		if _model.is_part(id):
			parts.append(id)
	parts.sort()
	# ---- memory: the body alone, the default look, the fullest look, everything (M10's resident set)
	# (giant.glb is preloaded with GiantModel's script, so the body's own buffers are counted from its
	# surfaces: GiantModel.mesh_bytes; the renderer's figure is what a look's parts add to them)
	_show([])
	_view(Vector3(0, 2.0, -8.5), Vector3(0, 1.9, 0))
	GiantModel.clear_recent_parts()
	var base := await _shot("")
	var core_mb := float(_model.resident_bytes()) / 1048576.0
	var none_mb := _buffer_mb()
	out.mesh_mb["body"] = core_mb
	out.mesh_mb["instance_overhead"] = none_mb - empty_mb
	_show(DEFAULT_PARTS)          # a mesh's buffers are made when it loads: no frame to wait for
	out.mesh_mb["default"] = core_mb + _buffer_mb() - none_mb
	out.mesh_mb["default_counted"] = float(_model.resident_bytes()) / 1048576.0
	var full: Array = ["Hair_wild_mane", "Beard_full"]
	for g: String in FULLEST:
		full.append_array(idx.garments[g])
	_show(full)
	GiantModel.clear_recent_parts()
	out.mesh_mb["fullest"] = core_mb + _buffer_mb() - none_mb
	out.mesh_mb["fullest_counted"] = float(_model.resident_bytes()) / 1048576.0
	out.mesh_mb["fullest_parts"] = full.size()
	for id: String in parts:
		_model.ensure_part(id)
	out.mesh_mb["all_loaded"] = core_mb + _buffer_mb() - none_mb
	_model.release_unused(full)
	GiantModel.clear_recent_parts()
	# ---- every part draws: alone, the body hidden (a frame of the whole giant costs most of the probe's
	# time), against the empty scene
	for id: String in BODY:
		_model.mesh(id).visible = false
	_show([])
	base = await _shot("")
	for id: String in parts:
		_show([id])
		await RenderingServer.frame_post_draw
		out.parts[id] = _diff(base, get_viewport().get_texture().get_image())
	for id: String in BODY:
		_model.mesh(id).visible = true
	# ---- a part's first load
	GiantModel.clear_recent_parts()
	_show([])
	await _frames(2)
	for id: String in ["Hair_long_braided"]:
		var t0 := Time.get_ticks_usec()
		_model.mesh(id).visible = true
		var read_ms := (Time.get_ticks_usec() - t0) / 1000.0
		await RenderingServer.frame_post_draw
		out.load_ms[id] = {"read_bind": read_ms, "to_first_frame": (Time.get_ticks_usec() - t0) / 1000.0}
	# ---- the chains: the cards and the cape follow their bones
	var sk := _model.skeleton()
	_view(Vector3(7.5, 2.9, 0.6), Vector3(0, 2.7, 0.2))
	_show(["Hair_long_braided", "Beard_forked", "Garment_cape"])
	var rest := await _shot("chains_rest" if _review else "")
	for bone: String in ["hair_01", "hair_02", "hair_03", "hair_l_01", "hair_r_01", "beard_01", "beard_02"]:
		_bend(sk, bone, Vector3.RIGHT, -22.0)
	var bent := await _shot("chains_hair_bent" if _review else "")
	out.chain["hair_and_beard"] = _diff(rest, bent)
	sk.reset_bone_poses()
	for bone: String in ["cape_c_01", "cape_l_01", "cape_r_01", "cape_c_02", "cape_l_02", "cape_r_02"]:
		_bend(sk, bone, Vector3.RIGHT, -20.0)
	bent = await _shot("chains_cape_bent" if _review else "")
	out.chain["cape"] = _diff(rest, bent)
	sk.reset_bone_poses()
	# ---- shadows: the proxy casts the giant's; nothing else does, but the free cape. A shadow is what
	# the sun's shadow switch darkens on the ground.
	_view(Vector3(0, 9.0, -9.0), Vector3(0, 0.4, 1.2))
	_show(DEFAULT_PARTS)
	var proxy := _model.shadow_proxy()
	var with_proxy := await _shadow_px("shadow_proxy" if _review else "")
	proxy.visible = false
	var without := await _shadow_px("")
	_show(DEFAULT_PARTS + ["Garment_cape"])
	var cape_only := await _shadow_px("")
	out.shadow = {"proxy": with_proxy, "none": without, "cape_alone": cape_only,
		"proxy_tris": int(proxy.mesh.surface_get_array_index_len(0)) / 3}
	if _review:
		# as M10 drew it: every shown mesh casting its own shadow, no proxy; and the lit body, near, with
		# M10's shadows and with the proxy's (the proxy must shade the skin it sits in no more than the skin
		# shaded itself)
		_show(DEFAULT_PARTS)
		var casters: Array = DEFAULT_PARTS + ["Body_Head", "Body_Torso", "Body_Limbs"]
		for id: String in casters:
			_model.mesh(id).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		out.shadow["as_m10"] = await _shadow_px("shadow_m10")
		_sun.shadow_enabled = true
		_view(Vector3(-3.0, 2.6, -7.5), Vector3(0, 2.0, 0))
		var lit_m10 := await _shot("body_m10_shadows")
		for id: String in casters:
			_model.mesh(id).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		proxy.visible = true
		var lit_proxy := await _shot("body_proxy_shadows")
		_model.visible = false
		var no_giant := await _shot("")
		_model.visible = true
		out.shadow["body_px"] = _diff(lit_proxy, no_giant)
		out.shadow["body_differs_from_m10_px"] = _diff(lit_proxy, lit_m10)
	proxy.visible = true
	out["validate"] = Array(GiantLook.validate(_model, idx, GiantLook.applied_look(_model)))
	if _review:
		await _review_frames()
	print("GIANT_PARTS " + JSON.stringify(out))
	get_tree().quit(0)


# --------------------------------------------------------------------------- helpers

func _show(ids: Array) -> void:
	for id: String in _model.index.meshes:
		if _model.is_part(id):
			_model.mesh(id).visible = ids.has(id)


func _view(from: Vector3, at: Vector3) -> void:
	_cam.global_position = from
	_cam.look_at(at, Vector3.UP)


func _frames(n: int) -> void:
	for i in n:
		await RenderingServer.frame_post_draw


func _shot(save_as: String) -> Image:
	await _frames(2 if _review else 1)
	var img := get_viewport().get_texture().get_image()
	if save_as != "":
		img.save_png(OUT_DIR + save_as + ".png")
	return img


static func _diff(a: Image, b: Image) -> int:
	return _diff_above(a, b, a.get_height())


static func _diff_above(a: Image, b: Image, rows: int) -> int:
	var n := 0
	for y in mini(rows, a.get_height()):
		for x in a.get_width():
			var ca := a.get_pixel(x, y)
			var cb := b.get_pixel(x, y)
			if absf(ca.r - cb.r) + absf(ca.g - cb.g) + absf(ca.b - cb.b) > 0.08:
				n += 1
	return n


## The pixels the sun's shadows darken in the current view (the same frame with the shadows off and on).
func _shadow_px(save_as: String) -> int:
	_sun.shadow_enabled = false
	var lit := await _shot("")
	_sun.shadow_enabled = true
	var shaded := await _shot(save_as)
	_sun.shadow_enabled = false
	var n := 0
	for y in lit.get_height():
		for x in lit.get_width():
			if shaded.get_pixel(x, y).get_luminance() < lit.get_pixel(x, y).get_luminance() - 0.1:
				n += 1
	return n


static func _buffer_mb() -> float:
	return float(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_BUFFER_MEM_USED)) / 1048576.0


## Turns a bone from its rest by `deg` about `axis` in the skeleton's space.
static func _bend(sk: Skeleton3D, bone: String, axis: Vector3, deg: float) -> void:
	var b := sk.find_bone(bone)
	if b < 0:
		return
	var parent := sk.get_bone_parent(b)
	var pb := sk.get_bone_global_rest(parent).basis if parent >= 0 else Basis.IDENTITY
	var local := pb.inverse() * Basis(axis, deg_to_rad(deg)) * pb * sk.get_bone_rest(b).basis
	sk.set_bone_pose_rotation(b, local.get_rotation_quaternion())


## --review: the frames of docs/systems/P48.md.
func _review_frames() -> void:
	_sun.shadow_enabled = true
	var sk := _model.skeleton()
	sk.reset_bone_poses()
	_show(DEFAULT_PARTS + ["Garment_cape"])
	_view(Vector3(7.0, 2.6, 2.0), Vector3(0, 2.2, 0.2))
	await _shot("cape_side")
	_view(Vector3(1.5, 2.8, 7.0), Vector3(0, 2.3, 0))
	await _shot("cape_back")
	_view(Vector3(-2.0, 3.0, -5.5), Vector3(0, 2.9, 0))
	await _shot("cape_collar_front")
	var lib := SkinnedRig.clip_library()
	if lib == null:
		return
	var player := AnimationPlayer.new()
	_model.add_child(player)
	player.root_node = player.get_path_to(sk.get_parent().get_parent())
	player.add_animation_library(SkinnedRig.LIBRARY, lib)
	_show(DEFAULT_PARTS)
	for clip: String in REVIEW_CLIPS:
		if not lib.has_animation(clip):
			continue
		var length := lib.get_animation(clip).length
		for frac: float in REVIEW_CLIPS[clip]:
			sk.reset_bone_poses()
			if clip.begins_with("grip_") or clip in ["carry_two_hand", "fp_rest"] or clip.begins_with("flinch"):
				player.play(String(SkinnedRig.LIBRARY) + "/idle")
				player.seek(0.0, true)
			player.play(String(SkinnedRig.LIBRARY) + "/" + clip)
			player.seek(frac * length, true)
			player.pause()
			var tag := "%s_%02d" % [clip, int(round(frac * 100.0))]
			if clip.begins_with("grip_"):
				var hand := _model.hand_transform(true).origin
				_view(hand + Vector3(0.9, 0.5, -0.9), hand)
				await _shot("clip_%s_hand" % tag)
				continue
			_view(Vector3(8.5, 2.2, 0.0), Vector3(0, 1.9, 0))
			await _shot("clip_%s_side" % tag)
			_view(Vector3(0.0, 2.2, -8.5), Vector3(0, 1.9, 0))
			await _shot("clip_%s_front" % tag)
	player.queue_free()
