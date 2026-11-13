extends IntegrationSuite
## M9 gate (lane ironreg; FOLLOWUPS, the M8 release check's Iron Regiment row and lane aldmere's "left" items): the
## breach of Fort Aldmere's gate stays made after a death, and the fort gate's waystone the death reloads is no fight -
## on the real world (scenes/world/world.tscn, deterministic streaming), the campaign from world_start at the fort
## gate's waystone, saving on, a giant that takes no damage, the gate broken as the giant (blows that offend Aldmere).
##   * The garrison falls back to its posts and stands down once the gate is breached, until the giant enters the
##     bailey this visit (data/world/encounter_aldmere_fort_gate.json, stand_down_when). So the breach's checkpoint
##     (quest.iron_regiment's start, an ordinary request) is taken as the garrison stands down, with none of it aware
##     of the giant: before, it waited on the garrison aware about him, then on the battle, and a death dropped it -
##     every death reloaded the waystone with the gate whole (lane aldmere's aldmere_e5_ir4: six attempts each broke it
##     again for 66-77 s under the wall archers and the bastions' ballistae). After a death the reload puts the
##     garrison's pikes, banner, archers and crews at their posts, at peace, and the giant walks from the waystone into
##     the bailey untouched - before, the breach roused them for good and after each reload they held the giant at the
##     waystone (aldmere_e5_ir5: twice 130 s, until he died). A blow on a stood-down member after the breach's
##     checkpoint rouses the garrison (P29's provoked flag) but is not in the checkpoint: a death still comes back to
##     it standing down. In the bailey the battle has them as before: the wall crews serve the bastions' two
##     ballistae, held until the Charge, and all four shoot from the Charge.
## Each case at stage 4 (the crown-first giant fights the garrison from his first blow on the gate) and at stage 5
## with Brannock's banner (the garrison stands down for it while the gate stands, and goes on standing down).
##   * Fix-up 1 (the lane's verifier): the war camp's first wreck - which starts the crown's sabotage
##     (quest.war_engines) and offends Aldmere - is not checkpointed while the camp is aware about the giant: a death
##     comes back to the Aldmere road's waystone, 18 m from that catapult, with the camp at peace and nothing wrecked.
##     The lane had made the start of an oath's road a completion request (taken at once, whoever is aware about):
##     the wreck was committed in the same tick, and after a death the camp's engines and riders shot and rode down a
##     giant standing at the waystone (14 hits, dead within 40 s).

const SCENE := "res://scenes/world/world.tscn"
const FORT_CP := "world.cp.fort_gate"
const GATE := "world.aldmere.fort_gate"
const GARRISON := "encounter.aldmere_fort_gate"
const WALL := "encounter.aldmere_iron_regiment_wall"
const CHARGE := "encounter.aldmere_iron_regiment_charge"
const BANNER := "item.brannock_banner"
const BASTION_BALLISTAE := ["world.aldmere.fort_ballista_e", "world.aldmere.fort_ballista_w"]
const WALL_CREWS := ["world.aldmere.wall_crew_1", "world.aldmere.wall_crew_2"]
## The bailey's floor beyond the engage trigger (the giant's titan path from the waystone ends here).
const BAILEY := Vector3(650.0, 60.0, -130.0)
const INSIDE_Z := -118.0
## The war camp's sabotage (fix-up 1): the Aldmere road's waystone and the camp's west catapult, 18 m from it.
const ROAD_CP := "world.cp.aldmere_road"
const ROAD_CP_AT := Vector2(470.0, 60.0)
const CAMP := "encounter.aldmere_war_camp"
const CAMP_CATAPULT := "world.aldmere.camp_catapult_1"

var w: WorldRoot
## [tick, respawn, reason, the gate garrison standing down, its members aware of the giant] of every checkpoint
## committed.
var saved: Array = []
## Hits of the gate garrison's members that reached the giant.
var garrison_hits: Array = []
## [tick, attacker id, health damage] of every hit that reached the giant.
var giant_hits: Array = []


