# M0 + M1 handoff: combat sandbox

Spec section 16 lists what every milestone handoff must contain: changed files, exact engine
version, launch/export instructions, controls, implemented versus deferred features, test
results with evidence, known bugs, and the next smallest milestone. This document provides
each of them.

## 1. Engine and environment

| Item | Value |
| --- | --- |
| Engine | **Godot 4.6.3-stable, official build `7d41c59c4`** (Linux x86_64 binary SHA-256 `f64d4ed1…bfeb3`) |
| Renderer / physics | Compatibility (OpenGL 3.3+), Jolt Physics, 60 physics ticks per second |
| Where it was built and tested | A Linux cloud container: headless runs, plus real rendering through Xvfb and Mesa llvmpipe (a **software** GPU, so its frame rates mean nothing) |
| Not available here | A Windows PC, a real GPU, a gamepad, human playtesters |

**What was actually run** (not just code-reviewed): the unit and integration test suites, a
10-minute simulated play session, rendered screenshot tours from both the editor build and the
exported release build, the Linux export (run headless and rendered), and the Windows export
(produced, but **not run**, since there is no Windows here).

## 2. How to run, controls, export

See [README.md](../README.md): sections 2 (run), 3 (controls), 5 (tests and soak), 6 (export)
and 9 (manual checklist).

## 3. Implemented (M0 + M1 first delivery)

| Requirement (spec section 1 / M1) | Status |
| --- | --- |
| 120 × 120 m arena | Done. Walls, pillars, doorway (2.6 × 5 m), low arch (4.2 m), 20° ramp and platform, wall-test lane, signs. |
| 12-ft giant (stage-1 profile from data) | Done. 3.6576 m, capsule 0.85 / 3.66 m, 5 m/s walk, 3.5 m reach. |
| One melee enemy | Done. Soldier with a 10-state FSM, 5 Hz perception, 10 Hz decisions, navmesh, attack tokens, two telegraphed attacks. |
| Practice dummy | Done. Armor 25, never dies, refills its health. |
| One breakable fence | Done. Category and stage permissions, broken mesh, blocking collision removed, one destruction event, loot once by world id, pooled debris (40 max, 5 s / off-screen cleanup). |
| Both camera modes | Done. Third person: collision-swept arm, shoulder offset, zoom. First person: eye at 92%, head hidden. Switching never touches gameplay state. |
| Movement | Done. Walk, sprint (8 stamina/s), jump, camera-relative or target-relative steering. |
| Light / heavy attacks | Done. Three-hit light chain (1.0 / 1.1 / 1.25), heavy ×1.8, data-driven timings, swept weapon capsule, one hit per entity. |
| Block / parry / dodge | Done. 120° block, parry window 0.20 s, guard break, dodge invulnerability 0.10–0.30 s. |
| Health / stamina (plus essence and fury) | Done. All four resources, regeneration rules, fury gains and decay. |
| Optional lock-on | Done. Q scoring, 35 m / 60°, release rules, directional switching with debounce, side-orbit framing for small targets. |
| Debug reset | Done. F5 in debug builds; "Restart sandbox" in the pause menu; Enter after defeat. |
| Heavy Footfall (after basic combat worked) | Done. Slot 1: 20 stamina, 8 s cooldown, 3 m radius, P=40 ×1.2, 25 poise, blocked by walls. |
| HUD, hotbar, messages, death screen, F1 controls overlay | Done |
| Debug panel (state, stage, stamina, attack id, target, frame time, AI state) | Done (F3, debug builds only) |
| Settings and remapping | Done. Every action remappable (keyboard/mouse and controller columns), hold/toggle sprint and lock-on, sensitivity, FOV, shake/bob/flash, vibration, aim assist. Saved with backup recovery. |
| Data-driven content with startup validation | Done. 23 JSON records with schema_version and stable ids; every listed validation category, plus unknown keys. |
| Export presets (Windows, Linux) | Done. Debug cheats are off in release builds. |

**Deferred (roadmap, deliberately not built):** growth stages 2–3 (data exists, no shrine or
switching), grabs and throws, abilities 2–8 and Titan Surge, character/world save files and
checkpoints (only the settings file uses the save system so far), more enemy archetypes, Valley
content, sound, real art, physics interpolation, and real-hardware performance tuning.

