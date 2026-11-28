extends TestSuite
## B1: functional armour's rules (Armour, pure; docs/systems/B1.md) and its records: the three sets validate and each
## piece is in its set's list in its own slot; an unarmoured giant's passives are empty (every pinned number holds);
## a full Iron set turns 10-15 % of a physical blow and a full Quarry set 20-25 %, at every stage alike (a share, not a
## number); weight slows stamina recovery past what the frame carries; tiers scale defence and poise; the set bonuses
## and a chosen perk; the saved state normalised (an unknown piece, a perk not on its list, a worn piece of another
## slot); the look drawn over the creator's record without changing it (hidden pieces still count); the forge's
## recipes and the titan stone's trait; Stoneback's broken plates' loot; a titan's sight over the ground; the warning
## prompts' unless_flags and the plated lock filter.

const SETS := ["armour_set.bastion", "armour_set.cinder", "armour_set.fetterer", "armour_set.frostbound", "armour_set.hide",
	"armour_set.hollow", "armour_set.iron", "armour_set.kingsfall", "armour_set.quarry", "armour_set.stormcaller", "armour_set.warden"]   # B2: Kingsfall; B3: the Warden set; C2: the Bastion set; D1: the Frostbound set; D2: the Stormcaller set; E1: the Fetterer's set; E2: the Cinder set; E3: the Oathbound set


func _set_eq(set_id: String) -> Dictionary:
	return Armour.equipment_with(Armour.set_pieces(set_id))


func _less_pct(eq: Dictionary) -> float:
	return float(Armour.stats(eq).less_pct)


func test_the_records_and_their_sets() -> void:
	assert_eq(Array(Armour.set_ids()), SETS, "the eleven sets (B2: the Kingsfall set; B3: the Warden set; C2: the Bastion set; D1: the Frostbound set; D2: the Stormcaller set; E1: the Fetterer's set; E2: the Cinder set; E3: the Oathbound set)")
	var slots := {}
	for sid: String in SETS:
		var srec := Armour.set_record(sid)
		assert_true((srec.get("refit", []) as Array).size() == 2, "%s: two refit steps (tiers 2 and 3)" % sid)
		for id: Variant in Armour.set_pieces(sid):
			var rec := Armour.piece(str(id))
			assert_false(rec.is_empty(), "%s: %s is an armour record" % [sid, id])
			assert_eq(str(rec.get("set", "")), sid, "%s names its set" % id)
			assert_true(Armour.SLOTS.has(str(rec.slot)), "%s: one of the seven slots" % id)
			assert_true((rec.get("perks", []) as Array).size() >= 2, "%s: an authored list of perks to choose from" % id)
			for p: Variant in rec.perks:
				assert_false(Armour.perk(str(p)).is_empty(), "%s: its perk %s is a record" % [id, p])
			slots[str(rec.slot)] = true
			var made := false
			for r: Dictionary in GameData.records_of_type("recipe"):
				made = made or str(r.get("makes", "")) == str(id)
			assert_true(made, "%s: a forge's recipe makes it" % id)
	assert_eq(slots.size(), 7, "the sets cover every slot: %s" % [slots.keys()])
	assert_eq(Armour.SLOTS, ExpansionState.ARMOUR_SLOTS, "the slots schema 3 reserved")


func test_unarmoured_changes_nothing() -> void:
	var m := Armour.modifiers(Armour.empty())
	assert_eq(m, {"modifiers": {}, "resistances": {}}, "no armour: no passive at all (every pinned number holds)")
	var c := Combatant.from_record("t", GameData.get_record("player.giant"))
	var before := [c.armor_total(), c.pools.stamina_max, c.poise_threshold_add(), c.modifier("stamina_regen_mult")]
	c.set_passives({}, {})
	assert_eq([c.armor_total(), c.pools.stamina_max, c.poise_threshold_add(), c.modifier("stamina_regen_mult")], before,
		"empty passives leave the combatant as it was")


