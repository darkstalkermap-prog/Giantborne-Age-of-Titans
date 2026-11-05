extends IntegrationSuite
## Flee reachability in the Valley (P15, plan §3.17, spec §15 "fleeing enemies have a reachable
## destination", review 7.1 #26; slow, runs with --slow): the soldiers of the return patrol on
## the King's Bridge and of the ruins' courtyard garrison, spawned by the EncounterDirector from
## their data and forced to flee from the giant (aware of it, morale broken), pick flee points on
## the human navigation layer that a layer-1 path reaches, and run there on their own AI. The
## bridge is the hard case: a 12 m deck between blocker rails, the barricade's channel west of it
## and the bridgehead court east of it (both open, as on the return leg).

const RETURN_PATROL := "encounter.return_patrol"
const COURTYARD := "encounter.ruins_courtyard"
## Arrival tolerance (EnemyBrain.FLEE_ARRIVE_M is 1.2 m) and the time each gets to run (a flee
## point behind the barricade's abutment is a 35 m run through the opened channel).
const ARRIVE_M := 1.5
const RUN_TICKS := 60 * 15

var level: LevelRoot


func before_each() -> void:
	await super()
	level = null


func after_each() -> void:
	if level != null and is_instance_valid(level):
		level.queue_free()
	level = null
	await super()


## Archers and mages stand still (they would shoot the giant while the soldiers flee).
func _on_member_spawned(_encounter_id: String, _entity_id: String, node: Node3D) -> void:
	if node is EnemyActor and not (node is SoldierEnemy):
		(node as EnemyActor).ai_enabled = false


func _soldiers(d: EncounterDirector, encounter_id: String) -> Array[SoldierEnemy]:
	var out: Array[SoldierEnemy] = []
	for id in d.members_of(encounter_id):
		var n := d.spawned(id)
		if n is SoldierEnemy:
			out.append(n as SoldierEnemy)
	return out


## Forces `encounter_id`'s soldiers to flee from the giant at `threat`, one at a time (the others
## wait with their AI paused, and each one leaves through the director once it has arrived:
## without agent avoidance a soldier standing at its flee point on an opened gate's nav link would
## block the next one's path - see the system doc's known gaps), and checks each flee point
## (reachable on the human layer, away from the giant) and the run there.
func _flee_check(d: EncounterDirector, encounter_id: String, threat: Vector3, what: String) -> void:
	var soldiers := _soldiers(d, encounter_id)
	assert_eq(soldiers.size(), 3, "%s: three soldiers spawned" % what)
	var map := level.nav_map()
	for s in soldiers:
		s.ai_enabled = false
	for s in soldiers:
		s.ai_enabled = true
		s.brain.on_noise(Sim.tick, threat, "player", true)
		s.brain.morale = 5.0
		s.brain.decide(Sim.tick, s.controller.state, s.global_position, func() -> bool: return true, func() -> void: pass)
		assert_eq(s.brain.state, EnemyBrain.AIState.FLEE, "%s: %s flees (%s)" % [what, s.entity_id, s.brain.state_name()])
		var fp := s.brain.flee_point
		assert_true(fp != Vector3.INF, "%s: %s has a flee point" % [what, s.entity_id])
		if fp == Vector3.INF:
			continue
		var on := NavigationServer3D.region_get_closest_point(level.nav_region(ValleyProbe.HUMAN), fp)
		assert_true(ValleyProbe.flat(on, fp) < 0.5, "%s: %s's flee point %s is on the human layer" % [what, s.entity_id, fp])
		var path := NavigationServer3D.map_get_path(map, s.global_position, fp, true, ValleyProbe.HUMAN)
		assert_true(path.size() > 0 and path[path.size() - 1].distance_to(fp) <= 1.0,
			"%s: a human path reaches %s's flee point" % [what, s.entity_id])
		assert_true(ValleyProbe.flat(fp, threat) > ValleyProbe.flat(s.global_position, threat),
			"%s: %s runs away from the giant" % [what, s.entity_id])
		var closest := INF
		for i in RUN_TICKS:
			if s.brain.flee_point != Vector3.INF:
				closest = minf(closest, ValleyProbe.flat(s.global_position, s.brain.flee_point))
			if closest <= ARRIVE_M:
				break
			await step_ticks(1)
		assert_true(closest <= ARRIVE_M, "%s: %s reaches its flee point (%.1f m short, %s)" % [
			what, s.entity_id, closest, s.brain.state_name()])
		assert_true(s.global_position.y > -1.0, "%s: %s never falls off the level" % [what, s.entity_id])
		d.despawn(s.entity_id)
		await step_ticks(1)


func test_the_return_patrol_and_the_courtyard_flee_to_reachable_points() -> void:
	level = ValleyProbe.instance(false)
	var d := level.director()
	d.member_spawned.connect(_on_member_spawned)
	world.add_child(level)
	assert_true(await ValleyProbe.wait_for_navigation(self, level), "navigation ready")
	var p := level.player()
	p.router.use_injection = true
	p.entity.combatant.unkillable = true
	# The return leg: the king is dead, the barricade and the practice gate are open.
	WorldState.set_flag("world.ogre_king.defeated", true)
	for id: String in ["valley.village.barricade", "valley.ruins.practice_gate"]:
		assert_true((ValleyProbe.prop(level, id) as BreakableProp).force_open("test"), "%s is open" % id)
	await ValleyProbe.wait_for_map_update(self, level)
	# The bridge: the giant comes from the ruins (east).
	var east := Vector3(121, 0, -20)
	GameSession.place_player(p, Transform3D(Basis(Vector3.UP, PI * 0.5), east + Vector3(0, 0.05, 0)))
	await step_ticks(1)
	d.force_activate(RETURN_PATROL)
	d.update_now()
	await step_ticks(2)
	assert_eq(d.encounter_state(RETURN_PATROL), EncounterDirector.ACTIVE, "the return patrol holds the bridge")
	await _flee_check(d, RETURN_PATROL, east, "the bridge")
	# The courtyard: the giant comes through the practice gate (west).
	var gate := Vector3(136, 0, -22)
	GameSession.place_player(p, Transform3D(Basis(Vector3.UP, -PI * 0.5), gate + Vector3(0, 0.05, 0)))
	await step_ticks(1)
	d.force_activate(COURTYARD)
	d.update_now()
	await step_ticks(2)
	assert_eq(d.encounter_state(COURTYARD), EncounterDirector.ACTIVE, "the courtyard garrison is up")
	await _flee_check(d, COURTYARD, gate, "the courtyard")
