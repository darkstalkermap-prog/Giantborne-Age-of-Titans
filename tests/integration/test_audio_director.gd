extends IntegrationSuite
## P19 (plan M6-M9 §3.1 integration tests, audio enabled): a hit on a dummy, the giant's footfalls
## and the cruise variant, threat cues for a telegraph from behind and from in front, the title's
## context music, a boss engagement and its phase layer, ambience beds, volumes on the buses, the
## focus mute, a pausing screen, and the loading gate holding the first tick until Audio.is_ready().
##
## Music time: the director reads bars from its own clock here (music.clock_positions) and the
## tests advance it with Audio.advance_for_tests(), because the Dummy driver mixes in real time.

const Fx := preload("res://tests/support/test_fixtures.gd")
const MainScript := preload("res://scripts/main.gd")
## P23's assets stand in for the placeholder bed and stinger these tests used (P23 deleted them):
## zone-frame stems (D dorian, 96 BPM, twelve bars of 30 s), the King's frame (104 BPM, twelve bars
## of 27.7 s), the King's one-bar intro (2.43 s) and the calm combat intro.
const MUSIC := "res://assets/audio/music/"
const AMB := "res://assets/audio/ambience/"
const INTRO_S := 2.43
const LEVEL_ID := "level.test_audio"
const GATE_SCENE := "user://test_audio_gate_level.tscn"


func before_each() -> void:
	await super()
	Audio.enable_for_tests()


func after_each() -> void:
	Audio.enable_for_tests(false)
	await super()


# --------------------------------------------------------------------------- fixtures

## Test records: a level with one district, a zone set (drone, two melody variants, pulse, drums),
## a boss set with a phase layer, a title set (it replaces the shipped title context's music), an
## ambience set and the cues they name.
func _install_music() -> void:
	Fx.record_override(LEVEL_ID, {"schema_version": 1, "type": "level", "scene": "", "start_checkpoint": "",
		"districts": [{"id": "arena", "display_name": "Arena", "min_m": [-60, 0, -60], "max_m": [60, 0, 60]}]})
	var zone_layers := {"explore": {"drone": 0, "melody": -2}, "danger": {"drone": 0, "melody": -9, "pulse": -3},
		"combat": {"drone": -4, "melody": -10, "pulse": -5, "drums": 0}}
	Fx.record_override("music.test_zone", {"schema_version": 1, "type": "music_set", "bpm": 96, "beats_per_bar": 4,
		"bars": 12, "frame": "zone_96",
		"stems": {"drone": MUSIC + "drone_calm.ogg", "melody_a": MUSIC + "melody_calm_a.ogg",
			"melody_b": MUSIC + "melody_calm_b.ogg", "pulse": MUSIC + "pulse.ogg", "drums": MUSIC + "combat_drums.ogg"},
		"layers": zone_layers,
		"melody": {"variants": ["melody_a", "melody_b"], "segment_bars": 4, "play_loops": [1, 2], "rest_loops": [1, 3],
			"max_repeat": 2, "min_phrase_gap_s": 60},
		"combat_intro": "mus.stinger.test_combat", "crossfade_bars": 1, "layer_fade_beats": 2})
	Fx.record_override("music.test_boss", {"schema_version": 1, "type": "music_set", "bpm": 104, "beats_per_bar": 4,
		"bars": 12, "frame": "boss_104", "stems": {"drums": MUSIC + "boss_drums.ogg", "theme": MUSIC + "boss_theme.ogg",
			"frenzy": MUSIC + "boss_frenzy.ogg"},
		"layers": {"explore": {"drums": 0, "theme": -2}, "combat": {"drums": 0, "theme": -2}},
		"phase_layers": {"2": {"frenzy": 0}},
		"intro": "mus.stinger.test_intro", "crossfade_bars": 1, "layer_fade_beats": 2})
	Fx.record_override("music.test_title", {"schema_version": 1, "type": "music_set", "bpm": 96, "beats_per_bar": 4,
		"bars": 12, "frame": "zone_96", "stems": {"drone": MUSIC + "drone_ancient.ogg", "theme": MUSIC + "title_theme.ogg"},
		"layers": {"explore": {"drone": 0, "theme": -3}}})
	Fx.record_override("ambience.test_zone", {"schema_version": 1, "type": "ambience_set",
		"beds": [{"cue": "amb.test_bed", "volume_db": 0}], "spots": [{"cue": "amb.test_spot", "weight": 1, "flush": true}],
		"spot_interval_s": [1, 2], "spot_distance_m": [10, 20],
		"reactions": {"flush_radius_m": 40, "flush_s": 8, "flush_cue": "amb.test_spot"}})
	Fx.record_override("audio_region.test_zone", {"schema_version": 1, "type": "audio_region", "level": LEVEL_ID,
		"districts": ["arena"], "context": "", "boss": "", "music": "music.test_zone", "ambience": "ambience.test_zone",
		"priority": 0})
	Fx.record_override("audio_region.test_boss", {"schema_version": 1, "type": "audio_region", "level": "",
		"context": "", "boss": "test.boss_x", "music": "music.test_boss", "ambience": "", "priority": 0})
	Fx.record_override("audio_region.context_title", {"schema_version": 1, "type": "audio_region", "level": "",
		"context": "title", "boss": "", "music": "music.test_title", "ambience": "", "priority": 0})
	Fx.record_override("audio_bank.test", {"schema_version": 1, "type": "audio_bank", "cues": {
		"amb.test_bed": {"files": [AMB + "bed_meadow.ogg"], "bus": "Ambience", "spatial": false, "volume_db": 0.0},
		"amb.test_spot": {"files": [AMB + "spot_lark.ogg"], "bus": "Ambience", "class": "spot", "volume_db": 0.0,
			"retrigger_ms": 0},
		"mus.stinger.test_intro": {"files": [MUSIC + "stinger_boss_ogre_king.ogg"], "bus": "Music", "spatial": false},
		"mus.stinger.test_combat": {"files": [MUSIC + "stinger_combat_calm.ogg"], "bus": "Music", "spatial": false}}})
	Audio.reload_catalog()
	Audio.music.clock_positions = true


