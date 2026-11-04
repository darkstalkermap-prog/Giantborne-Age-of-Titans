extends TestSuite
## Spec section 7 formulas, including the handoff's worked example.


func test_worked_example_unblocked() -> void:
	var raw := CombatRules.raw_damage(40.0, 10.0, 1.0, 1.0, 1.0)
	assert_near(raw, 46.0, 1e-9, "raw damage P=40 Str=10")
	var mitigated := CombatRules.physical_after_armor(raw, 25.0)
	assert_near(mitigated, 36.8, 1e-9, "armor 25 mitigation")
	assert_eq(CombatRules.round_damage(mitigated), 37, "worked example rounds to 37")


func test_worked_example_blocked() -> void:
	var mitigated := CombatRules.physical_after_armor(46.0, 25.0)
	assert_eq(CombatRules.round_damage(mitigated * 0.25), 9, "blocked health damage is 9")
	assert_eq(CombatRules.impact_stamina_cost(mitigated, 0.25), 10, "impact stamina is ceil(9.2) = 10")


func test_worked_example_heavy() -> void:
	var raw := CombatRules.raw_damage(40.0, 10.0, 1.8, 1.0, 1.0)
	assert_near(raw, 82.8, 1e-9, "heavy raw 82.8")
	assert_eq(CombatRules.round_damage(CombatRules.physical_after_armor(raw, 25.0)), 66, "heavy final 66")


func test_size_multiplier() -> void:
	assert_near(CombatRules.size_multiplier(3.6576), 1.0, 1e-9, "stage 1 is 1.0")
	assert_near(CombatRules.size_multiplier(1.8), 1.0, 1e-9, "humans clamp to 1.0")
	assert_near(CombatRules.size_multiplier(7.9248), pow(7.9248 / 3.6576, 0.45), 1e-9, "stage 3 power law")
	assert_near(CombatRules.size_multiplier(42.67), 2.5, 1e-9, "stage 10 clamps to 2.5")


func test_resistance_and_armor_rules() -> void:
	assert_near(CombatRules.elemental_after_resistance(100.0, 0.9), 25.0, 1e-9, "resistance clamps at 0.75")
	assert_near(CombatRules.elemental_after_resistance(100.0, -2.0), 150.0, 1e-9, "resistance clamps at -0.5")
	assert_near(CombatRules.effective_armor(25.0, 30.0), 0.0, 1e-9, "penetration cannot make armor negative")
	assert_near(CombatRules.physical_after_armor(46.0, 0.0), 46.0, 1e-9, "zero armor")


func test_poise_scale_and_knockback() -> void:
	assert_near(CombatRules.poise_scale(3.6576, 1.8), 2.0, 1e-9, "giant vs human clamps to 2")
	assert_near(CombatRules.poise_scale(1.8, 3.6576), 1.8 / 3.6576, 1e-9, "human vs giant")
	assert_near(CombatRules.poise_scale(1.0, 42.67), 0.25, 1e-9, "tiny vs titan clamps to 0.25")
	assert_near(CombatRules.knockback_speed(5.0, 2.0, 1.0, 9.0), 9.0, 1e-9, "knockback clamps to max")
	assert_near(CombatRules.knockback_speed(2.0, 2.0, 4.0, 9.0), 1.0, 1e-9, "stability divides")
	assert_near(CombatRules.knockback_speed(-3.0, 1.0, 1.0, 9.0), 0.0, 1e-9, "never negative")


func test_impact_cost_ceil_exact() -> void:
	assert_eq(CombatRules.impact_stamina_cost(40.0, 0.25), 10, "exact 10.0 stays 10")
	assert_eq(CombatRules.impact_stamina_cost(40.04, 0.25), 11, "10.01 rounds up")
	assert_eq(CombatRules.impact_stamina_cost(0.0, 0.25), 0, "zero")


func test_block_arc_is_frontal_120() -> void:
	var pos := Vector3.ZERO
	var fwd := Vector3(0, 0, -1)
	assert_true(CombatRules.block_covers(pos, fwd, Vector3(0, 0, -5), 120.0), "front")
	assert_true(CombatRules.block_covers(pos, fwd, Vector3(5 * sin(deg_to_rad(59.0)), 0, -5 * cos(deg_to_rad(59.0))), 120.0), "59 degrees")
	assert_false(CombatRules.block_covers(pos, fwd, Vector3(5 * sin(deg_to_rad(61.0)), 0, -5 * cos(deg_to_rad(61.0))), 120.0), "61 degrees")
	assert_false(CombatRules.block_covers(pos, fwd, Vector3(0, 0, 5), 120.0), "behind")


func test_attribute_rules() -> void:
	assert_near(CombatRules.recovery_scale(10.0), 1.0, 1e-9, "dex 10")
	assert_near(CombatRules.recovery_scale(20.0), 0.95, 1e-9, "dex 20 = 5%")
	assert_near(CombatRules.recovery_scale(100.0), 0.85, 1e-9, "cap 15%")
	assert_near(CombatRules.willpower_resistance_bonus(100.0), 0.20, 1e-9, "cap 20 points")
	assert_eq(CombatRules.xp_to_next_level(1), 100, "level 1")
	assert_eq(CombatRules.xp_to_next_level(19), 1000, "level 19")
	assert_eq(CombatRules.xp_to_next_level(20), 0, "level 20 capped")
