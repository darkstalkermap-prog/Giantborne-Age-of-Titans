extends IntegrationSuite
## E1: Orrik the Fetterer's fight in the Moot test arena (scenes/test/throne_test.tscn): his scene (HeirEnemy on the
## player's own giant body at 31.5 m, his plates' hurtboxes and anchors), the warband's crews brought in when the fight
## engages, the winches joining by his phases, a winch's harpoon telegraphed and binding a chain where it strikes, the
## chain holding the giant to its circle and torn by his pull or his heave (and the winch wrenched out of the ground),
## his hook and the haul that drags the giant, the Throne-breaker for a bound giant (telegraphed, and not swung at one
## who tore free), the chain-coil's break ending his hook, his armour coming off his look as it breaks, his death
## breaking the warband and dropping his parts, a new attempt making everything whole. Scripted blows through the
## ordinary resolution.

const ARENA := "res://scenes/test/throne_test.tscn"

var level: Node3D
var telegraphs: Array = []
var bound: Array = []
var torn: Array = []
var counts := {}


func before_each() -> void:
	await super()
	telegraphs.clear()
	bound.clear()
	torn.clear()
	counts.clear()
	WorldState.clear()
	Events.telegraph_started.connect(_on_telegraph)
	Events.fetter_bound.connect(_on_bound)
	Events.fetter_torn.connect(_on_torn)
	Events.loot_awarded.connect(_on_loot_count)


func after_each() -> void:
	for sig: Signal in [Events.telegraph_started, Events.fetter_bound, Events.fetter_torn, Events.loot_awarded]:
		for c: Dictionary in sig.get_connections():
			if (c.callable as Callable).get_object() == self:
				sig.disconnect(c.callable)
	PersonRig.reset_for_tests()
	await super()


func _on_telegraph(t: int, key: String, action_id: String, _target: String, shape: String, origin: Vector3,
		_yaw: float, _radius: float, _length: float, duration: float) -> void:
	telegraphs.append([t, key, action_id, shape, origin, duration])


func _on_bound(t: int, _id: String, anchor: String, kind: String, n: int) -> void:
	bound.append([t, anchor, kind, n])


func _on_torn(t: int, _id: String, anchor: String, how: String, n: int) -> void:
	torn.append([t, anchor, how, n])


func _on_loot_count(_t: int, _w: String, item: String, c: int, _r: String) -> void:
	counts[item] = int(counts.get(item, 0)) + c


func _load(stage := 8, branch := "vengeance") -> Dictionary:
	level = (load(ARENA) as PackedScene).instantiate() as Node3D
	var arena := level.get_node("BossArena") as ThroneChallenge
	arena.branch_override = branch
	world.add_child(level)
	var p := level.get_node("Player") as GiantPlayer
	p.router.use_injection = true
	await TestWait.until(self, func() -> bool: return p.is_on_floor(), 30)
	TitanDuel.prepare(p, stage)
	var t := level.get_node("Orrik") as HeirEnemy
	return {"player": p, "titan": t, "arena": arena}


func _winches() -> Array:
	var out: Array = []
	for n in level.get_node("Props").get_children():
		if n is FetterWinch:
			out.append(n)
	return out


## Binds a chain from `anchor_id` on the giant as its blow would (PlayerFetter.bind).
func _bind(p: GiantPlayer, anchor_id: String, kind := "winch") -> bool:
	return p.fetter.bind(anchor_id, kind)


func _blow(p: GiantPlayer, t: TitanEnemy, region: String, power: float, heavy := false) -> void:
	var e := HitEvent.new()
	e.tick = Sim.tick
	e.instance_id = Sim.new_instance_id()
	e.attacker_id = p.entity.entity_id
	e.target_id = t.entity_id
	e.power = power
	e.attacker_stat = 0.0
	e.size_policy = "none"
	e.poise_damage = 1.0
	e.attacker_height_m = 29.0
	e.tags = PackedStringArray(["Melee", "BasicAttack", "Heavy"] if heavy else ["Melee", "BasicAttack", "Light"])
	e.region = region
	e.attacker_position = p.global_position
	Sim.queue_hit(e)


