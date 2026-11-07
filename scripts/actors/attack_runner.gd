class_name AttackRunner
extends RefCounted
## Runs the hit queries of an actor's current action, one handler per hit shape (plan §2.7.2).
## Shared by the player and every enemy, so a new shape is one registered handler instead of
## another copy of the sweep code.
##
## The actor provides (duck typed):
##   weapon_segment_global(action, f) -> PackedVector3Array   shoulder/hand -> weapon tip
##   attack_origin_global() -> Vector3                         occlusion origin of the sweep
##   current_weapon() -> Dictionary                            weapon record (damage multiplier)
##   current_growth_stage() -> int                             HitEvent.attacker_growth_stage
##   weapon_hit_radius() -> float                              capsule radius of the weapon sweep
##
## Shapes: P02 `weapon_arc` and `cylinder_pulse`; P03 `sector_pulse`, `projectile`, and the
## `self_statuses` of any action (applied when it enters ACTIVE: Stone Skin, Mend, Titan Surge
## use hit_shape `none`). Later packages register theirs below their anchor in _init (P09 enemy
## ranged aim; P11a body_sweep on its own runner) or with register_shape() from their own code
## (P07 grab). Telegraphs are emitted by EnemyActor (P04), not here.
##
## Pulses (P03): the radius follows radius_from "melee_reach" (the actor's profile reach), else
## radius_by_stage_m[stage - 1], else radius_m; every cylinder pulse, sector pulse and
## projectile splash is an area effect (the player's skip neutral bystanders). Handlers emit
## Events.ability_effect: "sector", "roar" (a pulse with morale damage), "self_buff", "cast".

var actor: Node3D
var entity: CombatEntity
var controller: CombatController
## The player reports a "clank" when a swing first meets world geometry; enemies do not, so the
## clank counts tests and feedback see stay the player's.
var emit_clank := false
var prev_segment := PackedVector3Array()
## P03: set by an enemy actor at its aim-lock tick; used and cleared by the projectile handler
## for aim "target". INF = none.
var aim_point := Vector3.INF
## P03: Callable(a: ActionDef, spec: Dictionary) -> {"origin": Vector3, "aim": Vector3} that
## says where a projectile starts and what it flies at. PlayerAttack sets it (launch offset x k,
## lock-or-camera aim); without one, default_launch() is used (enemies).
var launch_resolver := Callable()

var _handlers: Dictionary = {}   ## hit_shape -> Callable(a: ActionDef, tick: int)
var _clanked_instance := -1


func _init(p_actor: Node3D, p_entity: CombatEntity, p_controller: CombatController) -> void:
	actor = p_actor
	entity = p_entity
	controller = p_controller
	register_shape("weapon_arc", _run_weapon_arc)
	register_shape("cylinder_pulse", _run_cylinder_pulse)
	## @anchor P03
	register_shape("sector_pulse", _run_sector_pulse)
	register_shape("projectile", _run_projectile)
	if controller != null:
		controller.phase_entered.connect(_on_phase_entered)
	## @anchor P07
	## @anchor P09
	## @anchor P11a
	# M6-M9 (P20): P30 band_pulse, P31 line_pulse, P32 engine launches, P34 the bosses' shapes.
	## @anchor P30
	register_shape("band_pulse", _run_band_pulse)   # P30: a formation's brace (see the P30 shapes below)
	## @anchor P31
	_p31_setup()   # P31: line_pulse, the titanforged perks on the weapon arc, the casts' effects (below)
	## @anchor P32
	## @anchor P34


## handler(a: ActionDef, tick: int) runs every ACTIVE tick of an action with this hit_shape.
## Registering a shape again replaces its handler.
func register_shape(shape: String, handler: Callable) -> void:
	_handlers[shape] = handler


func has_shape(shape: String) -> bool:
	return _handlers.has(shape)


## Called once per tick by the actor, after movement. Outside an action's ACTIVE phase it only
## forgets the previous weapon segment, so the next sweep starts fresh.
func run(tick: int) -> void:
	var a := controller.action
	if a == null or controller.phase() != ActionDef.Phase.ACTIVE:
		prev_segment = PackedVector3Array()
		return
	var handler: Callable = _handlers.get(a.hit_shape, Callable())
	if handler.is_valid():
		_p30_run(handler, a, tick)   # P30: the target provider's NPC or prop is hittable meanwhile


