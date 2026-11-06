class_name SaveSlots
extends RefCounted
## The one Valley save slot (plan §2.9, decision 14): user://saves/valley_1.json (IndexedDB on
## the web), versioned, written through SaveIO (temp file, verify, one backup, rename).
##
## read() = SaveIO.read_json (main file, else the backup with a "Recovered ..." message, newer
## versions refused) + migrate() (P20: an older document is brought up to SCHEMA_VERSION, one
## pure step per version) + validate() (a main file whose content is broken also falls back to
## the backup, which is migrated the same way) + sanitize (ids this build no longer knows are
## dropped, with a message). A file from a newer build is copied to valley_1.schemaN.rejected.json
## so it is never lost, and SaveIO never turns it into the backup. A load from the backup tells the
## player: "Your last save was damaged; the previous one was loaded." (then the details).
##
## Document (schema 2, P20; plan M6-M9 §2.6): {"schema_version", "build_version", "saved_at_unix",
##   "slot", "level", "checkpoint": {"respawn", "reason", "position": [x, y, z], "yaw"},
##   "character" (CharacterState: talents and ancestry_chosen since schema 2), "world"
##   (WorldState.to_save_dict, its own schema 2), "progress": {"prologue_complete",
##   "world_entered", "levels_visited", "tracked_quest"}, "stats"}. Schema 1 (the 0.5.0 Valley
##   build) had no progress, no checkpoint position and neither character key; _migrate_1_to_2
##   adds them. The slot name and the project name stay, so desktop and web saves are kept.
##   Tests point path_override at user://test_saves/.

const DIR := "user://saves"
const SLOT := "valley_1"
const SCHEMA_VERSION := 2
## Shown when the main file could not be loaded and the backup was (the details follow).
const RECOVERED_TEXT := "Your last save was damaged; the previous one was loaded."

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
## P16 (M3 review): a main file written by a newer build is kept as its schemaN.rejected copy
## before it is replaced (every path that writes - a checkpoint after --mode=valley --new-game
## too - not only a read from the title), and the previous main file becomes the backup only when
## it fully loads (validate() passes), so an invalid main never replaces the last good backup.
static func write(doc: Dictionary) -> Dictionary:
	var p := path()
	var data := doc.duplicate(true)
	data["schema_version"] = SCHEMA_VERSION
	var dir := p.get_base_dir()
	if not DirAccess.dir_exists_absolute(dir):
		var mk := DirAccess.make_dir_recursive_absolute(dir)
		if mk != OK:
			return {"ok": false, "message": "could not create %s (%s)" % [dir, error_string(mk)]}
	keep_newer_main()
	var err := SaveIO.write_json(p, data, loads)
	if err != OK:
		return {"ok": false, "message": "could not write %s (%s)" % [p.get_file(), error_string(err)]}
	return {"ok": true, "message": ""}


## SaveIO.write_json's backup check: true when `doc` would load (migrated, validate() finds
## nothing), so an older valid main file still becomes the backup.
static func loads(doc: Dictionary) -> bool:
	return validate(migrate(doc)).is_empty()


## When the main file was written by a newer build (schema_version above SCHEMA_VERSION), copies it
## to rejected_path() (unless an identical copy is there) and returns that path; "" otherwise.
static func keep_newer_main() -> String:
	var p := path()
	if not FileAccess.file_exists(p):
		return ""
	var parsed := JsonIO.read_file(p)
	if not parsed.ok or typeof(parsed.data) != TYPE_DICTIONARY:
		return ""
	var v: Variant = (parsed.data as Dictionary).get("schema_version")
	if not SchemaUtil.is_number(v) or int(v) <= SCHEMA_VERSION:
		return ""
	var keep := rejected_path(int(v))
	var main_text := FileAccess.get_file_as_string(p)
	var kept_text := FileAccess.get_file_as_string(keep) if FileAccess.file_exists(keep) else ""
	if main_text != kept_text:
		DirAccess.copy_absolute(p, keep)
	return keep


