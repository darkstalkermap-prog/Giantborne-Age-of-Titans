# Brief: UI, scene tools, test framework and autopilot (M2-M5 planning input)

Scope: `ui/*.gd`, `tools/build_scenes.gd` + `tools/*.sh`, `tests/*.gd`, sample suites,
`scripts/debug/autopilot.gd`, plus the parts of `scripts/main.gd` that host the UI. Read against
merged M0+M1 (`e89001f`, 15 suites / 1133 checks, measured wall time 7.0 s, of which
`test_obstacle_route` alone is 2.6 s and `test_world_and_flow_integration` 1.0 s).

## 1. Files and responsibilities

| File | Responsibility |
| --- | --- |
| `ui/hud.gd` (`Hud`, 503 lines) | Whole in-game HUD built in code: 4 resource bars + mode label, 9-slot hotbar (8 + ultimate), loot label, crosshair, capture hint, lock marker, target frame, messages, death overlay, F1 help. Read-only on gameplay. |
| `ui/pause_menu.gd` (`PauseMenu`) | Esc/Start menu: tabs Main / Settings / Controls, rebinding capture, pauses tree and sets `InputRouter.Context.MENU`. |
| `ui/ui_kit.gd` (`UiKit`) | Static helpers + palette: `box`, `label`, `panel`, `bar`, `button`. |
| `ui/debug_panel.gd` (`DebugPanel`) | F3 text panel (debug builds only): tick, frame stats, player/soldier debug info, debris, pending hits. |
| `scripts/main.gd` | Builds `CanvasLayer` (layer 10) with Hud, DebugPanel, PauseMenu; global keys; death restart; reset via `reload_current_scene`; starts Autopilot from CLI flags. |
| `tools/build_scenes.gd` (+ `.tscn`) | Generates every `.tscn` and the materials; run as a scene so autoloads resolve. |
| `tools/run_tests.sh` | `--import` then the headless runner; passes extra args (e.g. `--filter=unit`). |
| `tools/capture_tour.sh` | Runs `--scenario=capture` at 1280x720, under `xvfb-run` when no `$DISPLAY`. |
| `tools/build_web.sh` | Web export, gzip+base64 packing, patches `web/launcher.html` BUILD line, writes `play.html`. |
| `tests/test_runner.gd` (`run_tests.tscn`) | Discovers and runs suites, error logger, prints results, exit code. |
| `tests/test_suite.gd` (`TestSuite`) | Base: asserts, `step_ticks`, `action(id)`. |
| `tests/integration_suite.gd` (`IntegrationSuite`) | Base for engine tests: test world + floor, event capture arrays, spawn helpers, `queue_hit`. |
| `tests/test_error_logger.gd` (`TestErrorLogger`) | `Logger` subclass that collects every non-warning engine/script error. |
| `scripts/debug/autopilot.gd` (`Autopilot`) | Seeded soak bot (`--autoplay=S`) and screenshot tour (`--scenario=capture`). Ships in exports (only `tests/*, tools/*` are excluded). |

## 2. Key classes and APIs

