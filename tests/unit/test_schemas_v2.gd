extends TestSuite
## P01: the optional schema registry, the status_effect and progression record types, the two
## data warnings, condition checks, the new P01 fields, the new input actions, and
## GameData.override_record / restore_record / records_of_type.

const TMP_DATA := "user://test_tmp_schemas_v2"

const P01_TYPES := ["action", "growth_profile", "player", "enemy", "prop", "weapon", "item",
	"ancestry", "input_bindings", "status_effect", "progression"]
const LATER_TYPES := ["shrine", "encounter", "level", "loot_table", "npc", "dialogue", "quest",
	"tutorial_prompt"]


var _loaded_tmp := false


func after_each() -> void:
	_rm_tree(TMP_DATA)
	if _loaded_tmp:
		_loaded_tmp = false
		GameData.load_all(GameData.DATA_ROOT)


func _validate(rec: Dictionary) -> Dictionary:
	return DataValidator.validate_record(rec, "test.json")


func _errors(rec: Dictionary) -> String:
	return "\n".join(_validate(rec).errors)


func _out() -> Dictionary:
	return {"errors": PackedStringArray(), "warnings": PackedStringArray(), "refs": []}


# --------------------------------------------------------------------------- registry

func test_registry_matches_schema_modules_present() -> void:
	var present: Array = []
	var dir := DirAccess.open(DataValidator.SCHEMA_DIR)
	assert_true(dir != null, "schema folder exists")
	if dir == null:
		return
	for f in dir.get_files():
		if f.ends_with("_schema.gd"):
			present.append(f.trim_suffix("_schema.gd"))
	present.sort()
	var types: Array = DataValidator.RECORD_TYPES.duplicate()
	types.sort()
	assert_eq(types, present, "RECORD_TYPES are exactly the schema modules present")
	for t: String in DataValidator.SCHEMA_PATHS:
		assert_eq(DataValidator.SCHEMA_PATHS[t], "%s/%s_schema.gd" % [DataValidator.SCHEMA_DIR, t],
			"%s follows the <type>_schema.gd convention" % t)
	for t: String in P01_TYPES:
		assert_true(DataValidator.RECORD_TYPES.has(t), "P01 ships the %s module" % t)
	for t: String in LATER_TYPES:
		assert_true(DataValidator.SCHEMA_PATHS.has(t), "%s is pre-declared for a later package" % t)
	assert_eq(DataValidator.RECORD_TYPES, DataValidator.SCHEMAS.keys(), "RECORD_TYPES is derived from SCHEMAS")


func test_missing_schema_path_is_skipped_silently() -> void:
	var reg := DataValidator.build_registry({
		"action": DataValidator.SCHEMA_PATHS.action,
		"nope": "res://scripts/core/schemas/nope_schema.gd"})
	assert_eq(reg.keys(), ["action"], "only the module that exists is loaded (no error logged)")
	var r := _validate({"schema_version": 1, "id": "nope.thing", "type": "nope"})
	assert_true("\n".join(r.errors).contains("'type' must be one of"), "an unknown type is still an error")
	for t: String in DataValidator.SCHEMA_PATHS:
		if not DataValidator.RECORD_TYPES.has(t):
			var e := _errors({"schema_version": 1, "id": "%s.test" % t, "type": t})
			assert_true(e.contains("'type' must be one of"),
				"a %s record fails until its module ships" % t)


func test_required_records_are_merged_from_modules() -> void:
	var req: Dictionary = GameData.REQUIRED_RECORDS
	var expected := {"player.giant": "player", "enemy.soldier": "enemy", "prop.fence_wood": "prop",
		"prop.practice_dummy": "prop", "input.default": "input_bindings", "action.block": "action",
		"progression.default": "progression"}
	for id: String in expected:
		assert_eq(req.get(id, ""), expected[id], "required %s" % id)
	assert_eq(req, DataValidator.required_records(), "GameData uses the merged registry ids")
	var merged := {}
	for t: String in DataValidator.SCHEMAS:
		merged.merge(DataValidator.SCHEMAS[t].required_ids(), true)
	assert_eq(req.size(), merged.size(), "every module's required_ids() is included")


