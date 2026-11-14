# Brief: growth stages 4-6 and the content an open world needs (M7+ planning input)

Scope: how the shipped Valley build (0.5.0-m5) extends to growth stages 4-6 (spec §9: 36 / 48 / 62 ft
= 10.97 / 14.63 / 18.90 m, unlock levels 7 / 9 / 11), progression to about level 12 with the three
talent trees and two or three ancestries, a larger ability library with stage evolutions, new weapon
families and Giantforge refits, the enemy roles and bosses of an open world (pike and shield
formations, cavalry, siege crews, trolls, rival giants), peaceful resolutions beyond Thornwick, and
the save migration from a finished Valley game. The owner's direction: the Valley stays as the
opening tutorial, then the game opens into an open world; that overrides the spec's deferral of
open-world streaming. World streaming, terrain and region layout belong to the open-world brief;
this brief covers what growth, combat, enemies, progression and saves need from it.

Method: the code and docs were read on `claude/hopeful-gauss-0f323t` (identical to `main`); then a
copy of the repository (no `.git`) in the scratch folder got three test growth profiles and four lab
suites or scenes, and ran them with the project's own tools (Godot 4.6.3-stable, headless with
`--fixed-fps 60`, a debug build, 4 shared CPU cores; draw calls under Xvfb with Mesa llvmpipe). No
tracked file was changed. Lab files are listed in §7.

Every statement of fact is marked **VERIFIED** (read in the code or data at the cited place, or
measured by a lab run named here) or **ASSUMED** (reasoning, documentation, or not confirmed by a
run). Recommendations (§4-§6) are proposals built on the facts they cite.

## 0. The short version

1. **The growth framework is data-driven up to stage 10; the content is not.** Three new
   `growth_profile` records (stages 4-6) validated with 0 data errors and the giant debug-grew 1 -> 6
   with capsule, resources, camera, lock range, weapon geometry and hurtboxes following (VERIFIED, lab
   `test_zz_growth_lab`). What stays at stage-3 values is in data and small constants: Footfall's
   radius stops at 5 m, Thunder Roar's at 6 m, Boulder Hurl's range at about 26.5 m, weapons fit at
   most stage 3, the forge allows one upgrade step, shrines grow to stage 3, the bot's engage radius
   is clamped to stage 3, and the navmesh "giant" layer is baked for a 2.0 m radius (VERIFIED, §1).
2. **Light attacks 1-2 and the heavy still land from the giant's feet to its reach at stages 4-6**
   with k-scaled geometry and arc tilts of -16 / -20 / -24 degrees plus P17b's vertical aim: real
   locked swings connected with soldiers and wolves at contact + 0.3 m, mid-reach and 0.9 x reach and
   missed at 1.1 x reach for every stage 1-6 (VERIFIED, lab). **Light 3 cannot**: its arc has a dead
   zone at the feet that no tilt removes (stage 6: nothing between 4.05 and 8.65 m), and the fixed
   7.5 m tree's heavy misses soldiers at stages 5-6 (VERIFIED). Stage 4-6 weapons need their own
   movesets; the refit is the natural place for them.
3. **Small targets become specks**: a soldier under lock is 29 / 22 / 17 px tall at 1080p at stages
   4 / 5 / 6, a wolf 14 / 11 / 8 px (VERIFIED, lab framing). Individual 1.8 m humans stop being good
   lock targets at stage 4, which supports the spec's formations-as-lock-groups rule.
4. **Forty soldiers fit the CPU budget but not the draw-call budget.** Through the existing
   EncounterDirector (budget raised to 40 by data, all at AI tier 0): 40 soldiers holding formation
   against a stage-4 giant cost 3.98 ms CPU per tick at p95 (4.39 ms with a stage-6 giant swinging
   into them), against the 8 ms budget; rendered, 20 soldiers drew 1,059 draw calls and 40 drew
   2,019 (about 48 per rig with sun shadows), against 250; as one-box proxies 40 drew 219 (VERIFIED,
   lab `formation_lab`). Formations need a shared crowd renderer, not more rigs.
5. **Today's formation is one line per encounter**, 3 m apart: 40 soldiers held a 103 m wide line
   (VERIFIED, lab). And morale makes any 1.8 m unit flee after the first nearby death once the giant
   is 4x its height: 70 - 35 (awe) - 15 (one ally death x1.5 outmatched) = 20 < 25 (VERIFIED from the
   constants). Stage 4-6 formation threats need ranks, a banner that anchors morale, and pikes that
   out-reach the brace's 3 m.
6. **Enemies can only target the player** (`EnemyActor._target()` returns the PLAYER-team entity,
   VERIFIED), so "protect smaller peoples" (raiders fighting villagers) and siege crews attacking
   walls need a target provider first.
