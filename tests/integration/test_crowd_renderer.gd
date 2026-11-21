extends IntegrationSuite
## P30 (plan M6-M9 §2.10, §3.13 tests, decision 19), extended by P60 (plan M11 §2.9, §3.13 tests): the crowd
## renderer draws the people PersonRig did not skin. A formation of eight pikemen and a banner, every person
## skinnable but the cap at 0, is drawn as one MultiMesh per role and pose plus one per piece of gear (P59's
## crowd-pose meshes, the pikes and the banner's sword), each instance with its palette row, its flash and its
## faction's row; the banner's flag is painted in the formation's colour and sways; the pose follows the formation
## (hold, brace when braced or aware). With the cap at 4, the nearest four are skinned, a striking member is
## skinned wherever it stands; the dead fall skinned and become a corpse instance that frees its slot; a member
## that leaves the formation is drawn by the loners' renderer; a dissolved formation draws nothing. AI is off and
## the giant is a stand-in (a node of group "player" at stage 1's distance scale): this is presentation.

const PIKEMAN := "res://scenes/enemies/pikeman.tscn"
const BANNERMAN := "res://scenes/enemies/bannerman.tscn"

var player: Node3D
var f: Formation
var r: CrowdRenderer
var pikes: Array[EnemyActor] = []
var banner: EnemyActor


func before_each() -> void:
	await super()
	PersonRig.enable_for_tests()
	PersonRig.set_cap(0)
	pikes.clear()
	player = Node3D.new()
	player.name = "GiantStandIn"
	player.position = Vector3(0, 0.05, 5)
	world.add_child(player)
	player.add_to_group("player")
	f = Formation.new()
	f.id = "test.crowd"
	f.kind = "pike"
	f.display_name = "Pike Regiment"
	f.ranks = 2
	f.files = 4
	f.rank_spacing_m = 1.6
	f.file_spacing_m = 1.4
	f.banner_id = "test.crowd_banner"
	f.banner_color = Color(0.1, 0.3, 0.8)
	f.place(Vector3(0, 0, -20), PI)   # facing +Z, toward the giant
	for i in 8:
		var e := TestSpawn.enemy(world, PIKEMAN, f.slot_position(i), "test.crowd_%d" % i, false, PI)
		pikes.append(e)
		f.add_member(e, i)
	banner = TestSpawn.enemy(world, BANNERMAN, f.slot_position(Formation.BANNER_SLOT), "test.crowd_banner", false, PI)
	f.set_banner(banner)
	r = CrowdRenderer.new()
	r.formation = f
	world.add_child(r)
	await step_ticks(2)


func after_each() -> void:
	if is_instance_valid(r):
		r.release_all()
	f.dissolve()
	await super()


static func _rig(e: EnemyActor) -> PersonRig:
	return e.get_node("Visual") as PersonRig


## The instance of `e` in the set of `key` (person role | pose | piece): its custom data, or Color(-1) when not drawn
## there (the renderer's record of the frame: the headless renderer keeps no instance data).
func _custom_of(e: EnemyActor, key: String) -> Color:
	var d: Array = r.drawn.get(e.entity_id, [])
	return d[1] if not d.is_empty() and str(d[0]) == key else Color(-1, -1, -1, -1)


## One fixture for the whole sequence (the default tier's time budget): the crowd, the cap, the dead, leaving,
## dissolved.
func test_the_crowd_draws_its_people_and_hands_them_to_the_skinned_level() -> void:
	await _the_formation_is_one_multimesh_per_role_pose_and_gear()
	await _the_cap_skins_the_nearest_and_strikers_first()
	await _the_dead_fall_skinned_lie_as_a_corpse_and_leavers_go_to_the_loners()


