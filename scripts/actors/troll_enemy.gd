class_name TrollEnemy
extends OgreEnemy
## Trolls (plan M6-M9 §2.10, §5.13, §4.6; P34): enemy.troll (5.5 m), enemy.troll_whelp (3.5 m) and the
## Troll Matriarch (enemy.troll_matriarch, 9 m, a boss). The ogre's glue and super-armoured strikes,
## a TrollBrain (OgreBrain tactics), and EnemyActor's P34 regeneration: every second a hurt troll that
## is not Burning heals (12 hp/s; the Matriarch 25, 40 in her second phase) and refreshes its marker
## status, which this actor shows as a slow green pulse on its rig (an orange flicker while it burns).
## Fire: a brazier broken near it, the den's fire pit (a node of group fire_pits with meta radius_m: a
## troll or whelp thrown or dropped into it comes out Burning for THROWN_BURN_S), and - for the
## Matriarch - a burning body thrown into her (Burning thrown_burn_s and THROWN_FIRE_DAMAGE fire).
## Grabbable from stage 5 (two hands: 5.5 m is no more than half of 14.63 m); a whelp from stage 3.
##
## The Matriarch (her record's boss block, brood and drive_out; a MatriarchBrain):
##   * never grabbable (9 m is 61 % of a stage-5 giant; spec §8), group "bosses";
##   * her whelp throw: at its windup she picks up the nearest free whelp of brood.definition within
##     brood.reach_m (it rides her hand), and the throw's projectile (visual thrown_body) carries it at
##     the giant (ProjectileSystem.carry_body) - it lands and fights on; the brain skips the throw while
##     no whelp is in reach;
##   * a phase's `summon`: her roar calls that many whelps (up to brood.max_alive living), placed
##     summon_radius_m from her;
##   * the drive-out ending: once every drive_out.requires_flags flag holds and her health is at or
##     below health_frac, she stops fighting and runs to the marker exit_marker; there (or leave_s
##     after she set off) her outcome is "fled", Events.boss_disengaged(id, "fled") and she leaves.

const REGEN_TINT := Color(0.32, 0.95, 0.42)
const BURN_TINT := Color(1.0, 0.42, 0.10)
const TINT_PULSE_HZ := 1.2
const FIRE_PIT_GROUP := "fire_pits"
const FIRE_PIT_DEFAULT_RADIUS_M := 4.0
const THROWN_BURN_S := 10.0
const THROWN_FIRE_DAMAGE := 300.0
## She is out of the den this close to its exit marker.
const EXIT_ARRIVE_M := 3.0
## Where a carried whelp rides when the throw's action has no launch offset (her own space).
const DEFAULT_HAND := Vector3(-2.6, 8.2, 0.4)

## Whelps thrown (tests, debug).
var whelp_throws := 0
## Entity ids of the whelps her roars called.
var summoned: Array[String] = []
## True once she fled through the drive-out exit.
var fled := false
## The status tint painted now (alpha 0 = none; presentation).
var tint := Color(0, 0, 0, 0)
var _brood: Dictionary = {}
var _drive: Dictionary = {}
var _carried: EnemyActor = null
var _flee_started := -1
var _summon_seq := 0
var _time := 0.0


func _ready() -> void:
	super()
	var b: Variant = record.get("brood")
	_brood = b if typeof(b) == TYPE_DICTIONARY else {}
	var d: Variant = record.get("drive_out")
	_drive = d if typeof(d) == TYPE_DICTIONARY else {}
	if is_matriarch():
		install_boss_hooks()
		brain.boss_phase_entered.connect(_on_matriarch_phase)
		(brain as MatriarchBrain).whelp_ready = whelp_in_reach
	elif brain is TrollBrain:
		(brain as TrollBrain).burning_probe = p34_has_status_tag.bind("Burning")
	controller.phase_entered.connect(_on_troll_phase_entered)
	controller.action_ended.connect(_on_troll_action_ended)
	if not _brood.is_empty():
		Events.projectile_spawned.connect(_on_projectile_spawned)
	if is_matriarch():
		Events.projectile_impact.connect(_on_projectile_impact)


