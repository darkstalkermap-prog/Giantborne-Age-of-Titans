extends IntegrationSuite
## Grab, hold, throw and Crushing Grip (plan §3.7, decision 16, spec §8 and §15): every invalid
## grab spends nothing and names its reason; a heavy that breaks a soldier's poise followed by E
## grabs it at stages 1, 2 and 3; the held body sits in the hand, out of the simulation; an
## interrupted grab releases both entities; a throw into a second soldier hits each once through
## HitFactory and never lands inside geometry; Crushing Grip's damage and release; a stage-3 giant
## grabs and throws an ogre-sized stub that a stage-2 one cannot; growth, checkpoint and scene
## unload all let go cleanly.

const WOLF := "res://scenes/enemies/wolf.tscn"
const GRAB_ID := "ability.grab_hold"
const THROW_ID := "ability.throw_held"
const GRIP_ID := "ability.crushing_grip"

var grabs: Array[Array] = []      ## [tick, holder, target]
var ended: Array[Array] = []      ## [tick, holder, target, reason]
var rejected: Array[Array] = []   ## [actor, action, reason]
var messages: Array[String] = []


func before_each() -> void:
	await super()
	grabs.clear()
	ended.clear()
	rejected.clear()
	messages.clear()
	Events.grab_started.connect(_on_grab_started)
	Events.grab_ended.connect(_on_grab_ended)
	Events.action_rejected.connect(_on_rejected)
	Events.hud_message.connect(_on_message)


func after_each() -> void:
	for sig: Signal in [Events.grab_started, Events.grab_ended, Events.action_rejected, Events.hud_message]:
		for c: Dictionary in sig.get_connections():
			if (c.callable as Callable).get_object() == self:
				sig.disconnect(c.callable)
	await super()


func _on_grab_started(t: int, holder: String, target: String) -> void:
	grabs.append([t, holder, target])


func _on_grab_ended(t: int, holder: String, target: String, reason: String) -> void:
	ended.append([t, holder, target, reason])


func _on_rejected(_t: int, actor: String, action_id: String, reason: String) -> void:
	rejected.append([actor, action_id, reason])


func _on_message(text: String, _kind: String) -> void:
	messages.append(text)


# --------------------------------------------------------------------------- helpers

func _profile(stage: int) -> Dictionary:
	for rec: Dictionary in GameData.records_of_type("growth_profile"):
		if int(rec.get("stage", 0)) == stage:
			return rec
	return {}


## A giant of `stage` standing on the floor at `pos`, facing -Z (yaw 0).
func _giant(stage := 1, pos := Vector3(0, 0.05, 0), yaw := 0.0) -> GiantPlayer:
	var p := spawn_player(pos, yaw)
	if stage != 1:
		p.set_profile(_profile(stage))
	await TestWait.until(self, func() -> bool: return p.is_on_floor(), 40)
	await step_ticks(1)
	return p


func _soldier_at(pos: Vector3, id: String, face := Vector3.ZERO) -> SoldierEnemy:
	return spawn_soldier(pos, yaw_towards(pos, face), id)


## An enemy record built from the soldier's with `patch` (its id enemy.test_<name>), spawned as a
## stub on the soldier's body.
func _stub(pos: Vector3, id: String, patch: Dictionary) -> EnemyActor:
	var rec_id := "enemy.test_%s" % id.replace(".", "_")
	var rec := GameData.get_record("enemy.soldier").duplicate(true)
	rec["id"] = rec_id
	for k: String in patch:
		rec[k] = patch[k]
	TestFixtures.record_override(rec_id, rec)
	return TestSpawn.stub_enemy(world, pos, id, false, rec_id, yaw_towards(pos, Vector3.ZERO))


func _stagger(e: EnemyActor, seconds := 2.0) -> void:
	e.entity.stagger(seconds, "test")


## Grabs `e` (staggered first): the request, then the windup until the hand closes.
func _grab(p: GiantPlayer, e: EnemyActor) -> bool:
	if e.controller.state != CombatController.State.STAGGERED:
		_stagger(e, 3.0)
	if p.grab.try_grab() != CombatController.Verdict.ACCEPT:
		return false
	return await TestWait.until(self, func() -> bool: return p.grab.is_holding(), 40)


func _wait_free(p: GiantPlayer) -> void:
	await TestWait.until(self, func() -> bool:
		return p.controller.state == CombatController.State.LOCOMOTION and p.controller.action == null, 90)


func _hits_from(target_id: String, action_id: String) -> Array[HitResult]:
	var out: Array[HitResult] = []
	for r in hits:
		if r.event.target_id == target_id and r.event.action_id == action_id:
			out.append(r)
	return out


## The soldier's own capsule check (the same one a release uses).
func _spot_is_free(e: EnemyActor) -> bool:
	return e.is_free_spot(e.global_position)


# --------------------------------------------------------------------------- data

