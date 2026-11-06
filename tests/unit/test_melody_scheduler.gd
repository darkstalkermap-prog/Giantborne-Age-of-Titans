extends TestSuite
## P19 (plan M6-M9 decision 5, §2.5, §4.3): the melody scheduler - one or two played loops then
## one to three rested ones, a variant or a rest per four-bar segment, no variant more than twice
## in a row, no identical phrase within 60 s, and after three minutes of uneventful exploration a
## silence window that a discovery ends (drone first, the melody one loop later).

const LOOP_S := 30.0
const SEGMENTS := 3
const MELODY := {"variants": ["melody_a", "melody_b", "melody_c"], "segment_bars": 4, "play_loops": [1, 2],
	"rest_loops": [1, 3], "max_repeat": 2, "min_phrase_gap_s": 60}
const SILENCE := {"after_explore_s": 180, "length_s": [60, 120], "fade_s": 8}


func _scheduler(seed_value: int, silence := {}) -> MelodyScheduler:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var s := MelodyScheduler.new()
	s.configure(MELODY, silence, SEGMENTS, rng, 0.0)
	return s


## Drives `loops` loops (three segments each): [{"t", "loop", "segment", "choice", "playing"}],
## "playing" being the block the loop belongs to (read after its first segment).
func _run(s: MelodyScheduler, loops: int, start_s := 0.0) -> Array:
	var out: Array = []
	for loop in loops:
		var block := true
		for seg in SEGMENTS:
			var t := start_s + loop * LOOP_S + seg * (LOOP_S / SEGMENTS)
			var c := s.next_segment(t, seg)
			if seg == 0:
				block = s.playing
			out.append({"t": t, "loop": loop, "segment": seg, "choice": c, "playing": block})
	return out


func test_variants_repeat_at_most_twice_and_phrases_keep_60_s_apart() -> void:
	for seed_value in [1, 2, 3, 4, 5]:
		var choices := _run(_scheduler(seed_value), 60)
		var run_len := 0
		var last := ""
		var worst_run := 0
		var phrase_seen := {}
		var closest_gap := INF
		var variants_used := {}
		for c: Dictionary in choices:
			var v := str(c.choice)
			if v == "":
				run_len = 0
				last = ""
				continue
			variants_used[v] = true
			run_len = run_len + 1 if v == last else 1
			last = v
			worst_run = maxi(worst_run, run_len)
			var key := "%s:%d" % [v, c.segment]
			if phrase_seen.has(key):
				closest_gap = minf(closest_gap, float(c.t) - float(phrase_seen[key]))
			phrase_seen[key] = c.t
		assert_true(worst_run <= 2, "seed %d: no variant more than twice in a row (%d)" % [seed_value, worst_run])
		assert_true(closest_gap >= 60.0 - 1e-6, "seed %d: identical phrases at least 60 s apart (%.1f)" % [
			seed_value, closest_gap])
		assert_eq(variants_used.size(), 3, "seed %d: every variant plays" % seed_value)


func test_one_or_two_played_loops_then_one_to_three_rested() -> void:
	for seed_value in [11, 12, 13, 14]:
		var choices := _run(_scheduler(seed_value), 40)
		var blocks: Array = []   # [playing, loops] per block
		for loop in 40:
			var playing: bool = choices[loop * SEGMENTS].playing
			if blocks.is_empty() or bool(blocks[-1][0]) != playing:
				blocks.append([playing, 1])
			else:
				blocks[-1][1] += 1
			if not playing:
				for seg in SEGMENTS:
					assert_eq(str(choices[loop * SEGMENTS + seg].choice), "", "seed %d: a rested loop has no melody" % seed_value)
		assert_true(bool(blocks[0][0]) and int(blocks[0][1]) <= 2, "seed %d: it starts with one or two played loops" % seed_value)
		assert_true(blocks.size() >= 2 and not bool(blocks[1][0]), "seed %d: a rest within three loops" % seed_value)
		for i in blocks.size() - 1:   # the last block may be cut short by the run's end
			var b: Array = blocks[i]
			if bool(b[0]):
				assert_true(int(b[1]) >= 1 and int(b[1]) <= 2, "seed %d: played blocks of 1-2 loops (%d)" % [seed_value, b[1]])
			else:
				assert_true(int(b[1]) >= 1 and int(b[1]) <= 3, "seed %d: rested blocks of 1-3 loops (%d)" % [seed_value, b[1]])


func test_rest_weight_rests_some_segments_of_played_loops() -> void:
	var rested := 0
	var played := 0
	for seed_value in range(20, 30):
		for c: Dictionary in _run(_scheduler(seed_value), 20):
			if bool(c.playing):
				played += 1
				if str(c.choice) == "":
					rested += 1
	var share := float(rested) / maxf(float(played), 1.0)
	assert_true(share > 0.05 and share < 0.45, "about 15 %% of played segments rest (with the repeat and gap rules: %.2f)" % share)


func test_silence_window_after_three_minutes_and_its_reentry() -> void:
	var s := _scheduler(5, SILENCE)
	var started := false
	for i in 180:
		started = s.update(float(i), true) or started
	assert_false(started, "no silence before 180 s of uneventful exploration")
	assert_false(s.silent, "still music")
	assert_true(s.update(180.0, true), "silence starts at 180 s")
	assert_true(s.silent, "silent")
	assert_true(s.silence_ends_s >= 240.0 and s.silence_ends_s <= 300.0, "for 60 to 120 s (%.1f)" % s.silence_ends_s)
	assert_eq(s.next_segment(185.0, 0), "", "no melody in the silence")
	assert_false(s.wants_reentry(), "no re-entry without a reason")
	s.note_event(200.0)
	assert_true(s.wants_reentry(), "a discovery during the silence asks to re-enter")
	s.reenter(202.5, true)
	assert_false(s.silent, "the music is back")
	var first_loop := PackedStringArray()
	for seg in SEGMENTS:
		first_loop.append(s.next_segment(210.0 + seg * 10.0, seg))
	assert_eq(first_loop, PackedStringArray(["", "", ""]), "the drone first: the melody rests one loop")
	s.next_segment(240.0, 0)
	assert_true(s.playing, "the melody's block starts the loop after")


func test_silence_ends_by_itself_and_danger_postpones_it() -> void:
	var s := _scheduler(6, SILENCE)
	for i in 100:
		s.update(float(i), true)
	s.update(100.0, false)   # danger: exploration is eventful again
	for i in range(101, 280):
		s.update(float(i), true)
	assert_false(s.silent, "danger at 100 s postponed the silence to 280 s")
	assert_true(s.update(280.0, true), "silence at 280 s")
	s.update(s.silence_ends_s + 0.1, true)
	assert_true(s.wants_reentry(), "the silence ends after its length")


func test_without_a_silence_block_the_music_never_falls_silent() -> void:
	var s := _scheduler(7)
	var ever := false
	for i in 600:
		ever = s.update(float(i), true) or ever
	assert_false(ever, "no silence configured: never asked")
	assert_false(s.silent, "never silent")
