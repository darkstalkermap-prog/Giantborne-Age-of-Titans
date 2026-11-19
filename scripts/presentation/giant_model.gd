class_name GiantModel
extends Node3D
## The realistic giant's model (plan M10 §2.5, §2.6; P41): the root of scenes/player/giant_model.tscn,
## which tools/builders/giant_model.gd writes from assets/giant/manifest.json. Its child "Giant" is
## the instanced glTF (assets/giant/giant.glb), turned 180 degrees about Y so the giant faces -Z like
## every actor; its one Skeleton3D (the MPFB2 "game_engine" rig's 53 bones and P48's 18 leaf bones for
## hair, beard and cape) holds every mesh: the body in three parts, the eyes, the shadow proxy, and the
## hair and beard cards and the garments. The model is built at the stage-1 height (3.6576 m);
## Visual/Body scales it by k = height / 3.6576.
##
## Parts (P48, plan M11 §2.2): giant.glb holds the body, the eyes and the shadow proxy only. Every hair,
## beard and garment mesh is a part, a glTF of its own on the same skeleton (the index's
## `meshes[id].part_path`). The model keeps an empty MeshInstance3D under the skeleton for each part,
## named as its mesh, so everything that finds a mesh by its node (GiantLook, the tests) still does; a
## part's mesh is loaded the first time its node is shown (or ensure_part(id) is called) and bound to
## this skeleton by its named skin, and let go when its node is hidden (or release_unused() leaves it
## out). A part is a shared resource: two models showing the same hair hold the same Mesh, and the last
## PART_KEEP parts let go (by a hidden node or a freed model) stay loaded, so turning a style off and on
## again, or the next giant with the same look, costs nothing.
##
## Shadows: with the shadow proxy present every other mesh casts no shadow and the proxy is drawn in the
## shadow passes only, one draw call a cascade; a free mesh (the cape, `free` in the index) keeps its own.
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
## play_idle(): the run-time AnimationPlayer's name and the clip it loops (assets/giant/giant_clips.glb).
const IDLE_PLAYER := "IdlePlayer"
const IDLE_CLIP := "idle"

## The index key of a part's glTF ("part" already names a garment's body part, torso or limbs).
const PART_PATH := "part_path"
## The metadata on a part's run-time node: its mesh id.
const PART_META := &"giant_part"
## The shadow proxy's node when the index names none.
const SHADOW_PROXY := "ShadowProxy"
## Gate A: the limbs' layer, which every camera draws. A shadows-only mesh is still culled by the camera's cull
## mask in the shadow passes, so on the head's layer (W29) first person and the pressed camera lost the shadow.
const SHADOW_PROXY_LAYER := 1
## The parts let go last stay loaded (strong references), so a style turned off and on again, or the next
## model that shows it, does not load it twice.
const PART_KEEP := 6
## and no more than this many bytes of mesh buffers (counted roughly, part_cost): with the fullest look
## shown the giant's resident meshes stay under plan M11 §2.12's 4.5 MB.
const PART_KEEP_BYTES := 1000000

## The giant index (plan §2.5): meshes, garments, designs, regions, landmarks, defaults, tiers.
@export var index: Dictionary = {}

## Loaded parts by path: {"mesh": WeakRef, "skin": Skin}. The mesh is held weakly: a part nothing shows is
## freed (a Skin is 71 names and poses, kept).
static var _part_cache: Dictionary = {}
## The last PART_KEEP parts let go: [path, Mesh, its rough cost in bytes], the newest last.
static var _part_recent: Array = []
## Parts read from disk since the process started (the tests' and the bench's count).
static var _part_loads := 0
static var _exit_hooked := false

var _skeleton: Skeleton3D = null
var _meshes: Dictionary = {}     # mesh id -> MeshInstance3D
var _bound := false


func _notification(what: int) -> void:
	# The part nodes exist as soon as the scene is instanced, in the tree or not (GiantLook finds meshes by
	# their nodes on models that never enter it).
	if what == NOTIFICATION_SCENE_INSTANTIATED:
		_bind()
	elif what == NOTIFICATION_PREDELETE:
		# A model that goes (a level reload, a closed preview) leaves its parts in the recent list: the next
		# one finds the default look loaded.
		for id: String in _meshes:
			var mi: Variant = _meshes[id]
			if is_instance_valid(mi) and (mi as MeshInstance3D).mesh != null and is_part(id):
				GiantModel._keep_recent(str(index.meshes[id][PART_PATH]), (mi as MeshInstance3D).mesh)