func test_grab_data_schema_and_scenes() -> void:
	var grab := action(GRAB_ID)
	assert_eq(grab.hit_shape, "grab", "grab_hold runs the grab shape (EXECUTING)")
	assert_eq([grab.windup_ticks, grab.active_ticks, grab.recovery_ticks], [15, 6, 12], "0.25 / 0.10 / 0.20 s")
	assert_eq(grab.stamina_cost, 0.0, "no stamina cost")
	assert_eq(CombatController._timeline_state_for(grab), CombatController.State.EXECUTING, "EXECUTING")
	var grip := action(GRIP_ID)
	assert_eq([grip.power, grip.ability_multiplier, grip.stamina_cost, grip.cooldown_s], [40.0, 1.5, 20.0, 10.0],
		"Crushing Grip: P40 x 1.5, 20 stamina, 10 s")
	assert_true(grip.has_tag("Grab"), "tag Grab")
	assert_eq(PlayerGrab.max_mass_of(grip), "small", "crushes only small targets")
	assert_true(PlayerGrab.is_crush(grip) and not PlayerGrab.is_crush(grab), "crush vs hold")
	var throw := action(THROW_ID)
	assert_eq(throw.category, "projectile", "a throw is a projectile")
	assert_eq(throw.stamina_cost, 12.0, "12 stamina")
	assert_eq(str(Projectile.spec_for(throw).visual), "thrown_body", "visual thrown_body")
	assert_eq(str(Projectile.spec_for(throw).aim), "lock_or_camera", "aimed like Boulder Hurl")
	assert_eq(GameData.get_record("enemy.soldier").get("grab_attach"), "torso_fist", "soldiers: torso_fist")
	assert_eq(GameData.get_record("enemy.wolf").get("grab_attach"), "scruff", "wolves: scruff")
	assert_near(float(GameData.get_record("enemy.soldier").poise.stagger_vs_larger_s), 1.5, 1e-9,
		"a giant's poise break staggers a soldier 1.5 s")
	var slots: Array = GameData.get_record("player.giant").loadout.slots
	assert_eq([slots[3], slots[4]], ["ability.crushing_grip", "ability.boulder_hurl"], "slots 4 and 5")
	var library: Array = GameData.get_record("progression.default").ability_library
	assert_true(library.has(GRIP_ID) and library.has("ability.boulder_hurl"), "both in the ability library")
	assert_eq(_profile(2).unlocks, ["ability.boulder_hurl"], "stage 2 unlocks Boulder Hurl")
	for path: String in [SOLDIER, WOLF]:
		var n := (load(path) as PackedScene).instantiate()
		assert_true(n.get_node_or_null("Anchors/Grab") is Marker3D, "%s has Anchors/Grab" % path)
		n.free()
	# Schema: the grab block and grab_attach.
	var rec := GameData.get_record(GRIP_ID).duplicate(true)
	rec.erase("grab")
	var r := DataValidator.validate_record(rec, "test")
	assert_true("\n".join(r.errors).contains("'grab' is required for hit_shape 'grab'"), "grab shape needs a grab block")
	rec = GameData.get_record(THROW_ID).duplicate(true)
	rec["grab"] = {"mode": "hold"}
	r = DataValidator.validate_record(rec, "test")
	assert_true("\n".join(r.errors).contains("a 'grab' block needs hit_shape 'grab'"), "and only a grab shape has one")
	rec = GameData.get_record(GRIP_ID).duplicate(true)
	rec["grab"] = {"mode": "squeeze", "max_mass": "huge"}
	r = DataValidator.validate_record(rec, "test")
	assert_eq(r.errors.size(), 2, "bad mode and mass class: %s" % "\n".join(r.errors))
	var enemy := GameData.get_record("enemy.wolf").duplicate(true)
	enemy["grab_attach"] = "tail"
	assert_eq(DataValidator.validate_record(enemy, "test").errors.size(), 1, "grab_attach is a GRAB_ATTACH value")
	enemy["grab_attach"] = "two_hand"
	assert_eq(DataValidator.validate_record(enemy, "test").errors.size(), 0, "two_hand validates")


# --------------------------------------------------------------------------- eligibility

## Every refusal (find_candidate and the real request) spends nothing, starts no cooldown,
## changes no state and names its reason (spec §15: invalid grabs spend nothing).
func _expect_refusal(p: GiantPlayer, reason: String, what: String, slot := 0) -> void:
	var pools := p.entity.combatant.pools
	pools.stamina = pools.stamina_max
	var stamina := pools.stamina
	rejected.clear()
	var mode := "crush" if slot > 0 else "hold"
	assert_eq(str(p.grab.find_candidate(mode, "small" if slot > 0 else "").reason), reason,
		"%s: find_candidate says %s" % [what, reason])
	var v: int = p.grab.try_slot("slot_%d" % slot) if slot > 0 else p.grab.try_grab()
	assert_eq(v, CombatController.Verdict.REJECT, "%s: the request is refused" % what)
	assert_eq(p.controller.last_reject_reason, reason, "%s: with reason %s" % [what, reason])
	assert_eq(rejected.back() if not rejected.is_empty() else [], ["player", GRIP_ID if slot > 0 else GRAB_ID, reason],
		"%s: action_rejected reports it" % what)
	assert_near(pools.stamina, stamina, 1e-6, "%s: no stamina spent" % what)
	assert_true(p.controller.cooldowns.is_ready(GRIP_ID, Sim.tick), "%s: no cooldown started" % what)
	assert_eq(p.controller.state, CombatController.State.LOCOMOTION, "%s: the giant stays in locomotion" % what)
	assert_false(p.grab.is_holding(), "%s: nothing held" % what)
	assert_eq(grabs.size(), 0, "%s: no grab_started" % what)