## The attack context for the action running now.
func context() -> AttackContext:
	var ctx := AttackContext.new()
	ctx.entity = entity
	ctx.instance_id = controller.instance_id
	ctx.weapon = actor.current_weapon()
	ctx.growth_stage = actor.current_growth_stage()
	ctx.attacker_position = actor.global_position
	ctx.registry = controller.hit_registry
	return ctx


## Forget sweep state (a new action started, or the actor was reset).
func reset() -> void:
	prev_segment = PackedVector3Array()
	aim_point = Vector3.INF


# --------------------------------------------------------------------------- shapes

## Swept weapon capsule from the previous tick's segment to this tick's, so fast swings never
## tunnel. The first world contact of an instance may report a clank (player only).
func _run_weapon_arc(a: ActionDef, tick: int) -> void:
	var space := actor.get_world_3d().direct_space_state
	var origin: Vector3 = actor.attack_origin_global()
	var cur: PackedVector3Array = actor.weapon_segment_global(a, controller.active_fraction())
	var prev := prev_segment
	if prev.size() != 2:
		prev = actor.weapon_segment_global(a, controller.active_fraction_prev())
	var cands := HitQueryAdapter.sweep_capsule(space, entity, origin, prev[0], prev[1],
		cur[0], cur[1], float(actor.weapon_hit_radius()))
	prev_segment = cur
	HitFactory.queue(context(), a, cands, 0, tick)
	if emit_clank and _clanked_instance != controller.instance_id:
		var wall := HitQueryAdapter.first_world_hit(space, origin, cur[1], [])
		if not wall.is_empty():
			_clanked_instance = controller.instance_id
			Events.attack_clanked.emit(tick, entity.entity_id, controller.instance_id, wall.position)


## Vertical cylinder around the actor on the first active tick (Heavy Footfall, Thunder Roar):
## pulse_radius(), height_m, occlusion from 0.8 m above the feet, pulse id 1, an area effect.
## A pulse with morale damage is a roar (ability_effect "roar").
func _run_cylinder_pulse(a: ActionDef, tick: int) -> void:
	if not controller.is_first_active_tick():
		return
	var space := actor.get_world_3d().direct_space_state
	var feet := actor.global_position
	var radius := pulse_radius(a)
	var center := feet + Vector3.UP * (a.height_m * 0.5)
	var cands := HitQueryAdapter.cylinder_pulse(space, entity, center, radius, a.height_m,
		feet + Vector3.UP * 0.8)
	var ctx := context()
	ctx.area_effect = true
	HitFactory.queue(ctx, a, cands, 1, tick)
	Events.area_pulse.emit(tick, entity.entity_id, a.id, feet, radius)
	if float(a.param("morale_damage", 0.0)) > 0.0:
		Events.ability_effect.emit(tick, entity.entity_id, a.id, "roar", feet, radius, facing_yaw(), 360.0)


# --------------------------------------------------------------------------- P03 shapes

## The pulse radius of `a` for this actor now: the profile's melee_reach_m for radius_from
## "melee_reach", else radius_by_stage_m[growth stage - 1] (the last entry beyond the list),
## else radius_m.
func pulse_radius(a: ActionDef) -> float:
	if str(a.param("radius_from", "fixed")) == "melee_reach":
		var reach := _melee_reach()
		if reach > 0.0:
			return reach * float(a.param("radius_scale", 1.0))   # P31: Titan Stomp 0.9, Formation Sweep 1.2
	var by_stage: Variant = a.param("radius_by_stage_m")
	if typeof(by_stage) == TYPE_ARRAY and not (by_stage as Array).is_empty():
		var list: Array = by_stage
		var i := clampi(int(actor.current_growth_stage()) - 1, 0, list.size() - 1)
		return float(list[i])
	return a.radius_m


