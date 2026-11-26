extends IntegrationSuite
## The sparring post (P11b, plan §3.13 design 6, §4.4) with the real giant: it swings every 3 s
## with a circle telegraph while the giant stands within 4 m (and never beyond); blocking,
## parrying and dodging its swing give BLOCKED, PARRIED and EVADED; it never dies (it resets at
## 1 health); it never becomes aware, so it never defers a checkpoint; it is lockable, immobile,
## gives no XP, and is not in the "enemies" group (soak bots never take it for a kill).

const POST := "res://scenes/enemies/sparring_post.tscn"
const SWING := "ability.sparring_swing"

var telegraphs: Array = []


func before_each() -> void:
	await super()
	telegraphs.clear()
	Events.telegraph_started.connect(_on_telegraph)


func after_each() -> void:
	if Events.telegraph_started.is_connected(_on_telegraph):
		Events.telegraph_started.disconnect(_on_telegraph)
	await super()


func _on_telegraph(tick: int, actor_id: String, action_id: String, target_id: String, shape: String,
		_origin: Vector3, _yaw: float, radius: float, _length: float, duration_s: float) -> void:
	telegraphs.append({"tick": tick, "actor": actor_id, "action": action_id, "target": target_id,
		"shape": shape, "radius": radius, "duration": duration_s})


func _post(pos: Vector3, ai := true, id := "test.sparring_post") -> SparringPost:
	return TestSpawn.enemy(world, POST, pos, id, ai) as SparringPost


## A giant `distance` m south of the post, facing it.
func _giant_facing(post: SparringPost, distance: float) -> GiantPlayer:
	var pos := post.global_position + Vector3(0, 0, distance)
	return spawn_player(Vector3(pos.x, 0.05, pos.z), yaw_towards(pos, post.global_position))


func _post_telegraphs(id := "test.sparring_post") -> Array:
	return telegraphs.filter(func(t: Dictionary) -> bool: return t.actor == id)


## Waits for the post's next swing to reach `windup_tick` of its windup (controller.elapsed).
func _await_windup(post: SparringPost, windup_tick: int, max_ticks := 260) -> bool:
	return await TestWait.until(self, func() -> bool:
		return post.controller.action != null and post.controller.action.id == SWING \
			and post.controller.phase() == ActionDef.Phase.WINDUP and post.controller.elapsed >= windup_tick, max_ticks)


func _hits_from_post(id := "test.sparring_post") -> Array[HitResult]:
	var out: Array[HitResult] = []
	for r in hits:
		if r.event.attacker_id == id and r.event.target_id == "player":
			out.append(r)
	return out


func test_record_scene_and_groups() -> void:
	var rec: Dictionary = GameData.get_record("enemy.sparring_post")
	assert_eq(rec.get("archetype"), "training", "archetype training")
	assert_true(bool(rec.get("unkillable")), "unkillable")
	assert_true(bool(rec.get("lockable")), "lockable")
	assert_near(float(rec.get("threat")), 0.1, 1e-6, "threat 0.1")
	assert_eq(int(rec.get("xp_reward")), 0, "no XP")
	assert_false(bool(rec.get("grants_fury")), "no fury")
	var swing := action(SWING)
	assert_eq(swing.power, 10.0, "swing power 10")
	assert_eq(swing.windup_ticks, 48, "0.8 s windup")
	assert_true(swing.has_tag("Parryable") and swing.has_tag("Melee"), "parryable")
	var tele: Dictionary = swing.param("telegraph")
	assert_eq(tele.get("shape"), "circle", "a circle telegraph")
	assert_near(float(tele.get("radius_m")), 3.0, 1e-6, "of radius 3 m")
	assert_near(swing.radius_m, 3.0, 1e-6, "and a pulse that matches it")
	var post := _post(Vector3(0, 0.05, -6), false)
	await step_ticks(2)
	assert_eq(post.entity.team, CombatEntity.Team.ENEMY, "team ENEMY")
	assert_true(TargetingRules.player_may_target(post.entity) and post.entity.is_lockable(), "lockable by the player")
	assert_false(post.is_in_group("enemies"), "not in the enemies group")
	assert_true(post.is_in_group(SparringPost.GROUP) and post.is_in_group(SparringPost.TRAINING_GROUP),
		"in the sparring_posts and training_targets groups")
	assert_true(post.brain is SparringBrain, "a SparringBrain")
	assert_false(post.can_be_grabbed(), "never grabbed")
	for path in ["CombatEntity", "NavAgent", "Visual/Body", "Visual/LodProxy", "Visual/Body/Arms", "Anchors/Torso",
			"Hurtboxes/Post"]:
		assert_true(post.get_node_or_null(path) != null, "the scene has %s" % path)
	var start := post.global_position
	post.apply_knockback(Vector3.FORWARD, 8.0)
	await step_ticks(20)
	assert_true(ValleyProbe.flat(post.global_position, start) < 0.01, "immobile: knockback does not move it")


