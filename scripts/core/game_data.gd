extends Node
## Content database (autoload "GameData").
##
## Loads every JSON record under res://data at startup, validates it (DataValidator) and
## exposes lookups by stable string id. JSON stays the editable source of truth; ActionDef and
## StatusDef objects are cached, typed views built after validation.
##
## Records are shared: get_record() returns the live dictionary. Copy before writing; character
## state belongs in the save, never in records. Tests change records only through
## override_record() / restore_record(), which keep the typed caches in step.

const DATA_ROOT := "res://data"

signal reloaded

## Records the shipped scenes and code look up by id (id -> type), merged from every schema
## module's required_ids(). Missing or mistyped -> startup error.
var REQUIRED_RECORDS: Dictionary = DataValidator.required_records()

var records: Dictionary = {}       ## id -> raw record (Dictionary)
var record_paths: Dictionary = {}  ## id -> source file
var errors := PackedStringArray()
var warnings := PackedStringArray()
var _actions: Dictionary = {}      ## id -> ActionDef
var _statuses: Dictionary = {}     ## id -> StatusDef


func _ready() -> void:
	load_all(DATA_ROOT)
	for w in warnings:
		push_warning("[data] " + w)
	for e in errors:
		push_error("[data] " + e)


## check_required: also verify the ids the shipped scenes/code depend on (REQUIRED_RECORDS).
func load_all(root: String, check_required: bool = true) -> void:
	records.clear()
	record_paths.clear()
	errors.clear()
	warnings.clear()
	_actions.clear()
	_statuses.clear()
	REQUIRED_RECORDS = DataValidator.required_records()
	var refs: Array = []
	var files := JsonIO.list_json_files(root)
	if files.is_empty():
		errors.append("No data files found under %s" % root)
	for path in files:
		var parsed := JsonIO.read_file(path)
		if not parsed.ok:
			errors.append(parsed.error)
			continue
		var result := DataValidator.validate_record(parsed.data, path)
		errors.append_array(result.errors)
		warnings.append_array(result.warnings)
		refs.append_array(result.refs)
		if typeof(parsed.data) != TYPE_DICTIONARY or typeof(parsed.data.get("id")) != TYPE_STRING:
			continue
		var id: String = parsed.data.id
		if records.has(id):
			errors.append("Duplicate id '%s' in %s (first defined in %s)" % [id, path, record_paths[id]])
			continue
		records[id] = parsed.data
		record_paths[id] = path
	if check_required:
		for id: String in REQUIRED_RECORDS:
			refs.append({"ctx": "required by the sandbox scenes/code", "id": id, "type": REQUIRED_RECORDS[id]})
	errors.append_array(DataValidator.validate_references(records, refs))
	for id: String in records:
		_refresh_cache(id)
	_post_pass()
	reloaded.emit()


## Cross-record checks that need every record loaded. Packages add their checks below their
## own anchor only.
func _post_pass() -> void:
	# Decision 25: every enemy attack with a windup of 0.8 s or more needs a telegraph.
	# A warning until P09 (which sets telegraph_is_error = true at its anchor), an error after.
	var telegraph_problems := _untelegraphed_enemy_attacks()
	var telegraph_is_error := false
	## @anchor P09
	telegraph_is_error = true   # P09: decision 25 is enforced (telegraph decals and threat arrows ship)

	if telegraph_is_error:
		errors.append_array(telegraph_problems)
	else:
		warnings.append_array(telegraph_problems)
	## @anchor P10a
	# Encounters (P10a): a spawn entity_id belongs to one encounter only ("Duplicate spawn
	# entity_id '...'"), a spawn's definition is an enemy or npc record, and an encounter's
	# district is one of its level's districts (encounter_schema.gd cross_record_errors).
	if DataValidator.SCHEMAS.has("encounter"):
		errors.append_array(DataValidator.SCHEMAS["encounter"].cross_record_errors(records, record_paths))

	## @anchor P12
	# Progression (P12): the ability library holds abilities and ultimates; a forge upgrade fits at
	# least as high as its source and is one step (the upgraded weapon has no upgrade of its own).
	errors.append_array(Progression.data_errors(records, record_paths))

	pass


