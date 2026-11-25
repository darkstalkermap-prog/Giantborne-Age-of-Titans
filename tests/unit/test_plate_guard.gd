extends TestSuite
## C2: a titan's guard (PlateRules.parse_guard / guard_catches / guard_fill, PlateSet.catches / absorb / guard_step,
## pure): a blow from an attacker inside the guard's arc (turned yaw_deg to his left), struck no higher than its top,
## lands on the shield plate whatever region it touched - the shield's reduction keeps it from him, its stone takes it,
## its poise fills the meter (a Heavy's x heavy_mult, a light's x light_mult, an ability's x ability_mult); full, the
## guard breaks and the meter empties; the meter drains after regen_delay_s; a blow from behind, over the shield's top
## or while the guard is down lands where it struck; "disarm" is a break effect; the record checks.

const REC := {"height_m": 22.4, "plates": [
	{"id": "shield", "region": "shield", "health": 1000, "reduction": 0.9, "poise_reduction": 1.0, "weak_multiplier": 1.0,
		"on_break": {"effect": "disarm"},
		"guard": {"arc_deg": 150.0, "yaw_deg": 30.0, "top_m": 17.0, "meter": 100.0, "heavy_mult": 2.0, "light_mult": 0.5,
			"ability_mult": 1.0, "open_s": 5.0, "stagger_s": 3.0, "regen_per_s": 10.0, "regen_delay_s": 2.0}},
	{"id": "greave_l", "region": "shin_l", "health": 500, "reduction": 0.7, "weak_multiplier": 1.4},
	{"id": "back", "region": "back", "health": 500, "reduction": 0.85, "weak_multiplier": 2.6},
]}


func _plates() -> PlateSet:
	var s := PlateSet.from_record(REC)
	s.guard_up = true
	s.guard_origin = Vector3.ZERO
	s.guard_forward = Vector3(0, 0, -1)   # (he faces -Z; his left is -X)
	return s


## A blow from `from` landing at `at` on region `region` (poise 40, a Heavy when `heavy`).
func _hit(from: Vector3, at: Vector3, region: String, heavy := true) -> HitEvent:
	var h := HitEvent.new()
	h.attacker_position = from
	h.hit_point = at
	h.region = region
	h.poise_damage = 40.0
	h.attacker_height_m = 22.4   # (the titan's own height: the poise scale 1)
	h.tags = PackedStringArray(["Melee", "BasicAttack", "Heavy"] if heavy else ["Melee", "BasicAttack", "Light"])
	h.tick = 100
	return h


func _result(h: HitEvent, raw := 100.0) -> HitResult:
	var r := HitResult.new()
	r.event = h
	r.outcome = HitResult.Outcome.HIT
	r.raw_damage = raw
	return r


func test_parse_guard_and_its_defaults() -> void:
	var ps := PlateRules.parse(REC)
	assert_near(float(ps[0].guard.meter), 100.0, 1e-6, "its own meter")
	assert_near(float(ps[0].guard.yaw_deg), 30.0, 1e-6, "turned to his left")
	assert_true((ps[1].guard as Dictionary).is_empty(), "a greave is no shield")
	var d := PlateRules.parse_guard({"meter": 50.0})
	assert_near(float(d.arc_deg), float(PlateRules.GUARD_DEFAULTS.arc_deg), 1e-6, "the defaults fill the rest")
	assert_near(float(PlateRules.parse_guard({"meter": 0.0}).meter), 1.0, 1e-6, "never a meter of nothing")
	assert_true(PlateRules.parse_guard(null).is_empty(), "absent: no guard")
	assert_eq(str(ps[0].effect), PlateRules.EFFECT_DISARM, "the shield's break disarms")
	assert_true(PlateRules.ON_BREAK_EFFECTS.has(PlateRules.EFFECT_DISARM), "a known effect")


