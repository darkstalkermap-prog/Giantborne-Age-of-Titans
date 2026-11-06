class_name Discovery
extends Node
## Discovery (P27; plan M6-M9 §3.10 design 1, §2.3, decision 33): the runtime node "Discovery" that
## LevelRoot.RUNTIME_NODES makes in both campaign levels. It turns walking about into what the map,
## the compass, the journal and the quests know, all as WorldState flags (saved with every
## checkpoint, rolled back with a reload):
##   discovered.<poi short>      true once the giant stood within the POI's radius (at its min_stage or
##                               above; a sealed place only once its seal is open): the POI's xp is
##                               awarded once (Events.xp_award_requested, "discovery:<poi id>") and
##                               Events.poi_discovered is emitted. "revealed" (a string) when a vista
##                               showed it: on the map and the compass, but its XP and its event wait
##                               for the visit (decision 33: every POI pays when found).
##   sealed.<poi short>.seen     a sealed place (kind "secret") came within SEALED_SEEN_M (and
##                               sealed.seen_count, the number seen, for the tutorial)
##   map.seen.<chunk>            the giant entered that chunk of a chunked level; a vista also clears
##                               the fog of every chunk within its reveals_m (default 400 m)
##   region.<short>.entered      the region was entered (Events.region_changed); its discover_xp once
## visited.<checkpoint id> (fast travel) is GameSession's (P20: set on checkpoint_reached).
##
## It checks every CHECK_EVERY_TICKS ticks from a Sim POST_RESOLVE hook (tick % 30 == 0, so the
## timeline is the same however the level was entered), in POI id order. scan() is the whole check
## for a position and a stage, so tests and tools call it with any point (no player needed).
##
## POIs come from the level's `poi` records (P25) merged over its world index's pois table
## (poi_table(): positions, radii, kinds, XP, reveals_m, seals, compass and skyline flags); the chunk
## grid from the level record's world block (chunk_grid()). Both are read once (refresh()).

const GROUP := "discovery"
const CHECK_EVERY_TICKS := 30
## POST_RESOLVE order: after Quests (100), before the waystones (190) and GameSession (200).
const HOOK_ORDER := 160
## A sealed place this close (horizontally) counts as seen.
const SEALED_SEEN_M := 60.0
## A vista's reveal radius when its record names none (plan §2.7).
const DEFAULT_REVEAL_M := 400.0
## The value a vista writes to discovered.<poi>: known, not yet found.
const REVEALED := "revealed"
const XP_SOURCE_PREFIX := "discovery:"
## The flag of the map pin: [x, z] (level space) or "" (none). The map screen writes it.
const PIN_FLAG := "map.pin"
## How many sealed places were seen (an int, overwritten; the sealed-place tutorial's trigger).
const SEALED_COUNT_FLAG := "sealed.seen_count"
## Set the first time the map screen opens (the map tutorial's dismissal).
const MAP_OPENED_FLAG := "map.opened"

## The level whose POIs are checked (the parent LevelRoot's level_id; tests may set it).
var level_id := ""
## poi id -> info (poi_table()).
var pois: Dictionary = {}
## The chunk grid (chunk_grid(); {} for a level without chunks: the Valley).
var grid: Dictionary = {}
## What this node found, in order (tests, bot metrics): {"tick", "id", "how" (visit | reveal |
## region | sealed), "xp"}.
var found_log: Array = []

var _ids: PackedStringArray = []


func _ready() -> void:
	add_to_group(GROUP)
	if level_id == "":
		var root := get_parent() as LevelRoot
		level_id = root.level_id if root != null else GameSession.current_level_id()
	refresh()
	Sim.add_hook(Sim.Hook.POST_RESOLVE, self, _on_tick, HOOK_ORDER)
	Events.region_changed.connect(_on_region_changed)


func _exit_tree() -> void:
	Sim.remove_hooks(self)


## Re-reads the level's POIs and chunk grid (a test that installed records).
func refresh() -> void:
	pois = poi_table(level_id)
	_ids = PackedStringArray(pois.keys())
	_ids.sort()
	grid = chunk_grid(level_id)