## A LevelRoot of the test level (Audio detects it and registers its samples).
func _make_level() -> LevelRoot:
	var lv := LevelRoot.new()
	lv.name = "TestAudioLevel"
	lv.level_id = LEVEL_ID
	world.add_child(lv)
	return lv


func _requested(prefix: String) -> Array:
	var out: Array = []
	for e: Dictionary in Audio.cue_log():
		if str(e.requested).begins_with(prefix):
			out.append(e)
	return out


func _drain() -> void:
	await get_tree().process_frame


func _hit(attacker: CombatEntity, target: CombatEntity, point: Vector3) -> void:
	var e := HitEvent.new()
	e.tick = Sim.tick
	e.instance_id = Sim.new_instance_id()
	e.attacker_id = attacker.entity_id
	e.target_id = target.entity_id
	e.action_id = "ability.light_1"
	e.power = 10.0
	e.attacker_stat = 10.0
	e.attacker_height_m = attacker.combatant.height_m
	e.damage_split = {"physical": 1.0}
	e.tags = PackedStringArray(["Melee"])
	e.attacker_position = attacker.actor.global_position
	e.hit_point = point
	Sim.queue_hit(e)


# --------------------------------------------------------------------------- effects

func test_a_hit_on_a_dummy_logs_a_hit_cue_at_the_hit_point() -> void:
	var p := spawn_player(Vector3(0, 0, 6))
	var d := spawn_dummy(Vector3.ZERO)
	await step_ticks(2)
	Audio.clear_log()
	var point := Vector3(0.1, 1.3, 0.4)
	_hit(p.entity, d.get_node("CombatEntity") as CombatEntity, point)
	await step_ticks(1)
	await _drain()
	var hits := _requested("sfx.hit.")
	assert_eq(hits.size(), 1, "one hit cue: %s" % [Audio.logged_cues()])
	if hits.is_empty():
		return
	assert_eq(str(hits[0].requested), "sfx.hit.wood", "the dummy's material")
	assert_true(str(hits[0].cue).begins_with("sfx.hit."), "resolved within the hit family (%s)" % hits[0].cue)
	assert_eq(str(hits[0].bus), "SFX", "on the SFX bus")
	assert_eq(hits[0].pos, point, "at the hit point")
	assert_true(int(hits[0].voice) >= 0, "a voice plays it")
	var node := Audio.pool.voice_node(int(hits[0].voice))
	assert_true(node is AudioStreamPlayer3D, "a 3D voice")
	if node is AudioStreamPlayer3D:
		var v := node as AudioStreamPlayer3D
		assert_eq(v.playback_type, AudioServer.PLAYBACK_TYPE_DEFAULT, "samples on the web (decision 2)")
		assert_eq(v.attenuation_model, AudioStreamPlayer3D.ATTENUATION_LOGARITHMIC, "logarithmic")
		assert_eq(v.attenuation_filter_db, 0.0, "no distance filter")
		assert_eq(v.doppler_tracking, AudioStreamPlayer3D.DOPPLER_TRACKING_DISABLED, "no doppler")


