extends TestSuite
## B3: a titan's plates that grow back (PlateRules.parse_regrow / regrow_at, PlateSet.regrow_step, pure): a broken
## plate's wound stays open (a weak point) for after_s, the bark grows back over it for over_s, and it is whole again
## with health_frac of its health; fire (the titan burning) sears an open or regrowing wound for good; a "wither"
## plate (the Rootwarden's knot) stops every wound's clock for block_s; the loot counts a plate broken once even if
## it grew back; a new attempt clears it all; the record checks.

const REC := {"plates": [
	{"id": "shoulder_l", "region": "shoulder_l", "health": 100, "reduction": 0.85, "weak_multiplier": 2.0,
		"regrow": {"after_s": 2.0, "over_s": 1.0, "health_frac": 0.5}},
	{"id": "back", "region": "back", "health": 200, "reduction": 0.85, "weak_multiplier": 2.8,
		"regrow": {"after_s": 3.0, "over_s": 2.0, "health_frac": 0.25, "burn_sears": false}},
	{"id": "knot", "region": "knot", "health": 100, "reduction": 0.8, "weak_multiplier": 2.4,
		"on_break": {"effect": "wither", "block_s": 5.0}},
	{"id": "brow", "region": "brow", "health": 100, "reduction": 0.9, "weak_multiplier": 3.0},
]}


func _plates() -> PlateSet:
	return PlateSet.from_record(REC)


## Runs `n` ticks of regrowth from `tick0` and returns every event in order ([tick, kind, id]).
func _run(s: PlateSet, tick0: int, n: int, burning := false) -> Array:
	var out: Array = []
	for i in n:
		var r := s.regrow_step(tick0 + i, burning)
		for kind: String in ["seared", "regrowing", "regrown"]:
			for id: String in r[kind]:
				out.append([tick0 + i, kind, id])
	return out


func test_parse_regrow_and_its_defaults() -> void:
	var ps := PlateRules.parse(REC)
	assert_near(float(ps[0].regrow.after_s), 2.0, 1e-6, "its own after_s")
	assert_true(bool(ps[0].regrow.burn_sears), "fire sears by default")
	assert_false(bool(ps[1].regrow.burn_sears), "unless the record says not")
	assert_true((ps[2].regrow as Dictionary).is_empty(), "the knot never regrows")
	assert_true((ps[3].regrow as Dictionary).is_empty(), "nor a plate without the block (Stoneback's stone)")
	assert_eq(str(ps[2].effect), PlateRules.EFFECT_WITHER, "the knot withers")
	assert_near(float(ps[2].block_s), 5.0, 1e-6, "for its own block_s")
	var d := PlateRules.parse_regrow({"after_s": 1.0})
	assert_near(float(d.over_s), float(PlateRules.REGROW_DEFAULTS.over_s), 1e-6, "the defaults fill the rest")
	assert_near(float(PlateRules.parse_regrow({"health_frac": 0.0}).health_frac), 0.05, 1e-6, "never regrown at 0")
	assert_true(PlateRules.parse_regrow(null).is_empty(), "absent: never")


func test_regrow_at_open_regrowing_whole() -> void:
	var rg := PlateRules.parse_regrow({"after_s": 2.0, "over_s": 1.0})
	assert_eq(str(PlateRules.regrow_at(rg, 0.0).state), PlateRules.WOUND_OPEN, "open at first")
	assert_eq(str(PlateRules.regrow_at(rg, 1.99).state), PlateRules.WOUND_OPEN, "open till after_s")
	var mid := PlateRules.regrow_at(rg, 2.5)
	assert_eq(str(mid.state), PlateRules.WOUND_REGROWING, "then regrowing")
	assert_near(float(mid.grow), 0.5, 1e-6, "half grown half way (smoothstep)")
	assert_true(float(PlateRules.regrow_at(rg, 2.2).grow) < 0.2, "slow at first")
	assert_eq(str(PlateRules.regrow_at(rg, 3.0).state), "", "whole at after_s + over_s")
	assert_near(float(PlateRules.regrow_at(rg, 3.0).grow), 1.0, 1e-6, "fully grown")


func test_a_broken_plate_regrows_on_its_clock() -> void:
	var s := _plates()
	assert_true(s.force_break("shoulder_l"), "broken")
	assert_eq(s.wound_state("shoulder_l"), PlateRules.WOUND_OPEN, "its wound open")
	assert_true(s.is_broken("shoulder_l"), "a weak point")
	assert_near(s.grow_of("shoulder_l"), 0.0, 1e-6, "nothing grown")
	var ev := _run(s, 1000, 119)
	assert_eq(ev.size(), 0, "nothing for 2 s")
	ev = _run(s, 1119, 1)
	assert_eq(ev, [[1119, "regrowing", "shoulder_l"]], "regrowing at 2 s, once")
	assert_true(s.is_broken("shoulder_l"), "still a weak point while it grows")
	ev = _run(s, 1120, 60)
	assert_eq(ev, [[1179, "regrown", "shoulder_l"]], "whole at 3 s")
	assert_false(s.is_broken("shoulder_l"), "whole again")
	assert_false(s.break_order.has("shoulder_l"), "out of the break order (the rig shows it)")
	assert_near(float(s.health.shoulder_l), 50.0, 1e-6, "with half its health")
	assert_eq(s.wound_state("shoulder_l"), "", "no wound")
	assert_eq(s.ever_broken, ["shoulder_l"] as Array[String], "but the loot remembers it broke")
	assert_eq(s.regrown, ["shoulder_l"] as Array[String], "and the report")
	assert_true(s.force_break("shoulder_l"), "it can break again")
	assert_eq(s.ever_broken, ["shoulder_l"] as Array[String], "the loot counts it once")


