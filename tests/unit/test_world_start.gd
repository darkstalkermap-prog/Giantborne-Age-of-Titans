extends TestSuite
## progression.default's world_start (P20; plan M6-M9 §2.6): the character, inventory and flags of a
## campaign started in the world are the Valley's worst guaranteed outcome - its XP equals the
## floor of the Valley's XP budget (force: 1,050, computed here from the shipped data as
## tests/unit/test_xp_budget.gd does), its level and points follow from that XP, its abilities are
## the library's up to that level and its items are the force path's guaranteed loot.
## CharacterState.world_start builds it; GameSession.start_world_for_tests() / --mode=world start a
## campaign with it in level.world; the title's skip only works while level.world exists.

const PROGRESSION := "progression.default"
const MAIN := "quest.main"
const FOREST_OGRE := "valley.forest.ogre"
const KING := "valley.arena.ogre_king"
const GATE_PROP := "prop.gate_practice"
const BARRICADE_PROP := "prop.cart_barricade"
const STAND_IN := "res://scenes/test/flow_test_level.tscn"


func before_each() -> void:
	WorldState.clear()


func after_each() -> void:
	WorldState.clear()


func _ws() -> Dictionary:
	return GameData.get_record(PROGRESSION).get("world_start", {})


func _spawn(entity_id: String) -> Dictionary:
	for rec: Dictionary in GameData.records_of_type("encounter"):
		for sp: Dictionary in rec.get("spawns", []):
			if str(sp.entity_id) == entity_id:
				return sp
	fail("no encounter spawns %s" % entity_id)
	return {}


## The XP floor of the Valley: every main stage, the two mandatory kills, the practice gate and the
## worst outcome's own XP (force: the smashed barricade).
func _budget_floor() -> int:
	var total := 0
	for s: Dictionary in GameData.get_record(MAIN).get("stages", []):
		total += int(s.get("xp", 0))
	for id: String in [FOREST_OGRE, KING]:
		total += int(GameData.get_record(str(_spawn(id).definition)).get("xp_reward", 0))
	for id: String in [GATE_PROP, BARRICADE_PROP]:
		total += int(GameData.get_record(id).get("xp_reward", 0))
	return total


func _add_guaranteed(table_id: String, out: Dictionary) -> void:
	if table_id == "":
		return
	for g: Dictionary in GameData.get_record(table_id).get("guaranteed", []):
		out[str(g.item)] = int(out.get(str(g.item), 0)) + int(g.get("count", 1))


## What the force path is sure to bring: the mandatory kills' and props' guaranteed loot and the
## main stages' item rewards (the crates are optional).
func _force_path_loot() -> Dictionary:
	var out := {}
	for id: String in [FOREST_OGRE, KING]:
		var sp := _spawn(id)
		var table := str(sp.get("loot_table", ""))
		if table == "":
			table = str(GameData.get_record(str(sp.definition)).get("loot_table", ""))
		_add_guaranteed(table, out)
	for id: String in [GATE_PROP, BARRICADE_PROP]:
		_add_guaranteed(str(GameData.get_record(id).get("loot_table", "")), out)
	for s: Dictionary in GameData.get_record(MAIN).get("stages", []):
		for it: Dictionary in s.get("items", []):
			out[str(it.item)] = int(out.get(str(it.item), 0)) + int(it.get("count", 1))
	return out


func test_world_start_is_the_valley_budget_floor() -> void:
	var ws := _ws()
	assert_false(ws.is_empty(), "progression.default has world_start")
	var floor_xp := _budget_floor()
	assert_eq(floor_xp, 1050, "the Valley budget's floor is 1,050 XP (plan §4.7)")
	assert_eq(int(ws.xp), floor_xp, "world_start's XP is that floor")
	var level := Progression.level_for_xp(int(ws.xp))
	assert_eq(int(ws.level), level, "and its level is the level of that XP (%d)" % level)
	var prog := GameData.get_record(PROGRESSION)
	assert_eq(int(ws.unspent_attribute_points), (level - 1) * int(prog.attribute_points_per_level),
		"every level-up's attribute points, unspent")
	assert_eq(int(ws.talent_points), (level - 1) * int(prog.talent_points_per_level),
		"one talent point per level from level 2")
	assert_eq(int(GameData.get_record(str(ws.growth_profile)).get("stage", 0)), 3, "stage 3 (the Kingsfall growth)")
	assert_eq(str(ws.weapon), "weapon.club", "the base club")
	assert_eq(str(ws.ancestry), CharacterState.DEFAULT_ANCESTRY, "no ancestry chosen yet")


