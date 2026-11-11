extends TestSuite
## The world's XP budget (P29; plan M6-M9 §5.8, decision 26), computed from the shipped data only
## (tests/support/world_xp.gd): the guaranteed XP counts world_start (the Valley's worst outcome),
## the mandatory stages' quest XP without the xp_floor_level lifts, the worst resolution of each oath
## (its choice's XP plus the props its declared path must break) and the discoveries a mandatory path
## cannot avoid (the POIs whose radius covers the arrival, an objective's marker or the talker a
## stage-4 giant must reach), and keeps at least 50 XP of margin at every growth gate:
##   * the beacon reaches stage 4's level (growth.04, L7);
##   * after the first oath - Brannock's, any resolution - stage 5's (growth.05, L9);
##   * after two oaths and the oaths stage, stage 6's (growth.06, L11): it needs two oath quests,
##     so it is checked once P35 or P36 adds the second (in M7 only the march oath exists).
## The milestone floors (xp_floor_level) match those levels, so a level never holds the thread.

const MAIN := "quest.world_main"
const MARCH := "quest.oath_march"
const MARGIN := 50
## Plan §5.8: the march oath's worst resolution is worth 800 (help 1,000, intimidate 800, force 800).
const OATH_MIN_XP := 800
## The march's resolutions and the props each declared path must break (their XP is guaranteed).
const MARCH_PATHS := {"help": ["prop.gate_toll"], "intimidate": [], "force": ["prop.gatehouse_brannock"]}
## M8: the other oaths' resolutions and the props their declared paths must break (P35: the wood's
## drive burns the troll den's three brood nests).
const OATH_PATHS := {"quest.oath_wood": {"drive": ["prop.brood_nest", "prop.brood_nest", "prop.brood_nest"]}}
## The opening's unavoidable points: the Kings' Door's arrival, the beacon's marker; then the shrine's.
const BEACON_POINTS := ["world.cp.kingsgate_shelf", "world.marker.kingsgate_beacon"]
const SHRINE_POINTS := ["world.marker.kingsgate_shrine"]
## Where a stage-4 giant must stand to take Brannock's oath: Edda, inside the south gate.
const MARCH_POINTS := ["world.crownmarch.edda"]


func _need(profile: String) -> int:
	return WorldXp.xp_for_level(WorldXp.growth_level(profile))


## Guaranteed XP through the beacon (kings_door, beacon and the discoveries on the way).
func _through_beacon() -> int:
	return WorldXp.world_start_xp() + WorldXp.stages_xp(MAIN, ["kings_door", "beacon"]) \
		+ WorldXp.sum(WorldXp.discoveries_covering(BEACON_POINTS))


## Guaranteed XP through grow4 (the shrine's discovery is 0 by design: the shrine is the reward).
func _through_grow4() -> int:
	var seen := WorldXp.discoveries_covering(BEACON_POINTS)
	seen.merge(WorldXp.discoveries_covering(SHRINE_POINTS))
	return WorldXp.world_start_xp() + WorldXp.stages_xp(MAIN, ["kings_door", "beacon", "grow4"]) + WorldXp.sum(seen)


func test_every_place_the_budget_names_is_in_the_world() -> void:
	for id: String in BEACON_POINTS + SHRINE_POINTS + MARCH_POINTS:
		assert_true(WorldXp.position_of(id).is_finite(), "%s is in the world's index or encounters" % id)
	for s: String in ["kings_door", "beacon", "grow4", "oaths"]:
		assert_false(WorldXp.stage(MAIN, s).is_empty(), "%s has stage %s" % [MAIN, s])
	assert_eq(WorldXp.world_start_xp(), 1050, "world_start is the Valley's worst outcome (1,050 XP)")


func test_the_beacon_reaches_stage_4s_level_with_margin() -> void:
	var have := _through_beacon()
	var need := _need("growth.04")
	print("    world XP: through the beacon %d, stage 4 (L%d) needs %d, margin %d" % [
		have, WorldXp.growth_level("growth.04"), need, have - need])
	assert_true(have >= need + MARGIN, "the beacon gives L%d with %d XP of margin (%d of %d)" % [
		WorldXp.growth_level("growth.04"), MARGIN, have, need])
	var discovered := WorldXp.discoveries_covering(BEACON_POINTS)
	assert_true(discovered.has("poi.kingsgate_shelf"), "the arrival discovers the Kingsgate shelf (%s)" % [discovered.keys()])


