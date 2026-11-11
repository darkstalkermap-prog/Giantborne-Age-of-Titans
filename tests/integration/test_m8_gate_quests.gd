extends IntegrationSuite
## M8 gate review fixes, lane m8q (quests, dialogue and tutorials): the default tier's half - records,
## Quests over the shipped quests on the suite's floor, the save slot and the dialogue records; no world
## or chunk is loaded (the gate half: tests/gate/test_aldmere_walkthrough.gd, test_main_thread_combinations.gd,
## test_drowned_walkthrough.gd; the main.tscn half: tests/slow/test_m8_gate_tutorials.gd).
##   * F39: every record that writes an oath's done flag writes its met flag too (Edda's and Sedge's
##     resolutions always did; the crown's battle and ridge did not, so a breach or a sabotage won before
##     meeting the herald left quest.oath_crown on "Meet Aldmere's herald" for good), and a save already
##     stuck that way loads, completes the oath quest and pays its resolution once.
##   * F6: a crown sworn in peace (the parley, or Corvane spared) gives up Ballista Ridge's errand (and a
##     ridge found afterwards starts none), and a peace broken afterwards is named by the herald and
##     Corvane before their sworn lines - the herald mends it for 2 iron (faction.aldmere's reconcile).
##   * F34: the stage-6 Grow summary names what siege disruption unlocks - seizing a staggered or uncrewed
##     engine and hurling it - not "Wreck siege engines", which a giant of any stage can do with blows.
##   * F42: every npc record of role "talker" is built from a scene that carries an NpcTalker, which
##     names its npc and its record's dialogue once spawned as the director spawns it (Wenna the
##     ferrywoman was built from villager.tscn, which has none: her dialogue could not be reached).
##   * F46: a multi-marker stage leads to the nearest open marker the giant's stage can reach (a marker
##     inside a POI whose min_stage is above the giant's stage waits, unless nothing else is open), and
##     marker_id names the marker the position belongs to: a stage-4 giant at the third bell is led to
##     the second, not to the island's bell past the stage-5 channel.
##   * F29: the main thread's grow6 names the way round the Giant's Stair - its waiting text the Ironway, up
##     from Aldmere's road, and its lead: below stage 6, outside the Stonehold, the objective (the HUD
##     marker, the compass, the tracker's "by the Ironway") points at the Ironway's waystone, then at the
##     Standing Stones once the giant is up in the highlands; every size gate's message names the stage
##     it needs (decision 18), the Stair's the Ironway too.

const START_CP := "world.cp.kingsgate_shelf"
const CROWN := "quest.oath_crown"
const OATHS := ["march", "wood", "crown"]
const STUCK_SAVE := "res://tests/fixtures/saves/v2_crown_sabotage_stuck_on_meet.json"
const RIDGE := "quest.ballista_ridge"

var _xp: Array = []


func before_each() -> void:
	await super()
	_xp.clear()
	Events.xp_award_requested.connect(_on_xp)


func after_each() -> void:
	if Events.xp_award_requested.is_connected(_on_xp):
		Events.xp_award_requested.disconnect(_on_xp)
	Quests.end_dialogue()
	FactionState.reset_for_tests()
	SaveSlots.delete_slot(true)
	GameSession.persist = false
	await super()


func _on_xp(amount: int, source: String) -> void:
	_xp.append([amount, source])


func _settle() -> void:
	await step_ticks(Quests.EVALUATE_EVERY_TICKS * 2 + 1)


## The XP paid from sources that start with `prefix`, by source.
func _xp_from(prefix: String) -> Dictionary:
	var out := {}
	for a: Array in _xp:
		if str(a[1]).begins_with(prefix):
			out[str(a[1])] = int(out.get(str(a[1]), 0)) + int(a[0])
	return out


# --------------------------------------------------------------------------- F39

func test_every_writer_of_an_oaths_done_flag_writes_its_met_flag_too() -> void:
	var writers := OathRules.flag_writers(GameData.records)
	for key: String in OATHS:
		var met := {}
		for w: Dictionary in writers.get("oath.%s.met" % key, []):
			if QuestConditions.truthy(w.value):
				met[str(w.source)] = true
		var done: Array = writers.get(OathRules.done_flag(key), [])
		assert_true(done.size() >= 2, "oath.%s.done has its resolutions' writers (%d)" % [key, done.size()])
		var lacking := PackedStringArray()
		for w: Dictionary in done:
			if not met.has(str(w.source)):
				lacking.append(str(w.source))
		assert_eq(lacking, PackedStringArray(), "every writer of oath.%s.done also writes oath.%s.met (the oath quest's first stage)" % [key, key])


