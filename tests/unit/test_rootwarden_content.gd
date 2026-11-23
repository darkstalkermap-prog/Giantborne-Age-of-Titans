extends TestSuite
## B3: the Rootwarden's content as records: Wren's words in every order of the Greywood's story (the Matriarch
## holding her den, slain, driven out; the call; his rest) and the quest stages they move; his territory's sleeping
## rules as data (the grove discovered, not woken, by sight; engaged only after the call); the roster's record and an
## old save's sync from his flags (Hollowmere's two changes); his loot and a broken plate's own; the Warden set at a
## forge that works warden wood once he is at rest, and its regrowth perk; his intro and the prompts that teach him.

const WARDEN := "enemy.rootwarden"
const WREN := "dialogue.woodwright_wren"


func _start(flags: Dictionary) -> String:
	var ctx := QuestConditions.empty_context()
	ctx.flags = flags
	return DialogueSession.start_node(GameData.get_record(WREN), ctx)


func _told() -> String:
	return QuestConditions.outcome_flag(WREN, "told")


func _effects_of(node: String) -> Dictionary:
	var n := DialogueSession.node_record(GameData.get_record(WREN), node)
	for c: Dictionary in n.get("choices", []):
		if c.has("effects"):
			return c.effects
	return {}


func test_wrens_words_follow_the_matriarchs_fate() -> void:
	assert_eq(_start({}), "greet", "first met: who she is")
	var told := {_told(): true}
	assert_eq(_start(told), "told_again", "the Matriarch in her den: the blight first")
	var slain := told.duplicate()
	slain["boss.matriarch.outcome"] = "slain"
	assert_eq(_start(slain), "call_slain", "she is slain: the elders call the giant")
	var fled := told.duplicate()
	fled["boss.matriarch.outcome"] = "fled"
	assert_eq(_start(fled), "call_fled", "she was driven out and spared: another call, its own words")
	assert_true(str(DialogueSession.node_record(GameData.get_record(WREN), "call_slain").text) !=
		str(DialogueSession.node_record(GameData.get_record(WREN), "call_fled").text), "two texts")
	var untold := {"boss.matriarch.outcome": "slain"}
	assert_eq(_start(untold), "greet", "the Matriarch dead but Wren never asked: she tells him first")
	for node: String in ["call_slain", "call_fled"]:
		var fx := _effects_of(node)
		assert_eq(str(fx.get("outcome", "")), "called", "%s: the call" % node)
		var sf: Dictionary = fx.get("set_flags", {})
		assert_true(bool(sf.get("world.rootwarden.called", false)), "%s: entering his hollow will wake him" % node)
		assert_true(bool(sf.get("world.rootwarden.resin_laid", false)), "%s: the resin pots laid" % node)
		assert_true(str(fx.get("once_flag", "")) != "", "%s: its reward once" % node)
	var called := slain.duplicate()
	called["world.rootwarden.called"] = true
	called[QuestConditions.outcome_flag(WREN, "called")] = true
	assert_eq(_start(called), "called_again", "called: what to do")
	var struck := {"boss.rootwarden.defeated": true}
	assert_eq(_start(struck), "rested", "laid to rest without the call (struck alone): her thanks all the same")
	called["boss.rootwarden.defeated"] = true
	assert_eq(_start(called), "rested", "after the call: her thanks")
	called[QuestConditions.outcome_flag(WREN, "rested")] = true
	assert_eq(_start(called), "after", "and after")


func test_the_quest_stages_in_every_order() -> void:
	var q := GameData.get_record("quest.rootwarden")
	var ids := []
	var by := {}
	for s: Dictionary in q.stages:
		ids.append(str(s.id))
		by[str(s.id)] = s
	assert_eq(ids, ["look", "wren", "blight", "call", "rest", "thanks"], "the stages")
	var holds := func(stage: String, flags: Dictionary) -> bool:
		var ctx := QuestConditions.empty_context()
		ctx.flags = flags
		return QuestConditions.holds(by[stage].complete_when, ctx)
	assert_false(holds.call("blight", {}), "the blight stands while the Matriarch holds her den")
	assert_true(holds.call("blight", {"boss.matriarch.outcome": "slain"}), "lifted by her death")
	assert_true(holds.call("blight", {"boss.matriarch.outcome": "fled"}), "or her flight")
	var dead := {"boss.rootwarden.defeated": true}
	for s: String in ["look", "wren", "blight", "call", "rest"]:
		assert_true(holds.call(s, dead), "%s: his rest completes it (the giant went straight to him)" % s)
	assert_false(holds.call("thanks", dead), "only Wren's thanks is left")
	var start_ctx := QuestConditions.empty_context()
	start_ctx.flags = {_told(): true}
	assert_true(QuestConditions.all_hold(q.start_conditions, start_ctx), "Wren's words start it")
	start_ctx.flags = {QuestConditions.outcome_flag("dialogue.sedge", "warden"): true}
	assert_true(QuestConditions.all_hold(q.start_conditions, start_ctx), "and Sedge's")


