class_name PlayerHaul
extends PlayerComponent
## C4 (decision C4-2): the giant carries a settlement's load - a great timber, a king-stone, a quarry block - in both
## arms from where it lies (a HaulSource: E "Take up a king-stone") to the site that wants it (a SettlementSite:
## E "Set the king-stone down for the stone ring"), the `haul` component of GiantPlayer.COMPONENTS.
##
## While he carries one:
##   * he walks at CARRY_SPEED_MULT of his speed (the motor's "haul" multiplier), holding it across his arms (the
##     grab's two-handed hold pose; the load's mesh from scenes/world/haul_loads.tscn, sized by his height);
##   * his blows, dodges, jumps and abilities are refused ("Set the load down first (E)"): a stone that size is held
##     with both arms;
##   * E sets it down: at a site that wants it, it is delivered (SettlementWork.deliver: the site's stack grows);
##     anywhere else it is put back where it was taken (its pile: no load is lost and none litters the world);
##   * a stagger, a grab, a death, a travel or the level unloading put it back too.
## A load is never saved: a checkpoint keeps the deliveries, not the carrying.

const CARRY_SPEED_MULT := 0.7
const LOADS_SCENE := "res://scenes/world/haul_loads.tscn"
## Where the load rides, in the stage-1 giant's own space (x his body scale): before the chest, between his hands.
const SOCKET := Vector3(0.0, 2.15, -1.05)
const BLOCKED_EDGES := [&"light", &"heavy", &"dodge", &"jump", &"block_press", &"ultimate"]
const BLOCKED_TEXT := "You are carrying the %s: set it down first (E)."

var load_id := ""
## The source it came from (its world id) and the settlement record that wants loads of this kind.
var source_id := ""
var load_name := ""
var _visual: Node3D = null
static var _loads_scene: PackedScene = null


func edge_priority() -> int:
	return 9


func is_carrying() -> bool:
	return load_id != ""


## Takes up a load of kind `kind` from source `source` (HaulSource.interact). False when he already carries one.
func take_up(kind: String, source: String, display_name: String) -> bool:
	if is_carrying() or kind == "":
		return false
	load_id = kind
	source_id = source
	load_name = display_name
	player.motor.set_speed_mult(&"haul", CARRY_SPEED_MULT)
	_show_visual()
	Events.haul_changed.emit(Sim.tick, load_id, true)
	return true


## Puts the load down where it came from (no delivery). Returns true when he carried one.
func put_back(reason := "dropped") -> bool:
	if not is_carrying():
		return false
	var was := load_id
	load_id = ""
	source_id = ""
	player.motor.set_speed_mult(&"haul", 1.0)
	_hide_visual()
	Events.haul_changed.emit(Sim.tick, was, false)
	if reason == "dropped":
		Events.hud_message.emit("You set the %s down. It waits where you found it." % load_name, "info")
	return true


## The load delivered at `site` (SettlementSite.accepts said so): {"ok", "message"}.
func deliver_to(site: SettlementSite) -> Dictionary:
	if not is_carrying() or site == null:
		return {"ok": false, "message": ""}
	var rec := site.settlement()
	var r := SettlementWork.deliver(rec, site.project_id, load_id)
	if bool(r.ok):
		var was := load_id
		load_id = ""
		source_id = ""
		player.motor.set_speed_mult(&"haul", 1.0)
		_hide_visual()
		Events.haul_changed.emit(Sim.tick, was, false)
		site.on_delivered()
	return r


## The best site around him that wants his load (null when none).
func site_near() -> SettlementSite:
	if not is_carrying() or not player.is_inside_tree():
		return null
	var best: SettlementSite = null
	var best_d := INF
	var capsule_r := float(player.profile.get("capsule_radius_m", 0.85))
	for n in player.get_tree().get_nodes_in_group(SettlementSite.GROUP):
		var s := n as SettlementSite
		if s == null or not s.is_inside_tree() or not s.accepts(load_id):
			continue
		var to := s.global_position - player.global_position
		to.y = 0.0
		var d := to.length()
		if d <= s.radius_m + capsule_r and d < best_d:
			best = s
			best_d = d
	return best


