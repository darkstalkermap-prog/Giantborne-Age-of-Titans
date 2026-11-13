extends IntegrationSuite
## Shrines (plan §3.5, §2.7.4): the scene's nodes and groups; the first activation per load
## (within the record's 14 m) is a free Rest plus checkpoint_reached and shrine_activated, once;
## Rest heals, clears debuffs, keeps cooldowns and fury, and emits shrine_rested; growth is
## gated by level, combat, busy, holding, flags and the shrine's max stage; E asks for the
## shrine screen, whose Rest and Grow tabs work; the sandbox has its shrine.

const SHRINE := "res://scenes/world/shrine.tscn"
const ARENA := "res://scenes/world/sandbox_arena.tscn"

var reached: Array[Array] = []
var activated: Array[String] = []
var rested: Array[String] = []
var requested: Array[Array] = []
var blocked: Array[Array] = []


func before_each() -> void:
	await super()
	reached.clear()
	activated.clear()
	rested.clear()
	requested.clear()
	blocked.clear()
	Events.checkpoint_reached.connect(_on_reached)
	Events.shrine_activated.connect(_on_activated)
	Events.shrine_rested.connect(_on_rested)
	Events.ui_screen_requested.connect(_on_requested)
	Events.growth_blocked.connect(_on_blocked)


func after_each() -> void:
	for sig: Signal in [Events.checkpoint_reached, Events.shrine_activated, Events.shrine_rested,
			Events.ui_screen_requested, Events.growth_blocked]:
		for c: Dictionary in sig.get_connections():
			if (c.callable as Callable).get_object() == self:
				sig.disconnect(c.callable)
	get_tree().paused = false
	await super()


func _on_reached(_t: int, id: String, kind: String) -> void:
	reached.append([id, kind])


func _on_activated(_t: int, id: String) -> void:
	activated.append(id)


func _on_rested(_t: int, id: String) -> void:
	rested.append(id)


func _on_requested(screen: String, args: Dictionary) -> void:
	requested.append([screen, args])


func _on_blocked(_t: int, _id: String, reason: String, _message: String) -> void:
	blocked.append([reason])


func _shrine(pos: Vector3, world_id := "test.shrine", shrine_id := "shrine.sandbox", yaw := 0.0) -> Shrine:
	var s: Shrine = (load(SHRINE) as PackedScene).instantiate()
	s.world_id = world_id
	s.shrine_id = shrine_id
	s.position = pos
	s.rotation.y = yaw
	world.add_child(s)
	return s


func _grounded_player(pos: Vector3, yaw := 0.0) -> GiantPlayer:
	var p := spawn_player(pos, yaw)
	await TestWait.until(self, func() -> bool: return p.is_on_floor(), 30)
	await step_ticks(1)
	return p


# --------------------------------------------------------------------------- scene

func test_shrine_scene_nodes_groups_and_record() -> void:
	var s := _shrine(Vector3(0, 0, -30), "test.shrine_a", "shrine.grove")
	await step_ticks(1)
	assert_true(s.is_in_group("shrines"), "group shrines")
	assert_true(s.is_in_group("interactables"), "and interactables")
	var spawn := s.get_node("SpawnPoint") as CheckpointMarker
	assert_true(spawn != null, "SpawnPoint is a CheckpointMarker")
	assert_eq(spawn.checkpoint_id, "test.shrine_a", "its checkpoint id is the shrine's world id")
	assert_true(spawn.is_in_group("checkpoints"), "in group checkpoints (GameSession finds respawns there)")
	assert_true(s.get_node("GrowthPad") is Marker3D, "GrowthPad marker")
	assert_eq(s.record().get("id"), "shrine.grove", "record()")
	assert_eq(s.display_name(), "Grove Shrine", "display name from the record")
	assert_near(s.activation_radius_m(), 14.0, 1e-6, "activation radius 14 m")
	assert_eq(s.interact_id, "test.shrine_a", "interact id = world id")
	var stone := s.get_node("Stone") as StaticBody3D
	assert_eq(stone.collision_layer, HitQueryAdapter.LAYER_WORLD, "the stone is solid world geometry")
	var pad := s.growth_pad_position()
	assert_true(Vector2(pad.x - s.global_position.x, pad.z - s.global_position.z).length() > 5.0,
		"the pad is clear of the stone")
	var t := spawn.spawn_transform()
	var fwd := -t.basis.z
	assert_true(fwd.dot((pad - s.global_position).normalized()) > 0.9, "the respawn faces away from the stone")
	assert_false((s.get_node("Visual/Glow") as Node3D).visible, "the rune is dark until activated")


