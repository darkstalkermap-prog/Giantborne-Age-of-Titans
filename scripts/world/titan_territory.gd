class_name TitanTerritory
extends BossArena
## A3: a titan's ground in the open world - Stoneback's quarry beside Millford (the layout's arena element of style
## "titan", tools/world/kinds/arena.gd; his encounter encounter.crownmarch_stoneback). A BossArena without a gate
## whose fight is the titan's hunt across open ground instead of a ring:
##
## * **Engagement**: a living giant who comes within territory_m of the territory's centre (horizontally), inside
##   its region (region_id: the Crownmarch), with nothing but air between his eye over his home and the giant (B1:
##   line_of_sight - the hill round his pit hides a giant on its far side), engages him - he has seen it from his
##   quarry: boss_engaged (the boss
##   bar, his music, the lock-on to his plates as every boss's), the POI discover_poi is discovered ("sighted"),
##   and he walks out after it. The engage trigger (the pit's floor) engages too.
## * **The hunt**: while engaged he is told where the giant is every HUNT_EVERY_S (EnemyBrain.on_noise, certain), so
##   he pursues it well past his sight and memory - and past any leash: his encounter has none (an arena
##   encounter), the territory is his leash.
## * **Escape**: the disengage rule measures from the territory's centre: a giant beyond inner_radius_m (his pursuit
##   radius) + disengage_margin_m for disengage_s ends the hunt - boss_disengaged(left), the zone's music again, and
##   his new attempt (EnemyActor.p34_reset_attempt): full health, every plate whole (TitanEnemy), and he walks home.
##   Millford lies beyond that line (the hamlet is the giant's refuge: he never comes in among its houses).
##   A giant that dies reloads its checkpoint: he is back at home, whole.
## * **Streaming**: the territory's props live in the chunk of its centre; its pursuit radius lies within the
##   chunk streamer's keep distance (unload_at 3 chunks), so it stays loaded while he hunts. If his own chunk unloads
##   anyway (fast travel), the director despawns him (EncounterDirector: never a recorded death) and the territory
##   waits again: the next activation brings him back at home, whole.
## * **B3: a sleeping titan** (the Rootwarden): with wake_on_sight off, a giant he sees only discovers his POI (his
##   grove) - it does not engage him; a blow wakes him (TitanEnemy: his territory engages), and once wake_flag holds
##   (the woodfolk's call) the engage trigger engages too. Before it, entering his hollow does nothing: safe to look
##   at, deadly to wake.
## * **Death**: BossArena's - the defeated flag, boss_defeated (GameSession's checkpoint after the kill), and his
##   record's outcome flag (boss.stoneback.outcome); his encounter forbids that flag and his death persists, so he
##   never comes back. Once the giant has gone beyond his line (or on any later load of his ground) reopened_flag
##   is set: the settlement's change shows behind the giant's back, not at his corpse. Nothing else in the territory is removed at engagement (open ground: the living world goes
##   on around him; his encounter's reserved seat keeps him inside the combatant budget - EncounterDirector A3).

const HUNT_EVERY_S := 1.0
## B1: the sight line's samples (m apart) and how far over the ground it must pass.
const SIGHT_STEP_M := 4.0
const SIGHT_CLEARANCE_M := 0.5

## How near (m, horizontally) a giant must come to the centre for him to see it.
@export var territory_m := 110.0
## The region the giant must stand in ("" = any).
@export var region_id := "region.crownmarch"
## The POI discovered when he first sees the giant.
@export var discover_poi := ""
## B1: his sight is blocked by the ground between (the hill round his pit); his eye is this far over his home's ground.
@export var line_of_sight := true
@export var eye_height_m := 15.0
## Set (first write wins) once he is dead and the giant has gone beyond his line, or on a later load of his ground:
## the quarry reopens behind the giant's back, not at his corpse ("" = none).
@export var reopened_flag := ""

## B3: whether a giant he sees engages him (Stoneback: yes; the Rootwarden asleep in his grove: no - it is only
## discovered), and the flag without which his engage trigger does nothing ("" = none: it always engages).
@export var wake_on_sight := true
@export var wake_flag := ""

## Engagements by sight (tests, debug).
var sighted := 0
## B3: the giants he saw without waking (the POI discovered; tests, debug).
var seen_asleep := 0
var _hunt_tick := -1


func _ready() -> void:
	super()
	if state == State.DEFEATED:
		_reopen()   # a later load of his ground: the world has moved on


func _remove_intruders() -> void:
	pass


## B3: his engage trigger engages only once wake_flag holds (the woodfolk's call); a blow wakes him anyway.
func _on_area_entered(tick: int, area_id: String, entity_id: String) -> void:
	if area_id == engage_area_id and wake_flag != "" and not Waystone.flag_truthy(WorldState.get_flag(wake_flag)):
		return
	super(tick, area_id, entity_id)


