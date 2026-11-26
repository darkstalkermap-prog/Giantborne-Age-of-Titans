extends IntegrationSuite
## P62 (plan M11 §2.10, §3.15 design 3): the rival giant and Harrok are the player's realistic giant - SkinnedRig on
## giant_model.tscn - with their own looks:
##   * headless: their Visual is a SkinnedRig on an instance of the player's model (the same Mesh resources: no copy
##     in memory or in the pack), Body at k = height / 3.6576, the brain's pivots and hand markers, the axe from the
##     weapon record on WeaponSocket, as long as the gameplay's sweep;
##   * with the skinned layers: the record's appearance preset is drawn (the hide mantle and the war harness, the
##     iron rings in the beard; Harrok's iron vambraces), secondary motion runs on their hair and beard, a hit flash
##     reaches every surface, SKIN_STATS' look stays the player's;
##   * tip matching on their own weapon data: over every ACTIVE frame of the axe combo the visible axe's outer half
##     lies within the tested capsule (the axe's hit radius) of the swing the simulation tests.

const RIVAL := "res://scenes/enemies/rival_giant.tscn"
const HARROK := "res://scenes/enemies/harrok.tscn"
const COMBO := "ability.giant_axe_combo_1"


func _giant(scene: String, id: String, pos: Vector3, yaw := 0.0) -> RivalGiantEnemy:
	var g := (load(scene) as PackedScene).instantiate() as RivalGiantEnemy
	g.entity_id = id
	g.ai_enabled = false
	g.position = pos
	g.rotation.y = yaw
	world.add_child(g)
	return g


func test_headless_they_share_the_players_model_at_their_scale_with_their_axe() -> void:
	var p := spawn_player(Vector3(0, 0.05, 40), PI)
	var r := _giant(RIVAL, "test.rival_rig", Vector3(-20, 0.05, 0))
	var h := _giant(HARROK, "test.harrok_rig", Vector3(20, 0.05, 0))
	await step_ticks(2)
	var pm := (p.rig as SkinnedRig).model()
	for g: RivalGiantEnemy in [r, h]:
		var rig := g.rig as SkinnedRig
		assert_true(rig != null and rig.model() != null, "%s: a SkinnedRig on the giant's model" % g.entity_id)
		var k := float(g.record.height_m) / 3.6576
		assert_near(rig.body_scale, k, 1e-4, "%s: Body at k = %.3f" % [g.entity_id, k])
		assert_near(rig.body.scale.y, k, 1e-4, "%s: Body scaled" % g.entity_id)
		var same := 0
		for id: String in ["Body_Torso", "Body_Head", "Body_Limbs", "Garment_hide_mantle"]:
			var mi := rig.model().mesh(id)
			if mi != null and pm.mesh(id) != null and mi.mesh == pm.mesh(id).mesh:
				same += 1
		assert_eq(same, 4, "%s: the player's meshes themselves (no copy)" % g.entity_id)
		assert_true(rig.body.has_node("ShoulderR/Hand") and rig.body.has_node("HipL"), "%s: the brain's pivots" % g.entity_id)
		var w := rig.weapon_visual
		assert_true(w != null and w.get_parent() == rig.weapon_socket(), "%s: the axe on the socket" % g.entity_id)
		var seg := rig.visible_weapon_segment()
		assert_near((seg[1] as Vector3).distance_to(seg[0]), g.weapon_length, 1e-3, "%s: the axe as long as the sweep" % g.entity_id)
		assert_near(w.global_transform.basis.z.length(), 1.0, 1e-3, "%s: drawn at the record's length (world scale 1)" % g.entity_id)


