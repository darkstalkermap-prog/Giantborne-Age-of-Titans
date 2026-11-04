# GIANTBORN: AGE OF TITANS
## Claude build prompt and consolidated game specification
Version 2.0 | November 4, 2026 | Low-poly prototype first

> Source: the project owner's handoff document (`Giantborn_Claude_Build_Prompt.pdf`), kept here
> verbatim as the design reference for every milestone. Implementation decisions that refine
> or interpret it are recorded in [DECISIONS.md](DECISIONS.md).

## 1. START HERE - PROMPT FOR CLAUDE
You are my game development partner. Build Giantborn: Age of Titans from the specification below. Begin with a small, playable, low-poly 3D combat prototype in Godot using GDScript. Use a stable Godot version supported by your available tools, record the exact version, and keep the project compatible with it. If you cannot run Godot, say so clearly, supply the complete project and exact local run instructions, and distinguish code review from actual runtime testing. Do not claim that the game works unless you tested it.

My priority is working gameplay with simple graphics. Do not begin by building a massive open world, expensive visuals, or all ten giant stages. Make routine implementation decisions without repeatedly asking for permission. Ask only about a genuine blocker. Preserve the game vision below while implementing the milestones in order. Stop expanding scope when a milestone fails its acceptance checks.

Use simple original meshes, primitive shapes, flat materials, and placeholder sounds or silence. Prefer built-in Godot features and avoid paid assets, online services, API keys, and plugins unless demonstrably necessary. Create a playable project, not just a design document. Include a README, controls, known limitations, and a short test checklist. Work in small, runnable increments. Keep combat rules, data, presentation, input, and persistence separate. Use editable JSON for balance and content, stable string IDs, meters and seconds, and versioned saves. Unreal Engine is an optional future migration, not the current target.

FIRST DELIVERY: One 120 x 120 meter arena, one 12-foot giant, one melee enemy, a practice dummy, one breakable fence, both camera modes, movement, light/heavy attacks, block, parry, dodge, health/stamina, optional lock-on, and a debug reset. Add Heavy Footfall only after basic combat works. Provide the project files and launch instructions. Do not implement the entire specification in one pass. Tell me exactly which acceptance checks passed, failed, or could not be run. Then continue through the agreed milestones when requested.

Treat all unimplemented features as roadmap items. Use the numerical values below as initial tuning, not proven balance. If two rules conflict, use the explicit resolution notes in this document, record the change, and keep the prototype small.

## 2. GAME VISION AND FIXED DECISIONS
Giantborn: Age of Titans is a single-player open-world fantasy action RPG. Begin as a juvenile giant approximately twice human height and grow from 12 feet to 140 feet over 20 levels and 10 physical stages. Explore kingdoms, villages, forests, ruins, and giant territories; fight, intimidate, negotiate, or protect smaller peoples. Eventually confront dragons, armies, rival giants, and primordial titans.

Combat combines Skyrim's exploration and camera freedom, God of War's impact and grappling, Elden Ring's positioning and stamina, and EverQuest's abilities, buffs, resistances, equipment, and specialization. These are design influences, not instructions to copy assets, characters, UI, or worlds. Combat is real-time action; hotbar abilities supplement manual attacks. There is no mandatory auto-attack rotation.

Fixed decisions: switchable first-person and third-person cameras; balanced difficulty; optional lock-on; selective destruction; eight equipped abilities plus one ultimate; health, stamina, essence, and fury; 20 levels and ten growth stages; persistent character and selected world changes. Third-person is the default. Every growth milestone must change interactions, reach, positioning, and enemy tactics as well as numbers.

Core loop: explore, assess threats, fight or resolve an encounter peacefully, gain experience and equipment, choose upgrades, evolve at a safe location, revisit familiar spaces with new capabilities, then face larger threats. The world should feel more vulnerable as the giant grows, while organized armies and larger creatures remain dangerous. Ordinary guards should not become inexplicably durable against a World Titan.

Scope labels throughout this document: Sandbox is the first technical delivery. Valley is the later 20-30 minute vertical slice. Full game is the long-term vision. New formulas, tuning values, schemas, and acceptance thresholds in this handoff are proposed implementation decisions; the source discussion did not establish tested game balance.

## 3. ENGINE AND DEVELOPMENT STRATEGY
Default: Godot with GDScript and the Compatibility renderer, subject to a day-one hardware check. It offers a direct text-based workflow for Claude to generate and revise. Pin a stable version instead of requiring the newest release. Use CharacterBody3D-style character movement, engine collision queries, simple animation, and ordinary scene composition. Keep the initial target Windows desktop with keyboard/mouse and controller support added before the Valley milestone.

