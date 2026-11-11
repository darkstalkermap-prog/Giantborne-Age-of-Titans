extends IntegrationSuite
## P32 (plan M6-M9 §2.10, §3.16 slow tests, §5.11; slow, runs with --slow): siege engines and cavalry in
## play, readable and fair for a stage 4-6 giant.
##   * The ballista's aim line runs from its muzzle and freezes at the aim lock: a giant that steps
##     aside afterwards is missed.
##   * The catapult's landing circle lies where the stone will land, stays on through the flight with
##     its timer filling, and the stone comes down inside it, striking the giant as an 8 m attacker.
##   * On the siege test level a battery of two catapults and two ballistae, six crews and a shield
##     wall with its banner (encounter.siege_test_battery: the director's engines list hands each
##     engine its crew) against a stage-6 giant: every engine fires, its launches at the giant at least
##     1 s apart; the giant kills a ballista's crew, seizes the ballista and throws it at a catapult,
##     where it smashes and its splash strikes the catapult; a staggered catapult is seized from its
##     crew and thrown too; a broken engine's crew runs, and two engines falling within 2 s cost a
##     unit nearby 20 morale once.
##   * The cavalry pair (encounter.siege_test_cavalry) charges a stage-5 giant, wheels away 30-50 m and
##     charges again, each rider's wheel point found on the large navmesh.
##   * Every stage 4-6 moveset lands each of its blows on a ballista, a catapult and a cavalry rider
##     standing straight ahead, from contact + 0.3 m to 0.9 x the stage's melee reach (P31's reach
##     bands, for the new targets).

const LEVEL := "res://scenes/test/siege_test.tscn"
const BATTERY := "encounter.siege_test_battery"
const CAVALRY_ENC := "encounter.siege_test_cavalry"
const BALLISTA := "res://scenes/world/siege_ballista.tscn"
const CATAPULT := "res://scenes/world/siege_catapult.tscn"
const CREW := "res://scenes/enemies/siege_crew.tscn"
const CAVALRY := "res://scenes/enemies/cavalry.tscn"
const BOLT := "ability.ballista_bolt"
const STONE := "ability.catapult_stone"
const THROW := "ability.throw_engine"
const CHARGE := "ability.cavalry_charge"

var fired: Array = []      ## [tick, engine id, target id]
var launches: Array = []   ## [tick, owner id, visual]
var impacts: Array = []    ## [tick, projectile id, point]


func before_each() -> void:
	await super()
	fired.clear()
	launches.clear()
	impacts.clear()
	Events.siege_engine_fired.connect(_on_fired)
	Events.projectile_spawned.connect(_on_launch)
	Events.projectile_impact.connect(_on_impact)


func after_each() -> void:
	for sig: Signal in [Events.siege_engine_fired, Events.projectile_spawned, Events.projectile_impact]:
		for c: Dictionary in sig.get_connections():
			if (c.callable as Callable).get_object() == self:
				sig.disconnect(c.callable)
	await super()


func _on_fired(tick: int, engine_id: String, _action_id: String, target_id: String) -> void:
	fired.append([tick, engine_id, target_id])


func _on_launch(tick: int, id: int, owner_id: String, _action_id: String, _pos: Vector3, _vel: Vector3, visual: String) -> void:
	launches.append([tick, owner_id, visual, id])


func _on_impact(tick: int, projectile_id: int, point: Vector3, _hit: String) -> void:
	impacts.append([tick, projectile_id, point])


# --------------------------------------------------------------------------- helpers

static func _profile(stage: int) -> Dictionary:
	for rec: Dictionary in GameData.records_of_type("growth_profile"):
		if int(rec.get("stage", 0)) == stage:
			return rec
	return {}


## Quick engines: reload `reload_s`, windups `windup_s` (the shipped tracking fractions).
static func _quick(reload_s: float, windup_s: float) -> void:
	for id: String in ["prop.siege_ballista", "prop.siege_catapult"]:
		TestFixtures.record_override(id, {"engine": {"reload_s": reload_s}})
	for id: String in [BOLT, STONE]:
		TestFixtures.record_override(id, {"windup_s": windup_s, "recovery_s": 0.05})


