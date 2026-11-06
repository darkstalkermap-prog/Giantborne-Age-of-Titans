class_name MusicDirector
extends Node
## The adaptive score (P19; plan M6-M9 decision 5, §2.5, §4.3). Child "Music" of the Audio autoload,
## PROCESS_MODE_ALWAYS (it keeps time while a pausing screen is open, ducked).
##
## A music_set plays as one "deck": one AudioStreamPlayer per stem (PLAYBACK_TYPE_STREAM, the Music
## bus, `loop` set on the Ogg resource), all started in the same frame. Bars and segments come from
## the lead stem's (the set's first) playback position. Layer volumes follow the intensity (eased
## over layer_fade_beats); the melody scheduler (MelodyScheduler) picks a variant or a rest at
## every segment boundary and the variants are switched by volume; a set change waits for the next
## bar and cross-fades over crossfade_bars; stingers are one-shot streams on the Music bus that
## duck the stems (audio_mix.duck.stinger) for their length plus 0.5 s.
##
## States (§4.3): silent (process start, level_leaving, after a death's fade, while a level
## registers its samples); context (the title, the end screen, the sandbox: the context's set);
## zone (in a level: the zone's set with intensity layers, the melody scheduler and the silence
## window); boss (boss_engaged for a boss with an audio_region: the intro stinger, then the boss set
## cross-faded in 0.5 s, phase layers at the next bar on boss_phase_changed; back to the zone on
## boss_defeated (victory), boss_yielded and boss_disengaged(fled) (yield), boss_disengaged(left)).
##
## Intensity (every audio_mix.intensity.poll_s; AudioMath.intensity_target): explore, danger or
## combat from the threats around the giant weighed by their size (decision 6). Entering combat
## starts on the next beat with the set's combat_intro stinger (once per combat); leaving combat
## waits combat_hold_s, leaving danger danger_hold_s.
##
## The director uses only its own RandomNumberGenerator; nothing here touches the simulation.

enum State { SILENT, CONTEXT, ZONE, BOSS }
const STATE_NAMES := ["silent", "context", "zone", "boss"]
const STINGER_RELEASE_S := 0.5
const LEVEL_FADE_S := 1.0
const DEATH_FADE_S := 1.5
const BOSS_XFADE_S := 0.5
const START_FADE_S := 1.0
const VARIANT_FADE_S := 0.08
const DEFAULT_LAYER_FADE_BEATS := 2.0
const DEFAULT_CROSSFADE_BARS := 2
const SILENT_DB := -80.0
## The smallest volume change written to a playing player (set_volume).
const VOLUME_STEP_DB := 0.01
## Brain states in which an aware enemy is "engaged" for the music (approach, attack, recover,
## reposition, hold - which covers a brace - and staggered).
const ENGAGED_STATES := [EnemyBrain.AIState.APPROACH, EnemyBrain.AIState.ATTACK, EnemyBrain.AIState.RECOVER,
	EnemyBrain.AIState.REPOSITION, EnemyBrain.AIState.HOLD, EnemyBrain.AIState.STAGGERED]
const FLEEING_STATES := [EnemyBrain.AIState.FLEE, EnemyBrain.AIState.ROUTED]
## Archetypes that always count toward combat (decision 6: bosses and the rival giants).
const SPECIAL_ARCHETYPES := ["boss", "rival_giant"]


## One set playing: a player per stem and their eased gains.
class Deck:
	var set_id := ""
	var rec: Dictionary = {}
	var players: Dictionary = {}     ## stem -> AudioStreamPlayer
	var gains: Dictionary = {}       ## stem -> linear gain now (before the deck fade and ducks)
	var lead := ""
	var loop_s := 0.0
	var bar_s := 0.0
	var beat_s := 0.0
	var segment_s := 0.0
	var master := 0.0                ## the deck's fade gain
	var master_target := 1.0
	var master_rate := 1.0           ## gain per second toward master_target
	var melody_choice := ""          ## the variant heard in this segment ("" = rest)
	var segment := -1
	var last_pos := 0.0
	var boss := false
	var started_s := 0.0             ## the director's clock when the stems started

	## The lead stem's playback position (seconds into the loop).
	func player_position() -> float:
		var p: AudioStreamPlayer = players.get(lead)
		return p.get_playback_position() if p != null and is_instance_valid(p) and p.playing else last_pos

	func free_players() -> void:
		for s: String in players:
			var p: AudioStreamPlayer = players[s]
			if is_instance_valid(p):
				p.stop()
				p.queue_free()
		players.clear()


