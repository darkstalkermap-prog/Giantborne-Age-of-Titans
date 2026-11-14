extends IntegrationSuite
## M8 screenshot pass (V1): trees no longer hide the giant or what he fights. The screenshot pass found
## the Greywood's pines between the camera and the giant on arriving at the Hollowmere waystone at
## stage 4 (05_greywood_arrival_banner), the camera inside a pine at the dire wolves (05_pack_close)
## and pines filling the view of the Troll Matriarch's fight at her den (07_matriarch). The trees are
## now drawn with the scenery fade shader (SceneryFade), which dithers out what lies near the camera
## and in the cones from the camera to the giant and to the locked target.
##
## The measure (TreeSight): sight lines from the camera to twelve points on a body, and the first tree
## surface each meets - the real triangles of the shared tree meshes at every tree of the loaded
## chunks - drawn with less than half its pixels faded (the fade of the material each tree is drawn
## with: the old StandardMaterial3D fades nothing). On the real world (scenes/world/world.tscn,
## deterministic streaming) at stage 4 with the camera the game leaves (behind the giant, pitched
## down 18 degrees, the stage's camera distance) and at the stage's zoom limits, and in the Valley at
## stage 1:
##   * the Hollowmere waystone on arrival: a pine 9-11 m from the camera stood in front of half of him
##     (6 of 12 lines at 15.5 m, 5 at 12 m, 6 at 20.5 m). W23 (P39f): that pine stood in the waystone's
##     clearing, where the world builder's no-scenery grid never took its marks; since the grid's fix and
##     the world's rebuild no tree stands in his lines there at any zoom (the fade's work is checked at the
##     den, the pack and in the Valley);
##   * the way into the Matriarch's den, beside a pine (he stands in its lowest crown): all 12 lines,
##     at every zoom; and with the Troll Matriarch locked (the director wakes her den), the lines to
##     her;
##   * the dire pack's ride (1 line at 20.5 m);
##   * the Valley beside the forest wolves' clearing at stage 1: all 12 lines.
## Each place also checks that trees do stand in those lines (the fade has work to do there).

const SCENE := "res://scenes/world/world.tscn"
const VALLEY := "res://scenes/world/valley.tscn"
const MATRIARCH := "world.greywood.troll_matriarch"
const DEN_FROM := Vector3(-745, 0, -318)
const DEN_TOWARD := Vector3(-770, 0, -336)
const PACK := Vector3(-540, 0, -140)
const PACK_FROM := Vector3(-560, 0, -158)
const VALLEY_SPOT := Vector3(-154, 0.1, 63)
const VALLEY_YAW_DEG := 315.0

var w: WorldRoot = null


func after_each() -> void:
	w = null
	await super()


static func _profile_of_stage(stage: int) -> Dictionary:
	for rec: Dictionary in GameData.records_of_type("growth_profile"):
		if int(rec.get("stage", 0)) == stage:
			return rec
	return {}


static func _yaw_from(from: Vector3, to: Vector3) -> float:
	var d := to - from
	return atan2(-d.x, -d.z)


## The world at stage 4, the giant out of the way while rings load.
func _world() -> GiantPlayer:
	w = (load(SCENE) as PackedScene).instantiate() as WorldRoot
	world.add_child(w)
	w.streamer.deterministic = true
	var p := w.player()
	p.router.use_injection = true
	p.entity.apply_status("status.debug_invulnerable", NAN, -1.0, "test")
	p.set_profile(_profile_of_stage(4))
	return p


## Loads the ring at `t`, puts the giant there on the ground as an arrival does (GameSession.
## place_player: the camera behind him) and sets the camera up as a level load does (the stage's
## camera distance, the default pitch); then lets the arm settle.
func _arrive(p: GiantPlayer, t: Transform3D) -> void:
	p.process_mode = Node.PROCESS_MODE_DISABLED
	p.global_position = t.origin + Vector3.UP * 150.0
	var guard := 0
	while not w.streamer.ring_ready(t.origin) and guard < 1500:
		w.streamer.load_ring_slice(t.origin)
		await step_ticks(1)
		guard += 1
	var y := w.height_at(t.origin)
	if is_finite(y):
		t.origin.y = y + 0.1
	p.process_mode = Node.PROCESS_MODE_INHERIT
	GameSession.place_player(p, t)
	p.camera_rig.setup(p, p.profile)
	await step_ticks(200)


## The sight lines a tree hides from the camera to `body` (a standing body at `base`, `height` tall,
## `radius` wide), and how many lines meet a tree at all, fading or not.
func _lines(p: GiantPlayer, trees: Array, base: Vector3, height: float, radius: float) -> Dictionary:
	var eye := p.camera_rig.camera.global_position
	var pts := TreeSight.body_points(base, height, radius, eye)
	var crossing := 0
	for q: Vector3 in pts:
		if not TreeSight.first_tree_hit(eye, q, trees).is_empty():
			crossing += 1
	return {"hidden": TreeSight.hidden_lines(eye, pts, trees), "crossing": crossing, "of": pts.size()}


static func _text(hidden: Array) -> String:
	return ", ".join(hidden.map(func(h: Dictionary) -> String:
		return "%s %.1f m from the camera (fade %.2f)" % [h.tree, h.distance, h.fade]))


