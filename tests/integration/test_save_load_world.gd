extends IntegrationSuite
## The M3/M4 save/load gate (plan §3.8, spec §15 "save/load restores character, loadout, quest
## flags and gate state; loot never twice"), through GameSession (P06) on the flow test level with a
## practice gate placed in it:
##   * crack the gate to 40 % health, grow to stage 2, equip the sword, slot an ability, set a flag,
##     take a checkpoint (written to the test slot), change things afterwards, reload the
##     checkpoint: the gate is cracked at exactly 40 % again (visual, collision, closed nav link,
##     no events), the giant is stage 2 with the sword, the loadout and the flag are back;
##   * break the gate after the reload: XP and loot once; reload again and Continue from disk: it
##     stays broken and nothing is awarded twice.
## GameSession.reset_for_tests() logs scene reloads instead of reloading the runner, so the test
## frees and instantiates the level itself, as main.gd does on a reload.

const FLOW := "res://scenes/test/flow_test_level.tscn"
const GATE_SCENE := "res://scenes/world/gate_practice.tscn"
const GATE_ID := "test.flow_gate"
const GATE_POS := Vector3(-12, 0, 8)
const FLAG := "test.p08.saved_flag"

var level: Node3D
var player: GiantPlayer
var gate: BreakableProp
var xp_requests: Array = []
var stage_events: Array = []


func before_each() -> void:
	await super()
	xp_requests.clear()
	stage_events.clear()
	Events.xp_award_requested.connect(_on_xp)
	Events.object_stage_changed.connect(_on_stage)


func after_each() -> void:
	for sig: Signal in [Events.xp_award_requested, Events.object_stage_changed]:
		for c: Dictionary in sig.get_connections():
			if (c.callable as Callable).get_object() == self:
				sig.disconnect(c.callable)
	if level != null and is_instance_valid(level):
		level.queue_free()
	level = null
	player = null
	gate = null
	await super()


func _on_xp(amount: int, source: String) -> void:
	xp_requests.append([amount, source])


func _on_stage(_tick: int, world_id: String, index: int, stage_id: String) -> void:
	stage_events.append([world_id, index, stage_id])


## The flow test level with a practice gate in it (as if the level scene held one), then
## GameSession.on_level_ready, as main.gd does after a (re)load.
func _load_level() -> void:
	level = (load(FLOW) as PackedScene).instantiate() as Node3D
	var g := (load(GATE_SCENE) as PackedScene).instantiate() as BreakableProp
	g.name = "Gate"
	g.world_id = GATE_ID
	g.position = GATE_POS
	level.add_child(g)
	world.add_child(level)
	player = level.get_node("Player") as GiantPlayer
	player.router.use_injection = true
	gate = level.get_node("Gate") as BreakableProp
	GameSession.on_level_ready(level, player)


func _unload_level() -> void:
	if level != null and is_instance_valid(level):
		level.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	level = null
	player = null
	gate = null


## A player hit on the gate dealing `damage` (armor 10: power x 1.15 x 100 / 110, rounded once).
func _hit_gate(damage: float) -> void:
	queue_hit("player", GATE_ID, gate.global_position + Vector3(0, 0, -3), damage / (1.15 * 100.0 / 110.0))
	await step_ticks(2)


func _check_cracked_at_40(what: String) -> void:
	assert_eq(gate.stage_index, 1, "%s: the gate is in its cracked stage" % what)
	assert_eq(gate.stage_id(), "cracked", what + ": stage id")
	assert_near(gate.health(), 96.0, 1e-4, "%s: at 40 %% health (96 of 240)" % what)
	assert_true((gate.get_node("Cracked") as Node3D).visible, what + ": the Cracked visual shows")
	assert_false((gate.get_node("Intact") as Node3D).visible, what + ": the Intact one is hidden")
	assert_true(gate.has_collision(), what + ": it still blocks")
	assert_false(gate.nav_links_enabled(), what + ": its nav link is still closed")
	assert_false(gate.destroyed, what + ": not broken")


