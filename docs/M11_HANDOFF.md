# M11 handoff, part one: the giant refined (`0.11.0-m11`)

Spec §16 lists what every milestone handoff must contain: changed files and a runnable project, the
exact engine version, launch and export instructions, controls, implemented versus deferred
features, test results with measured evidence, known bugs, and the next smallest milestone. This
document provides each for **Part A of `docs/plans/M11_PLAN.md`**, released as `0.11.0-m11` (the plan
ships M11 in three parts, each a release: decision 86). Parts B (`0.12.0-m12`, more customization) and
C (`0.13.0-m13`, realistic NPCs) will have handoffs of their own. The earlier handoffs are
[M10_HANDOFF.md](M10_HANDOFF.md) (the realistic giant and the creator), [M6_M9_HANDOFF.md](M6_M9_HANDOFF.md)
(the campaign), [M2_M5_HANDOFF.md](M2_M5_HANDOFF.md) and [M1_HANDOFF.md](M1_HANDOFF.md).

| Spec §16 item | Where |
| --- | --- |
| Changed files and a runnable project | §2 |
| The exact engine version | §1 |
| Launch and export instructions; controls | §3 (README §2, §3, §6 and §7) |
| Implemented versus deferred features | §4 |
| Test results with measured evidence | §5 (Gate A and Gate A2), §6 (the checks and the measurements) |
| Known bugs | §9 |
| The next smallest milestone | §10, after the owner's approval (§7) and tasks (§8) |

**In one paragraph.** The player's giant moves and looks more like a living body, and nothing that
plays changed. He grips each weapon through a closed fist and rests the free hand open; sprints with a
clip of his own; lifts and stamps a foot for the stomp; steps when he turns on the spot; lands on bent
knees, braces, roars; flinches away from the side of a hit; reaches with his shoulder and body when a
weapon is carried past the stage it fits. Hair, braids, beards and the cape hang on new bones and swing
on springs, then settle. The crop, stubble and the short beard are shells (layers of strands), braids
are round plaits with beads, the long styles have loose strands, a beard exists from behind; the skin
has a pre-integrated subsurface term and is warm in the world's sun; the eyes have a catch-light and
follow the camera and the lock target. In first person the weapon rests low in the lower right corner,
the body's shadow is on the ground, and the legs are not drawn. Under it the body pipeline was reopened
once (leaf bones, build weights, landmarks, parts loaded on demand, a shadow proxy) with M10's body and
clips proved bit-identical, and the Web tools' debts were paid (a streaming unpacker, reproducible
exports). The seeded soak's result is the same in all 28 keys from M10's release to this one. Everything
was measured in a Linux container without a GPU, a real browser, a gamepad or a human player. **The
owner approved part one at checkpoint A** and decided three things (§7): ship it as `0.11.0-m11`, a
native CPU budget of 0.15 ms for the giant, and the warmer skin.

**The gate's result**: Gate A reviewed the W30 merge through the plan's eight lenses; two fix lanes
(the look, then the motion) and their merge (`m11-gate-a`, `9f96bb7`), then a second fix round, Gate
A2 (`m11-gate-a2`, `d0db605`), on what the merge's own tour showed: ten findings fixed, the misses
recorded (§5). This release is `m11-gate-a2` with the version, the description, the launcher's notes,
the native budget's figure and these documents (§5.5).

## 1. Engine, build and environment

- **Engine**: Godot 4.6.3-stable (`7d41c59c4`), the standard build, GDScript, the Compatibility
  renderer, Jolt, the fixed 60 Hz simulation. Unchanged since M9.
- **The giant's toolchain** (only to regenerate `assets/giant/`; never to build, export or play): as
  M10 left it - Python 3.13.18 with `bpy` 5.3.0, numpy, scipy, Pillow and OpenEXR, pinned with their
  sha256 in `tools/giant/requirements.txt`, in a venv outside the worktree (`GIANT_VENV`, the bake
  cache `GIANT_CACHE`). The vendored CC0 subset grew by four MakeHuman targets (137 files).
- **Where it ran**: a Linux container with 4 shared CPUs, 16 GB, no GPU (llvmpipe natively under Xvfb,
  SwiftShader in headless Chromium), no speakers, no gamepad, shared with the next part's first package
  (P53) during the release. Every frame time here is a software renderer's and indicative only.
- **Version**: `0.11.0-m11`, set by the ship step (P52) with the project's description and the
  launcher's notes. `tools/build_web.sh` reads `-m11` and applies the 26 MiB budget and the giant's 7.6
  MiB share.

## 2. Changed files and the runnable project

Part A is the commits from the `0.10.0-m10` merge on `main` (`5ff50f0`) to `m11-gate-a2` (`d0db605`):
39 commits, 324 files changed, 23,308 lines added and 5,117 removed; then the ship step's commits
(§5.5).