func _make_brain() -> EnemyBrain:
	var seed_value := Sim.DEFAULT_SEED ^ hash(entity.entity_id)
	if typeof(record.get("boss")) == TYPE_DICTIONARY:
		return MatriarchBrain.new(entity.entity_id, record, seed_value)
	return TrollBrain.new(entity.entity_id, record, seed_value)


## True for the Matriarch (a troll with boss phases).
func is_matriarch() -> bool:
	return brain != null and brain.has_boss_phases()


func sim_step(tick: int, dt: float) -> void:
	if is_matriarch():
		p34_boss_step(tick)
		update_boss_phase()
	p34_regen_step(tick)
	_drive_out_step(tick)
	super(tick, dt)
	if is_matriarch():
		queue_chain_next()
	_carry_step()


## The boss bar's pips (the Matriarch).
func boss_phase() -> int:
	return brain.boss_phase() if brain != null else 0


func phase_count() -> int:
	return brain.boss_phase_count() if brain != null else 0


func can_be_grabbed() -> bool:
	return false if is_matriarch() else super()


# --------------------------------------------------------------------------- fire

## The fire pit holding `point`, or null (nodes of group fire_pits, meta radius_m).
func fire_pit_at(point: Vector3) -> Node3D:
	if not is_inside_tree():
		return null
	for n in get_tree().get_nodes_in_group(FIRE_PIT_GROUP):
		var pit := n as Node3D
		if pit == null:
			continue
		var r := float(pit.get_meta("radius_m", FIRE_PIT_DEFAULT_RADIUS_M))
		if Vector2(point.x - pit.global_position.x, point.z - pit.global_position.z).length() <= r:
			return pit
	return null


## A troll or whelp set down in the fire pit (thrown or dropped) comes out Burning.
func on_released(reason: String, fallbacks: Array = []) -> void:
	super(reason, fallbacks)
	if is_inside_tree() and entity.is_alive() and fire_pit_at(global_position) != null:
		p34_ignite(float(_p34_regen.get("thrown_burn_s", THROWN_BURN_S)))


## A body the giant threw that hit the Matriarch: a burning one sets her Burning (thrown_burn_s) and
## burns her for thrown_damage fire (once per throw).
func _on_projectile_impact(_tick: int, projectile_id: int, _point: Vector3, hit_entity_id: String) -> void:
	if hit_entity_id != entity.entity_id or not entity.is_alive() or not is_inside_tree():
		return
	var system := ProjectileSystem.instance(get_tree())
	var pr := system.get_projectile(projectile_id) if system != null else null
	if pr == null or pr.held_entity_id == "" or pr.owner_id == entity.entity_id:
		return
	var body := Sim.get_entity(pr.held_entity_id)
	if body == null or not is_instance_valid(body.actor) or not body.actor.has_method("p34_has_status_tag") \
			or not bool(body.actor.call("p34_has_status_tag", "Burning")):
		return
	p34_ignite(float(_p34_regen.get("thrown_burn_s", THROWN_BURN_S)), pr.owner_id)
	var h := HitEvent.new()
	h.tick = Sim.tick
	h.instance_id = Sim.new_instance_id()
	h.attacker_id = pr.owner_id
	h.target_id = entity.entity_id
	h.action_id = "fire.thrown_body"
	h.power = float(_p34_regen.get("thrown_damage", THROWN_FIRE_DAMAGE))
	h.attacker_stat = 0.0
	h.size_policy = "none"
	h.damage_split = {"fire": 1.0}
	h.tags = PackedStringArray(["Fire", "Unblockable", "Unparryable"])
	h.attacker_position = pr.position
	Sim.queue_hit(h)


# --------------------------------------------------------------------------- the whelp throw

## True when a free whelp waits within brood.reach_m (the brain's throw needs one).
func whelp_in_reach() -> bool:
	return _nearest_whelp() != null


func _nearest_whelp() -> EnemyActor:
	if _brood.is_empty() or not is_inside_tree():
		return null
	var best: EnemyActor = null
	var best_d := float(_brood.get("reach_m", 16.0))
	for n in get_tree().get_nodes_in_group("enemies"):
		var w := n as EnemyActor
		if w == null or w == self or w.entity == null or w.entity.definition_id != str(_brood.get("definition", "")):
			continue
		if not w.entity.is_alive() or not w.can_be_grabbed() or w.controller.state == CombatController.State.STAGGERED:
			continue
		var d := w.global_position.distance_to(global_position)
		if d <= best_d:
			best = w
			best_d = d
	return best


