class_name AudioMath
extends RefCounted
## The audio engine's pure arithmetic (P19; plan M6-M9 §2.5, §4.3, §4.4): no nodes, no state but
## the cached manifest. Distance scaling and the audibility classes, Godot's logarithmic
## attenuation (the level a cue reaches at the listener), size pitch, the cue fallback chains,
## variant picking and voice stealing, bar and segment boundaries of a music loop, ducking, the
## music's threat-weighted intensity, the threat sting's suppression and the off-camera test.
## Unit-tested in tests/unit/test_audio_math.gd.

## The stage-1 giant's height: every other source's distances scale with height / this (decision 6).
const REFERENCE_HEIGHT_M := 3.6576
const DISTANCE_SCALE_MIN := 1.0
const DISTANCE_SCALE_MAX := 5.2
const SIZE_PITCH_MIN := 0.6
const SIZE_PITCH_MAX := 1.25
const SILENT_DB := -80.0
## AudioStreamPlayer3D.max_db the voice pool uses.
const MAX_DB := 3.0
const MANIFEST_PATH := "res://assets/audio/manifest.json"
## Intensity names, lowest first.
const EXPLORE := "explore"
const DANGER := "danger"
const COMBAT := "combat"
const INTENSITY_ORDER := [EXPLORE, DANGER, COMBAT]

static var _manifest: Dictionary = {}
static var _manifest_loaded := false


# --------------------------------------------------------------------------- distances

## clamp(player height / 3.6576, 1, 5.2): how far every other source carries for this giant.
static func distance_scale(player_height_m: float) -> float:
	return clampf(player_height_m / REFERENCE_HEIGHT_M, DISTANCE_SCALE_MIN, DISTANCE_SCALE_MAX)


## The factor a class's unit and max distances take: `scaled` true -> the distance scale; "sqrt"
## -> its square root (threat cues carry farther and stay directional); "own" -> the player's own
## height / 3.6576 (the giant's own sounds); false -> 1.
static func class_factor(scaled: Variant, scale: float, own_scale: float) -> float:
	if typeof(scaled) == TYPE_STRING:
		if scaled == "sqrt":
			return sqrt(maxf(scale, 0.0))
		if scaled == "own":
			return maxf(own_scale, 0.01)
		return 1.0
	return scale if bool(scaled) else 1.0


## Vector2(unit_size, max_distance) of a mix class {"unit_m", "max_m", "scaled"} at this scale.
static func class_distances(cls: Dictionary, scale: float, own_scale: float) -> Vector2:
	var f := class_factor(cls.get("scaled", true), scale, own_scale)
	return Vector2(float(cls.get("unit_m", 5.0)) * f, float(cls.get("max_m", 40.0)) * f)


## The level (dB) of a sound of `volume_db` heard `distance` metres away through Godot's
## ATTENUATION_LOGARITHMIC model: volume_db - 20 ln(distance / unit), capped at max_db, then
## multiplied by (1 - distance / max_distance) (the fade before silence; brief §4). SILENT_DB at or
## beyond max_distance.
static func level_at(distance: float, unit: float, max_distance: float, volume_db: float,
		max_db := MAX_DB) -> float:
	var d := maxf(distance, 0.0)
	if max_distance > 0.0 and d >= max_distance:
		return SILENT_DB
	var att := volume_db - 20.0 * log(d / maxf(unit, 1e-6) + 1e-5)
	att = minf(att, max_db)
	if max_distance > 0.0:
		var fade := 1.0 - d / max_distance
		att += 20.0 * log(maxf(fade, 1e-9)) / log(10.0)
	return maxf(att, SILENT_DB)