func test_every_growth_pad_has_stage_3_clearance() -> void:
	# The shrine's own pad, a stage-3 giant, nothing else around: the stone must not block.
	var s := _shrine(Vector3(0, 0, -20))
	var p := await _grounded_player(s.growth_pad_position() + Vector3(0, 0.05, 0))
	var c: Dictionary = p.growth.check_clearance(p.growth.profile_for_stage(3))
	assert_true(c.ok, "a stage-3 giant fits on the pad (%s)" % c.get("blocker", ""))


# --------------------------------------------------------------------------- activation and rest

func test_first_activation_heals_and_emits_once_per_load() -> void:
	var s := _shrine(Vector3(0, 0, -30))
	var p := await _grounded_player(Vector3(0, 0.05, 0))
	var pools := p.entity.combatant.pools
	pools.health = 0.3 * pools.health_max
	pools.stamina = 10.0
	pools.essence = 5.0
	await step_ticks(5)
	assert_false(s.is_activated(), "30 m away: not yet")
	assert_eq(activated.size(), 0, "no events yet")
	p.global_position = Vector3(0, 0.05, -18)   # 12 m from the shrine
	await step_ticks(2)
	assert_true(s.is_activated(), "within 14 m it activates")
	assert_near(pools.health, pools.health_max, 1e-3, "the free Rest heals")
	assert_near(pools.stamina, pools.stamina_max, 1e-3, "and refills stamina")
	assert_near(pools.essence, pools.essence_max, 1e-3, "and essence")
	assert_eq(reached, [["test.shrine", "shrine"]], "checkpoint_reached(world id, shrine) once")
	assert_eq(activated, ["test.shrine"], "shrine_activated once")
	assert_eq(rested.size(), 0, "the free Rest is not a shrine_rested")
	assert_true((s.get_node("Visual/Glow") as Node3D).visible, "the rune lights up")
	p.global_position = Vector3(0, 0.05, 20)
	await step_ticks(3)
	p.global_position = Vector3(0, 0.05, -20)
	pools.health = 0.5 * pools.health_max
	await step_ticks(3)
	assert_eq(activated.size(), 1, "coming back does not activate it again")
	assert_near(pools.health, 0.5 * pools.health_max, 1e-3, "nor heal again")
	assert_false(s.activate(p), "activate() after the first time returns false")
	var other := _shrine(Vector3(10, 0, -20), "test.shrine_b")
	await step_ticks(2)
	assert_true(other.is_activated(), "another shrine activates on its own")
	assert_eq(activated, ["test.shrine", "test.shrine_b"], "with its own event")


func test_no_free_rest_without_first_activation_rest_and_no_checkpoint_when_off() -> void:
	TestFixtures.record_override("shrine.thornwick", {"first_activation_rest": false, "checkpoint": false,
		"rest_heals": false})
	var s := _shrine(Vector3(0, 0, -10), "test.quiet", "shrine.thornwick")
	var p := await _grounded_player(Vector3(0, 0.05, 0))
	var pools := p.entity.combatant.pools
	pools.health = 0.3 * pools.health_max
	await step_ticks(3)
	assert_true(s.is_activated(), "activated")
	assert_near(pools.health, 0.3 * pools.health_max, 1e-3, "no free Rest")
	assert_eq(reached.size(), 0, "no checkpoint_reached")
	assert_eq(activated, ["test.quiet"], "shrine_activated still fires")
	var r := s.rest(p)
	assert_true(r.ok, "resting is allowed")
	assert_near(pools.health, 0.3 * pools.health_max, 1e-3, "but rest_heals false restores nothing")
	assert_eq(rested, ["test.quiet"], "shrine_rested still fires (a checkpoint for GameSession)")


