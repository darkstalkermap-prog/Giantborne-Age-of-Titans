extends TestSuite
## P19 (plan M6-M9 §3.1 tests): the audio engine's pure arithmetic - distance scaling and the
## audibility classes, Godot's logarithmic curve (the measured -20 ln(d / unit) at three
## distances, docs/plans/briefs/audio_tech.md §4), size pitch, the cue fallback chains, variant
## picking, voice stealing by priority and age, bar and segment boundaries, ducking, the threat
## sting's suppression and off-camera test, and the threat-weighted intensity (decision 6).

const MIX_ID := "audio_mix.default"


func _mix() -> Dictionary:
	return GameData.get_record(MIX_ID)


func test_distance_scale_follows_the_giant_and_is_clamped() -> void:
	assert_near(AudioMath.distance_scale(3.6576), 1.0, 1e-6, "the stage-1 giant hears at 1x")
	assert_near(AudioMath.distance_scale(1.8), 1.0, 1e-6, "never below 1")
	assert_near(AudioMath.distance_scale(18.9), 18.9 / 3.6576, 1e-6, "a stage-6 giant")
	assert_near(AudioMath.distance_scale(40.0), 5.2, 1e-6, "never above 5.2")


func test_class_distances_scale_by_the_class_rule() -> void:
	var classes: Dictionary = _mix().classes
	var impact := AudioMath.class_distances(classes.impact, 2.0, 2.0)
	assert_near(impact.x, 10.0, 1e-6, "impact unit 5 m x 2")
	assert_near(impact.y, 80.0, 1e-6, "impact max 40 m x 2")
	var threat := AudioMath.class_distances(classes.threat, 4.0, 4.0)
	assert_near(threat.x, 16.0, 1e-6, "threat cues scale by the square root: 8 m x 2")
	assert_near(threat.y, 160.0, 1e-6, "and 80 m x 2")
	var own := AudioMath.class_distances(classes.player, 1.0, 2.5)
	assert_near(own.x, 15.0, 1e-6, "the giant's own sounds follow its own height (6 m x 2.5)")
	assert_near(AudioMath.class_factor(false, 3.0, 3.0), 1.0, 1e-9, "an unscaled class")


func test_logarithmic_curve_matches_the_measured_points() -> void:
	# The brief's measurement (unit 10 m, max_db 3): -12.0 / -39.8 / -67.5 dBFS at 10 / 40 / 160 m,
	# i.e. 0, -27.7 and -55.5 dB relative to 10 m (-20 ln(d / unit)); 2 m is capped at max_db.
	assert_near(AudioMath.level_at(10.0, 10.0, 0.0, 0.0), 0.0, 0.01, "at the unit size")
	assert_near(AudioMath.level_at(40.0, 10.0, 0.0, 0.0), -27.73, 0.05, "four units away")
	assert_near(AudioMath.level_at(160.0, 10.0, 0.0, 0.0), -55.45, 0.05, "sixteen units away")
	assert_near(AudioMath.level_at(2.0, 10.0, 0.0, 0.0), AudioMath.MAX_DB, 1e-6, "close sources stop at max_db")
	# max_distance fades the last part linearly: x (1 - d / max)
	var plain := -20.0 * log(25.0 / 5.0)
	assert_near(AudioMath.level_at(25.0, 5.0, 30.0, 0.0), plain + 20.0 * log(1.0 / 6.0) / log(10.0), 0.05,
		"the fade before max_distance")
	assert_eq(AudioMath.level_at(30.0, 5.0, 30.0, 0.0), AudioMath.SILENT_DB, "silent at max_distance")
	assert_near(AudioMath.level_at(10.0, 10.0, 0.0, -6.0), -6.0, 0.01, "the cue's volume adds")


func test_size_pitch_lowers_bigger_bodies() -> void:
	assert_near(AudioMath.size_pitch(3.6576), 1.0, 1e-6, "the reference height")
	assert_near(AudioMath.size_pitch(1.8), pow(3.6576 / 1.8, 0.25), 1e-6, "a soldier sounds higher")
	assert_near(AudioMath.size_pitch(8.5), pow(3.6576 / 8.5, 0.25), 1e-6, "the Ogre King lower")
	assert_near(AudioMath.size_pitch(0.3), 1.25, 1e-6, "clamped at 1.25")
	assert_near(AudioMath.size_pitch(40.0), 0.6, 1e-6, "clamped at 0.6")