## The volume_db a cue of `volume_db` plays with at `distance` when its class has a level floor
## (`floor_db`, audio_mix.classes.<class>.floor_db; M6 gate): raised so that level_at() reaches at
## least volume_db + floor_db at the listener - the threat alerts (the sting, the aim lock) carry
## to any distance in their range, and their position still pans them (decision 7). The 3D player
## caps the attenuated level at max_db before the max_distance fade, so far out the floor gives way
## to max_db plus the fade. Unchanged when the cue is already that loud or out of range.
static func floored_volume(distance: float, unit: float, max_distance: float, volume_db: float,
		floor_db: float, max_db := MAX_DB) -> float:
	var level := level_at(distance, unit, max_distance, volume_db, max_db)
	var target := volume_db + floor_db
	if level <= SILENT_DB or level >= target:
		return volume_db
	return volume_db + (target - level)


## Pitch factor of a sound made by a body `height_m` tall: (3.6576 / height)^0.25, clamped
## 0.6-1.25, so bigger bodies sound lower.
static func size_pitch(height_m: float) -> float:
	return clampf(pow(REFERENCE_HEIGHT_M / maxf(height_m, 0.05), 0.25), SIZE_PITCH_MIN, SIZE_PITCH_MAX)


# --------------------------------------------------------------------------- cue names

## The family of a cue id: its second part ("hit" for sfx.hit.flesh.light).
static func cue_family(cue_id: String) -> String:
	return cue_id.get_slice(".", 1) if cue_id.count(".") >= 1 else ""


## The fallback chain of one cue (plan §2.5): the cue, then each parent down to three parts, then
## the family's default: sfx.hit.flesh.light -> sfx.hit.flesh -> sfx.hit.default.
static func fallback_chain(cue_id: String) -> PackedStringArray:
	var out := PackedStringArray()
	if cue_id == "":
		return out
	var parts := cue_id.split(".")
	var n := parts.size()
	out.append(cue_id)
	while n > 3:
		n -= 1
		var parent := ".".join(parts.slice(0, n))
		if not out.has(parent):
			out.append(parent)
	if parts.size() >= 2:
		var family_default := "%s.%s.default" % [parts[0], parts[1]]
		if not out.has(family_default):
			out.append(family_default)
	return out


## The candidates a request tries, in order: each explicit candidate with its parents, then the
## first candidate's family default (duplicates dropped).
static func expand_chain(candidates: Array) -> PackedStringArray:
	var out := PackedStringArray()
	var defaults := PackedStringArray()
	for c: Variant in candidates:
		var chain := fallback_chain(str(c))
		for i in chain.size():
			var id := chain[i]
			if id.ends_with(".default") and i == chain.size() - 1 and id != str(c):
				if not defaults.has(id):
					defaults.append(id)
				continue
			if not out.has(id):
				out.append(id)
	for id in defaults:
		if not out.has(id):
			out.append(id)
	return out


## The last part of a dotted id ("heavy_footfall" for ability.heavy_footfall).
static func short_id(id: String) -> String:
	var i := id.rfind(".")
	return id.substr(i + 1) if i >= 0 else id


# --------------------------------------------------------------------------- variants and voices

## A variant index in [0, count): never `last` again when there is another (the director's own RNG).
static func pick_variant(count: int, last: int, rng: RandomNumberGenerator) -> int:
	if count <= 1:
		return 0
	if last < 0 or last >= count:
		return rng.randi_range(0, count - 1)
	var i := rng.randi_range(0, count - 2)
	return i + 1 if i >= last else i


## The voice a request of `priority` may take when every voice is busy: among the voices whose
## priority is at most the request's, the lowest priority, then the oldest (smallest "started").
## voices: [{"priority": int, "started": int}]; -1 when none may be stolen (the request is dropped).
static func steal_index(voices: Array, priority: int) -> int:
	var best := -1
	for i in voices.size():
		var v: Dictionary = voices[i]
		if int(v.get("priority", 0)) > priority:
			continue
		if best < 0:
			best = i
			continue
		var b: Dictionary = voices[best]
		if int(v.priority) < int(b.priority) or (int(v.priority) == int(b.priority) \
				and int(v.get("started", 0)) < int(b.get("started", 0))):
			best = i
	return best


# --------------------------------------------------------------------------- music time

static func beat_seconds(bpm: float) -> float:
	return 60.0 / maxf(bpm, 1e-6)


