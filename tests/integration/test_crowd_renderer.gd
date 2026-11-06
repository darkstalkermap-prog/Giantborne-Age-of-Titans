extends IntegrationSuite
## P30 (plan M6-M9 §2.10, §3.13 tests, decision 19): the crowd renderer. A formation of eight pikemen
## and a banner far from the giant is drawn as one MultiMesh per pose in use (eight instances, their
## rigs hidden and idle), the banner always by its own rig with its flag painted in the formation's
## colour; the pose follows the formation (hold, brace when braced or aware); near the giant at
## most six members are promoted to their own rigs (the nearest), a striking or held member is
## promoted wherever it stands, the dead always show their own rig and never count; a member that
## leaves the formation and release_all() give every rig back. AI is off and the giant is a stand-in
## (a node of group "player" at stage 1's distance scale): this is presentation.

const PIKEMAN := "res://scenes/enemies/pikeman.tscn"
const BANNERMAN := "res://scenes/enemies/bannerman.tscn"

var player: Node3D
var f: Formation
var r: CrowdRenderer
var pikes: Array[EnemyActor] = []
var banner: EnemyActor


func before_each() -> void:
	await super()
	pikes.clear()
	player = Node3D.new()
	player.name = "GiantStandIn"
	player.position = Vector3(0, 0.05, 40)
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
	await step_ticks(1)


func after_each() -> void:
	if is_instance_valid(r):
		r.release_all()
	f.dissolve()
	await super()


static func _shown(e: EnemyActor) -> bool:
	return (e.get_node("Visual") as Node3D).visible


func _visible_sets() -> int:
	var n := 0
	for c in r.get_children():
		if c is MultiMeshInstance3D and (c as MultiMeshInstance3D).visible:
			n += 1
	return n


## One fixture for the whole sequence (the default tier's time budget): far, near, striking, dead,
## leaving, released, dissolved.
func test_the_crowd_draws_promotes_and_releases_its_members() -> void:
	await _far_members_are_one_multimesh_per_pose_and_the_banner_keeps_its_rig()
	await _near_the_giant_at_most_six_are_promoted_and_strikers_first()
	await _the_dead_show_their_rig_and_leavers_and_release_get_theirs_back()


func _far_members_are_one_multimesh_per_pose_and_the_banner_keeps_its_rig() -> void:
	r.refresh()
	assert_eq(r.instance_count(), 8, "eight members drawn as instances")
	assert_eq(int(r.pose_counts.get("hold", 0)), 8, "all holding")
	assert_eq(_visible_sets(), 1, "one draw call for the rank and file")
	for e in pikes:
		assert_false(_shown(e), "%s's own rig is hidden" % e.entity_id)
		assert_false((e.get_node("Visual") as Node).is_processing(), "and idle")
	assert_true(_shown(banner), "the banner keeps its rig")
	var flag := banner.get_node("Visual/Body/FlagPivot/Flag") as MeshInstance3D
	assert_true(flag.material_override is StandardMaterial3D and \
		(flag.material_override as StandardMaterial3D).albedo_color.is_equal_approx(f.banner_color),
		"its flag is painted in the formation's colour")
	var sway := (banner.get_node("Visual/Body/FlagPivot") as Node3D).rotation.y
	r._time += 0.45
	r.refresh()
	assert_true(absf((banner.get_node("Visual/Body/FlagPivot") as Node3D).rotation.y - sway) > 0.01, "the flag sways")
	f.state = "braced"
	r.refresh()
	assert_eq(int(r.pose_counts.get("brace", 0)), 8, "braced: the brace pose")
	assert_eq(int(r.pose_counts.get("hold", 0)), 0, "and no hold")
	assert_eq(_visible_sets(), 1, "still one draw call")
	f.state = "formed"
	f.aware = true
	r.refresh()
	assert_eq(int(r.pose_counts.get("brace", 0)), 8, "aware and standing: pikes levelled")


func _near_the_giant_at_most_six_are_promoted_and_strikers_first() -> void:
	f.state = "formed"
	f.aware = false
	player.global_position = Vector3(0, 0.05, -14)   # within 20 m of every member
	r.refresh()
	assert_eq(r.promoted.size(), CrowdRenderer.MAX_PROMOTED, "six promoted")
	assert_eq(r.instance_count(), 8 - CrowdRenderer.MAX_PROMOTED, "the rest in the crowd")
	var by_distance := pikes.duplicate()
	by_distance.sort_custom(func(a: EnemyActor, b: EnemyActor) -> bool:
		return a.global_position.distance_squared_to(player.global_position) < b.global_position.distance_squared_to(player.global_position))
	for i in CrowdRenderer.MAX_PROMOTED:
		assert_true(r.promoted.has(by_distance[i].entity_id), "the nearest are promoted (%s)" % by_distance[i].entity_id)
		assert_true(_shown(by_distance[i]), "and show their rig")
	# far again: a striking member is promoted wherever it stands
	player.global_position = Vector3(0, 0.05, 60)
	var striker := pikes[6]
	striker.controller.request(&"attack", {"action_id": "ability.pike_thrust"})
	assert_true(striker.controller.action != null, "the member strikes")
	r.refresh()
	assert_true(r.promoted.has(striker.entity_id), "a striking member is promoted")
	assert_true(_shown(striker), "its rig shows the strike")
	assert_eq(r.instance_count(), 7, "the other seven stay in the crowd")


func _the_dead_show_their_rig_and_leavers_and_release_get_theirs_back() -> void:
	player.global_position = Vector3(0, 0.05, 60)
	r.refresh()
	var base := r.instance_count()   # nine: the striker of the last step may still strike
	var dead := pikes[2]
	queue_hit(pikes[0].entity_id, dead.entity_id, player.global_position, 100000.0)
	await step_ticks(1)
	assert_false(dead.entity.is_alive(), "a member died")
	r.refresh()
	assert_true(_shown(dead), "the dead show their own rig (the fall)")
	assert_false(r.promoted.has(dead.entity_id), "and never count as promoted")
	assert_eq(r.instance_count(), base - 1, "one fewer in the crowd")
	var leaver := pikes[4]
	f.remove_member(leaver)
	r.refresh()
	assert_true(_shown(leaver), "a member that left gets its rig back")
	assert_eq(r.instance_count(), base - 2, "two fewer in the crowd")
	r.release_all()
	for e in pikes:
		assert_true(_shown(e), "release_all gives %s its rig back" % e.entity_id)
	f.dissolved = true
	r.refresh()
	assert_eq(r.instance_count(), 0, "a dissolved formation draws nothing")
