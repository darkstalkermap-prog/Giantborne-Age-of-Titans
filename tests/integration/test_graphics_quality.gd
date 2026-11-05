extends IntegrationSuite
## Graphics presets (P14, plan §3.16, §5.4): LevelRoot applies its level record's `render` preset
## for the quality in effect - the Sun's shadow distance, visibility_range_end on the scenery
## below it (groups "scenery" and "valley_scenery") and the viewport's MSAA - at _ready and again
## when the setting changes; the --graphics flag fixes the quality for a run; the web build (here
## LevelRoot.force_web_for_tests) runs the record's web_overrides: low and AI tier 1 from 30 m.

## A test level whose record carries both presets and web overrides (P10a's director test level:
## low 60 / 160 / no MSAA, medium 120 / 220 / 2x, web low with tier 1 from 30 m).
const LEVEL_ID := "level.director_test"

var _saved_quality: Variant
var _saved_override := ""
var _msaa_before := 0


func before_each() -> void:
	await super()
	_saved_quality = Settings.values.get("graphics_quality", Settings.GRAPHICS_DEFAULT)
	_saved_override = Settings.graphics_override
	Settings.graphics_override = ""
	_msaa_before = get_viewport().msaa_3d
	LevelRoot.force_web_for_tests = false


func after_each() -> void:
	LevelRoot.force_web_for_tests = false
	Settings.values["graphics_quality"] = _saved_quality
	Settings.graphics_override = _saved_override
	get_viewport().msaa_3d = _msaa_before as Viewport.MSAA
	await super()


## A small LevelRoot for `level_id`: a Sun (shadows to 90 m), one tree MeshInstance3D in group
## "scenery", one MultiMeshInstance3D in "valley_scenery", optionally an EncounterDirector.
func _level(level_id := LEVEL_ID, with_director := true) -> LevelRoot:
	var lv := LevelRoot.new()
	lv.name = "GraphicsTestLevel"
	lv.level_id = level_id
	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 90.0
	lv.add_child(sun)
	var tree := MeshInstance3D.new()
	tree.name = "Tree"
	tree.mesh = BoxMesh.new()
	tree.visibility_range_end = 999.0
	tree.add_to_group("scenery", true)
	lv.add_child(tree)
	var forest := MultiMeshInstance3D.new()
	forest.name = "Forest"
	forest.visibility_range_end = 999.0
	forest.add_to_group("valley_scenery", true)
	lv.add_child(forest)
	if with_director:
		var d := EncounterDirector.new()
		d.name = "EncounterDirector"
		lv.add_child(d)
	world.add_child(lv)
	return lv


## A preset with every value as a float, keys sorted (JSON numbers load as floats).
static func _numbers(d: Variant) -> Dictionary:
	var out := {}
	if typeof(d) != TYPE_DICTIONARY:
		return out
	var keys: Array = (d as Dictionary).keys()
	keys.sort()
	for k: Variant in keys:
		out[k] = float(d[k])
	return out


func _sun(lv: LevelRoot) -> DirectionalLight3D:
	return lv.get_node("Sun") as DirectionalLight3D


func _tree(lv: LevelRoot) -> GeometryInstance3D:
	return lv.get_node("Tree") as GeometryInstance3D


func _forest(lv: LevelRoot) -> GeometryInstance3D:
	return lv.get_node("Forest") as GeometryInstance3D


