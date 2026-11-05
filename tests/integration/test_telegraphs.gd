extends IntegrationSuite
## Decision 25's readability layer (plan §3.9): TelegraphVisuals' decals fill from 0 to 1 over
## the windup, flash while the strike is active and go when the actor leaves the windup / active
## phases (also when interrupted); an archer's aim line follows the live anchor until the aim
## lock and then freezes; the barrier's circle. The HUD's threat arrows: a telegraph aimed at the
## player from behind the camera shows an arrow at the screen edge, brightening with the windup,
## one in front does not, and casts on allies never do. And the M2-gate follow-up: status tints
## reach wolves (QuadrupedRig) as well as archers and mages (ActorRig).

const ARCHER := "res://scenes/enemies/archer.tscn"
const MAGE := "res://scenes/enemies/mage.tscn"
const WOLF := "res://scenes/enemies/wolf.tscn"


func _visuals() -> TelegraphVisuals:
	var tv := TelegraphVisuals.new()
	world.add_child(tv)
	return tv


func _hud() -> Hud:
	var layer := CanvasLayer.new()
	world.add_child(layer)
	var hud := Hud.new()
	layer.add_child(hud)
	return hud


func _arrows(hud: Hud) -> Node:
	return hud.get_node_or_null("ThreatArrows")


func after_each() -> void:
	for n in get_tree().get_nodes_in_group(ProjectileSystem.GROUP):
		n.queue_free()
	await super()


# --------------------------------------------------------------------------- decals

## A soldier's chop (0.85 s): the ground decal fills 0 -> 1 over the windup, flashes while active,
## and is gone after the strike.
func test_a_decal_fills_over_the_windup_and_flashes_while_active() -> void:
	var tv := _visuals()
	var p := spawn_player(Vector3(0, 0.05, 0), 0.0)
	var s := spawn_soldier(Vector3(0, 0.05, -3), PI)
	await step_ticks(2)
	s.brain.target_id = "player"
	s.controller.request(&"attack", {"action_id": "ability.soldier_chop"})
	var chop := action("ability.soldier_chop")
	var t := tv.telegraph_for("soldier_01")
	assert_false(t.is_empty(), "a decal for the chop")
	if t.is_empty():
		return
	assert_eq([t.action_id, t.shape, t.target_id], ["ability.soldier_chop", "line", "player"], "a line at the giant")
	assert_near(float(t.fill), 0.0, 1e-6, "empty as the windup begins")
	assert_false(bool(t.aim_line), "a melee line lies on the ground")
	assert_near((t.end as Vector3).distance_to(t.start as Vector3), 2.5, 1e-3, "2.5 m long")
	var fills: Array[float] = []
	for i in chop.windup_ticks - 1:
		await step_ticks(1)
		fills.append(float(tv.telegraph_for("soldier_01").get("fill", -1.0)))
	var rising := true
	for i in range(1, fills.size()):
		rising = rising and fills[i] > fills[i - 1]
	assert_true(rising, "it fills steadily")
	assert_near(fills[chop.windup_ticks / 2 - 1], float(chop.windup_ticks / 2) / chop.windup_ticks, 1e-6,
		"half full halfway through the windup")
	assert_near(fills.back(), float(chop.windup_ticks - 1) / chop.windup_ticks, 1e-6, "nearly full at its end")
	await get_tree().process_frame
	assert_true(bool(tv.telegraph_for("soldier_01").visible), "and drawn")
	await step_ticks(1)
	t = tv.telegraph_for("soldier_01")
	assert_near(float(t.fill), 1.0, 1e-6, "full when the strike is active")
	assert_true(bool(t.striking), "flashing during the active phase")
	await step_ticks(chop.active_ticks)
	assert_true(tv.telegraph_for("soldier_01").is_empty(), "gone once the strike is over")
	await get_tree().process_frame
	assert_eq(tv.active_count(), 0, "no decal left")
	assert_true(p != null, "player present")


## An interrupted windup (a stagger) removes its decal at once.
func test_an_interrupted_windup_removes_its_decal() -> void:
	var tv := _visuals()
	spawn_player(Vector3(0, 0.05, 0), 0.0)
	var w := TestSpawn.enemy(world, WOLF, Vector3(0, 0.05, -5), "test.wolf_t", false, PI)
	await step_ticks(2)
	w.brain.target_id = "player"
	w.controller.request(&"attack", {"action_id": "ability.wolf_lunge"})
	await step_ticks(10)
	assert_false(tv.telegraph_for("test.wolf_t").is_empty(), "the lunge is telegraphed")
	w.entity.stagger(1.0, "test")
	assert_true(tv.telegraph_for("test.wolf_t").is_empty(), "the stagger ended it")
	await get_tree().process_frame
	assert_eq(tv.active_count(), 0, "and its decal is gone")


