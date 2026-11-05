extends TestSuite
## P12 rules (plan §3.14, §4.7): the XP table and its level-ups at 100 / 250 / 450 / 700 / 1,000,
## 3 attribute points and 1 talent point per level, attribute allocation, the derived preview
## (Endurance, Dexterity cap, Constitution, Intellect, Willpower), the abilities a level and stage
## meet and where they are auto-slotted, loot rolls, the loot_table / item / enemy / prop / weapon
## schema fields, the progression post-pass, and the shipped P12 data.

const LIBRARY_ORDER := ["ability.heavy_footfall", "ability.sweeping_blow", "ability.stone_skin",
	"ability.crushing_grip", "ability.boulder_hurl", "ability.runic_bolt", "ability.ancestral_mend",
	"ability.thunder_roar", "ability.titan_surge"]


func _validate(rec: Dictionary) -> Dictionary:
	return DataValidator.validate_record(rec, "test.json")


func _errors(rec: Dictionary) -> String:
	return "\n".join(_validate(rec).errors)


func _warnings(rec: Dictionary) -> String:
	return "\n".join(_validate(rec).warnings)


func _character(level := 1, xp := 0, unspent := 0, talents := 0) -> Dictionary:
	return {"level": level, "xp": xp, "unspent_attribute_points": unspent, "talent_points": talents,
		"attributes": Progression.attributes_of({})}


# --------------------------------------------------------------------------- XP and levels

func test_xp_table_and_level_thresholds() -> void:
	for l in range(1, 20):
		assert_eq(Progression.xp_to_next(l), 100 + 50 * (l - 1), "xp_to_next(%d) = 100 + 50 x (L - 1)" % l)
		assert_eq(Progression.xp_to_next(l), CombatRules.xp_to_next_level(l), "the record matches the formula at %d" % l)
	assert_eq(Progression.xp_to_next(20), 0, "level 20 is the cap")
	assert_eq(Progression.xp_to_next(0), 0, "no level 0")
	assert_eq(Progression.level_cap(), 20, "cap 20")
	var thresholds := {1: 0, 2: 100, 3: 250, 4: 450, 5: 700, 6: 1000}
	for l: int in thresholds:
		assert_eq(Progression.xp_for_level(l), int(thresholds[l]), "level %d at %d XP in total" % [l, thresholds[l]])
	var cases := [[0, 1], [99, 1], [100, 2], [249, 2], [250, 3], [449, 3], [450, 4], [699, 4], [700, 5],
		[999, 5], [1000, 6], [1000000, 20]]
	for c: Array in cases:
		assert_eq(Progression.level_for_xp(int(c[0])), int(c[1]), "%d XP is level %d" % [c[0], c[1]])
	assert_eq(Progression.level_progress(3, 370), [120, 200], "the HUD's Lv 3  120 / 200 XP")
	assert_eq(Progression.level_progress(3, 268), [18, 200], "the save's level 3 with 268 XP")
	assert_eq(int(Progression.level_progress(20, 20000)[1]), 0, "nothing more to earn at the cap")


func test_add_xp_gives_three_attribute_points_and_one_talent_point_per_level() -> void:
	var c := _character()
	var r := Progression.add_xp(c, 99)
	assert_eq([int(r.old_level), int(r.new_level), int(r.gained)], [1, 1, 99], "99 XP: still level 1")
	assert_eq(int(c.unspent_attribute_points), 0, "no points yet")
	r = Progression.add_xp(c, 1)
	assert_eq(int(r.new_level), 2, "100 XP: level 2")
	assert_eq([int(r.attribute_points), int(r.talent_points)], [3, 1], "3 attribute points and 1 talent point")
	assert_eq([int(c.level), int(c.xp), int(c.unspent_attribute_points), int(c.talent_points)], [2, 100, 3, 1],
		"written into the character")
	r = Progression.add_xp(c, 350)
	assert_eq([int(r.old_level), int(r.new_level)], [2, 4], "450 XP: two levels at once")
	assert_eq([int(r.attribute_points), int(r.talent_points)], [6, 2], "points for both")
	assert_eq([int(c.unspent_attribute_points), int(c.talent_points)], [9, 3], "accumulated")
	var before := c.duplicate(true)
	assert_eq(int(Progression.add_xp(c, 0).gained), 0, "0 XP adds nothing")
	assert_eq(int(Progression.add_xp(c, -50).gained), 0, "negative XP adds nothing")
	assert_eq(c, before, "and changes nothing")
	var capped := _character()
	r = Progression.add_xp(capped, 1000000)
	assert_eq(int(capped.level), 20, "levels stop at the cap")
	assert_eq([int(capped.unspent_attribute_points), int(capped.talent_points)], [57, 19], "19 levels of points")
	r = Progression.add_xp(capped, 500)
	assert_eq(int(r.new_level), 20, "no level beyond the cap")
	assert_eq(int(capped.xp), 1000500, "but XP still counts")


