class_name SettlementSite
extends Interactable
## C4 (decision C4-2): the place where a settlement's project is built - the hall whose roof-tree goes up, the gap the
## stone ring closes, the bed of an anvil. Placed by the world builder's settlement_site kind (and the Valley's
## layout); `world_id` is the project's `site` in its settlement record.
##   * a load the giant carries is set down here when the project wants it (PlayerHaul offers that over this
##     node's own prompt): the stack beside it grows (the project's haul flags: FlagVisibility elements);
##   * E raises the project once every need is met (SettlementWork.raise): the work shows at once, dust and the
##     raising's sound, the camera's kick; before that, E names what is still missing;
##   * it offers nothing while its project is not the one being earned (an earlier tier first) or is raised.
## Group "settlement_sites" (PlayerHaul.site_near).

const GROUP := "settlement_sites"
const DUST_SCALE := 0.5

@export var world_id := ""
@export var settlement_id := ""
@export var project_id := ""

var last_result: Dictionary = {}


func _init() -> void:
	priority = 40
	radius_m = 14.0


func _ready() -> void:
	add_to_group(GROUP)
	if interact_id == "":
		interact_id = world_id
	if project_id == "" and settlement_id != "":
		project_id = str(SettlementRules.project_at(settlement(), world_id).get("id", ""))
	for sig: Signal in [Events.settlement_raised, Events.settlement_tier, Events.checkpoint_loaded]:
		if not sig.is_connected(_on_changed):
			sig.connect(_on_changed)
	refresh()


func _exit_tree() -> void:
	for sig: Signal in [Events.settlement_raised, Events.settlement_tier, Events.checkpoint_loaded]:
		if sig.is_connected(_on_changed):
			sig.disconnect(_on_changed)


func settlement() -> Dictionary:
	return SettlementRules.record(settlement_id)


func project_name() -> String:
	return str(SettlementRules.project(settlement(), project_id).get("name", project_id))


## True while the project is the one being earned and not raised.
func is_open() -> bool:
	var rec := settlement()
	if rec.is_empty():
		return false
	var st := SettlementWork.state(rec)
	return SettlementRules.project_tier(rec, project_id) == SettlementRules.tier_of(st) + 1 \
		and not bool(SettlementRules.project_state(st, project_id).raised)


func refresh() -> void:
	enabled = is_open()


func _on_changed(..._args: Array) -> void:
	refresh()


## True when the project still wants a load of `load_id`.
func accepts(load_id: String) -> bool:
	var rec := settlement()
	return not rec.is_empty() and SettlementRules.wants_load(rec, SettlementWork.state(rec), project_id, load_id) > 0


func prompt_text(_player: GiantPlayer) -> String:
	var p := SettlementRules.project(settlement(), project_id)
	var s := SettlementWork.status(settlement(), project_id)
	if bool(s.get("ready", false)):
		return str(p.get("raise", "Raise it"))
	return "%s (%d of %d done)" % [str(p.get("name", project_id)), int(s.get("met", 0)), int(s.get("total", 0))]


func can_interact(_player: GiantPlayer) -> bool:
	return bool(SettlementWork.can_raise(settlement(), project_id).get("ok", false))


func blocked_reason(_player: GiantPlayer) -> String:
	return str(SettlementWork.can_raise(settlement(), project_id).get("message", ""))


func interact(player: GiantPlayer) -> void:
	last_result = SettlementWork.raise(settlement(), project_id)
	if not bool(last_result.get("ok", false)):
		Events.hud_message.emit(str(last_result.get("message", "")), "warn")
		return
	Events.hud_message.emit(str(last_result.message), "good")
	_dust()
	if player != null and player.camera_rig != null:
		player.camera_rig.add_shake(0.5)
	refresh()


## A load set down here: its dust.
func on_delivered() -> void:
	_dust()


func _dust() -> void:
	if not is_inside_tree() or DisplayServer.get_name() == "headless":
		return
	DustBurst.puff(get_parent(), global_position + Vector3.UP * 1.5, 9.0, 22, 5.0, Color(0.72, 0.68, 0.6))
