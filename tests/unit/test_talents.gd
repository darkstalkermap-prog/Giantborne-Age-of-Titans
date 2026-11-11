extends TestSuite
## P33 rules (plan M6-M9 §2.11, §5.12, decision 22), pure: the three trees hold the plan's 27 talents
## with every effect of §5.12, each talent of tiers 2-4 needs the one above it in its column and the
## capstone (2 points) both talents of tier 4; tiers open at levels 6 / 8 / 9 / 10 / 12; a talent is
## refused in the order unknown, known, level, requires, points and learned once; passives combine
## ("_mult" keys multiply, the others add); the three ancestries are the plan's; the player-facing
## lines; the data checks catch broken trees, grants and signatures; and the tiers follow the world's
## level milestones (the level cap stays 20: level 12 is where the last tier opens, at the throne).

## talent id -> [tier, column, modifiers, grants] (plan §5.12).
const EXPECTED := {
	"talent.destroyer_heavy_hands": [1, 1, {"heavy_damage_mult": 1.10, "outgoing_poise_mult": 1.05}, []],
	"talent.destroyer_iron_grip": [1, 2, {"grab_reach_add": 1.5, "throw_damage_mult": 1.15}, []],
	"talent.destroyer_shoulder_charge": [2, 1, {}, ["ability.shoulder_charge"]],
	"talent.destroyer_bone_breaker": [2, 2, {"outgoing_poise_mult": 1.10}, []],
	"talent.destroyer_relentless": [3, 1, {"stamina_cost_mult": 0.85}, []],
	"talent.destroyer_juggernaut": [3, 2, {"poise_damage_taken_mult": 0.85}, []],
	"talent.destroyer_cleave_of_ages": [4, 1, {}, ["ability.cleave_of_ages"]],
	"talent.destroyer_bloodied_fury": [4, 2, {"fury_on_kill_add": 6.0}, []],
	"talent.destroyer_titans_wrath": [5, 0, {"outgoing_damage_mult": 1.08}, []],
	"talent.guardian_stone_hide": [1, 1, {"armor_flat": 15.0}, []],
	"talent.guardian_steady_stance": [1, 2, {"poise_threshold_add": 25.0}, []],
	"talent.guardian_bulwark": [2, 1, {}, ["ability.bulwark"]],
	"talent.guardian_tireless": [2, 2, {"stamina_cost_mult": 0.9}, []],
	"talent.guardian_unyielding": [3, 1, {"damage_taken_mult": 0.92}, []],
	"talent.guardian_grounded": [3, 2, {"elemental_resist_add": 0.10}, []],
	"talent.guardian_stonewall_stance": [4, 1, {}, ["ability.stonewall_stance"]],
	"talent.guardian_protector": [4, 2, {"heal_received_mult": 1.2}, []],
	"talent.guardian_mountains_heart": [5, 0, {"health_add": 250.0}, []],
	"talent.primordial_runic_mind": [1, 1, {"essence_cost_mult": 0.85}, []],
	"talent.primordial_kindled": [1, 2, {"fury_gain_mult": 1.2}, []],
	"talent.primordial_rune_lance": [2, 1, {}, ["ability.rune_lance"]],
	"talent.primordial_quick_runes": [2, 2, {"cooldown_mult": 0.95}, []],
	"talent.primordial_primal_regrowth": [3, 1, {}, ["ability.primal_regrowth"]],
	"talent.primordial_wellspring": [3, 2, {"essence_add": 40.0}, []],
	"talent.primordial_storm_call": [4, 1, {}, ["ability.storm_call"]],
	"talent.primordial_regrowth": [4, 2, {"heal_received_mult": 1.15}, []],
	"talent.primordial_worldsong": [5, 0, {"magic_damage_mult": 1.15}, []],
}
## ancestry id -> [attribute bonus, modifiers, signature, dialogue tags] (plan §5.12).
const ANCESTRIES := {
	"ancestry.stoneblood": [{"constitution": 3, "endurance": 2}, {"armor_flat": 10.0, "poise_threshold_add": 20.0},
		"ability.bedrock_ward", ["stone"]],
	"ancestry.stormborn": [{"intellect": 3, "willpower": 2},
		{"essence_add": 30.0, "elemental_resist_add": 0.10, "magic_damage_mult": 1.10}, "ability.thunderhead", ["storm"]],
	"ancestry.wildheart": [{"strength": 3, "dexterity": 2},
		{"fury_gain_mult": 1.25, "stamina_add": 20.0, "move_speed_mult": 1.05}, "ability.wild_surge", ["wild"]],
}


