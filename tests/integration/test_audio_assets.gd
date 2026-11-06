extends TestSuite
## P19 (plan M6-M9 §3.1 asset tests, §4.5, decision 8): the generated audio, checked offline with
## AudioStreamPlayback.mix_audio (no driver, no real time): every file a bank or a set names
## loads; effects are samplable, at most 2.0 s, neither clipped nor silent; loops repeat with an
## exact period (the second pass equals the first within 1e-4; here the shortest loop, every loop in
## tests/slow/test_music_loops.gd since P23's score); music stems last their set's loop to the
## frame; the manifest matches the files; the size budget holds (Ogg sizes x 1.03 and the exact QOA
## formula for WAVs) and the registered seconds per level hold.

const MIX_RATE := 44100.0
const SFX_MAX_S := 2.0
const BUDGET_M6_BYTES := 4.0 * 1024.0 * 1024.0
const BUDGET_ALL_BYTES := 9.5 * 1024.0 * 1024.0
const REGISTERED_CAP_S := {"level.valley": 110.0, "level.world": 170.0}
const QOA_IMPORT_BYTES := 370
const OGG_IMPORT_FACTOR := 1.03
## Frames skipped at the start of a pass (the resampler's interpolation latency, brief §3).
const LATENCY_FRAMES := 16

## P23: the streams this suite loaded, kept for its later tests (each file loads once per run).
var _loaded := {}


func _load(path: String) -> AudioStream:
	if not _loaded.has(path):
		_loaded[path] = load(path)
	return _loaded[path] as AudioStream


## Renders `seconds` of `stream` offline at the mix rate.
static func render(stream: AudioStream, seconds: float) -> PackedVector2Array:
	var pb := stream.instantiate_playback()
	pb.start(0.0)
	var out := PackedVector2Array()
	var total := int(seconds * MIX_RATE)
	while out.size() < total:
		var chunk := pb.mix_audio(1.0, mini(4096, total - out.size()))
		if chunk.is_empty():
			break   # a one-shot ended (mix_audio may return fewer frames than asked)
		out.append_array(chunk)
	pb.stop()
	return out


static func peak(frames: PackedVector2Array) -> float:
	var p := 0.0
	for f in frames:
		p = maxf(p, maxf(absf(f.x), absf(f.y)))
	return p


## Every audio file the data names: bank cue files, set stems.
func _referenced_files() -> Dictionary:
	var out := {}
	for bank: Dictionary in GameData.records_of_type("audio_bank"):
		for cue_id: String in bank.cues:
			for f: Variant in (bank.cues[cue_id] as Dictionary).get("files", []):
				out[str(f)] = "%s %s" % [bank.id, cue_id]
	for rec: Dictionary in GameData.records_of_type("music_set"):
		for stem: String in rec.get("stems", {}):
			out[str(rec.stems[stem])] = "%s %s" % [rec.id, stem]
	return out


func test_every_referenced_file_loads() -> void:
	var files := _referenced_files()
	assert_true(files.size() >= 250, "the banks and sets name their files (%d)" % files.size())
	for path: String in files:
		var s := _load(path)
		assert_true(s != null, "%s loads (%s)" % [path, files[path]])
		if path.ends_with(".wav"):
			assert_true(s is AudioStreamWAV, "%s is a WAV sample" % path)
		else:
			assert_true(s is AudioStreamOggVorbis, "%s is an Ogg stream" % path)


func test_effects_are_samplable_short_and_neither_clipped_nor_silent() -> void:
	var n := 0
	for path: String in _referenced_files():
		if not path.ends_with(".wav"):
			continue
		n += 1
		var s := _load(path) as AudioStreamWAV
		assert_true(s.can_be_sampled(), "%s can be a web sample" % path)
		assert_true(s.get_length() <= SFX_MAX_S + 1e-6, "%s is at most 2.0 s (%.3f)" % [path, s.get_length()])
		assert_eq(s.loop_mode, AudioStreamWAV.LOOP_DISABLED, "%s is a one-shot" % path)
		var p := peak(render(s, s.get_length()))
		assert_true(p < 1.0, "%s does not clip (%.3f)" % [path, p])
		assert_true(p > 0.001, "%s is not silent (%.4f)" % [path, p])
	assert_true(n >= 200, "every effect checked (%d)" % n)


