class_name Talents
extends RefCounted
## Talents and ancestries (plan M6-M9 §2.11, §5.12, decision 22; P33): the rules, pure - plain
## dictionaries and data records in, plain values out (no scene, no Sim). PlayerProgression applies
## them to the giant; the shrine's Talents and Ancestry tabs and the ancestry screen show them.
##
## Talents: three trees (Destroyer: melee, grabs and stagger; Guardian: protection and poise;
## Primordial: magic and fury) of nine talent records each (data/talents/), in five tiers. A tier
## opens at a character level (progression.default "talent_tier_levels": 6, 8, 9, 10, 12); within
## a tree each talent of tiers 2-4 needs the one above it in its column ("requires"), and the tier-5
## capstone needs both tier-4 talents and costs 2 points. A talent point comes with every level from
## level 2 (Progression.add_xp; the Valley's unspent points carry over), so a level-12 giant holds
## 11: one whole tree (10) and one talent more. Learning spends the points once and is permanent.
##
## Effects: a talent's "modifiers" (STATUS_MODIFIERS keys) are passives; its "grants" are abilities
## learned with it (granted_by "talent"); "replaces" {old: new} puts a new ability in an old one's
## slot. Passives are lasting modifiers folded into the Combatant's accessors (Combatant.passives,
## never statuses): the "_mult" keys multiply, every other key adds (passives_for).
##
## Ancestries (data/player/ancestry_*.json): every ancestry record but ancestry.neutral (the
## prologue's) can be chosen once, at a shrine, once the Old Kingdom has opened (the flag
## progress.world_entered). Choosing one adds its attribute_bonus to the attributes (once), makes
## its modifiers and resistances lasting passives (with the talents'), teaches its signature
## ability and sets the flag ancestry.chosen (its id). dialogue_tags name the peoples who answer to
## it (P36's dialogues read ancestry_is); dialogue_note says so to the player.

const TREES := ["destroyer", "guardian", "primordial"]
## tree -> [name, what it is about] (the Talents tab's headers).
const TREE_INFO := {
	"destroyer": ["Destroyer", "melee, grabs and stagger"],
	"guardian": ["Guardian", "protection and poise"],
	"primordial": ["Primordial", "magic and fury"],
}
const TIER_COUNT := 5
## The tiers' levels when the progression record has none (plan §5.12).
const DEFAULT_TIER_LEVELS := [6, 8, 9, 10, 12]
## Why a talent cannot be learned (check / learn): an unknown id, already learned, the tier's
## level not reached, a required talent missing, too few points.
const LEARN_REASONS := ["unknown", "known", "level", "requires", "points"]
## STATUS_MODIFIERS keys a passive may not use (periodic heals and slows belong to statuses).
const NON_PASSIVE_KEYS := ["heal_per_tick", "slow_fraction"]
## The flag GameSession sets on entering the Old Kingdom: ancestries are offered from then on.
const WORLD_FLAG := "progress.world_entered"
## The flag choosing an ancestry sets (its value: the ancestry id).
const CHOSEN_FLAG := "ancestry.chosen"
const NEUTRAL := CharacterState.DEFAULT_ANCESTRY
## Player-facing names of the passive keys, and how their value reads (pct: a multiplier shown as
## +/-%; flat: a number; flat_pct: a fraction shown as %; m: metres).
const KEY_TEXT := {
	"armor_flat": ["Armour", "flat"],
	"outgoing_damage_mult": ["Damage dealt", "pct"],
	"outgoing_poise_mult": ["Poise damage dealt", "pct"],
	"damage_taken_mult": ["Damage taken", "pct"],
	"fury_gain_mult": ["Fury gained", "pct"],
	"heal_received_mult": ["Healing received", "pct"],
	"stamina_cost_mult": ["Stamina costs", "pct"],
	"essence_cost_mult": ["Essence costs", "pct"],
	"cooldown_mult": ["Ability cooldowns", "pct"],
	"poise_threshold_add": ["Poise (staggers less)", "flat"],
	"poise_damage_taken_mult": ["Poise damage taken", "pct"],
	"grab_reach_add": ["Grab reach", "m"],
	"fury_on_kill_add": ["Fury per kill", "flat"],
	"move_speed_mult": ["Movement speed", "pct"],
	"elemental_resist_add": ["Elemental resistance", "flat_pct"],
	"health_add": ["Health", "flat"],
	"stamina_add": ["Stamina", "flat"],
	"essence_add": ["Essence", "flat"],
	"heavy_damage_mult": ["Heavy attack damage", "pct"],
	"throw_damage_mult": ["Throw damage", "pct"],
	"magic_damage_mult": ["Magic damage", "pct"],
	"armor_total": ["Armour", "flat"],
}
## The order passive lines are listed in (defence first, then offence, then resources).
const KEY_ORDER := ["health_add", "stamina_add", "essence_add", "armor_flat", "poise_threshold_add",
	"damage_taken_mult", "poise_damage_taken_mult", "elemental_resist_add", "heal_received_mult",
	"outgoing_damage_mult", "heavy_damage_mult", "throw_damage_mult", "magic_damage_mult",
	"outgoing_poise_mult", "grab_reach_add", "stamina_cost_mult", "essence_cost_mult", "cooldown_mult",
	"fury_gain_mult", "fury_on_kill_add", "move_speed_mult"]


