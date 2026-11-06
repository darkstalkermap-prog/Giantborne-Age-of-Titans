class_name AmbienceDirector
extends Node
## The ambience (P19; plan M6-M9 §2.5, §4.3). Child "Ambience" of the Audio autoload,
## PROCESS_MODE_PAUSABLE (the tree pause silences it with the effects).
##
## The zone's ambience_set (the winning audio_region's `ambience`, or the context's) plays:
##   beds      looping streams (AudioStreamPlayer, PLAYBACK_TYPE_STREAM, the Ambience bus),
##             cross-faded over BED_FADE_S on a zone change;
##   spots     one-shot amb. cues every spot_interval_s at a random bearing and distance
##             (spot_distance_m x the distance scale) around the listener, through the pool's two
##             spot voices (3D streams); weighted;
##   reactions a `flush` spot falls silent for flush_s after a giant's footfall or stomp within
##             flush_radius_m x the distance scale, which plays flush_cue once;
##   emitters  positioned loops: of the set's emitters on this level, the nearest two within their
##             radius play (3D streams), the others stop.
## Ducks (audio_mix.duck: dialogue, boss, combat) lower the beds, the emitters and the spots.
## It uses only its own RandomNumberGenerator.

const BED_FADE_S := 3.0
const EMITTER_FADE_S := 1.0
const MAX_EMITTERS := 2
const DEFAULT_SPOT_INTERVAL_S := Vector2(6.0, 14.0)
const DEFAULT_SPOT_DISTANCE_M := Vector2(15.0, 40.0)
const SILENT_DB := -80.0
const POLL_S := 0.25

var audio: Node = null
var set_id := ""
var rng := RandomNumberGenerator.new()
## Beds playing or fading: [{"player", "cue", "gain", "target", "volume_db"}].
var beds: Array = []
## Emitters playing: emitter key -> {"player", "cue", "gain", "target", "volume_db", "position"}.
var emitters: Dictionary = {}
## Spot cues played (newest last; tests and the F3 panel).
var spots_played: Array = []
var flushed_until_s := -INF
var flushes := 0

var _next_spot_s := INF
var _last_poll_s := -INF
var _rec: Dictionary = {}


func setup(p_audio: Node) -> void:
	audio = p_audio
	rng.seed = hash("audio.ambience")


func reset() -> void:
	for b: Dictionary in beds:
		_free_player(b.player)
	beds.clear()
	for k: String in emitters:
		_free_player(emitters[k].player)
	emitters.clear()
	spots_played.clear()
	set_id = ""
	_rec = {}
	flushed_until_s = -INF
	flushes = 0
	_next_spot_s = INF
	_last_poll_s = -INF
	rng.seed = hash("audio.ambience")


static func _free_player(p: Variant) -> void:
	if p is Node and is_instance_valid(p):
		(p as Node).queue_free()


func _now() -> float:
	return float(audio.clock_s) if audio != null else 0.0


func _process(delta: float) -> void:
	if audio == null or not bool(audio.get("enabled")):
		return
	var now := _now()
	if now - _last_poll_s >= POLL_S:
		_last_poll_s = now
		_poll(now)
	_update_volumes(delta)
	if set_id != "" and now >= _next_spot_s:
		_play_spot(now)


func _poll(now: float) -> void:
	var want := _desired_set()
	if want != set_id:
		_switch(want, now)
	_update_emitters()


## The ambience_set for where the giant is: the context's (title, end, sandbox) or the zone's.
func _desired_set() -> String:
	if bool(audio.call("level_loading")):
		return ""
	var level_id := str(audio.get("level_id"))
	if level_id == "":
		if GameSession.mode == GameSession.Mode.TITLE:
			return str((audio.call("context_region", "title") as Dictionary).get("ambience", ""))
		return ""
	if level_id == AudioDirector.SANDBOX_LEVEL:
		return str((audio.call("context_region", "sandbox") as Dictionary).get("ambience", ""))
	return str((audio.call("current_region") as Dictionary).get("ambience", ""))


