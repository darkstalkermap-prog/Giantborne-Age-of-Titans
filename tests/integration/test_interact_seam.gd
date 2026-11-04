extends IntegrationSuite
## The interact seam (plan §2.7.4): PlayerInteract picks the best Interactable (lowest priority
## value, then nearest; in reach of the capsule edge and in front, or very close), offers
## component candidates too, posts blocked_reason as a warning, and does nothing without a
## candidate. CheckpointMarker, the HUD widget registry and the "[E] Talk" prompt widget.


class Probe:
	extends Interactable
	var uses := 0
	var blocked := ""

	func can_interact(_player: GiantPlayer) -> bool:
		return blocked == ""

	func blocked_reason(_player: GiantPlayer) -> String:
		return blocked

	func interact(_player: GiantPlayer) -> void:
		uses += 1


class OwnInit:
	extends Interactable
	var built := false

	func _init() -> void:   # no super(): the group join must not depend on it
		built = true


class OwnInitMarker:
	extends CheckpointMarker

	func _init() -> void:
		checkpoint_id = "test.cp.own_init"


class OwnInitWidget:
	extends HudWidget

	func _init() -> void:
		pass


class Offer:
	extends PlayerComponent
	var offered := {}
	var used := 0

	func interact_candidate() -> Dictionary:
		return offered

	func use() -> void:
		used += 1


var messages: Array[String] = []


func before_each() -> void:
	await super()
	messages.clear()
	Events.hud_message.connect(_on_message)


func after_each() -> void:
	Events.hud_message.disconnect(_on_message)
	await super()


func _on_message(text: String, kind: String) -> void:
	messages.append("%s:%s" % [kind, text])


func _probe(pos: Vector3, id: String, prompt := "Use", priority := 50, radius := 3.5) -> Probe:
	var it := Probe.new()
	it.interact_id = id
	it.prompt = prompt
	it.priority = priority
	it.radius_m = radius
	it.position = pos
	world.add_child(it)
	return it


func _press(p: GiantPlayer) -> void:
	p.router.inject_edge(&"interact")
	await step_ticks(1)


func test_nearest_then_priority_wins() -> void:
	var p := spawn_player(Vector3(0, 0.05, 0), 0.0)
	var near := _probe(Vector3(0.5, 0, -2.0), "test.near", "Near")
	var far := _probe(Vector3(-0.5, 0, -3.5), "test.far", "Far")
	await step_ticks(8)
	assert_true(near.is_in_group("interactables"), "Interactables join their group")
	assert_eq(p.interact.current_prompt(), "Near", "same priority: the nearest one")
	await _press(p)
	assert_eq([near.uses, far.uses], [1, 0], "E uses the nearest")
	far.priority = 10
	await _press(p)
	assert_eq([near.uses, far.uses], [1, 1], "a lower priority value beats distance")
	assert_eq(p.interact.current_prompt(), "Far", "the prompt follows the best candidate")
	far.enabled = false
	await _press(p)
	assert_eq([near.uses, far.uses], [2, 1], "disabled interactables are ignored")


func test_reach_and_front_rules() -> void:
	var p := spawn_player(Vector3(0, 0.05, 0), 0.0)
	var behind := _probe(Vector3(0, 0, 3.0), "test.behind", "Behind")
	var out_of_reach := _probe(Vector3(0, 0, -4.6), "test.far_away", "Too far")
	await step_ticks(8)
	assert_eq(p.interact.current_prompt(), "", "behind the player and beyond radius + capsule: none")
	await _press(p)
	assert_eq(behind.uses + out_of_reach.uses, 0, "nothing used")
	behind.position = Vector3(0.3, 0, 1.2)
	out_of_reach.position = Vector3(0, 0, -4.2)   # 3.5 m radius + 0.85 m capsule = 4.35 m reach
	await step_ticks(7)
	assert_true(p.interact.current_prompt() in ["Behind", "Too far"], "both are candidates now")
	await _press(p)
	assert_eq(behind.uses, 1, "closer than 1.5 m counts even behind the player, and the nearest wins")


func test_blocked_reason_posts_a_warning() -> void:
	var p := spawn_player(Vector3(0, 0.05, 0), 0.0)
	var heavy := _probe(Vector3(0, 0, -2.0), "test.heavy", "Lift")
	heavy.blocked = "Too heavy to lift at this size"
	await step_ticks(8)
	await _press(p)
	assert_eq(heavy.uses, 0, "a blocked interactable is not used")
	assert_true(messages.has("warn:Too heavy to lift at this size"), "its reason is shown as a warning")
	heavy.blocked = ""
	await _press(p)
	assert_eq(heavy.uses, 1, "used once it allows it")


func test_no_candidate_does_nothing() -> void:
	var p := spawn_player(Vector3(0, 0.05, 0), 0.0)
	await step_ticks(8)
	var stamina := p.entity.combatant.pools.stamina
	await _press(p)
	assert_eq(messages, [] as Array[String], "no message (the M1 'nothing to grab' stub is gone)")
	assert_eq(p.controller.state, CombatController.State.LOCOMOTION, "no action")
	assert_near(p.entity.combatant.pools.stamina, stamina, 1e-9, "nothing spent")
	assert_eq(p.interact.current_candidate(), {}, "no candidate")