# --------------------------------------------------------------------------- records and tiers

## True for the keys that combine by product (the "_mult" keys); the others add.
static func is_product_key(key: String) -> bool:
	return key.ends_with("_mult")


## The record of talent `id` ({} when it is no talent record).
static func record(id: String) -> Dictionary:
	var rec := GameData.get_record(id)
	return rec if str(rec.get("type", "")) == "talent" else {}


## The levels at which tiers 1-5 open (the progression record's talent_tier_levels).
static func tier_levels(rec: Dictionary = {}) -> Array:
	var r := rec if not rec.is_empty() else Progression.record()
	var levels: Variant = r.get("talent_tier_levels")
	if typeof(levels) != TYPE_ARRAY or (levels as Array).size() < TIER_COUNT:
		return DEFAULT_TIER_LEVELS.duplicate()
	var out: Array = []
	for v: Variant in levels:
		out.append(int(v) if SchemaUtil.is_number(v) else 1)
	return out


## The level tier `tier` opens at (tier 1: 6).
static func tier_level(tier: int, rec: Dictionary = {}) -> int:
	var levels := tier_levels(rec)
	return int(levels[clampi(tier, 1, levels.size()) - 1])


## Every talent id of `tree` ("" = every tree), in tree order, then tier, column and id.
static func ids(tree: String = "") -> Array:
	var rows: Array = []
	for id in GameData.ids_of_type("talent"):
		var rec := GameData.get_record(id)
		var t := str(rec.get("tree", ""))
		if tree != "" and t != tree:
			continue
		rows.append([TREES.find(t), int(rec.get("tier", 1)), int(rec.get("column", 0)), id])
	rows.sort()
	var out: Array = []
	for r: Array in rows:
		out.append(str(r[3]))
	return out


## The talents of `tree` at `tier`, by column ([] when none).
static func at_tier(tree: String, tier: int) -> Array:
	var out: Array = []
	for id in ids(tree):
		if int(record(id).get("tier", 0)) == tier:
			out.append(id)
	return out


static func display_name(id: String) -> String:
	var rec := record(id)
	return str(rec.get("display_name", id)) if not rec.is_empty() else id


static func tree_of(id: String) -> String:
	return str(record(id).get("tree", ""))


static func tier_of(id: String) -> int:
	return int(record(id).get("tier", 1))


static func cost_of(id: String) -> int:
	return maxi(1, int(record(id).get("cost", 1)))


static func requires_of(id: String) -> Array:
	var r: Variant = record(id).get("requires", [])
	return (r as Array).duplicate() if typeof(r) == TYPE_ARRAY else []


static func effects_of(id: String) -> Dictionary:
	var e: Variant = record(id).get("effects", {})
	return e if typeof(e) == TYPE_DICTIONARY else {}