7. **Siege hits from small crews are size-scaled to nothing**: poise and knockback use attacker
   height over defender height, with no override (VERIFIED), so a bolt credited to a 1.8 m crewman
   deals 0.25x poise (the clamp's floor) to a stage-4+ giant (VERIFIED arithmetic). The `-20` siege morale event exists and is tested, but
   nothing raises it (VERIFIED).
8. **Talents and ability upgrades fit the data model as new records, not runtime patches**:
   rank and evolution records with their own ids (cooldowns are already per id), talent records with
   passive modifiers applied in the one place `Combatant` reads modifiers, ancestries as records with
   modifiers chosen when the world opens (§5).
9. **Save migration is small**: the save document is schema 1, its world block schema 2; Valley world
   ids are already `valley.`-prefixed; add a `migrate()` before `validate()` in `SaveSlots`, bump to
   2, keep the slot name and the project name (the user folder is derived from it) (§6).
10. **Hotspots** (§5.6): `data_validator.gd` (shared enums), `enemy_actor.gd` and `enemy_brain.gd`,
    `encounter_director.gd`, `player_targeting.gd`, `player_progression.gd` / `progression.gd`,
    `game_session.gd`, `save_slots.gd`, `quests.gd`, `ui/hud.gd`, `bot_combat.gd` / `valley_bot.gd`.

## 1. Where stages 1-3 are hard-wired

What already generalises (all VERIFIED by reading, and exercised by the lab growing 1 -> 6):

- `growth_profile` schema accepts `stage` 1-10 and `required_level` 1-20
  (`scripts/core/schemas/growth_profile_schema.gd:13-14`).
- `PlayerGrowth` looks profiles up by stage (`profile_for_stage`, `max_stage`), checks clearance with
  the new capsule, and applies everything through `GiantPlayer.set_profile` in one tick: stage gating,
  capsule and floor snap, camera (`CameraRig.apply_profile` keeps the zoom fraction), nav layers, then
  every component (`PlayerAttack.refresh_geometry`, `PlayerTargeting.apply_lock_profile`, and
  `PlayerGrowth._sync_body`: height, resource bonus with fractions kept, rig scale k = height /
  3.6576, hurtboxes and anchors rebuilt from their stage-1 sizes x k)
  (`scripts/actors/player/player_growth.gd:257-277, 373-437`; `scripts/actors/giant_player.gd:415-433`).
- `PlayerGrowth.PERMISSION_TEXT` and `DataValidator.INTERACTION_PERMISSIONS` already name
  `gate_breach`, `formation_sweep`, `siege_disruption`, `monster_grapple`, `titan_execution`
  (`player_growth.gd:49-58`, `scripts/core/data_validator.gd:73-74`).
- The Citadel Gate (`prop.gate_fortified`, 12 m, health 2,000, armour 40) already requires
  `min_growth_stage` 4 and `requires_permission` `gate_breach`, has an intact -> breached stage that
  removes collision and enables nav links, and stands at (190, 0, -60) on the Valley's east edge
  (`data/props/gate_fortified.json`; `tools/data/valley_layout.json:212`).
- Stages 2 and 3 are exact k-scalings of stage 1: `weapon_pivot_m`, `attack_origin_m`,
  `arm_length_m` and `weapon_scale` equal the stage-1 values x k (stage 3: 0.82 x 2.1667 = 1.78,
  2.9 x 2.1667 = 6.28, 1.5 x 2.1667 = 3.25) (`data/growth/growth_0[1-3].json`).

What is fixed at stage-3 values, and what stage 4-6 needs:

| # | Item | Where | Status | Stage 4-6 consequence |
| --- | --- | --- | --- | --- |
| 1 | Footfall `radius_by_stage_m` [3, 4, 5]; the runner uses the last entry beyond the list | `data/abilities/heavy_footfall.json`; `scripts/actors/attack_runner.gd:144-157` | VERIFIED (lab: 5.0 m at stages 4-6) | 5 m from the centre of a 3.7 m-radius giant reaches 1.3 m past its own capsule. Extend the list or evolve the ability (§5.2). |
| 2 | Thunder Roar `radius_m` 6, Boulder Hurl `range_m` 25 (fixed) | `data/abilities/thunder_roar.json`, `boulder_hurl.json` | VERIFIED; Hurl measured: a target 28 m away is in range from stage 4 (the launch point moves forward 0.6 x k), 32 m is out at every stage | Roar is inside the stage-5 melee reach; Hurl cannot answer siege engines at 50-100 m. |
| 3 | Light 3's arc | `data/abilities/light_3.json` | VERIFIED (lab: §2.3) | Dead zone at the feet at stages 4-6 for any tilt. |
| 4 | The tree is fixed-size (`scales_with_growth` false, 7.5 m) | `data/weapons/tree_oak.json` | VERIFIED (lab: `tree_heavy` misses soldiers at stages 5-6) | Needs a bigger tree or a scaled variant. |
| 5 | Every weapon fits at most stage 3 (`fit_max_stage` 2 or 3); beyond it the weapon keeps its last fitted size | `data/weapons/*.json`; `player_equipment.gd:73-118` | VERIFIED | Without refits a stage-6 giant swings a stage-3-sized club. |
| 6 | The forge reforges once: an `upgrade.to` weapon may not have an upgrade of its own | `scripts/progression/progression.gd:273-297` | VERIFIED | Multi-step refits are a data error today. |
| 7 | Shrine `max_stage`: Kingsfall 3 (schema allows 1-10) | `data/shrines/shrine_kingsfall.json`; `shrine_schema.gd:22` | VERIFIED | New shrines (data) in the open world. |
| 8 | Navmesh layers: human 1 (r 0.6), large 2 (r 1.5), giant 4 (r 2.0, h 8.5), small giant 8 (r 0.9); the four regions are stacked 0.35 / 0.25 / 0.15 / 0.0 m above the ground so nav links attach per layer | `tools/builders/valley.gd:24-31, 74-83` | VERIFIED | A stage-4+ capsule (r 2.2-3.7) does not match the giant layer. The player never paths (it has no NavigationAgent3D, `giant_player.gd:67-70`), so only the bot and AI giants need a new layer; the stacking trick has no room left below 0.0 m (ASSUMED). |
| 9 | The bot's engage radius `[16, 22, 28]` clamped to stages 1-3; ValleyBot hard-codes Valley ids, policies and the tree weapon | `scripts/debug/bot_combat.gd:47, 357`; `scripts/debug/valley_bot.gd:46-95, 1125` | VERIFIED | Its reach band is already geometry-generic (`bot_combat.gd:582-600` uses `PlayerAttack` and `AttackGeometry`). |
| 10 | Poise scale clamp 0.25-2.0 | `scripts/combat/combat_rules.gd:12-13, 54` | VERIFIED (lab: 2.0 against a soldier at every stage 1-6) | Growth no longer adds poise pressure on humans beyond stage 1; damage still grows (M_size 1.639 / 1.866 / 2.094 at stages 4-6, VERIFIED lab). |
| 11 | `step_height_m` only sets `floor_snap_length`; there is no step-up | `giant_player.gd:170-171` | VERIFIED | A 62 ft giant is stopped by any vertical wall it cannot slide up (46 degree floor angle). Low walls must be breakable, flattenable or slopes. |
| 12 | Vertical aim lifts at most to +16 degrees; profile tilts are limited to -30..0 | `player_attack.gd:40-41`; `growth_profile_schema.gd:55-59` | VERIFIED | Enough for lights 1-2 and the heavy at -24 (§2.3); not a fix for light 3. |
| 13 | `CosmeticProp` flattens from stage 2 | `scripts/world/cosmetic_prop.gd:21` | VERIFIED | Fine as is. |
| 14 | Enemies target only the player | `scripts/actors/enemy_actor.gd:200-205` | VERIFIED | No NPC-vs-NPC fights, no crews attacking walls. |
| 15 | Ad-hoc formation = one line per encounter, `formation_spacing_m` 3 m apart; markers searched within 25 m | `enemy_actor.gd:887-1001` | VERIFIED (lab: 40 soldiers held a line from x -51.6 to +51.5) | No ranks or blocks. |
| 16 | `_line_members()` and `_has_leader_now()` scan the whole `enemies` group per call (perception at 5 Hz; slots refresh every 0.5 s) | `enemy_actor.gd:790-810, 975-991`; `enemy_brain.gd:409, 727-733` | VERIFIED (read); measured cost acceptable at 40 (§2.6) | O(N^2); keep an eye on it beyond 40. |
| 17 | Awe -35 at 4x height, ally death -10 x1.5 outmatched, flee below 25, start 70 | `data/enemies/soldier.json`; `enemy_brain.gd:394-415, 143-149, 182` | VERIFIED | Humans break after one death against any stage-3+ giant. HOW_IT_PLAYS measured flee or rout 55 % of engaged time at stage 3 (VERIFIED, `docs/DECISIONS.md` row 26). |
| 18 | `ARCHETYPES` = soldier, archer, mage, wolf, ogre, boss, training; weapon `visual_shape` enum has no axe or fists (families already list them); `PROJECTILE_VISUALS` bolt, boulder, arrow, thrown_body; `MASS_CLASSES` small, medium, large, immovable | `data_validator.gd:61-83`; `weapon_schema.gd:13, 31` | VERIFIED | New roles and weapons edit shared enums: one package should add them all up front, as M2 did ("Every value the M2-M5 plan needs is declared here now", `data_validator.gd:52`). |
| 19 | Poise and knockback use `attacker_height_m` / defender height; no per-action override | `scripts/combat/damage_resolver.gd:78-79, 114`; `hit_factory.gd:54-55` | VERIFIED | Siege attacks need an override (spec §7 allows one). |
| 20 | The `siege_destroyed` morale event (-20, applied unscaled) exists; nothing raises it | `enemy_brain.gd:411-415`; `enemy_actor.gd:764-767` | VERIFIED | Wire it to siege engines (§4.3). |
| 21 | Statuses always expire (duration from the def or the call) | `scripts/combat/status_set.gd:25-40` | VERIFIED | Permanent talent or ancestry bonuses are not statuses (§5.3). |
| 22 | The ancestry schema has no fields; one neutral ancestry; talents are a counter (+1 per level) | `scripts/core/schemas/ancestry_schema.gd`; `data/player/ancestry_neutral.json`; `data/progression/progression_default.json` | VERIFIED | §5.3-§5.4. |
| 23 | `FactionState` is generic over `faction.<f>.*` flags but its HUD texts are a code constant for "village" only | `scripts/world/faction_state.gd:1-47` | VERIFIED | Move texts to faction records. |
| 24 | Quests run only in the Valley mode; `slice.completed` opens the end screen | `scripts/quests/quests.gd:5-6, 732-800`; `data/quests/quest_main.json:92` | VERIFIED | The world needs its own mode or a generalised "campaign" mode (§6). |
| 25 | The save document is `SCHEMA_VERSION` 1 (its world block 2); `validate()` refuses other versions; there is no migration step | `scripts/core/save_slots.gd:19, 130-157`; `scripts/core/world_state.gd:15` | VERIFIED | §6. |

## 2. Lab results

### 2.1 The test profiles

Proposed and exercised (data only, `growth_04-06.json` in the lab copy; VERIFIED they validate and
apply). Geometry keeps the exact k-scaling of stages 1-3; the rest extends the stage 1-3 trends.

| Field | Stage 4 | Stage 5 | Stage 6 |
| --- | --- | --- | --- |
| Height (k) | 10.9728 m (3.0) | 14.6304 m (4.0) | 18.8976 m (5.1667) |
| Required level | 7 | 9 | 11 |
| Capsule radius / height | 2.2 / 10.97 m | 2.9 / 14.63 m | 3.7 / 18.90 m |
| Walk speed, acceleration, turn | 7.1 m/s, 21, 300 deg/s | 7.6, 18, 250 | 8.1, 16, 210 |
| Melee reach (tested) | 8.6 m | 11.0 m | 13.6 m |
| Weapon pivot / attack origin / arm / weapon_scale | (2.46, 8.7, 0) / 7.8 / 4.5 / 3.0 | (3.28, 11.6, 0) / 10.4 / 6.0 / 4.0 | (4.24, 14.98, 0) / 13.43 / 7.75 / 5.167 |
| Arc pitch offset | -16 | -20 | -24 |
| Camera distance (zoom) / pivot / shoulder / orbit scale | 15.5 (12-20.5) / 10.04 / 2.2 / 3.0 | 19.5 (15-26) / 13.39 / 2.9 / 4.0 | 23.5 (18-32) / 17.29 / 3.7 / 5.17 |
| Lock range / half-angle | 55 m / 45 | 65 m / 42 | 80 m / 40 |
| Resource bonus (health / stamina) | +450 / +30 | +600 / +40 | +800 / +50 |
| Grab reach / lunge / capacity | 9.1 / 4.5 / medium | 11.5 / 6.0 / large | 14.1 / 7.5 / large |
| New permission | `gate_breach` | `formation_sweep` | `siege_disruption` |

Measured on the giant after growing (VERIFIED, lab): health maximum 950 / 1,100 / 1,300; stamina 130
/ 140 / 150; weapon length 5.55 / 7.40 / 9.56 m and hit radius 1.35 / 1.80 / 2.33 m (a club with
`fit_max_stage` raised to 10 in the lab); camera arm 15.8 / 19.9 / 24.2 m after the zoom-fraction
carry-over from stage 3.

### 2.2 Clearance

- The giant grew 1 -> 2 -> ... -> 6 on the integration floor with every check passing (VERIFIED).
- In the Valley, `check_clearance` passes for the stage 3, 4, 5 and 6 capsules at all seven respawn
  points: the four shrines and the three waystones (VERIFIED, lab `test_e_valley_clearance`).
- Along the Valley's giant-layer paths (links open), capsule overlaps every 2 m (VERIFIED, lab 3):

| Route (path length) | Stage 3 | Stage 4 | Stage 5 | Stage 6 |
| --- | --- | --- | --- | --- |
| Hollow -> Grove (243 m) | 0 / 152 | 13 / 152 | 23 / 152 | 30 / 152 |
| Hollow -> Thornwick (276 m) | 1 / 173 | 23 / 173 | 48 / 173 | 59 / 173 |
| Thornwick -> Kingsfall (187 m) | 6 / 116 | 6 / 116 | 22 / 116 | 26 / 116 |

  The stage-4+ overlaps start at the Hollow's exit (x -136, z 107-118). The six samples at x 93-99
  and 124 (z -20) that fail even at stage 3 are most likely a probe artefact at the bridge deck and
  the practice gate frame, since stage-3 giants cross there in every bot run (ASSUMED). Conclusion: the
  Valley is a stage 1-3 space; a stage-4+ revisit needs widened passages or breakable walls
  (ASSUMED from the overlap counts; not walked).

### 2.3 Reach against 1.8 m soldiers and 0.9 m wolves

Swept-weapon reach bands from the giant's centre (`PlayerAttack.sweep_reaches` /
`aimed_offset`, the same code the game uses; club scaled to the stage). "Contact" = the two capsules
touching. VERIFIED, lab `test_a`:

