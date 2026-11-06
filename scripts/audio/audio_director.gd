class_name AudioDirector
extends Node
## The audio engine (autoload "Audio", last in the autoload order; P19, plan M6-M9 §2.5 and
## decisions 1-8). Presentation only: it listens to Events (CueRouter) and to rig footfalls, reads
## state in _process, and never emits a gameplay signal, never spends or changes anything, never
## reads `finished` into game logic and never touches Sim.rng or the global RNG (its children own
## private RandomNumberGenerators). A gate test runs the seeded soak with audio on and off and
## compares the two AUTOPILOT_RESULT lines byte for byte.
##
## Children: Pool (VoicePool: 3D, spot and 2D voices), Music (MusicDirector, PROCESS_MODE_ALWAYS),
## Ambience (AmbienceDirector, PROCESS_MODE_PAUSABLE), Router (CueRouter: Events -> queued cue
## requests, drained here in _process) and Listener (an AudioListener3D at the giant's chest -
## camera_pivot_height x 0.8 - turned with the camera's yaw and pitch).
##
## Startup: --no-audio (the default test suite) leaves it disabled: no listeners, no players,
## nothing plays, is_ready() is true. Enabled, it makes the buses (Music, Ambience, SFX, UI, sending
## to Master, no effects; decision 3), builds the pool from audio_mix.default, loads the cue
## catalogue from every audio_bank record, connects the router and wires footfalls through
## get_tree().node_added. The loading gate: when a level appears (a node of group level_root, or
## the sandbox) it registers that level's SFX samples (AudioServer.register_stream_as_sample: global
## cues first, then the cues whose `levels` name the level) in slices of at most
## register_ms_per_frame while scripts/main.gd keeps the tree paused behind "Loading..."; is_ready()
## is false until every one is registered, so no play() ever registers (decision 2). On desktop the
## registration is a no-op and the slices only load the streams.
##
## Focus: on NOTIFICATION_APPLICATION_FOCUS_OUT and NOTIFICATION_WM_WINDOW_FOCUS_OUT, with
## Settings mute_when_unfocused, Master ramps to -80 dB in 0.2 s (back on focus in); on the web a
## visibilitychange callback mutes Master while the page is hidden. Pause: the SFX and ambience
## players pause with the tree; the music ducks (audio_mix.duck.pause) while a pausing screen is
## open. Settings: volume_master / music / ambience / sfx / ui (0..1, on top of the mix's bus
## levels; 0 mutes).
##
## Tests: enable_for_tests(), cue_log() (deterministic: the frame, tick, cue, bus, position, voice,
## priority and reason of every cue started), reset_for_tests() (ResetHooks.BEFORE_EACH first: stop
## all, clear the log and the queues, reset the directors, back to the process's enabled state).

const BUSES := ["Music", "Ambience", "SFX", "UI"]
const REFERENCE_HEIGHT_M := 3.6576
const MIX_ID := "audio_mix.default"
const GROUP := "audio_director"
const LOG_SIZE := 512
const NO_AUDIO_ARG := "--no-audio"
## With this user arg the engine prints one "AUDIO_STATS {json}" line when the process ends (the
## determinism gate test reads it to prove the audio run really played).
const STATS_ARG := "--audio-stats"
const LEVEL_GROUP := "level_root"
const SANDBOX_GROUP := "sandbox"
## The level key of the sandbox (it has no level record).
const SANDBOX_LEVEL := "sandbox"
## Levels and contexts with no music or ambience by decision (P23's coverage test reads them).
const SILENT_LEVELS := ["level.stress_arena", "level.director_test"]
const SILENT_CONTEXTS := ["loading"]
const FOCUS_MUTE_DB := -80.0
const FOCUS_RAMP_S := 0.2
const LISTENER_HEIGHT_FACTOR := 0.8
const ZONE_HYSTERESIS_M := 15.0
const ZONE_POLL_S := 0.25
## At exit: the longest wait for the mixing thread to drop the stopped playbacks.
const RELEASE_WAIT_MS := 250
## Settings key -> bus.
const VOLUME_KEYS := {"volume_master": "Master", "volume_music": "Music", "volume_ambience": "Ambience",
	"volume_sfx": "SFX", "volume_ui": "UI"}
const CUE_DEFAULTS := {"bus": "SFX", "spatial": true, "class": "impact", "volume_db": 0.0, "pitch": 1.0,
	"pitch_jitter": 0.0, "size_pitch": false, "max_voices": 4, "retrigger_ms": 40, "priority": 50,
	"far": "", "levels": []}