func test_world_start_items_are_the_force_path_guaranteed_loot() -> void:
	var expected := _force_path_loot()
	assert_eq(expected, {"item.ogre_tusk": 1, "item.iron_ingot": 1}, "the Ogre King's tusk and his iron ingot")
	var items := CharacterState.inventory_of(_ws().get("inventory", []))
	assert_eq(items, expected, "world_start's inventory is exactly that")


func test_world_start_knows_the_abilities_of_its_level_and_the_force_flags() -> void:
	var ws := _ws()
	var expected: Array = []
	for id: Variant in Progression.library():
		var unlock := int(GameData.get_record(str(id)).get("unlock_level", 1))
		if unlock <= int(ws.level):
			expected.append(str(id))
	var known: Array = ws.known_abilities
	expected.sort()
	known = known.duplicate()
	known.sort()
	assert_eq(known, expected, "the library's abilities up to level %d" % int(ws.level))
	assert_eq((ws.slots as Array).size(), 8, "eight slots")
	for id: Variant in ws.slots:
		assert_true(str(id) == "" or known.has(str(id)), "slot %s is a known ability" % id)
	var flags: Dictionary = ws.flags
	for f: String in ["slice.completed", "quest.main.done", "faction.village.hostile", "world.ogre_king.defeated"]:
		assert_true(QuestConditions.truthy(flags.get(f)), "%s is set" % f)
	assert_eq(str(flags.get("quest.village.outcome", "")), "force", "the force outcome")
	for f: Variant in flags:
		assert_false(str(f).begins_with("reward.village"), "no village reward was taken (%s)" % f)
		assert_false(str(f).begins_with("dialogue.elder.outcome.help"), "no help outcome (%s)" % f)


func test_character_state_world_start() -> void:
	var prog := GameData.get_record(PROGRESSION)
	var player := GameData.get_record("player.giant")
	var ws := _ws()
	var c := CharacterState.world_start(prog, player)
	var ng := CharacterState.new_game(prog, player)
	assert_eq(int(c.level), int(ws.level), "the level")
	assert_eq(int(c.xp), int(ws.xp), "the XP")
	assert_eq(int(c.growth_stage), 3, "stage 3")
	assert_eq(int(c.unspent_attribute_points), int(ws.unspent_attribute_points), "the attribute points")
	assert_eq(int(c.talent_points), int(ws.talent_points), "the talent points")
	assert_eq(str(c.weapon), "weapon.club", "the club")
	assert_eq(c.weapons_owned, ["weapon.club"], "owned")
	assert_eq(c.loadout.slots, ws.slots, "the slots")
	assert_eq(str(c.loadout.ultimate), str(ws.ultimate), "the ultimate")
	assert_eq((c.known_abilities as Array).size(), (ws.known_abilities as Array).size(), "the known abilities")
	assert_eq(c.talents, [], "no talents")
	assert_false(bool(c.ancestry_chosen), "no ancestry chosen")
	assert_false(c.has("resources"), "fresh pools (no saved resources)")
	assert_eq(c.attributes, ng.attributes, "the player's base attributes (the points are unspent)")
	assert_eq(str(c.id), str(ng.id), "the same giant")
	assert_eq(CharacterState.validate(c), PackedStringArray(), "a valid character")
	assert_eq(CharacterState.normalize(c), c, "already normalised")
	var plain := prog.duplicate(true)
	plain.erase("world_start")
	assert_eq(CharacterState.world_start(plain, player), ng, "without world_start it is the new game")


