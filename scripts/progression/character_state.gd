class_name CharacterState
extends RefCounted
## Static helpers over the character dictionary of the save (plan §2.9): who the giant is and
## what it carries between loads. GameSession keeps one live copy (`GameSession.character`),
## GiantPlayer.apply_character_state() / capture_character_state() move it in and out of the
## player, and SaveSlots writes it inside the save document.
##
## Shape (every key optional except definition_id, level and loadout; JSON numbers come back
## as floats, so normalize() casts them):
##   {"id": "char.valley_1", "definition_id": "player.giant", "ancestry": "ancestry.neutral",
##    "level": 3, "xp": 268, "unspent_attribute_points": 3, "talent_points": 2,
##    "attributes": {"strength": 12, ...}, "growth_stage": 2, "weapon": "weapon.club",
##    "weapons_owned": ["weapon.club"], "loadout": {"slots": [8 ids, "" = empty], "ultimate": ""},
##    "known_abilities": [...], "level_exempt": [...],
##    "resources": {"health": 695.0, "stamina": 110.0, "essence": 102.0, "fury": 0.0},
##    "talents": ["talent.guardian_stone_hide"], "ancestry_chosen": false}
## Keys this file does not know (added by later packages) pass through unchanged.
## Save schema 2 (P20, plan M6-M9 §2.6): "talents" (talent record ids, P33 learns them; unknown ids
## are dropped like abilities) and "ancestry_chosen" (true once the ancestry was chosen at a
## shrine: P33 normalises it to "the ancestry is not ancestry.neutral") - normalize() adds both.
## world_start() is the character a campaign started in the world gets.

const DEFAULT_ID := "char.valley_1"
const DEFAULT_DEFINITION := "player.giant"
const DEFAULT_ANCESTRY := "ancestry.neutral"
const DEFAULT_WEAPON := "weapon.club"
const SLOT_COUNT := 8
## CombatController.level 99 means "no level gating" (the sandbox); a Valley character is 1-20.
const MAX_LEVEL := 99
const COUNTER_KEYS := ["xp", "unspent_attribute_points", "talent_points"]
const ID_LIST_KEYS := ["weapons_owned", "known_abilities", "level_exempt"]
const RESOURCE_KEYS := ["health", "stamina", "essence", "fury"]
## The keys PlayerProgression (P12) applies and captures; "xp" is the total XP earned. P33 adds the
## learned talents and whether the ancestry was chosen.
const PROGRESSION_KEYS := ["level", "xp", "unspent_attribute_points", "talent_points", "attributes",
	"level_exempt", "ancestry", "talents", "ancestry_chosen"]


## The Valley's starting character: the player record's body and attributes with the
## progression record's new_game block (level, growth profile, weapon, ancestry, slots, ultimate,
## known abilities) on top. Resources start full.
static func new_game(progression: Dictionary, player_record: Dictionary) -> Dictionary:
	var c := from_player_record(player_record)
	var ng: Dictionary = progression.get("new_game", {}) if typeof(progression.get("new_game")) == TYPE_DICTIONARY else {}
	if SchemaUtil.is_number(ng.get("level")):
		c["level"] = int(ng.level)
	if typeof(ng.get("growth_profile")) == TYPE_STRING:
		c["growth_stage"] = _profile_stage(str(ng.growth_profile), int(c.growth_stage))
	if typeof(ng.get("weapon")) == TYPE_STRING and str(ng.weapon) != "":
		c["weapon"] = str(ng.weapon)
		c["weapons_owned"] = [str(ng.weapon)]
	if typeof(ng.get("ancestry")) == TYPE_STRING and str(ng.ancestry) != "":
		c["ancestry"] = str(ng.ancestry)
	var loadout: Dictionary = c.loadout
	if typeof(ng.get("slots")) == TYPE_ARRAY:
		loadout["slots"] = _slot_list(ng.slots)
	if typeof(ng.get("ultimate")) == TYPE_STRING:
		loadout["ultimate"] = str(ng.ultimate)
	var known: Array = []
	if typeof(ng.get("known_abilities")) == TYPE_ARRAY:
		for id: Variant in ng.known_abilities:
			_append_unique(known, str(id))
	for id: Variant in loadout.slots:
		_append_unique(known, str(id))
	_append_unique(known, str(loadout.ultimate))
	c["known_abilities"] = known
	return normalize(c)