## Whether `out` (two passes of a loop of `period` output frames, from the start) repeats exactly:
## [the largest difference between the passes past the resampler's latency, the first pass's peak].
static func pass_difference(out: PackedVector2Array, period: int) -> Vector2:
	var worst := 0.0
	var p := 0.0
	for i in range(LATENCY_FRAMES, period):
		var a := out[i]
		var b := out[i + period]
		worst = maxf(worst, maxf(absf(a.x - b.x), absf(a.y - b.y)))
		p = maxf(p, maxf(absf(a.x), absf(a.y)))
	return Vector2(worst, p)


## The loop entries of the manifest, shortest first (path order between equals).
static func loop_paths() -> PackedStringArray:
	var files: Dictionary = AudioMath.manifest().get("files", {})
	var paths: Array = []
	for path: String in files:
		if bool((files[path] as Dictionary).get("loop", false)):
			paths.append(path)
	paths.sort_custom(func(a: String, b: String) -> bool:
		var fa := int(files[a].frames) / float(files[a].rate)
		var fb := int(files[b].frames) / float(files[b].rate)
		return fa < fb if not is_equal_approx(fa, fb) else a < b)
	return PackedStringArray(paths)


## P23: the default suite renders the shortest loop over two periods (a 10 s emitter); the slow tier
## (tests/slow/test_music_loops.gd) renders every loop and stem the same way, about 8 s.
func test_loops_repeat_with_an_exact_period() -> void:
	var manifest := AudioMath.manifest()
	var paths := loop_paths()
	assert_true(paths.size() >= 25, "the score's stems, beds and emitters are loops (%d)" % paths.size())
	var path := paths[0]
	var e: Dictionary = manifest.files[path]
	var s := _load(path) as AudioStreamOggVorbis
	s.loop = true
	var period := int(round(float(e.frames) / float(e.rate) * MIX_RATE))
	assert_near(s.get_length(), float(e.frames) / float(e.rate), 1.0 / float(e.rate), "%s lasts its frames" % path)
	var out := render(s, 2.0 * period / MIX_RATE + 0.05)
	var d := pass_difference(out, period)
	assert_true(d.x < 1e-4, "%s: the second pass equals the first (largest difference %s)" % [path, str(d.x)])
	assert_true(d.y < 1.0 and d.y > 0.01, "%s is neither clipped nor silent (%.3f)" % [path, d.y])


func test_one_shot_oggs_end() -> void:
	var manifest := AudioMath.manifest()
	for path: String in manifest.get("files", {}):
		var e: Dictionary = manifest.files[path]
		if str(e.kind) != "oneshot":
			continue
		var s := _load(path) as AudioStreamOggVorbis
		s.loop = false
		assert_near(s.get_length(), float(e.seconds), 0.01, "%s lasts its seconds" % path)