func test_start_world_for_tests_sets_up_the_campaign_in_the_world() -> void:
	GameSession.start_world_for_tests()
	var ws := _ws()
	assert_true(GameSession.is_campaign(), "the campaign")
	assert_eq(GameSession.level_id, GameSession.WORLD_LEVEL_ID, "in level.world")
	assert_eq(GameSession.current_level_id(), "level.world", "current_level_id")
	assert_eq(GameSession.character, CharacterState.world_start(GameData.get_record(PROGRESSION),
		GameData.get_record("player.giant")), "with the world_start character")
	assert_true(GameSession.pending_restore, "waiting for the level")
	assert_eq(GameSession.scene_reloads, ["new_game"] as Array[String], "a New Game reload (logged in tests)")
	for f: String in (ws.flags as Dictionary):
		assert_eq(WorldState.get_flag(f), ws.flags[f], "flag %s" % f)
	assert_eq(WorldState.count_of("item.ogre_tusk"), 1, "the tusk")
	assert_eq(WorldState.count_of("item.iron_ingot"), 1, "the ingot")
	assert_true(WorldState.deltas.is_empty(), "no Valley world changes come along")
	assert_true(bool(GameSession.progress.prologue_complete), "the prologue counts as complete")
	assert_false(bool(GameSession.progress.world_entered), "the world is entered when it loads")
	var q := Quests.condition_context()
	assert_eq(str(q.level_id), "level.world", "quests see the world level")
	assert_true(QuestConditions.holds({"type": "quest_done", "quest": "quest.main"}, q), "and the finished main quest")


func test_the_world_mode_needs_the_world_level() -> void:
	assert_false(GameSession.world_available(), "this build has no level.world scene yet")
	var r := GameSession.change_mode("world")
	assert_false(r.ok, "--mode=world / Skip refuse without it")
	assert_eq(str(r.message), GameSession.WORLD_MISSING, "and say why")
	assert_eq(GameSession.scene_reloads.size(), 0, "no reload")
	var o := GameSession.parse_args(PackedStringArray(["--mode=world", "--new-game", "--start=world.cp.kingsgate_shelf",
		"--no-user-settings"]))
	assert_eq(str(o.mode), "world", "--mode=world parses")
	assert_eq(str(o.start), "world.cp.kingsgate_shelf", "--start parses")
	GameSession.apply_args(o)
	assert_eq(GameSession.mode, GameSession.Mode.TITLE, "without the world the command line shows the title")
	TestFixtures.record_override(GameSession.WORLD_LEVEL_ID, {"schema_version": 1, "type": "level",
		"display_name": "The Old Kingdom", "scene": STAND_IN, "start_checkpoint": "world.cp.kingsgate_shelf"})
	assert_true(GameSession.world_available(), "a level.world record with a scene (a stub here)")
	GameSession.apply_args(o)
	assert_true(GameSession.is_campaign() and GameSession.level_id == "level.world", "--mode=world starts the world")
	assert_eq(GameSession.level_scene_path(), STAND_IN, "its scene")
	GameSession.reset_for_tests()
	r = GameSession.change_mode("world", {"new_game": true})
	assert_true(r.ok, "the title's Skip starts it")
	assert_eq(GameSession.scene_reloads.back(), "new_game", "with a New Game reload")
	assert_eq(int(GameSession.character.level), int(_ws().level), "from world_start")


func test_the_schema_checks_world_start() -> void:
	var rec := GameData.get_record(PROGRESSION).duplicate(true)
	assert_eq(DataValidator.validate_record(rec, "test.json").errors, PackedStringArray(), "the shipped record validates")
	rec.world_start.slots = ["ability.heavy_footfall"]
	rec.world_start.flags["Bad Flag"] = true
	rec.world_start.flags["test.p20.object"] = {"a": 1}
	rec.world_start.inventory = [{"item": "item.iron_ingot", "count": 0}]
	var e := "\n".join(DataValidator.validate_record(rec, "test.json").errors)
	assert_true(e.contains("world_start.slots must have exactly 8 entries"), "eight slots: %s" % e)
	assert_true(e.contains("Bad Flag"), "flag ids are checked: %s" % e)
	assert_true(e.contains("test.p20.object"), "flag values are scalars: %s" % e)
	assert_true(e.contains("count"), "item counts are 1-999: %s" % e)