static func modifiers_of(id: String) -> Dictionary:
	var m: Variant = effects_of(id).get("modifiers", {})
	return m if typeof(m) == TYPE_DICTIONARY else {}


static func grants_of(id: String) -> Array:
	var g: Variant = effects_of(id).get("grants", [])
	return (g as Array).duplicate() if typeof(g) == TYPE_ARRAY else []


static func replaces_of(id: String) -> Dictionary:
	var r: Variant = effects_of(id).get("replaces", {})
	return r if typeof(r) == TYPE_DICTIONARY else {}


## The character level talent `id` needs: its tier's level (or its requires_level when higher).
static func level_needed(id: String, rec: Dictionary = {}) -> int:
	var t := record(id)
	return maxi(tier_level(int(t.get("tier", 1)), rec), int(t.get("requires_level", 1)))


# --------------------------------------------------------------------------- learning

## Whether a character ({"level", "talent_points", "talents"}) can learn `id` now:
## {ok, reason (LEARN_REASONS, "" when ok), message}. The first refusal in order: unknown, known,
## level, requires, points.
static func check(character: Dictionary, id: String, rec: Dictionary = {}) -> Dictionary:
	var t := record(id)
	if t.is_empty():
		return _fail("unknown", "There is no talent '%s'." % id)
	var learned := talents_of(character)
	if learned.has(id):
		return _fail("known", "You already know %s." % display_name(id))
	var need := level_needed(id, rec)
	if int(character.get("level", 1)) < need:
		return _fail("level", "%s opens at level %d." % [display_name(id), need])
	var missing: Array = []
	for r: Variant in requires_of(id):
		if not learned.has(str(r)):
			missing.append(display_name(str(r)))
	if not missing.is_empty():
		return _fail("requires", "%s needs %s first." % [display_name(id), " and ".join(missing)])
	var cost := cost_of(id)
	var points := maxi(0, int(character.get("talent_points", 0)))
	if points < cost:
		return _fail("points", "%s costs %d talent point%s (you have %d)." % [display_name(id), cost,
			"" if cost == 1 else "s", points])
	return {"ok": true, "reason": "", "message": ""}


## Learns `id` in `character` (in place): the talent joins "talents" and its cost leaves
## "talent_points", once. {ok, reason, message, spent}; nothing changes when refused.
static func learn(character: Dictionary, id: String, rec: Dictionary = {}) -> Dictionary:
	var r := check(character, id, rec)
	if not r.ok:
		r["spent"] = 0
		return r
	var cost := cost_of(id)
	var learned := talents_of(character)
	learned.append(id)
	character["talents"] = learned
	character["talent_points"] = maxi(0, int(character.get("talent_points", 0))) - cost
	return {"ok": true, "reason": "", "message": "Learned %s." % display_name(id), "spent": cost}


## The learned talent ids of a character dictionary (a copy; non-strings left out).
static func talents_of(character: Dictionary) -> Array:
	var out: Array = []
	var raw: Variant = character.get("talents", [])
	if typeof(raw) == TYPE_ARRAY:
		for v: Variant in raw:
			if typeof(v) == TYPE_STRING and str(v) != "" and not out.has(str(v)):
				out.append(str(v))
	return out


## Points spent on `talents` (their costs).
static func points_spent(talents: Array) -> int:
	var n := 0
	for id: Variant in talents:
		if not record(str(id)).is_empty():
			n += cost_of(str(id))
	return n


## The talent points a character has earned in all at `level` (one per level from level 2).
static func points_at_level(level: int, rec: Dictionary = {}) -> int:
	return maxi(0, level - 1) * Progression.talent_points_per_level(rec)


## Every point a tree's talents cost together (a whole tree: 10).
static func tree_cost(tree: String) -> int:
	var n := 0
	for id in ids(tree):
		n += cost_of(id)
	return n


static func _fail(reason: String, message: String) -> Dictionary:
	return {"ok": false, "reason": reason, "message": message}


# --------------------------------------------------------------------------- passives

