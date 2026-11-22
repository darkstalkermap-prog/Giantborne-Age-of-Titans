# M11 handoff, part three: realistic people and creatures (`0.13.0-m13`)

Spec §16 lists what every milestone handoff must contain: changed files and a runnable project, the
exact engine version, launch and export instructions, controls, implemented versus deferred
features, test results with measured evidence, known bugs, and the next smallest milestone. This
document provides each for **Part C of `docs/plans/M11_PLAN.md`**, released as `0.13.0-m13`, the last of
M11's three releases (decision 86). Part A is [M11_HANDOFF.md](M11_HANDOFF.md) (`0.11.0-m11`, the giant
refined) and Part B [M12_HANDOFF.md](M12_HANDOFF.md) (`0.12.0-m12`, more customization). The earlier
handoffs are [M10_HANDOFF.md](M10_HANDOFF.md), [M6_M9_HANDOFF.md](M6_M9_HANDOFF.md),
[M2_M5_HANDOFF.md](M2_M5_HANDOFF.md) and [M1_HANDOFF.md](M1_HANDOFF.md).

| Spec §16 item | Where |
| --- | --- |
| Changed files and a runnable project | §2 |
| The exact engine version | §1 |
| Launch and export instructions; controls | §3 (README §2, §3, §6 and §7) |
| Implemented versus deferred features | §4 |
| Test results with measured evidence | §5 (Part C's rows, Gate C, the ship), §6 (the checks and the measurements) |
| Known bugs | §9 |
| The next smallest milestone | §10, after the owner's approval (§7) and tasks (§8) |

**In one paragraph.** Every body around the giant is realistic now. A committed pipeline builds people from
the same CC0 body data as the giant (with the women's targets of the same release): eight roles and 29 variants
on one 512 px atlas a role, dressed by the giant's own wardrobe code, with crowd poses, far meshes, one set of
computed clips and their gear. Soldiers, pikemen, shieldmen, archers, mages, bannermen, siege crews and the iron
guard wear a surcoat in their faction's colour; villagers and elders, men and women, and the named characters
and Corvane are people too; riders sit on a skinned horse; the rival giant and Harrok are the player's own model
in looks of their own; the ogre, the troll, the whelp, the Ogre King and the Troll Matriarch are morphs of the
CC0 body with their gear; the wolf and the dire wolf (the project's own geometry, like the horse) wear a fur
shell. Up to 16 people near the giant are skinned and animated on the pose brain's clocks, the rest are crowd
instances and far meshes; brutes and wolves take up to 8 slots. Gate C keyed every human strike and brace, the
rival giants' chop and strokes and the dead, held and thrown on each action's own clock. **Nothing that plays
changed**: no gameplay node, timing or number moved, and the seeded soak is the same as at `0.10.0-m10`,
`0.11.0-m11` and `0.12.0-m12`. Everything was measured in a Linux container without a GPU, a real browser, a
gamepad or a human player. **The owner approved part three after Gate C** (§7).

**The gate's result**: Gate C reviewed Part C through the plan's lenses (§4.1); its code lane (`P64c.md`) and its
asset lane (`P65d.md`) fixed the confirmed findings, the owner accepted three rough spots for this release, and
what remains is in `docs/plans/FOLLOWUPS.md`, "From the M13 gate review". Gate C's merge (`b808eef`) is this
release's code; the ship step added the version, the launcher's notes, the budget's branch order, the screenshots
and these documents (§5.4).

## 1. Engine, build and environment

- **Engine**: Godot 4.6.3-stable (`7d41c59c4`), the standard build, GDScript, the Compatibility
  renderer, Jolt, the fixed 60 Hz simulation. Unchanged since M9.
- **The asset toolchain** (only to regenerate `assets/giant/`, `assets/people/` and `assets/creatures/`; never to
  build, export or play): Python with `bpy` 5.3.0, numpy, scipy, Pillow and OpenEXR, pinned in
  `tools/giant/requirements.txt`, in a venv outside the worktree (`GIANT_VENV`). `tools/giant/build_people.py`
  builds the people and the creatures with the same venv; its ambient occlusion is the project's own ray caster.
- **Where it ran**: a Linux container with 4 shared CPUs, no GPU (llvmpipe natively under Xvfb,
  SwiftShader in headless Chromium), no speakers, no gamepad. Every frame time here is a software
  renderer's and indicative only.
- **Version**: `0.13.0-m13`, set by the ship step (P66) with the project's description and the launcher's
  notes. `tools/build_web.sh` reads `-m13` and applies the 44 MiB budget, the giant's 13.6 MiB share and the
  people's 12.0 MiB share.

## 2. Changed files and the runnable project

Part C is the commits from the `0.12.0-m12` tag to Gate C's merge (`b808eef`): 98 commits (14 merges), 431 files
changed, 45,366 lines added and 5,466 removed; then the ship step's commits (§5.4).

| Area | Files changed (lines added) | What |
| --- | --- | --- |
| `assets/people/`, `assets/creatures/` | 70 (12,117) and 44 (3,200) | Eight roles' meshes (variants, crowd poses, far meshes), atlases, `people_clips.glb`, `gear.glb`, the manifest and provenance; the horse, the ogre and the troll with their clips, the wolf with its fur map and poses |
| `assets/giant/` | 8 (5,631) | The rival giants' garments (hide mantle, war harness) and the iron beard rings; the index and manifest |
| `tools/` | 122 (10,890) | `tools/giant/build_people.py` and the kit (`people_roles`, `people_body`, `people_outfit`, `people_bake`, `quadruped`, `brute`), the 88 added CC0 targets (`tools/giant/mpfb2/PEOPLE.sha256`), `test_people_tools.py`; the scene builders; `character_sheet.gd` (pages c1-c5); `tools/web/people_check.mjs` |
| `scripts/` | 35 (6,207) | `PersonRig`, `PersonLook`, `PersonModel`, `CrowdRenderer`, `BruteRig`, `SkinnedWolfRig`, `SkinnedQuadrupedRig`, `CreatureSlots`, `PeopleWarmUp`; `SkinnedRig` for the rival giants; the `person_role` schema and the `body` key; `capture_m11.gd` part C; `PeopleWebProbe` |
| `data/` | 40 (669) | `data/people/role_*.json` (eight roles); `body` (and the giants' `appearance`) in the enemy and NPC records; the rival giants' presets; the npc-only garments and beads |
| `scenes/`, `assets/shaders/` | 22 and 6 | Every person's and creature's scene rebuilt with its Visual (gameplay nodes unchanged); `person`, `person_crowd` and `fur_shell` shaders |
| `tests/` | 67 (3,244) | The people's determinism and seeded bosses with the people drawn, the readability of telegraphs on real bodies, the rigs, the crowd, the strikes, the render and draw-call probes |
| `docs/`, `web/` | 16 at the merge, and these | `docs/systems/P59.md`-`P65d.md`, `PERFORMANCE.md`, `FOLLOWUPS.md`, `DECISIONS.md`; with the ship step this handoff, `docs/systems/P66.md`, the README, `ARCHITECTURE.md` §26, `DECISIONS.md` §1.7, §1.9, §2.6, `CREDITS.md`, the screenshots in `docs/screenshots/m13/`, the version and the launcher's notes |

No enemy or NPC record changed a key other than `scene`, `render_lod_m`, `body` and `appearance`; no gameplay
script changed. The project runs as before: README §2.

## 3. Launch, export and controls

As README §2 (run it; `--skin` / `--no-skin` now switch the people and creatures too, `--people-cap=N`,
`--others-cap=N`, `--people-far`), §3 (the controls, unchanged), §6 (the M11 capture tour's part C,
`--scenario=capture_m11 --part=c --skin`, and the people sheet, `--sheet=c`) and §7 (the exports and the browser
build). An export needs neither Blender nor the venv. The launcher's download note reads "About 56 MB" (the engine
and the pack as shipped, 56,432,680 bytes; the page with the loader, the worklets and the poster is 56,837,922
bytes, about 56.8 MB).

## 4. Implemented versus deferred

### 4.1 Against Part C's gate rows (plan §0.3)

| Requirement | Built |
| --- | --- |
| Every human enemy and NPC a skinned, textured body from the pipeline, driven by the unchanged pose brain; at least two variants a role (three soldiers, five villagers); skin and hair varied; clothing by faction and role; named characters recognisable | Yes (P59, P59b, P60, P62, the P65 passes): eight roles, 29 variants (soldiers 4 with the iron guard, villagers 5 of whom two women, elders 4, the eight named characters each their own), palettes from the id's hash, the faction's surcoat colour checked at 60 m (P65d) |
| A formation of 40 at `low`: at most 250 draw calls with the giant, at most 16 skinned, the people's CPU at most 2.5 ms a frame on the Web | Yes on the release's Web build (§6.4): the forty 25 m before the giant 46 draw calls, 12 skinned and 28 crowd, 2.0 ms of the people's CPU; with five wolves and a dire wolf 52 calls and 2.1 ms. Native at most 0.6 ms: about 1.3 ms here on llvmpipe (P64), **not met here**; the reference PC is the owner's |
| Riders are people on horses; rival giants and Harrok the giant's body with their own looks; ogres and trolls morphs of the humanoid body; wolves and dire wolves modelled quadrupeds | Yes (P61-P64) |
| Corpses stay and free their slot after two seconds; a grabbed soldier hangs in the fist and tumbles when thrown; every telegraphed wind-up differs from idle by its view floor; flashes and tints on every surface, crowd instances included | Yes (P60, P64, P64c; `test_people_readability`, gate); since Gate C the dead drop their gear and the thrown get up within their stagger |
| Nothing that plays changes, with the people skinned or not, with positive controls | Yes: the soak's `AUTOPILOT_RESULT` is the baseline's on the release (§5.4); `test_people_determinism`, `test_bosses_seeded_people` and the giant's determinism gate pass on the final check |
| The download at most 60 MB: the pack at most 44 MiB, the people's share at most 12.0 MiB | Yes: 41.87 MiB, 11.25 MiB, the page 56.8 MB (§6.2) |
| Every people and creature asset regenerates bit-exactly from audited CC0 data or the project's own code | Yes: `PEOPLE VERIFY OK` with every pass on the release's final check (§5.4); `assets/people/PROVENANCE.md` and `assets/creatures/PROVENANCE.md` |

### 4.2 Deferred, and planned but not built

- **Out of reach in this engine configuration** (plan §0.5): strand hair, motion capture, talking faces; the animals
  are scripted, not filmed.
- **Planned and not done**: a get-up clip, corpse limb variants and a left grip on a haft (the asset lane); a
  saddle, the wolf's furred ears and the women's own face texture (accepted for this release); the props and
  machines keep their meshes (`DECISIONS.md` §3.7).
- **Done another way**: the horse and the wolf are distance fields polygonized, not lofted rings; the tour's part C
  came in P64b; the notables and riders moved from P59 to P62.

## 5. The gate and the release

Legend: **PASS** = verified by running the game, the engine or the tools here. **PARTIAL** = verified
here with a part that only real hardware or a person can confirm, or with part of the requirement met.
**FAIL** = measured and not met. **NOT RUN** = needs hardware, people or a step that is not this package's.
A Result is the verdict on the release's code unless the row names another commit.

### 5.1 The lenses on Part C

| Lens | Result | Evidence |
| --- | --- | --- |
| 1. The owner's request (realistic NPCs: every kind the owner listed, in their order) | **PASS** (the look is the owner's: lens 8) | §4.1; every enemy and NPC record names a body; the screenshots in `docs/screenshots/m13/` |
| 2. Gameplay unchanged | **PASS** | The soak's `AUTOPILOT_RESULT` on the release's final check and on the Linux export (41 attacks, 33 hits resolved, 4 enemy kills, 2 fence breaks, 7,201 frames, 0 errors); `test_people_determinism` (people on and off, with positive controls), `test_bosses_seeded_people` (two seeds of each boss without and with the people and the giants drawn), the giant's determinism gate and the readability gate pass (§5.4); no record key but `scene`, `render_lod_m`, `body` and `appearance` changed |
| 3. Animation quality | **PARTIAL** | Gate C keyed every human strike and brace, the rival giants' chop and strokes, the dead, the held and the thrown (`P64c.md`; `test_person_strikes`, `test_rival_giant_rig`, `test_brute_rig`); the tour's part C films them (264 frames). Left: the get-up is the fall played back, one corpse pose, the off hand open on a haft, the procedural gallop, the chop and the brace without a knee bend (§9) |
| 4. Saves and migration | **PASS** (the suites); the cross-version run **NOT RUN** | Part C changed neither the save schema (2) nor the look's record (`v` 2; `test_predeclared_m12`); the fixtures of `0.5` to `0.12` load in the suites of the final check. No cross-version run with older builds was made for this release |
| 5. UI and controls | **PASS** | The HUD's lock line, health bars and telegraphs over the new bodies (`test_people_readability`, the tour's frames); no UI string changed. A real gamepad is the owner's (§8) |
| 6. Web and performance | **PARTIAL** | The pack 41.87 MiB of 44, `PEOPLE_SHARE` 11.25 of 12.0, `GIANT_SHARE` 13.27 of 13.6, the page 56.8 MB (§6.2); the six Chromium checks OK (§6.4); every figure a software renderer's; the people's native CPU over its 0.6 ms here |
| 7. Provenance and determinism of the assets | **PASS** | `PEOPLE VERIFY OK` (every pass) and `GIANT VERIFY OK` on the final check; `PROVENANCE.md` for every creature file; `CREDITS.md` |
| 8. The look | **PASS** by the owner's approval after Gate C, with the rough spots of §9 accepted | The P65 look passes followed the owner's notes; the people sheet (c1-c5) |

### 5.2 Gate C's findings

Gate C's code lane (`docs/systems/P64c.md`) keyed the poses on each action's clock (the rival giants' chop had no
pose; the people's strikes took the box rig's generic pulse), made the dead drop their gear without a pop at the
corpse switch, and fixed the held soldier's weapon and the thrown soldier's landing; its asset lane
(`docs/systems/P65d.md`) made a formation's side read at 60 m, separated two faction pairs, fixed the rival giants'
blob and flap and the bosses' mantles. The props and machines keep their meshes (`DECISIONS.md` §3.7). What it left
is in `FOLLOWUPS.md`, "From the M13 gate review" (§9).

### 5.3 Follow-ups deferred

`docs/plans/FOLLOWUPS.md` holds every open row with its owner, in "From the M13 gate review" and "From the 0.13.0-m13
release (P66)". The ones a player can meet are §9's.

### 5.4 The ship (plan §3.19, as P52 and P58)

The ship step (P66, `docs/systems/P66.md`) on `pkg/p66`, cut from `b808eef` after the owner approved part three.

| Item | Result | Evidence |
| --- | --- | --- |
| The final check on the final code: every scene rebuilt with no diff, every tier, `--giant`, `--people`, `--people-full`, `--web-tools`, the soak, `--require` | **PASS** - `nice -n 10 tools/check.sh --build --slow --gate --giant --people --people-full --web-tools --require` on `e118922` (the release's code; the commit after it records this row): **CHECK PASSED** (03:15-03:58 UTC, 22 November, loads 0.65 at its start and 1.17 at its end, nothing else running). Every scene rebuilt with no change to a tracked file; the world's 64 chunks and 112 seams ok. The giant pipeline's 40 tests OK; `GIANT VERIFY OK: 91 files regenerated bit-exact` (the cheap passes) in 123 s; `GIANT_ESTIMATE shipped_mib=13.51 cap_mib=13.60`. The people pipeline's 48 tests OK; `PEOPLE VERIFY OK: 55 files regenerated bit-exact (every pass)` in 176 s; `PEOPLE_ESTIMATE shipped_mib=10.66 cap_mib=12.00 variants=29`. The Web tools' own tests OK. **378 suites, 80,460 checks, 0 failures; default 71.4 s, slow 441.5 s, gate 1,649.8 s**; no skip note. The 120 s soak's `AUTOPILOT_RESULT` is identical in all 28 keys to the Linux export's (41 attacks, 33 hits resolved, 4 enemy kills, 2 fence breaks, 7,201 frames, 0 errors, 0 warnings). The first run, on `6e4085b` (02:31-03:14 UTC), failed three checks of one test (`test_giant_tooling`: its forced 23 and 26 MB budgets were judged by the project's version, now -m13, where the people's share also comes off the giant's) with 378 suites, 80,457 checks, default 73.1 s, slow 455.1 s, gate 1,681.4 s; `e118922` names the version those runs mean (nothing loosened) | §6.1 |
| README, ARCHITECTURE, DECISIONS and CREDITS; this handoff | **PASS** | README.md (the introduction, §2, the options, §6, §7, §9, §10, §11), `docs/ARCHITECTURE.md` (the intro, §22, §26 new), `docs/DECISIONS.md` (§1.7 the approval, §1.9, §2.6), `CREDITS.md`, this document, `docs/PERFORMANCE.md` ("The 0.13.0-m13 release", the repository's growth), `docs/plans/FOLLOWUPS.md`; `tests/unit/test_ship_docs.gd` passes on them |
| Screenshots in `docs/screenshots/m13/` | **PASS** - 14 JPG of 71-94 KB at 1280x720, drawn by the game from source under Xvfb on llvmpipe with the M11 tour's part C (`--part=c --skin`, 264 frames, complete, 0 errors and 0 warnings by the game's count): townsfolk, a rider at the gallop and a charge, a soldier's slash, the pike's brace, the shield's bash, a held soldier, the dead, the troll beside the giant, the Ogre King's slam, the Troll Matriarch's sweep, the rival giant's chop, wolves at the trot and a wolf's lunge. The people sheet's five pages were drawn too (not committed) | `docs/screenshots/m13/` |
| The Web export within 44 MiB in three parts, `PEOPLE_SHARE` within 12.0, `GIANT_SHARE` within 13.6, built with the same bytes | **PASS** - `env -u XDG_DATA_HOME nice -n 10 tools/build_web.sh` (the release, into `builds/web/`; the project's own version, no `--budget-mb`): `PCK_SIZE preset="Web" raw=44254876 gzip=32927985 shipped=43903980 shipped_mb=41.87 budget_mb=44 parts=3`, three parts of 14,634,660 bytes; `GIANT_SHARE giant_bytes=15244986 shipped=13911024 shipped_mib=13.27 files=190 cap_mb=13.6`; `PEOPLE_SHARE people_bytes=11099811 shipped=11794708 shipped_mib=11.25 files=117 cap_mb=12.0`; `PCK_SHA256 338d82f18d8aa13562761d188d29abb8de33677188c4cb584e95b9a779f0189a` on both builds (the first on `b7129f3`, before the BUILD line and the note were committed, so only its `play.html` differs; the second on `e118922`, the final check's commit: **the folder to publish is `builds/web/` of the ship step's worktree**, built from it); 3,165 packed files, no test content, every record valid without `data/test`. The page's download 56,837,922 bytes | `PERFORMANCE.md`, "The 0.13.0-m13 release" |
| The six Chromium checks | **PASS** in their default forms - all six **OK**: `people_check.mjs` on the `Web (test)` build (the formation 46 draw calls and 2.0 ms of the people's CPU, the wolves 52 and 2.1 ms, the town 117; first frames 1.03x, 1.87x, 0.84x; the renderer's peak 665 MB); on the release build `creator_check.mjs` (2 misses reported, both the title's warm-up by design; the creator's first frame after New Game 0.29x; the skin with secondary motion 0.21-0.27 ms; peak 1,215 MB), `world_start_check.mjs` (both starts through the creator, saves with `build_version` `0.13.0-m13`; peak 1,091 MB), `audio_check.mjs` (231 holes, all the main thread's; peak 1,118 MB), `world_check.mjs` (the Continue, the fast travel, the 787.7 m walk, draw calls at most 57; 605 holes, every one placed on the main thread; peak 1,112 MB), `stream_check.mjs --world --audio` (357 holes, all the main thread's; peak 719 MB). The plan's audio criterion is NOT MET on software WebGL and the strict forms stay NOT RUN (§8) | §6.4 |
| The Linux export: the soak headless | **PASS** - `Giantborn.x86_64`, 117,037,896 bytes, 0 errors in the export's log. The 120 s soak headless: exit 0, 0 errors, 0 warnings, `AUTOPILOT_RESULT` 28 keys (41 attacks, 33 hits resolved, 4 enemy kills, 2 fence breaks, 7,201 frames). Not run on the export: the assisted bot runs and the tour under Xvfb (the tour ran from source) | the same |
| The Windows export built (not launched) | **PARTIAL** (built, not launched) - `Giantborn.exe`, 150,621,496 bytes, and `Giantborn.console.exe`, 188,928 bytes; 0 errors in the export's log | the same |
| Version `0.13.0-m13`, the project's description, the launcher's notes | **PASS** - `b7129f3` (`config/version` and `config/description`; the launcher's masthead, pitch and "What it is", "New in 0.13.0-m13", what it is not yet, the next build; `build_web.sh`'s branches with -m13's 44 last) and `c239e85` (the BUILD line and "About 56 MB"); `e118922` (`test_giant_tooling`'s forced budgets named as 0.12's); `test_launcher_notes`, `test_web_presets`, `test_predeclared_m11` and `test_giant_web_presets` pass | `project.godot`, `web/launcher.html`; the notes' text in `docs/systems/P66.md` |
| The owner's approval of part three | **PASS** - approved after Gate C (§7); no game file changed after it but the version's strings | §7 |
| The tag `0.13.0-m13`, the play link republished, the push, the pull request to `main` and its merge | **NOT RUN** by the ship step: the lead's steps, after verifying this work | Plan §4.3 |

## 6. Test results and measurements

Every table and command behind this section is in [PERFORMANCE.md](PERFORMANCE.md), from "The people's assets
(P59)" to "The 0.13.0-m13 release". The system documents hold each package's own measurements.

### 6.1 The checks

Budgets (plan §1.7): the default tier at most 75 s by the script's rule (a warning without `--strict-times`), the
slow tier 8 minutes, the gate tier 50 minutes; `--people` 6 minutes and `--people-full` 45 minutes.

| Check | Suites | Checks | Failures | Default | Slow | Gate |
| --- | --- | --- | --- | --- | --- | --- |
| `0.12.0-m12`, the ship's final check (the base) | 361 | 78,409 | 0 | 66.3 s | 408.1 s | 1,142.4 s |
| P64c's final check (`46daf2e`, Gate C's code lane; `--giant --people`) | 378 | 80,458 | 0 | 71.9 s | 429.7 s | 1,710.4 s |
| The release's first final check (`6e4085b`) | 378 | 80,457 | 3 (`test_giant_tooling`, fixed in `e118922`) | 73.1 s | 455.1 s | 1,681.4 s |
| **The release's final check (`e118922`; `--build --slow --gate --giant --people --people-full --web-tools --require`; a quiet machine)** | **378** | **80,460** | **0** | **71.4 s** | **441.5 s** | **1,649.8 s** |

On a quiet machine the default tier read 71.4 s (within the script's 75 s), the slow tier 441.5 s within its 8 minutes, the gate tier 27.5 minutes within its 50; `--people-full`'s regeneration took 176 s of its 45 minutes. Part C added 17 suites and 2,051 checks to `0.12.0-m12`'s.

### 6.2 The Web pack

| | `0.12.0-m12` (the release) | **`0.13.0-m13`** |
| --- | --- | --- |
| The pack as shipped | 31,749,016 bytes, 30.28 MiB of 32 | **43,903,980 bytes, 41.87 MiB of 44** |
| Parts (at most 15,000,000 bytes) | 3 of 10,583,006 | **3 of 14,634,660** |
| `GIANT_SHARE` | 13,768,208 bytes, 13.13 MiB of 13.6, 184 files | **13,911,024 bytes, 13.27 MiB of 13.6**, 190 files |
| `PEOPLE_SHARE` | 0 | **11,794,708 bytes, 11.25 MiB of 12.0**, 117 files |
| Packed files | 3,012 | 3,165 (no test content; every record valid without `data/test`) |

Part C adds 11.59 MiB to the shipped pack, 11.25 of it the people's and creatures' and 0.13 the giant's (the rival
giants' garments). The page's download is 56,837,922 bytes, about 56.8 MB (44.7 at `0.12.0-m12`), within the
owner's "about 60"; the launcher's note says "About 56 MB" (the engine and the pack as shipped, 56.43 MB, as its
script rounds them).

### 6.3 The people and creatures against their budgets (plan §2.12)

| Budget | Measured | Verdict |
| --- | --- | --- |
| The pack (44 MiB at -m13), `PEOPLE_SHARE` (12.0 MiB), `GIANT_SHARE` (13.6 MiB) | 41.87, 11.25 and 13.27 (the release) | met |
| A formation of 40 in view at `low`: draw calls (250) | 46 with the giant (the release's Web build); the town 117 | met |
| People skinned at once (16) | 12 in the formation view; the cap holds (`test_people_render`, PEOPLE_STATS) | met |
| The people's CPU a frame, Web (2.5 ms) | 2.0 ms with the forty, 2.1 with the wolves (the release's Web build) | met |
| The same, native (0.6 ms) | about 1.3 ms here (P64; llvmpipe, a shared machine) | **not met here** |
| A formation of 40 at 30 m, primitives (95,000) | 48,934 in the release's Web view (P60: 48,111) | met |
| Shader stalls: a first frame at most 3 times the median | the first formation 1.03x, the first wolf 1.87x, the levels 0.84-1.98x; the creator after New Game 0.29x; the title's warm-up 43-76x by design | met but the title's warm-up, by design |
| The page's peak renderer memory (1.4 GB) | 665-1,215 MB in the six checks | met |
| The repository's growth (30 MB; the added CC0 targets 4 MB) | the tree 21.51 MB from `0.12.0-m12` to Gate C's merge (the generated people and creatures 16.44 MB, the targets 3.87 MB) | met |

### 6.4 The Chromium checks

One at a time with nothing else running (the 1-minute load at each start 0.6-6.2: the browser raises the load
itself): all six **OK** in their default forms, 0 console errors and 0 failed requests in every run, the renderer's
peak 665-1,215 MB. `people_check.mjs` ran on the `Web (test)` build (the release has no test levels), the other five
on the release build. The music holes (231, 605, 357) are the software renderer's starved main thread, as in every
record: the plan's audio criterion is NOT MET here. The details are in `PERFORMANCE.md`, "The 0.13.0-m13 release".

## 7. The owner's decisions and approvals

**Gate C and the approval** (plan §4.2, checkpoint C; `DECISIONS.md` §1.7): after Gate C the owner reviewed Part C's
candidate and **approved part three**, and decided:

7. **Ship part three as `0.13.0-m13`** - this release.

**Known and accepted with the approval**, stated here and in the launcher's notes where a player meets them: the
women share the men's face texture; the wolf's ears are bare cones; the horse has no saddle; and the rough spots of
§9 that Gate C left to later passes.

**After the release's checks**, the lead's steps: the tag `0.13.0-m13`, the play link republished from this
release's Web build (`builds/web/` in the ship step's worktree, §5.4), the push, the pull request to `main` and its
merge. This document does not record them.

**Open decisions of the owner's**: what follows M11 (no milestone is planned yet); the two of the M6-M9 handoff's §10
(a licence for the project and its generated assets; whether to commit the lossless audio masters).

## 8. NOT RUN: the owner's tasks, and what could not run here

**The owner's tasks** (plan §4.5), **NOT RUN** here:

1. **The people and creatures on your own screens**: a real GPU and a real browser, with the people sheet beside it.
2. **Ten minutes of play**: a formation fight, a town, a wolf pack and a boss, on desktop and in a browser.
3. **Frame times and first frames on real hardware**, with `node tools/web/people_check.mjs --strict` and
   `node tools/web/creator_check.mjs --strict` on a machine with a GPU (and the three strict audio checks of the
   M6-M9 handoff's §9); the people's native CPU against its 0.6 ms on the reference PC.
4. Still open from earlier handoffs: a real gamepad in the creator's grids, a licence for the project and its
   generated assets, the lossless audio masters, and `build_giant.py --verify` on a second machine.

**What could not run here**:

- Anything on a GPU: every frame time, stall ratio and music hole is a software renderer's.
- A real browser other than headless Chromium, and a phone; the Windows export launched (it is only built).
- A cross-version run with the older releases' builds (Part C changed no save or look record; the fixtures load).
- Nobody has played it: whether the people read as people to a person, and how a formation fight feels with
  realistic bodies, are judgments no check here makes.

## 9. Known bugs and limitations

From Gate C (`FOLLOWUPS.md`, "From the M13 gate review"), each with its owner there:

- **Accepted for this release by the owner**: the women share the men's face texture with reweighted targets; the
  wolf's ears are bare cones; the horse has no saddle (the rider sits on the housing).
- **The whelp intersects the Troll Matriarch during the throw's wind-up** (lifted through her arm and side).
- **The dead horse's legs are rigid from the front** (they roll over with the body).
- **A rank at the crowd level stands in one identical hold pose.**
- **Corpses vary by their turn and their weapon's lie only**: every corpse is the same spread-eagled pose.
- **The off hand on a haft is an open hand** (the pike, the staff, the lance), and **the brutes' sweep has no grip
  for the off hand** on a two-handed club.
- **The thrown soldier's get-up is the fall clip played back** (it reads as a rewind at 3 m).
- **The chop's and the brace's legs are the clips' stance** (no knee bend at the impact or in the brace).
- **The troll's and the ogre's heads show facets** at the brow and jaw at close range.
- **The horse's gallop is procedural** (a keyed flexion, not an authored clip).
- **A kilt at a heavy build can let the thigh through** (Harrok's preset was trimmed to clear it).
- **The Web check never times the first brute, boss or rider** (measured by hand at Gate C: 1.79x, 1.59x, 2.16x of
  the median frame, against 3x).
- **The giants' axes are built in code** and read as props beside the new bodies; the props and machines keep their
  low-poly meshes.
- **The Web checks' memory guard trips on a loaded machine** (about 3.1 GB of renderer memory with three other jobs
  running, on 0.12 and 0.13 alike): run them alone.
- **The people's native CPU** reads about 1.3 ms against 0.6 on llvmpipe here; the Web's is within its 2.5.
- Everything in the M12 handoff's §9, the M11 handoff's §9, the M10 handoff's §9 and the M6-M9 handoff's §8 that
  this part did not fix still holds (the wardrobe's rough spots, no legs in first person, the browser's grids
  showing names, the browser's memory under a starved CPU).

## 10. Next milestone

**`0.13.0-m13` finishes M11.** No later milestone is planned yet: the owner chooses what follows. Before it, or
beside it: the owner's tasks of §8 and the open rows of `FOLLOWUPS.md` with their owners (the asset lane's get-up
clip, corpse variants and left grip; the creature passes; the tools pass for the Web check's brutes, bosses and
riders).
