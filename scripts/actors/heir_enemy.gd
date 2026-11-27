class_name HeirEnemy
extends TitanEnemy
## E1: Orrik the Fetterer, Harrok's sister-son and the Skarn's war-leader, grown at the Stones to a colossus's size
## (enemy.orrik, 31.5 m), who comes for the Stone Throne. A signature titan (TitanEnemy: his plates, phases, the circling
## and the hug answers, a phase's arena hazards - the warband's fire-pots) on the player's own giant body (SkinnedRig,
## giant_model.tscn at k = 31.5 / 3.6576, his record's appearance): a giant like the player, not a monster - his look is
## his armour, his war-paint and his trophies, and his breakable plates are the armour he wears. What the heir adds is
## the fetters (decision E1-2; PlayerFetter):
##
## * **His chain-hook** (the record's heir.hook: a thrown hook whose hit binds a chain anchored to him, the action's
##   `fetter` "hook") and **the haul** that follows it (heir.haul: the action's `haul` shortens the chain over its active
##   phase - it drags the giant toward him). A giant who tears the hook's chain (a pull or a heave) yanks him off his feet:
##   a stagger of heir.yank_stagger_s (chain_torn). Breaking the **chain-coil** on his left forearm (heir.coil_plate)
##   ends the hook for the attempt: it falls from him and any giant on it is free (HeirBrain.hook_lost).
## * **The Throne-breaker** (heir.breaker): his great overhead blow for a giant held by its pinned_only chains or more
##   (HeirBrain: the next entry while the giant stays bound) - its warning (a circle at the giant's feet as the windup
##   begins and the long windup) is the giant's time to tear free.
## * **His armour comes off as it breaks**: a broken plate's garments leave his look (heir.plate_slots: the helm, the
##   spaulders - both broken -, the vambraces of the coil, the greaves): the giant sees what he has broken.
## The fetter-winches round the arena are their own actors (FetterWinch), joined to his fight by his boss id.

## The stagger reason of a giant tearing his hook (the rig's flinch).
const YANK_REASON := "yanked"

var heir: Dictionary = {}
## Hooks that bit, hauls run, hooks torn from him, Throne-breakers swung (tests, the duel report).
var hooks_bit := 0
var hauls := 0
var yanks := 0
var breakers := 0
var _haul_left_m := 0.0
var _haul_per_tick := 0.0
var _look_broken: Dictionary = {}


func _ready() -> void:
	super()
	heir = record.get("heir", {}) if typeof(record.get("heir")) == TYPE_DICTIONARY else {}
	if not Events.fetter_bound.is_connected(_on_fetter_bound):
		Events.fetter_bound.connect(_on_fetter_bound)
	if not Events.plate_broken.is_connected(_on_heir_plate_broken):
		Events.plate_broken.connect(_on_heir_plate_broken)
	controller.phase_entered.connect(_on_heir_phase)


## (presentation) His axe drawn at a colossus's proportions: the weapon visuals build a giant's axe head at a man's
## size whatever the haft's length (a 0.6 m blade on a 13 m haft read as a pole); the rig's visual is rebuilt from the
## record with its length over AXE_HEAD_SCALE and scaled up by it - the same length, a head AXE_HEAD_SCALE times larger.
const AXE_HEAD_SCALE := 5.0
var _axe_regripped := false


func _process(_delta: float) -> void:
	if _axe_regripped:
		return
	var rig := get_node_or_null("Visual")
	if rig == null or not ("weapon_visual" in rig) or rig.get("weapon_visual") == null:
		return
	_axe_regripped = true
	var w: Dictionary = (weapon as Dictionary).duplicate() if typeof(weapon) == TYPE_DICTIONARY else {}
	if w.is_empty():
		return
	w["length_m"] = float(w.get("length_m", 9.0)) / AXE_HEAD_SCALE
	var node := WeaponVisuals.build(w)
	node.scale = Vector3.ONE * AXE_HEAD_SCALE / maxf(float(rig.get("body_scale")), 0.01)
	rig.call("set_weapon_visual", node)


func _exit_tree() -> void:
	super()
	if Events.fetter_bound.is_connected(_on_fetter_bound):
		Events.fetter_bound.disconnect(_on_fetter_bound)
	if Events.plate_broken.is_connected(_on_heir_plate_broken):
		Events.plate_broken.disconnect(_on_heir_plate_broken)


func _make_brain() -> EnemyBrain:
	return HeirBrain.new(entity.entity_id, record, Sim.DEFAULT_SEED ^ hash(entity.entity_id))


func heir_brain() -> HeirBrain:
	return brain as HeirBrain


func sim_step(tick: int, dt: float) -> void:
	_read_target()
	_haul_step()
	super(tick, dt)


## The target's chains, as the brain reads them (how many hold it; whether it is on his own hook).
func _read_target() -> void:
	var hb := heir_brain()
	if hb == null:
		return
	var f := _target_fetter()
	hb.fettered = f.count() if f != null else 0
	hb.target_hooked = f != null and f.holds(entity.entity_id)


func _target_fetter() -> PlayerFetter:
	var hb := heir_brain()
	var t := Sim.get_entity(hb.target_id) if hb != null and hb.target_id != "" else null
	if t == null or not is_instance_valid(t.actor):
		for e: CombatEntity in Sim.entities():   # (no target yet: the giant)
			if e.team == CombatEntity.Team.PLAYER and is_instance_valid(e.actor) and e.actor.get("fetter") != null:
				t = e
				break
	if t == null or not is_instance_valid(t.actor):
		return null
	var f: Variant = t.actor.get("fetter")
	return f as PlayerFetter if f != null else null


