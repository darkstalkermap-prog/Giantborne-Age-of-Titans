extends TestSuite
## A4: the cutscene timeline (CutsceneRules, pure) and the intro's record (cutscene.intro): shots cut at their starts
## and ease their camera's travel, subtitles and title by tick, a shake that fades, cues fired once in their tick
## range, actors eased between keys with their clips running on; the intro is about 30 s, its shots cover it end to
## end, its lines are short, one at a time, its title card closes it; and when the intro is due (GameSession: the
## world's first entry of a New Game, never a Continue, never twice).

const REC := {"ticks": 600,
	"shots": [{"id": "a", "start": 0, "end": 300, "from": [0, 0, 0], "to": [10, 0, 0], "look_from": [0, 0, -10],
		"look_to": [10, 0, -10], "fov": 50, "fov_to": 60, "ease": "linear"},
		{"id": "b", "start": 300, "end": 600, "from": [0, 5, 0], "look_from": [0, 5, -10]}],
	"lines": [{"start": 10, "end": 100, "text": "one"}, {"start": 120, "end": 200, "text": "two"}],
	"cues": [{"tick": 0, "cue": "c0"}, {"tick": 150, "cue": "c1"}],
	"shakes": [{"tick": 400, "amount": 1.0, "ticks": 20}],
	"fades": [{"start": 0, "end": 60, "from": 1.0, "to": 0.0}],
	"title": {"start": 500, "end": 600, "text": "T"},
	"actors": [{"id": "x", "kind": "stoneback", "show": [100, 500], "keys": [
		{"tick": 100, "at": [0, 0, 0], "yaw": 0, "clip": "rise", "clip_s": 0.0, "rate": 1.0},
		{"tick": 220, "at": [12, 0, 0], "yaw": 90, "clip": "walk", "clip_s": 0.0, "rate": 0.5, "loop": true, "ease": "linear"}]}]}


func after_each() -> void:
	GameSession.reset_for_tests()


func test_the_timeline() -> void:
	assert_eq(str(CutsceneRules.shot_at(REC, 0).id), "a", "the first shot")
	assert_eq(str(CutsceneRules.shot_at(REC, 300).id), "b", "cut at the next shot's start")
	assert_eq(CutsceneRules.shot_at(REC, 600), {}, "nothing after the end")
	var c := CutsceneRules.camera_at(REC, 150)
	assert_true((c.at as Vector3).is_equal_approx(Vector3(5, 0, 0)), "half way along a linear travel (%s)" % c.at)
	assert_near(float(c.fov), 55.0, 1e-4, "the fov eased")
	assert_true((CutsceneRules.camera_at(REC, 350).at as Vector3).is_equal_approx(Vector3(0, 5, 0)), "a still shot")
	assert_near(CutsceneRules.shake_at(REC, 400), 1.0, 1e-6, "a shake at its tick")
	assert_near(CutsceneRules.shake_at(REC, 410), 0.5, 1e-6, "fading")
	assert_eq(CutsceneRules.shake_at(REC, 420), 0.0, "gone")
	assert_false((CutsceneRules.camera_at(REC, 405).at as Vector3).is_equal_approx(Vector3(0, 5, 0)), "it moves the camera")
	assert_eq(CutsceneRules.camera_at(REC, 405), CutsceneRules.camera_at(REC, 405), "deterministically")
	assert_eq(CutsceneRules.line_at(REC, 50), "one", "a subtitle")
	assert_eq(CutsceneRules.line_at(REC, 110), "", "between lines none")
	assert_eq(CutsceneRules.due(REC, "cues", 0, 1).map(func(e: Dictionary) -> String: return str(e.cue)), ["c0"],
		"a cue in its range")
	assert_eq(CutsceneRules.due(REC, "cues", 1, 150).size(), 0, "not before its tick")
	assert_eq(CutsceneRules.due(REC, "cues", 150, 151).size(), 1, "once at it")
	assert_near(CutsceneRules.fade_at(REC, 30), 0.5, 1e-6, "the fade in")
	assert_eq(CutsceneRules.title_at(REC, 499), 0.0, "no title before its start")
	assert_near(CutsceneRules.title_at(REC, 530), 0.5, 1e-6, "the title fading in")
	var a: Dictionary = (REC.actors as Array)[0]
	assert_false(bool(CutsceneRules.actor_at(a, 50).visible), "an actor hidden before its show")
	var s := CutsceneRules.actor_at(a, 160)
	assert_true(bool(s.visible), "shown")
	assert_eq(str(s.clip), "rise", "its clip")
	assert_near(float(s.clip_s), 1.0, 1e-6, "running on from its key")
	assert_true((s.at as Vector3).is_equal_approx(Vector3(6, 0, 0)), "half way to the next key (%s)" % s.at)
	var w := CutsceneRules.actor_at(a, 340)
	assert_eq(str(w.clip), "walk", "the next key's clip")
	assert_near(float(w.clip_s), 1.0, 1e-6, "at its rate (2 s at 0.5)")
	assert_true(bool(w.loop), "looping")


