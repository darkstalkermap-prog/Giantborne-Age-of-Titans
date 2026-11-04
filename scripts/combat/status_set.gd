class_name StatusSet
extends RefCounted
## The active statuses of one combatant (spec section 8). Engine-free; ticked centrally by the
## Sim status pass (CombatEntity.tick_statuses), never by actors.
##
## Stacking policies:
##   refresh_no_stack  re-applying refreshes the duration and keeps the magnitude (Stone Skin)
##   strongest_wins    keeps the larger magnitude and refreshes the duration (slow)
##   independent       every application is its own instance (not used in the slice)
## Timing: applied at tick T with duration D ticks -> active through T + D - 1, removed by the
## status pass on T + D. Periodic effects tick every tick_ticks after application (restarted on
## refresh), the last one on the expiry tick: Mend heals 8 x 12.5 = 100 over 4 s.

signal changed

## One active instance: {"def": StatusDef, "magnitude": float, "source": String,
## "applied_tick": int, "expires_tick": int, "next_tick": int, "modifiers": Dictionary, "seq": int}
var _instances: Array = []
var _seq := 0


## Returns false (and changes nothing) when one of def.tags is in `immunities`.
## magnitude NAN = def.default_magnitude; duration_s <= 0 = the def's duration.
func apply(def: StatusDef, magnitude: float, duration_s: float, source_id: String, now: int,
		immunities: PackedStringArray) -> bool:
	if def == null:
		return false
	for tag in def.tags:
		if immunities.has(tag):
			return false
	var mag := def.default_magnitude if is_nan(magnitude) else magnitude
	var ticks := def.duration_ticks
	if duration_s > 0.0:
		ticks = maxi(1, ActionDef.seconds_to_ticks(duration_s))
	var existing := _find(def.id)
	if def.stacking != "independent" and not existing.is_empty():
		if def.stacking == "strongest_wins" and mag > float(existing.magnitude):
			existing.magnitude = mag
			existing.modifiers = _modifiers_for(def, mag)
		existing.def = def
		existing.applied_tick = now
		existing.expires_tick = now + ticks
		existing.next_tick = now + def.tick_ticks if def.tick_ticks > 0 else -1
		existing.source = source_id
		changed.emit()
		return true
	_seq += 1
	_instances.append({"def": def, "magnitude": mag, "source": source_id, "applied_tick": now,
		"expires_tick": now + ticks, "next_tick": now + def.tick_ticks if def.tick_ticks > 0 else -1,
		"modifiers": _modifiers_for(def, mag), "seq": _seq})
	_instances.sort_custom(_less)
	changed.emit()
	return true


func remove(status_id: String) -> void:
	var before := _instances.size()
	_instances = _instances.filter(func(i: Dictionary) -> bool: return i.def.id != status_id)
	if _instances.size() != before:
		changed.emit()


func clear() -> void:
	if _instances.is_empty():
		return
	_instances.clear()
	changed.emit()


func has(status_id: String) -> bool:
	return not _find(status_id).is_empty()


func is_empty() -> bool:
	return _instances.is_empty()


func count() -> int:
	return _instances.size()


## Ids of the active statuses, sorted (one entry per id).
func active_ids() -> PackedStringArray:
	var out := PackedStringArray()
	for i in _instances:
		if not out.has(i.def.id):
			out.append(i.def.id)
	return out


## The magnitude of the longest-running instance of status_id (NAN when inactive).
func magnitude(status_id: String) -> float:
	var inst := _find(status_id)
	return float(inst.magnitude) if not inst.is_empty() else NAN


## Seconds until status_id expires (the longest instance); 0 when inactive.
func remaining_s(status_id: String, now: int) -> float:
	var best := 0
	for i in _instances:
		if i.def.id == status_id:
			best = maxi(best, int(i.expires_tick) - now)
	return best / float(ActionDef.TICK_RATE)


## Advances periodic effects and expiry for tick `now`. Returns the effects, in status-id order:
## [{"type": "heal", "id", "amount", "source"}, {"type": "expired", "id"}, ...]. A heal due on
## the expiry tick comes before that status's "expired" entry.
func tick(now: int) -> Array:
	var out: Array = []
	if _instances.is_empty():
		return out
	var expired := false
	for inst in _instances:
		var def: StatusDef = inst.def
		if def.tick_ticks > 0:
			var guard := 0
			while int(inst.next_tick) >= 0 and now >= int(inst.next_tick) \
					and int(inst.next_tick) <= int(inst.expires_tick) and guard < 64:
				var heal := float((inst.modifiers as Dictionary).get("heal_per_tick", 0.0))
				if heal > 0.0:
					out.append({"type": "heal", "id": def.id, "amount": heal, "source": inst.source})
				inst.next_tick = int(inst.next_tick) + def.tick_ticks
				guard += 1
		if now >= int(inst.expires_tick):
			inst["expired"] = true
			expired = true
			out.append({"type": "expired", "id": def.id})
	if expired:
		_instances = _instances.filter(func(i: Dictionary) -> bool: return not i.get("expired", false))
		changed.emit()
	return out


## Sum of `key` over the active statuses that set it (0 when none).
func modifier_sum(key: String) -> float:
	var total := 0.0
	for i in _instances:
		total += float((i.modifiers as Dictionary).get(key, 0.0))
	return total


## Product of `key` over the active statuses that set it (1 when none).
func modifier_product(key: String) -> float:
	var total := 1.0
	for i in _instances:
		var m: Dictionary = i.modifiers
		if m.has(key):
			total *= float(m[key])
	return total


## Largest value of `key` over the active statuses that set it (0 when none).
func modifier_max(key: String) -> float:
	var best := 0.0
	var found := false
	for i in _instances:
		var m: Dictionary = i.modifiers
		if m.has(key):
			best = float(m[key]) if not found else maxf(best, float(m[key]))
			found = true
	return best


## HUD rows: [{"id", "label", "remaining_s", "debuff"}] sorted by id, one per status id
## (the longest instance), hidden statuses left out.
func hud_list(now: int) -> Array:
	var rows := {}
	for i in _instances:
		var def: StatusDef = i.def
		if def.hidden:
			continue
		var remaining := maxi(0, int(i.expires_tick) - now) / float(ActionDef.TICK_RATE)
		if rows.has(def.id) and float(rows[def.id].remaining_s) >= remaining:
			continue
		rows[def.id] = {"id": def.id, "label": def.hud_label, "remaining_s": remaining,
			"debuff": def.is_debuff()}
	var ids := rows.keys()
	ids.sort()
	var out: Array = []
	for id: String in ids:
		out.append(rows[id])
	return out


func _find(status_id: String) -> Dictionary:
	var best: Dictionary = {}
	for i in _instances:
		if i.def.id == status_id and (best.is_empty() or int(i.expires_tick) > int(best.expires_tick)):
			best = i
	return best


static func _modifiers_for(def: StatusDef, mag: float) -> Dictionary:
	var m := def.modifiers.duplicate()
	if def.magnitude_key != "":
		m[def.magnitude_key] = mag
	return m


static func _less(a: Dictionary, b: Dictionary) -> bool:
	if a.def.id != b.def.id:
		return a.def.id < b.def.id
	return int(a.seq) < int(b.seq)
