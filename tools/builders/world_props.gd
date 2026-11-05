extends RefCounted
## Builder: the world props of P08 (plan §2.12, §3.8, §4.3), one scene each under scenes/world/:
##   gate_practice   structural (Intact / Cracked / Broken), 10 m opening, NavLinkThrough
##   gate_fortified  structural, locked until stage 4 (Intact / Breached), NavLinkThrough
##   tree_small      breakable pine (Intact / Broken: a stump and the fallen trunk)
##   ancient_oak     UprootTree (Trunk collision + Visual); the stage-3 tree weapon
##   deadfall        breakable wall of trunks, 14 m wide; TreeWeapon only; NavLinkThrough
##   cart_barricade  breakable carts across a 12 m road (stage 2; opens on a flag); NavLinkThrough
##   cairn           breakable stone stack (projectile category only)
##   crate           breakable crate with loot
##   weapon_rack     WeaponRack (Frame + Display; the weapon mesh is built from data at _ready)
##   item_pickup     ItemPickup (a small chest, no collision)
##   bush, banner    CosmeticProp (Visual only; no collision, no CombatEntity)
## Breakables follow the BreakableProp contract: a StaticBody3D on the breakables layer with a
## CombatEntity (team NEUTRAL), one child per stage visual, Block* collision shapes (removed when
## it breaks), Hurtboxes/*, Anchors/Center and NavLink* (NavigationLink3D, disabled until it
## breaks). Props face -Z; walls of them (gates, barricade, deadfall) span local X, and their
## nav link crosses them along Z. Instances set world_id (and the interactables' ids).

const S_BREAKABLE := "res://scripts/world/breakable_prop.gd"
const S_COSMETIC := "res://scripts/world/cosmetic_prop.gd"
const S_UPROOT := "res://scripts/world/uproot_tree.gd"
const S_RACK := "res://scripts/world/weapon_rack.gd"
const S_PICKUP := "res://scripts/world/item_pickup.gd"
const DIR := "res://scenes/world/"
## Every nav layer (human 1, large 2, giant 4, small giant 8) may use an opened passage.
const ALL_NAV_LAYERS := 15
## The groups of a prop's merged meshes (P17b): LevelRoot's scenery group, so the level's graphics
## preset (scenery_visibility_end_m: 160 m low, 220 m medium in the Valley) hides them far off.
const PROP_GROUPS := ["scenery"]


static func build_all(kit: SceneKit) -> void:
	_materials(kit)
	kit.save(batched(kit, build_gate_practice(kit)), DIR + "gate_practice.tscn")
	kit.save(batched(kit, build_gate_fortified(kit)), DIR + "gate_fortified.tscn")
	kit.save(batched(kit, build_tree_small(kit)), DIR + "tree_small.tscn")
	kit.save(batched(kit, build_ancient_oak(kit)), DIR + "ancient_oak.tscn")
	kit.save(batched(kit, build_deadfall(kit)), DIR + "deadfall.tscn")
	kit.save(batched(kit, build_cart_barricade(kit)), DIR + "cart_barricade.tscn")
	kit.save(batched(kit, build_cairn(kit)), DIR + "cairn.tscn")
	kit.save(batched(kit, build_crate(kit)), DIR + "crate.tscn")
	kit.save(batched(kit, build_weapon_rack(kit)), DIR + "weapon_rack.tscn")
	kit.save(batched(kit, build_item_pickup(kit)), DIR + "item_pickup.tscn")
	kit.save(batched(kit, build_bush(kit)), DIR + "bush.tscn")
	kit.save(batched(kit, build_banner(kit)), DIR + "banner.tscn")


## P17b (draw calls): every visual group of a prop (Frame, Intact, Cracked, Broken, Visual, a
## static body's meshes) merged into one mesh with a surface per material (SceneKit.merge_meshes),
## each group on its own so the stage visuals still show and hide as before; the merged meshes are
## level scenery (PROP_GROUPS: the graphics preset's scenery distance hides them far off). Returns
## `root`.
static func batched(kit: SceneKit, root: Node) -> Node:
	for child in root.get_children():
		if child.get_script() == null and (child.get_class() == "Node3D" or child is StaticBody3D):
			kit.merge_meshes(child as Node3D, PackedStringArray(), PackedStringArray(PROP_GROUPS))
	return root


