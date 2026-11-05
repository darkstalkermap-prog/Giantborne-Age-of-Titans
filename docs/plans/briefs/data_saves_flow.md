# Brief: data loading, validation, saves, settings and game flow

Scope: `scripts/core/{data_validator,game_data,json_io,save_io,settings,events,world_state}.gd`,
`scripts/main.gd`, `scenes/main.tscn`, `project.godot`, `data/**`. Read on 2026-11-04 against the
merged M0+M1 code (15 suites / 1133 checks). Line numbers refer to that state.

## 1. Files and responsibilities

| File | Responsibility |
| --- | --- |
| `project.godot` | Autoload order, 60 Hz physics, Jolt, Compatibility renderer, physics layer names, `application/config/version="0.1.0-m1"` (the only "build version" string). No input map (bindings come from data). |
| `scripts/core/json_io.gd` (`JsonIO`) | Read/parse one JSON file with readable errors; list `*.json` recursively, sorted. |
| `scripts/core/data_validator.gd` (`DataValidator`) | Static schema + semantic validation of one record; cross-record reference check. All enums live here. |
| `scripts/core/game_data.gd` (autoload `GameData`) | Loads every record under `res://data`, validates, checks `REQUIRED_RECORDS`, caches `ActionDef`s, lookups by id. |
| `scripts/core/save_io.gd` (`SaveIO`) | Versioned JSON persistence: atomic temp-write + verify + one backup; read with backup fallback and future-version rejection. |
| `scripts/core/settings.gd` (autoload `Settings`) | Player settings in `user://settings.json` through SaveIO; applies input bindings; session-only state dict. |
| `scripts/core/events.gd` (autoload `Events`) | Global signal bus (13 signals). |
| `scripts/core/world_state.gd` (autoload `WorldState`) | In-memory world deltas keyed by stable world id + minimal inventory; `to_save_dict/from_save_dict`. |
| `scripts/core/sim.gd` (autoload `Sim`) | 60 Hz driver, tick counter, seeded `rng`, entity/actor registry, hit queue, attack tokens. |
| `scripts/main.gd` / `scenes/main.tscn` | Entry scene: data-error screen, builds sandbox + HUD + menus, pause/help/debug keys, death restart, reset by scene reload, autopilot flags, web pointer-lock handling. `main.tscn` is generated (`tools/build_scenes.gd::_build_main`, line 587) and is just a `Node` named `Main` with `main.gd`. |
| `data/**` | 23 records: `abilities/` (7 actions: light_1..3, heavy_1, heavy_footfall, soldier_slash, soldier_chop), `actions/` (block, dodge, jump, sprint), `enemies/soldier`, `growth/growth_01..03` (all three stage profiles already exist), `input/default_bindings`, `items/wood_scrap`, `player/giant` + `ancestry_neutral`, `props/fence_wood` + `practice_dummy`, `weapons/club` + `soldier_sword`. |

## 2. Key classes and APIs

### Autoload order (`project.godot` lines 19-23) - order matters
`Events` -> `GameData` -> `Settings` -> `WorldState` -> `Sim`.
`Settings._ready()` calls `apply_bindings()` -> `GameData.get_record("input.default")`, so
GameData must stay before Settings. Any new autoload that reads data must come after GameData;
one that restores saves should come after WorldState (it writes into it). All autoloads survive
`reload_current_scene()`.

### DataValidator (static, `RefCounted`)
- Consts: `SUPPORTED_SCHEMA_VERSION = 1`, `TICK_RATE = 60` (duplicated in `ActionDef` and `Sim`),
  `RECORD_TYPES` (line 12: `action, growth_profile, player, enemy, prop, weapon, item, ancestry,
  input_bindings`), enums `DAMAGE_TYPES, TAGS, ACTION_KINDS, ATTACK_KINDS, HIT_SHAPES
  ["weapon_arc","cylinder_pulse","none"], ATTACK_CATEGORIES, PROP_CATEGORIES, ARCHETYPES
  [soldier, archer, mage, wolf, ogre, boss], WEAPON_FAMILIES [club, sword, hammer, axe, fists],
  ATTRIBUTES, CANCEL_INTO, PHASES, SIZE_POLICIES, INTERRUPT_POLICIES, INTERACTION_PERMISSIONS`,
  `ID_REGEX = ^[a-z][a-z0-9_]*(\.[a-z0-9_]+)+$` (at least one dot; prefix not tied to type).
