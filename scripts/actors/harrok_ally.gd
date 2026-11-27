class_name HarrokAlly
extends CharacterBody3D
## E1 (decision E1-4): Harrok the Unbowed beside the giant - act one's champion, spared (or knelt to the talk ending),
## come back to the Moot to stand with the giant against his own sister-son. He is the rival giants' body at his 15 m
## (scenes/actors/harrok_ally.tscn: SkinnedRig on giant_model.tscn, his look and his axe) and a real ally in the fight,
## but not a combat entity: no blow of Orrik's or the warband's is aimed at him (the team rule lets an enemy's blows
## reach only the giant's own team: allies with brains of their own would touch every pinned combat rule - C4-5's
## reason), and his own blows land through Sim's hits as the garrison's do (no XP, no loot: the giant earns those).
## What he does, decided every DECIDE_S from plain values (a seeded fight repeats):
##   1. **He cuts the giant's chains**: a fetter-winch's chain on the giant (PlayerFetter) sends him to that winch; at its
##      drum he hews the chain through (PlayerFetter.release(.., "cut")) and his blow lands on the winch.
##   2. **He goes for the winches**: while a winch is in the fight (crewed, shooting), he goes to it and strikes its crew
##      down, then the winch.
##   3. **Else he fights at Orrik's legs**, keeping off his front: a blow every STRIKE_S on his legs (damage and poise:
##      he helps the giant stagger him).
## He keeps out of the giant's way (never inside his capsule's reach), and he speaks a line as he comes, as he cuts and
## when Orrik falls. A new attempt sends him away (ThroneChallenge); death, travel and Continue reload the scene.

const DECIDE_S := 0.5
const RUN_MPS := 8.0
const TURN_DEG_S := 220.0
## His axe's reach (m, his capsule's edge to the target's).
const REACH_M := 7.5
## A chain hewn through: his swing, then the chain goes (s).
const SWING_ACTION := "ability.harrok_combo_1"
const STRIKE_S := 2.4
const WINCH_POWER := 650.0
const CREW_POWER := 420.0
const HEIR_POWER := 70.0
const HEIR_POISE := 140.0
## He keeps this far beyond the giant's capsule (m).
const GIANT_CLEARANCE_M := 4.0
const RADIUS_M := 3.2
const HEIGHT_M := 15.0
const GRAVITY := 30.0
const LINES := {
	"come": "Harrok: \"Orrik! You will not have the throne while I stand. Colossus - I am with you.\"",
	"cut": "Harrok: \"Hold still - I have your chain!\"",
	"winch": "Harrok: \"Leave the winches to me!\"",
	"fallen": "Harrok: \"It is done. He was my blood, and he chose this. The throne is yours to keep.\"",
}

@export var boss_id := ""

## What he is doing ("cut", "winch", "heir", "idle", "won"), and his tallies (tests, the duel report).
var task := "idle"
var chains_cut := 0
var winch_blows := 0
var crew_blows := 0
var heir_blows := 0
var lines_spoken: Array[String] = []
var _target_node: Node3D = null
var _target_id := ""
var _next_decide := 0
var _swing_from := -1
var _swing_target := ""
var _swing_kind := ""
var _swing_action: ActionDef
var _next_strike := 0
var _rig_ready := false
var _left := false


func _ready() -> void:
	add_to_group("harrok_allies")
	_swing_action = GameData.get_action(SWING_ACTION)
	Sim.add_hook(Sim.Hook.POST_ACTORS, self, _on_tick, 60)
	_say("come")


func _exit_tree() -> void:
	Sim.remove_hooks(self)


func _process(_delta: float) -> void:
	if not _rig_ready:
		_dress()


## His look and his axe on the rival giants' rig (SkinnedRig sets them up only for an EnemyActor).
func _dress() -> void:
	_rig_ready = true
	var rig := get_node_or_null("Visual")
	if rig == null or not rig.has_method("apply_look"):
		return
	var rec := Appearance.preset_record("appearance_preset.npc_harrok")
	if not rec.is_empty() and bool(rig.call("layers_on")):
		rig.call("apply_look", Appearance.to_look(rec))
	var w := GameData.get_record("weapon.giant_axe")
	if not w.is_empty() and rig.get("weapon_visual") == null:
		var node := WeaponVisuals.build(w)
		node.scale = Vector3.ONE / maxf(float(rig.get("body_scale")), 0.01)
		rig.call("set_weapon_visual", node)