### Hud (`class_name Hud extends Control`)
- `var player: GiantPlayer` - auto-found each `_process` via group `"player"` when null/invalid.
- `func toggle_help()`, `func show_message(text: String, kind := "info")` (kinds `info|warn|bad|good`; same text within 0.6 s is dropped; max 3 lines, `MESSAGE_LIFETIME := 2.6` s, fade over last 0.5 s).
- Builders called in `_ready` (lines 35-41): `_build_resources`, `_build_hotbar`, `_build_center`, `_build_target_frame`, `_build_messages`, `_build_death`, `_build_help`.
- Per-frame (`_process`, line 363): `_update_resources`, `_update_hotbar` -> `_update_slots`, `_update_target`, `_update_messages`, death visibility (`controller.state == DEAD`), capture-hint visibility, loot label from `WorldState.inventory`.
- Subscribes: `Events.hud_message`, `loot_awarded`, `object_destroyed`, `camera_mode_changed`, `Settings.changed` (only `"bindings"` matters -> `_labels_dirty`).
- Slots: `_slots: Array[Dictionary]` with keys `root, cooldown, key, pad, title, cost, timer, reason, index`; index 8 = ultimate. Slot id read every frame from `controller.loadout["slot_%d"]` / `["ultimate"]`, def from `controller.library`. Cost text from `ActionDef.stamina_cost/essence_cost/fury_cost` ("20 STA"), cooldown overlay from `controller.cooldowns.remaining_s/remaining_fraction(def.id, Sim.tick)`. Unavailable reason (lines 435-450), in order: `Dead`, `Stage N` (`def.unlock_stage > c.growth_stage`), `Cooldown`, `Stamina`, `Essence`, `Fury`, `Busy` (`c.is_committed()`). Empty slot: 45% alpha, "ULT" title on slot 9.
- Key labels: `InputBindings.describe_action("ability_N"/"ultimate", false)` and `short_pad_label(...)`, refreshed only when `_labels_dirty`.
- Target: `player.locked_entity()` -> name + distance, health bar, hint; `LockMarker` placed at `cam.unproject_position(target.anchor_position()) - (16,16)` unless `is_position_behind`.
- Inner classes `Crosshair` (redraws every frame) and `LockMarker` (32x32 diamond).
- Screen regions in use (anchor/offsets): bottom-left resources (16..340, -150..-16); bottom-centre hotbar (-284..284, -92..-16); messages above it (-300..300, -200..-116); bottom-right loot (-260..-16, -40..-16); top-centre target frame (-170..170, 14..74); centre crosshair; capture hint (centre +40..+84); help panel (660x540 centred); DebugPanel top-left at (12, 86).

### PauseMenu (`class_name PauseMenu extends Control`)
- `process_mode = ALWAYS`; `is_open()`, `open()` (visible, `get_tree().paused = true`, context MENU, mouse visible, shows `Settings.load_message`), `close()` (cancels capture, `Settings.flush()`, unpause, context GAMEPLAY, recapture mouse unless headless).
- Pages: `_pages` dict built by `_build_main/_build_settings/_build_controls`; tab names hard-coded at line 42.
- Rows: `_slider_row(grid, text, key, lo, hi, step)` (live `Settings.set_value(key, v, false)`, flush on `drag_ended`), `_check_row`, `_option_row`.
- Rebinding: `_begin_capture(action, pad)`; `_input` takes the next key/mouse (or pad) event, ignores motion, Esc cancels, refuses binding `ability_modifier` onto a combo action, calls `Settings.find_conflicts` then `Settings.set_action_binding`. Grid lists every `InputBindings.ACTIONS` entry with `InputBindings.LABELS`.
- Main page "Restart sandbox" emits `Events.sandbox_reset_requested("menu_restart")`; Quit hidden on web.

### UiKit (static, `RefCounted`)
Colours `BG, BG_LIGHT, BORDER, TEXT, MUTED, HEALTH, STAMINA, ESSENCE, FURY, WARN, BAD, GOOD`.
`box(color, radius, border) -> StyleBoxFlat`, `label(text, size, color) -> Label` (outlined, mouse IGNORE), `panel(color) -> PanelContainer` (mouse IGNORE), `bar(fill, height) -> ProgressBar` (0..1, step 0), `button(text, size) -> Button` (FOCUS_ALL).

### DebugPanel (`class_name DebugPanel extends PanelContainer`)
Group `"hud_debug"` (autopilot uses it). `enabled = OS.is_debug_build()`, `toggle()`, `frame_stats() -> {avg,p95,p99}` over last 300 deltas. Reads `GiantPlayer.get_debug_info()`, each `"enemies"` node **cast to `SoldierEnemy`** (line 69: other classes are silently skipped), `"debris_pool"`, `Sim.entities()`, `Sim.pending_hit_count()`, `WorldState.deltas`.

