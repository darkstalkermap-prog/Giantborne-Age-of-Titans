extends TestSuite
## C1: act two's XP budget (decision C1-13; docs/BALANCE_LOG.md "C1"), from the shipped data only. Act one is not
## rebalanced: its guaranteed XP gives level 12 at the throne (test_main_thread_combinations), and the world bot's runs
## measured 14-16 there. Act two's thread floors the Breach's climb at level 13 (stage 7's) and the trials at level
## 15 (stage 8's), so a giant never grinds for a growth; and act two's own XP before stage 8 - its thread's stages to
## the trials, the Colossus's Trials, Maera's thanks and the Hoarfell's discoveries - covers levels 13 to 15 by itself.

const MAIN := "quest.act_two_main"
const TRIALS := "quest.rim_colossus"


func _hoarfell_discoveries() -> int:
	var total := int(GameData.get_record("region.hoarfell").get("discover_xp", 0))
	for rec: Dictionary in GameData.records_of_type("poi"):
		if str(rec.get("region", "")) == "region.hoarfell":
			total += int(rec.get("xp", 0))
	return total


func test_the_floors_are_the_colossi_levels() -> void:
	assert_eq(int(WorldXp.stage(MAIN, "breach").get("xp_floor_level", 0)), WorldXp.growth_level("growth.07"),
		"climbing the Breach lifts a giant to stage 7's level (13)")
	assert_eq(int(WorldXp.stage(MAIN, "trials").get("xp_floor_level", 0)), WorldXp.growth_level("growth.08"),
		"the trials lift it to stage 8's (15)")


func test_act_two_alone_covers_levels_13_to_15() -> void:
	var thread := WorldXp.stages_xp(MAIN, ["council", "breach", "grow7", "trials"])
	var trials := WorldXp.stages_xp(TRIALS)
	var maera := 150
	var found := _hoarfell_discoveries()
	var have := thread + trials + maera + found
	var need := WorldXp.xp_for_level(15) - WorldXp.xp_for_level(13)
	print("    act two budget: the thread to the trials %d, the trials %d, Maera %d, the Hoarfell's discoveries %d = %d; levels 13-15 need %d" % [
		thread, trials, maera, found, have, need])
	assert_true(have >= need, "act two's XP before stage 8 covers levels 13 to 15 (%d of %d)" % [have, need])
	assert_true(WorldXp.xp_for_level(20) > WorldXp.xp_for_level(15), "and leaves the track's levels 16-20 to milestones D-F")
	assert_eq(int(GameData.get_record("progression.default").level_cap), 20, "no level beyond 20")