func _winch(id: String) -> FetterWinch:
	for w: FetterWinch in _winches():
		if w.world_id == id:
			return w
	return null


func test_his_scene_and_record() -> void:
	var rec := GameData.get_record("enemy.orrik")
	assert_near(float(rec.height_m), 31.5, 1e-6, "103 ft: a little over a stage-8 giant (29.3 m), under stage 9 (35.4 m)")
	assert_eq(str(rec.appearance), "appearance_preset.npc_orrik", "a look of his own")
	var scene := (load("res://scenes/enemies/orrik.tscn") as PackedScene).instantiate()
	assert_true(scene is HeirEnemy, "a HeirEnemy (a TitanEnemy)")
	var rig := scene.get_node_or_null("Visual")
	assert_true(rig is SkinnedRig, "the player's own giant body (SkinnedRig)")
	if rig != null:
		assert_near(float(rig.get("fixed_body_scale")), 31.5 / 3.6576, 1e-3, "at k = 31.5 / 3.6576: proportions as the giant's")
	for n: String in ["Head", "ShoulderL", "ShoulderR", "ForearmL", "ArmR", "Torso", "Legs"]:
		assert_true(scene.get_node_or_null("Hurtboxes/" + n) != null, "a hurtbox %s" % n)
	for n: String in ["PlateHelm", "PlateSpaulderL", "PlateSpaulderR", "PlateCoil", "PlateGreaves", "Torso"]:
		assert_true(scene.get_node_or_null("Anchors/" + n) != null, "an anchor %s" % n)
	var head := scene.get_node("Hurtboxes/Head") as Node3D
	assert_true(head.position.y > 26.0 and head.position.y < 30.0, "his head in a stage-8 giant's reach (%.1f m)" % head.position.y)
	scene.free()


func test_the_warband_comes_with_the_fight_and_the_winches_join_by_his_phases() -> void:
	var s := await _load(8)
	var p: GiantPlayer = s.player
	var t: HeirEnemy = s.titan
	p.global_position = Vector3(0, 0.05, 40)
	for w: FetterWinch in _winches():
		assert_true(w.fire_held, "%s holds its fire before the fight" % w.world_id)
	(s.arena as ThroneChallenge).engage()
	await step_ticks(90)
	var crewed := 0
	for w: FetterWinch in _winches():
		crewed += 1 if w.is_crewed() else 0
	assert_eq(crewed, 5, "every winch has its Skarn giant")
	assert_false(_winch("test.throne.winch_1").fire_held, "the first two join as the fight engages")
	assert_false(_winch("test.throne.winch_2").fire_held, "the first two join as the fight engages")
	assert_true(_winch("test.throne.winch_3").fire_held, "the reserve waits for his horn")
	t.ai_enabled = false
	t.brain.update_boss_phase(0.6, Sim.tick)
	await step_ticks(2)
	for id: String in ["test.throne.winch_3", "test.throne.winch_4", "test.throne.winch_5"]:
		assert_false(_winch(id).fire_held, "%s joins at his second phase" % id)
	(s.arena as ThroneChallenge).disengage()
	await step_ticks(2)
	for w: FetterWinch in _winches():
		assert_true(w.fire_held, "%s holds its fire again after a new attempt" % w.world_id)


func test_a_harpoon_is_telegraphed_then_binds() -> void:
	var s := await _load(8)
	var p: GiantPlayer = s.player
	var t: HeirEnemy = s.titan
	t.ai_enabled = false
	p.global_position = Vector3(0, 0.05, 10)
	(s.arena as ThroneChallenge).engage()
	t.ai_enabled = false
	var start := Sim.tick
	while bound.is_empty() and Sim.tick - start < 60 * 20:
		await step_ticks(1)
	assert_false(bound.is_empty(), "a harpoon bit")
	var line_before := false
	for tg: Array in telegraphs:
		if str(tg[2]) == "ability.fetter_harpoon" and str(tg[3]) == "line" and int(tg[0]) < int((bound[0] as Array)[0]) - 30:
			line_before = true
	assert_true(line_before, "its aim line came before it, half a second and more")
	assert_eq(str((bound[0] as Array)[2]), "winch", "a winch's chain")
	assert_true(p.fetter.count() >= 1, "on the giant")


