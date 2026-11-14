extends TestSuite
## The world's factions by record (P29; plan M6-M9 §2.12, §5.9, decision 31): Brannock, Millford,
## the toll-riders and Aldmere as their records say - warnings, hostility (a hostile-by-default
## faction too), reconciliation by the talker's dialogue outcome (every time it is chosen) and
## give-way; their texts; Thornwick's texts unchanged (regression); and the respawn blocker: a
## respawn at Brannock's waystone while the town is hostile and its armed guards stand within 120 m
## moves to the nearest visited checkpoint that is not refused - and stays when the guards are dead
## or the town at peace. Records and FactionState's statics, no scene: the default tier's budget.

const WORLD := "level.world"
const BRANNOCK_CP := "world.cp.brannock"
## faction short -> [initial, offences_to_hostile, gives way, respawn_guard_m, reconcile talker].
const RECORDS := {
	"brannock": ["neutral", 2, true, 120.0, "world.crownmarch.edda"],
	"millford": ["neutral", 2, true, 120.0, "world.crownmarch.reeve_tamsin"],
	"toll_riders": ["hostile", 1, false, 0.0, ""],
	# M8 gate (F6): a peace sworn with the crown and broken afterwards is mended at the herald.
	"aldmere": ["neutral", 2, false, 0.0, "world.aldmere.herald"],
}
## Thornwick's texts as P22 shipped them (the regression of plan §3.12).
const THORNWICK := {"warned": "Thornwick's people cower. Strike again and they will fight you.",
	"hostile": "Thornwick turns on you: its guards will fight.",
	"stood_down": "Thornwick's guards stand down.",
	"reconciled": "Thornwick forgives you, if not the fright."}


func before_each() -> void:
	WorldState.clear()
	FactionState.reset_for_tests()


func after_each() -> void:
	WorldState.clear()
	FactionState.reset_for_tests()
	GameSession.mode = GameSession.Mode.SANDBOX
	GameSession.level_id = ""
	GameSession.respawn_id = ""


func test_every_world_faction_reads_as_its_record() -> void:
	for short: String in RECORDS:
		var spec: Array = RECORDS[short]
		var rec := FactionState.record_for(short)
		assert_false(rec.is_empty(), "faction.%s ships" % short)
		assert_eq(FactionState.initial(short), spec[0], "%s starts %s" % [short, spec[0]])
		assert_eq(FactionState.offences_to_hostile(short), spec[1], "%s turns hostile after %d offences" % [short, spec[1]])
		assert_eq(FactionState.give_way_m(short) > 0.0, spec[2], "%s's folk %s" % [short, "give way" if spec[2] else "hold"])
		assert_eq(FactionState.respawn_guard_m(short), spec[3], "%s's guards keep respawns %s m away" % [short, spec[3]])
		var talker := str((rec.get("reconcile", {}) as Dictionary).get("talker", ""))
		assert_eq(talker, spec[4], "%s's reconciliation talker" % short)
		for state: String in FactionState.TEXT_KEYS:
			assert_true(FactionState.text_for(short, state) != "", "%s says something when %s" % [short, state])
	var warnings := Array(GameData.warnings).filter(func(w: String) -> bool: return w.contains("faction."))
	assert_eq(warnings, [], "no warnings on the faction records")


func test_warnings_hostility_and_reconciliation_follow_the_records() -> void:
	var window := 30 * 60
	# Brannock: a first offence warns, a second inside the window turns it hostile.
	assert_eq(FactionState.offence_result_n(false, [], 100, window, FactionState.offences_to_hostile("brannock")),
		"warned", "Brannock: the first offence warns")
	assert_eq(FactionState.offence_result_n(true, [100], 200, window, FactionState.offences_to_hostile("brannock")),
		"hostile", "the second within 30 s turns it hostile")
	assert_eq(FactionState.offence_result_n(false, [], 100, window, FactionState.offences_to_hostile("toll_riders")),
		"hostile", "the toll-riders need no warning")
	assert_true(FactionState.is_hostile("toll_riders"), "the toll-riders are hostile from the start")
	assert_eq(FactionState.standing("toll_riders"), "hostile", "and act on it")
	assert_eq(FactionState.standing("brannock"), "neutral", "Brannock is at peace")
	WorldState.set_flag(FactionState.flag_id("brannock", "hostile"), true)
	assert_eq(FactionState.standing("brannock"), "hostile", "until it is offended twice")
	# Reconciliation: the talker's choice (outcome reconcile_brannock), every time it is chosen.
	FactionState.hub()
	assert_eq(FactionState.reconcile_outcome_faction("reconcile_brannock"), "brannock", "the outcome names the town")
	assert_eq(FactionState.reconcile_outcome_faction("reconcile_nowhere"), "", "an unknown faction is no outcome")
	assert_eq(FactionState.reconcile_outcome_faction("help"), "", "nor another outcome")
	Events.dialogue_outcome.emit(Sim.tick, "dialogue.edda", "reconcile_brannock")
	assert_true(FactionState.is_reconciled("brannock"), "Edda reconciles the town")
	assert_eq(FactionState.standing("brannock"), "reconciled", "reconciled wins over hostile")
	assert_false(FactionState.is_hostile("brannock"), "and it is no longer hostile")
	WorldState.set_flag(FactionState.flag_id("brannock", "reconciled"), false)
	Events.dialogue_outcome.emit(Sim.tick, "dialogue.edda", "reconcile_brannock")
	assert_true(FactionState.is_reconciled("brannock"), "a town that turned hostile again reconciles again")
	Events.dialogue_outcome.emit(Sim.tick, "dialogue.reeve_tamsin", "reconcile_millford")
	assert_true(FactionState.is_reconciled("millford"), "Tamsin reconciles Millford")