- `validate_record(rec, path) -> {errors, warnings, refs}` (line 38): id regex, future
  `schema_version` (early return), `type` in RECORD_TYPES (early return), `_check_fields(d,
  schema_for(type))`, then per-type semantic `match` (lines 61-71).
- `validate_references(records, refs) -> PackedStringArray` (line 76): each ref must exist and
  have exactly `ref.type`.
- `schema_for(type) -> Dictionary` (line 133): base fields (`schema_version` req int>=1, `id` req,
  `type` req enum, `display_name`, `description`) merged with a per-type block (the big `match`,
  lines 141-365).
- Spec builders: `_num(min,max,req)`, `_pos(req)` (>0), `_int(min,max,req)`, `_str(req, enum)`,
  `_ref(type, req, allow_empty)`, `_poise_fields()`.
- Spec dictionary vocabulary understood by `_check_value` (line 388): `t` in
  `number|int|string|bool|vec3|array|dict`; `req`, `min`, `max`, `gt`, `enum`, `ref`,
  `ref_allow_empty`; arrays: `items` in `string|number|dict`, `items_enum`, `items_ref`,
  `items_ref_allow_empty`, `item_fields`; dicts: `fields` (strict sub-schema) or
  `keys_enum` + `values` (map).
- Semantic helpers: `_require(d, keys, ctx, out, why)`, `_check_tick_multiple` (warning only,
  rounds), `_semantic_action/_growth/_player/_enemy/_input`.

### GameData (autoload, `extends Node`, no class_name)
- `DATA_ROOT = "res://data"`; `REQUIRED_RECORDS` (line 10): `player.giant, enemy.soldier,
  prop.fence_wood, prop.practice_dummy, input.default, action.block`.
- `signal reloaded`; vars `records` (id -> raw Dictionary), `record_paths`, `errors`, `warnings`,
  private `_actions` (id -> `ActionDef`).
- `load_all(root, check_required := true)` (line 33): clears everything, reads/validates every
  file, skips duplicates (error), appends required-record refs, validates refs, builds
  `ActionDef.from_dict` for every `type == "action"`, emits `reloaded`.
- `is_valid()`, `has_record(id)`, `get_record(id) -> Dictionary` (returns `{}` if missing, the
  live dict, not a copy), `get_action(id) -> ActionDef` (null if missing), `ids_of_type(type)`
  (sorted).

### JsonIO (static)
`read_file(path) -> {ok, data, error}`, `parse_text(text, source)`, `list_json_files(root)`
(recursive, skips dot-entries, sorted).

### SaveIO (static)
- `write_json(path, data: Dictionary) -> Error` (line 13): `JSON.stringify(data, "\t", true)`
  (sorted keys) -> `<path>.tmp` -> re-read and verify it is a Dictionary -> if the existing main
  file is loadable at `data.schema_version` it is copied to `<path>.bak` -> `rename_absolute(tmp,
  path)` (falls back to remove + rename). Does NOT create parent directories.
- `read_json(path, supported_version) -> {ok, data, source: "main"|"backup"|"none", message,
  future_version}` (line 42). Main first, then `.bak` with a "Recovered ..." message.
- `_try_load(path, supported_version)`: missing / corrupt / not-object / no valid integer
  `schema_version` >= 1 / newer than supported (sets `future_version`).
- It validates only the envelope (`schema_version`); content validation is the caller's job.

### Settings (autoload)
- `PATH = "user://settings.json"`, `SCHEMA_VERSION = 1`, `DEFAULTS`, `RANGES`, `ENUMS`.
- `signal changed(key)`; vars `values`, `load_message` (shown in pause menu), `persist` (false
  when `--no-user-settings`), `_unsaved`, `session := {"camera_mode": 0}` (session-only, survives
  scene reloads, never written).