func before_each() -> void:
	await super()
	saved.clear()
	garrison_hits.clear()
	giant_hits.clear()
	Events.checkpoint_saved.connect(_on_saved)
	Events.hit_resolved.connect(_on_giant_hit)


func after_each() -> void:
	if Events.checkpoint_saved.is_connected(_on_saved):
		Events.checkpoint_saved.disconnect(_on_saved)
	if Events.hit_resolved.is_connected(_on_giant_hit):
		Events.hit_resolved.disconnect(_on_giant_hit)
	Quests.end_dialogue()
	for f in Formation.live():
		f.dissolve()
	if w != null and is_instance_valid(w):
		w.queue_free()
	w = null
	await get_tree().process_frame
	FactionState.reset_for_tests()
	WanderDirector.reset_for_tests()
	SaveSlots.delete_slot(true)
	GameSession.persist = false
	await super()


func _on_saved(tick: int, respawn: String, _ok: bool, _message: String) -> void:
	var down := false
	var aware := -1
	if w != null and is_instance_valid(w) and w.director() != null:
		down = w.director().p29_standing_down(GARRISON)
		aware = _garrison_aware().size()
	saved.append([tick, respawn, str(GameSession.checkpoint_doc.get("checkpoint", {}).get("reason", "")), down, aware])


func _on_giant_hit(tick: int, result: HitResult) -> void:
	if w == null or result == null or result.event == null:
		return
	var p := w.player()
	if p == null or p.entity == null or result.event.target_id != p.entity.entity_id:
		return
	giant_hits.append([tick, result.event.attacker_id, result.health_damage])
	if w.director() != null and w.director().members_of(GARRISON).has(result.event.attacker_id):
		garrison_hits.append([tick, result.event.attacker_id])


static func _profile(stage: int) -> Dictionary:
	for rec: Dictionary in GameData.records_of_type("growth_profile"):
		if int(rec.get("stage", 0)) == stage:
			return rec
	return {}


static func _flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0.0, v.z)


## A load of the world as main.gd makes it: the level enters the tree, then the session restores the giant at
## its respawn, and the ring around it streams in before it is set down there.
func _load() -> void:
	WanderDirector.view_probe = func(_p: Vector3) -> bool: return false
	w = (load(SCENE) as PackedScene).instantiate() as WorldRoot
	world.add_child(w)
	w.streamer.deterministic = true
	var p := w.player()
	p.router.use_injection = true
	GameSession.on_level_ready(w, p)
	p.entity.apply_status("status.debug_invulnerable", NAN, -1.0, "test")
	await _move(Vector2(p.global_position.x, p.global_position.z))
	await step_ticks(5)


func _unload() -> void:
	Quests.end_dialogue()
	for f in Formation.live():
		f.dissolve()
	if w != null:
		w.queue_free()
	w = null
	await get_tree().process_frame
	await get_tree().process_frame
	await step_ticks(1)


## Puts the giant on the ground at `xz` once the ring around it is loaded.
func _move(xz: Vector2) -> void:
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


## The campaign's New Game at waystone `cp` (world_start; the fort gate's by default), saving on, the giant grown
## to `stage` and that checkpointed (as a growth at a shrine is).
func _new_game(stage: int, banner: bool, cp := FORT_CP) -> void:
	GameSession.persist = true
	GameSession.start_world_for_tests(cp)
	GameSession.level_id = "level.world"
	if banner:
		WorldState.add_item(BANNER, 1, "test")
	await _load()
	var p := w.player()
	var grown := false
	for i in 240:
		if p.current_growth_stage() == stage or bool(p.growth.debug_set_stage(stage).get("ok", false)):
			grown = true
			break
		await step_ticks(1)
	assert_true(grown, "the giant grows to stage %d" % stage)
	await step_ticks(5)
	GameSession.request_checkpoint("growth")
	var taken: bool = await TestWait.until(self, func() -> bool: return GameSession.pending_checkpoint().is_empty(), 120)
	assert_true(taken, "the grown giant's checkpoint (%s)" % [GameSession.checkpoint_blockers()])
	assert_false(QuestConditions.truthy(GameSession.checkpoint_doc.world.flags.get("world.aldmere.fort_breached", false)),
		"the checkpoint before the breach holds the gate whole")


