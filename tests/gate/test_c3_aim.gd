extends IntegrationSuite
## C3 (decision C3-4): the aim indicator tells the truth. With no lock, the cursor (the screen centre's ray from the
## camera) is put on a man, a breakable and a titan's plate at every stage 1-8 (TitanDuel.prepare: the stage, its
## level and weapon), for the light and the heavy; the swing plan the HUD's aim indicator draws
## (PlayerAttack.next_swing_plan) names what the swing will strike, then the swing is made and what it struck is
## compared: the same entities in the same order, the titan's plate the same region, and a target it says is out of
## reach is not struck. Every target stands still (the plan cannot know where a moving one will be).
## C3b (decision C3b-1): a man, a wolf and a fence at the giant's feet and at half his reach are struck at every stage
## 1-8 (the light; the heavy at a man) - by the swing, or by the stamp or the stomp the plan puts in its place when the
## arc would pass over them - and the indicator names what does it.

const STONEBACK := "res://scenes/enemies/stoneback.tscn"
const WOLF := "res://scenes/enemies/wolf.tscn"

var _log: Array = []
var _last_strike := ""


## Puts the cursor on `point`: the camera's yaw and pitch so the screen centre's ray passes through it (the
## camera's place depends on them: a few rounds).
## Returns false when the camera cannot look that steeply (its pitch limits).
func _aim_at(p: GiantPlayer, point: Vector3) -> bool:
	var ok := true
	for i in 6:
		await get_tree().process_frame
		var from := p.camera_rig.global_position
		var d := point - from
		p.camera_rig.yaw = TargetingRules.yaw_of(Vector3(d.x, 0.0, d.z))
		var want := atan2(d.y, Vector2(d.x, d.z).length())
		p.camera_rig.pitch = clampf(want, deg_to_rad(CameraRig.TP_PITCH_MIN), deg_to_rad(CameraRig.TP_PITCH_MAX))
		ok = is_equal_approx(p.camera_rig.pitch, want)
	await get_tree().process_frame
	return ok


func _idle(p: GiantPlayer) -> void:
	await TestWait.until(self, func() -> bool: return p.controller.state == CombatController.State.LOCOMOTION, 240)
	await step_ticks(45)   # past every chain window: the next press is the first light


## Swings (`heavy`) and returns the entities and regions struck, in order: [[entity_id, region]].
func _swing(p: GiantPlayer, heavy: bool) -> Array:
	var before := hits.size()
	p.router.inject_edge(&"heavy" if heavy else &"light")
	await step_ticks(2)
	var instance := p.controller.instance_id
	await TestWait.until(self, func() -> bool: return p.controller.state == CombatController.State.LOCOMOTION, 240)
	await step_ticks(4)
	var out: Array = []
	var seen := {}
	for i in range(before, hits.size()):
		var e := hits[i].event
		if e.attacker_id != p.entity.entity_id or e.instance_id != instance or seen.has(e.target_id):
			continue
		seen[e.target_id] = true
		out.append([e.target_id, e.region if e.plate_id != "" else ""])
	return out


static func _predicted(plan: Dictionary) -> Array:
	var out: Array = []
	for s: Dictionary in plan.get("struck", []):
		var e: CombatEntity = s.entity
		out.append([e.entity_id, str(s.region) if e.plates != null else ""])
	return out


