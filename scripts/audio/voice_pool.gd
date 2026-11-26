class_name VoicePool
extends Node
## The audio engine's voices (P19; plan M6-M9 §3.1 design 2): a fixed pool of players, no node per
## event. Child of the Audio autoload.
##
##   voices_3d   AudioStreamPlayer3D, PROCESS_MODE_PAUSABLE (silenced by the tree pause), playback
##               type left DEFAULT (Web Audio samples on the web; decision 2); 24 on desktop, 16 on
##               the web (every web sample play copies its buffer).
##   spot_voices AudioStreamPlayer3D on the Ambience bus with PLAYBACK_TYPE_STREAM (ambience spots
##               are Ogg streams), PROCESS_MODE_PAUSABLE.
##   voices_2d   AudioStreamPlayer, PROCESS_MODE_ALWAYS for interface cues (they play in menus); a
##               non-UI 2D cue makes its voice pausable for that play.
##   near_voices C3 (decision C3-2): for a 3D cue heard within its class's unit distance (the giant's own
##               swings and steps, the blows he lands), played at the level the 3D model gives it there. A
##               3D player starts its sample at gain zero and pans it in its physics processing (on the web
##               the Web Audio gains are set then): started in a frame's processing, it was panned in the
##               next frame's physics, which cut the first 16-40 ms - the whole transient of a hit or a
##               footfall - so C3 played them on unpanned 2D players, centred. C3b (decision C3b-6): they are
##               AudioStreamPlayer3D again (unit_size the source's distance: no attenuation, the model's level),
##               panned from the
##               source's bearing, and started only inside a physics frame and before their own physics
##               processing (process_physics_priority NEAR_PHYSICS_PRIORITY, after the simulation's): a
##               start asked for in a frame's processing waits for the next physics frame (at most one
##               frame, deferred), so the gains are set in the same engine frame - the same browser task -
##               as the source starts, before any of it is heard.
##
## Every 3D voice uses ATTENUATION_LOGARITHMIC with no distance filter (attenuation_filter_db 0: the
## filter does not exist for web samples, so far sounds are baked "far" variants instead), no
## doppler, no emission angle, no area reverb (area_mask 0) and max_db 3; unit_size and
## max_distance come per play from the cue's class (Audio.play). Stealing: a request that finds
## every voice of its kind busy takes the lowest-priority, oldest voice whose priority is at most
## its own (AudioMath.steal_index); otherwise it is dropped. At most starts_per_frame voices start
## in one frame (8 on the web).

enum Kind { VOICE_3D, SPOT, VOICE_2D, NEAR }
## C3b: the near voices' physics order (after every gameplay node's: their panning is computed after the frame's
## starts) and the pool's own (it starts the deferred near voices just before them).
const NEAR_PHYSICS_PRIORITY := 1000
const POOL_PHYSICS_PRIORITY := 999
## C3b: the near voices' ceiling (above any level the model gives a cue within its unit distance, plus the pan law).
const NEAR_MAX_DB := 9.0
const KIND_NAMES := ["3d", "spot", "2d", "near"]

var voices_3d: Array[AudioStreamPlayer3D] = []
var spot_voices: Array[AudioStreamPlayer3D] = []
var voices_2d: Array[AudioStreamPlayer] = []
var near_voices: Array[Node] = []   ## AudioStreamPlayer3D (C3b; typed as Node so any player can be looked up)
## C3b: near voices whose start waits for the next physics frame (asked for outside one).
var _deferred: Array[Node] = []
var starts_per_frame := 16
var starts_this_frame := 0
## Requests dropped because every voice of their kind was busy with a higher priority.
var dropped := 0
## Voices taken from a playing cue of equal or lower priority.
var stolen := 0

var _info: Dictionary = {}       ## player -> {"voice", "cue", "priority", "serial", "bus"}
var _by_voice: Dictionary = {}   ## voice id -> player
var _serial := 0
var _next_voice := 1


