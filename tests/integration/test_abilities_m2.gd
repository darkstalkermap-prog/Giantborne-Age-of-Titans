extends IntegrationSuite
## P03: the M2 abilities through the real player, controller and resolution path - cooldown
## spam, Stone Skin refresh, Mend, Titan Surge, Runic Bolt and the projectile system (walls,
## guards, parry, dedup, target death, splash category, enemy aim, level unload), Sweeping
## Blow's sector and Thunder Roar's slow and morale - plus the hotbar's reasons and target line
## and the status row.

const NEW_ABILITIES := ["ability.sweeping_blow", "ability.stone_skin", "ability.runic_bolt",
	"ability.ancestral_mend", "ability.thunder_roar", "ability.titan_surge"]


## A practice dummy that records the morale damage CombatEntity hands it (the plan's stub
## target for Roar; a dummy, so it never overrides EnemyActor's own on_morale_delta).
class MoraleDummy:
	extends PracticeDummy
	var morale_calls: Array = []

	func on_morale_delta(delta: float, source_id: String) -> void:
		morale_calls.append([delta, source_id])


## A player component that adds a precheck to one slot, as P07's grab will: the HUD passes its
## preview_params to preview_reason, so the slot shows the reason a request would get.
class PrecheckProbe:
	extends PlayerComponent
	var slot_key := "slot_6"
	var reason := "no_target"

	func preview_params(key: String, _def: ActionDef, params: Dictionary) -> void:
		if key == slot_key:
			params["precheck"] = check

	func check() -> String:
		return reason


var impacts: Array = []
var spawned: Array = []
var rejected: Array = []
var effects: Array = []


func before_each() -> void:
	await super()
	impacts.clear()
	spawned.clear()
	rejected.clear()
	effects.clear()
	Events.projectile_impact.connect(_on_impact)
	Events.projectile_spawned.connect(_on_spawned)
	Events.action_rejected.connect(_on_rejected)
	Events.ability_effect.connect(_on_effect)


func after_each() -> void:
	for sig: Signal in [Events.projectile_impact, Events.projectile_spawned, Events.action_rejected,
			Events.ability_effect]:
		for c: Dictionary in sig.get_connections():
			if (c.callable as Callable).get_object() == self:
				sig.disconnect(c.callable)
	# Without a level node the projectile system lives under the current scene (the test
	# runner): free it with the test, like a level unload would.
	for n in get_tree().get_nodes_in_group(ProjectileSystem.GROUP):
		n.queue_free()
	await super()


func _on_impact(_t: int, id: int, pos: Vector3, hit: String) -> void:
	impacts.append({"id": id, "position": pos, "hit": hit})


func _on_spawned(_t: int, id: int, owner_id: String, action_id: String, pos: Vector3, vel: Vector3, visual: String) -> void:
	spawned.append({"id": id, "owner": owner_id, "action": action_id, "position": pos, "velocity": vel,
		"visual": visual})


func _on_rejected(_t: int, actor_id: String, action_id: String, reason: String) -> void:
	rejected.append([actor_id, action_id, reason])


func _on_effect(_t: int, actor_id: String, action_id: String, kind: String, _c: Vector3, radius: float,
		_yaw: float, arc_deg: float) -> void:
	effects.append({"actor": actor_id, "action": action_id, "kind": kind, "radius": radius, "arc": arc_deg})


## The slot edge that fires `id` from the player's loadout ("" when it is not slotted).
static func _edge_for(p: GiantPlayer, id: String) -> StringName:
	for key: String in GiantPlayer.SLOT_KEYS:
		if str(p.controller.loadout.get(key, "")) == id:
			return &"ultimate" if key == "ultimate" else StringName(key)
	return &""


func _cast(p: GiantPlayer, id: String) -> void:
	var edge := _edge_for(p, id)
	assert_true(edge != &"", "%s is slotted in giant.json" % id)
	p.router.inject_edge(edge)


func _has_status(p: Node, status_id: String) -> bool:
	var e: CombatEntity = p.get("entity")
	return e != null and e.combatant.statuses.has(status_id)


func _system() -> ProjectileSystem:
	return ProjectileSystem.instance(get_tree())


# --------------------------------------------------------------------------- cooldowns

## [§15 cooldowns] 100 requests on consecutive ticks start each new ability once and spend its
## costs once; the next activation comes exactly when the cooldown ends.
func test_cooldown_spam_spends_once_per_cooldown() -> void:
	for id: String in NEW_ABILITIES:
		var def := action(id)
		var combatant := Combatant.from_record("spam", GameData.get_record("player.giant"), 3.6576)
		var c := CombatController.new("spam", combatant)
		c.add_action(def)
		var ultimate := def.kind == "ultimate"
		c.loadout = {"ultimate": id} if ultimate else {"slot_1": id}
		var kind := &"ultimate" if ultimate else &"slot"
		var params := {} if ultimate else {"slot": 1}
		var pools := combatant.pools
		pools.fury = 100.0
		var before := [pools.stamina, pools.essence, pools.fury]
		var starts: Array[int] = []
		# The lambda must not capture the controller (a reference cycle would leak it).
		c.action_started.connect(func(a: ActionDef, i: int) -> void:
			if a.id == id:
				starts.append(i))
		var t0 := 5000
		for t in range(t0, t0 + 100):
			c.begin_tick(t)
			c.request(kind, params)
		assert_eq(starts.size(), 1, "%s: 100 requests start it once" % id)
		assert_near(before[0] - pools.stamina, def.stamina_cost, 1e-6, "%s: stamina spent once" % id)
		assert_near(before[1] - pools.essence, def.essence_cost, 1e-6, "%s: essence spent once" % id)
		assert_near(before[2] - pools.fury, def.fury_cost, 1e-6, "%s: fury spent once" % id)
		if def.cooldown_s > 0.0:
			var ready := t0 + ActionDef.seconds_to_ticks(def.cooldown_s)
			c.begin_tick(ready - 1)
			assert_eq(c.request(kind, params), CombatController.Verdict.REJECT, "%s: still cooling down" % id)
			assert_eq(c.last_reject_reason, "cooldown", "%s: reason cooldown" % id)
			c.begin_tick(ready)
			assert_eq(c.request(kind, params), CombatController.Verdict.ACCEPT, "%s: ready when the cooldown ends" % id)
			assert_eq(starts.size(), 2, "%s: second activation after the cooldown" % id)
		else:
			assert_eq(c.last_reject_reason, "fury", "%s: the spent fury gates the next use" % id)


