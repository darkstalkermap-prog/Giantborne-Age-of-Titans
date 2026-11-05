extends IntegrationSuite
## P17b: regression tests for the two follow-ups docs/plans/FOLLOWUPS.md gives the balance package.
##   * The force branch's return leg put 16 hostile combatants round the giant: Thornwick's six
##     guards (a garrison outside the budget, turned hostile by the smashed barricade) beside the
##     village ambush and the return patrol, over the 12-active budget. A faction's armed members now
##     count toward the budget while their faction is hostile (EncounterDirector.counts()), so the
##     other encounters' members wait for room while they fight. On the director test level
##     (scenes/test/director_test.tscn): the soldiers' encounter is made a faction garrison outside
##     the budget, the 14-member budget encounter stands in for the ambush and the return patrol.
##   * The Valley drew 500-1,350 calls per view, most of them props built from one box per plank.
##     The prop builders merge each visual group into one mesh per material
##     (SceneKit.merge_meshes): the merge itself, and the shipped prop scenes as built. (The draw
##     calls themselves are measured with P14's Valley walk: docs/PERFORMANCE.md.)

const DIRECTOR_LEVEL := "res://scenes/test/director_test.tscn"
const SOLDIERS := "encounter.director_test_soldiers"
const BUDGET := "encounter.director_test_budget"
const FACTION := "testfolk"
const HOSTILE_FLAG := "faction.testfolk.hostile"

var level: LevelRoot
var director: EncounterDirector


func after_each() -> void:
	if level != null and is_instance_valid(level):
		level.queue_free()
		await get_tree().process_frame
		await get_tree().process_frame
	level = null
	director = null
	await super()


func _on_member_spawned(_encounter_id: String, _entity_id: String, node: Node3D) -> void:
	if "ai_enabled" in node:
		node.set("ai_enabled", false)


## The soldiers' encounter as a faction garrison outside the budget (Thornwick's guards).
func _garrison() -> void:
	var rec := GameData.get_record(SOLDIERS)
	var spawns: Array = []
	for s: Dictionary in rec.spawns:
		var c := s.duplicate(true)
		c["faction"] = FACTION
		spawns.append(c)
	TestFixtures.record_override(SOLDIERS, {"counts_toward_budget": false, "spawns": spawns})


func _load_level() -> void:
	level = (load(DIRECTOR_LEVEL) as PackedScene).instantiate() as LevelRoot
	world.add_child(level)
	director = level.director()
	director.member_spawned.connect(_on_member_spawned)
	level.player().router.use_injection = true
	await step_ticks(1)


func _kill(entity_id: String) -> void:
	var n := director.spawned(entity_id)
	queue_hit("player", entity_id, n.global_position + Vector3(0, 0, 2), 5000.0)
	await step_ticks(1)


func _spawned_of(prefix: String) -> int:
	var n := 0
	for id in director.encounter_ids():
		for e in director.members_of(id):
			if e.begins_with(prefix) and director.member_status(e) == EncounterDirector.SPAWNED:
				n += 1
	return n


## A neutral garrison spawns outside the budget and costs nothing; once its faction is hostile its
## members count, so nothing else spawns until the count is back under the cap; killing them frees
## the room for the waiting members of the other encounter.
func test_a_hostile_faction_counts_toward_the_budget() -> void:
	_garrison()
	await _load_level()
	assert_eq(director.max_active_enemies, 12, "the level record's budget")
	director.force_activate(BUDGET)
	director.force_activate(SOLDIERS)
	await step_ticks(2)
	assert_eq(_spawned_of("test.director.soldier_"), 3, "the neutral garrison spawned beyond the budget")
	assert_eq(director.active_combatant_count(), 12, "and does not count while neutral (12 budgeted)")
	WorldState.set_flag(HOSTILE_FLAG, true)
	assert_eq(director.active_combatant_count(), 15, "hostile, its three soldiers count (12 + 3)")
	for id in ["test.director.budget_w1", "test.director.budget_w2", "test.director.budget_w3"]:
		await _kill(id)
	assert_eq(director.active_combatant_count(), 12, "three of the budgeted members died")
	director.update_now()
	await step_ticks(1)
	assert_eq(director.member_status("test.director.budget_s6"), EncounterDirector.UNSPAWNED,
		"the 13th budgeted member still waits: the hostile garrison holds the room")
	assert_eq(director.active_combatant_count(), 12, "the count stays at the cap")
	for id in ["test.director.soldier_1", "test.director.soldier_2"]:
		await _kill(id)
	director.update_now()
	await step_ticks(1)
	assert_eq(director.member_status("test.director.budget_s6"), EncounterDirector.SPAWNED,
		"two soldiers died: the 13th spawned")
	assert_eq(director.member_status("test.director.budget_s7"), EncounterDirector.SPAWNED, "and the 14th")
	assert_eq(director.active_combatant_count(), 12, "12 combatants, never more once the faction turned")


