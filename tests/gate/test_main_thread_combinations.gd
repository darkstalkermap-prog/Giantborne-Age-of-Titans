extends IntegrationSuite
## The main thread in every order of the oaths (P36; plan M6-M9 §3.20, §5.7, §5.9, decision 26; the M8
## gate's acceptance), teleport-assisted (P36's contract), with every step through the writer a
## player's deed uses: the campaign from world_start in level.world with Quests over every shipped quest,
## on the suite's floor with the shipped chunks' props parts each deed needs.
##
## M8 gate (F3): the suite used to write every complete_when flag of an oath's stages itself (oath.<x>.met
## included, which the crown's battle and ridge never wrote: it hid F39) and always took the first
## resolution in name order. Now it writes no flag a resolution's own writer does not write, and the
## orders rotate the resolutions:
##   * the opening: the Kingsgate beacon lit (BeaconFire.light, its scouts' fight taken as won) and its
##     scene read; the giant grown at the Kingsgate shrine (Shrine.grow: the shrine's own gates);
##   * Brannock's oath by intimidation, by help (the toll fort's real gate broken, the fort and the Hollow
##     taken as cleared, Edda's report) and by force (the south gatehouse smashed, Edda's oath out of fear);
##   * the woodfolk's by slaying the shipped Matriarch and by driving her out (the den's three braziers
##     smashed burn its nests, the woodfolk pull the back wall down 20 s later at stage 4, or the giant
##     heaves it aside at stage 5, and below 60 % she flees through it), Sedge's oath after each;
##   * the crown's by breach (the fort's real gate broken, Corvane spared at the yield) and by sabotage
##     (Wynn spared, the seven real engines broken) - both by a giant that never met the herald (F39) -
##     and by parley with each of its tokens: Brannock's banner (Edda's help), the deserters' word (Wynn
##     spared), Stoneblood blood (the ancestry chosen) and stature (stage 5): the herald's choice, then
##     Corvane's oath at the horn;
##   * the growths to stage 5 (a stage-5 shrine, rotated) and 6 (the Standing Stones) through Shrine.grow
##     (each shrine's oath conditions and level gate), the Moot entered through its real area trigger,
##     the champion settled at the yield (spared; slain in one order) as the region walkthrough decides it,
##     the Stone Throne taken (StoneThrone.claim);
##   * after each main-thread stage and each oath: a checkpoint and its reload (GameSession's own save
##     document, the giant respawned), which keeps the stage and pays no XP and no titan iron again.
## In every order: each oath quest completes once with its outcome and its reward, the first lifts the
## giant to stage 5's level, two complete the oaths stage at stage 6's level, every quest stage pays once,
## the main thread completes at level 12 and the campaign's end screen opens once and names the oaths'
## and the champion's outcomes. The time of each order and of the suite is printed.

const START_CP := "world.cp.kingsgate_shelf"
const MAIN := "quest.world_main"
const MARCH := "quest.oath_march"
const WOOD := "quest.oath_wood"
const CROWN := "quest.oath_crown"
const SHRINE_SCENE := "res://scenes/world/shrine.tscn"
## The props parts of the chunks the deeds need (each loaded on the suite's floor, freed after its oath).
const BEACON_PART := "res://scenes/world/chunks/c3_6_0.tscn"
const TOLL_PART := "res://scenes/world/chunks/c5_5_0.tscn"
const GATEHOUSE_PART := "res://scenes/world/chunks/c4_6_0.tscn"
const DEN_PARTS := ["res://scenes/world/chunks/c0_2_0.tscn", "res://scenes/world/chunks/c1_2_0.tscn"]
const FORT_PART := "res://scenes/world/chunks/c6_3_0.tscn"
const ENGINE_PARTS := ["res://scenes/world/chunks/c5_4_0.tscn", "res://scenes/world/chunks/c6_4_0.tscn",
	"res://scenes/world/chunks/c7_4_0.tscn", "res://scenes/world/chunks/c7_3_0.tscn"]