func test_allocate_validates_points_and_attributes() -> void:
	var c := _character(2, 100, 3, 1)
	var r := Progression.allocate(c, {"strength": 2})
	assert_true(r.ok, "two points into Strength")
	assert_eq(int(c.attributes.strength), 12, "Strength 12")
	assert_eq(int(c.unspent_attribute_points), 1, "one point left")
	var before := c.duplicate(true)
	var refusals := [[{"luck": 1}, "unknown_attribute"], [{"strength": -1}, "negative"],
		[{"strength": 1.5}, "not_whole"], [{"strength": "one"}, "not_whole"], [{}, "nothing"],
		[{"strength": 0}, "nothing"], [{"strength": 1, "endurance": 1}, "not_enough_points"]]
	for case: Array in refusals:
		var out := Progression.allocate(c, case[0])
		assert_false(out.ok, "%s is refused" % [case[0]])
		assert_eq(str(out.reason), str(case[1]), "%s: %s" % [case[0], case[1]])
		assert_true(str(out.message) != "", "%s: with a message" % [case[0]])
	assert_eq(c, before, "a refusal changes nothing")
	assert_true(Progression.allocate(c, {"endurance": 1}).ok, "the last point")
	assert_eq(int(c.unspent_attribute_points), 0, "none left")
	assert_eq(Progression.attributes_of({"strength": 12.0, "dexterity": 40}), {"strength": 12, "endurance": 10,
		"dexterity": 40, "intellect": 10, "willpower": 10, "constitution": 10}, "six whole attributes, 10 by default")


func test_derived_preview_follows_the_attribute_rules() -> void:
	var rec := GameData.get_record("player.giant")
	var base := Progression.derived_preview(rec, Progression.attributes_of({}))
	assert_near(float(base.health), 500.0, 1e-6, "500 health at Endurance 10")
	assert_near(float(base.stamina), 100.0, 1e-6, "100 stamina")
	assert_near(float(base.essence), 100.0, 1e-6, "100 essence")
	assert_near(float(base.poise), 100.0, 1e-6, "100 poise")
	assert_near(float(base.recovery_scale), 1.0, 1e-9, "no recovery change at Dexterity 10")
	var e12 := Progression.derived_preview(rec, Progression.attributes_of({"endurance": 12}))
	assert_near(float(e12.health) - float(base.health), 30.0, 1e-6, "Endurance 12: +30 health")
	assert_near(float(e12.stamina) - float(base.stamina), 4.0, 1e-6, "and +4 stamina")
	for d: Array in [[20, 0.95], [40, 0.85], [60, 0.85], [5, 1.0]]:
		var v := Progression.derived_preview(rec, Progression.attributes_of({"dexterity": d[0]}))
		assert_near(float(v.recovery_scale), float(d[1]), 1e-9, "Dexterity %d: recovery x%.2f (capped at 15%%)" % [d[0], d[1]])
	assert_near(float(Progression.derived_preview(rec, {"constitution": 15}).poise), 115.0, 1e-6, "Constitution 15: +15 poise")
	assert_near(float(Progression.derived_preview(rec, {"intellect": 15}).essence), 110.0, 1e-6, "Intellect 15: +10 essence")
	assert_near(float(Progression.derived_preview(rec, {"willpower": 30}).elemental_resistance), 0.10, 1e-9,
		"Willpower 30: +10 points of elemental resistance")
	assert_near(float(Progression.derived_preview(rec, {"willpower": 80}).elemental_resistance), 0.20, 1e-9,
		"capped at 20 points")
	assert_near(float(Progression.derived_preview(rec, {"strength": 20}).damage_scale), 1.30, 1e-9,
		"Strength 20: x1.30 damage")
	var grown := Progression.derived_preview(rec, Progression.attributes_of({"endurance": 14}), {"health": 150.0, "stamina": 10.0})
	assert_near(float(grown.health), 710.0, 1e-6, "the boss table's 500 + 4 x 15 + 150 = 710")


# --------------------------------------------------------------------------- abilities

