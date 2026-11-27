extends IntegrationSuite
## E1: Harrok's return as data and story - the branch from act one's outcome (decision E1-5: spared and the talk ending
## stand with the giant; slain, and a save that never settled him, the vengeance), the lead paying off (the look-in at the
## Moot starts Harrok's Return), the quests' XP and the guaranteed path's levels after it (decision E1-7), the reward made
## from one kill (decision E1-6), the dialogues' aftermath and the rumour that leads on, the titan roster's sixth slot
## filled, and the saves: schema 3, the older fixtures and a 0.17 one at the Moot load.

const FIXTURE := "res://tests/fixtures/saves/v3_m17_e1_moot_challenge.json"


func test_the_branch_follows_act_ones_outcome() -> void:
	assert_eq(ThroneChallenge.branch_of("spared"), "ally", "Harrok spared: he stands beside the giant")
	assert_eq(ThroneChallenge.branch_of("yielded_talk"), "ally", "the talk ending: the same")
	assert_eq(ThroneChallenge.branch_of("slain"), "vengeance", "Harrok slain: his clan comes for the throne")
	assert_eq(ThroneChallenge.branch_of(null), "vengeance", "never settled (an old or odd save): the nearest - the vengeance")
	assert_eq(ThroneChallenge.branch_of("fled"), "vengeance", "anything else: the vengeance")


func test_the_lead_pays_off_and_the_quests_xp() -> void:
	var q := GameData.get_record("quest.harrok_return")
	var ctx := QuestConditions.empty_context()
	ctx.flags = {"lead.harrok.seen": true}
	assert_true(QuestConditions.all_hold(q.start_conditions, ctx), "the look-in at the Moot (lead.harrok.seen) starts it")
	var xp := 0
	for s: Dictionary in q.stages:
		xp += int(s.get("xp", 0))
	assert_eq(xp, 700, "its stages: the fight 400, the settling 300")
	assert_eq(int(GameData.get_record("enemy.orrik").xp_reward), 3000, "his kill 3,000")
	# the guaranteed path (Dgate's table at 17,280: level 17) after Harrok's return: 3,700 more
	var after := 17280 + 700 + 3000
	assert_eq(after, 20980, "20,980 XP")
	assert_eq(Progression.level_for_xp(after), 18, "level 18 after Harrok's return")
	assert_eq(Progression.level_for_xp(17280), 17, "level 17 before it")
	assert_eq(Progression.xp_for_level(20) - after, 13970, "13,970 XP left for the Cinder, the Hollow and the Worldbreaker")
	var lead := GameData.get_record("quest.cinder_lead")
	assert_false(lead.is_empty(), "the burning road: a lead")
	assert_eq(int((lead.stages as Array)[0].get("xp", 0)), 0, "a rumour only (no XP, nothing built)")
	assert_false(GameData.get_record("quest.winch_camp").is_empty(), "the preparation's quest")


func test_one_kill_pays_for_the_set_and_the_axe() -> void:
	var have := {}
	for g: Dictionary in GameData.get_record("loot.orrik").guaranteed:
		have[str(g.item)] = int(have.get(str(g.item), 0)) + int(g.count)
	for p: Dictionary in GameData.get_record("enemy.orrik").plates:
		if str(p.id) in ["helm", "greaves"]:   # (two plates broken: the bot breaks these in every duel)
			for l: Dictionary in p.get("loot", []):
				have[str(l.item)] = int(have.get(str(l.item), 0)) + int(l.count)
	have["item.titan_iron"] = 1
	var need := {}
	for r: Dictionary in GameData.records_of_type("recipe"):
		if str(r.get("works", "")) == "skarn_iron" and str(r.makes) != "armour.harrok_oath_ring":
			for c: Dictionary in r.cost:
				need[str(c.item)] = int(need.get(str(c.item), 0)) + int(c.count)
	for item: String in need:
		assert_true(int(have.get(item, 0)) >= int(need[item]), "%s: %d needed, %d from one kill" % [item, int(need[item]),
			int(have.get(item, 0))])
	assert_eq(Armour.set_pieces("armour_set.fetterer").size(), 7, "the Fetterer's set: six pieces and Harrok's ring")
	assert_true(str(GameData.get_record("weapon.heir_axe").get("perk", {}).get("kind", "")) == "flat_penetration",
		"the Heir's Axe bites through armour")


