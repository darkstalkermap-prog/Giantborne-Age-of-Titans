extends IntegrationSuite
## D2 (docs/systems/D2.md): the storm's rules on the real giant and its water, on the test floor - StormWater (its
## pools' depth over the ground, calm after his fall), PlayerStorm (the giant's wet share by its size, the wading's
## slowing, the shock's scale by the square of the share, the Stormcaller set's passives), the Bell-hammer's heavies on
## a foe standing in water - the Stormcaller's content (his quest, Maera's words and the Harrok lead, the roster, his
## loot paying for the set and the hammer, the forges, the prompts), the storm over the Steps (its flags), D1's tarn
## thawing in place after the Frostbound's fall, and the saves (a 0.16 fixture with his lead).


func before_each() -> void:
	await super()
	GameSession.expansion = ExpansionState.defaults()


func after_each() -> void:
	GameSession.expansion = ExpansionState.defaults()
	await super()


func _player(stage := 8) -> GiantPlayer:
	var p := spawn_player(Vector3(0, 0.05, 0), 0.0)
	await TestWait.until(self, func() -> bool: return p.is_on_floor(), 30)
	var duel: Script = load("res://scripts/debug/titan_duel.gd")
	duel.call("prepare", p, stage)   # (D3: stage 9 is the growth track's own)
	await step_ticks(2)
	return p


## A pool `depth` m deep over the floor round the origin (40 m across), as the test arena's.
func _water(depth := 6.0, calm_flag := "") -> StormWater:
	var w := StormWater.new()
	w.name = "Water"
	w.pools = [[0.0, 0.0, 20.0, 20.0, depth]]
	w.calm_flag = calm_flag
	world.add_child(w)
	return w


# --------------------------------------------------------------------------- the water

func test_the_pools_depth_and_their_calm() -> void:
	var w := _water(6.0, "test.d2.calm")
	WorldState.set_flag("test.d2.calm", false)
	await step_ticks(1)
	assert_near(StormWater.depth_at(get_tree(), Vector3(0, 0, 0)), 6.0, 1e-4, "6 m deep over the floor")
	assert_near(StormWater.depth_at(get_tree(), Vector3(5, 2.0, 3)), 4.0, 1e-4, "less where the ground stands higher")
	assert_eq(StormWater.depth_at(get_tree(), Vector3(30, 0, 0)), 0.0, "dry outside the pool")
	assert_eq(StormWater.depth_at(get_tree(), Vector3(0, 8.0, 0)), 0.0, "dry above its surface")
	assert_near(StormWater.wet_share(get_tree(), Vector3.ZERO, 24.0), 0.25, 1e-4, "a 24 m body: a quarter under it")
	assert_near(w.surface_here(Vector3(3, 0, 3)), 6.0, 1e-4, "its surface")
	WorldState.set_flag("test.d2.calm", true)
	assert_eq(StormWater.depth_at(get_tree(), Vector3.ZERO), 0.0, "after his fall the water is only water")
	WorldState.set_flag("test.d2.calm", false)


func test_the_shock_goes_as_the_square_of_the_share_under_water() -> void:
	assert_eq(PlayerStorm.shock_scale(0.0), 0.0, "dry: none")
	assert_eq(PlayerStorm.shock_scale(0.01), 0.0, "a splash: none")
	assert_near(PlayerStorm.shock_scale(0.25), 1.0, 1e-6, "a quarter under water: the whole shock")
	assert_near(PlayerStorm.shock_scale(0.125), 0.25, 1e-6, "half as deep: a quarter of it")
	assert_near(PlayerStorm.shock_scale(0.9), PlayerStorm.SHOCK_MAX, 1e-6, "at most SHOCK_MAX")


func test_a_bigger_giant_stands_higher_out_of_the_same_pool_and_wades_it_faster() -> void:
	_water(6.0)
	var wet := {}
	var slow := {}
	for stage: int in [7, 8, 9]:
		var p := await _player(stage)
		p.global_position = Vector3(0, 0.05, 0)
		await step_ticks(3)
		wet[stage] = p.storm.wet
		slow[stage] = float(p.motor.speed_mult_sources().get(&"storm_wade", 1.0))
		assert_true(p.storm.in_water(), "stage %d: in the water" % stage)
		p.queue_free()
		await step_ticks(2)
	assert_true(float(wet[7]) > float(wet[8]) and float(wet[8]) > float(wet[9]), "the share under water falls with size (%s)" % str(wet))
	assert_near(float(wet[7]), 6.0 / 23.7744, 0.01, "stage 7: 6 m of 23.8")
	assert_true(float(slow[7]) < float(slow[8]) and float(slow[8]) < float(slow[9]) and float(slow[9]) < 1.0,
		"the water slows a smaller giant more (%s)" % str(slow))
	assert_true(PlayerStorm.shock_scale(float(wet[7])) > 1.4 * PlayerStorm.shock_scale(float(wet[8])),
		"stage 7 takes far more of a shock than stage 8 in the same pool")


