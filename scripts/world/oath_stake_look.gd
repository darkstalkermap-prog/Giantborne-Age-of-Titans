class_name OathStakeLook
extends Node3D
## E3: the Oath-stake as it is drawn (presentation only): an iron stake as tall as a tower driven into a cracked boulder on
## the Kingsward's edge, where the old kings rooted the Hollow King's oath-chains - its iron bands, the ring at its head
## and four chains running from the ring down into the ground toward the field (made when it enters the tree:
## HollowArmour's plates and links, no file). `lying` false: driven in, leaning a little (the prop's Intact stage); true:
## heaved out and lying on the ground, the chains slack, the boulder split (Heaved).

@export var lying := false

static var _mesh_standing: ArrayMesh = null
static var _mesh_lying: ArrayMesh = null
static var _rock: ArrayMesh = null
static var _mat: ShaderMaterial = null
static var _rock_mat: StandardMaterial3D = null


func _ready() -> void:
	var mi := MeshInstance3D.new()
	mi.name = "Stake"
	mi.mesh = lying_mesh() if lying else standing_mesh()
	mi.material_override = material()
	add_child(mi)
	var rock := MeshInstance3D.new()
	rock.name = "Rock"
	rock.mesh = rock_mesh()
	rock.material_override = rock_material()
	rock.rotation.y = 0.6 if lying else 0.0
	add_child(rock)


static func material() -> ShaderMaterial:
	if _mat == null:
		_mat = ShaderMaterial.new()
		_mat.shader = load(HollowModel.ARMOUR_SHADER)
		_mat.set_shader_parameter(&"knot_glow", 0.0)
		_mat.set_shader_parameter(&"seed_offset", 7.3)
	return _mat


static func rock_material() -> StandardMaterial3D:
	if _rock_mat == null:
		_rock_mat = AshSpurLook.material().duplicate() as StandardMaterial3D
		_rock_mat.albedo_color = Color(0.5, 0.5, 0.49)
	return _rock_mat


static func rock_mesh() -> ArrayMesh:
	if _rock == null:
		var g := CinderGear.new(6611)
		var r := g.rng()
		g.lump(Vector3(0, 1.2, 0), Vector3(7.5, 4.2, 6.5), Basis(), 0.22, 8, 12)
		for k in 4:
			var a := TAU * float(k) / 4.0 + 0.4
			g.lump(Vector3(cos(a) * 7.0, 0.6, sin(a) * 6.5), Vector3(3.0, 2.0, 2.6) * r.randf_range(0.8, 1.2),
				Basis(Vector3.UP, r.randf() * TAU), 0.3, 6, 9)
		_rock = g.mesh()
	return _rock


## The stake along `dir` from `foot`: an octagonal iron bar tapering to its point below, banded, a ring at its head and
## the chains from the ring down to the ground (`slack`: lying loose).
static func _stake(ab: HollowArmour, foot: Vector3, dir: Vector3, slack: bool) -> void:
	dir = dir.normalized()
	var side := dir.cross(Vector3.FORWARD if absf(dir.z) < 0.9 else Vector3.RIGHT).normalized()
	var other := dir.cross(side).normalized()
	var rings: Array = []
	for t: float in [-4.0, 0.0, 26.0, 30.0]:
		var r := 1.6 if t > -1.0 else 0.25
		if t >= 26.0:
			r = 1.35
		rings.append(HollowArmour.ring(foot + dir * t, side, other, r, r, 1.0 if t >= 26.0 else 0.0))
	ab.loft(rings, 0.0, TAU, 8, 0.3)
	for t: float in [3.0, 11.0, 19.0]:
		ab.loft([HollowArmour.ring(foot + dir * t, side, other, 1.95, 1.95, 0.0),
			HollowArmour.ring(foot + dir * (t + 1.4), side, other, 1.95, 1.95, 0.6)], 0.0, TAU, 10, 0.4)
	var head := foot + dir * 30.8
	var pts := PackedVector3Array()
	for s in 13:
		var a := TAU * float(s) / 12.0
		pts.append(head + (side * cos(a) + dir * sin(a)) * 2.2)
	ab.chain(pts, 1.4, 0.9, 0.22)
	for k in 4:
		var a := TAU * float(k) / 4.0 + 0.7
		var out := Vector3(cos(a), 0.0, sin(a))
		var end := foot + out * (16.0 if not slack else 12.0) + Vector3.DOWN * 0.5
		var mid := head.lerp(end, 0.5) + Vector3.DOWN * (2.0 if not slack else 6.0)
		ab.chain(PackedVector3Array([head + out * 2.0, mid, end]), 2.0, 1.2, 0.28)


static func standing_mesh() -> ArrayMesh:
	if _mesh_standing == null:
		var ab := HollowArmour.new()
		ab.tone = 0.4
		_stake(ab, Vector3(0, 2.5, 0), Vector3(0.12, 1.0, 0.08), false)
		_mesh_standing = ab.mesh()
	return _mesh_standing


static func lying_mesh() -> ArrayMesh:
	if _mesh_lying == null:
		var ab := HollowArmour.new()
		ab.tone = 0.4
		_stake(ab, Vector3(-3.0, 2.0, -12.0), Vector3(0.05, 0.12, 1.0), true)
		_mesh_lying = ab.mesh()
	return _mesh_lying