func _say(key: String) -> void:
	lines_spoken.append(key)
	Events.hud_message.emit(str(LINES.get(key, "")), "info")


## Leaves the fight (a new attempt): he goes.
func leave() -> void:
	_left = true
	queue_free()


## Orrik has fallen.
func on_victory() -> void:
	task = "won"
	_swing_from = -1
	_say("fallen")


func _on_tick(tick: int) -> void:
	if _left or not is_inside_tree():
		return
	var dt := Sim.DT
	if task != "won" and tick >= _next_decide:
		_next_decide = tick + ActionDef.seconds_to_ticks(DECIDE_S)
		_decide()
	_swing_step(tick)
	_move(dt)


func _player() -> GiantPlayer:
	return get_tree().get_first_node_in_group("player") as GiantPlayer if is_inside_tree() else null


func _heir() -> Node3D:
	var e := Sim.get_entity(boss_id) if boss_id != "" else null
	return e.actor as Node3D if e != null and is_instance_valid(e.actor) and e.is_alive() else null


## The next task (see the class notes): the giant's chains, then the winches in the fight, then Orrik's legs.
func _decide() -> void:
	if _swing_from >= 0:
		return
	var p := _player()
	var best: Node3D = null
	var best_d := INF
	if p != null and p.fetter != null:
		for f: Dictionary in (p.fetter as PlayerFetter).fetters:
			if str(f.kind) != "winch":
				continue
			var e := Sim.get_entity(str(f.anchor))
			if e == null or not is_instance_valid(e.actor):
				continue
			var d := _flat(global_position, (e.actor as Node3D).global_position)
			if d < best_d:
				best_d = d
				best = e.actor as Node3D
	if best != null:
		if task != "cut":
			_say("cut")
		task = "cut"
		_target_node = best
		_target_id = str((best as FetterWinch).entity.entity_id)
		return
	best_d = INF
	for n in get_tree().get_nodes_in_group("fetter_winches"):
		var w := n as FetterWinch
		if w == null or w.destroyed or not w.is_inside_tree() or not w.in_action():
			continue
		var d := _flat(global_position, w.global_position)
		if d < best_d:
			best_d = d
			best = w
	if best != null:
		if task != "winch" and not lines_spoken.has("winch"):
			_say("winch")
		task = "winch"
		_target_node = best
		_target_id = str((best as FetterWinch).entity.entity_id)
		return
	var h := _heir()
	task = "heir" if h != null else "idle"
	_target_node = h
	_target_id = boss_id if h != null else ""


## Where he is going now (Vector3.INF: nowhere).
func goal() -> Vector3:
	if _target_node == null or not is_instance_valid(_target_node):
		return Vector3.INF
	var at := _target_node.global_position
	if task == "heir":
		# beside his legs, off his front (his left side, the coil's side), out of the giant's way
		var b := _target_node.global_transform.basis
		return at + b * Vector3(-11.0, 0.0, 3.0)
	if task == "winch":
		var w := _target_node as FetterWinch
		for c: Variant in w.crew():
			if is_instance_valid(c):
				return (c as Node3D).global_position
	return at


func _move(dt: float) -> void:
	var g := goal()
	var want := Vector3.ZERO
	var reach := _reach_of(task)
	if g != Vector3.INF and _swing_from < 0:
		var to := g - global_position
		to.y = 0.0
		if to.length() > reach:
			want = to.normalized() * RUN_MPS
	var p := _player()
	if p != null:
		var away := global_position - p.global_position
		away.y = 0.0
		var keep := float(p.profile.get("capsule_radius_m", 5.0)) + RADIUS_M + GIANT_CLEARANCE_M
		if away.length() < keep and away.length() > 0.01:
			want += away.normalized() * RUN_MPS
	if want.length() > RUN_MPS:
		want = want.normalized() * RUN_MPS
	velocity.x = want.x
	velocity.z = want.z
	velocity.y = 0.0 if is_on_floor() else velocity.y - GRAVITY * dt
	var face := want
	if _swing_from >= 0 or want.length() < 0.5:
		face = (g - global_position) if g != Vector3.INF else Vector3.ZERO
	face.y = 0.0
	if face.length() > 0.2:
		var target_yaw := atan2(-face.x, -face.z)
		var step := deg_to_rad(TURN_DEG_S) * dt
		rotation.y = rotation.y + clampf(wrapf(target_yaw - rotation.y, -PI, PI), -step, step)
	move_and_slide()


func _reach_of(kind: String) -> float:
	match kind:
		"cut", "winch":
			return REACH_M + 4.0
		"heir":
			return 3.0
	return REACH_M


