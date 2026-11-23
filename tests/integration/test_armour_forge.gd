extends IntegrationSuite
## B1: the forge makes armour and a titan weapon, refits a piece and sets its perk; the Character menu's rule puts it
## on and takes it off; worn armour changes the giant's own numbers (a real hit resolved on its combatant, its
## stamina recovery, its poise) and its look (the Quarry set's modelled stone drawn, the record untouched), and the
## state goes through a checkpoint document and SaveSlots and back. Titan stone only at a forge that works it, and
## only once the quarry has reopened; a fight blocks putting armour on.

const FORGE := "res://scenes/world/forge.tscn"


func before_each() -> void:
	await super()
	GameSession.expansion = ExpansionState.defaults()
	WorldState.clear()


func after_each() -> void:
	GameSession.expansion = ExpansionState.defaults()
	SaveSlots.delete_slot(true)
	GameSession.persist = false
	WorldState.clear()
	await super()


func _forge(works := PackedStringArray()) -> Forge:
	var f := (load(FORGE) as PackedScene).instantiate() as Forge
	f.world_id = "test.b1_forge"
	f.works = works
	f.position = Vector3(10, 0, 0)
	world.add_child(f)
	return f


func _player() -> GiantPlayer:
	var p := spawn_player(Vector3(0, 0.05, 0))
	await step_ticks(1)
	return p


func test_an_iron_forge_makes_the_iron_and_hide_sets_and_refuses_titan_stone() -> void:
	var p := await _player()
	var f := _forge()
	await step_ticks(1)
	var refused := f.can_craft(p, "recipe.iron_nasal_helm")
	assert_false(refused.ok, "without iron")
	assert_eq(str(refused.reason), "missing_items", "it says what is missing: %s" % refused.message)
	WorldState.add_item("item.iron_ingot", 2, "test")
	var made := f.craft(p, "recipe.iron_nasal_helm")
	assert_true(made.ok, "two ingots make the helm: %s" % made.message)
	assert_eq(WorldState.count_of("item.iron_ingot"), 0, "they are paid")
	assert_true(Armour.owns(GameSession.expansion.equipment, "armour.iron_nasal_helm"), "the helm is owned")
	assert_eq(str(GameSession.expansion.equipment.slots.head), "", "not worn: the Character menu puts it on")
	assert_eq(str(f.can_craft(p, "recipe.iron_nasal_helm").reason), "owned", "made once")
	WorldState.add_item("item.stoneback_slab", 9, "test")
	WorldState.add_item("item.quarry_iron", 9, "test")
	var stone := f.can_craft(p, "recipe.quarry_pauldrons")
	assert_eq(str(stone.reason), "works", "titan stone needs a forge that works it: %s" % stone.message)
	assert_true(str(stone.message).contains("Millford"), "and says where")
	var rows := f.recipes(p, "armour")
	assert_eq(rows.size(), 19, "the armour tab lists every piece's recipe (B2: the Kingsfall set's four; B3: the Warden set's four)")


func test_millfords_forge_works_titan_stone_once_the_quarry_reopens() -> void:
	var p := await _player()
	var f := _forge(PackedStringArray(["titan_stone"]))
	await step_ticks(1)
	WorldState.add_item("item.stoneback_slab", 12, "test")
	WorldState.add_item("item.quarry_iron", 8, "test")
	WorldState.add_item("item.stoneback_heart_stone", 1, "test")
	WorldState.add_item("item.iron_ingot", 6, "test")
	assert_eq(str(f.can_craft(p, "recipe.quarry_pauldrons").reason), "locked", "not before the quarry reopens")
	WorldState.try_set_flag("world.quarry.reopened", true)
	for r: String in ["recipe.quarry_pauldrons", "recipe.quarry_bracers", "recipe.quarry_greaves", "recipe.quarry_heart_stone"]:
		assert_true(f.craft(p, r).ok, "%s made" % r)
	var maul := f.craft(p, "recipe.quarry_maul")
	assert_true(maul.ok, "the Quarry Maul: %s" % maul.message)
	assert_eq(p.equipment.weapon_id(), "weapon.quarry_maul", "forged and taken in hand")
	assert_eq(str(p.controller.loadout.get("heavy", "")), "ability.quarry_smash", "its heavy is the Quarry Smash")
	# refit to tier 2 and a perk
	var refit := f.refit(p, "armour.quarry_pauldrons")
	assert_true(refit.ok, "tier 2: %s" % refit.message)
	assert_eq(Armour.tier_of(GameSession.expansion.equipment, "armour.quarry_pauldrons"), 2, "the tier kept")
	var perk := f.set_perk(p, "armour.quarry_pauldrons", "armour_perk.steady")
	assert_true(perk.ok, "Steady set: %s" % perk.message)
	assert_eq(str(f.set_perk(p, "armour.quarry_pauldrons", "armour_perk.steady").reason), "same_perk", "not twice")
	assert_eq(str(f.set_perk(p, "armour.quarry_pauldrons", "armour_perk.light_step").reason), "no_perk",
		"only its own list's")


