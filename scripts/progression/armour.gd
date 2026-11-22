class_name Armour
extends RefCounted
## Functional armour (B1; docs/systems/B1.md): the rules over the giant's equipment - the armour pieces it owns, the
## one worn in each of the seven slots, each piece's tier and perk, and which worn pieces it shows - and what they do.
## Pure: plain dictionaries in and out, read from GameData's records (armour, armour_set, armour_perk); the live
## state is GameSession.expansion.equipment (save schema 3's reserved field, ExpansionState), written by the
## Character menu's Equipment tab (equip, unequip, show / hide) and the forge (craft, refit, perk: Forge).
##
##   {"slots": {head, shoulders, chest, arms, waist, legs, trinket: armour id or ""},
##    "pieces": {armour id: {"tier": 1-3, "perk": armour_perk id or ""}},     what the giant owns
##    "hidden": {slot: true}}                                                 worn but not shown (still counts)
##
## What worn armour does (modifiers -> PlayerProgression.rebuild_passives -> Combatant.set_passives, beside the
## talents' and the ancestry's: never statuses):
##   * defence.physical: armour points (armor_flat) x the tier's TIER_MULT - a blow keeps 100 / (100 + A) of its
##     physical damage (DamageResolver.mitigate), so the same armour turns the same share at every stage: armour
##     scales with the giant (its mesh is skinned to his skeleton, its numbers are shares);
##   * the elemental defences: resistances added (x the tier);
##   * poise: added to the poise threshold (x the tier; a giant's threshold is the same at every stage, the blows'
##     poise scales with the sizes: CombatRules.poise_scale);
##   * a piece's own modifiers and its perk's (an authored list per piece, chosen at a forge, never rolled);
##   * the set bonuses (armour_set.bonuses: N pieces of one set worn);
##   * weight: the worn pieces' sum less WEIGHT_FREE slows stamina recovery by WEIGHT_STEP a point
##     (stamina_regen_mult), at most WEIGHT_MAX_SLOW.
## Without armour every value is neutral (no key at all), so an unarmoured giant's numbers are exactly as before.
##
## The look (look_of, dress): a worn, shown piece's wardrobe garments replace what the giant's own look wears in those
## cosmetic slots, and a modelled piece (the Quarry set's stone: giant index meshes) is added with the cosmetic slots
## it covers emptied - drawn over the record, never written into it: character.appearance (the creator's, its own
## cosmetic `armour` slot included) is untouched. A slot's own piece wins a cosmetic slot another worn piece's
## garments also name (the hooded mantle's hood gives way to a worn helm).

const SLOTS := ["head", "shoulders", "chest", "arms", "waist", "legs", "trinket"]
const SLOT_NAMES := {"head": "Head", "shoulders": "Shoulders", "chest": "Chest", "arms": "Arms", "waist": "Waist",
	"legs": "Legs", "trinket": "Trinket"}
## The cosmetic garment slot each armour slot draws in first (a piece's own slot wins these; Appearance.SLOTS).
const OWN_COSMETIC := {"head": "head", "shoulders": "shoulders", "chest": "armour", "arms": "arms", "waist": "waist",
	"legs": "shins"}
const MAX_TIER := 3
## A piece's defence and poise at tiers 1, 2 and 3.
const TIER_MULT := [1.0, 1.15, 1.3]
const TIER_NAMES := ["", "", "Reforged", "Masterwork"]
## The weight a giant's frame carries free, the stamina recovery lost per point above it, and the most it loses.
const WEIGHT_FREE := 3.0
const WEIGHT_STEP := 0.02
const WEIGHT_MAX_SLOW := 0.25
## Why a piece cannot be put on or taken off now ("" = it can).
const BLOCK_FIGHT := "Not in a fight: armour is put on and taken off out of combat."


# --------------------------------------------------------------------------- the state

## An empty equipment state.
static func empty() -> Dictionary:
	var slots := {}
	for s: String in SLOTS:
		slots[s] = ""
	return {"slots": slots, "pieces": {}, "hidden": {}}


