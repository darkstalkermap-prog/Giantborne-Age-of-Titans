extends Node
## Content database (autoload "GameData").
##
## Loads every JSON record under res://data at startup, validates it (DataValidator) and
## exposes lookups by stable string id. JSON stays the editable source of truth; ActionDef
## objects are a cached, typed view built after validation.

const DATA_ROOT := "res://data"

signal reloaded

var records: Dictionary = {}       ## id -> raw record (Dictionary)
var record_paths: Dictionary = {}  ## id -> source file
var errors := PackedStringArray()
var warnings := PackedStringArray()
var _actions: Dictionary = {}      ## id -> ActionDef


func _ready() -> void:
	load_all(DATA_ROOT)
	for w in warnings:
		push_warning("[data] " + w)
	for e in errors:
		push_error("[data] " + e)


func load_all(root: String) -> void:
	records.clear()
	record_paths.clear()
	errors.clear()
	warnings.clear()
	_actions.clear()
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
	errors.append_array(DataValidator.validate_references(records, refs))
	for id: String in records:
		if records[id].get("type") == "action":
			_actions[id] = ActionDef.from_dict(records[id])
	reloaded.emit()


func is_valid() -> bool:
	return errors.is_empty()


func has_record(id: String) -> bool:
	return records.has(id)


func get_record(id: String) -> Dictionary:
	return records.get(id, {})


func get_action(id: String) -> ActionDef:
	return _actions.get(id)


func ids_of_type(type: String) -> PackedStringArray:
	var out := PackedStringArray()
	for id: String in records:
		if records[id].get("type") == type:
			out.append(id)
	out.sort()
	return out
