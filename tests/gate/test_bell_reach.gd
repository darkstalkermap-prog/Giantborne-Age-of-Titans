extends IntegrationSuite
## M8 gate (F45): every bell of the Drowned Steps rings to a stage-4 giant's light swing from its own
## bed, on the real world (scenes/world/world.tscn, deterministic streaming: the terrain, the Mere's and
## the Wend's water, the shipped chunks). The fourth bell stands in the Wend's deep reach, 3 m deeper
## than the Mere's shallows; it hung so its lip cleared the water, its hurtbox 9.3 m over the riverbed,
## and a stage-4 giant wading there missed it with every light swing (heavy swings rang it). The bells
## now hang at most a shallows' height over their bed (half drowned in deep water), so the giant's
## light swing rings each of them as it rings the first. Each bell: the giant (stage 4, the world
## start's weapon) on the ground 6 m before it, facing it, swings the light attack through the input
## router (at most three swings).

const SCENE := "res://scenes/world/world.tscn"
const BELLS := ["world.drowned.bell_1", "world.drowned.bell_2", "world.drowned.bell_3", "world.drowned.bell_4",
	"world.drowned.bell_5"]
const STAND_M := 6.0

var w: WorldRoot = null


func after_each() -> void:
	w = null
	await super()


func _go(xz: Vector2, yaw: float) -> void:
	var p := w.player()
	var at := Vector3(xz.x, 200.0, xz.y)
	p.process_mode = Node.PROCESS_MODE_DISABLED
	p.global_position = at
	var guard := 0
	while not w.streamer.ring_ready(at) and guard < 900:
		w.streamer.load_ring_slice(at)
		await step_ticks(1)
		guard += 1
	var y := w.height_at(at)
	GameSession.place_player(p, Transform3D(Basis(Vector3.UP, yaw), Vector3(xz.x, (y if not is_nan(y) else 20.0) + 0.3, xz.y)))
	p.process_mode = Node.PROCESS_MODE_INHERIT
	await step_ticks(20)


func _bell(id: String) -> Node3D:
	for n in w.find_children("*", "", true, false):
		if "world_id" in n and str(n.get("world_id")) == id:
			return n as Node3D
	return null


## Light swings until the bell rings (at most `n`); how many it took (0 = it never rang).
func _light_swings(p: GiantPlayer, id: String, n: int) -> int:
	for i in n:
		p.router.inject_light_attack()
		await step_ticks(100)
		if WorldState.is_destroyed(id):
			return i + 1
	return 0


func test_a_stage_4_giant_rings_every_bell_with_a_light_swing_from_its_bed() -> void:
	w = (load(SCENE) as PackedScene).instantiate() as WorldRoot
	world.add_child(w)
	w.streamer.deterministic = true
	var p := w.player()
	p.router.use_injection = true
	p.entity.apply_status("status.debug_invulnerable", NAN, -1.0, "test")
	for rec: Dictionary in GameData.records_of_type("growth_profile"):
		if int(rec.get("stage", 0)) == 4:
			p.set_profile(rec)
	var missed := PackedStringArray()
	for id: String in BELLS:
		var at := WorldXp.position_of(id)
		await _go(Vector2(at.x, at.z + STAND_M), 0.0)   # loads the bell's ring
		var bell := _bell(id)
		assert_true(bell != null, "%s is loaded" % id)
		if bell == null:
			continue
		# 6 m before the bell along its own z (clear of its frame's posts), facing it.
		var dir := bell.global_transform.basis.z.normalized()
		var stand := bell.global_position + dir * STAND_M
		await _go(Vector2(stand.x, stand.z), atan2(dir.x, dir.z))
		var swings := await _light_swings(p, id, 3)
		var center := (bell.get_node("Anchors/Center") as Node3D).global_position
		print("    %s: feet y %.1f, the bell's centre %.1f m above them: %s" % [id, p.global_position.y,
			center.y - p.global_position.y, "rung by light swing %d" % swings if swings > 0 else "NOT rung by 3 light swings"])
		if swings == 0:
			missed.append("%s (feet y %.1f, centre %.1f m above them)" % [id, p.global_position.y, center.y - p.global_position.y])
	assert_eq(missed, PackedStringArray(), "a stage-4 giant's light swing from its bed rings every bell")
