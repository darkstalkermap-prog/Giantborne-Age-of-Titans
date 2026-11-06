extends IntegrationSuite
## P23 (plan M6-M9 §3.5 tests, §4.3): the Valley's score on its shipped records and Oggs, audio on.
##   - Giant's Hollow plays the calm set; its melody changes variant (or rests) only at the four-bar
##     segment boundaries, with the variant heard at the melody level and the others silent;
##   - crossing 20 m into the Old Wood brings the wild set in at the calm set's next bar, at the
##     calm set's position in the shared frame (its melody waiting for the next segment), and the
##     calm set is gone within its two crossfade bars;
##   - combat starts on a beat with the Wood's combat intro, its layers come in over two beats,
##     and the intro stinger ducks the stems by 8 dB until it has ended and released;
##   - the Ogre King's set follows his one-bar intro, in its own 104 BPM frame; phase 2 adds the
##     frenzy layer at the next bar; the victory stinger and the zone's set follow his defeat;
##   - the title, the end screen, the campaign's end and the sandbox play their sets.
## Music time comes from the director's clock (music.clock_positions) and Audio.advance_for_tests(),
## as in test_audio_director: the Dummy driver mixes in real time.

const VALLEY := "level.valley"
## The centre of Giant's Hollow and a point 20 m into the Old Wood across the Hollow's southern
## edge (z = 100 in level space; the hysteresis is 15 m).
const HOLLOW := Vector3(-145, 0, 150)
const WOOD := Vector3(-145, 0, 80)
const FRAME := 1.0 / 60.0


func before_each() -> void:
	await super()
	Audio.enable_for_tests()
	Audio.music.clock_positions = true


func after_each() -> void:
	Audio.enable_for_tests(false)
	await super()


## The Valley's level root (no scene: its record's districts are what the audio reads) and the
## giant at `at`; the samples registered and the zone's set started.
func _valley(at: Vector3) -> GiantPlayer:
	var lv := LevelRoot.new()
	lv.name = "Valley"
	lv.level_id = VALLEY
	world.add_child(lv)
	var p := spawn_player(at)
	Audio.advance_for_tests(1.6, 0.05)
	return p


## How far `t` is from the nearest multiple of `period` (either side; the clock sums frames).
static func off_grid(t: float, period: float) -> float:
	var into := fposmod(t, period)
	return minf(into, period - into)


## Advances to `lead` seconds before the next boundary of `period` in deck `d`, then frame by frame
## until `done` holds (at most `frames` frames). Returns the clock when it held (-1 if never).
func _step_until(d: MusicDirector.Deck, period: float, lead: float, done: Callable, frames := 30) -> float:
	var to_boundary := AudioMath.seconds_to_boundary(Audio.music.deck_position(d), period, d.loop_s)
	if to_boundary > lead:
		Audio.advance_for_tests(to_boundary - lead, 0.05)
	for i in frames:
		if done.call():
			return Audio.clock_s
		Audio.advance_for_tests(FRAME)
	return Audio.clock_s if done.call() else -1.0


func _melody_gain(d: MusicDirector.Deck) -> String:
	var problems := PackedStringArray()
	for v: String in ["melody_a", "melody_b", "melody_c"]:
		var want := db_to_linear(-2.0) if v == d.melody_choice else 0.0
		if absf(float(d.gains[v]) - want) > 1e-3:
			problems.append("%s at %.3f (want %.3f)" % [v, float(d.gains[v]), want])
	return ", ".join(problems)


