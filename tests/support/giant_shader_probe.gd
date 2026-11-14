extends Node
## The giant's shaders, rendered (P42; plan M10 §1.7 rule 6, §2.8, §2.13): tests/slow/test_giant_shaders.gd
## runs this scene (tests/support/giant_shader_probe.tscn: a main scene, so the autoloads GameData and the
## rest exist - a `-s` script runs without them, and Appearance reads GameData) in a child Godot under Xvfb
## with the Compatibility renderer (the headless runner draws nothing):
##
##   LP_NUM_THREADS=2 xvfb-run -a -s "-screen 0 1280x720x24" godot --path . --rendering-driver opengl3 \
##     --resolution 320x240 --audio-driver Dummy res://tests/support/giant_shader_probe.tscn -- --giant-tier=web
##
## It draws one frame per material category - skin, hair,
## eye, cloth - on the real model when scenes/player/giant_model.tscn exists (GiantLook.build_materials and
## apply, the default look), else on a stand-in: spheres and a card named like the index's meshes, with small
## generated maps. Each frame is saved to user://m10_frames/ and counted against the clear colour; on the real
## model the long hair and the full beard are also framed as the creator's Face and Hair views (§4.2's hair
## bar), and the cost of a frame of the whole giant at 320x240 is measured (P43 sets its caps from it). The frames
## are drawn by the normal loop, two per capture, and the probe quits right after (a watchdog quits it on a
## script error). Prints
## one line
##   GIANT_SHADERS {"model": bool, "frames": {kind: {"lit": fraction of pixels off the clear colour,
##                  "path": ...}}, "frame_ms": ..., "render_cpu_ms": ..., "render_gpu_ms": ...,
##                  "validate": [...], "adapter": ..., "tier": ...}
## and quits.

const MODEL := "res://scenes/player/giant_model.tscn"
const OUT_DIR := "user://m10_frames/"
const CLEAR := Color(0.18, 0.2, 0.24)
const KINDS := ["skin", "hair", "eye", "cloth"]
const TIMED_FRAMES := 12

## The stand-in's index (the plan's format; GiantLook reads nothing else).
const STAND_IN := {
	"meshes": {
		"Body_Torso": {"node": "Body_Torso", "category": "body", "layer": 1, "dye": "none", "covers": []},
		"Eyes": {"node": "Eyes", "category": "eyes", "layer": 3, "dye": "none", "covers": []},
		"Hair_long_back": {"node": "Hair_long_back", "category": "hair", "layer": 3, "dye": "none", "covers": []},
		"Beard_full": {"node": "Beard_full", "category": "beard", "layer": 3, "dye": "none", "covers": []},
		"Garment_braies": {"node": "Garment_braies", "category": "garment", "layer": 1, "dye": "primary",
			"covers": [11, 12]},
		"Garment_belt": {"node": "Garment_belt", "category": "garment", "layer": 1, "dye": "secondary", "covers": []},
	},
	"garments": {"braies": ["Garment_braies"], "belt": ["Garment_belt"]},
	"designs": {"tat_arm_bands": {"layer": 0, "channel": 0, "kind": "tattoo", "regions": [3]},
		"mark_granite_veins": {"layer": 1, "channel": 0, "kind": "mark", "regions": [3, 4]}},
	"tiers": {"web": "res://tests/fixtures/giant/tex/", "hi": "res://tests/fixtures/giant/tex_hi/"},
}

var _root3d: Node3D
var _cam: Camera3D
var _model: Node3D
var _index: Dictionary = {}
var _real := false


## The probe never outlives this (a script error must not leave the child running).
const WATCHDOG_S := 120.0


func _ready() -> void:
	get_tree().create_timer(WATCHDOG_S).timeout.connect(func() -> void:
		print("GIANT_SHADERS {\"error\": \"the probe timed out\"}")
		get_tree().quit(3))
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	RenderingServer.set_default_clear_color(CLEAR)
	_root3d = Node3D.new()
	add_child(_root3d)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = CLEAR
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.55, 0.58, 0.62)
	env.environment.ambient_light_energy = 0.6
	_root3d.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-35, 150, 0)
	sun.light_energy = 1.4
	_root3d.add_child(sun)
	_cam = Camera3D.new()
	_cam.fov = 40.0
	_root3d.add_child(_cam)
	_cam.current = true
	_real = ResourceLoader.exists(MODEL)
	if _real:
		_model = (load(MODEL) as PackedScene).instantiate() as Node3D
		_index = _model.get("index") if typeof(_model.get("index")) == TYPE_DICTIONARY else {}
		_root3d.add_child(_model)
	else:
		_model = _stand_in()
		_index = STAND_IN.duplicate(true)
		_root3d.add_child(_model)
	GiantLook.build_materials(_model, _index, "auto")
	GiantLook.apply(_model, _index, Appearance.to_look(Appearance.default_record(), "ancestry.stoneblood"))
	if not _real:
		_fill_stand_in_maps()
	get_tree().process_frame.connect(_run, CONNECT_ONE_SHOT)