func test_presets_follow_the_setting() -> void:
	Settings.values["graphics_quality"] = "medium"
	var outside := MeshInstance3D.new()
	outside.visibility_range_end = 999.0
	outside.add_to_group("scenery", true)
	world.add_child(outside)   # scenery of another level: never touched
	var lv := _level()
	await step_ticks(1)
	assert_eq(lv.graphics_quality(), "medium", "the saved setting decides on desktop")
	assert_near(_sun(lv).directional_shadow_max_distance, 120.0, 0.001, "medium: shadows to 120 m")
	assert_near(_tree(lv).visibility_range_end, 220.0, 0.001, "medium: scenery to 220 m")
	assert_near(_forest(lv).visibility_range_end, 220.0, 0.001, "also the Valley builder's scenery group")
	assert_near(outside.visibility_range_end, 999.0, 0.001, "scenery outside the level is left alone")
	assert_eq(int(get_viewport().msaa_3d), int(Viewport.MSAA_2X), "medium: 2x MSAA")
	assert_eq(int(lv.applied_graphics.get("scenery_nodes", 0)), 2, "two scenery nodes")
	# A live change (the settings page) re-applies at once.
	Settings.set_value("graphics_quality", "low", false)
	assert_eq(str(lv.applied_graphics.get("quality", "")), "low", "re-applied on the change")
	assert_near(_sun(lv).directional_shadow_max_distance, 60.0, 0.001, "low: shadows to 60 m")
	assert_near(_tree(lv).visibility_range_end, 160.0, 0.001, "low: scenery to 160 m")
	assert_near(_forest(lv).visibility_range_end, 160.0, 0.001, "low: the Valley scenery group too")
	assert_eq(int(get_viewport().msaa_3d), int(Viewport.MSAA_DISABLED), "low: no MSAA")
	assert_eq(int(lv.applied_graphics.get("msaa", -1)), 0, "applied msaa reported")
	assert_false(lv.applied_graphics.has("ai_tier1_m"), "desktop: the AI LOD distances stay the record's")
	assert_near(lv.director().near_m, 40.0, 0.001, "desktop: AI tier 1 from 40 m")
	Settings.set_value("graphics_quality", "medium", false)
	assert_near(_sun(lv).directional_shadow_max_distance, 120.0, 0.001, "and back to medium")
	# Another setting does not re-apply (the scenery keeps a value set meanwhile).
	_tree(lv).visibility_range_end = 50.0
	Settings.set_value("camera_shake", float(Settings.get_value("camera_shake")), false)
	assert_near(_tree(lv).visibility_range_end, 50.0, 0.001, "only graphics_quality re-applies")
	# Leaving the tree puts the viewport's MSAA back.
	Settings.set_value("graphics_quality", "low", false)
	world.remove_child(lv)
	lv.free()
	assert_eq(int(get_viewport().msaa_3d), _msaa_before, "the viewport MSAA is restored when the level leaves")


func test_the_command_line_flag_fixes_the_preset() -> void:
	assert_eq(Settings.parse_graphics_arg(PackedStringArray(["--graphics=low"])),
		{"value": "low", "error": ""}, "--graphics=low")
	assert_eq(str(Settings.parse_graphics_arg(PackedStringArray(["--mode=valley", "--graphics=MEDIUM"])).value),
		"medium", "case does not matter")
	assert_eq(str(Settings.parse_graphics_arg(PackedStringArray([])).value), "", "no flag: no override")
	var bad := Settings.parse_graphics_arg(PackedStringArray(["--graphics=ultra"]))
	assert_eq(str(bad.value), "", "an unknown preset is no override")
	assert_true(str(bad.error).contains("--graphics=ultra"), "and an error to warn about (%s)" % bad.error)
	assert_eq(Settings.resolve_graphics_quality("medium", "", false), "medium", "saved medium")
	assert_eq(Settings.resolve_graphics_quality("low", "", false), "low", "saved low")
	assert_eq(Settings.resolve_graphics_quality("medium", "low", false), "low", "the flag wins over the setting")
	assert_eq(Settings.resolve_graphics_quality("low", "medium", false), "medium", "both ways")
	assert_eq(Settings.resolve_graphics_quality("medium", "", true), "low", "the web always runs low")
	assert_eq(Settings.resolve_graphics_quality("medium", "medium", true), "low", "even with the flag")
	assert_eq(Settings.resolve_graphics_quality("ultra", "", false), Settings.GRAPHICS_DEFAULT, "unknown saved value")
	assert_eq(Settings.GRAPHICS_DEFAULT, "medium", "desktop default medium")
	assert_eq(str(Settings.DEFAULTS.graphics_quality), "medium", "the default setting")
	# The flag decides the level's preset and locks the settings row.
	Settings.values["graphics_quality"] = "medium"
	Settings.graphics_override = "low"
	assert_eq(Settings.graphics_quality, "low", "the preset in effect")
	assert_true(Settings.graphics_lock_reason().contains("--graphics=low"), "the row explains why it is locked")
	var lv := _level(LEVEL_ID, false)
	await step_ticks(1)
	assert_near(_sun(lv).directional_shadow_max_distance, 60.0, 0.001, "--graphics=low applies low")
	var grid := GridContainer.new()
	world.add_child(grid)
	var row := SettingsPages.graphics_row(grid)
	assert_true(row.disabled, "the settings row is disabled while the flag rules")
	assert_eq(row.get_item_text(row.selected), "Low", "and shows the preset in effect")
	Settings.graphics_override = ""
	assert_eq(Settings.graphics_lock_reason(), "", "no flag: the setting decides")
	var free_row := SettingsPages.graphics_row(grid)
	assert_false(free_row.disabled, "the row is enabled without the flag")
	assert_eq(free_row.item_count, 2, "Low and Medium")
	assert_eq(free_row.get_item_text(free_row.selected), "Medium", "showing the saved setting")
	free_row.item_selected.emit(0)
	assert_eq(str(Settings.get_value("graphics_quality")), "low", "choosing Low changes the setting")
	assert_near(_sun(lv).directional_shadow_max_distance, 60.0, 0.001, "and the level follows")
	grid.queue_free()