func test_a_save_stuck_on_meeting_the_herald_loads_and_pays_the_oath_once() -> void:
	# The save of 29ec501: the crown won by sabotage (Wynn spared, the seven engines broken) by a giant that
	# never met the herald - quest.oath_crown on 'meet', its resolve stage unpaid, level 8.
	var doc: Dictionary = SaveSlots.migrate(JsonIO.read_file(STUCK_SAVE).data)
	var flags: Dictionary = doc.world.flags
	assert_eq([str(flags.get("quest.oath_crown.stage", "")), str(flags.get("oath.crown.outcome", "")), flags.has("oath.crown.met")],
		["meet", "sabotage", false], "the fixture is stuck: the oath sworn, its quest on 'meet'")
	GameSession.persist = true
	assert_true(bool(SaveSlots.write(doc).ok), "the stuck save is in the slot")
	var r := GameSession.continue_valley()
	assert_true(bool(r.ok), "Continue loads it (%s)" % r.message)
	Quests.test_active = true
	Quests.scope = PackedStringArray()
	var p := spawn_player(Vector3(0, 0.05, 0), 0.0)
	GameSession.on_level_ready(world, p)
	p.global_position = Vector3(0, 0.05, 0)
	p.velocity = Vector3.ZERO
	var titan := WorldItems.count(WorldState.inventory, WorldItems.TITAN_IRON)
	var iron := WorldItems.count(WorldState.inventory, WorldItems.IRON)
	assert_eq(p.progression.level, 8, "the giant loads at level 8")
	await _settle()
	await _settle()
	assert_eq(Quests.quest_state(CROWN), Quests.COMPLETED, "the oath quest completes once the save loads")
	assert_eq(_xp_from("quest:" + CROWN), {"quest:%s:meet" % CROWN: 50, "quest:%s:resolve" % CROWN: 750},
		"its stages pay 50 and 750 XP")
	assert_true(p.progression.level >= 9, "the resolution's level-9 floor (%d)" % p.progression.level)
	assert_eq(WorldItems.count(WorldState.inventory, WorldItems.TITAN_IRON) - titan, 1, "the oath's titan iron")
	assert_eq(WorldItems.count(WorldState.inventory, WorldItems.IRON) - iron, 2, "the oath's 2 iron")
	assert_eq(Quests.objectives().filter(func(o: Dictionary) -> bool: return str(o.quest_id) == CROWN), [],
		"'Meet Aldmere's herald' leaves the tracker")
	var h := Quests.start_dialogue("dialogue.herald", "world.aldmere.herald")
	assert_eq(str(h.node().get("id", "")) if h != null else "", "sworn_sabotage", "the herald speaks of the sabotage")
	Quests.end_dialogue()
	# A checkpoint, then a reload: nothing is paid twice.
	assert_true(bool(GameSession.take_checkpoint("test").ok), "a checkpoint after the repair")
	var paid := _xp.size()
	GameSession.reload_checkpoint("menu")
	p.queue_free()
	await step_ticks(2)
	var q := spawn_player(Vector3(0, 0.05, 0), 0.0)
	GameSession.on_level_ready(world, q)
	q.global_position = Vector3(0, 0.05, 0)
	await _settle()
	assert_eq(_xp.size(), paid, "a reload pays nothing again (%s)" % [_xp.slice(paid)])
	assert_eq(Quests.quest_state(CROWN), Quests.COMPLETED, "and the oath quest stays complete")


# --------------------------------------------------------------------------- F6

## The campaign from world_start in level.world, the giant at `stage` on the suite's floor, Quests over
## every shipped quest.
func _world_start(stage := 4) -> GiantPlayer:
	GameSession.start_world_for_tests(START_CP)
	GameSession.level_id = "level.world"
	var p := spawn_player(Vector3(0, 0.05, 0), 0.0)
	GameSession.on_level_ready(world, p)
	p.global_position = Vector3(0, 0.05, 0)
	p.velocity = Vector3.ZERO
	p.set_profile(GameData.get_record("growth.%02d" % stage))
	Quests.test_active = true
	Quests.scope = PackedStringArray()
	await _settle()
	return p


