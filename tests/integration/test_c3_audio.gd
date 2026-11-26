extends IntegrationSuite
## C3 (decisions C3-1, C3-2, C3-3): the effects the owner did not hear on the Web.
##   * the buses are made by raising the bus count, in order (Master 0, then Music, Ambience, SFX, UI, each
##     sent to Master), and the audio engine never calls AudioServer.add_bus (on the web it reorders the
##     page's copy of the bus graph and unplugs Master from the speakers: every sample was silent);
##   * a cue heard within its class's unit distance plays on a near voice (a 2D player on the SFX bus) at the
##     level the 3D model gives it there; one farther out stays a 3D voice; a threat cue stays directional
##     however near;
##   * the giant's swing is pitched by his size (lower at stage 6 than at stage 1) and, from stage 4, a mass
##     layer plays under it, louder at stage 8 than at stage 4;
##   * a blow the giant lands plays its impact by what it struck, at the giant (a near voice).
## The Web build's own proof (a swing and a hit each heard in the browser) is tools/web/sfx_check.mjs.


func before_each() -> void:
	await super()
	Audio.enable_for_tests()


func after_each() -> void:
	Audio.enable_for_tests(false)
	await super()


func _logged(prefix: String) -> Array:
	var out: Array = []
	for e: Dictionary in Audio.cue_log():
		if str(e.cue).begins_with(prefix):
			out.append(e)
	return out


func test_the_buses_are_made_in_order_without_add_bus() -> void:
	assert_eq(AudioServer.get_bus_index("Master"), 0, "Master is bus 0")
	var i := 1
	for bus: String in AudioDirector.BUSES:
		assert_eq(AudioServer.get_bus_index(bus), i, "%s is bus %d" % [bus, i])
		assert_eq(str(AudioServer.get_bus_send(i)), "Master", "%s sends to Master" % bus)
		i += 1
	var src := FileAccess.get_file_as_string("res://scripts/audio/audio_director.gd")
	assert_false(src.contains("AudioServer.add_bus("), "the engine never calls AudioServer.add_bus")


func test_a_cue_at_the_giant_plays_on_a_near_voice_at_its_level() -> void:
	var p := spawn_player(Vector3.ZERO, 0.0)
	await step_ticks(2)
	Audio.clock_s += 1.0
	var at := Audio.listener_position() + Vector3(1.0, 0, 0)
	var v := Audio.play("sfx.hit.flesh.light", at, {"reason": "test"})
	var node := Audio.pool.voice_node(v)
	assert_true(node is AudioStreamPlayer3D and Audio.pool.near_voices.has(node), "a hit 1 m from the listener: a near voice")
	assert_eq(str((node as AudioStreamPlayer3D).bus), "SFX", "on the SFX bus")
	# C3b (decision C3b-6): placed where it sounds, so it pans from its bearing; no lift within its unit distance
	assert_true((node as AudioStreamPlayer3D).global_position.is_equal_approx(at), "at the cue's place (it pans)")
	assert_near((node as AudioStreamPlayer3D).unit_size, 1.0, 0.05, "its unit distance where it stands: no attenuation")
	var e: Dictionary = _logged("sfx.hit.flesh.light")[0]
	assert_true(bool(e.near), "logged as near")
	assert_near((node as AudioStreamPlayer3D).volume_db, float(e.level_db) + AudioDirector.NEAR_PAN_LAW_DB, 0.11,
		"at the level the model gives it there, the pan law made good")
	assert_true(float(e.level_db) >= 2.5, "full level within the unit distance (%.1f dB)" % float(e.level_db))
	Audio.clock_s += 1.0
	var far := Audio.play("sfx.hit.flesh.light", Audio.listener_position() + Vector3(20.0, 0, 0), {"reason": "test"})
	assert_true(Audio.pool.voice_node(far) is AudioStreamPlayer3D, "one 20 m out stays a 3D voice")
	Audio.clock_s += 1.0
	var sting := Audio.play("sfx.threat.sting", Audio.listener_position() + Vector3(0, 0, 1.0),
		{"reason": "test", "priority": 100})
	assert_true(Audio.pool.voice_node(sting) is AudioStreamPlayer3D, "a threat 1 m behind keeps its direction")
	assert_true(p != null, "the giant")


func _swing(p: GiantPlayer) -> void:
	Audio.pool.stop_all()
	Audio.clock_s += 1.0
	Audio.clear_log()
	Events.ability_started.emit(Sim.tick, p.entity.entity_id, "ability.light_1", 1)
	await get_tree().process_frame
	Audio.advance_for_tests(1.0 / 60.0)


