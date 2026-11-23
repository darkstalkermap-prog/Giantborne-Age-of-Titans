extends IntegrationSuite
## B3: the Rootwarden's fight in the grove test arena (scenes/test/grove_test.tscn): his scene (TitanEnemy, his bark
## plates' hurtboxes and anchors following the kneel), asleep until a blow or the arena wakes him, rooted until his
## second phase; a broken plate's wound open then regrowing then whole again; a brazier smashed beside him sets him
## burning and sears the open wounds (no regrowth); the knot withers every wound's clock and uproots him (phase 2:
## the uproot, then he walks; the grove's falling trees); the snare binds the giant's feet; the stomp answers a giant
## at his feet; his death and his loot (the broken plates' bark). Scripted blows through the ordinary resolution.

const GROVE := "res://scenes/test/grove_test.tscn"

var level: Node3D
var events: Array = []
var counts := {}


func before_each() -> void:
	await super()
	events.clear()
	counts.clear()
	Events.loot_awarded.connect(_on_loot_count)
	Events.plate_regrowing.connect(_on_regrowing)
	Events.plate_regrown.connect(_on_regrown)
	Events.plate_seared.connect(_on_seared)
	Events.titan_withered.connect(_on_withered)
	Events.titan_woke.connect(_on_woke)


func after_each() -> void:
	for sig: Signal in [Events.plate_regrowing, Events.plate_regrown, Events.plate_seared, Events.titan_withered,
			Events.titan_woke, Events.loot_awarded]:
		for c: Dictionary in sig.get_connections():
			if (c.callable as Callable).get_object() == self:
				sig.disconnect(c.callable)
	PersonRig.reset_for_tests()
	await super()


func _on_loot_count(_t: int, _w: String, item: String, c: int, _r: String) -> void:
	counts[item] = int(counts.get(item, 0)) + c


func _on_regrowing(t: int, id: String, plate: String) -> void:
	events.append([t, "regrowing", id, plate])


func _on_regrown(t: int, id: String, plate: String) -> void:
	events.append([t, "regrown", id, plate])


func _on_seared(t: int, id: String, plate: String) -> void:
	events.append([t, "seared", id, plate])


func _on_withered(t: int, id: String, plate: String, seconds: float) -> void:
	events.append([t, "withered", id, plate, seconds])


func _on_woke(t: int, id: String, reason: String) -> void:
	events.append([t, "woke", id, reason])


func _kinds() -> Array:
	var out: Array = []
	for e: Array in events:
		out.append(str(e[1]) + ":" + str(e[3]))
	return out


func _load(stage := 5) -> Dictionary:
	level = (load(GROVE) as PackedScene).instantiate() as Node3D
	level.set("stage", 0)
	world.add_child(level)
	var p := level.get_node("Player") as GiantPlayer
	p.router.use_injection = true
	await TestWait.until(self, func() -> bool: return p.is_on_floor(), 30)
	TitanDuel.prepare(p, stage)
	var t := level.get_node("Rootwarden") as TitanEnemy
	return {"player": p, "titan": t}


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
	e.tags = PackedStringArray(["Melee", "Heavy"] if heavy else ["Melee"])
	e.region = region
	e.attacker_position = p.global_position
	Sim.queue_hit(e)


func test_his_scene_and_record() -> void:
	var rec := GameData.get_record("enemy.rootwarden")
	assert_near(float(rec.height_m), 21.3, 1e-6, "70 ft")
	assert_true(bool(rec.dormant), "he sleeps")
	assert_eq(int(rec.rooted_until_phase), 2, "rooted till his second phase")
	var scene := (load("res://scenes/enemies/rootwarden.tscn") as PackedScene).instantiate()
	assert_true(scene is TitanEnemy, "a TitanEnemy")
	for n: String in ["ShoulderL", "ShoulderR", "Back", "ForearmR", "Knot", "ShinL", "ShinR", "Head", "ArmL", "Torso",
			"Legs"]:
		var hb := scene.get_node_or_null("Hurtboxes/" + n) as Node3D
		assert_true(hb != null, "a hurtbox %s" % n)
		if hb != null:
			assert_true(hb.has_meta(TitanEnemy.KNEEL_META), "%s follows the kneel" % n)
	for n: String in ["PlateShoulderL", "PlateShoulderR", "PlateBack", "PlateForearmR", "PlateKnot", "PlateShinL",
			"PlateShinR", "Torso", "KneeL", "KneeR"]:
		assert_true(scene.get_node_or_null("Anchors/" + n) != null, "an anchor %s" % n)
	var sh := (scene.get_node("Hurtboxes/ShoulderL") as Node3D)
	assert_true(sh.position.y > 15.0, "his shoulders over a stage-5 giant's head (%.1f m)" % sh.position.y)
	var k: Vector3 = sh.get_meta(TitanEnemy.KNEEL_META)
	assert_true(k.y < sh.position.y - 3.0, "they come down when he kneels (%.1f m)" % k.y)
	var knot := scene.get_node("Hurtboxes/Knot") as Node3D
	assert_true(knot.position.y < 14.0 and knot.position.x < 0.0, "the knot on his left forearm, in a stage-5 giant's reach")
	scene.free()


