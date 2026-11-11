extends IntegrationSuite
## The main thread in every order of the oaths (P36; plan M6-M9 §3.20, §5.7, decision 26; the M8 gate's
## acceptance), teleport-assisted: the campaign from world_start in level.world with Quests over every
## shipped quest, the opening taken as won (the beacon's scouts cleared, the beacon lit), the giant grown
## by its debug growth where the shrines would; each oath is won the way its first-oath resolution is
## written - its stages' flags set as the dialogue or the deed that resolves it would set them (the
## resolution's value of oath.<x>.outcome, then oath.<x>.done) - and Quests completes it, paying its
## XP, its floors and its reward. For every ordered pair of the oaths that ship (six orders with
## quest.oath_wood; on P36's branch, where P35's wood oath is not yet, the orders with it are skipped and
## the W21 merge runs them) and for all three:
##   * the first oath's resolution is open at stage 4 and lifts the giant to stage 5's level, and the
##     stage-5 shrines' oath condition holds;
##   * the second completes the oaths stage, lifts the giant to stage 6's level and opens the Standing
##     Stones (stage 6);
##   * grow6 (the Stones' gift), entering the Moot, the champion settled (Harrok spared: the MootArena of
##     the Moot's chunk reconciles his clan) and the Stone Throne taken (the throne of the same chunk):
##     the main thread completes at level 12, campaign.completed opens the campaign's end screen ("The
##     Giant King") with the oaths' outcomes.

const START_CP := "world.cp.kingsgate_shelf"
const MAIN := "quest.world_main"
const OATHS := ["quest.oath_march", "quest.oath_wood", "quest.oath_crown"]
## The Moot's chunks: its ring and arena (c4_1), the Stone Throne (c4_0).
const MOOT_PARTS := ["res://scenes/world/chunks/c4_1_0.tscn", "res://scenes/world/chunks/c4_0_0.tscn"]
const THRONE := "world.stonehold.stone_throne"

var _screens: Array = []


func before_each() -> void:
	await super()
	_screens.clear()
	Events.ui_screen_requested.connect(_on_screen)


func after_each() -> void:
	if Events.ui_screen_requested.is_connected(_on_screen):
		Events.ui_screen_requested.disconnect(_on_screen)
	Quests.end_dialogue()
	FactionState.reset_for_tests()
	await super()


func _on_screen(screen: String, args: Dictionary) -> void:
	_screens.append([screen, args])


func _settle() -> void:
	await step_ticks(Quests.EVALUATE_EVERY_TICKS * 2 + 1)


## The campaign from world_start with the opening won: stage 4, the main thread on its oaths stage.
func _opening() -> GiantPlayer:
	GameSession.start_world_for_tests(START_CP)
	GameSession.level_id = "level.world"
	var p := spawn_player(Vector3(0, 0.05, 0), 0.0)
	GameSession.on_level_ready(world, p)
	p.global_position = Vector3(0, 0.05, 0)
	p.velocity = Vector3.ZERO
	p.entity.apply_status("status.debug_invulnerable", NAN, -1.0, "test")
	Quests.test_active = true
	Quests.scope = PackedStringArray()
	await _settle()
	WorldState.set_flag(EncounterDirector.cleared_flag("encounter.crownmarch_kingsgate_scouts"), true)
	WorldState.set_flag("world.kingsgate.lit", true)
	await _settle()
	assert_true(await _grow(p, 4), "the giant grows to stage 4")
	await _settle()
	assert_eq(Quests.stage_of(MAIN), "oaths", "the main thread waits on the oaths at stage 4")
	return p


func _grow(p: GiantPlayer, stage: int) -> bool:
	for i in 240:
		if bool(p.growth.debug_set_stage(stage).get("ok", false)):
			return true
		await step_ticks(1)
	return false


## A first-oath resolution of the oath quest `id` (the first in name order: deterministic).
func _resolution(id: String) -> String:
	var roads := OathRules.first_oath_resolutions(id, GameData.records)
	return roads[0] if not roads.is_empty() else ""


## Wins the oath `id` the way its resolution writes it: every flag test of its stages' complete_when
## made true (equals values as written), the outcome first; Quests completes it.
func _win(id: String) -> String:
	var key := OathRules.oath_key(id)
	var outcome := _resolution(id)
	WorldState.set_flag(OathRules.outcome_flag(key), outcome)
	for s: Dictionary in GameData.get_record(id).get("stages", []):
		_set_flags_of(s.get("complete_when"))
		await _settle()
	WorldState.set_flag(OathRules.done_flag(key), true)
	await _settle()
	return outcome


func _set_flags_of(c: Variant) -> void:
	if typeof(c) == TYPE_ARRAY:
		for x: Variant in c:
			_set_flags_of(x)
	elif typeof(c) == TYPE_DICTIONARY:
		var d: Dictionary = c
		match str(d.get("type", "")):
			"flag":
				if not QuestConditions.truthy(WorldState.get_flag(str(d.flag))):
					WorldState.set_flag(str(d.flag), d.get("equals", true))
			"all", "any", "count":
				_set_flags_of(d.get("of"))


func _shrine_open(shrine_id: String) -> bool:
	var c := QuestConditions.empty_context()
	c.flags = WorldState.flags
	return QuestConditions.all_hold(GameData.get_record(shrine_id).get("growth_requires_conditions", []), c)


func _find(root: Node, world_id: String) -> Node:
	for n in root.find_children("*", "", true, false):
		if "world_id" in n and str(n.get("world_id")) == world_id:
			return n
	return null


