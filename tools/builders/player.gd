extends RefCounted
## Builder: the player giant (scenes/player/giant.tscn). P43 (plan M10 §2.9): the realistic, skinned body
## (Visual/Body/Model, an instance of giant_model.tscn) driven by the pose brain (SkinnedRig); the
## stylized meshes are gone, their pivots stay; the weapon hangs at Visual/Body/WeaponSocket.

const S_GIANT := "res://scripts/actors/giant_player.gd"
const S_CAMERA := "res://scripts/presentation/camera_rig.gd"
## P43: the skinned rig and the realistic model (giant_model.gd builds the model's scene first).
const S_SKINNED_RIG := "res://scripts/presentation/skinned_rig.gd"
const MODEL := "res://scenes/player/giant_model.tscn"
const PATH := "res://scenes/player/giant.tscn"


static func build_all(kit: SceneKit) -> void:
	kit.save(build_giant(kit), PATH)


static func build_giant(kit: SceneKit) -> Node:
	var root := CharacterBody3D.new()
	root.name = "Giant"
	kit.scripted(root, S_GIANT)
	root.collision_layer = SceneKit.L_ACTORS
	root.collision_mask = SceneKit.ACTOR_MASK
	var cs := CollisionShape3D.new()
	cs.name = "BodyShape"
	var cap := CapsuleShape3D.new()
	cap.radius = 0.85
	cap.height = 3.66
	cs.shape = cap
	cs.position = Vector3(0, 1.83, 0)
	root.add_child(cs)
	root.add_child(kit.combat_entity("player", "player.giant", 1))
	var anchors := kit.n3("Anchors")
	anchors.add_child(kit.marker("Torso", Vector3(0, 2.3, 0)))
	root.add_child(anchors)
	var hb := kit.n3("Hurtboxes")
	hb.add_child(kit.hurtbox("Legs", "legs", kit.box_shape(Vector3(1.1, 1.6, 0.7)), Vector3(0, 0.8, 0)))
	hb.add_child(kit.hurtbox("Torso", "torso", kit.box_shape(Vector3(1.4, 1.5, 0.9)), Vector3(0, 2.35, 0)))
	hb.add_child(kit.hurtbox("Head", "head", kit.box_shape(Vector3(0.7, 0.7, 0.7)), Vector3(0, 3.3, 0)))
	root.add_child(hb)
	var visual := kit.n3("Visual")
	# P43 (plan M10 §2.9): the realistic model is the body. Visual's script is SkinnedRig (an ActorRig: the
	# pose brain stays); the brain's pivots and hand markers stay without meshes; the model and the weapon
	# socket join Body. The skinned layers' nodes (AnimationPlayer, AnimationTree, PoseBrainModifier) are
	# made at run time and never saved (an instance's children are never saved, plan §2.5).
	kit.scripted(visual, S_SKINNED_RIG, {"weapon_arm_path": NodePath("Body/ShoulderR"),
		"off_arm_path": NodePath("Body/ShoulderL"), "leg_left_path": NodePath("Body/HipL"),
		"leg_right_path": NodePath("Body/HipR"), "torso_path": NodePath("Body/Torso"),
		"body_path": NodePath("Body"), "stride_length_m": 1.6})
	var body := kit.n3("Body")
	visual.add_child(body)
	for side in [-1.0, 1.0]:
		body.add_child(kit.n3("HipL" if side < 0 else "HipR", Vector3(0.32 * side, 1.6, 0)))
	body.add_child(kit.n3("Torso", Vector3(0, 1.6, 0)))
	for side in [-1.0, 1.0]:
		var shoulder := kit.n3("ShoulderL" if side < 0 else "ShoulderR", Vector3(0.82 * side, 2.9, 0))
		shoulder.basis = SceneKit.arm_basis(12.0 * side, -78.0)
		# where each stylized hand was: the brain's hand point (the grab socket's aim, the headless weapon)
		shoulder.add_child(kit.marker("Hand", Vector3(0, 0, -1.5)))
		body.add_child(shoulder)
	# an edit-state instance: the saved scene keeps the instance alone, so the model's index is always
	# giant_model.tscn's own (a copy saved here would go stale when the model is regenerated)
	var model_path := kit.output_path(MODEL)
	if ResourceLoader.exists(model_path):
		var model := (load(model_path) as PackedScene).instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE)
		model.name = "Model"
		body.add_child(model)
	else:
		push_error("player: %s is missing (tools/builders/giant_model.gd runs before player.gd)" % MODEL)
	# the weapon's parent: at the brain's hand headless, in the fist with the skinned layers (SkinnedRig)
	var socket := kit.n3("WeaponSocket", Vector3(0.82, 2.9, 0) + SceneKit.arm_basis(12.0, -78.0) * Vector3(0, 0, -1.5))
	socket.basis = SceneKit.arm_basis(12.0, -78.0)
	body.add_child(socket)
	root.add_child(visual)
	var rig := kit.n3("CameraRig")
	kit.scripted(rig, S_CAMERA)
	var cam := Camera3D.new()
	cam.name = "Camera3D"
	cam.fov = 75.0
	rig.add_child(cam)
	root.add_child(rig)
	return root
