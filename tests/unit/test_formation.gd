extends TestSuite
## P30 (plan M6-M9 §2.10, §3.13 tests, decision 19): the Formation's geometry and its data rules,
## without actors. The slot grid (rank-major from the front rank's left file, the banner one rank
## behind) around the pivot at any facing; the facing turn limited by turn_deg_s; the front band
## (the brace's rectangle) and in_front(); the lock texts; fan-out rout points (spread over the fan,
## alternating near and far, away from the threat) and the named flee points in turn; the web's
## compositions (front rank and banner first); and the encounter checks - FormationRules.record_errors
## (ids, slots, banners, stage ranges) and cross_record_errors (banner roles, the caps of every
## 150 m cluster on both platforms) - on hand-made records and on the shipped test records.


func _grid(ranks := 2, files := 5, rs := 1.6, fs := 1.4) -> Formation:
	var f := Formation.new()
	f.ranks = ranks
	f.files = files
	f.rank_spacing_m = rs
	f.file_spacing_m = fs
	f.display_name = "Pike Regiment"
	return f


func test_the_slot_grid_is_rank_major_from_the_front_left_and_the_banner_stands_behind() -> void:
	var f := _grid()
	f.place(Vector3(10, 0, 20), 0.0)   # facing -Z
	assert_eq(f.slot_count(), 10, "2 x 5 slots")
	# slot 0: front rank (forward = -Z, z = -0.8), left file seen from behind (x = -2.8)
	var s0 := f.slot_position(0)
	assert_near(s0.x, 10.0 - 2.8, 1e-4, "slot 0 is the left file")
	assert_near(s0.z, 20.0 - 0.8, 1e-4, "slot 0 is in the front rank")
	var s4 := f.slot_position(4)
	assert_near(s4.x, 10.0 + 2.8, 1e-4, "slot 4 is the front rank's right file")
	var s5 := f.slot_position(5)
	assert_near(s5.z, 20.0 + 0.8, 1e-4, "slot 5 opens the second rank, behind")
	assert_near(s5.x, s0.x, 1e-4, "on the left file")
	var b := f.slot_position(Formation.BANNER_SLOT)
	assert_near(b.x, 10.0, 1e-4, "the banner is centred")
	assert_near(b.z, 20.0 + 0.8 + 1.6, 1e-4, "one rank behind the last rank")
	assert_near(f.front_center().z, 19.2, 1e-4, "the front rank's centre")
	assert_near(f.anchor().y, Formation.CHEST_HEIGHT_M, 1e-4, "the lock point at chest height")
	assert_near(f.half_width(), 2.8 + 0.7, 1e-4, "half the rank out to the outer shoulders")


func test_the_grid_turns_with_the_facing() -> void:
	var f := _grid()
	f.place(Vector3.ZERO, PI)   # facing +Z
	var s0 := f.slot_position(0)
	assert_near(s0.z, 0.8, 1e-4, "the front rank is toward +Z")
	assert_near(s0.x, 2.8, 1e-4, "its left file is on +X seen from behind")
	f.place(Vector3.ZERO, PI * 0.5)   # facing -X
	assert_near(f.front_center().x, -0.8, 1e-4, "facing -X: the front rank is toward -X")
	assert_near(Formation.forward_of(PI * 0.5).x, -1.0, 1e-5, "forward of a quarter turn")
	assert_near(Formation.right_of(0.0).x, 1.0, 1e-5, "right of no turn is +X")


func test_the_facing_turns_at_most_turn_deg_s() -> void:
	var step := deg_to_rad(40.0) * 0.1
	var y := Formation.turn_toward(0.0, PI * 0.5, step)
	assert_near(y, step, 1e-6, "a big turn is limited to one step")
	assert_near(Formation.turn_toward(0.0, 0.01, step), 0.01, 1e-6, "a small one is taken whole")
	# across the -PI / PI seam it turns the short way
	var across := Formation.turn_toward(PI - 0.01, -PI + 0.01, 1.0)
	assert_near(absf(wrapf(across - (-PI + 0.01), -PI, PI)), 0.0, 1e-5, "the short way across the seam")


