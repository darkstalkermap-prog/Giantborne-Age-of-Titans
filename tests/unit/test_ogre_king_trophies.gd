extends TestSuite
## B2: the Ogre King as a signature titan - his record's trophies (PlateRules: their regions, their health, a quarter
## to two fifths of a blow kept and none of its poise), the new "unbalance" break (the crown: every later blow's poise
## x1.6 for the attempt, PlateSet.poise_taken_mult, reset by a new attempt), the keg's topple, the bell's weak point,
## the trophies' own break cues, the loot (his titan parts, a broken trophy's own), the roster's record and the
## save's sync from the defeated flag (old saves mid-Valley or past it), the Kingsfall set's records and recipes at a
## forge that works the King's trophies once he has fallen, his intro cutscene and the prompts that teach the
## trophies, the corpse kept as a landmark. Pure: records and rules (docs/systems/B2.md).

const KING := "enemy.ogre_king"


func _plate(id: String) -> Dictionary:
	for p: Dictionary in PlateRules.parse(GameData.get_record(KING)):
		if str(p.id) == id:
			return p
	return {}


func test_his_trophies_are_plates_of_wood_and_iron() -> void:
	var rec := GameData.get_record(KING)
	var ids: Array = []
	for p: Dictionary in PlateRules.parse(rec):
		ids.append(str(p.id))
		assert_true(bool(p.breakable), "%s breaks" % p.id)
		assert_true(str(p.piece).begins_with("trophy_"), "%s: a trophy's mesh" % p.id)
		assert_true(float(p.reduction) >= 0.2 and float(p.reduction) <= 0.4,
			"%s keeps a quarter to two fifths of a blow (a depth, not a wall): %.2f" % [p.id, p.reduction])
		assert_eq(float(p.poise_reduction), 0.0, "%s keeps none of a blow's poise" % p.id)
		assert_true(str(p.cue) != "", "%s: its own break cue" % p.id)
	assert_eq(ids, ["crown", "bell", "wheel_l", "wheel_r", "keg"], "the five trophies")
	assert_true(PlateRules.errors(rec, "enemy.ogre_king").is_empty(), "the plates validate")
	assert_eq(str(_plate("crown").region), "head", "the crown on his head")
	assert_eq(str(_plate("bell").region), "belly", "the bell over his belly")
	assert_eq(str(_plate("keg").region), "back", "the keg on his back")
	assert_eq(str(_plate("crown").effect), PlateRules.EFFECT_UNBALANCE, "the crown unbalances him")
	assert_eq(float(_plate("crown").poise_mult), 1.6, "x1.6 poise after")
	assert_eq(str(_plate("keg").effect), PlateRules.EFFECT_TOPPLE, "the keg drops him to a knee")
	assert_eq(float(_plate("keg").again_damage), 0.0, "once only")
	assert_false(PlateRules.parse_topple(rec).is_empty(), "his topple block")
	assert_eq(int(rec.get("growth_stage", 0)), 3, "he tramples as a stage-3 giant")
	assert_eq(float(rec.height_m), 8.5, "P11a's 8.5 m kept (his fight's reach)")
	assert_eq(int(rec.health), 1500, "the spec's 1,500 health kept")


func test_the_unbalance_break_multiplies_every_later_blows_poise() -> void:
	var ps := PlateSet.from_record(GameData.get_record(KING))
	var hit := HitEvent.new()
	hit.region = "legs"
	ps.prepare(hit)
	assert_eq(hit.region_poise_mult, 1.0, "an unplated region: full poise")
	ps.poise_taken_mult = 1.6
	ps.prepare(hit)
	assert_near(hit.region_poise_mult, 1.6, 1e-6, "unbalanced: every blow's poise x1.6")
	var on_bell := HitEvent.new()
	on_bell.region = "belly"
	ps.prepare(on_bell)
	assert_near(on_bell.region_poise_mult, 1.6, 1e-6, "an intact trophy keeps no poise")
	assert_near(on_bell.region_damage_mult, 0.7, 1e-6, "an intact bell keeps 30 % of the blow")
	ps.reset()
	assert_eq(ps.poise_taken_mult, 1.0, "a new attempt: balanced again")
	ps.force_break("bell")
	ps.prepare(on_bell)
	assert_near(on_bell.region_damage_mult, 1.5, 1e-6, "the bell broken: his belly a weak point x1.5")


