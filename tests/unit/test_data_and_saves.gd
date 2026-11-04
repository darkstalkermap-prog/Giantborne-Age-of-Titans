extends TestSuite
## Startup data validation and versioned save I/O with backup recovery.

const TMP_DATA := "user://test_tmp_data"
const SAVE := "user://test_tmp_saves/sample.json"


func after_each() -> void:
	_rm_tree(TMP_DATA)
	_rm_tree(SAVE.get_base_dir())
	GameData.load_all(GameData.DATA_ROOT)


func test_shipped_data_is_valid() -> void:
	GameData.load_all(GameData.DATA_ROOT)
	assert_eq(GameData.errors.size(), 0, "shipped data has no validation errors: %s" % "\n".join(GameData.errors))
	for id in ["ability.light_1", "ability.light_2", "ability.light_3", "ability.heavy_1",
			"ability.heavy_footfall", "action.dodge", "action.block", "growth.01", "enemy.soldier",
			"prop.fence_wood", "prop.practice_dummy", "player.giant", "input.default"]:
		assert_true(GameData.has_record(id), "has %s" % id)


func test_spec_values_in_data() -> void:
	var l1 := GameData.get_action("ability.light_1")
	assert_eq([l1.stamina_cost, l1.windup_ticks, l1.active_ticks, l1.recovery_ticks], [8.0, 12, 9, 18], "light timings")
	assert_eq([GameData.get_action("ability.light_2").ability_multiplier, GameData.get_action("ability.light_3").ability_multiplier], [1.1, 1.25], "combo multipliers")
	var h := GameData.get_action("ability.heavy_1")
	assert_eq([h.stamina_cost, h.windup_ticks, h.active_ticks, h.recovery_ticks, h.ability_multiplier], [22.0, 30, 12, 33, 1.8], "heavy")
	var d := GameData.get_action("action.dodge")
	assert_eq([d.stamina_cost, d.windup_ticks + d.active_ticks + d.recovery_ticks, d.iframe_start_tick, d.iframe_end_tick], [18.0, 45, 6, 18], "dodge")
	var f := GameData.get_action("ability.heavy_footfall")
	assert_eq([f.stamina_cost, f.cooldown_s, f.radius_m, f.power, f.ability_multiplier, f.poise_damage], [20.0, 8.0, 3.0, 40.0, 1.2, 25.0], "footfall")
	var g := GameData.get_record("growth.01")
	assert_eq([g.height_m, g.capsule_radius_m, g.walk_speed_mps, g.melee_reach_m, g.camera_distance_m], [3.6576, 0.85, 5.0, 3.5, 6.5], "stage 1 profile")
	for e in GameData.get_record("enemy.soldier").attacks:
		assert_true(GameData.get_action(e).windup_ticks >= 27, "%s windup >= 0.45 s" % e)


func _write(name: String, data: Dictionary) -> void:
	DirAccess.make_dir_recursive_absolute(TMP_DATA)
	var f := FileAccess.open(TMP_DATA.path_join(name), FileAccess.WRITE)
	f.store_string(JSON.stringify(data))
	f.close()


func _errors_for(files: Dictionary) -> String:
	_rm_tree(TMP_DATA)
	for name: String in files:
		_write(name, files[name])
	GameData.load_all(TMP_DATA)
	return "\n".join(GameData.errors)


func _weapon(id := "weapon.test") -> Dictionary:
	return {"schema_version": 1, "id": id, "type": "weapon", "family": "club",
		"damage_multiplier": 1.0, "length_m": 1.0, "hit_radius_m": 0.3}


