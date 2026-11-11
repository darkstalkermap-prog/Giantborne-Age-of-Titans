extends IntegrationSuite
## M8 gate (F4, F47): every world shrine's growth pad has room for the stage the shrine grows the
## giant to. On the real world (scenes/world/world.tscn, deterministic streaming), for each shrine of
## the layout tables: its ring loaded, the giant (at the stage below) set on the shrine's GrowthPad -
## where the bot grows and where a respawn there wakes - and PlayerGrowth.check_clearance asked for
## the shrine's max_stage. The Greywood shrine's pad stood 2.1 m from a pine of its clearing (a
## stage-5 capsule is 2.9 m across the radius: "Not enough room to grow here", blocker Batch4); its
## pad now faces the open side of the clearing. Also: the stage-5 capsule fits where each shrine's
## SpawnPoint puts a giant that respawns there.

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