func test_he_sleeps_until_a_blow_wakes_him() -> void:
	var n := await _load()
	var p: GiantPlayer = n.player
	var t: TitanEnemy = n.titan
	assert_true(t.dormant, "asleep")
	assert_false(t.ai_enabled, "his AI off")
	assert_true(t.is_rooted(), "rooted")
	# a giant walking up to him does not wake him
	p.global_position = t.global_position + Vector3(0, 0, 14)
	await step_ticks(90)
	assert_true(t.dormant, "still asleep beside a giant")
	assert_eq(t.controller.action, null, "no strike")
	var arena := level.get_node("BossArena") as BossArena
	assert_false(arena.is_engaged(), "the arena waits")
	_blow(p, t, "torso", 40.0)
	await step_ticks(2)
	assert_false(t.dormant, "a blow wakes him")
	assert_true(t.ai_enabled, "his AI on")
	assert_eq(t.wake_reason, "struck", "struck")
	assert_true(arena.is_engaged(), "his ground engaged")
	assert_true(_kinds().has("woke:struck"), "titan_woke(struck)")
	await step_ticks(240)
	assert_true(Vector2(t.global_position.x - (-0.0), t.global_position.z - (-18.0)).length() < 0.5,
		"rooted: he has not walked (%.2f m)" % Vector2(t.global_position.x, t.global_position.z + 18.0).length())


func test_the_arena_engaging_wakes_him() -> void:
	var n := await _load()
	var t: TitanEnemy = n.titan
	(level.get_node("BossArena") as BossArena).engage()
	await step_ticks(1)
	assert_false(t.dormant, "awake")
	assert_eq(t.wake_reason, "engaged", "engaged")


func test_a_broken_plate_grows_back_unless_burned() -> void:
	var n := await _load()
	var p: GiantPlayer = n.player
	var t: TitanEnemy = n.titan
	t.wake("test")
	t.ai_enabled = false
	var ps := t.plates()
	var rg: Dictionary = ps.plate("shoulder_l").regrow
	_blow(p, t, "shoulder_l", 5000.0, true)
	await step_ticks(1)
	assert_true(ps.is_broken("shoulder_l"), "broken")
	assert_eq(ps.wound_state("shoulder_l"), PlateRules.WOUND_OPEN, "the wound open")
	await step_ticks(int(float(rg.after_s) * 60.0) + 2)
	assert_eq(ps.wound_state("shoulder_l"), PlateRules.WOUND_REGROWING, "regrowing after after_s")
	assert_true(_kinds().has("regrowing:shoulder_l"), "announced")
	await step_ticks(int(float(rg.over_s) * 60.0) + 2)
	assert_false(ps.is_broken("shoulder_l"), "whole again")
	assert_true(_kinds().has("regrown:shoulder_l"), "announced")
	assert_near(ps.health_frac("shoulder_l"), float(rg.health_frac), 1e-3, "with its share of the bark")
	assert_false(t.plate_breaks.has("shoulder_l"), "no longer listed broken")
	# burned: a brazier smashed beside him sets him burning; the open wound is seared and never regrows
	_blow(p, t, "back", 5000.0, true)
	await step_ticks(1)
	assert_true(ps.is_broken("back"), "his back broken")
	var brazier: BreakableProp = null
	for b in get_tree().get_nodes_in_group("breakables"):
		if str(b.get("world_id")) == "test.grove.brazier_1":
			brazier = b as BreakableProp
	assert_true(brazier != null, "a brazier in the grove")
	assert_true(brazier.global_position.distance_to(t.global_position) <= float(t.record.fire.brazier_radius_m),
		"within his fire's reach")
	queue_hit(p.entity.entity_id, brazier.entity.entity_id, brazier.global_position + Vector3(0, 1, 3), 500.0)
	await step_ticks(3)
	assert_true(t.p34_has_status_tag("Burning"), "he burns")
	assert_eq(t.fire_ignitions, 1, "one ignition")
	assert_eq(ps.wound_state("back"), PlateRules.WOUND_SEARED, "the open wound is seared")
	assert_true(_kinds().has("seared:back"), "announced")
	await step_ticks(int((float(ps.plate("back").regrow.after_s) + float(ps.plate("back").regrow.over_s)) * 60.0) + 30)
	assert_true(ps.is_broken("back"), "a seared wound never grows back")