static func _materials(kit: SceneKit) -> void:
	kit.add_material("gate_wood", Color(0.42, 0.29, 0.17), 0.9)
	kit.add_material("gate_wood_split", Color(0.62, 0.47, 0.30), 0.9)
	kit.add_material("iron", Color(0.30, 0.31, 0.34), 0.5, 0.5)
	kit.add_material("bark", Color(0.33, 0.24, 0.16), 0.95)
	kit.add_material("leaves", Color(0.25, 0.42, 0.20), 0.95)
	kit.add_material("leaves_dark", Color(0.17, 0.32, 0.16), 0.95)
	kit.add_material("cairn_stone", Color(0.56, 0.55, 0.52), 0.95)
	kit.add_material("cart_wood", Color(0.50, 0.36, 0.22), 0.9)
	kit.add_material("banner_cloth", Color(0.62, 0.14, 0.13), 0.9)
	var glow := kit.add_material("pickup_glow", Color(1.0, 0.85, 0.35), 0.3)
	glow.emission_enabled = true
	glow.emission = Color(1.0, 0.78, 0.30)
	glow.emission_energy_multiplier = 1.6
	if kit.out_root == "":
		ResourceSaver.save(glow, "%s/pickup_glow.tres" % SceneKit.MAT_DIR, ResourceSaver.FLAG_CHANGE_PATH)


# --------------------------------------------------------------------------- shared parts

## The root of a breakable or structural prop: StaticBody3D on the breakables layer, its
## BreakableProp script with `world_id`, a CombatEntity (team NEUTRAL) on Anchors/Center.
static func _breakable_root(kit: SceneKit, node_name: String, world_id: String, definition_id: String,
		center: Vector3) -> StaticBody3D:
	var root := StaticBody3D.new()
	root.name = node_name
	kit.scripted(root, S_BREAKABLE, {"world_id": world_id})
	root.collision_layer = SceneKit.L_BREAKABLE
	root.collision_mask = 0
	root.add_child(kit.combat_entity(world_id, definition_id, 0, "../Anchors/Center"))
	var anchors := kit.n3("Anchors")
	anchors.add_child(kit.marker("Center", center))
	root.add_child(anchors)
	return root


static func _block(kit: SceneKit, node_name: String, size: Vector3, pos: Vector3) -> CollisionShape3D:
	var cs := CollisionShape3D.new()
	cs.name = node_name
	cs.shape = kit.box_shape(size)
	cs.position = pos
	return cs


static func _hurtboxes(kit: SceneKit, size: Vector3, pos: Vector3) -> Node3D:
	var hb := kit.n3("Hurtboxes")
	hb.add_child(kit.hurtbox("Body", "body", kit.box_shape(size), pos))
	return hb


## A disabled link across the prop along Z (from +half_depth to -half_depth), for every layer.
static func _nav_link(half_depth: float) -> NavigationLink3D:
	var link := NavigationLink3D.new()
	link.name = "NavLinkThrough"
	link.start_position = Vector3(0, 0, half_depth)
	link.end_position = Vector3(0, 0, -half_depth)
	link.bidirectional = true
	link.navigation_layers = ALL_NAV_LAYERS
	link.enabled = false
	return link


## A cylinder lying along local X (a log), centre `pos`.
static func _log(kit: SceneKit, node_name: String, r: float, length: float, pos: Vector3, mat: String,
		yaw_deg := 0.0) -> MeshInstance3D:
	var mi := kit.cyl(node_name, r, r * 1.1, length, pos, mat)
	mi.rotation_degrees = Vector3(0, yaw_deg, 90)
	return mi


# --------------------------------------------------------------------------- gates