var audio: Node = null
var state: int = State.SILENT
var context := ""
var intensity := AudioMath.EXPLORE
var boss_id := ""
var boss_phase := 1
var scheduler := MelodyScheduler.new()
var rng := RandomNumberGenerator.new()
## The deck heard now (null in silence) and the decks still fading out.
var deck: Deck = null
var old_decks: Array = []
## A change that waits: {"set", "kind": "bar" | "time", "bar": index, "at_s", "fade_s", "state",
## "boss_id"}; {} when none.
var pending: Dictionary = {}
## Stingers played (cue ids), newest last (tests and the F3 panel).
var stingers: Array = []
## Tests: bar and segment positions come from the director's clock (Audio.clock_s) instead of the
## lead stem's playback position, so a test can advance music time without waiting real seconds
## (the Dummy driver mixes in real time).
var clock_positions := false

var _stinger: AudioStreamPlayer
var _stinger_cue := ""
var _stinger_priority := -1
var _stinger_until_s := -INF
var _last_poll_s := -INF
var _last_high_s := 0.0
var _combat_intro_played := false
var _pending_combat := false
var _pending_combat_beat := -1
var _last_combat_hit_s := -INF
var _last_lesser_hit_s := -INF
var _last_telegraph_s := -INF
var _engaged_bosses: Dictionary = {}
var _end_context := ""
var _fading_to_silence := false
var _zone_record_id := ""
var _layers_override: Dictionary = {}
## P23: with --audio-stats every set start prints one "AUDIO_MUSIC {json}" line (set, state,
## context, the director's clock): the web audio check (tools/web/audio_check.mjs) reads the zone
## set's start as the moment the giant stands in the Hollow.
var _print_sets := false


func setup(p_audio: Node) -> void:
	audio = p_audio
	rng.seed = hash("audio.music")
	_stinger = AudioStreamPlayer.new()
	_stinger.name = "Stinger"
	_stinger.playback_type = AudioServer.PLAYBACK_TYPE_STREAM
	_stinger.bus = "Music"
	_stinger.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_stinger)
	_print_sets = OS.get_cmdline_user_args().has(AudioDirector.STATS_ARG)


## Back to silence at once: every deck and the stinger stopped, the state cleared (tests, reloads).
func reset() -> void:
	if deck != null:
		deck.free_players()
	for d: Deck in old_decks:
		d.free_players()
	deck = null
	old_decks.clear()
	pending = {}
	state = State.SILENT
	context = ""
	intensity = AudioMath.EXPLORE
	boss_id = ""
	boss_phase = 1
	stingers.clear()
	if _stinger != null:
		_stinger.stop()
	_stinger_cue = ""
	_stinger_priority = -1
	_stinger_until_s = -INF
	_last_poll_s = -INF
	_combat_intro_played = false
	_pending_combat = false
	_last_combat_hit_s = -INF
	_last_lesser_hit_s = -INF
	_last_telegraph_s = -INF
	_engaged_bosses.clear()
	_end_context = ""
	_fading_to_silence = false
	_zone_record_id = ""
	_layers_override = {}
	scheduler = MelodyScheduler.new()
	rng.seed = hash("audio.music")
	clock_positions = false


## A new level (Audio detected it): no boss is engaged, no end screen, explore, nothing pending.
func on_level_changed() -> void:
	_engaged_bosses.clear()
	boss_id = ""
	boss_phase = 1
	_end_context = ""
	intensity = AudioMath.EXPLORE
	_pending_combat = false
	_combat_intro_played = false
	pending = {}
	if state == State.BOSS:
		state = State.ZONE


func _now() -> float:
	return float(audio.clock_s) if audio != null else 0.0


func state_name() -> String:
	return STATE_NAMES[state]


func set_id() -> String:
	return deck.set_id if deck != null else ""


# --------------------------------------------------------------------------- inputs from the router

## The giant dealt or took a hit from an enemy; `counts`: the enemy counts toward combat
## (decision 6), else it is a lesser enemy (at most danger).
func note_player_hit(counts: bool) -> void:
	if counts:
		_last_combat_hit_s = _now()
	else:
		_last_lesser_hit_s = _now()


## A telegraph was aimed at the giant (danger for telegraph_recent_s).
func note_telegraph() -> void:
	_last_telegraph_s = _now()


