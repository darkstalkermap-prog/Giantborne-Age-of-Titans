extends Node
## Scene generator for the low-poly prototype (giant, soldier, dummy, fence, arena, main).
##
##   godot --headless --path . res://tools/build_scenes.tscn
##
## (Runs as a scene, not with -s, so autoload names resolve when gameplay scripts compile.)
## Writes Godot-serialized .tscn/.tres files, so they open and edit normally in the editor.
## The generated scenes are the source of truth afterwards: re-running this tool OVERWRITES
## manual edits to those files. Gameplay numbers live in data/*.json, not here.

const MAT_DIR := "res://assets/materials"
const S_GIANT := "res://scripts/actors/giant_player.gd"
const S_SOLDIER := "res://scripts/actors/soldier_enemy.gd"
const S_DUMMY := "res://scripts/actors/practice_dummy.gd"
const S_FENCE := "res://scripts/world/breakable_prop.gd"
const S_ARENA := "res://scripts/world/sandbox_arena.gd"
const S_DEBRIS := "res://scripts/world/debris_pool.gd"
const S_ENTITY := "res://scripts/combat/combat_entity.gd"
const S_HURTBOX := "res://scripts/combat/hurtbox.gd"
const S_RIG := "res://scripts/presentation/actor_rig.gd"
const S_CAMERA := "res://scripts/presentation/camera_rig.gd"
const S_MAIN := "res://scripts/main.gd"

const L_WORLD := 1
const L_ACTORS := 2
const L_HURTBOX := 4
const L_BREAKABLE := 16
const FP_HIDDEN := 2   ## render layer value for geometry hidden in first person

var mats: Dictionary = {}


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(MAT_DIR)
	_make_materials()
	_save(_build_giant(), "res://scenes/player/giant.tscn")
	_save(_build_soldier(), "res://scenes/enemies/soldier.tscn")
	_save(_build_dummy(), "res://scenes/world/practice_dummy.tscn")
	_save(_build_fence(), "res://scenes/world/fence_wood.tscn")
	_save(_build_arena(), "res://scenes/world/sandbox_arena.tscn")
	_save(_build_main(), "res://scenes/main.tscn")
	print("build_scenes: done")
	get_tree().quit(0)


# --------------------------------------------------------------------------- helpers

func _make_materials() -> void:
	var specs := {
		"stone": [Color(0.52, 0.52, 0.55), 0.9],
		"stone_dark": [Color(0.38, 0.38, 0.42), 0.9],
		"wood": [Color(0.55, 0.38, 0.22), 0.85],
		"wood_dark": [Color(0.36, 0.25, 0.15), 0.9],
		"giant_skin": [Color(0.78, 0.60, 0.45), 0.8],
		"giant_tunic": [Color(0.42, 0.30, 0.20), 0.9],
		"giant_belt": [Color(0.22, 0.16, 0.12), 0.8],
		"giant_hair": [Color(0.25, 0.17, 0.10), 0.9],
		"club": [Color(0.48, 0.33, 0.20), 0.85],
		"eyes": [Color(0.08, 0.08, 0.1), 0.6],
		"soldier_tabard": [Color(0.70, 0.14, 0.12), 0.85],
		"soldier_mail": [Color(0.55, 0.57, 0.60), 0.5],
		"soldier_skin": [Color(0.86, 0.68, 0.55), 0.8],
		"steel": [Color(0.75, 0.77, 0.80), 0.35],
		"sack": [Color(0.66, 0.56, 0.38), 0.95],
		"sign_post": [Color(0.3, 0.3, 0.3), 0.9],
	}
	for name: String in specs:
		var m := StandardMaterial3D.new()
		m.albedo_color = specs[name][0]
		m.roughness = specs[name][1]
		if name == "steel":
			m.metallic = 0.6
		var path := "%s/%s.tres" % [MAT_DIR, name]
		ResourceSaver.save(m, path, ResourceSaver.FLAG_CHANGE_PATH)
		mats[name] = m
	var ground := ShaderMaterial.new()
	ground.shader = load("res://assets/shaders/ground_checker.gdshader")
	ResourceSaver.save(ground, "%s/ground.tres" % MAT_DIR, ResourceSaver.FLAG_CHANGE_PATH)
	mats["ground"] = ground


