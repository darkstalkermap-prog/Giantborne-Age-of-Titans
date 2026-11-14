extends TestSuite
## P01's untelegraphed enemy attack finding (moved here from tests/unit/test_schemas_v2.gd by P42, plan M10
## §1.7 rule 4: it writes temporary data and reloads GameData twice, 0.6-0.9 s of the default tier; the same
## rule as an error since P09 is tests/unit/test_ranged_brains.gd's
## test_an_untelegraphed_enemy_attack_is_a_data_error): a 0.85 s enemy attack without a telegraph is
## reported, an ability an enemy lists counts as an enemy attack, a 0.75 s windup needs none, and player
## abilities are not checked.

const TMP_DATA := "user://test_tmp_untelegraphed"

var _loaded_tmp := false


func after_each() -> void:
	_rm_tree(TMP_DATA)
	if _loaded_tmp:
		_loaded_tmp = false
		GameData.load_all(GameData.DATA_ROOT)


func _write(name: String, data: Dictionary) -> void:
	DirAccess.make_dir_recursive_absolute(TMP_DATA)
	var f := FileAccess.open(TMP_DATA.path_join(name), FileAccess.WRITE)
	f.store_string(JSON.stringify(data))
	f.close()


func _rm_tree(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	for f in dir.get_files():
		dir.remove(f)
	for d in dir.get_directories():
		_rm_tree(path.path_join(d))
	DirAccess.remove_absolute(path)


func test_untelegraphed_enemy_attack_warns() -> void:
	var chop: Dictionary = (GameData.get_record("ability.soldier_chop") as Dictionary).duplicate(true)
	chop.erase("telegraph")   # P04 gave the shipped chop its telegraph; the test needs one without
	var slow_chop := chop.duplicate(true)
	slow_chop["id"] = "ability.test_chop"   # enemy_attack, windup 0.85 s
	var quick := chop.duplicate(true)
	quick["id"] = "ability.test_quick"
	quick["windup_s"] = 0.75
	var cast: Dictionary = (GameData.get_record("ability.heavy_footfall") as Dictionary).duplicate(true)
	cast["id"] = "ability.test_cast"       # an ability an enemy uses
	cast["windup_s"] = 0.9
	var player_cast := cast.duplicate(true)
	player_cast["id"] = "ability.test_player_cast"   # same timing, no enemy uses it
	var enemy: Dictionary = (GameData.get_record("enemy.soldier") as Dictionary).duplicate(true)
	enemy["id"] = "enemy.test_caster"
	enemy["attacks"] = ["ability.test_cast", "ability.test_quick"]
	enemy["attack_weights"] = [0.5, 0.5]
	_rm_tree(TMP_DATA)
	_write("a.json", slow_chop)
	_write("b.json", quick)
	_write("c.json", cast)
	_write("d.json", player_cast)
	_write("e.json", enemy)
	_write("f.json", GameData.get_record("weapon.soldier_sword"))
	_write("g.json", GameData.get_record("ability.soldier_brace"))   # the soldier's hold_attack (P11b)
	_loaded_tmp = true
	GameData.load_all(TMP_DATA, false)
	# A warning until P09 turns the same finding into an error: accept it in either list.
	var findings := "\n".join(GameData.warnings) + "\n" + "\n".join(GameData.errors)
	var other_errors := Array(GameData.errors).filter(func(e: String) -> bool: return not e.contains("has no telegraph"))
	assert_eq(other_errors.size(), 0, "the test data is otherwise valid: %s" % "\n".join(other_errors))
	assert_true(findings.contains("(ability.test_chop): enemy attack (kind enemy_attack) with windup_s 0.85"),
		"an untelegraphed 0.85 s enemy attack is reported")
	assert_true(findings.contains("(ability.test_cast): enemy attack (used by enemy.test_caster)"),
		"an ability listed in an enemy's attacks counts as an enemy attack")
	assert_false(findings.contains("ability.test_quick"), "a 0.75 s windup needs no telegraph")
	assert_false(findings.contains("ability.test_player_cast"), "player abilities are not checked")
	GameData.load_all(GameData.DATA_ROOT)
	if not (GameData.get_record("ability.soldier_chop") as Dictionary).has("telegraph"):
		assert_true("\n".join(GameData.warnings).contains("(ability.soldier_chop)"),
			"the shipped 0.85 s soldier chop is reported until it has a telegraph")


# --------------------------------------------------------------------------- P01 fields