## Builds the players from audio_mix.pool (`web` picks the web counts).
func configure(pool_cfg: Dictionary, web: bool) -> void:
	clear()
	var n3 := int(pool_cfg.get("web_voices_3d" if web else "voices_3d", 24))
	var ns := int(pool_cfg.get("spot_voices", 2))
	var n2 := int(pool_cfg.get("voices_2d", 8))
	starts_per_frame = int(pool_cfg.get("web_starts_per_frame" if web else "starts_per_frame", 16))
	for i in n3:
		voices_3d.append(_make_3d("Voice3D_%d" % i, AudioServer.PLAYBACK_TYPE_DEFAULT, "SFX"))
	for i in ns:
		spot_voices.append(_make_3d("Spot_%d" % i, AudioServer.PLAYBACK_TYPE_STREAM, "Ambience"))
	for i in n2:
		var p := AudioStreamPlayer.new()
		p.name = "Voice2D_%d" % i
		p.process_mode = Node.PROCESS_MODE_ALWAYS
		p.bus = "UI"
		add_child(p)
		voices_2d.append(p)
	for i in int(pool_cfg.get("near_voices", 8)):
		var p := _make_3d("Near_%d" % i, AudioServer.PLAYBACK_TYPE_DEFAULT, "SFX")
		p.max_db = NEAR_MAX_DB   # (its unit distance is where it stands: the level is its volume, AudioDirector)
		p.process_physics_priority = NEAR_PHYSICS_PRIORITY
		near_voices.append(p)
	process_physics_priority = POOL_PHYSICS_PRIORITY
	set_physics_process(true)


func _make_3d(node_name: String, playback_type: int, bus: String) -> AudioStreamPlayer3D:
	var p := AudioStreamPlayer3D.new()
	p.name = node_name
	p.process_mode = Node.PROCESS_MODE_PAUSABLE
	configure_3d(p)
	p.playback_type = playback_type
	p.bus = bus
	add_child(p)
	return p


## The fixed settings of every 3D player of the engine (decision 2, §3.1 design 2).
static func configure_3d(p: AudioStreamPlayer3D) -> void:
	p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_LOGARITHMIC
	p.attenuation_filter_db = 0.0
	p.attenuation_filter_cutoff_hz = 20500.0
	p.doppler_tracking = AudioStreamPlayer3D.DOPPLER_TRACKING_DISABLED
	p.emission_angle_enabled = false
	p.area_mask = 0
	p.max_db = AudioMath.MAX_DB


## Frees every player.
func clear() -> void:
	for p: Node in voices_3d + spot_voices + voices_2d + near_voices:
		if is_instance_valid(p):
			p.queue_free()
	voices_3d.clear()
	spot_voices.clear()
	voices_2d.clear()
	near_voices.clear()
	_deferred.clear()
	_info.clear()
	_by_voice.clear()


## A new frame: the start budget refills.
func begin_frame() -> void:
	starts_this_frame = 0


func can_start() -> bool:
	return starts_this_frame < starts_per_frame


func _list(kind: int) -> Array:
	match kind:
		Kind.SPOT:
			return spot_voices
		Kind.VOICE_2D:
			return voices_2d
		Kind.NEAR:
			return near_voices
	return voices_3d


func _busy(p: Node) -> bool:
	return is_instance_valid(p) and (bool(p.get("playing")) or _deferred.has(p))


## How many voices play this cue now.
func count_playing(cue_id: String) -> int:
	var n := 0
	for p: Node in _info:
		if is_instance_valid(p) and str(_info[p].cue) == cue_id and _busy(p):
			n += 1
	return n


## Voices of a kind playing now.
func busy_count(kind: int) -> int:
	var n := 0
	for p: Node in _list(kind):
		if _busy(p):
			n += 1
	return n


func size_of(kind: int) -> int:
	return _list(kind).size()


