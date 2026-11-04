class_name TestFixtures
extends RefCounted
## Temporary data changes for one test (plan §2.13). record_override() patches a record (deep
## merge) and restore_all() - run by the ResetHooks after every test - puts every patched
## record back, so tests never leak tuning into each other.
##
## Through GameData.override_record / restore_record when they exist (P01: they also refresh
## the cached ActionDef/StatusDef). Before that it patches GameData.records itself and, for
## action records, the cached ActionDef.

## [id, previous, used_api, existed, previous_action]; restored newest first.
static var _saved: Array = []


static func record_override(id: String, patch: Dictionary) -> void:
	if GameData.has_method("override_record"):
		var previous: Variant = GameData.call("override_record", id, patch)
		_saved.append([id, previous, true, true, null])
		return
	var existed := GameData.records.has(id)
	var previous: Dictionary = (GameData.records.get(id, {}) as Dictionary).duplicate(true)
	var merged := previous.duplicate(true)
	deep_merge(merged, patch)
	GameData.records[id] = merged
	var previous_action: Variant = null
	var actions: Variant = GameData.get("_actions")
	if typeof(actions) == TYPE_DICTIONARY and merged.get("type") == "action":
		previous_action = (actions as Dictionary).get(id)
		(actions as Dictionary)[id] = ActionDef.from_dict(merged)
	_saved.append([id, previous, false, existed, previous_action])


## Undo every override, newest first. Returns how many records were restored.
static func restore_all() -> int:
	var restored := _saved.size()
	while not _saved.is_empty():
		var entry: Array = _saved.pop_back()
		var id: String = entry[0]
		if entry[2]:
			GameData.call("restore_record", id, entry[1])
			continue
		if entry[3]:
			GameData.records[id] = entry[1]
		else:
			GameData.records.erase(id)
		var actions: Variant = GameData.get("_actions")
		if typeof(actions) == TYPE_DICTIONARY:
			if entry[4] != null:
				(actions as Dictionary)[id] = entry[4]
			elif not entry[3]:
				(actions as Dictionary).erase(id)
	return restored


static func pending_count() -> int:
	return _saved.size()


## Merges `patch` into `base` in place: nested dictionaries merge, everything else replaces.
static func deep_merge(base: Dictionary, patch: Dictionary) -> void:
	for key: Variant in patch:
		var value: Variant = patch[key]
		if typeof(value) == TYPE_DICTIONARY and typeof(base.get(key)) == TYPE_DICTIONARY:
			deep_merge(base[key], value)
		elif typeof(value) == TYPE_DICTIONARY or typeof(value) == TYPE_ARRAY:
			base[key] = value.duplicate(true)
		else:
			base[key] = value
