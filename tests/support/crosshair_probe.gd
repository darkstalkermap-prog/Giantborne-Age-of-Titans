class_name CrosshairProbe
extends RefCounted
## Is the crosshair obscured by the player's own body? (plan §3.5 design 9; reused by P07 for
## a held body and by P08 for weapons.) Each sample() casts the screen-centre ray from the
## camera and intersects it with the local bounds (AABB) of every VisualInstance3D under the
## roots that the camera draws now (its layers & the camera's cull_mask, visible in the tree).
## The tick counts as obscured when such a mesh is the first thing the ray meets within
## RANGE_M, nearer than the first physics hit (world, breakables, other actors; the roots'
## own bodies are excluded). The giant's visuals have no collision shapes, so bounds are the
## only way to test them. The probe keeps the run's statistics.
##
##   var probe := CrosshairProbe.new(player.camera_rig.camera, [player])
##   ... every tick: probe.sample()
##   assert_true(probe.max_consecutive <= 30, ...)

const RANGE_M := 40.0
const WORLD_MASK := HitQueryAdapter.LAYER_WORLD | HitQueryAdapter.LAYER_ACTORS | HitQueryAdapter.LAYER_BREAKABLE

var camera: Camera3D
var roots: Array = []
var samples := 0
var obscured_ticks := 0
var consecutive := 0
var max_consecutive := 0
## Name and distance of the mesh that obscured the last obscured sample.
var last_blocker := ""
var last_distance := INF
## The longest obscured run's first blocker (diagnostics for failing tests).
var worst_blocker := ""
var _exclude: Array[RID] = []


func _init(p_camera: Camera3D, p_roots: Array) -> void:
	camera = p_camera
	roots = p_roots.duplicate()
	for r: Variant in roots:
		_collect_rids(r as Node)


## One tick: true when the player's own geometry is the first thing the centre ray meets.
func sample() -> bool:
	samples += 1
	var hit := first_own_hit()
	var obscured := not hit.is_empty() and float(hit.distance) < _world_distance(float(hit.distance))
	if obscured:
		obscured_ticks += 1
		consecutive += 1
		last_blocker = str(hit.node)
		last_distance = float(hit.distance)
		if consecutive > max_consecutive:
			max_consecutive = consecutive
			worst_blocker = last_blocker
	else:
		consecutive = 0
	return obscured


## The nearest of the roots' drawn meshes along the centre ray within RANGE_M:
## {"distance", "node" (its path below the root)} or {}.
func first_own_hit() -> Dictionary:
	if camera == null or not is_instance_valid(camera):
		return {}
	var origin := camera.global_position
	var dir := -camera.global_transform.basis.z.normalized()
	var best := {}
	for r: Variant in roots:
		var root := r as Node
		if root == null or not is_instance_valid(root):
			continue
		for vi in visual_instances(root):
			if (vi.layers & camera.cull_mask) == 0 or not vi.is_visible_in_tree():
				continue
			var d := ray_aabb_distance(origin, dir, vi.global_transform, vi.get_aabb(), RANGE_M)
			if d < INF and (best.is_empty() or d < float(best.distance)):
				best = {"distance": d, "node": str(root.get_path_to(vi))}
	return best


## Distance to the first physics hit along the centre ray, up to `limit` (INF when none).
func _world_distance(limit: float) -> float:
	var origin := camera.global_position
	var dir := -camera.global_transform.basis.z.normalized()
	var q := PhysicsRayQueryParameters3D.create(origin, origin + dir * minf(limit, RANGE_M), WORLD_MASK, _exclude)
	q.collide_with_areas = false
	var hit := camera.get_world_3d().direct_space_state.intersect_ray(q)
	return origin.distance_to(hit.position) if not hit.is_empty() else INF


func _collect_rids(node: Node) -> void:
	if node == null:
		return
	if node is CollisionObject3D:
		_exclude.append((node as CollisionObject3D).get_rid())
	for c in node.get_children():
		_collect_rids(c)


## Every VisualInstance3D at or below `root`.
static func visual_instances(root: Node) -> Array[VisualInstance3D]:
	var out: Array[VisualInstance3D] = []
	if root is VisualInstance3D:
		out.append(root as VisualInstance3D)
	for c in root.get_children():
		out.append_array(visual_instances(c))
	return out


## World-space distance along the ray (origin, unit dir) to `aabb` placed with `xform`,
## within max_d; 0 when the origin is inside it; INF when it misses.
static func ray_aabb_distance(origin: Vector3, dir: Vector3, xform: Transform3D, aabb: AABB,
		max_d: float) -> float:
	var inv := xform.affine_inverse()
	var lo := inv * origin
	var ld := inv.basis * dir
	if aabb.has_point(lo):
		return 0.0
	var tmin := 0.0
	var tmax := INF
	for axis in 3:
		var o := lo[axis]
		var d := ld[axis]
		var a := aabb.position[axis]
		var b := aabb.end[axis]
		if absf(d) < 1e-12:
			if o < a or o > b:
				return INF
			continue
		var t1 := (a - o) / d
		var t2 := (b - o) / d
		if t1 > t2:
			var tmp := t1
			t1 = t2
			t2 = tmp
		tmin = maxf(tmin, t1)
		tmax = minf(tmax, t2)
		if tmin > tmax:
			return INF
	var hit_local := lo + ld * tmin
	var d_world := origin.distance_to(xform * hit_local)
	return d_world if d_world <= max_d else INF