## `raw` (a save's equipment block) with every key: unknown slots dropped, a slot's piece kept only when it is a
## known armour record of that slot and owned (a worn piece is owned: one worn but not listed is added at tier 1),
## tiers clamped to 1-3, a perk kept only when the piece's list has it.
static func normalized(raw: Variant) -> Dictionary:
	var out := empty()
	if typeof(raw) != TYPE_DICTIONARY:
		return out
	var r: Dictionary = raw
	if typeof(r.get("pieces")) == TYPE_DICTIONARY:
		for id: Variant in r.pieces:
			var rec := piece(str(id))
			if rec.is_empty():
				continue
			var p: Variant = r.pieces[id]
			var tier := 1
			var perk := ""
			if typeof(p) == TYPE_DICTIONARY:
				tier = clampi(int(p.get("tier", 1)) if SchemaUtil.is_number(p.get("tier")) else 1, 1, MAX_TIER)
				perk = str(p.get("perk", "")) if typeof(p.get("perk")) == TYPE_STRING else ""
				if perk != "" and not (rec.get("perks", []) as Array).has(perk):
					perk = ""
			out.pieces[str(id)] = {"tier": tier, "perk": perk}
	if typeof(r.get("slots")) == TYPE_DICTIONARY:
		for s: String in SLOTS:
			var id := str(r.slots.get(s, "")) if typeof(r.slots.get(s, "")) == TYPE_STRING else ""
			var rec := piece(id)
			if id == "" or rec.is_empty() or str(rec.get("slot", "")) != s:
				continue
			out.slots[s] = id
			if not out.pieces.has(id):
				out.pieces[id] = {"tier": 1, "perk": ""}
	if typeof(r.get("hidden")) == TYPE_DICTIONARY:
		for s: String in SLOTS:
			if r.hidden.get(s, false) == true:
				out.hidden[s] = true
	return out


## An equipment state wearing `ids` (owned at tier 1) with `hidden` slots hidden: tools and tests.
static func equipment_with(ids: Array, hidden: Array = []) -> Dictionary:
	var eq := empty()
	for id: Variant in ids:
		var rec := piece(str(id))
		if rec.is_empty():
			continue
		eq.pieces[str(id)] = {"tier": 1, "perk": ""}
		eq.slots[str(rec.slot)] = str(id)
	for s: Variant in hidden:
		eq.hidden[str(s)] = true
	return eq


# --------------------------------------------------------------------------- the records

static func piece(id: String) -> Dictionary:
	if id == "":
		return {}
	var rec := GameData.get_record(id)
	return rec if str(rec.get("type", "")) == "armour" else {}


static func set_record(id: String) -> Dictionary:
	var rec := GameData.get_record(id)
	return rec if str(rec.get("type", "")) == "armour_set" else {}


static func perk(id: String) -> Dictionary:
	var rec := GameData.get_record(id) if id != "" else {}
	return rec if str(rec.get("type", "")) == "armour_perk" else {}


## A set's pieces in its own order.
static func set_pieces(set_id: String) -> Array:
	return (set_record(set_id).get("pieces", []) as Array).duplicate()


## Every armour set id, sorted.
static func set_ids() -> PackedStringArray:
	var ids := GameData.ids_of_type("armour_set")
	ids.sort()
	return ids


## Every armour piece of `slot` (in its set's order, the sets by id).
static func pieces_for_slot(slot: String) -> Array:
	var out: Array = []
	for sid: String in set_ids():
		for id: Variant in set_pieces(sid):
			if str(piece(str(id)).get("slot", "")) == slot:
				out.append(str(id))
	return out


static func display_name(id: String) -> String:
	var rec := GameData.get_record(id)
	return str(rec.get("display_name", id))


## "Quarry Pauldrons", "Reforged Quarry Pauldrons" (tier 2), "Masterwork ..." (tier 3).
static func piece_name(id: String, tier: int) -> String:
	var n := display_name(id)
	return n if tier <= 1 else "%s %s" % [TIER_NAMES[clampi(tier, 1, MAX_TIER)], n]


# --------------------------------------------------------------------------- what is worn

## The worn pieces: [{"slot", "id", "rec", "tier", "perk", "hidden"}] in slot order.
static func worn(eq: Dictionary) -> Array:
	var out: Array = []
	var slots: Dictionary = eq.get("slots", {})
	var pieces: Dictionary = eq.get("pieces", {})
	var hidden: Dictionary = eq.get("hidden", {})
	for s: String in SLOTS:
		var id := str(slots.get(s, ""))
		var rec := piece(id)
		if rec.is_empty():
			continue
		var p: Dictionary = pieces.get(id, {}) if typeof(pieces.get(id)) == TYPE_DICTIONARY else {}
		out.append({"slot": s, "id": id, "rec": rec, "tier": clampi(int(p.get("tier", 1)), 1, MAX_TIER),
			"perk": str(p.get("perk", "")), "hidden": bool(hidden.get(s, false))})
	return out