Godot is the recommended lightweight starting choice, not a claim about Claude's specific installed integrations. Validate that Claude can produce a project which opens, runs, and exports in the chosen environment. Godot's MIT license and renderer options are documented in sources [1] and [2]. Compatibility has different feature limits from the other renderers; do not depend on advanced rendering features. Low-poly graphics alone do not solve expensive AI, physics, or world streaming.

Unity with C# is a realistic alternative if the developer already has a functioning Unity workflow. It brings additional editor and project overhead, and its code and scenes would still need work to migrate to Unreal. Unity Personal eligibility is governed by its current terms [5]. Do not change engines just because a generated script has a bug.

Unreal Engine is suitable later if its tooling, team skills, profiling results, and content ambitions justify it. It can also produce low-poly games, but starting there is not necessary for this prototype. Moving to Unreal means rebuilding engine integrations, not pressing a graphics-conversion button. Unreal licensing has product-specific conditions [6]; verify terms before commercial release.

Decision gate: keep Godot if the slice is fun and meets performance goals. Consider Unreal only after a small migration experiment proves a concrete benefit. Do not promise the migration will save time or preserve all code. Do not spend the prototype budget building a custom engine-independent framework.

## 4. CONTROLS AND INPUT PRIORITY
All bindings must be remappable. Keyboard/mouse defaults preserve the original design.

| Action | Keyboard / mouse | Controller |
| --- | --- | --- |
| Move / look | WASD / mouse | Left / right stick |
| Light attack | Left mouse | RB / R1 |
| Heavy attack | Shift + left mouse | RT / R2 |
| Block / parry | Right mouse | LB / L1 |
| Dodge / jump | Space / F | B / Circle; A / Cross |
| Interact / grab | E | X / Square |
| Sprint | Shift + movement | Left-stick press |
| Lock target | Tab | Right-stick press |
| Switch target | Wheel while locked | Right-stick flick while locked |
| Camera mode | V | D-pad Up, without modifier |
| Abilities 1-4 | 1-4 | LT + A, B, X, Y |
| Abilities 5-8 | 5-8 | LT + D-pad Up, Right, Down, Left |
| Ultimate | R | LT + RT |

Modifier actions consume their inputs: LT + B uses slot 2 and does not dodge; LT + Up uses slot 5 and does not switch camera; LT + RT uses the ultimate and does not heavy attack. Shift + left mouse issues one heavy attack, stops sprinting, and never also issues light attack. Sprint resumes only with eligible movement after recovery. Holding block creates one parry window on initial press; repeated held frames do not reopen it.

Use separate gameplay, pause/menu, and text-entry input contexts. Pause suppresses gameplay input. Target switching has a 0.20-second repeat debounce. Queue at most one next action for 0.15 seconds, revalidating it when consumed; invalid requests do not spend resources. Expose hold/toggle sprint and lock-on, camera sensitivity, and vibration settings. The hotbar shows cost, cooldown, key binding, unavailable-state reason, and selected target where needed.

## 5. CAMERA AND TARGETING
One player entity owns both camera modes. Switching cameras does not respawn the player or change attack range. Third-person uses a collision-tested follow arm. Start at 6.5 m follow distance for stage 1, with zoom and shoulder offset; tune per growth stage. A sphere sweep retracts the camera at obstacles and smoothly restores distance. First-person uses a stabilized eye anchor at about 92% of height. Hide obstructing head geometry and use a simple hand/weapon representation. Camera bob, shake, hit flash, and motion blur should be independently reducible; default motion blur off.

Initial field of view is 75 degrees, adjustable. First-person lock-on provides target information and optional gentle aim assistance without compulsory camera rotation. Third-person lock-on frames the player and target; use a torso or low weak point rather than looking directly upward at a large target's head. Giant-scale fights favor third-person visibility, but first-person remains selectable.

Free targeting follows aim direction. Soft targeting can adjust attack facing by at most 10 degrees during windup and never pulls through a wall. Hard lock selects eligible hostile targets within 35 m and a 60-degree half-angle for stage 1; later stages override these values. Require visibility and a valid target anchor. Score candidates with Q = 0.55 * alignment + 0.30 * proximity + 0.15 * threat, with each term normalized to 0..1. Alignment = max(0, dot(aim, direction)); proximity = 1 - clamp(distance/range, 0, 1). Threat is authored by enemy role.

Release lock on death, invalid target, distance above 1.25 times lock range, or continuous obstruction above 0.75 seconds. Do not immediately acquire another target without a new request. Directional target switches choose the nearest visible screen-space candidate on the requested side. Large monsters expose named target anchors with shared health and optional limb poise. At stages 4-6, formations become selectable groups; stages 7-10 prioritize monsters, siege equipment, and formations over individual soldiers.

