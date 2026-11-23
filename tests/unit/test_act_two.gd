extends TestSuite
## C1: act one's end and act two's start as pure rules (ActTwo) - when the finale is due, the pledges every act-one
## ending gives (Harrok slain, spared or yielded; each oath and how it was won; Skarn and Millford), act two's start
## writing its flags once, the rim council's dialogue built from the pledge table, the save's act following the flag,
## and the act-two quests' and the finale's records.


func _ctx(flags: Dictionary) -> Dictionary:
	return {"flags": flags, "stage": 6, "level": 14, "inventory": {}}


func _answers(flags: Dictionary) -> Dictionary:
	return ActTwo.answers(_ctx(flags))


func test_the_finale_is_due_once_act_one_ends_and_until_act_two_begins() -> void:
	assert_false(ActTwo.due({}), "not before the throne")
	assert_true(ActTwo.due({"campaign.completed": true}), "the throne taken: due")
	assert_false(ActTwo.due({"campaign.completed": true, "act.two.begun": true}), "act two begun: done")
	assert_false(ActTwo.begun({}), "act one by default")


func test_every_ending_branch_gives_its_pledges() -> void:
	var pledges := ActTwo.pledges()
	assert_eq(pledges.size(), 6, "six act-one settlements answer")
	# Harrok: spared and yielded send; slain refuses (his clan will come for the throne)
	for outcome: String in ["spared", "yielded_talk"]:
		assert_eq(str(_answers({"boss.harrok.outcome": outcome}).harrok_clan), "sends", "Harrok %s: his clan sends" % outcome)
	assert_eq(str(_answers({"boss.harrok.outcome": "slain"}).harrok_clan), "refuses", "Harrok slain: his clan refuses")
	# the oaths and how they were won
	assert_eq(str(_answers({"oath.march.done": true, "oath.march.outcome": "help"}).brannock), "sends", "Brannock helped")
	assert_eq(str(_answers({"oath.march.done": true, "oath.march.outcome": "intimidate"}).brannock), "sends", "Brannock's tribute")
	assert_eq(str(_answers({"oath.march.done": true, "oath.march.outcome": "force"}).brannock), "refuses", "Brannock forced")
	assert_eq(str(_answers({}).brannock), "refuses", "no oath, no aid")
	assert_eq(str(_answers({"oath.march.done": true, "oath.march.outcome": "help", "faction.brannock.hostile": true}).brannock),
		"refuses", "a town turned hostile refuses")
	assert_eq(str(_answers({"oath.wood.done": true, "oath.wood.outcome": "slay"}).greywood), "sends", "the wood's oath")
	assert_eq(str(_answers({"oath.crown.done": true, "oath.crown.outcome": "parley"}).aldmere), "sends", "the crown's parley")
	for outcome: String in ["sabotage", "breach"]:
		assert_eq(str(_answers({"oath.crown.done": true, "oath.crown.outcome": outcome}).aldmere), "refuses", "the crown by %s" % outcome)
	assert_eq(str(_answers({"world.skarn.saved": true}).skarn), "sends", "Skarn saved")
	assert_eq(str(_answers({"world.skarn.rebuilt": true}).skarn), "sends", "Skarn rebuilt")
	assert_eq(str(_answers({"world.skarn.burned": true}).skarn), "refuses", "Skarn burned")
	assert_eq(str(_answers({"world.millford.defended": true}).millford), "sends", "Millford defended")
	assert_eq(str(_answers({"world.millford.defended": true, "world.millford.burned": true}).millford), "refuses", "Millford burned")
	for p: Dictionary in pledges:
		assert_true(str(p.sends_line) != "" and str(p.refuses_line) != "", "%s has both lines" % p.id)
		assert_false(str(p.sends_line).contains("Frostbound") or str(p.refuses_line).contains("Worldbreaker"),
			"%s's lines name no later titan" % p.id)


