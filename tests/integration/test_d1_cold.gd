extends IntegrationSuite
## D1 (docs/systems/D1.md): the cold's rules on the real giant and the tarn's ice, on the test floor - PlayerRime (rime
## by a giant's stage and armour, the slow, the freeze and a heavy that shatters it, the thaw by time and by a fire, a
## blow's rime, the wade), WarmthSource (lit by its flag), IceSheet (cracked and broken by area pulses, men's blows
## too small, refrozen thin, thawed after his fall) - and the Frostbound's content (his quest, Maera's words, the
## roster, his loot paying for the set, the set and the Rime-maul, the prompts).


func before_each() -> void:
	await super()
	GameSession.expansion = ExpansionState.defaults()


func after_each() -> void:
	GameSession.expansion = ExpansionState.defaults()
	await super()


func _player(stage := 7) -> GiantPlayer:
	var p := spawn_player(Vector3(0, 0.05, 0), 0.0)
	await TestWait.until(self, func() -> bool: return p.is_on_floor(), 30)
	var duel: Script = load("res://scripts/debug/titan_duel.gd")
	duel.call("prepare", p, stage)
	await step_ticks(2)
	return p


func _sheet(radius := 40.0, cell := 9.0) -> IceSheet:
	var s := IceSheet.new()
	s.name = "Ice"
	s.sheet_id = "test.ice"
	s.radius_m = radius
	s.cell_m = cell
	s.refreeze_s = 2.0
	world.add_child(s)
	return s


# --------------------------------------------------------------------------- the rime

func test_rime_takes_hold_by_the_giants_stage_and_slows_him() -> void:
	var p := await _player(7)
	assert_true(p.rime is PlayerRime, "the giant has the rime component")
	var took: float = p.rime.add_rime(40.0, "test")
	assert_near(took, 40.0 * PlayerRime.RIME_TAKEN_BY_STAGE[7], 0.01, "a stage-7 giant takes its stage's share")
	await step_ticks(1)
	var mult := float(p.motor.speed_mult_sources().get(&"rime", 1.0))
	assert_near(mult, 1.0 - PlayerRime.RIME_SLOW_AT_FULL * p.rime.fraction(), 0.01, "it slows him as it builds")
	assert_true(PlayerRime.RIME_TAKEN_BY_STAGE[6] > PlayerRime.RIME_TAKEN_BY_STAGE[7], "a smaller giant takes more")
	assert_true(PlayerRime.RIME_TAKEN_BY_STAGE[8] < PlayerRime.RIME_TAKEN_BY_STAGE[7], "a bigger one less")
	p.entity.combatant.passives["rime_taken_mult"] = 0.5
	assert_near(p.rime.taken_mult(), PlayerRime.RIME_TAKEN_BY_STAGE[7] * 0.5, 0.001, "the Frostbound set's ice halves it")


func test_full_rime_freezes_him_fast_and_a_heavy_shatters_it() -> void:
	var p := await _player(7)
	var frozen: Array = []
	var on_frozen := func(_t: int, id: String, s: float) -> void: frozen.append([id, s])
	Events.rime_frozen.connect(on_frozen)
	p.rime.add_rime(500.0, "test")
	Events.rime_frozen.disconnect(on_frozen)
	assert_true(p.rime.is_frozen(), "full: frozen fast")
	assert_eq(frozen.size(), 1, "Events.rime_frozen")
	assert_true(p.entity.combatant.statuses.has("status.frozen_fast"), "the frozen status (the HUD's FROZEN, the tint)")
	assert_eq(p.rime.add_rime(10.0, "test"), 0.0, "frozen, no more takes hold")
	assert_true(p.rime.handle_edge(&"dodge"), "no dodge while frozen")
	assert_true(p.rime.handle_edge(&"jump"), "no jump")
	assert_false(p.rime.handle_edge(&"heavy"), "a heavy is his own")
	p.router.inject_edge(&"heavy")
	await step_ticks(3)
	assert_false(p.rime.is_frozen(), "a heavy begun shatters the ice off him")
	assert_eq(p.rime.shatters, 1, "counted as shattered")
	assert_true(p.rime.rime <= PlayerRime.AFTER_FREEZE + 0.01, "the rime falls back after the freeze")


