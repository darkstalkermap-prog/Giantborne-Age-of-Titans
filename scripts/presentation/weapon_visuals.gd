class_name WeaponVisuals
extends RefCounted
## The low-poly mesh of a weapon record (plan §3.8 design 4), shared by the giant's hand
## (PlayerEquipment) and weapon racks. build(rec) returns a Node3D named "Weapon" whose meshes run
## along its local -Z from the grip (the origin) to the tip, length_m away, at the record's
## stage-1 size; the caller scales the node (the hand: effective_weapon_scale / k, so the mesh is
## exactly as long as the hit sweep).
##
## Shapes by visual_shape: club (a tapered cudgel), sword (grip, guard, blade), hammer (shaft and a
## wide iron head), tree (a trunk with branches and a canopy at the far end; the canopy is on render
## layer 2, which the camera hides in first person). A reinforced weapon (id ending in
## "_reinforced") gets iron bands. Presentation only.
##
## P31 (plan M6-M9 §5.12): axe (a long haft with a broad bearded iron head on one side and a back
## spike) and pine (the Greywood's uprooted great pine: a tapering trunk, a root ball at the grip and
## tiers of needles toward the far end, hidden in first person like the tree's canopy, and carried
## raised like the tree). A titanforged weapon (id ending in "_titan") gets dark titan-iron bands with
## a glowing rune line.

const NODE_NAME := "Weapon"
const FP_HIDDEN_LAYER := 2
## The arm pose (yaw, pitch in degrees) the tree is carried in: raised to the right, so the trunk
## stays clear of the view centre in first person and out of the ground at rest.
const TREE_IDLE_POSE := Vector2(24.0, 30.0)
const COLORS := {
	"wood": [Color(0.48, 0.33, 0.20), 0.85, 0.0],
	"leather": [Color(0.30, 0.20, 0.12), 0.9, 0.0],
	"steel": [Color(0.76, 0.78, 0.82), 0.35, 0.6],
	"iron": [Color(0.32, 0.33, 0.36), 0.5, 0.5],
	"bark": [Color(0.36, 0.26, 0.17), 0.95, 0.0],
	"leaves": [Color(0.27, 0.43, 0.20), 0.95, 0.0],
	"needles": [Color(0.16, 0.30, 0.17), 0.95, 0.0],   # P31: the great pine
	"titan": [Color(0.20, 0.22, 0.27), 0.4, 0.75],     # P31: titan iron
	"rune": [Color(0.55, 0.85, 1.0), 0.3, 0.0],        # P31: the titanforged rune line (glows)
}

static var _materials := {}


static func material(mat_name: String) -> StandardMaterial3D:
	if not _materials.has(mat_name):
		var spec: Array = COLORS.get(mat_name, COLORS.wood)
		var m := StandardMaterial3D.new()
		m.albedo_color = spec[0]
		m.roughness = spec[1]
		if float(spec[2]) > 0.0:
			m.metallic = spec[2]
		if mat_name == "rune":
			m.emission_enabled = true
			m.emission = spec[0]
		_materials[mat_name] = m
	return _materials[mat_name]


## The weapon's mesh node: "Weapon", grip at the origin, tip at -Z length_m (stage-1 metres).
static func build(rec: Dictionary) -> Node3D:
	var root := Node3D.new()
	root.name = NODE_NAME
	var length := float(rec.get("length_m", 1.85))
	match shape_of(rec):
		"sword":
			_sword(root, length)
		"hammer":
			_hammer(root, length)
		"tree":
			_tree(root, length)
		"none":
			pass
		"club":
			_club(root, length)
		"axe":
			_axe(root, length)   # P31
		"pine":
			_pine(root, length)   # P31
		_:
			_staff(root, length)
	if is_reinforced(rec):
		_reinforce(root, shape_of(rec), length)
	if is_titanforged(rec):
		_titanforge(root, shape_of(rec), length)   # P31
	return root


## Iron bands on a reforged club or maul, an iron ridge along a reforged blade.
static func _reinforce(root: Node3D, shape: String, length: float) -> void:
	match shape:
		"club":
			for i in 2:
				var f := 0.55 + 0.25 * i
				root.add_child(_cyl("Band%d" % i, lerpf(0.11, 0.24, f) + 0.03, 0.08, Vector3(0, 0, -length * f), "iron"))
		"hammer":
			for i in 2:
				root.add_child(_cyl("Band%d" % i, 0.09, 0.08, Vector3(0, 0, -length * (0.3 + 0.25 * i)), "iron"))
		"sword":
			var blade := maxf(length - 0.34, 0.1)
			root.add_child(_box("Ridge", Vector3(0.05, 0.05, blade * 0.9), Vector3(0, 0, -0.34 - blade * 0.45), "iron"))


