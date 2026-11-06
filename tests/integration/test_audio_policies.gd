extends TestSuite
## P19 (plan M6-M9 decisions 1-3, §3.1 policy tests): the playback policy holds in the code and at
## run time - no PLAYBACK_TYPE_SAMPLE, AudioStreamRandomizer, AudioStreamPolyphonic,
## AudioStreamPlaylist (nor the interactive and synchronized streams decision 5 leaves out) in
## scripts/ or ui/; every Music and Ambience player, the spot voices included, plays as a STREAM;
## the audio scripts never draw from the global RNG or Sim.rng; loops are Ogg; the web output
## latency is 200 ms; the buses carry no effects.

const CODE_DIRS := ["res://scripts", "res://ui"]
const FORBIDDEN := ["PLAYBACK_TYPE_SAMPLE", "AudioStreamRandomizer", "AudioStreamPolyphonic", "AudioStreamPlaylist",
	"AudioStreamInteractive", "AudioStreamSynchronized"]
const AUDIO_DIR := "res://scripts/audio"
const Fx := preload("res://tests/support/test_fixtures.gd")


func after_each() -> void:
	Audio.enable_for_tests(false)


static func _gd_files(dir_path: String) -> PackedStringArray:
	var out := PackedStringArray()
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return out
	for f in dir.get_files():
		if f.ends_with(".gd"):
			out.append(dir_path.path_join(f))
	for d in dir.get_directories():
		out.append_array(_gd_files(dir_path.path_join(d)))
	return out


## The code of a line without its comment (a "#" outside a string ends the code).
static func code_of(line: String) -> String:
	var in_str := false
	var quote := ""
	for i in line.length():
		var c := line[i]
		if in_str:
			if c == "\\":
				continue
			if c == quote:
				in_str = false
		elif c == "\"" or c == "'":
			in_str = true
			quote = c
		elif c == "#":
			return line.substr(0, i)
	return line


func test_no_forbidden_stream_types_or_playback_modes_in_code() -> void:
	var files := PackedStringArray()
	for d: String in CODE_DIRS:
		files.append_array(_gd_files(d))
	assert_true(files.size() > 50, "the code is scanned (%d files)" % files.size())
	var offenders := PackedStringArray()
	for path in files:
		var n := 0
		for line in FileAccess.get_file_as_string(path).split("\n"):
			n += 1
			for word: String in FORBIDDEN:
				if line.contains(word) and code_of(line).contains(word):
					offenders.append("%s:%d %s" % [path, n, word])
	assert_eq(offenders, PackedStringArray(), "decision 2: samples only by default, no randomizer, polyphonic or playlist streams")


func test_the_audio_scripts_never_use_the_global_or_simulation_rng() -> void:
	var re := RegEx.create_from_string("(?<![\\w.])(randf|randi|randf_range|randi_range|randfn|seed|randomize)\\s*\\(")
	var offenders := PackedStringArray()
	var files := _gd_files(AUDIO_DIR)
	assert_true(files.size() >= 7, "every audio script is scanned")
	for path in files:
		var n := 0
		for line in FileAccess.get_file_as_string(path).split("\n"):
			n += 1
			if re.search(line) == null and not line.contains("Sim.rng"):
				continue
			var code := code_of(line)
			if re.search(code) != null or code.contains("Sim.rng"):
				offenders.append("%s:%d %s" % [path, n, code.strip_edges()])
	assert_eq(offenders, PackedStringArray(), "decision 1: audio owns private RandomNumberGenerators")


func test_project_settings_and_formats() -> void:
	assert_eq(int(ProjectSettings.get_setting("audio/driver/output_latency.web", 0)), 200,
		"the web output latency survives 120 ms main-thread stalls (brief §5.3)")
	var autoloads: Array = []
	for p in ProjectSettings.get_property_list():
		var key := str(p.name)
		if key.begins_with("autoload/"):
			autoloads.append(key.trim_prefix("autoload/"))
	assert_eq(str(autoloads.back()) if not autoloads.is_empty() else "", "Audio", "Audio is the last autoload")
	var manifest := AudioMath.manifest()
	for path: String in manifest.get("files", {}):
		var e: Dictionary = manifest.files[path]
		if bool(e.get("loop", false)):
			assert_true(path.ends_with(".ogg"), "%s: loops are always Ogg" % path)
		if str(e.kind) == "sfx":
			assert_true(path.ends_with(".wav") and float(e.seconds) <= 2.0, "%s: effects are WAVs of at most 2 s" % path)


func test_every_music_and_ambience_player_is_a_stream() -> void:
	Audio.enable_for_tests()
	# P23's title music (two stems) with the meadow's bed under it (the shipped title has no bed)
	Fx.record_override("audio_region.context_title", {"ambience": "ambience.meadow"})
	Audio.reload_catalog()
	Audio.music.clock_positions = true
	GameSession.mode = GameSession.Mode.TITLE
	Audio.advance_for_tests(0.6)
	Audio.music.play_stinger("mus.stinger.quest", 50)
	var players := _players(Audio)
	var checked := 0
	for p: Node in players:
		var bus := str(p.get("bus"))
		if bus == "Music" or bus == "Ambience":
			checked += 1
			assert_eq(int(p.get("playback_type")), AudioServer.PLAYBACK_TYPE_STREAM, "%s on %s is a stream" % [p.name, bus])
		else:
			assert_eq(int(p.get("playback_type")), AudioServer.PLAYBACK_TYPE_DEFAULT,
				"%s on %s keeps the default (samples on the web)" % [p.name, bus])
	assert_true(checked >= 6, "stems, the stinger, a bed and the two spot voices were checked (%d)" % checked)
	assert_eq(Audio.pool.spot_voices.size(), 2, "two spot voices")
	for v: AudioStreamPlayer3D in Audio.pool.spot_voices:
		assert_eq(v.playback_type, AudioServer.PLAYBACK_TYPE_STREAM, "spot voices are streams")
		assert_eq(str(v.bus), "Ambience", "on the Ambience bus")
	for bus: String in AudioDirector.BUSES:
		var idx := AudioServer.get_bus_index(bus)
		assert_true(idx > 0, "%s exists" % bus)
		assert_eq(AudioServer.get_bus_effect_count(idx), 0, "%s has no effects (decision 3)" % bus)
	GameSession.mode = GameSession.Mode.SANDBOX


static func _players(root: Node) -> Array:
	var out: Array = []
	for c in root.get_children():
		if c is AudioStreamPlayer or c is AudioStreamPlayer3D:
			out.append(c)
		out.append_array(_players(c))
	return out
