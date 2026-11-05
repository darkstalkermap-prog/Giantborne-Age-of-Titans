extends TestSuite
## The guaranteed-XP budget of the quest line (P15, plan §4.7, decision 7), computed from the
## shipped data only, so tuning (P17b) keeps it true:
##   * mandatory XP reaches the Grove's growth level (growth.02 required_level, 3) before stage
##     `grove`, the level of the last library abilities (unlock_level 4: Mend, Roar, Surge) by the
##     end of stage `gate`, and the Kingsfall growth level (growth.03 required_level, 5) before
##     `grow3`, for every village outcome;
##   * guaranteed XP counts the main stages' XP, the mandatory kills (the forest ogre, the Ogre
##     King, and the field ogre on the help_ogre path), the practice gate's prop XP and the
##     outcome's own XP: the elder's help or intimidation reward, or the smashed barricade's prop
##     XP for force (the worst outcome). No tutorial XP, no optional kills.
##   * The plan's worked numbers (§4.7: 260 before the Grove, 450 / 460 / 540 at the gate for
##     force / intimidate / help, 910 before grow3, 1,050 at the end) are printed for the record.

const MAIN := "quest.main"
const OUTCOMES := ["help_cache", "help_ogre", "intimidate", "force"]
## The mandatory kills: entity id -> its encounter (its definition gives the kill XP).
const FOREST_OGRE := "valley.forest.ogre"
const KING := "valley.arena.ogre_king"
const FIELD_OGRE := "valley.fields.ogre"
const GATE_PROP := "prop.gate_practice"
const BARRICADE_PROP := "prop.cart_barricade"
## The plan's gate stages: XP gathered before `grove` and `grow3`, and through `gate`.
const BEFORE_GROVE := "grove"
const THROUGH_GATE := "gate"
const BEFORE_GROW3 := "grow3"


func _main_stages() -> Array:
	return GameData.get_record(MAIN).get("stages", [])


func _stage_ids() -> PackedStringArray:
	var out := PackedStringArray()
	for s: Dictionary in _main_stages():
		out.append(str(s.id))
	return out


## Sum of the main stages' XP before `stage_id` (inclusive: through it).
func _stage_xp(stage_id: String, inclusive: bool) -> int:
	var total := 0
	for s: Dictionary in _main_stages():
		if str(s.id) == stage_id and not inclusive:
			return total
		total += int(s.get("xp", 0))
		if str(s.id) == stage_id:
			return total
	fail("quest.main has no stage '%s'" % stage_id)
	return total


## The kill XP of a spawn (its definition's xp_reward), found through the encounter records.
func _kill_xp(entity_id: String) -> int:
	for rec: Dictionary in GameData.records_of_type("encounter"):
		for sp: Dictionary in rec.get("spawns", []):
			if str(sp.entity_id) == entity_id:
				return int(GameData.get_record(str(sp.definition)).get("xp_reward", 0))
	fail("no encounter spawns %s" % entity_id)
	return 0


func _prop_xp(prop_id: String) -> int:
	return int(GameData.get_record(prop_id).get("xp_reward", 0))


## The elder's reward XP for an outcome (the choice whose effects set it; once-gated).
func _dialogue_xp(outcome: String) -> int:
	for n: Dictionary in GameData.get_record("dialogue.elder").get("nodes", []):
		for c: Dictionary in n.get("choices", []):
			var e: Dictionary = c.get("effects", {})
			if str(e.get("outcome", "")) == outcome:
				return int(e.get("xp", 0))
	return 0


## The XP an outcome itself guarantees: the elder's reward, plus the field ogre's kill on the
## help_ogre path; force: the smashed barricade's prop XP.
func _outcome_xp(outcome: String) -> int:
	match outcome:
		"force":
			return _prop_xp(BARRICADE_PROP)
		"help_ogre":
			return _dialogue_xp(outcome) + _kill_xp(FIELD_OGRE)
	return _dialogue_xp(outcome)


func _growth_level(stage: int) -> int:
	for rec: Dictionary in GameData.records_of_type("growth_profile"):
		if int(rec.get("stage", 0)) == stage:
			return int(rec.get("required_level", 1))
	fail("no growth profile for stage %d" % stage)
	return 99


## The highest unlock_level of the progression's ability library (the last abilities, L4).
func _last_ability_level() -> int:
	var top := 1
	for id: Variant in Progression.library():
		var a := GameData.get_action(str(id))
		if a != null:
			top = maxi(top, int(GameData.get_record(str(id)).get("unlock_level", 1)))
	return top


func test_the_quest_line_has_its_stages_in_order() -> void:
	var ids := _stage_ids()
	assert_eq(ids, PackedStringArray(["leave_hollow", "wolves", "ogre", "grove", "hurl", "to_village", "village",
		"bridge", "gate", "courtyard", "causeway", "boss", "grow3", "tree", "deadfall", "crown"]),
		"quest.main's sixteen stages in the spec's order (plan §4.5)")
	assert_true(bool(GameData.get_record(MAIN).get("prototype_pacing", false)), "prototype pacing (decision 7)")
	assert_eq(GameData.get_record(MAIN).get("on_complete_flags", {}), {"slice.completed": true},
		"completing it completes the slice")


