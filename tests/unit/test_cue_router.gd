extends TestSuite
## P19 (plan M6-M9 §2.5, §3.1 design 2-3, §4.1): the router's conventions and requests, and the
## voice pool's rules through Audio.play - cue fallback chains to the placeholder bank, voice,
## material and step classes from the mix, the requests the handlers build, every M6 signal routed
## or deliberately silent, the retrigger guard, per-cue caps, voice stealing by priority and age,
## and variants that never repeat. Audio is enabled for these tests (the suite runs silent).

const Fx := preload("res://tests/support/test_fixtures.gd")
## Every Events signal of M0-M5 (P20 adds the M7-M9 block in W12; P21's coverage test checks all).
const M6_SIGNALS := ["ability_started", "action_rejected", "hit_resolved", "attack_clanked", "area_pulse",
	"entity_died", "staggered", "object_destroyed", "loot_awarded", "growth_changed", "lock_target_changed",
	"camera_mode_changed", "hud_message", "sandbox_reset_requested", "status_applied", "status_expired", "healed",
	"ability_effect", "projectile_spawned", "projectile_impact", "telegraph_started", "morale_changed",
	"enemy_routed", "encounter_leashed", "encounter_activated", "encounter_cleared", "boss_engaged",
	"boss_phase_changed", "boss_defeated", "faction_changed", "grab_started", "grab_ended", "growth_blocked",
	"shrine_activated", "shrine_rested", "checkpoint_reached", "checkpoint_saved", "checkpoint_loaded",
	"reload_checkpoint_requested", "mode_change_requested", "object_stage_changed", "object_opened", "interacted",
	"area_entered", "area_exited", "flag_changed", "weapon_equipped", "loadout_changed", "xp_award_requested",
	"xp_gained", "level_changed", "ability_learned", "attributes_changed", "item_added", "item_removed",
	"upgrade_applied", "quest_started", "quest_stage_changed", "quest_completed", "quest_abandoned",
	"dialogue_requested", "dialogue_started", "dialogue_outcome", "dialogue_ended", "tutorial_shown",
	"tutorial_dismissed", "slice_completed", "ui_screen_requested"]


func before_each() -> void:
	Audio.enable_for_tests()


func after_each() -> void:
	Audio.enable_for_tests(false)


func _router() -> CueRouter:
	return Audio.router


func _chains() -> Array:
	var out: Array = []
	for r: Dictionary in _router().queue:
		out.append(r.chain)
	return out


func test_every_m6_signal_is_routed_or_deliberately_silent() -> void:
	var handled := CueRouter.ROUTED_SIGNALS + CueRouter.STATE_SIGNALS
	for sig: String in M6_SIGNALS:
		assert_true(handled.has(sig) or CueRouter.SILENT_SIGNALS.has(sig), "%s is routed or listed silent" % sig)
		if CueRouter.ROUTED_SIGNALS.has(sig):
			assert_true(_router().has_method("_on_" + sig), "%s has a handler" % sig)
	for sig: String in CueRouter.ROUTED_SIGNALS:
		assert_false(CueRouter.SILENT_SIGNALS.has(sig), "%s is not both routed and silent" % sig)
	for sig: String in CueRouter.VARIADIC_SIGNALS:
		assert_true(CueRouter.ROUTED_SIGNALS.has(sig), "%s (M7-M9) is routed when it exists" % sig)


## P21 replaced the placeholder bank's sfx cues with the effect banks: specific cues resolve to
## themselves, a missing subject or variant falls back along the chain to its parent and then to
## the family's default, and the stingers still fall back to the placeholder until P23.
func test_cues_fall_back_to_the_placeholder_bank() -> void:
	assert_eq(str(Audio.resolve("sfx.hit.flesh.light").get("id", "")), "sfx.hit.flesh.light", "a hit resolves to itself")
	assert_eq(str(Audio.resolve("sfx.hit.unobtainium.light").get("id", "")), "sfx.hit.default",
		"an unknown material falls back to the family default")
	assert_eq(str(Audio.resolve("sfx.step.giant_s3.hard.cruise").get("id", "")), "sfx.step.giant_s3.hard.cruise", "a footfall")
	assert_eq(str(Audio.resolve("sfx.step.giant_s1.soft.cruise").get("id", "")), "sfx.step.giant_s1.soft",
		"a missing variant falls back to its parent")
	assert_eq(str(Audio.resolve("sfx.ui.lock_on").get("id", "")), "sfx.ui.lock_on", "an interface cue")
	assert_eq(str(Audio.resolve("mus.stinger.growth").get("id", "")), "mus.stinger.default", "a stinger (placeholder until P23)")
	assert_eq(str(Audio.resolve_chain(["sfx.ability.thunder_roar.roar", "sfx.voice.giant.roar"]).get("id", "")),
		"sfx.ability.thunder_roar.roar", "the first candidate")
	assert_eq(str(Audio.resolve_chain(["sfx.ability.unknown_ability.roar", "sfx.voice.unknown_voice.roar"]).get("id", "")),
		"sfx.ability.default", "the first candidate's family default")
	assert_true(Audio.resolve("nothing.at.all").is_empty(), "an unknown family resolves to nothing")
	assert_true(Audio.has_cue("sfx.hit.default") and not Audio.has_cue("sfx.hit.flesh"), "has_cue is exact")
	assert_eq(Audio.catalog_problems(), PackedStringArray(), "the shipped audio data has no cross-record problem")


