extends RefCounted
## Builder: the wolf (scenes/enemies/wolf.tscn) - a 0.9 m quadruped on a QuadrupedRig, with
## Visual/LodProxy for AI LOD tier 2. Gameplay numbers live in data/enemies/wolf.json.

const S_WOLF := "res://scripts/actors/wolf_enemy.gd"
const S_QUAD_RIG := "res://scripts/presentation/quadruped_rig.gd"
const PATH := "res://scenes/enemies/wolf.tscn"


static func build_all(kit: SceneKit) -> void:
	kit.add_material("wolf_fur", Color(0.43, 0.41, 0.38), 0.95)
	kit.add_material("wolf_dark", Color(0.21, 0.19, 0.18), 0.9)
	kit.add_material("wolf_eye", Color(0.95, 0.74, 0.22), 0.4)
	kit.save(build_wolf(kit), PATH)


static func build_wolf(kit: SceneKit) -> Node:
	var root := CharacterBody3D.new()
	root.name = "Wolf"
	kit.scripted(root, S_WOLF, {"entity_id": "wolf_01"})
	root.collision_layer = SceneKit.L_ACTORS
	root.collision_mask = SceneKit.ACTOR_MASK
	var cs := CollisionShape3D.new()
	cs.name = "BodyShape"
	var cap := CapsuleShape3D.new()
	cap.radius = 0.4
	cap.height = 0.9
	cs.shape = cap
	cs.position = Vector3(0, 0.45, 0)
	root.add_child(cs)
	root.add_child(kit.combat_entity("wolf_01", "enemy.wolf", 2))
	var anchors := kit.n3("Anchors")
	anchors.add_child(kit.marker("Torso", Vector3(0, 0.55, 0)))
	root.add_child(anchors)
	var hb := kit.n3("Hurtboxes")
	var head_shape := SphereShape3D.new()
	head_shape.radius = 0.18
	hb.add_child(kit.hurtbox("Head", "head", head_shape, Vector3(0, 0.64, -0.55)))
	hb.add_child(kit.hurtbox("Body", "torso", kit.box_shape(Vector3(0.42, 0.42, 0.95)), Vector3(0, 0.52, 0)))
	hb.add_child(kit.hurtbox("Legs", "legs", kit.box_shape(Vector3(0.38, 0.34, 0.85)), Vector3(0, 0.17, 0)))
	root.add_child(hb)
	var agent := NavigationAgent3D.new()
	agent.name = "NavAgent"
	root.add_child(agent)
	var visual := kit.n3("Visual")
	kit.scripted(visual, S_QUAD_RIG, {"body_path": NodePath("Body"), "head_path": NodePath("Body/Head"),
		"tail_path": NodePath("Body/Tail"), "leg_fl_path": NodePath("Body/LegFL"),
		"leg_fr_path": NodePath("Body/LegFR"), "leg_bl_path": NodePath("Body/LegBL"),
		"leg_br_path": NodePath("Body/LegBR")})
	var body := kit.n3("Body")
	visual.add_child(body)
	body.add_child(kit.box("Torso", Vector3(0.36, 0.34, 0.86), Vector3(0, 0.55, 0.04), "wolf_fur"))
	body.add_child(kit.box("Chest", Vector3(0.4, 0.4, 0.3), Vector3(0, 0.56, -0.3), "wolf_fur"))
	body.add_child(kit.box("Ruff", Vector3(0.42, 0.18, 0.2), Vector3(0, 0.74, -0.34), "wolf_dark"))
	var head := kit.n3("Head", Vector3(0, 0.64, -0.44))
	head.add_child(kit.box("Skull", Vector3(0.26, 0.24, 0.26), Vector3(0, 0.04, -0.1), "wolf_fur"))
	head.add_child(kit.box("Snout", Vector3(0.14, 0.12, 0.22), Vector3(0, -0.02, -0.32), "wolf_dark"))
	head.add_child(kit.box("Jaw", Vector3(0.12, 0.05, 0.18), Vector3(0, -0.09, -0.29), "wolf_dark"))
	head.add_child(kit.box("EarL", Vector3(0.06, 0.12, 0.05), Vector3(-0.08, 0.2, -0.04), "wolf_dark"))
	head.add_child(kit.box("EarR", Vector3(0.06, 0.12, 0.05), Vector3(0.08, 0.2, -0.04), "wolf_dark"))
	head.add_child(kit.box("EyeL", Vector3(0.04, 0.04, 0.02), Vector3(-0.07, 0.08, -0.23), "wolf_eye"))
	head.add_child(kit.box("EyeR", Vector3(0.04, 0.04, 0.02), Vector3(0.07, 0.08, -0.23), "wolf_eye"))
	body.add_child(head)
	var tail := kit.n3("Tail", Vector3(0, 0.64, 0.46))
	var tail_mesh := kit.box("Brush", Vector3(0.09, 0.09, 0.44), Vector3(0, -0.07, 0.2), "wolf_fur")
	tail_mesh.rotation_degrees = Vector3(20, 0, 0)
	tail.add_child(tail_mesh)
	body.add_child(tail)
	for leg_name: String in ["LegFL", "LegFR", "LegBL", "LegBR"]:
		var x := -0.12 if leg_name.ends_with("L") else 0.12
		var z := -0.3 if leg_name.begins_with("LegF") else 0.3
		var hip := kit.n3(leg_name, Vector3(x, 0.42, z))
		hip.add_child(kit.box("Leg", Vector3(0.1, 0.4, 0.1), Vector3(0, -0.2, 0), "wolf_fur"))
		hip.add_child(kit.box("Paw", Vector3(0.12, 0.06, 0.15), Vector3(0, -0.39, -0.03), "wolf_dark"))
		body.add_child(hip)
	# AI LOD tier 2 shows this single box instead of the rig (EnemyActor.set_lod_tier).
	visual.add_child(kit.lod_proxy(Vector3(0.42, 0.62, 1.0), Vector3(0, 0.36, 0), "wolf_fur"))
	root.add_child(visual)
	return root
