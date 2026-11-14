extends IntegrationSuite
## M8 gate (plan M6-M9 §3.20, §5.7 the crown's parley, §5.10 the encounters' budgets): Fort Aldmere's gate
## garrison on the real world (scenes/world/world.tscn, deterministic streaming), a stage-4 giant.
##   * F40: Aldmere at war with the giant, who carries Brannock's banner within 150 m of the gate and then
##     holds the herald's accepted parley instead: the garrison stands down - and so do its two wall
##     ballistae, whose crews are in the world (NEUTRAL while it does): no blow, bolt or arrow of the fort
##     touches the giant; when the stand-down ends the ballistae are Aldmere's again (at war: ENEMY).
##   * F41: Aldmere at peace, the giant comes up the road from the war camp: the camp's members cost no
##     budget while Aldmere is at peace, so the gate's four wall archers and its two ballista crews all
##     spawn and both ballistae are crewed.

const SCENE := "res://scenes/world/world.tscn"
const GARRISON := "encounter.aldmere_fort_gate"
const CAMP := "encounter.aldmere_war_camp"
const BALLISTAE := ["world.aldmere.fort_ballista_w", "world.aldmere.fort_ballista_e"]
const WALL := ["world.aldmere.wall_archer_1", "world.aldmere.wall_archer_2", "world.aldmere.wall_archer_3",
	"world.aldmere.wall_archer_4", "world.aldmere.wall_crew_1", "world.aldmere.wall_crew_2"]


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


func _world(xz: Vector2) -> WorldRoot:
	WanderDirector.test_active = true
	WanderDirector.view_probe = func(_p: Vector3) -> bool: return false
	var w := (load(SCENE) as PackedScene).instantiate() as WorldRoot
	world.add_child(w)
	w.streamer.deterministic = true
	w.player().router.use_injection = true
	w.player().set_profile(_profile(4))
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


func _engine(w: Node, id: String) -> SiegeEngine:
	for n in w.get_tree().get_nodes_in_group(SiegeEngine.GROUP):
		if n is SiegeEngine and (n as SiegeEngine).world_id == id:
			return n
	return null


func test_a_hostile_aldmere_holds_its_wall_ballistae_for_the_banner_and_the_parley() -> void:
	WorldState.set_flag("faction.aldmere.hostile", true)
	WorldState.add_item("item.brannock_banner", 1, "test")
	var w := await _world(Vector2(860.0, -60.0))
	var p := w.player()
	await step_ticks(60)
	await _move(w, Vector2(740.0, -60.0))   # 96 m from the gate, east of it
	await step_ticks(10 * 60)
	var d := w.director()
	assert_true(FactionState.is_hostile("aldmere"), "Aldmere is at war with the giant")
	assert_true(d.p29_standing_down(GARRISON), "the banner within 150 m: the gate garrison stands down")
	for id: String in WALL:
		assert_eq(d.member_status(id), EncounterDirector.SPAWNED, "%s is in the world" % id)
		var n := d.spawned(id)
		assert_eq(str(n.get("faction_standing")) if n != null else "", "stood_down", "%s stands down" % id)
	for id: String in BALLISTAE:
		var e := _engine(w, id)
		assert_true(e != null, "%s is in the world" % id)
		if e != null:
			assert_eq(e.entity.team, CombatEntity.Team.NEUTRAL, "%s stands down with its garrison" % id)
			assert_true(d.p29_engine_stood_down(id), "the director stood %s down" % id)
	var fort := {}
	for id: String in d.members_of(GARRISON):
		fort[id] = true
	for id: String in BALLISTAE:
		fort[id] = true
	var taken: Array = []
	var on_hit := func(_t: int, r: HitResult) -> void:
		if r.event != null and r.event.target_id == p.entity.entity_id and fort.has(r.event.attacker_id):
			taken.append([r.event.attacker_id, r.health_damage])
	Events.hit_resolved.connect(on_hit)
	await step_ticks(25 * 60)
	assert_eq(taken, [], "the banner held: no hit from the fort while its garrison stands aside")
	# The herald's accepted parley instead of the banner.
	WorldState.remove_item("item.brannock_banner", 1, "test")
	WorldState.set_flag("oath.crown.parley_accepted", true)
	await step_ticks(25 * 60)
	assert_true(d.p29_standing_down(GARRISON), "the accepted parley: it stands down still")
	assert_eq(taken, [], "the parley accepted: no hit from the fort")
	Events.hit_resolved.disconnect(on_hit)
	# The stand-down ends: the ballistae are Aldmere's again - at war.
	WorldState.set_flag("oath.crown.parley_accepted", false)
	await step_ticks(2 * 30 + 2)
	assert_false(d.p29_standing_down(GARRISON), "no token, no stand-down")
	for id: String in BALLISTAE:
		var e := _engine(w, id)
		if e != null:
			assert_eq(e.entity.team, CombatEntity.Team.ENEMY, "%s is Aldmere's again (at war)" % id)
	w.queue_free()
	await step_ticks(2)


func test_the_road_up_from_the_war_camp_finds_the_gate_garrison_whole() -> void:
	var w := await _world(Vector2(520.0, 100.0))
	await step_ticks(5 * 60)
	var d := w.director()
	assert_false(FactionState.is_hostile("aldmere"), "Aldmere at peace")
	assert_eq(d.encounter_state(CAMP), EncounterDirector.ACTIVE, "the war camp is up")
	for at: Vector2 in [Vector2(650.0, 80.0), Vector2(650.0, 0.0), Vector2(650.0, -40.0)]:
		await _move(w, at)
		await step_ticks(10 * 60)
	var rows: Array = []
	for id: String in WALL:
		rows.append("%s %s" % [id.trim_prefix("world.aldmere."), d.member_status(id)])
	print("    fort gate: up the road from the camp: %s; combatants %d/%d" % [rows, d.active_combatant_count(), d.max_active_enemies])
	assert_eq(d.encounter_state(CAMP), EncounterDirector.ACTIVE, "the camp is still up behind the giant")
	for id: String in WALL:
		assert_eq(d.member_status(id), EncounterDirector.SPAWNED, "%s spawned on the road approach" % id)
	for id: String in BALLISTAE:
		var e := _engine(w, id)
		assert_true(e != null and e.is_crewed(), "%s is crewed" % id)
	assert_true(d.active_combatant_count() <= d.max_active_enemies, "within the twelve")
	w.queue_free()
	await step_ticks(2)
