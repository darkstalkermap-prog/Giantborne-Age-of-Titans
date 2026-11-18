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
##   * build_web.sh empties .godot/exported/ unless told to keep it, and writes the checksum.
## Two real exports of one commit in two checkouts are in docs/PERFORMANCE.md (they take minutes).

const DIR := "user://test_export_reproducible"
const SCENES := ["res://scenes/player/giant_model.tscn", "res://scenes/player/giant.tscn",
	"res://scenes/enemies/soldier.tscn", "res://scenes/main.tscn", "res://scenes/world/valley.tscn"]
const BUILD_WEB := "res://tools/build_web.sh"


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


func test_the_build_exports_from_an_empty_conversion_cache_and_prints_the_checksum() -> void:
	var sh := FileAccess.get_file_as_string(BUILD_WEB)
	var clear_at := sh.find("rm -rf .godot/exported")
	var export_at := sh.find("--export-release \"$PRESET\"")
	assert_true(clear_at > 0 and export_at > clear_at, "build_web.sh empties .godot/exported/ before the export")
	assert_true(sh.contains("if [ \"$KEEP_CACHE\" != \"1\" ]; then") and sh.contains("--keep-export-cache) KEEP_CACHE=1 ;;"),
		"unless --keep-export-cache")
	assert_true(sh.contains("PCK_SHA256 ") and sh.contains("index.pck.sha256"), "and prints and writes the pack's SHA-256")
