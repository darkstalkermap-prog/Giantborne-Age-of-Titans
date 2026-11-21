# M11 handoff, part two: more customization (`0.12.0-m12`)

Spec §16 lists what every milestone handoff must contain: changed files and a runnable project, the
exact engine version, launch and export instructions, controls, implemented versus deferred
features, test results with measured evidence, known bugs, and the next smallest milestone. This
document provides each for **Part B of `docs/plans/M11_PLAN.md`**, released as `0.12.0-m12` (the plan
ships M11 in three parts, each a release: decision 86). Part A is [M11_HANDOFF.md](M11_HANDOFF.md)
(`0.11.0-m11`, the giant refined); Part C (`0.13.0-m13`, realistic NPCs) will have a handoff of its own.
The earlier handoffs are [M10_HANDOFF.md](M10_HANDOFF.md), [M6_M9_HANDOFF.md](M6_M9_HANDOFF.md),
[M2_M5_HANDOFF.md](M2_M5_HANDOFF.md) and [M1_HANDOFF.md](M1_HANDOFF.md).

| Spec §16 item | Where |
| --- | --- |
| Changed files and a runnable project | §2 |
| The exact engine version | §1 |
| Launch and export instructions; controls | §3 (README §2, §3, §4.3, §6 and §7) |
| Implemented versus deferred features | §4 |
| Test results with measured evidence | §5 (Part B's rows, Gate B, the cross-version save run, the ship), §6 (the checks and the measurements) |
| Known bugs | §9 |
| The next smallest milestone | §10, after the owner's approval (§7) and tasks (§8) |

**In one paragraph.** The player dresses the giant piece by piece. The look's record went to `v` 2 with
ten garment slots and three accessory slots, dyes by material and per piece, two build sliders, six face
sliders and beads; every `0.10` and `0.11` look migrates to a record that draws exactly what it drew. The
wardrobe has 35 garments and armour pieces and 8 accessories, each a part loaded on demand and a shell
pushed out only as far as what is worn under it needs, with 12 outfits as starting points and 14 dyes and
5 metals; the catalogue grew to 12 hair styles, 10 beards, three bead sets, 28 tattoos over five regions,
8 war paints, 10 scars and 14 presets. The creator has eleven categories, option grids with pictures (names
in the browser), a name filter and material buttons, signed sliders, and row jumps for the pad. After the
part-two preview five look passes followed the owner's notes, and at checkpoint B the giant's body was
reproportioned at their request (legs x1.30, torso x0.85, a longer neck, narrower shoulders, a larger head,
smaller hands: 7.94 heads tall instead of 8.35), every stage's height and all gameplay data unchanged. One
gameplay change was made inside Part B and kept: the leash's contact rule (an enemy walking back to its
post that ends up pressed against the giant stops and waits after one second). The seeded soak is the same
as at `0.10.0-m10` and `0.11.0-m11`. Everything was measured in a Linux container without a GPU, a real
browser, a gamepad or a human player. **The owner approved part two at checkpoint B** (§7).

**The gate's result**: Gate B reviewed Part B's candidate (`47a0af6`, the W33look2 merge) through the
plan's lenses; one fix lane fixed or recorded its seven confirmed findings (`docs/systems/GATE_B.md`,
`DECISIONS.md` §3.6). The three later look lanes, the body's proportions and the creator's framings
merged after it, each with a full check with 0 failures; this release is their head (`2a91c8b`) with the
version, the launcher's notes, the screenshots and these documents (§5.5).

## 1. Engine, build and environment

- **Engine**: Godot 4.6.3-stable (`7d41c59c4`), the standard build, GDScript, the Compatibility
  renderer, Jolt, the fixed 60 Hz simulation. Unchanged since M9.
