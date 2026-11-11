extends IntegrationSuite
## The Aldmere March walkthrough (P36; plan M6-M9 §3.20, §5.7, §5.9, §5.13): the crown's oath on every
## road, each as the first oath at stage 4 where §5.7 allows, teleport-assisted - the fights taken as won
## (the battle's yield decided through FortBattle, as the yield prompt would) and every other step the
## shipped game: the campaign from world_start in level.world, Quests over every shipped quest, the
## Aldmere chunks' props parts (the fort's real gate struck by a stage-4 giant, the war engines broken,
## the fort's forge, the battle), and the herald's, the deserters' and Corvane's dialogue chosen as a
## player would:
##   * breach, Corvane spared: the gate breaks at stage 4, the Iron Regiment's battle settles, the oath is
##     won (breach), Aldmere reconciled, the fort opened, its titan forge open;
##   * breach, Corvane struck: the oath won the same, the battle's survivors routed, the forge shut;
##   * sabotage: the camp's four engines and the ridge's three broken - Aldmere turns hostile - the oath
##     won (sabotage), the army withdrawn;
##   * parley with the deserters' word and with Stoneblood blood (the two tokens a stage-4 first oath has),
##     and with Brannock's banner and at stage 5 (the herald greys each token the giant lacks, with its
##     reason): the herald accepts, Corvane swears at the parley horn - Aldmere allied, the fort opened,
##     the crown's flags struck at the toll fort, the forge open;
##   * from a "help" save (Brannock's banner, the march's oath won by help) the giant walks the real world
##     up to Fort Aldmere's gate and stands there: its garrison stands down and no blow, bolt or arrow of
##     the fort touches the giant.

const START_CP := "world.cp.kingsgate_shelf"
const MAIN := "quest.world_main"
const CROWN := "quest.oath_crown"
const FORT_PART := "res://scenes/world/chunks/c6_3_0.tscn"
## The war camp's engines (c5_4, c6_4) and Ballista Ridge's (c7_4, c7_3).
const ENGINE_PARTS := ["res://scenes/world/chunks/c5_4_0.tscn", "res://scenes/world/chunks/c6_4_0.tscn",
	"res://scenes/world/chunks/c7_4_0.tscn", "res://scenes/world/chunks/c7_3_0.tscn"]
const GATE := "world.aldmere.fort_gate"
const FORGE := "world.aldmere.fort_forge"
const CORVANE := "world.aldmere.corvane"
const ENGINES := ["world.aldmere.camp_catapult_1", "world.aldmere.camp_ballista_1", "world.aldmere.camp_ballista_2",
	"world.aldmere.camp_catapult_2", "world.aldmere.ridge_ballista_1", "world.aldmere.ridge_ballista_2",
	"world.aldmere.ridge_ballista_3"]
const SCENE := "res://scenes/world/world.tscn"


func after_each() -> void:
	Quests.end_dialogue()
	for f in Formation.live():
		f.dissolve()
	FactionState.reset_for_tests()
	WanderDirector.reset_for_tests()
	await super()


func _settle() -> void:
	await step_ticks(Quests.EVALUATE_EVERY_TICKS * 2 + 1)


## The campaign from world_start, the opening won, the giant at stage 4 on the test floor.
func _opening(stage := 4) -> GiantPlayer:
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
	for s in range(4, stage + 1):
		var grown := false
		for i in 240:
			if bool(p.growth.debug_set_stage(s).get("ok", false)):
				grown = true
				break
			await step_ticks(1)
		assert_true(grown, "the giant grows to stage %d" % s)
	await _settle()
	assert_eq(Quests.quest_state(CROWN), Quests.ACTIVE, "the crown's oath starts at stage 4")
	return p


func _part(path: String) -> Node3D:
	var part := (load(path) as PackedScene).instantiate() as Node3D
	world.add_child(part)
	return part


func _find(root: Node, world_id: String) -> Node:
	for n in root.find_children("*", "", true, false):
		if "world_id" in n and str(n.get("world_id")) == world_id:
			return n
	return null


## A dialogue session with its first available choice whose text starts with `prefix` taken.
func _choose_text(s: DialogueSession, prefix: String) -> bool:
	for c: Dictionary in s.choices():
		if str(c.text).begins_with(prefix) and not bool(c.get("locked", false)):
			s.choose(int(c.index))
			return true
	return false