func _choose_text(s: DialogueSession, prefix: String) -> bool:
	for c: Dictionary in s.choices():
		if str(c.text).begins_with(prefix) and not bool(c.get("locked", false)):
			s.choose(int(c.index))
			return true
	return false


## The crown's oath by parley, as a player swears it: Wynn spared (his word), the herald shown it,
## Corvane's oath at the horn.
func _parley() -> void:
	var d := Quests.start_dialogue("dialogue.deserters", "world.aldmere.deserter_wynn")
	if d != null:
		d.choose_outcome("spare")
	Quests.end_dialogue()
	var h := Quests.start_dialogue("dialogue.herald", "world.aldmere.herald")
	assert_true(h != null and _choose_text(h, "What are the three roads"), "the herald names the three roads")
	if h != null:
		h.choose_outcome("parley_deserters")
	Quests.end_dialogue()
	var c := Quests.start_dialogue("dialogue.corvane", "world.aldmere.fort_parley")
	if c != null:
		c.choose_outcome("parley")
	Quests.end_dialogue()
	await _settle()
	assert_eq(str(WorldState.get_flag("oath.crown.outcome", "")), "parley", "the crown sworn by parley")


func _blow(target_id: String) -> void:
	var e := HitEvent.new()
	e.tick = Sim.tick
	e.instance_id = Sim.new_instance_id()
	e.attacker_id = "player"
	e.target_id = target_id
	e.action_id = "ability.light_1"
	e.power = 5.0
	e.attacker_stat = 10.0
	e.attacker_height_m = 11.0
	e.damage_split = {"physical": 1.0}
	e.tags = PackedStringArray(["Melee", "Light", "BasicAttack"])
	e.attacker_position = Vector3.ZERO
	Sim.queue_hit(e)


var _guards := 0


## Aldmere offended the way FactionState counts it: two blows on one of its soldiers.
func _offend_aldmere() -> void:
	_guards += 1
	var guard: SoldierEnemy = (load(SOLDIER) as PackedScene).instantiate()
	guard.entity_id = "test.m8q.aldmere_guard_%d" % _guards
	guard.ai_enabled = false
	guard.faction = "aldmere"
	guard.position = Vector3(0, 0.05, -5)
	world.add_child(guard)
	await step_ticks(2)
	for i in 2:
		_blow(guard.entity_id)
		await step_ticks(3)
	assert_eq(FactionState.standing("aldmere"), "hostile", "two blows on its soldier turn Aldmere hostile again")


func _node_of(dialogue_id: String, npc: String) -> String:
	var s := Quests.start_dialogue(dialogue_id, npc)
	var node := str(s.node().get("id", "")) if s != null else ""
	Quests.end_dialogue()
	return node


func test_a_peaceful_crown_gives_up_the_ridge_and_a_broken_peace_is_named_and_mended() -> void:
	await _world_start(4)
	WorldState.set_flag(Discovery.discovered_flag("poi.ballista_ridge"), true)   # the ridge found on the way
	await _settle()
	assert_eq(Quests.quest_state(RIDGE), Quests.ACTIVE, "Ballista Ridge's errand starts at stage 4")
	await _parley()
	assert_eq(Quests.quest_state(RIDGE), Quests.ABANDONED, "a crown sworn in peace gives the ridge's errand up")
	assert_eq(Quests.objectives().filter(func(o: Dictionary) -> bool: return str(o.quest_id) == RIDGE), [],
		"'Silence the three ballistae' leaves the tracker")
	assert_eq(FactionState.standing("aldmere"), "reconciled", "Aldmere at peace")
	assert_eq(_node_of("dialogue.herald", "world.aldmere.herald"), "sworn_parley", "the herald: the peace holds")
	# The peace broken: the herald and Corvane say so before their sworn lines.
	await _offend_aldmere()
	assert_eq(_node_of("dialogue.corvane", "world.aldmere.fort_parley"), "broken_peace", "Corvane names the broken peace")
	var iron := WorldItems.count(WorldState.inventory, WorldItems.IRON)
	var h := Quests.start_dialogue("dialogue.herald", "world.aldmere.herald")
	assert_eq(str(h.node().get("id", "")) if h != null else "", "broken_peace", "so does the herald")
	assert_true(h != null and h.find_choice("reconcile_aldmere") >= 0, "she takes a price for the harm (%s)" % [
		h.choices().map(func(c: Dictionary) -> String: return str(c.text)) if h != null else []])
	if h != null:
		h.choose_outcome("reconcile_aldmere")
	Quests.end_dialogue()
	await step_ticks(2)
	assert_eq(WorldItems.count(WorldState.inventory, WorldItems.IRON), iron - 2, "2 iron paid")
	assert_eq(FactionState.standing("aldmere"), "reconciled", "the peace mended")
	assert_eq(_node_of("dialogue.herald", "world.aldmere.herald"), "sworn_parley", "the herald: the peace holds again")
	assert_eq(_node_of("dialogue.corvane", "world.aldmere.fort_parley"), "sworn", "Corvane too")
	# With no iron the price is named, greyed.
	await _offend_aldmere()
	var left := WorldItems.count(WorldState.inventory, WorldItems.IRON)
	if left > 0:
		WorldState.remove_item(WorldItems.IRON, left, "test")
	var h2 := Quests.start_dialogue("dialogue.herald", "world.aldmere.herald")
	var locked := h2.choices().filter(func(c: Dictionary) -> bool: return bool(c.get("locked", false))) if h2 != null else []
	assert_eq(locked.map(func(c: Dictionary) -> String: return str(c.locked_text)), ["You need 2 iron"],
		"without iron the price is greyed with its reason")
	Quests.end_dialogue()