## A discovery, a zone change: exploration is eventful (the silence window restarts or ends).
func note_event() -> void:
	scheduler.note_event(_now())


func on_boss_engaged(id: String) -> void:
	_engaged_bosses[id] = true
	var rec := audio.call("boss_region", id) as Dictionary
	var set_rec := _set_record(str(rec.get("music", "")))
	if set_rec.is_empty():
		return
	boss_id = id
	boss_phase = 1
	var intro := str(set_rec.get("intro", ""))
	var wait_s := 0.0
	if intro != "":
		wait_s = play_stinger(intro, 90)
	pending = {"set": str(set_rec.id), "kind": "time", "at_s": _now() + maxf(wait_s, 0.0),
		"fade_s": BOSS_XFADE_S, "state": State.BOSS, "boss_id": id}


func on_boss_phase_changed(id: String, phase: int) -> void:
	if id != boss_id or (state != State.BOSS and pending.get("boss_id", "") != id):
		return
	if deck != null and deck.boss and phase > boss_phase:
		# the phase layer joins at the next bar
		pending = {"phase": phase, "kind": "bar", "bar": _bar_index(deck), "set": deck.set_id}
	else:
		boss_phase = maxi(boss_phase, phase)


## The boss is over: `stinger` ("victory", "yield" or "" for none), then back to the zone's set.
func on_boss_finished(id: String, stinger: String) -> void:
	_engaged_bosses.erase(id)
	if id != boss_id:
		return
	boss_id = ""
	boss_phase = 1
	if stinger != "":
		play_stinger("mus.stinger." + stinger, 90)
	if pending.get("boss_id", "") == id:
		pending = {}
	if state == State.BOSS:
		state = State.ZONE
		intensity = AudioMath.EXPLORE
		_change_to(_zone_set_id(), "time", BOSS_XFADE_S)


## The giant died: the death stinger and every stem faded out over 1.5 s.
func on_player_died() -> void:
	play_stinger("mus.stinger.death", 100)
	fade_to_silence(DEATH_FADE_S)


func on_slice_completed() -> void:
	_end_context = "end"
	play_stinger("mus.stinger.prologue_end", 100)


## The world's end (P36): the campaign_end context.
func on_campaign_completed() -> void:
	_end_context = "campaign_end"


## Every deck fades out over `seconds`, then silence (level_leaving: 1 s; death: 1.5 s). With
## `hold`, nothing new starts before the fade has ended.
func fade_to_silence(seconds: float, hold := true) -> void:
	pending = {}
	_fading_to_silence = hold
	for d: Deck in ([deck] if deck != null else []) + old_decks:
		d.master_target = 0.0
		d.master_rate = 1.0 / maxf(seconds, 0.01)
	if deck != null:
		old_decks.append(deck)
		deck = null
	state = State.SILENT


## Plays a stinger cue (a one-shot stream on the Music bus) unless a higher-priority one is
## playing; returns its length in seconds (0 when it did not play).
func play_stinger(cue_id: String, priority: int) -> float:
	if audio == null:
		return 0.0
	var cue: Dictionary = audio.call("resolve", cue_id)
	if cue.is_empty():
		audio.call("note_missing", cue_id)
		return 0.0
	if stinger_playing() and priority < _stinger_priority:
		return 0.0
	var files: Array = cue.get("files", [])
	if files.is_empty():
		return 0.0
	var stream := audio.call("load_stream", str(files[0])) as AudioStream
	if stream == null:
		return 0.0
	if stream is AudioStreamOggVorbis:
		(stream as AudioStreamOggVorbis).loop = false
	_stinger.stream = stream
	_stinger.volume_db = float(cue.get("volume_db", 0.0)) + _duck_db(false)
	_stinger.play()
	_stinger_cue = str(cue.get("id", cue_id))
	_stinger_priority = priority
	var length := stream.get_length()
	_stinger_until_s = _now() + length + STINGER_RELEASE_S
	stingers.append(_stinger_cue)
	if stingers.size() > 32:
		stingers.remove_at(0)
	audio.call("log_cue", {"cue": _stinger_cue, "requested": cue_id, "bus": "Music", "pos": Vector3.INF,
		"voice": -2, "priority": priority, "reason": "stinger", "file": str(files[0])})
	return length


## True while a stinger plays (its length plus the 0.5 s release, by the director's clock).
func stinger_playing() -> bool:
	return _now() < _stinger_until_s


# --------------------------------------------------------------------------- the frame