func test_guard_catches_by_arc_side_and_height() -> void:
	var g := PlateRules.parse_guard((REC.plates[0] as Dictionary).guard)
	var f := Vector3(0, 0, -1)
	assert_true(PlateRules.guard_catches(g, Vector3.ZERO, f, Vector3(0, 0, -10), Vector3(0, 5, -3)), "straight before him")
	assert_true(PlateRules.guard_catches(g, Vector3.ZERO, f, Vector3(-10, 0, 0), Vector3(-3, 5, 0)),
		"his left side (the shield's side: the arc is turned toward it)")
	assert_true(PlateRules.guard_catches(g, Vector3.ZERO, f, Vector3(5, 0, -10), Vector3(1, 5, -3)),
		"his right-front within the arc's edge (45 degrees right)")
	assert_false(PlateRules.guard_catches(g, Vector3.ZERO, f, Vector3(10, 0, -2), Vector3(3, 5, 0)),
		"his right side: outside the arc (his broken side)")
	assert_false(PlateRules.guard_catches(g, Vector3.ZERO, f, Vector3(0, 0, 10), Vector3(0, 5, 3)), "behind him")
	assert_false(PlateRules.guard_catches(g, Vector3.ZERO, f, Vector3(0, 0, -10), Vector3(0, 18, -3)),
		"over the shield's top (a taller giant's blow at his helm)")
	assert_true(PlateRules.guard_catches(g, Vector3.ZERO, f, Vector3(0, 0, -10), Vector3.ZERO), "no point known: caught")
	assert_false(PlateRules.guard_catches({}, Vector3.ZERO, f, Vector3(0, 0, -10), Vector3.ZERO), "no guard")


func test_guard_fill_by_the_blows_kind() -> void:
	var g := PlateRules.parse_guard((REC.plates[0] as Dictionary).guard)
	assert_near(PlateRules.guard_fill(g, 40.0, PackedStringArray(["BasicAttack", "Heavy"])), 80.0, 1e-6, "a heavy x2")
	assert_near(PlateRules.guard_fill(g, 40.0, PackedStringArray(["BasicAttack", "Light"])), 20.0, 1e-6, "a light x0.5")
	assert_near(PlateRules.guard_fill(g, 40.0, PackedStringArray(["AoE"])), 40.0, 1e-6, "an ability x1")
	assert_near(PlateRules.guard_fill(g, 0.0, PackedStringArray(["Heavy"])), 0.0, 1e-6, "no poise: nothing")


func test_a_caught_blow_lands_on_the_shield_and_fills_the_meter() -> void:
	var s := _plates()
	var h := _hit(Vector3(0, 0, -12), Vector3(-1, 4, -2), "shin_l")
	s.prepare(h)
	assert_true(h.guarded, "the guard caught it")
	assert_eq(h.region, "shield", "it landed on the shield")
	assert_eq(h.plate_id, "shield", "the shield's plate")
	assert_eq(h.plate_state, PlateRules.STATE_ARMOURED, "armoured")
	assert_near(h.region_damage_mult, 0.1, 1e-6, "the shield keeps 90 % from him")
	assert_near(h.region_poise_mult, 0.0, 1e-6, "and all of its poise")
	var out := s.absorb(_result(h))
	assert_true(bool(out.get("guarded", false)), "reported as guarded")
	assert_near(float(out.meter), 0.8, 1e-6, "a heavy fills 80 of 100")
	assert_near(float(out.stone), 150.0, 1e-6, "its stone takes the heavy's raw damage x1.5")
	assert_false(bool(out.get("guard_broken", false)), "not yet broken")
	var h2 := _hit(Vector3(-3, 0, -12), Vector3(-2, 6, -2), "torso")
	s.prepare(h2)
	var out2 := s.absorb(_result(h2))
	assert_true(bool(out2.get("guard_broken", false)), "the second heavy breaks it")
	assert_near(s.guard_meter, 0.0, 1e-6, "the meter empties")
	assert_eq(s.guard_breaks, 1, "one break")
	assert_eq(s.guarded_hits, 2, "two caught blows")


