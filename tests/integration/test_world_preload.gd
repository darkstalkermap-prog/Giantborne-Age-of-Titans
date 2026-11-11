extends TestSuite
## M8 gate (F26; plan M6-M9 §5.2: streaming work at most 4 ms a frame, its steps under about 3 ms):
## the world's runtime scripts and the shared scenes its chunks' props sub-scenes use load with the
## level, behind the loading screen - level.world's `preload` list, which WorldRoot.warm_preload()
## loads at _ready and keeps - so no TerrainChunk "props_dep" step loads one during play. Before, the
## first visit to a chunk loaded each in a step of its own: fort_battle.gd 19-27 ms, stone_throne.gd and
## forge_fire.gd 12-14 ms, beacon_fire.gd 8-10 ms, the rockfall's and the toppled statue's scenes 7-12 ms
## (headless desktop; 41.7 ms on the web build, which has no loader thread).
## Files and records only (the default tier): the list names exactly the res:// dependencies of every
## chunk's props sub-scenes - a new kind's script or shared scene must join it - each once, each one
## that exists. tests/slow/test_world_preload.gd streams the world with it.

const LEVEL := "level.world"
const CHUNK_DIR := "res://assets/world/chunks"


## Every res:// dependency of the props sub-scenes of the world's chunks (the paths TerrainChunk.
## missing_dependencies() can return) -> the number of sub-scenes that use it.
static func props_dependencies() -> Dictionary:
	var out := {}
	var rec := GameData.get_record(LEVEL)
	var grid: Array = (rec.get("world", {}) as Dictionary).get("grid", [8, 8])
	for x in int(grid[0]):
		for z in int(grid[1]):
			var path := CHUNK_DIR.path_join("c%d_%d.res" % [x, z])
			if not ResourceLoader.exists(path):
				continue
			var data := load(path) as ChunkData
			if data == null:
				continue
			for scene in data.props_scenes:
				for d in ResourceLoader.get_dependencies(scene):
					var dep := d.get_slice("::", d.get_slice_count("::") - 1) if d.contains("::") else d
					if dep.begins_with("res://"):
						out[dep] = int(out.get(dep, 0)) + 1
	return out


func test_the_preload_list_names_every_dependency_of_the_chunks_props() -> void:
	var rec := GameData.get_record(LEVEL)
	assert_true(rec.has("preload"), "level.world has a preload list")
	var listed: Array = rec.get("preload", [])
	var deps := props_dependencies()
	assert_true(deps.size() >= 40, "the chunks' props sub-scenes use many shared resources (%d)" % deps.size())
	var missing: Array = []
	for dep: String in deps:
		if not listed.has(dep):
			missing.append(dep)
	missing.sort()
	var unused: Array = []
	for p: Variant in listed:
		if not deps.has(str(p)):
			unused.append(str(p))
	assert_eq(missing, [], "every dependency of a chunk's props is preloaded (add these to data/world/level_world.json's preload)")
	assert_eq(unused, [], "every preloaded path is used by a chunk's props (remove these from the list)")
	var seen := {}
	for p: Variant in listed:
		assert_false(seen.has(p), "%s is listed once" % p)
		seen[p] = true
		assert_true(ResourceLoader.exists(str(p)), "%s exists" % p)
	# The heaviest first-time loads the review measured are among them.
	for p: String in ["res://scripts/world/fort_battle.gd", "res://scripts/world/stone_throne.gd",
			"res://scripts/world/forge_fire.gd", "res://scripts/world/condition_forge.gd",
			"res://scripts/world/beacon_fire.gd", "res://scenes/world/toppled_statue.tscn",
			"res://scenes/world/rockfall.tscn", "res://scenes/world/siege_catapult.tscn"]:
		assert_true(listed.has(p), "%s is preloaded" % p.get_file())


func test_the_validator_checks_the_preload_list() -> void:
	var rec := (GameData.get_record(LEVEL) as Dictionary).duplicate(true)
	assert_eq(DataValidator.validate_record(rec, "level_world.json").errors, PackedStringArray(),
		"level.world validates with its preload list")
	rec["preload"] = ["res://scripts/world/fort_battle.gd", "scripts/world/stone_throne.gd",
		"res://scripts/world/no_such_script.gd", "res://scripts/world/fort_battle.gd", 7]
	var errors: PackedStringArray = DataValidator.validate_record(rec, "level_world.json").errors
	var text := "\n".join(errors)
	assert_true(text.contains("preload[1]: 'scripts/world/stone_throne.gd' must be a res:// path"), "a res:// path: %s" % text)
	assert_true(text.contains("preload[2]: 'res://scripts/world/no_such_script.gd' does not exist"), "that exists: %s" % text)
	assert_true(text.contains("preload[3]: 'res://scripts/world/fort_battle.gd' is listed twice"), "listed once: %s" % text)
	assert_true(text.contains("preload[4]: expected a string"), "a path is a string: %s" % text)
	assert_eq(errors.size(), 4, "and nothing else: %s" % text)