func _switch(new_set: String, now: float) -> void:
	set_id = new_set
	var rec := GameData.get_record(new_set)
	_rec = rec if str(rec.get("type", "")) == "ambience_set" else {}
	for b: Dictionary in beds:
		b.target = 0.0
	if _rec.is_empty():
		_next_spot_s = INF
		return
	for bed: Variant in _rec.get("beds", []):
		if typeof(bed) != TYPE_DICTIONARY:
			continue
		var cue: Dictionary = audio.call("resolve", str(bed.get("cue", "")))
		if cue.is_empty():
			audio.call("note_missing", str(bed.get("cue", "")))
			continue
		var stream := _loop_stream(cue)
		if stream == null:
			continue
		var p := AudioStreamPlayer.new()
		p.name = "Bed_%s" % str(cue.id).replace(".", "_")
		p.playback_type = AudioServer.PLAYBACK_TYPE_STREAM
		p.bus = "Ambience"
		p.stream = stream
		p.volume_db = SILENT_DB
		add_child(p)
		p.play()
		beds.append({"player": p, "cue": str(cue.id), "gain": 0.0, "target": 1.0,
			"volume_db": float(cue.get("volume_db", 0.0)) + float(bed.get("volume_db", 0.0))})
		audio.call("log_cue", {"cue": str(cue.id), "requested": str(bed.get("cue", "")), "bus": "Ambience",
			"pos": Vector3.INF, "voice": -4, "priority": 0, "reason": "bed", "file": str((cue.files as Array)[0])})
	_next_spot_s = now + _interval()


## The cue's first file as a looping stream (beds and emitters loop; decision 2: always Ogg).
func _loop_stream(cue: Dictionary) -> AudioStream:
	var files: Array = cue.get("files", [])
	if files.is_empty():
		return null
	var stream := audio.call("load_stream", str(files[0])) as AudioStream
	if stream is AudioStreamOggVorbis:
		(stream as AudioStreamOggVorbis).loop = true
	return stream


func _interval() -> float:
	var r := _pair(_rec.get("spot_interval_s"), DEFAULT_SPOT_INTERVAL_S)
	return rng.randf_range(r.x, r.y)


static func _pair(v: Variant, fallback: Vector2) -> Vector2:
	if typeof(v) == TYPE_ARRAY and (v as Array).size() == 2:
		return Vector2(float(v[0]), float(v[1]))
	return fallback


func _play_spot(now: float) -> void:
	_next_spot_s = now + _interval()
	var spots: Array = []
	var total := 0.0
	for s: Variant in _rec.get("spots", []):
		if typeof(s) != TYPE_DICTIONARY:
			continue
		if bool(s.get("flush", false)) and now < flushed_until_s:
			continue
		spots.append(s)
		total += float(s.get("weight", 1.0))
	if spots.is_empty() or total <= 0.0:
		return
	var roll := rng.randf() * total
	var pick: Dictionary = spots[spots.size() - 1]
	for s: Dictionary in spots:
		roll -= float(s.get("weight", 1.0))
		if roll <= 0.0:
			pick = s
			break
	var centre: Vector3 = audio.call("listener_position")
	var dist_r := _pair(_rec.get("spot_distance_m"), DEFAULT_SPOT_DISTANCE_M) * float(audio.call("distance_scale"))
	var bearing := rng.randf_range(0.0, TAU)
	var dist := rng.randf_range(dist_r.x, dist_r.y)
	var at := centre + Vector3(sin(bearing) * dist, 0.0, cos(bearing) * dist)
	var cue_id := str(pick.get("cue", ""))
	var voice := int(audio.call("play", cue_id, at, {"volume_db": float(pick.get("volume_db", 0.0)) + duck_db(),
		"reason": "spot", "kind": "spot"}))
	if voice >= 0:
		spots_played.append(cue_id)
		if spots_played.size() > 64:
			spots_played.remove_at(0)


## A giant's footfall or stomp at `pos`: flush spots fall silent for flush_s when it is within
## flush_radius_m x the distance scale of the listener; entering the flush plays flush_cue once.
func on_giant_impact(pos: Vector3) -> void:
	var r: Variant = _rec.get("reactions")
	if typeof(r) != TYPE_DICTIONARY:
		return
	var radius := float(r.get("flush_radius_m", 40.0)) * float(audio.call("distance_scale"))
	var centre: Vector3 = audio.call("listener_position")
	if Vector2(pos.x - centre.x, pos.z - centre.z).length() > radius:
		return
	var now := _now()
	var was_flushed := now < flushed_until_s
	flushed_until_s = now + float(r.get("flush_s", 8.0))
	if was_flushed:
		return
	flushes += 1
	var cue := str(r.get("flush_cue", ""))
	if cue != "":
		audio.call("play", cue, pos + Vector3(0.0, 2.0, 0.0), {"reason": "flush", "kind": "spot",
			"volume_db": duck_db()})


