extends IntegrationSuite
## P16: regression tests for the follow-ups docs/plans/FOLLOWUPS.md gives the UX pass (the M2 and
## M3 gate reviews). A Runic Bolt locked beyond its reach shows "Out of range" on the hotbar and is
## refused with nothing spent; a Crushing Grip whose hand closes on nothing gets its stamina and
## cooldown back; the growth clearance counts actors and the growth combat gate counts aware
## enemies near the shrine; a schema-valid but invalid main save never replaces the backup; a new
## game started from the command line keeps a newer build's save; a reload from the pause menu or
## F9 while dead gets the death floor; quitting to the title forgets the level a Continue loaded.
## (The boss bar and the quest tracker: test_hud_layout.)

const FLOW := "res://scenes/test/flow_test_level.tscn"
const SHRINE := "res://scenes/world/shrine.tscn"
const BOLT_ID := "ability.runic_bolt"
const GRIP_ID := "ability.crushing_grip"

var rejected: Array[Array] = []    ## [actor, action, reason]
var messages: Array[String] = []
var grabs := 0
var level: Node3D


func before_each() -> void:
	await super()
	rejected.clear()
	messages.clear()
	grabs = 0
	level = null
	Events.action_rejected.connect(_on_rejected)
	Events.hud_message.connect(_on_message)
	Events.grab_started.connect(_on_grab_started)


func after_each() -> void:
	for sig: Signal in [Events.action_rejected, Events.hud_message, Events.grab_started]:
		for c: Dictionary in sig.get_connections():
			if (c.callable as Callable).get_object() == self:
				sig.disconnect(c.callable)
	await _unload_level()
	await super()


func _on_rejected(_t: int, actor: String, action_id: String, reason: String) -> void:
	rejected.append([actor, action_id, reason])


func _on_message(text: String, _kind: String) -> void:
	messages.append(text)


func _on_grab_started(_t: int, _holder: String, _target: String) -> void:
	grabs += 1


# --------------------------------------------------------------------------- helpers

func _grounded_player(pos := Vector3(0, 0.05, 0), yaw := 0.0) -> GiantPlayer:
	var p := spawn_player(pos, yaw)
	await TestWait.until(self, func() -> bool: return p.is_on_floor(), 40)
	await step_ticks(1)
	return p


func _hud() -> Hud:
	var layer := CanvasLayer.new()
	world.add_child(layer)
	var hud := Hud.new()
	layer.add_child(hud)
	return hud


func _messages_with(part: String) -> int:
	var n := 0
	for m in messages:
		if m.contains(part):
			n += 1
	return n


func _shrine(pos: Vector3, world_id: String, shrine_id: String) -> Shrine:
	var s: Shrine = (load(SHRINE) as PackedScene).instantiate()
	s.world_id = world_id
	s.shrine_id = shrine_id
	s.position = pos
	world.add_child(s)
	return s


## The flow test level, loaded as main.gd does after a (re)load; its Player.
func _load_flow_level() -> GiantPlayer:
	level = (load(FLOW) as PackedScene).instantiate() as Node3D
	world.add_child(level)
	var p := level.get_node("Player") as GiantPlayer
	p.router.use_injection = true
	GameSession.on_level_ready(level, p)
	return p


func _unload_level() -> void:
	if level != null and is_instance_valid(level):
		level.queue_free()
		await get_tree().process_frame
		await get_tree().process_frame
	level = null


## A save document that loads (SaveSlots.validate passes).
func _doc(respawn: String) -> Dictionary:
	return {"schema_version": SaveSlots.SCHEMA_VERSION, "build_version": "test", "saved_at_unix": 0,
		"slot": SaveSlots.SLOT, "level": "level.valley", "checkpoint": {"respawn": respawn, "reason": "test"},
		"character": CharacterState.new_game(GameData.get_record("progression.default"),
			GameData.get_record("player.giant")),
		"world": WorldState.to_save_dict(), "stats": {"deaths": 0, "checkpoint_loads": 0, "play_time_s": 0.0}}


static func _write_raw(path: String, data: Dictionary) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify(data, "\t"))
	f.close()


