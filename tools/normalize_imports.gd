extends SceneTree
## Makes the imported glTF scenes the same bytes in every checkout (P49; plan M11 §3.2 item 5).
##
## The scene importer packs the scene it built from a .glb and saves it under .godot/imported/, and packing
## gives every node a random unique id (the engine's cryptographic generator: it cannot be seeded, and a
## post-import script cannot set the ids). An export packs that imported file as it is, so two checkouts
## that each imported assets/giant/giant.glb exported packs that differed in exactly that file (128 bytes at
## 0.10.0-m10: 28 node ids and the file's checksum), whatever the scenes' own ids (tools/scene_kit.gd).
##
## This tool rewrites each imported scene's node ids to stable ones - SceneKit.stable_node_id(the source
## file's path, the node's path) - through PackedScene._bundled["node_ids"], saves it where it was (compressed
## when it was) and writes the new checksum into the import's .md5 file, so the editor does not import it
## again. Nothing else in the file changes; a scene that already has its stable ids is left alone, so a
## second run writes nothing. tools/build_web.sh runs it before every export.
##
##   tools/gd.sh --headless --path . -s res://tools/normalize_imports.gd [-- --check]
##
## Prints NORMALIZE_IMPORTS {"scenes": n, "rewritten": n, "nodes": n, "files": [...]} and exits 0; with
## --check it writes nothing and exits 1 when a scene would be rewritten. Tools only: never exported.

const SCENE_KIT := "res://tools/scene_kit.gd"

var _started := false


func _initialize() -> void:
	process_frame.connect(_run)


static func _imports(dir: String, out: PackedStringArray) -> void:
	var d := DirAccess.open(dir)
	if d == null:
		return
	for f in d.get_files():
		if f.ends_with(".import"):
			out.append(dir.path_join(f))
	for sub in d.get_directories():
		if not sub.begins_with(".") and not d.file_exists(sub.path_join(".gdignore")):
			_imports(dir.path_join(sub), out)


## The imported scene of `import_path` (a .import file of the scene importer): "" for any other import.
static func imported_scene_of(import_path: String) -> String:
	var cfg := ConfigFile.new()
	if cfg.load(import_path) != OK or str(cfg.get_value("remap", "importer", "")) != "scene":
		return ""
	var dest := str(cfg.get_value("remap", "path", ""))
	return dest if dest.ends_with(".scn") and FileAccess.file_exists(dest) else ""


## The stable ids of the nodes of `ps`, the imported scene of the source file `source`.
static func stable_ids(ps: PackedScene, source: String, kit: GDScript) -> PackedInt32Array:
	var state := ps.get_state()
	var out := PackedInt32Array()
	var used := {}
	for i in state.get_node_count():
		var node_path := str(state.get_node_path(i))
		var salt := 0
		var id: int = kit.call("stable_node_id", source, node_path, salt)
		while used.has(id):
			salt += 1
			id = kit.call("stable_node_id", source, node_path, salt)
		used[id] = true
		out.append(id)
	return out


## Rewrites the imported scene at `dest` (of `source`) when its ids are not the stable ones. Returns the
## number of nodes rewritten (0: already stable; -1: it could not be read or written).
static func normalize(dest: String, source: String, kit: GDScript, write := true) -> int:
	var ps := ResourceLoader.load(dest, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
	if ps == null:
		return -1
	var bundle: Dictionary = ps._bundled
	var want := stable_ids(ps, source, kit)
	var have: Variant = bundle.get("node_ids", PackedInt32Array())
	if typeof(have) == TYPE_PACKED_INT32_ARRAY and have == want:
		return 0
	if not write:
		return want.size()
	var head := FileAccess.open(dest, FileAccess.READ)
	var compressed := head != null and head.get_buffer(4).get_string_from_ascii() == "RSCC"
	if head != null:
		head.close()
	bundle["node_ids"] = want
	ps._bundled = bundle
	if ResourceSaver.save(ps, dest, ResourceSaver.FLAG_COMPRESS if compressed else ResourceSaver.FLAG_NONE) != OK:
		return -1
	# The import's record of what it wrote: the editor imports the file again when this does not match.
	var md5_path := dest.get_basename() + ".md5"
	if FileAccess.file_exists(md5_path):
		var cfg := FileAccess.get_file_as_string(md5_path)
		var re := RegEx.create_from_string("dest_md5=\"[0-9a-f]*\"")
		var f := FileAccess.open(md5_path, FileAccess.WRITE)
		if f == null:
			return -1
		f.store_string(re.sub(cfg, "dest_md5=\"%s\"" % FileAccess.get_md5(dest)))
		f.close()
	return want.size()


func _run() -> void:
	if _started:
		return
	_started = true
	var check := OS.get_cmdline_user_args().has("--check")
	var kit := load(SCENE_KIT) as GDScript
	var imports := PackedStringArray()
	_imports("res://", imports)
	imports.sort()
	var out := {"scenes": 0, "rewritten": 0, "nodes": 0, "files": [], "failed": []}
	for import_path in imports:
		var dest := imported_scene_of(import_path)
		if dest == "":
			continue
		out.scenes += 1
		var n := normalize(dest, import_path.trim_suffix(".import"), kit, not check)
		if n < 0:
			(out.failed as Array).append(import_path)
		elif n > 0:
			out.rewritten += 1
			out.nodes += n
			(out.files as Array).append(import_path.trim_suffix(".import"))
	print("NORMALIZE_IMPORTS " + JSON.stringify(out))
	quit(1 if not (out.failed as Array).is_empty() or (check and int(out.rewritten) > 0) else 0)