- `load_settings()` (future version -> copies file to `settings.schema%d.rejected.json`),
  `_merge(data)` (type/range/enum sanitizing, unknown keys ignored), `_sanitize_bindings`,
  `save_settings()`, `get_value`, `set_value(key, v, save := true)`, `flush()` (on
  `NOTIFICATION_WM_CLOSE_REQUEST`, pause close, quit), `apply_bindings()`,
  `set_action_binding(action, pad, ev)`, `reset_bindings()`, `find_conflicts`.

### Events (autoload) - full list
`ability_started(tick, actor_id, action_id, instance_id)`, `action_rejected(tick, actor_id,
action_id, reason)`, `hit_resolved(tick, result: HitResult)`, `attack_clanked(tick, actor_id,
instance_id, point)`, `area_pulse(tick, actor_id, action_id, center, radius)`,
`entity_died(tick, entity_id, killer_id)` (once per death), `staggered(tick, entity_id,
duration_s, reason)`, `object_destroyed(tick, world_id, by_entity_id)` (once),
`loot_awarded(tick, world_id, item_id, count, recipient_id)`, `growth_changed(tick, entity_id,
old_stage, new_stage)` (declared, unused - reserved for M3), `lock_target_changed(actor_id,
target_id, reason)`, `camera_mode_changed(mode)`, `hud_message(text, kind)`,
`sandbox_reset_requested(reason)`.
Contract (header comment): emitted after state changed; listeners never spend resources or change
combat state.

### WorldState (autoload)
`SCHEMA_VERSION = 1`; `deltas` (world_id -> `{destroyed, damage_stage, loot_awarded}`),
`inventory` (item_id -> count). `get_delta`, `is_destroyed`, `record_destroyed(world_id,
damage_stage := 1)`, `try_award_loot(world_id) -> bool` (true exactly once), `add_item`,
`clear()` (debug/sandbox only), `to_save_dict()`, `from_save_dict(data) -> bool` (requires
`schema_version == 1` exactly). Writers today: only `BreakableProp` (`scripts/world/
breakable_prop.gd` lines 27-51).

### main.gd (`extends Node`, root `Main`)
- `SANDBOX_SCENE = "res://scenes/world/sandbox_arena.tscn"` (line 13), vars `hud: Hud`,
  `pause_menu: PauseMenu`, `debug_panel: DebugPanel`, `sandbox: Node3D`, `autopilot: Autopilot`.
- `_ready()` (line 22): `PROCESS_MODE_ALWAYS`, unpause, `InputRouter.set_context(GAMEPLAY)`,
  CanvasLayer (layer 10); if `!GameData.is_valid()` -> `_show_data_errors` and return (all input
  handlers then no-op because `pause_menu == null`). Else instantiate sandbox (PAUSABLE),
  `HitFeedback` ("HitFeedback"), `Hud` ("Hud"), `DebugPanel` ("DebugPanel"), `PauseMenu`
  ("PauseMenu"); connect `Events.sandbox_reset_requested`; `_start_autopilot_if_requested()`;
  capture mouse unless autopilot or web.
- Cmdline user args: `--autoplay=SECONDS`, `--scenario=capture`, `--capture-dir=PATH`,
  `--no-user-settings` (read by Settings). Tests also use `--filter=`.
- `_unhandled_input`: `pause` toggles menu; when not paused: `help` -> `hud.toggle_help()`,
  `debug_panel`, `debug_reset` (debug builds) -> emit reset `"debug_reset"`, Enter/KP Enter while
  `_player_dead()` -> emit `"restart_after_death"`. Pause menu "Restart sandbox" emits
  `"menu_restart"` (`ui/pause_menu.gd` line 101).
- `_input`: `static is_capture_click(event, mouse_captured, menu_open)` (unit-tested by
  `tests/unit/test_mouse_capture.gd`, which preloads `main.gd` - keep it static and its name).
- `_notification`: focus-out opens pause (not headless, not autopilot).
- `_process`: web only - pointer-lock loss opens pause menu (unless dead).
- `_on_reset_requested(reason)` (line 166): `WorldState.clear()`, `Sim.clear_pending()`, GAMEPLAY
  context, unpause, `call_deferred("reload_current_scene")`. Note: clears world deltas for every
  reason, including death.