func _run() -> void:
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)
	var out := {"model": _real, "frames": {}, "tier": GiantLook.built_tier(_model),
		"adapter": RenderingServer.get_video_adapter_name(),
		"validate": Array(GiantLook.validate(_model, _index, GiantLook.applied_look(_model)))}
	for kind: String in KINDS:
		_show_only(kind)
		_frame_on(kind)
		out.frames[kind] = await _capture("shader_%s" % kind)
	_show_all()
	if _real:
		var lm: Dictionary = _index.get("landmarks", {})
		var eye: Vector3 = _v3(lm.get("eye_mid", [0.0, 3.45, -0.24]))
		_look_from(eye + Vector3(0.0, 0.05, -1.3), eye)                 # the creator's Face framing
		out.frames["face_long_hair_full_beard"] = await _capture("hair_face")
		_look_from(eye + Vector3(1.0, 0.25, 1.1), eye + Vector3(0, -0.1, 0))   # the Hair framing, from behind
		out.frames["hair_back"] = await _capture("hair_back")
	_frame_whole()
	var cost: Dictionary = await _timed()
	out.merge(cost)
	print("GIANT_SHADERS " + JSON.stringify(out))
	get_tree().quit(0)


# --------------------------------------------------------------------------- the stand-in

func _stand_in() -> Node3D:
	var root := Node3D.new()
	root.name = "StandInGiant"
	var body := MeshInstance3D.new()
	body.name = "Body_Torso"
	var sphere := SphereMesh.new()
	sphere.radius = 0.5
	sphere.height = 1.0
	body.mesh = sphere
	body.position = Vector3(-0.6, 0.6, 0)
	root.add_child(body)
	var eyes := MeshInstance3D.new()
	eyes.name = "Eyes"
	var eye_mesh := SphereMesh.new()
	eye_mesh.radius = 0.25
	eye_mesh.height = 0.5
	eyes.mesh = eye_mesh
	eyes.position = Vector3(0.6, 0.6, 0)
	root.add_child(eyes)
	var hair := MeshInstance3D.new()
	hair.name = "Hair_long_back"
	var quad := QuadMesh.new()
	quad.size = Vector2(0.8, 1.0)
	hair.mesh = quad
	hair.position = Vector3(-0.6, 0.6, 0.2)
	root.add_child(hair)
	var beard := MeshInstance3D.new()
	beard.name = "Beard_full"
	var beard_quad := QuadMesh.new()
	beard_quad.size = Vector2(0.5, 0.4)
	beard.mesh = beard_quad
	beard.position = Vector3(-0.6, 0.35, 0.55)
	root.add_child(beard)
	var belt := MeshInstance3D.new()
	belt.name = "Garment_belt"
	var belt_box := BoxMesh.new()
	belt_box.size = Vector3(0.85, 0.12, 0.65)
	belt.mesh = belt_box
	belt.position = Vector3(0.6, 0.95, 0)
	root.add_child(belt)
	var cloth := MeshInstance3D.new()
	cloth.name = "Garment_braies"
	var box := BoxMesh.new()
	box.size = Vector3(0.8, 0.6, 0.6)
	cloth.mesh = box
	cloth.position = Vector3(0.6, 0.6, 0)
	root.add_child(cloth)
	return root


## Small generated maps on the stand-in's materials (the real model's come from its tiers).
func _fill_stand_in_maps() -> void:
	var solid := func(c: Color, fmt: int = Image.FORMAT_RGBA8) -> ImageTexture:
		var img := Image.create(8, 8, false, fmt)
		img.fill(c)
		return ImageTexture.create_from_image(img)
	var design := Image.create(8, 8, false, Image.FORMAT_RGBA8)
	design.fill(Color(0, 0, 0, 0))
	var arr := Texture2DArray.new()
	arr.create_from_images([design])
	var atlas := Image.create(8, 8, false, Image.FORMAT_RGBA8)
	for y in 8:
		for x in 8:
			atlas.set_pixel(x, y, Color(1, 1, 1, 1.0 if x % 2 == 0 else 0.0))
	for mat in GiantLook.materials(_model):
		if mat.shader == GiantLook.SKIN_SHADER:
			mat.set_shader_parameter("albedo_tex", solid.call(GiantLook.BAKE_TONE))
			mat.set_shader_parameter("normal_tex", solid.call(Color(0.5, 0.5, 1.0)))
			mat.set_shader_parameter("orm_tex", solid.call(Color(1.0, 0.6, 0.3)))
			mat.set_shader_parameter("mask_tex", solid.call(Color(0, 0, 0, 0)))
			mat.set_shader_parameter("design_tex", arr)
		elif mat.shader == GiantLook.HAIR_SHADER:
			mat.set_shader_parameter("hair_atlas", ImageTexture.create_from_image(atlas))
		elif mat.shader == GiantLook.CLOTH_SHADER:
			mat.set_shader_parameter("detail_tex", solid.call(Color(0.5, 0.5, 1.0, 0.75)))   # a flat normal, the dye