# --------------------------------------------------------------------------- self statuses

func test_stone_skin_refreshes_without_stacking() -> void:
	TestFixtures.record_override("ability.stone_skin", {"cooldown_s": 0})
	var p := spawn_player(Vector3(0, 0.05, 0), 0.0)
	await step_ticks(2)
	var c := p.entity.combatant
	var base := c.armor
	_cast(p, "ability.stone_skin")
	assert_true(await TestWait.until(self, func() -> bool: return _has_status(p, "status.stone_skin"), 30),
		"Stone Skin applies when the cast becomes active")
	var cast_tick := Sim.tick
	assert_near(c.armor_total(), base + 30.0, 1e-6, "+30 armor")
	assert_eq(effects.filter(func(e: Dictionary) -> bool: return e.kind == "self_buff").size(), 1, "a self_buff effect")
	await step_ticks(300 - 14)
	assert_true(c.statuses.remaining_s("status.stone_skin", Sim.tick) < 1.3, "about 1 s left before the re-cast")
	_cast(p, "ability.stone_skin")
	assert_true(await TestWait.until(self, func() -> bool:
		return c.statuses.remaining_s("status.stone_skin", Sim.tick) > 5.5, 30), "the re-cast refreshes the duration")
	assert_true(Sim.tick - cast_tick >= 290, "re-cast about 5 s after the first (%d ticks)" % (Sim.tick - cast_tick))
	assert_near(c.armor_total(), base + 30.0, 1e-6, "still +30: refresh, no stacking")
	assert_eq(c.statuses.count(), 1, "one instance")
	assert_near(c.armor, base, 1e-6, "base armor is never changed")
	await step_ticks(370)
	assert_false(_has_status(p, "status.stone_skin"), "expired 6 s after the refresh")
	assert_near(c.armor_total(), base, 1e-6, "armor back to base")


func test_stone_skin_recast_at_5_s_is_rejected_by_the_real_cooldown() -> void:
	var p := spawn_player(Vector3(0, 0.05, 0), 0.0)
	await step_ticks(2)
	_cast(p, "ability.stone_skin")
	assert_true(await TestWait.until(self, func() -> bool: return _has_status(p, "status.stone_skin"), 30), "cast")
	await step_ticks(300 - 14)
	var pools := p.entity.combatant.pools
	var essence := pools.essence
	var remaining := p.entity.combatant.statuses.remaining_s("status.stone_skin", Sim.tick)
	rejected.clear()
	_cast(p, "ability.stone_skin")
	await step_ticks(1)
	assert_eq(rejected.size(), 1, "the re-cast is rejected")
	if rejected.size() == 1:
		assert_eq(rejected[0], ["player", "ability.stone_skin", "cooldown"], "with reason cooldown")
	assert_true(pools.essence >= essence - 1e-6, "nothing spent (%.2f -> %.2f)" % [essence, pools.essence])
	assert_true(p.entity.combatant.statuses.remaining_s("status.stone_skin", Sim.tick) < remaining,
		"and the status is not refreshed")


func test_mend_heals_100_over_4_s_and_caps() -> void:
	var p := spawn_player(Vector3(0, 0.05, 0), 0.0)
	await step_ticks(2)
	var pools := p.entity.combatant.pools
	pools.health = pools.health_max - 150.0
	var heals: Array = []
	var on_heal := func(_t: int, id: String, amount: float, _s: String) -> void: heals.append([id, amount])
	Events.healed.connect(on_heal)
	_cast(p, "ability.ancestral_mend")
	assert_true(await TestWait.until(self, func() -> bool: return _has_status(p, "status.mend"), 30), "Mend applies")
	var start := pools.health
	await step_ticks(240)
	assert_near(pools.health - start, 100.0, 1e-6, "100 health over 4 s")
	assert_eq(heals.size(), 8, "8 ticks of 12.5")
	assert_false(_has_status(p, "status.mend"), "expired after 4 s")
	pools.health = pools.health_max - 30.0
	heals.clear()
	assert_true(p.entity.apply_status("status.mend"), "applied again")
	await step_ticks(241)
	assert_near(pools.health, pools.health_max, 1e-6, "healing caps at the maximum")
	var total := 0.0
	for h: Array in heals:
		total += float(h[1])
	assert_near(total, 30.0, 1e-6, "healed reports only what was gained")
	Events.healed.disconnect(on_heal)


func test_titan_surge_boosts_damage_and_poise_and_blocks_fury() -> void:
	var p := spawn_player(Vector3(0, 0.05, 0), 0.0)
	spawn_dummy(Vector3(0, 0, -2.6))
	await step_ticks(2)
	p.entity.combatant.crit_chance = 0.0
	var pools := p.entity.combatant.pools
	pools.fury = 100.0
	_cast(p, "ability.titan_surge")
	assert_true(await TestWait.until(self, func() -> bool: return _has_status(p, "status.titan_surge"), 40),
		"Titan Surge applies")
	assert_near(pools.fury, 0.0, 1e-6, "100 fury spent")
	await step_ticks(25)
	p.router.inject_light_attack()
	await step_ticks(45)
	var on := hits_on("dummy_01")
	assert_eq(on.size(), 1, "the light lands")
	if on.size() == 1:
		assert_eq(on[0].outcome, HitResult.Outcome.HIT, "a hit")
		assert_eq(on[0].health_damage, 46, "46 raw x 1.25 = 57.5 vs armor 25 = 46 (37 without the surge)")
		var plain := 12.0 * CombatRules.poise_scale(3.6576, 2.2)
		assert_near(on[0].poise_damage, plain * 1.25, 1e-4, "poise damage x 1.25")
	assert_near(pools.fury, 0.0, 1e-6, "no fury is gained while it lasts")
	assert_false(p.controller.is_invulnerable(), "no invulnerability")


