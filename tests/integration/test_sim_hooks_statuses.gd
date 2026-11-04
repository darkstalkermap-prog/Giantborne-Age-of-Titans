extends IntegrationSuite
## P01 Sim seams in the running engine: hook phases and order around the actors, hit resolution
## and the status pass; hook pruning; RNG streams that leave the crit sequence alone; launch
## slots; the dead-shooter rule; statuses, heals and on-hit effects on real entities.

const MEND := "status.test_mend"
const SLOW := "status.test_slow"
const SKIN := "status.test_skin"
const MARK := "status.test_mark"
const BLINK := "status.test_blink"

var _restore: Array = []
var applied: Array = []
var expired: Array = []
var healed: Array = []

## A test actor: optional morale hook and posture, read by CombatEntity.
const ACTOR_SOURCE := """extends Node3D
var morale: Array = []
var blocking := false
var invulnerable := false
func on_morale_delta(delta: float, source_id: String) -> void:
	morale.append([delta, source_id])
func get_defense_state() -> DefenseState:
	var d := DefenseState.new()
	d.position = global_position
	d.forward = -global_transform.basis.z
	d.height_m = 1.8
	d.blocking = blocking
	d.invulnerable = invulnerable
	d.block_elapsed_ticks = 1 << 20
	d.stamina = 100.0
	return d
"""

## A Sim actor that reports its step.
const PROBE_SOURCE := """extends Node
var on_step: Callable
func sim_step(tick: int, _dt: float) -> void:
	if on_step.is_valid():
		on_step.call(tick)
"""


func before_each() -> void:
	await super()
	applied.clear()
	expired.clear()
	healed.clear()
	_status(MEND, {"stacking": "refresh_no_stack", "duration_s": 4.0, "tick_s": 0.5,
		"modifiers": {"heal_per_tick": 12.5}, "tags": ["Buff", "Heal"]})
	_status(SLOW, {"stacking": "strongest_wins", "duration_s": 3.0, "magnitude_key": "slow_fraction",
		"default_magnitude": 0.3, "modifiers": {"slow_fraction": 0.3}, "tags": ["Debuff", "Slow"]})
	_status(SKIN, {"stacking": "refresh_no_stack", "duration_s": 6.0, "modifiers": {"armor_flat": 30},
		"tags": ["Buff"]})
	_status(MARK, {"stacking": "refresh_no_stack", "duration_s": 2.0, "tags": ["Debuff"]})
	_status(BLINK, {"stacking": "refresh_no_stack", "duration_s": 1.0 / 60.0, "tags": ["Buff"]})
	Events.status_applied.connect(_on_applied)
	Events.status_expired.connect(_on_expired)
	Events.healed.connect(_on_healed)


func after_each() -> void:
	Sim.remove_hooks(self)
	Events.status_applied.disconnect(_on_applied)
	Events.status_expired.disconnect(_on_expired)
	Events.healed.disconnect(_on_healed)
	_restore.reverse()
	for pair: Array in _restore:
		GameData.restore_record(pair[0], pair[1])
	_restore.clear()
	await super()


func _status(id: String, fields: Dictionary) -> void:
	var rec := {"schema_version": 1, "type": "status_effect"}
	rec.merge(fields, true)
	_restore.append([id, GameData.override_record(id, rec)])


func _on_applied(t: int, entity_id: String, status_id: String, source_id: String, duration_s: float) -> void:
	applied.append([t, entity_id, status_id, source_id, duration_s])


func _on_expired(t: int, entity_id: String, status_id: String) -> void:
	expired.append([t, entity_id, status_id])


func _on_healed(t: int, entity_id: String, amount: float, source_id: String) -> void:
	healed.append([t, entity_id, amount, source_id])


## A bare actor with a CombatEntity, inside the test world.
func _bare(id: String, definition: String, team := CombatEntity.Team.ENEMY, pos := Vector3.ZERO) -> CombatEntity:
	var s := GDScript.new()
	s.source_code = ACTOR_SOURCE
	s.reload()
	var actor := Node3D.new()
	actor.set_script(s)
	actor.position = pos
	var ce := CombatEntity.new()
	ce.name = "CombatEntity"
	ce.entity_id = id
	ce.definition_id = definition
	ce.team = team
	actor.add_child(ce)
	world.add_child(actor)
	return ce


