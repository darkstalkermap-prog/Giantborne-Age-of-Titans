class_name CheckpointMarker
extends Marker3D
## A respawn point: shrine spawn points, waystones and test-level checkpoints (plan §2.7.4).
## GameSession (P06) moves the player to the marker of the last checkpoint reached.
## Group "checkpoints": joined in _notification (which runs for every class of the hierarchy),
## so subclasses need no super() calls in _init or _ready.

## Stable id, e.g. "valley.shrine.grove" or "valley.cp.forest_road".
@export var checkpoint_id := ""


func _notification(what: int) -> void:
	if what == NOTIFICATION_ENTER_TREE:
		add_to_group("checkpoints")


## Where (and facing which way) the player respawns: the marker's global transform with the
## basis reduced to its yaw, so a tilted marker never spawns a tilted giant.
func spawn_transform() -> Transform3D:
	var t := global_transform if is_inside_tree() else transform
	var fwd := -t.basis.z
	fwd.y = 0.0
	var yaw := 0.0 if fwd.length_squared() < 1e-8 else TargetingRules.yaw_of(fwd)
	return Transform3D(Basis(Vector3.UP, yaw), t.origin)
