extends TestSuite
## The crown's oath and the finale in the world's XP and equipment budgets (P36; plan M6-M9 §5.8, decision
## 26), from the shipped data only (tests/support/world_xp.gd, world_items.gd): every road of the crown's
## oath pays 800 XP (worst and best: the meeting's 50 and the resolution's 750) and its reward; as the
## first oath it reaches stage 5's level with 50 XP of margin; every pair of the oaths that ship (the
## wood's pairs once quest.oath_wood is on the branch - P35; the merged run covers them) with the oaths
## stage reaches stage 6's; the finale (grow6, the Standing Stones, the Moot, the champion, the throne)
## reaches level 12; and the Stones' gift with the second oath's reward pays the second titanforging at
## a titan forge the crown's road opens (the fort's, or Skarn's once it is saved or rebuilt).

const MAIN := "quest.world_main"
const CROWN := "quest.oath_crown"
const MARCH := "quest.oath_march"
const WOOD := "quest.oath_wood"
const MARGIN := 50
const OATH_XP := 800
## The march's resolutions and the props each declared path must break (P29's XP test).
const MARCH_PATHS := {"help": ["prop.gate_toll"], "intimidate": [], "force": ["prop.gatehouse_brannock"]}
## W21: the wood's (P35's test_world_budgets_wood): the drive path must burn the den's three brood nests.
const WOOD_PATHS := {"slay": [], "drive": ["prop.brood_nest", "prop.brood_nest", "prop.brood_nest"]}
## Where a stage-4 giant must stand to take each oath (the discoveries it cannot avoid; W21: Sedge in
## Hollowmere, P35's).
const OATH_POINTS := {MARCH: ["world.crownmarch.edda"], CROWN: ["world.aldmere.herald"], WOOD: ["world.greywood.sedge"]}
const BEACON_POINTS := ["world.cp.kingsgate_shelf", "world.marker.kingsgate_beacon"]
const SHRINE_POINTS := ["world.marker.kingsgate_shrine"]
## The finale's unavoidable places: the Standing Stones' shrine, the Moot's ring.
const FINALE_POINTS := ["world.marker.standing_stones", "world.marker.moot_ring"]
const TITANFORGE := {"item.titan_iron": 2, "item.iron_ingot": 2}


func _need(profile: String) -> int:
	return WorldXp.xp_for_level(WorldXp.growth_level(profile))


func _through_grow4() -> int:
	var seen := WorldXp.discoveries_covering(BEACON_POINTS)
	seen.merge(WorldXp.discoveries_covering(SHRINE_POINTS))
	return WorldXp.world_start_xp() + WorldXp.stages_xp(MAIN, ["kings_door", "beacon", "grow4"]) + WorldXp.sum(seen)


## The worst first-oath resolution of an oath quest (its XP, the declared path's props for the march).
func _worst(quest_id: String) -> int:
	var worst := -1
	for outcome: String in OathRules.first_oath_resolutions(quest_id, GameData.records):
		var extra: Array = MARCH_PATHS.get(outcome, []) if quest_id == MARCH \
			else WOOD_PATHS.get(outcome, []) if quest_id == WOOD else []
		var xp := WorldXp.resolution_xp(quest_id, outcome, extra)
		worst = xp if worst < 0 else mini(worst, xp)
	return worst


## The oath quests that ship on this branch (the wood's waits for P35).
func _oaths() -> PackedStringArray:
	var out := PackedStringArray()
	for id: String in [MARCH, WOOD, CROWN]:
		if GameData.has_record(id):
			out.append(id)
	return out


func _discoveries(quest_id: String) -> Dictionary:
	return WorldXp.discoveries_covering(OATH_POINTS.get(quest_id, []))


func test_every_crown_road_pays_800_and_the_oaths_reward() -> void:
	var roads := OathRules.first_oath_resolutions(CROWN, GameData.records)
	assert_eq(roads, PackedStringArray(["breach", "parley", "sabotage"]), "the crown's three roads")
	for outcome: String in roads:
		var xp := WorldXp.resolution_xp(CROWN, outcome)
		print("    crown budget: the crown's oath by %s: %d" % [outcome, xp])
		assert_eq(xp, OATH_XP, "the crown's oath by %s is worth %d (worst and best)" % [outcome, OATH_XP])
	assert_eq(WorldItems.stage_items(CROWN), WorldItems.loot("loot.oath_reward"), "its resolution pays the oath's reward")
	assert_eq(int(WorldXp.stage(CROWN, "resolve").get("xp_floor_level", 0)), WorldXp.growth_level("growth.05"),
		"and lifts the XP to stage 5's level")
	var at := WorldXp.position_of("world.aldmere.herald")
	assert_true(at.is_finite(), "the herald stands in the world")
	assert_true(_discoveries(CROWN).has("poi.war_camp"), "meeting her discovers the war camp (%s)" % [_discoveries(CROWN).keys()])


func test_the_crown_as_the_first_oath_reaches_stage_5() -> void:
	var have := _through_grow4() + _worst(CROWN) + WorldXp.sum(_discoveries(CROWN))
	var need := _need("growth.05")
	print("    crown budget: the crown as the first oath %d, stage 5 (L%d) needs %d, margin %d" % [
		have, WorldXp.growth_level("growth.05"), need, have - need])
	assert_true(have >= need + MARGIN, "the crown's oath first gives L%d with %d XP of margin (%d of %d)" % [
		WorldXp.growth_level("growth.05"), MARGIN, have, need])


