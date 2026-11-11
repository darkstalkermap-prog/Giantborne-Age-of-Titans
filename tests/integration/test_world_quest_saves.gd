extends IntegrationSuite
## M8 gate fix-up 1: the world's quests and the save (the audit's play pass, N4.1 and N4.2). The campaign
## from world_start in level.world on the suite's floor, saving on, Quests over every shipped quest as the
## campaign runs them (not a test's test_active):
##   * N4.1: a stage the loaded save already meets - the growth checkpoint is taken before the stage it
##     completes - is completed once the restored giant is in its level, and pays it: Continue used to
##     evaluate the quests while the title was still up (no player: the XP went to no listener and the
##     stage's once-flag was set for good), and a tutorial prompt showed there.
##   * N4.2: the world's main thread is checkpointed - quest.world_main's stages and an oath won are taken
##     with enemies aware about (completion requests: the war camp after its sabotage) and survive a quit to
##     the title; another quest's start in the world (Ulfra's plea starting the siege) is an ordinary
##     request: it waits for the aware enemy, then is taken.

const START_CP := "world.cp.kingsgate_shelf"
const MAIN := "quest.world_main"
const WOOD := "quest.oath_wood"
const SIEGE := "quest.siege_of_skarn"

var _xp: Array = []
var _shown: Array = []


func before_each() -> void:
	await super()
	_xp.clear()
	_shown.clear()
	Events.xp_award_requested.connect(_on_xp)
	Events.tutorial_shown.connect(_on_shown)


func after_each() -> void:
	if Events.xp_award_requested.is_connected(_on_xp):
		Events.xp_award_requested.disconnect(_on_xp)
	if Events.tutorial_shown.is_connected(_on_shown):
		Events.tutorial_shown.disconnect(_on_shown)
	Quests.end_dialogue()
	FactionState.reset_for_tests()
	SaveSlots.delete_slot(true)
	GameSession.persist = false
	await super()


func _on_xp(amount: int, source: String) -> void:
	_xp.append([amount, source])


func _on_shown(_tick: int, prompt_id: String) -> void:
	_shown.append(prompt_id)


func _settle() -> void:
	await step_ticks(Quests.EVALUATE_EVERY_TICKS * 2 + 1)


## The campaign's New Game in the world, saving on, the giant at `stage` (Quests run as the campaign runs
## them: no test_active).
func _world_start(stage: int) -> GiantPlayer:
	GameSession.persist = true
	GameSession.start_world_for_tests(START_CP)
	GameSession.level_id = "level.world"
	var p := await _restore()
	p.set_profile(GameData.get_record("growth.%02d" % stage))
	await _settle()
	return p


## The level's giant once a load is done: on_level_ready restores the session's character.
func _restore() -> GiantPlayer:
	var p := spawn_player(Vector3(0, 0.05, 0), 0.0)
	GameSession.on_level_ready(world, p)
	p.global_position = Vector3(0, 0.05, 0)
	p.velocity = Vector3.ZERO
	return p


func _saved() -> Dictionary:
	var r := SaveSlots.read()
	assert_true(r.ok, "the save slot reads (%s)" % r.message)
	return r.data if r.ok else {}


func _saved_flag(flag: String) -> Variant:
	return ((_saved().get("world", {}) as Dictionary).get("flags", {}) as Dictionary).get(flag)


## Quit to title and Continue: the title's frames (no player) pass, then the level's giant is restored.
func _quit_and_continue(p: GiantPlayer, title_ticks: int) -> GiantPlayer:
	GameSession.go_to_title()
	p.queue_free()
	await step_ticks(2)
	var r := GameSession.continue_valley()
	assert_true(bool(r.ok), "Continue loads the save (%s)" % r.message)
	await step_ticks(title_ticks)
	return await _restore()


func test_a_stage_the_save_already_meets_pays_its_xp_after_continue() -> void:
	var p := await _world_start(3)
	assert_false(Quests.test_active, "the campaign runs the quests")
	assert_eq(Quests.stage_of(MAIN), "beacon", "the main thread waits at the beacon")
	WorldState.set_flag("world.kingsgate.lit", true)
	await _settle()
	assert_eq(Quests.stage_of(MAIN), "grow4", "the beacon relit: grow at the Kingsgate shrine")
	# The giant grows at the shrine: the growth's checkpoint is written before the quests see the growth.
	p.set_profile(GameData.get_record("growth.04"))
	assert_true(bool(GameSession.take_checkpoint("growth").ok), "the growth's checkpoint")
	var saved_xp := int((_saved().get("character", {}) as Dictionary).get("xp", -1))
	assert_eq(str(_saved_flag(Quests.stage_flag(MAIN))), "grow4", "the save holds the grown giant on grow4")
	_xp.clear()
	_shown.clear()
	var q := await _quit_and_continue(p, Quests.EVALUATE_EVERY_TICKS * 3)
	# While the title was up nothing was evaluated (the restored giant is on screen only now).
	assert_eq(_xp, [], "no XP paid while the title was up")
	assert_eq(_shown, [], "no tutorial prompt shown while the title was up")
	assert_eq(int(q.progression.xp), saved_xp, "the giant loads with the saved XP")
	await _settle()
	assert_eq(Quests.stage_of(MAIN), "oaths", "the stage completes once the giant is back")
	var award := Quests.stage_award(Quests.stage_record(GameData.get_record(MAIN), "grow4"), saved_xp)
	assert_true(award > 0, "grow4 pays XP (%d)" % award)
	assert_eq(int(q.progression.xp), saved_xp + award, "and pays it to the giant (%s)" % [_xp])
	assert_eq(_xp.filter(func(a: Array) -> bool: return str(a[1]) == "quest:%s:grow4" % MAIN).size(), 1, "once")
	# N4.2: the stage change is checkpointed with it.
	assert_eq(str(_saved_flag(Quests.stage_flag(MAIN))), "oaths", "the save moves on to the oaths")
	assert_eq(int((_saved().get("character", {}) as Dictionary).get("xp", -1)), saved_xp + award, "with the XP")