func test_fallback_chains() -> void:
	assert_eq(AudioMath.fallback_chain("sfx.hit.flesh.light"),
		PackedStringArray(["sfx.hit.flesh.light", "sfx.hit.flesh", "sfx.hit.default"]), "variant, subject, family default")
	assert_eq(AudioMath.fallback_chain("sfx.step.giant_s3.soft.cruise"),
		PackedStringArray(["sfx.step.giant_s3.soft.cruise", "sfx.step.giant_s3.soft", "sfx.step.giant_s3",
			"sfx.step.default"]), "every parent down to three parts")
	assert_eq(AudioMath.fallback_chain("sfx.parry"), PackedStringArray(["sfx.parry", "sfx.parry.default"]),
		"a two-part cue falls back to its family default")
	assert_eq(AudioMath.expand_chain(["sfx.ability.heavy_footfall.cast", "sfx.ability.default.cast"]),
		PackedStringArray(["sfx.ability.heavy_footfall.cast", "sfx.ability.heavy_footfall",
			"sfx.ability.default.cast", "sfx.ability.default"]), "explicit candidates, then the family default")
	assert_eq(AudioMath.expand_chain(["sfx.ability.thunder_roar.roar", "sfx.voice.giant.roar"]),
		PackedStringArray(["sfx.ability.thunder_roar.roar", "sfx.ability.thunder_roar", "sfx.voice.giant.roar",
			"sfx.voice.giant", "sfx.ability.default", "sfx.voice.default"]), "the first candidate's default first")
	assert_eq(AudioMath.cue_family("sfx.hit.flesh.light"), "hit", "the family is the second part")
	assert_eq(AudioMath.short_id("ability.heavy_footfall"), "heavy_footfall", "short ids")


func test_variant_picking_never_repeats() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	var last := -1
	var seen := {}
	var repeats := 0
	for i in 300:
		var v := AudioMath.pick_variant(3, last, rng)
		if v == last:
			repeats += 1
		seen[v] = true
		last = v
	assert_eq(repeats, 0, "never the same variant twice in a row")
	assert_eq(seen.size(), 3, "every variant is used")
	assert_eq(AudioMath.pick_variant(1, 0, rng), 0, "a single file is always picked")


func test_voice_stealing_takes_the_lowest_priority_then_the_oldest() -> void:
	var voices := [{"priority": 50, "started": 1}, {"priority": 40, "started": 3}, {"priority": 40, "started": 2},
		{"priority": 90, "started": 0}]
	assert_eq(AudioMath.steal_index(voices, 60), 2, "the oldest of the lowest priority")
	assert_eq(AudioMath.steal_index(voices, 100), 2, "a higher request still takes the lowest")
	assert_eq(AudioMath.steal_index(voices, 40), 2, "equal priority may steal")
	assert_eq(AudioMath.steal_index(voices, 30), -1, "a lower request is dropped")
	assert_eq(AudioMath.steal_index([], 100), -1, "nothing to steal")


func test_bar_and_segment_boundaries() -> void:
	var bar := AudioMath.bar_seconds(96.0, 4)
	assert_near(bar, 2.5, 1e-9, "a 4/4 bar at 96 BPM")
	assert_near(AudioMath.loop_seconds(96.0, 4, 12), 30.0, 1e-9, "zone_96: twelve bars are 30 s")
	assert_near(AudioMath.next_boundary(2.4, bar, 30.0), 2.5, 1e-9, "the next bar")
	assert_near(AudioMath.next_boundary(2.5, bar, 30.0), 5.0, 1e-9, "strictly after the position")
	assert_near(AudioMath.next_boundary(29.9, bar, 30.0), 0.0, 1e-9, "the loop's end wraps to its start")
	assert_near(AudioMath.seconds_to_boundary(29.9, bar, 30.0), 0.1, 1e-6, "0.1 s to the wrap")
	assert_near(AudioMath.seconds_to_boundary(1.0, bar, 30.0), 1.5, 1e-9, "1.5 s to the bar")
	assert_eq(AudioMath.segment_index(9.99, 10.0), 0, "the first segment")
	assert_eq(AudioMath.segment_index(10.0, 10.0), 1, "a boundary starts the next segment")
	assert_eq(AudioMath.segment_index(29.0, 10.0), 2, "the third segment")