func test_footfalls_use_the_stage_size_class_and_the_cruise_variant() -> void:
	var p := spawn_player(Vector3.ZERO)
	await step_ticks(2)
	Audio.clear_log()
	p.router.set_injected_move(Vector2(0, 1))
	var stepped: bool = await TestWait.until(self, func() -> bool: return not _requested("sfx.step.").is_empty(), 90)
	assert_true(stepped, "the walking giant's footfall is heard")
	if stepped:
		var e: Dictionary = _requested("sfx.step.")[0]
		assert_eq(str(e.requested), "sfx.step.giant_s1.soft", "the stage-1 size class on soft ground")
		assert_eq(int(e.priority), 50, "the giant's footfall priority")
	Audio.router.set_walk_started(10.5)   # ten and a half seconds of walking so far
	Audio.clear_log()
	var cruising: bool = await TestWait.until(self, func() -> bool: return not _requested("sfx.step.").is_empty(), 60)
	assert_true(cruising, "another footfall")
	if cruising:
		var c: Dictionary = _requested("sfx.step.")[0]
		assert_eq(str(c.requested), "sfx.step.giant_s1.soft.cruise", "the cruise variant after 10 s")
		assert_eq(int(c.priority), 45, "at the cruise priority")
		assert_eq(str(c.reason), "cruise", "a cruising step")
	# A jump and a stomp end the cruise: the next footfall is the full cue again (a new walk starts).
	for ev: String in ["jump", "stomp"]:
		Audio.router.set_walk_started(10.5)
		if ev == "jump":
			Events.ability_started.emit(Sim.tick, p.entity.entity_id, "action.jump", Sim.new_instance_id())
		else:
			Events.area_pulse.emit(Sim.tick, p.entity.entity_id, "ability.heavy_footfall", p.global_position, 6.0)
		await _drain()
		Audio.clear_log()
		# The Dummy driver plays in real time while the headless run is faster, so the earlier steps
		# still hold the cue's voices (the giant's steps are capped at 2, plan §4.4; P21): free them.
		Audio.pool.stop_all()
		var full: bool = await TestWait.until(self, func() -> bool: return not _requested("sfx.step.").is_empty(), 60)
		assert_true(full, "a footfall after the %s" % ev)
		if full:
			assert_eq(str(_requested("sfx.step.")[0].requested), "sfx.step.giant_s1.soft",
				"the full footfall after a %s" % ev)
	p.router.set_injected_move(Vector2.ZERO)


