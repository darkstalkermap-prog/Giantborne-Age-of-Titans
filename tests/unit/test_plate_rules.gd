extends TestSuite
## A2: the plate rules (PlateRules, pure) and a titan's plate state (PlateSet) without the engine: parsing and the
## defaults, what a blow on an intact, a broken and an armour-only plate does, the stone a blow takes (a Heavy
## cracks it faster), the break at 0 and only once, the region pick's order (deterministic: plain values), the
## resolver's region multipliers (exactly 1.0 leaves every pinned number alone) and the record checks.

const REC := {"plates": [
	{"id": "shoulder_l", "region": "shoulder_l", "piece": "plate_shoulder_l", "anchor": "PlateShoulderL",
		"health": 100, "reduction": 0.85, "weak_multiplier": 2.0, "break": {"stagger_s": 2.2, "debris": 10}},
	{"id": "back", "region": "back", "health": 200, "reduction": 0.8, "poise_reduction": 0.5, "weak_multiplier": 3.0,
		"heavy_multiplier": 2.0},
	{"id": "shin_l", "region": "shin_l", "breakable": false, "reduction": 0.7},
]}


func _hit(region: String, power := 100.0, tags := PackedStringArray(["Melee"])) -> HitEvent:
	var h := HitEvent.new()
	h.region = region
	h.power = power
	h.attacker_stat = 0.0
	h.size_policy = "none"
	h.poise_damage = 40.0
	h.tags = tags
	return h


func _defender(armor := 0.0) -> Combatant:
	return Combatant.from_record("t", {"id": "enemy.t", "health": 5000, "armor": armor,
		"poise": {"threshold": 999, "recover_per_s": 0, "recover_delay_s": 1, "stagger_s": 1, "immunity_s": 1}}, 16.8)


func _resolve(s: PlateSet, h: HitEvent, d: Combatant) -> HitResult:
	s.prepare(h)
	var r := DamageResolver.resolve(h, d, DefenseState.new())
	r.plate = s.absorb(r)
	return r


func test_parse_fills_the_defaults() -> void:
	var ps := PlateRules.parse(REC)
	assert_eq(ps.size(), 3, "three plates in the record's order")
	assert_eq(str(ps[0].id), "shoulder_l", "the first")
	assert_near(float(ps[0].stagger_s), 2.2, 1e-6, "its own stagger")
	assert_eq(int(ps[0].debris), 10, "its own debris")
	assert_near(float(ps[0].heavy_multiplier), PlateRules.DEFAULT_HEAVY_MULT, 1e-6, "the default heavy multiplier")
	assert_near(float(ps[0].poise_reduction), 0.85, 1e-6, "poise reduction defaults to the reduction")
	assert_near(float(ps[1].poise_reduction), 0.5, 1e-6, "or its own")
	assert_false(bool(ps[2].breakable), "the shin is armour only")
	assert_near(float(ps[2].weak_multiplier), 1.0, 1e-6, "armour never exposes a weak point")
	assert_eq(PlateRules.parse({}).size(), 0, "no plates block: none")


func test_effect_intact_broken_and_bare() -> void:
	var p := PlateRules.parse(REC)[0] as Dictionary
	var intact := PlateRules.effect(p, false)
	assert_eq(str(intact.state), PlateRules.STATE_ARMOURED, "intact: armoured")
	assert_near(float(intact.damage_mult), 0.15, 1e-6, "15 % reaches the body")
	assert_near(float(intact.poise_mult), 0.15, 1e-6, "and 15 % of the poise")
	var broken := PlateRules.effect(p, true)
	assert_eq(str(broken.state), PlateRules.STATE_WEAK, "broken: a weak point")
	assert_near(float(broken.damage_mult), 2.0, 1e-6, "its multiplier")
	assert_near(float(broken.poise_mult), 1.0, 1e-6, "full poise")
	var bare := PlateRules.effect({}, false)
	assert_eq(str(bare.state), PlateRules.STATE_BODY, "no plate: the body")
	assert_eq(float(bare.damage_mult), 1.0, "exactly 1.0")
	assert_eq(float(bare.poise_mult), 1.0, "exactly 1.0")


