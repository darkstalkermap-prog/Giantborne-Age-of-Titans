extends TestSuite
## Tip matching (P42; plan M10 §2.9, decision 3): pure, from the weapon data and the landmarks. Every
## player weapon arc (the light chain and the heavy of each weapon's moveset at the stage) at stages 1, 3, 4
## and 6, every second ACTIVE sample as PlayerAttack sweeps it (the stage's arc tilt included): the visible
## weapon's outer half lies inside the tested capsule in 100 % of the samples, at most 15° off the tested
## direction (median at most 9°), the grip within the arm's reach and the two-bone solve exact (the palm
## within 0.01 m of the grip). A weapon carried past its fit stage (an unreforged club, sword or hammer at
## stage 4 or 6: PlayerEquipment.too_small_at) keeps its stage-2 length, and its tested capsule starts
## beyond the real hand's reach; for it the direction, the reach and the solve are checked and the
## capsule's miss is measured and printed (P42.md, deviation 4). idle_grip() is within reach for every
## weapon family. With the default
## landmarks (the animation research's lab body) here; over the exported landmarks of giant_model.tscn when it
## exists (the W25 merge runs that part; skipped with a note before P41 merges).

const STAGES := [1, 3, 4, 6]
const MODEL := "res://scenes/player/giant_model.tscn"
const MEDIAN_DEG := 9.0


## The weapons a player can wield at `stage` (a moveset of their own; the stage and permission gates of
## PlayerEquipment.can_equip).
static func player_weapons(stage: int, profile: Dictionary) -> Array:
	var out: Array = []
	for rec: Dictionary in GameData.records_of_type("weapon"):
		if str(rec.get("light_chain", "")) == "":
			continue
		if int(rec.get("required_stage", 1)) > stage:
			continue
		var perm := str(rec.get("required_permission", ""))
		if perm != "" and not (profile.get("interaction_permissions", []) as Array).has(perm):
			continue
		out.append(rec)
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return str(a.id) < str(b.id))
	return out


## The actions of a weapon's moveset at `stage`: the light chain followed through chain_next, then the heavy.
static func arcs_of(rec: Dictionary, stage: int) -> Array[ActionDef]:
	var m := PlayerEquipment.moveset_for(rec, stage)
	var out: Array[ActionDef] = []
	var seen := {}
	var id := str(m.light_chain)
	while id != "" and not seen.has(id) and seen.size() < 6:
		seen[id] = true
		var a := GameData.get_action(id)
		if a == null:
			break
		out.append(a)
		id = str(a.param("chain_next", ""))
	var heavy := GameData.get_action(str(m.heavy))
	if heavy != null and not seen.has(heavy.id):
		out.append(heavy)
	return out


