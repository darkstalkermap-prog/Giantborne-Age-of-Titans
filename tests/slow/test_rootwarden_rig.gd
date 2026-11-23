extends IntegrationSuite
## B3: the Rootwarden as drawn and as saved: his model and clips (RootwardenRig over RootwardenModel), asleep in his
## dormant clip until he wakes; a bark plate cracked, broken (the sapwood glowing where it was), regrowing (the bark
## dissolving back over it) and whole again, or seared by fire (charred, never regrowing); a shin broken: he goes down
## on a knee and his shoulders' and knot's hurtboxes come down into a stage-5 giant's reach; his intro plays as his
## fight engages, once, skips and gives the camera back; a mid-world save (schema 3, before B3) goes on through his
## rest, the Warden set made and worn, and back.

const WARDEN := "res://scenes/enemies/rootwarden.tscn"
const GROVE := "res://scenes/test/grove_test.tscn"
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
	return TestSpawn.enemy(world, WARDEN, Vector3(0, 0.05, -18), "test.rootwarden_%d" % _n, false, 0.0) as TitanEnemy


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func test_his_model_and_clips() -> void:
	var t := _warden()
	await step_ticks(3)
	await _frames(2)
	var rig := t.rig as RootwardenRig
	assert_true(rig != null and rig.has_model(), "his own model")
	for c: String in ["dormant", "idle", "walk", "run", "roar", "uproot", "lash", "erupt", "snare", "rip", "hurl", "stomp",
			"reel", "kneel", "rise", "death"]:
		assert_true(rig.model.has_clip(c), "his clip %s" % c)
	var names := Array(rig.model.plate_names())
	for p: String in ["bark_shoulder_l", "bark_shoulder_r", "bark_back", "bark_forearm_r", "bark_knot", "bark_shin_l",
			"bark_shin_r"]:
		assert_true(names.has(p), "his plate %s" % p)
	assert_true(t.dormant, "asleep")
	assert_eq(rig.model.clip, "dormant", "in his dormant clip")
	t.wake("struck")
	await step_ticks(10)
	await _frames(2)
	assert_eq(rig.model.clip, "roar", "he wakes roaring")


func test_a_plate_breaks_regrows_or_is_seared() -> void:
	var t := _warden()
	await step_ticks(3)
	t.wake("struck")
	await step_ticks(2)
	var rig := t.rig as RootwardenRig
	var ps := t.plates()
	ps.health["shoulder_l"] = float(ps.plate("shoulder_l").health) * 0.4
	await _frames(2)
	assert_true(rig.model.plate_crack("bark_shoulder_l") > 0.0, "cracked below 60 %")
	assert_true(t.break_plate("shoulder_l"), "broken")
	await _frames(2)
	assert_false(rig.model.plate_visible("bark_shoulder_l"), "the bark gone from him")
	assert_true(rig.model.sap_visible("bark_shoulder_l"), "the sapwood shows, glowing")
	assert_true(rig.plates_shown_broken.has("shoulder_l"), "its break shown")
	var rg: Dictionary = ps.plate("shoulder_l").regrow
	await step_ticks(int((float(rg.after_s) + float(rg.over_s) * 0.5) * 60.0))
	await _frames(2)
	assert_eq(ps.wound_state("shoulder_l"), PlateRules.WOUND_REGROWING, "regrowing")
	assert_true(rig.model.plate_visible("bark_shoulder_l"), "the bark coming back over it")
	var g := rig.model.plate_grow("bark_shoulder_l")
	assert_true(g > 0.1 and g < 0.95, "part grown (%.2f)" % g)
	await step_ticks(int(float(rg.over_s) * 0.6 * 60.0))
	await _frames(2)
	assert_false(ps.is_broken("shoulder_l"), "whole")
	assert_near(rig.model.plate_grow("bark_shoulder_l"), 1.0, 1e-3, "fully grown")
	assert_false(rig.model.sap_visible("bark_shoulder_l"), "the sapwood covered")
	assert_true(rig.plates_shown_regrown.has("shoulder_l"), "its regrowth shown")
	# seared: broken again, then burned
	assert_true(t.break_plate("shoulder_r"), "the other shoulder broken")
	assert_true(t.p34_ignite(8.0, ""), "set burning")
	await step_ticks(2)
	await _frames(2)
	assert_eq(ps.wound_state("shoulder_r"), PlateRules.WOUND_SEARED, "seared")
	await _frames(60)   # (the char spreads over the sapwood in about 0.7 s)
	assert_true(rig.model.sap_char("bark_shoulder_r") > 0.5, "charred (%.2f)" % rig.model.sap_char("bark_shoulder_r"))
	await step_ticks(int((float(rg.after_s) + float(rg.over_s) + 2.0) * 60.0))
	await _frames(2)
	assert_false(rig.model.plate_visible("bark_shoulder_r"), "a seared wound never grows back")