func test_voice_material_and_step_classes_come_from_the_mix() -> void:
	var r := _router()
	assert_eq(r.voice_of("enemy.wolf"), "wolf", "wolves")
	assert_eq(r.voice_of("enemy.ogre_king"), "ogre_king", "the King")
	assert_eq(r.voice_of("npc.elder"), "elder", "the elder")
	assert_eq(r.voice_of("enemy.sparring_post"), "none", "the post has no voice")
	assert_eq(r.voice_of("enemy.unmapped"), "human", "the default voice")
	assert_eq(r.material_of("prop.cairn"), "stone", "stone props")
	assert_eq(r.material_of("prop.fence_wood"), "wood", "wood props")
	assert_eq(r.material_of("prop.unmapped"), "wood", "the default material")
	assert_eq(r.step_class_of("enemy.wolf"), "paw", "paws")
	assert_eq(r.step_class_of("enemy.ogre"), "heavy", "ogres")
	var mix: Dictionary = Audio.mix
	for id: String in GameData.ids_of_type("prop"):
		assert_true((mix.materials as Dictionary).has(id), "every prop has a material (%s)" % id)
	for t: String in ["enemy", "npc"]:
		for id: String in GameData.ids_of_type(t):
			assert_true((mix.voices as Dictionary).has(id), "every %s has a voice (%s)" % [t, id])
			assert_true((mix.steps as Dictionary).has(id), "every %s has a step class (%s)" % [t, id])
	for lv: Dictionary in GameData.records_of_type("level"):
		var surfaces: Dictionary = (mix.surfaces as Dictionary).get(lv.id, {})
		for d: Dictionary in lv.get("districts", []):
			assert_true(surfaces.has(d.id), "%s's district %s has a surface" % [lv.id, d.id])
	Fx.record_override("enemy.test_rider", {"type": "enemy", "archetype": "cavalry"})
	assert_eq(r.step_class_of("enemy.test_rider"), "hoof", "an unmapped record by its archetype")
	assert_eq(r.step_class_of("enemy.test_nobody"), "human", "the default step")


func test_handlers_build_their_requests() -> void:
	var r := _router()
	r.queue.clear()
	r._on_attack_clanked(1, "x", 1, Vector3(1, 2, 3))
	assert_eq(_chains(), [["sfx.clank.stone"]], "a clank")
	assert_eq(r.queue[0].at, Vector3(1, 2, 3), "at the contact point")
	r.queue.clear()
	r._on_hud_message("Not enough stamina", "warn")
	r._on_hud_message("Saved", "info")
	assert_eq(_chains(), [["sfx.ui.warn"]], "warnings only")
	r.queue.clear()
	r._on_grab_ended(1, "h", "t", "thrown")
	r._on_grab_ended(1, "h", "t", "interrupted")
	assert_eq(_chains(), [["sfx.grab.throw"]], "a throw; an interrupted grab is silent")
	r.queue.clear()
	r._on_faction_changed(1, "village", "hostile")
	r._on_faction_changed(1, "village", "warned")
	assert_eq(_chains(), [["sfx.world.alarm_bell"], ["sfx.voice.crowd.gasp"]], "faction cues")
	r.queue.clear()
	r._on_item_added(1, "item.crown_first_king", 1, "pickup")
	r._on_item_added(1, "item.iron_ingot", 1, "loot")
	r._on_item_added(1, "item.wood_scrap", 1, "loot")
	assert_eq(_chains(), [["sfx.ui.item.quest", "sfx.ui.item"], ["sfx.ui.item.metal", "sfx.ui.item"], ["sfx.ui.item"]],
		"quest items, metal, others")
	r.queue.clear()
	r._on_growth_blocked(1, "player", "combat", "Enemies are near")
	r._on_growth_blocked(1, "player", "combat", "Enemies are near")
	assert_eq(_chains(), [["sfx.ui.denied"]], "a refusal buzzes at most once per 0.5 s")
	Audio.clock_s += 0.6
	r._on_growth_blocked(1, "player", "combat", "Enemies are near")
	assert_eq(_chains().size(), 2, "and again after it")
	r.queue.clear()
	r._on_lock_target_changed("someone_else", "x", "press")
	assert_true(r.queue.is_empty(), "only the giant's lock is heard")
	r._on_ability_effect(1, "nobody", "ability.x", "aim_preview", Vector3.ZERO, 0.0, 0.0, 0.0)
	assert_true(r.queue.is_empty(), "an aim preview is not an effect")
	r._on_quest_started(1, "quest.main")
	r._on_tutorial_shown(1, "tutorial.light")
	r._on_checkpoint_saved(1, "cp", false, "saving is off")
	assert_eq(_chains(), [["sfx.ui.quest_new"], ["sfx.ui.tip"]], "quest and tip; a failed save is silent")
	r.queue.clear()