## 6. COMBAT STATE AND HIT RESOLUTION
Gameplay owns timing; animation displays it. Run the combat simulation on a fixed 60 Hz step and render independently. Use explicit states: Locomotion, Attacking, Blocking, Dodging, Casting, Staggered, Grabbed, Executing, and Dead. Idle is locomotion with zero movement. An attack has windup, active, and recovery phases. Each record defines costs, hit windows, allowed cancels, movement limits, and interrupt policy.

Priority: Dead overrides all; hard stagger interrupts ordinary attacks/casts; Grabbed and Executing permit only explicit escape or cancellation rules; normal requests require a valid transition. Dodge can cancel only designated recovery windows. Heavy attacks cannot be cancelled during their active strike. Validate resources, state, target eligibility, and cooldown before activation. Deduct costs and start cooldown once on acceptance. Interrupted committed actions receive no refund unless their data explicitly says otherwise.

| Action | Stamina | Windup / active / recovery | Initial rule |
| --- | --- | --- | --- |
| Light | 8 | 0.20 / 0.15 / 0.30 s | Three-hit chain; multipliers 1.0, 1.1, 1.25 |
| Heavy | 22 | 0.50 / 0.20 / 0.55 s | 1.8 damage multiplier; high poise damage |
| Dodge | 18 | Total 0.75 s | Invulnerable from 0.10 to 0.30 s |
| Block | 5 on entry | Held stance | Frontal 120-degree coverage |
| Perfect parry | 10 total | First 0.20 s of block | Eligible melee only; 5 extra on success |
| Sprint | 8 / second | While moving | Stops at zero stamina |

Block entry spends 5. Successful parry spends 5 more; if that is unavailable, evaluate as ordinary block. Later attacks cannot turn a failed parry into a free defense. Unblockable and unparryable flags are independent. Dodge invulnerability does not bypass kill volumes or explicitly tagged unavoidable hazards. At larger stages, dodge becomes a weighty sidestep with the same clearly signaled window, not a giant roll.

During active windows sweep weapon/limb shapes between previous and current poses. Collision queries include world occluders before damageable bodies. Deduplicate by attack-instance ID plus target entity, not by collider. Explicit multi-hit abilities use separate pulse IDs. Queue hit results in stable order and apply death once. A target already dead cannot generate additional resources. Cap hits per sweep only when authored, never silently because of an undersized collision-query buffer.

## 7. RESOURCES AND COMBAT FORMULAS
Level 1 baseline: 500 health, 100 stamina, 100 essence, and 0/100 fury. Proposed starting attributes are 10 each. Regenerate stamina at 15/second after one second without spending; pause regeneration while sprinting, blocking, or in attack/cast commitment. Essence regenerates at 4/second after two seconds without casting. Health recovers at safe rest or through healing; no automatic in-combat healing. Fury gains 4 per accepted damaging basic attack, 6 per parry, and 8 per kill, once per event; a basic attack's crowd hits still award only 4. Fury decays at 5/second after ten seconds outside combat.

Physical raw damage: D_raw = P * (1 + 0.015 * Strength) * M_ability * M_weapon * M_size.

P is attack base power, M_ability is its coefficient, M_weapon is an equipment multiplier, and M_size = clamp((attacker_height / 3.6576)^0.45, 1, 2.5). This uses attacker growth relative to the initial giant, not victim size. Relative size separately controls reactions. For magical attacks replace Strength with Intellect and use that spell's power and size policy. Default spell size multiplier is 1 unless authored otherwise.

Armor after penetration: A_eff = max(0, Armor - flat_penetration). Physical damage after armor = D_raw * 100 / (100 + A_eff). Elemental damage instead uses D_raw * (1 - resistance), with resistance clamped to -0.5..0.75. Split mixed attacks into typed portions before mitigation; armor does not also reduce elemental damage. Apply a 1.5 critical multiplier only when eligible, then weak-point multiplier (default 1, exposed weak point 1.25), then defense mitigation. Round once at the end. Default player critical chance is 5%; use seeded randomness in tests.

Block reduces eligible physical health damage by 75% and elemental damage by 50%. Impact stamina cost = ceil(0.25 * pre-block mitigated damage). If insufficient, consume remaining stamina, apply 50% of that damage, and stagger for 1.0 second. Parry negates eligible hit damage and adds 40 poise damage to the attacker. Immunity yields zero damage. No minimum damage rule overrides immunity.

Worked example: P=40, Strength=10, all multipliers=1, Armor=25 gives 46 raw and 36.8 mitigated damage, rounded to 37. A successful physical block yields 9 health damage and costs 10 impact stamina, in addition to the earlier block entry cost. A heavy using multiplier 1.8 produces 82.8 raw and 66 final damage against the same armor.

