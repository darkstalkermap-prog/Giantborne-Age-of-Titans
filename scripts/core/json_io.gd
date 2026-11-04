class_name JsonIO
extends RefCounted
## Small JSON helpers with readable error messages.


## Reads and parses one JSON file. Returns {"ok": bool, "data": Variant, "error": String}.
static func read_file(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {"ok": false, "data": null, "error": "File not found: %s" % path}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {"ok": false, "data": null,
			"error": "Cannot open %s (error %d)" % [path, FileAccess.get_open_error()]}
	var text := file.get_as_text()
	file.close()
	return parse_text(text, path)


static func parse_text(text: String, source: String) -> Dictionary:
	var json := JSON.new()
	var err := json.parse(text)
	if err != OK:
		return {"ok": false, "data": null, "error": "%s:%d: JSON parse error: %s" % [
			source, json.get_error_line(), json.get_error_message()]}
	return {"ok": true, "data": json.data, "error": ""}


## Lists every *.json file below root (recursive), sorted for deterministic load order.
static func list_json_files(root: String) -> PackedStringArray:
	var out := PackedStringArray()
	_collect(root, out)
	out.sort()
	return out


static func _collect(dir_path: String, out: PackedStringArray) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if not entry.begins_with("."):
			var full := dir_path.path_join(entry)
			if dir.current_is_dir():
				_collect(full, out)
			elif entry.ends_with(".json"):
				out.append(full)
		entry = dir.get_next()
	dir.list_dir_end()