## Actions used by an enemy (kind enemy_attack, or listed in an enemy's attacks or in its
## boss.phases[].attacks) with windup_s >= 0.8 and no telegraph.
func _untelegraphed_enemy_attacks() -> PackedStringArray:
	var users := {}   # action id -> description of the first user
	for id: String in ids_of_type("action"):
		if str(records[id].get("kind", "")) == "enemy_attack":
			users[id] = "kind enemy_attack"
	for enemy: Dictionary in records_of_type("enemy"):
		var lists: Array = [enemy.get("attacks", [])]
		var boss: Variant = enemy.get("boss")
		if typeof(boss) == TYPE_DICTIONARY and typeof(boss.get("phases")) == TYPE_ARRAY:
			for phase: Variant in boss.phases:
				if typeof(phase) == TYPE_DICTIONARY:
					lists.append(phase.get("attacks", []))
		for list: Variant in lists:
			if typeof(list) != TYPE_ARRAY:
				continue
			for action_id: Variant in list:
				if typeof(action_id) == TYPE_STRING and not users.has(action_id):
					users[action_id] = "used by %s" % enemy.get("id", "?")
	var out := PackedStringArray()
	var ids := users.keys()
	ids.sort()
	for action_id: String in ids:
		var rec: Dictionary = records.get(action_id, {})
		if rec.is_empty() or rec.get("type") != "action":
			continue  # a missing or mistyped reference is already an error
		var windup: Variant = rec.get("windup_s", 0.0)
		if SchemaUtil.is_number(windup) and float(windup) >= 0.8 - 1e-6 and not rec.has("telegraph"):
			out.append("%s (%s): enemy attack (%s) with windup_s %s >= 0.8 s has no telegraph (decision 25)" % [
				record_paths.get(action_id, "?"), action_id, users[action_id], windup])
	return out


func is_valid() -> bool:
	return errors.is_empty()


func has_record(id: String) -> bool:
	return records.has(id)


func get_record(id: String) -> Dictionary:
	return records.get(id, {})


func get_action(id: String) -> ActionDef:
	return _actions.get(id)


func get_status(id: String) -> StatusDef:
	return _statuses.get(id)


func ids_of_type(type: String) -> PackedStringArray:
	var out := PackedStringArray()
	for id: String in records:
		if records[id].get("type") == type:
			out.append(id)
	out.sort()
	return out


## The raw records of one type, sorted by id (live dictionaries; copy before writing).
func records_of_type(type: String) -> Array:
	var out: Array = []
	for id in ids_of_type(type):
		out.append(records[id])
	return out


## Deep-merges `patch` into records[id] (dictionaries merge recursively; arrays and values are
## replaced), refreshes the ActionDef / StatusDef caches in place (holders of the cached object,
## such as CombatController.library, see the change) and returns the previous record for
## restore_record(). An unknown id creates the record from the patch (previous = {}).
## The patched record is not validated: this is a test and tooling seam.
## Restore several overrides of one id in reverse order (last override first).
func override_record(id: String, patch: Dictionary) -> Dictionary:
	var previous: Dictionary = (records.get(id, {}) as Dictionary).duplicate(true)
	var merged := previous.duplicate(true)
	_deep_merge(merged, patch)
	if not merged.has("id"):
		merged["id"] = id
	records[id] = merged
	_refresh_cache(id)
	return previous


## Puts back a record returned by override_record(). An empty `previous` removes the record
## (it did not exist before the override).
func restore_record(id: String, previous: Dictionary) -> void:
	if previous.is_empty():
		records.erase(id)
		_actions.erase(id)
		_statuses.erase(id)
		return
	records[id] = previous.duplicate(true)
	_refresh_cache(id)


func _refresh_cache(id: String) -> void:
	var rec: Dictionary = records.get(id, {})
	match str(rec.get("type", "")):
		"action":
			_statuses.erase(id)
			var a: ActionDef = _actions.get(id)
			if a == null:
				_actions[id] = ActionDef.from_dict(rec)
			else:
				a.fill(rec)
		"status_effect":
			_actions.erase(id)
			var s: StatusDef = _statuses.get(id)
			if s == null:
				_statuses[id] = StatusDef.from_dict(rec)
			else:
				s.fill(rec)
		_:
			_actions.erase(id)
			_statuses.erase(id)


static func _deep_merge(target: Dictionary, patch: Dictionary) -> void:
	for k: Variant in patch:
		var v: Variant = patch[k]
		if typeof(v) == TYPE_DICTIONARY and typeof(target.get(k)) == TYPE_DICTIONARY:
			_deep_merge(target[k], v)
		elif typeof(v) == TYPE_DICTIONARY or typeof(v) == TYPE_ARRAY:
			target[k] = v.duplicate(true)
		else:
			target[k] = v