| Area | Files changed (lines added) | What |
| --- | --- | --- |
| `assets/giant/` | 61 (2,239) | `giant.glb` (71 bones, the body, the eyes, the shadow proxy), 21 part files in `parts/`, `giant_clips.glb` (28 clips), the graded albedo, `tex/curvature.png`, `tex/skin_lut.png`, `shell_strands.png`, `cloth_metal.png`, the 256 px cloth maps, the manifest (38 files) |
| `tools/` | 36 (4,736) | `tools/giant/`: `freeze.py` and its fixture, `kit/giant_parts.py`, the kit's hair, skin, pack, clips and export changes, four vendored CC0 targets; `build_web.sh` (the staged budgets, `PEOPLE_SHARE`, `PCK_SHA256`, the empty export cache), `pck_files.py`, `normalize_imports.gd`, `scene_kit.gd`'s stable node ids; `tools/web/` (the checks' waits, the recorder's clock, `memory_probe.mjs`, their tests) |
| `scripts/` | 16 (2,776) | `SkinnedRig` (the new sources, the balanced gated tree, flinches, the eyes' look, the sway), `PoseBrainModifier` (the fist, the reach, the arms' limit), `SecondaryMotion` (new), `TipMatching`, `GiantModel` (parts, the proxy), `GiantLook` (shells, tones, the cloth's rim), `RigPaint` (the proxy's path), `CaptureM11` (new), `UiProbe`, the loading screen's warm-up |
| `assets/shaders/` | 7 (334) | `giant_shell.gdshader` (new), the skin's lookup, the hair's highlights, the eyes, the cloth, `giant_first_person.gdshaderinc` (the legs by region) |
| `scenes/` | 124 (4,516) | Every generated scene carries the builders' stable node ids (P49); `giant_model.tscn` with the new index |
| `tests/` | 68 (4,507) | New suites for the parts, the proxy, the motion, the springs, the skin in the world's light, reproducible exports, the M11 tour, the pre-declarations; headroom moves between the tiers |
| `ui/` | 3 (37) | The preview's Web pixel scale; the skin swatch shows the drawn colour |
| `docs/`, `web/` | 7 at the gate, and these | `docs/systems/P48.md`-`P51.md`, the plan, `PERFORMANCE.md`, `FOLLOWUPS.md`; the launcher's streaming unpacker; with the ship step this handoff, `docs/systems/P52.md`, the README, `ARCHITECTURE.md` §23-§24, `DECISIONS.md` §1.6, §1.7, §2.4, §3.5, §4.4, `USABILITY_SCRIPT.md` §12.2, the screenshots in `docs/screenshots/m11/`, the version and the launcher's notes |

No data record, no script under `scripts/combat`, `ai`, `world` or `quests`, and no gameplay node of
the giant's scene changed. The project runs as before: README §2.

## 3. Launch, export and controls

As README §2 (run it), §3 (the controls: unchanged; the sprint is still Shift held while moving), §6
(the M11 capture tour, `--scenario=capture_m11 --part=a --skin`) and §7 (the exports and the browser
build). An export needs neither Blender nor the giant's venv. The launcher unpacks the pack as it
downloads (one stream), and its download note reads about 38 MB.

## 4. Implemented versus deferred

### 4.1 Against Part A's gate rows (plan §0.3)

| Requirement | Built |
| --- | --- |
| The weapon through the closed fist and the off hand not drooping in every generic pose; the stomp lifts and plants a leg; a sprint clip distinct from the run; turning on the spot steps; a hit from each of four sides flinches; no pose pops between the legs' sources | Yes (P48's clips, P50's rig). The handle lies on the fist's line in every generic pose (0.0000 x k), the fist's axis at most 29 degrees off it; the stomp lifts the foot 0.86 m and plants it within 0.007 m; the flinches move the head 0.31-0.44 m away from the hit (Gate A2); the legs' largest change between two frames 23.5 degrees, the arms' 20.0 since Gate A. Inside a tested swing the hand can still turn 144 degrees between two frames (§9) |
| Hair, beard, braids and the cape hang and swing on bones, never pass through the shoulders at a full head turn, and come to rest | Yes (P48's bones, P50's springs and limits): the braids reach their 38-degree limit on a sprint, the cape lifts 40.6 degrees and is back within 2 degrees 0.25 s after he stops; colliders on the head and chest. The cape swings as one board (no cross links: §9) |
| A weapon carried past its fit stage within 1.0 capsule radius and 15 degrees at every stage, or the miss recorded as a limit of honest reach | Partly: the shoulder, spine and pelvis reach toward the tip (`TipMatching.match_swing_reach`), within their limits; where they do not suffice the nearest reach is the recorded limit (`docs/systems/P50.md`) |
| Hair beyond flat cards: volume shading and a two-lobe highlight; shells for the crop, stubble and the short beard; braids as geometry; loose strands; a beard that exists from behind | Yes (P51; the shells' grey and light at Gate A2). A black shell beard face-on against the sun stays dark (accepted, §7) |
| The default skin's lit chest within 12/255 of the approved render under the creator's light; a subsurface term; a swatch showing the drawn colour | The subsurface term and the swatch: yes. The chest: **26/255** off since Gate A, which made the skin right in the world's sun; **the owner accepted it** (§7, decision 3) |
| Eyes with a cornea highlight, a limbal ring, a lid shadow and a look direction; every scar and mark above its view floor in the stage-1 rear or first-person view | The eyes: yes, and the rig turns them (Gate A). Scars and marks: the ones that can be in either view are above their floors; the face's, the chest's and the left hand's cannot be and are listed (`test_hair_render.NOT_IN_EITHER_VIEW`); the granite veins fell below in first person when the body's shadow came back (§9) |
| Meshes on demand with the fullest look's buffers at most 4.5 MB; shadows one draw call a cascade; draw calls at `medium` at most 330 (the Valley walk) and 620 (the stress arena) | Buffers 2.60 MB (fullest), shadows one draw a cascade: yes. **Draw calls at `medium` 379 and 642: missed** (from 395 and 674; accepted until part three, §7) |
| The creator's preview on the Web sharper within the stall rule, or the reason; a command-line `--continue` warmed up | The `--continue` warm-up: yes (P49). The creator's first frame on the Web is **3.3 times** the median frame (the rule: 3), as at W29 and W30 (§5.2) |
| Nothing that plays changes; the tools' open rows closed or re-recorded | Yes: the soak identical in all 28 keys at every merge and on the release's export; `test_giant_determinism` 57 checks, 0 failures; the M10 handoff's tool rows closed by P49 or re-recorded (`FOLLOWUPS.md`, "From P49") |

### 4.2 Deferred, and planned but not built

- **By the plan** (§0.5, the parts): clothing by slot, the build and face sliders, more styles and
  designs (`0.12.0-m12`); realistic people, mounts and beasts (`0.13.0-m13`). Strand hair, motion
  capture and talking faces are out of reach in this engine configuration.
- **From P50's cut list, not built**: the head's own look (the eyes turn, the head does not), foot
  placement on slopes, a growth tween.
- **Planned and not done**: the skirt's waist fade in first person (Gate A2 stops drawing the legs
  instead), `carry_two_hand` (the tree is carried one-handed), the creator's preview without the springs
  and the eyes' look (P55), a coarser last LOD for the hair cards, lashes and fuller brows as geometry.
