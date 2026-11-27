class_name PlayerStorm
extends PlayerComponent
## D2 (decision D2-2): the giant in the Stormcaller's storm - how deep he stands in its water. The `storm` component of
## GiantPlayer.COMPONENTS.
##
## Every tick it reads the storm's water at his feet (StormWater.depth_at): `depth_m`, and `wet`, the share of his body
## under it (depth over his height: the same pool is to a small giant's thigh and a big one's shin). What it does:
##   * wading is slow: his speed is cut by WADE_SLOW a unit of wet share (at most to WADE_MIN): a bigger body wades the
##     same pool faster (the Stormcaller set's 7 pieces: half as much, `wade_slow_mult`);
##   * the Stormcaller's lightning runs through the water to him (TitanEnemy._storm_shock: a bolt that strikes water
##     within its reach shocks every body standing in it, by the square of its wet share - shock_scale), so the deeper
##     he stands the harder it takes him; dry ground (a rim, the shore, a step out of the water) takes none of it.
## `danger` is true while a storm titan is awake near him (the HUD shows the water meter then). Never saved.

const WADE_SLOW := 1.25
const WADE_MIN := 0.55
const WADE_FROM := 0.03
## A body this share under water takes the shock's whole power; the power goes as the square of the share over it (a
## body twice as deep in it takes four times the shock, to SHOCK_MAX), so a bigger giant standing higher out of the
## same pool takes much less of it.
const SHOCK_REF_WET := 0.25
const SHOCK_MIN_WET := 0.015
const SHOCK_MAX := 1.6
const DANGER_M := 170.0

var depth_m := 0.0
var wet := 0.0
var danger := false
## Shocks taken this life and their damage (tests, the duel report); gusts that moved him.
var shocks := 0
var shock_damage := 0
var gusts := 0
var _danger_check := -1
## The tick until which a bolt of his is coming down on water within its shock's reach of him (the HUD's warning).
var warn_until := -1


func edge_priority() -> int:
	return 7


func setup(p: GiantPlayer) -> void:
	super(p)
	if not Events.hit_resolved.is_connected(_on_hit_resolved):
		Events.hit_resolved.connect(_on_hit_resolved)
	if not Events.telegraph_started.is_connected(_on_telegraph):
		Events.telegraph_started.connect(_on_telegraph)


func on_exit() -> void:
	if Events.hit_resolved.is_connected(_on_hit_resolved):
		Events.hit_resolved.disconnect(_on_hit_resolved)
	if Events.telegraph_started.is_connected(_on_telegraph):
		Events.telegraph_started.disconnect(_on_telegraph)


## True while a bolt of his is coming down on the water within its shock's reach of him.
func warned() -> bool:
	return Sim.tick < warn_until


## A storm bolt telegraphed (its action's `storm_bolt`) on water within the shock's reach of him: warned until it
## strikes (the HUD says so; the rig draws the water's ring).
func _on_telegraph(tick: int, _key: String, action_id: String, _target: String, _shape: String, origin: Vector3,
		_yaw: float, _radius: float, _length: float, duration_s: float) -> void:
	if player == null or not player.is_inside_tree():
		return
	var a := GameData.get_action(action_id)
	if a == null or not bool(a.param("storm_bolt", false)):
		return
	var tree := player.get_tree()
	if StormWater.depth_at(tree, origin) < 0.6:
		return
	var reach := 32.0
	for n in tree.get_nodes_in_group("bosses"):
		var t := n as TitanEnemy
		if t != null and not t.storm.is_empty():
			reach = float(t.storm.get("spread_m", reach))
			break
	if Vector2(origin.x - player.global_position.x, origin.z - player.global_position.z).length() > reach:
		return
	warn_until = maxi(warn_until, tick + int(duration_s * Sim.TICK_RATE))


## The multiplier on a shock through the water for a body `wet_share` under it (0 when it stands dry).
static func shock_scale(wet_share: float) -> float:
	if wet_share < SHOCK_MIN_WET:
		return 0.0
	var k := wet_share / SHOCK_REF_WET
	return clampf(k * k, 0.0, SHOCK_MAX)


## The giant's height (his profile's), for his wet share.
func height_m() -> float:
	return float(player.profile.get("height_m", 3.66)) if player.profile != null else 3.66


## The share of the water's slowing that holds him (the Stormcaller set's passive `wade_slow_mult`).
func wade_mult() -> float:
	if player.entity == null or player.entity.combatant == null:
		return 1.0
	return player.entity.combatant.modifier("wade_slow_mult")


func in_water() -> bool:
	return wet >= SHOCK_MIN_WET


func post_movement(_tick: int, _dt: float) -> void:
	if player.entity == null or not player.entity.is_alive():
		depth_m = 0.0
		wet = 0.0
		player.motor.set_speed_mult(&"storm_wade", 1.0)
		return
	var tree := player.get_tree() if player.is_inside_tree() else null
	depth_m = StormWater.depth_at(tree, player.global_position) if tree != null else 0.0
	wet = clampf(depth_m / maxf(height_m(), 0.1), 0.0, 1.0)
	var slow := 1.0 - WADE_SLOW * maxf(0.0, wet - WADE_FROM) * wade_mult()
	player.motor.set_speed_mult(&"storm_wade", clampf(slow, WADE_MIN, 1.0))
	if Sim.tick >= _danger_check:
		_danger_check = Sim.tick + 30
		danger = tree != null and _storm_titan_near(tree)


func _storm_titan_near(tree: SceneTree) -> bool:
	for n in tree.get_nodes_in_group("bosses"):
		var t := n as TitanEnemy
		if t == null or t.storm.is_empty() or t.dormant or t.entity == null or not t.entity.is_alive():
			continue
		if t.global_position.distance_to(player.global_position) <= DANGER_M:
			return true
	return false


## A shock of the storm's that struck him (its action's `storm_shock` tag: TitanEnemy's shock action).
func _on_hit_resolved(_tick: int, r: HitResult) -> void:
	if r == null or r.event == null or player == null or player.entity == null:
		return
	if r.event.target_id != player.entity.entity_id:
		return
	var a := GameData.get_action(r.event.action_id)
	if a == null:
		return
	if bool(a.param("storm_shock", false)):
		shocks += 1
		shock_damage += r.health_damage
	elif float(a.param("gale", 0.0)) > 0.0 and r.knockback_speed > 0.0:
		gusts += 1


func rig_state(out: Dictionary) -> void:
	if wet > 0.0:
		out["storm_wet"] = wet


func debug_info(out: Dictionary) -> void:
	if wet > 0.0 or shocks > 0:
		out["storm"] = "wet %.0f%% (%.1f m)  shocks %d (%d)" % [wet * 100.0, depth_m, shocks, shock_damage]
