extends IntegrationSuite
## Valley revisits at stages 4-6 (P26, plan M6-M9 §5.6; slow, runs with --slow). The Valley was built
## for stages 1-3; a giant that comes back from the world is bigger. Every checkpoint of the Valley
## (its shrines' spawn points and its waystones) is measured at stages 4, 5 and 6, in the state of a
## revisit (the crown taken: every road-blocking prop out of the way and the Citadel Gate breached):
##   * the capsule: the stage's capsule at the respawn point, lifted like the growth check, overlaps
##     no world, breakable or blocker shape;
##   * the camera: the real giant at that stage stands there and the third-person camera, turned to
##     eight bearings, is never inside the world;
##   * the way out: a path on the giant navigation layer (4, the Valley's player_nav_fallback for
##     stages 4-6) to one of the Valley's two exits - the Kings' Door, the Citadel's stair - along
##     which the stage's capsule, swept every SAMPLE_M, fits. That layer is cut for a 2.0 m agent
##     (NAV_RADIUS_M) on 0.5 m cells, so its path hugs corners and trunks closer than a wider capsule
##     walks: a sample fits when the capsule, its bottom lifted by what its rounded bottom rides over
##     (an edge whose contact stays within the body's 46 degree floor angle: 0.67 / 0.89 / 1.13 m at
##     stages 4 / 5 / 6 - kerbs and the feet of ramps), overlaps nothing at the path point or at most
##     (radius - 2.0) + SHIFT_SLACK_M to either side of it - a passage narrower than the capsule still
##     fails, a corner does not; a breakable the stage breaks with a blow (a tree, a fence) is not in
##     its way.
## A checkpoint's limit is the highest stage that passes all three (3 when stage 4 fails: the Valley's
## shrines never grow a giant beyond 3). The test asserts that the layout's max_stage of every
## checkpoint - and so the index's, which travel and respawns read - is that measured limit, and prints
## the table (docs/systems/P26.md). A stage-6 giant then really walks two stretches where the brief's
## strict sampling overlaps most (the Hollow's exit; the Grove through Thornwick's gate and lanes to the
## ruins gate),
## its own capsule never inside the world. It also records the overlap sampling of the M5 brief's three routes
## (Hollow -> Grove, Hollow -> Thornwick, Thornwick -> Kingsfall) at stages 3-6: the brief's strict
## count (the capsule lifted 0.05 m on the path itself) and the corridor count above.

const SAMPLE_M := 2.0
const NAV_RADIUS_M := 2.0
const SHIFT_SLACK_M := 1.0
const SHIFT_STEP_M := 0.5
## GiantPlayer's floor_max_angle: the capsule's rounded bottom rides over an edge up to
## radius * (1 - cos(46 degrees)) high.
const FLOOR_MAX_ANGLE_DEG := 46.0
const STAGES := [4, 5, 6]
const BEARINGS := 8
## The exits and the point a giant walks to for each (the Kings' Door's LevelExit stands behind the
## crown's altar: its approach is the marker in front of the altar).
const EXIT_APPROACH := {"valley.exit.kings_door": "valley.marker.kings_door",
	"valley.exit.citadel_stair": "valley.marker.citadel_hall"}

var level: LevelRoot


func before_each() -> void:
	await super()
	level = null


func after_each() -> void:
	if level != null and is_instance_valid(level):
		level.queue_free()
	level = null
	await super()


## The Valley in the state of a revisit: every road-blocking prop and the Citadel Gate opened.
func _revisit_valley() -> LevelRoot:
	var lv := ValleyProbe.instance(true)
	world.add_child(lv)
	assert_true(await ValleyProbe.wait_for_navigation(self, lv), "navigation ready")
	for id: String in ValleyProbe.LINK_PROPS + ["valley.ruins.citadel_gate"]:
		var bp := ValleyProbe.prop(lv, id) as BreakableProp
		assert_true(bp != null and bp.force_open("test"), "%s is out of the way" % id)
	await ValleyProbe.wait_for_map_update(self, lv)
	await step_ticks(2)
	return lv


