extends IntegrationSuite
## The Crownmarch's slow checks (P29; plan M6-M9 §3.12, §2.12, §5.9):
##   * Edda, Tamsin and the toll captain are reachable by a stage-6 giant where the director puts them
##     at stage 6 - Edda on Brannock's green (the town's POI admits stage 4 inside its walls: a bigger
##     giant meets her outside the south gate), Tamsin in Millford (its POI admits stage 6), the captain
##     at his toll bar - by a titan-layer path from the nearest waystone, built from the shipped chunks'
##     navmeshes and their props' links; without damage: no hostile armed member stands within 30 m of
##     the stand point while the towns are at peace and the toll is pending (the toll fort's garrison
##     stands down then); without trapping: the stand point has titan-layer ground under it;
##   * the director's stand_down_when on a live encounter (the director test level with a fixture of
##     the toll fort's rule): hostile-by-faction members stand down while it holds, take up arms once
##     the toll is refused, stand down again when it holds again, and a connecting blow of the giant
##     provokes them for good (encounter.<short>.provoked).

const LEVEL := "level.world"
const TITAN := 16
const GATE_BITS := {4: 32, 5: 64, 6: 128}
const REACH_M := 15.0
const SAFE_M := 30.0
## Talker -> [its spawn's entity id, the waystone a giant starts from].
const TALKERS := {"npc.edda": ["world.crownmarch.edda", "world.cp.brannock"],
	"npc.reeve_tamsin": ["world.crownmarch.reeve_tamsin", "world.cp.millford"],
	"npc.toll_captain": ["world.crownmarch.toll_captain", "world.cp.kings_road"]}
const CHUNKS := ["c2_6", "c3_6", "c4_5", "c4_6", "c5_5", "c5_6"]
const DIRECTOR_LEVEL := "res://scenes/test/director_test.tscn"
const SOLDIERS := "encounter.director_test_soldiers"
const DEFIED := "test.p29.toll_defied"

var _nav: NavMaps = null
var _links: Array = []


func after_each() -> void:
	for l: RID in _links:
		NavigationServer3D.free_rid(l)
	_links.clear()
	if _nav != null:
		_nav.free_all()
		_nav = null
	await super()


static func _mask(stage: int) -> int:
	var m := TITAN
	for s: int in GATE_BITS:
		if stage >= s:
			m |= int(GATE_BITS[s])
	return m


static func _local_to(ancestor: Node3D, node: Node3D) -> Transform3D:
	var xf := Transform3D.IDENTITY
	var n: Node = node
	while n != null and n != ancestor:
		if n is Node3D:
			xf = (n as Node3D).transform * xf
		n = n.get_parent()
	return xf


## The titan maps of the Crownmarch chunks the talkers stand in, with their props' titan links.
func _build_maps() -> void:
	var w: Dictionary = GameData.get_record(LEVEL).world
	_nav = NavMaps.new()
	_nav.setup(w.nav_layers, (w.gate_bits as Dictionary).values(), TITAN, true)
	for id: String in CHUNKS:
		var d := load("%s/%s.res" % [w.chunk_dir, id]) as ChunkData
		for bit: int in d.nav:
			if bit == TITAN or GATE_BITS.values().has(bit):
				_nav.add_region(d.chunk_id, bit, load(str(d.nav[bit])) as NavigationMesh, Transform3D(Basis(), d.origin))
		for path: String in d.props_scenes:
			var part := (load(path) as PackedScene).instantiate() as Node3D
			for link: NavigationLink3D in part.find_children("*", "NavigationLink3D", true, false):
				if (link.navigation_layers & TITAN) == 0:
					continue
				var xf := Transform3D(Basis(), d.origin) * _local_to(part, link)
				var rid := NavigationServer3D.link_create()
				NavigationServer3D.link_set_map(rid, _nav.map_for(TITAN))
				NavigationServer3D.link_set_navigation_layers(rid, TITAN)
				NavigationServer3D.link_set_bidirectional(rid, true)
				NavigationServer3D.link_set_start_position(rid, xf * link.start_position)
				NavigationServer3D.link_set_end_position(rid, xf * link.end_position)
				NavigationServer3D.link_set_enabled(rid, true)
				_links.append(rid)
			part.free()
	await get_tree().physics_frame
	await get_tree().physics_frame


func _path(from: Vector3, to: Vector3, stage: int) -> PackedVector3Array:
	var q := NavigationPathQueryParameters3D.new()
	q.map = _nav.map_for(TITAN)
	q.start_position = from
	q.target_position = to
	q.navigation_layers = _mask(stage)
	q.path_search_max_polygons = 0
	var res := NavigationPathQueryResult3D.new()
	NavigationServer3D.query_path(q, res)
	return res.path


## Where the director puts a talker for a giant of `stage`: its spawn point, or its settlement's
## green when the stage is above the settlement's max_inner_stage (EncounterDirector.p29_green_for).
func _stand_point(entity_id: String, stage: int) -> Vector3:
	var at := WorldXp.position_of(entity_id)
	for poi: Dictionary in GameData.records_of_type("poi"):
		if str(poi.get("level", "")) != LEVEL or str(poi.get("kind", "")) != "settlement" or not poi.has("max_inner_stage"):
			continue
		var c: Array = poi.position_m
		if Vector2(at.x - float(c[0]), at.z - float(c[2])).length() <= float(poi.radius_m) and stage > int(poi.max_inner_stage):
			var g: Array = poi.green_m
			return Vector3(float(g[0]), float(g[1]), float(g[2]))
	return at