func test_new_enum_values_are_declared() -> void:
	for tag in ["TreeWeapon", "Throw", "Charge"]:
		assert_true(DataValidator.TAGS.has(tag), "TAGS has %s" % tag)
	for shape in ["sector_pulse", "projectile", "grab", "body_sweep"]:
		assert_true(DataValidator.HIT_SHAPES.has(shape), "HIT_SHAPES has %s" % shape)
	for fam in ["tree", "bow", "staff", "jaws", "natural"]:
		assert_true(DataValidator.WEAPON_FAMILIES.has(fam), "WEAPON_FAMILIES has %s" % fam)
	assert_true(DataValidator.ARCHETYPES.has("training"), "ARCHETYPES has training")
	assert_eq(DataValidator.STATUS_STACKING, ["refresh_no_stack", "strongest_wins", "independent"], "stacking")
	assert_eq(DataValidator.STATUS_MODIFIERS.size(), 7, "seven status modifiers")
	assert_eq(DataValidator.MASS_CLASSES, ["small", "medium", "large", "immovable"], "mass classes")
	assert_eq(DataValidator.GRAB_ATTACH, ["none", "torso_fist", "scruff", "two_hand"], "grab attach")
	assert_eq(DataValidator.CONDITION_TYPES.size(), 14, "condition types")
	assert_eq(DataValidator.BOT_ACTIONS.size(), 12, "bot actions")
	assert_eq(DataValidator.TUTORIAL_EVENTS.size(), 12, "tutorial events")
	for list: Array in [DataValidator.STATUS_TAGS, DataValidator.PROJECTILE_VISUALS, DataValidator.AIM_MODES,
			DataValidator.TELEGRAPH_SHAPES, DataValidator.OUTMATCHED_BEHAVIORS, DataValidator.NPC_ROLES,
			DataValidator.ITEM_CATEGORIES, DataValidator.DODGE_STYLES, DataValidator.TUTORIAL_TRIGGERS,
			DataValidator.TUTORIAL_DISMISS]:
		assert_true(list.size() >= 2, "enum list declared: %s" % [list])


# --------------------------------------------------------------------------- status_effect

func _slow() -> Dictionary:
	return {"schema_version": 1, "id": "status.slow", "type": "status_effect", "display_name": "Slowed",
		"hud_label": "SLOW", "stacking": "strongest_wins", "duration_s": 3.0, "tick_s": 0,
		"magnitude_key": "slow_fraction", "default_magnitude": 0.3, "modifiers": {"slow_fraction": 0.3},
		"tags": ["Debuff", "Slow"], "hidden": false}


func test_status_effect_valid_example() -> void:
	var r := _validate(_slow())
	assert_eq(r.errors.size(), 0, "the plan's example validates: %s" % "\n".join(r.errors))
	assert_eq(r.warnings.size(), 0, "and has no warnings")
	var mend := {"schema_version": 1, "id": "status.mend", "type": "status_effect", "stacking": "refresh_no_stack",
		"duration_s": 4.0, "tick_s": 0.5, "modifiers": {"heal_per_tick": 12.5}, "tags": ["Buff", "Heal"]}
	assert_eq(_validate(mend).errors.size(), 0, "a heal over time with tick_s validates")


