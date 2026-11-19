extends Node
## The build sliders, rendered (P53; plan M11 §2.4, §3.6, decision 7): tests/slow/test_build_render.gd runs this
## scene (tests/support/build_render_probe.tscn) in a child Godot under Xvfb with the Compatibility renderer:
##
##   LP_NUM_THREADS=2 xvfb-run -a -s "-screen 0 1280x720x24" godot --path . --rendering-driver opengl3 \
##     --resolution 320x240 --audio-driver Dummy res://tests/support/build_render_probe.tscn -- --giant-tier=web
##
## The real model (scenes/player/giant_model.tscn) in the Wanderer's look and the warrior's (a tunic and a jerkin
## over the chest), seen from behind at the stage-1 rear Game view's height, at build (0, 0), (1, 1) and (-1, -1),
## each against a plain background (the silhouette: pixels off the clear colour) and once more over a lit ground
## (the shadow: ground pixels darker than the ground's own lit colour). The skeleton's bone poses and the
## index's landmarks are read before and after every build (the push is in the vertex shaders: no joint moves).
## Frames go to user://m11_frames/P53/. Prints one line
##   BUILD_RENDER {"frames": {name: {"lit": share, "shadow": share, "path": ...}}, "changed": {name: share},
##                 "bones_moved_m": max, "proxy_material": bool, "validate": [...], "adapter": ...}
## and quits.

const MODEL := "res://scenes/player/giant_model.tscn"
const OUT_DIR := "user://m11_frames/P53/"
const CLEAR := Color(0.18, 0.2, 0.24)
const GROUND := Color(0.62, 0.6, 0.55)
const BUILDS := {"zero": Vector2.ZERO, "plus": Vector2(1.0, 1.0), "minus": Vector2(-1.0, -1.0)}
const WATCHDOG_S := 150.0

var _root3d: Node3D
var _cam: Camera3D
var _model: Node3D
var _ground: MeshInstance3D
var _index: Dictionary = {}