static func _respawn_in(path: String) -> String:
	var r := JsonIO.read_file(path)
	if not r.ok or typeof(r.data) != TYPE_DICTIONARY:
		return "<unreadable>"
	return str(((r.data as Dictionary).get("checkpoint", {}) as Dictionary).get("respawn", ""))


# --------------------------------------------------------------------------- M2: Runic Bolt range

## FOLLOWUPS (M2 gate): a bolt locked onto a target beyond its 25 m fizzled while the hotbar showed
## it ready. Now the hotbar says "Out of range" (the same precheck as the request), the cast is
## refused with that reason and spends nothing, and within reach it casts as before.
func test_runic_bolt_locked_beyond_its_reach_is_out_of_range_and_spends_nothing() -> void:
	var p := await _grounded_player()
	var hud := _hud()
	var d := spawn_dummy(Vector3(0, 0, -30), "test.far_dummy")
	await step_ticks(2)
	p.camera_rig.yaw = 0.0
	p.router.inject_edge(&"lock_press")
	await step_ticks(2)
	assert_eq(p.lock.target_id, "test.far_dummy", "the stage-1 giant locks a dummy 30 m away (lock range 35 m)")
	assert_eq(str(p.controller.loadout.slot_6), BOLT_ID, "slot 6 holds Runic Bolt")
	var bolt := action(BOLT_ID)
	assert_eq(p.attack.range_reason(bolt), "out_of_range", "beyond the bolt's 25 m")
	hud.refresh()
	assert_eq(hud.slot_state(5).reason_code, "out_of_range", "the hotbar previews the range check")
	assert_eq(hud.slot_state(5).reason, "Out of range", "and says so")
	assert_eq(hud.slot_state(5).target, "» Practice Dummy", "still naming the locked target")
	var pools := p.entity.combatant.pools
	var essence := pools.essence
	p.router.inject_edge(&"slot_6")
	await step_ticks(1)
	assert_true(p.controller.action_id() != BOLT_ID, "the cast is refused")
	assert_near(pools.essence, essence, 1e-6, "no essence spent")
	assert_true(p.controller.cooldowns.is_ready(BOLT_ID, Sim.tick), "no cooldown started")
	assert_true(rejected.has(["player", BOLT_ID, "out_of_range"]), "rejected out_of_range: %s" % [rejected])
	assert_true(hud.message_texts().has("Runic Bolt: the target is out of range (25 m)"),
		"the HUD says why: %s" % [hud.message_texts()])
	d.global_position = Vector3(0, 0, -20)
	await step_ticks(2)
	hud.refresh()
	assert_eq(hud.slot_state(5).reason, "", "20 m away the bolt is ready again")
	p.router.inject_edge(&"slot_6")
	await step_ticks(1)
	assert_eq(p.controller.action_id(), BOLT_ID, "and casts")
	assert_near(pools.essence, essence - bolt.essence_cost, 1e-6, "for its 15 essence")
	await TestWait.until(self, func() -> bool: return p.controller.action == null, 60)
	p.targeting.release_lock("manual")
	p.controller.cooldowns.clear()
	d.global_position = Vector3(0, 0, -30)
	await step_ticks(1)
	assert_eq(p.attack.range_reason(bolt), "", "unlocked, a bolt flies at the crosshair: never out of range")
	hud.refresh()
	assert_eq(hud.slot_state(5).reason, "", "the hotbar agrees")


# --------------------------------------------------------------------------- M3: Crushing Grip