## Of the set's emitters on this level, the nearest two within their radius play.
func _update_emitters() -> void:
	var wanted := {}
	var level_id := str(audio.get("level_id"))
	if not _rec.is_empty() and level_id != "":
		var centre: Vector3 = audio.call("listener_position")
		var near: Array = []
		var i := 0
		for e: Variant in _rec.get("emitters", []):
			i += 1
			if typeof(e) != TYPE_DICTIONARY or str(e.get("level", "")) != level_id:
				continue
			var p: Variant = e.get("position_m")
			if typeof(p) != TYPE_ARRAY or (p as Array).size() != 3:
				continue
			var pos := Vector3(float(p[0]), float(p[1]), float(p[2]))
			var d := centre.distance_to(pos)
			if d <= float(e.get("radius_m", 0.0)):
				near.append({"key": "%s#%d" % [e.get("cue", ""), i], "d": d, "e": e, "pos": pos})
		near.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.d < b.d)
		for k in mini(MAX_EMITTERS, near.size()):
			wanted[near[k].key] = near[k]
	for key: String in emitters.keys():
		if not wanted.has(key):
			emitters[key].target = 0.0
	for key: String in wanted:
		if emitters.has(key):
			emitters[key].target = 1.0
			continue
		var w: Dictionary = wanted[key]
		var cue: Dictionary = audio.call("resolve", str(w.e.get("cue", "")))
		if cue.is_empty():
			audio.call("note_missing", str(w.e.get("cue", "")))
			continue
		var stream := _loop_stream(cue)
		if stream == null:
			continue
		var player := AudioStreamPlayer3D.new()
		player.name = "Emitter_%d" % emitters.size()
		VoicePool.configure_3d(player)
		player.playback_type = AudioServer.PLAYBACK_TYPE_STREAM
		player.bus = "Ambience"
		var cls: Dictionary = audio.call("class_distances", str(cue.get("class", "spot")))
		player.unit_size = float(cls.get("unit", 10.0))
		player.max_distance = maxf(float(cls.get("max", 74.0)), float(w.e.get("radius_m", 0.0)))
		player.stream = stream
		player.volume_db = SILENT_DB
		add_child(player)
		player.global_position = w.pos
		player.play()
		emitters[key] = {"player": player, "cue": str(cue.id), "gain": 0.0, "target": 1.0,
			"volume_db": float(cue.get("volume_db", 0.0)) + float(w.e.get("volume_db", 0.0)), "position": w.pos}


## The Ambience duck of the active reasons (audio_mix.duck: dialogue, boss, combat).
func duck_db() -> float:
	return AudioMath.duck_db((audio.get("mix") as Dictionary).get("duck", {}), audio.call("active_ducks"), "Ambience")


func _update_volumes(delta: float) -> void:
	var duck := duck_db()
	for b: Dictionary in beds.duplicate():
		b.gain = move_toward(float(b.gain), float(b.target), delta / BED_FADE_S)
		var p: AudioStreamPlayer = b.player
		if not is_instance_valid(p):
			beds.erase(b)
			continue
		p.volume_db = (float(b.volume_db) + linear_to_db(float(b.gain)) + duck) if float(b.gain) > 0.0001 else SILENT_DB
		if float(b.gain) <= 0.0001 and float(b.target) <= 0.0:
			_free_player(p)
			beds.erase(b)
	for key: String in emitters.keys():
		var e: Dictionary = emitters[key]
		e.gain = move_toward(float(e.gain), float(e.target), delta / EMITTER_FADE_S)
		var p3: AudioStreamPlayer3D = e.player
		if not is_instance_valid(p3):
			emitters.erase(key)
			continue
		p3.volume_db = (float(e.volume_db) + linear_to_db(float(e.gain)) + duck) if float(e.gain) > 0.0001 else SILENT_DB
		if float(e.gain) <= 0.0001 and float(e.target) <= 0.0:
			_free_player(p3)
			emitters.erase(key)


func bed_cues() -> PackedStringArray:
	var out := PackedStringArray()
	for b: Dictionary in beds:
		if float(b.target) > 0.0:
			out.append(str(b.cue))
	return out


func debug_lines() -> PackedStringArray:
	var out := PackedStringArray()
	out.append("AMBIENCE %s  beds %s  emitters %d  spots %d%s" % [set_id if set_id != "" else "-",
		",".join(bed_cues()) if not bed_cues().is_empty() else "-", emitters.size(), spots_played.size(),
		"  flushed" if _now() < flushed_until_s else ""])
	return out