func _meet_the_herald() -> void:
	var s := Quests.start_dialogue("dialogue.herald", "world.aldmere.herald")
	assert_true(s != null, "the herald talks")
	if s == null:
		return
	assert_eq(str(s.node().get("id", "")), "greet", "she greets a giant she has not met")
	assert_true(_choose_text(s, "What are the three roads"), "she names the three roads")
	assert_eq(str(s.node().get("id", "")), "ways", "the three roads")
	Quests.end_dialogue()
	await _settle()
	assert_eq(Quests.stage_of(CROWN), "resolve", "meeting the herald completes the oath's first stage")


## Strikes a prop as a stage-4 giant until it is destroyed (at most 80 blows).
func _break(p: GiantPlayer, world_id: String, stage := 4) -> bool:
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
		h.attacker_growth_stage = stage
		h.attacker_position = (e.actor as Node3D).global_position + Vector3(0, 0, 8) if e.actor != null else Vector3.ZERO
		Sim.queue_hit(h)
		await step_ticks(1)
	return WorldState.is_destroyed(world_id)


func _sworn(p: GiantPlayer, outcome: String) -> void:
	assert_eq(Quests.quest_state(CROWN), Quests.COMPLETED, "the crown's oath is won by %s" % outcome)
	assert_eq(str(WorldState.get_flag("oath.crown.outcome")), outcome, "its outcome")
	assert_true(p.progression.level >= 9, "the XP is floored at level 9 (%d)" % p.progression.level)
	assert_true(WorldItems.count(WorldState.inventory, WorldItems.TITAN_IRON) >= 1, "the oath's titan iron")
	assert_true(WorldItems.count(WorldState.inventory, WorldItems.IRON) >= 2, "the oath's iron")
	var c := QuestConditions.empty_context()
	c.flags = WorldState.flags
	assert_true(QuestConditions.all_hold(GameData.get_record("shrine.world_aldmere").growth_requires_conditions, c),
		"the stage-5 shrines open after the first oath")


func _breach(p: GiantPlayer) -> FortBattle:
	await _meet_the_herald()
	var part := _part(FORT_PART)
	await step_ticks(2)
	var gate := _find(part, GATE)
	assert_true(gate != null, "Fort Aldmere's gate is in its chunk")
	assert_true(await _break(p, GATE), "a stage-4 giant breaks the fort's gate")
	assert_true(QuestConditions.truthy(WorldState.get_flag("world.aldmere.fort_breached")), "the fort is breached")
	await _settle()
	assert_eq(Quests.quest_state("quest.iron_regiment"), Quests.ACTIVE, "the Iron Regiment waits in the bailey")
	var battle: FortBattle = null
	for n in part.find_children("*", "", true, false):
		if n is FortBattle:
			battle = n
	assert_true(battle != null, "the battle is in the fort's chunk")
	if battle != null:
		assert_eq(battle.commander_id, CORVANE, "Corvane commands it")
		assert_false(battle.at_peace(), "no parley: the bailey is not at peace")
	return battle


func test_breach_and_corvane_spared_as_the_first_oath() -> void:
	var p := await _opening()
	var battle := await _breach(p)
	if battle == null:
		return
	WorldState.set_flag("boss.corvane.outcome", "spared")
	battle.p34_on_yield_decided(CORVANE, "spare")
	await _settle()
	await _sworn(p, "breach")
	assert_true(QuestConditions.truthy(WorldState.get_flag("faction.aldmere.reconciled")), "a spared Corvane: Aldmere reconciled")
	assert_true(QuestConditions.truthy(WorldState.get_flag("world.aldmere.fort_open")), "the fort opened to the giant")
	var forge := _find(world, FORGE) as ConditionForge
	assert_true(forge != null and forge.is_open(), "the fort's titan forge works for the giant")
	var s := Quests.start_dialogue("dialogue.corvane", "world.aldmere.fort_parley")
	assert_eq(str(s.node().get("id", "")) if s != null else "", "spared", "Corvane answers the horn as the spared warlord")
	Quests.end_dialogue()