func _process(delta: float) -> void:
	if audio == null or not bool(audio.get("enabled")):
		return
	var now := _now()
	var cfg: Dictionary = (audio.get("mix") as Dictionary).get("intensity", {})
	if now - _last_poll_s >= float(cfg.get("poll_s", 0.25)):
		_last_poll_s = now
		_poll(now, cfg)
	_update_pending(now)
	if deck != null:
		_update_segments(deck, now)
		if _pending_combat and _beat_index(deck) != _pending_combat_beat:
			_pending_combat = false
			_enter_combat()
	_update_gains(delta)


## Every poll_s: the state for the place and the intensity.
func _poll(now: float, cfg: Dictionary) -> void:
	if _fading_to_silence:
		if deck == null and old_decks.is_empty():
			_fading_to_silence = false
		else:
			return
	var want := _desired_state()
	if int(want.state) == State.SILENT:
		if state != State.SILENT or deck != null or not pending.is_empty():
			fade_to_silence(LEVEL_FADE_S, false)
		return
	# A boss fight keeps its music whatever the zone or context says (until it ends or a death).
	var boss_active := state == State.BOSS or int(pending.get("state", -1)) == State.BOSS
	if not boss_active and int(want.state) == State.CONTEXT:
		if state != State.CONTEXT or context != str(want.context) \
				or (set_id() != str(want.set) and pending.get("set", "") != str(want.set)):
			state = State.CONTEXT
			context = str(want.context)
			intensity = AudioMath.EXPLORE
			_change_to(str(want.set), "bar", -1.0)
	elif not boss_active and int(want.state) == State.ZONE:
		if state != State.ZONE or (set_id() != str(want.set) and pending.get("set", "") != str(want.set)):
			var was_zone := state == State.ZONE
			state = State.ZONE
			context = ""
			_change_to(str(want.set), "bar", -1.0)
			if was_zone:
				note_event()
	if state == State.ZONE or state == State.BOSS:
		_update_intensity(now, cfg)
	if deck != null and (state == State.ZONE or state == State.CONTEXT):
		if scheduler.update(now, intensity == AudioMath.EXPLORE):
			pass   # the silence starts: _target_db() fades every stem over fade_s
		if scheduler.wants_reentry():
			pending = {"reenter": true, "kind": "bar", "bar": _bar_index(deck), "set": deck.set_id}


## What should play now: {"state", "set", "context"}.
func _desired_state() -> Dictionary:
	if bool(audio.call("level_loading")) or bool(audio.call("player_dead")):
		return {"state": State.SILENT}
	var level_id := str(audio.get("level_id"))
	if _end_context != "":
		var rec_end: Dictionary = audio.call("context_region", _end_context)
		if not str(rec_end.get("music", "")).is_empty():
			return {"state": State.CONTEXT, "context": _end_context, "set": str(rec_end.music)}
	if level_id == "":
		if GameSession.mode == GameSession.Mode.TITLE:
			var rec_t: Dictionary = audio.call("context_region", "title")
			if not str(rec_t.get("music", "")).is_empty():
				return {"state": State.CONTEXT, "context": "title", "set": str(rec_t.music)}
		return {"state": State.SILENT}
	if level_id == AudioDirector.SANDBOX_LEVEL:
		var rec_s: Dictionary = audio.call("context_region", "sandbox")
		if not str(rec_s.get("music", "")).is_empty():
			return {"state": State.CONTEXT, "context": "sandbox", "set": str(rec_s.music)}
		return {"state": State.SILENT}
	var zone := _zone_set_id()
	if zone == "":
		return {"state": State.SILENT}
	return {"state": State.ZONE, "set": zone}


func _zone_set_id() -> String:
	var rec: Dictionary = audio.call("current_region")
	_zone_record_id = str(rec.get("id", ""))
	_layers_override = rec.get("layers", {}) if typeof(rec.get("layers")) == TYPE_DICTIONARY else {}
	return str(rec.get("music", ""))


func _set_record(set_id_value: String) -> Dictionary:
	var rec := GameData.get_record(set_id_value)
	return rec if str(rec.get("type", "")) == "music_set" else {}


# --------------------------------------------------------------------------- intensity

