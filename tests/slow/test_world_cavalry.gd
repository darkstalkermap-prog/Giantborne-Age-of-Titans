extends IntegrationSuite
## M8 screenshot pass (V3): the world's riders charge where a player meets them. The screenshot pass saw
## no rider start a charge in Fort Aldmere's bailey (the Iron Regiment's Charge, about 20 s) or at the war
## camp with Aldmere at war (about 60 s). On the real world (scenes/world/world.tscn, deterministic
## streaming), a giant that takes no damage, staged as the capture staged it:
##   * The Charge: the fort's gate broken (Aldmere at war), the bailey entered through its engage trigger,
##     the giant at the gate end where the Wall musters and the Wall struck down by his blows. Its six riders spawned at the
##     stables, 89-114 m from him - beyond their 70 m sight and 30 m hearing - and stood there unaware for
##     the rest of the battle (0 charges in 40 s); now the battle tells its units where the giant is
##     (BattleBoss._alert_units) and they ride out and charge.
##   * The war camp: Aldmere at war, the giant 40 m east of the camp's pickets - outside the camp's 70 m
##     leash, its riders posted 60-68 m from its centre. They rode for a start point beyond the leash, were
##     sent home, saw him again and rode out again (60 leashes in 60 s, no charge); now a rider rides for
##     its start point only as far as its leash allows (CavalryBrain.leash_clamp) and holds there facing
##     him, and charges once he comes within its start window.

const SCENE := "res://scenes/world/world.tscn"
const GATE := "world.aldmere.fort_gate"
const WALL := "encounter.aldmere_iron_regiment_wall"
const CHARGE := "encounter.aldmere_iron_regiment_charge"
const CAMP := "encounter.aldmere_war_camp"
const CAMP_CENTRE := Vector2(520, 120)
const CAMP_LEASH_M := 70.0
## Where the capture stood the giant, 40 m east of the pickets, facing the camp.
const CAMP_WATCH := Vector2(625, 118)
const CAMP_FACING := Vector3(583, 0, 124)
## Where he walks to next: the pickets' riders' start window.
const CAMP_CLOSE := Vector2(604, 119)

var leashed: Array = []


func before_each() -> void:
	await super()
	leashed.clear()
	Events.encounter_leashed.connect(_on_leashed)


func after_each() -> void:
	if Events.encounter_leashed.is_connected(_on_leashed):
		Events.encounter_leashed.disconnect(_on_leashed)
	Quests.end_dialogue()
	for f in Formation.live():
		f.dissolve()
	FactionState.reset_for_tests()
	WanderDirector.reset_for_tests()
	await super()


func _on_leashed(tick: int, encounter_id: String, entity_id: String) -> void:
	leashed.append([tick, encounter_id, entity_id])


static func _profile(stage: int) -> Dictionary:
	for rec: Dictionary in GameData.records_of_type("growth_profile"):
		if int(rec.get("stage", 0)) == stage:
			return rec
	return {}


static func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


func _world(xz: Vector2, stage: int) -> WorldRoot:
	WanderDirector.test_active = true
	WanderDirector.view_probe = func(_p: Vector3) -> bool: return false
	var w := (load(SCENE) as PackedScene).instantiate() as WorldRoot
	world.add_child(w)
	w.streamer.deterministic = true
	var p := w.player()
	p.router.use_injection = true
	p.set_profile(_profile(stage))
	p.entity.apply_status("status.debug_invulnerable", NAN, -1.0, "test")
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


func _face(p: GiantPlayer, to: Vector3) -> void:
	var d := to - p.global_position
	p.rotation.y = atan2(-d.x, -d.z)
	p.facing_yaw = p.rotation.y
	p.camera_rig.yaw = p.facing_yaw


## A blow of the giant `p`'s: `power` on `id` (a prop, or a unit with `unit` true).
func _blow(p: GiantPlayer, id: String, power: float, unit: bool) -> void:
	var e := Sim.get_entity(id)
	if e == null or not e.is_alive():
		return
	var h := HitEvent.new()
	h.tick = Sim.tick
	h.instance_id = Sim.new_instance_id()
	h.attacker_id = p.entity.entity_id
	h.target_id = id
	h.power = power
	h.damage_split = {"physical": 1.0}
	if unit:
		h.size_policy = "none"
		h.tags = PackedStringArray(["Melee", "Unblockable", "Unparryable"])
	else:
		h.attacker_stat = 40.0
		h.attacker_height_m = 20.0
		h.poise_damage = 50.0
		h.tags = PackedStringArray(["Melee"])
		h.category = "melee"
		h.attacker_growth_stage = 5
	h.attacker_position = (e.actor as Node3D).global_position + Vector3(0, 0, 8) if e.actor != null else Vector3.ZERO
	Sim.queue_hit(h)


func _riders(d: EncounterDirector, enc: String) -> Array[CavalryEnemy]:
	var out: Array[CavalryEnemy] = []
	for id: String in d.members_of(enc):
		var e := Sim.get_entity(id)
		if e != null and e.is_alive() and e.actor is CavalryEnemy:
			out.append(e.actor as CavalryEnemy)
	return out


func _charges(riders: Array[CavalryEnemy]) -> int:
	var n := 0
	for r in riders:
		if is_instance_valid(r):
			n += r.charges_started
	return n