## FOLLOWUPS (M3 gate): a Crushing Grip on a staggered soldier spends 20 stamina and starts its
## 10 s cooldown on accept; when the soldier is out of reach as the hand closes (the attachment
## recheck fails), both come back (spec §15: invalid grabs spend nothing).
func test_a_crushing_grip_that_closes_on_nothing_gives_back_its_stamina_and_cooldown() -> void:
	var p := await _grounded_player()
	var s := spawn_soldier(Vector3(0, 0.05, -3.0), PI, "test.slippery")
	await step_ticks(2)
	s.entity.stagger(3.0, "test")
	await step_ticks(1)
	var pools := p.entity.combatant.pools
	var stamina := pools.stamina
	assert_eq(str(p.controller.loadout.slot_4), GRIP_ID, "slot 4 holds Crushing Grip")
	assert_eq(p.grab.try_slot("slot_4"), CombatController.Verdict.ACCEPT, "a staggered soldier in reach: accepted")
	assert_near(pools.stamina, stamina - 20.0, 1e-6, "20 stamina paid on accept")
	assert_false(p.controller.cooldowns.is_ready(GRIP_ID, Sim.tick), "the cooldown started")
	s.global_position = Vector3(0, 0.05, -16.0)   # gone from the reach during the windup
	var closed: bool = await TestWait.until(self, func() -> bool:
		return p.controller.action == null or p.controller.phase() == ActionDef.Phase.RECOVERY, 60)
	assert_true(closed, "the hand closed")
	assert_false(p.grab.is_holding(), "on nothing")
	assert_eq(grabs, 0, "no grab started")
	assert_near(pools.stamina, stamina, 1e-6, "the 20 stamina came back")
	assert_true(p.controller.cooldowns.is_ready(GRIP_ID, Sim.tick), "and the cooldown is over")
	assert_near(p.controller.cooldowns.remaining_fraction(GRIP_ID, Sim.tick), 0.0, 1e-6, "the hotbar shows no cooldown")
	assert_eq(_messages_with("Nothing in reach"), 1, "the giant is told why: %s" % [messages])


# --------------------------------------------------------------------------- M3: growth

## FOLLOWUPS (M3 gate): the clearance check ignored the actors layer, so a giant could grow into a
## dummy or a soldier. Now an actor inside the new capsule refuses the growth (named in the
## message), and the refusal changes nothing.
func test_growth_clearance_counts_actors_and_a_refusal_changes_nothing() -> void:
	var p := await _grounded_player()
	var prof2: Dictionary = p.growth.profile_for_stage(2)
	assert_true(bool(p.growth.check_clearance(prof2).ok), "open floor: room to grow")
	var dummy := spawn_dummy(Vector3(0, 0, -1.4), "test.close_dummy")
	await step_ticks(2)
	var r: Dictionary = p.growth.check_clearance(prof2)
	assert_false(bool(r.ok), "a dummy 1.4 m away is inside the stage-2 capsule (radius 1.2 m)")
	assert_eq(str(r.reason), "clearance", "reason clearance")
	assert_eq(str(r.message), "Practice Dummy is in the way. Step into the open to grow.", "the blocker is named")
	var radius := (p.body_shape.shape as CapsuleShape3D).radius
	var health_max := p.entity.combatant.pools.health_max
	var d: Dictionary = p.growth.debug_set_stage(2)
	assert_false(bool(d.ok), "the growth is refused")
	assert_eq(p.growth_stage, 1, "still stage 1")
	assert_near((p.body_shape.shape as CapsuleShape3D).radius, radius, 1e-6, "the capsule is unchanged")
	assert_near(p.entity.combatant.pools.health_max, health_max, 1e-6, "and so are the maxima")
	dummy.queue_free()
	var s := spawn_soldier(Vector3(1.4, 0.05, 0.0), 0.0, "test.close_soldier")
	await step_ticks(2)
	assert_false(bool(p.growth.check_clearance(prof2).ok), "a soldier at the giant's side blocks it too")
	s.global_position = Vector3(9.0, 0.05, 0.0)
	await step_ticks(2)
	assert_true(bool(p.growth.debug_set_stage(2).ok), "once it stands clear, the giant grows")
	assert_eq(p.growth_stage, 2, "stage 2")


