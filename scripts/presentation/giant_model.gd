class_name GiantModel
extends Node3D
## The realistic giant's model (plan M10 §2.5, §2.6; P41): the root of scenes/player/giant_model.tscn,
## which tools/builders/giant_model.gd writes from assets/giant/manifest.json. Its child "Giant" is
## the instanced glTF (assets/giant/giant.glb), turned 180 degrees about Y so the giant faces -Z like
## every actor; its one Skeleton3D (the MPFB2 "game_engine" rig, 53 bones) holds every mesh: the body
## in three parts, the eyes, the hair and beard cards and the garments. The model is built at the
## stage-1 height (3.6576 m); Visual/Body scales it by k = height / 3.6576.
##
## `index` (exported, saved in the scene) describes the meshes, garments, designs, regions, the
## landmarks (the skeleton's joints at stage 1 in this node's frame: +X the giant's right, +Y up, -Z his
## front), the default meshes and the texture tiers. Edits inside an instanced scene are never saved
## (a SceneKit save keeps nothing set on a node inside an instance), so _ready() applies every mesh's
## render layer and the default visibility from the index. Presentation only: no gameplay code reads
## the model (plan §2.7). The model draws with the glTF's placeholder materials until a caller runs
## GiantLook.build_materials (P42).

## Every GiantModel joins this group.
const GROUP := "giant_models"
## The imported glTF, held for the whole process: a cache miss costs tens of milliseconds a load
## (plan §1.7 rule 3).
const SCENE := preload("res://assets/giant/giant.glb")
## The arms' turn toward the body in pose_relaxed() (degrees, from the rest A-pose) and the elbows' bend.
const RELAXED_ARM_DEG := 38.0
const RELAXED_ELBOW_DEG := 12.0

## The giant index (plan §2.5): meshes, garments, designs, regions, landmarks, defaults, tiers.
@export var index: Dictionary = {}

var _skeleton: Skeleton3D = null
var _meshes: Dictionary = {}     # mesh id -> MeshInstance3D


func _ready() -> void:
	add_to_group(GROUP)
	_bind()
	apply_defaults()


## Finds the skeleton and every index mesh under the instanced glTF.
func _bind() -> void:
	_meshes.clear()
	var found := find_children("*", "Skeleton3D", true, false)
	_skeleton = found[0] as Skeleton3D if not found.is_empty() else null
	var by_name := {}
	for n in find_children("*", "MeshInstance3D", true, false):
		by_name[n.name] = n
	for id: String in index.get("meshes", {}):
		var e: Dictionary = index.meshes[id]
		var mi: MeshInstance3D = by_name.get(str(e.get("node", id)))
		if mi != null:
			_meshes[id] = mi


## Every index mesh on its render layer (1 limbs, 2 torso and garment cores, 3 head, eyes, hair and
## beards), shown when the index's defaults list it.
func apply_defaults() -> void:
	var shown: Array = index.get("defaults", {}).get("shown", [])
	for id: String in _meshes:
		var mi: MeshInstance3D = _meshes[id]
		mi.layers = 1 << (int(index.meshes[id].get("layer", 1)) - 1)
		mi.visible = shown.has(id)


## The one Skeleton3D of the model.
func skeleton() -> Skeleton3D:
	if _skeleton == null:
		_bind()
	return _skeleton


## The MeshInstance3D of an index mesh id ("Body_Torso", "Hair_long_back", "Garment_tunic_core"); null
## for an unknown id.
func mesh(id: String) -> MeshInstance3D:
	if _meshes.is_empty():
		_bind()
	return _meshes.get(id)


## The meshes of one index category ("body", "eyes", "hair", "beard", "garment"), in id order.
func meshes(category: String) -> Array[MeshInstance3D]:
	if _meshes.is_empty():
		_bind()
	var ids: Array = _meshes.keys()
	ids.sort()
	var out: Array[MeshInstance3D] = []
	for id: String in ids:
		if str(index.meshes[id].get("category", "")) == category:
			out.append(_meshes[id])
	return out


