extends TestSuite
## CharacterState (plan §2.9): the new-game character from progression.default and the player
## record, int casts after a JSON round trip, defaults, unknown ids dropped (and reported),
## unknown keys kept, and the structural validation.


func _progression() -> Dictionary:
	return GameData.get_record("progression.default")


func _player() -> Dictionary:
	return GameData.get_record("player.giant")


## A JSON round trip, like a save on disk: every number comes back as a float.
func _through_json(d: Dictionary) -> Dictionary:
	return JSON.parse_string(JSON.stringify(d)) as Dictionary


func test_new_game_follows_the_progression_record() -> void:
	var c := CharacterState.new_game(_progression(), _player())
	var ng: Dictionary = _progression().new_game
	assert_eq(c.id, "char.valley_1", "the one slot's character id")
	assert_eq(c.definition_id, "player.giant", "the player definition")
	assert_eq(c.ancestry, "ancestry.neutral", "ancestry from new_game (decision 20)")
	assert_eq(c.level, int(ng.level), "new_game level")
	assert_eq(typeof(c.level), TYPE_INT, "levels are ints")
	assert_eq(c.growth_stage, 1, "growth.01 is stage 1")
	assert_eq(c.weapon, "weapon.club", "new_game weapon")
	assert_eq(c.weapons_owned, ["weapon.club"], "and it is owned")
	assert_eq(c.xp, 0, "no XP")
	assert_eq(c.unspent_attribute_points, 0, "no points")
	assert_eq(c.talent_points, 0, "no talent points")
	assert_eq(c.level_exempt, [], "nothing taught early yet")
	var slots: Array = c.loadout.slots
	assert_eq(slots.size(), 8, "eight slots")
	for i in 8:
		assert_eq(slots[i], str(ng.slots[i]), "slot %d from new_game" % (i + 1))
	assert_eq(c.loadout.ultimate, str(ng.ultimate), "ultimate from new_game")
	for id: Variant in ng.known_abilities:
		assert_true((c.known_abilities as Array).has(id), "%s is known" % id)
	for key: String in Combatant.ATTRIBUTE_KEYS:
		assert_eq(c.attributes[key], int(_player().attributes[key]), "%s from the record" % key)
	var res: Dictionary = c.resources
	assert_near(float(res.health), 500.0, 1e-6, "full health")
	assert_near(float(res.stamina), 100.0, 1e-6, "full stamina")
	assert_near(float(res.essence), 100.0, 1e-6, "full essence")
	assert_near(float(res.fury), 0.0, 1e-9, "no fury")
	assert_eq(CharacterState.validate(c), PackedStringArray(), "the new-game character validates")


func test_from_player_record_uses_the_record_loadout() -> void:
	var c := CharacterState.from_player_record(_player())
	var rec_slots: Array = _player().loadout.slots
	for i in 8:
		assert_eq(c.loadout.slots[i], str(rec_slots[i]), "slot %d from giant.json" % (i + 1))
	assert_eq(c.loadout.ultimate, str(_player().loadout.ultimate), "ultimate from giant.json")
	for id: Variant in rec_slots:
		if str(id) != "":
			assert_true((c.known_abilities as Array).has(id), "slotted %s is known" % id)
	assert_eq(c.level, 1, "level 1")


func test_full_resources_follow_endurance() -> void:
	var rec := _player().duplicate(true)
	rec.attributes["endurance"] = 14
	rec.attributes["intellect"] = 13
	var res := CharacterState.full_resources(rec)
	assert_near(float(res.health), 500.0 + 4 * 15.0, 1e-6, "Endurance adds 15 health per point")
	assert_near(float(res.stamina), 100.0 + 4 * 2.0, 1e-6, "and 2 stamina")
	assert_near(float(res.essence), 100.0 + 3 * 2.0, 1e-6, "Intellect adds 2 essence")


func test_normalize_casts_json_numbers_back_to_ints() -> void:
	var c := CharacterState.new_game(_progression(), _player())
	c.level = 3
	c.xp = 268
	c.unspent_attribute_points = 3
	c.talent_points = 2
	c.growth_stage = 2
	c.attributes.strength = 12
	c.level_exempt = ["ability.stone_skin"]
	c.resources = {"health": 695.5, "stamina": 110.0, "essence": 102.0, "fury": 12.0}
	var raw := _through_json(c)
	assert_eq(typeof(raw.level), TYPE_FLOAT, "JSON brings the level back as a float")
	var n := CharacterState.normalize(raw)
	for key: String in ["level", "xp", "unspent_attribute_points", "talent_points", "growth_stage"]:
		assert_eq(typeof(n[key]), TYPE_INT, "%s is an int again" % key)
		assert_eq(n[key], c[key], "%s keeps its value" % key)
	assert_eq(typeof(n.attributes.strength), TYPE_INT, "attributes are ints")
	assert_eq(n.attributes.strength, 12, "strength kept")
	assert_eq(n.level_exempt, ["ability.stone_skin"], "level_exempt kept")
	assert_eq(n.ancestry, "ancestry.neutral", "ancestry kept")
	assert_eq(typeof(n.resources.health), TYPE_FLOAT, "resources are floats")
	assert_near(float(n.resources.health), 695.5, 1e-6, "health kept")
	assert_eq(n, CharacterState.normalize(n), "normalize is idempotent")