func _near_dict(actual: Dictionary, expected: Dictionary, message: String) -> void:
	var keys := actual.keys()
	keys.sort()
	var want := expected.keys()
	want.sort()
	assert_eq(keys, want, message + " (keys)")
	for k: Variant in expected:
		assert_near(float(actual.get(k, NAN)), float(expected[k]), 1e-9, "%s: %s" % [message, k])


## GameData's records with some replaced ({id: {key: value}} merged into a copy; {id: null} drops a
## record), for the data checks.
func _records_with(patches: Dictionary) -> Dictionary:
	var recs := GameData.records.duplicate()
	for id: Variant in patches:
		if patches[id] == null:
			recs.erase(id)
			continue
		var rec: Dictionary = (recs.get(id, {}) as Dictionary).duplicate(true)
		for k: Variant in patches[id]:
			rec[k] = patches[id][k]
		recs[id] = rec
	return recs


func _errors_with(patches: Dictionary) -> String:
	return "\n".join(Talents.data_errors(_records_with(patches)))


# --------------------------------------------------------------------------- the trees

func test_the_three_trees_hold_the_plans_talents() -> void:
	assert_eq(Talents.ids().size(), 27, "27 talents")
	var expected_ids := EXPECTED.keys()
	expected_ids.sort()
	var ids := Talents.ids()
	ids.sort()
	assert_eq(ids, expected_ids, "exactly the plan's talents")
	for tree: String in Talents.TREES:
		assert_eq(Talents.ids(tree).size(), 9, "%s: nine talents" % tree)
		assert_eq(Talents.tree_cost(tree), 10, "%s: the whole tree costs 10 points" % tree)
		for tier in range(1, Talents.TIER_COUNT):
			assert_eq(Talents.at_tier(tree, tier).size(), 2, "%s tier %d: two talents" % [tree, tier])
		assert_eq(Talents.at_tier(tree, 5).size(), 1, "%s: one crown" % tree)
	for id: String in EXPECTED:
		var e: Array = EXPECTED[id]
		var rec := Talents.record(id)
		assert_eq([int(rec.tier), int(rec.get("column", -1))], [e[0], e[1]], "%s: tier %d, column %d" % [id, e[0], e[1]])
		assert_eq(Talents.cost_of(id), 2 if int(e[0]) == 5 else 1, "%s: the crown costs 2, the rest 1" % id)
		_near_dict(Talents.modifiers_of(id), e[2], "%s's passives" % id)
		assert_eq(Talents.grants_of(id), e[3], "%s's grants" % id)
		for g: Variant in e[3]:
			assert_eq(Progression.granted_by(str(g)), "talent", "%s is granted_by talent" % g)
	assert_true(Talents.data_errors(GameData.records).is_empty(), "the shipped data passes the talent checks (%s)" %
		[Talents.data_errors(GameData.records)])


func test_requirements_columns_and_tier_levels() -> void:
	assert_eq(Talents.tier_levels(), [6, 8, 9, 10, 12], "tiers open at levels 6, 8, 9, 10 and 12")
	for tree: String in Talents.TREES:
		for tier in range(1, Talents.TIER_COUNT + 1):
			for id: Variant in Talents.at_tier(tree, tier):
				var rec := Talents.record(str(id))
				assert_eq(Talents.level_needed(str(id)), Talents.tier_level(tier), "%s opens at its tier's level" % id)
				var reqs := Talents.requires_of(str(id))
				if tier == 1:
					assert_eq(reqs, [], "%s needs nothing" % id)
				elif tier == Talents.TIER_COUNT:
					var both := Talents.at_tier(tree, tier - 1)
					reqs.sort()
					both.sort()
					assert_eq(reqs, both, "%s (the crown) needs both talents of tier 4" % id)
				else:
					var above := ""
					for other: Variant in Talents.at_tier(tree, tier - 1):
						if int(Talents.record(str(other)).column) == int(rec.column):
							above = str(other)
					assert_eq(reqs, [above], "%s needs the talent above it (%s)" % [id, above])