func test_invalid_grabs_spend_nothing_and_name_their_reason() -> void:
	var p := await _giant(1)
	_expect_refusal(p, "nothing_in_reach", "no enemy at all")
	var far := _soldier_at(Vector3(0, 0.05, -6.6), "test.far")
	_stagger(far)
	_expect_refusal(p, "nothing_in_reach", "a staggered soldier beyond reach + lunge (6.6 > 4 + 2)")
	far.queue_free()
	# Behind a wall: the eye cannot see the grab point.
	var wall := add_box(Vector3(4, 6, 0.3), Vector3(0, 3, -1.8))
	var hidden := _soldier_at(Vector3(0, 0.05, -3.2), "test.hidden")
	_stagger(hidden)
	_expect_refusal(p, "no_los", "behind a wall")
	hidden.queue_free()
	wall.queue_free()
	await step_ticks(1)
	var cases := [
		["too_tall", {"height_m": 2.4}, "a 2.4 m stub against a 3.66 m giant"],
		["too_heavy", {"mass_class": "medium"}, "a medium stub at stage 1 (capacity small)"],
		["immune", {"immunities": ["Grab"]}, "a stub immune to Grab"],
		["no_attach_profile", {"grab_attach": "none"}, "a stub with grab_attach none"],
		["no_attach_profile", {"grab_attach": "two_hand"}, "a two_hand stub at stage 1"],
	]
	for i in cases.size():
		var c: Array = cases[i]
		var s := _stub(Vector3(0, 0.05, -3.0), "test.stub_%d" % i, c[1])
		await step_ticks(1)
		_stagger(s)
		_expect_refusal(p, c[0], c[2])
		s.queue_free()
		await step_ticks(1)
	var calm := _soldier_at(Vector3(0, 0.05, -3.0), "test.calm")
	await step_ticks(1)
	_expect_refusal(p, "not_staggered", "a soldier whose poise is not broken")
	# E on it: refused through the controller, with the reason on the HUD.
	messages.clear()
	p.router.inject_edge(&"interact")
	await step_ticks(2)
	assert_eq(p.controller.last_reject_reason, "not_staggered", "E reports not_staggered")
	assert_true(messages.has(PlayerGrab.reason_text("not_staggered")), "and the HUD says why: %s" % [messages])
	assert_false(p.grab.is_holding(), "nothing held")
	calm.entity.combatant.pools.health = 1.0
	queue_hit("player", "test.calm", p.global_position, 50.0)
	await step_ticks(2)
	assert_false(calm.entity.is_alive(), "killed")
	_expect_refusal(p, "not_grabbable", "a corpse")
	calm.queue_free()
	await step_ticks(1)


func test_attachment_and_crush_limits_by_stage() -> void:
	var p := await _giant(2)
	var two := _stub(Vector3(0, 0.05, -3.5), "test.two_hand", {"grab_attach": "two_hand"})
	await step_ticks(1)
	_stagger(two)
	_expect_refusal(p, "no_attach_profile", "a two_hand stub at stage 2")
	two.queue_free()
	p.queue_free()
	await step_ticks(2)
	var big := await _giant(3)
	var ogre := _stub(Vector3(0, 0.05, -4.5), "test.ogre", {"height_m": 3.4, "mass_class": "medium",
		"grab_attach": "two_hand"})
	await step_ticks(1)
	_stagger(ogre)
	_expect_refusal(big, "too_heavy_to_crush", "Crushing Grip on a staggered medium stub at stage 3", 4)
	assert_eq(str(big.grab.find_candidate("hold").reason), "", "but a stage-3 giant can lift it")


# --------------------------------------------------------------------------- the grab