## false with --no-audio (the default suite): no listeners, no players, nothing plays.
var enabled := true
var music: MusicDirector
var ambience: AmbienceDirector
var pool: VoicePool
var router: CueRouter
var listener: AudioListener3D
## The audio_mix record in use.
var mix: Dictionary = {}
## Presentation time: the sum of process deltas (with --fixed-fps it advances 1/60 s a frame,
## so the log is deterministic).
var clock_s := 0.0
## Process frames since the engine was enabled (the cue log's "frame").
var frame := 0
## The level whose samples are registered ("" = none; "sandbox" for the sandbox).
var level_id := ""
## Requests that resolved to no cue: requested cue id -> count (the coverage tests keep it empty).
var missing: Dictionary = {}
## Counters: played, dropped (no voice), capped (max_voices or starts per frame), retrigger,
## inaudible (under min_level_db), suppressed (threat stings), registered (samples).
var stats := {}
## Tests: register at most this many files a frame (0 = only the time budget limits it).
var registration_files_per_frame_cap := 0

var _enabled_at_start := true
var _cues: Dictionary = {}
var _catalog_problems := PackedStringArray()
var _rng := RandomNumberGenerator.new()
var _log: Array = []
var _last_variant: Dictionary = {}
var _last_start_ms: Dictionary = {}
var _streams: Dictionary = {}
var _registered: Dictionary = {}
var _reg_queue: Array = []
var _reg_total := 0
var _level_ref: WeakRef = null
var _focused := true
var _focus_db := 0.0
var _page_hidden := false
var _js_callback: Variant = null
var _zone_record: Dictionary = {}
var _last_zone_poll_s := -INF
var _player_cache: GiantPlayer = null
var _player_frame := -1


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group(GROUP)
	add_to_group("debug_info_providers")
	_enabled_at_start = not OS.get_cmdline_user_args().has(NO_AUDIO_ARG)
	enabled = false
	if _enabled_at_start:
		_enable()


func _exit_tree() -> void:
	if enabled and OS.get_cmdline_user_args().has(STATS_ARG):
		print("AUDIO_STATS " + JSON.stringify(stats_summary()))
	_release_playbacks()


## At exit (the autoload leaves the tree only when the process ends): stops every player of the
## engine and waits, at most RELEASE_WAIT_MS, until the mixing thread has dropped their playbacks.
## Godot frees a stopped playback on the audio thread's next mix steps; a process that quits
## before them (the soak's quit() while sounds play) would keep each playback and its stream alive
## at exit ("ObjectDB instances leaked", "resources still in use").
func _release_playbacks() -> void:
	var held: Array = []
	for p: Node in _players_under(self):
		if bool(p.call("has_stream_playback")):
			held.append(p.call("get_stream_playback"))
		p.call("stop")
	if held.is_empty():
		return
	held.append(RefCounted.new())   # a probe held by this array alone: the count to wait for
	var deadline := Time.get_ticks_msec() + RELEASE_WAIT_MS
	while Time.get_ticks_msec() < deadline:
		var alone := _ref_count(held, held.size() - 1)
		var waiting := false
		for i in held.size() - 1:
			if _ref_count(held, i) > alone:
				waiting = true
				break
		if not waiting:
			return
		OS.delay_msec(5)


static func _ref_count(list: Array, i: int) -> int:
	return (list[i] as RefCounted).get_reference_count()


static func _players_under(node: Node) -> Array:
	var out: Array = []
	for c in node.get_children():
		if c is AudioStreamPlayer or c is AudioStreamPlayer3D:
			out.append(c)
		out.append_array(_players_under(c))
	return out


# --------------------------------------------------------------------------- enable / disable

func _enable() -> void:
	if enabled:
		return
	enabled = true
	_rng.seed = hash("audio")
	_zero_stats()
	reload_catalog()
	_ensure_buses()
	pool = VoicePool.new()
	pool.name = "Pool"
	pool.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(pool)
	pool.configure(mix.get("pool", {}), OS.has_feature("web"))
	music = MusicDirector.new()
	music.name = "Music"
	music.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(music)
	music.setup(self)
	ambience = AmbienceDirector.new()
	ambience.name = "Ambience"
	ambience.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(ambience)
	ambience.setup(self)
	router = CueRouter.new()
	router.name = "Router"
	add_child(router)
	router.setup(self)
	listener = AudioListener3D.new()
	listener.name = "Listener"
	add_child(listener)
	if not get_tree().node_added.is_connected(_on_node_added):
		get_tree().node_added.connect(_on_node_added)
	if not Settings.changed.is_connected(_on_settings_changed):
		Settings.changed.connect(_on_settings_changed)
	if not GameData.reloaded.is_connected(reload_catalog):
		GameData.reloaded.connect(reload_catalog)
	_apply_volumes()
	_setup_web_visibility()
	_wire_existing(get_tree().root)


