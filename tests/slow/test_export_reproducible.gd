extends TestSuite
## P49 (plan M11 §3.2 item 5; the 0.10.0-m10 release's finding "a Web export is not the same bytes in two
## checkouts"): an export converts every text scene to binary by loading it, instancing it and packing it
## again (the engine's EditorExportPlatform::_export_customize), and packing gives every node that has no
## unique id a random one. The scene files carried none (SceneKit stripped them), so each checkout's
## conversions differed; the release was built with one conversion copied by hand. SceneKit now writes a
## stable id for every node (tools/scene_kit.gd, stable_unique_ids), and tools/build_web.sh exports from an
## empty conversion cache and prints the pack's SHA-256.
##   * the conversion, done here as the export does it, twice: the same bytes for the giant's model, the
##     giant, a soldier, the main scene and the Valley;
##   * the control: the same scene's text without its ids converts to different bytes each time (the
##     engine's behaviour this package works round - if a later engine stops doing so, this says so);
##   * every scene an export packs (scenes/**) has an id on every node, the kit's own;
##   * an imported glTF scene (the importer gives its nodes random ids at every import, and the pack holds
##     the imported file as it is): tools/normalize_imports.gd gives a copy of the giant's imported scene,
##     its ids scrambled, the stable ones - the same bytes whatever the ids were - and writes the file's
##     checksum where the editor looks for it; a second pass changes nothing;
##   * build_web.sh empties .godot/exported/ unless told to keep it, normalizes the imports before the
##     export, and writes the checksum.
## Two real exports of one commit in two checkouts are in docs/PERFORMANCE.md (they take minutes).

const DIR := "user://test_export_reproducible"
const SCENES := ["res://scenes/player/giant_model.tscn", "res://scenes/player/giant.tscn",
	"res://scenes/enemies/soldier.tscn", "res://scenes/main.tscn", "res://scenes/world/valley.tscn"]
const BUILD_WEB := "res://tools/build_web.sh"
const NORMALIZE := "res://tools/normalize_imports.gd"
const GIANT_GLB := "res://assets/giant/giant.glb"


func before_each() -> void:
	DirAccess.make_dir_recursive_absolute(DIR)


func after_each() -> void:
	var d := DirAccess.open(DIR)
	if d != null:
		for f in d.get_files():
			d.remove(f)
	DirAccess.remove_absolute(DIR)


## The scene at `path` converted to a binary scene, as an export converts it: its bytes. Every conversion
## of one scene is saved at the same path, as an export's is (.godot/exported/<hash>/export-<md5>-<name>.scn:
## the saver seeds the ids it gives a scene's external resources from the path it saves to).
func _convert(path: String) -> PackedByteArray:
	var ps := ResourceLoader.load(path, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
	if ps == null:
		return PackedByteArray()
	var node := ps.instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE)
	if node == null:
		return PackedByteArray()
	var out := PackedScene.new()
	out.pack(node)
	node.free()
	var to := DIR.path_join("export-" + path.md5_text() + "-" + path.get_file().get_basename() + ".scn")
	if ResourceSaver.save(out, to) != OK:
		return PackedByteArray()
	return FileAccess.get_file_as_bytes(to)


func test_a_scene_converts_to_the_same_bytes_twice() -> void:
	for path: String in SCENES:
		var a := _convert(path)
		_convert(SCENES[(SCENES.find(path) + 1) % SCENES.size()])   # another conversion in between
		var b := _convert(path)
		assert_true(a.size() > 200, "%s converts (%d bytes)" % [path.get_file(), a.size()])
		assert_true(a == b, "%s: two conversions give the same %d bytes" % [path.get_file(), a.size()])


