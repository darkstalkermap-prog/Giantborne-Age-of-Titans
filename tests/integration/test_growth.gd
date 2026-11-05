extends IntegrationSuite
## Growth stages 1-3 (plan §3.5): growing at a shrine keeps the resource fractions and changes
## collision, visuals, movement, camera, reach, lock range and the navigation profile together;
## a blocked growth (the growth course's trap alcove) changes nothing; no invalid spawn after a
## growth; every light and the heavy still reach a soldier and a wolf at the feet of a stage-2
## and stage-3 giant in both camera modes (decision 5); footstep shake follows the camera_shake
## setting; the camera hides the head when its arm is pressed short; unlocks, debug keys,
## events and the save key.

const SHRINE := "res://scenes/world/shrine.tscn"
const WOLF := "res://scenes/enemies/wolf.tscn"
const COURSE := "res://scenes/test/growth_course.tscn"
const ATTACKS := ["ability.light_1", "ability.light_2", "ability.light_3", "ability.heavy_1"]

var growth_events: Array[Array] = []
var blocked_events: Array[Array] = []
var learned_events: Array[Array] = []
var messages: Array[String] = []


func before_each() -> void:
	await super()
	growth_events.clear()
	blocked_events.clear()
	learned_events.clear()
	messages.clear()
	# P08 caps weapons at their fit stage; these tests measure the full-size club at stage 3.
	TestFixtures.record_override("weapon.club", {"fit_max_stage": 3})
	Events.growth_changed.connect(_on_growth)
	Events.growth_blocked.connect(_on_blocked)
	Events.ability_learned.connect(_on_learned)
	Events.hud_message.connect(_on_message)


func after_each() -> void:
	for sig: Signal in [Events.growth_changed, Events.growth_blocked, Events.ability_learned, Events.hud_message]:
		for c: Dictionary in sig.get_connections():
			if (c.callable as Callable).get_object() == self:
				sig.disconnect(c.callable)
	Settings.values["camera_shake"] = Settings.DEFAULTS.camera_shake
	await super()


func _on_growth(_t: int, id: String, old_stage: int, new_stage: int) -> void:
	growth_events.append([id, old_stage, new_stage])


func _on_blocked(_t: int, id: String, reason: String, message: String) -> void:
	blocked_events.append([id, reason, message])


func _on_learned(_t: int, action_id: String, slot_key: String) -> void:
	learned_events.append([action_id, slot_key])


func _on_message(text: String, _kind: String) -> void:
	messages.append(text)


func _shrine(pos: Vector3, world_id := "test.shrine", shrine_id := "shrine.sandbox") -> Shrine:
	var s: Shrine = (load(SHRINE) as PackedScene).instantiate()
	s.world_id = world_id
	s.shrine_id = shrine_id
	s.position = pos
	world.add_child(s)
	return s


func _wolf(pos: Vector3, id: String, yaw := 0.0) -> WolfEnemy:
	return TestSpawn.enemy(world, WOLF, pos, id, false, yaw) as WolfEnemy


## A giant standing on the floor (growth needs it: reason "busy" while airborne).
func _grounded_player(pos: Vector3, yaw := 0.0) -> GiantPlayer:
	var p := spawn_player(pos, yaw)
	await TestWait.until(self, func() -> bool: return p.is_on_floor(), 30)
	await step_ticks(1)
	return p


func _profile(stage: int) -> Dictionary:
	return PlayerGrowth.find_profile(GameData.records_of_type("growth_profile"), stage)


## Everything that follows the growth profile, for before/after comparisons.
static func body_fields(p: GiantPlayer) -> Dictionary:
	var cap := p.body_shape.shape as CapsuleShape3D
	var pools := p.entity.combatant.pools
	var hb := {}
	for area in p.get_node("Hurtboxes").get_children():
		var cs := area.get_node("Shape") as CollisionShape3D
		hb[area.name] = [(area as Node3D).position, (cs.shape as BoxShape3D).size]
	return {
		"stage": p.growth_stage, "controller_stage": p.controller.growth_stage, "profile": p.profile.get("id"),
		"capsule": [cap.radius, cap.height, p.body_shape.position], "floor_snap": p.floor_snap_length,
		"height": p.entity.combatant.height_m, "pivot": p.weapon_pivot, "origin": p.attack_origin,
		"arm": p.arm_length, "weapon": [p.weapon_length, p.weapon_radius],
		"pools_max": [pools.health_max, pools.stamina_max, pools.essence_max],
		"pools": [pools.health, pools.stamina, pools.essence],
		"lock": [p.lock.range_m, p.lock.half_angle_deg], "nav": p.nav_layers,
		"camera": [p.camera_rig.profile.get("id"), p.camera_rig.desired_distance],
		"rig": [p.rig.body_scale, (p.get_node("Visual/Body") as Node3D).scale,
			(p.get_node("Visual/Body/ShoulderR") as Node3D).position],
		"hurtboxes": hb, "anchor": (p.get_node("Anchors/Torso") as Node3D).position,
		"known": p.known_abilities.duplicate(), "loadout": p.controller.loadout.duplicate(),
	}


