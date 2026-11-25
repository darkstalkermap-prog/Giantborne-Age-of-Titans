class_name CutsceneRules
extends RefCounted
## A cutscene's timeline (A4; the reusable cutscene player's pure part: CutscenePlayer plays it, the tests read it).
## A "cutscene" record (data/cutscenes/, scripts/core/schemas/cutscene_schema.gd) is a shot list in ticks (60 a
## second, from the cutscene's start; deterministic: nothing here reads a clock or a random number):
##   ticks        its length
##   focus        [x, y, z]: where the world streams around while it plays (its shots stand within that ring; y unused)
##   shots        [{"id", "start", "end", "from", "to" ([x, y, z]: the camera's travel), "look_from", "look_to"
##                (what it looks at), "fov", "fov_to", "ease" ("linear", "smooth", "in", "out")}] - one camera at a
##                time, cut at each shot's start
##   lines        [{"start", "end", "text"}]: the subtitles (narration; no voice)
##   cues         [{"tick", "cue", "volume_db"}]: sounds by cue id (non-positional)
##   shakes       [{"tick", "amount", "ticks"}]: the camera shaken from `tick`, fading over `ticks`
##   dust         [{"tick", "at", "size", "count", "speed"}]: dust clouds (DustBurst)
##   rocks        (C1b) [{"tick", "at", "count", "size", "spread" [x, y, z], "fall" [x, y, z], "stagger", "seed"}]:
##                rockfalls - `count` rocks (up to `size` metres) breaking away within `spread` of `at` over `stagger`
##                ticks, thrown off at `fall` m/s and falling (gravity), tumbling, until they lie on the ground
##                (rock_at: a pure function of the tick; the player clamps each to the ground it lands on)
##   actors       [{"id", "kind" ("stoneback": his model; "giant": the player's own giant, at "stage"),
##                "keys": [{"tick", "at", "yaw", "clip", "clip_s" (the clip's time at the key), "rate" (clip
##                seconds a second; 0 holds), "loop"}], "show" [from, to], "on_ground" (its height the ground's in a
##                world), "variant" (a villager's)}] - between keys the place eases, the clip runs on from its key
##   fades        [{"start", "end", "from", "to"}]: black over the picture (1 = black)
##   title        {"start", "end", "text", "sub"}: the title card
## Times outside a shot or line read as none.

const TICK_RATE := 60.0


static func ticks_of(rec: Dictionary) -> int:
	return int(rec.get("ticks", 0))


static func seconds_of(rec: Dictionary) -> float:
	return float(ticks_of(rec)) / TICK_RATE


## The shot playing at `tick` ({} none), the last that has started.
static func shot_at(rec: Dictionary, tick: int) -> Dictionary:
	var best := {}
	for s: Variant in rec.get("shots", []):
		if typeof(s) != TYPE_DICTIONARY:
			continue
		if int(s.get("start", 0)) <= tick and tick < int(s.get("end", 0)):
			best = s
	return best


static func ease_of(u: float, kind: String) -> float:
	u = clampf(u, 0.0, 1.0)
	match kind:
		"linear":
			return u
		"in":
			return u * u
		"out":
			return 1.0 - (1.0 - u) * (1.0 - u)
	return u * u * (3.0 - 2.0 * u)


static func vec3(v: Variant, fallback := Vector3.ZERO) -> Vector3:
	if typeof(v) == TYPE_ARRAY and (v as Array).size() == 3:
		return Vector3(float(v[0]), float(v[1]), float(v[2]))
	return fallback


## The camera at `tick`: {"shot" (its id), "at", "look", "fov"} - its shot's travel eased, the shake added
## ({} outside every shot).
static func camera_at(rec: Dictionary, tick: int) -> Dictionary:
	var s := shot_at(rec, tick)
	if s.is_empty():
		return {}
	var a := int(s.get("start", 0))
	var b := int(s.get("end", a + 1))
	var u := ease_of(float(tick - a) / maxf(float(b - a), 1.0), str(s.get("ease", "smooth")))
	var from := vec3(s.get("from"))
	var at := from.lerp(vec3(s.get("to"), from), u)
	var lf := vec3(s.get("look_from"), at + Vector3.FORWARD)
	var look := lf.lerp(vec3(s.get("look_to"), lf), u)
	var fov := lerpf(float(s.get("fov", 55.0)), float(s.get("fov_to", s.get("fov", 55.0))), u)
	var shake := shake_at(rec, tick)
	if shake > 0.0:
		# (a deterministic wobble: sines of the tick)
		var t := float(tick)
		var off := Vector3(sin(t * 1.9) + 0.5 * sin(t * 4.3), sin(t * 2.7 + 1.0) + 0.5 * sin(t * 5.1), sin(t * 2.3 + 2.0))
		at += off * shake * 0.35
		look += off * shake * 0.6
	return {"shot": str(s.get("id", "")), "at": at, "look": look, "fov": fov}


## The shake's amount at `tick` (each shake fading linearly over its ticks; the strongest counts).
static func shake_at(rec: Dictionary, tick: int) -> float:
	var out := 0.0
	for k: Variant in rec.get("shakes", []):
		if typeof(k) != TYPE_DICTIONARY:
			continue
		var t0 := int(k.get("tick", 0))
		var n := maxi(1, int(k.get("ticks", 30)))
		if tick >= t0 and tick < t0 + n:
			out = maxf(out, float(k.get("amount", 0.0)) * (1.0 - float(tick - t0) / float(n)))
	return out


