extends IntegrationSuite
## E3: the Hollow Titan's story in data (default tier): the lead E2 left pays off (quest.hollow starts on it), the
## preparation is optional XP only, the XP path (decision E3-5: exactly 6,990 - the guaranteed path at level 20 at the
## very end, 34,950 XP, and no level beyond), one kill pays for the Oathbound set and the Oathblade, Brann's words follow
## the fight, the Worldbreaker is a rumour only (0 XP, nothing built: no stage-10 growth), the roster's ninth slot, the
## reward's numbers, and the saves (a 0.17 fixture on the road to the Kingsward:
## tests/fixtures/saves/v3_m17_e3_kingsward_road.json).

const FIXTURE := "res://tests/fixtures/saves/v3_m17_e3_kingsward_road.json"
## The guaranteed path after E2 (docs/systems/E2.md section 6) and level 20's XP.
const AFTER_E2_XP := 27960
const LEVEL_20_XP := 34950


func _stage_xp(quest_id: String) -> int:
	var total := 0
	for s: Dictionary in GameData.get_record(quest_id).get("stages", []):
		total += int(s.get("xp", 0))
	return total


func test_the_lead_pays_off_and_the_worldbreaker_is_a_rumour() -> void:
	var q := GameData.get_record("quest.hollow")
	assert_false(q.is_empty(), "quest.hollow exists")
	assert_true(JSON.stringify(q.get("start_conditions", [])).contains("lead.hollow.heard"), "it starts on E2's rumour")
	var lead := GameData.get_record("quest.worldbreaker_lead")
	assert_eq(_stage_xp("quest.worldbreaker_lead"), 0, "the Worldbreaker: a lead only, 0 XP")
	assert_true(JSON.stringify(lead.start_conditions).contains("lead.worldbreaker.heard"), "on Brann's word")
	assert_true(GameData.get_record("enemy.worldbreaker").is_empty(), "nothing of the Worldbreaker is built")
	var top := 0
	for rec: Dictionary in GameData.records_of_type("growth_profile"):
		top = maxi(top, int(rec.get("stage", 0)))
	assert_eq(top, 9, "no stage-10 growth (the next packages')")
	var roster: Array = GameData.get_record("titan_roster.signature").titans
	var r: Dictionary = roster.filter(func(t: Dictionary) -> bool: return str(t.id) == "titan.hollow")[0]
	assert_eq(str(r.enemy), "enemy.hollow", "the ninth slot: the Hollow Titan")
	assert_eq(str(r.defeated_flag), "boss.hollow.defeated", "his fall recorded")
	assert_eq(str(r.sighted_poi), "poi.kingsward", "sighted at the Kingsward")
	var w: Dictionary = roster.filter(func(t: Dictionary) -> bool: return str(t.id) == "titan.worldbreaker")[0]
	assert_false(w.has("enemy"), "the Worldbreaker's slot still empty")


func test_the_xp_path_ends_at_level_20() -> void:
	var kill := int(GameData.get_record("enemy.hollow").xp_reward)
	var poi := int(GameData.get_record("poi.kingsward").xp)
	var quest := _stage_xp("quest.hollow")
	assert_eq(kill, 5600, "his kill")
	assert_eq(poi + quest + kill, 6990, "exactly the 6,990 E2 left (decisions E2-6, E3-5)")
	var stages: Array = GameData.get_record("quest.hollow").stages
	var before_tell := AFTER_E2_XP + poi + kill + int(stages[0].xp) + int(stages[1].xp)
	assert_eq(Progression.level_for_xp(before_tell), 19, "level 19 until the last word (%d XP)" % before_tell)
	var after := AFTER_E2_XP + poi + quest + kill
	assert_eq(after, LEVEL_20_XP, "34,950 XP at the very end")
	assert_eq(Progression.level_for_xp(after), 20, "level 20 when Brann is told")
	assert_eq(Progression.level_for_xp(after + 100000), 20, "no level beyond 20")
	assert_eq(_stage_xp("quest.hollow_stake"), 250, "the preparation: optional XP only")
	assert_false(JSON.stringify(GameData.get_record("quest.hollow").stages).contains("stake"),
		"the fight's quest never asks for the preparation")