## The practice gate: two 5 m timber leaves (6 m tall) between stone posts, a 10 m opening.
static func build_gate_practice(kit: SceneKit) -> Node:
	var root := _breakable_root(kit, "GatePractice", "valley.ruins.practice_gate", "prop.gate_practice",
		Vector3(0, 3.0, 0))
	root.add_child(_block(kit, "BlockLeaves", Vector3(10.0, 6.0, 0.5), Vector3(0, 3.0, 0)))
	root.add_child(_block(kit, "PostLeft", Vector3(0.9, 6.8, 0.9), Vector3(-5.45, 3.4, 0)))
	root.add_child(_block(kit, "PostRight", Vector3(0.9, 6.8, 0.9), Vector3(5.45, 3.4, 0)))
	root.add_child(_hurtboxes(kit, Vector3(10.0, 6.0, 1.0), Vector3(0, 3.0, 0)))
	var frame := kit.n3("Frame")
	for side in [-1.0, 1.0]:
		frame.add_child(kit.box("Post%s" % ("L" if side < 0 else "R"), Vector3(0.9, 6.8, 0.9),
			Vector3(5.45 * side, 3.4, 0), "stone_dark"))
		frame.add_child(kit.box("Cap%s" % ("L" if side < 0 else "R"), Vector3(1.1, 0.3, 1.1),
			Vector3(5.45 * side, 6.95, 0), "stone"))
	root.add_child(frame)
	var intact := kit.n3("Intact")
	_gate_leaves(kit, intact, 0.0, false)
	root.add_child(intact)
	var cracked := kit.n3("Cracked")
	_gate_leaves(kit, cracked, 4.0, true)
	root.add_child(cracked)
	var broken := kit.n3("Broken")
	for i in 6:
		var x := -4.2 + 1.68 * i
		broken.add_child(kit.box("Stump%d" % i, Vector3(1.2, 0.6 + 0.25 * (i % 3), 0.45),
			Vector3(x, 0.3 + 0.12 * (i % 3), 0), "gate_wood"))
	var fallen := kit.box("FallenLeaf", Vector3(4.6, 0.4, 2.4), Vector3(-1.5, 0.2, -2.2), "gate_wood")
	fallen.rotation_degrees = Vector3(0, 18, 4)
	broken.add_child(fallen)
	root.add_child(broken)
	cracked.visible = false
	broken.visible = false
	root.add_child(_nav_link(3.0))
	return root


## Two gate leaves of vertical planks with iron bands; `lean` (degrees) and `cracked` add a
## sagging leaf, a gap and pale split wood.
static func _gate_leaves(kit: SceneKit, parent: Node3D, lean: float, cracked: bool) -> void:
	for leaf in 2:
		var side := -1.0 if leaf == 0 else 1.0
		var leaf_node := kit.n3("Leaf%d" % leaf, Vector3(2.5 * side, 0, 0))
		if cracked and leaf == 1:
			leaf_node.rotation_degrees = Vector3(0, 0, -lean)
		for p in 5:
			if cracked and leaf == 0 and p == 3:
				continue   # a missing plank
			var mat := "gate_wood_split" if cracked and (p + leaf) % 3 == 0 else "gate_wood"
			leaf_node.add_child(kit.box("Plank%d" % p, Vector3(0.92, 6.0 - 0.2 * (p % 2), 0.4),
				Vector3(-2.0 + 1.0 * p, 3.0, 0), mat))
		for b in 2:
			leaf_node.add_child(kit.box("Band%d" % b, Vector3(4.9, 0.25, 0.48), Vector3(0, 1.4 + 3.2 * b, 0), "iron"))
		parent.add_child(leaf_node)
	if cracked:
		parent.add_child(kit.box("Crack", Vector3(0.12, 4.2, 0.5), Vector3(0.25, 2.6, 0), "wood_dark"))
		for s in 3:
			var splinter := kit.box("Splinter%d" % s, Vector3(0.9, 0.12, 0.12), Vector3(-1.0 + 0.9 * s, 0.1, -0.8), "gate_wood_split")
			splinter.rotation_degrees = Vector3(0, 25.0 * s, 0)
			parent.add_child(splinter)