| Stage (contact vs soldier) | Light 1, default tilt | Light 1, vertical aim | Light 3, vertical aim | Heavy |
| --- | --- | --- | --- | --- |
| 3 (2.0 m) | 2.0-5.0 | 2.0-7.0 | 2.5-6.9 | 2.0-7.0 |
| 4 (2.55 m) | 2.55-6.85 | 2.55-9.15 | **4.25**-8.85 | 2.55-9.15 |
| 5 (3.25 m) | 3.25-8.25 | 3.25-11.55 | **6.25**-11.05 | 3.25-11.55 |
| 6 (4.05 m) | 4.05-9.35 | 4.05-14.35 | **8.65**-13.45 | 4.05-14.15 |

Wolves behave the same within 0.1-1 m (stage 6 light 1 aimed 4.1-13.5 m, VERIFIED). Every band is one
contiguous interval (VERIFIED: two transitions each). Light 3 at the default tilt misses soldiers
entirely at stages 4-6, and scanning its tilt from 0 to -44 degrees in 4-degree steps never closes
the gap: its best band at stage 6 is 8.65-10.95 m at -8 degrees, and from -12 degrees down it hits
nothing (VERIFIED, lab 2). The tree (7.5 m, fixed): `tree_heavy` reaches soldiers 5.65-10.65 m at
stage 4 and not at all at stages 5-6 (VERIFIED, lab 2).