func test_a_freeze_thaws_by_itself_and_the_rime_falls_away_with_time() -> void:
	var p := await _player(7)
	p.rime.add_rime(500.0, "test")
	await step_ticks(int(PlayerRime.FREEZE_S * 60.0) + 2)
	assert_false(p.rime.is_frozen(), "the freeze thaws after FREEZE_S")
	var before: float = p.rime.rime
	await step_ticks(int((PlayerRime.DECAY_DELAY_S + 1.0) * 60.0))
	assert_true(p.rime.rime < before - 2.0, "it falls away with time (%.1f -> %.1f)" % [before, p.rime.rime])


func test_a_lit_fire_thaws_him_and_an_unlit_one_does_not() -> void:
	var p := await _player(7)
	WorldState.set_flag("test.d1.lit", false)
	var w := WarmthSource.new()
	w.radius_m = 20.0
	w.requires_flag = "test.d1.lit"
	w.position = Vector3(0, 0, -5)
	world.add_child(w)
	await step_ticks(1)
	p.rime.add_rime(60.0, "test")
	await step_ticks(30)
	assert_false(p.rime.warm, "an unlit fire is no fire")
	WorldState.set_flag("test.d1.lit", true)
	var before: float = p.rime.rime
	await step_ticks(30)
	assert_true(p.rime.warm, "lit: he stands in its warmth")
	assert_true(p.rime.rime < before - 10.0, "the fire thaws him fast (%.1f -> %.1f)" % [before, p.rime.rime])
	assert_true(WarmthSource.nearest(world.get_tree(), p.global_position) == w, "the nearest lit fire")


func test_a_blow_with_rime_rimes_the_giant_it_strikes() -> void:
	var p := await _player(7)
	var dummy := spawn_dummy(Vector3(0, 0.05, -6), "d1_dummy")
	await step_ticks(2)
	var e := HitEvent.new()
	e.tick = Sim.tick
	e.instance_id = Sim.new_instance_id()
	e.attacker_id = dummy.entity.entity_id
	e.target_id = p.entity.entity_id
	e.action_id = "ability.frostbound_rake"
	e.power = 20.0
	e.attacker_stat = 10.0
	e.attacker_height_m = 2.0
	e.damage_split = {"physical": 1.0}
	e.poise_damage = 1.0
	e.tags = PackedStringArray(["Melee"])
	e.attacker_position = dummy.global_position
	Sim.queue_hit(e)
	await step_ticks(3)
	assert_true(p.rime.rime > 1.0, "the rake's rime took hold (%.1f)" % p.rime.rime)


# --------------------------------------------------------------------------- the ice

func test_heavy_pulses_crack_and_break_the_ice_and_mens_blows_do_not() -> void:
	var s := _sheet()
	await step_ticks(1)
	var k := s.cell_of(Vector3(0, 0, 0))
	assert_true(k >= 0, "the middle is ice")
	assert_eq(s.state(k), IceSheet.WHOLE, "whole at first")
	Events.area_pulse.emit(Sim.tick, "test", "", Vector3(0, 0, 0), 2.0)
	assert_eq(s.state(k), IceSheet.WHOLE, "a man's blow (a small pulse) leaves it whole")
	Events.area_pulse.emit(Sim.tick, "test", "", Vector3(0, 0, 0), 6.0)
	assert_eq(s.state(k), IceSheet.CRACKED, "a stomp cracks it")
	Events.area_pulse.emit(Sim.tick, "test", "", Vector3(0, 0, 0), 6.0)
	assert_eq(s.state(k), IceSheet.OPEN, "another breaks it open")
	var far := s.cell_of(Vector3(30, 0, 0))
	assert_eq(s.state(far), IceSheet.WHOLE, "far off it holds")
	Events.area_pulse.emit(Sim.tick, "test", "ability.frostbound_nova", Vector3(30, 0, 0), 6.0)
	assert_eq(s.state(far), IceSheet.OPEN, "his nova (ice_crack 2) breaks it open at once")
	await step_ticks(int(s.refreeze_s * 60.0) + 2)
	assert_eq(s.state(k), IceSheet.CRACKED, "open water freezes over again, thin")
	assert_eq(s.state_at(Vector3(0, 30, 0)), IceSheet.NOT_ICE, "a giant's height above it is not on it")
	s.reset()
	assert_eq(s.counts().cracked + s.counts().open, 0, "a new attempt: whole again")