## The Moot's chunks: its ring, arena and area trigger (c4_1), the Stone Throne (c4_0).
const MOOT_PARTS := ["res://scenes/world/chunks/c4_1_0.tscn", "res://scenes/world/chunks/c4_0_0.tscn"]
const BEACON := "world.crownmarch.kingsgate_beacon_fire"
const TOLL_GATE := "world.crownmarch.toll_gate"
const GATEHOUSE := "world.crownmarch.brannock_south_gate"
const BRAZIERS := ["world.greywood.den_brazier_1", "world.greywood.den_brazier_2", "world.greywood.den_brazier_3"]
const WALL := "world.greywood.troll_den_wall"
const MATRIARCH := "world.greywood.troll_matriarch"
const FORT_GATE := "world.aldmere.fort_gate"
const CORVANE := "world.aldmere.corvane"
const ENGINES := ["world.aldmere.camp_catapult_1", "world.aldmere.camp_ballista_1", "world.aldmere.camp_ballista_2",
	"world.aldmere.camp_catapult_2", "world.aldmere.ridge_ballista_1", "world.aldmere.ridge_ballista_2",
	"world.aldmere.ridge_ballista_3"]
const HARROK := "world.stonehold.harrok"
const THRONE := "world.stonehold.stone_throne"
const MOOT_AREA := "world.area.moot"
## [world id, record] of the shrines the giant grows at: the Kingsgate shrine (stage 4), the three stage-5
## shrines (one per order, rotated) and the Standing Stones (stage 6).
const KINGSGATE_SHRINE := ["world.shrine.kingsgate", "shrine.world_kingsgate"]
const STAGE5_SHRINES := [["world.shrine.greywood", "shrine.world_greywood"], ["world.shrine.aldmere", "shrine.world_aldmere"],
	["world.shrine.steps", "shrine.world_steps"]]
const STONES := ["world.shrine.stones", "shrine.world_stones"]
## The orders: [oath quest, resolution] in the order they are won, and the champion's end. Every ordered
## pair of the oaths comes first and second once; every resolution comes once at least - the march's
## three, the wood's slaying and its drive-out both ways (the 20 s wall at stage 4, the heave at stage 5),
## the crown's breach, sabotage and parley with each of its four tokens.
const ORDERS := [
	{"oaths": [[MARCH, "intimidate"], [WOOD, "slay"]], "champion": "spared"},
	{"oaths": [[MARCH, "help"], [CROWN, "parley_banner"]], "champion": "spared"},
	{"oaths": [[WOOD, "drive"], [MARCH, "force"]], "champion": "spared"},
	{"oaths": [[WOOD, "slay"], [CROWN, "parley_stature"]], "champion": "slain"},
	{"oaths": [[CROWN, "breach"], [MARCH, "help"]], "champion": "spared"},
	{"oaths": [[CROWN, "sabotage"], [WOOD, "drive"]], "champion": "spared"},
	{"oaths": [[MARCH, "force"], [WOOD, "slay"], [CROWN, "parley_deserters"]], "champion": "spared"},
	{"oaths": [[CROWN, "parley_stoneblood"], [WOOD, "drive"], [MARCH, "intimidate"]], "champion": "spared"},
]

var p: GiantPlayer = null
var _screens: Array = []
var _xp: Array = []            ## [amount, source] of every XP award
var _parts: Dictionary = {}    ## part path -> its node, while it is loaded


func before_each() -> void:
	await super()
	_screens.clear()
	_xp.clear()
	_parts.clear()
	Events.ui_screen_requested.connect(_on_screen)
	Events.xp_award_requested.connect(_on_xp)


func after_each() -> void:
	if Events.ui_screen_requested.is_connected(_on_screen):
		Events.ui_screen_requested.disconnect(_on_screen)
	if Events.xp_award_requested.is_connected(_on_xp):
		Events.xp_award_requested.disconnect(_on_xp)
	Quests.end_dialogue()
	for f in Formation.live():
		f.dissolve()
	FactionState.reset_for_tests()
	WanderDirector.reset_for_tests()
	p = null
	await super()


func _on_screen(screen: String, args: Dictionary) -> void:
	_screens.append([screen, args])


func _on_xp(amount: int, source: String) -> void:
	_xp.append([amount, source])


## Lets Quests evaluate (every EVALUATE_EVERY_TICKS ticks, or at once on a flag change) twice over.
func _settle() -> void:
	await step_ticks(Quests.EVALUATE_EVERY_TICKS * 2 + 1)