## The sealed citadel gate: 12 m iron-bound doors between towers. Locked until stage 4.
static func build_gate_fortified(kit: SceneKit) -> Node:
	var root := _breakable_root(kit, "GateFortified", "valley.ruins.citadel_gate", "prop.gate_fortified",
		Vector3(0, 5.0, 0))
	root.add_child(_block(kit, "BlockDoors", Vector3(12.0, 12.0, 1.2), Vector3(0, 6.0, 0)))
	root.add_child(_block(kit, "TowerLeft", Vector3(3.0, 15.0, 3.0), Vector3(-7.5, 7.5, 0)))
	root.add_child(_block(kit, "TowerRight", Vector3(3.0, 15.0, 3.0), Vector3(7.5, 7.5, 0)))
	root.add_child(_hurtboxes(kit, Vector3(12.0, 12.0, 1.8), Vector3(0, 6.0, 0)))
	var frame := kit.n3("Frame")
	for side in [-1.0, 1.0]:
		frame.add_child(kit.box("Tower%s" % ("L" if side < 0 else "R"), Vector3(3.0, 15.0, 3.0),
			Vector3(7.5 * side, 7.5, 0), "stone_dark"))
	frame.add_child(kit.box("Lintel", Vector3(12.0, 2.0, 2.0), Vector3(0, 13.0, 0), "stone_dark"))
	root.add_child(frame)
	var intact := kit.n3("Intact")
	for door in 2:
		var side := -1.0 if door == 0 else 1.0
		intact.add_child(kit.box("Door%d" % door, Vector3(5.9, 12.0, 1.0), Vector3(3.0 * side, 6.0, 0), "wood_dark"))
		for b in 4:
			intact.add_child(kit.box("Band%d_%d" % [door, b], Vector3(6.0, 0.4, 1.1), Vector3(3.0 * side, 1.5 + 3.0 * b, 0), "iron"))
	intact.add_child(kit.box("Bar", Vector3(9.0, 0.6, 0.5), Vector3(0, 6.0, -0.75), "iron"))
	root.add_child(intact)
	var breached := kit.n3("Breached")
	for i in 5:
		breached.add_child(kit.box("Rubble%d" % i, Vector3(2.0, 0.8, 1.6), Vector3(-4.8 + 2.4 * i, 0.4, (i % 2) * 1.2), "wood_dark"))
	breached.visible = false
	root.add_child(breached)
	root.add_child(_nav_link(3.0))
	return root


# --------------------------------------------------------------------------- trees

## A forest pine: trunk and three tiers of needles; broken, a stump and the trunk on the ground.
static func build_tree_small(kit: SceneKit) -> Node:
	var root := _breakable_root(kit, "TreeSmall", "valley.forest.tree_01", "prop.tree_small", Vector3(0, 2.5, 0))
	var cs := CollisionShape3D.new()
	cs.name = "BlockTrunk"
	var cyl := CylinderShape3D.new()
	cyl.radius = 0.4
	cyl.height = 7.0
	cs.shape = cyl
	cs.position = Vector3(0, 3.5, 0)
	root.add_child(cs)
	root.add_child(_hurtboxes(kit, Vector3(0.9, 6.0, 0.9), Vector3(0, 3.0, 0)))
	var intact := kit.n3("Intact")
	intact.add_child(kit.cyl("Trunk", 0.28, 0.38, 7.0, Vector3(0, 3.5, 0), "bark"))
	for t in 3:
		var tier := kit.cyl("Needles%d" % t, 0.2, 2.2 - 0.55 * t, 2.2, Vector3(0, 3.6 + 1.5 * t, 0), "leaves_dark")
		intact.add_child(tier)
	root.add_child(intact)
	var broken := kit.n3("Broken")
	broken.add_child(kit.cyl("Stump", 0.36, 0.4, 0.8, Vector3(0, 0.4, 0), "bark"))
	broken.add_child(_log(kit, "Fallen", 0.3, 5.5, Vector3(3.2, 0.32, 0.4), "bark", 12.0))
	broken.add_child(kit.cyl("FallenNeedles", 0.2, 1.4, 1.8, Vector3(6.3, 0.9, 1.0), "leaves_dark"))
	broken.visible = false
	root.add_child(broken)
	return root


## An ancient oak (UprootTree): a 9 m trunk on WORLD and a wide canopy (visual only).
static func build_ancient_oak(kit: SceneKit) -> Node:
	var root := kit.n3("AncientOak")
	kit.scripted(root, S_UPROOT, {"world_id": "valley.kingsfall.oak", "prop_id": "prop.ancient_oak",
		"weapon_id": "weapon.tree_oak", "prompt": "Uproot", "radius_m": 3.5, "priority": 45})
	var trunk := StaticBody3D.new()
	trunk.name = "Trunk"
	trunk.collision_layer = SceneKit.L_WORLD
	trunk.collision_mask = 0
	var cs := CollisionShape3D.new()
	cs.name = "Shape"
	var cyl := CylinderShape3D.new()
	cyl.radius = 0.9
	cyl.height = 9.0
	cs.shape = cyl
	cs.position = Vector3(0, 4.5, 0)
	trunk.add_child(cs)
	root.add_child(trunk)
	var visual := kit.n3("Visual")
	visual.add_child(kit.cyl("Trunk", 0.75, 1.0, 9.0, Vector3(0, 4.5, 0), "bark"))
	for r in 4:
		var root_mesh := _log(kit, "Root%d" % r, 0.28, 2.4, Vector3(0, 0.25, 0), "bark", 45.0 * r)
		root_mesh.position = Vector3(cos(PI * 0.5 * r) * 1.0, 0.25, sin(PI * 0.5 * r) * 1.0)
		visual.add_child(root_mesh)
	for b in 3:
		var bough := _log(kit, "Bough%d" % b, 0.3, 4.0, Vector3(0, 8.0 + 0.8 * b, 0), "bark", 60.0 * b)
		visual.add_child(bough)
	visual.add_child(kit.sphere("Canopy", 4.2, Vector3(0, 11.5, 0), "leaves"))
	visual.add_child(kit.sphere("CanopyL", 2.8, Vector3(-3.0, 10.4, 1.0), "leaves_dark"))
	visual.add_child(kit.sphere("CanopyR", 2.8, Vector3(3.0, 10.8, -1.2), "leaves_dark"))
	root.add_child(visual)
	return root


