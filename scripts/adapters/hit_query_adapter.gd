class_name HitQueryAdapter
extends RefCounted
## Engine adapter: turns attack geometry into Godot physics queries.
##
## Weapon sweeps interpolate the weapon capsule between its previous and current pose in
## sub-steps no longer than 3/4 of its radius, so fast swings cannot tunnel. For every
## overlapped hurtbox, world occluders are tested first: the line from the attack origin to
## the weapon point, and from that point to the hurtbox, must both be clear. Walls (and an
## intact fence) therefore stop attacks. The query buffer grows instead of silently capping.

const LAYER_WORLD := 1
const LAYER_ACTORS := 2
const LAYER_HURTBOX := 4
const LAYER_DEBRIS := 8
const LAYER_BREAKABLE := 16
const OCCLUDER_MASK := LAYER_WORLD | LAYER_BREAKABLE
const INITIAL_BUFFER := 64
const MAX_BUFFER := 4096
const MAX_SUBSTEPS := 16


## Returns candidate dictionaries: {"entity", "hurtbox", "point", "substep", "distance", "weak_point"}.
static func sweep_capsule(space: PhysicsDirectSpaceState3D, attacker: CombatEntity,
		origin: Vector3, prev_a: Vector3, prev_b: Vector3, cur_a: Vector3, cur_b: Vector3,
		radius: float) -> Array:
	var out: Array = []
	var travel := maxf(prev_a.distance_to(cur_a), prev_b.distance_to(cur_b))
	var steps := clampi(int(ceilf(travel / maxf(radius * 0.75, 0.05))), 1, MAX_SUBSTEPS)
	var shape := CapsuleShape3D.new()
	shape.radius = radius
	var params := PhysicsShapeQueryParameters3D.new()
	params.collide_with_areas = true
	params.collide_with_bodies = false
	params.collision_mask = LAYER_HURTBOX
	params.shape = shape
	for i in range(1, steps + 1):
		var t := float(i) / steps
		var a := prev_a.lerp(cur_a, t)
		var b := prev_b.lerp(cur_b, t)
		var axis := b - a
		shape.height = axis.length() + 2.0 * radius
		params.transform = Transform3D(basis_y_to(axis), (a + b) * 0.5)
		for r: Dictionary in intersect_all(space, params):
			var hb := r.get("collider") as Hurtbox
			if hb == null or hb.entity == null:
				continue
			var target := hb.entity
			if target == attacker or not CombatEntity.can_damage(attacker.team, target.team):
				continue
			var center := hb.global_position
			var p := AttackGeometry.closest_point_on_segment(a, b, center)
			if not line_clear(space, origin, p, OCCLUDER_MASK, target.occlusion_rids):
				continue
			if not line_clear(space, p, center, OCCLUDER_MASK, target.occlusion_rids):
				continue
			out.append({"entity": target, "hurtbox": hb, "point": p, "substep": i,
				"distance": origin.distance_to(center), "weak_point": hb.weak_point})
	return out


## Vertical cylinder pulse (area abilities such as Heavy Footfall).
static func cylinder_pulse(space: PhysicsDirectSpaceState3D, attacker: CombatEntity,
		center: Vector3, radius: float, height: float, los_origin: Vector3) -> Array:
	var out: Array = []
	var shape := CylinderShape3D.new()
	shape.radius = radius
	shape.height = height
	var params := PhysicsShapeQueryParameters3D.new()
	params.collide_with_areas = true
	params.collide_with_bodies = false
	params.collision_mask = LAYER_HURTBOX
	params.shape = shape
	params.transform = Transform3D(Basis(), center)
	for r: Dictionary in intersect_all(space, params):
		var hb := r.get("collider") as Hurtbox
		if hb == null or hb.entity == null:
			continue
		var target := hb.entity
		if target == attacker or not CombatEntity.can_damage(attacker.team, target.team):
			continue
		var c := hb.global_position
		if not line_clear(space, los_origin, c, OCCLUDER_MASK, target.occlusion_rids):
			continue
		var flat := Vector2(c.x - center.x, c.z - center.z)
		out.append({"entity": target, "hurtbox": hb, "point": c, "substep": 0,
			"distance": flat.length(), "weak_point": hb.weak_point})
	return out


