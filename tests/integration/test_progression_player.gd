extends IntegrationSuite
## PlayerProgression in the real giant (plan §3.14): the sandbox giant earns XP and levels but is
## never level-gated; a Valley character (applied state) is gated, and a level-up learns, auto-slots
## and announces its abilities, the notice waiting until the giant is out of combat;
## learn_ability(Mend, "reward") at level 3 is usable at once, slotted, and survives a checkpoint
## reload; kill XP only for the player's kills of ENEMY actors (never a neutral dummy; props pay
## through xp_award_requested once); allocation with the derived maxima keeping their fractions and
## the Dexterity cap; the shrine's Loadout and Attributes tabs; F8 and the XP bar; the save keys.

const SHRINE := "res://scenes/world/shrine.tscn"
const FLOW := "res://scenes/test/flow_test_level.tscn"
const GATE := "res://scenes/world/gate_practice.tscn"

var xp_events: Array = []
var level_events: Array = []
var learned_events: Array = []
var attribute_events := 0
var messages: Array[String] = []
var level: Node3D


func before_each() -> void:
	await super()
	xp_events.clear()
	level_events.clear()
	learned_events.clear()
	attribute_events = 0
	messages.clear()
	Events.xp_gained.connect(_on_xp)
	Events.level_changed.connect(_on_level)
	Events.ability_learned.connect(_on_learned)
	Events.attributes_changed.connect(_on_attributes)
	Events.hud_message.connect(_on_message)


func after_each() -> void:
	for sig: Signal in [Events.xp_gained, Events.level_changed, Events.ability_learned,
			Events.attributes_changed, Events.hud_message]:
		for c: Dictionary in sig.get_connections():
			if (c.callable as Callable).get_object() == self:
				sig.disconnect(c.callable)
	if level != null and is_instance_valid(level):
		level.queue_free()
	level = null
	await super()


func _on_xp(_tick: int, amount: int, source: String, total: int) -> void:
	xp_events.append([amount, source, total])


func _on_level(_tick: int, old_level: int, new_level: int) -> void:
	level_events.append([old_level, new_level])


func _on_learned(_tick: int, action_id: String, slot_key: String) -> void:
	learned_events.append([action_id, slot_key])


func _on_attributes(_tick: int) -> void:
	attribute_events += 1


func _on_message(text: String, _kind: String) -> void:
	messages.append(text)


func _new_game_state() -> Dictionary:
	return CharacterState.new_game(GameData.get_record("progression.default"), GameData.get_record("player.giant"))


## A giant with the New Game character applied (level 1, gated, Footfall and Sweep slotted).
func _valley_player(pos := Vector3(0, 0.05, 0)) -> GiantPlayer:
	var p := spawn_player(pos)
	await step_ticks(1)
	p.apply_character_state(_new_game_state())
	return p


func _hud() -> Hud:
	var layer := CanvasLayer.new()
	world.add_child(layer)
	var hud := Hud.new()
	layer.add_child(hud)
	return hud


func _slot_reason(p: GiantPlayer, slot: int) -> String:
	return p.controller.preview_reason(&"slot", {"slot": slot})


# --------------------------------------------------------------------------- gating

func test_the_sandbox_giant_earns_xp_and_levels_without_level_gating() -> void:
	var p := spawn_player(Vector3(0, 0.05, 0))
	await step_ticks(2)
	var prog: PlayerProgression = p.progression
	assert_true(prog != null, "the progression component exists")
	assert_false(prog.is_gated(), "a fresh giant is not level-gated")
	assert_eq(p.controller.level, 99, "controller.level 99 (gating off)")
	assert_eq([prog.level, prog.xp], [1, 0], "level 1, no XP")
	var r := prog.add_xp(250, "test")
	assert_eq(int(r.new_level), 3, "250 XP: level 3")
	assert_eq(xp_events, [[250, "test", 250]], "xp_gained with the total")
	assert_eq(level_events, [[1, 3]], "level_changed once")
	assert_eq([prog.unspent_attribute_points, prog.talent_points], [6, 2], "points for two levels")
	assert_eq(p.controller.level, 99, "the sandbox stays ungated after a level-up")
	assert_eq(_slot_reason(p, 7), "", "Mend (level 4) is still usable in the sandbox")
	assert_eq(learned_events, [], "the sandbox giant knows every library ability already")
	var out := p.capture_character_state()
	assert_eq(int(out.level), 99, "its saved level says 'no gating'")
	assert_eq(int(out.xp), 250, "with its XP")
	var again := _new_game_state()
	again["level"] = 99
	again["xp"] = 460
	p.apply_character_state(again)
	assert_false(prog.is_gated(), "applying level 99 keeps gating off")
	assert_eq(prog.level, 4, "the level shown follows the XP (460: level 4)")
	assert_eq(p.controller.level, 99, "and the controller stays ungated")