## Strikes world object `id` as the giant (from `from`, an offset of the object's place) until its health is at
## most `frac` of its maximum or it is destroyed.
func _strike_until(id: String, frac: float, from: Vector3) -> void:
	var p := w.player()
	for i in 200:
		var e := Sim.get_entity(id)
		if e == null or WorldState.is_destroyed(id) or e.combatant.pools.health <= frac * e.combatant.pools.health_max:
			return
		var h := HitEvent.new()
		h.tick = Sim.tick
		h.instance_id = Sim.new_instance_id()
		h.attacker_id = p.entity.entity_id
		h.target_id = id
		h.power = 300.0
		h.attacker_stat = 40.0
		h.attacker_height_m = 20.0
		h.damage_split = {"physical": 1.0}
		h.poise_damage = 50.0
		h.tags = PackedStringArray(["Melee"])
		h.category = "melee"
		h.attacker_growth_stage = p.current_growth_stage()
		h.attacker_position = (e.actor as Node3D).global_position + from if e.actor != null else Vector3.ZERO
		Sim.queue_hit(h)
		await step_ticks(6)


## Strikes the gate as the giant (an offence against Aldmere) until its health is at most `frac` of its maximum.
func _strike_gate(frac: float) -> void:
	await _strike_until(GATE, frac, Vector3(0, 0, 8))


## One ordinary blow of the giant on the member `id` (a light hit, not a kill).
func _strike_member(id: String) -> void:
	var e := Sim.get_entity(id)
	if e == null or e.actor == null or not e.is_alive():
		return
	var h := HitEvent.new()
	h.tick = Sim.tick
	h.instance_id = Sim.new_instance_id()
	h.attacker_id = w.player().entity.entity_id
	h.target_id = id
	h.power = 5.0
	h.damage_split = {"physical": 1.0}
	h.tags = PackedStringArray(["Melee"])
	h.category = "melee"
	h.attacker_position = (e.actor as Node3D).global_position + Vector3(0, 0, 6)
	Sim.queue_hit(h)


func _battle() -> FortBattle:
	if w == null:
		return null
	for n in w.get_tree().get_nodes_in_group(BattleBoss.BATTLE_GROUP):
		if n is FortBattle and w.is_ancestor_of(n):
			return n
	return null


## The garrison's members standing in the world, alive (entity ids).
func _garrison_up() -> Array:
	var d := w.director()
	return Array(d.members_of(GARRISON)).filter(func(id: String) -> bool:
		var e := Sim.get_entity(id)
		return d.member_status(id) == EncounterDirector.SPAWNED and e != null and e.is_alive())


## The garrison's members aware of the giant now.
func _garrison_aware() -> Array:
	return _garrison_up().filter(func(id: String) -> bool:
		var a := Sim.get_entity(id).actor as EnemyActor
		return a != null and a.brain != null and a.brain.aware)


## The garrison's members not stood down (their faction_standing), with it.
func _garrison_not_down() -> Array:
	return _garrison_up().filter(func(id: String) -> bool:
		var a := Sim.get_entity(id).actor as EnemyActor
		return a == null or str(a.get("faction_standing")) != "stood_down")


