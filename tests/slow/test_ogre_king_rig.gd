extends IntegrationSuite
## B2: the Ogre King as a signature titan in play (docs/systems/B2.md): his scene is a TitanEnemy with P11a's body
## (capsule, anchors, the head, torso and legs hurtboxes) and a hurtbox and an anchor a trophy; his OgreKingRig draws
## his own model (the five trophies, the chain belt, the ram, his clips); a trophy cracks as its health wears, and
## breaking it hides it, drops a copy of it to the ground and throws its splinters; the crown's break unbalances him
## (every later blow's poise x1.6), the keg's drops him to a knee (his crown and shoulders come down into a stage-2
## giant's reach), the bell's leaves his belly a weak point; the lock of a stage-2 giant frames his knee as P11a's
## did and the lock-switch picks a trophy; dying, he drops the ram; his intro plays as his fight engages, once, and
## skips; a cutscene closed by any path gives the camera back (B1's last-pass row); Thornwick's trophy stand shows
## once he has fallen; a mid-Valley save (schema 3) goes on through his death, his parts and the Kingsfall set
## made at Thornwick's smithy, and back through SaveSlots.

const KING := "res://scenes/enemies/ogre_king.tscn"
const ARENA := "res://scenes/test/boss_arena_test.tscn"
const FIXTURES := "res://tests/fixtures/saves/"


func before_each() -> void:
	super()
	PersonRig.enable_for_tests()
	GameSession.expansion = ExpansionState.defaults()


func after_each() -> void:
	SaveSlots.delete_slot(true)
	GameSession.expansion = ExpansionState.defaults()
	super()


static var _n := 0


func _king() -> TitanEnemy:
	_n += 1
	var k := TestSpawn.enemy(world, KING, Vector3(0, 0.05, -14), "test.ogre_king_%d" % _n, false, 0.0) as TitanEnemy
	return k


func test_his_scene_is_a_titan_with_p11as_body() -> void:
	var k := _king()
	await step_ticks(3)
	assert_true(k is TitanEnemy and k is OgreBoss, "a TitanEnemy (an OgreBoss)")
	assert_true(k.brain is OgreBossBrain, "his sequences as before")
	for n: String in ["Hurtboxes/Head", "Hurtboxes/Torso", "Hurtboxes/Legs", "Hurtboxes/Belly", "Hurtboxes/Back",
			"Hurtboxes/ShoulderL", "Hurtboxes/ShoulderR", "Anchors/Torso", "Anchors/KneeL", "Anchors/KneeR",
			"Anchors/PlateCrown", "Anchors/PlateBell", "Anchors/PlateKeg", "Visual/Body", "Visual/LodProxy"]:
		assert_true(k.has_node(n), "%s" % n)
	assert_true(k.get_node("Anchors/PlateCrown").has_meta(TitanEnemy.KNEEL_META), "the crown's anchor follows his kneel")
	var rig := k.rig as OgreKingRig
	assert_true(rig != null and rig.has_model(), "his own model")
	assert_eq(Array(rig.model.trophy_names()), OgreKingModel.TROPHIES, "the five trophies")
	for c: String in ["idle", "walk", "run", "roar", "combo_a", "combo_b", "slam", "charge", "charge_run", "reel", "kneel",
			"rise", "death"]:
		assert_true(rig.model.has_clip(c), "his clip %s" % c)
	var keys := OgreKingModel.clip_keys()
	assert_eq((keys.get("slam", []) as Array).size(), 5, "the slam's keys in the manifest")
	assert_near(float((keys.slam as Array)[2]), 1.5, 1e-3, "his slam lands at its windup's end (1.5 s)")
	var crown_top := rig.model.piece_centre("trophy_crown").y - k.global_position.y
	assert_true(crown_top > 8.0 and crown_top < 9.2, "his crown at his head (%.2f m)" % crown_top)


func test_a_trophy_cracks_breaks_falls_and_splinters() -> void:
	var k := _king()
	await step_ticks(3)
	var rig := k.rig as OgreKingRig
	var ps := k.plates()
	ps.health["bell"] = float(ps.plate("bell").health) * 0.4
	await get_tree().process_frame
	await get_tree().process_frame
	assert_eq(rig.model.trophy_crack("trophy_bell"), OgreKingModel.CRACKED, "cracked below 60 %")
	assert_true(k.break_plate("bell"), "broken")
	await get_tree().process_frame
	await get_tree().process_frame
	assert_false(rig.model.trophy_visible("trophy_bell"), "the bell is gone from him")
	assert_true(rig.fallen.has("trophy_bell"), "a copy of it falls")
	assert_eq(rig.trophies_shown_broken, ["bell"] as Array[String], "its break shown once")
	for i in 120:
		await get_tree().process_frame
	assert_true(rig.fallen_landed("trophy_bell"), "and lies on the ground")
	# a new attempt: whole again
	k._p34_reset_extra()
	await get_tree().process_frame
	await get_tree().process_frame
	assert_true(rig.model.trophy_visible("trophy_bell"), "a new attempt: the bell whole on him")
	assert_false(rig.fallen.has("trophy_bell"), "the fallen copy gone")