## Runs the contract with `tm`; returns {"samples", "angles": PackedFloat32Array, "failures": int}. Each
## failure is reported once per weapon and stage (the first sample that breaks it).
func run_contract(tm: TipMatching, label: String) -> Dictionary:
	var angles := PackedFloat32Array()
	var samples := 0
	var bad := 0
	var small_worst := 0.0   # the worst outer-half miss / radius of a weapon past its fit stage
	for stage: int in STAGES:
		var profile := PlayerGrowth.find_profile(GameData.records_of_type("growth_profile"), stage)
		assert_true(not profile.is_empty(), "%s: the stage-%d profile" % [label, stage])
		var weapons := player_weapons(stage, profile)
		assert_true(weapons.size() >= 5, "%s: stage %d has player weapons (%d)" % [label, stage, weapons.size()])
		for rec: Dictionary in weapons:
			var arcs := arcs_of(rec, stage)
			var small := PlayerEquipment.too_small_at(rec, stage)
			var reported := false
			for a: ActionDef in arcs:
				if a.arc.is_empty() or a.active_ticks <= 0:
					continue
				var offset := PlayerAttack.offset_for(profile, a.id)
				for i in range(0, a.active_ticks, 2):
					var f := float(i + 1) / float(a.active_ticks)
					var g := TipMatching.swing_geometry(profile, rec, stage, a, f, offset)
					var m := tm.match_swing(g.pivot, g.dir, g.arm, g.weapon)
					var seg := TipMatching.tested_segment(g.pivot, g.dir, g.arm, g.weapon)
					var dev := TipMatching.outer_half_deviation(m.grip, m.weapon_dir, g.weapon, seg[0], seg[1])
					var ang := TipMatching.angle_deg(m.weapon_dir, g.dir)
					var reach := (m.grip as Vector3).distance_to(tm.shoulder.r)
					samples += 1
					angles.append(ang)
					var why := ""
					if small:
						small_worst = maxf(small_worst, dev / float(g.radius))
					if dev > float(g.radius) + 1e-4 and not small:
						why = "the outer half strays %.3f m from the tested segment (radius %.3f)" % [dev, g.radius]
					elif ang > TipMatching.MAX_ANGLE_DEG + 1e-3:
						why = "the weapon is %.1f° off the tested direction" % ang
					elif reach > tm.grip_reach("r") + 1e-4:
						why = "the grip is %.3f m from the shoulder (reach %.3f)" % [reach, tm.grip_reach("r")]
					elif not bool(m.exact) or float(m.fist_error) > TipMatching.FIST_TOLERANCE_M:
						why = "the solve misses the grip by %.4f m" % float(m.fist_error)
					if why != "":
						bad += 1
						if not reported:
							reported = true
							fail("%s: %s at stage %d, %s f=%.2f: %s" % [label, rec.id, stage, a.id, f, why])
	return {"samples": samples, "angles": angles, "failures": bad, "small_worst": small_worst}


static func median(values: PackedFloat32Array) -> float:
	var v := values.duplicate()
	v.sort()
	return v[v.size() / 2] if not v.is_empty() else 0.0


func _check(tm: TipMatching, label: String) -> void:
	var r := run_contract(tm, label)
	assert_true(int(r.samples) > 400, "%s: %d samples over the arcs" % [label, r.samples])
	checks += 1
	assert_eq(int(r.failures), 0, "%s: every sample keeps the contract (%d of %d broke it)" % [label, r.failures,
		r.samples])
	var med := median(r.angles)
	assert_true(med <= MEDIAN_DEG, "%s: the median angle off the tested direction is %.2f° (at most %.0f°)" % [label,
		med, MEDIAN_DEG])
	print("    test_tip_matching: %s - %d samples, median %.2f°, worst %.2f°; past their fit stage the outer half misses by up to %.2f x the radius" % [
		label, r.samples, med, Array(r.angles).max() if not (r.angles as PackedFloat32Array).is_empty() else 0.0,
		float(r.small_worst)])


func test_every_player_weapon_arc_keeps_the_contract_with_the_default_landmarks() -> void:
	var tm := TipMatching.from_index({})
	assert_eq(tm.source, "landmarks", "no index: the default landmarks")
	assert_near(float(tm.reach.r), 1.385, 1e-6, "the brief's reach")
	_check(tm, "default landmarks")


func test_the_exported_landmarks_keep_the_contract_once_the_model_exists() -> void:
	if not ResourceLoader.exists(MODEL):
		print("    test_tip_matching: the exported landmarks skipped - %s does not exist yet (P41; the W25 merge runs it)" % MODEL)
		return
	var root := (load(MODEL) as PackedScene).instantiate()
	var index: Variant = root.get("index")
	root.free()
	assert_true(typeof(index) == TYPE_DICTIONARY, "giant_model.tscn's root carries the index")
	if typeof(index) != TYPE_DICTIONARY:
		return
	var tm := TipMatching.from_index(index)
	assert_eq(tm.source, "index", "the model's landmarks are read")
	_check(tm, "exported landmarks")


