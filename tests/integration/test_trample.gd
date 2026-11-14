extends IntegrationSuite
## Trample and heave (P26, plan M6-M9 §2.9, §5.5, decision 31): a giant of a prop's trample_stage
## or more walking into it sends one trample hit (melee, 9,999, through the hit queue) and
## Events.trampled - a stage-4 giant walks through a palisade a stage-3 one is stopped by; trampling
## a faction's house is an offence (FactionState), its fence is not; a stage-5 giant heaves a
## rockfall aside, a stage-4 one gets the locked message and size_gate_blocked.

const PALISADE := "res://scenes/world/palisade_trample.tscn"
const ROCKFALL := "res://scenes/world/rockfall.tscn"
const TOWN := "test_town"

var trampled: Array[Array] = []
var gate_events: Array[Array] = []
var warnings: Array[String] = []


func before_each() -> void:
	await super()
	FactionState.reset_for_tests()
	FactionState.hub()   # installed by the faction's people in a level (EnemyActor, Civilian)
	trampled.clear()
	gate_events.clear()
	warnings.clear()
	Events.trampled.connect(_on_trampled)
	Events.size_gate_blocked.connect(_on_gate)
	Events.hud_message.connect(_on_message)


func after_each() -> void:
	for pair: Array in [[Events.trampled, _on_trampled], [Events.size_gate_blocked, _on_gate],
			[Events.hud_message, _on_message]]:
		if (pair[0] as Signal).is_connected(pair[1]):
			(pair[0] as Signal).disconnect(pair[1])
	await super()


func _on_trampled(_tick: int, world_id: String, entity_id: String) -> void:
	trampled.append([world_id, entity_id])


func _on_gate(_tick: int, gate_id: String, min_stage: int, message: String) -> void:
	gate_events.append([gate_id, min_stage, message])


func _on_message(text: String, kind: String) -> void:
	if kind == "warn":
		warnings.append(text)


func _prop(path: String, pos: Vector3, id: String) -> BreakableProp:
	var bp := (load(path) as PackedScene).instantiate() as BreakableProp
	bp.world_id = id
	bp.position = pos
	world.add_child(bp)
	return bp


func _giant(pos: Vector3, stage: int) -> GiantPlayer:
	var p := spawn_player(pos)
	await TestWait.until(self, func() -> bool: return p.is_on_floor(), 30)
	if stage > 1:
		var r: Dictionary = p.growth.debug_set_stage(stage)
		assert_true(r.ok, "stage %d (%s)" % [stage, r.get("reason", "")])
	return p


func test_a_stage_4_giant_tramples_a_palisade_a_stage_3_one_does_not() -> void:
	var fence := _prop(PALISADE, Vector3(0, 0, -6), "test.palisade")   # stakes 10 x 3.5 x 0.6 m
	assert_eq([fence.trample_stage(), fence.can_trample(3), fence.can_trample(4)], [4, false, true], "trample_stage 4")
	var p := await _giant(Vector3(0, 0.05, -3.0), 3)
	p.camera_rig.yaw = 0.0
	p.router.set_injected_move(Vector2(0, 1))
	await step_ticks(30)
	p.router.set_injected_move(Vector2.ZERO)
	assert_false(fence.destroyed, "stage 3: the palisade stands")
	assert_true(p.global_position.z > -6.0, "and stops the giant (z %.2f)" % p.global_position.z)
	assert_eq(trampled.size(), 0, "nothing trampled")
	p.global_position = Vector3(0, 0.05, -2.5)
	p.velocity = Vector3.ZERO
	await step_ticks(1)
	assert_true((p.growth.debug_set_stage(4) as Dictionary).ok, "stage 4")
	p.router.set_injected_move(Vector2(0, 1))
	var through: bool = await TestWait.until(self, func() -> bool: return p.global_position.z < -7.5, 120)
	p.router.set_injected_move(Vector2.ZERO)
	assert_true(fence.destroyed, "stage 4: trampled")
	assert_eq(trampled, [["test.palisade", "player"]], "one Events.trampled, naming the prop and the giant")
	assert_true(destroyed.has("test.palisade"), "broken through the hit queue (object_destroyed)")
	var hit := hits_on("test.palisade")
	assert_true(hit.size() == 1 and hit[0].event.action_id == BreakableProp.TRAMPLE_ACTION
		and hit[0].event.tags.has("Melee"), "one trample hit, a melee one")
	assert_true(through, "and the giant walks on through (z %.2f)" % p.global_position.z)


func test_trampling_a_faction_house_is_an_offence_and_its_fence_is_not() -> void:
	var house := _prop(PALISADE, Vector3(-8, 0, -6), "test.town_house")
	house.set_meta(&"faction", TOWN)
	house.set_meta(&"prop_tags", PackedStringArray(["house"]))
	var fence := _prop(PALISADE, Vector3(8, 0, -6), "test.town_fence")
	fence.set_meta(&"faction", TOWN)
	fence.set_meta(&"prop_tags", PackedStringArray(["fence"]))
	var p := await _giant(Vector3(0, 0.05, 4), 4)
	assert_true(fence.trample(p), "the giant tramples the town's fence")
	await step_ticks(2)
	assert_true(fence.destroyed, "it breaks")
	assert_eq(FactionState.standing(TOWN), "neutral", "a fence is no offence")
	assert_false(fence.trample(p), "a broken prop is not trampled again")
	assert_true(house.trample(p), "the giant tramples a house of the town")
	await step_ticks(2)
	assert_true(house.destroyed, "it breaks")
	assert_eq(FactionState.standing(TOWN), "warned", "trampling a house is an offence")
	var hub := FactionState.hub()
	assert_true(hub.history.size() == 1 and str(hub.history[0].target) == "test.town_house", "one offence, the house")
	assert_eq(trampled, [["test.town_fence", "player"], ["test.town_house", "player"]], "both trampled")


func test_a_stage_5_giant_heaves_a_rockfall_and_a_stage_4_one_cannot() -> void:
	var rock := _prop(ROCKFALL, Vector3(0, 0, -12), "test.rockfall")
	var point := rock.get_node("HeavePoint") as HeavePoint
	assert_true(point != null and point.prop() == rock, "the HeavePoint heaves its parent")
	assert_eq(point.interact_id, "test.rockfall", "named by the prop's world id")
	var p := await _giant(Vector3(0, 0.05, -2), 4)
	assert_eq(point.prompt_text(p), "Heave the rockfall aside", "[E] Heave the rockfall aside")
	assert_true(point.can_interact(p), "usable while the rocks stand")
	point.interact(p)
	var text := "It will not move. Grow to stage 5."
	assert_eq([point.last_result.ok, point.last_result.reason, point.last_result.message], [false, "permission", text],
		"stage 4: refused with the prop's locked message")
	assert_eq(gate_events, [["test.rockfall", 5, text]], "size_gate_blocked names stage 5")
	assert_true(warnings.has(text), "and the HUD says it")
	await step_ticks(2)
	assert_false(rock.destroyed, "the rocks stand")
	assert_true((p.growth.debug_set_stage(5) as Dictionary).ok, "stage 5")
	point.interact(p)
	assert_true(point.last_result.ok, "stage 5: heaved")
	await step_ticks(2)
	assert_true(rock.destroyed and destroyed.has("test.rockfall"), "the rockfall is heaved aside")
	assert_false(rock.has_collision(), "its blocking rocks are gone")
	assert_true(rock.nav_links_enabled(), "and its navigation link opens")
	assert_false(point.can_interact(p), "nothing left to heave")
