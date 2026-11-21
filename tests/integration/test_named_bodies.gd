extends IntegrationSuite
## P62 (plan M11 §2.9, §3.15 design 1): the townsfolk and the named characters are realistic people, headless with
## the people switched on (PersonRig.enable_for_tests; ResetHooks turns them off after every test):
##   * every npc record and Corvane's names a body of a role the people's manifest has; each named character its
##     own variant (Edda, Reeve Tamsin, the ferrywoman, the herald, the toll captain, the deserter, Corvane: notables;
##     P65b: Sedge and Elder Maren the elders' two women), the villagers a pool of five (three men, two women), the roles' palettes and factions whole;
##   * the villager's and the talkers' scenes are PersonRigs: headless nothing is made, the brain's pivots stay;
##   * a villager skinned near the giant takes a variant of the pool by its id; Edda her own variant, her colours,
##     her faction's colour, her height (the record's 1.7 m x the women's 0.93); Corvane at 2.0 m with his sword;
##   * a fleeing villager runs on the flee clip; one fleeing with nowhere to run cowers where it stands; one gone
##     indoors (hidden) leaves its level and gives its model back.
## The giant is a stand-in (a node of group "player" at stage 1's distance scale): this is presentation.

const VILLAGER := "res://scenes/npcs/villager.tscn"
const ELDER := "res://scenes/npcs/elder.tscn"
const CORVANE := "res://scenes/enemies/corvane.tscn"
const NAMED := {"npc.edda": "edda", "npc.reeve_tamsin": "reeve_tamsin", "npc.sedge": "elder_d", "npc.elder": "elder_c",
	"npc.ferrywoman": "ferrywoman", "npc.herald": "herald", "npc.toll_captain": "toll_captain",
	"npc.deserter": "deserter", "enemy.corvane": "corvane"}
const ROLES := ["person_role.villager", "person_role.elder", "person_role.notable", "person_role.rider"]

var player: Node3D


func before_each() -> void:
	await super()
	player = Node3D.new()
	player.name = "GiantStandIn"
	player.position = Vector3(0, 0.05, 6)
	world.add_child(player)
	player.add_to_group("player")


func _civilian(scene: String, record: String, id: String, pos: Vector3, ai := false, faction := "village") -> Civilian:
	var v := (load(scene) as PackedScene).instantiate() as Civilian
	v.entity_id = id
	v.ai_enabled = ai
	v.faction = faction
	(v.get_node("CombatEntity") as CombatEntity).definition_id = record
	v.position = pos
	world.add_child(v)
	return v


func test_every_record_names_a_body_the_manifest_has() -> void:
	for r: String in ROLES:
		var rec := PersonLook.role_record(r)
		assert_false(rec.is_empty(), "%s is a person_role record" % r)
		assert_true(PersonModel.has_role(PersonLook.asset_role(r)), "%s draws from a role of the manifest" % r)
		var all: Array = (PersonModel.index().roles[PersonLook.asset_role(r)] as Dictionary).get("variants", [])
		for v: Variant in rec.get("variants", []):
			assert_true(all.has(v), "%s's pool variant %s is the manifest's" % [r, v])
	assert_eq((PersonLook.role_record("person_role.villager").variants as Array).size(), 5,
		"five villagers (three men, two women)")
	for id: String in GameData.records_of_type("npc").map(func(d: Dictionary) -> String: return str(d.id)):
		var body: Variant = GameData.get_record(id).get("body")
		assert_true(typeof(body) == TYPE_DICTIONARY, "%s names a body" % id)
	var seen := {}
	for id: String in NAMED:
		var rec := GameData.get_record(id)
		var spec := PersonLook.spec(rec.get("body"), "test." + id, "", float(rec.get("height_m", 1.8)), {})
		assert_eq(str(spec.variant), str(NAMED[id]), "%s is its own variant" % id)
		assert_eq(str(spec.role), "elder" if str(spec.variant).begins_with("elder_") else "notable",
			"%s is a notable (or an elder)" % id)
		assert_false(seen.has(spec.variant), "%s's variant is no one else's" % id)
		seen[spec.variant] = true
	var corvane := GameData.get_record("enemy.corvane")
	var c := PersonLook.spec(corvane.get("body"), "test.corvane", "aldmere", float(corvane.height_m), {})
	assert_near(float(c.height_scale), 2.0 / 1.8, 1e-4, "Corvane at his record's 2.0 m")
	assert_eq(c.gear, ["sword"], "with a sword")


func test_headless_the_townsfolk_draw_nothing_and_keep_the_pivots() -> void:
	assert_false(PersonRig.layers_enabled(), "the people are off headless (ResetHooks)")
	for scene: String in [VILLAGER, ELDER]:
		var v := _civilian(scene, "npc.villager" if scene == VILLAGER else "npc.edda", "test.headless_" + scene.get_file(),
			Vector3(1, 0.05, 0))
		await step_ticks(2)
		var rig := v.rig as PersonRig
		assert_true(rig != null, "%s: Visual is a PersonRig" % scene.get_file())
		assert_true(rig.model() == null and rig.level == PersonRig.Level.NONE, "%s: no model, no level" % scene.get_file())
		assert_true(rig.body.has_node("ShoulderR") and rig.body.has_node("HipL") and rig.body.has_node("Torso"),
			"%s: the brain's pivots stay" % scene.get_file())
		assert_eq(rig.body.find_children("*", "MeshInstance3D", true, false).size(), 0, "%s: no box mesh" % scene.get_file())
		assert_near(rig.render_lod_m, 45.0, 1e-4, "%s: the people's 45 m" % scene.get_file())
		v.queue_free()
		await step_ticks(1)