func test_skinned_they_wear_their_looks_flash_and_sway() -> void:
	SkinnedRig.enable_for_tests()
	var r := _giant(RIVAL, "test.rival_look", Vector3(-20, 0.05, 0))
	var h := _giant(HARROK, "test.harrok_look", Vector3(20, 0.05, 0))
	var p := spawn_player(Vector3(0, 0.05, 40), PI)
	await step_ticks(3)
	var rr := r.rig as SkinnedRig
	var hr := h.rig as SkinnedRig
	assert_eq(rr.own_look, "appearance_preset.npc_rival_giant", "the rival giant's look")
	assert_eq(hr.own_look, "appearance_preset.npc_harrok", "Harrok's look")
	for want: String in ["Garment_hide_mantle", "Garment_war_harness", "Beads_iron"]:
		assert_true(rr.shown_meshes().has(want), "the rival giant wears %s (%s)" % [want, rr.shown_meshes()])
	for want: String in ["Garment_hide_mantle", "Garment_iron_vambraces", "Beads_iron"]:
		assert_true(hr.shown_meshes().has(want), "Harrok wears %s (%s)" % [want, hr.shown_meshes()])
	assert_true(rr.shown_meshes() != hr.shown_meshes(), "two looks")
	assert_true(rr.secondary() != null and not (rr.secondary().chains as Array).is_empty(), "secondary motion runs (%s)" % [
		rr.secondary().chains if rr.secondary() != null else []])
	assert_true(rr.animation_tree() != null and rr.legs_source() != "", "the giant's clips drive its legs")
	r.flash(1.0)
	await step_ticks(1)
	var lit := 0
	var mats := GiantLook.materials(rr.model())
	for m: Variant in mats:
		if m is ShaderMaterial and ((m as ShaderMaterial).get_shader_parameter("flash") as Vector3).x > 0.3:
			lit += 1
	assert_true(mats.size() > 5 and lit == mats.size(), "a flash on every surface (%d of %d)" % [lit, mats.size()])
	assert_true(str(SkinnedRig.run_stats().look) != "appearance_preset.npc_harrok"
		and str(SkinnedRig.run_stats().look) != "appearance_preset.npc_rival_giant", "SKIN_STATS' look is the player's")
	p.queue_free()


func test_tip_matching_shows_the_tested_swing_on_their_weapon_data() -> void:
	SkinnedRig.enable_for_tests()
	var report := PackedStringArray()
	for spec: Array in [[RIVAL, "test.rival_tip"], [HARROK, "test.harrok_tip"]]:
		var g := _giant(spec[0], spec[1], Vector3(0, 0.05, 0))
		await step_ticks(3)
		var rig := g.rig as SkinnedRig
		var act := GameData.get_action(COMBO)
		g.controller.force_action(act)
		var worst := 0.0
		var frames := 0
		for k in 240:
			await get_tree().process_frame
			if g.controller.action == null and rig.rig_state().get("action") == null:
				break
			if int(rig.rig_state().get("phase", 0)) != ActionDef.Phase.ACTIVE:
				if frames > 0:
					break   # (the first blow measured; the chained second is the same contract)
				continue
			# (the action the rig shows: the combo chains its second blow the other way)
			var shown: ActionDef = rig.rig_state().get("action")
			var seg := g.weapon_segment_global(shown, float(rig.rig_state().get("phase_fraction", 0.0)))
			var vis := rig.visible_weapon_segment()
			if vis.size() != 2:
				continue
			var grip: Vector3 = vis[0]
			var dir: Vector3 = (vis[1] as Vector3) - grip
			worst = maxf(worst, TipMatching.outer_half_deviation(grip, dir, dir.length(), seg[0], seg[1]))
			frames += 1
		assert_true(frames >= 2, "%s: ACTIVE frames seen (%d)" % [spec[1], frames])
		assert_true(worst <= g.weapon_hit_radius(), "%s: the axe's outer half within the tested capsule (%.3f m of %.2f)" % [
			spec[1], worst, g.weapon_hit_radius()])
		report.append("%s %.3f m" % [str(spec[1]).trim_prefix("test."), worst])
		g.queue_free()
		await step_ticks(1)
	print("    test_rival_giant_rig: the axe combo's worst outer-half miss over the ACTIVE frames: %s" % ", ".join(report))


