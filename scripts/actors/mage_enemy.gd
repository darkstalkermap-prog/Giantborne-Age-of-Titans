class_name MageEnemy
extends EnemyActor
## Mage (enemy.mage, plan §3.9, §4.4): the shared EnemyActor glue with a MageBrain and the ranged
## helpers of EnemyActor's P09 section. Its casts are kind "ability" (CASTING), paid from the
## essence in its record: the slowing bolt (committed aim at 60 % of the 1.0 s windup; during the
## draw it turns toward the giant until the lock, as archers do) and the barrier, a targets_ally
## cast that lands on the ally its brain picked when it enters ACTIVE (apply_ally_cast). Its
## perception lists the allies within tactics.barrier_range_m for that pick. Poise 25: heavies,
## Footfall, throws, Boulder Hurl and Runic Bolt interrupt its casts. Group "ranged_enemies".


func _ready() -> void:
	add_to_group(RANGED_GROUP)
	super()
	controller.phase_entered.connect(_on_mage_phase_entered)


func _exit_tree() -> void:
	release_ranged_claims()
	super()


func _make_brain() -> EnemyBrain:
	var b := MageBrain.new(entity.entity_id, record, Sim.DEFAULT_SEED ^ hash(entity.entity_id))
	install_ranged_helpers(b)
	return b


func _update_facing(dt: float) -> void:
	if not update_ranged_aim(dt):
		super(dt)


func on_entity_died(killer_id: String) -> void:
	super(killer_id)
	release_ranged_claims()


## Perception extra: "allies" - every living ally of this team within tactics.barrier_range_m
## (held ones excluded): [{id, health_frac, distance}], most hurt first (ties by id).
func _sense_extra(snapshot: Dictionary) -> void:
	var reach := float(_tactics().get("barrier_range_m", 12.0))
	var list: Array = []
	for n in get_tree().get_nodes_in_group("enemies"):
		var other := n as EnemyActor
		if other == null or other == self or other.entity == null or other.entity.combatant == null:
			continue
		if other.entity.team != entity.team or not other.entity.is_alive() or other.is_held():
			continue
		var d := other.global_position.distance_to(global_position)
		if d > reach:
			continue
		list.append({"id": other.entity.entity_id, "health_frac": other.entity.combatant.pools.ratio("health"),
			"distance": d})
	list.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a.health_frac) < float(b.health_frac) if not is_equal_approx(float(a.health_frac),
			float(b.health_frac)) else str(a.id) < str(b.id))
	snapshot["allies"] = list


func _on_mage_phase_entered(action: ActionDef, _instance_id: int, phase: int) -> void:
	if phase == ActionDef.Phase.ACTIVE and action != null and is_same(action.param("targets_ally", false), true):
		apply_ally_cast(action)


func get_debug_info() -> Dictionary:
	var d := super()
	d["band"] = brain.ranged_band(brain.is_outmatched())
	d["settled"] = brain.is_settled(global_position)
	d["ranged_token"] = brain.holds_ranged_token
	d["essence"] = entity.combatant.pools.essence
	d["ward_for"] = brain.ally_target_id
	return d