## An engine of `scene` at `pos` facing the origin.
func _engine(scene: String, world_id: String, pos: Vector3) -> SiegeEngine:
	var e := (load(scene) as PackedScene).instantiate() as SiegeEngine
	e.world_id = world_id
	e.position = pos
	e.rotation.y = TargetingRules.yaw_of(Vector3(-pos.x, 0.0, -pos.z))
	world.add_child(e)
	return e


## A crew member (AI off) at `engine`'s crew place, taken into its crew.
func _crew(engine: SiegeEngine, id: String) -> EnemyActor:
	var c := TestSpawn.enemy(world, CREW, engine.global_position + Vector3(0, 0.05, 0), id, false, engine.rotation.y)
	engine.add_crew(c)
	c.global_position = engine.crew_slot(c) + Vector3(0, 0.05, 0)
	return c


static func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


func _from(target_id: String, action_id: String) -> Array[HitResult]:
	var out: Array[HitResult] = []
	for r in hits_on(target_id):
		if r.event.action_id == action_id:
			out.append(r)
	return out


# --------------------------------------------------------------------------- telegraphs

func test_the_ballistas_aim_line_freezes_at_the_lock_and_a_step_aside_dodges_the_bolt() -> void:
	_quick(0.1, 0.3)
	var tv := TelegraphVisuals.new()
	world.add_child(tv)
	var p := spawn_player(Vector3(0, 0.05, 0))
	p.entity.combatant.unkillable = true
	var b := _engine(BALLISTA, "test.p32_ballista_t", Vector3(0, 0, -30))
	_crew(b, "test.p32_crew_t")
	var drawing: bool = await TestWait.until(self, func() -> bool: return not tv.telegraph_for("test.p32_ballista_t").is_empty(), 30)
	assert_true(drawing, "the ballista's windup is telegraphed")
	var t := tv.telegraph_for("test.p32_ballista_t")
	assert_true(bool(t.get("aim_line", false)), "as an aim line")
	if not t.is_empty():
		assert_true((t.start as Vector3).distance_to(b.launch_point_global()) < 0.05, "from its muzzle")
	var lock_at := EnemyActor.aim_lock_tick(GameData.get_action(BOLT))
	await TestWait.until(self, func() -> bool: return b.aim_locked(), lock_at + 4)
	assert_true(b.aim_locked(), "the aim locks at %d ticks of the windup" % lock_at)
	var locked := b.current_aim_point()
	assert_true(locked.distance_to(p.entity.anchor_position()) < 0.5, "on the giant")
	p.global_position += Vector3(9.0, 0.0, 0.0)   # a step aside after the lock
	await step_ticks(2)
	t = tv.telegraph_for("test.p32_ballista_t")
	if not t.is_empty():
		assert_true((t.end as Vector3).distance_to(locked) < 0.05, "the line stays where it locked")
	var hits_before := hits_on(p.entity.entity_id).size()
	await TestWait.until(self, func() -> bool: return launches.size() >= 1, 20)
	assert_eq(launches.size(), 1, "the bolt flies")
	await step_ticks(34)   # 30 m at 60 m/s, and a little
	assert_eq(hits_on(p.entity.entity_id).size(), hits_before, "to the locked point: the giant that stepped aside is missed")