func _on_tick(tick: int) -> void:
	if tick % CHECK_EVERY_TICKS != 0 or not is_inside_tree():
		return
	var p := GameSession.player()
	if p == null or not is_instance_valid(p) or not p.is_inside_tree() or p.entity == null or not p.entity.is_alive():
		return
	scan(p.global_position - _root_offset(), p.current_growth_stage(), tick)


## The level root's position (POIs are in level space; the roots sit at the origin).
func _root_offset() -> Vector3:
	var root := get_parent() as Node3D
	return root.global_position if root != null and root.is_inside_tree() else Vector3.ZERO


## One check at `pos` (level space) for a giant of `stage`: the chunk seen, every sealed place within
## SEALED_SEEN_M seen, every POI found whose radius holds `pos` (a vista also reveals its
## neighbours). Returns the POI ids found now, in id order.
func scan(pos: Vector3, stage: int, tick: int = Sim.tick) -> PackedStringArray:
	var out := PackedStringArray()
	var chunk := chunk_of(grid, pos)
	if chunk != "":
		WorldState.try_set_flag(seen_flag(chunk), true)
	for id in _ids:
		var info: Dictionary = pois[id]
		var d := flat_distance(pos, info.position)
		if str(info.kind) == "secret" and d <= SEALED_SEEN_M:
			if WorldState.try_set_flag(sealed_seen_flag(id), true):
				WorldState.set_flag(SEALED_COUNT_FLAG, int(WorldState.get_flag(SEALED_COUNT_FLAG, 0)) + 1)
				found_log.append({"tick": tick, "id": id, "how": "sealed", "xp": 0})
		if d > float(info.radius) or is_found(WorldState.flags, id):
			continue
		if str(info.kind) == "secret":
			if not seal_open(str(info.seal)):
				continue
		elif stage < int(info.min_stage):
			continue
		if discover(id, tick):
			out.append(id)
	return out


## Finds a POI: discovered.<short> becomes true (it was unset or "revealed"), its XP is awarded,
## Events.poi_discovered is emitted and a vista reveals the POIs and chunks around it. False when it
## was found before or is not one of this level's POIs.
func discover(poi_id: String, tick: int = Sim.tick, how := "visit") -> bool:
	if not pois.has(poi_id) or is_found(WorldState.flags, poi_id):
		return false
	var info: Dictionary = pois[poi_id]
	WorldState.set_flag(discovered_flag(poi_id), true)
	var xp := int(info.xp)
	if xp > 0:
		Events.xp_award_requested.emit(xp, XP_SOURCE_PREFIX + poi_id)
	found_log.append({"tick": tick, "id": poi_id, "how": how, "xp": xp})
	if str(info.kind) == "vista":
		reveal_around(info.position, float(info.reveals_m), poi_id)
	Events.poi_discovered.emit(tick, poi_id)
	return true


## Marks every other non-secret POI within `radius` of `center` as revealed (known on the map and
## the compass; no XP, no event) and every chunk within it as seen. Returns the POIs revealed now.
func reveal_around(center: Vector3, radius: float, except := "") -> PackedStringArray:
	var out := PackedStringArray()
	for id in _ids:
		var info: Dictionary = pois[id]
		if id == except or str(info.kind) == "secret" or is_known(WorldState.flags, id):
			continue
		if flat_distance(center, info.position) <= radius:
			WorldState.set_flag(discovered_flag(id), REVEALED)
			found_log.append({"tick": Sim.tick, "id": id, "how": "reveal", "xp": 0})
			out.append(id)
	for chunk in chunks_within(grid, center, radius):
		WorldState.try_set_flag(seen_flag(chunk), true)
	return out


func _on_region_changed(tick: int, region_id: String, _previous: String) -> void:
	enter_region(region_id, tick)


