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
## B1: the functional armour changed (Armour; GameSession.expansion.equipment). kind: "crafted" (a forge made a piece or a
## weapon: id is its record), "refit" (a piece to its next tier), "perk" (a piece's perk set), "equipped",
## "unequipped", "shown", "hidden" (the Equipment tab). The router plays the forge's sound for the forge's three.
signal armour_changed(tick: int, kind: String, id: String)

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

# --------------------------------------------------------------------------- campaign and world (M7-M9)
# Every signal of the M6-M9 plan (section 2.4), declared up front by P20 so the packages that emit
# them and listen to them never edit this block. Each one names its emitter ("Emitter:"); a
# listener connects only to what exists (Audio checks Events.has_signal()). Later packages add a
# signal nobody declared here directly below their own anchor at the end of the file.

## A level change is asked for. reason: exit | fast_travel | debug | bot.
## Emitter: LevelExit (P20; the Valley's exits P26), the map screen (P27), the bots (P38).
## Listener: GameSession.travel_to.
signal travel_requested(level_id: String, checkpoint_id: String, reason: String)
## Emitter: GameSession (P20), after the destination's checkpoint, before the reload.
## Listeners: Audio (fade), the HUD.
signal level_leaving(tick: int, from_level: String, to_level: String, reason: String)
## The level is ready: the ring loaded and the samples registered. reason: new_game | continue |
## death | travel | fast_travel | debug. Emitter: GameSession (P20).
## Listeners: Audio, Quests, Discovery, the tutorial, the bot.
signal level_entered(tick: int, level_id: String, reason: String)
## Emitter: ChunkStreamer (P24a). Listeners: Discovery, the skyline mask, debug.
signal world_chunk_loaded(chunk_id: String)
## Before any node of the chunk is freed. Emitter: ChunkStreamer (P24a).
## Listener: the EncounterDirector (despawns the members standing in it).
signal world_chunk_unloading(chunk_id: String)
## Emitter: ChunkStreamer (P24a).
signal world_chunk_unloaded(chunk_id: String)
## Emitter: WorldRoot (P24a; 15 m hysteresis). Listeners: Audio, the region banner (P27), Quests.
signal region_changed(tick: int, region_id: String, previous_id: String)
## Emitter: Discovery (P27). Listeners: the HUD toast, the Audio stinger, Quests, bot metrics.
signal poi_discovered(tick: int, poi_id: String)
## Emitter: Quests (P27). Listeners: the objective marker, the compass, the tracker.
signal quest_tracked(quest_id: String)
## Emitter: SizeGate and stage-gated props (P26). Listeners: a HUD message, Audio (the gate's own
## cue), the tutorial.
signal size_gate_blocked(tick: int, gate_id: String, min_stage: int, message: String)
## Emitter: BreakableProp trampling (P26). Listeners: Audio, FactionState (houses), metrics.
signal trampled(tick: int, world_id: String, entity_id: String)
## state: formed | advancing | braced | broken | routed | banner_fell.
## Emitter: Formation (P30). Listeners: the HUD lock label, Audio, bot metrics, the tutorial.
signal formation_changed(tick: int, formation_id: String, state: String)
## Emitter: SiegeEngine (P32). Listeners: Audio, metrics.
signal siege_engine_fired(tick: int, engine_id: String, action_id: String, target_id: String)
## Emitter: SiegeEngine (P32). Listeners: Audio, metrics.
signal siege_engine_crewed(tick: int, engine_id: String, crewed: bool)
## An evolution replaced its base ability in a slot. Emitter: PlayerProgression (P31).
## Listeners: the HUD notice, Audio, the tutorial.
signal ability_evolved(tick: int, from_id: String, to_id: String, slot_key: String)
## Emitter: PlayerProgression (P33). Listeners: the HUD, Audio, Quests.
signal talent_learned(tick: int, talent_id: String)
## Emitter: PlayerProgression (P33). Listeners: Quests, Audio, the HUD.
signal ancestry_chosen(tick: int, ancestry_id: String)
## Emitter: BattleBoss, RivalGiantBrain (P34). Listeners: Quests, Audio, the boss bar, the yield prompt.
signal boss_yielded(tick: int, boss_id: String)
## reason: left (the player left the arena; the boss resets) | fled (the Matriarch's drive-out) |
## yielded_talk (M8 release: Harrok's talk ending chosen while his duel is engaged - the duel ends without a
## victory). Emitter: BossArena, BattleBoss, MatriarchBrain (P34), MootArena. Listeners: Audio, the boss bar,
## Quests, GameSession (fled, yielded_talk: the fight's end checkpoint).
signal boss_disengaged(tick: int, boss_id: String, reason: String)
## Emitter: WanderDirector (P37). Listeners: metrics, debug.
signal wander_spawned(tick: int, template_id: String, encounter_id: String)
## Emitter: WorldEvent (P37). Listeners: Quests, the HUD, Audio.
signal world_event_started(tick: int, event_id: String)
## Emitter: WorldEvent (P37). Listeners: Quests, the HUD, Audio.
signal world_event_ended(tick: int, event_id: String, outcome: String)

# --------------------------------------------------------------------------- appearance (M10)
# The signal of the M10 plan (§2.11), declared by P42. Presentation only: nothing in the simulation, AI,
# combat, world or quests listens to it; GameSession's checkpoint rule does.