Poise is a separate accumulation meter. Stage-1 player threshold is 100; light attacks add 12, heavy attacks 35, Footfall 25. Recover 20/second after three seconds without poise damage. At threshold, stagger 1 second and reset the meter. Grant 1.5 seconds of stagger immunity after recovery. Apply poise scale clamp(attacker_height / defender_height, 0.25, 2); siege and magical restraint attacks may override this. Height alone never authorizes a grab.

Knockback speed = clamp(base_impulse * size_ratio / stability, 0, max_speed), where size_ratio is attacker height / defender height and stability is a positive authored value. This is a gameplay response, not a physical mass simulation. Clamp displacement against world collision. Never apply unbounded forces to giant rigid bodies.

## 8. ABILITIES, GRABS, AND STATUS EFFECTS
Eight equipped slots are the interface contract. Begin with one implemented ability, then four, then eight for the Valley. Slots can remain empty. Change loadout at safe rest. Full-game target is roughly 24 active abilities with upgrades, three talent trees, ancestry options, and one separate ultimate; that library is not a prototype requirement.

| Valley ability | Cost / cooldown | Initial effect |
| --- | --- | --- |
| Heavy Footfall | 20 stamina / 8 s | 3 m radius, P=40, 1.2 multiplier, 25 poise |
| Boulder Hurl | 15 stamina / 6 s | Stage 2; P=40, 1.6 multiplier; 25 m aimed projectile |
| Sweeping Blow | 18 stamina / 7 s | 120-degree arc in melee reach; 1.2 multiplier |
| Crushing Grip | 20 stamina / 10 s | Eligible small target; 1.5 multiplier, then release |
| Stone Skin | 25 essence / 20 s | +30 armor for 6 seconds; no stacking |
| Ancestral Mend | 30 essence / 15 s | Restore 100 health over 4 seconds |
| Runic Bolt | 15 essence / 4 s | P=40 using Intellect; 25 m magic projectile |
| Thunder Roar | 25 essence / 14 s | 6 m radius; morale -20; 30% slow for 3 seconds |

Prototype ultimate: Titan Surge costs 100 fury, lasts 6 seconds, and increases outgoing damage and poise damage by 25%. It grants no invulnerability and generates no fury while active. Full-game Worldbreaker replaces or upgrades the ultimate at stage 10: a telegraphed area strike in authored battle zones, not arbitrary terrain deformation. Footfall evolves toward Titan Stomp, Earthquake, and Worldbreaker themes, but shared visual themes do not imply shared cooldowns or duplicated ability slots.

Boulder Hurl becomes available at stage 2, level 3; an earlier tutorial may preview an inert rock but must not contradict the unlock. Tree weapon becomes available at stage 3. A prototype wooden practice gate can break at any stage; fortified gate breach is the stage-4 unlock. This resolves the original valley sequence's early gate destruction versus later siege unlock.

Grab requires distance within the authored reach, unobstructed line of sight, target height at most 50% of player height, target mass class within capacity, no grab immunity, and a supported attachment profile. Living targets also require broken poise. Recheck eligibility on attachment. Keep one held target, suspend its ordinary movement, and restore it on release, interruption, death, or scene unload. Throw uses a swept trajectory and ordinary damage events. Boss grapples require authored boss windows; low health alone never makes a dragon grabbable.

Status policy: Stone Skin refreshes duration without stacking magnitude; strongest slow wins and duration refreshes; healing ticks every 0.5 seconds and caps at maximum health; fear cannot stack-lock bosses. Apply explicit immunities by tags. Dispel, damage-over-time, elemental combinations, and complex buff stacking are full-game extensions.

## 9. GROWTH, PROGRESSION, AND EQUIPMENT
Use one character identity with stage-specific physical profiles. Do not implement growth by scaling only the mesh. Each profile defines height, collision, acceleration, step height, speed, reach, camera offsets, animation references, target rules, and interaction permissions. Conversion: one foot = 0.3048 meters.

| Stage | Unlock level | Height | Combat change |
| --- | --- | --- | --- |
| 1 | 1 | 12 ft / 3.66 m | Melee, defense, small-target grabs |
| 2 | 3 | 18 ft / 5.49 m | Boulder throwing and longer reach |
| 3 | 5 | 26 ft / 7.92 m | Tree weapon and stronger crowd control |
| 4 | 7 | 36 ft / 10.97 m | Fortified gate breach; formation threats |
| 5 | 9 | 48 ft / 14.63 m | Formation sweep |
| 6 | 11 | 62 ft / 18.90 m | Siege disruption |
| 7 | 13 | 78 ft / 23.77 m | Large-monster grapple windows |
| 8 | 15 | 96 ft / 29.26 m | Colossal shockwave |
| 9 | 17 | 116 ft / 35.36 m | Titan executions |
| 10 | 20 | 140 ft / 42.67 m | Worldbreaker in designated zones |

