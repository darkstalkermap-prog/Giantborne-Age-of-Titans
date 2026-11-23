class_name ExpansionState
extends RefCounted
## The open-world expansion's own save state (A4; save schema 3, SaveSlots._migrate_2_to_3): what the
## expansion needs now and what milestones B and C will fill, kept in real fields rather than in the world's
## generic flags. Pure: plain dictionaries in and out (GameSession holds the live copy as `expansion` and writes
## it into every checkpoint document; the Character menu reads it).
##
##   "act"              1 (act one; the throne ends it in milestone C)
##   "titans"           {titan id (the roster's): {"state": unseen | sighted | slain, "plates_broken_best",
##                      "kills", "first_sighted_play_s" (the session's play time then; -1 unknown),
##                      "first_sighted_unix" (0 unknown), "drops": [{"item", "count"}] (his loot table's, at
##                      the kill)}}; a titan never met has no entry
##   "equipment"        {"slots": {head, shoulders, chest, arms, waist, legs, trinket: armour id or ""},
##                      "pieces": {armour id: {"tier", "perk"}}, "hidden": {slot: true}} - the functional armour (B1:
##                      Armour's state; "pieces" and "hidden" are B1's within schema 3: optional, a schema-3 file
##                      without them has none, an A build reading a B1 file keeps its slots and drops them). Not the
##                      look's cosmetic `armour` slot (character.appearance), which stays what it is.
##   "settlements"      {settlement (its POI id): {"level": 0, "flags": {name: true}}}: the development state
##                      milestone C builds on; today the flags mirror what the world's flags say of it
##                      (SETTLEMENT_FLAGS: Millford's quarry reopened and freed, defended or burned)
##   "cinematics_seen"  the cutscene ids this game has played (the intro plays once, on a New Game: CutscenePlayer)
##
## The roster (data/titans/titan_roster.json) names the titans and the flags A3 wrote for Stoneback
## (boss.stoneback.outcome, boss.stoneback.defeated, discovered.stoneback_quarry), which the migration and
## every snapshot still read (sync_from_flags): the flags stay the game's own truth, the fields their record.

const ROSTER_ID := "titan_roster.signature"
const ARMOUR_SLOTS := ["head", "shoulders", "chest", "arms", "waist", "legs", "trinket"]
const STATE_UNSEEN := "unseen"
const STATE_SIGHTED := "sighted"
const STATE_SLAIN := "slain"
const TITAN_STATES := [STATE_UNSEEN, STATE_SIGHTED, STATE_SLAIN]
const ACT_DEFAULT := 1
## The world flags a settlement's record mirrors: [settlement, its field, the world flag].
const SETTLEMENT_FLAGS := [
	["poi.millford", "quarry_reopened", "world.quarry.reopened"],
	["poi.thornwick", "kings_trophies", "world.ogre_king.defeated"],   # B2: Thornwick after the Ogre King falls
	["poi.millford", "quarry_freed", "world.millford.quarry_freed"],
	["poi.millford", "defended", "world.millford.defended"],
	["poi.millford", "burned", "world.millford.burned"],
]
const INTRO_ID := "cutscene.intro"
const KEYS := ["act", "titans", "equipment", "settlements", "cinematics_seen"]


## A new game's state.
static func defaults() -> Dictionary:
	return {"act": ACT_DEFAULT, "titans": {}, "equipment": Armour.empty(), "settlements": {},
		"cinematics_seen": []}


## A titan's record with every field (a titan never met: unseen, nothing else).
static func titan_defaults() -> Dictionary:
	return {"state": STATE_UNSEEN, "plates_broken_best": 0, "kills": 0, "first_sighted_play_s": -1.0,
		"first_sighted_unix": 0, "drops": []}


# --------------------------------------------------------------------------- the roster

## The roster's titans in the story's order ([] without the record).
static func roster() -> Array:
	var rec := GameData.get_record(ROSTER_ID)
	return rec.get("titans", []) if typeof(rec.get("titans")) == TYPE_ARRAY else []


static func roster_entry(titan_id: String) -> Dictionary:
	for t: Dictionary in roster():
		if str(t.get("id", "")) == titan_id:
			return t
	return {}


