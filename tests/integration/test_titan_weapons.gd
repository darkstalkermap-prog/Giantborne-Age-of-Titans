extends IntegrationSuite
## The axe, the great pine and the titanforged weapons (P31, plan M6-M9 §5.12, decision 24): their
## multipliers, fits and perks; each perk reaches the blows it names (the club's heavies, the sword's
## light 3s, every axe blow; the maul's heavy shockwave) and changes the hits it builds (+25 % poise on
## a formation member only, +10 flat penetration on the axe's own 15 - an axe ignores 15 armour); and
## the meshes (an axe head, the pine's needles hidden in first person, titan-iron bands) are as long as
## the sweep. The perks in real stage 4-6 swings are in tests/slow/test_stage_reach_bands.gd.

const TITAN := {"weapon.club_titan": 1.35, "weapon.sword_titan": 1.30, "weapon.hammer_titan": 1.55,
	"weapon.axe_titan": 1.5}


func test_records_fits_and_perks() -> void:
	for id: String in TITAN:
		var w := GameData.get_record(id)
		assert_near(float(w.damage_multiplier), float(TITAN[id]), 1e-6, "%s: x%.2f" % [id, TITAN[id]])
		assert_eq(int(w.fit_max_stage), 6, "%s fits stage 6" % id)
		assert_true(typeof(w.get("perk")) == TYPE_DICTIONARY and str(w.perk.get("text", "")) != "", "%s has a perk" % id)
		assert_false(w.has("upgrade"), "%s is the end of its chain" % id)
	assert_eq(GameData.get_record("weapon.club_titan").perk.kind, "formation_poise", "the club: formation poise")
	assert_near(float(GameData.get_record("weapon.club_titan").perk.poise_mult), 1.25, 1e-6, "+25 %")
	assert_eq(GameData.get_record("weapon.sword_titan").perk.kind, "pierce", "the sword: pierce")
	assert_eq(GameData.get_record("weapon.hammer_titan").perk.kind, "heavy_shockwave", "the maul: a shockwave")
	assert_near(float(GameData.get_record("weapon.hammer_titan").perk.radius_m), 3.0, 1e-6, "of 3 m")
	assert_eq(int(GameData.get_record("weapon.axe_titan").perk.flat_penetration), 10, "the axe: +10 penetration")
	var axe := GameData.get_record("weapon.axe")
	assert_eq([float(axe.damage_multiplier), int(axe.fit_max_stage), str(axe.upgrade.forge_tier)], [1.25, 6, "titan"],
		"the axe: x1.25, fits 6, titanforged at a titan forge")
	for id: String in ["ability.axe_light_1", "ability.axe_light_2", "ability.axe_light_3", "ability.axe_heavy",
			"ability.axe_great_light_1", "ability.axe_great_light_2", "ability.axe_great_light_3", "ability.axe_great_heavy"]:
		var a := GameData.get_action(id)
		assert_near(a.flat_penetration, 15.0, 1e-6, "%s bites through 15 armour" % id)
	var light := GameData.get_action("ability.axe_light_1").arc
	assert_near(absf(float(light.yaw_start_deg) - float(light.yaw_end_deg)), 140.0, 1e-6, "an axe cleaves a 140-degree arc")
	var pine := GameData.get_record("weapon.tree_pine")
	assert_eq([int(pine.required_stage), int(pine.fit_max_stage), bool(pine.scales_with_growth)], [4, 6, true],
		"the great pine: from stage 4, growing with the giant to 6")
	assert_near(CombatRules.effective_armor(15.0, GameData.get_action("ability.axe_heavy").flat_penetration), 0.0, 1e-6,
		"an axe blow ignores 15 armour")