## visual_shape, else one guessed from the family ("club" for unknown families).
static func shape_of(rec: Dictionary) -> String:
	var shape := str(rec.get("visual_shape", ""))
	if shape != "":
		return shape
	match str(rec.get("family", "")):
		"sword", "hammer", "tree", "bow", "staff", "axe":
			return str(rec.family)
	return "club"


static func is_reinforced(rec: Dictionary) -> bool:
	return str(rec.get("id", "")).ends_with("_reinforced")


## The arm's rest pose for this weapon, or Vector2.INF for the rig's own.
static func idle_pose(rec: Dictionary) -> Vector2:
	return TREE_IDLE_POSE if shape_of(rec) in ["tree", "pine"] else Vector2.INF


## How far the tip is from the grip in the node's own space (the meshes' extent along -Z).
static func local_length(node: Node3D) -> float:
	var tip := 0.0
	for mi in _meshes(node):
		var xform := _relative_transform(mi, node)
		var aabb := mi.get_aabb()
		for i in 8:
			tip = maxf(tip, -(xform * aabb.get_endpoint(i)).z)
	return tip


## The tip's distance from the grip in world space: local_length x the node's global scale.
static func world_length(node: Node3D) -> float:
	return local_length(node) * node.global_basis.get_scale().z


static func _meshes(node: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	for c in node.get_children():
		if c is MeshInstance3D:
			out.append(c as MeshInstance3D)
		out.append_array(_meshes(c))
	return out


static func _relative_transform(n: Node3D, ancestor: Node3D) -> Transform3D:
	var t := Transform3D.IDENTITY
	var cur: Node = n
	while cur != null and cur != ancestor:
		if cur is Node3D:
			t = (cur as Node3D).transform * t
		cur = cur.get_parent()
	return t


# --------------------------------------------------------------------------- shapes

static func _club(root: Node3D, length: float) -> void:
	# The M1 club: a cylinder 0.11 m at the grip, 0.24 m at the far end.
	root.add_child(_cyl("Head", 0.24, length, Vector3(0, 0, -length * 0.5), "wood", 0.11))


static func _sword(root: Node3D, length: float) -> void:
	root.add_child(_box("Pommel", Vector3(0.11, 0.11, 0.07), Vector3(0, 0, 0.02), "iron"))
	root.add_child(_box("Grip", Vector3(0.08, 0.08, 0.26), Vector3(0, 0, -0.13), "leather"))
	root.add_child(_box("Guard", Vector3(0.44, 0.07, 0.08), Vector3(0, 0, -0.3), "iron"))
	var blade := maxf(length - 0.34, 0.1)
	root.add_child(_box("Blade", Vector3(0.16, 0.035, blade), Vector3(0, 0, -0.34 - blade * 0.5), "steel"))


static func _hammer(root: Node3D, length: float) -> void:
	var head := 0.42
	var shaft := maxf(length - head * 0.5, 0.1)
	root.add_child(_cyl("Shaft", 0.06, shaft, Vector3(0, 0, -shaft * 0.5), "wood"))
	root.add_child(_box("Head", Vector3(0.95, head, head), Vector3(0, 0, -(length - head * 0.5)), "iron"))


static func _tree(root: Node3D, length: float) -> void:
	var canopy_r := minf(1.9, length * 0.3)
	var trunk := length - canopy_r * 0.6
	root.add_child(_cyl("Trunk", 0.3, trunk, Vector3(0, 0, -trunk * 0.5), "bark", 0.42))
	root.add_child(_sphere("Roots", 0.55, Vector3(0, 0, 0.25), "bark"))
	for i in 3:
		var z := -length * (0.45 + 0.12 * i)
		var branch := _box("Branch%d" % i, Vector3(0.14, 0.14, 1.6), Vector3(0.45 * (1 - 2 * (i % 2)), 0.2, z), "bark")
		branch.rotation_degrees = Vector3(0, 35.0 * (1 - 2 * (i % 2)), 0)
		root.add_child(branch)
	var canopy := _sphere("Canopy", canopy_r, Vector3(0, 0, -(length - canopy_r)), "leaves")
	canopy.layers = FP_HIDDEN_LAYER
	root.add_child(canopy)
	var tuft := _sphere("CanopyTuft", canopy_r * 0.6, Vector3(0.7, 0.6, -(length - canopy_r * 1.6)), "leaves")
	tuft.layers = FP_HIDDEN_LAYER
	root.add_child(tuft)


static func _staff(root: Node3D, length: float) -> void:
	root.add_child(_cyl("Shaft", 0.05, length, Vector3(0, 0, -length * 0.5), "wood"))


static func _box(node_name: String, size: Vector3, pos: Vector3, mat: String) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = node_name
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.position = pos
	mi.material_override = material(mat)
	return mi


## A cylinder along -Z (top_r at the far end, bottom_r at the grip end; -1 = top_r).
static func _cyl(node_name: String, top_r: float, height: float, pos: Vector3, mat: String,
		bottom_r := -1.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = node_name
	var cm := CylinderMesh.new()
	cm.top_radius = top_r
	cm.bottom_radius = bottom_r if bottom_r > 0.0 else top_r
	cm.height = height
	cm.radial_segments = 8
	mi.mesh = cm
	mi.position = pos
	mi.rotation_degrees = Vector3(-90, 0, 0)   # the mesh's +Y (top) points along -Z
	mi.material_override = material(mat)
	return mi


static func _sphere(node_name: String, r: float, pos: Vector3, mat: String) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = node_name
	var sm := SphereMesh.new()
	sm.radius = r
	sm.height = r * 2.0
	sm.radial_segments = 10
	sm.rings = 6
	mi.mesh = sm
	mi.position = pos
	mi.material_override = material(mat)
	return mi


# --------------------------------------------------------------------------- P31: axe, great pine, titanforged

## True for a titanforged weapon (id ending in "_titan").
static func is_titanforged(rec: Dictionary) -> bool:
	return str(rec.get("id", "")).ends_with("_titan")


## A felling axe: a haft along -Z, a broad bearded head to the right (+X) near the far end, an iron
## cap and a back spike to the left.
static func _axe(root: Node3D, length: float) -> void:
	root.add_child(_cyl("Haft", 0.055, length, Vector3(0, 0, -length * 0.5), "wood", 0.065))
	var head_z := -(length - 0.28)
	root.add_child(_box("Cheek", Vector3(0.22, 0.12, 0.36), Vector3(0.06, 0, head_z), "iron"))
	var blade := _box("Blade", Vector3(0.5, 0.05, 0.62), Vector3(0.38, 0, head_z + 0.04), "steel")
	root.add_child(blade)
	var beard := _box("Beard", Vector3(0.22, 0.05, 0.3), Vector3(0.5, 0, head_z + 0.36), "steel")
	beard.rotation_degrees = Vector3(0, -28, 0)
	root.add_child(beard)
	root.add_child(_box("Spike", Vector3(0.26, 0.07, 0.1), Vector3(-0.2, 0, head_z), "iron"))
	root.add_child(_cyl("Cap", 0.07, 0.08, Vector3(0, 0, -length + 0.04), "iron"))


## The great pine: a tapering trunk (thick at the grip), a root ball behind the grip and three tiers
## of needles toward the far end (layer FP_HIDDEN_LAYER, like the tree's canopy).
static func _pine(root: Node3D, length: float) -> void:
	root.add_child(_cyl("Trunk", 0.16, length, Vector3(0, 0, -length * 0.5), "bark", 0.44))
	root.add_child(_sphere("Roots", 0.6, Vector3(0, 0, 0.3), "bark"))
	for i in 3:
		var tier_len := length * (0.30 - 0.01 * i)
		var z := -length * (0.40 + 0.16 * i) - tier_len * 0.5   # the last tier ends at the tip
		var cone := _cyl("Needles%d" % i, 0.05, tier_len, Vector3(0, 0, z), "needles", length * (0.2 - 0.04 * i))
		cone.layers = FP_HIDDEN_LAYER
		root.add_child(cone)


## Titan-iron bands (two, a third on the axe's head) with a glowing rune line along the weapon.
static func _titanforge(root: Node3D, shape: String, length: float) -> void:
	var radius := {"club": 0.27, "hammer": 0.1, "sword": 0.11, "axe": 0.1}.get(shape, 0.12) as float
	for i in 2:
		var f := 0.35 + 0.3 * i
		var r := lerpf(0.11, radius, f) + 0.03 if shape == "club" else radius
		root.add_child(_cyl("TitanBand%d" % i, r, 0.1, Vector3(0, 0, -length * f), "titan"))
	if shape == "axe":
		root.add_child(_box("TitanEdge", Vector3(0.08, 0.06, 0.64), Vector3(0.64, 0, -(length - 0.32)), "titan"))
	var rune_len := length * 0.5
	root.add_child(_box("Rune", Vector3(0.03, 0.03, rune_len), Vector3(0, radius * 0.8 if shape == "club" else 0.06,
		-length * 0.3 - rune_len * 0.5), "rune"))