func _ready() -> void:
	add_to_group(GROUP)
	if not _bound:
		_bind()
	_drop_stray_parts()
	apply_defaults()


## Finds the skeleton and every index mesh under the instanced glTF, and makes the empty node of every
## part that has none yet.
func _bind() -> void:
	_meshes.clear()
	var found := find_children("*", "Skeleton3D", true, false)
	_skeleton = found[0] as Skeleton3D if not found.is_empty() else null
	if _skeleton == null:
		return
	var meshes: Dictionary = index.get("meshes", {})
	var skin: Skin = null
	for id: String in meshes:
		var e: Dictionary = meshes[id]
		var node_name := str(e.get("node", id))
		var mi := _skeleton.get_node_or_null(node_name) as MeshInstance3D
		if mi != null and skin == null and not e.has(PART_PATH):
			skin = mi.skin          # the model's own Skin (the body's): every mesh of giant.glb shares it
	for id: String in meshes:
		var e: Dictionary = meshes[id]
		var node_name := str(e.get("node", id))
		var mi := _skeleton.get_node_or_null(node_name) as MeshInstance3D
		if mi == null and e.has(PART_PATH):
			mi = MeshInstance3D.new()
			mi.name = node_name
			mi.visible = false
			mi.skeleton = NodePath("..")
			mi.skin = skin
			mi.set_meta(PART_META, id)
			_skeleton.add_child(mi)
		if mi == null:
			continue
		_meshes[id] = mi
		if e.has(PART_PATH) and not mi.visibility_changed.is_connected(_on_part_visibility):
			mi.visibility_changed.connect(_on_part_visibility.bind(id))
	_bound = true


## Node.duplicate() instances the scene again (which makes the part nodes) and then copies the original's
## run-time nodes beside them under other names: those copies go, or a copied model would draw its parts
## twice.
func _drop_stray_parts() -> void:
	if _skeleton == null:
		return
	for c in _skeleton.get_children():
		if c.has_meta(PART_META) and _meshes.get(str(c.get_meta(PART_META))) != c:
			_skeleton.remove_child(c)
			c.free()


## Every index mesh on its render layer (1 limbs, 2 torso and garment cores, 3 head, eyes, hair and
## beards), shown when the index's defaults list it; the shadows on the proxy (see the class notes).
func apply_defaults() -> void:
	var shown: Array = index.get("defaults", {}).get("shown", [])
	var proxy := shadow_proxy()
	for id: String in _meshes:
		var mi: MeshInstance3D = _meshes[id]
		var e: Dictionary = index.meshes[id]
		mi.layers = 1 << (int(e.get("layer", 1)) - 1)
		mi.visible = shown.has(id)
		if proxy != null:
			mi.cast_shadow = (GeometryInstance3D.SHADOW_CASTING_SETTING_ON if bool(e.get("free", false))
					else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)
	if proxy != null:
		# on the limbs' layer, which every camera keeps: the renderer culls a shadow caster by the camera's
		# mask too, so on a layer first person culls (the head's, W29) the giant cast no shadow there; a mesh
		# drawn in the shadow passes only is never drawn by the camera itself
		proxy.layers = 1 << (SHADOW_PROXY_LAYER - 1)
		proxy.visible = true
		proxy.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY


# --------------------------------------------------------------------------- parts (P48)

## The body at about 2,500 triangles, drawn in the shadow passes only; null when the model has none.
func shadow_proxy() -> MeshInstance3D:
	var sk := skeleton()
	if sk == null:
		return null
	var node_name := str((index.get("shadow_proxy", {}) as Dictionary).get("node", SHADOW_PROXY))
	return sk.get_node_or_null(node_name) as MeshInstance3D


## True when `id` is a part (a mesh with a glTF of its own).
func is_part(id: String) -> bool:
	var e: Variant = index.get("meshes", {}).get(id)
	return typeof(e) == TYPE_DICTIONARY and (e as Dictionary).has(PART_PATH)


## True when the part's mesh is loaded on this model.
func is_part_loaded(id: String) -> bool:
	var mi: MeshInstance3D = _meshes.get(id)
	return mi != null and mi.mesh != null