## Starts a swing when he is in reach of his task's target; at the swing's active phase the blow lands.
func _swing_step(tick: int) -> void:
	if _swing_action == null:
		return
	if _swing_from >= 0:
		var t := tick - _swing_from
		var hit_at := _swing_action.windup_ticks
		var end := hit_at + _swing_action.active_ticks + _swing_action.recovery_ticks
		if t == hit_at:
			_land(_swing_kind, _swing_target)
		if t >= end:
			_swing_from = -1
		return
	if task == "won" or task == "idle" or tick < _next_strike:
		return
	var g := goal()
	if g == Vector3.INF:
		return
	if _flat(global_position, g) > _reach_of(task) + 0.5:
		return
	_swing_from = tick
	_swing_kind = task
	_swing_target = _target_id
	_next_strike = tick + ActionDef.seconds_to_ticks(STRIKE_S)


func _land(kind: String, target_id: String) -> void:
	match kind:
		"cut":
			var p := _player()
			if p != null and p.fetter != null and (p.fetter as PlayerFetter).release(target_id, "cut"):
				chains_cut += 1
			_hit(target_id, WINCH_POWER, 60.0)
			winch_blows += 1
		"winch":
			var w := Sim.get_entity(target_id)
			var crew_hit := false
			if w != null and is_instance_valid(w.actor) and w.actor is FetterWinch:
				for c: Variant in (w.actor as FetterWinch).crew():
					if is_instance_valid(c) and _flat(global_position, (c as Node3D).global_position) <= REACH_M + 6.0:
						_hit(str((c as EnemyActor).entity.entity_id), CREW_POWER, 200.0)
						crew_blows += 1
						crew_hit = true
						break
			if not crew_hit:
				_hit(target_id, WINCH_POWER, 60.0)
				winch_blows += 1
		"heir":
			_hit(target_id, HEIR_POWER, HEIR_POISE, "legs")
			heir_blows += 1


func _hit(target_id: String, power: float, poise: float, region := "") -> void:
	var t := Sim.get_entity(target_id)
	if t == null or not t.is_alive():
		return
	var h := HitEvent.new()
	h.tick = Sim.tick
	h.instance_id = Sim.new_instance_id()
	h.attacker_id = "harrok_ally"
	h.target_id = t.entity_id
	h.action_id = "ally.harrok_axe"
	h.power = power
	h.attacker_stat = 10.0
	h.attacker_height_m = HEIGHT_M
	h.size_policy = "none"
	h.damage_split = {"physical": 1.0}
	h.poise_damage = poise
	h.category = "melee"
	h.tags = PackedStringArray(["Melee"])
	h.attacker_position = global_position
	h.region = region
	if is_instance_valid(t.actor):
		h.hit_point = (t.actor as Node3D).global_position + Vector3.UP * 2.0
		h.distance = _flat(global_position, (t.actor as Node3D).global_position)
	Sim.queue_hit(h)


static func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


## The rig's state (SkinnedRig: his swing's action and phase, his speed).
func get_rig_state() -> Dictionary:
	var a: ActionDef = null
	var phase := 0
	var frac := 0.0
	if _swing_from >= 0 and _swing_action != null:
		a = _swing_action
		var t := float(Sim.tick - _swing_from) / Sim.TICK_RATE
		var w: float = _swing_action.windup_ticks / float(Sim.TICK_RATE)
		var ac: float = _swing_action.active_ticks / float(Sim.TICK_RATE)
		if t < w:
			phase = ActionDef.Phase.WINDUP
			frac = t / maxf(w, 0.01)
		elif t < w + ac:
			phase = ActionDef.Phase.ACTIVE
			frac = (t - w) / maxf(ac, 0.01)
		else:
			phase = ActionDef.Phase.RECOVERY
			frac = clampf((t - w - ac) / maxf(_swing_action.recovery_ticks / float(Sim.TICK_RATE), 0.01), 0.0, 1.0)
	return {"state": CombatController.State.ATTACKING if a != null else CombatController.State.LOCOMOTION,
		"action": a, "phase": phase, "phase_fraction": frac, "speed": Vector2(velocity.x, velocity.z).length(),
		"dead": false, "staggered": false, "dodging": false, "guarding": false}


func get_debug_info() -> Dictionary:
	return {"id": "harrok_ally", "task": task, "cut": chains_cut, "winch_blows": winch_blows, "crew_blows": crew_blows,
		"heir_blows": heir_blows}