## The archer's aim line runs from the bow to current_aim_point(): it follows the giant until the
## aim lock, then freezes on the stored point (decision 24).
func test_the_aim_line_follows_until_the_lock_then_freezes() -> void:
	var tv := _visuals()
	var p := spawn_player(Vector3(0, 0.05, 0), 0.0)
	p.entity.combatant.unkillable = true
	var a := TestSpawn.enemy(world, ARCHER, Vector3(0, 0.05, -15), "test.archer_t", false, PI) as ArcherEnemy
	await step_ticks(2)
	a.brain.target_id = "player"
	a.controller.request(&"attack", {"action_id": "ability.archer_shot"})
	var t := tv.telegraph_for("test.archer_t")
	assert_true(bool(t.get("aim_line", false)), "an aim line")
	assert_true((t.start as Vector3).is_equal_approx(a.launch_point_global(action("ability.archer_shot"))), "from the bow")
	assert_true((t.end as Vector3).is_equal_approx(p.entity.anchor_position()), "to the giant")
	p.global_position.x += 2.0
	await step_ticks(1)
	assert_true((tv.telegraph_for("test.archer_t").end as Vector3).is_equal_approx(p.entity.anchor_position()),
		"it follows the giant before the lock")
	await TestWait.until(self, func() -> bool: return a.aim_locked(), 60)
	var frozen: Vector3 = tv.telegraph_for("test.archer_t").end
	p.global_position.x += 4.0
	await step_ticks(5)
	t = tv.telegraph_for("test.archer_t")
	assert_eq(t.end, frozen, "after the lock it stays on the stored point")
	assert_false((t.end as Vector3).is_equal_approx(p.entity.anchor_position()), "while the giant moved away")
	await get_tree().process_frame
	assert_true(bool(tv.telegraph_for("test.archer_t").visible), "drawn")


## The barrier's circle at the mage's feet, radius 1.6 m, for the 1.2 s windup.
func test_the_barrier_shows_a_circle() -> void:
	var tv := _visuals()
	spawn_player(Vector3(0, 0.05, 0), 0.0)
	var m := TestSpawn.enemy(world, MAGE, Vector3(0, 0.05, -12), "test.mage_t", false, PI) as MageEnemy
	await step_ticks(2)
	m.brain.target_id = "player"
	m.controller.request(&"attack", {"action_id": "ability.mage_barrier"})
	var t := tv.telegraph_for("test.mage_t")
	assert_eq(str(t.get("shape", "")), "circle", "a circle")
	assert_near((t.end as Vector3).distance_to(t.start as Vector3), 1.6, 1e-3, "1.6 m round")
	await step_ticks(36)
	assert_near(float(tv.telegraph_for("test.mage_t").fill), 0.5, 1e-6, "half full halfway through its 72 ticks")


# --------------------------------------------------------------------------- threat arrows

## A telegraph at the player from behind the camera shows an edge arrow that brightens with the
## windup and goes with it; one in front does not; a cast on an ally never does.
func test_threat_arrows_show_only_off_screen_threats() -> void:
	var p := spawn_player(Vector3(0, 0.05, 0), 0.0)   # faces -Z; its camera looks along -Z
	p.entity.combatant.unkillable = true
	var hud := _hud()
	var behind := TestSpawn.enemy(world, ARCHER, Vector3(2, 0.05, 14), "test.archer_behind", false, 0.0) as ArcherEnemy
	var ahead := TestSpawn.enemy(world, ARCHER, Vector3(0, 0.05, -16), "test.archer_ahead", false, PI) as ArcherEnemy
	await step_ticks(3)
	await get_tree().process_frame
	var w := _arrows(hud)
	assert_true(w != null and w.has_method("arrows"), "the threat-arrow widget is on the HUD")
	if w == null:
		return
	var cam := p.camera_rig.camera
	assert_true(cam.is_position_behind(behind.attack_origin_global()), "one archer is behind the camera")
	assert_false(cam.is_position_behind(ahead.attack_origin_global()), "the other in front")
	ahead.brain.target_id = "player"
	ahead.controller.request(&"attack", {"action_id": "ability.archer_shot"})
	await step_ticks(2)
	assert_eq(w.call("visible_count"), 0, "a threat in view gets no arrow")
	behind.brain.target_id = "player"
	behind.controller.request(&"attack", {"action_id": "ability.archer_shot"})
	await step_ticks(1)
	var arrows: Array = w.call("arrows")
	assert_eq(arrows.size(), 1, "the archer behind gets an arrow")
	if arrows.size() == 1:
		var a: Dictionary = arrows[0]
		assert_eq(a.actor_id, "test.archer_behind", "for that archer")
		var view := hud.get_viewport_rect().size
		var pos: Vector2 = a.position
		var inset := minf(minf(pos.x, view.x - pos.x), minf(pos.y, view.y - pos.y))
		assert_near(inset, 24.0, 0.5, "its tip 24 px inside the screen edge")
		assert_true((a.direction as Vector2).y > 0.5, "pointing down: behind the camera")
		assert_true((a.direction as Vector2).x > 0.0, "and to the right, where it stands")
		var early := float(a.alpha)
		await step_ticks(40)
		var later: Array = w.call("arrows")
		assert_true(later.size() == 1 and float(later[0].alpha) > early + 0.3, "brightening as the windup completes")
	await TestWait.until(self, func() -> bool: return behind.controller.action == null, 120)
	assert_eq(w.call("visible_count"), 0, "gone with the telegraph")
	var m := TestSpawn.enemy(world, MAGE, Vector3(-3, 0.05, 12), "test.mage_behind", false, 0.0) as MageEnemy
	await step_ticks(2)
	m.brain.target_id = "player"
	m.controller.request(&"attack", {"action_id": "ability.mage_barrier"})
	await step_ticks(2)
	assert_eq(w.call("visible_count"), 0, "a barrier (a cast on an ally) threatens nobody")
	await TestWait.until(self, func() -> bool: return m.controller.action == null, 120)
	m.controller.request(&"attack", {"action_id": "ability.mage_slow_bolt"})
	await step_ticks(2)
	assert_eq(w.call("visible_count"), 1, "its slow bolt does")


