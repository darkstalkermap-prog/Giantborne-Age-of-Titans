class_name SettlementGarrison
extends Node3D
## C4 (decision C4-5): a settlement's garrison fights beside the giant - archers on Last Hearth's stone ring (tier 2)
## and the beacon tower's great bow (tier 3) loose at anything hostile that comes within their range: a raid's men,
## a troll, a wolf. Each post is a place on the walls with the garrison member who keeps it (an entity of the
## settlement's garrison encounter: no member alive, no shots from that post), the tier from which it is manned (and
## that tier's life come: its settled flag), its range, its interval and its arrow's power.
##
## Deterministic: posts in order, a target picked by distance then entity id among the living ENEMY-team entities in
## range (never a titan: arrows do nothing a titan would notice), the shot's hit queued for the tick its arrow
## arrives (flight at ARROW_SPEED_MPS) through Sim's hit resolution as a ranged hit from the garrison (its id: no XP,
## no loot - the giant earns those), never Sim.rng. Presentation: a streak along the arrow's flight, and
## Events.garrison_loosed (the cue router's bow).
## Posts (the world layout's garrison kind): [{"pos": [x, y, z] (the node's frame), "member": entity id or "",
## "min_tier", "range_m", "interval_s", "power", "kind": "bow" | "great_bow"}].

const HOOK_ORDER := 105
const ARROW_SPEED_MPS := 70.0
const DEFAULT_RANGE_M := 70.0
const DEFAULT_INTERVAL_S := 2.4
const DEFAULT_POWER := 60.0
const STREAK_LIFE_S := 0.6

@export var world_id := ""
@export var settlement_id := ""
@export var posts: Array = []

## Shots in flight: [{"due": tick, "target": id, "power", "from": Vector3, "kind"}].
var _flying: Array = []
var _next_tick: Array = []
var shots := 0
var hits := 0
var _streaks: Array = []   ## [{"node", "from", "to", "t"}] (presentation)


func _ready() -> void:
	add_to_group("settlement_garrisons")
	_next_tick = []
	for i in posts.size():
		_next_tick.append(0)
	Sim.add_hook(Sim.Hook.POST_ACTORS, self, _on_tick, HOOK_ORDER)


func _exit_tree() -> void:
	Sim.remove_hooks(self)
	_flying.clear()


func settlement() -> Dictionary:
	return SettlementRules.record(settlement_id)


## True when post `i` is manned now (its tier reached and settled, its member alive or none named).
func post_manned(i: int) -> bool:
	if i < 0 or i >= posts.size():
		return false
	var p: Dictionary = posts[i]
	var rec := settlement()
	if rec.is_empty():
		return false
	var tier := int(p.get("min_tier", 1))
	if SettlementRules.tier_of(SettlementWork.state(rec)) < tier:
		return false
	if not QuestConditions.truthy(WorldState.get_flag(SettlementRules.settled_flag(rec, tier))):
		return false
	var member := str(p.get("member", ""))
	if member == "":
		return true
	var e := Sim.get_entity(member)
	return e != null and e.is_alive()


func manned_count() -> int:
	var n := 0
	for i in posts.size():
		if post_manned(i):
			n += 1
	return n


func post_position(i: int) -> Vector3:
	var p: Dictionary = posts[i]
	var v: Variant = p.get("pos", [0, 0, 0])
	var local := Vector3(float(v[0]), float(v[1]), float(v[2])) if typeof(v) == TYPE_ARRAY else Vector3.ZERO
	var member := Sim.get_entity(str(p.get("member", "")))
	if member != null and member.is_alive() and is_instance_valid(member.actor):
		return (member.actor as Node3D).global_position + Vector3.UP * 1.6
	return to_global(local)


