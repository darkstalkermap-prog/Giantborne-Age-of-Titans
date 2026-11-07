extends IntegrationSuite
## The open world's abilities (P31, plan M6-M9 §5.12) through the real giant: Earthquake's six pulses
## strike along its line in order, one pulse id each, after the giant's own telegraph (a crack in its
## colours); Rune Lance reaches a target 58 m away and Storm Call falls on the lock target from above
## after its 1.2 s telegraph (a circle on the target) and sets it Burning; Shoulder Charge dashes
## 12 m through what stands in its way, sweeping it aside, and stops at a wall; Thunderhead staggers
## humans for 1.5 s and not wolves; the self casts (Bulwark, Stonewall Stance, Bedrock Ward, Wild
## Surge, Primal Regrowth) change what they say; and the library holds the actives and the ultimate.

const WOLF := "res://scenes/enemies/wolf.tscn"

var telegraphs: Array = []
var staggers: Array = []
var spawned: Array = []
var expired: Array = []


func before_each() -> void:
	await super()
	telegraphs.clear()
	staggers.clear()
	spawned.clear()
	expired.clear()
	Events.telegraph_started.connect(_on_telegraph)
	Events.staggered.connect(_on_staggered)
	Events.projectile_spawned.connect(_on_spawned)
	Events.status_expired.connect(_on_expired)


func after_each() -> void:
	for sig: Signal in [Events.telegraph_started, Events.staggered, Events.projectile_spawned, Events.status_expired]:
		for c: Dictionary in sig.get_connections():
			if (c.callable as Callable).get_object() == self:
				sig.disconnect(c.callable)
	for n in get_tree().get_nodes_in_group(ProjectileSystem.GROUP):
		n.queue_free()
	await super()


func _on_telegraph(t: int, actor_id: String, action_id: String, target_id: String, shape: String, origin: Vector3,
		_yaw: float, radius: float, length: float, duration_s: float) -> void:
	telegraphs.append({"tick": t, "actor": actor_id, "action": action_id, "target": target_id, "shape": shape,
		"origin": origin, "radius": radius, "length": length, "duration": duration_s})


func _on_staggered(_t: int, id: String, seconds: float, reason: String) -> void:
	staggers.append([id, snappedf(seconds, 0.01), reason])


func _on_spawned(_t: int, _id: int, owner_id: String, action_id: String, pos: Vector3, vel: Vector3, visual: String) -> void:
	spawned.append({"owner": owner_id, "action": action_id, "position": pos, "velocity": vel, "visual": visual})


func _on_expired(_t: int, id: String, status_id: String) -> void:
	expired.append([id, status_id])


func _giant(stage := 1) -> GiantPlayer:
	var p := spawn_player(Vector3(0, 0.05, 0))
	await TestWait.until(self, func() -> bool: return p.is_on_floor(), 30)
	p.entity.combatant.unkillable = true
	if stage > 1:
		assert_true(bool(p.growth.debug_set_stage(stage).ok), "stage %d" % stage)
		await step_ticks(2)
	return p


## Slots `id` into slot 3, fills the pools and casts it through the slot key; true when it started.
func _cast(p: GiantPlayer, id: String) -> bool:
	await TestWait.until(self, func() -> bool: return p.controller.state == CombatController.State.LOCOMOTION, 120)
	p.set_loadout_slot("slot_3", id)
	var pools := p.entity.combatant.pools
	pools.stamina = pools.stamina_max
	pools.essence = pools.essence_max
	p.router.inject_edge(&"slot_3")
	await step_ticks(2)
	return started.has("player:" + id)


func _lock(p: GiantPlayer, target: Node3D) -> void:
	var id := str(target.get("entity_id"))
	p.lock.target_id = id
	p.targeting.sync_lock(id, "acquired")


func _hits_of(target_id: String, action_id: String) -> Array[HitResult]:
	var out: Array[HitResult] = []
	for r in hits_on(target_id):
		if r.event.action_id == action_id:
			out.append(r)
	return out