func test_the_hollows_melody_moves_at_segment_boundaries_and_the_wood_comes_in_at_a_bar() -> void:
	var p := _valley(HOLLOW)
	assert_eq(Audio.music.state_name(), "zone", "zone music in the Hollow")
	assert_eq(Audio.music.set_id(), "music.valley_calm", "the calm set")
	var calm: MusicDirector.Deck = Audio.music.deck
	if calm == null:
		return
	assert_near(calm.segment_s, 10.0, 1e-6, "four-bar segments of 10 s at 96 BPM")
	# three loops in one-second steps: every change of the melody falls on a segment boundary
	var changes := 0
	var off_boundary := 0
	var bad_gains := 0
	var last_choice := calm.melody_choice
	var last_segment := calm.segment
	var heard := {}
	for i in 90:
		Audio.advance_for_tests(1.0, 1.0)
		if calm.melody_choice != last_choice:
			changes += 1
			if calm.segment == last_segment or off_grid(Audio.music.deck_position(calm), calm.segment_s) > 1.0 + 1e-6:
				off_boundary += 1
		elif _melody_gain(calm) != "":
			bad_gains += 1   # a step after a change the 80 ms switch has ended
		heard[calm.melody_choice] = true
		last_choice = calm.melody_choice
		last_segment = calm.segment
	assert_true(changes >= 2, "the melody moves within three loops (%d changes)" % changes)
	assert_eq(off_boundary, 0, "only at segment boundaries")
	assert_eq(bad_gains, 0, "the chosen variant at the melody level, the others silent")
	assert_true(heard.has("") and heard.size() >= 2, "it rests and plays (%s)" % [heard.keys()])
	# the crossing: 20 m into the Old Wood
	assert_near(calm.master, 1.0, 1e-6, "the calm set fully in")
	p.global_position = WOOD
	for i in 30:
		Audio.advance_for_tests(FRAME)
		if not Audio.music.pending.is_empty():
			break
	assert_eq(str(Audio.current_region().get("id", "")), "audio_region.valley_wood", "the Old Wood's region")
	assert_eq(str(Audio.music.pending.get("set", "")), "music.valley_wild", "the wild set waits for the bar")
	assert_eq(Audio.music.set_id(), "music.valley_calm", "the calm set plays on until then")
	var switched_at := _step_until(calm, calm.bar_s, 2.0 * FRAME,
		func() -> bool: return Audio.music.set_id() == "music.valley_wild")
	assert_true(switched_at > 0.0, "the wild set starts at the bar")
	var into_bar := off_grid(switched_at - calm.started_s, calm.bar_s)
	assert_true(into_bar < 1.5 * FRAME, "at a bar of the calm set (%.3f s from it)" % into_bar)
	var wild: MusicDirector.Deck = Audio.music.deck
	assert_true(Audio.music.old_decks.has(calm), "the calm set fades out")
	assert_near(Audio.music.deck_position(wild), Audio.music.deck_position(calm), 1e-3,
		"the wild set starts where the calm set is: one frame, one harmony through the crossfade")
	if fposmod(Audio.music.deck_position(wild), wild.segment_s) > MusicDirector.SEGMENT_ENTRY_S:
		assert_eq(wild.melody_choice, "", "mid-phrase, its melody waits for the next segment boundary")
	Audio.advance_for_tests(wild.bar_s, 0.05)
	assert_true(Audio.music.old_decks.has(calm) and calm.master > 0.3 and calm.master < 0.7,
		"half way through the two-bar crossfade after one bar (calm %.2f)" % calm.master)
	assert_near(wild.master, 0.5, 0.02, "and the wild set half in")
	Audio.advance_for_tests(wild.bar_s + 0.1, 0.05)
	assert_false(Audio.music.old_decks.has(calm), "the calm set is gone within two bars")
	assert_near(wild.master, 1.0, 1e-6, "the wild set fully in")