## The first entry into a region: region.<short>.entered and its record's discover_xp
## ("discovery:<region id>"). False when it was entered before (or "" / unknown).
func enter_region(region_id: String, tick: int = Sim.tick) -> bool:
	if region_id == "" or not WorldState.try_set_flag(region_flag(region_id), true):
		return false
	var xp := int(GameData.get_record(region_id).get("discover_xp", 0))
	if xp > 0:
		Events.xp_award_requested.emit(xp, XP_SOURCE_PREFIX + region_id)
	found_log.append({"tick": tick, "id": region_id, "how": "region", "xp": xp})
	return true


## The POIs found now, in id order (tests, debug).
func found_ids() -> PackedStringArray:
	var out := PackedStringArray()
	for id in _ids:
		if is_found(WorldState.flags, id):
			out.append(id)
	return out


## The node of the current level (null when the level has none: the sandbox, a test level).
static func of_tree(tree: SceneTree) -> Discovery:
	return tree.get_first_node_in_group(GROUP) as Discovery if tree != null else null


# --------------------------------------------------------------------------- flags (pure)

## "poi.hollowmere" -> "hollowmere" (the id after its record prefix).
static func short_id(id: String) -> String:
	return QuestConditions.short_of(id)


static func discovered_flag(poi_id: String) -> String:
	return "discovered." + short_id(poi_id)


static func sealed_seen_flag(poi_id: String) -> String:
	return "sealed.%s.seen" % short_id(poi_id)


static func region_flag(region_id: String) -> String:
	return "region.%s.entered" % short_id(region_id)


static func seen_flag(chunk_id: String) -> String:
	return "map.seen." + chunk_id


## True once the POI was found (discovered.<short> is true).
static func is_found(flags: Dictionary, poi_id: String) -> bool:
	return QuestConditions.same_value(flags.get(discovered_flag(poi_id)), true)


## True when the POI is on the map: found, or revealed by a vista.
static func is_known(flags: Dictionary, poi_id: String) -> bool:
	return QuestConditions.truthy(flags.get(discovered_flag(poi_id)))


## True when a sealed place's seal is open: its prop destroyed (heaved) or opened, its ledge taken.
static func seal_open(seal: String) -> bool:
	if seal == "":
		return false
	var d := WorldState.get_delta(seal)
	return bool(d.get("destroyed", false)) or bool(d.get("opened", false)) or bool(d.get("taken", false))


## The map pin from the flags: Vector2 (x, z) or Vector2.INF when none.
static func pin_of(flags: Dictionary) -> Vector2:
	var v: Variant = flags.get(PIN_FLAG, "")
	if (typeof(v) == TYPE_ARRAY or typeof(v) == TYPE_PACKED_FLOAT32_ARRAY or typeof(v) == TYPE_PACKED_FLOAT64_ARRAY) \
			and v.size() >= 2 and SchemaUtil.is_number(v[0]) and SchemaUtil.is_number(v[1]):
		return Vector2(float(v[0]), float(v[1]))
	return Vector2.INF


## Distance on the ground plane.
static func flat_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


# --------------------------------------------------------------------------- tables (pure)

## The POIs of a level: id -> {"id", "short", "display_name", "kind", "position" (Vector3, level
## space), "radius", "xp", "min_stage", "reveals_m", "seal", "compass", "skyline", "region",
## "map_icon", "note"}. Every `poi` record whose level is `p_level_id`, with the world index's entry
## (where the builder placed it) for the position and radius when it has one; POIs only the index
## knows keep the index's fields.
static func poi_table(p_level_id: String) -> Dictionary:
	var out := {}
	if p_level_id == "":
		return out
	var idx := WorldIndex.for_level(p_level_id)
	var from_index: Dictionary = idx.pois if idx != null else {}
	for rec: Dictionary in GameData.records_of_type("poi"):
		if str(rec.get("level", "")) != p_level_id:
			continue
		var id := str(rec.get("id", ""))
		out[id] = _info(id, rec, from_index.get(id, {}))
	for id: Variant in from_index:
		if not out.has(str(id)) and typeof(from_index[id]) == TYPE_DICTIONARY:
			out[str(id)] = _info(str(id), {}, from_index[id])
	return out