- **Done another way**: the curvature is a map of its own, not in the mask map's alpha
  (`DECISIONS.md` §2.4).

## 5. The gate

Gate A ran on the W30 merge (`wave-30`, `84468ea`), 18-19 November 2026, through the plan's eight
lenses (plan §4.1). The findings went to two fix lanes in turn, each on its own worktree and one at a
time on the generated assets: the look lane (the skin in the world's light, the first-person shadow,
the braies) and the motion lane (the giant's CPU, the arms' pop, the eyes); their merge, `m11-gate-a`
(`9f96bb7`), reviewed the part's code again (no confirmed defect needing a fix), ran the tours and
built the preview for checkpoint A. The merge's own tour showed four more things, which a second fix
round, Gate A2, fixed on `m11-gate-a2` (`d0db605`): the shell hair in the world's light, the flinches,
first person's rest and its hips.

Legend: **PASS** = verified by running the game, the engine or the tools here. **PARTIAL** = verified
here with a part that only real hardware or a person can confirm, or with part of the requirement
met. **FAIL** = measured and not met. **NOT RUN** = needs hardware or people that are not available
here, or was not run on this code. A Result is the verdict on `m11-gate-a2` unless the row names
another commit; where the review found a failure that a lane then fixed, the row says both.

### 5.1 The gate table (plan §4.1), with Gate A2's changes