## {set id: worn pieces of it}.
static func set_counts(eq: Dictionary) -> Dictionary:
	var out := {}
	for w: Dictionary in worn(eq):
		var sid := str((w.rec as Dictionary).get("set", ""))
		out[sid] = int(out.get(sid, 0)) + 1
	return out


## The set bonuses earned now: [{"set", "set_name", "pieces", "name", "text", "modifiers", "active"}] for every bonus
## of every set with a piece worn (active: enough pieces), in set and count order.
static func bonuses(eq: Dictionary) -> Array:
	var out: Array = []
	var counts := set_counts(eq)
	var sids: Array = counts.keys()
	sids.sort()
	for sid: Variant in sids:
		var srec := set_record(str(sid))
		for b: Variant in srec.get("bonuses", []):
			if typeof(b) != TYPE_DICTIONARY:
				continue
			out.append({"set": str(sid), "set_name": str(srec.get("display_name", sid)), "pieces": int(b.pieces),
				"worn": int(counts[sid]), "name": str(b.get("name", "")), "text": str(b.get("text", "")),
				"modifiers": b.get("modifiers", {}), "active": int(counts[sid]) >= int(b.pieces)})
	return out


static func weight(eq: Dictionary) -> float:
	var w := 0.0
	for p: Dictionary in worn(eq):
		w += float((p.rec as Dictionary).get("weight", 0.0))
	return w


## The stamina recovery multiplier of `w` worn weight (1.0 at WEIGHT_FREE or less).
static func weight_mult(w: float) -> float:
	return 1.0 - minf(WEIGHT_MAX_SLOW, WEIGHT_STEP * maxf(0.0, w - WEIGHT_FREE))


## The passives of the worn armour: {"modifiers": {STATUS_MODIFIERS key: value}, "resistances": {type: share}}
## (Talents.combine's rules: "_mult" keys multiply, the others add). {} and {} unarmoured.
static func modifiers(eq: Dictionary) -> Dictionary:
	var mods := {}
	var res := {}
	var list := worn(eq)
	for p: Dictionary in list:
		var rec: Dictionary = p.rec
		var tm := float(TIER_MULT[int(p.tier) - 1])
		var dfn: Dictionary = rec.get("defence", {}) if typeof(rec.get("defence")) == TYPE_DICTIONARY else {}
		for t: Variant in dfn:
			var v := float(dfn[t]) * tm
			if v == 0.0:
				continue
			if str(t) == "physical":
				Talents.combine(mods, {"armor_flat": v})
			else:
				res[str(t)] = float(res.get(str(t), 0.0)) + v
		if float(rec.get("poise", 0.0)) > 0.0:
			Talents.combine(mods, {"poise_threshold_add": float(rec.poise) * tm})
		if typeof(rec.get("modifiers")) == TYPE_DICTIONARY:
			Talents.combine(mods, rec.modifiers)
		var pk := perk(str(p.perk))
		if not pk.is_empty():
			if typeof(pk.get("modifiers")) == TYPE_DICTIONARY:
				Talents.combine(mods, pk.modifiers)
			if typeof(pk.get("resistances")) == TYPE_DICTIONARY:
				for t: Variant in pk.resistances:
					res[str(t)] = float(res.get(str(t), 0.0)) + float(pk.resistances[t])
	for b: Dictionary in bonuses(eq):
		if bool(b.active) and typeof(b.modifiers) == TYPE_DICTIONARY:
			Talents.combine(mods, b.modifiers)
	if not list.is_empty():
		var wm := weight_mult(weight(eq))
		if wm != 1.0:
			Talents.combine(mods, {"stamina_regen_mult": wm})
	return {"modifiers": mods, "resistances": res}


## `a` and `b` passives ({"modifiers", "resistances"}) combined.
static func merged(a: Dictionary, b: Dictionary) -> Dictionary:
	var mods: Dictionary = (a.get("modifiers", {}) as Dictionary).duplicate()
	Talents.combine(mods, b.get("modifiers", {}))
	var res: Dictionary = (a.get("resistances", {}) as Dictionary).duplicate()
	var br: Dictionary = b.get("resistances", {})
	for t: Variant in br:
		res[str(t)] = float(res.get(str(t), 0.0)) + float(br[t])
	return {"modifiers": mods, "resistances": res}