### main.gd (UI host)
Fields `hud, pause_menu, debug_panel, sandbox, autopilot`. `SANDBOX_SCENE` const (line 13). `_unhandled_input` (line 100): `pause` toggles menu; when closed: `help`, `debug_panel`, `debug_reset` (debug builds), Enter while dead -> `sandbox_reset_requested("restart_after_death")`. `_input` takes click-to-capture (`static is_capture_click`). Focus-out and web pointer-lock loss open pause (not with autopilot). `_on_reset_requested`: `WorldState.clear()`, `Sim.clear_pending()`, context GAMEPLAY, unpause, deferred `reload_current_scene`.

### Scene generator (`tools/build_scenes.gd`)
`_ready` (lines 33-43) calls, in order: `_make_materials`, then `_save(_build_giant(), ...giant.tscn)`, soldier, dummy, fence, arena, main, then quits. Helpers: `_save(root, path)` (sets owners via `_own`, packs, frees), `_scripted(node, script_path, props)`, `_n3`, `_box`, `_cyl`, `_sphere`, `_static_box`, `_hurtbox(name, region, shape, pos)`, `_box_shape`, `_arm_basis`, `_sign`. Constants: script paths `S_*`, layers `L_WORLD=1, L_ACTORS=2, L_HURTBOX=4, L_BREAKABLE=16`, `FP_HIDDEN=2`; `mats` dict (16 colour materials + `ground` shader). `_build_arena` **loads already-saved** fence/dummy/giant/soldier `.tscn` from disk, so builder order is a real dependency.

### TestSuite
`failures`, `current_test`, `checks`; `before_each()/after_each()` (may await); `fail(msg)`; `assert_true/false(cond, msg)`, `assert_eq(actual, expected, msg)` (type-strict except int/float mixes: an `Array` vs `Array[String]` mismatch fails - tests write `[...] as Array[String]`), `assert_near(a, e, tol, msg)`; `step_ticks(n)` (awaits `process_frame` until `Sim.tick` advanced n; fails after `n*4+20` frames); `action(id) -> ActionDef`.

### IntegrationSuite
Consts `GIANT, SOLDIER, DUMMY, FENCE` scene paths. Capture arrays reset per test: `hits: Array[HitResult]`, `deaths`, `destroyed`, `loot` (`"world_id:item"`), `lock_events` (`[tick, actor, target, reason]`), `started` (`"actor:action_id"`), `clanks`. `before_each`: `Sim.clear_pending()`, `WorldState.clear()`, `Settings.session.camera_mode = 0`, context GAMEPLAY, new `world` Node3D with a 120x1x120 floor, connects Events, steps 1 tick. `after_each`: disconnects only its own callables from those 7 signals, frees `world`, waits 2 frames, clears pending hits.
Helpers: `add_box(size, pos, layer)`, `spawn_player(pos, yaw) -> GiantPlayer` (sets `router.use_injection = true`), `spawn_soldier(pos, yaw, id := "soldier_01", ai := false)`, `spawn_dummy(pos, id)`, `spawn_fence(pos, world_id := "test.fence_01", yaw)`, `hits_on(target_id)`, `static yaw_towards(from, to)`, `queue_hit(attacker_id, target_id, attacker_pos, power := 10.0, tags, height)`. `_wait_until(cond, max_ticks)` exists only locally in `test_defense_integration.gd`.

### Test runner
`SUITE_DIRS = ["res://tests/unit", "res://tests/integration"]`, non-recursive, files `test_*.gd`, sorted. Per suite: `script.new()`, add as child, every method starting `test_` in `get_method_list()` order; before each test `Sim.reseed(Sim.DEFAULT_SEED)` (20261104). Errors captured by `TestErrorLogger` after each test become failures. `--filter=X` matches substring of the path. Settings isolated (`persist = false`, defaults restored once at start). Exit code 1 on any failure; data validation errors are failures.

### Input injection (used by tests and the bot; `InputRouter`)
`use_injection`, `inject_edge(&"dodge"|&"jump"|&"interact"|&"slot_N"|&"ultimate"|&"lock_press"|&"lock_release"|&"block_press"|&"block_release"|&"camera_toggle"|&"target_left"|&"target_right"|&"sprint_press"|&"stick_flick_*"|&"stick_tap_*")`, `inject_light_attack()` (heavy if injected `heavy_modifier` held), `set_injected_hold(&"block"|&"sprint"|&"heavy_modifier"|&"lock", bool)`, `set_injected_move(Vector2)`. Camera is turned by writing `player.camera_rig.yaw`. Static `InputRouter.context` (GAMEPLAY/MENU/TEXT) zeroes edges outside GAMEPLAY, even injected ones.

