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
| Fight one enemy | PASS | `test_soldier_engages_with_readable_attacks`, `test_soldier_guard_blocks_front_flank_and_heavy_break_it`; soak run (17 soldier kills) |
| Block / parry / dodge | PASS | `test_parry_real_soldier_slash`, `test_late_block_is_ordinary_block`, `test_dodge_invulnerability_in_engine`, guard break |
| Die and reset | PASS | `test_player_death_is_final_until_reset`; the soak run reset the sandbox repeatedly through the same reload path |
| Break a fence | PASS | `test_fence_breaks_once_and_loot_once`; screenshot |
| No crashes in a 10-minute run | PASS | 600 simulated seconds (36,001 ticks) of autopilot play on the final code, exit 0, **zero** errors or warnings |
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
| Fixed obstacle route in both modes (narrow door, ceiling clearance, slope, nearby wall) | PASS (stage 1) | `test_route_third_person`, `test_route_first_person`: every waypoint reached, **0** ticks with the camera inside geometry; `test_follow_arm_stays_long_through_a_doorway`: the arm never collapses |
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
RESULT: 15 suites, 1133 checks, 0 failures
```
- 7 unit suites: rules, resolver, controller, resources/poise, targeting/registry/geometry,
  data/saves, click-to-capture.
- 8 integration suites with real scenes, physics and input events: hits, defense,
  targeting/camera, world/flow/AI/input, obstacle route, first-person combat, plus two suites
  of regression tests for the review findings.
- The runner installs an engine `Logger`: any script or engine error during a test fails that
  test (verified with a deliberately crashing probe). It also always isolates the player's
  settings file.

The 10-minute soak (`--autoplay=600`, seeded, current code) result line:
```
{"attacks":247,"heavies":56,"blocks":67,"parries":2,"dodges":48,"footfalls":38,"jumps":12,
 "lock_presses":34,"camera_toggles":16,"fence_breaks":11,"soldier_kills":17,"resets":17,
 "hits_resolved":195,"max_debris":8,"simulated_s":600.02,"ticks":36001}   # 0 errors, 0 warnings
```

## 5b. Independent review

After the first complete build, five independent reviewers each checked one area of the spec:
combat rules, input and the action state machine, camera and targeting, AI/world/data, and
engine robustness. A separate skeptical verifier then tried to refute each finding, often by
re-running the scenario in the engine. Of the 22 findings, every one was real, and every one is
fixed with a regression test. The verifiers then re-checked the fixed code in the engine,
including real X11 window events for the mouse-sensitivity and window-close cases. They
confirmed 21 fixes. For the 22nd (right-stick target switching in first-person lock), they
showed my first fix was incomplete: a fast push that was then held still switched. It now
switches only on a flick-and-release ("tap").

| Area | Findings (all fixed) |
| --- | --- |
| Combat rules | Unblockable wrongly implied unparryable; dodged hits did not count as combat (fury decayed mid-fight) |
| Input / state machine | Hold-mode lock stuck after a release during pause; a held block never resumed; controller combos were hard-coded (not remappable) |
| Camera / targeting | Follow arm collapsed to 0 m at door jambs and walls; the giant's chest hid humans in first person; the block faced the movement direction, not the aim; first-person stick look switched targets; switching failed with the target behind the camera; the lock marker was a frame late |
| AI / world / data | The soldier tracked a hidden giant's live position; the soldier did not "guard the front" (spec 10); one bad saved binding unbound an action; ids used by scenes were not validated; a breakable that loaded destroyed stayed in the navmesh; a newer-version file could overwrite the good backup; immunity names were unchecked |
| Engine robustness | Mouse sensitivity depended on window size; keyboard slider changes were lost on quit; the test runner could pass a crashing test; running tests could wipe the player's bindings |

## 5c. Browser build (play link)

The play link (README, "Browser build") is the single-threaded Web export, published as a
claude.ai Artifact with `web/launcher.html` as the page. Tested locally in Playwright Chromium
with a software GPU, serving the exact files that were published:

| Check | Result | Evidence |
| --- | --- | --- |
| Loads the packed engine and data, then boots to the arena | PASS | 12.3 MB downloaded and unpacked; arena and HUD up 3.1 s after Play; no console errors |
| Click takes the mouse; Esc gives it back and opens the pause menu; Resume takes it again | PASS | Headed Chromium on a virtual display: pointer lock on, off, on |
| V switches camera, H shows the controls (with the browser note), pause menu has no Quit | PASS | Screenshots of each state |
| A host that forbids WebAssembly gets a plain message and the exact error to copy | PASS | Simulated with a strict Content-Security-Policy |
| Phone width: the page fits with no sideways scroll and says to use a computer | PASS | 390 px viewport |
| Runs inside the claude.ai Artifact frame | NOT RUN | Can only be checked by opening the link |
| Real browsers (Chrome, Edge, Firefox, Safari on a real GPU); gamepad inside the frame | NOT RUN | Needs a real computer |

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
- The 22 review findings in section 5b.
- Clicking the game did not take the mouse back. The input router consumed the click as an
  attack before `main.gd` saw it. On desktop this was hidden, because the mouse is captured at
  startup and when menus close; the browser build depends on that click, since browsers grant
  pointer lock only inside one. Found by the headed-browser test. `main.gd` now takes the click
  in `_input` (unit checks in `test_mouse_capture`), and that click no longer also swings.

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