## The character of a campaign started in the world (P20, plan M6-M9 §2.6): new_game() with the
## progression record's world_start block on top - the Valley's worst guaranteed outcome (level,
## total XP, unspent attribute and talent points, growth profile, weapon and the weapons owned,
## ancestry, slots, ultimate and known abilities). No resources: the giant starts with the full
## pools of its stage. Without a world_start block it is new_game()'s character.
static func world_start(progression: Dictionary, player_record: Dictionary) -> Dictionary:
	var c := new_game(progression, player_record)
	var ws: Dictionary = progression.get("world_start", {}) if typeof(progression.get("world_start")) == TYPE_DICTIONARY else {}
	if ws.is_empty():
		return c
	for key: String in ["level", "xp", "unspent_attribute_points", "talent_points"]:
		if SchemaUtil.is_number(ws.get(key)):
			c[key] = int(ws[key])
	if typeof(ws.get("growth_profile")) == TYPE_STRING:
		c["growth_stage"] = _profile_stage(str(ws.growth_profile), int(c.growth_stage))
	if typeof(ws.get("weapon")) == TYPE_STRING and str(ws.weapon) != "":
		c["weapon"] = str(ws.weapon)
	var owned: Array = [str(c.weapon)]
	if typeof(ws.get("weapons_owned")) == TYPE_ARRAY:
		for id: Variant in ws.weapons_owned:
			_append_unique(owned, str(id))
	c["weapons_owned"] = owned
	if typeof(ws.get("ancestry")) == TYPE_STRING and str(ws.ancestry) != "":
		c["ancestry"] = str(ws.ancestry)
	if typeof(ws.get("attributes")) == TYPE_DICTIONARY:
		var attrs: Dictionary = (c.attributes as Dictionary).duplicate()
		for key: Variant in ws.attributes:
			attrs[str(key)] = _whole(ws.attributes[key], int(attrs.get(str(key), 10)))
		c["attributes"] = attrs
	var loadout: Dictionary = c.loadout
	if typeof(ws.get("slots")) == TYPE_ARRAY:
		loadout["slots"] = _slot_list(ws.slots)
	if typeof(ws.get("ultimate")) == TYPE_STRING:
		loadout["ultimate"] = str(ws.ultimate)
	var known: Array = []
	if typeof(ws.get("known_abilities")) == TYPE_ARRAY:
		for id: Variant in ws.known_abilities:
			_append_unique(known, str(id))
	for id: Variant in loadout.slots:
		_append_unique(known, str(id))
	_append_unique(known, str(loadout.ultimate))
	c["known_abilities"] = known
	c.erase("resources")
	return normalize(c)


## {item id: count} from a [{"item", "count"}] list (world_start's inventory; unknown items and
## counts below 1 are left out).
static func inventory_of(list: Variant) -> Dictionary:
	var out := {}
	if typeof(list) != TYPE_ARRAY:
		return out
	for e: Variant in list:
		if typeof(e) != TYPE_DICTIONARY:
			continue
		var id := str(e.get("item", ""))
		var n := _whole(e.get("count", 1), 1)
		if id == "" or n < 1 or _record_type(id) != "item":
			continue
		out[id] = int(out.get(id, 0)) + n
	return out