func test_the_swing_is_pitched_by_size_and_carries_its_mass_from_stage_four() -> void:
	var p := spawn_player(Vector3.ZERO, 0.0)
	await step_ticks(2)
	await _swing(p)
	var s1 := _logged("sfx.swing.")
	assert_eq(s1.size(), 1, "stage 1: the whoosh alone (%s)" % [s1])
	assert_true(bool(s1[0].near) if s1.size() > 0 else false, "at the giant: a near voice")
	var pitch1 := float(s1[0].pitch) if s1.size() > 0 else 0.0
	var levels := {}
	for stage: int in [4, 6, 8]:
		assert_true(p.growth.debug_set_stage(stage).ok, "grow to stage %d" % stage)
		await step_ticks(2)
		await _swing(p)
		var whoosh := _logged("sfx.swing.blunt.")
		var mass := _logged("sfx.swing.mass.")
		assert_eq(whoosh.size(), 1, "stage %d: the whoosh" % stage)
		assert_eq(mass.size(), 1, "stage %d: and its mass" % stage)
		if whoosh.size() > 0:
			assert_true(float(whoosh[0].pitch) < pitch1 * 0.95, "stage %d's whoosh is lower (%.3f < %.3f)" % [stage, float(whoosh[0].pitch), pitch1])
			# C3b: heard at his own size's distances - a near voice at every stage, never under his steps
			assert_true(bool(whoosh[0].near), "stage %d: the whoosh on a near voice (%.1f m)" % [stage, float(whoosh[0].dist_m)])
		if mass.size() > 0:
			levels[stage] = float(mass[0].level_db)
	assert_true(float(levels.get(8, -99.0)) > float(levels.get(4, 0.0)) + 3.0, "the mass is louder at stage 8 than at stage 4 (%s)" % [levels])
	assert_near(CueRouter.mass_swing_db(10.0), 0.0, 0.01, "0 dB at 10 m")
	assert_near(CueRouter.mass_swing_db(80.0), CueRouter.MASS_SWING_MAX_DB, 0.01, "capped")


func test_a_blow_on_a_body_and_on_a_prop_sound_by_what_they_struck() -> void:
	var p := spawn_player(Vector3.ZERO, 0.0)
	await step_ticks(2)
	var cue_of := func(material: String) -> String:
		var cue := Audio.resolve("sfx.hit.%s" % material)
		return str(cue.get("id", ""))
	for m: String in ["flesh.light", "flesh.heavy", "armor.light", "armor.heavy", "wood", "stone", "iron"]:
		assert_eq(cue_of.call(m), "sfx.hit.%s" % m, "an impact of its own for %s" % m)
	assert_true(Audio.has_cue("sfx.block.guard"), "a guard's block")
	assert_true(Audio.has_cue("sfx.step.giant_s8.hard"), "a stage-8 footfall")
	assert_true(p != null, "the giant")


## C3b (decision C3b-6): near voices starting together (a blow's thud, hit, cry and fall) are lowered 2 dB for each one
## started just before, at most 6 dB, so the stack sounds as one heavy blow instead of clipping.
func test_a_stack_of_near_sounds_is_tamed() -> void:
	spawn_player(Vector3.ZERO, 0.0)
	await step_ticks(2)
	Audio.clock_s += 1.0
	var at := Audio.listener_position() + Vector3(1.0, 0, 0)
	var vols: Array = []
	for cue: String in ["sfx.hit.flesh.light", "sfx.hit.wood", "sfx.impact.stomp", "sfx.body.fall.small", "sfx.hit.flesh.heavy"]:
		var v := Audio.play(cue, at, {"reason": "test"})
		var node := Audio.pool.voice_node(v) as AudioStreamPlayer3D
		var e: Dictionary = _logged(cue)[0]
		vols.append(node.volume_db - float(e.level_db) if node != null else NAN)
	assert_near(float(vols[0]), AudioDirector.NEAR_PAN_LAW_DB, 0.11, "the first at its level")
	assert_near(float(vols[1]), AudioDirector.NEAR_PAN_LAW_DB - 2.0, 0.11, "the second 2 dB under")
	assert_near(float(vols[4]), AudioDirector.NEAR_PAN_LAW_DB - AudioDirector.NEAR_STACK_MAX_DB, 0.11, "at most 6 dB under")
	Audio.clock_s += 1.0
	var later := Audio.play("sfx.hit.wood", at, {"reason": "test"})
	var ln := Audio.pool.voice_node(later) as AudioStreamPlayer3D
	assert_near(ln.volume_db - float(_logged("sfx.hit.wood").back().level_db), AudioDirector.NEAR_PAN_LAW_DB, 0.11, "a blow a second later at its level again")