## The numbers a giant with `base` passives (its talents' and ancestry's: Talents.passives_for) has wearing `eq`:
## {"armour", "kept" (the share of a physical blow kept: 100 / (100 + armour)), "less_pct" (the share turned, %),
## "poise" (the threshold added), "weight", "stamina_regen" (x), "stamina_cost" (x), "move" (x), "health" (+),
## "resist": {type: share}} - the Equipment tab's comparison.
static func stats(eq: Dictionary, base: Dictionary = {}) -> Dictionary:
	var all := merged(base, modifiers(eq))
	var m: Dictionary = all.modifiers
	var a := float(m.get("armor_flat", 0.0))
	var kept := 100.0 / (100.0 + maxf(0.0, a))
	return {"armour": a, "kept": kept, "less_pct": (1.0 - kept) * 100.0,
		"poise": float(m.get("poise_threshold_add", 0.0)), "weight": weight(eq),
		"stamina_regen": float(m.get("stamina_regen_mult", 1.0)), "stamina_cost": float(m.get("stamina_cost_mult", 1.0)),
		"move": float(m.get("move_speed_mult", 1.0)), "health": float(m.get("health_add", 0.0)),
		"poise_taken": float(m.get("poise_damage_taken_mult", 1.0)), "resist": all.resistances}


# --------------------------------------------------------------------------- changing it

## `id` owned (a forge made it): tier 1, no perk. False when it was owned already or is not an armour record.
static func grant(eq: Dictionary, id: String) -> bool:
	if piece(id).is_empty() or (eq.get("pieces", {}) as Dictionary).has(id):
		return false
	eq["pieces"][id] = {"tier": 1, "perk": ""}
	return true


static func owns(eq: Dictionary, id: String) -> bool:
	return (eq.get("pieces", {}) as Dictionary).has(id)


static func tier_of(eq: Dictionary, id: String) -> int:
	var p: Variant = (eq.get("pieces", {}) as Dictionary).get(id)
	return clampi(int((p as Dictionary).get("tier", 1)), 1, MAX_TIER) if typeof(p) == TYPE_DICTIONARY else 0


static func perk_of(eq: Dictionary, id: String) -> String:
	var p: Variant = (eq.get("pieces", {}) as Dictionary).get(id)
	return str((p as Dictionary).get("perk", "")) if typeof(p) == TYPE_DICTIONARY else ""


## Wears owned piece `id` in its slot (what was there goes back to the pieces owned). False when it is not owned.
static func equip(eq: Dictionary, id: String) -> bool:
	var rec := piece(id)
	if rec.is_empty() or not owns(eq, id):
		return false
	eq["slots"][str(rec.slot)] = id
	return true


## Takes off what `slot` wears. False when it wore nothing.
static func unequip(eq: Dictionary, slot: String) -> bool:
	if str((eq.get("slots", {}) as Dictionary).get(slot, "")) == "":
		return false
	eq["slots"][slot] = ""
	return true


## Shows or hides what `slot` wears (it counts either way).
static func set_hidden(eq: Dictionary, slot: String, hidden: bool) -> void:
	if not SLOTS.has(slot):
		return
	if hidden:
		eq["hidden"][slot] = true
	else:
		(eq["hidden"] as Dictionary).erase(slot)


static func is_hidden(eq: Dictionary, slot: String) -> bool:
	return bool((eq.get("hidden", {}) as Dictionary).get(slot, false))


static func set_tier(eq: Dictionary, id: String, tier: int) -> void:
	if owns(eq, id):
		eq["pieces"][id]["tier"] = clampi(tier, 1, MAX_TIER)


static func set_perk(eq: Dictionary, id: String, perk_id: String) -> bool:
	if not owns(eq, id) or (perk_id != "" and not (piece(id).get("perks", []) as Array).has(perk_id)):
		return false
	eq["pieces"][id]["perk"] = perk_id
	return true


## The refit step that takes owned piece `id` to its next tier ({} at MAX_TIER or for an unknown piece):
## {"tier", "cost", "forge_tier", "works"} (the set's refit list; a step's works else the set's).
static func next_refit(eq: Dictionary, id: String) -> Dictionary:
	var t := tier_of(eq, id)
	if t < 1 or t >= MAX_TIER:
		return {}
	var srec := set_record(str(piece(id).get("set", "")))
	for step: Variant in srec.get("refit", []):
		if typeof(step) == TYPE_DICTIONARY and int(step.get("tier", 0)) == t + 1:
			var out: Dictionary = (step as Dictionary).duplicate(true)
			if str(out.get("works", "")) == "":
				out["works"] = str(srec.get("works", ""))
			return out
	return {}


