extends IntegrationSuite
## Boulder Hurl (plan §3.7 design 4, §2.8.4, spec §8): locked at stage 1 ("Stage 2"); at stage 2
## it arcs onto a soldier 20 m away, showing its landing ring during the windup; its 1.5 m
## splash hits a second wolf; a projectile-only cairn falls to it while a light attack and a
## Runic Bolt do nothing to it; it needs the stage's throw_boulder permission; growing to stage 2
## teaches and slots it.

const WOLF := "res://scenes/enemies/wolf.tscn"
const HURL_ID := "ability.boulder_hurl"

var previews: Array[Array] = []   ## [tick, center, radius]
var learned: Array[Array] = []


func before_each() -> void:
	await super()
	previews.clear()
	learned.clear()
	Events.ability_effect.connect(_on_effect)
	Events.ability_learned.connect(_on_learned)


func after_each() -> void:
	for sig: Signal in [Events.ability_effect, Events.ability_learned]:
		for c: Dictionary in sig.get_connections():
			if (c.callable as Callable).get_object() == self:
				sig.disconnect(c.callable)
	await super()


func _on_effect(t: int, actor: String, action_id: String, kind: String, center: Vector3, radius: float,
		_yaw: float, _arc: float) -> void:
	if kind == "aim_preview" and actor == "player" and action_id == HURL_ID:
		previews.append([t, center, radius])


func _on_learned(_t: int, action_id: String, slot_key: String) -> void:
	learned.append([action_id, slot_key])


func _profile(stage: int) -> Dictionary:
	for rec: Dictionary in GameData.records_of_type("growth_profile"):
		if int(rec.get("stage", 0)) == stage:
			return rec
	return {}


func _giant(stage: int) -> GiantPlayer:
	var p := spawn_player(Vector3(0, 0.05, 0), 0.0)
	if stage != 1:
		p.set_profile(_profile(stage))
	await TestWait.until(self, func() -> bool: return p.is_on_floor(), 40)
	await step_ticks(1)
	return p


func _lock(p: GiantPlayer, id: String) -> void:
	p.router.inject_edge(&"lock_press")
	await step_ticks(1)
	assert_eq(p.lock.target_id, id, "locked on %s" % id)


func _hurls_on(target_id: String) -> Array[HitResult]:
	var out: Array[HitResult] = []
	for r in hits_on(target_id):
		if r.event.action_id == HURL_ID:
			out.append(r)
	return out


func test_boulder_hurl_is_locked_at_stage_1() -> void:
	var p := await _giant(1)
	assert_eq(str(p.controller.loadout.slot_5), HURL_ID, "slot 5 holds Boulder Hurl")
	assert_eq(p.controller.preview_reason(&"slot", {"slot": 5}), "locked", "growth-stage locked")
	assert_eq(Hud.reason_text("locked", action(HURL_ID)), "Stage 2", "the hotbar says Stage 2")
	var pools := p.entity.combatant.pools
	var stamina := pools.stamina
	p.router.inject_edge(&"slot_5")
	await step_ticks(1)
	assert_eq(p.controller.last_reject_reason, "locked", "refused: locked")
	assert_near(pools.stamina, stamina, 1e-6, "nothing spent")
	assert_true(p.controller.cooldowns.is_ready(HURL_ID, Sim.tick), "no cooldown")
	assert_eq(p.controller.state, CombatController.State.LOCOMOTION, "nothing started")


func test_boulder_hurl_hits_a_soldier_20_m_away_at_stage_2() -> void:
	var p := await _giant(2)
	var s := spawn_soldier(Vector3(0, 0.05, -20), PI, "test.far_soldier")
	await step_ticks(1)
	await _lock(p, "test.far_soldier")
	var pools := p.entity.combatant.pools
	var stamina := pools.stamina
	p.router.inject_edge(&"slot_5")
	await step_ticks(1)
	assert_eq(p.controller.action_id(), HURL_ID, "Boulder Hurl starts")
	assert_near(pools.stamina, stamina - 15.0, 1e-6, "15 stamina")
	assert_false(p.controller.cooldowns.is_ready(HURL_ID, Sim.tick), "6 s cooldown")
	var landed: bool = await TestWait.until(self, func() -> bool: return _hurls_on("test.far_soldier").size() > 0, 150)
	assert_true(landed, "the boulder reaches the soldier 20 m away")
	var r := _hurls_on("test.far_soldier")
	assert_eq(r.size(), 1, "one hit")
	if r.is_empty():
		return
	assert_true(r[0].event.from_projectile, "a projectile")
	assert_eq(r[0].event.category, "projectile", "category projectile")
	assert_true(r[0].dealt_damage(), "it hurts")
	# The landing ring: every windup tick, at the soldier's feet, the splash wide.
	var windup := action(HURL_ID).windup_ticks
	assert_true(previews.size() >= windup - 2, "aim_preview during the windup (%d of %d ticks)" % [previews.size(), windup])
	var last: Array = previews.back() if not previews.is_empty() else [0, Vector3.INF, 0.0]
	var flat := Vector2(last[1].x - s.global_position.x, last[1].z - s.global_position.z).length()
	assert_true(flat < 1.0, "the ring is at the target (%.2f m off)" % flat)
	assert_near(float(last[1].y), 0.0, 0.1, "on the ground")
	assert_near(float(last[2]), 1.5, 1e-6, "as wide as the splash")