func test_earthquake_strikes_along_its_line_in_order() -> void:
	var p := await _giant(6)
	var tv := TelegraphVisuals.new()
	world.add_child(tv)
	var ids: Array[String] = []
	for i in 6:
		var id := "test.quake_%d" % i
		spawn_dummy(Vector3(0, 0, -5.0 * (i + 1)), id)
		ids.append(id)
	await step_ticks(2)
	assert_true(await _cast(p, "ability.earthquake"), "Earthquake starts")
	var t: Dictionary = telegraphs.back() if not telegraphs.is_empty() else {}
	assert_eq([t.get("actor"), t.get("action"), t.get("shape")], ["player", "ability.earthquake", "line"],
		"the giant telegraphs its crack (%s)" % [t])
	assert_eq([float(t.get("length", 0)), float(t.get("radius", 0))], [30.0, 3.5], "30 m long, 7 m wide")
	await step_ticks(3)
	var shown := tv.telegraph_for("player")
	assert_true(bool(shown.get("visible", false)), "drawn (%s)" % [shown])
	var view: Dictionary = tv._views.get("player", {})
	if not view.is_empty():
		var base: MeshInstance3D = view.base
		assert_true(base.mesh is ArrayMesh, "as a crack, not the threat strip")
		assert_eq((base.material_override as StandardMaterial3D).albedo_color, TelegraphVisuals.P31_BASE_COLOR,
			"in the giant's colours")
	var a := GameData.get_action("ability.earthquake")
	await step_ticks(a.windup_ticks + a.active_ticks)
	var ticks: Array = []
	for i in 6:
		var on := _hits_of(ids[i], "ability.earthquake")
		assert_eq(on.size(), 1, "the dummy %d m ahead is struck once" % (5 * (i + 1)))
		if on.size() == 1:
			assert_eq(on[0].event.pulse_id, i + 1, "by pulse %d" % (i + 1))
			ticks.append(on[0].event.tick)
	var ordered := ticks.duplicate()
	ordered.sort()
	assert_eq(ticks, ordered, "the pulses run outward in order (%s)" % [ticks])
	assert_true(ticks.size() == 6 and int(ticks[5]) - int(ticks[0]) == 5 * AttackRunner.line_pulse_interval(a),
		"one pulse every %d ticks" % AttackRunner.line_pulse_interval(a))


func test_rune_lance_reaches_58_m_and_storm_call_falls_on_the_lock_target() -> void:
	var p := await _giant(5)
	var tv := TelegraphVisuals.new()
	world.add_child(tv)
	var far := spawn_soldier(Vector3(0, 0.05, -58), 0.0, "test.lance_far")
	far.entity.combatant.unkillable = true
	await step_ticks(2)
	_lock(p, far)
	assert_true(await _cast(p, "ability.rune_lance"), "Rune Lance starts")
	await TestWait.until(self, func() -> bool: return not _hits_of("test.lance_far", "ability.rune_lance").is_empty(), 150)
	assert_eq(_hits_of("test.lance_far", "ability.rune_lance").size(), 1, "the lance strikes a target 58 m away")
	assert_eq(str(spawned.back().visual) if not spawned.is_empty() else "", "rune_lance", "as a rune lance")
	far.queue_free()
	var target := spawn_soldier(Vector3(4, 0.05, -20), 0.0, "test.storm")
	target.entity.combatant.unkillable = true
	await step_ticks(2)
	_lock(p, target)
	telegraphs.clear()
	spawned.clear()
	var cast_tick := Sim.tick
	assert_true(await _cast(p, "ability.storm_call"), "Storm Call starts")
	var t: Dictionary = telegraphs.back() if not telegraphs.is_empty() else {}
	assert_eq([t.get("shape"), t.get("target"), float(t.get("radius", 0))], ["circle", "test.storm", 6.0],
		"a 6 m circle telegraphed on the lock target (%s)" % [t])
	assert_true((t.get("origin", Vector3.INF) as Vector3).distance_to(target.global_position) < 0.1, "where it stands")
	assert_near(float(t.get("duration", 0)), 1.2, 0.02, "for the 1.2 s windup")
	await step_ticks(3)
	var shown := tv.telegraph_for("player")
	assert_true((shown.get("start", Vector3.INF) as Vector3).distance_to(target.global_position) < 0.2,
		"TelegraphVisuals draws the circle on the target (%s)" % [shown])
	var a := GameData.get_action("ability.storm_call")
	await step_ticks(a.windup_ticks - 8)
	assert_eq(_hits_of("test.storm", "ability.storm_call").size(), 0, "nothing lands during the telegraph")
	await TestWait.until(self, func() -> bool: return not _hits_of("test.storm", "ability.storm_call").is_empty(), 60)
	var on := _hits_of("test.storm", "ability.storm_call")
	assert_eq(on.size(), 1, "then the strike lands on the target once")
	assert_true(on.size() == 1 and on[0].event.tick - cast_tick >= a.windup_ticks, "after the telegraph")
	var bolt: Dictionary = spawned.back() if not spawned.is_empty() else {}
	assert_eq(str(bolt.get("visual", "")), "storm_bolt", "a storm bolt")
	var from: Vector3 = bolt.get("position", Vector3.ZERO)
	assert_true(from.y > target.global_position.y + 20.0 and Vector2(from.x - 4.0, from.z + 20.0).length() < 1.0,
		"falling from above the target (%s)" % from)
	assert_true(target.entity.combatant.statuses.has("status.burning"), "and sets it Burning")


