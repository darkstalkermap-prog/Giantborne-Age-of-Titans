extends IntegrationSuite
## P23 (plan M6-M9 §3.5 tests, §4.3): the Valley's ambience on its shipped records and Oggs, audio
## on.
##   - the bed follows the zone with its 15 m hysteresis: 5 m into the Old Wood the Hollow's meadow
##     plays on, 20 m in the forest bed fades in and the meadow's fades out over 3 s, and 5 m back
##     into the Hollow the forest stays;
##   - the meadow's spots play from its own list within its distance band (10-28 m, times the
##     giant's distance scale) around the listener;
##   - a giant's stomp near the listener flushes the birds: the flush cue once, no lark while the
##     stomps go on, larks again after them; a stomp far away flushes nothing;
##   - of the emitters within reach only the nearest two play, and they follow the giant.
## Time comes from Audio.advance_for_tests(); the spot voices are freed between steps, because the
## Dummy driver plays in real time while the test runs faster.

const VALLEY := "level.valley"
## Giant's Hollow's centre, and points across its southern edge (z = 100 in level space).
const HOLLOW := Vector3(-145, 0, 150)
const WOOD_5 := Vector3(-145, 0, 95)
const WOOD_20 := Vector3(-145, 0, 80)
const HOLLOW_5 := Vector3(-145, 0, 105)
const MEADOW_SPOTS := ["amb.lark", "amb.cricket", "amb.gust"]
const Fx := preload("res://tests/support/test_fixtures.gd")


func before_each() -> void:
	await super()
	Audio.enable_for_tests()


func after_each() -> void:
	Audio.enable_for_tests(false)
	await super()


func _valley(at: Vector3) -> GiantPlayer:
	var lv := LevelRoot.new()
	lv.name = "Valley"
	lv.level_id = VALLEY
	world.add_child(lv)
	var p := spawn_player(at)
	Audio.advance_for_tests(1.0, 0.05)
	return p


## The ambience cues played meanwhile (the cue log), with `reason`.
func _played(reason: String) -> Array:
	var out: Array = []
	for e: Dictionary in Audio.cue_log():
		if str(e.get("reason", "")) == reason:
			out.append(e)
	return out


## `seconds` of ambience in 2.5 s steps, the spot voices freed after each (real-time playback).
func _run(seconds: float) -> void:
	var left := seconds
	while left > 0.0:
		Audio.advance_for_tests(minf(2.5, left), 0.5)
		Audio.pool.stop_all()
		left -= 2.5


func _bed_count(cue: String) -> int:
	var n := 0
	for b: Dictionary in Audio.ambience.beds:
		if str(b.cue) == cue:
			n += 1
	return n


func test_the_bed_follows_the_zone_with_15_m_of_hysteresis() -> void:
	var p := _valley(HOLLOW)
	assert_eq(Audio.ambience.set_id, "ambience.meadow", "the Hollow's meadow")
	assert_eq(Audio.ambience.bed_cues(), PackedStringArray(["amb.bed_meadow"]), "its bed")
	var bed: AudioStreamPlayer = Audio.ambience.beds[0].player
	assert_eq(bed.playback_type, AudioServer.PLAYBACK_TYPE_STREAM, "a stream")
	assert_true((bed.stream as AudioStreamOggVorbis).loop, "looping")
	Audio.advance_for_tests(AmbienceDirector.BED_FADE_S, 0.1)
	assert_near(float(Audio.ambience.beds[0].gain), 1.0, 1e-6, "faded in over 3 s")
	p.global_position = WOOD_5
	Audio.advance_for_tests(1.0, 0.05)
	assert_eq(str(Audio.region_at(WOOD_5).get("id", "")), "audio_region.valley_wood", "5 m past the edge is the Old Wood")
	assert_eq(Audio.ambience.set_id, "ambience.meadow", "but the meadow plays on within 15 m of the edge")
	p.global_position = WOOD_20
	Audio.advance_for_tests(0.3, 0.05)
	assert_eq(Audio.ambience.set_id, "ambience.forest", "20 m in: the forest")
	assert_eq(Audio.ambience.bed_cues(), PackedStringArray(["amb.bed_forest"]), "its bed comes in")
	assert_eq(_bed_count("amb.bed_meadow"), 1, "the meadow's bed fades out")
	Audio.advance_for_tests(AmbienceDirector.BED_FADE_S - 0.5, 0.05)
	assert_eq(_bed_count("amb.bed_meadow"), 1, "still fading before 3 s")
	Audio.advance_for_tests(0.8, 0.05)
	assert_eq(_bed_count("amb.bed_meadow"), 0, "gone after the 3 s fade")
	p.global_position = HOLLOW_5
	Audio.advance_for_tests(1.0, 0.05)
	assert_eq(Audio.ambience.set_id, "ambience.forest", "5 m back into the Hollow the forest stays")


