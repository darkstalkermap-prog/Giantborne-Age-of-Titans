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
	assert_eq(titles, ["Rest", "Grow", "Loadout", "Attributes"], "Rest and Grow, and P12's Loadout and Attributes")
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