Real swings (locked, soldier or wolf with AI off, one swing each; VERIFIED, lab `test_b`): light 1 and
the heavy connected at contact + 0.3 m, at mid-reach and at 0.9 x reach, and missed at 1.1 x reach, at
every stage 1-6 against both targets (96 swings). Damage of a non-crit light on a soldier: 66 / 75 /
84 at stages 4 / 5 / 6 (VERIFIED).

### 2.4 Lock-on and framing

- Lock acquisition straight ahead (VERIFIED, lab `test_c`): stage 4 locks at 45 m and not 60 m; stage
  5 at 60 m and not 75 m; stage 6 at 75 m and not 90 m; i.e. the profile's `lock_range_m` holds.
- Framing a target 2 m beyond contact (headless viewport 1280 x 1280 with the default 75 degree
  vertical FOV, heights rescaled to a 1080 px tall screen; VERIFIED). The lock framing clamps at its
  small-target pitch limit of -48 degrees for every case but the stage-1 soldier (-44.5)
  (`camera_rig.gd:27`, VERIFIED):

| Stage | Free look (pitch -18): soldier / wolf | Locked: soldier / wolf | Camera height when locked |
| --- | --- | --- | --- |
| 1 | 112 / 54 px | 91 / 41 px | 7.9 m |
| 3 | 62 / 30 px | 40 / 19 px | 16.3 m |
| 4 | 47 / 23 px | 29 / 14 px | 21.8 m |
| 5 | 37 / 18 px | 22 / 11 px | 28.2 m |
| 6 | 30 / 15 px | 17 / 8 px | 35.3 m |

  Every target stayed on screen (VERIFIED). Whether 8-17 px is readable is a human judgement (NOT
  RUN); the numbers say single humans and wolves stop being primary lock targets at stage 4-6.

### 2.5 Boulder Hurl

The range check uses the horizontal distance from the launch point (`player_attack.gd:262-294`,
VERIFIED); the launch point rises to 9.6 / 12.8 / 16.5 m at stages 4 / 5 / 6 (VERIFIED, lab `test_d`).
Effective horizontal reach stays about 26.5 m plus 0.6 x k forward (VERIFIED). Siege engines and
archers on walls at 40-100 m need a stage-scaled ranged answer.

### 2.6 Twenty to forty soldiers through the director and its LOD

