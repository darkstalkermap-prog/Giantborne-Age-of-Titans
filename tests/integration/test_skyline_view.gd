extends TestSuite
## P25 (plan M6-M9 §3.8, §5.1): the first view. From the Kingsgate shelf - the stage-3 camera behind
## the giant standing at world.cp.kingsgate_shelf, at the waystone's yaw and the rig's default pitch,
## the default field of view, the low preset's far plane - a landmark of each of the five regions is
## in the view frustum and no ridge of the skyline's coarse heightfield (the terrain drawn beyond the
## loaded chunks) hides it. Also: the skyline's landmark mesh exists and every skyline POI's landmark
## stands in its region. Resources and records only: the default tier's budget.

const LEVEL := "level.world"
const INDEX := "res://assets/world/index_world.res"
const START := "world.cp.kingsgate_shelf"
## CameraRig's default third-person pitch and the settings' default field of view (vertical).
const PITCH_DEG := -18.0
const ASPECT := 16.0 / 9.0
## Each region's landmark seen from the shelf: world id -> [region, the height of its top over its
## base (tools/data/world: the beacon's 31 m, a great pine's 50 m, the bell tower's 34 m, the
## keep's 26 m, the Standing Stones' 16 m trilithons)].
const LANDMARKS := {
	"world.crownmarch.kingsgate_beacon": ["region.crownmarch", 31.0],
	"world.greywood.great_pine_1": ["region.greywood", 50.0],
	"world.drowned.bell_tower": ["region.drowned_steps", 34.0],
	"world.aldmere.fort_keep": ["region.aldmere", 26.0],
	"world.stonehold.standing_stones": ["region.stonehold", 16.0],
}
## The ray may graze the coarse terrain this close to its landmark (the landmark's own ground).
const NEAR_TARGET_M := 40.0
const STEP_M := 8.0


func _profile() -> Dictionary:
	for rec: Dictionary in GameData.records_of_type("growth_profile"):
		if int(rec.get("stage", 0)) == 3:
			return rec
	return {}


## The coarse skyline terrain as SkylineWriter.coarse() returned it, from the mesh's grid vertices.
func _coarse() -> Dictionary:
	var mesh := load(str(GameData.get_record(LEVEL).world.skyline)) as ArrayMesh
	var v: PackedVector3Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var n := int(roundf(sqrt(float(v.size()))))
	var h := PackedFloat32Array()
	h.resize(v.size())
	for k in v.size():
		h[k] = v[k].y
	return {"origin": Vector2(v[0].x, v[0].z), "spacing": v[1].x - v[0].x, "size": Vector2i(n, n), "h": h}


## The stage-3 camera at the start checkpoint: its transform.
func _camera() -> Transform3D:
	var idx := load(INDEX) as WorldIndex
	var spawn := idx.spawn_transform(START)
	var prof := _profile()
	var yaw := spawn.basis.get_euler().y
	var basis := Basis.from_euler(Vector3(deg_to_rad(PITCH_DEG), yaw, 0.0))
	var pivot := spawn.origin + Vector3.UP * float(prof.get("camera_pivot_height_m", 7.25))
	var right := Vector3(cos(yaw), 0.0, -sin(yaw))
	var at := pivot + right * float(prof.get("camera_shoulder_offset_m", 1.6)) + basis.z * float(prof.get("camera_distance_m", 12.0))
	return Transform3D(basis, at)


func test_each_region_has_a_landmark_in_the_first_view() -> void:
	var idx := load(INDEX) as WorldIndex
	assert_true(idx.has_checkpoint(START), "the start checkpoint is in the index")
	var cam := _camera()
	var coarse := _coarse()
	var low: Dictionary = GameData.get_record(LEVEL).render.low
	var far := float(low.get("camera_far_m", 800.0))
	var fov := float(Settings.DEFAULTS.get("fov_deg", 75.0))
	var tan_v := tan(deg_to_rad(fov) * 0.5)
	var tan_h := tan_v * ASPECT
	var regions := {}
	for id: String in LANDMARKS:
		var spec: Array = LANDMARKS[id]
		var base := idx.position_of(id)
		assert_true(base != Vector3.INF, "%s is in the index" % id)
		if base == Vector3.INF:
			continue
		assert_eq(idx.region_at(base), str(spec[0]), "%s stands in %s" % [id, spec[0]])
		var top := base + Vector3.UP * float(spec[1])
		var local := cam.affine_inverse() * top
		var depth := -local.z
		var in_view := depth > 0.0 and depth <= far and absf(local.x / depth) <= tan_h and absf(local.y / depth) <= tan_v
		assert_true(in_view, "%s is in the stage-3 camera's view from the shelf (%.0f m, %.0f / %.0f degrees)" % [id, depth,
			rad_to_deg(atan2(local.x, depth)), rad_to_deg(atan2(local.y, depth))])
		var hidden := _hidden_by(coarse, cam.origin, top)
		assert_true(hidden == Vector3.INF, "no ridge of the skyline hides %s (blocked at %s)" % [id, hidden])
		regions[spec[0]] = true
	assert_eq(regions.size(), 5, "a landmark of every region")


## The first point where the coarse terrain rises over the sight line from `from` to `to`
## (Vector3.INF when it never does before the landmark's own ground).
static func _hidden_by(coarse: Dictionary, from: Vector3, to: Vector3) -> Vector3:
	var flat := Vector2(to.x - from.x, to.z - from.z).length()
	var steps := int(ceil((flat - NEAR_TARGET_M) / STEP_M))
	for k in range(1, maxi(steps, 1)):
		var t := float(k) * STEP_M / flat
		var p := from.lerp(to, t)
		var ground := SkylineWriter.coarse_height(coarse, p.x, p.z)
		if not is_nan(ground) and ground > p.y:
			return p
	return Vector3.INF


func test_the_skyline_holds_the_landmarks_and_the_beacons() -> void:
	var w: Dictionary = GameData.get_record(LEVEL).world
	var marks := load(str(w.skyline_landmarks)) as ArrayMesh
	assert_true(marks != null and marks.get_surface_count() == 1, "the merged landmark silhouettes")
	var aabb := marks.get_aabb()
	assert_true(aabb.size.x > 1200.0 and aabb.size.z > 1200.0, "spread over the kingdom (%s)" % aabb)
	var idx := load(INDEX) as WorldIndex
	var skyline := 0
	for poi: Dictionary in GameData.records_of_type("poi"):
		if str(poi.get("level", "")) != LEVEL or not bool(poi.get("skyline", false)):
			continue
		skyline += 1
		var at := idx.position_of(str(poi.landmark))
		assert_true(at != Vector3.INF and aabb.grow(1.0).has_point(at + Vector3.UP), "%s's landmark is in the skyline's bounds" % poi.id)
	assert_true(skyline >= 10, "about twelve skyline POIs (%d)" % skyline)
	var root := load(str(GameData.get_record(LEVEL).scene)) as PackedScene
	var state := root.get_state()
	var beacons := PackedStringArray()
	for i in state.get_node_count():
		if str(state.get_node_name(i)) != "Skyline":
			continue
		for p in state.get_node_property_count(i):
			if str(state.get_node_property_name(i, p)) == "beacon_flags":
				beacons = state.get_node_property_value(i, p)
	assert_true(beacons.has("world.kingsgate.lit"), "the Kingsgate beacon's column (lit by world.kingsgate.lit)")
	assert_true(beacons.has("world.shepherds_watch.lit"), "the Shepherd's Watch column")
