extends IntegrationSuite
## P22 (plan M6-M9 §3.4 design 4; M5 FOLLOWUPS: Thornwick turned hostile on help paths when the
## return leg's fight at the barricade reached the guards behind it). Thornwick stays calm: guard
## posts 3 and 4 and the captain moved west, at least 22 m from the barricade's centre, and a guard
## at peace steps back 10 m from an enemy that comes within 12 m of it (FactionState's hook).
##
## The stage-3 return leg on a help path, with every AI on: the Ogre King has fallen, the bridge is
## open (faction.village.gate_open), the return patrol (encounter.return_patrol) holds the King's
## Bridge and the village's guards and folk are out. A stage-3 giant fights the patrol at the
## barricade - locked on the nearest enemy, it keeps it inside its light swing's reach (the Valley
## bot's reach band), never west of the square's edge, and swings - for at most FIGHT_S. No blow of the giant reaches a member of the village: no offence, the village stays
## neutral, every guard stays neutral.

const BARRICADE := Vector3(96, 0, -20)
const STAND := Vector3(90, 0.05, -20)
const PATROL := ["valley.ruins.patrol_1", "valley.ruins.patrol_captain", "valley.ruins.patrol_2",
	"valley.ruins.patrol_archer", "valley.ruins.patrol_mage"]
const GUARDS := ["valley.village.guard_1", "valley.village.guard_2", "valley.village.guard_3",
	"valley.village.guard_4", "valley.village.captain", "valley.village.tower_archer"]
const FIGHT_S := 30.0
## The giant fights at the barricade: it never steps west of this (the village square's east edge).
const WEST_LIMIT_X := 82.0
## Guard posts that moved (M6-M9 §3.4 design 4): at least this far from the barricade's centre.
const POST_CLEARANCE_M := 22.0

var level: LevelRoot


func before_each() -> void:
	await super()
	FactionState.reset_for_tests()


func after_each() -> void:
	if level != null and is_instance_valid(level):
		level.queue_free()
	level = null
	await super()


func _profile(stage: int) -> Dictionary:
	for rec: Dictionary in GameData.records_of_type("growth_profile"):
		if int(rec.get("stage", 0)) == stage:
			return rec
	return {}


## The nearest living patrol member (team ENEMY), or null.
func _nearest_enemy(d: EncounterDirector, from: Vector3) -> EnemyActor:
	var best: EnemyActor = null
	var best_d := INF
	for id: String in PATROL:
		var e := d.spawned(id) as EnemyActor
		if e == null or not is_instance_valid(e) or e.entity == null or not e.entity.is_alive() \
				or e.entity.team != CombatEntity.Team.ENEMY:
			continue
		var dist := ValleyProbe.flat(e.global_position, from)
		if dist < best_d:
			best_d = dist
			best = e
	return best


