class_name Hurtbox
extends Area3D
## A damageable volume. One entity may own several (head, torso, legs); hits are
## de-duplicated per entity, never per hurtbox. Hurtboxes do not block movement or attacks.

@export var region := "torso"
@export var weak_point := false

var entity: CombatEntity = null


func _ready() -> void:
	collision_layer = HitQueryAdapter.LAYER_HURTBOX
	collision_mask = 0
	monitoring = false
	monitorable = true