## A complete character built from a player record alone (the giant as the record describes it):
## level 1, no XP or points, the record's attributes, growth profile stage, weapon and loadout,
## full resources.
static func from_player_record(player_record: Dictionary) -> Dictionary:
	var rec := player_record
	var c := {}
	c["id"] = DEFAULT_ID
	c["definition_id"] = str(rec.get("id", DEFAULT_DEFINITION))
	c["ancestry"] = str(rec.get("ancestry", DEFAULT_ANCESTRY))
	c["level"] = 1
	c["xp"] = 0
	c["unspent_attribute_points"] = 0
	c["talent_points"] = 0
	var attrs := {}
	var rec_attrs: Dictionary = rec.get("attributes", {}) if typeof(rec.get("attributes")) == TYPE_DICTIONARY else {}
	for key: String in Combatant.ATTRIBUTE_KEYS:
		attrs[key] = _whole(rec_attrs.get(key, 10), 10)
	c["attributes"] = attrs
	c["growth_stage"] = _profile_stage(str(rec.get("growth_profile", "growth.01")), 1)
	var weapon := str(rec.get("weapon", DEFAULT_WEAPON))
	c["weapon"] = weapon
	c["weapons_owned"] = [weapon]
	var lo: Dictionary = rec.get("loadout", {}) if typeof(rec.get("loadout")) == TYPE_DICTIONARY else {}
	var slots := _slot_list(lo.get("slots", []))
	var ultimate := str(lo.get("ultimate", ""))
	c["loadout"] = {"slots": slots, "ultimate": ultimate}
	var known: Array = []
	for id: Variant in slots:
		_append_unique(known, str(id))
	_append_unique(known, ultimate)
	c["known_abilities"] = known
	c["level_exempt"] = []
	c["resources"] = full_resources(rec)
	return c


## Full pools for a record: the maxima its Combatant derives (base resources plus attribute
## bonuses), fury 0.
static func full_resources(player_record: Dictionary) -> Dictionary:
	var pools := Combatant.from_record("character_state", player_record).pools
	return {"health": pools.health_max, "stamina": pools.stamina_max, "essence": pools.essence_max,
		"fury": 0.0}


## int() casts, defaults and unknown ids dropped (see sanitize(), which also lists them).
static func normalize(d: Dictionary) -> Dictionary:
	return sanitize(d).data