func test_the_iron_regiments_charge_rides_from_the_stables() -> void:
	var w := await _world(Vector2(650.0, -75.0), 5)
	var p := w.player()
	await step_ticks(10)
	for i in 80:
		if WorldState.is_destroyed(GATE):
			break
		_blow(p, GATE, 900.0, false)
		await step_ticks(1)
	assert_true(WorldState.is_destroyed(GATE), "the fort's gate breaks")
	# Breaking the kingdom's gate is war, as two offences make it (the capture's staging).
	WorldState.set_flag(FactionState.flag_id("aldmere", "hostile"), true)
	assert_true(FactionState.is_hostile("aldmere"), "Aldmere is at war with the giant")
	await step_ticks(30)
	var b: FortBattle = null
	for n in w.get_tree().get_nodes_in_group(BattleBoss.BATTLE_GROUP):
		if n is FortBattle:
			b = n
	assert_true(b != null, "the battle is loaded")
	if b == null:
		return
	# Into the engage trigger and past the portcullis, as a player walks in: the gate end of the bailey.
	await _move(w, Vector2(650.0, -112.0))
	await step_ticks(6)
	await _move(w, Vector2(650.0, -128.0))
	await step_ticks(6)
	assert_eq(b.state_name(), "engaged", "walking in engages the battle")
	_face(p, Vector3(650, 0, -215))
	await step_ticks(300)
	var d := w.director()
	for i in 40:
		var left := 0
		for id: String in d.members_of(WALL):
			var e := Sim.get_entity(id)
			if e != null and e.is_alive():
				left += 1
				_blow(p, id, 1.0e6, true)
		await step_ticks(15)
		if left == 0:
			break
	assert_true(b.phase_log.has(2), "the Wall fell: The Charge (%s)" % [b.phase_log])
	var riders := _riders(d, CHARGE)
	assert_eq(riders.size(), 6, "the six riders came")
	var far := 0
	for r in riders:
		if _flat(r.global_position, p.global_position) > 80.0:
			far += 1
	assert_eq(far, 6, "all of them at the stables, beyond their 70 m sight of the giant")
	var t0 := Sim.tick
	var charged := {}
	while Sim.tick - t0 < 25 * 60:
		await step_ticks(30)
		for r in riders:
			if is_instance_valid(r) and r.charges_started > 0:
				charged[r.entity_id] = true
	var lines := PackedStringArray()
	for r in riders:
		if is_instance_valid(r):
			lines.append("%s %d (%.0f m)" % [r.entity_id.get_slice(".", 2), r.charges_started, _flat(r.global_position, p.global_position)])
	print("    the Charge, 25 s after the Wall fell: %d charges, %d of 6 riders charged: %s" % [_charges(riders), charged.size(), ", ".join(lines)])
	assert_true(charged.size() >= 4, "the riders ride out from the stables and charge the giant (%d of 6 charged)" % charged.size())
	w.queue_free()
	await step_ticks(2)


func test_the_war_camps_riders_hold_their_pickets_and_charge_a_giant_in_reach() -> void:
	WorldState.set_flag(FactionState.flag_id("aldmere", "hostile"), true)
	var w := await _world(CAMP_WATCH, 4)
	var p := w.player()
	_face(p, CAMP_FACING)
	var d := w.director()
	await step_ticks(60)
	var riders := _riders(d, CAMP)
	assert_eq(riders.size(), 4, "the camp's four riders stand at their pickets")
	# 20 s 40 m east of the pickets: outside the camp's leash, no start point fits inside it.
	leashed.clear()
	await step_ticks(20 * 60)
	var rider_leashes := leashed.filter(func(l: Array) -> bool: return str(l[2]).contains("camp_rider"))
	var lines := PackedStringArray()
	for r in riders:
		var c := Vector3(CAMP_CENTRE.x, 0, CAMP_CENTRE.y)
		lines.append("%s %s, %.0f m from the camp's centre, %.0f m from the giant" % [r.entity_id.get_slice(".", 2),
			EnemyBrain.STATE_NAMES[r.brain.state], _flat(r.global_position, c), _flat(r.global_position, p.global_position)])
	print("    the war camp, 20 s with the giant 40 m east of the pickets: %d leashes, %d charges: %s" % [
		rider_leashes.size(), _charges(riders), "; ".join(lines)])
	assert_eq(rider_leashes.size(), 0, "no rider rides out past its leash and is sent home (%d leashes)" % rider_leashes.size())
	for r in riders:
		assert_true(r.brain.aware, "%s watches the giant" % r.entity_id)
		assert_true(_flat(r.global_position, Vector3(CAMP_CENTRE.x, 0, CAMP_CENTRE.y)) <= CAMP_LEASH_M,
			"%s holds inside the camp's leash" % r.entity_id)
	# He walks up to the pickets: they charge him.
	var before := _charges(riders)
	var t0 := Sim.tick
	var goal := Vector3(CAMP_CLOSE.x, 0, CAMP_CLOSE.y)
	while Sim.tick - t0 < 20 * 60 and _charges(riders) == before:
		var to := goal - p.global_position
		to.y = 0.0
		if to.length() > 2.0:
			p.camera_rig.yaw = atan2(-to.x, -to.z)
			p.router.injected_move = Vector2(0, 1)
		else:
			p.router.injected_move = Vector2.ZERO
		await step_ticks(6)
	p.router.injected_move = Vector2.ZERO
	print("    the war camp: the giant walked to %s; %d charges after %.1f s" % [
		Vector2(p.global_position.x, p.global_position.z).snapped(Vector2.ONE), _charges(riders) - before, (Sim.tick - t0) / 60.0])
	assert_true(_charges(riders) > before, "a rider charges the giant at the pickets")
	w.queue_free()
	await step_ticks(2)