func _the_formation_is_one_multimesh_per_role_pose_and_gear() -> void:
	r.refresh()
	assert_eq(r.instance_count(), 9, "eight members and the banner's body drawn as instances")
	assert_eq(int(r.pose_counts.get("hold", 0)), 9, "all holding")
	assert_eq(r.promoted.size(), 0, "none skinned (the cap is 0)")
	assert_eq(r.draw_sets(), 3, "three draw calls: the bodies, the pikes, the banner's sword")
	for e in pikes:
		assert_false(_rig(e).skinned(), "%s has no skinned body" % e.entity_id)
		assert_true(r.crowded.has(e.entity_id), "%s is in the crowd" % e.entity_id)
	var rows := {}
	for e in pikes:
		var c := _custom_of(e, "person_role.soldier|hold|")
		assert_eq(int(c.r), int(_rig(e).body_spec().row), "%s: its palette row in the custom data" % e.entity_id)
		rows[int(c.r)] = true
	assert_true(rows.size() >= 3, "the eight show several palette rows (%d)" % rows.size())
	# a flash reaches a crowd instance
	pikes[3].flash(1.0)
	await step_ticks(1)
	r.refresh()
	assert_true(_custom_of(pikes[3], "person_role.soldier|hold|").g > 0.3, "a member's hit flash is in its instance")
	assert_true(_custom_of(pikes[4], "person_role.soldier|hold|").g == 0.0, "and only in its own")
	var flag := banner.get_node("Visual/Body/FlagPivot/Flag") as MeshInstance3D
	assert_true(flag.material_override is StandardMaterial3D and \
		(flag.material_override as StandardMaterial3D).albedo_color.is_equal_approx(f.banner_color),
		"the banner's flag is painted in the formation's colour")
	var sway := (banner.get_node("Visual/Body/FlagPivot") as Node3D).rotation.y
	r._time += 0.45
	r.refresh()
	assert_true(absf((banner.get_node("Visual/Body/FlagPivot") as Node3D).rotation.y - sway) > 0.01, "the flag sways")
	f.state = "braced"
	r.refresh()
	assert_eq(int(r.pose_counts.get("brace", 0)), 9, "braced: the brace pose")
	assert_eq(r.draw_sets(), 3, "still three draw calls")
	f.state = "formed"
	f.aware = true
	r.refresh()
	assert_eq(int(r.pose_counts.get("brace", 0)), 9, "aware and standing: pikes levelled")
	f.aware = false


func _the_cap_skins_the_nearest_and_strikers_first() -> void:
	PersonRig.set_cap(4)
	player.global_position = Vector3(0, 0.05, -14)
	await step_ticks(1)
	PersonRig.decide_now()   # (the frames decide every PersonRig.ALLOC_FRAMES frames)
	r.refresh()
	assert_eq(r.promoted.size(), 4, "four skinned (the cap)")
	assert_eq(r.instance_count(), 5, "the rest in the crowd")
	var all: Array = pikes.duplicate()
	all.append(banner)
	all.sort_custom(func(a: EnemyActor, b: EnemyActor) -> bool:
		return a.global_position.distance_squared_to(player.global_position) < b.global_position.distance_squared_to(player.global_position))
	for i in 4:
		assert_true(_rig(all[i]).skinned(), "the nearest are skinned (%s)" % all[i].entity_id)
	all.erase(banner)
	var striker: EnemyActor = all[7]
	striker.controller.request(&"attack", {"action_id": "ability.pike_thrust"})
	assert_true(striker.controller.action != null, "the farthest pikeman strikes")
	await step_ticks(1)
	PersonRig.decide_now()
	r.refresh()
	assert_eq(_rig(striker).level, PersonRig.Level.SKINNED, "a striking member is skinned first")
	assert_eq(r.promoted.size(), 4, "and the cap holds")


func _the_dead_fall_skinned_lie_as_a_corpse_and_leavers_go_to_the_loners() -> void:
	PersonRig.set_cap(2)   # (the striker of the last step may still strike)
	var dead := pikes[2]
	queue_hit(pikes[0].entity_id, dead.entity_id, player.global_position, 100000.0)
	await step_ticks(2)
	assert_false(dead.entity.is_alive(), "a member died")
	PersonRig.decide_now()
	await step_ticks(1)   # (its body takes the death clip in its frame)
	r.refresh()
	assert_true(_rig(dead).skinned() and _rig(dead).current_clip() == "death", "the dead fall skinned (first in the cap)")
	_rig(dead).set("_dead_t", 60.0)   # the fall and CORPSE_AFTER_S are over
	PersonRig.decide_now()
	r.refresh()
	assert_eq(_rig(dead).level, PersonRig.Level.CORPSE, "then lie as a corpse")
	assert_false(_rig(dead).skinned(), "which frees its slot")
	assert_eq(int(r.pose_counts.get("corpse", 0)), 1, "drawn as the corpse pose")
	var leaver := pikes[4]
	f.remove_member(leaver)
	await step_ticks(2)
	r.refresh()
	assert_false(r.crowded.has(leaver.entity_id), "a member that left is not this formation's")
	var lr := PersonRig.loner_renderer()
	assert_true(lr != null and lr.crowded.has(leaver.entity_id), "the loners' renderer draws it")
	f.dissolved = true
	r.refresh()
	assert_eq(r.instance_count(), 0, "a dissolved formation draws nothing")