# --------------------------------------------------------------------------- framing and capture

func _show_only(kind: String) -> void:
	var meshes: Dictionary = _index.get("meshes", {})
	for id: Variant in meshes:
		var mi := GiantLook.mesh_node(_model, _index, str(id))
		if mi != null:
			mi.set_meta("p42_was_visible", mi.get_meta("p42_was_visible", mi.visible))
			mi.visible = GiantLook.shader_kind(str((meshes[id] as Dictionary).get("category", ""))) == kind \
				and bool(mi.get_meta("p42_was_visible"))


func _show_all() -> void:
	for id: Variant in _index.get("meshes", {}):
		var mi := GiantLook.mesh_node(_model, _index, str(id))
		if mi != null and mi.has_meta("p42_was_visible"):
			mi.visible = bool(mi.get_meta("p42_was_visible"))


## Frames the visible meshes of `kind` (their combined bounds).
func _frame_on(_kind: String) -> void:
	var box := AABB()
	var first := true
	for id: Variant in _index.get("meshes", {}):
		var mi := GiantLook.mesh_node(_model, _index, str(id))
		if mi == null or not mi.is_visible_in_tree() or mi.mesh == null:
			continue
		var b := mi.global_transform * mi.get_aabb()
		box = b if first else box.merge(b)
		first = false
	if first:
		box = AABB(Vector3(-0.5, 0, -0.5), Vector3(1, 3.6, 1))
	var c := box.get_center()
	var r := maxf(box.size.length() * 0.5, 0.2)
	var front := -1.0 if _real else 1.0   # the model faces -Z (the index's game frame); the stand-in is seen from +Z
	_look_from(c + Vector3(0.0, 0.15 * r, front * r * 2.6), c)


func _frame_whole() -> void:
	_show_all()
	var box := AABB(Vector3(-1, 0, -1), Vector3(2, 3.7, 2)) if _real else AABB(Vector3(-1.2, 0, -0.5), Vector3(2.4, 1.2, 1))
	var c := box.get_center()
	_look_from(c + Vector3(0.0, 0.2, (-1.0 if _real else 1.0) * box.size.length() * 1.3), c)


func _look_from(from: Vector3, at: Vector3) -> void:
	_cam.look_at_from_position(from, at, Vector3.UP)


static func _v3(v: Variant) -> Vector3:
	if typeof(v) == TYPE_VECTOR3:
		return v
	if typeof(v) == TYPE_ARRAY and (v as Array).size() == 3:
		return Vector3(float(v[0]), float(v[1]), float(v[2]))
	return Vector3.ZERO


## Waits for two drawn frames, saves the second and counts its pixels off the clear colour.
func _capture(frame_name: String) -> Dictionary:
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := OUT_DIR + frame_name + ".png"
	img.save_png(path)
	var lit := 0
	var total := 0
	for y in range(0, img.get_height(), 2):
		for x in range(0, img.get_width(), 2):
			total += 1
			var p := img.get_pixel(x, y)
			if absf(p.r - CLEAR.r) + absf(p.g - CLEAR.g) + absf(p.b - CLEAR.b) > 0.06:
				lit += 1
	return {"lit": float(lit) / maxf(1.0, float(total)), "path": ProjectSettings.globalize_path(path),
		"size": [img.get_width(), img.get_height()]}


## The cost of a frame of the whole giant at this size: the viewport's measured render time (CPU and GPU,
## ms, the mean over TIMED_FRAMES frames after two to settle) and the wall time between drawn frames.
func _timed() -> Dictionary:
	var rid := get_viewport().get_viewport_rid()
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var cpu := 0.0
	var gpu := 0.0
	var t0 := Time.get_ticks_usec()
	for i in TIMED_FRAMES:
		await RenderingServer.frame_post_draw
		cpu += RenderingServer.viewport_get_measured_render_time_cpu(rid)
		gpu += RenderingServer.viewport_get_measured_render_time_gpu(rid)
	return {"frame_ms": float(Time.get_ticks_usec() - t0) / 1000.0 / float(TIMED_FRAMES),
		"render_cpu_ms": cpu / float(TIMED_FRAMES), "render_gpu_ms": gpu / float(TIMED_FRAMES)}