func _event(attacker_id: String, target_id: String, power: float) -> HitEvent:
	var e := HitEvent.new()
	e.tick = Sim.tick
	e.instance_id = Sim.new_instance_id()
	e.attacker_id = attacker_id
	e.target_id = target_id
	e.power = power
	e.attacker_stat = 10.0
	e.attacker_height_m = 1.8
	e.damage_split = {"physical": 1.0}
	e.tags = PackedStringArray(["Ranged"])
	e.attacker_position = Vector3(0, 0, -3)
	return e


# --------------------------------------------------------------------------- hooks

func test_hooks_run_in_phase_and_order() -> void:
	var target := _bare("test.hook_target", "prop.practice_dummy", CombatEntity.Team.NEUTRAL)
	var order: Array = []
	var probe := Node.new()
	var ps := GDScript.new()
	ps.source_code = PROBE_SOURCE
	ps.reload()
	probe.set_script(ps)
	world.add_child(probe)
	probe.set("on_step", func(t: int) -> void: order.append(["actor", t]))
	Sim.register_actor("aaa_probe", probe)
	var counts := [Sim.hook_count(Sim.Hook.PRE_ACTORS), Sim.hook_count(Sim.Hook.POST_ACTORS),
		Sim.hook_count(Sim.Hook.POST_RESOLVE)]
	Sim.add_hook(Sim.Hook.POST_RESOLVE, self, func(t: int) -> void: order.append(["post_resolve_200", t]), 200)
	Sim.add_hook(Sim.Hook.PRE_ACTORS, self, func(t: int) -> void: order.append(["pre_100_a", t]), 100)
	Sim.add_hook(Sim.Hook.POST_ACTORS, self, func(t: int) -> void:
		order.append(["post_actors", t])
		Sim.queue_hit(_event("test.anyone", target.entity_id, 10.0)))
	Sim.add_hook(Sim.Hook.PRE_ACTORS, self, func(t: int) -> void: order.append(["pre_10", t]), 10)
	Sim.add_hook(Sim.Hook.PRE_ACTORS, self, func(t: int) -> void: order.append(["pre_100_b", t]), 100)
	Sim.add_hook(Sim.Hook.POST_RESOLVE, self, func(t: int) -> void: order.append(["post_resolve_100", t]), 100)
	assert_eq(Sim.hook_count(Sim.Hook.PRE_ACTORS), counts[0] + 3, "three PRE_ACTORS hooks registered")
	var resolve_cb := func(t: int, r: HitResult) -> void:
		if r.event.target_id == target.entity_id:
			order.append(["resolve", t])
	var expire_cb := func(t: int, _e: String, _s: String) -> void: order.append(["status_pass", t])
	Events.hit_resolved.connect(resolve_cb)
	Events.status_expired.connect(expire_cb)
	assert_true(target.apply_status(BLINK), "a one-tick status")
	await step_ticks(1)
	var t := Sim.tick
	var names: Array = []
	for entry: Array in order:
		if entry[1] == t:
			names.append(entry[0])
	assert_eq(names, ["pre_10", "pre_100_a", "pre_100_b", "actor", "post_actors", "resolve", "status_pass",
		"post_resolve_100", "post_resolve_200"],
		"PRE_ACTORS by order then registration -> actors -> POST_ACTORS -> hits -> statuses -> POST_RESOLVE")
	Sim.remove_hooks(self)
	assert_eq([Sim.hook_count(Sim.Hook.PRE_ACTORS), Sim.hook_count(Sim.Hook.POST_ACTORS),
		Sim.hook_count(Sim.Hook.POST_RESOLVE)], counts, "remove_hooks(owner) removes all of them")
	order.clear()
	await step_ticks(2)
	var hook_entries := order.filter(func(e: Array) -> bool: return e[0] != "actor" and e[0] != "resolve")
	assert_eq(hook_entries, [], "removed hooks no longer run")
	Events.hit_resolved.disconnect(resolve_cb)
	Events.status_expired.disconnect(expire_cb)
	Sim.unregister_actor("aaa_probe", probe)


func _add_refcounted_hook(calls: Array) -> void:
	var rc := RefCounted.new()
	Sim.add_hook(Sim.Hook.POST_RESOLVE, rc, func(_t: int) -> void: calls[0] += 1)
	# rc goes out of scope here and is freed.