| Lens | Result | Evidence |
| --- | --- | --- |
| 1. The owner's request ("refine and improve the Giant movements and graphics") | **PASS** (the look is the owner's: lens 8) | Every motion and graphics item of plan §0.3 in the M11 tour (163 frames from the side, the front and three-quarters) and in play: the grips, the stomp, the sprint, the turns, the landing, the brace, the roar, the flinches, secondary motion on every chain, the reach past fit, first person, hair, skin, eyes, scars and cloth. Gate A2 made two of them readable that the merge's tour did not (the flinches, first person at rest) |
| 2. Gameplay unchanged | **PASS** | The seeded 120 s soak's `AUTOPILOT_RESULT` is the same in all 28 keys (41 attacks, 33 hits resolved, 4 enemy kills, 2 fence breaks, 7,201 frames, 0 errors, 0 warnings) at the W29 merge, the W30 merge, both Gate A checks, Gate A2's checks and this release (§5.5); with `--skin --skin-stats` too (SKIN_STATS 7 flinches, 7,203 secondary-motion frames: the positive controls). `test_giant_determinism` (gate) 57 checks, 0 failures. The code rules (`test_skin_rules`, `test_appearance_rules`) pass. No data record and no simulation script changed. The release's Linux export plays the assisted novice Valley run to the tenth of a second of `0.9.0-m9`'s and `0.10.0-m10`'s (452.4 s). Not in the gate's records: the world bot's smoke run and the Valley twin compared against a `0.10.0-m10` worktree; the gate tier's `test_world_bot_smoke` passes |
| 3. Animation quality | **PARTIAL** | `test_giant_motion_render` (each source without a pop, the stomp's lift and plant, the flinches, the grips, the reach, the springs' swing, rest and limits), `test_skinned_rig`, `test_tip_matching`, `test_first_person_shoulders`, `test_capture_m11_tour`, 0 failures. The review's frames: right - the sprint reads as a run of its own, the stomp lifted and planted, the block with the club across, the turns, stage 6, the braids hang and swing as round tubes. Fixed at Gate A: the arms popped up to 81 degrees between two frames on a block (now 20.0). Fixed at Gate A2: the flinches read as one frame and the side ones leaned toward the hit (now 0.31-0.44 m away from it); first person at rest showed the club upright over a third of the view (now low in the corner, 0.058 of the frame); looking down showed the hips' caps (now no legs drawn). What keeps it PARTIAL: the weapon hand turns up to 144 degrees between two frames inside a tested swing; the cape swings as one board; the arms trail a fast change by about 0.1 s; the two-handed carry is not built; the tour has no lock-on beat (the eyes' turn to a lock was verified by `test_skinned_rig`'s numbers) |
| 4. Saves and migration | **PASS** | Nothing in the save or the look's record changed. A real save written by `0.10.0-m10` (a scratch worktree, the Valley, 150 s) with the 0.10 fixture's look (now shells) continued on the merge with `--skin`: 0 errors, the look shown, the save written again with the look byte-identical. The save suites pass |
| 5. UI and controls | **PARTIAL** | The creator is unchanged but for the skin swatches, which show the drawn tone (`GiantLook.drawn_tone`, within 30/255 since Gate A); the preview on the Web keeps the canvas's pixel scale (P49 measured the larger one). The creator's suites pass. A real gamepad and a real browser are the owner's (§8) |
| 6. Web and performance | **PARTIAL** | The pack 23.44 MiB of 26 in two parts, `GIANT_SHARE` 6.41 of 7.6; the five Chromium checks OK in their default forms at Gate A (the audio criterion NOT MET on software WebGL, as in every record), four of them on this release's build, where `world_check.mjs` failed twice on one unplaced hole under another lane's load (§5.5); draw calls at `low` at most 152 and 153 (250); the giant's mesh buffers 2.60 MB (4.5); the skin's CPU 0.230-0.248 ms on the Web (0.45) and 0.136-0.144 ms natively (0.12 then, **missed**; 0.15 since the owner's decision, met). What keeps it PARTIAL: draw calls at `medium` (379 and 642 against 330 and 620: **FAIL**, accepted), the creator's first frame after New Game on the Web 3.3 times the median (**FAIL**, accepted), every figure a software renderer's |
| 7. Provenance and determinism of the assets | **PASS** | `GIANT VERIFY OK: 38 files regenerated bit-exact` at every Gate A and Gate A2 check (`--giant`), and with every bake pass on the release's final check (§5.5); the freeze test (the body, its 53 bones and M10's clips bit-identical to `0.10.0-m10`); the four added targets audited against the wheel (137 files); every scene rebuilt with no diff (`--build`); `test_ship_docs` passes |
| 8. The look | **PASS** by the owner's approval at checkpoint A, with two accepted deviations | Found at the review and fixed at Gate A: the skin chalk-white in the sun and grey-mauve in shade (now warm: the default's near-white share 0.88-0.90 to 0.00), no body shadow in first person, bright slivers on the braies. Found in the merge's tour and fixed at Gate A2: the Storm Herald's short beard a flat black mass, the Iron Veteran's greying crop near black with specks (`test_skin_world_render`, 55 checks on the shells). Accepted by the owner: the creator-light chest 26/255 off the studio render approved for 0.10; a black shell beard face-on against the sun dark |

### 5.2 Inside the lenses: what is not PASS

| Item | Result | Evidence |
| --- | --- | --- |
| Draw calls at `medium` (lens 6) | **FAIL**, accepted until part three | p50 / p95 / p99 / max at 640x360, llvmpipe: the Valley walk 213 / 307 / 349 / **379** (330), the stress arena 312 / 551 / 617 / **642** (620); 395 and 674 at `0.10.0-m10`. The giant is one shadow draw a cascade now; the rest is the static world (up to 221 at `medium`) and the box NPCs, which part three replaces (P60). The Web runs `low` (at most 152 and 153: met) |
| The creator's first frame after New Game on the Web (lens 6) | **FAIL**, accepted | 3.3 times the median frame at Gate A (506.8 against 153.8 ms; 3.28 at W30), against 3; 3.59 on this release's build with the load rising from 2.8 to 5.3 (§5.5). The shrine's creator 2.21; the title's warm-up frame 30-75 times by design (behind "Preparing...") |
| The giant's native CPU with secondary motion (lens 6) | **FAIL** against 0.12 at the gate, **PASS** against the owner's 0.15 | 0.136-0.143 ms (Gate A, four runs), 0.143-0.144 (Gate A2, three runs); 0.291 at the W30 merge before Gate A's changes |
| The default skin against the approved studio render (lens 8) | **FAIL** against 12/255, accepted | (220, 160, 131) against (198, 170, 157) in the creator's light: 26/255 at most a channel (P51 had 5/255 before Gate A traded it for the world's light) |
| The weapon hand inside a tested swing (lens 3) | **PARTIAL** | Up to 144 degrees between two frames in a light's ACTIVE window (as at W30); the arms' limit does not apply there (it would move the fist off the tested segment) |
| Scars and marks in the stage-1 rear and first-person views (lens 8) | **PARTIAL** | The granite veins 13 px in first person (90 the floor; 135 before the shadow came back); the forearm slash and the back lash read 0.8-0.9 of M10's in their framings; the face's, the chest's and the left hand's designs cannot be in either view |
| First person (lens 3) | **PASS** with accepted limits | The weapon in the lower right at rest at stages 1 and 6 (`test_first_person_shoulders`); no caps looking down (0.000-0.003 of the block where they were); the body's shadow (0.041 of the frame). No legs or feet are drawn; stage 6's unreforged sword is a sliver at rest (0.006 of the frame) |
| The slow test tier (plan §1.7) | **PASS**, near its limit | 375.3-395.3 s at the Gate A and Gate A2 checks against 400 (the script's own rule: 8 minutes); P53 moves headroom in W31 (§6.1 has this release's reading) |
| The owner's look and play (lens 8, plan §4.5) | **PASS** for the approval; the hands-on tasks **NOT RUN** here | §7, §8 |

