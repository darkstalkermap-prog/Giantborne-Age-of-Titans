class_name ProjectileSystem
extends Node
## Every projectile of the level in flight (plan §2.7.4, §3.3): Runic Bolt, Boulder Hurl (P07),
## arrows and mage bolts (P09). One per level, created lazily by instance() and parented to the
## level ("level_root" node, otherwise the current scene), so it is freed with the level and
## no projectile survives a reload. Group "projectile_system".
##
## Stepped by Sim in the POST_ACTORS phase (order 100): after every actor moved and before hit
## resolution, so its hits resolve on the same tick. Per projectile and tick: exact kinematics,
## the first world contact on the way (a sphere cast on WORLD | BREAKABLE) stops it, hurtboxes
## on the way are swept with HitQueryAdapter.sweep_sphere and queued through HitFactory with
## the impact point as attacker_position, from_projectile = true and pulse id = projectile id.
## A non-piercing projectile ends at its first hit; an impact with impact_radius_m > 0 adds a
## splash (a cylinder pulse, pulse id = id + SPLASH_PULSE_OFFSET, area_effect) built from the
## same action, so it keeps the action's category, tags and on-hit statuses. Projectiles end at
## the range (straight shots), after 5 s, below the world, or when their owner is freed.
##
## Presentation: pooled meshes per visual kind (bolt, boulder, arrow; thrown_body has none: P07
## moves the body itself). Events: projectile_spawned, projectile_impact; the splash also emits
## area_pulse. Local signals let later packages follow a projectile without editing this file
## (P07: a thrown body rides it).

signal projectile_moved(projectile: Projectile)
## reason: impact | range | timeout | fell | owner_gone | cleared
signal projectile_ended(projectile: Projectile, reason: String)

const GROUP := "projectile_system"
const HOOK_ORDER := 100
const SPLASH_PULSE_OFFSET := 1000000

## Projectile ids are unique for the whole run (never reused across levels).
static var _next_id := 1

var _active: Array[Projectile] = []
var _visuals: Dictionary = {}     ## projectile id -> MeshInstance3D
var _pool: Dictionary = {}        ## visual kind -> Array of hidden MeshInstance3D
var _materials: Dictionary = {}   ## visual kind -> Material


## The level's projectile system, created on first use. Its parent is the "level_root" node
## when there is one (LevelRoot, P10a), otherwise tree.current_scene (the sandbox's main
## scene), so it is freed with the level.
static func instance(tree: SceneTree) -> ProjectileSystem:
	var parent := parent_for(tree)
	for n in tree.get_nodes_in_group(GROUP):
		var s := n as ProjectileSystem
		if s != null and s.get_parent() == parent and _usable(s):
			return s
	var system := ProjectileSystem.new()
	system.name = "ProjectileSystem"
	if parent != null:
		parent.add_child(system)
	return system


## Where a new system goes: the first "level_root" node, else the current scene, else the root.
static func parent_for(tree: SceneTree) -> Node:
	var level := tree.get_first_node_in_group("level_root")
	if level != null and _usable(level):
		return level
	if tree.current_scene != null:
		return tree.current_scene
	return tree.root


## In the tree and not on its way out (neither it nor an ancestor is queued for deletion).
static func _usable(n: Node) -> bool:
	if n == null or not is_instance_valid(n) or not n.is_inside_tree():
		return false
	var cur := n
	while cur != null:
		if cur.is_queued_for_deletion():
			return false
		cur = cur.get_parent()
	return true


func _enter_tree() -> void:
	add_to_group(GROUP)
	add_to_group("debug_info_providers")
	Sim.remove_hooks(self)
	Sim.add_hook(Sim.Hook.POST_ACTORS, self, _step, HOOK_ORDER)


func _exit_tree() -> void:
	Sim.remove_hooks(self)