func test_status_effect_invalid_examples() -> void:
	var rec := _slow()
	rec["speed"] = 2
	assert_true(_errors(rec).contains("unknown key 'speed'"), "unknown key")
	rec = _slow()
	rec["stacking"] = "stacky"
	assert_true(_errors(rec).contains("unknown value 'stacky'"), "bad stacking enum")
	rec = _slow()
	rec["tags"] = ["Debuff", "Stunned"]
	assert_true(_errors(rec).contains("unknown value 'Stunned'"), "bad status tag")
	rec = _slow()
	rec["modifiers"] = {"slow_fraction": 0.3, "move_speed": 0.5}
	assert_true(_errors(rec).contains("unknown key 'move_speed'"), "modifier keys are a closed list")
	rec = _slow()
	rec.erase("duration_s")
	assert_true(_errors(rec).contains("missing required key 'duration_s'"), "duration is required")
	# status_effect records have no reference fields, so there is no bad-ref case for them.
	rec = _slow()
	rec["modifiers"] = {"armor_flat": 5}
	assert_true(_errors(rec).contains("magnitude_key 'slow_fraction' must also be listed in modifiers"),
		"semantic: magnitude_key must be one of the modifiers")
	rec = _slow()
	rec["magnitude_key"] = "speed"
	assert_true(_errors(rec).contains("magnitude_key: unknown value 'speed'"), "semantic: magnitude_key is a modifier key")
	rec = _slow()
	rec["modifiers"] = {"slow_fraction": 0.3, "heal_per_tick": 5}
	assert_true(_errors(rec).contains("'heal_per_tick' needs tick_s > 0"), "semantic: heal_per_tick needs tick_s")
	rec = _slow()
	rec["duration_s"] = 0.333
	var r := _validate(rec)
	assert_eq(r.errors.size(), 0, "an odd duration is not an error")
	assert_true("\n".join(r.warnings).contains("not a whole number of 1/60 s ticks"), "semantic: tick-multiple warning")


# --------------------------------------------------------------------------- progression

func _progression() -> Dictionary:
	return (GameData.get_record("progression.default") as Dictionary).duplicate(true)


func test_progression_valid_example() -> void:
	assert_true(GameData.has_record("progression.default"), "progression.default ships")
	var r := _validate(_progression())
	assert_eq(r.errors.size(), 0, "the shipped record validates: %s" % "\n".join(r.errors))
	assert_eq(DataValidator.validate_references(GameData.records, r.refs).size(), 0, "its references resolve")
	var p := _progression()
	assert_eq((p.xp_to_next as Array).size(), 19, "19 level steps")
	assert_eq(int(p.xp_to_next[0]), 100, "L1 -> L2 costs 100")
	assert_eq(int(p.xp_to_next[18]), 1000, "L19 -> L20 costs 1000")
	for i in 19:
		assert_eq(int(p.xp_to_next[i]), CombatRules.xp_to_next_level(i + 1), "matches CombatRules at L%d" % (i + 1))
	assert_eq(p.ability_library, ["ability.heavy_footfall"], "only abilities that exist today")
	assert_eq(p.new_game.known_abilities, ["ability.heavy_footfall"], "new game knows Footfall")


func test_progression_invalid_examples() -> void:
	var rec := _progression()
	rec["xp_bonus"] = 2
	assert_true(_errors(rec).contains("unknown key 'xp_bonus'"), "unknown key")
	rec = _progression()
	rec["new_game"]["ghost"] = true
	assert_true(_errors(rec).contains("unknown key 'ghost'"), "unknown key inside new_game")
	# progression has no string enums; an out-of-range value is its closest equivalent.
	rec = _progression()
	rec["level_cap"] = 25
	assert_true(_errors(rec).contains("level_cap: must be <= 20"), "out of range")
	rec = _progression()
	rec["new_game"]["weapon"] = "weapon.missing"
	rec["ability_library"] = ["ability.heavy_footfall", "ability.missing"]
	var r := _validate(rec)
	var ref_errors := "\n".join(DataValidator.validate_references(GameData.records, r.refs))
	assert_true(ref_errors.contains("missing reference 'weapon.missing'"), "bad weapon reference")
	assert_true(ref_errors.contains("missing reference 'ability.missing'"), "bad ability reference")
	rec = _progression()
	(rec.xp_to_next as Array).pop_back()
	assert_true(_errors(rec).contains("xp_to_next must have level_cap - 1 = 19 entries (got 18)"), "semantic: 19 entries")
	rec = _progression()
	rec["xp_to_next"][5] = 10
	assert_true(_errors(rec).contains("xp_to_next must be non-decreasing"), "semantic: non-decreasing")
	rec = _progression()
	rec["xp_to_next"][3] = 250.5
	assert_true(_errors(rec).contains("expected an integer"), "xp values are integers")
	rec = _progression()
	(rec.new_game.slots as Array).pop_back()
	assert_true(_errors(rec).contains("new_game.slots must have exactly 8 entries"), "semantic: 8 slots")