## Reads the slot. Returns {"ok", "data", "source": "main"|"backup"|"none", "message",
## "future_version", "dropped"}: data is the validated, sanitized document; message explains a
## recovery, a rejected newer file or dropped ids ("" when the main file loaded cleanly).
static func read() -> Dictionary:
	var p := path()
	var r := SaveIO.read_json(p, SCHEMA_VERSION)
	var out := {"ok": false, "data": {}, "source": str(r.source), "message": str(r.message),
		"future_version": int(r.get("future_version", 0)), "dropped": PackedStringArray()}
	if int(out.future_version) > 0 and FileAccess.file_exists(p):
		var keep := keep_newer_main()
		if keep == "":
			keep = rejected_path(int(out.future_version))
		out.message = _join(out.message, "It was kept as %s." % keep.get_file())
	if not r.ok:
		return out
	var data: Dictionary = migrate(r.data)
	var problems := validate(data)
	if not problems.is_empty():
		if r.source != "main":
			out.source = "none"
			out.message = _join(out.message, "%s.bak is invalid too (%s)." % [p.get_file(), problems[0]])
			return out
		var bak := SaveIO.read_json(p + ".bak", SCHEMA_VERSION)
		var bak_data: Dictionary = migrate(bak.data) if bak.ok else {}
		var bak_problems := validate(bak_data) if bak.ok else PackedStringArray(["unreadable"])
		if not bak.ok or not bak_problems.is_empty():
			out.source = "none"
			out.message = _join(out.message, "%s is invalid (%s)." % [p.get_file(), problems[0]])
			return out
		data = bak_data
		out.source = "backup"
		out.message = _join(out.message, "%s is invalid (%s). Recovered the previous valid copy from %s.bak." % [
			p.get_file(), problems[0], p.get_file()])
	# A damaged main file (not one a newer build wrote: its message says so) leads with the plain line.
	if str(out.source) == "backup" and int(out.future_version) == 0:
		out.message = _join(RECOVERED_TEXT, str(out.message))
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
	# Schema 2 (P20): the respawn's position and yaw, and the campaign's progress.
	if typeof(cp) == TYPE_DICTIONARY:
		var pos: Variant = (cp as Dictionary).get("position")
		if pos != null and not _is_vec3(pos):
			errors.append("checkpoint.position: must be [x, y, z]")
		var yaw: Variant = (cp as Dictionary).get("yaw")
		if yaw != null and not SchemaUtil.is_number(yaw):
			errors.append("checkpoint.yaw: must be a number")
	if doc.has("progress"):
		var prog: Variant = doc.progress
		if typeof(prog) != TYPE_DICTIONARY:
			errors.append("progress: must be an object")
		else:
			for key: String in ["prologue_complete", "world_entered"]:
				if (prog as Dictionary).has(key) and typeof(prog[key]) != TYPE_BOOL:
					errors.append("progress.%s: must be true or false" % key)
			if (prog as Dictionary).has("levels_visited") and typeof(prog.levels_visited) != TYPE_ARRAY:
				errors.append("progress.levels_visited: must be an array")
			if (prog as Dictionary).has("tracked_quest") and typeof(prog.tracked_quest) != TYPE_STRING:
				errors.append("progress.tracked_quest: must be a string")
	return errors


# --------------------------------------------------------------------------- migration (P20)

## Brings a document written by an older build up to SCHEMA_VERSION: one pure step per version
## (_migrate_1_to_2), on a copy. A document without a usable schema_version, or one newer than
## this build, comes back unchanged (validate() and SaveIO report those).
static func migrate(doc: Dictionary) -> Dictionary:
	var out := doc.duplicate(true)
	var v: Variant = out.get("schema_version")
	if not SchemaUtil.is_number(v) or float(v) != floorf(float(v)) or int(v) < 1:
		return out
	var version := int(v)
	while version < SCHEMA_VERSION:
		match version:
			1:
				out = _migrate_1_to_2(out)
		version += 1
		out["schema_version"] = version
	return out


## Schema 1 -> 2 (plan M6-M9 §2.6, decision 16): character.talents [] and
## character.ancestry_chosen (false unless the ancestry is not ancestry.neutral); the progress
## block (prologue_complete from the flag slice.completed, world_entered false, levels_visited the
## save's level, tracked_quest ""); checkpoint.position and yaw from the level's world index when
## it knows the respawn. Nothing else changes (the world block is already its own schema 2).
static func _migrate_1_to_2(doc: Dictionary) -> Dictionary:
	var out := doc
	var c: Variant = out.get("character")
	if typeof(c) == TYPE_DICTIONARY:
		var ch: Dictionary = c
		if not ch.has("talents"):
			ch["talents"] = []
		if not ch.has("ancestry_chosen"):
			var anc: Variant = ch.get("ancestry")
			ch["ancestry_chosen"] = typeof(anc) == TYPE_STRING and str(anc) != "" \
				and str(anc) != CharacterState.DEFAULT_ANCESTRY
	var flags: Dictionary = {}
	var world: Variant = out.get("world")
	if typeof(world) == TYPE_DICTIONARY and typeof((world as Dictionary).get("flags")) == TYPE_DICTIONARY:
		flags = world.flags
	var level := str(out.get("level", "")) if typeof(out.get("level")) == TYPE_STRING else ""
	if not out.has("progress"):
		out["progress"] = {"prologue_complete": QuestConditions.truthy(flags.get("slice.completed")),
			"world_entered": false, "levels_visited": [level if level != "" else "level.valley"],
			"tracked_quest": ""}
	var cp: Variant = out.get("checkpoint")
	if typeof(cp) == TYPE_DICTIONARY and not (cp as Dictionary).has("position") and level != "":
		var respawn := str((cp as Dictionary).get("respawn", ""))
		var idx := WorldIndex.for_level(level)
		if respawn != "" and idx != null and idx.has_checkpoint(respawn):
			var e := idx.checkpoint(respawn)
			var pos: Vector3 = e.position
			cp["position"] = [pos.x, pos.y, pos.z]
			cp["yaw"] = float(e.get("yaw", 0.0))
	return out


static func _is_vec3(v: Variant) -> bool:
	if typeof(v) != TYPE_ARRAY or (v as Array).size() != 3:
		return false
	for c: Variant in v:
		if not SchemaUtil.is_number(c):
			return false
	return true


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