func _on_troll_phase_entered(action: ActionDef, _instance_id: int, phase: int) -> void:
	if action == null or action.id != str(_brood.get("throw_action", "")) or phase != ActionDef.Phase.WINDUP:
		return
	var w := _nearest_whelp()
	if w == null or not w.controller.enter_grabbed(entity.entity_id):
		controller.call("_finish_action", true)   # nothing to throw: the throw ends at once
		return
	w.on_grabbed(entity.entity_id)
	_carried = w
	_carry_step()


## The carried whelp rides her throwing hand (the throw's launch offset).
func _carry_step() -> void:
	if _carried == null:
		return
	if not is_instance_valid(_carried) or not _carried.is_held() or _carried.grab_holder_id != entity.entity_id:
		_carried = null
		return
	var a := GameData.get_action(str(_brood.get("throw_action", "")))
	var spec := Projectile.spec_for(a) if a != null else {}
	var offset: Vector3 = spec.get("launch_offset", Vector3.INF)
	if offset == Vector3.INF:
		offset = DEFAULT_HAND
	_carried.carry(to_global(offset), global_transform.basis, _carried.body_centre_local())


func _on_projectile_spawned(_tick: int, projectile_id: int, owner_id: String, action_id: String,
		_position: Vector3, _velocity: Vector3, _visual: String) -> void:
	if owner_id != entity.entity_id or action_id != str(_brood.get("throw_action", "")) or _carried == null:
		return
	var w := _carried
	_carried = null
	var system := ProjectileSystem.instance(get_tree())
	if system != null and is_instance_valid(w) and system.carry_body(projectile_id, w.entity_id, entity.entity_id):
		whelp_throws += 1
	elif is_instance_valid(w):
		w.on_released("dropped")


## A throw that ended before its launch (a stagger, death, a new attempt) drops the whelp.
func _on_troll_action_ended(_action: ActionDef, _instance_id: int, _interrupted: bool) -> void:
	_drop_carried()


func _drop_carried() -> void:
	if _carried != null and is_instance_valid(_carried) and _carried.is_held() \
			and _carried.grab_holder_id == entity.entity_id:
		_carried.on_released("dropped")
	_carried = null


func on_entity_died(killer_id: String) -> void:
	_drop_carried()
	super(killer_id)


# --------------------------------------------------------------------------- summons

func _on_matriarch_phase(phase: int, _phase_id: String, _enter_action: String) -> void:
	var rec: Dictionary = brain.boss_phases[phase - 1] if phase - 1 < brain.boss_phases.size() else {}
	var n := int(rec.get("summon", 0))
	if n > 0:
		p34_summon(n)


## Calls up to `count` whelps (never more than brood.max_alive living), summon_radius_m from her, each
## alerted to the giant. Returns how many came.
func p34_summon(count: int) -> int:
	var def_id := str(_brood.get("definition", ""))
	var path := str(GameData.get_record(def_id).get("scene", ""))
	var scene := load(path) as PackedScene if path != "" else null
	if scene == null or not is_inside_tree():
		return 0
	var band: Array = _brood.get("summon_radius_m", [8.0, 14.0])
	var room := int(_brood.get("max_alive", 6)) - _living_whelps()
	var came := 0
	var p := get_tree().get_first_node_in_group("player") as GiantPlayer
	while came < mini(count, room):
		_summon_seq += 1
		var ang := TAU * fposmod(float(_summon_seq) * 0.381966, 1.0) + facing_yaw
		var r := lerpf(float(band[0]), float(band[1]), fposmod(float(_summon_seq) * 0.618034, 1.0))
		var w := scene.instantiate() as EnemyActor
		w.entity_id = "%s.whelp_%d" % [entity.entity_id, _summon_seq]
		get_parent().add_child(w)
		w.global_position = global_position + Vector3(sin(ang), 0.05, cos(ang)) * r
		w.home_position = w.global_position
		if p != null and w.brain != null:
			w.brain.on_noise(Sim.tick, p.global_position, p.entity.entity_id, true)
		summoned.append(w.entity_id)
		came += 1
	return came