Level 19 remains stage 9. Prototype stage profiles: heights 3.6576 / 5.4864 / 7.9248 m; capsule radii 0.85 / 1.20 / 1.65 m; total capsule heights 3.66 / 5.49 / 7.92 m; walk speeds 5.0 / 5.8 / 6.5 m/s; melee reach from actor center 3.5 / 4.8 / 6.5 m; follow distances 6.5 / 9 / 12 m. These are starting test values. Use a simple kinematic body, not simulated biological mass.

Apply growth only at a safe shrine outside combat. Test the new capsule and overhead clearance before changing anything. On failure retain the current stage and show an explanation. On success update collision, visuals, movement, camera, unlocked abilities, and navigation profile together; preserve health and resource percentages. Do not heal through repeated profile switching. Debug stage changes are clearly separate from progression.

Proposed XP to next level L is 100 + 50*(L-1), for L=1..19. Level 20 is capped. Award three attribute points and one talent point per gained level. Baseline attributes are Strength, Endurance, Dexterity, Intellect, Willpower, and Constitution at 10. Endurance adds 15 health and 2 stamina per point above 10; Intellect adds 2 essence; Constitution adds 3 poise threshold; Willpower adds 0.5 percentage points elemental resistance, capped at 20 points from attributes. Dexterity reduces attack recovery by 0.5% per point above 10, capped at 15%; active and parry windows do not change. Strength affects physical damage as specified.

Destroyer develops melee, grabs, and stagger; Guardian develops protection and poise; Primordial develops magic and fury. Ancestry is a small additional layer, with one neutral placeholder ancestry in the prototype. Full equipment families: clubs, swords, hammers, axes, and fists/grappling. Sandbox uses a club; Valley adds sword and hammer only after combat stabilizes. Giantforge reforging lets important gear fit later stages; ordinary gear does not grow infinitely. Prototype inventory is minimal: equipped weapon, a few loot items, and one upgrade interaction.

## 10. AI, ENCOUNTERS, AND BOSSES
Use a finite-state machine first: Idle, Patrol, Alert, Approach, Attack, Recover, Reposition, Flee, Staggered, Dead. Perception checks visible targets at 5 Hz; nearby movement updates each physics tick; tactical decisions at 5-10 Hz. Initial sight range 25 m, hearing radius 15 m for attacks, and last-known-position memory 3 seconds. Loss of target leads to investigation, then return to patrol. Path failures over two seconds trigger a new destination, not teleportation.

| Archetype | Tactical role and counterplay |
| --- | --- |
| Soldier | Guards the front, approaches legs, pauses between strikes; flank or heavy attack |
| Archer | Keeps 12-20 m distance, seeks authored cover/elevation; pressure or throw |
| Mage | Telegraphs slow/barrier attacks; interrupt or evade |
| Wolf | Flanks and lunges with clear windup; dodge then punish |
| Ogre | Slow heavy strikes and stagger resistance; recovery punish |

Valley has these five archetypes, introduced incrementally. Boss is a larger ogre variant using the same foundation. Civilians flee toward safe markers and do not use combat pathfinding continuously. Full-game extensions include trolls, dragons, rival giants, titans, and siege crews.

Attack coordination: at most two melee enemies can hold attack tokens around the player; others reposition. Ranged enemies stagger projectile launches. Initial melee windups are at least 0.45 seconds, major attacks at least 0.8 seconds. Enemies may track during early windup but should not instantly rotate after committing. Difficulty should come from readable threats and decisions, not unavoidable overlapping damage.

Morale is 0..100, initially 70 for soldiers. Commander loss subtracts 25, siege destruction 20, and each nearby allied death 10 within a two-second event debounce. Below 25, eligible units flee for at least 4 seconds; above 45 they can regroup if a leader remains. Bosses ignore morale unless authored. Size modifies preferred tactics: outmatched infantry retreats to formations, ranged units spread, and siege/magic target the giant. Basic soldiers do not gain huge health just because the player grew.

Valley boss has 1,500 health and 150 poise as initial tuning. Above 50% health it alternates two-hit melee and a telegraphed slam. Below 50% it adds a charge with a punishable wall recovery. No unseen instant phase damage. Arena has a safe exit before engagement and a checkpoint outside. Full-game dragon concept: aerial attacks countered by boulders/magic, grounded limb targeting, a poise-break grapple opportunity, and a more aggressive final phase. This is later content, not a first-delivery requirement.

## 11. SELECTIVE DESTRUCTION AND WORLD PERSISTENCE
Three categories: cosmetic props react without saved state; breakables have health and an intact/broken mesh; structural objects have authored damage stages and persistent consequences. Prototype examples are a fence, a tree, and a practice gate. Fortresses, walls, towers, and bridges arrive later. Terrain remains fixed. Do not create runtime voxel destruction or full-building structural physics.

