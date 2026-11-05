class_name Progression
extends RefCounted
## Progression rules (spec §9, plan §3.14 design 1): XP and levels, attribute points, the derived
## values the attribute screens preview, which abilities a character meets at a level and stage,
## and where a newly learned ability is slotted. Pure: plain dictionaries and data records in,
## plain values out (no scene, no Sim); PlayerProgression applies the results to the giant.
##
## Character dictionaries use the save keys (CharacterState): "level", "xp" (the TOTAL earned,
## so the save's level 3 / xp 268 means 18 XP into level 3), "unspent_attribute_points",
## "talent_points" and "attributes" ({strength, endurance, dexterity, intellect, willpower,
## constitution}: whole numbers).
##
## XP table (progression.default, plan §4.7): xp_to_next(L) = 100 + 50 x (L - 1), so levels 2, 3,
## 4, 5 and 6 are reached at 100, 250, 450, 700 and 1,000 XP in total; level_cap (20) is the last.
## Every level gained gives attribute_points_per_level (3) attribute points and
## talent_points_per_level (1) talent point.

const RECORD_ID := "progression.default"
const ATTRIBUTE_KEYS := Combatant.ATTRIBUTE_KEYS
## Player-facing names and the one-line effect of each attribute (spec §9; the numbers live in
## Combatant / CombatRules).
const ATTRIBUTE_INFO := {
	"strength": ["Strength", "+1.5% weapon and ability damage per point"],
	"endurance": ["Endurance", "+15 health and +2 stamina per point above 10"],
	"dexterity": ["Dexterity", "-0.5% attack recovery per point above 10 (at most -15%)"],
	"intellect": ["Intellect", "+2 essence per point above 10; magic damage"],
	"willpower": ["Willpower", "+0.5 elemental resistance per point above 10 (at most +20)"],
	"constitution": ["Constitution", "+3 poise per point above 10"],
}
const ALLOCATE_REASONS := ["unknown_attribute", "not_whole", "negative", "nothing", "not_enough_points"]
const LEARNABLE_KINDS := ["ability", "ultimate"]
const SLOT_COUNT := 8


static func record() -> Dictionary:
	return GameData.get_record(RECORD_ID)


static func _rec(rec: Dictionary) -> Dictionary:
	return rec if not rec.is_empty() else record()


# --------------------------------------------------------------------------- XP and levels

static func level_cap(rec: Dictionary = {}) -> int:
	return maxi(1, int(_rec(rec).get("level_cap", 20)))


static func attribute_points_per_level(rec: Dictionary = {}) -> int:
	return maxi(0, int(_rec(rec).get("attribute_points_per_level", 3)))


static func talent_points_per_level(rec: Dictionary = {}) -> int:
	return maxi(0, int(_rec(rec).get("talent_points_per_level", 1)))


## XP needed to go from `level` to level + 1: the record's xp_to_next table (CombatRules'
## formula beyond it); 0 below level 1 and at or beyond the level cap.
static func xp_to_next(level: int, rec: Dictionary = {}) -> int:
	var r := _rec(rec)
	if level < 1 or level >= level_cap(r):
		return 0
	var table: Variant = r.get("xp_to_next", [])
	if typeof(table) == TYPE_ARRAY and level - 1 < (table as Array).size():
		return maxi(0, int(table[level - 1]))
	return CombatRules.xp_to_next_level(level)


## The total XP at which `level` is reached (level 1: 0, level 2: 100, level 3: 250, ...).
static func xp_for_level(level: int, rec: Dictionary = {}) -> int:
	var r := _rec(rec)
	var total := 0
	for l in range(1, clampi(level, 1, level_cap(r))):
		total += xp_to_next(l, r)
	return total


## The level a total of `xp` reaches (at most the cap).
static func level_for_xp(xp: int, rec: Dictionary = {}) -> int:
	var r := _rec(rec)
	var cap := level_cap(r)
	var lvl := 1
	while lvl < cap and xp >= xp_for_level(lvl + 1, r):
		lvl += 1
	return lvl


## XP earned inside the current level and XP the level needs: [into, needed] (needed 0 at the cap).
static func level_progress(level: int, xp: int, rec: Dictionary = {}) -> Array:
	var r := _rec(rec)
	var needed := xp_to_next(level, r)
	var into := maxi(0, xp - xp_for_level(level, r))
	return [mini(into, needed) if needed > 0 else into, needed]