## Walks the giant along its own titan path to `goal` for at most `seconds`; the last position.
func _walk(goal: Vector3, seconds: float) -> Vector3:
	var p := w.player()
	var layers: int = p.growth.nav_query_mask()
	var path := NavQuery.path(w, p.global_position, goal, layers, NavQuery.PURPOSE_FAR)
	assert_true(path.size() >= 2, "a titan path from %s to %s" % [p.global_position, goal])
	var idx := 1
	for t in int(seconds * 60.0):
		if _flat(goal - p.global_position).length() < 3.0 or p.global_position.z < INSIDE_Z:
			break
		while idx < path.size() and _flat(path[idx] - p.global_position).length() < 2.5:
			idx += 1
		var next := goal if idx >= path.size() else path[idx]
		p.camera_rig.yaw = TargetingRules.yaw_of(_flat(next - p.global_position))
		p.router.injected_move = Vector2(0, 1)
		await step_ticks(1)
	p.router.injected_move = Vector2.ZERO
	return p.global_position


func _kill(id: String) -> void:
	var e := Sim.get_entity(id)
	if e == null or e.actor == null or not e.is_alive():
		return
	var h := HitEvent.new()
	h.tick = Sim.tick
	h.instance_id = Sim.new_instance_id()
	h.attacker_id = w.player().entity.entity_id
	h.target_id = id
	h.power = 1.0e6
	h.size_policy = "none"
	h.damage_split = {"physical": 1.0}
	h.tags = PackedStringArray(["Melee", "Unblockable", "Unparryable"])
	h.attacker_position = (e.actor as Node3D).global_position + Vector3(0, 0, 6)
	Sim.queue_hit(h)


## The bastions' ballistae in the fight now (crewed, free to shoot, not held), sorted.
func _bastions_shooting() -> Array:
	var out: Array = []
	for n in w.get_tree().get_nodes_in_group(SiegeEngine.GROUP):
		var e := n as SiegeEngine
		if e != null and BASTION_BALLISTAE.has(e.world_id) and e.in_action():
			out.append(e.world_id)
	out.sort()
	return out


## The enemies aware of the giant within `radius_m` of him now (entity ids, sorted): what holds an ordinary
## checkpoint request back (GameSession.checkpoint_blockers).
func _aware_within(radius_m: float) -> Array:
	var out: Array = []
	var p := w.player()
	for n in get_tree().get_nodes_in_group("enemies"):
		var en := n as Node3D
		if en == null or not en.is_inside_tree():
			continue
		var e: Variant = en.get("entity")
		if e is CombatEntity and not (e as CombatEntity).is_alive():
			continue
		var brain: Variant = en.get("brain")
		if brain == null or not (brain is Object) or not ("aware" in brain) or not bool(brain.get("aware")):
			continue
		if en.global_position.distance_to(p.global_position) <= radius_m:
			out.append(str(en.get("entity_id")))
	out.sort()
	return out


## The hits on the giant by the war camp's members or engines (fix-up 1).
func _camp_hits() -> Array:
	var camp: Array = Array(w.director().members_of(CAMP))
	for entry: Variant in GameData.get_record(CAMP).get("engines", []):
		if typeof(entry) == TYPE_DICTIONARY:
			camp.append(str(entry.get("engine", "")))
	return giant_hits.filter(func(x: Array) -> bool: return camp.has(str(x[1])))


## True when the last checkpoint holds world object `id` destroyed.
static func _checkpoint_holds_destroyed(id: String) -> bool:
	var deltas: Variant = (GameSession.checkpoint_doc.get("world", {}) as Dictionary).get("deltas", {})
	return typeof(deltas) == TYPE_DICTIONARY and typeof(deltas.get(id)) == TYPE_DICTIONARY \
		and bool((deltas[id] as Dictionary).get("destroyed", false))


