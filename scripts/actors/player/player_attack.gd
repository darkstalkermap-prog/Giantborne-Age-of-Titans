class_name PlayerAttack
extends PlayerComponent
## The giant's weapon geometry and hit queries. Hits are produced by a shared AttackRunner
## (one handler per hit shape) and built by HitFactory, exactly like every enemy's.
##
## Geometry (player.weapon_pivot, attack_origin, arm_length, weapon_length, weapon_radius) is
## a cache read from the growth profile and the weapon record; it is refreshed when either
## changes, never mid-swing.

var runner: AttackRunner


func setup(p: GiantPlayer) -> void:
	super(p)
	runner = AttackRunner.new(player, player.entity, player.controller)
	runner.emit_clank = true
	refresh_geometry()


## Reads the weapon geometry cache from the profile and the weapon. The weapon's length and
## radius follow player.current_weapon_scale() (1.0 until growth profiles carry weapon_scale).
func refresh_geometry() -> void:
	var profile := player.profile
	var w := player.weapon
	var p: Array = profile.get("weapon_pivot_m", [0.82, 2.9, 0.0])
	player.weapon_pivot = Vector3(p[0], p[1], p[2])
	var o: Array = profile.get("attack_origin_m", [0.0, 2.6, 0.0])
	player.attack_origin = Vector3(o[0], o[1], o[2])
	player.arm_length = float(profile.get("arm_length_m", 1.5))
	var weapon_scale := player.current_weapon_scale()
	player.weapon_length = float(w.get("length_m", 1.85)) * weapon_scale
	player.weapon_radius = float(w.get("hit_radius_m", 0.45)) * weapon_scale


func on_profile_changed(_old_profile: Dictionary, _new_profile: Dictionary) -> void:
	refresh_geometry()
	runner.reset()


func on_weapon_changed(_weapon: Dictionary) -> void:
	refresh_geometry()
	runner.reset()


func on_action_started(action: ActionDef, _instance_id: int) -> void:
	if action.kind in ["light", "heavy", "ability", "ultimate"]:
		runner.prev_segment = PackedVector3Array()
		player.stats.attacks += 1


## Weapon segment (shoulder-side end, tip) in world space at fraction f of the action's arc.
## The rig poses the arm with the same AttackGeometry, so the visible swing is the tested one.
func weapon_segment_global(action: ActionDef, f: float) -> PackedVector3Array:
	var ang := AttackGeometry.arc_point(action, f)
	var dir := AttackGeometry.local_direction(ang.x, ang.y)
	var seg := AttackGeometry.segment_local(player.weapon_pivot, dir, player.arm_length,
		player.arm_length + player.weapon_length)
	return PackedVector3Array([player.to_global(seg[0]), player.to_global(seg[1])])


func run_hit_queries(tick: int) -> void:
	runner.run(tick)
