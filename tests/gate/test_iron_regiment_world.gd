extends IntegrationSuite
## M8 gate (plan M6-M9 §2.10, §5.13 boss 1, §3.20 "every battle fits the caps on both platforms"): the
## Iron Regiment's battle on the real world (scenes/world/world.tscn, deterministic streaming), a stage-5
## giant that takes no damage, Fort Aldmere's real gate broken and the bailey entered through its engage
## trigger as a player would.
##   * F8: the battle's arena is the bailey inside the curtain wall (its floor rectangle), not a circle
##     whose disengage line cut through the bailey's corners: the giant stands 6 s in each corner of the
##     closed bailey and the battle goes on; a giant that really leaves (beyond the floor + 20 m for 5 s)
##     still resets it.
##   * F9 (F24): on the web, the gate broken with its garrison alive, the battle stands the garrison's
##     pikes, banner and archers out when it engages (the crews of its own ballistae stay) and keeps its
##     units' room: the Wall musters whole (banners first) within the web's 20 formation members, the bar
##     counts what spawned, and the Charge's six riders spawn whole within the twelve combatants.
##   * F9, Ballista Ridge: a giant who comes from the ridge over the King's Road finds its shield wall and
##     crews still in the world when it engages (the ridge stays active out to 210 m): as many of them as
##     the caps need leave too (EncounterDirector.p34_make_room), the Wall musters whole and the Charge's
##     riders spawn whole.
##   * M9 gate (lane aldmere; plan §5.13: two ballistae in the Wall, all four from the Charge): in the Wall
##     only the two inner ballistae (the Wall's own crews) shoot - the gate bastions' pair, its garrison
##     crews at their places, holds its fire - and from the Charge into the Last Stand all four shoot
##     (test_the_phases_follow_the_wall_and_the_charge_with_the_ballistae_standing); the HUD tells the
##     giant so as the battle engages and again as the Charge frees the pair (ENGINES_LINE, CHARGE_LINE).

const SCENE := "res://scenes/world/world.tscn"
const GATE := "world.aldmere.fort_gate"
const WALL := "encounter.aldmere_iron_regiment_wall"
const CHARGE := "encounter.aldmere_iron_regiment_charge"
const GARRISON := "encounter.aldmere_fort_gate"
const RIDGE := "encounter.aldmere_ballista_ridge"
## The bailey's two inner ballistae (the Wall's crews), sorted: the only ones that shoot in the Wall (M9 gate).
const INNER_BALLISTAE := ["world.aldmere.fort_ballista_ne", "world.aldmere.fort_ballista_nw"]
## The gate bastions' two ballistae (the gate garrison's crews), sorted: they join at the Charge (M9 gate).
const BASTION_BALLISTAE := ["world.aldmere.fort_ballista_e", "world.aldmere.fort_ballista_w"]
## Spots inside the curtain wall (560..740 x -245..-95), near each corner (99-107 m from the arena's
## centre at (650, -165): beyond the old circle's 72 + 20 m).
const CORNERS := [Vector2(730, -236), Vector2(570, -236), Vector2(730, -104), Vector2(570, -104)]
## The HUD's lines about the ballistae as the battle engages and as the Charge begins (M9 gate).
const ENGINES_LINE := "Smash the ballistae: two shoot now, two more join when the Charge begins."
const CHARGE_LINE := "Two more ballistae open fire."

var disengaged: Array = []
## The HUD's messages since the test began (text only).
var hud_lines: Array = []


func before_each() -> void:
	await super()
	disengaged.clear()
	hud_lines.clear()
	Events.boss_disengaged.connect(_on_disengaged)
	Events.hud_message.connect(_on_hud_message)


func after_each() -> void:
	if Events.boss_disengaged.is_connected(_on_disengaged):
		Events.boss_disengaged.disconnect(_on_disengaged)
	if Events.hud_message.is_connected(_on_hud_message):
		Events.hud_message.disconnect(_on_hud_message)
	Quests.end_dialogue()
	for f in Formation.live():
		f.dissolve()
	FactionState.reset_for_tests()
	WanderDirector.reset_for_tests()
	LevelRoot.force_web_for_tests = false
	await super()


func _on_disengaged(t: int, id: String, reason: String) -> void:
	disengaged.append([t, id, reason])


