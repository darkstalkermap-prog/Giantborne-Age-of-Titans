class_name CinderHunch
extends SkeletonModifier3D
## E2: the Cinder Titan's carriage (presentation only): his body is the Stormcaller's and so are his clips, but he does not
## stand as the bell-warden stood. After every clip's pose this bends him into his own - the back rounded forward under
## the weight of his slag, the shoulders drawn up and forward, the head thrust out and lifted to look ahead: a heavier,
## hunched silhouette over the same feet. Rotations in each bone's own frame (degrees about x, y, z), on top of the clip.

const BENDS := {
	"spine_01": Vector3(4.0, 0.0, 0.0),
	"spine_02": Vector3(6.0, 0.0, 0.0),
	"spine_03": Vector3(5.0, 0.0, 0.0),
	"neck_01": Vector3(-4.0, 0.0, 0.0),
	"head": Vector3(-8.0, 0.0, 0.0),
	"clavicle_l": Vector3(0.0, 0.0, -6.0),
	"clavicle_r": Vector3(0.0, 0.0, 6.0),
}

## How much of the bend (0 standing as the clip has him .. 1).
@export var amount := 1.0
var _ids: Dictionary = {}


func _process_modification() -> void:
	var sk := get_skeleton()
	if sk == null or amount <= 0.0:
		return
	if _ids.is_empty():
		for b: String in BENDS:
			_ids[b] = sk.find_bone(b)
	for b: String in BENDS:
		var i: int = _ids[b]
		if i < 0:
			continue
		var d: Vector3 = BENDS[b] * amount
		var q := Quaternion.from_euler(Vector3(deg_to_rad(d.x), deg_to_rad(d.y), deg_to_rad(d.z)))
		sk.set_bone_pose_rotation(i, sk.get_bone_pose_rotation(i) * q)