func test_an_unbalance_plate_needs_its_multiplier() -> void:
	var rec := {"plates": [{"id": "x", "region": "head", "health": 10, "reduction": 0.3,
		"on_break": {"effect": "unbalance"}}]}
	assert_false(PlateRules.errors(rec, "t").is_empty(), "unbalance without poise_mult above 1 is refused")
	rec.plates[0].on_break["poise_mult"] = 1.5
	assert_true(PlateRules.errors(rec, "t").is_empty(), "with it: valid")


func test_the_trophies_splinter_with_their_own_sounds() -> void:
	assert_eq(PlateRules.trophy_cues(_plate("bell")), ["sfx.break.trophy.bell"], "the bell: its cracked toll alone")
	assert_eq(PlateRules.trophy_cues(_plate("crown")), ["sfx.break.trophy.iron", "sfx.break.wood.large"],
		"the crown: its iron and the shields' wood")
	assert_eq(PlateRules.trophy_cues(_plate("wheel_l")), ["sfx.break.wood.large"], "a wheel: wood")
	assert_eq(PlateRules.trophy_cues(_plate("keg")), ["sfx.break.trophy.keg", "sfx.break.wood.large"],
		"the keg: its burst and its staves")
	for p: Dictionary in PlateRules.parse(GameData.get_record("enemy.stoneback")):
		if bool(p.breakable):
			assert_eq(PlateRules.trophy_cues(p), ["sfx.break.stone.large"], "Stoneback's %s: stone, as before" % p.id)
	for cue: String in ["sfx.break.trophy.bell", "sfx.break.trophy.iron", "sfx.break.trophy.keg"]:
		var found := false
		for b: Dictionary in GameData.records_of_type("audio_bank"):
			found = found or (b.get("cues", {}) as Dictionary).has(cue)
		assert_true(found, "%s is a bank cue" % cue)


func test_his_loot_is_his_titan_parts() -> void:
	var drops := ExpansionState.loot_of("loot.ogre_king")
	var by := {}
	for d: Dictionary in drops:
		by[str(d.item)] = int(d.count)
	assert_eq(int(by.get("item.ogre_hide", 0)), 4, "four cuts of his hide")
	assert_eq(int(by.get("item.ogre_crown_iron", 0)), 1, "his crown's iron")
	assert_eq(int(by.get("item.kings_bell_bronze", 0)), 1, "the bell's bronze")
	assert_eq(int(by.get("item.ogre_tusk", 0)), 1, "the tusk, as before")
	for id: String in ["item.ogre_hide", "item.ogre_crown_iron", "item.kings_bell_bronze"]:
		assert_false(GameData.get_record(id).is_empty(), "%s is an item" % id)
	var extra := PlateRules.break_loot(GameData.get_record(KING), ["crown", "bell", "wheel_l"])
	assert_eq(extra, [{"item": "item.ogre_crown_iron", "count": 1}, {"item": "item.kings_bell_bronze", "count": 1},
		{"item": "item.wood_scrap", "count": 2}], "each trophy broken in the fight adds its own")


func test_the_roster_and_the_save_know_him() -> void:
	var e := ExpansionState.roster_entry("titan.ogre_king")
	assert_eq(str(e.get("enemy", "")), KING, "his enemy record")
	assert_eq(float(e.get("height_m", 0.0)), 8.5, "his height")
	assert_eq(ExpansionState.titan_for("valley.arena.ogre_king"), "titan.ogre_king", "his arena's boss id")
	assert_eq(ExpansionState.titan_for(KING), "titan.ogre_king", "his record")
	# an old save past the Valley (schema 3, the flag set before B2): his record follows the flag, never lowered
	var st := ExpansionState.defaults()
	ExpansionState.sync_from_flags(st, {"world.ogre_king.defeated": true})
	var t: Dictionary = st.titans.get("titan.ogre_king", {})
	assert_eq(str(t.get("state", "")), ExpansionState.STATE_SLAIN, "slain by the defeated flag")
	assert_true(int(t.get("kills", 0)) >= 1, "one kill at least")
	assert_false((t.get("drops", []) as Array).is_empty(), "his drops recorded")
	assert_true(bool(((st.settlements.get("poi.thornwick", {}) as Dictionary).get("flags", {}) as Dictionary).get(
		"kings_trophies", false)), "Thornwick's change mirrored")
	# mid-Valley (before him): nothing
	var mid := ExpansionState.defaults()
	ExpansionState.sync_from_flags(mid, {"quest.village.outcome": "help_cache"})
	assert_false(mid.titans.has("titan.ogre_king"), "not met yet")