func _on_hud_message(text: String, _kind: String) -> void:
	hud_lines.append(text)


static func _profile(stage: int) -> Dictionary:
	for rec: Dictionary in GameData.records_of_type("growth_profile"):
		if int(rec.get("stage", 0)) == stage:
			return rec
	return {}


func _world(xz: Vector2) -> WorldRoot:
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


## Strikes a prop as a stage-5 giant until it is destroyed (at most 80 blows).
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


func _battle(w: Node) -> FortBattle:
	for n in w.get_tree().get_nodes_in_group(BattleBoss.BATTLE_GROUP):
		if n is FortBattle:
			return n
	return null


## The real world before Fort Aldmere's gate, a stage-5 giant that takes no damage, the gate broken. With
## `via_ridge` the giant first stands 5 s on the King's Road below Ballista Ridge (the ridge wakes).
func _fort(web: bool, via_ridge := false) -> WorldRoot:
	LevelRoot.force_web_for_tests = web
	WanderDirector.test_active = true
	WanderDirector.view_probe = func(_p: Vector3) -> bool: return false
	var w: WorldRoot = await _world(Vector2(760.0, -30.0) if via_ridge else Vector2(650.0, -75.0))
	var p := w.player()
	p.set_profile(_profile(5))
	p.entity.apply_status("status.debug_invulnerable", NAN, -1.0, "test")
	if via_ridge:
		await step_ticks(5 * 60)
		await _move(w, Vector2(650.0, -75.0))
	await step_ticks(10)
	assert_true(await _break(GATE, p.entity.entity_id), "the fort's gate breaks")
	await step_ticks(30)
	return w


## Into the engage trigger and past the portcullis, as a player walks in.
func _enter_bailey(w: WorldRoot, b: BattleBoss) -> void:
	await _move(w, Vector2(650.0, -112.0))
	await step_ticks(6)
	await _move(w, Vector2(650.0, -128.0))
	await step_ticks(6)
	assert_eq(b.state_name(), "engaged", "walking in engages the battle")
	assert_true(b.is_gate_closed(), "the portcullis closes behind the giant")


func test_the_bailey_corners_never_disengage_the_battle() -> void:
	var w := await _fort(false)
	var b := _battle(w)
	assert_true(b != null, "the battle is loaded")
	if b == null:
		return
	await _enter_bailey(w, b)
	await step_ticks(60)
	for c: Vector2 in CORNERS:
		await _move(w, c)
		var p := w.player()
		var local := b.to_local(p.global_position)
		var r := Vector2(local.x, local.z).length()
		assert_true(p.global_position.x > 561.5 and p.global_position.x < 738.5 and p.global_position.z > -243.5
			and p.global_position.z < -96.5, "the giant stands inside the curtain wall at %s" % [p.global_position])
		await step_ticks(6 * 60)
		print("    iron regiment: %s, %.1f m from the arena's centre: %s, disengaged %s" % [c, r, b.state_name(), disengaged])
		assert_eq(disengaged, [], "6 s in the bailey's corner at %s (%.0f m from the centre) keeps the battle" % [c, r])
		assert_eq(b.state_name(), "engaged", "still engaged")
		assert_true(b.is_gate_closed(), "the portcullis stays down")
	# A giant that really leaves: out past the gate, beyond the bailey + 20 m, for 5 s.
	await _move(w, Vector2(650.0, -40.0))
	await step_ticks(int(5.5 * 60))
	assert_eq(disengaged.size(), 1, "leaving the bailey for good still resets the battle")
	if not disengaged.is_empty():
		assert_eq([disengaged[0][1], disengaged[0][2]], ["battle.iron_regiment", "left"], "boss_disengaged(battle.iron_regiment, left)")
	assert_eq(b.state_name(), "waiting", "the battle waits for a new attempt")
	w.queue_free()
	await step_ticks(2)


func _kill(id: String) -> void:
	var e := Sim.get_entity(id)
	if e == null or e.actor == null or not e.is_alive():
		return
	var h := HitEvent.new()
	h.tick = Sim.tick
	h.instance_id = Sim.new_instance_id()
	h.attacker_id = "test.nobody"
	h.target_id = id
	h.power = 1.0e6
	h.size_policy = "none"
	h.damage_split = {"physical": 1.0}
	h.tags = PackedStringArray(["Melee", "Unblockable", "Unparryable"])
	h.attacker_position = (e.actor as Node3D).global_position + Vector3(0, 0, 6)
	Sim.queue_hit(h)