func _disable() -> void:
	if not enabled:
		return
	enabled = false
	if get_tree().node_added.is_connected(_on_node_added):
		get_tree().node_added.disconnect(_on_node_added)
	if Settings.changed.is_connected(_on_settings_changed):
		Settings.changed.disconnect(_on_settings_changed)
	if GameData.reloaded.is_connected(reload_catalog):
		GameData.reloaded.disconnect(reload_catalog)
	if router != null:
		router.teardown()
	for n: Node in [pool, music, ambience, router, listener]:
		if n != null and is_instance_valid(n):
			if n == listener and listener.is_current():
				listener.clear_current()
			remove_child(n)
			n.free()
	pool = null
	music = null
	ambience = null
	router = null
	listener = null
	_reset_state()
	var master := AudioServer.get_bus_index("Master")
	if master >= 0:
		AudioServer.set_bus_volume_db(master, 0.0)
		AudioServer.set_bus_mute(master, false)


func _reset_state() -> void:
	_log.clear()
	_last_variant.clear()
	_last_start_ms.clear()
	_reg_queue.clear()
	_reg_total = 0
	_registered.clear()
	_streams.clear()
	_level_ref = null
	level_id = ""
	missing.clear()
	_zone_record = {}
	_last_zone_poll_s = -INF
	_focused = true
	_focus_db = 0.0
	_player_cache = null
	_player_frame = -1
	registration_files_per_frame_cap = 0
	_zero_stats()


func _zero_stats() -> void:
	stats = {"played": 0, "dropped": 0, "capped": 0, "retrigger": 0, "inaudible": 0, "suppressed": 0,
		"registered": 0}


## Tests: turn the engine on (or off). The default suite runs with --no-audio; audio suites call
## this in before_each, and reset_for_tests() puts the process's state back after each test.
func enable_for_tests(on := true) -> void:
	if on:
		_enable()
	else:
		_disable()
	clear_log()


## The test runner: the state reset_for_tests() returns to (silent by default, plan §2.16).
func set_process_default(on: bool) -> void:
	_enabled_at_start = on
	enable_for_tests(on)


## ResetHooks.BEFORE_EACH (first entry): stop everything, clear the log and the queues, reset the
## directors, and return to the process's own enabled state. Nothing to do when disabled.
func reset_for_tests() -> void:
	if enabled != _enabled_at_start:
		enable_for_tests(_enabled_at_start)
	if not enabled:
		return
	pool.stop_all()
	pool.dropped = 0
	pool.stolen = 0
	music.reset()
	ambience.reset()
	router.reset()
	_reset_state()
	reload_catalog()
	clock_s = 0.0
	frame = 0
	_rng.seed = hash("audio")
	_apply_volumes()


# --------------------------------------------------------------------------- the catalogue

## Rebuilds the cue catalogue from the audio_bank records and re-reads the mix (GameData.reloaded;
## tests that override audio records call it).
func reload_catalog() -> void:
	_cues.clear()
	_catalog_problems.clear()
	mix = GameData.get_record(MIX_ID).duplicate(true)
	_merge_district_surfaces()
	for bank: Dictionary in GameData.records_of_type("audio_bank"):
		var cues: Variant = bank.get("cues")
		if typeof(cues) != TYPE_DICTIONARY:
			continue
		for cue_id: String in cues:
			if _cues.has(cue_id):
				_catalog_problems.append("%s: cue %s is also in %s" % [bank.id, cue_id, _cues[cue_id].bank])
				continue
			var c: Dictionary = CUE_DEFAULTS.duplicate(true)
			c.merge((cues[cue_id] as Dictionary).duplicate(true), true)
			c["id"] = cue_id
			c["bank"] = str(bank.id)
			_cues[cue_id] = c
	for cue_id: String in _cues:
		var far := str(_cues[cue_id].get("far", ""))
		if far != "" and not _cues.has(far):
			_catalog_problems.append("%s: its far cue %s is in no bank" % [cue_id, far])
	for t: String in ["music_set", "ambience_set"]:
		for rec: Dictionary in GameData.records_of_type(t):
			for cue_id: String in set_cues(rec):
				if resolve(cue_id).is_empty():
					_catalog_problems.append("%s: cue %s resolves to nothing" % [rec.id, cue_id])



## A level district's own `surface` (the test levels under data/test, which the shipped mix may
## not name: the Web release leaves them out) fills the mix's surfaces map where the mix is silent
## (wave 13).
func _merge_district_surfaces() -> void:
	var surfaces: Dictionary = mix.get("surfaces", {})
	for lv: Dictionary in GameData.records_of_type("level"):
		for d: Variant in lv.get("districts", []):
			if typeof(d) != TYPE_DICTIONARY or str(d.get("surface", "")) == "":
				continue
			var by_level: Dictionary = surfaces.get(lv.id, {})
			if not by_level.has(d.id):
				by_level[d.id] = str(d.surface)
			surfaces[lv.id] = by_level
	if not mix.is_empty():
		mix["surfaces"] = surfaces


