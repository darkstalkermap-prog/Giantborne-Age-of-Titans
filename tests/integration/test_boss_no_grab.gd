extends IntegrationSuite
## M8 gate (F13): no boss can be grabbed (plan M6-M9 §2.10 "no rival giant, troll matriarch or boss
## can be grabbed", §5.13; spec §8: boss grapples are stage 7). Warlord Corvane (2.0 m, small,
## torso_fist: every other grab rule would take him once his poise breaks) carries the Grab immunity
## of Harrok and the Matriarch: at stages 4, 5 and 6 a staggered Corvane in reach is refused - E's
## grab, Crushing Grip, the fists' finisher and, at stage 6, Rampart Grip - with "immune", and nothing
## is spent. And a yield ends any hold on the yielding boss: held when he yields, he is set down
## (grab_ended "interrupted") before the prompt opens.

const CORVANE := "res://scenes/enemies/corvane.tscn"
const GRAB_ID := "ability.grab_hold"
const GRIP := "ability.crushing_grip"
const RAMPART := "ability.rampart_grip"
const FISTS := "weapon.fists"
const L3 := "ability.fists_light_3"

var grabs: Array = []
var ended: Array = []


func before_each() -> void:
	await super()
	grabs.clear()
	ended.clear()
	WorldState.clear()
	Quests.end_dialogue()
	Events.grab_started.connect(_on_grab_started)
	Events.grab_ended.connect(_on_grab_ended)


func after_each() -> void:
	for sig: Signal in [Events.grab_started, Events.grab_ended]:
		for c: Dictionary in sig.get_connections():
			if (c.callable as Callable).get_object() == self:
				sig.disconnect(c.callable)
	Quests.end_dialogue()
	get_tree().paused = false
	await super()


func _on_grab_started(_t: int, holder: String, target: String) -> void:
	grabs.append([holder, target])


func _on_grab_ended(_t: int, holder: String, target: String, reason: String) -> void:
	ended.append([holder, target, reason])


static func _profile(stage: int) -> Dictionary:
	for rec: Dictionary in GameData.records_of_type("growth_profile"):
		if int(rec.get("stage", 0)) == stage:
			return rec
	return {}


## A giant of `stage` with Corvane staggered right in front of it, well inside its reach.
func _giant_and_corvane(stage: int) -> Array:
	var p := spawn_player(Vector3(0, 0.05, 0), 0.0)
	p.set_profile(_profile(stage))
	await TestWait.until(self, func() -> bool: return p.is_on_floor(), 40)
	var c := (load(CORVANE) as PackedScene).instantiate() as EnemyActor
	c.entity_id = "test.corvane"
	c.ai_enabled = false
	c.position = Vector3(0, 0.05, -(float(p.profile.get("capsule_radius_m", 1.0)) + 1.5))
	world.add_child(c)
	await step_ticks(2)
	c.entity.stagger(4.0, "test")
	assert_true(PlayerGrab.has_broken_poise(c.entity), "stage %d: Corvane staggered" % stage)
	return [p, c]


## `request` (a Callable returning the controller's verdict) is refused "immune" and spends nothing.
func _refused_for_nothing(p: GiantPlayer, request: Callable, action_id: String, what: String) -> void:
	var pools := p.entity.combatant.pools
	pools.stamina = pools.stamina_max
	grabs.clear()
	var v: int = request.call()
	assert_eq(v, CombatController.Verdict.REJECT, "%s: refused" % what)
	assert_eq(p.controller.last_reject_reason, "immune", "%s: he cannot be grabbed" % what)
	assert_near(pools.stamina, pools.stamina_max, 1e-6, "%s: no stamina spent" % what)
	assert_true(p.controller.cooldowns.is_ready(action_id, Sim.tick), "%s: no cooldown" % what)
	await step_ticks(20)
	assert_false(p.grab.is_holding(), "%s: nothing held" % what)
	assert_eq(grabs, [], "%s: no grab_started" % what)


func test_corvane_cannot_be_grabbed_at_stages_4_to_6() -> void:
	for stage in [4, 5, 6]:
		var pc: Array = await _giant_and_corvane(stage)
		var p: GiantPlayer = pc[0]
		var c: EnemyActor = pc[1]
		assert_true(c.entity.combatant.is_immune_to("Grab"), "Corvane's record: immune to Grab")
		assert_eq(p.grab.check_target(c.entity), "immune", "stage %d: check_target" % stage)
		await _refused_for_nothing(p, p.grab.try_grab, GRAB_ID, "stage %d: E" % stage)
		p.set_loadout_slot("slot_4", GRIP)
		await _refused_for_nothing(p, p.grab.try_slot.bind("slot_4"), GRIP, "stage %d: Crushing Grip" % stage)
		if stage == 6:
			p.set_loadout_slot("slot_4", RAMPART)
			await _refused_for_nothing(p, p.grab.try_slot.bind("slot_4"), RAMPART, "stage 6: Rampart Grip")
		assert_true(p.equipment.grant_weapon(FISTS, true).ok, "stage %d: the fists" % stage)
		p.controller.chain_next_id = L3   # the fists' chain stands at its third blow, the grab
		p.controller.chain_expire_tick = p.controller.now + 30
		await _refused_for_nothing(p, p.grab.try_finisher, L3, "stage %d: the fists' finisher" % stage)
		assert_true(c.entity.is_alive() and c.controller.state != CombatController.State.GRABBED,
			"stage %d: he stands, never in the hand" % stage)
		p.queue_free()
		c.queue_free()
		await step_ticks(2)


## A boss that yields in the giant's hand is set down at once (here Corvane with his immunity taken
## away for the test, the only way left to hold a boss that can yield).
func test_a_yield_sets_the_held_boss_down() -> void:
	var pc: Array = await _giant_and_corvane(4)
	var p: GiantPlayer = pc[0]
	var c: EnemyActor = pc[1]
	c.entity.combatant.immunities = PackedStringArray()
	assert_eq(p.grab.try_grab(), CombatController.Verdict.ACCEPT, "grabbed (the stand-in)")
	var held: bool = await TestWait.until(self, func() -> bool: return p.grab.is_holding(), 40)
	assert_true(held, "held")
	c.p34_yield("health")
	assert_true(c.yielded, "he yields")
	assert_false(p.grab.is_holding(), "the hand lets him go")
	assert_eq(ended.back() if not ended.is_empty() else [], ["player", "test.corvane", "interrupted"],
		"grab_ended interrupted")
	assert_true(c.controller.state != CombatController.State.GRABBED, "set down")
	assert_eq(c.grab_holder_id, "", "no holder")
	await step_ticks(30)
	assert_false(p.grab.is_holding(), "still not held")
	assert_true(c.entity.is_alive() and c.yielded and c.yield_decided == "", "alive, yielded, the prompt deciding")