func test_newly_met_abilities_and_auto_slots() -> void:
	var lib := Progression.library()
	assert_eq(lib, LIBRARY_ORDER, "the library lists the eight abilities and the ultimate in slot order")
	var known := ["ability.heavy_footfall", "ability.sweeping_blow"]
	assert_eq(Progression.newly_met(lib, known, 1, 1), PackedStringArray(), "nothing new at level 1")
	assert_eq(Progression.newly_met(lib, known, 2, 1), PackedStringArray(["ability.stone_skin", "ability.crushing_grip"]),
		"level 2: Stone Skin and Crushing Grip")
	assert_eq(Progression.newly_met(lib, known, 3, 1), PackedStringArray(["ability.stone_skin", "ability.crushing_grip",
		"ability.runic_bolt"]), "level 3 at stage 1: + Runic Bolt (Boulder Hurl needs stage 2)")
	assert_true(Progression.newly_met(lib, known, 3, 2).has("ability.boulder_hurl"), "level 3 at stage 2: + Boulder Hurl")
	assert_eq(Progression.newly_met(lib, known + ["ability.stone_skin", "ability.crushing_grip", "ability.runic_bolt",
		"ability.boulder_hurl"], 4, 2), PackedStringArray(["ability.ancestral_mend", "ability.thunder_roar",
		"ability.titan_surge"]), "level 4: Mend, Roar and Titan Surge")
	for i in 8:
		assert_eq(Progression.preferred_slot(LIBRARY_ORDER[i], lib), "slot_%d" % (i + 1), "%s belongs in slot %d" % [LIBRARY_ORDER[i], i + 1])
	assert_eq(Progression.preferred_slot("ability.titan_surge", lib), "ultimate", "the ultimate's own slot")
	assert_eq(Progression.preferred_slot("ability.light_1", lib), "", "not in the library: no slot of its own")
	var lo := {"slot_1": "ability.heavy_footfall", "slot_2": "ability.sweeping_blow", "slot_3": "", "slot_4": "",
		"slot_5": "", "slot_6": "", "slot_7": "", "slot_8": "", "ultimate": ""}
	assert_eq(Progression.auto_slot(lo, "ability.stone_skin", lib), "slot_3", "Stone Skin: slot 3 (the first empty one too)")
	assert_eq(Progression.auto_slot(lo, "ability.runic_bolt", lib), "slot_6", "Runic Bolt keeps slot 6 free of Boulder Hurl")
	assert_eq(Progression.auto_slot(lo, "ability.titan_surge", lib), "ultimate", "the ultimate")
	lo["slot_6"] = "ability.heavy_footfall"
	assert_eq(Progression.auto_slot(lo, "ability.runic_bolt", lib), "slot_3", "its slot taken: the first empty one")
	lo["ultimate"] = "ability.titan_surge"
	assert_eq(Progression.auto_slot(lo, "ability.titan_surge", lib), "", "an ultimate never displaces another")
	for i in 8:
		lo["slot_%d" % (i + 1)] = "ability.heavy_footfall"
	assert_eq(Progression.auto_slot(lo, "ability.stone_skin", lib), "", "every slot full: learned but not slotted")
	assert_eq(Progression.slot_key_label("slot_6"), "6", "slot 6 shows its key")
	assert_eq(Progression.slot_key_label("ultimate"), "R", "the ultimate's key")


# --------------------------------------------------------------------------- loot

func test_loot_rolls_guaranteed_and_weighted_entries() -> void:
	assert_eq(Loot.roll("loot.ogre_king"), [{"item": "item.ogre_tusk", "count": 1}, {"item": "item.iron_ingot", "count": 1}],
		"the Ogre King: the tusk and an ingot, nothing rolled")
	assert_eq(Loot.roll("loot.crate_quarry"), [{"item": "item.iron_ingot", "count": 1}], "the quarry chest: one ingot")
	assert_eq(Loot.roll("loot.crate_armory"), [{"item": "item.iron_ingot", "count": 1}], "the armory crate: one ingot")
	assert_eq(Loot.roll(""), [], "no table, no loot")
	var table := {"rolls": 1, "entries": [{"item": "item.wood_scrap", "count": 1, "weight": 3.0},
		{"item": "item.iron_ingot", "count": 1, "weight": 1.0}]}
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var scrap := 0
	var sizes := {}
	for i in 2000:
		var drops := Loot.roll_table(table, rng)
		sizes[drops.size()] = true
		if str(drops[0].item) == "item.wood_scrap":
			scrap += 1
	assert_eq(sizes.keys(), [1], "one roll, one drop every time")
	assert_near(float(scrap) / 2000.0, 0.75, 0.04, "weight 3 of 4 drops about 75%% of the time (%d / 2000)" % scrap)
	var entries: Array = table.entries
	assert_eq(str(Loot.pick_entry(entries, 4.0, 0.0).item), "item.wood_scrap", "u = 0: the first entry")
	assert_eq(str(Loot.pick_entry(entries, 4.0, 0.7499).item), "item.wood_scrap", "u < 3/4: the first")
	assert_eq(str(Loot.pick_entry(entries, 4.0, 0.75).item), "item.iron_ingot", "u >= 3/4: the second")
	var zero_first := [{"item": "item.iron_ingot", "count": 1, "weight": 0.0}, {"item": "item.wood_scrap", "count": 1, "weight": 1.0}]
	assert_eq(str(Loot.pick_entry(zero_first, 1.0, 0.0).item), "item.wood_scrap", "a zero-weight entry is never picked")
	var merged := Loot.roll_table({"rolls": 2, "entries": [{"item": "item.wood_scrap", "count": 2, "weight": 1.0}],
		"guaranteed": [{"item": "item.wood_scrap", "count": 1}]}, rng)
	assert_eq(merged, [{"item": "item.wood_scrap", "count": 5}], "drops of one item are merged (1 + 2 + 2)")
	Sim.reseed(Sim.DEFAULT_SEED)
	var first := Loot.roll("loot.raider")
	Sim.reseed(Sim.DEFAULT_SEED)
	assert_eq(Loot.roll("loot.raider"), first, "the loot stream is seeded: the same roll after a reseed")
	var crit_before := Sim.rng.state
	Loot.roll("loot.raider")
	assert_eq(Sim.rng.state, crit_before, "loot never draws from Sim.rng (the crit stream)")