func test_blows_the_guard_does_not_catch() -> void:
	var s := _plates()
	var back := _hit(Vector3(0, 0, 12), Vector3(0, 15, 2), "back")
	s.prepare(back)
	assert_false(back.guarded, "from behind")
	assert_eq(back.plate_id, "back", "his back plate")
	var right := _hit(Vector3(12, 0, -1), Vector3(2, 4, -1), "shin_l")
	s.prepare(right)
	assert_false(right.guarded, "from his right")
	s.guard_up = false
	var front := _hit(Vector3(0, 0, -12), Vector3(0, 4, -2), "shin_l")
	s.prepare(front)
	assert_false(front.guarded, "his guard down (his bar's recovery, a stagger)")
	assert_eq(front.plate_id, "greave_l", "the greave it struck")
	s.guard_up = true
	s.force_break("shield")
	var after := _hit(Vector3(0, 0, -12), Vector3(0, 4, -2), "shin_l")
	s.prepare(after)
	assert_false(after.guarded, "the shield broken: no guard")


func test_the_meter_drains_after_its_delay_and_a_new_attempt_clears_it() -> void:
	var s := _plates()
	var h := _hit(Vector3(0, 0, -12), Vector3(0, 4, -2), "shin_l", false)
	s.prepare(h)
	s.absorb(_result(h))
	assert_near(s.guard_meter, 20.0, 1e-6, "a light fills 20")
	for t in range(100, 100 + 119):
		s.guard_step(t)
	assert_near(s.guard_meter, 20.0, 1e-6, "no drain inside regen_delay_s")
	for t in range(219, 219 + 60):
		s.guard_step(t)
	assert_true(s.guard_meter < 20.0 - 9.0 and s.guard_meter > 0.0, "about 10 a second after it (%.2f)" % s.guard_meter)
	s.reset()
	assert_near(s.guard_meter, 0.0, 1e-6, "a new attempt: empty")
	assert_eq(s.guard_breaks, 0, "and no breaks")


func test_unbalance_fills_the_meter_faster() -> void:
	var s := _plates()
	s.poise_taken_mult = 1.5
	var h := _hit(Vector3(0, 0, -12), Vector3(0, 4, -2), "shin_l", false)
	s.prepare(h)
	s.absorb(_result(h))
	assert_near(s.guard_meter, 30.0, 1e-6, "a light x1.5 (his broken side's iron gone)")


func test_the_record_checks() -> void:
	assert_eq(PlateRules.errors(REC, "t").size(), 0, "a good record")
	var two := REC.duplicate(true)
	(two.plates as Array).append({"id": "shield2", "region": "shield2", "health": 10, "reduction": 0.5,
		"guard": {"meter": 10.0}})
	assert_true(Array(PlateRules.errors(two, "t")).any(func(e: String) -> bool: return e.contains("one guard")),
		"at most one guard plate")
	var unb := {"plates": [{"id": "s", "region": "s", "breakable": false, "reduction": 0.5, "guard": {"meter": 10.0}}]}
	assert_true(Array(PlateRules.errors(unb, "t")).any(func(e: String) -> bool: return e.contains("guard plate must")),
		"a guard plate must be breakable")
	var key := {"plates": [{"id": "s", "region": "s", "health": 10, "reduction": 0.5, "guard": {"metre": 10.0}}]}
	assert_true(Array(PlateRules.errors(key, "t")).any(func(e: String) -> bool: return e.contains("unknown key")),
		"an unknown guard key")
	var dis := {"plates": [{"id": "s", "region": "s", "breakable": false, "reduction": 0.5,
		"on_break": {"effect": "disarm"}}]}
	assert_true(Array(PlateRules.errors(dis, "t")).any(func(e: String) -> bool: return e.contains("disarm plate")),
		"a disarm plate must be breakable")
	var eff := {"plates": [{"id": "s", "region": "s", "health": 10, "reduction": 0.5, "on_break": {"effect": "explode"}}]}
	assert_true(Array(PlateRules.errors(eff, "t")).any(func(e: String) -> bool: return e.contains("unknown effect")),
		"an unknown break effect")
