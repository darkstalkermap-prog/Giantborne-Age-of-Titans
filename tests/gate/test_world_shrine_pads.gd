extends IntegrationSuite
## M8 gate (F4, F47): every world shrine's growth pad has room for the stage the shrine grows the
## giant to. On the real world (scenes/world/world.tscn, deterministic streaming), for each shrine of
## the layout tables: its ring loaded, the giant (at the stage below) set on the shrine's GrowthPad -
## where the bot grows and where a respawn there wakes - and PlayerGrowth.check_clearance asked for
## the shrine's max_stage. The Greywood shrine's pad stood 2.1 m from a pine of its clearing (a
## stage-5 capsule is 2.9 m across the radius: "Not enough room to grow here", blocker Batch4); its
## pad now faces the open side of the clearing. Also: the stage-5 capsule fits where each shrine's
## SpawnPoint puts a giant that respawns there.
## M8 gate fix-up 1 (F4 in the real game): growth is checked where the giant stands, and pines of the
## Greywood clearing (FOLLOWUPS: the builder's no-scenery grid) left 7 of 24 spots within the shrine's reach
## without room - the F47 run was refused twice there. A giant using a shrine whose spot has no room now grows
## on the shrine's pad (PlayerGrowth.shrine_clearance / pad_with_room): from every spot within reach of every
## world shrine the shrine's stage has room, and at the F47 run's spots the giant grows, on the pad.

const SCENE := "res://scenes/world/world.tscn"
const REGIONS := ["crownmarch", "greywood", "drowned_steps", "aldmere", "stonehold"]

var w: WorldRoot = null


func after_each() -> void:
	w = null
	await super()


## [{"id", "record", "pos": Vector2}] of every shrine in the layout tables.
static func world_shrines() -> Array:
	var out: Array = []
	for r: String in REGIONS:
		var d: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tools/data/world/%s.json" % r))
		for s: Dictionary in d.get("shrines", []):
			out.append({"id": str(s.id), "record": str(s.record), "pos": Vector2(float(s.pos[0]), float(s.pos[1]))})
	return out


static func _profile_of_stage(stage: int) -> Dictionary:
	for rec: Dictionary in GameData.records_of_type("growth_profile"):
		if int(rec.get("stage", 0)) == stage:
			return rec
	return {}


func _shrine_node(id: String) -> Shrine:
	for n in w.find_children("*", "Shrine", true, false):
		if (n as Shrine).world_id == id:
			return n
	return null


func test_every_world_shrine_pad_has_room_for_the_stage_it_grants() -> void:
	w = (load(SCENE) as PackedScene).instantiate() as WorldRoot
	world.add_child(w)
	w.streamer.deterministic = true
	var p := w.player()
	p.router.use_injection = true
	p.entity.apply_status("status.debug_invulnerable", NAN, -1.0, "test")
	var shrines := world_shrines()
	assert_eq(shrines.size(), 5, "the world's five shrines")
	var refused := PackedStringArray()
	for s: Dictionary in shrines:
		var stage := int(GameData.get_record(str(s.record)).get("max_stage", 0))
		var at := Vector3((s.pos as Vector2).x, 200.0, (s.pos as Vector2).y)
		p.process_mode = Node.PROCESS_MODE_DISABLED
		p.global_position = at
		var guard := 0
		while not w.streamer.ring_ready(at) and guard < 900:
			w.streamer.load_ring_slice(at)
			await step_ticks(1)
			guard += 1
		await step_ticks(20)
		var node := _shrine_node(str(s.id))
		assert_true(node != null, "%s is loaded" % s.id)
		if node == null:
			continue
		p.set_profile(_profile_of_stage(stage - 1))
		for spot: Array in [["pad", node.growth_pad_position()],
				["spawn point", (node.get_node("SpawnPoint") as Node3D).global_position]]:
			p.global_position = (spot[1] as Vector3) + Vector3.UP * 0.05
			p.velocity = Vector3.ZERO
			p.process_mode = Node.PROCESS_MODE_INHERIT
			await step_ticks(3)
			var r: Dictionary = p.growth.check_clearance(_profile_of_stage(stage))
			if not bool(r.ok):
				refused.append("%s's %s at %s: stage %d refused (%s, blocker %s)" % [s.id, spot[0], spot[1], stage,
					r.get("reason", ""), r.get("blocker", "")])
			p.process_mode = Node.PROCESS_MODE_DISABLED
	assert_eq(refused, PackedStringArray(), "every world shrine's pad has room for the stage it grants")


