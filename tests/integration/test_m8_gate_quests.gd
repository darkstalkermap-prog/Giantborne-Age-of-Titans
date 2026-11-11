extends IntegrationSuite
## M8 gate review fixes, lane m8q (quests, dialogue and tutorials): the default tier's half - records,
## Quests over the shipped quests on the suite's floor, the save slot and the dialogue records; no world
## or chunk is loaded (the gate half: tests/gate/test_aldmere_walkthrough.gd, test_main_thread_combinations.gd,
## test_drowned_walkthrough.gd; the main.tscn half: tests/slow/test_m8_gate_tutorials.gd).
##   * F39: every record that writes an oath's done flag writes its met flag too (Edda's and Sedge's
##     resolutions always did; the crown's battle and ridge did not, so a breach or a sabotage won before
##     meeting the herald left quest.oath_crown on "Meet Aldmere's herald" for good), and a save already
##     stuck that way loads, completes the oath quest and pays its resolution once.

const START_CP := "world.cp.kingsgate_shelf"
const CROWN := "quest.oath_crown"
const OATHS := ["march", "wood", "crown"]
const STUCK_SAVE := "res://tests/fixtures/saves/v2_crown_sabotage_stuck_on_meet.json"

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
