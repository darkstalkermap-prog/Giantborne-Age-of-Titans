extends RefCounted
## Builder (P60; plan M11 §2.9, §3.13 design 5): the people's model and the shared parts of every person's scene.
##
##   * scenes/people/person_model.tscn - a PersonModel root, "People/Skeleton3D" with P59's 23 bones (names,
##     parents and the reference man's rests, read from the soldier's first variant in assets/people/soldier.glb),
##     an empty MeshInstance3D "Mesh" on it, and an AnimationPlayer rooted at the model (the clips' tracks start
##     "People/Skeleton3D:"). No mesh, material or clip is stored: PersonModel puts a variant's mesh, skin and rests
##     on a pooled model at run time (P59's files stay the only copy, in the pack once);
##   * person_visual(): the Visual of a person's scene for soldier.gd, ranged.gd, formations.gd and siege.gd - a
##     PersonRig (its person role, gear and the brain's arm poses), Body with the brain's pivots and no meshes
##     (HipL, HipR, Torso, ShoulderL, ShoulderR: every node path tests and the brain name stays), the hidden
##     Visual/CrowdPoses/<pose> (hold, brace, advance, flee, corpse: empty nodes that take the role's pose meshes at
##     run time) and Visual/LodProxy (a MultiMeshInstance3D: the far mesh at AI LOD tier 2, one instance), hidden.
##   * (A1) scenes/creatures/stoneback.tscn - Stoneback, the quarry titan: a StonebackRig root that loads his model,
##     plates and clips from assets/creatures at run time (no actor, no AI: a later package wraps it); skipped with a
##     note while his files are missing.
## Runs before soldier.gd (tools/build_scenes.gd BUILDERS); skipped with a note while P59's files are missing.

const OUT := "res://scenes/people/person_model.tscn"
const SCRIPT := "res://scripts/presentation/person_model.gd"
const RIG_SCRIPT := "res://scripts/presentation/person_rig.gd"
const SOURCE := "res://assets/people/soldier.glb"
const SOURCE_VARIANT := "soldier_a"
const POSES := ["hold", "brace", "advance", "flee", "corpse"]
const STONEBACK_OUT := "res://scenes/creatures/stoneback.tscn"
const STONEBACK_SCRIPT := "res://scripts/presentation/stoneback_rig.gd"
const STONEBACK_SOURCE := "res://assets/creatures/stoneback.glb"


static func build_all(kit: SceneKit) -> void:
	if not ResourceLoader.exists(SOURCE):
		print("people_models: skipped (%s is missing: run tools/giant/build_people.py)" % SOURCE)
		return
	kit.save(build_model(), OUT)
	if ResourceLoader.exists(STONEBACK_SOURCE):
		kit.save(build_stoneback(), STONEBACK_OUT)
	else:
		print("people_models: stoneback skipped (%s is missing: run tools/giant/build_people.py --stoneback)" % STONEBACK_SOURCE)


## (A1) Stoneback's scene: the rig alone (it instantiates his glTF itself, so the file stays the only copy).
static func build_stoneback() -> Node:
	var root := Node3D.new()
	root.name = "Stoneback"
	root.set_script(load(STONEBACK_SCRIPT))
	return root


## The model scene (see the class notes).
static func build_model() -> Node:
	var src := (load(SOURCE) as PackedScene).instantiate()
	var mi := src.find_child(SOURCE_VARIANT, true, false) as MeshInstance3D
	var from := mi.get_parent() as Skeleton3D
	var root := Node3D.new()
	root.name = "PersonModel"
	root.set_script(load(SCRIPT))
	var people := Node3D.new()
	people.name = "People"
	root.add_child(people)
	var sk := Skeleton3D.new()
	sk.name = "Skeleton3D"
	for i in from.get_bone_count():
		sk.add_bone(from.get_bone_name(i))
	for i in from.get_bone_count():
		sk.set_bone_parent(i, from.get_bone_parent(i))
		sk.set_bone_rest(i, from.get_bone_rest(i))
	sk.reset_bone_poses()
	people.add_child(sk)
	var mesh := MeshInstance3D.new()
	mesh.name = "Mesh"
	mesh.skeleton = NodePath("..")
	sk.add_child(mesh)
	var ap := AnimationPlayer.new()
	ap.name = "AnimationPlayer"
	ap.root_node = NodePath("..")
	ap.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	root.add_child(ap)
	src.free()
	return root


## A person's Visual (see the class notes): `person_role` and `gear` the scene's default body (the record's `body`
## wins), `rig_props` the brain's exports (arm poses, stride), `pose_names` the crowd poses.
static func person_visual(kit: SceneKit, person_role: String, gear: Array, rig_props: Dictionary) -> Node3D:
	var visual := kit.n3("Visual")
	var props := {"weapon_arm_path": NodePath("Body/ShoulderR"), "off_arm_path": NodePath("Body/ShoulderL"),
		"leg_left_path": NodePath("Body/HipL"), "leg_right_path": NodePath("Body/HipR"),
		"torso_path": NodePath("Body/Torso"), "body_path": NodePath("Body"), "stride_length_m": 0.9,
		"leg_swing_rad": 0.6, "person_role": person_role, "gear": PackedStringArray(gear)}
	props.merge(rig_props, true)
	kit.scripted(visual, RIG_SCRIPT, props)
	var body := kit.n3("Body")
	visual.add_child(body)
	for side in [-1.0, 1.0]:
		body.add_child(kit.n3("HipL" if side < 0 else "HipR", Vector3(0.12 * side, 0.85, 0)))
	body.add_child(kit.n3("Torso", Vector3(0, 0.85, 0)))
	var idle: Vector2 = props.get("idle_arm_pose", Vector2(12.0, -78.0))
	var off_idle: Vector2 = props.get("off_idle_pose", Vector2(-10.0, -80.0))
	for side in [-1.0, 1.0]:
		var shoulder := kit.n3("ShoulderL" if side < 0 else "ShoulderR", Vector3(0.25 * side, 1.42, 0))
		var pose: Vector2 = off_idle if side < 0 else idle
		shoulder.basis = SceneKit.arm_basis(pose.x, pose.y)
		body.add_child(shoulder)
	var poses := kit.n3("CrowdPoses")
	poses.visible = false
	for p: String in POSES:
		var pm := MeshInstance3D.new()
		pm.name = p
		poses.add_child(pm)
	visual.add_child(poses)
	var proxy := MultiMeshInstance3D.new()
	proxy.name = "LodProxy"
	proxy.visible = false
	visual.add_child(proxy)
	return visual