## The giant's lines at the three arm lengths a player has at stage 4: the camera distance the game
## sets, and the zoom limits. Returns the most lines that met a tree at one of them.
func _check_giant(p: GiantPlayer, place: String) -> int:
	var prof := p.profile
	var most := 0
	for want: float in [float(prof.camera_distance_m), float(prof.camera_zoom_min_m), float(prof.camera_zoom_max_m)]:
		p.camera_rig.desired_distance = want
		await step_ticks(200)
		assert_near(p.camera_rig.current_distance, want, 1.0, "%s: the arm reaches %.1f m (no obstruction)" % [place, want])
		var r := _lines(p, TreeSight.world_trees(w), p.global_position, float(prof.height_m), float(prof.capsule_radius_m))
		most = maxi(most, int(r.crossing))
		assert_eq((r.hidden as Array).size(), 0, "%s, the arm at %.1f m: no tree hides the giant (%d of %d lines meet a tree; hidden: %s)" % [
			place, want, r.crossing, r.of, _text(r.hidden)])
	return most


func test_trees_do_not_hide_the_giant_arriving_at_hollowmere_at_stage_4() -> void:
	var p := await _world()
	var idx := WorldIndex.for_level("level.world")
	var t := idx.spawn_transform("world.cp.hollowmere")
	assert_true(t.origin.is_finite(), "the Hollowmere waystone is in the index")
	await _arrive(p, t)
	assert_near(rad_to_deg(p.camera_rig.pitch), -18.0, 0.5, "the camera as a load leaves it: pitched down 18 degrees")
	assert_near(rad_to_deg(wrapf(p.camera_rig.yaw - p.facing_yaw, -PI, PI)), 0.0, 0.5, "behind the giant")
	var trees := TreeSight.world_trees(w)
	assert_true(trees.size() > 500, "the Greywood's trees are loaded (%d)" % trees.size())
	for tr: Dictionary in trees.slice(0, 5):
		var sm := tr.material as ShaderMaterial
		assert_true(sm != null and sm.shader != null and sm.shader.resource_path == TreeSight.FADE_SHADER,
			"%s is drawn with the scenery fade shader" % tr.key)
	var most := await _check_giant(p, "Hollowmere")
	# W23 (P39f): the waystone's clearing is kept clear now (it held the pine of the screenshot: 4-6 lines).
	assert_eq(most, 0, "the waystone's clearing keeps the pines out of the lines to the giant (%d lines meet one)" % most)


func test_trees_do_not_hide_the_den_fight_or_the_locked_matriarch() -> void:
	var p := await _world()
	await _arrive(p, Transform3D(Basis(Vector3.UP, _yaw_from(DEN_FROM, DEN_TOWARD)), DEN_FROM))
	var most := await _check_giant(p, "the Matriarch's den")
	assert_true(most >= 8, "the giant stands in a pine's crown there (%d lines meet one)" % most)
	# The Matriarch (the director has woken her den), locked as a player locks her: the lines to her and
	# to the giant are clear while the camera frames the lock.
	var m := Sim.get_entity(MATRIARCH)
	assert_true(m != null and m.is_alive(), "the Troll Matriarch is in her den")
	if m == null:
		return
	p.camera_rig.desired_distance = float(p.profile.camera_distance_m)
	p.camera_rig.yaw = _yaw_from(p.global_position, m.actor.global_position)
	await step_ticks(3)
	p.targeting.try_lock()
	assert_eq(p.lock.target_id, MATRIARCH, "she is locked")
	await step_ticks(150)
	var trees := TreeSight.world_trees(w)
	var c := m.combatant
	var r := _lines(p, trees, m.actor.global_position, c.height_m, 2.4)
	assert_true(int(r.crossing) >= 1, "pines stand between the camera and her (%d lines meet one)" % r.crossing)
	assert_eq((r.hidden as Array).size(), 0, "no tree hides the locked Matriarch (%d of %d lines meet a tree; hidden: %s)" % [
		r.crossing, r.of, _text(r.hidden)])
	var g := _lines(p, trees, p.global_position, float(p.profile.height_m), float(p.profile.capsule_radius_m))
	assert_eq((g.hidden as Array).size(), 0, "nor the giant while she is locked (hidden: %s)" % _text(g.hidden))


func test_trees_do_not_hide_the_giant_at_the_dire_pack() -> void:
	var p := await _world()
	await _arrive(p, Transform3D(Basis(Vector3.UP, _yaw_from(PACK_FROM, PACK)), PACK_FROM))
	await _check_giant(p, "the dire pack's ride")


func test_trees_do_not_hide_the_giant_in_the_valley_wood() -> void:
	var v := (load(VALLEY) as PackedScene).instantiate()
	world.add_child(v)
	var p := get_tree().get_first_node_in_group("player") as GiantPlayer
	p.router.use_injection = true
	p.entity.apply_status("status.debug_invulnerable", NAN, -1.0, "test")
	await step_ticks(5)
	GameSession.place_player(p, Transform3D(Basis(Vector3.UP, deg_to_rad(VALLEY_YAW_DEG)), VALLEY_SPOT))
	p.camera_rig.setup(p, p.profile)
	await step_ticks(120)
	assert_eq(int(p.profile.get("stage", 0)), 1, "stage 1")
	var trees := TreeSight.valley_trees(v)
	assert_true(trees.size() > 100, "the Valley's tree parts (%d)" % trees.size())
	var r := _lines(p, trees, p.global_position, float(p.profile.height_m), float(p.profile.capsule_radius_m))
	assert_true(int(r.crossing) >= 8, "a tree's crown stands between the camera and the giant (%d lines meet one)" % r.crossing)
	assert_eq((r.hidden as Array).size(), 0, "no tree hides the giant in the Valley wood (hidden: %s)" % _text(r.hidden))