func _save(root: Node, path: String) -> void:
	_own(root, root)
	var packed := PackedScene.new()
	var err := packed.pack(root)
	if err != OK:
		push_error("pack failed for %s: %d" % [path, err])
		return
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	err = ResourceSaver.save(packed, path, ResourceSaver.FLAG_CHANGE_PATH)
	print("saved %s (%s)" % [path, "ok" if err == OK else "error %d" % err])
	root.free()


func _own(node: Node, root: Node) -> void:
	for child in node.get_children():
		child.owner = root
		if child.scene_file_path == "":
			_own(child, root)


func _scripted(node: Node, script_path: String, props := {}) -> Node:
	node.set_script(load(script_path))
	for k: String in props:
		node.set(k, props[k])
	return node


func _n3(name: String, pos := Vector3.ZERO) -> Node3D:
	var n := Node3D.new()
	n.name = name
	n.position = pos
	return n


func _box(name: String, size: Vector3, pos: Vector3, mat: String, layers := 1) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = name
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.position = pos
	mi.material_override = mats[mat]
	mi.layers = layers
	return mi


func _cyl(name: String, top_r: float, bottom_r: float, height: float, pos: Vector3, mat: String) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = name
	var cm := CylinderMesh.new()
	cm.top_radius = top_r
	cm.bottom_radius = bottom_r
	cm.height = height
	cm.radial_segments = 8
	mi.mesh = cm
	mi.position = pos
	mi.material_override = mats[mat]
	return mi


func _sphere(name: String, r: float, pos: Vector3, mat: String, layers := 1) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = name
	var sm := SphereMesh.new()
	sm.radius = r
	sm.height = r * 2.0
	sm.radial_segments = 10
	sm.rings = 6
	mi.mesh = sm
	mi.position = pos
	mi.material_override = mats[mat]
	mi.layers = layers
	return mi


func _static_box(name: String, size: Vector3, pos: Vector3, mat: String, layer := L_WORLD) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = name
	body.position = pos
	body.collision_layer = layer
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	cs.name = "Shape"
	var shape := BoxShape3D.new()
	shape.size = size
	cs.shape = shape
	body.add_child(cs)
	body.add_child(_box("Mesh", size, Vector3.ZERO, mat))
	return body


func _hurtbox(name: String, region: String, shape: Shape3D, pos: Vector3) -> Area3D:
	var a := Area3D.new()
	a.name = name
	a.position = pos
	a.collision_layer = L_HURTBOX
	a.collision_mask = 0
	a.monitoring = false
	_scripted(a, S_HURTBOX, {"region": region})
	var cs := CollisionShape3D.new()
	cs.name = "Shape"
	cs.shape = shape
	a.add_child(cs)
	return a


func _box_shape(size: Vector3) -> BoxShape3D:
	var s := BoxShape3D.new()
	s.size = size
	return s


func _arm_basis(yaw_deg: float, pitch_deg: float) -> Basis:
	var y := deg_to_rad(yaw_deg)
	var p := deg_to_rad(pitch_deg)
	var dir := Vector3(sin(y) * cos(p), sin(p), -cos(y) * cos(p))
	return Basis.looking_at(dir, Vector3.UP)


func _sign(text: String, pos: Vector3) -> Label3D:
	var l := Label3D.new()
	l.name = "Sign_" + text.get_slice(" ", 0).capitalize()
	l.text = text
	l.position = pos
	l.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	l.font_size = 64
	l.pixel_size = 0.006
	l.outline_size = 12
	l.visibility_range_end = 40.0
	l.modulate = Color(1.0, 0.95, 0.8)
	return l


# --------------------------------------------------------------------------- giant