# --------------------------------------------------------------------------- warnings

func test_light_without_basic_attack_warns() -> void:
	var rec: Dictionary = (GameData.get_record("ability.light_1") as Dictionary).duplicate(true)
	var r := _validate(rec)
	assert_false("\n".join(r.warnings).contains("BasicAttack"), "a tagged light attack does not warn")
	rec["tags"] = ["Melee", "Parryable", "Light"]
	r = _validate(rec)
	assert_eq(r.errors.size(), 0, "missing BasicAttack is not an error")
	assert_true("\n".join(r.warnings).contains("without the 'BasicAttack' tag"), "but it warns")


func test_untelegraphed_enemy_attack_warns() -> void:
	var chop: Dictionary = (GameData.get_record("ability.soldier_chop") as Dictionary).duplicate(true)
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
	_loaded_tmp = true
	GameData.load_all(TMP_DATA, false)
	var w := "\n".join(GameData.warnings)
	assert_eq(GameData.errors.size(), 0, "the test data is valid: %s" % "\n".join(GameData.errors))
	assert_true(w.contains("(ability.test_chop): enemy attack") and w.contains("has no telegraph"),
		"an untelegraphed 0.85 s enemy attack warns")
	assert_true(w.contains("(ability.test_cast): enemy attack (used by enemy.test_caster)"),
		"an ability listed in an enemy's attacks counts as an enemy attack")
	assert_false(w.contains("ability.test_quick"), "a 0.75 s windup needs no telegraph")
	assert_false(w.contains("ability.test_player_cast"), "player abilities are not checked")
	GameData.load_all(GameData.DATA_ROOT)
	assert_true("\n".join(GameData.warnings).contains("(ability.soldier_chop)"),
		"the shipped 0.85 s soldier chop warns until telegraphs exist (P04/P09)")


# --------------------------------------------------------------------------- P01 fields

func test_new_p01_fields() -> void:
	var light: Dictionary = (GameData.get_record("ability.light_1") as Dictionary).duplicate(true)
	light["unlock_level"] = 3
	assert_eq(_validate(light).errors.size(), 0, "unlock_level 3 is valid")
	assert_eq(ActionDef.from_dict(light).unlock_level, 3, "ActionDef reads unlock_level")
	assert_eq(ActionDef.from_dict(GameData.get_record("ability.light_2")).unlock_level, 1, "unlock_level defaults to 1")
	light["unlock_level"] = 0
	assert_true(_errors(light).contains("unlock_level: must be >= 1"), "unlock_level >= 1")
	light["unlock_level"] = 21
	assert_true(_errors(light).contains("unlock_level: must be <= 20"), "unlock_level <= 20")
	var enemy: Dictionary = (GameData.get_record("enemy.soldier") as Dictionary).duplicate(true)
	enemy["xp_reward"] = 15
	enemy["poise"]["recovery_mult"] = 3.5
	enemy["poise"]["stagger_vs_larger_s"] = 1.5
	assert_eq(_validate(enemy).errors.size(), 0, "xp_reward and the new poise fields validate")
	enemy["xp_reward"] = -1
	enemy["poise"]["recovery_mult"] = 0.5
	enemy["poise"]["stagger_vs_larger_s"] = 0.0
	var e := _errors(enemy)
	assert_true(e.contains("xp_reward: must be >= 0"), "xp_reward >= 0")
	assert_true(e.contains("recovery_mult: must be >= 1"), "recovery_mult >= 1")
	assert_true(e.contains("stagger_vs_larger_s: must be > 0"), "stagger_vs_larger_s > 0")
	var player: Dictionary = (GameData.get_record("player.giant") as Dictionary).duplicate(true)
	player["poise"]["recovery_mult"] = 2.0
	assert_eq(_validate(player).errors.size(), 0, "the shared poise block applies to the player too")


