class_name PersonModel
extends Node3D
## A skinned person (P60; plan M11 §2.9): the root of scenes/people/person_model.tscn, which
## tools/builders/people_models.gd writes - the 23-bone skeleton of P59's people under "People" (the name the
## clips' tracks start with: "People/Skeleton3D:pelvis"), one MeshInstance3D "Mesh" on it, and an
## AnimationPlayer whose root is this node. The model is turned 180 degrees about Y inside its parent so the
## person faces -Z like every actor (the glTF faces +Z) and scaled by the body's height.
##
## A model is pooled: PersonRig takes one when its actor becomes skinned (acquire) and gives it back when it
## leaves the skinned level (release), so at most PersonRig.MAX_SKINNED models are in use however many people
## a level holds. A model takes any role and variant: set_variant() puts the variant's mesh and skin on the mesh
## node and its own joints' rests on the skeleton (every variant of P59 shares the reference man's rest
## orientations and pelvis, so one set of clips poses them all).
##
## The role's data is read once a process from P59's files (role_data()): the manifest's index, the role's glTF (its
## variants' meshes, skins and rests, the five crowd-pose meshes and the far mesh), the atlases, the gear and the
## clips. The materials: one ShaderMaterial (person.gdshader) a model, duplicated from the role's; one crowd
## material (person_crowd.gdshader) a person role, shared by every MultiMesh that draws it. Presentation only:
## no gameplay code reads a model (the code rules of plan M10 §2.7, extended to the people).

const SCENE_PATH := "res://scenes/people/person_model.tscn"
const MANIFEST := "res://assets/people/manifest.json"
const PERSON_SHADER := "res://assets/shaders/person.gdshader"
const CROWD_SHADER := "res://assets/shaders/person_crowd.gdshader"
const LIBRARY := &"people"
const SKELETON_PATH := NodePath("People/Skeleton3D")
const MESH_PATH := NodePath("People/Skeleton3D/Mesh")
const PLAYER_NAME := "AnimationPlayer"
## The clips that loop (imported clips have loop off).
const LOOPS := ["idle", "walk", "run", "flee", "held", "tumble", "cower"]
## The people's reference height (P59 exports every person at 1.8 m).
const HEIGHT_M := 1.8

## The manifest's index, its roles' facts, and the roles' data read so far (role -> Dictionary).
static var _index: Dictionary = {}
static var _facts: Dictionary = {}
static var _roles: Dictionary = {}
static var _gear: Dictionary = {}
static var _clips: AnimationLibrary = null
static var _scene: PackedScene = null
static var _crowd_materials: Dictionary = {}
## Free models by role, and how many models the process made (tests, the stats).
static var _pool: Dictionary = {}
static var made := 0
static var _exit_hooked := false

var role := ""
var variant := ""
var material: ShaderMaterial = null
var _skeleton: Skeleton3D = null
var _mesh: MeshInstance3D = null
var _player: AnimationPlayer = null


# --------------------------------------------------------------------------- P59's data

## The manifest's index (plan §2.8): roles, bones, bands, poses, the clips' and the gear's paths.
static func index() -> Dictionary:
	if _index.is_empty():
		var doc: Variant = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST))
		if doc is Dictionary:
			_index = (doc as Dictionary).get("index", {})
			_facts = (doc as Dictionary).get("roles", {})
	return _index


## True when the index has `asset_role` (a role P59 built).
static func has_role(asset_role: String) -> bool:
	return (index().get("roles", {}) as Dictionary).has(asset_role)


## The role's data, read once: {"variants": {name: {"mesh", "skin", "rests": Array[Transform3D] by bone name,
## "natural": the suggested height scale}}, "poses": {pose: Mesh}, "far": Mesh, "albedo", "normal", "orm"}.
## {} for a role the index does not have.
static func role_data(asset_role: String) -> Dictionary:
	if _roles.has(asset_role):
		return _roles[asset_role]
	_hook_exit()
	var entry: Dictionary = (index().get("roles", {}) as Dictionary).get(asset_role, {})
	if entry.is_empty() or not ResourceLoader.exists(str(entry.scene)):
		return {}
	var root := (load(str(entry.scene)) as PackedScene).instantiate()
	var out := {"variants": {}, "poses": {}, "far": null, "order": entry.variants,
		"albedo": load(str(entry.albedo)), "normal": load(str(entry.normal)), "orm": load(str(entry.orm))}
	var facts: Dictionary = (_facts.get(asset_role, {}) as Dictionary).get("variants", {})
	for v: String in entry.variants:
		var mi := root.find_child(v, true, false) as MeshInstance3D
		if mi == null:
			continue
		var sk := mi.get_parent() as Skeleton3D
		var rests := {}
		for i in sk.get_bone_count():
			rests[sk.get_bone_name(i)] = sk.get_bone_rest(i)
		out.variants[v] = {"mesh": mi.mesh, "skin": mi.skin, "rests": rests,
			"natural": float((facts.get(v, {}) as Dictionary).get("natural_height_m", 1.0))}
	for pose: String in entry.poses:
		var pm := root.find_child(str(entry.poses[pose]), true, false) as MeshInstance3D
		if pm != null:
			out.poses[pose] = pm.mesh
	var far := root.find_child(str(entry.far), true, false) as MeshInstance3D
	out.far = far.mesh if far != null else null
	root.free()
	_roles[asset_role] = out
	return out


