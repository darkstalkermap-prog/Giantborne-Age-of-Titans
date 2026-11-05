class_name PlayerComponent
extends RefCounted
## Base of the giant's components (plan §2.7.1). GiantPlayer owns one instance per entry of
## GiantPlayer.COMPONENTS that exists, calls setup() once, then drives the hooks below from its
## 60 Hz sim_step. Every hook is optional; the defaults do nothing.
##
## Components share the actor's public state (player.facing_yaw, player.controller, ...) and
## talk to each other only through public methods (player.targeting.locked_entity(), ...),
## never through each other's private fields.

var player: GiantPlayer


## Called once when the component is added (from GiantPlayer._ready for the registry), after
## the controller and router exist. `player` is already set; overrides call super(p) anyway.
func setup(p: GiantPlayer) -> void:
	player = p


## Order in which edges are offered: lower first (grab 10, interact 50, default 100).
func edge_priority() -> int:
	return 100


## Offered every router edge of the tick (meta edges first, then action edges) unless a
## component with a lower edge_priority consumed it. Return true to consume it.
func handle_edge(_edge: StringName) -> bool:
	return false


## Before any edge is dispatched (only while alive).
func pre_actions(_intents: Dictionary, _dt: float) -> void:
	pass


## After movement and hit queries, before pools and poise tick.
func post_movement(_tick: int, _dt: float) -> void:
	pass


func on_action_started(_action: ActionDef, _instance_id: int) -> void:
	pass


func on_action_ended(_action: ActionDef, _instance_id: int, _interrupted: bool) -> void:
	pass


## The growth profile changed (GiantPlayer.set_profile).
func on_profile_changed(_old_profile: Dictionary, _new_profile: Dictionary) -> void:
	pass


## The equipped weapon changed (GiantPlayer.set_weapon).
func on_weapon_changed(_weapon: Dictionary) -> void:
	pass


## Character state (save data) being applied; read the keys this component owns.
func apply_state(_state: Dictionary) -> void:
	pass


## Write the keys this component owns into `out` (it already holds every passthrough key).
func capture_state(_out: Dictionary) -> void:
	pass


## Extra keys for ActorRig (get_rig_state), e.g. "holding".
func rig_state(_out: Dictionary) -> void:
	pass


## Extra keys for the F3 debug panel (get_debug_info).
func debug_info(_out: Dictionary) -> void:
	pass


## {} or {"priority": int, "prompt": String, "distance": float, "call": Callable,
## "id": String (optional, reported in Events.interacted)}: lets a component offer an E action
## that competes with the Interactable nodes around the player.
func interact_candidate() -> Dictionary:
	return {}


## The player leaves the scene (unload, reload): release anything held.
func on_exit() -> void:
	pass