func test_condition_checks() -> void:
	var out := _out()
	SchemaUtil.check_conditions([
		{"type": "flag", "flag": "quest.main.stage", "equals": "grove"},
		{"type": "flag", "flag": "quest.main.done"},
		{"type": "entered", "area": "valley.area.arena_engage"},
		{"type": "killed", "targets": ["valley.forest.ogre"]},
		{"type": "has_item", "item": "item.wood_scrap", "count": 1},
		{"type": "hits_on", "targets": ["valley.hollow.dummy_1"], "count": 3, "action_kind": "light"},
		{"type": "all", "of": [{"type": "stage_at_least", "stage": 2}, {"type": "level_at_least", "level": 3},
			{"type": "not", "of": {"type": "flag", "flag": "faction.village.hostile"}}]},
		{"type": "any", "of": [{"type": "destroyed", "world_id": "valley.ruins.practice_gate"},
			{"type": "weapon_equipped", "weapon": "weapon.club"}]},
	], "cond", out)
	assert_eq(out.errors.size(), 0, "valid conditions: %s" % "\n".join(out.errors))
	var ref_ids: Array = []
	for r: Dictionary in out.refs:
		ref_ids.append(r.id)
	assert_true(ref_ids.has("item.wood_scrap") and ref_ids.has("weapon.club"), "item and weapon are references")
	assert_eq(DataValidator.validate_references(GameData.records, out.refs).size(), 0, "and they resolve")
	var cases := [
		[{"type": "teleport"}, "unknown value 'teleport'"],
		[{"type": "flag", "flag": "Bad Flag"}, "flag id 'Bad Flag' must be lowercase dotted form"],
		[{"type": "has_item", "item": "item.wood_scrap"}, "missing required key 'count'"],
		[{"type": "killed", "targets": []}, "must list at least one id"],
		[{"type": "entered", "area": "valley.area.x", "extra": 1}, "unknown key 'extra'"],
		[{"type": "any", "of": [{"type": "flag"}]}, "cond[0].of[0]: missing required key 'flag'"],
		[{"type": "not", "of": {"type": "stage_at_least", "stage": 0}}, "stage: must be >= 1"],
		[{"type": "hits_on", "targets": ["a.b"], "count": 1, "action_kind": "kick"}, "unknown value 'kick'"],
	]
	for c: Array in cases:
		out = _out()
		SchemaUtil.check_conditions([c[0]], "cond", out)
		assert_true("\n".join(out.errors).contains(c[1]), "invalid condition reports '%s' (got %s)" % [c[1], out.errors])
	out = _out()
	assert_true(SchemaUtil.check_flag_id("tutorial.camera.done", "f", out), "dotted flag ids pass")
	assert_false(SchemaUtil.check_flag_id("tutorial", "f", out), "an undotted flag id fails")


# --------------------------------------------------------------------------- input actions

func test_new_input_actions_have_bindings_and_labels() -> void:
	for a in ["inventory", "debug_grow", "debug_shrink", "debug_xp", "debug_checkpoint", "interact"]:
		assert_true(InputBindings.ACTIONS.has(a), "%s is an input action" % a)
		assert_true(InputBindings.LABELS.has(a), "%s has a rebinding label" % a)
	assert_eq(InputBindings.describe_action("inventory", false), "I", "inventory on I")
	assert_eq(InputBindings.describe_action("inventory", true), "Pad Back", "inventory on pad Back")
	assert_eq(InputBindings.describe_action("debug_grow", false), "F6", "debug grow on F6")
	assert_eq(InputBindings.describe_action("debug_shrink", false), "F7", "debug shrink on F7")
	assert_eq(InputBindings.describe_action("debug_xp", false), "F8", "debug XP on F8")
	assert_eq(InputBindings.describe_action("debug_checkpoint", false), "F9", "debug checkpoint on F9")
	assert_eq(InputBindings.describe_action("interact", false), "E", "interact stays on E")