# --------------------------------------------------------------------------- Runic Bolt and projectiles

func test_runic_bolt_uses_intellect_through_the_real_cast() -> void:
	TestFixtures.record_override("ability.runic_bolt", {"cooldown_s": 0})
	var p := spawn_player(Vector3(0, 0.05, 0), 0.0)
	spawn_dummy(Vector3(0, 0, -10))
	await step_ticks(2)
	p.entity.combatant.crit_chance = 0.0
	p.router.inject_edge(&"lock_press")
	await step_ticks(2)
	assert_eq(p.lock.target_id, "dummy_01", "locked on the dummy")
	_cast(p, "ability.runic_bolt")
	assert_true(await TestWait.until(self, func() -> bool: return hits_on("dummy_01").size() == 1, 60), "the bolt lands")
	assert_eq(spawned.size(), 1, "one projectile launched")
	if spawned.size() == 1:
		assert_eq(spawned[0].action, "ability.runic_bolt", "of the bolt")
		assert_eq(spawned[0].visual, "bolt", "with the bolt visual")
		var expected := Vector3(0.6, 2.9, -0.8)
		assert_true((spawned[0].position as Vector3).distance_to(expected) < 0.05,
			"launched from launch_offset_m at stage 1 (%s)" % spawned[0].position)
	var first := hits_on("dummy_01")[0]
	assert_eq(first.health_damage, 46, "P40 x (1 + 0.015 x Intellect 10), arcane ignores the dummy's armor")
	assert_true(first.event.from_projectile, "marked as a projectile hit")
	assert_eq(first.event.category, "magic", "magic category")
	assert_eq(effects.filter(func(e: Dictionary) -> bool: return e.kind == "cast").size(), 1, "a cast effect")
	p.entity.combatant.set_attributes({"intellect": 20.0})
	await step_ticks(30)
	_cast(p, "ability.runic_bolt")
	assert_true(await TestWait.until(self, func() -> bool: return hits_on("dummy_01").size() == 2, 60), "second bolt")
	assert_eq(hits_on("dummy_01")[1].health_damage, 52, "Intellect 20: 40 x 1.3 = 52")


func test_projectile_stops_at_a_wall() -> void:
	var p := spawn_player(Vector3(0, 0.05, 0), 0.0)
	spawn_dummy(Vector3(0, 0, -12), "behind_wall")
	add_box(Vector3(6, 6, 0.4), Vector3(0, 3, -6))
	await step_ticks(2)
	var sys := _system()
	sys.spawn(p.entity, action("ability.runic_bolt"), Vector3(0, 2, -1.5), Vector3(0, 0, -35),
		p.attack.runner.context())
	assert_eq(sys.active_count(), 1, "in flight")
	await step_ticks(30)
	assert_eq(hits_on("behind_wall").size(), 0, "the wall stops it")
	assert_eq(impacts.size(), 1, "one impact")
	if impacts.size() == 1:
		assert_eq(impacts[0].hit, "", "on the world")
		assert_near((impacts[0].position as Vector3).z, -5.5, 0.05, "touching the wall's face (radius 0.3)")
	assert_eq(sys.active_count(), 0, "removed on impact")


func test_projectile_blocked_by_a_front_guard_using_the_impact_point() -> void:
	# The shooter stands BEHIND the soldier, but the bolt meets the soldier's front: the guard
	# arc is measured from the impact point, so it is blocked.
	var p := spawn_player(Vector3(0, 0.05, 8), 0.0)
	var s := spawn_soldier(Vector3(0, 0.05, 0), 0.0)
	await step_ticks(2)
	s.brain.aware = true
	s.brain.state = SoldierBrain.AIState.ALERT
	assert_true(s.is_guarding(), "the soldier guards its front (-Z)")
	var sys := _system()
	sys.spawn(p.entity, action("ability.runic_bolt"), Vector3(0, 1.2, -5), Vector3(0, 0, 35), p.attack.runner.context())
	await step_ticks(12)
	var on := hits_on("soldier_01")
	assert_eq(on.size(), 1, "one hit")
	if on.size() == 1:
		assert_eq(on[0].outcome, HitResult.Outcome.BLOCKED, "blocked: the impact point is inside the guard")
		assert_true(on[0].event.attacker_position.z < -0.1, "attacker_position is the impact point (%s)" % on[0].event.attacker_position)
	sys.spawn(p.entity, action("ability.runic_bolt"), Vector3(0, 1.2, 5), Vector3(0, 0, -35), p.attack.runner.context())
	await step_ticks(12)
	on = hits_on("soldier_01")
	assert_eq(on.size(), 2, "the second bolt lands too")
	if on.size() == 2:
		assert_eq(on[1].outcome, HitResult.Outcome.HIT, "from behind the guard does not cover it")