func test_validator_catches_bad_data() -> void:
	assert_true(_errors_for({"a.json": _weapon(), "b.json": _weapon()}).contains("Duplicate id 'weapon.test'"), "duplicate ids")
	var neg := _weapon()
	neg["damage_multiplier"] = -1.0
	assert_true(_errors_for({"a.json": neg}).contains("must be > 0"), "negative multiplier")
	var bad_enum := _weapon()
	bad_enum["family"] = "spoon"
	assert_true(_errors_for({"a.json": bad_enum}).contains("unknown value 'spoon'"), "unknown enum")
	var typo := _weapon()
	typo["lenght_m"] = 2.0
	assert_true(_errors_for({"a.json": typo}).contains("unknown key 'lenght_m'"), "unknown key (typo)")
	var future := _weapon()
	future["schema_version"] = 99
	assert_true(_errors_for({"a.json": future}).contains("newer than supported"), "future schema version")
	var dodge := {"schema_version": 1, "id": "action.bad_dodge", "type": "action", "kind": "dodge",
		"stamina_cost": -5, "duration_s": 0.75, "move_s": 0.45, "iframe_start_s": 0.3,
		"iframe_end_s": 0.1, "distance_m": 4}
	var errs := _errors_for({"a.json": dodge})
	assert_true(errs.contains("stamina_cost: must be >= 0"), "negative cost")
	assert_true(errs.contains("iframe_start_s must be < iframe_end_s"), "invalid timing")
	var attack := {"schema_version": 1, "id": "ability.bad", "type": "action", "kind": "light",
		"power": 40, "damage_type": "physical", "ability_multiplier": 1, "stamina_cost": 8,
		"cooldown_s": 0, "windup_s": 0.2, "active_s": 0.0, "recovery_s": 0.3, "poise_damage": 1,
		"max_hits_per_target": 1, "tags": ["Melee"], "hit_shape": "weapon_arc",
		"arc": {"windup_yaw_deg": 0, "windup_pitch_deg": 0, "yaw_start_deg": 0, "yaw_end_deg": 0,
			"pitch_start_deg": 0, "pitch_end_deg": 0}, "chain_next": "ability.missing"}
	errs = _errors_for({"a.json": attack})
	assert_true(errs.contains("active_s must be > 0"), "zero active window")
	assert_true(errs.contains("missing reference 'ability.missing'"), "missing reference")
	var growth := {"schema_version": 1, "id": "growth.bad", "type": "growth_profile", "stage": 1,
		"required_level": 1, "height_m": 0.0, "capsule_radius_m": 0.85, "capsule_total_height_m": 3.66,
		"walk_speed_mps": 5, "melee_reach_m": 3.5, "camera_distance_m": 6.5, "camera_zoom_min_m": 4.5,
		"camera_zoom_max_m": 9, "camera_pivot_height_m": 3.3, "camera_shoulder_offset_m": 0.8,
		"eye_height_ratio": 0.92, "acceleration_mps2": 30, "turn_rate_deg_s": 500, "step_height_m": 0.4,
		"jump_velocity_mps": 6, "dodge_distance_m": 4, "lock_range_m": 35, "lock_half_angle_deg": 60,
		"weapon_pivot_m": [0, 1, 0], "attack_origin_m": [0, 1, 0], "arm_length_m": 1}
	assert_true(_errors_for({"a.json": growth}).contains("height_m: must be > 0"), "nonpositive height")


func test_save_roundtrip_and_backup_recovery() -> void:
	DirAccess.make_dir_recursive_absolute(SAVE.get_base_dir())
	assert_eq(SaveIO.write_json(SAVE, {"schema_version": 1, "value": 1}), OK, "first write")
	assert_eq(SaveIO.write_json(SAVE, {"schema_version": 1, "value": 2}), OK, "second write")
	var r := SaveIO.read_json(SAVE, 1)
	assert_true(r.ok and r.source == "main" and int(r.data.value) == 2, "reads newest")
	assert_false(FileAccess.file_exists(SAVE + ".tmp"), "temp file replaced")
	var f := FileAccess.open(SAVE, FileAccess.WRITE)
	f.store_string("{ this is not json")
	f.close()
	r = SaveIO.read_json(SAVE, 1)
	assert_true(r.ok, "recovers")
	assert_eq(r.source, "backup", "from the backup")
	assert_eq(int(r.data.value), 1, "previous valid copy")
	assert_true(String(r.message).contains("corrupt") and String(r.message).contains("Recovered"), "clear message: %s" % r.message)