- **The giant's toolchain** (only to regenerate `assets/giant/`; never to build, export or play): as
  M11's part one left it - Python with `bpy` 5.3.0, numpy, scipy, Pillow and OpenEXR, pinned in
  `tools/giant/requirements.txt`, in a venv outside the worktree (`GIANT_VENV`, the bake cache
  `GIANT_CACHE`). `tools/giant/fixtures/m10_freeze.json` was taken again for the reproportioned body
  (checkpoint B's decision 4).
- **Where it ran**: a Linux container with 4 shared CPUs, no GPU (llvmpipe natively under Xvfb,
  SwiftShader in headless Chromium), no speakers, no gamepad. Every frame time here is a software
  renderer's and indicative only. This container is slower than Part A's: the default test tier reads
  75-83 s against the script's 75 s (a warning, not a failure; §6.1).
- **Version**: `0.12.0-m12`, set by the ship step (P58) with the project's description and the
  launcher's notes. `tools/build_web.sh` reads `-m12` and applies the 32 MiB budget and the giant's 13.6
  MiB share.

## 2. Changed files and the runnable project

Part B is the commits from the `0.11.0-m11` tag to the W33frame merge (`2a91c8b`): 112 commits (19
merges), 365 files changed, 43,710 lines added and 2,506 removed; then the ship step's commits (§5.5).

| Area | Files changed (lines added) | What |
| --- | --- | --- |
| `assets/giant/` | 156 (19,840) | `giant.glb` (the reproportioned body, the face keys, the tangent's sign in the colour's alpha), 69 part files in `parts/` (25 garments, 8 accessories, 9 hair and beard styles, 3 bead sets added), the clips, the cloth maps (mail, scale), the designs, the hair atlas, the manifest |
| `tools/` | 19 (6,152) | `tools/giant/`: `giant_garment.py` (`Wardrobe`, slots, layering), `giant_hair.py` (styles, beads), `designs.py`, `export_game.py` (the index v2, face keys, far levels), `giant_body.py` (`PROPORTIONS`), `far_lods.gd`, the freeze fixture; `character_sheet.gd` (the wardrobe sheet); `tools/web/creator_check.mjs` (grids, pictures, `--shader-log`) |
| `scripts/` | 14 (1,579) | `Appearance` at `v` 2 (`migrate`, `sanitize`, `to_look` by slot), `GiantLook` by slot (pushes, face keys, bead mask, the skip-unchanged plan), `GiantModel` (`apply_build`), `SaveSlots` and `CharacterState` (the migration note and its flag), the schemas, `EnemyActor` (the leash's contact rule), `TipMatching` (the cross poles on the new body), `CaptureM11` (part B), `UiProbe` |
| `ui/` | 10 (2,135) | `CreatorScreen`, `OptionRows`, `OptionGrid` (new), `ThumbnailCache` (new), `GiantPreview` (framings, `frame_on`), the shrine's Appearance tab (the clothing by slot) |
| `data/` | 29 (1,052) | `data/appearance/` (the garment, accessory, bead, build, face and metal sets; twelve outfits; fourteen presets at `v` 2), `data/tutorial/appearance_slots.json` |
| `scenes/`, `assets/shaders/` | 1 and 4 | `giant_model.tscn` regenerated; the skin, cloth, hair and shell shaders (the build push, the bead mask, the tangent's sign, metal and leather) |
| `tests/` | 113 (8,884) | The migration oracle and matrix, the wardrobe's layering and stack checks, the creator's grids and thumbnails, the catalogue's rendered checks, the look cache, the leash's wait, the far levels, the body's proportions |
| `docs/`, `web/` | 17 at the merge, and these | `docs/systems/P53.md`-`P57.md`, `W33look.md`-`W33look5.md`, `W33body.md`, `GATE_B.md`, `PERFORMANCE.md`, `FOLLOWUPS.md`, `DECISIONS.md`, `BALANCE_LOG.md`; with the ship step this handoff, `docs/systems/P58.md`, the README, `ARCHITECTURE.md` §25, `DECISIONS.md` §1.7, §1.8, §2.5, the screenshots in `docs/screenshots/m12/`, the version and the launcher's notes |

No data record of combat, the world or the quests changed. One gameplay script changed: `EnemyActor`'s
leash return (§5.1, lens 2). The project runs as before: README §2.

## 3. Launch, export and controls

As README §2 (run it), §3 (the controls, with the creator's rows: LT and RT jump five rows and turn a
grid's pages, the right stick's up and down zoom), §4.3 (the creator's categories), §6 (the M11 capture
tour's part B, `--scenario=capture_m11 --part=b --skin`, and the creator probe) and §7 (the exports and the
browser build). An export needs neither Blender nor the giant's venv. The launcher's download note reads
"About 44 MB" (the engine and the pack as shipped; the page with the loader, the worklets and the poster
is 44,682,958 bytes, about 44.7 MB).

## 4. Implemented versus deferred

### 4.1 Against Part B's gate rows (plan §0.3)

| Requirement | Built |
| --- | --- |
| Clothing by slot: ten garment slots and three accessory slots, each with "none"; 35 garments and armour pieces; no two shown garments intersect or z-fight in the idle, the walk and a heavy swing | Yes (P53, P54, the W33 look lanes): 35 garments in ten slots, 8 accessories in three; the layering check (`test_wardrobe_render`) and the gate's stack check (`test_wardrobe_stack_render`: 200 random slot looks in three poses from three sides, 3 px in patches at worst against a floor of 0.0005 of the giant, the positive control 413 px) pass on the release's head |
| The record at `v` 2; every `v` 1 record migrates to a look that shows exactly the garments, dyes and designs it showed before; a broken, unknown or future record never fails a load | Yes (P53): the M10 oracle against every preset, every option and 360 random records (`test_appearance_migration`, slow `test_appearance_migration_matrix`); **the cross-version run on real saves both ways** (§5.4). Two deliberate data changes draw differently from 0.11 for the same record: the reproportioned body under every look, and the war paint's chalk slightly warmer (`#dcd6c8` to `#cdc2a8`, a look pass) |
| Two build sliders that change the silhouette in the stage-1 rear view and move no joint by more than 1 mm; face sliders if the probe passes | Yes: brawn and girth (P53; `test_build_render`), the creator stopping them at 0.6; six face keys on the head, beards and bead sets (P56) |
| The target catalogue within the giant's share | Yes: nothing on §6.3's cut list was cut; the release ships the giant's files at 13.13 MiB of 13.6 |
| The creator stays usable: every option reachable with a pad in at most 4 moves, a filter for the keyboard, thumbnails, the layout whole at 1280x720, Undo over every new row | Yes, natively (P55, P57; at most 6 literal pad presses, 3.3 on average); **on the Web the grids show names, not pictures** (the read-back over the stall rule on SwiftShader; plan §2.7's rule). A real gamepad and a real browser on a GPU are the owner's (§8) |
| The giant at most 24 draw calls at `low` in the fullest slot look, a typical preset at most 14 | Yes (P57): the Huscarl 20, the Wanderer 9 in the Valley |

### 4.2 Deferred, and planned but not built

- **By the plan**: the realistic people, riders, rival giants, brutes and wolves (`0.13.0-m13`).
  Strand hair, motion capture and talking faces are out of reach in this engine configuration.
- **Planned and not done**: hair under a helm cut by a plane (the long styles are cut by length and the
  tail, the wild mane and four new styles are hidden under a helm); the creator's preview and thumbnails
  running the springs (a cloak there lies on the back as exported); a cowl for the hood; skirt rows on
  chains (a stride can bring the thighs through a skirt's front rows).
- **Done another way**: the index v2's fields first lived in the data (P53), then in the index (P54); the
  scars share the scar layers' channels by region (P56); on the Web the grids show names (P57).

## 5. The gate and the release

Legend: **PASS** = verified by running the game, the engine or the tools here. **PARTIAL** = verified
here with a part that only real hardware or a person can confirm, or with part of the requirement met.
**FAIL** = measured and not met. **NOT RUN** = needs hardware or people that are not available here.
A Result is the verdict on the release's code unless the row names another commit.

### 5.1 The lenses on Part B

| Lens | Result | Evidence |
| --- | --- | --- |
| 1. The owner's request ("more customization": clothing and armour piece by piece, more hair, beards, braids and beads, a larger creator) | **PASS** (the look is the owner's: lens 8) | §4.1; the wardrobe sheet and the creator at checkpoint B; the screenshots in `docs/screenshots/m12/` |
| 2. Gameplay unchanged but for the one kept change | **PASS** | The seeded 120 s soak's `AUTOPILOT_RESULT` is unchanged (41 attacks, 33 hits resolved, 4 enemy kills, 2 fence breaks, 7,201 frames, 0 errors) at every merge of Part B and on the release's final check (§5.5). The leash's contact rule (W32, `EnemyActor.LEASH_CONTACT_M` 0.05 m, `LEASH_CONTACT_WAY_S` 1 s) is a deliberate gameplay change kept at Gate B (`DECISIONS.md` §3.6, `BALANCE_LOG.md`); `test_leash_waits` and the riders' trap over four phases prove it. The body's reproportioning kept every capsule, reach band, grip range and the stride |
| 3. Animation quality | **PARTIAL** | The clips regenerated on the new body; `test_skinned_rig_motion` and `test_giant_motion_render` pass at their bounds (W33body lowered `TipMatching.CROSS_POLES` so the weapon arm's elbow stays within 0.15 of the middle). Capes and cloaks swing on the cape's chains; in the creator they do not move |
| 4. Saves and migration | **PASS** | §5.4: real saves of `0.10.0-m10` and `0.11.0-m11` continued on this build, and this build's saves continued on both older builds and back |
| 5. UI and controls | **PARTIAL** | The creator's suites pass (the grid, the screen, the controls, the thumbnails, the layout at five sizes); Gate B fixed typing in a grid, the grids' pictures and the picture cache. A real gamepad and a real browser are the owner's (§8) |
| 6. Web and performance | **PARTIAL** | The pack 30.28 MiB of 32 in three parts, `GIANT_SHARE` 13.13 of 13.6 (§6.2); the Chromium checks on the release build (§6.4); every figure a software renderer's. The skin's native CPU with secondary motion read 0.160-0.183 ms against 0.15 at P57 (not re-measured here) |
| 7. Provenance and determinism of the assets | **PASS** | `GIANT VERIFY OK` with every bake pass on the release's final check (§5.5); the freeze test on the re-taken fixture; every scene rebuilt with no diff |
| 8. The look | **PASS** by the owner's approval at checkpoint B, with the rough spots of §9 accepted | Five look passes followed the owner's notes; the body was reproportioned at their request |

### 5.2 Gate B's findings

Gate B reviewed `47a0af6` and confirmed two major and five minor findings; each was fixed with a test that fails
before it or recorded (`docs/systems/GATE_B.md`): the look's skip-unchanged cache drawing a re-shown piece with an
old build or push (major); the leash's contact rule recorded as a test fix (major: kept as a gameplay change); the
option grid showing another grid's pictures; typing a name in a grid; the shrine's line and the Colours row
ignoring a garment's own dye; the README's creator zoom; the unbounded picture cache.

### 5.3 Follow-ups deferred

`docs/plans/FOLLOWUPS.md` holds every open row with its owner, in "From the look record v2 (P53)" to "From the M12
gate review" and "From the 0.12.0-m12 release (P58)". The ones a player can meet: the rough spots of §9 (a later
look pass); the creator's preview without the springs (a motion pass); hair under a helm cut by length (a later
look pass); the skin's native CPU over 0.15 ms with the cloak's chains (a motion pass).

### 5.4 The cross-version save run (plan §3.11, lens 4)

Run by the ship step on 21 November 2026. **The older builds are the tags' own code** (`0.10.0-m10`, `0.11.0-m11`,
each `git archive` of its tag imported into a scratch folder) **run headless with the same engine**, not their
exported binaries. A scratch driver script (not in the repository) opens the game's own `main.tscn`, then either
starts a New Game as the creator's Begin does (`GameSession.start_new_world` or `start_new_valley` with a preset's
record) and keeps the first checkpoint's file, or presses Continue (`GameSession.continue_valley`) on a given save
with `--save-dir=`, waits for the level and the player, records the load message, the record in memory and the look
the player draws, takes a checkpoint and reads back the file that build wrote.

**The saves**: written by `0.10.0-m10` (a world New Game as the Wild Hunter, a Valley New Game as the Northern
Chieftain), by `0.11.0-m11` (the world as the Iron Veteran, the Valley as the Storm Herald), each with a `v` 1 look;
and by `0.12.0-m12` (the world as the Huscarl, the Valley as the Bronze Lord), each with a `v` 2 look. Every run:
exit 0, 0 errors and 0 warnings in its log.

| Run | Result |
| --- | --- |
| The four `0.10` and `0.11` saves Continued on `0.12.0-m12` | **PASS** - each loaded in its level, said "Your giant's clothing is now worn piece by piece; nothing was changed." once, held a `v` 2 record in memory, and its checkpoint wrote `build_version` `0.12.0-m12`, the look at `v` 2 and the flag `appearance.slots_seen`. **The look drawn is the one the older build drew**: the same garments (e.g. the Iron Veteran's tunic, jerkin, belt, bracers and boots), the cloth and leather dyes to the last digit on every cloth and leather piece, and the same values in all 19 other look fields (hair, beard, skin, eyes, tattoos, scars, mark, ...) as the same save Continued on its own build; the one difference is the war paint's chalk, retinted in the data by a look pass (`#dcd6c8` to `#cdc2a8`) |
| The `0.10` and `0.11` fixtures Continued on `0.12.0-m12` | **PASS** - `v2_appearance` (0.10): migrated with the note, its furs, bracers, belt and braies drawn; `v2_appearance_unknown_ids` (0.10): the four unknown ids reported and dropped, then the migration's note; `v2_appearance_broken` (0.10): "Your giant's look could not be read; the default look is used."; `v2_appearance_future` (0.11's imagined `v: 2` with a skin block): read as a broken version 2, the default look, never a failed load (recorded since P53); `v2_world_check_aldmere_shrine` (0.8) and `v1_pre_crown` (0.5): no look, none added, no note; `v2_appearance_v3_future` (a `v` 3): kept byte for byte through the checkpoint with `NOTE_FUTURE` |
| The two `0.12.0-m12` saves Continued on `0.11.0-m11`, the world save on `0.10.0-m10`, and `tests/fixtures/saves/v2_appearance_v2.json` on `0.11.0-m11` | **PASS** - each older build said "This giant's look was made by a newer version of the game; the default look is shown until you change it.", drew the default look (braies and belt) and **kept the `v` 2 record byte for byte** in memory and in the file its own checkpoint wrote (`build_version` `0.11.0-m11` / `0.10.0-m10`) |
| Those files, written by the older builds, Continued on `0.12.0-m12` again | **PASS** - the record equal to the one `0.12.0-m12` first wrote, no note, the Huscarl's ten pieces drawn again (iron helm, iron pauldrons, shirt, mail hauberk, iron vambraces, war belt, trousers, greaves, boots, long cloak) |

So a look made or changed in `0.12.0-m12` shows only in `0.12.0-m12` or later; an older build keeps it in the save
until the look is changed there. The launcher's notes and the README say so.

### 5.5 The ship (plan §3.11, as P52)

The ship step (P58, `docs/systems/P58.md`) on `pkg/P58`, cut from `2a91c8b` after the owner approved checkpoint B.

| Item | Result | Evidence |
| --- | --- | --- |
| The final check on the final code: every scene rebuilt with no diff, every tier, `--giant-full`, `--web-tools`, `--audio`, the soak, `--require` | TBD-CHECK | §6.1 |
| README, ARCHITECTURE and DECISIONS consolidated; this handoff | **PASS** | README.md (the introduction, §2, §4.3, §6, §7, §9, §10, §11), `docs/ARCHITECTURE.md` (the intro, §6, §22, §23.8, §25 new), `docs/DECISIONS.md` (§1.7 checkpoint B's approval, §1.8, §2.5), this document, `docs/PERFORMANCE.md` ("The 0.12.0-m12 release"), `docs/plans/FOLLOWUPS.md`; `tests/unit/test_ship_docs.gd` passes on them |
| Screenshots in `docs/screenshots/m12/` | **PASS** - 12 JPG of 72-98 KB at 1280x720, drawn by the game under Xvfb on llvmpipe: five of the creator on the game's wardrobe (the Clothing slots, the outfits' and the armour's grids with their pictures, the Colours rows, the Bronze Lord dressed from behind; `creator_probe.tscn --shots --wardrobe`) and seven of the M11 tour's part B (the Huscarl, the Bronze Lord, the Northern Chieftain, the Berserker, the fullest look walking and at stage 4, brawn at the creator's +0.6; `--part=b --skin`, 69 frames, complete, 0 errors and 0 warnings by the game's count) | `docs/screenshots/m12/` |
| The cross-version save run | **PASS** | §5.4 |
| The Web export within 32 MiB in three parts, `GIANT_SHARE` within 13.6, built with the same bytes | **PASS** - `tools/build_web.sh --version=0.12.0-m12` (the project's own version; no `--budget-mb`): `PCK_SIZE preset="Web" raw=33126020 gzip=23811762 shipped=31749016 shipped_mb=30.28 budget_mb=32 parts=3`, three parts of 10,583,006 / 10,583,006 / 10,583,004 bytes; `GIANT_SHARE giant_bytes=15120468 shipped=13768208 shipped_mib=13.13 files=184 cap_mb=13.6`; `PEOPLE_SHARE` 0; `PCK_SHA256 565ef0f10db1956fe9973b6a79e3951ce4673a82b493cdc800a0559d67278dc5` on three builds (the last two equal in every file, the first differing only in `play.html`'s BUILD line and note); 3,012 packed files, no test content, every record valid without `data/test`. The page's download 44,682,958 bytes | `PERFORMANCE.md`, "The 0.12.0-m12 release" |
| The Chromium checks on the release build | **PASS** in their default forms - all five **OK** on the release build: `creator_check.mjs` (2 misses reported, both the title's warm-up by design; **the creator's first frame after New Game 0.24x** the median, the outfits' grid 2.71x, the armour's 0.66x, the shrine's creator 0.93x; the skin with secondary motion 0.200-0.276 ms; one pointer-lock request inside Begin's gesture; 0 console errors), `world_start_check.mjs` (both starts through the creator, saves with `build_version` `0.12.0-m12` and a look), `audio_check.mjs` (264 holes, all the main thread's), `world_check.mjs` (the Continue, the fast travel, the 787.7 m walk, draw calls at most 63; 603 holes, every one placed on the main thread), `stream_check.mjs --world --audio` (397.5 m, 0 thrash, draw calls at most 60; 354 holes, all the main thread's). The plan's audio criterion is NOT MET on software WebGL and the strict forms stay NOT RUN (§8) | the same |
| The Linux export: the soak headless | **PASS** - `Giantborn.x86_64`, 105,875,936 bytes, 0 errors in the export's log. The 120 s soak headless: 0 errors, 0 warnings, `AUTOPILOT_RESULT` identical in all 28 keys to `0.11.0-m11`'s (41 attacks, 33 hits resolved, 4 enemy kills, 2 fence breaks, 7,201 frames). Not run on the export this time: the assisted Valley bot run and the tour under Xvfb (the tour's part B ran from source, `docs/screenshots/m12/`) | the same |
| The Windows export built (not launched) | **PARTIAL** (built, not launched) - `Giantborn.exe`, 139,459,536 bytes, and `Giantborn.console.exe`, 188,928 bytes; 0 errors in the export's log | the same |
| Version `0.12.0-m12`, the project's description, the launcher's notes | **PASS** - `2350dd1` (`config/version` and `config/description`; the launcher's masthead, pitch and categories, "New in 0.12.0-m12" with the leash's contact rule and the note that a look made in 0.12 shows only in 0.12 or later, what it is not yet, the next build) and `286e9aa` (the BUILD line and "About 44 MB"); `test_launcher_notes` and `test_web_presets` pass | `project.godot`, `web/launcher.html`; the notes' text in `docs/systems/P58.md` |
| The owner's approval of part two | **PASS** - approved at checkpoint B (§7); no game file changed after it but the version's strings | §7 |
| The tag `0.12.0-m12`, the play link republished, the pull request to `main` and its merge | **NOT RUN** by the ship step: the lead's steps, after verifying this work | Plan §4.3 |

## 6. Test results and measurements

Every table and command behind this section is in [PERFORMANCE.md](PERFORMANCE.md): "M11 W33: Web and
performance for the wardrobe (P57)" and "The 0.12.0-m12 release". The system documents hold each
package's own measurements.

### 6.1 The checks

Budgets (plan §1.7): the default tier at most 75 s by the script's rule (a warning without
`--strict-times`), the slow tier 8 minutes, the gate tier 50 minutes. This container runs the default tier
at 75-83 s; no release check used `--strict-times`.

TBD-CHECKS-TABLE

### 6.2 The Web pack

| | `0.11.0-m11` (the release) | P57 (W33) | **`0.12.0-m12`** |
| --- | --- | --- | --- |
| The pack as shipped | 24,579,820 bytes, 23.44 MiB of 26 | 31,385,032 bytes, 29.93 MiB of 32 | **31,749,016 bytes, 30.28 MiB of 32** |
| Parts (at most 15,000,000 bytes) | 2 of 12,289,910 | 3 of 10,461,678 | **3 of 10,583,006** (the last 10,583,004) |
| `GIANT_SHARE` | 6,726,120 bytes, 6.41 MiB of 7.6, 84 files | 13,405,180 bytes, 12.78 MiB of 13.6, 184 files | **13,768,208 bytes, 13.13 MiB of 13.6**, 184 files |
| `PEOPLE_SHARE` | 0 | 0 | 0 |

Part B adds 6.84 MiB to the shipped pack, 6.72 of it the giant's. The page's download is 44,682,958 bytes,
about 44.7 MB (37.5 at `0.11.0-m11`); the launcher's note says "About 44 MB" (the engine and the pack as
shipped, 44.28 MB).

### 6.3 The giant against its budgets (plan §2.12)

| Budget | Measured | Verdict |
| --- | --- | --- |
| The pack (32 MiB at -m12) and `GIANT_SHARE` (13.6 MiB) | 30.28 and 13.13 (the release) | met |
| The giant's draw calls at `low`, a typical preset (14) and the fullest look (24) | the Wanderer 9, the Huscarl 20 (P57) | met |
| Draw calls in the Valley's view at `low` (250) | 112 and 119 (P57) | met |
| The giant's mesh buffers in play (4.5 MB) | the Wanderer 1.90 MB, the fullest 2.66 (P57) | met |
| Texture memory, the giant (9 MB) | 4.85 MB at the web tier, 6.95 with the hi tier (P57) | met |
| The giant's primitives beyond 120 m (4,000) | met since W33look2's far levels (`test_giant_far_render`, gate) | met |
| A whole look applied (1 ms) | about 0.33 ms (`test_giant_preview`) | met |
| The skin's CPU with secondary motion, Web (0.45 ms) | 0.2485 ms after the Valley, 0.276 after the world, 0.200 with the shrine's two giants (the release build) | met |
| The same, native (0.15 ms) | 0.160-0.183 ms (P57, loads 1.3-5; not re-measured here) | **not met** |
| Shader stalls: each first frame at most 3 times the median | on the Web the creator after New Game 0.24x (3.59x at `0.11.0-m11`), a grid's first frame 2.71x at most, the shrine's creator 0.93x, the levels 0.43-1.54x; the title's warm-up 73-99x by design | met but the title's warm-up, by design |
| The page's peak renderer memory (1.4 GB) | 718-1,202 MB in the five checks | met |

### 6.4 The Chromium checks

On the release build (the second of the three identical builds), one after another with the machine otherwise
idle but for the checks themselves (loads 0.8 at the first start, 4.6-7.2 at the later ones): all five **OK** in
their default forms, 0 console errors and 0 failed requests in every run, the renderer's peak 718-1,202 MB. The
creator's first frame after New Game, `0.11.0-m11`'s accepted miss (3.59x), reads 0.24x since P57's warm-up; the
grids show names on the Web. `world_check.mjs`, which failed `0.11.0-m11`'s default form on one unplaced hole in 3 of
5 runs, passed its one run here with all 603 holes placed on the main thread. The music holes (264, 603, 354) are the
software renderer's starved main thread, as in every record: the plan's audio criterion is NOT MET here.

## 7. The owner's decisions and approvals

**Checkpoint B** (plan §4.2; `DECISIONS.md` §1.7): the owner reviewed Part B's candidate. At their
request five look passes followed (`docs/systems/W33look.md` ... `W33look5.md`) and the body was
reproportioned (decision 4: the M10 body freeze lifted for one lane, W33body; the creator's framings
followed in W33frame). **The owner approved part two**, and decided:

5. **Ship part two as `0.12.0-m12`** - this release.
6. **The shoulders stay at about 3.1 head widths** ("Keep as is"), not the brief's 2.6-2.9: drawing the
   shoulder joints in breaks the tested swings' tip matching.

**Known and accepted with the approval**, stated here and in the launcher's notes where a player meets
them: §9's rough spots; the browser's grids show names; only the giant changed.

**After the release's checks**, the lead's steps: the tag `0.12.0-m12`, the play link republished from
this release's Web build, the pull request to `main` and its merge. This document does not record them.

**Open decisions of the owner's**: the look of part three at its checkpoints (C1, C); the two of the M6-M9
handoff's §10 (a licence for the project and its generated assets; whether to commit the lossless audio
masters).

## 8. NOT RUN: the owner's tasks, and what could not run here

**The owner's tasks** (plan §4.5), **NOT RUN** here:

1. **The wardrobe on your own screens**: a real GPU and a real browser; the creator with
   `play.html?args=--creator-pictures=on` to see whether pictures in the grids are quick enough on a GPU.
2. **The creator with a real gamepad**: the row jumps (LT / RT), a grid's pages, the zoom on the right
   stick (the creator sheet, `docs/USABILITY_SCRIPT.md` §12).
3. **Ten minutes of play dressed in armour and a cloak**: every weapon family, a sprint, a stomp, first
   person, on desktop and in a browser.
4. **Frame times and first frames on real hardware**, with `node tools/web/creator_check.mjs --strict` on a
   machine with a GPU (and the three strict audio checks of the M6-M9 handoff's §9).
5. Still open from earlier handoffs: a licence for the project and its generated assets, the lossless
   audio masters, and `build_giant.py --verify` on a second machine.

**What could not run here**:

- Anything on a GPU: every frame time, stall ratio and music hole is a software renderer's; the Web's
  audio criterion has never been met in this container.
- A real browser other than headless Chromium, and a phone; the Windows export launched (it is only
  built); the exported `0.10.0-m10` and `0.11.0-m11` binaries (§5.4 ran their tags' code).
- Nobody has played it: whether the wardrobe reads as clothing to a person, and how the dressed giant
  sits in the low-poly world, are judgments no check here makes.

## 9. Known bugs and limitations

- **Capes and cloaks show two lumps over the upper back seen from behind**; **the fur cloak is boxy**.
  In the creator's preview and thumbnails a cloak lies on the back as exported (no springs there).
- **Card beards seen from the side break into blocks** (the trimmed beard and the chops most), and **the
  short beard reads greyish** at the default grey.
- **The crop shows a thin strip of scalp at the front** (its front edge one pixel above the scalp tint's
  hairline on the reshaped head: `test_hair_render` `KNOWN_MISSES`).
- **The tunic and the shirt, and the jerkin and the cuirass, look too alike.**
- **The boots' toes fold in places** (small dark specks at the toe bases from close up); leg wraps and
  greaves are plain tubes; the hood from behind is a bowl; the top knot is thin.
- **Hair under a helm is cut by length**: the warrior's tail, the wild mane, the top knot, the side-shaved
  top, the long loose hair and the circlet are hidden under a helm.
- **In the browser the creator's grids show names instead of pictures** (a picture's read-back takes
  0.7-3.9 s on a software renderer).
- **A look made or changed in `0.12.0-m12` shows only in `0.12.0-m12` or later**: `0.10` and `0.11` builds
  keep it in the save and draw the default look until it is changed there.
- **Only the giant changed**: the soldiers, villagers, beasts and the world are still the game's simple
  shapes; they come in `0.13.0-m13`.
- **The skin's native CPU with secondary motion** read 0.160-0.183 ms against 0.15 at P57 (the cloak's
  three chains add about 0.012 ms); the Web's is within its 0.45.
- **The default test tier** reads 75-83 s on this container against the script's 75 s (a warning).
- Everything in the M11 handoff's §9, the M10 handoff's §9 and the M6-M9 handoff's §8 that this part did
  not fix still holds (no legs in first person, a black shell beard against the sun, the browser's memory
  under a starved CPU, the bake's one-texel jitter).

## 10. Next milestone

**`0.13.0-m13`, M11's part three: realistic NPCs** (plan §3.12-§3.19): the people pipeline (P59, which
started beside this release), `PersonRig` and the crowd, mounts and the giants' gear, townsfolk, named
characters, riders and the rival giants, brutes and wolves, the Web tiers for people, the people look pass;
the pack's budget at 44 MiB with the people's 12 MiB share and the giant's 13.6 kept. Before it, or beside
it: the owner's tasks of §8.
