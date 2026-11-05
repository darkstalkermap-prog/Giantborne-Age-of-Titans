extends IntegrationSuite
## The archer (plan §3.9, §4.4, decisions 24 and 25) through real scenes and ticks: its scene, it
## settles in its 12-20 m band and on an elevation marker before a cover marker, the outmatched
## 15.6-26 m band held for 10 s without falling back to ALERT, staggered launches and the ranged
## token pool, arrows blocked by the guard, evaded by dodge invulnerability and stopped by walls,
## committed aim (a 4 m sidestep after the aim lock dodges the arrow; standing still does not),
## its kick, and a throw and Boulder Hurl interrupting its draw. The ranged test level's climb is
## a slow suite (tests/slow/test_ranged_level.gd).

const ARCHER := "res://scenes/enemies/archer.tscn"
const MAGE := "res://scenes/enemies/mage.tscn"
const SHOT := "ability.archer_shot"

var spawned: Array = []
var impacts: Array = []


func before_each() -> void:
	await super()
	spawned.clear()
	impacts.clear()
	Events.projectile_spawned.connect(_on_spawned)
	Events.projectile_impact.connect(_on_impact)


func after_each() -> void:
	for sig: Signal in [Events.projectile_spawned, Events.projectile_impact]:
		for c: Dictionary in sig.get_connections():
			if (c.callable as Callable).get_object() == self:
				sig.disconnect(c.callable)
	for n in get_tree().get_nodes_in_group(ProjectileSystem.GROUP):
		n.queue_free()
	await super()


func _on_spawned(t: int, id: int, owner_id: String, action_id: String, pos: Vector3, vel: Vector3, _visual: String) -> void:
	spawned.append({"tick": t, "id": id, "owner": owner_id, "action": action_id, "position": pos, "velocity": vel})


func _on_impact(t: int, id: int, pos: Vector3, hit: String) -> void:
	impacts.append({"tick": t, "id": id, "position": pos, "hit": hit})


func _archer(pos: Vector3, id: String, ai := false, yaw := PI) -> ArcherEnemy:
	return TestSpawn.enemy(world, ARCHER, pos, id, ai, yaw) as ArcherEnemy


func _player(pos := Vector3(0, 0.05, 0), yaw := 0.0) -> GiantPlayer:
	var p := spawn_player(pos, yaw)
	p.entity.combatant.unkillable = true
	return p


static func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


## Starts the archer's shot at the player by hand (its AI off).
func _draw(a: ArcherEnemy) -> void:
	a.brain.target_id = "player"
	a.controller.request(&"attack", {"action_id": SHOT})


func _launches_by(owner_id: String) -> Array:
	return spawned.filter(func(s: Dictionary) -> bool: return s.owner == owner_id)


# --------------------------------------------------------------------------- scene

func test_archer_scene_and_classes() -> void:
	var p := _player()
	var a := _archer(Vector3(0, 0.05, -3), "test.archer_a")
	await step_ticks(2)
	assert_true(a is ArcherEnemy and a is EnemyActor, "ArcherEnemy extends EnemyActor")
	assert_true(a.brain is ArcherBrain, "with an ArcherBrain")
	assert_true(a.rig is ActorRig, "and an ActorRig")
	for path in ["CombatEntity", "NavAgent", "BodyShape", "Visual/Body", "Visual/LodProxy", "Anchors/Torso",
			"Anchors/Grab", "Hurtboxes/Head", "Hurtboxes/Torso", "Hurtboxes/Legs"]:
		assert_true(a.get_node_or_null(path) != null, "has %s" % path)
	assert_false((a.get_node("Visual/LodProxy") as Node3D).visible, "the LOD proxy is hidden")
	assert_true(a.is_in_group("ranged_enemies") and a.is_in_group("enemies"), "groups enemies and ranged_enemies")
	assert_eq(a.collision_mask, SceneKit.ACTOR_MASK, "collides with the blockers layer")
	assert_eq(a.agent.navigation_layers, 1, "human nav layer")
	assert_eq(a.entity.team, CombatEntity.Team.ENEMY, "hostile")
	assert_eq(a.grab_attach(), "torso_fist", "held by the torso")
	assert_eq(p.grab.check_target(a.entity), "not_staggered", "grabbable once its poise breaks")
	a.entity.stagger(2.0, "test")
	assert_eq(p.grab.check_target(a.entity), "", "a staggered archer can be grabbed (pressure or throw)")
	assert_eq(a.current_aim_point(), Vector3.INF, "no aim point without a drawn shot")


