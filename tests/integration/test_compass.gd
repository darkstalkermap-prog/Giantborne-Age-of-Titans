extends IntegrationSuite
## P27 (plan M6-M9 §2.14, §3.10 design 3): the compass's marks (HudCompass.markers_for, pure) on the
## stub level of tests/support/world_ux_fixtures.gd: bearings in the four quadrants for two headings,
## the cap of six nearest known POIs within 600 m, the "?" of undiscovered places (250 m, 1,000 m for a
## skyline landmark), the pin, the tracked objective's diamonds - three for a multi-marker stage, held
## at the strip's ends when behind - and at most three leads; and the live widget: hidden without a
## world index, shown on a level with one.

const Fx := preload("res://tests/support/world_ux_fixtures.gd")
const NO_PIN := Vector2.INF


static func _kinds(marks: Array, kind: String) -> Array:
	return marks.filter(func(m: Dictionary) -> bool: return str(m.kind) == kind)


func test_bearings_in_the_four_quadrants() -> void:
	assert_near(HudCompass.heading_of(0.0), 0.0, 0.01, "yaw 0 faces north")
	assert_near(HudCompass.heading_of(-PI / 2.0), 90.0, 0.01, "yaw -90 degrees faces east")
	assert_near(HudCompass.heading_of(PI), 180.0, 0.01, "yaw 180 faces south")
	var o := Vector3.ZERO
	var targets := {"ne": Vector3(100, 0, -100), "se": Vector3(100, 0, 100), "sw": Vector3(-100, 0, 100),
		"nw": Vector3(-100, 0, -100)}
	var bearings := {"ne": 45.0, "se": 135.0, "sw": 225.0, "nw": 315.0}
	for q: String in targets:
		assert_near(HudCompass.bearing_of(o, targets[q]), bearings[q], 0.01, "%s lies at %d degrees" % [q, bearings[q]])
	# heading north: NE right of centre, NW left, the southern two behind (held objectives at the ends)
	var objs: Array = [targets.ne, targets.se, targets.sw, targets.nw]
	var marks := HudCompass.markers_for(o, 0.0, {}, {}, objs, [], NO_PIN)
	var xs: Array = []
	for m: Dictionary in marks:
		xs.append([roundi(float(m.x)), bool(m.held)])
	var half := HudCompass.HALF_WIDTH
	assert_eq(xs, [[roundi(half * 0.5), false], [roundi(HudCompass.EDGE_PX), true], [-roundi(HudCompass.EDGE_PX), true],
		[-roundi(half * 0.5), false]], "facing north: NE at +45 degrees, NW at -45, SE and SW held at the ends")
	# heading east: NE at -45 (left), SE at +45 (right), NW behind on the left
	marks = HudCompass.markers_for(o, 90.0, {}, {}, objs, [], NO_PIN)
	assert_near(float(marks[0].offset), -45.0, 0.01, "facing east the NE mark is 45 degrees left")
	assert_near(float(marks[1].offset), 45.0, 0.01, "and the SE mark 45 degrees right")
	assert_true(bool(marks[3].held) and float(marks[3].x) < 0.0, "NW (behind, to the left) is held at the left end")
	assert_eq(HudCompass.cardinal(90.0), "E", "the cardinal of 90 degrees")