func test_without_its_ids_a_scene_converts_differently_each_time() -> void:
	var src := "res://scenes/enemies/soldier.tscn"
	var text := FileAccess.get_file_as_string(src)
	var stripped := SceneKit.new().strip_unique_ids(text)
	assert_true(text.contains(" unique_id=") and not stripped.contains(" unique_id="), "the soldier's ids are taken out")
	var plain := DIR.path_join("soldier_plain.tscn")
	var f := FileAccess.open(plain, FileAccess.WRITE)
	f.store_string(stripped)
	f.close()
	var a := _convert(plain)
	var b := _convert(plain)
	assert_true(a.size() > 200 and a.size() == b.size(), "it still converts, to the same size (%d, %d)" % [a.size(), b.size()])
	assert_true(a != b, "but not to the same bytes: the engine gave each node a random id, twice")
	var differing := 0
	for i in mini(a.size(), b.size()):
		if a[i] != b[i]:
			differing += 1
	var nodes := stripped.count("\n[node ")
	assert_true(differing > 0 and differing <= 4 * nodes, "only the ids differ: %d bytes for %d nodes" % [differing, nodes])


static func _scenes_under(dir: String, out: PackedStringArray) -> void:
	var d := DirAccess.open(dir)
	if d == null:
		return
	for f in d.get_files():
		if f.ends_with(".tscn"):
			out.append(dir.path_join(f))
	for sub in d.get_directories():
		_scenes_under(dir.path_join(sub), out)


func test_every_packed_scene_has_an_id_on_every_node() -> void:
	var paths := PackedStringArray()
	_scenes_under("res://scenes", paths)
	assert_true(paths.size() >= 100, "the project's scenes (%d)" % paths.size())
	var id_re := RegEx.create_from_string(" unique_id=([0-9]+)")
	var nodes := 0
	var bad: Array = []
	for path in paths:
		var seen := {}
		for line in FileAccess.get_file_as_string(path).split("\n"):
			if not line.begins_with("[node "):
				continue
			nodes += 1
			var m := id_re.search(line)
			if m == null or int(m.get_string(1)) <= 0 or seen.has(m.get_string(1)):
				if bad.size() < 5:
					bad.append("%s: %s" % [path, line.left(80)])
			elif m != null:
				seen[m.get_string(1)] = true
	assert_true(nodes > 3000, "their nodes (%d)" % nodes)
	assert_eq(bad, [], "every node line has its own positive unique_id")
	# The root's id is the kit's (the whole rule is tests/unit/test_scene_kit.gd's).
	for path: String in SCENES:
		assert_true(FileAccess.get_file_as_string(path).contains(" unique_id=%d" % SceneKit.stable_node_id(path, ".")),
			"%s: the root carries the kit's id" % path.get_file())