static func bar_seconds(bpm: float, beats_per_bar: int) -> float:
	return beat_seconds(bpm) * maxi(1, beats_per_bar)


static func loop_seconds(bpm: float, beats_per_bar: int, bars: int) -> float:
	return bar_seconds(bpm, beats_per_bar) * maxi(1, bars)


## The next boundary of `period_s` strictly after `position_s` (seconds into a loop of loop_s),
## as a loop position: a boundary at the loop's end is 0.0 (the start of the next pass).
static func next_boundary(position_s: float, period_s: float, loop_s: float) -> float:
	if period_s <= 0.0:
		return position_s
	var k := floorf(position_s / period_s + 1e-9) + 1.0
	var t := k * period_s
	if loop_s > 0.0 and t >= loop_s - 1e-6:
		return 0.0
	return t


## Seconds from `position_s` until the next boundary of period_s (the loop wraps at loop_s).
static func seconds_to_boundary(position_s: float, period_s: float, loop_s: float) -> float:
	var nb := next_boundary(position_s, period_s, loop_s)
	if nb <= position_s + 1e-9:
		return maxf(loop_s - position_s, 0.0) + nb
	return nb - position_s


## The index of the segment (of segment_s) that contains position_s.
static func segment_index(position_s: float, segment_s: float) -> int:
	if segment_s <= 0.0:
		return 0
	return int(floorf(position_s / segment_s + 1e-9))


# --------------------------------------------------------------------------- mix

## The summed duck of the active reasons on one bus (plan §4.4: audio_mix.duck = reason -> bus -> dB).
static func duck_db(duck: Dictionary, active: Array, bus: String) -> float:
	var total := 0.0
	for reason: Variant in active:
		var row: Variant = duck.get(reason)
		if typeof(row) == TYPE_DICTIONARY:
			total += float(row.get(bus, 0.0))
	return maxf(total, SILENT_DB)


static func linear_to_db_safe(value: float) -> float:
	return SILENT_DB if value <= 0.0001 else maxf(linear_to_db(value), SILENT_DB)


# --------------------------------------------------------------------------- threats

## Decision 7: no threat sting for an attack whose expected damage is under min_damage_fraction of
## the giant's maximum health, or (skip_at_poise_floor) whose attacker's poise ratio sits at the
## 0.25 floor (CombatRules.POISE_SCALE_MIN: it cannot stagger the giant).
static func sting_suppressed(expected_damage: float, max_health: float, poise_ratio: float,
		cfg: Dictionary) -> bool:
	var min_fraction := float(cfg.get("min_damage_fraction", 0.03))
	if max_health > 0.0 and expected_damage < min_fraction * max_health:
		return true
	if bool(cfg.get("skip_at_poise_floor", true)) and poise_ratio <= CombatRules.POISE_SCALE_MIN + 1e-6:
		return true
	return false


## True when `source` lies outside the camera's view for a threat cue: its horizontal angle from
## the camera's (flattened) forward is above fov_deg x factor.
static func off_camera(cam_pos: Vector3, cam_forward: Vector3, source: Vector3, fov_deg: float,
		factor: float) -> bool:
	var f := Vector2(cam_forward.x, cam_forward.z)
	var d := Vector2(source.x - cam_pos.x, source.z - cam_pos.z)
	if f.length_squared() < 1e-9 or d.length_squared() < 1e-9:
		return false
	return absf(rad_to_deg(f.angle_to(d))) > fov_deg * factor


## The expected damage of `action` from `attacker` on `defender` (no crit, no block): the attack's
## power through DamageResolver.mitigate on a crit-free HitEvent built like HitFactory.build. It
## reads nothing random, so it never touches Sim.rng.
static func expected_damage(action: ActionDef, attacker: Combatant, weapon: Dictionary,
		defender: Combatant) -> float:
	if action == null or attacker == null or defender == null:
		return 0.0
	var e := HitEvent.new()
	e.power = action.power
	e.ability_multiplier = action.ability_multiplier
	e.weapon_multiplier = float(weapon.get("damage_multiplier", 1.0)) if action.uses_weapon else 1.0
	e.attacker_stat = attacker.attribute("intellect") if action.category == "magic" else attacker.attribute("strength")
	e.attacker_height_m = attacker.height_m
	e.size_policy = action.size_policy
	e.damage_split = action.damage_split
	e.tags = action.tags
	e.crit = false
	e.flat_penetration = action.flat_penetration
	e.outgoing_damage_mult = attacker.outgoing_damage_mult()
	return float(DamageResolver.mitigate(e, defender).get("total", 0.0))