## FOLLOWUPS (M3 gate): the combat gate counted only hits of the last 10 s, so an aware enemy
## closing in did not block growth although the refusal says "Enemies are near". Now a living
## enemy aware of the giant within the shrine's activation radius (14 m) blocks it; the Grow tab
## shows the same.
func test_an_aware_enemy_near_the_shrine_blocks_growth() -> void:
	var grove := _shrine(Vector3(0, 0, -12), "test.grove", "shrine.grove")
	var p := await _grounded_player()
	assert_true(bool(grove.can_grow(p, 2).ok), "a quiet grove: the giant may grow")
	var s := spawn_soldier(Vector3(8, 0.05, -12), 0.0, "test.watcher")
	await step_ticks(2)
	assert_true(bool(grove.can_grow(p, 2).ok), "an unaware soldier 8 m from the shrine does not block")
	s.brain.aware = true
	var r: Dictionary = grove.can_grow(p, 2)
	assert_eq(str(r.reason), "combat", "an aware one does")
	assert_eq(str(r.message), "Enemies are near. You cannot grow while fighting.", "with the combat message")
	assert_eq(p.growth.aware_enemies_near(grove), PackedStringArray(["test.watcher"]), "naming it")
	var combat_met := true
	for row: Dictionary in load("res://ui/screens/shrine/grow_tab.gd").rows_for(grove, p):
		if str(row.id) == "combat":
			combat_met = bool(row.met)
	assert_false(combat_met, "the Grow tab's Out of combat row is unmet")
	var g: Dictionary = grove.grow(p, 2)
	assert_false(bool(g.ok), "grow() refuses")
	assert_eq(p.growth_stage, 1, "and changes nothing")
	s.global_position = Vector3(25, 0.05, -12)
	await step_ticks(2)
	assert_true(bool(grove.can_grow(p, 2).ok), "an aware soldier 25 m from the shrine does not block")
	s.global_position = Vector3(8, 0.05, -12)
	queue_hit("tester", "test.watcher", Vector3(8, 0, -10), 5000.0)
	await step_ticks(2)
	assert_false(s.entity.is_alive(), "the soldier died")
	s.brain.aware = true
	assert_true(bool(grove.can_grow(p, 2).ok), "a dead one never blocks")
	assert_true(bool(grove.grow(p, 2).ok), "the giant grows")


# --------------------------------------------------------------------------- M3: saves

## FOLLOWUPS (M3 gate): a main save with a valid envelope but invalid content was copied over the
## only good backup by the next checkpoint. Now only a main file that fully loads becomes the
## backup.
func test_an_invalid_main_save_never_replaces_the_backup() -> void:
	var path := SaveSlots.path()
	assert_true(bool(SaveSlots.write(_doc("valley.cp.a")).ok), "save a")
	assert_true(bool(SaveSlots.write(_doc("valley.cp.b")).ok), "save b (a becomes the backup)")
	assert_eq(_respawn_in(path + ".bak"), "valley.cp.a", "the backup is a")
	var broken := _doc("valley.cp.broken")
	broken["character"] = "not an object"
	_write_raw(path, broken)
	assert_false(SaveSlots.validate(broken).is_empty(), "the main file now has a valid envelope but cannot load")
	var r := SaveSlots.read()
	assert_eq(str(r.source), "backup", "a read recovers the backup")
	assert_true(bool(SaveSlots.write(_doc("valley.cp.c")).ok), "the next checkpoint writes c")
	assert_eq(_respawn_in(path + ".bak"), "valley.cp.a", "the broken main did not replace the good backup")
	assert_eq(_respawn_in(path), "valley.cp.c", "the main file is c")
	assert_true(bool(SaveSlots.write(_doc("valley.cp.d")).ok), "save d")
	assert_eq(_respawn_in(path + ".bak"), "valley.cp.c", "a main file that loads still becomes the backup")


## FOLLOWUPS (M3 gate): --mode=valley --new-game overwrote a newer build's save without keeping the
## rejected copy that the title screen's read keeps. Now every write keeps it.
func test_a_new_game_from_the_command_line_keeps_a_newer_builds_save() -> void:
	var path := SaveSlots.path()
	var newer := _doc("valley.cp.future")
	newer["schema_version"] = SaveSlots.SCHEMA_VERSION + 1
	_write_raw(path, newer)
	GameSession.apply_args(GameSession.parse_args(PackedStringArray(["--mode=valley", "--new-game",
		"--level=" + FLOW, "--save-dir=" + path.get_base_dir()])))
	assert_true(GameSession.is_valley() and GameSession.pending_restore, "a new game is pending")
	assert_true(GameSession.persist, "--save-dir keeps saving on")
	_load_flow_level()
	assert_eq(GameSession.checkpoints_taken, 1, "the new game took its first checkpoint")
	var kept := SaveSlots.rejected_path(SaveSlots.SCHEMA_VERSION + 1)
	assert_true(FileAccess.file_exists(kept), "the newer save was kept as %s" % kept.get_file())
	var k := JsonIO.read_file(kept)
	assert_eq(int((k.data as Dictionary).get("schema_version", 0)) if k.ok else 0, SaveSlots.SCHEMA_VERSION + 1,
		"with its own schema version")
	assert_eq(_respawn_in(kept), "valley.cp.future", "and its content")
	var main := JsonIO.read_file(path)
	assert_eq(int((main.data as Dictionary).get("schema_version", 0)) if main.ok else 0, SaveSlots.SCHEMA_VERSION,
		"the main file is the new game's checkpoint")