func test_the_world_main_thread_and_an_oath_are_saved_with_enemies_about_and_survive_a_quit() -> void:
	var p := await _world_start(4)
	assert_eq(Quests.stage_of(MAIN), "beacon", "the main thread waits at the beacon")
	var guard := TestSpawn.stub_enemy(world, p.global_position + Vector3(0, 0, -10), "test.fixup.guard")
	await step_ticks(2)
	guard.brain.aware = true
	assert_true(GameSession.checkpoint_blockers().has("aware:test.fixup.guard"), "an aware enemy 10 m away")
	var taken := GameSession.checkpoints_taken
	WorldState.set_flag("world.kingsgate.lit", true)
	await _settle()
	assert_eq(Quests.stage_of(MAIN), "oaths", "the beacon relit, the giant already grown: the oaths")
	assert_true(GameSession.checkpoints_taken > taken, "the main thread's stages take their checkpoint")
	assert_eq(str(_saved_flag(Quests.stage_flag(MAIN))), "oaths", "with the aware enemy about")
	# The wood's oath, won: its quest's completion is saved with the enemy still aware.
	assert_eq(Quests.quest_state(WOOD), Quests.ACTIVE, "the wood's oath quest runs at stage 4")
	WorldState.set_flag("oath.wood.met", true)
	await _settle()
	WorldState.set_flag("boss.matriarch.outcome", "fled")
	await _settle()
	WorldState.set_flag("oath.wood.outcome", "drive")
	WorldState.set_flag("oath.wood.done", true)
	await _settle()
	assert_eq(Quests.quest_state(WOOD), Quests.COMPLETED, "the wood's oath is won")
	assert_eq(_saved_flag(Quests.done_flag(WOOD)), true, "and saved with the aware enemy about")
	assert_eq(str(_saved_flag("oath.wood.outcome")), "drive", "its outcome too")
	assert_true(GameSession.pending_checkpoint().is_empty(), "nothing waits")
	# Another quest started in the world (Ulfra's plea starts the siege's quest): an ordinary request.
	WorldState.set_flag("world.skarn.plea_accepted", true)
	await _settle()
	assert_eq(Quests.quest_state(SIEGE), Quests.ACTIVE, "the plea starts the siege's quest")
	assert_eq(str(GameSession.pending_checkpoint().get("reason", "")), "quest_started", "its checkpoint waits for the aware enemy")
	assert_eq(_saved_flag(Quests.stage_flag(SIEGE)), null, "not saved yet")
	guard.brain.aware = false
	await step_ticks(2)
	assert_eq(str(_saved_flag(Quests.stage_flag(SIEGE))), "await", "taken once no enemy is aware")
	# A quit to the title and Continue keep all of it.
	var q := await _quit_and_continue(p, 3)
	await _settle()
	assert_eq(Quests.stage_of(MAIN), "oaths", "after Continue: the oaths stage")
	assert_eq(Quests.quest_state(WOOD), Quests.COMPLETED, "the wood's oath won")
	assert_eq(str(WorldState.get_flag("oath.wood.outcome", "")), "drive", "its outcome kept")
	assert_eq(Quests.quest_state(SIEGE), Quests.ACTIVE, "the plea kept")
	assert_true(q.progression.level >= 7, "the beacon's level floor kept (%d)" % q.progression.level)


## A completion request that something other than an aware enemy holds back (a hold) is committed by
## Quit to title: the main thread's stage is not lost to a quit.
func test_a_main_stage_held_back_is_committed_by_a_quit_to_the_title() -> void:
	var p := await _world_start(4)
	p.controller.holding_id = "test.fixup.body"
	WorldState.set_flag("world.kingsgate.lit", true)
	await _settle()
	assert_eq(Quests.stage_of(MAIN), "oaths", "the beacon relit and grown: the oaths")
	assert_true(bool(GameSession.pending_checkpoint().get("completion", false)), "the stage's checkpoint waits for the hold")
	assert_true(str(_saved_flag(Quests.stage_flag(MAIN))) != "oaths", "not on disk yet")
	GameSession.go_to_title()
	assert_eq(str(_saved_flag(Quests.stage_flag(MAIN))), "oaths", "the quit to the title commits it")