`lab/formation_lab.tscn` loads `scenes/test/director_test.tscn`, raises `level.director_test`'s
`max_active_enemies` to 40, switches its own encounters off and adds one encounter of N soldiers in
ranks of 10 (one commander); the giant (invulnerable) stands 22 m or 5 m from the front rank. 600
warm-up ticks, then 1,800 measured ticks (30 s), PerfProbe's `cpu_tick_ms` and `sim_ms`. Every member
was at AI tier 0 for the whole run (engaged, within the director's 40 m `near_m`) (VERIFIED):

| N | Giant | Stand | CPU per tick p50 / p95 / p99 (ms) | `Sim.step` p50 / p95 | States (sampled) |
| --- | --- | --- | --- | --- | --- |
| 12 | stage 1 | 22 m | 1.31 / 1.97 / 2.61 | 1.05 / 1.68 | approach, reposition |
| 12 | stage 4 | 22 m | 0.98 / 1.48 / 1.72 | 0.71 / 1.09 | hold 87 % |
| 20 | stage 1 | 22 m | 2.11 / 3.24 / 4.23 | 1.76 / 2.81 | approach, reposition |
| 20 | stage 4 | 5 m | 1.66 / 2.46 / 3.45 | 1.27 / 1.91 | hold, brace strikes |
| 40 | stage 1 | 22 m | 4.48 / 6.66 / 8.57 | 3.98 / 5.96 | approach 61 %, reposition 34 % |
| 40 | stage 4 | 22 m | 2.85 / 3.98 / 4.94 | 2.26 / 3.12 | hold 80 % |
| 40 | stage 4 | 8 m, swinging | 3.13 / 4.58 / 5.74 (max 11.9) | p95 3.77 | hold |
| 40 | stage 6 | 8 m, swinging | 3.04 / 4.39 / 5.72 (max 12.2) | p95 3.63 | 4 killed, then flee and stagger |

All VERIFIED (container, debug build, headless). A soldier costs about 0.10 ms per tick while
approaching and about 0.055 ms while holding (VERIFIED, differences of the rows). The brace counter
still lands on a stage-4 giant standing 5 m away (24 enemy hits in 30 s, VERIFIED). The single-threaded
web build will cost more per soldier (ASSUMED, not measured; WASM is usually slower than native).

Draw calls, rendered (Xvfb, llvmpipe, `--graphics=low`; `level.director_test`'s low preset keeps sun
shadows to 60 m), the stage-4 camera on the formation (VERIFIED, lab render runs):

| Soldiers | Full rigs | One-box proxies |
| --- | --- | --- |
| 1 | 147 | 102 |
| 12 | 675 | 135 |
| 20 | 1,059 | 159 |
| 40 | 2,019 | 219 |

About 48 draw calls per rig here (33 in the Valley, whose low preset has no sun shadows,
`docs/PERFORMANCE.md`, VERIFIED) and 3 per proxy (VERIFIED). Draw-call counts depend on the scene, not
on the GPU's speed (ASSUMED, as PERFORMANCE.md states).

## 3. What the numbers mean for design

- CPU allows 40 full soldier actors in one fight on desktop; draw calls allow about 4 (VERIFIED §2.6
  plus PERFORMANCE.md). The constraint is rendering, so a formation's members can stay real
  `EnemyActor`s (hurtboxes, damage, morale, deaths all work today) while most are drawn by one shared
  instanced mesh (ASSUMED feasible: MultiMesh is already used for scenery, `tools/builders/valley.gd`
  header, VERIFIED).
- Humans should be a crowd, not opponents, from stage 4: tiny on screen (§2.4), awed and broken by one
  death (§1 row 17), 2 attack tokens at a time (`data/enemies/soldier.json` `max_attackers` 2,
  VERIFIED). Threat at stages 4-6 comes from organised groups (pikes, shields, ballistae, catapults,
  cavalry charges) and from big creatures (trolls, rival giants).
- Movesets, not tilts, are the remaining reach problem (§2.3).

## 4. Recommendations: combat and enemies

### 4.1 Growth profiles 4-6

Ship §2.1's values as the starting point (they are tested), plus: per-action tilts only where a band
needs them; `nav_layers` 16 (a new "titan" layer, radius about 3.0 m, cell 1.0 m) used by the bot and
AI giants, with the open-world builder baking it; `footstep_shake` 0.18 / 0.24 / 0.30; `unlocks` the
stage evolutions of §5.2. Add a `target_rules` block (spec §9 lists "target rules" as a profile field):
`{"formation_lock": true}` from stage 4. Extend `ENGAGE_RADIUS_M` by deriving it from the profile
(about 2.5 x melee reach) instead of a table. Add a step-up or a "titan stepover" rule: walls under
about 0.12 x height on a layer a stage-4+ giant flattens or ignores (cosmetic and fence layers),
since there is no step-up (§1 row 11).

### 4.2 Formations as lock groups (spec §5: selectable groups at stages 4-6)

- **Data.** An encounter gains `formations: [{"id", "kind": "pike" | "shield" | "line" | "crew",
  "banner": <entity id>, "files", "rank_spacing_m", "file_spacing_m", "facing": "threat"}]` and a
  spawn's `formation` id. The director owns a `Formation` object per entry: members, slot grid (ranks
  x files around a pivot that turns to face the threat), cohesion (living, non-fleeing share) and its
  anchor (front centre at chest height). This replaces the one-line `_line_slot` for members of a
  formation and removes the per-call group scans (§1 rows 15-16).