## The actor's melee reach: its growth profile's melee_reach_m (the giant), otherwise its arm
## plus weapon length (enemies); 0 when unknown.
func _melee_reach() -> float:
	var profile: Variant = actor.get("profile")
	if typeof(profile) == TYPE_DICTIONARY and (profile as Dictionary).has("melee_reach_m"):
		return float(profile.melee_reach_m)
	var arm: Variant = actor.get("arm_length")
	var weapon_len: Variant = actor.get("weapon_length")
	if typeof(arm) == TYPE_FLOAT and typeof(weapon_len) == TYPE_FLOAT:
		return float(arm) + float(weapon_len)
	return 0.0


## The actor's facing (yaw, radians; 0 faces -Z).
func facing_yaw() -> float:
	var fwd := -actor.global_transform.basis.z
	return TargetingRules.yaw_of(fwd) if Vector2(fwd.x, fwd.z).length_squared() > 1e-8 else 0.0


## Sweeping Blow: a cylinder pulse (pulse_radius(), height = height_m or the actor's height)
## on the first active tick, kept to |yaw delta| <= sector_deg / 2 of the facing, with
## occlusion from the attack origin. Pulse id 1, an area effect.
func _run_sector_pulse(a: ActionDef, tick: int) -> void:
	if not controller.is_first_active_tick():
		return
	var space := actor.get_world_3d().direct_space_state
	var feet := actor.global_position
	var radius := pulse_radius(a)
	var height := a.height_m if a.height_m > 0.0 else entity.combatant.height_m
	var center := feet + Vector3.UP * (height * 0.5)
	var origin: Vector3 = actor.attack_origin_global()
	var cands := HitQueryAdapter.cylinder_pulse(space, entity, center, radius, height, origin)
	var yaw := facing_yaw()
	var arc_deg := float(a.param("sector_deg", 360.0))
	var half := deg_to_rad(arc_deg * 0.5)
	var inside: Array = []
	for c: Dictionary in cands:
		var to: Vector3 = (c.point as Vector3) - feet
		to.y = 0.0
		if to.length_squared() < 1e-6 \
				or absf(TargetingRules.yaw_delta(yaw, TargetingRules.yaw_of(to))) <= half + 1e-4:
			inside.append(c)
	var ctx := context()
	ctx.area_effect = true
	HitFactory.queue(ctx, a, inside, 1, tick)
	Events.ability_effect.emit(tick, entity.entity_id, a.id, "sector", feet, radius, yaw, arc_deg)


## Projectile actions launch on their first active tick: the launch resolver (or
## default_launch) gives the origin and aim point, Projectile.launch_velocity the velocity, and
## the level's ProjectileSystem takes it from there. aim_point is cleared after every launch.
func _run_projectile(a: ActionDef, tick: int) -> void:
	if not controller.is_first_active_tick():
		return
	var spec := Projectile.spec_for(a)
	var launch: Dictionary = launch_resolver.call(a, spec) if launch_resolver.is_valid() \
		else default_launch(a, spec)
	aim_point = Vector3.INF
	var origin: Vector3 = launch.get("origin", actor.attack_origin_global())
	var aim: Vector3 = launch.get("aim", origin + -actor.global_transform.basis.z * float(spec.range_m))
	var velocity := Projectile.launch_velocity(origin, aim, spec)
	var system := ProjectileSystem.instance(actor.get_tree())
	system.spawn(entity, a, origin, velocity, context())
	Events.ability_effect.emit(tick, entity.entity_id, a.id, "cast", origin, 0.0, facing_yaw(), 0.0)


## Launch point and aim for actors without a launch resolver (enemies): launch_offset_m in the
## actor's own space (or its attack origin), aimed per spec.aim - "target": aim_point when the
## actor stored one at its aim-lock tick, otherwise the anchor of its target at launch (the
## brain's target, else the nearest living entity it may damage); "forward": straight ahead at
## range. Player-only modes (lock_or_camera, camera) fall back to "target" here.
func default_launch(_a: ActionDef, spec: Dictionary) -> Dictionary:
	var offset: Vector3 = spec.get("launch_offset", Vector3.INF)
	var origin: Vector3 = actor.to_global(offset) if offset != Vector3.INF else actor.attack_origin_global()
	var forward := -actor.global_transform.basis.z
	var aim := origin + forward * float(spec.get("range_m", 25.0))
	if str(spec.get("aim", "target")) != "forward":
		if aim_point != Vector3.INF:
			aim = aim_point
		else:
			var t := _default_target()
			if t != null:
				aim = t.anchor_position()
	return {"origin": origin, "aim": aim}