func test_thornwicks_texts_are_unchanged() -> void:
	for state: String in THORNWICK:
		assert_eq(FactionState.text_for("village", state), THORNWICK[state], "Thornwick's %s text" % state)
	assert_eq(FactionState.respawn_guard_m("village"), 0.0, "Thornwick's guards never move a respawn")


func test_a_respawn_at_brannock_moves_away_while_its_guards_are_hostile() -> void:
	GameSession.mode = GameSession.Mode.VALLEY
	GameSession.level_id = WORLD
	GameSession.respawn_id = BRANNOCK_CP
	var blocker := func(id: String) -> String: return FactionState.respawn_refusal(id)
	GameSession.register_respawn_blocker(blocker)
	assert_true(WorldIndex.for_level(WORLD).has_checkpoint(BRANNOCK_CP), "Brannock's waystone is in the world's index")
	assert_eq(FactionState.respawn_refusal(BRANNOCK_CP), "", "at peace: no refusal")
	assert_eq(GameSession.respawn_checkpoint(), BRANNOCK_CP, "the giant respawns at Brannock")
	WorldState.set_flag(FactionState.flag_id("brannock", "hostile"), true)
	var guards := FactionState.armed_members_near(WORLD, "brannock", WorldXp.position_of(BRANNOCK_CP), 120.0)
	assert_eq(guards.size(), 6, "four guards and the two archers of the south gate stand within 120 m of the waystone (the north gate's two do not)")
	assert_eq(FactionState.respawn_refusal(BRANNOCK_CP), "Brannock's guards hold the ground there.", "hostile: refused")
	WorldState.set_flag(GameSession.VISITED_PREFIX + "world.cp.kings_road", true)
	WorldState.set_flag(GameSession.VISITED_PREFIX + "world.cp.millford", true)
	var moved := GameSession.respawn_checkpoint()
	assert_eq(moved, "world.cp.kings_road", "the respawn moves to the nearest visited checkpoint (%s)" % moved)
	assert_eq(FactionState.respawn_refusal("world.cp.kings_road"), "", "which Brannock's guards do not refuse")
	for id: String in guards:
		WorldState.record_killed(id)
	assert_eq(FactionState.respawn_refusal(BRANNOCK_CP), "", "with its guards dead the town no longer refuses")
	GameSession.unregister_respawn_blocker(blocker)


## W23 (P39f; FOLLOWUPS "From P37"): a template's spawns are no members of its faction - it is never placed where
## its record draws it up (its copies stand where the WanderDirector puts them, never by a checkpoint) - so one drawn
## up by Brannock's waystone neither counts among its guards nor refuses a respawn there.
func test_a_template_drawn_up_by_a_checkpoint_is_no_guard() -> void:
	var at := WorldXp.position_of(BRANNOCK_CP)
	TestFixtures.record_override("encounter.test_tpl_brannock_militia", {"type": "encounter", "level": WORLD, "template": true,
		"center_m": [at.x, at.y, at.z], "spawns": [{"entity_id": "world.test.tpl_militia_1", "definition": "enemy.soldier",
			"position_m": [at.x + 5.0, at.y, at.z], "faction": "brannock"}]})
	WorldState.set_flag(FactionState.flag_id("brannock", "hostile"), true)
	var near := FactionState.armed_members_near(WORLD, "brannock", at, 120.0)
	assert_false(near.has("world.test.tpl_militia_1"), "a template's spawn is no guard (%s)" % [near])
	assert_eq(near.size(), 6, "the south gate's six guards and archers as before")
	for id: String in near:
		WorldState.record_killed(id)
	assert_eq(FactionState.respawn_refusal(BRANNOCK_CP), "", "with the guards dead the template drawn up there refuses nothing")
