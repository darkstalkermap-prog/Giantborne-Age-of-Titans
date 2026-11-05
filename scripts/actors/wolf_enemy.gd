class_name WolfEnemy
extends EnemyActor
## Fast, low quadruped (enemy.wolf, spec 10): the shared EnemyActor glue with a WolfBrain and a
## QuadrupedRig. Its lunge is the base's scripted `motion` (a committed 9 m/s dash behind a line
## telegraph, then a long recovery to punish); its bite is a weapon arc at head height. No guard.
## Same perception, decision and movement rates as every enemy; nav layer 1 (human).

@onready var quad: QuadrupedRig = get_node_or_null("Visual") as QuadrupedRig


func _make_brain() -> EnemyBrain:
	return WolfBrain.new(entity.entity_id, record, Sim.DEFAULT_SEED ^ hash(entity.entity_id))


func flash(strength: float, color := Color(1.0, 0.95, 0.85)) -> void:
	if quad != null:
		quad.flash(strength, color)


func get_rig_state() -> Dictionary:
	var s := super()
	s["lunging"] = controller.action != null and typeof(controller.action.param("motion")) == TYPE_DICTIONARY \
		and controller.phase() == ActionDef.Phase.ACTIVE
	return s
