extends IntegrationSuite
## Batched cosmetic dressing (P15, scripts/world/cosmetic_field.gd): a district's bushes, banners
## and barley sheaves drawn as three MultiMeshes (spheres, boxes, cones; per-instance colours,
## no shadows) that still react like CosmeticProps - pulses and sweeps that reach an item wobble
## it, a stage-1 giant brushing past wobbles it, a stage-2 giant flattens it for 4 s - and are
## never saved. The Valley's districts carry theirs (the plan's ~30 props in the Hollow, the
## fields and the square, banners on the palisade and the ruins' walls).

const BUSH := Vector3(0, 0, -10)
const BANNER := Vector3(6, 0, -10)
const SHEAF := Vector3(-6, 0, -10)
const TINT := Color(0.2, 0.32, 0.55)


func _field() -> CosmeticField:
	var f := CosmeticField.new()
	f.name = "Dressing"
	for it: Array in [["bush", BUSH, 0.0], ["banner", BANNER, 90.0], ["sheaf", SHEAF, 0.0]]:
		f.kinds.append(str(it[0]))
		f.transforms.append(Transform3D(Basis(Vector3.UP, deg_to_rad(float(it[2]))), it[1]))
	f.tints = PackedColorArray([Color(0, 0, 0, 0), TINT, Color(0, 0, 0, 0)])
	world.add_child(f)
	return f


## The vertical scale of item `i`'s first part right now (the CPU copy of the MultiMesh buffer).
func _height_scale(f: CosmeticField, i: int) -> float:
	var first: Array = CosmeticField.TEMPLATES[f.kinds[i]][0]
	var parts := f.parts_of(i).filter(func(p: Array) -> bool: return str(p[0]) == str(first[0]))
	var t := f.part_transform(str(parts[0][0]), int(parts[0][1]))
	var rest: Transform3D = f.transforms[i] * (first[1] as Transform3D)
	return t.basis.y.length() / rest.basis.y.length()


func test_every_kind_in_three_multimeshes_never_saved() -> void:
	var f := _field()
	await step_ticks(1)
	assert_eq(f.item_count(), 3, "three items")
	assert_eq(f.get_child_count(), 3, "three MultiMeshInstances: spheres, boxes and cones")
	var counts := {}
	for k: String in f.multimeshes:
		counts[k] = (f.multimeshes[k] as MultiMesh).instance_count
	assert_eq(counts, {"sphere": 3, "box": 4, "cone": 1}, "a bush's three spheres, a banner's three boxes and a sheaf's cone and band")
	for c in f.get_children():
		var mmi := c as MultiMeshInstance3D
		assert_eq(mmi.cast_shadow, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "%s casts no shadow" % mmi.name)
		assert_true(mmi.visibility_range_end > 0.0, "%s fades out at a distance" % mmi.name)
		assert_true(mmi.multimesh.use_colors, "%s carries per-instance colours" % mmi.name)
	var cloth := -1
	for p: Array in f.parts_of(1):
		var t := f.part_transform(str(p[0]), int(p[1]))
		if t.basis.x.length() > 1.2 and t.basis.y.length() > 2.0:
			cloth = int(p[1])
	assert_true(cloth >= 0, "the banner's cloth is a box part")
	var buf: PackedFloat32Array = (f.multimeshes["box"] as MultiMesh).buffer
	assert_true(Color(buf[cloth * 16 + 12], buf[cloth * 16 + 13], buf[cloth * 16 + 14]).is_equal_approx(TINT), "in the banner's tint")
	assert_true(f.part_transform("cone", 0).origin.distance_to(SHEAF + Vector3(0, 0.7, 0)) < 1e-3, "the sheaf's cone in place")
	assert_true(f.is_in_group(CosmeticField.GROUP), "group cosmetic_fields")
	assert_true(WorldState.deltas.is_empty() and WorldState.flags.is_empty(), "nothing saved")