func _part(path: String) -> Node3D:
	if _parts.has(path) and is_instance_valid(_parts[path]):
		return _parts[path]
	var part := (load(path) as PackedScene).instantiate() as Node3D
	world.add_child(part)
	_parts[path] = part
	await step_ticks(2)
	return part


func _free_parts() -> void:
	for path: String in _parts:
		if is_instance_valid(_parts[path]):
			(_parts[path] as Node).queue_free()
	_parts.clear()
	await step_ticks(2)


func _find(world_id: String) -> Node:
	for n in world.find_children("*", "", true, false):
		if "world_id" in n and str(n.get("world_id")) == world_id:
			return n
	return null


func _titan() -> int:
	return WorldItems.count(WorldState.inventory, WorldItems.TITAN_IRON)


# --------------------------------------------------------------------------- the deeds' writers

## Strikes a prop with the giant's heavy blows at its stage until it is destroyed (at most 80).
func _break(world_id: String) -> bool:
	for i in 80:
		if WorldState.is_destroyed(world_id):
			return true
		var e := Sim.get_entity(world_id)
		if e == null:
			fail("%s has no entity" % world_id)
			return false
		var h := HitEvent.new()
		h.tick = Sim.tick
		h.instance_id = Sim.new_instance_id()
		h.attacker_id = p.entity.entity_id
		h.target_id = world_id
		h.power = 900.0
		h.attacker_stat = 40.0
		h.attacker_height_m = 20.0
		h.damage_split = {"physical": 1.0}
		h.poise_damage = 50.0
		h.tags = PackedStringArray(["Melee"])
		h.category = "melee"
		h.attacker_growth_stage = p.current_growth_stage()
		h.attacker_position = (e.actor as Node3D).global_position + Vector3(0, 0, 8) if e.actor != null else Vector3.ZERO
		Sim.queue_hit(h)
		await step_ticks(1)
	await step_ticks(2)
	return WorldState.is_destroyed(world_id)


## A conversation with `npc` as a player holds it: the choices whose text starts with each of `via`,
## then the choice whose outcome is `outcome`; then it ends.
func _say(dialogue: String, npc: String, outcome: String, via: Array = []) -> void:
	var s := Quests.start_dialogue(dialogue, npc)
	assert_true(s != null, "%s talks" % npc)
	if s == null:
		return
	for prefix: String in via:
		var taken := false
		for c: Dictionary in s.choices():
			if str(c.text).begins_with(prefix) and not bool(c.get("locked", false)):
				s.choose(int(c.index))
				taken = true
				break
		assert_true(taken, "%s: '%s...' is offered" % [npc, prefix])
	var offered := s.choices().map(func(c: Dictionary) -> String: return str(c.text))
	assert_true(s.find_choice(outcome) >= 0, "%s offers %s (node %s: %s)" % [npc, outcome, s.node().get("id", ""), offered])
	if s.find_choice(outcome) >= 0:
		s.choose_outcome(outcome)
	Quests.end_dialogue()
	await _settle()


## A scene the game started (the beacon's) read to its end, as a player reads it.
func _read_the_scene() -> void:
	await step_ticks(2)
	var guard := 0
	while Quests.dialogue != null and Quests.dialogue.is_active() and guard < 12:
		var cs := Quests.dialogue.choices()
		if cs.is_empty():
			break
		Quests.dialogue.choose(int((cs[0] as Dictionary).index))
		guard += 1
	Quests.end_dialogue()
	await _settle()


## Grows the giant to `stage` at the shrine `spec` ([world id, record]) placed beside it on the floor:
## Shrine.grow checks the shrine's oath conditions, the giant's level, its state and the room. The giant
## rests out of combat first (a hit exchanged keeps it in combat for 10 s); at most 4 s of tries.
func _grow(stage: int, spec: Array) -> bool:
	var s := (load(SHRINE_SCENE) as PackedScene).instantiate() as Shrine
	s.world_id = str(spec[0])
	s.shrine_id = str(spec[1])
	s.position = Vector3(30, 0, 0)
	world.add_child(s)
	await step_ticks(2)
	var r := {}
	for i in 240:
		p.entity.combatant.pools.since_combat = 999.0
		r = s.grow(p, stage)
		if bool(r.get("ok", false)) or str(r.get("reason", "")) in ["conditions", "level", "shrine_max", "flags"]:
			break
		await step_ticks(1)
	s.queue_free()
	await _settle()
	assert_true(bool(r.get("ok", false)), "%s grows the giant to stage %d (%s: %s)" % [spec[1], stage, r.get("reason", ""), r.get("message", "")])
	return bool(r.get("ok", false))