func test_the_set_keeps_the_storm_off_its_wearer() -> void:
	_water(6.0)
	var p := await _player(8)
	p.global_position = Vector3(0, 0.05, 0)
	await step_ticks(3)
	var bare := float(p.motor.speed_mult_sources().get(&"storm_wade", 1.0))
	var set_rec := GameData.get_record("armour_set.stormcaller")
	var mods := {}
	for b: Dictionary in set_rec.bonuses:
		for k: String in b.modifiers:
			mods[k] = float(mods.get(k, 1.0 if k.ends_with("_mult") else 0.0)) * float(b.modifiers[k]) \
				if k.ends_with("_mult") else float(mods.get(k, 0.0)) + float(b.modifiers[k])
	p.entity.combatant.set_passives(mods)
	await step_ticks(3)
	var worn := float(p.motor.speed_mult_sources().get(&"storm_wade", 1.0))
	assert_true(worn > bare, "seven pieces: the water slows it less (%.3f > %.3f)" % [worn, bare])
	assert_near(p.entity.combatant.modifier("storm_shock_taken_mult"), 0.7 * 0.6, 1e-6,
		"the shock: 30% less, then 40% less again")
	p.entity.combatant.set_passives({})


## The warning and the HUD's water meter: a bolt of his telegraphed on the water within its shock's reach warns the
## giant standing in it until it strikes (not one on dry ground, nor one beyond the reach); the meter shows only while
## the storm is awake near him and he stands in its water, and says so while he is warned.
func test_a_bolt_on_his_water_warns_the_giant_in_it() -> void:
	_water(6.0)
	var p := await _player(8)
	p.global_position = Vector3(0, 0.05, 0)
	await step_ticks(3)
	var bolt := "ability.stormcaller_bolt"
	Events.telegraph_started.emit(Sim.tick, "t#stone1", bolt, "", "circle", Vector3(40, 0, 0), 0.0, 6.0, 0.0, 2.0)
	assert_false(p.storm.warned(), "a bolt on dry ground: no warning")
	Events.telegraph_started.emit(Sim.tick, "t#stone2", "ability.stormcaller_slam", "", "circle", Vector3(5, 0, 0), 0.0,
		6.0, 0.0, 2.0)
	assert_false(p.storm.warned(), "a blow, not a bolt: no warning")
	Events.telegraph_started.emit(Sim.tick, "t#stone3", bolt, "", "circle", Vector3(12, 0, 0), 0.0, 6.0, 0.0, 1.0)
	assert_true(p.storm.warned(), "a bolt on his water within its reach: warned")
	var layer := CanvasLayer.new()
	world.add_child(layer)
	var hud := Hud.new()
	hud.size = Vector2(1280, 720)
	layer.add_child(hud)
	hud.player = p
	await get_tree().process_frame
	p.storm.danger = false
	hud.refresh()
	assert_false(bool(hud.water_meter().get("visible", true)), "no storm awake near him: no meter")
	p.storm.danger = true
	hud.refresh()
	var m := hud.water_meter()
	assert_true(bool(m.get("visible", false)), "the meter while he stands in the storm's water")
	assert_true(str(m.get("text", "")).contains("LIGHTNING"), "its warning (%s)" % str(m.get("text", "")))
	await step_ticks(int(1.2 * Sim.TICK_RATE))
	assert_false(p.storm.warned(), "the warning ends with the strike")
	p.storm.danger = true
	hud.refresh()
	assert_true(str(hud.water_meter().get("text", "")).contains("% of you under it"), "then the depth again")
	p.global_position = Vector3(40, 0.05, 0)
	await step_ticks(3)
	p.storm.danger = true
	hud.refresh()
	assert_false(bool(hud.water_meter().get("visible", true)), "dry: the meter hides")
	layer.queue_free()