## The player kept a new look at a shrine (the creator's "Keep this look": P44's Appearance tab calls
## PlayerAppearance.set_record). Emitter: PlayerAppearance (P42). Listener: GameSession (the shrine's
## checkpoint is taken again at once, as for the other shrine choices: M8 gate F15).
signal appearance_changed(tick: int, entity_id: String)

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

# M6-M9 (written by P20, plan M6-M9 §1.5).

## @anchor P21

## @anchor P22

## @anchor P23

## @anchor P24a

## @anchor P24b

## @anchor P25

## @anchor P26

## @anchor P27

## @anchor P28

## @anchor P29

## @anchor P30

## @anchor P31

## @anchor P32

## @anchor P33

## @anchor P34

## @anchor P35

## @anchor P36

## @anchor P37

## @anchor P38

## @anchor P39

## @anchor P40

# M10 (written by P42, plan M10 §1.5).

## @anchor P41

## @anchor P43

## @anchor P44

## @anchor P45

## @anchor P46

## @anchor P47

# M11 (written by P49, plan M11 §1.5: Part A's pre-declarations; no gameplay signal is added by M11).

## @anchor P50

## @anchor P51

## @anchor P52

## @anchor P53

## @anchor P54

## @anchor P55

## @anchor P56

## @anchor P57

## @anchor P58

## @anchor P59

## @anchor P60

## @anchor P61

## @anchor P62

## @anchor P63

## @anchor P64

## @anchor P65

## @anchor P66

# The open-world expansion (0.14; the A packages).

## @anchor A2
## A titan's plate broke (TitanEnemy: its mesh hides, stone flies, it staggers; the region is a weak point now).
signal plate_broken(tick: int, entity_id: String, plate_id: String)
## A4: a titan went down on a knee (a topple plate broke, or enough damage to its broken region after) for
## `seconds`, and rose again (TitanEnemy).
signal titan_toppled(tick: int, entity_id: String, plate_id: String, seconds: float)
signal titan_rose(tick: int, entity_id: String)

## @anchor B3
## B3: a titan's broken plate began to grow back over its wound (the Rootwarden's bark; PlateRules regrow), grew back
## whole (its region armoured again), or had its wound seared by fire (it never regrows in the attempt); a "wither"
## plate broke (his knot: no plate regrows for `seconds`); a dormant titan woke (a blow, or his territory's call).
signal plate_regrowing(tick: int, entity_id: String, plate_id: String)
signal plate_regrown(tick: int, entity_id: String, plate_id: String)
signal plate_seared(tick: int, entity_id: String, plate_id: String)
signal titan_withered(tick: int, entity_id: String, plate_id: String, seconds: float)
signal titan_woke(tick: int, entity_id: String, reason: String)
## C2: a titan's guard broke (its meter full: the Broken Warden's shield beaten aside), a titan lost the plate he fought
## with (his shield broken or thrown down: it lies where it fell), rubble of his old walls fell on him.
signal titan_guard_broken(tick: int, entity_id: String, plate_id: String)
signal titan_disarmed(tick: int, entity_id: String, plate_id: String)
signal titan_rubble(tick: int, entity_id: String, world_id: String)

## @anchor C4
## C4: a settlement's development (SettlementWork): a load set down at a project's site, materials given to it
## (`what` "haul:<load>" | "give:<item>"), a project raised by the giant at its site, a settlement standing at a new
## tier (its work shown, its unlocks open), the tier's life come behind the giant's back (its folk, fires, banners),
## and a project whose needs are all met (ready to raise). The giant took up or set down a load (PlayerHaul).
signal settlement_progress(tick: int, settlement_id: String, project_id: String, what: String)
signal settlement_raised(tick: int, settlement_id: String, project_id: String)
signal settlement_tier(tick: int, settlement_id: String, tier: int)
signal settlement_settled(tick: int, settlement_id: String, tier: int)
signal settlement_ready(tick: int, settlement_id: String, project_id: String)
signal haul_changed(tick: int, load_id: String, carrying: bool)
## C4: a settlement's garrison loosed an arrow (or the beacon's great bow a bolt) from `from` (SettlementGarrison).
signal garrison_loosed(tick: int, settlement_id: String, from: Vector3, kind: String)

## @anchor D1
## D1: the cold (PlayerRime): the rime on a giant changed (0..100: a breath, a blow of the Frostbound's, his cold, a
## wade in open water; a fire, a heavy blow or time shedding it), rose full and froze him fast for `seconds` (he cannot
## dodge until a heavy blow shatters it or it thaws), or the freeze ended (`shattered`: broken by his own blow).
signal rime_changed(tick: int, entity_id: String, rime: float)
signal rime_frozen(tick: int, entity_id: String, seconds: float)
signal rime_thawed(tick: int, entity_id: String, shattered: bool)
## D1: a frozen tarn's ice (IceSheet): a cell cracked (state 1) or broke open (state 0) under a blow, a stomp or a
## weight, or froze again (1 from 0); a titan broke through it and went down to the knee in the water.
signal ice_changed(tick: int, sheet_id: String, cell: int, state: int, by_id: String)
signal titan_fell_through(tick: int, entity_id: String, point: Vector3)
