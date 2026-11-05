class_name ArcherEnemy
extends EnemyActor
## Archer (enemy.archer, plan §3.9, §4.4): the shared EnemyActor glue with an ArcherBrain, the
## ranged helpers of EnemyActor's P09 section (ranged tokens, launch slots, firing points on
## elevation and cover markers) and committed aim: during the 0.9 s draw it turns toward the
## giant until 60 % of the windup, then stores the aim point and stops turning; the arrow flies
## there (decision 24). Its rig draws the bow at the aim point. Group "ranged_enemies". No guard;
## its kick is a short sector at leg height. Counterplay: pressure it, or throw something at it.

## Off-hand (string hand) pose while drawing: pulled back to the cheek (yaw, pitch in degrees).
const DRAW_POSE := Vector2(-55.0, 18.0)
const RELEASE_POSE := Vector2(-20.0, 4.0)


func _ready() -> void:
	add_to_group(RANGED_GROUP)
	super()


func _exit_tree() -> void:
	release_ranged_claims()
	super()


func _make_brain() -> EnemyBrain:
	var b := ArcherBrain.new(entity.entity_id, record, Sim.DEFAULT_SEED ^ hash(entity.entity_id))
	install_ranged_helpers(b)
	return b


func _update_facing(dt: float) -> void:
	if not update_ranged_aim(dt):
		super(dt)


func on_entity_died(killer_id: String) -> void:
	super(killer_id)
	release_ranged_claims()


## The ActorRig keys, plus the draw: while a shot is drawn the bow arm points at the aim point
## (current_aim_point) and the string hand pulls back to the cheek, letting go on release.
func get_rig_state() -> Dictionary:
	var s := super()
	var a := controller.action
	var phase := controller.phase()
	if a != null and a.hit_shape == "projectile" and (phase == ActionDef.Phase.WINDUP or phase == ActionDef.Phase.ACTIVE):
		var aim := current_aim_point()
		if aim != Vector3.INF:
			var off_idle := rig.off_idle_pose if rig != null else Vector2(-10.0, -80.0)
			var f := controller.phase_fraction()
			var off := off_idle.lerp(DRAW_POSE, smoothstep(0.0, 1.0, f)) if phase == ActionDef.Phase.WINDUP else RELEASE_POSE
			s["pose_override"] = {"arm": ActorRig.aim_pose(weapon_pivot, to_local(aim)), "off": off, "exact": false}
	return s


func get_debug_info() -> Dictionary:
	var d := super()
	d["band"] = brain.ranged_band(brain.is_outmatched())
	d["settled"] = brain.is_settled(global_position)
	d["ranged_token"] = brain.holds_ranged_token
	d["aim_locked"] = aim_locked()
	return d
