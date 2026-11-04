# Architecture

Three practical layers, as the spec asks (section 12): **rules and data**, **engine adapters**
and **presentation**, plus a thin layer of actor scripts that glue them together. Nothing in
presentation or UI spends resources or changes combat state.

```
data/*.json ──► GameData (validate) ──► ActionDef / Combatant
                                              │
input ─► InputRouter ─► intents ─► CombatController (validate → commit cost/cooldown → timeline)
                                              │
                    actor sim_step ─► HitQueryAdapter (sweeps/pulses, occluders first)
                                              │
                                    HitEvent ─► Sim (stable order) ─► CombatEntity
                                              │                         │
                                     DamageResolver (pure)       resources / poise / stagger / death
                                              │
                         Events (AbilityStarted, HitResolved, EntityDied, ObjectDestroyed, …)
                                              │
                 HUD · HitFeedback · CameraRig · ActorRig · WorldState (persistence deltas)
```

## Folders

| Folder | Contents |
| --- | --- |
| `data/` | All tuning and content as JSON (`schema_version`, stable `id`, SI units). |
| `scripts/core/` | Autoloads: `Events` (signals), `GameData` (load + validate), `Settings`, `WorldState`, `Sim` (60 Hz driver). Plus `DataValidator`, `SaveIO`, `JsonIO`. |
| `scripts/combat/` | Pure rules: `CombatRules`, `DamageResolver`, `ResourcePool`, `PoiseMeter`, `InputBuffer`, `Cooldowns`, `HitRegistry`, `TargetingRules`, `LockOnTracker`, `AttackGeometry`, `ActionDef`, `Combatant`, `CombatController`. Engine-facing: `CombatEntity`, `Hurtbox`. |
| `scripts/adapters/` | `HitQueryAdapter` (physics queries), `InputRouter` (contexts, modifiers), `InputBindings` (InputMap from data). |
| `scripts/actors/` | `GiantPlayer`, `SoldierEnemy`, `PracticeDummy`: glue between controller, movement, queries and presentation. |
| `scripts/ai/` | `SoldierBrain` finite-state machine (decides only; the actor senses and moves). |
| `scripts/world/` | `BreakableProp`, `DebrisPool`, `SandboxArena`. |
| `scripts/presentation/` | `CameraRig`, `ActorRig` (procedural animation), `HitFeedback`. |
| `ui/` | `Hud`, `DebugPanel`, `PauseMenu` (settings and rebinding), `UiKit`. |
| `scripts/debug/` | `Autopilot`: seeded bot for soak runs and the screenshot tour (command-line only). |
| `scenes/` | Generated scenes: giant, soldier, dummy, fence, arena, main. |
| `tests/` | `unit/` (pure rules) and `integration/` (real scenes, real physics, real input events). |
| `tools/` | `run_tests.sh`, `build_scenes.tscn` / `.gd`. |
| `assets/` | Materials, shader, and `source/` (empty until real art exists). |

## Simulation tick (Sim autoload, 60 Hz)

1. `tick += 1`.
2. Every registered actor's `sim_step(tick, dt)` runs, in entity-id order:
   - consume input intents (player) or perceive and decide (AI, at 5 Hz / 10 Hz);
   - `controller.begin_tick` advances timelines and may consume the buffered request;
   - new requests are validated and committed;
   - movement (`move_and_slide`);
   - hit queries for active attacks, which queue `HitEvent`s;
   - resource and poise regeneration;
   - lock-on maintenance.
3. Queued hits are sorted (attacker, instance, pulse, sub-step, distance, target) and resolved
   one by one through `CombatEntity.receive_hit` → `DamageResolver.resolve` → apply. Death is
   applied once. Hits from attackers that died earlier in the same pass are dropped.

Presentation (`_process`) reads controller state and never writes it.

## Combat entity contract

A damageable thing is any node with a `CombatEntity` child. The entity gets its stable id from
the actor's exported `entity_id` (or `world_id` for persistent props). The actor may implement:
- `get_defense_state() -> DefenseState` (block, parry, dodge posture);
- `accepts_hit(hit) -> bool` (category and stage permissions);
- `apply_knockback(direction, speed)`;
- `on_entity_died(killer_id)`;
- `flash(strength)`.

Hurtboxes are `Area3D` volumes on physics layer 3. Occluders are layers 1 (world) and
5 (breakables).

## Physics layers

| Layer | Name | Used by |
| --- | --- | --- |
| 1 | world | floor, walls, pillars, arena features; occludes attacks, camera and lock-on visibility |
| 2 | actors | giant, soldiers, dummies (movement blocking only) |
| 3 | hurtboxes | damageable volumes (queried, never collide) |
| 4 | debris | cosmetic pooled debris (collides with world only) |
| 5 | breakables | fence while intact (blocks movement, occludes attacks) |

Render layer 2 (`first_person_hidden`) holds head geometry culled by the first-person camera.

## Adding content

- **A new attack or ability:** add `data/abilities/<name>.json` (copy `light_1.json` or
  `heavy_footfall.json`). Put its id in the player's loadout (`data/player/giant.json`, `slots`).
  The validator reports any missing or invalid field at startup.
- **A new enemy type:** add `data/enemies/<name>.json`, then a scene like
  `scenes/enemies/soldier.tscn` with a `CombatEntity`, hurtboxes and a brain.
- **A new breakable:** add `data/props/<name>.json` and a scene with a `BreakableProp` root, a
  `BlockShape`, `Intact`/`Broken` children and a unique `world_id`.

## Determinism and tests

- Fixed ticks, a seeded `Sim.rng` (reseeded for every test), and stable iteration and hit order.
- Run with `--fixed-fps 60` for exact tick stepping in tests and soak runs.
- Unit tests cover pure rules. Integration tests spawn the real scenes and drive the real
  input path (`InputRouter` injection, plus real `InputEvent`s for routing and contexts).
  Expected outcomes are checked with tolerances, not exact trajectories.