## normalize() with a report: {"data": the normalized copy, "dropped": ids this build does not
## know (abilities, weapons, the ancestry or the player definition), each listed once}. Unknown
## slot ids become empty slots; an unknown weapon, ancestry or definition falls back to the
## player record's (or the defaults). Unknown keys are kept as they are.
static func sanitize(d: Dictionary) -> Dictionary:
	var out := d.duplicate(true)
	var dropped := PackedStringArray()
	out["id"] = str(d.id) if typeof(d.get("id")) == TYPE_STRING and str(d.id) != "" else DEFAULT_ID
	var def_id := str(d.get("definition_id", DEFAULT_DEFINITION))
	if _record_type(def_id) != "player":
		if typeof(d.get("definition_id")) == TYPE_STRING and def_id != "":
			_append_unique_packed(dropped, def_id)
		def_id = DEFAULT_DEFINITION
	out["definition_id"] = def_id
	var rec := GameData.get_record(def_id)
	var ancestry := str(d.get("ancestry", "")) if typeof(d.get("ancestry")) == TYPE_STRING else ""
	if ancestry == "" or _record_type(ancestry) != "ancestry":
		if ancestry != "":
			_append_unique_packed(dropped, ancestry)
		ancestry = str(rec.get("ancestry", DEFAULT_ANCESTRY))
	out["ancestry"] = ancestry
	out["level"] = clampi(_whole(d.get("level", 1), 1), 1, MAX_LEVEL)
	for key: String in COUNTER_KEYS:
		out[key] = maxi(0, _whole(d.get(key, 0), 0))
	out["growth_stage"] = maxi(1, _whole(d.get("growth_stage"),
		_profile_stage(str(rec.get("growth_profile", "growth.01")), 1)))
	var attrs := {}
	var raw_attrs: Dictionary = d.attributes if typeof(d.get("attributes")) == TYPE_DICTIONARY else {}
	var rec_attrs: Dictionary = rec.get("attributes", {}) if typeof(rec.get("attributes")) == TYPE_DICTIONARY else {}
	for key: String in Combatant.ATTRIBUTE_KEYS:
		attrs[key] = _whole(raw_attrs.get(key, rec_attrs.get(key, 10)), _whole(rec_attrs.get(key, 10), 10))
	out["attributes"] = attrs
	var weapon := str(d.get("weapon", "")) if typeof(d.get("weapon")) == TYPE_STRING else ""
	if weapon == "" or _record_type(weapon) != "weapon":
		if weapon != "":
			_append_unique_packed(dropped, weapon)
		weapon = str(rec.get("weapon", DEFAULT_WEAPON))
	out["weapon"] = weapon
	for key: String in ID_LIST_KEYS:
		var want := "weapon" if key == "weapons_owned" else "action"
		var clean: Array = []
		var raw: Array = d[key] if typeof(d.get(key)) == TYPE_ARRAY else []
		for id: Variant in raw:
			var s := str(id)
			if s == "":
				continue
			if _record_type(s) == want:
				_append_unique(clean, s)
			else:
				_append_unique_packed(dropped, s)
		out[key] = clean
	# Save schema 2 (P20): the learned talents (talent records; P33) and whether the ancestry was
	# chosen.
	var talents: Array = []
	var raw_talents: Array = d.talents if typeof(d.get("talents")) == TYPE_ARRAY else []
	for id: Variant in raw_talents:
		var s := str(id)
		if s == "":
			continue
		if _record_type(s) == "talent":
			_append_unique(talents, s)
		else:
			_append_unique_packed(dropped, s)
	out["talents"] = talents
	# P33: the choice is the ancestry itself - every ancestry but the neutral (prologue) one is chosen,
	# and the neutral one never is, whatever the save says (a neutral character marked as having
	# chosen would never be offered the choice).
	out["ancestry_chosen"] = ancestry != DEFAULT_ANCESTRY
	var lo: Dictionary = d.loadout if typeof(d.get("loadout")) == TYPE_DICTIONARY else {}
	var slots: Array = []
	for id: Variant in _slot_list(lo.get("slots", [])):
		var s := str(id)
		if s != "" and _record_type(s) != "action":
			_append_unique_packed(dropped, s)
			s = ""
		slots.append(s)
	var ultimate := str(lo.get("ultimate", "")) if typeof(lo.get("ultimate", "")) == TYPE_STRING else ""
	if ultimate != "" and _record_type(ultimate) != "action":
		_append_unique_packed(dropped, ultimate)
		ultimate = ""
	var new_lo := lo.duplicate(true)
	new_lo["slots"] = slots
	new_lo["ultimate"] = ultimate
	out["loadout"] = new_lo
	if typeof(d.get("resources")) == TYPE_DICTIONARY:
		var res := {}
		for key: String in RESOURCE_KEYS:
			var v: Variant = (d.resources as Dictionary).get(key)
			if SchemaUtil.is_number(v):
				res[key] = maxf(0.0, float(v))
		out["resources"] = res
	elif d.has("resources"):
		out.erase("resources")
	return {"data": out, "dropped": dropped}