func test_pulses_and_sweeps_wobble_what_they_reach() -> void:
	var f := _field()
	await step_ticks(1)
	Events.area_pulse.emit(Sim.tick, "player", "ability.heavy_footfall", BUSH + Vector3(0, 0, 2), 3.0)
	assert_eq(Array(f.react_counts), [1, 0, 0], "a Footfall 2 m away wobbles the bush only")
	assert_true(f.is_wobbling(0) and not f.is_flattened(0), "a wobble")
	Events.area_pulse.emit(Sim.tick, "player", "ability.heavy_footfall", BUSH + Vector3(0, 0, 2), 3.0)
	assert_eq(f.react_counts[0], 1, "once per tick")
	await step_ticks(3)
	assert_true(f.part_transform("sphere", 0).basis.y.normalized().angle_to(Vector3.UP) > 0.02, "the bush tilts")
	assert_true(f.part_transform("sphere", 0).basis.y.z < 0.0, "away from the stamp (north)")
	await step_ticks(40)
	assert_false(f.is_wobbling(0), "and settles")
	assert_true(f.part_transform("sphere", 0).basis.y.normalized().angle_to(Vector3.UP) < 1e-4, "back upright")
	# A sweep in front of the giant reaches the banner, not the bush behind its arc.
	Events.ability_effect.emit(Sim.tick, "player", "ability.sweeping_blow", "sector", BANNER + Vector3(0, 0, 4), 5.0, 0.0, 120.0)
	assert_eq(Array(f.react_counts), [1, 1, 0], "a sweep over the banner wobbles it")
	await step_ticks(3)
	assert_true(f.part_transform("box", 0).basis.y.z < 0.0, "the yawed banner leans away from the sweep too")
	Events.ability_effect.emit(Sim.tick, "player", "ability.sweeping_blow", "sector", SHEAF + Vector3(0, 0, -4), 5.0, 0.0, 120.0)
	assert_eq(f.react_counts[2], 0, "a sweep facing away does not reach the sheaf behind it")
	Events.ability_effect.emit(Sim.tick + 1, "player", "ability.thunder_roar", "roar", SHEAF + Vector3(0, 0, -4), 6.0, 0.0, 360.0)
	assert_eq(f.react_counts[2], 1, "a roar does")
	assert_eq(f.react_count, 3, "three reactions in all")


func test_a_grown_giant_flattens_what_it_steps_into() -> void:
	var f := _field()
	var p := spawn_player(SHEAF + Vector3(0, 0.05, 12), 0.0)
	await step_ticks(2)
	GameSession.place_player(p, Transform3D(Basis(), SHEAF + Vector3(0.3, 0.05, 0)))
	await TestWait.until(self, func() -> bool: return f.react_counts[2] > 0, 20)
	assert_eq(f.react_counts[2], 1, "a stage-1 giant brushing past moves the sheaf")
	assert_false(f.is_flattened(2), "but does not flatten it")
	GameSession.place_player(p, Transform3D(Basis(), SHEAF + Vector3(0, 0.05, 14)))
	await step_ticks(20)
	assert_true(bool(p.growth.debug_set_stage(2).ok), "grown to stage 2")
	await step_ticks(2)
	GameSession.place_player(p, Transform3D(Basis(), SHEAF + Vector3(0.3, 0.05, 0)))
	await TestWait.until(self, func() -> bool: return f.is_flattened(2), 20)
	assert_true(f.is_flattened(2), "a stage-2 giant flattens it")
	await step_ticks(15)
	assert_near(_height_scale(f, 2), 0.25, 0.02, "squashed to a quarter of its height")
	await step_ticks(60 * 5)
	assert_false(f.is_flattened(2), "it rises again after about 4 s")
	assert_near(_height_scale(f, 2), 1.0, 1e-3, "back to its height")


func test_the_valleys_districts_are_dressed() -> void:
	var counts := {}
	var banners := {}
	for district: String in ["hollow", "village", "ruins", "kingsfall"]:
		var scene := (load("res://scenes/world/valley/%s.tscn" % district) as PackedScene).instantiate()
		var field := scene.get_node_or_null("Dressing") as CosmeticField
		assert_true(field != null, "%s has its dressing" % district)
		if field != null:
			counts[district] = field.item_count()
			banners[district] = Array(field.kinds).count("banner")
			for k: String in field.kinds:
				assert_true(CosmeticField.RECORDS.has(k) and not GameData.get_record(str(CosmeticField.RECORDS[k])).is_empty(),
					"%s: %s has a cosmetic prop record" % [district, k])
		scene.free()
	assert_true(int(counts.get("hollow", 0)) + int(counts.get("village", 0)) >= 30,
		"about 30 cosmetic props in the Hollow, the fields and the square (%s)" % counts)
	assert_true(int(banners.get("village", 0)) >= 8, "banners on Thornwick's palisade (%d)" % banners.get("village", 0))
	assert_true(int(banners.get("ruins", 0)) >= 4, "and on the ruins' walls (%d)" % banners.get("ruins", 0))
	for k: String in CosmeticField.RECORDS:
		assert_eq(str(GameData.get_record(str(CosmeticField.RECORDS[k])).get("category", "")), "cosmetic",
			"%s is a cosmetic prop" % CosmeticField.RECORDS[k])