## Heavy, then E straight away (it waits through the heavy's recovery): the stagger against a
## giant twice the soldier's height lasts 1.5 s and the lunge covers the knockback, so the hand
## closes inside it, at stages 1, 2 and 3.
func test_heavy_then_e_grabs_a_soldier_at_every_stage() -> void:
	# P08 caps weapons at their fit stage; this test needs the full-size club's heavy at stage 3
	# (as P05's growth tests do).
	TestFixtures.record_override("weapon.club", {"fit_max_stage": 3})
	for stage in [1, 2, 3]:
		grabs.clear()
		var p := await _giant(stage)
		var reach := float(p.profile.melee_reach_m)
		var s := _soldier_at(Vector3(0, 0.05, -0.6 * reach), "test.heavy_%d" % stage)
		await step_ticks(1)
		p.router.set_injected_hold(&"heavy_modifier", true)
		p.router.inject_light_attack()
		await step_ticks(1)
		p.router.set_injected_hold(&"heavy_modifier", false)
		var broke: bool = await TestWait.until(self, func() -> bool:
			return s.controller.state == CombatController.State.STAGGERED, 60)
		assert_true(broke, "stage %d: the heavy breaks the soldier's poise" % stage)
		var stagger_ticks := s.controller.stagger_ticks_left
		var hit_tick := Sim.tick
		assert_true(stagger_ticks >= 88, "stage %d: a 1.5 s stagger against the larger giant (%d ticks)" % [stage, stagger_ticks])
		var start := p.global_position
		p.router.inject_edge(&"interact")
		var held: bool = await TestWait.until(self, func() -> bool: return p.grab.is_holding(), 90)
		assert_true(held, "stage %d: E grabs the staggered soldier" % stage)
		if not held:
			p.queue_free()
			s.queue_free()
			await step_ticks(2)
			continue
		assert_true(Sim.tick - hit_tick < stagger_ticks, "stage %d: inside the stagger (%d < %d ticks)" % [
			stage, Sim.tick - hit_tick, stagger_ticks])
		assert_eq(grabs, [[grabs[0][0], "player", s.entity_id]], "stage %d: grab_started once" % stage)
		assert_eq(s.controller.state, CombatController.State.GRABBED, "stage %d: the soldier is GRABBED" % stage)
		assert_eq(s.controller.held_by, "player", "stage %d: held by the player" % stage)
		var gap := Vector2(s.global_position.x - p.global_position.x, s.global_position.z - p.global_position.z).length()
		assert_true(p.global_position.distance_to(start) <= float(p.profile.grab_lunge_m) + 0.05,
			"stage %d: the lunge stays within grab_lunge_m (%.2f m)" % [stage, p.global_position.distance_to(start)])
		assert_true(gap < float(p.profile.grab_reach_m) + 1.0, "stage %d: held at the hand (%.2f m)" % [stage, gap])
		p.grab.drop()
		p.queue_free()
		s.queue_free()
		await step_ticks(2)


func test_the_held_body_sits_in_the_hand_out_of_the_simulation() -> void:
	var p := await _giant(1)
	var s := _soldier_at(Vector3(0, 0.05, -3.0), "test.held")
	await step_ticks(1)
	p.router.inject_edge(&"lock_press")
	await step_ticks(1)
	assert_eq(p.lock.target_id, "test.held", "locked on it before the grab")
	assert_true(await _grab(p, s), "grabbed")
	await step_ticks(2)
	assert_eq(p.controller.holding_id, "test.held", "holding_id")
	assert_eq(p.grab.held_attach(), "torso_fist", "in a fist")
	assert_eq(p.lock.target_id, "", "the lock let go of the held body")
	assert_false(s.entity.is_lockable(), "a held body cannot be locked")
	assert_true(s.is_held() and s.grab_holder_id == "player", "the soldier knows who holds it")
	assert_eq(s.process_mode, Node.PROCESS_MODE_DISABLED, "out of the simulation (Sim skips it, physics too)")
	assert_near(p.motor.speed_mult(), 0.6, 1e-9, "the giant walks at 0.6 x while holding")
	var anchor := (s.get_node("Anchors/Grab") as Node3D).global_position
	var socket := p.to_global(p.grab.socket_local())
	assert_true(anchor.distance_to(socket) < 0.01, "its grab point sits in the hand (%.3f m)" % anchor.distance_to(socket))
	assert_true(p.to_local(anchor).x < -0.5, "in the off (left) hand")
	p.interact.refresh()
	assert_eq(p.interact.current_prompt(), "Put down", "the prompt offers to put it down")
	var rig := p.get_rig_state()
	assert_eq(rig.holding, "torso_fist", "rig state holding")
	assert_eq(rig.grab_phase, "hold", "rig state grab_phase")
	assert_true(rig.has("pose_override"), "the hold pose overrides the arms")
	# Moving: the body follows the hand.
	p.router.set_injected_move(Vector2(1, 0))
	await step_ticks(20)
	p.router.set_injected_move(Vector2.ZERO)
	anchor = (s.get_node("Anchors/Grab") as Node3D).global_position
	assert_true(anchor.distance_to(p.to_global(p.grab.socket_local())) < 0.01, "still in the hand after walking")
	# An AI LOD change while held (the director, P10a) does not put it back into the simulation.
	s.set_lod_tier(1)
	await step_ticks(2)
	assert_eq(s.process_mode, Node.PROCESS_MODE_DISABLED, "still out of the simulation after a LOD change")
	anchor = (s.get_node("Anchors/Grab") as Node3D).global_position
	assert_true(anchor.distance_to(p.to_global(p.grab.socket_local())) < 0.01, "and in the hand")
	# The rig's off arm (it lerps into the pose) points at the socket, and its hand is there: the
	# visible grip is the simulated one. The test resumes before this frame's _process, so the
	# arm shows the previous tick's socket.
	await step_ticks(10)
	var shoulder := p.get_node("Visual/Body/ShoulderL") as Node3D
	var arm := -shoulder.global_transform.basis.z.normalized()
	var to_socket := (p.to_global(p.grab.socket_local()) - shoulder.global_position).normalized()
	assert_true(rad_to_deg(arm.angle_to(to_socket)) < 3.0, "the off arm points at the socket (%.1f degrees off)" % rad_to_deg(arm.angle_to(to_socket)))
	var hand := (p.get_node("Visual/Body/ShoulderL/Hand") as Node3D).global_position
	assert_true(hand.distance_to(p.to_global(p.grab.socket_local())) < 0.25, "the hand is at the socket (%.2f m)" % hand.distance_to(p.to_global(p.grab.socket_local())))
	# Other abilities wait for an empty hand; Crushing Grip does not.
	rejected.clear()
	p.router.inject_edge(&"slot_1")
	await step_ticks(1)
	assert_eq(p.controller.last_reject_reason, "holding", "Footfall is refused while holding")
	assert_true(messages.has(PlayerGrab.reason_text("holding")), "and the HUD says why")
	assert_eq(p.controller.state, CombatController.State.LOCOMOTION, "nothing started")
	var hud_params := {"slot": 1}
	p.grab.preview_params("slot_1", action("ability.heavy_footfall"), hud_params)
	assert_eq(p.controller.preview_reason(&"slot", hud_params), "holding", "the hotbar shows it too")
	# Another component's precheck on the same slot runs first; an empty answer falls through.
	var earlier := {"slot": 1, "precheck": func() -> String: return "no_target"}
	p.grab.preview_params("slot_1", action("ability.heavy_footfall"), earlier)
	assert_eq(p.controller.preview_reason(&"slot", earlier), "no_target", "an earlier precheck's reason wins")
	earlier = {"slot": 1, "precheck": func() -> String: return ""}
	p.grab.preview_params("slot_1", action("ability.heavy_footfall"), earlier)
	assert_eq(p.controller.preview_reason(&"slot", earlier), "holding", "then this component's")
	# E puts it down in front, upright, staggered 0.6 s, back in the simulation.
	p.router.inject_edge(&"interact")
	await step_ticks(1)
	assert_false(p.grab.is_holding(), "E put it down")
	assert_eq(ended.back()[3], "dropped", "grab_ended dropped")
	assert_eq(s.controller.state, CombatController.State.STAGGERED, "released into a 0.6 s stagger")
	assert_true(s.controller.stagger_ticks_left <= 36, "0.6 s")
	assert_eq(s.process_mode, Node.PROCESS_MODE_INHERIT, "back in the simulation")
	assert_eq(s.lod_tier, 1, "at the LOD tier it was given meanwhile")
	assert_true(s.entity.is_lockable(), "lockable again")
	assert_near(p.motor.speed_mult(), 1.0, 1e-9, "full speed again")
	assert_eq(p.controller.holding_id, "", "holding_id cleared")
	await TestWait.until(self, func() -> bool: return s.is_on_floor(), 60)
	assert_true(s.is_on_floor(), "it drops onto the floor")
	assert_true(_spot_is_free(s), "standing in a free spot")
	assert_near(absf(s.global_transform.basis.y.dot(Vector3.UP)), 1.0, 1e-3, "upright")


