class_name AshSpurLook
extends Node3D
## E2: the Grey Spur's rock as it is drawn (presentation only): a fang of grey rock 46 m tall and the boulders at its foot, made
## when it enters the tree (CinderGear: a seeded, jagged shape - no file). `lying` false: standing over the Cut,
## leaning toward it (the prop's Intact stage); true: thrown down across the Cut, a dam of broken rock (Heaved).

@export var lying := false
## The rock's size over its mesh's (a fang taller than a stage-9 giant; a dam a hill's worth of rock).
const STANDING_SCALE := 2.0
const LYING_SCALE := 2.2

static var _mesh_standing: ArrayMesh = null
static var _mesh_lying: ArrayMesh = null
static var _mat: StandardMaterial3D = null


func _ready() -> void:
	var mi := MeshInstance3D.new()
	mi.name = "Rock"
	mi.mesh = lying_mesh() if lying else standing_mesh()
	mi.material_override = material()
	mi.scale = Vector3.ONE * (LYING_SCALE if lying else STANDING_SCALE)
	add_child(mi)


static func material() -> StandardMaterial3D:
	if _mat == null:
		_mat = StandardMaterial3D.new()
		_mat.albedo_color = Color(0.43, 0.42, 0.40)
		_mat.roughness = 0.95
		var tex := load("res://assets/creatures/stoneback_stone_normal.png") as Texture2D
		if tex != null:
			_mat.normal_enabled = true
			_mat.normal_texture = tex
			_mat.normal_scale = 0.8
			_mat.uv1_scale = Vector3(0.35, 0.35, 0.35)
	return _mat


static func standing_mesh() -> ArrayMesh:
	if _mesh_standing == null:
		var g := CinderGear.new(4417)
		var r := g.rng()
		# the fang: 22 m, leaning over the Cut (local -x), bending a little at its top
		g.spike(Vector3(1.5, -1.0, 0.0), Vector3(-0.35, 1.0, 0.05), 23.0, 5.2, Vector3(-0.6, 1.0, 0.1), 7, 7, 0.22)
		g.spike(Vector3(4.0, -1.0, 3.0), Vector3(-0.2, 1.0, -0.2), 11.0, 3.4, Vector3.ZERO, 6, 4, 0.25)
		for k in 5:
			var a := TAU * float(k) / 5.0 + r.randf() * 0.5
			g.lump(Vector3(cos(a) * 6.0 + 1.0, 0.8, sin(a) * 6.0), Vector3(2.6, 2.0, 2.4) * r.randf_range(0.8, 1.3),
				Basis(Vector3.UP, r.randf() * TAU), 0.3, 6, 9)
		_mesh_standing = g.mesh()
	return _mesh_standing


static func lying_mesh() -> ArrayMesh:
	if _mesh_lying == null:
		var g := CinderGear.new(4418)
		var r := g.rng()
		# the fang thrown down across the Cut (along local z), broken in three, boulders packed round it
		for k in 3:
			var z := -9.0 + 9.0 * float(k)
			g.lump(Vector3(r.randf_range(-1.0, 1.0), 3.2, z), Vector3(4.6, 3.6, 4.4) * r.randf_range(0.85, 1.15),
				Basis(Vector3.UP, r.randf() * TAU), 0.28, 7, 10)
		for k in 7:
			var z := -13.0 + 26.0 * float(k) / 6.0
			g.lump(Vector3(r.randf_range(-5.0, 5.0), 1.4, z), Vector3(2.4, 1.8, 2.2) * r.randf_range(0.7, 1.3),
				Basis(Vector3.UP, r.randf() * TAU), 0.32, 6, 9)
		_mesh_lying = g.mesh()
	return _mesh_lying
