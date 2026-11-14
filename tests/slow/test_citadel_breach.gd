extends IntegrationSuite
## From the Kings' Door to the Citadel at stage 4 (P26, plan M6-M9 §5.6; slow, runs with --slow): the
## Valley after the crown (slice.completed; the barricade, the practice gate and the deadfall broken),
## a stage-4 giant placed at the Kings' Door waystone walks the giant-layer path (layer 4, the
## Valley's player_nav_fallback) to the Citadel Gate, its capsule sampled every CLEARANCE_EVERY ticks
## and never inside the world; it breaches the gate (a stage-4 blow: test_valley_exits refuses a
## stage-3 one), walks on into the hall - whose area pays 150 XP once - and the stair's exit leads to
## the world's Broken Stair.

const CLEARANCE_EVERY := 10
const WAYPOINT_M := 1.5

var level: LevelRoot
var xp: Array[Array] = []
var travels: Array[Array] = []


func before_each() -> void:
	await super()
	level = null
	xp.clear()
	travels.clear()
	TestFixtures.record_override("weapon.club", {"fit_max_stage": 6})
	Events.xp_award_requested.connect(_on_xp)
	Events.travel_requested.connect(_on_travel)


func after_each() -> void:
	for pair: Array in [[Events.xp_award_requested, _on_xp], [Events.travel_requested, _on_travel]]:
		if (pair[0] as Signal).is_connected(pair[1]):
			(pair[0] as Signal).disconnect(pair[1])
	if level != null and is_instance_valid(level):
		level.queue_free()
	level = null
	await super()


func _on_xp(amount: int, source: String) -> void:
	xp.append([amount, source])


func _on_travel(level_id: String, checkpoint_id: String, reason: String) -> void:
	travels.append([level_id, checkpoint_id, reason])


## Walks `p` along the waypoints of `points` (a giant-layer path) with the stick, a waypoint reached
## within `waypoint_m`; every CLEARANCE_EVERY ticks its own capsule (a hair inside its surface) is
## tested against world, breakable and blocker geometry. {"reached", "total", "ticks", "metres",
## "samples", "overlaps", "first", "stuck_at"}. (test_valley_revisits walks a stage-6 giant with it.)
static func walk_sampled(suite: TestSuite, p: GiantPlayer, points: PackedVector3Array, waypoint_m := WAYPOINT_M) -> Dictionary:
	var out := {"reached": 0, "total": 0, "ticks": 0, "metres": 0.0, "samples": 0, "overlaps": 0, "first": "",
		"stuck_at": Vector3.INF}
	var space := p.get_world_3d().direct_space_state
	var cap := (p.body_shape.shape as CapsuleShape3D).duplicate() as CapsuleShape3D
	cap.radius -= 0.05
	cap.height -= 0.1
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = cap
	q.collision_mask = HitQueryAdapter.LAYER_WORLD | HitQueryAdapter.LAYER_BREAKABLE | 32
	q.exclude = [p.get_rid()]
	var waypoints: Array[Vector3] = []
	for v in points:
		if waypoints.is_empty() and ValleyProbe.flat(v, p.global_position) < waypoint_m:
			continue
		waypoints.append(v)
	out.total = waypoints.size()
	var prev := p.global_position
	var last := prev
	for wp in waypoints:
		var seg := wp - prev
		seg.y = 0.0
		prev = wp
		var ok := false
		for i in 300 + int(seg.length() * 30.0):
			var to := wp - p.global_position
			to.y = 0.0
			if to.length() < waypoint_m:
				ok = true
				break
			var yaw := TargetingRules.yaw_of(seg if seg.length() > 0.5 else to)
			p.camera_rig.yaw = yaw
			p.router.set_injected_move(ValleyProbe.stick_toward(to, yaw))
			await suite.step_ticks(1)
			out.ticks = int(out.ticks) + 1
			out.metres = float(out.metres) + ValleyProbe.flat(p.global_position, last)
			last = p.global_position
			if int(out.ticks) % CLEARANCE_EVERY == 0:
				out.samples = int(out.samples) + 1
				q.transform = Transform3D(Basis(), p.global_position + Vector3.UP * p.body_shape.position.y)
				var hits := space.intersect_shape(q, 1)
				if not hits.is_empty():
					out.overlaps = int(out.overlaps) + 1
					if str(out.first) == "":
						out.first = "%s at %s" % [(hits[0].collider as Node).name if hits[0].collider is Node else "?",
							p.global_position]
		if not ok:
			out.stuck_at = p.global_position
			break
		out.reached = int(out.reached) + 1
	p.router.set_injected_move(Vector2.ZERO)
	return out


