extends IntegrationSuite
## D3: stage 9 and the growth chain made real, without a world - the stage-9 profile's framing and numbers against
## the curve (a 116 ft body: the camera far enough to read him, close enough that the ground stays big under him);
## the chain (stage 8 asks the Frostbound slain, stage 9 the Stormcaller slain, each with its refusal, and the quest
## that leads to stage 9); the old saves (a 0.16 save grown to stage 8 on C1's trials with the Frostbound alive keeps
## its stage; the new 0.16 fixture at stage 9 loads and keeps its); what fits a stage-9 giant (every armour set; the
## titans' weapons and the Colossus Anvil's after their stage-9 working); the awe tiers that break a troll, an ogre,
## a rimkin and a wolf before a stage-9 giant and not a stage-8; level 17 on the guaranteed path; the growth moment's
## curve; the Stormstair's pools drawn with the storm's water.

const FIXTURES := "res://tests/fixtures/saves/"
const STAGE8_TRIALS := "v3_m16_c1_stage8_trials.json"
const STAGE9 := "v3_m16_d3_stage9.json"


func _profile(stage: int) -> Dictionary:
	return PlayerGrowth.find_profile(GameData.records_of_type("growth_profile"), stage)


func test_stage_9_frames_a_116_ft_body() -> void:
	var g8 := _profile(8)
	var g9 := _profile(9)
	var h := float(g9.height_m)
	assert_near(h, 116.0 * 0.3048, 1e-3, "116 ft is 35.36 m")
	# the camera: the arm about 1.2 heights back (stage 8's 1.23), the pivot at the brow (0.915 of the height)
	var arm_ratio := float(g9.camera_distance_m) / h
	assert_true(arm_ratio >= 1.1 and arm_ratio <= float(g8.camera_distance_m) / float(g8.height_m) + 1e-3,
		"the default arm %.2f heights back: no farther than stage 8's, so the ground stays big under him" % arm_ratio)
	assert_near(float(g9.camera_pivot_height_m) / h, float(g8.camera_pivot_height_m) / float(g8.height_m), 0.01,
		"the pivot at the same height on the body")
	assert_true(float(g9.camera_zoom_max_m) <= CameraRig.MAX_ARM_M + 1e-3, "the rig's arm reaches the zoom's far end")
	# reach and the size multiplier (C1-4)
	assert_near(float(g9.melee_reach_m) / h, float(g8.melee_reach_m) / float(g8.height_m), 0.01, "reach in proportion")
	assert_near(CombatRules.size_multiplier(h), 2.78, 0.01, "the size multiplier x2.78 (C1-4's curve)")
	assert_true(int(g9.resource_bonus.health) > int(g8.resource_bonus.health), "more health than stage 8")
	# the stride
	var stride := GameData.get_action("ability.colossus_stride")
	var vault: Dictionary = stride.param("vault")
	assert_true(h * float(vault.get("max_height_ratio", 0.5)) > 16.0 and float(g8.height_m) * float(vault.get("max_height_ratio", 0.5)) < 16.0,
		"a 16 m tower is in a stage-9 stride and out of a stage-8's")
	print("    stage 9: %.2f m, reach %.1f m, camera %.0f m (zoom %.0f-%.0f), pivot %.2f m, size x%.2f" % [h,
		float(g9.melee_reach_m), float(g9.camera_distance_m), float(g9.camera_zoom_min_m), float(g9.camera_zoom_max_m),
		float(g9.camera_pivot_height_m), CombatRules.size_multiplier(h)])