## Adds `n` XP (n <= 0 adds nothing) to `character` in place. Each level gained adds the record's
## attribute and talent points; levels stop at the cap (XP still counts). Returns {"gained",
## "old_level", "new_level", "attribute_points", "talent_points"} (the points added now).
static func add_xp(character: Dictionary, n: int, rec: Dictionary = {}) -> Dictionary:
	var r := _rec(rec)
	var old_level := maxi(1, int(character.get("level", 1)))
	var out := {"gained": 0, "old_level": old_level, "new_level": old_level, "attribute_points": 0,
		"talent_points": 0}
	if n <= 0:
		return out
	var xp := maxi(0, int(character.get("xp", 0))) + n
	character["xp"] = xp
	out.gained = n
	var lvl := old_level
	var cap := level_cap(r)
	while lvl < cap and xp >= xp_for_level(lvl + 1, r):
		lvl += 1
	var levels := maxi(0, lvl - old_level)
	if levels > 0:
		character["level"] = lvl
		out.new_level = lvl
		out.attribute_points = levels * attribute_points_per_level(r)
		out.talent_points = levels * talent_points_per_level(r)
		character["unspent_attribute_points"] = maxi(0, int(character.get("unspent_attribute_points", 0))) \
			+ int(out.attribute_points)
		character["talent_points"] = maxi(0, int(character.get("talent_points", 0))) + int(out.talent_points)
	return out


# --------------------------------------------------------------------------- attributes

## Six whole-number attributes from `attrs` (missing ones from `fallback`, then 10).
static func attributes_of(attrs: Variant, fallback: Dictionary = {}) -> Dictionary:
	var src: Dictionary = attrs if typeof(attrs) == TYPE_DICTIONARY else {}
	var out := {}
	for key: String in ATTRIBUTE_KEYS:
		var v: Variant = src.get(key, fallback.get(key, 10))
		out[key] = int(roundf(float(v))) if SchemaUtil.is_number(v) else 10
	return out


## Spends unspent attribute points: `delta` = {attribute: points}. Refused, changing nothing, for
## an attribute that is not one of the six, a value that is not a whole number or is negative,
## nothing to spend, or more points than are unspent. On success character.attributes and
## character.unspent_attribute_points change in place. {ok, reason, message, spent}.
static func allocate(character: Dictionary, delta: Dictionary) -> Dictionary:
	var total := 0
	for key: Variant in delta:
		if not ATTRIBUTE_KEYS.has(str(key)):
			return _fail("unknown_attribute", "There is no attribute '%s'." % str(key))
		var v: Variant = delta[key]
		if not SchemaUtil.is_number(v) or float(v) != floorf(float(v)):
			return _fail("not_whole", "Attribute points are whole numbers.")
		if int(v) < 0:
			return _fail("negative", "Attribute points cannot be taken back.")
		total += int(v)
	if total == 0:
		return _fail("nothing", "Choose where to spend a point first.")
	var unspent := maxi(0, int(character.get("unspent_attribute_points", 0)))
	if total > unspent:
		return _fail("not_enough_points", "You have only %d point%s to spend." % [unspent, "" if unspent == 1 else "s"])
	var attrs := attributes_of(character.get("attributes", {}))
	for key: Variant in delta:
		attrs[str(key)] = int(attrs[str(key)]) + int(delta[key])
	character["attributes"] = attrs
	character["unspent_attribute_points"] = unspent - total
	var out := {"ok": true, "reason": "", "message": "", "spent": total}
	return out


## What `attributes` (with the growth bonus) make of a player record, through a scratch Combatant
## (the same formulas the giant uses): {"health", "stamina", "essence", "poise", "recovery_scale",
## "recovery_reduction" (0..0.15), "elemental_resistance" (0..0.20), "damage_scale"
## (1 + 0.015 x Strength), "magic_scale" (1 + 0.015 x Intellect)}.
static func derived_preview(player_record: Dictionary, attributes: Dictionary,
		growth_bonus: Dictionary = {}) -> Dictionary:
	var c := Combatant.from_record("progression_preview", player_record)
	c.growth_bonus = growth_bonus.duplicate()
	var attrs := {}
	for key: String in ATTRIBUTE_KEYS:
		attrs[key] = float(attributes.get(key, c.attribute(key)))
	c.set_attributes(attrs)
	var scale := c.recovery_scale()
	return {
		"health": c.pools.health_max, "stamina": c.pools.stamina_max, "essence": c.pools.essence_max,
		"poise": c.poise.threshold, "recovery_scale": scale, "recovery_reduction": 1.0 - scale,
		"elemental_resistance": CombatRules.willpower_resistance_bonus(c.attribute("willpower")),
		"damage_scale": 1.0 + CombatRules.STRENGTH_SCALE * c.attribute("strength"),
		"magic_scale": 1.0 + CombatRules.STRENGTH_SCALE * c.attribute("intellect"),
	}


static func attribute_name(key: String) -> String:
	return str((ATTRIBUTE_INFO.get(key, [key.capitalize()]) as Array)[0])


static func attribute_effect(key: String) -> String:
	var info: Array = ATTRIBUTE_INFO.get(key, [key, ""])
	return str(info[1]) if info.size() > 1 else ""


# --------------------------------------------------------------------------- abilities

## The record's ability_library (every ability a character can learn, in the §4.7 slot order).
static func library(rec: Dictionary = {}) -> Array:
	var lib: Variant = _rec(rec).get("ability_library", [])
	return (lib as Array).duplicate() if typeof(lib) == TYPE_ARRAY else []