func test_hooks_are_pruned_when_their_owner_is_freed() -> void:
	var calls: Array = [0, 0]
	var owner := Node.new()
	world.add_child(owner)
	var base := Sim.hook_count(Sim.Hook.POST_ACTORS)
	Sim.add_hook(Sim.Hook.POST_ACTORS, owner, func(_t: int) -> void: calls[0] += 1)
	await step_ticks(2)
	assert_eq(calls[0], 2, "runs every tick")
	owner.free()
	await step_ticks(2)
	assert_eq(calls[0], 2, "a freed owner's hook stops running")
	assert_eq(Sim.hook_count(Sim.Hook.POST_ACTORS), base, "and is pruned")
	var rc_calls: Array = [0]
	_add_refcounted_hook(rc_calls)
	await step_ticks(2)
	assert_eq(rc_calls[0], 0, "a freed RefCounted owner's hook never runs")


# --------------------------------------------------------------------------- RNG streams

func test_rng_streams_leave_the_crit_sequence_alone() -> void:
	Sim.reseed(Sim.DEFAULT_SEED)
	var expected: Array = []
	for i in 6:
		expected.append(Sim.rng.randf())
	Sim.reseed(Sim.DEFAULT_SEED)
	var got: Array = []
	for i in 6:
		Sim.rng_for("loot").randf()
		Sim.rng_for("ai").randi()
		got.append(Sim.rng.randf())
	assert_eq(got, expected, "drawing from streams does not change Sim.rng draws")
	Sim.reseed(Sim.DEFAULT_SEED)
	assert_eq(Sim.rng_for("loot").seed, Sim.DEFAULT_SEED ^ hash("loot"), "stream seed = DEFAULT_SEED ^ hash(name)")
	assert_true(Sim.rng_for("loot") == Sim.rng_for("loot"), "one generator per stream")
	var loot_a: Array = []
	for i in 4:
		loot_a.append(Sim.rng_for("loot").randi())
	Sim.reseed(Sim.DEFAULT_SEED)
	var loot_b: Array = []
	var ai: Array = []
	for i in 4:
		loot_b.append(Sim.rng_for("loot").randi())
		ai.append(Sim.rng_for("ai").randi())
	assert_eq(loot_b, loot_a, "reseed() resets every stream")
	assert_true(ai != loot_a, "streams are independent of each other")
	Sim.reseed(7)
	assert_eq(Sim.rng_for("loot").seed, 7 ^ hash("loot"), "reseed(seed) re-bases the streams")
	# The worked example still holds after stream draws: the giant's first light crit roll is the
	# first Sim.rng draw after reseeding, exactly as before.
	Sim.reseed(Sim.DEFAULT_SEED)
	var probe := RandomNumberGenerator.new()
	probe.seed = Sim.DEFAULT_SEED
	var will_crit := probe.randf() < 0.05
	var p := spawn_player(Vector3(0, 0.05, 0), 0.0)
	spawn_dummy(Vector3(0, 0, -2.6))
	await step_ticks(2)
	for i in 10:
		Sim.rng_for("debris").randf()
		Sim.rng_for("bot").randi()
	p.router.inject_light_attack()
	await step_ticks(45)
	var on := hits_on("dummy_01")
	assert_eq(on.size(), 1, "the light lands once")
	if on.size() == 1:
		assert_eq(on[0].crit, will_crit, "the crit roll is the unchanged first Sim.rng draw")
		assert_eq(on[0].health_damage, 55 if will_crit else 37, "light vs armor 25 = 37 (55 on a crit)")


# --------------------------------------------------------------------------- launch slots

func test_launch_slots_space_ranged_launches() -> void:
	Sim.clear_pending()
	assert_eq(Sim.last_launch_tick("player"), -1, "no launch yet")
	var t0 := Sim.tick
	assert_true(Sim.request_launch_slot("player", "valley.road.archer_a", 60), "first launch granted")
	assert_eq(Sim.last_launch_tick("player"), t0, "and recorded")
	assert_false(Sim.request_launch_slot("player", "valley.road.mage_a", 60), "a second shooter waits")
	await step_ticks(59)
	assert_false(Sim.request_launch_slot("player", "valley.road.mage_a", 60), "59 ticks is too soon")
	assert_eq(Sim.last_launch_tick("player"), t0, "a refused request records nothing")
	await step_ticks(1)
	assert_true(Sim.request_launch_slot("player", "valley.road.mage_a", 60), "60 ticks later it is granted")
	assert_eq(Sim.last_launch_tick("player"), t0 + 60, "recorded")
	assert_true(Sim.request_launch_slot("valley.village.guard_1", "x", 60), "slots are per target")
	Sim.clear_pending()
	assert_eq(Sim.last_launch_tick("player"), -1, "clear_pending() clears launch slots")
	assert_true(Sim.request_launch_slot("player", "valley.road.archer_a", 60), "granted again at once")


