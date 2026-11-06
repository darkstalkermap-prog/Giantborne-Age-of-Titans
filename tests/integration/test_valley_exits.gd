extends IntegrationSuite
## The Valley's exits and the Citadel (P26, plan M6-M9 §5.6), on the integration floor with the
## Valley's own records and layout entries: the Kings' Door is indestructible and shut until the crown
## is claimed (slice.completed), then open, and its LevelExit leaves for the world's Kingsgate
## shelf; the Citadel Gate refuses a stage-3 giant with its message and falls to a stage-4 one,
## setting world.citadel.breached; the hoard pays titan iron x2 and the Kings' Annals; the hall pays
## 150 XP once; the stair leaves for the world's Broken Stair; the end screen says "Prologue
## complete" and Continue points at the door.

const KINGS_DOOR := "res://scenes/world/kings_door.tscn"
const GATE := "res://scenes/world/gate_fortified.tscn"
const PICKUP := "res://scenes/world/item_pickup.tscn"
const DOOR_TEXT := "The door of the First King opens only for the one who wears his crown."

var travels: Array[Array] = []
var gate_events: Array[Array] = []
var messages: Array[Array] = []
var xp: Array[Array] = []


func before_each() -> void:
	await super()
	travels.clear()
	gate_events.clear()
	messages.clear()
	xp.clear()
	Events.travel_requested.connect(_on_travel)
	Events.size_gate_blocked.connect(_on_gate)
	Events.hud_message.connect(_on_message)
	Events.xp_award_requested.connect(_on_xp)


func after_each() -> void:
	for pair: Array in [[Events.travel_requested, _on_travel], [Events.size_gate_blocked, _on_gate],
			[Events.hud_message, _on_message], [Events.xp_award_requested, _on_xp]]:
		if (pair[0] as Signal).is_connected(pair[1]):
			(pair[0] as Signal).disconnect(pair[1])
	get_tree().paused = false
	await super()


func _on_travel(level_id: String, checkpoint_id: String, reason: String) -> void:
	travels.append([level_id, checkpoint_id, reason])


func _on_gate(_tick: int, gate_id: String, min_stage: int, message: String) -> void:
	gate_events.append([gate_id, min_stage, message])


func _on_message(text: String, kind: String) -> void:
	messages.append([text, kind])


func _on_xp(amount: int, source: String) -> void:
	xp.append([amount, source])


## The layout entry of `list` with this id (world_id or id).
static func _entry(list: String, id: String) -> Dictionary:
	for e: Dictionary in ValleyProbe.layout().get(list, []):
		if str(e.get("world_id", e.get("id", ""))) == id:
			return e
	return {}


## The LevelExit the Valley builder makes from the layout's exit `id`.
func _exit(id: String) -> LevelExit:
	var e := _entry("exits", id)
	var x := LevelExit.new()
	x.exit_id = id
	x.to_level = str(e.to_level)
	x.to_checkpoint = str(e.to_checkpoint)
	x.requires_flags = PackedStringArray(e.get("requires_flags", []))
	x.locked_message = str(e.get("locked_message", ""))
	world.add_child(x)
	return x


## A direct blow of a stage-`stage` giant (power 9,999) on `target_id` through the hit queue.
func _blow(target_id: String, stage: int) -> void:
	var e := HitEvent.new()
	e.tick = Sim.tick
	e.instance_id = Sim.new_instance_id()
	e.attacker_id = "player"
	e.target_id = target_id
	e.action_id = "ability.heavy_1"
	e.category = "melee"
	e.power = 9999.0
	e.attacker_stat = 10.0
	e.attacker_height_m = 10.97
	e.damage_split = {"physical": 1.0}
	e.tags = PackedStringArray(["Melee", "Heavy"])
	e.attacker_position = Vector3(0, 0, -4)
	e.attacker_growth_stage = stage
	Sim.queue_hit(e)


func _giant(stage: int) -> GiantPlayer:
	var p := spawn_player(Vector3(0, 0.05, 0))
	await TestWait.until(self, func() -> bool: return p.is_on_floor(), 30)
	if stage > 1:
		assert_true((p.growth.debug_set_stage(stage) as Dictionary).ok, "stage %d" % stage)
	return p