func test_threat_cues_from_behind_and_from_in_front() -> void:
	var p := spawn_player(Vector3.ZERO, 0.0)
	var behind := spawn_soldier(Vector3(0, 0, 12), 0.0, "t.soldier_back")
	var front := spawn_soldier(Vector3(0, 0, -10), 0.0, "t.soldier_front")
	await step_ticks(3)
	var chop := GameData.get_action("ability.soldier_chop")
	var dmg := AudioMath.expected_damage(chop, behind.entity.combatant, behind.weapon, p.entity.combatant)
	assert_true(dmg >= 0.03 * p.entity.combatant.pools.health_max, "a soldier's chop is worth a sting (%.1f)" % dmg)
	Audio.clear_log()
	Events.telegraph_started.emit(Sim.tick, "t.soldier_back", "ability.soldier_chop", p.entity.entity_id, "line",
		behind.global_position, 0.0, 0.3, 2.5, 0.85)
	await _drain()
	assert_eq(_requested("sfx.threat.windup.").size(), 1, "the windup at the attacker")
	assert_eq(_requested("sfx.threat.sting").size(), 1, "and a sting: the attacker is behind the camera")
	if not _requested("sfx.threat.windup.").is_empty():
		assert_eq(str(_requested("sfx.threat.windup.")[0].requested), "sfx.threat.windup.line", "the line shape")
		assert_true((_requested("sfx.threat.windup.")[0].pos as Vector3).distance_to(behind.global_position) < 2.0,
			"at the attacker")
	Audio.clear_log()
	Audio.clock_s += 1.0
	Events.telegraph_started.emit(Sim.tick, "t.soldier_front", "ability.soldier_chop", p.entity.entity_id, "line",
		front.global_position, PI, 0.3, 2.5, 0.85)
	await _drain()
	assert_eq(_requested("sfx.threat.windup.").size(), 1, "the windup in front")
	assert_eq(_requested("sfx.threat.sting").size(), 0, "no sting for a threat in view and near")
	Audio.clear_log()
	Audio.clock_s += 1.0
	Events.telegraph_started.emit(Sim.tick, "t.soldier_front", "ability.soldier_chop", "someone_else", "line",
		front.global_position, PI, 0.3, 2.5, 0.85)
	await _drain()
	assert_eq(_requested("sfx.threat.").size(), 0, "a telegraph aimed elsewhere is not a threat to the giant")


# --------------------------------------------------------------------------- music and ambience

func test_the_title_opens_its_context_music() -> void:
	_install_music()
	GameSession.mode = GameSession.Mode.TITLE
	Audio.advance_for_tests(0.3)
	assert_eq(Audio.music.state_name(), "context", "the context state")
	assert_eq(Audio.music.context, "title", "the title context")
	assert_eq(Audio.music.set_id(), "music.test_title", "the title's set")
	var deck: MusicDirector.Deck = Audio.music.deck
	assert_true(deck != null and deck.players.size() == 2, "one stream player per stem")
	if deck == null:
		return
	for stem: String in deck.players:
		var pl: AudioStreamPlayer = deck.players[stem]
		assert_eq(pl.playback_type, AudioServer.PLAYBACK_TYPE_STREAM, "%s is a stream (decision 2)" % stem)
		assert_eq(str(pl.bus), "Music", "%s on the Music bus" % stem)
		assert_true(pl.playing, "%s plays" % stem)
		assert_true((pl.stream as AudioStreamOggVorbis).loop, "%s loops (set on the resource)" % stem)
	Audio.advance_for_tests(1.2)
	assert_near(float(deck.gains.drone), 1.0, 0.01, "the drone at its explore level")
	assert_true(float(deck.gains.theme) > 0.5, "the theme at -3 dB")
	GameSession.mode = GameSession.Mode.SANDBOX
	Audio.advance_for_tests(0.3)
	assert_eq(Audio.music.state_name(), "silent", "no title, no level: silence")