func test_stems_last_their_sets_loop_to_the_frame() -> void:
	var sets := GameData.records_of_type("music_set")
	for rec: Dictionary in sets:
		var want := AudioMath.loop_seconds(float(rec.bpm), int(rec.beats_per_bar), int(rec.bars))
		for stem: String in rec.stems:
			var s := _load(str(rec.stems[stem]))
			var e := AudioMath.manifest_entry(str(rec.stems[stem]))
			var rate := float(e.get("rate", 22050))
			assert_near(s.get_length(), want, 1.0 / rate, "%s %s lasts the loop to the frame" % [rec.id, stem])
	assert_true(sets.size() >= 6, "P23's sets ship (title, end, three zone sets, the Ogre King)")
	# the zone frame's drone is 12 bars at 96 BPM exactly, the King's frame 12 bars at 104 BPM
	var drone := _load("res://assets/audio/music/drone_calm.ogg")
	assert_near(drone.get_length(), AudioMath.loop_seconds(96.0, 4, 12), 1.0 / 22050.0, "the drone is 12 bars at 96 BPM")
	var e := AudioMath.manifest_entry("res://assets/audio/music/drone_calm.ogg")
	assert_eq(str(e.get("frame", "")), "zone_96", "its frame is recorded")
	assert_eq(int(e.get("beats", 0)), 48, "48 beats")
	var boss := AudioMath.manifest_entry("res://assets/audio/music/boss_drums.ogg")
	assert_eq(str(boss.get("frame", "")), "boss_104", "the King's stems have their own frame")


func test_the_manifest_matches_the_files() -> void:
	var manifest := AudioMath.manifest()
	var files: Dictionary = manifest.get("files", {})
	assert_true(files.size() >= 9, "every generated file is listed")
	for key: String in ["python", "numpy", "ffmpeg", "libvorbis"]:
		assert_true(str((manifest.get("tools", {}) as Dictionary).get(key, "")) != "", "the %s version is recorded" % key)
	for path: String in files:
		var e: Dictionary = files[path]
		assert_true(FileAccess.file_exists(path), "%s exists" % path)
		var bytes := FileAccess.get_file_as_bytes(path)
		assert_eq(bytes.size(), int(e.size), "%s has the recorded size" % path)
		var hc := HashingContext.new()
		hc.start(HashingContext.HASH_SHA256)
		hc.update(bytes)
		assert_eq(hc.finish().hex_encode(), str(e.file_hash), "%s has the recorded hash" % path)
		for key: String in ["family", "generator", "function", "seed", "params_hash", "frames", "rate", "channels",
				"master_hash", "kind"]:
			assert_true(e.has(key), "%s records %s" % [path, key])
	var listed := {}
	for path: String in files:
		listed[path] = true
	for path: String in _referenced_files():
		assert_true(listed.has(path), "%s was generated (it is in the manifest)" % path)


## The imported size of one manifest entry (plan §4.5): the exact QOA formula plus 370 bytes for a
## WAV, the Ogg file x 1.03.
static func imported_bytes(e: Dictionary) -> float:
	if str(e.kind) == "sfx":
		var frames := int(e.frames)
		var per := 8 + 24 * ceili(frames / 5120.0) + 8 * ceili(frames / 20.0)
		return float(int(e.channels) * per + QOA_IMPORT_BYTES)
	return float(e.size) * OGG_IMPORT_FACTOR


func test_size_budget_and_registered_seconds_hold() -> void:
	var files: Dictionary = AudioMath.manifest().get("files", {})
	var m6 := 0.0
	var all := 0.0
	for path: String in files:
		var b := imported_bytes(files[path])
		all += b
		if str((files[path] as Dictionary).get("scope", "m6")) == "m6":
			m6 += b
	assert_true(m6 <= BUDGET_M6_BYTES, "M6 audio within 4.0 MB (%.3f MB)" % (m6 / 1048576.0))
	assert_true(all <= BUDGET_ALL_BYTES, "all audio within 9.5 MB (%.3f MB)" % (all / 1048576.0))
	assert_eq(imported_bytes({"kind": "sfx", "frames": 4410, "channels": 1}), float(8 + 24 + 8 * 221 + 370),
		"the QOA arithmetic")
	for level: String in REGISTERED_CAP_S:
		var seconds := 0.0
		for path in Audio.sample_paths_for(level):
			seconds += float(AudioMath.manifest_entry(path).get("seconds", 0.0))
		assert_true(seconds <= float(REGISTERED_CAP_S[level]), "%s registers %.1f s of samples (cap %.0f s)" % [
			level, seconds, REGISTERED_CAP_S[level]])
		assert_true(seconds > 0.0, "%s registers the global cues" % level)