func test_breach_and_corvane_struck_as_the_first_oath() -> void:
	var p := await _opening()
	var battle := await _breach(p)
	if battle == null:
		return
	WorldState.set_flag("boss.corvane.outcome", "slain")
	battle._on_entity_died(Sim.tick, CORVANE, p.entity.entity_id)
	await _settle()
	await _sworn(p, "breach")
	assert_true(battle.routed_survivors, "the battle's survivors rout (the garrison flees)")
	assert_false(QuestConditions.truthy(WorldState.get_flag("world.aldmere.fort_open")), "the fort stays shut")
	var forge := _find(world, FORGE) as ConditionForge
	assert_true(forge != null and not forge.is_open(), "its forge stays cold")
	var s := Quests.start_dialogue("dialogue.corvane", "world.aldmere.fort_parley")
	assert_eq(str(s.node().get("id", "")) if s != null else "", "silent", "no one answers the horn")
	Quests.end_dialogue()


func test_sabotage_as_the_first_oath() -> void:
	var p := await _opening()
	await _meet_the_herald()
	for path: String in ENGINE_PARTS:
		_part(path)
	await step_ticks(2)
	for id: String in ENGINES:
		assert_true(await _break(p, id), "%s is broken" % id)
		await step_ticks(1)
	await _settle()
	assert_true(QuestConditions.truthy(WorldState.get_flag("faction.aldmere.hostile")), "breaking Aldmere's engines turns it hostile")
	await _settle()
	assert_eq(Quests.quest_state("quest.war_engines"), Quests.COMPLETED, "the war engines are wrecked")
	await _sworn(p, "sabotage")
	assert_true(QuestConditions.truthy(WorldState.get_flag("world.aldmere.army_withdrawn")), "the army withdraws")
	assert_eq(Quests.stage_of("quest.war_engines"), "ridge", "Ballista Ridge's three ballistae were its last stage")


## The herald accepts the parley on `token`, then Corvane swears at the horn.
func _parley(p: GiantPlayer, token: String) -> void:
	_part(FORT_PART)
	await step_ticks(2)
	var s := Quests.start_dialogue("dialogue.herald", "world.aldmere.herald")
	assert_true(s != null and _choose_text(s, "What are the three roads"), "she names the three roads")
	if s == null:
		return
	var locked := s.choices().filter(func(c: Dictionary) -> bool: return bool(c.get("locked", false)))
	for c: Dictionary in locked:
		assert_true(str(c.locked_text) != "", "a token the giant lacks is greyed with its reason (%s)" % c.text)
	assert_true(s.find_choice("parley_" + token) >= 0, "the %s token is offered" % token)
	s.choose_outcome("parley_" + token)
	Quests.end_dialogue()
	assert_true(QuestConditions.truthy(WorldState.get_flag("oath.crown.parley_accepted")), "the herald accepts the parley")
	var c := Quests.start_dialogue("dialogue.corvane", "world.aldmere.fort_parley")
	assert_eq(str(c.node().get("id", "")) if c != null else "", "parley", "Corvane answers the horn ready to parley")
	if c != null:
		c.choose_outcome("parley")
	Quests.end_dialogue()
	await _settle()
	await _sworn(p, "parley")
	for f: String in ["faction.aldmere.allied", "world.aldmere.fort_open", "world.aldmere.flags_struck"]:
		assert_true(QuestConditions.truthy(WorldState.get_flag(f)), "the parley sets %s" % f)
	var forge := _find(world, FORGE) as ConditionForge
	assert_true(forge != null and forge.is_open(), "the fort's forge opens")


func test_parley_with_the_deserters_word_as_the_first_oath() -> void:
	var p := await _opening()
	var d := Quests.start_dialogue("dialogue.deserters", "world.aldmere.deserter_wynn")
	assert_true(d != null, "Sergeant Wynn talks")
	if d != null:
		d.choose_outcome("spare")
	Quests.end_dialogue()
	await _settle()
	assert_true(QuestConditions.truthy(WorldState.get_flag("oath.crown.token_deserters")), "the deserters give their word")
	assert_eq(WorldItems.count(WorldState.inventory, WorldItems.IRON), WorldItems.count(WorldItems.world_start(), WorldItems.IRON) + 1,
		"and 1 iron from their pay chest")
	await _parley(p, "deserters")