# --------------------------------------------------------------------------- M3: session

## FOLLOWUPS (M3 gate): loading the checkpoint from the pause menu (or F9) while dead skipped the
## death floor. Now a reload asked for while the player is dead gets it (60 % health, full
## stamina), whatever asked.
func test_a_menu_or_f9_reload_while_dead_gets_the_death_floor() -> void:
	for reason: String in ["menu", "debug"]:
		GameSession.level_override = FLOW
		GameSession.start_new_valley()
		var p := _load_flow_level()
		await step_ticks(2)
		var pools := p.entity.combatant.pools
		pools.health = pools.health_max * 0.15
		pools.stamina = pools.stamina_max * 0.2
		Events.checkpoint_reached.emit(Sim.tick, "test.cp_b", "waystone")
		await step_ticks(2)
		assert_near(float(GameSession.checkpoint_doc.character.resources.health), pools.health_max * 0.15, 1.0,
			"%s: the checkpoint holds 15 %% health" % reason)
		queue_hit("tester", "player", p.global_position + Vector3(0, 0, -2), 50000.0)
		await step_ticks(2)
		assert_eq(p.controller.state, CombatController.State.DEAD, "%s: the player died" % reason)
		Events.reload_checkpoint_requested.emit(reason)
		assert_eq(GameSession.scene_reloads.back(), reason, "%s: the reload was asked for" % reason)
		await _unload_level()
		p = _load_flow_level()
		pools = p.entity.combatant.pools
		assert_true(pools.health >= pools.health_max * 0.6 - 1e-3,
			"%s while dead: at least 60 %% health (%.0f / %.0f)" % [reason, pools.health, pools.health_max])
		assert_near(pools.stamina, pools.stamina_max, 1e-3, "%s while dead: full stamina" % reason)
		await _unload_level()


## FOLLOWUPS (M3 gate): quitting to the title kept the level_override a Continue had loaded from its
## save (a test level), so Sandbox and New Game then loaded that level. Now the title forgets it; a
## --level of the command line stays.
func test_quit_to_title_forgets_the_level_a_continue_loaded() -> void:
	GameSession.persist = true
	GameSession.level_override = FLOW
	GameSession.start_new_valley()
	_load_flow_level()
	await _unload_level()
	assert_true(SaveSlots.exists(), "the new game wrote the slot (its level: the flow test level)")
	GameSession.go_to_title()
	var r := GameSession.continue_valley()
	assert_true(bool(r.ok), "Continue: %s" % r.message)
	assert_eq(GameSession.level_override, FLOW, "Continue loads the save's own level")
	GameSession.go_to_title()
	assert_eq(GameSession.level_override, "", "quitting to the title forgets it")
	GameSession.start_sandbox()
	assert_eq(GameSession.level_scene_path(), GameSession.SANDBOX_SCENE, "Sandbox loads the M1 sandbox")
	GameSession.go_to_title()
	assert_true(bool(GameSession.change_mode("valley", {"new_game": true}).ok), "New Game starts")
	assert_eq(GameSession.level_scene_path(), GameSession.scene_for_level(GameSession.VALLEY_LEVEL_ID),
		"in the Valley, not the saved test level")
	GameSession.apply_args(GameSession.parse_args(PackedStringArray(["--level=" + FLOW])))
	GameSession.go_to_title()
	assert_eq(GameSession.level_override, FLOW, "a --level of the command line stays")