## The stage's capsule standing at `at` (its top CLEARANCE_LIFT_M over its height, like the growth
## check), its bottom `lift` m above `at`, touches world, breakable or blocker geometry: the touched
## shape's name, or "".
static func _blocked(space: PhysicsDirectSpaceState3D, profile: Dictionary, at: Vector3,
		lift := PlayerGrowth.CLEARANCE_LIFT_M, skip_breakable := false) -> String:
	var cap := CapsuleShape3D.new()
	cap.radius = float(profile.capsule_radius_m)
	var top := maxf(float(profile.capsule_total_height_m), 2.0 * cap.radius) + PlayerGrowth.CLEARANCE_LIFT_M
	cap.height = maxf(top - lift, 2.0 * cap.radius)
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = cap
	q.collision_mask = HitQueryAdapter.LAYER_WORLD | HitQueryAdapter.LAYER_BREAKABLE | 32
	q.collide_with_areas = false
	q.transform = Transform3D(Basis(), at + Vector3.UP * (top - cap.height * 0.5))
	for h: Dictionary in space.intersect_shape(q, 8):
		var body := h.collider as CollisionObject3D
		if body == null:
			return "?"
		if skip_breakable and body is BreakableProp and _breaks(body as BreakableProp, profile):
			continue
		var owner_node := body.shape_owner_get_owner(body.shape_find_owner(int(h.shape)))
		return str(owner_node.name) if owner_node is Node else str(body.name)
	return ""


## True when a giant of the profile's stage breaks `bp` with a blow (melee, no weapon tag needed).
static func _breaks(bp: BreakableProp, profile: Dictionary) -> bool:
	var rec := bp.record
	if bp.destroyed:
		return true
	if bp.is_indestructible() or bool(rec.get("protected", false)):
		return false
	if not (rec.get("accepted_attack_categories", []) as Array).has("melee"):
		return false
	if not (rec.get("required_tags", []) as Array).is_empty():
		return false
	if int(profile.get("stage", 1)) < int(rec.get("min_growth_stage", 1)):
		return false
	var permission := str(rec.get("requires_permission", ""))
	return permission == "" or (profile.get("interaction_permissions", []) as Array).has(permission)


## The corridor test of a path sample: the capsule, its bottom lifted by what it rides over, fits at
## `at` or up to (radius - NAV_RADIUS_M) + SHIFT_SLACK_M across the path direction `dir`. "" or what
## it touches on the path itself.
static func _corridor(space: PhysicsDirectSpaceState3D, profile: Dictionary, at: Vector3, dir: Vector3) -> String:
	var lift := ride_height(profile)
	var hit := _blocked(space, profile, at, lift, true)
	if hit == "":
		return ""
	var side := Vector3(-dir.z, 0.0, dir.x).normalized()
	if side == Vector3.ZERO:
		return hit
	var reach := float(profile.capsule_radius_m) - NAV_RADIUS_M + SHIFT_SLACK_M
	var d := SHIFT_STEP_M
	while d <= reach + 0.001:
		for sgn: float in [1.0, -1.0]:
			if _blocked(space, profile, at + side * (d * sgn), lift, true) == "":
				return ""
		d += SHIFT_STEP_M
	return hit


## The height of an edge the stage's capsule rides over (its contact normal within the floor angle).
static func ride_height(profile: Dictionary) -> float:
	return float(profile.capsule_radius_m) * (1.0 - cos(deg_to_rad(FLOOR_MAX_ANGLE_DEG)))


## The SAMPLE_M samples along the giant-layer path from `from` to `to` where the stage's capsule does
## not fit: {"overlaps" (the corridor test), "strict" (the brief's: lifted 0.05 m on the path itself),
## "samples", "length", "reaches", "first" (where the first corridor overlap is)}.
func _swept(lv: LevelRoot, profile: Dictionary, from: Vector3, to: Vector3) -> Dictionary:
	var space := lv.get_world_3d().direct_space_state
	var path := ValleyProbe.path(lv, from, to, ValleyProbe.GIANT)
	var out := {"overlaps": 0, "strict": 0, "samples": 0, "length": 0.0, "reaches": false, "first": ""}
	if path.size() < 2:
		return out
	out.reaches = ValleyProbe.flat(path[path.size() - 1], to) <= 2.5
	for i in path.size() - 1:
		var a := path[i]
		var b := path[i + 1]
		var seg := ValleyProbe.flat(a, b)
		if seg < 0.05:
			continue   # a repeated point: its next segment samples it, with a direction
		out.length = float(out.length) + seg
		var dir := Vector3(b.x - a.x, 0.0, b.z - a.z)
		var n := maxi(1, int(ceil(seg / SAMPLE_M)))
		for k in n:
			var at := a.lerp(b, float(k) / n)
			out.samples = int(out.samples) + 1
			if _blocked(space, profile, at) != "":
				out.strict = int(out.strict) + 1
			var hit := _corridor(space, profile, at, dir)
			if hit != "":
				out.overlaps = int(out.overlaps) + 1
				if str(out.first) == "":
					out.first = "%s at (%.0f, %.0f)" % [hit, at.x, at.z]
	return out


