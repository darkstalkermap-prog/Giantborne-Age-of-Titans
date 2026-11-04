class_name Projectile
extends RefCounted
## One projectile in flight: pure state plus the pure math that launches and moves it (plan
## §3.3). ProjectileSystem steps it from the Sim POST_ACTORS hook, sweeps it against hurtboxes
## and the world, and resolves its impact; everything here is engine-free and unit-tested.
##
## Motion is exact constant-gravity kinematics per tick (p += v dt + g dt^2 / 2; v += g dt), so
## an arc solved by launch_velocity() passes through its aim point. Hits go through the
## projectile's own HitRegistry (never the action's: the action may end while it flies).

const MAX_AGE_TICKS := 300        ## removed after 5 s at the latest
const KILL_Y := -60.0             ## fell out of the world

var id := 0
var owner_id := ""
## The shooter's CombatEntity. A freed owner (despawned, scene unloaded) drops the projectile;
## a dead one does not (decision 8: shots in flight still land).
var owner: CombatEntity
var action: ActionDef
## Snapshot of the attack context at launch: its registry is `registry`, from_projectile is
## true, projectile_id is `id`, the outgoing multipliers are frozen.
var ctx: AttackContext
var position := Vector3.ZERO
var velocity := Vector3.ZERO
var gravity := 0.0                ## m/s^2, downward
var radius := 0.3
var range_m := 25.0               ## path length of a straight (gravity 0) shot
var traveled := 0.0               ## path length so far
var age_ticks := 0
var spawn_tick := 0               ## first moves on the tick after it was launched
var visual := "bolt"
var impact_radius := 0.0          ## > 0: a splash pulse at the impact
var impact_height := 2.0
var pierce := false
var registry := HitRegistry.new()
var hit_entities := PackedStringArray()   ## entities hit directly (the splash skips them)
## P07: id of a body riding this projectile (a thrown soldier); "" = none.
var held_entity_id := ""
var ended := false


## The action's projectile block with every default filled in (plan §2.8.2). launch_offset is
## Vector3.INF when the record has none (the actor's attack origin is used then).
static func spec_for(a: ActionDef) -> Dictionary:
	var raw: Variant = a.param("projectile", {}) if a != null else {}
	var d: Dictionary = raw if typeof(raw) == TYPE_DICTIONARY else {}
	var off: Variant = d.get("launch_offset_m")
	var offset := Vector3.INF
	if typeof(off) == TYPE_ARRAY and (off as Array).size() == 3:
		offset = Vector3(float(off[0]), float(off[1]), float(off[2]))
	return {
		"speed_mps": float(d.get("speed_mps", 20.0)),
		"radius_m": float(d.get("radius_m", 0.3)),
		"range_m": float(d.get("range_m", 25.0)),
		"gravity_mps2": float(d.get("gravity_mps2", 0.0)),
		"aim": str(d.get("aim", "lock_or_camera")),
		"arc_to_target": bool(d.get("arc_to_target", false)),
		"launch_offset": offset,
		"visual": str(d.get("visual", "bolt")),
		"impact_radius_m": float(d.get("impact_radius_m", 0.0)),
		"impact_height_m": float(d.get("impact_height_m", 2.0)),
		"pierce": bool(d.get("pierce", false)),
	}


## Launch velocity from `origin` toward `aim` for a spec (spec_for). A straight shot flies
## along the line at speed_mps. With arc_to_target and gravity, it takes the LOW ballistic
## angle that passes through the aim point; an aim farther than range_m (horizontally) is
## pulled back to range_m first, and a point that is still out of reach gets the 45-degree
## (longest) throw toward it.
static func launch_velocity(origin: Vector3, aim: Vector3, spec: Dictionary) -> Vector3:
	var speed := float(spec.get("speed_mps", 20.0))
	var to := aim - origin
	if to.length_squared() < 1e-8:
		to = Vector3.FORWARD
	var gravity := float(spec.get("gravity_mps2", 0.0))
	if not bool(spec.get("arc_to_target", false)) or gravity <= 0.0:
		return to.normalized() * speed
	var flat := Vector3(to.x, 0.0, to.z)
	var d := flat.length()
	if d < 0.01:
		return to.normalized() * speed
	var max_range := float(spec.get("range_m", 25.0))
	if d > max_range:
		flat = flat * (max_range / d)
		d = max_range
	var h := to.y
	var v2 := speed * speed
	var disc := v2 * v2 - gravity * (gravity * d * d + 2.0 * h * v2)
	var theta := deg_to_rad(45.0)
	if disc >= 0.0:
		theta = atan((v2 - sqrt(disc)) / (gravity * d))
	return flat.normalized() * speed * cos(theta) + Vector3.UP * speed * sin(theta)


## Where the projectile will be `dt` seconds from now (not committed).
func next_position(dt: float) -> Vector3:
	return position + velocity * dt + Vector3.DOWN * (0.5 * gravity * dt * dt)


## Commits one step that ended at `to` (velocity gains gravity * dt).
func advance_to(to: Vector3, dt: float) -> void:
	traveled += position.distance_to(to)
	position = to
	velocity += Vector3.DOWN * (gravity * dt)
	age_ticks += 1


## Why the projectile should be removed now without an impact ("" = keep flying): a straight
## shot at its range, any shot after MAX_AGE_TICKS or below KILL_Y. Arcs end on the ground
## (their aim was already clamped to the range).
func expiry_reason() -> String:
	if gravity <= 0.0 and traveled >= range_m - 1e-6:
		return "range"
	if age_ticks >= MAX_AGE_TICKS:
		return "timeout"
	if position.y < KILL_Y:
		return "fell"
	return ""