## Adds `mods` into `into`: "_mult" keys multiply, the others add.
static func combine(into: Dictionary, mods: Dictionary) -> void:
	for key: Variant in mods:
		var k := str(key)
		if not SchemaUtil.is_number(mods[key]):
			continue
		var v := float(mods[key])
		if is_product_key(k):
			into[k] = float(into.get(k, 1.0)) * v
		else:
			into[k] = float(into.get(k, 0.0)) + v


## The passives of learned `talents` and `ancestry`: {"modifiers": {key: value}, "resistances":
## {damage type: added resistance}}. Unknown talents count for nothing.
static func passives_for(talents: Array, ancestry: String) -> Dictionary:
	var mods := {}
	var res := {}
	for id: Variant in talents:
		combine(mods, modifiers_of(str(id)))
	var anc := ancestry_record(ancestry)
	if not anc.is_empty():
		var am: Variant = anc.get("modifiers", {})
		if typeof(am) == TYPE_DICTIONARY:
			combine(mods, am)
		var ar: Variant = anc.get("resistances", {})
		if typeof(ar) == TYPE_DICTIONARY:
			for t: Variant in ar:
				if SchemaUtil.is_number(ar[t]) and float(ar[t]) != 0.0:
					res[str(t)] = float(res.get(str(t), 0.0)) + float(ar[t])
	return {"modifiers": mods, "resistances": res}


## The schema check of a talent's or an ancestry's modifiers (both schema modules call it): never
## heal_per_tick or slow_fraction (periodic heals and slows are statuses), every "_mult" above 0.
static func check_passive_modifiers(mods: Variant, ctx: String, out: Dictionary) -> void:
	if typeof(mods) != TYPE_DICTIONARY:
		return
	for key: Variant in mods:
		var k := str(key)
		if NON_PASSIVE_KEYS.has(k):
			out.errors.append("%s.%s: a passive cannot heal over time or slow (that is a status)" % [ctx, k])
		elif is_product_key(k) and SchemaUtil.is_number(mods[key]) and float(mods[key]) <= 0.0:
			out.errors.append("%s.%s: a multiplier must be above 0 (got %s)" % [ctx, k, mods[key]])


## "Heavy attack damage +10%", "Armour +15", "Grab reach +1.5 m", "Stamina costs -15%".
static func modifier_line(key: String, value: float) -> String:
	var info: Array = KEY_TEXT.get(key, [key.capitalize(), "flat"])
	var label := str(info[0])
	match str(info[1]):
		"pct":
			return "%s %s" % [label, _signed_pct((value - 1.0) * 100.0)]
		"flat_pct":
			return "%s %s" % [label, _signed_pct(value * 100.0)]
		"m":
			return "%s %s m" % [label, _signed(value)]
	return "%s %s" % [label, _signed(value)]


## One line per modifier of `mods` (KEY_ORDER first), leaving out the neutral ones.
static func modifier_lines(mods: Dictionary) -> PackedStringArray:
	var out := PackedStringArray()
	var keys: Array = []
	for k: String in KEY_ORDER:
		if mods.has(k):
			keys.append(k)
	for k: Variant in mods:
		if not keys.has(str(k)):
			keys.append(str(k))
	for k: String in keys:
		if not SchemaUtil.is_number(mods[k]):
			continue
		var v := float(mods[k])
		if (is_product_key(k) and is_equal_approx(v, 1.0)) or (not is_product_key(k) and is_zero_approx(v)):
			continue
		out.append(modifier_line(k, v))
	return out


## Everything talent `id` does, one line each: its passives, then "New ability: <name> - <what it
## does> (<cost>, <cooldown>)" for each ability it grants and "<new> takes <old>'s slot" for each
## replacement.
static func effect_lines(id: String) -> PackedStringArray:
	var out := modifier_lines(modifiers_of(id))
	for a: Variant in grants_of(id):
		out.append("New ability: " + ability_line(str(a)))
	var rep := replaces_of(id)
	for old: Variant in rep:
		out.append("%s takes the place of %s" % [_action_name(str(rep[old])), _action_name(str(old))])
	return out