func test_mandatory_xp_reaches_each_gate_for_every_outcome() -> void:
	var grove_level := _growth_level(2)
	var grow3_level := _growth_level(3)
	var ability_level := _last_ability_level()
	assert_eq(grove_level, 3, "the Grove's growth needs level 3 (growth.02)")
	assert_eq(grow3_level, 5, "Kingsfall's growth needs level 5 (growth.03)")
	assert_eq(ability_level, 4, "the last library abilities unlock at level 4")
	var kills_before_grove := _kill_xp(FOREST_OGRE)
	var before_grove := _stage_xp(BEFORE_GROVE, false) + kills_before_grove
	print("    xp budget: before grove %d (level %d)" % [before_grove, Progression.level_for_xp(before_grove)])
	assert_true(before_grove >= Progression.xp_for_level(grove_level),
		"before the Grove: %d XP reach level %d (%d)" % [before_grove, grove_level, Progression.xp_for_level(grove_level)])
	for outcome: String in OUTCOMES:
		var extra := _outcome_xp(outcome) + _prop_xp(GATE_PROP)
		var at_gate := _stage_xp(THROUGH_GATE, true) + kills_before_grove + extra
		var before_grow3 := _stage_xp(BEFORE_GROW3, false) + kills_before_grove + _kill_xp(KING) + extra
		var at_end := _stage_xp("crown", true) + kills_before_grove + _kill_xp(KING) + extra
		print("    xp budget %-10s: end of gate %d (L%d), before grow3 %d (L%d), end %d (L%d)" % [outcome,
			at_gate, Progression.level_for_xp(at_gate), before_grow3, Progression.level_for_xp(before_grow3),
			at_end, Progression.level_for_xp(at_end)])
		assert_true(at_gate >= Progression.xp_for_level(ability_level),
			"%s: %d XP by the end of the gate reach level %d" % [outcome, at_gate, ability_level])
		assert_true(before_grow3 >= Progression.xp_for_level(grow3_level),
			"%s: %d XP before grow3 reach level %d" % [outcome, before_grow3, grow3_level])
		assert_true(at_end > before_grow3, "%s: the last stages still pay" % outcome)


func test_the_worst_outcome_is_force_and_the_rewards_are_once_gated() -> void:
	var worst := ""
	var worst_xp := 1 << 30
	for outcome: String in OUTCOMES:
		if _outcome_xp(outcome) < worst_xp:
			worst_xp = _outcome_xp(outcome)
			worst = outcome
	assert_eq(worst, "force", "force (the barricade's prop XP) is the worst outcome for XP")
	assert_eq(_prop_xp(BARRICADE_PROP), 30, "the barricade gives 30 XP (plan §4.3)")
	assert_eq(_prop_xp(GATE_PROP), 20, "the practice gate 20")
	assert_eq(_dialogue_xp("help_cache"), 120, "the cache help pays 120")
	assert_eq(_dialogue_xp("help_ogre"), 120, "the ogre help pays 120")
	assert_eq(_dialogue_xp("intimidate"), 40, "intimidation 40")
	# Every rewarding choice is gated by a once-flag (spec §14: rewards once).
	for n: Dictionary in GameData.get_record("dialogue.elder").get("nodes", []):
		for c: Dictionary in n.get("choices", []):
			var e: Dictionary = c.get("effects", {})
			if int(e.get("xp", 0)) > 0 or not (e.get("give_items", []) as Array).is_empty() \
					or not (e.get("learn_abilities", []) as Array).is_empty():
				var once := str(e.get("once_flag", ""))
				assert_true(once == "reward.village.help" or once == "reward.village.intimidate",
					"%s / '%s' is gated by a reward.village once-flag (%s)" % [n.id, c.text, once])


func test_the_boss_is_met_with_the_last_abilities() -> void:
	# Plan §4.7: "Before boss: >= 450" - the worst outcome still has Mend, Roar and Titan Surge's
	# level when it reaches the Ogre King. (The shipped numbers are printed: the plan's worked
	# table is 260 / 450 / 460 / 540 / 490 / 910 / 1,050; P17b may tune them, the inequalities
	# are what must hold.)
	var ogre := _kill_xp(FOREST_OGRE)
	var gate := _prop_xp(GATE_PROP)
	for outcome: String in OUTCOMES:
		var before_boss := _stage_xp("boss", false) + ogre + _outcome_xp(outcome) + gate
		print("    xp budget %-10s: before the boss %d" % [outcome, before_boss])
		assert_true(before_boss >= Progression.xp_for_level(_last_ability_level()),
			"%s: %d XP before the boss reach level %d" % [outcome, before_boss, _last_ability_level()])
	assert_true(_stage_xp("boss", true) > _stage_xp("boss", false), "the boss stage itself pays XP")
	assert_true(_kill_xp(KING) > _kill_xp(FOREST_OGRE), "the king pays more than an ogre")