func test_perks_reach_their_blows_and_change_their_hits() -> void:
	var p := spawn_player(Vector3(0, 0.05, 0))
	await TestWait.until(self, func() -> bool: return p.is_on_floor(), 30)
	var runner: AttackRunner = p.attack.runner
	var cases := [
		["weapon.club_titan", "ability.heavy_1", "formation_poise"], ["weapon.club_titan", "ability.light_1", ""],
		["weapon.sword_titan", "ability.sword_light_3", "pierce"], ["weapon.sword_titan", "ability.sword_light_1", ""],
		["weapon.axe_titan", "ability.axe_light_1", "flat_penetration"], ["weapon.axe", "ability.axe_light_1", ""],
		["weapon.hammer_titan", "ability.hammer_heavy", ""],
	]
	for c: Array in cases:
		assert_true(bool(p.equipment.grant_weapon(c[0], true).get("ok", false)), "%s equipped" % c[0])
		var perk := runner.p31_perk_for(GameData.get_action(c[1]))
		assert_eq(str(perk.get("kind", "")), c[2], "%s, %s: perk '%s'" % c)
	var loner := spawn_soldier(Vector3(5, 0.05, -5), 0.0, "test.loner")
	var ranked := spawn_soldier(Vector3(-5, 0.05, -5), 0.0, "test.ranked")
	ranked.formation_id = "test.formation"
	var club_perk: Dictionary = GameData.get_record("weapon.club_titan").perk
	for t: SoldierEnemy in [loner, ranked]:
		var e := HitEvent.new()
		e.poise_damage = 40.0
		AttackRunner.p31_apply_perk(club_perk, e, t.entity)
		assert_near(e.poise_damage, 50.0 if t == ranked else 40.0, 1e-4,
			"the titanforged club's heavy on a %s" % ("formation member: +25 % poise" if t == ranked else "loner: unchanged"))
	var e := HitEvent.new()
	e.flat_penetration = 15.0
	AttackRunner.p31_apply_perk(GameData.get_record("weapon.axe_titan").perk, e, loner.entity)
	assert_near(e.flat_penetration, 25.0, 1e-4, "the titanforged axe: 15 + 10 flat penetration")
	# The maul's shockwave (stage-1 metres) and the sword's pierce reach grow with the weapon.
	var maul_perk: Dictionary = GameData.get_record("weapon.hammer_titan").perk
	p.equipment.grant_weapon("weapon.hammer_titan", true)
	assert_near(runner.p31_shockwave_radius(maul_perk), 3.0, 1e-4, "3 m at stage 1")
	assert_true(bool(p.growth.debug_set_stage(4).ok), "stage 4")
	assert_near(runner.p31_shockwave_radius(maul_perk), 3.0 * p.current_weapon_scale(), 1e-4,
		"x%.2f at stage 4" % p.current_weapon_scale())


func test_axe_pine_and_titanforged_meshes() -> void:
	for id: String in ["weapon.axe", "weapon.axe_titan", "weapon.tree_pine", "weapon.club_titan", "weapon.sword_titan",
			"weapon.hammer_titan"]:
		var rec := GameData.get_record(id)
		var node := WeaponVisuals.build(rec)
		var length := float(rec.length_m)
		assert_true(absf(WeaponVisuals.local_length(node) - length) <= 0.02 * length,
			"%s: the mesh is %.2f m long, as the sweep (%.2f)" % [id, WeaponVisuals.local_length(node), length])
		assert_eq(node.get_node_or_null("TitanBand0") != null, id.ends_with("_titan"), "%s: titan-iron bands only when titanforged" % id)
		node.free()
	var axe := WeaponVisuals.build(GameData.get_record("weapon.axe"))
	assert_true(axe.get_node_or_null("Blade") != null and axe.get_node_or_null("Haft") != null, "the axe: a haft and a blade")
	axe.free()
	var pine := WeaponVisuals.build(GameData.get_record("weapon.tree_pine"))
	var needles := pine.get_node_or_null("Needles0") as MeshInstance3D
	assert_true(needles != null and needles.layers == WeaponVisuals.FP_HIDDEN_LAYER, "the pine's needles hide in first person")
	pine.free()
	assert_eq(WeaponVisuals.idle_pose(GameData.get_record("weapon.tree_pine")), WeaponVisuals.TREE_IDLE_POSE,
		"the pine is carried like the tree")
	assert_eq(WeaponVisuals.shape_of({"family": "axe"}), "axe", "an axe without a visual_shape is still an axe")