# --------------------------------------------------------------------------- schemas and data

func test_loot_table_and_item_schemas() -> void:
	assert_true(DataValidator.RECORD_TYPES.has("loot_table"), "loot_table is a record type")
	var good := {"schema_version": 1, "id": "loot.test", "type": "loot_table", "rolls": 1,
		"entries": [{"item": "item.wood_scrap", "count": 1, "weight": 2.5}],
		"guaranteed": [{"item": "item.iron_ingot", "count": 1}]}
	assert_eq(_validate(good).errors, PackedStringArray(), "a valid loot table")
	var refs := (_validate(good).refs as Array).map(func(x: Dictionary) -> String: return "%s:%s" % [x.type, x.id])
	assert_true(refs.has("item:item.wood_scrap") and refs.has("item:item.iron_ingot"), "entries reference items")
	var cases := [
		[{"rolls": 1, "entries": []}, "needs at least one weighted entry"],
		[{"rolls": -1}, "rolls: must be >= 0"],
		[{"rolls": 11}, "rolls: must be <= 10"],
		[{"entries": [{"item": "item.wood_scrap", "count": 0, "weight": 1}]}, "count: must be >= 1"],
		[{"entries": [{"item": "item.wood_scrap", "count": 1, "weight": 0}]}, "weight: must be > 0"],
		[{"entries": [{"item": "item.wood_scrap", "count": 1}]}, "missing required key 'weight'"],
		[{"chance": 0.5}, "unknown key 'chance'"],
	]
	for c: Array in cases:
		var rec := good.duplicate(true)
		rec.merge(c[0], true)
		assert_true(_errors(rec).contains(str(c[1])), "%s is refused (%s)" % [c[0], c[1]])
	var bare := {"schema_version": 1, "id": "loot.bare", "type": "loot_table", "rolls": 0}
	assert_true(_errors(bare).contains("missing required key 'entries'"), "entries are required")
	bare["entries"] = []
	assert_true(_warnings(bare).contains("can never drop anything"), "an empty table warns")
	var unrolled := {"schema_version": 1, "id": "loot.unrolled", "type": "loot_table", "rolls": 0,
		"entries": [{"item": "item.wood_scrap", "count": 1, "weight": 1}]}
	assert_true(_warnings(unrolled).contains("never rolled"), "entries with rolls 0 warn")
	var item := {"schema_version": 1, "id": "item.test", "type": "item", "stack_max": 1, "category": "quest",
		"quest_item": true}
	assert_eq(_validate(item).errors, PackedStringArray(), "item category and quest_item validate")
	item["category"] = "food"
	assert_true(_errors(item).contains("unknown value 'food'"), "a category from ITEM_CATEGORIES")
	item["category"] = "material"
	assert_true(_warnings(item).contains("a quest_item is usually of category quest"), "a material quest item warns")
	item["quest_item"] = "yes"
	assert_true(_errors(item).contains("quest_item: expected true/false"), "quest_item is a bool")