func test_the_catapults_landing_circle_holds_through_the_flight_and_the_stone_lands_in_it() -> void:
	_quick(0.5, 0.6)
	var tv := TelegraphVisuals.new()
	world.add_child(tv)
	var p := spawn_player(Vector3(0, 0.05, 0))
	p.set_profile(_profile(5))
	p.entity.combatant.unkillable = true
	var c := _engine(CATAPULT, "test.p32_catapult_t", Vector3(0, 0, -52))
	_crew(c, "test.p32_hauler_t")
	var drawing: bool = await TestWait.until(self, func() -> bool: return not tv.telegraph_for("test.p32_catapult_t").is_empty(), 40)
	assert_true(drawing, "the catapult's windup is telegraphed")
	var t := tv.telegraph_for("test.p32_catapult_t")
	assert_eq(str(t.get("shape", "")), "circle", "as a circle")
	var launched: bool = await TestWait.until(self, func() -> bool: return launches.size() >= 1, 60)
	assert_true(launched, "the stone is launched")
	if not launched:
		return
	await step_ticks(1)
	var circle := tv.landing_for("test.p32_catapult_t")
	assert_false(circle.is_empty(), "the landing circle stays on once the stone flies")
	if circle.is_empty():
		return
	var centre: Vector3 = circle.point
	assert_true(_flat(centre, p.global_position) < 1.0, "it lies where the giant stood when the aim locked")
	assert_true(float(circle.flight_s) > 0.5, "a flight of %.2f s to read it" % float(circle.flight_s))
	var timer := float(circle.timer)
	var steady := true
	var samples := 0
	while impacts.is_empty() and samples < 240:
		await step_ticks(3)
		samples += 1
		var now := tv.landing_for("test.p32_catapult_t")
		if impacts.is_empty():
			if now.is_empty() or float(now.timer) + 1e-6 < timer:
				steady = false
			else:
				timer = float(now.timer)
	assert_true(steady, "through the whole flight, its timer filling")
	assert_false(impacts.is_empty(), "the stone comes down")
	if impacts.is_empty():
		return
	var at: Vector3 = impacts[0][2]
	assert_true(_flat(at, centre) <= float(circle.radius), "inside the circle (%.2f m from its centre, radius %.1f)" % [
		_flat(at, centre), float(circle.radius)])
	await step_ticks(1)
	assert_true(tv.landing_for("test.p32_catapult_t").is_empty(), "and the circle goes when it lands")
	var on := _from(p.entity.entity_id, STONE)
	assert_eq(on.size(), 1, "the stone strikes the giant who stood still")
	if on.size() == 1:
		assert_near(on[0].event.attacker_height_m, 8.0, 1e-4, "as an 8 m attacker")


# --------------------------------------------------------------------------- the battery

