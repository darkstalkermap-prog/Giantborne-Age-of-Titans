extends RefCounted
## Builder: the player giant (scenes/player/giant.tscn).

const S_GIANT := "res://scripts/actors/giant_player.gd"
const S_CAMERA := "res://scripts/presentation/camera_rig.gd"
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
	kit.scripted(visual, SceneKit.S_RIG, {"weapon_arm_path": NodePath("Body/ShoulderR"),
		"off_arm_path": NodePath("Body/ShoulderL"), "leg_left_path": NodePath("Body/HipL"),
		"leg_right_path": NodePath("Body/HipR"), "torso_path": NodePath("Body/Torso"),
		"body_path": NodePath("Body"), "stride_length_m": 1.6})
	var body := kit.n3("Body")
	visual.add_child(body)
	for side in [-1.0, 1.0]:
		var hip := kit.n3("HipL" if side < 0 else "HipR", Vector3(0.32 * side, 1.6, 0))
		hip.add_child(kit.box("Leg", Vector3(0.45, 1.5, 0.5), Vector3(0, -0.75, 0), "giant_tunic"))
		hip.add_child(kit.box("Foot", Vector3(0.5, 0.16, 0.72), Vector3(0, -1.52, -0.1), "giant_belt"))
		body.add_child(hip)
	var torso := kit.n3("Torso", Vector3(0, 1.6, 0))
	# Chest and belt are hidden in first person too: from the eye they would cover the ground
	# (and any human) within ~2.6 m of the giant and the crosshair when looking down.
	var fp := SceneKit.FP_HIDDEN
	torso.add_child(kit.box("Chest", Vector3(1.3, 1.45, 0.8), Vector3(0, 0.73, 0), "giant_tunic", fp))
	torso.add_child(kit.box("Belt", Vector3(1.36, 0.18, 0.86), Vector3(0, 0.1, 0), "giant_belt", fp))
	torso.add_child(kit.box("Neck", Vector3(0.36, 0.2, 0.36), Vector3(0, 1.52, 0), "giant_skin", fp))
	torso.add_child(kit.box("Head", Vector3(0.62, 0.62, 0.62), Vector3(0, 1.74 + 0.0, 0), "giant_skin", fp))
	torso.add_child(kit.box("Hair", Vector3(0.66, 0.16, 0.66), Vector3(0, 2.08, 0.02), "giant_hair", fp))
	torso.add_child(kit.box("Brow", Vector3(0.5, 0.08, 0.06), Vector3(0, 1.86, -0.32), "giant_hair", fp))
	torso.add_child(kit.box("EyeL", Vector3(0.08, 0.08, 0.04), Vector3(-0.13, 1.78, -0.32), "eyes", fp))
	torso.add_child(kit.box("EyeR", Vector3(0.08, 0.08, 0.04), Vector3(0.13, 1.78, -0.32), "eyes", fp))
	body.add_child(torso)
	for side in [-1.0, 1.0]:
		var shoulder := kit.n3("ShoulderL" if side < 0 else "ShoulderR", Vector3(0.82 * side, 2.9, 0))
		shoulder.basis = SceneKit.arm_basis(12.0 * side, -78.0)
		shoulder.add_child(kit.box("UpperArm", Vector3(0.34, 0.34, 0.8), Vector3(0, 0, -0.4), "giant_skin"))
		shoulder.add_child(kit.box("Forearm", Vector3(0.3, 0.3, 0.7), Vector3(0, 0, -1.15), "giant_skin"))
		shoulder.add_child(kit.box("Hand", Vector3(0.38, 0.38, 0.38), Vector3(0, 0, -1.5), "giant_skin"))
		if side > 0:
			var club := kit.cyl("Club", 0.24, 0.11, 1.85, Vector3(0, 0, -1.5 - 0.925), "club")
			club.rotation_degrees = Vector3(-90, 0, 0)
			shoulder.add_child(club)
		body.add_child(shoulder)
	# P22 (decision 9): one vertex-coloured mesh per pivot with the rig material. The club stays its
	# own mesh (the weapon visual hides it), and the chest, the belt and the head (render layer 2,
	# which the camera culls in first person) stay three meshes of their own: 8 meshes, was 19.
	kit.merge_rig(body, {
		"Torso": [["Chest", ["Chest"]], ["Belt", ["Belt"]], ["Head", ["Neck", "Head", "Hair", "Brow", "EyeL", "EyeR"]]],
		"ShoulderR": [["Club", ["Club"]]],
	})
	# Where each hand is (the grab socket's visible grip, tests), now that the hand box is merged.
	for shoulder_name: String in ["ShoulderL", "ShoulderR"]:
		body.get_node(shoulder_name).add_child(kit.marker("Hand", Vector3(0, 0, -1.5)))
	root.add_child(visual)
	var rig := kit.n3("CameraRig")
	kit.scripted(rig, S_CAMERA)
	var cam := Camera3D.new()
	cam.name = "Camera3D"
	cam.fov = 75.0
	rig.add_child(cam)
	root.add_child(rig)
	return root