## The brain's living target (enemies), else the nearest living entity this actor may damage.
func _default_target() -> CombatEntity:
	var brain: Variant = actor.get("brain")
	if brain is Object and "target_id" in brain and str(brain.get("target_id")) != "":
		var t := Sim.get_entity(str(brain.get("target_id")))
		if t != null and t.is_alive():
			return t
	var best: CombatEntity = null
	var best_d := INF
	for e in Sim.entities():
		if e == entity or not e.is_alive() or not CombatEntity.can_damage(entity.team, e.team):
			continue
		var d := actor.global_position.distance_squared_to(e.actor.global_position)
		if d < best_d:
			best = e
			best_d = d
	return best


## self_statuses are applied when an action enters ACTIVE (Stone Skin, Mend, Titan Surge),
## whatever its hit shape. Emits ability_effect "self_buff" when one was applied.
func _on_phase_entered(a: ActionDef, _instance_id: int, phase: int) -> void:
	if phase != ActionDef.Phase.ACTIVE or a == null:
		return
	var list: Variant = a.param("self_statuses")
	if typeof(list) != TYPE_ARRAY or (list as Array).is_empty():
		return
	var applied := false
	for entry: Variant in list:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		if entity.apply_status(str(entry.get("status", "")), float(entry.get("magnitude", NAN)),
				float(entry.get("duration_s", -1.0)), entity.entity_id):
			applied = true
	if applied:
		Events.ability_effect.emit(Sim.tick, entity.entity_id, a.id, "self_buff", actor.global_position,
			0.0, facing_yaw(), 0.0)


# --------------------------------------------------------------------------- P30 shapes
# Registered at the P30 anchor of _init; the hook in run() is _p30_run (plan M6-M9 §2.10).

## P30 (decision 20): () -> CombatEntity - the NPC or prop an enemy's target provider fights now
## (EnemyActor._p30_provider_target); null = none. The M1 team rule lets an enemy's hit queries
## reach only the player, so for each hit query of this runner that one NEUTRAL entity counts as
## a target (its team is the player's for the duration of the query, then restored). Unset: no
## change.
var provider_target := Callable()


## run()'s call of a shape handler: plain, or with the provider's NPC or prop made hittable.
func _p30_run(handler: Callable, a: ActionDef, tick: int) -> void:
	var t: CombatEntity = provider_target.call() if provider_target.is_valid() else null
	if t == null or t.team != CombatEntity.Team.NEUTRAL or not t.is_alive():
		handler.call(a, tick)
		return
	t.team = CombatEntity.Team.PLAYER
	handler.call(a, tick)
	t.team = CombatEntity.Team.NEUTRAL