func test_the_front_band_lies_along_the_front_rank() -> void:
	var f := _grid()
	f.brace_m = 7.0
	f.place(Vector3.ZERO, 0.0)
	var band := f.front_band()
	assert_near(float(band.depth), 7.0, 1e-4, "without an action the band reaches brace_m")
	assert_near((band.near as Vector3).z, -0.8, 1e-4, "it starts at the front rank")
	assert_near((band.center as Vector3).z, -0.8 - 3.5, 1e-4, "its centre is half its depth ahead")
	assert_near(float(band.half_width), f.half_width(), 1e-4, "as wide as the rank")
	f.brace_action = "ability.formation_brace_pike"
	assert_near(f.band_depth(), GameData.get_action("ability.formation_brace_pike").radius_m, 1e-4,
		"with an action it reaches the action's radius")
	assert_true(f.in_front(Vector3(0, 0, -5), 7.0), "a point ahead of the rank is in front")
	assert_false(f.in_front(Vector3(0, 0, 3), 7.0), "a point behind is not")
	assert_false(f.in_front(Vector3(8, 0, -4), 7.0), "nor one beside the rank")
	assert_true(f.in_front(Vector3(4.0, 0, -4), 7.0, 1.0), "unless within the margin")
	assert_near(f.front_gap(Vector3(0, 0, -5.8)), 5.0, 1e-4, "the gap in front of the rank")


func test_lock_texts() -> void:
	var f := _grid()
	assert_eq(f.lock_label(), "Pike Regiment (0)", "the group's line counts the living")
	f.banner_name = "Banner of the Toll-Riders"
	assert_eq(f.banner_label(), "⚑ Banner of the Toll-Riders", "the banner's line has the flag")
	f.banner_name = ""
	assert_eq(f.banner_label(), "⚑ Banner", "an unnamed banner")
	var rec := {"id": "pikes", "kind": "shield"}
	var g := Formation.from_record("encounter.crownmarch_toll_fort", rec)
	assert_eq(g.id, "crownmarch_toll_fort.pikes", "the id is the encounter's short id and the entry's")
	assert_eq(g.display_name, "Shield Wall", "named by its kind when the record names none")


func test_routs_fan_out_away_from_the_threat_or_over_the_flee_points() -> void:
	var from := Vector3(0, 0, 0)
	var threat := Vector3(0, 0, 20)   # the giant south: flee north (-Z)
	var seen := {}
	for i in Formation.FAN_POINTS:
		var p := Formation.fan_point(from, threat, i)
		var d := Vector2(p.x, p.z).length()
		assert_true(d >= Formation.FAN_MIN_M - 0.01 and d <= Formation.FAN_MAX_M + 0.01, "point %d is 30-60 m away" % i)
		assert_true(p.z < 0.0, "point %d lies away from the threat" % i)
		var ang := rad_to_deg(absf(atan2(p.x, -p.z)))
		assert_true(ang <= Formation.FAN_DEG * 0.5 + 0.5, "point %d is inside the 140-degree fan" % i)
		seen[Vector2i(roundi(p.x), roundi(p.z))] = true
	assert_eq(seen.size(), Formation.FAN_POINTS, "five different points")
	assert_true(Vector2(Formation.fan_point(from, threat, 0).x, Formation.fan_point(from, threat, 0).z).length()
		< Vector2(Formation.fan_point(from, threat, 1).x, Formation.fan_point(from, threat, 1).z).length(),
		"neighbours alternate near and far")
	var f := _grid()
	f.flee_points = [Vector3(1, 0, -50), Vector3(2, 0, -50)] as Array[Vector3]
	assert_eq(f.rout_point(from, threat, 0), Vector3(1, 0, -50), "the first flee point")
	assert_eq(f.rout_point(from, threat, 3), Vector3(2, 0, -50), "in turn")


func test_web_compositions_keep_the_banner_and_the_front_rank_first() -> void:
	var slots := [9, 3, 0, 1, 2, 4, 5, 6, 7, 8, Formation.BANNER_SLOT]
	var kept := Formation.web_kept_slots(slots, 0.5)
	assert_eq(kept, [Formation.BANNER_SLOT, 0, 1, 2, 3, 4], "the banner and the front rank of five")
	assert_eq(Formation.web_kept_slots([0, 1, 2], 0.1), [0], "at least one member")
	assert_eq(Formation.web_kept_slots([0, 1, 2, Formation.BANNER_SLOT], 1.0).size(), 4, "a scale of 1 keeps all")
	# the shipped stress case fits the web's 20 at its 0.45
	var stress := GameData.get_record("encounter.formation_test_stress")
	var counts := FormationRules.member_counts(stress, 4)
	assert_eq(int(counts[0]), 40, "the stress case is 40 members on the desktop")
	assert_eq(int(counts[1]), 20, "and 20 on the web (0.45 of each regiment, banners kept)")