func test_the_aftermath_dialogues() -> void:
	var oath := GameData.get_record("dialogue.moot_oath")
	var ctx := QuestConditions.empty_context()
	ctx.flags = {"boss.harrok.outcome": "slain", "boss.orrik.defeated": true}
	assert_eq(DialogueSession.start_node(oath, ctx), "knelt", "Harrok slain, Orrik down: the clan kneels")
	ctx.flags = {"boss.harrok.outcome": "spared", "boss.orrik.defeated": true}
	assert_eq(DialogueSession.start_node(oath, ctx), "harrok_speaks", "Harrok spared: he speaks for the clan")
	var h := GameData.get_record("dialogue.harrok")
	ctx.flags = {"boss.harrok.outcome": "spared", "lead.harrok.hearth": true}
	assert_eq(DialogueSession.start_node(h, ctx), "orrik_comes", "Harrok tells of Orrik")
	ctx.flags = {"boss.harrok.outcome": "spared", "lead.harrok.hearth": true, "boss.orrik.defeated": true}
	assert_eq(DialogueSession.start_node(h, ctx), "holds_won", "after the fight he holds the Moot")
	ctx.flags = {"boss.harrok.outcome": "spared", "boss.orrik.defeated": true, "world.moot.settled": true}
	assert_eq(DialogueSession.start_node(h, ctx), "holds", "and after")
	ctx.flags = {"boss.harrok.outcome": "spared"}
	assert_eq(DialogueSession.start_node(h, ctx), "spared", "before the rumour: act one's words")
	for d: Dictionary in [oath, h]:
		var said := false
		for n: Dictionary in d.nodes:
			for c: Dictionary in n.get("choices", []):
				var fx: Dictionary = c.get("effects", {})
				if str(fx.get("outcome", "")) == "moot_settled":
					said = true
					assert_true(bool((fx.get("set_flags", {}) as Dictionary).get("lead.cinder.heard", false)),
						"%s: the rumour of the burning road" % d.id)
		assert_true(said, "%s settles the Moot" % d.id)


func test_the_roster_names_him_sixth() -> void:
	var roster: Array = GameData.get_record("titan_roster.signature").titans
	var r: Dictionary = roster.filter(func(t: Dictionary) -> bool: return str(t.id) == "titan.harrok")[0]
	assert_eq(str(r.enemy), "enemy.orrik", "Harrok's slot: Orrik the Fetterer")
	assert_eq(str(r.defeated_flag), "boss.orrik.defeated", "his fall recorded")


func test_the_saves_hold() -> void:
	for f: String in ["v3_m15_campaign_complete.json", "v3_m16_d2_storm_lead.json", "v3_m16_d3_stage9.json",
			"v3_m17_dgate_stage9.json", "v3_m17_e1_moot_challenge.json"]:
		var doc := SaveSlots.migrate(JsonIO.read_file("res://tests/fixtures/saves/" + f).data)
		assert_eq(SaveSlots.validate(doc), PackedStringArray(), "%s validates" % f)
		assert_eq(int(doc.schema_version), 3, "%s: schema 3" % f)
	var e1 := SaveSlots.migrate(JsonIO.read_file(FIXTURE).data)
	assert_eq(str(e1.build_version), "0.17.0-m17", "a 0.17 save")
	var flags: Dictionary = (e1.world.flags as Dictionary).duplicate(true)
	assert_eq(str(flags.get("quest.harrok_return.stage", "")), "answer", "Harrok's Return under way")
	assert_eq(ThroneChallenge.branch_of(flags.get("boss.harrok.outcome")), "ally", "Harrok spared in it")
	assert_eq(int(e1.character.growth_stage), 9, "a stage-9 giant")
	var x := ExpansionState.from_doc(e1)
	flags["boss.orrik.defeated"] = true
	flags["boss.orrik.outcome"] = "slain"
	ExpansionState.sync_from_flags(x, flags)
	assert_eq(str((x.titans["titan.harrok"] as Dictionary).state), ExpansionState.STATE_SLAIN, "his fall recorded")
	assert_false(flags.has("fetters"), "the chains are never saved")
