# Implementation decisions and spec interpretations

The specification ([GIANTBORN_SPEC_V2.md](GIANTBORN_SPEC_V2.md)) asks that every interpretation
and conflict resolution be recorded. This file collects them for the whole build, milestones M0 to
M11 (M11's first part, `0.11.0-m11`, and its second, `0.12.0-m12`):

1. [The plans' decisions](#1-the-plans-decisions): the 30 interpretations the M2-M5 plan fixed
   before any code was written (`docs/plans/M2_M5_PLAN.md` §0.3, numbered 1-30 here) and the 34 of
   the M6-M9 plan (`docs/plans/M6_M9_PLAN.md` §0.3, numbered 31-64 here), each with what was built;
   then §1.3: the one deviation from the spec itself (the lossless music and ambience masters that
   are not committed), the licence left to the owner, and the spec's scope as the owner later
   directed it and as the plan read it; §1.4: the 21 decisions of the M10 plan
   (`docs/plans/M10_PLAN.md` §0.4, numbered 65-85 here), and §1.5: the owner's answers to that plan's
   questions; §1.6: the 21 decisions of the M11 plan (`docs/plans/M11_PLAN.md` §0.4, numbered 86-106
   here; Part A, the giant refined, used thirteen of them, and the other eight are recorded when the
   part that uses them ships), §1.7: the owner's answers to the M11 plan's questions and their
   decisions at checkpoints A and B, and §1.8: what Part B (more customization) built of the plan's
   decisions.
2. [Deviations recorded by the packages](#2-deviations-recorded-by-the-packages): where the packages
   (P01-P18 for M2-M5, P19-P40 for M6-M9, P41-P46 for M10, P48-P51 for M11's Part A, P53-P57 and the W33
   lanes for its Part B) departed from their
   plan, and why. Each package's own
   record, with every detail and the test that covers it, is `docs/systems/<package>.md`.
3. [Fixes from the milestone gate reviews](#3-fixes-from-the-milestone-gate-reviews).
4. [The plans' review logs](#4-the-plans-review-logs), in short.
5. [The M0/M1 decisions](#5-the-m0m1-decisions): the combat sandbox's rules, still in force unless
   a row says what replaced them (M10 changed two: the visible swing and first person's render
   layers).

Everything below is a proposed default: data, or a small code path, that can be changed. A number
quoted from a measurement names its source. Measurements of the M6-M9 code are the W23 confirmation's
(`wave-23` with commit `a7da72d`; `docs/BALANCE_LOG.md`, "M9 confirmation") unless named otherwise:
the M9 gate's fixes followed that confirmation, and what they changed is in §3.2; the M9 gate's final
measurements and the ship's final check are in `docs/M6_M9_HANDOFF.md` §5.4, §6 and §7. Measurements
of the M10 code are the M10 gate's on its merged code (`m10-gate`, commit `348a7bf`) unless named
otherwise; `docs/M10_HANDOFF.md` §5 and §6 hold them. Measurements of M11's Part A are the Gate A merge's
(`m11-gate-a`, commit `9f96bb7`) and its second fix round's (`m11-gate-a2`, commit `d0db605`) unless named
otherwise; `docs/M11_HANDOFF.md` §5 and §6 hold them. Measurements of M11's Part B are the system documents'
(P53-P57, the W33 lanes, Gate B) and the release's (`docs/M12_HANDOFF.md` §5 and §6).

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
| 34 | 4 | **Every sound is original and generated by committed code, and the generators are the masters.** `tools/audio/` (Python 3 and numpy, seeded, float64, single-threaded) writes every sound; effect WAV masters are committed; music and ambience are rendered to lossless masters and only the bit-exact Ogg is committed, beside a manifest of every hash and the tool versions; `build_audio.py --verify` regenerates every master and Ogg and compares them (part of `check.sh --audio`); `--masters-out` writes the music and ambience masters as FLAC; `PROVENANCE.md` states originality and leaves the licence to the owner. **A recorded deviation from spec §13** (§1.3). | As planned (P19, P21, P23, P28): 441 files, every check with `--audio` since P28 regenerating all of them bit-exact on the recorded toolchain (Python 3.13.18, numpy 2.5.3, ffmpeg 6.1.1, libvorbis 1.3.7; `assets/audio/manifest.json`), W23's last in P39f's web part's final check (`docs/systems/P39f.md`, "Part web"); the release's final check (`tools/check.sh --build --slow --gate --audio` on the merged head `43d92b8`, the final game code; handoff §6.1): all 441 files regenerated bit-exact. `assets/audio/PROVENANCE.md`: "Licence: the project's licence; the owner chooses it." |
| 35 | 5 | **The score is layered stems** on plain stream players started in one frame; layer volumes eased live; set changes cross-faded at bar boundaries; three melody variants per exploration set picked per four-bar segment (no variant more than two segments in a row, no phrase repeated within 60 s), rests of one to three loops, a silence window after three minutes of calm; danger and combat stems shared per tempo, the region's melody kept under combat at −10 dB, a combat-intro stinger per region; boss sets in their own tempo and mode with a one-bar intro; stingers duck the stems. | As planned (P19's MusicDirector and MelodyScheduler; P23's Valley score; P28's world score: five regions, three bosses). P23: a district change keeps the frame's position (no clash of chords while the sets cross-fade); melodies rendered segment by segment so a variant's tail never crosses into a rest; loudness (LUFS) balances the score rather than peaks. |
| 36 | 6 | **The listener stands at the giant's chest**, turned with the camera; other sources' distances scale with the giant's height ÷ 3.66; distance muffling uses baked "far" variants. **The music weighs threats against the giant**: `combat` only for an enemy of at least 0.3 x the giant's height or a formation member, engine crew, boss or rival giant; lesser enemies raise at most `danger` within 40 m; fleeing and routed enemies never count; the danger radius at most 150 m. | As planned (P19, P28). Measured: the music was in `combat` for 43 % of the stage 4-6 time spent among only lesser enemies in the W23 confirmation (plan §6.4's target: under 25 %; `docs/HOW_IT_PLAYS.md`, "The music's intensity"); the rule is as planned and unchanged since P19 (the mix data's `intensity` block is plan §4.4's): only an enemy that counts raises `combat`, and a lesser enemy's blow raises only `danger` (`AudioMath.intensity_target`, `MusicDirector.note_player_hit`). So the cause `docs/plans/FOLLOWUPS.md` records ("From the M9 confirmation": P28's rules "count any engaged enemy") is not what the code does. The music and the measure differ in reach. The music counts an engaged enemy that counts out to 35 m x the giant's height / 3.66 (105 m at stage 4, 140 m at stage 5, 181 m at stage 6, though it looks no farther than 150 m). The measure looks only at the enemies engaged within 40 m (`RunMetrics.HOSTILE_NEAR_M`) and judges them by the music's own rule (`WorldMetrics.counts_for_music`, so formation members and crews count). A formation or crew engaged beyond 40 m therefore holds the music in `combat` during time the measure counts as among only lesser enemies; a counting enemy's blow (5 s) and the combat hold (6 s) add to it. **The M9 gate changed the rule** (lane balance, `4be451d`, data): from a 10 m giant (stage 4) the combat radius is capped at 40 m (`audio_mix.intensity.combat_cap_m` 40, `combat_cap_min_height_m` 10), the measure's own engaged radius, so a formation or crew engaged beyond 40 m raises only `danger`; its traced cause was formations and siege crews 40-120 m off holding the music in `combat` (`docs/BALANCE_LOG.md`, "M9 gate (lane "balance": ...)", "The music among lesser enemies"). The cap is a part of the drop, the runs' changed play the rest (a replay with the cap taken out: `w.mixed:novice:1` 100 % -> 68 %). At the gate's final round a landed shot from a hostile crewed engine counts as its crew's hit and raises `combat` for 5 s (`3729d2e`). Measured on the code the gate shipped (`7502770`, `final_after_world_a`, seed 1): **9 %** of the stage 4-6 time among only lesser enemies in `combat` - met (`docs/BALANCE_LOG.md`, "M9 gate: the final measurement"; `docs/HOW_IT_PLAYS.md`, "The music's intensity") |
| 37 | 7 | **Threats are audible and directional.** A positional windup cue at the attacker for every telegraphed attack aimed at the giant; a broadband "threat sting" there when the attacker is off camera or beyond 20 m (scaled), unless the expected damage is under 3 % of the giant's health or the poise ratio sits at the 0.25 floor; one wall cue per formation brace; an engine's launch at the engine and a rising whistle at the landing circle; a cue when a ranged enemy commits its aim. | As planned (P19's router, P21's threat family - kept apart from the hits by a spectral test - P28's world rules). M6 gate: the sting and the aim lock moved to the mix's `alert` class, so a far sting is not lost under the combat layer (`test_threat_audibility`). P28: the whistle starts at the launch, not the telegraph. Open: the sting of a siege engine or a cavalry charge against a big giant is muted, because the router weighs the attacker's own height rather than the action's size override (`docs/plans/FOLLOWUPS.md`, "From P32"). |
| 38 | 8 | **Size and memory budgets**: M6 audio ≤ 4.0 MB imported, all audio ≤ 9.5 MB; world data ≤ 5.0 MB; the web `index.pck` shipped gzipped and base64-encoded in parts of at most 15 MB that the launcher joins, ≤ 7.5 MB after M6, ≤ 21 MB after M7, ≤ 23 MB at the end; test content never in the web release; registered web samples under 110 s (the Valley) and 170 s (the world). | Met at every release through `0.8.0-m8` and on the W23 code: M6 audio 3.93 MB (P23); all audio 9.229 MB of 9.5, the Valley's registered samples 108.57 s of 110 and the world's 167.81 s of 170 (P39f's web part's final check, W23); world data 2,390,369 bytes at P25 and 2,984,279 at W23 (`docs/M6_M9_HANDOFF.md` §2); the shipped pck 6.52 MB at the M6 gate's release (commit `aaf3844`), 15.92 MB in two parts at `0.7.0-m7`, 16.53 MB in two parts at `0.8.0-m8` and 16.67 MB in two parts in the W23 confirmation's release build (`docs/PERFORMANCE.md`). At `0.9.0-m9`, every one met: the shipped `index.pck` 17,500,048 bytes = 16.69 MB of 23, in 2 parts of 8,750,024 bytes (the largest far under 15 MB), no test content (`tools/build_web.sh` on `dfdfdfc`, the final game code; handoff §7); the final check's audio budget line, all audio 9.229 MB imported of 9.5, the Valley's registered samples 108.57 s of 110 and the world's 167.81 s of 170 (handoff §6.1); the world data 2,984,279 bytes on the final commit, unchanged since W23 and under 5.0 MB (handoff §2). `tools/build_web.sh` fails over the milestone's budget since the M7 polish (P22). P23 measured Godot 4.6.3's Ogg import factor at 1.11, not the plan's 1.03. |
| 39 | 9 | **Enemy rigs get cheaper, not fewer**: one vertex-coloured mesh per animated part with one material per actor; the renderer's visibility ranges swap distant rigs for the one-box proxy by archetype (bosses exempt). Target: about 7 draw calls per near rig, 1 per far one. | P22 as planned (the stress arena's twelve combatants 221 -> 77 draw calls). The M6 gate measured a miss (the Valley walk at `low` up to 268 draw calls against 250); P30's merged rest-pose mesh at mid distance and P27's batched HUD (about 10 draw calls instead of about 120) brought the walk to max 154 (`docs/PERFORMANCE.md`, "Draw calls after P27"). |
| 40 | 10 | **The Valley stays the prologue, almost unchanged**: the crown opens the Kings' Door; the end screen becomes "Prologue complete" with Continue; the Citadel gets an interior breachable at stage 4 and a second exit; Thornwick's guard posts move; checkpoints get display names and a `max_stage`; a sealed vault opens to a stage-5 heave; a finished save may skip the prologue. | As planned (P20, P22, P26). Every Valley checkpoint measured `max_stage` 6 (P26's corridor test). A second new waystone, `valley.cp.citadel_stair`, receives the giant from the world's Broken Stair. |
| 41 | 11 | **Two campaign levels and reload transitions**: `level.valley` and `level.world`; `GameSession.Mode.VALLEY` means the campaign; travel and fast travel are a checkpoint at the destination plus a reload; the save's `level` picks the level; level-wide nodes of later packages are made at run time from `LevelRoot.RUNTIME_NODES`. | As planned (P20). M7 gate: fast travel is refused for a stone its respawn blockers refuse, and a load that moves the respawn says why. M8 release: no checkpoint is committed while a boss fight or battle is engaged. |
| 42 | 12 | **A 2,048 x 2,048 m world in 8 x 8 chunks of 256 m**, bounded by a rim; chunks load within Chebyshev distance 1 and unload at 3 or more (at most 25 loaded), nearest first, with a 4 ms per-frame budget (a fixed quota headless); 16-bit heights at 4 m; no plugins, no floating origin; chunk-border slopes at most 35°. **The world can be seen to its edge**: an always-loaded skyline, fog from 400 to 1,800 m, a 2,400 m far plane, beacon columns. | As planned (P24a, P25). P25 needed a slope-limiting projection before P24a's border relaxation. M8 gate (F26): a preload list loads the chunks' scripts and shared scenes behind the loading screen. Measured: the loaded margin at least 250 m with no thrash on the stage-6 tour and in every bot run; the worst streaming work frame headless is a large props part's text parse: 12.19 ms on the tour and 17.9-33.9 ms in the W23 matrix's bot runs (three at a time on four shared CPUs), against plan §6.4's 12 ms, a miss (`docs/PERFORMANCE.md`, "The M9 confirmation"); exports ship binary scenes, whose parse takes about a tenth of the time (P39f). |
| 43 | 13 | **Navigation in the world is baked offline** on three layers with one map each (human 1, large 2, titan 16), size-gated ground as titan gate regions (32 / 64 / 128); lean bakes, the grown box, the aligned y grid; every query through `NavQuery` (unlimited polygons, 120 m chase and 300 m far caps, goals snapped, a per-tick budget, throttled re-paths); the Valley's paths unchanged; async iterations off when streaming is deterministic, readiness by iteration id; a road graph for long routes; nothing bakes at run time. | As planned (P24b, P25): `test_world_determinism` (gate) requires two world walks with AI to give byte-identical results. M7 gate: the actors' firing, flee and rout searches keep the budget and resume where they stopped; M7 polish: civilians' safe points too, and every layer map keys its edges at its own cell (16 edge errors on the human map gone). A gate region takes every titan polygon that touches gated ground; size gates are drawn in 6 m for the split (P25). |
| 44 | 14 | **A world index per level**: positions and display names of checkpoints, markers, areas, POIs, exits, encounters, safe markers and quest props, the region grid and the road graph; everything falls back to it when a node is not loaded. | As planned (P20 for the Valley, P25 for the world). M8 gate (F18): road edges carry their kind, so wanderers stand on open roads. |
| 45 | 15 | **The director in a streamed world** updates only encounters whose chunk is loaded and ready, despawns living members before their chunk unloads (they come back home at full health), filters spawns by stage, scales formations for the web, requires a leash on every world encounter but arena bosses, which get a disengage rule. | As planned (P24b, P30, P34). Through W23 the director keeps its older rule (P17b): a faction's armed members already in the world count toward the budget of 12 when it turns hostile, and new spawns wait; the W23 confirmation saw 13-17 counted for at most 0.35 s and 16 for 43.6 s when a faction turned (`docs/PERFORMANCE.md`, "The M9 confirmation"; FOLLOWUPS). **P40 keeps the rule** (no code change in `0.9.0-m9`). On the final code the count passed 12 in 4 of the 19 world runs read with `tools/bot_report.py`'s `world_streaming` (the M9 gate's 17 `final_after_*` runs and the release's two quiet-machine runs): 16 for 43.9 s (`w_mixed_expert_1`), 16 for 0.3 s and 0.2 s (`w_conqueror_expert_1`, `w_conqueror_novice_1_assist`) and 13 for 0.05 s (the 60-minute run); no counted member spawned at the cap. The reason is the numbers: the excess is bounded by the turning faction's members already in the world, and the cost it was suspected of is not its own - the war camp's sabotage alone on a quiet machine reads 9.98 ms p95 in the Aldmere March with never more than 12 counted (`w24perf_mixed`), so holding the newly hostile members back would not bring the region under 8 ms, while it would leave armed hostile members idle in sight of the giant, a new behaviour to tune (`docs/systems/P40.md`, "Decisions and deviations"; FOLLOWUPS' row, closed by P40, which M10 may reopen if the reference PC finds a cost) |
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
| 56 | 26 | **The main thread is non-linear, and every oath can come first**: the three oaths start together at stage 4 and any two complete the stage; each has a peaceful and a violent resolution open as the first oath at stage 4; a choice that still needs something shows greyed with its reason; the finale needs stage 6. | As planned (P29's `OathRules` proves a first-oath resolution for every oath; P35, P36). The gate suite `test_main_thread_combinations` runs every order of every pair (M8 gate F3: through every resolution's own writer). In the W23 confirmation the bot completed the march-first and wood-first orders but not the crown-first (the Iron Regiment at stage 4; `docs/HOW_IT_PLAYS.md`). On the final code (`7502770`, the M9 gate's final measurement): assisted, all three first-oath orders completed with no death (`final_after_orders`, P38's acceptance), the crown first winning the Iron Regiment at its first attempt; unassisted (`final_after_extra_orders`, the novice on seed 1), the march first and the wood first completed and the crown first did not - it now gets through Fort Aldmere's gateway and loses the battle at stage 4: six deaths, five of them in the battle (handoff §5.4) |
| 57 | 27 | **Wandering encounters and world events** come from region tables filtered by stage and faction standings, spawn out of sight on loaded ground, persist their outcomes and cannot be farmed (a template's kill XP falls to zero after its third spawn); events start only when their centre chunk is loaded and the giant is within 200 m, suspend while unloaded and reset on death; moving columns are a path parameter while unloaded. | As planned (P37's framework and the Crownmarch, P35's and P36's tables and events). Not shipped: the siege trains of the wander tables (an engine is a placed prop keyed by its world id; FOLLOWUPS). An event left unloaded for 600 s is abandoned with no outcome (not in the plan). |
| 58 | 28 | **The world bot extends the Valley bot** (road-graph routing, tracked objectives, exploration, oath policies in any order); balance is judged on the novice, stability on the assisted bot. | As planned (P38). P39 added measurement fixes and rules of play the bot never had (siege disruption, the ability rotation, the expert's answers, the expert's brazier lure), which shape the ability and boss numbers it reports (`docs/systems/P38.md`, "P39 (W23)"). |
| 59 | 29 | **Stages 7-10 come later by data**: profiles to stage 10 already validate; layers, gate bits, region records, chunk grid, skyline and world record are data; the builder accepts a larger grid. | Not built, as planned (§0.4). |
| 60 | 30 | **Every milestone has a gate review, and the ship its own.** | M6 (W14), M7 (W18, then the M7 polish), M8 (W21: a review, an audit with two fix-up rounds, a screenshot pass and the release check of `0.8.0-m8`), the W23 confirmation and the M9 gate, and the Ship gate (W24): §3.2. |
| 61 | 31 | **Peoples by site, and manners toward a giant**: factions are records with texts, thresholds and per-site dispositions; the toll-riders hostile from the start, Aldmere at peace until offended; friendly civilians give way; talkers meet a big giant on their green; damaging houses is an offence; a hostile settlement can be reconciled; outcomes show on site; quest-critical props are indestructible. | As planned (P22's factions by record, P29's Crownmarch, P36's Aldmere, Skarn and Harrok's clan; P25's GameData check that every quest-critical prop is indestructible). |
| 62 | 32 | **An equipment budget sits beside the XP budget**: reinforcing affordable by the beacon, one titanforging (and a titan forge) by the first oath, two by stage 6; titan iron on the mandatory path from the beacon's cache, every oath and the Standing Stones; optional sources extra; nothing missable. | As planned (P29's `test_world_equipment_budget`, extended by P35 and P36); it passes in the W23 confirmation. |
| 63 | 33 | **Exploration pays**: every POI gives discovery XP; vistas reveal the POIs within 400 m on the map; fourteen Old Kings' cairns (thirteen in the world, one in the Valley's vault) give an attribute point each, nine of them behind size gates; sealed places are logged in the journal with the stage they need; caches give iron. | As planned (P25, P26, P27, P35, P36), with two exceptions. The Kingsgate, Greywood and Aldmere shrines' POIs give no discovery XP (plan §5.4's "30 / 0": the shrine is the reward; P25). The Standing Stones' shrine POI gives 40, and the Sunken Steps' shrine stands inside that ruin's POI (30). Twelve cairns stand, not fourteen: eleven in the world and the Valley vault's (P26). The two missing ones are sealed Crownmarch places (stage 5): the Toppled King (`poi.kingsgate_statue`) and the Barrow Vault (`poi.barrow_vault`) hold only their 2-iron caches (`tools/data/world/crownmarch.json`). P25 left the sealed cairns to P35 and P36 (`docs/systems/P25.md`), whose regions held four of them, and `test_world_data` accepts 7 to 13 world cairns. The bots seek no sealed place or cairn. |
| 64 | 34 | **Three test tiers**: the default suite (≤ 75 s, audio off, per-package caps), the slow tier (`tests/slow/`, ≤ 8 minutes) and the gate tier (`tests/gate/`, ≤ 50 minutes); every wave merge records the default and slow times. | As planned (P19 added the gate tier and the `TIMES` line). The W23 confirmation's full check: 282 suites, 49,265 checks, 0 failures; default 71.0 s, slow 313.3 s, gate 660.1 s (`docs/systems/P39.md`, "Tests and the full check"). The release's final check (`tools/check.sh --build --slow --gate --audio` on the merged head `43d92b8`, the final game code; handoff §6.1): 291 suites, 50,114 checks, 0 failures; default 73.4 s of 75, slow 314.9 s of 8 minutes, gate 687.0 s of 50 minutes; the default tier alone 73.0 s. |

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

### 1.4 The M10 decisions (M10 plan §0.4)

The M10 plan's decisions 1-21 are numbered 65-85 here ("Plan" gives the plan's own number, which the
system documents `P41.md` to `P46.md` use). The plan holds each decision's full text. Decisions 67 and
72 change two M0/M1 contracts; each is also recorded beside the row it changes, in §5 ("Hit
detection", "Camera and targeting").

| # | Plan | Decision | What was built (and where it moved) |
| --- | --- | --- | --- |
| 65 | 1 | **The player's giant only.** M10 replaces the stylized rig of the player; soldiers, villagers, named NPCs, the rival and clan giants, Harrok, the creatures and the world keep their low-poly look, and so do the player's weapons. | As planned (P43: `scenes/player/giant.tscn` lost its stylized meshes; no other actor's scene changed). The owner confirmed the low-poly weapons (§1.5, answer 4). |
| 66 | 2 | **The pose brain stays; a skinned body follows it.** `ActorRig` keeps computing every pose; `SkinnedRig extends ActorRig` adds an `AnimationTree` of computed-keyframe clips and one `PoseBrainModifier`; where the brain does not walk the legs never step. | As planned (P43). The legs' source is chosen in a fixed order: dead, airborne, an action's own motion (the run clip on a clock of its own), walking (the clips' time from the brain's walk phase), else the stance. Added by the package: a wrist limit of 45°, one grip axis of 41° for every weapon family, a protracted clavicle and a straight arm during a hold (§2.3). Not built: the stomp's leg lift (the plan's cut list). |
| 67 | 3 | **Tip matching replaces the 1° rule**: the hand holds a grip the real arm can reach and the visible weapon aims at the tested segment's tip; its outer half stays inside the tested capsule, at most 15° off the tested direction (7° median). The gameplay geometry is not changed. | `TipMatching` (P42), driven by `PoseBrainModifier` (P43). On the exported landmarks, 1,004 samples over every player weapon arc at stages 1, 3, 4 and 6: median 7.10°, worst 12.94° (`test_tip_matching`); the M10 gate's own every-tick check over stages 1-6: 2,626 samples, median 7.06°, worst 13.03°, the outer half at most 0.80 radii from the capsule's axis, none breaking the contract. **The contract holds for weapons that fit their stage**: an unreforged club, sword or hammer carried past its fit stage points at the tested tip and falls short of it (the gate measured up to 3.88 radii, the stage-6 sword); the HUD already tells the player that weapon is too small (§2.3, P42 and P43). The W25 merge moved the grip's reach limit from 0.97 to 0.95 of the palm's reach for the exported skeleton's longer hand. |
| 68 | 4 | **The gameplay body is unchanged**: the capsule, hurtboxes, lock anchor, attack origin, grab sockets, launch points and camera geometry stay the stylized giant's; a held body's *visual* is moved by the remaining gap to the visible palm (at most 0.33·k m). | As planned. The M10 gate compared the player's scene with `0.9.0-m9`'s: its 23 gameplay nodes are identical, no existing data record and no simulation script changed. During a hold the visible palm comes within 0.23·k of the socket and the held body's visual closes the rest; its collision never moves. |
| 69 | 5 | **Presentation only, write-only**: the skinned layers write only under `Visual/Body` (and the held body's `Visual` offset); no simulation, AI, combat, world or quest code reads the skeleton, the clips, the model or the look. | As planned: `test_skin_rules` and `test_appearance_rules` (the code rules), gate `test_giant_determinism` (three seeded soaks and a seeded Valley run byte-identical with the skin off, on, and with another look, with positive controls). The M10 gate found the 120 s soak's result byte-identical on `0.9.0-m9` and on the candidate, and the world bot's smoke run identical once wall-time, node-count and memory fields are removed. |
| 70 | 6 | **The skinned layers run where something is drawn**: with a display they run; headless they stay off unless a test enables them or the command line says `--skin`; `--skin-stats` proves what ran. | As planned (`SkinnedRig.layers_enabled()`, `--skin`, `--no-skin`, `enable_for_tests()`, the `SKIN_STATS` line). The model is instanced headless, so node paths exist; the weapon then hangs at the brain's hand. |
| 71 | 7 | **Growth is a uniform scale** of the stage-1 model by height / 3.6576; no per-stage proportions; growth stays instant. | As planned. |
| 72 | 8 | **First person by render layers, with closed cuts**: the head on layer 3 with hair, beard and eyes, the torso on layer 2 with the garments' core parts, the limbs on layer 1; every cut loop capped; first person culls layers 2 and 3; pressed close culls layer 3, and layer 2 only if a render shows the torso over the crosshair; the tree's canopy and the pine's needles move to layer 3. The camera's geometry does not change. | As planned (P41: five cut loops, each capped on both sides; P43: the camera's masks). The render of the growth course's low passage showed the torso below the crosshair, so pressed close culls the head's layer only (`CameraRig.PRESSED_CULLS_TORSO` false). The gate added a shader fade of the limbs round the shoulders in first person, because the capped shoulder cuts showed as slabs when looking down (§3.3, LC-3); P46 lifted the braies' cap over the thigh cuts. |
| 73 | 9 | **Assets are generated, audited and verified**: `tools/giant/` regenerates every giant asset from a vendored, audited CC0 subset of the MakeHuman/MPFB2 data; `--verify` compares with the manifest, bit-exact on the reference toolchain; no GPL or Apache code is copied. After W25 the body mesh, the skeleton, the region ids and the landmarks are frozen. | As planned (P41; the clips P43; the target content P46), with one recorded deviation: the tangent-normal bake jitters by a texel from run to run, so "bit-exact" tolerates at most 64 texels of a Cycles map off by 1/255 (§2.3, P41). 133 vendored files, 13 generated files. The gate's provenance lens regenerated all 13 bit-exact with every bake pass, found no line of the kit shared with the wheel's code, and the audit clean. The body stayed frozen through the gate (its hash is the W25 one). |
| 74 | 10 | **No shape keys in M10**: no face or build sliders; one face and one build; height is the growth stage. | As planned. |
| 75 | 11 | **One design array**: tattoos, war paint, ancestry marks and scars are layers of one VRAM-compressed texture array; the body's per-vertex region id picks each region's design; within a layer a region's area carries at most one design in R, G or B plus one in A. | As planned: 29 designs in six 512 px layers (16 tattoos, 4 war paints, 6 scars, 3 marks). The scars are designs too, on two layers of their own, where the research had baked them into the skin (§2.3, P41 and P46). The values are quantized to the compressor's levels, which keeps every design within the slow suite's error bound with no ghost. |
| 76 | 12 | **Hair is cards** with depth-pre-pass blending and tinted skin under them; no alpha to coverage. **Skin** uses wrap lighting with a back-light transmission term; no subsurface scattering. | As planned. The cards took two more passes to read as hair: P46's second pass (feathered sides, strand tips, narrower and more cards, softened card shadows, rounded normals) and the gate's (a hairline fringe, feathered roots, the long beards as pointed locks, a beard that fades seen from behind; §3.3, LC-6). The gate also eased the wrap's red and tied the bake tone to the default tone (§3.3, OR-1). |
| 77 | 13 | **Palettes, not free colour pickers**: every colour is a named swatch from data, saved as an id. | As planned: skin, eyes, hair colour, ink, paint colour and dye are `appearance_set` records of named swatches. |
| 78 | 14 | **The look lives in the character, schema 2 kept**: `character.appearance` is optional with its own `"v"`; absent means the default look; sanitize repairs and reports, and its notes reach the load message; a record from a later build is kept untouched; the creator writes the full record. | As planned (P42). The gate found the creator editing a later build's record in place and fixed it: the creator starts from the default look and only a kept change replaces such a record (§3.4, LB-1). A `0.9.0-m9` build keeps a `0.10` save's look through Continue, checkpoints and a death (the gate's cross-version run). |
| 79 | 15 | **One creator, three doors**: `CreatorScreen` opens at New Game, at the launcher's "Start in the open world" (`--creator`) and from the shrine's Appearance tab (Keep applies and re-takes the shrine's checkpoint; Cancel restores). Leaving with changes asks first; Undo covers every change; changes are free at any shrine and stage. Two one-time messages tell players of older saves and new ancestry marks where the tab is. | As planned (P44; the launcher's argument P45). |
| 80 | 16 | **Ancestry marks are automatic and removable**: `mark: "auto"` shows the chosen ancestry's mark, "none" hides it; marks, two ancestry-only eye colours and one skin tone are locked until the ancestry is chosen. | As planned; the owner kept the default (§1.5, answer 2). |
| 81 | 17 | **Two texture tiers**: the desktop draws the 1024 px normal and ORM maps; the Web preset excludes them and keeps the 23 MB budget - unless the owner raises it. | The owner raised it (§1.5, answer 1). W25 and W26 shipped as the decision's first half says; since P45 (W27) the Web presets keep `tex_hi/`, the tier "auto" picks the 1024 px maps on the Web too, the budget for a `-m10` version is 26 MB and the giant's share is capped at 7.6. `--giant-tier=web` still forces the 512 px maps. |
| 82 | 18 | **Options must read in play**: every design category offers bold pieces that show from behind at stage 1 or in first person; the rendered option check measures those views; the creator has a "Game view" and says when clothing hides a design. | As planned (P44's check, P46's content). At W26 the scars did not reach the views' floors and were a listed known miss; P46's back lashes read from behind (63 pixels of the tile against a floor of 18) and the list is empty. The check draws 176 tiles. |
| 83 | 19 | **The owner sees it early and approves it before the release**: a note before W25; a private playable link, a video and character sheet A after W26; sheet B and the release candidate after the gate. The release waits for the approval; no other work waits. | The note and the questions went out before W25 and were answered on 12 November 2026 (§1.5). The preview link, the video and sheet A followed the W26 merge. No notes on them had arrived when P46 finished, during the W27 merge or at the gate, so none was applied. Sheet B was rendered from the gate's code and the release candidate built from it; **the owner approved them on 18 November 2026, with no notes**, and the release followed (`docs/M10_HANDOFF.md` §7). |
| 84 | 20 | **Test tiers as in M6-M9, with M10's caps**: each package's cost is counted from the runner's per-suite times; merges run with `--require` (no check may skip) and `--strict-times`. | As planned (`tools/check.sh --require`, `--strict-times`, P41; `tools/giant_suites.py` for the suites that load the giant). Every wave merge and the gate merge record the tiers: the gate's merged code ran 330 suites in 65.4 s (default), 348.2 s (slow) and 815.5 s (gate), under 75 s, 8 minutes and 50 minutes. P42 moved six long default tests to the slow tier for headroom. |
| 85 | 21 | **The gate has an independent review** with fix lanes and an audit, plus the owner's look approval. | Four reviewers over the plan's eight lenses, every finding verified adversarially: 21 findings, 19 confirmed and 2 refuted, and one note of the orchestrator's (the skin's tone). Three fix lanes (ui, web, look), one at a time on the generated assets; the audit of the fixes came back dry on its first round. §3.3, §3.4; `docs/M10_HANDOFF.md` §5. |

### 1.5 The owner's answers to the M10 plan's questions (M10 plan §0.6)

Sent with the note before W25 and answered on 12 November 2026. They replace the plan's defaults where
they differ, and every package read them as decisions.

| # | Question | The plan's default | The owner's answer | What it changed |
| --- | --- | --- | --- | --- |
| 1 | Raise the Web pack budget from 23 to 26 MiB (still two parts)? | Keep 23: the Web draws 512 px textures | **Raise it to 26 MiB**, still in parts of at most 15 MiB; the Web keeps the 1024 px normal and ORM maps like the desktop builds | Applied by P45 in W27 (the orchestrator's reading: W25 and W26 keep 23 MiB and the exclusion, so that P41's export measures the floor's share): `tex_hi/` off the Web presets' exclusions, the `-m10` budget 26, `GIANT_SHARE`'s cap 7.6. The two maps add 1.73 MiB shipped. The gate's release candidate ships 22.49 MiB |
| 2 | Ancestry marks automatic on the choice (removable at shrines), or only offered? | Automatic, removable | **Automatic**, hidden at shrines if the player wishes (the default stands) | Nothing: `mark: "auto"` is the default record's |
| 3 | A "World style" switch that lights the giant flatter, closer to the world's look? | Not built in M10 | **No** (the default stands) | Nothing built; no Settings row |
| 4 | Keep the low-poly weapons in M10? | Yes | **Yes** (the default stands) | No material pass on the weapons |
| 5 | Approve the look: notes on the preview link and sheet A after W26; on sheet B before the release approve, approve with notes, or not yet | - | No notes on the preview had arrived by the gate. **Sheet B: "Approve"** (18 November 2026), with no notes | Nothing to apply. The tag `0.10.0-m10`, the play link and the merge to `main` waited for it and followed it (`docs/M10_HANDOFF.md` §7) |

One more decision was the owner's and open at the M10 release: M11's direction. Their request of 18
November 2026 set it (the giant refined, more customization, realistic NPCs; M11 plan §0.2, and §1.6
below).

### 1.6 The M11 decisions (M11 plan §0.4)

The M11 plan's decisions 1-21 are numbered 86-106 here ("Plan" gives the plan's own number, which the
system documents `P48.md` to `P51.md` use). The plan holds each decision's full text. Part A (the giant
refined, `0.11.0-m11`) used decisions 86-94 and 103-106; decisions 95-102 are Part B's and Part C's (the
clothing slots, the record's `v` 2, the people and the beasts) and are recorded with what was built when
those parts ship (P58, P66).

| # | Plan | Decision | What was built in Part A (and where it moved) |
| --- | --- | --- | --- |
| 86 | 1 | **Three parts in the owner's order, each a release**: the giant refined (`0.11.0-m11`), more customization (`0.12.0-m12`), realistic NPCs (`0.13.0-m13`). | As planned; the owner confirmed three releases (§1.7). Part A passed its gate (Gate A and its second fix round, Gate A2) and the owner approved it at checkpoint A; this release is the first of the three. |
| 87 | 2 | **The pack budget grows in steps to 44 MiB** (26, 32, 44) inside the owner's "about 60 MB" for the page. | `tools/build_web.sh` applies 26 MiB and the giant's 7.6 MiB share to `-m10` and `-m11`, 32 and 13.6 to `-m12`, 44, 13.6 and the people's 12.0 from `-m13` (P49). The `0.11.0-m11` release ships 23.44 MiB of 26 (6.41 MiB of the giant's 7.6); the page is about 37.5 MB. |
| 88 | 3 | **Gameplay geometry stays the stylized bodies'**; the realistic bodies are presentation. | As planned: no capsule, hurtbox, anchor, socket, reach band or data record changed in Part A. The reach past a weapon's fit stage (P50) moves only the drawn shoulder, spine and pelvis. |
| 89 | 4 | **The pose brain stays the driver of every actor**; skinned bodies follow it; no gameplay script reads a skeleton, a clip, a model or a look. | As planned. The seeded soak's `AUTOPILOT_RESULT` is the same in all 28 keys from the W29 merge to this release, and `test_giant_determinism` (gate) passes with the skin off and on (57 checks). |
| 90 | 5 | **Clips stay computed keyframes**; no outside motion data. | As planned: 19 more clips from `tools/giant/kit/clips.py` (28 in all; P48), keyed only on the bones they move; two were changed at Gate A2 (the side flinches' lean, `fp_rest`'s forearm). |
| 91 | 6 | **The body is unfrozen once, in W29, and frozen again**: leaf bones for hair, beard, braids and the cape; build weights in the vertex colour; grip and side landmarks; the styles and garments as separate parts; the body's positions, UVs, region ids and bone weights bit-identical to M10's. | As planned (P48): 18 leaf bones (71 in all), `COLOR.g` and `.b` the brawn and girth weights, `grip_*`, `knuckle_*` and `toe_*` landmarks, designs with a side, 21 parts in `assets/giant/parts/`. `tools/giant/freeze.py` and `fixtures/m10_freeze.json` prove the body, the 53 body bones and M10's clips unchanged at every regeneration. Four more CC0 targets were vendored (137 files) so the two build directions exist. |
| 92 | 7 | **Shape changes: the build by shader, the face by shape keys only if the probe passes**; height is never a choice. | Part A built only the channels: the build weights are in the vertex colour and probe 2 showed the vertex push and its shadow working; the sliders themselves are Part B's (P53, P56). Probe 3 found the dark patch's cause (morph normals without morph tangents) and passed, so the face keys are P56's to build. No player-facing slider ships in `0.11.0-m11`. |
| 93 | 8 | **Hair stays polygons and becomes more than flat cards**: volume normals, a two-lobe strand highlight, shells for the crop, stubble and the short beard, braids as twisted tubes with beads, loose strands at the hairline, hair bones for sway. | As planned (P51): shells at 12 layers on the desktop and 6 on the Web, stacked at load time (no shipped bytes for the layers, never a shadow); braids as seven-sided tubes with two bead rings; loose strands on the four long styles; a row of cards under the jaw so a beard exists from behind. Gate A2 gave the shells the cards' light and grey (§3.5). A black shell beard face-on with the sun behind him is still dark (`docs/M11_HANDOFF.md` §9). |
| 94 | 9 | **Skin gets a pre-integrated subsurface term**: a 64 px lookup in `light()`, curvature in the mask map's spare capacity. | Built with one deviation (§2.4): the curvature is a 256 px map of its own (`tex/curvature.png`), because in the mask map's alpha the VRAM compression spoiled the masks. Gate A made the lookup a per-channel wrap (`SKIN_WRAP`) and eased the albedo's grade, so the skin is warm in the world's sun (§3.5, and the owner's decision 3 in §1.7). |
| 95-102 | 10-17 | Clothing by slot (10), the record's `v` 2 (11), NPCs as one mesh and one material (12), people skinned only near the giant (13), the 23-bone people skeleton (14), the rival giants on the giant's model (15), ogres and trolls as morphs (16), scripted quadrupeds (17). | Not used by Part A. P49 pre-declared Part A's registries only; Parts B and C record these with what they build (P58, P66). |
| 103 | 18 | **One asset writer per wave**, and one writing lane during a gate. | As planned: P48 in W29, P51 in W30; at Gate A the look lane and then the motion lane, one at a time; Gate A2 one lane. |
| 104 | 19 | **Headless stays cheap**: skinned layers only where something is drawn. | As planned: the springs, the flinches and the eyes' look run inside the skinned layers (decision 70); headless the bots and the default tier pay nothing new. |
| 105 | 20 | **The owner sees each part in their hands before it ships**, and the look is theirs to approve. | Checkpoint A: a private page with the Gate A2 candidate, a video of the tour and the giant sheet. **The owner approved it** and decided three things (§1.7). |
| 106 | 21 | **Test tiers as in M10**, `--require` and `--strict-times` at every merge, the default tier at most 72 s and the slow tier at most 400 s at Part A's end. | P49 moved 3.05 s of the default tier to `tests/slow/` and one slow suite to `tests/gate/` for headroom. The Gate A merge's quiet default tier read 62.8 s; the slow tier 375-395 s, near its 400 (P53 moves headroom in W31). This release's final check is in `docs/M11_HANDOFF.md` §5.5. |

### 1.7 The owner's answers to the M11 plan's questions, and checkpoint A

**The questions** (M11 plan §0.6) went out with the note before W29; on 18 November 2026 the owner
confirmed every default ("GO"): three releases, one per part; 59.1 MB for the last download as "about
60"; build sliders and, if the engine allows them cleanly, six face sliders; the two added clothing slots
("armour" and "shins"); the box animals kept rather than a poor wolf; women among the people from more
CC0 body data. Question 7, the look, is asked at each part's checkpoint.

**Checkpoint A** (M11 plan §4.2): the owner saw the Gate A2 candidate on a private page with its video
and the giant sheet, and **approved part one**. With the approval they decided:

| # | Decision | What it changed |
| --- | --- | --- |
| 1 | **Ship part one as `0.11.0-m11`.** | This release (P52): the version, the launcher's notes, the exports and the checks. The tag, the play link and the merge to `main` are the lead's, after the release's checks. |
| 2 | **The giant's native CPU budget with secondary motion is 0.15 ms a frame**, not 0.12 (plan §2.12). Measured with every modifier on: 0.136-0.143 ms at Gate A, 0.143-0.144 at Gate A2; the Web's 0.230-0.248 ms stays within its 0.45. | Plan §2.12's row and `UiProbe`'s comment on `skin_springs_ms` read 0.15; no test or tool encoded the native figure. The row is met. The brain's modifier (0.046-0.051 ms of it) stays P57's to trim if the wardrobe needs the room. |
| 3 | **The warmer skin in the world's light is accepted**, although the default look's lit chest in the creator's light now reads (220, 160, 131), up to 26/255 a channel off the studio render approved for `0.10.0-m10` (198, 170, 157); Part A's gate row asked for 12. | Nothing to change: `test_skin_tone_render` keeps its tolerance of 30/255 and `GiantLook.DRAWN_DEFAULT` the drawn tone; `test_skin_world_render` guards the world's light. The Gate A look lane's FOLLOWUPS row is closed by this decision. |

Known and accepted with the approval, and stated in the handoff and the launcher's notes: the draw calls
at `medium` (379 against 330 in the Valley walk, 642 against 620 in the stress arena; the people's part
brings the room); the creator's first frame in the browser at 3.3 times the median frame (the rule: 3);
no legs or feet in first person; a black shell beard face-on against the sun reads dark; stage 6's
unreforged sword is a sliver at first person's rest; the slow test tier near its 400 s (P53 moves
headroom).

**Checkpoint B, the body's proportions (2026-11-20).** On the owner's explicit request ("the proportionality needs
to be fixed especially with the body legs and shoulders ... whether they are 6 foot or 60 ft"), the orchestrator
lifted the M10 body freeze (decision 9, and decision 91's re-freeze) for one lane, W33body:

| # | Decision | What it changed |
| --- | --- | --- |
| 4 | **The giant's body is reproportioned and frozen again**: legs about 47 % of his height (40 %), about 8 heads (8.35), a visible neck, shoulders about 1.5 times the hips (1.6, and 4.2 head widths wide with the A-pose arms), the hands about three quarters of a head. Every stage keeps its height; gameplay data (capsules, reach bands, grips' ranges, abilities, the stride) is unchanged; the landmarks follow the mesh. | `tools/giant/kit/giant_body.py` `PROPORTIONS`, `proportioned()`; `giant_parts.BUILD_SHOULDER_EASE`; a full regeneration (`--giant-full`), new clips; `tools/giant/fixtures/m10_freeze.json` re-taken (`freeze.py` hashes of the new body, its 53 bones and the nine clips) and the body hash in `test_giant_tools.py`; the animation brief's shoulder and reach (`tests/integration/test_giant_assets.gd`) moved to the new body's. `docs/systems/W33body.md`. |

**Checkpoint B, the approval (2026-11-20).** The owner reviewed Part B's candidate at checkpoint B - the five look
passes and the body's proportions above were made at their request there, and the creator's framings follow the new
body (W33frame) - and **approved part two**:

| # | Decision | What it changed |
| --- | --- | --- |
| 5 | **Ship part two as `0.12.0-m12`.** | This release (P58): the version, the description, the launcher's notes (with the leash's contact rule and the note that a look made in 0.12 shows only in 0.12 or later), the Web build and its checks, the cross-version save run, the screenshots and these documents. The tag, the play link and the merge to `main` are the lead's, after the release's checks. |
| 6 | **The shoulders stay at about 3.1 head widths** ("Keep as is"), not the 2.6-2.9 of the proportions' brief: drawing the shoulder joints in breaks the tested swings' tip matching. | Nothing more to change; `FOLLOWUPS.md` ("From the body's proportions") closes the row. |

Known and accepted with the approval, and stated in the launcher's notes and `docs/M12_HANDOFF.md` §9: capes and
cloaks show two lumps over the upper back from behind; card beards break into blocks from the side and the short
beard reads greyish; the crop shows a thin strip of scalp at the front; the tunic and the shirt, the jerkin and the
cuirass look too alike; the fur cloak is boxy; the browser's creator grids show names instead of pictures; only the
giant changed (the people come in `0.13.0-m13`).

**Gate C and the approval of part three (2026-11-22).** After Gate C (M11 plan §4.1; its code lane `P64c.md`, its
asset lane `P65d.md`, what it leaves in `FOLLOWUPS.md` "From the M13 gate review") the owner reviewed Part C's
candidate and **approved part three**:

| # | Decision | What it changed |
| --- | --- | --- |
| 7 | **Ship part three as `0.13.0-m13`.** | This release (P66): the version, the description, the launcher's notes, the Web build within 44 MiB and its six Chromium checks, the exports, the screenshots and these documents. The tag, the play link and the merge to `main` are the lead's, after the release's checks. |

Known and accepted with the approval, and stated in the launcher's notes and `docs/M13_HANDOFF.md` §9: the women
share the men's face texture; the wolf's ears are bare cones; the horse has no saddle; the rough spots Gate C left
to later passes (the brutes' heads' facets, the off hand open on a haft, the thrown soldier's get-up, one corpse
pose and one crowd hold pose, the procedural gallop, the dead horse's legs, the whelp through the Matriarch's arm,
the chop and the brace without a knee bend, a kilt at a heavy build); the props and machines keep their low-poly
meshes (§3.7).

### 1.8 The M11 decisions in Part B (M11 plan §0.4)

Part B (`0.12.0-m12`) used decisions 87, 92, 95 and 96 and kept 88-90 and 103-106; 97-102 are Part C's (§1.9).

| # | Plan | Decision | What was built in Part B |
| --- | --- | --- | --- |
| 87 | 2 | **The pack budget grows in steps** (26, 32, 44 MiB). | `-m12` is judged against 32 MiB and the giant's 13.6 MiB share. `0.12.0-m12` ships 31,749,016 bytes, 30.28 MiB of 32, in three parts; the giant 13.13 MiB of 13.6 (184 files); the page about 44.7 MB. |
| 88 | 3 | **Gameplay geometry stays the stylized bodies'.** | Kept, through the body's reproportioning (W33body: every stage's height, the capsules, reach bands, grips' ranges and the stride unchanged; the landmarks follow the mesh). |
| 89 | 4 | **The pose brain drives every actor; no gameplay script reads a look.** | Kept; the code rules pass. One gameplay change inside Part B, the leash's contact rule (W32; §3.6), kept as a deliberate change; the seeded soak is unchanged (41 attacks, 33 hits resolved, 4 enemy kills, 2 fence breaks, 7,201 frames). |
| 92 | 7 | **Shape changes: the build by shader, the face by shape keys if the probe passes.** | Built: two build sliders (brawn, girth) pushing skin, garments and the shadow proxy along the normal (P53; the creator stops them at 0.6, the record keeps -1 to 1); six face keys (jaw, chin, nose, brow, cheeks, age) on the head, the beards and the bead sets (P56), the tangent's sign rebuilt in the shaders. Height is still never a choice. |
| 95 | 10 | **Clothing by slot, with an over-layer for armour.** | Ten garment slots and three accessory slots (P53), 35 garments and 8 accessories as parts on demand, 12 outfits as starting points, 14 dyes and 5 metals, each garment a shell at its slot's standoff (P54); since the first W33 look lane pushed out only by what is worn under it. The layering and z-fighting checks (`test_wardrobe_render`, the gate's `test_wardrobe_stack_render` with its positive control) pass. |
| 96 | 11 | **The record goes to `v` 2; schema 2 is kept; a 0.10 or 0.11 build keeps a `v` 2 record untouched and draws the default look.** | Built (P53): `Appearance.migrate` (M10's oracle proves every preset, option and 360 random records draw as before), `NOTE_MIGRATED` once, a v1 record rewritten only at a kept look or the next checkpoint. The release's cross-version run (`docs/M12_HANDOFF.md` §5.4): real saves of `0.10.0-m10` and `0.11.0-m11` continue on this build with the same garments, dyes and designs; a `0.12.0-m12` save opened by both older builds keeps its look record byte for byte through their own checkpoint and draws the default look; the release notes say so. |
| 103-106 | 18-21 | One asset writer per wave; headless stays cheap; the owner sees each part first; test tiers as in M10. | As planned: P54 in W32 and P56 in W33, then the W33 look lanes and W33body one at a time; checkpoint B before the release (§1.7); `--require` at every merge. The default tier read 75-83 s in the W33 lanes' checks with other lanes beside them (a warning; `--strict-times` was not used) and 66.3 s on the release's final check on a quiet machine; the slow tier 408-470 s against its 8 minutes. |

### 1.9 The M11 decisions in Part C (M11 plan §0.4)

Part C (`0.13.0-m13`) used decisions 97-102 and kept 87-89 and 103-106.

| # | Plan | Decision | What was built in Part C |
| --- | --- | --- | --- |
| 87 | 2 | **The pack budget grows in steps** (26, 32, 44 MiB). | `-m13` is judged against 44 MiB, the giant's 13.6 MiB and the people's 12.0 MiB shares. `0.13.0-m13` ships 43,903,980 bytes, 41.87 MiB of 44, in three parts; the giant 13.27 MiB of 13.6 (190 files), the people and creatures 11.25 MiB of 12.0 (117 files); the page about 56.8 MB, inside the owner's "about 60". `build_web.sh`'s last default is now -m13's 44 (P66). |
| 88 | 3 | **Gameplay geometry stays the stylized bodies'.** | Kept: every scene keeps its capsule, hurtboxes, anchors, sockets, NavAgent and the brain's pivots (hidden); no data key but `scene`, `render_lod_m`, `body` and `appearance` changed in an enemy or NPC record. |
| 89 | 4 | **The pose brain drives every actor; no gameplay script reads a look.** | Kept: `PersonRig`, `BruteRig`, `SkinnedWolfRig` and `SkinnedQuadrupedRig` are `ActorRig`s or `QuadrupedRig`s fed by the brain; Gate C's poses are keyed on each action's own clock (P64c). The seeded soak is unchanged (41 attacks, 33 hits resolved, 4 enemy kills, 2 fence breaks, 7,201 frames); `test_people_determinism` with the people on and off, and `test_bosses_seeded_people`, read every gameplay event the same. |
| 97 | 12 | **A person is one mesh and one material**, variants and palettes from the id's hash. | Built (P59, P60): eight roles and 29 variants on one atlas a role, the faction band and the palette rows read in the shader; a skinned person draws the body and its gear (2-3 calls) and one shadow; a crowd one call per role, pose and level. |
| 98 | 13 | **People are skinned only near the giant**; crowds and far levels beyond. | Built (P60): at most 16 people skinned (the held, the striking, the falling, then the nearest within 40 m), the rest crowd instances of baked poses and far meshes; brutes and wolves at most 8 (`CreatureSlots`, P64); horses at most 8 every frame (P62). |
| 99 | 14 | **The people's skeleton is 23 bones**, the giant's names less the fingers. | Built (P59): one set of computed clips poses every variant; the brutes ride the same 23 bones (P63). |
| 100 | 15 | **The rival giants are the giant's model** in looks of their own. | Built (P61, P62): `SkinnedRig` takes an enemy's look from its record's `appearance` (`preset_npc_rival_giant`, `preset_npc_harrok`) and the same meshes as the player's; two garments and a bead set marked `npc`, never offered by the creator. |
| 101 | 16 | **Ogres and trolls are morphs** of the CC0 body. | Built (P63, the P65 passes): `tools/giant/kit/brute.py` reshapes the CC0 MakeHuman data into the ogre and the troll (the whelp the troll's variant), the bosses' gear on the same skeleton (`assets/creatures/PROVENANCE.md`). |
| 102 | 17 | **The quadrupeds are scripted**, the project's own geometry, with the box animals kept as the fallback. | Built (P61, P63, P64, P62): the horse and the wolf from a signed distance field of the project's own parts, their gaits planned in the world with no clip (no planted hoof or paw slides); the wolf's fur shell; `body.rig: "box"` keeps the low-poly rig. The beasts' look passed: every record ships `skinned`. |
| 103-106 | 18-21 | One asset writer per wave; headless stays cheap; the owner sees each part first; test tiers as in M10. | As planned: P59, P61, P63 and the P65 passes wrote assets one lane at a time; headless no person or creature model is made; the owner reviewed Part C's candidate and approved it after Gate C (§1.7); `--require` at every merge. The release's final check: see `docs/M13_HANDOFF.md` §6.1. |

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

**P40 Ship.** As planned, with these deviations. The world tour is a new tool, `tools/world_tour.gd` with `tools/world_tour.sh`, which renders only each shot's frames, because a fully drawn campaign under software OpenGL would take days; its route is the crown-first order assisted (the one route through Fort Aldmere's breach and battle), with three placed shots for what it does not pass. Two bugs in the tool that the run found were fixed before its commit, and the three cosmetic problems its shots showed (the throne's prompt, the map's view at the world's edge, the cut checkpoint toast) went to FOLLOWUPS, not fixed. No game code changed; the version commit also changes the description's milestone count, which `test_launcher_notes` requires. The two Chromium checks the build run ran under load (`stream_check.mjs --world --audio`, `world_check.mjs`) were run again on the quiet machine, where all three pass their default form. The final check ran on the merged head `43d92b8`, beside these documents' last commit, which changes no code. The director's budget rule was kept (decision 45). Left: the strict web audio criteria, the reference PC, real browsers and people (handoff §9), the world matrix's seeds 2-3, two cairns. See [docs/systems/P40.md](systems/P40.md).

### 2.3 M10 (P41-P46)

The ones that change behaviour or a contract, in short. Each package's system document has a
"Decisions and deviations" (or "Decisions as built" and "Deviations") section with the reasons in
full, and its gate section the later changes.

**P41 The giant asset pipeline and the model.** "Bit-exact on the reference toolchain" allows the
bake's own jitter: the tangent-space normal bake came out one texel different (one channel by 1/255)
in 3 of 14 bakes on the same inputs and machine, so `--verify` accepts a Cycles map that differs in at
most 64 texels by at most 1/255 and reports it as `TOLERATED`; anything more is a content difference.
The cause inside Blender was not traced. The scars are designs in the array, not baked into the skin,
so a look can show or hide each. The design values are quantized to the S3TC block's levels. A garment
`covers` a body region when at least 97 % of the region's vertices meet it along their normals. Garment
hems stay open; only cuts at the body's part boundaries are capped. The vendored subset is 133 files,
not the plan's 136 (the default rig, its weights and the SSS image are not needed). The detail maps
are 128 px and there are three (a fur map beside weave and leather). `--verify` never reads the bake
cache. The braies' cut is one loop round both thighs. The Web presets excluded `tex_hi/` in W25
although the owner's answer was already 26 MiB: the plan gave that change to P45. `GIANT_SHARE`'s cap
is the budget less 18.4 MB, so it moves with the budget. The behavioural test of the Web share runs in
the slow tier.

**P42 The look.** The tip-matching contract holds for the weapons that fit their stage; for a weapon
carried past its fit stage the test checks the direction, the reach and the solve, and prints the
capsule's miss (decision 67). The contract runs at stages 1, 3, 4 and 6. The mark's one-time prompt is
the player's own: its flag is set only for a look with a record or a save from before M10, never for a
command-line or bot look, so the bots' runs set no new flag. An empty record sanitizes to the default
with no preset name. Randomize over 1,000 seeds in every scope runs in the slow tier, the session's
tests are a suite of their own, and the shrine case is a slow suite: the default tier's cap could not
carry them. `--creator` without a matching mode warns and starts nothing different. Six long default
tests moved whole to `tests/slow/` for headroom, each still covered by a named suite. Two files outside
the package's list changed because the new signal and prompts required it (`cue_router.gd`'s silent
list, `test_valley_content`). The W25 review then fixed four things the lanes could not see apart:
`GiantLook` loaded texture names as paths, so the real model drew its hair without the atlas and its
garments without their detail maps; "Hidden by your clothing" counted a region as covered only at
97 %, where the creator needs 75 % of one garment's coverage; the shrine tab's summary ignored the
giant's line; a copy of a model shared its original's materials.

**P43 The skinned giant.** The hold reaches further than the plan's "farthest point toward the
socket": the gameplay socket is the stylized arm's, beyond the real palm's reach, so the modifier
protracts the clavicle (up to 18°) and straightens the arm, which brings the palm within 0.23 m of the
socket at stage 1, under the 0.33·k the held body's visual may move. One grip axis (41°) serves every
weapon family, and a wrist limit replaces a per-family axis: the arm is solved again until the wrist
bends at most 45°. A weapon carried past its fit stage points at the tested tip and falls short of it;
that is the look. The airborne pose blends in over the third frame off the ground. A knockback faster
than 0.5 m/s shows the stance, so a slide never walks. The pressed-close camera culls the head's layer
only (decision 72). `tests/support/crosshair_probe.gd` measures a skinned mesh by the triangles its
posed bones move, not by its rest box, which spans the whole body; two first-person suites turn the
skinned layers on. The motion checks are a slow suite. The player's builder instances the model with
its edit state, so the saved scene holds no stale copy of the index. Not built: the stomp's leg lift
(the cut list). The W26 merge added `GiantModel.play_idle()`, which the package had left out, so the
creator's preview idles.

**P44 The character creator.** The sheet tool is a main scene (`tools/character_sheet.tscn`), not the
plan's `-s` script: a script run that way has no autoloads, and the look's rules read the game data.
Sheet A has seven pages (the designs page is two). War paint frames its design's region, as tattoos
and scars do, not always the face. Hand designs frame the left hand, where the one hand design is.
The preview builds no materials headless unless a test asks. The option check's view floors are in
pixels (18 from behind, 90 in first person) and its tiles stand still, so an option is measured
against its base in the same pose. The creator's pad and keyboard walks and the shrine's saves run in
the slow tier. At W26 the scars were a listed known miss of the option check; P46 took them off.

**P45 The Web build, performance and the Chromium checks.** No warm-up was added to the loading
screen: the plan asks for one only if Continue or the shrine path stalls above three times the median
frame, and on the package's branch neither did (the gate later read it over the rule and built it:
§3.4, LD-2). `scripts/main.gd` instead gained the hook of `UiProbe`, which prints the marks the checks
need and exists only with `--ui-probe`. The title's worst frame is reported as a miss by design: it is
the warm-up itself, behind "Preparing...". A stall or a slow skin is a MISS line and fails a check
only with `--strict`, because software WebGL is all this machine has. `build_web.sh --version=V` is
new, so that the `-m10` budget rule could be tested before the version changed. P41's budget test was
updated to the owner's 26 and 7.6. The fullest look shows 12 meshes, not the plan's 13: no preset
pairs the warrior's outfit with long hair and a full beard. `world_start_check.mjs` has no test of its
own; its arguments are tied to the launcher's by a default suite.

**P46 The look pass.** Braids are cards (a herringbone of short lobes over a core card), not the
plan's braided-strand atlas: the same read at the creator's framings and about 0.2 MiB less in the
pack. A hair or beard option may carry a `length`, a cut of its mesh drawn by the shader; two cuts
ship (`hair.shoulder`, `beard.trimmed`), not the plan's two or three a mesh. The option needed the
set's schema and two lines of `Appearance.to_look`, files outside the package's list; the hair's sway
needed one line in `SkinnedRig`. The scars fill two layers of the array and are drawn paler and pinker
than the skin, where they were the skin a little redder and read as nothing in play. The option
check's beard floor was set again by its rule (about half the set's smallest share) on the target
catalogue, where a trimmed beard is compared with the full one. No bake input changed, so the quick
verify was the package's check. Not built: the end-screen portrait (the cut list), the World style and
the weapons' material pass (the owner's answers). No owner's notes had arrived, so none was applied.
The W27 merge fixed the sway forward: it read world transforms while the sandbox's reset had the
giant out of the tree, three engine errors a skinned soak, which broke the determinism gate.

### 2.4 M11 Part A (P48-P51)

The ones that change behaviour or a contract, in short; each package's system document has the reasons in
full, and its "Gate A" and "Gate A2" sections the later changes (§3.5).

**P48 The body pipeline II.** A part's file is `part_path` in the index, not `part` (M10's `part`, a
garment's body part, is read by a test outside the package). `GiantLook.apply` did not call `ensure_part`
and `release_unused` in W29 (not P48's file); the model loads a part when its node is shown and lets it go
when hidden, and P51 added the two calls. Four more CC0 targets were vendored (137 files) so the brawn and
girth directions both exist; that changed the bake's input keys and the bake ran again in full, every map
coming out M10's. The shadow proxy went on render layer 3 (Gate A moved it to 1: §3.5). The free cape still
covers the lower back, so the outfits' data and the designs' rule hold. One texel of the normal bake flips
by 1/255 between runs (M10's jitter, now with an address).

**P49 Web, tools and performance debts.** The launcher unpacks the pack as one stream, a network chunk at a
time (probe 9: 110-120 MB less than joining the text at the last budget), not a part at a time. Exports are
reproducible because the builders write stable node ids (`SceneKit.stable_node_id`) and the imported glTF
scenes are given stable ones before the export (`tools/normalize_imports.gd`); the engine's own random ids
cannot be seeded. The memory growth of a starved browser (the M10 gate's LD-1) is the browser's and the
engine's audio side while no line of the game runs: recorded, not fixed, the checks' memory guard kept. The
loading screen runs the creator preview's warm-up for a `--continue` start; natively on llvmpipe without a
driver cache it does not cover the creator's first frame, on the Web it does. 3.05 s of the default tier and
one slow suite moved down a tier for headroom.

**P50 The giant's motion.** Tip matching places the fist's centre, not the knuckle line (`for_fist`), with
its contract unchanged; in a tested swing the hand keeps M10's orientation and only the generic poses turn
the fist onto the handle. A roar source was added. The springs' joints are rate-limited (720 degrees a
second) after the solver. The pelvis makes up the clavicle's and the spine's shortfall within its own 0.10
x k, so the reach past a weapon's fit stage holds in play. Not done: the skirt's waist fade (Gate A2 instead
stops drawing the legs in first person, §3.5), `carry_two_hand` (the tree is carried one-handed), the
creator's preview without secondary motion or the eyes' look (P55).

**P51 The look pass II.** The curvature is a map of its own (decision 94). Shells are 12 layers on the
desktop and 6 on the Web, stacked at load time. The skin's grade first matched the studio render within
5/255; Gate A traded that match for the world's light (§1.7, decision 3). Not done: a coarser last LOD for
the hair cards, lashes and fuller brows as geometry. The scars that cannot be in the stage-1 rear view or
first person (the face's, the chest's, the left hand's) are listed as such in the rendered check.

### 2.5 M11 Part B (P53-P57, the W33 lanes)

The ones that change behaviour or a contract, in short; each system document has the reasons in full.

**P53 The look record v2.** The index v2's fields for M10's garments went into the data (`set_garment.json`)
because W31 had no asset writer; P54 wrote the index v2. M10's own "future" fixture (`v2_appearance_future.json`,
a `v: 2` with a skin block) now reads as a broken version 2 (the default look and its note, never a failed load);
the later-build cases read `v2_appearance_v3_future.json`. The migration's matrix is split between the default and
the slow tier. Other packages' tests put an outfit on with `Appearance.with_outfit` where they set `outfit.set` by
hand (the record's contract changed; no check loosened).

**P54 The wardrobe.** M10's garments moved by more than a few millimetres where an inner slot has a looser garment;
the cape lies on the back to 0.29 m under the shoulders, so the shoulders' garments lie over it; a helm cuts the
long styles by length, not by a plane (the tail and the wild mane are hidden under a helm). The draw-call budget is
asserted on meshes, as the plan counts them.

**P55 The creator II.** "At most 4 pad moves" is counted in steps (the row, A, the page, the cell); P57 added the
row jumps so the literal presses are at most 6. Moving over a grid's cells puts each piece on; one grid opening is
one undo step. The build sliders stop at 0.6. Per-slot dyes were built here (the split point to P57 not taken).

**P56 The catalogue II.** The scars share the two scar layers' channels by region (no third layer); the body's
colour alpha carries the tangent's sign; the face keys are not on the hair (they fade off the scalp: all six on
every style would have shipped 37.66 MB against 32); hair under a helm is still cut by length.

**P57 Web and performance.** On the Web the grids show names, not pictures (a picture's read-back on SwiftShader
is 0.7-3.9 s, over the stall rule; `--creator-pictures=on` overrides). The zoom moved to the right stick; LT / RT
jump five rows. `test_catalogue_render` moved to the gate tier and two walks to the slow tier for headroom.

**The W33 look lanes and W33body.** Five look passes at the owner's request after the part-two preview (garments
pushed only by what is worn under them, mail and scale, far levels, trophies and rings, skirts and braies, paint
and scars, cloaks, beards, the crop, dyes), each with `--giant-full`; then the body reproportioned under checkpoint
B's decision 4, with the freeze fixture taken again and three hair measures and the face's step ceilings re-derived
on the new body with their reasons (`W33body.md`, "W33frame"). One rendered check keeps a known miss on the new
head: the crop's front edge one pixel above the scalp tint's hairline (`test_hair_render` `KNOWN_MISSES`).

### 2.6 M11 Part C (P59-P65d, Gate C)

The ones that change behaviour or a contract, in short; each system document has the reasons in full.

**P59 The people pipeline.** The `notable` and `rider` roles moved to P61 and then P62 (the brief's split point); no
variant was cut. The people are built at the giant's stage-1 height and exported at 1.8 m so the giant's garment and
clip code applies in its own units.

**P60 PersonRig.** `enemy_actor.gd` needed no hook; the loners share one crowd renderer; the run and the flee play at
2.6 m a cycle, not the brain's phase.

**P61 and P63 The creatures.** The horse's and the wolf's bodies are distance fields polygonized, not rings lofted
along a spine; the bare and the tacked horse are two meshes; the dire wolf is the wolf at twice its size; the Ogre
King's mantle is the giant's `hide_mantle` in the faction's band.

**P62 Townsfolk, riders and the rival giants.** Elder Maren wears a villager woman's variant (the elder role's two
variants are bearded men); the giants' looks draw 23 and 26 calls (no budget names them).

**P64 and P64b Brutes and wolves in play.** The wolf has its own copy of the horse's gait plan; the sweeps and the
throw are the box rig's poses solved onto real arms (P64c keyed the rest on the action's clock); the fur shell is off
at `low` (the Web). The tour's part C was built in P64b.

**The P65 look passes and Gate C.** The owner's notes were applied as asset changes (faces, the women, the wolf's
head, the bosses' cloaks, the mail, the faction colours at 60 m, the rival giants' blob and flap); the props and
machines keep their meshes (§3.7). What is left is in `FOLLOWUPS.md`, "From the M13 gate review".

### 2.7 The open-world expansion (0.14; the A packages)

**The expansion's story and milestones (approved by the owner before A2):**

- **Act one ends at the Stone Throne.** The stage-6 crown and Harrok's duel stay as built; taking the throne sets
  `campaign.completed` and becomes the middle of the game. The throne and the three oaths were the locks the old giant
  kings set on the Worldbreaker, the first titan, chained under the mountains beyond the rim. Taking the throne breaks
  them. The Worldbreaker is the finale.
- **Stages 7-10 (78, 96, 116, 140 ft; levels 13, 15, 17, 20).** Each stage is earned by beating that stage's titan and
  then growing at a new standing stone. Stage 7: the rim cracks, new land opens, the Frostbound Titan comes down from
  the heights above Stonehold; act one's settlements send or refuse aid. Stage 8: the Stormcaller over the Drowned
  Steps floods the lowlands; Harrok returns - an ally if spared, his clan come for the throne if slain. Stage 9: the
  Cinder Titan burns a road toward the kingdom; behind him the Hollow Titan, the shell of the last giant king who
  fought the Worldbreaker and failed. Stage 10: the player breaks the last chain, since the Worldbreaker can only be
  killed awake; the finale is fought at full size in the broken rim.
- **Act one's titans.** Stoneback (55 ft) in a quarry beside Millford, deadly in the Crownmarch until outgrown; the
  Ogre King raised to a signature titan; the Rootwarden in the Greywood; the Bastion Titan (the Broken Warden) at Fort
  Aldmere's toll fort. Every titan has a preparation and an aftermath that changes the settlement beside it.
- **Milestones.** A: Stoneback, the intro cinematic (about 30 s, skippable, with a video export), the Character menu,
  save schema 3 with its migration. B: armour and equipment slots that change the numbers (apart from cosmetics),
  crafting and reforging from titan parts, the Ogre King, the Rootwarden. C: the throne as act one's end, the Bastion
  Titan, settlement development, the land beyond the rim, stages 7-8. D: Frostbound, Stormcaller, stage 9. E: Cinder,
  Hollow, Harrok's return, stage 10. F: the Worldbreaker, balance to level 20, polish, ship.
- **Standing rules.** No level beyond 20; no engine migration; the download cap rises as needed and each build's size
  is reported.

**A2 Stoneback's fight: breakable plates and the titans' rules** (`docs/systems/A2.md`):

- **A titan is struck in one region a pulse, picked from plain values (A2-1).** Hits stay de-duplicated per entity
  (`HitRegistry`), so a swing through three of a titan's hurtboxes lands once; `HitFactory.pick_titan_regions` keeps
  one of his candidates of each call where his first stood (every other target's order and every non-titan hit are
  untouched): the hurtbox nearest the attacker's lock point when the attacker holds him locked (the plate the lock
  frames - the player aims at a plate by the lock), else the earliest sub-step, the deepest contact, the distance and
  the region's name. A weapon swing aimed at a plate that first touches him elsewhere is held back three ticks so it
  can reach the plate; then its first contact lands. Every key is a position, a tick or a name - never the physics
  query's order - so a seeded fight breaks the same plates on the same ticks (`tests/gate/test_stoneback_seeded.gd`).
  Rejected: a hit per hurtbox (it would break the per-entity rule every resolver and test holds), the physics order
  (not stable), the region the attacker's lock names whatever the swing touched (a blow that never reached the
  shoulder would crack it).
- **The plates are state beside the combatant, the resolver stays pure (A2-2).** `PlateSet` (on `CombatEntity.plates`,
  null for everyone else) sets the hit's region multipliers before `DamageResolver` and takes the stone's share after;
  the resolver applies `region_damage_mult` / `region_poise_mult` after armour - exactly 1.0 for every other hit, so no
  pinned number moves (the soak's line is identical). A plate's stone takes the blow's raw damage (before the body's
  armour; a Heavy x1.5); a broken plate's region is a weak point with its own multiplier, which replaces the generic
  1.25 weak point for a titan.
- **A titan's blow scales with his size against the target's (A2-3).** `versus_size_exponent` on his actions:
  raw damage x (his height / the target's) ^ 1.5, clamped 0.5-3 (`CombatRules.versus_size_multiplier`). One number set
  then kills a stage-3 giant in two or three blows and leaves a stage-6 giant room to fight; without it the stage-3
  and stage-6 health gap (890 to 1,525) could not hold both claims. Only actions that name it are touched.
- **His hide is armour-only plates.** The torso and legs carry non-breakable `hide_torso` (55 %) and `hide_legs`
  (50 %) entries: frontal blows at his body do little, as the brief asks; the forearms and shins' stone is armour only
  (60 / 70 %), not a small reward - one rule a region reads more plainly than a dozen small breaks.
- **Phase 2 by plates** (`enter_on_plates_broken`), as P34's `enter_on_poise_breaks`: begun at the first step he is not
  staggered, so the break's stagger plays out before his roar.
- **The animation is authored offline**: seven clips in `tools/giant/kit/stoneback_moves.py` (key poses solved as A1's,
  slerped between), not procedural arms at runtime; `stoneback_clips.glb` regenerates bit-exact with the rest.

**A3 Stoneback felt and placed: his presence, his quarry, his territory** (`docs/systems/A3.md`):

- **Stoneback is 17.7 m (58 ft), not 55 ft (A3-1; a deviation from the approved story's "55 ft").** At 16.8 m and
  hunched he read no taller than the 14.6 m stage-5 giant: the brutes' walk dropped his crown to 14.3-15.6 m. A3
  carries him straighter (the mesh's hunch 14 -> 6 degrees, his own gait: a shorter stride and a 4-degree lean),
  which brought the walk's crown to 16.1-16.3 m at 16.8 m - still within 1.5-1.7 m of a stage-5 giant's crown, less
  than its head. Raised 5 % to 17.7 m his walk carries the crown at 16.9-17.1 m and the idle at 17.5-17.6 m: a head
  and more over stage 5, as the owner asks, with natural proportions; a stage-6 giant (18.9 m) still overtops him
  by 1.3 m. Rejected: a larger raise (the brief's ceiling is about 18 m, and stage 6 must outgrow him) or a
  low camera (the stills must show heights honestly).
- **A world titan's territory is a gateless boss arena (A3-2).** `TitanTerritory` (a `BossArena`, the layout's
  arena style "titan"): he engages a giant he sees (within `territory_m`, in the region), is told where it is every
  second while engaged, and the arena's disengage rule (from his territory's centre: the pursuit line) ends the hunt
  with the boss framework's new attempt (whole, his plates whole, walking home). One mechanism for the boss bar, the
  music, the checkpoint blocker and the checkpoint after the kill. Rejected: a leash on his encounter (it would end a
  hunt at the encounter's centre, never where the giant escaped, and would not make him whole) and new brain states.
- **The director's rules bend by record, not by archetype (A3-3).** His encounter is an arena encounter (no leash),
  `lod_near_m` keeps his AI at the near tier within 400 m, and `reserve_seat` holds his seat in the 12-combatant
  budget while the giant is near (the battles' reservation, `p34_reserve`, and `p34_make_room`); a chunk unload still
  despawns him, safe because his pursuit line lies within the streamer's keep distance. Rejected: exempting titans
  from the budget (a thirteenth combatant), a global LOD change.
- **The settlement changes behind the giant's back (A3-4).** His death sets his outcome at once (the quest, the
  reeve's thanks), but the reopened quarry (`world.quarry.reopened`: the works, the cranes, the carts, Millford's
  forge and stall) shows once the giant has gone beyond his line, or on any later load of his ground - not around his
  corpse. The flag is the territory's (`reopened_flag`), saved with the world's flags (no save schema change).
- **His fight in the world's balance (A3-5)**: the versus-size exponent stays 1.5 (against 17.7 m: x3.34 / 2.04 /
  1.33 / 0.91 at stages 3-6); his rage chains less tightly (phase 2's pause x0.75, the raging smash's windup 1.6 s)
  so a giant who has broken two plates has room to finish him; the shoulders' hurtboxes cover the slabs and the
  deltoid. The expert bot baits his charge into stone. `docs/BALANCE_LOG.md` "A3" has the numbers and what the bot
  still cannot do.

**A4 Milestone A finished: the topple, the Character menu, save schema 3, the intro** (`docs/systems/A4.md`):

- **A stage-5 giant beats Stoneback by breaking his legs, not by a number (A4-1).** His shin plates are breakable
  low targets whose `on_break` effect is `topple`: broken (or after 180 more damage to a broken shin, no sooner than
  6 s after he rose) he goes down on a knee for 6 s, his shoulders, back and brow lowered into a smaller giant's
  reach, every blow x1.15 and a Heavy x1.6 besides; he rises dazed (3 s before he strikes). The effect is data on
  the plate (`on_break`) and the record (`topple`), so the nine titans to come can topple, or not, by data. The
  lock frames his shins first at every stage (`lock_bias_m` -10) and never a knee on the ground; a swing may tilt
  down at them. Rejected: raising a stage-5 giant's reach or lowering his plates (a number tweak the owner ruled
  out), a grab of a kneeling titan (a 17.7 m body in the grab's machinery: FOLLOWUPS).
- **His body follows the kneel, coarsely (A4-2).** Each hurtbox and lock anchor carries its kneeling position,
  carried by its bone's rigid motion from the idle's first key to the kneel's last frame (the kit writes the bones
  into the creatures' manifest; the scene builder computes the positions); TitanEnemy lerps them by the down's
  weight every tick. Positions only: the boxes keep their size and orientation. Rejected: following every clip
  (every strike's frames would move the hurtboxes mid-swing, against A2-1's plain-value pick; FOLLOWUPS keeps it).
- **The balance is measured with the bot playing the titan's fight (A4-3).** TitanDuelBot strikes his shins in
  his recoveries, walks in for heavies while he is down and backs away as he rises; its abilities keep two heavies'
  stamina for his downs (`BotCombat.ability_stamina_floor`, 0 for every other bot: the world and Valley bots are
  unchanged). His health went 6,200 -> 16,000 because stage 6 topples him too; his rage comes after three plates
  (the shins and forearms break now) and his pause is 2.4-3.2 s. The numbers: `docs/BALANCE_LOG.md`, "A4".
- **Save schema 3 holds the expansion's fields; the flags stay (A4-4).** `act`, `titans`, `equipment` (the armour
  slots, empty), `settlements` and `cinematics_seen` are real fields (`ExpansionState`); `_migrate_2_to_3` fills them
  from the flags A3 wrote (`boss.stoneback.outcome` / `.defeated`, `discovered.stoneback_quarry`,
  `world.quarry.reopened`, `world.millford.*`), and every snapshot keeps them in line with the flags (never
  lowering), because the game's own logic (encounters, quests, the territory) still reads the flags. As 1 -> 2: in
  memory, the schema 2 file the backup, a newer file refused and kept. Rejected: moving the flags into the fields
  (every A3 reader would change, and a schema 2 build could not read its own flags back).
- **The intro plays where the giant first meets the world (A4-5).** On the world's first entry of a New Game - the
  "Skip to the Old Kingdom" start and the Valley's hand-over through the Kings' Door - not before the Valley's
  prologue: the prologue is the giant's youth, the intro the kingdom's story and the titans it leads to, and it
  ends on Millford and Stoneback, the first thing the world asks of the giant. Never on a Continue, never twice
  (`cinematics_seen`); again from the title's Watch the intro. A cutscene is a pausing screen over the live world
  (the HUD, the pause and the footer come from the screen stack), its timeline in ticks for a deterministic movie.
- **The Character menu is read-only and always open (A4-6).** It opens in a fight too (it pauses the game, as the
  map and the journal do); the inventory keeps its combat rule. What it shows is changed where it was (shrines,
  forges); the armour slots are shown empty until milestone B and the look's cosmetic `armour` slot is untouched.
- **No new sound (A4-7).** The intro's and the topple's cues are registered ones (the stone hum, rockfall, a huge
  body fall, the titan roar, Harrok's boss stinger, the stomp): the world's registered SFX seconds stay 169.86 of
  170, so decision 8's cap was not raised.

**B1 Functional armour, crafting and reforging from titan parts (milestone B opens)** (`docs/systems/B1.md`):

- **Armour is passives, not statuses, and turns shares (B1-1).** A worn piece's defence, poise, modifiers, perk and
  its set's bonuses go through `Combatant.set_passives` beside the talents' and the ancestry's (`Armour.modifiers`,
  merged by `PlayerProgression.rebuild_passives`); physical defence is armour points (a blow keeps 100 / (100 + A));
  weight is the one new key, `stamina_regen_mult` (2 % slower recovery a point beyond 3, at most 25 %). Unarmoured the
  armour adds no key: every pinned number, the soak and Stoneback's duels are as before. A full Iron set turns 13.8 %,
  a full Quarry set 23.1 % (the owner's 10-15 and 20-25 %), tier 3 x1.3. Rejected: a damage_taken_mult per piece (it
  would stack multiplicatively with the barrier's and ignore armour penetration) and stamina cost for weight (the
  heavies' cost is what a fight is paced by; recovery is gentler).
- **A piece fits every stage (B1-2).** Its numbers are shares (the same share of a blow at any size, the poise
  threshold the same at every stage while the blows' poise scales) and its mesh is skinned to the giant's skeleton,
  which play scales whole: made once, kept as the giant grows. Rejected: a fits-stage range per piece (re-crafting at
  each stage would be busywork without a design reason).
- **The Quarry set's stone is modelled (B1-3).** Flat-topped slabs whose feet hug the skin, iron straps and rings,
  rigid on their skin vertex's weights, built over the bare skin and over what may be worn under them (pushed by the
  layering table as the rings are), in a new index category `armour`; the cloth shader's kind 5 is cut stone with its
  iron in the mesh's band mask (UV2.y; 0 after the glTF's V flip). The Iron and Hide sets show the wardrobe's proven
  garments in their own dyes (only the nasal helm is new). Rejected: the skin pushed out to a plane (shells: its own
  normals and plane fits spiked at the shoulder's round; it read as a rounded rock, Stoneback's plates' own fault).
- **Titan stone is a forge's trait, unlocked by its settlement (B1-4).** `Forge.works` (from the world layout) and a
  recipe's `works` and `requires_flag`: Millford's quarry forge - lit when the quarry reopens - works titan stone; every
  other forge makes the Iron and Hide sets and says where the Quarry set is made. Later titans' settlements unlock
  their recipes the same way. Rejected: a parallel crafting station, and recipes by forge id (a list to edit per
  forge).
- **Titan parts only from titans, and a reason to break his plates (B1-5).** Stoneback stays dead (A3): his loot
  (heart-stone, four slabs, four quarry iron) plus a slab for each stone plate broken in the fight that kills him (the
  brow a quarry iron: `plates[].loot`), and once the quarry reopens two piles in its pit (four slabs, two quarry iron).
  Rejected: re-fighting him for parts (he stays dead) and parts per hit (farmable within one fight).
- **Armour goes on and off anywhere out of combat; forges make and reforge it (B1-6).** The Character menu's
  Equipment tab, under the checkpoint's own blockers (no fight, no enemy hunting the giant). Rejected: equipping at
  forges only (a trip to change a look) and in a fight (a menu as a combat tool).
- **Schema 3 holds it (B1-7).** `equipment.pieces` and `equipment.hidden` are optional keys of schema 3's reserved
  block: an A file loads with nothing owned, an A build reading a B1 file keeps its slots. No schema 4.
- **His sight is by line of sight (B1-8).** `TitanTerritory.sees` adds a sampled line from his eye over his home to
  the giant's chest over the world's ground: the hill round his pit hides a giant on its far side. Rejected: a shaped
  sight region (a polygon per titan to hand-author and keep in step with the terrain).
- **A perk is chosen, never rolled (B1-9).** Each piece names two or three of nine authored perks; the Reforge tab sets
  one (the set's perk cost a change). Rejected: re-rolls.

**B2 The Ogre King as a signature titan; the armour look pass** (`docs/systems/B2.md`):

- **His trophies are plates on P11a's fight (B2-1).** The King is a `TitanEnemy` on `OgreBoss` - his phases, chained
  combo, slam, charge, arena, checkpoint, flags and quest hooks untouched - and his five trophies (crown, bell, two
  wheels, keg) are `PlateRules` plates with the A-milestone's effects (stagger, topple, a weak point) and one new
  generic effect, `unbalance` (every later blow's poise x`poise_mult` for the attempt). His height stays P11a's 8.5 m
  (9.03 m to the crown's points; a stage-3 giant is 7.92 m): his reach, hurtboxes and lock were tuned to it.
  Rejected: a new boss record and scene (old mid-Valley saves name `valley.arena.ogre_king`), and a taller King
  (P11a's reach tuning would have to be redone for a fight a stage-2 giant must win).
- **The trophies are a depth, not a wall (B2-2).** An intact trophy keeps 25-40 % of a blow and none of its poise, so
  a new player's swings still stagger him in his recoveries; a small giant's lock frames only what it reaches
  comfortably (`lock_comfortable_only`: his knee at stage 1, as P11a's; the bell at stage 2) unless the player
  switches. The bot band is kept, not re-tuned: P17b's Valley batch (15 runs,
  seeds 1-3, every outcome, novice, assisted, an expert) before and after B2 - novice deaths at the King 0 of 14
  both, his damage a boss attempt median 0.86 -> 0.85 of the giant's health, the boss segment median 53.2 -> 52.4 s,
  assisted 0.21-0.26 -> 0.21-0.29, every run done; `tests/gate/test_ogre_king_fairness.gd` (stage 2, the novice with
  and without his trophies: 2 wins of 3 against 1, 39 s against 41 s, 0.92 of its health against 0.99).
  Rejected: plates that keep poise (a novice's stagger windows would close) and a lock that frames his crown or
  shoulders for a small giant (swings over its head miss).
- **His parts make a set at forges that work his trophies, after his fall (B2-3).** `works: "ogre_trophy"` on
  Thornwick's smithy and the Giantforge, the recipes' `requires_flag` his defeated flag - B1-4's pattern. The
  Kingsfall set is lighter than the Iron set (11.5 % against 13.8 %) and buys poise instead (+6, then 10 % more poise
  dealt): a stage-2-3 giant's set for staggering titans. Rejected: a third heavy set (Quarry already is one).
- **The armour look pass models what B1 dyed (B2-4).** Pieces conform to the skin by rays cast from inside the body
  outward, their iron is straps and rings on them (never a hoop round a limb), each part rides the skin under its own
  points, stiffened (`follow`), and a piece made for its own set's garments is built over them (`base_cover`) rather
  than pushed. Metal and leather pieces are smooth-shaded with box UVs and their iron in the cloth shader's band mask.
  Rejected: the B1 per-vertex rigid weights (they cut at the deltoid in a raised arm) and the layering push for
  plates over mail (it inflated them away from the chest).
- **His intro plays when his fight engages, once (B2-5).** On `boss_engaged` (the arena's gate closing), recorded in
  `cinematics_seen`, never twice in a session, skippable at once, never in a tool run; 13 s. Rejected: on entering
  Kingsfall (the causeway's prompt is there; a cutscene before the giant sees the arena hides the gate's lesson).
- **No new sound (B2-6).** The trophies' break cues are registered files re-pitched (`sfx.break.trophy.*`); the
  world's registered SFX seconds stay 169.86 of 170, the Valley's 108.57 of 110; the cap was not raised.
- **The Web budgets hold without a raise (B2-8).** A real `tools/build_web.sh`: the pack 45.35 of 50 MB, the giant's
  share 13.72 of 14.0 MiB (ten more modelled pieces), the people's and creatures' 13.84 of 14.0 MiB (his model 1.38 MB
  and clips, no LODs or shadow meshes). The people's cap was not raised to 15.0.
- **A titan's body stays five minutes (B2-7).** `ai.corpse_keep_s` (300 s for him and Stoneback) over the encounter
  director's own free time. A static corpse prop at the reopened quarry was not made (the world's chunk scenes would
  be rebuilt for it; FOLLOWUPS).

**B3 The Rootwarden, the Greywood's signature titan** (`docs/systems/B3.md`):

- **Regrowth is a plate's property, not his (B3-1).** Any plate may name `regrow` (after_s, over_s, health_frac,
  burn_sears); `PlateSet.regrow_step` runs every wound's clock each tick, fire (the titan burning) sears an open or
  regrowing wound for good, and a new generic break effect, `wither` (`on_break.block_s`), stops every clock; a phase
  may enter on a plate's break (`enter_on_plate`). The loot counts a plate broken once even if it grew back
  (`ever_broken`). Rejected: Rootwarden-only code in `TitanEnemy` (the later titans' plates would each need theirs) and
  plates that regrow at full health (a break would be undone; half is enough to make the fire matter).
- **He sleeps until struck or called (B3-2).** `dormant` (his AI off) until a blow wakes him or his territory engages;
  his territory's `wake_on_sight` off - a giant he sees only discovers the grove - and its engage trigger gated by
  `wake_flag` (`world.rootwarden.called`); `rooted_until_phase` 2. Rejected: waking on sight (a giant at the lookout,
  96 m off, would start a fight it cannot win below stage 5; the grove is meant to be looked at first) and a quest
  gate that keeps him unkillable (a strong giant may go straight to him: every stage completes by his rest).
- **His grove is a new layout kind of world parts (B3-3).** `grove` (trunk, root_arch, dead, fallen, pool, stumps,
  saplings) in the structures mesh, a flatten feature for the hollow, a new ride, and flagged scripted elements (the
  resin pots) through `FlagVisibility` wrappers - the chunks and nav layers rebuilt, a second build bit-identical.
  Rejected: modelled tree assets in the kit (more Web megabytes for scenery the low-poly world draws as well) and a
  separate level (the grove is meant to be found from the ride).
- **Wren's words follow the Matriarch's fate (B3-4).** Dialogue entries (no node conditions): unresolved, the blight
  first; slain or driven out, two calls in two texts, the same outcome (`called`: the hollow wakes him, the resin laid).
  Rejected: a third ending for him (he cannot flee or be spared: rooted, his rest is the only end the story allows).
- **Three new sounds and a raised world cap (B3-5).** The lash, the eruption and the regrowth are synthesised
  (`gen_world_sfx.py`); the world's registered seconds cap rises 170 -> 175 s for 0.15.0-m15 (172.86 used); the rip,
  the hurl and his music reuse Stoneback's and the Matriarch's. Rejected: re-pitching B2's trophy splinters for living
  wood (they read as planks).
- **The people's share rises to 16.0 MiB, the giant's to 15.0; the pack holds (B3-6).** A real
  `tools/build_web.sh`: the pack 47.24 of 50 MB; the people's and creatures' 15.26 MiB - over B2's 14.0, so its cap is
  16.0 from -m15; the giant's share 13.86 MiB (the Warden set's pieces), within 14.0 as built but 14.13 by the giant
  pipeline's conservative estimate, so its cap is 15.0 from -m15 (`build_web.sh`, `build_people.PEOPLE_SHARE_MIB`,
  `test_build_web_budget`, the tools' tests; the owner's allowance for the third titan). The page's download about
  62 MB. Rejected: dropping his clips' frames or his textures' size to fit
  14.0 (his bark is what the fight reads by).
- **Balance is set by the duels, not by tuning his plates (B3-7).** His powers and health were set so a stage-4 giant
  dies in every duel far from bringing him down, stage 5 wins the hard fight in 7-9 minutes and stage 6 wins most
  (BALANCE_LOG, "B3"); the plates' numbers (health, regrowth) were left where they read best in the fight (a shoulder
  open about 14 s, regrowing over 6 s). Rejected: an armour-free weak point that ends the fight early (the knot
  withers him; it does not end him).

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
"The M9 gate (lane aldmere): Fort Aldmere's gateway, the King's Road and the crown-first order" and "The M9 gate (lane ironreg): the Iron Regiment's phases, the breach after a death and the war camp's wall", "M9 gate (lane "balance")", "M9 gate (integration)", "M9 gate (catch-up)", "M9 gate (final)" and "M9 gate (the final round)" in P39.md, and "M9 gate (lane review)" in P39f.md (with `docs/BALANCE_LOG.md`'s M9 gate sections)
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
| M9 gate | Fort Aldmere's gate garrison stood in the gateway's mouth with about 5 m beside each flank, less than a stage-4 or stage-5 giant needs; two crown runs of three stopped there (W23). | Its pikes stand beside the gate's approach, not on its line (lane aldmere, `1855c3a`; gate `test_fort_gateway`). On the final code the unassisted crown-first order gets through to the battle. |
| M9 gate | The war camp's shield wall stood across the King's Road at the camp's entrance (30 stuck moments in W23's matrix), then on the diagonal to the Aldmere road's waystone. | The wall stands off the road (lane aldmere, `ea95089`; gate `test_war_camp_road`), then off that diagonal (lane ironreg, `0b6c233`). |
| M9 gate | The crown-first order: the Last Stand killed the assisted giant; all four of the fort's ballistae shot through the Wall, against plan §5.13. | The gate bastions' pair holds its fire until the Charge and keeps its crew counted (lane aldmere, `812e626`, `82eab0b`; `SiegeEngine.set_fire_held`); the HUD names which ballistae shoot and which join at the Charge (`40afc4e`, `f041f7b`; since `b1f2d29` a ballista whose crew is gone for good is left out). Assisted, the crown first wins the battle at its first attempt with no death (`final_after_orders`). |
| M9 gate | The review's major finding: the Iron Regiment's phases went by the battle's bar, which counts its ballistae, so breaking the bastions' pair early brought the Charge and the Last Stand together. | The phases follow the units' health with every engine counted whole (`BattleBoss.phase_fraction`); the bar shown is as it was (lane ironreg, `baaf6a8`; gate `test_iron_regiment_world`). |
| M9 gate | A death undid the breach of Fort Aldmere's gate (every death reloaded the waystone with the gate whole), and the garrison held the giant at the waystone. | The garrison stands down once the gate has fallen, and the breach is checkpointed then (lane ironreg, `23d4d3c`; its fix-up `bb8fab5` dropped the completion request for an oath's road, which had committed the war camp's first wreck mid-fight; gate `test_fort_breach_reload`). |
| M9 gate | The review's leash loop: a member returning outside its leash to a taken post ended its return early and came back, again and again. | A return never ends early outside the leash: it waits off the body on its post, answers a blow and asks for a fresh path after a detour (lane review, `0f89cdd`, `1623c00`; slow `test_leash_waits`, gate `test_war_camp_leash`). |
| M9 gate | The review's minors: an old save lost the director's event tracker; the discovery toast, the hotbar's labels and the map's focus label collided or overflowed; Reeve Tamsin's raid line; "The" in the middle of a sentence. | An old save's tracker as M8 had it (`471f02d`); the toast wraps, the hotbar's labels and the map's label keep clear (`6d06882`, `2c2ab0f`, `7b6cc19`); the reeve speaks of the houses a raid lost (`47b63f2`); "the" mid-sentence (`1f1ba46`) (lane review; `docs/systems/P39f.md`, "M9 gate (lane review)"). |
| M9 gate | No novice slew the Troll Matriarch (W23: six deaths each, no slay). | Tuning, data (lane balance, `b29ddb4`, `6c3d9db`): her phase 2 regenerates 13 hp/s, calls one whelp, and her frenzy is 35 + 40 with a 3.0 s punish window, so the novice can slay her; on the final code the conqueror novice slays her with three deaths (gate `test_matriarch_phase_two`). |
| M9 gate | Lone humans did not flee a stage-4 giant (4 % of their engaged time against plan §5.14's 70 %). | Tuning (lane balance, `ada7ebd`, `18b2708`): an awe tier takes 50 of a soldier's 70 morale before a giant 6x its height, and a soldier sent running does not come back. On the final code the lone soldiers flee 65 %; pooled with the archers and mages, who keep their range by design, 31 % (still missed: a design decision handed to M10). |
| M9 gate | The music was in `combat` 43 % of the stage 4-6 time among only lesser enemies (target under 25 %). | Tuning, mix data (lane balance, `4be451d`): the combat radius is capped at 40 m from a 10 m giant (decision 36); at the final round a hostile crewed engine's landed shot counts as its crew's hit (`3729d2e`). 9 % on the final code. |
| M9 gate | The world bot measured wrong or never tried what a player would (plan §3.23): it fought formations off its way, missed engines that shot it, left abilities unused, and the expert's dodge reserve kept it from every blow. | Measurement fixes in the bot only (lane balance, `73dad1c`, `36d7938`, `41fddb0`, `bd541da`; `docs/BALANCE_LOG.md`, "The bot (measurement fixes, plan §3.23)"); the integration's member scan skips a chunk whose unload is pending (`6e0c7a0`). |
| M9 gate | A thrown enemy fell through the world (found by lane balance's runs). | An enemy fallen through the world is set back at its home (`e3aae55`). |
| M9 gate | Lane balance's verification: the conqueror novice, now past the Matriarch, lost Harrok's slay - struck after his yield, he rose and killed it. | Tuning (`e35781c`): the Strike lands before he rises, leaving him 10 % of his health (`yield_at.strike_health_frac` 0.1). On the final code the conqueror novice of seed 1 still loses the slay (FOLLOWUPS "Harrok's slay", M10). |
| M9 gate | The final review: the Wall's routed men counted as fighting, so the Charge waited until they were cut down across the bailey; a provocation of the gate garrison from before the breach outlived the gate's fall. | Routed planned units count as fallen for the phases and the bar, whose notches follow the phases (`55a56db`; gate `test_iron_regiment_world`); the gate's fall lifts an earlier provocation (`504b989`). |
| M9 gate | The final review: the Moot's watching Skarn giants, within a stage-6 giant's reach outside the ring, were struck by its blows at Harrok and turned Skarn hostile for good. | The watchers are spectators whose blows offend no one, and they leave when Harrok is slain (`af0b7b9`; slow `test_m9_gate_final`, gate `test_stonehold_walkthrough`). |
| M9 gate | The final review: ranged members stepped past their leash for a firing point and were leashed home; riders sent home stuck against the giant in their way; a member answering a blow was held off its leash by any body on its post. | Firing points stay inside the leash (`6bdf7e5`); the riders' "way" wait starts sooner and backs off the body (`771e00b`); only a hostile holder keeps a member off its leash (`71e18df`); the diagnosis's far path check carries on where its query stopped (`c2644d4`, the bot's classification only). |
| M9 gate | The final round's Item B: the stage-4 novice loses the Iron Regiment battle to the inner ballistae and the Wall's pikes. | One tuning attempt (every ballista's reload 6 -> 10 s) lengthened the novice's lives but not to 1-3 deaths, so it was reverted; handed to M10 with its levers (FOLLOWUPS, "From the M9 gate's final round"). |
| Ship (W24) | The docs draft's claim-by-claim audit: 84 findings in README, ARCHITECTURE, DECISIONS and the handoff, 81 confirmed. | 77 applied in the draft (`be21318`); the other four in the release's commits: the strict `stream_check` command's `--build=builds/web` in the build run (`dfdfdfc`); the PERFORMANCE budget row's "3-18" draw calls, the two missing cairns' FOLLOWUPS row and the cited sections checked to exist after the gate in the commit that filled the placeholders (`5ad0f80`). |
| Ship (W24) | The world tour's tool quit at once when the campaign flag ended its run, so no `AUTOPILOT_RESULT`; its map shot was half empty. | Fixed in the tool before its commit (`5b59b41`): `_finish` hands back and waits; the map shot zooms out (`docs/systems/P40.md`). |
| Ship (W24) | The tour's shots showed three cosmetic problems no headless run had: the throne's prompt after the throne is taken, the map's empty half at the world's edge, the cut checkpoint toast. | Handed on, not fixed in the release (FOLLOWUPS, "From the ship package (P40)", M10). |
| Ship (W24) | Two Chromium checks (`stream_check.mjs --world --audio`, `world_check.mjs`) failed their default form on the release build on one hole each the recorder did not place on the main thread, at loads of 12-17. | Run again alone on the quiet machine: both OK, with `audio_check.mjs` again (`docs/PERFORMANCE.md`, "The 0.9.0-m9 release (quiet machine)"); no code changed. |
| Ship (W24) | The world tour's script had no committed `.uid`, which every other `tools/` script has. | Committed (`9f0112a`). |

### 3.3 M10 (the gate, lane look)

The look's findings of the M10 gate review and what was decided; the detail is in `docs/systems/P46.md`, "The M10
gate (lane look)".

| Finding | Decision |
| --- | --- |
| The creator's key light shone on the giant's back (LC-1). | The studio lights turn with the camera's yaw: the key always from the camera's side, the rim from behind. The rendered option check's floors were measured again in that light. |
| First person looking down showed the arms' shoulder caps as flat slabs (LC-3). | Fixed in the shaders, the body mesh untouched: while the camera is inside the head the limbs fade out towards the shoulders (a dithered discard in a box round them). New cap geometry was allowed only if this did not read clean at stages 1, 4 and 6; it did. |
| The model's mesh buffers are 5.87 MB against 3.5 MB (LD-3). | Accepted. The budget row is **6.0 MB** for the target catalogue: every hair, beard and garment mesh is resident whichever a look shows. Loading a style on demand is left to M11. |
| The fullest look draws 4,118 primitives at 121-130 m at 1920x1080 against 4,000 (LD-4). | Accepted and recorded: 3 % over between 120 and about 150 m at 1080p only, met at 1280x720, and the game's camera never stands that far from the player's giant. A coarser last LOD for the hair cards is M11's. |
| `giant_clips.glb` had no provenance row (LD-5). | Row added: computed keyframes, no outside animation data. |
| The hair's card tips at the creator's framings (LC-6). | First handed to M11, then required at the gate and done: a fringe of narrow cards at the hairline of the four long styles, card roots that feather strand by strand, the full and the forked beard's cards as narrow pointed locks whose tips thin out, a beard that fades out seen from behind, the wild mane's locks laid under the shoulders' garments. A change was kept only where the before and after frames of all eight presets showed it clearly better: the short and the braided beard keep their cards. `giant.glb` regenerated; `--giant-full` bit-exact. |
| The default skin read orange-red in the world's light (OR-1). | First handed to M11, then required at the gate and done, parameters only: the skin's `bake_tone` is the default tone, so the default look draws the albedo as the kit baked it (the approved renders' skin) and the other tones scale it by their swatch against the default's; the light's wrap is less red. **This sets aside plan M10 §2.8's row for `bake_tone`** (the constant (0.69, 0.53, 0.44), the kit's bake parameter): with it the default look multiplied the bake by (1, 0.80, 0.74). |
| The far primitives and the mesh buffers after the hair changes. | 3,920 primitives at 121-130 m at 1920x1080: the 4,000 row is met. The mesh buffers read 5.98 MB of the 6.0 MB row. |

### 3.4 M10 (the gate, lanes ui and web)

The other two fix lanes of the M10 gate (the review of the W27 merge: four reviewers over the plan's
eight lenses, every finding verified adversarially; 19 of 21 confirmed). The detail is in
`docs/systems/P44.md`, "The M10 gate's fixes (lane ui)", `docs/systems/P43.md` and `P45.md`, "After the
M10 gate (lane web)", and `docs/PERFORMANCE.md`, "The M10 gate, lane web". Every fix has a regression
test that failed before it.

| Finding | What was found | Fix or decision |
| --- | --- | --- |
| LA-1 (major, ui) | With the mouse a click on a preset below the focused one was lost whenever the pointer moved at all while held: the focused preset's description opened under its button and moved every button below it. | The description is shown in one label under the list; no preset button moves. `tests/slow/test_creator_mouse.gd` sends real mouse events to every preset and swatch row; no suite had. |
| LA-2 (major, ui) | The first click on a colour swatch was swallowed whenever the focus was on another row (hair, beard, ink, paint and dye colours): the row sent the focus back to its chosen swatch while the button was held. | A focus that arrives with the left mouse button down stays on the pressed swatch and applies it; the keyboard and the pad still enter a row on its chosen swatch. |
| LB-1 (major, ui) | The creator at a shrine edited a later build's look (`v` above 1) in place: Keep stored it altered and still marked as the later build's, the giant kept the default look, and unknown shapes raised script errors. No build writes such a record yet; `0.10` is the build that will meet them. | The creator starts from the default look (what the giant shows for such a record) and never holds the later record; a kept change stores this build's record; Cancel and Keep without a change leave the later record as it was. The Appearance tab says that the default look is shown (decision 78). |
| LA-3 (minor, ui) | The creator's preview was drawn at about 720x550 in every window, so upscaled 1.5x at 1920x1080 and 2x at 2560x1440. | On desktop the preview draws one viewport pixel per window pixel, up to 2x. **On the Web it stays at 1x**: the larger viewport's cost there was not measured against the budgets (a follow-up for M11). |
| LA-4 (minor, ui) | The footer hint kept the other device's line for the creator's own keys and buttons. | The creator notes the device of every event it consumes. |
| LA-5 (minor, ui) | Through the faded garments of a "Hidden by your clothing" row the sunken skin showed cut lines at the hips and notches at the shoulders. | While the garments fade the skin is not sunk. The warrior's outfit has nothing under its tunic, so the faded back view still shows bare hips: an asset change, left to M11. |
| LA-6 (minor, ui) | After Back from the launcher's world start the title's focus was on Sandbox. | The focus returns to the button that opened the creator only when one did, otherwise to the title's first entry. |
| LC-7 (minor, web) | The capture tour never captured the mouse, so "Click the game to control the camera" lay across every third-person frame and the video; its throw beat was refused, and the stomp, roar and buff after it with it. | The tour holds the mouse captured, throws as a player does, notes every cast that has not started by its shot and fells the arena's soldiers before the growth beats; `tests/gate/test_capture_m10_tour.gd` runs the whole tour headless. |
| LC-8 (minor, web) | The rendered rig probe could miss its heavy swing's active frame when a frame took long to draw. | The probe pauses the tree while a frame is drawn; the suites assert that no tick passed. |
| LD-1 (minor, web; downgraded from major) | Under CPU load the Web check's page grew to 4.3 and 6.9 GB after Begin and was OOM-killed. The verifier found it is not M10's: `0.9.0-m9` grows the same with the browser pinned to one CPU, and with evenly competing load the candidate finishes. | Recorded as the single-threaded Web build's level load in a starved browser on software WebGL; the allocation inside the page was not chased (M11). Each of the five Chromium checks now watches its page's renderer and stops with a FAILED line over 3,072 MB (`tools/web/memory_guard.mjs`). |
| LD-2 (minor, web) | The world's first frame on Continue was over the stall rule on the Web in six of seven readings (up to 4.61 times the median frame), and the loading screen's warm-up the plan asks for in that case had not been built. | Built: the loading gate ends by putting the camera on the giant and drawing the finished level three times behind "Loading...", the tree paused. The cause was the camera, which stood at the level's start through the load while the save had set the giant down at his shrine. After: 0.36 to 2.51 times the median frame in five runs. |
| LD-6 (minor, web) | The probe's "giant alone" draw-call reading was the difference of two live frames and moved by about 4 from run to run. | Both counts are the median of five frames of the paused level. Re-measured: 12 draw calls and 20,578 primitives for the fullest look at `low`. |
| LC-5 (minor, web) | In the brain's generic arm poses (a roar, the stomp, a buff) the weapon sits on the knuckle line with the fist hanging under it, and the open off hand droops. The tested swings are not affected. | **Deferred to M11**: the fix moves tip matching's socket and needs rendered frames of every weapon at stages 1, 4 and 6 (`docs/plans/FOLLOWUPS.md`, "From the M10 gate review"). |
| LC-2 (refuted) | The Stoneknuckles are drawn as a plank of boxes hanging from the fist. | The frames are accurate and the plan allows it: the player's weapons keep their low-poly meshes in M10 (decision 65; the owner's answer 4), the fists included. Not a defect of M10; realistic weapons are deferred. |
| LC-4 (refuted) | Scars and ancestry marks cannot be made out by eye in play. | Refuted at the game's resolution: at 1280x720 the back lashes, the forearm slash and the lightning tree read from behind. The reviewer had judged the option check's 320x240 tiles, where the giant is about 30 pixels wide. |

### 3.5 M11 Part A (Gate A and Gate A2)

Gate A reviewed the W30 merge (P50 and P51 on P48 and P49) through the plan's eight lenses (M11 plan
§4.1); two fix lanes (the look, then the motion) and a merge, then a second fix round, Gate A2, on what the
merge's own tour showed. The detail is in `docs/systems/P50.md` and `P51.md`, "Gate A" and "Gate A2", and
`docs/PERFORMANCE.md`, "M11 Gate A: the merged measurements"; `docs/M11_HANDOFF.md` §5 has the gate table.
Every change has a test that failed before it or a rendered comparison.

| Finding | Fix or decision |
| --- | --- |
| The skin read chalk-white where the sun lit it and grey-mauve in shade, with ragged bright islands (the W30 merge's frames against 0.10's). | Gate A: the lookup became a per-channel wrap (`SKIN_WRAP`), the albedo's grade eased (saturation 0.8, no gain), a tone away from the default takes back the bake's saturation. The default skin's near-white share 0.88-0.90 to 0.00; the studio match 5/255 to 26/255, accepted by the owner (§1.7, decision 3). `test_skin_world_render` (new). |
| First person cast no body shadow. | Gate A: the renderer culls shadow casters by the camera's mask, and the proxy was on the head's layer, which first person culls; it is on the limbs' layer (1). First person gains one shadow draw a cascade; third person is unchanged. |
| The braies showed bright slivers at the crotch in the world's light. | Gate A: the cloth's rim light ignores N.L; weave and leather take none (fur keeps 0.45). |
| The giant's native CPU a frame with secondary motion was 0.29 ms (§2.12: 0.12). | Gate A: a balanced, gated blend tree (a branch at no weight is not evaluated), the sway run by the rig with its nodes held, fixed parameter slots, no dictionary a frame: 0.136-0.143 ms merged with the picture unchanged (every bone within 0.000005 m). The owner set the budget at 0.15 (§1.7, decision 2). |
| The arms popped up to 81 degrees between two frames when a block started or ended. | Gate A: outside a tested swing each arm's joints move at most 1,200 degrees a second (20 a frame); the arms' worst step 20.0 degrees. The block's gameplay window is untouched. |
| The eyes did not move. | Gate A: the rig writes the eye's `look` toward the lock's focus point, else along the camera's level facing, clamped to about 7.6 degrees and eased. The creator's preview does not turn them yet (P55). |
| The Storm Herald's short beard (a shell) drew as one black mass, the Iron Veteran's greying crop near black with white specks. | Gate A2: the shells take the grey as the cards do, the cards' light and a sky sheen along the strands. A black shell beard face-on against the sun stays dark, as black cards are: accepted. |
| A hit from the front and one from behind read as the same frame; the side flinches leaned toward the hit. | Gate A2: the side clips' sign fixed in `kit/clips.py`; the rig adds the flinches at up to 2.5 times over 0.5 s: the head moves 0.31-0.44 m away from the hit (0.12-0.18 before). |
| First person at rest showed the club upright over the right third of the view. | Gate A2: `fp_rest`'s forearm turned 75 degrees, so the weapon lies low in the lower right corner at every stage (the stage-1 club 0.058 of the frame, 0.183 before). Stage 6's unreforged sword is a sliver there: accepted. |
| First person looking down showed the thighs' flat caps between the arms. | Gate A2: first person draws no legs, as it draws no torso: the skin and every garment discard the pelvis, legs, feet and caps by the region id in `COLOR.r` while the camera is in the head; the shadow keeps the whole body. No legs or feet in first person: accepted. |

### 3.6 M11 Part B (Gate B)

Gate B reviewed Part B's candidate (`47a0af6`) through the plan's lenses; one fix lane followed. The findings and
their fixes are in `docs/systems/GATE_B.md`; what was not fixed is in `docs/plans/FOLLOWUPS.md`, "From the M12 gate
review". Every fix has a test that failed before it.

| Finding | Fix or decision |
| --- | --- |
| **An accepted gameplay change inside Part B: the leash's contact rule** (W32, commit `d09f1d7`). A leash return outside its leash held pressed into a giant's body (its edge within `EnemyActor.LEASH_CONTACT_M` = 0.05 m of his, or into it) for `LEASH_CONTACT_WAY_S` = 1 s on end begins its wait at once ("way", or "post" when he stands on its post) instead of at its second path failure. It changes the war-camp riders' trap: in 20 of 60 Sim phases a rider stayed pressed into him up to 6.8 s, now at most 3.5 s, and every return ends within 11 s. Part B was to carry no gameplay number; this one is kept as a deliberate gameplay change, not a test fix. | Kept; recorded here and in `docs/BALANCE_LOG.md`, "Gate B: the leash's contact rule"; the 0.12.0-m12 release notes name it. The soak is unchanged (41 attacks, 33 hits, 4 kills, 2 fence breaks). `test_leash_waits.test_a_return_pressed_into_a_giant_for_a_second_begins_its_wait_phase_0` / `_phase_30` (slow tier): the wait begins on the 60th tick pressed into him, before any second path failure (with the rule off: 314 ticks and two failures). |
| The look's skip-unchanged cache (P57) left a piece hidden while the build or the layering changed with its old build and push when shown again. | The build and a garment's push are part of each material's own compared values; a whole look still about 0.33 ms. `test_giant_look_cache`, slow `test_giant_look_cache_random`. |
| The creator's grid showed another grid's or another dye's pictures (kept by option id), and a late picture overwrote the open grid's. | A grid forgets its pictures when it opens and shows only those its page asked for (by key). Slow `test_creator_thumbnails`. |
| Typing a name in a grid: Q, E, R, V, F acted mid-word. | The first letter puts the focus in the find box; those keys keep their meaning only as the first key ("/" for a name that starts with one). `test_creator_grid`. |
| The shrine's line and the Colours row ignored a garment's own dye. | Both resolve the dye as the look draws it (`Appearance.slot_dye_id`). `test_appearance_record`. |
| The picture cache was unbounded and keyed a garment by all three dyes. | At most 200 pictures, the least recently shown going first; a garment keyed by its one dye. `test_thumbnail_cache`, slow `test_creator_thumbnails`. |

### 3.7 M11 Part C (Gate C)

Gate C reviewed Part C's people and creatures; the code lane's fixes are in `docs/systems/P64c.md`, and what was not
fixed is in `docs/plans/FOLLOWUPS.md`, "From the M13 gate review".

| Finding | Fix or decision |
| --- | --- |
| Objects that are not people or creatures - the sparring post, the practice dummy, the ballista, the catapult, the talker's horn post and the speaking stone - still draw their box meshes beside the realistic people. | **Decided: they keep their meshes.** Part C replaced bodies (people and creatures), which animate and are judged as bodies; these are props and machines, built of the boxes and cylinders they are, and are not people. A later look pass may model them; nothing in Part C does. |

### 3.8 The open-world expansion's milestone A (the A5 gate)

A5 reviewed milestone A (A1-A4) from the dev head `9460595`, running every suspicion before calling it a finding (the
real game under Xvfb, the Web release in headless Chromium, the real world in the gate tier, saves the released
`0.13.0-m13` build wrote). The findings, their tests and the suspicions rejected are in `docs/systems/A5.md`; what was
not fixed is in `docs/plans/FOLLOWUPS.md`, "From the milestone A gate (A5)". Every fix has a test that failed before it.

| Finding | Fix or decision |
| --- | --- |
| The game's words on Stoneback were the developers' (his items' "A2: ... (no recipe yet)" in the inventory) and taught A3's fight (Bram: his legs "only knocking on a wall"; the quest: the charge and the back) after A4 made his shins the way a smaller giant wins. | Rewritten as the game's; Bram and the slay objective name the shins and the kneel. `test_expansion_text`. |
| **The lock framed his shins at every stage (A4-1's `lock_bias_m`).** | **Decided (A5-1): while he stands, a giant whose swing reaches a higher plate squarely frames the higher plate nearest its camera's aim; the shins only when none is within its swing; down, A4's rule. The lock-switch on a titan cycles his plates across the screen (a pick kept until a new lock or attempt), not the targets.** The duel bot picks his shins with the switch while he stands, so the balance stands as A4 measured it. Rejected: the nearest plate to the giant's chest (A4's, which the shins' bias always won), a separate plate input (one more binding for one titan). |
| **The intro replayed in play** (the brief's "from the title or the Character menu"; A4 did the title only). | **Decided (A5-2): the Character menu's Watch the intro plays it over the live world, only when a checkpoint could be taken** (no fight, no enemy hunting the giant: the replay moves the streamer's focus to Millford, and from far away the giant's chunks and their encounters unload and come back). The cutscene hides the level's titans while it plays and streams the giant's ring back in behind black before it closes. Rejected: replaying it as the title's cutscene-only session (it would leave the game in play). |
| The roster's unnamed tenth slot. | Harrok, sixth (his return at stage 8), as the owner's list has him. |
| A plain `tools/check.sh` passes without what A2 moved to the slow and gate tiers, and said it parsed every script. | **Kept as A2 left the tiers** (the default tier's 75 s); the plain run now says what it left out. The definition-of-done run (`--slow --gate`) is unchanged. |

### 3.9 The open-world expansion's milestone B (the B4 gate)

B4 reviewed milestone B (B1-B3: functional armour and the forge's crafting, the Ogre King as a signature titan, the
Rootwarden) from the dev head `61d2b8a`, running every suspicion before calling it a finding (the real game under Xvfb
driven by the UI probe's new titan tour, saves the released `0.14.0-m14` build wrote, the real Valley and the real
grove in the gate and titans tiers, the Web release in headless Chromium). The findings, their tests and the
suspicions rejected are in `docs/systems/B4.md`; what was not fixed is in `docs/plans/FOLLOWUPS.md`, "From the
milestone B gate (B4)". Every fix has a test that failed before it.

| Finding | Fix or decision |
| --- | --- |
| **Every save past the Valley that an older build wrote held the Ogre King's fall but none of his parts**: the Kingsfall set could never be made, and (B2's roster) his record listed drops the giant never got. | **Decided (B4-1): such a save is given his hide, crown-iron and bell-bronze once as it loads** (his defeated flag set, no record of him: `ExpansionState.owed_parts`, `SaveSlots.read`), and the load says so; his trophies' extras are not owed. A save this build wrote records him, so nothing is given twice. The load also brings the titans' records into line with the flags (a 0.14 schema-3 save showed him unmet until the next checkpoint). Rejected: a version check (the record is the save's own proof), leaving it (a 0.14 player could never make the set). |
| **A swing locked on one of the King's trophies landed on his torso** wherever it first touched him (`HitFactory.AIM_SNAP_M`, 4.5 m, set for Stoneback's 17.7 m, holds every hurtbox of the 8.5 m King): locked on his bell from the front a stage-3 giant struck his torso 2 swings of 3, locked on his keg from behind 5 of 6 - why no bot broke his keg. | **Decided (B4-2): a titan's record may set its own snap (`aim_snap_m`: the King 1.2 m), and for such a titan a swing locked on a plate beyond his body (his keg from his front) is not held back for it.** Stoneback and the Rootwarden set none: their fights are unchanged. The King's duels were re-run: the novice keeps B2's band, the aimed expert wins faster (BALANCE_LOG "B4"). Rejected: enlarging his trophies' hurtboxes (P11a's body and B2's fairness), scaling the snap with height alone (his torso's centre stays inside any share that keeps Stoneback's 4.5 m). |
| **The test tiers outgrew `check.sh`'s one-hour limit**: default, slow and gate took 3,020 s at B3 in one process limited to 3,600 s; the gate's first run here was cut off by it. | **Decided (B4-3): the signature titans' balance duels are their own tier, `tests/titans`** (Stoneback's balance and seeded duels, the King's fairness and keg, the Rootwarden's arena and grove duels), run by `--titans` and by `--gate` as a second process with its own log, limit (40 min) and budget (25 min); the first process's limit is 80 min (a hang guard, not the budget); the TIMES line names the titans' time. The default and slow tiers stood at or over their budgets on this machine (the dev head 74.6-76.2 s and 492 s): the titans' integration scenes moved to the slow tier, the world's seams and walk and the armour render to the gate (default 70.0 s, slow 414.8 s). Nothing was dropped. |
| The cutscenes drew the player's giant without its armour; the Materials tab listed only Stoneback's materials as a titan's; the Kingsfall recipes' "the Giantforge in the ruins" did not say the Valley; the snare's bind showed only the hit's white flash; the launcher called this build the milestone's first. | Fixed as found (B4.md G4-G8). |
| **The Rootwarden is harder in his real grove**: stage 5 loses 3 of 3 there (run alone; in the titans' tier it holds out to the limit with him at 18 %) where it won 3 of 3 on the test arena's floor. | **Decided (B4-4): recorded, not tuned** - one bot's measure in a new place, against B3's tuning on the floor, is not enough to move his numbers; the grove duels now run in the titans' tier and FOLLOWUPS carries it to the owner. |

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

### 4.3 The M10 plan (its §8)

Three reviews of the plan's first draft, each answered in the plan before any package started: a
feasibility review (14 findings), a review from the owner's and the player's side (10) and a review
of the process and the tests (15). All 39 findings were checked against the code, the logs or the
reviewer's probe and folded in, 34 as proposed and 5 with a change; seven of the reviewers' specific
proposals were rejected, each with its reason (a locomotion clock from ground speed in every grounded
state, a required stomp clip, committing the full-resolution bake outputs, a first-person mask test on
background pixels, among them). The plan's §8 lists every finding and where it went, and §7 the probes
that verified the facts the plan rests on. The reviews are the reason for, among others, the capped
cuts and the three render layers (decision 72; the owner's review, finding 7), the packing rule of the
design array (75; feasibility 4), the positive controls of the determinism gate (69; feasibility 3),
the rule that options must read in play and its rendered check (82; the owner's review, 4), the
owner's three checkpoints (83; the owner's review, 1), the legs' sources that keep a stride from
gliding or stepping in the air (66; the owner's review, 3) and `--require` with `--strict-times` (84;
process 4 and 5).

### 4.4 The M11 plan (its §7)

The M11 plan carries a verification log instead of a review section: what was read in full, what was read
in the code at `5ff50f0` (each fact marked VERIFIED), what was derived, and the ten probes of its §1.2,
run before W29 and recorded under the log. Two changed the plan: probe 10 found a clothed person ships at
about 282 KB, not 165 KiB, so Part C's variants per role or their triangles come down (P59's first
variant decides); probe 6 set the shells at 12 layers on the desktop and 6 on the Web. The others confirmed
the plan's designs (parts on demand, the build by shader, the face keys with morph tangents, the springs,
the lookup in `light()`, the people's clip driver, crowd variation, the launcher's stream).

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
| Weapon shape | A capsule along the arm and weapon, swept from the previous to the current pose; the procedural rig reads the same `AttackGeometry`, so the visible swing is the tested swing. Since M3 it scales with the growth stage and the weapon's fit. **Changed in M10 for the player's giant (decision 67, tip matching):** the tested capsule and everything that decides a hit are as this row says, but the realistic arm cannot reach the stylized grip, so the visible swing is no longer the tested swing to within a degree. The hand takes a grip the real arm can reach and the visible weapon aims at the tested segment's tip: its outer half stays inside the tested capsule and it lies at most 15° off the tested direction (measured: median 7.1°, worst 12.9°), for every weapon that fits its stage. Every other actor's rig still reads `AttackGeometry` directly. |
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
| First person | Eye at 92 % of height; head, chest and belt on render layer 2, culled by the first-person camera. First-person lock never rotates the camera unless the optional aim assist is on. **Changed in M10 (decision 72, render layers with closed cuts):** the eye and the camera's geometry are as this row says, but the realistic body is three meshes with capped cuts - the head with the eyes, hair and beard on render layer 3, the torso with the garments' core parts on layer 2, the limbs on layer 1. First person culls layers 2 and 3; third person with the arm pressed close culls layer 3 only; the tree's canopy and the pine's needles moved to layer 3. Since the M10 gate the limbs also fade out round the shoulders while the camera is inside the head (§3.3, LC-3). |
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