func _enc(formations: Array, spawns: Array) -> Dictionary:
	return {"id": "encounter.t", "type": "encounter", "level": "level.t", "center_m": [0, 0, 0],
		"formations": formations, "spawns": spawns}


func _spawn(id: String, formation: String, slot: int, def := "enemy.pikeman", pos := [0, 0, 0]) -> Dictionary:
	return {"entity_id": id, "definition": def, "position_m": pos, "formation": formation, "slot": slot}


func test_record_errors_catch_bad_formations() -> void:
	var good := _enc([{"id": "pikes", "kind": "pike", "ranks": 1, "files": 2, "banner": "b",
		"brace_m": 6, "brace_action": "ability.formation_brace_pike"}],
		[_spawn("a", "pikes", 0), _spawn("c", "pikes", 1), _spawn("b", "pikes", -1, "enemy.bannerman")])
	assert_eq(FormationRules.record_errors(good, "t").size(), 0, "a good formation passes")
	var cases := {
		"a duplicate id": _enc([{"id": "p", "ranks": 1, "files": 1}, {"id": "p", "ranks": 1, "files": 1}],
			[_spawn("a", "p", 0)]),
		"a capitalised id": _enc([{"id": "Pikes", "ranks": 1, "files": 1}], [_spawn("a", "Pikes", 0)]),
		"a slot outside the grid": _enc([{"id": "p", "ranks": 1, "files": 2}], [_spawn("a", "p", 2)]),
		"a shared slot": _enc([{"id": "p", "ranks": 1, "files": 2}], [_spawn("a", "p", 0), _spawn("c", "p", 0)]),
		"an unknown formation": _enc([{"id": "p", "ranks": 1, "files": 2}], [_spawn("a", "p", 0), _spawn("c", "q", 0)]),
		"a member without a slot": _enc([{"id": "p", "ranks": 1, "files": 2}], [_spawn("a", "p", 0),
			{"entity_id": "c", "definition": "enemy.pikeman", "formation": "p"}]),
		"a slot without a formation": _enc([{"id": "p", "ranks": 1, "files": 2}], [_spawn("a", "p", 0),
			{"entity_id": "c", "definition": "enemy.pikeman", "slot": 1}]),
		"two banners": _enc([{"id": "p", "ranks": 1, "files": 2, "banner": "b"}], [_spawn("a", "p", 0),
			_spawn("b", "p", -1, "enemy.bannerman"), _spawn("c", "p", -1, "enemy.bannerman")]),
		"a banner the formation does not name": _enc([{"id": "p", "ranks": 1, "files": 2}], [_spawn("a", "p", 0),
			_spawn("b", "p", -1, "enemy.bannerman")]),
		"a named banner that is not its slot -1": _enc([{"id": "p", "ranks": 1, "files": 2, "banner": "x"}],
			[_spawn("a", "p", 0)]),
		"no member": _enc([{"id": "p", "ranks": 1, "files": 2}], []),
		"an empty stage range": _enc([{"id": "p", "ranks": 1, "files": 2, "min_stage": 5, "max_stage": 4}],
			[_spawn("a", "p", 0)]),
		"a brace action without brace_m": _enc([{"id": "p", "ranks": 1, "files": 2,
			"brace_action": "ability.formation_brace_pike"}], [_spawn("a", "p", 0)]),
	}
	for what: String in cases:
		assert_true(FormationRules.record_errors(cases[what], "t").size() > 0, "%s is an error" % what)