## The force branch's return leg: the faction is already hostile when its garrison activates, so
## the garrison waits for room like any budgeted encounter, the budget never goes over 12, and the
## garrison spawns as the other members die.
func test_a_hostile_garrison_waits_for_room_and_the_budget_holds() -> void:
	_garrison()
	WorldState.set_flag(HOSTILE_FLAG, true)
	await _load_level()
	director.force_activate(BUDGET)
	director.force_activate(SOLDIERS)
	var peak := 0
	for i in 3:
		await step_ticks(1)
		peak = maxi(peak, director.active_combatant_count())
	assert_eq(director.active_combatant_count(), 12, "17 hostile members requested, 12 in the world")
	assert_eq(_spawned_of("test.director.soldier_"), 0, "the hostile garrison waits (the budget encounter came first)")
	for id in ["test.director.budget_w1", "test.director.budget_w2", "test.director.budget_w3",
			"test.director.budget_w4"]:
		await _kill(id)
		peak = maxi(peak, director.active_combatant_count())
	director.update_now()
	await step_ticks(1)
	peak = maxi(peak, director.active_combatant_count())
	assert_eq(director.member_status("test.director.budget_s7"), EncounterDirector.SPAWNED,
		"the budget encounter's waiting members spawned first")
	assert_eq(_spawned_of("test.director.soldier_"), 2, "then two of the garrison")
	assert_eq(director.active_combatant_count(), 12, "the room is full again")
	assert_true(peak <= 12 and director.peak_active <= 12, "never more than 12 (peak %d / %d)" % [peak,
		director.peak_active])


## Members whose definition is not an enemy (villagers, the elder) never count, hostile or not.
func test_npc_members_of_a_hostile_faction_do_not_count() -> void:
	var m := EncounterDirector.Member.new()
	m.faction = FACTION
	m.budgeted = false
	m.enemy_def = false
	WorldState.set_flag(HOSTILE_FLAG, true)
	assert_false(EncounterDirector.counts(m), "an NPC of a hostile faction is not a combatant")
	m.enemy_def = true
	assert_true(EncounterDirector.counts(m), "an armed member of a hostile faction is")
	WorldState.set_flag(HOSTILE_FLAG, false)
	assert_false(EncounterDirector.counts(m), "not while the faction is at peace")
	m.faction = ""
	assert_false(EncounterDirector.counts(m), "an unbudgeted member without a faction never counts")
	m.budgeted = true
	assert_true(EncounterDirector.counts(m), "a budgeted enemy always counts")


# --------------------------------------------------------------------------- batched props