func test_the_poi_cap_the_unknowns_and_the_pin() -> void:
	var pois := {}
	for i in 9:
		var a := deg_to_rad(10.0 * i - 40.0)
		pois["poi.p%d" % i] = {"position": Vector3(sin(a), 0, -cos(a)) * (100.0 + 50.0 * i), "kind": "ruin",
			"compass": true, "skyline": false}
	pois["poi.secret"] = {"position": Vector3(0, 0, -50), "kind": "secret", "compass": false, "skyline": false}
	pois["poi.near_unknown"] = {"position": Vector3(10, 0, -200), "kind": "camp", "compass": true, "skyline": false}
	pois["poi.mid_unknown"] = {"position": Vector3(10, 0, -400), "kind": "camp", "compass": true, "skyline": false}
	pois["poi.sky_unknown"] = {"position": Vector3(-10, 0, -900), "kind": "landmark", "compass": true, "skyline": true}
	pois["poi.sky_too_far"] = {"position": Vector3(-10, 0, -1100), "kind": "landmark", "compass": true, "skyline": true}
	var flags := {}
	for i in 9:
		flags["discovered.p%d" % i] = true if i % 2 == 0 else Discovery.REVEALED
	flags["discovered.secret"] = true
	var marks := HudCompass.markers_for(Vector3.ZERO, 0.0, pois, flags, [], [], NO_PIN)
	var known := _kinds(marks, "poi")
	var ids: Array = known.map(func(m: Dictionary) -> String: return str(m.id))
	ids.sort()
	assert_eq(ids, ["poi.p0", "poi.p1", "poi.p2", "poi.p3", "poi.p4", "poi.p5"],
		"the six nearest known POIs (found or revealed) within 600 m; p6-p8 (400-500 m) are left out by the cap")
	for m: Dictionary in known:
		assert_true(float(m.distance) <= HudCompass.RADIUS_M, "%s is within 600 m" % m.id)
	assert_true(_kinds(marks, "poi").filter(func(m: Dictionary) -> bool: return m.id == "poi.secret").is_empty(),
		"a sealed place never shows (compass: false)")
	var unknown_ids: Array = _kinds(marks, "unknown").map(func(m: Dictionary) -> String: return str(m.id))
	unknown_ids.sort()
	assert_eq(unknown_ids, ["poi.near_unknown", "poi.sky_unknown"],
		"? for an undiscovered place within 250 m and a skyline landmark within 1,000 m only")
	marks = HudCompass.markers_for(Vector3.ZERO, 0.0, pois, flags, [], [], Vector2(0, 2000))
	assert_eq(_kinds(marks, "pin").size(), 0, "a pin behind the giant is off the strip")
	marks = HudCompass.markers_for(Vector3.ZERO, 180.0, pois, flags, [], [], Vector2(0, 2000))
	var pin := _kinds(marks, "pin")
	assert_eq(pin.size(), 1, "the pin shows at any distance (2 km)")
	if not pin.is_empty():
		assert_near(float(pin[0].x), 0.0, 0.01, "facing south it is dead ahead")


func test_three_diamonds_for_a_multi_marker_stage_and_the_leads() -> void:
	var objective := {"position": Vector3(0, 0, -50), "positions": [Vector3(0, 0, -50), Vector3(60, 0, -60),
		Vector3(-60, 0, -60)]}
	var points := HudCompass.objective_positions(objective)
	assert_eq(points.size(), 3, "every marker of the stage")
	var marks := HudCompass.markers_for(Vector3.ZERO, 0.0, {}, {}, points, [], NO_PIN)
	assert_eq(_kinds(marks, "objective").size(), 3, "three diamonds")
	assert_eq(HudCompass.objective_positions({"position": Vector3(5, 0, 5)}), [Vector3(5, 0, 5)],
		"a one-marker stage: its position")
	var leads: Array = []
	for i in 5:
		leads.append({"marker_id": "lead_%d" % i, "position": Vector3(10.0 * i, 0, -100)})
	marks = HudCompass.markers_for(Vector3.ZERO, 0.0, {}, {}, [], leads, NO_PIN)
	assert_eq(_kinds(marks, "lead").size(), 3, "at most three leads")


func test_the_live_compass_follows_the_level_index() -> void:
	var p := spawn_player(Vector3(0, 0.05, 140), 0.0)
	var layer := CanvasLayer.new()
	world.add_child(layer)
	var hud := Hud.new()
	layer.add_child(hud)
	await get_tree().process_frame
	var c := hud.get_node_or_null("Compass")
	assert_true(c is HudCompass, "the HUD made the compass from the registry")
	assert_eq(c.call("visible_text"), "", "hidden where there is no world index (the sandbox)")
	Fx.install()
	GameSession.level_id = Fx.LEVEL
	GameSession.mode = GameSession.Mode.VALLEY
	WorldState.set_flag("discovered.test_p27_vista", true)
	WorldState.set_flag(Discovery.PIN_FLAG, [0.0, -150.0, Fx.LEVEL])
	p.camera_rig.yaw = 0.0
	await get_tree().process_frame
	await get_tree().process_frame
	var marks: Array = c.call("markers_now")
	assert_true(str(c.call("visible_text")).begins_with("N 0"), "shown on a level with an index, facing north (%s)" % c.call("visible_text"))
	assert_eq(_kinds(marks, "pin").size(), 1, "the pin ahead")
	assert_eq(_kinds(marks, "poi").map(func(m: Dictionary) -> String: return str(m.id)), ["poi.test_p27_vista"],
		"the known vista within 600 m")
	var unknown: Array = _kinds(marks, "unknown").map(func(m: Dictionary) -> String: return str(m.id))
	unknown.sort()
	assert_eq(unknown, ["poi.test_p27_far", "poi.test_p27_ruin", "poi.test_p27_shrine", "poi.test_p27_town"],
		"? for the town (240 m), the ruin (205 m) and the shrine (215 m), and the far landmark on the skyline (367 m); not the 260 m ruin, nor the sealed place")
	GameSession.mode = GameSession.Mode.SANDBOX


