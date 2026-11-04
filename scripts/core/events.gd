extends Node
## Global event bus (autoload "Events").
##
## Gameplay systems emit these after they have changed state; presentation (HUD, effects,
## camera), persistence and tests subscribe. Nothing connected here may spend resources or
## change combat state on its own. Every event carries the simulation tick and stable ids.

## An action was accepted: costs were paid and its cooldown started (once).
signal ability_started(tick: int, actor_id: String, action_id: String, instance_id: int)
## A request was refused. Nothing was spent. reason is a short machine-readable code.
signal action_rejected(tick: int, actor_id: String, action_id: String, reason: String)
## One hit was resolved against one target.
signal hit_resolved(tick: int, result: HitResult)
## A weapon sweep was stopped by world geometry (a wall, the floor, an intact fence).
signal attack_clanked(tick: int, actor_id: String, instance_id: int, point: Vector3)
## An area ability fired its pulse (presentation: ground ring, camera shake).
signal area_pulse(tick: int, actor_id: String, action_id: String, center: Vector3, radius: float)
## Emitted exactly once per death.
signal entity_died(tick: int, entity_id: String, killer_id: String)
signal staggered(tick: int, entity_id: String, duration_s: float, reason: String)
## Emitted exactly once per persistent object destruction.
signal object_destroyed(tick: int, world_id: String, by_entity_id: String)
signal loot_awarded(tick: int, world_id: String, item_id: String, count: int, recipient_id: String)
## Reserved for milestone M3 (growth at shrines). Declared now so listeners can be written.
signal growth_changed(tick: int, entity_id: String, old_stage: int, new_stage: int)
signal lock_target_changed(actor_id: String, target_id: String, reason: String)
signal camera_mode_changed(mode: int)
## Short player-facing notice for the HUD ("Not enough stamina", "Parry!").
signal hud_message(text: String, kind: String)
## Ask the main scene to rebuild the sandbox. debug=true also clears world deltas.
signal sandbox_reset_requested(reason: String)