func test_combat_starts_on_a_beat_and_the_kings_set_follows_his_intro() -> void:
	_valley(WOOD)
	assert_eq(Audio.music.set_id(), "music.valley_wild", "the Old Wood's set")
	var wild: MusicDirector.Deck = Audio.music.deck
	if wild == null:
		return
	# combat: a hit on an enemy that counts; it starts on the next beat with the Wood's intro
	Audio.music.note_player_hit(true)
	for i in 20:   # the next intensity poll: combat waits for the beat
		Audio.advance_for_tests(FRAME)
		if bool(Audio.music.get("_pending_combat")):
			break
	assert_eq(Audio.music.intensity, AudioMath.EXPLORE, "not before the beat")
	var entered_at := _step_until(wild, wild.beat_s, 2.0 * FRAME,
		func() -> bool: return Audio.music.intensity == AudioMath.COMBAT)
	assert_true(entered_at > 0.0, "combat")
	var into_beat := off_grid(entered_at - wild.started_s, wild.beat_s)
	assert_true(into_beat < 1.5 * FRAME, "on a beat (%.3f s from it)" % into_beat)
	assert_eq(str(Audio.music.stingers.back()), "mus.stinger.combat_wild", "the Old Wood's combat intro")
	assert_true(Audio.active_ducks().has("stinger"), "the intro ducks the music")
	assert_near(float(wild.gains.drums), 0.0, 0.02, "the drums start from silence")
	Audio.advance_for_tests(wild.beat_s, FRAME)
	assert_near(float(wild.gains.drums), 0.5, 0.03, "half in after one beat (two-beat layer fades)")
	Audio.advance_for_tests(wild.beat_s + 0.05, FRAME)
	assert_near(float(wild.gains.drums), 1.0, 1e-6, "in after two beats")
	assert_near(float(wild.gains.drone), db_to_linear(-4.0), 1e-3, "the drone at its combat level")
	assert_near(float(wild.gains.brass), db_to_linear(-2.0), 1e-3, "the brass at -2 dB")
	var drone: AudioStreamPlayer = wild.players.drone
	var level := linear_to_db(float(wild.gains.drone) * wild.master)
	assert_near(drone.volume_db, level - 8.0, 0.05, "ducked 8 dB under the stinger")
	var intro_len := (load("res://assets/audio/music/stinger_combat_wild.ogg") as AudioStream).get_length()
	var release_s := entered_at + intro_len + MusicDirector.STINGER_RELEASE_S
	Audio.advance_for_tests(release_s - Audio.clock_s - 3.0 * FRAME, 0.05)
	assert_true(Audio.active_ducks().has("stinger"), "the duck holds through the intro and its release")
	var released_at := -1.0
	for i in 6:
		Audio.advance_for_tests(FRAME)
		if not Audio.active_ducks().has("stinger"):
			released_at = Audio.clock_s
			break
	assert_true(released_at > 0.0, "the stinger's duck ends")
	assert_near(released_at - entered_at, intro_len + MusicDirector.STINGER_RELEASE_S, 2.0 * FRAME,
		"after the intro (%.2f s) and its 0.5 s release" % intro_len)
	Audio.advance_for_tests(FRAME)
	assert_near(drone.volume_db, linear_to_db(float(wild.gains.drone) * wild.master), 0.05, "the stems back at their level")
	# the Ogre King: his set after the one-bar intro, in its own frame
	Events.boss_engaged.emit(Sim.tick, "enemy.ogre_king")
	await get_tree().process_frame
	assert_eq(str(Audio.music.stingers.back()), "mus.stinger.boss_ogre_king", "the King's intro")
	var king_intro := (load("res://assets/audio/music/stinger_boss_ogre_king.ogg") as AudioStream).get_length()
	assert_near(king_intro, 4.0 * 60.0 / 104.0 + 0.12, 0.02, "one bar at 104 BPM and its ring (%.2f s)" % king_intro)
	Audio.advance_for_tests(king_intro - 0.2, FRAME)
	assert_eq(Audio.music.set_id(), "music.valley_wild", "the zone set holds through the intro")
	Audio.advance_for_tests(0.3, FRAME)
	assert_eq(Audio.music.set_id(), "music.boss_ogre_king", "the King's set after it")
	assert_eq(Audio.music.state_name(), "boss", "the boss state")
	var king: MusicDirector.Deck = Audio.music.deck
	assert_near(king.bar_s, 4.0 * 60.0 / 104.0, 1e-6, "in its own frame at 104 BPM")
	assert_true(Audio.music.deck_position(king) < 0.35, "from the top of its loop (another frame: no alignment)")
	assert_true(Audio.active_ducks().has("boss"), "the fight ducks the ambience")
	Audio.advance_for_tests(0.6, FRAME)
	assert_true(Audio.music.old_decks.is_empty(), "the zone set is out after the 0.5 s crossfade")
	var to_bar := AudioMath.seconds_to_boundary(Audio.music.deck_position(king), king.bar_s, king.loop_s)
	Events.boss_phase_changed.emit(Sim.tick, "enemy.ogre_king", 2)
	await get_tree().process_frame
	to_bar -= FRAME   # the frame the event took
	if to_bar < 0.1:
		to_bar += king.bar_s   # the bar passed during that frame: the next one
	assert_eq(Audio.music.boss_phase, 1, "phase 2 waits for the next bar")
	Audio.advance_for_tests(maxf(to_bar - 0.05, 0.0), FRAME)
	assert_eq(Audio.music.boss_phase, 1, "still phase 1 just before the bar")
	assert_near(float(king.gains.frenzy), 0.0, 1e-6, "the frenzy layer silent")
	Audio.advance_for_tests(0.1, FRAME)
	assert_eq(Audio.music.boss_phase, 2, "phase 2 at the bar")
	Audio.advance_for_tests(1.3, FRAME)
	assert_near(float(king.gains.frenzy), 1.0, 1e-6, "the frenzy layer in after two beats")
	Events.boss_defeated.emit(Sim.tick, "enemy.ogre_king")
	await get_tree().process_frame
	Audio.advance_for_tests(0.2, FRAME)
	assert_eq(str(Audio.music.stingers.back()), "mus.stinger.victory", "the victory stinger")
	assert_eq(Audio.music.state_name(), "zone", "back to the zone")
	assert_eq(Audio.music.set_id(), "music.valley_wild", "and the Old Wood's set")