func test_a_hold_times_out() -> void:
	var p := await _giant(1)
	var s := _soldier_at(Vector3(0, 0.05, -3.0), "test.timeout")
	await step_ticks(1)
	assert_near(p.grab.hold_timeout_s, 5.0, 1e-9, "a hold lasts 5 s")
	p.grab.hold_timeout_s = 0.5
	assert_true(await _grab(p, s), "grabbed")
	var t0 := Sim.tick
	await TestWait.until(self, func() -> bool: return not p.grab.is_holding(), 60)
	assert_false(p.grab.is_holding(), "let go by itself")
	assert_eq(ended.back()[3], "timeout", "grab_ended timeout")
	assert_true(Sim.tick - t0 <= 31, "after 0.5 s")
	assert_ne_grabbed(s)


func assert_ne_grabbed(s: EnemyActor) -> void:
	assert_true(s.controller.state != CombatController.State.GRABBED, "%s is no longer GRABBED" % s.entity_id)
	assert_eq(s.controller.held_by, "", "%s: held_by cleared" % s.entity_id)
	assert_false(s.is_held(), "%s: not held" % s.entity_id)
	assert_eq(s.process_mode, Node.PROCESS_MODE_INHERIT, "%s: back in the simulation" % s.entity_id)


# --------------------------------------------------------------------------- interruptions