## A formation's brace (P30, decision 19): on the first active tick, one band - a box along the
## actor's band (EnemyActor.p30_brace_band(): its formation's front_band(), as wide as the front
## rank and band depth deep, height_m tall, standing on the ground) - catches every hurtbox inside
## it whose centre a clear line reaches from the front rank's chest height; one hit per target per
## pulse (pulse id 1, the action's max_hits_per_target through the controller's registry). The hit
## strikes as an attacker of the brace's height (the action's attacker_height_override_m when it
## has one, else EnemyActor.p30_brace_height(), 5 m): poise and knockback treat it as coming from
## a 5 m attacker, so pikes stagger a stage-4 giant's legs; the damage keeps the action's
## size_policy. Emits ability_effect "band" (centre, half width, yaw, depth).
func _run_band_pulse(a: ActionDef, tick: int) -> void:
	if not controller.is_first_active_tick():
		return
	var band := band_of(a)
	var height := a.height_m if a.height_m > 0.0 else 3.0
	var yaw := float(band.yaw)
	var center: Vector3 = band.center
	var near: Vector3 = band.near
	var shape := BoxShape3D.new()
	shape.size = Vector3(float(band.half_width) * 2.0, height, float(band.depth))
	var params := PhysicsShapeQueryParameters3D.new()
	params.collide_with_areas = true
	params.collide_with_bodies = false
	params.collision_mask = HitQueryAdapter.LAYER_HURTBOX
	params.shape = shape
	params.transform = Transform3D(Basis(Vector3.UP, yaw), Vector3(center.x, center.y + height * 0.5, center.z))
	var space := actor.get_world_3d().direct_space_state
	var los_from := near + Vector3.UP * 1.2
	var cands: Array = []
	for r: Dictionary in HitQueryAdapter.intersect_all(space, params):
		var hb := r.get("collider") as Hurtbox
		if hb == null or hb.entity == null:
			continue
		var target := hb.entity
		if target == entity or not CombatEntity.can_damage(entity.team, target.team):
			continue
		var c := hb.global_position
		if not HitQueryAdapter.line_clear(space, los_from, c, HitQueryAdapter.OCCLUDER_MASK, target.occlusion_rids):
			continue
		cands.append({"entity": target, "hurtbox": hb, "point": c, "substep": 0,
			"distance": Vector2(c.x - near.x, c.z - near.z).length(), "weak_point": hb.weak_point})
	var override := float(a.param("attacker_height_override_m", 0.0))
	if override <= 0.0:
		override = float(actor.call("p30_brace_height")) if actor.has_method("p30_brace_height") else 5.0
	var ctx := context()
	HitFactory.sort_candidates(cands)
	for cand: Dictionary in cands:
		var target: CombatEntity = cand.entity
		if HitFactory.skip_candidate(ctx.entity, target, ctx.area_effect):
			continue
		if not ctx.registry.try_register(ctx.instance_id, 1, target.entity_id, a.max_hits_per_target):
			continue
		var e := HitFactory.build(ctx, a, cand, 1, tick)
		e.attacker_height_m = maxf(e.attacker_height_m, override)
		Sim.queue_hit(e)
	Events.ability_effect.emit(tick, entity.entity_id, a.id, "band", center, float(band.half_width), yaw,
		float(band.depth))


## The band a band_pulse of this actor strikes: the actor's p30_brace_band() (its formation's front
## band) when it has one, else a band in front of the actor as deep as the action's radius_m.
func band_of(a: ActionDef) -> Dictionary:
	if actor.has_method("p30_brace_band"):
		return actor.call("p30_brace_band")
	var depth := a.radius_m if a.radius_m > 0.0 else 4.0
	var yaw := facing_yaw()
	var fwd := Vector3(-sin(yaw), 0.0, -cos(yaw))
	return {"center": actor.global_position + fwd * (depth * 0.5), "near": actor.global_position,
		"half_width": 1.5, "depth": depth, "yaw": yaw}


# --------------------------------------------------------------------------- P31 shapes and casts
# Set up at the P31 anchor of _init (plan M6-M9 §2.11, §5.12): Earthquake's line_pulse; the weapon
# arc of a titanforged weapon with a perk (the plain P02 sweep otherwise); and the effects a cast
# brings when it enters ACTIVE (fury, a heal sized by the maximum health, cleared slows) or ends its
# active phase (the titanforged maul's shockwave).

## Earthquake's line of this action instance: {"instance", "origin" (the feet when the strike began),
## "yaw"} - the crack runs where the giant faced at its first active tick.
var _p31_line := {}
## The swing instance whose pierce (the titanforged sword) already struck its second target.
var _p31_pierced_instance := -1


func _p31_setup() -> void:
	register_shape("line_pulse", _run_line_pulse)
	register_shape("weapon_arc", _p31_run_weapon_arc)
	if controller != null:
		controller.phase_entered.connect(_p31_on_phase_entered)