func test_the_sets_turn_their_share_of_a_blow() -> void:
	var iron := _less_pct(_set_eq("armour_set.iron"))
	var quarry := _less_pct(_set_eq("armour_set.quarry"))
	var hide := _less_pct(_set_eq("armour_set.hide"))
	assert_true(iron >= 10.0 and iron <= 15.0, "a full Iron set: 10-15 %% less damage (%.1f)" % iron)
	assert_true(quarry >= 20.0 and quarry <= 25.0, "a full Quarry set: 20-25 %% less damage (%.1f)" % quarry)
	assert_true(hide > 0.0 and hide < iron, "the Hide set is lighter (%.1f)" % hide)
	# the resolver's own numbers: a stage-1 blow and a stage-6 blow lose the same share
	for stage_h: float in [3.6576, 18.9]:
		var hit := HitEvent.new()
		hit.power = 200.0
		hit.attacker_stat = 0.0
		hit.size_policy = "none"
		hit.attacker_height_m = stage_h
		hit.tags = PackedStringArray(["Melee"])
		var bare := Combatant.from_record("t", GameData.get_record("player.giant"), stage_h)
		var worn := Combatant.from_record("t", GameData.get_record("player.giant"), stage_h)
		var m := Armour.modifiers(_set_eq("armour_set.quarry"))
		worn.set_passives(m.modifiers, m.resistances)
		var b := float(DamageResolver.mitigate(hit, bare).total)
		var a := float(DamageResolver.mitigate(hit, worn).total)
		assert_near(1.0 - a / b, quarry / 100.0, 0.001, "at %.1f m the Quarry set turns the same share" % stage_h)


func test_weight_and_stamina() -> void:
	var q := Armour.modifiers(_set_eq("armour_set.quarry")).modifiers as Dictionary
	var w := Armour.weight(_set_eq("armour_set.quarry"))
	assert_near(float(q.get("stamina_regen_mult", 1.0)), Armour.weight_mult(w), 0.0001, "the Quarry set's weight slows recovery")
	assert_true(Armour.weight_mult(w) < 0.95 and Armour.weight_mult(w) >= 1.0 - Armour.WEIGHT_MAX_SLOW, "modestly (%.2f)" % Armour.weight_mult(w))
	var h := Armour.modifiers(_set_eq("armour_set.hide")).modifiers as Dictionary
	assert_true(float(h.get("stamina_regen_mult", 1.0)) > 1.0, "the full Hide set recovers faster (its bonus)")
	assert_eq(Armour.weight_mult(Armour.WEIGHT_FREE), 1.0, "a frame carries WEIGHT_FREE at no cost")
	# the pools recover by it
	var c := Combatant.from_record("t", GameData.get_record("player.giant"))
	c.set_passives({"stamina_regen_mult": 0.5}, {})
	c.pools.stamina = 0.0
	c.pools.since_stamina_spend = 99.0
	c.pools.tick(1.0, true)
	assert_near(c.pools.stamina, c.pools.stamina_regen_per_s * 0.5, 0.001, "half the recovery a second")


func test_tiers_bonuses_and_perks() -> void:
	var eq := Armour.equipment_with(["armour.quarry_pauldrons"])
	var a1 := float((Armour.modifiers(eq).modifiers as Dictionary).armor_flat)
	Armour.set_tier(eq, "armour.quarry_pauldrons", 3)
	var a3 := float((Armour.modifiers(eq).modifiers as Dictionary).armor_flat)
	assert_near(a3 / a1, Armour.TIER_MULT[2], 0.0001, "tier 3 scales the defence")
	assert_eq(Armour.piece_name("armour.quarry_pauldrons", 3), "Masterwork Quarry Pauldrons", "and names it")
	var two := Armour.equipment_with(["armour.quarry_pauldrons", "armour.quarry_greaves"])
	var bon := Armour.bonuses(two)
	assert_true(bon.any(func(b: Dictionary) -> bool: return int(b.pieces) == 2 and bool(b.active)), "two pieces: the 2-piece bonus")
	assert_true(bon.any(func(b: Dictionary) -> bool: return int(b.pieces) == 4 and not bool(b.active)), "not yet the 4-piece")
	assert_false(Armour.set_perk(two, "armour.quarry_pauldrons", "armour_perk.light_step"), "a perk not on its list is refused")
	assert_true(Armour.set_perk(two, "armour.quarry_pauldrons", "armour_perk.steady"), "one of its own is set")
	var with_perk := float((Armour.modifiers(two).modifiers as Dictionary).poise_threshold_add)
	Armour.set_perk(two, "armour.quarry_pauldrons", "")
	var without := float((Armour.modifiers(two).modifiers as Dictionary).poise_threshold_add)
	assert_near(with_perk - without, 12.0, 0.001, "Steady: poise +12")
	assert_false(Armour.next_refit(two, "armour.quarry_pauldrons").is_empty(), "a refit step to tier 2")
	assert_eq(str(Armour.next_refit(two, "armour.quarry_pauldrons").works), "titan_stone", "worked at a titan-stone forge")


