extends RefCounted
## Builder: the soldier (scenes/enemies/soldier.tscn).

const S_SOLDIER := "res://scripts/actors/soldier_enemy.gd"
const PATH := "res://scenes/enemies/soldier.tscn"


static func build_all(kit: SceneKit) -> void:
	kit.save(build_soldier(kit), PATH)


static func build_soldier(kit: SceneKit) -> Node:
	var root := CharacterBody3D.new()
	root.name = "Soldier"
	kit.scripted(root, S_SOLDIER, {"entity_id": "soldier_01"})
	root.collision_layer = SceneKit.L_ACTORS
	root.collision_mask = SceneKit.ACTOR_MASK
	var cs := CollisionShape3D.new()
	cs.name = "BodyShape"
	var cap := CapsuleShape3D.new()
	cap.radius = 0.35
	cap.height = 1.8
	cs.shape = cap
	cs.position = Vector3(0, 0.9, 0)
	root.add_child(cs)
	root.add_child(kit.combat_entity("soldier_01", "enemy.soldier", 2))
	var anchors := kit.n3("Anchors")
	anchors.add_child(kit.marker("Torso", Vector3(0, 1.15, 0)))
	# P07: where a giant's fist closes around the soldier (attachment profile torso_fist).
	anchors.add_child(kit.marker("Grab", Vector3(0, 1.2, 0)))
	root.add_child(anchors)
	var hb := kit.n3("Hurtboxes")
	var head_shape := SphereShape3D.new()
	head_shape.radius = 0.17
	hb.add_child(kit.hurtbox("Head", "head", head_shape, Vector3(0, 1.63, 0)))
	hb.add_child(kit.hurtbox("Torso", "torso", kit.box_shape(Vector3(0.55, 0.65, 0.32)), Vector3(0, 1.15, 0)))
	hb.add_child(kit.hurtbox("Legs", "legs", kit.box_shape(Vector3(0.45, 0.85, 0.3)), Vector3(0, 0.42, 0)))
	root.add_child(hb)
	var agent := NavigationAgent3D.new()
	agent.name = "NavAgent"
	root.add_child(agent)
	var visual := kit.n3("Visual")
	kit.scripted(visual, SceneKit.S_RIG, {"weapon_arm_path": NodePath("Body/ShoulderR"),
		"off_arm_path": NodePath("Body/ShoulderL"), "leg_left_path": NodePath("Body/HipL"),
		"leg_right_path": NodePath("Body/HipR"), "torso_path": NodePath("Body/Torso"),
		"body_path": NodePath("Body"), "stride_length_m": 0.9, "leg_swing_rad": 0.6,
		"idle_arm_pose": Vector2(15, -70), "block_pose": Vector2(-30, 10)})
	var body := kit.n3("Body")
	visual.add_child(body)
	for side in [-1.0, 1.0]:
		var hip := kit.n3("HipL" if side < 0 else "HipR", Vector3(0.12 * side, 0.85, 0))
		hip.add_child(kit.box("Leg", Vector3(0.2, 0.82, 0.24), Vector3(0, -0.41, 0), "soldier_mail"))
		hip.add_child(kit.box("Boot", Vector3(0.22, 0.12, 0.32), Vector3(0, -0.8, -0.04), "giant_belt"))
		body.add_child(hip)
	var torso := kit.n3("Torso", Vector3(0, 0.85, 0))
	torso.add_child(kit.box("Mail", Vector3(0.5, 0.62, 0.3), Vector3(0, 0.31, 0), "soldier_mail"))
	torso.add_child(kit.box("Tabard", Vector3(0.52, 0.66, 0.32), Vector3(0, 0.28, 0), "soldier_tabard"))
	torso.add_child(kit.box("Head", Vector3(0.24, 0.26, 0.26), Vector3(0, 0.78, 0), "soldier_skin"))
	torso.add_child(kit.box("Helmet", Vector3(0.3, 0.16, 0.32), Vector3(0, 0.92, 0), "steel"))
	torso.add_child(kit.box("Nasal", Vector3(0.04, 0.16, 0.04), Vector3(0, 0.8, -0.15), "steel"))
	body.add_child(torso)
	for side in [-1.0, 1.0]:
		var shoulder := kit.n3("ShoulderL" if side < 0 else "ShoulderR", Vector3(0.25 * side, 1.42, 0))
		shoulder.basis = SceneKit.arm_basis(15.0 * side, -70.0)
		shoulder.add_child(kit.box("UpperArm", Vector3(0.13, 0.13, 0.3), Vector3(0, 0, -0.15), "soldier_mail"))
		shoulder.add_child(kit.box("Forearm", Vector3(0.12, 0.12, 0.25), Vector3(0, 0, -0.42), "soldier_skin"))
		if side > 0:
			shoulder.add_child(kit.box("Grip", Vector3(0.05, 0.05, 0.14), Vector3(0, 0, -0.5), "giant_belt"))
			shoulder.add_child(kit.box("Guard", Vector3(0.22, 0.04, 0.05), Vector3(0, 0, -0.56), "steel"))
			shoulder.add_child(kit.box("Blade", Vector3(0.07, 0.02, 0.95), Vector3(0, 0, -0.5 - 0.475), "steel"))
		body.add_child(shoulder)
	# P22 (decision 9): one vertex-coloured mesh per pivot, the sword its own: 6 meshes, was 16.
	kit.merge_rig(body, {"ShoulderR": [["Weapon", ["Grip", "Guard", "Blade"]]]})
	# AI LOD tier 2 shows this single box instead of the rig (EnemyActor.set_lod_tier).
	visual.add_child(kit.lod_proxy(Vector3(0.5, 1.8, 0.35), Vector3(0, 0.9, 0), "soldier_tabard"))
	root.add_child(visual)
	return root