## Structural problems ("character.<key>: ..."); [] when the dictionary can be loaded. Unknown
## ids are not problems here (normalize drops them).
static func validate(d: Dictionary) -> PackedStringArray:
	var errors := PackedStringArray()
	if typeof(d.get("definition_id")) != TYPE_STRING or str(d.definition_id) == "":
		errors.append("character.definition_id: missing or not a string")
	if not d.has("level"):
		errors.append("character.level: missing")
	for key: String in ["level", "growth_stage"] + COUNTER_KEYS:
		if not d.has(key):
			continue
		if not _is_whole(d[key]):
			errors.append("character.%s: must be a whole number" % key)
		elif key in ["level", "growth_stage"] and int(d[key]) < 1:
			errors.append("character.%s: must be >= 1" % key)
		elif key in COUNTER_KEYS and int(d[key]) < 0:
			errors.append("character.%s: must be >= 0" % key)
	for key: String in ["id", "ancestry", "weapon"]:
		if d.has(key) and typeof(d[key]) != TYPE_STRING:
			errors.append("character.%s: must be a string" % key)
	if d.has("attributes"):
		if typeof(d.attributes) != TYPE_DICTIONARY:
			errors.append("character.attributes: must be an object")
		else:
			for key: Variant in d.attributes:
				if not SchemaUtil.is_number(d.attributes[key]):
					errors.append("character.attributes.%s: must be a number" % key)
	for key: String in ID_LIST_KEYS:
		if d.has(key):
			_check_string_list(d[key], "character.%s" % key, errors)
	if d.has("talents"):
		_check_string_list(d.talents, "character.talents", errors)
	if d.has("ancestry_chosen") and typeof(d.ancestry_chosen) != TYPE_BOOL:
		errors.append("character.ancestry_chosen: must be true or false")
	if typeof(d.get("loadout")) != TYPE_DICTIONARY:
		errors.append("character.loadout: missing or not an object")
	else:
		var lo: Dictionary = d.loadout
		if typeof(lo.get("slots")) != TYPE_ARRAY:
			errors.append("character.loadout.slots: missing or not an array")
		else:
			_check_string_list(lo.slots, "character.loadout.slots", errors)
			if (lo.slots as Array).size() > SLOT_COUNT:
				errors.append("character.loadout.slots: at most %d entries" % SLOT_COUNT)
		if lo.has("ultimate") and typeof(lo.ultimate) != TYPE_STRING:
			errors.append("character.loadout.ultimate: must be a string")
	if d.has("resources"):
		if typeof(d.resources) != TYPE_DICTIONARY:
			errors.append("character.resources: must be an object")
		else:
			for key: Variant in d.resources:
				var v: Variant = d.resources[key]
				if not SchemaUtil.is_number(v) or float(v) < 0.0:
					errors.append("character.resources.%s: must be a number >= 0" % key)
	return errors


# --------------------------------------------------------------------------- progression (P12)

## True for a character without level gating: level 99 (MAX_LEVEL), the sandbox giant's and the
## tools'. PlayerProgression then keeps controller.level at 99 and derives the shown level from XP.
static func is_ungated(d: Dictionary) -> bool:
	return SchemaUtil.is_number(d.get("level")) and int(d.level) >= MAX_LEVEL


## The progression part of `d` (the PROGRESSION_KEYS present in it), a copy: what the bot and the
## tests compare across a reload.
static func progression_part(d: Dictionary) -> Dictionary:
	var out := {}
	for key: String in PROGRESSION_KEYS:
		if d.has(key):
			out[key] = d[key].duplicate(true) if typeof(d[key]) in [TYPE_DICTIONARY, TYPE_ARRAY] else d[key]
	return out


# --------------------------------------------------------------------------- helpers

static func _record_type(id: String) -> String:
	if id == "" or not GameData.has_record(id):
		return ""
	return str(GameData.get_record(id).get("type", ""))


static func _profile_stage(profile_id: String, fallback: int) -> int:
	var profile := GameData.get_record(profile_id)
	return _whole(profile.get("stage", fallback), fallback) if not profile.is_empty() else fallback


## Exactly SLOT_COUNT strings ("" = empty) from an array (shorter arrays are padded).
static func _slot_list(raw: Variant) -> Array:
	var out: Array = []
	var arr: Array = raw if typeof(raw) == TYPE_ARRAY else []
	for i in SLOT_COUNT:
		out.append(str(arr[i]) if i < arr.size() and arr[i] != null else "")
	return out


static func _is_whole(v: Variant) -> bool:
	return SchemaUtil.is_number(v) and float(v) == floorf(float(v))


## v as an int when it is a number (rounded), else fallback.
static func _whole(v: Variant, fallback: int) -> int:
	return int(roundf(float(v))) if SchemaUtil.is_number(v) else fallback


static func _append_unique(list: Array, id: String) -> void:
	if id != "" and not list.has(id):
		list.append(id)


static func _append_unique_packed(list: PackedStringArray, id: String) -> void:
	if id != "" and not list.has(id):
		list.append(id)


static func _check_string_list(v: Variant, ctx: String, errors: PackedStringArray) -> void:
	if typeof(v) != TYPE_ARRAY:
		errors.append("%s: must be an array of strings" % ctx)
		return
	for item: Variant in v:
		if typeof(item) != TYPE_STRING:
			errors.append("%s: must be an array of strings" % ctx)
			return