func test_the_chain_stage_8_the_frostbound_stage_9_the_stormcaller() -> void:
	var g8 := _profile(8)
	var g9 := _profile(9)
	var flags := {"act.two.begun": true, "visited.world.shrine.rimstone": true, Quests.done_flag("quest.rim_colossus"): true}
	var ctx := {"flags": flags, "stage": 7, "level": 15}
	var r := PlayerGrowth.requirement_gate(g8, ctx)
	assert_eq([r.ok, r.reason], [false, "requirement"], "the trials done, the Frostbound alive: stage 8 refused")
	assert_eq(str(r.message), "The Rimstone will not answer while the Frostbound Titan holds the ice above the Hoarwatch. Bring him down first.",
		"the refusal says what is still needed")
	flags["boss.frostbound.defeated"] = true
	assert_true(bool(PlayerGrowth.requirement_gate(g8, ctx).ok), "his fall: stage 8")
	r = PlayerGrowth.requirement_gate(g9, ctx)
	assert_eq(str(r.message), "The Rimstone will not answer while the Stormcaller's storm stands over the Drowned Steps. Bring him down first.",
		"stage 9's refusal")
	flags["boss.stormcaller.defeated"] = true
	assert_true(bool(PlayerGrowth.requirement_gate(g9, ctx).ok), "his fall: stage 9")
	assert_eq(PlayerGrowth.level_gate(g9, 16).message, "You must reach level 17 to grow to stage 9.", "and the level's refusal")
	assert_eq(int(GameData.get_record("shrine.world_rimstone").max_stage), 9, "the Rimstone grows stage 9")
	var q := GameData.get_record("quest.elder_colossus")
	var qctx := QuestConditions.empty_context()
	assert_false(QuestConditions.all_hold(q.start_conditions, qctx), "the growth's quest waits for the storm")
	qctx.flags = {"boss.stormcaller.defeated": true}
	assert_true(QuestConditions.all_hold(q.start_conditions, qctx), "and starts on his fall")
	assert_eq(str(((q.stages as Array)[0] as Dictionary).complete_when.type), "stage_at_least", "grow to stage 9")
	var slay: Dictionary = Quests.stage_record(GameData.get_record("quest.stormcaller"), "slay")
	assert_eq(int(slay.get("xp_floor_level", 0)), 17, "his fall lifts a giant to stage 9's level")


func test_old_saves_keep_their_stage() -> void:
	for f: String in ["v3_m16_d1_frost_lead.json", "v3_m16_d2_storm_lead.json", STAGE8_TRIALS, STAGE9]:
		var doc := SaveSlots.migrate(JsonIO.read_file(FIXTURES + f).data)
		assert_eq(SaveSlots.validate(doc), PackedStringArray(), "%s validates" % f)
		assert_eq(int(doc.schema_version), 3, "%s: schema 3 (no new schema)" % f)
	# a 0.16 save grown to stage 8 on C1's trials, the Frostbound alive: it stays a stage-8 giant (never shrunk)
	var old := SaveSlots.migrate(JsonIO.read_file(FIXTURES + STAGE8_TRIALS).data)
	assert_false(bool((old.world.flags as Dictionary).get("boss.frostbound.defeated", false)), "(the Frostbound alive)")
	var p := spawn_player(Vector3(0, 0.05, 0))
	await step_ticks(1)
	p.apply_character_state(CharacterState.normalize(old.character))
	await step_ticks(2)
	assert_eq(p.growth_stage, 8, "the stage-8 save stays stage 8")
	assert_near(p.entity.combatant.height_m, float(_profile(8).height_m), 1e-4, "at 96 ft")
	var ctx := {"flags": old.world.flags, "stage": 8, "level": int(old.character.level)}
	assert_false(bool(PlayerGrowth.requirement_gate(_profile(9), ctx).ok), "and asks the Stormcaller of stage 9")
	# the new 0.16 fixture at stage 9
	var nine := SaveSlots.migrate(JsonIO.read_file(FIXTURES + STAGE9).data)
	assert_eq(str(nine.build_version), "0.16.0-m16", "a 0.16 save")
	p.apply_character_state(CharacterState.normalize(nine.character))
	await step_ticks(2)
	assert_eq(p.growth_stage, 9, "the stage-9 save is a stage-9 giant")
	assert_near(p.entity.combatant.height_m, float(_profile(9).height_m), 1e-4, "116 ft")
	assert_eq(str(p.current_weapon().get("id", "")), "weapon.club_greatforged", "with the greatforged club")
	# Dgate (DG-1): its level kept, its XP lifted onto the colossus levels' costs (never lowered)
	assert_eq(int(p.progression.level), 17, "level 17 kept")
	assert_eq(int(p.progression.xp), Progression.lifted_xp(17, int(nine.character.xp)), "its share of level 17 kept on today's costs")
	assert_true(int(p.progression.xp) >= int(nine.character.xp), "never less XP than saved (%d)" % int(nine.character.xp))
	var x := ExpansionState.from_doc(nine)
	assert_eq(str((x.titans["titan.stormcaller"] as Dictionary).state), ExpansionState.STATE_SLAIN, "the Stormcaller slain")


