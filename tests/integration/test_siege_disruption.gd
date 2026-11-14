extends IntegrationSuite
## P32 (plan M6-M9 §2.10, §3.16 tests, §5.12): siege disruption and Rampart Grip.
##   * A stage-5 giant's grab of a ballista is refused with "engine_stage" (its sentence on the HUD)
##     and spends nothing; a stage-6 giant's grab of a crewed one is refused with "engine_crewed" until
##     the engine's poise breaks; then both hands seize it - out of the simulation, its crew running,
##     held 2 s at most - and a light hurls it (ability.throw_engine, the engine riding the projectile):
##     it comes down by the soldier the giant locked on, smashes there and its splash strikes him.
##   * Rampart Grip (Crushing Grip's stage-6 form; its evolution is test_evolutions'): a staggered
##     soldier is crushed and let go; an uncrewed engine in reach is seized and hurled at once, riding
##     its projectile (its landing is the first test's).

const BALLISTA := "res://scenes/world/siege_ballista.tscn"
const CREW := "res://scenes/enemies/siege_crew.tscn"
const GRAB_ID := "ability.grab_hold"
const THROW := "ability.throw_engine"
const RAMPART := "ability.rampart_grip"

var grabs: Array[Array] = []      ## [holder, target]
var ended: Array[Array] = []      ## [holder, target, reason]
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


func _on_grab_started(_t: int, holder: String, target: String) -> void:
	grabs.append([holder, target])


func _on_grab_ended(_t: int, holder: String, target: String, reason: String) -> void:
	ended.append([holder, target, reason])


func _on_rejected(_t: int, actor: String, action_id: String, reason: String) -> void:
	rejected.append([actor, action_id, reason])


func _on_message(text: String, _kind: String) -> void:
	messages.append(text)


# --------------------------------------------------------------------------- helpers

static func _profile(stage: int) -> Dictionary:
	for rec: Dictionary in GameData.records_of_type("growth_profile"):
		if int(rec.get("stage", 0)) == stage:
			return rec
	return {}


## A giant of `stage` at `pos`, facing -Z. Its recoveries are cut short (controller.recovery_scale, as
## P31's reach bands do): the checks here are about seizing and throwing, not the pauses after them.
func _giant(stage: int, pos: Vector3) -> GiantPlayer:
	var p := spawn_player(pos, 0.0)
	p.set_profile(_profile(stage))
	p.controller.recovery_scale = 0.05
	await step_ticks(2)
	return p


## A ballista at `pos` with its front (-Z) turned toward `face`.
func _engine(id: String, pos: Vector3, face: Vector3) -> SiegeEngine:
	var e := (load(BALLISTA) as PackedScene).instantiate() as SiegeEngine
	e.world_id = id
	e.position = pos
	e.rotation.y = yaw_towards(pos, face)
	world.add_child(e)
	return e


func _from(target_id: String, action_id: String) -> Array[HitResult]:
	var out: Array[HitResult] = []
	for r in hits_on(target_id):
		if r.event.action_id == action_id:
			out.append(r)
	return out


## A grab request that must be refused with `reason`, costing nothing (stamina, cooldown, state, hand).
func _expect_refusal(p: GiantPlayer, reason: String, what: String) -> void:
	var pools := p.entity.combatant.pools
	pools.stamina = pools.stamina_max
	rejected.clear()
	messages.clear()
	assert_eq(str(p.grab.find_candidate("hold").reason), reason, "%s: find_candidate says %s" % [what, reason])
	assert_eq(p.grab.try_grab(), CombatController.Verdict.REJECT, "%s: the grab is refused" % what)
	assert_eq(p.controller.last_reject_reason, reason, "%s: with reason %s" % [what, reason])
	assert_eq(rejected.back() if not rejected.is_empty() else [], ["player", GRAB_ID, reason],
		"%s: action_rejected reports it" % what)
	assert_true(messages.has(PlayerGrab.reason_text(reason)), "%s: the HUD says why (%s)" % [what, messages])
	assert_near(pools.stamina, pools.stamina_max, 1e-6, "%s: no stamina spent" % what)
	assert_eq(p.controller.state, CombatController.State.LOCOMOTION, "%s: the giant stays in locomotion" % what)
	assert_false(p.grab.is_holding(), "%s: nothing held" % what)
	assert_eq(grabs.size(), 0, "%s: no grab_started" % what)


# --------------------------------------------------------------------------- siege disruption