func _check_stage_fields(p: GiantPlayer, stage: int) -> void:
	var prof := _profile(stage)
	var k := float(prof.height_m) / CombatRules.REFERENCE_HEIGHT_M
	var f := body_fields(p)
	var what := "stage %d" % stage
	assert_eq(f.stage, stage, "%s: growth_stage" % what)
	assert_eq(f.controller_stage, stage, "%s: the controller's stage (unlock gating)" % what)
	assert_eq(f.profile, prof.id, "%s: profile record" % what)
	assert_near(f.capsule[0], float(prof.capsule_radius_m), 1e-6, "%s: capsule radius" % what)
	assert_near(f.capsule[1], float(prof.capsule_total_height_m), 1e-6, "%s: capsule height" % what)
	assert_near((f.capsule[2] as Vector3).y, float(prof.capsule_total_height_m) * 0.5, 1e-6, "%s: capsule on the feet" % what)
	assert_near(f.floor_snap, maxf(0.3, float(prof.step_height_m)), 1e-6, "%s: floor snap" % what)
	assert_near(f.height, float(prof.height_m), 1e-6, "%s: combatant height" % what)
	var pv: Array = prof.weapon_pivot_m
	assert_true((f.pivot as Vector3).is_equal_approx(Vector3(pv[0], pv[1], pv[2])), "%s: weapon pivot" % what)
	var ao: Array = prof.attack_origin_m
	assert_true((f.origin as Vector3).is_equal_approx(Vector3(ao[0], ao[1], ao[2])), "%s: attack origin" % what)
	assert_near(f.arm, float(prof.arm_length_m), 1e-6, "%s: arm length" % what)
	var ws := float(prof.get("weapon_scale", 1.0))
	assert_near(f.weapon[0], 1.85 * ws, 1e-4, "%s: club length x weapon_scale" % what)
	assert_near(f.weapon[1], 0.45 * ws, 1e-4, "%s: club radius x weapon_scale" % what)
	var bonus := PlayerGrowth.resource_bonus(prof)
	assert_near(f.pools_max[0], 500.0 + float(bonus.get("health", 0.0)), 1e-4, "%s: health max with the growth bonus" % what)
	assert_near(f.pools_max[1], 100.0 + float(bonus.get("stamina", 0.0)), 1e-4, "%s: stamina max with the growth bonus" % what)
	assert_near(f.lock[0], float(prof.lock_range_m), 1e-6, "%s: lock range" % what)
	assert_near(f.lock[1], float(prof.lock_half_angle_deg), 1e-6, "%s: lock half-angle" % what)
	assert_eq(f.nav, int(prof.nav_layers), "%s: navigation layers" % what)
	assert_eq(f.camera[0], prof.id, "%s: the camera follows the profile" % what)
	var lo := float(prof.camera_zoom_min_m)
	var hi := float(prof.camera_zoom_max_m)
	var g1 := _profile(1)
	var frac := (float(g1.camera_distance_m) - float(g1.camera_zoom_min_m)) / (float(g1.camera_zoom_max_m) - float(g1.camera_zoom_min_m))
	assert_near(f.camera[1], lerpf(lo, hi, frac), 1e-4, "%s: the zoom keeps its fraction" % what)
	assert_near(f.rig[0], k, 1e-6, "%s: rig body scale k" % what)
	assert_true((f.rig[1] as Vector3).is_equal_approx(Vector3.ONE * k), "%s: Visual/Body scaled by k" % what)
	assert_true((f.rig[2] as Vector3).is_equal_approx(Vector3(pv[0], pv[1], pv[2]) / k), "%s: shoulder at pivot / k in Body space" % what)
	var torso: Array = f.hurtboxes["Torso"]
	assert_true((torso[1] as Vector3).is_equal_approx(Vector3(1.4, 1.5, 0.9) * k), "%s: torso hurtbox size x k (%s)" % [what, torso[1]])
	assert_true((torso[0] as Vector3).is_equal_approx(Vector3(0, 2.35, 0) * k), "%s: torso hurtbox position x k" % what)
	assert_true((f.anchor as Vector3).is_equal_approx(Vector3(0, 2.3, 0) * k), "%s: lock anchor x k" % what)
	var area := p.get_node("Hurtboxes/Torso") as Node3D
	assert_true(area.scale.is_equal_approx(Vector3.ONE), "%s: collision is resized, never node-scaled" % what)


