extends IntegrationSuite
## The Crownmarch walkthrough (P29; plan M6-M9 §3.12, the M7 gate): from world_start to Brannock's
## oath, once for each of its three resolutions, teleport-assisted - the fights are taken as won (their
## encounters' cleared flags) and every other step runs the shipped game: the campaign started from
## world_start in level.world, Quests over every shipped quest, the shipped chunks' props parts (the
## Kingsgate beacon's fire, the toll fort's gate, Brannock's south gatehouse) struck or lit by the giant,
## the growth to stage 4, and Edda's dialogue chosen by outcome:
##   * the opening: kings_door completes in the world, the beacon lights once its scouts are cleared
##     (its cache pays, the XP is floored at level 7), stage 4 completes grow4, the oaths stage waits
##     and Brannock's oath starts;
##   * help: offered, the toll gate broken at stage 4 and the fort and the Hollow cleared, then reported;
##   * intimidate: at stage 4, at once (the tribute);
##   * force: the south gatehouse smashed at stage 4 (the town turns hostile), then the oath by fear;
## and after each: the oath done with its outcome, its rewards (the oath's titan iron and iron, the
## resolution's own), the XP floored at level 9, the town's standing, and the main thread still on its
## oaths stage (M7 ships one oath of the three).

const START_CP := "world.cp.kingsgate_shelf"
const BEACON_PART := "res://scenes/world/chunks/c3_6_0.tscn"
const TOLL_PART := "res://scenes/world/chunks/c5_5_0.tscn"
const GATEHOUSE_PART := "res://scenes/world/chunks/c4_6_0.tscn"
const BEACON := "world.crownmarch.kingsgate_beacon_fire"
const TOLL_GATE := "world.crownmarch.toll_gate"
const GATEHOUSE := "world.crownmarch.brannock_south_gate"
const MAIN := "quest.world_main"
const MARCH := "quest.oath_march"


## The campaign from world_start in level.world, with the giant on a floor and Quests running every
## shipped quest; returns the giant once the opening has run (stage 4, the oaths stage active).
func _opening() -> GiantPlayer:
	GameSession.start_world_for_tests(START_CP)
	GameSession.level_id = "level.world"
	var p := spawn_player(Vector3(0, 0.05, 0), 0.0)
	GameSession.on_level_ready(world, p)
	# the session places the giant at its start checkpoint's index transform: back onto this floor
	p.global_position = Vector3(0, 0.05, 0)
	p.velocity = Vector3.ZERO
	Quests.test_active = true
	Quests.scope = PackedStringArray()
	await _settle()
	assert_eq(Quests.quest_state(MAIN), Quests.ACTIVE, "the world's main quest started from world_start")
	assert_eq(Quests.stage_of(MAIN), "beacon", "kings_door completes in the world: the beacon is next")
	assert_eq(Quests.main_quest_id, MAIN, "it is the main quest")
	var part := _part(BEACON_PART)
	var fire := _find(part, BEACON) as BeaconFire
	assert_true(fire != null, "the Kingsgate beacon's fire is in its chunk")
	assert_false(fire.light(), "not while the toll-rider scouts hold the hill")
	WorldState.set_flag(EncounterDirector.cleared_flag("encounter.crownmarch_kingsgate_scouts"), true)
	assert_true(fire.light(), "relit once they are gone")
	await _settle()
	assert_eq(Quests.stage_of(MAIN), "grow4", "the beacon stage completes")
	assert_true(p.progression.level >= 7, "the XP is floored at level 7 (%d)" % p.progression.level)
	assert_eq(WorldItems.count(WorldState.inventory, WorldItems.TITAN_IRON), 1, "the beacon's cache paid")
	var grown := false
	for i in 240:   # the giant settles on the floor first (a busy giant does not grow)
		if bool(p.growth.debug_set_stage(4).get("ok", false)):
			grown = true
			break
		await step_ticks(1)
	assert_true(grown, "the giant grows to stage 4")
	await _settle()
	assert_eq(Quests.stage_of(MAIN), "oaths", "stage 4 completes grow4")
	assert_eq(Quests.quest_state(MARCH), Quests.ACTIVE, "Brannock's oath starts at stage 4")
	return p


## Lets Quests evaluate (every EVALUATE_EVERY_TICKS ticks, or at once on a flag change) twice over.
func _settle() -> void:
	await step_ticks(Quests.EVALUATE_EVERY_TICKS * 2 + 1)


func _part(path: String) -> Node3D:
	var part := (load(path) as PackedScene).instantiate() as Node3D
	world.add_child(part)
	return part


func _find(root: Node, world_id: String) -> Node:
	for n in root.find_children("*", "", true, false):
		if "world_id" in n and str(n.get("world_id")) == world_id:
			return n
	return null


