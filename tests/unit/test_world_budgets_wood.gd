extends TestSuite
## The wood oath's budgets (P35; plan M6-M9 §5.7, §5.8, decision 26, decision 32), from the shipped data
## only, through P29's helpers (tests/support/world_xp.gd, world_items.gd):
##   * XP: both resolutions are worth 800 (slay: the meeting 50 and Sedge's 750; drive: the meeting,
##     the three brood nests 3 x 50 its declared path must burn and Sedge's 600); the wood as the first
##     oath reaches stage 5's level and, with Brannock's, two oaths reach stage 6's, each with at least
##     50 XP of margin (Hollowmere's discovery is on the way: Sedge stands in it);
##   * equipment: the wood as the first oath, on every toll path, keeps the first titanforging (2 titan
##     iron and 2 iron) for the Titan Forge - a titan-tier forge reachable at stage 4 without a second
##     oath (its fire waits only for the scavengers), whose ribs add 2 titan iron;
##   * every P35 quest's XP and items are the plan's (the optional sources: the Titan's Bones 2 titan
##     iron, the Hidden Grove 1, the sunken vault 2 iron).

const WOOD := "quest.oath_wood"
const MARCH := "quest.oath_march"
const MAIN := "quest.world_main"
const MARGIN := 50
## The wood's resolutions and the props each declared path must break (their XP is guaranteed).
const WOOD_PATHS := {"slay": [], "drive": ["prop.brood_nest", "prop.brood_nest", "prop.brood_nest"]}
## The march's (P29's table, for the two-oath gate).
const MARCH_PATHS := {"help": ["prop.gate_toll"], "intimidate": [], "force": ["prop.gatehouse_brannock"]}
const BEACON_POINTS := ["world.cp.kingsgate_shelf", "world.marker.kingsgate_beacon"]
const SHRINE_POINTS := ["world.marker.kingsgate_shrine"]
## Where a stage-4 giant must stand to take each oath: Sedge among Hollowmere's huts, Edda in Brannock.
const WOOD_POINTS := ["world.greywood.sedge"]
const MARCH_POINTS := ["world.crownmarch.edda"]
## The plan's side quests (§5.7): quest -> [XP, optional sources' items {item: count} of its place].
const SIDE := {"quest.great_pine": [100, {}], "quest.woodcutters": [150, {}], "quest.the_needle": [100, {"item.titan_iron": 1}],
	"quest.drowned_bells": [200, {}], "quest.sunken_vault": [100, {"item.iron_ingot": 2}],
	"quest.titan_bones": [150, {"item.titan_iron": 2}]}
## Where each side quest's items come from (the place's loot table, paid once).
const SOURCES := {"quest.the_needle": "loot.cache_hidden_grove", "quest.sunken_vault": "loot.cache_sunken_vault",
	"quest.titan_bones": "loot.titan_bones"}
const TITANFORGE := {"item.titan_iron": 2, "item.iron_ingot": 2}
const TOLL_PATHS := {"pay": "paid", "cow": "cowed", "none": ""}


func _need(profile: String) -> int:
	return WorldXp.xp_for_level(WorldXp.growth_level(profile))


func _through_grow4() -> int:
	var seen := WorldXp.discoveries_covering(BEACON_POINTS)
	seen.merge(WorldXp.discoveries_covering(SHRINE_POINTS))
	return WorldXp.world_start_xp() + WorldXp.stages_xp(MAIN, ["kings_door", "beacon", "grow4"]) + WorldXp.sum(seen)


func _worst(quest_id: String, paths: Dictionary) -> int:
	var worst := -1
	for outcome: String in paths:
		var xp := WorldXp.resolution_xp(quest_id, outcome, paths[outcome])
		worst = xp if worst < 0 else mini(worst, xp)
	return worst


func test_both_resolutions_are_worth_800_and_the_first_oath_reaches_stage_5() -> void:
	var resolutions := OathRules.first_oath_resolutions(WOOD, GameData.records)
	assert_eq(resolutions, PackedStringArray(["drive", "slay"]), "slay and drive are open to a first oath at stage 4")
	for outcome: String in WOOD_PATHS:
		var xp := WorldXp.resolution_xp(WOOD, outcome, WOOD_PATHS[outcome])
		print("    world XP: the wood's oath by %s: %d" % [outcome, xp])
		assert_eq(xp, 800, "the wood's oath by %s is worth 800 (plan §5.7)" % outcome)
	assert_eq(WorldXp.prop_xp("prop.brood_nest"), 50, "a brood nest burns for 50")
	var hollowmere := WorldXp.discoveries_covering(WOOD_POINTS)
	assert_true(hollowmere.has("poi.hollowmere"), "meeting Sedge at stage 4 discovers Hollowmere (%s)" % [hollowmere.keys()])
	var have := _through_grow4() + _worst(WOOD, WOOD_PATHS) + WorldXp.sum(hollowmere)
	var need := _need("growth.05")
	print("    world XP: after the wood as the first oath %d, stage 5 (L%d) needs %d, margin %d" % [
		have, WorldXp.growth_level("growth.05"), need, have - need])
	assert_true(have >= need + MARGIN, "the wood as the first oath gives L%d with %d XP of margin (%d of %d)" % [
		WorldXp.growth_level("growth.05"), MARGIN, have, need])
	var swear := WorldXp.stage(WOOD, "swear")
	assert_eq(int(swear.get("xp_floor_level", 0)), WorldXp.growth_level("growth.05"), "the oath's floor is stage 5's level")