func test_a_battery_and_a_shield_wall_against_a_stage_6_giant_that_throws_their_engines() -> void:
	var lv := (load(LEVEL) as PackedScene).instantiate() as LevelRoot
	world.add_child(lv)
	await step_ticks(2)
	var p := lv.player()
	p.set_profile(_profile(6))
	p.entity.apply_status(StressScenario.STATUS_INVULNERABLE, NAN, -1.0, "test")
	p.global_position = Vector3(0, 0.05, 30)
	p.velocity = Vector3.ZERO
	var d := lv.director()
	d.force_activate(BATTERY)
	d.update_now()
	await step_ticks(2)
	var ids := ["test.siege.catapult_1", "test.siege.ballista_1", "test.siege.ballista_2", "test.siege.catapult_2"]
	var engines := {}
	for id: String in ids:
		engines[id] = d.p32_engine(id)
		assert_true(engines[id] != null, "%s stands" % id)
	assert_eq(d.p32_engine_of(BATTERY, "test.siege.crew_1"), "test.siege.catapult_1", "the engines list hands out crews")
	var all_crewed: bool = await TestWait.until(self, func() -> bool:
		for e: SiegeEngine in engines.values():
			if e == null or not e.crewed:
				return false
		return true, 240)
	assert_true(all_crewed, "every engine's crew stands by it")
	# The battery opens up: every engine fires, the launches at the giant a second apart.
	var all_fired: bool = await TestWait.until(self, func() -> bool:
		var by := {}
		for f: Array in fired:
			by[str(f[1])] = true
		return by.size() == 4, 900)
	var by_engine := {}
	for f: Array in fired:
		by_engine[str(f[1])] = int(by_engine.get(str(f[1]), 0)) + 1
	assert_true(all_fired, "every engine fires (%s)" % [by_engine])
	var gap := ActionDef.seconds_to_ticks(1.0)
	var at_giant: Array = []
	for l: Array in launches:
		if str(l[1]) in ids:
			at_giant.append(int(l[0]))
	for i in range(1, at_giant.size()):
		assert_true(int(at_giant[i]) - int(at_giant[i - 1]) >= gap,
			"engine launches at the giant stay a second apart (%d ticks)" % (int(at_giant[i]) - int(at_giant[i - 1])))
	print("    test_siege_battery: %d engine launches at the giant, by engine %s" % [at_giant.size(), by_engine])
	# The giant kills the east ballista's crew, seizes it and hurls it at the east catapult.
	var b2: SiegeEngine = engines["test.siege.ballista_2"]
	var c2: SiegeEngine = engines["test.siege.catapult_2"]
	p.global_position = b2.global_position + Vector3(0, 0.05, 10.0)
	p.facing_yaw = 0.0
	p.camera_rig.yaw = 0.0
	await step_ticks(2)
	assert_eq(p.grab.check_target(b2.entity), "engine_crewed", "its crew holds it")
	for crew: EnemyActor in b2.crew():
		queue_hit(p.entity.entity_id, crew.entity.entity_id, p.global_position, 1.0e6)
	var unmanned: bool = await TestWait.until(self, func() -> bool: return not b2.crewed, 30)
	assert_true(unmanned, "its crew dead, the ballista stands uncrewed")
	var c2_crew: Array = c2.crew()
	var morale_before := {}
	for m: EnemyActor in c2_crew:
		morale_before[m.entity_id] = m.brain.morale
	var thrown := await _seize_and_throw(p, b2, c2)
	assert_true(thrown, "the ballista is seized and thrown")
	var smashed: bool = await TestWait.until(self, func() -> bool: return b2.destroyed, 180)
	assert_true(smashed, "it smashes where it comes down")
	await step_ticks(1)
	assert_true(_flat(b2.global_position, c2.global_position) < 6.0, "by the catapult it was thrown at (%.1f m)" % _flat(b2.global_position, c2.global_position))
	assert_eq(_from(c2.entity.entity_id, THROW).size(), 1, "its splash strikes the catapult")
	for m: EnemyActor in c2_crew:
		if is_instance_valid(m) and m.entity.is_alive():
			assert_true(m.brain.morale <= float(morale_before[m.entity_id]) - 20.0 + 1e-3,
				"%s, 20 m off, loses 20 morale" % m.entity_id)
	# The west catapult, staggered from its crew, is seized and thrown at the west ballista.
	var c1: SiegeEngine = engines["test.siege.catapult_1"]
	var b1: SiegeEngine = engines["test.siege.ballista_1"]
	var c1_crew: Array = c1.crew()
	assert_eq(c1_crew.size(), 2, "two men crew the catapult")
	await TestWait.until(self, func() -> bool:
		return p.controller.state == CombatController.State.LOCOMOTION and p.controller.action == null, 90)
	p.global_position = c1.global_position + Vector3(0, 0.05, 11.0)
	await step_ticks(2)
	c1.entity.stagger(3.0, "test")
	var thrown_2 := await _seize_and_throw(p, c1, b1)
	assert_true(thrown_2, "the staggered catapult is seized from its crew and thrown")
	for m: EnemyActor in c1_crew:
		assert_eq(m.brain.state, EnemyBrain.AIState.ROUTED, "%s runs (%s)" % [m.entity_id, m.brain.state_name()])
	var smashed_2: bool = await TestWait.until(self, func() -> bool: return c1.destroyed, 180)
	assert_true(smashed_2, "the catapult smashes too")
	print("    test_siege_battery: thrown %s and %s; destroyed %s" % [b2.world_id, c1.world_id, destroyed])


## Seizes `engine` (uncrewed or staggered) and throws it at `at` (the lock on it). True once it flies.
func _seize_and_throw(p: GiantPlayer, engine: SiegeEngine, at: SiegeEngine) -> bool:
	p.entity.combatant.pools.stamina = p.entity.combatant.pools.stamina_max
	assert_eq(p.grab.check_target(engine.entity), "", "%s may be seized" % engine.world_id)
	if p.grab.try_grab() != CombatController.Verdict.ACCEPT:
		return false
	var held: bool = await TestWait.until(self, func() -> bool: return p.grab.is_holding(), 40)
	if not held:
		return false
	await TestWait.until(self, func() -> bool:
		return p.controller.state == CombatController.State.LOCOMOTION and p.controller.action == null, 60)
	p.lock.target_id = at.entity.entity_id
	p.router.inject_light_attack()
	return await TestWait.until(self, func() -> bool: return not p.grab.is_holding(), 60)


# --------------------------------------------------------------------------- cavalry

