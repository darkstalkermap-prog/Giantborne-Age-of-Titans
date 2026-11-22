extends IntegrationSuite
## A4: Stoneback beaten by fighting like a giant - his shin plates break (PlateRules' on_break "topple") and drop
## him to a knee for a few seconds (TitanEnemy: a stagger of the kneel, down_s and the rise), his upper hurtboxes and
## lock anchors following the kneel down into a smaller giant's reach (each node's kneel_position, from the kneel
## clip's bones), every blow and a Heavy above all landing harder while he is down; enough damage to the broken shin
## drops him again, no sooner than again_immune_s after he rose; he is dazed (recover_s) before his next strike.
## In the quarry test arena (his AI off), with scripted blows through the ordinary resolution.

const QUARRY := "res://scenes/test/quarry_test.tscn"

var level: Node3D
var toppled: Array = []
var rose: Array = []


func before_each() -> void:
	await super()
	toppled.clear()
	rose.clear()
	Events.titan_toppled.connect(_on_toppled)
	Events.titan_rose.connect(_on_rose)


func after_each() -> void:
	for sig: Signal in [Events.titan_toppled, Events.titan_rose]:
		for c: Dictionary in sig.get_connections():
			if (c.callable as Callable).get_object() == self:
				sig.disconnect(c.callable)
	PersonRig.reset_for_tests()
	await super()


func _on_toppled(tick: int, id: String, plate: String, seconds: float) -> void:
	toppled.append([tick, id, plate, seconds])


func _on_rose(tick: int, id: String) -> void:
	rose.append([tick, id])


func _load(skinned := false) -> Dictionary:
	if skinned:
		PersonRig.enable_for_tests()
	level = (load(QUARRY) as PackedScene).instantiate() as Node3D
	level.set("stage", 0)
	world.add_child(level)
	var p := level.get_node("Player") as GiantPlayer
	p.router.use_injection = true
	await TestWait.until(self, func() -> bool: return p.is_on_floor(), 30)
	TitanDuel.prepare(p, 5)
	var t := level.get_node("Stoneback") as TitanEnemy
	t.ai_enabled = false
	t.brain.target_id = p.entity.entity_id
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


func _hb(t: TitanEnemy, node_name: String) -> Node3D:
	return t.get_node("Hurtboxes/" + node_name) as Node3D


func test_the_record_and_the_scene_carry_the_topple() -> void:
	var rec := GameData.get_record("enemy.stoneback")
	var top := PlateRules.parse_topple(rec)
	assert_false(top.is_empty(), "his record topples him")
	var shin := {}
	for pl: Dictionary in PlateRules.parse(rec):
		if str(pl.id) == "shin_l":
			shin = pl
	assert_eq(str(shin.effect), PlateRules.EFFECT_TOPPLE, "his shin's break topples him")
	assert_true(bool(shin.breakable) and float(shin.health) > 0.0, "a breakable shin with stone")
	# the clips' lengths are the record's kneel and rise
	assert_near(float(top.kneel_s), BruteRig.clip_length(StonebackRig.CREATURE, "kneel"), 0.05, "the kneel's length")
	assert_near(float(top.rise_s), BruteRig.clip_length(StonebackRig.CREATURE, "rise"), 0.05, "the rise's length")
	var scene := (load("res://scenes/enemies/stoneback.tscn") as PackedScene).instantiate()
	for n: String in ["Hurtboxes/Brow", "Hurtboxes/ShoulderL", "Hurtboxes/ShoulderR", "Hurtboxes/Back",
			"Anchors/PlateBrow", "Anchors/PlateBack", "Anchors/PlateShinL", "Anchors/PlateShinR"]:
		var node := scene.get_node(n) as Node3D
		assert_true(node.has_meta(TitanEnemy.KNEEL_META), "%s follows the kneel" % n)
		if n.begins_with("Hurtboxes/") or n in ["Anchors/PlateBrow", "Anchors/PlateBack"]:
			var k: Vector3 = node.get_meta(TitanEnemy.KNEEL_META)
			assert_true(k.y < node.position.y - 3.0, "%s comes down on the knee (%.1f -> %.1f m)" % [n, node.position.y, k.y])
			assert_true(k.y < 12.0, "%s within a stage-5 giant's comfortable swing (%.1f m)" % [n, k.y])
	scene.free()