func _update_intensity(now: float, cfg: Dictionary) -> void:
	var target := AudioMath.intensity_target(intensity_snapshot(), cfg)
	if state == State.BOSS:
		target = AudioMath.COMBAT
	var next := next_intensity(intensity, target, _last_high_s, now, cfg)
	if AudioMath.intensity_rank(target) >= AudioMath.intensity_rank(intensity):
		_last_high_s = now
	if next == intensity:
		return
	if AudioMath.intensity_rank(next) > AudioMath.intensity_rank(AudioMath.EXPLORE):
		note_event()
	if next == AudioMath.COMBAT and deck != null:
		# entering combat starts on the next beat, with the zone's combat intro
		if not _pending_combat:
			_pending_combat = true
			_pending_combat_beat = _beat_index(deck)
		return
	if intensity == AudioMath.COMBAT and next != AudioMath.COMBAT:
		_combat_intro_played = false
	intensity = next


## The intensity after one poll (decision 6, §4.3): rises at once to the target; falls to it only
## after the current level's hold time (combat_hold_s, danger_hold_s) has passed since the target
## last reached the current level (`last_high_s`).
static func next_intensity(current: String, target: String, last_high_s: float, now_s: float,
		cfg: Dictionary) -> String:
	var rc := AudioMath.intensity_rank(current)
	var rt := AudioMath.intensity_rank(target)
	if rt >= rc:
		return target
	var hold := float(cfg.get("combat_hold_s", 6.0)) if current == AudioMath.COMBAT \
		else float(cfg.get("danger_hold_s", 8.0))
	if now_s - last_high_s >= hold - 1e-6:
		return target
	return current


func _enter_combat() -> void:
	intensity = AudioMath.COMBAT
	if _combat_intro_played or deck == null:
		return
	_combat_intro_played = true
	var intro := str(deck.rec.get("combat_intro", ""))
	if intro != "":
		play_stinger(intro, 70)


## The snapshot AudioMath.intensity_target weighs: every enemy within the danger cap of the giant.
func intensity_snapshot() -> Dictionary:
	var p: Node3D = audio.call("player")
	if p == null:
		return {}
	var now := _now()
	var cfg: Dictionary = (audio.get("mix") as Dictionary).get("intensity", {})
	var cap := float(cfg.get("danger_cap_m", 150.0))
	var ppos := p.global_position
	var threats: Array = []
	for n in get_tree().get_nodes_in_group("enemies"):
		var actor := n as Node3D
		if actor == null or not actor.is_inside_tree():
			continue
		var d := Vector2(actor.global_position.x - ppos.x, actor.global_position.z - ppos.z).length()
		if d > cap:
			continue
		var t := threat_of(actor)
		if t.is_empty():
			continue
		t["distance"] = d
		threats.append(t)
	return {"threats": threats, "player_height": float(audio.call("player_height")),
		"scale": float(audio.call("distance_scale")), "boss_engaged": not _engaged_bosses.is_empty(),
		"combat_hit_age_s": now - _last_combat_hit_s, "lesser_hit_age_s": now - _last_lesser_hit_s,
		"telegraph_age_s": now - _last_telegraph_s, "encounter_inside": _inside_active_encounter(ppos)}


## The music's view of one enemy: {"height", "special", "aware", "engaged", "fleeing", "hostile"}
## ({} for a dead or entity-less node).
static func threat_of(actor: Node) -> Dictionary:
	var e: Variant = actor.get("entity")
	if not (e is CombatEntity) or not (e as CombatEntity).is_alive():
		return {}
	var entity := e as CombatEntity
	var brain: Variant = actor.get("brain")
	var aware := false
	var st := -1
	if brain is EnemyBrain:
		aware = (brain as EnemyBrain).aware
		st = (brain as EnemyBrain).state
	var routed := actor.has_method("is_routed") and bool(actor.call("is_routed"))
	return {"height": entity.combatant.height_m, "special": is_special(actor), "aware": aware,
		"engaged": st in ENGAGED_STATES, "fleeing": routed or st in FLEEING_STATES,
		"hostile": entity.team == CombatEntity.Team.ENEMY}


## A boss, a rival giant, a formation member or an engine crew (decision 6) always counts.
static func is_special(actor: Node) -> bool:
	if actor.is_in_group("bosses"):
		return true
	var rec: Variant = actor.get("record")
	if typeof(rec) == TYPE_DICTIONARY and SPECIAL_ARCHETYPES.has(str(rec.get("archetype", ""))):
		return true
	for key in ["formation_id", "engine_id"]:
		var v: Variant = actor.get(key)
		if typeof(v) == TYPE_STRING and v != "":
			return true
	return false