## The abilities of `lib` (in its order) a character of `level` and growth `stage` meets and does
## not know yet: unlock_level <= level and unlock_stage <= stage (ActionDefs from GameData).
static func newly_met(lib: Array, known: Array, level: int, stage: int) -> PackedStringArray:
	var out := PackedStringArray()
	for id_v: Variant in lib:
		var id := str(id_v)
		if id == "" or known.has(id) or out.has(id):
			continue
		var def := GameData.get_action(id)
		if def == null or not LEARNABLE_KINDS.has(def.kind):
			continue
		if def.unlock_level <= level and def.unlock_stage <= stage:
			out.append(id)
	return out


## The slot an ability belongs in (plan §4.7): "ultimate" for an ultimate; otherwise slot_N, N its
## position among the library's non-ultimate abilities (Footfall 1, Sweep 2, Stone Skin 3, Grip 4,
## Boulder Hurl 5, Runic Bolt 6, Mend 7, Roar 8); "" when it is not in the library (or beyond 8).
static func preferred_slot(id: String, lib: Array) -> String:
	var def := GameData.get_action(id)
	if def != null and def.kind == "ultimate":
		return "ultimate"
	var n := 0
	for other_v: Variant in lib:
		var other := str(other_v)
		var other_def := GameData.get_action(other)
		if other_def != null and other_def.kind == "ultimate":
			continue
		n += 1
		if other == id:
			return "slot_%d" % n if n <= SLOT_COUNT else ""
	return ""


## Where a newly learned ability is auto-slotted in `loadout` (controller.loadout keys): an
## ultimate into "ultimate" when it is empty; an ability into its preferred slot when that is
## empty, else into the first empty slot_1..slot_8. "" = nowhere free (learned, not slotted).
static func auto_slot(loadout: Dictionary, id: String, lib: Array) -> String:
	var def := GameData.get_action(id)
	if def != null and def.kind == "ultimate":
		return "ultimate" if str(loadout.get("ultimate", "")) == "" else ""
	var preferred := preferred_slot(id, lib)
	if preferred.begins_with("slot_") and str(loadout.get(preferred, "")) == "":
		return preferred
	for i in SLOT_COUNT:
		var key := "slot_%d" % (i + 1)
		if str(loadout.get(key, "")) == "":
			return key
	return ""


## The key shown for a slot ("6", "R"): its keyboard binding, or the slot number.
static func slot_key_label(slot_key: String) -> String:
	if slot_key == "":
		return ""
	var action_name := "ultimate" if slot_key == "ultimate" else slot_key.replace("slot_", "ability_")
	var label := InputBindings.describe_action(action_name, false)
	if label == "-" or label == "":
		return "U" if slot_key == "ultimate" else slot_key.trim_prefix("slot_")
	return label


# --------------------------------------------------------------------------- data checks

## Cross-record checks of the progression data (GameData post-pass, P12 anchor):
##   * every ability_library entry is an action of kind ability or ultimate;
##   * every weapon upgrade fits at least as high as its source (PlayerEquipment.upgrade_problems)
##     and is one step: the upgraded weapon has no upgrade of its own (the slice has one upgrade).
static func data_errors(records: Dictionary, record_paths: Dictionary = {}) -> PackedStringArray:
	var out := PackedStringArray()
	var rec: Dictionary = records.get(RECORD_ID, {})
	var lib: Variant = rec.get("ability_library", [])
	if typeof(lib) == TYPE_ARRAY:
		for id_v: Variant in lib:
			var a: Dictionary = records.get(str(id_v), {})
			if a.is_empty() or str(a.get("type", "")) != "action":
				continue   # a missing or mistyped reference is a validation error already
			if not LEARNABLE_KINDS.has(str(a.get("kind", ""))):
				out.append("%s (%s): ability_library entry '%s' is a %s action, not an ability or ultimate" % [
					record_paths.get(RECORD_ID, "?"), RECORD_ID, str(id_v), str(a.get("kind", ""))])
	out.append_array(PlayerEquipment.upgrade_problems(records))
	var ids := records.keys()
	ids.sort()
	for id: Variant in ids:
		var w: Dictionary = records[id]
		if str(w.get("type", "")) != "weapon" or typeof(w.get("upgrade")) != TYPE_DICTIONARY:
			continue
		var to_id := str((w.upgrade as Dictionary).get("to", ""))
		var to: Dictionary = records.get(to_id, {})
		if str(to.get("type", "")) == "weapon" and typeof(to.get("upgrade")) == TYPE_DICTIONARY:
			out.append("%s (%s): upgrade.to %s has an upgrade of its own (the forge reforges a weapon once)" % [
				record_paths.get(id, "?"), id, to_id])
	return out


static func _fail(reason: String, message: String) -> Dictionary:
	return {"ok": false, "reason": reason, "message": message, "spent": 0}
