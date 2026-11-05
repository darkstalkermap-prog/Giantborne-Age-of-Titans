extends RefCounted
## Builder: the practice dummy and the breakable wooden fence
## (scenes/world/practice_dummy.tscn, scenes/world/fence_wood.tscn).

const S_DUMMY := "res://scripts/actors/practice_dummy.gd"
const S_FENCE := "res://scripts/world/breakable_prop.gd"
const DUMMY_PATH := "res://scenes/world/practice_dummy.tscn"
const FENCE_PATH := "res://scenes/world/fence_wood.tscn"


static func build_all(kit: SceneKit) -> void:
	kit.save(build_dummy(kit), DUMMY_PATH)
	# P17b (draw calls): the fence's posts and rails as one mesh per material (SceneKit.merge_meshes),
	# its Intact and Broken groups merged apart so they still show and hide as before. The dummy
	# keeps its parts (PracticeDummy flashes the materials of each).
	var fence := build_fence(kit)
	for group: String in ["Intact", "Broken"]:
		kit.merge_meshes(fence.get_node(group) as Node3D, PackedStringArray(), PackedStringArray(["scenery"]))
	kit.save(fence, FENCE_PATH)


static func build_dummy(kit: SceneKit) -> Node:
	var root := StaticBody3D.new()
	root.name = "PracticeDummy"
	kit.scripted(root, S_DUMMY, {"entity_id": "dummy_01"})
	root.collision_layer = SceneKit.L_ACTORS
	root.collision_mask = 0
	var cs := CollisionShape3D.new()
	cs.name = "Shape"
	var cyl := CylinderShape3D.new()
	cyl.radius = 0.35
	cyl.height = 2.2
	cs.shape = cyl
	cs.position = Vector3(0, 1.1, 0)
	root.add_child(cs)
	root.add_child(kit.combat_entity("dummy_01", "prop.practice_dummy", 0))
	var anchors := kit.n3("Anchors")
	anchors.add_child(kit.marker("Torso", Vector3(0, 1.45, 0)))
	root.add_child(anchors)
	var hb := kit.n3("Hurtboxes")
	hb.add_child(kit.hurtbox("Body", "torso", kit.box_shape(Vector3(0.9, 1.3, 0.5)), Vector3(0, 1.45, 0)))
	hb.add_child(kit.hurtbox("Post", "legs", kit.box_shape(Vector3(0.3, 0.9, 0.3)), Vector3(0, 0.45, 0)))
	root.add_child(hb)
	var visual := kit.n3("Visual")
	visual.add_child(kit.cyl("Base", 0.5, 0.55, 0.15, Vector3(0, 0.075, 0), "wood_dark"))
	visual.add_child(kit.cyl("Post", 0.11, 0.13, 2.0, Vector3(0, 1.0, 0), "wood"))
	visual.add_child(kit.box("Crossbar", Vector3(1.4, 0.14, 0.14), Vector3(0, 1.7, 0), "wood"))
	visual.add_child(kit.box("Sack", Vector3(0.8, 0.9, 0.42), Vector3(0, 1.35, 0), "sack"))
	visual.add_child(kit.sphere("Head", 0.27, Vector3(0, 2.02, 0), "sack"))
	root.add_child(visual)
	return root


static func build_fence(kit: SceneKit) -> Node:
	var root := StaticBody3D.new()
	root.name = "FenceWood"
	kit.scripted(root, S_FENCE, {"world_id": "sandbox.fence_01"})
	root.collision_layer = SceneKit.L_BREAKABLE
	root.collision_mask = 0
	var cs := CollisionShape3D.new()
	cs.name = "BlockShape"
	cs.shape = kit.box_shape(Vector3(8.0, 1.6, 0.3))
	cs.position = Vector3(0, 0.8, 0)
	root.add_child(cs)
	root.add_child(kit.combat_entity("sandbox.fence_01", "prop.fence_wood", 0, "../Anchors/Center"))
	var anchors := kit.n3("Anchors")
	anchors.add_child(kit.marker("Center", Vector3(0, 0.9, 0)))
	root.add_child(anchors)
	var hb := kit.n3("Hurtboxes")
	hb.add_child(kit.hurtbox("Panel", "body", kit.box_shape(Vector3(8.0, 1.6, 0.6)), Vector3(0, 0.8, 0)))
	root.add_child(hb)
	var intact := kit.n3("Intact")
	var broken := kit.n3("Broken")
	for i in 5:
		var x := -4.0 + 2.0 * i
		intact.add_child(kit.box("Post%d" % i, Vector3(0.22, 1.7, 0.22), Vector3(x, 0.85, 0), "wood_dark"))
		broken.add_child(kit.box("Stump%d" % i, Vector3(0.22, 0.45, 0.22), Vector3(x, 0.22, 0), "wood_dark"))
	intact.add_child(kit.box("RailLow", Vector3(8.2, 0.16, 0.1), Vector3(0, 0.6, 0), "wood"))
	intact.add_child(kit.box("RailHigh", Vector3(8.2, 0.16, 0.1), Vector3(0, 1.25, 0), "wood"))
	broken.visible = false
	root.add_child(intact)
	root.add_child(broken)
	return root