func test_projectile_is_not_parryable() -> void:
	var p := spawn_player(Vector3(0, 0.05, 0), 0.0)
	var s := spawn_soldier(Vector3(0, 0.05, -9), PI, "shooter")
	await step_ticks(2)
	p.router.set_injected_hold(&"block", true)
	p.router.inject_edge(&"block_press")
	await step_ticks(2)
	assert_eq(p.controller.state, CombatController.State.BLOCKING, "blocking, inside the parry window")
	_system().spawn(s.entity, action("ability.runic_bolt"), Vector3(0, 2.0, -2.2), Vector3(0, 0, 35), s.runner.context())
	await step_ticks(3)
	var on := hits_on("player")
	assert_eq(on.size(), 1, "the enemy bolt reaches the giant")
	if on.size() == 1:
		assert_eq(on[0].outcome, HitResult.Outcome.BLOCKED, "blocked, never parried (no Melee/Parryable tags)")
		assert_true(p.controller.block_elapsed_ticks() < 12, "still inside the parry window")
	p.router.set_injected_hold(&"block", false)
	p.router.inject_edge(&"block_release")


func test_projectile_dedups_per_projectile() -> void:
	var bolt: Dictionary = GameData.get_record("ability.runic_bolt").duplicate(true)
	bolt["id"] = "ability.test_pierce_bolt"
	bolt["projectile"]["pierce"] = true
	bolt["projectile"]["radius_m"] = 0.6
	bolt["projectile"]["speed_mps"] = 6.0
	TestFixtures.record_override("ability.test_pierce_bolt", bolt)
	var p := spawn_player(Vector3(0, 0.05, 6), 0.0)
	spawn_soldier(Vector3(0, 0.05, 0), 0.0)
	await step_ticks(2)
	var sys := _system()
	var a := action("ability.test_pierce_bolt")
	var ctx := p.attack.runner.context()
	# Slow and wide: it overlaps the soldier's three hurtboxes for many ticks.
	var first := sys.spawn(p.entity, a, Vector3(0, 1.0, 2.0), Vector3(0, 0, -6), ctx)
	var second := sys.spawn(p.entity, a, Vector3(0, 1.0, 2.6), Vector3(0, 0, -6), ctx)
	await step_ticks(70)
	var on := hits_on("soldier_01")
	assert_eq(on.size(), 2, "one hit per projectile, however many hurtboxes and ticks it overlaps")
	var ids: Array = []
	for r in on:
		ids.append(r.event.projectile_id)
		assert_eq(r.event.instance_id, ctx.instance_id, "both belong to the same attack instance")
	ids.sort()
	assert_eq(ids, [first, second], "each projectile hit once")
	assert_eq(sys.get_projectile(first) != null, true, "a piercing bolt keeps flying after its hit")


func test_target_death_mid_cast_leaves_no_stale_hits() -> void:
	var p := spawn_player(Vector3(0, 0.05, 0), 0.0)
	var s := spawn_soldier(Vector3(0, 0.05, -9), PI)
	await step_ticks(2)
	p.router.inject_edge(&"lock_press")
	await step_ticks(2)
	assert_eq(p.lock.target_id, "soldier_01", "locked")
	_cast(p, "ability.runic_bolt")
	await step_ticks(6)
	assert_eq(p.controller.state, CombatController.State.CASTING, "winding up the bolt")
	queue_hit("tester", "soldier_01", s.global_position + Vector3(0, 0, 2), 9999.0)
	await step_ticks(1)
	assert_false(s.entity.is_alive(), "the target died during the windup")
	assert_eq(p.lock.target_id, "", "the lock was released")
	var after_death := hits.size()
	await step_ticks(60)
	assert_eq(spawned.size(), 1, "the bolt still launched (at the crosshair)")
	for i in range(after_death, hits.size()):
		assert_false(hits[i].event.target_id == "soldier_01", "no hit on the dead target")
	assert_eq(Sim.pending_hit_count(), 0, "no stale queued hits")
	assert_eq(_system().active_count(), 0, "the bolt ended")
	# A bolt already flying at a target that dies before it arrives passes the corpse.
	var s2 := spawn_soldier(Vector3(3, 0.05, -14), PI, "soldier_02")
	await step_ticks(2)
	_system().spawn(p.entity, action("ability.runic_bolt"), Vector3(3, 1.2, -2), Vector3(0, 0, -35),
		p.attack.runner.context())
	await step_ticks(5)
	queue_hit("tester", "soldier_02", s2.global_position + Vector3(0, 0, 2), 9999.0)
	await step_ticks(40)
	var on := hits_on("soldier_02")
	assert_eq(on.size(), 1, "only the lethal blow; the bolt never hits the corpse")
	assert_eq(Sim.pending_hit_count(), 0, "nothing left queued")