func test_the_intro() -> void:
	var rec := GameData.get_record(ExpansionState.INTRO_ID)
	assert_false(rec.is_empty(), "the intro's record")
	var secs := CutsceneRules.seconds_of(rec)
	assert_true(secs >= 26.0 and secs <= 34.0, "about 30 s (%.1f)" % secs)
	var shots: Array = rec.shots
	assert_eq(int(shots[0].start), 0, "a shot from the start")
	for i in shots.size() - 1:
		assert_eq(int(shots[i].end), int(shots[i + 1].start), "no gap after %s" % shots[i].id)
	assert_eq(int(shots.back().end), CutsceneRules.ticks_of(rec), "to the end")
	var ids: Array = shots.map(func(s: Dictionary) -> String: return str(s.id))
	assert_eq(ids, ["rim", "vista", "millford", "pit", "small"], "the story's shots in order")
	var last_end := -1
	for l: Dictionary in rec.lines:
		assert_true(int(l.start) >= last_end, "one line at a time (%s)" % l.text)
		last_end = int(l.end)
		assert_true(str(l.text).length() <= 56, "a short line: %s" % l.text)
		assert_true(int(l.end) - int(l.start) >= 90, "on screen long enough to read: %s" % l.text)
	var text := " ".join((rec.lines as Array).map(func(l: Dictionary) -> String: return str(l.text)))
	for word: String in ["kings", "titan", "rim", "Millford"]:
		assert_true(text.contains(word), "the story: %s" % word)
	var kinds: Array = (rec.actors as Array).map(func(a: Dictionary) -> String: return str(a.kind))
	assert_true(kinds.has("stoneback") and kinds.has("giant") and kinds.has("villager"),
		"Stoneback, the player's own giant and people in frame (%s)" % str(kinds))
	assert_true(CutsceneRules.title_at(rec, CutsceneRules.ticks_of(rec) - 1) > 0.9, "the title card at the end")
	assert_true((rec.shakes as Array).size() >= 4, "his footfalls shake the camera")
	for c: Dictionary in rec.cues:
		assert_true(Audio.has_cue(str(c.cue)), "an existing cue (no new sound): %s" % c.cue)


func test_the_intro_is_due_on_the_worlds_first_entry_of_a_new_game_only() -> void:
	GameSession.cutscenes_on = true
	GameSession.level_id = GameSession.WORLD_LEVEL_ID
	GameSession.progress = GameSession.default_progress()
	GameSession.expansion = ExpansionState.defaults()
	GameSession.call("_check_intro", "new_game")
	assert_true(GameSession.intro_due, "a New Game in the world")
	GameSession.call("_check_intro", "continue")
	assert_false(GameSession.intro_due, "never on a Continue")
	GameSession.call("_check_intro", "travel")
	assert_true(GameSession.intro_due, "the Valley's hand-over (the first travel into the world)")
	GameSession.progress.world_entered = true
	GameSession.call("_check_intro", "travel")
	assert_false(GameSession.intro_due, "not on a later entry")
	GameSession.progress.world_entered = false
	ExpansionState.note_seen(GameSession.expansion, ExpansionState.INTRO_ID)
	GameSession.call("_check_intro", "new_game")
	assert_false(GameSession.intro_due, "not once this game has seen it")
	GameSession.expansion = ExpansionState.defaults()
	GameSession.level_id = GameSession.VALLEY_LEVEL_ID
	GameSession.call("_check_intro", "new_game")
	assert_false(GameSession.intro_due, "not in the Valley (it plays at the hand-over)")
	GameSession.level_id = GameSession.WORLD_LEVEL_ID
	GameSession.cutscenes_on = false
	GameSession.call("_check_intro", "new_game")
	assert_false(GameSession.intro_due, "not while cutscenes are off (tool runs, headless)")
	var o := GameSession.parse_args(PackedStringArray(["--cinematic=intro", "--quit-after-cinematic"]))
	assert_eq(str(o.cinematic), "cutscene.intro", "--cinematic names the cutscene")
	assert_eq(str(o.mode), "world", "in the world")
	assert_true(bool(o.quit_after_cinematic), "and the run ends after it")
	assert_true(bool(GameSession.parse_args(PackedStringArray(["--no-cutscenes"])).no_cutscenes), "--no-cutscenes")