## The `count` pulse centres of a line_pulse action `a` struck from `origin` facing `yaw` (on the
## ground: origin's height), from line.start_m to line.length_m ahead.
static func line_pulse_points(a: ActionDef, origin: Vector3, yaw: float) -> PackedVector3Array:
	var line: Dictionary = a.param("line", {}) if a != null else {}
	var count := maxi(1, int(line.get("count", 1)))
	var start := float(line.get("start_m", 0.0))
	var length := float(line.get("length_m", start))
	var fwd := Vector3(-sin(yaw), 0.0, -cos(yaw))
	var out := PackedVector3Array()
	for i in count:
		var d := start if count == 1 else lerpf(start, length, float(i) / float(count - 1))
		out.append(origin + fwd * d)
	return out


## The ticks between a line_pulse action's pulses (line.interval_s rounded to ticks, at least 1).
static func line_pulse_interval(a: ActionDef) -> int:
	var line: Dictionary = a.param("line", {}) if a != null else {}
	return maxi(1, ActionDef.seconds_to_ticks(float(line.get("interval_s", 0.0))))


## Earthquake (hit shape line_pulse): from the first active tick, every line_pulse_interval ticks one
## cylinder pulse (line.radius_m, line.height_m or height_m) at the next point of the line - pulse id
## i + 1, line of sight from the crack itself (0.8 m above it), an area effect - until line.count
## pulses have struck. Each pulse emits area_pulse (feedback, the impact cue).
func _run_line_pulse(a: ActionDef, tick: int) -> void:
	if controller.is_first_active_tick() or int(_p31_line.get("instance", -1)) != controller.instance_id:
		_p31_line = {"instance": controller.instance_id, "origin": actor.global_position, "yaw": facing_yaw()}
	var j := controller.elapsed - a.windup_ticks
	var interval := line_pulse_interval(a)
	if j < 0 or j % interval != 0:
		return
	var points := line_pulse_points(a, _p31_line.origin, float(_p31_line.yaw))
	var i := j / interval
	if i >= points.size():
		return
	var line: Dictionary = a.param("line", {})
	var radius := float(line.get("radius_m", 3.0))
	var height := float(line.get("height_m", a.height_m if a.height_m > 0.0 else 4.0))
	var point: Vector3 = points[i]
	var space := actor.get_world_3d().direct_space_state
	var cands := HitQueryAdapter.cylinder_pulse(space, entity, point + Vector3.UP * (height * 0.5), radius,
		height, point + Vector3.UP * 0.8)
	var ctx := context()
	ctx.area_effect = true
	HitFactory.queue(ctx, a, cands, i + 1, tick)
	Events.area_pulse.emit(tick, entity.entity_id, a.id, point, radius)


## The perk of the actor's weapon that changes this weapon blow's hits ({} = none): the titanforged
## club's formation poise on Heavy blows, the sword's pierce on its listed light 3s, the axe's flat
## penetration on every blow. The maul's shockwave comes after the swing (_p31_on_phase_entered).
func p31_perk_for(a: ActionDef) -> Dictionary:
	if a == null or not a.uses_weapon:
		return {}
	var w: Variant = actor.current_weapon() if actor.has_method("current_weapon") else {}
	if typeof(w) != TYPE_DICTIONARY or typeof((w as Dictionary).get("perk")) != TYPE_DICTIONARY:
		return {}
	var perk: Dictionary = w.perk
	match str(perk.get("kind", "")):
		"formation_poise":
			return perk if a.has_tag("Heavy") else {}
		"pierce":
			return perk if (perk.get("actions", []) as Array).has(a.id) else {}
		"flat_penetration":
			return perk
	return {}


