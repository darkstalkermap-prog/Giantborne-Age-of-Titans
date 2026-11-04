extends TestSuite
## DamageResolver outcomes: hit, block, parry (and its boundaries), guard break, dodge,
## immunity, typed damage. Defender uses armor 25 so numbers match the worked example.

var defender: Combatant


func before_each() -> void:
	defender = Combatant.from_record("def", {"id": "test.def", "health": 500, "armor": 25,
		"height_m": 3.6576, "poise": {"threshold": 100}})


func _hit(power := 40.0, mult := 1.0, tags := PackedStringArray(["Melee", "Parryable"])) -> HitEvent:
	var h := HitEvent.new()
	h.power = power
	h.ability_multiplier = mult
	h.attacker_stat = 10.0
	h.attacker_height_m = 3.6576
	h.damage_split = {"physical": 1.0}
	h.tags = tags
	h.poise_damage = 12.0
	h.attacker_position = Vector3(0, 0, -3)   # in front of a defender facing -Z
	return h


func _defense(blocking := false, elapsed := 0, stamina := 100.0) -> DefenseState:
	var d := DefenseState.new()
	d.position = Vector3.ZERO
	d.forward = Vector3(0, 0, -1)
	d.height_m = 3.6576
	d.blocking = blocking
	d.block_elapsed_ticks = elapsed
	d.parry_available = blocking
	d.stamina = stamina
	d.apply_block_def(GameData.get_action("action.block"))
	return d


func test_hit_matches_worked_example() -> void:
	var r := DamageResolver.resolve(_hit(), defender, _defense())
	assert_eq(r.outcome, HitResult.Outcome.HIT, "outcome")
	assert_eq(r.health_damage, 37, "health damage 37")
	assert_near(r.poise_damage, 12.0, 1e-9, "same-size poise scale 1")


func test_block_matches_worked_example() -> void:
	var r := DamageResolver.resolve(_hit(), defender, _defense(true, 30))
	assert_eq(r.outcome, HitResult.Outcome.BLOCKED, "outcome")
	assert_eq(r.health_damage, 9, "blocked health damage 9")
	assert_near(r.stamina_damage, 10.0, 1e-9, "impact stamina 10")
	assert_near(r.poise_damage, 0.0, 1e-9, "blocked hits do not add poise")


func test_heavy_matches_worked_example() -> void:
	var r := DamageResolver.resolve(_hit(40.0, 1.8), defender, _defense())
	assert_eq(r.health_damage, 66, "heavy 66")


func test_parry_window_boundaries() -> void:
	for t in [0, 1, 11]:
		var r := DamageResolver.resolve(_hit(), defender, _defense(true, t))
		assert_eq(r.outcome, HitResult.Outcome.PARRIED, "tick %d of block is inside the 0.20 s window" % t)
		assert_eq(r.health_damage, 0, "parry negates damage")
		assert_near(r.stamina_damage, 5.0, 1e-9, "parry costs 5 extra")
		assert_near(r.attacker_poise_damage, 40.0, 1e-9, "40 poise to the attacker")
	var late := DamageResolver.resolve(_hit(), defender, _defense(true, 12))
	assert_eq(late.outcome, HitResult.Outcome.BLOCKED, "tick 12 (0.20 s) is an ordinary block")


func test_parry_needs_its_stamina_else_ordinary_block() -> void:
	# P=10 -> 11.5 raw -> 9.2 mitigated -> impact ceil(2.3) = 3. Stamina 4 < 5 parry cost.
	var r := DamageResolver.resolve(_hit(10.0), defender, _defense(true, 2, 4.0))
	assert_eq(r.outcome, HitResult.Outcome.BLOCKED, "falls back to an ordinary block")
	assert_eq(r.health_damage, 2, "9.2 * 0.25 = 2.3 -> 2")
	assert_eq(r.notes, "failed_parry", "flagged so the window is consumed")


func test_consumed_parry_window_blocks_only() -> void:
	var d := _defense(true, 3)
	d.parry_available = false
	var r := DamageResolver.resolve(_hit(), defender, d)
	assert_eq(r.outcome, HitResult.Outcome.BLOCKED, "a failed parry cannot be retried for free")