## P39f (FOLLOWUPS, "From the M8 screenshot pass": "compass markers draw over its direction letters" - a red pin
## on the N of "NE", "?" on "NW" and "E"): the strip has a row of marks above a row of letters, so no mark of any
## kind covers any letter wherever both stand - here every kind exactly on every letter's bearing - and both rows
## lie inside the strip's height. Live: a POI due north of the giant, the pin due north-east and undiscovered places
## round it, facing north: each mark is drawn at its letter's x, on the marks' row.
func test_marks_never_cover_the_letters() -> void:
	var layer := CanvasLayer.new()
	world.add_child(layer)
	var hud := Hud.new()
	layer.add_child(hud)
	await get_tree().process_frame
	var font := hud.get_theme_font("font", "Label")
	var bad := PackedStringArray()
	var letters := ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
	for heading in range(0, 360, 5):
		for k in 8:
			var x := HudCompass.x_of(HudCompass.offset_deg(k * 45.0, float(heading)))
			if not is_finite(x):
				continue
			var cx := HudCompass.HALF_WIDTH + x
			var lr := HudCompass.letter_rect(letters[k], cx, font)
			if lr.position.y < 0.0 or lr.end.y > HudCompass.HEIGHT:
				bad.append("%s at heading %d leaves the strip: %s" % [letters[k], heading, lr])
			for kind: String in ["objective", "lead", "poi", "pin", "unknown"]:
				var mr := HudCompass.mark_rect(kind, cx)
				if mr.intersects(lr):
					bad.append("a %s mark covers %s at heading %d" % [kind, letters[k], heading])
				if mr.position.y < 0.0 or mr.end.y > HudCompass.HEIGHT:
					bad.append("a %s mark leaves the strip: %s" % [kind, mr])
	assert_eq(bad, PackedStringArray(), "no mark covers a letter, and all of them lie on the strip")
	var lowest := 0.0
	for kind: String in ["objective", "lead", "poi", "pin", "unknown"]:
		lowest = maxf(lowest, HudCompass.mark_rect(kind, 0.0).end.y)
	assert_true(lowest <= HudCompass.letter_rect("N", 0.0, font).position.y,
		"the marks' row ends (%.0f px) above the letters' (%.0f px)" % [lowest, HudCompass.letter_rect("N", 0.0, font).position.y])
	# live: marks exactly on the N and NE letters
	var p := spawn_player(Vector3(0, 0.05, 140), 0.0)
	Fx.install()
	GameSession.level_id = Fx.LEVEL
	GameSession.mode = GameSession.Mode.VALLEY
	WorldState.set_flag("discovered.test_p27_town", true)                    # (0, -100): due north of (0, 140)
	WorldState.set_flag(Discovery.PIN_FLAG, [240.0, -100.0, Fx.LEVEL])      # due north-east
	p.camera_rig.yaw = 0.0
	await get_tree().process_frame
	await get_tree().process_frame
	var c := hud.get_node("Compass")
	var marks: Array = c.call("markers_now")
	var town := marks.filter(func(m: Dictionary) -> bool: return str(m.id) == "poi.test_p27_town")
	var pin := marks.filter(func(m: Dictionary) -> bool: return str(m.kind) == "pin")
	assert_true(town.size() == 1 and absf(float(town[0].x)) < 0.5, "the town sits on the N (%s)" % str(town))
	assert_true(pin.size() == 1 and absf(float(pin[0].offset) - 45.0) < 0.5, "the pin on the NE (%s)" % str(pin))
	bad.clear()
	for m: Dictionary in marks:
		var cx := HudCompass.HALF_WIDTH + float(m.x)
		for k in 8:
			var x := HudCompass.x_of(HudCompass.offset_deg(k * 45.0, 0.0))
			if is_finite(x) and HudCompass.mark_rect(str(m.kind), cx).intersects(
					HudCompass.letter_rect(letters[k], HudCompass.HALF_WIDTH + x, font)):
				bad.append("%s %s covers %s" % [m.kind, m.id, letters[k]])
	assert_eq(bad, PackedStringArray(), "live: no mark covers a letter")
	GameSession.mode = GameSession.Mode.SANDBOX