func interact_candidate() -> Dictionary:
	if not is_carrying():
		return {}
	var site := site_near()
	if site != null:
		return {"priority": 8, "prompt": "Set the %s down for %s" % [load_name, site.project_name().to_lower()],
			"distance": 0.0, "call": func() -> void: deliver_to(site), "id": site.interact_id}
	return {"priority": 8, "prompt": "Put the %s down" % load_name, "distance": 0.0,
		"call": func() -> void: put_back("dropped"), "id": ""}


func handle_edge(edge: StringName) -> bool:
	if not is_carrying():
		return false
	if edge in BLOCKED_EDGES or String(edge).begins_with("slot_"):
		Events.hud_message.emit(BLOCKED_TEXT % load_name, "warn")
		return true
	return false


func post_movement(_tick: int, _dt: float) -> void:
	if not is_carrying():
		return
	var c := player.controller
	if c != null and (c.state == CombatController.State.DEAD or c.state == CombatController.State.GRABBED \
			or c.state == CombatController.State.STAGGERED):
		put_back("interrupted")
		return
	_place_visual()


func on_exit() -> void:
	put_back("unloaded")


func on_profile_changed(_old_profile: Dictionary, _new_profile: Dictionary) -> void:
	if is_carrying():
		_place_visual()


func rig_state(out: Dictionary) -> void:
	if not is_carrying() or player.rig == null:
		return
	out["holding"] = "two_hand"
	out["grab_phase"] = "hold"
	out["hauling"] = load_id
	out["pose_override"] = ActorRig.grab_pose("hold", true, socket_local(), player.weapon_pivot,
		player.rig.idle_arm_pose, player.rig.off_idle_pose, ActionDef.Phase.ACTIVE, 0.0, float(Sim.tick) * Sim.DT)


func debug_info(out: Dictionary) -> void:
	if is_carrying():
		out["haul"] = "carrying %s from %s" % [load_id, source_id]


func body_scale() -> float:
	return float(player.profile.get("height_m", CombatRules.REFERENCE_HEIGHT_M)) / CombatRules.REFERENCE_HEIGHT_M


func socket_local() -> Vector3:
	return SOCKET * body_scale()


# --------------------------------------------------------------------------- the load's look

func _show_visual() -> void:
	_hide_visual()
	_visual = make_load_visual(load_id)
	_visual.name = "HaulLoad"
	player.add_child(_visual)
	_place_visual()


func _hide_visual() -> void:
	if _visual != null and is_instance_valid(_visual):
		_visual.queue_free()
	_visual = null


func _place_visual() -> void:
	if _visual == null or not is_instance_valid(_visual):
		return
	_visual.position = socket_local()
	_visual.rotation = Vector3.ZERO
	var k := body_scale()
	_visual.scale = Vector3(k, k, k)


## The mesh of load `id` at a stage-1 giant's size (scenes/world/haul_loads.tscn's child of that name; a plain block
## where the scene or the child does not exist: tests, a load no look was built for).
static func make_load_visual(id: String) -> Node3D:
	if _loads_scene == null and ResourceLoader.exists(LOADS_SCENE):
		_loads_scene = load(LOADS_SCENE) as PackedScene
	if _loads_scene != null:
		var all := _loads_scene.instantiate() as Node3D
		var one := all.get_node_or_null(NodePath(id)) as Node3D
		if one != null:
			all.remove_child(one)
			all.free()
			one.position = Vector3.ZERO
			one.visible = true
			var wrap := Node3D.new()
			wrap.add_child(one)
			return wrap
		all.free()
	var root := Node3D.new()
	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(1.3, 0.55, 0.55)
	mi.mesh = box
	root.add_child(mi)
	return root
