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