## "Shoulder Charge - charge 12 m... (22 stamina, 9 s cooldown)" for an ability id.
static func ability_line(action_id: String) -> String:
	var def := GameData.get_action(action_id)
	if def == null:
		return action_id
	var text := def.display_name
	var desc := str(def.param("description", ""))
	var colon := desc.find(": ")
	if colon >= 0 and colon < 16:
		desc = desc.substr(colon + 2)   # "Destroyer: lower your shoulder..." -> "lower your shoulder..."
	if desc != "":
		text += " - " + desc.trim_suffix(".")
	var costs := PackedStringArray()
	if def.stamina_cost > 0.0:
		costs.append("%d stamina" % roundi(def.stamina_cost))
	if def.essence_cost > 0.0:
		costs.append("%d essence" % roundi(def.essence_cost))
	if def.cooldown_s > 0.0:
		costs.append("%s s cooldown" % _num_text(def.cooldown_s))
	if not costs.is_empty():
		text += " (%s)" % ", ".join(costs)
	return text


static func _action_name(id: String) -> String:
	var def := GameData.get_action(id)
	return def.display_name if def != null else id


static func _signed(v: float) -> String:
	return ("+" if v >= 0.0 else "-") + _num_text(absf(v))


static func _signed_pct(v: float) -> String:
	return _signed(v) + "%"


## 15 -> "15", 1.5 -> "1.5", 15.5 -> "15.5", 7.999999 -> "8".
static func _num_text(v: float) -> String:
	var r := snappedf(v, 0.1)
	if is_equal_approx(r, roundf(r)):
		return str(int(roundf(r)))
	return "%.1f" % r


# --------------------------------------------------------------------------- ancestries

## The ancestries a character can choose (every ancestry record but the neutral one), by id.
static func ancestry_ids() -> Array:
	var out: Array = []
	for id in GameData.ids_of_type("ancestry"):
		if id != NEUTRAL:
			out.append(id)
	return out


## The record of ancestry `id` ({} when it is no ancestry record).
static func ancestry_record(id: String) -> Dictionary:
	var rec := GameData.get_record(id)
	return rec if str(rec.get("type", "")) == "ancestry" else {}


static func is_choosable(id: String) -> bool:
	return id != NEUTRAL and not ancestry_record(id).is_empty()


## {attribute: points} the ancestry adds when chosen.
static func attribute_bonus_of(id: String) -> Dictionary:
	var out := {}
	var b: Variant = ancestry_record(id).get("attribute_bonus", {})
	if typeof(b) == TYPE_DICTIONARY:
		for k: Variant in b:
			if Progression.ATTRIBUTE_KEYS.has(str(k)) and SchemaUtil.is_number(b[k]):
				out[str(k)] = int(b[k])
	return out


static func signature_of(id: String) -> String:
	return str(ancestry_record(id).get("signature", ""))


static func dialogue_tags_of(id: String) -> PackedStringArray:
	var t: Variant = ancestry_record(id).get("dialogue_tags", [])
	return PackedStringArray(t) if typeof(t) == TYPE_ARRAY else PackedStringArray()


## What ancestry `id` gives, as lines for the Ancestry tab and screen: {"name", "description",
## "attributes" ("Constitution +3, Endurance +2"), "passives" (modifier lines and resistances),
## "signature" (ability_line), "peoples" (dialogue_note)}.
static func ancestry_summary(id: String) -> Dictionary:
	var rec := ancestry_record(id)
	var attrs := PackedStringArray()
	var bonus := attribute_bonus_of(id)
	for key: String in Progression.ATTRIBUTE_KEYS:
		if int(bonus.get(key, 0)) != 0:
			attrs.append("%s %s" % [Progression.attribute_name(key), _signed(float(bonus[key]))])
	var passives := PackedStringArray()
	var p := passives_for([], id)
	passives.append_array(modifier_lines(p.modifiers))
	for t: Variant in p.resistances:
		passives.append("%s resistance %s" % [str(t).capitalize(), _signed_pct(float(p.resistances[t]) * 100.0)])
	var sig := signature_of(id)
	return {"name": str(rec.get("display_name", id)), "description": str(rec.get("description", "")),
		"attributes": ", ".join(attrs), "passives": passives,
		"signature": ability_line(sig) if sig != "" else "", "signature_id": sig,
		"peoples": str(rec.get("dialogue_note", ""))}