func test_the_saved_state_is_normalised() -> void:
	var raw := {"slots": {"head": "armour.quarry_pauldrons", "shoulders": "armour.no_such", "legs": "armour.iron_greaves",
		"tail": "x"}, "pieces": {"armour.iron_greaves": {"tier": 9, "perk": "armour_perk.hale"}, "armour.gone": {"tier": 1}},
		"hidden": {"legs": true, "nose": true}}
	var n := Armour.normalized(raw)
	assert_eq(n.slots.head, "", "a piece of another slot comes off")
	assert_eq(n.slots.shoulders, "", "an unknown piece comes off")
	assert_eq(n.slots.legs, "armour.iron_greaves", "a good one stays")
	assert_eq(n.pieces["armour.iron_greaves"], {"tier": 3, "perk": ""}, "its tier clamped, a perk not on its list dropped")
	assert_false((n.pieces as Dictionary).has("armour.gone"), "an unknown piece owned goes")
	assert_eq(n.hidden, {"legs": true}, "only the seven slots hide")
	# schema 3's document: the block round-trips, an unknown id reported
	var st := ExpansionState.defaults()
	st.equipment = Armour.equipment_with(["armour.iron_hauberk"], ["chest"])
	Armour.set_tier(st.equipment, "armour.iron_hauberk", 2)
	var doc := ExpansionState.write_into({}, st)
	var back := ExpansionState.from_doc(JSON.parse_string(JSON.stringify(doc)))
	assert_eq(back.equipment, st.equipment, "the equipment block round-trips through JSON")
	assert_eq(ExpansionState.validate(doc), PackedStringArray(), "and validates")
	back.equipment.pieces["armour.later"] = {"tier": 1, "perk": ""}
	assert_true(ExpansionState.sanitize(back).has("armour.later"), "a later build's piece is dropped and named")
	# an A-milestone document (slots only) still loads: the new keys are optional within schema 3
	var old := ExpansionState.from_doc({"equipment": {"slots": {"head": ""}}})
	assert_eq(old.equipment.pieces, {}, "a schema-3 file from before B1: nothing owned")


func test_the_look_is_drawn_over_the_record() -> void:
	var rec := Appearance.default_record()
	var frozen := rec.duplicate(true)
	var eq := Armour.equipment_with(Armour.set_pieces("armour_set.iron"))
	var dressed := Armour.dress(rec, eq)
	assert_eq(rec, frozen, "the creator's record is not changed")
	assert_eq(str(dressed.outfit.slots.head.item), "garment.nasal_helm", "the helm in the head slot")
	assert_eq(str(dressed.outfit.slots.armour.item), "garment.mail_hauberk", "the hauberk in the cosmetic armour slot")
	assert_eq(str(dressed.outfit.slots.armour.dye), "metal.iron", "in the piece's own dye")
	Armour.set_hidden(eq, "head", true)
	assert_eq(str(Armour.dress(rec, eq).outfit.slots.head.item), str(rec.outfit.slots.head.item), "hidden: the giant's own head")
	assert_near(_less_pct(eq), _less_pct(Armour.equipment_with(Armour.set_pieces("armour_set.iron"))), 0.0001,
		"a hidden piece still counts")
	var q := Armour.equipment_with(Armour.set_pieces("armour_set.quarry"))
	var look := Armour.look_of(rec, q)
	for m: String in ["Armour_quarry_pauldrons", "Armour_quarry_bracers", "Armour_quarry_greaves", "Armour_quarry_heart_stone"]:
		assert_true((look.accessories as Array).has(m), "the Quarry set's modelled %s drawn" % m)
	assert_eq(str(Armour.dress(rec, q).outfit.slots.shoulders.item), "", "the shoulders' own garment cleared under the slabs")
	# the hooded mantle's hood gives way to a worn helm
	var mix := Armour.equipment_with(["armour.hide_hooded_mantle", "armour.iron_nasal_helm"])
	var dm := Armour.dress(rec, mix)
	assert_eq(str(dm.outfit.slots.head.item), "garment.nasal_helm", "the helm's own slot wins")
	assert_eq(str(dm.outfit.slots.shoulders.item), "garment.hide_mantle", "the mantle stays")