## The cue ids a music or ambience set names (stingers, beds, spots, emitters, the flush cue).
static func set_cues(rec: Dictionary) -> PackedStringArray:
	var out := PackedStringArray()
	for key: String in ["combat_intro", "intro"]:
		if str(rec.get(key, "")) != "":
			out.append(str(rec[key]))
	for list_key: String in ["beds", "spots", "emitters"]:
		var list: Variant = rec.get(list_key)
		if typeof(list) == TYPE_ARRAY:
			for item: Variant in list:
				if typeof(item) == TYPE_DICTIONARY and str(item.get("cue", "")) != "":
					out.append(str(item.cue))
	var reactions: Variant = rec.get("reactions")
	if typeof(reactions) == TYPE_DICTIONARY and str(reactions.get("flush_cue", "")) != "":
		out.append(str(reactions.flush_cue))
	return out


## Cross-record problems of the audio data (duplicate cue ids, far cues and set cues that resolve
## to nothing). Empty for the shipped data (tests).
func catalog_problems() -> PackedStringArray:
	if not enabled:
		reload_catalog()
	return _catalog_problems.duplicate()


## The cue after the fallback chain (sfx.hit.flesh.light -> sfx.hit.flesh -> sfx.hit.default);
## {} when nothing resolves. The dictionary carries "id" (the cue found) and "bank".
func resolve(cue_id: String) -> Dictionary:
	return resolve_chain([cue_id])


func resolve_chain(candidates: Array) -> Dictionary:
	if _cues.is_empty() and not enabled:
		reload_catalog()
	for id in AudioMath.expand_chain(candidates):
		if _cues.has(id):
			return _cues[id]
	return {}


func has_cue(cue_id: String) -> bool:
	if _cues.is_empty() and not enabled:
		reload_catalog()
	return _cues.has(cue_id)


func cue_ids() -> PackedStringArray:
	var out := PackedStringArray(_cues.keys())
	out.sort()
	return out


func note_missing(cue_id: String) -> void:
	missing[cue_id] = int(missing.get(cue_id, 0)) + 1


## A stream by res:// path, loaded once and kept (registered samples stay alive with it).
func load_stream(path: String) -> AudioStream:
	var s: AudioStream = _streams.get(path)
	if s == null and path != "" and ResourceLoader.exists(path):
		s = load(path) as AudioStream
		if s != null:
			_streams[path] = s
	return s


# --------------------------------------------------------------------------- playing

## Plays a cue now: `at` Vector3.INF is non-positional. opts: "source_height_m" (size pitch),
## "priority", "volume_db", "pitch", "reason", "expected_damage" + "max_health" + "poise_ratio"
## (a threat sting: suppressed under decision 7's thresholds), "kind" ("spot": an ambience spot
## voice). Returns a voice id, or -1 (unknown cue, capped, retrigger guard, under min_level_db,
## suppressed sting, disabled). A Music-bus cue plays as a stinger (-2).
func play(cue_id: String, at: Vector3 = Vector3.INF, opts: Dictionary = {}) -> int:
	return play_request([cue_id], at, opts)


## play() with explicit candidates (the router's requests).
func play_request(chain: Array, at: Vector3, opts: Dictionary) -> int:
	if not enabled or chain.is_empty():
		return -1
	var cue := resolve_chain(chain)
	if cue.is_empty():
		note_missing(str(chain[0]))
		return -1
	var bus := str(cue.get("bus", "SFX"))
	if bus == "Music":
		return -2 if music.play_stinger(str(cue.id), int(opts.get("priority", cue.get("priority", 60)))) > 0.0 else -1
	if opts.has("expected_damage") and AudioMath.sting_suppressed(float(opts.expected_damage),
			float(opts.get("max_health", 0.0)), float(opts.get("poise_ratio", 1.0)), mix.get("sting", {})):
		stats.suppressed += 1
		return -1
	var now_ms := int(clock_s * 1000.0)
	var last := int(_last_start_ms.get(cue.id, -1000000))
	if now_ms - last < int(cue.get("retrigger_ms", 40)):
		stats.retrigger += 1
		return -1
	if pool.count_playing(str(cue.id)) >= int(cue.get("max_voices", 4)) or not pool.can_start():
		stats.capped += 1
		return -1
	var spatial := bool(cue.get("spatial", true)) and at != Vector3.INF
	var kind := VoicePool.Kind.VOICE_2D
	if bus == "Ambience" or str(opts.get("kind", "")) == "spot":
		kind = VoicePool.Kind.SPOT
		if at == Vector3.INF:
			at = listener_position()
		spatial = true
	elif spatial:
		kind = VoicePool.Kind.VOICE_3D
	var volume := float(cue.get("volume_db", 0.0)) + float(opts.get("volume_db", 0.0))
	var dist := Vector2(5.0, 40.0)
	if spatial:
		dist = _distances(str(cue.get("class", "spot" if kind == VoicePool.Kind.SPOT else "impact")))
		var d := listener_position().distance_to(at)
		var far := str(cue.get("far", ""))
		if far != "" and d > 0.5 * dist.y:
			var fc := resolve(far)
			if not fc.is_empty():
				cue = fc
				volume = float(cue.get("volume_db", 0.0)) + float(opts.get("volume_db", 0.0))
				dist = _distances(str(cue.get("class", "impact")))
		if AudioMath.level_at(d, dist.x, dist.y, volume) < float((mix.get("pool", {}) as Dictionary).get("min_level_db", -45.0)):
			stats.inaudible += 1
			return -1
	var files: Array = cue.get("files", [])
	if files.is_empty():
		note_missing(str(cue.id))
		return -1
	var idx := AudioMath.pick_variant(files.size(), int(_last_variant.get(cue.id, -1)), _rng)
	var stream := load_stream(str(files[idx]))
	if stream == null:
		note_missing(str(cue.id))
		return -1
	var pitch := float(cue.get("pitch", 1.0)) * float(opts.get("pitch", 1.0))
	var jitter := float(cue.get("pitch_jitter", 0.0))
	if jitter > 0.0:
		pitch *= 1.0 + _rng.randf_range(-jitter, jitter)
	if bool(cue.get("size_pitch", false)) and opts.has("source_height_m"):
		pitch *= AudioMath.size_pitch(float(opts.source_height_m))
	var priority := int(opts.get("priority", cue.get("priority", 50)))
	var player := pool.acquire(kind, priority)
	if player == null:
		stats.dropped += 1
		return -1
	var voice := pool.start(player, stream, str(cue.id), priority, {"bus": bus, "volume_db": volume,
		"pitch": pitch, "position": at, "unit_size": dist.x, "max_distance": dist.y,
		"pausable": bus != "UI"})
	_last_variant[cue.id] = idx
	_last_start_ms[cue.id] = now_ms
	stats.played += 1
	log_cue({"cue": str(cue.id), "requested": str(chain[0]), "bus": bus, "pos": at if spatial else Vector3.INF,
		"voice": voice, "priority": priority, "reason": str(opts.get("reason", "")), "file": str(files[idx])})
	return voice