## A checkpoint and its reload (GameSession's save document; the giant respawned on the floor): the main
## thread keeps its stage and nothing is paid again.
func _reload(label: String) -> void:
	Quests.end_dialogue()
	await _settle()
	var stage := Quests.stage_of(MAIN)
	var state := Quests.quest_state(MAIN)
	var titan := _titan()
	var level: int = p.progression.level
	var growth := p.current_growth_stage()
	var r := GameSession.take_checkpoint("test")
	assert_true(bool(r.get("ok", false)), "%s: a checkpoint (%s)" % [label, r.get("message", "")])
	var paid := _xp.size()
	GameSession.reload_checkpoint("menu")
	p.queue_free()
	await step_ticks(2)
	p = spawn_player(Vector3(0, 0.05, 0), 0.0)
	GameSession.on_level_ready(world, p)
	p.global_position = Vector3(0, 0.05, 0)
	p.velocity = Vector3.ZERO
	p.entity.apply_status("status.debug_invulnerable", NAN, -1.0, "test")
	await _settle()
	await _settle()
	assert_eq([Quests.quest_state(MAIN), Quests.stage_of(MAIN)], [state, stage], "%s: the reload keeps the main thread's stage" % label)
	assert_eq(_xp.slice(paid), [], "%s: the reload pays no XP again" % label)
	assert_eq(_titan(), titan, "%s: nor titan iron" % label)
	assert_eq([p.progression.level, p.current_growth_stage()], [level, growth], "%s: the giant keeps its level and stage" % label)


# --------------------------------------------------------------------------- the oaths

func _win(quest: String, how: String) -> void:
	match quest:
		MARCH:
			await _win_march(how)
		WOOD:
			await _win_wood(how)
		CROWN:
			await _win_crown(how)


func _win_march(how: String) -> void:
	match how:
		"intimidate":
			await _say("dialogue.edda", "world.crownmarch.edda", "intimidate")
		"help":
			await _say("dialogue.edda", "world.crownmarch.edda", "offer_help")
			assert_eq(Quests.stage_of(MARCH), "resolve", "met: the oath waits for the March's roads")
			await _part(TOLL_PART)
			assert_true(await _break(TOLL_GATE), "the toll fort's gate breaks")
			assert_true(QuestConditions.truthy(WorldState.get_flag("world.toll_fort.breached")), "the toll fort is breached")
			for enc: String in ["encounter.crownmarch_toll_fort", "encounter.crownmarch_raiders"]:
				WorldState.set_flag(EncounterDirector.cleared_flag(enc), true)   # the fights taken as won
			await _settle()
			await _say("dialogue.edda", "world.crownmarch.edda", "help")
		"force":
			await _part(GATEHOUSE_PART)
			assert_true(await _break(GATEHOUSE), "Brannock's south gatehouse falls")
			assert_true(QuestConditions.truthy(WorldState.get_flag("world.brannock.gate_broken")), "the gate is broken")
			assert_true(FactionState.is_hostile("brannock"), "the town turns hostile")
			await _settle()
			await _say("dialogue.edda", "world.crownmarch.edda", "force")


## The shipped Matriarch on the floor (her outcome is hers wherever she stands).
func _matriarch() -> TrollEnemy:
	var rec := GameData.get_record("enemy.troll_matriarch")
	var m := (load(str(rec.scene)) as PackedScene).instantiate() as TrollEnemy
	m.set("entity_id", MATRIARCH)
	m.position = Vector3(0, 0.05, 40)
	world.add_child(m)
	await step_ticks(2)
	return m


