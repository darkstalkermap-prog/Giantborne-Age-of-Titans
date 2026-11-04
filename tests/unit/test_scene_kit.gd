extends TestSuite
## SceneKit and the builder runner (plan §2.12, §3.4): the layer constants, --only selection,
## builders writing into a redirected folder, no node unique_id attributes in any generated
## scene, and byte-identical regeneration.

const BUILD_SCENES := "res://tools/build_scenes.gd"
const OUT := "user://test_scene_kit"


func _runner() -> GDScript:
	return load(BUILD_SCENES) as GDScript


func _read(path: String) -> String:
	var f := FileAccess.open(path, FileAccess.READ)
	return f.get_as_text() if f != null else ""


func _rm_tree(path: String) -> void:
	var d := DirAccess.open(path)
	if d == null:
		return
	for sub in d.get_directories():
		_rm_tree(path.path_join(sub))
	for f in d.get_files():
		d.remove(f)
	DirAccess.remove_absolute(path)


func after_each() -> void:
	_rm_tree(OUT)


func test_layer_constants() -> void:
	assert_eq(SceneKit.L_WORLD, 1, "world")
	assert_eq(SceneKit.L_ACTORS, 2, "actors")
	assert_eq(SceneKit.L_HURTBOX, 4, "hurtboxes")
	assert_eq(SceneKit.L_DEBRIS, 8, "debris")
	assert_eq(SceneKit.L_BREAKABLE, 16, "breakables")
	assert_eq(SceneKit.L_BLOCKER, 32, "blockers (physics layer 6)")
	assert_eq(SceneKit.ACTOR_MASK, 51, "ACTOR_MASK = world | actors | breakables | blockers")
	assert_eq(SceneKit.FP_HIDDEN, 2, "first-person hidden render layer")
	assert_eq(SceneKit.L_BLOCKER, EnemyActor.LAYER_BLOCKER, "the enemy code agrees on the blocker layer")
	assert_eq(HitQueryAdapter.OCCLUDER_MASK & SceneKit.L_BLOCKER, 0, "attack occluders ignore blockers")
	assert_eq(EnemyActor.SIGHT_MASK, SceneKit.L_WORLD | SceneKit.L_BREAKABLE, "enemy sight: world and breakables")


func test_only_selection() -> void:
	var r := _runner()
	var builders: Array = r.get("BUILDERS")
	assert_eq(r.call("parse_only", PackedStringArray(["--only=wolf"])), PackedStringArray(["wolf"]), "one name")
	assert_eq(r.call("parse_only", PackedStringArray(["--slow", "--only=wolf, sandbox,wolf.gd"])),
		PackedStringArray(["wolf", "sandbox"]), "a list; spaces, .gd and repeats are tolerated")
	assert_eq(r.call("parse_only", PackedStringArray([])), PackedStringArray(), "absent")
	var all: Dictionary = r.call("select", builders, PackedStringArray())
	assert_true(all.ok and (all.paths as Array).size() == builders.size(), "no --only: every builder")
	var one: Dictionary = r.call("select", builders, PackedStringArray(["wolf"]))
	assert_eq(one.paths, ["res://tools/builders/wolf.gd"], "--only=wolf runs the wolf builder only")
	var two: Dictionary = r.call("select", builders, PackedStringArray(["main", "player"]))
	assert_eq(two.paths, ["res://tools/builders/player.gd", "res://tools/builders/main.gd"],
		"selected builders keep the BUILDERS order")
	var bad: Dictionary = r.call("select", builders, PackedStringArray(["wolf", "nope"]))
	assert_false(bad.ok, "an unknown builder is an error")
	assert_true(str(bad.error).contains("nope"), "naming it")