# --------------------------------------------------------------------------- positioning

## It settles in its 12-20 m band from too far and from too close, and shoots from there.
func test_archer_settles_in_the_band() -> void:
	var p := _player()
	var far := _archer(Vector3(-10, 0.05, -28), "test.archer_far", true)
	var near := _archer(Vector3(10, 0.05, -6), "test.archer_near", true)
	far.rotation.y = yaw_towards(far.position, Vector3.ZERO)
	near.rotation.y = yaw_towards(near.position, Vector3.ZERO)
	await TestWait.until(self, func() -> bool:
		return _launches_by(far.entity_id).size() >= 1 and _launches_by(near.entity_id).size() >= 1, 420)
	for a: ArcherEnemy in [far, near]:
		var d := _flat(a.global_position, p.global_position)
		assert_true(d >= 12.0 and d <= 20.0, "%s settled in the band (%.1f m)" % [a.entity_id, d])
		assert_true(a.brain.is_settled(a.global_position), "%s at its firing point" % a.entity_id)
		assert_true(_launches_by(a.entity_id).size() >= 1, "%s shoots from there" % a.entity_id)
	assert_true(_flat(far.global_position, near.global_position) >= 6.0, "the two keep their 6 m spread")


## An elevation marker in the band is taken before a nearer cover marker; a second archer takes the
## cover marker (the claimed one is not shared).
func test_archer_takes_the_elevation_marker_first() -> void:
	var p := _player()
	var high := Marker3D.new()
	high.position = Vector3(10, 0.05, -14)
	high.add_to_group(EnemyActor.ELEVATION_GROUP)
	world.add_child(high)
	var cover := Marker3D.new()
	cover.position = Vector3(-4, 0.05, -18)
	cover.add_to_group(EnemyActor.COVER_GROUP)
	world.add_child(cover)
	var a := _archer(Vector3(0, 0.05, -24), "test.archer_1", true)
	await step_ticks(2)
	var b := _archer(Vector3(-2, 0.05, -27), "test.archer_2", true)
	# Whichever decides first takes the elevation marker; the other the cover marker.
	var on_marker := func(e: ArcherEnemy, m: Node3D) -> bool:
		return e.firing_marker() == m and _flat(e.global_position, m.global_position) < EnemyBrain.FIRING_SETTLE_M
	var ok: bool = await TestWait.until(self, func() -> bool:
		return (on_marker.call(a, high) and on_marker.call(b, cover)) or (on_marker.call(b, high) and on_marker.call(a, cover)), 480)
	assert_true(ok, "one archer on the elevation marker, the other at the cover marker (%s, %s)" % [
		a.global_position, b.global_position])
	var holder := str(high.get_meta(EnemyActor.FIRING_POINT_META, ""))
	assert_true(holder in ["test.archer_1", "test.archer_2"], "the elevation marker is claimed (%s)" % holder)
	assert_true(str(cover.get_meta(EnemyActor.FIRING_POINT_META, "")) not in ["", holder], "the cover marker by the other")
	assert_true(p != null, "player present")


## Plan §3.9: an outmatched archer (a stage-2 giant) holds its 15.6-26 m band for 10 s without
## falling back to ALERT (its 32 m sight covers the top of the band).
func test_outmatched_archer_holds_its_band_for_10_s() -> void:
	var p := _player()
	p.set_profile(GameData.get_record("growth.02"))
	var a := _archer(Vector3(3, 0.05, -24.5), "test.archer_out", true)
	a.rotation.y = yaw_towards(a.position, Vector3.ZERO)
	var engaged: bool = await TestWait.until(self, func() -> bool:
		return a.brain.state in [EnemyBrain.AIState.APPROACH, EnemyBrain.AIState.ATTACK, EnemyBrain.AIState.RECOVER], 90)
	assert_true(engaged, "it engaged")
	assert_true(a.brain.is_outmatched(), "outmatched by the stage-2 giant")
	var lo := INF
	var hi := 0.0
	var alerts := 0
	for i in 600:
		await step_ticks(1)
		var d := _flat(a.global_position, p.global_position)
		lo = minf(lo, d)
		hi = maxf(hi, d)
		if a.brain.state == EnemyBrain.AIState.ALERT or not a.brain.aware:
			alerts += 1
	assert_true(lo >= 15.6 and hi <= 26.0, "it stayed in 15.6-26 m (%.1f-%.1f m)" % [lo, hi])
	assert_eq(alerts, 0, "never back to ALERT, never unaware")
	assert_true(_launches_by("test.archer_out").size() >= 2, "it kept shooting")