## The weapon arc (P02's sweep) of a blow a perk changes: the same swept capsule, occlusion,
## dedupe and clank, with the perk applied to each hit it builds; any other blow is P02's sweep.
func _p31_run_weapon_arc(a: ActionDef, tick: int) -> void:
	var perk := p31_perk_for(a)
	if perk.is_empty():
		_run_weapon_arc(a, tick)
		return
	var space := actor.get_world_3d().direct_space_state
	var origin: Vector3 = actor.attack_origin_global()
	var cur: PackedVector3Array = actor.weapon_segment_global(a, controller.active_fraction())
	var prev := prev_segment
	if prev.size() != 2:
		prev = actor.weapon_segment_global(a, controller.active_fraction_prev())
	var cands := HitQueryAdapter.sweep_capsule(space, entity, origin, prev[0], prev[1],
		cur[0], cur[1], float(actor.weapon_hit_radius()))
	prev_segment = cur
	var ctx := context()
	HitFactory.sort_candidates(cands)
	for cand: Dictionary in cands:
		var target: CombatEntity = cand.entity
		if HitFactory.skip_candidate(ctx.entity, target, ctx.area_effect):
			continue
		if not ctx.registry.try_register(ctx.instance_id, 0, target.entity_id, a.max_hits_per_target):
			continue
		var e := HitFactory.build(ctx, a, cand, 0, tick)
		p31_apply_perk(perk, e, target)
		Sim.queue_hit(e)
		if str(perk.get("kind", "")) == "pierce" and _p31_pierced_instance != ctx.instance_id:
			_p31_pierce(perk, a, ctx, target, tick)
	if emit_clank and _clanked_instance != controller.instance_id:
		var wall := HitQueryAdapter.first_world_hit(space, origin, cur[1], [])
		if not wall.is_empty():
			_clanked_instance = controller.instance_id
			Events.attack_clanked.emit(tick, entity.entity_id, controller.instance_id, wall.position)


## Applies a perk to one built hit on `target`: formation_poise multiplies the poise of a blow on a
## formation member (EnemyActor.formation_id); flat_penetration adds armour penetration.
static func p31_apply_perk(perk: Dictionary, e: HitEvent, target: CombatEntity) -> void:
	match str(perk.get("kind", "")):
		"formation_poise":
			if p31_in_formation(target):
				e.poise_damage *= float(perk.get("poise_mult", 1.0))
		"flat_penetration":
			e.flat_penetration += float(perk.get("flat_penetration", 0.0))


## True when `target` stands in a formation (P30: an EnemyActor whose formation_id is set).
static func p31_in_formation(target: CombatEntity) -> bool:
	if target == null or target.actor == null or not is_instance_valid(target.actor):
		return false
	var fid: Variant = target.actor.get("formation_id")
	return typeof(fid) == TYPE_STRING and str(fid) != ""


## The titanforged sword's pierce: the blow that struck `first` runs on into the nearest other foe
## standing in line behind it - beyond it along the line from the attacker through it, at most
## perk.range_m x the attacker's body scale farther, within its radius plus the weapon's of that line
## - once per swing (pulse id 2, the same registry).
func _p31_pierce(perk: Dictionary, a: ActionDef, ctx: AttackContext, first: CombatEntity, tick: int) -> void:
	if first.actor == null or not is_instance_valid(first.actor):
		return
	var from := actor.global_position
	var to: Vector3 = (first.actor as Node3D).global_position - from
	to.y = 0.0
	if to.length_squared() < 1e-6:
		return
	var dir := to.normalized()
	var start := to.length()
	var reach := float(perk.get("range_m", 1.5)) * _p31_body_scale()
	var best: CombatEntity = null
	var best_s := INF
	for e: CombatEntity in Sim.entities():
		if e == entity or e == first or not e.is_alive() or e.actor == null or not is_instance_valid(e.actor) \
				or not CombatEntity.can_damage(entity.team, e.team):
			continue
		var rel: Vector3 = (e.actor as Node3D).global_position - from
		rel.y = 0.0
		var s := rel.dot(dir) - start
		var side := (rel - dir * rel.dot(dir)).length()
		if s <= 0.0 or s > reach or side > EnemyActor.entity_radius(e) + float(actor.weapon_hit_radius()):
			continue
		if s < best_s:
			best_s = s
			best = e
	if best == null or not ctx.registry.try_register(ctx.instance_id, 2, best.entity_id, a.max_hits_per_target):
		return
	_p31_pierced_instance = ctx.instance_id
	var e := HitFactory.build(ctx, a, {"entity": best, "hurtbox": null, "point": best.anchor_position(),
		"substep": 0, "distance": start + best_s, "weak_point": false}, 2, tick)
	Sim.queue_hit(e)


