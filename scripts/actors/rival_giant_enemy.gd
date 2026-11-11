class_name RivalGiantEnemy
extends OgreBoss
## Rival giants (plan M6-M9 §2.10, §5.13 boss 3; P34): enemy.rival_giant (10 m) and Harrok the
## Unbowed (enemy.harrok, 15 m). The Ogre King's machinery (OgreBoss: group "bosses", the boss
## framework's phases and sequences, the chained combo, never grabbable) with a giant's arms: the axe
## combos are weapon arcs of a 4.5 m axe through AttackRunner (pitch_mid_deg sweeps them through the
## giant's height), the overhead chop a line pulse, the boulder throw a lob whose landing circle is
## committed at its windup (EnemyActor's P34 `indirect`), and the shoulder charge OgreBoss's committed
## run (its body sweep; it turns only in its windup, its body ignores other actors) that ends against
## stone in giant_charge_recover - 2.5 s to punish - or on its cap.
##
## Harrok (a HarrokBrain): his second phase begins at 50 % or after two poise breaks
## (enter_on_poise_breaks, EnemyActor P34), with the roar and the Moot's falling stones - arena hazards
## of his brain, announced here as circle telegraphs (keys "<id>#stone<n>", the giant their target, so
## the threat cues play at the stones) and struck through his runner (AttackRunner.p34_hazard_pulse:
## the hits are his). He yields by the yield protocol (EnemyActor P34): Spare, or Strike and he rises
## to fight to the death. While yielded he kneels (the rig's arms down).

const RECOVER_ID := "ability.giant_charge_recover"
const KNEEL_POSE := {"arm": Vector2(20.0, -88.0), "off": Vector2(-20.0, -88.0), "exact": false}

## Hazard pulses struck (tests, debug).
var hazard_pulses := 0


func _make_brain() -> EnemyBrain:
	var seed_value := Sim.DEFAULT_SEED ^ hash(entity.entity_id)
	if typeof(record.get("yield_at")) == TYPE_DICTIONARY or _has_hazard_phase():
		return HarrokBrain.new(entity.entity_id, record, seed_value)
	return RivalGiantBrain.new(entity.entity_id, record, seed_value)


func _has_hazard_phase() -> bool:
	var boss: Variant = record.get("boss")
	if typeof(boss) != TYPE_DICTIONARY:
		return false
	for ph: Variant in boss.get("phases", []):
		if typeof(ph) == TYPE_DICTIONARY and str(ph.get("hazard", "")) != "":
			return true
	return false


func sim_step(tick: int, dt: float) -> void:
	p34_boss_step(tick)
	super(tick, dt)
	_hazard_step(tick)


## The charge's recovery reels like a stagger; a yielded giant kneels.
func get_rig_state() -> Dictionary:
	var s := super()
	var a := controller.action
	if a != null and a.id == RECOVER_ID:
		s["staggered"] = true
	if yielded or stood_down:
		s["pose_override"] = KNEEL_POSE
	return s


# --------------------------------------------------------------------------- arena hazards

## Announces the brain's new hazards and strikes the due ones (Harrok's falling stones).
func _hazard_step(tick: int) -> void:
	var hb := brain as HarrokBrain
	if hb == null or not entity.is_alive():
		return
	if yielded or stood_down or not ai_enabled:
		hb.p34_clear_hazards()
		return
	var t := Sim.get_entity(hb.target_id) if hb.target_id != "" else null
	var target_pos := t.actor.global_position if t != null and is_instance_valid(t.actor) and t.is_alive() \
		else Vector3.INF
	var r := hb.hazard_step(tick, target_pos)
	var a := GameData.get_action(hb.phase_hazard()) if hb.phase_hazard() != "" else null
	if a == null:
		a = GameData.get_action(str(r.get("action", "")))
	if a == null:
		return
	var spec: Dictionary = a.param("arena_hazard", {})
	for h: Dictionary in r.new:
		Events.telegraph_started.emit(tick, hazard_key(int(h.id)), a.id, hb.target_id, "circle", h.point, 0.0,
			float(spec.get("radius_m", a.radius_m)), 0.0, float(spec.get("telegraph_s", 1.5)))
	for h: Dictionary in r.due:
		runner.p34_hazard_pulse(a, h.point, tick)
		hazard_pulses += 1


## The telegraph key of hazard `id` (not an entity id: the cue and the circle sit at the stone).
func hazard_key(id: int) -> String:
	return "%s#stone%d" % [entity.entity_id, id]


func _p34_reset_extra() -> void:
	var hb := brain as HarrokBrain
	if hb != null:
		hb.p34_clear_hazards()


func get_debug_info() -> Dictionary:
	var d := super()
	d["breaks"] = poise_breaks
	if yielded:
		d["yield"] = "%s %s" % [yield_reason, yield_decided if yield_decided != "" else "(prompt)"]
	if brain is HarrokBrain:
		d["stones"] = "%d up, %d struck" % [(brain as HarrokBrain).hazards.size(), hazard_pulses]
	return d
