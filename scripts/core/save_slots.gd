class_name SaveSlots
extends RefCounted
## The one Valley save slot (plan §2.9, decision 14): user://saves/valley_1.json (IndexedDB on
## the web), versioned, written through SaveIO (temp file, verify, one backup, rename).
##
## read() = SaveIO.read_json (main file, else the backup with a "Recovered ..." message, newer
## versions refused) + validate() (a main file whose content is broken also falls back to the
## backup) + sanitize (ids this build no longer knows are dropped, with a message). A file from a
## newer build is copied to valley_1.schemaN.rejected.json so it is never lost, and SaveIO never
## turns it into the backup.
##
## Document: {"schema_version", "build_version", "saved_at_unix", "slot", "level",
##   "checkpoint": {"respawn", "reason"}, "character" (CharacterState), "world"
##   (WorldState.to_save_dict), "stats"}. Tests point path_override at user://test_saves/.

const DIR := "user://saves"
const SLOT := "valley_1"
const SCHEMA_VERSION := 1

## "" = DIR/SLOT.json. GameSession sets it from --save-dir; tests use user://test_saves/.
static var path_override := ""


static func path() -> String:
	if path_override != "":
		return path_override
	return DIR.path_join(SLOT + ".json")


## True when the slot (or its backup) is on disk, readable or not.
static func exists() -> bool:
	var p := path()
	return FileAccess.file_exists(p) or FileAccess.file_exists(p + ".bak")


## Where a save written by a newer build is kept: valley_1.schemaN.rejected.json beside the slot.
static func rejected_path(version: int) -> String:
	return "%s.schema%d.rejected.json" % [path().get_basename(), version]


## Writes `doc` (its schema_version set to SCHEMA_VERSION), creating the folder first.
## Returns {"ok", "message"}; the message names the problem when it failed.
static func write(doc: Dictionary) -> Dictionary:
	var p := path()
	var data := doc.duplicate(true)
	data["schema_version"] = SCHEMA_VERSION
	var dir := p.get_base_dir()
	if not DirAccess.dir_exists_absolute(dir):
		var mk := DirAccess.make_dir_recursive_absolute(dir)
		if mk != OK:
			return {"ok": false, "message": "could not create %s (%s)" % [dir, error_string(mk)]}
	var err := SaveIO.write_json(p, data)
	if err != OK:
		return {"ok": false, "message": "could not write %s (%s)" % [p.get_file(), error_string(err)]}
	return {"ok": true, "message": ""}


## Reads the slot. Returns {"ok", "data", "source": "main"|"backup"|"none", "message",
## "future_version", "dropped"}: data is the validated, sanitized document; message explains a
## recovery, a rejected newer file or dropped ids ("" when the main file loaded cleanly).
static func read() -> Dictionary:
	var p := path()
	var r := SaveIO.read_json(p, SCHEMA_VERSION)
	var out := {"ok": false, "data": {}, "source": str(r.source), "message": str(r.message),
		"future_version": int(r.get("future_version", 0)), "dropped": PackedStringArray()}
	if int(out.future_version) > 0 and FileAccess.file_exists(p):
		var keep := rejected_path(int(out.future_version))
		var main_text := FileAccess.get_file_as_string(p)
		var kept_text := FileAccess.get_file_as_string(keep) if FileAccess.file_exists(keep) else ""
		if main_text != kept_text:
			DirAccess.copy_absolute(p, keep)
		out.message = _join(out.message, "It was kept as %s." % keep.get_file())
	if not r.ok:
		return out
	var data: Dictionary = r.data
	var problems := validate(data)
	if not problems.is_empty():
		if r.source != "main":
			out.source = "none"
			out.message = _join(out.message, "%s.bak is invalid too (%s)." % [p.get_file(), problems[0]])
			return out
		var bak := SaveIO.read_json(p + ".bak", SCHEMA_VERSION)
		var bak_problems := validate(bak.data) if bak.ok else PackedStringArray(["unreadable"])
		if not bak.ok or not bak_problems.is_empty():
			out.source = "none"
			out.message = _join(out.message, "%s is invalid (%s)." % [p.get_file(), problems[0]])
			return out
		data = bak.data
		out.source = "backup"
		out.message = _join(out.message, "%s is invalid (%s). Recovered the previous valid copy from %s.bak." % [
			p.get_file(), problems[0], p.get_file()])
	var clean := sanitize(data)
	out.ok = true
	out.data = clean.data
	out.dropped = clean.dropped
	if not (clean.dropped as PackedStringArray).is_empty():
		out.message = _join(out.message, "Dropped ids this build does not know: %s." % ", ".join(clean.dropped))
	return out