func test_worn_armour_changes_the_numbers_and_the_look() -> void:
	var p := await _player()
	var c := p.entity.combatant
	var armour0 := c.armor_total()
	var poise0 := c.poise_threshold_add()
	var look0: Dictionary = p.appearance.look()
	var record0: Dictionary = p.appearance.record()
	var eq: Dictionary = GameSession.expansion.equipment
	for id: Variant in Armour.set_pieces("armour_set.quarry"):
		Armour.grant(eq, str(id))
		var r := CharacterScreen.apply_option(p, str(Armour.piece(str(id)).slot), str(id))
		assert_true(r.ok, "%s put on: %s" % [id, r.message])
	assert_true(c.armor_total() > armour0 + 25.0, "the Quarry set's armour on the combatant (%.1f)" % c.armor_total())
	assert_true(c.poise_threshold_add() > poise0, "and its poise")
	assert_true(c.modifier("stamina_regen_mult") < 1.0, "its weight slows stamina recovery")
	# a real hit on the giant: about a fifth less
	var hit := HitEvent.new()
	hit.power = 300.0
	hit.attacker_stat = 0.0
	hit.size_policy = "none"
	hit.tags = PackedStringArray(["Melee"])
	var bare := Combatant.from_record("b", GameData.get_record("player.giant"), c.height_m)
	var less := 1.0 - float(DamageResolver.mitigate(hit, c).total) / float(DamageResolver.mitigate(hit, bare).total)
	assert_true(less >= 0.20 and less <= 0.26, "a blow lands %.0f%% lighter" % (less * 100.0))
	var look: Dictionary = p.appearance.look()
	assert_true((look.accessories as Array).has("Armour_quarry_pauldrons"), "the stone is drawn")
	assert_eq(p.appearance.record(), record0, "the look's record is untouched")
	# hidden: still counts, not drawn
	CharacterScreen._equipment()
	Armour.set_hidden(eq, "shoulders", true)
	Armour.refresh_player(p)
	assert_false((p.appearance.look().accessories as Array).has("Armour_quarry_pauldrons"), "hidden: not drawn")
	assert_true(c.armor_total() > armour0 + 25.0, "but still counts")
	# off again
	for s: String in Armour.SLOTS:
		CharacterScreen.apply_option(p, s, "-")
	assert_eq(c.armor_total(), armour0, "all off: the armour as before")
	assert_eq(p.appearance.look(), look0, "and the look")


func test_a_fight_blocks_putting_armour_on() -> void:
	var p := await _player()
	var eq: Dictionary = GameSession.expansion.equipment
	Armour.grant(eq, "armour.iron_hauberk")
	var soldier := spawn_soldier(Vector3(6, 0.05, 0), 0.0, "soldier_b1", true)
	await step_ticks(2)
	soldier.brain.aware = true
	var r := CharacterScreen.apply_option(p, "chest", "armour.iron_hauberk")
	assert_false(r.ok, "an enemy hunting the giant: refused")
	assert_eq(str(r.message), Armour.BLOCK_FIGHT, "and says why")
	assert_eq(str(eq.slots.chest), "", "nothing changed")


func test_the_equipment_goes_through_a_checkpoint_and_back() -> void:
	var p := await _player()
	var eq: Dictionary = GameSession.expansion.equipment
	for id: String in ["armour.iron_hauberk", "armour.hide_bracers", "armour.quarry_heart_stone"]:
		Armour.grant(eq, id)
		Armour.equip(eq, id)
	Armour.set_tier(eq, "armour.iron_hauberk", 3)
	Armour.set_perk(eq, "armour.hide_bracers", "armour_perk.heavy_hand")
	Armour.set_hidden(eq, "trinket", true)
	Armour.grant(eq, "armour.iron_greaves")
	var want: Dictionary = eq.duplicate(true)
	var snap := GameSession.snapshot_document("test_b1")
	assert_eq(int(snap.schema_version), 3, "still save schema 3 (its reserved block holds it)")
	assert_eq(SaveSlots.validate(snap), PackedStringArray(), "the document validates")
	GameSession.persist = true
	assert_true(SaveSlots.write(snap).ok, "written")
	var back := SaveSlots.read()
	assert_true(back.ok, "read back")
	assert_eq(ExpansionState.from_doc(back.data).equipment, want, "every piece, tier, perk, worn slot and hidden slot")
	GameSession.expansion = ExpansionState.defaults()
	p.progression.rebuild_passives()
	var bare := p.entity.combatant.armor_total()
	GameSession.expansion = ExpansionState.from_doc(back.data)
	Armour.refresh_player(p)
	assert_true(p.entity.combatant.armor_total() > bare, "loaded, the giant wears it again")