## The subtitle at `tick` ("" none).
static func line_at(rec: Dictionary, tick: int) -> String:
	for l: Variant in rec.get("lines", []):
		if typeof(l) == TYPE_DICTIONARY and int(l.get("start", 0)) <= tick and tick < int(l.get("end", 0)):
			return str(l.get("text", ""))
	return ""


## The entries of `key` ("cues", "shakes", "dust") whose tick lies in [t0, t1) (each fires once as the timeline
## passes it).
static func due(rec: Dictionary, key: String, t0: int, t1: int) -> Array:
	var out: Array = []
	for c: Variant in rec.get(key, []):
		if typeof(c) == TYPE_DICTIONARY and int(c.get("tick", 0)) >= t0 and int(c.get("tick", 0)) < t1:
			out.append(c)
	return out


## C1b: rock `k` of rockfall `entry` at `tick`: {"visible", "at" (its centre, before any ground), "axis", "spin"
## (radians a second), "size" (m), "s" (seconds since it broke away)} - seeded by the entry's seed and k, so the same
## every run. Not visible before it breaks away.
const ROCK_GRAVITY := 9.8


static func rock_at(entry: Dictionary, k: int, tick: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(entry.get("seed", 1)) * 7919 + k * 104729 + 17
	var spread := vec3(entry.get("spread"), Vector3(20.0, 10.0, 20.0))
	var start := vec3(entry.get("at")) + Vector3(rng.randf_range(-1.0, 1.0) * spread.x, rng.randf_range(-1.0, 1.0) * spread.y,
		rng.randf_range(-1.0, 1.0) * spread.z)
	var delay := rng.randf_range(0.0, float(entry.get("stagger", 60)))
	var v0 := vec3(entry.get("fall")) + Vector3(rng.randf_range(-3.0, 3.0), rng.randf_range(-1.0, 3.0), rng.randf_range(-3.0, 3.0))
	var size := float(entry.get("size", 6.0)) * (1.0 if k == 0 else rng.randf_range(0.3, 0.9))
	var axis := Vector3(rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0)).normalized()
	var spin := rng.randf_range(0.5, 1.8) * (1.0 if rng.randf() < 0.5 else -1.0)
	var s := (float(tick - int(entry.get("tick", 0))) - delay) / TICK_RATE
	if s < 0.0:
		return {"visible": false, "at": start, "axis": axis, "spin": spin, "size": size, "s": 0.0}
	var at := start + v0 * s + Vector3(0.0, -0.5 * ROCK_GRAVITY * s * s, 0.0)
	return {"visible": true, "at": at, "axis": axis if axis.length() > 0.1 else Vector3.UP, "spin": spin, "size": size, "s": s}


## The black over the picture at `tick` (0 none .. 1 black).
static func fade_at(rec: Dictionary, tick: int) -> float:
	for f: Variant in rec.get("fades", []):
		if typeof(f) != TYPE_DICTIONARY:
			continue
		var a := int(f.get("start", 0))
		var b := int(f.get("end", a))
		if tick >= a and tick < b:
			return lerpf(float(f.get("from", 1.0)), float(f.get("to", 0.0)), float(tick - a) / maxf(float(b - a), 1.0))
	return 0.0


## The title card's opacity at `tick` (0 hidden; it fades in over its first second).
static func title_at(rec: Dictionary, tick: int) -> float:
	var t: Variant = rec.get("title")
	if typeof(t) != TYPE_DICTIONARY:
		return 0.0
	var a := int(t.get("start", 0))
	var b := int(t.get("end", a))
	if tick < a or tick >= b:
		return 0.0
	return clampf(float(tick - a) / TICK_RATE, 0.0, 1.0)


## Actor `actor`'s state at `tick`: {"visible", "at", "yaw" (degrees), "clip", "clip_s"} (eased between its keys,
## the clip running on from the key before).
static func actor_at(actor: Dictionary, tick: int) -> Dictionary:
	var keys: Array = actor.get("keys", [])
	var show: Array = actor.get("show", [0, 1 << 30]) if typeof(actor.get("show")) == TYPE_ARRAY else [0, 1 << 30]
	var vis := tick >= int(show[0]) and tick < int(show[1])
	if keys.is_empty():
		return {"visible": vis, "at": Vector3.ZERO, "yaw": 0.0, "clip": "", "clip_s": 0.0}
	var i := 0
	while i + 1 < keys.size() and int((keys[i + 1] as Dictionary).get("tick", 0)) <= tick:
		i += 1
	var k: Dictionary = keys[i]
	var at := vec3(k.get("at"))
	var yaw := float(k.get("yaw", 0.0))
	if i + 1 < keys.size():
		var n: Dictionary = keys[i + 1]
		var span := maxf(float(int(n.get("tick", 0)) - int(k.get("tick", 0))), 1.0)
		var u := ease_of(float(tick - int(k.get("tick", 0))) / span, str(n.get("ease", "smooth")))
		at = at.lerp(vec3(n.get("at"), at), u)
		yaw = lerpf(yaw, float(n.get("yaw", yaw)), u)
	var dt := float(tick - int(k.get("tick", 0))) / TICK_RATE
	var clip_s := float(k.get("clip_s", 0.0)) + dt * float(k.get("rate", 1.0))
	return {"visible": vis, "at": at, "yaw": yaw, "clip": str(k.get("clip", "")), "clip_s": clip_s,
		"loop": bool(k.get("loop", false))}