## The roster's titan whose boss id (a BossArena's, an encounter's) or enemy id is `id` ("" when none).
static func titan_for(id: String) -> String:
	if id == "":
		return ""
	for t: Dictionary in roster():
		if str(t.get("enemy", "")) == id or (t.get("boss_ids", []) as Array).has(id):
			return str(t.id)
	return ""


# --------------------------------------------------------------------------- reading and writing a document

## The state a save document holds, normalised (a missing or mistyped key gets its default; titans the roster
## does not know are kept as they are - sanitize() drops them).
static func from_doc(doc: Dictionary) -> Dictionary:
	var out := defaults()
	if SchemaUtil.is_number(doc.get("act")):
		out.act = clampi(int(doc.act), 1, 3)
	if typeof(doc.get("titans")) == TYPE_DICTIONARY:
		for id: Variant in doc.titans:
			if typeof(doc.titans[id]) == TYPE_DICTIONARY:
				out.titans[str(id)] = _titan_from(doc.titans[id])
	var eq: Variant = doc.get("equipment")
	if typeof(eq) == TYPE_DICTIONARY and typeof((eq as Dictionary).get("slots")) == TYPE_DICTIONARY:
		for s: String in ARMOUR_SLOTS:
			var v: Variant = eq.slots.get(s, "")
			out.equipment.slots[s] = str(v) if typeof(v) == TYPE_STRING else ""
		# B1: the pieces owned (their tiers and perks) and the hidden slots, kept as they are (sanitize checks the ids)
		if typeof((eq as Dictionary).get("pieces")) == TYPE_DICTIONARY:
			for id: Variant in eq.pieces:
				var p: Variant = eq.pieces[id]
				var tier := 1
				var perk := ""
				if typeof(p) == TYPE_DICTIONARY:
					tier = clampi(int(p.get("tier", 1)) if SchemaUtil.is_number(p.get("tier")) else 1, 1, Armour.MAX_TIER)
					perk = str(p.get("perk", "")) if typeof(p.get("perk")) == TYPE_STRING else ""
				out.equipment.pieces[str(id)] = {"tier": tier, "perk": perk}
		if typeof((eq as Dictionary).get("hidden")) == TYPE_DICTIONARY:
			for s: String in ARMOUR_SLOTS:
				if eq.hidden.get(s, false) == true:
					out.equipment.hidden[s] = true
	if typeof(doc.get("settlements")) == TYPE_DICTIONARY:
		for id: Variant in doc.settlements:
			var st: Variant = doc.settlements[id]
			if typeof(st) != TYPE_DICTIONARY:
				continue
			var flags := {}
			if typeof((st as Dictionary).get("flags")) == TYPE_DICTIONARY:
				for k: Variant in st.flags:
					flags[str(k)] = bool(st.flags[k]) if typeof(st.flags[k]) == TYPE_BOOL else true
			out.settlements[str(id)] = {"level": int(st.get("level", 0)) if SchemaUtil.is_number(st.get("level")) else 0,
				"flags": flags}
	if typeof(doc.get("cinematics_seen")) == TYPE_ARRAY:
		for c: Variant in doc.cinematics_seen:
			if typeof(c) == TYPE_STRING and not (out.cinematics_seen as Array).has(str(c)):
				out.cinematics_seen.append(str(c))
	return out


static func _titan_from(raw: Dictionary) -> Dictionary:
	var t := titan_defaults()
	var state := str(raw.get("state", STATE_UNSEEN))
	t.state = state if state in TITAN_STATES else STATE_UNSEEN
	for k: String in ["plates_broken_best", "kills", "first_sighted_unix"]:
		if SchemaUtil.is_number(raw.get(k)):
			t[k] = maxi(0, int(raw[k]))
	if SchemaUtil.is_number(raw.get("first_sighted_play_s")):
		t.first_sighted_play_s = float(raw.first_sighted_play_s)
	if typeof(raw.get("drops")) == TYPE_ARRAY:
		for d: Variant in raw.drops:
			if typeof(d) == TYPE_DICTIONARY and typeof(d.get("item")) == TYPE_STRING:
				t.drops.append({"item": str(d.item), "count": maxi(1, int(d.get("count", 1)))})
	return t