func test_unparryable_and_unblockable() -> void:
	var r := DamageResolver.resolve(_hit(40.0, 1.0, PackedStringArray(["Melee", "Unparryable"])), defender, _defense(true, 2))
	assert_eq(r.outcome, HitResult.Outcome.BLOCKED, "unparryable is still blockable")
	var u := DamageResolver.resolve(_hit(40.0, 1.0, PackedStringArray(["Melee", "Parryable", "Unblockable"])), defender, _defense(true, 2))
	assert_eq(u.outcome, HitResult.Outcome.HIT, "unblockable ignores block (and parry)")
	var magic := DamageResolver.resolve(_hit(40.0, 1.0, PackedStringArray(["Magic", "Parryable"])), defender, _defense(true, 2))
	assert_eq(magic.outcome, HitResult.Outcome.BLOCKED, "only melee can be parried")


func test_block_only_covers_front() -> void:
	var h := _hit()
	h.attacker_position = Vector3(0, 0, 3)  # behind
	var r := DamageResolver.resolve(h, defender, _defense(true, 30))
	assert_eq(r.outcome, HitResult.Outcome.HIT, "attacks from behind are not blocked")
	assert_eq(r.health_damage, 37, "full damage from behind")


func test_guard_break() -> void:
	var r := DamageResolver.resolve(_hit(), defender, _defense(true, 30, 7.0))
	assert_eq(r.outcome, HitResult.Outcome.GUARD_BROKEN, "impact 10 > stamina 7")
	assert_near(r.stamina_damage, 7.0, 1e-9, "consumes the remaining stamina")
	assert_eq(r.health_damage, 18, "50% of 36.8 = 18.4 -> 18")
	assert_near(r.stagger_s, 1.0, 1e-9, "1.0 s stagger")


func test_dodge_invulnerability() -> void:
	var d := _defense()
	d.invulnerable = true
	assert_eq(DamageResolver.resolve(_hit(), defender, d).outcome, HitResult.Outcome.EVADED, "i-frames evade")
	var unavoidable := _hit(40.0, 1.0, PackedStringArray(["Unavoidable"]))
	assert_eq(DamageResolver.resolve(unavoidable, defender, d).outcome, HitResult.Outcome.HIT, "Unavoidable ignores i-frames")


func test_dead_and_immune_targets() -> void:
	var d := _defense()
	d.is_dead = true
	assert_eq(DamageResolver.resolve(_hit(), defender, d).outcome, HitResult.Outcome.IGNORED, "dead target ignored")
	var immune := Combatant.from_record("imm", {"id": "test.imm", "health": 10, "immunities": ["physical"]})
	var r := DamageResolver.resolve(_hit(), immune, _defense())
	assert_eq(r.outcome, HitResult.Outcome.IMMUNE, "immune")
	assert_eq(r.health_damage, 0, "immunity yields zero damage (no minimum damage)")


func test_crit_then_weak_point_then_mitigation() -> void:
	var h := _hit()
	h.crit = true
	h.weak_point = true
	var r := DamageResolver.resolve(h, defender, _defense())
	# 46 * 1.5 * 1.25 = 86.25 -> * 100/125 = 69.0
	assert_near(r.raw_damage, 86.25, 1e-9, "crit and weak point multiply raw")
	assert_eq(r.health_damage, 69, "rounded once at the end")


func test_typed_damage_split() -> void:
	var resist := Combatant.from_record("r", {"id": "test.r", "health": 500, "armor": 25,
		"resistances": {"fire": 0.5}})
	var h := _hit()
	h.damage_split = {"physical": 0.5, "fire": 0.5}
	var r := DamageResolver.resolve(h, resist, _defense())
	# physical 23 -> 18.4 ; fire 23 * 0.5 = 11.5 ; total 29.9 -> 30
	assert_eq(r.health_damage, 30, "armor only reduces the physical portion")
	var pure_fire := _hit()
	pure_fire.damage_split = {"fire": 1.0}
	var armored := Combatant.from_record("a", {"id": "test.a", "health": 500, "armor": 1000})
	assert_eq(DamageResolver.resolve(pure_fire, armored, _defense()).health_damage, 46, "armor never reduces elemental")


func test_size_scaled_poise() -> void:
	var human := Combatant.from_record("h", {"id": "test.h", "health": 200, "height_m": 1.8})
	var d := _defense()
	d.height_m = 1.8
	var r := DamageResolver.resolve(_hit(), human, d)
	assert_near(r.poise_damage, 24.0, 1e-9, "giant vs human poise x2")