func test_a_broken_shin_brings_his_shoulders_and_knot_down() -> void:
	var t := _warden()
	await step_ticks(3)
	t.wake("struck")
	await step_ticks(2)
	var sh := t.get_node("Hurtboxes/ShoulderL") as Node3D
	var knot := t.get_node("Hurtboxes/Knot") as Node3D
	var sh_up := sh.global_position.y - t.global_position.y
	var knot_up := knot.global_position.y - t.global_position.y
	assert_true(t.break_plate("shin_l"), "his shin breaks")
	assert_true(t.is_down(), "he goes down on a knee")
	await step_ticks(90)
	var sh_down := sh.global_position.y - t.global_position.y
	var knot_down := knot.global_position.y - t.global_position.y
	assert_true(sh_down < sh_up - 3.0, "his shoulder comes down (%.1f -> %.1f m)" % [sh_up, sh_down])
	assert_true(knot_down < knot_up - 1.5, "and his knot (%.1f -> %.1f m)" % [knot_up, knot_down])
	assert_true(sh_down < 14.0, "within a stage-5 giant's reach (%.1f m)" % sh_down)
	assert_eq((t.rig as RootwardenRig).model.clip, "kneel", "his kneel clip")


func test_his_intro_plays_once_skips_and_gives_the_camera_back() -> void:
	var level := (load(GROVE) as PackedScene).instantiate() as Node3D
	level.set("stage", 0)
	world.add_child(level)
	var p := level.get_node("Player") as GiantPlayer
	await TestWait.until(self, func() -> bool: return p.is_on_floor(), 60)
	var t := level.get_node("Rootwarden") as TitanEnemy
	var stack := ScreenStack.new()
	add_child(stack)
	var cam_before := get_viewport().get_camera_3d()
	var doc_before: Dictionary = GameSession.checkpoint_doc
	GameSession.checkpoint_doc = {"cinematics_seen": ["cutscene.intro"]}   # (the last checkpoint, from before his fight)
	GameSession.cutscenes_on = true
	assert_true(GameSession.titan_intro_due("cutscene.rootwarden"), "due before it played")
	var screen := GameSession.play_cutscene("cutscene.rootwarden") as CutsceneScreen
	assert_true(screen != null, "the cutscene opens")
	await _frames(1)
	assert_false(t.visible, "the real warden hidden while his double plays")
	assert_true(screen.actors.has("warden") and screen.actors.has("giant"), "his model and the giant")
	screen.skip()
	await _frames(2)
	assert_true(t.visible, "shown again after the skip")
	assert_true(ExpansionState.seen(GameSession.expansion, "cutscene.rootwarden"), "seen: once a game")
	assert_false(GameSession.titan_intro_due("cutscene.rootwarden"), "never again")
	# B5: the mark is in the last checkpoint's document at once (no checkpoint is taken in his fight): a quit to the
	# title mid-fight and a Continue (the document read back) do not play it again
	assert_eq(GameSession.checkpoint_doc.get("cinematics_seen"), ["cutscene.intro", "cutscene.rootwarden"],
		"his intro written into the save's document as it ended")
	assert_true(ExpansionState.seen(ExpansionState.from_doc(GameSession.checkpoint_doc), "cutscene.rootwarden"),
		"a Continue from it has seen it")
	GameSession.checkpoint_doc = doc_before
	assert_true(get_viewport().get_camera_3d() == cam_before, "the camera given back")
	GameSession.cutscenes_on = false
	stack.queue_free()
	level.queue_free()
	await step_ticks(2)


func test_a_mid_world_save_goes_on_through_his_rest_and_back() -> void:
	var r := JsonIO.read_file(FIXTURES + "v2_a4_world_mid.json")
	var doc := SaveSlots.migrate(r.data)
	assert_eq(SaveSlots.validate(doc), PackedStringArray(), "the save from before B3 is valid")
	assert_false((doc.get("titans", {}) as Dictionary).has("titan.rootwarden"), "he is not met in it")
	GameSession.expansion = ExpansionState.from_doc(doc)
	var flags: Dictionary = (doc.world as Dictionary).get("flags", {})
	flags["boss.rootwarden.outcome"] = "slain"
	flags["boss.rootwarden.defeated"] = true
	flags["world.greywood.grove_greened"] = true
	ExpansionState.sync_from_flags(GameSession.expansion, flags)
	ExpansionState.note_slain(GameSession.expansion, "titan.rootwarden")
	Armour.grant(GameSession.expansion.equipment, "armour.warden_mantle")
	Armour.equip(GameSession.expansion.equipment, "armour.warden_mantle")
	var out := ExpansionState.write_into(doc.duplicate(true), GameSession.expansion)
	out.world.flags = flags
	assert_eq(SaveSlots.validate(out), PackedStringArray(), "the document after his rest validates")
	GameSession.persist = true
	assert_true(SaveSlots.write(out).ok, "written")
	var back := SaveSlots.read()
	assert_true(back.ok, "read back")
	var st := ExpansionState.from_doc(back.data)
	assert_eq(str((st.titans.get("titan.rootwarden", {}) as Dictionary).get("state", "")), ExpansionState.STATE_SLAIN,
		"his record: at rest")
	assert_true(Armour.owns(st.equipment, "armour.warden_mantle"), "the Warden Mantle owned")
	assert_eq(str(st.equipment.slots.shoulders), "armour.warden_mantle", "and worn")
	var hf: Dictionary = ((st.settlements.get("poi.hollowmere", {}) as Dictionary).get("flags", {}) as Dictionary)
	assert_true(bool(hf.get("grove_greened", false)), "Hollowmere's grove greened")
	GameSession.persist = false


## Stages 4-6 locked on him (21.3 m) from 24 m: the lock frames a plate the giant reaches (not his crown), the camera
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