## What setting a perk on piece `id` costs (its set's perk_cost).
static func perk_cost(id: String) -> Array:
	return (set_record(str(piece(id).get("set", ""))).get("perk_cost", []) as Array).duplicate(true)


## The trait a forge must work for piece `id` (its set's "works"; "" = any forge).
static func works_of(id: String) -> String:
	return str(set_record(str(piece(id).get("set", ""))).get("works", ""))


# --------------------------------------------------------------------------- the look

## `record` (an appearance record) dressed in the worn, shown pieces of `eq`: a copy whose outfit slots show the pieces'
## wardrobe garments (in the piece's dye, its look's "dye") and empty the cosmetic slots and accessories a modelled
## piece covers (its look's "clears", "clears_accessories"); `record` itself is not changed. A piece in its own cosmetic
## slot (OWN_COSMETIC) wins it over another piece's extra garment (a worn helm over the hooded mantle's hood).
static func dress(record: Dictionary, eq: Dictionary) -> Dictionary:
	var list := worn(eq)
	if list.is_empty():
		return record
	var out := record.duplicate(true)
	if typeof(out.get("outfit")) != TYPE_DICTIONARY or typeof(out.outfit.get("slots")) != TYPE_DICTIONARY:
		return out
	var taken := {}
	for p: Dictionary in list:
		if bool(p.hidden):
			continue
		var look: Dictionary = (p.rec as Dictionary).get("look", {})
		for cs: Variant in look.get("clears", []):
			out.outfit.slots[str(cs)] = {"item": "", "dye": ""}
			taken[str(cs)] = true
		for a: Variant in look.get("clears_accessories", []):
			if typeof(out.outfit.get("accessories")) == TYPE_DICTIONARY:
				out.outfit.accessories[str(a)] = ""
	# a slot's own piece first, then the others' extra garments into the cosmetic slots still free
	for pass_own: bool in [true, false]:
		for p: Dictionary in list:
			if bool(p.hidden):
				continue
			var look: Dictionary = (p.rec as Dictionary).get("look", {})
			for g: Variant in look.get("garments", []):
				var cs := str(Appearance.option(str(g)).get("slot", ""))
				if cs == "" or taken.has(cs):
					continue
				if (str(OWN_COSMETIC.get(str(p.slot), "")) == cs) != pass_own:
					continue
				taken[cs] = true
				out.outfit.slots[cs] = {"item": str(g), "dye": str(look.get("dye", ""))}
	return out


## The modelled pieces (giant index meshes) the worn, shown pieces of `eq` add to a look ([] when none).
static func look_meshes(eq: Dictionary) -> Array:
	var out: Array = []
	for p: Dictionary in worn(eq):
		if bool(p.hidden):
			continue
		for m: Variant in ((p.rec as Dictionary).get("look", {}) as Dictionary).get("meshes", []):
			if not out.has(str(m)):
				out.append(str(m))
	return out


## The concrete look of `record` for a giant of `ancestry_id` wearing `eq` (Appearance.to_look of the dressed record,
## the modelled pieces among its accessories): what every renderer of the player's giant draws.
static func look_of(record: Dictionary, eq: Dictionary, ancestry_id := "") -> Dictionary:
	var look := Appearance.to_look(dress(record, eq), ancestry_id)
	var extra := look_meshes(eq)
	if not extra.is_empty():
		var acc: Array = (look.get("accessories", []) as Array).duplicate()
		for m: Variant in extra:
			if not acc.has(m):
				acc.append(m)
		look["accessories"] = acc
	return look


# --------------------------------------------------------------------------- when

## Why the giant cannot put armour on or take it off now ("" when it can): out of combat only - no fight engaged,
## no enemy hunting it, not grabbed, dead or mid-action (the checkpoint's own blockers, a menu aside).
static func change_blocked() -> String:
	for b: String in GameSession.checkpoint_blockers():
		if b != "screen":
			return BLOCK_FIGHT
	return ""


## The giant's passives and look again after its equipment changed (the Equipment tab, a forge, a load).
static func refresh_player(p: GiantPlayer) -> void:
	if p == null or not is_instance_valid(p):
		return
	if p.progression != null:
		p.progression.rebuild_passives()
	if p.appearance != null:
		p.appearance.refresh()