## Strikes a prop as a stage-4 giant until its on_destroyed flag is set (at most 60 blows).
func _smash(p: GiantPlayer, world_id: String, flag: String) -> bool:
	for i in 60:
		if QuestConditions.truthy(WorldState.get_flag(flag)):
			return true
		var e := Sim.get_entity(world_id)
		if e == null:
			fail("%s has no entity (%s)" % [world_id, i])
			return false
		var h := HitEvent.new()
		h.tick = Sim.tick
		h.instance_id = Sim.new_instance_id()
		h.attacker_id = p.entity.entity_id
		h.target_id = world_id
		h.power = 600.0
		h.attacker_stat = 40.0
		h.attacker_height_m = 20.0
		h.damage_split = {"physical": 1.0}
		h.poise_damage = 50.0
		h.tags = PackedStringArray(["Melee"])
		h.category = "melee"
		h.attacker_growth_stage = 4
		h.attacker_position = (e.actor as Node3D).global_position + Vector3(0, 0, 8) if e.actor != null else Vector3.ZERO
		Sim.queue_hit(h)
		await step_ticks(1)
	var prop := _find(world, world_id)
	print("    %s: last rejection %s" % [world_id, prop.get("last_rejection") if prop != null else "?"])
	return QuestConditions.truthy(WorldState.get_flag(flag))


func _talk_to_edda(outcome: String, expect_node: String) -> void:
	var s := Quests.start_dialogue("dialogue.edda", "world.crownmarch.edda")
	assert_true(s != null, "Edda talks")
	if s == null:
		return
	assert_eq(str(s.node().get("id", "")), expect_node, "Edda opens with %s" % expect_node)
	assert_true(s.find_choice(outcome) >= 0, "the %s choice is offered" % outcome)
	s.choose_outcome(outcome)
	Quests.end_dialogue()
	await _settle()


func _sworn(p: GiantPlayer, outcome: String, iron: int, titan: int) -> void:
	assert_eq(Quests.quest_state(MARCH), Quests.COMPLETED, "Brannock's oath is won by %s" % outcome)
	assert_eq(str(WorldState.get_flag("oath.march.outcome")), outcome, "its outcome")
	assert_true(p.progression.level >= 9, "the XP is floored at level 9 (%d)" % p.progression.level)
	assert_eq(WorldItems.count(WorldState.inventory, WorldItems.IRON), iron, "%s: the iron of the path" % outcome)
	assert_eq(WorldItems.count(WorldState.inventory, WorldItems.TITAN_IRON), titan, "%s: the titan iron of the path" % outcome)
	assert_eq(Quests.stage_of(MAIN), "oaths", "the main thread waits for a second oath (M8)")
	var c := QuestConditions.empty_context()
	c.flags = WorldState.flags
	assert_true(QuestConditions.all_hold(GameData.get_record("shrine.world_greywood").growth_requires_conditions, c),
		"the stage-5 shrines open after the first oath")


func test_the_march_by_intimidation() -> void:
	var p := await _opening()
	await _talk_to_edda("intimidate", "greet")
	# world_start 1 + the cache 2 + the tribute 2 + the oath 2 iron; the cache 1 + the oath 1 titan iron
	await _sworn(p, "intimidate", 7, 2)
	assert_true(QuestConditions.truthy(WorldState.get_flag("faction.brannock.tribute")), "Brannock pays tribute")
	assert_false(FactionState.is_hostile("brannock"), "and stays at peace")


func test_the_march_by_help() -> void:
	var p := await _opening()
	await _talk_to_edda("offer_help", "greet")
	assert_eq(Quests.stage_of(MARCH), "resolve", "met: the oath waits for the March's roads")
	_part(TOLL_PART)
	assert_true(await _smash(p, TOLL_GATE, "world.toll_fort.breached"), "the toll fort's gate breaks at stage 4")
	for enc: String in ["encounter.crownmarch_toll_fort", "encounter.crownmarch_raiders"]:
		WorldState.set_flag(EncounterDirector.cleared_flag(enc), true)
	await _talk_to_edda("help", "report")
	# + the toll gate's 2 iron and Edda's 2: 1 + 2 + 2 + 2 + 2 iron
	await _sworn(p, "help", 9, 2)
	assert_eq(WorldItems.count(WorldState.inventory, "item.brannock_banner"), 1, "Brannock's banner")
	assert_true(QuestConditions.truthy(WorldState.get_flag("faction.brannock.allied")), "Brannock is allied")


func test_the_march_by_force() -> void:
	var p := await _opening()
	_part(GATEHOUSE_PART)
	assert_true(await _smash(p, GATEHOUSE, "world.brannock.gate_broken"), "the south gatehouse falls at stage 4")
	assert_true(FactionState.is_hostile("brannock"), "the town turns hostile")
	await _talk_to_edda("force", "fear")
	await _sworn(p, "force", 5, 2)
	assert_true(FactionState.is_hostile("brannock"), "it stays hostile until Edda is paid")
	var forge := TownForge.new()
	forge.faction = "brannock"
	assert_false(forge.is_open(), "its smithy is shut")
	forge.free()