func test_edge_geometry() -> void:
	var view := Vector2(1280, 720)
	var script: GDScript = load("res://ui/hud/threat_arrows.gd")
	var right: Vector2 = script.call("edge_point", view, Vector2(1, 0), 24.0)
	assert_eq(right, Vector2(1256, 360), "straight right: 24 px inside the right edge")
	var down: Vector2 = script.call("edge_point", view, Vector2(0, 1), 24.0)
	assert_eq(down, Vector2(640, 696), "straight down: 24 px above the bottom")
	var diag: Vector2 = script.call("edge_point", view, Vector2(1, 1).normalized(), 24.0)
	assert_near(diag.y, 696.0, 1e-3, "a diagonal meets the nearer (bottom) edge")


# --------------------------------------------------------------------------- status tints (M2 gate follow-up)

## Wolves never showed status tints: QuadrupedRig was not an ActorRig and HitFeedback tinted only
## those. Now HitFeedback tints any rig with set_status_tint() - the wolf's QuadrupedRig, and the
## ActorRig of archers and mages (the barrier has its own tint).
func test_status_tints_reach_wolves_archers_and_mages() -> void:
	var fb := HitFeedback.new()
	world.add_child(fb)
	var w := TestSpawn.enemy(world, WOLF, Vector3(4, 0.05, -6), "test.wolf_tint", false) as WolfEnemy
	var m := TestSpawn.enemy(world, MAGE, Vector3(-4, 0.05, -6), "test.mage_tint", false) as MageEnemy
	await step_ticks(2)
	assert_eq(HitFeedback.tint_target(w), w.quad, "a wolf's tint goes to its QuadrupedRig")
	assert_eq(HitFeedback.tint_target(m), m.rig, "a mage's to its ActorRig")
	assert_near(w.quad.status_tint().a, 0.0, 1e-9, "no tint at first")
	w.entity.apply_status("status.slow", NAN, 0.5)
	var slow_tint: Color = HitFeedback.STATUS_TINTS.filter(func(e: Array) -> bool: return e[0] == "status.slow")[0][1]
	assert_eq(w.quad.status_tint(), slow_tint, "a slowed wolf shows the slow tint")
	await get_tree().process_frame
	var mats: Array = w.quad.get("_materials")
	var bases: Array = w.quad.get("_base_colors")
	assert_true(mats.size() > 0 and not (mats[0] as StandardMaterial3D).albedo_color.is_equal_approx(bases[0]),
		"its materials take the colour")
	await step_ticks(32)
	assert_false(w.entity.combatant.statuses.has("status.slow"), "the slow expired")
	assert_near(w.quad.status_tint().a, 0.0, 1e-9, "and the tint went with it")
	await get_tree().process_frame
	await get_tree().process_frame
	assert_true((mats[0] as StandardMaterial3D).albedo_color.is_equal_approx(bases[0]), "back to its own colours")
	m.entity.apply_status("status.barrier")
	var ward_tint: Color = HitFeedback.STATUS_TINTS.filter(func(e: Array) -> bool: return e[0] == "status.barrier")[0][1]
	assert_eq(m.rig.status_tint(), ward_tint, "a warded mage shows the barrier tint")
	m.entity.apply_status("status.slow")
	assert_eq(m.rig.status_tint(), ward_tint, "the ward outranks a slow")