func test_splash_carries_the_projectile_category() -> void:
	TestFixtures.record_override("prop.test_projectile_only", {"schema_version": 1, "type": "prop",
		"category": "breakable", "display_name": "Projectile-only cairn", "height_m": 1.6, "health": 80,
		"armor": 0, "accepted_attack_categories": ["projectile"], "min_growth_stage": 1,
		"debris_count": 0, "lockable": false, "grants_fury": false, "threat": 0.0, "stability": 100.0})
	var hurl: Dictionary = GameData.get_record("ability.runic_bolt").duplicate(true)
	hurl["id"] = "ability.test_hurl"
	hurl["category"] = "projectile"
	hurl["damage_type"] = "physical"
	hurl["damage_split"] = {"physical": 1.0}
	hurl["crit_eligible"] = false
	hurl["projectile"]["impact_radius_m"] = 1.5
	hurl["projectile"]["visual"] = "boulder"
	TestFixtures.record_override("ability.test_hurl", hurl)
	var p := spawn_player(Vector3(0, 0.05, 0), 0.0)
	var cairn: BreakableProp = (load(FENCE) as PackedScene).instantiate()
	cairn.world_id = "test.cairn"
	(cairn.get_node("CombatEntity") as CombatEntity).definition_id = "prop.test_projectile_only"
	cairn.position = Vector3(0, 0, -6)
	world.add_child(cairn)
	await step_ticks(2)
	var sys := _system()
	# A magic bolt straight at it: the cairn accepts only the projectile category.
	sys.spawn(p.entity, action("ability.runic_bolt"), Vector3(0, 1.0, -2), Vector3(0, 0, -35), p.attack.runner.context())
	await step_ticks(10)
	var on := hits_on("test.cairn")
	assert_eq(on.size(), 1, "the bolt reaches the cairn")
	if on.size() == 1:
		assert_eq(on[0].outcome, HitResult.Outcome.IMMUNE, "a magic bolt is rejected")
		assert_eq(on[0].notes, "not_permitted", "by the prop's accepted categories")
	# A projectile-category shot into the ground in front of it: only the splash reaches it.
	var origin := Vector3(0, 2.0, -2.0)
	var ground := Vector3(0, 0, -5.0)
	sys.spawn(p.entity, action("ability.test_hurl"), origin, (ground - origin).normalized() * 35.0,
		p.attack.runner.context())
	await step_ticks(10)
	on = hits_on("test.cairn")
	assert_eq(on.size(), 2, "the splash reaches it")
	if on.size() == 2:
		assert_eq(on[1].outcome, HitResult.Outcome.HIT, "a projectile-category splash damages it")
		assert_true(on[1].health_damage > 0, "for real damage (%d)" % on[1].health_damage)
		assert_eq(on[1].event.category, "projectile", "the splash inherits the action's category")
		assert_true(on[1].event.area_effect, "and is an area effect")
		assert_eq(on[1].event.pulse_id, (spawned.back().id as int) + ProjectileSystem.SPLASH_PULSE_OFFSET, "splash pulse id")
	assert_eq(impacts.back().hit, "", "the second shot hit the ground")


func test_enemy_target_aim_uses_the_stored_aim_point() -> void:
	var enemy_bolt: Dictionary = GameData.get_record("ability.runic_bolt").duplicate(true)
	enemy_bolt["id"] = "ability.test_enemy_bolt"
	enemy_bolt["cooldown_s"] = 0
	enemy_bolt["essence_cost"] = 0
	enemy_bolt["unlock_level"] = 1
	enemy_bolt["projectile"]["aim"] = "target"
	enemy_bolt["projectile"]["launch_offset_m"] = [0.0, 1.4, -0.5]
	TestFixtures.record_override("ability.test_enemy_bolt", enemy_bolt)
	var s := spawn_soldier(Vector3(0, 0.05, 0), 0.0, "caster")
	var p := spawn_player(Vector3(0, 0.05, -12), PI)
	await step_ticks(2)
	s.controller.add_action(action("ability.test_enemy_bolt"))
	s.controller.request(&"attack", {"action_id": "ability.test_enemy_bolt"})
	var stored := Vector3(6, 1.5, -12)
	s.runner.aim_point = stored   # what P09 stores at the aim-lock tick, during the windup
	assert_true(await TestWait.until(self, func() -> bool: return spawned.size() == 1, 40), "launched")
	var origin := s.to_global(Vector3(0.0, 1.4, -0.5))
	if spawned.size() == 1:
		var dir: Vector3 = (spawned[0].velocity as Vector3).normalized()
		assert_true(dir.is_equal_approx((stored - origin).normalized()), "flies at the stored aim point")
		assert_true((spawned[0].position as Vector3).is_equal_approx(origin), "from the launch offset")
	assert_eq(s.runner.aim_point, Vector3.INF, "the aim point is cleared after the launch")
	await step_ticks(40)
	s.controller.request(&"attack", {"action_id": "ability.test_enemy_bolt"})
	assert_true(await TestWait.until(self, func() -> bool: return spawned.size() == 2, 40), "second launch")
	if spawned.size() == 2:
		var to_player := (p.entity.anchor_position() - (spawned[1].position as Vector3)).normalized()
		assert_true((spawned[1].velocity as Vector3).normalized().is_equal_approx(to_player),
			"without a stored point it aims at the target's anchor at launch")


## Decision 8: a shot in flight still lands after its shooter dies; a shooter that is freed
## (despawned, level unloaded) takes its projectiles with it.
func test_a_bolt_in_flight_outlives_its_dead_shooter() -> void:
	var p := spawn_player(Vector3(0, 0.05, 0), 0.0)
	var s := spawn_soldier(Vector3(0, 0.05, -14), PI, "shooter")
	await step_ticks(2)
	var sys := _system()
	var ends: Array = []
	sys.projectile_ended.connect(func(pr: Projectile, why: String) -> void: ends.append([pr.id, why]))
	var first := sys.spawn(s.entity, action("ability.runic_bolt"), Vector3(0, 2.0, -12), Vector3(0, 0, 35),
		s.runner.context())
	queue_hit("tester", "shooter", s.global_position + Vector3(0, 0, -2), 9999.0)
	await step_ticks(1)
	assert_false(s.entity.is_alive(), "the shooter died while its bolt was in flight")
	assert_eq(sys.active_count(), 1, "the bolt keeps flying")
	assert_true(await TestWait.until(self, func() -> bool: return hits_on("player").size() == 1, 40),
		"and still lands on the giant")
	var on := hits_on("player")
	if on.size() == 1:
		assert_eq(on[0].event.attacker_id, "shooter", "from the dead shooter")
		assert_true(on[0].event.from_projectile, "as a projectile hit")
		assert_eq(on[0].outcome, HitResult.Outcome.HIT, "resolved, not dropped")
	assert_eq(ends, [[first, "impact"]], "it ended on the impact")
	var s2 := spawn_soldier(Vector3(5, 0.05, -14), PI, "shooter_2")
	await step_ticks(2)
	var second := sys.spawn(s2.entity, action("ability.runic_bolt"), Vector3(5, 2.0, -12), Vector3(0, 0, 35),
		s2.runner.context())
	await step_ticks(2)
	s2.queue_free()
	await step_ticks(2)
	assert_true(sys.get_projectile(second) == null, "a freed shooter's bolt is removed")
	assert_eq(ends.back(), [second, "owner_gone"], "with reason owner_gone")
	await step_ticks(30)
	assert_eq(hits_on("player").size(), 1, "and never lands")


