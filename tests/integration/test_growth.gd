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
var loadout_events := 0


func before_each() -> void:
	await super()
	growth_events.clear()
	blocked_events.clear()
	learned_events.clear()
	messages.clear()
	loadout_events = 0
	# P08 caps weapons at their fit stage; these tests measure the full-size club at stage 3.
	TestFixtures.record_override("weapon.club", {"fit_max_stage": 3})
	Events.growth_changed.connect(_on_growth)
	Events.growth_blocked.connect(_on_blocked)
	Events.ability_learned.connect(_on_learned)
	Events.hud_message.connect(_on_message)
	Events.loadout_changed.connect(_on_loadout)


func after_each() -> void:
	for sig: Signal in [Events.growth_changed, Events.growth_blocked, Events.ability_learned, Events.hud_message,
			Events.loadout_changed]:
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


func _on_loadout(_t: int, _id: String) -> void:
	loadout_events += 1


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
	assert_eq(p.entity.combatant.mass_class, "large", "the giant is a large mass (the player schema's default)")
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
	var trap := (course.get_node("Markers/TrapPoint") as Node3D).global_position
	p.global_position = trap + Vector3(0, 0.05, 0)
	p.velocity = Vector3.ZERO
	await step_ticks(20)
	assert_true(p.is_on_floor(), "standing in the trap alcove (6 m ceiling)")
	var two := shrine.grow(p, 2)
	assert_true(two.ok, "a 5.49 m stage-2 giant still fits under the 6 m ceiling (%s)" % two.message)
	await step_ticks(10)
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


# --------------------------------------------------------------------------- camera

## Footstep shake goes through camera_rig.add_shake, which the camera_shake setting scales:
## with the setting at 0 the camera's local transform stays identity while a stage-3 giant
## walks; at 1 it does not. A stage-1 giant (footstep_shake 0) never shakes.
func test_footstep_shake_follows_the_camera_shake_setting() -> void:
	var p := await _grounded_player(Vector3(0, 0.05, 30))
	var shaken_stage_1 := await _walk_and_count_shake(p, 1.0, 90)
	assert_eq(shaken_stage_1, 0, "stage 1 (footstep_shake 0) never shakes the camera")
	assert_true(p.growth.debug_set_stage(3).ok, "stage 3")
	await step_ticks(20)
	var steps_before := p.rig.footfalls
	var shaken_off := await _walk_and_count_shake(p, 0.0, 150)
	assert_true(p.rig.footfalls > steps_before, "the stage-3 giant took steps (%d)" % (p.rig.footfalls - steps_before))
	assert_eq(shaken_off, 0, "camera_shake 0: the camera's local transform stays identity")
	var shaken_on := await _walk_and_count_shake(p, 1.0, 150)
	assert_true(shaken_on > 0, "camera_shake 1: footfalls shake the camera (%d frames)" % shaken_on)


func _walk_and_count_shake(p: GiantPlayer, setting: float, ticks: int) -> int:
	Settings.values["camera_shake"] = setting
	var shaken := 0
	p.camera_rig.yaw = 0.0
	p.router.set_injected_move(Vector2(0, 1))
	for i in ticks:
		await step_ticks(1)
		if not p.camera_rig.camera.transform.is_equal_approx(Transform3D.IDENTITY):
			shaken += 1
	p.router.set_injected_move(Vector2.ZERO)
	await step_ticks(30)
	return shaken


## A wall right behind the giant cuts the third-person arm below 1.2 x the capsule radius: the
## camera then hides render layer 2 (head, chest, belt), as first person does, and shows it
## again once the arm grows back out.
func test_camera_hides_the_head_while_the_arm_is_pressed_short() -> void:
	var p := await _grounded_player(Vector3(0, 0.05, 0))
	await step_ticks(60)
	var head := p.get_node("Visual/Body/Torso/Head") as MeshInstance3D
	var cam := p.camera_rig.camera
	assert_false(p.camera_rig.head_hidden, "an open view shows the head")
	assert_true((head.layers & cam.cull_mask) != 0, "the head is drawn")
	var wall := add_box(Vector3(10, 10, 1), Vector3(0, 5, 1.6))   # the camera sits behind (+Z)
	await step_ticks(3)
	assert_true(p.camera_rig.current_distance < 1.2 * 0.85, "the arm is pressed short (%.2f m)" % p.camera_rig.current_distance)
	assert_true(p.camera_rig.head_hidden, "the camera hides the head")
	assert_eq(head.layers & cam.cull_mask, 0, "the head is not drawn")
	var arm := p.get_node("Visual/Body/ShoulderR/Mesh") as MeshInstance3D   # P22: the merged arm
	assert_true((arm.layers & cam.cull_mask) != 0, "the arms stay drawn")
	wall.queue_free()
	await step_ticks(90)
	assert_false(p.camera_rig.head_hidden, "the arm grew back: the head shows again (arm %.2f m)" % p.camera_rig.current_distance)
	assert_true((head.layers & cam.cull_mask) != 0, "drawn again")