func test_a_level_up_learns_auto_slots_and_waits_to_announce() -> void:
	var p := await _valley_player()
	var hud := _hud()
	var prog: PlayerProgression = p.progression
	assert_true(prog.is_gated(), "an applied character is gated")
	assert_eq(p.controller.level, 1, "level 1")
	assert_eq(_slot_reason(p, 1), "", "Footfall usable")
	await step_ticks(2)
	var notice := hud.get_node_or_null("AbilityNotice")
	var bar := hud.get_node_or_null("XpBar")
	assert_true(notice != null and bar != null, "the notice and XP bar widgets are on the HUD")
	if notice == null or bar == null:
		return
	assert_eq(str(bar.call("visible_text")), "Lv 1  0 / 100 XP", "the XP bar")
	var pools := p.entity.combatant.pools
	pools.mark_combat()
	prog.add_xp(100, "test")
	assert_eq(level_events, [[1, 2]], "level 2")
	assert_eq(p.controller.level, 2, "pushed to the controller")
	assert_eq(learned_events, [["ability.stone_skin", "slot_3"], ["ability.crushing_grip", "slot_4"]],
		"Stone Skin into slot 3 and Crushing Grip into slot 4")
	assert_eq(p.controller.loadout.slot_3, "ability.stone_skin", "slot 3 holds Stone Skin")
	assert_eq(_slot_reason(p, 3), "", "and it is usable at level 2")
	assert_true(p.known_abilities.has("ability.stone_skin"), "known")
	assert_true(messages.has("Level 2! +3 attribute points, +1 talent point"), "a level-up line")
	for i in 3:
		await get_tree().process_frame
	assert_eq(str(notice.call("visible_text")), "", "no notice while fighting")
	assert_eq(int(notice.call("pending_count")), 2, "both notices wait")
	pools.since_combat = 999.0
	for i in 3:
		await get_tree().process_frame
	assert_eq(str(notice.call("visible_text")), "New ability: Stone Skin [3]", "the first notice once out of combat")
	assert_eq(int(notice.call("pending_count")), 1, "the second one next")
	assert_true(str(bar.call("visible_text")).begins_with("Lv 2  0 / 150 XP"), "the bar shows level 2 (%s)" % bar.call("visible_text"))
	prog.add_xp(150, "test")
	assert_eq(learned_events.back(), ["ability.runic_bolt", "slot_6"], "level 3: Runic Bolt into its own slot 6")
	assert_eq(p.controller.loadout.slot_5, "", "slot 5 stays free for Boulder Hurl")