func test_the_web_build_runs_low_with_nearer_ai_tier_1() -> void:
	Settings.values["graphics_quality"] = "medium"
	LevelRoot.force_web_for_tests = true
	var lv := _level()
	await step_ticks(1)
	assert_true(LevelRoot.is_web(), "forced web")
	assert_eq(lv.graphics_quality(), "low", "the web overrides force low over a medium setting")
	assert_near(_sun(lv).directional_shadow_max_distance, 60.0, 0.001, "web: shadows to 60 m")
	assert_near(_tree(lv).visibility_range_end, 160.0, 0.001, "web: scenery to 160 m")
	assert_eq(int(get_viewport().msaa_3d), int(Viewport.MSAA_DISABLED), "web: no MSAA")
	assert_near(lv.director().near_m, 30.0, 0.001, "web: AI tier 1 from 30 m")
	assert_near(lv.director().mid_m, 90.0, 0.001, "tier 2 still from 90 m")
	assert_near(float(lv.applied_graphics.get("ai_tier1_m", 0.0)), 30.0, 0.001, "reported")
	assert_true(bool(lv.applied_graphics.get("web", false)), "and marked as the web preset")
	assert_eq(lv.director().lod_tier_for(Vector3(35, 0, 0), Vector3.ZERO, false), 1, "35 m away: tier 1 on the web")
	# A setting change cannot leave low on the web.
	Settings.set_value("graphics_quality", "medium", false)
	assert_near(_sun(lv).directional_shadow_max_distance, 60.0, 0.001, "still low after a setting change")
	# Without the forced flag the same record gives the desktop distances.
	LevelRoot.force_web_for_tests = false
	var desk := _level()
	await step_ticks(1)
	assert_near(desk.director().near_m, 40.0, 0.001, "desktop: tier 1 from 40 m")
	assert_eq(desk.director().lod_tier_for(Vector3(35, 0, 0), Vector3.ZERO, false), 0, "35 m away: tier 0 on desktop")


func test_level_records_carry_the_presets() -> void:
	for id: String in ["level.valley", "level.director_test", "level.stress_arena"]:
		var rec := GameData.get_record(id)
		if id == "level.stress_arena" and rec.is_empty():
			continue   # the stress arena's record arrives with its scene
		assert_eq(str(rec.get("type", "")), "level", "%s exists" % id)
		var render: Dictionary = rec.get("render", {})
		assert_eq(_numbers(render.get("low", {})), {"msaa": 0.0, "scenery_visibility_end_m": 160.0,
			"shadow_distance_m": 60.0}, "%s: the low preset (plan §5.4)" % id)
		assert_eq(_numbers(render.get("medium", {})), {"msaa": 2.0, "scenery_visibility_end_m": 220.0,
			"shadow_distance_m": 120.0}, "%s: the medium preset" % id)
		var web: Dictionary = rec.get("web_overrides", {})
		assert_eq(str(web.get("quality", "")), "low", "%s: the web build runs low" % id)
		assert_near(float(web.get("ai_tier1_m", 0.0)), 30.0, 0.001, "%s: web AI tier 1 from 30 m" % id)
	# A level without a record (or without presets) applies nothing and does not fail.
	var bare := _level("level.no_such_level", false)
	await step_ticks(1)
	assert_near(_sun(bare).directional_shadow_max_distance, 90.0, 0.001, "no record: the scene's own shadow distance")
	assert_false(bare.applied_graphics.has("msaa"), "no MSAA change without a preset")