func test_stone_damage_and_heavy() -> void:
	var ps := PlateRules.parse(REC)
	var tags := PackedStringArray(["Melee"])
	var heavy := PackedStringArray(["Melee", "Heavy"])
	assert_near(PlateRules.stone_damage(ps[0], 40.0, tags), 40.0, 1e-6, "the raw damage")
	assert_near(PlateRules.stone_damage(ps[0], 40.0, heavy), 60.0, 1e-6, "a Heavy x1.5")
	assert_near(PlateRules.stone_damage(ps[1], 40.0, heavy), 80.0, 1e-6, "the plate's own heavy multiplier")
	assert_eq(PlateRules.stone_damage(ps[2], 40.0, heavy), 0.0, "armour only takes no stone")
	assert_eq(PlateRules.stone_damage({}, 40.0, tags), 0.0, "no plate")


func test_region_of_and_default() -> void:
	assert_eq(PlateRules.region_of("back"), "back", "its own")
	assert_eq(PlateRules.region_of(""), PlateRules.DEFAULT_REGION, "no hurtbox: the default")
	assert_eq(PlateRules.region_of("", "legs"), "legs", "the record's default")


func test_a_plate_takes_blows_then_breaks_once_and_exposes_the_weak_point() -> void:
	var s := PlateSet.from_record(REC)
	var d := _defender()
	var r1 := _resolve(s, _hit("shoulder_l", 60.0), d)
	assert_eq(r1.event.plate_id, "shoulder_l", "the shoulder's plate")
	assert_eq(r1.event.plate_state, PlateRules.STATE_ARMOURED, "armoured")
	assert_eq(r1.health_damage, 9, "15 % of 60 reaches the body")
	assert_near(r1.poise_damage, 40.0 * 0.15 * CombatRules.poise_scale(CombatRules.REFERENCE_HEIGHT_M, DefenseState.new().height_m), 1e-4,
		"and 15 % of the poise")
	assert_near(float(r1.plate.stone), 60.0, 1e-6, "the stone took the raw 60")
	assert_near(float(r1.plate.left), 40.0, 1e-6, "40 left")
	assert_false(bool(r1.plate.broken), "not yet")
	assert_near(s.health_frac("shoulder_l"), 0.4, 1e-6, "40 %")
	var r2 := _resolve(s, _hit("shoulder_l", 60.0), d)
	assert_true(bool(r2.plate.broken), "the second blow breaks it")
	assert_eq(r2.event.plate_state, PlateRules.STATE_ARMOURED, "(it struck an intact plate)")
	assert_true(s.is_broken("shoulder_l"), "broken")
	assert_eq(s.break_order, ["shoulder_l"] as Array[String], "once, in order")
	var r3 := _resolve(s, _hit("shoulder_l", 60.0), d)
	assert_eq(r3.event.plate_state, PlateRules.STATE_WEAK, "now a weak point")
	assert_eq(r3.health_damage, 120, "x2.0")
	assert_false(bool(r3.plate.broken), "it never breaks twice")
	assert_eq(s.broken_count(), 1, "one break")
	assert_eq(s.intact_breakable(), ["back"] as Array[String], "the back still holds")


func test_armour_only_and_the_bare_body() -> void:
	var s := PlateSet.from_record(REC)
	var d := _defender()
	var shin := _resolve(s, _hit("shin_l", 100.0), d)
	assert_eq(shin.event.plate_state, PlateRules.STATE_ARMOURED, "the shin is armoured")
	assert_eq(shin.health_damage, 30, "70 % kept")
	assert_eq(float(shin.plate.stone), 0.0, "no stone taken")
	assert_false(s.is_broken("shin_l"), "never breaks")
	var torso := _resolve(s, _hit("torso", 100.0), d)
	assert_eq(torso.event.plate_id, "", "no plate on the torso")
	assert_true(torso.plate.is_empty(), "nothing absorbed")
	assert_eq(torso.health_damage, 100, "the whole blow")
	var none := _resolve(s, _hit("", 100.0), d)
	assert_eq(none.health_damage, 100, "no hurtbox: the default region (the torso)")