func test_a_ridge_found_after_a_peaceful_crown_starts_no_errand() -> void:
	await _world_start(4)
	await _parley()
	WorldState.set_flag(Discovery.discovered_flag("poi.ballista_ridge"), true)
	await _settle()
	assert_eq(Quests.quest_state(RIDGE), Quests.INACTIVE, "Aldmere's allies are not asked to silence its ballistae")


func test_the_sabotage_and_the_struck_warlord_keep_aldmere_at_war() -> void:
	await _world_start(4)
	# The sabotage's and a struck Corvane's Aldmere stays hostile: their sworn lines, no price offered.
	for pair: Array in [["sabotage", "", "sworn_sabotage"], ["breach", "slain", "sworn_breach"]]:
		WorldState.clear()
		for f: Array in [["oath.crown.met", true], ["oath.crown.done", true], ["oath.crown.outcome", pair[0]],
				[FactionState.flag_id("aldmere", "hostile"), true]]:
			WorldState.set_flag(str(f[0]), f[1])
		if str(pair[1]) != "":
			WorldState.set_flag("boss.corvane.outcome", pair[1])
		assert_eq(_node_of("dialogue.herald", "world.aldmere.herald"), str(pair[2]), "%s: the herald's sworn line" % pair[0])


# --------------------------------------------------------------------------- F34

func test_the_stage_6_grow_summary_says_what_siege_disruption_unlocks() -> void:
	var p5 := PlayerGrowth.find_profile(GameData.records_of_type("growth_profile"), 5)
	var p6 := PlayerGrowth.find_profile(GameData.records_of_type("growth_profile"), 6)
	var s := PlayerGrowth.change_summary(p5, p6, {}, {}, [], {})
	assert_true((s.permissions as Array).has("siege_disruption"), "stage 6 adds siege disruption")
	var lines := Array(s.lines).filter(func(l: String) -> bool: return l.to_lower().contains("siege engine"))
	assert_eq(lines.size(), 1, "one line names it (%s)" % [s.lines])
	var line: String = lines[0] if not lines.is_empty() else ""
	assert_true(line.contains("Seize") and line.contains("staggered or uncrewed") and line.contains("hurl"),
		"it says what stage 6 adds: seizing a staggered or uncrewed engine and hurling it (%s)" % line)
	assert_false(line.contains("Wreck"), "not wrecking engines, which blows do at any stage")
	# The engines' own refusal says the same two ways in (siege_engine.gd's crewed line).
	for id: String in ["prop.siege_ballista", "prop.siege_catapult"]:
		var engine: Dictionary = GameData.get_record(id).get("engine", {})
		assert_eq(int(engine.get("grab_stage", 0)), 6, "%s is seized from stage 6" % id)
		assert_false(GameData.get_record(id).has("requires_stage"), "%s breaks under blows at any stage" % id)


# --------------------------------------------------------------------------- F42