func _build_giant() -> Node:
	var root := CharacterBody3D.new()
	root.name = "Giant"
	_scripted(root, S_GIANT)
	root.collision_layer = L_ACTORS
	root.collision_mask = L_WORLD | L_ACTORS | L_BREAKABLE
	var cs := CollisionShape3D.new()
	cs.name = "BodyShape"
	var cap := CapsuleShape3D.new()
	cap.radius = 0.85
	cap.height = 3.66
	cs.shape = cap
	cs.position = Vector3(0, 1.83, 0)
	root.add_child(cs)
	root.add_child(_scripted(Node.new(), S_ENTITY, {"name": "CombatEntity", "entity_id": "player",
		"definition_id": "player.giant", "team": 1, "anchor_path": NodePath("../Anchors/Torso")}))
	var anchors := _n3("Anchors")
	var torso_anchor := Marker3D.new()
	torso_anchor.name = "Torso"
	torso_anchor.position = Vector3(0, 2.3, 0)
	anchors.add_child(torso_anchor)
	root.add_child(anchors)
	var hb := _n3("Hurtboxes")
	hb.add_child(_hurtbox("Legs", "legs", _box_shape(Vector3(1.1, 1.6, 0.7)), Vector3(0, 0.8, 0)))
	hb.add_child(_hurtbox("Torso", "torso", _box_shape(Vector3(1.4, 1.5, 0.9)), Vector3(0, 2.35, 0)))
	hb.add_child(_hurtbox("Head", "head", _box_shape(Vector3(0.7, 0.7, 0.7)), Vector3(0, 3.3, 0)))
	root.add_child(hb)
	var visual := _n3("Visual")
	_scripted(visual, S_RIG, {"weapon_arm_path": NodePath("Body/ShoulderR"),
		"off_arm_path": NodePath("Body/ShoulderL"), "leg_left_path": NodePath("Body/HipL"),
		"leg_right_path": NodePath("Body/HipR"), "torso_path": NodePath("Body/Torso"),
		"body_path": NodePath("Body"), "stride_length_m": 1.6})
	var body := _n3("Body")
	visual.add_child(body)
	for side in [-1.0, 1.0]:
		var hip := _n3("HipL" if side < 0 else "HipR", Vector3(0.32 * side, 1.6, 0))
		hip.add_child(_box("Leg", Vector3(0.45, 1.5, 0.5), Vector3(0, -0.75, 0), "giant_tunic"))
		hip.add_child(_box("Foot", Vector3(0.5, 0.16, 0.72), Vector3(0, -1.52, -0.1), "giant_belt"))
		body.add_child(hip)
	var torso := _n3("Torso", Vector3(0, 1.6, 0))
	# Chest and belt are hidden in first person too: from the eye they would cover the ground
	# (and any human) within ~2.6 m of the giant and the crosshair when looking down.
	torso.add_child(_box("Chest", Vector3(1.3, 1.45, 0.8), Vector3(0, 0.73, 0), "giant_tunic", FP_HIDDEN))
	torso.add_child(_box("Belt", Vector3(1.36, 0.18, 0.86), Vector3(0, 0.1, 0), "giant_belt", FP_HIDDEN))
	torso.add_child(_box("Neck", Vector3(0.36, 0.2, 0.36), Vector3(0, 1.52, 0), "giant_skin", FP_HIDDEN))
	torso.add_child(_box("Head", Vector3(0.62, 0.62, 0.62), Vector3(0, 1.74 + 0.0, 0), "giant_skin", FP_HIDDEN))
	torso.add_child(_box("Hair", Vector3(0.66, 0.16, 0.66), Vector3(0, 2.08, 0.02), "giant_hair", FP_HIDDEN))
	torso.add_child(_box("Brow", Vector3(0.5, 0.08, 0.06), Vector3(0, 1.86, -0.32), "giant_hair", FP_HIDDEN))
	torso.add_child(_box("EyeL", Vector3(0.08, 0.08, 0.04), Vector3(-0.13, 1.78, -0.32), "eyes", FP_HIDDEN))
	torso.add_child(_box("EyeR", Vector3(0.08, 0.08, 0.04), Vector3(0.13, 1.78, -0.32), "eyes", FP_HIDDEN))
	body.add_child(torso)
	for side in [-1.0, 1.0]:
		var shoulder := _n3("ShoulderL" if side < 0 else "ShoulderR", Vector3(0.82 * side, 2.9, 0))
		shoulder.basis = _arm_basis(12.0 * side, -78.0)
		shoulder.add_child(_box("UpperArm", Vector3(0.34, 0.34, 0.8), Vector3(0, 0, -0.4), "giant_skin"))
		shoulder.add_child(_box("Forearm", Vector3(0.3, 0.3, 0.7), Vector3(0, 0, -1.15), "giant_skin"))
		shoulder.add_child(_box("Hand", Vector3(0.38, 0.38, 0.38), Vector3(0, 0, -1.5), "giant_skin"))
		if side > 0:
			var club := _cyl("Club", 0.24, 0.11, 1.85, Vector3(0, 0, -1.5 - 0.925), "club")
			club.rotation_degrees = Vector3(-90, 0, 0)
			shoulder.add_child(club)
		body.add_child(shoulder)
	root.add_child(visual)
	var rig := _n3("CameraRig")
	_scripted(rig, S_CAMERA)
	var cam := Camera3D.new()
	cam.name = "Camera3D"
	cam.fov = 75.0
	rig.add_child(cam)
	root.add_child(rig)
	return root