func test_component_candidates_compete() -> void:
	var p := spawn_player(Vector3(0, 0.05, 0), 0.0)
	var probe := _probe(Vector3(0, 0, -2.0), "test.probe", "Use")
	var offer := Offer.new()
	p.add_component(&"offer", offer)
	offer.offered = {"priority": 10, "prompt": "Grab", "distance": 2.5, "call": offer.use, "id": "test.grab"}
	await step_ticks(8)
	assert_eq(p.interact.current_prompt(), "Grab", "a component candidate with a lower priority value wins")
	await _press(p)
	assert_eq([offer.used, probe.uses], [1, 0], "its Callable is used")
	offer.offered = {}
	await _press(p)
	assert_eq([offer.used, probe.uses], [1, 1], "without the offer the interactable is used")


func test_interacted_event_when_declared() -> void:
	var p := spawn_player(Vector3(0, 0.05, 0), 0.0)
	_probe(Vector3(0, 0, -2.0), "test.talker", "Talk")
	await step_ticks(8)
	if not Events.has_signal(&"interacted"):
		await _press(p)   # P01 not merged yet: nothing to listen to, and no error
		assert_true(true, "Events.interacted is not declared on this branch; the emit is skipped")
		return
	var got: Array = []
	var cb := func(tick: int, actor_id: String, interact_id: String) -> void:
		got.append([actor_id, interact_id])
	Events.connect(&"interacted", cb)
	await _press(p)
	Events.disconnect(&"interacted", cb)
	assert_eq(got, [["player", "test.talker"]], "interacted(tick, actor, interact_id) once")


func test_checkpoint_marker() -> void:
	var m := CheckpointMarker.new()
	m.checkpoint_id = "test.cp.one"
	m.position = Vector3(3, 1, -4)
	m.rotation = Vector3(0.3, PI / 2.0, 0.0)   # pitched: the spawn keeps only the yaw
	world.add_child(m)
	await step_ticks(1)
	assert_true(m.is_in_group("checkpoints"), "CheckpointMarkers join the checkpoints group")
	var t := m.spawn_transform()
	assert_true(t.origin.is_equal_approx(Vector3(3, 1, -4)), "spawn at the marker")
	var fwd := -t.basis.z
	assert_true(fwd.is_equal_approx(Vector3(-1, 0, 0)), "facing the marker's yaw, level (%s)" % fwd)
	var own := OwnInitMarker.new()
	world.add_child(own)
	assert_true(own.is_in_group("checkpoints") and own.checkpoint_id == "test.cp.own_init",
		"a subclass with its own _init still joins the group")


func test_subclasses_with_their_own_init_still_join() -> void:
	var p := spawn_player(Vector3(0, 0.05, 0), 0.0)
	var it := OwnInit.new()
	it.prompt = "Own"
	it.position = Vector3(0, 0, -2.0)
	world.add_child(it)
	await step_ticks(8)
	assert_true(it.built and it.is_in_group("interactables"), "own _init ran and the group was joined")
	assert_eq(p.interact.current_prompt(), "Own", "and PlayerInteract finds it")


func test_hud_widgets_and_the_interact_prompt() -> void:
	var layer := CanvasLayer.new()
	world.add_child(layer)
	var hud := Hud.new()
	layer.add_child(hud)
	var p := spawn_player(Vector3(0, 0.05, 0), 0.0)
	await step_ticks(3)
	var prompt := hud.get_node_or_null("InteractPrompt")
	assert_true(prompt is HudWidget, "Hud created the interact prompt widget from the registry")
	var made := HudWidgets.create_all(hud, ["res://ui/hud/no_such_widget.gd", "res://ui/hud/interact_prompt.gd"])
	assert_eq(made.size(), 1, "missing widget files are skipped without errors")
	made[0].queue_free()
	var created := 0
	for path: String in HudWidgets.WIDGETS:
		if ResourceLoader.exists(path):
			created += 1
	var widgets := 0
	for child in hud.get_children():
		if child is HudWidget:
			widgets += 1
	assert_eq(widgets, created + 1, "one widget per existing registry entry (+ the extra one)")
	assert_eq((prompt as Control).mouse_filter, Control.MOUSE_FILTER_IGNORE, "widgets never take the mouse")
	var own := OwnInitWidget.new()
	hud.add_child(own)
	assert_eq(own.mouse_filter, Control.MOUSE_FILTER_IGNORE, "even a widget with its own _init")
	own.queue_free()
	assert_eq(prompt.call("visible_text"), "", "hidden without a candidate")
	_probe(Vector3(0, 0, -2.0), "test.elder", "Talk")
	await step_ticks(8)
	await get_tree().process_frame
	var key := InputBindings.describe_action("interact", false)
	assert_eq(prompt.call("visible_text"), "[%s] Talk" % key, "shows '[E] Talk' for the best candidate")
	p.growth_stage = 2
	Events.growth_changed.emit(Sim.tick, "player", 1, 2)
	var mode_label: Label = hud.get("_mode_label")
	assert_true(mode_label.text.contains("Stage 2"), "growth_changed refreshes the stage label (%s)" % mode_label.text)
	p.growth_stage = 1
