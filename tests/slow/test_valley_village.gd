extends IntegrationSuite
## Thornwick's people, guards and the Hollow sparring post in the real Valley (P11b, plan §3.13,
## §4.3-4.4; slow, runs with --slow), all spawned by the EncounterDirector from data:
##   * encounter.village_guards: four guards at their village posts (valley.marker.guard_post_1..4,
##     claimed), the captain (commander) before the barricade and the archer on the watchtower - all
##     neutral (team NEUTRAL, not targetable), holding, never aware (no checkpoint is deferred);
##   * encounter.village_folk (not budgeted): six villagers on the human navmesh and Elder Maren
##     with her NpcTalker (dialogue.elder);
##   * standing down sends every villager to a reachable cottage door (valley.marker.safe_house_*)
##     where it stops processing, the guards stand down at their posts and stay neutral, the elder
##     stays; turning hostile makes every guard ENEMY and lockable;
##   * encounter.hollow_sparring (not budgeted): the sparring post beside the Hollow's dummies,
##     lockable, swinging at a giant that stands within 4 m, never aware.

const GUARDS := ["valley.village.guard_1", "valley.village.guard_2", "valley.village.guard_3", "valley.village.guard_4"]
const VILLAGERS := ["valley.village.villager_1", "valley.village.villager_2", "valley.village.villager_3",
	"valley.village.villager_4", "valley.village.villager_5", "valley.village.villager_6"]
const ELDER := "valley.village.elder"
const CAPTAIN := "valley.village.captain"
const ARCHER := "valley.village.tower_archer"
const POST := "valley.hollow.sparring_post"
## Where the giant waits: west of the square, within reach of the village encounters only (the
## field ogre's activates within 60 m of (40, 55)).
const VILLAGE_STAND := Vector3(30, 0.05, -30)

var level: LevelRoot
var telegraphs: Array = []


func before_each() -> void:
	await super()
	FactionState.reset_for_tests()
	telegraphs.clear()
	Events.telegraph_started.connect(_on_telegraph)


func after_each() -> void:
	if Events.telegraph_started.is_connected(_on_telegraph):
		Events.telegraph_started.disconnect(_on_telegraph)
	if level != null and is_instance_valid(level):
		level.queue_free()
	level = null
	await super()


func _on_telegraph(tick: int, actor_id: String, action_id: String, target_id: String, shape: String,
		_origin: Vector3, _yaw: float, _radius: float, _length: float, _duration_s: float) -> void:
	telegraphs.append([tick, actor_id, action_id, target_id, shape])


## The Valley with its director, the giant moved to `at`, the navigation ready and one director
## update run.
func _valley_at(at: Vector3) -> EncounterDirector:
	level = ValleyProbe.instance(false)
	world.add_child(level)
	var p := level.player()
	p.router.use_injection = true
	assert_true(await ValleyProbe.wait_for_navigation(self, level), "navigation ready")
	GameSession.place_player(p, Transform3D(Basis(), at))
	await step_ticks(1)
	var d := level.director()
	d.update_now()
	await step_ticks(2)
	return d


func _on_human_navmesh(pos: Vector3) -> bool:
	var on := NavigationServer3D.region_get_closest_point(level.nav_region(ValleyProbe.HUMAN), pos)
	return ValleyProbe.flat(on, pos) < 0.5


func _spawn_point(encounter_id: String, entity_id: String) -> Vector3:
	for s: Dictionary in GameData.get_record(encounter_id).get("spawns", []):
		if s.get("entity_id") == entity_id:
			return ValleyProbe.v3(s.position_m)
	return Vector3.INF


func test_the_village_spawns_from_data_neutral_and_calm() -> void:
	var d := await _valley_at(VILLAGE_STAND)
	assert_eq(d.encounter_state("encounter.village_guards"), EncounterDirector.ACTIVE, "the guards are out")
	assert_eq(d.encounter_state("encounter.village_folk"), EncounterDirector.ACTIVE, "and the folk")
	await step_ticks(40)
	for id: String in GUARDS + [CAPTAIN, ARCHER]:
		var g := d.spawned(id) as EnemyActor
		assert_true(g != null, "%s spawned" % id)
		if g == null:
			continue
		assert_true(ValleyProbe.flat(g.home_position, _spawn_point("encounter.village_guards", id)) < 0.1,
			"%s at its data position" % id)
		assert_eq(g.faction, "village", "%s of faction village" % id)
		assert_eq(g.entity.team, CombatEntity.Team.NEUTRAL, "%s neutral" % id)
		assert_false(TargetingRules.player_may_target(g.entity), "%s not targetable" % id)
		assert_true(g.brain.state == EnemyBrain.AIState.HOLD, "%s holds (%s)" % [id, g.brain.state_name()])
		assert_false(g.brain.aware, "%s never aware" % id)
	for i in GUARDS.size():
		var g := d.spawned(GUARDS[i]) as EnemyActor
		if g == null:
			continue
		var marker := g.formation_marker()
		assert_true(marker != null and str(marker.get("marker_id")) == "valley.marker.guard_post_%d" % (i + 1),
			"%s holds valley.marker.guard_post_%d" % [GUARDS[i], i + 1])
		assert_true(_on_human_navmesh(g.global_position), "%s stands on the human navmesh" % GUARDS[i])
	assert_true((d.spawned(CAPTAIN) as EnemyActor).commander, "the captain commands")
	assert_true(d.spawned(ARCHER) is ArcherEnemy, "an archer on the tower")
	for id: String in VILLAGERS:
		var v := d.spawned(id) as Civilian
		assert_true(v != null, "%s spawned" % id)
		if v == null:
			continue
		assert_eq(v.entity.team, CombatEntity.Team.NEUTRAL, "%s neutral" % id)
		assert_eq(v.brain.state, CivilianBrain.State.IDLE, "%s idles in the square" % id)
		assert_true(_on_human_navmesh(v.global_position), "%s stands on the human navmesh" % id)
	var elder := d.spawned(ELDER) as Civilian
	assert_true(elder != null, "the elder spawned")
	if elder != null:
		var talker := elder.get_node_or_null("Talker") as NpcTalker
		assert_true(talker != null and talker.resolved_npc_id() == ELDER and talker.resolved_dialogue_id() == "dialogue.elder",
			"Elder Maren talks as %s with dialogue.elder" % ELDER)
		assert_true(_on_human_navmesh(elder.global_position), "the elder stands on the human navmesh")
	for b in GameSession.checkpoint_blockers():
		assert_false(str(b).begins_with("aware:"), "no village member defers a checkpoint (%s)" % b)
	assert_eq(d.active_combatant_count(), 6, "the six guards count toward the budget, the folk do not")