## Loads the part and binds it to this model's skeleton the first time; returns its node (the mesh of
## giant.glb itself for an id that is no part). Null for an unknown id or a part whose file is missing.
func ensure_part(id: String) -> MeshInstance3D:
	if not _bound:
		_bind()
	var mi: MeshInstance3D = _meshes.get(id)
	if mi == null or not is_part(id) or mi.mesh != null:
		return mi
	var res := GiantModel.load_part(str(index.meshes[id][PART_PATH]))
	if res.is_empty():
		return null
	# Every part is exported on the model's own armature, so its skin is the body's bind for bind; the
	# model's one Skin then serves every mesh (one set of bone matrices). A part whose skin differs keeps
	# its own.
	if mi.skin == null or not GiantModel.same_binds(mi.skin, res.skin):
		mi.skin = res.skin
	mi.mesh = res.mesh
	return mi


## Hides and lets go of every part that `shown` (mesh ids) does not list; never the body, the eyes or the
## proxy.
func release_unused(shown: Array) -> void:
	for id: String in _meshes:
		if is_part(id) and not shown.has(id):
			(_meshes[id] as MeshInstance3D).visible = false
			_release(id)


## The ids of the parts loaded on this model, sorted.
func loaded_parts() -> PackedStringArray:
	var out := PackedStringArray()
	for id: String in _meshes:
		if is_part(id) and (_meshes[id] as MeshInstance3D).mesh != null:
			out.append(id)
	out.sort()
	return out


func _release(id: String) -> void:
	var mi: MeshInstance3D = _meshes.get(id)
	if mi == null or mi.mesh == null:
		return
	GiantModel._keep_recent(str(index.meshes[id][PART_PATH]), mi.mesh)
	mi.mesh = null


func _on_part_visibility(id: String) -> void:
	var mi: MeshInstance3D = _meshes.get(id)
	if mi == null:
		return
	if mi.visible:
		ensure_part(id)
	else:
		_release(id)


## {"mesh": Mesh, "skin": Skin} of a part's glTF, shared by every model that shows it; {} when the file
## is missing or holds no skinned mesh.
static func load_part(path: String) -> Dictionary:
	var hit: Dictionary = _part_cache.get(path, {})
	if not hit.is_empty():
		var mesh := (hit.mesh as WeakRef).get_ref() as Mesh
		if mesh != null:
			return {"mesh": mesh, "skin": hit.skin}
	if not ResourceLoader.exists(path):
		push_warning("GiantModel: the part %s is missing (tools/giant/build_giant.py writes it)" % path)
		return {}
	var scene := load(path) as PackedScene
	var inst := scene.instantiate() if scene != null else null
	var out := {}
	if inst != null:
		for n in inst.find_children("*", "MeshInstance3D", true, false):
			var src := n as MeshInstance3D
			if src.mesh != null and src.skin != null:
				out = {"mesh": src.mesh, "skin": src.skin}
				break
		inst.free()
	if out.is_empty():
		push_warning("GiantModel: the part %s holds no skinned mesh" % path)
		return {}
	_part_loads += 1
	_part_cache[path] = {"mesh": weakref(out.mesh), "skin": out.skin}
	_drop_at_exit()
	return out


## The shared tables hold resources: they are emptied when the tree goes, so nothing is left at exit.
static func _drop_at_exit() -> void:
	if _exit_hooked:
		return
	var tree := Engine.get_main_loop() as SceneTree
	if tree != null and tree.root != null:
		_exit_hooked = true
		tree.root.tree_exiting.connect(GiantModel._drop_all)


static func _drop_all() -> void:
	_part_recent.clear()
	_part_cache.clear()
	_exit_hooked = false


static func _keep_recent(path: String, mesh: Mesh) -> void:
	for i in range(_part_recent.size() - 1, -1, -1):
		if str(_part_recent[i][0]) == path:
			_part_recent.remove_at(i)
	_part_recent.append([path, mesh, GiantModel.part_cost(mesh)])
	var total := 0
	for r: Array in _part_recent:
		total += int(r[2])
	while _part_recent.size() > PART_KEEP or (total > PART_KEEP_BYTES and _part_recent.size() > 1):
		total -= int(_part_recent[0][2])
		_part_recent.pop_front()


## A mesh's buffers in bytes, roughly and without reading them back (mesh_bytes does): 40 bytes a vertex
## (position, normal, tangent, colour, UV, four bones and weights) and its indices with their LODs.
static func part_cost(mesh: Mesh) -> int:
	if mesh == null or mesh.get_surface_count() == 0:
		return 0
	return mesh.surface_get_array_len(0) * 40 + mesh.surface_get_array_index_len(0) * 3