# --------------------------------------------------------------------------- dead shooters

func test_projectiles_outlive_a_shooter_that_died_earlier() -> void:
	var shooter := _bare("zz_shooter", "enemy.soldier")
	_bare("test.target_a", "prop.practice_dummy", CombatEntity.Team.NEUTRAL)
	# Same tick: the lethal hit resolves first (attacker "aa_killer" sorts first), then the
	# shooter's projectile from that same pass is dropped.
	Sim.queue_hit(_event("aa_killer", "zz_shooter", 100000.0))
	var arrow := _event("zz_shooter", "test.target_a", 20.0)
	arrow.from_projectile = true
	arrow.projectile_id = 1
	Sim.queue_hit(arrow)
	await step_ticks(1)
	assert_true(shooter.combatant.dead, "the shooter died")
	assert_eq(shooter.died_tick, Sim.tick, "died_tick records the death tick")
	assert_eq(hits_on("test.target_a").size(), 0, "a projectile hit from an owner killed this tick is dropped")
	var shooter2 := _bare("zz_shooter_2", "enemy.soldier")
	_bare("test.target_b", "prop.practice_dummy", CombatEntity.Team.NEUTRAL)
	Sim.queue_hit(_event("aa_killer", "zz_shooter_2", 100000.0))
	await step_ticks(1)
	assert_true(shooter2.combatant.dead, "the second shooter died")
	var in_flight := _event("zz_shooter_2", "test.target_b", 20.0)
	in_flight.from_projectile = true
	in_flight.projectile_id = 2
	Sim.queue_hit(in_flight)
	Sim.queue_hit(_event("zz_shooter_2", "test.target_b", 20.0))   # a melee hit from the corpse
	await step_ticks(1)
	assert_true(shooter2.died_tick < Sim.tick, "the owner died on an earlier tick")
	var on := hits_on("test.target_b")
	assert_eq(on.size(), 1, "only the projectile hit resolves")
	if on.size() == 1:
		assert_true(on[0].event.from_projectile, "the in-flight projectile still lands (decision 8)")
		assert_true(on[0].health_damage > 0, "and deals damage")


# --------------------------------------------------------------------------- statuses

func test_status_pass_heals_and_expires_through_sim() -> void:
	var patient := _bare("test.patient", "enemy.soldier")
	patient.combatant.pools.health = 100.0
	var t0 := Sim.tick
	assert_true(patient.apply_status(MEND, NAN, -1.0, "player"), "Mend applied")
	assert_eq(applied, [[t0, "test.patient", MEND, "player", 4.0]], "status_applied(tick, entity, status, source, duration)")
	await step_ticks(240)
	var total := 0.0
	for h: Array in healed:
		total += float(h[2])
		assert_eq(h[3], "player", "heals report the caster")
	assert_eq(healed.size(), 8, "8 heal ticks")
	assert_near(total, 100.0, 1e-6, "100 over 4 s")
	assert_near(patient.combatant.pools.health, 200.0, 1e-6, "applied to health")
	assert_eq(healed.back()[0], t0 + 240, "the last heal lands on the expiry tick")
	assert_eq(expired, [[t0 + 240, "test.patient", MEND]], "status_expired exactly once, at expiry")
	assert_false(patient.combatant.statuses.has(MEND), "gone")
	healed.clear()
	var full := _bare("test.nearly_full", "enemy.soldier")
	full.combatant.pools.health = 210.0
	full.apply_status(MEND, NAN, -1.0, "player")
	await step_ticks(240)
	assert_near(full.combatant.pools.health, 220.0, 1e-6, "healing caps at maximum health")
	var gained := 0.0
	for h: Array in healed:
		gained += float(h[2])
	assert_near(gained, 10.0, 1e-6, "healed reports only what was gained")


func test_status_immunity_death_and_unknown_cases() -> void:
	var boss := _bare("test.immune", "enemy.soldier")
	boss.combatant.status_immunities = PackedStringArray(["Slow"])
	assert_false(boss.apply_status(SLOW, NAN, -1.0, "player"), "a Slow-immune entity ignores slows")
	assert_eq(applied, [], "no status_applied")
	assert_true(boss.apply_status(MARK), "other statuses still apply")
	var corpse := _bare("test.corpse", "enemy.soldier")
	Sim.queue_hit(_event("aa_killer", "test.corpse", 100000.0))
	await step_ticks(1)
	assert_false(corpse.apply_status(MEND, NAN, -1.0, "player"), "the dead take no statuses")
	corpse.heal(50.0, "player")
	assert_near(corpse.combatant.pools.health, 0.0, 1e-9, "and no heals")
	var slowed := _bare("test.slowed", "enemy.soldier")
	assert_true(slowed.apply_status(SLOW, 0.5, 1.0, "player"), "magnitude and duration overrides")
	assert_near(slowed.combatant.move_mult(), 0.5, 1e-9, "magnitude 0.5")
	assert_near(slowed.combatant.statuses.remaining_s(SLOW, Sim.tick), 1.0, 1e-9, "duration 1 s")
	assert_near(float(applied.back()[4]), 1.0, 1e-9, "status_applied reports the applied duration")