func test_every_pair_of_oaths_reaches_stage_6() -> void:
	var oaths := _oaths()
	assert_true(oaths.has(MARCH) and oaths.has(CROWN), "the march's and the crown's oaths ship")
	if not oaths.has(WOOD):
		print("    crown budget: quest.oath_wood is not on this branch - its pairs wait for the merged run (P35)")
	var need := _need("growth.06")
	var pairs := 0
	for i in oaths.size():
		for j in range(i + 1, oaths.size()):
			var a := oaths[i]
			var b := oaths[j]
			var seen := _discoveries(a)
			seen.merge(_discoveries(b))
			var have := _through_grow4() + _worst(a) + _worst(b) + WorldXp.stages_xp(MAIN, ["oaths"]) + WorldXp.sum(seen)
			print("    crown budget: %s and %s with the oaths stage %d, stage 6 needs %d" % [a, b, have, need])
			assert_true(have >= need + MARGIN, "%s and %s give L%d with %d XP of margin (%d of %d)" % [
				a, b, WorldXp.growth_level("growth.06"), MARGIN, have, need])
			pairs += 1
	assert_true(pairs >= 1, "at least one pair of oaths ships")


func test_the_finale_reaches_level_12() -> void:
	var oaths := _oaths()
	var worsts: Array[int] = []
	for id: String in oaths:
		worsts.append(_worst(id))
	worsts.sort()
	var seen := _discoveries(MARCH)
	seen.merge(_discoveries(CROWN))
	var two := _through_grow4() + worsts[0] + worsts[1] + WorldXp.stages_xp(MAIN, ["oaths"]) + WorldXp.sum(seen)
	var finale := WorldXp.stages_xp(MAIN, ["grow6", "moot", "champion", "throne"])
	assert_eq(finale, 700, "grow6 100, moot 100, champion 300, throne 200")
	var places := WorldXp.discoveries_covering(FINALE_POINTS)
	assert_true(places.has("poi.standing_stones") and places.has("poi.the_moot"), "the finale discovers the Stones and the Moot (%s)" % [places.keys()])
	var have := two + finale + WorldXp.sum(places)
	var need := WorldXp.xp_for_level(12)
	print("    crown budget: the finale %d, level 12 needs %d, margin %d" % [have, need, have - need])
	assert_true(have >= need + MARGIN, "the finale gives level 12 with %d XP of margin (%d of %d)" % [MARGIN, have, need])
	assert_eq(int(WorldXp.stage(MAIN, "grow6").complete_when.stage), 6, "grow6 waits for stage 6")


func test_the_stones_gift_and_the_second_oath_pay_the_second_titanforging() -> void:
	# after the first titanforging the worst path holds nothing (plan §5.8); the second oath's reward and
	# the Stones' gift then pay the second
	var b := WorldItems.plus(WorldItems.stage_items(CROWN), WorldItems.stage_items(MAIN, "grow6"))
	print("    crown budget: the second oath (the crown's) and the Stones' gift: %s" % WorldItems.label(b))
	assert_eq(WorldItems.count(WorldItems.stage_items(MAIN, "grow6"), WorldItems.TITAN_IRON), 1, "the Stones' gift: 1 titan iron")
	assert_true(WorldItems.affordable(WorldItems.plus(b, TITANFORGE, -1)), "they pay a titanforging (%s)" % WorldItems.label(b))
	# a titan forge the crown's roads open: the fort's on a parley or a spared Corvane, Skarn's once saved or rebuilt
	var forges := {}
	for el: Dictionary in WorldContent.elements_of("condition_forge"):
		forges[str(el.id)] = el
	assert_eq(str((forges.get("world.aldmere.fort_forge", {}) as Dictionary).get("tier", "")), "titan", "the fort's forge is a titan forge")
	assert_eq(str((forges.get("world.stonehold.skarn_forge", {}) as Dictionary).get("tier", "")), "titan", "Skarn's hearth-forge too")
	var fort: Dictionary = forges["world.aldmere.fort_forge"].open_when
	var skarn: Dictionary = forges["world.stonehold.skarn_forge"].open_when
	for case: Array in [[{"oath.crown.outcome": "parley"}, true], [{"boss.corvane.outcome": "spared"}, true],
			[{"boss.corvane.outcome": "slain"}, false], [{"oath.crown.outcome": "sabotage"}, false]]:
		var ctx := QuestConditions.empty_context()
		ctx.flags = case[0]
		assert_eq(QuestConditions.holds(fort, ctx), case[1], "the fort's forge with %s" % [case[0]])
	var c := QuestConditions.empty_context()
	c.flags = {"world.skarn.rebuilt": true}
	assert_true(QuestConditions.holds(skarn, c), "Skarn's forge opens once Skarn is rebuilt")
	c.flags = {"event.siege_of_skarn.done": true, "event.siege_of_skarn.outcome": "saved"}
	assert_true(QuestConditions.holds(skarn, c), "...or saved")
	# the optional extras of the regions (never missable, never counted)
	assert_eq(WorldItems.count(WorldItems.stage_items("quest.siege_of_skarn"), WorldItems.TITAN_IRON), 1, "saving Skarn: 1 titan iron")
	assert_eq(WorldXp.stages_xp("quest.siege_of_skarn"), 300, "the siege of Skarn: 300 XP")
	assert_eq(WorldXp.stages_xp("quest.skarn_rebuild"), 100, "rebuilding Skarn: 100 XP")
	assert_eq(WorldXp.stages_xp("quest.deserters"), 120, "the deserters: 120 XP")
	assert_eq(WorldXp.stages_xp("quest.ballista_ridge"), 150, "Ballista Ridge: 150 XP")