func test_the_knot_withers_his_wounds_and_uproots_him() -> void:
	var n := await _load()
	var p: GiantPlayer = n.player
	var t: TitanEnemy = n.titan
	t.wake("test")
	t.ai_enabled = false
	var ps := t.plates()
	_blow(p, t, "shoulder_r", 5000.0, true)
	await step_ticks(1)
	await step_ticks(60)
	_blow(p, t, "knot", 5000.0, true)
	await step_ticks(1)
	assert_true(ps.is_broken("knot"), "the knot broken")
	assert_true(ps.is_withered(Sim.tick), "withered")
	assert_true(_kinds().has("withered:knot"), "titan_withered")
	var open_at := int(ps.wounds.shoulder_r.open_ticks)
	await step_ticks(600)
	assert_eq(int(ps.wounds.shoulder_r.open_ticks), open_at, "the shoulder's wound waits")
	assert_true(ps.is_broken("shoulder_r"), "and stays open")
	# the knot's break uproots him: phase 2 (once the break's stagger has played out), its enter action
	t.ai_enabled = true
	await TestWait.until(self, func() -> bool: return t.brain.boss_phase() == 2, 400)
	assert_eq(t.brain.boss_phase(), 2, "phase 2 on the knot's break")
	assert_false(t.is_rooted(), "uprooted: he may walk")
	await step_ticks(2)
	assert_true(started.has(t.entity_id + ":ability.rootwarden_uproot"), "he tears free (%s)" % str(started))
	assert_eq((t.brain as TitanBrain).phase_hazard(), "ability.rootwarden_treefall", "the grove's trees begin to fall")


func test_the_snare_binds_the_giants_feet() -> void:
	var n := await _load()
	var p: GiantPlayer = n.player
	var t: TitanEnemy = n.titan
	t.wake("test")
	t.ai_enabled = false
	p.global_position = t.global_position + Vector3(4, 0, 22)
	await step_ticks(2)
	t.brain.target_id = p.entity.entity_id
	t.controller.force_action(GameData.get_action("ability.rootwarden_snare"))
	await step_ticks(2)
	assert_near(t.runner.aim_point.distance_to(p.global_position), 0.0, 0.5, "the circle committed at the giant's feet")
	await TestWait.until(self, func() -> bool: return p.entity.combatant.statuses.has("status.rooted"), 140)
	assert_true(p.entity.combatant.statuses.has("status.rooted"), "rooted")
	assert_true(p.entity.combatant.move_mult() < 0.2, "hardly able to move")
	# B4: and it reads bound - a status tint of its own (B3's showed only the hit's white flash)
	var tint := Color(0, 0, 0, 0)
	for entry: Array in HitFeedback.STATUS_TINTS:
		if str(entry[0]) == "status.rooted":
			tint = entry[1]
	assert_true(tint.a > 0.0, "the Rooted status has a tint")
	var fb := HitFeedback.new()
	world.add_child(fb)
	fb.call("_refresh_tint", p.entity.entity_id)
	assert_eq(p.rig.status_tint(), tint, "the bound giant wears it")
	fb.queue_free()


func test_the_stomp_answers_a_giant_at_his_feet() -> void:
	var n := await _load()
	var p: GiantPlayer = n.player
	var t: TitanEnemy = n.titan
	(level.get_node("BossArena") as BossArena).engage()
	await step_ticks(1)
	p.global_position = t.global_position + Vector3(0, 0, 6.5)
	var stomped := false
	for i in 900:
		await step_ticks(1)
		p.global_position = t.global_position + Vector3(0, 0, 6.5)
		p.entity.combatant.pools.health = p.entity.combatant.pools.health_max
		if t.controller.action != null and t.controller.action.id == "ability.rootwarden_stomp":
			stomped = true
			break
	assert_true(stomped, "a giant hugging his legs is stomped")
	assert_true((t.brain as TitanBrain).hug_answers >= 1 or (t.brain as TitanBrain).sequence_log.has(
		"hug:ability.rootwarden_stomp"), "the hug answer")


func test_his_death_drops_his_parts() -> void:
	var n := await _load()
	var p: GiantPlayer = n.player
	var t: TitanEnemy = n.titan
	t.wake("test")
	t.ai_enabled = false
	_blow(p, t, "shoulder_l", 5000.0, true)
	await step_ticks(1)
	assert_true(t.plates().is_broken("shoulder_l"), "a shoulder broken")
	t.entity.combatant.pools.health = 10.0
	_blow(p, t, "torso", 5000.0, true)
	await step_ticks(3)
	assert_false(t.entity.is_alive(), "dead")
	var got := counts
	assert_true(int(got.get("item.warden_heartwood", 0)) >= 1, "his heartwood")
	assert_true(int(got.get("item.warden_bark", 0)) >= 5, "four bark and the broken shoulder's (%d)" % int(
		got.get("item.warden_bark", 0)))
	assert_true(int(got.get("item.amber_sap", 0)) >= 3, "his sap")