func test_ducking_sums_the_active_reasons_per_bus() -> void:
	var duck: Dictionary = _mix().duck
	assert_near(AudioMath.duck_db(duck, ["stinger"], "Music"), -8.0, 1e-9, "stingers duck the music 8 dB")
	assert_near(AudioMath.duck_db(duck, ["stinger", "pause"], "Music"), -18.0, 1e-9, "ducks add")
	assert_near(AudioMath.duck_db(duck, ["dialogue"], "Ambience"), -10.0, 1e-9, "dialogue ducks the ambience")
	assert_near(AudioMath.duck_db(duck, ["boss", "combat"], "Ambience"), -10.0, 1e-9, "boss and combat")
	assert_near(AudioMath.duck_db(duck, ["stinger"], "SFX"), 0.0, 1e-9, "effects are never ducked")
	assert_near(AudioMath.duck_db(duck, [], "Music"), 0.0, 1e-9, "nothing active")


func test_threat_sting_suppression() -> void:
	var cfg: Dictionary = _mix().sting
	assert_true(AudioMath.sting_suppressed(10.0, 1000.0, 1.0, cfg), "1 % of the health: no sting")
	assert_false(AudioMath.sting_suppressed(40.0, 1000.0, 1.0, cfg), "4 %: a sting")
	assert_true(AudioMath.sting_suppressed(400.0, 1000.0, 0.25, cfg), "an attacker at the 0.25 poise floor")
	assert_false(AudioMath.sting_suppressed(400.0, 1000.0, 0.26, cfg), "above the floor")
	assert_false(AudioMath.sting_suppressed(400.0, 1000.0, 0.25, {"min_damage_fraction": 0.03,
		"skip_at_poise_floor": false}), "the floor rule can be switched off")


func test_off_camera_test_uses_the_horizontal_angle() -> void:
	var fwd := Vector3(0, 0, -1)
	assert_false(AudioMath.off_camera(Vector3.ZERO, fwd, Vector3(0, 0, -10), 75.0, 0.55), "straight ahead")
	assert_false(AudioMath.off_camera(Vector3.ZERO, fwd, Vector3(3, 5, -10), 75.0, 0.55), "16.7 degrees off")
	assert_true(AudioMath.off_camera(Vector3.ZERO, fwd, Vector3(10, 0, -1), 75.0, 0.55), "84 degrees off")
	assert_true(AudioMath.off_camera(Vector3.ZERO, fwd, Vector3(0, 0, 10), 75.0, 0.55), "behind")


func test_expected_damage_reads_no_random_number() -> void:
	var attacker := Combatant.from_record("t.soldier", GameData.get_record("enemy.soldier"))
	var giant := Combatant.from_record("t.giant", GameData.get_record("player.giant"), 3.6576)
	var chop := GameData.get_action("ability.soldier_chop")
	var state_before := Sim.rng.state
	var dmg := AudioMath.expected_damage(chop, attacker, GameData.get_record("weapon.soldier_sword"), giant)
	assert_eq(Sim.rng.state, state_before, "Sim.rng untouched (no crit roll)")
	assert_true(dmg > 0.0, "a soldier's chop hurts (%.1f)" % dmg)
	var e := HitEvent.new()
	e.power = chop.power
	e.ability_multiplier = chop.ability_multiplier
	e.weapon_multiplier = float(GameData.get_record("weapon.soldier_sword").get("damage_multiplier", 1.0))
	e.attacker_stat = attacker.attribute("strength")
	e.attacker_height_m = attacker.height_m
	e.size_policy = chop.size_policy
	e.damage_split = chop.damage_split
	e.tags = chop.tags
	e.flat_penetration = chop.flat_penetration
	assert_near(dmg, float(DamageResolver.mitigate(e, giant).total), 1e-6, "the same number DamageResolver gives")


# --------------------------------------------------------------------------- intensity (decision 6)

func _soldier(distance: float, overrides: Dictionary = {}) -> Dictionary:
	var t := {"distance": distance, "height": 1.8, "special": false, "aware": true, "engaged": true,
		"fleeing": false, "hostile": true}
	t.merge(overrides, true)
	return t


func _snapshot(threats: Array, player_height: float, extra: Dictionary = {}) -> Dictionary:
	var s := {"threats": threats, "player_height": player_height,
		"scale": AudioMath.distance_scale(player_height), "boss_engaged": false, "combat_hit_age_s": INF,
		"lesser_hit_age_s": INF, "telegraph_age_s": INF, "encounter_inside": false}
	s.merge(extra, true)
	return s