func test_zone_music_boss_set_after_its_intro_and_a_phase_layer_at_the_next_bar() -> void:
	_install_music()
	_make_level()
	spawn_player(Vector3.ZERO)
	await step_ticks(1)
	Audio.advance_for_tests(0.6)
	assert_eq(Audio.level_id, LEVEL_ID, "the level is detected")
	assert_eq(Audio.music.state_name(), "zone", "zone music")
	assert_eq(Audio.music.set_id(), "music.test_zone", "the district's set")
	assert_eq(Audio.ambience.set_id, "ambience.test_zone", "the district's ambience")
	assert_eq(Audio.ambience.bed_cues(), PackedStringArray(["amb.test_bed"]), "its bed plays")
	var bed_player: AudioStreamPlayer = Audio.ambience.beds[0].player
	assert_eq(bed_player.playback_type, AudioServer.PLAYBACK_TYPE_STREAM, "beds are streams")
	assert_eq(str(bed_player.bus), "Ambience", "on the Ambience bus")
	Events.boss_engaged.emit(Sim.tick, "test.boss_x")
	await _drain()
	assert_true(Audio.music.stingers.has("mus.stinger.test_intro"), "the intro stinger plays")
	Audio.advance_for_tests(INTRO_S - 0.3)
	assert_eq(Audio.music.set_id(), "music.test_zone", "the zone set holds through the one-bar intro")
	Audio.advance_for_tests(0.6)
	assert_eq(Audio.music.set_id(), "music.test_boss", "the boss set after its intro")
	assert_eq(Audio.music.state_name(), "boss", "the boss state")
	assert_true(Audio.active_ducks().has("boss"), "the boss ducks the ambience")
	var deck: MusicDirector.Deck = Audio.music.deck
	var pos := Audio.music.deck_position(deck)
	var to_bar := AudioMath.seconds_to_boundary(pos, deck.bar_s, deck.loop_s)
	Events.boss_phase_changed.emit(Sim.tick, "test.boss_x", 2)
	await _drain()
	assert_eq(Audio.music.boss_phase, 1, "the phase waits for the next bar")
	Audio.advance_for_tests(maxf(to_bar - 0.05, 0.0))
	assert_eq(Audio.music.boss_phase, 1, "still phase 1 just before the bar")
	assert_near(float(deck.gains.frenzy), 0.0, 1e-6, "the frenzy layer silent")
	Audio.advance_for_tests(0.2)
	assert_eq(Audio.music.boss_phase, 2, "phase 2 at the bar")
	Audio.advance_for_tests(1.0)
	assert_true(float(deck.gains.frenzy) > 0.5, "its layer comes in")
	Events.boss_defeated.emit(Sim.tick, "test.boss_x")
	await _drain()
	Audio.advance_for_tests(0.2)
	assert_eq(Audio.music.state_name(), "zone", "back to the zone after the victory")
	assert_true(Audio.music.stingers.has("mus.stinger.victory") and str(Audio.cue_log().back().requested) != "",
		"the victory stinger")
	Audio.advance_for_tests(0.6)
	assert_eq(Audio.music.set_id(), "music.test_zone", "the zone's set again")


## M8 release (R1): the endings of a boss fight that are not a kill - Harrok's talk ending chosen while his duel
## is engaged (boss_disengaged "yielded_talk", MootArena) and a drive-out ("fled") - end the boss music with the
## yield stinger, never the victory's; a giant who walked out ("left") hears none. The talk ending mid-duel
## played the victory stinger (boss_defeated) before; before that it left the boss music on.
func test_a_boss_fight_ended_without_a_kill_ends_its_music_with_the_yield_stinger() -> void:
	_install_music()
	_make_level()
	spawn_player(Vector3.ZERO)
	await step_ticks(1)
	Audio.advance_for_tests(0.6)
	for row: Array in [["yielded_talk", "mus.stinger.yield"], ["fled", "mus.stinger.yield"], ["left", ""]]:
		var reason := str(row[0])
		Events.boss_engaged.emit(Sim.tick, "test.boss_x")
		await _drain()
		Audio.advance_for_tests(INTRO_S + 0.3)
		assert_eq(Audio.music.state_name(), "boss", "%s: the boss set plays" % reason)
		Audio.music.stingers.clear()
		Events.boss_disengaged.emit(Sim.tick, "test.boss_x", reason)
		await _drain()
		Audio.advance_for_tests(0.2)
		assert_eq(Audio.music.state_name(), "zone", "%s: back to the zone" % reason)
		assert_eq(Audio.music.stingers, [str(row[1])] if str(row[1]) != "" else [],
			"%s: %s" % [reason, "the %s" % row[1] if str(row[1]) != "" else "no stinger"])
		assert_false(Audio.music.stingers.has("mus.stinger.victory"), "%s: never the victory stinger" % reason)
		Audio.advance_for_tests(3.0)