## 4. Acceptance checks

Legend: **PASS** = verified by running the game or engine in this environment.
**NOT RUN** = needs hardware or people that are not available here. **PARTIAL** = verified
here, but part of it can only be confirmed on your PC.

### M0 exit gate
| Check | Result | Evidence |
| --- | --- | --- |
| Project opens / imports | PASS | `godot --headless --import` with no errors; every scene loads in the test runs |
| Arena runs | PASS | Headless and rendered (Xvfb) runs; screenshots |
| Version pinned | PASS | 4.6.3-stable recorded in `project.godot`, README and here |
| Export launches | PARTIAL | The Linux release export ran headless (120 s autopilot, no errors) and rendered (screenshot tour). The Windows `.exe` exported successfully but **was not launched** (no Windows here). |
| Reference PC recorded | NOT RUN | Your hardware is unknown. Please record CPU, GPU, RAM and OS in this table after your first run. |

### First-delivery minimum pass (spec 15)
| Check | Result | Evidence |
| --- | --- | --- |
| Launch without missing dependencies | PASS | Editor build and exported Linux build |
| Move and attack | PASS | Integration tests; screenshot tour |
| Switch perspective | PASS | `test_camera_switch_preserves_state`, first-person tests, screenshots |
| Fight one enemy | PASS | `test_soldier_engages_with_readable_attacks`; soak run (dozens of soldier kills) |
| Block / parry / dodge | PASS | `test_parry_real_soldier_slash`, `test_late_block_is_ordinary_block`, `test_dodge_invulnerability_in_engine`, guard break |
| Die and reset | PASS | `test_player_death_is_final_until_reset`; the soak run reset the sandbox repeatedly through the same reload path |
| Break a fence | PASS | `test_fence_breaks_once_and_loot_once`; screenshot |
| No crashes in a 10-minute run | PASS | 600 simulated seconds (36,001 ticks) of autopilot play, exit 0, **zero** errors or warnings |
| Inputs give feedback on the next physics tick | PASS | `test_input_feedback_on_next_tick` |

### Combat correctness
| Check | Result | Evidence |
| --- | --- | --- |
| Worked example: 37 unblocked, 9 blocked (10 impact stamina), heavy 66 | PASS | Unit tests; in-engine on the dummy (light 37, heavy 66); the screenshot shows **66** |
| Stamina never below zero | PASS | 20,000-operation randomized unit test; 600-tick in-engine exhaustion test |
| One sweep over three colliders on one enemy = one hit | PASS | `test_one_sweep_three_hurtboxes_one_hit` (the query really overlaps head, torso and legs) |
| Two enemies each receive one hit | PASS | `test_two_enemies_each_hit_once` (and fury +4 only once) |
| Walls stop attacks | PASS | `test_wall_stops_attack` (control swing hits; walled swing does not, and reports a clank) |
| 100 consecutive activations charge cost and cooldown once each | PASS | `test_hundred_activations_charge_once_each` (2,000 stamina exactly, 100 starts, spam spends nothing) |
| Dodge and parry boundaries (just before, during, just after) | PASS | Unit tests (ticks 5/6/17/18 and 11/12) and in-engine dodge boundaries |
| Queue expires after 0.15 s | PASS | `test_input_buffer_expires_after_015s` (consumed at 9 ticks, expired at 10) |
| Releasing lock on death never leaves a stale target | PASS | `test_lock_releases_on_death_same_tick` (same tick, no re-acquisition) |

### Camera (stage 1; three sizes are M3)
| Check | Result | Evidence |
| --- | --- | --- |
| Fixed obstacle route in both modes (narrow door, ceiling clearance, slope, nearby wall) | PASS (stage 1) | `test_route_third_person`, `test_route_first_person`: every waypoint reached, **0** ticks with the camera inside geometry |
| No persistent camera penetration | PASS | The same route test, plus `test_third_person_camera_does_not_enter_wall` |
| Crosshair not obscured | PARTIAL | HUD crosshair verified in screenshots. Lock-on side-orbit added after screenshots showed the giant hiding small targets. Judging comfort needs human playtests. |
| Camera switch preserves position, resources, target and attack timing | PASS | `test_camera_switch_preserves_state` |
| First-person downward attacks against humans | PASS | `test_first_person_downward_attacks_hit_a_human` (three-hit chain and heavy) |
| Three sizes, growth spawn checks | NOT IN SCOPE | M3 |