# --------------------------------------------------------------------------- soldier

func _build_soldier() -> Node:
	var root := CharacterBody3D.new()
	root.name = "Soldier"
	_scripted(root, S_SOLDIER, {"entity_id": "soldier_01"})
	root.collision_layer = L_ACTORS
	root.collision_mask = L_WORLD | L_ACTORS | L_BREAKABLE
	var cs := CollisionShape3D.new()
	cs.name = "BodyShape"
	var cap := CapsuleShape3D.new()
	cap.radius = 0.35
	cap.height = 1.8
	cs.shape = cap
	cs.position = Vector3(0, 0.9, 0)
	root.add_child(cs)
	root.add_child(_scripted(Node.new(), S_ENTITY, {"name": "CombatEntity", "entity_id": "soldier_01",
		"definition_id": "enemy.soldier", "team": 2, "anchor_path": NodePath("../Anchors/Torso")}))
	var anchors := _n3("Anchors")
	var a := Marker3D.new()
	a.name = "Torso"
	a.position = Vector3(0, 1.15, 0)
	anchors.add_child(a)
	root.add_child(anchors)
	var hb := _n3("Hurtboxes")
	var head_shape := SphereShape3D.new()
	head_shape.radius = 0.17
	hb.add_child(_hurtbox("Head", "head", head_shape, Vector3(0, 1.63, 0)))
	hb.add_child(_hurtbox("Torso", "torso", _box_shape(Vector3(0.55, 0.65, 0.32)), Vector3(0, 1.15, 0)))
	hb.add_child(_hurtbox("Legs", "legs", _box_shape(Vector3(0.45, 0.85, 0.3)), Vector3(0, 0.42, 0)))
	root.add_child(hb)
	var agent := NavigationAgent3D.new()
	agent.name = "NavAgent"
	root.add_child(agent)
	var visual := _n3("Visual")
	_scripted(visual, S_RIG, {"weapon_arm_path": NodePath("Body/ShoulderR"),
		"off_arm_path": NodePath("Body/ShoulderL"), "leg_left_path": NodePath("Body/HipL"),
		"leg_right_path": NodePath("Body/HipR"), "torso_path": NodePath("Body/Torso"),
		"body_path": NodePath("Body"), "stride_length_m": 0.9, "leg_swing_rad": 0.6,
		"idle_arm_pose": Vector2(15, -70), "block_pose": Vector2(-30, 10)})
	var body := _n3("Body")
	visual.add_child(body)
	for side in [-1.0, 1.0]:
		var hip := _n3("HipL" if side < 0 else "HipR", Vector3(0.12 * side, 0.85, 0))
		hip.add_child(_box("Leg", Vector3(0.2, 0.82, 0.24), Vector3(0, -0.41, 0), "soldier_mail"))
		hip.add_child(_box("Boot", Vector3(0.22, 0.12, 0.32), Vector3(0, -0.8, -0.04), "giant_belt"))
		body.add_child(hip)
	var torso := _n3("Torso", Vector3(0, 0.85, 0))
	torso.add_child(_box("Mail", Vector3(0.5, 0.62, 0.3), Vector3(0, 0.31, 0), "soldier_mail"))
	torso.add_child(_box("Tabard", Vector3(0.52, 0.66, 0.32), Vector3(0, 0.28, 0), "soldier_tabard"))
	torso.add_child(_box("Head", Vector3(0.24, 0.26, 0.26), Vector3(0, 0.78, 0), "soldier_skin"))
	torso.add_child(_box("Helmet", Vector3(0.3, 0.16, 0.32), Vector3(0, 0.92, 0), "steel"))
	torso.add_child(_box("Nasal", Vector3(0.04, 0.16, 0.04), Vector3(0, 0.8, -0.15), "steel"))
	body.add_child(torso)
	for side in [-1.0, 1.0]:
		var shoulder := _n3("ShoulderL" if side < 0 else "ShoulderR", Vector3(0.25 * side, 1.42, 0))
		shoulder.basis = _arm_basis(15.0 * side, -70.0)
		shoulder.add_child(_box("UpperArm", Vector3(0.13, 0.13, 0.3), Vector3(0, 0, -0.15), "soldier_mail"))
		shoulder.add_child(_box("Forearm", Vector3(0.12, 0.12, 0.25), Vector3(0, 0, -0.42), "soldier_skin"))
		if side > 0:
			shoulder.add_child(_box("Grip", Vector3(0.05, 0.05, 0.14), Vector3(0, 0, -0.5), "giant_belt"))
			shoulder.add_child(_box("Guard", Vector3(0.22, 0.04, 0.05), Vector3(0, 0, -0.56), "steel"))
			shoulder.add_child(_box("Blade", Vector3(0.07, 0.02, 0.95), Vector3(0, 0, -0.5 - 0.475), "steel"))
		body.add_child(shoulder)
	root.add_child(visual)
	return root


