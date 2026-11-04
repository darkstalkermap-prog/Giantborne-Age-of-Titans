class_name HitRegistry
extends RefCounted
## Hit de-duplication keyed by (attack instance, pulse, target ENTITY) - never by collider.
## A sweep that overlaps three hurtboxes of one enemy therefore lands one hit.

var _by_instance: Dictionary = {}   ## instance_id -> {"pulse:entity" -> count}


func try_register(instance_id: int, pulse_id: int, entity_id: String, max_hits: int) -> bool:
	var per: Dictionary = _by_instance.get(instance_id, {})
	var key := "%d:%s" % [pulse_id, entity_id]
	var count: int = per.get(key, 0)
	if count >= maxi(1, max_hits):
		return false
	per[key] = count + 1
	_by_instance[instance_id] = per
	return true


func hits_for(instance_id: int, pulse_id: int, entity_id: String) -> int:
	return int((_by_instance.get(instance_id, {}) as Dictionary).get("%d:%s" % [pulse_id, entity_id], 0))


func forget(instance_id: int) -> void:
	_by_instance.erase(instance_id)


func clear() -> void:
	_by_instance.clear()