func test_the_splash_hits_two_wolves() -> void:
	var p := await _giant(2)
	TestSpawn.enemy(world, WOLF, Vector3(-0.6, 0.05, -14), "test.wolf_a", false, PI)
	TestSpawn.enemy(world, WOLF, Vector3(0.6, 0.05, -14), "test.wolf_b", false, PI)
	await step_ticks(1)
	p.router.inject_edge(&"lock_press")
	await step_ticks(1)
	assert_true(p.lock.target_id in ["test.wolf_a", "test.wolf_b"], "locked on a wolf")
	p.router.inject_edge(&"slot_5")
	var both: bool = await TestWait.until(self, func() -> bool:
		return _hurls_on("test.wolf_a").size() > 0 and _hurls_on("test.wolf_b").size() > 0, 150)
	assert_true(both, "both wolves are hit")
	var areas := 0
	for id in ["test.wolf_a", "test.wolf_b"]:
		var r := _hurls_on(id)
		assert_eq(r.size(), 1, "%s is hit once" % id)
		if not r.is_empty() and r[0].event.area_effect:
			areas += 1
	assert_eq(areas, 1, "one directly, the other by the splash")


## Spec §8 / plan §2.8.4: Boulder Hurl's category is projectile, so it topples a cairn that only
## projectiles can hurt, while a light attack (melee) and a Runic Bolt (magic) do nothing.
func test_a_projectile_only_cairn_falls_to_the_boulder_alone() -> void:
	TestFixtures.record_override("prop.test_cairn", {"schema_version": 1, "type": "prop",
		"category": "breakable", "display_name": "Watch Cairn (test)", "height_m": 3.0, "health": 60,
		"armor": 0, "accepted_attack_categories": ["projectile"], "min_growth_stage": 1,
		"debris_count": 0, "lockable": true, "grants_fury": false, "threat": 0.05, "stability": 100.0})
	var p := await _giant(2)
	var cairn: BreakableProp = (load(FENCE) as PackedScene).instantiate()
	cairn.world_id = "test.cairn"
	(cairn.get_node("CombatEntity") as CombatEntity).definition_id = "prop.test_cairn"
	cairn.position = Vector3(0, 0, -3.6)
	world.add_child(cairn)
	await step_ticks(1)
	var pools := cairn.entity.combatant.pools
	p.router.inject_light_attack()
	await TestWait.until(self, func() -> bool: return hits_on("test.cairn").size() > 0, 60)
	var melee := hits_on("test.cairn")
	assert_eq(melee.size(), 1, "the light attack reaches the cairn")
	if not melee.is_empty():
		assert_eq(melee[0].outcome, HitResult.Outcome.IMMUNE, "and is refused")
	assert_near(pools.health, 60.0, 1e-6, "no damage from melee")
	await TestWait.until(self, func() -> bool: return p.controller.action == null, 90)
	await _lock(p, "test.cairn")
	p.controller.request(&"attack", {"action_id": "ability.runic_bolt"})
	await TestWait.until(self, func() -> bool: return hits_on("test.cairn").size() > 1, 90)
	var bolt := hits_on("test.cairn")
	assert_eq(bolt.size(), 2, "the bolt reaches it")
	if bolt.size() == 2:
		assert_eq(bolt[1].event.action_id, "ability.runic_bolt", "the Runic Bolt")
		assert_eq(bolt[1].outcome, HitResult.Outcome.IMMUNE, "is refused too")
	assert_near(pools.health, 60.0, 1e-6, "no damage from magic")
	await TestWait.until(self, func() -> bool: return p.controller.action == null, 90)
	p.router.inject_edge(&"slot_5")
	var down: bool = await TestWait.until(self, func() -> bool: return destroyed.has("test.cairn"), 150)
	assert_true(down, "the boulder topples it")
	assert_eq(_hurls_on("test.cairn").size(), 1, "with one hit")


func test_boulder_hurl_needs_the_throw_boulder_permission() -> void:
	TestFixtures.record_override("growth.02", {"interaction_permissions": ["grab_small"]})
	var p := await _giant(2)
	var pools := p.entity.combatant.pools
	var stamina := pools.stamina
	p.router.inject_edge(&"slot_5")
	await step_ticks(1)
	assert_eq(p.controller.last_reject_reason, "no_permission", "refused without throw_boulder")
	assert_near(pools.stamina, stamina, 1e-6, "nothing spent")
	assert_true(p.controller.cooldowns.is_ready(HURL_ID, Sim.tick), "no cooldown")
	var params := {"slot": 5}
	p.grab.preview_params("slot_5", action(HURL_ID), params)
	assert_eq(p.controller.preview_reason(&"slot", params), "no_permission", "the hotbar previews the refusal")


func test_holding_refuses_boulder_hurl() -> void:
	var p := await _giant(2)
	var s := spawn_soldier(Vector3(0, 0.05, -4.0), PI, "test.held")
	await step_ticks(1)
	s.entity.stagger(3.0, "test")
	assert_eq(p.grab.try_grab(), CombatController.Verdict.ACCEPT, "grab")
	await TestWait.until(self, func() -> bool: return p.controller.action == null and p.grab.is_holding(), 60)
	assert_true(p.grab.is_holding(), "holding")
	p.router.inject_edge(&"slot_5")
	await step_ticks(1)
	assert_eq(p.controller.last_reject_reason, "holding", "both hands are needed for a boulder")
	p.grab.drop()


func test_growing_to_stage_2_teaches_and_slots_boulder_hurl() -> void:
	var p := await _giant(1)
	p.known_abilities.erase(HURL_ID)
	p.set_loadout_slot("slot_5", "")
	assert_true(p.growth.debug_set_stage(2).ok, "grow to stage 2")
	assert_true(p.known_abilities.has(HURL_ID), "Boulder Hurl is learned")
	assert_eq(str(p.controller.loadout.slot_5), HURL_ID, "into the first empty slot")
	assert_eq(learned, [[HURL_ID, "slot_5"]], "announced once")