## True when an active encounter with a living, non-fleeing hostile that counts has the giant
## inside its activate radius.
func _inside_active_encounter(ppos: Vector3) -> bool:
	var director := get_tree().get_first_node_in_group(EncounterDirector.GROUP) as EncounterDirector
	if director == null:
		return false
	var h := float(audio.call("player_height"))
	var ratio := float(((audio.get("mix") as Dictionary).get("intensity", {}) as Dictionary).get("lesser_height_ratio", 0.3))
	for enc_id: String in director.encounter_ids():
		if director.encounter_state(enc_id) != EncounterDirector.ACTIVE:
			continue
		var rec := GameData.get_record(enc_id)
		var c: Variant = rec.get("center_m")
		if typeof(c) != TYPE_ARRAY or (c as Array).size() != 3:
			continue
		var centre := Vector3(float(c[0]), float(c[1]), float(c[2]))
		if Vector2(ppos.x - centre.x, ppos.z - centre.z).length() > float(rec.get("activate_radius_m", 0.0)):
			continue
		for member: String in director.members_of(enc_id):
			var node := director.spawned(member)
			if node == null:
				continue
			var t := threat_of(node)
			if not t.is_empty() and bool(t.hostile) and not bool(t.fleeing) \
					and AudioMath.threat_counts(float(t.height), h, bool(t.special), ratio):
				return true
	return false


# --------------------------------------------------------------------------- decks

## Changes to set `set_id_value`: at the next bar of the deck playing (kind "bar"), else at once;
## fade_s < 0 = the set's crossfade_bars.
func _change_to(set_id_value: String, kind: String, fade_s: float) -> void:
	if set_id_value == "":
		fade_to_silence(LEVEL_FADE_S, false)
		return
	if deck == null:
		_start_deck(set_id_value, START_FADE_S if fade_s < 0.0 else fade_s)
		pending = {}
		return
	if deck.set_id == set_id_value and pending.is_empty():
		return
	pending = {"set": set_id_value, "kind": kind, "bar": _bar_index(deck), "at_s": _now(), "fade_s": fade_s}


func _update_pending(now: float) -> void:
	if pending.is_empty():
		return
	var due := false
	match str(pending.get("kind", "")):
		"time":
			due = now >= float(pending.get("at_s", now))
		"bar":
			due = deck == null or _bar_index(deck) != int(pending.get("bar", -1))
	if not due:
		return
	var p := pending
	pending = {}
	if p.has("phase"):
		boss_phase = maxi(boss_phase, int(p.phase))
		return
	if p.has("reenter"):
		if deck != null:
			scheduler.reenter(now, deck.segment <= 0 and _segment_index(deck) == 0)
		return
	var fade := float(p.get("fade_s", -1.0))
	if p.has("state"):
		state = int(p.state)
	if deck != null and deck.set_id == str(p.set) and not p.has("state"):
		return
	_start_deck(str(p.set), fade)