func test_no_projectile_survives_its_level() -> void:
	var level := Node3D.new()
	level.name = "Level"
	level.add_to_group("level_root")
	world.add_child(level)
	assert_eq(ProjectileSystem.parent_for(get_tree()), level, "a level_root node hosts the system")
	var p := spawn_player(Vector3(0, 0.05, 0), 0.0)
	await step_ticks(2)
	var sys := _system()
	assert_eq(sys.get_parent(), level, "created under the level")
	assert_eq(ProjectileSystem.instance(get_tree()), sys, "one system per level")
	sys.spawn(p.entity, action("ability.runic_bolt"), Vector3(0, 30, 0), Vector3(0, 0.5, 0), p.attack.runner.context())
	assert_eq(sys.active_count(), 1, "a slow projectile in flight")
	level.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	assert_false(is_instance_valid(sys), "freed with the level, with its projectiles")
	assert_eq(ProjectileSystem.parent_for(get_tree()), get_tree().current_scene,
		"without a level_root the system goes to the current scene (the sandbox's main scene)")
	await step_ticks(2)
	assert_eq(Sim.pending_hit_count(), 0, "nothing left behind")


# --------------------------------------------------------------------------- Sweeping Blow and Roar

func test_sweeping_blow_hits_the_sector_only() -> void:
	var p := spawn_player(Vector3(0, 0.05, 0), 0.0)
	var r := 2.6
	var a_pos := Vector3(r * sin(deg_to_rad(50.0)), 0.05, -r * cos(deg_to_rad(50.0)))
	var b_pos := Vector3(-a_pos.x, 0.05, a_pos.z)
	var side := Vector3(r, 0.05, 0.0)
	spawn_soldier(a_pos, yaw_towards(a_pos, Vector3.ZERO), "at_plus_50")
	spawn_soldier(b_pos, yaw_towards(b_pos, Vector3.ZERO), "at_minus_50")
	spawn_soldier(side, yaw_towards(side, Vector3.ZERO), "at_90")
	await step_ticks(2)
	_cast(p, "ability.sweeping_blow")
	await step_ticks(30)
	assert_eq(hits_on("at_plus_50").size(), 1, "+50 degrees: hit")
	assert_eq(hits_on("at_minus_50").size(), 1, "-50 degrees: hit")
	assert_eq(hits_on("at_90").size(), 0, "90 degrees: outside the 120-degree sector")
	assert_near(p.facing_yaw, 0.0, 1e-4, "no soft-target turn during the windup")
	var sectors := effects.filter(func(e: Dictionary) -> bool: return e.kind == "sector")
	assert_eq(sectors.size(), 1, "one sector effect")
	if sectors.size() == 1:
		assert_near(float(sectors[0].radius), float(p.profile.melee_reach_m), 1e-6, "radius = melee reach")
		assert_near(float(sectors[0].arc), 120.0, 1e-6, "120 degrees")
	for r_hit in hits_on("at_plus_50") + hits_on("at_minus_50"):
		assert_true(r_hit.event.area_effect, "an area effect")


func test_footfall_radius_follows_the_growth_stage() -> void:
	var p := spawn_player(Vector3(0, 0.05, 0), 0.0)
	await step_ticks(2)
	var f := action("ability.heavy_footfall")
	assert_near(f.radius_m, 3.0, 1e-9, "base radius unchanged (the M1 pin)")
	assert_near(p.attack.runner.pulse_radius(f), 3.0, 1e-9, "stage 1: 3 m")
	p.growth_stage = 2
	assert_near(p.attack.runner.pulse_radius(f), 4.0, 1e-9, "stage 2: 4 m")
	p.growth_stage = 3
	assert_near(p.attack.runner.pulse_radius(f), 5.0, 1e-9, "stage 3: 5 m")
	# P26 (plan M6-M9 §2.9): the list runs to stage 6 now (6.5 / 8 / 9.5 m at stages 4-6).
	p.growth_stage = 6
	assert_near(p.attack.runner.pulse_radius(f), 9.5, 1e-9, "stage 6: 9.5 m")
	p.growth_stage = 7
	assert_near(p.attack.runner.pulse_radius(f), 9.5, 1e-9, "beyond the list: the last entry")
	p.growth_stage = 1
	assert_near(p.attack.runner.pulse_radius(action("ability.sweeping_blow")), 3.5, 1e-9,
		"Sweeping Blow: the profile's melee reach")