func _living_whelps() -> int:
	var n := 0
	for node in get_tree().get_nodes_in_group("enemies"):
		var w := node as EnemyActor
		if w != null and w.entity != null and w.entity.is_alive() \
				and w.entity.definition_id == str(_brood.get("definition", "")):
			n += 1
	return n


## A new attempt: the whelps her roars called go, a carried one is dropped.
func _p34_reset_extra() -> void:
	_drop_carried()
	for id in summoned:
		var e := Sim.get_entity(id)
		if e != null and is_instance_valid(e.actor):
			(e.actor as Node).queue_free()
	summoned.clear()
	_flee_started = -1


# --------------------------------------------------------------------------- the drive-out ending

## True when every drive_out.requires_flags flag holds and her health is at or below health_frac.
func drive_out_ready() -> bool:
	if _drive.is_empty() or entity == null or not entity.is_alive() or fled:
		return false
	for f: Variant in _drive.get("requires_flags", []):
		if not Waystone.flag_truthy(WorldState.get_flag(str(f))):
			return false
	return entity.combatant.pools.ratio("health") <= float(_drive.get("health_frac", 0.0)) + 1e-6


## True while she runs for the exit (and once she is gone).
func is_fleeing() -> bool:
	return _flee_started >= 0


func _drive_out_step(tick: int) -> void:
	if fled or _drive.is_empty() or not entity.is_alive():
		return
	if _flee_started < 0:
		if not drive_out_ready():
			return
		_flee_started = tick
		_drop_carried()
		ai_enabled = false   # she fights no more; she can still be chased and struck
		if controller.action != null:
			controller.call("_finish_action", true)
		controller.buffer.clear()
		Sim.release_all_tokens(entity.entity_id)
		brain.begin_return(tick)
	var exit := exit_point()
	brain.return_step(tick, exit)
	var arrived := Vector2(exit.x - global_position.x, exit.z - global_position.z).length() <= EXIT_ARRIVE_M
	if arrived or tick - _flee_started >= ActionDef.seconds_to_ticks(float(_drive.get("leave_s", 10.0))):
		_finish_flight(tick)


## The drive-out exit (the level marker exit_marker; her home when the level has none).
func exit_point() -> Vector3:
	var id := str(_drive.get("exit_marker", ""))
	for n in get_tree().get_nodes_in_group(LevelMarker.GROUP):
		if n is LevelMarker and (n as LevelMarker).marker_id == id:
			return (n as Node3D).global_position
	return home_position


func _finish_flight(tick: int) -> void:
	fled = true
	_p34_write_outcome("fled")
	Events.boss_disengaged.emit(tick, entity.entity_id, "fled")
	var director := get_tree().get_first_node_in_group(EncounterDirector.GROUP) as EncounterDirector
	if director != null and director.member_status(entity.entity_id) == EncounterDirector.SPAWNED:
		director.despawn(entity.entity_id)
	else:
		ai_enabled = false
		queue_free.call_deferred()


# --------------------------------------------------------------------------- presentation

func _process(delta: float) -> void:
	_time += delta
	var burning := p34_has_status_tag("Burning")
	var want := Color(0, 0, 0, 0)
	if burning:
		want = BURN_TINT
		want.a = 0.45 + 0.25 * absf(sin(_time * 17.0))
	elif p34_regenerating():
		want = REGEN_TINT
		want.a = 0.18 + 0.32 * (0.5 + 0.5 * sin(_time * TAU * TINT_PULSE_HZ))
	if want.a <= 0.0 and tint.a <= 0.0:
		return
	tint = want
	if rig != null:
		rig.set_status_tint(want)


func get_debug_info() -> Dictionary:
	var d := super()
	d["regen"] = "%d heals, %.0f hp%s" % [regen_heals, regen_healed, " (burning)" if p34_has_status_tag("Burning") else ""]
	if is_matriarch():
		d["phase"] = "%d/%d" % [boss_phase(), phase_count()]
		d["whelps"] = "%d thrown, %d called" % [whelp_throws, summoned.size()]
	return d