# --------------------------------------------------------------------------- staggered launches

## Spec 10 / decision 25: two archers never launch at one target within 1.0 s (launch slots,
## also with a mage's longer windup in the mix), and of three ranged enemies on one target at most
## two hold ranged tokens.
func test_launch_slots_and_the_ranged_token_pool() -> void:
	var p := _player()
	var ranged: Array[EnemyActor] = []
	for spec: Array in [[Vector3(-12, 0.05, -10), "test.archer_l"], [Vector3(12, 0.05, -10), "test.archer_r"]]:
		ranged.append(_archer(spec[0], spec[1], true, yaw_towards(spec[0], Vector3.ZERO)))
	var m := TestSpawn.enemy(world, MAGE, Vector3(0, 0.05, -13), "test.mage_c", true, PI)
	ranged.append(m)
	var most := 0
	for i in 360:
		await step_ticks(1)
		most = maxi(most, Sim.token_holders(EnemyActor.ranged_token_key("player")).size())
	var at_player := spawned.filter(func(s: Dictionary) -> bool: return s.owner.begins_with("test."))
	var ticks: Array = at_player.map(func(s: Dictionary) -> int: return int(s.tick))
	ticks.sort()
	assert_true(ticks.size() >= 4, "they launch (%d)" % ticks.size())
	var min_gap := 100000
	for i in range(1, ticks.size()):
		min_gap = mini(min_gap, int(ticks[i]) - int(ticks[i - 1]))
	assert_true(min_gap >= 60, "launches at least 1.0 s apart (closest %d ticks)" % min_gap)
	var archer_ticks: Array = at_player.filter(func(s: Dictionary) -> bool: return s.action == SHOT).map(
		func(s: Dictionary) -> int: return int(s.tick))
	var owners := {}
	for s: Dictionary in at_player:
		owners[s.owner] = true
	assert_true(owners.has("test.archer_l") and owners.has("test.archer_r"), "both archers shot")
	assert_true(archer_ticks.size() >= 2, "archer launches seen (%d)" % archer_ticks.size())
	assert_true(most <= EnemyActor.MAX_RANGED_HOLDERS, "never more than two ranged tokens held (most %d)" % most)
	assert_eq(most, 2, "and the pool is used")
	assert_eq(ranged[0].launch_gap_ticks(SHOT), 66, "an archer's slot gap: 60 ticks + the 6 its draw is shorter")
	assert_eq(m.launch_gap_ticks("ability.mage_slow_bolt"), 60, "the mage's: 60")
	assert_true(p != null, "player present")


# --------------------------------------------------------------------------- arrows

func test_arrows_are_blocked_by_the_guard() -> void:
	var p := _player()
	var a := _archer(Vector3(0, 0.05, -14), "test.archer_g")
	await step_ticks(2)
	p.router.set_injected_hold(&"block", true)
	p.router.inject_edge(&"block_press")
	_draw(a)
	var ok: bool = await TestWait.until(self, func() -> bool: return hits_on("player").size() == 1, 120)
	assert_true(ok, "the arrow reached the giant")
	var on := hits_on("player")
	if on.size() == 1:
		assert_eq(on[0].event.action_id, SHOT, "the archer's shot")
		assert_true(on[0].event.from_projectile, "a projectile hit")
		assert_eq(on[0].outcome, HitResult.Outcome.BLOCKED, "blocked by the guard (never parried: no Melee tag)")
	p.router.set_injected_hold(&"block", false)
	p.router.inject_edge(&"block_release")