func test_shoulder_charge_dashes_12_m_through_its_path_and_stops_at_a_wall() -> void:
	var p := await _giant()
	var a := spawn_soldier(Vector3(0, 0.05, -5), 0.0, "test.charge_a")
	var b := spawn_soldier(Vector3(0.6, 0.05, -9), 0.0, "test.charge_b")
	for s in [a, b]:
		s.entity.combatant.unkillable = true
	await step_ticks(2)
	assert_true(await _cast(p, "ability.shoulder_charge"), "Shoulder Charge starts")
	await TestWait.until(self, func() -> bool: return p.controller.state == CombatController.State.LOCOMOTION, 120)
	assert_near(p.motor.motion_travelled, 12.0, 0.3, "the dash carries the giant 12 m (%.2f)" % p.motor.motion_travelled)
	assert_eq(p.motor.motion_end_reason, "distance", "to its full distance")
	assert_true(p.global_position.z < -11.5, "straight ahead (%s)" % p.global_position)
	for id in ["test.charge_a", "test.charge_b"]:
		assert_eq(_hits_of(id, "ability.shoulder_charge").size(), 1, "%s is swept once" % id)
	assert_true(absf(a.global_position.x) > 0.5 or absf(a.global_position.z + 5.0) > 0.5, "and thrown out of the way")
	assert_true((p.collision_mask & HitQueryAdapter.LAYER_ACTORS) != 0, "the giant collides with actors again")
	# A wall 6 m ahead of the giant's new place ends the dash against it.
	add_box(Vector3(8, 4, 1), p.global_position + Vector3(0, 2, -6.5))
	await step_ticks(2)
	p.controller.cooldowns.clear()
	var before := p.global_position
	assert_true(await _cast(p, "ability.shoulder_charge"), "a second charge")
	var charge := GameData.get_action("ability.shoulder_charge")
	await step_ticks(charge.windup_ticks + charge.active_ticks)
	assert_eq(p.motor.motion_end_reason, "wall", "stops at the wall")
	assert_true(p.motor.motion_travelled < 6.0 and before.z - p.global_position.z < 6.0,
		"short of it (%.2f m)" % p.motor.motion_travelled)