func test_a_cracked_gate_growth_sword_loadout_and_flags_survive_save_and_load() -> void:
	GameSession.persist = true
	GameSession.level_override = FLOW
	GameSession.start_new_valley()
	_load_level()
	await step_ticks(2)
	await _hit_gate(144.0)
	_check_cracked_at_40("before the checkpoint")
	assert_eq(stage_events, [[GATE_ID, 1, "cracked"]], "object_stage_changed once, for the crack")
	var delta := WorldState.get_delta(GATE_ID)
	assert_eq(int(delta.damage_stage), 1, "the delta holds the stage")
	assert_near(float(delta.health), 96.0, 1e-4, "and the health")
	assert_true(player.growth.debug_set_stage(2).ok, "grown to stage 2")
	assert_true(player.equipment.grant_weapon("weapon.sword", true).ok, "the sword equipped")
	player.set_loadout_slot("slot_4", "ability.stone_skin")
	WorldState.set_flag(FLAG, "kept")
	await step_ticks(2)
	var taken: Dictionary = GameSession.take_checkpoint("test")
	assert_true(taken.ok and str(taken.message) == "", "the checkpoint was written (%s)" % taken)
	var doc := GameSession.checkpoint_doc
	assert_eq(int(doc.character.growth_stage), 2, "the save holds stage 2")
	assert_eq(str(doc.character.weapon), "weapon.sword", "the sword")
	assert_eq(doc.character.weapons_owned, ["weapon.club", "weapon.sword"], "the weapons owned")
	assert_near(float(doc.world.deltas[GATE_ID].health), 96.0, 1e-4, "and the cracked gate")
	# After the checkpoint: changes the reload must roll back.
	await _hit_gate(30.0)
	assert_true(gate.health() < 96.0, "the gate took more damage after the checkpoint")
	assert_true(player.equipment.grant_weapon("weapon.hammer", true).ok, "the maul equipped after it")
	player.set_loadout_slot("slot_4", "")
	WorldState.set_flag(FLAG, "changed")
	GameSession.reload_checkpoint("debug")
	assert_eq(GameSession.scene_reloads.back(), "debug", "a reload through GameSession")
	await _unload_level()
	stage_events.clear()
	_load_level()
	await step_ticks(2)
	_check_cracked_at_40("after the reload")
	assert_true(stage_events.is_empty(), "a restored gate emits no stage events")
	assert_eq(player.growth_stage, 2, "the giant is stage 2 again")
	assert_eq(player.equipment.weapon_id(), "weapon.sword", "holding the sword")
	assert_eq(player.controller.loadout.light, "ability.sword_light_1", "with its light chain")
	assert_near(player.weapon_length, 1.6 * 1.5, 1e-4, "at its stage-2 size")
	assert_eq(player.equipment.owned(), PackedStringArray(["weapon.club", "weapon.sword"]),
		"owning what it owned at the checkpoint (not the maul)")
	assert_eq(player.controller.loadout.slot_4, "ability.stone_skin", "the loadout is back")
	assert_eq(WorldState.get_flag(FLAG), "kept", "and the flag")
	# Break it after the reload: XP and loot once.
	xp_requests.clear()
	loot.clear()
	await _hit_gate(200.0)
	assert_true(gate.destroyed, "the gate breaks")
	assert_eq(stage_events, [[GATE_ID, 2, "broken"]], "into its broken stage")
	assert_eq(destroyed.count(GATE_ID), 1, "object_destroyed once")
	assert_eq(xp_requests, [[20, "prop:" + GATE_ID]], "its 20 XP once")
	assert_eq(loot, ["%s:item.wood_scrap" % GATE_ID] as Array[String], "its loot once")
	assert_eq(WorldState.count_of("item.wood_scrap"), 2, "two wood scraps")
	assert_true(bool(WorldState.get_flag("world.ruins.gate_broken", false)), "world.ruins.gate_broken is set")
	assert_false(gate.has_collision(), "it no longer blocks")
	assert_true(gate.nav_links_enabled(), "its nav link opened")
	await _hit_gate(50.0)
	assert_eq(xp_requests.size(), 1, "hitting the wreck gives nothing more")
	taken = GameSession.take_checkpoint("test")
	assert_true(taken.ok, "a checkpoint after the break")
	# Reload, then Continue from disk: still broken, nothing awarded twice.
	GameSession.reload_checkpoint("debug")
	await _unload_level()
	stage_events.clear()
	_load_level()
	await step_ticks(2)
	assert_true(gate.destroyed, "after the reload the gate is still broken")
	assert_true((gate.get_node("Broken") as Node3D).visible, "showing its broken visual")
	assert_false(gate.has_collision(), "without collision")
	assert_true(gate.nav_links_enabled(), "with its nav link open")
	assert_eq(destroyed.count(GATE_ID), 1, "no second object_destroyed")
	assert_eq(xp_requests.size(), 1, "no second XP")
	assert_eq(loot.size(), 1, "no second loot")
	assert_eq(WorldState.count_of("item.wood_scrap"), 2, "the inventory came back with the two scraps")
	await _unload_level()
	GameSession.go_to_title()
	assert_eq(WorldState.count_of("item.wood_scrap"), 0, "the title starts from a clean world")
	var r := GameSession.continue_valley()
	assert_true(r.ok, "Continue reads the save from disk (%s)" % r.message)
	_load_level()
	await step_ticks(2)
	assert_true(gate.destroyed, "Continue: the gate is broken")
	assert_eq(player.growth_stage, 2, "Continue: stage 2")
	assert_eq(player.equipment.weapon_id(), "weapon.sword", "Continue: the sword")
	assert_eq(player.controller.loadout.slot_4, "ability.stone_skin", "Continue: the loadout")
	assert_eq(WorldState.get_flag(FLAG), "kept", "Continue: the flag")
	assert_eq(WorldState.count_of("item.wood_scrap"), 2, "Continue: the inventory")
	assert_eq(xp_requests.size(), 1, "Continue awards nothing either")
	assert_eq(loot.size(), 1, "and no loot")