func test_his_territory_sleeps() -> void:
	var gw := JsonIO.read_file("res://tools/data/world/greywood.json").data as Dictionary
	var terr := {}
	for el: Dictionary in gw.elements:
		if str(el.get("id", "")) == "world.greywood.rootwarden_territory":
			terr = el
	assert_false(terr.is_empty(), "his territory")
	assert_false(bool(terr.get("wake_on_sight", true)), "sight does not wake him")
	assert_eq(str(terr.get("wake_flag", "")), "world.rootwarden.called", "his hollow wakes him only after the call")
	assert_eq(str(terr.get("reopened_flag", "")), "world.greywood.grove_greened", "the grove greens after his rest")
	assert_eq(str(terr.get("discover_poi", "")), "poi.rootwarden_grove", "seen: the grove")
	var rec := GameData.get_record(WARDEN)
	assert_true(bool(rec.dormant), "he sleeps")
	assert_eq(int(rec.rooted_until_phase), 2, "rooted till he tears himself up")


func test_the_roster_and_an_old_save_know_him() -> void:
	var e := ExpansionState.roster_entry("titan.rootwarden")
	assert_eq(str(e.get("enemy", "")), WARDEN, "his enemy record")
	assert_near(float(e.get("height_m", 0.0)), 21.3, 1e-6, "his height (70 ft)")
	assert_eq(ExpansionState.titan_for("world.greywood.rootwarden"), "titan.rootwarden", "his boss id")
	assert_eq(ExpansionState.titan_for(WARDEN), "titan.rootwarden", "his record")
	assert_eq(str(GameSession.TITAN_INTROS.get("titan.rootwarden", "")), "cutscene.rootwarden", "his intro on his wake")
	# a save from before B3: no record, nothing
	var before := ExpansionState.defaults()
	ExpansionState.sync_from_flags(before, {"boss.matriarch.outcome": "slain"})
	assert_false(before.titans.has("titan.rootwarden"), "not met")
	# his grove seen: sighted
	var seen := ExpansionState.defaults()
	ExpansionState.sync_from_flags(seen, {Discovery.discovered_flag("poi.rootwarden_grove"): true})
	assert_eq(str((seen.titans.get("titan.rootwarden", {}) as Dictionary).get("state", "")), ExpansionState.STATE_SIGHTED,
		"his grove discovered: sighted")
	# at rest: slain, his drops, Hollowmere's changes
	var st := ExpansionState.defaults()
	ExpansionState.sync_from_flags(st, {"boss.rootwarden.defeated": true, "world.greywood.grove_greened": true})
	var t: Dictionary = st.titans.get("titan.rootwarden", {})
	assert_eq(str(t.get("state", "")), ExpansionState.STATE_SLAIN, "slain")
	assert_false((t.get("drops", []) as Array).is_empty(), "his drops")
	var hf: Dictionary = ((st.settlements.get("poi.hollowmere", {}) as Dictionary).get("flags", {}) as Dictionary)
	assert_true(bool(hf.get("warden_rested", false)) and bool(hf.get("grove_greened", false)), "Hollowmere's two changes")


func test_his_loot() -> void:
	var by := {}
	for d: Dictionary in ExpansionState.loot_of("loot.rootwarden"):
		by[str(d.item)] = int(d.count)
	assert_eq(by, {"item.warden_heartwood": 1, "item.warden_bark": 4, "item.amber_sap": 3}, "heartwood, bark, sap")
	var rec := GameData.get_record(WARDEN)
	var extra := PlateRules.break_loot(rec, ["shoulder_l", "knot"])
	assert_false(extra.is_empty(), "a broken plate adds its own")
	for id: String in ["item.warden_heartwood", "item.warden_bark", "item.amber_sap"]:
		assert_false(GameData.get_record(id).is_empty(), "%s is an item" % id)