func test_the_web_battle_fits_the_cap_with_the_gate_garrison_alive() -> void:
	var w := await _fort(true)
	var b := _battle(w)
	assert_true(b != null, "the battle is loaded")
	if b == null:
		return
	var d := w.director()
	var garrison := Array(d.members_of(GARRISON)).filter(func(id: String) -> bool:
		return d.member_status(id) == EncounterDirector.SPAWNED)
	var pikes := garrison.filter(func(id: String) -> bool: return id.contains("gate_pike") or id.contains("gate_banner"))
	print("    iron regiment (web): before the battle, the gate garrison %d up (%d of its formation), formation members %d/%d" % [
		garrison.size(), pikes.size(), d.formation_member_count(), d.max_formation_members])
	assert_eq(d.max_formation_members, 20, "the web's formation cap")
	assert_true(pikes.size() >= 7, "the garrison's pikes and banner stand at the broken gate (%d)" % pikes.size())
	await _enter_bailey(w, b)
	await step_ticks(120)
	for id: String in pikes:
		assert_true(d.member_status(id) != EncounterDirector.SPAWNED, "%s stood out (%s)" % [id, d.member_status(id)])
	for crew: String in ["world.aldmere.wall_crew_1", "world.aldmere.wall_crew_2"]:
		if garrison.has(crew):
			assert_eq(d.member_status(crew), EncounterDirector.SPAWNED, "%s stays at its ballista (the battle's)" % crew)
	var planned := b.planned()
	var waiting: Array = []
	for id: String in d.members_of(WALL):
		if planned.has(id) and d.member_status(id) != EncounterDirector.SPAWNED:
			waiting.append(id)
	print("    iron regiment (web): 2 s after engaging, the Wall waiting %s; formation members %d/%d; stood out %d" % [
		waiting, d.formation_member_count(), d.max_formation_members, b.stood_out.size()])
	assert_eq(waiting, [], "every unit of the Wall the bar counts has spawned")
	assert_eq(d.member_status("world.aldmere.regiment_shield_banner"), EncounterDirector.SPAWNED, "the shield wall's banner with it")
	assert_true(d.formation_member_count() <= d.max_formation_members, "within the web's cap")
	var counted := 0.0
	for id: String in planned:
		var e := Sim.get_entity(id)
		counted += e.combatant.pools.health if e != null and e.combatant != null else float(planned[id])
	for eid in b.engines:
		var e := Sim.get_entity(eid)
		counted += e.combatant.pools.health if e != null and e.combatant != null and e.is_alive() else 0.0
	assert_near(float(b.aggregate().current), counted, 0.5, "the bar counts what spawned")
	# The Wall falls: the Charge's six riders spawn whole within the budget.
	for id: String in d.members_of(WALL):
		_kill(id)
	await step_ticks(30)
	assert_true(b.phase_log.has(2), "The Charge (%s)" % [b.phase_log])
	var riders := Array(d.members_of(CHARGE)).filter(func(id: String) -> bool: return d.member_status(id) == EncounterDirector.SPAWNED)
	print("    iron regiment (web): the Charge %d riders up, combatants %d/%d" % [riders.size(), d.active_combatant_count(), d.max_active_enemies])
	assert_eq(riders.size(), 6, "six riders, whole")
	assert_true(d.active_combatant_count() <= d.max_active_enemies, "within the twelve")
	w.queue_free()
	await step_ticks(2)