func test_loot_table_refs_on_enemies_props_and_the_weapon_cost_rule() -> void:
	var enemy: Dictionary = GameData.get_record("enemy.soldier").duplicate(true)
	enemy["loot_table"] = "loot.raider"
	var r := _validate(enemy)
	assert_eq(r.errors, PackedStringArray(), "an enemy may name a loot table")
	var refs := (r.refs as Array).map(func(x: Dictionary) -> String: return "%s:%s" % [x.type, x.id])
	assert_true(refs.has("loot_table:loot.raider"), "a reference to a loot_table record")
	enemy["loot_table"] = ""
	assert_eq(_validate(enemy).errors, PackedStringArray(), "an empty loot_table is allowed")
	var crate: Dictionary = GameData.get_record("prop.crate").duplicate(true)
	assert_eq(_validate(crate).errors, PackedStringArray(), "the crate's loot table validates")
	var bush: Dictionary = GameData.get_record("prop.bush").duplicate(true)
	bush["loot_table"] = "loot.raider"
	assert_true(_errors(bush).contains("loot_table is not for cosmetic props"), "a cosmetic prop has no loot")
	var club: Dictionary = GameData.get_record("weapon.club").duplicate(true)
	(club.upgrade as Dictionary)["cost"] = []
	assert_true(_errors(club).contains("upgrade.cost: must list at least one item"), "an upgrade always costs something")


func test_progression_post_pass() -> void:
	assert_eq(Progression.data_errors(GameData.records, GameData.record_paths), PackedStringArray(),
		"the shipped data passes the progression post-pass")
	var records := GameData.records.duplicate()
	var chained: Dictionary = (records["weapon.club_reinforced"] as Dictionary).duplicate(true)
	chained["upgrade"] = {"to": "weapon.hammer_reinforced", "cost": [{"item": "item.iron_ingot", "count": 2}]}
	records["weapon.club_reinforced"] = chained
	assert_true("\n".join(Progression.data_errors(records)).contains("has an upgrade of its own"),
		"a reforged weapon cannot be reforged again")
	records = GameData.records.duplicate()
	var shrunk: Dictionary = (records["weapon.club_reinforced"] as Dictionary).duplicate(true)
	shrunk["fit_max_stage"] = 1
	records["weapon.club_reinforced"] = shrunk
	assert_true("\n".join(Progression.data_errors(records)).contains("fits only up to stage 1"),
		"an upgrade fits at least as high as its source (PlayerEquipment.upgrade_problems)")
	records = GameData.records.duplicate()
	var prog: Dictionary = (records["progression.default"] as Dictionary).duplicate(true)
	(prog.ability_library as Array).append("ability.light_1")
	records["progression.default"] = prog
	assert_true("\n".join(Progression.data_errors(records)).contains("not an ability or ultimate"),
		"the library holds abilities and ultimates only")


func test_shipped_p12_data() -> void:
	for id: String in ["loot.ogre_king", "loot.crate_armory", "loot.crate_quarry", "loot.raider"]:
		assert_eq(str(GameData.get_record(id).get("type", "")), "loot_table", "%s ships" % id)
	var raider := GameData.get_record("loot.raider")
	for e: Dictionary in raider.entries:
		assert_true(str(e.item) != "item.iron_ingot", "raiders never drop iron (the iron count of §4.7)")
	var iron := 0
	for id: String in ["loot.ogre_king", "loot.crate_armory", "loot.crate_quarry"]:
		for g: Dictionary in GameData.get_record(id).get("guaranteed", []):
			if str(g.item) == "item.iron_ingot":
				iron += int(g.count)
	assert_eq(iron, 3, "3 of the Valley's 5 ingots come from loot (the village gives the other 2)")
	var xp := {"enemy.soldier": 20, "enemy.wolf": 15, "enemy.archer": 25, "enemy.mage": 30}
	for id: String in xp:
		assert_eq(int(GameData.get_record(id).get("xp_reward", 0)), int(xp[id]), "%s gives %d XP" % [id, xp[id]])
	var crate := GameData.get_record("prop.crate")
	assert_eq(str(crate.get("loot_table", "")), "loot.crate_quarry", "the crate rolls a loot table")
	assert_false(crate.has("loot"), "instead of an inline loot list")
	var items := {"item.supply_cache": ["quest", true], "item.ogre_tusk": ["trophy", false],
		"item.crown_first_king": ["quest", true], "item.iron_ingot": ["material", false]}
	for id: String in items:
		var rec := GameData.get_record(id)
		assert_eq(str(rec.get("category", "material")), str(items[id][0]), "%s is a %s" % [id, items[id][0]])
		assert_eq(bool(rec.get("quest_item", false)), bool(items[id][1]), "%s quest_item %s" % [id, items[id][1]])
	assert_eq(str(Progression.record().get("prototype_xp_label", "")), "Prototype pacing: accelerated quest XP",
		"the prototype pacing label (decision 7)")
