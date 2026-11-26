extends IntegrationSuite
## C4 (decisions C4-1..C4-5): a settlement's development in play, on the test floor with the real giant -
##   * a load taken up at its source (HaulSource), carried in both arms (slower, his blows refused), set down at the
##     project's site (SettlementSite through PlayerHaul's E): the state's count, the site's stack flag, the event;
##     put down elsewhere it goes back to its pile; a source no work wants refuses;
##   * materials given from the pack; the deed done in the world; the work raised at its site only when all is met:
##     the tier's flags, its toast's event, its horn's; the life of the tier behind the giant's back (SettlementWatch:
##     not while he stands by it, once he is away); a FlagVisibility element of the tier shows;
##   * the garrison's posts loose only from their tier and its life, at a hostile in range, and its arrows land;
##   * the Colossus Anvil rimforges a titanforged club (a titan forge refuses, saying where to go);
##   * the save: the state written into a checkpoint document, validated and read back whole; the 0.14 and 0.15 saves
##     load with their settlements as they were (no projects key) and the C4 fixture with its projects;
##   * the settlement panel: its rows, a Give that takes from the pack, a trade, focus by keyboard and pad.

const LH := "settlement.last_hearth"
const FIXTURE_DIR := "res://tests/fixtures/saves/"

var stack: ScreenStack = null


func before_each() -> void:
	await super()
	GameSession.expansion = ExpansionState.defaults()
	stack = null


func after_each() -> void:
	if stack != null and is_instance_valid(stack):
		stack.close_all()
	GameSession.expansion = ExpansionState.defaults()
	await super()


func _rec() -> Dictionary:
	return SettlementRules.record(LH)


func _player(stage := 6) -> GiantPlayer:
	var p := spawn_player(Vector3(0, 0.05, 0), 0.0)
	await TestWait.until(self, func() -> bool: return p.is_on_floor(), 30)
	if stage > 1:
		var duel: Script = load("res://scripts/debug/titan_duel.gd")
		duel.call("prepare", p, stage)
	await step_ticks(2)
	return p


func _source(at: Vector3, load_id: String, load_name: String) -> HaulSource:
	var s := HaulSource.new()
	s.name = "Source"
	s.world_id = "test.source." + load_id
	s.load_id = load_id
	s.load_name = load_name
	s.position = at
	world.add_child(s)
	return s


func _site(at: Vector3, site_id: String) -> SettlementSite:
	var s := SettlementSite.new()
	s.name = "Site"
	s.world_id = site_id
	s.settlement_id = LH
	s.position = at
	world.add_child(s)
	return s


func _press_e(p: GiantPlayer) -> void:
	p.interact.refresh()
	p.interact.use_candidate(p.interact.current_candidate())
	await step_ticks(2)


func test_a_load_carried_and_set_down_at_its_site() -> void:
	var p := await _player()
	var src := _source(Vector3(0, 0, -6), "timber", "great timber")
	var site := _site(Vector3(0, 0, -40), "world.hoarfell.hearth_site_hall")
	await step_ticks(2)
	assert_true(src.can_interact(p), "the Windfall's timber is wanted (the hall)")
	await _press_e(p)
	assert_true(p.haul.is_carrying(), "he carries a timber")
	assert_eq(float(p.motor.speed_mult_sources().get(&"haul", 1.0)), PlayerHaul.CARRY_SPEED_MULT, "slower with it")
	assert_true(p.get_rig_state().get("holding", "") == "two_hand", "in both arms")
	assert_true(p.get_node_or_null("HaulLoad") != null, "its mesh rides before his chest")
	p.router.inject_edge(&"light")
	await step_ticks(3)
	assert_true(p.controller.action == null or p.controller.action.kind != "light", "his light is refused while carrying")
	assert_false(src.can_interact(p), "his arms are full")
	# put down away from the site: back to its pile
	await _press_e(p)
	assert_false(p.haul.is_carrying(), "put down")
	assert_eq(SettlementRules.project_state(SettlementWork.state(_rec()), "hall_roof").hauled.get("timber", 0), 0, "nothing delivered")
	# carried to the site and set down there
	var progress: Array = []
	var cb := func(_t: int, sid: String, pid: String, what: String) -> void: progress.append([sid, pid, what])
	Events.settlement_progress.connect(cb)
	await _press_e(p)
	assert_true(p.haul.is_carrying(), "taken up again")
	p.global_position = Vector3(0, 0.05, -36)
	await step_ticks(3)
	assert_true(site.accepts("timber"), "the hall's site wants it")
	await _press_e(p)
	Events.settlement_progress.disconnect(cb)
	assert_false(p.haul.is_carrying(), "set down")
	assert_eq(int(SettlementRules.project_state(SettlementWork.state(_rec()), "hall_roof").hauled.get("timber", 0)), 1, "one timber at the hall")
	assert_true(QuestConditions.truthy(WorldState.get_flag("settlement.last_hearth.hall_roof.timber_1")), "its stack's flag")
	assert_eq(progress, [[LH, "hall_roof", "haul:timber"]], "the event")
	assert_eq(float(p.motor.speed_mult_sources().get(&"haul", 1.0)), 1.0, "his pace back")
	# a load no work wants
	var stone := _source(Vector3(4, 0, -36), "kingstone", "king-stone")
	await step_ticks(1)
	assert_false(stone.can_interact(p), "no work being earned wants a king-stone at tier 0")
	assert_true(stone.blocked_reason(p).contains("No settlement needs"), "and it says so")