func test_the_throne_breaker_comes_for_a_bound_giant_and_not_for_a_free_one() -> void:
	var s := await _load(8)
	var p: GiantPlayer = s.player
	var t: HeirEnemy = s.titan
	p.global_position = Vector3(0, 0.05, 0)
	(s.arena as ThroneChallenge).engage()
	for w: FetterWinch in _winches():
		w.set_fire_held(true)
	await step_ticks(30)
	assert_true(_bind(p, _winch("test.throne.winch_1").entity.entity_id), "a chain")
	assert_true(_bind(p, _winch("test.throne.winch_2").entity.entity_id), "a second: bound")
	var hb := t.heir_brain()
	var start := Sim.tick
	var windup_at := -1
	while Sim.tick - start < 60 * 15:
		await step_ticks(1)
		for w: FetterWinch in _winches():
			w.set_fire_held(true)
		if t.controller.action_id() == "ability.orrik_throne_breaker":
			windup_at = Sim.tick
			break
	assert_true(windup_at > 0, "he raised the Throne-breaker over a bound giant (%s)" % str(hb.sequence_log))
	var warned := false
	for tg: Array in telegraphs:
		if str(tg[2]) == "ability.orrik_throne_breaker" and int(tg[0]) >= windup_at - 1:
			warned = true
	assert_true(warned, "its warning on the ground as the axe goes up")
	assert_true(GameData.get_action("ability.orrik_throne_breaker").windup_ticks >= 144, "a long warning")
	# a free giant: the answer is dropped before the swing begins
	p.fetter.release_all("cut")
	t.controller.call("_finish_action", true)
	hb._answer = ""
	hb._answer_kind = ""
	var before := hb.breaker_answers
	await step_ticks(60 * 12)
	assert_eq(hb.breaker_answers, before, "no Throne-breaker for a free giant")


func test_his_hook_bites_the_haul_drags_and_a_torn_hook_yanks_him() -> void:
	var s := await _load(8)
	var p: GiantPlayer = s.player
	var t: HeirEnemy = s.titan
	p.global_position = Vector3(0, 0.05, 30)
	(s.arena as ThroneChallenge).engage()
	t.brain.update_boss_phase(0.6, Sim.tick)
	await step_ticks(1)
	for w: FetterWinch in _winches():
		w.set_fire_held(true)
	var start := Sim.tick
	while t.hooks_bit == 0 and Sim.tick - start < 60 * 40:
		await step_ticks(1)
		for w: FetterWinch in _winches():
			w.set_fire_held(true)
	assert_true(t.hooks_bit >= 1, "his hook bit (%s)" % str(t.heir_brain().sequence_log))
	assert_true(p.fetter.holds(t.entity_id), "its chain runs to him")
	var length0 := 0.0
	for f: Dictionary in p.fetter.fetters:
		if str(f.anchor) == t.entity_id:
			length0 = float(f.length)
	start = Sim.tick
	while t.hauls == 0 and Sim.tick - start < 60 * 4:
		await step_ticks(1)
	await step_ticks(int(60 * 1.8))
	assert_true(t.hauls >= 1, "the haul follows the hook")
	var length1 := length0
	for f: Dictionary in p.fetter.fetters:
		if str(f.anchor) == t.entity_id:
			length1 = float(f.length)
	assert_true(length1 < length0 - 8.0, "the haul shortened his chain (%.1f -> %.1f m)" % [length0, length1])
	if p.fetter.holds(t.entity_id):
		var heavy := GameData.get_action(str(p.controller.loadout.get("heavy", "")))
		p.fetter.on_action_started(heavy, 1)
		await step_ticks(2)
		assert_false(p.fetter.holds(t.entity_id), "a heave tore the hook's chain")
		assert_true(t.yanks >= 1 and t.controller.state == CombatController.State.STAGGERED, "and yanked him off balance")