func test_one_kill_pays_for_the_set_and_the_sword() -> void:
	var have := {}
	for e: Dictionary in GameData.get_record("loot.hollow").guaranteed:
		have[str(e.item)] = int(have.get(str(e.item), 0)) + int(e.count)
	# two plates broken (the breastplate and the crowned helm) add their own
	for p: Dictionary in GameData.get_record("enemy.hollow").plates:
		if str(p.id) in ["cuirass", "helm"]:
			for e: Dictionary in p.get("loot", []):
				have[str(e.item)] = int(have.get(str(e.item), 0)) + int(e.count)
	have["item.iron_ingot"] = 99
	have["item.titan_iron"] = 99
	var need := {}
	for rid: String in ["recipe.hollow_helm", "recipe.hollow_pauldrons", "recipe.hollow_cuirass", "recipe.hollow_vambraces",
			"recipe.hollow_greaves", "recipe.hollow_signet", "recipe.oathblade"]:
		var rec := GameData.get_record(rid)
		assert_false(rec.is_empty(), "%s exists" % rid)
		assert_eq(str(rec.get("requires_flag", "")), "boss.hollow.defeated", "%s once he has fallen" % rid)
		assert_eq(str(rec.get("works", "")), "hollow_gilt", "%s at Last Hearth's titan forges" % rid)
		for e: Dictionary in rec.get("cost", []):
			need[str(e.item)] = int(need.get(str(e.item), 0)) + int(e.count)
	for item: String in need:
		assert_true(int(have.get(item, 0)) >= int(need[item]), "%s: %d needed, %d from one kill" % [item, int(need[item]),
			int(have.get(item, 0))])
	assert_eq(Armour.set_pieces("armour_set.hollow").size(), 6, "the Oathbound set: six pieces")
	var blade := GameData.get_record("weapon.oathblade")
	assert_eq(str(blade.perk.kind), "heavy_shockwave", "the Oathblade's heavy rings")
	assert_eq(int(blade.fit_max_stage), 10, "it fits a colossus to the last stage")
	var set := GameData.get_record("armour_set.hollow")
	var poise := 1.0
	for b: Dictionary in set.bonuses:
		poise *= float((b.modifiers as Dictionary).get("poise_damage_taken_mult", 1.0))
	assert_near(poise, 0.85, 0.001, "the set: blows rock its wearer 15% less")


func test_brann_follows_the_fight() -> void:
	var b := GameData.get_record("dialogue.kingsward_brann")
	var ctx := QuestConditions.empty_context()
	ctx.flags = {}
	assert_eq(DialogueSession.start_node(b, ctx), "greet", "before: where the empty king stood and went")
	ctx.flags = {"world.kingsward.brann_met": true}
	assert_eq(DialogueSession.start_node(b, ctx), "watch", "met: how he is fought")
	ctx.flags = {"world.kingsward.brann_met": true, "world.kingsward.stake_pulled": true}
	assert_eq(DialogueSession.start_node(b, ctx), "staked", "the Oath-stake pulled: the chains slack")
	ctx.flags = {"boss.hollow.defeated": true}
	assert_eq(DialogueSession.start_node(b, ctx), "fallen", "his fall: the chains drop")
	ctx.flags = {"boss.hollow.defeated": true, "world.kingsward.hollow_told": true}
	assert_eq(DialogueSession.start_node(b, ctx), "after", "and after: laid under the stones")
	var fallen := DialogueSession.node_record(b, "fallen")
	var fx: Dictionary = (fallen.choices[0] as Dictionary).effects
	assert_true(bool((fx.set_flags as Dictionary).get("lead.worldbreaker.heard", false)), "the Worldbreaker's rumour")
	assert_eq(str(fx.outcome), "hollow_fallen", "closes quest.hollow")
	var who := DialogueSession.node_record(b, "who")
	assert_true(JSON.stringify(who.choices).contains("world.kingsward.stake_asked"), "the Oath-stake asked of the giant")


func test_the_saves_hold() -> void:
	var doc := SaveSlots.migrate(JsonIO.read_file(FIXTURE).data)
	assert_eq(SaveSlots.validate(doc), PackedStringArray(), "the E3 fixture validates")
	assert_eq(int(doc.schema_version), 3, "schema 3 (no new field)")
	assert_eq(str(doc.build_version), "0.17.0-m17", "a 0.17 save")
	assert_eq(int(doc.character.growth_stage), 9, "a stage-9 giant")
	assert_eq(int(doc.character.xp), AFTER_E2_XP, "on the guaranteed path after E2")
	var flags: Dictionary = (doc.world.flags as Dictionary).duplicate(true)
	assert_true(bool(flags.get("lead.hollow.heard", false)), "the rumour heard")
	assert_eq(str(flags.get("quest.hollow.stage", "")), "stand", "the Hollow Titan's quest under way")
	var x := ExpansionState.from_doc(doc)
	flags["boss.hollow.defeated"] = true
	flags["boss.hollow.outcome"] = "slain"
	ExpansionState.sync_from_flags(x, flags)
	assert_eq(str((x.titans["titan.hollow"] as Dictionary).state), ExpansionState.STATE_SLAIN, "his fall recorded")
	# the E2 fixture (before this package) still loads with the Hollow Titan unmet
	var old := SaveSlots.migrate(JsonIO.read_file("res://tests/fixtures/saves/v3_m17_e2_cinder_road.json").data)
	assert_eq(SaveSlots.validate(old), PackedStringArray(), "the E2 fixture still validates")
	var ox := ExpansionState.from_doc(old)
	assert_true(str((ox.titans.get("titan.hollow", {}) as Dictionary).get("state", "")) != ExpansionState.STATE_SLAIN,
		"and the Hollow Titan is not slain in it")