## Launches one projectile of action `a` owned by `owner` from `origin` with `velocity`.
## `ctx` is the shooter's attack context (AttackRunner.context()); the projectile keeps a
## snapshot with its own registry and the outgoing multipliers frozen. Returns the id.
func spawn(owner: CombatEntity, a: ActionDef, origin: Vector3, velocity: Vector3, ctx: AttackContext) -> int:
	var spec := Projectile.spec_for(a)
	var p := Projectile.new()
	p.id = _next_id
	_next_id += 1
	p.owner = owner
	p.owner_id = owner.entity_id if owner != null else ""
	p.action = a
	p.position = origin
	p.velocity = velocity
	p.gravity = float(spec.gravity_mps2)
	p.radius = float(spec.radius_m)
	p.range_m = float(spec.range_m)
	p.visual = str(spec.visual)
	p.impact_radius = float(spec.impact_radius_m)
	p.impact_height = float(spec.impact_height_m)
	p.pierce = bool(spec.pierce)
	p.spawn_tick = Sim.tick
	var snap := ctx.snapshot() if ctx != null else AttackContext.new()
	if snap.entity == null:
		snap.entity = owner
	snap.registry = p.registry
	snap.from_projectile = true
	snap.projectile_id = p.id
	snap.area_effect = false
	if owner != null and owner.combatant != null:
		snap.outgoing_damage_mult = owner.combatant.outgoing_damage_mult()
		snap.outgoing_poise_mult = owner.combatant.outgoing_poise_mult()
	p.ctx = snap
	_active.append(p)
	_show_visual(p)
	Events.projectile_spawned.emit(Sim.tick, p.id, p.owner_id, a.id if a != null else "",
		origin, velocity, p.visual)
	return p.id


func active_count() -> int:
	return _active.size()


## The projectiles in flight, in launch order (tests, debug).
func projectiles() -> Array[Projectile]:
	return _active.duplicate()


func get_projectile(projectile_id: int) -> Projectile:
	for p in _active:
		if p.id == projectile_id:
			return p
	return null


## Removes every projectile without impacts (tests, tools).
func clear() -> void:
	for p in _active.duplicate():
		_end(p, "cleared")
	_active.clear()


func debug_lines() -> PackedStringArray:
	return PackedStringArray(["Projectiles: %d in flight" % _active.size()])


# --------------------------------------------------------------------------- stepping

## Sim POST_ACTORS hook: every projectile in launch order, except the ones launched this tick
## (they start moving on the next one, whether or not the system already existed).
func _step(tick: int) -> void:
	if _active.is_empty():
		return
	for p in _active.duplicate():
		if p.ended or p.spawn_tick >= tick:
			continue
		if p.owner == null or not is_instance_valid(p.owner) or not p.owner.is_inside_tree():
			_end(p, "owner_gone")
			continue
		_advance(p, tick)
	_active = _active.filter(func(p: Projectile) -> bool: return not p.ended)


func _advance(p: Projectile, tick: int) -> void:
	var dt := Sim.DT
	var from := p.position
	var to := p.next_position(dt)
	var space := p.owner.get_viewport().find_world_3d().direct_space_state
	var contact := HitQueryAdapter.sphere_contact(space, from, to, p.radius)
	var stop := to if contact.is_empty() else (contact.position as Vector3)
	var cands := HitQueryAdapter.sweep_sphere(space, p.owner, from, stop, p.radius)
	HitFactory.sort_candidates(cands)
	var first_substep := -1
	var impact := Vector3.INF
	var hit_id := ""
	for c: Dictionary in cands:
		if not p.pierce and first_substep >= 0 and int(c.substep) != first_substep:
			break
		var target: CombatEntity = c.entity
		if p.hit_entities.has(target.entity_id) or not target.is_alive():
			continue   # one hit per projectile and target; a corpse never stops a shot
		p.ctx.attacker_position = c.point
		p.ctx.area_effect = false
		if HitFactory.queue(p.ctx, p.action, [c], p.id, tick) > 0:
			p.hit_entities.append(target.entity_id)
			if first_substep < 0:
				first_substep = int(c.substep)
				impact = c.point
				hit_id = target.entity_id
	if impact != Vector3.INF and not p.pierce:
		_impact(p, impact, hit_id, tick)
		return
	if not contact.is_empty():
		_impact(p, stop, "", tick)
		return
	p.advance_to(to, dt)
	_move_visual(p)
	projectile_moved.emit(p)
	var why := p.expiry_reason()
	if why != "":
		_end(p, why)


