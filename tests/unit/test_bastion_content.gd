extends TestSuite
## C2: the Broken Warden's content as records: Hode's words before and after his fall and the quest stages they move;
## his territory's sleeping rules as data (the keep discovered, not woken, by sight; his yard reopened after his fall);
## the roster's record and an old save's sync from his flags (the toll fort's two changes); his loot and a broken
## plate's own; the Bastion set and the Gate-bar at a forge that works warden stone once he has fallen; the prompts
## that teach him; one fall pays for the set.

const WARDEN := "enemy.bastion"
const HODE := "dialogue.toll_keeper_hode"


func _start(flags: Dictionary) -> String:
	var ctx := QuestConditions.empty_context()
	ctx.flags = flags
	return DialogueSession.start_node(GameData.get_record(HODE), ctx)


func _effects_of(node: String) -> Dictionary:
	var n := DialogueSession.node_record(GameData.get_record(HODE), node)
	for c: Dictionary in n.get("choices", []):
		if c.has("effects"):
			return c.effects
	return {}


func _aldmere(id: String) -> Dictionary:
	var al := JsonIO.read_file("res://tools/data/world/aldmere.json").data as Dictionary
	for el: Dictionary in al.elements:
		if str(el.get("id", "")) == id:
			return el
	return {}


func test_hodes_words_follow_the_warden() -> void:
	assert_eq(_start({}), "greet", "first met: who he is")
	var told := {QuestConditions.outcome_flag(HODE, "told"): true}
	assert_eq(_start(told), "told_again", "told: how to fight him")
	var fallen := {"boss.bastion.defeated": true}
	assert_eq(_start(fallen), "fallen", "fallen (whether Hode told the giant or not): his thanks")
	var fx := _effects_of("fallen")
	assert_eq(str(fx.get("outcome", "")), "fallen", "the outcome")
	assert_true(str(fx.get("once_flag", "")) != "", "its reward once")
	fallen[QuestConditions.outcome_flag(HODE, "fallen")] = true
	assert_eq(_start(fallen), "after", "and after")
	var advice := ""
	for node: String in ["how", "keep"]:
		advice += str(DialogueSession.node_record(GameData.get_record(HODE), node).text).to_lower()
	for word: String in ["back", "right side", "hard enough", "towers", "greaves", "charge"]:
		assert_true(advice.contains(word), "Hode's advice names the way in: %s" % word)


func test_the_quest_stages() -> void:
	var q := GameData.get_record("quest.bastion")
	var ids := []
	var by := {}
	for s: Dictionary in q.stages:
		ids.append(str(s.id))
		by[str(s.id)] = s
	assert_eq(ids, ["hode", "slay", "road"], "the stages")
	var holds := func(stage: String, flags: Dictionary) -> bool:
		var ctx := QuestConditions.empty_context()
		ctx.flags = flags
		return QuestConditions.holds(by[stage].complete_when, ctx)
	assert_false(holds.call("slay", {}), "he stands")
	var dead := {"boss.bastion.defeated": true}
	assert_true(holds.call("hode", dead), "his fall completes Hode's stage (the giant went straight to him)")
	assert_true(holds.call("slay", dead), "and the fight's")
	assert_false(holds.call("road", dead), "only Hode's thanks is left")


func test_his_territory_sleeps_and_his_yard_opens_after() -> void:
	var terr := _aldmere("world.aldmere.warden_territory")
	assert_false(terr.is_empty(), "his territory")
	assert_false(bool(terr.get("wake_on_sight", true)), "sight does not wake him")
	assert_eq(str(terr.get("reopened_flag", "")), "world.warden_keep.opened", "the keep opens after his fall")
	assert_eq(str(terr.get("discover_poi", "")), "poi.warden_keep", "seen: the keep")
	var rec := GameData.get_record(WARDEN)
	assert_true(bool(rec.dormant), "he sleeps")
	var post := _aldmere("world.aldmere.warden_warning")
	assert_false(post.is_empty(), "a warning post on the road up to him")
	var forge := _aldmere("world.aldmere.warden_keep_forge")
	assert_true(JSON.stringify(forge).contains("warden_stone"), "the keep's forge works warden stone")
	assert_true(JSON.stringify(forge.get("open_when", "")).contains("boss.bastion.defeated"), "once he has fallen")
	var towers := 0
	for el: Dictionary in (JsonIO.read_file("res://tools/data/world/aldmere.json").data as Dictionary).elements:
		if str(el.get("kind", "")) == "rubble_tower":
			towers += 1
			var flat := Vector2(float(el.pos[0]) - 706.0, float(el.pos[1]) - 189.0).length()
			assert_true(flat <= float(rec.rubble.radius_m), "%s within his rubble's reach of his post (%.1f m)" % [el.id, flat])
	assert_eq(towers, 2, "two crumbling towers in his breach")