func test_the_bell_hammer_rings_through_water() -> void:
	_water(6.0)
	var p := await _player(8)
	var perk: Dictionary = GameData.get_record("weapon.bell_hammer").perk
	assert_eq(str(perk.kind), "ring_through", "its perk")
	p.global_position = Vector3(0, 0.05, 0)
	await step_ticks(2)
	var e := HitEvent.new()
	e.power = 100.0
	e.poise_damage = 40.0
	AttackRunner.p31_apply_perk(perk, e, p.entity)
	assert_near(e.power, 150.0, 1e-6, "a foe in the water: half again as hard")
	assert_near(e.poise_damage, 60.0, 1e-6, "and its poise")
	p.global_position = Vector3(40, 0.05, 0)
	await step_ticks(2)
	var dry := HitEvent.new()
	dry.power = 100.0
	AttackRunner.p31_apply_perk(perk, dry, p.entity)
	assert_near(dry.power, 100.0, 1e-6, "on dry ground: as any hammer")
	assert_eq(int(GameData.get_record("weapon.bell_hammer").fit_max_stage), 9, "it fits a stage-9 giant")


# --------------------------------------------------------------------------- his content

func test_his_quest_maera_the_harrok_lead_and_the_roster() -> void:
	var q := GameData.get_record("quest.stormcaller")
	assert_eq((q.stages as Array).map(func(st: Dictionary) -> String: return str(st.id)), ["reach", "slay", "tell"],
		"the quest: reach the Stormstair, slay him, tell Maera")
	var ctx := QuestConditions.empty_context()
	ctx.flags = {"lead.stormcaller.seen": true}
	assert_true(QuestConditions.all_hold(q.start_conditions, ctx), "the look south starts it")
	var d := GameData.get_record("dialogue.hearth_maera")
	var ids: Array = (d.nodes as Array).map(func(n: Dictionary) -> String: return str(n.id))
	for n: String in ["storm_watch", "storm_fallen", "after_storm"]:
		assert_true(ids.has(n), "Maera's %s" % n)
	var fallen: Dictionary = (d.nodes as Array).filter(func(n: Dictionary) -> bool: return str(n.id) == "storm_fallen")[0]
	var eff: Dictionary = (fallen.choices[0] as Dictionary).effects
	assert_true(bool(eff.set_flags.get("lead.harrok.hearth", false)), "her lead toward Harrok's return")
	assert_true(bool(eff.set_flags.get("world.last_hearth.storm_told", false)), "the Lodestone set below the beacon")
	assert_eq(str(eff.outcome), "storm_fallen", "her outcome")
	# (her storm entries come before the Frostbound's: the newest word first)
	var order: Array = (d.entries as Array).map(func(e: Dictionary) -> String: return str(e.node))
	assert_true(order.find("storm_fallen") < order.find("after_frost"), "her storm's words before the cold's")
	var h := GameData.get_record("quest.harrok_lead")
	assert_eq((h.stages as Array).size(), 1, "Harrok's return is a lead only (one look)")
	assert_eq(str(((h.stages as Array)[0] as Dictionary).complete_when.area), "world.area.moot", "at the Moot")
	var r := ExpansionState.roster_entry("titan.stormcaller")
	assert_eq(str(r.enemy), "enemy.stormcaller", "the roster's Stormcaller is in the game")
	assert_eq(str(r.defeated_flag), "boss.stormcaller.defeated", "his defeated flag")
	assert_eq(str(r.sighted_poi), "poi.stormstair", "his lair")
	# D3: stage 9 is built, and his fall is its condition
	var g9 := GameData.get_record("growth.09")
	assert_eq(str((g9.growth_requirement as Dictionary).conditions[1].get("flag", "")), "boss.stormcaller.defeated",
		"stage 9 waits for his fall (D3)")