func test_a_heavy_cracks_faster_and_an_evaded_blow_takes_no_stone() -> void:
	var s := PlateSet.from_record(REC)
	var d := _defender()
	var r := _resolve(s, _hit("back", 60.0, PackedStringArray(["Melee", "Heavy"])), d)
	assert_near(float(r.plate.stone), 120.0, 1e-6, "the back's heavy multiplier 2.0")
	var h := _hit("back", 60.0)
	s.prepare(h)
	var miss := HitResult.new()
	miss.event = h
	miss.outcome = HitResult.Outcome.EVADED
	miss.raw_damage = 60.0
	assert_near(float(s.absorb(miss).stone), 0.0, 1e-6, "only a landed blow cracks it")
	assert_near(s.health_frac("back"), 0.4, 1e-6, "80 of 200 left")


func test_armour_applies_before_the_plate() -> void:
	var s := PlateSet.from_record(REC)
	var d := _defender(60.0)
	var r := _resolve(s, _hit("shoulder_l", 160.0), d)
	assert_eq(r.health_damage, CombatRules.round_damage(160.0 * 100.0 / 160.0 * 0.15), "armour, then the plate")
	assert_near(float(r.plate.stone), 160.0, 1e-6, "the stone takes the raw blow (the body's armour is not the stone's)")


func test_reset_and_force_break_and_snapshot() -> void:
	var s := PlateSet.from_record(REC)
	assert_true(s.force_break("back"), "breaks")
	assert_false(s.force_break("back"), "only once")
	assert_false(s.force_break("shin_l"), "armour never breaks")
	assert_false(s.force_break("nope"), "an unknown plate")
	assert_true(bool((s.snapshot().back as Dictionary).broken), "the snapshot says so")
	s.reset()
	assert_eq(s.broken_count(), 0, "a new attempt: whole again")
	assert_near(s.health_frac("back"), 1.0, 1e-6, "full stone")


func test_unplated_hits_keep_exact_numbers() -> void:
	var h := _hit("torso", 77.0)
	var d := _defender(35.0)
	var plain := DamageResolver.resolve(h, d, DefenseState.new())
	assert_eq(h.region_damage_mult, 1.0, "a hit nobody prepared keeps 1.0")
	assert_eq(h.region_poise_mult, 1.0, "and 1.0 poise")
	var again := _hit("torso", 77.0)
	again.region = ""
	assert_eq(DamageResolver.resolve(again, d, DefenseState.new()).mitigated_damage, plain.mitigated_damage,
		"the region field alone changes nothing")


func test_pick_order_is_plain_and_total() -> void:
	var a := {"substep": 1, "contact": 2.0, "distance": 5.0, "region": "torso"}
	var b := {"substep": 2, "contact": 0.1, "distance": 1.0, "region": "brow"}
	assert_true(PlateRules.pick_before(a, b), "the earlier sub-step first")
	var c := {"substep": 1, "contact": 1.0, "distance": 9.0, "region": "shoulder_l"}
	assert_true(PlateRules.pick_before(c, a), "then the deeper contact")
	var e := {"substep": 1, "contact": 1.0, "distance": 9.0, "region": "back"}
	assert_true(PlateRules.pick_before(e, c), "then the region's name")
	assert_false(PlateRules.pick_before(c, e), "a total order")


func test_record_errors() -> void:
	var bad := {"plates": [{"id": "a", "region": "x", "reduction": 0.5, "health": 0},
		{"id": "a", "region": "x", "reduction": 0.5, "health": 10},
		{"id": "c", "region": "y", "reduction": 0.5, "breakable": false, "weak_multiplier": 2.0}]}
	var errs := PlateRules.errors(bad, "enemy.bad")
	assert_eq(errs.size(), 4, "four problems: %s" % ", ".join(errs))
	assert_eq(PlateRules.errors(REC, "enemy.ok").size(), 0, "the good record is clean")
	assert_eq(PlateRules.errors(GameData.get_record("enemy.stoneback"), "enemy.stoneback").size(), 0,
		"Stoneback's plates are clean")