# --------------------------------------------------------------------------- dummy & fence

func _build_dummy() -> Node:
	var root := StaticBody3D.new()
	root.name = "PracticeDummy"
	_scripted(root, S_DUMMY, {"entity_id": "dummy_01"})
	root.collision_layer = L_ACTORS
	root.collision_mask = 0
	var cs := CollisionShape3D.new()
	cs.name = "Shape"
	var cyl := CylinderShape3D.new()
	cyl.radius = 0.35
	cyl.height = 2.2
	cs.shape = cyl
	cs.position = Vector3(0, 1.1, 0)
	root.add_child(cs)
	root.add_child(_scripted(Node.new(), S_ENTITY, {"name": "CombatEntity", "entity_id": "dummy_01",
		"definition_id": "prop.practice_dummy", "team": 0, "anchor_path": NodePath("../Anchors/Torso")}))
	var anchors := _n3("Anchors")
	var a := Marker3D.new()
	a.name = "Torso"
	a.position = Vector3(0, 1.45, 0)
	anchors.add_child(a)
	root.add_child(anchors)
	var hb := _n3("Hurtboxes")
	hb.add_child(_hurtbox("Body", "torso", _box_shape(Vector3(0.9, 1.3, 0.5)), Vector3(0, 1.45, 0)))
	hb.add_child(_hurtbox("Post", "legs", _box_shape(Vector3(0.3, 0.9, 0.3)), Vector3(0, 0.45, 0)))
	root.add_child(hb)
	var visual := _n3("Visual")
	visual.add_child(_cyl("Base", 0.5, 0.55, 0.15, Vector3(0, 0.075, 0), "wood_dark"))
	visual.add_child(_cyl("Post", 0.11, 0.13, 2.0, Vector3(0, 1.0, 0), "wood"))
	visual.add_child(_box("Crossbar", Vector3(1.4, 0.14, 0.14), Vector3(0, 1.7, 0), "wood"))
	visual.add_child(_box("Sack", Vector3(0.8, 0.9, 0.42), Vector3(0, 1.35, 0), "sack"))
	visual.add_child(_sphere("Head", 0.27, Vector3(0, 2.02, 0), "sack"))
	root.add_child(visual)
	return root


func _build_fence() -> Node:
	var root := StaticBody3D.new()
	root.name = "FenceWood"
	_scripted(root, S_FENCE, {"world_id": "sandbox.fence_01"})
	root.collision_layer = L_BREAKABLE
	root.collision_mask = 0
	var cs := CollisionShape3D.new()
	cs.name = "BlockShape"
	cs.shape = _box_shape(Vector3(8.0, 1.6, 0.3))
	cs.position = Vector3(0, 0.8, 0)
	root.add_child(cs)
	root.add_child(_scripted(Node.new(), S_ENTITY, {"name": "CombatEntity", "entity_id": "sandbox.fence_01",
		"definition_id": "prop.fence_wood", "team": 0, "anchor_path": NodePath("../Anchors/Center")}))
	var anchors := _n3("Anchors")
	var a := Marker3D.new()
	a.name = "Center"
	a.position = Vector3(0, 0.9, 0)
	anchors.add_child(a)
	root.add_child(anchors)
	var hb := _n3("Hurtboxes")
	hb.add_child(_hurtbox("Panel", "body", _box_shape(Vector3(8.0, 1.6, 0.6)), Vector3(0, 0.8, 0)))
	root.add_child(hb)
	var intact := _n3("Intact")
	var broken := _n3("Broken")
	for i in 5:
		var x := -4.0 + 2.0 * i
		intact.add_child(_box("Post%d" % i, Vector3(0.22, 1.7, 0.22), Vector3(x, 0.85, 0), "wood_dark"))
		broken.add_child(_box("Stump%d" % i, Vector3(0.22, 0.45, 0.22), Vector3(x, 0.22, 0), "wood_dark"))
	intact.add_child(_box("RailLow", Vector3(8.2, 0.16, 0.1), Vector3(0, 0.6, 0), "wood"))
	intact.add_child(_box("RailHigh", Vector3(8.2, 0.16, 0.1), Vector3(0, 1.25, 0), "wood"))
	broken.visible = false
	root.add_child(intact)
	root.add_child(broken)
	return root