func test_villagers_and_named_characters_are_skinned_with_their_looks() -> void:
	PersonRig.enable_for_tests()
	var v := _civilian(VILLAGER, "npc.villager", "test.villager_a", Vector3(-1, 0.05, 0))
	var edda := _civilian(ELDER, "npc.edda", "test.edda", Vector3(1, 0.05, 0), false, "brannock")
	var corvane := (load(CORVANE) as PackedScene).instantiate() as EnemyActor
	corvane.entity_id = "test.corvane"
	corvane.ai_enabled = false
	corvane.position = Vector3(3, 0.05, 0)
	world.add_child(corvane)
	await step_ticks(2)
	PersonRig.decide_now()
	await step_ticks(1)   # (a rig promoted on one frame attaches its model on its next _process)
	var vr := v.rig as PersonRig
	assert_true(vr.skinned(), "the villager is skinned near the giant")
	var pool: Array = PersonLook.role_record("person_role.villager").variants
	assert_true(pool.has(vr.model().variant), "a villager of the pool (%s)" % vr.model().variant)
	assert_eq(vr.model().variant, str(pool[absi(hash("test.villager_a")) % pool.size()]), "by its id's hash")
	assert_eq(vr.current_clip(), "idle", "standing: the idle clip, never a bind pose")
	var er := edda.rig as PersonRig
	assert_true(er.skinned() and er.model().role == "notable" and er.model().variant == "edda", "Edda as herself")
	var mat := er.model().material
	assert_true((mat.get_shader_parameter("hair_color") as Color).is_equal_approx(Color.html("#3a2a1e")), "her hair")
	assert_true((mat.get_shader_parameter("faction_color") as Color).is_equal_approx(
		PersonLook.faction_color("person_role.notable", "brannock")), "Brannock's colour on her tabard")
	assert_near(float(er.body_spec().height_scale), 1.7 / 1.8 * 0.93, 1e-4, "her height: 1.7 m, a woman's 0.93")
	assert_near(er.model().scale.y, 1.7 / 1.8 * 0.93, 1e-3, "the model at that height")
	var cr := corvane.rig as PersonRig
	assert_true(cr.skinned() and cr.model().variant == "corvane", "Corvane skinned as himself")
	assert_near(cr.model().scale.y, 2.0 / 1.8, 1e-3, "at 2.0 m")
	assert_true(cr.weapon_socket() != null and cr.weapon_socket().get_node_or_null("Gear_sword") != null, "his sword in the fist")
	var stats := PersonRig.run_stats()
	for want: String in ["edda", "corvane"]:
		assert_true((stats.variants as Array).has(want), "PEOPLE_STATS counts %s drawn" % want)


func test_a_civilian_flees_on_the_flee_clip_and_cowers_with_nowhere_to_run() -> void:
	PersonRig.enable_for_tests()
	var v := _civilian(VILLAGER, "npc.villager", "test.flee", Vector3(0, 0.05, 0))
	await step_ticks(2)
	PersonRig.decide_now()
	await step_ticks(1)
	var rig := v.rig as PersonRig
	assert_true(rig.skinned(), "skinned")
	# fleeing with nowhere to go (no safe marker in this world): it stands, then cowers
	v.brain.start_fleeing("giant")
	assert_eq(v.brain.state, CivilianBrain.State.FLEE, "the villager flees")
	await step_ticks(int(PersonRig.COWER_AFTER_S * 60.0) + 4)
	assert_eq(rig.current_clip(), "cower", "with nowhere to run it cowers")
	assert_eq(String(rig.model().player().current_animation), "people/cower", "on the cower clip")
	# running: the flee clip, back to the cower when it stops again
	v.process_mode = Node.PROCESS_MODE_DISABLED   # (held still: the rig reads the velocity set here)
	rig.process_mode = Node.PROCESS_MODE_ALWAYS
	v.velocity = Vector3(3.2, 0, 0)
	await step_ticks(3)
	assert_eq(rig.current_clip(), "flee", "running away: the flee clip")
	v.velocity = Vector3.ZERO
	v.process_mode = Node.PROCESS_MODE_INHERIT
	rig.process_mode = Node.PROCESS_MODE_INHERIT
	# indoors: hidden, it leaves its level and its model goes back
	v.brain.state = CivilianBrain.State.SAFE
	await step_ticks(3)
	assert_true(v.sheltered and not v.visible, "it went indoors")
	PersonRig.decide_now()
	assert_true(rig.level == PersonRig.Level.DORMANT and rig.model() == null, "and left its level and its model")
	assert_eq(CrowdRenderer.civilian_pose(v), "hold", "a crowd's civilian standing holds")
