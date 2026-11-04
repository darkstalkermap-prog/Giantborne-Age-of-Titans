class_name PlayerInteract
extends PlayerComponent
## The interact key (E / pad X). Every REFRESH_TICKS it picks the best candidate around the
## player: Interactable nodes within radius_m of the capsule edge and in front (or very close),
## plus whatever the other components offer through interact_candidate(). The lowest priority
## value wins, then the shortest distance. current_prompt() serves the HUD widget.
##
## Pressing E re-checks at once: on the best candidate it calls interact() (and emits
## Events.interacted), or shows the candidate's blocked_reason() as a warning when it cannot be
## used right now. With no candidate the key does nothing and the edge is left to the default
## mapping (which ignores it).

const REFRESH_TICKS := 6
const FRONT_DOT := 0.2      ## minimum cos(angle) between facing and the candidate ...
const CLOSE_M := 1.5        ## ... unless it is closer than this

var _best: Dictionary = {}
var _last_refresh_tick := -1000000


func edge_priority() -> int:
	return 50


func handle_edge(edge: StringName) -> bool:
	if edge != &"interact":
		return false
	refresh()
	if _best.is_empty():
		return false
	use_candidate(_best)
	return true


func post_movement(tick: int, _dt: float) -> void:
	if tick - _last_refresh_tick >= REFRESH_TICKS:
		_last_refresh_tick = tick
		refresh()


func on_exit() -> void:
	_best = {}


func debug_info(out: Dictionary) -> void:
	out["interact"] = current_prompt()


## Prompt of the current best candidate ("Talk", "Rest"), or "" when there is none.
func current_prompt() -> String:
	return str(_best.get("prompt", ""))


## The current best candidate: {} or {"priority", "prompt", "distance", "call", "id",
## "node" (the Interactable, absent for component candidates)}.
func current_candidate() -> Dictionary:
	return _best


## Recomputes the best candidate now.
func refresh() -> void:
	_best = {}
	if player == null or not player.is_inside_tree():
		return
	var origin := player.global_position
	var fwd := -player.global_transform.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	var capsule_r := float(player.profile.get("capsule_radius_m", 0.85))
	for node in player.get_tree().get_nodes_in_group("interactables"):
		var it := node as Interactable
		if it == null or not it.enabled or not it.is_inside_tree():
			continue
		var to := it.global_position - origin
		to.y = 0.0
		var dist := to.length()
		if dist > it.radius_m + capsule_r:
			continue
		if dist >= CLOSE_M and fwd.dot(to / maxf(dist, 1e-6)) < FRONT_DOT:
			continue
		_consider({"priority": it.priority, "prompt": it.prompt_text(player), "distance": dist,
			"id": it.interact_id, "node": it})
	for c: PlayerComponent in player.components():
		var cand := c.interact_candidate()
		if not cand.is_empty():
			_consider(cand)


func _consider(cand: Dictionary) -> void:
	if _best.is_empty() or _better(cand, _best):
		_best = cand


static func _better(a: Dictionary, b: Dictionary) -> bool:
	var pa := int(a.get("priority", 50))
	var pb := int(b.get("priority", 50))
	if pa != pb:
		return pa < pb
	var da := float(a.get("distance", 0.0))
	var db := float(b.get("distance", 0.0))
	if not is_equal_approx(da, db):
		return da < db
	return str(a.get("id", "")) < str(b.get("id", ""))


## Uses a candidate: an Interactable's interact() (or its blocked reason), or a component's
## Callable. Emits Events.interacted for candidates with an id once P01's signal exists.
func use_candidate(cand: Dictionary) -> void:
	if cand.has("node"):
		var node: Variant = cand.node
		if not is_instance_valid(node) or not (node as Node).is_inside_tree():
			return
		var it := node as Interactable
		if it == null:
			return
		if not it.can_interact(player):
			var reason := it.blocked_reason(player)
			if reason != "":
				Events.hud_message.emit(reason, "warn")
			return
		it.interact(player)
	else:
		var call: Callable = cand.get("call", Callable())
		if not call.is_valid():
			return
		call.call()
	var id := str(cand.get("id", ""))
	if id != "" and Events.has_signal(&"interacted"):
		Events.emit_signal(&"interacted", Sim.tick, player.entity.entity_id, id)