func _win_wood(how: String) -> void:
	await _say("dialogue.sedge", "world.greywood.sedge", "accept")
	assert_eq(Quests.stage_of(WOOD), "den", "met: the oath waits for the den")
	var m: TrollEnemy = null
	match how:
		"slay":
			m = await _matriarch()
			m.entity.combatant.pools.health = 1.0
			var h := HitEvent.new()
			h.tick = Sim.tick
			h.instance_id = Sim.new_instance_id()
			h.attacker_id = p.entity.entity_id
			h.target_id = MATRIARCH
			h.power = 5000.0
			h.attacker_stat = 40.0
			h.attacker_height_m = 11.0
			h.damage_split = {"physical": 1.0}
			h.tags = PackedStringArray(["Melee", "Unblockable", "Unparryable"])
			h.category = "melee"
			h.attacker_growth_stage = p.current_growth_stage()
			h.attacker_position = m.global_position + Vector3(0, 0, 6)
			Sim.queue_hit(h)
			await step_ticks(3)
			assert_eq(WorldState.get_flag("boss.matriarch.outcome"), "slain", "the Matriarch is struck down")
			await _settle()
			await _say("dialogue.sedge", "world.greywood.sedge", "slay")
		"drive":
			for path: String in DEN_PARTS:
				await _part(path)
			var wall := _find(WALL) as DenWall
			assert_true(wall != null and not wall.is_open(), "the den's back wall stands")
			if wall == null:
				return
			var heaved := p.current_growth_stage() >= 5
			if heaved:
				var heave := wall.get_node_or_null("HeavePoint") as HeavePoint
				heave.interact(p)
				await step_ticks(3)
				assert_true(wall.is_open(), "a stage-5 giant heaves the den's back wall aside")
			for b: String in BRAZIERS:
				assert_true(await _break(b), "%s is smashed" % b)
				await step_ticks(3)
			assert_true(QuestConditions.truthy(WorldState.get_flag("world.troll_den.nests_burned")), "the den's nests burn")
			if not heaved:
				await step_ticks(ActionDef.seconds_to_ticks(19.0))
				assert_false(wall.is_open(), "the woodfolk need their 20 s")
				await step_ticks(ActionDef.seconds_to_ticks(1.5))
				assert_true(wall.is_open(), "then they pull the wall down")
			m = await _matriarch()
			var pools := m.entity.combatant.pools
			pools.health = pools.health_max * 0.55
			await step_ticks(2)
			assert_true(m.is_fleeing(), "below 60 %, the nests burned and the wall open, she runs")
			m.global_position = m.exit_point() + Vector3(0, 0.05, 1.0)
			await step_ticks(3)
			assert_eq(WorldState.get_flag("boss.matriarch.outcome"), "fled", "she is driven out")
			await _settle()
			await _say("dialogue.sedge", "world.greywood.sedge", "drive")
	# The fight's leftovers taken as beaten: her body and the whelps she called (aware enemies near the
	# giant defer every checkpoint, as they would in the den).
	for n in get_tree().get_nodes_in_group("enemies"):
		if world.is_ancestor_of(n):
			n.queue_free()
	await step_ticks(2)