## Spec §15: an interrupted grab releases both entities.
func test_an_interrupted_grab_releases_both() -> void:
	var p := await _giant(1)
	var a := _soldier_at(Vector3(0, 0.05, -3.0), "test.int_a")
	await step_ticks(1)
	assert_true(await _grab(p, a), "grabbed")
	p.entity.stagger(1.0, "test")
	await step_ticks(1)
	assert_false(p.grab.is_holding(), "a staggered holder lets go")
	assert_eq(ended.back()[3], "interrupted", "grab_ended interrupted")
	assert_ne_grabbed(a)
	assert_eq(p.controller.state, CombatController.State.STAGGERED, "the holder is staggered, not EXECUTING")
	await _wait_free(p)
	# Staggered during the grab's windup: the hand never closes.
	_stagger(a, 3.0)
	grabs.clear()
	assert_eq(p.grab.try_grab(), CombatController.Verdict.ACCEPT, "a new grab starts")
	await step_ticks(3)
	assert_eq(p.controller.state, CombatController.State.EXECUTING, "in its windup")
	p.entity.stagger(1.0, "test")
	await step_ticks(25)
	assert_eq(grabs.size(), 0, "no grab_started")
	assert_true(p.controller.state != CombatController.State.EXECUTING, "the holder left EXECUTING")
	assert_true(a.controller.state != CombatController.State.GRABBED, "the target is not GRABBED")
	await _wait_free(p)
	# The target dies in the hand.
	assert_true(await _grab(p, a), "grabbed again")
	a.entity.combatant.pools.health = 1.0
	queue_hit("test.attacker", "test.int_a", p.global_position, 40.0)
	await step_ticks(2)
	assert_false(a.entity.is_alive(), "killed in the hand")
	assert_false(p.grab.is_holding(), "the holder let go")
	assert_eq(p.controller.holding_id, "", "holding_id cleared")
	assert_eq(ended.back()[3], "target_died", "grab_ended target_died")
	assert_false(a.is_held(), "the corpse is not held")
	assert_eq(a.process_mode, Node.PROCESS_MODE_INHERIT, "the corpse is back in the simulation")
	# The holder dies.
	var b := _soldier_at(Vector3(2, 0.05, -2.5), "test.int_b")
	await _wait_free(p)
	assert_true(await _grab(p, b), "grabbed a second soldier")
	p.controller.kill()
	await step_ticks(1)
	assert_eq(ended.back()[3], "holder_died", "grab_ended holder_died")
	assert_ne_grabbed(b)


func test_growth_and_checkpoints_refused_by_a_hold_let_go() -> void:
	var p := await _giant(1)
	var s := _soldier_at(Vector3(0, 0.05, -3.0), "test.grower")
	await step_ticks(1)
	assert_true(await _grab(p, s), "grabbed")
	await _wait_free(p)
	var r: Dictionary = p.growth.debug_set_stage(2)
	assert_eq(str(r.reason), "holding", "growth is refused while holding")
	assert_false(p.grab.is_holding(), "and the hold lets go")
	assert_eq(ended.back()[3], "interrupted", "grab_ended interrupted")
	assert_true(p.growth.debug_set_stage(2).ok, "the next growth works")
	# A pending checkpoint: while the held enemy is aware (it blocks the checkpoint by itself) the
	# hold goes on; once the hold is the only thing the checkpoint waits for, it lets go.
	var t := _soldier_at(Vector3(0, 0.05, -4.5), "test.saver")
	await step_ticks(1)
	assert_true(await _grab(p, t), "grabbed at stage 2")
	await _wait_free(p)
	t.brain.aware = true
	GameSession.test_checkpoints = true
	GameSession.request_checkpoint("test")
	await step_ticks(3)
	assert_eq(GameSession.checkpoint_blockers(), PackedStringArray(["holding", "aware:test.saver"]), "two blockers")
	assert_true(p.grab.is_holding(), "dropping an aware enemy would not help: the hold goes on")
	t.brain.aware = false
	await step_ticks(2)
	assert_false(p.grab.is_holding(), "the checkpoint waits only for the hold: it lets go")
	assert_eq(ended.back()[3], "interrupted", "grab_ended interrupted")
	await step_ticks(2)
	assert_true(GameSession.pending_checkpoint().is_empty(), "and the checkpoint is taken")
	GameSession.test_checkpoints = false


# --------------------------------------------------------------------------- throw and crush

## A throw into a second soldier hits each once (the second directly, the thrown one when it
## lands), through HitFactory, and the landing spot is never inside geometry.
func test_throwing_a_soldier_into_another_hits_each_once() -> void:
	var p := await _giant(1)
	var a := _soldier_at(Vector3(0, 0.05, -3.0), "test.thrown")
	var b := _soldier_at(Vector3(0.5, 0.05, -10.0), "test.struck")
	add_box(Vector3(12, 4, 1), Vector3(0, 2, -14.0))   # a wall behind the target
	await step_ticks(1)
	assert_true(await _grab(p, a), "grabbed")
	await _wait_free(p)
	p.router.inject_edge(&"lock_press")
	await step_ticks(1)
	assert_eq(p.lock.target_id, "test.struck", "locked on the second soldier")
	var stamina := p.entity.combatant.pools.stamina
	p.router.inject_light_attack()
	await step_ticks(1)
	assert_eq(p.controller.action_id(), THROW_ID, "light throws the held body")
	assert_near(p.entity.combatant.pools.stamina, stamina - 12.0, 1e-6, "for 12 stamina")
	var thrown: bool = await TestWait.until(self, func() -> bool: return not p.grab.is_holding(), 40)
	assert_true(thrown, "it left the hand")
	assert_eq(ended.back()[3], "thrown", "grab_ended thrown")
	assert_true(a.is_held(), "the body flies, still out of the simulation")
	var landed: bool = await TestWait.until(self, func() -> bool: return not a.is_held(), 120)
	assert_true(landed, "it came down")
	await step_ticks(2)
	var on_b := _hits_from("test.struck", THROW_ID)
	var on_a := _hits_from("test.thrown", THROW_ID)
	assert_eq(on_b.size(), 1, "the struck soldier is hit once")
	assert_eq(on_a.size(), 1, "the thrown soldier is hit once (its landing)")
	for r in on_b + on_a:
		assert_eq(r.event.attacker_id, "player", "a player hit")
		assert_true(r.event.from_projectile and r.event.projectile_id > 0, "a projectile's hit (HitFactory)")
		assert_eq(r.event.category, "projectile", "category projectile")
		assert_eq(r.event.attacker_growth_stage, 1, "HitFactory filled in the stage")
		assert_true(r.event.has_tag("Throw"), "tag Throw")
		assert_true(r.dealt_damage(), "it hurt")
	assert_eq(hits_on("player").size(), 0, "the giant is never hit by its own throw")
	assert_ne_grabbed(a)
	await TestWait.until(self, func() -> bool: return a.is_on_floor(), 60)
	assert_true(a.is_on_floor(), "the thrown soldier lands on the floor")
	assert_true(_spot_is_free(a), "never inside geometry or another body")
	assert_true(a.global_position.y > -0.2, "not under the floor")