## SceneKit.merge_meshes: the visible parts of a group become one mesh with a surface per material,
## at the same places; hidden parts, parts named to keep and other node types stay; groups emptied
## by the merge go.
func test_merge_meshes_makes_one_mesh_per_material() -> void:
	var kit := SceneKit.new("user://p17b_merge_probe")
	kit.add_material("probe_wood", Color(0.5, 0.3, 0.2), 0.9)
	kit.add_material("probe_iron", Color(0.3, 0.3, 0.3), 0.5)
	var root := kit.n3("Intact")
	var leaf := kit.n3("Leaf", Vector3(2, 0, 0))
	leaf.add_child(kit.box("Plank0", Vector3(1, 2, 0.2), Vector3(0, 1, 0), "probe_wood"))
	leaf.add_child(kit.box("Plank1", Vector3(1, 2, 0.2), Vector3(1, 1, 0), "probe_wood"))
	leaf.add_child(kit.box("Band", Vector3(2, 0.2, 0.3), Vector3(0.5, 1.5, 0), "probe_iron"))
	root.add_child(leaf)
	var hidden := kit.box("Hidden", Vector3.ONE, Vector3.ZERO, "probe_wood")
	hidden.visible = false
	root.add_child(hidden)
	root.add_child(kit.box("Glow", Vector3.ONE, Vector3(0, 3, 0), "probe_iron"))
	var label := Label3D.new()
	label.name = "Sign"
	root.add_child(label)
	assert_eq(kit.merge_meshes(root, PackedStringArray(["Glow"])), 3, "three parts merged")
	var merged := root.get_node_or_null("Merged") as MeshInstance3D
	assert_true(merged != null, "one Merged mesh in the group")
	if merged != null:
		assert_eq(merged.mesh.get_surface_count(), 2, "a surface per material (wood, iron)")
		assert_eq(merged.mesh.surface_get_material(0), kit.mats["probe_wood"], "the wood surface")
		assert_eq(merged.mesh.surface_get_material(1), kit.mats["probe_iron"], "the iron surface")
		var box := merged.get_aabb()
		assert_true(box.has_point(Vector3(3.4, 1.0, 0.0)) and box.has_point(Vector3(1.6, 0.1, 0.0)),
			"at the parts' places (the leaf's offset baked in): %s" % box)
	assert_true(root.get_node_or_null("Leaf") == null, "the emptied group is gone")
	assert_true(root.get_node_or_null("Hidden") != null, "a hidden part stays apart")
	assert_true(root.get_node_or_null("Glow") != null, "a kept part stays apart")
	assert_true(root.get_node_or_null("Sign") != null, "other node types stay")
	assert_eq(kit.merge_meshes(kit.n3("Empty")), 0, "nothing to merge: nothing changes")
	root.free()


## The shipped prop scenes as built: each visual group (Frame, Intact, Cracked, Broken, Visual, a
## static body) holds at most one mesh node, its surfaces one per material; the stage visuals are
## still the groups BreakableProp shows and hides; the shrine's glow and the waystone-like parts a
## script toggles stay apart.
func test_shipped_props_draw_one_mesh_per_group() -> void:
	var cases := {"gate_practice": ["Frame", "Intact", "Cracked", "Broken"],
		"gate_fortified": ["Frame", "Intact"], "tree_small": ["Intact", "Broken"], "deadfall": ["Intact", "Broken"],
		"cart_barricade": ["Intact", "Broken"], "cairn": ["Intact", "Broken"], "crate": ["Intact", "Broken"],
		"fence_wood": ["Intact", "Broken"], "ancient_oak": ["Visual"], "weapon_rack": ["Frame"],
		"item_pickup": ["Visual"]}
	for scene: String in cases:
		var n := (load("res://scenes/world/%s.tscn" % scene) as PackedScene).instantiate()
		for group: String in cases[scene]:
			var g := n.get_node_or_null(group)
			assert_true(g != null, "%s keeps its %s group" % [scene, group])
			if g == null:
				continue
			var meshes := g.find_children("*", "MeshInstance3D", true, false)
			assert_eq(meshes.size(), 1, "%s/%s: one mesh node (%d)" % [scene, group, meshes.size()])
			for mi: MeshInstance3D in meshes:
				var mats := {}
				for i in mi.mesh.get_surface_count():
					mats[mi.mesh.surface_get_material(i)] = true
				assert_eq(mats.size(), mi.mesh.get_surface_count(), "%s/%s: one surface per material" % [scene, group])
		n.free()
	var shrine := (load("res://scenes/world/shrine.tscn") as PackedScene).instantiate()
	assert_true(shrine.get_node_or_null("Visual/Glow") is MeshInstance3D, "the shrine's glow stays apart (Shrine lights it)")
	assert_false((shrine.get_node("Visual/Glow") as Node3D).visible, "and dark")
	assert_true(shrine.get_node_or_null("Merged") is MeshInstance3D, "its stone, dais and cap merged")
	shrine.free()