func test_idle_grip_is_within_reach_for_every_family() -> void:
	var tm := TipMatching.from_index({})
	var families := {}
	for rec: Dictionary in GameData.records_of_type("weapon"):
		if str(rec.get("light_chain", "")) != "":
			families[str(rec.get("family", ""))] = true
	assert_true(families.size() >= 5, "the player's weapon families (%s)" % [families.keys()])
	for fam: String in families:
		for side: String in ["r", "l"]:
			var g := tm.idle_grip(fam, side)
			var sh: Vector3 = tm.shoulder[side]
			assert_true((g.grip as Vector3).distance_to(sh) <= tm.palm_reach(side) + 1e-4,
				"%s (%s): the resting grip is within reach" % [fam, side])
			assert_true(bool(g.exact), "%s (%s): the arm reaches it exactly" % [fam, side])
			assert_true((g.palm as Vector3).distance_to(g.grip) <= TipMatching.FIST_TOLERANCE_M,
				"%s (%s): the palm is on the grip" % [fam, side])
			assert_near((g.weapon_dir as Vector3).length(), 1.0, 1e-4, "%s: the weapon's direction is a unit" % fam)
	var tree := tm.idle_grip("tree")
	assert_true((tree.weapon_dir as Vector3).y > 0.3, "the tree's trunk points up from the carrying hand")


func test_the_pieces() -> void:
	var tm := TipMatching.from_landmarks(TipMatching.DEFAULT_LANDMARKS)
	var sh: Vector3 = tm.shoulder.r
	# Reachable: the grip is on the sphere around the tip and within reach.
	var tip := sh + Vector3(0.3, -0.2, -2.5)
	var grip := TipMatching.tip_matched_grip(sh, tip, sh + Vector3(0, 0, -1.2), 1.8, tm.grip_reach())
	assert_near(grip.distance_to(tip), 1.8, 1e-3, "the grip is a weapon's length from the tip")
	assert_true(grip.distance_to(sh) <= tm.grip_reach() + 1e-4, "and within reach")
	# Out of reach: the farthest reachable point toward the tip.
	var far := sh + Vector3(0, 0, -9.0)
	var g2 := TipMatching.tip_matched_grip(sh, far, sh + Vector3(0, 0, -1.2), 1.8, tm.grip_reach())
	assert_near(g2.distance_to(sh), tm.grip_reach(), 1e-4, "beyond reach: the arm's full reach")
	assert_true((g2 - sh).normalized().dot((far - sh).normalized()) > 0.9999, "toward the tip")
	# The two-bone solve: exact inside the bones' reach, the elbow toward the pole.
	var s := TipMatching.two_bone(sh, sh + Vector3(0.2, -0.4, -0.5), 0.6, 0.5, Vector3(0.6, -0.6, 0.5))
	assert_true(bool(s.exact), "a reachable target is reached exactly")
	assert_near((s.elbow as Vector3).distance_to(sh), 0.6, 1e-4, "the upper arm keeps its length")
	assert_near((s.elbow as Vector3).distance_to(s.end), 0.5, 1e-4, "the forearm keeps its length")
	var out := TipMatching.two_bone(sh, sh + Vector3(0, 0, -5), 0.6, 0.5, Vector3.DOWN)
	assert_false(bool(out.exact), "a target beyond the bones is not reached")
	# The hand's axis lies GRIP_AXIS_DEG off the weapon.
	var w := Vector3(0, 0, -1)
	var h := TipMatching.hand_axis(w, Vector3(1, 0, 0))
	assert_near(TipMatching.angle_deg(h, w), TipMatching.GRIP_AXIS_DEG, 1e-3, "the diagonal grip")
	# A partial index falls back joint by joint.
	var partial := TipMatching.from_index({"landmarks": {"shoulder_r": [0.4, 3.0, 0.0], "shoulder_l": [-0.4, 3.0, 0.0]}})
	assert_eq(partial.source, "index", "an index with both shoulders is read")
	assert_eq(partial.shoulder.r, Vector3(0.4, 3.0, 0.0), "its shoulder")
	assert_eq(partial.landmarks.elbow_r, TipMatching.DEFAULT_LANDMARKS.elbow_r, "a missing joint takes the default")