func test_spots_stay_in_their_band_and_a_stomp_flushes_the_birds() -> void:
	var p := _valley(HOLLOW)
	assert_eq(Audio.ambience.set_id, "ambience.meadow", "the meadow")
	Audio.clear_log()
	_run(45.0)
	var spots := _played("spot")
	assert_true(spots.size() >= 4, "spots play every 5-12 s (%d in 45 s)" % spots.size())
	var band := Vector2(10.0, 28.0) * Audio.distance_scale()
	var centre := Audio.listener_position()
	var outside := PackedStringArray()
	for e: Dictionary in spots:
		assert_true(MEADOW_SPOTS.has(str(e.requested)), "%s is one of the meadow's spots" % e.requested)
		var d := Vector2((e.pos as Vector3).x - centre.x, (e.pos as Vector3).z - centre.z).length()
		if d < band.x - 0.01 or d > band.y + 0.01:
			outside.append("%s at %.1f m" % [e.requested, d])
	assert_true(outside.is_empty(), "every spot within %.0f-%.0f m of the listener: %s" % [band.x, band.y, outside])
	# a stomp far away flushes nothing
	var far := p.global_position + Vector3(200, 0, 0)
	Events.area_pulse.emit(Sim.tick, p.entity.entity_id, "ability.heavy_footfall", far, 6.0)
	await get_tree().process_frame
	assert_eq(Audio.ambience.flushes, 0, "a stomp 200 m away flushes no bird")
	# stomps beside the giant: the birds take flight once, and no lark sings while they go on
	Audio.clear_log()
	for i in 9:
		Events.area_pulse.emit(Sim.tick, p.entity.entity_id, "ability.heavy_footfall", p.global_position, 6.0)
		_run(5.0)
	assert_eq(Audio.ambience.flushes, 1, "one flush while the stomps go on")
	var flushed := _played("flush")
	assert_eq(flushed.size(), 1, "the flush cue once")
	if not flushed.is_empty():
		assert_eq(str(flushed[0].requested), "amb.birds_flush", "the birds take flight")
	var during := _played("spot")
	var larks := during.filter(func(e: Dictionary) -> bool: return str(e.requested) == "amb.lark")
	assert_true(during.size() >= 3, "other spots go on (%d)" % during.size())
	assert_eq(larks.size(), 0, "no lark while the giant stomps")
	Audio.clear_log()
	_run(45.0)
	var after := _played("spot").filter(func(e: Dictionary) -> bool: return str(e.requested) == "amb.lark")
	assert_true(after.size() >= 1, "the larks come back (%d)" % after.size())


func test_only_the_nearest_two_emitters_play() -> void:
	# three emitters around the Hollow's centre, 10, 20 and 30 m east of it, all within reach
	var em := []
	for i in 3:
		em.append({"cue": "amb.forge_fire" if i != 1 else "amb.river_loop", "level": VALLEY,
			"position_m": [HOLLOW.x + 10.0 * (i + 1), 0, HOLLOW.z], "radius_m": 50})
	Fx.record_override("ambience.meadow", {"emitters": em})
	var p := _valley(HOLLOW)
	assert_eq(Audio.ambience.emitters.size(), 2, "two of the three play")
	var xs := []
	for key: String in Audio.ambience.emitters:
		var e: Dictionary = Audio.ambience.emitters[key]
		xs.append(roundi((e.position as Vector3).x - HOLLOW.x))
		var player: AudioStreamPlayer3D = e.player
		assert_eq(player.playback_type, AudioServer.PLAYBACK_TYPE_STREAM, "an emitter is a stream")
		assert_eq(str(player.bus), "Ambience", "on the Ambience bus")
	xs.sort()
	assert_eq(xs, [10, 20], "the nearest two")
	# 45 m east: the far one is the nearest now and the first the third, so it fades out
	p.global_position = HOLLOW + Vector3(45, 0, 0)
	Audio.advance_for_tests(0.3, 0.05)
	var targets := {}
	for key: String in Audio.ambience.emitters:
		var e: Dictionary = Audio.ambience.emitters[key]
		targets[roundi((e.position as Vector3).x - HOLLOW.x)] = float(e.target)
	assert_eq(float(targets.get(30, -1.0)), 1.0, "the far one joins")
	assert_eq(float(targets.get(20, -1.0)), 1.0, "the middle one stays")
	assert_eq(float(targets.get(10, 0.0)), 0.0, "the first fades out")
	Audio.advance_for_tests(AmbienceDirector.EMITTER_FADE_S + 0.2, 0.05)
	assert_eq(Audio.ambience.emitters.size(), 2, "two again after the fade")
