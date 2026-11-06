extends TestSuite
## P23 (plan M6-M9 §3.5 tests, §4.3, §4.5): every loop the game ships - the score's stems, the
## ambience beds and the two emitters - rendered offline over two periods with
## AudioStreamPlayback.mix_audio at the 44.1 kHz mix rate (no driver, no real time):
##   - the second pass equals the first (within 1e-4, past the resampler's latency): the stream
##     wraps at exactly its frame count, so stems that start together stay together forever;
##   - the wrap is seamless: the step across the seam is no larger than the largest step within
##     46 ms on either side of it (a click at the seam would stand out of its neighbourhood);
##   - neither clipped nor silent;
##   - every music set's stems are aligned to the set's frame: each lasts the set's loop to the
##     frame, carries the frame's name and beat count in the manifest, and every stem of a frame has
##     the same frame count, so the sets of one frame can cross-fade bar for bar;
##   - every zone melody variant is quiet (40 dB under its own level) for 40 ms around each segment
##     boundary, where the melody scheduler switches variants (the 80 ms switch never cuts a note).
## The default suite renders only the shortest loop (test_audio_assets); this tier renders all of
## them, about 6 s.

const MIX_RATE := 44100.0
## Frames skipped at the start of a pass (the resampler's interpolation latency).
const LATENCY_FRAMES := 16
## The seam's neighbourhood on each side, in output frames (46 ms).
const SEAM_WINDOW := 2048
## Half the window around a segment boundary that must be quiet, in seconds.
const BOUNDARY_HALF_S := 0.04
const BOUNDARY_QUIET_DB := -40.0
const MAX_DIFFERENCE := 1e-4


static func render(stream: AudioStream, frames: int) -> PackedVector2Array:
	var pb := stream.instantiate_playback()
	pb.start(0.0)
	var out := PackedVector2Array()
	while out.size() < frames:
		var chunk := pb.mix_audio(1.0, mini(4096, frames - out.size()))
		if chunk.is_empty():
			break
		out.append_array(chunk)
	pb.stop()
	return out


static func step(out: PackedVector2Array, i: int) -> float:
	var a := out[i]
	var b := out[i - 1]
	return maxf(absf(a.x - b.x), absf(a.y - b.y))


## The RMS of out[from, to).
static func window_rms(out: PackedVector2Array, from: int, to: int) -> float:
	var sum := 0.0
	for i in range(from, to):
		sum += out[i].length_squared()
	return sqrt(sum / maxf(1.0, float(to - from)))


## Every loop entry of the manifest, path -> entry.
static func loops() -> Dictionary:
	var out := {}
	var files: Dictionary = AudioMath.manifest().get("files", {})
	for path: String in files:
		if bool((files[path] as Dictionary).get("loop", false)):
			out[path] = files[path]
	return out


func test_every_loop_repeats_exactly_and_wraps_without_a_click() -> void:
	var entries := loops()
	assert_true(entries.size() >= 25, "the score's 19 stems, four beds and two emitters are loops (%d)" % entries.size())
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
		var out := render(s, 2 * period + 64)
		assert_eq(out.size(), 2 * period + 64, "%s renders two periods" % path)
		if out.size() < 2 * period + 64:
			continue
		var worst := 0.0
		var p := 0.0
		for i in range(LATENCY_FRAMES, period):
			var a := out[i]
			var b := out[i + period]
			worst = maxf(worst, maxf(absf(a.x - b.x), absf(a.y - b.y)))
			p = maxf(p, maxf(absf(a.x), absf(a.y)))
		assert_true(worst < MAX_DIFFERENCE, "%s: the second pass equals the first (largest difference %s)" % [
			path, str(worst)])
		assert_true(p < 1.0, "%s does not clip (%.3f)" % [path, p])
		assert_true(p > 0.01, "%s is not silent (%.4f)" % [path, p])
		var seam := 0.0
		for k in range(-1, 2):
			seam = maxf(seam, step(out, period + k))
		var local := 0.0
		for i in range(period - SEAM_WINDOW, period + SEAM_WINDOW):
			if absi(i - period) > 2:
				local = maxf(local, step(out, i))
		assert_true(seam <= local + 1e-6, "%s wraps without a click (step %.5f at the seam, %.5f around it)" % [
			path, seam, local])