## A copy of the giant's imported scene at `to`, every node id replaced by `ids_from(i)`; its checksum file beside it.
func _scrambled_copy(imported: String, to: String, ids_from: Callable) -> void:
	var ps := ResourceLoader.load(imported, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
	var bundle: Dictionary = ps._bundled
	var ids := PackedInt32Array()
	for i in ps.get_state().get_node_count():
		ids.append(int(ids_from.call(i)))
	bundle["node_ids"] = ids
	ps._bundled = bundle
	assert_eq(ResourceSaver.save(ps, to, ResourceSaver.FLAG_COMPRESS), OK, "a copy of the imported scene is written")
	var f := FileAccess.open(to.get_basename() + ".md5", FileAccess.WRITE)
	f.store_string("source_md5=\"0123\"\ndest_md5=\"%s\"\n\n" % FileAccess.get_md5(to))
	f.close()


func test_an_imported_scene_gets_the_same_ids_whatever_the_importer_drew() -> void:
	var tool := load(NORMALIZE) as GDScript
	var kit := load("res://tools/scene_kit.gd") as GDScript
	var imported: String = tool.call("imported_scene_of", GIANT_GLB + ".import")
	assert_true(imported.begins_with("res://.godot/imported/giant.glb-") and imported.ends_with(".scn"),
		"the giant's imported scene is found through its .import file (%s)" % imported)
	assert_eq(str(tool.call("imported_scene_of", "res://assets/giant/giant_clips.glb.import")), "", "an import that is no scene is left alone")
	if imported == "":
		return
	var nodes := (ResourceLoader.load(imported, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene).get_state().get_node_count()
	assert_true(nodes >= 20, "the imported giant has its nodes (%d)" % nodes)
	# Two imports of one file: the same scene, other ids. Both are written at the same path, one after the
	# other, as two checkouts each hold their import at one path (a binary scene names its own path in its
	# sub-resources' references, so two paths would differ in that alone).
	var a := DIR.path_join("giant.scn")
	_scrambled_copy(imported, a, func(i: int) -> int: return 900000 - 7 * i)
	var md5_second_import := FileAccess.get_md5(a)
	assert_eq(int(tool.call("normalize", a, GIANT_GLB, kit)), nodes, "the second import is rewritten: every node")
	var second := FileAccess.get_file_as_bytes(a)
	_scrambled_copy(imported, a, func(i: int) -> int: return 1000 + i)
	assert_true(FileAccess.get_md5(a) != md5_second_import, "two imports differ (their node ids)")
	assert_eq(int(tool.call("normalize", a, GIANT_GLB, kit)), nodes, "the first is rewritten: every node")
	assert_true(FileAccess.get_file_as_bytes(a) == second, "to the same %d bytes" % second.size())
	assert_true(FileAccess.get_file_as_string(a.get_basename() + ".md5").contains("dest_md5=\"%s\"" % FileAccess.get_md5(a))
		and FileAccess.get_file_as_string(a.get_basename() + ".md5").contains("source_md5=\"0123\""),
		"the import's .md5 file names the new checksum (so the editor does not import it again) and keeps the source's")
	var ps := ResourceLoader.load(a, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
	var ids: PackedInt32Array = (ps._bundled as Dictionary).node_ids
	assert_eq(ids, tool.call("stable_ids", ps, GIANT_GLB, kit), "its ids are the stable ones")
	assert_eq(int(ids[0]), int(kit.call("stable_node_id", GIANT_GLB, str(ps.get_state().get_node_path(0)))), "the root's is the kit's for the source file and the node's path")
	var seen := {}
	for id in ids:
		seen[id] = true
	assert_eq(seen.size(), nodes, "no two nodes share one")
	assert_eq(int(tool.call("normalize", a, GIANT_GLB, kit)), 0, "a second pass rewrites nothing")
	assert_eq(int(tool.call("normalize", a, GIANT_GLB, kit, false)), 0, "and --check finds nothing to do")
	# The scene itself is what it was: the same nodes, the same meshes.
	var before := (ResourceLoader.load(imported, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene).instantiate()
	var after := ps.instantiate()
	var names_before := before.find_children("*", "MeshInstance3D", true, false).map(func(n: Node) -> String: return str(n.name))
	var names_after := after.find_children("*", "MeshInstance3D", true, false).map(func(n: Node) -> String: return str(n.name))
	assert_true(names_before.size() >= 9 and names_before == names_after, "the same meshes under the same names (%d)" % names_after.size())
	var body_before := before.find_child("Body_Torso", true, false) as MeshInstance3D
	var body_after := after.find_child("Body_Torso", true, false) as MeshInstance3D
	assert_true(var_to_bytes(body_before.mesh.surface_get_arrays(0)) == var_to_bytes(body_after.mesh.surface_get_arrays(0)), "the torso's vertices are untouched")
	before.free()
	after.free()


func test_the_build_exports_from_an_empty_conversion_cache_and_prints_the_checksum() -> void:
	var sh := FileAccess.get_file_as_string(BUILD_WEB)
	var clear_at := sh.find("rm -rf .godot/exported")
	var export_at := sh.find("--export-release \"$PRESET\"")
	assert_true(clear_at > 0 and export_at > clear_at, "build_web.sh empties .godot/exported/ before the export")
	assert_true(sh.contains("if [ \"$KEEP_CACHE\" != \"1\" ]; then") and sh.contains("--keep-export-cache) KEEP_CACHE=1 ;;"),
		"unless --keep-export-cache")
	assert_true(sh.contains("PCK_SHA256 ") and sh.contains("index.pck.sha256"), "and prints and writes the pack's SHA-256")
	var normalize_at := sh.find("-s res://tools/normalize_imports.gd")
	assert_true(normalize_at > clear_at and normalize_at < export_at, "the imported scenes get their stable ids before the export")
	assert_true(sh.find("--headless --path . --import") < normalize_at and sh.find("--headless --path . --import") > clear_at,
		"after an import of its own, so that the export imports nothing anew")