## Vector2(unit_size, max_distance) of a mix class at the current distance scale.
func _distances(cls_name: String) -> Vector2:
	var classes: Dictionary = mix.get("classes", {})
	var cls: Dictionary = classes.get(cls_name, {"unit_m": 5.0, "max_m": 40.0, "scaled": true})
	return AudioMath.class_distances(cls, distance_scale(), player_height() / REFERENCE_HEIGHT_M)


## {"unit", "max"} of a class (the ambience emitters).
func class_distances(cls_name: String) -> Dictionary:
	var v := _distances(cls_name)
	return {"unit": v.x, "max": v.y}


func log_cue(entry: Dictionary) -> void:
	var e := entry.duplicate()
	e["frame"] = frame
	e["tick"] = Sim.tick
	_log.append(e)
	if _log.size() > LOG_SIZE:
		_log.remove_at(0)


## The last 512 cues started: {"frame", "tick", "cue", "requested", "bus", "pos", "voice",
## "priority", "reason", "file"} (voice -2: a stinger; -3: a music set started; -4: a bed).
func cue_log() -> Array:
	return _log.duplicate(true)


func clear_log() -> void:
	_log.clear()


## Tests: runs the engine's frame logic for `seconds` of presentation time in steps of `step`
## without waiting for real frames (the music and ambience directors and the router included).
## Combine with music.clock_positions so bars follow the clock.
func advance_for_tests(seconds: float, step := 1.0 / 60.0) -> void:
	if not enabled:
		return
	var left := seconds
	while left > 1e-9:
		var dt := minf(step, left)
		left -= dt
		_process(dt)
		music._process(dt)
		ambience._process(dt)


## Cue ids of the log, in order (tests).
func logged_cues() -> PackedStringArray:
	var out := PackedStringArray()
	for e: Dictionary in _log:
		out.append(str(e.cue))
	return out


func stats_summary() -> Dictionary:
	var out := stats.duplicate()
	out["missing"] = missing.duplicate()
	out["voices_stolen"] = pool.stolen if pool != null else 0
	out["music_set"] = music.set_id() if music != null else ""
	return out


# --------------------------------------------------------------------------- the frame

func _process(delta: float) -> void:
	if not enabled:
		return
	clock_s += delta
	frame += 1
	_detect_level()
	if not _reg_queue.is_empty():
		_register_slice()
	pool.begin_frame()
	_update_listener()
	_update_focus(delta)
	if clock_s - _last_zone_poll_s >= ZONE_POLL_S:
		_last_zone_poll_s = clock_s
		_poll_zone()
	router.process_frame()


func _input(event: InputEvent) -> void:
	if enabled and router != null:
		router.on_input(event)


func _on_node_added(node: Node) -> void:
	if router != null:
		router.on_node_added(node)
	if node is LevelRoot:
		_detect_level()


func _wire_existing(node: Node) -> void:
	for child in node.get_children():
		if router != null:
			router.on_node_added(child)
		_wire_existing(child)