func test_thunder_roar_slows_and_costs_morale_unblockably() -> void:
	var p := spawn_player(Vector3(0, 0.05, 0), 0.0)
	var s := spawn_soldier(Vector3(0, 0.05, -4), PI)
	var node: Node = (load(DUMMY) as PackedScene).instantiate()
	node.set_script(MoraleDummy)
	var stub := node as MoraleDummy
	stub.entity_id = "morale_stub"
	stub.position = Vector3(3.5, 0, 1)
	world.add_child(stub)
	spawn_dummy(Vector3(0, 0, 7.5), "out_of_range")
	await step_ticks(2)
	s.brain.aware = true
	s.brain.state = SoldierBrain.AIState.ALERT
	assert_true(s.is_guarding(), "the soldier guards toward the giant")
	assert_near(s.controller.move_speed_multiplier(), 1.0, 1e-9, "unslowed")
	_cast(p, "ability.thunder_roar")
	assert_true(await TestWait.until(self, func() -> bool: return _has_status(s, "status.slow"), 40), "the roar lands")
	var on := hits_on("soldier_01")
	assert_eq(on.size(), 1, "one roar hit on the soldier")
	if on.size() == 1:
		assert_eq(on[0].outcome, HitResult.Outcome.HIT, "unblockable: a guard does not stop it")
		assert_eq(on[0].health_damage, 0, "no damage")
	assert_near(s.controller.move_speed_multiplier(), 0.7, 1e-6, "30% slow")
	assert_eq(stub.morale_calls, [[-20.0, "player"]], "on_morale_delta(-20) on the stub target")
	assert_eq(hits_on("out_of_range").size(), 0, "6 m radius")
	assert_eq(effects.filter(func(e: Dictionary) -> bool: return e.kind == "roar").size(), 1, "a roar effect")
	await step_ticks(170)
	assert_true(_has_status(s, "status.slow"), "still slowed just before 3 s")
	await step_ticks(15)
	assert_false(_has_status(s, "status.slow"), "the slow ends after 3 s")
	assert_near(s.controller.move_speed_multiplier(), 1.0, 1e-9, "full speed again")


# --------------------------------------------------------------------------- hotbar and status row

func _hud() -> Hud:
	var layer := CanvasLayer.new()
	world.add_child(layer)
	var hud := Hud.new()
	layer.add_child(hud)
	return hud


## Every slot's shown reason is the reason preview_reason gives for that slot right now, with the
## request parameters the player's components add (preview_params: P07's grab precheck on the
## Crushing Grip and Boulder Hurl slots).
func _check_hotbar(hud: Hud, p: GiantPlayer, label: String) -> void:
	await get_tree().process_frame
	hud.refresh()   # this tick's state (the HUD's own update ran a physics tick earlier)
	for i in 9:
		var ultimate := i == 8
		var key := "ultimate" if ultimate else "slot_%d" % (i + 1)
		var id := str(p.controller.loadout.get(key, ""))
		var state := hud.slot_state(i)
		assert_eq(state.id, id, "%s: slot %d shows %s" % [label, i + 1, id])
		if id == "":
			assert_eq(state.reason, "", "%s: an empty slot has no reason" % label)
			continue
		var params := {} if ultimate else {"slot": i + 1}
		for comp: PlayerComponent in p.components():
			if comp.has_method("preview_params"):
				comp.call("preview_params", key, p.controller.library.get(id), params)
		var code := p.controller.preview_reason(&"ultimate" if ultimate else &"slot", params)
		assert_eq(state.reason_code, code, "%s: slot %d reason code = preview_reason" % [label, i + 1])
		assert_eq(state.reason, Hud.reason_text(code, GameData.get_action(id)), "%s: slot %d text" % [label, i + 1])


func test_hotbar_reasons_follow_preview_reason() -> void:
	var p := spawn_player(Vector3(0, 0.05, 0), 0.0)
	var hud := _hud()
	await step_ticks(2)
	var pools := p.entity.combatant.pools
	await _check_hotbar(hud, p, "ready")
	assert_eq(hud.slot_state(0).reason, "", "Footfall is available")
	assert_eq(hud.slot_state(8).reason, "Fury", "the ultimate needs 100 fury")
	p.controller.level = 1
	await _check_hotbar(hud, p, "level 1")
	assert_eq(hud.slot_state(2).reason, "Lv 2", "Stone Skin unlocks at level 2")
	assert_eq(hud.slot_state(5).reason, "Lv 3", "Runic Bolt at level 3")
	assert_eq(hud.slot_state(6).reason, "Lv 4", "Mend at level 4")
	assert_eq(hud.slot_state(1).reason, "", "Sweeping Blow at level 1")
	p.controller.level_exempt["ability.runic_bolt"] = true
	await _check_hotbar(hud, p, "exempt")
	assert_eq(hud.slot_state(5).reason, "", "a reward-taught ability skips the level gate")
	p.controller.level = 99
	TestFixtures.record_override("ability.runic_bolt", {"unlock_stage": 2})
	await _check_hotbar(hud, p, "stage gate")
	assert_eq(hud.slot_state(5).reason, "Stage 2", "a growth-stage gate")
	TestFixtures.restore_all()
	pools.stamina = 5.0
	pools.essence = 10.0
	await _check_hotbar(hud, p, "low resources")
	assert_eq(hud.slot_state(1).reason, "Stamina", "Sweeping Blow needs 18 stamina")
	assert_eq(hud.slot_state(2).reason, "Essence", "Stone Skin needs 25 essence")
	pools.stamina = pools.stamina_max
	pools.essence = pools.essence_max
	pools.fury = 100.0
	pools.mark_combat()   # fury decays only after 10 s out of combat
	await _check_hotbar(hud, p, "full")
	assert_eq(hud.slot_state(8).reason, "", "the ultimate is ready at 100 fury")
	_cast(p, "ability.heavy_footfall")
	await step_ticks(3)
	await _check_hotbar(hud, p, "casting")
	assert_eq(hud.slot_state(1).reason, "Busy", "busy while Footfall is cast")
	assert_eq(hud.slot_state(0).reason, "Cooldown", "Footfall itself is cooling down")
	await step_ticks(70)
	await _check_hotbar(hud, p, "cooling down")
	assert_eq(hud.slot_state(0).reason, "Cooldown", "still cooling down after the cast")
	assert_eq(hud.slot_state(1).reason, "", "the others are free again")
	p.controller.kill()
	await _check_hotbar(hud, p, "dead")
	assert_eq(hud.slot_state(1).reason, "Dead", "dead")


