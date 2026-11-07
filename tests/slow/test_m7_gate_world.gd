extends IntegrationSuite
## M7 gate review fixes on the real world (scenes/world/world.tscn, deterministic streaming; plan
## M6-M9 §0.2's M7 row: "two formation fights that threaten a stage-4 giant"):
##   * a defied toll fort brings its pikes down the road to a stage-4 giant standing 16 m before their
##     home rank (8 m before the rank once it has advanced) and damages it with the brace: no pike or
##     banner is leashed (the encounter's leash holds the formation's reach, and an intact formation's
##     members are left to their formation) and the advance ends inside the brace distance (it used to
##     stop half a metre outside it and stand "formed");
##   * the Raiders' Hollow's shield wall does the same to a stage-4 giant 16 m before its front rank.

const SCENE := "res://scenes/world/world.tscn"
const FORT := "encounter.crownmarch_toll_fort"
const RAIDERS := "encounter.crownmarch_raiders"
## How long a fight may take to draw blood (the pikes walk ~9 m at 1.4 m/s, then a 0.8 s windup).
const FIGHT_TICKS := 60 * 30

var _leashed: Array[String] = []


func before_each() -> void:
	await super()
	_leashed.clear()
	Events.encounter_leashed.connect(_on_leashed)


func after_each() -> void:
	if Events.encounter_leashed.is_connected(_on_leashed):
		Events.encounter_leashed.disconnect(_on_leashed)
	for f in Formation.live():
		f.dissolve()
	await super()


func _on_leashed(_t: int, _enc: String, id: String) -> void:
	_leashed.append(id)


## The real world with the giant held still above (x, z) until the ring around it has streamed in.
func _world(xz: Vector2) -> WorldRoot:
	var w := (load(SCENE) as PackedScene).instantiate() as WorldRoot
	world.add_child(w)
	w.streamer.deterministic = true
	w.player().router.use_injection = true
	await _go(w, xz)
	return w


## Puts the giant on the ground at (x, z) once the ring around it is ready.
func _go(w: WorldRoot, xz: Vector2) -> void:
	var p := w.player()
	var at := Vector3(xz.x, 200.0, xz.y)
	p.process_mode = Node.PROCESS_MODE_DISABLED
	p.global_position = at
	var guard := 0
	while not w.streamer.ring_ready(at) and guard < 600:
		w.streamer.load_ring_slice(at)
		await step_ticks(1)
		guard += 1
	var y := w.height_at(at)
	p.global_position = Vector3(xz.x, (y if not is_nan(y) else 20.0) + 0.3, xz.y)
	p.velocity = Vector3.ZERO
	p.process_mode = Node.PROCESS_MODE_INHERIT


## A stage-4 giant (its profile set directly: the growth path is P05's and P26's).
func _stage_4(p: GiantPlayer) -> void:
	for rec: Dictionary in GameData.records_of_type("growth_profile"):
		if int(rec.get("stage", 0)) == 4:
			p.set_profile(rec)
	assert_eq(int(p.current_growth_stage()), 4, "a stage-4 giant")


## Waits until `enc`'s formation `local` has drawn blood from the giant (or FIGHT_TICKS passed);
## returns [the formation, the damage its members dealt, their hits].
func _fight(w: WorldRoot, enc: String, local: String) -> Array:
	var d := w.director()
	var p := w.player()
	var fid := Formation.formation_id(enc, local)
	var damage := 0.0
	var landed := 0
	var f: Formation = null
	for i in FIGHT_TICKS / 30:
		await step_ticks(30)
		f = d.formation(fid)
		if f == null:
			continue
		var ids := {}
		for m in f.all_members():
			ids[m.entity_id] = true
		damage = 0.0
		landed = 0
		for r in hits_on(p.entity.entity_id):
			if ids.has(r.event.attacker_id) and r.health_damage > 0.0:
				damage += r.health_damage
				landed += 1
		if landed >= 2:
			break
	return [f, damage, landed]


func _members_leashed(f: Formation) -> Array:
	var out: Array = []
	for m in f.all_members():
		if m.leash_count > 0 or _leashed.has(m.entity_id):
			out.append(m.entity_id)
	return out


func test_a_defied_toll_fort_brings_its_pikes_to_a_stage_4_giant_on_the_road() -> void:
	var w: WorldRoot = await _world(Vector2(460.0, 560.0))
	var p := w.player()
	_stage_4(p)
	WorldState.set_flag("world.toll_fort.defied", true)   # "I pay no toll.": the stand-down ends
	var home_front := 366.1
	await _go(w, Vector2(460.0, home_front + 16.0))
	var hp0 := p.entity.combatant.pools.health
	var out: Array = await _fight(w, FORT, "pikes")
	var f: Formation = out[0]
	assert_true(f != null, "the pikes formed for the stage-4 giant")
	if f == null:
		return
	print("    toll fort: %d brace(s), %d hit(s) for %.0f damage; the giant %.0f -> %.0f; the rank %.1f m from it" % [
		f.brace_count, out[2], out[1], hp0, p.entity.combatant.pools.health, f.front_gap(p.global_position)])
	assert_eq(_members_leashed(f), [], "no pike or banner was leashed")
	assert_true(f.brace_count >= 1, "the pikes braced (%d)" % f.brace_count)
	assert_true(int(out[2]) >= 1 and float(out[1]) > 0.0, "their brace damaged the giant (%d hits, %.0f)" % [out[2], out[1]])
	assert_true(p.entity.combatant.pools.health < hp0, "the giant lost health")
	assert_true(f.front_gap(p.global_position) <= f.brace_m + 0.05, "the rank advanced inside its brace distance")
	var enc := GameData.get_record(FORT)
	for rec: Dictionary in enc.formations:
		assert_true(FormationRules.reach_m(enc, rec) <= float(enc.leash_radius_m), "the leash holds the pikes' reach")


func test_the_raiders_shield_wall_closes_on_a_stage_4_giant_and_braces() -> void:
	var w: WorldRoot = await _world(Vector2(60.0, 640.0))
	var p := w.player()
	_stage_4(p)
	await _go(w, Vector2(-84.9 + 16.0, 568.0))   # 16 m before the wall's front rank, facing east
	var hp0 := p.entity.combatant.pools.health
	var out: Array = await _fight(w, RAIDERS, "shields")
	var f: Formation = out[0]
	assert_true(f != null, "the shield wall formed for the stage-4 giant")
	if f == null:
		return
	print("    raiders: %d brace(s), %d hit(s) for %.0f damage; the giant %.0f -> %.0f" % [
		f.brace_count, out[2], out[1], hp0, p.entity.combatant.pools.health])
	assert_eq(_members_leashed(f), [], "no shieldman or banner was leashed")
	assert_true(f.brace_count >= 1, "the wall braced (%d)" % f.brace_count)
	assert_true(int(out[2]) >= 1 and float(out[1]) > 0.0, "its brace damaged the giant (%d hits, %.0f)" % [out[2], out[1]])