func test_rest_heals_clears_debuffs_and_keeps_cooldowns_and_fury() -> void:
	var s := _shrine(Vector3(0, 0, -6))
	var p := await _grounded_player(Vector3(0, 0.05, 0))
	await step_ticks(2)
	assert_true(s.is_activated(), "activated on arrival")
	p.router.inject_edge(&"slot_1")   # Heavy Footfall: an 8 s cooldown
	await step_ticks(40)
	var cd := p.controller.cooldowns.remaining_s("ability.heavy_footfall", Sim.tick)
	assert_true(cd > 5.0, "Footfall is cooling down (%.1f s)" % cd)
	var pools := p.entity.combatant.pools
	pools.health = 100.0
	pools.essence = 0.0
	pools.fury = 40.0
	p.entity.apply_status("status.slow")
	p.entity.apply_status("status.stone_skin")
	var r := s.rest(p)
	assert_true(r.ok, "rested")
	assert_near(pools.health, pools.health_max, 1e-3, "health restored")
	assert_near(pools.stamina, pools.stamina_max, 1e-3, "stamina restored")
	assert_near(pools.essence, pools.essence_max, 1e-3, "essence restored")
	assert_near(pools.fury, 40.0, 1e-6, "fury kept")
	assert_false(p.entity.combatant.statuses.has("status.slow"), "a slow (debuff) wears off")
	assert_true(p.entity.combatant.statuses.has("status.stone_skin"), "a buff is kept")
	assert_near(p.controller.cooldowns.remaining_s("ability.heavy_footfall", Sim.tick), cd, 0.05, "cooldowns keep running")
	assert_eq(rested, ["test.shrine"], "shrine_rested(world id)")
	assert_true(str(r.message).contains("restored"), "a message for the screen")


# --------------------------------------------------------------------------- growth gates

func test_growth_gates_level_combat_busy_holding_flags_and_max_stage() -> void:
	var grove := _shrine(Vector3(0, 0, -12), "test.grove", "shrine.grove")
	var kingsfall := _shrine(Vector3(30, 0, -12), "test.kingsfall", "shrine.kingsfall")
	var hollow := _shrine(Vector3(-30, 0, -12), "test.hollow", "shrine.hollow")
	var p := await _grounded_player(Vector3(0, 0.05, 0))
	var c := p.controller
	assert_eq(grove.can_grow(p, 2).ok, true, "the Grove grows a level-99 sandbox giant to stage 2")
	c.level = 2
	var r := grove.can_grow(p, 2)
	assert_eq(r.reason, "level", "level 2 < required level 3")
	assert_true(str(r.message).contains("level 3"), "names the level (%s)" % r.message)
	c.level = 3
	assert_true(grove.can_grow(p, 2).ok, "level 3 is enough")
	assert_eq(grove.can_grow(p, 3).reason, "shrine_max", "the Grove only grows to stage 2")
	assert_eq(hollow.can_grow(p, 2).reason, "shrine_max", "the Hollow shrine grows nobody")
	assert_eq(grove.can_grow(p, 1).reason, "already", "already stage 1")
	# P26: stages 4-6 have profiles now (the Grove still grows to stage 2 only); none has stage 7.
	assert_eq(grove.can_grow(p, 4).reason, "shrine_max", "the Grove does not grow to stage 4")
	assert_eq(grove.can_grow(p, 7).reason, "no_profile", "no stage-7 profile")
	c.level = 99
	var k := kingsfall.can_grow(p, 2)
	assert_eq(k.reason, "flags", "Kingsfall waits for the Ogre King's defeat")
	assert_eq(k.message, "The Ogre King still rules Kingsfall. The shrine will not answer while he lives.",
		"with the record's message")
	WorldState.set_flag("world.ogre_king.defeated", true)
	assert_true(kingsfall.can_grow(p, 2).ok, "the flag opens it")
	p.entity.combatant.pools.mark_combat()
	assert_eq(grove.can_grow(p, 2).reason, "combat", "not while fighting")
	assert_eq(grove.can_grow(p, 2).message, "Enemies are near. You cannot grow while fighting.", "combat message")
	p.entity.combatant.pools.since_combat = 999.0
	c.holding_id = "test.held"
	assert_eq(grove.can_grow(p, 2).reason, "holding", "not while holding something")
	c.holding_id = ""
	p.router.inject_light_attack()
	await step_ticks(2)
	assert_eq(grove.can_grow(p, 2).reason, "busy", "not mid-swing")
	var refused := grove.grow(p, 2)
	assert_false(refused.ok, "grow() refuses too")
	assert_eq(p.growth_stage, 1, "and changes nothing")
	assert_eq(blocked.back(), ["busy"], "growth_blocked busy")
	await TestWait.until(self, func() -> bool: return c.state == CombatController.State.LOCOMOTION, 90)
	assert_true(grove.grow(p, 2).ok, "once idle again, the Grove grows the giant")
	assert_eq(p.growth_stage, 2, "stage 2")
	assert_eq(p.growth.check_growth(3, null).reason, "shrine_max", "growth needs a shrine")