func test_intensity_weighs_threats_against_the_giant() -> void:
	var cfg: Dictionary = _mix().intensity
	var fleeing: Array = []
	for i in 10:
		fleeing.append(_soldier(8.0 + i, {"fleeing": true}))
	assert_eq(AudioMath.intensity_target(_snapshot(fleeing, 18.9), cfg), AudioMath.EXPLORE,
		"a stage-6 giant among 10 fleeing soldiers stays in explore")
	var wolf := {"distance": 5.0, "height": 2.0, "special": false, "aware": true, "engaged": true,
		"fleeing": false, "hostile": true}
	assert_eq(AudioMath.intensity_target(_snapshot([wolf], 18.9), cfg), AudioMath.DANGER,
		"a 2 m wolf at a stage-6 giant's feet raises at most danger")
	wolf.distance = 45.0
	assert_eq(AudioMath.intensity_target(_snapshot([wolf], 18.9), cfg), AudioMath.EXPLORE,
		"and only within an unscaled 40 m")
	var pikeman := _soldier(30.0, {"special": true})
	assert_eq(AudioMath.intensity_target(_snapshot([pikeman], 18.9), cfg), AudioMath.COMBAT,
		"a formation member raises combat whatever its size")
	assert_eq(AudioMath.intensity_target(_snapshot([_soldier(20.0)], 3.6576), cfg), AudioMath.COMBAT,
		"a soldier engaged within 35 m of a stage-1 giant is combat")
	assert_eq(AudioMath.intensity_target(_snapshot([_soldier(50.0)], 3.6576), cfg), AudioMath.DANGER,
		"aware within 70 m: danger")
	assert_eq(AudioMath.intensity_target(_snapshot([_soldier(20.0, {"engaged": false})], 3.6576), cfg),
		AudioMath.DANGER, "aware but not engaged: danger")
	assert_eq(AudioMath.intensity_target(_snapshot([_soldier(20.0, {"aware": false})], 3.6576), cfg),
		AudioMath.EXPLORE, "unaware enemies do not count")
	assert_eq(AudioMath.intensity_target(_snapshot([_soldier(20.0, {"hostile": false})], 3.6576), cfg),
		AudioMath.EXPLORE, "nor do neutral villagers")
	var far_ogre := {"distance": 160.0, "height": 3.4, "special": false, "aware": true, "engaged": false,
		"fleeing": false, "hostile": true}
	assert_eq(AudioMath.intensity_target(_snapshot([far_ogre], 18.9), cfg), AudioMath.EXPLORE,
		"the danger radius is capped at 150 m")
	far_ogre.distance = 140.0
	far_ogre.height = 6.0
	assert_eq(AudioMath.intensity_target(_snapshot([far_ogre], 18.9), cfg), AudioMath.DANGER,
		"inside the cap a counting threat is danger")


func test_intensity_from_hits_telegraphs_bosses_and_encounters() -> void:
	var cfg: Dictionary = _mix().intensity
	var h := 3.6576
	assert_eq(AudioMath.intensity_target(_snapshot([], h, {"boss_engaged": true}), cfg), AudioMath.COMBAT,
		"an engaged boss")
	assert_eq(AudioMath.intensity_target(_snapshot([], h, {"combat_hit_age_s": 4.0}), cfg), AudioMath.COMBAT,
		"a hit from a counting enemy within 5 s")
	assert_eq(AudioMath.intensity_target(_snapshot([], h, {"combat_hit_age_s": 6.0}), cfg), AudioMath.EXPLORE,
		"not after 5 s")
	assert_eq(AudioMath.intensity_target(_snapshot([], h, {"lesser_hit_age_s": 1.0}), cfg), AudioMath.DANGER,
		"a lesser enemy's hit is danger")
	assert_eq(AudioMath.intensity_target(_snapshot([], h, {"telegraph_age_s": 2.0}), cfg), AudioMath.DANGER,
		"a telegraph aimed at the giant within 3 s")
	assert_eq(AudioMath.intensity_target(_snapshot([], h, {"encounter_inside": true}), cfg), AudioMath.DANGER,
		"inside an active encounter")
	assert_true(AudioMath.threat_counts(1.1, 3.6576, false, 0.3), "0.3 x the giant's height counts")
	assert_false(AudioMath.threat_counts(1.0, 3.6576, false, 0.3), "below it does not")