func test_the_cavalry_pair_charges_wheels_away_and_charges_again() -> void:
	var lv := (load(LEVEL) as PackedScene).instantiate() as LevelRoot
	world.add_child(lv)
	await step_ticks(2)
	var p := lv.player()
	p.set_profile(_profile(5))
	p.entity.apply_status(StressScenario.STATUS_INVULNERABLE, NAN, -1.0, "test")
	p.global_position = Vector3(120, 0.05, 40)
	p.velocity = Vector3.ZERO
	var d := lv.director()
	d.force_activate(CAVALRY_ENC)
	d.update_now()
	await step_ticks(2)
	var riders: Array[CavalryEnemy] = []
	for id: String in ["test.siege.cavalry_1", "test.siege.cavalry_2"]:
		var e := Sim.get_entity(id)
		assert_true(e != null and e.actor is CavalryEnemy, "%s rides" % id)
		if e != null and e.actor is CavalryEnemy:
			riders.append(e.actor as CavalryEnemy)
	var wheel_points := {}
	var runs := {}         # charge runs completed, by rider
	var galloping := {}
	var q0 := NavQuery.queries_total
	var start := Sim.tick
	var done := false
	while Sim.tick - start < 1500 and not done:
		await step_ticks(2)
		done = true
		for r in riders:
			var b := r.cavalry_brain()
			var seen: Array = wheel_points.get(r.entity_id, [])
			if b.wheel_point != Vector3.INF and b.cycle == "wheel" and not seen.has(b.wheel_point):
				wheel_points[r.entity_id] = seen + [b.wheel_point]
			var g := r.is_galloping()
			if bool(galloping.get(r.entity_id, false)) and not g:
				runs[r.entity_id] = int(runs.get(r.entity_id, 0)) + 1
			galloping[r.entity_id] = g
			if int(runs.get(r.entity_id, 0)) < 2 or b.wheels < 1:
				done = false
	var charge_hits := _from(p.entity.entity_id, CHARGE)
	for r in riders:
		var b := r.cavalry_brain()
		assert_true(int(runs.get(r.entity_id, 0)) >= 2 and b.wheels >= 1, "%s charged %d times and wheeled %d times" % [
			r.entity_id, int(runs.get(r.entity_id, 0)), b.wheels])
		for wp: Vector3 in wheel_points.get(r.entity_id, []):
			var away := _flat(wp, p.global_position)
			assert_true(away >= 25.0 and away <= 55.0, "%s wheels 30-50 m off the giant (%.1f m)" % [r.entity_id, away])
		var mine := charge_hits.filter(func(h: HitResult) -> bool: return h.event.attacker_id == r.entity_id)
		assert_eq(mine.size(), int(runs.get(r.entity_id, 0)), "each of %s's charges strikes the giant's legs once" % r.entity_id)
	assert_true(NavQuery.queries_total > q0, "the wheel points were searched on the navmesh (%d path queries)" % (NavQuery.queries_total - q0))
	assert_true(_flat(p.global_position, Vector3(120, 0, 40)) < 1.0, "and the giant is not shoved along their lines")
	print("    test_siege_battery: the riders charged %s times in %.1f s; %d charge hits" % [
		runs.values(), float(Sim.tick - start) / Sim.TICK_RATE, charge_hits.size()])


# --------------------------------------------------------------------------- reach on engines and riders

## The stage 4-6 weapons with a moveset of their own (the titanforged forms swing their base's).
const WEAPONS := ["weapon.club_reinforced", "weapon.sword_reinforced", "weapon.hammer_reinforced", "weapon.axe",
	"weapon.tree_pine", "weapon.fists"]
## The giant's recovery while it swings here (the hits all land in the windup and the active phase).
const FAST_RECOVERY := 0.05


## The strikes of `weapon_id`'s moveset at `stage`: its light chain through chain_next, then the heavy;
## a grab (the fists' third light) is no strike.
static func strikes_of(weapon_id: String, stage: int) -> Array:
	var m := PlayerEquipment.moveset_for(GameData.get_record(weapon_id), stage)
	var out: Array = []
	var id := str(m.light_chain)
	var seen := {}
	while id != "" and not seen.has(id) and seen.size() < 4:
		seen[id] = true
		var a := GameData.get_action(id)
		if a != null and a.hit_shape != "grab":
			out.append(id)
		id = str(a.param("chain_next", "")) if a != null else ""
	out.append(str(m.heavy))
	return out