func _breach_case(stage: int, banner: bool) -> void:
	var name := "stage %d%s" % [stage, " with Brannock's banner" if banner else ""]
	await _new_game(stage, banner)
	var p := w.player()
	var d := w.director()
	var b := _battle()
	assert_true(b != null, "%s: the battle is loaded" % name)
	if b == null:
		return
	# The gate struck: the garrison takes up arms (or, for the banner, stands down while the gate stands).
	await _move(Vector2(650.0, -80.0))
	await step_ticks(30)
	await _strike_gate(0.15)
	await step_ticks(90)
	assert_false(WorldState.is_destroyed(GATE), "%s: the gate still stands" % name)
	assert_true(FactionState.is_hostile("aldmere"), "%s: the blows on Aldmere's gate are offences: at war" % name)
	var aware_before := _garrison_aware()
	print("    fort breach (%s): before the last blow the garrison %d up, %d aware, standing down %s" % [name,
		_garrison_up().size(), aware_before.size(), d.p29_standing_down(GARRISON)])
	if banner:
		assert_true(d.p29_standing_down(GARRISON), "%s: the garrison stands down for the banner while the gate stands" % name)
	else:
		assert_true(aware_before.size() >= 4, "%s: the garrison fights the giant at its gate (%d aware)" % [name, aware_before.size()])
	# The gate falls.
	saved.clear()
	await _strike_gate(0.0)
	assert_true(WorldState.is_destroyed(GATE), "%s: the gate is breached" % name)
	var taken: bool = await TestWait.until(self, func() -> bool:
		return QuestConditions.truthy(GameSession.checkpoint_doc.world.flags.get("world.aldmere.fort_breached", false)) \
			and str(GameSession.checkpoint_doc.world.flags.get("quest.iron_regiment.stage", "")) != "", 120)
	print("    fort breach (%s): after the breach the checkpoints %s, the garrison standing down %s, %d aware" % [name,
		saved, d.p29_standing_down(GARRISON), _garrison_aware().size()])
	assert_true(taken, "%s: the breach is checkpointed within 2 s (blockers %s, pending %s)" % [name,
		GameSession.checkpoint_blockers(), GameSession.pending_checkpoint()])
	# Fix-up 1: the breach's checkpoint is the ordinary one, taken as the garrison stands down - never mid-fight.
	var breach_cps := saved.filter(func(s: Array) -> bool: return str(s[2]) == "quest_started")
	assert_eq(breach_cps.size(), 1, "%s: one checkpoint for the breach (%s)" % [name, saved])
	if not breach_cps.is_empty():
		assert_true(bool(breach_cps[0][3]), "%s: the breach is checkpointed with the garrison standing down (%s)" % [name, saved])
		assert_eq(int(breach_cps[0][4]), 0, "%s: ...none of it aware of the giant as it is taken (%s)" % [name, saved])
	assert_eq(Quests.quest_state("quest.iron_regiment"), "active", "%s: the breach starts the crown's road by breach" % name)
	assert_eq(GameSession.respawn_checkpoint(), FORT_CP, "%s: the respawn stays the fort gate's waystone" % name)
	await step_ticks(40)
	assert_true(d.p29_standing_down(GARRISON), "%s: the breached gate's garrison falls back and stands down" % name)
	assert_eq(_garrison_aware(), [], "%s: none of it stays aware of the giant" % name)
	var provoked := EncounterDirector.provoked_flag(GARRISON)
	if not banner:
		# Fix-up 1: a blow on a stood-down member after the breach's checkpoint rouses the garrison for good (P29) -
		# the giant fights it at the gate - but it is not in the checkpoint.
		var pikes := _garrison_up().filter(func(id: String) -> bool: return id.contains("pike"))
		assert_false(pikes.is_empty(), "%s: a pikeman of the garrison stands at its post" % name)
		if not pikes.is_empty():
			_strike_member(str(pikes[0]))
		await step_ticks(10)
		assert_true(QuestConditions.truthy(WorldState.get_flag(provoked)), "%s: the blow provokes the garrison" % name)
		assert_false(d.p29_standing_down(GARRISON), "%s: ...which stands down no longer" % name)
		assert_false(QuestConditions.truthy(GameSession.checkpoint_doc.world.flags.get(provoked, false)),
			"%s: the breach's checkpoint, taken before the blow, does not hold the provocation" % name)
	# Into the bailey: the battle has them as before.
	await _move(Vector2(650.0, -112.0))
	await step_ticks(6)
	await _move(Vector2(650.0, -128.0))
	await step_ticks(90)
	assert_eq(b.state_name(), "engaged", "%s: walking in engages the battle" % name)
	assert_false(d.p29_standing_down(GARRISON), "%s: in the bailey the garrison is the battle's again" % name)
	# The giant dies in the battle: the death screen's confirm reloads the last checkpoint.
	GameSession.reload_checkpoint("death")
	await _unload()
	await _load()
	p = w.player()
	d = w.director()
	b = _battle()
	await step_ticks(60)
	var up := _garrison_up()
	print("    fort breach (%s): after a death the giant at (%.1f, %.1f), the gate broken %s, the garrison %d up, %d not standing down, %d aware" % [
		name, p.global_position.x, p.global_position.z, WorldState.is_destroyed(GATE), up.size(), _garrison_not_down().size(),
		_garrison_aware().size()])
	assert_true(WorldState.is_destroyed(GATE), "%s: after a death the breach stays made" % name)
	assert_false(QuestConditions.truthy(WorldState.get_flag(provoked)), "%s: no provocation comes back with the reload" % name)
	assert_true(_flat(p.global_position - Vector3(650.0, 0.0, -55.0)).length() < 15.0, "%s: at the fort gate's waystone (%s)" % [
		name, p.global_position])
	assert_true(b != null and b.state_name() == "waiting" and not b.is_gate_closed(), "%s: the battle waits, the portcullis open" % name)
	assert_true(up.size() >= 10, "%s: the garrison is at the fort (%d up)" % [name, up.size()])
	assert_eq(_garrison_not_down(), [], "%s: every member stands down at its post" % name)
	assert_eq(_garrison_aware(), [], "%s: none is aware of the giant at the waystone" % name)
	# The walk in from the waystone: no blow, arrow or bolt of the garrison on the way.
	garrison_hits.clear()
	var at := await _walk(BAILEY, 30.0)
	print("    fort breach (%s): the walk in ends at (%.1f, %.1f); the garrison's hits on the way %s" % [name, at.x, at.z, garrison_hits])
	assert_true(at.z < INSIDE_Z, "%s: the giant walks from the waystone into the bailey (at z %.1f)" % [name, at.z])
	assert_eq(garrison_hits, [], "%s: untouched by the garrison" % name)
	await step_ticks(90)
	assert_eq(b.state_name(), "engaged", "%s: the battle engages again, a full attempt" % name)
	# The battle as lane aldmere left it: the bastions' pair crewed by the wall crews and held through the Wall.
	for crew: String in WALL_CREWS:
		var e := Sim.get_entity(crew)
		assert_true(e != null and e.is_alive() and e.team == CombatEntity.Team.ENEMY, "%s: %s serves its ballista for Aldmere" % [name, crew])
	assert_eq(_bastions_shooting(), [], "%s: the bastions' pair holds its fire in the Wall" % name)
	var planned := b.planned()
	for id: String in d.members_of(WALL):
		if planned.has(id) and not id.contains("regiment_crew"):
			_kill(id)
	await step_ticks(60)
	assert_true(b.phase_log.has(2), "%s: the Wall falls: the Charge (%s)" % [name, b.phase_log])
	assert_eq(_bastions_shooting(), BASTION_BALLISTAE, "%s: from the Charge the bastions' pair shoots" % name)