### Autopilot (`class_name Autopilot extends Node`)
Static state survives scene reloads: `_started, _elapsed, _duration, _scenario, _capture_dir, _stats, _frame_ms, _step, _rng (seed 424242)`. `configure(seconds, scenario, capture_dir)` is a no-op after the first call. Process mode ALWAYS for capture, PAUSABLE for soak. `_physics_process`: finds player, forces `router.use_injection`, tracks `max_debris`, runs `_run_capture` or `_run_soak`. Soak: target = first alive `"enemies"` -> fence (`"breakables"`) -> `"dummies"`; `_face()` lerps camera yaw; walks, sprint beyond 14 m, sidestep when stuck 0.5 s; every 0.25-0.8 s within 6 m rolls light 42% / heavy 12% / block 12% / dodge 10% / slot_1 7% / jump 3% / lock 6% / camera 3% / target_right. Dead 1.5 s or no soldier 12 s -> `sandbox_reset_requested`. Capture: array of lambdas (rebuilt every tick) advanced by `_step`, `_walk_to(target, stop, dt, timeout)`, `_shot(name)` (awaits `frame_post_draw`, saves PNG; headless -> "skipped"), `_toggle_debug_panel()`. `_finish()` prints `AUTOPILOT_RESULT {json}` (stats + `simulated_s`, `frames`, `frame_ms_p50/p95/p99`, `shots`) and always `quit(0)`.

### Groups and node names code relies on
Groups: `player`, `enemies`, `dummies`, `breakables`, `debris_pool`, `sandbox`, `hud_debug`. Names: `Main` children `Hud`, `DebugPanel`, `PauseMenu`, `HitFeedback`, `Autopilot`; arena `Player`, `Soldier01`, `Spawns/PlayerSpawn`, `PatrolRoute`, `DebrisPool`, `Navigation`; fence child `BlockShape`; player children `CombatEntity`, `CameraRig`, `InputRouter`.

## 3. Data flow and invariants

- UI is a pure reader: Hud/DebugPanel read controller, pools, cooldowns, lock, `WorldState`; they never change combat state. Player-facing notices go through `Events.hud_message` (emitted by gameplay, e.g. `giant_player.gd` line 192 for `interact`).
- Sim (autoload, `process_physics_priority = -1000`) steps before any other physics callback, so anything injected in a node's `_physics_process` (the autopilot) is consumed on the **next** tick. Tests inject between `step_ticks` calls, so injection at tick T shows effect at T+1 (`test_input_feedback_on_next_tick`).
- Pause = `get_tree().paused = true`: Sim, sandbox, Hud, HitFeedback freeze (pausable); PauseMenu, Main and capture autopilot keep running. Menu context suppresses all gameplay edges and look.
- Reset/restart/death-restart = full scene reload; UI is rebuilt from scratch, autoloads persist, Autopilot statics persist.
- Tests rely on: `--fixed-fps 60` (one physics tick per frame), reseeded `Sim.rng` per test, `Sim.tick` monotonic across tests (always use relative ticks), `WorldState` cleared per integration test, `InputRouter.context` reset to GAMEPLAY, any logged error = failure, `Settings.persist = false`.
- Hotbar reasons duplicate controller validation order (`CombatController._evaluate`, line ~250: dead, empty, locked, cooldown, busy/cancel, costs). If M2 adds reasons (target required, status-silenced, out of range) both must change together.

## 4. Extension points: how to add each M2-M5 item

General rule: **one file per widget/screen**, Hud only hosts. Put HUD widgets in `ui/hud/` (e.g. `ui/hud/xp_widget.gd`), full-screen modal screens in `ui/screens/`. Each widget is a `Control` that finds `player` like Hud does (or receives `hud.player`), reads state in `_process`, subscribes to Events with method callables (never capturing lambdas: they leaked across resets in M1).

