extends IntegrationSuite
## P32 (plan M6-M9 §2.10, §3.16 tests, §5.11): cavalry harasses a giant's legs.
##   * The cycle - charge, wheel away 30-50 m past the giant, charge again from there - on
##     CavalryBrain driven without physics: a kinematic stand-in for the horse runs to the brain's
##     move_target at the record's run speed, faces its face point at once, and plays an attack's
##     phases (the charge's run: the action's motion along the line it committed to). The real horse's
##     lap takes about 11 s, so it is the slow battery's (tests/slow/test_siege_battery.gd).
##   * The real charge, sped up (a shorter windup and a faster, shorter run): its line telegraph, one
##     hit as it rides through a stage-4 giant's legs - struck as a 4 m attacker - without shoving the
##     giant along the line, and the horse collides with actors again once its run is over; then a
##     giant that steps off the line after the commit is not hit (the rider does not turn after it).
##   * M8 screenshot pass (V3): the leash - a rider rides for its start point only as far as its leash
##     allows, holds there facing the giant and charges from there once he is in its window.

const CAVALRY := "res://scenes/enemies/cavalry.tscn"
const CHARGE := "ability.cavalry_charge"
const LOCO := CombatController.State.LOCOMOTION
const ATTACKING := CombatController.State.ATTACKING

var _telegraphs: Array[Array] = []


func before_each() -> void:
	await super()
	_telegraphs.clear()
	Events.telegraph_started.connect(_on_telegraph)


func after_each() -> void:
	if Events.telegraph_started.is_connected(_on_telegraph):
		Events.telegraph_started.disconnect(_on_telegraph)
	await super()


func _on_telegraph(_t: int, actor_id: String, action_id: String, _target: String, shape: String,
		_origin: Vector3, _yaw: float, _radius: float, length: float, _duration: float) -> void:
	_telegraphs.append([actor_id, action_id, shape, length])


## A giant of `stage` at `pos` (its profile set directly: the growth path is P05's).
func _giant(stage: int, pos: Vector3) -> GiantPlayer:
	var p := spawn_player(pos, 0.0)
	for rec: Dictionary in GameData.records_of_type("growth_profile"):
		if int(rec.get("stage", 0)) == stage:
			p.set_profile(rec)
	return p


func _charge_hits(target_id: String) -> Array[HitResult]:
	var out: Array[HitResult] = []
	for r in hits_on(target_id):
		if r.event.action_id == CHARGE:
			out.append(r)
	return out


static func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


# --------------------------------------------------------------------------- the cycle (no physics)