# --------------------------------------------------------------------------- arena

func _build_arena() -> Node:
	var root := Node3D.new()
	root.name = "SandboxArena"
	_scripted(root, S_ARENA)
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var psm := ProceduralSkyMaterial.new()
	psm.sky_top_color = Color(0.33, 0.50, 0.78)
	psm.sky_horizon_color = Color(0.72, 0.78, 0.86)
	psm.ground_bottom_color = Color(0.22, 0.22, 0.2)
	psm.ground_horizon_color = Color(0.62, 0.64, 0.62)
	sky.sky_material = psm
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.60, 0.62, 0.68)
	env.ambient_light_energy = 0.55
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.0
	var we := WorldEnvironment.new()
	we.name = "Environment"
	we.environment = env
	root.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation_degrees = Vector3(-52, -32, 0)
	sun.light_energy = 1.0
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 90.0
	root.add_child(sun)

	var nav := NavigationRegion3D.new()
	nav.name = "Navigation"
	var nm := NavigationMesh.new()
	nm.agent_radius = 0.5
	nm.agent_height = 2.0
	nm.agent_max_climb = 0.25
	nm.agent_max_slope = 35.0
	nm.cell_size = 0.25
	nm.cell_height = 0.25
	nm.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	nm.geometry_collision_mask = L_WORLD | L_ACTORS | L_BREAKABLE
	nav.navigation_mesh = nm
	root.add_child(nav)

	var ground := StaticBody3D.new()
	ground.name = "Ground"
	ground.collision_layer = L_WORLD
	ground.collision_mask = 0
	var gcs := CollisionShape3D.new()
	gcs.name = "Shape"
	gcs.shape = _box_shape(Vector3(130, 1, 130))
	gcs.position = Vector3(0, -0.5, 0)
	ground.add_child(gcs)
	var gmesh := MeshInstance3D.new()
	gmesh.name = "Mesh"
	var plane := PlaneMesh.new()
	plane.size = Vector2(130, 130)
	gmesh.mesh = plane
	gmesh.material_override = mats["ground"]
	ground.add_child(gmesh)
	nav.add_child(ground)

	var walls := _n3("Walls")
	walls.add_child(_static_box("North", Vector3(124, 8, 2), Vector3(0, 4, -61), "stone"))
	walls.add_child(_static_box("South", Vector3(124, 8, 2), Vector3(0, 4, 61), "stone"))
	walls.add_child(_static_box("East", Vector3(2, 8, 124), Vector3(61, 4, 0), "stone"))
	walls.add_child(_static_box("West", Vector3(2, 8, 124), Vector3(-61, 4, 0), "stone"))
	nav.add_child(walls)

	var pillars := _n3("Pillars")
	var pillar_positions := [Vector3(-22, 4, -4), Vector3(22, 4, -40), Vector3(-9, 4, -34),
		Vector3(9, 4, -36), Vector3(-34, 4, 22), Vector3(36, 4, 20)]
	for i in pillar_positions.size():
		pillars.add_child(_static_box("Pillar%d" % i, Vector3(3, 8, 3), pillar_positions[i], "stone_dark"))
	nav.add_child(pillars)

	var tests := _n3("TestFeatures")
	# Wall lane: a dummy stands behind a solid wall; swings must not pass through it.
	tests.add_child(_static_box("TestWall", Vector3(0.8, 6, 12), Vector3(-14, 3, 36), "stone"))
	# Doorway: 2.6 m wide, 5 m tall opening for camera/clearance checks.
	tests.add_child(_static_box("DoorwayLeft", Vector3(17.7, 7, 1), Vector3(-35.15, 3.5, 10), "stone"))
	tests.add_child(_static_box("DoorwayRight", Vector3(11.7, 7, 1), Vector3(-17.85, 3.5, 10), "stone"))
	tests.add_child(_static_box("DoorwayLintel", Vector3(2.6, 2, 1), Vector3(-25, 6, 10), "stone"))
	# Low arch: 6 m wide tunnel with a 4.2 m ceiling (giant is 3.66 m).
	tests.add_child(_static_box("ArchWallWest", Vector3(1, 4.2, 8), Vector3(21.5, 2.1, 6), "stone_dark"))
	tests.add_child(_static_box("ArchWallEast", Vector3(1, 4.2, 8), Vector3(28.5, 2.1, 6), "stone_dark"))
	tests.add_child(_static_box("ArchRoof", Vector3(8, 0.8, 8), Vector3(25, 4.6, 6), "stone_dark"))
	# Ramp (20 degrees) up to a 3 m platform.
	tests.add_child(_static_box("Platform", Vector3(10, 3, 10), Vector3(36, 1.5, -24), "stone"))
	var ramp_len := 3.0 / sin(deg_to_rad(20.0))
	var ramp := _static_box("Ramp", Vector3(5, 0.4, ramp_len), Vector3(36, 1.5 - 0.19, -19 + 3.0 / tan(deg_to_rad(20.0)) * 0.5), "stone")
	ramp.rotation_degrees = Vector3(20, 0, 0)
	tests.add_child(ramp)
	nav.add_child(tests)

	var fence: Node3D = (load("res://scenes/world/fence_wood.tscn") as PackedScene).instantiate()
	fence.name = "Fence01"
	fence.position = Vector3(12, 0, 34)
	fence.rotation_degrees = Vector3(0, 90, 0)
	fence.set("world_id", "sandbox.fence_01")
	nav.add_child(fence)
	var dummy: Node3D = (load("res://scenes/world/practice_dummy.tscn") as PackedScene).instantiate()
	dummy.name = "PracticeDummy"
	dummy.position = Vector3(0, 0, 32)
	dummy.set("entity_id", "dummy_01")
	nav.add_child(dummy)
	var wall_dummy: Node3D = (load("res://scenes/world/practice_dummy.tscn") as PackedScene).instantiate()
	wall_dummy.name = "WallDummy"
	wall_dummy.position = Vector3(-16.5, 0, 36)
	wall_dummy.set("entity_id", "dummy_behind_wall")
	nav.add_child(wall_dummy)

	var spawns := _n3("Spawns")
	var ps := Marker3D.new()
	ps.name = "PlayerSpawn"
	ps.position = Vector3(0, 0.05, 40)
	spawns.add_child(ps)
	root.add_child(spawns)
	var route := _n3("PatrolRoute")
	for i in 3:
		var m := Marker3D.new()
		m.name = "P%d" % (i + 1)
		m.position = [Vector3(0, 0, -12), Vector3(14, 0, -22), Vector3(-14, 0, -22)][i]
		route.add_child(m)
	root.add_child(route)
	var player: Node3D = (load("res://scenes/player/giant.tscn") as PackedScene).instantiate()
	player.name = "Player"
	player.position = Vector3(0, 0.05, 40)
	root.add_child(player)
	var soldier: Node3D = (load("res://scenes/enemies/soldier.tscn") as PackedScene).instantiate()
	soldier.name = "Soldier01"
	soldier.position = Vector3(0, 0.05, -12)
	soldier.set("entity_id", "soldier_01")
	soldier.set("patrol_route", NodePath("../PatrolRoute"))
	root.add_child(soldier)
	var debris := _n3("DebrisPool")
	_scripted(debris, S_DEBRIS)
	root.add_child(debris)

	var signs := _n3("Signs")
	signs.add_child(_sign("PRACTICE DUMMY (armor 25)", Vector3(0, 3.3, 32)))
	signs.add_child(_sign("BREAKABLE FENCE", Vector3(12, 2.6, 34)))
	signs.add_child(_sign("WALL TEST: hits must not pass", Vector3(-12.5, 6.8, 36)))
	signs.add_child(_sign("DOORWAY 2.6 x 5 m", Vector3(-25, 7.8, 10)))
	signs.add_child(_sign("LOW ARCH 4.2 m", Vector3(25, 5.8, 6)))
	signs.add_child(_sign("RAMP 20 deg", Vector3(36, 5.0, -14)))
	signs.add_child(_sign("SOLDIER PATROL", Vector3(0, 4.0, -18)))
	root.add_child(signs)
	return root


func _build_main() -> Node:
	var root := Node.new()
	root.name = "Main"
	_scripted(root, S_MAIN)
	return root
