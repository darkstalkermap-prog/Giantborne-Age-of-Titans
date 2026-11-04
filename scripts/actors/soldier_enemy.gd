class_name SoldierEnemy
extends EnemyActor
## Human-sized melee enemy: the shared EnemyActor glue with a SoldierBrain and a frontal guard.
## Perception at 5 Hz, decisions at 10 Hz, movement and hit queries every tick.


func _make_brain() -> EnemyBrain:
	return SoldierBrain.new(entity.entity_id, record, Sim.DEFAULT_SEED ^ hash(entity.entity_id))


## Soldiers "guard the front" (spec 10): while aware and not attacking they hold a frontal
## guard that blocks with the normal block rules and their own stamina. Flank them, or break
## the guard with heavy attacks (a broken guard staggers them). They turn slower while guarding.
func _is_guarding() -> bool:
	var guard: Dictionary = record.get("guard", {})
	if guard.is_empty() or controller.state != CombatController.State.LOCOMOTION or not brain.aware:
		return false
	if not (brain.state in [SoldierBrain.AIState.ALERT, SoldierBrain.AIState.APPROACH,
			SoldierBrain.AIState.RECOVER, SoldierBrain.AIState.REPOSITION]):
		return false
	return entity.combatant.pools.stamina >= float(guard.get("min_stamina", 0.0))


func _turn_rate_deg_s() -> float:
	var rate := super()
	if is_guarding():
		rate = float((record.get("guard", {}) as Dictionary).get("turn_rate_deg_s", rate))
	return rate