### 5.3 Findings fixed at the gate

`DECISIONS.md` §3.5 lists each with its fix; the detail is in `docs/systems/P51.md` ("Gate A", "Gate
A2"), `docs/systems/P50.md` ("Gate A", "Gate A2") and `docs/PERFORMANCE.md` ("M11 Gate A"). In short:

| Round | Finding | Fixed by |
| --- | --- | --- |
| Gate A, look | The skin chalk-white in the sun, grey-mauve in shade, ragged at the terminator | A per-channel wrap in the subsurface lookup, the albedo's grade eased, tones re-saturated by their distance from the default (`test_skin_world_render`, new) |
| Gate A, look | No body shadow in first person | The shadow proxy on the limbs' layer (the renderer culls casters by the camera's mask) |
| Gate A, look | Bright slivers on the braies in the sun | No rim light on weave and leather |
| Gate A, motion | The giant's CPU 0.29 ms natively | A balanced, gated blend tree, the sway held by the rig, fixed parameter slots: 0.136-0.143 ms, the picture unchanged |
| Gate A, motion | The arms popped on a block | A per-joint rate limit outside tested swings: 81 to 20 degrees a frame |
| Gate A, motion | The eyes did not move | The rig writes the eyes' `look` toward the lock or along the camera |
| Gate A2 | The short beard a black mass, the greying crop near black with specks | The shells take the grey and the light as the cards do, with a sky sheen |
| Gate A2 | The flinches unreadable, the side ones toward the hit | The side clips' sign fixed; added at up to 2.5 times over 0.5 s |
| Gate A2 | The club upright over a third of the first-person view at rest | `fp_rest`'s forearm turned 75 degrees: the weapon low in the corner |
| Gate A2 | The hips' caps between the arms looking down in first person | First person discards the pelvis, legs, feet and caps by body region |

### 5.4 Follow-ups deferred

`docs/plans/FOLLOWUPS.md` holds every open row with its owner, in "From P49" to "From the Gate A merge
(M11)" and "From the 0.11.0-m11 release (P52)". The ones a player can meet, and their owners: the
weapon hand's turn inside a tested swing (a later motion pass, P62); the cape as one board and the
springs' tuning in the index (P54); the creator's preview without the eyes' look or the springs (P55);
the granite veins and two scars weaker in their views (P55, P56); the red band at the shoulders'
terminator and the pale tone's cool shade (a later look pass); lashes and brows (P56); a coarser hair
LOD (P56); the draw calls at `medium` (P60); the creator's first frame on the Web (P57). The native CPU
budget and the studio match are closed by the owner's decisions (§7).

### 5.5 The Ship gate (plan §3.5, §4.3)

The ship step (P52, `docs/systems/P52.md`) on `pkg/P52`, cut from `m11-gate-a2`: the version, the launcher's notes,
the owner's budget figure and these documents on the approved code, then the builds, the runs and the final check.
Every row's commands and figures are in `PERFORMANCE.md`, "The 0.11.0-m11 release".