# --------------------------------------------------------------------------- intensity (§4.3)

## True when an enemy counts toward combat for the music (decision 6): at least
## lesser_height_ratio x the giant's height, or special (a formation member, an engine crew, a
## boss, a rival giant).
static func threat_counts(height_m: float, player_height_m: float, special: bool, ratio: float) -> bool:
	return special or height_m >= ratio * player_height_m - 1e-6


## The intensity a snapshot asks for (before the hold times): "combat" | "danger" | "explore".
## snapshot: {"threats": [{"distance", "height", "special", "aware", "engaged", "fleeing", "hostile"}],
##   "player_height", "scale", "boss_engaged", "combat_hit_age_s", "lesser_hit_age_s",
##   "telegraph_age_s", "encounter_inside"}; cfg: audio_mix.intensity.
static func intensity_target(snapshot: Dictionary, cfg: Dictionary) -> String:
	if bool(snapshot.get("boss_engaged", false)):
		return COMBAT
	var scale := float(snapshot.get("scale", 1.0))
	var h := float(snapshot.get("player_height", REFERENCE_HEIGHT_M))
	var ratio := float(cfg.get("lesser_height_ratio", 0.3))
	var combat_r := float(cfg.get("combat_radius_m", 35.0)) * scale
	var danger_r := minf(float(cfg.get("danger_radius_m", 70.0)) * scale, float(cfg.get("danger_cap_m", 150.0)))
	var lesser_r := float(cfg.get("lesser_danger_m", 40.0))
	if float(snapshot.get("combat_hit_age_s", INF)) <= float(cfg.get("hit_recent_s", 5.0)):
		return COMBAT
	var danger := false
	for t: Dictionary in snapshot.get("threats", []):
		if not bool(t.get("hostile", true)) or bool(t.get("fleeing", false)) or not bool(t.get("aware", false)):
			continue
		var d := float(t.get("distance", INF))
		if threat_counts(float(t.get("height", 1.8)), h, bool(t.get("special", false)), ratio):
			if bool(t.get("engaged", false)) and d <= combat_r:
				return COMBAT
			if d <= danger_r:
				danger = true
		elif d <= lesser_r:
			danger = true
	if danger or bool(snapshot.get("encounter_inside", false)):
		return DANGER
	if float(snapshot.get("lesser_hit_age_s", INF)) <= float(cfg.get("hit_recent_s", 5.0)):
		return DANGER
	if float(snapshot.get("telegraph_age_s", INF)) <= float(cfg.get("telegraph_recent_s", 3.0)):
		return DANGER
	return EXPLORE


static func intensity_rank(intensity: String) -> int:
	return maxi(0, INTENSITY_ORDER.find(intensity))


# --------------------------------------------------------------------------- the manifest

## assets/audio/manifest.json (build_audio.py), read once; {} when it is not there (exported
## builds do not ship it: the checks that read it are build-time checks).
static func manifest() -> Dictionary:
	if not _manifest_loaded:
		_manifest_loaded = true
		_manifest = {}
		if FileAccess.file_exists(MANIFEST_PATH):
			var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST_PATH))
			if typeof(parsed) == TYPE_DICTIONARY:
				_manifest = parsed
	return _manifest


## The manifest entry of a res:// path ({} when unknown).
static func manifest_entry(path: String) -> Dictionary:
	var files: Variant = manifest().get("files", {})
	return files.get(path, {}) if typeof(files) == TYPE_DICTIONARY else {}
