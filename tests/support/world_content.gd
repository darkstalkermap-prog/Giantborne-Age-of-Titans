class_name WorldContent
extends RefCounted
## The world's content for the content tests (P29; plan M6-M9 §3.12): what the world's quests, dialogue
## and prompts may name, and the flags the world writes besides the records' own writers.
##   * places(): every id of a world place - the world index's markers, areas, props, exits,
##     checkpoints and encounters - and every spawn of the world's encounters.
##   * written_flags(): the world's encounters' cleared flags and their factions' standing flags
##     (warned and hostile; reconciled for a faction record with a reconciliation, which FactionState
##     writes on its dialogue outcome), the lit flag of every beacon fire of the layout tables
##     (BeaconFire) and the on_destroyed_flags of every breakable site's prop record; P35: the forge
##     fires' lit flags, the bells', braziers', brood nests' and den wall's records' and nodes' flags,
##     and the bosses' outcome and defeated flags.
## Records, the index and the layout tables only (no scene): the default tier's budget. Both are
## built once per run (the shipped content does not change during one).

const LEVEL := "level.world"
const BREAKABLE_SITE := "res://tools/world/kinds/breakable_site.gd"
## P35: the kinds whose elements are breakable props of their own records (record_of(el)).
const KINDS_DIR := "res://tools/world/kinds/"
const P35_BREAKABLE_KINDS := ["bell", "brazier", "nest", "den_wall"]

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
	# P35: the forge fires' lit flags (a ForgeFire is a BeaconFire), the on_destroyed_flags of the
	# breakables P35's kinds place (bells, braziers and bonfires, brood nests, the den's back wall),
	# the den's nests-burned flag (BroodNest) and wall flag (DenWall), and the bosses' outcome and
	# defeated flags (EnemyActor writes an enemy record's boss_outcome).
	for el: Dictionary in elements_of("forge_fire"):
		if str(el.get("flag", "")) != "":
			w[str(el.flag)] = true
	for kind: String in P35_BREAKABLE_KINDS:
		var script: GDScript = load(KINDS_DIR + kind + ".gd")
		for el: Dictionary in elements_of(kind):
			var rec := GameData.get_record(str(script.call("record_of", el)))
			for f: Variant in (rec.get("on_destroyed_flags", {}) as Dictionary):
				w[str(f)] = true
			if script.has_method("written_flags"):
				for f: Variant in script.call("written_flags", el):
					w[str(f)] = true
	for rec: Dictionary in GameData.records_of_type("enemy"):
		var bo: Variant = rec.get("boss_outcome")
		if typeof(bo) == TYPE_DICTIONARY:
			for key: String in ["flag", "defeated_flag"]:
				if str((bo as Dictionary).get(key, "")) != "":
					w[str(bo[key])] = true
	_flags = w
	return w