func test_the_wood_and_the_march_reach_stage_6_with_the_oaths_stage() -> void:
	var seen := WorldXp.discoveries_covering(WOOD_POINTS)
	seen.merge(WorldXp.discoveries_covering(MARCH_POINTS))
	var have := _through_grow4() + _worst(WOOD, WOOD_PATHS) + _worst(MARCH, MARCH_PATHS) \
		+ WorldXp.stages_xp(MAIN, ["oaths"]) + WorldXp.sum(seen)
	var need := _need("growth.06")
	print("    world XP: after the wood and the march and the oaths stage %d, stage 6 (L%d) needs %d, margin %d" % [
		have, WorldXp.growth_level("growth.06"), need, have - need])
	assert_true(have >= need + MARGIN, "two oaths give L%d with %d XP of margin (%d of %d)" % [
		WorldXp.growth_level("growth.06"), MARGIN, have, need])


func test_the_wood_as_the_first_oath_keeps_a_titanforging_for_the_titan_forge() -> void:
	var start := WorldItems.plus(WorldItems.world_start(), WorldItems.loot("loot.beacon_cache"))
	var weapon := str((Progression.record().get("world_start", {}) as Dictionary).get("weapon", ""))
	var after := WorldItems.plus(start, WorldItems.refit_cost(weapon), -1)
	assert_true(WorldItems.affordable(after), "the beacon pays the reinforcement")
	for outcome: String in WOOD_PATHS:
		for toll: String in TOLL_PATHS:
			var b := WorldItems.plus(after, WorldItems.stage_items(WOOD))
			if str(TOLL_PATHS[toll]) != "":
				b = WorldItems.plus(b, WorldItems.choice_items("dialogue.toll_captain", str(TOLL_PATHS[toll])))
			assert_true(WorldItems.affordable(WorldItems.plus(b, TITANFORGE, -1)),
				"the wood by %s with the toll %s keeps the first titanforging (%s)" % [outcome, toll, WorldItems.label(b)])
			var forged := WorldItems.plus(WorldItems.plus(b, WorldItems.loot("loot.titan_bones")), TITANFORGE, -1)
			assert_true(WorldItems.affordable(forged), "and the Titan Forge's ribs keep it whole (%s)" % WorldItems.label(forged))
	# The Titan Forge: titan tier, lit once the bones' scavengers are gone - no stage, no oath.
	var forge: Dictionary = {}
	var fire: Dictionary = {}
	for el: Dictionary in WorldContent.elements():
		match str(el.get("id", "")):
			"world.drowned.titan_forge":
				forge = el
			"world.drowned.titan_forge_fire":
				fire = el
	assert_eq(str(forge.get("tier", "")), "titan", "the Titan Forge titanforges")
	assert_eq(forge.get("requires_flags", []), [str(fire.get("flag", ""))], "once its fire is lit")
	for f: Variant in fire.get("requires_flags", []):
		assert_false(str(f).begins_with("oath."), "its fire waits for no oath (%s)" % f)
		assert_true(str(f).begins_with("encounter.") and str(f).ends_with(".cleared"), "only for its scavengers (%s)" % f)
	var reinforced := str(GameData.get_record(weapon).get("upgrade", {}).get("to", ""))
	assert_eq(str((GameData.get_record(reinforced).get("upgrade", {}) as Dictionary).get("forge_tier", "")), "titan",
		"the reinforced start weapon's next step is the titan forge's")
	assert_eq(WorldItems.refit_cost(reinforced), TITANFORGE, "and costs the first titanforging")


func test_every_quest_s_xp_and_items_are_the_plans() -> void:
	var total := 0
	for qid: String in SIDE:
		var xp := WorldXp.stages_xp(qid)
		total += xp
		assert_eq(xp, int(SIDE[qid][0]), "%s pays %d XP" % [qid, SIDE[qid][0]])
		for s: Dictionary in GameData.get_record(qid).get("stages", []):
			assert_eq((s.get("items", []) as Array).size(), 0, "%s.%s pays no items itself: its place does" % [qid, s.id])
		if SOURCES.has(qid):
			assert_eq(WorldItems.loot(str(SOURCES[qid])), SIDE[qid][1], "%s's place pays %s" % [qid, SIDE[qid][1]])
	print("    world XP: the Greywood's and the Drowned Steps' side quests pay %d (optional)" % total)
	assert_eq(WorldXp.stages_xp(WOOD), 50, "the oath's stages pay the meeting; Sedge pays the rest")
	assert_eq(WorldItems.stage_items(WOOD), WorldItems.loot("loot.oath_reward"), "the oath pays its reward")