## A piece of gear's mesh (gear.glb; its grip at the origin, its length along +Y), null when unknown.
static func gear_mesh(piece: String) -> Mesh:
	if _gear.is_empty():
		var path := str(index().get("gear", ""))
		if not ResourceLoader.exists(path):
			return null
		var root := (load(path) as PackedScene).instantiate()
		for c in root.find_children("gear_*", "MeshInstance3D", true, false):
			_gear[str(c.name).trim_prefix("gear_")] = (c as MeshInstance3D).mesh
		root.free()
	return _gear.get(piece)


## The clip library (a copy of P59's, the loops set), held for the process; null without the clips.
static func clip_library() -> AnimationLibrary:
	if _clips == null:
		var path := str(index().get("clips", ""))
		if ResourceLoader.exists(path):
			var src := load(path) as AnimationLibrary
			if src != null:
				_clips = src.duplicate(true) as AnimationLibrary
				for n: String in LOOPS:
					if _clips.has_animation(n):
						_clips.get_animation(n).loop_mode = Animation.LOOP_LINEAR
	return _clips


## A joint of a crowd pose of `asset_role` in the model's own frame (+Z the person's front, metres at 1.8 m):
## the manifest's record of the joints the pose mesh was skinned with (P59 writes Blender's frame: x, y, z ->
## x, z, -y). Vector3.INF when unknown.
static func pose_joint(asset_role: String, pose: String, joint: String) -> Vector3:
	index()
	var j: Variant = ((((_facts.get(asset_role, {}) as Dictionary).get("poses", {}) as Dictionary).get(pose, {}) as Dictionary) \
		.get("joints", {}) as Dictionary).get(joint)
	if typeof(j) != TYPE_ARRAY or (j as Array).size() != 3:
		return Vector3.INF
	return Vector3(float(j[0]), float(j[2]), -float(j[1]))


# --------------------------------------------------------------------------- materials

## A new material for one skinned model of `asset_role` (person.gdshader with the role's atlases).
static func skinned_material(asset_role: String) -> ShaderMaterial:
	var r := role_data(asset_role)
	var m := ShaderMaterial.new()
	m.shader = load(PERSON_SHADER)
	if not r.is_empty():
		m.set_shader_parameter(&"albedo_tex", r.albedo)
		m.set_shader_parameter(&"normal_tex", r.normal)
		m.set_shader_parameter(&"orm_tex", r.orm)
		m.set_shader_parameter(&"band_tex", r.orm)
	return m


## The material a piece of gear of a skinned person draws with (its vertex colours; one a person: it flashes
## and tints with the body).
static func gear_material() -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load(PERSON_SHADER)
	m.set_shader_parameter(&"gear", true)
	return m


## The crowd material of `person_role` (person_crowd.gdshader, the role's atlases and palette; `gear`: the gear's
## variant), shared by every MultiMesh that draws it.
static func crowd_material(person_role: String, gear := false) -> ShaderMaterial:
	var key := "%s|%s" % [person_role, gear]
	if _crowd_materials.has(key):
		return _crowd_materials[key]
	var m := ShaderMaterial.new()
	m.shader = load(CROWD_SHADER)
	var r := role_data(PersonLook.asset_role(person_role))
	if not r.is_empty():
		m.set_shader_parameter(&"albedo_tex", r.albedo)
		m.set_shader_parameter(&"orm_tex", r.orm)
		m.set_shader_parameter(&"band_tex", r.orm)
	m.set_shader_parameter(&"palette_tex", ImageTexture.create_from_image(PersonLook.palette_image(person_role)))
	m.set_shader_parameter(&"gear", gear)
	_crowd_materials[key] = m
	return m