func test_a_tier_earned_raised_and_settled() -> void:
	var p := await _player()
	var rec := _rec()
	var st := SettlementWork.state(rec)
	var site := _site(Vector3(0, 0, -8), "world.hoarfell.hearth_site_hall")
	var shown := FlagVisibility.new()
	shown.visible_when_flag = "settlement.last_hearth.hall_roof.raised"
	world.add_child(shown)
	var life := FlagVisibility.new()
	life.visible_when_flag = "settlement.last_hearth.tier_1.settled"
	world.add_child(life)
	await step_ticks(2)
	assert_false(shown.visible, "the roofed hall hidden at tier 0")
	assert_true(site.enabled, "the hall's site offers its work")
	assert_false(site.can_interact(p), "not ready")
	assert_true(site.blocked_reason(p).contains("Not yet"), "it names what is missing: %s" % site.blocked_reason(p))
	SettlementWork.deliver(rec, "hall_roof", "timber")
	SettlementWork.deliver(rec, "hall_roof", "timber")
	WorldState.add_item("item.hide", 5, "test")
	var g := SettlementWork.give(rec, "hall_roof", "item.hide")
	assert_true(bool(g.ok) and int(g.count) == 3, "three hides given")
	assert_eq(WorldState.count_of("item.hide"), 2, "taken from the pack")
	var ready: Array = []
	var cb := func(_t: int, sid: String, pid: String) -> void: ready.append(pid)
	Events.settlement_ready.connect(cb)
	WorldState.record_destroyed("world.hoarfell.hearth_rockfall", 1)
	var tiers: Array = []
	var cb2 := func(_t: int, sid: String, tier: int) -> void: tiers.append(tier)
	Events.settlement_tier.connect(cb2)
	assert_true(site.can_interact(p), "ready once the rockfall is heaved")
	assert_eq(site.prompt_text(p), "Raise the roof-tree", "its prompt")
	await _press_e(p)
	Events.settlement_ready.disconnect(cb)
	Events.settlement_tier.disconnect(cb2)
	assert_eq(tiers, [1], "Last Hearth stands at tier 1")
	assert_eq(SettlementRules.tier_of(st), 1, "its state")
	assert_eq(WorldState.get_flag("settlement.last_hearth.tier"), 1, "the world's tier flag")
	assert_true(shown.visible, "the roofed hall shows at once (he raised it)")
	assert_false(site.enabled, "its site offers nothing more")
	# the tier's life comes behind his back
	var watch := SettlementWatch.new()
	watch.level_id = "level.world"
	world.add_child(watch)
	watch._started = true
	watch.position_override = SettlementWatch.centre_of(rec) + Vector3(20, 0, 0)
	watch.poll()
	assert_false(life.visible, "not while he stands by the camp")
	watch.position_override = SettlementWatch.centre_of(rec) + Vector3(400, 0, 0)
	watch.poll()
	assert_true(life.visible, "once he is away: the folk, the fire, the smoke")
	assert_eq(SettlementRules.current_projects(rec, st).size(), 2, "tier 2's ring and forge are being earned")


func test_the_garrison_looses_from_its_tier_at_a_hostile() -> void:
	var rec := _rec()
	var g := SettlementGarrison.new()
	g.settlement_id = LH
	g.posts = [{"pos": [0, 3, 0], "member": "", "min_tier": 2, "range_m": 60, "interval_s": 1.0, "power": 60, "kind": "bow"}]
	world.add_child(g)
	var s := spawn_soldier(Vector3(0, 0.05, -30), 0.0, "c4_raider", false)
	s.entity.team = CombatEntity.Team.ENEMY
	await step_ticks(5)
	var hp0 := s.entity.combatant.pools.health
	await step_ticks(90)
	assert_eq(g.shots, 0, "no shots at tier 0")
	SettlementWork.debug_set_tier(rec, 2, false)
	await step_ticks(90)
	assert_eq(g.shots, 0, "none before the tier's life has come (its archers are not on the steps)")
	SettlementWork.debug_set_tier(rec, 2, true)
	assert_eq(g.manned_count(), 1, "the post is manned")
	await step_ticks(130)
	assert_true(g.shots >= 2 and g.hits >= 1, "it looses (%d shots, %d hits)" % [g.shots, g.hits])
	assert_true(s.entity.combatant.pools.health < hp0 or not s.entity.is_alive(), "and its arrows land")
	g.queue_free()