## M9 confirmation (W23, the layout defect of the Charge's and the Last Stand's thresholds): on both compositions the
## Charge begins once the Wall's fighting units fall and the Last Stand once the riders fall, while the battle's four
## ballistae and the two crews of the inner pair still stand - a giant who cannot break the fort's ballistae (the
## bastion pair stands 16 m up) sees every phase. With 0.6 and 0.25 the bar stayed at 0.622 / 0.670 after the Wall and
## at 0.452 / 0.465 after the riders, and neither phase began (the phase-spent rule waits on the crews). M9 gate
## (lane aldmere; plan §5.13): which ballistae shoot in each phase - in the Wall the two inner ones (the Wall's
## crews) while the gate bastions' pair holds its fire with its garrison crews at their places, from the Charge
## on all four. Before, all four shot from the Wall's first blow.
func test_the_phases_follow_the_wall_and_the_charge_with_the_ballistae_standing() -> void:
	for web: bool in [false, true]:
		var w := await _fort(web)
		var b := _battle(w)
		assert_true(b != null, "the battle is loaded")
		if b == null:
			return
		var d := w.director()
		hud_lines.clear()
		await _enter_bailey(w, b)
		await step_ticks(120)
		assert_true(hud_lines.has(ENGINES_LINE), "%s: the HUD tells the giant which ballistae shoot as the battle engages (%s)" % [
			"web" if web else "desktop", hud_lines])
		assert_false(hud_lines.has(CHARGE_LINE), "the Charge's line waits for the Charge")
		var crews := {}
		for entry: Variant in GameData.get_record(WALL).get("engines", []):
			for c: Variant in (entry as Dictionary).get("crew", []):
				crews[str(c)] = true
		assert_eq(crews.size(), 2, "the Wall's encounter crews the two inner ballistae")
		var name := "web" if web else "desktop"
		var shooting := _shooting_engines(w, b)
		print("    iron regiment (%s): in the Wall the ballistae that shoot %s, the bastions' crewed %s" % [name, shooting,
			_crewed_engines(w, BASTION_BALLISTAE)])
		assert_eq(shooting, INNER_BALLISTAE, "%s: in the Wall the two inner ballistae shoot, the bastions' pair holds its fire" % name)
		assert_eq(_crewed_engines(w, BASTION_BALLISTAE), BASTION_BALLISTAE, "%s: the gate garrison's crews stand at the bastions' pair" % name)
		var planned := b.planned()
		for id: String in d.members_of(WALL):
			if planned.has(id) and not crews.has(id):
				_kill(id)
		await step_ticks(30)
		print("    iron regiment (%s): the Wall's fighting units fallen, the bar at %.3f, phases %s" % [
			name, b.aggregate_fraction(), b.phase_log])
		assert_true(b.phase_log.has(2), "%s: the Charge begins once the Wall falls (%s, bar %.3f)" % [name, b.phase_log, b.aggregate_fraction()])
		for id: String in crews:
			var e := Sim.get_entity(id)
			assert_true(e != null and e.is_alive(), "%s: %s still serves its ballista" % [name, id])
		for eid in b.engines:
			var e := Sim.get_entity(eid)
			assert_true(e != null and e.is_alive(), "%s: %s still stands" % [name, eid])
		shooting = _shooting_engines(w, b)
		print("    iron regiment (%s): in the Charge the ballistae that shoot %s" % [name, shooting])
		assert_eq(shooting.size(), 4, "%s: from the Charge all four ballistae shoot (%s)" % [name, shooting])
		assert_eq(hud_lines.count(CHARGE_LINE), 1, "%s: the HUD says so as the Charge begins (%s)" % [name, hud_lines])
		var guard := 0
		while _up(d, CHARGE).size() < 6 and guard < 300:
			await step_ticks(1)
			guard += 1
		for id: String in d.members_of(CHARGE):
			_kill(id)
		await step_ticks(30)
		print("    iron regiment (%s): the riders fallen, the bar at %.3f, phases %s" % [name, b.aggregate_fraction(), b.phase_log])
		assert_true(b.phase_log.has(3), "%s: the Last Stand begins once the riders fall (%s, bar %.3f)" % [name, b.phase_log, b.aggregate_fraction()])
		for id: String in crews:
			var e := Sim.get_entity(id)
			assert_true(e != null and e.is_alive(), "%s: %s still serves its ballista in the Last Stand" % [name, id])
		shooting = _shooting_engines(w, b)
		assert_eq(shooting.size(), 4, "%s: in the Last Stand all four ballistae shoot (%s)" % [name, shooting])
		w.queue_free()
		await step_ticks(2)
		FactionState.reset_for_tests()
		WanderDirector.reset_for_tests()
		LevelRoot.force_web_for_tests = false