## P64c (the M13 gate review): the overhead chop (a line pulse) and the strokes' windups in both hands. The chop: at
## the windup's top both fists over the head and the axe's head behind it; at the active phase's end the axe brought
## down ahead (its tip low, ahead of the giant), both fists on the haft. The axe combo's windup: the axe drawn back
## over the shoulder (its tip behind the giant), the off fist on the haft.
func _run_to(g: RivalGiantEnemy, action: String, phase: int, at: float) -> bool:
	if g.controller.action == null or g.controller.action.id != action:
		g.controller.force_action(GameData.get_action(action))
	for i in 300:
		await get_tree().process_frame
		var s: Dictionary = (g.rig as SkinnedRig).rig_state()
		if int(s.get("phase", 0)) == phase and float(s.get("phase_fraction", 0.0)) >= at:
			await get_tree().process_frame
			return true
	return false


func _off_haft(rig: SkinnedRig) -> float:
	var seg := rig.visible_weapon_segment()
	var p := rig.palm_global(true)
	var u := ((seg[1] as Vector3) - (seg[0] as Vector3)).normalized()
	var d := p - (seg[0] as Vector3)
	return (d - u * d.dot(u)).length()


func test_the_chop_raises_the_axe_overhead_and_brings_it_down_in_both_hands() -> void:
	SkinnedRig.enable_for_tests()
	var report := PackedStringArray()
	for spec: Array in [[RIVAL, "test.rival_chop", "ability.giant_axe_chop"], [HARROK, "test.harrok_chop", "ability.harrok_chop"]]:
		var g := _giant(spec[0], spec[1], Vector3(0, 0.05, 0))
		await step_ticks(3)
		var rig := g.rig as SkinnedRig
		assert_true(rig.two_handed(), "%s: the axe in both hands" % spec[1])
		var h := float(g.record.height_m)
		var grip_m := 0.05 * h   # (the off palm, beside the haft it holds: a hand's breadth at the giant's scale)
		assert_true(await _run_to(g, spec[2], ActionDef.Phase.WINDUP, 0.95), "%s: the windup's top" % spec[1])
		var seg := rig.visible_weapon_segment()
		var fist := g.to_local(seg[0] as Vector3)
		var tip := g.to_local(seg[1] as Vector3)
		assert_true(fist.y > h * 0.88, "%s: the fists over the head (%.2f of %.1f m)" % [spec[1], fist.y, h])
		assert_true(tip.z > fist.z + h * 0.1, "%s: the axe's head behind (%.2f m)" % [spec[1], tip.z - fist.z])
		assert_true(_off_haft(rig) < grip_m, "%s: the off palm on the haft (%.2f m)" % [spec[1], _off_haft(rig)])
		assert_true(await _run_to(g, spec[2], ActionDef.Phase.ACTIVE, 0.95), "%s: the active phase" % spec[1])
		seg = rig.visible_weapon_segment()
		fist = g.to_local(seg[0] as Vector3)
		tip = g.to_local(seg[1] as Vector3)
		assert_true(tip.z < -h * 0.25 and tip.y < h * 0.3, "%s: brought down ahead (tip %s)" % [spec[1], tip])
		assert_true(fist.y < h * 0.65, "%s: the fists low (%.2f m)" % [spec[1], fist.y])
		assert_true(_off_haft(rig) < grip_m, "%s: the off palm on the haft (%.2f m)" % [spec[1], _off_haft(rig)])
		report.append("%s tip %.1f m ahead, %.1f m up" % [str(spec[1]).trim_prefix("test."), -tip.z, tip.y])
		await step_ticks(120)
		assert_true(await _run_to(g, COMBO, ActionDef.Phase.WINDUP, 0.95), "%s: the combo's windup" % spec[1])
		seg = rig.visible_weapon_segment()
		tip = g.to_local(seg[1] as Vector3)
		assert_true(tip.z > -h * 0.05 and tip.y > h * 0.6, "%s: drawn back over the shoulder (tip %s)" % [spec[1], tip])
		assert_true(_off_haft(rig) < grip_m * 1.4, "%s: the off palm on the haft (%.2f m)" % [spec[1], _off_haft(rig)])
		g.queue_free()
		await step_ticks(1)
	print("    test_rival_giant_rig: the chop %s" % ", ".join(report))