## Growth keeps the camera's zoom fraction and never snaps the arm: right after growing, the
## arm is still the old length and then grows out at the restore speed.
func test_camera_zoom_fraction_kept_and_arm_never_snaps() -> void:
	var s := _shrine(Vector3(0, 0, -12))
	var p := await _grounded_player(Vector3(0, 0.05, 0))
	await step_ticks(60)
	p.camera_rig.zoom(1)
	p.camera_rig.zoom(1)
	await step_ticks(60)
	var g1 := _profile(1)
	var g2 := _profile(2)
	var frac := (p.camera_rig.desired_distance - float(g1.camera_zoom_min_m)) / (float(g1.camera_zoom_max_m) - float(g1.camera_zoom_min_m))
	var arm_before := p.camera_rig.current_distance
	assert_true(s.grow(p, 2).ok, "grow")
	assert_near(p.camera_rig.current_distance, arm_before, 1e-6, "the arm is not snapped by the growth")
	assert_near(p.camera_rig.desired_distance,
		lerpf(float(g2.camera_zoom_min_m), float(g2.camera_zoom_max_m), frac), 1e-4, "the zoom fraction is kept")
	await step_ticks(10)
	var mid := p.camera_rig.current_distance
	assert_true(mid > arm_before and mid < p.camera_rig.desired_distance, "the arm grows out smoothly (%.2f m)" % mid)


# --------------------------------------------------------------------------- unlocks, keys, state

func test_growth_unlocks_are_learned_slotted_and_announced_once() -> void:
	var rec := GameData.get_record("ability.stone_skin").duplicate(true)
	rec["id"] = "ability.test_growth_unlock"
	rec["display_name"] = "Test Unlock"
	TestFixtures.record_override("ability.test_growth_unlock", rec)
	TestFixtures.record_override("growth.02", {"unlocks": ["ability.test_growth_unlock", "ability.runic_bolt"]})
	var s := _shrine(Vector3(0, 0, -12))
	var p := await _grounded_player(Vector3(0, 0.05, 0))
	# Since P07 the sandbox giant has all eight slots filled (Crushing Grip 4, Boulder Hurl 5):
	# empty one, so the auto-slot has somewhere to go.
	p.set_loadout_slot("slot_5", "")
	var id := "ability.test_growth_unlock"
	var slot := PlayerGrowth.first_empty_slot(p.controller.loadout)
	assert_true(slot != "", "the sandbox loadout has an empty slot (%s)" % slot)
	assert_false(p.known_abilities.has(id), "not known before growing")
	var r := s.grow(p, 2)
	assert_true(r.ok, "grow")
	assert_true(p.known_abilities.has(id), "learned")
	assert_true(p.controller.library.has(id), "in the controller's library")
	assert_eq(str(p.controller.loadout[slot]), id, "put into the first empty slot")
	assert_eq(learned_events, [[id, slot]], "ability_learned once; Runic Bolt was known and slotted already")
	assert_eq(r.summary.learned, [{"id": id, "slot": slot}], "the growth summary lists it")
	assert_eq(loadout_events, 1, "loadout_changed for the auto-slot")
	assert_true(", ".join(r.summary.lines).contains("Test Unlock"), "by name")
	assert_true(s.grow(p, 3).ok, "grow on")
	assert_true(p.growth.debug_set_stage(1).ok, "shrink")
	assert_true(p.known_abilities.has(id), "shrinking keeps what was learned")
	assert_true(p.growth.debug_set_stage(2).ok, "grow again")
	assert_eq(learned_events.size(), 1, "never learned twice")


