class_name WorldContent
extends RefCounted
## The world's content for the content tests (P29; plan M6-M9 §3.12): what the world's quests, dialogue
## and prompts may name, and the flags the world writes besides the records' own writers.
##   * places(): every id of a world place - the world index's markers, areas, props, exits,
##     checkpoints and encounters - and every spawn of the world's encounters.
##   * written_flags(): the world's encounters' cleared flags and their factions' standing flags
##     (warned and hostile; reconciled for a faction record with a reconciliation, which FactionState
##     writes on its dialogue outcome), the lit flag of every beacon fire of the layout tables
##     (BeaconFire) and the on_destroyed_flags of every breakable site's prop record.
## Records, the index and the layout tables only (no scene): the default tier's budget. Both are
## built once per run (the shipped content does not change during one).

const LEVEL := "level.world"
const BREAKABLE_SITE := "res://tools/world/kinds/breakable_site.gd"

static var _places: Dictionary = {}
static var _flags: Dictionary = {}
static var _elements: Array = []


## The world's index (null when it was never built).
static func index() -> WorldIndex:
	return WorldIndex.for_level(LEVEL)


## The world's encounter records.
static func encounters() -> Array:
	return GameData.records_of_type("encounter").filter(func(r: Dictionary) -> bool:
		return str(r.get("level", "")) == LEVEL)


## Every element of the region layout tables (tools/data/world/<region>.json; parsed directly - the
## builder's WorldLayout.load_all() also compiles every kind script), loaded once.
static func elements() -> Array:
	if _elements.is_empty():
		for r: String in WorldLayout.REGION_FILES:
			var t := WorldFeatures.load_json(WorldLayout.DATA_DIR.path_join(r + ".json"))
			_elements.append_array(t.get("elements", []))
	return _elements


## The layout's elements of kind `kind`.
static func elements_of(kind: String) -> Array:
	return elements().filter(func(el: Dictionary) -> bool: return str(el.get("kind", "")) == kind)


## id -> true for every world place (see the class notes).
static func places() -> Dictionary:
	if not _places.is_empty():
		return _places
	var out := {}
	var idx := index()
	if idx != null:
		for table: Dictionary in [idx.markers, idx.areas, idx.props, idx.exits, idx.checkpoints, idx.encounters]:
			for id: Variant in table:
				out[str(id)] = true
	for rec: Dictionary in encounters():
		out[str(rec.id)] = true
		for sp: Dictionary in rec.get("spawns", []):
			out[str(sp.entity_id)] = true
	_places = out
	return out


## flag -> true for every flag the world writes besides the quests', dialogue's and prompts' own
## writers (see the class notes).
static func written_flags() -> Dictionary:
	if not _flags.is_empty():
		return _flags
	var w := {}
	for rec: Dictionary in encounters():
		w[EncounterDirector.cleared_flag(str(rec.id))] = true
		for sp: Dictionary in rec.get("spawns", []):
			if str(sp.get("faction", "")) != "":
				w[FactionState.flag_id(str(sp.faction), "warned")] = true
				w[FactionState.flag_id(str(sp.faction), "hostile")] = true
	for rec: Dictionary in GameData.records_of_type("faction"):
		if typeof(rec.get("reconcile")) == TYPE_DICTIONARY:
			w[FactionState.flag_id(str(rec.id).trim_prefix("faction."), "reconciled")] = true
	for el: Dictionary in elements_of("beacon_fire"):
		if str(el.get("flag", "")) != "":
			w[str(el.flag)] = true
	var site: GDScript = load(BREAKABLE_SITE)
	for el: Dictionary in elements_of("breakable_site"):
		var rec := GameData.get_record(str(site.call("record_of", el)))
		for f: Variant in (rec.get("on_destroyed_flags", {}) as Dictionary):
			w[str(f)] = true
	w.merge(p36_written_flags())
	_flags = w
	return w


## P36: the flags the Aldmere March's and the Stonehold's runtime writes besides the records - the arenas'
## (FortBattle and MootArena: the boss's defeated flag and settled outcome, the fort opened, the Moot
## emptied), the Stone Throne's claim, the longhouses' rebuilt flags (RebuildPoint) and every world event's
## (WorldEvent: <id>.runs, .done, .outcome and its outcomes' set_flags).
static func p36_written_flags() -> Dictionary:
	var w := {}
	for el: Dictionary in elements_of("arena"):
		for key: String in ["defeated_flag", "settled_flag", "open_flag", "empty_flag"]:
			if str(el.get(key, "")) != "":
				w[str(el[key])] = true
	for el: Dictionary in elements_of("throne"):
		w[str(el.get("claim_flag", "world.throne.claimed"))] = true
	for el: Dictionary in elements_of("longhouse"):
		if str(el.get("rebuilt_flag", "")) != "":
			w[str(el.rebuilt_flag)] = true
	for rec: Dictionary in GameData.records_of_type("world_event"):
		for key: String in ["runs", "done", "outcome"]:
			w[WorldEvent.flag(str(rec.id), key)] = true
		for o: Variant in (rec.get("outcomes", {}) as Dictionary).values():
			if typeof(o) == TYPE_DICTIONARY:
				for f: Variant in (o.get("set_flags", {}) as Dictionary):
					w[str(f)] = true
	return w