func test_a_broken_shin_drops_him_to_a_knee_and_lowers_his_upper_body() -> void:
	var n := await _load()
	var p: GiantPlayer = n.player
	var t: TitanEnemy = n.titan
	var brow0 := _hb(t, "Brow").position
	var back0 := _hb(t, "Back").position
	var stone := float(t.plates().plate("shin_l").health)
	_blow(p, t, "shin_l", stone * 2.0, true)
	await step_ticks(1)
	assert_true(t.plates().is_broken("shin_l"), "the shin breaks")
	assert_true(t.is_down(), "he goes down")
	assert_eq(toppled.size(), 1, "titan_toppled once")
	assert_eq(str(toppled[0][2]), "shin_l", "for the shin")
	assert_eq(t.controller.state, CombatController.State.STAGGERED, "a stagger")
	assert_eq(t.controller.stagger_reason, TitanEnemy.TOPPLE_REASON, "of reason topple")
	var total := PlateRules.down_total_s(t.plates().plate("shin_l"), t.topple)
	assert_near(t.down_total_s(), total, 1.0 / 60.0, "the kneel, the time down and the rise")
	# half way through: on his knee, his upper hurtboxes lowered
	await step_ticks(int(total * 0.5 * Sim.TICK_RATE))
	assert_near(t.down_weight, 1.0, 1e-6, "on his knee")
	assert_true(_hb(t, "Brow").position.y < brow0.y - 4.0, "his brow is lowered (%.1f m)" % _hb(t, "Brow").position.y)
	assert_true(_hb(t, "Back").position.y < back0.y - 3.0, "his back too")
	# the physics follows: a sphere where the lowered brow is finds his brow hurtbox
	var q := PhysicsShapeQueryParameters3D.new()
	var sp := SphereShape3D.new()
	sp.radius = 0.6
	q.shape = sp
	q.collision_mask = HitQueryAdapter.LAYER_HURTBOX
	q.collide_with_areas = true
	q.collide_with_bodies = false
	q.transform = Transform3D(Basis(), _hb(t, "Brow").global_position)
	var found := false
	for r: Dictionary in level.get_world_3d().direct_space_state.intersect_shape(q, 32):
		if r.get("collider") == _hb(t, "Brow"):
			found = true
	assert_true(found, "the brow's hurtbox is where the kneel puts it")
	# up again: whole height, dazed before he strikes
	await step_ticks(int(total * 0.5 * Sim.TICK_RATE) + 2)
	assert_false(t.is_down(), "he rises")
	assert_eq(rose.size(), 1, "titan_rose once")
	assert_true(_hb(t, "Brow").position.is_equal_approx(brow0), "his brow back where he stands")
	assert_true(t.brain.strike_ready_tick >= Sim.tick + int(float(t.topple.recover_s) * Sim.TICK_RATE) - 3,
		"dazed: his next strike waits recover_s")


func test_blows_on_a_kneeling_titan_land_harder_a_heavy_most() -> void:
	var n := await _load()
	var p: GiantPlayer = n.player
	var t: TitanEnemy = n.titan
	_blow(p, t, "torso", 400.0)
	await step_ticks(1)
	var standing := (hits_on(t.entity_id).back() as HitResult).health_damage
	_blow(p, t, "torso", 400.0, true)
	await step_ticks(1)
	var standing_heavy := (hits_on(t.entity_id).back() as HitResult).health_damage
	assert_true(t.knock_down("shin_l"), "down")
	await step_ticks(2)
	_blow(p, t, "torso", 400.0)
	await step_ticks(1)
	var down := (hits_on(t.entity_id).back() as HitResult).health_damage
	_blow(p, t, "torso", 400.0, true)
	await step_ticks(1)
	var down_heavy := (hits_on(t.entity_id).back() as HitResult).health_damage
	var k := float(t.topple.damage_mult)
	var kh := float(t.topple.heavy_mult)
	assert_near(float(down), float(standing) * k, 1.0, "every blow x%.2f while he is down" % k)
	assert_near(float(down_heavy), float(standing_heavy) * k * kh, 1.0, "a Heavy x%.2f besides" % kh)
	assert_true(down_heavy > down, "a Heavy is the decisive blow")


func test_another_break_keeps_him_down_and_the_broken_shin_drops_him_again() -> void:
	var n := await _load()
	var p: GiantPlayer = n.player
	var t: TitanEnemy = n.titan
	_blow(p, t, "shin_l", 5000.0, true)
	await step_ticks(2)
	assert_true(t.is_down(), "down")
	var until := t.down_since + t.down_ticks
	assert_true(t.break_plate("back"), "his back breaks while he is down")
	await step_ticks(1)
	assert_true(t.is_down() and t.controller.stagger_reason == TitanEnemy.TOPPLE_REASON, "he stays down (no reel)")
	assert_eq(t.down_since + t.down_ticks, until, "the same down")
	await step_ticks(until - Sim.tick + 2)
	assert_false(t.is_down(), "up")
	# within again_immune_s of his rise the broken shin's damage does not drop him
	var again := float(t.plates().plate("shin_l").again_damage)
	assert_true(again > 0.0, "the shin drops him again after enough damage")
	_blow(p, t, "shin_l", again * 3.0)
	await step_ticks(1)
	assert_false(t.is_down(), "not within again_immune_s")
	t.controller.call("_end_stagger")
	await step_ticks(int(float(t.topple.again_immune_s) * Sim.TICK_RATE) + 2)
	_blow(p, t, "shin_l", again * 3.0)
	await step_ticks(1)
	assert_true(t.is_down(), "after it, the broken shin's damage drops him again")
	assert_eq(t.topples, 2, "two downs")
	assert_eq(toppled.size(), 2, "announced twice")


func test_a_new_attempt_stands_him_up_whole() -> void:
	var n := await _load()
	var t: TitanEnemy = n.titan
	var brow0 := _hb(t, "Brow").position
	assert_true(t.knock_down("shin_r"), "down")
	await step_ticks(60)
	t.p34_reset_attempt()
	await step_ticks(1)
	assert_false(t.is_down(), "a new attempt: standing")
	assert_true(_hb(t, "Brow").position.is_equal_approx(brow0), "his hurtboxes where he stands")
	assert_eq(t.topples, 0, "no down counted")
	t.p34_stop_return()


func test_the_rig_kneels_with_a_blow_on_the_ground_and_rises() -> void:
	var n := await _load(true)
	var t: TitanEnemy = n.titan
	var rig := t.get_node("Visual") as TitanRig
	assert_true(rig.has_model(), "his model is drawn (PersonRig.enable_for_tests)")
	assert_true(t.knock_down("shin_l"), "down")
	for i in 50:
		await get_tree().process_frame
	assert_eq(rig.current_clip(), "kneel", "the kneel clip")
	assert_eq(rig.knee_impacts, 1, "the knee strikes the ground once (dust, a shake)")
	await step_ticks(t.down_ticks - (Sim.tick - t.down_since) - 20)
	await get_tree().process_frame
	assert_eq(rig.current_clip(), "rise", "the rise at the end of the down")