func test_ancestries_match_the_plan() -> void:
	var ids := Talents.ancestry_ids()
	ids.sort()
	assert_eq(ids, ["ancestry.stoneblood", "ancestry.stormborn", "ancestry.wildheart"], "three ancestries to choose")
	assert_false(Talents.is_choosable("ancestry.neutral"), "the prologue's neutral ancestry is no choice")
	assert_false(Talents.is_choosable("talent.guardian_stone_hide"), "nor is a talent")
	for id: String in ANCESTRIES:
		var e: Array = ANCESTRIES[id]
		assert_true(Talents.is_choosable(id), "%s can be chosen" % id)
		assert_eq(Talents.attribute_bonus_of(id), e[0], "%s's attribute points" % id)
		var p := Talents.passives_for([], id)
		_near_dict(p.modifiers, e[1], "%s's passives" % id)
		assert_eq(p.resistances, {}, "%s adds no resistance by damage type" % id)
		assert_eq(Talents.signature_of(id), e[2], "%s's signature" % id)
		assert_eq(Progression.granted_by(str(e[2])), "ancestry", "%s is granted_by ancestry" % e[2])
		assert_eq(Array(Talents.dialogue_tags_of(id)), e[3], "%s's dialogue tags" % id)
	assert_eq(Talents.passives_for([], "ancestry.neutral"), {"modifiers": {}, "resistances": {}}, "the neutral one gives nothing")


# --------------------------------------------------------------------------- learning

func test_check_refuses_in_order_and_learn_spends_once() -> void:
	var c := {"level": 6, "talent_points": 0, "talents": []}
	assert_eq(str(Talents.check(c, "talent.nothing").reason), "unknown", "an unknown id")
	assert_eq(str(Talents.check(c, "ability.bulwark").reason), "unknown", "an ability is no talent")
	assert_eq(str(Talents.check(c, "talent.destroyer_shoulder_charge").reason), "level", "tier 2 waits for level 8")
	assert_eq(str(Talents.check(c, "talent.destroyer_shoulder_charge").message), "Shoulder Charge opens at level 8.",
		"and says so")
	c.level = 8
	assert_eq(str(Talents.check(c, "talent.destroyer_shoulder_charge").reason), "requires", "then its requirement")
	assert_eq(str(Talents.check(c, "talent.destroyer_shoulder_charge").message), "Shoulder Charge needs Heavy Hands first.",
		"named")
	assert_eq(str(Talents.check(c, "talent.destroyer_heavy_hands").reason), "points", "then the points")
	assert_eq(str(Talents.check(c, "talent.destroyer_heavy_hands").message),
		"Heavy Hands costs 1 talent point (you have 0).", "counted")
	c.talent_points = 2
	var r := Talents.learn(c, "talent.destroyer_heavy_hands")
	assert_true(r.ok and int(r.spent) == 1, "Heavy Hands learned for one point")
	assert_eq([c.talents, int(c.talent_points)], [["talent.destroyer_heavy_hands"], 1], "the point is spent")
	r = Talents.learn(c, "talent.destroyer_heavy_hands")
	assert_eq([str(r.reason), int(r.spent), int(c.talent_points)], ["known", 0, 1], "a second time: known, nothing spent")
	assert_true(Talents.learn(c, "talent.destroyer_shoulder_charge").ok, "the talent below it opens")
	assert_eq(int(c.talent_points), 0, "for the last point")
	c.talent_points = 1
	c.level = 12
	for id: String in ["talent.destroyer_relentless", "talent.destroyer_cleave_of_ages"]:
		c.talent_points = int(c.talent_points) + 1
		assert_true(Talents.learn(c, id).ok, "%s down column 1" % id)
	assert_eq(str(Talents.check(c, "talent.destroyer_titans_wrath").reason), "requires", "the crown needs column 2's tier 4 too")
	assert_true(str(Talents.check(c, "talent.destroyer_titans_wrath").message).contains("Bloodied Fury"), "named")
	c.talents.append_array(["talent.destroyer_iron_grip", "talent.destroyer_bone_breaker", "talent.destroyer_juggernaut",
		"talent.destroyer_bloodied_fury"])
	c.talent_points = 1
	assert_eq(str(Talents.check(c, "talent.destroyer_titans_wrath").reason), "points", "the crown costs two")
	c.talent_points = 2
	r = Talents.learn(c, "talent.destroyer_titans_wrath")
	assert_true(r.ok and int(r.spent) == 2 and int(c.talent_points) == 0, "two points for the crown")
	assert_eq(Talents.points_spent(c.talents), 10, "the whole tree: 10 points")
	assert_eq(Talents.points_at_level(12), 11, "11 points at level 12 (one per level from level 2)")
	assert_eq(Talents.talents_of({"talents": ["talent.guardian_bulwark", 3, "", "talent.guardian_bulwark"]}),
		["talent.guardian_bulwark"], "talents_of keeps each string id once")


# --------------------------------------------------------------------------- passives