func test_cross_record_errors_check_banner_roles_and_the_caps_of_every_cluster() -> void:
	var records := {
		"enemy.pikeman": {"id": "enemy.pikeman", "type": "enemy", "role": "pike"},
		"enemy.bannerman": {"id": "enemy.bannerman", "type": "enemy", "role": "banner"},
		"level.t": {"id": "level.t", "type": "level"},
	}
	var spawns: Array = []
	for i in 30:
		spawns.append(_spawn("m%d" % i, "big", i))
	var big := _enc([{"id": "big", "kind": "pike", "ranks": 3, "files": 10}], spawns)
	big["id"] = "encounter.big"
	records["encounter.big"] = big
	var errors := FormationRules.cross_record_errors(records)
	assert_eq(errors.size(), 6, "30 members fit the desktop's 40 but not the web's 20, at every stage (%s)" % [errors])
	big["web_formation_scale"] = 0.6
	assert_eq(FormationRules.cross_record_errors(records).size(), 0, "a web scale of 0.6 keeps 18")
	# a second encounter 100 m away joins the cluster: 30 + 15 = 45 on the desktop
	var spawns2: Array = []
	for i in 15:
		spawns2.append(_spawn("n%d" % i, "small", i))
	var small := _enc([{"id": "small", "kind": "line", "ranks": 3, "files": 5, "min_stage": 4}], spawns2)
	small["id"] = "encounter.small"
	small["center_m"] = [100, 0, 0]
	small["web_formation_scale"] = 0.1
	records["encounter.small"] = small
	errors = FormationRules.cross_record_errors(records)
	var desktop_over := 0
	for e in errors:
		if e.contains("max_formation_members 40"):
			desktop_over += 1
	assert_eq(desktop_over, 6, "both encounters see 45 at stages 4-6 (%s)" % [errors])
	# W23 (P39f; FOLLOWUPS "From P37"): a template drawn up 100 m away is a cluster of its own - its copies come
	# where the WanderDirector places them, within the live caps - but must still fit the caps by itself
	small["template"] = true
	assert_eq(FormationRules.cross_record_errors(records).size(), 0, "a template 100 m away joins no placed cluster")
	var lone: Array = []
	for i in 45:
		lone.append(_spawn("t%d" % i, "small", i))
	small["spawns"] = lone
	(small.formations[0] as Dictionary)["ranks"] = 5
	(small.formations[0] as Dictionary)["files"] = 9
	errors = FormationRules.cross_record_errors(records)
	desktop_over = 0
	for e in errors:
		if e.contains("max_formation_members 40"):
			desktop_over += 1
	assert_eq(desktop_over, 3, "a template of 45 alone is over the desktop's 40 at stages 4-6 (%s)" % [errors])
	small.erase("template")
	small["spawns"] = spawns2
	(small.formations[0] as Dictionary)["ranks"] = 3
	(small.formations[0] as Dictionary)["files"] = 5
	small["center_m"] = [160, 0, 0]
	assert_eq(FormationRules.cross_record_errors(records).size(), 0, "160 m away it is another cluster")
	# a banner of the wrong role, and a banner standing in a rank
	big.spawns.append(_spawn("flag", "big", -1, "enemy.pikeman"))
	(big.formations[0] as Dictionary)["banner"] = "flag"
	big.spawns.append(_spawn("flag2", "big", 29, "enemy.bannerman"))
	errors = FormationRules.cross_record_errors(records)
	var roles := 0
	for e in errors:
		if e.contains("role"):
			roles += 1
	assert_eq(roles, 2, "both role errors are reported (%s)" % [errors])


func test_the_shipped_formation_records_pass_their_checks() -> void:
	for id: String in ["encounter.formation_test_pikes", "encounter.formation_test_shields",
			"encounter.formation_test_rout", "encounter.formation_test_stress"]:
		var rec := GameData.get_record(id)
		assert_false(rec.is_empty(), "%s exists" % id)
		assert_eq(FormationRules.record_errors(rec, id).size(), 0, "%s's formations are well formed" % id)
	assert_eq(FormationRules.cross_record_errors(GameData.records, GameData.record_paths).size(), 0,
		"every shipped cluster fits the caps")
	for id: String in ["enemy.pikeman", "enemy.shieldman", "enemy.bannerman"]:
		assert_true(DataValidator.SOLDIER_ROLES.has(str(GameData.get_record(id).get("role", ""))), "%s has a soldier role" % id)
	for g: String in ["growth.stage_4", "growth.stage_5", "growth.stage_6"]:
		var rec := GameData.get_record(g)
		if rec.is_empty():
			continue
		assert_true(bool((rec.get("target_rules", {}) as Dictionary).get("formation_lock", false)),
			"%s folds formations into lock groups" % g)