# --------------------------------------------------------------------------- levels and the loading gate

## The loaded level: the level_root node, else the sandbox (null when there is none).
func level_node() -> Node:
	var lv := _level_ref.get_ref() as Node if _level_ref != null else null
	return lv if lv != null and is_instance_valid(lv) and lv.is_inside_tree() else null


func _find_level() -> Node:
	var lv := get_tree().get_first_node_in_group(LEVEL_GROUP)
	if lv == null:
		lv = get_tree().get_first_node_in_group(SANDBOX_GROUP)
	return lv


func _detect_level() -> void:
	var lv := _find_level()
	var current := level_node()
	if lv == current:
		if lv == null and level_id != "":
			level_id = ""
			_zone_record = {}
		return
	_level_ref = weakref(lv) if lv != null else null
	_zone_record = {}
	_last_zone_poll_s = -INF
	if music != null:
		music.on_level_changed()
	if lv == null:
		level_id = ""
		return
	level_id = str(lv.get("level_id")) if lv is LevelRoot else SANDBOX_LEVEL
	_begin_registration(level_id)


## The SFX sample files a level registers: every WAV of a cue with no `levels`, then of the cues
## whose `levels` name the level (in cue id order).
func sample_paths_for(level: String) -> PackedStringArray:
	if _cues.is_empty():
		reload_catalog()
	var out := PackedStringArray()
	var ids := _cues.keys()
	ids.sort()
	for pass_global: bool in [true, false]:
		for cue_id: String in ids:
			var c: Dictionary = _cues[cue_id]
			if not (str(c.get("bus", "SFX")) in ["SFX", "UI"]):
				continue
			var levels: Array = c.get("levels", [])
			if pass_global != levels.is_empty():
				continue
			if not pass_global and not levels.has(level):
				continue
			for f: Variant in c.get("files", []):
				var path := str(f)
				if path.ends_with(".wav") and not out.has(path):
					out.append(path)
	return out


func _begin_registration(level: String) -> void:
	var needed := sample_paths_for(level)
	for path: String in _registered.keys():
		if not needed.has(path):
			_registered.erase(path)
			_streams.erase(path)   # freed with its last user: the web sample goes with it
	_reg_queue.clear()
	for path in needed:
		if not _registered.has(path):
			_reg_queue.append(path)
	_reg_total = _reg_queue.size()


## One slice: register queued samples for at most register_ms_per_frame milliseconds.
func _register_slice() -> void:
	var budget_us := int(float((mix.get("pool", {}) as Dictionary).get("register_ms_per_frame", 12.0)) * 1000.0)
	var t0 := Time.get_ticks_usec()
	var n := 0
	while not _reg_queue.is_empty():
		if registration_files_per_frame_cap > 0 and n >= registration_files_per_frame_cap:
			break
		var path := str(_reg_queue.pop_front())
		var s := load_stream(path)
		if s != null:
			AudioServer.register_stream_as_sample(s)
			_registered[path] = true
			stats.registered += 1
		n += 1
		if Time.get_ticks_usec() - t0 >= budget_us:
			break


## True when every sample of the current level is registered (always true when disabled).
## scripts/main.gd keeps the tree paused behind "Loading..." until it is.
func is_ready() -> bool:
	if not enabled:
		return true
	_detect_level()
	return _reg_queue.is_empty()


## 0..1 for the loading screen.
func registration_progress() -> float:
	if not enabled or _reg_total <= 0:
		return 1.0
	return clampf(1.0 - float(_reg_queue.size()) / float(_reg_total), 0.0, 1.0)


## True while a level is registering its samples (the music stays silent meanwhile).
func level_loading() -> bool:
	return enabled and not _reg_queue.is_empty()


# --------------------------------------------------------------------------- the player and the listener

## The giant (group "player"), cached for the frame; null without one.
func player() -> GiantPlayer:
	if _player_frame != frame or (_player_cache != null and not is_instance_valid(_player_cache)):
		_player_frame = frame
		_player_cache = get_tree().get_first_node_in_group("player") as GiantPlayer
		if _player_cache != null and not _player_cache.is_inside_tree():
			_player_cache = null
	return _player_cache if is_instance_valid(_player_cache) else null


func player_height() -> float:
	var p := player()
	if p == null:
		return REFERENCE_HEIGHT_M
	return float(p.profile.get("height_m", REFERENCE_HEIGHT_M))


func player_dead() -> bool:
	var p := player()
	return p != null and p.controller != null and p.controller.state == CombatController.State.DEAD


## clamp(player height / 3.6576, 1, 5.2) (1 without a giant).
func distance_scale() -> float:
	return AudioMath.distance_scale(player_height())