## Sphere swept from `from` to `to` (projectiles): the sweep_capsule rules for a moving ball.
## Positions are sub-stepped at most 0.75 * radius apart (at most MAX_SUBSTEPS + 1 positions,
## the start included), so a fast projectile never tunnels through a hurtbox. A hurtbox counts
## only when the line from the sphere's centre to the hurtbox centre is clear of world
## occluders, and only once per sweep (its earliest sub-step). Returns candidates
## {"entity", "hurtbox", "point" (the sphere centre at contact), "substep", "distance" (from
## `from` to the hurtbox centre), "weak_point"}, filtered by team like sweep_capsule.
static func sweep_sphere(space: PhysicsDirectSpaceState3D, attacker: CombatEntity, from: Vector3,
		to: Vector3, radius: float) -> Array:
	var out: Array = []
	var travel := from.distance_to(to)
	var steps := clampi(int(ceilf(travel / maxf(radius * 0.75, 0.05))), 1, MAX_SUBSTEPS)
	var shape := SphereShape3D.new()
	shape.radius = radius
	var params := PhysicsShapeQueryParameters3D.new()
	params.collide_with_areas = true
	params.collide_with_bodies = false
	params.collision_mask = LAYER_HURTBOX
	params.shape = shape
	var seen := {}
	for i in range(0, steps + 1):
		var p := from.lerp(to, float(i) / steps)
		params.transform = Transform3D(Basis(), p)
		for r: Dictionary in intersect_all(space, params):
			var hb := r.get("collider") as Hurtbox
			if hb == null or hb.entity == null or seen.has(hb.get_instance_id()):
				continue
			var target := hb.entity
			if target == attacker or (attacker != null and not CombatEntity.can_damage(attacker.team, target.team)):
				continue
			var center := hb.global_position
			if not line_clear(space, p, center, OCCLUDER_MASK, target.occlusion_rids):
				continue
			seen[hb.get_instance_id()] = true
			out.append({"entity": target, "hurtbox": hb, "point": p, "substep": i,
				"distance": from.distance_to(center), "weak_point": hb.weak_point})
	return out


## First contact of a sphere moving from `from` to `to` with world occluders (WORLD and
## BREAKABLE). {} when the path is clear; otherwise {"fraction": the safe fraction 0..1,
## "position": the sphere's centre where it first touches}. A sphere that starts inside
## geometry reports fraction 0.
static func sphere_contact(space: PhysicsDirectSpaceState3D, from: Vector3, to: Vector3,
		radius: float, exclude: Array[RID] = []) -> Dictionary:
	if from.distance_squared_to(to) < 1e-10:
		return {}
	var shape := SphereShape3D.new()
	shape.radius = radius
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = shape
	q.transform = Transform3D(Basis(), from)
	q.motion = to - from
	q.collision_mask = OCCLUDER_MASK
	q.collide_with_areas = false
	q.collide_with_bodies = true
	q.exclude = exclude
	var r := space.cast_motion(q)
	if r.size() < 2 or float(r[1]) >= 1.0:
		return {}
	var f := clampf(float(r[0]), 0.0, 1.0)
	return {"fraction": f, "position": from.lerp(to, f)}


## intersect_shape that grows its result buffer until nothing is cut off.
static func intersect_all(space: PhysicsDirectSpaceState3D, params: PhysicsShapeQueryParameters3D) -> Array:
	var cap := INITIAL_BUFFER
	while true:
		var results := space.intersect_shape(params, cap)
		if results.size() < cap or cap >= MAX_BUFFER:
			if results.size() >= MAX_BUFFER:
				push_warning("HitQueryAdapter: %d overlaps reached the hard query limit" % results.size())
			return results
		cap *= 2
	return []


static func line_clear(space: PhysicsDirectSpaceState3D, from: Vector3, to: Vector3, mask: int,
		exclude: Array[RID]) -> bool:
	if from.distance_squared_to(to) < 1e-6:
		return true
	var q := PhysicsRayQueryParameters3D.create(from, to, mask, exclude)
	q.collide_with_areas = false
	q.collide_with_bodies = true
	return space.intersect_ray(q).is_empty()


## First world hit along a segment, or {} (used for "clank" feedback).
static func first_world_hit(space: PhysicsDirectSpaceState3D, from: Vector3, to: Vector3,
		exclude: Array[RID]) -> Dictionary:
	if from.distance_squared_to(to) < 1e-6:
		return {}
	var q := PhysicsRayQueryParameters3D.create(from, to, OCCLUDER_MASK, exclude)
	q.collide_with_areas = false
	return space.intersect_ray(q)


## Orthonormal basis whose +Y axis points along `axis` (capsule shapes are Y-aligned).
static func basis_y_to(axis: Vector3) -> Basis:
	if axis.length_squared() < 1e-10:
		return Basis()
	var y := axis.normalized()
	var ref := Vector3.UP if absf(y.dot(Vector3.UP)) < 0.99 else Vector3.RIGHT
	var x := ref.cross(y).normalized()
	var z := x.cross(y).normalized()
	return Basis(x, y, z)