func test_the_kingsfall_set_is_made_where_his_trophies_are_worked() -> void:
	var srec := Armour.set_record("armour_set.kingsfall")
	assert_false(srec.is_empty(), "the set record")
	assert_eq(str(srec.get("works", "")), "ogre_trophy", "its trait")
	var pieces := Armour.set_pieces("armour_set.kingsfall")
	assert_eq(pieces.size(), 4, "four pieces")
	var slots := []
	for id: Variant in pieces:
		var rec := Armour.piece(str(id))
		slots.append(str(rec.slot))
		assert_false(((rec.get("look", {}) as Dictionary).get("meshes", []) as Array).is_empty(), "%s: a modelled mesh" % id)
	assert_eq(slots, ["head", "chest", "waist", "arms"], "helm, cuirass, tassets, bracers")
	var made := 0
	for r: Dictionary in GameData.records_of_type("recipe"):
		if str(r.get("makes", "")).begins_with("armour.kingsfall_"):
			made += 1
			assert_eq(str(r.get("works", "")), "ogre_trophy", "%s needs the trait" % r.id)
			assert_eq(str(r.get("requires_flag", "")), "world.ogre_king.defeated", "%s waits for his fall" % r.id)
	assert_eq(made, 4, "a recipe a piece")
	var less := float(Armour.stats(Armour.equipment_with(pieces)).less_pct)
	assert_true(less > 9.0 and less < 13.5, "lighter than the Iron set's 13.8 %%: %.1f %%" % less)


func test_his_intro_and_the_prompts_that_teach_the_trophies() -> void:
	var c := GameData.get_record("cutscene.ogre_king")
	assert_false(c.is_empty(), "his cutscene")
	var s := CutsceneRules.seconds_of(c)
	assert_true(s >= 10.0 and s <= 15.0, "10-15 s: %.1f" % s)
	var kinds := []
	for a: Dictionary in c.actors:
		kinds.append(str(a.kind))
	assert_true(kinds.has("ogre_king") and kinds.has("giant"), "the King's model and the giant at stage 2")
	assert_true((load("res://scripts/core/schemas/cutscene_schema.gd").ACTOR_KINDS as Array).has("ogre_king"),
		"a cutscene actor kind")
	assert_eq(str(GameSession.TITAN_INTROS.get("titan.ogre_king", "")), "cutscene.ogre_king", "played as his fight engages")
	var warn := GameData.get_record("tutorial.ogre_king_trophies")
	assert_eq(str((warn.trigger as Dictionary).area), "valley.area.causeway", "on the causeway into Kingsfall")
	assert_true((warn.get("unless_flags", []) as Array).has("world.ogre_king.defeated"), "never after his fall")
	var down := GameData.get_record("tutorial.ogre_king_down")
	assert_eq(str((down.trigger as Dictionary).event), "titan_toppled", "when the keg drops him")
	assert_true(DataValidator.TUTORIAL_EVENTS.has("titan_toppled"), "a tutorial event")


func test_a_titans_corpse_stays_a_landmark() -> void:
	var d := EncounterDirector.new()
	assert_eq(d.corpse_keep_s_of(null), d.corpse_free_s, "no node: the director's own")
	assert_eq(float((GameData.get_record(KING).ai as Dictionary).get("corpse_keep_s", 0)), 300.0, "the King's: 5 min")
	assert_eq(float((GameData.get_record("enemy.stoneback").ai as Dictionary).get("corpse_keep_s", 0)), 300.0,
		"Stoneback's: 5 min")
	d.free()
