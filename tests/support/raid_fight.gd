class_name RaidFight
extends RefCounted
## The milestone C gate (docs/systems/Cgate.md, finding G3): the Rimward's raid on Last Hearth fought by the bots' own
## fighting (BotCombat: the lock, the reach, the light chain and the heavies, the abilities by rule, the dodges and
## parries of its skill profile, all through the giant's input router) as a defender plays it: of the raiders it goes
## for the one nearest the Hearth's folk (the rimkin warleader only when he is the nearest threat to the giant itself
## or no man is left), sprinting between them. With `idle` the giant stands at the bonfire and does nothing: what the
## garrison (or nobody) does alone. It stands in for the ValleyBot BotCombat reads (metrics, steer_toward,
## steer_world, stop_moving). Used by tests/gate/test_cgate_raid.gd and the gate's measurement runs.

const RAIDER_PREFIX := "world.hoarfell.hearth_raider_"
const FOLK_PREFIX := "world.hoarfell.hearth_folk_"
## A man this close to one of the folk is the giant's first business.
const FOLK_THREAT_M := 25.0

var player: GiantPlayer
var combat := BotCombat.new()
var metrics := RunMetrics.new()
var rng := RandomNumberGenerator.new()
var idle := false
var prefer_heavy := false
## The report: kills by who made them, the folk lost, the giant's lowest health share.
var kills := {"giant": 0, "garrison": 0, "other": 0}
var killed: Array = []
var folk_lost := 0
var lowest_health := 1.0
var giant_dead := false
## Damage to the giant by its source (the raider's definition), and the giant's damage dealt to the raiders.
var taken := {}
var dealt := 0
var garrison_dealt := 0
var _connected := false


func setup(p: GiantPlayer, skill: String, seed_value: int, p_idle := false) -> void:
	player = p
	idle = p_idle
	rng.seed = seed_value
	p.router.use_injection = true
	if p.attack != null:
		p.attack.bot_controls()
	combat.setup(self, p, skill, rng)
	if not _connected:
		_connected = true
		Events.entity_died.connect(_on_died)
		Events.hit_resolved.connect(_on_hit)


func teardown() -> void:
	combat.teardown()
	if _connected and Events.entity_died.is_connected(_on_died):
		Events.entity_died.disconnect(_on_died)
	if _connected and Events.hit_resolved.is_connected(_on_hit):
		Events.hit_resolved.disconnect(_on_hit)
	_connected = false
	stop_moving()


func _on_hit(_tick: int, r: HitResult) -> void:
	if r == null or r.event == null or player == null:
		return
	if r.event.target_id == player.entity.entity_id and r.health_damage > 0:
		var src := Sim.get_entity(r.event.attacker_id)
		var key := src.definition_id.trim_prefix("enemy.") if src != null else r.event.attacker_id
		taken[key] = int(taken.get(key, 0)) + r.health_damage
	elif r.event.target_id.contains("hearth_raider"):
		if r.event.attacker_id == player.entity.entity_id:
			dealt += r.health_damage
		elif r.event.attacker_id.ends_with(".garrison"):
			garrison_dealt += r.health_damage


func _on_died(_tick: int, id: String, killer: String) -> void:
	if id.begins_with(RAIDER_PREFIX) or id.contains("hearth_raider"):
		var who := "giant" if killer == "player" or (player != null and killer == player.entity.entity_id) \
			else ("garrison" if killer.ends_with(".garrison") or killer.contains("hearth_garrison") else "other")
		kills[who] = int(kills[who]) + 1
		killed.append([id, killer])
	elif id.begins_with(FOLK_PREFIX):
		folk_lost += 1
	elif player != null and id == player.entity.entity_id:
		giant_dead = true


func raiders() -> Array[EnemyActor]:
	var out: Array[EnemyActor] = []
	for e: CombatEntity in Sim.entities():
		if e == null or not e.is_alive() or e.team != CombatEntity.Team.ENEMY or not is_instance_valid(e.actor):
			continue
		if not e.entity_id.contains("hearth_raider"):
			continue
		if e.actor is EnemyActor and (e.actor as Node).is_inside_tree():
			out.append(e.actor as EnemyActor)
	return out


func _folk_positions() -> Array[Vector3]:
	var out: Array[Vector3] = []
	for e: CombatEntity in Sim.entities():
		if e != null and e.is_alive() and e.entity_id.begins_with(FOLK_PREFIX) and is_instance_valid(e.actor):
			out.append((e.actor as Node3D).global_position)
	return out


## The raider it goes for, as a defender plays it: a man within FOLK_THREAT_M of the folk first (the nearest such to
## the giant), else whatever stands nearest the giant (the warleader holding him included).
func pick() -> EnemyActor:
	var rs := raiders()
	if rs.is_empty():
		return null
	var at := player.global_position
	var folk := _folk_positions()
	var best: EnemyActor = null
	var best_d := INF
	for r in rs:
		if r.entity.combatant.height_m > 4.0 or (r.brain != null and r.brain.state == EnemyBrain.AIState.ROUTED):
			continue
		var near_folk := false
		for f in folk:
			if _flat(r.global_position - f).length() < FOLK_THREAT_M:
				near_folk = true
		var d := _flat(r.global_position - at).length()
		if near_folk and d < best_d:
			best = r
			best_d = d
	if best != null:
		return best
	for r in rs:
		if r.brain != null and r.brain.state == EnemyBrain.AIState.ROUTED:
			continue
		var d := _flat(r.global_position - at).length() - EnemyActor.entity_radius(r.entity)
		if d < best_d:
			best = r
			best_d = d
	return best


func tick(t: int) -> void:
	var pools := player.entity.combatant.pools
	lowest_health = minf(lowest_health, pools.health / maxf(1.0, pools.health_max))
	if idle or not player.entity.is_alive():
		stop_moving()
		return
	if combat.defend(t):
		return
	var target := pick()
	if target == null:
		stop_moving()
		return
	combat.fight(t, target)


static func _flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0.0, v.z)


func steer_toward(point: Vector3, sprint: bool) -> void:
	steer_world((point - player.global_position).normalized(), sprint)


func steer_world(dir: Vector3, sprint: bool) -> void:
	var flat := Vector3(dir.x, 0.0, dir.z)
	if flat.length_squared() < 1e-6:
		stop_moving()
		return
	var basis_yaw := player.camera_rig.yaw
	var locked := player.targeting.locked_entity()
	if locked != null and locked.is_alive() and not player.camera_rig.is_first_person():
		basis_yaw = player.motor.yaw_to(locked.anchor_position())
	else:
		player.camera_rig.yaw = lerp_angle(player.camera_rig.yaw, TargetingRules.yaw_of(flat), 0.25)
		basis_yaw = player.camera_rig.yaw
	var local := flat.normalized().rotated(Vector3.UP, -basis_yaw)
	player.router.set_injected_move(Vector2(local.x, -local.z).limit_length(1.0))
	player.router.set_injected_hold(&"sprint", sprint)


func stop_moving() -> void:
	if player == null or not is_instance_valid(player):
		return
	player.router.set_injected_move(Vector2.ZERO)
	player.router.set_injected_hold(&"sprint", false)