func test_fire_sears_an_open_and_a_regrowing_wound() -> void:
	var s := _plates()
	s.force_break("shoulder_l")
	var ev := _run(s, 0, 30)
	assert_eq(ev.size(), 0, "open, not yet growing")
	ev = _run(s, 30, 1, true)
	assert_eq(ev, [[30, "seared", "shoulder_l"]], "burning: seared at once")
	assert_eq(s.wound_state("shoulder_l"), PlateRules.WOUND_SEARED, "seared")
	ev = _run(s, 31, 600)
	assert_eq(ev.size(), 0, "a seared wound never regrows")
	assert_true(s.is_broken("shoulder_l"), "and stays a weak point")
	var s2 := _plates()
	s2.force_break("shoulder_l")
	_run(s2, 0, 140)
	assert_eq(s2.wound_state("shoulder_l"), PlateRules.WOUND_REGROWING, "growing back")
	ev = _run(s2, 140, 1, true)
	assert_eq(ev, [[140, "seared", "shoulder_l"]], "fire burns the new bark away")
	assert_near(s2.grow_of("shoulder_l"), 0.0, 1e-6, "nothing left of it")
	var s3 := _plates()
	s3.force_break("back")
	_run(s3, 0, 60, true)
	assert_eq(s3.wound_state("back"), PlateRules.WOUND_OPEN, "burn_sears false: fire does not sear it")
	var none := _plates()
	assert_eq(_run(none, 0, 10, true).size(), 0, "no wound, nothing to sear")


func test_the_knot_withers_every_wound() -> void:
	var s := _plates()
	s.force_break("shoulder_l")
	_run(s, 0, 60)
	s.force_break("knot")
	assert_eq(s.wound_state("knot"), "", "the knot has no wound of its own (it never regrows)")
	s.wither(60, 5.0)
	assert_true(s.is_withered(60), "withered")
	assert_true(s.is_withered(359), "for 5 s")
	assert_false(s.is_withered(360), "then not")
	var ev := _run(s, 60, 300)
	assert_eq(ev.size(), 0, "no clock runs while withered")
	assert_eq(int(s.wounds.shoulder_l.open_ticks), 60, "the shoulder's clock stopped at 1 s")
	ev = _run(s, 360, 60)
	assert_eq(ev, [[419, "regrowing", "shoulder_l"]], "it runs on from where it stopped")
	s.wither(500, 2.0)
	s.wither(500, 1.0)
	assert_eq(s.withered_until, 500 + 120, "the longest wither wins")
	var b := _plates()
	b.force_break("shoulder_l")
	b.wither(0, 5.0)
	assert_eq(_run(b, 0, 10, true), [[0, "seared", "shoulder_l"]], "fire still sears a withered wound")


func test_a_new_attempt_heals_every_wound() -> void:
	var s := _plates()
	s.force_break("shoulder_l")
	s.force_break("knot")
	s.wither(0, 50.0)
	s.reset()
	assert_true(s.wounds.is_empty(), "no wounds")
	assert_eq(s.withered_until, -1, "no wither")
	assert_true(s.ever_broken.is_empty(), "no loot breaks")
	assert_false(s.is_broken("shoulder_l"), "whole")


func test_a_blow_on_a_regrowing_wound_is_a_weak_point() -> void:
	var s := _plates()
	s.force_break("shoulder_l")
	_run(s, 0, 150)
	var h := HitEvent.new()
	h.region = "shoulder_l"
	s.prepare(h)
	assert_eq(h.plate_state, PlateRules.STATE_WEAK, "weak while the bark is still coming back")
	assert_near(h.region_damage_mult, 2.0, 1e-6, "its weak multiplier")
	_run(s, 150, 40)
	var h2 := HitEvent.new()
	h2.region = "shoulder_l"
	s.prepare(h2)
	assert_eq(h2.plate_state, PlateRules.STATE_ARMOURED, "armoured once grown")


func test_the_record_checks() -> void:
	var bad := {"plates": [
		{"id": "a", "region": "a", "breakable": false, "reduction": 0.5, "regrow": {"after_s": 1.0}},
		{"id": "b", "region": "b", "health": 10, "regrow": {"after_s": 1.0, "over_s": 0.0, "speed": 2.0}},
		{"id": "c", "region": "c", "health": 10, "regrow": {"health_frac": 1.5}},
		{"id": "d", "region": "d", "health": 10, "on_break": {"effect": "wither", "block_s": 0.0}},
		{"id": "e", "region": "e", "breakable": false, "reduction": 0.5, "on_break": {"effect": "wither"}},
	]}
	var errs := "\n".join(PlateRules.errors(bad, "rec"))
	assert_true(errs.contains("rec.plates[0]: only a breakable plate regrows"), "armour never regrows")
	assert_true(errs.contains("rec.plates[1].regrow: unknown key 'speed'"), "unknown keys")
	assert_true(errs.contains("rec.plates[1].regrow: over_s must be above 0"), "a growth takes time")
	assert_true(errs.contains("rec.plates[2].regrow: health_frac must be in (0, 1]"), "a share of its health")
	assert_true(errs.contains("rec.plates[3]: wither needs block_s above 0"), "a wither lasts")
	assert_true(errs.contains("rec.plates[4]: a wither plate must be breakable"), "a wither plate breaks")
	assert_eq(PlateRules.errors(REC, "rec").size(), 0, "the good record passes")
	var warden := GameData.get_record("enemy.rootwarden")
	assert_eq(PlateRules.errors(warden, "warden").size(), 0, "the Rootwarden's record passes")