# --------------------------------------------------------------------------- obstacles

## The Deadfall: a 14 m wide, 6 m tall wall of fallen trunks (only a tree-sized weapon breaks it).
static func build_deadfall(kit: SceneKit) -> Node:
	var root := _breakable_root(kit, "Deadfall", "valley.forest.deadfall", "prop.deadfall", Vector3(0, 3.0, 0))
	root.add_child(_block(kit, "BlockLogs", Vector3(14.0, 6.0, 2.6), Vector3(0, 3.0, 0)))
	root.add_child(_hurtboxes(kit, Vector3(14.0, 6.0, 3.2), Vector3(0, 3.0, 0)))
	var intact := kit.n3("Intact")
	for i in 7:
		var y := 0.55 + 0.82 * i
		var yaw := 8.0 * (1 - 2 * (i % 2)) + 3.0 * (i % 3)
		intact.add_child(_log(kit, "Log%d" % i, 0.55 - 0.03 * (i % 3), 14.5 - 0.6 * (i % 2),
			Vector3(0.3 * (1 - 2 * (i % 2)), y, 0.15 * (i % 3) - 0.15), "bark", yaw))
	for b in 4:
		var branch := kit.box("Branch%d" % b, Vector3(0.2, 2.6, 0.2), Vector3(-5.0 + 3.3 * b, 5.8, 0.3), "bark")
		branch.rotation_degrees = Vector3(0, 0, 25.0 * (1 - 2 * (b % 2)))
		intact.add_child(branch)
	root.add_child(intact)
	var broken := kit.n3("Broken")
	for i in 6:
		broken.add_child(_log(kit, "Piece%d" % i, 0.5, 3.2, Vector3(-6.0 + 2.4 * i, 0.5, 1.6 * ((i % 3) - 1)), "bark",
			35.0 * (i % 4)))
	broken.visible = false
	root.add_child(broken)
	root.add_child(_nav_link(4.0))
	return root


## The village's cart barricade across the 12 m road: two carts chained together with stakes.
static func build_cart_barricade(kit: SceneKit) -> Node:
	var root := _breakable_root(kit, "CartBarricade", "valley.village.barricade", "prop.cart_barricade",
		Vector3(0, 1.6, 0))
	root.add_child(_block(kit, "BlockCarts", Vector3(12.0, 3.5, 2.2), Vector3(0, 1.75, 0)))
	root.add_child(_hurtboxes(kit, Vector3(12.0, 3.5, 2.8), Vector3(0, 1.75, 0)))
	var intact := kit.n3("Intact")
	for c in 2:
		var x := -3.0 + 6.0 * c
		intact.add_child(kit.box("Bed%d" % c, Vector3(5.6, 0.9, 2.0), Vector3(x, 1.3, 0), "cart_wood"))
		intact.add_child(kit.box("Side%d" % c, Vector3(5.6, 1.4, 0.15), Vector3(x, 2.4, -0.95), "cart_wood"))
		for w in 2:
			var wheel := kit.cyl("Wheel%d_%d" % [c, w], 0.75, 0.75, 0.2, Vector3(x - 1.8 + 3.6 * w, 0.75, 1.05), "wood_dark")
			wheel.rotation_degrees = Vector3(90, 0, 0)
			intact.add_child(wheel)
	intact.add_child(kit.box("Chain", Vector3(11.6, 0.12, 0.12), Vector3(0, 2.0, -1.1), "iron"))
	for s in 5:
		var stake := kit.box("Stake%d" % s, Vector3(0.16, 2.4, 0.16), Vector3(-4.8 + 2.4 * s, 2.2, -1.3), "wood")
		stake.rotation_degrees = Vector3(-30, 0, 0)
		intact.add_child(stake)
	root.add_child(intact)
	var broken := kit.n3("Broken")
	for i in 5:
		var plank := kit.box("Plank%d" % i, Vector3(2.4, 0.15, 0.6), Vector3(-4.0 + 2.0 * i, 0.1, 1.2 * ((i % 2) - 0.5)), "cart_wood")
		plank.rotation_degrees = Vector3(0, 30.0 * i, 0)
		broken.add_child(plank)
	var lost_wheel := kit.cyl("LostWheel", 0.75, 0.75, 0.2, Vector3(4.2, 0.12, -1.6), "wood_dark")
	broken.add_child(lost_wheel)
	broken.visible = false
	root.add_child(broken)
	root.add_child(_nav_link(3.0))
	return root