Each persistent object has a stable world ID, damage stage, health, loot-awarded flag, and collision/navigation consequences. Apply damage only if attack category and stage permissions match. At zero health, swap to the broken representation, remove blocking collision where appropriate, emit one destruction event, and award loot once. Save logical state; debris is cosmetic. Cap active debris at 40 objects, pool them, and remove after 5 seconds or when offscreen. Default debris cannot damage actors.

Quest-critical objects are explicitly protected or have an authored alternate route. A collapsed bridge must not strand the player without a tested escape. Use pre-authored alternate paths or navigation obstacle toggles before attempting expensive dynamic navigation rebuilding. Saving and loading must preserve broken gates and never respawn their loot.

World architecture: the Sandbox is one scene. Valley is a compact connected region with district scenes and stable IDs. Full-game open-world streaming is a later technical milestone. Store changed world objects as deltas instead of serializing every decorative object. Giant navigation uses profiles and authored clearance corridors; humans and giants do not share identical traversal assumptions. Stages 7-10 require a separate large-scale traversal spike before full-world commitments.

## 12. MIGRATION-FRIENDLY ARCHITECTURE
Keep three practical layers: rules and data; engine adapters; presentation. CombatRules calculates damage, eligibility, costs, and cooldowns from plain values. CombatController owns action state and requests queries. Engine adapters perform collision, movement, navigation, time, input, and storage. Presentation responds to events for animation, audio, effects, camera, and HUD. A scene node may host a system, but node paths must not become permanent save IDs.

Recommended folders: data/abilities, data/growth, data/enemies, scripts/core, scripts/combat, scripts/ai, scripts/adapters, scenes/player, scenes/enemies, scenes/world, ui, assets/source, tests, docs. Do not create an abstract framework for systems that have no second implementation. Keep pure calculations isolated where inexpensive; use Godot naturally for scene composition.

Command flow: InputIntent -> validate -> commit cost/cooldown -> action timeline -> engine collision query -> HitEvent -> DamageResolver -> health/poise/status update -> presentation events -> persistence delta. One subsystem owns resource spending; animation and UI never spend resources independently. Emit AbilityStarted, HitResolved, EntityDied, GrowthChanged, and ObjectDestroyed events with stable IDs and simulation tick.

Data contract examples, with SI units and explicit schema versions:

```json
{"schema_version":1,"id":"ability.light_1","power":40,
 "damage_type":"physical","ability_multiplier":1.0,
 "stamina_cost":8,"cooldown_s":0,"windup_s":0.20,
 "active_s":0.15,"recovery_s":0.30,"poise_damage":12,
 "max_hits_per_target":1,"tags":["Melee","Parryable"]}
```

```json
{"schema_version":1,"id":"growth.01","required_level":1,
 "height_m":3.6576,"capsule_radius_m":0.85,
 "capsule_total_height_m":3.66,"walk_speed_mps":5.0,
 "melee_reach_m":3.5,"camera_distance_m":6.5}
```

Validate duplicate IDs, missing references, negative costs, nonpositive heights, invalid timing, and unknown enum values at project startup. Treat JSON as source content; compile/cache into engine resources if useful. Store save schema version, build version, character ID, level, XP, attributes, growth stage, resources, inventory IDs, ability loadout, quest flags, checkpoint, and world deltas. Save to a temporary file, replace atomically where supported, and keep one previous valid backup. Reject unsupported future versions clearly. Never save raw object pointers or engine instance IDs.

Use unit tests for rules and integration tests for engine behavior. Fixed timesteps and seeded tests improve repeatability, but physics across different engines is not guaranteed deterministic. Reuse expected outcomes and tolerances, not exact engine trajectories.

## 13. PORTABLE ASSETS AND OPTIONAL UNREAL MIGRATION
Keep editable Blender source files, original textures, audio masters, animation source, license records, and export presets. Use a consistent skeleton and named attachment points. Author geometry in meters with applied transforms; include a 1-meter calibration cube and human reference. Export glTF/GLB for Godot [3]. For Unreal, test glTF or FBX import with representative assets; Epic documents its FBX pipeline [4]. Never assume materials, skeleton retargeting, physics, or root motion will import identically.

Prefer simple standard materials: base color, roughness, metallic, and normal textures when needed. Low-poly prototypes can use flat colors. Engine-specific shaders, particle graphs, terrain, animation state machines, navigation, UI layouts, and scene files should be expected to require rebuilding. Audio WAV masters and PNG texture sources are more portable than engine import caches. Track licenses and avoid assets restricted to one engine if migration matters.