func test_future_version_rejected_clearly() -> void:
	DirAccess.make_dir_recursive_absolute(SAVE.get_base_dir())
	var f := FileAccess.open(SAVE, FileAccess.WRITE)
	f.store_string(JSON.stringify({"schema_version": 7}))
	f.close()
	var r := SaveIO.read_json(SAVE, 1)
	assert_false(r.ok, "not loaded")
	assert_eq(int(r.future_version), 7, "future version reported")
	assert_true(String(r.message).contains("newer version"), "clear message: %s" % r.message)


func _rm_tree(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	for f in dir.get_files():
		dir.remove(f)
	for d in dir.get_directories():
		_rm_tree(path.path_join(d))
	DirAccess.remove_absolute(path)


func test_required_records_and_enum_lists() -> void:
	# Copy the shipped data, drop one record the scenes depend on, and add a typo'd immunity.
	_rm_tree(TMP_DATA)
	for path in JsonIO.list_json_files(GameData.DATA_ROOT):
		if path.ends_with("fence_wood.json"):
			continue
		var rel := path.trim_prefix(GameData.DATA_ROOT + "/").replace("/", "__")
		var parsed := JsonIO.read_file(path)
		if path.ends_with("soldier.json"):
			parsed.data["immunities"] = ["Fire"]
		_write(rel, parsed.data)
	GameData.load_all(TMP_DATA)
	var errs := "\n".join(GameData.errors)
	assert_true(errs.contains("missing reference 'prop.fence_wood'"), "a record the scenes need is reported missing")
	assert_true(errs.contains("unknown value 'Fire'"), "immunities must be known damage types or tags")
	assert_false(GameData.is_valid(), "the sandbox would refuse to start")


func test_backup_never_replaced_by_unloadable_main() -> void:
	DirAccess.make_dir_recursive_absolute(SAVE.get_base_dir())
	SaveIO.write_json(SAVE, {"schema_version": 1, "value": 1})
	SaveIO.write_json(SAVE, {"schema_version": 1, "value": 2})     # bak = 1, main = 2
	var f := FileAccess.open(SAVE, FileAccess.WRITE)
	f.store_string(JSON.stringify({"schema_version": 7}))           # a newer build wrote main
	f.close()
	SaveIO.write_json(SAVE, {"schema_version": 1, "value": 3})     # must not back up the v7 file
	var bak := SaveIO.read_json(SAVE + ".bak", 1)
	assert_true(bak.ok, "backup still loadable")
	assert_eq(int(bak.data.get("value", -1)), 1, "backup is still the last valid file")
	f = FileAccess.open(SAVE, FileAccess.WRITE)
	f.store_string("garbage")
	f.close()
	var r := SaveIO.read_json(SAVE, 1)
	assert_true(r.ok and r.source == "backup", "recovers from the preserved backup")


func test_bad_saved_binding_falls_back_to_defaults() -> void:
	var before := Settings.load_message
	Settings._merge({"bindings": {"attack_light": [{"mouse_button": "Left"}], "pause": [{"key": "Esc"}],
		"jump": [{"key": "G"}]}})
	Settings.apply_bindings()
	assert_eq(InputBindings.describe_action("attack_light", false), "Mouse Left", "invalid override ignored: default LMB kept")
	assert_eq(InputBindings.describe_action("pause", false), "Escape", "invalid override ignored: default Escape kept")
	assert_eq(InputBindings.describe_action("jump", false), "G", "valid override still applied")
	assert_true(Settings.load_message.contains("attack_light") and Settings.load_message.contains("pause"), "player is told which bindings were ignored")
	Settings.load_message = before
	Settings.reset_bindings()


func test_live_setting_changes_are_flushed() -> void:
	var fov: float = Settings.get_value("fov_deg")
	Settings.set_value("fov_deg", 81.0, false)   # live slider change, not yet written
	assert_true(Settings._unsaved, "a live change is marked unsaved")
	Settings.notification(Node.NOTIFICATION_WM_CLOSE_REQUEST)
	assert_false(Settings._unsaved, "closing the window flushes pending changes")
	Settings.set_value("fov_deg", fov, false)
	Settings.flush()