# --------------------------------------------------------------------------- growth 1 -> 2 -> 3 -> 2

func test_growth_keeps_fractions_and_updates_every_field() -> void:
	var s := _shrine(Vector3(0, 0, -12))
	var p := await _grounded_player(Vector3(0, 0.05, 0))
	_check_stage_fields(p, 1)
	var pools := p.entity.combatant.pools
	pools.health = 0.4 * pools.health_max
	pools.stamina = 0.5 * pools.stamina_max
	var r2 := s.grow(p, 2)
	assert_true(r2.ok, "grows to stage 2 at the shrine (%s)" % r2.message)
	assert_near(pools.health, 0.4 * 650.0, 1e-3, "40% health stays 40% of the new maximum (never healed)")
	assert_near(pools.stamina, 0.5 * 110.0, 1e-3, "50% stamina stays 50%")
	assert_near(pools.essence, pools.essence_max, 1e-3, "full essence stays full")
	_check_stage_fields(p, 2)
	assert_eq(p.nav_layers, 4, "nav layers 8 -> 4")
	await step_ticks(2)
	var r3 := s.grow(p, 3)
	assert_true(r3.ok, "grows to stage 3 (%s)" % r3.message)
	assert_near(pools.health, 0.4 * 800.0, 1e-3, "still 40%")
	_check_stage_fields(p, 3)
	await step_ticks(2)
	var back: Dictionary = p.growth.debug_set_stage(2)
	assert_true(back.ok, "debug shrink to stage 2")
	assert_near(pools.health, 0.4 * 650.0, 1e-3, "and still 40% after shrinking")
	_check_stage_fields(p, 2)
	assert_eq(growth_events, [["player", 1, 2], ["player", 2, 3], ["player", 3, 2]], "one growth_changed per growth")
	assert_eq(_profile(1).get("nav_layers"), 8, "stage 1 uses the small-giant nav layer")
	var summary: Dictionary = r2.summary
	assert_eq(summary.stage, [1, 2], "the summary names the stages")
	assert_true((summary.permissions as Array).has("throw_boulder"), "and the interaction stage 2 adds")
	assert_true((summary.lines as PackedStringArray).size() >= 4, "with player-facing lines")


func test_growth_lock_ranges_35_40_45() -> void:
	var s := _shrine(Vector3(0, 0, -12))
	var p := await _grounded_player(Vector3(0, 0.05, 0))
	var ranges: Array = [p.lock.range_m]
	for stage in [2, 3]:
		assert_true(s.grow(p, stage).ok, "grow to %d" % stage)
		ranges.append(p.lock.range_m)
		await step_ticks(1)
	assert_eq(ranges, [35.0, 40.0, 45.0], "lock range 35 -> 40 -> 45 m")


# --------------------------------------------------------------------------- blocked growth

func test_blocked_growth_in_the_trap_changes_nothing() -> void:
	var course: Node3D = (load(COURSE) as PackedScene).instantiate()
	world.add_child(course)
	var p := course.get_node("Player") as GiantPlayer
	p.router.use_injection = true
	var shrine := course.get_node("Shrine") as Shrine
	await step_ticks(4)
	assert_true(shrine.grow(p, 2).ok, "stage 2 in the open")
	var trap := (course.get_node("Markers/TrapPoint") as Node3D).global_position
	p.global_position = trap + Vector3(0, 0.05, 0)
	p.velocity = Vector3.ZERO
	await step_ticks(20)
	assert_true(p.is_on_floor(), "standing in the trap alcove (6 m ceiling)")
	growth_events.clear()
	var before := body_fields(p)
	var r := shrine.grow(p, 3)
	assert_false(r.ok, "stage 3 does not fit under a 6 m ceiling")
	assert_eq(r.reason, "clearance", "reason clearance")
	assert_eq(r.message, "Not enough room to grow here. Step into the open.", "player-facing message")
	assert_eq(body_fields(p), before, "a blocked growth changes nothing [§15 blocked growth leaves old parameters intact]")
	assert_eq(growth_events.size(), 0, "no growth_changed")
	assert_eq(blocked_events, [["player", "clearance", r.message]], "growth_blocked emitted once")
	assert_true(messages.has(r.message), "the HUD shows why")
	var d: Dictionary = p.growth.debug_set_stage(3)
	assert_eq(d.reason, "clearance", "the debug path checks clearance too")
	assert_eq(body_fields(p), before, "and changes nothing either")
	await step_ticks(5)
	assert_eq(body_fields(p).stage, 2, "still stage 2 after more ticks")
	course.queue_free()
	await step_ticks(2)