1. **Hud widget registry** (do first, one small package): add `ui/hud/hud_widgets.gd` with `const WIDGETS := [preload(...), ...]`; in `Hud._ready` after `_build_help()` add `for w in HudWidgets.WIDGETS: add_child(w.new())`. Later packages each add one line there. Do not use DirAccess scanning for this (exported builds list remapped script files).
2. **Modal screen base** (one package, before any menu): `ui/screens/ui_screen.gd` `class_name UiScreen extends Control` with `open()/close()/is_open()`, `pauses_game := true`, generalising PauseMenu lines 65-81 (pause, context MENU, mouse visible, `grab_focus()` on the first button - currently nothing calls `grab_focus`, so pad navigation of menus is unverified). Add `ui/screens/screen_stack.gd` owned by `main.gd`: only one modal open; `pause` action closes the top screen first, else opens PauseMenu. Change `main._unhandled_input` once to route through it.
3. **Title menu**: `ui/screens/title_screen.gd`. Simplest: `main.gd` shows the title instead of instantiating `SANDBOX_SCENE` immediately; choice (New Valley / Continue / Sandbox / Settings / Quit) sets a session field (e.g. `Settings.session["mode"]` or a new session autoload, see data_saves_flow brief) and loads the level. Must be skipped when `--autoplay`/`--scenario` is present, and for a `--level=` flag. Reuse PauseMenu's settings/controls pages: extract `_build_settings/_build_controls` into `ui/screens/settings_pages.gd` so both menus share them.
4. **XP / level**: add a thin XP bar + "Lv N" row into the resources panel via an `XpWidget` placed directly above it (y -186..-156) rather than editing `_build_resources`. Listen to new `Events.xp_gained(tick, amount, source)` / `level_changed(tick, old, new)`; show `show_message("Level 3!", "good")`. Fix: the mode label "Stage N" is refreshed only on camera/binding changes (`_refresh_mode_label`, line 355); connect `Events.growth_changed` to it.
5. **Level-up attribute allocation**: `ui/screens/attributes_screen.gd` (UiScreen): six rows `Strength..Constitution` with +/- buttons, unspent points, preview of derived health/stamina/essence; Confirm calls a progression API (e.g. `Progression.allocate(dict)`), never writes pools directly. Open from a "points available" prompt (key in help) and from shrines.
6. **Loadout editing at shrines**: `ui/screens/shrine_screen.gd` with tabs Rest / Grow / Loadout / Attributes. Loadout tab: 8 slot buttons + ultimate, a list of unlocked abilities (`ActionDef.hotbar_label`, cost, `unlock_stage`), assignment calls a player API (e.g. `GiantPlayer.set_loadout_slot(i, id)`) that updates `controller.loadout`; Hud picks it up next frame with no extra code. Grow: call the growth API and display its failure explanation text.
7. **Inventory / equipment**: `ui/screens/inventory_screen.gd` listing `WorldState.inventory` (or its M4 replacement) with `GameData.get_record(id).display_name`, an equipped-weapon section, one upgrade interaction. New action `inventory` (key I / pad Back) needs `InputBindings.ACTIONS` + `LABELS` + `data/input/default_bindings.json`; it then appears in the rebinding grid automatically. Remove/shrink the bottom-right `_loot_label` once inventory exists.
8. **Quest tracker / objective marker**: `ui/hud/quest_tracker.gd` top-right panel (free region) reading the quest state's current objective text; `ui/hud/objective_marker.gd` reusing the `LockMarker` projection code (line 465-470) plus edge clamping and distance. Expect an API like `Quests.current_objective() -> {text, world_pos, target_id}`; the Valley bot should read the same API.
9. **Interact prompts**: gameplay adds an interactable contract (group `interactables`, `prompt_text()`, `can_interact(player)`, `interact(player)`) and a read-only `player.interact_candidate` updated in sim; `ui/hud/interact_prompt.gd` at centre +100 shows "[E] Talk" using `InputBindings.describe_action("interact", pad)`. There is no "last used device" tracking anywhere; add one (e.g. in InputRouter `_unhandled_input`) if prompts should switch between keyboard and pad glyphs. Replace the stub at `giant_player.gd` line 191.
10. **Dialogue with choices**: `ui/screens/dialogue_screen.gd` (UiScreen, pauses) with speaker, text, numbered choice buttons (1-4 keys + pad focus). Choices call `DialogueSession.choose(index)`; the screen is only a view so the bot and tests can call `choose()` directly. Resolution flags live in quest/world state, not in the UI.
11. **Status icons**: `ui/hud/status_row.gd` above the resource panel (and a mini row in the target frame), reading the combatant's status list (combat brief owns the model); text chips like "SKIN 4s", "SLOW 2s", "SURGE 5s" using `UiKit.panel` + `label`.
12. **Boss bar**: `ui/hud/boss_bar.gd` top-centre, wide (-320..320, 14..54), name + health + phase pips, visible while an entity in a `bosses` group is engaged (or on `Events.boss_engaged/boss_phase_changed`). Move `_target_frame` down (offset_top 64) when the boss bar is visible, or hide the target frame when the lock target is the boss.
13. **Tutorial prompts**: `ui/hud/tutorial_prompt.gd` left-centre panel (avoid DebugPanel at top-left), driven by data (`data/tutorial/*.json`: id, trigger event, text with `{action:dodge}` placeholders resolved via `describe_action`) and a "seen" flag set in save data. Show once, dismiss on the taught action or timeout.
14. **Death screen**: `_build_death` hard-codes "Press Enter to restart the sandbox"; make the hint mode-dependent ("Enter: load last checkpoint") and have `main.gd` emit a checkpoint-reload request instead of `sandbox_reset_requested` in Valley mode. Pause menu Main page gets "Load last checkpoint" / "Quit to title".
15. **Help overlay**: `_controls_text` rows (line 297) are hard-coded M1 text ("Heavy Footfall (slot 1)", "none equipped in M1"); generate ability rows from the current loadout and add interact/inventory.
16. **Hotbar spec gap**: "selected target where needed" is not shown. For targeted abilities (Runic Bolt, Boulder Hurl) add a small target line under the slot or reuse the lock frame. Move the reason computation into a pure `CombatController.preview_reason(kind, params) -> String` and call it from `_update_slots`, so HUD and controller can never disagree.
17. **DebugPanel**: replace the `as SoldierEnemy` cast with a duck-typed `has_method("get_debug_info")` over `enemies`, cap printed enemies (12+ combatants overflow the screen), add quest/checkpoint/level lines.