## `doc` with the state's keys written in (a copy of each).
static func write_into(doc: Dictionary, state: Dictionary) -> Dictionary:
	for k: String in KEYS:
		doc[k] = (state.get(k) as Variant)
		if typeof(doc[k]) in [TYPE_DICTIONARY, TYPE_ARRAY]:
			doc[k] = doc[k].duplicate(true)
	return doc


## A schema-3 document's problems with these keys ([] when they load). Each key is optional (as the progress block
## is): a missing one is its default (from_doc), a present one must have its type.
static func validate(doc: Dictionary) -> PackedStringArray:
	var errors := PackedStringArray()
	if doc.has("act"):
		var act: Variant = doc.act
		if not SchemaUtil.is_number(act) or float(act) != floorf(float(act)) or int(act) < 1 or int(act) > 3:
			errors.append("act: must be a whole number from 1 to 3")
	if doc.has("titans"):
		if typeof(doc.titans) != TYPE_DICTIONARY:
			errors.append("titans: must be an object")
		else:
			for id: Variant in doc.titans:
				var t: Variant = doc.titans[id]
				if typeof(t) != TYPE_DICTIONARY:
					errors.append("titans.%s: must be an object" % str(id))
				elif typeof((t as Dictionary).get("state")) != TYPE_STRING or not (str(t.state) in TITAN_STATES):
					errors.append("titans.%s.state: must be one of %s" % [str(id), ", ".join(TITAN_STATES)])
	if doc.has("equipment"):
		var eq: Variant = doc.equipment
		if typeof(eq) != TYPE_DICTIONARY or typeof((eq as Dictionary).get("slots")) != TYPE_DICTIONARY:
			errors.append("equipment.slots: must be an object")
		else:
			for s: Variant in eq.slots:
				if typeof(eq.slots[s]) != TYPE_STRING:
					errors.append("equipment.slots.%s: must be a string" % str(s))
			if (eq as Dictionary).has("pieces") and typeof(eq.pieces) != TYPE_DICTIONARY:
				errors.append("equipment.pieces: must be an object")
			if (eq as Dictionary).has("hidden") and typeof(eq.hidden) != TYPE_DICTIONARY:
				errors.append("equipment.hidden: must be an object")
	if doc.has("settlements") and typeof(doc.settlements) != TYPE_DICTIONARY:
		errors.append("settlements: must be an object")
	if doc.has("cinematics_seen") and typeof(doc.cinematics_seen) != TYPE_ARRAY:
		errors.append("cinematics_seen: must be an array")
	return errors


## The titans the roster does not know are dropped (their ids returned): a later build's titan in an older
## build's hands. Equipment slots this build does not know go too; a slot's item this build does not know empties.
static func sanitize(state: Dictionary) -> PackedStringArray:
	var dropped := PackedStringArray()
	var titans: Dictionary = state.get("titans", {})
	for id: Variant in titans.keys():
		if roster_entry(str(id)).is_empty():
			titans.erase(id)
			dropped.append(str(id))
	var slots: Dictionary = (state.get("equipment", {}) as Dictionary).get("slots", {})
	for s: Variant in slots.keys():
		if not (str(s) in ARMOUR_SLOTS):
			slots.erase(s)
		elif str(slots[s]) != "" and not GameData.has_record(str(slots[s])):
			dropped.append(str(slots[s]))
			slots[s] = ""
	# B1: pieces this build does not know go (a later build's armour), the rest made whole (Armour.normalized: a worn
	# piece of another slot comes off, a perk not on its piece's list goes)
	var eq: Dictionary = state.get("equipment", {})
	var pieces: Dictionary = eq.get("pieces", {}) if typeof(eq.get("pieces")) == TYPE_DICTIONARY else {}
	for id: Variant in pieces.keys():
		if Armour.piece(str(id)).is_empty() and not dropped.has(str(id)):
			dropped.append(str(id))
	if not eq.is_empty():
		state["equipment"] = Armour.normalized(eq)
	return dropped


# --------------------------------------------------------------------------- the flags A3 wrote (migration, snapshots)