## The watch cairn: a 3 m stack of stones (only a hurled boulder topples it).
static func build_cairn(kit: SceneKit) -> Node:
	var root := _breakable_root(kit, "Cairn", "valley.grove.cairn", "prop.cairn", Vector3(0, 1.6, 0))
	root.add_child(_block(kit, "BlockStones", Vector3(2.0, 3.0, 2.0), Vector3(0, 1.5, 0)))
	root.add_child(_hurtboxes(kit, Vector3(2.2, 3.0, 2.2), Vector3(0, 1.5, 0)))
	var intact := kit.n3("Intact")
	var sizes := [Vector3(2.0, 0.8, 1.9), Vector3(1.6, 0.7, 1.5), Vector3(1.2, 0.6, 1.2), Vector3(0.8, 0.5, 0.8), Vector3(0.45, 0.4, 0.45)]
	var y := 0.0
	for i in sizes.size():
		var s: Vector3 = sizes[i]
		var stone := kit.box("Stone%d" % i, s, Vector3(0.05 * (i % 2), y + s.y * 0.5, -0.04 * (i % 3)), "cairn_stone")
		stone.rotation_degrees = Vector3(0, 17.0 * i, 0)
		intact.add_child(stone)
		y += s.y
	root.add_child(intact)
	var broken := kit.n3("Broken")
	for i in 4:
		broken.add_child(kit.box("Fallen%d" % i, Vector3(0.9, 0.5, 0.8), Vector3(-1.2 + 0.8 * i, 0.25, 0.6 * ((i % 2) * 2 - 1)), "cairn_stone"))
	broken.add_child(kit.box("Base", Vector3(2.0, 0.6, 1.9), Vector3(0, 0.3, 0), "cairn_stone"))
	broken.visible = false
	root.add_child(broken)
	return root


## A supply crate (loot).
static func build_crate(kit: SceneKit) -> Node:
	var root := _breakable_root(kit, "Crate", "valley.quarry.chest", "prop.crate", Vector3(0, 0.6, 0))
	root.add_child(_block(kit, "BlockCrate", Vector3(1.4, 1.2, 1.0), Vector3(0, 0.6, 0)))
	root.add_child(_hurtboxes(kit, Vector3(1.5, 1.2, 1.1), Vector3(0, 0.6, 0)))
	var intact := kit.n3("Intact")
	intact.add_child(kit.box("Box", Vector3(1.4, 1.2, 1.0), Vector3(0, 0.6, 0), "cart_wood"))
	for b in 2:
		intact.add_child(kit.box("Slat%d" % b, Vector3(1.44, 0.12, 1.04), Vector3(0, 0.25 + 0.7 * b, 0), "wood_dark"))
	root.add_child(intact)
	var broken := kit.n3("Broken")
	for i in 4:
		var plank := kit.box("Plank%d" % i, Vector3(1.3, 0.08, 0.3), Vector3(-0.5 + 0.35 * i, 0.05, 0.3 * ((i % 2) * 2 - 1)), "cart_wood")
		plank.rotation_degrees = Vector3(0, 40.0 * i, 0)
		broken.add_child(plank)
	broken.visible = false
	root.add_child(broken)
	return root