# --------------------------------------------------------------------------- interaction and screen

func test_interact_asks_for_the_shrine_screen() -> void:
	var s := _shrine(Vector3(0, 0, -3))
	var p := await _grounded_player(Vector3(0, 0.05, 0))
	await step_ticks(8)
	assert_eq(p.interact.current_prompt(), "Rest at the Sandbox Shrine", "the prompt names the shrine")
	p.router.inject_edge(&"interact")
	await step_ticks(1)
	assert_eq(requested.size(), 1, "one screen request")
	if requested.size() == 1:
		assert_eq(requested[0][0], "shrine", "for the shrine screen")
		assert_eq((requested[0][1] as Dictionary).get("shrine"), s, "with the shrine")
		assert_eq((requested[0][1] as Dictionary).get("world_id"), "test.shrine", "and its world id")


func test_shrine_screen_rest_and_grow_tabs() -> void:
	var s := _shrine(Vector3(0, 0, -6))
	var p := await _grounded_player(Vector3(0, 0.05, 0))
	await step_ticks(2)
	var layer := CanvasLayer.new()
	world.add_child(layer)
	var stack := ScreenStack.new()
	layer.add_child(stack)
	await get_tree().process_frame
	var screen := stack.open("shrine", {"shrine": s}) as ShrineScreen
	assert_true(screen != null, "SCREENS[shrine] opens the shrine screen")
	if screen == null:
		return
	assert_true(get_tree().paused, "it pauses the game")
	var titles: Array = []
	for t in screen.tabs:
		titles.append(t.tab_title())
	assert_eq(titles, ["Rest", "Grow", "Loadout", "Attributes", "Talents"],
		"Rest and Grow, P12's Loadout and Attributes, and P33's Talents (Ancestry waits for the Old Kingdom)")
	var pools := p.entity.combatant.pools
	pools.health = 0.4 * pools.health_max
	screen.show_tab(0)
	var rest_tab := screen.tab("Rest")
	var rest_out: Dictionary = rest_tab.call("press_rest")
	assert_true(rest_out.ok, "Rest")
	assert_near(pools.health, pools.health_max, 1e-3, "healed")
	assert_eq(rested, ["test.shrine"], "shrine_rested")
	screen.show_tab(1)
	var grow_tab := screen.tab("Grow")
	assert_true(str(grow_tab.call("title_text")).begins_with("Grow to stage 2"), "the Grow tab offers stage 2")
	var rows: Array = grow_tab.get("requirements")
	var ids: Array = []
	for row: Dictionary in rows:
		ids.append(row.id)
		assert_true(row.met, "%s is met (%s)" % [row.id, row.text])
	assert_eq(ids, ["shrine_max", "level", "combat", "busy", "clearance"], "every requirement is listed")
	assert_false((grow_tab.get("grow_button") as Button).disabled, "Grow is enabled")
	var out: Dictionary = grow_tab.call("press_grow")
	assert_true(out.ok, "Grow grows the giant while the game is paused")
	assert_eq(p.growth_stage, 2, "stage 2")
	assert_true(str(grow_tab.call("result_text")).contains("Height 3.7 m -> 5.5 m"), "the tab lists what changed")
	assert_true(str(grow_tab.call("title_text")).begins_with("Grow to stage 3"), "and now offers stage 3")
	stack.close_all()
	assert_false(get_tree().paused, "closing it unpauses")
	await step_ticks(2)
	assert_eq(p.growth_stage, 2, "still stage 2 afterwards")