- `_player_dead()`: `get_first_node_in_group("player") as GiantPlayer` and
  `controller.state == CombatController.State.DEAD`.

### Groups and node names code relies on
Groups: `"player"` (GiantPlayer), `"breakables"` (BreakableProp), `"sandbox"` (SandboxArena).
Nodes: `Spawns/PlayerSpawn` (`SandboxArena.player_spawn()`), `Navigation` in the arena; GiantPlayer
children `CombatEntity`, `CameraRig`, `Visual`, `BodyShape`; BreakableProp children
`CombatEntity`, `Intact`, `Broken`, `Block*` collision shapes. Stable ids: player entity id
`"player"`, `soldier_01`, `dummy_01`, `dummy_behind_wall`, fence world id `sandbox.fence_01`.

## 3. Data flow and invariants

1. Boot: autoloads `_ready` in order; `GameData._ready` -> `load_all(DATA_ROOT)`; errors are
   `push_error`ed, warnings `push_warning`ed. `main._ready` refuses to start on any error.
2. Actors pull raw dicts by id in `_ready` (`GiantPlayer` reads `definition_id` ->
   `growth_profile`, `weapon`, `loadout`; `CombatEntity` -> `Combatant.from_record`). They hold
   copies of numbers; nothing re-reads data at runtime (no hot reload).
3. Invariants that must stay true:
   - Every shipped record validates with zero errors (`test_shipped_data_is_valid`; the test
     runner also turns any `GameData.errors` into failures). Warnings never fail tests;
     `push_error` anywhere during a test does (`TestErrorLogger`).
   - Unknown keys are errors - every new field must be added to `schema_for` before data uses it.
   - Ids are globally unique across all types; references are exact-type.
   - `REQUIRED_RECORDS` ids exist (`test_required_records_and_enum_lists` deletes
     `fence_wood.json` and expects `missing reference 'prop.fence_wood'`).
   - Tests assert specific error substrings: `"Duplicate id '"`, `"must be > 0"`,
     `"unknown value '"`, `"unknown key '"`, `"newer than supported"`, `"stamina_cost: must be >=
     0"`, `"iframe_start_s must be < iframe_end_s"`, `"active_s must be > 0"`,
     `"missing reference '"`, `"height_m: must be > 0"`. Do not reword these messages.
   - Exact data values asserted by `test_spec_values_in_data` (light/heavy/dodge timings, footfall,
     growth.01 numbers, soldier windups >= 27 ticks).
   - SaveIO tests: newest read from main; no `.tmp` left; corrupt main -> backup with message
     containing "corrupt" and "Recovered"; future version -> `future_version` and "newer version";
     a newer-version main is never copied over the backup.
   - Settings tests: invalid binding override falls back per action; `set_value(.., false)` marks
     `_unsaved` and WM close flushes.
   - Loot is awarded at most once per world id; a re-instanced prop with a destroyed delta starts
     broken (`test_fence_breaks_once_and_loot_once`).
   - `IntegrationSuite.before_each` calls `Sim.clear_pending()`, `WorldState.clear()`,
     `Settings.session["camera_mode"] = 0` - any new global state must be reset there too.
   - The test runner forces `Settings.persist = false` and default values; tests must never touch
     real user files.

## 4. Extension points: how to add the M2-M5 content

### Generic recipe for a new record type
1. `DataValidator.RECORD_TYPES` (line 12): add the type string.
2. `DataValidator.schema_for` (line 141 `match`): add a `"<type>": s.merge({...})` block.
3. Optional semantics: add `"<type>": _semantic_<type>(d, ctx, out)` to the `match` at line 61.
4. Data files under `data/<folder>/` (any folder; the loader is recursive and type-driven).
5. If code looks an id up unconditionally, add it to `GameData.REQUIRED_RECORDS`.
6. Optional typed cache: build it in `GameData.load_all` after `validate_references` (like
   `_actions`), with a getter. Otherwise read raw dicts via `get_record` / `ids_of_type`.
Limitations to know: refs are single-type (no "item or weapon"); there is no `int` item type
for arrays (`items: "number"` also forbids negatives); intra-record references (dialogue node ->
node, quest stage -> stage) need hand-written semantic checks; no regex check for free-form
flag strings.