## One case: the plan, the swing, the comparison. Returns the plan's primary id ("" for nothing).
func _case(p: GiantPlayer, what: String, target: CombatEntity, aim: Vector3, heavy: bool) -> String:
	await _idle(p)
	var placed := await _aim_at(p, aim)
	var plan: Dictionary = p.attack.next_swing_plan(heavy)
	var predicted := _predicted(plan)
	var prim: CombatEntity = plan.get("primary")
	var struck := await _swing(p, heavy)
	var tag := "stage %d %s %s" % [p.growth_stage, "heavy" if heavy else "light", what]
	_last_strike = str(plan.get("strike", "swing"))
	_log.append("%s: plan %s %s %s (%s) -> struck %s" % [tag, plan.get("source", ""), _last_strike, predicted,
		"reaches" if plan.reaches else "out of reach", struck])
	if placed:
		assert_true(str(plan.source) in ["cursor", "soft"], "%s: the cursor is on it (%s)" % [tag, plan.source])
		assert_true(plan.get("entity") == target, "%s: the plan aims at it" % tag)
	else:
		_log.append("%s: the camera cannot look that steeply: no cursor on it" % tag)
	assert_eq(struck, predicted, "%s: struck what the indicator showed" % tag)
	if bool(plan.reaches):
		assert_true(prim == target, "%s: the indicator shows it struck" % tag)
		assert_true(not struck.is_empty() and str(struck[0][0]) == target.entity_id or struck.any(func(x: Array) -> bool: return str(x[0]) == target.entity_id),
			"%s: and it was struck" % tag)
	else:
		assert_false(struck.any(func(x: Array) -> bool: return str(x[0]) == target.entity_id),
			"%s: out of reach, not struck" % tag)
	return prim.entity_id if prim != null else ""


func test_the_indicated_target_is_the_struck_target_at_every_stage() -> void:
	var p := spawn_player(Vector3(0, 0.05, 0), 0.0)
	await TestWait.until(self, func() -> bool: return p.is_on_floor(), 30)
	var reached := {"man": 0, "prop": 0, "titan": 0}
	var cases := 0
	for stage in range(1, 9):
		TitanDuel.prepare(p, stage)
		await step_ticks(150)   # the camera's arm restores to the new stage's length
		p.global_position = Vector3(0, 0.05, 0)
		p.facing_yaw = 0.0
		p.rotation.y = 0.0
		await step_ticks(4)
		var reach := float(p.profile.get("melee_reach_m", 3.5))
		for heavy: bool in [false, true]:
			# a man a little left of straight ahead, at half the swing's reach for the light, nearer for the heavy
			# (his chest under the cursor)
			var d := maxf(1.6, reach * (0.45 if heavy else 0.6))
			var man := spawn_soldier(Vector3(-d * sin(0.15), 0.05, -d * cos(0.15)), PI, "c3.man_%d_%s" % [stage, heavy])
			await step_ticks(6)
			if await _case(p, "man", man.entity, man.entity.anchor_position(), heavy) != "":
				reached.man += 1
			cases += 1
			man.queue_free()
			await step_ticks(4)
			# a fence to the right, its rails under the cursor
			var fence := spawn_fence(Vector3(d * sin(0.2), 0.0, -d * cos(0.2)), "c3.fence_%d_%s" % [stage, heavy], 0.2)
			await step_ticks(6)
			if await _case(p, "prop", fence.entity, fence.global_position + Vector3.UP * 0.8, heavy) != "":
				reached.prop += 1
			cases += 1
			fence.queue_free()
			await step_ticks(4)
		# a titan before the giant: the cursor on the plate nearest the swing's height, light and heavy
		var t := (load(STONEBACK) as PackedScene).instantiate() as TitanEnemy
		t.entity_id = "c3.titan_%d" % stage
		t.position = Vector3(0, 0.05, -(reach * 0.5 + 3.0))
		t.rotation.y = 0.0
		world.add_child(t)
		await step_ticks(6)
		t.set("ai_enabled", false)
		var plate := _plate_near(t, p.global_position.y + p.weapon_pivot.y)
		for heavy: bool in [false, true]:
			if await _case(p, "titan plate %s" % plate.region, t.entity, plate.global_position, heavy) != "":
				reached.titan += 1
			cases += 1
		t.queue_free()
		await step_ticks(6)
	for line: String in _log:
		print("    " + line)
	assert_eq(cases, 48, "every stage, both swings, three targets")
	# (C3: a colossus's swing did not come down to a man or a fence before its feet at stages 7 and 8 - the oak club past
	# its fit; C3b: TitanDuel gives them the titanforged club the campaign's colossus carries, and the stamp or the stomp
	# takes what the swing would pass over - every stage reaches them)
	assert_eq(int(reached.man), 16, "the man is reached at every stage (%d of 16)" % int(reached.man))
	assert_eq(int(reached.prop), 16, "the fence is reached at every stage (%d of 16)" % int(reached.prop))
	assert_true(int(reached.titan) >= 8, "a titan's plate is reached at the bigger stages (%d of 16)" % int(reached.titan))