### Adding scene builders without editing one file
Split `tools/build_scenes.gd` into `tools/scene_kit.gd` (`class_name SceneKit`: `mats`, `save`, `own`, `scripted`, `box`, `cyl`, `sphere`, `static_box`, `hurtbox`, `sign`, layer constants) and per-area builder files `tools/builders/<area>.gd` each exposing `static func build_all(kit: SceneKit) -> void` that calls `kit.save(...)`. `build_scenes.gd._ready` keeps an explicit ordered list (`const BUILDERS := ["res://tools/builders/actors.gd", "res://tools/builders/enemies.gd", "res://tools/builders/props.gd", "res://tools/builders/sandbox.gd", "res://tools/builders/valley.gd", "res://tools/builders/test_scenes.gd", "res://tools/builders/main.gd"]`), dependencies first. Add a `--only=<builder>` user arg to rebuild one area. Materials stay in `_make_materials` (or move to `data`-like table in SceneKit); new materials are additive dict entries. Large static layouts (the valley) should come from a data table (positions/sizes per block) rather than hundreds of builder lines.

### Writing tests for M2-M5
- Unit: `extends TestSuite`, pure objects, `before_each` builds them (see `tests/unit/test_controller.gd`). Static UI logic (e.g. `preview_reason`, prompt text formatting, objective-marker edge clamp) goes here.
- Integration: `extends IntegrationSuite`; spawn, `await step_ticks(n)`, inject, assert. Promote `_wait_until` into a new helper file rather than editing the base (see section 5). For Valley scenes: `world.add_child(load(path).instantiate())` as `test_obstacle_route.gd` does with the arena; set `ai_enabled = false` on actors you do not need.
- UI tests (none exist today): add a CanvasLayer under `world`, `Hud.new()` / screen `.new()`, spawn a player, step frames, assert on widget state. Prefer each widget exposing a small read API (`visible_text()`, `slot_state(i)`) over reaching into private nodes. Press buttons with `button.pressed.emit()`. Never pause the tree in a test unless you unpause in the same test: Sim is pausable, so `step_ticks` times out.
- Suites must be flat in `tests/unit` or `tests/integration` (runner is non-recursive). Put slow suites (valley load, long runs) in `tests/slow/` and add that dir only behind a `--slow` flag, to keep the default run under ~15 s.

