extends Node
## Global event bus (autoload "Events").
##
## Gameplay systems emit these after they have changed state; presentation (HUD, effects,
## camera), persistence and tests subscribe. Nothing connected here may spend resources or
## change combat state on its own. Every gameplay event carries the simulation tick and stable
## ids. Connect method callables, never capturing lambdas (they outlive their nodes).
##
## Every signal of the M2-M5 plan (section 2.4) is declared here up front, grouped by area, so
## packages emit and listen instead of editing this file. A package that still needs a new
## signal adds it directly below its own "## @anchor" line at the end of the file.

# --------------------------------------------------------------------------- combat (M1)

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
## Growth stage changed (PlayerGrowth, P05; also the debug grow/shrink keys).
signal growth_changed(tick: int, entity_id: String, old_stage: int, new_stage: int)
signal lock_target_changed(actor_id: String, target_id: String, reason: String)
signal camera_mode_changed(mode: int)
## Short player-facing notice for the HUD ("Not enough stamina", "Parry!").
signal hud_message(text: String, kind: String)
## Ask the main scene to rebuild the sandbox (main clears world deltas and reloads the scene).
signal sandbox_reset_requested(reason: String)

# --------------------------------------------------------------------------- statuses and effects

## CombatEntity.apply_status (P01) applied or refreshed a status.
signal status_applied(tick: int, entity_id: String, status_id: String, source_id: String, duration_s: float)
## The Sim status pass removed an expired status (once per expiring instance).
signal status_expired(tick: int, entity_id: String, status_id: String)
## CombatEntity.heal (P01): amount is the health actually gained.
signal healed(tick: int, entity_id: String, amount: float, source_id: String)
## An ability's visible effect. kind: sector | roar | self_buff | cast | aim_preview
## (AttackRunner handlers P03, PlayerGrab P07).
signal ability_effect(tick: int, actor_id: String, action_id: String, kind: String, center: Vector3,
	radius: float, yaw: float, arc_deg: float)
signal projectile_spawned(tick: int, projectile_id: int, owner_id: String, action_id: String,
	position: Vector3, velocity: Vector3, visual: String)
## hit_entity_id "" = the projectile hit the world.
signal projectile_impact(tick: int, projectile_id: int, position: Vector3, hit_entity_id: String)

# --------------------------------------------------------------------------- enemies and AI

## Emitted by EnemyActor on controller.phase_entered WINDUP for an action with a telegraph (P04).
signal telegraph_started(tick: int, actor_id: String, action_id: String, target_id: String,
	shape: String, origin: Vector3, yaw: float, radius: float, length: float, duration_s: float)
signal morale_changed(tick: int, entity_id: String, morale: float, delta: float, reason: String)
signal enemy_routed(tick: int, entity_id: String, encounter_id: String)
signal encounter_leashed(tick: int, encounter_id: String, entity_id: String)
signal encounter_activated(tick: int, encounter_id: String)
signal encounter_cleared(tick: int, encounter_id: String)
signal boss_engaged(tick: int, boss_id: String)
signal boss_phase_changed(tick: int, boss_id: String, phase: int)
## BossArena (P11a), after the arena is clear.
signal boss_defeated(tick: int, boss_id: String)
## state: warned | hostile | stood_down (FactionState, P11b).
signal faction_changed(tick: int, faction: String, state: String)

# --------------------------------------------------------------------------- grab

signal grab_started(tick: int, holder_id: String, target_id: String)
## reason: thrown | dropped | crushed | interrupted | holder_died | target_died | timeout | unloaded
signal grab_ended(tick: int, holder_id: String, target_id: String, reason: String)

# --------------------------------------------------------------------------- growth, shrines, checkpoints

signal growth_blocked(tick: int, entity_id: String, reason: String, message: String)
## First activation per load, after the free Rest (Shrine, P05).
signal shrine_activated(tick: int, shrine_id: String)
signal shrine_rested(tick: int, shrine_id: String)
## kind: shrine | waystone
signal checkpoint_reached(tick: int, checkpoint_id: String, kind: String)
signal checkpoint_saved(tick: int, checkpoint_id: String, ok: bool, message: String)
signal checkpoint_loaded(tick: int, checkpoint_id: String, source: String)
## main (death confirm) and debug F9 ask GameSession to reload the last checkpoint (P06).
signal reload_checkpoint_requested(reason: String)
## Title and pause screens ask GameSession to change mode (P06).
signal mode_change_requested(mode: String, options: Dictionary)

# --------------------------------------------------------------------------- world objects and interaction

## A structural prop moved to another authored damage stage (BreakableProp, P08).
signal object_stage_changed(tick: int, world_id: String, stage_index: int, stage_id: String)
## BreakableProp.force_open (P08).
signal object_opened(tick: int, world_id: String, reason: String)
## PlayerInteract (P02) after an interaction ran.
signal interacted(tick: int, actor_id: String, interact_id: String)
signal area_entered(tick: int, area_id: String, entity_id: String)
signal area_exited(tick: int, area_id: String, entity_id: String)
## WorldState.set_flag / try_set_flag, only when the stored value changed.
signal flag_changed(tick: int, flag_id: String, value: Variant)

# --------------------------------------------------------------------------- character, items, progression

signal weapon_equipped(tick: int, entity_id: String, weapon_id: String)
signal loadout_changed(tick: int, entity_id: String)
## Props with xp_reward (P08), Quests and dialogue (P13) ask PlayerProgression (P12) for XP.
signal xp_award_requested(amount: int, source: String)
signal xp_gained(tick: int, amount: int, source: String, total: int)
signal level_changed(tick: int, old_level: int, new_level: int)
## slot_key "" = learned but not slotted.
signal ability_learned(tick: int, action_id: String, slot_key: String)
signal attributes_changed(tick: int)
## WorldState.add_item / remove_item.
signal item_added(tick: int, item_id: String, count: int, source: String)
signal item_removed(tick: int, item_id: String, count: int, reason: String)
## Forge (P12).
signal upgrade_applied(tick: int, from_weapon: String, to_weapon: String)

# --------------------------------------------------------------------------- quests, dialogue, tutorial

signal quest_started(tick: int, quest_id: String)
signal quest_stage_changed(tick: int, quest_id: String, stage_id: String)
signal quest_completed(tick: int, quest_id: String)
signal quest_abandoned(tick: int, quest_id: String)
## NpcTalker (P13) -> Quests (P13).
signal dialogue_requested(npc_id: String, dialogue_id: String)
signal dialogue_started(tick: int, dialogue_id: String, npc_id: String)
signal dialogue_outcome(tick: int, dialogue_id: String, outcome: String)
signal dialogue_ended(tick: int, dialogue_id: String)
signal tutorial_shown(tick: int, prompt_id: String)
signal tutorial_dismissed(tick: int, prompt_id: String, reason: String)
signal slice_completed(tick: int)

# --------------------------------------------------------------------------- UI

## Gameplay (shrine, NPC, forge, end) asks the ScreenStack (P03) to open a screen, deferred.
signal ui_screen_requested(screen: String, args: Dictionary)

# --------------------------------------------------------------------------- package anchors
# A package that needs a signal nobody declared above adds it directly below its own anchor.

## @anchor P02

## @anchor P03

## @anchor P04

## @anchor P05

## @anchor P06

## @anchor P07

## @anchor P08

## @anchor P09

## @anchor P10a

## @anchor P10b

## @anchor P11a

## @anchor P11b

## @anchor P12

## @anchor P13

## @anchor P14

## @anchor P15

## @anchor P16

## @anchor P17a

## @anchor P17b

## @anchor P18
