class_name MelodyScheduler
extends RefCounted
## The melody scheduler (P19; plan M6-M9 decision 5, §2.5, §4.3): pure, driven by the music
## director at every segment boundary of the lead stem, with the director's own RNG.
##
## It plays the melody for play_loops loops, then rests for rest_loops loops. Inside a played loop
## it picks, per segment, one of the variants or (with weight rest_weight, default 0.15) a rest,
## never the same variant for more than max_repeat segments in a row and never the same phrase
## (variant and segment index) within min_phrase_gap_s. After after_explore_s of exploration with
## no discovery, region or place change, danger or combat (note_event()), it asks for silence:
## every stem fades out over fade_s and the ambience plays alone for length_s; it then re-enters at
## the next bar (the director calls reenter()): drone first, the melody one loop later. A
## discovery, a zone change or danger during the silence re-enters early.

const REST := ""
const DEFAULT_REST_WEIGHT := 0.15

var variants: Array = []
var segments_per_loop := 3
var play_loops := Vector2i(1, 2)
var rest_loops := Vector2i(1, 3)
var max_repeat := 2
var min_phrase_gap_s := 60.0
var rest_weight := DEFAULT_REST_WEIGHT
var after_explore_s := 180.0
var silence_length_s := Vector2(60.0, 120.0)
var fade_s := 8.0
var silence_enabled := false

var rng: RandomNumberGenerator
## The block in progress: playing (true) or resting (false), and its loops left (this loop included).
var playing := true
var loops_left := 1
var last_variant := REST
var repeat_count := 0
## "variant:segment" -> the time (s) the phrase last played.
var phrase_times: Dictionary = {}
## Every choice made: [{"t": s, "segment": i, "choice": variant or ""}] (tests, the F3 panel).
var history: Array = []
## Time of the last event that keeps the music going (a discovery, a zone change, danger).
var last_event_s := 0.0
var silent := false
var silence_started_s := -1.0
var silence_ends_s := -1.0
var reentry_pending := false

var _last_segment := -1


## Reads a set's melody and silence blocks (§2.5) and resets the state at `now_s`.
func configure(melody: Dictionary, silence: Dictionary, p_segments_per_loop: int, p_rng: RandomNumberGenerator,
		now_s: float) -> void:
	rng = p_rng
	variants = (melody.get("variants", []) as Array).duplicate()
	segments_per_loop = maxi(1, p_segments_per_loop)
	play_loops = _range(melody.get("play_loops"), Vector2i(1, 2))
	rest_loops = _range(melody.get("rest_loops"), Vector2i(1, 3))
	max_repeat = maxi(1, int(melody.get("max_repeat", 2)))
	min_phrase_gap_s = float(melody.get("min_phrase_gap_s", 60.0))
	rest_weight = clampf(float(melody.get("rest_weight", DEFAULT_REST_WEIGHT)), 0.0, 1.0)
	silence_enabled = not silence.is_empty()
	after_explore_s = float(silence.get("after_explore_s", 180.0))
	var ls: Variant = silence.get("length_s", [60, 120])
	silence_length_s = Vector2(float(ls[0]), float(ls[1])) if typeof(ls) == TYPE_ARRAY and (ls as Array).size() == 2 \
		else Vector2(60.0, 120.0)
	fade_s = float(silence.get("fade_s", 8.0))
	reset(now_s)


func reset(now_s: float) -> void:
	playing = true
	loops_left = _roll(play_loops)
	last_variant = REST
	repeat_count = 0
	phrase_times.clear()
	history.clear()
	last_event_s = now_s
	silent = false
	silence_started_s = -1.0
	silence_ends_s = -1.0
	reentry_pending = false
	_last_segment = -1


static func _range(v: Variant, fallback: Vector2i) -> Vector2i:
	if typeof(v) == TYPE_ARRAY and (v as Array).size() == 2:
		var lo := int(v[0])
		return Vector2i(lo, maxi(lo, int(v[1])))
	return fallback


func _roll(r: Vector2i) -> int:
	return rng.randi_range(r.x, r.y) if rng != null else r.x


## Called at every segment boundary with the segment's index in the loop (0 .. segments_per_loop
## - 1): the variant stem to hear in it, or REST.
func next_segment(now_s: float, segment: int) -> String:
	if segment == 0 and _last_segment >= 0:
		_end_of_loop()
	_last_segment = segment
	var choice := REST
	if not silent and playing and not variants.is_empty():
		choice = _pick(now_s, segment)
	if choice == REST:
		repeat_count = 0
		last_variant = REST
	else:
		repeat_count = repeat_count + 1 if choice == last_variant else 1
		last_variant = choice
		phrase_times["%s:%d" % [choice, segment]] = now_s
	history.append({"t": now_s, "segment": segment, "choice": choice})
	if history.size() > 256:
		history.remove_at(0)
	return choice


func _end_of_loop() -> void:
	loops_left -= 1
	if loops_left > 0:
		return
	playing = not playing
	loops_left = _roll(play_loops if playing else rest_loops)


func _pick(now_s: float, segment: int) -> String:
	if rng != null and rng.randf() < rest_weight:
		return REST
	var candidates: Array = []
	for v: Variant in variants:
		var name := str(v)
		if name == last_variant and repeat_count >= max_repeat:
			continue
		var key := "%s:%d" % [name, segment]
		if phrase_times.has(key) and now_s - float(phrase_times[key]) < min_phrase_gap_s - 1e-6:
			continue
		candidates.append(name)
	if candidates.is_empty():
		return REST
	return str(candidates[rng.randi_range(0, candidates.size() - 1)]) if rng != null else str(candidates[0])


# --------------------------------------------------------------------------- the silence window

## A discovery, a zone (region or place) change, danger or combat: exploration is eventful again;
## during a silence the music re-enters at the next bar.
func note_event(now_s: float) -> void:
	last_event_s = now_s
	if silent:
		reentry_pending = true


## Advances the silence window. Returns true when silence starts now (the director fades the
## stems out over fade_s).
func update(now_s: float, exploring: bool) -> bool:
	if not exploring:
		note_event(now_s)
		return false
	if silent:
		if now_s >= silence_ends_s:
			reentry_pending = true
		return false
	if silence_enabled and now_s - last_event_s >= after_explore_s:
		silent = true
		silence_started_s = now_s
		silence_ends_s = now_s + (rng.randf_range(silence_length_s.x, silence_length_s.y) if rng != null \
			else silence_length_s.x)
		return true
	return false


## True while the director should hold the music at the next bar to re-enter.
func wants_reentry() -> bool:
	return silent and reentry_pending


## The music comes back (at a bar): the drone now, the melody after one rested loop (the rest
## of the current loop counts only when the music re-enters at the loop's start).
func reenter(now_s: float, at_loop_start := true) -> void:
	silent = false
	reentry_pending = false
	last_event_s = now_s
	playing = false
	loops_left = 1 if at_loop_start else 2
	last_variant = REST
	repeat_count = 0
	_last_segment = -1