func test_builders_list_covers_every_builder_file() -> void:
	var builders: Array = _runner().get("BUILDERS")
	var names := PackedStringArray()
	for path: String in builders:
		names.append(_runner().call("builder_name", path))
	for expected in ["player", "soldier", "wolf", "props", "shrine", "growth_course", "test_levels",
			"world_props", "ranged", "test_director", "forge", "heavy", "npcs", "sandbox", "valley",
			"stress", "main"]:
		assert_true(names.has(expected), "BUILDERS declares %s" % expected)
	assert_true(names.find("player") < names.find("sandbox") and names.find("wolf") < names.find("sandbox")
		and names.find("props") < names.find("sandbox") and names.find("sandbox") < names.find("main"),
		"builders run before the scenes that instance their output")
	var d := DirAccess.open("res://tools/builders")
	for f in d.get_files():
		if f.ends_with(".gd"):
			assert_true(builders.has("res://tools/builders/" + f), "%s is in BUILDERS" % f)


func test_strip_unique_ids() -> void:
	var kit := SceneKit.new(OUT)
	var text := "[node name=\"A\" type=\"Node3D\" unique_id=1234567]\n[node name=\"B\" type=\"Node3D\" parent=\".\" unique_id=-42]\n"
	assert_eq(kit.strip_unique_ids(text), "[node name=\"A\" type=\"Node3D\"]\n[node name=\"B\" type=\"Node3D\" parent=\".\"]\n",
		"every node unique_id attribute is removed")


func test_wolf_builder_output_is_clean_and_deterministic() -> void:
	var kit := SceneKit.new(OUT)
	var result: Dictionary = _runner().call("run", kit, ["res://tools/builders/wolf.gd"])
	assert_true(result.ok and int(result.ran) == 1, "the wolf builder ran")
	var path := OUT.path_join("scenes/enemies/wolf.tscn")
	assert_eq(kit.saved, PackedStringArray([path]), "it wrote one scene, under the redirected folder")
	var first := _read(path)
	assert_true(first.length() > 1000, "the scene was written")
	assert_false(first.contains("unique_id="), "no node unique_id attributes")
	assert_true(first.contains("[node name=\"LodProxy\" type=\"MeshInstance3D\" parent=\"Visual\"]"), "Visual/LodProxy")
	assert_true(first.contains("collision_mask = 51"), "the wolf body uses ACTOR_MASK")
	var wolf := (load(path) as PackedScene).instantiate()
	for node_path in ["CombatEntity", "NavAgent", "BodyShape", "Visual/Body", "Visual/LodProxy",
			"Anchors/Torso", "Hurtboxes/Head", "Hurtboxes/Body", "Hurtboxes/Legs", "Visual/Body/Head",
			"Visual/Body/Tail", "Visual/Body/LegFL", "Visual/Body/LegBR"]:
		assert_true(wolf.has_node(node_path), "the wolf has %s" % node_path)
	assert_false((wolf.get_node("Visual/LodProxy") as Node3D).visible, "the proxy starts hidden")
	wolf.free()
	var kit2 := SceneKit.new(OUT)
	_runner().call("run", kit2, ["res://tools/builders/wolf.gd"])
	assert_eq(_read(path), first, "regenerating gives a byte-identical file")


func test_committed_scenes_have_no_unique_ids() -> void:
	for path in ["res://scenes/player/giant.tscn", "res://scenes/enemies/soldier.tscn",
			"res://scenes/enemies/wolf.tscn", "res://scenes/world/practice_dummy.tscn",
			"res://scenes/world/fence_wood.tscn", "res://scenes/world/sandbox_arena.tscn",
			"res://scenes/main.tscn"]:
		var text := _read(path)
		assert_true(text.length() > 0, "%s exists" % path)
		assert_false(text.contains("unique_id="), "%s has no unique_id attributes" % path)
	var soldier := _read("res://scenes/enemies/soldier.tscn")
	assert_true(soldier.contains("[node name=\"LodProxy\" type=\"MeshInstance3D\" parent=\"Visual\"]"),
		"the soldier gained Visual/LodProxy")
	for path in ["res://scenes/player/giant.tscn", "res://scenes/enemies/soldier.tscn",
			"res://scenes/enemies/wolf.tscn"]:
		var root := (load(path) as PackedScene).instantiate() as CollisionObject3D
		assert_eq(root.collision_mask, SceneKit.ACTOR_MASK, "%s collides with the blockers layer" % path)
		root.free()