func test_what_fits_a_stage_9_giant() -> void:
	for rec: Dictionary in GameData.records_of_type("armour"):
		for key: String in ["fit_max_stage", "max_stage", "fit_stage"]:
			assert_false(rec.has(key), "%s has no stage cap: every armour piece is drawn at every stage" % rec.id)
	assert_eq(int(GameData.get_record("weapon.bell_hammer").fit_max_stage), 9, "the Bell-hammer fits stage 9")
	var maul := GameData.get_record("weapon.rime_maul")
	assert_eq(int(maul.fit_max_stage), 8, "the Rime-maul as made fits stages 7-8")
	var up: Dictionary = maul.upgrade
	assert_eq(str(up.forge_tier), "colossus", "the Colossus Anvil re-hafts it")
	var great := GameData.get_record(str(up.to))
	assert_eq(int(great.fit_max_stage), 9, "great-hafted it fits stage 9")
	assert_eq(str(great.perk.kind), "chill", "and keeps its chill")
	for fam: String in ["club", "axe", "sword", "hammer", "fists"]:
		var rim := GameData.get_record("weapon.%s_rimforged" % fam)
		assert_eq(str((rim.upgrade as Dictionary).to), "weapon.%s_greatforged" % fam, "the %s greatforges" % fam)
		assert_eq(int(GameData.get_record("weapon.%s_greatforged" % fam).fit_max_stage), 9, "and fits stage 9")
	var p := spawn_player(Vector3(0, 0.05, 0))
	await step_ticks(1)
	TitanDuel.prepare(p, 9)
	await step_ticks(1)
	p.equipment.grant_weapon("weapon.rime_maul", true)
	assert_true(p.equipment.is_too_small(), "the Rime-maul is too small for a stage-9 hand")
	p.equipment.grant_weapon("weapon.rime_maul_greathafted", true)
	assert_false(p.equipment.is_too_small(), "great-hafted it fits")


func test_the_awe_tiers_break_the_small_before_stage_9() -> void:
	var h8 := float(_profile(8).height_m)
	var h9 := float(_profile(9).height_m)
	for id: String in ["enemy.troll", "enemy.troll_whelp", "enemy.ogre", "enemy.rimkin_giant", "enemy.rimkin_warleader",
			"enemy.dire_wolf", "enemy.wolf", "enemy.iron_guard"]:
		var rec := GameData.get_record(id)
		var b := EnemyBrain.new("test." + id, rec, 1)
		var own := float(rec.height_m)
		assert_false(b.awe_breaks_at(h8 / own), "%s stands before a stage-8 giant (%.1fx)" % [id, h8 / own])
		assert_true(b.awe_breaks_at(h9 / own), "%s breaks before a stage-9 giant (%.1fx)" % [id, h9 / own])
	# the humans already break before a colossus (C1's 13x); stage 9 changes nothing for them
	var soldier := EnemyBrain.new("test.soldier", GameData.get_record("enemy.soldier"), 1)
	assert_eq(soldier.awe_loss_at(h9 / 1.8), 200.0, "a soldier loses everything before stage 9, as before stage 7")