func test_one_fall_with_two_plates_broken_pays_for_the_set_and_the_hammer() -> void:
	var counts := {}
	for g: Dictionary in GameData.get_record("loot.stormcaller").guaranteed:
		counts[str(g.item)] = int(counts.get(str(g.item), 0)) + int(g.count)
	for pl: Dictionary in GameData.get_record("enemy.stormcaller").plates:
		if str(pl.id) in ["crown", "greave_l"]:
			for l: Dictionary in pl.get("loot", []):
				counts[str(l.item)] = int(counts.get(str(l.item), 0)) + int(l.count)
	var need := {}
	var set_rec := GameData.get_record("armour_set.stormcaller")
	var recipes: Array = []
	for piece: String in set_rec.pieces:
		recipes.append(GameData.get_record("recipe." + piece.trim_prefix("armour.")))
	recipes.append(GameData.get_record("recipe.bell_hammer"))
	for rec: Dictionary in recipes:
		assert_eq(str(rec.works), "storm_bronze", "%s is worked at Last Hearth's forge (storm_bronze)" % rec.id)
		assert_eq(str(rec.requires_flag), "boss.stormcaller.defeated", "%s once he has fallen" % rec.id)
		assert_eq(str(rec.forge_tier), "titan", "%s at a titan forge" % rec.id)
		for c: Dictionary in rec.cost:
			if str(c.item).begins_with("item.drowned") or str(c.item).begins_with("item.storm"):
				need[str(c.item)] = int(need.get(str(c.item), 0)) + int(c.count)
	for item: String in ["item.drowned_bronze", "item.storm_tine", "item.stormcaller_lodestone"]:
		assert_true(int(counts.get(item, 0)) >= int(need.get(item, 0)), "%s: %d from one fall, %d for the set and hammer" % [
			item, int(counts.get(item, 0)), int(need.get(item, 0))])
	assert_eq((set_rec.pieces as Array).size(), 7, "seven pieces")
	var two: Dictionary = (set_rec.bonuses as Array)[0]
	assert_near(float(two.modifiers.storm_shock_taken_mult), 0.7, 0.001, "two pieces: the shock takes 30% less of you")
	for forge_id: String in ["world.hoarfell.hearth_forge", "world.hoarfell.colossus_anvil"]:
		var el := _layout_element("hoarfell", forge_id)
		assert_true((el.get("works", []) as Array).has("storm_bronze"), "%s works his bronze" % forge_id)
	var trophy := _layout_element("hoarfell", "world.hoarfell.hearth_lodestone")
	assert_eq(str(trophy.get("visible_when_flag", "")), "world.last_hearth.storm_told", "the Lodestone once Maera has heard")
	for t: String in ["tutorial.stormcaller_warning", "tutorial.stormcaller_water", "tutorial.stormcaller_ground"]:
		assert_false(GameData.get_record(t).is_empty(), "the prompt %s" % t)


static func _layout_element(table: String, id: String) -> Dictionary:
	var t := WorldFeatures.load_json("res://tools/data/world/%s.json" % table)
	for el: Dictionary in t.get("elements", []):
		if str(el.get("id", "")) == id:
			return el
	return {}


# --------------------------------------------------------------------------- the storm over the Steps

func test_the_storm_stands_from_act_two_and_clears_after_his_fall() -> void:
	var el := _layout_element("drowned_steps", "world.drowned.stormstair_storm")
	assert_eq(str(el.get("active_flag", "")), "act.two.begun", "the storm came with act two")
	assert_eq(str(el.get("calm_flag", "")), "boss.stormcaller.defeated", "it clears after his fall")
	var w := StormWeather.new()
	w.radius_m = 100.0
	w.fade_m = 100.0
	w.active_flag = "test.d2.storm"
	w.calm_flag = "test.d2.calm"
	world.add_child(w)
	WorldState.set_flag("test.d2.storm", false)
	assert_eq(w.strength_at(Vector3.ZERO), 0.0, "before act two: no storm")
	WorldState.set_flag("test.d2.storm", true)
	assert_eq(w.strength_at(Vector3(50, 0, 0)), 1.0, "within its radius: full")
	assert_near(w.strength_at(Vector3(150, 0, 0)), 0.5, 1e-3, "fading beyond it")
	assert_eq(w.strength_at(Vector3(260, 0, 0)), 0.0, "gone by radius and fade")
	WorldState.set_flag("test.d2.calm", true)
	assert_true(w.calm(), "his fall: it clears")
	var world_spec := WorldFeatures.load_json("res://tools/data/world/world.json")
	var storms: Array = (world_spec.get("storms", []) as Array).filter(func(s: Dictionary) -> bool:
		return str(s.id) == "drowned_storm")
	assert_eq(storms.size(), 1, "the storm's clouds over the Steps")
	assert_eq(str((storms[0] as Dictionary).calm_flag), "boss.stormcaller.defeated", "they clear with it")
	WorldState.set_flag("test.d2.calm", false)
	WorldState.set_flag("test.d2.storm", false)


# --------------------------------------------------------------------------- D1's tarn thaws in place

