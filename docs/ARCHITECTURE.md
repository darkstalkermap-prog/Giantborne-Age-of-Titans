# Architecture

How the Valley build is put together: the layers, the autoloads and the simulation tick, each area
of the game, the tools and the tests. It consolidates the system docs of the 21 M2-M5 packages
(`docs/systems/P01.md` ... `P18.md`, which keep every public API and detail); the interpretations
behind it are in [DECISIONS.md](DECISIONS.md).

## 1. Layers

Three practical layers, as the spec asks (section 12): **rules and data**, **engine adapters** and
**presentation**, plus actor scripts that glue them together. Nothing in presentation or UI spends
resources or changes combat state; listeners of `Events` never do either.

```
data/**/*.json ──► GameData (schema registry, validation, post-pass) ──► ActionDef / StatusDef / records
                                                   │
 input ─► InputRouter ─► intents ─► GiantPlayer components ─► CombatController (validate → commit → timeline)
 AI ─► EnemyBrain (perceive / decide) ─► EnemyActor ─────────────┘           │
                                                   AttackRunner (arcs, pulses, sectors, projectiles, grabs)
                                                                             │
                              HitFactory ─► HitEvent ─► Sim (stable order) ─► CombatEntity ─► DamageResolver (pure)
                                                                             │
       Events (≈70 signals: hits, deaths, statuses, telegraphs, quests, saves, screens, ...)
                                                                             │
   Quests · GameSession (checkpoints) · EncounterDirector · FactionState · HUD widgets · HitFeedback ·
   TelegraphVisuals · CameraRig · ActorRig · WorldState (flags, deltas, inventory) · the Valley bot
```

## 2. Autoloads and the tick

Autoloads, in order (`project.godot`): `Events` (every signal, declared up front with one anchor
per package), `GameData` (loads and validates `data/`), `Settings`, `WorldState` (flags, world
deltas, inventory; save format v2), `GameSession` (modes, character state, checkpoints, saves),
`Quests` (quests, dialogue, tutorial prompts, the end of the slice) and `Sim` (the 60 Hz driver).

`Sim.step()`, once per physics tick:

1. `tick += 1`.
2. **PRE_ACTORS hooks**: the EncounterDirector's activation, leash and AI LOD (order 10).
3. **Actors** in entity-id order: the player's `sim_step` (input edges offered to its components,
   movement, hit queries) and each enemy's (perceive at 5 Hz, decide at 10 Hz, scripted motion,
   steering, hit queries); props and dummies.
4. **POST_ACTORS hooks**: the ProjectileSystem (order 100) moves projectiles and thrown bodies.
5. **Hit resolution** in a stable order (attacker, instance, pulse, sub-step, distance, target);
   hits from an attacker that died earlier in the pass are dropped unless they come from a
   projectile.
6. **The status pass**: every entity ticks its statuses (expiry, healing over time).
7. **POST_RESOLVE hooks**: shrine activation (50), Quests (100), FactionState (150), GameSession's
   deferred checkpoint (200).

Randomness: crits use the seeded `Sim.rng` in hit order (pinned by the worked-example tests); every
other consumer (loot, AI picks, the bot) draws from its own `Sim.rng_for("<stream>")`. Launch slots
(`request_launch_slot`) space ranged launches at a target. Presentation runs in `_process` and only
reads state.

## 3. Data and validation

- `data/` holds every number and every piece of content as one JSON record per file
  (`schema_version`, a dotted `id`, SI units): 152 records in 18 folders - abilities and actions,
  statuses, the player and growth profiles, enemies, NPCs, props, weapons, items, loot tables,
  shrines, the progression table, quests, dialogue, tutorial prompts, levels and encounters, input
  bindings.
- `DataValidator` (`scripts/core/data_validator.gd`) holds the shared enums and an optional
  **schema registry**: one module per record type in `scripts/core/schemas/` (`fields()`,
  `semantic()`, `required_ids()`), loaded only when its file exists. Unknown keys are errors; ticks
  that are not whole warn; references are checked by type.