| System | Reusable foundation | Unreal work expected |
| --- | --- | --- |
| Balance and progression | JSON/CSV values, IDs, formulas | Import to Data Tables/Assets; validate |
| Character and art | Meshes, skeleton source, textures | Import, materials, collision, retargeting |
| Combat | Rules, tests, action definitions | C++/Blueprint adapters and integration |
| Abilities | Costs, effects, tags, timing | Optional Gameplay Ability System mapping |
| Input / cameras / UI | Bindings and behavior requirements | Enhanced Input, camera, HUD rebuild |
| AI / navigation | States, tactics, encounter data | Behavior Tree/StateTree and nav setup |
| Destruction / world | Object IDs and damage stages | Actor setup; optional Chaos; streaming |
| Saves | Versioned logical schema | Reader/writer and checkpoint mapping |

Use adapters to convert meters to Unreal centimeters (multiply lengths by 100), coordinate axes, rotations, and handedness. Test orientation with the reference cube and a forward arrow. Do not multiply time, damage, or dimensionless values by 100. Preserve IDs and test fixtures. GDScript does not automatically become C++ or Blueprint; even C# would not remove Unreal integration work.

Migration experiment: allocate an estimated 1-2 weeks for an experienced developer after the Valley, not a promise. Port one giant, one enemy, one attack, both cameras, one gate, and one save fixture. Compare feel, build workflow, performance, and implementation effort. Continue only if the benefit is measurable and the team can fund the rewrite. Keep the Godot build and content pipeline working until parity is demonstrated. A full migration can take months depending on content and team experience; no reliable total can be estimated before the spike.

## 14. PROTOTYPE SCOPE AND VALLEY FLOW
Sandbox is 120 x 120 m and lasts 5-10 minutes. Include only the first-delivery requirements in section 1. Its purpose is to prove responsive giant movement, readable attacks, camera usability, and hit correctness. A cube arena with simple silhouettes is enough. Do not block progress on realistic animation.

Valley of Broken Kings is the next milestone, initially about 400 x 400 m, expandable toward 1 km2 only if traversal and performance justify it. This deliberately reduces the earlier 1-2 km2 proposal. Include one ancestry, three growth profiles, five enemy archetypes, eight abilities, three simple weapons, a small village, forest, ruined fortress, boss, checkpoint saves, and a minimal quest/inventory flow. Target 20-30 minutes. No full crafting economy, huge quest tree, or simulated city.

Sequence: awaken in Giant's Hollow and learn both cameras; fight wolves and an ogre in the forest; earn accelerated level 3 and evolve safely to stage 2; learn Boulder Hurl; approach the village and choose a simple intimidation or help objective; reach the ruins and break a practice gate; fight the ogre boss; earn level 5 and stage 3; revisit an earlier obstacle with a tree weapon. Place a shrine at each growth point. Use accelerated quest XP only in this slice and label it as prototype pacing.

Peaceful option: return a stolen supply cache to the village or remove a threatening ogre. Intimidation can cause guards to stand down without granting kill XP. Record the resolution flag so rewards cannot be farmed by repeating dialogue. Death reloads the last checkpoint with its resources and world snapshot; no inventory-loss system in the prototype. Saving during a grab or execution is deferred until a stable state.

Explicitly deferred: multiplayer, all ten playable sizes, dragons with full flight AI, procedural terrain destruction, unrestricted building collapse, hundreds of simulated NPCs, expansive crafting, cinematic dialogue, production-quality assets, and a seamless continent. These remain vision items rather than hidden requirements for Claude's first build.

## 15. MILESTONES AND ACCEPTANCE GATES
Effort estimates assume an experienced solo developer using placeholders and AI assistance; they are planning ranges, not delivery promises. A learner should expect longer. Acceptance gates determine progress, not calendar dates.

| Milestone | Suggested effort | Exit gate |
| --- | --- | --- |
| M0: Setup | 1-2 days | Project opens, arena runs, version pinned, export launches |
| M1: Combat Sandbox | 1-2 weeks | Controls, both cameras, one enemy, damage/defense, breakable work |
| M2: Combat depth | 1-2 weeks | Targeting, three-hit combo, four abilities, two enemy roles |
| M3: Scale proof | 1-2 weeks | Three profiles, safe growth, grab/throw, persistent gate |
| M4: Playable Valley | 3-5 weeks | Complete loop, five roles, eight abilities, boss, save/load |
| M5: Test and tune | 1-2 weeks | Usability, performance, controller, stability gates pass |
| Optional engine spike | 1-2 weeks | Representative Unreal port measured against Godot |

Minimum first-delivery pass: launch without missing dependencies; move and attack; switch perspective; fight one enemy; block/parry/dodge; die and reset; break a fence. No crashes in a 10-minute run. Inputs produce feedback on the next eligible physics tick. If runtime execution is unavailable, mark every runtime gate unverified and supply steps for the user to test locally.

