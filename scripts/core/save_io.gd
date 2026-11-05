class_name SaveIO
extends RefCounted
## Versioned JSON persistence used for settings now and character/world saves later (M3/M4).
##
## Write: serialize -> write "<path>.tmp" -> read it back and verify -> copy the previous
## valid file to "<path>.bak" -> rename the temp file over the real one. On platforms where
## rename cannot replace an existing file the old file is removed first; the backup keeps a
## valid copy for that window.
## Read: try the main file, fall back to the backup with a clear message, and reject files
## written by a newer schema version instead of guessing.
##
## `loads` (optional, P16): Callable(data: Dictionary) -> bool, the caller's full check of a
## document. The previous main file becomes the backup only when it parses, has a supported
## schema_version AND `loads` accepts it, so a schema-valid but otherwise broken main file never
## replaces the last good backup (the save slot passes SaveSlots.validate).


static func write_json(path: String, data: Dictionary, loads := Callable()) -> Error:
	var text := JSON.stringify(data, "\t", true)
	var tmp := path + ".tmp"
	var file := FileAccess.open(tmp, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(text)
	file.flush()
	file.close()
	var check := JsonIO.read_file(tmp)
	if not check.ok or typeof(check.data) != TYPE_DICTIONARY:
		DirAccess.remove_absolute(tmp)
		return ERR_FILE_CORRUPT
	if FileAccess.file_exists(path):
		# Only a previous file that this build could itself load becomes the backup; a corrupt,
		# newer-version or (with `loads`) invalid main file must never overwrite the last good
		# backup.
		var previous := _try_load(path, int(data.get("schema_version", 1)))
		if previous.ok and loads.is_valid() and not bool(loads.call(previous.data)):
			previous.ok = false
		if previous.ok:
			var copy_err := DirAccess.copy_absolute(path, path + ".bak")
			if copy_err != OK:
				push_warning("SaveIO: could not refresh backup for %s (error %d)" % [path, copy_err])
	var err := DirAccess.rename_absolute(tmp, path)
	if err != OK and FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
		err = DirAccess.rename_absolute(tmp, path)
	return err


## Returns {"ok", "data", "source": "main"|"backup"|"none", "message", "future_version"}.
static func read_json(path: String, supported_version: int) -> Dictionary:
	var main := _try_load(path, supported_version)
	if main.ok:
		return {"ok": true, "data": main.data, "source": "main", "message": "", "future_version": 0}
	var bak := _try_load(path + ".bak", supported_version)
	if bak.ok:
		return {"ok": true, "data": bak.data, "source": "backup",
			"message": "%s Recovered the previous valid copy from %s.bak." % [main.message, path.get_file()],
			"future_version": main.get("future_version", 0)}
	var message := ""
	if FileAccess.file_exists(path):
		message = main.message
		if FileAccess.file_exists(path + ".bak"):
			message += " The backup is unusable too (%s)." % bak.message
	return {"ok": false, "data": {}, "source": "none", "message": message,
		"future_version": main.get("future_version", 0)}


static func _try_load(path: String, supported_version: int) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {"ok": false, "message": "%s is missing." % path.get_file()}
	var parsed := JsonIO.read_file(path)
	if not parsed.ok:
		return {"ok": false, "message": "%s is corrupt (%s)." % [path.get_file(), parsed.error]}
	if typeof(parsed.data) != TYPE_DICTIONARY:
		return {"ok": false, "message": "%s is corrupt (not a JSON object)." % path.get_file()}
	var version: Variant = parsed.data.get("schema_version")
	if not (typeof(version) == TYPE_INT or typeof(version) == TYPE_FLOAT) \
			or float(version) != floorf(float(version)) or int(version) < 1:
		return {"ok": false, "message": "%s has no valid schema_version." % path.get_file()}
	if int(version) > supported_version:
		return {"ok": false, "future_version": int(version),
			"message": "%s was written by a newer version (schema %d; this build supports %d)." % [
				path.get_file(), int(version), supported_version]}
	return {"ok": true, "data": parsed.data}