func test_arrows_are_evaded_by_dodge_invulnerability() -> void:
	var p := _player()
	var a := _archer(Vector3(0, 0.05, -14), "test.archer_e")
	await step_ticks(8)   # on the floor: a dodge needs ground contact
	p.router.inject_edge(&"dodge")
	var ok: bool = await TestWait.until(self, func() -> bool: return p.controller.is_invulnerable(), 20)
	assert_true(ok, "the dodge's invulnerable window began")
	var at := p.entity.anchor_position()
	var from := at + Vector3(0, 0, -1.5)
	ProjectileSystem.instance(get_tree()).spawn(a.entity, action(SHOT), from, (at - from).normalized() * 32.0,
		a.runner.context())
	await TestWait.until(self, func() -> bool: return hits_on("player").size() >= 1, 10)
	var on := hits_on("player")
	assert_eq(on.size(), 1, "the arrow met the giant")
	if on.size() == 1:
		assert_eq(on[0].outcome, HitResult.Outcome.EVADED, "inside the dodge's i-frames it is evaded")
		assert_eq(on[0].health_damage, 0, "no damage")


func test_arrows_stop_at_walls() -> void:
	var p := _player()
	add_box(Vector3(8, 6, 1), Vector3(0, 3, -7))   # a wall between the archer and the giant
	var a := _archer(Vector3(0, 0.05, -14), "test.archer_w")
	await step_ticks(2)
	_draw(a)
	var ok: bool = await TestWait.until(self, func() -> bool: return impacts.size() == 1, 120)
	assert_true(ok, "the arrow struck something")
	if impacts.size() == 1:
		assert_eq(str(impacts[0].hit), "", "the wall")
		assert_true(absf((impacts[0].position as Vector3).z + 7.5) < 0.8, "at the wall's face (z %.2f)" % (impacts[0].position as Vector3).z)
	assert_eq(hits_on("player").size(), 0, "the giant behind it is not hit")
	assert_true(p != null, "player present")


# --------------------------------------------------------------------------- committed aim

## Decision 24: the aim locks at 60 % of the draw (it stops turning and stores the target's
## anchor); a giant that steps 4 m sideways after the lock is missed, one that stands still is hit.
func test_committed_aim_a_sidestep_after_the_lock_dodges_the_arrow() -> void:
	var p := _player()
	var a := _archer(Vector3(0, 0.05, -16), "test.archer_aim")
	await step_ticks(2)
	var shot := action(SHOT)
	var lock_tick := EnemyActor.aim_lock_tick(shot)
	assert_eq(lock_tick, 32, "the lock: 60 % of the 54-tick draw")
	_draw(a)
	var live_before := a.current_aim_point()
	assert_true(live_before.is_equal_approx(p.entity.anchor_position()), "before the lock the aim follows the anchor")
	p.global_position.x += 1.0   # it moves before the lock: the aim follows
	await step_ticks(1)
	assert_true(a.current_aim_point().is_equal_approx(p.entity.anchor_position()), "and tracks it")
	var locked: bool = await TestWait.until(self, func() -> bool: return a.aim_locked(), 60)
	assert_true(locked, "the aim locked")
	assert_eq(a.controller.elapsed, lock_tick, "at the lock tick")
	var stored := a.runner.aim_point
	assert_true(stored.is_equal_approx(p.entity.anchor_position()), "it stored the giant's anchor")
	var yaw := a.facing_yaw
	p.global_position.x += 4.0   # the sidestep, after the lock
	await step_ticks(6)
	assert_eq(a.current_aim_point(), stored, "the aim line stays on the stored point")
	assert_near(a.facing_yaw, yaw, 1e-6, "and the archer no longer turns")
	var sys := ProjectileSystem.instance(get_tree())
	var passed: bool = await TestWait.until(self, func() -> bool:
		if spawned.size() != 1:
			return false
		var flying := sys.projectiles()
		return flying.is_empty() or flying[0].position.z > p.global_position.z + 3.0, 120)
	assert_true(passed, "the arrow flew past the giant's line")
	assert_eq(spawned.size(), 1, "one arrow")
	if spawned.size() == 1:
		var origin: Vector3 = spawned[0].position
		var expected := Projectile.launch_velocity(origin, stored, Projectile.spec_for(shot))
		assert_true((spawned[0].velocity as Vector3).is_equal_approx(expected), "launched at the stored point")
	assert_eq(hits_on("player").size(), 0, "the sidestep dodged it")
	# Standing still: the next arrow lands.
	await TestWait.until(self, func() -> bool: return a.controller.action == null, 90)
	_draw(a)
	var hit: bool = await TestWait.until(self, func() -> bool: return hits_on("player").size() == 1, 120)
	assert_true(hit, "a giant that stands still is hit")


