extends TestSuite
## Every GDScript file in the project compiles - including registry entries nothing loads yet, which
## `--import` alone never parses (moved from tests/unit/test_anchors.gd by A2: it took 14-16 s of the
## default tier's 75 s budget on the 4-CPU machine; the slow tier runs in every definition-of-done check).


## Every .gd under `dir` (recursive; hidden folders and folders with a .gdignore are skipped).
static func _scripts_under(dir: String, out: PackedStringArray) -> void:
	var d := DirAccess.open(dir)
	if d == null or d.file_exists(".gdignore"):
		return
	for f in d.get_files():
		if f.ends_with(".gd"):
			out.append(dir.path_join(f))
	for sub in d.get_directories():
		if not sub.begins_with("."):
			_scripts_under(dir.path_join(sub), out)


func test_every_script_compiles() -> void:
	var paths := PackedStringArray()
	_scripts_under("res://", paths)
	assert_true(paths.size() > 80, "found the project's scripts (%d)" % paths.size())
	assert_true(paths.has("res://scripts/actors/player/player_motor.gd"), "including the components")
	for path in paths:
		var script := load(path) as GDScript
		assert_true(script != null and script.can_instantiate(), "%s compiles" % path)