## The main thread for the oaths in `order` (two or three of them).
func _run(order: Array) -> void:
	var p := await _opening()
	var first: String = order[0]
	assert_eq(Quests.quest_state(first), Quests.ACTIVE, "%s starts at stage 4" % first)
	var outcome := await _win(first)
	assert_eq(Quests.quest_state(first), Quests.COMPLETED, "%s won first by %s" % [first, outcome])
	assert_true(p.progression.level >= WorldXp.growth_level("growth.05"), "the first oath lifts the giant to stage 5's level (%d)" % p.progression.level)
	assert_true(_shrine_open("shrine.world_greywood"), "the stage-5 shrines open after the first oath")
	assert_true(await _grow(p, 5), "the giant grows to stage 5")
	for i in range(1, order.size()):
		var id: String = order[i]
		assert_eq(Quests.quest_state(id), Quests.ACTIVE, "%s is open" % id)
		var o := await _win(id)
		assert_eq(Quests.quest_state(id), Quests.COMPLETED, "%s won by %s" % [id, o])
		if i == 1:
			assert_eq(Quests.stage_of(MAIN), "grow6", "two oaths complete the oaths stage (%s)" % [order])
			assert_true(p.progression.level >= WorldXp.growth_level("growth.06"), "two oaths lift the giant to stage 6's level (%d)" % p.progression.level)
			assert_true(_shrine_open("shrine.world_stones"), "the Standing Stones grow a giant to stage 6")
	var titan_before := WorldItems.count(WorldState.inventory, WorldItems.TITAN_IRON)
	assert_true(await _grow(p, 6), "the giant grows to stage 6")
	await _settle()
	assert_eq(Quests.stage_of(MAIN), "moot", "grow6 completes")
	assert_eq(WorldItems.count(WorldState.inventory, WorldItems.TITAN_IRON), titan_before + 1, "the Stones' gift: 1 titan iron")
	Events.area_entered.emit(Sim.tick, "world.area.moot", p.entity.entity_id)
	await _settle()
	assert_eq(Quests.stage_of(MAIN), "champion", "entering the Moot completes its stage")
	var part := Node3D.new()
	world.add_child(part)
	for path: String in MOOT_PARTS:
		part.add_child((load(path) as PackedScene).instantiate())
	await step_ticks(2)
	var arena: MootArena = null
	for n in part.find_children("*", "", true, false):
		if n is MootArena:
			arena = n
	assert_true(arena != null, "the Moot's arena is in its chunk")
	WorldState.set_flag("boss.harrok.outcome", "spared")
	if arena != null:
		arena.p34_on_yield_decided(arena.boss_id, "spare")
	await _settle()
	assert_true(QuestConditions.truthy(WorldState.get_flag("faction.harrok_clan.reconciled")), "Harrok spared reconciles his clan")
	assert_eq(Quests.stage_of(MAIN), "throne", "the champion settled")
	var throne := _find(part, THRONE) as StoneThrone
	assert_true(throne != null, "the Stone Throne is in the Moot's chunk")
	if throne == null:
		return
	assert_true(throne.claim(), "the giant takes the Stone Throne")
	await _settle()
	assert_eq(Quests.quest_state(MAIN), Quests.COMPLETED, "the main thread completes (%s)" % [order])
	assert_true(QuestConditions.truthy(WorldState.get_flag("campaign.completed")), "campaign.completed")
	assert_true(p.progression.level >= 12, "the finale reaches level 12 (%d)" % p.progression.level)
	var ends := _screens.filter(func(s: Array) -> bool: return str(s[0]) == "end")
	assert_eq(ends.size(), 1, "the campaign's end screen opens once")
	if ends.size() == 1:
		var args: Dictionary = ends[0][1]
		assert_true(bool(args.get("campaign", false)), "as the campaign's end")
		var lines := EndScreen.campaign_lines(args)
		assert_eq(str(lines[lines.size() - 1]), str(EndScreen.CHAMPION_LINES.spared), "its last line is the champion's outcome")
		for id: String in order:
			var key := OathRules.oath_key(id)
			assert_eq(str(args.get(key, "")), str(WorldState.get_flag(OathRules.outcome_flag(key), "")), "it names %s's outcome" % id)


## The orders of the oaths that ship: every ordered pair, and all three in their written order.
func _orders() -> Array:
	var shipped := OATHS.filter(func(id: String) -> bool: return GameData.has_record(id))
	var out: Array = []
	for a: String in OATHS:
		for b: String in OATHS:
			if a != b:
				out.append([a, b])
	out.append(OATHS.duplicate())
	var skipped := out.filter(func(o: Array) -> bool: return not o.all(func(id: String) -> bool: return shipped.has(id)))
	if not skipped.is_empty():
		print("    main thread: skipped %d orders with an oath not on this branch (%s)" % [skipped.size(),
			", ".join(OATHS.filter(func(id: String) -> bool: return not shipped.has(id)))])
	return out.filter(func(o: Array) -> bool: return o.all(func(id: String) -> bool: return shipped.has(id)))


func test_the_main_thread_in_every_order_of_the_oaths() -> void:
	var orders := _orders()
	assert_true(orders.size() >= 2, "at least the march and the crown in both orders (%d orders)" % orders.size())
	for order: Array in orders:
		print("    main thread: %s" % " -> ".join(order.map(func(id: String) -> String: return OathRules.oath_key(id))))
		await _run(order)
		await _reset()


## Back to a clean campaign between orders (the suite's own reset, as between tests).
func _reset() -> void:
	Quests.end_dialogue()
	FactionState.reset_for_tests()
	for c in world.get_children():
		c.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	Sim.clear_pending()
	WorldState.clear()
	_screens.clear()
	add_box(Vector3(120, 1, 120), Vector3(0, -0.5, 0))
	await step_ticks(1)