func test_the_rider_charges_wheels_away_past_the_giant_and_charges_again() -> void:
	var rec: Dictionary = GameData.get_record("enemy.cavalry")
	var b := CavalryBrain.new("test.p32_lap", rec, 5)
	var charge := GameData.get_action(CHARGE)
	var motion: Dictionary = charge.param("motion")
	var dt := 1.0 / Sim.TICK_RATE
	var giant := Vector3.ZERO
	var radius := 2.2   # a stage-4 giant
	var pos := Vector3(0, 0, 40)
	var facing := Vector3.FORWARD
	var tokens := {"asked": 0, "held": 0}
	var req := func() -> bool:
		tokens.asked += 1
		tokens.held += 1
		return true
	var rel := func() -> void: tokens.held = maxi(0, int(tokens.held) - 1)
	var attack := ""
	var attack_tick := 0
	var run_dir := Vector3.ZERO
	var run_left := 0.0
	var starts: Array[Vector3] = []        # where each charge was asked for
	var first_wheel := Vector3.INF
	var token_in_wheel := false
	var t0 := 1000
	for tick in range(t0, t0 + 1500):
		if (tick - t0) % 12 == 0:
			var to := giant - pos
			to.y = 0.0
			b.perceive(tick, {"exists": true, "target_id": "player", "alive": true, "position": giant,
				"distance": to.length(), "visible": true,
				"facing_deg": rad_to_deg(facing.signed_angle_to(to, Vector3.UP)) if to.length() > 0.01 else 0.0,
				"target_radius": radius, "target_forward": Vector3.BACK, "target_height": 10.9728,
				"target_stage": 4, "target_state": LOCO, "self_health_frac": 1.0, "has_leader": true})
		if (tick - t0) % 6 == 0:
			b.decide(tick, ATTACKING if attack != "" else LOCO, pos, req, rel)
			if b.state == EnemyBrain.AIState.REPOSITION:
				token_in_wheel = token_in_wheel or b.holds_token or int(tokens.held) > 0
				if first_wheel == Vector3.INF and b.wheel_point != Vector3.INF:
					first_wheel = b.wheel_point
			if b.attack_request != "" and attack == "":
				attack = b.attack_request
				attack_tick = tick
				if attack == CHARGE:
					starts.append(pos)
					run_dir = Vector3(giant.x - pos.x, 0.0, giant.z - pos.z).normalized()
					run_left = float(motion.max_distance_m)
				b.attack_request = ""
		if b.charges >= 2 and starts.size() >= 2:
			break
		if attack != "":
			var a := GameData.get_action(attack)
			var e := tick - attack_tick
			if attack == CHARGE and e >= a.windup_ticks and e < a.windup_ticks + a.active_ticks and run_left > 0.0:
				var step := minf(float(motion.speed_mps) * dt, run_left)
				pos += run_dir * step
				run_left -= step
			if e >= a.windup_ticks + a.active_ticks + a.recovery_ticks:
				attack = ""
			continue
		if b.face_point != Vector3.INF:
			var f := Vector3(b.face_point.x - pos.x, 0.0, b.face_point.z - pos.z)
			if f.length() > 0.01:
				facing = f.normalized()
		if b.move_target != Vector3.INF:
			var d := Vector3(b.move_target.x - pos.x, 0.0, b.move_target.z - pos.z)
			var speed := float(rec.run_speed_mps) if b.move_speed < 0.0 else float(rec.walk_speed_mps)
			if d.length() > 0.05:
				pos += d.normalized() * minf(speed * dt, d.length())
				if b.face_point == Vector3.INF:
					facing = d.normalized()
	assert_eq(starts.size(), 2, "it charged, then charged again (%d charges, %d wheels)" % [b.charges, b.wheels])
	assert_true(b.wheels >= 1, "it wheeled away between them")
	if starts.size() < 2:
		return
	var window := b.start_window()
	var edge := _flat(starts[0], giant) - radius
	assert_true(edge >= window.x - 0.01 and edge <= window.y + 0.01,
		"the first charge starts inside its window (%.1f m from the giant's surface; %.0f-%.0f)" % [edge, window.x, window.y])
	assert_true(first_wheel != Vector3.INF, "it picked a wheel point")
	if first_wheel != Vector3.INF:
		var away := _flat(first_wheel, giant)
		assert_true(away >= 30.0 - 0.01 and away <= 50.0 + 0.01, "30-50 m from the giant (%.1f m)" % away)
		assert_true(first_wheel.z < -radius and absf(first_wheel.x) < 1.0,
			"beyond the giant, on along the charge line (%s)" % first_wheel)
	assert_true(starts[1].z < 0.0, "the re-charge comes from the far side (%s)" % starts[1])
	var edge2 := _flat(starts[1], giant) - radius
	assert_true(edge2 >= window.x - 0.01 and edge2 <= window.y + 0.01,
		"and from inside the window again (%.1f m)" % edge2)
	assert_false(token_in_wheel, "the attack token goes back before the wheel")
	assert_eq(int(tokens.asked), 2, "one token asked for per charge")
	# A start point it cannot reach turns its approach round the giant; it does not wheel.
	var blocked := CavalryBrain.new("test.p32_blocked", rec, 3)
	var from := Vector3(0, 0, 60)
	var snap := {"exists": true, "target_id": "player", "alive": true, "position": giant, "distance": 60.0,
		"visible": true, "facing_deg": 0.0, "target_radius": radius, "target_forward": Vector3.BACK,
		"target_height": 10.9728, "target_stage": 4, "target_state": LOCO, "self_health_frac": 1.0, "has_leader": true}
	blocked.perceive(t0, snap)
	blocked.state = EnemyBrain.AIState.APPROACH
	blocked.state_tick = t0
	blocked.decide(t0 + 6, LOCO, from, req, rel)
	var first := blocked.move_target
	blocked.on_path_failed(from)
	blocked.decide(t0 + 12, LOCO, from, req, rel)
	assert_eq(blocked.state, EnemyBrain.AIState.APPROACH, "a blocked approach is no wheel")
	var turned := rad_to_deg(Vector2(first.x, first.z).angle_to(Vector2(blocked.move_target.x, blocked.move_target.z)))
	assert_near(absf(turned), CavalryBrain.BLOCKED_TURN_DEG, 0.5, "it turns its start point %.0f degrees round the giant" % turned)
	blocked.on_path_failed(from)
	blocked.decide(t0 + 18, LOCO, from, req, rel)
	var turned_2 := rad_to_deg(Vector2(first.x, first.z).angle_to(Vector2(blocked.move_target.x, blocked.move_target.z)))
	assert_near(turned_2, -turned, 0.5, "blocked again, it tries the other side (%.0f degrees)" % turned_2)


