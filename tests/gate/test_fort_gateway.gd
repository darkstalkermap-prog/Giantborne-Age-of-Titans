extends IntegrationSuite
## M9 gate (FOLLOWUPS "From the M9 confirmation": Fort Aldmere's gate garrison stops a stage-4 or stage-5 giant in the
## gateway): on the real world (scenes/world/world.tscn, deterministic streaming) a giant of stages 4 to 6 walks its own
## titan path from the fort gate's waystone through the gate into the bailey with the gate garrison alive, its AI on:
##   * the breach: the gate broken by the giant (an offence: Aldmere at war, the garrison takes up arms and its pike
##     formation advances on the giant) - stages 4, 5 and 6 walk into the bailey, where the battle engages;
##   * the parley: the gate opened by the crown's peace (world.aldmere.fort_open; Aldmere at peace, the garrison holds its
##     post) - stages 4 and 6 walk on to the fort's forge, as a friend of the fort does.
## Every titan path into the bailey crosses the gate on its link from (650, -87) to (650, -105). Before the M9 gate the
## pikes' post stood on that line 5-9 m before it (pivot (650, -79.1)): every one of these walks stopped against the
## formation's front rank at z -69 to -75 and stood there for the rest of its time (the breach: the pikes advanced 6 m
## and braced; the parley: they held their post), as the M9 confirmation's crown runs did. The post is now in front of the
## west bastion, beside the road's approach (pivot (626, -75)).

const SCENE := "res://scenes/world/world.tscn"
const GATE := "world.aldmere.fort_gate"
const GARRISON := "encounter.aldmere_fort_gate"
## The fort gate's waystone (world.cp.fort_gate), where a giant who died in the battle wakes and walks in again.
const WAYSTONE := Vector2(650.0, -55.0)
const BAILEY := Vector3(650.0, 60.0, -130.0)
const FORGE := Vector3(604.0, 60.0, -220.0)
## Past the gate's link (its inner end at z -105): inside the bailey.
const INSIDE_Z := -110.0


func after_each() -> void:
	Quests.end_dialogue()
	for f in Formation.live():
		f.dissolve()
	FactionState.reset_for_tests()
	WanderDirector.reset_for_tests()
	await super()


static func _profile(stage: int) -> Dictionary:
	for rec: Dictionary in GameData.records_of_type("growth_profile"):
		if int(rec.get("stage", 0)) == stage:
			return rec
	return {}


static func _flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0.0, v.z)


func _world(xz: Vector2) -> WorldRoot:
	WanderDirector.test_active = true
	WanderDirector.view_probe = func(_p: Vector3) -> bool: return false
	var w := (load(SCENE) as PackedScene).instantiate() as WorldRoot
	world.add_child(w)
	w.streamer.deterministic = true
	w.player().router.use_injection = true
	await _move(w, xz)
	return w


## Puts the giant on the ground at `xz` once the ring around it is loaded.
func _move(w: WorldRoot, xz: Vector2) -> void:
	var p := w.player()
	var at := Vector3(xz.x, 300.0, xz.y)
	p.process_mode = Node.PROCESS_MODE_DISABLED
	p.global_position = at
	var guard := 0
	while not w.streamer.ring_ready(at) and guard < 800:
		w.streamer.load_ring_slice(at)
		await step_ticks(1)
		guard += 1
	var y := w.height_at(at)
	p.global_position = Vector3(xz.x, (y if not is_nan(y) else 80.0) + 0.3, xz.y)
	p.velocity = Vector3.ZERO
	p.process_mode = Node.PROCESS_MODE_INHERIT


## Strikes a prop as the giant until it is destroyed (at most 80 blows): an offence against its faction.
func _break(world_id: String, attacker: String) -> bool:
	for i in 80:
		if WorldState.is_destroyed(world_id):
			return true
		var e := Sim.get_entity(world_id)
		if e == null:
			return false
		var h := HitEvent.new()
		h.tick = Sim.tick
		h.instance_id = Sim.new_instance_id()
		h.attacker_id = attacker
		h.target_id = world_id
		h.power = 900.0
		h.attacker_stat = 40.0
		h.attacker_height_m = 20.0
		h.damage_split = {"physical": 1.0}
		h.poise_damage = 50.0
		h.tags = PackedStringArray(["Melee"])
		h.category = "melee"
		h.attacker_growth_stage = 5
		h.attacker_position = (e.actor as Node3D).global_position + Vector3(0, 0, 8) if e.actor != null else Vector3.ZERO
		Sim.queue_hit(h)
		await step_ticks(1)
	return WorldState.is_destroyed(world_id)


## The garrison's pike formation members (rank and file and banner) standing in the world, alive.
func _pikes_alive(w: WorldRoot) -> int:
	var d := w.director()
	var n := 0
	for id: String in d.members_of(GARRISON):
		if not (id.contains("gate_pike") or id.contains("gate_banner")):
			continue
		var e := Sim.get_entity(id)
		if d.member_status(id) == EncounterDirector.SPAWNED and e != null and e.is_alive():
			n += 1
	return n


