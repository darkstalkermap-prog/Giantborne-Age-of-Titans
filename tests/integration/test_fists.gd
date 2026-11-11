extends IntegrationSuite
## P32 (plan M6-M9 §3.16 tests, §5.12): the fists (the Stoneknuckles) and their finisher.
##   * They need a stage-4 giant and fit it to stage 6; their light chain's third blow is a grab.
##   * At stage 4 the chain's third light, against a soldier whose poise is whole, is refused with
##     "not_staggered" and costs nothing (no stamina, no action, the hand empty); after two hooks on a
##     staggered soldier it seizes him (fists_light_3: a grab, held like E's).
##   * The titanforged fists' perk adds 1.5 m to the grab reach (their finisher is the same).
## One test: the giant serves every check (the default tier's time).

const FISTS := "weapon.fists"
const FISTS_TITAN := "weapon.fists_titan"
const L1 := "ability.fists_light_1"
const L3 := "ability.fists_light_3"

var grabs: Array[Array] = []   ## [holder, target]
var messages: Array[String] = []


func before_each() -> void:
	await super()
	grabs.clear()
	messages.clear()
	Events.grab_started.connect(_on_grab_started)
	Events.hud_message.connect(_on_message)


func after_each() -> void:
	for sig: Signal in [Events.grab_started, Events.hud_message]:
		for c: Dictionary in sig.get_connections():
			if (c.callable as Callable).get_object() == self:
				sig.disconnect(c.callable)
	await super()


func _on_grab_started(_t: int, holder: String, target: String) -> void:
	grabs.append([holder, target])


func _on_message(text: String, _kind: String) -> void:
	messages.append(text)


static func _profile(stage: int) -> Dictionary:
	for rec: Dictionary in GameData.records_of_type("growth_profile"):
		if int(rec.get("stage", 0)) == stage:
			return rec
	return {}


func test_the_third_light_seizes_a_staggered_soldier_and_refuses_a_steady_one_for_nothing() -> void:
	var p := spawn_player(Vector3(0, 0.05, 0), 0.0)
	p.set_profile(_profile(3))
	await step_ticks(2)
	var eq: PlayerEquipment = p.equipment
	assert_false(eq.grant_weapon(FISTS, true).ok, "a stage-3 giant cannot wear them")
	assert_eq(str(eq.last_result.reason), "stage", "they need stage 4")
	p.set_profile(_profile(4))
	await step_ticks(1)
	assert_true(eq.equip_weapon(FISTS).ok, "a stage-4 giant can")
	assert_eq(int(GameData.get_record(FISTS).fit_max_stage), 6, "and they fit it to stage 6")
	var base := float(_profile(4).grab_reach_m)
	assert_near(p.grab.grab_reach(), base, 1e-6, "the profile's grab reach")
	assert_true(eq.grant_weapon(FISTS_TITAN, true).ok, "the titanforged Stoneknuckles")
	assert_near(p.grab.grab_reach(), base + 1.5, 1e-6, "+1.5 m (their perk)")
	assert_near(float(GameData.get_record(FISTS_TITAN).damage_multiplier), 1.1, 1e-6, "and x1.1")
	assert_eq(p.controller.next_light_id(), L1, "the fists' light chain")
	var third := GameData.get_action(L3)
	assert_eq(third.hit_shape, "grab", "whose third blow is a grab")
	# A steady soldier in reach: the third light is refused and costs nothing.
	var s := spawn_soldier(Vector3(0, 0.05, -5.0), 0.0, "test.p32_steady", false)
	s.entity.combatant.unkillable = true
	await step_ticks(1)
	var pools := p.entity.combatant.pools
	pools.stamina = pools.stamina_max
	p.controller.chain_next_id = L3        # the chain stands at its third blow
	p.controller.chain_expire_tick = p.controller.now + 30
	assert_eq(p.controller.next_light_id(), L3, "the next light is the third")
	p.router.inject_light_attack()
	await step_ticks(1)
	assert_eq(p.controller.last_reject_reason, "not_staggered", "refused: his poise is whole")
	assert_true(messages.has(PlayerGrab.reason_text("not_staggered")), "the HUD says why (%s)" % [messages])
	assert_near(pools.stamina, pools.stamina_max, 1e-6, "no stamina spent")
	assert_eq(p.controller.state, CombatController.State.LOCOMOTION, "the giant stays free")
	assert_false(p.grab.is_holding(), "nothing held")
	# Staggered, he is seized by the chain's third blow after two hooks.
	s.entity.stagger(4.0, "test")
	p.controller.chain_next_id = ""
	p.controller.chain_expire_tick = -1
	pools.stamina = pools.stamina_max
	var ids: Array[String] = []
	for i in 3:
		p.router.inject_light_attack()
		for t in 24:
			await step_ticks(1)
			var id := p.controller.action_id()
			if id != "" and (ids.is_empty() or ids.back() != id):
				ids.append(id)
	var held: bool = await TestWait.until(self, func() -> bool: return p.grab.is_holding(), 30)
	assert_eq(ids, [L1, "ability.fists_light_2", L3], "two hooks, then the grab")
	assert_true(held, "the third light seized the staggered soldier")
	assert_eq(grabs.back() if not grabs.is_empty() else [], ["player", "test.p32_steady"], "grab_started on him")
	assert_eq(hits_on("test.p32_steady").size(), 2, "both hooks struck him first")