func test_grow_tab_shows_unmet_requirements_and_disables_grow() -> void:
	var s := _shrine(Vector3(0, 0, -6), "test.kings", "shrine.kingsfall")
	var p := await _grounded_player(Vector3(0, 0.05, 0))
	p.controller.level = 1
	await step_ticks(2)
	var layer := CanvasLayer.new()
	world.add_child(layer)
	var stack := ScreenStack.new()
	layer.add_child(stack)
	await get_tree().process_frame
	var screen := stack.open("shrine", {"shrine": s}) as ShrineScreen
	screen.show_tab(1)
	var grow_tab := screen.tab("Grow")
	var unmet: Array = []
	for row: Dictionary in grow_tab.get("requirements"):
		if not row.met:
			unmet.append(row.id)
	assert_eq(unmet, ["flags", "level"], "the boss flag and the level are missing")
	assert_true((grow_tab.get("grow_button") as Button).disabled, "Grow is disabled")
	stack.close_all()


## M8 gate fix-up 1 (F4): a giant using a shrine (standing within its reach) whose own spot has no room
## for the next stage grows on the shrine's growth pad: the growth steps it onto the pad, facing the
## stone, and the Grow tab counts the pad's room. Beyond the shrine's reach, or with no room on the pad
## either, the growth is refused for clearance as before and the giant stays where it stood.
func test_a_giant_without_room_within_the_shrines_reach_grows_on_its_pad() -> void:
	var s := _shrine(Vector3(0, 0, -6))
	var pad := s.growth_pad_position()
	# Low roofs: stage 1 (3.66 m) fits under them, stage 2 (5.49 m) does not.
	add_box(Vector3(3, 1, 3), Vector3(0, 4.5, -2))   # 4 m from the stone: within its reach
	add_box(Vector3(3, 1, 3), Vector3(0, 4.5, 3))   # 9 m from it: beyond
	var p := await _grounded_player(Vector3(0, 0.05, 3))
	var prof: Dictionary = p.growth.profile_for_stage(2)
	assert_eq(str(p.growth.check_clearance(prof).reason), "clearance", "no room for stage 2 under the far roof")
	var far := s.can_grow(p, 2)
	assert_eq(str(far.reason), "clearance", "beyond the shrine's reach the growth is refused (%s)" % far.message)
	var at := p.global_position
	assert_false(bool(s.grow(p, 2).ok), "grow() refuses too")
	assert_eq(blocked.back(), ["clearance"], "growth_blocked clearance")
	assert_true(p.growth_stage == 1 and p.global_position.distance_to(at) < 0.01, "nothing changes, nothing moves")
	# Within the shrine's reach under the near roof: the pad has room.
	p.global_position = Vector3(0, 0.05, -2)
	await step_ticks(3)
	assert_eq(str(p.growth.check_clearance(prof).reason), "clearance", "no room for stage 2 under the near roof")
	var near := s.can_grow(p, 2)
	assert_true(near.ok, "within the shrine's reach its pad has room (%s)" % near.get("message", ""))
	var step: Vector3 = near.get("step_to", Vector3.INF)
	assert_true(step.is_finite() and Vector2(step.x - pad.x, step.z - pad.z).length() < 0.01,
		"the growth steps onto the pad (%s, pad %s)" % [step, pad])
	var rows: Array = load("res://ui/screens/shrine/grow_tab.gd").rows_for(s, p)
	var room: Array = rows.filter(func(row: Dictionary) -> bool: return row.id == "clearance")
	assert_true(room.size() == 1 and bool(room[0].met), "the Grow tab counts the pad's room (%s)" % [room])
	assert_true(bool(s.grow(p, 2).ok), "the giant grows")
	assert_eq(p.growth_stage, 2, "to stage 2")
	assert_true(Vector2(p.global_position.x - pad.x, p.global_position.z - pad.z).length() < 0.05,
		"on the pad (%s, pad %s)" % [p.global_position, pad])
	var to_stone := s.global_position - p.global_position
	assert_near(angle_difference(p.facing_yaw, atan2(-to_stone.x, -to_stone.z)), 0.0, 0.01, "facing the stone")
	assert_true(p.velocity.is_zero_approx(), "at rest")
	await step_ticks(10)
	assert_true(bool(p.growth.check_clearance(prof).ok), "with room around it")
	assert_true(Vector2(p.global_position.x - pad.x, p.global_position.z - pad.z).length() < 0.2, "and it stays there")
	# Stage 3 beside the stone under a roof (stage 2 fits under it, stage 3's 7.92 m does not): the pad has
	# room, then a roof on the pad too leaves no way out and the growth is refused.
	add_box(Vector3(3, 1, 3), Vector3(3, 6.5, -6))
	p.global_position = Vector3(3, 0.05, -6)
	await step_ticks(3)
	assert_true(bool(s.can_grow(p, 3).ok), "stage 3 on the pad while it has room")
	add_box(Vector3(4, 1, 4), Vector3(pad.x, 6.5, pad.z))
	await step_ticks(1)
	var both := s.can_grow(p, 3)
	assert_eq(str(both.reason), "clearance", "no room here and none on the pad: refused (%s)" % both.message)
	assert_false(bool(s.grow(p, 3).ok), "grow() refuses")
	assert_true(p.growth_stage == 2 and Vector2(p.global_position.x - 3, p.global_position.z + 6).length() < 0.2,
		"and the giant stays where it stood")
	# A pad with no floor under it (past the floor's edge at z -60) is no way out either.
	var edge := _shrine(Vector3(20, 0, -55), "test.edge")
	add_box(Vector3(3, 1, 3), Vector3(20, 6.5, -51))
	p.global_position = Vector3(20, 0.05, -51)
	await step_ticks(3)
	assert_true(edge.growth_pad_position().z < -60.0, "the edge shrine's pad hangs past the floor")
	assert_eq(str(edge.can_grow(p, 3).reason), "clearance", "no floor on the pad: refused")