## A plain breakable (the M1 fence) now keeps partial damage too: its health comes back after a
## reload (the M1 limitation "fence partial damage is not persisted").
func test_partial_fence_damage_is_persisted() -> void:
	var f := spawn_fence(Vector3(0, 0, -6), "test.fence_partial")
	await step_ticks(2)
	queue_hit("tester", "test.fence_partial", Vector3(0, 0, -3), 30.0)
	await step_ticks(2)
	var hp := f.health()
	assert_true(hp < 80.0 and hp > 0.0, "the fence took damage (%.1f / 80)" % hp)
	assert_near(float(WorldState.get_delta("test.fence_partial").health), hp, 1e-4, "its health is in the delta")
	assert_eq(int(WorldState.get_delta("test.fence_partial").damage_stage), 0, "still intact (stage 0)")
	f.queue_free()
	await step_ticks(2)
	var again := spawn_fence(Vector3(4, 0, -6), "test.fence_partial")
	await step_ticks(2)
	assert_near(again.health(), hp, 1e-4, "a reloaded fence has the same health")
	assert_false(again.destroyed, "and is still standing")
	var saved := WorldState.to_save_dict()
	WorldState.clear()
	assert_true(WorldState.from_save_dict(JSON.parse_string(JSON.stringify(saved))), "through JSON")
	assert_near(float(WorldState.get_delta("test.fence_partial").health), hp, 1e-4, "the health survives JSON")
	assert_eq(typeof(WorldState.get_delta("test.fence_partial").damage_stage), TYPE_INT, "the stage comes back an int")