func test_every_sets_stems_are_aligned_to_its_frame() -> void:
	var sets := GameData.records_of_type("music_set")
	assert_true(sets.size() >= 6, "the title, end, three zone sets and the Ogre King's (%d)" % sets.size())
	var frames_of := {}   # frame name -> frame count of its stems
	for rec: Dictionary in sets:
		var beats := int(rec.beats_per_bar) * int(rec.bars)
		var want_s := AudioMath.loop_seconds(float(rec.bpm), int(rec.beats_per_bar), int(rec.bars))
		for stem: String in rec.stems:
			var path := str(rec.stems[stem])
			var e := AudioMath.manifest_entry(path)
			assert_true(bool(e.get("loop", false)), "%s %s is a loop" % [rec.id, stem])
			assert_eq(str(e.get("frame", "")), str(rec.get("frame", "")), "%s %s is written in the set's frame" % [
				rec.id, stem])
			assert_eq(int(e.get("beats", 0)), beats, "%s %s lasts the set's %d beats" % [rec.id, stem, beats])
			var rate := float(e.get("rate", 22050))
			assert_eq(int(e.get("frames", 0)), int(round(want_s * rate)), "%s %s lasts the loop to the frame" % [
				rec.id, stem])
			var frame := str(e.get("frame", ""))
			if frames_of.has(frame):
				assert_eq(int(e.frames), int(frames_of[frame]), "%s %s matches the other stems of %s" % [
					rec.id, stem, frame])
			else:
				frames_of[frame] = int(e.get("frames", 0))
	assert_true(frames_of.has("zone_96") and frames_of.has("boss_104"), "the zone frame and the King's frame")
	assert_eq(int(frames_of.get("zone_96", 0)), 661500, "the zone frame: twelve bars at 96 BPM, 30 s at 22.05 kHz")
	assert_eq(int(frames_of.get("boss_104", 0)), 610615, "the King's frame: twelve bars at 104 BPM, 27.69 s")


func test_melody_variants_are_quiet_at_their_segment_boundaries() -> void:
	var checked := 0
	for rec: Dictionary in GameData.records_of_type("music_set"):
		var melody: Dictionary = rec.get("melody", {})
		if melody.is_empty():
			continue
		var bar_s := 60.0 / float(rec.bpm) * float(rec.beats_per_bar)
		var segment_s := bar_s * float(melody.get("segment_bars", 4))
		var loop_s := AudioMath.loop_seconds(float(rec.bpm), int(rec.beats_per_bar), int(rec.bars))
		for variant: String in melody.variants:
			var path := str(rec.stems[variant])
			var s := load(path) as AudioStreamOggVorbis
			s.loop = true
			var period := int(round(loop_s * MIX_RATE))
			var out := render(s, period + int(BOUNDARY_HALF_S * MIX_RATE) + 64)
			var level := window_rms(out, LATENCY_FRAMES, period)
			assert_true(level > 0.01, "%s plays" % path)
			var half := int(BOUNDARY_HALF_S * MIX_RATE)
			var t := segment_s
			while t <= loop_s + 1e-6:
				var at := int(round(t * MIX_RATE))
				var quiet := window_rms(out, at - half, at + half)
				var db := 20.0 * log(maxf(quiet, 1e-9) / level) / log(10.0)
				assert_true(db <= BOUNDARY_QUIET_DB, "%s is quiet at %.1f s, a segment boundary (%.1f dB)" % [path, t, db])
				checked += 1
				t += segment_s
	assert_true(checked >= 27, "three variants of three zone sets, three boundaries each (%d)" % checked)
