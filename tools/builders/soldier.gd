extends RefCounted
## Builder: the soldier (scenes/enemies/soldier.tscn): the soldier's gameplay body (P04: capsule, hurtboxes,
## anchors) and, since P60, a realistic person as its Visual (people_models.gd's person_visual).

const S_SOLDIER := "res://scripts/actors/soldier_enemy.gd"
const PATH := "res://scenes/enemies/soldier.tscn"
const PEOPLE := preload("res://tools/builders/people_models.gd")


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
	# P60 (plan M11 §2.9): a realistic person (PersonRig on P59's soldier role); the brain's pivots stay, without
	# meshes. The record's body key picks the variant, the palette and the gear (enemy.soldier: a sword).
	var visual := PEOPLE.person_visual(kit, "person_role.soldier", ["sword"],
		{"idle_arm_pose": Vector2(15, -70), "block_pose": Vector2(-30, 10)})
	root.add_child(visual)
	return root