## Brings `state` into line with the world's flags (a v2 save's migration, every snapshot): a titan the roster
## says is slain by its outcome or defeated flag is slain (one kill at least), one whose ground was discovered
## is at least sighted; each settlement's mirrored flags (SETTLEMENT_FLAGS). Never lowers anything.
static func sync_from_flags(state: Dictionary, flags: Dictionary) -> Dictionary:
	var titans: Dictionary = state.titans
	for t: Dictionary in roster():
		var id := str(t.get("id", ""))
		var slain := false
		var of := str(t.get("outcome_flag", ""))
		if of != "" and str(flags.get(of, "")) == STATE_SLAIN:
			slain = true
		var df := str(t.get("defeated_flag", ""))
		if df != "" and QuestConditions.truthy(flags.get(df)):
			slain = true
		var poi := str(t.get("sighted_poi", ""))
		# (discovered.<poi> is true once found; "revealed" by a vista is not a sighting)
		var seen := poi != "" and typeof(flags.get(Discovery.discovered_flag(poi))) == TYPE_BOOL \
			and bool(flags.get(Discovery.discovered_flag(poi)))
		if not slain and not seen:
			continue
		var rec: Dictionary = titans.get(id, titan_defaults())
		if slain:
			rec.state = STATE_SLAIN
			rec.kills = maxi(1, int(rec.kills))
			if (rec.drops as Array).is_empty():
				rec.drops = loot_of(str(t.get("loot_table", "")))
		elif str(rec.state) == STATE_UNSEEN:
			rec.state = STATE_SIGHTED
		titans[id] = rec
	var settlements: Dictionary = state.settlements
	for row: Array in SETTLEMENT_FLAGS:
		if not QuestConditions.truthy(flags.get(str(row[2]))):
			continue
		var st: Dictionary = settlements.get(str(row[0]), {"level": 0, "flags": {}})
		(st.flags as Dictionary)[str(row[1])] = true
		settlements[str(row[0])] = st
	return state


## A loot table's guaranteed drops as [{"item", "count"}] ([] without one).
static func loot_of(table_id: String) -> Array:
	var out: Array = []
	var rec := GameData.get_record(table_id) if table_id != "" else {}
	for g: Variant in rec.get("guaranteed", []):
		if typeof(g) == TYPE_DICTIONARY:
			out.append({"item": str(g.get("item", "")), "count": int(g.get("count", 1))})
	return out


# --------------------------------------------------------------------------- what play records

## The giant sighted titan `id` (his territory engaged it): unseen -> sighted, the first time noted.
static func note_sighted(state: Dictionary, id: String, play_s: float, unix: int) -> void:
	if id == "":
		return
	var rec: Dictionary = state.titans.get(id, titan_defaults())
	if str(rec.state) == STATE_UNSEEN:
		rec.state = STATE_SIGHTED
	if float(rec.first_sighted_play_s) < 0.0 and int(rec.first_sighted_unix) == 0:
		rec.first_sighted_play_s = snappedf(play_s, 0.1)
		rec.first_sighted_unix = unix
	state.titans[id] = rec


## `count` of titan `id`'s plates broken in this attempt: the best kept.
static func note_plates(state: Dictionary, id: String, count: int) -> void:
	if id == "":
		return
	var rec: Dictionary = state.titans.get(id, titan_defaults())
	rec.plates_broken_best = maxi(int(rec.plates_broken_best), count)
	if str(rec.state) == STATE_UNSEEN:
		rec.state = STATE_SIGHTED
	state.titans[id] = rec


## Titan `id` slain: one more kill, his drops (his roster loot table's) recorded.
static func note_slain(state: Dictionary, id: String) -> void:
	if id == "":
		return
	var rec: Dictionary = state.titans.get(id, titan_defaults())
	rec.state = STATE_SLAIN
	rec.kills = int(rec.kills) + 1
	if (rec.drops as Array).is_empty():
		rec.drops = loot_of(str(roster_entry(id).get("loot_table", "")))
	state.titans[id] = rec


## True once cutscene `id` has played in this game.
static func seen(state: Dictionary, id: String) -> bool:
	return (state.get("cinematics_seen", []) as Array).has(id)


static func note_seen(state: Dictionary, id: String) -> void:
	var list: Array = state.get("cinematics_seen", [])
	if not list.has(id):
		list.append(id)
	state["cinematics_seen"] = list