func test_crushing_grip_damage_and_release() -> void:
	var p := await _giant(1)
	var s := _soldier_at(Vector3(0, 0.05, -3.0), "test.crushed")
	await step_ticks(1)
	assert_true(await _grab(p, s), "grabbed")
	await _wait_free(p)
	var pools := p.entity.combatant.pools
	var stamina := pools.stamina
	p.router.inject_edge(&"slot_4")
	await step_ticks(1)
	assert_eq(p.controller.action_id(), GRIP_ID, "slot 4 is Crushing Grip")
	assert_near(pools.stamina, stamina - 20.0, 1e-6, "20 stamina")
	var done: bool = await TestWait.until(self, func() -> bool: return not p.grab.is_holding(), 40)
	assert_true(done, "crushed and released")
	await step_ticks(1)
	var expected := CombatRules.round_damage(CombatRules.physical_after_armor(40.0 * 1.15 * 1.5, 15.0))
	assert_eq(expected, 60, "round(40 x 1.15 x 1.5 vs armor 15) = 60")
	var crush := _hits_from("test.crushed", GRIP_ID)
	assert_eq(crush.size(), 1, "one crush hit")
	assert_eq(crush[0].health_damage if not crush.is_empty() else -1, 60, "60 damage")
	assert_near(s.entity.combatant.pools.health, 160.0, 1e-6, "220 -> 160")
	assert_eq(ended.back()[3], "crushed", "grab_ended crushed")
	assert_ne_grabbed(s)
	assert_eq(s.controller.state, CombatController.State.STAGGERED, "dropped staggered")
	assert_false(p.controller.cooldowns.is_ready(GRIP_ID, Sim.tick), "10 s cooldown")
	# From an empty hand: grab and crush in one move (once the first one has found its feet: a
	# staggered soldier in reach could be grabbed again).
	await TestWait.until(self, func() -> bool: return s.controller.state == CombatController.State.LOCOMOTION, 60)
	var t := _soldier_at(Vector3(2.6, 0.05, -2.8), "test.crushed_2")
	await step_ticks(1)
	_stagger(t, 3.0)
	p.controller.cooldowns.clear()
	await _wait_free(p)
	grabs.clear()
	assert_eq(p.grab.try_slot("slot_4"), CombatController.Verdict.ACCEPT, "Crushing Grip on a staggered soldier in reach")
	await TestWait.until(self, func() -> bool: return _hits_from("test.crushed_2", GRIP_ID).size() > 0, 40)
	await step_ticks(1)
	assert_eq(grabs.size(), 1, "it grabbed it")
	assert_eq(_hits_from("test.crushed_2", GRIP_ID).size(), 1, "and crushed it once")
	assert_false(p.grab.is_holding(), "then let go")
	assert_ne_grabbed(t)


func test_stage_3_grabs_and_throws_an_ogre_the_stage_2_giant_cannot() -> void:
	var mid := await _giant(2)
	var ogre := _stub(Vector3(0, 0.05, -4.0), "test.ogre", {"height_m": 3.4, "mass_class": "medium",
		"grab_attach": "two_hand", "capsule_radius_m": 0.9})
	await step_ticks(1)
	_stagger(ogre, 4.0)
	assert_eq(mid.grab.try_grab(), CombatController.Verdict.REJECT, "a stage-2 giant cannot")
	assert_eq(mid.controller.last_reject_reason, "too_tall", "the ogre is too tall for it")
	mid.queue_free()
	await step_ticks(2)
	var big := await _giant(3)
	assert_true(await _grab(big, ogre), "a stage-3 giant grabs the staggered ogre")
	assert_eq(big.grab.held_attach(), "two_hand", "with both hands")
	await _wait_free(big)
	big.camera_rig.pitch = deg_to_rad(-20.0)
	big.router.inject_light_attack()
	var thrown: bool = await TestWait.until(self, func() -> bool: return not big.grab.is_holding(), 40)
	assert_true(thrown, "and throws it")
	var landed: bool = await TestWait.until(self, func() -> bool: return not ogre.is_held(), 150)
	assert_true(landed, "it lands")
	await step_ticks(1)
	assert_eq(_hits_from("test.ogre", THROW_ID).size(), 1, "and takes its landing hit")
	assert_ne_grabbed(ogre)