# --------------------------------------------------------------------------- sandbox

func test_the_sandbox_has_a_shrine_that_grows_to_stage_3() -> void:
	var arena: Node3D = (load(ARENA) as PackedScene).instantiate()
	TestSpawn.disable_all_ai(arena)
	world.add_child(arena)
	await step_ticks(3)
	var shrines := get_tree().get_nodes_in_group("shrines")
	assert_eq(shrines.size(), 1, "one shrine in the sandbox")
	var s := shrines[0] as Shrine
	assert_eq(s.world_id, "sandbox.shrine", "world id")
	assert_eq(s.shrine_id, "shrine.sandbox", "record")
	assert_true(s.global_position.is_equal_approx(Vector3(-40, 0, 40)), "at (-40, 0, 40)")
	var rec := s.record()
	assert_true(bool(rec.allows_growth) and int(rec.max_stage) == 3, "grows to stage 3")
	assert_eq((rec.get("growth_requires_flags", []) as Array).size(), 0, "with no flags")
	var p := arena.get_node("Player") as GiantPlayer
	p.router.use_injection = true
	p.global_position = s.growth_pad_position() + Vector3(0, 0.05, 0)
	await TestWait.until(self, func() -> bool: return p.is_on_floor(), 30)
	await step_ticks(2)
	assert_true(s.is_activated(), "standing on the pad activated it")
	assert_true(s.grow(p, 2).ok, "stage 2 on the sandbox shrine's pad")
	assert_true(s.grow(p, 3).ok, "stage 3 too: the pad has stage-3 clearance")
	arena.queue_free()
	await step_ticks(2)


