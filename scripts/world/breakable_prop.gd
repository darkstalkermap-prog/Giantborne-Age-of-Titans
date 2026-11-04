class_name BreakableProp
extends StaticBody3D
## A persistent breakable (spec section 11): health, intact/broken representations, a stable
## world id, one destruction event, one loot award, cosmetic pooled debris.
##
## Damage applies only when the attack category and the attacker's growth stage are allowed
## by the prop's data. At zero health the intact mesh and its blocking collision are removed
## (so the navmesh can be rebuilt without it), ObjectDestroyed fires once, and loot is
## awarded once per world id - reloading or re-breaking never awards it again.

@export var world_id := ""

@onready var entity: CombatEntity = $CombatEntity
@onready var intact: Node3D = $Intact
@onready var broken: Node3D = $Broken

var destroyed := false
var record: Dictionary = {}


func _ready() -> void:
	add_to_group("breakables")
	record = GameData.get_record(entity.definition_id)
	broken.visible = false
	if world_id == "":
		push_error("BreakableProp %s has no world_id" % get_path())
	if WorldState.is_destroyed(world_id):
		_apply_broken_state(false)
		entity.combatant.dead = true


func accepts_hit(hit: HitEvent) -> bool:
	if destroyed:
		return false
	var categories: Array = record.get("accepted_attack_categories", [])
	if not categories.has(hit.category):
		return false
	return hit.attacker_growth_stage >= int(record.get("min_growth_stage", 1))


func on_entity_died(killer_id: String) -> void:
	if destroyed:
		return
	_apply_broken_state(true)
	WorldState.record_destroyed(world_id)
	Events.object_destroyed.emit(Sim.tick, world_id, killer_id)
	if WorldState.try_award_loot(world_id):
		for loot: Dictionary in record.get("loot", []):
			var item := str(loot.get("item", ""))
			var count := int(loot.get("count", 1))
			WorldState.add_item(item, count)
			Events.loot_awarded.emit(Sim.tick, world_id, item, count, killer_id)


func _apply_broken_state(spawn_debris: bool) -> void:
	destroyed = true
	intact.visible = false
	broken.visible = true
	for child in get_children():
		if child is CollisionShape3D and child.name.begins_with("Block"):
			child.queue_free()  # removed (not just disabled) so navmesh rebakes ignore it
	for hb in entity.hurtboxes:
		hb.set_deferred("monitorable", false)
		for c in hb.get_children():
			if c is CollisionShape3D:
				(c as CollisionShape3D).set_deferred("disabled", true)
	if spawn_debris:
		_spawn_debris()


func _spawn_debris() -> void:
	var pool := get_tree().get_first_node_in_group("debris_pool") as DebrisPool
	if pool == null:
		return
	var count := int(record.get("debris_count", 6))
	var pieces: Array[Transform3D] = []
	var velocities: Array[Vector3] = []
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(world_id)
	var length := 8.0
	for i in count:
		var along := (float(i) + 0.5) / count - 0.5
		var local := Vector3(along * length, 0.6 + 0.6 * (i % 2), 0.0)
		var t := Transform3D(Basis(Vector3.UP, rng.randf_range(-0.3, 0.3)) * Basis(Vector3.FORWARD, PI * 0.5 * (i % 2)), local)
		pieces.append(global_transform * t)
		var away := global_transform.basis.z * (1.0 if rng.randf() < 0.5 else -1.0)
		velocities.append(away * rng.randf_range(1.5, 4.0) + Vector3.UP * rng.randf_range(2.0, 5.0))
	pool.spawn(pieces, velocities)