### Valley bot (end-to-end quest run)
Build `scripts/debug/valley_bot.gd` (new file), dispatched from `Autopilot._physics_process` when `_scenario == "valley"` (one added branch). Design:
- **Goal-driven, not step-indexed**: every tick derive the goal from game state (`Quests.current_objective()`, player level/points, shrine proximity), so a checkpoint reload (scene reload) resumes naturally; only counters live in statics.
- **Movement**: follow `NavigationServer3D.map_get_path(get_world_3d().navigation_map, from, to, true)` waypoints with `_face()`; keep the soak's stuck-sidestep; fall back to authored `BotRoute` Marker3D chains in the valley scene for tricky spots.
- **Combat**: factor `_run_soak` lines 147-209 into `_fight(target, dt)`; use lock-on, dodge on visible enemy windups (`controller.phase()` of the attacker), use all equipped slots by cost/cooldown availability (read the same data as the hotbar).
- **Interaction**: `inject_edge(&"interact")` near the target; dialogue via `DialogueSession.choose(i)` from a policy flag `--bot-choice=help|intimidate`; level-up via the progression API; shrine growth/loadout via shrine APIs.
- **Watchdogs**: per-objective timeout (e.g. 240 s) and max deaths per objective; on breach record `stuck_at` and finish with non-zero exit. Finish early on quest completion.
- **Result**: extend `AUTOPILOT_RESULT` with `objectives` (id + seconds), `deaths`, `checkpoint_loads`, `level`, `stage`, `quest_flags`, `rewards_by_world_id` (duplicate check), `errors`.
- Command: `godot --headless --path . --fixed-fps 60 -- --no-user-settings --scenario=valley --autoplay=2400` (duration = hard timeout).

### 30-minute stability run
`--scenario=valley --autoplay=1800` with a loop mode: after completion, reload the last checkpoint / start a new game and keep fighting. Add to the autopilot: an error-counting `Logger` (copy of `TestErrorLogger` into `scripts/debug/`, since `tests/*` is excluded from exports) and `quit(1)` when errors > 0; sample every 60 s `Performance.OBJECT_NODE_COUNT`, `OBJECT_ORPHAN_NODE_COUNT`, `MEMORY_STATIC` and fail on monotonic growth across reloads; per-tick invariants: player y > -50, no NaN positions, lock target alive or empty, `Sim.pending_hit_count()` bounded, debris <= 40, tokens <= 2, each world id rewarded at most once.

### Stress route (12 combatants, 20 breakables, 40 debris)
Generate `scenes/test/stress_arena.tscn` from a builder (12 AI enemies of mixed roles, 20 breakables along a fixed route, nav baked). Add `--level=<path>` to `main.gd` (replacing the `SANDBOX_SCENE` const use) and `--scenario=stress`: the bot walks the route for 300 s, heavy/Footfall through every breakable (debris saturates 40), fights continuously. Measure real frame time only **without** `--fixed-fps` on the reference PC; in headless CI report CPU cost per tick from `Performance.TIME_PHYSICS_PROCESS` / `TIME_PROCESS` (p95/p99), which stays meaningful with fixed fps.

## 5. Hotspots and conflict-avoidance proposal