func test_debug_keys_grow_and_shrink() -> void:
	var p := await _grounded_player(Vector3(0, 0.05, 0))
	for expected in [2, 3]:
		p.router.inject_edge(&"debug_grow")
		await step_ticks(2)
		assert_eq(p.growth_stage, expected, "F6 grows to stage %d" % expected)
		assert_true(messages.has("DEBUG: stage %d" % expected), "and says so")
	p.router.inject_edge(&"debug_grow")
	await step_ticks(2)
	assert_eq(p.growth_stage, 3, "no stage 4 profile: stays stage 3")
	assert_eq(blocked_events.back()[1], "no_profile", "growth_blocked no_profile")
	for expected in [2, 1]:
		p.router.inject_edge(&"debug_shrink")
		await step_ticks(2)
		assert_eq(p.growth_stage, expected, "F7 shrinks to stage %d" % expected)
	p.router.inject_edge(&"debug_shrink")
	await step_ticks(2)
	assert_eq(p.growth_stage, 1, "nothing below stage 1")
	assert_eq(growth_events, [["player", 1, 2], ["player", 2, 3], ["player", 3, 2], ["player", 2, 1]],
		"growth_changed for every change and none for the refusals")
	p.entity.combatant.pools.mark_combat()
	p.router.inject_edge(&"debug_grow")
	await step_ticks(2)
	assert_eq(p.growth_stage, 2, "the debug key ignores the combat gate")


func test_growth_stage_round_trips_through_the_character_state() -> void:
	var s := _shrine(Vector3(0, 0, -12))
	var p := await _grounded_player(Vector3(0, 0.05, 0))
	assert_true(s.grow(p, 2).ok, "grow")
	var out := p.capture_character_state()
	assert_eq(int(out.growth_stage), 2, "capture writes growth_stage")
	p.queue_free()
	await step_ticks(2)
	var q := await _grounded_player(Vector3(8, 0.05, 0))
	growth_events.clear()
	learned_events.clear()
	q.apply_character_state({"growth_stage": 3, "resources": {"health": 700.0, "stamina": 50.0,
		"essence": 20.0, "fury": 0.0}})
	assert_eq(q.growth_stage, 3, "the saved stage is restored")
	var pools := q.entity.combatant.pools
	assert_near(pools.health_max, 800.0, 1e-4, "with the stage-3 maxima")
	assert_near(pools.health, 700.0, 1e-4, "and the saved resources applied after it (absolute)")
	assert_near(pools.stamina, 50.0, 1e-4, "stamina")
	assert_eq(growth_events.size(), 0, "a restore is silent: no growth_changed (no checkpoint, no notice)")
	assert_eq(learned_events.size(), 0, "and teaches nothing")
	assert_eq(q.nav_layers, 4, "nav layers follow the restored stage")
	assert_eq(int(q.capture_character_state().growth_stage), 3, "and capture reports it")


## The rig shows the tilted arc: during the ACTIVE phase of a stage-3 light 1 (tilt -16) and
## heavy (tilt -12), the weapon arm points exactly along the swept weapon segment, and the
## scaled shoulder sits on the profile's pivot.
func test_the_rig_shows_the_tilted_arc_at_stage_3() -> void:
	var p := await _grounded_player(Vector3(0, 0.05, 0))
	assert_true(p.growth.debug_set_stage(3).ok, "stage 3")
	await step_ticks(3)
	var shoulder := p.get_node("Visual/Body/ShoulderR") as Node3D
	assert_true(shoulder.global_position.is_equal_approx(p.to_global(p.weapon_pivot)), "the shoulder is on the pivot")
	for attack_id: String in ["ability.light_1", "ability.heavy_1"]:
		var a := GameData.get_action(attack_id)
		p.entity.combatant.pools.stamina = p.entity.combatant.pools.stamina_max
		p.controller.request(&"attack", {"action_id": attack_id})
		var active: bool = await TestWait.until(self, func() -> bool:
			return p.controller.phase() == ActionDef.Phase.ACTIVE and p.controller.elapsed > a.windup_ticks + 2, 60)
		assert_true(active, "%s is active" % attack_id)
		# The test resumes on process_frame, before the nodes' _process: the rig still shows the
		# previous tick, whose arc fraction is active_fraction_prev().
		var seg := p.weapon_segment_global(a, p.controller.active_fraction_prev())
		var swept := (seg[1] - seg[0]).normalized()
		var arm := -shoulder.global_transform.basis.z.normalized()
		assert_true(rad_to_deg(arm.angle_to(swept)) < 1.0, "%s: the arm points along the swept segment (%.2f degrees off)" % [
			attack_id, rad_to_deg(arm.angle_to(swept))])
		assert_near(float(p.get_rig_state().arc_pitch_offset_deg), PlayerAttack.offset_for(p.profile, attack_id), 1e-9,
			"%s: the rig reads the action's tilt" % attack_id)
		await TestWait.until(self, func() -> bool: return p.controller.action == null, 90)