func _ready() -> void:
	get_tree().create_timer(WATCHDOG_S).timeout.connect(func() -> void:
		print("BUILD_RENDER {\"error\": \"the probe timed out\"}")
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
	sun.rotation_degrees = Vector3(-55, 20, 0)   # high and behind him: his shadow falls toward the camera's side
	sun.light_energy = 1.4
	sun.shadow_enabled = true
	_root3d.add_child(sun)
	_cam = Camera3D.new()
	_cam.fov = 40.0
	_root3d.add_child(_cam)
	_cam.current = true
	_ground = MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(14, 14)
	_ground.mesh = plane
	var gm := StandardMaterial3D.new()
	gm.albedo_color = GROUND
	gm.roughness = 1.0
	_ground.material_override = gm
	_ground.visible = false
	_root3d.add_child(_ground)
	if not ResourceLoader.exists(MODEL):
		print("BUILD_RENDER {\"error\": \"no %s\"}" % MODEL)
		get_tree().quit(2)
		return
	_model = (load(MODEL) as PackedScene).instantiate() as Node3D
	_index = _model.get("index") if typeof(_model.get("index")) == TYPE_DICTIONARY else {}
	_root3d.add_child(_model)
	GiantLook.build_materials(_model, _index, "web")
	get_tree().process_frame.connect(_run, CONNECT_ONE_SHOT)


func _run() -> void:
	var out := {"frames": {}, "changed": {}, "bones_moved_m": 0.0, "landmarks_same": true,
		"adapter": RenderingServer.get_video_adapter_name(), "validate": [], "proxy_material": false,
		"build_max_m": float(_index.get("build_max_m", 0.0))}
	var sk: Skeleton3D = _model.call("skeleton") if _model.has_method("skeleton") else null
	var rest := _bones(sk)
	var landmarks: Variant = (_model.call("landmarks") as Dictionary).duplicate(true) if _model.has_method("landmarks") else {}
	# the rear Game view at stage 1: behind him (+Z; he faces -Z) and a little above the shoulders
	_cam.look_at_from_position(Vector3(0.0, 3.4, 8.2), Vector3(0.0, 1.9, 0.0), Vector3.UP)
	var images := {}
	for look_name: String in ["wanderer", "warrior"]:
		var rec := Appearance.default_record() if look_name == "wanderer" \
			else Appearance.with_outfit(Appearance.default_record(), "outfit.warrior")
		for b: String in BUILDS:
			var r := rec.duplicate(true)
			r.build = {"brawn": (BUILDS[b] as Vector2).x, "girth": (BUILDS[b] as Vector2).y}
			var look := Appearance.to_look(r, "")
			GiantLook.apply(_model, _index, look)
			out.validate.append_array(Array(GiantLook.validate(_model, _index, look)))
			_ground.visible = false
			var key := "%s_%s" % [look_name, b]
			var shot := await _capture("build_" + key)
			images[key] = shot.image
			out.frames[key] = shot.info
			_ground.visible = true
			var lit := await _capture("build_%s_ground" % key)
			out.frames[key]["shadow"] = _shadow_share(lit.image)
			_ground.visible = false
			out.bones_moved_m = maxf(float(out.bones_moved_m), _moved(rest, _bones(sk)))
			if _model.has_method("landmarks") and str(_model.call("landmarks")) != str(landmarks):
				out.landmarks_same = false
			if b != "zero":
				var proxy: MeshInstance3D = _model.call("shadow_proxy") if _model.has_method("shadow_proxy") else null
				out.proxy_material = proxy != null and proxy.material_override is ShaderMaterial \
					and Vector2(proxy.material_override.get_shader_parameter("build")) == BUILDS[b]
	for look_name: String in ["wanderer", "warrior"]:
		for b: String in ["plus", "minus"]:
			out.changed["%s_%s" % [look_name, b]] = _diff(images["%s_zero" % look_name], images["%s_%s" % [look_name, b]])
	print("BUILD_RENDER " + JSON.stringify(out))
	get_tree().quit(0)


## Every bone's global pose origin (model space).
static func _bones(sk: Skeleton3D) -> Array:
	var out: Array = []
	if sk == null:
		return out
	for i in sk.get_bone_count():
		out.append(sk.get_bone_global_pose(i).origin)
	return out


static func _moved(a: Array, b: Array) -> float:
	var worst := 0.0 if a.size() == b.size() else 1.0e9
	for i in mini(a.size(), b.size()):
		worst = maxf(worst, (a[i] as Vector3).distance_to(b[i]))
	return worst


## Two drawn frames, the second saved and counted against the clear colour.
func _capture(frame_name: String) -> Dictionary:
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := OUT_DIR + frame_name + ".png"
	img.save_png(path)
	var lit := 0
	var total := 0
	for y in img.get_height():
		for x in img.get_width():
			total += 1
			if _off_clear(img.get_pixel(x, y)):
				lit += 1
	return {"image": img, "info": {"lit": float(lit) / maxf(1.0, float(total)), "path": ProjectSettings.globalize_path(path)}}


static func _off_clear(p: Color) -> bool:
	return absf(p.r - CLEAR.r) + absf(p.g - CLEAR.g) + absf(p.b - CLEAR.b) > 0.06


## The share of pixels that differ between two frames of one size (by more than a channel's noise).
static func _diff(a: Image, b: Image) -> float:
	var n := 0
	var total := 0
	for y in a.get_height():
		for x in a.get_width():
			total += 1
			var p := a.get_pixel(x, y)
			var q := b.get_pixel(x, y)
			if absf(p.r - q.r) + absf(p.g - q.g) + absf(p.b - q.b) > 0.06:
				n += 1
	return float(n) / maxf(1.0, float(total))


## The share of the frame that is ground in shadow: grey pixels well darker than the lit ground, below the
## giant's feet line (the lower third of the frame).
static func _shadow_share(img: Image) -> float:
	var n := 0
	var total := 0
	for y in range(img.get_height() * 2 / 3, img.get_height()):
		for x in img.get_width():
			total += 1
			var p := img.get_pixel(x, y)
			var grey := absf(p.r - p.g) < 0.05 and absf(p.g - p.b) < 0.07
			if grey and p.get_luminance() < 0.32 and _off_clear(p):
				n += 1
	return float(n) / maxf(1.0, float(total))
