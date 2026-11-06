extends TestSuite
## P28 (plan M6-M9 §3.11 tests, §4.3, §4.5): the world's loops - the five regions' drones, their
## fifteen melody variants and Aldmere's snare, the three bosses' stems in their own frames, the
## region and place beds, the emitter loops and the formations' march - rendered offline with
## AudioStreamPlayback.mix_audio at the 44.1 kHz mix rate (no driver, no real time), one period and
## TAIL_S past the wrap:
##   - the pass after the wrap repeats the loop's start (within 1e-4, past the resampler's
##     latency): the stream wraps at exactly its frame count, so a set's stems stay together;
##   - the wrap is seamless: the step across the seam is no larger than the largest step within
##     46 ms on either side of it;
##   - neither clipped nor silent;
##   - the zone sets' stems are in the Valley's zone frame (twelve bars at 96 BPM, 661,500 frames,
##     sharing its danger and combat stems), each boss set's in its own (the Iron Regiment's 112 BPM,
##     the Matriarch's 6/8 at 84, Harrok's 72 BPM);
##   - every world melody variant is quiet (40 dB under its own level) for 40 ms around each
##     segment boundary, where the melody scheduler switches variants.
## P23's suite (test_music_loops) renders the M6 loops; this one the world's (manifest scope
## "world").

const LOOPS := preload("res://tests/slow/test_music_loops.gd")
const MIX_RATE := 44100.0
## Seconds rendered past the wrap and compared with the loop's start.
const TAIL_S := 2.0
## The peak is read every this many frames (the build normalised every file; this guards the import).
const PEAK_STRIDE := 4
const ZONE_FRAMES := 661500
const BOSS_FRAMES := {"music.boss_regiment": 567000, "music.boss_matriarch": 504000, "music.boss_harrok": 588000}
const SHARED := ["pulse", "drums", "brass"]


## Every world loop of the manifest, path -> entry.
static func world_loops() -> Dictionary:
	var out := {}
	var files: Dictionary = AudioMath.manifest().get("files", {})
	for path: String in files:
		var e: Dictionary = files[path]
		if bool(e.get("loop", false)) and str(e.get("scope", "")) == "world":
			out[path] = e
	return out


## The world's melody variants: path -> the set's segment seconds.
static func melody_variants() -> Dictionary:
	var out := {}
	for rec: Dictionary in GameData.records_of_type("music_set"):
		var melody: Dictionary = rec.get("melody", {})
		if melody.is_empty():
			continue
		var bar_s := 60.0 / float(rec.bpm) * float(rec.beats_per_bar)
		for variant: String in melody.variants:
			var path := str(rec.stems[variant])
			if path.contains("/world/"):
				out[path] = bar_s * float(melody.get("segment_bars", 4))
	return out


func test_every_world_loop_repeats_and_wraps_without_a_click() -> void:
	var entries := world_loops()
	assert_true(entries.size() >= 46, "31 stems, eleven beds and five loops (%d)" % entries.size())
	var variants := melody_variants()
	assert_eq(variants.size(), 15, "five regions' three melody variants")
	var boundaries := 0
	for path: String in entries:
		var e: Dictionary = entries[path]
		var s := load(path) as AudioStreamOggVorbis
		assert_true(s != null, "%s loads" % path)
		if s == null:
			continue
		s.loop = true
		var seconds := float(e.frames) / float(e.rate)
		assert_near(s.get_length(), seconds, 1.0 / float(e.rate), "%s lasts its frames" % path)
		var period := int(round(seconds * MIX_RATE))
		var tail := int(TAIL_S * MIX_RATE)
		var out := LOOPS.render(s, period + tail + 64)
		assert_eq(out.size(), period + tail + 64, "%s renders a period and its wrap" % path)
		if out.size() < period + tail + 64:
			continue
		var worst := 0.0
		for i in range(LOOPS.LATENCY_FRAMES, tail):
			var a := out[i]
			var b := out[i + period]
			worst = maxf(worst, maxf(absf(a.x - b.x), absf(a.y - b.y)))
		assert_true(worst < LOOPS.MAX_DIFFERENCE, "%s: past the wrap it repeats its start (largest difference %s)" % [
			path, str(worst)])
		var p := 0.0
		for i in range(LOOPS.LATENCY_FRAMES, period, PEAK_STRIDE):
			var a := out[i]
			p = maxf(p, maxf(absf(a.x), absf(a.y)))
		assert_true(p < 1.0, "%s does not clip (%.3f)" % [path, p])
		assert_true(p > 0.01, "%s is not silent (%.4f)" % [path, p])
		var seam := 0.0
		for k in range(-1, 2):
			seam = maxf(seam, LOOPS.step(out, period + k))
		var local := 0.0
		for i in range(period - LOOPS.SEAM_WINDOW, period + LOOPS.SEAM_WINDOW):
			if absi(i - period) > 2:
				local = maxf(local, LOOPS.step(out, i))
		assert_true(seam <= local + 1e-6, "%s wraps without a click (step %.5f at the seam, %.5f around it)" % [
			path, seam, local])
		if variants.has(path):
			var segment_s := float(variants[path])
			var level := LOOPS.window_rms(out, LOOPS.LATENCY_FRAMES, period)
			assert_true(level > 0.01, "%s plays" % path)
			var half := int(LOOPS.BOUNDARY_HALF_S * MIX_RATE)
			var t := segment_s
			while t <= seconds + 1e-6:
				var at := int(round(t * MIX_RATE))
				var quiet := LOOPS.window_rms(out, at - half, at + half)
				var db := 20.0 * log(maxf(quiet, 1e-9) / level) / log(10.0)
				assert_true(db <= LOOPS.BOUNDARY_QUIET_DB, "%s is quiet at %.1f s, a segment boundary (%.1f dB)" % [
					path, t, db])
				boundaries += 1
				t += segment_s
	assert_true(boundaries >= 45, "fifteen variants, three boundaries each (%d)" % boundaries)


func test_the_world_sets_are_in_their_frames() -> void:
	var zone := 0
	for rec: Dictionary in GameData.records_of_type("music_set"):
		var id := str(rec.id)
		var world_stems := 0
		for stem: String in rec.stems:
			var path := str(rec.stems[stem])
			if not path.contains("/world/"):
				continue
			world_stems += 1
			var e := AudioMath.manifest_entry(path)
			assert_eq(str(e.get("scope", "")), "world", "%s %s is the world's" % [id, stem])
			assert_eq(str(e.get("frame", "")), str(rec.frame), "%s %s is in the set's frame" % [id, stem])
			var want := int(BOSS_FRAMES.get(id, ZONE_FRAMES))
			assert_eq(int(e.get("frames", 0)), want, "%s %s lasts its frame's %d frames" % [id, stem, want])
		if world_stems == 0:
			continue
		if BOSS_FRAMES.has(id):
			assert_eq(world_stems, (rec.stems as Dictionary).size(), "%s shares no stem" % id)
			assert_false(str(rec.frame) == "zone_96", "%s has its own frame" % id)
			continue
		zone += 1
		assert_eq(str(rec.frame), "zone_96", "%s is in the zone frame" % id)
		for stem: String in SHARED:
			assert_true(str(rec.stems.get(stem, "")).begins_with("res://assets/audio/music/") \
				and not str(rec.stems.get(stem, "")).contains("/world/"), "%s shares the Valley's %s" % [id, stem])
	assert_eq(zone, 5, "the five regions' sets")