## The real giant at `stage` at the respawn transform `t`: the camera, turned to BEARINGS bearings,
## stays out of the world. Returns "" or where it clipped.
func _camera_clips(lv: LevelRoot, p: GiantPlayer, stage: int, t: Transform3D) -> String:
	p.set_profile(p.growth.profile_for_stage(stage))
	GameSession.place_player(p, Transform3D(t.basis, t.origin + Vector3.UP * 0.1))
	await step_ticks(3)
	var space := lv.get_world_3d().direct_space_state
	var q := PhysicsPointQueryParameters3D.new()
	q.collision_mask = HitQueryAdapter.OCCLUDER_MASK
	for i in BEARINGS:
		p.camera_rig.yaw = wrapf(t.basis.get_euler().y + TAU * float(i) / BEARINGS, -PI, PI)
		p.camera_rig.pitch = deg_to_rad(-18.0)
		await get_tree().process_frame
		await get_tree().process_frame
		q.position = p.camera_rig.camera.global_position
		if not space.intersect_point(q, 1).is_empty():
			return "bearing %d: inside the world at %s" % [i, q.position]
	return ""


func _checkpoint_transform(lv: LevelRoot, id: String) -> Transform3D:
	var n := lv.checkpoint(id)
	if n != null:
		return n.global_transform
	return lv.index().spawn_transform(id)


func _layout_limits() -> Dictionary:
	var out := {}
	var layout := ValleyProbe.layout()
	for list: String in ["shrines", "waystones"]:
		for e: Dictionary in layout.get(list, []):
			out[str(e.get("world_id", e.get("id", "")))] = int(e.get("max_stage", WorldIndex.ANY_STAGE))
	return out


func test_every_valley_checkpoint_carries_its_measured_stage_limit() -> void:
	level = await _revisit_valley()
	var lv := level
	var p := lv.get_node("Player") as GiantPlayer
	p.router.use_injection = true
	var space := lv.get_world_3d().direct_space_state
	var approaches := {}
	for exit_id: String in EXIT_APPROACH:
		var m := lv.marker(str(EXIT_APPROACH[exit_id]))
		assert_true(m != null, "%s has its approach marker" % exit_id)
		if m != null:
			approaches[exit_id] = m.global_position
	var limits := _layout_limits()
	var ids := lv.index().checkpoint_ids()
	assert_eq(ids.size(), 9, "the Valley's nine checkpoints (four shrines, five waystones)")
	var table := PackedStringArray()
	for id in ids:
		var t := _checkpoint_transform(lv, id)
		var best := 3
		var notes := PackedStringArray()
		for stage: int in STAGES:
			var prof: Dictionary = p.growth.profile_for_stage(stage)
			var why := _blocked(space, prof, t.origin)
			if why != "":
				notes.append("s%d capsule: %s" % [stage, why])
				break
			why = await _camera_clips(lv, p, stage, t)
			if why != "":
				notes.append("s%d camera: %s" % [stage, why])
				break
			var out_ok := false
			var tried := PackedStringArray()
			for exit_id: String in approaches:
				var r := _swept(lv, prof, t.origin, approaches[exit_id])
				if bool(r.reaches) and int(r.overlaps) == 0:
					out_ok = true
					break
				tried.append("%s: %d of %d (%s%s)" % [exit_id.get_slice(".", 2), int(r.overlaps), int(r.samples),
					r.first, "" if bool(r.reaches) else ", no path"])
			if not out_ok:
				notes.append("s%d way out: %s" % [stage, "; ".join(tried)])
				break
			best = stage
		table.append("%s %d %s" % [id, best, " | ".join(notes)])
		assert_eq(best, int(limits.get(id, -1)), "%s: the layout's max_stage is its measured limit %d (%s)" % [id,
			best, " | ".join(notes)])
		assert_eq(lv.index().max_stage_of(id), best, "%s: the index carries it" % id)
	for line in table:
		print("    revisit: " + line)
	assert_eq(int(limits.get("valley.cp.kings_door", 0)), 6, "the Kings' Door's waystone takes any giant up to stage 6")