## An npc record's scene spawned as EncounterDirector._spawn does: its CombatEntity's definition and
## the actor's entity id set before it enters the tree.
func _spawn_npc(definition: String, entity_id: String, at: Vector3) -> Node3D:
	var node := (load(str(GameData.get_record(definition).get("scene", ""))) as PackedScene).instantiate() as Node3D
	var ce := node.get_node_or_null("CombatEntity")
	if ce != null and "definition_id" in ce:
		ce.set("definition_id", definition)
	node.set("entity_id", entity_id)
	node.position = at
	world.add_child(node)
	return node


static func _talker_of(node: Node) -> NpcTalker:
	for n in node.find_children("*", "", true, false):
		if n is NpcTalker:
			return n
	return null


func test_every_talker_npc_is_built_from_a_scene_that_carries_an_npc_talker() -> void:
	var talkers := GameData.records_of_type("npc").filter(func(r: Dictionary) -> bool: return str(r.get("role", "")) == "talker")
	assert_true(talkers.size() >= 8, "the talkers ship (%d)" % talkers.size())
	var lacking := PackedStringArray()
	var i := 0
	for rec: Dictionary in talkers:
		i += 1
		var id := "test.m8q.talker_%d" % i
		var node := _spawn_npc(str(rec.id), id, Vector3(4.0 * i, 0.05, -10))
		await step_ticks(1)
		var t := _talker_of(node)
		if t == null:
			lacking.append("%s (%s)" % [rec.id, rec.scene])
			continue
		assert_eq(t.resolved_npc_id(), id, "%s's talker names its npc" % rec.id)
		assert_eq(t.resolved_dialogue_id(), str(rec.get("dialogue", "")), "%s's talker runs its record's dialogue" % rec.id)
		assert_false(t.dialogue_record().is_empty(), "%s's dialogue exists" % rec.id)
	assert_eq(lacking, PackedStringArray(), "every talker can be talked to")


# --------------------------------------------------------------------------- F46

const BELLS := "quest.drowned_bells"


func _bell_marker(n: int) -> Vector3:
	return WorldXp.position_of("world.marker.bell_%d" % n)


func test_the_bells_lead_a_stage_4_giant_to_a_bell_it_can_reach() -> void:
	GameSession.start_world_for_tests("world.cp.mere_south")
	GameSession.level_id = "level.world"
	var p := spawn_player(Vector3(0, 0.05, 0), 0.0)
	GameSession.on_level_ready(world, p)
	p.set_profile(GameData.get_record("growth.04"))
	Quests.test_active = true
	Quests.scope = PackedStringArray([BELLS])
	await _settle()
	assert_true(Quests.start_quest(BELLS), "the bells' quest starts")
	for id: String in ["world.drowned.bell_1", "world.drowned.bell_3"]:
		WorldState.record_destroyed(id)   # rung (a bell records its destruction)
	# The giant stands at the third bell's marker on the north shore.
	var at := _bell_marker(3)
	add_box(Vector3(40, 1, 40), Vector3(at.x, -0.5, at.z))
	p.global_position = Vector3(at.x, 0.05, at.z)
	p.velocity = Vector3.ZERO
	await _settle()
	var o := Quests.objective_for(BELLS)
	assert_eq(o.markers, PackedStringArray(["world.marker.bell_2", "world.marker.bell_4", "world.marker.bell_5"]),
		"three bells still to ring")
	assert_eq(str(o.marker_id), "world.marker.bell_2", "a stage-4 giant is led to the second bell, the nearest it can reach")
	assert_true((o.position as Vector3).is_equal_approx(_bell_marker(2)), "and the position is that bell's (%s)" % o.position)
	assert_eq((o.positions as Array).size(), 3, "the compass still draws every open bell")
	# At stage 5 the island's bell past the channel is the nearest.
	p.set_profile(GameData.get_record("growth.05"))
	await _settle()
	o = Quests.objective_for(BELLS)
	assert_eq(str(o.marker_id), "world.marker.bell_5", "at stage 5 the island's bell leads")
	assert_true((o.position as Vector3).is_equal_approx(_bell_marker(5)), "its position is the island bell's")
	# Back at stage 4 with only the island's bell open, it still leads (nothing else is open).
	p.set_profile(GameData.get_record("growth.04"))
	for id: String in ["world.drowned.bell_2", "world.drowned.bell_4"]:
		WorldState.record_destroyed(id)
	await _settle()
	o = Quests.objective_for(BELLS)
	assert_eq([str(o.marker_id), (o.position as Vector3).is_equal_approx(_bell_marker(5))], ["world.marker.bell_5", true],
		"the last open bell leads even before the giant can reach it")
	assert_eq(Quests.marker_min_stage("world.marker.bell_5"), 5, "the island's bell lies in the Ancestral Circle (stage 5)")
	assert_eq(Quests.marker_min_stage("world.marker.bell_2"), 0, "the second bell in the open shallows")