func test_thunderhead_staggers_humans_and_the_self_casts_do_what_they_say() -> void:
	var p := await _giant()
	var s := spawn_soldier(Vector3(3, 0.05, -3), 0.0, "test.head_soldier")
	var w := TestSpawn.enemy(world, WOLF, Vector3(-3, 0.05, -3), "test.head_wolf", false, 0.0)
	for e: EnemyActor in [s, w]:
		e.entity.combatant.unkillable = true
	await step_ticks(2)
	assert_true(await _cast(p, "ability.thunderhead"), "Thunderhead starts")
	await step_ticks(GameData.get_action("ability.thunderhead").windup_ticks + 2)
	assert_eq(_hits_of("test.head_soldier", "ability.thunderhead").size(), 1, "it strikes the soldier")
	assert_eq(_hits_of("test.head_wolf", "ability.thunderhead").size(), 1, "and the wolf")
	assert_true(staggers.has(["test.head_soldier", 1.5, "stunned"]), "the soldier is stunned 1.5 s (%s)" % [staggers])
	assert_false(staggers.has(["test.head_wolf", 1.5, "stunned"]), "the wolf is not (not a human)")
	s.queue_free()
	w.queue_free()
	var c := p.entity.combatant
	var motor: PlayerMotor = p.motor
	# Bulwark, Stonewall Stance and Bedrock Ward are their statuses (the casts apply them as P03's
	# self_statuses): damage taken x0.4 and no knockback; x0.6 and speed x0.7; +40 armour.
	for sa: Array in [["ability.bulwark", "status.bulwark"], ["ability.stonewall_stance", "status.stonewall_stance"],
			["ability.bedrock_ward", "status.bedrock_ward"]]:
		var self_statuses: Array = GameData.get_action(sa[0]).param("self_statuses", [])
		assert_eq(str((self_statuses[0] as Dictionary).status) if not self_statuses.is_empty() else "", sa[1],
			"%s casts %s" % sa)
	var armour := c.armor_total()
	p.entity.apply_status("status.bulwark")
	assert_near(c.damage_taken_mult(), 0.4, 1e-4, "Bulwark: damage taken x0.4")
	p.knockback_velocity = Vector3.ZERO
	p.apply_knockback(Vector3.BACK, 10.0)
	assert_eq(p.knockback_velocity, Vector3.ZERO, "and no knockback")
	c.statuses.clear()
	p.apply_knockback(Vector3.BACK, 10.0)
	assert_true(p.knockback_velocity.length() > 9.0, "knockback again without it")
	p.knockback_velocity = Vector3.ZERO
	p.entity.apply_status("status.stonewall_stance")
	assert_near(c.damage_taken_mult(), 0.6, 1e-4, "Stonewall: damage taken x0.6")
	assert_near(motor.status_speed_mult(), 0.7, 1e-4, "and speed x0.7")
	c.statuses.clear()
	p.entity.apply_status("status.bedrock_ward")
	assert_near(c.armor_total() - armour, 40.0, 1e-4, "Bedrock Ward: +40 armour")
	c.statuses.clear()
	# Wild Surge (a real cast): +30 fury on its active tick and speed x1.15.
	c.pools.fury = 0.0
	assert_true(await _cast(p, "ability.wild_surge"), "Wild Surge")
	await step_ticks(GameData.get_action("ability.wild_surge").windup_ticks)
	assert_near(c.pools.fury, 30.0 * c.pools.fury_gain_mult, 1e-4, "Wild Surge: +30 fury")
	assert_near(motor.status_speed_mult(), 1.15, 1e-4, "and speed x1.15")
	c.statuses.clear()
	# Primal Regrowth (a real cast): clears the slow and heals 20 % of the maximum over 6 s (12 heals).
	c.pools.health = c.pools.health_max * 0.5
	p.entity.apply_status("status.slow", 0.3, 4.0, "test")
	assert_true(c.statuses.has("status.slow"), "slowed")
	assert_true(await _cast(p, "ability.primal_regrowth"), "Primal Regrowth")
	await step_ticks(GameData.get_action("ability.primal_regrowth").windup_ticks)
	assert_false(c.statuses.has("status.slow"), "the slow is cleared")
	assert_true(expired.has(["player", "status.slow"]), "and announced as ended")
	var per_heal := c.statuses.magnitude("status.primal_regrowth")
	assert_near(per_heal * 12.0, 0.2 * c.pools.health_max, 0.01, "12 heals add up to 20 %% of %.0f" % c.pools.health_max)
	var health := c.pools.health
	await step_ticks(31)
	assert_near(c.pools.health - health, per_heal, 0.01, "the first heal after half a second")


func test_the_library_holds_the_actives_and_the_ultimate() -> void:
	var lib := Progression.library()
	var actives := 0
	var ultimates := 0
	for id: String in lib:
		var a := GameData.get_action(id)
		assert_true(a != null, "%s exists" % id)
		if a != null:
			actives += 1 if a.kind == "ability" else 0
			ultimates += 1 if a.kind == "ultimate" else 0
	# Rampart Grip (P32, evolves Crushing Grip at stage 6) is the 24th active once its record ships.
	var expected := 24 if GameData.get_action("ability.rampart_grip") != null else 23
	assert_eq([actives, ultimates], [expected, 1], "%d actives and the ultimate (§5.12)" % expected)
	for rec: Dictionary in GameData.records_of_type("action"):
		if str(rec.get("granted_by", "")) != "" or str(rec.get("evolves_from", "")) != "":
			assert_true(lib.has(str(rec.id)), "%s is in the library" % rec.id)