# --------------------------------------------------------------------------- close range

## Under 2.5 m from a stage-1 giant's centre the archer kicks (a sector at leg height).
func test_archer_kicks_a_giant_at_its_feet() -> void:
	var p := _player()
	var a := _archer(Vector3(0, 0.05, -2.2), "test.archer_k", true)
	var ok: bool = await TestWait.until(self, func() -> bool:
		return hits_on("player").any(func(r: HitResult) -> bool: return r.event.action_id == "ability.archer_kick"), 150)
	assert_true(ok, "the kick lands on the giant's legs")
	assert_eq(_launches_by("test.archer_k").size(), 0, "no arrow from point blank")
	assert_true(p != null and a != null, "actors present")


## Pressure or throw: a thrown body staggers a drawing archer, so its arrow never leaves.
func test_a_throw_interrupts_the_archers_draw() -> void:
	var p := _player()
	var s := spawn_soldier(Vector3(0, 0.05, -3.0), PI, "test.thrown")
	var a := _archer(Vector3(0.5, 0.05, -10), "test.archer_t")
	await step_ticks(2)
	s.entity.stagger(3.0, "test")
	assert_eq(p.grab.try_grab(), CombatController.Verdict.ACCEPT, "grab")
	assert_true(await TestWait.until(self, func() -> bool: return p.grab.is_holding(), 40), "holding the soldier")
	await TestWait.until(self, func() -> bool:
		return p.controller.state == CombatController.State.LOCOMOTION and p.controller.action == null, 90)
	p.router.inject_edge(&"lock_press")
	await step_ticks(1)
	assert_eq(p.lock.target_id, "test.archer_t", "locked on the archer")
	_draw(a)
	p.router.inject_light_attack()
	var staggered: bool = await TestWait.until(self, func() -> bool:
		return a.controller.state == CombatController.State.STAGGERED or not a.entity.is_alive(), 80)
	assert_true(staggered, "the throw staggered (or killed) the archer")
	var on := hits_on("test.archer_t")
	assert_true(on.size() >= 1 and on[0].event.action_id == "ability.throw_held", "hit by the thrown body")
	await step_ticks(40)
	assert_eq(_launches_by("test.archer_t").size(), 0, "its arrow never left")


func test_boulder_hurl_interrupts_the_archers_draw() -> void:
	var p := _player()
	p.set_profile(GameData.get_record("growth.02"))
	var a := _archer(Vector3(0, 0.05, -16), "test.archer_b")
	await step_ticks(3)
	p.router.inject_edge(&"lock_press")
	await step_ticks(1)
	assert_eq(p.lock.target_id, "test.archer_b", "locked on the archer")
	p.router.inject_edge(&"slot_5")
	var thrown: bool = await TestWait.until(self, func() -> bool:
		return spawned.any(func(s: Dictionary) -> bool: return s.action == "ability.boulder_hurl"), 60)
	assert_true(thrown, "Boulder Hurl launched")
	_draw(a)
	var stopped: bool = await TestWait.until(self, func() -> bool:
		return a.controller.state == CombatController.State.STAGGERED or not a.entity.is_alive(), 80)
	assert_true(stopped, "the boulder staggered (or killed) the archer mid-draw")
	assert_true(hits_on("test.archer_b").any(func(r: HitResult) -> bool: return r.event.action_id == "ability.boulder_hurl"),
		"hit by the boulder")
	await step_ticks(40)
	assert_eq(_launches_by("test.archer_b").size(), 0, "its arrow never left")