func test_standing_down_shelters_the_folk_and_hostility_arms_the_guards() -> void:
	var d := await _valley_at(VILLAGE_STAND)
	await step_ticks(30)
	var starts := {}
	for id: String in VILLAGERS:
		var v := d.spawned(id) as Civilian
		if v != null:
			starts[id] = v.global_position
	assert_eq(starts.size(), 6, "six villagers")
	WorldState.try_set_flag("faction.village.stood_down", true)
	var sheltered: bool = await TestWait.until(self, func() -> bool:
		for id: String in VILLAGERS:
			var v := d.spawned(id) as Civilian
			if v == null or not v.sheltered:
				return false
		return true, 900)
	assert_true(sheltered, "every villager reached a shelter")
	for id: String in VILLAGERS:
		var v := d.spawned(id) as Civilian
		if v == null:
			continue
		var m := v.safe_marker
		assert_true(m != null and str(m.get("marker_id")).begins_with("valley.marker.safe_house_"),
			"%s ran to a cottage door (%s)" % [id, m.get("marker_id") if m != null else "none"])
		assert_true(ValleyProbe.reaches(level, starts[id], v.brain.destination, ValleyProbe.HUMAN, 1.0),
			"%s's door is reachable on the human layer" % id)
		assert_eq(v.process_mode, Node.PROCESS_MODE_DISABLED, "%s stopped processing" % id)
	var elder := d.spawned(ELDER) as Civilian
	assert_true(elder != null and elder.brain.state == CivilianBrain.State.IDLE, "the elder stays to talk")
	for id: String in GUARDS:
		var g := d.spawned(id) as EnemyActor
		if g == null:
			continue
		assert_eq(g.brain.state, EnemyBrain.AIState.STAND_DOWN, "%s stands down" % id)
		assert_eq(g.entity.team, CombatEntity.Team.NEUTRAL, "%s stays neutral" % id)
		assert_false(g.is_guarding(), "%s lowers its guard" % id)
		assert_true(ValleyProbe.flat(g.global_position, g.formation_marker().global_position) < 1.0,
			"%s at its post" % id)
	# The village turns hostile after all (the barricade, or two blows): every guard is armed.
	WorldState.try_set_flag("faction.village.hostile", true)
	await step_ticks(3)
	for id: String in GUARDS + [CAPTAIN, ARCHER]:
		var g := d.spawned(id) as EnemyActor
		if g == null:
			continue
		assert_eq(g.entity.team, CombatEntity.Team.ENEMY, "%s fights" % id)
		assert_true(TargetingRules.player_may_target(g.entity), "%s is now a target" % id)


func test_the_hollow_sparring_post_swings_and_never_counts() -> void:
	var d := await _valley_at(Vector3(-115, 0.05, 155))
	assert_eq(d.encounter_state("encounter.hollow_sparring"), EncounterDirector.ACTIVE, "the Hollow's post is out")
	var post := d.spawned(POST) as SparringPost
	assert_true(post != null, "the sparring post spawned")
	if post == null:
		return
	assert_true(ValleyProbe.flat(post.global_position, Vector3(-108, 0, 165)) < 0.1, "at (-108, 165)")
	assert_true(_on_human_navmesh(post.global_position), "on the human navmesh")
	assert_eq(d.active_combatant_count(), 0, "it does not count toward the budget")
	assert_true(TargetingRules.player_may_target(post.entity) and post.entity.is_lockable(), "lockable")
	var p := level.player()
	var stand := post.global_position + Vector3(0, 0.05, -3.3)
	GameSession.place_player(p, Transform3D(Basis(Vector3.UP, PI), stand))
	var swung: bool = await TestWait.until(self, func() -> bool:
		return telegraphs.any(func(t: Array) -> bool: return t[1] == POST and t[4] == "circle" and t[3] == "player"), 90)
	assert_true(swung, "it swings at the giant beside it, behind a circle telegraph")
	await step_ticks(120)
	assert_false(post.brain.aware, "never aware")
	for b in GameSession.checkpoint_blockers():
		assert_false(str(b).begins_with("aware:"), "never a checkpoint blocker (%s)" % b)
	assert_true(post.entity.is_alive(), "still standing")