## Splash (when the action has one), the impact event, then removal.
func _impact(p: Projectile, point: Vector3, hit_id: String, tick: int) -> void:
	p.position = point
	if p.impact_radius > 0.0:
		var space := p.owner.get_viewport().find_world_3d().direct_space_state
		var cands := HitQueryAdapter.cylinder_pulse(space, p.owner, point, p.impact_radius,
			p.impact_height, point)
		var others: Array = []
		for c: Dictionary in cands:
			if not p.hit_entities.has((c.entity as CombatEntity).entity_id):
				others.append(c)
		p.ctx.attacker_position = point
		p.ctx.area_effect = true
		HitFactory.queue(p.ctx, p.action, others, p.id + SPLASH_PULSE_OFFSET, tick)
		Events.area_pulse.emit(tick, p.owner_id, p.action.id if p.action != null else "", point,
			p.impact_radius)
	Events.projectile_impact.emit(tick, p.id, point, hit_id)
	_end(p, "impact")


func _end(p: Projectile, reason: String) -> void:
	if p.ended:
		return
	p.ended = true
	_hide_visual(p)
	projectile_ended.emit(p, reason)


# --------------------------------------------------------------------------- visuals

func _show_visual(p: Projectile) -> void:
	if p.visual == "thrown_body" or not is_inside_tree():
		return
	var list: Array = _pool.get(p.visual, [])
	var mi: MeshInstance3D = list.pop_back() if not list.is_empty() else _make_visual(p.visual)
	_visuals[p.id] = mi
	mi.visible = true
	_move_visual(p)


func _move_visual(p: Projectile) -> void:
	var mi: MeshInstance3D = _visuals.get(p.id)
	if mi == null or not mi.is_inside_tree():
		return
	var basis := Basis.from_scale(Vector3.ONE * p.radius)
	if p.velocity.length_squared() > 1e-6 and p.visual in ["bolt", "arrow"]:
		var dir := p.velocity.normalized()
		basis = Basis.looking_at(dir, Vector3.UP if absf(dir.y) < 0.99 else Vector3.RIGHT) \
			* Basis.from_scale(Vector3(p.radius, p.radius, p.radius * (2.5 if p.visual == "bolt" else 1.0)))
	mi.global_transform = Transform3D(basis, p.position)


func _hide_visual(p: Projectile) -> void:
	var mi: MeshInstance3D = _visuals.get(p.id)
	_visuals.erase(p.id)
	if mi == null or not is_instance_valid(mi):
		return
	mi.visible = false
	var list: Array = _pool.get(p.visual, [])
	list.append(mi)
	_pool[p.visual] = list


## A unit-sized mesh of one visual kind (scaled by the projectile radius when shown).
func _make_visual(kind: String) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.top_level = true
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	match kind:
		"boulder":
			var box := BoxMesh.new()
			box.size = Vector3(1.8, 1.6, 1.7)
			mi.mesh = box
		"arrow":
			var shaft := BoxMesh.new()
			shaft.size = Vector3(0.25, 0.25, 3.0)
			mi.mesh = shaft
		_:
			var ball := SphereMesh.new()
			ball.radius = 1.0
			ball.height = 2.0
			ball.radial_segments = 12
			ball.rings = 6
			mi.mesh = ball
	mi.material_override = _material(kind)
	add_child(mi)
	return mi


func _material(kind: String) -> Material:
	if _materials.has(kind):
		return _materials[kind]
	var m := StandardMaterial3D.new()
	match kind:
		"boulder":
			m.albedo_color = Color(0.45, 0.42, 0.38)
		"arrow":
			m.albedo_color = Color(0.45, 0.32, 0.18)
		_:
			m.albedo_color = Color(0.55, 0.85, 1.0)
			m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			m.emission_enabled = true
			m.emission = Color(0.4, 0.75, 1.0)
	_materials[kind] = m
	return m


# --------------------------------------------------------------------------- package extensions
# Later packages add their members directly below their own anchor (plan §1.5): P07 thrown
# bodies riding a projectile (held_entity_id) and Boulder Hurl; P09 enemy volleys.

## @anchor P07

## @anchor P09
