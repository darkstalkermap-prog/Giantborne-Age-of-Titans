extends IntegrationSuite
## E2: the Cinder Titan's story in data (default tier): the lead E1 left pays off (quest.cinder starts on it), the
## preparation is optional XP only, the XP path (decision E2-6: 6,980 of the 13,970 left - the guaranteed path at level
## 19 after him, 6,990 left for the Hollow Titan so stage 10 stands at level 20 before the Worldbreaker), one kill pays for
## the Cinder set and the Cinder-maul, Ysolde's words follow the fight, the Hollow Titan is a rumour only (0 XP, nothing
## built), the roster's seventh slot, the reward's numbers, and the saves (a 0.17 fixture on the road to the Ashfell:
## tests/fixtures/saves/v3_m17_e2_cinder_road.json).

const FIXTURE := "res://tests/fixtures/saves/v3_m17_e2_cinder_road.json"
## The guaranteed path after E1 (docs/systems/E1.md section 6) and level 20's XP.
const AFTER_E1_XP := 20980
const LEVEL_20_XP := 34950


func _stage_xp(quest_id: String) -> int:
	var total := 0
	for s: Dictionary in GameData.get_record(quest_id).get("stages", []):
		total += int(s.get("xp", 0))
	return total


func test_the_lead_pays_off_and_the_hollow_titan_is_a_rumour() -> void:
	var q := GameData.get_record("quest.cinder")
	assert_false(q.is_empty(), "quest.cinder exists")
	var starts := JSON.stringify(q.get("start_conditions", []))
	assert_true(starts.contains("lead.cinder.heard"), "it starts on E1's rumour of the burning road")
	var lead := GameData.get_record("quest.hollow_lead")
	assert_eq(_stage_xp("quest.hollow_lead"), 0, "the Hollow Titan: a lead only, 0 XP")
	assert_true(JSON.stringify(lead.start_conditions).contains("lead.hollow.heard"), "on Ysolde's tale")
	# (E3 built the Hollow Titan behind the lead: tests/integration/test_e3_story.gd holds his own story's data)
	assert_eq(str(GameData.get_record("quest.hollow").get("start_conditions", [])).contains("lead.hollow.heard"), true,
		"E3: the lead pays off in quest.hollow")
	var roster: Array = GameData.get_record("titan_roster.signature").titans
	var r: Dictionary = roster.filter(func(t: Dictionary) -> bool: return str(t.id) == "titan.cinder")[0]
	assert_eq(str(r.enemy), "enemy.cinder", "the seventh slot: the Cinder Titan")
	assert_eq(str(r.defeated_flag), "boss.cinder.defeated", "his fall recorded")
	var h: Dictionary = roster.filter(func(t: Dictionary) -> bool: return str(t.id) == "titan.hollow")[0]
	assert_eq(str(h.get("enemy", "")), "enemy.hollow", "E3: the Hollow Titan's slot filled")


func test_the_xp_path() -> void:
	var kill := int(GameData.get_record("enemy.cinder").xp_reward)
	var poi := int(GameData.get_record("poi.ember_hollow").xp)
	var quest := _stage_xp("quest.cinder")
	assert_eq(kill, 5600, "his kill")
	assert_eq(poi + quest + kill, 6980, "his share of the 13,970 left after E1 (decision E2-6)")
	var after := AFTER_E1_XP + poi + quest + kill
	assert_eq(Progression.level_for_xp(after), 19, "the guaranteed path at level 19 after him (%d XP)" % after)
	assert_eq(LEVEL_20_XP - after, 6990, "6,990 left for the Hollow Titan: stage 10 at level 20 before the Worldbreaker")
	assert_eq(Progression.level_for_xp(LEVEL_20_XP), 20, "level 20 at 34,950")
	assert_eq(_stage_xp("quest.cinder_dam"), 250, "the preparation: optional XP only")
	assert_false(JSON.stringify(GameData.get_record("quest.cinder").stages).contains("dammed"),
		"the fight's quest never asks for the preparation")