## Where his hook's chain leaves him: his left fist (the rig's palm when it is drawn; else the hand's place by his side).
func chain_point() -> Vector3:
	var v := get_node_or_null("Visual")
	if v != null and v.has_method("palm_global") and v.is_inside_tree() and DisplayServer.get_name() != "headless":
		var p: Vector3 = v.call("palm_global", true)
		if p.is_finite() and p != Vector3.ZERO:
			return p
	var h := float(record.get("height_m", 30.0))
	return global_position + global_transform.basis * Vector3(-0.2 * h, 0.5 * h, -0.08 * h)


## PlayerFetter: the giant tore his hook's chain - it yanks him off balance.
func chain_torn(_by: Node3D) -> void:
	if not entity.is_alive() or yielded:
		return
	yanks += 1
	_haul_left_m = 0.0
	if controller.action != null:
		controller.call("_finish_action", true)
	controller.buffer.clear()
	entity.stagger(float(heir.get("yank_stagger_s", 3.0)), YANK_REASON)


func _on_fetter_bound(_tick: int, _entity_id: String, anchor_id: String, _kind: String, _count: int) -> void:
	if entity == null or anchor_id != entity.entity_id:
		return
	hooks_bit += 1
	var hb := heir_brain()
	if hb != null:
		hb.hook_bit = true
		hb.target_hooked = true


func _on_heir_phase(a: ActionDef, _instance_id: int, phase: int) -> void:
	if a == null:
		return
	if a.id == str(heir.get("breaker", "")) and phase == ActionDef.Phase.WINDUP:
		breakers += 1
	if phase == ActionDef.Phase.ACTIVE:
		var spec: Variant = a.param("haul")
		if typeof(spec) == TYPE_DICTIONARY:
			hauls += 1
			_haul_left_m = float((spec as Dictionary).get("metres", 0.0))
			_haul_per_tick = _haul_left_m / float(maxi(1, a.active_ticks))
	elif phase == ActionDef.Phase.RECOVERY:
		_haul_left_m = 0.0


## While a haul's active phase runs, his hook's chain shortens: the giant on it is dragged in.
func _haul_step() -> void:
	if _haul_left_m <= 0.0:
		return
	var f := _target_fetter()
	var a := controller.action
	if f == null or a == null or typeof(a.param("haul")) != TYPE_DICTIONARY:
		_haul_left_m = 0.0
		return
	var step := minf(_haul_per_tick, _haul_left_m)
	_haul_left_m -= step
	f.haul(entity.entity_id, step, float((a.param("haul") as Dictionary).get("min_m", 8.0)))


## His plates: the coil's break ends his hook (and frees a giant on it); every break takes its armour off his look.
func _on_heir_plate_broken(_tick: int, id: String, plate_id: String) -> void:
	if entity == null or id != entity.entity_id:
		return
	if plate_id == str(heir.get("coil_plate", "")):
		var hb := heir_brain()
		if hb != null:
			hb.hook_lost = true
		var f := _target_fetter()
		if f != null:
			f.release(entity.entity_id, "anchor")
	_look_broken[plate_id] = true
	_redress()


## His look less the garments of the plates broken (heir.plate_slots: plate -> [outfit slots]; a slot shared by two
## plates comes off once both are broken).
func dressed_record() -> Dictionary:
	var rec := Appearance.preset_record(str(record.get("appearance", "")))
	if rec.is_empty():
		return {}
	var out: Dictionary = rec.duplicate(true)
	var slots: Dictionary = heir.get("plate_slots", {})
	var by_slot := {}
	for plate: String in slots:
		for s: Variant in slots[plate]:
			if not by_slot.has(str(s)):
				by_slot[str(s)] = []
			(by_slot[str(s)] as Array).append(plate)
	for s: String in by_slot:
		var all := true
		for plate: Variant in by_slot[s]:
			all = all and _look_broken.has(str(plate))
		if all and typeof(out.get("outfit")) == TYPE_DICTIONARY and (out.outfit as Dictionary).has("slots"):
			out.outfit.slots[s] = {"item": "", "dye": ""}
	return out


## The garments still on him (tests): the dressed record's outfit items.
func worn_garments() -> Array:
	var out: Array = []
	var rec := dressed_record()
	if typeof(rec.get("outfit")) != TYPE_DICTIONARY:
		return out
	for s: String in (rec.outfit as Dictionary).get("slots", {}):
		var item := str(rec.outfit.slots[s].get("item", ""))
		if item != "":
			out.append(item)
	return out


func _redress() -> void:
	var v := get_node_or_null("Visual")
	if v == null or not v.has_method("apply_look"):
		return
	var rec := dressed_record()
	if not rec.is_empty() and bool(v.call("layers_on")):
		v.call("apply_look", Appearance.to_look(rec))


func _p34_reset_extra() -> void:
	super()
	hooks_bit = 0
	hauls = 0
	yanks = 0
	breakers = 0
	_haul_left_m = 0.0
	var hb := heir_brain()
	if hb != null:
		hb.hook_lost = false
		hb.hook_bit = false
	if not _look_broken.is_empty():
		_look_broken.clear()
		_redress()


func get_rig_state() -> Dictionary:
	var s := super()
	if controller.state == CombatController.State.STAGGERED and controller.stagger_reason == YANK_REASON:
		s["yanked"] = true
	return s


func get_debug_info() -> Dictionary:
	var d := super()
	var hb := heir_brain()
	d["heir"] = "hooks %d, hauls %d, yanks %d, breakers %d%s" % [hooks_bit, hauls, yanks, breakers,
		" (hook lost)" if hb != null and hb.hook_lost else ""]
	return d