func test_passives_combine_products_and_sums() -> void:
	var p := Talents.passives_for(["talent.destroyer_heavy_hands", "talent.destroyer_bone_breaker",
		"talent.destroyer_relentless", "talent.guardian_tireless", "talent.guardian_grounded",
		"talent.guardian_protector", "talent.primordial_regrowth", "talent.primordial_wellspring",
		"talent.primordial_kindled", "talent.primordial_worldsong", "talent.unknown"], "ancestry.stormborn")
	var m: Dictionary = p.modifiers
	assert_near(float(m.outgoing_poise_mult), 1.05 * 1.10, 1e-9, "Heavy Hands x Bone Breaker")
	assert_near(float(m.stamina_cost_mult), 0.85 * 0.9, 1e-9, "Relentless x Tireless")
	assert_near(float(m.heal_received_mult), 1.2 * 1.15, 1e-9, "Protector x Regrowth")
	assert_near(float(m.magic_damage_mult), 1.15 * 1.10, 1e-9, "Worldsong x Stormborn")
	assert_near(float(m.essence_add), 40.0 + 30.0, 1e-9, "Wellspring + Stormborn")
	assert_near(float(m.elemental_resist_add), 0.10 + 0.10, 1e-9, "Grounded + Stormborn")
	assert_near(float(m.fury_gain_mult), 1.2, 1e-9, "Kindled")
	assert_false(m.has("armor_flat"), "nothing unlearned")
	var w := Talents.passives_for(["talent.primordial_kindled"], "ancestry.wildheart").modifiers as Dictionary
	assert_near(float(w.fury_gain_mult), 1.2 * 1.25, 1e-9, "Kindled x Wildheart")
	var into := {"armor_flat": 5.0, "damage_taken_mult": 0.5}
	Talents.combine(into, {"armor_flat": 10, "damage_taken_mult": 0.5, "bad": "x"})
	assert_eq(into, {"armor_flat": 15.0, "damage_taken_mult": 0.25}, "combine: sums and products, non-numbers left out")


func test_player_facing_lines() -> void:
	assert_eq(Talents.modifier_lines({"heavy_damage_mult": 1.1, "outgoing_poise_mult": 1.05}),
		PackedStringArray(["Heavy attack damage +10%", "Poise damage dealt +5%"]), "Heavy Hands")
	assert_eq(Talents.modifier_lines({"stamina_cost_mult": 0.85, "armor_flat": 15, "grab_reach_add": 1.5,
		"elemental_resist_add": 0.1, "fury_on_kill_add": 6, "move_speed_mult": 1.0}),
		PackedStringArray(["Armour +15", "Elemental resistance +10%", "Grab reach +1.5 m", "Stamina costs -15%",
		"Fury per kill +6"]), "defence first, neutral values left out")
	assert_eq(Talents.effect_lines("talent.destroyer_shoulder_charge"), PackedStringArray([
		"New ability: Shoulder Charge - lower your shoulder and charge 12 m, bowling over everything in your path (22 stamina, 9 s cooldown)"]),
		"a grant names the ability, what it does and what it costs")
	assert_eq(Talents.effect_lines("talent.guardian_mountains_heart"), PackedStringArray(["Health +250"]), "a crown's passive")
	var s := Talents.ancestry_summary("ancestry.stoneblood")
	assert_eq([s.name, s.attributes], ["Stoneblood", "Endurance +2, Constitution +3"], "the summary's attributes")
	assert_eq(s.passives, PackedStringArray(["Armour +10", "Poise (staggers less) +20"]), "its strengths")
	assert_true(str(s.signature).begins_with("Bedrock Ward - the mountain in your blood rises"), "its signature (%s)" % s.signature)
	assert_true(str(s.signature).ends_with("(25 essence, 20 s cooldown)"), "with its cost")
	assert_true(str(s.peoples).contains("Moot"), "and the peoples who answer to it")


# --------------------------------------------------------------------------- data checks