func test_volumes_reach_the_buses() -> void:
	var music_bus := AudioServer.get_bus_index("Music")
	assert_true(music_bus >= 0 and AudioServer.get_bus_index("SFX") >= 0 and AudioServer.get_bus_index("UI") >= 0
		and AudioServer.get_bus_index("Ambience") >= 0, "the four buses exist")
	assert_eq(AudioServer.get_bus_send(music_bus), &"Master", "they send to Master")
	assert_eq(AudioServer.get_bus_effect_count(music_bus), 0, "with no effects")
	Settings.set_value("volume_music", 0.5, false)
	assert_near(AudioServer.get_bus_volume_db(music_bus), -9.0 + linear_to_db(0.5), 0.01, "the mix level plus the setting")
	Settings.set_value("volume_sfx", 0.0, false)
	assert_true(AudioServer.is_bus_mute(AudioServer.get_bus_index("SFX")), "0 mutes")
	Settings.set_value("volume_master", 0.25, false)
	assert_near(Audio.master_db(), linear_to_db(0.25), 0.01, "Master follows its setting")
	for key: String in ["volume_music", "volume_sfx", "volume_master"]:
		Settings.set_value(key, Settings.DEFAULTS[key], false)
	assert_false(AudioServer.is_bus_mute(AudioServer.get_bus_index("SFX")), "unmuted again")
	assert_near(AudioServer.get_bus_volume_db(music_bus), -9.0 + linear_to_db(0.8), 0.01, "the default music volume")


func test_focus_loss_mutes_master_and_focus_returns_it() -> void:
	Audio.notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	Audio.advance_for_tests(0.1)
	assert_true(Audio.master_db() < -20.0 and Audio.master_db() > -80.0, "ramping down (%.1f dB)" % Audio.master_db())
	Audio.advance_for_tests(0.15)
	assert_true(Audio.master_db() <= -79.9, "Master at -80 dB within 0.2 s")
	Audio.notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
	Audio.advance_for_tests(0.25)
	assert_near(Audio.master_db(), 0.0, 0.01, "restored on focus in")
	Audio.notification(Window.NOTIFICATION_WM_WINDOW_FOCUS_OUT)
	Audio.advance_for_tests(0.25)
	assert_true(Audio.master_db() <= -79.9, "the web's window focus-out mutes too")
	Audio.notification(Window.NOTIFICATION_WM_WINDOW_FOCUS_IN)
	Audio.advance_for_tests(0.25)
	Settings.set_value("mute_when_unfocused", false, false)
	Audio.notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	Audio.advance_for_tests(0.25)
	assert_near(Audio.master_db(), 0.0, 0.01, "no mute when the setting is off")
	Audio.notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
	Settings.set_value("mute_when_unfocused", true, false)