## Where the listener is (the giant's chest; the camera or the origin without a giant).
func listener_position() -> Vector3:
	if listener != null and listener.is_inside_tree() and listener.is_current():
		return listener.global_position
	var cam := get_viewport().get_camera_3d() if get_viewport() != null else null
	return cam.global_position if cam != null else Vector3.ZERO


func _update_listener() -> void:
	var p := player()
	if p == null:
		if listener.is_current():
			listener.clear_current()
		return
	var pivot := float(p.profile.get("camera_pivot_height_m", 3.3))
	listener.global_position = p.global_position + Vector3.UP * pivot * LISTENER_HEIGHT_FACTOR
	var rig := p.camera_rig
	listener.global_basis = Basis.from_euler(Vector3(rig.pitch, rig.yaw, 0.0)) if rig != null else p.global_basis
	if not listener.is_current():
		listener.make_current()


# --------------------------------------------------------------------------- zones (audio_region)

## The audio_region winning where the giant stands (§2.5: the highest priority match of the
## level's districts, regions and POIs, with 15 m hysteresis); {} when none.
func current_region() -> Dictionary:
	return _zone_record


func _poll_zone() -> void:
	var p := player()
	var lv := level_node()
	if p == null or lv == null or level_id == SANDBOX_LEVEL or SILENT_LEVELS.has(level_id):
		_zone_record = {}
		return
	var pos := p.global_position
	var winner := region_at(pos)
	if winner.is_empty() or str(winner.get("id", "")) == str(_zone_record.get("id", "")):
		return
	if not _zone_record.is_empty():
		for off: Vector3 in [Vector3(ZONE_HYSTERESIS_M, 0, 0), Vector3(-ZONE_HYSTERESIS_M, 0, 0),
				Vector3(0, 0, ZONE_HYSTERESIS_M), Vector3(0, 0, -ZONE_HYSTERESIS_M)]:
			if str(region_at(pos + off).get("id", "")) != str(winner.id):
				return   # not yet 15 m inside the new zone
	_zone_record = winner


## The winning audio_region at `pos` in the current level ({} when none matches).
func region_at(pos: Vector3) -> Dictionary:
	var lv := level_node()
	if lv == null:
		return {}
	var district := str(lv.call("district_at", pos)) if lv.has_method("district_at") else ""
	var region := str(lv.call("region_at", pos)) if lv.has_method("region_at") else ""
	var best: Dictionary = {}
	var best_p := -1000000
	for rec: Dictionary in GameData.records_of_type("audio_region"):
		if str(rec.get("level", "")) != level_id or str(rec.get("context", "")) != "" or str(rec.get("boss", "")) != "":
			continue
		var hit := false
		if district != "" and (rec.get("districts", []) as Array).has(district):
			hit = true
		elif region != "" and (rec.get("regions", []) as Array).has(region):
			hit = true
		elif _in_poi(rec.get("pois", []), pos):
			hit = true
		if hit and int(rec.get("priority", 0)) > best_p:
			best = rec
			best_p = int(rec.get("priority", 0))
	return best


static func _in_poi(pois: Variant, pos: Vector3) -> bool:
	if typeof(pois) != TYPE_ARRAY:
		return false
	for poi_id: Variant in pois:
		var rec := GameData.get_record(str(poi_id))
		var c: Variant = rec.get("position_m")
		if typeof(c) == TYPE_ARRAY and (c as Array).size() == 3:
			var centre := Vector3(float(c[0]), float(c[1]), float(c[2]))
			if Vector2(pos.x - centre.x, pos.z - centre.z).length() <= float(rec.get("radius_m", 0.0)):
				return true
	return false


## The audio_region of a context (title, end, campaign_end, sandbox); {} when none.
func context_region(context: String) -> Dictionary:
	for rec: Dictionary in GameData.records_of_type("audio_region"):
		if str(rec.get("context", "")) == context:
			return rec
	return {}


## The audio_region whose boss is `boss_id` (an entity id: its record id is tried too).
func boss_region(boss_id: String) -> Dictionary:
	var keys := [boss_id]
	var e := Sim.get_entity(boss_id)
	if e != null:
		keys.append(e.definition_id)
	for rec: Dictionary in GameData.records_of_type("audio_region"):
		if keys.has(str(rec.get("boss", ""))):
			return rec
	return {}


## The footfall surface at `pos`: the level's surface_at (P24a), else the region record's surface,
## else audio_mix.surfaces[level][district or region], else "soft".
func surface_at(pos: Vector3) -> String:
	var lv := level_node()
	if lv == null:
		return "soft"
	if lv.has_method("surface_at"):
		var s: Variant = lv.call("surface_at", pos)
		if typeof(s) == TYPE_STRING and s != "":
			return s
	var zone := ""
	if lv.has_method("region_at"):
		zone = str(lv.call("region_at", pos))
		var surface := str(GameData.get_record(zone).get("surface", ""))
		if surface != "":
			return surface
	elif lv.has_method("district_at"):
		zone = str(lv.call("district_at", pos))
	var surfaces: Dictionary = (mix.get("surfaces", {}) as Dictionary).get(level_id, {})
	return str(surfaces.get(zone, "soft"))


