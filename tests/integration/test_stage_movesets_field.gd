extends IntegrationSuite
## Weapons' stage_movesets (P26, plan M6-M9 §2.9, §2.11, decision 24): PlayerEquipment swings the
## entry with the highest stage key at or below the giant's stage while the weapon fits it; an id
## with no action record falls back to the weapon's own moveset (the reinforced weapons point at
## P31's stage-4 records); a weapon too small for the stage keeps its own. Growing and shrinking
## swap the controller's light chain and heavy; the weapon schema checks the field.

## A fixture moveset for stage 4: the sword's chain and the hammer's heavy (existing records).
const FIXTURE := {"4": {"light_chain": "ability.sword_light_1", "heavy": "ability.hammer_heavy"}}


func test_moveset_for_picks_the_highest_stage_key_that_fits() -> void:
	var rec := {"light_chain": "ability.light_1", "heavy": "ability.heavy_1", "scales_with_growth": true,
		"fit_max_stage": 6, "stage_movesets": FIXTURE}
	var at3 := PlayerEquipment.moveset_for(rec, 3)
	assert_eq([at3.light_chain, at3.heavy, at3.stage], ["ability.light_1", "ability.heavy_1", 0], "stage 3: the weapon's own")
	for stage in [4, 5, 6]:
		var m := PlayerEquipment.moveset_for(rec, stage)
		assert_eq([m.light_chain, m.heavy, m.stage], ["ability.sword_light_1", "ability.hammer_heavy", 4],
			"stage %d: the stage-4 moveset" % stage)
	var two := rec.duplicate(true)
	two.stage_movesets = {"4": FIXTURE["4"], "6": {"light_chain": "ability.hammer_light_1"}}
	var m6 := PlayerEquipment.moveset_for(two, 6)
	assert_eq([m6.light_chain, m6.heavy, m6.stage], ["ability.hammer_light_1", "ability.heavy_1", 6],
		"stage 6: the stage-6 entry (its missing heavy is the weapon's own)")
	var small := rec.duplicate(true)
	small.fit_max_stage = 3
	assert_eq(PlayerEquipment.moveset_for(small, 4).light_chain, "ability.light_1", "too small for stage 4: its own moveset")
	var missing := rec.duplicate(true)
	# P31 ships the club's great moveset, so the missing ids are ones no record will ever have.
	missing.stage_movesets = {"4": {"light_chain": "ability.test_no_such_light", "heavy": "ability.test_no_such_heavy"}}
	var mm := PlayerEquipment.moveset_for(missing, 4)
	assert_eq([mm.light_chain, mm.heavy, mm.stage], ["ability.light_1", "ability.heavy_1", 0],
		"ids with no action record fall back to the weapon's moveset")
	for id in ["weapon.club_reinforced", "weapon.sword_reinforced", "weapon.hammer_reinforced"]:
		var r := GameData.get_record(id)
		assert_eq(int(r.get("fit_max_stage", 0)), 6, "%s fits stage 6" % id)
		assert_true((r.get("stage_movesets", {}) as Dictionary).has("4"), "%s names its stage-4 moveset" % id)
		var own := PlayerEquipment.moveset_for(r, 4)
		var expect_light := str(r.get("light_chain", "ability.light_1"))
		if GameData.get_action(str(r.stage_movesets["4"].light_chain)) != null:
			expect_light = str(r.stage_movesets["4"].light_chain)
		assert_eq(own.light_chain, expect_light, "%s at stage 4: its stage-4 chain once it exists, its own until then" % id)


func test_growing_swaps_the_moveset_at_its_stage() -> void:
	TestFixtures.record_override("weapon.club", {"fit_max_stage": 6, "stage_movesets": FIXTURE})
	var p := spawn_player(Vector3(0, 0.05, 0))
	await TestWait.until(self, func() -> bool: return p.is_on_floor(), 30)
	assert_eq([p.controller.loadout.light, p.controller.loadout.heavy], ["ability.light_1", "ability.heavy_1"],
		"stage 1: the club's own moveset")
	assert_true((p.growth.debug_set_stage(4) as Dictionary).ok, "grow to 4")
	assert_eq([p.controller.loadout.light, p.controller.loadout.heavy], ["ability.sword_light_1", "ability.hammer_heavy"],
		"stage 4: the stage-4 moveset")
	assert_true(p.controller.library.has("ability.sword_light_1") and p.controller.library.has("ability.hammer_heavy"),
		"and its actions are in the controller's library")
	await step_ticks(2)
	assert_true((p.growth.debug_set_stage(3) as Dictionary).ok, "shrink to 3")
	assert_eq([p.controller.loadout.light, p.controller.loadout.heavy], ["ability.light_1", "ability.heavy_1"],
		"stage 3 again: the club's own")


func test_the_weapon_schema_checks_stage_movesets() -> void:
	var base := GameData.get_record("weapon.club_reinforced").duplicate(true)
	var bad_key := base.duplicate(true)
	bad_key.stage_movesets = {"7": FIXTURE["4"]}
	var bad_slot := base.duplicate(true)
	bad_slot.stage_movesets = {"4": {"light": "ability.light_1"}}
	var good := base.duplicate(true)
	good.stage_movesets = FIXTURE
	assert_eq(_errors(good), PackedStringArray(), "a stage-4 moveset within the fit is valid")
	assert_true(_errors(bad_key).size() > 0, "a key above fit_max_stage is an error (%s)" % ", ".join(_errors(bad_key)))
	assert_true(_errors(bad_slot).size() > 0, "an unknown slot is an error (%s)" % ", ".join(_errors(bad_slot)))


func _errors(rec: Dictionary) -> PackedStringArray:
	return PackedStringArray(DataValidator.validate_record(rec, "test.json").errors)