func _key(code: Key, pressed: bool) -> void:
	var e := InputEventKey.new()
	e.physical_keycode = code
	e.keycode = code
	e.pressed = pressed
	Input.parse_input_event(e)


func test_router_emits_debug_edges_only() -> void:
	InputRouter.set_context(InputRouter.Context.GAMEPLAY)
	var router := InputRouter.new()
	add_child(router)
	await get_tree().process_frame
	router.consume()
	var cases := [[KEY_F6, [&"debug_grow"]], [KEY_F7, [&"debug_shrink"]], [KEY_F8, [&"debug_xp"]],
		[KEY_F9, []], [KEY_I, []]]
	for c: Array in cases:
		_key(c[0], true)
		await get_tree().process_frame
		var expected: Array = c[1] if OS.is_debug_build() else []
		assert_eq(router.consume().edges, expected, "key %s -> edges %s" % [OS.get_keycode_string(c[0]), c[1]])
		_key(c[0], false)
		await get_tree().process_frame
		assert_eq(router.consume().edges, [] as Array, "release produces no edge")
	router.queue_free()
	await get_tree().process_frame


# --------------------------------------------------------------------------- GameData

func test_override_record_refreshes_cached_action_in_place() -> void:
	var a := GameData.get_action("ability.light_1")
	var prev := GameData.override_record("ability.light_1",
		{"power": 99, "movement": {"windup_speed_mult": 0.9}, "tags": ["Melee", "Light"]})
	assert_true(GameData.get_action("ability.light_1") == a, "the cached ActionDef object is kept")
	assert_near(a.power, 99.0, 1e-9, "and refreshed")
	assert_near(a.move_mult(ActionDef.Phase.WINDUP), 0.9, 1e-9, "nested dictionaries merge")
	assert_near(a.move_mult(ActionDef.Phase.ACTIVE), 0.15, 1e-9, "untouched nested keys survive")
	assert_false(a.has_tag("BasicAttack"), "arrays are replaced")
	assert_near(float(GameData.get_record("ability.light_1").power), 99.0, 1e-9, "the record changed")
	assert_near(float(prev.power), 40.0, 1e-9, "the previous record is returned")
	GameData.restore_record("ability.light_1", prev)
	assert_true(GameData.get_action("ability.light_1") == a, "restore keeps the object")
	assert_near(a.power, 40.0, 1e-9, "power restored")
	assert_near(a.move_mult(ActionDef.Phase.WINDUP), 0.3, 1e-9, "movement restored")
	assert_true(a.has_tag("BasicAttack"), "tags restored")
	assert_eq(GameData.get_record("ability.light_1"), prev, "the record is back")


func test_override_record_creates_and_restore_removes() -> void:
	assert_false(GameData.has_record("status.test_tmp"), "no such record yet")
	var prev := GameData.override_record("status.test_tmp", {"schema_version": 1, "type": "status_effect",
		"stacking": "refresh_no_stack", "duration_s": 2.0, "modifiers": {"armor_flat": 10}})
	assert_eq(prev, {}, "nothing existed before")
	var s := GameData.get_status("status.test_tmp")
	assert_true(s != null and s.duration_ticks == 120, "a created status record gets a StatusDef")
	if s != null:
		assert_eq(s.id, "status.test_tmp", "the id is filled in")
	GameData.restore_record("status.test_tmp", prev)
	assert_false(GameData.has_record("status.test_tmp"), "restoring {} removes the record")
	assert_true(GameData.get_status("status.test_tmp") == null, "and its StatusDef")


func test_records_of_type_sorted_by_id() -> void:
	var recs := GameData.records_of_type("action")
	var ids := GameData.ids_of_type("action")
	assert_eq(recs.size(), ids.size(), "one record per id")
	for i in recs.size():
		assert_eq(str(recs[i].id), ids[i], "sorted by id (%d)" % i)
	assert_eq(GameData.records_of_type("no_such_type"), [], "unknown type -> empty")


# --------------------------------------------------------------------------- files

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