func test_an_engine_is_refused_below_stage_6_and_while_crewed_then_seized_and_thrown_where_it_smashes() -> void:
	var p := await _giant(5, Vector3(0, 0.05, 0))
	var eng := _engine("test.p32_seized", Vector3(0, 0, -7.5), Vector3(0, 0, 40))
	var crew := TestSpawn.enemy(world, CREW, eng.global_position + Vector3(0, 0.05, -2.5), "test.p32_hauler", false, 0.0)
	eng.add_crew(crew)
	await step_ticks(1)
	assert_true(eng.crewed, "the ballista is crewed")
	_expect_refusal(p, "engine_stage", "a stage-5 giant")
	assert_eq(PlayerGrab.reason_text("engine_stage"), "Grow to stage 6 to seize siege engines.", "the stage sentence")
	p.set_profile(_profile(6))
	await step_ticks(1)
	_expect_refusal(p, "engine_crewed", "a crewed engine at stage 6")
	# Its poise breaks: now it may be seized, crew or no crew.
	eng.entity.stagger(3.0, "test")
	assert_eq(p.grab.check_target(eng.entity), "", "a staggered engine may be seized")
	assert_eq(p.grab.try_grab(), CombatController.Verdict.ACCEPT, "the grab is accepted")
	var held: bool = await TestWait.until(self, func() -> bool: return p.grab.is_holding(), 40)
	assert_true(held, "seized")
	if not held:
		return
	assert_eq(grabs.back(), ["player", eng.entity.entity_id], "grab_started on the engine")
	assert_eq(p.grab.held_attach(), "two_hand", "with both hands")
	assert_true(eng.is_held() and eng.process_mode == Node.PROCESS_MODE_DISABLED, "held, out of the simulation")
	assert_false(eng.crewed, "no longer crewed")
	assert_true((crew as EnemyActor).brain.crew_lost, "its crew ran")
	assert_near(p.grab.hold_limit_s(), 2.0, 1e-6, "held 2 s at most")
	assert_eq(p.grab.throw_id(), THROW, "a light hurls it with the engine's throw")
	crew.queue_free()   # (it ran: out of the lock's way)
	# A soldier 13 m ahead, locked: the throw comes down on him.
	var s := spawn_soldier(Vector3(0, 0.05, -13.0), 0.0, "test.p32_under", false)
	await TestWait.until(self, func() -> bool:
		return p.controller.state == CombatController.State.LOCOMOTION and p.controller.action == null, 60)
	p.router.inject_edge(&"lock_press")
	await step_ticks(1)
	assert_eq(p.lock.target_id, "test.p32_under", "locked on the soldier")
	var stamina := p.entity.combatant.pools.stamina
	p.router.inject_light_attack()
	await step_ticks(1)
	assert_eq(p.controller.action_id(), THROW, "light hurls the engine")
	assert_near(p.entity.combatant.pools.stamina, stamina - float(GameData.get_record(THROW).stamina_cost), 1e-6,
		"for the throw's stamina")
	var smashed: bool = await TestWait.until(self, func() -> bool: return eng.destroyed, 150)
	assert_true(smashed, "the engine came down and smashed")
	assert_eq(ended.back() if not ended.is_empty() else [], ["player", eng.entity.entity_id, "thrown"], "grab_ended thrown")
	assert_true(destroyed.has("test.p32_seized"), "object_destroyed reports it")
	var near := Vector2(eng.global_position.x - s.global_position.x, eng.global_position.z - s.global_position.z).length()
	assert_true(near < 6.0, "it landed by the locked soldier (%.1f m)" % near)
	await step_ticks(1)
	assert_eq(_from("test.p32_under", THROW).size(), 1, "its 5 m splash struck the soldier once")
	assert_eq(_from("player", THROW).size(), 0, "never the giant itself")


# --------------------------------------------------------------------------- Rampart Grip

func test_rampart_grip_crushes_a_staggered_soldier_and_hurls_an_uncrewed_engine_at_once() -> void:
	var p := await _giant(6, Vector3(0, 0.05, 0))
	p.set_loadout_slot("slot_4", RAMPART)
	var pools := p.entity.combatant.pools
	# A small body is crushed and let go, as Crushing Grip does.
	var s := spawn_soldier(Vector3(0, 0.05, -6.0), 0.0, "test.p32_crushed", false)
	await step_ticks(1)
	s.entity.stagger(3.0, "test")
	pools.stamina = pools.stamina_max
	assert_eq(p.grab.try_slot("slot_4"), CombatController.Verdict.ACCEPT, "Rampart Grip on a staggered soldier")
	assert_near(pools.stamina, pools.stamina_max - 25.0, 1e-6, "25 stamina")
	var crushed: bool = await TestWait.until(self, func() -> bool: return _from("test.p32_crushed", RAMPART).size() > 0, 40)
	assert_true(crushed, "crushed")
	await step_ticks(1)
	assert_eq(grabs, [["player", "test.p32_crushed"]], "it grabbed him")
	assert_eq(ended.back() if not ended.is_empty() else [], ["player", "test.p32_crushed", "crushed"], "and let go, crushed")
	assert_false(p.grab.is_holding(), "the hand is empty")
	assert_false(p.controller.cooldowns.is_ready(RAMPART, Sim.tick), "Rampart Grip's cooldown runs")
	s.queue_free()
	# An uncrewed engine is seized and hurled at once.
	var eng := _engine("test.p32_ramparted", Vector3(0, 0, -7.5), Vector3(0, 0, 40))
	await TestWait.until(self, func() -> bool:
		return p.controller.state == CombatController.State.LOCOMOTION and p.controller.action == null, 40)
	p.controller.cooldowns.clear()
	assert_false(eng.crewed, "an uncrewed ballista")
	assert_eq(p.grab.ability_reason(GameData.get_action(RAMPART)), "", "Rampart Grip may seize it")
	pools.stamina = pools.stamina_max
	assert_eq(p.grab.try_slot("slot_4"), CombatController.Verdict.ACCEPT, "slot 4: Rampart Grip")
	var hurled: bool = await TestWait.until(self, func() -> bool: return p.controller.action_id() == THROW, 40)
	assert_true(hurled, "seized and hurled at once")
	assert_near(pools.stamina, pools.stamina_max - 25.0, 1e-6, "the hurl costs nothing more")
	var flying: bool = await TestWait.until(self, func() -> bool: return not p.grab.is_holding(), 40)
	assert_true(flying, "it left the hands")
	assert_eq(ended.back() if not ended.is_empty() else [], ["player", eng.entity.entity_id, "thrown"], "grab_ended thrown")
	assert_true(eng.is_held() and not eng.destroyed, "the engine flies, still out of the simulation")
	assert_eq(ProjectileSystem.instance(get_tree()).p32_carried_engines(), 1, "riding its projectile")