func test_no_invalid_spawn_after_growth() -> void:
	var s := _shrine(Vector3(0, 0, -12))
	var p := await _grounded_player(Vector3(0, 0.05, 0))
	for stage in [2, 3]:
		assert_true(s.grow(p, stage).ok, "grow to %d" % stage)
		var cap := p.body_shape.shape as CapsuleShape3D
		var q := PhysicsShapeQueryParameters3D.new()
		q.shape = cap
		q.transform = Transform3D(Basis(), p.global_position + Vector3.UP * (cap.height * 0.5 + 0.01))
		q.collision_mask = PlayerGrowth.CLEARANCE_MASK
		q.exclude = [p.get_rid()]
		var overlaps := p.get_world_3d().direct_space_state.intersect_shape(q, 4)
		assert_eq(overlaps.size(), 0, "stage %d: the new capsule overlaps nothing" % stage)
		var landed: bool = await TestWait.until(self, func() -> bool: return p.is_on_floor(), 30)
		assert_true(landed, "stage %d: on the floor within 0.5 s" % stage)
		assert_near(p.global_position.y, 0.0, 0.1, "stage %d: feet on the ground" % stage)


# --------------------------------------------------------------------------- downward attacks

## Every light and the heavy, each started on its own facing straight ahead, at stages 2 and
## 3, in third and first person, lands on a 1.8 m soldier and on a 0.9 m wolf standing at
## 0.6 x melee reach in front (decision 5) [§15 downward attacks].
func test_lights_and_heavy_reach_soldiers_and_wolves_at_stages_2_and_3() -> void:
	var n := 0
	for stage in [2, 3]:
		for first_person in [false, true]:
			var p := await _grounded_player(Vector3(0, 0.05, 0))
			p.entity.combatant.unkillable = true
			var grown: Dictionary = p.growth.debug_set_stage(stage)
			assert_true(grown.ok, "stage %d (%s)" % [stage, grown.reason])
			if first_person:
				p.router.inject_edge(&"camera_toggle")
			await step_ticks(3)
			var d := 0.6 * float(p.profile.melee_reach_m)
			for kind in ["soldier", "wolf"]:
				for attack_id: String in ATTACKS:
					n += 1
					var id := "test.%s_reach_%d" % [kind, n]
					var pos := Vector3(0, 0.05, -d)
					var target: EnemyActor
					if kind == "soldier":
						target = spawn_soldier(pos, 0.0, id)
					else:
						target = _wolf(pos, id, 0.0)
					target.entity.combatant.unkillable = true
					p.camera_rig.yaw = 0.0
					p.entity.combatant.pools.stamina = p.entity.combatant.pools.stamina_max
					await step_ticks(2)
					var a := GameData.get_action(attack_id)
					assert_eq(p.controller.request(&"attack", {"action_id": attack_id}), CombatController.Verdict.ACCEPT,
						"%s starts" % attack_id)
					await step_ticks(a.windup_ticks + a.active_ticks + 2)
					var landed := 0
					for r in hits_on(id):
						if r.event.action_id == attack_id:
							landed += 1
					assert_eq(landed, 1, "stage %d %s: %s lands on a %s %.2f m in front" % [stage,
						"first person" if first_person else "third person", attack_id, kind, d])
					target.queue_free()
					await TestWait.until(self, func() -> bool:
						return p.controller.state == CombatController.State.LOCOMOTION, 90)
					await step_ticks(1)
			p.queue_free()
			await step_ticks(2)


func _landed(target_id: String, attack_id: String) -> int:
	var n := 0
	for r in hits_on(target_id):
		if r.event.action_id == attack_id:
			n += 1
	return n


## Where a lunge stops: the wolf's approach_stop_m (0.1 m) capsule gap from the giant.
static func lunge_stop_m(p: GiantPlayer) -> float:
	return float(p.profile.capsule_radius_m) + 0.4 + 0.1