## P39f (FOLLOWUPS, "From the M8 screenshot pass": "the shrine's tab row does not show the open tab"): whichever
## way a tab opens - show_tab, a click on its button, pad RB - its button alone is marked open (UiKit.set_tab_open:
## a lit box with a gold underline and a gold title), the others plain with a muted title; the pause menu's page
## tabs the same.
func test_the_tab_row_shows_the_open_tab() -> void:
	var s := _shrine(Vector3(0, 0, -6))
	await _grounded_player(Vector3(0, 0.05, 0))
	var layer := CanvasLayer.new()
	world.add_child(layer)
	var stack := ScreenStack.new()
	layer.add_child(stack)
	await get_tree().process_frame
	var screen := stack.open("shrine", {"shrine": s}) as ShrineScreen
	var buttons := screen.tab_buttons()
	assert_true(buttons.size() >= 4, "the shrine's tabs (%d)" % buttons.size())
	var check := func(open: int, how: String) -> void:
		for i in buttons.size():
			var b := buttons[i]
			var is_open := i == open
			assert_eq(UiKit.is_tab_open(b), is_open, "%s: %s is %s" % [how, b.text, "open" if is_open else "closed"])
			assert_eq(b.get_theme_color("font_color"), UiKit.TAB_OPEN if is_open else UiKit.MUTED,
				"%s: %s's title colour" % [how, b.text])
			var sb := b.get_theme_stylebox("normal") as StyleBoxFlat
			assert_eq(sb != null and sb.border_width_bottom == UiKit.TAB_UNDERLINE_PX and sb.border_color == UiKit.TAB_OPEN,
				is_open, "%s: %s %s the gold underline" % [how, b.text, "has" if is_open else "has not"])
	check.call(0, "on opening")
	for i in buttons.size():
		screen.show_tab(i)
		check.call(i, "show_tab(%d)" % i)
	buttons[1].pressed.emit()
	check.call(1, "a click on %s" % buttons[1].text)
	var rb := InputEventJoypadButton.new()
	rb.button_index = JOY_BUTTON_RIGHT_SHOULDER
	rb.pressed = true
	screen._unhandled_input(rb)
	check.call(2, "pad RB")
	var sizes := buttons.map(func(b: Button) -> Vector2: return b.get_combined_minimum_size())
	screen.show_tab(0)
	assert_eq(buttons.map(func(b: Button) -> Vector2: return b.get_combined_minimum_size()), sizes,
		"an open tab is as big as a closed one: the row does not move")
	stack.close_all()
	var pause := stack.open("pause") as PauseMenu
	if pause != null:
		for page: String in ["Main", "Settings", "Controls"]:
			pause.show_page(page)
			for other: String in ["Main", "Settings", "Controls"]:
				assert_eq(UiKit.is_tab_open(pause.tab_button(other)), other == page,
					"the pause menu on %s: its %s tab is %s" % [page, other, "open" if other == page else "closed"])
	stack.close_all()