func test_swings_every_3_s_with_a_circle_telegraph_within_4_m() -> void:
	var post := _post(Vector3(0, 0.05, -6))
	var p := _giant_facing(post, 3.4)
	var ok: bool = await TestWait.until(self, func() -> bool: return _post_telegraphs().size() >= 3, 480)
	assert_true(ok, "three swings while the giant stands 3.4 m away")
	var mine := _post_telegraphs()
	if mine.size() >= 3:
		assert_eq(mine[0].action, SWING, "the sparring swing")
		assert_eq(mine[0].shape, "circle", "behind a circle telegraph")
		assert_near(float(mine[0].radius), 3.0, 1e-6, "of radius 3 m")
		assert_near(float(mine[0].duration), 0.8, 1e-6, "filling over the 0.8 s windup")
		assert_eq(mine[0].target, "player", "aimed at the giant (the tutorial block and dodge prompts)")
		assert_eq(int(mine[1].tick) - int(mine[0].tick), 180, "the second swing 3 s after the first")
		assert_eq(int(mine[2].tick) - int(mine[1].tick), 180, "and the third 3 s later")
	assert_true(_hits_from_post().size() >= 2, "the swings land on a giant that stands in them")
	assert_true(_hits_from_post().all(func(r: HitResult) -> bool: return r.health_damage == 12),
		"12 damage each (10 x 1.15, armour 0)")
	# Out of reach: no swing at all.
	p.global_position = post.global_position + Vector3(0, 0.05, 6.0)
	await step_ticks(30)
	var before := _post_telegraphs().size()
	await step_ticks(240)
	assert_eq(_post_telegraphs().size(), before, "no swing while the giant stands 6 m away")
	assert_true(post.brain.state in [EnemyBrain.AIState.IDLE], "it waits (%s)" % post.brain.state_name())


func test_block_parry_and_dodge_give_blocked_parried_and_evaded() -> void:
	var post := _post(Vector3(0, 0.05, -6))
	var p := _giant_facing(post, 3.2)
	await step_ticks(8)
	# Block: raised early in the windup and held.
	assert_true(await _await_windup(post, 4), "a swing begins")
	p.router.set_injected_hold(&"block", true)
	p.router.inject_edge(&"block_press")
	await step_ticks(60)
	var got := _hits_from_post()
	assert_eq(got.size(), 1, "the first swing connects once")
	if got.size() == 1:
		assert_eq(got[0].outcome, HitResult.Outcome.BLOCKED, "a held block: BLOCKED")
	p.router.set_injected_hold(&"block", false)
	p.router.inject_edge(&"block_release")
	# Parry: block pressed just before the swing lands.
	assert_true(await _await_windup(post, 45), "the next swing nears its strike")
	p.router.set_injected_hold(&"block", true)
	p.router.inject_edge(&"block_press")
	await step_ticks(20)
	got = _hits_from_post()
	assert_eq(got.size(), 2, "the second swing connects once")
	if got.size() == 2:
		assert_eq(got[1].outcome, HitResult.Outcome.PARRIED, "block pressed as it lands: PARRIED")
	p.router.set_injected_hold(&"block", false)
	p.router.inject_edge(&"block_release")
	# Dodge: rolling in through the swing as it lands (the i-frames cover the strike).
	assert_true(await _await_windup(post, 40), "the third swing nears its strike")
	p.router.set_injected_move(Vector2(0, 1))
	p.router.inject_edge(&"dodge")
	await step_ticks(20)
	p.router.set_injected_move(Vector2.ZERO)
	got = _hits_from_post()
	assert_eq(got.size(), 3, "the third swing reaches the dodging giant once")
	if got.size() == 3:
		assert_eq(got[2].outcome, HitResult.Outcome.EVADED, "dodged through it: EVADED")
	assert_eq(post.swings(), 3, "three swings")


func test_never_dies_resets_and_never_defers_a_checkpoint() -> void:
	var post := _post(Vector3(0, 0.05, -6))
	var p := _giant_facing(post, 3.3)
	await step_ticks(4)
	var hp := post.entity.combatant.pools
	for i in 3:
		queue_hit("player", post.entity_id, p.global_position, 4000.0)
		await step_ticks(2)
		assert_true(post.entity.is_alive(), "alive after a lethal blow (%d)" % (i + 1))
		assert_near(hp.health, hp.health_max, 1e-6, "reset to full health (%d)" % (i + 1))
	assert_eq(post.resets, 3, "three resets")
	assert_false(deaths.has(post.entity_id), "no death event")
	assert_eq(post.entity.combatant.xp_reward, 0, "no XP to earn")
	# Swinging at the giant, it never becomes aware: a checkpoint is never deferred by it.
	var aware_ticks := 0
	var blocked_ticks := 0
	for i in 200:
		await step_ticks(1)
		if post.brain.aware:
			aware_ticks += 1
		for b in GameSession.checkpoint_blockers():
			if str(b).begins_with("aware:"):
				blocked_ticks += 1
	assert_true(_post_telegraphs().size() >= 1, "it swung meanwhile")
	assert_eq(aware_ticks, 0, "never aware")
	assert_eq(blocked_ticks, 0, "never a checkpoint blocker")