## The target post `i` would shoot now (null when none in range).
func pick_target(i: int) -> CombatEntity:
	var from := post_position(i)
	var range_m := float((posts[i] as Dictionary).get("range_m", DEFAULT_RANGE_M))
	var best: CombatEntity = null
	var best_d := INF
	for e: CombatEntity in Sim.entities():
		if e == null or not e.is_alive() or e.team != CombatEntity.Team.ENEMY or not is_instance_valid(e.actor):
			continue
		if not (e.actor as Node).is_inside_tree():
			continue
		if str(e.combatant.base_record.get("archetype", "")) == "titan":
			continue
		var at := (e.actor as Node3D).global_position
		var d := Vector2(at.x - from.x, at.z - from.z).length()
		if d > range_m:
			continue
		if d < best_d - 1e-4 or (absf(d - best_d) <= 1e-4 and best != null and e.entity_id < best.entity_id):
			best = e
			best_d = d
	return best


func _on_tick(tick: int) -> void:
	# arrows arriving
	var still: Array = []
	for f: Dictionary in _flying:
		if int(f.due) <= tick:
			_land(f)
		else:
			still.append(f)
	_flying = still
	for i in posts.size():
		if tick < int(_next_tick[i]) or not post_manned(i):
			continue
		var t := pick_target(i)
		if t == null:
			continue
		var p: Dictionary = posts[i]
		var from := post_position(i)
		var to := (t.actor as Node3D).global_position + Vector3.UP * minf(1.4, t.combatant.height_m * 0.5)
		var flight := maxi(1, int(ceil(from.distance_to(to) / ARROW_SPEED_MPS * Sim.TICK_RATE)))
		_flying.append({"due": tick + flight, "target": t.entity_id, "power": float(p.get("power", DEFAULT_POWER)),
			"from": from, "kind": str(p.get("kind", "bow"))})
		_next_tick[i] = tick + int(round(float(p.get("interval_s", DEFAULT_INTERVAL_S)) * Sim.TICK_RATE))
		shots += 1
		Events.garrison_loosed.emit(tick, settlement_id, from, str(p.get("kind", "bow")))
		_streak(from, to, float(flight) / Sim.TICK_RATE)


func _land(f: Dictionary) -> void:
	var t := Sim.get_entity(str(f.target))
	if t == null or not t.is_alive():
		return
	var h := HitEvent.new()
	h.tick = Sim.tick
	h.instance_id = Sim.new_instance_id()
	h.attacker_id = "%s.garrison" % settlement_id
	h.target_id = t.entity_id
	h.action_id = "garrison." + str(f.kind)
	h.power = float(f.power)
	h.attacker_stat = 10.0
	h.attacker_height_m = 1.8
	h.size_policy = "none"
	h.damage_split = {"physical": 1.0}
	h.poise_damage = 8.0 if str(f.kind) == "bow" else 40.0
	h.category = "projectile"
	h.from_projectile = true
	h.tags = PackedStringArray(["Ranged", "Projectile"])
	h.attacker_position = f.from
	if is_instance_valid(t.actor):
		h.hit_point = (t.actor as Node3D).global_position + Vector3.UP
	Sim.queue_hit(h)
	hits += 1


# --------------------------------------------------------------------------- the streaks (presentation)

func _streak(from: Vector3, to: Vector3, life_s: float) -> void:
	if DisplayServer.get_name() == "headless" or not is_inside_tree():
		return
	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.06, 0.06, 1.6)
	mi.mesh = box
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.32, 0.25, 0.18)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	mi.global_position = from
	if from.distance_to(to) > 0.1:
		mi.look_at(to, Vector3.UP)
	_streaks.append({"node": mi, "from": from, "to": to, "t": 0.0, "life": maxf(0.15, minf(life_s, STREAK_LIFE_S * 3.0))})


func _process(delta: float) -> void:
	if _streaks.is_empty():
		return
	var keep: Array = []
	for s: Dictionary in _streaks:
		s.t = float(s.t) + delta
		var n := s.node as MeshInstance3D
		if not is_instance_valid(n):
			continue
		var f := clampf(float(s.t) / float(s.life), 0.0, 1.0)
		var at: Vector3 = (s.from as Vector3).lerp(s.to, f)
		at.y += sin(f * PI) * 2.0
		n.global_position = at
		if f >= 1.0:
			n.queue_free()
		else:
			keep.append(s)
	_streaks = keep
