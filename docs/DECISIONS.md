# Implementation decisions and spec interpretations

The specification ([GIANTBORN_SPEC_V2.md](GIANTBORN_SPEC_V2.md)) asks that every interpretation
and conflict resolution be recorded. This file collects them for the whole build, milestones M0 to
M9:

1. [The plans' decisions](#1-the-plans-decisions): the 30 interpretations the M2-M5 plan fixed
   before any code was written (`docs/plans/M2_M5_PLAN.md` §0.3, numbered 1-30 here) and the 34 of
   the M6-M9 plan (`docs/plans/M6_M9_PLAN.md` §0.3, numbered 31-64 here), each with what was built;
   then §1.3: the one deviation from the spec itself (the lossless music and ambience masters that
   are not committed), the licence left to the owner, and the spec's scope as the owner later
   directed it and as the plan read it.
2. [Deviations recorded by the packages](#2-deviations-recorded-by-the-packages): where the packages
   (P01-P18 for M2-M5, P19-P40 for M6-M9) departed from their plan, and why. Each package's own
   record, with every detail and the test that covers it, is `docs/systems/<package>.md`.
3. [Fixes from the milestone gate reviews](#3-fixes-from-the-milestone-gate-reviews).
4. [The plans' review logs](#4-the-plans-review-logs), in short.
5. [The M0/M1 decisions](#5-the-m0m1-decisions): the combat sandbox's rules, still in force unless
   a row says what replaced them.

Everything below is a proposed default: data, or a small code path, that can be changed. A number
quoted from a measurement names its source. Measurements of the M6-M9 code are the W23 confirmation's
(`wave-23` with commit `a7da72d`; `docs/BALANCE_LOG.md`, "M9 confirmation") unless named otherwise:
the M9 gate's fixes followed that confirmation, and what they changed is in §3.2; the M9 gate's final
measurements and the ship's final check are in `docs/M6_M9_HANDOFF.md` §5.4, §6 and §7.

## 1. The plans' decisions

### 1.1 The M2-M5 decisions (M2-M5 plan §0.3)

| # | Decision | What was built (and where it moved) |
| --- | --- | --- |
| 1 | **One Valley scene, district sub-scenes.** Geometry from one layout table (`tools/data/valley_layout.json`, not shipped); navigation pre-baked offline into four layers (human, large, giant, small giant); a breakable that blocks a path carries a `NavigationLink3D` enabled when it breaks; no runtime bake in the Valley; no streaming. | As planned (P10b): eight district scenes, four compressed navmeshes of 15-19 KB, one nav link per layer at that layer's height. A path query to an unreachable point can exhaust Godot 4.6.3's 4,096-polygon search limit, so the navmeshes were made leaner (fewer forest trees, hexagonal trunks, a coarser contour) and a slow test keeps whole-map queries under 3,500 polygons. |
| 2 | **Enemies spawn from data.** An `EncounterDirector` spawns `encounter` records with stable ids, persists kills, despawns far unengaged members (they return at full health), never respawns a cleared encounter, and enforces a budget of 12 active combatants, three AI LOD tiers (tier 2 a one-box proxy) and a leash. | As planned (P10a). Later: a level's encounter scenes load with the level and an activation spawns at most 2 members a tick (P17a, the spawn hitch); a hostile faction's armed members count toward the budget even in an unbudgeted encounter (P17b, the force branch's 16 hostiles). |
| 3 | **Weapons fit up to a stage; the Giantforge refits them.** `weapon_scale` 1.0 / 1.5 / 2.1667; a weapon follows growth up to `fit_max_stage`, then keeps that size with a "too small" warning; club, sword and hammer fit stage 2, their reforged variants stage 3; the tree is stage-3 only. | As planned (P08, P12). A forge reforges the equipped weapon for 2 iron; the village forge opens only on a help outcome, the ruins' Giantforge always. |
| 4 | **Growth adds body.** Stage 2 +150 health / +10 stamina, stage 3 +300 / +20; percentages kept; nothing heals by changing profile. | As planned (P05). |
| 5 | **Big giants still hit humans and wolves.** Arc pitch offsets 0 / −6 / −12 by stage. | P05 kept −6 / −12 and added per-action exceptions (`arc_pitch_offsets_deg`: stage 3's light 1 at −16) so the chain lands on a wolf at the giant's feet. P17b added the **vertical aim**: a light or heavy swung at the lock (or the soft target) lifts the stage's tilt just enough to reach it, so blows land at the stage's reach (3.5 / 5 / 6.5 m) while the default tilt still reaches the feet. |
| 6 | **Levels gate abilities** (`unlock_level`; `controller.level` 99 = no gating; `level_exempt` for rewards; auto-slot; loadout at shrines). | As planned (P01, P12). The auto-slot uses the ability's own slot from plan §4.7 when it is free (P12), so Boulder Hurl is always slot 5 and Runic Bolt slot 6. |
| 7 | **XP is accelerated and labelled** "Prototype pacing: accelerated quest XP". | As planned: the progression record's label, a sign in the Hollow, the tracker's pacing line, the inventory screen (P12, P13, P15). `test_xp_budget` keeps level 3 before the Grove, level 4 by the practice gate and level 5 before the stage-3 growth for every village outcome. |
| 8 | **In-flight projectiles still land after the shooter dies** (dropped only if the owner died this tick). | As planned (P01, P03). |
| 9 | **Statuses are ticked centrally**; status immunity is a separate list; Stone Skin changes `armor_total()`, never `armor`. | As planned (P01). A refresh never shortens a status (the later expiry wins). |
| 10 | **Thunder Roar** is unblockable, deals 0 damage, slows 30 % and costs 20 morale on HIT; a dodge evades it. | As planned (P03): a cylinder pulse with morale damage. |
| 11 | **Village outcomes last and differ.** Help (cache or ogre): 120 XP, 2 iron, Ancestral Mend, the village forge. Intimidate (stage ≥ 2): 40 XP and Thunder Roar, no iron, forge shut. Force: only by smashing the barricade (stage ≥ 2), kill XP only, an ambush on the return leg. Striking villagers sets hostility, never the outcome. Every outcome opens the bridge. Rewards only through once-flags. | As planned (P11b, P13, P15). The elder's conversation has the extra nodes a real talk needs (thanks, waiting, done; P15). |
| 12 | **Kingsfall growth requires the boss's defeat.** | As planned (`growth_requires_flags`, P05). |
| 13 | **Checkpoints are frequent and never lose a boss kill**: a shrine's first activation (a free Rest), Rest, the shrine screen, waystones, growth, the boss's defeat, every main-quest stage; deferred while dead, grabbed, executing, holding, in another screen or near an aware enemy; death reloads the last checkpoint with at least 60 % health and full stamina; only the Valley writes. | As planned (P06). Later: the slice's completion checkpoint ignores aware enemies and Quit to title commits it (P17a); New Game asks before replacing a saved game (P06). |
| 14 | **One save slot** `user://saves/valley_1.json` (IndexedDB on the web), versioned, with backup recovery. | As planned (P06). A main file that does not fully load is never copied over the backup (P16). The web persistence was checked in Chromium by P18 (`docs/M2_M5_HANDOFF.md`). |
| 15 | **Modes**: a title screen (New Valley, Continue, Sandbox, Settings, Quit); `--autoplay` / `--scenario` without `--mode` still boot the sandbox. | As planned (P06). The game opens at the title; Quit is hidden on the web. |
| 16 | **Grab design.** E grabs a staggered target in reach (melee reach + 0.5 m) with a lunge; the six spec §8 rules including an attachment profile; a poise break by a twice-taller attacker staggers 1.5 s; light or heavy throws, E drops; Crushing Grip crushes small targets; Boulder Hurl rips its own rock; a staggered ogre is grabbable from stage 3; the boss is immune. | As planned (P07). The lunge drives the motor's knockback channel; holds use the off hand; grab and throw have a 0.6 s input queue; every grab needs a fresh poise break (M3 gate). |
| 17 | **Factions and hostile-only targeting.** Lock, soft target and the player's area effects consider team ENEMY and faction-less NEUTRAL only; a direct hit on a village member warns, a second within 30 s turns the village hostile; intimidation stands the guards down. | As planned (P03, P11b). A broken guard is an offence too; one blow is one offence however many villagers it clips. |
| 18 | **The fortified Citadel Gate** is structural, `min_growth_stage` 4, permanently locked. | Two damage stages (intact, breached), because a structural prop's last stage must remove collision (P08); the breach is unreachable in the slice. |
| 19 | **The Deadfall** accepts only `TreeWeapon` hits. | As planned (P08). |
| 20 | **Talents and ancestry**: points accrue and show; one neutral ancestry, saved and shown. | As planned (P12). |
| 21 | **Physics layer 6 "blockers"** for invisible movement walls; every actor uses `SceneKit.ACTOR_MASK` (51); camera, attack occluders, LOS and hurtboxes ignore it; the navmesh treats it as an obstacle. | As planned (P01, P04, P10b). |
| 22 | **Debug keys** (debug builds only): F6 / F7 grow / shrink, F8 +100 XP, F9 reload the checkpoint; F5 sandbox reset; release exports have none. | As planned (P01, P05, P06, P12). |
| 23 | **Selective destruction in all three spec categories**: cosmetic (never saved), breakable, structural (the practice gate intact → cracked → broken); every persistent prop saves its stage and health. | As planned (P08); this ended the M1 limitation that partial damage was not saved. Each prop's meshes are merged per material (P17b, draw calls). |
| 24 | **Enemies commit their aim** at `tracking_fraction` of the windup (0.6 for archers and mages); a sidestep after the lock dodges the shot. | As planned (P09). Launch slots are padded by the difference in windups, so launches at one target are always at least 1.0 s apart. |
| 25 | **Readable threats without audio or animation**: a filling telegraph decal for every enemy attack with a windup of 0.8 s or more, aim lines, screen-edge threat arrows, at most two ranged attackers at once, 1.0 s between launches. | As planned (P09). An untelegraphed long windup is a data error. The arrows and the objective marker draw over every HUD panel and slide along the edge to stay clear of them (M4 gate). |
| 26 | **Size changes enemy tactics and morale**: outmatched soldiers hold formation and brace; awe (−35 morale) at 4x height; regroup only with a leader, else rout; bosses ignore morale. | As planned (P04, P11b). The brace reaches 4 m (the giant's leg hurtbox lies inside its capsule) and deals 28 to a stage-2 giant after tuning. Measured: soldiers hold formation 58 % of their engaged time at stage 2 and flee or rout 55 % at stage 3 (median of the novice runs). |
| 27 | **The Ogre King is a real boss**: 8.5 m; phase 1 alternates combo and slam; a 1.5 s roar marks phase 2, which adds a charge into the wall or a pillar and a 2.5 s punishable recovery; slam and charge unblockable. | As planned (P11a); super armour now ends at the recovery (the punish window). Tuned in P17b: the slam deals 101 to a stage-2 giant with a 1.5 s windup and a 1.8 s recovery, the combo 67 / 77, 0.6-1.0 s between attacks; health 1,500 and poise 150 kept. |
| 28 | **The tutorial encounter is in the Valley** (Giant's Hollow's dummies and sparring post, then the first wolf pack); the sandbox gets a sparring post. | As planned (P11b, P15). A lesson whose prompt timed out still counts when the player does it later (M4 gate). |
| 29 | **The navigation profile changes with growth**: stage 1 on the small-giant layer (8, with the 4 m alleys), stages 2-3 on the giant layer (4). | As planned (P05, P10b). |
| 30 | **Balance is judged on a novice bot**; the expert is the ceiling; stability uses an assisted bot (damage taken x0.25). | As planned (P17a, P17b). P17b's final batch (tag `final`): the novice completes 17 of 18 runs and the expert 4 of 4; some M2-M5 plan §5.6 targets are still missed (`docs/BALANCE_LOG.md`, "Confirmation (tag `final`)"; `docs/systems/P17b.md`, "Known gaps"; `docs/M2_M5_HANDOFF.md` §6.4). |

### 1.2 The M6-M9 decisions (M6-M9 plan §0.3)

The M6-M9 plan's decisions 1-34 are numbered 31-64 here ("Plan" gives the plan's own number, which
the system documents use). The plan holds each decision's full text.

| # | Plan | Decision | What was built (and where it moved) |
| --- | --- | --- | --- |
| 31 | 1 | **Audio is presentation only.** One autoload, `Audio`, last in the order; it listens and reads state, never emits a gameplay signal, spends or changes nothing, never reads `finished` into game logic and never touches `Sim.rng` or the global RNG. The seeded soak with audio on and off must give byte-identical results; the default suite runs silent. | As planned (P19): private generators, a policy test that scans `scripts/audio/`, the gate suite `test_audio_determinism`. The M6 gate found seeded Valley bot runs diverging with and without audio (the navigation map's sync, not the audio): the loading gate now also waits for the navigation map, the autopilot waits with it, and headless runs sync navigation on the main thread (`test_valley_audio_determinism`). The test runner is silent by default (`--with-audio`). |
| 32 | 2 | **One playback policy for both platforms.** Effects are WAV masters imported as QOA and played with `PLAYBACK_TYPE_DEFAULT` (a stream on the desktop, a Web Audio sample on the web), registered behind the loading screen before the first tick; everything on the Music and Ambience buses, spots included, is Ogg Vorbis played as a stream; no `PLAYBACK_TYPE_SAMPLE`, randomizer, polyphonic or playlist streams; every effect at most 2.0 s; `output_latency.web` 200. | As planned (P19; `test_audio_policies` greps for the forbidden calls). P23 found and closed a race in Godot 4.6.3 that crashed the mixing thread under load (a playing player's replaced bus details freed while the mixer copied them): a mixing barrier once a frame and volumes written only when they change (`test_audio_thread_safety`); 30 audio-on bot runs under load with no crash (`docs/systems/P23.md`, "The audio-thread crash (fixed first)"). |
| 33 | 3 | **Buses are made at run time** (Master, Music, Ambience, SFX, UI; no effects), so both platforms mix alike. | As planned (P19). |
| 34 | 4 | **Every sound is original and generated by committed code, and the generators are the masters.** `tools/audio/` (Python 3 and numpy, seeded, float64, single-threaded) writes every sound; effect WAV masters are committed; music and ambience are rendered to lossless masters and only the bit-exact Ogg is committed, beside a manifest of every hash and the tool versions; `build_audio.py --verify` regenerates every master and Ogg and compares them (part of `check.sh --audio`); `--masters-out` writes the music and ambience masters as FLAC; `PROVENANCE.md` states originality and leaves the licence to the owner. **A recorded deviation from spec §13** (§1.3). | As planned (P19, P21, P23, P28): 441 files, every check with `--audio` since P28 regenerating all of them bit-exact on the recorded toolchain (Python 3.13.18, numpy 2.5.3, ffmpeg 6.1.1, libvorbis 1.3.7; `assets/audio/manifest.json`), W23's last in P39f's web part's final check (`docs/systems/P39f.md`, "Part web"); ⟦SHIP: the final check's `--audio` result on the final commit (tools/check.sh --build --slow --gate --audio, as docs/M6_M9_HANDOFF.md §6.1): the number of files regenerated bit-exact, or the failure⟧. `assets/audio/PROVENANCE.md`: "Licence: the project's licence; the owner chooses it." |
| 35 | 5 | **The score is layered stems** on plain stream players started in one frame; layer volumes eased live; set changes cross-faded at bar boundaries; three melody variants per exploration set picked per four-bar segment (no variant more than two segments in a row, no phrase repeated within 60 s), rests of one to three loops, a silence window after three minutes of calm; danger and combat stems shared per tempo, the region's melody kept under combat at −10 dB, a combat-intro stinger per region; boss sets in their own tempo and mode with a one-bar intro; stingers duck the stems. | As planned (P19's MusicDirector and MelodyScheduler; P23's Valley score; P28's world score: five regions, three bosses). P23: a district change keeps the frame's position (no clash of chords while the sets cross-fade); melodies rendered segment by segment so a variant's tail never crosses into a rest; loudness (LUFS) balances the score rather than peaks. |
| 36 | 6 | **The listener stands at the giant's chest**, turned with the camera; other sources' distances scale with the giant's height ÷ 3.66; distance muffling uses baked "far" variants. **The music weighs threats against the giant**: `combat` only for an enemy of at least 0.3 x the giant's height or a formation member, engine crew, boss or rival giant; lesser enemies raise at most `danger` within 40 m; fleeing and routed enemies never count; the danger radius at most 150 m. | As planned (P19, P28). Measured: the music was in `combat` for 43 % of the stage 4-6 time spent among only lesser enemies in the W23 confirmation (plan §6.4's target: under 25 %; `docs/HOW_IT_PLAYS.md`, "The music's intensity"); the rule is as planned and unchanged since P19 (the mix data's `intensity` block is plan §4.4's): only an enemy that counts raises `combat`, and a lesser enemy's blow raises only `danger` (`AudioMath.intensity_target`, `MusicDirector.note_player_hit`). So the cause `docs/plans/FOLLOWUPS.md` records ("From the M9 confirmation": P28's rules "count any engaged enemy") is not what the code does. The music and the measure differ in reach. The music counts an engaged enemy that counts out to 35 m x the giant's height / 3.66 (105 m at stage 4, 140 m at stage 5, 181 m at stage 6, though it looks no farther than 150 m). The measure looks only at the enemies engaged within 40 m (`RunMetrics.HOSTILE_NEAR_M`) and judges them by the music's own rule (`WorldMetrics.counts_for_music`, so formation members and crews count). A formation or crew engaged beyond 40 m therefore holds the music in `combat` during time the measure counts as among only lesser enemies; a counting enemy's blow (5 s) and the combat hold (6 s) add to it. ⟦SHIP: the M9 gate's change to this rule if merged (fix/m9-balance `4be451d`: `audio_mix.intensity.combat_cap_m` 40 for a giant of at least `combat_cap_min_height_m` 10 m) and the cause it traced, and the share measured on the code the gate shipped (docs/BALANCE_LOG.md, the M9 gate's section; docs/HOW_IT_PLAYS.md, "The music's intensity"); delete the change if it was not merged⟧ |
| 37 | 7 | **Threats are audible and directional.** A positional windup cue at the attacker for every telegraphed attack aimed at the giant; a broadband "threat sting" there when the attacker is off camera or beyond 20 m (scaled), unless the expected damage is under 3 % of the giant's health or the poise ratio sits at the 0.25 floor; one wall cue per formation brace; an engine's launch at the engine and a rising whistle at the landing circle; a cue when a ranged enemy commits its aim. | As planned (P19's router, P21's threat family - kept apart from the hits by a spectral test - P28's world rules). M6 gate: the sting and the aim lock moved to the mix's `alert` class, so a far sting is not lost under the combat layer (`test_threat_audibility`). P28: the whistle starts at the launch, not the telegraph. Open: the sting of a siege engine or a cavalry charge against a big giant is muted, because the router weighs the attacker's own height rather than the action's size override (`docs/plans/FOLLOWUPS.md`, "From P32"). |
| 38 | 8 | **Size and memory budgets**: M6 audio ≤ 4.0 MB imported, all audio ≤ 9.5 MB; world data ≤ 5.0 MB; the web `index.pck` shipped gzipped and base64-encoded in parts of at most 15 MB that the launcher joins, ≤ 7.5 MB after M6, ≤ 21 MB after M7, ≤ 23 MB at the end; test content never in the web release; registered web samples under 110 s (the Valley) and 170 s (the world). | Met at every release through `0.8.0-m8` and on the W23 code: M6 audio 3.93 MB (P23); all audio 9.229 MB of 9.5, the Valley's registered samples 108.57 s of 110 and the world's 167.81 s of 170 (P39f's web part's final check, W23); world data 2,390,369 bytes at P25 and 2,984,279 at W23 (`docs/M6_M9_HANDOFF.md` §2); the shipped pck 6.52 MB at the M6 gate's release (commit `aaf3844`), 15.92 MB in two parts at `0.7.0-m7`, 16.53 MB in two parts at `0.8.0-m8` and 16.67 MB in two parts in the W23 confirmation's release build (`docs/PERFORMANCE.md`). ⟦SHIP: the `0.9.0-m9` release, each met or not: its index.pck as shipped (bytes and MB of 23, the parts and the largest against 15 MB, no test content; from tools/build_web.sh on the final commit, as docs/M6_M9_HANDOFF.md §7), the final check's audio budget line (imported MB of 9.5, the Valley's registered seconds of 110 and the world's of 170; docs/M6_M9_HANDOFF.md §6.1) and the world data's bytes on the final commit (docs/M6_M9_HANDOFF.md §2)⟧ `tools/build_web.sh` fails over the milestone's budget since the M7 polish (P22). P23 measured Godot 4.6.3's Ogg import factor at 1.11, not the plan's 1.03. |
| 39 | 9 | **Enemy rigs get cheaper, not fewer**: one vertex-coloured mesh per animated part with one material per actor; the renderer's visibility ranges swap distant rigs for the one-box proxy by archetype (bosses exempt). Target: about 7 draw calls per near rig, 1 per far one. | P22 as planned (the stress arena's twelve combatants 221 -> 77 draw calls). The M6 gate measured a miss (the Valley walk at `low` up to 268 draw calls against 250); P30's merged rest-pose mesh at mid distance and P27's batched HUD (about 10 draw calls instead of about 120) brought the walk to max 154 (`docs/PERFORMANCE.md`, "Draw calls after P27"). |
| 40 | 10 | **The Valley stays the prologue, almost unchanged**: the crown opens the Kings' Door; the end screen becomes "Prologue complete" with Continue; the Citadel gets an interior breachable at stage 4 and a second exit; Thornwick's guard posts move; checkpoints get display names and a `max_stage`; a sealed vault opens to a stage-5 heave; a finished save may skip the prologue. | As planned (P20, P22, P26). Every Valley checkpoint measured `max_stage` 6 (P26's corridor test). A second new waystone, `valley.cp.citadel_stair`, receives the giant from the world's Broken Stair. |
| 41 | 11 | **Two campaign levels and reload transitions**: `level.valley` and `level.world`; `GameSession.Mode.VALLEY` means the campaign; travel and fast travel are a checkpoint at the destination plus a reload; the save's `level` picks the level; level-wide nodes of later packages are made at run time from `LevelRoot.RUNTIME_NODES`. | As planned (P20). M7 gate: fast travel is refused for a stone its respawn blockers refuse, and a load that moves the respawn says why. M8 release: no checkpoint is committed while a boss fight or battle is engaged. |
| 42 | 12 | **A 2,048 x 2,048 m world in 8 x 8 chunks of 256 m**, bounded by a rim; chunks load within Chebyshev distance 1 and unload at 3 or more (at most 25 loaded), nearest first, with a 4 ms per-frame budget (a fixed quota headless); 16-bit heights at 4 m; no plugins, no floating origin; chunk-border slopes at most 35°. **The world can be seen to its edge**: an always-loaded skyline, fog from 400 to 1,800 m, a 2,400 m far plane, beacon columns. | As planned (P24a, P25). P25 needed a slope-limiting projection before P24a's border relaxation. M8 gate (F26): a preload list loads the chunks' scripts and shared scenes behind the loading screen. Measured: the loaded margin at least 250 m with no thrash on the stage-6 tour and in every bot run; the worst streaming work frame headless is a large props part's text parse: 12.19 ms on the tour and 17.9-33.9 ms in the W23 matrix's bot runs (three at a time on four shared CPUs), against plan §6.4's 12 ms, a miss (`docs/PERFORMANCE.md`, "The M9 confirmation"); exports ship binary scenes, whose parse takes about a tenth of the time (P39f). |
| 43 | 13 | **Navigation in the world is baked offline** on three layers with one map each (human 1, large 2, titan 16), size-gated ground as titan gate regions (32 / 64 / 128); lean bakes, the grown box, the aligned y grid; every query through `NavQuery` (unlimited polygons, 120 m chase and 300 m far caps, goals snapped, a per-tick budget, throttled re-paths); the Valley's paths unchanged; async iterations off when streaming is deterministic, readiness by iteration id; a road graph for long routes; nothing bakes at run time. | As planned (P24b, P25): `test_world_determinism` (gate) requires two world walks with AI to give byte-identical results. M7 gate: the actors' firing, flee and rout searches keep the budget and resume where they stopped; M7 polish: civilians' safe points too, and every layer map keys its edges at its own cell (16 edge errors on the human map gone). A gate region takes every titan polygon that touches gated ground; size gates are drawn in 6 m for the split (P25). |
| 44 | 14 | **A world index per level**: positions and display names of checkpoints, markers, areas, POIs, exits, encounters, safe markers and quest props, the region grid and the road graph; everything falls back to it when a node is not loaded. | As planned (P20 for the Valley, P25 for the world). M8 gate (F18): road edges carry their kind, so wanderers stand on open roads. |
| 45 | 15 | **The director in a streamed world** updates only encounters whose chunk is loaded and ready, despawns living members before their chunk unloads (they come back home at full health), filters spawns by stage, scales formations for the web, requires a leash on every world encounter but arena bosses, which get a disengage rule. | As planned (P24b, P30, P34). Through W23 the director keeps its older rule (P17b): a faction's armed members already in the world count toward the budget of 12 when it turns hostile, and new spawns wait; the W23 confirmation saw 13-17 counted for at most 0.35 s and 16 for 43.6 s when a faction turned (`docs/PERFORMANCE.md`, "The M9 confirmation"; FOLLOWUPS). ⟦SHIP: P40's decision on FOLLOWUPS' row "The director's counted combatants pass the budget of 12" (keep the rule, or hold the newly hostile members back), with its reason; restate the rule here if it changed⟧ |
| 46 | 16 | **Save schema 2**: `SaveSlots.migrate()` before `validate()`, one step per version; 1 -> 2 adds `character.talents`, `character.ancestry_chosen`, the `progress` block and the checkpoint's position; a damaged v2 main file with a v1 backup recovers through the migrated backup; the slot and the project name stay; a finished Valley save continues with the Kings' Door open. | As planned (P20; `test_save_migration` on five v1 fixtures). M7 polish: a migrated save also gets the `visited.<id>` flags its progress proves (fast travel to the stones it used). M8 gate: talents, the ancestry and attributes chosen at a shrine are saved at once (F15); a boss's end and the world's main-thread stages are completion checkpoints (F38, N4.2). M8 release: the title's save line names where Continue wakes the giant (R2). |
| 47 | 17 | **Growth stages 4-6** at 10.97 / 14.63 / 18.90 m, levels 7 / 9 / 11, lock 55 / 65 / 80 m, arc tilts −16 / −20 / −24°; stage 4 needs the Kingsgate beacon lit, stage 5 one oath, stage 6 two. | As planned (P26 profiles with their size-gate and navigation masks; the shrines' conditions, P29). |
| 48 | 18 | **Size gates** of four kinds: props with `min_growth_stage` (heave at 5), invisible walls on physics layers 7-9 mirrored by the titan gate bits, narrow passes by geometry (the Needle fits stages 3-4), and trampling; each names its stage and answers with a diegetic cue. | As planned (P26, P25, P35's NarrowPass). M8 gate (F29): every size gate names its stage. |
| 49 | 19 | **Formations are lock groups at stages 4-6**: one candidate per formation plus the bannerman; one brace band attack per formation with one melee token and one hit per target per pulse; ranks, a banner that halves awe and ally-death losses, a crowd renderer, routs that fan out; caps of 40 members on the desktop and 20 on the web. | As planned (P30). M7 gate: a formation's reach stays inside its encounter's leash and the director leaves an intact formation to it; the advance ends inside the brace distance; the brace strikes the band its telegraph drew. M7 polish: a formation whose members all flee stays broken while its banner lives. Measured (W23 confirmation): formations hold or brace 79 % of their engaged time while their banner lives, and 89 % of the locks with a formation engaged are group or banner locks (both targets met). |
| 50 | 20 | **Enemies can target NPCs and props** through a target provider, opt-in per record (`targets`). | As planned (P30; per spawn for templates, P37). W23 (P39f): with nothing of its targets in sight a unit keeps no target rather than measuring itself against a giant it does not see; a sheltered civilian or a protected NPC is never a target; a target struck for 12 s without a damaging blow is given up for 60 s. |
| 51 | 21 | **Siege attacks carry a size override** (`attacker_height_override_m`), so a ballista bolt staggers a big giant like an 8 m attacker; destroying an engine raises the −20 siege morale event (2 s debounce per unit). | As planned (P32). The bolt's poise is 140, not plan §5.11's 60, so that it can stagger a stage-4 giant at all; P39 lowered its power (90 -> 60), not its poise. |
| 52 | 22 | **Talents and ancestries are passives on the `Combatant`**, never statuses; three trees of nine talents; three ancestries chosen once at a shrine after the world opens (a migrated save gets the same choice). | As planned (P33): 27 talents, the crowns costing 2 points; the level cap stays 20, talent tiers open at levels 6, 8, 9, 10 and 12. Costs and cooldowns scale through per-character copies of the actions. Bulwark takes x0.4 from every side (the frontal rule needs the hit's direction in `DamageResolver`, which no package owned). |
| 53 | 23 | **The library is 24 actives and one ultimate**: the Valley's 8, 6 stage evolutions, 7 talent abilities and 3 ancestry signatures, plus Titan Surge; evolutions replace their base in the same slot; ranks not built. | As planned (P31, with Rampart Grip, the 24th, from P32). `progression_default.json`'s library holds the 25. |
| 54 | 24 | **Weapons grow with the giant once reinforced**: base weapons fit stage 2; reinforcing (2 iron at an iron-tier forge) makes a weapon fit stage 6 with its family's stage 4-6 moveset, whose third light lands at the feet; titanforging (2 titan iron + 2 iron at a titan-tier forge) adds damage and one perk; the axe and the fists fit stage 6; the great pine is the stage 4-6 tree. | As planned (P26's `stage_movesets`, P31's movesets, axe, great pine and perks, P32's fists). The reinforced sword and maul grew longer so their stage 4-6 blows land at 0.9 x the melee reach (P31). |
| 55 | 25 | **XP keeps the prototype-pacing label in the world**: a budget test guarantees level 7 at the beacon, 9 after any one oath, 11 after any two and 12 at the throne from the Valley's worst outcome (level 6, 1,050 XP), at least 50 XP of margin; milestones carry an `xp_floor_level`. | As planned (P20's `world_start`, P29's budget tests, extended by P35 and P36). The W23 confirmation's five budget suites pass with the smallest margin 70 XP (`docs/BALANCE_LOG.md`, "Every target of plan §6.4"). |
| 56 | 26 | **The main thread is non-linear, and every oath can come first**: the three oaths start together at stage 4 and any two complete the stage; each has a peaceful and a violent resolution open as the first oath at stage 4; a choice that still needs something shows greyed with its reason; the finale needs stage 6. | As planned (P29's `OathRules` proves a first-oath resolution for every oath; P35, P36). The gate suite `test_main_thread_combinations` runs every order of every pair (M8 gate F3: through every resolution's own writer). In the W23 confirmation the bot completed the march-first and wood-first orders but not the crown-first (the Iron Regiment at stage 4; `docs/HOW_IT_PLAYS.md`). ⟦SHIP: the M9 gate's first-oath orders on the final code, crown first included (handoff §5.4)⟧ |
| 57 | 27 | **Wandering encounters and world events** come from region tables filtered by stage and faction standings, spawn out of sight on loaded ground, persist their outcomes and cannot be farmed (a template's kill XP falls to zero after its third spawn); events start only when their centre chunk is loaded and the giant is within 200 m, suspend while unloaded and reset on death; moving columns are a path parameter while unloaded. | As planned (P37's framework and the Crownmarch, P35's and P36's tables and events). Not shipped: the siege trains of the wander tables (an engine is a placed prop keyed by its world id; FOLLOWUPS). An event left unloaded for 600 s is abandoned with no outcome (not in the plan). |
| 58 | 28 | **The world bot extends the Valley bot** (road-graph routing, tracked objectives, exploration, oath policies in any order); balance is judged on the novice, stability on the assisted bot. | As planned (P38). P39 added measurement fixes and rules of play the bot never had (siege disruption, the ability rotation, the expert's answers, the expert's brazier lure), which shape the ability and boss numbers it reports (`docs/systems/P38.md`, "P39 (W23)"). |
| 59 | 29 | **Stages 7-10 come later by data**: profiles to stage 10 already validate; layers, gate bits, region records, chunk grid, skyline and world record are data; the builder accepts a larger grid. | Not built, as planned (§0.4). |
| 60 | 30 | **Every milestone has a gate review, and the ship its own.** | M6 (W14), M7 (W18, then the M7 polish), M8 (W21: a review, an audit with two fix-up rounds, a screenshot pass and the release check of `0.8.0-m8`), the W23 confirmation and the M9 gate, and the Ship gate (W24): §3.2. |
| 61 | 31 | **Peoples by site, and manners toward a giant**: factions are records with texts, thresholds and per-site dispositions; the toll-riders hostile from the start, Aldmere at peace until offended; friendly civilians give way; talkers meet a big giant on their green; damaging houses is an offence; a hostile settlement can be reconciled; outcomes show on site; quest-critical props are indestructible. | As planned (P22's factions by record, P29's Crownmarch, P36's Aldmere, Skarn and Harrok's clan; P25's GameData check that every quest-critical prop is indestructible). |
| 62 | 32 | **An equipment budget sits beside the XP budget**: reinforcing affordable by the beacon, one titanforging (and a titan forge) by the first oath, two by stage 6; titan iron on the mandatory path from the beacon's cache, every oath and the Standing Stones; optional sources extra; nothing missable. | As planned (P29's `test_world_equipment_budget`, extended by P35 and P36); it passes in the W23 confirmation. |
| 63 | 33 | **Exploration pays**: every POI gives discovery XP; vistas reveal the POIs within 400 m on the map; fourteen Old Kings' cairns (thirteen in the world, one in the Valley's vault) give an attribute point each, nine of them behind size gates; sealed places are logged in the journal with the stage they need; caches give iron. | As planned (P25, P26, P27, P35, P36), with two exceptions. The Kingsgate, Greywood and Aldmere shrines' POIs give no discovery XP (plan §5.4's "30 / 0": the shrine is the reward; P25). The Standing Stones' shrine POI gives 40, and the Sunken Steps' shrine stands inside that ruin's POI (30). Twelve cairns stand, not fourteen: eleven in the world and the Valley vault's (P26). The two missing ones are sealed Crownmarch places (stage 5): the Toppled King (`poi.kingsgate_statue`) and the Barrow Vault (`poi.barrow_vault`) hold only their 2-iron caches (`tools/data/world/crownmarch.json`). P25 left the sealed cairns to P35 and P36 (`docs/systems/P25.md`), whose regions held four of them, and `test_world_data` accepts 7 to 13 world cairns. The bots seek no sealed place or cairn. |
| 64 | 34 | **Three test tiers**: the default suite (≤ 75 s, audio off, per-package caps), the slow tier (`tests/slow/`, ≤ 8 minutes) and the gate tier (`tests/gate/`, ≤ 50 minutes); every wave merge records the default and slow times. | As planned (P19 added the gate tier and the `TIMES` line). The W23 confirmation's full check: 282 suites, 49,265 checks, 0 failures; default 71.0 s, slow 313.3 s, gate 660.1 s (`docs/systems/P39.md`, "Tests and the full check"). ⟦SHIP: the ship's final check on the final commit: suites, checks, failures and the default, slow and gate times against 75 s, 8 and 50 minutes (handoff §6.1)⟧ |

### 1.3 Deviations from the spec, the licence and the spec's scope

One deviation from the owner's spec is recorded by decision (plan M6-M9 decision 4, here 34, and the
review log's "Music and ambience masters not kept", plan §8). The licence is not a deviation: it is a
decision the plan leaves to the owner (plan §0.4, §6.7 and the review log's "CC0 chosen without the
owner", §8). Both are the owner's to settle (`docs/M6_M9_HANDOFF.md` §10):

- **The lossless music and ambience masters are not committed** (spec §13: "Keep editable ...
  audio masters"). The effects' WAV masters are committed (they are also Godot's import source). For
  music and ambience the generators are the masters: `build_audio.py --verify` regenerates every
  master and every shipped Ogg and compares their hashes with the manifest, so regeneration is proven
  bit-exact on the recorded toolchain, and `build_audio.py --masters-out=<dir>` writes the lossless
  masters as FLAC on request. The plan's review chose this ("Music and ambience masters not kept":
  a changed fix) because the FLAC masters would add about 60 MB to a repository of about 19 MB at
  planning time and be rewritten on every tuning pass (plan §0.3 decision 4, §6.7). The owner may ask
  for them to be committed instead: `python3 tools/audio/build_audio.py --masters-out=assets/source/audio`.
- **No licence is chosen**, which the spec does not ask for: spec §13 asks to keep "license records",
  and `assets/audio/PROVENANCE.md` is that record. It records that every sound is original and
  synthesized by the committed generators, with no recordings and no third-party samples, and lists
  each family's generator, seeds and tool versions; it leaves the licence as "the project's licence;
  the owner chooses it". The plan's review rejected choosing one ("CC0 chosen without the owner":
  accepted), so the repository has no licence file.

Interpretations of the spec's scope (plan §0.1). The owner's later direction ("I like the beginning
as a tutorial but it needs to open up to an open world to explore in the world"; the plan's Inputs
row) is read as follows: the Valley stays the 400 x 400 m slice of spec §14 and becomes the prologue
(decision 40), and the open world the owner asked for is a second, streamed level of 2 x 2 km, not an
enlarged Valley or a seamless continent (decisions 41-42). Stopping growth at stage 6 of the spec's
ten is the plan's own scope; the owner's direction ("continue to build the game") set no limit.
Stages 7-10 stay deferred, as spec §14 deferred "all ten playable sizes", and boss grapples, dragons
and the rest of plan §0.4 stay deferred with them (decision 59).

A further reading of spec §14 comes from the plan, not from the owner's direction: the spec asks for
accelerated quest XP "only in this slice" (the Valley), and the M6-M9 plan keeps it in the world,
still labelled "Prototype pacing" (plan decision 25, here 55; plan §5.7: "All quests keep
`prototype_pacing: true`"). The growth brief had offered either dropping the acceleration or keeping
the label (`docs/plans/briefs/growth_extension.md` §5.1). Every quest's XP shows the label, and the
campaign's end screen reads "The Old Kingdom - prototype pacing".

## 2. Deviations recorded by the packages

### 2.1 M2-M5 (P01-P18)

The ones that change behaviour or a contract, in short; the system docs give the reasons in full.

**P01 Core seams.** Schema anchors sit inside each module's `fields()` and `semantic()` (code at
the top of a file cannot reach them). Hooks take `hook(tick)`. `override_record` refreshes cached
`ActionDef`s in place and can create and remove test records. `preview_reason` reports "busy" for
every RETRY. EXECUTING honours cancel rules like CASTING. A status refresh keeps the later expiry.
`healed` reports the health actually gained. `const V := DataValidator` does not parse on 4.6.3, so
schema modules spell the class out.

**P02 Actor seams.** `weapon_hit_radius()` is a fifth duck-typed actor method for AttackRunner.
`ResetHooks` entries may carry a failure message ("screen left open"). Anchor rows of other
packages are checked once their creator has landed. A compile check of every script backs
`tools/check.sh`, because `--import` does not parse scripts. The M1 "Nothing to grab here yet"
message is gone (E with no candidate does nothing). The M1 soak's result stayed byte-identical.

**P03 Abilities and screens.** The target line reads `» Soldier` (the default font has no `→`).
Projectile meshes live in ProjectileSystem. Timings the plan left open (Sweeping Blow 0.30 / 0.10 /
0.40 s, the self buffs, the roar; Titan Surge has no cooldown). A non-piercing projectile hits every
target touched at its first hit sub-step. ScreenStack sets the MENU input context for every modal
screen, pausing or not. Any player component may add request parameters for the hotbar
(`preview_params`), so the HUD and the controller share one code path.

**P04 Scene kit, wolf, morale.** The wolf lunge's active phase is 0.45 s, not 0.25 s (9 m/s for
0.25 s cannot reach the giant from the planned band). `SceneKit.save` also renumbers resource ids,
so `--only` and full builds write identical files. Flee points fall back to a path's end. Token
holders take turns, so a third attacker gets one. A dormant (tier 2) actor releases its tokens.
Weapon arcs gained `pitch_mid_deg` (M2 gate, below).

**P05 Growth and shrines.** The camera also hides the head when the arm is pressed close behind it
(the plan's 1.2 x radius rule missed a stage-3 giant under the growth course's roof). Per-action arc
pitch exceptions. Growth refusals gain `already`, and airborne counts as `busy`. Rest heals and
removes debuffs but keeps fury, buffs and cooldowns, and is not gated by combat. A save restore
applies the stage silently (no `growth_changed`).

**P06 Session and saves.** Only the Valley writes the slot (a test level in sandbox mode keeps its
checkpoints in memory). The death floor applies after the character state. New Game asks before
replacing a save. Continue needs the save's level, not the Valley. The loading frame pauses the
tree, so the seeded soak keeps its exact timeline. The death confirm (Enter / pad A) runs in
`main._input`.

**P07 Grab and throw.** A held body leaves the simulation through `process_mode` DISABLED (P04's
dormant tier). The lunge uses the motor's knockback channel. One-hand holds use the off hand; in
first person every hold is low and to the left. While holding, every ability but a crush is
refused. Throw numbers: P40 x 1.2, poise 30, 20 m/s, range 20 m, a 1.5 m splash. Crushing Grip is
0.25 / 0.10 / 0.35 s and never crits.

**P08 Props and weapons.** `protected` props report IMMUNE `not_permitted` (the notes are
CombatEntity's). The fortified gate has two stages. The practice gate drops 2 wood scraps. Moveset
timings are whole ticks (the sword 10 / 7 / 14, the maul 17 / 9 / 23). The tree is a mid-range
weapon carried raised; its sweeps miss the giant's feet. The nav-link test uses an authored navmesh
(a runtime bake raced Godot's asynchronous map iterations).

**P09 Archer, mage, readability.** Launch slots are padded by the windup difference. Shots wait
until the unit is settled at its firing point. Line of sight is checked from the launch height
(1.45 m), so cover lower than that works. The barrier is a `targets_ally` cast whose
`on_hit_statuses` land on the ally. The kick is a short sector pulse. The ranged playground's climb
is a slow suite.

**P10a Level framework.** RETURN (the leash) is driven by the actor with the AI paused; full health
6 s after the leash or on arrival. Members that do not fit the budget spawn in id order as room
frees up. `despawn` frees at the end of the frame. Area events are deferred to the end of the
physics frame. Offline navmeshes carve solid boxes with projected obstructions (no islands inside
pillars). Test records ship in `data/world/`, one record per JSON file.

**P10b Valley world.** One record per JSON file (`encounter_<name>.json`). Per-layer nav links. The
search-limit fix (decision 1). MultiMesh transforms are written as a buffer (the headless renderer
drops `set_instance_transform`). Navmeshes are external files. A ridge separates the forest from
the fields, the bridge has blocker rails, and nothing reaches the ruins but through the practice
gate. The Hollow cottage arch (an optional stage-1 shortcut) was not built.

**P11a Ogre and boss.** Super armour covers the windup and active phases only. Strikes are pulses
that match their telegraphs exactly. The combo chains through the controller's input buffer. The
charge passes through actors and shoves the giant aside. A sequence entry is skipped only after 2 s
of patience near its range band. The king faces the entrance (yaw 0). The ogre's stagger is 2.0 s
against a giant twice its height (the stage-3 grab window).

**P11b Civilians and factions.** Five one-line hooks outside the P11b anchors (the faction behaviour
acts inside existing functions). FactionState is a shared hub, not a node. The sparring post is not
in the `enemies` group (it would hold the M1 soak forever) and stands west of the sandbox's test
wall. The brace reaches 4 m. Neutral guards keep their guard up while they watch. Hostility wins
over standing down. The elder never flees. Village guards do not count toward the budget while
neutral (they held half the director's slots across the map).

**P12 Progression.** The auto-slot prefers an ability's own §4.7 slot. Level 99 in a save means
"never gated". `xp` in the save is the total. Kill XP needs team ENEMY and the `enemies` group (a
prop pays through its own XP). Raider loot is wood scrap, never iron (the five ingots of §4.7 stay
exact). The progression post-pass checks the forge's upgrade rule.

**P13 Quests and dialogue.** For quests, `entered` holds once the area was entered since the load
(tutorial triggers: presence only). Kill and destroy conditions read the saved deltas and the
deaths seen since the load. Dialogue outcomes persist as flags. Id prefixes are enforced. A node
with no choice gets an implicit `[Leave]`. The main quest's completion is a checkpoint. A quest's
start emits only `quest_started`.

**P14 Performance.** CPU per tick is timed from inside the physics step (the engine's `TIME_*`
monitors are per-second maxima on 4.6). The stress arena has its own level record and spawner (no
director, so every combatant runs AI tier 0, the worst case), puts fresh breakables in place after
each lap, and grows the giant to stage 2. A preset's `shadow_distance_m` 0 switches sun shadows off.

**P15 Content.** Stages that complete on `entered` also accept the states that can only come after
them (a reload resets level memory). `quest.tutorial` is abandoned at stage 2. Every prompt that
waits for an action has a fallback timeout. The village captain stands beside the barricade's road,
not in it. The dressing is batched in `CosmeticField` MultiMeshes. The Hollow cottage arch stays
unbuilt.

**P16 UX and controller.** Pad A and B join `ui_accept` / `ui_cancel` at run time (Godot 4.6's
defaults hold no pad button). A "Button prompts" setting pins the glyphs. A rebinding capture gives
up after 6 s (a pad has no Esc). LB / RB switch pages and tabs. A menu footer names the keys. The
ability notice moved to the top centre; the boss bar is 540 px wide. An out-of-range Runic Bolt is
refused, not only shown. Growth clearance counts actors.

**P17a Valley bot.** Result files go to `user://bot_runs/<tag>/`. The bot plays the optional
tutorial (bounded by 120 s). The assisted mode is a hidden status, so the damage path is unchanged.
Additions to the plan's bot rules, each found needed in a run: `--bot-trace`, the errand give-up,
the rest before a kill objective, the reach band, the tree only for the Deadfall, the walk back out
of a navmesh pocket.

**P17b Balance.** A game-code change in a tuning package: the vertical aim (decision 5), because the
short reach was geometry, not a number. Bot fixes that correct measurement mistakes, never the
difficulty. `test_obstacle_route` moved to the slow suites (the default suite's 75 s budget). The
village yard's navmesh pocket is not fixed. The human time estimate stays below 20 minutes and no
content was added to pad it. The Ogre King keeps 1,500 health.

**P18 Ship.** A Valley screenshot tour that runs beside the bot (`tools/valley_tour.gd`; P17b's
optional capture scenario was not built); the actors' draw calls documented as a known limitation
instead of a late renderer change; one HUD message fixed that the tour's shots showed (a destroyed
prop was named by its district); the version `0.5.0-m5`. See [docs/systems/P18.md](systems/P18.md).

### 2.2 M6-M9 (P19-P40)

The ones that change behaviour or a contract, in short. Each package's system document has a
"Decisions and deviations" (or "Deviations") section with the reasons in full (P39f's has none: each
fix's own section gives its reasons, and each part's "Left, and why" what it left), and its gate
sections the later changes.

**P19 Audio engine.** A threat sting's expected damage is computed with `DamageResolver.mitigate` on
a crit-free `HitEvent` (the plan's `DamageResolver.preview` does not exist); it reads no random
number. The threat sting has a cue of its own (falling back to the windup's, it was dropped by the
retrigger guard). Extra mix blocks: `steps`, `threat` (the router's thresholds as data) and
`footfall.stop_gap_s`. A music stem shared by two sets must share their frame, checked through the
manifest. Cross-record catalogue problems are `Audio.catalog_problems()`, not load errors. The test
runner is silent by default (`--with-audio`). Desktop sample registration is a no-op but still
loads the level's streams behind the loading screen. About 4,570 lines of GDScript against the
plan's 3,500 in all.

**P20 Campaign foundations.** The per-visit set of activated shrines and waystones clears when a
level loads, not on `level_entered`. Every load with a giant emits `level_entered` (the sandbox's
with reason `debug`). The index fallback for a checkpoint lives in `respawn_transform`. Fast travel
waits for aware enemies like a checkpoint (only the open map is ignored); a refused travel is a HUD
warning. Continue on a save whose level this build lacks goes to the Valley's return checkpoint.
`world_start` leaves out the crown and the Valley's world deltas but keeps the force run's tutorial
flags. Beyond the owned files: the dialogue screen's greyed choices and the new condition shapes in
`schema_util.gd`. M7 polish: a migrated save also gets the `visited.<id>` flags its progress proves
(beyond §2.6's "nothing else changes").

**P21 Sound effects.** The giant's own body (casts, buffs, grabs, guard, voice, growth) is
non-positional, because as a 3D voice at the listener's chest every cue played at the +3 dB cap;
its footfalls stay positional. Masters are normalised to −6 dBFS peak and balanced in the banks by
measured A-weighted loudness, not by ear. The threat family's separation test uses the RMS frequency
for the spectral centroid (no FFT in GDScript). Four routing rules: hurt calls for every voiced body,
voiceless bodies by material, roar actions voicing a roar, wet ground by the level's water. 215 cues
over 209 files (the plan: 188); caps and retrigger guards per cue (the engine has no per-family cap);
cruise steps only at stage 3.

**P22 Rigs and M5 polish.** The ogre's rig has 6 meshes and the giant's 8 (the plan: 7 and 9). The
far proxy lives under `Visual/Body`, so it falls and hides with the body and `set_lod_tier` needed no
change. The rendered draw-call check measures the stress arena's twelve combatants (−65 %); the whole
view fell 23 % at the median, a miss of the plan's 40 %. Thornwick's guard posts stand at x 73.5 (the
plan's x 72 is inside a cottage wall). Reconciled faction members need no actor change. The give-way
civilian is brain logic.

**P23 Music and ambience.** Loudness (LUFS), not peaks, balances the score; the beds sit at −17 to
−18 LUFS rather than the plan's −12 dBFS RMS, which would have put them about 6 dB over the explore
mix. Melodies are rendered segment by segment. Beds are stereo, everything else mono at 22.05 kHz.
The audio-thread crash is fixed in the audio director (a mixing barrier), not in the voice pool. The
silent list is an `audio_region` record. Godot 4.6.3 imports Ogg at about 1.11 x its size, not 1.03
(the budget arithmetic uses 1.11). 18 ambience spots, not 14. The web check's hole criterion has two
forms: by default a hole the main thread's long frames explain passes, and `--strict` is the plan's
criterion as written, which software WebGL cannot pass. The default tier's audio suites run over
their 0.5 s cap (0.58-0.81 s).

**P24a Terrain and streaming.** `ChunkData.far_scenery` (not in the plan) keeps a settlement's merged
buildings on the horizon while its trees fade. Deterministic streaming loads synchronously; heavy
steps run alone in a frame, and a props part's dependencies load one a step. The border rule's
tolerance is 35.05° (a quantised 35° ramp passes). The skyline's shader globals are registered at
run time. A web export does not compile a bare `free()` on self (`queue_free()`). The stream check
judges the page's own frame intervals, because the engine's frame delta is capped at 133 ms. The slow
walk test takes the better of two walks when the first's work p99 is over 6 ms (wall time on a shared
machine).

**P24b Navigation and the director.** A gate region takes every titan polygon that touches gated
ground (Recast's long border polygons let a stage-3 mask cross otherwise). `NavQuery.path` lets the
query snap its goal instead of a closest-point scan first (about 1 ms saved). A chase whose path ends
short of a giant in deep water stops at the bank. Waypoints are levelled in a streamed world (an
agent never reached a waypoint 0.75 m over its feet). Asynchronous iterations stay on in interactive
desktop play. An encounter updates only while its centre chunk is loaded and ready. The leash rule is
GameData's. The determinism gate compares results without their wall-time fields and adds an AI trace.

**P25 World builder.** Border relaxation cannot bend a planar 35-45° slope, so the builder first runs
a slope-limiting projection. Coordinates moved from plan §5.4 where a point fell on water, a gate
region or outside its landmark's reach (listed in P25.md). Titan-sized places: vault doors of 15 m,
the Moot's gate 28 m wide. A size gate's rectangle is drawn in by 6 m for the gate split, so open
ground beside the Giant's Stair is not closed to stages 4-5. The reachability check (119 places) is
a gate suite, not a builder check. The rim is walled (bounds walls 400 m tall). The Kingsgate,
Greywood and Aldmere shrine POIs give no discovery XP (the Standing Stones' shrine POI gives 40). The
Hidden Grove's second key is a stage-5 rockfall on its north ridge.

**P26 Growth 4-6 and the Valley's exits.** The Valley's revisit test is a corridor test and every
checkpoint measures `max_stage` 6. The Citadel's gateway is 20 m tall so a stage-6 giant can enter.
A second new waystone, `valley.cp.citadel_stair`. The reach matrix of the default tier is geometric;
the real swings are slow-tier tests. Props built but not placed in the Valley (the trample palisade,
the great pine, the titan-tree, the toppled statue, the size-gate walls) serve the world's packages.

**P27 Open-world UX.** The compass spans ±270 px and the region banner sits at 206-252 px (the plan's
places met other panels). A vista's POIs are `"revealed"`: on the map and compass, but their XP waits
for the visit. A sealed place is found only once its seal opens. The pin is `[x, z, level]`. Two flags
beyond the plan (`sealed.seen_count`, `map.opened`). The world's tutorials wait for
`progress.world_entered`. The HUD's batching (`hud_kit.gd`) touched every widget: the wave gave P27
the whole HUD's draw calls.

**P28 World audio.** The region and boss sets use the Valley's zone frame and phrase writer (one
kingdom's score; Aldmere adds a snare). Aliases instead of new samples wherever a file would add
nothing. The incoming whistle starts at the launch, not at the telegraph. A formation is heard as one
body. The settlement arrival plays once per level visit. The new creatures' voices are found by
archetype (the mix's voices must name records that did not exist yet). 98 effect files rather than
112; one extra loop.

**P29 The Crownmarch.** The toll fort's garrison and its captain are two encounters (the fort can be
cleared without killing the talker), the garrison standing down by `stand_down_when`. Edda's "free
reinforcement" is paid as 2 iron. The cluster cap of 12 individuals is checked over cliques of
encounters within 150 m of each other. Brannock's archers stand inside the wall (on it they began
outside their leash). The XP budget's unavoidable discoveries count the arrival's and the objectives'
places.

**P30 Formations.** `FormationRules` is a file of its own (the schema needs it without the actors).
The brace's size override lives in the band pulse; the general override is P32's. The target
provider flips an NPC's or prop's team to the player's for the unit's own hit query only. From stage
4 an outmatched soldier with no formation to join flees and routs. The banner's lock threat is 0.55,
so the formation wins the first lock and the banner is one switch away. Audio data for the new
soldiers in P28's files (additive).

**P31 Abilities and weapons.** The reinforced and titanforged sword and maul are longer (1.9 m and
1.8 m) so their stage 4-6 blows land at 0.9 x the melee reach. Bulwark takes x0.4 from every side.
Shoulder Charge runs at 26 m/s. Perk distances grow with the weapon. Storm Call sets Burning on
everything it strikes. The status ids follow the cues P28 had named (`status.stonewall_stance`,
`status.primal_regrowth`).

**P32 Siege, cavalry and fists.** The bolt's poise is 140, not 60 (decision 51). An engine's throw is
its own action (`ability.throw_engine`), the engine riding the projectile to smash where it lands.
`SiegeRules` is a file of its own. Engines run their own controller and runner. An engine turns
neutral as it breaks (otherwise its death also counted as an ally's). Ready engines take turns for
the launch slot. The cavalry record has no awe. Thunderhead staggers riders.

**P33 Talents and ancestries.** The level cap stays 20; level 12 is where the last tier opens. Each
talent of tiers 2-4 needs the one above it in its column, a crown both talents of tier 4. Costs and
cooldowns scale through per-character action copies; heals and poise damage through the combatant's
own pool and meter; grab reach through a raised copy of the growth profile. The sprint costs less
under Relentless and Tireless too. `ancestry_chosen` is derived from the ancestry itself. The
ancestry is offered once the world has opened (`progress.world_entered`).

**P34 Trolls, rival giants, bosses.** Trolls and rival giants do not join Thunderhead's stagger. Iron
guards use the shieldman's scene. Burning deals no damage (a marker status); a burning whelp's 300 on
the Matriarch is an explicit fire hit. The phase-spent rule: a battle phase whose units have all
fallen gives way to the next even above its fraction. Every director spawn moves out of the giant's
footprint. Actions are cancelled through `CombatController._finish_action` (no public cancel).

**P35 The Greywood and the Drowned Steps.** Encounters moved off the plan's points where they fell
on a waystone, a 36° ridge or water; the fourth bell hangs in the Wend's deep reach (the terrain has
no stage-4 pool where the plan put it); Sedge's oath has three stages (meet, den, swear); the
Stoneknuckles' rack waits for the bells, not the quest; the troll pack after the drive is a wander
entry; the bell's material is iron.

**P36 Aldmere, the Stonehold and the finale.** The siege line is the toll-riders' hired company, not
Aldmere's own (a reconciled Aldmere would otherwise never besiege Skarn); its engines appear with the
siege (`ConditionSpawn`). The siege's "fail timer" is its bombardment (only while the giant is within
200 m), with a 600 s backstop since the M8 gate. The crown oath's XP sits on its resolve stage (the
plan's totals). Two helper quests write the breach and sabotage outcomes. The wander tables' siege
trains are not shipped. The tower ballista stands on a new open gun tower. The Iron Regiment's web
composition keeps three of Corvane's six guards (aggregate 11,740 on the web, 14,080 on the desktop).

**P37 The living world.** The living world runs in the campaign only. Spawn `targets` and `prefer` are
encounter fields beyond plan §2.13. Columns walk the index's road graph between two places (the world
has no patrol routes). The army column starts on the road east of the toll fort. Raiders take
house-tagged props too and raid each for himself. An event unloaded for 600 s is abandoned with no
outcome. The toll-riders' siege train and the reeve's changed dialogue were deferred (the dialogue
was added in W23).

**P38 The world bot.** In the world the bot checks the director's own budget rule (no counted member
spawns at the cap) instead of the Valley's strict 12, since a faction turning hostile with its
members in the world may pass the cap. The den, the battle and the duel fight on their own terms
before other threats. An arena leash and a boss fight's respawn waystone are the bot's own rules. The
engage radius is 2.5 x the melee reach from stage 4. The watchdog adds a travel allowance. The
drive-out waits for the woodfolk. A fixed passive talent build per skill. `--bot-until=<flag>`.

**P39 Stability, balance and how it plays.** The bolt's poise stays 140 (only its power fell). The
Iron Regiment's Charge threshold was left to the merged code (it became the W23 confirmation's fix,
§3.2). The lone soldier's awe was left for the merged code. The Iron Regiment's web aggregate is kept
by decision. The world walk's tour passes its own route. The formation stress's two engines are
placed at run time. The report's set is the novice's runs made again on the final numbers. No fourth
tuning iteration; fix-up 1 made the Matriarch's brazier lure the expert's alone, because it cost the
novice a slay.

**P39f Fixes and polish.** Every defect of the FOLLOWUPS rows it took was reproduced on `wave-22` (a
failing test or a probe of the shipped world) before it was fixed; the one its verifier found in the
lane's own new give-up rule (fix-up round 1: the count ran on while a raider fought the giant) was
reproduced on the lane's code (`6fe8d7d`). Left, with reasons: far people as plain posts, faint seams
in the distant haze, the siege trains of the wander tables (a framework change), the worst streaming
frame headless (a text scene's parse; exports ship binary scenes), and Godot's exit-time report of
resources held by process-lifetime caches after a completed campaign (recorded, not hidden). The web
checks' default verdicts pass a hole cut short by the recording's end with no driver read inside it
(`holes_cut_at_disarm`, reported apart); the strict forms are unchanged.

**P40 Ship.** ⟦SHIP: P40's deviations from plan §3.24 in short, as P18's paragraph does (the world tour's tool and route, any fix its shots led to, the final check, the exports and web checks, any fix outside its owned paths, what was left), from docs/systems/P40.md⟧ See [docs/systems/P40.md](systems/P40.md).

## 3. Fixes from the milestone gate reviews

### 3.1 M2-M5 and their Ship gate

Each milestone gate, and the Ship gate at the end, had an independent review. Every confirmed
finding was fixed with a regression test, or handed to the package that owned the files through
`docs/plans/FOLLOWUPS.md` (all closed or deferred there).

| Gate | Finding | Fix |
| --- | --- | --- |
| M2 | The stage-1 light chain passed over a 0.9 m wolf at the giant's feet. | Weapon arcs gained `pitch_mid_deg` (a curved pitch); lights 1 and 2 dip low in front (P04). |
| M2 | The seeded soak no longer broke the fence after the wolves arrived. | A soak target order (engaged enemies, the fence, then the rest) and a `check.sh` coverage check. |
| M3 | A released body counted as broken poise, so one stagger allowed endless re-grabs. | `PlayerGrab.has_broken_poise`: a release's recovery is not a poise break (P07). |
| M4 | A tutorial prompt's fallback timeout lost its lesson (the quest stage could never complete). | A lesson stays open after its prompt is taken away (P13's tutorial director). |
| M4 | Threat arrows and the objective marker drew under the TIP box and the hotbar. | Both overlays draw last and slide along the edge clear of every panel (`HudEdge`, P16). |
| Ship | The handoff counted P17a's assisted runs of the four village outcomes as runs on the same game code, and as the M4 gate's evidence, but P17b retuned the game after them. | The four outcomes ran assisted on the final code (handoff §6.2, all completed) and the M4 row cites those runs; §1 and §6.4 say P17a's runs came before P17b's tuning (`test_ship_docs`). |
| Ship | The owner's spec names the AI tools it was written for and drawn from; the repository is meant to name no AI product or model. | One recorded exception: `GIANTBORN_SPEC_V2.md` stays verbatim, and its source note says so. No other file names an AI product or model. The hosting platform's own names are allowed, since they name no product or model: the claude.ai play link, the launcher's `claude:viewport-fit-sides` meta tag and `window.claude` hook, and the integration branch. `test_ship_docs` checks every text file in the repository. The owner may still redact the spec instead; the test's exception then goes. |

### 3.2 M6-M9

Each M6-M9 gate had a review (plan §1.3), and the M8 gate an audit and a re-audit besides; every
confirmed finding was fixed with a regression test or handed on through `docs/plans/FOLLOWUPS.md`
(open rows: `docs/M6_M9_HANDOFF.md` §8). The fixes, in short; the M6 gate's inline "M6 gate" notes
(P04, P17b, P19, P21, P23), each package's "M7 gate", "M7 polish", "M8 gate", "M8 screenshot pass"
and "M8 release" sections, and the M9 gate lanes' sections of `docs/systems/P39.md` and
`docs/systems/P39f.md`
⟦SHIP: their exact names once the lanes have merged (so far "The M9 gate (lane aldmere): ..." and "The M9 gate (lane ironreg): ..." in P39.md and "M9 gate (lane review)" in P39f.md; and lane balance's, if it adds one)⟧
have the detail and the tests.

| Gate | Finding | Fix |
| --- | --- | --- |
| M6 | Seeded Valley bot runs played differently with and without audio. | The loading gate also waits for the level's navigation map, the autopilot waits with it, headless runs sync navigation on the main thread (P19; gate suite `test_valley_audio_determinism`). |
| M6 | A far threat sting reached the listener 21-30 dB down, under the combat music. | The sting and the aim lock moved to the mix's `alert` class (P21; `test_threat_audibility`). |
| M6 | The expert's crown stage on the intimidate path ran out its watchdog: a wolf pack broken by a giant that outmatches it kept coming back to harass. | Such a pack routs (`tactics.outmatched_rout`); the Valley bot's stall at an encounter lasts while it stays within 15 m (`docs/BALANCE_LOG.md`, "M6 gate"). |
| M6 | The web audio check could not tell a hole in the music caused by slow frames from a real fault, and its pass did not say the plan's criterion was not met. | Every report states the criterion's verdict, a default pass with holes says "the plan's criterion NOT MET", a failed run keeps its trace; the check has its own stub test (P23). The criterion itself is the owner's to run on a GPU (`docs/M6_M9_HANDOFF.md` §5.1: NOT RUN). |
| M6 | The Valley's largest views at `low` passed the 250 draw-call budget by 3-18 (five of the seven districts the walk measured, at 253-268; `docs/PERFORMANCE.md`, "Draw calls at the M6 gate"). | Recorded as a measured miss and handed on; fixed by P30's mid distance and P27's batched HUD (max 154; `docs/PERFORMANCE.md`, "Draw calls after P27"). |
| M7 | The Crownmarch's formation fights never threatened a stage-4 giant: the director leashed the toll fort's pikes as soon as they advanced, the advance stopped half a metre outside the brace distance, and the brace struck where its telegraph no longer was. | A formation's reach must lie inside its leash (a schema rule) and the director leaves an intact formation's members to it; the advance ends inside the brace distance; the brace keeps the band its windup drew (P30, P29; `test_m7_gate_fixes`, `test_m7_gate_world`). |
| M7 | The map offered fast travel to a hostile town's waystone, and the reload woke the giant at the stone it had left without a word. | Fast travel is refused for a stone its respawn blockers refuse, judged in the destination's level; a load that moves the respawn says why (P27, P29, P20). |
| M7 | Ranged units' firing, flee and rout searches spent up to 51 path queries in a tick (37 ms) at a giant 200 m away. | Searches keep the per-tick budget, take one candidate a tick and resume where they stopped; a target beyond the chase cap is not searched for (P24b). |
| M7 | The M7 web check had no music recorder. | `stream_check.mjs --world --audio` records the music across region borders (P24a's tool); the strict criterion is the owner's (NOT RUN). |
| M7 polish | The review's smaller items. | A migrated save keeps the stones it reached (P20); `build_web.sh` fails over the milestone's budget (P22); the world's default walk route (P24a, P25); the toll fort's tower archers hold a post on the gate tower (P09, P29); civilians' searches within the budget and the human map's edge merge (P24b); a won oath drops its lead; an objective on another level leads to this level's door; a formation whose members all flee stays broken while its banner lives (P30). |
| M8 | The review's findings (numbered F1-F47) and the audit's and the re-audit's (N2-N4), fixed in six lanes over three rounds (m8y and m8e; m8b and m8s; m8q and m8p) and two fix-up rounds (the merges `6c83590` to `241bf80`). | Among them: no boss can be grabbed, and no fight input decides the yield prompt (F13, F7, N3.1); Harrok struck rises to a fight the bar and the music follow (F11); a boss out of sight walks round what hides the giant (F36); the battle's arena is the bailey and fits the caps with the gate garrison alive (F8, F9); battle kill XP paid once (F14); shrine choices and a boss's end saved at once (F15, F38); the world's main thread checkpointed (N4.2); world events left behind hold no slot and survive a Continue, and the siege's shots burn the longhouses (F2, F19, F12); wanderers on open roads, the index's road kinds (F18); the world's scripts loaded behind the loading screen (F26); every view of the world at 40 static draw calls or fewer at `low` (F27); every size gate names its stage (F29); the main-thread combinations win every oath through its real writers (F3); the crown's battle and ridge write the oath's meeting (F39); the stage-4 Matriarch re-measured and handed to P39 (F37). |
| M8 screenshot pass | Trees hid the giant; the lock line was blank; riders never charged. | Trees between the camera and the giant fade (`scenery_fade.gdshader`, V1); the lock line names the target and its distance again (V2); riders hold their pickets and charge within reach (V3). The HUD, map and screen rows went to P39f (fixed in W23). |
| M8 release | R1 (blocker): a checkpoint held back before Fort Aldmere's battle was committed mid-battle, and after a death or a Continue the giant was shut in the bailey with a Wall that never came back. R2: the title's save line named a respawn Continue did not use. R3: the novice cannot win the Iron Regiment. | R1: no checkpoint while a fight is engaged; a battle starts every attempt afresh and repairs a save written mid-battle; Harrok's talk ending mid-duel ends the duel without a victory (P34, P06, P36, P19, P20; `test_battle_reload`, `test_fight_checkpoints`, `test_iron_regiment_reload`). R2: the line names where Continue wakes the giant. R3: left for P39's balance pass. |
| M9 (W23 confirmation) | The Iron Regiment's Charge (at 0.60 of the battle's bar) and Last Stand (0.25) could not begin while the fort's ballistae and the Wall's two crews stood (the bar stopped at 0.622 / 0.670 after the Wall, 0.452 / 0.465 after the riders). | A layout defect: the thresholds are 0.70 and 0.50 for every composition (commit `a7da72d`; `test_aldmere_stonehold_content`, gate `test_iron_regiment_world`). Also in W23: the brazier lure made the expert's alone (P39 fix-up 1), the raiders' give-up count (P39f fix-up 1). |
| M9 gate | ⟦SHIP: the M9 gate's findings and their fixes, one row each (its review's, and any audit's or check's after the lanes' merge), from every commit after `wave-23` (`f851b0d`) up to the code the M9 gate shipped (its final commit or tag): the fix lanes fix/m9-aldmere, fix/m9-ironreg, fix/m9-balance and fix/m9-review, any later fix-up lane, and every fix made on the integration branch at or after their merge (as W23's `a7da72d` was); sources: those commits, their system-doc notes, docs/BALANCE_LOG.md's M9 gate sections and, for a finding handed on, its docs/plans/FOLLOWUPS.md row; and the tuning they made, with its reasons⟧ | ⟦SHIP: as the finding's row⟧ |
| Ship (W24) | ⟦SHIP: the Ship gate review's findings and their fixes, if any (P40's own review), one row each⟧ | ⟦SHIP: as the finding's row⟧ |

## 4. The plans' review logs

### 4.1 The M2-M5 plan (its §7)

Before any code, the plan was reviewed three times: spec coverage (26 findings), feasibility (22)
and gameplay (21). Every finding led to a change, most of them exactly as suggested. The ones whose
fix was changed, or partly rejected, and why:

- **Weapon fit** (coverage 1): the club fits stage 2, not stage 1 (growth to stage 2 comes long
  before any forge), and an outgrown weapon keeps its last fitted size with a warning instead of
  being refused.
- **Neutral guards** (coverage 5): eligibility is "team ENEMY, or NEUTRAL without a faction", not
  "team ENEMY only", because the practice dummy is NEUTRAL and lockable.
- **Regrouping** (coverage 10): `regroup_needs_leader` defaults to true and the leader is a commander
  or a non-fleeing ally within 20 m (the suggested "highest-morale unit" always exists).
- **The P11 split** (feasibility 8): P11b runs in wave 7 and the NPC talker moved to P13.
- **Checkpoint placement** (gameplay 2): the forest waystone is at (−140, 38) and the Thornwick shrine
  at (14, −26), away from the hunters and the guard posts.
- **Grab** (gameplay 4): reach = melee reach + 0.5 m with a lunge; knockback on the poise-breaking
  hit is not suppressed.
- **Time targets** (gameplay 6): the 20-30 minute target applies to the human estimate, with a raw
  13-26 minute sanity band.
- **The King's numbers** (gameplay 9): recomputed with the spec's formula (76 / 92 / 126 before
  tuning).
- **Village area effects** (gameplay 14): area effects skip faction members; the first direct hit
  only warns.
- **The courtyard's leash** (gameplay 17): 55 m, not 70 m (70 m reaches past the causeway).
- **The ability schedule** (gameplay 18): Mend and Roar are taught at the village, and the XP of four
  stages was raised so the worst outcome still reaches level 4 at the gate.
- **The ogre's punish window** (gameplay 19): the recovery multiplier is 3.5, not 3.0 (3.0 left one
  stage-1 heavy below the ogre's poise).
- **Boulder aim** (gameplay 21): the landing marker shows during the 0.45 s windup (abilities fire
  on press).

### 4.2 The M6-M9 plan (its §8)

Before any code, the M6-M9 plan's first draft was reviewed three times: the owner's direction and the
spec (30 items), feasibility (22) and design quality (25). Facts the changes rest on were re-verified
in the code and in scratch experiments (navigation readiness with async iterations on and off, the
`NavigationServer3D` path API, bit-exact libvorbis encodes, a per-file audio budget). Every item but
one was accepted, most as suggested; one was rejected in part. The ones whose fix changed, the two
whose facts were re-measured, the one rejected in part, and why:

- **Music and ambience masters not kept** (owner and spec): changed fix - the generators are the
  masters, proven bit-exact by `--verify`, with FLAC on request (§1.3; decision 34).
- **No weapon lands light 3 at stage 4 in M7** and **no fitting weapon at stage 4** (owner and spec;
  design, a blocker): changed fix - reach separated from crafting: any reinforced weapon fits stage 6
  with its family's stage moveset, base weapons still fit stage 2 so the Valley's forge lesson stays
  (decision 54).
- **The Matriarch grab breaks the 50 % rule and the deferral**: the first option, adapted - she stays
  9 m and cannot be grabbed; fire comes from braziers and from whelps or trolls thrown into her pit.
- **Deterministic streaming does not make navigation deterministic** (a blocker): accepted and
  re-measured (12-24 ticks of readiness jitter with the defaults, 1 tick with async iterations off on
  both maps and regions; decision 43).
- **`map_get_path` cannot take a polygon limit**: accepted and re-verified (it stopped 467 m short on
  an 8,100-polygon map; `query_path` did not): every call site through `NavQuery` (decision 43).
- **The world data budget and the host's 16 MB file cap**: changed fix - the one pck ships in parts
  the launcher joins, instead of a second resource pack (decision 38).
- **"No checkpoint is written when the slice completes"** (feasibility): rejected in part - the code
  already took one (P17a's completion checkpoint), so finished v1 saves hold `slice.completed`.
- **P38 reaches P37's APIs in the same wave**: changed fix - P37 moved two waves earlier.
- **The `oaths` stage gives no lead**: changed fix - the main stage's three markers lead to the three
  powers, rather than starting all three oath quests at once.
- **Thin stage-gated returns; the Grove missable**: changed fix - the Grove's second key, nine sealed
  places, cairns that give an attribute point (an existing currency) rather than a new progression.
- **Accidental betrayal of a yield**: a stronger fix - the yield protocol (immunity, earlier hits
  discarded, a held confirm in a prompt).
- **Trolls' fire counter unlearnable**: changed fix - braziers or bonfires at every troll site and a
  lesson at the woodcutters' camp; burning logs were left out (carrying props would need a second grab
  path).

## 5. The M0/M1 decisions

The combat sandbox's rules. They still hold unless a row says what replaced them.

### Engine and project

| Decision | Why |
| --- | --- |
| **Godot 4.6.3-stable (official build `7d41c59c4`)**, GDScript, Compatibility renderer | Latest patch of the previous stable line (4.7.2 was newest on 2026-11-04). The spec asks for a pinned stable version, not the newest. |
| Jolt Physics selected explicitly in `project.godot` | Godot's recommended 3D engine in 4.6; Area3D shape queries were probed and work. |
| Fixed 60 Hz simulation in the `Sim` autoload | All combat runs in whole ticks; rendering (camera, animation, UI) runs in `_process`. Since M2 `Sim` also has hook phases, named RNG streams and a status pass (`ARCHITECTURE.md`). |
| Physics interpolation **off** | Bodies move at 60 Hz. On displays above 60 Hz, bodies update at 60 Hz while the camera's mouse look stays per-frame. |
| Input bindings live in `data/input/default_bindings.json`, not `project.godot` | Keeps every binding remappable and data-driven; user overrides are saved in `user://settings.json`. |
| Scenes are generated by `tools/build_scenes.tscn` (since M2 a runner over one builder per area in `tools/builders/`) | Valid, editor-friendly `.tscn` files from code; `SceneKit.save` strips random ids, so a rebuild changes only what changed. **Once you edit scenes in the editor, the editor copy is the source of truth; re-running the tool overwrites it.** |
| Resets reload the scene | Since M4 by mode: the sandbox reloads fresh (F5, Restart sandbox, Enter after death); the Valley reloads the last checkpoint after a death. |

### Combat rules

| Topic | Decision |
| --- | --- |
| Timing | Seconds convert to ticks once (`round(s * 60)`). An action accepted at tick T is at elapsed 0; light attacks are active from elapsed 12 to 20 and finish at 39 (0.65 s). Dodge invulnerability covers elapsed 6 to 17 (0.10 s up to, not including, 0.30 s). |
| Parry window | A hit is a parry when `block_elapsed_ticks < 12` (the first 0.20 s), counting from the tick block was accepted. |
| Tapped block | A block press lasts at least the parry window (0.20 s), so a tap gives a full parry window. Holding never reopens it; a new press (and a new 5 stamina) is needed. |
| Held block | Block is a held stance. If the block input is still held when the giant is free to block again, blocking resumes: the 5 stamina entry cost but **no** parry window. Without a lock the guard faces the aim; pressing block snaps the facing to the aim or the locked target. |
| Unblockable / Unparryable | Independent flags. An Unblockable melee attack can still be parried inside the parry window; outside it, it ignores the block. An Unparryable attack can still be blocked. (The Ogre King's slam and charge carry both.) |
| Failed parry | A parryable hit inside the window that cannot be parried (for example, under 5 stamina) is an ordinary block **and consumes the window**. Successful parries do not consume it; each costs its own 5 stamina. |
| Guard break | 50 % of the pre-block mitigated damage; remaining stamina consumed; a 1.0 s stagger. |
| Blocked hits and poise | A successful block applies no poise damage to the blocker; stamina is the guard meter. |
| Parry poise | 40 poise damage to the attacker, not size-scaled (Titan Surge's +25 % applies to it since P11a). |
| Stagger immunity | 1.5 s after any stagger, against stun-locks; poise damage is ignored while staggered. |
| Interrupt policy | `interrupt_policy` per action (`hard_stagger` by default). `super_armor` is used since M4 by the ogres' and the King's strikes and covers the windup and active phases only (P11a). Interrupted actions are never refunded. |
| Cancel windows | Lights may cancel their recovery into the next light, a dodge or a block. Heavies may only dodge-cancel, from 0.25 s into recovery. Dodge may cancel into attacks, block or dodge from 0.15 s into its recovery. |
| Input buffer | One slot, newest wins, live for 9 ticks (0.15 s), then revalidated. Requests that fail on resources, cooldown, locks or empty slots are rejected at once with a reason and spend nothing. |
| Combo chain | The next light is used if requested during the current light's recovery or within 0.35 s after it. After light 3 the chain restarts. A heavy, an ability or an interruption breaks it. |
| Sprint | 8 stamina/s; locked at zero until released or back to 25. Shift + light issues one heavy. |
| Stamina regeneration | 15/s after 1.0 s without spending. |
| Fury | +4 the first time a basic attack instance damages a fury-granting target, +6 per parry, +8 per kill. Props never grant fury; abilities are not basic attacks. Titan Surge (100 fury, since M2) spends it. |
| Crits | 5 % for the player, rolled from the seeded `Sim.rng` in stable hit order (pinned by the 37 / 66 / 44 tests). Enemies have 0 %. Every newer random consumer has its own generator: a `Sim.rng_for` stream (loot, wander, the bots) or a private one seeded from its id (enemy brains, debris). |
| Same-tick deaths | Hits resolve in a stable order; hits from an attacker that died earlier in the same pass are dropped, except projectiles (decision 8). |
| Dead targets | Resolve as `IGNORED`: no damage, events, fury or resources. |
| Practice dummy | Armor 25, so on-screen numbers reproduce the worked example (light 37, heavy 66, Footfall 44). Unkillable; refills 3 s after the last hit; lockable. |
| Soldier | Health 220, armor 15, poise 40. Slash P=30 (0.55 s windup), overhead chop P=45 (0.85 s, telegraphed since M2). A frontal 120° guard with its own 40-point stamina while aware and not attacking; heavies break it; flank hits land fully. Since M4 also the brace counter, awe, and 1.2-1.8 s between strikes (P17b). |
| Heavy attack shape | An overhead slam from the right shoulder angled inward, so it lands on the centre line about 2 m ahead. |

### Hit detection

| Topic | Decision |
| --- | --- |
| Weapon shape | A capsule along the arm and weapon, swept from the previous to the current pose; the procedural rig reads the same `AttackGeometry`, so the visible swing is the tested swing. Since M3 it scales with the growth stage and the weapon's fit. |
| Sweeps | Sub-stepped at no more than 3/4 of the radius per step (up to 16 sub-steps per tick). |
| Occlusion | The line from the attack origin to the weapon point, and from the weapon point to the hurtbox, must be clear of world and breakable geometry (the target's own colliders excluded). |
| Query buffer | Starts at 64 results and doubles until nothing is cut off (hard cap 4096, with a warning). |
| Hurtboxes | Area3D volumes on their own layer; dedup per entity id. Large enemies have several lock anchors on one health pool (P11a). |

### Camera and targeting

| Topic | Decision |
| --- | --- |
| Third-person framing | Stage 1 shoulder offset 1.1 m, pitch −18°; growth scales the arm (about 6.5 / 9 / 12 m) and the lock orbit (P05). |
| Follow arm | One rigid arm swept with a 0.35 m sphere; retracts at once, restores at 6 m/s. The head is hidden when the arm is pressed close (P05). |
| Lock-on framing | Aims at the target's lock anchor for the viewer's height (a knee of the Ogre King at stages 1-2), pitch clamped −35°..+8°; small, close targets get a side orbit. |
| Aim and cone | Lock cone and target switching use horizontal directions; visibility is a ray from the eyes. Lock range 35 / 40 / 45 m by stage. Only hostile or faction-less targets are lockable (decision 17). |
| Wheel and stick flick | While locked the wheel switches targets; otherwise it zooms. A right-stick flick switches in third person; in first person only a flick that snaps back within 0.25 s does. |
| Controller combos | Ability slots and the ultimate are LT + button combos; while LT is held those buttons do nothing else. Remappable. |
| First person | Eye at 92 % of height; head, chest and belt on render layer 2, culled by the first-person camera. First-person lock never rotates the camera unless the optional aim assist is on. |
| Motion blur | None; the setting shows "Off". |

### AI, world and data

| Topic | Decision |
| --- | --- |
| Perception | 5 Hz with per-actor offsets; sight cone and range per record (archers 32 m); hearing of the player's attacks; being hit reveals the attacker; a hidden target is tracked only at its last known position. Distant actors perceive at 1 Hz (AI tier 1) or sleep (tier 2). |
| Path failure | No progress for 2 s triggers `on_path_failed`. Enemies never teleport. Without navmesh data, actors steer directly. |
| Navigation | The sandbox bakes its navmesh at load and re-bakes when the fence breaks. The Valley is baked offline and never re-bakes (decision 1). |
| Morale | Replaced in M2-M4 by decisions 26 and 17: ally deaths, commanders, awe, Thunder Roar, flee / regroup / rout. |
| Breakables | Replaced by decision 23: every persistent prop saves its damage stage and health. The blocking shape is disabled and detached at once, so a navmesh bake in the same frame never sees it. |
| World deltas | Saved with every checkpoint since M3 (decision 13), with flags, inventory and kills (`WorldState` v2). |
| Data validation | Unknown keys are errors; timings that are not whole ticks warn and are rounded; references are checked by type; the ids the code needs are required (`REQUIRED_RECORDS`, merged from the schema modules since M2); cross-record checks run in a post-pass. Any error replaces the game with the full list. |
| Settings file | Saved through `SaveIO` (temp file → verify → backup → replace). A corrupt file falls back to the backup with a message; a newer schema is kept as `settings.schemaN.rejected.json`. The Valley save uses the same path (decision 14). |

### Browser build

| Topic | Decision |
| --- | --- |
| Hosting | The play link is a claude.ai Artifact page: private by default, shared from the page's Share menu, with no extra branch, service or account. |
| Threads | The Web export is single-threaded, so it needs no cross-origin isolation headers, which the host cannot send. |
| File packing | The host serves `.js`, `.wasm`, text and images, but not `.pck` or archives, and caps text files at 16 MB. `index.wasm` (36 MB) and `index.pck` therefore ship gzipped and base64-encoded as `.txt` files; the launcher downloads them with progress, unpacks them with `DecompressionStream` and hands Godot ordinary responses. `tools/build_web.sh` writes the byte counts into the launcher. |
| Mouse | Browsers grant pointer lock only inside a click and keep the first Esc for themselves. On the web the game does not capture the mouse at start; a click on the game, or the title's button that starts a mode, captures it, and losing the lock opens the pause menu. |
| Release build | The play link is a release export: no debug panel or debug keys, Quit hidden. It always uses the `low` graphics preset and starts AI tier 1 at 30 m (`level.valley`'s `web_overrides`). |
| Saves | Settings and the one Valley save live in the browser's storage (IndexedDB), so Continue works after a reload. |
| Updates | When the page is republished, open viewers reload at a quiet moment; the launcher starts the game again, and Continue picks up the saved game. |