| Item | Result | Evidence |
| --- | --- | --- |
| The final check on the final code: every scene rebuilt with no diff, every tier, `--giant-full`, `--audio`, the soak, `--require --strict-times` | **Pending** at this commit: the final check runs on it, and its numbers are recorded in the next commit | §6.1 |
| README, ARCHITECTURE and DECISIONS consolidated; this handoff; the motion sheet | **PASS** | README.md (part one in the introduction, §2, §4.3, §6, §7, §9, §10, §11), `docs/ARCHITECTURE.md` (§23 revised, §24 new; the intro, §14, §16, §22), `docs/DECISIONS.md` §1.6, §1.7, §2.4, §3.5, §4.4, `docs/USABILITY_SCRIPT.md` §12.2, this document; `tests/unit/test_ship_docs.gd` passes on them |
| Screenshots in `docs/screenshots/m11/` | **PASS** - 10 JPG of 76-102 KB at 1280x720, frames of the M11 tour played by the release's Linux export under Xvfb (the Compatibility renderer on llvmpipe, `--skin`): the sprint, the stomp lifted and planted, a turn on the spot, the club's heavy in the fist, the roar, a flinch from the left, stage 6, first person at rest and looking down | `docs/screenshots/m11/` |
| The Linux export: the soak and an assisted bot run headless; once under Xvfb with `--skin` (the M11 tour, 0 errors) | **PASS** - `Giantborn.x86_64`, 99,243,280 bytes, 0 errors in the export's log. The 120 s soak: 0 errors, 0 warnings, `AUTOPILOT_RESULT` identical in all 28 keys to the baseline (41 attacks, 33 hits resolved, 4 enemy kills, 2 fence breaks, 7,201 frames). The assisted novice Valley run (intimidate, seed 1): completed in 452.4 s simulated, 0 deaths, 0 invariant failures, 0 errors, 0 warnings, as `0.10.0-m10` to the tenth of a second. Under Xvfb with `--skin`: the M11 capture tour complete, 163 frames, 0 errors, 0 warnings | `PERFORMANCE.md`, "The 0.11.0-m11 release" |
| The Windows export built (not launched) | **PARTIAL** (built, not launched) - `Giantborn.exe`, 132,826,880 bytes, and `Giantborn.console.exe`, 188,928 bytes; 0 errors in the export's log | the same |
| The Web export within 26 MiB in parts of at most 15 MB, `GIANT_SHARE` within 7.6, built twice with the same bytes | **PASS** - `tools/build_web.sh` with no `--budget-mb`: `PCK_SIZE preset="Web" raw=26739748 gzip=18434864 shipped=24579820 shipped_mb=23.44 budget_mb=26 parts=2`, two parts of 12,289,910 bytes; `GIANT_SHARE giant_bytes=8872395 shipped=6726120 shipped_mib=6.41 files=84 cap_mb=7.6`; `PCK_SHA256 0f61a02bdec5fb840854e2f46cd49337f601cfe491b87cb13ad881e10e65a21e` on three builds, the last two equal in every file; 2,895 packed files, no test content. The page's download 37,513,762 bytes, about 37.5 MB | the same |
| The five Chromium checks on the release build | **PARTIAL** - four **OK** in their default forms: `creator_check.mjs` (3 misses reported: the creator's first frame after New Game **3.59x** the median, the title's warm-up twice by design; the Valley's first frame 1.21x, Continue 0.46x, the shrine's creator 2.18x; the skin with secondary motion 0.2005-0.279 ms; one pointer-lock request inside Begin's gesture; 0 console errors), `world_start_check.mjs` (both starts through the creator, saves with version `0.11.0-m11` and a look), `audio_check.mjs` (242 holes, all the main thread's), `stream_check.mjs --world --audio` (397.5 m, 0 thrash, draw calls at most 60; 357 holes, all the main thread's). `world_check.mjs` **FAILED** its default form twice, each time on one hole of about 600 not placed on the main thread, with the other lane loading the machine to 7.7 and 8.4 by each run's end; its Continue, fast travel, walk (787.7 m, 0 stuck), draw calls (at most 63), memory and console were as at Gate A, where it passed on the same pack but for the version. The plan's audio criterion is NOT MET on software WebGL and the strict forms stay NOT RUN (§8) | `PERFORMANCE.md`, "The 0.11.0-m11 release" (both runs); FOLLOWUPS |
| Version `0.11.0-m11`, the project's description, the launcher's notes | **PASS** - `117b713` (`config/version` and `config/description`; the launcher's masthead, "New in 0.11.0-m11", what it is not yet, the next build, "About 38 MB" and the release build's BUILD line); `test_launcher_notes` passes | `project.godot`, `web/launcher.html`; the notes' text in `docs/systems/P52.md` |
| The owner's budget decision applied | **PASS** - `d37228c`: plan §2.12's native row 0.15 ms and `UiProbe`'s comment; no test or tool encoded the figure | `DECISIONS.md` §1.7 |
| The owner's approval of part one | **PASS** - approved at checkpoint A on the Gate A2 candidate, with the three decisions of §7; no game file changed after it but the version's strings and that comment | §7 |
| The tag `0.11.0-m11`, the play link republished, the pull request to `main` and its merge | **NOT RUN** by the ship step: the lead's steps, after verifying this work | Plan §4.3 |

## 6. Test results and measurements

Every table and command behind this section is in [PERFORMANCE.md](PERFORMANCE.md): "M11 W29: the
Web, tools and performance debts (P49)", "M11 W29: the merged measurements", "M11 W30: the giant's
motion (P50)", "M11 W30: the merged measurements", "M11 Gate A: the merged measurements" and "The
0.11.0-m11 release". The system documents hold each package's own measurements.

### 6.1 The checks

Budgets (plan §1.7, §2.12): the default tier at most 72 s at the part's end on a quiet machine (the
script's own rule: 75 s), the slow tier at most 400 s (the script's: 8 minutes), the gate tier 50
minutes.