## One swing of `attack_id` straight ahead at `target` (its entity `e`) put back `d` m in front of the
## giant and turned to face it: how many hits landed on it.
func _swing_at_target(p: GiantPlayer, attack_id: String, target: Node3D, e: CombatEntity, d: float) -> int:
	e.combatant.pools.health = e.combatant.pools.health_max
	e.combatant.poise.value = 0.0
	target.global_position = Vector3(0, target.global_position.y if target is SiegeEngine else 0.05, -d)
	target.rotation.y = PI
	if "facing_yaw" in target:
		target.set("facing_yaw", PI)
	var actor := target as EnemyActor
	if actor != null:
		actor.velocity = Vector3.ZERO
		actor.knockback_velocity = Vector3.ZERO
		actor.move_velocity = Vector3.ZERO
	p.global_position = Vector3(0, p.global_position.y, 0)
	p.velocity = Vector3.ZERO
	p.move_velocity = Vector3.ZERO
	p.camera_rig.yaw = 0.0
	p.facing_yaw = 0.0
	p.entity.combatant.pools.stamina = p.entity.combatant.pools.stamina_max
	p.controller.recovery_scale = FAST_RECOVERY
	await step_ticks(2)
	var before := _from(e.entity_id, attack_id).size()
	var a := GameData.get_action(attack_id)
	if p.controller.request(&"attack", {"action_id": attack_id}) != CombatController.Verdict.ACCEPT:
		return -1
	await step_ticks(a.windup_ticks + a.active_ticks + 2)
	var landed := _from(e.entity_id, attack_id).size() - before
	await TestWait.until(self, func() -> bool: return p.controller.state == CombatController.State.LOCOMOTION, 90)
	return landed


func test_every_stage_4_to_6_moveset_lands_on_engines_and_riders() -> void:
	add_box(Vector3(160, 1, 160), Vector3(0, -0.5, 0))
	var p := spawn_player(Vector3(0, 0.05, 0))
	await TestWait.until(self, func() -> bool: return p.is_on_floor(), 30)
	p.entity.combatant.unkillable = true
	var ballista := _engine(BALLISTA, "test.p32_reach_ballista", Vector3(-20, 0, 50))
	var catapult := _engine(CATAPULT, "test.p32_reach_catapult", Vector3(20, 0, 50))
	var rider := TestSpawn.enemy(world, CAVALRY, Vector3(0, 0.05, 50), "test.p32_reach_rider", false, 0.0)
	# [node, entity, half-depth toward the giant (its hurtbox's, or the rider's capsule radius), parked at]
	var targets := [[ballista, ballista.entity, 2.0, Vector3(-20, 0, 50)], [catapult, catapult.entity, 2.3, Vector3(20, 0, 50)],
		[rider, rider.entity, float(rider.record.capsule_radius_m), Vector3(0, 0.05, 50)]]
	for t: Array in targets:
		(t[1] as CombatEntity).combatant.unkillable = true
	await step_ticks(2)
	var swings := 0
	var misses: Array = []
	for stage: int in [4, 5, 6]:
		assert_true(bool(p.growth.debug_set_stage(stage).ok), "stage %d" % stage)
		await step_ticks(2)
		var reach := float(p.profile.melee_reach_m)
		for weapon_id: String in WEAPONS:
			var r: Dictionary = p.equipment.grant_weapon(weapon_id, true)
			assert_true(bool(r.get("ok", false)), "stage %d: %s equipped (%s)" % [stage, weapon_id, r.get("message", "")])
			await step_ticks(1)
			var strikes := strikes_of(weapon_id, stage)
			for t: Array in targets:
				for other: Array in targets:
					if other != t:
						(other[0] as Node3D).global_position = other[3]   # behind the giant: never the swing's target
				var contact := float(p.profile.capsule_radius_m) + float(t[2])
				for d: float in [contact + 0.3, 0.9 * reach]:
					for attack_id: String in strikes:
						swings += 1
						var landed: int = await _swing_at_target(p, attack_id, t[0], t[1], d)
						if landed != 1:
							misses.append("stage %d %s %s on %s at %.2f m: %d" % [stage, weapon_id, attack_id,
								(t[1] as CombatEntity).entity_id, d, landed])
	assert_eq(misses, [], "every blow lands once (%d of %d missed)" % [misses.size(), swings])
	print("    test_siege_battery: %d swings at engines and riders, %d missed" % [swings, misses.size()])
	for m: String in misses.slice(0, 30):
		print("      miss: " + m)