func test_the_breach_stays_made_after_a_death_at_stage_4() -> void:
	await _breach_case(4, false)


func test_the_breach_stays_made_after_a_death_at_stage_5_with_the_banner() -> void:
	await _breach_case(5, true)


## Fix-up 1: the crown's sabotage begun beside the Aldmere road's waystone - the war camp's west catapult wrecked at
## stage 4 with a crew aware of the giant - then a death.
func test_the_war_camps_first_wreck_is_not_checkpointed_mid_fight() -> void:
	await _new_game(4, false, ROAD_CP)
	var p := w.player()
	assert_true(_flat(p.global_position - Vector3(ROAD_CP_AT.x, 0.0, ROAD_CP_AT.y)).length() < 15.0,
		"the New Game stands at the Aldmere road's waystone (%s)" % [p.global_position])
	assert_false(FactionState.is_hostile("aldmere"), "Aldmere is at peace")
	# Beside the catapult, 18 m from the waystone: it is wrecked with its camp about the giant.
	await _move(Vector2(480.0, 55.0))
	await step_ticks(60)
	saved.clear()
	await _strike_until(CAMP_CATAPULT, 0.0, Vector3(0, 0, -8))
	var aware := _aware_within(GameSession.AWARE_BLOCK_RADIUS_M)
	print("    war camp: the catapult wrecked %s, the sabotage %s, Aldmere hostile %s, aware within 40 m %s" % [
		WorldState.is_destroyed(CAMP_CATAPULT), Quests.quest_state("quest.war_engines"), FactionState.is_hostile("aldmere"), aware])
	assert_true(WorldState.is_destroyed(CAMP_CATAPULT), "the camp's west catapult is wrecked")
	assert_eq(Quests.quest_state("quest.war_engines"), "active", "the wreck starts the crown's sabotage")
	assert_true(FactionState.is_hostile("aldmere"), "the blows on Aldmere's engine are offences: at war")
	assert_false(aware.is_empty(), "a camp member is aware of the giant within 40 m")
	await step_ticks(120)
	var pending := GameSession.pending_checkpoint()
	print("    war camp: 2 s later the checkpoints %s, pending %s, blockers %s" % [saved, pending, GameSession.checkpoint_blockers()])
	assert_eq(saved, [], "no checkpoint is committed while the camp is aware about the giant (%s)" % [saved])
	assert_false(_checkpoint_holds_destroyed(CAMP_CATAPULT), "the last checkpoint holds the catapult whole")
	assert_eq(str(pending.get("reason", "")), "quest_started", "the sabotage's start waits for its checkpoint")
	assert_false(bool(pending.get("completion", false)), "...as an ordinary request (aware enemies hold it back)")
	# A death: the reload gives back the waystone with the camp at peace and nothing wrecked.
	GameSession.reload_checkpoint("death")
	await _unload()
	await _load()
	p = w.player()
	await step_ticks(60)
	print("    war camp: after a death the giant at (%.1f, %.1f), the catapult wrecked %s, the sabotage %s, Aldmere hostile %s, aware within 40 m %s" % [
		p.global_position.x, p.global_position.z, WorldState.is_destroyed(CAMP_CATAPULT), Quests.quest_state("quest.war_engines"),
		FactionState.is_hostile("aldmere"), _aware_within(GameSession.AWARE_BLOCK_RADIUS_M)])
	assert_true(_flat(p.global_position - Vector3(ROAD_CP_AT.x, 0.0, ROAD_CP_AT.y)).length() < 15.0,
		"after a death the giant is at the Aldmere road's waystone (%s)" % [p.global_position])
	assert_false(WorldState.is_destroyed(CAMP_CATAPULT), "the catapult stands again")
	assert_true(Quests.quest_state("quest.war_engines") != "active", "the sabotage is not begun (%s)" % Quests.quest_state("quest.war_engines"))
	assert_false(FactionState.is_hostile("aldmere"), "Aldmere is at peace")
	# 30 s at the waystone, his own health at stake: no blow, arrow, bolt or stone of the camp reaches him.
	p.entity.combatant.statuses.remove("status.debug_invulnerable")
	giant_hits.clear()
	var health: float = p.entity.combatant.pools.health
	await step_ticks(30 * 60)
	print("    war camp: 30 s at the waystone - the hits on the giant %s, his health %.0f of %.0f" % [giant_hits, p.entity.combatant.pools.health, health])
	assert_eq(_camp_hits(), [], "no camp member or engine strikes the giant at the waystone")
	assert_true(p.entity.is_alive() and p.entity.combatant.pools.health >= health, "the giant stands there unharmed")