| Hotspot | Who would edit it | Proposal |
| --- | --- | --- |
| `ui/hud.gd` | XP, status, boss, quest, prompts, tutorial, hotbar | Widget registry (4.1); Hud core edited by one package only (hotbar target/reason, death text, help rows). |
| `scripts/main.gd` `_ready` / `_unhandled_input` / reset | title, checkpoints, screens, level flag, bot | One "flow" package owns main.gd; others hook via ScreenStack and Events. |
| `ui/pause_menu.gd` | settings additions, new menu items | Extract settings pages; menu items added via a list of `[label, callable]` entries. |
| `tools/build_scenes.gd` | every new enemy, prop, valley area | SceneKit + per-area builder files with an ordered list. |
| `tests/integration_suite.gd` | everyone wanting helpers / new event captures | Freeze it; add `tests/support/*.gd` static helpers (`TestWait.until(suite, cond, ticks)`, `ValleyFixture.load(suite)`); suites connect extra Events themselves and disconnect in their own `after_each` (call `super()`). |
| `scripts/debug/autopilot.gd` | soak, capture, valley, stress | Keep as dispatcher; each scenario in its own file under `scripts/debug/`. |
| `scripts/core/events.gd` | every feature adding signals | Pre-declare the M2-M5 signals in one early commit (xp_gained, level_changed, quest_updated, objective_changed, dialogue_started/ended, status_applied/removed, boss_engaged, boss_phase_changed, checkpoint_saved/loaded, interact_target_changed). |
| `InputBindings.ACTIONS/LABELS` + `default_bindings.json` | inventory, quest log, any new key | One package adds all new actions at once. |

## 6. Pitfalls and gotchas

- `set_anchors_preset` keeps the old rect in Godot 4; always `set_anchors_and_offsets_preset` (made the M1 HUD invisible).
- Event connections must be **method callables**; capturing lambdas outlived their nodes and double-counted after resets (handoff section 6; comment in autopilot line 50).
- Hud and HitFeedback are PAUSABLE: anything shown during a modal (dialogue, shrine) must live in the screen (ALWAYS) or the HUD will be frozen behind it.
- Mode label stage text goes stale after growth (see 4.4).
- DebugPanel ignores non-`SoldierEnemy` enemies (line 69).
- With `--fixed-fps 60`, `_process` delta is constant, so `Autopilot` frame_ms and `DebugPanel.frame_stats()` are meaningless (always ~16.7 ms) in tests/soaks; README correctly says measure without it.
- `Autopilot._finish` always exits 0, and it does not count errors; a soak "passes" even if scripts errored. `configure` ignores a second call (statics), so one Autopilot config per process.
- `_run_capture` rebuilds a ~45-lambda array every tick; fine now, wasteful for a long valley script.
- Autopilot injections are consumed one tick later (Sim priority -1000).
- `InputRouter.context` is a static global; a test that sets MENU or calls `Input.action_press` must restore/release it (see `test_real_input_events_and_contexts`). `Settings.set_value` changes persist across tests in one run (only reset at runner start): restore them (`test_hold_lock_follows_polled_key_state` does).
- Any `push_error` during a test fails it; use `push_warning` for expected non-fatal conditions.
- `assert_eq` is type-strict for arrays (typed vs untyped).
- Runner is non-recursive; subfolders in `tests/unit`/`tests/integration` are ignored silently.
- `step_ticks` while the tree is paused times out.
- No `grab_focus` anywhere: controller navigation of menus is untested; rebinding with Esc as both `pause` and cancel works only because `_input` handles capture before `_unhandled_input`.
- Hotbar costs show only `int()` of costs; fractional costs display truncated.
- Builder order: `_build_arena` loads previously saved scenes from disk; a fresh clone needs one full run, and scene changes need a regeneration before tests (`build_scenes.tscn` then `--import`).
- Export `include_filter` is `data/*.json, data/*/*.json`: data nested deeper (e.g. `data/quests/valley/x.json`) is **not exported**; keep data two levels deep or widen the filter.
- Capture tour needs a display (`xvfb-run`); headless runs record "skipped" shots and do not fail.