# --------------------------------------------------------------------------- unload

func test_scene_unload_while_holding_releases_without_errors() -> void:
	var p := await _giant(1)
	var s := _soldier_at(Vector3(0, 0.05, -3.0), "test.unload")
	await step_ticks(1)
	assert_true(await _grab(p, s), "grabbed")
	p.queue_free()
	await step_ticks(2)
	assert_eq(ended.back()[3], "unloaded", "grab_ended unloaded")
	assert_ne_grabbed(s)
	# A whole level unloads while holding: its children leave the tree before it (the held enemy,
	# added after the giant, even before the giant), and nothing logs an error.
	var level := Node3D.new()
	world.add_child(level)
	var g: GiantPlayer = (load(GIANT) as PackedScene).instantiate()
	g.position = Vector3(-6, 0.05, 0)
	level.add_child(g)
	g.router.use_injection = true
	var h: SoldierEnemy = (load(SOLDIER) as PackedScene).instantiate()
	h.entity_id = "test.unload_level"
	h.ai_enabled = false
	h.position = Vector3(-6, 0.05, -3.0)
	level.add_child(h)
	await TestWait.until(self, func() -> bool: return g.is_on_floor(), 30)
	assert_true(await _grab(g, h), "grabbed in the level")
	ended.clear()
	level.queue_free()
	await step_ticks(2)
	assert_eq(ended.size(), 1, "one grab_ended")
	assert_eq(ended.back()[3] if not ended.is_empty() else "", "unloaded", "reason unloaded")
	# A flying body when its whole level goes away: no errors (the after_each frees the world).
	var q := await _giant(1, Vector3(6, 0.05, 0))
	var t := _soldier_at(Vector3(6, 0.05, -3.0), "test.unload_2")
	await step_ticks(1)
	assert_true(await _grab(q, t), "grabbed")
	await _wait_free(q)
	q.router.inject_light_attack()
	await TestWait.until(self, func() -> bool: return not q.grab.is_holding(), 40)
	assert_true(t.is_held(), "in flight")


# --------------------------------------------------------------------------- wolves and walls

## Wolves are lifted by the scruff: the grab point (Anchors/Grab, the neck) in the hand, the wolf
## hanging nose up, its QuadrupedRig still animating; a drop puts it on its feet in a free spot.
func test_a_wolf_is_lifted_by_the_scruff() -> void:
	var p := await _giant(1)
	var w := TestSpawn.enemy(world, WOLF, Vector3(0, 0.05, -3.0), "test.scruffed", false, PI)
	await step_ticks(1)
	assert_true(await _grab(p, w), "grabbed the staggered wolf")
	await step_ticks(1)
	assert_eq(p.grab.held_attach(), "scruff", "by the scruff")
	var anchor := (w.get_node("Anchors/Grab") as Node3D).global_position
	assert_true(anchor.distance_to(p.to_global(p.grab.socket_local())) < 0.01, "its scruff is in the hand")
	var nose := -w.global_transform.basis.z
	assert_true(nose.y > 0.6, "it hangs nose up (%.2f)" % nose.y)
	assert_eq(w.get_node("Visual").process_mode, Node.PROCESS_MODE_PAUSABLE, "its rig keeps animating")
	assert_true(p.grab.drop(), "put down")
	assert_eq(w.get_node("Visual").process_mode, Node.PROCESS_MODE_INHERIT, "the rig follows the actor again")
	await TestWait.until(self, func() -> bool: return w.is_on_floor(), 60)
	assert_true(w.is_on_floor() and _spot_is_free(w), "on its feet in a free spot")
	assert_near(absf(w.global_transform.basis.y.dot(Vector3.UP)), 1.0, 1e-3, "upright")


## The hand can reach into a wall (the held body has no collision while held); putting it down
## there finds the nearest free spot beside the giant instead, never inside the wall.
func test_a_body_held_into_a_wall_is_put_down_outside_it() -> void:
	var p := await _giant(1)
	var s := _soldier_at(Vector3(0, 0.05, -3.0), "test.walled")
	await step_ticks(1)
	assert_true(await _grab(p, s), "grabbed")
	await _wait_free(p)
	add_box(Vector3(6, 5, 2.0), Vector3(-1.0, 2.5, -2.6))   # a wall where the hand is
	await step_ticks(2)
	assert_false(s.is_free_spot(s.global_position), "the held body is inside the wall now")
	assert_true(p.grab.drop(), "put down")
	assert_true(_spot_is_free(s), "outside the wall")
	await TestWait.until(self, func() -> bool: return s.is_on_floor(), 60)
	assert_true(s.is_on_floor() and _spot_is_free(s), "standing in a free spot")
	assert_true(s.global_position.z > -1.6 or s.global_position.z < -3.6, "not in the wall's depth (z %.2f)" % s.global_position.z)