func test_data_checks_catch_broken_records() -> void:
	var prog: Dictionary = GameData.get_record(Progression.RECORD_ID)
	var no_levels := prog.duplicate(true)
	no_levels.erase("talent_tier_levels")
	var e := "\n".join(Talents.data_errors(_records_with({}).merged({Progression.RECORD_ID: no_levels}, true)))
	assert_true(e.contains("talent_tier_levels is missing"), "tier levels are required while talents exist")
	assert_true(_errors_with({Progression.RECORD_ID: {"talent_tier_levels": [6, 8, 9]}}).contains("must list 5 levels"), "five tiers")
	assert_true(_errors_with({Progression.RECORD_ID: {"talent_tier_levels": [6, 9, 8, 10, 12]}}).contains("must rise"), "rising")
	assert_true(_errors_with({Progression.RECORD_ID: {"talent_tier_levels": [6, 8, 9, 10, 25]}}).contains("outside levels 1-20"),
		"within the cap")
	assert_true(_errors_with({"talent.destroyer_bone_breaker": {"requires_level": 9}}).contains(
		"requires_level 9, but tier 2 opens at level 8"), "requires_level is the tier's")
	assert_true(_errors_with({"talent.destroyer_bone_breaker": {"requires": ["talent.guardian_stone_hide"]}}).contains(
		"of another tree"), "requirements stay in the tree")
	assert_true(_errors_with({"talent.destroyer_bone_breaker": {"requires": ["talent.destroyer_juggernaut"]}}).contains(
		"not in a lower tier"), "requirements come from a lower tier")
	var extra: Dictionary = GameData.get_record("talent.destroyer_heavy_hands").duplicate(true)
	extra["id"] = "talent.destroyer_extra"
	e = _errors_with({"talent.destroyer_extra": extra})
	assert_true(e.contains("at most two talents per tier") and e.contains("column 1 of destroyer tier 1"),
		"two per tier, one per column (%s)" % e)
	e = _errors_with({"talent.destroyer_shoulder_charge": {"effects": {"modifiers": {}, "grants": ["ability.heavy_footfall"], "replaces": {}}}})
	assert_true(e.contains("whose granted_by is ''"), "a talent grants talent abilities")
	assert_true(e.contains("ability.shoulder_charge") and e.contains("0 talents grant it"), "and every talent ability is granted")
	assert_true(_errors_with({"ability.shoulder_charge": {"unlock_level": 9}}).contains("unlocks at level 9, after the talent's level 8"),
		"a grant is open at its talent's level")
	e = _errors_with({"ancestry.wildheart": {"signature": ""}})
	assert_true(e.contains("needs a signature ability"), "a choosable ancestry has a signature")
	assert_true(e.contains("ability.wild_surge") and e.contains("signature of 0 ancestries"), "and every ancestry ability is one's")
	var lib: Array = (prog.ability_library as Array).duplicate()
	lib.erase("ability.thunderhead")
	assert_true(_errors_with({Progression.RECORD_ID: {"ability_library": lib}}).contains(
		"ability.thunderhead is not in progression.default's ability_library"), "signatures are in the library")
	var bad := {"schema_version": 1, "id": "talent.guardian_bad", "type": "talent", "display_name": "Bad", "tree": "guardian",
		"tier": 5, "column": 1, "cost": 2, "requires": [], "requires_level": 12,
		"effects": {"modifiers": {"heal_per_tick": 5, "damage_taken_mult": 0}, "grants": [], "replaces": {}}}
	var v := "\n".join(DataValidator.validate_record(bad, "test.json").errors)
	assert_true(v.contains("a passive cannot heal over time or slow"), "no periodic heal on a passive (%s)" % v)
	assert_true(v.contains("a multiplier must be above 0"), "no zero multiplier")
	assert_true(v.contains("a tier-5 capstone stands in column 0"), "the crown's column")


# --------------------------------------------------------------------------- the world's milestones

func test_tiers_follow_the_worlds_level_milestones() -> void:
	var levels := Talents.tier_levels()
	assert_eq(Progression.level_cap(), 20, "the level cap stays 20 (the XP table runs to it; level 12 is a milestone)")
	assert_true(int(levels[-1]) <= Progression.level_cap(), "every tier opens below the cap")
	assert_eq(Progression.xp_for_level(int(levels[-1])), 3850,
		"the crowns open at level 12, 3,850 XP: the throne's level in the world budget (plan §5.8: 4,120 guaranteed)")
	var ws := CharacterState.world_start(Progression.record(), GameData.get_record("player.giant"))
	assert_eq(int(ws.level), int(levels[0]), "a campaign entering the world stands at tier 1's level (6)")
	assert_eq(int(ws.talent_points), Talents.points_at_level(int(ws.level)), "with the Valley's talent points unspent (5)")
	for pair: Array in [["growth.04", 1], ["growth.05", 3], ["growth.06", 4]]:
		var lv := int(GameData.get_record(str(pair[0])).get("required_level", 1))
		var open := 0
		for t in range(1, Talents.TIER_COUNT + 1):
			if Talents.tier_level(t) <= lv:
				open = t
		assert_eq(open, int(pair[1]), "%s's level %d opens tiers 1-%d" % [pair[0], lv, pair[1]])
	assert_true(Talents.points_at_level(int(levels[-1])) >= Talents.tree_cost("destroyer") + 1,
		"a level-12 giant holds one whole tree and a talent more")