| Check | Suites | Checks | Failures | Default | Slow | Gate |
| --- | --- | --- | --- | --- | --- | --- |
| `0.10.0-m10`, the ship's final check (the base) | 330 | 56,119 | 0 | 66.2 s | 341.8 s | 844.6 s |
| The W30 merge, check 2 (`--slow --gate --giant --web-tools`) | 343 | 57,520 | 0 | 60.0 s | 361.0 s | 794.6 s |
| The Gate A merge, check 1 (`--build --slow --gate --giant --web-tools`) | 344 | 57,578 | 0 | 73.5 s | 375.3 s | 885.2 s |
| The Gate A merge, check 2 (default tier, quiet) | 227 | 43,791 | 0 | 62.8 s | - | - |
| Gate A2, its lane's check (`--slow --giant`) | 310 | 54,412 | 0 | 65.1 s | 395.3 s | - |
| Gate A2, merged (`--build --slow --gate --giant --web-tools`) | 344 | 57,657 | 0 | 65.2 s | 384.6 s | 873.7 s |

### 6.2 The Web pack

| | `0.10.0-m10` (the release) | The W30 merge | The Gate A merge | **`0.11.0-m11`** |
| --- | --- | --- | --- | --- |
| The pack as shipped | 23,586,472 bytes, 22.49 MiB of 26 | 23.42 MiB | 24,576,908 bytes, 23.44 MiB | **24,579,820 bytes, 23.44 MiB of 26** |
| Parts (at most 15,000,000 bytes) | 2 of 11,793,236 | 2 of 12,281,288 | 2 | **2 of 12,289,910** |
| `GIANT_SHARE` | 5,845,364 bytes, 5.57 MiB of 7.6, 33 files | 6.42 MiB, 84 files | 6,724,464 bytes, 6.41 MiB | **6,726,120 bytes, 6.41 MiB of 7.6**, 84 files |