## The F47 reviewer's three spots at the Greywood shrine (grove2.log: refused at the first two - blockers
## Batch4 and Batch8 - grown at the third).
const F47_SPOTS := [Vector3(-542.4, 26.0, 104.6), Vector3(-534.2, 25.8, 108.7), Vector3(-535.4, 25.7, 113.4)]


func _ground_y(at: Vector3) -> float:
	var space := (w as Node3D).get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(Vector3(at.x, 400.0, at.z), Vector3(at.x, -100.0, at.z))
	q.collision_mask = 1
	var hit := space.intersect_ray(q)
	return float((hit.position as Vector3).y) if not hit.is_empty() else at.y


func _stand(p: GiantPlayer, spot: Vector3) -> void:
	p.global_position = Vector3(spot.x, _ground_y(spot) + 0.05, spot.z)
	p.velocity = Vector3.ZERO
	p.process_mode = Node.PROCESS_MODE_INHERIT
	await step_ticks(3)
	p.process_mode = Node.PROCESS_MODE_DISABLED


func test_a_giant_using_a_shrine_grows_from_anywhere_within_its_reach() -> void:
	w = (load(SCENE) as PackedScene).instantiate() as WorldRoot
	world.add_child(w)
	w.streamer.deterministic = true
	var p := w.player()
	p.router.use_injection = true
	p.entity.apply_status("status.debug_invulnerable", NAN, -1.0, "test")
	WorldState.set_flag("world.kingsgate.lit", true)
	for f: String in ["oath.march.done", "oath.crown.done"]:
		WorldState.set_flag(f, true)
	var no_room := PackedStringArray()
	var stepped := 0
	for s: Dictionary in world_shrines():
		var stage := int(GameData.get_record(str(s.record)).get("max_stage", 0))
		var at := Vector3((s.pos as Vector2).x, 200.0, (s.pos as Vector2).y)
		p.process_mode = Node.PROCESS_MODE_DISABLED
		p.global_position = at
		var guard := 0
		while not w.streamer.ring_ready(at) and guard < 900:
			w.streamer.load_ring_slice(at)
			await step_ticks(1)
			guard += 1
		await step_ticks(20)
		var node := _shrine_node(str(s.id))
		if node == null:
			no_room.append("%s not loaded" % s.id)
			continue
		var prof := _profile_of_stage(stage)
		p.set_profile(_profile_of_stage(stage - 1))
		var reach := node.radius_m + float(p.profile.get("capsule_radius_m", 1.0))
		for ring: float in [reach * 0.7, reach]:
			for k in 12:
				var a := TAU * k / 12.0
				await _stand(p, node.global_position + Vector3(cos(a), 0, sin(a)) * ring)
				var r: Dictionary = p.growth.shrine_clearance(prof, node)
				if not bool(r.ok):
					no_room.append("%s at %.1f m, %d deg: %s" % [s.id, ring, k * 30, r.get("blocker", r.get("reason", ""))])
				elif (r.get("step_to", Vector3.INF) as Vector3).is_finite():
					stepped += 1
		if str(s.id) == "world.shrine.greywood":
			for spot: Vector3 in F47_SPOTS:
				p.set_profile(_profile_of_stage(stage - 1))
				p.global_position = Vector3(spot.x, _ground_y(spot) + 0.05, spot.z)
				p.velocity = Vector3.ZERO
				p.process_mode = Node.PROCESS_MODE_INHERIT
				await step_ticks(10)
				var before: Dictionary = p.growth.check_clearance(prof)
				var g: Dictionary = node.grow(p, stage)
				await step_ticks(2)
				p.process_mode = Node.PROCESS_MODE_DISABLED
				assert_true(bool(g.ok), "at the F47 spot %s the giant grows to stage %d (%s)" % [spot, stage, g.get("message", "")])
				if not bool(before.ok):
					var pad := node.growth_pad_position()
					assert_true(Vector2(p.global_position.x - pad.x, p.global_position.z - pad.z).length() < 0.5,
						"its own spot had no room (%s): it grew on the shrine's pad" % before.get("blocker", ""))
	assert_eq(no_room, PackedStringArray(), "from every spot within a world shrine's reach the giant has room to grow")
	assert_true(stepped > 0, "some spots (the Greywood clearing's) grow on the pad (%d)" % stepped)