func test_open_water_slows_and_rimes_a_wading_giant_until_he_has_fallen() -> void:
	var p := await _player(7)
	var s := _sheet()
	s.thaw_flag = "test.d1.thawed"
	WorldState.set_flag("test.d1.thawed", false)
	await step_ticks(1)
	s.break_open(s.cell_of(p.global_position), "test")
	await step_ticks(30)
	assert_true(p.rime.wading, "he wades in the open water")
	assert_true(float(p.motor.speed_mult_sources().get(&"wading", 1.0)) < 1.0, "slowed")
	assert_true(p.rime.rime > 0.5, "the cold water rimes him")
	WorldState.set_flag("test.d1.thawed", true)
	p.rime.shed_rime(100.0, "test")
	await step_ticks(20)
	assert_false(p.rime.wading, "after his fall the water is only water")
	s.reset()
	assert_true(s.counts().open > s.counts().cracked, "thawed: open water and floes")


# --------------------------------------------------------------------------- his content

func test_his_quest_maera_and_the_roster() -> void:
	var q := GameData.get_record("quest.frostbound")
	assert_eq((q.stages as Array).map(func(st: Dictionary) -> String: return str(st.id)), ["reach", "slay", "tell"],
		"the quest: reach the Rimeglass, slay him, tell Maera")
	assert_false(GameData.get_record("quest.stormcaller_lead").is_empty(), "the Stormcaller's lead follows")
	var d := GameData.get_record("dialogue.hearth_maera")
	var ids: Array = (d.nodes as Array).map(func(n: Dictionary) -> String: return str(n.id))
	for n: String in ["frost_watch", "frost_fallen", "after_frost"]:
		assert_true(ids.has(n), "Maera's %s" % n)
	var fallen: Dictionary = (d.nodes as Array).filter(func(n: Dictionary) -> bool: return str(n.id) == "frost_fallen")[0]
	var eff: Dictionary = (fallen.choices[0] as Dictionary).effects
	assert_true(bool(eff.set_flags.get("lead.stormcaller.hearth", false)), "her lead toward the Stormcaller")
	assert_eq(str(eff.outcome), "frost_fallen", "her outcome")
	var r := ExpansionState.roster_entry("titan.frostbound")
	assert_eq(str(r.enemy), "enemy.frostbound", "the roster's fifth titan is in the game")
	assert_eq(str(r.defeated_flag), "boss.frostbound.defeated", "his defeated flag")
	assert_eq(str(r.sighted_poi), "poi.rimeglass", "his lair")


func test_one_fall_with_two_plates_broken_pays_for_the_set() -> void:
	var counts := {}
	for g: Dictionary in GameData.get_record("loot.frostbound").guaranteed:
		counts[str(g.item)] = int(counts.get(str(g.item), 0)) + int(g.count)
	for pl: Dictionary in GameData.get_record("enemy.frostbound").plates:
		if str(pl.id) in ["crown", "greave_l"]:
			for l: Dictionary in pl.get("loot", []):
				counts[str(l.item)] = int(counts.get(str(l.item), 0)) + int(l.count)
	var need := {}
	var set_rec := GameData.get_record("armour_set.frostbound")
	for piece: String in set_rec.pieces:
		var rec := GameData.get_record("recipe." + piece.trim_prefix("armour."))
		assert_eq(str(rec.works), "frost_ice", "%s is worked at Last Hearth's forge (frost_ice)" % piece)
		assert_eq(str(rec.requires_flag), "boss.frostbound.defeated", "%s once he has fallen" % piece)
		for c: Dictionary in rec.cost:
			need[str(c.item)] = int(need.get(str(c.item), 0)) + int(c.count)
	for item: String in ["item.hoarfrost_shard", "item.cairn_capstone", "item.frostbound_heart"]:
		assert_true(int(counts.get(item, 0)) >= int(need.get(item, 0)), "%s: %d from one fall, %d for the set" % [
			item, int(counts.get(item, 0)), int(need.get(item, 0))])
	assert_eq((set_rec.pieces as Array).size(), 7, "seven pieces")
	var two: Dictionary = (set_rec.bonuses as Array)[0]
	assert_near(float(two.modifiers.rime_taken_mult), 0.75, 0.001, "two pieces: the rime takes a quarter less hold")
	var maul := GameData.get_record("weapon.rime_maul")
	assert_eq(str(maul.perk.kind), "chill", "the Rime-maul's heavies chill")
	for forge_id: String in ["world.hoarfell.hearth_forge", "world.hoarfell.colossus_anvil"]:
		var el := _layout_element(forge_id)
		assert_true((el.get("works", []) as Array).has("frost_ice"), "%s works his ice" % forge_id)