## Structural problems of a save document; [] when it can be loaded.
static func validate(doc: Dictionary) -> PackedStringArray:
	var errors := PackedStringArray()
	var v: Variant = doc.get("schema_version")
	if not SchemaUtil.is_number(v) or float(v) != floorf(float(v)) or int(v) < 1 or int(v) > SCHEMA_VERSION:
		errors.append("schema_version: must be a whole number from 1 to %d" % SCHEMA_VERSION)
	if typeof(doc.get("level")) != TYPE_STRING or str(doc.level) == "":
		errors.append("level: missing or not a string")
	var cp: Variant = doc.get("checkpoint")
	if typeof(cp) != TYPE_DICTIONARY or typeof((cp as Dictionary).get("respawn")) != TYPE_STRING:
		errors.append("checkpoint.respawn: missing or not a string")
	if typeof(doc.get("character")) != TYPE_DICTIONARY:
		errors.append("character: missing or not an object")
	else:
		errors.append_array(CharacterState.validate(doc.character))
	var world: Variant = doc.get("world")
	if typeof(world) != TYPE_DICTIONARY:
		errors.append("world: missing or not an object")
	else:
		var wv: Variant = (world as Dictionary).get("schema_version")
		if not SchemaUtil.is_number(wv) or not (int(wv) in [1, WorldState.SCHEMA_VERSION]):
			errors.append("world.schema_version: must be 1 or %d" % WorldState.SCHEMA_VERSION)
		for key: String in ["deltas", "inventory", "flags"]:
			if (world as Dictionary).has(key) and typeof(world[key]) != TYPE_DICTIONARY:
				errors.append("world.%s: must be an object" % key)
	if doc.has("stats") and typeof(doc.stats) != TYPE_DICTIONARY:
		errors.append("stats: must be an object")
	return errors


## A validated document with the character normalized and unknown ids dropped: abilities,
## weapons, ancestry (CharacterState.sanitize) and inventory items. {"data", "dropped"}.
static func sanitize(doc: Dictionary) -> Dictionary:
	var out := doc.duplicate(true)
	var c := CharacterState.sanitize(doc.character)
	out["character"] = c.data
	var dropped: PackedStringArray = c.dropped
	var world: Dictionary = out.world
	if typeof(world.get("inventory")) == TYPE_DICTIONARY:
		var inventory: Dictionary = world.inventory
		for item: Variant in inventory.keys():
			var id := str(item)
			if not GameData.has_record(id) or str(GameData.get_record(id).get("type", "")) != "item":
				inventory.erase(item)
				if not dropped.has(id):
					dropped.append(id)
	return {"data": out, "dropped": dropped}


## Removes the slot, its backup and a stray temp file; with include_rejected also the
## schemaN.rejected copies (tests only: those copies are a newer build's saves).
static func delete_slot(include_rejected := false) -> void:
	var p := path()
	for f: String in [p, p + ".bak", p + ".tmp"]:
		if FileAccess.file_exists(f):
			DirAccess.remove_absolute(f)
	if not include_rejected:
		return
	var dir := DirAccess.open(p.get_base_dir())
	if dir == null:
		return
	var prefix := p.get_file().get_basename() + ".schema"
	for f in dir.get_files():
		if f.begins_with(prefix) and f.ends_with(".rejected.json"):
			dir.remove(f)


static func _join(a: String, b: String) -> String:
	if a == "":
		return b
	if b == "":
		return a
	return a + " " + b