## A component's precheck reaches the hotbar through preview_params (the hook P07's grab uses),
## and the precheck codes map to their text.
func test_hotbar_shows_a_component_precheck_reason() -> void:
	var p := spawn_player(Vector3(0, 0.05, 0), 0.0)
	var hud := _hud()
	await step_ticks(2)
	var probe := PrecheckProbe.new()
	p.add_component(&"precheck_probe", probe)
	await get_tree().process_frame
	hud.refresh()
	assert_eq(p.controller.preview_reason(&"slot", {"slot": 6, "precheck": probe.check}), "no_target",
		"the precheck rejects slot 6")
	assert_eq(hud.slot_state(5).reason_code, "no_target", "the hotbar previews with the component's params")
	assert_eq(hud.slot_state(5).reason, "No target", "shown as No target")
	assert_eq(hud.slot_state(0).reason, "", "the other slots are unaffected")
	probe.reason = "no_grab_target"
	hud.refresh()
	assert_eq(hud.slot_state(5).reason, "No target", "the grab's reason reads the same")
	probe.reason = "too_heavy"
	hud.refresh()
	assert_eq(hud.slot_state(5).reason, "Too Heavy", "any other code is shown capitalised")
	probe.reason = ""
	hud.refresh()
	assert_eq(hud.slot_state(5).reason, "", "an empty precheck accepts")
	p.remove_component(&"precheck_probe")


func test_hotbar_target_line_for_projectile_slots() -> void:
	var p := spawn_player(Vector3(0, 0.05, 0), 0.0)
	var hud := _hud()
	spawn_dummy(Vector3(0, 0, -10))
	await step_ticks(2)
	await get_tree().process_frame
	hud.refresh()
	assert_eq(hud.slot_state(5).id, "ability.runic_bolt", "slot 6 holds Runic Bolt")
	assert_eq(hud.slot_state(5).target, "aim", "unlocked: the bolt flies at the crosshair")
	assert_eq(hud.slot_state(0).target, "", "no target line on a pulse")
	p.router.inject_edge(&"lock_press")
	await step_ticks(2)
	hud.refresh()
	assert_eq(hud.slot_state(5).target, "» Practice Dummy", "locked: the selected target")


func test_status_row_shows_the_players_statuses() -> void:
	var p := spawn_player(Vector3(0, 0.05, 0), 0.0)
	var hud := _hud()
	await step_ticks(2)
	var row: Node = hud.get_node_or_null("StatusRow")
	assert_true(row != null and row.has_method("visible_text"), "the status row widget is on the HUD")
	if row == null:
		return
	await get_tree().process_frame
	assert_eq(row.visible_text(), "", "nothing active")
	p.entity.apply_status("status.stone_skin")
	p.entity.apply_status("status.slow")
	await get_tree().process_frame
	assert_eq(row.visible_text(), "SLOW 3s  SKIN 6s", "chips sorted by status id, seconds rounded up")
	await step_ticks(185)
	await get_tree().process_frame
	assert_eq(row.visible_text(), "SKIN 3s", "the slow expired")


# --------------------------------------------------------------------------- presentation

func test_hit_feedback_draws_every_ability_effect_and_status_tints() -> void:
	var p := spawn_player(Vector3(0, 0.05, 0), 0.0)
	var fb := HitFeedback.new()
	world.add_child(fb)
	await step_ticks(2)
	var kinds := ["sector", "roar", "self_buff", "aim_preview"]
	for kind: String in kinds:
		assert_false(fb.effect_visible(kind), "%s: hidden at first" % kind)
	Events.ability_effect.emit(Sim.tick, "player", "ability.sweeping_blow", "sector", Vector3.ZERO, 3.5, 0.0, 120.0)
	Events.ability_effect.emit(Sim.tick, "player", "ability.thunder_roar", "roar", Vector3.ZERO, 6.0, 0.0, 360.0)
	Events.ability_effect.emit(Sim.tick, "player", "ability.stone_skin", "self_buff", Vector3.ZERO, 0.0, 0.0, 0.0)
	Events.ability_effect.emit(Sim.tick, "player", "ability.runic_bolt", "cast", Vector3(0, 3, -1), 0.0, 0.0, 0.0)
	# P07 emits aim_preview during Boulder Hurl's windup at the predicted landing point.
	Events.ability_effect.emit(Sim.tick, "player", "ability.boulder_hurl", "aim_preview", Vector3(0, 0, -12),
		1.5, 0.0, 0.0)
	for kind: String in kinds:
		assert_true(fb.effect_visible(kind), "%s: shown" % kind)
	for i in 6:
		await get_tree().process_frame
	assert_true(fb.effect_visible("aim_preview"), "the landing ring stays briefly after an emit")
	for i in 30:
		await get_tree().process_frame
	assert_false(fb.effect_visible("aim_preview"), "and goes once the emits stop")
	assert_false(fb.effect_visible("sector"), "the sector fades")
	for i in 20:
		await get_tree().process_frame
	for kind: String in kinds:
		assert_false(fb.effect_visible(kind), "%s: gone again" % kind)
	# Status tints: the first STATUS_TINTS entry the actor has, cleared when the last expires.
	var rig := p.rig
	assert_near(rig.status_tint().a, 0.0, 1e-9, "no tint without statuses")
	p.entity.apply_status("status.stone_skin", NAN, 0.5)
	assert_eq(rig.status_tint(), HitFeedback.STATUS_TINTS[1][1], "Stone Skin tints the rig")
	p.entity.apply_status("status.titan_surge", NAN, 1.0)
	assert_eq(rig.status_tint(), HitFeedback.STATUS_TINTS[0][1], "Titan Surge has the higher priority")
	await step_ticks(35)
	assert_false(p.entity.combatant.statuses.has("status.stone_skin"), "Stone Skin expired")
	assert_eq(rig.status_tint(), HitFeedback.STATUS_TINTS[0][1], "the surge tint stays")
	await step_ticks(30)
	assert_near(rig.status_tint().a, 0.0, 1e-9, "no tint once every status expired")