func test_the_crown_unbalances_him_the_keg_drops_him_the_bell_exposes_his_belly() -> void:
	var k := _king()
	await step_ticks(3)
	var crown_up := (k.get_node("Anchors/PlateCrown") as Node3D).global_position.y
	assert_true(k.break_plate("crown"), "the crown breaks")
	assert_near(k.plates().poise_taken_mult, 1.6, 1e-6, "unbalanced: x1.6 poise")
	assert_true(k.controller.state == CombatController.State.STAGGERED, "and dazed by it")
	await step_ticks(200)
	assert_true(k.break_plate("keg"), "the keg bursts")
	assert_true(k.is_down(), "he goes down on a knee")
	assert_eq(k.topples, 1, "once")
	await step_ticks(60)
	var crown_down := (k.get_node("Anchors/PlateCrown") as Node3D).global_position.y
	assert_true(crown_down < crown_up - 1.8 and crown_down - k.global_position.y < 6.6,
		"his crown comes down into a stage-2 giant's reach (%.2f -> %.2f m)" % [crown_up, crown_down])
	var hit := HitEvent.new()
	hit.region = "belly"
	k.plates().prepare(hit)
	var before := hit.region_damage_mult
	k.break_plate("bell")
	k.plates().prepare(hit)
	assert_true(hit.region_damage_mult > before * 2.0, "the bell broken: his belly a weak point (%.2f -> %.2f)" % [
		before, hit.region_damage_mult])


func test_a_stage_2_giants_lock_frames_his_knee_and_the_switch_picks_a_trophy() -> void:
	var n := await _arena()
	var k: TitanEnemy = n.king
	var p: GiantPlayer = n.player
	p.global_position = k.global_position + Vector3(0, 0, -9)
	await step_ticks(3)
	var h := 5.4864
	assert_false(k.titan_lock_point(h).is_finite(), "no trophy framed on its own above a small giant's swing")
	var low: Node3D = null
	for a: Node3D in k.entity.lock_anchors():
		if low == null or a.global_position.y < low.global_position.y:
			low = a
	assert_true(k.entity.lock_anchor_position(h).is_equal_approx(low.global_position), "his knee, as P11a framed it")
	k.lock_choice = "bell"
	assert_true(k.titan_lock_point(h).is_equal_approx((k.get_node("Anchors/PlateBell") as Node3D).global_position),
		"the lock-switch's pick is framed")
	k.lock_choice = ""
	assert_true(k.titan_lock_point(7.9248).is_finite(), "a stage-3 giant frames a trophy it reaches squarely")


func test_dying_he_drops_the_ram() -> void:
	var k := _king()
	await step_ticks(3)
	var rig := k.rig as OgreKingRig
	var h := HitEvent.new()
	h.tick = Sim.tick
	h.instance_id = Sim.new_instance_id()
	h.attacker_id = "player"
	h.target_id = k.entity.entity_id
	h.power = 100000.0
	h.attacker_stat = 10.0
	h.attacker_height_m = 3.6576
	h.damage_split = {"physical": 1.0}
	h.tags = PackedStringArray(["Melee"])
	h.attacker_position = k.global_position + Vector3(0, 0, 3)
	Sim.queue_hit(h)
	for i in 90:
		await get_tree().process_frame
		await step_ticks(1)
	assert_eq(rig.current_clip(), "death", "his death clip")
	assert_true(rig.fallen.has("ram"), "the ram falls from his fist")


func _arena() -> Dictionary:
	var level := (load(ARENA) as PackedScene).instantiate() as Node3D
	world.add_child(level)
	var p := level.get_node("Player") as GiantPlayer
	await TestWait.until(self, func() -> bool: return p.is_on_floor(), 60)
	await step_ticks(2)
	return {"level": level, "player": p, "king": level.get_node("OgreKing"),
		"arena": level.get_node("BossArena") as BossArena}


