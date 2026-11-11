extends TestSuite
## P25 (plan M6-M9 §0.2, §3.8, §5.10): the M7 content rule on the world's records and index -
## every region has at least two encounters (existing archetypes) and two caches or cairns; every
## POI gives discovery XP (the shrine POIs' 0 of plan §5.4 excepted: the shrine is the reward) and
## holds at least one of an encounter, a cache, a cairn, a talker, a quest target, a shrine, a
## waystone or a sealed place; every walkable chunk lies within 400 m of such a POI. The light
## encounters use only archetypes that exist, keep the leash rule and the budget. The Crownmarch's
## encounters are P29's (its own tests count them); its caches and cairns are checked here.
## Records and the index only: the default tier's budget.

const LEVEL := "level.world"
const INDEX := "res://assets/world/index_world.res"
const INTERIOR := 896.0
const REGIONS := ["region.crownmarch", "region.greywood", "region.drowned_steps", "region.aldmere", "region.stonehold"]
## The regions whose encounters P25 ships (the M7 light content, §5.10).
const LIGHT_REGIONS := ["region.greywood", "region.drowned_steps", "region.aldmere", "region.stonehold"]
const NEAR_POI_M := 400.0
const MAX_LEASH_M := 70.0
const BUDGET := 12

var _idx: WorldIndex = null


func _index() -> WorldIndex:
	if _idx == null:
		_idx = load(INDEX) as WorldIndex
	return _idx


func _of_level(type: String) -> Array:
	return GameData.records_of_type(type).filter(func(r: Dictionary) -> bool: return str(r.get("level", "")) == LEVEL)


static func _rect(bounds: Array) -> Rect2:
	return Rect2(Vector2(float(bounds[0][0]), float(bounds[0][1])),
		Vector2(float(bounds[1][0]) - float(bounds[0][0]), float(bounds[1][1]) - float(bounds[0][1])))


static func _xz(v: Variant) -> Vector2:
	if v is Vector3:
		return Vector2((v as Vector3).x, (v as Vector3).z)
	var a: Array = v
	return Vector2(float(a[0]), float(a[2]))


## The region holding a point (clamped into the interior), "" when none.
static func _region_of(p: Vector2) -> String:
	var q := Vector2(clampf(p.x, -INTERIOR + 0.01, INTERIOR - 0.01), clampf(p.y, -INTERIOR + 0.01, INTERIOR - 0.01))
	for id: String in REGIONS:
		if _rect(GameData.get_record(id).bounds_m).has_point(q):
			return id
	return ""


func test_every_region_has_encounters_and_caches_or_cairns() -> void:
	var encounters := {}
	for enc: Dictionary in _of_level("encounter"):
		var r := _region_of(_xz(enc.center_m))
		encounters[r] = int(encounters.get(r, 0)) + 1
	for id: String in LIGHT_REGIONS:
		assert_true(int(encounters.get(id, 0)) >= 2, "%s has at least two encounters (%d)" % [id, int(encounters.get(id, 0))])
	var finds := {}
	var idx := _index()
	for pid: String in idx.props:
		if str(idx.props[pid].get("kind", "")) in ["cache", "ledge", "cairn"]:
			var r := _region_of(_xz(idx.props[pid].position))
			finds[r] = int(finds.get(r, 0)) + 1
	for id: String in REGIONS:
		assert_true(int(finds.get(id, 0)) >= 2, "%s has at least two caches or cairns (%d)" % [id, int(finds.get(id, 0))])