## Dgate (decision DG-1; D3-6's floors kept): the guaranteed path from the trials' floor (level 15) through the
## Frostbound and the Stormcaller (their quests, Maera's words, their kills, the discoveries) to stage 9's growth and the
## Harrok lead. On the colossus levels' costs a giant is level 16 after the Frostbound, 17 at the Stormcaller's fall (the
## slay stage's floor 17 kept), still 17 at the end of milestone D's content, and levels 18-20 are left to E-F.
func test_level_17_on_the_guaranteed_path() -> void:
	var st := {"xp": Progression.xp_for_level(15), "lines": []}
	var add := func(what: String, n: int) -> void:
		st.xp = int(st.xp) + n
		(st.lines as Array).append("%s +%d -> %d (level %d)" % [what, n, int(st.xp), Progression.level_for_xp(int(st.xp))])
	add.call("the Rimeglass", int(GameData.get_record("poi.rimeglass").get("xp", 0)))
	add.call("the Frostbound's quest, to his slaying", int(WorldXp.stage("quest.frostbound", "reach").get("xp", 0)))
	var before_frost := int(st.xp)
	add.call("his slaying (the quest's slay stage and his kill)", int(WorldXp.stage("quest.frostbound", "slay").get("xp", 0))
		+ int(GameData.get_record("enemy.frostbound").xp_reward))
	add.call("Maera: frost_fallen", 200)
	var after_frost := int(st.xp)
	add.call("growth to stage 8", int(WorldXp.stage("quest.act_two_main", "grow8").get("xp", 0)))
	add.call("the Hoarwatch", int(WorldXp.stage("quest.act_two_main", "hoarwatch").get("xp", 0)))
	add.call("the look south", WorldXp.stages_xp("quest.stormcaller_lead"))
	add.call("the Stormcaller's quest, to his slaying", int(WorldXp.stage("quest.stormcaller", "reach").get("xp", 0)))
	var before_storm := int(st.xp)
	add.call("his slaying", int(WorldXp.stage("quest.stormcaller", "slay").get("xp", 0))
		+ int(GameData.get_record("enemy.stormcaller").xp_reward))
	st.xp = maxi(int(st.xp), Progression.xp_for_level(int(WorldXp.stage("quest.stormcaller", "slay").get("xp_floor_level", 0))))
	add.call("Maera: storm_fallen", 240)
	var at_storm := int(st.xp)
	add.call("stage 9's growth (the Elder Colossus)", WorldXp.stages_xp("quest.elder_colossus"))
	add.call("the Harrok lead", WorldXp.stages_xp("quest.harrok_lead"))
	var xp := int(st.xp)
	print("    Dgate XP path: " + "; ".join(PackedStringArray(st.lines as Array)))
	assert_eq(Progression.level_for_xp(before_frost), 15, "level 15 on the Rimeglass")
	assert_eq(Progression.level_for_xp(after_frost), 16, "level 16 after the Frostbound")
	assert_eq(Progression.level_for_xp(before_storm), 16, "still 16 when the Stormcaller's fight begins")
	assert_eq(Progression.level_for_xp(at_storm), 17, "level 17 at the Stormcaller's fall: stage 9's, no grind")
	assert_eq(Progression.level_for_xp(xp), 17, "still 17 after milestone D's content")
	assert_true(Progression.xp_for_level(18) - xp >= 1000, "level 18 is not within reach of D's last leads (%d to go)" % (
		Progression.xp_for_level(18) - xp))
	assert_eq(int(WorldXp.stage("quest.stormcaller", "slay").get("xp_floor_level", 0)), 17, "D3's floor kept")
	assert_eq(int(GameData.get_record("progression.default").level_cap), 20, "no level beyond 20")


func test_the_growth_moment_curve() -> void:
	assert_near(GrowthMoment.swell_curve(0.0), 0.0, 1e-6, "it starts at the old size")
	assert_near(GrowthMoment.swell_curve(1.0), 1.0, 1e-6, "and ends at the new")
	var last := -1.0
	for i in 21:
		var v := GrowthMoment.swell_curve(float(i) / 20.0)
		assert_true(v >= last - 1e-6, "it only grows (%.3f)" % v)
		last = v
	assert_true(GrowthMoment.duration_s(9) > GrowthMoment.duration_s(4), "a colossus's growth lasts longer")
	assert_true(GrowthMoment.duration_s(9) >= 3.0 and GrowthMoment.duration_s(9) <= 3.6, "stage 9's: %.1f s" % GrowthMoment.duration_s(9))


func test_the_stormstairs_pools_are_drawn_with_the_storms_water() -> void:
	var w := StormWater.new()
	assert_false(w.draw, "the world's node is not the test arena's")
	assert_true(StormWater.WORLD_SCALE > 1.0 and StormWater.WORLD_LIFT_M > 0.0, "drawn wider than the basin, over the chunk's water")
	w.free()