## A free voice of `kind`, else one stolen from a cue of equal or lower priority (lowest, then
## oldest), else null (the request is dropped).
func acquire(kind: int, priority: int) -> Node:
	var list := _list(kind)
	for p: Node in list:
		if not _busy(p):
			return p
	var candidates: Array = []
	for p: Node in list:
		var i: Dictionary = _info.get(p, {})
		candidates.append({"priority": int(i.get("priority", 0)), "started": int(i.get("serial", 0))})
	var k := AudioMath.steal_index(candidates, priority)
	if k < 0:
		dropped += 1
		return null
	var victim: Node = list[k]
	victim.call("stop")
	stolen += 1
	return victim


## Starts `stream` on `player` and records it; returns the new voice id. settings: "bus",
## "volume_db", "pitch", "position" (3D), "unit_size", "max_distance" (3D), "pausable" (2D).
func start(player: Node, stream: AudioStream, cue_id: String, priority: int, settings: Dictionary) -> int:
	var old: Dictionary = _info.get(player, {})
	if not old.is_empty():
		_by_voice.erase(int(old.voice))
	player.set("stream", stream)
	player.set("bus", str(settings.get("bus", "SFX")))
	player.set("volume_db", float(settings.get("volume_db", 0.0)))
	player.set("pitch_scale", clampf(float(settings.get("pitch", 1.0)), 0.05, 8.0))
	if player is AudioStreamPlayer3D:
		var p3 := player as AudioStreamPlayer3D
		p3.unit_size = maxf(float(settings.get("unit_size", 5.0)), 0.01)
		p3.max_distance = maxf(float(settings.get("max_distance", 40.0)), 0.0)
		if p3.is_inside_tree():
			p3.global_position = settings.get("position", Vector3.ZERO)
	elif player is AudioStreamPlayer:
		player.process_mode = Node.PROCESS_MODE_PAUSABLE if bool(settings.get("pausable", false)) \
			else Node.PROCESS_MODE_ALWAYS
	if near_voices.has(player) and not Engine.is_in_physics_frame():
		if not _deferred.has(player):
			_deferred.append(player)   # C3b: started in the next physics frame
	else:
		_deferred.erase(player)
		player.call("play")
	_serial += 1
	var voice := _next_voice
	_next_voice += 1
	_info[player] = {"voice": voice, "cue": cue_id, "priority": priority, "serial": _serial,
		"bus": str(settings.get("bus", "SFX"))}
	_by_voice[voice] = player
	starts_this_frame += 1
	return voice


## The player of a voice id while that voice still plays its cue (null otherwise).
func voice_node(voice: int) -> Node:
	var p: Node = _by_voice.get(voice)
	if p == null or not is_instance_valid(p):
		return null
	return p if int((_info.get(p, {}) as Dictionary).get("voice", -1)) == voice else null


## The cue a voice id plays ("" when it is no longer that voice's).
func voice_cue(voice: int) -> String:
	var p := voice_node(voice)
	return str((_info.get(p, {}) as Dictionary).get("cue", "")) if p != null else ""


func stop_all() -> void:
	_deferred.clear()
	for p: Node in voices_3d + spot_voices + voices_2d + near_voices:
		if is_instance_valid(p):
			p.call("stop")
			p.set("stream", null)
	_info.clear()
	_by_voice.clear()
	starts_this_frame = 0


## C3b: the near voices asked for outside a physics frame start now, before their own physics processing pans them.
func _physics_process(_delta: float) -> void:
	if _deferred.is_empty():
		return
	var list := _deferred.duplicate()
	_deferred.clear()
	for p: AudioStreamPlayer3D in list:
		if is_instance_valid(p) and p.stream != null:
			p.play()


## "3d 3/24 spot 0/2 2d 1/8 near 2/8" for the F3 panel.
func summary() -> String:
	return "3d %d/%d spot %d/%d 2d %d/%d near %d/%d" % [busy_count(Kind.VOICE_3D), voices_3d.size(),
		busy_count(Kind.SPOT), spot_voices.size(), busy_count(Kind.VOICE_2D), voices_2d.size(),
		busy_count(Kind.NEAR), near_voices.size()]
