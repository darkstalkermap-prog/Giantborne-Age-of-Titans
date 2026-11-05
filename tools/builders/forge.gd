extends RefCounted
## Builder: the forge of P12 (plan §2.12, §3.14 design 6): scenes/world/forge.tscn, an anvil and a
## hearth of boxes sized for a giant, with the Forge interactable on the root.
##   Forge (Node3D, Forge)        world_id / display_name / requires_flags / requires_flag_values
##                                are set per placed instance (the Valley: valley.village.forge
##                                with the help outcomes, valley.ruins.giantforge open)
##     Hearth (StaticBody3D, WORLD)  a stone hearth with a chimney, 3 m behind the root
##       Fire                         the glowing coals (visual only)
##     Anvil (StaticBody3D, WORLD)   an iron anvil on a stone block, 2 m in front of the hearth
## The root is where the giant interacts from (radius_m 4.5 from its capsule edge); the forge faces
## -Z (the anvil side).

const S_FORGE := "res://scripts/world/forge.gd"
const PATH := "res://scenes/world/forge.tscn"


static func build_all(kit: SceneKit) -> void:
	_materials(kit)
	kit.save(build_forge(kit), PATH)


static func _materials(kit: SceneKit) -> void:
	kit.add_material("forge_stone", Color(0.30, 0.29, 0.28), 0.95)
	kit.add_material("forge_iron", Color(0.20, 0.21, 0.23), 0.45, 0.6)
	var fire := kit.add_material("forge_fire", Color(1.0, 0.45, 0.12), 0.4)
	fire.emission_enabled = true
	fire.emission = Color(1.0, 0.42, 0.10)
	fire.emission_energy_multiplier = 2.0
	if kit.out_root == "":
		ResourceSaver.save(fire, "%s/forge_fire.tres" % SceneKit.MAT_DIR, ResourceSaver.FLAG_CHANGE_PATH)


static func build_forge(kit: SceneKit) -> Node:
	var root := kit.n3("Forge")
	kit.scripted(root, S_FORGE, {"world_id": "valley.ruins.giantforge", "display_name": "Giantforge",
		"prompt": "Reforge", "radius_m": 4.5, "priority": 45})
	var hearth := StaticBody3D.new()
	hearth.name = "Hearth"
	hearth.position = Vector3(0, 0, 3.0)
	hearth.collision_layer = SceneKit.L_WORLD
	hearth.collision_mask = 0
	hearth.add_child(_shape("Base", Vector3(4.2, 1.6, 3.0), Vector3(0, 0.8, 0)))
	hearth.add_child(_shape("Chimney", Vector3(1.8, 4.8, 1.8), Vector3(0, 4.0, 0.5)))
	hearth.add_child(kit.box("BaseMesh", Vector3(4.2, 1.6, 3.0), Vector3(0, 0.8, 0), "forge_stone"))
	hearth.add_child(kit.box("Lip", Vector3(4.4, 0.25, 3.2), Vector3(0, 1.72, 0), "forge_stone"))
	hearth.add_child(kit.box("ChimneyMesh", Vector3(1.8, 4.8, 1.8), Vector3(0, 4.0, 0.5), "forge_stone"))
	var fire := kit.n3("Fire", Vector3(0, 1.9, -0.3))
	fire.add_child(kit.box("Coals", Vector3(2.6, 0.3, 1.6), Vector3.ZERO, "forge_fire"))
	fire.add_child(kit.box("Flame", Vector3(1.2, 0.8, 0.6), Vector3(0, 0.5, 0.1), "forge_fire"))
	hearth.add_child(fire)
	root.add_child(hearth)
	var anvil := StaticBody3D.new()
	anvil.name = "Anvil"
	anvil.position = Vector3(0, 0, 0.8)
	anvil.collision_layer = SceneKit.L_WORLD
	anvil.collision_mask = 0
	anvil.add_child(_shape("Block", Vector3(1.4, 1.1, 1.0), Vector3(0, 0.55, 0)))
	anvil.add_child(_shape("Top", Vector3(2.4, 0.5, 0.9), Vector3(0, 1.35, 0)))
	anvil.add_child(kit.box("BlockMesh", Vector3(1.4, 1.1, 1.0), Vector3(0, 0.55, 0), "forge_stone"))
	anvil.add_child(kit.box("Waist", Vector3(0.9, 0.3, 0.7), Vector3(0, 1.0, 0), "forge_iron"))
	anvil.add_child(kit.box("TopMesh", Vector3(2.4, 0.5, 0.9), Vector3(0, 1.35, 0), "forge_iron"))
	var horn := kit.cyl("Horn", 0.05, 0.42, 1.1, Vector3(1.65, 1.35, 0), "forge_iron")
	horn.rotation_degrees = Vector3(0, 0, 90)
	anvil.add_child(horn)
	root.add_child(anvil)
	return root


static func _shape(node_name: String, size: Vector3, pos: Vector3) -> CollisionShape3D:
	var cs := CollisionShape3D.new()
	cs.name = node_name
	var shape := BoxShape3D.new()
	shape.size = size
	cs.shape = shape
	cs.position = pos
	return cs