func _start_deck(set_id_value: String, fade_s: float) -> void:
	var rec := _set_record(set_id_value)
	if rec.is_empty():
		return
	var d := Deck.new()
	d.set_id = set_id_value
	d.rec = rec
	d.boss = state == State.BOSS
	d.beat_s = AudioMath.beat_seconds(float(rec.get("bpm", 96)))
	d.bar_s = AudioMath.bar_seconds(float(rec.get("bpm", 96)), int(rec.get("beats_per_bar", 4)))
	d.loop_s = AudioMath.loop_seconds(float(rec.get("bpm", 96)), int(rec.get("beats_per_bar", 4)), int(rec.get("bars", 1)))
	var melody: Dictionary = rec.get("melody", {}) if typeof(rec.get("melody")) == TYPE_DICTIONARY else {}
	d.segment_s = d.bar_s * float(melody.get("segment_bars", rec.get("bars", 1)))
	var stems: Dictionary = rec.get("stems", {})
	for stem: String in stems:
		if d.lead == "":
			d.lead = stem
		var stream := audio.call("load_stream", str(stems[stem])) as AudioStream
		if stream == null:
			continue
		if stream is AudioStreamOggVorbis:
			(stream as AudioStreamOggVorbis).loop = true
		var player := AudioStreamPlayer.new()
		player.name = "%s_%s" % [set_id_value.replace(".", "_"), stem]
		player.playback_type = AudioServer.PLAYBACK_TYPE_STREAM
		player.bus = "Music"
		player.process_mode = Node.PROCESS_MODE_ALWAYS
		player.stream = stream
		player.volume_db = SILENT_DB
		add_child(player)
		d.players[stem] = player
		d.gains[stem] = 0.0
	for stem: String in d.players:
		(d.players[stem] as AudioStreamPlayer).play()
	d.started_s = _now()
	var xfade := fade_s
	if xfade < 0.0:
		xfade = d.bar_s * float(rec.get("crossfade_bars", DEFAULT_CROSSFADE_BARS)) if deck != null else START_FADE_S
	d.master = 0.0
	d.master_target = 1.0
	d.master_rate = 1.0 / maxf(xfade, 0.01)
	if deck != null:
		deck.master_target = 0.0
		deck.master_rate = 1.0 / maxf(xfade, 0.01)
		old_decks.append(deck)
	deck = d
	_combat_intro_played = false
	var segs := maxi(1, int(round(d.loop_s / maxf(d.segment_s, 1e-6))))
	scheduler.configure(melody, rec.get("silence", {}) if typeof(rec.get("silence")) == TYPE_DICTIONARY else {},
		segs, rng, _now())
	if typeof(_zone_melody_override()) == TYPE_DICTIONARY:
		_apply_melody_override(_zone_melody_override())
	d.segment = 0
	d.melody_choice = scheduler.next_segment(_now(), 0)
	d.last_pos = 0.0
	audio.call("log_cue", {"cue": set_id_value, "requested": set_id_value, "bus": "Music", "pos": Vector3.INF,
		"voice": -3, "priority": 0, "reason": state_name(), "file": ""})
	if _print_sets:
		print("AUDIO_MUSIC " + JSON.stringify({"set": set_id_value, "state": state_name(), "context": context,
			"clock_s": snappedf(_now(), 0.01)}))


func _zone_melody_override() -> Variant:
	if state != State.ZONE or _zone_record_id == "":
		return null
	var rec := GameData.get_record(_zone_record_id)
	return rec.get("melody") if typeof(rec.get("melody")) == TYPE_DICTIONARY else null


func _apply_melody_override(m: Dictionary) -> void:
	if m.has("play_loops"):
		scheduler.play_loops = MelodyScheduler._range(m.play_loops, scheduler.play_loops)
	if m.has("rest_loops"):
		scheduler.rest_loops = MelodyScheduler._range(m.rest_loops, scheduler.rest_loops)
	if m.has("max_repeat"):
		scheduler.max_repeat = int(m.max_repeat)
	if m.has("min_phrase_gap_s"):
		scheduler.min_phrase_gap_s = float(m.min_phrase_gap_s)
	if m.has("rest_weight"):
		scheduler.rest_weight = float(m.rest_weight)


## Where deck `d` is in its loop (seconds): the lead stem's playback position, or the director's
## clock since the stems started (clock_positions, tests).
func deck_position(d: Deck) -> float:
	if d == null:
		return 0.0
	if clock_positions:
		return fposmod(_now() - d.started_s, maxf(d.loop_s, 1e-6))
	return d.player_position()


func _bar_index(d: Deck) -> int:
	return AudioMath.segment_index(deck_position(d), d.bar_s) if d != null else -1


func _beat_index(d: Deck) -> int:
	return AudioMath.segment_index(deck_position(d), d.beat_s) if d != null else -1


func _segment_index(d: Deck) -> int:
	return AudioMath.segment_index(deck_position(d), d.segment_s) if d != null else 0


## At every segment boundary of the lead stem: the scheduler's next choice.
func _update_segments(d: Deck, now: float) -> void:
	var pos := deck_position(d)
	var seg := AudioMath.segment_index(pos, d.segment_s)
	var wrapped := pos + 1e-6 < d.last_pos
	d.last_pos = pos
	if seg == d.segment and not wrapped:
		return
	d.segment = seg
	d.melody_choice = scheduler.next_segment(now, seg)


# --------------------------------------------------------------------------- volumes