### Ability / AI / world (M1 subset)
| Check | Result | Evidence |
| --- | --- | --- |
| Cooldowns prevent repeated activation | PASS | Unit and integration Footfall tests |
| Destroyed objects never award loot twice (including after reload) | PASS | Fence test, which re-instantiates with the same world id |
| Corrupt newest save → backup recovery with a clear message | PASS (settings file) | `test_save_roundtrip_and_backup_recovery`, `test_future_version_rejected_clearly` |
| Enemy windups ≥ 0.45 s (major ≥ 0.8 s), no rotation after commit | PASS | Data check plus `test_soldier_engages_with_readable_attacks` |
| ≤ 2 melee attack tokens | PASS | `test_attack_tokens_limit_attackers` (3 soldiers) |
| Grabs, boss phases, save/load of character and gates | NOT IN SCOPE | M3 / M4 |

### Performance and usability (spec 16)
| Check | Result | Notes |
| --- | --- | --- |
| 60 FPS at 1080p low on the reference PC (p95 ≤ 16.7 ms, p99 < 33.3 ms) | NOT RUN | No real GPU here. Run `Giantborn.console.exe -- --no-user-settings --autoplay=300` on your PC; it prints `frame_ms_p95` / `p99`. The F3 panel shows them live. |
| Five-minute stress route (12 combatants, 20 breakables) | NOT RUN | M5 item; needs content that does not exist yet |
| Three-new-player usability gate | NOT RUN | Needs people; README section 9 is the script to give them |
| Controller feel and vibration | NOT RUN | No gamepad here. Routing of every combo is tested with synthetic joypad events. |

## 5. Test evidence

Command: `tools/run_tests.sh` (headless, `--fixed-fps 60`).

```
RESULT: 12 suites, 1070 checks, 0 failures
```
- 6 unit suites: rules, resolver, controller, resources/poise, targeting/registry/geometry,
  data/saves.
- 6 integration suites with real scenes and physics: hits, defense, targeting/camera,
  world/flow/AI/input, obstacle route, first-person combat.

The 10-minute soak (`--autoplay=600`, seeded) result line:
```
{"attacks":209,"heavies":45,"blocks":60,"dodges":44,"footfalls":33,"jumps":13,"lock_presses":32,
 "camera_toggles":14,"fence_breaks":13,"soldier_kills":19,"resets":19,"hits_resolved":168,
 "max_debris":8,"simulated_s":600.02,"ticks":36001}   # zero errors or warnings in the log
```

## 6. Bugs found while testing (all fixed)

- HUD invisible: Godot 4's `set_anchors_preset` keeps the old rect. Now `set_anchors_and_offsets_preset`.
- Event listeners leaked across sandbox resets (lambdas that do not capture `self` outlive their
  node), double-counting events. Now method callables.
- "NavigationMesh is already baking" after resets: the navmesh resource was shared between scene
  instances. Now duplicated per instance.
- The giant's body hid small, close targets from the lock-on camera (seen in screenshots). Fixed
  with the side orbit.
- The heavy overhead slam came down 0.8 m right of a human standing in front of the giant (found
  by the first-person test). The slam now angles inward.
- With no navmesh, soldiers could not move. They now steer directly when there is no path data.

## 7. Known limitations

See [README.md § 8](../README.md#8-known-limitations).

## 8. Next smallest milestone

**M2, combat depth:**
- three more abilities (Sweeping Blow, Stone Skin, Runic Bolt) plus Titan Surge;
- a second enemy role (wolf: flanking lunges, so dodge-then-punish matters);
- target-switching polish on groups;
- the first three-person usability test.

Before M2, run the game on your PC: confirm Windows launch and gamepad feel, and record the
reference PC and frame times in section 4.