func _exit(lv: LevelRoot, id: String) -> LevelExit:
	for n in get_tree().get_nodes_in_group(LevelExit.GROUP):
		if lv.is_ancestor_of(n) and (n as LevelExit).exit_id == id:
			return n as LevelExit
	return null


func test_a_stage_4_giant_walks_from_the_kings_door_into_the_citadel() -> void:
	var lv := ValleyProbe.instance(true)
	level = lv
	world.add_child(lv)
	assert_true(await ValleyProbe.wait_for_navigation(self, lv), "navigation ready")
	for id: String in ValleyProbe.LINK_PROPS:
		(ValleyProbe.prop(lv, id) as BreakableProp).force_open("test")
	WorldState.set_flag("slice.completed", true)
	await ValleyProbe.wait_for_map_update(self, lv)
	var p := lv.get_node("Player") as GiantPlayer
	p.router.use_injection = true
	var start := lv.index().spawn_transform("valley.cp.kings_door")
	GameSession.place_player(p, Transform3D(start.basis, start.origin + Vector3.UP * 0.1))
	await TestWait.until(self, func() -> bool: return p.is_on_floor(), 60)
	await step_ticks(1)
	var grown: Dictionary = p.growth.debug_set_stage(4)
	assert_true(grown.ok, "a stage-4 giant at the Kings' Door waystone (%s)" % grown.get("reason", ""))
	assert_eq(p.nav_layers, 4, "it paths on the Valley's giant layer (player_nav_fallback)")
	await step_ticks(5)
	var gate := ValleyProbe.prop(lv, "valley.ruins.citadel_gate") as BreakableProp
	var gate_at := lv.marker("valley.marker.citadel_gate").global_position
	var path := ValleyProbe.path(lv, p.global_position, gate_at, ValleyProbe.GIANT)
	assert_true(path.size() > 1 and ValleyProbe.flat(path[path.size() - 1], gate_at) < 2.5, "a giant-layer path to the Citadel Gate")
	var r := await walk_sampled(self, p, path)
	print("    citadel: Kings' Door -> the gate at stage 4: %.0f m in %.1f s, %d clearance samples, %d overlaps" % [
		r.metres, int(r.ticks) / 60.0, r.samples, r.overlaps])
	assert_eq(int(r.reached), int(r.total), "the stage-4 giant walks it (stuck at %s)" % r.stuck_at)
	assert_true(float(r.metres) > 250.0, "across the Valley (%.0f m)" % r.metres)
	assert_true(int(r.samples) > 100, "sampled along the way (%d)" % r.samples)
	assert_eq(int(r.overlaps), 0, "its capsule never inside the world (%s)" % r.first)
	assert_true(gate != null and not gate.destroyed, "the Citadel Gate stands")
	var e := HitEvent.new()
	e.tick = Sim.tick
	e.instance_id = Sim.new_instance_id()
	e.attacker_id = "player"
	e.target_id = gate.world_id
	e.action_id = "ability.heavy_1"
	e.power = 9999.0
	e.attacker_growth_stage = p.growth_stage
	e.attacker_height_m = float(p.profile.height_m)
	e.tags = PackedStringArray(["Melee", "Heavy"])
	e.attacker_position = p.global_position
	Sim.queue_hit(e)
	await step_ticks(2)
	assert_true(gate.destroyed, "a stage-4 blow breaches it")
	assert_eq(WorldState.get_flag("world.citadel.breached"), true, "world.citadel.breached")
	await ValleyProbe.wait_for_map_update(self, lv)
	var hall := lv.marker("valley.marker.citadel_hall").global_position
	var in_path := ValleyProbe.path(lv, p.global_position, hall, ValleyProbe.GIANT)
	assert_true(in_path.size() > 1 and ValleyProbe.flat(in_path[in_path.size() - 1], hall) < 2.5, "a path through the breach")
	var r2 := await walk_sampled(self, p, in_path)
	assert_eq(int(r2.reached), int(r2.total), "into the hall (stuck at %s)" % r2.stuck_at)
	assert_eq(int(r2.overlaps), 0, "its capsule never inside the world (%s)" % r2.first)
	await step_ticks(3)
	assert_eq(xp, [[150, "area:valley.area.citadel_hall"]], "the hall pays 150 XP once")
	var stair := _exit(lv, "valley.exit.citadel_stair")
	assert_true(stair != null and stair.can_interact(p), "the Citadel stair's exit")
	stair.interact(p)
	assert_eq(travels, [["level.world", "world.cp.broken_stair", "exit"]], "leads to the world's Broken Stair")