func test_a_reward_ability_is_usable_slotted_and_survives_a_reload() -> void:
	GameSession.level_override = FLOW
	GameSession.start_new_valley()
	level = (load(FLOW) as PackedScene).instantiate() as Node3D
	world.add_child(level)
	var p := level.get_node("Player") as GiantPlayer
	p.router.use_injection = true
	GameSession.on_level_ready(level, p)
	await step_ticks(2)
	assert_eq(p.controller.level, 1, "New Game: level 1, gated")
	p.progression.add_xp(250, "test")
	assert_eq(p.progression.level, 3, "level 3")
	assert_false(p.known_abilities.has("ability.ancestral_mend"), "Mend is a level-4 ability")
	learned_events.clear()
	assert_true(p.progression.learn_ability("ability.ancestral_mend", "reward"), "taught by a reward")
	assert_eq(learned_events, [["ability.ancestral_mend", "slot_7"]], "auto-slotted into slot 7")
	assert_true(p.controller.level_exempt.has("ability.ancestral_mend"), "level_exempt")
	assert_eq(_slot_reason(p, 7), "", "usable at once at level 3")
	assert_eq(_slot_reason(p, 8), "empty_slot", "slot 8 stays empty (Roar is a level-4 ability)")
	assert_false(p.progression.learn_ability("ability.ancestral_mend", "reward"), "a second teaching does nothing")
	assert_eq(learned_events.size(), 1, "and announces nothing")
	var taken: Dictionary = GameSession.take_checkpoint("test")
	assert_true(taken.ok, "a checkpoint (%s)" % taken)
	assert_eq(int(GameSession.checkpoint_doc.character.level), 3, "the save holds level 3")
	assert_eq(GameSession.checkpoint_doc.character.level_exempt, ["ability.ancestral_mend"], "and the exemption")
	GameSession.reload_checkpoint("debug")
	level.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	level = (load(FLOW) as PackedScene).instantiate() as Node3D
	world.add_child(level)
	p = level.get_node("Player") as GiantPlayer
	p.router.use_injection = true
	GameSession.on_level_ready(level, p)
	await step_ticks(2)
	assert_eq(p.progression.level, 3, "after the reload: level 3")
	assert_eq(p.controller.level, 3, "gated at 3")
	assert_eq(p.progression.xp, 250, "250 XP")
	assert_eq(p.progression.unspent_attribute_points, 6, "the points")
	assert_true(p.known_abilities.has("ability.ancestral_mend"), "Mend is still known")
	assert_eq(p.controller.loadout.slot_7, "ability.ancestral_mend", "still in slot 7")
	assert_eq(_slot_reason(p, 7), "", "and still usable at level 3")
	assert_eq(_slot_reason(p, 6), "", "Runic Bolt too")


# --------------------------------------------------------------------------- kill XP

func test_kill_xp_comes_from_the_players_kills_of_enemies_only() -> void:
	var p := spawn_player(Vector3(0, 0.05, 0))
	var a := spawn_soldier(Vector3(-6, 0.05, -6), 0.0, "test.soldier_a")
	var b := spawn_soldier(Vector3(6, 0.05, -6), 0.0, "test.soldier_b")
	var dummy := spawn_dummy(Vector3(0, 0, -8), "test.dummy")
	await step_ticks(2)
	queue_hit("player", "test.soldier_a", a.global_position + Vector3(0, 1, 2), 5000.0)
	await step_ticks(2)
	assert_true(deaths.has("test.soldier_a"), "the player killed a soldier")
	assert_eq(xp_events, [[20, "kill:test.soldier_a", 20]], "its 20 XP")
	queue_hit("tester", "test.soldier_b", b.global_position + Vector3(0, 1, 2), 5000.0)
	await step_ticks(2)
	assert_true(deaths.has("test.soldier_b"), "someone else killed the other")
	assert_eq(xp_events.size(), 1, "no XP for a kill that is not the player's")
	assert_false(WorldState.deltas.has("test.soldier_a"), "a soldier without a loot table leaves no loot delta")
	dummy.entity.combatant.unkillable = false
	queue_hit("player", "test.dummy", Vector3(0, 1, -6), 50000.0)
	await step_ticks(2)
	assert_eq(xp_events.size(), 1, "a NEUTRAL target (the dummy) gives no kill XP")
	var gate := (load(GATE) as PackedScene).instantiate() as BreakableProp
	gate.world_id = "test.gate"
	gate.position = Vector3(0, 0, 12)
	world.add_child(gate)
	await step_ticks(2)
	queue_hit("player", "test.gate", Vector3(0, 1, 9), 5000.0)
	await step_ticks(2)
	assert_true(gate.destroyed, "the player broke the practice gate")
	assert_eq(xp_events.size(), 2, "its XP once (xp_award_requested), not again as a kill")
	assert_eq(xp_events.back(), [20, "prop:test.gate", 40], "20 XP from the prop")
	assert_eq(p.progression.xp, 40, "40 XP in all")


# --------------------------------------------------------------------------- attributes