func test_every_march_resolution_pays_the_oath_and_the_worst_reaches_stage_5() -> void:
	var resolutions := OathRules.first_oath_resolutions(MARCH, GameData.records)
	var expected := PackedStringArray(MARCH_PATHS.keys())
	expected.sort()
	assert_eq(resolutions, expected, "the march's resolutions open to a first oath at stage 4")
	var worst := -1
	for outcome: String in MARCH_PATHS:
		var xp := WorldXp.resolution_xp(MARCH, outcome, MARCH_PATHS[outcome])
		print("    world XP: the march oath by %s: %d" % [outcome, xp])
		assert_true(xp >= OATH_MIN_XP, "the march oath by %s is worth at least %d (%d)" % [outcome, OATH_MIN_XP, xp])
		worst = xp if worst < 0 else mini(worst, xp)
	var town := WorldXp.discoveries_covering(MARCH_POINTS)
	assert_true(town.has("poi.brannock"), "taking the oath at stage 4 discovers Brannock (%s)" % [town.keys()])
	var have := _through_grow4() + worst + WorldXp.sum(town)
	var need := _need("growth.05")
	print("    world XP: after the first oath (worst) %d, stage 5 (L%d) needs %d, margin %d" % [
		have, WorldXp.growth_level("growth.05"), need, have - need])
	assert_true(have >= need + MARGIN, "the first oath gives L%d with %d XP of margin (%d of %d)" % [
		WorldXp.growth_level("growth.05"), MARGIN, have, need])


func test_two_oaths_reach_stage_6_once_the_second_oath_exists() -> void:
	var worsts: Array[int] = []
	for id: String in GameData.ids_of_type("quest"):
		if OathRules.oath_key(id) == "":
			continue
		var worst := -1
		for outcome: String in OathRules.first_oath_resolutions(id, GameData.records):
			var extra: Array = MARCH_PATHS.get(outcome, []) if id == MARCH else (OATH_PATHS.get(id, {}) as Dictionary).get(outcome, [])
			var xp := WorldXp.resolution_xp(id, outcome, extra)
			worst = xp if worst < 0 else mini(worst, xp)
		assert_true(worst >= 0, "%s has a resolution open to a first oath" % id)
		worsts.append(maxi(worst, 0))
	assert_true(worsts.size() >= 1, "Brannock's oath ships (P29)")
	if worsts.size() < 2:
		print("    world XP: one oath quest present (M7): the two-oath gate waits for P35 and P36")
		return
	worsts.sort()
	var have := _through_grow4() + worsts[0] + worsts[1] + WorldXp.stages_xp(MAIN, ["oaths"]) \
		+ WorldXp.sum(WorldXp.discoveries_covering(MARCH_POINTS))
	var need := _need("growth.06")
	print("    world XP: after two oaths and the oaths stage %d, stage 6 needs %d" % [have, need])
	assert_true(have >= need + MARGIN, "two oaths give L%d with %d XP of margin (%d of %d)" % [
		WorldXp.growth_level("growth.06"), MARGIN, have, need])


func test_the_milestone_floors_match_the_growth_levels() -> void:
	assert_eq(int(WorldXp.stage(MAIN, "beacon").get("xp_floor_level", 0)), WorldXp.growth_level("growth.04"),
		"the beacon lifts the XP to stage 4's level")
	assert_eq(int(WorldXp.stage(MAIN, "oaths").get("xp_floor_level", 0)), WorldXp.growth_level("growth.06"),
		"the oaths stage lifts it to stage 6's level")
	var stages: Array = GameData.get_record(MARCH).get("stages", [])
	assert_eq(int((stages.back() as Dictionary).get("xp_floor_level", 0)), WorldXp.growth_level("growth.05"),
		"an oath's resolution lifts it to stage 5's level")
	assert_eq(int(WorldXp.stage(MAIN, "grow4").get("complete_when", {}).get("stage", 0)), 4, "grow4 waits for stage 4")
