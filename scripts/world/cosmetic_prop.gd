class_name CosmeticProp
extends Node3D
## A cosmetic prop (plan §3.8 design 2, decision 23): bushes, banners, barley sheaves. It has no
## CombatEntity and no collision, so attacks pass through it without a hit, and it is never
## saved. It reacts - presentation only - to:
##   * Events.area_pulse whose radius reaches it (Heavy Footfall, Thunder Roar, splashes);
##   * Events.ability_effect "sector" (Sweeping Blow: within the radius and the arc) and "roar";
##   * an actor (the giant, enemies, NPCs) coming within react_radius_m of it, checked at 5 Hz
##     from a Sim hook.
## A reaction is a short wobble away from its source, or a 4 s flatten when a stage-2+ giant
## steps into it. react() is public; react_count counts the reactions (one per tick at most, so a
## roar's pulse and its roar effect count once).
##
## Children: Visual (the meshes; the only node that moves). Group "cosmetic_props".

const GROUP := "cosmetic_props"
const CHECK_TICKS := 12             ## 5 Hz at the 60 Hz Sim
const HOOK_ORDER := 220             ## POST_RESOLVE, after the gameplay hooks
const FLATTEN_S := 4.0
const FLATTEN_SCALE_Y := 0.25
const FLATTEN_STAGE := 2            ## a giant of this stage or larger flattens it underfoot
const PULSE_MARGIN_M := 0.4         ## a pulse reaches the prop when its edge is this close
const DEFAULT_RADIUS_M := 1.5
const ACTOR_GROUPS := ["player", "enemies", "npcs"]

## The prop record ("prop.bush", "prop.banner"): category cosmetic.
@export var prop_id := "prop.bush"
## < 0: the record's react_radius_m (DEFAULT_RADIUS_M without one).
@export var react_radius_m := -1.0

var record: Dictionary = {}
var react_count := 0
var flattened := false
var last_react_source := Vector3.INF
var _visual: Node3D
var _inside := {}                   ## instance id -> true while that actor is within reach
var _phase := 0
var _last_react_tick := -1
var _tween: Tween
var _flat_left := 0.0


func _notification(what: int) -> void:
	if what == NOTIFICATION_ENTER_TREE:
		add_to_group(GROUP)


func _ready() -> void:
	record = GameData.get_record(prop_id)
	if record.is_empty():
		push_error("CosmeticProp %s: unknown prop record '%s'" % [get_path(), prop_id])
	if react_radius_m < 0.0:
		react_radius_m = float(record.get("react_radius_m", DEFAULT_RADIUS_M))
	_visual = get_node_or_null("Visual") as Node3D
	_phase = absi(hash(str(get_path()))) % CHECK_TICKS
	Events.area_pulse.connect(_on_area_pulse)
	Events.ability_effect.connect(_on_ability_effect)
	Sim.add_hook(Sim.Hook.POST_RESOLVE, self, _on_sim_tick, HOOK_ORDER)


func _exit_tree() -> void:
	Sim.remove_hooks(self)


## One reaction to something at `source` (world position). strength >= 1 flattens it for
## FLATTEN_S; less wobbles it. Counts once per tick.
func react(source: Vector3, strength: float) -> void:
	if Sim.tick == _last_react_tick:
		return
	_last_react_tick = Sim.tick
	react_count += 1
	last_react_source = source
	if _visual == null:
		return
	if strength >= 1.0:
		_flatten()
	elif not flattened:
		_wobble(source, strength)


func _on_area_pulse(_tick: int, _actor_id: String, _action_id: String, center: Vector3, radius: float) -> void:
	if not is_inside_tree():
		return
	if _flat_distance(center, global_position) <= radius + PULSE_MARGIN_M:
		react(center, 0.6)


func _on_ability_effect(_tick: int, _actor_id: String, _action_id: String, kind: String, center: Vector3,
		radius: float, yaw: float, arc_deg: float) -> void:
	if not is_inside_tree() or not kind in ["sector", "roar"]:
		return
	var to := global_position - center
	to.y = 0.0
	if to.length() > radius + PULSE_MARGIN_M:
		return
	if kind == "sector" and to.length() > 1e-3:
		if absf(angle_difference(yaw, TargetingRules.yaw_of(to))) > deg_to_rad(arc_deg * 0.5):
			return
	react(center, 0.7)


## Actors entering reach, checked every CHECK_TICKS ticks (phase-shifted per prop).
func _on_sim_tick(tick: int) -> void:
	if (tick + _phase) % CHECK_TICKS != 0 or not is_inside_tree():
		return
	var seen := {}
	for group: String in ACTOR_GROUPS:
		for n in get_tree().get_nodes_in_group(group):
			var actor := n as Node3D
			if actor == null or not actor.is_inside_tree():
				continue
			var key := actor.get_instance_id()
			if _flat_distance(actor.global_position, global_position) > react_radius_m + actor_radius(actor):
				continue
			seen[key] = true
			if not _inside.has(key):
				react(actor.global_position, 1.0 if flattens(actor) else 0.5)
	_inside = seen


## A giant of FLATTEN_STAGE or larger flattens cosmetic props underfoot.
static func flattens(actor: Node) -> bool:
	return actor.is_in_group("player") and "growth_stage" in actor and int(actor.get("growth_stage")) >= FLATTEN_STAGE


## The horizontal radius of an actor's body: the giant's profile capsule, a record's capsule.
static func actor_radius(actor: Node) -> float:
	for key: String in ["profile", "record"]:
		if key in actor:
			var rec: Variant = actor.get(key)
			if typeof(rec) == TYPE_DICTIONARY and (rec as Dictionary).has("capsule_radius_m"):
				return float(rec.capsule_radius_m)
	return 0.4


static func _flat_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


# --------------------------------------------------------------------------- presentation

func _wobble(source: Vector3, strength: float) -> void:
	var away := global_position - source
	away.y = 0.0
	# A small tilt about the horizontal axis at right angles to the push (local space; the
	# angles are small, so Euler x/z approximate the axis-angle rotation).
	var axis := global_basis.inverse() * (Vector3.UP.cross(away.normalized()) if away.length_squared() > 1e-6 else Vector3.RIGHT)
	var angle := deg_to_rad(10.0 + 14.0 * clampf(strength, 0.0, 1.0))
	var tilt := Vector3(axis.x, 0.0, axis.z)
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_visual.rotation = Vector3.ZERO
	_tween = create_tween()
	_tween.tween_property(_visual, "rotation", tilt * angle, 0.08)
	_tween.tween_property(_visual, "rotation", tilt * -angle * 0.5, 0.16)
	_tween.tween_property(_visual, "rotation", tilt * angle * 0.2, 0.14)
	_tween.tween_property(_visual, "rotation", Vector3.ZERO, 0.18)


func _flatten() -> void:
	flattened = true
	_flat_left = FLATTEN_S
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_visual.rotation = Vector3.ZERO
	_tween = create_tween()
	_tween.tween_property(_visual, "scale", Vector3(1.15, FLATTEN_SCALE_Y, 1.15), 0.12)


func _process(delta: float) -> void:
	if not flattened:
		return
	_flat_left -= delta
	if _flat_left > 0.0:
		return
	flattened = false
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(_visual, "scale", Vector3.ONE, 0.5)