func test_allocation_raises_maxima_keeping_fractions_and_dexterity_is_capped() -> void:
	var p := await _valley_player()
	var prog: PlayerProgression = p.progression
	prog.add_xp(100, "test")
	var pools := p.entity.combatant.pools
	pools.health = pools.health_max * 0.5
	var r := prog.allocate({"endurance": 2})
	assert_true(r.ok, "two points into Endurance")
	assert_near(pools.health_max, 530.0, 1e-6, "Endurance 12: 500 + 30 health")
	assert_near(pools.stamina_max, 104.0, 1e-6, "and 100 + 4 stamina")
	assert_near(pools.health / pools.health_max, 0.5, 1e-6, "the health fraction is kept")
	assert_eq(attribute_events, 1, "attributes_changed")
	assert_eq(prog.unspent_attribute_points, 1, "one point left")
	assert_eq(int(p.capture_character_state().attributes.endurance), 12, "saved as Endurance 12")
	assert_false(prog.allocate({"strength": 2}).ok, "not enough points")
	assert_eq(attribute_events, 1, "a refusal changes nothing")
	var preview: Dictionary = prog.derived_preview({"endurance": 1})
	assert_near(float(preview.health), 545.0, 1e-6, "the preview of one more point")
	var state := p.capture_character_state()
	state["attributes"]["dexterity"] = 60
	p.apply_character_state(state)
	assert_near(p.controller.recovery_scale, 0.85, 1e-9, "Dexterity 60 is capped at -15% recovery")
	state["attributes"]["dexterity"] = 20
	p.apply_character_state(state)
	assert_near(p.controller.recovery_scale, 0.95, 1e-9, "Dexterity 20: -5%")
	var screen_layer := CanvasLayer.new()
	world.add_child(screen_layer)
	var stack := ScreenStack.new()
	screen_layer.add_child(stack)
	await get_tree().process_frame
	prog.add_xp(150, "test")   # level 3: 3 more points
	var s := stack.open("attributes", {"player": p}) as AttributesScreen
	assert_true(s != null, "SCREENS[attributes] opens the attributes screen")
	if s == null:
		return
	var panel := s.panel_ui
	assert_eq(panel.ancestry_text(), "Ancestry: Unaligned — no modifiers in the prototype", "the ancestry line")
	assert_true(panel.talent_text().contains("talent trees are a full-game feature"), "the talent note")
	assert_true(panel.add_point("strength"), "plan a point")
	assert_true(panel.add_point("strength"), "and another")
	assert_true(panel.preview_text().contains("Damage x1.150 -> x1.180"), "the preview shows the damage change (%s)" % panel.preview_text())
	assert_true(panel.remove_point("strength"), "take one back")
	var out := panel.confirm()
	assert_true(out.ok, "confirm spends it")
	assert_eq(int(prog.attributes().strength), 11, "Strength 11")
	assert_eq(prog.unspent_attribute_points, 3, "3 points left")
	stack.close_all()


# --------------------------------------------------------------------------- shrine tabs