# --------------------------------------------------------------------------- the pool

## A model of `asset_role` showing `variant`, from the pool or new (null when the role or its scene is missing).
static func acquire(asset_role: String, p_variant: String) -> PersonModel:
	var free: Array = _pool.get(asset_role, [])
	var m: PersonModel = null
	while not free.is_empty() and m == null:
		var c: Variant = free.pop_back()
		if is_instance_valid(c):
			m = c as PersonModel
	if m == null:
		if _scene == null:
			if not ResourceLoader.exists(SCENE_PATH):
				return null
			_scene = load(SCENE_PATH) as PackedScene
		m = _scene.instantiate() as PersonModel
		if m == null:
			return null
		made += 1
	m.set_variant(asset_role, p_variant)
	return m


## Gives `m` back to the pool (out of the tree, its animation stopped).
static func release(m: PersonModel) -> void:
	if m == null or not is_instance_valid(m):
		return
	if m.get_parent() != null:
		m.get_parent().remove_child(m)
	if m._player != null:
		m._player.stop()
	if not _pool.has(m.role):
		_pool[m.role] = []
	(_pool[m.role] as Array).append(m)


## Everything held for the process goes when the tree does (the pooled models are out of the tree: freed here), so
## a run exits with nothing left in use.
static func _hook_exit() -> void:
	if _exit_hooked:
		return
	var tree := Engine.get_main_loop() as SceneTree
	if tree != null and tree.root != null:
		_exit_hooked = true
		tree.root.tree_exiting.connect(PersonModel.drop_all)


static func drop_all() -> void:
	clear_pool()
	_roles.clear()
	_gear.clear()
	_crowd_materials.clear()
	_clips = null
	_scene = null
	_exit_hooked = false
	CrowdRenderer.drop_caches()


## The pooled models (tests).
static func pooled() -> int:
	var n := 0
	for list: Array in _pool.values():
		n += list.size()
	return n


## Frees the pool (a level change keeps it; tests that count models call it).
static func clear_pool() -> void:
	for list: Array in _pool.values():
		for m: Variant in list:
			if is_instance_valid(m):
				(m as Node).free()
	_pool.clear()


# --------------------------------------------------------------------------- one model

func skeleton() -> Skeleton3D:
	if _skeleton == null:
		_skeleton = get_node_or_null(SKELETON_PATH) as Skeleton3D
	return _skeleton


func mesh_instance() -> MeshInstance3D:
	if _mesh == null:
		_mesh = get_node_or_null(MESH_PATH) as MeshInstance3D
	return _mesh


## The model's AnimationPlayer (manual: PersonRig seeks and advances it), with the clips.
func player() -> AnimationPlayer:
	if _player == null:
		_player = get_node_or_null(PLAYER_NAME) as AnimationPlayer
		if _player != null:
			var lib := clip_library()
			if lib != null and not _player.has_animation_library(LIBRARY):
				_player.add_animation_library(LIBRARY, lib)
			_player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	return _player


## Puts `asset_role`'s `p_variant` on this model (its first variant when unknown): the mesh, its skin, the
## skeleton's rests and a material of the role.
func set_variant(asset_role: String, p_variant: String) -> void:
	var r := role_data(asset_role)
	var variants: Dictionary = r.get("variants", {})
	if variants.is_empty():
		return
	if not variants.has(p_variant):
		p_variant = str((r.order as Array)[0])
	var sk := skeleton()
	var mi := mesh_instance()
	if sk == null or mi == null:
		return
	if asset_role != role or material == null:
		material = skinned_material(asset_role)
	role = asset_role
	variant = p_variant
	var v: Dictionary = variants[p_variant]
	var rests: Dictionary = v.rests
	for i in sk.get_bone_count():
		var bn := sk.get_bone_name(i)
		if rests.has(bn):
			sk.set_bone_rest(i, rests[bn])
	sk.reset_bone_poses()   # (the rests as the poses: positions and scales a reused model's arms left are gone)
	mi.mesh = v.mesh
	mi.skin = v.skin
	mi.material_override = material


## The suggested height scale of the variant shown (P59: 1.0 for the men, 0.93 for the women).
func natural_scale() -> float:
	var v: Dictionary = (role_data(role).get("variants", {}) as Dictionary).get(variant, {})
	return float(v.get("natural", 1.0))