func test_the_warden_set_is_made_where_warden_wood_is_worked() -> void:
	var srec := Armour.set_record("armour_set.warden")
	assert_eq(str(srec.get("works", "")), "warden_wood", "its trait")
	var pieces := Armour.set_pieces("armour_set.warden")
	assert_eq(pieces.size(), 4, "four pieces")
	var meshed := 0
	for id: Variant in pieces:
		var rec := Armour.piece(str(id))
		if not ((rec.get("look", {}) as Dictionary).get("meshes", []) as Array).is_empty():
			meshed += 1
	assert_eq(meshed, 4, "mantle, bracers, greaves and the heartwood amulet modelled")
	var made := 0
	for r: Dictionary in GameData.records_of_type("recipe"):
		if str(r.get("makes", "")).begins_with("armour.warden_"):
			made += 1
			assert_eq(str(r.get("works", "")), "warden_wood", "%s needs the trait" % r.id)
			assert_eq(str(r.get("requires_flag", "")), "boss.rootwarden.defeated", "%s waits for his rest" % r.id)
	assert_eq(made, 4, "a recipe a piece")
	var gw := JsonIO.read_file("res://tools/data/world/greywood.json").data as Dictionary
	var forge := {}
	for el: Dictionary in gw.elements:
		if str(el.get("id", "")) == "world.greywood.hollowmere_woodwright":
			forge = el
	assert_false(forge.is_empty(), "Wren's woodworks at Hollowmere")
	assert_true(JSON.stringify(forge).contains("warden_wood"), "works warden wood")
	var all := Armour.stats(Armour.equipment_with(pieces))
	assert_true(float(all.less_pct) > 0.0, "it protects (%.1f %%)" % float(all.less_pct))


func test_the_regrowth_perk_heals_a_giant_out_of_the_fight() -> void:
	var pp := Combatant.PassivePools.new()
	pp.health_max = 1000.0
	pp.health = 500.0
	pp.regrow_frac_s = 0.003
	pp.since_damage = 0.0
	for i in 180:
		pp.tick(1.0 / 60.0, true)
	assert_near(pp.health, 500.0, 1e-6, "not within 4 s of a blow")
	for i in 600:
		pp.tick(1.0 / 60.0, true)
	# 13 s since the blow: 9 s of growth at 3 a second
	assert_true(pp.health > 500.0 + 24.0 and pp.health < 500.0 + 30.0, "then 0.3 %% a second (%.1f)" % pp.health)
	pp.damage_health(50.0)
	var after := pp.health
	pp.tick(1.0 / 60.0, true)
	assert_near(pp.health, after, 1e-6, "a blow stops it again")
	var plain := Combatant.PassivePools.new()
	plain.health_max = 1000.0
	plain.health = 500.0
	for i in 600:
		plain.tick(1.0 / 60.0, true)
	assert_near(plain.health, 500.0, 1e-6, "without the perk: nothing")


func test_his_intro_and_the_prompts() -> void:
	var c := GameData.get_record("cutscene.rootwarden")
	var s := CutsceneRules.seconds_of(c)
	assert_true(s >= 10.0 and s <= 15.0, "10-15 s: %.1f" % s)
	var kinds := []
	for a: Dictionary in c.actors:
		kinds.append(str(a.kind))
	assert_true(kinds.has("rootwarden") and kinds.has("giant"), "his model and the giant")
	var sleep := GameData.get_record("tutorial.rootwarden_dormant")
	assert_true((sleep.get("unless_flags", []) as Array).has("boss.rootwarden.defeated"), "never after his rest")
	var regrow := GameData.get_record("tutorial.rootwarden_regrow")
	assert_eq(str((regrow.trigger as Dictionary).event), "plate_regrowing", "when his bark grows back")
	assert_true(DataValidator.TUTORIAL_EVENTS.has("plate_regrowing"), "a tutorial event")


## His loot, one bark plate broken in the fight and Wren's thanks pay for the whole set.
func test_one_rest_pays_for_the_set() -> void:
	var have := {}
	for d: Dictionary in ExpansionState.loot_of("loot.rootwarden"):
		have[str(d.item)] = int(have.get(str(d.item), 0)) + int(d.count)
	for d: Dictionary in PlateRules.break_loot(GameData.get_record(WARDEN), ["shin_l"]):
		have[str(d.item)] = int(have.get(str(d.item), 0)) + int(d.count)
	var thanks := _effects_of("rested")
	for g: Dictionary in thanks.get("give_items", []):
		have[str(g.item)] = int(have.get(str(g.item), 0)) + int(g.count)
	var need := {}
	for r: Dictionary in GameData.records_of_type("recipe"):
		if str(r.get("makes", "")).begins_with("armour.warden_"):
			for c: Dictionary in r.cost:
				need[str(c.item)] = int(need.get(str(c.item), 0)) + int(c.count)
	for item: String in need:
		assert_true(int(have.get(item, 0)) >= int(need[item]), "%s: %d of %d" % [item, int(have.get(item, 0)),
			int(need[item])])