func test_the_roster_and_an_old_save_know_him() -> void:
	var e := ExpansionState.roster_entry("titan.bastion")
	assert_eq(str(e.get("display_name", "")), "The Bastion Titan", "the story's name")
	assert_eq(str(e.get("enemy", "")), WARDEN, "his enemy record")
	assert_near(float(e.get("height_m", 0.0)), 22.4, 1e-6, "his height (73.5 ft)")
	assert_eq(ExpansionState.titan_for("world.aldmere.bastion"), "titan.bastion", "his boss id")
	assert_eq(ExpansionState.titan_for(WARDEN), "titan.bastion", "his record")
	var before := ExpansionState.defaults()
	ExpansionState.sync_from_flags(before, {"quest.kingsroad_toll.done": true, "world.toll_fort.breached": true})
	assert_false(before.titans.has("titan.bastion"), "the fort's content done: not met")
	var seen := ExpansionState.defaults()
	ExpansionState.sync_from_flags(seen, {Discovery.discovered_flag("poi.warden_keep"): true})
	assert_eq(str((seen.titans.get("titan.bastion", {}) as Dictionary).get("state", "")), ExpansionState.STATE_SIGHTED,
		"his keep discovered: sighted")
	var st := ExpansionState.defaults()
	ExpansionState.sync_from_flags(st, {"boss.bastion.defeated": true, "world.warden_keep.opened": true})
	var t: Dictionary = st.titans.get("titan.bastion", {})
	assert_eq(str(t.get("state", "")), ExpansionState.STATE_SLAIN, "slain")
	assert_false((t.get("drops", []) as Array).is_empty(), "his drops")
	var tf: Dictionary = ((st.settlements.get("poi.toll_fort", {}) as Dictionary).get("flags", {}) as Dictionary)
	assert_true(bool(tf.get("warden_fallen", false)) and bool(tf.get("keep_opened", false)), "the toll fort's two changes")


func test_his_loot() -> void:
	var by := {}
	for d: Dictionary in ExpansionState.loot_of("loot.bastion"):
		by[str(d.item)] = int(d.count)
	assert_eq(by, {"item.warden_keystone": 1, "item.warden_ashlar": 4, "item.gate_iron": 4}, "keystone, ashlar, iron")
	assert_eq(int(GameData.get_record("item.warden_keystone").stack_max), 1, "the keystone a trophy")
	var extra := PlateRules.break_loot(GameData.get_record(WARDEN), ["shield", "greave_l"])
	assert_eq(extra.size(), 2, "the shield's iron and the greave's stone")


func test_the_bastion_set_and_the_gate_bar() -> void:
	var srec := Armour.set_record("armour_set.bastion")
	assert_eq(str(srec.get("works", "")), "warden_stone", "its trait")
	var pieces := Armour.set_pieces("armour_set.bastion")
	assert_eq(pieces.size(), 7, "seven pieces")
	var slots := {}
	var meshed := 0
	for id: Variant in pieces:
		var rec := Armour.piece(str(id))
		slots[str(rec.slot)] = true
		if not ((rec.get("look", {}) as Dictionary).get("meshes", []) as Array).is_empty():
			meshed += 1
	assert_eq(slots.size(), 7, "every slot (no new slot)")
	assert_eq(meshed, 7, "all seven drawn on the giant")
	var made := 0
	for r: Dictionary in GameData.records_of_type("recipe"):
		var makes := str(r.get("makes", ""))
		if makes.begins_with("armour.bastion_") or makes == "weapon.gate_bar":
			made += 1
			assert_eq(str(r.get("works", "")), "warden_stone", "%s needs the trait" % r.id)
			assert_eq(str(r.get("requires_flag", "")), "boss.bastion.defeated", "%s waits for his fall" % r.id)
	assert_eq(made, 8, "a recipe a piece and the bar's")
	var all := Armour.stats(Armour.equipment_with(pieces))
	assert_true(float(all.less_pct) > 0.0, "it protects (%.1f %%)" % float(all.less_pct))
	var m := Armour.modifiers(Armour.equipment_with(pieces))
	assert_near(float((m.modifiers as Dictionary).get("block_stamina_mult", 1.0)), 0.6, 1e-6, "four pieces: a cheaper block")
	assert_true(Talents.KEY_TEXT.has("block_stamina_mult"), "a modifier the menus can name")
	var bar := GameData.get_record("weapon.gate_bar")
	assert_false(bar.is_empty(), "the Gate-bar")
	assert_eq(str(bar.get("slot", "weapon")), "weapon", "in the weapon's slot")


func test_the_prompts_that_teach_him() -> void:
	var warn := GameData.get_record("tutorial.bastion_warning")
	assert_true((warn.get("unless_flags", []) as Array).has("boss.bastion.defeated"), "never after his fall")
	var guard := GameData.get_record("tutorial.bastion_guard")
	assert_eq(str((guard.trigger as Dictionary).event), "titan_guard_broken", "when his guard first breaks")
	assert_true(DataValidator.TUTORIAL_EVENTS.has("titan_guard_broken"), "a tutorial event")


## His loot, the shield (always: he throws it down at 35 % if it is not broken first), two plates of stone broken in
## the fight and Hode's thanks pay for the whole set.
func test_one_fall_pays_for_the_set() -> void:
	var have := {"item.iron_ingot": 2}
	for d: Dictionary in ExpansionState.loot_of("loot.bastion"):
		have[str(d.item)] = int(have.get(str(d.item), 0)) + int(d.count)
	for d: Dictionary in PlateRules.break_loot(GameData.get_record(WARDEN), ["shield", "greave_l", "greave_r"]):
		have[str(d.item)] = int(have.get(str(d.item), 0)) + int(d.count)
	for g: Dictionary in _effects_of("fallen").get("give_items", []):
		have[str(g.item)] = int(have.get(str(g.item), 0)) + int(g.count)
	var need := {}
	for r: Dictionary in GameData.records_of_type("recipe"):
		if str(r.get("makes", "")).begins_with("armour.bastion_"):
			for c: Dictionary in r.cost:
				need[str(c.item)] = int(need.get(str(c.item), 0)) + int(c.count)
	for item: String in need:
		assert_true(int(have.get(item, 0)) >= int(need[item]), "%s: %d of %d" % [item, int(have.get(item, 0)),
			int(need[item])])
