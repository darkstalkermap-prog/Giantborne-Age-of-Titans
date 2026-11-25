extends IntegrationSuite
## C2: the Broken Warden as drawn and as saved: his model and clips (BastionRig over BastionModel), asleep in his
## dormant clip until he wakes roaring; a plate cracked then broken (it falls from him and lies where it fell); his
## guard broken (the guard-break clip, stone chips off the shield); the shield's break (it topples from his arm to the
## ground, and he goes two-handed: idle2); a greave broken brings his helm and pauldron down into a stage-5 giant's
## reach; a campaign-complete save (schema 3, from before C2, the fort's content all done) can still fight him, and
## goes on through his fall, the Bastion set made and worn, and back; the lock frames a plate the giant reaches at
## stages 4-6.

const BASTION := "res://scenes/enemies/bastion.tscn"
const FIXTURES := "res://tests/fixtures/saves/"


func before_each() -> void:
	super()
	PersonRig.enable_for_tests()
	GameSession.expansion = ExpansionState.defaults()


func after_each() -> void:
	SaveSlots.delete_slot(true)
	GameSession.expansion = ExpansionState.defaults()
	PersonRig.reset_for_tests()
	super()


static var _n := 0


func _warden() -> TitanEnemy:
	_n += 1
	return TestSpawn.enemy(world, BASTION, Vector3(0, 0.05, -20), "test.bastion_%d" % _n, false, 0.0) as TitanEnemy


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func test_his_model_and_clips() -> void:
	var t := _warden()
	await step_ticks(3)
	await _frames(2)
	var rig := t.rig as BastionRig
	assert_true(rig != null and rig.has_model(), "his own model")
	for c: String in ["dormant", "idle", "walk", "run", "roar", "bash", "hammer", "sweep", "charge", "charge_run", "stomp",
			"reel", "guardbreak", "rearm", "idle2", "walk2", "run2", "smash2", "sweep2", "kneel", "rise", "death"]:
		assert_true(rig.model.has_clip(c), "his clip %s" % c)
	var names := Array(rig.model.plate_names())
	for p: String in BastionModel.PLATES:
		assert_true(names.has(p), "his plate %s" % p)
	assert_true(rig.model.piece("bar") != null, "his gate-bar")
	assert_true(t.dormant, "asleep")
	assert_eq(rig.model.clip, "dormant", "in his dormant clip")
	t.wake("struck")
	await step_ticks(10)
	await _frames(2)
	assert_eq(rig.model.clip, "roar", "he wakes roaring")


func test_a_plate_cracks_breaks_and_falls() -> void:
	var t := _warden()
	await step_ticks(3)
	t.wake("struck")
	t.ai_enabled = false
	await step_ticks(2)
	var rig := t.rig as BastionRig
	var ps := t.plates()
	ps.health["back"] = float(ps.plate("back").health) * 0.4
	await _frames(2)
	assert_true(rig.model.plate_crack("back") > 0.0, "cracked below 60 %")
	assert_true(t.break_plate("back"), "broken")
	await _frames(2)
	assert_false(rig.model.plate_visible("back"), "gone from him")
	assert_true(rig.plates_shown_broken.has("back"), "its break shown")
	assert_true(rig.fallen.has("back"), "it falls")
	await _frames(150)
	assert_true(rig.fallen_landed("back"), "and lies where it fell")


func test_his_guard_breaks_and_his_shield_falls() -> void:
	var t := _warden()
	await step_ticks(3)
	t.wake("struck")
	t.ai_enabled = false
	await step_ticks(30)
	var rig := t.rig as BastionRig
	assert_true(t.break_guard(), "the guard broken")
	await step_ticks(10)
	await _frames(2)
	assert_eq(rig.model.clip, "guardbreak", "his guard-break clip (the shield knocked wide)")
	assert_eq(rig.guard_breaks_shown, 1, "shown once")
	await step_ticks(int(float(t.plates().guard.stagger_s) * 60.0) + 30)
	assert_true(t.break_plate("shield"), "the shield's stone broken")
	assert_true(t.disarmed, "disarmed")
	await step_ticks(4)
	await _frames(2)
	assert_false(rig.model.plate_visible("shield"), "gone from his arm")
	assert_true(rig.fallen_shield() != null, "it topples from him")
	await _frames(200)
	assert_true(rig.fallen_landed("shield"), "and lies on the ground")
	await step_ticks(400)
	await _frames(2)
	assert_true(BastionModel.TWO_HANDED.has(rig.model.clip), "two-handed now (%s)" % rig.model.clip)


func test_a_broken_greave_brings_his_helm_down() -> void:
	var t := _warden()
	await step_ticks(3)
	t.wake("struck")
	await step_ticks(2)
	var head := t.get_node("Hurtboxes/Head") as Node3D
	var back := t.get_node("Hurtboxes/Back") as Node3D
	var head_up := head.global_position.y - t.global_position.y
	var back_up := back.global_position.y - t.global_position.y
	assert_true(t.break_plate("greave_l"), "his greave breaks")
	assert_true(t.is_down(), "he goes down on a knee")
	await step_ticks(90)
	var head_down := head.global_position.y - t.global_position.y
	var back_down := back.global_position.y - t.global_position.y
	assert_true(head_down < head_up - 3.0, "his helm comes down (%.1f -> %.1f m)" % [head_up, head_down])
	assert_true(back_down < back_up - 2.0, "and his back (%.1f -> %.1f m)" % [back_up, back_down])
	assert_true(head_down < 17.0, "within a stage-5 giant's reach (%.1f m)" % head_down)
	assert_eq((t.rig as BastionRig).model.clip, "kneel", "his kneel clip")