## Water above the ground at `pos` (P24a's water_at; 0 without water).
func water_depth_at(pos: Vector3) -> float:
	var lv := level_node()
	if lv == null or not lv.has_method("water_at"):
		return 0.0
	var w: Variant = lv.call("water_at", pos)
	if typeof(w) == TYPE_FLOAT or typeof(w) == TYPE_INT:
		return maxf(float(w) - pos.y, 0.0)
	return 0.0


# --------------------------------------------------------------------------- ducks, buses, settings, focus

## The duck reasons active now (audio_mix.duck): stinger, dialogue, pause, boss, combat.
func active_ducks() -> Array:
	var out: Array = []
	if music != null and music.stinger_playing():
		out.append("stinger")
	if router != null and router.dialogue_open():
		out.append("dialogue")
	if get_tree().paused and level_node() != null and not level_loading():
		out.append("pause")
	if music != null and music.state == MusicDirector.State.BOSS:
		out.append("boss")
	if music != null and music.intensity == AudioMath.COMBAT:
		out.append("combat")
	return out


func _ensure_buses() -> void:
	for bus: String in BUSES:
		if AudioServer.get_bus_index(bus) >= 0:
			continue
		AudioServer.add_bus()
		var idx := AudioServer.bus_count - 1
		AudioServer.set_bus_name(idx, bus)
		AudioServer.set_bus_send(idx, "Master")


## Settings volume (0..1) for a bus, on top of the mix's bus level; 0 mutes.
func set_bus_volume_linear(bus: String, value: float) -> void:
	var idx := AudioServer.get_bus_index(bus)
	if idx < 0:
		return
	var base := float((mix.get("bus_db", {}) as Dictionary).get(bus, 0.0))
	if bus == "Master":
		base += _focus_db
	AudioServer.set_bus_mute(idx, value <= 0.0001 or (bus == "Master" and _page_hidden))
	AudioServer.set_bus_volume_db(idx, base + AudioMath.linear_to_db_safe(maxf(value, 0.0001)) if value > 0.0001 else -80.0)


func _apply_volumes() -> void:
	for key: String in VOLUME_KEYS:
		set_bus_volume_linear(VOLUME_KEYS[key], float(Settings.get_value(key)))


func _on_settings_changed(key: String) -> void:
	if VOLUME_KEYS.has(key) or key == "mute_when_unfocused":
		_apply_volumes()


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_WM_WINDOW_FOCUS_OUT:
			_focused = false
		NOTIFICATION_APPLICATION_FOCUS_IN, NOTIFICATION_WM_WINDOW_FOCUS_IN:
			_focused = true


func _update_focus(delta: float) -> void:
	var target := FOCUS_MUTE_DB if (not _focused and bool(Settings.get_value("mute_when_unfocused"))) else 0.0
	if is_equal_approx(_focus_db, target):
		return
	_focus_db = move_toward(_focus_db, target, absf(FOCUS_MUTE_DB) / FOCUS_RAMP_S * delta)
	set_bus_volume_linear("Master", float(Settings.get_value("volume_master")))


## Master's volume now (dB; tests).
func master_db() -> float:
	return AudioServer.get_bus_volume_db(AudioServer.get_bus_index("Master"))


func _setup_web_visibility() -> void:
	if not OS.has_feature("web") or _js_callback != null:
		return
	var document: Variant = JavaScriptBridge.get_interface("document")
	if document == null:
		return
	_js_callback = JavaScriptBridge.create_callback(_on_visibility_changed)
	document.addEventListener("visibilitychange", _js_callback)


func _on_visibility_changed(_args: Array) -> void:
	var document: Variant = JavaScriptBridge.get_interface("document")
	_page_hidden = document != null and bool(document.hidden) and bool(Settings.get_value("mute_when_unfocused"))
	set_bus_volume_linear("Master", float(Settings.get_value("volume_master")))


# --------------------------------------------------------------------------- debug

## Lines for the F3 panel (group debug_info_providers).
func debug_lines() -> PackedStringArray:
	var lines := PackedStringArray()
	if not enabled:
		lines.append("AUDIO off (--no-audio)")
		return lines
	var miss := PackedStringArray()
	for k: String in missing:
		miss.append(k)
	miss.sort()
	lines.append("AUDIO %s  queue %d  level %s%s  played %d  missing %d%s" % [pool.summary(),
		router.queue.size(), level_id if level_id != "" else "-",
		"  registering %d%%" % int(registration_progress() * 100.0) if level_loading() else "",
		int(stats.played), miss.size(), (" (" + ", ".join(miss.slice(0, 4)) + ")") if not miss.is_empty() else ""])
	lines.append_array(music.debug_lines())
	lines.append_array(ambience.debug_lines())
	return lines