## Walks the giant along its own titan path to `goal` for at most `seconds`, as a player follows the way in. Returns
## {"at": the last position, "pikes_at_gate": the garrison's pikes alive when the giant crossed the gate's line (z -95;
## -1 if it never did), "state_at_gate": their formation's state then}.
func _walk(w: WorldRoot, goal: Vector3, seconds: float) -> Dictionary:
	var p := w.player()
	var layers: int = p.growth.nav_query_mask()
	var path := NavQuery.path(w, p.global_position, goal, layers, NavQuery.PURPOSE_FAR)
	assert_true(path.size() >= 2, "a titan path from the waystone to %s" % [goal])
	var out := {"at": p.global_position, "pikes_at_gate": -1, "state_at_gate": ""}
	var idx := 1
	for t in int(seconds * 60.0):
		if _flat(goal - p.global_position).length() < 3.0:
			break
		while idx < path.size() and _flat(path[idx] - p.global_position).length() < 2.5:
			idx += 1
		var next := goal if idx >= path.size() else path[idx]
		p.camera_rig.yaw = TargetingRules.yaw_of(_flat(next - p.global_position))
		p.router.injected_move = Vector2(0, 1)
		var before_z := p.global_position.z
		await step_ticks(1)
		if before_z > -95.0 and p.global_position.z <= -95.0 and int(out.pikes_at_gate) < 0:
			out["pikes_at_gate"] = _pikes_alive(w)
			for f in Formation.live():
				if f.encounter_id == GARRISON:
					out["state_at_gate"] = f.state
	p.router.injected_move = Vector2.ZERO
	out["at"] = p.global_position
	return out


func test_a_giant_of_stages_4_to_6_walks_through_the_breached_gate_past_its_garrison() -> void:
	for stage: int in [4, 5, 6]:
		var w := await _world(WAYSTONE)
		var p := w.player()
		p.set_profile(_profile(stage))
		p.entity.apply_status("status.debug_invulnerable", NAN, -1.0, "test")
		await step_ticks(60)
		assert_eq(_pikes_alive(w), 11, "stage %d: the garrison's ten pikes and their banner stand before the gate" % stage)
		assert_true(await _break(GATE, p.entity.entity_id), "stage %d: the giant breaks the fort's gate" % stage)
		await step_ticks(60)
		assert_true(FactionState.is_hostile("aldmere"), "stage %d: the breach is an offence: Aldmere at war" % stage)
		var r := await _walk(w, BAILEY, 25.0)
		var at: Vector3 = r.at
		print("    fort gateway (breach, stage %d, radius %.1f m): the giant at (%.1f, %.1f); at the gate's line the pikes alive %d, their formation %s" % [
			stage, float(_profile(stage).get("capsule_radius_m", 0.0)), at.x, at.z, int(r.pikes_at_gate), r.state_at_gate])
		assert_true(at.z < INSIDE_Z, "stage %d: the giant walks into the bailey through the breached gate (at z %.1f)" % [stage, at.z])
		assert_eq(int(r.pikes_at_gate), 11, "stage %d: with the garrison's pike formation alive as it passed the gate" % stage)
		assert_true(str(r.state_at_gate) in ["formed", "advancing", "braced"], "stage %d: the formation still in its ranks (%s)" % [stage, r.state_at_gate])
		w.queue_free()
		await step_ticks(2)
		for f in Formation.live():
			f.dissolve()
		FactionState.reset_for_tests()
		WanderDirector.reset_for_tests()
		WorldState.clear()


func test_a_giant_of_stages_4_and_6_walks_through_the_opened_gate_to_the_forge() -> void:
	for stage: int in [4, 6]:
		WorldState.set_flag("oath.crown.outcome", "parley")
		WorldState.set_flag("world.aldmere.fort_open", true)
		var w := await _world(WAYSTONE)
		var p := w.player()
		p.set_profile(_profile(stage))
		p.entity.apply_status("status.debug_invulnerable", NAN, -1.0, "test")
		await step_ticks(120)
		assert_false(FactionState.is_hostile("aldmere"), "stage %d: the crown's peace: Aldmere is no foe" % stage)
		assert_eq(_pikes_alive(w), 11, "stage %d: the garrison's pikes stand at their post" % stage)
		var r := await _walk(w, FORGE, 35.0)
		var at: Vector3 = r.at
		print("    fort gateway (parley, stage %d): the giant at (%.1f, %.1f), %.1f m from the forge; at the gate's line the pikes alive %d" % [
			stage, at.x, at.z, _flat(FORGE - at).length(), int(r.pikes_at_gate)])
		assert_true(_flat(FORGE - at).length() < 6.0, "stage %d: the giant walks through the opened gate to the fort's forge (at %s)" % [stage, at])
		assert_eq(int(r.pikes_at_gate), 11, "stage %d: past the garrison at its post" % stage)
		w.queue_free()
		await step_ticks(2)
		for f in Formation.live():
			f.dissolve()
		FactionState.reset_for_tests()
		WanderDirector.reset_for_tests()
		WorldState.clear()