## True when two skins bind the same bones by name in the same order with the same poses.
static func same_binds(a: Skin, b: Skin) -> bool:
	if a == b:
		return true
	if a == null or b == null or a.get_bind_count() != b.get_bind_count():
		return false
	for i in a.get_bind_count():
		if a.get_bind_name(i) != b.get_bind_name(i) or not a.get_bind_pose(i).is_equal_approx(b.get_bind_pose(i)):
			return false
	return true


## {"loads": parts read from disk so far, "alive": parts some model or the recent list holds,
## "recent": the paths kept after their last model let go}.
static func part_stats() -> Dictionary:
	var alive := 0
	for path: String in _part_cache:
		if (_part_cache[path].mesh as WeakRef).get_ref() != null:
			alive += 1
	var recent := PackedStringArray()
	for r: Array in _part_recent:
		recent.append(str(r[0]))
	return {"loads": _part_loads, "alive": alive, "recent": recent}


## The bytes of a mesh's vertex, attribute, skin and index buffers, its LODs' indices included (what the
## renderer keeps for it; plan M11 §2.12's "mesh buffers").
static func mesh_bytes(mesh: Mesh) -> int:
	if mesh == null:
		return 0
	var total := 0
	for s in mesh.get_surface_count():
		var d: Dictionary = RenderingServer.mesh_get_surface(mesh.get_rid(), s)
		for k: String in ["vertex_data", "attribute_data", "skin_data", "index_data"]:
			total += (d.get(k, PackedByteArray()) as PackedByteArray).size()
		for lod: Variant in d.get("lods", []):
			total += ((lod as Dictionary).get("index_data", PackedByteArray()) as PackedByteArray).size()
	return total


## The mesh buffers this model holds now: the body, the eyes, the shadow proxy and the loaded parts.
func resident_bytes() -> int:
	var total := GiantModel.mesh_bytes(shadow_proxy().mesh) if shadow_proxy() != null else 0
	for id: String in _meshes:
		total += GiantModel.mesh_bytes((_meshes[id] as MeshInstance3D).mesh)
	return total


## The mesh buffers the recent list keeps loaded beyond what models show.
static func recent_bytes() -> int:
	var total := 0
	for r: Array in _part_recent:
		total += GiantModel.mesh_bytes(r[1] as Mesh)
	return total


## Drops the recent list (tests and benches that count what is loaded).
static func clear_recent_parts() -> void:
	_part_recent.clear()


## The one Skeleton3D of the model (71 bones: the 53 of the game_engine rig and the 18 leaf bones of the
## index's `chains`).
func skeleton() -> Skeleton3D:
	if not _bound:
		_bind()
	return _skeleton


## The MeshInstance3D of an index mesh id ("Body_Torso", "Hair_long_back", "Garment_tunic_core"); null
## for an unknown id.
func mesh(id: String) -> MeshInstance3D:
	if not _bound:
		_bind()
	return _meshes.get(id)


## The meshes of one index category ("body", "eyes", "hair", "beard", "garment"), in id order.
func meshes(category: String) -> Array[MeshInstance3D]:
	if not _bound:
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


## Plays the idle clip (P43's: breathing, the arms hanging relaxed, a 2 s loop) on a model that stands by
## itself: the creator's preview (plan M10 §2.10). Its AnimationPlayer is made here at run time and never
## saved (§2.5). Without the clips, and on the player's model (SkinnedRig's AnimationTree poses that one),
## the model stands in pose_relaxed() instead. Returns true when the clip plays.
func play_idle() -> bool:
	var sk := skeleton()
	var lib := SkinnedRig.clip_library()
	if sk == null or lib == null or not lib.has_animation(IDLE_CLIP) or has_node("AnimationTree"):
		pose_relaxed()
		return false
	var player := get_node_or_null(IDLE_PLAYER) as AnimationPlayer
	if player == null:
		player = AnimationPlayer.new()
		player.name = IDLE_PLAYER
		add_child(player)
		player.root_node = player.get_path_to(sk.get_parent().get_parent())
		player.add_animation_library(SkinnedRig.LIBRARY, lib)
	player.play(String(SkinnedRig.LIBRARY) + "/" + IDLE_CLIP)
	return true


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