### Abilities with effect types (M2/M4)
- Valley abilities are `type: "action"`, `kind: "ability"` (ultimate: `kind: "ultimate"`).
  Fields already in schema: `essence_cost`, `fury_cost`, `cooldown_s`, `unlock_stage`, `tags`,
  `category` (incl. `projectile`, `magic`), `hit_shape`, `radius_m`, `height_m`,
  `damage_split`, `size_policy`. `ActionDef.params` holds the raw record, so kind-specific fields
  can be read without editing `ActionDef`.
- Add to the action schema: `"effects": {"t": "array", "items": "dict", "item_fields": {...}}`
  with `type` enum `EFFECT_TYPES` (e.g. `damage, apply_status, heal_over_time, morale,
  projectile, grab, buff`), `status: _ref("status_effect")`, `magnitude`, `duration_s`,
  `radius_m`, `speed_mps`, `range_m`, `attribute` (enum ATTRIBUTES, for Runic Bolt's Intellect).
  Because `item_fields` rejects unknown keys, either list the union of effect fields or validate
  per effect type in `_semantic_action`. Add `"projectile"` (and maybe `"cone"` for Sweeping
  Blow's 120-degree arc, `"grab"`) to `HIT_SHAPES`; extend `_semantic_action` requirements per
  shape. Also add `"Projectile"`-related tags only if new (TAGS already has `Projectile`, `Grab`,
  `AoE`, `Magic`).
- Loadout: `data/player/giant.json` `loadout.slots` (exactly 8, `""` = empty; enforced by
  `_semantic_player`). New ability ids are pulled in by `GiantPlayer._build_controller`.

### Status effects
New type `status_effect` (`data/status/*.json`, ids `status.stone_skin`, `status.slow`,
`status.mend`, `status.fear`): fields `stacking` enum `["refresh_no_stack", "strongest_wins",
"independent"]`, `duration_s`, `tick_s` (tick-multiple warning via `_check_tick_multiple`),
`modifiers` dict (`keys_enum` e.g. `armor_flat, move_speed_mult, outgoing_damage_mult,
poise_damage_mult, health_per_tick`), `tags` (`items_enum: TAGS`), `boss_immune` bool.

### Enemies
`enemy` type exists; `ARCHETYPES` already lists all five + boss. Expect to add fields (all unknown
keys are errors): `preferred_range_m` [min,max] for archers (no vec2 type - use two numbers),
`projectile` ref, `xp_reward` (int), `loot_table` (`_ref("loot_table")`), `mass_class`,
`grab_immune`, boss `phases` (array of dict: `health_below`, `attacks`, `once`), `ignores_morale`.
`_semantic_enemy` checks attacks/weights; move per-archetype requirements there. Scenes still
need `tools/build_scenes.gd` builders.

### Items, loot tables
- `item` schema is only `stack_max`; add `category` enum (`material, quest, upgrade, weapon`),
  `quest_item` bool, `weapon` ref for weapon pickups.
- New type `loot_table`: `entries` array of `{item: _ref("item", true), count: _int(1),
  weight: _num(0.0)}`, `rolls: _int(1)`. Roll with `Sim.rng` only (determinism). Props keep the
  inline `loot` list; add an optional `loot_table` ref to the prop schema rather than replacing it.

### Quests and dialogue
- `quest`: `stages` (array of dict: `id`, `objective`, `complete_flag`), `rewards` (`xp: _int(0)`,
  `items` array of item refs), `resolution_flags` (strings), `accelerated_xp` bool (spec: label
  prototype pacing). Semantic check: unique stage ids.
- `dialogue`: `speaker`, `nodes` (array of dict: `id`, `text`, `choices` array of dict: `text`,
  `next`, `require_flags`, `set_flags`, `quest`, `reward_once_flag`). Semantic check: `next`
  points to an existing node id in the same record. Flags are strings; recommend a regex check
  `^(quest|world|dialogue)\.[a-z0-9_.]+$` in the semantic function.

### Shrines, checkpoints, levels/XP, talents
- `shrine` (or keep shrines purely as placed nodes with a `world_id` and give them a record for
  tuning): `checkpoint` bool, `allows_growth` bool, `max_stage`, `restores_resources` bool,
  `loadout_change` bool.
- `progression` (single record `progression.default`, add to `REQUIRED_RECORDS`): `xp_to_next`
  array of 19 ints (100 + 50*(L-1)), `level_cap: 20`, `attribute_points_per_level: 3`,
  `talent_points_per_level: 1`, `attribute_effects` (spec section 9 per-point values). Semantic:
  length 19, nondecreasing. Growth profiles already carry `required_level` and `unlocks`.
- `talent`: `tree` enum `["destroyer", "guardian", "primordial"]`, `max_rank`, `requires`
  (`_ref("talent", false, true)`), `modifiers` dict.
- `weapon`: sword/hammer are just new files (`WEAPON_FAMILIES` has them).
- `level`/`region` record for the Valley (optional): `scene` path string, `checkpoints` ids,
  `start_checkpoint`.

### Title menu with game modes
Add a small session autoload (proposal: `scripts/core/game_session.gd`, autoload `GameSession`,
placed after `WorldState`, before or after `Sim`) holding state that must survive
`reload_current_scene()`: `mode` (`"title" | "sandbox" | "valley"`), `character: Dictionary`
(live character state), `checkpoint_snapshot: Dictionary`, `pending_restore: bool`,
`quest_flags` (or put flags in WorldState - see below). Then in `main.gd`:
- Replace the hard-coded `SANDBOX_SCENE` instantiation (line 32) with `_start_mode(mode)`; mode
  `"title"` builds a `TitleMenu` (new `ui/title_menu.gd`) instead of world/HUD. Buttons:
  "New game (Valley)", "Continue" (enabled only if `SaveSlots.read()` is ok; show its
  `message`, e.g. "recovered from backup" / "newer version"), "Sandbox", Settings, Quit
  (hidden on web like pause menu line 107).
- Selecting a mode sets `GameSession.mode` and reloads the scene (reuse the reload path), so
  every mode starts from a clean tree.
- Autopilot/capture/tests: if `--autoplay`/`--scenario` (or a new `--mode=sandbox|valley`) is
  present, skip the title and go straight to that mode; default for these flags must remain
  sandbox so `tools/capture_tour.sh` and soak runs keep working.
- Web: the title "Start" click is a real click, so call `_capture_mouse()` from it (pointer lock
  is only granted inside a click).
- Pause menu: "Restart sandbox" -> mode-dependent ("Reload checkpoint" in Valley) + "Quit to
  title". Hud death hint (`ui/hud.gd` line 266, "Press Enter to restart the sandbox") becomes
  mode-dependent.

### Character saves (spec section 12 field list)
Proposal: `scripts/core/save_slots.gd` (`class_name SaveSlots`, static, thin wrapper over SaveIO)
with `PATH = "user://saves/valley_1.json"`, `SCHEMA_VERSION = 1`, `exists()`, `read() ->
{ok, data, message, source}`, `write(data) -> Error` (does `DirAccess.make_dir_recursive_absolute`
first), `validate(data) -> PackedStringArray`, and the same rejected-file copy Settings does
(`valley_1.schemaN.rejected.json`). Honor a no-persist flag like `Settings.persist` (tests and
autopilot must not write the user's slot). Document shape:
```json
{"schema_version": 1, "build_version": "0.1.0-m1", "saved_at_unix": 0,
 "character": {"id": "char.valley_1", "definition_id": "player.giant", "level": 1, "xp": 0,
   "attributes": {"strength": 10, ...}, "unspent_attribute_points": 0, "talent_points": 0,
   "talents": {}, "growth_stage": 1,
   "resources": {"health": 500, "stamina": 100, "essence": 100, "fury": 0},
   "inventory": {"item.wood_scrap": 1}, "weapon": "weapon.club",
   "loadout": {"light_chain": "...", "heavy": "...", "slots": ["", ...8], "ultimate": ""}},
 "quest_flags": {"quest.village.resolved_intimidate": true},
 "checkpoint": {"id": "shrine.hollow", "scene": "res://scenes/world/valley.tscn"},
 "world": {"schema_version": 1, "deltas": {...}, "inventory": {...}}}
```
`build_version` from `ProjectSettings.get_setting("application/config/version")`. Validate
loaded ids against GameData (unknown ability/item ids after a content change -> drop with a
message, never crash). Position comes from the checkpoint marker, not a saved Vector3 (if a
transform is ever saved, store arrays; `JSON.stringify` turns Vector3 into a string).

### Checkpoints and death -> reload checkpoint
- Taking a checkpoint (shrine interaction, out of combat, controller idle - spec: never during a
  grab/execution): build the snapshot dict above from the player (`entity.combatant.pools`:
  `health, stamina, essence, fury`; `controller.loadout`; `growth_stage`), progression state,
  `WorldState.to_save_dict()`, quest flags; store it in `GameSession.checkpoint_snapshot` and
  write it with `SaveSlots.write`.
- Death in Valley: emit a new reason (e.g. `"reload_checkpoint"`) or a new signal; in
  `_on_reset_requested` branch on mode: Sandbox keeps `WorldState.clear()`; Valley does
  `WorldState.from_save_dict(snapshot.world)`, restores flags/inventory/progression, sets
  `pending_restore`, then reloads the scene. After reload, the Valley scene/`main` spawns the
  player at the checkpoint marker and applies snapshot resources and stage (needs a GiantPlayer
  hook such as `apply_character_state(dict)` called after `_ready`; `ResourcePool` fields are
  plain vars, but max values derive from `Combatant.from_record` + attributes, so apply
  attributes/stage first, then current values).
- Continue from title = read the slot into `checkpoint_snapshot` and take the same restore path.

### Quest flags that prevent farming
Keep flags in the same snapshot as XP, inventory and world deltas so a death rolls all of them
back together. Grant every reward through a `try_set_flag(flag) -> bool` (true only the first
time), mirroring `WorldState.try_award_loot`. Intimidation sets its resolution flag without kill
XP. Simplest home: add `flags: Dictionary` to `WorldState` (bump `SCHEMA_VERSION` to 2 and make
`from_save_dict` accept 1 and 2 - it currently requires equality), or a separate `QuestState`
autoload included in the snapshot.

## 5. Hotspots and how to avoid edit conflicts

| Hotspot | Why |
| --- | --- |
| `DataValidator.RECORD_TYPES`, `schema_for` `match`, `validate_record` `match`, shared enum consts | Every new record type and every new field (unknown keys are errors). |
| `GameData.REQUIRED_RECORDS`, `load_all` cache building | Any id code depends on; any typed cache. |
| `main.gd` `_ready`, `_unhandled_input`, `_on_reset_requested` | Title/modes, checkpoints, death flow, new global keys, new UI layers. |
| `events.gd` | Every system adds signals. |
| `data/player/giant.json` | Loadout, attributes, weapon - touched by abilities, progression and items. |
| `tests/integration_suite.gd::before_each` | Every new global state must be reset here. |
| `ui/pause_menu.gd::_build_main`, `ui/hud.gd` | Mode-dependent buttons and hints. |
| `tools/build_scenes.gd` | Every new scene (single generator file). |
| `ActionDef` / validator duplicated `ATTACK_KINDS`, `TICK_RATE` | Must change in step. |

Proposal (do first, in one small serial commit before parallel M2 work):
1. Split schemas into per-type modules: `scripts/core/schemas/<type>_schema.gd`, each with
   `static func fields() -> Dictionary`, `static func semantic(d, ctx, out)` and
   `static func required_ids() -> Dictionary`. `DataValidator` keeps the generic checker and
   shared enums and gets a one-line-per-type registry `const SCHEMAS := {"action":
   ActionSchema, ...}`; `RECORD_TYPES` becomes `SCHEMAS.keys()`; `REQUIRED_RECORDS` is the merge
   of `required_ids()`. Keep all existing error strings identical. Then each feature owns its
   own schema file; the registry edit is a one-line append. (Note `_check_fields` /
   `_check_value` are "private" statics - make them public helpers.)
2. Events: pre-declare the M2-M5 signals in one commit (status_applied/expired,
   projectile_spawned, grab_started/ended, xp_gained, level_up, quest_flag_set,
   checkpoint_saved, checkpoint_loaded, dialogue_choice, item_added), grouped by section.
3. main.gd: move flow into `GameSession` + a `GameFlow`/mode-start function so features register
   UI/world builders instead of editing `_ready`; one owner for `main.gd`.
4. Assign single owners for `giant.json` and `build_scenes.gd`, or let features add new
   builder functions only appended at the end with one call each in `_ready`.

## 6. Pitfalls and gotchas

- `Events.sandbox_reset_requested` comment says "debug=true also clears world deltas", but the
  signal has only `reason` and `main._on_reset_requested` always clears `WorldState` - including
  `restart_after_death`. A Valley death must not do this.
- `reload_current_scene` re-runs `main._ready`; autoload state persists (WorldState,
  `Settings.session`, `Sim.tick` keeps counting, `Sim.rng` is not reseeded). Put any
  cross-reload state (mode, pending restore) in an autoload, never in `main`.
- `GameData.get_record` returns the live dictionary: mutating it (e.g. writing loadout changes
  into `player.giant`) silently changes "data" for the session. Copy first; character state
  belongs in the save, not in records.
- `load_all` replaces `_actions` with new `ActionDef` objects; holders of old references (e.g.
  `CombatController.library`) keep stale ones. Tests call `load_all(TMP_DATA)` and restore in
  `after_each`.
- Validator early-returns on wrong/missing `type` and future `schema_version`, so other errors in
  that file are not reported until fixed. Duplicate-id records are dropped after validation.
- `dict` specs with `fields` ignore `keys_enum/values`; `array` `items: "number"` rejects
  negatives; no `int` array; refs only exact-type; `vec3` only.
- `DataValidator._semantic_input` requires a default binding for every `InputBindings.ACTIONS`
  entry: a new input action needs both `InputBindings.ACTIONS` (and LABELS) and
  `data/input/default_bindings.json`. `interact` already exists (label "Interact / grab").
- Non-tick-multiple timings are warnings and get rounded in `ActionDef` - silent tuning drift.
- `SaveIO.write_json` fails if the parent directory is missing (`user://saves/`). The backup is
  refreshed only if the old main loads at the new data's `schema_version`. `read_json` checks the
  envelope only. The future-version "keep as rejected" logic lives in `Settings.load_settings`,
  not SaveIO - replicate it for character saves.
- JSON round-trips lose types: numbers may come back as float (always `int()` them), Vector3 is
  stringified, dictionary keys are strings. Store vectors as arrays.
- `WorldState.from_save_dict` requires `schema_version == SCHEMA_VERSION`; bumping the version
  breaks old saves unless a migration is added. `WorldState.inventory` is the only inventory and
  is wiped by `clear()`; for Valley, inventory belongs in the character snapshot.
- Web: `user://` is browser storage (IndexedDB); temp-file + rename persistence is untested in
  the browser - verify a save survives a page reload. Quit buttons are hidden on web; pointer
  lock needs a click; losing lock opens pause (`main._process`), so a title menu must not
  re-trigger this (only check while a mode is running).
- `main._input/_process/_notification/_unhandled_input` all early-return when `pause_menu ==
  null`; a title screen without a PauseMenu inherits that (fine), but code checking
  `autopilot != null` to skip mouse capture must keep working.
- `test_mouse_capture.gd` preloads `res://scripts/main.gd`; `main.gd` must stay parse-safe in
  isolation and keep `static func is_capture_click`.
- `.tscn` files are generated by `tools/build_scenes.gd`; never hand-edit, regenerate with
  `godot --headless --path . res://tools/build_scenes.tscn`.
- `GiantPlayer` reads `growth_profile` from the record in `_ready` and copies loadout into the
  controller; there is no API yet to apply a saved stage/loadout/resources after spawn - this is
  needed for checkpoints and shrine growth (M3).
- `OUT_OF_WORLD_Y` respawn uses `spawn_transform` captured in `GiantPlayer._ready`; with
  checkpoints, set the player transform before/at `_ready` or update `spawn_transform`.