func test_the_light_encounters_use_existing_archetypes_within_the_rules() -> void:
	# The light content of the four regions P25 ships (the Crownmarch's settlements, talkers and
	# formation fights are P29's: tests/integration/test_crownmarch_content.gd).
	# P36: a region package that brings its region's content removes the region record's m7_note; its
	# encounters are its own tests' (P36: tests/integration/test_aldmere_stonehold_content.gd; P35:
	# test_greywood_drowned_content.gd). M8 gate (F22): the journal's text is the record's journal_note,
	# so P35 no longer keeps its regions' m7_note as their description: in the M8 build no region waits.
	var waiting := LIGHT_REGIONS.filter(func(id: String) -> bool:
		return str(GameData.get_record(id).get("m7_note", "")) != "")
	var light := _of_level("encounter").filter(func(r: Dictionary) -> bool: return waiting.has(_region_of(_xz(r.center_m))))
	assert_true(light.size() >= 2 * waiting.size(), "two light encounters in each region still waiting for its package (%d in %s)" % [
		light.size(), waiting])
	for enc: Dictionary in light:
		var id := str(enc.id)
		# M8 (P35, P36): an arena boss's encounter is held by its arena's disengage rule instead of a
		# leash (GameData's leash rule exempts `arena: true`), and the regions' settlements and talkers
		# spawn npc records (folk, elders, the ferrywoman) beside the enemies.
		var arena := bool(enc.get("arena", false))
		assert_true(arena or (float(enc.get("leash_radius_m", 0.0)) > 0.0 and float(enc.leash_radius_m) <= MAX_LEASH_M),
			"%s has a leash of at most 70 m" % id)
		var c := _xz(enc.center_m)
		var at_once := 0
		for sp: Dictionary in enc.spawns:
			var def := GameData.get_record(str(sp.definition))
			var type := str(def.get("type", ""))
			assert_true(type == "enemy" or type == "npc", "%s spawns an existing archetype (%s)" % [id, sp.definition])
			assert_true(arena or _xz(sp.position_m).distance_to(c) <= float(enc.leash_radius_m), "%s's %s starts inside its leash" % [id, sp.entity_id])
			assert_true(str(sp.entity_id).begins_with("world."), "%s's spawn ids are world ids" % id)
			if type == "enemy" and int(sp.get("max_stage", 10)) >= 4 and int(sp.get("min_stage", 0)) <= 4:
				at_once += 1
		assert_true(at_once <= BUDGET, "%s fits the combatant budget at stage 4 (%d)" % [id, at_once])
		var chunk := str(_index().encounters.get(id, {}).get("chunk", ""))
		assert_true(chunk != "", "%s has its chunk in the index" % id)


func _poi_holds(poi: Dictionary) -> PackedStringArray:
	var idx := _index()
	var c := _xz(poi.position_m)
	var r := float(poi.radius_m)
	var out := PackedStringArray()
	if str(poi.kind) == "secret":
		out.append("sealed place")
	for enc: Dictionary in _of_level("encounter"):
		if _xz(enc.center_m).distance_to(c) <= r:
			out.append("encounter")
			for sp: Dictionary in enc.spawns:
				if str(GameData.get_record(str(sp.definition)).get("type", "")) == "npc":
					out.append("talker")
	for pid: String in idx.props:
		var p: Dictionary = idx.props[pid]
		if _xz(p.position).distance_to(c) > r:
			continue
		match str(p.get("kind", "")):
			"cache", "ledge":
				out.append("cache")
			"cairn":
				out.append("cairn")
		if bool(p.get("quest_target", false)):
			out.append("quest target")
	for cid: String in idx.checkpoints:
		var e: Dictionary = idx.checkpoints[cid]
		if _xz(e.position).distance_to(c) <= r and str(e.get("kind", "")) in ["shrine", "waystone"]:
			out.append(str(e.kind))
	return out


func test_every_poi_gives_xp_and_holds_something() -> void:
	for poi: Dictionary in _of_level("poi"):
		var id := str(poi.id)
		if str(poi.kind) != "shrine":
			assert_true(int(poi.get("xp", 0)) > 0, "%s gives discovery XP" % id)
		var holds := _poi_holds(poi)
		assert_false(holds.is_empty(), "%s holds an encounter, cache, cairn, talker, quest target, shrine, waystone or sealed place" % id)


func test_every_walkable_chunk_lies_within_400_m_of_such_a_poi() -> void:
	var held: Array = []
	for poi: Dictionary in _of_level("poi"):
		if not _poi_holds(poi).is_empty():
			held.append(_xz(poi.position_m))
	var w: Dictionary = GameData.get_record(LEVEL).world
	var origin := Vector2(float(w.origin_m[0]), float(w.origin_m[2]))
	var size := float(w.chunk_size_m)
	for z in int(w.grid[1]):
		for x in int(w.grid[0]):
			var chunk := Rect2(origin + Vector2(x, z) * size, Vector2(size, size))
			var walkable := chunk.intersection(Rect2(-INTERIOR, -INTERIOR, 2.0 * INTERIOR, 2.0 * INTERIOR))
			if walkable.get_area() <= 0.0:
				continue
			var centre := walkable.get_center()
			var best := INF
			for p: Vector2 in held:
				best = minf(best, p.distance_to(centre))
			assert_true(best <= NEAR_POI_M, "c%d_%d's walkable ground lies within 400 m of a POI that holds something (%.0f m)" % [x, z, best])