static func _info(id: String, rec: Dictionary, entry: Variant) -> Dictionary:
	var e: Dictionary = entry if typeof(entry) == TYPE_DICTIONARY else {}
	var pos := Vector3.INF
	if typeof(e.get("position")) == TYPE_VECTOR3:
		pos = e.position
	elif typeof(rec.get("position_m")) == TYPE_ARRAY and (rec.position_m as Array).size() >= 3:
		pos = Vector3(float(rec.position_m[0]), float(rec.position_m[1]), float(rec.position_m[2]))
	var kind := str(rec.get("kind", e.get("kind", "landmark")))
	var reveals := float(rec.get("reveals_m", 0.0))
	if kind == "vista" and reveals <= 0.0:
		reveals = DEFAULT_REVEAL_M
	return {"id": id, "short": short_id(id),
		"display_name": str(rec.get("display_name", e.get("display_name", id))),
		"kind": kind, "position": pos,
		"radius": float(e.get("radius", rec.get("radius_m", 30.0))),
		"xp": int(rec.get("xp", 0)), "min_stage": int(rec.get("min_stage", e.get("min_stage", 0))),
		"reveals_m": reveals, "seal": str(rec.get("seal", "")),
		"compass": bool(rec.get("compass", true)), "skyline": bool(rec.get("skyline", false)),
		"region": str(rec.get("region", e.get("region", ""))),
		"map_icon": str(rec.get("map_icon", kind)), "note": str(rec.get("note", ""))}


## A level's chunk grid from its record's world block: {"origin": Vector2 (x, z of the grid's
## north-west corner), "size": chunk metres, "grid": Vector2i}; {} when the level has no chunks.
static func chunk_grid(p_level_id: String) -> Dictionary:
	var rec := GameData.get_record(p_level_id)
	var w: Variant = rec.get("world")
	if typeof(w) != TYPE_DICTIONARY:
		return {}
	var g: Variant = w.get("grid")
	var o: Variant = w.get("origin_m")
	if typeof(g) != TYPE_ARRAY or (g as Array).size() < 2 or typeof(o) != TYPE_ARRAY or (o as Array).size() < 3:
		return {}
	var size := float(w.get("chunk_size_m", 256.0))
	if size <= 0.0:
		return {}
	return {"origin": Vector2(float(o[0]), float(o[2])), "size": size, "grid": Vector2i(int(g[0]), int(g[1]))}


## "c<x>_<z>" of the chunk holding `pos` ("" outside the grid or without one).
static func chunk_of(g: Dictionary, pos: Vector3) -> String:
	if g.is_empty() or not pos.is_finite():
		return ""
	var c := chunk_coords(g, pos)
	var n: Vector2i = g.grid
	if c.x < 0 or c.y < 0 or c.x >= n.x or c.y >= n.y:
		return ""
	return "c%d_%d" % [c.x, c.y]


static func chunk_coords(g: Dictionary, pos: Vector3) -> Vector2i:
	var o: Vector2 = g.origin
	var s := float(g.size)
	return Vector2i(floori((pos.x - o.x) / s), floori((pos.z - o.y) / s))


## The level-space rectangle (x, z) of chunk (x, z).
static func chunk_rect(g: Dictionary, coords: Vector2i) -> Rect2:
	var s := float(g.size)
	var o: Vector2 = g.origin
	return Rect2(o + Vector2(coords) * s, Vector2(s, s))


## Every chunk whose rectangle comes within `radius` of `center`, in row order.
static func chunks_within(g: Dictionary, center: Vector3, radius: float) -> PackedStringArray:
	var out := PackedStringArray()
	if g.is_empty() or not center.is_finite():
		return out
	var n: Vector2i = g.grid
	var c := Vector2(center.x, center.z)
	for z in n.y:
		for x in n.x:
			var r := chunk_rect(g, Vector2i(x, z))
			var nearest := Vector2(clampf(c.x, r.position.x, r.end.x), clampf(c.y, r.position.y, r.end.y))
			if nearest.distance_to(c) <= radius:
				out.append("c%d_%d" % [x, z])
	return out