# --------------------------------------------------------------------------- F29

const MAIN := "quest.world_main"
const TRACKER := preload("res://ui/hud/quest_tracker.gd")
const LAYOUTS := ["crownmarch", "greywood", "drowned_steps", "aldmere", "stonehold"]


func test_every_size_gate_names_its_stage_and_the_stair_the_way_round() -> void:
	var gates := {}
	for r: String in LAYOUTS:
		var d: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tools/data/world/%s.json" % r))
		for g: Dictionary in d.get("size_gates", []):
			gates[str(g.id)] = g
	assert_true(gates.size() >= 4, "the world's size gates (%s)" % [gates.keys()])
	for id: String in gates:
		var g: Dictionary = gates[id]
		var text := str(g.get("message", ""))
		if text == "":
			text = str(SizeGate.DEFAULT_MESSAGES.get(int(g.min_stage), ""))
		assert_true(text.contains("Grow to stage %d" % int(g.min_stage)), "%s names the stage it needs: '%s'" % [id, text])
	for id: String in ["world.gate.giants_stair", "world.gate.moot"]:
		assert_true(str(gates[id].message).ends_with("Grow to stage 6.") or str(gates[id].message).contains("Grow to stage 6,"),
			"%s ends with what to do (%s)" % [id, gates[id].message])
	assert_true(str(gates["world.gate.giants_stair"].message).contains("the Ironway"), "the Stair names the way round")


func test_grow6_names_the_ironway_and_leads_a_smaller_giant_round_by_it() -> void:
	var grow6 := Quests.stage_record(GameData.get_record(MAIN), "grow6")
	var waiting := str(grow6.get("waiting_text", ""))
	assert_true(waiting.contains("Ironway") and waiting.contains("Aldmere's road"),
		"grow6's waiting text names the way round (%s)" % waiting)
	GameSession.start_world_for_tests(START_CP)
	GameSession.level_id = "level.world"
	var p := spawn_player(Vector3(0, 0.05, 0), 0.0)
	GameSession.on_level_ready(world, p)
	p.set_profile(GameData.get_record("growth.05"))
	Quests.test_active = true
	Quests.scope = PackedStringArray([MAIN])
	Quests.main_quest_id = MAIN
	WorldState.set_flag(Quests.stage_flag(MAIN), "grow6")   # the main thread on grow6 (two oaths won)
	var stones := WorldXp.position_of("world.marker.standing_stones")
	var foot := WorldXp.position_of("world.cp.ironway")
	# On the Mere's north shore, below the Stair: the lead is the Ironway's waystone.
	for at: Vector3 in [Vector3(0, 0.05, -200), Vector3(-196, 0.05, 32), Vector3(500, 0.05, 150)]:
		p.global_position = at
		var o := Quests.objective_for(MAIN)
		assert_eq(str(o.marker_id), "world.cp.ironway", "at %s a stage-5 giant is led to the Ironway's foot" % at)
		assert_true((o.position as Vector3).is_equal_approx(foot), "the marker and the compass point there (%s)" % o.position)
		assert_eq(str(o.via_text), "by the Ironway", "the tracker says which way")
		assert_eq(TRACKER.title_of(o), "The Crown Unclaimed  -  by the Ironway", "the tracker's title line")
	# Up in the highlands (the Ironway's top, in the Stonehold): the Standing Stones.
	p.global_position = Vector3(700, 0.05, -560)
	var up := Quests.objective_for(MAIN)
	assert_eq(str(up.marker_id), "world.marker.standing_stones", "up the Ironway the Stones lead")
	assert_true((up.position as Vector3).is_equal_approx(stones), "their position")
	assert_eq(str(up.via_text), "", "no way round left to name")
	# A stage-6 giant climbs the Stair: no lead.
	p.set_profile(GameData.get_record("growth.06"))
	p.global_position = Vector3(0, 0.05, -200)
	assert_eq(str(Quests.objective_for(MAIN).marker_id), "world.marker.standing_stones", "at stage 6 the Stones lead from anywhere")