func test_unknown_ids_are_dropped_and_reported() -> void:
	var c := CharacterState.new_game(_progression(), _player())
	c.loadout.slots[2] = "ability.removed_move"
	c.loadout.ultimate = "ability.removed_ultimate"
	(c.known_abilities as Array).append("ability.removed_move")
	c.level_exempt = ["ability.removed_move", "ability.stone_skin"]
	c.weapon = "weapon.lost_axe"
	c.weapons_owned = ["weapon.club", "weapon.lost_axe"]
	c.ancestry = "ancestry.gone"
	c["talents"] = {"destroyer": 1}   # a key from a later package
	var r := CharacterState.sanitize(_through_json(c))
	var n: Dictionary = r.data
	assert_eq(n.loadout.slots[2], "", "an unknown slotted ability becomes an empty slot")
	assert_eq(n.loadout.ultimate, "", "an unknown ultimate too")
	assert_false((n.known_abilities as Array).has("ability.removed_move"), "dropped from known_abilities")
	assert_eq(n.level_exempt, ["ability.stone_skin"], "dropped from level_exempt, the rest kept")
	assert_eq(n.weapon, "weapon.club", "an unknown weapon falls back to the record's")
	assert_eq(n.weapons_owned, ["weapon.club"], "and leaves the owned list")
	assert_eq(n.ancestry, "ancestry.neutral", "an unknown ancestry falls back")
	assert_eq(n.talents, {"destroyer": 1.0}, "unknown keys pass through")
	var dropped: PackedStringArray = r.dropped
	for id in ["ability.removed_move", "ability.removed_ultimate", "weapon.lost_axe", "ancestry.gone"]:
		assert_true(dropped.has(id), "%s is reported" % id)
	assert_eq(dropped.count("ability.removed_move"), 1, "each id is reported once")


func test_defaults_fill_missing_keys() -> void:
	var n := CharacterState.normalize({"definition_id": "player.giant", "level": 2.0,
		"loadout": {"slots": ["ability.heavy_footfall"]}})
	assert_eq(n.id, "char.valley_1", "default id")
	assert_eq(n.ancestry, "ancestry.neutral", "the record's ancestry")
	assert_eq(n.weapon, "weapon.club", "the record's weapon")
	assert_eq(n.growth_stage, 1, "the record's growth stage")
	assert_eq(n.xp, 0, "xp 0")
	assert_eq((n.loadout.slots as Array).size(), 8, "slots padded to eight")
	assert_eq(n.loadout.slots[0], "ability.heavy_footfall", "the given slot kept")
	assert_eq(n.loadout.ultimate, "", "no ultimate")
	assert_false(n.has("resources"), "no resources: the player keeps full pools")
	var odd := CharacterState.normalize({"definition_id": "player.nobody", "level": 500,
		"loadout": {"slots": []}})
	assert_eq(odd.definition_id, "player.giant", "an unknown definition falls back to the giant")
	assert_eq(odd.level, CharacterState.MAX_LEVEL, "levels are clamped")


func test_validate_reports_structural_problems() -> void:
	assert_eq(CharacterState.validate(CharacterState.new_game(_progression(), _player())), PackedStringArray(),
		"valid")
	var errors := CharacterState.validate({"level": "three", "loadout": "none", "resources": {"health": -5},
		"known_abilities": "ability.x", "xp": -1, "attributes": {"strength": "big"}, "weapon": 3})
	var text := "\n".join(errors)
	for want in ["character.definition_id", "character.level: must be a whole number", "character.loadout",
			"character.resources.health", "character.known_abilities", "character.xp: must be >= 0",
			"character.attributes.strength", "character.weapon"]:
		assert_true(text.contains(want), "reports %s (%s)" % [want, text])
	assert_true("\n".join(CharacterState.validate({"definition_id": "player.giant", "loadout": {"slots": []}})).contains(
		"character.level: missing"), "a missing level")
	var too_many := CharacterState.validate({"definition_id": "player.giant", "level": 1,
		"loadout": {"slots": ["", "", "", "", "", "", "", "", ""]}})
	assert_true("\n".join(too_many).contains("at most 8"), "at most eight slots")