func test_the_colossus_anvil_rimforges() -> void:
	var p := await _player(6)
	p.equipment.grant_weapon("weapon.club_titan")
	p.equipment.equip_weapon("weapon.club_titan")
	WorldState.add_item("item.titan_iron", 2, "test")
	WorldState.add_item("item.iron_ingot", 3, "test")
	var titan := (load("res://scenes/world/forge.tscn") as PackedScene).instantiate() as Forge
	titan.world_id = "c4.titan_forge"
	titan.tier = "titan"
	world.add_child(titan)
	var anvil := (load("res://scenes/world/forge.tscn") as PackedScene).instantiate() as Forge
	anvil.world_id = "c4.colossus_anvil"
	anvil.tier = "colossus"
	anvil.look_scale = 2.2
	anvil.position = Vector3(30, 0, 0)
	world.add_child(anvil)
	await step_ticks(2)
	var refused := titan.can_upgrade(p)
	assert_eq(str(refused.reason), "forge_tier", "a titan forge cannot rimforge")
	assert_true(str(refused.message).contains("Colossus Anvil"), "it says where to go")
	assert_true(anvil.look.scale.is_equal_approx(Vector3.ONE * 2.2), "the anvil's smithy at a colossus's size")
	assert_true(bool(anvil.upgrade(p).ok), "the anvil rimforges")
	assert_eq(p.equipment.weapon_id(), "weapon.club_rimforged", "the Rimforged Club")
	assert_eq(int(GameData.get_record("weapon.club_rimforged").fit_max_stage), 8, "it fits stages 7 and 8")


func test_the_state_saves_and_older_saves_load() -> void:
	var rec := _rec()
	var st := SettlementWork.state(rec)
	SettlementRules.deliver(rec, st, "hall_roof", "timber")
	SettlementRules.give(st, "hall_roof", "item.hide", 2)
	var doc := ExpansionState.write_into({}, GameSession.expansion)
	assert_eq(ExpansionState.validate(doc), PackedStringArray(), "the document validates")
	var back := ExpansionState.from_doc(JSON.parse_string(JSON.stringify(doc)))
	var pst: Dictionary = back.settlements["poi.last_hearth"].projects.hall_roof
	assert_eq([int(pst.hauled.timber), int(pst.given["item.hide"]), bool(pst.raised)], [1, 2, false], "read back whole")
	for f: String in ["v3_m14_valley", "v3_m14_world_mixed", "v3_m15_campaign_complete"]:
		var r := JsonIO.read_file(FIXTURE_DIR + f + ".json")
		var d := SaveSlots.migrate(r.data)
		assert_eq(SaveSlots.validate(d), PackedStringArray(), "%s validates" % f)
		var e := ExpansionState.from_doc(d)
		for poi: String in e.settlements:
			assert_false((e.settlements[poi] as Dictionary).has("projects"), "%s: %s without projects" % [f, poi])
		GameSession.expansion = e
		WorldState.flags = (d.world.flags as Dictionary).duplicate(true)
		SettlementWork.mend_flags("")
		assert_eq(SettlementRules.tier_of(SettlementWork.state(rec)), 0, "%s: Last Hearth at tier 0" % f)
	var c4 := SaveSlots.migrate(JsonIO.read_file(FIXTURE_DIR + "v3_m16_c4_last_hearth.json").data)
	assert_eq(SaveSlots.validate(c4), PackedStringArray(), "the C4 fixture validates")
	GameSession.expansion = ExpansionState.from_doc(c4)
	WorldState.flags = (c4.world.flags as Dictionary).duplicate(true)
	SettlementWork.mend_flags("")
	var st2 := SettlementWork.state(rec)
	assert_eq(SettlementRules.tier_of(st2), 1, "its Last Hearth at tier 1")
	assert_eq(SettlementRules.wants_load(rec, st2, "ring_wall", "kingstone"), 1, "one king-stone still wanted for the ring")