## P39f (FOLLOWUPS, "From the M8 screenshot pass": "the Kingsgate shrine's floating name is too small to read from
## where fast travel puts the giant"): the name above every shrine (the shrine scene's Visual/Name, filled from
## its record) keeps one size on screen - an em of at least 18 px at the default field of view on a 720 px screen,
## at least 14 px at the widest - where the shared sign was a 0.38 m text, about 6 px from a stage-3 camera behind
## a giant on the pad; it shows from the pad at every stage (a stage-6 camera stands within its range) and floats
## clear of the stone's cap. Now that it reads, it would read through a screen's see-through panel (the shrine
## window opens right in front of it): it hides while any screen is open, as the HUD does - a shrine made while
## one is open starts hidden - and shows again once the last one closes or its stack leaves the tree.
func test_the_shrine_name_reads_from_the_pad() -> void:
	# (the camera's farthest zoom at stage 6 is 32 m behind a 17 m pivot: 45 m from the name - within its 90 m)
	var s := _shrine(Vector3(0, 0, -6), "test.kingsgate", "shrine.world_kingsgate")
	await get_tree().process_frame
	var l := s.get_node("Visual/Name") as Label3D
	assert_eq(l.text, s.display_name(), "the name is the record's (%s)" % l.text)
	assert_true(l.fixed_size, "one size on screen at any distance")
	for pair: Array in [[75.0, 18.0], [100.0, 14.0]]:
		var em := float(l.font_size) * l.pixel_size / (2.0 * tan(deg_to_rad(float(pair[0])) * 0.5)) * 720.0
		assert_true(em >= float(pair[1]), "at %d degrees the name is %.1f px tall (at least %d)" % [int(pair[0]), em, int(pair[1])])
	var old_em := 64.0 * 0.006 / (2.0 * tan(deg_to_rad(37.5)) * 30.0) * 720.0
	assert_true(old_em < 8.0, "the old sign was %.1f px from 30 m" % old_em)
	var pad := s.growth_pad_position()
	for stage in range(1, 7):
		var prof := GameData.get_record("growth.%02d" % stage)
		assert_false(prof.is_empty(), "stage %d's growth profile" % stage)
		# the camera zoomed all the way out, behind a giant facing the stone
		var back := maxf(float(prof.get("camera_distance_m", 0.0)), float(prof.get("camera_zoom_max_m", 0.0)))
		var camera := pad + (pad - s.global_position).normalized() * back + Vector3.UP * float(prof.get("camera_pivot_height_m",
			prof.get("height_m", 4.0)))
		var d := camera.distance_to(l.global_position)
		assert_true(d <= l.visibility_range_end, "stage %d: the camera behind a giant on the pad is %.0f m from the name (shown to %.0f m)" % [stage, d, l.visibility_range_end])
	var cap_top := 0.0
	for n in s.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.mesh != null and mi.name != "Glow":
			cap_top = maxf(cap_top, (mi.global_transform * mi.get_aabb()).end.y)
	assert_true(l.global_position.y - cap_top >= 1.0, "the name floats %.1f m over the stone (top %.2f m)" % [l.global_position.y - cap_top, cap_top])
	var layer := CanvasLayer.new()
	world.add_child(layer)
	var stack := ScreenStack.new()
	layer.add_child(stack)
	await get_tree().process_frame
	var overlay := load("res://tests/support/test_overlay_screen.gd") as GDScript
	assert_true(l.visible, "the name shows while no screen is open")
	stack.push(overlay.new() as UiScreen)
	assert_false(l.visible, "the name hides while a screen is open")
	var s2 := _shrine(Vector3(40, 0, -6), "test.kingsgate_2", "shrine.world_kingsgate")
	var l2 := s2.get_node("Visual/Name") as Label3D
	assert_false(l2.visible, "a shrine made while a screen is open starts with its name hidden")
	stack.close_all()
	assert_true(l.visible and l2.visible, "the names show again once the screen closes")
	stack.push(overlay.new() as UiScreen)
	assert_false(l.visible or l2.visible, "hidden again under the next screen")
	layer.remove_child(stack)
	assert_true(l.visible and l2.visible, "a stack leaving the tree with its screen open shows the names again")
	stack.free()
