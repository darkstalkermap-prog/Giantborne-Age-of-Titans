class_name TrophyDisplay
extends Node3D
## B2: one of the Ogre King's pieces shown as a static thing in the world (Thornwick's trophy stand after his fall:
## the crown on its pike, the wheels, the ram, the bell): the piece's own mesh from his asset
## (assets/creatures/ogre_king.glb; OgreKingModel's pieces) drawn in his wood material, in its rest shape (no
## skeleton: a skinned mesh draws its bind pose), moved so its bounds' centre stands at this node's origin, turned by
## `piece_rotation_deg`. Made where the people are drawn (PersonRig.layers_enabled(): a display, --skin; never
## headless), like his model. Presentation only.

## The piece's node name in his asset ("trophy_crown", "trophy_wheel_l", "ram", ...).
@export var piece := "trophy_crown"
## How the piece is first laid (before piece_rotation_deg): "none" (as he wore it, upright, his front +Z), "long_x"
## (its longest extent along X and its thinnest up: a ram lying on trestles), "disc_z" (its thinnest extent along Z:
## a wheel standing on its rim, facing +Z) - from the principal axes of its vertices.
@export var align := "none"
## The piece turned (degrees, XYZ) about its bounds' centre after `align`.
@export var piece_rotation_deg := Vector3.ZERO

## The piece's MeshInstance3D once made (null headless or without the asset).
var shown: MeshInstance3D = null


func _ready() -> void:
	if PersonRig.layers_enabled():
		build()


## Makes the piece's mesh under this node; false when the asset or the piece is missing.
func build() -> bool:
	if shown != null:
		return true
	var e := OgreKingModel.entry()
	var path := str(e.get("scene", ""))
	if e.is_empty() or not ResourceLoader.exists(path):
		return false
	var model := (load(path) as PackedScene).instantiate() as Node3D
	var src := model.find_child(piece, true, false) as MeshInstance3D
	var mesh: Mesh = src.mesh if src != null else null
	model.free()
	if mesh == null:
		return false
	shown = MeshInstance3D.new()
	shown.name = "Piece"
	shown.mesh = mesh
	shown.material_override = OgreKingModel.wood_material_of(e, piece)
	var c := mesh.get_aabb().get_center()
	var b := Basis.from_euler(piece_rotation_deg * (PI / 180.0)) * _aligned(mesh)
	shown.transform = Transform3D(b, -(b * c))
	add_child(shown)
	return true


## The basis that lays the mesh as `align` says (its principal axes: the vertices' covariance's eigenvectors by a
## few power iterations, deterministic).
func _aligned(mesh: Mesh) -> Basis:
	if align == "none" or mesh.get_surface_count() == 0:
		return Basis()
	var pts: PackedVector3Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	if pts.size() < 3:
		return Basis()
	var mean := Vector3.ZERO
	for p in pts:
		mean += p
	mean /= float(pts.size())
	var cov := [[0.0, 0.0, 0.0], [0.0, 0.0, 0.0], [0.0, 0.0, 0.0]]
	for p in pts:
		var d := p - mean
		for i in 3:
			for j in 3:
				cov[i][j] += d[i] * d[j]
	var axes: Array[Vector3] = []
	for k in 2:
		var v := Vector3(1.0, 0.7, 0.4) if k == 0 else Vector3(0.3, 1.0, -0.6)
		for _it in 40:
			var w := Vector3(cov[0][0] * v.x + cov[0][1] * v.y + cov[0][2] * v.z,
				cov[1][0] * v.x + cov[1][1] * v.y + cov[1][2] * v.z, cov[2][0] * v.x + cov[2][1] * v.y + cov[2][2] * v.z)
			for a in axes:
				w -= a * w.dot(a)
			if w.length() < 1e-9:
				break
			v = w.normalized()
		axes.append(v)
	var long_a := axes[0]
	var mid_a := axes[1]
	var thin := long_a.cross(mid_a).normalized()
	# the rotation taking the mesh's (right-handed) axes onto the target's: long_x lays its thinnest up, disc_z faces
	# it along +Z (both targets right-handed, so no mirror)
	var from := Basis(long_a, mid_a, thin)
	var to := Basis(Vector3.RIGHT, Vector3.FORWARD, Vector3.UP) if align == "long_x" else Basis(Vector3.RIGHT, Vector3.UP, Vector3.BACK)
	return to * from.inverse()