func test_the_talkers_are_reachable_at_stage_6_without_damage_or_trapping() -> void:
	await _build_maps()
	var down: Variant = GameData.get_record("encounter.crownmarch_toll_fort").get("stand_down_when")
	assert_true(QuestConditions.holds(down, QuestConditions.empty_context()), "the toll fort stands down while the toll is pending")
	for npc: String in TALKERS:
		var entity: String = TALKERS[npc][0]
		var stand := _stand_point(entity, 6)
		var from := WorldXp.position_of(str(TALKERS[npc][1]))
		assert_true(stand.is_finite() and from.is_finite(), "%s has a stand point and a waystone" % npc)
		if npc == "npc.edda":
			var g: Array = GameData.get_record("poi.brannock").green_m
			assert_true(Vector2(stand.x - float(g[0]), stand.z - float(g[2])).length() < 1.0, "a stage-6 giant meets Edda on Brannock's green")
		var path := _path(from, stand, 6)
		assert_false(path.is_empty(), "%s: a titan path from %s" % [npc, TALKERS[npc][1]])
		if path.is_empty():
			continue
		var end := path[path.size() - 1]
		assert_true(Vector2(end.x - stand.x, end.z - stand.z).length() <= REACH_M,
			"%s is reachable at stage 6 (the path ends %.1f m from %s)" % [npc, Vector2(end.x - stand.x, end.z - stand.z).length(), stand])
		var ground := NavigationServer3D.map_get_closest_point(_nav.map_for(TITAN), stand)
		assert_true(Vector2(ground.x - stand.x, ground.z - stand.z).length() <= REACH_M,
			"%s stands on ground a titan can stand on (no trap)" % npc)
		# No hostile armed member within SAFE_M of the stand point while everyone is at peace.
		for enc: Dictionary in WorldContent.encounters():
			var cleared_ok := enc.has("stand_down_when") and QuestConditions.holds(enc.stand_down_when, QuestConditions.empty_context())
			for sp: Dictionary in enc.spawns:
				var f := str(sp.get("faction", ""))
				if str(GameData.get_record(str(sp.definition)).get("type", "")) != "enemy" or cleared_ok:
					continue
				if f != "" and not FactionState.is_hostile(f):
					continue
				var p: Array = sp.position_m
				assert_true(Vector2(float(p[0]) - stand.x, float(p[2]) - stand.z).length() > SAFE_M,
					"%s: no hostile %s within %d m of where the giant talks" % [npc, sp.entity_id, int(SAFE_M)])


# --------------------------------------------------------------------------- stand_down_when

func _load_director_level() -> Array:
	var rec := GameData.get_record(SOLDIERS).duplicate(true)
	var spawns: Array = rec.spawns
	for sp: Dictionary in spawns:
		sp["faction"] = "toll_riders"
	TestFixtures.record_override(SOLDIERS, {"spawns": spawns,
		"stand_down_when": {"type": "not", "of": {"type": "flag", "flag": DEFIED}}})
	var level := (load(DIRECTOR_LEVEL) as PackedScene).instantiate() as LevelRoot
	world.add_child(level)
	await step_ticks(1)
	var director := level.director()
	var player := level.player()
	player.global_position = Vector3(35, 0.05, -12)
	player.velocity = Vector3.ZERO
	director.update_now()
	await step_ticks(2)
	return [level, director, player]


func _standings(director: EncounterDirector) -> Array:
	var out: Array = []
	for id in director.members_of(SOLDIERS):
		var n := director.spawned(id)
		out.append(str(n.get("faction_standing")) if n != null else "")
	return out


func test_a_garrison_stands_down_until_defied_or_provoked() -> void:
	var made := await _load_director_level()
	var director: EncounterDirector = made[1]
	assert_eq(director.encounter_state(SOLDIERS), EncounterDirector.ACTIVE, "the garrison is active")
	assert_true(FactionState.is_hostile("toll_riders"), "the toll-riders are hostile by their faction")
	assert_eq(_standings(director), ["stood_down", "stood_down", "stood_down"], "while the toll is pending they stand down")
	assert_true(director.p29_standing_down(SOLDIERS), "the director says so")
	WorldState.set_flag(DEFIED, true)
	director.p29_update_stand_downs()
	assert_eq(_standings(director), ["hostile", "hostile", "hostile"], "refused: they take up arms")
	WorldState.set_flag(DEFIED, false)
	director.p29_update_stand_downs()
	assert_eq(_standings(director), ["stood_down", "stood_down", "stood_down"], "the rule holds again: they stand down")
	var target := str(director.members_of(SOLDIERS)[0])
	queue_hit("player", target, director.spawned(target).global_position + Vector3(0, 0, 2), 1.0)
	await step_ticks(3)
	assert_true(QuestConditions.truthy(WorldState.get_flag(EncounterDirector.provoked_flag(SOLDIERS))), "a blow provokes them")
	assert_false(director.p29_standing_down(SOLDIERS), "a provoked garrison no longer stands down")
	var alive := _standings(director).filter(func(s: String) -> bool: return s != "")
	assert_true(alive.all(func(s: String) -> bool: return s == "hostile"), "they fight (%s)" % [alive])