# --------------------------------------------------------------------------- data checks

## Cross-record checks (GameData post-pass, anchor P33):
##   * the progression record's talent_tier_levels: one level per tier, rising, within the cap;
##   * each talent's requires_level is its tier's level, its requirements are talents of its own
##     tree in lower tiers, at most two talents share a tree and tier and no two a column;
##   * a granted ability is an ability with granted_by "talent", in the library, open at the
##     talent's level; every ability with granted_by "talent" is granted by exactly one talent;
##   * a choosable ancestry has a signature with granted_by "ancestry" in the library, and every
##     ability with granted_by "ancestry" is exactly one ancestry's signature.
static func data_errors(records: Dictionary, record_paths: Dictionary = {}) -> PackedStringArray:
	var out := PackedStringArray()
	var prog: Dictionary = records.get(Progression.RECORD_ID, {})
	var lib: Array = prog.get("ability_library", []) if typeof(prog.get("ability_library")) == TYPE_ARRAY else []
	var cap := int(prog.get("level_cap", 20))
	var pctx := "%s (%s)" % [record_paths.get(Progression.RECORD_ID, "?"), Progression.RECORD_ID]
	var talent_ids: Array = []
	var ancestry_ids_: Array = []
	for id: Variant in records:
		match str((records[id] as Dictionary).get("type", "")):
			"talent":
				talent_ids.append(str(id))
			"ancestry":
				ancestry_ids_.append(str(id))
	talent_ids.sort()
	ancestry_ids_.sort()
	var levels: Variant = prog.get("talent_tier_levels")
	if typeof(levels) != TYPE_ARRAY:
		if not talent_ids.is_empty():
			out.append("%s: talent_tier_levels is missing (one level per talent tier, 1-%d)" % [pctx, TIER_COUNT])
		levels = DEFAULT_TIER_LEVELS
	elif (levels as Array).size() != TIER_COUNT:
		out.append("%s: talent_tier_levels must list %d levels (tiers 1-%d), got %d" % [pctx, TIER_COUNT,
			TIER_COUNT, (levels as Array).size()])
		levels = DEFAULT_TIER_LEVELS
	else:
		for i in range(TIER_COUNT):
			var lv := int(levels[i])
			if lv < 1 or lv > cap:
				out.append("%s: talent_tier_levels[%d] = %d is outside levels 1-%d" % [pctx, i, lv, cap])
			if i > 0 and lv < int(levels[i - 1]):
				out.append("%s: talent_tier_levels must rise (tier %d opens at %d, before tier %d at %d)" % [
					pctx, i + 1, lv, i, int(levels[i - 1])])
	var granted_by_talent := {}   # action id -> [talent ids]
	var slots := {}               # "tree/tier/column" -> talent id
	var per_tier := {}            # "tree/tier" -> count
	for id: String in talent_ids:
		var t: Dictionary = records[id]
		var ctx := "%s (%s)" % [record_paths.get(id, "?"), id]
		var tree := str(t.get("tree", ""))
		var tier := clampi(int(t.get("tier", 1)), 1, TIER_COUNT)
		var tier_lv := int((levels as Array)[tier - 1])
		if t.has("requires_level") and int(t.requires_level) != tier_lv:
			out.append("%s: requires_level %d, but tier %d opens at level %d (talent_tier_levels)" % [ctx,
				int(t.requires_level), tier, tier_lv])
		var tier_key := "%s/%d" % [tree, tier]
		per_tier[tier_key] = int(per_tier.get(tier_key, 0)) + 1
		if int(per_tier[tier_key]) > 2:
			out.append("%s: a tree has at most two talents per tier (%s tier %d has more)" % [ctx, tree, tier])
		var slot_key := "%s/%d" % [tier_key, int(t.get("column", 0))]
		if slots.has(slot_key):
			out.append("%s: column %d of %s tier %d is %s's already" % [ctx, int(t.get("column", 0)), tree, tier,
				slots[slot_key]])
		slots[slot_key] = id
		var reqs: Variant = t.get("requires", [])
		if typeof(reqs) == TYPE_ARRAY:
			for r: Variant in reqs:
				var req: Dictionary = records.get(str(r), {})
				if str(req.get("type", "")) != "talent":
					continue   # a missing or mistyped reference is a validation error already
				if str(req.get("tree", "")) != tree:
					out.append("%s: requires %s of another tree (%s)" % [ctx, str(r), str(req.get("tree", ""))])
				elif int(req.get("tier", 1)) >= tier:
					out.append("%s: requires %s, which is not in a lower tier" % [ctx, str(r)])
		var eff: Dictionary = t.get("effects", {}) if typeof(t.get("effects")) == TYPE_DICTIONARY else {}
		var grants: Variant = eff.get("grants", [])
		if typeof(grants) == TYPE_ARRAY:
			for g: Variant in grants:
				var a: Dictionary = records.get(str(g), {})
				if str(a.get("type", "")) != "action":
					continue
				(granted_by_talent.get_or_add(str(g), []) as Array).append(id)
				if str(a.get("kind", "")) != "ability":
					out.append("%s: grants %s, a %s action (a talent grants abilities)" % [ctx, str(g), str(a.get("kind", ""))])
				if str(a.get("granted_by", "")) != "talent":
					out.append("%s: grants %s, whose granted_by is '%s' (talent abilities say \"talent\")" % [ctx,
						str(g), str(a.get("granted_by", ""))])
				if not lib.has(str(g)):
					out.append("%s: grants %s, which is not in %s's ability_library" % [ctx, str(g), Progression.RECORD_ID])
				if int(a.get("unlock_level", 1)) > tier_lv:
					out.append("%s: grants %s, which unlocks at level %d, after the talent's level %d" % [ctx,
						str(g), int(a.get("unlock_level", 1)), tier_lv])
		var reps: Variant = eff.get("replaces", {})
		if typeof(reps) == TYPE_DICTIONARY:
			for old: Variant in reps:
				if not lib.has(str(reps[old])):
					out.append("%s: replaces %s with %s, which is not in the ability_library" % [ctx, str(old), str(reps[old])])
	var signatures := {}   # action id -> [ancestry ids]
	for id: String in ancestry_ids_:
		if id == NEUTRAL:
			continue
		var anc: Dictionary = records[id]
		var ctx := "%s (%s)" % [record_paths.get(id, "?"), id]
		var sig := str(anc.get("signature", ""))
		if sig == "":
			out.append("%s: a choosable ancestry needs a signature ability" % ctx)
			continue
		var a: Dictionary = records.get(sig, {})
		if str(a.get("type", "")) != "action":
			continue
		(signatures.get_or_add(sig, []) as Array).append(id)
		if str(a.get("granted_by", "")) != "ancestry":
			out.append("%s: its signature %s has granted_by '%s' (ancestry abilities say \"ancestry\")" % [ctx,
				sig, str(a.get("granted_by", ""))])
		if not lib.has(sig):
			out.append("%s: its signature %s is not in %s's ability_library" % [ctx, sig, Progression.RECORD_ID])
	var action_ids: Array = []
	for id: Variant in records:
		if str((records[id] as Dictionary).get("type", "")) == "action":
			action_ids.append(str(id))
	action_ids.sort()
	for id: String in action_ids:
		var by := str((records[id] as Dictionary).get("granted_by", ""))
		var ctx := "%s (%s)" % [record_paths.get(id, "?"), id]
		if by == "talent" and (granted_by_talent.get(id, []) as Array).size() != 1:
			out.append("%s: granted_by talent, but %d talents grant it (exactly one should)" % [ctx,
				(granted_by_talent.get(id, []) as Array).size()])
		elif by == "ancestry" and (signatures.get(id, []) as Array).size() != 1:
			out.append("%s: granted_by ancestry, but it is the signature of %d ancestries (exactly one should)" % [ctx,
				(signatures.get(id, []) as Array).size()])
	return out