# --------------------------------------------------------------------------- the charge (physics)

func test_the_charge_strikes_once_through_the_legs_and_a_step_off_the_line_after_the_commit_dodges_it() -> void:
	# Sped up: a 0.4 s windup (committed after 70 %), a 26 m run at 40 m/s in a 0.7 s active phase.
	TestFixtures.record_override(CHARGE, {"windup_s": 0.4, "active_s": 0.7, "recovery_s": 0.1,
		"motion": {"speed_mps": 40.0, "max_distance_m": 26.0}})
	var p := _giant(4, Vector3(0, 0.05, 0))
	var c := TestSpawn.enemy(world, CAVALRY, Vector3(0, 0.05, 13), "test.p32_rider", false, 0.0) as CavalryEnemy
	await step_ticks(2)
	var base_layer := c.collision_layer
	var base_mask := c.collision_mask
	assert_true(base_layer & HitQueryAdapter.LAYER_ACTORS != 0, "the horse is an actor body")
	c.brain.target_id = p.entity.entity_id
	c.brain.face_point = p.global_position
	c.controller.request(&"attack", {"action_id": CHARGE})
	await step_ticks(1)
	assert_true(_telegraphs.has([c.entity.entity_id, CHARGE, "line", 40.0]), "the charge shows its 40 m line (%s)" % [_telegraphs])
	var seen := {"through": false, "stepped": false}   # (a lambda's captured locals are copies)
	var passed: bool = await TestWait.until(self, func() -> bool:
		if c.is_galloping() and c.collision_layer & HitQueryAdapter.LAYER_ACTORS == 0 \
				and c.collision_mask & HitQueryAdapter.LAYER_ACTORS == 0:
			seen.through = true
		return c.global_position.z < -10.0, 70)
	assert_true(passed, "the horse rode through where the giant stands (z %.1f)" % c.global_position.z)
	assert_true(seen.through, "galloping, it left the actor layer and its mask")
	var on := _charge_hits(p.entity.entity_id)
	assert_eq(on.size(), 1, "one hit per charge")
	if on.size() == 1:
		assert_near(on[0].event.attacker_height_m, 4.0, 1e-4, "struck as a 4 m attacker")
		assert_near(on[0].poise_damage, 60.0 * CombatRules.poise_scale(4.0, p.entity.combatant.height_m), 1e-3,
			"its 60 poise at the 4 m ratio")
	assert_true(_flat(p.global_position, Vector3.ZERO) < 0.5,
		"the giant is not shoved along the line (%.2f m)" % _flat(p.global_position, Vector3.ZERO))
	var settled: bool = await TestWait.until(self, func() -> bool: return c.controller.state == LOCO, 60)
	assert_true(settled, "the charge is over")
	assert_eq([c.collision_layer, c.collision_mask], [base_layer, base_mask], "the horse collides with actors again")
	# The dodge: the rider charges back at the giant, which steps 5 m off the line after the commit.
	c.facing_yaw = PI
	c.rotation.y = PI
	c.controller.request(&"attack", {"action_id": CHARGE})
	await step_ticks(1)
	var a := GameData.get_action(CHARGE)
	var commit := int(a.windup_ticks * a.tracking_fraction)
	var x0 := c.global_position.x
	var gone: bool = await TestWait.until(self, func() -> bool:
		c.brain.face_point = p.global_position   # the brain follows the giant; the commit ignores it
		if not seen.stepped and c.controller.elapsed > commit:
			seen.stepped = true
			p.global_position = Vector3(5.0, 0.05, 0.0)
		return c.global_position.z > 10.0, 70)
	assert_true(seen.stepped and gone, "the second charge ran past (z %.1f)" % c.global_position.z)
	assert_true(absf(c.global_position.x - x0) < 0.3, "committed, it kept its line (x %.2f)" % c.global_position.x)
	assert_eq(_charge_hits(p.entity.entity_id).size(), 1, "the giant that stepped aside is not hit")
	c.queue_free()


