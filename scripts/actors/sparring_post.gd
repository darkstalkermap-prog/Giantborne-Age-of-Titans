class_name SparringPost
extends EnemyActor
## The sparring post (enemy.sparring_post, archetype training; plan §3.13 design 6, §4.4): a
## wooden post with padded arms that teaches block, parry and dodge. A SparringBrain swings its
## arms all round it every 3 s while the giant stands within 4 m: a circle telegraph (r 3 m) fills
## over the 0.8 s windup, then a parryable pulse - block it (BLOCKED), parry it as it lands
## (PARRIED) or dodge through it (EVADED).
##
## Team ENEMY and lockable (threat 0.1), so the giant can lock it and practise its own blows;
## immobile (no steering, no knockback, never grabbed); unkillable: its record's `unkillable`
## keeps it at 1 health or more, and a blow that leaves it there resets it to full health. It
## gives no XP and no fury, never becomes aware (it never defers a checkpoint), and its
## encounter does not count toward the budget.
##
## It is a training device, not a combatant: it leaves the "enemies" group EnemyActor puts it in
## (soak bots and tools treat "enemies" as things to kill; this one never dies) and joins
## "sparring_posts" and "training_targets" instead. Its Visual is not an ActorRig: the post spins
## its Visual/Body/Arms through the swing.

const GROUP := "sparring_posts"
const TRAINING_GROUP := "training_targets"
## How far the arms turn over a swing's active phase (degrees), and their rest yaw.
const SWING_SPIN_DEG := 360.0
const ARMS_PATH := "Visual/Body/Arms"

## How many times the post reset to full health.
var resets := 0
var _arms: Node3D


func _ready() -> void:
	super()
	remove_from_group("enemies")
	add_to_group(GROUP)
	add_to_group(TRAINING_GROUP)
	_arms = get_node_or_null(ARMS_PATH) as Node3D
	entity.hit_taken.connect(_on_post_hit)


func _make_brain() -> EnemyBrain:
	return SparringBrain.new(entity.entity_id, record, Sim.DEFAULT_SEED ^ hash(entity.entity_id))


## The swings since it was placed (SparringBrain.swings).
func swings() -> int:
	return (brain as SparringBrain).swings if brain is SparringBrain else 0


## Immobile: it never steers and is never pushed (gravity still keeps it on the floor). A leash
## return keeps the movement (the wave rule for archetype overrides; its encounter has no leash).
func _custom_movement(_dt: float) -> bool:
	if is_returning():
		return false
	move_velocity = Vector3.ZERO
	knockback_velocity = Vector3.ZERO
	return true


func apply_knockback(_direction: Vector3, _speed: float) -> void:
	pass


func can_be_grabbed() -> bool:
	return false


## A blow that leaves it at 1 health (its floor: unkillable) resets it to full.
func _on_post_hit(_result: HitResult) -> void:
	var pools := entity.combatant.pools
	if entity.is_alive() and pools.health <= 1.0 + 1e-4:
		resets += 1
		entity.heal(pools.health_max - pools.health, "reset")


func _process(_delta: float) -> void:
	if _arms == null or controller == null:
		return
	var a := controller.action
	var spin := 0.0
	if a != null and a.id == _swing_id():
		match controller.phase():
			ActionDef.Phase.WINDUP:
				spin = -20.0 * controller.phase_fraction()   # wound back
			ActionDef.Phase.ACTIVE:
				spin = -20.0 + (SWING_SPIN_DEG + 20.0) * controller.phase_fraction()
	_arms.rotation.y = deg_to_rad(spin)


func _swing_id() -> String:
	var list: Array = record.get("attacks", [])
	return str(list[0]) if not list.is_empty() else ""


func get_rig_state() -> Dictionary:
	var s := super()
	s["swinging"] = controller.action != null and controller.action.id == _swing_id()
	return s


func get_debug_info() -> Dictionary:
	var d := super()
	d["swings"] = swings()
	d["resets"] = resets
	return d