func _win_crown(how: String) -> void:
	match how:
		"breach":
			# The fort found on the road: the herald never met.
			await _part(FORT_PART)
			assert_true(await _break(FORT_GATE), "the fort's gate breaks")
			assert_true(QuestConditions.truthy(WorldState.get_flag("world.aldmere.fort_breached")), "the fort is breached")
			await _settle()
			var battle: FortBattle = null
			for n in world.find_children("*", "", true, false):
				if n is FortBattle:
					battle = n
			assert_true(battle != null, "the Iron Regiment's battle is in the fort's chunk")
			assert_false(QuestConditions.truthy(WorldState.get_flag("oath.crown.met")), "the herald was never met")
			if battle != null:
				# The battle's yield as the region walkthrough decides it: Corvane yields and is spared.
				WorldState.set_flag("boss.corvane.outcome", "spared")
				battle.p34_on_yield_decided(CORVANE, "spare")
		"sabotage":
			# Wynn spared marks the engines: the herald never met.
			await _say("dialogue.deserters", "world.aldmere.deserter_wynn", "spare")
			assert_eq(Quests.quest_state("quest.war_engines"), Quests.ACTIVE, "the war engines' errand is in the journal")
			for path: String in ENGINE_PARTS:
				await _part(path)
			assert_false(QuestConditions.truthy(WorldState.get_flag("oath.crown.met")), "the herald was never met")
			for id: String in ENGINES:
				assert_true(await _break(id), "%s is broken" % id)
				await step_ticks(1)
			assert_true(FactionState.is_hostile("aldmere"), "breaking its engines turns Aldmere hostile")
		_:
			match how.trim_prefix("parley_"):
				"deserters":
					await _say("dialogue.deserters", "world.aldmere.deserter_wynn", "spare")
					assert_true(QuestConditions.truthy(WorldState.get_flag("oath.crown.token_deserters")), "the deserters give their word")
				"stoneblood":
					var r: Dictionary = p.progression.choose_ancestry("ancestry.stoneblood")
					assert_true(bool(r.get("ok", false)), "the giant is Stoneblood (%s)" % r)
				"banner":
					assert_eq(WorldItems.count(WorldState.inventory, "item.brannock_banner"), 1, "Brannock's banner, from Edda's help")
				"stature":
					assert_eq(p.current_growth_stage(), 5, "a giant of stage 5")
			await _say("dialogue.herald", "world.aldmere.herald", how, ["What are the three roads"])
			assert_true(QuestConditions.truthy(WorldState.get_flag("oath.crown.parley_accepted")), "the herald accepts the parley")
			await _say("dialogue.corvane", "world.aldmere.fort_parley", "parley")
	await _settle()
	await _settle()


## Wins the oath `quest` by `how` and checks it: the quest complete with the outcome its writer wrote,
## its last stage's reward paid (its titan iron among it).
func _sworn(quest: String, how: String) -> void:
	var key := OathRules.oath_key(quest)
	var stages: Array = GameData.get_record(quest).get("stages", [])
	var reward := Quests.reward_flag(quest, str((stages.back() as Dictionary).id))
	var titan := _titan()
	assert_eq(Quests.quest_state(quest), Quests.ACTIVE, "%s is open" % quest)
	assert_false(QuestConditions.truthy(WorldState.get_flag(reward)), "%s's reward is not paid yet" % quest)
	await _win(quest, how)
	var outcome := "parley" if how.begins_with("parley_") else how
	assert_eq(Quests.quest_state(quest), Quests.COMPLETED, "%s is won by %s (its stage: %s)" % [quest, how, Quests.stage_of(quest)])
	assert_eq(str(WorldState.get_flag(OathRules.outcome_flag(key), "")), outcome, "%s's outcome" % quest)
	assert_true(QuestConditions.truthy(WorldState.get_flag(reward)), "%s's reward is paid (%s)" % [quest, reward])
	assert_true(_titan() - titan >= 1, "%s's titan iron (%d)" % [quest, _titan() - titan])


# --------------------------------------------------------------------------- one order

func _opening() -> void:
	GameSession.start_world_for_tests(START_CP)
	GameSession.level_id = "level.world"
	p = spawn_player(Vector3(0, 0.05, 0), 0.0)
	GameSession.on_level_ready(world, p)
	# the session places the giant at its start checkpoint's index transform: back onto this floor
	p.global_position = Vector3(0, 0.05, 0)
	p.velocity = Vector3.ZERO
	p.entity.apply_status("status.debug_invulnerable", NAN, -1.0, "test")
	Quests.test_active = true
	Quests.scope = PackedStringArray()
	FactionState.hub()   # the world's soldiers and folk install it in the game
	await _settle()
	assert_eq(Quests.stage_of(MAIN), "beacon", "the main thread starts at the beacon")
	await _part(BEACON_PART)
	var fire := _find(BEACON) as BeaconFire
	assert_true(fire != null, "the Kingsgate beacon's fire is in its chunk")
	WorldState.set_flag(EncounterDirector.cleared_flag("encounter.crownmarch_kingsgate_scouts"), true)   # the fight won
	assert_true(fire != null and fire.light(), "the giant lights the Kingsgate beacon")
	await _read_the_scene()
	await _free_parts()
	assert_eq(Quests.stage_of(MAIN), "grow4", "the beacon stage completes")
	await _reload("the beacon")
	assert_true(await _grow(4, KINGSGATE_SHRINE), "the giant grows to stage 4 at the Kingsgate shrine")
	assert_eq(Quests.stage_of(MAIN), "oaths", "stage 4: the main thread waits on the oaths")
	await _reload("grow4")