func test_the_tarn_thaws_in_place_after_the_frostbounds_fall() -> void:
	var s := IceSheet.new()
	s.name = "Ice"
	s.sheet_id = "test.ice"
	s.radius_m = 40.0
	s.cell_m = 9.0
	s.thaw_flag = "test.d2.thawed"
	WorldState.set_flag("test.d2.thawed", false)
	world.add_child(s)
	await step_ticks(1)
	assert_eq(s.counts().whole, s.counts().whole + s.counts().cracked + s.counts().open, "whole before his fall")
	WorldState.set_flag("test.d2.thawed", true)
	await step_ticks(2)
	assert_false(s.cold(), "the cold is gone at once")
	assert_true(s.thaw_started >= 0, "the thaw began where the giant stands (no reload)")
	assert_true(s.counts().whole > 0, "the ice breaks up over a few seconds, not at once")
	await step_ticks(int(IceSheet.THAW_S * 0.5 * 60.0))
	var mid := s.counts()
	assert_true(mid.whole > 0 and mid.open + mid.cracked > 0, "half way: the middle open, the shore still ice (%s)" % str(mid))
	await step_ticks(int(IceSheet.THAW_S * 0.6 * 60.0) + 10)
	var done := s.counts()
	assert_eq(done.whole, 0, "thawed: no whole ice left (%s)" % str(done))
	assert_true(done.open > done.cracked, "open water and floes, as a later load shows it")
	assert_eq(s.thaw_started, -1, "the thaw is over")
	var again := s.counts()
	s.reset()
	assert_eq(s.counts(), again, "the same tarn a reload would show")
	WorldState.set_flag("test.d2.thawed", false)
	s.queue_free()


# --------------------------------------------------------------------------- saves

## D2: a 0.16.0-m16 save (tests/fixtures/saves/v3_m16_d2_storm_lead.json: written by hand from the schema, derived
## from D1's fixture - the Frostbound slain and Maera told, the look south taken, grown to stage 8, at the bell tower's
## waystone in the Drowned Steps - from before the Stormcaller was in the game) and the older saves load (schema 3, no
## new key), meet him unseen, start his quest from the lead and record his fall.
func test_older_saves_meet_him_and_record_his_fall() -> void:
	for f: String in ["v3_m15_campaign_complete.json", "v3_m16_c4_last_hearth.json", "v3_m16_d1_frost_lead.json",
			"v3_m16_d2_storm_lead.json"]:
		var doc := SaveSlots.migrate(JsonIO.read_file("res://tests/fixtures/saves/" + f).data)
		assert_eq(SaveSlots.validate(doc), PackedStringArray(), "%s validates" % f)
		assert_eq(int(doc.schema_version), 3, "%s: schema 3" % f)
		var x := ExpansionState.from_doc(doc)
		assert_eq(str(((x.get("titans", {}) as Dictionary).get("titan.stormcaller", {}) as Dictionary).get("state",
			ExpansionState.STATE_UNSEEN)), ExpansionState.STATE_UNSEEN, "%s: the Stormcaller unseen" % f)
	var d2 := SaveSlots.migrate(JsonIO.read_file("res://tests/fixtures/saves/v3_m16_d2_storm_lead.json").data)
	assert_eq(str(d2.build_version), "0.16.0-m16", "a 0.16 save")
	var flags: Dictionary = (d2.world.flags as Dictionary).duplicate(true)
	var ctx := QuestConditions.empty_context()
	ctx.flags = flags
	assert_true(QuestConditions.all_hold(GameData.get_record("quest.stormcaller").start_conditions, ctx),
		"its lead starts the Stormcaller's quest")
	assert_true(bool(flags.get("act.two.begun", false)), "act two: the storm stands and he is there")
	assert_eq(int(d2.character.growth_stage), 8, "a stage-8 giant")
	var x := ExpansionState.from_doc(d2)
	assert_eq(str((x.titans["titan.frostbound"] as Dictionary).state), ExpansionState.STATE_SLAIN, "the Frostbound slain")
	flags["boss.stormcaller.defeated"] = true
	flags["boss.stormcaller.outcome"] = "slain"
	ExpansionState.sync_from_flags(x, flags)
	assert_eq(str((x.titans["titan.stormcaller"] as Dictionary).state), ExpansionState.STATE_SLAIN, "his fall recorded")
	assert_true(bool(((x.settlements["poi.last_hearth"] as Dictionary).flags as Dictionary).get("stormcaller_fallen", false)),
		"Last Hearth's record learns it")