## The M2 gate's "dodge then punish" at the bigger stages: lights 1 and 2 and the heavy, each
## started alone, land on a wolf standing where its lunge stops (1.7 m from a stage-2 giant's
## centre, 2.15 m from a stage-3 one), straight ahead and 15 degrees to either side. (Light 3
## is an overhead chop down the right side: at a stage-3 giant's feet it only reaches the
## right; the chain test below shows it still connects after the first two blows.)
func test_lights_1_2_and_heavy_reach_a_wolf_at_the_feet_of_stages_2_and_3() -> void:
	var n := 0
	for stage in [2, 3]:
		var p := await _grounded_player(Vector3(0, 0.05, 0))
		p.entity.combatant.unkillable = true
		assert_true(p.growth.debug_set_stage(stage).ok, "stage %d" % stage)
		await step_ticks(2)
		var d := lunge_stop_m(p)
		for attack_id: String in ["ability.light_1", "ability.light_2", "ability.heavy_1"]:
			for bearing: float in [-15.0, 0.0, 15.0]:
				n += 1
				var id := "test.wolf_feet_%d" % n
				var t := deg_to_rad(bearing)
				var pos := Vector3(d * sin(t), 0.05, -d * cos(t))
				var w := _wolf(pos, id, yaw_towards(pos, Vector3.ZERO))
				w.entity.combatant.unkillable = true
				p.camera_rig.yaw = 0.0
				p.global_position = Vector3(0, 0.05, 0)
				p.entity.combatant.pools.stamina = p.entity.combatant.pools.stamina_max
				await step_ticks(2)
				var a := GameData.get_action(attack_id)
				p.controller.request(&"attack", {"action_id": attack_id})
				await step_ticks(a.windup_ticks + a.active_ticks + 2)
				assert_eq(_landed(id, attack_id), 1, "stage %d: %s lands on a wolf at the giant's feet (%.2f m, %+.0f degrees)" % [
					stage, attack_id, d, bearing])
				w.queue_free()
				await TestWait.until(self, func() -> bool:
					return p.controller.state == CombatController.State.LOCOMOTION, 90)
				await step_ticks(1)
		p.queue_free()
		await step_ticks(2)


## A wolf that lunges at a stage-2 or stage-3 giant stops at its feet; the light chain entered
## through the input router in its 0.9 s recovery lands lights 1 and 2 inside that window, and
## light 3 connects too.
func test_a_lunging_wolf_is_punished_by_the_light_chain_at_stages_2_and_3() -> void:
	var lunge := GameData.get_action("ability.wolf_lunge")
	var n := 0
	for stage in [2, 3]:
		n += 1
		var p := await _grounded_player(Vector3(0, 0.05, 0))
		p.entity.combatant.unkillable = true
		assert_true(p.growth.debug_set_stage(stage).ok, "stage %d" % stage)
		await step_ticks(2)
		var start := lunge_stop_m(p) + 3.0
		var id := "test.wolf_punished_%d" % n
		var wpos := Vector3(0, 0.05, -start)
		var w := _wolf(wpos, id, yaw_towards(wpos, Vector3.ZERO))
		w.entity.combatant.unkillable = true
		p.camera_rig.yaw = 0.0
		await step_ticks(3)
		w.brain.target_id = "player"
		w.controller.request(&"attack", {"action_id": "ability.wolf_lunge"})
		var recovering: bool = await TestWait.until(self, func() -> bool:
			return w.controller.phase() == ActionDef.Phase.RECOVERY, lunge.windup_ticks + lunge.active_ticks + 5)
		assert_true(recovering, "stage %d: the lunge ends in its recovery" % stage)
		var stop := Vector2(w.global_position.x, w.global_position.z).length()
		assert_true(stop < lunge_stop_m(p) + 0.2, "stage %d: it stopped at the giant's feet (%.2f m)" % [stage, stop])
		var window_end := Sim.tick + lunge.recovery_ticks
		for i in 3:
			var light_id := "ability.light_%d" % (i + 1)
			p.router.inject_light_attack()
			var swung: bool = await TestWait.until(self, func() -> bool:
				return p.controller.action != null and p.controller.action.id == light_id \
					and p.controller.phase() == ActionDef.Phase.RECOVERY, 60)
			assert_true(swung, "stage %d: %s ran" % [stage, light_id])
		var hit_tick := {}
		for r in hits_on(id):
			hit_tick[r.event.action_id] = r.event.tick
		for light_id: String in ["ability.light_1", "ability.light_2"]:
			assert_true(hit_tick.has(light_id) and int(hit_tick[light_id]) <= window_end,
				"stage %d: %s lands in the recovery window (hits %s)" % [stage, light_id, hit_tick])
		assert_true(hit_tick.has("ability.light_3"), "stage %d: and the third blow connects (hits %s)" % [stage, hit_tick])
		p.queue_free()
		w.queue_free()
		await step_ticks(2)