## B3: engaging him wakes him (a sleeping titan: TitanEnemy.wake) - the boss_engaged handler does it too; and his
## first engagement is announced as every boss's.
func _alert_boss(tick: int) -> void:
	var b := boss()
	if b != null and b.has_method("wake"):
		b.call("wake", "engaged")
	super(tick)


func _reopen() -> void:
	if reopened_flag != "" and not Waystone.flag_truthy(WorldState.get_flag(reopened_flag)):
		WorldState.try_set_flag(reopened_flag, true)


func _on_post_resolve(tick: int) -> void:
	if state == State.WAITING:
		var p := _player()
		if p != null and p.entity != null and p.entity.is_alive() and sees(p.global_position) \
				and boss_entity() != null and boss_entity().is_alive():
			if not wake_on_sight:
				# B3: asleep - seen, the grove is discovered; nothing else (a blow or the call wakes him)
				if seen_asleep == 0 or tick % 60 == 0:
					seen_asleep += 1
					_discover(tick)
				return
			sighted += 1
			_discover(tick)
			engage(tick)
			_hunt_tick = tick
		return
	if state == State.DEFEATED:
		var pd := _player()
		if pd != null and outside_m(pd.global_position) > disengage_margin_m:
			_reopen()
		return
	if state == State.ENGAGED:
		var b := boss()
		if b == null or b.entity == null or not b.entity.is_alive():
			if b == null and not WorldState.is_killed(boss_id):
				state = State.WAITING   # despawned (his chunk unloaded): he returns at home, whole
			return
		var p := _player()
		if p != null and p.entity != null and p.entity.is_alive() and b.brain != null \
				and tick - _hunt_tick >= ActionDef.seconds_to_ticks(HUNT_EVERY_S) \
				and outside_m(p.global_position) <= disengage_margin_m:
			_hunt_tick = tick
			b.brain.on_noise(tick, p.global_position, p.entity.entity_id, true)
	super._on_post_resolve(tick)


## Whether a giant standing at `point` is in his sight: within territory_m of the centre, in the region, and (B1) not
## hidden from his quarry by the ground between (sight_clear: the line from his eye over his home to the giant's
## chest; the hill round his pit hid a giant on its far shoulder no more than the open side did).
func sees(point: Vector3) -> bool:
	var flat := Vector2(point.x - global_position.x, point.z - global_position.z)
	if flat.length() > territory_m:
		return false
	if region_id != "" and region_at(point) != region_id:
		return false
	if not line_of_sight:
		return true
	var level := get_tree().get_first_node_in_group("level_root") as LevelRoot if is_inside_tree() else null
	if level == null or not level.has_method("height_at"):
		return true
	var height := func(p: Vector3) -> float: return float(level.call("height_at", p))
	var ground := float(height.call(global_position))
	var eye := Vector3(global_position.x, (ground if not is_nan(ground) else global_position.y) + eye_height_m,
		global_position.z)
	var chest := point + Vector3.UP * target_height_m()
	return sight_clear(eye, chest, height, SIGHT_STEP_M, SIGHT_CLEARANCE_M)


## The height above its feet at which a giant is seen (the player's growth profile's, half way up its body).
func target_height_m() -> float:
	var p := _player()
	return float(p.profile.get("height_m", 8.0)) * 0.55 if p != null and p.profile != null else 4.0


## B1: true when the straight line from `eye` to `target` stays above the ground (`height_at(point) -> float`, NaN
## where nothing is loaded: no obstacle) at every SIGHT_STEP_M along it, by `clearance` - pure, for the tests.
static func sight_clear(eye: Vector3, target: Vector3, height_at: Callable, step_m := 4.0, clearance := 0.5) -> bool:
	var flat := Vector2(target.x - eye.x, target.z - eye.z).length()
	var n := maxi(1, int(ceil(flat / maxf(step_m, 0.5))))
	for i in range(1, n):
		var t := float(i) / float(n)
		var p := eye.lerp(target, t)
		var g := float(height_at.call(p))
		if not is_nan(g) and g > p.y - clearance:
			return false
	return true


## The region at `point` (the world's; "" in a level without regions).
func region_at(point: Vector3) -> String:
	var level := get_tree().get_first_node_in_group("level_root") as LevelRoot if is_inside_tree() else null
	if level != null and level.has_method("region_at"):
		return str(level.call("region_at", point))
	return ""


func _discover(tick: int) -> void:
	if discover_poi == "":
		return
	var level := get_tree().get_first_node_in_group("level_root") as LevelRoot
	var d: Discovery = level.discovery() if level != null else null
	if d != null:
		d.discover(discover_poi, tick, "sighted")


func debug_lines() -> PackedStringArray:
	var out := super.debug_lines()
	out.append("territory %.0f m, pursuit %.0f m, sighted %d" % [territory_m, inner_radius_m + disengage_margin_m, sighted])
	return out