# --------------------------------------------------------------------------- the leash (M8 screenshot pass)

## M8 screenshot pass (V3): a rider rides for its start point only as far as its leash allows. The war
## camp's riders, posted at the edge of the camp's 70 m leash, rode for a start point beyond it, were sent
## home, saw the giant again and rode out again (60 leashes a minute, no charge). On CavalryBrain with a
## leash clamp like CavalryEnemy's (70 m round the centre, 3 m short of its edge): from its post it holds,
## facing the giant; from farther in it rides only to the leash; and it charges from its post once the
## giant is in its window. Without a leash it rides for its start point as before.
func test_the_leash_keeps_the_approach_inside_it() -> void:
	var rec: Dictionary = GameData.get_record("enemy.cavalry")
	var radius := 2.2   # a stage-4 giant
	var edge_m := 70.0 - 3.0
	var clamp := func(pt: Vector3) -> Vector3:
		var off := Vector2(pt.x, pt.z)
		if off.length() <= edge_m:
			return pt
		off = off.normalized() * edge_m
		return Vector3(off.x, pt.y, off.y)
	var req := func() -> bool: return true
	var rel := func() -> void: pass
	var t0 := 1000
	var b := CavalryBrain.new("test.v3_leash", rec, 7)
	b.leash_clamp = clamp
	var decide_at := func(tick: int, me: Vector3, giant: Vector3) -> void:
		var to := giant - me
		b.perceive(tick, {"exists": true, "target_id": "player", "alive": true, "position": giant,
			"distance": to.length(), "visible": true, "facing_deg": 0.0, "target_radius": radius,
			"target_forward": Vector3.LEFT, "target_height": 10.9728, "target_stage": 4, "target_state": LOCO,
			"self_health_frac": 1.0, "has_leader": true})
		if b.state != EnemyBrain.AIState.APPROACH and b.state != EnemyBrain.AIState.ATTACK:
			b.state = EnemyBrain.AIState.APPROACH
			b.state_tick = tick
		b.decide(tick, LOCO, me, req, rel)
	# At its post 66 m out, the giant 40 m beyond it: its start point (24 m short of him, 82 m out) is past
	# the leash - it holds where it stands, facing him.
	var post := Vector3(66, 0, 0)
	var giant := Vector3(106, 0, 0)
	decide_at.call(t0, post, giant)
	assert_true(b.held_by_leash, "the leash keeps it short of its start point")
	assert_eq(b.move_target, Vector3.INF, "at the leash's edge it holds")
	assert_true(b.face_point.is_equal_approx(giant), "facing the giant")
	assert_eq(b.attack_request, "", "no charge from 37.8 m off his surface (window %s)" % b.start_window())
	# From farther in, it rides out only as far as the leash allows.
	decide_at.call(t0 + 6, Vector3(40, 0, 0), giant)
	assert_true(b.move_target != Vector3.INF and absf(b.move_target.x - edge_m) < 0.01,
		"it rides to %s, the leash's edge (not to its start point, 82 m out)" % b.move_target)
	# The giant comes within its window: it charges from its post.
	giant = Vector3(88, 0, 0)
	decide_at.call(t0 + 12, post, giant)
	assert_eq(b.attack_request, CHARGE, "it charges from the leash's edge (%.1f m off his surface)" % (22.0 - radius))
	# Without a leash it rides for its start point as before.
	var free := CavalryBrain.new("test.v3_free", rec, 7)
	free.perceive(t0, {"exists": true, "target_id": "player", "alive": true, "position": Vector3(106, 0, 0),
		"distance": 40.0, "visible": true, "facing_deg": 0.0, "target_radius": radius, "target_forward": Vector3.LEFT,
		"target_height": 10.9728, "target_stage": 4, "target_state": LOCO, "self_health_frac": 1.0, "has_leader": true})
	free.state = EnemyBrain.AIState.APPROACH
	free.state_tick = t0
	free.decide(t0 + 6, LOCO, post, req, rel)
	assert_false(free.held_by_leash, "no leash")
	assert_true(free.move_target != Vector3.INF and absf(free.move_target.x - 82.0) < 0.01,
		"it rides for its start point, 24 m short of the giant (%s)" % free.move_target)