## The landmarks at stage 1 in this node's frame: Vector3 joints ("shoulder_r", "elbow_r", "wrist_r",
## "palm_r", "hip_r", "knee_r", "ankle_r" and their "_l" twins, "eye_mid", "head", "neck", "pelvis")
## and float reaches ("reach_r", "reach_l": shoulder to elbow to wrist to the palm's grip point).
func landmarks() -> Dictionary:
	return GiantModel.landmarks_of(index)


static func landmarks_of(idx: Dictionary) -> Dictionary:
	var out := {}
	var lm: Dictionary = idx.get("landmarks", {})
	for k: String in lm:
		var v: Variant = lm[k]
		if v is Array and (v as Array).size() == 3:
			out[k] = Vector3(float(v[0]), float(v[1]), float(v[2]))
		else:
			out[k] = float(v)
	return out


## The hand bone's global transform (the preview's weapon is placed at it; plan §2.10). The skeleton's
## pending pose changes are applied first.
func hand_transform(right: bool) -> Transform3D:
	var sk := skeleton()
	if sk == null:
		return global_transform if is_inside_tree() else transform
	var bone := sk.find_bone("hand_r" if right else "hand_l")
	if bone < 0:
		return global_transform if is_inside_tree() else transform
	sk.force_update_all_bone_transforms()
	var base := sk.global_transform if sk.is_inside_tree() else _transform_to(sk)
	return base * sk.get_bone_global_pose(bone)


## The skeleton's transform relative to this node's parent, outside the tree.
func _transform_to(node: Node3D) -> Transform3D:
	var t := Transform3D.IDENTITY
	var n: Node = node
	while n != null and n != get_parent():
		if n is Node3D:
			t = (n as Node3D).transform * t
		n = n.get_parent()
	return t


## Arms down from the rest A-pose and the elbows a little bent: the pose of previews and sheets
## before P43's idle clip exists. Pose rotations take effect once the skeleton is inside the tree.
func pose_relaxed() -> void:
	var sk := skeleton()
	if sk == null:
		return
	for side: String in ["l", "r"]:
		_turn_toward(sk, "upperarm_" + side, Vector3.DOWN, RELAXED_ARM_DEG)
		_bend(sk, "lowerarm_" + side, RELAXED_ELBOW_DEG)
	sk.force_update_all_bone_transforms()


## Back to the rest pose.
func pose_rest() -> void:
	var sk := skeleton()
	if sk != null:
		sk.reset_bone_poses()
		sk.force_update_all_bone_transforms()


## Turns a bone about its head, in skeleton space, toward `toward` by up to `deg` degrees.
static func _turn_toward(sk: Skeleton3D, bone_name: String, toward: Vector3, deg: float) -> void:
	var b := sk.find_bone(bone_name)
	if b < 0:
		return
	var rest := sk.get_bone_global_rest(b)
	var child := sk.find_bone(bone_name.replace("upperarm", "lowerarm"))
	var dir := (sk.get_bone_global_rest(child).origin - rest.origin).normalized() if child >= 0 else rest.basis.y
	var axis := dir.cross(toward)
	if axis.length() < 1e-6:
		return
	var angle := minf(deg_to_rad(deg), dir.angle_to(toward))
	_rotate_global(sk, b, Basis(axis.normalized(), angle))


## Bends a forearm bone forward (about the skeleton's X axis) by `deg` degrees.
static func _bend(sk: Skeleton3D, bone_name: String, deg: float) -> void:
	var b := sk.find_bone(bone_name)
	if b >= 0:
		_rotate_global(sk, b, Basis(Vector3.RIGHT, deg_to_rad(deg)))


## Applies a skeleton-space rotation to a bone's rest: local = parent⁻¹ · q · parent · rest_local.
static func _rotate_global(sk: Skeleton3D, b: int, q: Basis) -> void:
	var parent := sk.get_bone_parent(b)
	var pb := sk.get_bone_global_rest(parent).basis if parent >= 0 else Basis.IDENTITY
	var local := pb.inverse() * q * pb * sk.get_bone_rest(b).basis
	sk.set_bone_pose_rotation(b, local.get_rotation_quaternion())