func test_parley_with_stoneblood_blood_as_the_first_oath() -> void:
	var p := await _opening()
	var r: Dictionary = p.progression.choose_ancestry("ancestry.stoneblood")
	assert_true(bool(r.get("ok", false)), "the giant is Stoneblood (%s)" % r)
	await _parley(p, "stoneblood")


func test_parley_with_brannocks_banner_and_at_stage_5() -> void:
	for token: String in ["banner", "stature"]:
		var p := await _opening(5 if token == "stature" else 4)
		if token == "banner":
			WorldState.add_item("item.brannock_banner", 1, "test")
		await _parley(p, token)
		await _reset()


func _reset() -> void:
	Quests.end_dialogue()
	FactionState.reset_for_tests()
	for c in world.get_children():
		c.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	Sim.clear_pending()
	WorldState.clear()
	add_box(Vector3(120, 1, 120), Vector3(0, -0.5, 0))
	await step_ticks(1)


# --------------------------------------------------------------------------- the help save on the real world

func _world(xz: Vector2) -> WorldRoot:
	var w := (load(SCENE) as PackedScene).instantiate() as WorldRoot
	world.add_child(w)
	w.streamer.deterministic = true
	w.player().router.use_injection = true
	var p := w.player()
	var at := Vector3(xz.x, 200.0, xz.y)
	p.process_mode = Node.PROCESS_MODE_DISABLED
	p.global_position = at
	var guard := 0
	while not w.streamer.ring_ready(at) and guard < 600:
		w.streamer.load_ring_slice(at)
		await step_ticks(1)
		guard += 1
	var y := w.height_at(at)
	p.global_position = Vector3(xz.x, (y if not is_nan(y) else 60.0) + 0.3, xz.y)
	p.velocity = Vector3.ZERO
	p.process_mode = Node.PROCESS_MODE_INHERIT
	return w


func test_a_help_save_walks_up_to_the_fort_unharmed() -> void:
	# the march's oath won by help: Brannock allied, its banner in the bag
	for f: String in ["oath.march.met", "oath.march.done"]:
		WorldState.set_flag(f, true)
	WorldState.set_flag("oath.march.outcome", "help")
	WorldState.set_flag("faction.brannock.allied", true)
	WorldState.add_item("item.brannock_banner", 1, "test")
	var w: WorldRoot = await _world(Vector2(650.0, -10.0))
	var p := w.player()
	for rec: Dictionary in GameData.records_of_type("growth_profile"):
		if int(rec.get("stage", 0)) == 4:
			p.set_profile(rec)
	var start_health := p.entity.combatant.pools.health
	var d := w.director()
	var taken: Array = []
	var on_hit := func(_t: int, r: HitResult) -> void:
		if r.event != null and r.event.target_id == p.entity.entity_id and r.health_damage > 0:
			taken.append([r.event.attacker_id, r.health_damage])
	Events.hit_resolved.connect(on_hit)
	# up the road to the gate, a few metres a step, then stand before it
	for zz: float in [-20.0, -30.0, -40.0, -50.0, -60.0, -66.0]:
		var at := Vector3(650.0, 0.0, zz)
		var y := w.height_at(at)
		p.global_position = Vector3(650.0, (y if not is_nan(y) else 58.0) + 0.3, zz)
		p.velocity = Vector3.ZERO
		await step_ticks(60)
	await step_ticks(60 * 15)
	Events.hit_resolved.disconnect(on_hit)
	var garrison := d.members_of("encounter.aldmere_fort_gate")
	var spawned: Array = Array(garrison).filter(func(id: String) -> bool: return d.member_status(id) == "spawned")
	print("    aldmere walkthrough: the gate garrison in the world %d of %d; hits on the giant %s" % [spawned.size(), garrison.size(), taken])
	assert_true(spawned.size() >= 8, "the gate garrison is in the world (%d)" % spawned.size())
	assert_eq(taken, [], "no blow, bolt or arrow of the fort touches the giant")
	assert_true(is_equal_approx(p.entity.combatant.pools.health, start_health), "the giant takes no damage")