func test_his_intro_plays_once_as_the_fight_engages_skips_and_gives_the_camera_back() -> void:
	var n := await _arena()
	var stack := ScreenStack.new()
	add_child(stack)
	var cam_before := get_viewport().get_camera_3d()
	GameSession.cutscenes_on = true
	assert_true(GameSession.titan_intro_due("cutscene.ogre_king"), "due before it played")
	var screen := GameSession.play_cutscene("cutscene.ogre_king") as CutsceneScreen
	assert_true(screen != null, "the cutscene opens")
	await get_tree().process_frame
	assert_false((n.king as Node3D).visible, "the real King hidden while his double plays")
	assert_true(screen.actors.has("king") and screen.actors.has("giant"), "the King's model and the giant")
	screen.skip()
	await get_tree().process_frame
	await get_tree().process_frame
	assert_true((n.king as Node3D).visible, "shown again after the skip")
	assert_true(ExpansionState.seen(GameSession.expansion, "cutscene.ogre_king"), "seen: once a game")
	assert_false(GameSession.titan_intro_due("cutscene.ogre_king"), "never again")
	assert_true(get_viewport().get_camera_3d() == cam_before, "the camera given back")
	# B1's last-pass row: closed with every screen (no skip), it still gives the camera back
	var again := stack.open("cutscene", {"cutscene": "cutscene.ogre_king", "level": n.level}) as CutsceneScreen
	await get_tree().process_frame
	assert_true(get_viewport().get_camera_3d() != cam_before, "the cutscene's camera current")
	stack.close_all()
	await get_tree().process_frame
	await get_tree().process_frame
	assert_true(get_viewport().get_camera_3d() == cam_before, "close_all over it: the camera given back")
	assert_true((n.king as Node3D).visible, "and the King shown")
	assert_false(is_instance_valid(again) and again.is_inside_tree(), "the screen gone")
	GameSession.cutscenes_on = false
	stack.queue_free()


func test_thornwick_shows_his_trophies_once_he_has_fallen() -> void:
	var valley := (load("res://scenes/world/valley.tscn") as PackedScene).instantiate() as Node3D
	var after := valley.get_node_or_null("Aftermath") as FlagVisibility
	assert_true(after != null, "the Valley has its aftermath")
	assert_eq(after.visible_when_flag, "world.ogre_king.defeated", "shown once he has fallen")
	var names := []
	for d in after.find_children("*", "TrophyDisplay", true, false):
		names.append(str((d as TrophyDisplay).piece))
	names.sort()
	assert_eq(names, ["ram", "trophy_bell", "trophy_crown", "trophy_wheel_l", "trophy_wheel_r"], "his pieces on the stand")
	var forge := valley.find_child("valley_village_forge", true, false)
	if forge == null:
		forge = valley.find_child("*village*forge*", true, false)
	assert_true(forge != null and (forge.get("works") as PackedStringArray).has("ogre_trophy"),
		"Thornwick's smithy works his trophies")
	valley.free()
	var shown := TrophyDisplay.new()
	shown.piece = "trophy_crown"
	world.add_child(shown)
	await get_tree().process_frame
	assert_true(shown.shown != null and shown.shown.mesh != null, "a trophy drawn from his asset")


func test_a_mid_valley_schema_3_save_goes_on_through_his_fall_and_back() -> void:
	var r := JsonIO.read_file(FIXTURES + "v2_a4_valley.json")
	var doc := SaveSlots.migrate(r.data)
	assert_eq(int(doc.schema_version), 3, "the mid-Valley save at schema 3")
	assert_eq(SaveSlots.validate(doc), PackedStringArray(), "valid")
	assert_false((doc.get("titans", {}) as Dictionary).has("titan.ogre_king"), "not met yet")
	GameSession.expansion = ExpansionState.from_doc(doc)
	# his fall: the flag, his loot, a trophy's own; the Kingsfall helm made at Thornwick's smithy
	var flags: Dictionary = (doc.world as Dictionary).get("flags", {})
	flags["world.ogre_king.defeated"] = true
	ExpansionState.sync_from_flags(GameSession.expansion, flags)
	ExpansionState.note_slain(GameSession.expansion, "titan.ogre_king")
	Armour.grant(GameSession.expansion.equipment, "armour.kingsfall_helm")
	Armour.equip(GameSession.expansion.equipment, "armour.kingsfall_helm")
	var out := ExpansionState.write_into(doc.duplicate(true), GameSession.expansion)
	out.world.flags = flags
	assert_eq(SaveSlots.validate(out), PackedStringArray(), "the document after his fall validates")
	GameSession.persist = true
	assert_true(SaveSlots.write(out).ok, "written")
	var back := SaveSlots.read()
	assert_true(back.ok, "read back")
	var st := ExpansionState.from_doc(back.data)
	assert_eq(str((st.titans.get("titan.ogre_king", {}) as Dictionary).get("state", "")), ExpansionState.STATE_SLAIN,
		"his record: slain")
	assert_true(Armour.owns(st.equipment, "armour.kingsfall_helm"), "the Kingsfall helm owned")
	assert_eq(str(st.equipment.slots.head), "armour.kingsfall_helm", "and worn")
	GameSession.persist = false