## The actor's size relative to the stage-1 giant (its growth profile's height, else its combatant's).
func _p31_body_scale() -> float:
	var profile: Variant = actor.get("profile")
	if typeof(profile) == TYPE_DICTIONARY and (profile as Dictionary).has("height_m"):
		return float(profile.height_m) / CombatRules.REFERENCE_HEIGHT_M
	return entity.combatant.height_m / CombatRules.REFERENCE_HEIGHT_M if entity != null else 1.0


## A cast's own effects when it enters ACTIVE (after any self_statuses): fury_on_cast (Wild Surge),
## heal_over_time (Primal Regrowth: the status's heal_per_tick sized so its periodic heals add up to
## max_health_fraction of the maximum health) and clears_status_tags (the caster's statuses with
## those tags end: slows). When a Heavy blow of a weapon with the heavy_shockwave perk (the
## titanforged maul) leaves ACTIVE, the shockwave strikes where its head came down.
func _p31_on_phase_entered(a: ActionDef, _instance_id: int, phase: int) -> void:
	if a == null or entity == null:
		return
	if phase == ActionDef.Phase.ACTIVE:
		_p31_cast_effects(a)
	elif phase == ActionDef.Phase.RECOVERY and a.uses_weapon and a.has_tag("Heavy"):
		var w: Variant = actor.current_weapon() if actor.has_method("current_weapon") else {}
		var perk: Variant = (w as Dictionary).get("perk") if typeof(w) == TYPE_DICTIONARY else null
		if typeof(perk) == TYPE_DICTIONARY and str(perk.get("kind", "")) == "heavy_shockwave":
			_p31_shockwave(a, perk, Sim.tick)


func _p31_cast_effects(a: ActionDef) -> void:
	var fury := float(a.param("fury_on_cast", 0.0))
	if fury > 0.0:
		entity.combatant.pools.add_fury(fury)
	var hot: Variant = a.param("heal_over_time")
	if typeof(hot) == TYPE_DICTIONARY:
		var def := GameData.get_status(str(hot.get("status", "")))
		if def != null and def.tick_ticks > 0:
			var heals := maxi(1, int(def.duration_ticks / def.tick_ticks))
			var amount := float(hot.get("max_health_fraction", 0.0)) * entity.combatant.pools.health_max
			entity.apply_status(def.id, amount / heals, -1.0, entity.entity_id)
	var tags: Variant = a.param("clears_status_tags")
	if typeof(tags) == TYPE_ARRAY and not (tags as Array).is_empty():
		var statuses := entity.combatant.statuses
		for sid in statuses.active_ids():
			var sdef := GameData.get_status(sid)
			if sdef == null:
				continue
			for t: Variant in tags:
				if sdef.has_tag(str(t)):
					statuses.remove(sid)
					Events.status_expired.emit(Sim.tick, entity.entity_id, sid)
					break


## The titanforged maul's shockwave: a cylinder pulse of perk.radius_m on the ground under the
## weapon's head at the end of the heavy's arc, power_mult x the heavy's power, an area effect
## (pulse id 3; the blow's own targets are not struck twice).
func _p31_shockwave(a: ActionDef, perk: Dictionary, tick: int) -> void:
	var seg: PackedVector3Array = actor.weapon_segment_global(a, 1.0)
	var at := Vector3(seg[1].x, actor.global_position.y, seg[1].z)
	var radius := float(perk.get("radius_m", 3.0))
	var space := actor.get_world_3d().direct_space_state
	var cands := HitQueryAdapter.cylinder_pulse(space, entity, at + Vector3.UP * 1.5, radius, 3.0,
		at + Vector3.UP * 0.8)
	var wave := ActionDef.from_dict(a.params.merged({"power": a.power * float(perk.get("power_mult", 0.5)),
		"tags": ["Melee", "AoE", "Unparryable"]}, true))
	var ctx := context()
	ctx.area_effect = true
	ctx.attacker_position = at
	for c: Dictionary in cands:
		if controller.hit_registry.hits_for(ctx.instance_id, 0, (c.entity as CombatEntity).entity_id) > 0:
			continue
		HitFactory.queue(ctx, wave, [c], 3, tick)
	Events.area_pulse.emit(tick, entity.entity_id, a.id, at, radius)