func test_one_kill_pays_for_the_set_and_the_maul() -> void:
	var have := {}
	for e: Dictionary in GameData.get_record("loot.cinder").guaranteed:
		have[str(e.item)] = int(have.get(str(e.item), 0)) + int(e.count)
	# two plates broken (the heart-coal and the crown) add their own
	for p: Dictionary in GameData.get_record("enemy.cinder").plates:
		if str(p.id) in ["heart", "crown"]:
			for e: Dictionary in p.get("loot", []):
				have[str(e.item)] = int(have.get(str(e.item), 0)) + int(e.count)
	have["item.iron_ingot"] = 99
	have["item.titan_iron"] = 99
	var need := {}
	for rid: String in ["recipe.cinder_helm", "recipe.cinder_pauldrons", "recipe.cinder_coat", "recipe.cinder_vambraces",
			"recipe.cinder_greaves", "recipe.cinder_heartcoal", "recipe.cinder_maul"]:
		var rec := GameData.get_record(rid)
		assert_false(rec.is_empty(), "%s exists" % rid)
		assert_eq(str(rec.get("requires_flag", "")), "boss.cinder.defeated", "%s once he has fallen" % rid)
		assert_eq(str(rec.get("works", "")), "cinder_slag", "%s at Last Hearth's titan forges" % rid)
		for e: Dictionary in rec.get("cost", []):
			need[str(e.item)] = int(need.get(str(e.item), 0)) + int(e.count)
	for item: String in need:
		assert_true(int(have.get(item, 0)) >= int(need[item]), "%s: %d needed, %d from one kill" % [item, int(need[item]),
			int(have.get(item, 0))])
	assert_eq(Armour.set_pieces("armour_set.cinder").size(), 6, "the Cinder set: six pieces")
	var maul := GameData.get_record("weapon.cinder_maul")
	assert_eq(str(maul.perk.kind), "sear", "the Cinder-maul's heavies sear")
	assert_eq(int(maul.fit_max_stage), 10, "it fits a colossus to the last stage")


func test_ysolde_follows_the_fight() -> void:
	var y := GameData.get_record("dialogue.ashfell_ysolde")
	var ctx := QuestConditions.empty_context()
	ctx.flags = {}
	assert_eq(DialogueSession.start_node(y, ctx), "greet", "before: what walks at the road's head")
	ctx.flags = {"world.ashfell.spur_asked": true}
	assert_eq(DialogueSession.start_node(y, ctx), "watch", "asked: how he is fought")
	ctx.flags = {"world.ashfell.spur_asked": true, "world.ashfell.dammed": true}
	assert_eq(DialogueSession.start_node(y, ctx), "dammed", "the Spur thrown down: the pit fills")
	ctx.flags = {"boss.cinder.defeated": true}
	assert_eq(DialogueSession.start_node(y, ctx), "fallen", "his fall: the fires go out")
	ctx.flags = {"boss.cinder.defeated": true, "world.ashfell.cinder_told": true}
	assert_eq(DialogueSession.start_node(y, ctx), "after", "and after: Thornstead rebuilding")
	var fallen := DialogueSession.node_record(y, "fallen")
	var fx: Dictionary = (fallen.choices[0] as Dictionary).effects
	assert_true(bool((fx.set_flags as Dictionary).get("lead.hollow.heard", false)), "the empty king's rumour")
	assert_eq(str(fx.outcome), "cinder_fallen", "closes quest.cinder")


func test_the_heat_meter_keys_and_the_set_passive() -> void:
	var set := GameData.get_record("armour_set.cinder")
	var mult := 1.0
	for b: Dictionary in set.bonuses:
		mult *= float((b.modifiers as Dictionary).get("heat_taken_mult", 1.0))
	assert_near(mult, 0.45, 0.001, "the whole set: heat takes 45% hold")
	assert_true(DataValidator.STATUS_MODIFIERS.has("heat_taken_mult"), "a passive the armour may carry")


func test_the_saves_hold() -> void:
	var doc := SaveSlots.migrate(JsonIO.read_file(FIXTURE).data)
	assert_eq(SaveSlots.validate(doc), PackedStringArray(), "the E2 fixture validates")
	assert_eq(int(doc.schema_version), 3, "schema 3 (no new field)")
	assert_eq(str(doc.build_version), "0.17.0-m17", "a 0.17 save")
	assert_eq(int(doc.character.growth_stage), 9, "a stage-9 giant")
	assert_eq(int(doc.character.xp), AFTER_E1_XP, "on the guaranteed path after E1")
	var flags: Dictionary = (doc.world.flags as Dictionary).duplicate(true)
	assert_true(bool(flags.get("lead.cinder.heard", false)), "the rumour heard")
	assert_eq(str(flags.get("quest.cinder.stage", "")), "reach", "the Cinder Titan's quest under way")
	assert_false(flags.has("heat"), "the heat is never saved")
	var x := ExpansionState.from_doc(doc)
	flags["boss.cinder.defeated"] = true
	flags["boss.cinder.outcome"] = "slain"
	ExpansionState.sync_from_flags(x, flags)
	assert_eq(str((x.titans["titan.cinder"] as Dictionary).state), ExpansionState.STATE_SLAIN, "his fall recorded")