func test_the_rime_maul_chills_what_its_heavy_strikes() -> void:
	var perk: Dictionary = GameData.get_record("weapon.rime_maul").perk
	var heavy := GameData.get_action("ability.hammer_heavy")
	var e := HitEvent.new()
	AttackRunner.p31_apply_perk(perk, e, null)
	assert_eq(e.on_hit_statuses.size(), 1, "the chill rides the hit")
	assert_eq(str((e.on_hit_statuses[0] as Dictionary).status), "status.slow", "a slow")
	assert_true(heavy != null and heavy.has_tag("Heavy"), "on a heavy")


static func _layout_element(id: String) -> Dictionary:
	var t := WorldFeatures.load_json("res://tools/data/world/hoarfell.json")
	for el: Dictionary in t.get("elements", []):
		if str(el.get("id", "")) == id:
			return el
	return {}


# --------------------------------------------------------------------------- saves

## D1: a 0.16.0-m16 save (tests/fixtures/saves/v3_m16_d1_frost_lead.json: written by hand from the schema, derived from
## the C4 Web fixture - Last Hearth at tier 3, grown to stage 7, Maera's lead heard and looked at, at the Colossus
## Steps' waystone - from before the Frostbound was in the game) and the 0.15 and C4 saves load (schema 3, no new key),
## meet him unseen, start his quest from the lead and record his fall.
func test_older_saves_meet_him_and_record_his_fall() -> void:
	for f: String in ["v3_m15_campaign_complete.json", "v3_m16_c4_last_hearth.json", "v3_m16_d1_frost_lead.json"]:
		var doc := SaveSlots.migrate(JsonIO.read_file("res://tests/fixtures/saves/" + f).data)
		assert_eq(SaveSlots.validate(doc), PackedStringArray(), "%s validates" % f)
		assert_eq(int(doc.schema_version), 3, "%s: schema 3" % f)
		var x := ExpansionState.from_doc(doc)
		assert_eq(str(((x.get("titans", {}) as Dictionary).get("titan.frostbound", {}) as Dictionary).get("state",
			ExpansionState.STATE_UNSEEN)), ExpansionState.STATE_UNSEEN, "%s: the Frostbound unseen" % f)
	var d1 := SaveSlots.migrate(JsonIO.read_file("res://tests/fixtures/saves/v3_m16_d1_frost_lead.json").data)
	assert_eq(str(d1.build_version), "0.16.0-m16", "a 0.16 save")
	var flags: Dictionary = (d1.world.flags as Dictionary).duplicate(true)
	var ctx := QuestConditions.empty_context()
	ctx.flags = flags
	assert_true(QuestConditions.all_hold(GameData.get_record("quest.frostbound").start_conditions, ctx),
		"its lead starts the Frostbound's quest")
	assert_true(int(d1.character.growth_stage) >= 7, "a colossus: the Colossus Steps are open to him")
	var x := ExpansionState.from_doc(d1)
	flags["boss.frostbound.defeated"] = true
	flags["boss.frostbound.outcome"] = "slain"
	ExpansionState.sync_from_flags(x, flags)
	assert_eq(str((x.titans["titan.frostbound"] as Dictionary).state), ExpansionState.STATE_SLAIN, "his fall recorded")
	assert_true(bool(((x.settlements["poi.last_hearth"] as Dictionary).flags as Dictionary).get("frostbound_fallen", false)),
		"Last Hearth's record learns it")