- `GameData` merges every module's required ids, runs a **post-pass** for rules that span records
  (an untelegraphed long enemy windup, duplicate spawn ids, encounter definitions, the forge's
  upgrade rule, the progression table), and offers `override_record` / `restore_record` for tests.
  Any error stops the game at a screen that lists them all.

## 4. Combat core (`scripts/combat/`)

- `CombatController`: the action state machine (locomotion, attacking, casting, executing, blocking,
  dodging, staggered, grabbed, dead), costs and cooldowns, the 0.15 s input buffer, level and stage
  gating (`preview_reason` gives the HUD the same answer a request would get), `force_action` for
  scripted follow-ups (the boss's roar and wall recovery), super armour through windup and active.
- `Combatant`, `ResourcePool` (health, stamina, essence, fury; rescaled on growth), `PoiseMeter`
  (recovery punish multiplier, longer stagger against a twice-taller attacker), and statuses
  (`StatusDef`, `StatusSet`: refresh, strongest-wins or independent stacking; armour, slow, damage
  and fury modifiers; healing over time).
- `CombatEntity` (on every damageable node): receives hits through `DamageResolver` (pure; spec §7
  formulas), applies on-hit statuses and morale damage, emits the events, carries the faction and
  the lock anchors.
- `HitFactory` / `AttackContext`: the one place that builds a `HitEvent` for every source (weapon
  multiplier, attributes, size, crits, statuses, area-effect flag). `skip_candidate` keeps the
  player's area effects off neutral villagers.
- `AttackRunner` (`scripts/actors/attack_runner.gd`): dispatches an action's hit shape -
  `weapon_arc` (a swept capsule along the arm and weapon), `cylinder_pulse`, `sector_pulse`,
  `projectile`, `grab`, `body_sweep` (the boss's charge) - and self statuses.
- `ProjectileSystem` (one per level): exact ballistic steps, a sphere cast against the world, a
  swept sphere against hurtboxes, splash, committed aim points, thrown bodies.
- `TargetingRules` / `LockOnTracker`: lockable means team ENEMY or faction-less NEUTRAL; the lock
  keeps the best target in a horizontal cone and range that grow with the stage.

## 5. The giant (`scripts/actors/giant_player.gd`, `scripts/actors/player/`)

`GiantPlayer` is glue over a registry of `PlayerComponent`s, each with hooks for input edges,
pre-action logic, post-movement work, saves, the rig and the debug panel:

| Component | Owns |
| --- | --- |
| `PlayerMotor` | Walk, sprint, facing, dodge burst, knockback, speed multipliers |
| `PlayerTargeting` | Hard lock, soft target, switching, lock anchors |
| `PlayerAttack` | Weapon geometry (scaled by stage and weapon fit), the vertical aim, launch points and aims, hit queries through AttackRunner |
| `PlayerInteract` | The E candidate (shrines, NPCs, pickups, racks, forges, grabs) and its prompt |
| `PlayerGrowth` | Stages 1-3: checks (clearance, combat, flags), applying a growth in one tick (capsule, resources, nav layers, weapon, camera, rig), debug grow and shrink |
| `PlayerEquipment` | Owned weapons, equipping, the fit cap and the "too small" warning, the weapon mesh |
| `PlayerGrab` | Grab, hold, throw, put down, Crushing Grip, every release path |
| `PlayerProgression` | XP, levels, attributes, ability learning and auto-slotting, kill loot |

`apply_character_state` / `capture_character_state` move the whole character (stage, level, XP,
attributes, loadout, weapons, resources) in and out of the save document.

## 6. Enemies and NPCs (`scripts/actors/`, `scripts/ai/`)

- `EnemyActor` (a `CharacterBody3D`) senses, moves (navigation agent on the record's nav layers,
  scripted lunges and charges), runs its `AttackRunner`, announces telegraphs, takes attack tokens
  (2 melee, 2 ranged per target), switches AI LOD tiers (tier 2 sleeps behind a one-box proxy),
  handles morale, flight and rout, grabs, the leash return, factions and awe.
- `EnemyBrain` (pure state machine): IDLE, PATROL, ALERT, APPROACH, ATTACK, RECOVER, REPOSITION,
  FLEE, STAGGERED, DEAD, HOLD, STAND_DOWN, RETURN, ROUTED; outmatched tactics (formation and brace,
  harass, spread, kite); boss phases and attack sequences.
- Archetypes: `SoldierEnemy` (frontal guard, brace), `WolfEnemy` (lunge, flank, harass;
  `QuadrupedRig`), `ArcherEnemy` (elevation and cover, committed shots), `MageEnemy` (slowing bolt,
  barrier on an ally, kiting), `OgreEnemy` (super-armoured smash and sweep, a long punish window),
  `OgreBoss` (the Ogre King: two phases, combo, slam, wall charge), `SparringPost` (the tutorial's
  practice target), `Civilian` (flees to reachable shelters; the elder talks).
- `FactionState` turns blows on village members into warnings and hostility and stands the guards
  down on intimidation (flags in `WorldState`).

## 7. The world and the Valley (`scripts/world/`)

- **Levels.** `LevelRoot` (the root of the Valley and the test levels) names its `level` record and
  answers lookups: markers, checkpoints, area triggers, patrol routes, districts, nav regions; it
  applies the record's graphics presets and the web overrides. `AreaTrigger` reports the player
  entering named areas; `LevelMarker`s are objective, cover, elevation, formation, safe, patrol and
  bot-route points.
- **Encounters.** `EncounterDirector` spawns `encounter` records near the player (scenes preloaded
  with the level, at most 2 spawns a tick), persists kills, despawns far unengaged members, keeps
  the 12-combatant budget, sets AI LOD tiers by distance, leashes, alerts groups and clears
  encounters. `BossArena` closes the Kingsfall gate behind the giant and opens it at the King's
  death.
- **The Valley** (`scenes/world/valley.tscn`, 400 x 400 m) is generated from
  `tools/data/valley_layout.json` by `tools/builders/valley.gd`: eight district sub-scenes (collision,
  blockers, MultiMesh visuals, scenery), four offline navmeshes in `assets/nav/` (human 1, large 2,
  giant 4, small giant 8), props, shrines, waystones, forges, markers, triggers, patrol routes and
  the boss arena.
- **Props.** `BreakableProp` covers breakable and structural props (damage stages, saved health,
  debris layouts, nav links that open, locked messages, XP, flags, loot tables); `CosmeticProp` and
  `CosmeticField` (batched bushes, banners, barley) only react. `DebrisPool` caps debris at 40.
- **Interactables.** `Interactable` and its subclasses: `Shrine` (activation, Rest, growth, the
  loadout and attributes), `Waystone` (checkpoint), `Forge` (the reforge), `UprootTree` (the tree
  weapon), `WeaponRack`, `ItemPickup` (the supply cache, the crown) and `NpcTalker` (the elder).

## 8. Quests, dialogue and tutorials (`scripts/quests/`)

`Quests` runs data-driven quests whose stages complete on world state (kills, flags, destroyed
props, items, stage, level, areas entered), grants once-only rewards, offers objectives (with the
bot's hint) to the HUD and the bot, hosts the `DialogueSession` (entry nodes, visible choices,
once-gated rewards) and the `TutorialDirector` (one prompt at a time; a lesson stays open after its
prompt times out), and emits `slice_completed` at the crown. `QuestConditions` is the pure evaluator
of the condition shapes; `TutorialText` resolves `{placeholders}` for the last device used.

## 9. Session, saves and checkpoints

`GameSession` owns the mode (title, sandbox, Valley), New Game and Continue, the live character
state and the checkpoint document: requests from shrines, waystones, growth, the boss and quest
stages are taken in POST_RESOLVE when nothing blocks them (dead, grabbed, holding, a screen open,
an aware enemy within 40 m). `SaveSlots` writes the one slot (`user://saves/valley_1.json`) through
`SaveIO` (temp file, verify, backup, replace; backup recovery; newer versions kept aside).
`CharacterState` builds, normalises and validates the character. Every mode change, reset and
reload is a reload of `scenes/main.tscn`; `main.gd` builds the level, HUD, screen stack and debug
panel, then calls `GameSession.on_level_ready`.

## 10. UI (`ui/`)

- `Hud` with a registry of `HudWidget`s: interact prompt, status row, checkpoint toast, XP bar,
  ability notice, boss bar, quest tracker, tutorial prompt, objective marker and threat arrows (the
  last two draw over every panel and keep clear of them along the screen edge). The layout test
  checks every region at five resolutions.
- `ScreenStack` and `UiScreen`s: pause (Settings, Controls), title, shrine (Rest, Grow, Loadout,
  Attributes tabs), dialogue, inventory, attributes, forge, end. A pausing screen pauses the tree
  and switches input to the menu context. `UiNav` wires focus for pad and keyboard with wrap-around.
- `InputRouter` (contexts, modifiers, injection for bots and tests) and `InputBindings` (the InputMap
  from data, user overrides, last-device glyphs).
- `DebugPanel` (F3, debug builds): state, stage, stamina, attack id, target, frame time, AI state,
  and the lines of every `debug_info_providers` node.

## 11. Presentation (`scripts/presentation/`)

`CameraRig` (third and first person, collision-swept arm scaled by stage, lock framing, head
culling), `ActorRig` and `QuadrupedRig` (procedural poses that read the same `AttackGeometry` as
the hit sweep, status tints, hold and throw poses), `HitFeedback` (numbers, sparks, rings, sector
fans), `TelegraphVisuals` (filling decals and aim lines), `WeaponVisuals` (low-poly weapon meshes).
Materials are flat colours; there is no audio.

## 12. Physics, render and navigation layers; groups

| Physics layer (value) | Name | Used by |
| --- | --- | --- |
| 1 (1) | world | Terrain, walls, cliffs, houses, pillars; occludes attacks, camera and sight |
| 2 (2) | actors | Player, enemies, NPCs, dummies |
| 3 (4) | hurtboxes | Damageable volumes (queried, never collide) |
| 4 (8) | debris | Pooled debris (collides with the world only) |
| 5 (16) | breakables | Intact breakables; block movement, attacks and enemy sight |
| 6 (32) | blockers | Invisible movement walls (river banks, bridge rails); actors only (`ACTOR_MASK` 51) |

Render layer 2 (`first_person_hidden`) holds the head, chest and belt (culled in first person and
when the third-person arm is pressed close) and the tree weapon's canopy. Navigation layers: 1
human (soldiers, archers, mages, wolves, civilians), 2 large (ogres), 4 giant (stages 2-3, the Ogre
King, the bot), 8 small giant (stage 1, with the 4 m alleys). Groups name the things systems look
for: `player`, `enemies`, `breakables`, `interactables`, `checkpoints`, `shrines`, `waystones`,
`level_root`, `encounter_director`, `area_triggers`, the marker kinds, `ranged_enemies`, `bosses`,
`npcs`, `civilians`, `screen_stack`, `debug_info_providers`.

## 13. Scenes and builders

Every scene is generated: `tools/build_scenes.tscn` runs the builders of `tools/builders/` in
dependency order (`player`, `soldier`, `wolf`, `props`, `shrine`, `growth_course`, `test_levels`,
`world_props`, `ranged`, `test_director`, `forge`, `heavy`, `npcs`, `sandbox`, `valley`, `stress`,
`main`); `-- --only=<names>` rebuilds a few. `SceneKit` (`tools/scene_kit.gd`) holds the palette,
the node helpers, the layer constants and `save()`, which strips random ids so a rebuild changes
only what changed, and `merge_meshes` (one mesh per material per prop). Scenes: the giant, seven
enemy and two NPC scenes, the world props, the sandbox arena, the Valley and its districts, and
seven test levels (`scenes/test/`: growth course, flow test, ranged playground, director test, boss
arena, village test, stress arena).

## 14. Debug tools and the bots (`scripts/debug/`, `tools/`)

- `Autopilot` (`--autoplay=S`, `--scenario=...`): the M1 sandbox soak and screenshot tour, and the
  dispatcher for `stress` (`StressScenario`: 12 combatants, 20 breakables, 40 debris), `valley_walk`
  (`ValleyWalk`: every district and the AI LOD comparison) and `valley` (the bot). It prints one
  `AUTOPILOT_RESULT {json}` line; `ErrorCounter` makes any engine or script error a non-zero exit.
- `ValleyBot` + `BotCombat` + `RunMetrics` + `BotDiagnosis`: a goal-driven player of the whole quest
  line under a village policy, novice or expert, optionally assisted; per-segment metrics; the
  watchdogs and the `world_blocked` / `bot_failed` diagnosis; invariants every tick; `--bot-loop`
  for the 30-minute run.
- `PerfProbe`: CPU per tick, frame and render times, draw calls, nodes and memory, with budget
  verdicts (`PERF_RESULT {json}`).
- `tools/`: `gd.sh` (a per-worktree `user://`), `check.sh` (the definition-of-done sequence),
  `run_tests.sh`, `run_bots.sh` (bot batches) and `bot_report.py` (their tables), `build_web.sh`
  (the play link's files), `capture_tour.sh` (the M1 sandbox shots), `valley_tour.gd` (the Valley
  shots), `draw_call_probe.tscn` (the static world's draw calls).

## 15. Tests (`tests/`)

- `tests/unit` (pure objects), `tests/integration` (real scenes, real ticks, real input events) and
  `tests/slow` (the Valley, routes, walkthroughs, stress and bot smoke; only with `--slow`).
- The runner (`tests/run_tests.tscn`) reseeds `Sim`, runs `ResetHooks` around every test (session,
  quests, record overrides, open screens), turns any logged engine or script error into a failure,
  and fails a suite that does not compile. `tests/support/` holds the helpers (`TestWait`,
  `TestSpawn`, `TestFixtures`, `ValleyProbe`, `CrosshairProbe`, quest fixtures, the anchor table).
- `test_anchors` also compiles every script in the project, because `--import` does not.

## 16. Adding content

- **An attack or ability:** a record in `data/abilities/` (copy a similar one); add it to the
  progression library and a slot or a weapon's moveset. The validator reports what is missing.
- **An enemy:** a record in `data/enemies/` (stats, attacks, AI, tactics, nav layers), a builder
  for its scene (or reuse a scene with another `definition`), and an encounter that spawns it.
- **A prop:** a record in `data/props/` and a scene from `tools/builders/world_props.gd`; place it
  in the layout table with a unique `world_id`.
- **A quest stage, dialogue or prompt:** records in `data/quests/`, `data/dialogue/`,
  `data/tutorial/`; markers and triggers in the layout table.
- **The Valley's geometry:** edit `tools/data/valley_layout.json`, then rebuild (`tools/check.sh
  --only=valley`); the navmeshes are re-baked by the builder.

## 17. Determinism

Fixed ticks, seeded streams, stable iteration and hit order. Run tests and bots with
`--fixed-fps 60` for exact stepping; a bot run is repeatable for a seed on one machine, with small
differences across machines (physics), which is why balance is judged over several seeds.
