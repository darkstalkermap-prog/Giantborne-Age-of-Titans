extends IntegrationSuite
## M9 gate (lane review): a save written before W23 (0.8.0-m8 and older) and the tracker of a world event it holds
## running. W23 (P39f) keeps whether the director holds an event's tracker in the flag <event>.tracker_held, and
## read a missing flag as "the player's": a 0.8.0-m8 save taken while the director held the raid's tracker kept
## the tracker on the raid, out of play, after a Continue far off (the review's probe). Now a run resumed without
## the flag holds it unknown until the director's first sync, which applies M8's rule (a tracker on the running
## event is the director's: out of play it goes back) and writes the flag, so every later save says whose it is
## and W23's rule - the player's own Track stands - holds from then on.
## On the tiny streamed level of tests/support/living_world_fixtures.gd (a raid by the giant's start; "far off"
## is its east end, out of the raid's start radius), with the save as an older build wrote it: the run's flags
## without <event>.tracker_held and <event>.tracked_before, the tracker as the save's progress kept it.

const F := preload("res://tests/support/living_world_fixtures.gd")
const MAIN := "quest.test_old_save_main"
const SIDE := "quest.test_old_save_side"
const FAR := Vector3(96.0, 0.0, 80.0)

var _root: WorldRoot
var _wd: WanderDirector


func after_each() -> void:
	F.reset()
	await super()


func _setup() -> WorldEvent:
	F.install()
	var made := F.make(world)
	_root = made[0]
	_wd = made[1]
	QuestFixtures.install([
		QuestFixtures.quest(MAIN, [QuestFixtures.stage("go", QuestFixtures.flag_cond("test.never"))]),
		QuestFixtures.quest(SIDE, [QuestFixtures.stage("go", QuestFixtures.flag_cond("test.never_side"))])])
	QuestFixtures.activate([MAIN, SIDE], [], MAIN)
	Quests.evaluate_now()
	assert_true(Quests.track(SIDE), "the player follows the side quest")
	WorldState.set_flag("p37.raid.on", true)
	_wd.check_events(Sim.tick)
	assert_eq(Quests.tracked_quest_id, F.RAID, "the raid starts by the giant and takes the tracker")
	return _wd.events[F.RAID]


## A Continue of the save an older build wrote now: the W23 flags gone, the carry forgotten, the tracker as the
## save kept it, the giant at `at`.
func _continue_old_save(tracked: String, at: Vector3, old := true) -> WorldEvent:
	if old:
		WorldState.flags.erase(WorldEvent.flag(F.RAID, "tracker_held"))
		WorldState.flags.erase(WorldEvent.flag(F.RAID, "tracked_before"))
	Quests.tracked_quest_id = tracked
	_root.free()
	WanderDirector._carry.clear()
	var made := F.make(world, at)
	_root = made[0]
	_wd = made[1]
	var raid: WorldEvent = _wd.events[F.RAID]
	assert_eq(raid.state, WorldEvent.WAITING, "the Continue resumes the raid")
	return raid


func test_an_older_save_with_the_directors_tracker_gives_it_back_far_off() -> void:
	_setup()
	var raid := _continue_old_save(F.RAID, FAR)
	assert_true(raid.get("hold_unknown") == true, "whose the tracker is waits for the first sync")
	await step_ticks(WanderDirector.UPDATE_TICKS * 3)
	assert_false(_wd.in_play(raid), "the raid is out of play")
	assert_true(Quests.tracked_quest_id != F.RAID, "the director's tracker leaves the raid, as on 0.8.0-m8 (on '%s')" % Quests.tracked_quest_id)
	assert_false(raid.get("hold_unknown") == true or raid.holds_tracker, "decided: the director holds nothing now")
	assert_true(WorldState.has_flag(WorldEvent.flag(F.RAID, "tracker_held")), "the flag is written, so the next save says whose it is")
	# From here W23's rule holds: the journal's Track of the raid far off stands, across another Continue too.
	assert_true(Quests.track(F.RAID), "the journal's Track")
	await step_ticks(WanderDirector.UPDATE_TICKS * 3)
	assert_eq(Quests.tracked_quest_id, F.RAID, "the player's Track stands")
	raid = _continue_old_save(F.RAID, FAR, false)
	assert_false(raid.get("hold_unknown") == true, "this save has the flag")
	await step_ticks(WanderDirector.UPDATE_TICKS * 3)
	assert_eq(Quests.tracked_quest_id, F.RAID, "the player's Track stands after the next Continue")


func test_an_older_save_continued_by_the_raid_keeps_its_tracker_until_it_is_left_behind() -> void:
	_setup()
	var raid := _continue_old_save(F.RAID, F.GIANT_AT)
	await step_ticks(WanderDirector.UPDATE_TICKS * 3)
	assert_true(_wd.in_play(raid), "the raid is in play by the giant")
	assert_eq(Quests.tracked_quest_id, F.RAID, "it keeps the tracker")
	assert_true(raid.holds_tracker, "as the director's (M8's rule)")
	assert_eq(WorldState.get_flag(WorldEvent.flag(F.RAID, "tracker_held")), true, "and the flag says so")
	F.move_giant(_root, FAR.x, FAR.z)
	await step_ticks(WanderDirector.UPDATE_TICKS * 3)
	assert_false(_wd.in_play(raid), "left behind")
	assert_true(Quests.tracked_quest_id != F.RAID, "it gives the tracker back (on '%s')" % Quests.tracked_quest_id)


func test_an_older_save_with_another_quest_tracked_keeps_it() -> void:
	_setup()
	var raid := _continue_old_save(SIDE, FAR)
	await step_ticks(WanderDirector.UPDATE_TICKS * 3)
	assert_eq(Quests.tracked_quest_id, SIDE, "the save's side quest stays tracked")
	assert_false(raid.holds_tracker, "the director holds nothing")
	assert_eq(WorldState.get_flag(WorldEvent.flag(F.RAID, "tracker_held")), false, "and the flag says so")
	assert_true(Quests.track(F.RAID), "the journal's Track of the raid, far off")
	await step_ticks(WanderDirector.UPDATE_TICKS * 3)
	assert_eq(Quests.tracked_quest_id, F.RAID, "the player's Track stands")