func test_the_m5_routes_overlap_sampling_at_stages_3_to_6() -> void:
	level = await _revisit_valley()
	var lv := level
	var hollow := ValleyProbe.shrine(lv, "valley.shrine.hollow").growth_pad_position()
	var grove := ValleyProbe.shrine(lv, "valley.shrine.grove").growth_pad_position()
	var thornwick := ValleyProbe.shrine(lv, "valley.shrine.thornwick").growth_pad_position()
	var kingsfall := ValleyProbe.shrine(lv, "valley.shrine.kingsfall").growth_pad_position()
	var routes := [["Hollow -> Grove", hollow, grove], ["Hollow -> Thornwick", hollow, thornwick],
		["Thornwick -> Kingsfall", thornwick, kingsfall]]
	var p := lv.get_node("Player") as GiantPlayer
	for r: Array in routes:
		var cells := PackedStringArray()
		for stage in [3, 4, 5, 6]:
			var s := _swept(lv, p.growth.profile_for_stage(stage), r[1], r[2])
			assert_true(bool(s.reaches), "%s: a giant-layer path" % r[0])
			cells.append("stage %d strict %d / %d, corridor %d" % [stage, int(s.strict), int(s.samples), int(s.overlaps)])
			if stage == 3:
				assert_true(float(s.length) > 100.0, "%s: %.0f m" % [r[0], s.length])
		print("    revisit route %s: %s" % [r[0], ", ".join(cells)])


## The corridor probe against the real thing: a stage-6 giant (3.7 m capsule) walks the Hollow's exit
## to the forest road waystone and from the Grove through Thornwick's gate and lanes to the ruins gate
## waystone - where the strict sampling overlaps most - on the giant-layer path (waypoints within 1.2 m plus the 1.7 m it
## stands further from walls than the path's 2.0 m agent), its own capsule never inside the world.
func test_a_stage_6_giant_walks_the_valleys_narrowest_stretches() -> void:
	level = await _revisit_valley()
	var lv := level
	var p := lv.get_node("Player") as GiantPlayer
	p.router.use_injection = true
	var walker: GDScript = load("res://tests/slow/test_citadel_breach.gd")
	for leg: Array in [["valley.shrine.hollow", "valley.cp.forest_road"], ["valley.shrine.grove", "valley.cp.ruins_gate"]]:
		GameSession.place_player(p, _checkpoint_transform(lv, str(leg[0])))
		await TestWait.until(self, func() -> bool: return p.is_on_floor(), 60)
		await step_ticks(1)
		var grown: Dictionary = p.growth.debug_set_stage(6)
		assert_true(grown.ok or p.growth_stage == 6, "%s: a stage-6 giant (%s)" % [leg[0], grown.get("reason", "")])
		await step_ticks(2)
		var to := _checkpoint_transform(lv, str(leg[1])).origin
		var path := ValleyProbe.path(lv, p.global_position, to, ValleyProbe.GIANT)
		var prof: Dictionary = p.growth.profile_for_stage(6)
		var strict := _swept(lv, prof, p.global_position, to)
		var r: Dictionary = await walker.walk_sampled(self, p, path, 1.2 + float(prof.capsule_radius_m) - NAV_RADIUS_M)
		print("    revisit walk at stage 6: %s -> %s: %.0f m, %d of %d waypoints, %d clearance samples, %d overlaps (strict sampling %d of %d)" % [
			leg[0], leg[1], r.metres, r.reached, r.total, r.samples, r.overlaps, strict.strict, strict.samples])
		assert_eq(int(r.reached), int(r.total), "%s -> %s: walked at stage 6 (stuck at %s)" % [leg[0], leg[1], r.stuck_at])
		assert_eq(int(r.overlaps), 0, "%s -> %s: the capsule never inside the world (%s)" % [leg[0], leg[1], r.first])
		assert_true(int(strict.strict) > 0, "%s -> %s: a stretch the strict sampling flags (%d)" % [leg[0], leg[1], strict.strict])