- **Targeting.** When the profile has `formation_lock`, `PlayerTargeting.gather_candidates` folds the
  members of each living formation into one candidate `"formation:<id>"` (anchor = the formation's
  anchor, threat = the highest member threat, visible = any member visible, distance to the anchor);
  singletons stay candidates. `LockOnTracker` needs no change (it is pure and works on ids and
  snapshot dictionaries, `lock_on_tracker.gd`, VERIFIED). `locked_entity()` resolves a formation id to
  its **focus member** (the living member nearest the giant's attack origin), so the camera's
  `lock_target`, the vertical aim and grabs keep receiving a `CombatEntity` (46 references to the lock
  in 15 files, VERIFIED by grep). The lock releases as `target_died` when the formation has no
  living, non-routed member. Left/right switching moves between formations and singletons. The HUD
  lock line shows the formation's name and count.
- **Threat at stage 4.** Pikes: a brace with 5-6 m reach (the soldier's is 3 m + the giant's radius,
  `soldier_brace.json`, VERIFIED) and leg poise damage; shields: a frontal guard that blocks lights
  (the soldier guard mechanism exists, `soldier.json` `guard`, VERIFIED) and is broken by heavies,
  stomps and sweeps. **Morale**: while the banner lives, awe and ally-death losses count x0.5 and
  formation units regroup; the banner's death is `commander_died` (-25 x1.5, VERIFIED constant).
  Formation units start at 90 morale.
- **Formation sweep (stage 5).** A Sweeping Blow evolution: sector pulse at 1.2 x melee reach, extra
  poise and -10 morale per member hit, gated by `unlock_stage` 5 and `formation_sweep`.
- **Rendering.** A crowd renderer per formation: one MultiMesh per material and pose (hold, brace,
  advance, flee) fed each frame from the members' transforms; members within about 20 m of the giant,
  or striking, are promoted to their full rig. This fixes the dominant cost (§2.6) and is the
  "distance LOD for rigs" the handoff deferred (`docs/M2_M5_HANDOFF.md` §7, VERIFIED).
- **Budget.** Count a formation's members against a separate `max_formation_members` (desktop 40,
  web about 20, ASSUMED until measured on the web), not the 12 individual combatants.

### 4.3 Siege engines and the -20 morale event

- `SiegeEngine`: a `BreakableProp` (structural, saved stage and health, nav-link and loot behaviour
  already exist, VERIFIED `breakable_prop.gd`) with an `AttackRunner` that fires `projectile` actions
  (ballista: fast straight bolt with an aim line; catapult: arc with splash, the boulder visual) only
  while crewed (at least one living crew member within 4 m). It takes the ranged tokens and launch
  slots, so launches at the giant stay at least 1.0 s apart (decisions 24-25, VERIFIED in
  `docs/DECISIONS.md`); telegraphs follow the existing rule (windups of 0.8 s or more must be
  telegraphed, VERIFIED decision 25).
- Crew: soldiers with a `crew` outmatched behaviour (stay at the engine, reload; flee when it
  breaks).
- Destruction: the engine calls `on_morale_event("siege_destroyed")` on every enemy of its encounter
  or faction within about 30 m: -20, unscaled (VERIFIED constants). Add a 2 s debounce per unit so a
  battery's three engines do not stack beyond intent.
- Size override: add `attacker_height_override_m` (or `size_class: "siege"`) to the action schema and
  feed it to `HitEvent.attacker_height_m`, so a ballista bolt has the poise and knockback of, say, an
  8 m attacker (§1 row 19). Without it the engines cannot stagger a big giant.
- Siege disruption (stage 6): grabbing an engine needs a prop-grab path, since the grab shape is
  built for actors with `grab_attach` (ASSUMED from `PlayerGrab`'s design in DECISIONS row 16, not
  traced in code); throwing it reuses the thrown-body projectile (VERIFIED it exists, decision 16).

### 4.4 Other roles and bosses

- **Cavalry** (rider and horse as one actor, about 2.6 m, run 10-12 m/s): the existing scripted
  `motion` charge plus the boss's `body_sweep` hit shape (VERIFIED both exist), then wheel away and
  re-charge; outmatched behaviour `harass` (only WolfBrain implements it today, VERIFIED
  `enemy_brain.gd:639-642`). Open ground; nav layer "large".
- **Trolls** (5-6 m): reuse `OgreEnemy` / `OgreBrain` (super armour, punish windows, VERIFIED); a
  regeneration status (`heal_per_tick` is a status modifier, VERIFIED) that fire damage suppresses
  (`fire` is a damage type, VERIFIED). Grabbable from stage 5 (height under 50 % of 14.63 m, capacity
  "large").
- **Rival giants** (8-11 m, stage-3/4 bodies): enemies built on the boss framework (phases, attack
  sequences, `force_action`, BossArena; VERIFIED `enemy_brain.gd:1159-1438`, `boss_arena.gd`) with
  weapon arcs (enemies already sweep weapons through `AttackRunner`, VERIFIED), lock anchors on knees
  and torso (VERIFIED), nav layer giant or titan. Boss grapples stay at stage 7 (spec §9).
- **Bosses** for stages 4-6 (proposals): a citadel warlord behind a pike regiment and a ballista
  battery (stage 4, the gate breach), a troll matriarch (stage 5), a rival giant champion with a
  peaceful honour-duel outcome (stage 6).
- **Wolves and lone soldiers** stay as early-region and ambient enemies; packs of larger beasts (dire
  wolves about 1.6-2 m) replace them at stage 4+ (ASSUMED; readability §2.4).

### 4.5 Weapons: axes, fists and Giantforge refits

- `WEAPON_FAMILIES` already lists axe and fists; `visual_shape` does not, and `WeaponVisuals` needs
  their meshes (VERIFIED §1 row 18; the mesh part ASSUMED from the enum).
- Axe: `flat_penetration` (an existing action field, VERIFIED `scripts/combat/action_def.gd:33`)
  and wide cleaves. Fists and grappling: no weapon length, fast chain whose finisher is a grab attempt
  (the `grab` hit shape exists, VERIFIED), scaling with the stage's grab capacity.
- **Refits.** Allow chains (remove the one-step rule at `progression.gd:273-297`), keep "each step
  fits at least as high", and give forges a `max_refit_stage`. A refit to stage 4-6 brings its own
  `light_chain` and `heavy` (equipping puts the weapon's moveset into the loadout, VERIFIED
  `player_equipment.gd:8-12`): that is where the stage 4-6 arcs that fix light 3's dead zone live. New
  materials (for example titan iron) as items; the tree weapon gets a stage 4-6 variant (a great
  pine) or scales with growth.