## The titan's plate hurtbox whose centre stands nearest `height` (the giant's swing height).
static func _plate_near(t: TitanEnemy, height: float) -> Hurtbox:
	var best: Hurtbox = null
	for hb: Hurtbox in PlayerAttack._hurtboxes_of(t.entity):
		if best == null or absf(hb.global_position.y - height) < absf(best.global_position.y - height):
			best = hb
	return best


## C3b: a body at the giant's feet and at half his reach, at every stage: the swing or the low strike in its place
## strikes it, as the indicator says.
func test_what_stands_at_the_feet_is_struck_at_every_stage() -> void:
	var p := spawn_player(Vector3(0, 0.05, 0), 0.0)
	await TestWait.until(self, func() -> bool: return p.is_on_floor(), 30)
	var struck := 0
	var cases := 0
	var low := {}
	for stage in range(1, 9):
		TitanDuel.prepare(p, stage)
		await step_ticks(150)
		p.global_position = Vector3(0, 0.05, 0)
		p.facing_yaw = 0.0
		p.rotation.y = 0.0
		await step_ticks(4)
		var reach := float(p.profile.get("melee_reach_m", 3.5))
		var cap := float(p.profile.get("capsule_radius_m", 0.85))
		for what: String in ["man", "wolf", "fence"]:
			for where: String in ["feet", "mid"]:
				for heavy: bool in ([false, true] if what == "man" else [false]):
					var side := -0.18 if what == "man" else (0.22 if what == "fence" else 0.05)
					var d := cap + 1.0 if where == "feet" else maxf(cap + 1.6, reach * 0.5)
					var at := Vector3(d * sin(side), 0.05, -d * cos(side))
					var id := "c3b.%s_%s_%d_%s" % [what, where, stage, heavy]
					var target: CombatEntity = null
					var node: Node3D = null
					var aim := Vector3.ZERO
					match what:
						"man":
							node = spawn_soldier(at, PI, id)
						"wolf":
							var w := (load(WOLF) as PackedScene).instantiate() as EnemyActor
							w.entity_id = id
							w.set("ai_enabled", false)
							w.position = at
							w.rotation.y = PI
							world.add_child(w)
							node = w
						"fence":
							node = spawn_fence(Vector3(at.x, 0.0, at.z), id, side)
					await step_ticks(6)
					target = node.get("entity") as CombatEntity
					aim = target.anchor_position() if what != "fence" else node.global_position + Vector3.UP * 0.8
					var prim := await _case(p, "%s at the %s" % [what, where], target, aim, heavy)
					cases += 1
					var tag := "stage %d %s %s at the %s" % [stage, "heavy" if heavy else "light", what, where]
					assert_eq(prim, target.entity_id, "%s: struck" % tag)
					if prim == target.entity_id:
						struck += 1
					if _last_strike != "swing":
						low[_last_strike] = int(low.get(_last_strike, 0)) + 1
					if is_instance_valid(node):
						node.queue_free()
					await step_ticks(4)
	for line: String in _log:
		print("    " + line)
	print("    low strikes: %s" % low)
	assert_eq(cases, 64, "eight stages, three bodies at two distances, the heavy at the man")
	assert_eq(struck, cases, "every one struck (%d of %d)" % [struck, cases])
	assert_true(int(low.get("stamp", 0)) > 0 and int(low.get("stomp", 0)) > 0, "the stamp and the stomp both struck")