Combat correctness: the worked damage example returns 37 unblocked and 9 blocked; stamina never drops below zero; one sweep intersecting three colliders on one enemy causes one hit; two enemies each receive one hit; walls stop attacks; 100 consecutive activations charge cost and cooldown once each. Test just before, during, and after dodge/parry boundaries. Queue requests expire after 0.15 seconds. Releasing lock on death never leaves a stale target.

Camera and growth: complete a fixed obstacle route in all three sizes and both modes; no persistent camera penetration or obscured crosshair; no invalid spawn after growth; blocked growth leaves all old parameters intact. Camera switches preserve position, resources, target identity, and attack timing. Test narrow doors, slopes, ceiling clearance, and a nearby wall. First-person testing must include downward attacks against humans.

Ability/AI/world: invalid grabs spend nothing; interrupted grabs release both entities; cooldowns prevent repeated activation; target death during casting is handled; fleeing enemies have a reachable destination. Boss phases occur exactly once. Save/load restores character, loadout, quest flags, and gate state; destroyed objects never award loot twice. Corrupt the newest save and verify backup recovery with a clear message.

## 16. PERFORMANCE, PLAYTESTS, AND HANDOFF
Select and record a real reference PC at M0; the user's hardware is currently unknown. Initial target: 1080p low settings and 60 FPS. Measure a standalone exported build, not just the editor. Use a five-minute scripted stress route with 12 active combatants, 20 breakables, and at most 40 cosmetic debris bodies. Target 95th-percentile frame time at or below 16.7 ms and 99th percentile below 33.3 ms, excluding documented loading screens. These are goals, not measured results.

Start with simple lighting, modest shadow distance, shared materials, pooled projectiles/effects, and reduced AI update frequency at distance. Avoid per-frame scene-wide searches. Set a visible active-enemy budget before increasing map size. Profile CPU physics/AI and GPU rendering separately. Maintain a low-detail background representation for distant actors. Do not hide poor performance by deleting essential gameplay behavior.

Usability gate: ask at least three new players to complete the Sandbox. At least two should complete the tutorial encounter without developer intervention and correctly identify heavy attacks, blocking, and dodge timing. Record confusion, camera discomfort, accidental ability use, and time to defeat. Run a 30-minute Valley session with no crash, softlock, duplicated rewards, or unrecoverable targeting state. Fix recurring failures before adding content.

Claude's handoff for every milestone must include: changed files and runnable project; exact engine version; launch/export instructions; controls; implemented versus deferred features; test results with measured evidence where available; known bugs; next smallest milestone. Keep a debug panel for state, stage, stamina, attack ID, target, frame time, and AI state. Disable debug cheats in ordinary exported play mode.

Definition of success: the player can feel the difference between a small giant and a larger giant in one enjoyable, stable, low-graphics loop. A large feature list or generated code volume is not acceptance evidence. Keep working in the chosen engine while it serves that goal.

## 17. SOURCE NOTES AND VERIFIED ENGINE REFERENCES
This specification consolidates the referenced ChatGPT conversation, titled 'Washer Not Spinning Troubleshooting' but containing the Giantborn design: conversation ID 6ae0e2ea-7860-83e9-827f-bb0910730d66. The retrieved material included the game pitch, hybrid combat design, selected camera/difficulty/destruction decisions, growth table, UE5 technical design, and prototype roadmap. The final technical message was capped by the retrieval service; its closing first-implementation list was incomplete. This handoff does not claim a verbatim reproduction of that missing tail.

Updated decisions: Godot/GDScript first; lower initial graphics; smaller Sandbox and Valley; Unreal optional; explicit Claude build prompt; implementation details filled in as proposed defaults. The original ten heights, 20-level structure, four resources, eight-slot hotbar, hybrid combat identity, and selective destruction are preserved. The prior UE-specific architecture is translated into neutral responsibilities, with an optional future Unreal mapping.

Official technical references checked November 4, 2026. Engine recommendations and effort estimates are design judgments; the following sources support engine capabilities and license information, not game balance or delivery timelines.

[1] Godot license: https://godotengine.org/license/

[2] Godot renderer overview: https://docs.godotengine.org/en/stable/tutorials/rendering/renderers.html

[3] Godot 3D import formats: https://docs.godotengine.org/en/stable/tutorials/assets_pipeline/importing_3d_scenes/available_formats.html

[4] Epic FBX content pipeline: https://dev.epicgames.com/documentation/en-us/unreal-engine/fbx-content-pipeline

[5] Unity Editor terms: https://unity.com/legal/editor-terms-of-service/software

[6] Unreal Engine licensing: https://www.unrealengine.com/license

END OF HANDOFF. Give Claude this complete document. Ask it to implement M0 and M1 first, using the START HERE instructions, and to demonstrate a working build before expanding the game.