Part A adds 0.95 MiB to the shipped pack, 0.84 of it the giant's (plan §2.12's Part A arithmetic: about
1.5); the plan's "about 24.0" for `0.11.0-m11` is met with 23.44. The page's download is about 37.5 MB
(36.5 at `0.10.0-m10`; the plan's "at most 40.2").

### 6.3 The giant against its budgets (plan §2.12)

| Budget | Measured | Verdict |
| --- | --- | --- |
| Draw calls in every measured view at `low` (at most 250) | the Valley walk max 152, the stress arena max 153 (Gate A) | met |
| Draw calls at `medium` (the Valley walk 330, the stress arena 620) | 379 and 642 (Gate A; the W30 and W29 merges' counts exactly) | missed, accepted (§7) |
| The giant's CPU a frame with secondary motion, native (0.15 ms since checkpoint A; 0.12 before) | 0.136-0.143 ms (Gate A), 0.143-0.144 (Gate A2) | met (missed against 0.12) |
| The same, Web (0.45 ms) | 0.230-0.248 ms (Gate A); 0.2005-0.279 ms on the release build | met |
| The giant's mesh buffers in play (4.5 MB) | the default look 2.15 MB, the fullest 2.60, every part 5.28 | met |
| Shader stalls: each first frame at most 3 times the median | natively within it but the title's warm-up; on the Web the creator after New Game 3.3x (Gate A), the shrine's creator 2.21x | missed for the creator after New Game, accepted (§7) |
| The page's peak renderer memory (1.4 GB) | 0.69-1.16 GB in the five checks (Gate A) | met |
| The pack (26 MiB) and `GIANT_SHARE` (7.6 MiB) | 23.44 and 6.41 | met |
| Test tiers: default at most 72 s, slow at most 400 s, gate under 50 minutes | §6.1 | met; the slow tier near its limit |
| `--giant` at most 6 minutes, `--giant-full` 25 | 74-76 s (Gate A2, `--skip-bake`); **Pending** at this commit: the final check runs on it, and its numbers are recorded in the next commit | met |

### 6.4 The Chromium checks

At the Gate A merge (each started at a 1-minute load under 3; 0 console errors and 0 failed requests in
every run): `creator_check.mjs` OK, 3 misses reported (the creator after New Game 3.3x, the title's
warm-up frames twice by design); `world_start_check.mjs` OK; `audio_check.mjs` OK, the criterion NOT MET
(264 holes, all on the main thread); `world_check.mjs` OK, NOT MET (604 holes); `stream_check.mjs
--world --audio` OK, NOT MET (340 holes). On this release's build (§5.5): `creator_check.mjs`,
`world_start_check.mjs`, `audio_check.mjs` and `stream_check.mjs --world --audio` OK in their default forms (the
creator's first frame after New Game 3.59x, read with the load rising from 2.8 to 5.3); `world_check.mjs` failed its
default form twice on one unplaced hole each time, under the other lane's load.

## 7. The owner's decisions and approvals

**The answers before W29** (18 November 2026; `DECISIONS.md` §1.7): every default of the plan's §0.6
confirmed ("GO") - three releases; about 59.1 MB for the last download; build and face sliders; the
two added clothing slots; the box animals kept rather than a poor wolf; women among the people from more
CC0 data.

**Checkpoint A** (plan §4.2): a private page with the Gate A2 candidate, a video cut from the M11 tour
and the giant sheet (the skin in the world's light, hair and eyes, the motion in pairs with 0.10).
**The owner approved part one**, and decided:

1. **Ship part one as `0.11.0-m11`** - this release.
2. **The giant's native CPU budget with secondary motion is 0.15 ms a frame** (plan §2.12 said 0.12;
   measured 0.136-0.144). Applied: the plan's row and `UiProbe`'s comment; no test or tool encoded the
   native figure.
3. **The warmer in-world skin is accepted**, although the default chest in the creator's light is up to
   26/255 off the studio render approved for `0.10.0-m10`. Nothing to change.

**Known and accepted with the approval**, stated here and in the launcher's notes where a player meets
them: the draw calls at `medium` miss (379 against 330, 642 against 620; part three brings the room);
the creator's first frame in the browser is 3.3 times the median frame (the rule: 3); in first person
the legs and feet are never drawn; a black shell beard face-on against the sun is dark; stage 6's
unreforged sword at first person's rest is a sliver; the slow test tier is near its 400 s (384-395 s;
P53 moves headroom).

**After the release's checks**, the lead's steps: the tag `0.11.0-m11`, the play link republished from
this release's Web build, the pull request to `main` and its merge. This document does not record them.

**Open decisions of the owner's**: the look of parts two and three at their checkpoints; the two of
the M6-M9 handoff's §10 (a licence for the project and its generated assets; whether to commit the
lossless audio masters).

## 8. NOT RUN: the owner's tasks, and what could not run here

**The owner's tasks** (plan §4.5), **NOT RUN** here:

1. **The look on your own screens**: a real GPU and a real browser, with the motion sheet of
   `docs/USABILITY_SCRIPT.md` §12.2 beside the giant sheet of checkpoint A.
2. **Ten minutes of play**: every weapon family, a sprint, a stomp, first person (the motion sheet's
   rows), on desktop and in a browser.
3. **Frame times and first frames on real hardware**, with `node tools/web/creator_check.mjs --strict`
   on a machine with a GPU (and the three strict audio checks of the M6-M9 handoff's §9).
4. **A real gamepad in the creator's rows** (the creator sheet, `docs/USABILITY_SCRIPT.md` §12).
5. Still open from earlier handoffs: a licence for the project and its generated assets, the lossless
   audio masters, and `build_giant.py --verify` on a second machine.

**What could not run here**:

- Anything on a GPU: every frame time, stall ratio and music hole is a software renderer's; the Web's
  audio criterion has never been met in this container.
- A real browser other than headless Chromium, and a phone; the Windows export launched (it is only
  built).
- `build_giant.py --verify` on another toolchain.
- Nobody has played it: whether the motion reads as a living body to a person, and how the refined
  giant sits in the low-poly world, are judgments no check here makes.

## 9. Known bugs and limitations

- **No legs or feet in first person** (Gate A2): looking down shows the arms, the weapon and the body's
  shadow. Accepted.
- **A black short beard (a shell) face-on with the sun behind him reads as a dark mass**: the sky's
  ambient has no highlight in this renderer, and black cards read nearly as dark. Accepted.
- **Stage 6's unreforged sword at first person's rest is a sliver** in the corner (0.006 of the frame).
  Accepted.
- **The skin in the creator's light is warmer than the studio render approved for 0.10** (26/255 at
  most). Accepted. A red band where the body's shadow cuts the wrapped light shows faintly on the
  shoulders; the pale tone's shade is cooler than 0.10's.
- **The weapon hand can turn up to 144 degrees between two frames inside a tested swing**; the arms
  trail a fast change of the brain's arm pose by up to about 0.1 s outside one.
- **The cape swings as one board** (its three chains have no cross links); the tree is carried
  one-handed.
- **The creator's preview stands still**: no springs and no eyes' look there.
- **The granite veins mark is faint in first person** now that the arms lie in the body's shadow; the
  forearm slash and the back lash read a little less than in 0.10.
- **Draw calls at `medium`** miss their M11 budget (379 and 642); **the creator's first frame on the
  Web** is 3.3 times the median frame.
- **The slow test tier** runs 384-395 s against 400; P53 moves headroom in W31.
- **The Web tools**: `world_check.mjs` failed its default form twice on this release's build, each time on one
  hole of about 600 that its recorder did not place on the main thread, while another lane loaded the machine (it
  passed at Gate A on the same pack but for the version); run a failed default form again on a quiet machine before
  reading it as the build's.
- Everything in the M10 handoff's §9 and the M6-M9 handoff's §8 that this part did not fix still holds
  (the browser's memory under a starved CPU, the bake's one-texel jitter).

## 10. Next milestone

**`0.12.0-m12`, M11's part two: more customization** (plan §3.6-§3.11): the look's record at `v` 2
with a migration that keeps every `0.10` and `0.11` look; clothing and armour by slot (ten garment slots
and three accessory slots, 35 pieces); more hair, beards, braids and beads, designs and presets; the
build sliders and the face sliders; the creator II with pages, thumbnails and a filter; the Web budget
at 32 MiB. P53 (the record v2) started beside this release. Before it, or beside it: the owner's tasks
of §8.