func _up(d: EncounterDirector, enc: String) -> Array:
	return Array(d.members_of(enc)).filter(func(id: String) -> bool: return d.member_status(id) == EncounterDirector.SPAWNED)


## The battle's engines in the fight now - crewed, free to shoot, their fire not held (world ids, sorted; M9
## gate). On the old code an engine had no hold: crewed and free to shoot was in the fight.
func _shooting_engines(w: Node, b: BattleBoss) -> Array:
	var out: Array = []
	for n in w.get_tree().get_nodes_in_group(SiegeEngine.GROUP):
		var e := n as SiegeEngine
		if e != null and b.engines.has(e.world_id) and e.is_crewed() and e.can_shoot() and not e.get("fire_held") == true:
			out.append(e.world_id)
	out.sort()
	return out


## Of the engines `ids`, those a crew serves now (world ids, sorted; M9 gate).
func _crewed_engines(w: Node, ids: Array) -> Array:
	var out: Array = []
	for n in w.get_tree().get_nodes_in_group(SiegeEngine.GROUP):
		var e := n as SiegeEngine
		if e != null and ids.has(e.world_id) and e.is_crewed():
			out.append(e.world_id)
	out.sort()
	return out


func test_the_web_battle_makes_room_from_ballista_ridge() -> void:
	var w := await _fort(true, true)
	var b := _battle(w)
	assert_true(b != null, "the battle is loaded")
	if b == null:
		return
	var d := w.director()
	var spawned := func(id: String) -> bool: return d.member_status(id) == EncounterDirector.SPAWNED
	var ridge_wall := Array(d.members_of(RIDGE)).filter(func(id: String) -> bool:
		return not id.contains("ridge_crew") and spawned.call(id))
	var ridge_crews := Array(d.members_of(RIDGE)).filter(func(id: String) -> bool:
		return id.contains("ridge_crew") and spawned.call(id))
	print("    iron regiment (web, via the ridge): before the battle, the ridge %s with %d of its wall and %d crews up; formation members %d/%d, combatants %d/%d" % [
		d.encounter_state(RIDGE), ridge_wall.size(), ridge_crews.size(), d.formation_member_count(), d.max_formation_members,
		d.active_combatant_count(), d.max_active_enemies])
	assert_eq(d.encounter_state(RIDGE), EncounterDirector.ACTIVE, "the ridge is still awake at the gate")
	assert_true(ridge_wall.size() >= 7, "its shield wall stands (%d)" % ridge_wall.size())
	await _enter_bailey(w, b)
	await step_ticks(120)
	for id: String in ridge_wall:
		assert_eq(d.member_status(id), EncounterDirector.DESPAWNED, "%s made room (%s)" % [id, d.member_status(id)])
	var planned := b.planned()
	var waiting: Array = []
	for id: String in d.members_of(WALL):
		if planned.has(id) and d.member_status(id) != EncounterDirector.SPAWNED:
			waiting.append(id)
	var crews_left := ridge_crews.filter(func(id: String) -> bool: return d.member_status(id) == EncounterDirector.DESPAWNED)
	print("    iron regiment (web, via the ridge): 2 s after engaging, the Wall waiting %s; formation members %d/%d; combatants %d/%d; stood out %d (%d of the ridge's crews)" % [
		waiting, d.formation_member_count(), d.max_formation_members, d.active_combatant_count(), d.max_active_enemies,
		b.stood_out.size(), crews_left.size()])
	assert_eq(waiting, [], "every unit of the Wall the bar counts has spawned")
	assert_true(d.formation_member_count() <= d.max_formation_members, "within the web's cap")
	for id: String in d.members_of(WALL):
		_kill(id)
	await step_ticks(30)
	assert_true(b.phase_log.has(2), "The Charge (%s)" % [b.phase_log])
	var riders := Array(d.members_of(CHARGE)).filter(func(id: String) -> bool: return spawned.call(id))
	print("    iron regiment (web, via the ridge): the Charge %d riders up, combatants %d/%d" % [riders.size(), d.active_combatant_count(), d.max_active_enemies])
	assert_eq(riders.size(), 6, "six riders, whole")
	assert_true(d.active_combatant_count() <= d.max_active_enemies, "within the twelve")
	w.queue_free()
	await step_ticks(2)