func test_on_hit_statuses_and_morale() -> void:
	var target := _bare("test.morale_target", "enemy.soldier")
	var hit := _event("player", "test.morale_target", 10.0)
	hit.on_hit_statuses = [{"status": SLOW, "magnitude": 0.3, "duration_s": 3.0},
		{"status": MARK, "on_blocked": true}]
	hit.morale_damage = 20.0
	Sim.queue_hit(hit)
	await step_ticks(1)
	assert_true(target.combatant.statuses.has(SLOW), "HIT applies on_hit_statuses")
	assert_true(target.combatant.statuses.has(MARK), "all of them")
	assert_near(target.combatant.move_mult(), 0.7, 1e-9, "the slow's magnitude")
	assert_eq(target.actor.get("morale"), [[-20.0, "player"]], "morale damage reaches on_morale_delta")
	var blocker := _bare("test.blocker", "enemy.soldier")
	blocker.actor.set("blocking", true)
	var blocked := _event("player", "test.blocker", 10.0)
	blocked.on_hit_statuses = hit.on_hit_statuses
	blocked.morale_damage = 20.0
	Sim.queue_hit(blocked)
	await step_ticks(1)
	var r := hits_on("test.blocker")
	assert_true(r.size() == 1 and r[0].outcome == HitResult.Outcome.BLOCKED, "the hit was blocked")
	assert_false(blocker.combatant.statuses.has(SLOW), "BLOCKED skips entries without on_blocked")
	assert_true(blocker.combatant.statuses.has(MARK), "and applies those with it")
	assert_eq(blocker.actor.get("morale"), [[-20.0, "player"]], "morale damage also lands on a block")
	var dodger := _bare("test.dodger", "enemy.soldier")
	dodger.actor.set("invulnerable", true)
	var evaded := _event("player", "test.dodger", 10.0)
	evaded.on_hit_statuses = hit.on_hit_statuses
	evaded.morale_damage = 20.0
	Sim.queue_hit(evaded)
	await step_ticks(1)
	assert_true(dodger.combatant.statuses.is_empty(), "an evaded hit applies nothing")
	assert_eq(dodger.actor.get("morale"), [], "and no morale damage")
	var victim := _bare("test.victim", "enemy.soldier")
	var lethal := _event("player", "test.victim", 100000.0)
	lethal.on_hit_statuses = hit.on_hit_statuses
	lethal.morale_damage = 20.0
	Sim.queue_hit(lethal)
	await step_ticks(1)
	assert_true(victim.combatant.dead, "killed")
	assert_true(victim.combatant.statuses.is_empty(), "a killing hit applies no statuses")
	assert_eq(victim.actor.get("morale"), [], "and no morale damage")


func test_stone_skin_on_the_real_dummy() -> void:
	var dummy := spawn_dummy(Vector3(0, 0, -2.6))
	await step_ticks(1)
	assert_true(TargetingRules.player_may_target(dummy.entity), "the practice dummy is a valid target")
	queue_hit("player", "dummy_01", Vector3(0, 0, 0), 40.0, PackedStringArray(["Melee"]), 3.6576)
	await step_ticks(1)
	assert_true(dummy.entity.apply_status(SKIN, NAN, -1.0, "dummy_01"), "Stone Skin on the dummy")
	queue_hit("player", "dummy_01", Vector3(0, 0, 0), 40.0, PackedStringArray(["Melee"]), 3.6576)
	await step_ticks(1)
	var on := hits_on("dummy_01")
	assert_eq(on.size(), 2, "two hits")
	if on.size() == 2:
		assert_eq(on[0].health_damage, 37, "37 without Stone Skin")
		assert_eq(on[1].health_damage, 30, "30 with +30 armor")
	assert_near(dummy.entity.combatant.armor, 25.0, 1e-9, "base armor is never mutated")