func test_shrine_loadout_and_attributes_tabs() -> void:
	var s: Shrine = (load(SHRINE) as PackedScene).instantiate()
	s.world_id = "test.shrine"
	s.shrine_id = "shrine.sandbox"
	s.position = Vector3(0, 0, -8)
	world.add_child(s)
	var p := spawn_player(Vector3(0, 0.05, 0))
	await TestWait.until(self, func() -> bool: return p.is_on_floor(), 30)
	await step_ticks(2)
	var prog: PlayerProgression = p.progression
	assert_eq(prog.set_slot("slot_3", "ability.runic_bolt", null).reason, "no_shrine", "only at a shrine")
	var layer := CanvasLayer.new()
	world.add_child(layer)
	var stack := ScreenStack.new()
	layer.add_child(stack)
	await get_tree().process_frame
	var screen := stack.open("shrine", {"shrine": s}) as ShrineScreen
	assert_true(screen != null, "the shrine screen opens")
	if screen == null:
		return
	var tab := screen.tab("Loadout")
	assert_true(tab != null and screen.tab("Attributes") != null, "Loadout and Attributes tabs")
	if tab == null:
		stack.close_all()
		return
	var options: PackedStringArray = tab.call("options_for", "slot_3")
	assert_eq(options[0], "", "an empty choice first")
	assert_true(options.has("ability.runic_bolt") and not options.has("ability.titan_surge"),
		"slots offer abilities, not the ultimate")
	assert_eq(tab.call("options_for", "ultimate"), PackedStringArray(["", "ability.titan_surge"]), "the ultimate slot offers ultimates")
	var before_6 := str(p.controller.loadout.slot_6)
	var before_3 := str(p.controller.loadout.slot_3)
	var out: Dictionary = tab.call("assign", "slot_3", "ability.runic_bolt")
	assert_true(out.ok, "Runic Bolt into slot 3")
	assert_eq(p.controller.loadout.slot_3, "ability.runic_bolt", "slot 3 holds it")
	assert_eq(p.controller.loadout.slot_6, before_3, "the slots swapped (%s was in slot 6)" % before_6)
	assert_eq(str(tab.call("assign", "ultimate", "ability.stone_skin").reason), "wrong_kind", "an ability is no ultimate")
	assert_eq(str(tab.call("assign", "slot_2", "ability.light_1").reason), "not_known", "only learned abilities")
	assert_true(tab.call("assign", "slot_8", "").ok, "a slot can be emptied")
	assert_eq(p.controller.loadout.slot_8, "", "slot 8 is empty")
	p.entity.combatant.pools.mark_combat()
	assert_eq(str(tab.call("assign", "slot_8", "ability.thunder_roar").reason), "combat", "not during combat")
	assert_eq(p.controller.loadout.slot_8, "", "nothing changed")
	p.entity.combatant.pools.since_combat = 999.0
	prog.add_xp(100, "test")
	var attr_tab := screen.tab("Attributes")
	var spent: Dictionary = attr_tab.call("spend", {"constitution": 3})
	assert_true(spent.ok, "the Attributes tab spends points")
	assert_near(p.entity.combatant.poise.threshold, 109.0, 1e-6, "Constitution 13: +9 poise")
	var no_loadout: Dictionary = GameData.get_record("shrine.sandbox").duplicate(true)
	no_loadout["id"] = "shrine.test_plain"
	no_loadout["loadout"] = false
	no_loadout["attributes"] = false
	TestFixtures.record_override("shrine.test_plain", no_loadout)
	stack.close_all()
	s.shrine_id = "shrine.test_plain"
	var plain := stack.open("shrine", {"shrine": s}) as ShrineScreen
	var titles: Array = []
	for t in plain.tabs:
		titles.append(t.tab_title())
	assert_eq(titles, ["Rest", "Grow"], "a shrine record can turn both tabs off")
	assert_eq(prog.set_slot("slot_3", "ability.stone_skin", s).reason, "no_shrine", "and its loadout")
	stack.close_all()


# --------------------------------------------------------------------------- debug key, bar, save keys

func test_f8_adds_100_xp_and_the_save_keys_round_trip() -> void:
	var p := await _valley_player()
	p.router.inject_edge(&"debug_xp")
	await step_ticks(2)
	assert_eq(xp_events, [[100, "debug", 100]], "F8: +100 XP")
	assert_eq(p.progression.level, 2, "level 2")
	assert_true(messages.has("DEBUG: +100 XP"), "announced")
	assert_eq(PlayerProgression.level_up_text({"new_level": 4, "attribute_points": 6, "talent_points": 2}),
		"Level 4! +6 attribute points, +2 talent points", "the level-up line")
	var out := p.capture_character_state()
	for key: String in CharacterState.PROGRESSION_KEYS:
		assert_true(out.has(key), "the save has %s" % key)
	assert_eq([int(out.level), int(out.xp), int(out.unspent_attribute_points), int(out.talent_points)],
		[2, 100, 3, 1], "level, XP and points")
	assert_eq(str(out.ancestry), "ancestry.neutral", "the ancestry")
	var json: Dictionary = JSON.parse_string(JSON.stringify(CharacterState.normalize(out)))
	p.queue_free()
	await step_ticks(2)
	var q := spawn_player(Vector3(6, 0.05, 0))
	await step_ticks(1)
	q.apply_character_state(CharacterState.normalize(json))
	assert_true(q.progression.is_gated(), "a loaded character is gated")
	assert_eq([q.progression.level, q.progression.xp, q.progression.unspent_attribute_points,
		q.progression.talent_points], [2, 100, 3, 1], "and the same after JSON")
	assert_eq(q.capture_character_state().attributes, out.attributes, "attributes round-trip")
	assert_eq(CharacterState.progression_part(q.capture_character_state()), CharacterState.progression_part(out),
		"every progression key round-trips through JSON")
	assert_eq(CharacterState.progression_part({"xp": 5, "loadout": {}}), {"xp": 5}, "progression_part keeps only those keys")
	assert_false(CharacterState.is_ungated(out), "level 2 is gated")
	assert_true(CharacterState.is_ungated({"level": 99}), "level 99 is not")
	assert_eq(xp_events.size(), 1, "a restore emits no XP")
	assert_eq(level_events.size(), 1, "and no level change")