func test_act_two_begins_once_and_writes_its_flags() -> void:
	var flags := {"campaign.completed": true, "boss.harrok.outcome": "spared", "world.skarn.saved": true}
	var setter := func(id: String, value: Variant) -> bool:
		if flags.has(id):
			return false
		flags[id] = value
		return true
	var given := ActTwo.begin(setter, _ctx(flags))
	assert_eq(given.size(), 6, "every pledge answered")
	assert_true(ActTwo.begun(flags), "act.two.begun")
	assert_eq(str(flags["pledge.harrok_clan"]), "sends", "Harrok spared: his clan sends")
	assert_true(bool(flags["pledge.harrok_clan.sends"]), "and its .sends flag")
	assert_eq(str(flags["pledge.brannock"]), "refuses", "Brannock without an oath refuses")
	assert_true(bool(flags["pledge.brannock.refuses"]), "and its .refuses flag")
	flags["boss.harrok.outcome"] = "slain"
	assert_true(ActTwo.begin(setter, _ctx(flags)).is_empty(), "a second start gives nothing")
	assert_eq(str(flags["pledge.harrok_clan"]), "sends", "a pledge never changes once given")
	var written := ActTwo.written_flags()
	for id: String in flags:
		if id.begins_with("pledge.") or id == ActTwo.BEGUN_FLAG:
			assert_true(written.has(id), "%s is among the flags act two's start writes" % id)


func test_the_rim_council_speaks_the_pledge_table() -> void:
	var d := GameData.get_record("dialogue.rim_council")
	assert_false(d.is_empty(), "the council's dialogue ships")
	var nodes := {}
	for n: Dictionary in d.nodes:
		nodes[str(n.id)] = n
	for p: Dictionary in ActTwo.pledges():
		for ans: String in [ActTwo.SENDS, ActTwo.REFUSES]:
			var id := "%s_%s" % [p.id, ans]
			assert_true(nodes.has(id), "the council has %s" % id)
			if nodes.has(id):
				assert_eq(str(nodes[id].text), ActTwo.line_for(p, ans), "%s speaks the table's line" % id)
	var closing := JSON.stringify(d.nodes)
	assert_true(closing.contains("act_two.council_heard"), "hearing them out sets act_two.council_heard")


func test_the_save_act_follows_act_two() -> void:
	var st := ExpansionState.defaults()
	assert_eq(int(st.act), 1, "a new game is in act one")
	ExpansionState.sync_from_flags(st, {"campaign.completed": true})
	assert_eq(int(st.act), 1, "the throne alone leaves act one until act two begins")
	ExpansionState.sync_from_flags(st, {"act.two.begun": true, "pledge.skarn.sends": true})
	assert_eq(int(st.act), 2, "act 2 once it has begun")
	assert_true(bool(st.settlements["poi.skarn"].flags.pledge_sends), "a settlement's pledge is mirrored into its record")
	st.act = 3
	ExpansionState.sync_from_flags(st, {"act.two.begun": true})
	assert_eq(int(st.act), 3, "never lowered")


func test_the_act_two_records() -> void:
	var main := GameData.get_record(ActTwo.MAIN_QUEST)
	assert_eq(str(main.start_conditions[0].flag), ActTwo.BEGUN_FLAG, "act two's thread starts with act two")
	var ids: Array = (main.stages as Array).map(func(s: Dictionary) -> String: return str(s.id))
	assert_eq(ids, ["council", "breach", "grow7", "trials", "grow8", "hoarwatch"], "its stages")
	var finale := GameData.get_record(ActTwo.FINALE_ID)
	var secs := float(finale.ticks) / 60.0
	assert_true(secs >= 20.0 and secs <= 30.0, "the finale runs 20-30 s (%.1f)" % secs)
	assert_eq(str(finale.title.text), "ACT TWO", "it ends on the Act Two card")
	assert_eq(int(GameData.get_record("growth.08").growth_requirement.conditions[1].get("quest", "") == "quest.rim_colossus"), 1,
		"stage 8 waits for the Colossus's Trials until milestone D")