func test_a_pausing_screen_pauses_effects_and_ducks_the_music() -> void:
	_install_music()
	_make_level()
	var p := spawn_player(Vector3.ZERO)
	await step_ticks(1)
	Audio.advance_for_tests(2.0)
	assert_eq(Audio.music.set_id(), "music.test_zone", "zone music plays")
	var drone: AudioStreamPlayer = Audio.music.deck.players.drone
	var before := drone.volume_db
	# a long effect (the 0.72 s tree swing at a quarter speed lasts 2.9 s), so it still plays when the menu opens
	Fx.record_override("audio_bank.test", {"cues": {"sfx.swing.test_long": {"files": ["res://assets/audio/sfx/combat/swing_tree_heavy_1.wav"],
		"bus": "SFX", "class": "impact", "pitch": 0.25, "volume_db": 0.0}}})
	Audio.reload_catalog()
	var v := Audio.play("sfx.swing.test_long", p.global_position + Vector3(2, 1, 0), {"reason": "test"})
	assert_true(v >= 0, "an effect plays")
	var sfx := Audio.pool.voice_node(v) as AudioStreamPlayer3D
	await step_ticks(1)   # a 3D player hands its playback to the AudioServer on its next physics frame
	var stack := ScreenStack.new()
	add_child(stack)
	var screen := UiScreen.new()   # the base screen pauses the game, like the pause menu
	stack.push(screen)
	assert_true(get_tree().paused, "a pausing screen pauses the tree")
	assert_eq(str(Audio.router.queue.back().chain[0]) if not Audio.router.queue.is_empty() else "", "sfx.ui.open",
		"the screen's open cue is requested")
	assert_true(sfx != null and not sfx.can_process(), "the effect voice is pausable and paused")
	assert_true(sfx != null and sfx.get_stream_paused(), "its stream is paused with the tree")
	await get_tree().process_frame
	assert_true(Audio.active_ducks().has("pause"), "the pause duck is active")
	Audio.advance_for_tests(1.0)
	assert_near(drone.volume_db, before - 10.0, 0.5, "the music ducks 10 dB (%.1f -> %.1f)" % [before, drone.volume_db])
	assert_true(drone.playing and drone.can_process(), "the music keeps playing (PROCESS_MODE_ALWAYS)")
	stack.close_all()
	assert_eq(str(Audio.router.queue.back().chain[0]) if not Audio.router.queue.is_empty() else "", "sfx.ui.close",
		"and its close cue")
	stack.queue_free()
	await get_tree().process_frame
	assert_false(get_tree().paused, "unpaused")
	Audio.advance_for_tests(1.0)
	assert_near(drone.volume_db, before, 0.5, "the duck lifts")


# --------------------------------------------------------------------------- the loading gate

func test_the_loading_gate_holds_the_first_tick_until_audio_is_ready() -> void:
	_install_music()
	var lv := LevelRoot.new()
	lv.name = "GateLevel"
	lv.level_id = LEVEL_ID
	var packed := PackedScene.new()
	packed.pack(lv)
	lv.free()
	assert_eq(ResourceSaver.save(packed, GATE_SCENE), OK, "the gate's test level is saved")
	GameSession.level_override = GATE_SCENE
	var expected := Audio.sample_paths_for(LEVEL_ID).size()
	assert_true(expected >= 5, "the level has samples to register (%d)" % expected)
	# about 5 paused frames of registration, whatever the size of the shipped banks (P21 added 209 files)
	var per_frame := maxi(2, ceili(expected / 5.0))
	Audio.registration_files_per_frame_cap = per_frame
	var tick0 := Sim.tick
	var main := MainScript.new()
	add_child(main)
	await get_tree().process_frame
	var held := 0
	while not Audio.is_ready() and held < 60:
		assert_true(get_tree().paused, "the tree stays paused while samples register (frame %d)" % held)
		assert_eq(Sim.tick, tick0, "no simulation tick before the samples are ready")
		held += 1
		await get_tree().process_frame
	assert_true(Audio.is_ready(), "every sample registered")
	assert_true(held >= expected / per_frame - 1, "the gate held for the registration (%d frames, %d files)" % [held, expected])
	assert_eq(int(Audio.stats.registered), expected, "each file registered once")
	await get_tree().process_frame
	await get_tree().process_frame
	assert_false(get_tree().paused, "the gate opens")
	assert_true(Sim.tick > tick0, "and the simulation runs")
	main.queue_free()
	await get_tree().process_frame
	GameSession.level_override = ""
	DirAccess.remove_absolute(ProjectSettings.globalize_path(GATE_SCENE))