## The dB a stem of `d` should have now (before ducks and the deck fade).
func _target_db(d: Deck, stem: String) -> float:
	var rec := d.rec
	var layers: Dictionary = rec.get("layers", {})
	var key := AudioMath.COMBAT if d.boss and layers.has(AudioMath.COMBAT) else intensity
	if not layers.has(key):
		key = AudioMath.EXPLORE
	var layer: Dictionary = (layers.get(key, {}) as Dictionary).duplicate()
	if not d.boss and _layers_override.has(key) and typeof(_layers_override[key]) == TYPE_DICTIONARY:
		layer.merge(_layers_override[key], true)
	if d.boss:
		var phases: Dictionary = rec.get("phase_layers", {}) if typeof(rec.get("phase_layers")) == TYPE_DICTIONARY else {}
		for p: String in phases:
			if p.is_valid_int() and int(p) <= boss_phase and typeof(phases[p]) == TYPE_DICTIONARY:
				layer.merge(phases[p], true)
	if not d.boss and scheduler.silent:
		return SILENT_DB
	var melody: Dictionary = rec.get("melody", {}) if typeof(rec.get("melody")) == TYPE_DICTIONARY else {}
	var variants: Array = melody.get("variants", [])
	if variants.has(stem):
		if stem != d.melody_choice or not layer.has("melody"):
			return SILENT_DB
		return float(layer["melody"])
	return float(layer.get(stem, SILENT_DB))


## The Music duck of the active reasons (audio_mix.duck): stinger (not for the stinger itself),
## pause, dialogue.
func _duck_db(for_stems: bool) -> float:
	var reasons: Array = audio.call("active_ducks")
	if not for_stems:
		reasons = reasons.filter(func(r: Variant) -> bool: return r != "stinger")
	return AudioMath.duck_db((audio.get("mix") as Dictionary).get("duck", {}), reasons, "Music")


func _update_gains(delta: float) -> void:
	var duck := _duck_db(true)
	for d: Deck in ([deck] if deck != null else []) + old_decks:
		d.master = move_toward(d.master, d.master_target, d.master_rate * delta)
		var fade_beats := float(d.rec.get("layer_fade_beats", DEFAULT_LAYER_FADE_BEATS))
		var layer_rate := 1.0 / maxf(fade_beats * d.beat_s, 0.01)
		var silence_rate := 1.0 / maxf(scheduler.fade_s, 0.01)
		var melody: Dictionary = d.rec.get("melody", {}) if typeof(d.rec.get("melody")) == TYPE_DICTIONARY else {}
		var variants: Array = melody.get("variants", [])
		for stem: String in d.players:
			var target := db_to_linear(_target_db(d, stem)) if _target_db(d, stem) > SILENT_DB + 0.5 else 0.0
			var rate := layer_rate
			if variants.has(stem):
				rate = 1.0 / VARIANT_FADE_S
			if scheduler.silent and not d.boss:
				rate = silence_rate
			d.gains[stem] = move_toward(float(d.gains[stem]), target, rate * delta)
			var g := float(d.gains[stem]) * d.master
			var p: AudioStreamPlayer = d.players[stem]
			if is_instance_valid(p):
				set_volume(p, (linear_to_db(g) + duck) if g > 0.0001 else SILENT_DB)
	for d: Deck in old_decks.duplicate():
		if d.master <= 0.0001 and d.master_target <= 0.0:
			d.free_players()
			old_decks.erase(d)
	if _stinger != null and _stinger.playing:
		var cue: Dictionary = audio.call("resolve", _stinger_cue) if _stinger_cue != "" else {}
		set_volume(_stinger, float(cue.get("volume_db", 0.0)) + _duck_db(false))


## Sets a player's volume only when it changes by more than VOLUME_STEP_DB (P23). Every volume_db
## set on a playing AudioStreamPlayer replaces its playback's bus details in the AudioServer (an
## allocation the main thread frees a frame later; AudioDirector.mix_barrier), so a steady stem or
## bed sets nothing and a fade sets at most once a frame.
static func set_volume(p: Node, db: float) -> void:
	if absf(float(p.get("volume_db")) - db) > VOLUME_STEP_DB:
		p.set("volume_db", db)


## Lines for the F3 panel.
func debug_lines() -> PackedStringArray:
	var out := PackedStringArray()
	var seg := "-"
	if deck != null:
		seg = "%d (%s)" % [deck.segment, deck.melody_choice if deck.melody_choice != "" else "rest"]
	out.append("MUSIC %s%s set %s  intensity %s  melody seg %s%s  stinger %s  ducks %s" % [state_name(),
		(" " + context) if context != "" else "", set_id() if set_id() != "" else "-", intensity, seg,
		"  silence" if scheduler.silent else "", _stinger_cue if stinger_playing() else "-",
		",".join(PackedStringArray(audio.call("active_ducks"))) if audio != null else "-"])
	return out