func test_the_coil_ends_his_hook_and_his_armour_comes_off_as_it_breaks() -> void:
	var s := await _load(8)
	var p: GiantPlayer = s.player
	var t: HeirEnemy = s.titan
	t.ai_enabled = false
	assert_true(t.worn_garments().has("garment.iron_vambraces"), "the coil's iron on his arm")
	assert_true(t.worn_garments().has("garment.horned_helm"), "his helm")
	assert_true(_bind(p, t.entity_id, "hook"), "on his hook")
	assert_true(t.break_plate("chain_coil"), "the coil breaks")
	await step_ticks(2)
	assert_true(t.heir_brain().hook_lost, "no more hook")
	assert_false(p.fetter.holds(t.entity_id), "the giant on it is free")
	assert_false(t.worn_garments().has("garment.iron_vambraces"), "the coil's iron is gone from his look")
	t.break_plate("spaulder_l")
	assert_true(t.worn_garments().has("garment.bone_spaulders"), "one spaulder broken: the trophies still hang")
	t.break_plate("spaulder_r")
	assert_false(t.worn_garments().has("garment.bone_spaulders"), "both broken: the trophies are gone")
	t.break_plate("helm")
	assert_false(t.worn_garments().has("garment.horned_helm"), "his helm is gone")
	t.p34_reset_attempt()
	await step_ticks(2)
	assert_true(t.worn_garments().has("garment.horned_helm"), "a new attempt: whole again")
	assert_false(t.heir_brain().hook_lost, "and his hook back")


func test_his_death_breaks_the_warband_and_drops_his_parts() -> void:
	var s := await _load(8)
	var p: GiantPlayer = s.player
	var t: HeirEnemy = s.titan
	p.global_position = Vector3(0, 0.05, 30)
	(s.arena as ThroneChallenge).engage()
	await step_ticks(60)
	t.ai_enabled = false
	var d := (s.arena as ThroneChallenge)._director()
	assert_eq(d.encounter_state("encounter.throne_test_warband"), "active", "the warband is here")
	t.break_plate("helm")
	t.entity.combatant.pools.health = 1.0
	_blow(p, t, "torso", 5000.0, true)
	await step_ticks(5)
	assert_false(t.entity.is_alive(), "he falls")
	assert_eq((s.arena as ThroneChallenge).state, BossArena.State.DEFEATED, "the fight is won")
	await step_ticks(5)
	assert_true(d.encounter_state("encounter.throne_test_warband") != "active", "the warband breaks and leaves")
	assert_eq(int(counts.get("item.heir_torc", 0)), 1, "the Heir's Torc")
	assert_eq(int(counts.get("item.fetter_iron", 0)), 7, "six links of fetter-iron and the helm's")
	assert_eq(int(counts.get("item.trophy_bone", 0)), 2, "two trophy bones")
	for w: FetterWinch in _winches():
		assert_false(w.can_shoot() and not w.fire_held and w.is_crewed(), "%s stands abandoned" % w.world_id)


## A colossus who never answers: the winches chain him and Orrik breaks him (40 s of the fight, no input).
func test_an_idle_colossus_is_chained_and_broken() -> void:
	var s := await _load(8)
	var p: GiantPlayer = s.player
	var t: HeirEnemy = s.titan
	p.global_position = Vector3(0, 0.05, 20)
	(s.arena as ThroneChallenge).engage()
	var full := p.entity.combatant.pools.health_max
	for i in 40:
		await step_ticks(60)
		if not p.entity.is_alive():
			break
	var crewed := 0
	for w: FetterWinch in _winches():
		crewed += 1 if w.is_crewed() else 0
	assert_true(crewed >= 2, "the crews came (%d winches crewed)" % crewed)
	assert_true(bound.size() >= 1, "the winches chained him (%d)" % bound.size())
	var left := p.entity.combatant.pools.health if p.entity.is_alive() else 0.0
	assert_true(left < full * 0.6, "and Orrik broke him (%.0f of %.0f left; %s)" % [left, full,
		str((t.brain as TitanBrain).sequence_log)])