## One giant, grown along the way: the Citadel Gate holds against stage 3 and falls to stage 4; the
## Kings' Door holds against stage 6 until the crown is claimed, then its exit leads to the world.
func test_the_citadel_gate_and_the_kings_door() -> void:
	var gate := (load(GATE) as PackedScene).instantiate() as BreakableProp
	gate.world_id = "test.citadel_gate"
	gate.position = Vector3(-15, 0, -14)
	world.add_child(gate)
	var door := (load(KINGS_DOOR) as PackedScene).instantiate() as BreakableProp
	door.world_id = "test.kings_door"
	door.position = Vector3(15, 0, -14)
	world.add_child(door)
	var exit := _exit("valley.exit.kings_door")
	var p := await _giant(3)
	var text := "Fortified gates can be breached at stage 4."
	_blow("test.citadel_gate", p.growth_stage)
	await step_ticks(2)
	assert_false(gate.destroyed, "stage 3: the Citadel Gate holds")
	assert_true(messages.has([text, "warn"]), "with its message")
	assert_eq(gate_events, [["test.citadel_gate", 4, text]], "and size_gate_blocked names stage 4")
	assert_false(WorldState.get_flag("world.citadel.breached") == true, "not breached")
	assert_true((p.growth.debug_set_stage(4) as Dictionary).ok, "stage 4")
	_blow("test.citadel_gate", p.growth_stage)
	await step_ticks(2)
	assert_true(gate.destroyed, "stage 4: breached")
	assert_eq(WorldState.get_flag("world.citadel.breached"), true, "world.citadel.breached is set (the world side's door reads it)")
	assert_true((p.growth.debug_set_stage(6) as Dictionary).ok, "stage 6")
	assert_true(door.is_indestructible() and door.has_collision(), "the Kings' Door: indestructible, shut")
	assert_eq(door.open_flag(), "slice.completed", "opened by the crown's flag")
	_blow("test.kings_door", p.growth_stage)
	await step_ticks(2)
	assert_false(door.destroyed, "a stage-6 giant's blow does not break it")
	assert_true(messages.has([DOOR_TEXT, "warn"]), "it says whose door it is")
	assert_false(exit.can_interact(p), "the exit is shut before the crown")
	assert_eq(exit.blocked_reason(p), DOOR_TEXT, "with the same words")
	exit.interact(p)
	assert_eq(travels.size(), 0, "a shut exit asks for nothing")
	WorldState.set_flag("slice.completed", true)
	await step_ticks(1)
	assert_false(door.has_collision(), "the crown claimed: the door stands open")
	assert_true((door.get_node("Open") as Node3D).visible and not (door.get_node("Closed") as Node3D).visible,
		"its open leaves show")
	assert_true(exit.can_interact(p), "and the exit is open")
	exit.interact(p)
	assert_eq(travels, [["level.world", "world.cp.kingsgate_shelf", "exit"]], "to the world's Kingsgate shelf")
	var waystone := _entry("waystones", "valley.cp.kings_door")
	assert_eq(PackedStringArray(waystone.get("requires_flags", [])), PackedStringArray(["slice.completed"]),
		"the Kings' Door waystone opens with it")
	assert_eq(int(waystone.get("max_stage", 0)), 6, "and takes any giant up to stage 6")


## (No giant needed: a pickup, an area and an exit act for whoever uses them.)
func test_the_hoard_the_hall_and_the_stair() -> void:
	var p: GiantPlayer = null
	for id in ["valley.citadel.hoard_titan_iron", "valley.citadel.kings_annals"]:
		var e := _entry("props", id)
		var pick := (load(PICKUP) as PackedScene).instantiate() as ItemPickup
		pick.world_id = id
		for k: String in (e.get("set", {}) as Dictionary):
			pick.set(k, e.set[k])
		world.add_child(pick)
		pick.interact(p)
	assert_eq(WorldState.count_of("item.titan_iron"), 2, "the hoard: titan iron x2")
	assert_eq(WorldState.count_of("item.kings_annals"), 1, "and the Kings' Annals")
	assert_eq(WorldState.get_flag("world.citadel.hoard_taken"), true, "the hoard is taken")
	var hall := _entry("triggers", "valley.area.citadel_hall")
	var reward := RewardArea.new()
	reward.area_id = str(hall.id)
	reward.reward_xp = int(hall.reward_xp)
	reward.reward_flag = str(hall.reward_flag)
	reward.reward_message = str(hall.reward_message)
	world.add_child(reward)
	for i in 2:
		Events.area_entered.emit(Sim.tick, reward.area_id, "player")
	assert_eq(xp, [[150, "area:valley.area.citadel_hall"]], "150 XP the first time only")
	assert_true(messages.has(["The Hall of the Broken Kings: +150 XP", "good"]), "with its line")
	var stair := _exit("valley.exit.citadel_stair")
	assert_true(stair.can_interact(p), "the stair is always open")
	stair.interact(p)
	assert_eq(travels, [["level.world", "world.cp.broken_stair", "exit"]], "to the world's Broken Stair")


func test_the_end_screen_says_prologue_complete_and_continues() -> void:
	var layer := CanvasLayer.new()
	world.add_child(layer)
	var stack := ScreenStack.new()
	layer.add_child(stack)
	var screen := stack.open("end", {"time_s": 600.0, "deaths": 1, "level": 6, "stage": 3, "outcome": "help_ogre"}) as EndScreen
	assert_true(screen != null, "the end screen")
	if screen == null:
		return
	await get_tree().process_frame
	assert_eq([EndScreen.TITLE, EndScreen.SUBTITLE], ["Prologue complete", "The Valley of Broken Kings - prototype pacing"],
		"Prologue complete - the Valley of Broken Kings")
	assert_eq(screen.continue_button.text, "Continue", "Continue")
	assert_true(screen.first_focus() == screen.continue_button, "is the default")
	screen.press_continue()
	assert_false(stack.any_open(), "Continue closes it")
	assert_true(messages.has([EndScreen.CONTINUE_HINT, "info"]), "and points at the open door")