func test_the_return_patrol_fight_at_the_barricade_offends_no_one() -> void:
	GameSession.start_new_valley()
	WorldState.set_flag("world.ogre_king.defeated", true)
	WorldState.set_flag("faction.village.gate_open", true)
	level = ValleyProbe.instance(false)
	world.add_child(level)
	var p := level.player()
	GameSession.on_level_ready(level, p)
	p.router.use_injection = true
	p.set_profile(_profile(3))
	assert_true(await ValleyProbe.wait_for_navigation(self, level), "navigation ready")
	GameSession.place_player(p, Transform3D(Basis(Vector3.UP, -PI * 0.5), STAND))
	await step_ticks(1)
	var d := level.director()
	d.update_now()
	await step_ticks(2)
	assert_eq(d.encounter_state("encounter.return_patrol"), EncounterDirector.ACTIVE, "the return patrol holds the bridge")
	assert_eq(d.encounter_state("encounter.village_guards"), EncounterDirector.ACTIVE, "the guards are out")
	# The moved posts: every guard but the two at the west gate stands >= 22 m from the barricade.
	for id: String in ["valley.village.guard_3", "valley.village.guard_4", "valley.village.captain"]:
		var g := d.spawned(id) as EnemyActor
		assert_true(g != null and ValleyProbe.flat(g.home_position, BARRICADE) >= POST_CLEARANCE_M,
			"%s posted >= %.0f m from the barricade" % [id, POST_CLEARANCE_M])
	# The fight: the light swing's reach on a soldier at stage 3, as the Valley bot computes it.
	var bc := BotCombat.new()
	bc.player = p
	var band := bc.reach_band(GameData.get_action("ability.light_1"), 0.35, 1.8)
	assert_true(band != Vector2.ZERO, "the stage-3 light swing lands on a soldier somewhere (%s)" % band)
	if band == Vector2.ZERO:
		band = Vector2(3.0, 6.0)
	var hub := FactionState.hub()
	var giant_hits := 0
	var ticks := 0
	var swing_cooldown := 0
	var lock_wait := 0
	while ticks < int(FIGHT_S * 60.0):
		var t := _nearest_enemy(d, p.global_position)
		if t == null:
			break
		var to := t.global_position - p.global_position
		to.y = 0.0
		var yaw := TargetingRules.yaw_of(to)
		# Locked on (as a player would, and as the bot does): the swings aim at the target's body.
		var locked := p.locked_entity()
		if locked != t.entity and ticks >= lock_wait:
			if locked == null or not locked.is_alive():
				p.camera_rig.yaw = yaw
			p.router.inject_edge(&"lock_press")   # locks the target (or, locked elsewhere, toggles off)
			lock_wait = ticks + 8
		if locked == null:
			p.camera_rig.yaw = yaw
		var stick := Vector2.ZERO
		var dist := to.length()
		if dist > band.y - 0.3:
			stick = ValleyProbe.stick_toward(to, yaw)
			if p.global_position.x <= WEST_LIMIT_X and to.x < 0.0:
				stick = Vector2.ZERO   # never into the village: wait for it at the barricade
		elif dist < band.x + 0.3:
			stick = ValleyProbe.stick_toward(-to, yaw)   # too close for the swing: step back
		p.router.set_injected_move(stick)
		if dist >= band.x - 0.3 and dist <= band.y + 0.3 and swing_cooldown <= 0:
			p.router.inject_light_attack()
			swing_cooldown = 24
		swing_cooldown -= 1
		# The giant is kept alive: this test is about the village, not the patrol's damage.
		var hp := p.entity.combatant.pools
		hp.health = hp.health_max
		await step_ticks(1)
		ticks += 1
	p.router.set_injected_move(Vector2.ZERO)
	for r in hits:
		if r.event != null and r.event.attacker_id == "player" and PATROL.has(r.event.target_id):
			giant_hits += 1
	assert_true(giant_hits >= 3, "the giant fought the patrol (%d blows landed in %.1f s)" % [giant_hits, ticks / 60.0])
	var members: Array[String] = []
	for r in hits:
		if r.event == null or r.event.attacker_id != "player":
			continue
		var e := Sim.get_entity(r.event.target_id)
		if e != null and e.faction == "village":
			members.append(r.event.target_id)
	assert_eq(members, [] as Array[String], "no blow of the giant reached a member of the village")
	assert_eq(hub.history.size(), 0, "no offence (%s)" % [hub.history])
	assert_eq(FactionState.standing("village"), "neutral", "Thornwick stays neutral")
	assert_false(WorldState.get_flag("faction.village.warned") == true, "never warned")
	for id: String in GUARDS:
		var g := d.spawned(id) as EnemyActor
		assert_true(g != null and g.entity.team == CombatEntity.Team.NEUTRAL, "%s stays neutral" % id)
	print("    thornwick help path: %d blows on the patrol in %.1f s, %d step-backs %s" % [giant_hits,
		ticks / 60.0, hub.step_backs.size(), hub.step_backs])