## 5. Recommendations: progression

### 5.1 Levels 7-12

The XP table already runs to 20 (`progression_default.json`, VERIFIED): totals are 1,350 at level 7,
2,200 at level 9, 3,250 at level 11 and 3,850 at level 12 (VERIFIED, computed from the table). The
Valley ends at level 5-6 (VERIFIED, `docs/HOW_IT_PLAYS.md` line 339), so the world must provide about
650 XP to stage 4, 850 more to stage 5, 1,050 more to stage 6 and 600 to level 12. The open world
should drop the Valley's "Prototype pacing" acceleration or keep the label (decision 7, VERIFIED). Each
level still gives 3 attribute points and 1 talent point (VERIFIED), so a level-12 giant has 11 talent
points, 4-5 of them already accrued in the Valley and never spendable there (VERIFIED: nothing spends
them).

### 5.2 Abilities, upgrades and stage evolutions

- **Records, not patches.** Every rank and every evolution is its own action record with
  `upgrade_of` / `evolves_from`, `unlock_level`, `unlock_stage` and an inherited slot. Cooldowns are
  per action id (VERIFIED, `scripts/combat/cooldowns.gd:7`), which gives the spec's "shared visual themes do not imply
  shared cooldowns" for free; saves keep storing ids; the validator checks the chains. Learning an
  evolution replaces its base in the same slot (auto-slotting today prefers the ability's position in
  `ability_library`, `progression.gd:221-255`, VERIFIED; the replacement rule is new).
- **Library toward 24** (proposal, about 12 new): Titan Stomp (stage 4, from Footfall; radius about
  1.0 x melee reach) -> Earthquake (stage 6, a telegraphed fissure line); Formation Sweep (stage 5,
  from Sweeping Blow); Crag Hurl (stage 4, from Boulder Hurl; 45-60 m, larger splash, breaks siege
  engines); Titan Roar (stage 5, from Thunder Roar; 15 m, -30 morale, unlocks intimidation lines);
  Rampart Grip (stage 6, from Crushing Grip; grabs and throws engines); Shoulder Charge (Destroyer;
  `body_sweep`); Earthen Wall and Bulwark (Guardian; a temporary wall prop and a wide guard);
  Rune Lance and Storm Call (Primordial; a 60 m magic projectile and a telegraphed area strike);
  Primal Regrowth (Primordial; heal over time and cleanse slows). All shapes exist today
  (`cylinder_pulse`, `sector_pulse`, `projectile`, `grab`, `body_sweep`, self statuses, VERIFIED
  `data_validator.gd:61-62`).
- Every stage-scaled pulse uses `radius_from: "melee_reach"` or a six-entry `radius_by_stage_m`
  (VERIFIED both are supported, `attack_runner.gd:144-157`).

### 5.3 Talent trees (Destroyer, Guardian, Primordial)

- `talent` records: `tree`, `tier` (1-5), `cost`, `requires` (talent ids), `requires_level`, and
  `effects`: `modifiers` (passives), `grants` (ability ids) and `replaces` (an ability id to its
  ranked id). The character gains `"talents": [ids]`; `talent_points` stays the unspent count.
- **Passives live on the combatant, not in statuses**: statuses always expire and show on the HUD
  (§1 row 21). Add `Combatant.passives` (a dictionary rebuilt from talents and ancestry) and fold it
  into the accessors that already centralise every modifier read: `armor_total`, outgoing damage and
  poise, damage taken, slow, fury gain (`combatant.gd:115-138`, VERIFIED). New keys as needed
  (stamina cost, cooldown, poise threshold, grab reach, fury on kill).
- The shrine screen gets a Talents tab beside Rest, Grow, Loadout and Attributes (the tabs exist,
  VERIFIED `docs/ARCHITECTURE.md` §10). Destroyer: melee, grabs, stagger; Guardian: protection, poise,
  protecting allies; Primordial: magic, fury (spec §9).

### 5.4 Ancestries (two or three)

- Ancestry records gain `attribute_bonus`, `resistances`, `modifiers` (passives as above), an
  optional signature ability, and `dialogue_tags` that open negotiation lines with certain peoples.
  Proposals: Stoneblood (Guardian lean: armour, poise, earth), Stormborn (Primordial: lightning
  resistance, essence), Wildheart (Destroyer: fury gain, stamina).