func test_stingers_play_on_the_music_bus() -> void:
	_router()._on_level_changed(1, 1, 2)
	_router()._on_quest_completed(1, "quest.main")
	assert_true(Audio.music.stingers.has("mus.stinger.default"), "the level-up stinger played (placeholder)")
	var log := Audio.cue_log()
	assert_true(log.size() >= 1 and str(log[0].bus) == "Music" and str(log[0].requested) == "mus.stinger.level_up",
		"logged on the Music bus as requested")
	assert_true(Audio.active_ducks().has("stinger"), "a stinger ducks the stems")


func _bank_with(cues: Dictionary) -> void:
	Fx.record_override("audio_bank.placeholder", {"cues": cues})
	Audio.reload_catalog()


func _ui_cue(priority: int, max_voices: int, retrigger_ms: int) -> Dictionary:
	return {"files": ["res://assets/audio/placeholder/tone_mid.wav"], "bus": "UI", "spatial": false,
		"volume_db": -6.0, "priority": priority, "max_voices": max_voices, "retrigger_ms": retrigger_ms}


func test_retrigger_guard_and_per_cue_cap() -> void:
	_bank_with({"sfx.ui.t_guard": _ui_cue(50, 2, 45)})
	assert_true(Audio.play("sfx.ui.t_guard") >= 0, "the first play")
	assert_eq(Audio.play("sfx.ui.t_guard"), -1, "a retrigger within 45 ms is refused")
	Audio.clock_s += 0.044
	assert_eq(Audio.play("sfx.ui.t_guard"), -1, "still inside the guard at 44 ms")
	Audio.clock_s += 0.002
	assert_true(Audio.play("sfx.ui.t_guard") >= 0, "after 45 ms it plays")
	Audio.clock_s += 0.05
	assert_eq(Audio.play("sfx.ui.t_guard"), -1, "the cue's two voices are busy: capped")
	assert_true(int(Audio.stats.retrigger) >= 2 and int(Audio.stats.capped) >= 1, "counted")


func test_voice_stealing_by_priority_and_age() -> void:
	_bank_with({"sfx.ui.t_low": _ui_cue(10, 32, 0), "sfx.ui.t_high": _ui_cue(90, 32, 0),
		"sfx.ui.t_lower": _ui_cue(5, 32, 0)})
	var pool := Audio.pool
	var n := pool.size_of(VoicePool.Kind.VOICE_2D)
	var first := -1
	for i in n:
		Audio.pool.begin_frame()
		var v := Audio.play("sfx.ui.t_low")
		if i == 0:
			first = v
		assert_true(v >= 0, "low-priority voice %d" % i)
	assert_eq(pool.busy_count(VoicePool.Kind.VOICE_2D), n, "every 2D voice is busy")
	var high := Audio.play("sfx.ui.t_high")
	assert_true(high >= 0, "a higher priority request steals")
	assert_eq(pool.voice_node(first), null, "the oldest low-priority voice was taken")
	assert_eq(pool.voice_cue(high), "sfx.ui.t_high", "now playing the high cue")
	assert_eq(Audio.play("sfx.ui.t_lower"), -1, "a lower priority request is dropped")
	assert_eq(pool.stolen, 1, "one voice stolen")
	assert_true(pool.dropped >= 1, "one request dropped")


func test_variants_never_repeat_through_play() -> void:
	var last := ""
	var files := {}
	for i in 12:
		Audio.clock_s += 0.1
		Audio.pool.stop_all()
		var v := Audio.play("sfx.hit.flesh.light", Vector3.INF, {"reason": "test"})   # three variants (P21)
		assert_true(v >= 0, "play %d" % i)
		var f := str(Audio.cue_log().back().file)
		assert_true(f != last, "no file twice in a row")
		files[f] = true
		last = f
	assert_eq(files.size(), 3, "all three variants are used")


func test_disabled_audio_plays_and_logs_nothing() -> void:
	Audio.enable_for_tests(false)
	assert_false(Audio.enabled, "disabled")
	assert_eq(Audio.play("sfx.hit.default"), -1, "play refuses")
	Events.attack_clanked.emit(Sim.tick, "x", 1, Vector3.ZERO)
	Events.hud_message.emit("x", "warn")
	await get_tree().process_frame
	assert_eq(Audio.cue_log(), [], "nothing logged")
	assert_true(Audio.is_ready(), "the loading gate never waits for a disabled engine")
	assert_eq(Audio.registration_progress(), 1.0, "nothing to register")