func test_recipes_and_the_titan_stone() -> void:
	var titan := 0
	for r: Dictionary in GameData.records_of_type("recipe"):
		var made := GameData.get_record(str(r.makes))
		assert_false(made.is_empty(), "%s makes a record" % r.id)
		if str(r.get("works", "")) == "titan_stone":
			titan += 1
			assert_eq(str(r.get("requires_flag", "")), "world.quarry.reopened", "%s waits for the quarry" % r.id)
	assert_eq(titan, 5, "the Quarry set's four pieces and the Quarry Maul work titan stone")
	var maul := GameData.get_record("weapon.quarry_maul")
	assert_eq(str(maul.get("heavy", "")), "ability.quarry_smash", "the maul's heavy is his smash")
	assert_eq(str((maul.stage_movesets["4"] as Dictionary).heavy), "ability.quarry_great_smash", "and a giant's from stage 4")


func test_stonebacks_broken_plates_add_loot() -> void:
	var rec := GameData.get_record("enemy.stoneback")
	assert_eq(PlateRules.break_loot(rec, []), [], "no plate broken: nothing more")
	var some := PlateRules.break_loot(rec, ["shin_l", "shin_r", "brow", "back"])
	assert_eq(some, [{"item": "item.stoneback_slab", "count": 3}, {"item": "item.quarry_iron", "count": 1}],
		"a slab a stone plate, the brow's quarry iron")
	var all_plates: Array = []
	for p: Dictionary in rec.plates:
		if bool(p.get("breakable", false)):
			all_plates.append(str(p.id))
	assert_eq(PlateRules.break_loot(rec, all_plates)[0], {"item": "item.stoneback_slab", "count": 7}, "seven slabs at most")


func test_a_titan_sees_over_the_ground_only() -> void:
	var flat := func(_p: Vector3) -> float: return 0.0
	var hill := func(p: Vector3) -> float: return 30.0 if p.x > 40.0 and p.x < 60.0 else 0.0
	var eye := Vector3(0, 15, 0)
	assert_true(TitanTerritory.sight_clear(eye, Vector3(100, 4, 0), flat), "open ground: seen")
	assert_false(TitanTerritory.sight_clear(eye, Vector3(100, 4, 0), hill), "a hill between: hidden")
	assert_true(TitanTerritory.sight_clear(eye, Vector3(100, 60, 0), hill), "a giant tall over the hill: seen")
	var unloaded := func(_p: Vector3) -> float: return NAN
	assert_true(TitanTerritory.sight_clear(eye, Vector3(100, 4, 0), unloaded), "nothing loaded: no obstacle")


func test_the_warning_and_plate_prompts() -> void:
	var ctx := {"flags": {}, "stage": 3}
	var warn := GameData.get_record("tutorial.stoneback_warning_south")
	var td := TutorialDirector.new()
	assert_true(td.eligible(warn, ctx), "the warning shows while he lives")
	ctx.flags["boss.stoneback.defeated"] = true
	assert_false(td.eligible(warn, ctx), "never after his death (unless_flags)")
	var plates := GameData.get_record("tutorial.titan_plates")
	assert_true(TutorialDirector.event_matches(plates.trigger, "lock_target_changed",
		{"actor": "player", "target": "t", "plated": true}), "a plated lock triggers the hint")
	assert_false(TutorialDirector.event_matches(plates.trigger, "lock_target_changed",
		{"actor": "player", "target": "w", "plated": false}), "a wolf does not")