func test_a_finished_campaign_can_still_fight_him_and_goes_on_through_his_fall() -> void:
	var r := JsonIO.read_file(FIXTURES + "v3_m15_campaign_complete.json")
	var doc := SaveSlots.migrate(r.data)
	assert_eq(SaveSlots.validate(doc), PackedStringArray(), "the save from before C2 is valid")
	var flags: Dictionary = (doc.world as Dictionary).get("flags", {})
	assert_true(flags.has("quest.kingsroad_toll.done"), "the toll fort's content done in it")
	assert_false((doc.get("titans", {}) as Dictionary).has("titan.bastion"), "he is not met in it")
	for f: String in flags:
		WorldState.set_flag(f, flags[f])
	for id: String in ["encounter.aldmere_bastion", "encounter.aldmere_toll_keeper"]:
		assert_true(EncounterDirector.flags_allow(GameData.get_record(id)), "%s waits for it" % id)
	assert_false(EncounterDirector.flags_allow(GameData.get_record("encounter.aldmere_warden_masons")),
		"the masons wait for his fall")
	GameSession.expansion = ExpansionState.from_doc(doc)
	flags["boss.bastion.outcome"] = "slain"
	flags["boss.bastion.defeated"] = true
	flags["world.warden_keep.opened"] = true
	ExpansionState.sync_from_flags(GameSession.expansion, flags)
	ExpansionState.note_slain(GameSession.expansion, "titan.bastion")
	for id: String in Armour.set_pieces("armour_set.bastion"):
		Armour.grant(GameSession.expansion.equipment, id)
		Armour.equip(GameSession.expansion.equipment, id)
	var out := ExpansionState.write_into(doc.duplicate(true), GameSession.expansion)
	out.world.flags = flags
	assert_eq(SaveSlots.validate(out), PackedStringArray(), "the document after his fall validates (schema 3)")
	assert_eq(int(out.schema_version), 3, "still schema 3")
	GameSession.persist = true
	assert_true(SaveSlots.write(out).ok, "written")
	var back := SaveSlots.read()
	assert_true(back.ok, "read back")
	var st := ExpansionState.from_doc(back.data)
	assert_eq(str((st.titans.get("titan.bastion", {}) as Dictionary).get("state", "")), ExpansionState.STATE_SLAIN,
		"his record: fallen")
	assert_eq(str(st.equipment.slots.chest), "armour.bastion_cuirass", "the Bastion cuirass worn")
	assert_eq(int(Armour.set_counts(st.equipment).get("armour_set.bastion", 0)), 7, "the whole set")
	var tf: Dictionary = ((st.settlements.get("poi.toll_fort", {}) as Dictionary).get("flags", {}) as Dictionary)
	assert_true(bool(tf.get("warden_fallen", false)), "the toll fort knows")
	assert_true(bool(tf.get("keep_opened", false)), "and the keep is open")
	GameSession.persist = false


## Stages 4-6 locked on him (22.4 m) from 26 m: the lock frames a plate the giant reaches (not his crown), the camera
## holds it in view with its arm within MAX_ARM_M and never looks steeply up.
func test_the_lock_frames_a_plate_in_reach_at_stages_4_to_6() -> void:
	for stage: int in [4, 5, 6]:
		var p := spawn_player(Vector3(0, 0.05, 6), 0.0)
		var prof := {}
		for rec: Dictionary in GameData.records_of_type("growth_profile"):
			if int(rec.get("stage", 0)) == stage:
				prof = rec
		p.set_profile(prof)
		await TestWait.until(self, func() -> bool: return p.is_on_floor(), 40)
		var t := _warden()
		await step_ticks(3)
		p.targeting.try_lock()
		assert_eq(p.lock.target_id, t.entity_id, "stage %d: the giant locks him" % stage)
		for i in 45:
			await get_tree().process_frame
			await step_ticks(1)
		var focus := p.camera_rig.lock_focus_point()
		var h := p.entity.combatant.height_m
		assert_true(focus.y - t.global_position.y < h * 1.25,
			"stage %d (%.1f m): the lock frames what it reaches (%.1f m up)" % [stage, h, focus.y - t.global_position.y])
		assert_true(p.camera_rig.camera.is_position_in_frustum(focus), "stage %d: in view" % stage)
		assert_true(p.camera_rig.current_distance <= CameraRig.MAX_ARM_M + 1e-3, "stage %d: the arm within %.0f m (%.1f)" % [
			stage, CameraRig.MAX_ARM_M, p.camera_rig.current_distance])
		assert_true(rad_to_deg(p.camera_rig.pitch) <= CameraRig.LOCK_PITCH_MAX + 0.5, "stage %d: never steeply up" % stage)
		print("    stage %d: lock %.1f m up, arm %.1f m, pitch %.1f deg" % [stage, focus.y - t.global_position.y,
			p.camera_rig.current_distance, rad_to_deg(p.camera_rig.pitch)])
		p.targeting.release_lock("manual")
		t.queue_free()
		p.queue_free()
		await step_ticks(2)