func _run(index: int, order: Dictionary) -> void:
	var oaths: Array = order.oaths
	var champion := str(order.champion)
	var label := " -> ".join(oaths.map(func(o: Array) -> String: return "%s (%s)" % [OathRules.oath_key(str(o[0])), o[1]]))
	var t0 := Time.get_ticks_msec()
	await _opening()
	for i in oaths.size():
		await _sworn(str(oaths[i][0]), str(oaths[i][1]))
		await _free_parts()
		if i == 0:
			assert_eq(Quests.stage_of(MAIN), "oaths", "one oath: the main thread waits for a second")
			assert_true(p.progression.level >= WorldXp.growth_level("growth.05"),
				"the first oath lifts the giant to stage 5's level (%d)" % p.progression.level)
			await _reload("the first oath")
			assert_true(await _grow(5, STAGE5_SHRINES[index % STAGE5_SHRINES.size()]), "a stage-5 shrine grows the giant after the first oath")
		elif i == 1:
			assert_eq(Quests.stage_of(MAIN), "grow6", "two oaths complete the oaths stage (%s)" % label)
			assert_true(p.progression.level >= WorldXp.growth_level("growth.06"),
				"two oaths lift the giant to stage 6's level (%d)" % p.progression.level)
			await _reload("the oaths stage")
		else:
			assert_eq(Quests.stage_of(MAIN), "grow6", "a third oath leaves the main thread on grow6")
			await _reload("the third oath")
	var titan := _titan()
	assert_true(await _grow(6, STONES), "the Standing Stones grow the giant to stage 6")
	assert_eq(Quests.stage_of(MAIN), "moot", "grow6 completes")
	assert_eq(_titan() - titan, 1, "the Stones' gift: 1 titan iron")
	await _reload("grow6")
	await _enter_the_moot()
	await _reload("the moot")
	await _settle_the_champion(champion)
	await _reload("the champion")
	var throne := _find(THRONE) as StoneThrone
	assert_true(throne != null and throne.claim(), "the giant takes the Stone Throne")
	await _settle()
	assert_eq(Quests.quest_state(MAIN), Quests.COMPLETED, "the main thread completes (%s)" % label)
	assert_true(QuestConditions.truthy(WorldState.get_flag("campaign.completed")), "campaign.completed")
	assert_true(p.progression.level >= 12, "the finale reaches level 12 (%d)" % p.progression.level)
	await _reload("the throne")
	assert_eq(Quests.quest_state(MAIN), Quests.COMPLETED, "the campaign stays complete after a reload")
	for o: Array in oaths:
		assert_eq(Quests.quest_state(str(o[0])), Quests.COMPLETED, "%s stays won" % o[0])
	var sources := {}
	for a: Array in _xp:
		if str(a[1]).begins_with("quest:"):
			sources[str(a[1])] = int(sources.get(str(a[1]), 0)) + 1
	assert_eq(sources.keys().filter(func(k: String) -> bool: return int(sources[k]) != 1), [], "every quest stage pays once (%s)" % label)
	var ends := _screens.filter(func(s: Array) -> bool: return str(s[0]) == "end")
	assert_eq(ends.size(), 1, "the campaign's end screen opens once, reload or not")
	if ends.size() == 1:
		var args: Dictionary = ends[0][1]
		assert_true(bool(args.get("campaign", false)), "as the campaign's end")
		var lines := EndScreen.campaign_lines(args)
		assert_eq(str(lines[lines.size() - 1]), str(EndScreen.CHAMPION_LINES[champion]), "its last line is the champion's end (%s)" % champion)
		for o: Array in oaths:
			var key := OathRules.oath_key(str(o[0]))
			assert_eq(str(args.get(key, "")), str(WorldState.get_flag(OathRules.outcome_flag(key), "")), "it names %s's outcome" % o[0])
	print("    main thread %d: %s, the champion %s - %.1f s, level %d" % [index + 1, label, champion,
		float(Time.get_ticks_msec() - t0) / 1000.0, p.progression.level])