func test_the_panel_gives_trades_and_takes_focus() -> void:
	var p := await _player()
	var rec := _rec()
	SettlementWork.debug_set_tier(rec, 1)
	WorldState.add_item("item.iron_ingot", 4, "test")
	WorldState.add_item("item.hide", 3, "test")
	var layer := CanvasLayer.new()
	world.add_child(layer)
	stack = ScreenStack.new()
	layer.add_child(stack)
	await get_tree().process_frame
	var sc := stack.open("settlement", {"settlement": LH, "player": p}) as SettlementScreen
	await get_tree().process_frame
	await get_tree().process_frame
	assert_true(sc != null and stack.is_open("settlement"), "the panel opens")
	assert_true(sc.tiers_text().contains("The Roofed Hall (stands)") and sc.tiers_text().contains("The Stone Ring (being earned)"),
		"the tier track: %s" % sc.tiers_text())
	var rows := sc.rows_text()
	assert_eq(rows.size(), 2, "tier 2's two projects: %s" % [rows])
	sc.select(1)
	assert_true(sc.detail_text().contains("Iron to start the forge"), "the forge's needs")
	assert_true(sc.detail_text().contains("The Hearth's forge"), "what its tier unlocks")
	var r := sc.press_give("item.iron_ingot", "forge")
	assert_true(bool(r.ok), "Give: %s" % r.message)
	assert_eq(WorldState.count_of("item.iron_ingot"), 1, "three iron taken")
	assert_true(sc.result_text().contains("Given to Last Hearth"), "it says so")
	sc.show_tab_named("Trades")
	assert_eq(sc.rows_text().size(), 1, "one trade open at tier 1")
	var t := sc.press_trade("hides_for_iron")
	assert_true(bool(t.ok), "traded: %s" % t.message)
	assert_eq([WorldState.count_of("item.hide"), WorldState.count_of("item.iron_ingot")], [0, 2], "hides for iron")
	sc.show_tab_named("Tiers")
	assert_eq(sc.rows_text().size(), 4, "every tier listed")
	# focus: the tab row, the rows, Leave; keyboard and pad move through them
	var rows_f := sc.focus_rows()
	assert_eq((rows_f[0] as Array).size(), 3, "the tab row first")
	assert_true((rows_f[rows_f.size() - 1] as Array).has(sc.leave_button), "Leave last")
	sc.show_tab(0)
	await get_tree().process_frame
	sc.row_buttons[0].grab_focus()
	var down := InputEventAction.new()
	down.action = "ui_down"
	down.pressed = true
	Input.parse_input_event(down)
	await get_tree().process_frame
	await get_tree().process_frame
	assert_true(sc.row_buttons[1].has_focus() or sc.get_viewport().gui_get_focus_owner() != sc.row_buttons[0],
		"down moves the focus off the first row")
	# the Character menu's tab lists it
	var lines := SettlementScreen.summary_lines(rec)
	assert_true(lines[0].contains("Last Hearth: The Roofed Hall (tier 1 of 3)"), "the Character menu's summary: %s" % lines[0])
	assert_true(CharacterScreen.TABS.has("Settlements"), "the Character menu's Settlements tab")
	stack.close_all()


func test_an_older_aftermath_is_its_first_tier() -> void:
	var watch := SettlementWatch.new()
	watch.level_id = "level.world"
	world.add_child(watch)
	watch._started = true
	var mill := SettlementRules.record("settlement.millford")
	watch.position_override = SettlementWatch.centre_of(mill) + Vector3(30, 0, 0)
	WorldState.set_flag("world.quarry.reopened", true)
	watch.poll()
	assert_eq(SettlementRules.tier_of(SettlementWork.state(mill)), 0, "not while the giant stands in Millford")
	watch.position_override = SettlementWatch.centre_of(mill) + Vector3(600, 0, 0)
	watch.poll()
	assert_eq(SettlementRules.tier_of(SettlementWork.state(mill)), 1, "the reopened quarry is Millford's first tier, behind his back")
	assert_true(QuestConditions.truthy(WorldState.get_flag("settlement.millford.tier_1")), "its flag")
	# Thornwick's (the Valley's) comes while the giant is in the world: another level is always away
	WorldState.set_flag("world.ogre_king.defeated", true)
	watch.poll()
	var thorn := SettlementRules.record("settlement.thornwick")
	assert_eq(SettlementRules.tier_of(SettlementWork.state(thorn)), 1, "the King's trophies are Thornwick's first tier")
	# the second tier's work: its site, its load, its gift
	var st := SettlementWork.state(mill)
	assert_eq(SettlementRules.wants_load(mill, st, "masons_hall", "block"), 2, "the masons' hall wants two quarry blocks")
	assert_eq(SettlementScreen.summary_lines(mill)[0], "# Millford: The Quarry Reopened (tier 1 of 2)", "its summary")