# --------------------------------------------------------------------------- interactables

## A weapon rack: a timber frame (WORLD) and the Display point where the weapon stands upright.
static func build_weapon_rack(kit: SceneKit) -> Node:
	var root := kit.n3("WeaponRack")
	kit.scripted(root, S_RACK, {"world_id": "valley.ruins.sword_rack", "weapon_id": "weapon.sword",
		"prompt": "Take", "radius_m": 3.0, "priority": 45})
	var frame := StaticBody3D.new()
	frame.name = "Frame"
	frame.collision_layer = SceneKit.L_WORLD
	frame.collision_mask = 0
	var cs := CollisionShape3D.new()
	cs.name = "Shape"
	cs.shape = kit.box_shape(Vector3(1.8, 2.4, 0.5))
	cs.position = Vector3(0, 1.2, 0.25)
	frame.add_child(cs)
	for side in [-1.0, 1.0]:
		frame.add_child(kit.box("Post%s" % ("L" if side < 0 else "R"), Vector3(0.2, 2.4, 0.2), Vector3(0.8 * side, 1.2, 0.25), "wood_dark"))
	frame.add_child(kit.box("Top", Vector3(1.9, 0.18, 0.3), Vector3(0, 2.35, 0.25), "wood_dark"))
	frame.add_child(kit.box("Rest", Vector3(1.6, 0.14, 0.4), Vector3(0, 1.6, 0.1), "wood"))
	frame.add_child(kit.box("Foot", Vector3(1.9, 0.2, 0.9), Vector3(0, 0.1, 0.1), "wood_dark"))
	root.add_child(frame)
	root.add_child(kit.n3("Display", Vector3(0, 0.25, -0.15)))
	return root


## An item pickup: a small banded chest with a glow, no collision (the giant steps over it).
static func build_item_pickup(kit: SceneKit) -> Node:
	var root := kit.n3("ItemPickup")
	kit.scripted(root, S_PICKUP, {"world_id": "valley.quarry.cache", "item_id": "item.iron_ingot",
		"count": 1, "set_flag": "", "prompt": "Take", "radius_m": 3.0, "priority": 45})
	var visual := kit.n3("Visual")
	visual.add_child(kit.box("Chest", Vector3(1.0, 0.55, 0.7), Vector3(0, 0.28, 0), "cart_wood"))
	visual.add_child(kit.box("Lid", Vector3(1.04, 0.18, 0.74), Vector3(0, 0.64, 0), "wood_dark"))
	visual.add_child(kit.box("Band", Vector3(0.12, 0.76, 0.76), Vector3(0, 0.38, 0), "iron"))
	visual.add_child(kit.box("Glow", Vector3(0.3, 0.3, 0.3), Vector3(0, 1.1, 0), "pickup_glow"))
	root.add_child(visual)
	return root


# --------------------------------------------------------------------------- cosmetic

## A bush: three leafy spheres (CosmeticProp; no collision).
static func build_bush(kit: SceneKit) -> Node:
	var root := kit.n3("Bush")
	kit.scripted(root, S_COSMETIC, {"prop_id": "prop.bush"})
	var visual := kit.n3("Visual")
	visual.add_child(kit.sphere("Leaves0", 0.75, Vector3(0, 0.6, 0), "leaves"))
	visual.add_child(kit.sphere("Leaves1", 0.55, Vector3(0.55, 0.5, 0.2), "leaves_dark"))
	visual.add_child(kit.sphere("Leaves2", 0.5, Vector3(-0.5, 0.45, -0.25), "leaves"))
	root.add_child(visual)
	return root


## A banner on a pole: the cloth hangs from a crossbar (CosmeticProp; no collision).
static func build_banner(kit: SceneKit) -> Node:
	var root := kit.n3("Banner")
	kit.scripted(root, S_COSMETIC, {"prop_id": "prop.banner"})
	var visual := kit.n3("Visual")
	visual.add_child(kit.cyl("Pole", 0.07, 0.09, 4.2, Vector3(0, 2.1, 0), "wood_dark"))
	visual.add_child(kit.box("Crossbar", Vector3(1.5, 0.1, 0.1), Vector3(0, 4.0, 0), "wood_dark"))
	visual.add_child(kit.box("Cloth", Vector3(1.3, 2.2, 0.05), Vector3(0, 2.85, -0.08), "banner_cloth"))
	root.add_child(visual)
	return root