## The Moot entered as the giant walks in: its chunks loaded, the giant set down inside its area trigger
## (44 m from its heart, clear of the duel's engage area) on a floor there; the trigger's own overlap
## reports the entry.
func _enter_the_moot() -> void:
	for path: String in MOOT_PARTS:
		await _part(path)
	var area: AreaTrigger = null
	for n in world.find_children("*", "", true, false):
		if n is AreaTrigger and (n as AreaTrigger).area_id == MOOT_AREA:
			area = n
	assert_true(area != null, "the Moot's area trigger is in its chunk")
	if area == null:
		return
	var at := area.global_position + Vector3(44, 0, 0)
	add_box(Vector3(30, 1, 30), at - Vector3(0, 0.5, 0))
	GameSession.place_player(p, Transform3D(Basis.IDENTITY, at + Vector3(0, 0.3, 0)))
	assert_true(await TestWait.until(self, func() -> bool: return area.player_inside, 60), "the giant stands in the Moot")
	await _settle()
	assert_eq(Quests.stage_of(MAIN), "champion", "entering the Moot completes its stage")
	GameSession.place_player(p, Transform3D(Basis.IDENTITY, Vector3(0, 0.3, 0)))
	await step_ticks(5)


func _settle_the_champion(how: String) -> void:
	var arena: MootArena = null
	for n in world.find_children("*", "", true, false):
		if n is MootArena:
			arena = n
	assert_true(arena != null, "the Moot's arena is in its chunk")
	if arena == null:
		return
	# The honour duel's end as the region walkthrough decides it: Harrok yields and is spared, or falls.
	if how == "spared":
		WorldState.set_flag("boss.harrok.outcome", "spared")
		arena.p34_on_yield_decided(HARROK, "spare")
	else:
		WorldState.set_flag("boss.harrok.outcome", "slain")
		arena._on_entity_died(Sim.tick, HARROK, p.entity.entity_id)
	await _settle()
	assert_eq(Quests.stage_of(MAIN), "throne", "the champion settled (%s)" % how)
	assert_eq(QuestConditions.truthy(WorldState.get_flag("faction.harrok_clan.reconciled")), how == "spared",
		"Harrok's clan reconciled only if he was spared")


func test_the_main_thread_in_every_order_of_the_oaths() -> void:
	var t0 := Time.get_ticks_msec()
	var pairs := {}
	var seen := {}
	for order: Dictionary in ORDERS:
		var o: Array = order.oaths
		pairs["%s>%s" % [o[0][0], o[1][0]]] = true
		for x: Array in o:
			seen["%s:%s" % [x[0], x[1]]] = true
	assert_eq(pairs.size(), 6, "every ordered pair of the three oaths is won first and second")
	for want: String in ["%s:intimidate" % MARCH, "%s:help" % MARCH, "%s:force" % MARCH, "%s:slay" % WOOD, "%s:drive" % WOOD,
			"%s:breach" % CROWN, "%s:sabotage" % CROWN, "%s:parley_banner" % CROWN, "%s:parley_deserters" % CROWN,
			"%s:parley_stoneblood" % CROWN, "%s:parley_stature" % CROWN]:
		assert_true(seen.has(want), "the orders take %s" % want)
	for i in ORDERS.size():
		await _run(i, ORDERS[i])
		await _reset()
	print("    test_main_thread_combinations: %d orders in %.1f s" % [ORDERS.size(), float(Time.get_ticks_msec() - t0) / 1000.0])


## Back to a clean campaign between orders (the suite's own reset, as between tests).
func _reset() -> void:
	Quests.end_dialogue()
	for f in Formation.live():
		f.dissolve()
	FactionState.reset_for_tests()
	for c in world.get_children():
		c.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	Sim.clear_pending()
	WorldState.clear()
	_screens.clear()
	_xp.clear()
	_parts.clear()
	p = null
	add_box(Vector3(120, 1, 120), Vector3(0, -0.5, 0))
	await step_ticks(1)