func test_the_title_the_end_screens_and_the_sandbox_play_their_sets() -> void:
	GameSession.mode = GameSession.Mode.TITLE
	Audio.advance_for_tests(0.3, FRAME)
	assert_eq(Audio.music.context, "title", "the title context")
	assert_eq(Audio.music.set_id(), "music.title", "the title's theme")
	assert_eq(Audio.ambience.set_id, "", "no ambience under the title")
	var title: MusicDirector.Deck = Audio.music.deck
	if title == null:
		return
	assert_eq(title.players.size(), 2, "the horn choir and the stone choir")
	Events.slice_completed.emit(Sim.tick)
	await get_tree().process_frame
	assert_eq(str(Audio.music.stingers.back()), "mus.stinger.prologue_end", "the prologue's end stinger")
	var to_bar := AudioMath.seconds_to_boundary(Audio.music.deck_position(title), title.bar_s, title.loop_s)
	Audio.advance_for_tests(to_bar + 0.3, 0.05)
	assert_eq(Audio.music.context, "end", "the end screen")
	assert_eq(Audio.music.set_id(), "music.end", "its set at the title's next bar")
	assert_near(Audio.music.deck_position(Audio.music.deck), Audio.music.deck_position(title), 1e-3,
		"the theme carries on where the title's was")
	var end_deck: MusicDirector.Deck = Audio.music.deck
	Audio.music.on_campaign_completed()
	Audio.advance_for_tests(0.3, FRAME)
	assert_eq(Audio.music.context, "campaign_end", "the campaign's end")
	to_bar = AudioMath.seconds_to_boundary(Audio.music.deck_position(end_deck), end_deck.bar_s, end_deck.loop_s)
	Audio.advance_for_tests(to_bar + 0.3, 0.05)
	assert_eq(Audio.music.set_id(), "music.campaign_end", "its set from the score's stems at the next bar")
	assert_eq(Audio.music.deck.players.size(), 3, "the horn choir, the stone choir and the brass far under them")
	# the sandbox: the calm set and the meadow without a level record
	Audio.music.reset()
	Audio.music.clock_positions = true
	GameSession.mode = GameSession.Mode.SANDBOX
	var sandbox := Node3D.new()
	sandbox.name = "Sandbox"
	sandbox.add_to_group(AudioDirector.SANDBOX_GROUP)
	world.add_child(sandbox)
	spawn_player(Vector3.ZERO)
	Audio.advance_for_tests(1.0, 0.05)
	assert_eq(Audio.level_id, AudioDirector.SANDBOX_LEVEL, "the sandbox is detected")
	assert_eq(Audio.music.context, "sandbox", "the sandbox context")
	assert_eq(Audio.music.set_id(), "music.valley_calm", "the calm set")
	assert_eq(Audio.ambience.set_id, "ambience.sandbox", "the sandbox's meadow")
	assert_eq(Audio.ambience.bed_cues(), PackedStringArray(["amb.bed_meadow"]), "its bed")