- Choice point: when the world opens (the end of the prologue), once, at a shrine, so a finished
  Valley save gets the same choice after migration. The ancestry is already saved and sanitised (an
  unknown one falls back to the player record's, `character_state.gd:128-133`, VERIFIED).

### 5.5 Peaceful resolutions beyond Thornwick

- The dialogue and quest machinery is generic: choices carry conditions (`stage_at_least`,
  `level_at_least`, `has_item`, `dialogue_outcome`, flags, all / any / not) and effects (`set_flags`,
  `outcome`, `xp`, `learn_abilities`, `once_flag`) (VERIFIED `dialogue_elder.json`,
  `data_validator.gd:88-90`). Intimidation, negotiation and tribute for new settlements are data.
- Move `FactionState`'s texts into `faction` records (§1 row 23) so each settlement, fort or giant clan
  is data.
- "Protect smaller peoples" needs enemies that fight NPCs or props: a target provider in
  `EnemyActor._sense()` (the nearest hostile entity among the teams and factions the record allows)
  instead of the player-only `_target()` (§1 row 14). A cheaper first step is raids on structures:
  raiders attack `BreakableProp` houses while villagers flee to shelters (civilian flight exists,
  VERIFIED `civilian.gd`), and the quest fails if N houses fall.
- At stages 4-6 humans are awed on sight (VERIFIED arithmetic, §1 row 17): intimidation should be the
  default outcome with towns, with forts needing a demonstration (breach the gate, break the
  formation's banner) and rival giants an honour duel.

### 5.6 Hotspot files

| File (lines) | Why every package will touch it |
| --- | --- |
| `scripts/core/data_validator.gd` (177) | Shared enums: archetypes, families, shapes, projectile visuals, permissions, conditions (§1 row 18). Pre-declare all M7+ values in one early package. |
| `scripts/actors/enemy_actor.gd` (1,986) and `scripts/ai/enemy_brain.gd` (1,599) | Formation slots, crew and cavalry behaviours, target provider, morale changes; already split by `@anchor` per package (VERIFIED). Add anchors for each M7+ package. |
| `scripts/world/encounter_director.gd` (857) | Formation objects, a separate formation budget, crowd renderer hand-off, siege engines in encounters. |
| `scripts/actors/player/player_targeting.gd` (240), `scripts/presentation/camera_rig.gd` (313), `ui/hud.gd` (925, the most-changed file of M2-M5 by commits) | Group lock, focus member, lock framing for groups, lock label. |
| `scripts/actors/player/player_progression.gd` (411), `scripts/progression/progression.gd` (302), `scripts/combat/combatant.gd` | Talents, passives, evolutions, the refit rule. |
| `scripts/core/game_session.gd` (901), `scripts/core/save_slots.gd` (201), `scripts/progression/character_state.gd` (311) | Modes and level transitions, migration, new character keys. |
| `scripts/quests/quests.gd` (860) | Active outside the Valley, slice end becomes the prologue's end. |
| `scripts/debug/valley_bot.gd` (1,645), `bot_combat.gd` (768) | Stage clamps and Valley ids; a region bot. |
| `data/progression/progression_default.json`, schema modules in `scripts/core/schemas/` | Library, new record types (talent, faction, formation fields). |
| `tests/support/anchors_expected.gd` | The anchor table the test suite checks. |

(Line counts VERIFIED with `wc -l`; churn from `git log` VERIFIED: `ui/hud.gd` 16 commits,
`enemy_actor.gd` 14, `valley_bot.gd` 11, `giant_player.gd` 9.)

## 6. Save migration (save document schema 1 -> 2)

Facts (all VERIFIED): one slot `user://saves/valley_1.json` written through `SaveIO` with a backup;
`SaveSlots.SCHEMA_VERSION` 1 and `validate()` accepts 1..SCHEMA_VERSION only; a file from a newer build
is copied to `valley_1.schemaN.rejected.json` and never becomes the backup (`save_slots.gd:19-90,
130-157`); the document holds `level` (a level record id), `checkpoint.respawn`, `character`, `world`
(WorldState schema 2: deltas, inventory, flags; schema 1 is still read), `stats`. Valley world and
entity ids are prefixed `valley.` (`valley_bot.gd:86-91`, `valley_layout.json`), quest state lives in
`quest.<id>.stage/done` flags, and a finished game has `slice.completed` true. `GameSession` loads any
level record's scene from the save's `level` (`game_session.gd:234-245`). The user folder comes from
`config/name` ("Giantborn: Age of Titans", no custom user dir, `project.godot:10`); the web save sits
in IndexedDB under that name (`docs/PERFORMANCE.md` line 392).

Recommendation:

1. `SaveSlots.SCHEMA_VERSION = 2` and `SaveSlots.migrate(doc) -> doc` run after `read_json` and before
   `validate()`, one step per version (`_migrate_1_to_2`), pure and unit-tested on real fixtures:
   saves written at the end of bot runs of the Valley (all four village outcomes), kept under
   `tests/fixtures/`.
2. v2 adds `character.talents` ([]), `character.ancestry_chosen` (false; the choice is offered when
   the world opens), `progress.prologue_complete` (from `slice.completed`), and keeps everything else.
   `talent_points` carries over unspent. Growth stage stays 1-3. The checkpoint stays where the
   finished game left it (its last shrine or waystone); the Valley's exit leads on, so no position is
   invented.
3. Keep the slot name `valley_1` and the project name: renaming either orphans existing saves,
   desktop and web (ASSUMED from Godot's `user://` mapping; the folder name is VERIFIED above).
4. The 0.5.0 build already protects a v2 save it cannot read (the rejected copy, VERIFIED), which
   matters for a cached web build.
5. Region transitions reuse Continue's path: commit a checkpoint whose `level` is the target region,
   then reload `main.tscn` (every mode change is already a reload, VERIFIED `game_session.gd:404-416`).
   Add a `campaign` mode (or generalise `VALLEY`) so quests, checkpoints and saves run in every region
   (§1 row 24).

## 7. Lab files, NOT RUN items and open questions

Lab (scratch, never committed), all under
`<scratchpad>/growth_lab/` (the session's scratch folder):
`repo/data/growth/growth_04.json`, `growth_05.json`, `growth_06.json` (the profiles of §2.1);
`repo/tests/integration/test_zz_growth_lab.gd` (profiles, reach bands, real hits, lock and framing,
Hurl, Valley respawn clearance), `test_zz_growth_lab2.gd` (light 3 tilts, the tree),
`test_zz_growth_lab3.gd` (Valley route clearance); `repo/lab/formation_lab.gd` and `.tscn` with
`make_formation.py` (the formation runs); logs `lab1.log`, `lab2.log`, `lab3.log`,
`perf_<N>_<stage>_<stand>.log`, `render_<N>[--lab-proxy].log`, `swing_4.log`, `swing_6.log`,
`bbox_12.log`, `bbox_40.log`.

NOT RUN: the web build with 20-40 soldiers; a human judging 8-17 px targets; a stage 4-6 walk of any
route (only capsule probes); real GPU numbers; group lock, crowd renderer, siege engines, talents and
migration (all designs).

Open questions for the planner: whether the open world starts at stage 3 (the Valley ends at level
5-6 and stage 4 needs level 7) with the first world shrine granting stage 4, and the Citadel Gate as
the stage-4 "revisit" breach; whether formations of 40 are wanted on the web or capped at about 20;
whether the bot should be generalised now (region bot driven by quest `bot` hints) or after the first
region exists.
