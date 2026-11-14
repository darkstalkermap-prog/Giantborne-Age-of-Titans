# Giantborn M10 plan: the realistic giant and the character creator

| Item | Value |
| --- | --- |
| Base | `main` after the 0.9.0-m9 ship (P40, W24). Planned on the integration tip `1c33b8e` (W22 merged; M9's W23 and W24 still running). Before W25 the orchestrator re-checks every fact below that M9 can change (§1.2, "Before W25") |
| Engine | Godot 4.6.3-stable (`7d41c59c4`), GDScript, Compatibility renderer, Jolt, fixed 60 Hz `Sim`. Asset pipeline: Blender 5.3 as the `bpy` 5.3.0 Python module (Python 3.13) in one shared venv outside every worktree (`GIANT_VENV`) |
| Targets | Linux and Windows desktop exports and the single-threaded Web export (the play link) |
| Inputs | The owner's words and choices (§0.2); the three M10 research briefs `giant_asset.md`, `giant_animation.md`, `character_creator.md` (committed with this plan as `docs/plans/briefs/m10_*.md`, their scratch-folder paths rewritten to `<scratchpad>/`); `M6_M9_PLAN.md` (structure and conventions); `ARCHITECTURE.md` and `DECISIONS.md` as P40 leaves them; the code at `1c33b8e`; this planning run's probes (§7); three reviews of the first draft (feasibility, the owner and player, process and tests) and this revision's own checks (§7, §8) |
| Output | 7 packages (P41–P47) in 4 waves (W25–W28, at most two agents at once), three owner checkpoints (a note before W25; a private playable link with a video and character sheet A after W26; character sheet B with the release candidate after the gate), one milestone gate, and the ship |
| Release | `0.10.0-m10`: tagged, published as the play link and merged to `main` only after the owner approves sheet B |
| Estimate | About 3 calendar days from the 0.9.0-m9 ship (2.5 at best, 4 with the likely overruns); about 58 agent-hours (§6) |

Every fact below is marked **VERIFIED** (someone ran it: one of the three research runs, named; this
planning run, "planner"; one of the three reviews, named; or this revision, "revision"; "VERIFIED
(code)" means read and grepped in the repository at `1c33b8e`) or **ASSUMED** (reasoned, not run).
Design choices are not facts and carry no mark. The facts that shape the plan:

- **The asset** (VERIFIED, asset brief): the kit's giant exports as a normal skinned glTF that Godot
  4.6.3 imports and draws in the Compatibility renderer: the unsubdivided CC0 hm08 body at stage-1
  height (3.6576 m), 26,756 triangles and 14,517 vertices in Godot, on MPFB2's CC0 "game_engine"
  skeleton (53 bones, 4 influences per vertex); seven garments as separate skinned meshes on the same
  skeleton (42,598 triangles for body, eyes and all seven); the glTF faces +Z and the game's actors
  face -Z. Godot's importer builds LODs for skinned meshes and the Compatibility renderer uses them
  (49,594 primitives at 4 m down to 3,352 at 120 m for the full outfit with hair and beard; the LODs
  cost 0.25 MB shipped); LODs generated per mesh keep a cut between two meshes closed (all 320 seam
  vertices of a test sphere cut in two stay in every LOD of both halves, VERIFIED feasibility review).
  Customisation works at run time in one ShaderMaterial per surface (skin tone, hair colour on
  stubble, scalp and brows, designs, scars, procedural eyes, clothing visibility and dyes, covered
  skin sunk by a region bitmask); hair and beards are cards (long hair 5,580 triangles, full beard
  3,360, one draw call each); alpha to coverage does nothing in this renderer; skin uses per-channel
  wrap lighting plus a thickness-driven back-light instead of subsurface scattering. Draw calls at
  the Web preset: 3 (body and eyes) to 11 (full outfit with hair and beard); today's box giant has 8.
- **Hair is the weakest part** (VERIFIED, revision, viewed `<scratchpad>/m10_plan/giant_asset/frames2/hair_compare.png`
  beside the approved `<scratchpad>/giant/renders/test_outdoor_head.png`): even the softest of the three
  in-engine card variants shows shingled steps and a thin scalp, where the approved render shows
  strands; the asset brief budgets "a day of art tuning" for hair.
- **Its cost on the Web pack** (VERIFIED, asset brief, one Web test export measured like
  `build_web.sh`: gzip -9 then base64): the game at `1c33b8e` ships 17,399,456 B = 16.59 MiB; the
  meshes with LODs and the four research hair and beard meshes 1.76 MiB; per map at 512 px VRAM
  compressed: albedo 89 KB, normal 329 KB, ORM 136 KB, masks 24 KB; at 1024 px the normal map alone
  is 1.29 MiB. WebP lossy flattened the skin and Basis Universal was larger than VRAM compression on
  every map. A shape key adds about 0.34 MiB shipped.
- **Determinism of the sources** (VERIFIED, asset brief): two runs of the glTF export, the hair atlas
  and the Cycles bakes gave byte-identical files, and a 1-thread bake matched 2 threads; Godot's
  re-imported scene files differ by a few bytes each time, so checks compare the glTF and PNG sources,
  never `.godot/imported`. The 1024 px bake takes 793 s at 2 threads, of which AO 535 s and
  thickness 117 s; every other pass together takes about 2.3 minutes (albedo 10.2 s, roughness 6.0 s,
  normal 54.7 s, masks 14.5 s, scars 16.6 s, rest position 4.8 s, rest normal 32.3 s; VERIFIED,
  revision, `giant_asset/logs/bake1024.log`).
- **The research code to port** (VERIFIED, revision, `wc -l` and `grep`): the kit snapshot is 3,320
  lines, of which `giant_pose.py` (480) is imported by no export, bake or hair script, so the game
  pipeline ports 2,840 kit lines plus about 1,030 lines of research scripts (export 272, hair cards
  264, bake 266, designs 150, pack 49, vendoring 26). The research drew four designs (arm bands, a
  chest spiral, forearm chevrons, face paint) and baked four scars, two of them empty.
- **Animation** (VERIFIED, animation brief): nothing in the 60 Hz simulation reads the rig (weapon
  sweep, hurtboxes, lock anchor, grab sockets and camera come from data and the growth profile; the
  rig feeds only footfall audio, camera shake, flashes and tints). A real body of the stylized
  giant's height reaches 1.385·k from a shoulder at (0.414, 3.015, -0.033)·k, so the sweep's grip
  point is out of reach in 98 % of ACTIVE samples; "tip matching" keeps the weapon's outer half
  inside the hit capsule in 100 % of 12,450 ACTIVE samples over every player weapon and stages 1–6
  (worst 0.60 hit radii), 7.0° median and 13.8° worst off the tested direction. A computed-keyframe
  walk synced to the brain's stride (within 2.5 %) and the real `ability.heavy_1` swing ran in the
  real `giant.tscn`; growth stages are uniform scales; one skinned giant costs 0.26 ms of CPU a frame
  on the Web, 35–70 µs natively; modifier results are only visible during `skeleton_updated`; six
  integration suites assert stylized node paths or the 1° arm rule.
- **The pose brain's gaps** (VERIFIED (code), revision): the brain advances its walk phase only in
  `LOCOMOTION` and `BLOCKING` (`actor_rig.gd`), while the rig state's `speed` is the horizontal speed
  in every state (`giant_player.gd`), so a clip blended by speed would glide in a frozen mid-stride
  during a dodge (4.5 m in 0.45 s), Shoulder Charge (26 m/s for 12 m) and a knockback; a jump stays
  in `LOCOMOTION` (`combat_controller.gd`), so the legs keep stepping in the air; `body_sweep` and
  `line_pulse` abilities have no pose branch; death is a 0.48π rotation of the whole body about the
  feet; stomps are drawn with the arms only.
- **The creator and saves** (VERIFIED, creator brief): a 7th shrine tab fits the real ShrineScreen
  at 1280x720 and level 20; a `character.appearance` block survives read, migrate, validate,
  sanitize, Continue, apply and capture, the next checkpoint and a death reload in the M9 code, while
  a schema 3 save is refused by M9; a SubViewport preview with its own world renders natively and in
  WebGL2 with 57 of 57 options changing the same pixels within 1 %; applying a whole look costs
  0.03 ms native and 0.06 ms on the Web; turning off the root viewport's 3D at a shrine cut its draw
  calls 677 → 0; the first frame with the giant's shaders stalls 0.5–3.3 s natively and 1.3–2.0 s
  on the Web's software renderers; loading the giant's scenes and materials takes 247–671 ms in
  WebAssembly. One `sampler2DArray` plus the per-vertex region id picks one design per region on
  desktop and WebGL2. Every exported morph leaves a dark patch between the brows; Pillow's RGBA
  resize wiped the RGB channels of the 512 px masks; two of the four baked scar channels are empty.
- **What the player sees in play** (VERIFIED, owner review's script, re-run by the revision): at
  the default third-person camera (1280x720, 75° FOV) the whole giant is 260 px tall at stage 1 and
  373 px at stage 6, the face 16–23 px wide, an arm band 5–8 px and an iris 1.3–1.8 px; the camera
  sits behind the giant, which turns toward its movement; the hip cut enters the first-person view at a
  pitch of −75° at stage 1 and −60° at stages 4–6 (the camera allows −85°). Stage 1 takes 3.12
  footfalls a second walking and 4.69 sprinting.
- **Engine behaviours the plan must respect** (VERIFIED, feasibility review's probes, Godot 4.6.3
  headless): three line designs packed into R, G and B over the same area of one DXT5 layer ghost
  into each other (error mean 0.21, the others showing through at mean 0.15–0.18), while one design
  per channel in separate areas stays clean (mean 0.02–0.05, no ghost); render layers, visibility,
  material overrides and nodes added inside an instanced scene are lost when a SceneKit-style save is
  reloaded (VERIFIED (code): `SceneKit.own()` never owns the children of an instance); a headless
  ShaderMaterial stores and returns a misspelled uniform without complaint, while
  `get_shader_uniform_list()` reports the real 24; `--import` imports an OBJ, a JPEG and a PNG placed
  under `tools/` (4.0 MB) because nothing there carries a `.gdignore`.
- **The session and the soak** (VERIFIED (code), revision): the 120 s seeded soak boots the sandbox
  (`--autoplay` without `--mode`), `start_sandbox()` clears the character, and `on_level_ready`
  applies a character only on a pending restore, so a look passed only to New Game never reaches the
  soak; the soak injects light, heavy, block, dodge, `slot_1`, jump, lock, camera and target presses
  and never grabs, and its `footfalls` count is the number of `slot_1` (Heavy Footfall) presses, not
  the rig's footfalls; the Valley bot grabs and throws, and `run_metrics` counts both; the gate tier
  already holds a seeded Valley twin run (`test_valley_audio_determinism`, 150 s, audio on and off).
  `SaveSlots.read` reports only dropped ids and `CharacterState.sanitize` returns only data and
  dropped ids; `UiScreen.cancel()` closes without asking; `UiNav.page_step` is pad-only; the title
  has no loading gate; the camera hides one render layer (2) both in first person and when the
  third-person arm is pressed close, and the tree's canopy and the pine's needles are on that layer.
- **New Game today** (VERIFIED (code), revision): `test_session_flow` and
  `test_title_checkpoint_names` press the title's New Game and expect an immediate reload;
  `audio_check.mjs` and `world_start_check.mjs` press Enter on the title and wait for the Valley;
  the launcher's "Start in the open world" passes `--mode=world`, a command-line New Game; the M8
  release ran `world_start_check.mjs` and `stream_check.mjs --world --audio`.
- **The base** (VERIFIED (code), the system docs and `.userdata/check/suite_times.txt`): the default
  test tier ran 56.2–88.4 s in the last twelve recorded runs (one commit ran 78.2 s and then 63.3 s),
  against a 75 s budget that `check.sh` only warns about; the slow tier 201–297 s of 8 minutes, the
  gate tier 377–588 s of 50 minutes; 281 suites and 48,145 checks at P39f's last check. On 0.9.0-m9
  (re-checked on 0.9.0-m9, §7): 291 suites (55 unit, 154 integration, 53 slow, 29 gate) and 50,114 checks
  at P40's final check (default 73.4 s, slow 314.9 s, gate 687.0 s); the default tier alone is 209 suites
  and 38,005 checks and ran 78.3 and 79.8 s in two quiet-machine runs, over its 75 s budget, and 65.8–77.9 s
  in the last twelve recorded runs.
  `ScreenStack.SCREENS`, `ShrineScreen.TABS`, `GiantPlayer.COMPONENTS`, `DataValidator.SCHEMA_PATHS`,
  `build_scenes.gd BUILDERS` and `ResetHooks` are pre-declared registries that skip missing files
  (M6–M9's P20 shipped `test_predeclared_m7.gd` for its entries); `GiantPlayer.rig` is typed `ActorRig`;
  `RigPaint` copies only `StandardMaterial3D` overrides; `build_web.sh` derives the pack budget from
  the version's `-mN` suffix (m8 and later: 23 MiB) and fails over it or over 15 MB a part;
  `.userdata/` (and so any cache under it) belongs to one worktree; rendered suites print "skipped"
  and pass without `xvfb-run`. M9 has already changed `screen_stack.gd` (the footer shows the top
  screen's `nav_hint()`), `ui_screen.gd`, `title_screen.gd` and `shrine_screen.gd` on `pkg/P39f`.
- **The precedents for the schedule** (VERIFIED, revision, git): M6–M9 waves of two packages took
  about 2–5.5 hours each; the M6 gate (5 findings) took about 3 hours from the W13 merge to its tag;
  the M8 gate (46 findings over a whole open world) took 16.3 hours to its last fix-up merge and 20.7
  hours to its tag.
- **This planning run's probes** (VERIFIED, planner, §7): loading the research giant's imported
  scenes costs 4.4 ms the first time, a cache miss 3.0 ms plus 16.3 ms for seven textures; instancing
  costs 0.15–0.28 ms; a tiled PNG imported with the `2d_array_texture` importer is a VRAM-compressed
  `CompressedTexture2DArray` (DXT5) that a `sampler2DArray` accepts; a glTF imported with the
  `animation_library` importer loads as an `AnimationLibrary` (loop off); the CC0
  `rig.game_engine.json` lists 53 bones.

---

## 0. Scope, the owner's decisions, interpretations and the deferred list

### 0.1 Goal

Put the realistic giant the owner approved into the game as the player's own body, and let the
player shape the giant. **The giant**: a skinned, textured, CC0-derived body with hair and beard cards,
garments and procedural eyes, driven by today's pose system so that every combat state, every
weapon family, grabs and throws, staggers, dodges, jumps and death read at least as well as they do
now; growing through stages 1–6 by uniform scale; first person kept clean; hit flashes and status
tints kept; every asset regenerated by committed tools from audited CC0 inputs, bit-exactly on the
reference toolchain. **The creator**: one character-creation screen that opens at New Game and again
from a new Appearance tab at every shrine, with presets, Randomize, Undo and the categories the owner
named — hair and beard styles and colours, tattoos and war paint, scars, skin tone, eyes and clothing
— saved in the character without a save-schema bump, with options chosen so that they read in play,
not only in the creator. **What must not change**: anything that plays. The simulation, the hit
geometry, hurtboxes, camera geometry, grab sockets, balance, the bots' results and the seeded soak
stay exactly as 0.9.0-m9 left them; the look is presentation only. The Web build keeps its 23 MiB
pack budget unless the owner raises it.

### 0.2 The owner's words and choices

The first request, when M9 was running (the name of a third-party generation service is left out,
because no repository file may name such a product):

> "use … or Blender to render a very detailed realistic Giant in our world"

After seeing the Blender renders (verbatim):

> "Looks good you can add it but make the  Giant be customizable with tattoos hair variations etc a character creation of you will"

Their choices, as relayed with the request:

1. **The realistic giant in the game** — the player's body in play, not only a render or a menu figure.
2. **A character-creation screen at New Game** with hair and beard styles and colours, tattoos and
   war paint, scars, skin tone, eyes and clothing.
3. **Changeable later at shrines.**
4. **The next milestone, M10, right after 0.9.0-m9 ships, in about 2–3 days of work.**
5. They were told that the realistic giant will stand out against the simpler soldiers and world until
   those are upgraded too, and chose it anyway.

What they have not seen yet, and will see before they are asked to approve anything (§4.2): the giant
in-engine (cards, not strands), moving, at the size the game camera shows it, and the creator in their
own hands.

### 0.3 The M10 gate and the packages that prove it

| Requirement | Proven by |
| --- | --- |
| The realistic giant is the player in play: third and first person, stages 1–6, every player weapon family (club, sword, hammer, axe, fists, the tree and the great pine), every ability pose the brain draws, grabs, holds and throws, staggers, dodges, jumps, Shoulder Charge, death, hit flashes and status tints; no frozen-stride glide, no legs stepping in the air, no breathing corpse | P43 (the skinned rig, its suites, the capture tour); P41 (the asset); the gate's frame review (§4.1) |
| Nothing that plays changes: the default, slow and gate tiers pass; the seeded soak and the world bot's smoke run give byte-identical results on 0.9.0-m9 and on the candidate (wall-time, node-count and memory fields removed); the skin on or off and two different looks give byte-identical soaks, and a seeded Valley bot run that grabs and throws gives identical results with the skin on and off, each with a `SKIN_STATS` line that proves the skin and the look ran | P43 (the determinism gate suite, code rules); P42 (the look never enters the simulation; `--appearance=` in every mode); the gate (§4.1 lens 2) |
| Character creation at New Game, and from the launcher's open-world start: hair and beard styles and colours with grey, tattoos, war paint, scars, skin tone, eyes, clothing with dyes, presets, Randomize and Undo; Back keeps the save and asks before discarding changes; Begin keeps the Web pointer lock | P44 (screen, preview, flows); P42 (record, data, `--creator`); P41 and P46 (content); P45 (the launcher, the Chromium checks) |
| Changeable at every shrine, free, any number of times; the change is saved at once and restored on Continue and after a death; players of older saves are told once | P44 (the Appearance tab); P42 (the checkpoint rule, the component, the one-time messages) |
| The options read in play: every design category has options that show from behind at stage 1 or in first person; a design under clothing says so | P41 and P46 (design rules), P44 (the rendered option check's rear and first-person views; the creator's notes) |
| Saves: schema 2 kept; every older save loads with the default look; a broken or unknown look is repaired with a message the player sees, never a failed load; a look from a later build is kept untouched; a 0.9.0-m9 build keeps a 0.10 save's look | P42 (fixtures, sanitize, notes); the gate's cross-version run (§4.1 lens 4) |
| Every giant asset generated by committed tools from audited CC0 inputs, with provenance and credits; `build_giant.py --verify` regenerates every output bit-exactly on the reference toolchain in any worktree | P41 (P43 for the clips, P46 for its content) |
| The Web build within budget: the pack ≤ 23 MiB and M10's share ≤ 4.6 MiB, parts ≤ 15 MB, ≤ 250 draw calls a view, the skin's CPU ≤ 0.35 ms a frame, no shader stall above 3× the median frame on the title, the creator, a level and a shrine, the Chromium checks pass | P41 (the share, measured from W25), P45 |
| The owner approved the look: their notes on the playable preview and sheet A applied, sheet B approved before the release | P44 (the sheet tool), P46 (the notes), the gate, P47 (§4.2) |
| The test tiers within budget at every merge (default < 75 s, slow < 8 min, gate < 50 min), with no check skipped | every wave merge (§1.7) |

### 0.4 Interpretations and decisions (P47 copies these into `DECISIONS.md`)

1. **The player's giant only.** M10 replaces the stylized rig of the player. Soldiers, villagers,
   named NPCs, the rival and clan giants, Harrok, the creatures and the world keep their low-poly
   look (§0.5 gives the reasons and the next step). The player's weapons keep their low-poly meshes.
2. **The pose brain stays; a skinned body follows it.** `ActorRig` keeps computing every pose on the
   frame clock. A new `SkinnedRig extends ActorRig` adds the realistic body: an `AnimationTree` of
   computed-keyframe clips (idle, walk, run, grips, an airborne pose, a death) whose walk time is
   taken from the brain's walk phase while the brain walks, then one `PoseBrainModifier` (a
   `SkeletonModifier3D`) that twists the spine, solves the weapon arm by tip matching and maps the
   off arm and the grab hand. Where the brain does not walk, the legs never step: dodges, staggers
   and knockbacks hold the stance under the body's lean, an action that moves the giant (Shoulder
   Charge) runs the run clip on a clock of its own, a jump shows the airborne pose, and death stops
   the idle and buckles the knees before today's fall. Because `SkinnedRig` extends `ActorRig`, every
   `is ActorRig` reader keeps working, and footfall audio stays on the brain.
3. **Tip matching replaces the 1° rule.** The M0/M1 contract "the procedural rig reads the same
   `AttackGeometry`, so the visible swing is the tested swing" becomes: the hand holds a grip the
   real arm can reach and the visible weapon aims at the tested segment's tip; its outer half stays
   inside the tested capsule (measured over every arc), at most 15° off the tested direction (7°
   median). The gameplay geometry (pivots, arm lengths, reach bands) is not changed in M10.
4. **The gameplay body is unchanged.** The capsule, hurtboxes, lock anchor, attack origin, grab
   sockets, launch points and camera geometry stay the stylized giant's (§2.7); the realistic
   proportions are presentation. A held body's *visual* is moved by the remaining gap to the visible
   palm (at most 0.33·k m); its collision stays where the simulation puts it.
5. **Presentation only, write-only.** The skinned layers write only under `Visual/Body` (and the held
   body's `Visual` offset while holding); no simulation, AI, combat, world or quest code reads the
   skeleton, the clips, the model or the look. Code-rule tests enforce it; a gate suite proves it with
   positive controls (§3.3).
6. **The skinned layers run where something is drawn.** With a display (the game, Xvfb renders, the
   Web) they run; in headless runs (the default test tier, the bots) they stay off unless a test
   calls `SkinnedRig.enable_for_tests()` or the command line says `--skin`; `--skin-stats` prints a
   `SKIN_STATS` line at exit that proves what ran. The model is still instanced headless (VERIFIED,
   planner: 0.15–0.28 ms), so node paths exist; the weapon hangs at the brain's hand.
7. **Growth is a uniform scale** of the stage-1 model by `k = height / 3.6576` under `Visual/Body`,
   as today; no per-stage proportions in M10; growth stays instant.
8. **First person by render layers, with closed cuts.** The body is exported in three meshes: the
   head (scalp, face, neck) on render layer 3 with the hair, beard and eyes; the torso (chest, belly,
   back, pelvis) on layer 2 with the core parts of garments; the limbs on layer 1. Every cut loop is
   capped (filled, weighted to the limb's root bone, shaded as skin or the garment's inside), so no
   limb is hollow when seen from inside. First person culls layers 2 and 3. Third person with the arm
   pressed close culls layer 3, and layer 2 too if P43's render in the growth course's low passage
   shows the torso over the crosshair. Whatever must hide whenever the camera is pressed close (the
   tree's canopy, the pine's needles) moves to layer 3. The camera's masks change; its geometry (the
   eye at 0.92 of the height and 0.18 m forward, the pressed-close rule) does not.
9. **Assets are generated, audited and verified.** `tools/giant/` (bpy 5.3.0 in a pinned venv shared
   by all worktrees) regenerates every giant asset — meshes, garments, hair and beard cards, eyes,
   the Cycles bakes, the design array, the clips — from a vendored, audited CC0 subset of the
   MakeHuman/MPFB2 data. `--verify` regenerates into a temporary folder and compares with the
   manifest: bit-exact on the reference toolchain, a stated tolerance for the Cycles bakes on another
   CPU, reporting "toolchain differs" apart from "content differs". The quick form `--skip-bake`
   re-bakes the cheap passes and takes AO and thickness from the committed desktop ORM map, so every
   output is regenerated and compared in any fresh worktree within minutes. No code from GPL or
   Apache-licensed sources is copied; the kit's code is original. **After W25 the body mesh, the
   skeleton, the region ids and the landmarks are frozen for M10**: later work and the owner's notes
   change materials, hair, garments, designs and palettes; a body change needs the orchestrator's
   decision, the clips regenerated and P43's suites re-run.
10. **No shape keys in M10.** No face or build sliders: a dense blend shape costs about 0.34 MiB
    shipped each and every exported morph showed an unexplained dark patch (VERIFIED, asset and
    creator briefs). Height is the growth stage and never a choice. One face and one build.
11. **One design array.** Tattoos, war paint, ancestry marks and scars are layers of one
    VRAM-compressed texture array (`assets/giant/designs.png`, imported as a 2D array); the body's
    per-vertex region id (16 regions, §2.6) picks the design of each region; any number of designs
    costs one sampler. Within one layer, a region's area carries at most one design in R, G or B plus
    one in A, because the compressor ghosts designs that share an area (§2.5).
12. **Hair is cards** with depth-pre-pass blending, tinted scalp and beard skin under them; no alpha
    to coverage. **Skin** uses wrap lighting with a back-light transmission term; no subsurface
    scattering.
13. **Palettes, not free colour pickers.** Every colour is a named swatch from data (readable in the
    world's light, steppable with a pad, saved as an id that can be retuned).
14. **The look lives in the character, schema 2 kept.** `character.appearance` is an optional key with
    its own `"v"`; absent means the default look (old saves, fixtures, the bots and every command-line
    start without `--appearance=`); sanitize repairs and reports, and its notes reach the player's
    load message; a record from a later build (`v` above 1) is kept untouched; the creator writes the
    full record.
15. **One creator, three doors.** `CreatorScreen` opens at New Game (after the existing confirm and
    the prologue or skip choice), at the launcher's "Start in the open world" (`--creator`), and from
    the shrine's Appearance tab (Keep applies and re-takes the shrine's checkpoint, as M8's F15 rule
    does for talents; Cancel restores). Leaving with changes asks first; Undo covers every change.
    Changes are free, at any shrine, at any stage. The pause menu and the HUD get nothing; two one-time
    messages tell players of older saves and new ancestry marks where the tab is.
16. **Ancestry marks are automatic and removable** (owner may change, §0.6): `mark: "auto"` shows the
    chosen ancestry's mark; "none" hides it; marks, two ancestry-only eye colours and one skin tone
    are locked until the ancestry is chosen.
17. **Two texture tiers.** Desktop exports draw the 1024 px normal and ORM maps (`tex_hi/`); the Web
    preset excludes them and the giant falls back to the 512 px maps (`tex/`, the albedo included),
    keeping the 23 MiB pack budget. The owner raised the Web budget to 26 MiB (§0.6): from P45 on, the
    Web pack keeps the 1024 px maps too (§0.6, "How answer 1 applies").
18. **Options must read in play.** The face is 16–23 px wide at the game camera and usually turned
    away, so every design category offers bold, large pieces that show from behind at stage 1 or in
    first person (sleeves, back pieces, shoulder paint; strokes of at least 4 cm at stage 1), the
    rendered option check measures the rear and first-person views, and the creator has a "Game
    view" and says when clothing hides a design.
19. **The owner sees it early and approves it before the release** (§4.2): a note with in-engine
    frames and the questions before W25; a private playable link, a 60–90 s video and character sheet
    A after W26 (their notes steer P46); sheet B and the release candidate after the gate. The release
    waits for their approval; no other work waits.
20. **Test tiers as in M6–M9**, with M10's caps (§1.7): each package's cost is counted from the test
    runner's per-suite times; merges run with `--require` (no check may skip) and `--strict-times`.
21. **The gate has an independent review** with fix lanes and an audit, as at the M8 gate, plus the
    owner's look approval (§4).

### 0.5 Out of scope in M10 (deferred), and why the world keeps its look

The owner asked for the giant, and they accepted that the giant will stand out. Upgrading the people
and the world is a milestone or more of its own: every human archetype needs a body, outfits per
faction and its own CPU cost per skinned actor on the Web (about 0.07–0.1 ms each with several on
screen, VERIFIED, animation brief), and the world needs textured terrain, props and buildings. Doing
any of it inside the M10 window would starve the giant and the creator. The plan therefore keeps the
world and the human NPCs as they are and **recommends M11 = "people near the camera"**: soldiers,
villagers and named NPCs on the same body pipeline, with their stylized rigs kept as the far level of
detail (the creator brief's option A), then world materials (option D). Deferred, each with its
reason:

- **A "World" style switch for the giant** (flatter lighting, softer normals, a palette pulled toward
  the world's): nobody has seen it, and a realistic body lit flat may still read as realistic by its
  shape (ASSUMED). Its time goes to the hair. The owner may ask for it (§0.6 question 3), and then
  P46 adds it (about 1 agent-hour) and sheet B shows it.
- **Other giants** (rival and clan giants, Harrok): stylized in M10; the skeleton, brain and tip
  matching can carry them later.
- **Animation beyond M10's clips**: foot IK on slopes, roar, flex, flinch and roll clips, two-handed
  grips (reachable in only 4–21 % of swing samples, VERIFIED animation brief), head look, bone-driven
  hair and beard physics, facial expressions, a growth tween. (M10 has idle, walk, run, grips, an
  airborne pose and a death; a stomp clip is on the cut list.)
- **Gameplay pivots matched to the real skeleton** (would remove the 7° offset; a gameplay change to
  reach bands, the vertical aim and the balance matrices) — a later option if playtests notice.
- **Face and build sliders, age wrinkles, a name** (§0.4 decision 10).
- **Realistic weapon meshes** (a material pass is on the cut list, §6.3).
- **An end-screen portrait and a title figure** (cut list; the title warm-up is not deferred).
- **Real GPUs and real browsers**: every frame time here comes from software renderers (llvmpipe,
  SwiftShader); the owner's machines decide (§4.4).

### 0.6 Questions for the owner, with the defaults the plan proceeds on

Sent before W25 with the note of §4.2 (in-engine frames from the research, the approved renders
beside them, the scope in plain words). No answer blocks any package; the release waits only for
the approval of sheet B.

| # | Question | Default (the plan proceeds on it) | What a different answer changes |
| --- | --- | --- | --- |
| 1 | Raise the Web pack budget from 23 to 26 MiB (still two parts)? | Keep 23 MiB: the Web draws 512 px textures, desktop 1024 px normal and ORM | 26 MiB: P45 lets the Web keep the 1024 maps (+≈1.3 MiB) and P46 may add styles; one line in `build_web.sh` and its test |
| 2 | Ancestry marks automatic on the choice (removable at shrines), or only offered? | Automatic, removable | "Offered": the default `mark` becomes "none" (data) |
| 3 | Do you want a "World style" switch that lights the giant flatter, closer to the world's look? | Not built in M10 (§0.5) | Yes: P46 adds it after the hair work, a Settings row, Realistic by default; sheet B shows both |
| 4 | Keep the low-poly weapons in M10? | Yes (a material pass is cut-list item 1) | A material pass: P46, about 2 agent-hours |
| 5 | Approve the look (the preview link and sheet A after W26: notes; sheet B before the release: approve, approve with notes, or not yet) | — | Notes after W26 steer P46; "not yet" on sheet B opens one fix lane before sheet B is sent again |

**The owner's answers (12 November 2026, before W25).** They replace the defaults above where they
differ, and every package reads them as decisions:

1. **Raise the Web pack budget to 26 MiB** (still two parts of at most 15 MiB). The Web keeps the
   1024 px normal and ORM maps like the desktop builds. P45 changes the budget line in
   `tools/build_web.sh` and its test, and records the new budget in `docs/PERFORMANCE.md`. P46 may
   spend the remaining headroom on more styles, within the 26 MiB budget.
2. **Ancestry marks are automatic** when the line is chosen, and can be hidden at shrines (the
   default stands).
3. **No "World style" switch** in M10 (the default stands).
4. **Keep the low-poly weapons** in M10 (the default stands).

**How answer 1 applies** (the orchestrator, 14 November 2026, before W25). W25 builds both tiers and
the Web presets' exclusions as §1.6 and §3.1 item 9 say, so P41's test export measures the floor's
share at 512 px (≤ 2.9 MiB), and the budget stays 23 MiB through W26. **P45 applies the answer in
W27**: it removes `assets/giant/tex_hi/*` from the Web presets' exclusions (the manifest stays
excluded), raises `build_web.sh`'s budget for `-m10` to 26 MiB and `GIANT_SHARE`'s cap to 7.6 MiB
(4.6 plus the 3 MiB the answer adds, keeping §2.12's 1.7 MiB margin under the budget), updates their
tests and §2.12's row, and its checks expect `tex_hi/` in the Web pack; `GiantLook`'s tier "auto"
then picks `tex_hi/` on the Web as on the desktop. Where a later row still names 23 MiB, a 4.6 MiB
share or a Web pack without `tex_hi/`, it describes W25 and W26; from P45 on, the figures of this
paragraph apply.

---

## 1. Execution model and wave schedule

### 1.1 Definition of done for every package

As in M6–M9 §1.1. Each package is one agent in one session, about 1,200–3,500 new lines including
tests and data (an asset package counts its generators, data and tests, not its generated files;
research code moved into the repository with edits is listed apart as "ported" lines and counts at
about a third of a new line). Before committing:

1. Every Godot command runs through `tools/gd.sh` (the worktree's own `user://`); exports run without
   `XDG_DATA_HOME`. Heavy processes run under `nice -n 19`; Cycles uses at most 2 threads. The giant
   pipeline runs with the shared venv `GIANT_VENV` and the shared cache `GIANT_CACHE` (§2.5), never
   copies inside a worktree.
2. `tools/check.sh` with the right options passes: import → build scenes (`--only=<builders>` for the
   builders the package changed, `--build` for all) → import → default suite (plus `--slow` when the
   package added or changed slow suites, `--gate` when it added or changed gate suites) → the 120 s
   seeded soak with `"errors":0` and the breakable-path coverage. **Giant asset packages** (P41, P43
   for its clips, P46) add `--giant` (P41 adds the option: `tools/giant/test_giant_tools.py`, then
   `build_giant.py --verify --skip-bake`, which regenerates and compares every output with the cheap
   bake passes, about 4–5 minutes, ASSUMED from the measured passes) and, when they changed the bake
   inputs (the body, its UVs, the skin code, the bake settings), `--giant-full` (the full
   regeneration including AO and thickness, about 15–20 minutes at 2 threads, ASSUMED from the
   793 s bake). Every package that touches a scene builder rebuilds twice and requires no diff.
   **Every package's final check adds `--require`**: a missing venv, `xvfb-run` or Chromium is a
   failure, not a skip.
3. Shipped data validates; no runtime errors; scenes and generated resources are never hand-edited;
   the generated giant assets change only through `tools/giant/` and its manifest.
4. **Test budget (§1.7).** Each package's added default, slow and gate time is capped in its spec and
   reported in its system doc from the test runner's per-suite times: its own suites plus the
   change in the suites of §1.7's list that load the giant.
5. `docs/systems/<package-id>.md`: what was built, public APIs, data, decisions and deviations, known
   gaps, the runtime added to the suites, and for asset and Web packages the pack share, the draw
   calls and the CPU per frame. **Only P47 edits `README.md`, `ARCHITECTURE.md` and `DECISIONS.md`.**
   `PERFORMANCE.md`, `USABILITY_SCRIPT.md`, `CREDITS.md` and `FOLLOWUPS.md` are edited by the packages
   named in §3.
6. Commit on `pkg/<id>` with messages that name the package id. No AI product or model names and no
   absolute scratch-folder paths in any file (`test_ship_docs` checks every text file).

### 1.2 Branches, worktrees, the wave merge and generated assets

Unchanged from M6–M9 §1.2: the integration branch is the one M2–M9 used; each package works on a
local `pkg/<id>` branch in its own worktree from the integration tip at the start of its wave; a
package uses only what exists at the start of its wave plus its own work ("Cross-lane symbols" in §3
lists the few it must reach defensively). The wave merge: merge the first package, import → full
build → import → full suite; merge the second (conflicts only in the hunks §1.5 names); import →
full build → import → `check.sh --slow --giant --require --strict-times` (`--gate` and
`--giant-full` at W27) → the 120 s soak; record the default and slow times and every per-suite cost;
commit "Merge wave N" and tag `wave-N` (continuing from `wave-24`). Fix-forward only under about 50
lines, else revert the package and re-run it. Each merge also runs its own step of §4.2 (W25: the
hair frames; W26: the preview link, the video and sheet A).

**Generated outputs.** Scenes are regenerated by the full build as before. The giant's generated
assets (everything under `assets/giant/`, its `manifest.json` included, §2.5) have exactly one writing
package per wave (§1.5) and exactly one writing lane at a time during the gate: the merge takes that
writer's files and runs `--giant`. No two packages or lanes regenerate them at once.

**Before W25** (the orchestrator, about 1.5 hours):
1. Commit this plan and the three briefs to `docs/plans/` with every scratch-folder path rewritten to
   `<scratchpad>/` (VERIFIED, planner grep: 15 lines in the briefs; the only other match, the
   integration branch's name, is one `test_ship_docs` allows).
2. Re-check on the 0.9.0-m9 base what M9 can have changed: re-run the planner's greps and probes
   (§7), the creator brief's shrine fit at level 20 and its save lab, two default-tier runs with
   their per-suite times, one Web export's size, and the files §1.5 assigns (M9 changed
   `screen_stack.gd`, `ui_screen.gd`, `title_screen.gd`, `shrine_screen.gd`, `autopilot.gd` and
   `tools/web/*` after `1c33b8e`, VERIFIED revision); record the differences in this plan's §7.
3. Create the shared venv at `GIANT_VENV` (default `$HOME/.cache/giantborn/giant-venv`) from the
   research venv's pinned versions (Python 3.13.18, bpy 5.3.0, numpy 2.5.4, scipy 1.18.1, Pillow
   13.0.0, OpenEXR 3.5.4, VERIFIED planner) and the cache folder `GIANT_CACHE` (default
   `$HOME/.cache/giantborn/giant-cache`); record `pip freeze` and the download time (about 1 GB,
   10–15 minutes, ASSUMED). P41 commits the pinned requirements from it.
4. Send the owner the note of §4.2 with the questions of §0.6.

### 1.3 Wave schedule (two lanes)

| Wave | Lane A | Lane B | Leaves working |
| --- | --- | --- | --- |
| W25 | **P41** The giant asset pipeline and the model | **P42** The look: appearance rules, data and saves; the giant's shaders and `GiantLook`; tip matching; the M10 pre-declarations | Players see no change yet (the stylized giant still plays). `build_giant.py --verify` regenerates every giant asset from the audited CC0 subset in any worktree; the model draws every floor option in-engine with the real shaders; the look record saves, loads, repairs itself and reaches the player's messages; New Game takes an appearance and `--creator` is parsed; every M10 registry entry, anchor and event is declared and tested; the default tier has its headroom; the Web share of the floor is measured |
| W26 | **P43** The skinned giant in the game | **P44** The character creator, the shrine's Appearance tab and the character sheets | The realistic giant plays: pose brain, clips, tip matching, stages 1–6, first person, jumps, charges, death, grabs, tints and flashes. New Game opens the creator; every shrine has the Appearance tab. **The owner gets a private playable link, a video and sheet A** |
| W27 | **P45** The Web build, performance, warm-ups and the Chromium checks | **P46** The look pass: hair first, the owner's notes, the target catalogue | The Web build within budget with the giant and the creator; the Chromium checks, the launcher's world start through the creator; the hair's second pass; the catalogue at its target; **M10 gate**, then **sheet B and the release candidate go to the owner** |
| W28 | **P47** Ship | — | **Ship gate.** Docs, handoff, exports; after the owner approves sheet B: the tag `0.10.0-m10`, the play link and the merge to `main` |

**Why this order.** The asset (P41) and the look (P42) meet only through the contracts of §2 (the
catalogue's ids, the giant index and its landmarks, the look dictionary, the shader uniforms), so they
run side by side: P41 owns everything that is generated or imported (the Python pipeline and the
model scene), P42 everything that turns a record into uniforms (the rules, the data, the four shaders,
`GiantLook`) plus `TipMatching`, a pure library that needs only the weapon data and the skeleton's
landmarks. That split balances the wave (P41 about 6 hours, P42 about 5) and puts `DEFAULT_LOOK` and
the data that must equal it in one package. P42 also lands every registry entry and anchor M10 needs,
so later packages only add files. The rig (P43) needs the model and tip matching; the creator (P44)
needs the model, the look, the record and the data; they share no files, and the creator's preview
uses the model directly rather than the player's rig, so neither waits for the other. The Web and
performance work (P45) and the look pass (P46) need the integrated giant and creator, and P46 needs
the owner's notes on the playable preview, which arrive while P46 starts with the hair. Content beyond
the floor catalogue is deliberately late: the owner plays the floor before it is multiplied.

**Owner checkpoints** (§4.2): the note before W25 (questions; recommended, not blocking); the
playable link, video and sheet A after the W26 merge (not blocking: their notes steer P46 and, when
they arrive late, a lane of the gate); sheet B with the release candidate after the gate (blocking
only for the tag, the play link and the merge to `main`).

### 1.4 Dependencies

| Package | Depends on (merged earlier) |
| --- | --- |
| P41, P42 | 0.9.0-m9 on `main`; the shared venv (before W25, P41 only) |
| P43 | P41 (the model, the bones, the landmarks, `GiantModel`, the venv and the vendored data for its clips); P42 (`GiantLook`, the shaders, `TipMatching`, the `appearance` component, the anchors, `--appearance=`) |
| P44 | P41 (`GiantModel`, `hand_transform`); P42 (`GiantLook`, `TipMatching.idle_grip`, the record, data, `Appearance`, the session's New Game path and `--creator`, `SCREENS["creator"]`, `TABS`, `appearance_changed`) |
| P45 | P43, P44 |
| P46 | P43, P44; the owner's notes on the preview (applied when they arrive) |
| P47 | P45, P46, the M10 gate; the owner's approval of sheet B (for the tag, the play link and the merge) |

### 1.5 Hotspot policy

The three mechanisms of M6–M9 §1.5 stay. **P42 extends them for M10 in W25:**

1. **Pre-declared registries** (P42 adds every planned path; a missing file is skipped silently, so
   P42's `test_predeclared_m10.gd` checks each path's spelling against this table and each file's
   existence once its owner has merged):
   `ScreenStack.SCREENS["creator"]`, `ShrineScreen.TABS` (Appearance, last), `GiantPlayer.COMPONENTS`
   (`appearance`) with its `appearance` field, `DataValidator.SCHEMA_PATHS` (`appearance_set`,
   `appearance_preset`), `ResetHooks.AFTER_EACH` (`["script", "res://scripts/presentation/skinned_rig.gd",
   "reset_for_tests"]`, P43's file). P41 adds `giant_model.gd` to `build_scenes.gd BUILDERS` (before
   `player.gd`).
2. **Package anchors** (`## @anchor P<id>` lines written by P42 and listed in
   `tests/support/anchors_expected.gd` with P42 as their creator):

| File | Anchors (M10) |
| --- | --- |
| `scripts/core/events.gd` | P41, P43, P44, P45, P46, P47 (P42 declares §2.11's signal in an "appearance (M10)" block above them) |
| `scripts/core/game_data.gd` (post-pass) | P42 (its own), P46 |
| `scripts/progression/character_state.gd` | P46 |

3. **Single owner per wave** for the other shared files:

| File | W25 | W26 | W27 | W28 |
| --- | --- | --- | --- | --- |
| `scripts/core/game_session.gd` | P42 | — | — | — |
| `scripts/core/save_slots.gd` (`read()` joins the look's notes; the header), `scripts/core/data_validator.gd` | P42 | — | — | — |
| `scripts/progression/character_state.gd` (outside its P46 anchor) | P42 | — | — | — |
| `scripts/actors/giant_player.gd` | P42 (COMPONENTS, field) | P43 | — | — |
| `ui/screens/screen_stack.gd` | P42 (SCREENS) | — | — | — |
| `ui/screens/title_screen.gd` | — | P44 | — | — |
| `ui/screens/shrine_screen.gd` | P42 (TABS) | — | — | — |
| `ui/screens/end_screen.gd` | — | — | P46 (portrait, cut list) | — |
| `tests/support/reset_hooks.gd`, `tests/support/anchors_expected.gd` | P42 | — | — | — |
| Moving existing default suites to `tests/slow/` (§1.7 rule 4) | P42 | — | — | — |
| `tests/unit/test_ship_docs.gd` | P41 (skip the vendored CC0 subset) | — | — | — |
| `tests/integration/{test_session_flow,test_title_checkpoint_names}.gd` | — | P44 | — | — |
| `tools/build_scenes.gd`, `tools/check.sh` | P41 | — | P45 (only if a check option is needed) | — |
| `tools/builders/player.gd`, `scripts/presentation/{actor_rig,rig_paint,camera_rig,weapon_visuals}.gd`, `scripts/debug/autopilot.gd` | — | P43 | — | — |
| `scripts/presentation/giant_model.gd` | P41 | P43 | P46 | — |
| `scripts/presentation/giant_look.gd`, `assets/shaders/giant_*.gdshader` | P42 | P43 | P46 | — |
| `scripts/presentation/tip_matching.gd` | P42 | P43 | — | — |
| `tools/giant/**`, `assets/giant/**` | P41 | P43 (`kit/clips.py`, `giant_clips.glb`, the `--clips` step) | P46 | gate lanes, one at a time |
| `data/appearance/**`, `data/tutorial/appearance_*.json` | P42 | — | P46 | — |
| `export_presets.cfg`, `tools/build_web.sh`, `tools/pck_files.py` | P41 (the manifest and `tex_hi/` exclusions; `GIANT_SHARE`) | — | P45 | P47 |
| `web/launcher.html`, `tools/web/**` | — | — | P45 | P47 |
| `scripts/core/settings.gd`, `ui/screens/settings_pages.gd` | — | — | P46 (only if the owner asked for the World style) | — |
| `scripts/main.gd` | — | — | P45 (the loading screen's warm-up, only if measured necessary) | — |
| `project.godot` | — | — | — | P47 (version, description) |
| `docs/PERFORMANCE.md` | P41 | P43 | P45 | P47 |
| `docs/USABILITY_SCRIPT.md` | — | P44 | P46 | — |
| `CREDITS.md` (new) | P41 | — | P46 | P47 (linked from `README.md`) |
| `docs/plans/FOLLOWUPS.md` | any package, its own section (append only) | | | |

P44 needs no `screen_stack.gd` or `ui_screen.gd` edit: M9's footer already shows the top screen's
`nav_hint()` (VERIFIED (code) on `pkg/P39f`), which `CreatorScreen` overrides.

### 1.6 Shared edits inside W25

P41 and P42 share no file except `docs/plans/FOLLOWUPS.md` (each appends its own section). P42 owns
every code hotspot of W25; P41 owns `tools/build_scenes.gd` (one BUILDERS line before `player.gd`),
`tools/check.sh` (`--giant`, `--giant-full`, `--require`, `--strict-times`), `export_presets.cfg`
(the Web presets exclude `assets/giant/manifest.json` and `assets/giant/tex_hi/*`),
`tools/pck_files.py` and `tools/build_web.sh` (`GIANT_SHARE`), `tests/unit/test_ship_docs.gd`,
`CREDITS.md` and `docs/PERFORMANCE.md` (its rows).

### 1.7 Test tiers and budgets in M10

The default tier is the scarce one: 56–88 s against 75 s in the last twelve recorded runs, with ±20 %
between two runs of one commit on this shared machine (VERIFIED, `suite_times.txt`). On the 0.9.0-m9 base
it ran 78.3 and 79.8 s in two runs on the quiet machine, already over 75 s before any M10 suite
(re-checked on 0.9.0-m9, §7). M10's rules:

1. **Caps per package** (default / slow / gate): P41 0.4 s / 5 s / 0; P42 0.6 s / 20 s / 0; P43
   0.6 s / 45 s / 6 min; P44 0.8 s / 40 s / 0; P45 0.1 s / 10 s / 0; P46 0.1 s / +10 s inside P44's
   option check / 0. With the every-script compile check (`test_anchors`, about 0.17–0.20 s per
   3,500 new lines, VERIFIED, P38's doc) M10 adds at most **3.5 s** to the default tier, 130 s to the
   slow tier and 6 minutes to the gate tier. **2 s of the default tier are reserved** for the gate's
   regression tests and P47.
2. **Per-suite accounting.** A package's cost is the sum of its own suites' times from the runner's
   per-suite output plus the change, before and after, in the suites that load the giant (P41 fixes
   the list in its system doc: `test_rig_merge`, `test_growth`, `test_growth_456`,
   `test_camera_review_fixes`, `test_grab_throw`, `test_weapons`, `test_session_flow` and every other
   suite that instances `scenes/player/giant.tscn`, found by grep); the tier's total is recorded but
   not used to judge a package, because two runs of one commit differ by up to a fifth.
3. **The giant costs headless tests nearly nothing by construction**: the skinned layers are off
   headless (decision 6); the model's scene and its textures are held for the whole process by
   `preload` constants and a static texture cache, because a cache miss costs about 19 ms per load
   (VERIFIED, planner); headless, `GiantLook` sets visibility and stores the look but builds no
   materials unless the layers are on; instancing costs 0.15–0.28 ms (VERIFIED, planner).
4. **Headroom first.** In W25, P42 moves at least 3 s of the heaviest existing default suites (by the
   per-suite times on 0.9.0-m9) to `tests/slow/`, choosing long simulations whose checks other
   default suites repeat, and lists them in its system doc; together with rule 1 the default tier
   then ends M10 no higher than it starts. (Re-checked on 0.9.0-m9: the base already runs 78–80 s, so
   3 s alone leaves the W25 merge's `--strict-times` over 75 s. P42 moves at least 3 s and as much more
   as its own two runs show is needed for the faster run of the W25 merge, with P41's and P42's own
   1.0 s, to stay under 75 s: about 6–7 s on the re-check's runs. The per-suite and per-test times and
   the candidates are in `<scratchpad>/m10/w25/recheck/heaviest_default_suites.md`, §7.)
5. **`--strict-times`** (P41 adds it to `check.sh`, which today only warns): when the default tier
   takes over 75 s or the slow tier over 8 minutes, the tier runs once more and the faster run
   decides; both runs are recorded. Every wave merge and the gate run with it.
6. **Rendered checks** (shader compiles, option renders, first-person views, tip matching on screen)
   run in a child Godot under `xvfb-run` with `--rendering-driver opengl3` (the pattern of
   `test_rig_draw_calls`), at 320x240 where the check allows, with the render loop off between
   captured frames; without `xvfb-run` they skip with a note, which `--require` turns into a failure.
   The per-frame cost of the real model is measured at the W25 merge (P42's rendered suite) and P43
   sets its caps from it; stages 4 and 6 render in the gate tier.

---

## 2. Shared contracts

SI units (m, s; degrees in data, radians in code). Every data record carries `schema_version: 1`, a
stable dotted `id` and a `type`; one record per JSON file under `data/<folder>/` (two levels at most:
the export filter is `data/*.json, data/*/*.json`). Signatures are GDScript 4.6.

### 2.1 Folders and owners

| Folder or file | New contents (owner) |
| --- | --- |
| `tools/giant/` | `requirements.txt`, `setup_venv.sh`, `README.md`, `fetch_mpfb2.py` (the audit), `mpfb2/` (the vendored CC0 subset with `LICENSE.md`, `SOURCE.md` and a `.gdignore`), `kit/` (`mh_data.py`, `giant_body.py`, `giant_skin.py`, `giant_hair.py`, `giant_garment.py`, `designs.py`, `node_util.py`, `skin_textures.py`, `export_game.py`, `bake.py`, `pack.py`), `build_giant.py`, `manifest.py`, `test_giant_tools.py` (P41); `kit/clips.py` (P43); content parameters (P46) |
| `assets/giant/` | `giant.glb`, `tex/` (the Web tier: every map at 512 px), `tex_hi/` (desktop-only 1024 px normal and ORM), `designs.png` (the design array), `hair_*.png` (card atlases), `cloth_*.png` (detail maps), `manifest.json`, `PROVENANCE.md`, their `.import` files (P41; P46 regenerates); `giant_clips.glb` (P43) |
| `assets/shaders/` | `giant_skin.gdshader`, `giant_hair.gdshader`, `giant_eye.gdshader`, `giant_cloth.gdshader` (P42; P46 tunes) |
| `scenes/player/` | `giant_model.tscn` from the builder `tools/builders/giant_model.gd` (P41); `giant.tscn` regenerated with the skinned body (P43) |
| `scripts/presentation/` | `giant_model.gd` (`GiantModel`, P41); `giant_look.gd` (`GiantLook`), `tip_matching.gd` (`TipMatching`) (P42); `skinned_rig.gd`, `pose_brain_modifier.gd` (P43) |
| `scripts/progression/appearance.gd` | `Appearance`: the record's rules (P42) |
| `scripts/actors/player/player_appearance.gd` | `PlayerAppearance`, a `PlayerComponent` (P42) |
| `scripts/core/schemas/` | `appearance_set_schema.gd`, `appearance_preset_schema.gd` (P42) |
| `scripts/debug/capture_m10.gd` | the capture tour scenario (P43) |
| `data/appearance/` | `set_<category>.json` (13 sets) and `preset_<key>.json` (8 presets) (P42; P46 adds options and revises presets) |
| `data/tutorial/` | `appearance_shrines.json`, `appearance_mark.json` (the one-time messages, P42) |
| `ui/screens/creator/` | `creator_screen.gd`, `giant_preview.gd`, `option_rows.gd` (P44) |
| `ui/screens/shrine/appearance_tab.gd` | the Appearance tab (P44) |
| `tools/character_sheet.gd` | the character sheets (P44) |
| `tools/web/` | `creator_check.mjs`, `test_creator_check.mjs` (P45) |
| `tests/fixtures/saves/` | `v2_appearance.json`, `v2_appearance_unknown_ids.json`, `v2_appearance_broken.json`, `v2_appearance_future.json` (P42) |
| `CREDITS.md` | the project's credits: the MakeHuman/MPFB2 CC0 data, the build tools, a link to `assets/audio/PROVENANCE.md` (P41; P47 links it from `README.md`) |
| `docs/screenshots/m10/` | sheet A (the W26 merge), sheet B (after the gate), the release shots (P47) |

### 2.2 The appearance record and its schema

```json
"appearance": {
  "v": 1,
  "preset": "appearance_preset.wanderer",
  "skin": "skin.ruddy",
  "eyes": "eyes.grey_green",
  "hair": {"style": "hair.long_back", "color": "haircolor.chestnut", "grey": 0.12},
  "beard": {"style": "beard.full", "color": "", "grey": 0.2},
  "tattoos": {"arms": "", "chest": "", "back": "", "face": "", "ink": "ink.woad"},
  "paint": {"design": "", "color": "paintcolor.chalk"},
  "scars": [],
  "mark": "auto",
  "outfit": {"set": "outfit.wanderer", "primary": "dye.undyed", "secondary": "dye.dark_leather"}
}
```

| Key | Type | Allowed values | `Appearance.sanitize` |
| --- | --- | --- | --- |
| `v` | int | 1 | cast from a JSON float; missing → 1; **above 1: the whole record is kept untouched** (a later build wrote it), the default look is shown, and the note "This giant's look was made by a newer version of the game; the default look is shown until you change it." |
| `preset` | String | `appearance_preset.<key>` or "" | unknown → "" (used for the summary only) |
| `skin`, `eyes` | String | `skin.<key>`, `eyes.<key>` | unknown, or locked by its `requires` → the set's default, reported |
| `hair.style`, `hair.color` | String | `hair.<key>`, `haircolor.<key>` | idem |
| `hair.grey`, `beard.grey` | float | 0–1 | clamped; not a number → 0 |
| `beard.style` | String | `beard.<key>` | default, reported |
| `beard.color` | String | `haircolor.<key>`, or "" for the hair's colour | unknown → "", reported |
| `tattoos.arms`, `.chest`, `.back`, `.face` | String | a `tattoo.<key>` whose `region` is that region, or "" | unknown or in the wrong region → "", reported |
| `tattoos.ink` | String | `ink.<key>` | default |
| `paint.design` | String | `paint.<key>` or "" | unknown → "", reported |
| `paint.color` | String | `paintcolor.<key>` | default |
| `scars` | Array of String | unique `scar.<key>`, at most 4 | unknown dropped (reported), duplicates removed, truncated to 4 |
| `mark` | String | "auto" or "none" | anything else → "auto" |
| `outfit.set`, `.primary`, `.secondary` | String | `outfit.<key>`, `dye.<key>` | default, reported |
| any other key | — | — | kept as it is, so a later build's addition survives an older build |

Rules:
- The record is the optional key `character.appearance`, beside the talents and the ancestry; it is not
  one of `CharacterState.PROGRESSION_KEYS` (the bots compare those across reloads).
- **Absent means the default look.** `Appearance.resolve(character)` returns the record, or the
  `--appearance=` preset's record when the command line names one, or the default preset's record.
  Old saves, fixtures, the bots and every command-line start carry no key; `capture_character_state()`
  writes the key only when the character had one, so the exact comparisons of whole characters in
  today's suites keep passing (VERIFIED (code), creator brief).
- **Only the creator writes it**, always the full record.
- **A look never fails a load, and the player hears about a repair.**
  `Appearance.sanitize(record) -> {"record", "dropped", "notes"}`; `CharacterState.sanitize` passes
  the look's dropped ids and notes up (`{"data", "dropped", "notes"}`), and `SaveSlots.read` joins the
  notes into its message beside the existing "Dropped ids this build does not know: …" line. A block
  that is not a dictionary, or whose fields have the wrong types, becomes the default with "Your
  giant's look could not be read; the default look is used." Validation never sends a save to its
  backup over the look.
- `SaveSlots.SCHEMA_VERSION` stays 2 (a schema 3 file would lock 0.9 players out of Continue, VERIFIED
  creator brief); the header documents the optional key; the record's own `"v"` versions it, with
  `Appearance.migrate()` as its one pure step per version (none needed in M10).

### 2.3 Appearance data: sets, presets and the catalogue

```
appearance_set     {schema_version: 1, id: "appearance_set.<set>", type: "appearance_set", category: "<set>",
                    display_name, options: [{key, name, default?: true, requires?: {"ancestry": "<ancestry id>"},
                                             ...the category's fields}]}
appearance_preset  {schema_version: 1, id: "appearance_preset.<key>", type: "appearance_preset", display_name,
                    description, ancestry?: "<ancestry id>" (a suggestion only), appearance: {a full record}}
```

An option's id in the record is `<set>.<key>` (`hair.long_back`). Category fields: `color` ("#rrggbb",
sRGB) for skin, eyes (with `glow`), haircolor (with `tip`), ink, paintcolor, dye and mark (with
`glow`); `mesh` (a giant index mesh id; "" for none) and `scalp_tint` for hair; `mesh`, `stubble` and
`beard_tint` for beards; `design` (a giant index design id) and `region` (arms, chest, back or face)
for tattoos and paint; `design` for scars and marks; `garments` (giant index garment ids) for outfits.
Validation: unknown keys are errors (as for every record); keys unique in a set; exactly one default
in each set except tattoo, paint, scar and mark (none); colours parse; a preset's record passes
`Appearance.sanitize` with nothing dropped (GameData post-pass at P42's anchor); every `mesh`, `design`
and garment id exists in the giant index (a test reads the index from `giant_model.tscn`).

**The catalogue.** The *floor* is made in W25 (content by P41, data by P42) and its ids are fixed here,
so the two packages can work side by side; the *target* is P46's in W27, after the owner has played
the floor. Giant index ids: meshes `Hair_<key>`, `Beard_<key>`; designs `tat_<key>`, `paint_<key>`,
`scar_<key>`, `mark_<key>`; garments by their key.

| Set | Floor (W25) | Target adds (W27, P46) |
| --- | --- | --- |
| `skin` | `pale`, `fair`, `ruddy` (default), `tan`, `olive`, `bronze`, `brown`, `deep`, `weathered`, `ashen` (requires Stoneblood) | — |
| `eyes` | `grey_green` (default), `blue`, `grey`, `green`, `hazel`, `brown`, `dark`, `ice`, `storm` (requires Stormborn; a slight glow), `amber` (requires Wildheart) | — |
| `hair` | `shaved` (no mesh; scalp tint), `crop` (`Hair_crop`), `long_back` (`Hair_long_back`; default) | `long_braided`, `warrior_tail`, `wild_mane` |
| `beard` | `none`, `stubble` (no mesh; the stubble mask), `short` (`Beard_short`), `full` (`Beard_full`; default) | `braided`, `forked` |
| `haircolor` | `black`, `dark_brown`, `brown`, `chestnut` (default), `auburn`, `copper`, `red`, `dark_blond`, `blond`, `white` | — |
| `tattoo` | arms `arm_bands` (upper arm), `arm_chevrons` (forearm); chest `chest_spiral`, `chest_knot`; back `back_wings`, `back_tree` (large back pieces); face `face_lines`, `face_dots` | 8 more, 2 per region (16), among them a full sleeve and a shoulder-to-shoulder piece |
| `ink` | `woad` (default), `soot`, `ochre`, `chalk`, `moss`, `iron` | — |
| `paint` | face `face_stripes` (stripes under the eyes and a brow band: the research's face paint), arms `shoulder_bands` (three broad bands over the shoulders and upper arms) | face `full_face`, back `back_hand` (a hand print between the shoulder blades) |
| `paintcolor` | `chalk` (default), `ochre`, `woad`, `blood`, `ash`, `soot` | — |
| `scar` | `brow`, `forearm_slash`, `chest_claws`, `knuckles` | `cheek`, `back_lash` |
| `mark` | `granite_veins` (shoulders and forearms; requires Stoneblood), `lightning_tree` (back and arm; Stormborn), `claw_stripes` (cheek, chest and the outer upper arm; Wildheart) | — |
| `outfit` | `wanderer` (braies, belt; default), `hunter` (braies, belt, furs, bracers), `warrior` (tunic, jerkin, belt, bracers, boots), `chieftain` (braies, belt, furs, jerkin, boots) — over the garments `braies`, `belt`, `tunic`, `jerkin`, `bracers`, `boots`, `furs` | 1–2 outfits over up to 3 new garments (P46 names them, for example a cloak, a kilt, leg wraps) |
| `dye` | `undyed` (default primary), `dark_leather` (default secondary), `madder`, `woad_blue`, `weld_yellow`, `moss_green`, `walnut`, `bone` | — |
| presets | `wanderer` (the default and the owner-approved render: long chestnut hair, a full beard, braies), `stone_elder`, `storm_herald`, `wild_hunter`, `iron_veteran`, `young_giant`, `ash_raider`, `northern_chieftain` — floor content only | revised with the target content |

The floor: 3 hair styles, 4 beard choices, 10 hair colours, 10 skin tones, 10 eye colours (2 locked),
8 tattoos, 2 war paints, 4 scars, 3 marks, 4 outfits, 8 dyes, 8 presets. The target: 6 hair styles,
6 beard choices, 16 tattoos, 4 war paints, 6 scars, 5–6 outfits, sized to the budget of §2.12. Height
is never a choice; there are no face or build sliders (§0.4).

**Design rules (reading in play, decision 18).** Every design category (tattoo, paint, scar, mark)
has at least one option that changes the stage-1 rear third-person view or the first-person view
above the floor of P44's rendered check; strokes are at least 4 cm wide at stage 1 (about 4 px at the
default camera, VERIFIED owner review's numbers); pieces favour the shoulders, upper back, upper arms
and forearms, which the camera sees; a design whose region the current outfit covers is shown by the
creator as "Hidden by your clothing" (§2.10). Of the floor, `arm_bands`, `arm_chevrons`,
`back_wings`, `back_tree`, `shoulder_bands`, `forearm_slash`, `knuckles`, `granite_veins` and
`lightning_tree` are drawn to pass the rear or first-person floor.

### 2.4 The look: `Appearance.to_look` → `GiantLook.apply`

The one interface between the rules and every renderer of the giant (the player's rig, the creator's
preview, the character sheets). Both sides are P42's, so the default look and the data that must equal
it are written in one package:

```gdscript
# Pure; reads the appearance records: the concrete look of a record for a chosen ancestry.
static func to_look(record: Dictionary, ancestry_id: String) -> Dictionary          # Appearance
# Shows and hides meshes and sets uniforms on one model instance (its root and its index, §2.5).
# Unknown ids are skipped; validate() lists them and every uniform name that the shader does not
# declare (get_shader_uniform_list()). Never an engine error.
static func build_materials(root: Node3D, index: Dictionary, tier: String) -> void  # GiantLook
static func apply(root: Node3D, index: Dictionary, look: Dictionary) -> void
static func validate(root: Node3D, index: Dictionary, look: Dictionary) -> PackedStringArray
```

`GiantLook` reads the index format, not the `GiantModel` class, so P42 can test it in W25 on a
synthetic model built from a small index, and every caller passes `model, model.index`.

| Look key | Type | Meaning |
| --- | --- | --- |
| `skin_tone` | Color (sRGB) | the skin's colour; the shader scales the baked albedo by tone / bake tone |
| `eye_color`, `eye_glow` | Color, float | the iris; emission 0–1 (the Stormborn eyes) |
| `hair_mesh`, `beard_mesh` | String | index mesh ids shown ("" = none); every other hair and beard mesh is hidden |
| `hair_color`, `hair_tip`, `hair_grey` | Color, Color, float | the cards' colour, sun-bleached tips, the grey strand fraction |
| `beard_color`, `beard_grey` | Color, float | the beard's (the hair's when the record's `beard.color` is "") |
| `scalp_tint`, `stubble`, `beard_tint` | float | the hair colour on the scalp (under hair, and for shaved), the stubble's strength, the beard colour on the skin under the cards |
| `tattoos` | Array of {`design`: String, `ink`: Color} | index design ids, one ink for all |
| `paint` | {`design`, `color`} or {} | war paint, drawn on top |
| `mark` | {`design`, `color`, `glow`} or {} | the ancestry mark (`mark: "auto"` resolved with the ancestry) |
| `scars` | Array of String | index scar ids, at most 4 |
| `garments` | Array of String | index garment ids shown; the covered regions sink under them (`hidden_regions` from the index's `covers`) |
| `dye_primary`, `dye_secondary` | Color | each garment takes the dye of its slot |

**`GiantLook.DEFAULT_LOOK` — the Wanderer, pinned now** (the research palettes, VERIFIED, revision,
`creator_lab/proj/creator_lab.gd`), so the model draws before and without the data and the data's
values are fixed:

| Look key | Value | The data that must give it |
| --- | --- | --- |
| `skin_tone` | `#b07a62` | `skin.ruddy.color` |
| `eye_color`, `eye_glow` | `#4c7361`, 0.0 | `eyes.grey_green` |
| `hair_mesh`, `beard_mesh` | `Hair_long_back`, `Beard_full` | `hair.long_back.mesh`, `beard.full.mesh` |
| `hair_color`, `hair_tip`, `hair_grey` | `#4a2c1a`, `#6e4a30`, 0.12 | `haircolor.chestnut` (`color`, `tip`); the record |
| `beard_color`, `beard_grey` | `#4a2c1a`, 0.2 | the hair's colour (`beard.color` ""); the record |
| `scalp_tint`, `stubble`, `beard_tint` | 1.0, 0.8, 1.0 | `hair.long_back.scalp_tint`; `beard.full.stubble`, `beard.full.beard_tint` |
| `tattoos`, `paint`, `mark`, `scars` | [], {}, {}, [] | the record (no ancestry yet) |
| `garments` | [`braies`, `belt`] | `outfit.wanderer.garments` |
| `dye_primary`, `dye_secondary` | `#73614a`, `#2a2622` | `dye.undyed`, `dye.dark_leather` |

P42's test requires `to_look(<the default record>, "")` to equal `DEFAULT_LOOK` key by key, colours
within 1/255 per channel and numbers within 1e-4 (hex-parsed and literal colours differ in the last
bit).

### 2.5 The giant asset: files, pipeline, manifest, index and import settings

**The pipeline** — `tools/giant/build_giant.py [--body] [--garments] [--hair] [--bake] [--designs]
[--pack] [--clips] [--all] [--verify] [--skip-bake] [--no-cache] [--budget] [--out=DIR]`, run with the
venv's Python (`$GIANT_VENV/bin/python`) under `nice -n 19`:

| Step | Does |
| --- | --- |
| `--body`, `--garments`, `--hair` | build the kit's giant at 3.6576 m on the game_engine rig, strip render modifiers, split the body into head, torso and limbs and each spanning garment into core and limbs (§2.6), cap every cut loop, write the region ids, grow the hair and beard cards on the unsubdivided surface, export every mesh on one armature into `assets/giant/giant.glb`, and write the landmarks into the manifest |
| `--bake` | Cycles selected-to-active bakes from the kit's procedural skin at 1024 px, 2 threads, seed 0. The cheap passes (about 2.3 minutes, VERIFIED log): albedo at the neutral tone, tangent normal, roughness, masks (stubble, scalp, brows, lips), scars, and the rest position and rest normal (EXR, into `GIANT_CACHE` only). The expensive passes (about 11 minutes): AO and inside-AO thickness |
| `--designs` | draw every tattoo, war paint, mark and scar as distance fields in 3D on the rest pose (seam-free) and pack them into the layers of `designs.png` under the packing rule below |
| `--pack` | write the Web tier (`tex/`: albedo, normal, ORM, masks at 512 px) and the desktop tier (`tex_hi/`: normal and ORM at 1024 px, the ORM holding AO, roughness and thickness at full precision), resizing masks one channel at a time (Pillow's RGBA resize premultiplies and wiped the RGB channels of the research's 512 px masks, VERIFIED creator brief), the hair atlases and the cloth detail maps |
| `--clips` (P43) | write the computed-keyframe clips into `assets/giant/giant_clips.glb` |
| `--verify` | regenerate everything into a temporary folder and compare with `manifest.json`: bit-exact on the reference toolchain; for Cycles outputs on another toolchain at most 2/255 per channel and 0.1/255 on average; report "toolchain differs" apart from "content differs" |
| `--skip-bake` | with `--verify` (what `check.sh --giant` runs): run the cheap bake passes, read AO and thickness back from the committed `tex_hi/orm.png` (R and B, 8-bit, lossless), and regenerate and compare every output — meshes, hair, designs, both tiers, atlases; it also checks that the expensive passes' inputs (the body mesh and UVs, the skin code, the settings) still hash to the manifest's, and asks for `--giant-full` when they do not |
| `--budget` | estimate each output's shipped size from the measured rates and fail over the giant share of §2.12 (the real number comes from a Web export: P41 at W25, the W26 preview build, P45) |

`GIANT_CACHE` (default `$HOME/.cache/giantborn/giant-cache`, shared by every worktree,
content-addressed) keeps the bakes and the rest maps between runs, so a design-only change re-bakes
nothing; `--no-cache` ignores it. `manifest.json` records per output its path, step, inputs (the
hashes of the vendored files, the kit modules and the parameters), sha256 and size, plus the
toolchain (Python, bpy, numpy, scipy, Pillow and OpenEXR versions, CPU flags), the body's hash (the
freeze of decision 9) and the landmarks; it is excluded from the Web presets like the audio manifest.

**The packing rule for `designs.png`** (VERIFIED need, feasibility review's compressor probe): the
array's layers are 512x512 RGBA, imported VRAM-compressed (DXT5; RGB share one colour block per 4x4
texels, A has its own). Within one layer, the UV area of any region carries a design in at most one of
R, G and B, plus at most one in A; designs in different regions' areas may share a channel. `--designs`
assigns layers and channels greedily under this rule (about 4–5 layers for the floor, 6–8 for the
target, ASSUMED), and P41's slow suite round-trips every layer through Godot's S3TC compressor
(`Image.compress`) and fails when a design's mean error over its own texels exceeds 0.05 or another
design shows through at a mean above 0.05. One sampler whatever the count. 512 px is ASSUMED sharp
enough for the bold designs of §2.3; P44's option check at the Face and Tattoo framings is the test,
and the fallback is a desktop-only 1024 px copy (`tex_hi/designs.png`).

**The CC0 inputs.** `tools/giant/mpfb2/` vendors the subset the pipeline reads: the hm08 `base.obj`,
the targets used, `target.json`, the game_engine rig and weights, the default rig and weights while
the region masks still need them, the region mask images and the licence: 136 files, 9,960,994 bytes
raw, about 4.5 MB compressed in git (VERIFIED, asset brief). Porting the region masks to the
game_engine bones lets P41 drop `sss.png` and the default weights (−3.1 MB raw, VERIFIED asset brief).
A `.gdignore` keeps Godot from importing the folder (it imported `base.obj`, a JPEG and a PNG there
into 4.0 MB, VERIFIED feasibility review), and `test_ship_docs` skips it (its 4.98 M characters of
JSON cost 43–55 ms a run, VERIFIED process review). `fetch_mpfb2.py` re-extracts the subset from the
wheel `anny-0.6.2-py3-none-any.whl` (47,711,600 bytes, sha256
`bad70bdc2be0dfa9880d60129c3a1339678f08f493184f637dc2825c3e27b8d2`, VERIFIED asset brief on the local
copy; its download address ASSUMED) and compares file by file — an audit, not part of `--verify`,
which needs no network.

**Provenance** (`assets/giant/PROVENANCE.md`, and `CREDITS.md`): the body, skeleton and weights derive
from MakeHuman/MPFB2 data released CC0 (the base mesh's own CC0 statement; the weights files'
`"license": "CC0"`), extracted as data from the named wheel, whose Apache-2.0 code was read only as a
reference by the research run and is not copied; every texture, card, garment, design, clip and
shader is generated by the committed code; Blender (as `bpy`, GPL-3.0-or-later), numpy, scipy, Pillow
and OpenEXR are build tools and are not redistributed; the licence of the project's own assets stays
the owner's choice (CC0 inputs fit any).

**The giant index** — written by the builder `tools/builders/giant_model.gd` from `manifest.json` into
`scenes/player/giant_model.tscn` as the root's exported `index`, so it ships inside the scene:

```
index = {
  "meshes":    {"<mesh id>": {"node": "Garment_tunic_core", "category": "body|eyes|hair|beard|garment",
                              "layer": 1, 2 or 3, "dye": "primary|secondary|none", "covers": [region ids], "tris": int}},
  "garments":  {"<garment id>": ["<mesh id>", ...]},        # a garment split at the boundary has two meshes
  "designs":   {"<design id>": {"layer": int, "channel": 0..3, "kind": "tattoo|paint|mark|scar", "regions": [region ids]}},
  "regions":   [{"id": 0, "name": "scalp"}, ...],
  "landmarks": {"shoulder_r": [x, y, z], "elbow_r": ..., "wrist_r": ..., "palm_r": ..., (and _l), "hip_r": ...,
                "knee_r": ..., "ankle_r": ..., "eye_mid": ..., "reach_r": float, "reach_l": float},  # stage 1, game frame (-Z forward)
  "defaults":  {"shown": ["Body_Head", "Body_Torso", "Body_Limbs", "Eyes", "Hair_long_back", "Beard_full", ...]},
  "tiers":     {"web": "res://assets/giant/tex/", "hi": "res://assets/giant/tex_hi/"},
  "manifest_sha256": "..."
}
```

**Edits inside the instanced glTF are never saved.** A SceneKit save keeps nothing set on a node inside
an instance (render layers, visibility, material overrides, added children; VERIFIED feasibility
review's probe), so `GiantModel._ready()` applies each mesh's layer and the default visibility from
`index`, and the skinned rig creates its animation and modifier nodes at run time (§2.9); tests check
the scene as reloaded from disk.

**Import settings** (committed `.import` files; P41's asset suite checks the key ones):

| File | Importer | Settings |
| --- | --- | --- |
| `giant.glb` | scene | `meshes/generate_lods=true`, `meshes/create_shadow_meshes=true`, `meshes/ensure_tangents=true`, `skins/use_named_skins=true`, `animation/import=false` |
| `giant_clips.glb` (P43) | animation_library | `animation/import=true`, `animation/fps=30`, `animation/remove_immutable_tracks=true`; loops are set in code (imported clips have loop off, VERIFIED planner) |
| `tex/*.png`, `tex_hi/*.png`, `hair_*.png`, `cloth_*.png` | texture | VRAM compressed, mipmaps; normal maps as normal maps (RGTC); albedo sRGB |
| `designs.png` | 2d_array_texture | `slices/vertical` = the layer count, `compress/mode=2` (VRAM), mipmaps (VERIFIED planner: imports as a `CompressedTexture2DArray`, DXT5) |

### 2.6 Meshes, regions, render layers and the bone contract

| Mesh node (children of the one `Skeleton3D`, bound by bone name) | Render layer | Contents |
| --- | --- | --- |
| `Body_Head` | 3 | scalp, face, neck; the neck cut capped |
| `Body_Torso` | 2 | chest, belly, back, pelvis; the neck, shoulder and hip cuts capped |
| `Body_Limbs` | 1 | arms, hands, thighs, knees, shins, feet; the shoulder and hip cuts capped, so the mesh is closed |
| `Eyes` | 3 | both eyes in one mesh; the iris is drawn by the shader |
| `Hair_<style>`, `Beard_<style>` | 3 | cards, every vertex weighted to `head` |
| `Garment_<id>`, or `Garment_<id>_core` and `Garment_<id>_limbs` | 2 or 1 | a garment that spans the boundary is split along it (the tunic's skirt and the braies' legs are limbs); its cut loops capped in the garment's inside colour |

A cap is the cut loop filled with a fan of triangles, weighted 100 % to the bone on its own side of
the cut (the limb's `upperarm` or `thigh`, the torso's `clavicle` or `pelvis`, `neck_01` on both sides
of the neck) and given region 15, so it shades as plain skin (or cloth, on a garment's cap) when seen
from inside in first person (the hip cut enters the view at a pitch of −75° at
stage 1 and −60° at stages 4–6, VERIFIED owner review) and when the third-person camera is pressed
close. The split keeps the joined mesh's normals so no seam shows in third person (ASSUMED technique,
animation brief); per-mesh LODs keep the seam closed (VERIFIED feasibility review). P41's tool test
requires `Body_Limbs` and every limb garment part to have no open boundary edge.

**Regions** — stored per vertex in `COLOR_0.r` as (id + 0.5) / 16 and decoded in the shader as
`int(COLOR.r * 16.0)` (rounding would be wrong; VERIFIED creator brief for 12 regions; 16 is P41's
extension, ASSUMED straightforward: the front and back of the torso are told apart on the rest pose
by the spine's plane):

| Id | Region | Design region | Mesh |
| --- | --- | --- | --- |
| 0 | scalp (top and back of the head) | — | head |
| 1 | face | face | head |
| 2 | neck | — | head |
| 3 | chest | chest | torso |
| 4 | belly | chest | torso |
| 5 | upper back | back | torso |
| 6 | lower back | back | torso |
| 7 | pelvis | — | torso |
| 8 | upper arm | arms | limbs |
| 9 | forearm | arms | limbs |
| 10 | hand | (scars only) | limbs |
| 11 | thigh | — | limbs |
| 12 | knee | — | limbs |
| 13 | shin | — | limbs |
| 14 | foot | — | limbs |
| 15 | caps (the inside of every cut) | — | all three |

**Bones** — MPFB2 game_engine, 53 (VERIFIED planner, `rig.game_engine.json`): `Root`; `pelvis`,
`spine_01`, `spine_02`, `spine_03`, `neck_01`, `head`; and per side (`_l`, `_r`): `clavicle`,
`upperarm`, `lowerarm`, `hand`, `thumb_01`–`03`, `index_01`–`03`, `middle_01`–`03`, `ring_01`–`03`,
`pinky_01`–`03`, `thigh`, `calf`, `foot`, `ball`. No face or eye bones. Four weights per vertex (the
strongest of up to six or seven). The clips drive the pelvis, legs and fingers; the modifier drives
`spine_01`–`03`, both `clavicle`, `upperarm`, `lowerarm` and `hand`.

**Landmarks** — the index's `landmarks` are the exported skeleton's joint positions at stage 1 in the
game frame; `TipMatching` reads them, and the W25 merge re-runs the reach statistics on them (the
animation brief measured its numbers on its own lab body, VERIFIED animation brief: `export_test_giant.py`
built from the live kit).

**Orientation and scale**: the glTF faces +Z; `GiantModel` turns it 180° about Y so it faces -Z like
every actor; it is built at 3.6576 m (stage 1) and `Visual/Body` scales it by k as today.

### 2.7 What gameplay reads (unchanged), and what may read the skinned body

| Anchor | Where it comes from | Read by |
| --- | --- | --- |
| Body capsule (r 0.85, h 3.66, ×k) | `BodyShape` | physics, the growth clearance |
| Lock anchor (0, 2.3, 0)·k | `Anchors/Torso` | lock-on, enemy aims, camera framing |
| Hurtboxes Legs, Torso, Head | `Hurtboxes/*` (static boxes, ×k) | HitFactory, enemy sweeps (their `region` field is read by nothing, VERIFIED (code), animation brief) |
| Weapon sweep | the profile pivot (0.82, 2.9, 0)·k + the `AttackGeometry` direction × [1.5·k, 1.5·k + weapon length] | `PlayerAttack.weapon_segment_global()` |
| Attack origin (0, 2.6, 0)·k | the growth profile | AttackRunner's occlusion test |
| Grab sockets | `PlayerGrab.SOCKETS` × k | PlayerGrab (the held body is placed there every tick) |
| Camera geometry | `camera_pivot_height_m` (3.35·k); first-person eye at 0.92 × height and 0.18 m forward; the pressed-close rule | CameraRig (only its culling masks change, decision 8) |
| Footfalls | `ActorRig.footfall`, from the brain's walk phase | footstep audio and camera shake (presentation) |

Rules, each a code-rule test:
- Nothing under `scripts/combat/`, `scripts/ai/`, `scripts/world/`, `scripts/quests/`,
  `scripts/core/sim.gd` or the player components other than `PlayerAppearance` names `Skeleton3D`,
  `get_bone_`, `GiantModel`, `GiantLook`, `SkinnedRig`, `PoseBrainModifier`, `WeaponSocket`,
  `AnimationTree`, `TipMatching` or `appearance` (P42 owns the `appearance` rule, P43 the rest). None
  of these words appears there today, and `Skeleton3D`, `AnimationTree` and `WeaponSocket` appear
  nowhere under `scripts/` or `ui/` (VERIFIED, planner grep at `1c33b8e`), so the rules start green.
- `SkinnedRig` and `PoseBrainModifier` write only under their own `Visual` node and, during a hold,
  to the held body's `Visual.position`, which they restore when the hold ends or the body is freed.
  The skin may read gameplay state (the rig state, `is_on_floor()`), never the other way round.

### 2.8 Shader parameters

Every giant shader has `uniform vec4 tint` (a status tint: rgb colour, a strength; written by
`RigPaint`) and `uniform vec3 flash` (the hit-flash emission; `RigPaint`). `GiantLook.validate()` and
P42's tests compare every name `GiantLook` sets with `get_shader_uniform_list()` (a headless material
accepts a misspelled name silently, VERIFIED feasibility review).

`giant_skin.gdshader` (`Body_Head`, `Body_Torso`, `Body_Limbs`):

| Uniform | Type | Set by |
| --- | --- | --- |
| `albedo_tex`, `normal_tex`, `orm_tex` (R AO, G roughness, B thickness), `mask_tex` (R stubble, G scalp, B brows, A lips) | sampler2D | `GiantLook`, by tier |
| `design_tex` | sampler2DArray (a `CompressedTexture2DArray`, typed `TextureLayered` in code) | `GiantLook` |
| `skin_tone`, `bake_tone` | vec3, source_color | the look; the constant (0.69, 0.53, 0.44) |
| `hair_color`, `beard_color` | vec3, source_color | the look |
| `stubble`, `scalp_tint`, `beard_tint`, `brows` | float 0–1 | the look |
| `region_tattoo[16]`, `region_paint[16]`, `region_mark[16]` | int: layer × 4 + channel + 1, **0 for none** | the look; uniform arrays take no defaults in 4.6.3 shaders (VERIFIED creator brief), so 0 must mean none and `GiantLook` always fills them |
| `tattoo_ink`, `paint_color`, `mark_color` | vec3, source_color | the look |
| `mark_glow` | float | the look |
| `scar_layer`, `scar_on` | int, vec4 | the look (one RGBA layer of four scars; P46 adds `scar_layer_b`, `scar_on_b` for scars 5–6) |
| `hidden_regions` | int, one bit per region | from the shown garments |
| `hide_shrink` | float, 0.03 m in model space | constant |
| `light_model` (0 Lambert, 1 wrap, 2 wrap and transmission), `wrap`, `sss_color`, `transmission`, `rough_scale` | | tuned constants |

`giant_hair.gdshader` (`Hair_*`, `Beard_*`; depth pre-pass with a blended fringe): `hair_atlas`,
`hair_color`, `tip_color`, `grey`, `spec_shift`, `alpha_boost`; P46 may add `length` (cards cut along
their root-to-tip coordinate: 2–3 lengths per mesh at no pack cost) and `head_motion` (a sway from
the head's velocity, which `SkinnedRig` writes each frame when the uniform exists).
`giant_eye.gdshader` (`Eyes`): `iris_color`, `iris_glow`, `pupil_size`. `giant_cloth.gdshader`
(`Garment_*`): `detail_tex` (a tileable weave or leather map with mipmaps, replacing the research
shader's procedural weave that moirés at a distance, VERIFIED asset brief), `dye_color`,
`detail_strength`, `normal_strength`, `fade` (0–1, the creator's "hidden by clothing" fade).

### 2.9 The skinned rig

The player's scene after P43 (`scenes/player/giant.tscn`); the nodes marked "run time" are created by
`SkinnedRig` when the layers are on and are never saved (§2.5):

```
Giant (CharacterBody3D, giant_player.gd)                    unchanged
├─ BodyShape, CombatEntity, Anchors/Torso, Hurtboxes/*      unchanged (§2.7)
├─ Visual (SkinnedRig)                                      was ActorRig
│  ├─ Body (scale k)                                        leans, staggers and falls as today
│  │  ├─ HipL, HipR, Torso, ShoulderL, ShoulderR            the brain's pivots, kept, no meshes
│  │  │  └─ ShoulderL/Hand, ShoulderR/Hand                   markers: the brain's hand points
│  │  ├─ Model (GiantModel: an instance of giant_model.tscn, turned 180°)
│  │  │  ├─ (imported) Skeleton3D
│  │  │  │  ├─ Body_Head, Body_Torso, Body_Limbs, Eyes, Hair_*, Beard_*, Garment_*
│  │  │  │  └─ PoseBrainModifier (SkeletonModifier3D)       run time
│  │  │  ├─ AnimationPlayer (library "giant")                run time
│  │  │  └─ AnimationTree                                    run time
│  │  └─ WeaponSocket (Node3D)                               saved; the weapon visual's parent, placed in the fist
└─ CameraRig/Camera3D                                       unchanged geometry; masks for layers 2 and 3
```

```gdscript
class_name SkinnedRig extends ActorRig     # scripts/presentation/skinned_rig.gd (P43)
signal posed                               # after the modifier ran (from skeleton_updated); tests read final poses here
static func enable_for_tests() -> void     # the layers on in a headless test, until reset_for_tests (ResetHooks)
static func reset_for_tests() -> void
static func layers_enabled() -> bool       # a display, --skin, or enable_for_tests; never with --no-skin
func model() -> GiantModel
func apply_look(look: Dictionary) -> void  # GiantLook.apply on the model; PlayerAppearance calls it
func weapon_socket() -> Node3D
func visible_weapon_segment() -> Array     # [grip, tip] in global space; valid inside `posed`
func palm_global(left: bool) -> Vector3    # valid inside `posed`
func skin_stats() -> Dictionary            # look id, posed frames, modifier runs, held-visual writes, shown meshes, rig footfalls
```

**One frame, in order:**
1. `ActorRig._process` — the unchanged brain: `_arm`, `_off`, the torso twist, the leg phase, body
   lean and fall, the walk phase, footfalls.
2. The `AnimationTree` (a BlendTree built in code), with the legs' source chosen from the brain's
   state, never from speed alone (the brain walks only in `LOCOMOTION` and `BLOCKING`):
   - **the brain walks** (speed > 0.3 in `LOCOMOTION` or `BLOCKING`): `idle` | `TimeSeek(walk)` |
     `TimeSeek(run)` blended by normalized speed (speed / k: 5.0 at stage 1 down to 1.57 at stage 6,
     VERIFIED animation brief), the time set from the brain each frame as
     `fposmod(_walk_phase + π/2, 2π) / 2π × length` so heel strikes fall on the brain's footfalls;
   - **an action's motion moves the giant** (Shoulder Charge, lunges: the action has a `motion` block
     and its phase is moving): the run clip on the skin's own clock, advanced by ground speed / stride;
   - **airborne** (`not is_on_floor()` for more than two frames): the airborne pose (legs gathered);
   - **dead**: the idle and locomotion stop; the death clip (knees buckle, the torso slumps) is seeked
     by the body's fall fraction, under today's fall of `Visual/Body`;
   - **otherwise** (dodges, staggers, knockbacks, standing actions): the stance pose (the idle's legs)
     under the body's existing lean, so nothing glides in a frozen stride;
   then `Blend2` grips filtered to each hand's fingers. Footfall audio stays on the brain.
3. `PoseBrainModifier`: the brain's torso twist spread over `spine_01`–`03`; the weapon arm by tip
   matching; the off arm: the brain's off pose mapped to "palm at shoulder + direction × 0.9 × reach"
   while an action, block, dodge or override runs, the clip's arm in plain locomotion; during a grab
   the off palm on the socket when in reach, else its farthest point toward it, and the held body's
   `Visual` moved by the remaining gap (≤ 0.33·k m); `WeaponSocket` placed in the fist along the
   weapon's axis, its scale `effective_weapon_scale / k` as today.
4. Leans, staggers, dodges and the death fall are inherited from `Visual/Body`.

**Tip matching** (`TipMatching`, pure, P42): tip = pivot/k + direction × (arm + weapon)/k in Body
space; the grip = the natural grip (shoulder + direction × 0.93 × reach) moved onto the sphere of
radius weapon length around the tip and projected into reach (alternating projections), or the
farthest reachable point toward the tip; an analytic two-bone solve (elbow pole down, back and out,
tunable per arc side); the hand turned so a diagonal grip axis lies along the weapon;
`idle_grip(family)` gives the resting grip the creator's preview uses. The landmarks come from the
model's index (`TipMatching.from_index(index)`), or from `DEFAULT_LANDMARKS` (the animation brief's
values) where no model exists. **Contract**: over every ACTIVE sample of every player weapon arc at
stages 1, 3, 4 and 6, the visible weapon's outer half lies inside the tested capsule (100 %), at most
15° off the tested direction, the fist within 0.01 m of its target. **Per action** (the animation
brief's table): weapon arcs (fists and the tree included) by tip matching; blocks, dodges, casts,
flexes, sweeps and throws by the generic mapping; grabs by the palm and the held-visual offset;
stomps and roars by the brain's arm poses (the stomp's leg clip is on the cut list).

**Headless default**: when `layers_enabled()` is false the run-time nodes are not created (the
skeleton stays at rest) and `WeaponSocket` follows the brain's `ShoulderR/Hand` marker; the model is
still instanced, so every saved path exists.

**Paint**: `GiantLook.build_materials` gives each instance its own ShaderMaterial copies; `RigPaint`
gains a ShaderMaterial path (the `tint` and `flash` uniforms), so `flash()` and `set_status_tint()`
reach every giant surface while the weapon keeps the StandardMaterial3D path.

**First person and the pressed-close camera**: decision 8; the eye stays inside the hidden head (the
model's eyes are 0.082 m above and 0.064 m ahead of the game's eye at stage 1, VERIFIED animation
brief).

**`SKIN_STATS`**: with `--skin-stats`, the game prints at exit one line
`SKIN_STATS {"look": <preset or "custom">, "layers": bool, "posed_frames": n, "modifier_runs": n,
"held_visual_writes": n, "shown_meshes": [...], "rig_footfalls": n}` for the player's rig; the gate
suite asserts it (§3.3).

### 2.10 The creator's screens and flows

```
ScreenStack.SCREENS["creator"] = "res://ui/screens/creator/creator_screen.gd"     # P42 declares, P44 builds
open("creator", {"context": "new_game", "start": {"mode": "valley" or "world", "options": {...}}})
open("creator", {"context": "shrine", "player": GiantPlayer, "shrine": Shrine, "appearance": Dictionary})
closed(result):  {"appearance": record, "begin": true}    New Game: Begin
                 {"appearance": record}                   shrine: Keep this look
                 {"cancelled": true}                      Back or Cancel (confirmed when the look changed), Esc, pad B
```

**New Game:**
```
Title ── New Game ──┬─ (a save exists) "New Game: replace the saved game?" ── New Game again ─┐
                    ├─ (the prologue is finished) Play the prologue | Skip to the Old Kingdom ─┤
                    └─ (no save) ─────────────────────────────────────────────────────────────┤
                                                                                               v
    CreatorScreen {context "new_game"}    Back → the title as it was; the save untouched
    "Begin your journey" / "Begin in the Old Kingdom" → closed({"appearance", "begin"}) emitted from
    the button's own pressed handler → TitleScreen.start_game(mode, options + {"appearance": record})
    in the same call stack (browsers grant pointer lock only inside the click; VERIFIED (code), the
    title's own comment) → GameSession.change_mode → _begin_new_valley / _begin_new_world store the
    record in the character → reload → the first checkpoint writes the save, as today
```
**The launcher's open-world start**: `--mode=world --creator` (P45 changes the launcher's button)
starts at the title with the creator open for a world start (P42 parses `--creator` into
`GameSession.creator_start`; P44's title opens the creator when it is set); Back leaves the player on
the title. Other command-line New Games (`--mode=valley --new-game`, `--mode=world` without
`--creator`), the bots, the tests and the sandbox never open the creator; `--appearance=<preset id>`
gives them a preset's look in every mode.

**Shrines:** `ShrineScreen.TABS` gains `["Appearance", "res://ui/screens/shrine/appearance_tab.gd"]`
last. The tab shows the look's summary (`Appearance.summary_lines`: "Hair: long, combed back,
chestnut, a little grey", ...) and "Change your look...", which opens the creator over the paused
shrine screen. While the creator is on top the root viewport's 3D is off (it is back on when the
creator closes or another screen covers it). Keep → `player.appearance.set_record(record)`: the live
giant changes, `Events.appearance_changed(tick, entity_id)` fires and GameSession re-takes and writes
the shrine's checkpoint (the F15 list). Cancel restores the look in memory without a write. The tab's
title reads "Appearance (new)" until it is first opened in a save (the `appearance.tab_seen` flag);
players of older saves also get the one-time message of §2.11.

**Layout at 1280x720** (the creator brief's mock-up, VERIFIED inside the window and above the footer):
a title row; the category tabs (Presets, Skin, Eyes, Hair, Beard, Tattoos, War paint, Scars, Clothing);
the 720x544 preview at the left with Full / Face / Back / Game view; the 512x544 options panel at the
right; Randomize, Randomize all, Undo, Reset, Presets..., then Back and Begin (or Cancel and Keep);
the stack's footer with the screen's own `nav_hint()`. Larger windows grow the panels by anchors.

**Controls** (the P16 focus rules): `focus_rows()` = [the tabs] + the category's rows + [the
actions]; LB and RB, or PageUp and PageDown, change category; row kinds: swatch rows and cyclers
apply the focused value at once (moving the focus previews and keeps, like the cyclers; every change
enters the undo history), sliders (grey), toggles (scars). The preview turns with the right stick, a
mouse drag or Q and E, and zooms with LT and RT, the wheel or + and −; X or V cycles the view; Y or R
randomizes the open category; "Randomize all" is a button; Undo is a button, Ctrl+Z or the pad's View
button and steps back through at least 32 changes, Randomize, presets and Reset included; Ctrl+Enter
is Begin (New Game) or Keep (shrine). **Back, Cancel, Esc and pad B** close at once when the record
equals the one the screen opened with, and otherwise ask "Discard your changes?" (Discard / Keep
editing; the focus starts on Keep editing). Every swatch has a name; a locked option says why ("Choose
your line at a shrine of the Old Kingdom"); the ancestry mark ("Ancestry mark: shown / hidden") is a
row of the Tattoos category.

**Reading in play.** A design row whose region the current outfit covers says "Hidden by your
clothing", and while it has the focus the covering garments fade (`fade` uniform) in the preview.
"Game view" shows the current stage (stage 1 at New Game) from the game's default third-person camera,
behind and above, in the world's light, with a soldier beside it for scale.

**The preview** (`GiantPreview`, a `SubViewportContainer`): a SubViewport with `own_world_3d`, its own
environment (a dark backdrop, ambient light, a key light with shadows, a cool rim light, a stone
disc), MSAA 2x on desktop and off on the Web, `UPDATE_WHEN_VISIBLE` (portraits use `UPDATE_ONCE`), the
same `giant_model.tscn` and `GiantLook` as the game, the idle clip when present (else
`GiantModel.pose_relaxed()`), the equipped weapon at shrines (placed at `GiantModel.hand_transform()`
with `TipMatching.idle_grip(family)`), and framing per category: Hair three-quarter from behind (where
styles differ); Beard, Eyes and War paint the face; Tattoos and Scars the focused design's region;
Skin, Clothing and Presets the full body. The preview and its animation run with
`PROCESS_MODE_ALWAYS`, because the tree is paused while a shrine's screen is open.

**The warm-up**: the title shows "Preparing..." with New Game and Continue disabled while a hidden
64x64 SubViewport draws the model with every material category for two frames under the preview's
lighting (shadowed key light and rim, no fog) and for two frames under a level's (a shadowed sun and
fog); the buttons enable after those frames or after 6 s, whichever is first. Without a display
(headless tests) there is no warm-up and the buttons are enabled at once. The warm-up viewport is
freed when a level loads; the compiled variants stay while `GiantLook`'s cache holds the shaders
(ASSUMED), which P45 checks by measuring the first "Change your look..." at a shrine.

**Randomize**: `Appearance.random_record(rng, scope, keep_outfit, ancestry_id)` with the screen's own
`RandomNumberGenerator`, seeded from the clock, never `Sim.rng` or `Sim.rng_for`; `scope` is one
category (Y) or "all" (the button, which keeps the outfit unless the Clothing category is open);
natural hair colours 90 % of the time, at most two tattoo regions and never one the outfit covers,
war paint 30 %. **Reset** returns to the look the screen opened with (a shrine) or the default preset
(New Game); both are undoable.

### 2.11 Events, registries, command line, settings and flags

| Kind | Name | Owner |
| --- | --- | --- |
| Signal | `appearance_changed(tick: int, entity_id: String)`: the player kept a new look at a shrine | P42 declares it; `PlayerAppearance` emits it; GameSession's F15 list (P42) |
| Registries | `SCREENS["creator"]`; `TABS` Appearance; `COMPONENTS` appearance (and the `appearance` field); `SCHEMA_PATHS` `appearance_set` and `appearance_preset`; `ResetHooks` SkinnedRig | P42 (tested by `test_predeclared_m10.gd`) |
| Registry | `build_scenes.gd BUILDERS`: `giant_model.gd` before `player.gd` | P41 |
| Command line | `--appearance=<appearance_preset id>` (every mode, when the character has no look) | P42 |
| Command line | `--creator` (with `--mode=world`, or `--mode=valley --new-game`: open the creator first) | P42 parses, P44 opens, P45 uses in the launcher |
| Command line | `--giant-tier=web` or `--giant-tier=hi` (forces the texture tier; sheets and tests) | P42 |
| Command line | `--skin`, `--no-skin`, `--skin-stats`, `--scenario=capture_m10` | P43 |
| Tutorial prompts | `tutorial.appearance_shrines` ("Your giant can now be shaped at any shrine: the Appearance tab.") at the first shrine after loading a save that had no look (the `appearance.legacy_save` flag); `tutorial.appearance_mark` ("Your line's mark now shows on your giant. You can hide it at a shrine, in Appearance.") on `ancestry_chosen` while `mark` is "auto"; both `once` | P42 (data and the flag) |
| Flags | `appearance.tab_seen` (P44), `appearance.legacy_save` (P42) | |
| Group | `giant_models` (every `GiantModel`) | P41 |

No new setting in M10 (the World style is deferred, §0.5).

### 2.12 Budgets

| Budget | Value | Checked by |
| --- | --- | --- |
| Web pack, shipped (gzip then base64, MiB as `build_web.sh` counts) | ≤ 23 (M6–M9 decision 8) through W26; M10's share (`assets/giant/`, the giant's shaders and scenes) ≤ 4.6, the floor's ≤ 2.9; target total ≤ 21.3. From P45 on (the owner's answer 1, §0.6): ≤ 26, M10's share ≤ 7.6 with `tex_hi/` in the Web pack, target total ≤ 24.3 | `build_web.sh` (a `GIANT_SHARE` line from W25; fails over either), P41 (a test export), the W26 preview build, P45, the gate |
| Pack parts | ≤ 15 MB each | `build_web.sh` |
| Giant draw calls, low preset, fullest look (warrior outfit, long hair, full beard) | ≤ 13 (the box giant: 8; with the head split: 12, ASSUMED from the mesh list) | P41 (meshes shown per look), P45 (probe) |
| Draw calls in every measured view | ≤ 250 (unchanged) | P45 (the Valley walk and the world viewpoints of `PERFORMANCE.md`) |
| Giant primitives | ≤ 55,000 at 4 m with the fullest look; ≤ 4,000 beyond 120 m (LODs) | P41, P45 |
| The skin's CPU per frame (the player) | Web ≤ 0.35 ms (0.26 measured); native ≤ 0.10 ms | P45 (Web bench), P43 (native) |
| Texture memory at the Web tier | ≤ 9 MB of textures (the 512 px maps, the atlases and about 6 design layers at 512 px: about 4 MB, ASSUMED) and ≤ 3.5 MB of mesh buffers (3.04 MB measured, VERIFIED asset brief) | P45 |
| Shader stalls | the title's worst frame until its buttons enable, the creator's first frame, a level's first frame and the first "Change your look..." at a shrine each ≤ 3× the median frame after the warm-ups | P45 (native probe, `creator_check.mjs`) |
| Test tiers | default +≤ 3.5 s with ≥ 3 s moved to the slow tier (P42) and 2 s reserved, < 75 s; slow +≤ 130 s and < 8 min; gate +≤ 6 min and < 50 min | every merge, `--strict-times` |
| Repository growth | ≤ 25 MB (the vendored CC0 subset ≈ 10 MB raw, ≈ 7 MB after the trim; generated assets ≈ 8–12 MB) | P41, P46 |
| Full regeneration | `--giant-full` ≤ 25 min and `--giant` ≤ 6 min at 2 threads on this machine | P41 |

The arithmetic behind the share (MiB shipped): the base 16.59 (VERIFIED at `1c33b8e`; 16.69 on 0.9.0-m9,
17,499,328 B, re-checked on 0.9.0-m9, so every total below is 0.10 higher: floor ≈ 19.6, target ≈ 21.2) + the meshes with LODs and the four floor hair and beard meshes 1.76 (VERIFIED) +
the Web-tier textures and the hair atlas ≈ 0.80 (VERIFIED rates: albedo 89 KB, normal 329 KB, ORM
136 KB, masks about 34 KB, scars and tattoo about 13 KB, the atlas 229 KB) + the design array ≈ 0.10
(ASSUMED: 4–6 layers at 10–17 KB each, feasibility review) + the denser crop ≈ 0.06 (ASSUMED) + cloth
detail maps, scripts, scenes and data ≈ 0.15 (ASSUMED) ≈ **2.9 for the floor (total ≈ 19.5)**; the
target adds five hair and beard styles ≈ 0.7, up to three garments ≈ 0.4, two hair atlases ≈ 0.45 and
the clips ≈ 0.02 (all ASSUMED from the measured per-style rates; the clips imported to 12 KB, VERIFIED
planner) ≈ **4.5 for the target (total ≈ 21.1)**. The share's cap leaves 0.1 MiB, so the measured
share decides the content cut list (§6.3) from W26 on; the desktop-only 1024 px maps (≈ 1.3 MiB more)
are excluded from the Web presets from W25.

### 2.13 Test conventions

As in M6–M9 §2.16, plus:
- The default tier runs headless with the skinned layers off; skin suites call
  `SkinnedRig.enable_for_tests()`; ResetHooks resets it after every test and `test_skin_rules`
  asserts that the layers are off at the start of each test.
- Final bone poses, and whatever the modifier places, are read inside `SkinnedRig.posed` (modifier
  results are only visible during `skeleton_updated`, VERIFIED animation brief); swing measurements
  compare with `phase_fraction()` at `frame_pre_draw`, never with the previous tick.
- Asset checks compare the committed glTF and PNG sources and the manifest, never `.godot/imported`;
  scene checks load the saved scene from disk (edits inside an instance are not saved, §2.5).
- Rendered checks run a child Godot under `xvfb-run -a -s "-screen 0 1280x720x24"` with
  `--rendering-driver opengl3`, an explicit `--giant-tier`, at most 2 llvmpipe threads, frames at
  320x240 (grids of small viewports for many options), the render loop off between captured frames;
  without `xvfb-run` they skip with a note, and `check.sh --require` fails on any such note; they save
  their frames to `user://m10_frames/` for the merges, the sheets and the gate's review.
- Save fixtures with and without a look, and with a look from a later build, live in
  `tests/fixtures/saves/`.
- Every option of every set is exercised through `Appearance.to_look` and `GiantLook.apply` headless
  (visibility and uniforms, `validate()` empty) and rendered once in the slow tier (pixels change in
  its framed view; each design category also in the rear or first-person view).

---

## 3. Package specifications

Each package lists its wave and lane, dependencies, goal, owned paths (exclusive within its wave),
allowed hotspot edits (at its own anchors, or as the single owner of §1.5), design, tests, its
test-time budget (default suite cap / slow / gate), acceptance and size. "Cross-lane symbols" are the
few things a package must reach defensively because its wave partner adds them. Every package also
writes `docs/systems/<id>.md` and passes §1.1. Each design list is in priority order; a package that
passes about 3,500 new lines or its time range splits at a numbered item and records it.

### 3.1 P41 — The giant asset pipeline and the model: the CC0 inputs, the Blender tools, the bakes, the designs, the texture tiers and `GiantModel`

- **Wave / lane:** W25, A, parallel with P42. **Depends on:** 0.9.0-m9; the shared venv (before
  W25). **Milestone:** M10.
- **Goal:** everything the giant is made of, generated by committed tools from audited CC0 inputs,
  regenerated and compared bit-exactly in any worktree, imported into the game as
  `giant_model.tscn` with its index and landmarks; the floor catalogue's content (§2.3); the Web
  pack's accounting from the first wave.

**Owned paths**
- `tools/giant/**` (§2.1, §2.5) except `kit/clips.py`; `assets/giant/**` except `giant_clips.glb`
- `scripts/presentation/giant_model.gd`, `tools/builders/giant_model.gd`, `scenes/player/giant_model.tscn`
- `CREDITS.md`
- Tests: `tools/giant/test_giant_tools.py`, `tests/integration/test_giant_assets.gd`,
  `tests/slow/test_design_array.gd`

**Hotspot edits:** `tools/build_scenes.gd` (BUILDERS: `giant_model.gd` before `player.gd`);
`tools/check.sh` (`--giant`: the pipeline's tests, then `build_giant.py --verify --skip-bake`;
`--giant-full`: `--verify` with every bake; `--require`: any "skipped" note of the venv, `xvfb-run` or
Chromium fails the check; `--strict-times`, §1.7 rule 5); `export_presets.cfg` (the Web presets
exclude `assets/giant/manifest.json` and `assets/giant/tex_hi/*`); `tools/pck_files.py`
(`--giant-share`, and a listing per pack) and `tools/build_web.sh` (prints `GIANT_SHARE`; fails over
4.6 MiB) with their tests; `tests/unit/test_ship_docs.gd` (skips `tools/giant/mpfb2/`); `.gitignore`
if needed; `docs/PERFORMANCE.md` (the asset rows); `docs/plans/FOLLOWUPS.md`.

**Design**
1. **Venv and inputs**: `requirements.txt` pinned with hashes from the shared venv; `setup_venv.sh`
   recreates `GIANT_VENV` outside every worktree (bpy 5.3.0 is 927 MB installed, VERIFIED planner);
   `GIANT_CACHE` likewise; the vendored CC0 subset with its licence, source note and `.gdignore`;
   `fetch_mpfb2.py` (§2.5).
2. **The kit**, ported from the research run's frozen snapshot (not from the render workflow's later
   edits, so the outputs reproduce the brief's measurements): `mh_data`, `giant_body`, `giant_skin`,
   `giant_hair`, `giant_garment`, `node_util`, `skin_textures` (2,840 lines) and the research's
   export, hair, bake, design, pack and vendoring scripts (about 1,030 lines), with the research
   switches that leave the beard shadow and the scalp tint to the shader. `giant_pose` is not ported
   (the pipeline never poses; P43 ports the two helpers its clips need).
3. **Export**: the body at 3.6576 m on the game_engine rig; the three-way body split and the garment
   split (§2.6), every cut loop capped; the 16 region ids; one eyes mesh; the seven garments (boots
   decimated toward 2,500 triangles, ASSUMED enough); hair cards `crop` (double the research's card
   density, or a scalp-hair pass: the research crop is patchy, VERIFIED asset brief) and `long_back`;
   beards `short` and `full`; one glTF; the landmarks and the body's hash into the manifest.
4. **Bakes**: the cheap passes and the expensive ones as two groups (§2.5), `GIANT_CACHE`, and the
   new `--skip-bake` that reads AO and thickness from the committed `tex_hi/orm.png`.
5. **Designs**: the floor's 17 — 8 tattoos, 2 war paints, 4 scars, 3 ancestry marks; the research
   drew 4 (arm bands, chest spiral, forearm chevrons, the face paint that becomes `face_stripes`), so
   9 are new and the two empty scar channels are fixed (VERIFIED creator brief) — drawn on the rest
   pose by the design rules of §2.3 and packed by the packing rule of §2.5.
6. **Pack**: both tiers (the Web tier's albedo at 512 px too: 89 KB against 252 KB at 1024, VERIFIED
   asset brief), resized one channel at a time; the hair atlas; a tileable weave and a leather detail
   map.
7. **Manifest, verify, budget, the check options** (§2.5, §1.7).
8. **`GiantModel` and its builder**: `giant_model.tscn` = a `GiantModel` root with the glTF instance;
   the exported `index` (with `landmarks` and `defaults`); `_ready()` applies every mesh's layer and
   the default visibility from the index (never saved, §2.5); `skeleton()`, `mesh(id)`,
   `meshes(category)`, `landmarks()`, `hand_transform(right: bool) -> Transform3D` (the hand bone's
   global pose, for the preview's weapon), `pose_relaxed()` (arms down; previews and sheets before the
   clips exist); a `preload` of the glTF scene so it loads once per process; joins `giant_models`.
   The model draws with the glTF's own materials until a caller runs `GiantLook.build_materials`
   (P42's, same wave).
9. **The Web accounting**: the exclusions, `--giant-share`, `GIANT_SHARE`, and one Web test export at
   the end of the package measuring the floor's share (≤ 2.9 MiB, §2.12).
10. **Provenance and credits**: `assets/giant/PROVENANCE.md`; `CREDITS.md`.
11. **Measure and record**: the base's default-tier per-suite times and Web pack on 0.9.0-m9 (with
    P42, who uses them for §1.7 rule 4); the list of suites that load the giant (§1.7 rule 2); the
    model's headless load and instance cost; meshes, draw calls and primitives per look (counted from
    the index and the LODs; rendered at the W25 merge by P42's suite); `--giant` and `--giant-full`
    times; the repository growth; the floor's Web share.

**Tests to add**
- `test_giant_tools.py` (run by `--giant`): per-channel resizing keeps every channel (the Pillow
  regression); the region encoding decodes with `int()`; `Body_Limbs` and the limb garment parts
  have no open boundary edge (the caps); the packing rule holds in every layer; the design generator
  is deterministic; `--skip-bake` reproduces the pack and the designs bit-exactly from the cheap
  passes and the committed ORM; the manifest round trip; the audit's file list equals the vendored
  files' hashes.
- `test_giant_assets.gd` (default): the model loads and instances; 53 bones with the contract's
  names; every index mesh exists with its layer and category, under its triangle cap; the saved scene,
  reloaded from disk, shows the layers and default visibility after `_ready`; the index, the glTF and
  the design array agree; the landmarks exist and lie within 2 cm of the animation brief's (shoulder
  (0.414, 3.015, −0.033), reach 1.385 at stage 1); the import settings of §2.5; no `.import` file under
  `tools/`; the fullest look shows at most 13 meshes; `hand_transform` follows the hand bone.
- `test_design_array.gd` (slow, headless): every layer of `designs.png` round-trips through
  `Image.compress(COMPRESS_S3TC)` with each design's mean error ≤ 0.05 and no other design showing
  through above a mean of 0.05 (the feasibility review's probe as a test).

**Test time:** default ≤ 0.4 s; slow ≤ 5 s; gate 0. **Acceptance:** [M10] `check.sh --giant --require`
and `--giant-full` pass, bit-exact on the reference toolchain, in a fresh worktree with the shared
cache emptied; the model loads with every floor mesh and design id; meshes, draw calls, primitives
and memory within §2.12; `PROVENANCE.md` and `CREDITS.md` complete; the floor's Web share measured
from a test export. **Size:** about 2,300 new lines (Python ~1,450: the split, caps, regions, eyes and
garment split ~400, the rest step, cache, manifest, verify and budget ~450, nine designs and the
packer ~400, pack tiers and audit ~200; GDScript ~400; tests ~450) plus about 3,870 ported lines,
besides the vendored data and the generated assets. Split point: if P41 passes 7 hours, item 5's nine
new designs move to P46 and the W25 merge drops their data rows (a fix-forward under 50 lines).
**Cross-lane symbols:** none (P42 owns the tests that compare its data and its look with the index).

### 3.2 P42 — The look: appearance rules, data and saves; the giant's shaders and `GiantLook`; tip matching; the M10 pre-declarations

- **Wave / lane:** W25, B, parallel with P41. **Depends on:** 0.9.0-m9. **Milestone:** M10.
- **Goal:** the look as data and as a saved part of the character, never touching the simulation;
  the shaders and `GiantLook` that turn a record into a drawn giant; `TipMatching` as a pure library;
  a New Game and a launcher start that take a look; a shrine change that saves at once; every
  registry entry, anchor and event M10 needs, tested; headroom in the default tier.

**Owned paths**
- `scripts/progression/appearance.gd` (`Appearance`: `default_record()`, `resolve(character)`,
  `sanitize(record) -> {record, dropped, notes}`, `migrate(record)`, `to_look(record, ancestry_id)`,
  `random_record(rng, scope, keep_outfit, ancestry_id)`, `summary_lines(record)`, `options(category,
  ancestry_id)`, `locked_reason(option_id, ancestry_id)`, `covered_regions(record)`)
- `scripts/actors/player/player_appearance.gd` (`PlayerAppearance`: `apply_state` and `capture_state`
  (the key only when present; a later build's record written back unchanged), `record()`,
  `set_record(record)` (stores, applies, emits `appearance_changed`), the `--appearance=` preset when
  the character has no look, in every mode (the sandbox and the soak included), re-resolves on
  `ancestry_chosen` for `mark: "auto"`, applies through `player.rig.apply_look(look)` when the rig has
  that method — a no-op on the stylized rig of W25)
- `scripts/core/schemas/{appearance_set,appearance_preset}_schema.gd`; `data/appearance/set_*.json`
  (13) and `preset_*.json` (8) with the floor catalogue (§2.3; the Wanderer's values pinned in §2.4,
  the other colours from the research palettes, chosen to read in the world's light);
  `data/tutorial/appearance_{shrines,mark}.json`
- `assets/shaders/giant_{skin,hair,eye,cloth}.gdshader`; `scripts/presentation/giant_look.gd`;
  `scripts/presentation/tip_matching.gd`
- `tests/fixtures/saves/v2_appearance*.json`
- Tests: `tests/unit/{test_appearance_record,test_appearance_schemas,test_appearance_rules,test_giant_look,test_tip_matching,test_predeclared_m10}.gd`,
  `tests/integration/test_giant_look_real.gd`, `tests/slow/test_giant_shaders.gd`, and their own new
  tests in `tests/unit/test_save_migration.gd` and `tests/unit/test_save_slots.gd`

**Hotspot edits:** `scripts/core/events.gd` (the "appearance (M10)" block with `appearance_changed`;
anchors P41, P43–P47); `scripts/core/data_validator.gd` (SCHEMA_PATHS); `scripts/core/game_data.gd`
(its anchor P42: presets valid against the sets, one default per set);
`scripts/progression/character_state.gd` (sanitize the key and pass up its notes; the anchor P46);
`scripts/core/save_slots.gd` (`read()` joins the notes; the header's note);
`scripts/core/game_session.gd` (`change_mode` passes `options.appearance` to `_begin_new_valley` and
`_begin_new_world`; `--appearance=`; `--creator` into `creator_start`; `appearance_changed` joins the
F15 list; the `appearance.legacy_save` flag when a loaded save has no look);
`scripts/actors/giant_player.gd` (the COMPONENTS entry and the `appearance` field);
`ui/screens/screen_stack.gd` (SCREENS); `ui/screens/shrine_screen.gd` (TABS);
`tests/support/{reset_hooks,anchors_expected}.gd` (P42 becomes the M10 anchors' creator); the moves of
existing default suites to `tests/slow/` (§1.7 rule 4); `docs/plans/FOLLOWUPS.md`.

**Design** (§2.2–§2.4, §2.8, §2.9's tip matching, §2.11):
1. **Pre-declarations** and `test_predeclared_m10.gd`.
2. **Headroom**: with P41's per-suite times, move at least 3 s of default suites to the slow tier
   (re-checked on 0.9.0-m9: enough for the W25 merge to stay under 75 s, §1.7 rule 4).
3. **`Appearance`**: `sanitize` with notes and the later-build rule; `to_look` resolves palettes,
   locks and `mark: "auto"`; `random_record` follows §2.10 (one category or all; never a region the
   outfit covers); `summary_lines` reads like "Hair: long, combed back, chestnut, a little grey";
   `covered_regions` for "Hidden by your clothing".
4. **`PlayerAppearance`**, the session paths (New Game, `--appearance=` in every mode, `--creator`,
   the F15 checkpoint, the legacy flag) and the saves (notes into `read()`'s message).
5. **Data**: 13 sets, 8 presets, the two tutorial prompts.
6. **The shaders**, ported from the creator lab (`creator_lab/proj/shaders`) with the region-array
   design path (§2.8's +1 encoding), the `tint` and `flash` uniforms, the cloth `fade`, no World
   style.
7. **`GiantLook`**: `build_materials(root, index, tier)` (unique ShaderMaterials per instance, a
   static texture cache; tier "auto" picks `tex_hi/` when its files exist and `--giant-tier` does not
   force "web"), `apply`, `validate` (unknown ids, and every uniform name checked against
   `get_shader_uniform_list()`), `materials(root)` (for RigPaint), `DEFAULT_LOOK` (§2.4); headless,
   `apply` sets visibility and stores the look and builds no materials unless the skinned layers are
   on or a test asks.
8. **`TipMatching`** (§2.9): pure, from the weapon data and the landmarks (`from_index`, or
   `DEFAULT_LANDMARKS`); `idle_grip(family)`.

**Tests to add**
- `test_appearance_record.gd`: the default from data; `resolve` (absent → the default; the
  `--appearance=` preset; `mark` "auto" with and without an ancestry; "none"); `sanitize` (unknown ids
  → defaults and the dropped list; locked options; a tattoo in the wrong region; scars unique and at
  most 4; numbers clamped and cast; `v` cast from 1.0; `v` 2 kept untouched with its note; unknown
  keys kept; a non-dictionary → the default and its note); `to_look` for every option of every set;
  `to_look(default) == GiantLook.DEFAULT_LOOK` within §2.4's tolerance; `random_record` valid for 1,000
  seeds in every scope, never on a covered region, with `Sim.rng`'s state unchanged; every preset
  valid.
- `test_appearance_schemas.gd`: bad sets rejected (unknown category, duplicate keys, two defaults, a
  palette without a colour, a design option without a region).
- `test_appearance_rules.gd`: the `appearance` code rule of §2.7.
- `test_giant_look.gd` (a synthetic model: a few meshes with the real shaders, a small index): every
  look key sets the expected uniforms and visibility; `validate()` flags a misspelled uniform name and
  an unknown id; two instances never share a material; the tier falls back to `tex/` when a `tex_hi/`
  file is missing; the region arrays are always filled (0 = none).
- `test_tip_matching.gd` (pure, from the weapon data): every player weapon arc at stages 1, 4 and 6
  (every second ACTIVE sample): the outer half inside the capsule in 100 % of samples, at most 15° off
  the tested direction (median ≤ 9°), the grip within reach, the solve exact; `idle_grip` within reach
  for every family; and, when `giant_model.tscn` exists, the same over the exported landmarks (the
  W25 merge runs it).
- `test_predeclared_m10.gd`: every M10 registry path spelled as §1.5 lists it and existing once its
  owner has merged; every M10 anchor; `appearance_changed` declared.
- `test_giant_look_real.gd` (skipped with a note while `giant_model.tscn` does not exist; the W25
  merge runs it): `GiantLook.apply` over every index item and every option of the data sets the
  expected visibility and uniforms with `validate()` empty; the data's mesh, design and garment ids
  exist in the index; `DEFAULT_LOOK` applies cleanly.
- `test_giant_shaders.gd` (slow, Xvfb): every giant shader compiles in the Compatibility renderer
  without an error; one frame per material category is not blank (on the real model when it exists,
  else on a sphere); on the real model it also saves the hair frames for §4.2's hair bar (long hair
  and full beard at the creator's Face and Hair framings) and records the per-frame cost at 320x240
  for P43's caps.
- Saves and session: v1 and v2 fixtures without the key load and resolve to the default; a record
  round-trips exactly through write and read; unknown ids load with the message; a broken block loads
  with the default and the note in `read()`'s message; a future-version record loads, shows the
  default and is written back unchanged by the next checkpoint; a damaged main file with a look
  recovers from the backup with its look, and a broken look alone never sends the read to the backup;
  a character without a look captures no key; a New Game with an appearance option stores it (valley
  and world); `--appearance=` gives the sandbox, a bot run and a command-line New Game that look;
  `--creator` sets `creator_start`; `appearance_changed` while a shrine's screen is open re-takes the
  checkpoint; the legacy flag is set once.

**Test time:** default ≤ 0.6 s; slow ≤ 20 s; gate 0. **Acceptance:** [M10] the record, data, saves,
session and look paths as specified; the shaders and `GiantLook` draw the real model at the W25 merge
with `validate()` empty; the tip-matching contract on the exported landmarks at the merge; every
pre-declaration in place and tested; at least 3 s moved out of the default tier. **Size:** about 3,250
new lines (GDScript ~1,900: `Appearance` 550, `PlayerAppearance` 150, schemas 150, session and saves
150, `GiantLook` 450, `TipMatching` 300, registries and tutorial 100; data ~450; tests ~900) plus about
450 ported shader lines. Split point: `TipMatching` (item 8) moves back to P43 if P42 passes 6 hours.
**Cross-lane symbols:** `giant_model.tscn` and its index (P41, same wave): the tests that read them
are skipped with a note while `ResourceLoader.exists()` is false; the W25 merge runs them.

### 3.3 P43 — The skinned giant in the game

- **Wave / lane:** W26, A, parallel with P44. **Depends on:** P41, P42. **Milestone:** M10.
- **Goal:** the realistic model is the player: driven by the pose brain, its clips and tip matching,
  at every stage, in first person and with the camera pressed close, jumping, charging, holding and
  throwing, tinted and flashing, dying without breathing; gameplay unchanged, and proven unchanged
  with positive controls.

**Owned paths**
- `scripts/presentation/{skinned_rig,pose_brain_modifier}.gd`
- `tools/giant/kit/clips.py`, `assets/giant/giant_clips.glb` (and its `.import`)
- `scripts/debug/capture_m10.gd`
- Tests: `tests/unit/test_skin_rules.gd`, `tests/integration/test_skinned_rig.gd`,
  `tests/slow/test_skinned_rig_render.gd`, `tests/gate/{test_giant_determinism,test_skinned_rig_stages}.gd`;
  the rewrites of
  `tests/integration/{test_rig_merge,test_growth,test_growth_456,test_camera_review_fixes,test_grab_throw,test_weapons}.gd`

**Hotspot edits:** `tools/builders/player.gd` (the stylized meshes removed; the brain's pivots and hand
markers kept; `Visual/Body/Model` and `WeaponSocket`; Visual's script becomes `SkinnedRig`) and the
regenerated `scenes/player/giant.tscn`; `scripts/presentation/actor_rig.gd` (read accessors for the
brain's outputs and the hooks `set_weapon_visual` and `set_body_scale` need; no behaviour change);
`scripts/presentation/rig_paint.gd` (the ShaderMaterial path); `scripts/presentation/camera_rig.gd`
(the culling masks for layers 2 and 3, decision 8); `scripts/presentation/weapon_visuals.gd` (the
canopy and needles to layer 3); `scripts/presentation/{giant_model,giant_look,tip_matching}.gd` and
the shaders (W26 owner: `play_idle()`, the clip library, fixes found by the rig);
`tools/giant/build_giant.py` (the `--clips` step); `scripts/debug/autopilot.gd` (the `capture_m10`
scenario's dispatch; `--skin-stats` at exit); `scripts/actors/giant_player.gd` (only if a delegate is
needed); `docs/PERFORMANCE.md` (the native skin rows); `docs/plans/FOLLOWUPS.md`.

**Design** (§2.9):
1. **`SkinnedRig`**: the model under `Visual/Body/Model`; at `_ready`, when the layers are on, it
   creates the `AnimationPlayer` (the clip library), the `AnimationTree` and the `PoseBrainModifier`
   under the model's skeleton (never saved, §2.5); `--skin`, `--no-skin`, `layers_enabled`;
   `skin_stats()` and `SKIN_STATS`.
2. **The legs' sources** of §2.9 step 2: the brain's walk, an action's motion (the skin's own clock),
   airborne, dead, stance. Never cut: the run clip, the airborne pose, the stance gating, the idle
   stopping at death.
3. **Clips** by computed keyframes in `clips.py` (no hand animation; it ports `local_quat` and
   `mirror_ops` from the research kit's `giant_pose.py`): idle (breathing, a 2 s loop), walk and run
   (two-step cycles whose stride at k = 1 matches the brain's 3.2 m per cycle (`stride_length_m` 1.6
   per step, VERIFIED (code)) within 5 %; the lab's walk was within 2.5 %, VERIFIED animation brief),
   right and left grip, an open hand, the airborne pose, the death (knees buckle, the torso slumps);
   the stomp's leg lift (seeked by the stomp's phase fraction, its impact at the start of ACTIVE) is a
   cut-list item. Elbow poles are tuned per arc side and the grip axis per weapon family, against arms
   crossing the body on cross-body arcs (yaw down to −100° in the arc data, animation brief) and wrist
   bends over 45°.
4. **`PoseBrainModifier`** with `TipMatching.from_index(model.index)`; the grab palm and the
   held-visual offset, restored after a release and after the held body dies.
5. **Paint**: `RigPaint`'s ShaderMaterial path; `SkinnedRig` writes the hair shader's `head_motion`
   when P46 has added it.
6. **The camera's masks and the pressed-close decision**: first person culls layers 2 and 3; the
   pressed-close mask culls layer 3, and layer 2 too if a render in the growth course's low passage
   (the case `test_growth_route` drives) shows the torso over the crosshair; the decision and its frame
   go into the system doc.
7. **The capture tour** `--scenario=capture_m10` (run with `--skin` under Xvfb, with `--write-movie`
   for the owner's video): idle, walk, run, sprint, jump, each weapon family's light and heavy, a
   block, both dodges, Shoulder Charge, Earthquake, a grab, hold and throw, a stomp, a roar, a self
   buff, a stagger, a knockback, the death fall, stages 1–6, first person looking down and ahead; at
   most 4 minutes of wall time (ASSUMED); its frames saved for the merges and the gate.
8. **Measure**: the native skin CPU per frame; the change in the existing rendered suites that now
   draw the skinned giant (`rig_draw_probe`, `formation_draw_probe`, `world_draw_probe`: each pays the
   giant's first shader compile, up to 3.3 s on llvmpipe, VERIFIED creator brief).

**Tests to add**
- `test_skin_rules.gd` (unit): §2.7's skeleton and model code rules, and the write-only rule; the
  layers are off at the start of every test (ResetHooks).
- `test_skinned_rig.gd` (integration, `enable_for_tests`): the node contract of §2.9 on the scene
  reloaded from disk (the run-time nodes created, none saved); every track of every clip resolves to
  a bone (0 unresolved); the walk's time follows the brain's phase and the footfall count over a 5 s
  walk equals the stylized rig's; during a dodge, a stagger and a knockback the legs hold the stance
  (every leg bone within 2° of the stance pose); during Shoulder Charge the run clip advances; after a
  jump the airborne pose shows within three frames; at death the idle stops and the death clip
  follows the fall; a heavy at stage 1 and at stage 4 measured in `posed` (tip and direction within
  the contract, the fist within 0.01 m); `flash` and `set_status_tint` reach every giant surface and
  the weapon; `apply_look` on the live giant; growth to stage 4 scales by 3 with the look kept; the
  head, hair, beard and eyes on layer 3, the torso and core garment parts on layer 2, the limbs on
  layer 1, and the camera's masks cull 2 and 3 in first person; a grab's visible palm within 0.33·k
  of the socket, and the held body's `Visual` restored after a release and after the held body dies;
  the headless default (no run-time nodes, `WeaponSocket` at the brain's hand); `SKIN_STATS` counts.
- The six rewrites keep their intent (animation brief §8): the giant row of `test_rig_merge` lists the
  skinned meshes, the layer-2 and layer-3 meshes and the materials; `test_growth` replaces the 1° rule
  by "the visible weapon's head inside the swept capsule at stage 3"; `test_growth_456` puts the
  first-person eye inside the new head's bounds; `test_camera_review_fixes` checks the new layers and
  masks; `test_grab_throw` adds the visible palm within the measured gap; `test_weapons` finds the
  weapon under `WeaponSocket`.
- `test_skinned_rig_render.gd` (slow, Xvfb, stage 1, 320x240, the render loop off between captures):
  idle, walk, a heavy's windup, active and recovery, a jump, first person looking down and at the
  crosshair: no frame blank; the crosshair's pixel not covered by the giant at rest; frames saved for
  the gate (the caps themselves are proven by P41's closed-mesh test; the frames are reviewed).
- `test_skinned_rig_stages.gd` (gate, Xvfb): the same frames at stages 4 and 6, and the pressed-close
  render in the growth course's passage.
- `test_giant_determinism.gd` (gate), in child processes, each with 0 errors and 0 warnings and
  nothing left behind at exit:
  - the seeded 120 s soak three times — `--no-skin`; `--skin --skin-stats --appearance=appearance_preset.wanderer`;
    `--skin --skin-stats --appearance=appearance_preset.ash_raider` — prints byte-identical
    `AUTOPILOT_RESULT` lines, while the two `SKIN_STATS` lines show the layers on, more than 1,000
    posed frames and modifier runs, rig footfalls above 0, and different `look` and `shown_meshes`
    (the positive control: the skin and the look really ran);
  - a seeded Valley bot run (`--scenario=valley --bot-village=intimidate --bot-skill=novice
    --bot-seed=3`, 150 s, the pattern of `test_valley_audio_determinism`) with `--skin --skin-stats`
    and with `--no-skin` prints identical results, with grabs and throws above 0 in the run's metrics
    and `held_visual_writes` above 0 in `SKIN_STATS` (the one write into another actor, exercised).

**Test time:** default ≤ 0.6 s; slow ≤ 45 s (its own suite plus the change in the existing rendered
suites; the cap re-set from the per-frame cost P42 records at the W25 merge, before P43 starts);
gate ≤ 6 min. **Acceptance:** [M10] the realistic giant plays in every state §0.3 lists; the
tip-matching contract holds on the exported landmarks; the six suites pass rewritten; the gate suites
pass with their positive controls; the native skin CPU ≤ 0.10 ms a frame; the capture tour runs and
its video is made. **Size:** about 3,150 lines (GDScript ~1,700, Python ~450, tests ~1,000). Split
point: the capture tour (item 7) goes to P45 if P43 passes 8 hours. **Cross-lane symbols:** none
(P44's preview uses the model, not the rig).

### 3.4 P44 — The character creator, the shrine's Appearance tab and the character sheets

- **Wave / lane:** W26, B, parallel with P43. **Depends on:** P41, P42. **Milestone:** M10.
- **Goal:** §2.10: the creator at New Game, at the launcher's world start and at every shrine, its
  preview, controls, safety (Undo, the discard question), reading-in-play aids, flows and warm-up; the
  old saves' "(new)" tab; the rendered option check; the character sheets for the owner.

**Owned paths**
- `ui/screens/creator/{creator_screen,giant_preview,option_rows}.gd`, `ui/screens/shrine/appearance_tab.gd`,
  `tools/character_sheet.gd`
- Tests: `tests/integration/{test_creator_screen,test_shrine_appearance,test_creator_layout,test_giant_preview}.gd`,
  `tests/slow/test_appearance_render.gd`; the rewrites of
  `tests/integration/{test_session_flow,test_title_checkpoint_names}.gd` (New Game → the creator →
  Begin); the updates of `tests/integration/{test_shrine,test_shrine_panel_fit,test_talent_tab}.gd`
  (their exact tab lists gain Appearance; "LB twice from Rest" now lands on Ancestry, VERIFIED creator
  brief) and of `tests/integration/test_progression_player.gd`'s `test_shrine_loadout_and_attributes_tabs`
  (a shrine with both tabs off: `["Rest", "Grow", "Talents"]` gains Appearance; re-checked on 0.9.0-m9,
  the creator brief's lab did not run that suite)

**Hotspot edits:** `ui/screens/title_screen.gd` (New Game opens the creator after the confirm and the
prologue or skip choice; `GameSession.creator_start` opens it at once; `start_game(mode, options)` made
public; the warm-up and "Preparing..."); `docs/USABILITY_SCRIPT.md` (a creator sheet);
`docs/plans/FOLLOWUPS.md`. No `screen_stack.gd` or `ui_screen.gd` edit: `CreatorScreen` overrides M9's
`nav_hint()`.

**Design:** §2.10, in this order:
1. The screen, its rows and the flows (New Game, `--creator`, the shrine tab), the discard question,
   Undo and the keys of §2.10.
2. The preview: own world, framings (Hair from behind), the idle when present, the weapon at shrines,
   Game view, the "Hidden by your clothing" note and fade.
3. The title's warm-up and "Preparing...".
4. `test_appearance_render.gd`, the rendered option check (moved here from P45 so that P46's content
   meets it in its own wave): every option of every set rendered in its framed view, in grids of small
   viewports (sixteen 320x240 tiles a frame), against the base look — no engine or shader error, no
   blank tile, changed pixels above a floor per category; and each option of the design categories
   (tattoo, paint, scar, mark) also in the stage-1 rear Game view and in first person, where at least
   one option per category passes a floor (decision 18). The floors are set from the floor
   catalogue's renders and recorded; the check caught the research's two empty scar channels
   (VERIFIED creator brief).
5. `tools/character_sheet.gd` (a Godot `-s` tool that renders labelled pages of 1920 px wide PNGs into
   `docs/screenshots/m10/`, reusing `GiantPreview`'s portrait mode and the world's sun, ambient, sky
   and fog values from `world.gd`): the pages of §4.2. Split point: if P44 passes 7 hours, the
   orchestrator assembles sheet A from the saved frames by hand and the tool moves to P46.

**Tests to add**
- `test_creator_screen.gd`: from the title — New Game without a save → the creator → Begin: one
  mode-change request carrying the record, made in the same call stack as the press; with a save the
  confirm comes first; a finished prologue → skip → the creator → Begin in the Old Kingdom → world
  mode; `creator_start` opens the creator at once for a world start; Back with no change → the title
  as it was and the save file's bytes unchanged; Back after a change → "Discard your changes?", Keep
  editing keeps the look, Discard leaves; Undo steps back through a swatch, Randomize, a preset and
  Reset; Y randomizes only the open category and "Randomize all" everything but the outfit; with a
  pad, LB and RB through every category, the D-pad through every row, a swatch applied on focus, B
  backs out (asking when changed), the focus never lost after a category switch, Randomize or Undo;
  with a keyboard, PageUp and PageDown, Q and E, + and −, Ctrl+Z and Ctrl+Enter; Randomize leaves
  `Sim.rng` untouched; locked options give their reason; a design under the outfit says "Hidden by
  your clothing".
- `test_shrine_appearance.gd`: the tab at a shrine; Change → the creator over the shrine; Keep → the
  player's look, `appearance_changed`, the shrine's checkpoint re-taken and written; Cancel → restored
  without a write; Continue after quitting restores the look; a death reload keeps it; the root
  viewport's 3D is off while the creator is on top and on afterwards; "(new)" until first opened.
- `test_creator_layout.gd`: at 1280x720, 1366x768, 1600x900, 1920x1080 and 2560x1440 every panel,
  button and the preview lie inside the window and above the footer, none overlapping; the discard
  question too.
- `test_giant_preview.gd`: its own world; a whole look applied in under 1 ms (headless); framing per
  category (Hair from behind); Game view at the stage's camera; `UPDATE_WHEN_VISIBLE` while open,
  `UPDATE_ONCE` for a portrait; the weapon at `hand_transform` with `idle_grip`; the title's buttons
  enabled at once headless, and the warm-up viewport freed when a level loads.
- The title suites rewritten: every New Game path passes through the creator and Begin, with the
  original assertions kept after Begin.

**Test time:** default ≤ 0.8 s; slow ≤ 40 s; gate 0. **Acceptance:** [M10] the New Game, launcher and
shrine flows, controls, safety and layout as specified; the creator usable with a pad, a keyboard and
a mouse; the option check passes on the floor catalogue with its floors recorded; the sheet tool
renders sheet A at the W26 merge; the usability script's creator sheet written. **Size:** about 3,500
lines (GDScript ~2,300: the screen 950, the preview 450, rows 450, the tab 200, the title 100, the
sheet tool 150; tests ~1,200). **Cross-lane symbols:** `GiantModel.play_idle()` (P43, same wave):
called when `has_method`, else `pose_relaxed()`.

### 3.5 P45 — The Web build, performance, warm-ups and the Chromium checks

- **Wave / lane:** W27, A, parallel with P46. **Depends on:** P43, P44. **Milestone:** M10.
- **Goal:** the M10 build within every budget of §2.12, measured on the Web and on desktop; the
  Chromium checks of the creator and of every New Game path; the launcher's world start through the
  creator.

**Owned paths**
- `tools/web/{creator_check,test_creator_check}.mjs`
- Tests: `tests/integration/test_giant_web_presets.gd`

**Hotspot edits:** `tools/web/{audio_check,world_start_check}.mjs` and their tests where they exist (New Game now
passes the creator: Enter, then Ctrl+Enter for Begin; the world start's two presses, then the
creator, then Begin); `web/launcher.html` ("Start in the open world" passes `['--', '--mode=world',
'--creator']`); `export_presets.cfg` and `tools/build_web.sh` (the owner's answer 1, §0.6: the budget for `-m10`
becomes 26 MiB and `GIANT_SHARE`'s cap 7.6 MiB, with their tests, and the Web presets stop excluding
`assets/giant/tex_hi/*`); `scripts/main.gd` (the loading screen's
warm-up of the giant's level and preview variants, only if the probe shows a stall on Continue or at
a shrine); `docs/PERFORMANCE.md` (the M10 rows); `docs/plans/FOLLOWUPS.md`.

**Design and measurements**
1. **Exports**: the release `Web` build and `Web (test)`: the shipped size, its parts and
   `GIANT_SHARE`; `pck_files.py --check-no-test`; `tex_hi/` in the Web pack (the owner's answer 1, §0.6)
   and in the Linux pack's listing.
2. **`creator_check.mjs`** (headless Chromium, the release build; its own test as for
   `stream_check.mjs`): boot; the title's worst frame until its buttons enable; New Game → the
   creator; change a category with the keyboard; Undo; a screenshot; Begin → the Valley loads, with the
   pointer-lock request made inside the click; a third-person screenshot of the realistic giant; the
   level's first frame; Continue a world save fixture at a shrine and open "Change your look..." (its
   first frame); every stall against the median frame; 0 console errors.
3. **The other Chromium checks on the M10 build**: `world_check.mjs`, `audio_check.mjs` and
   `world_start_check.mjs` (both updated) and `stream_check.mjs --world --audio`.
4. **Native captures under Xvfb**, low and medium: the Valley walk and the world viewpoints (draw calls
   ≤ 250), the stress arena with the giant, the skin's CPU per frame with `--skin`, texture and mesh
   memory from the rendering server's monitors; on the Web, the animation brief's skin bench (the
   player alone, and with the creator's preview open).
5. **Warm-ups**: if the shrine path or Continue stalls above 3× the median, the loading screen draws
   the giant under the preview's and the level's lighting before it hides (M8's F26 pattern).
6. `test_giant_web_presets.gd` (default; parses only): the exclusions, the tier fallback order and the
   launcher's arguments.

**Test time:** default ≤ 0.1 s; slow ≤ 10 s; gate 0. **Acceptance:** [M10] every budget of §2.12 met
and recorded in `PERFORMANCE.md`, or a miss reported as a miss with its cause; the five Chromium checks
pass on the release build. **Size:** about 1,500 lines. **Cross-lane symbols:** none; P46's new
options enter the measurements from the data automatically.

### 3.6 P46 — The look pass: hair first, the owner's notes, the target catalogue

- **Wave / lane:** W27, B, parallel with P45. **Depends on:** P43, P44; the owner's notes on the
  preview link, the video and sheet A (applied when they arrive; they usually arrive while item 1 runs).
  **Milestone:** M10.
- **Goal:** the hair as close to the approved render as cards allow; the owner's notes applied; the
  catalogue from the floor to the target within the budget, with designs that read in play.

**Owned paths**
- `tools/giant/kit/**` (content parameters and new content, except `clips.py`), `assets/giant/**`
  (regenerated, except the clips), `data/appearance/**` (new options, revised presets),
  `assets/shaders/giant_*.gdshader` (tuning), `scripts/presentation/{giant_model,giant_look}.gd`
  (W27 owner)
- Tests: its additions to P42's data tests and P44's option check floors

**Hotspot edits:** `scripts/core/game_data.gd` (anchor P46, only for a new data rule);
`scripts/progression/character_state.gd` (anchor P46, only if the record changes);
`ui/screens/end_screen.gd` (the portrait, cut list); `scripts/core/settings.gd` and
`ui/screens/settings_pages.gd` (only if the owner asked for the World style); `CREDITS.md` (new
content's lines); `docs/USABILITY_SCRIPT.md` (a look section for the owner's own pass);
`docs/plans/FOLLOWUPS.md`.

**Design**, in this order (§6.3's cut list drops from its own order, which protects the hair):
1. **Hair, second pass**: the hairline and the scalp's density, the crop's coverage, the cards'
   shingling at the creator's Face and Hair framings against the approved close-up, the braided-strand
   atlas; the `length` uniform (2–3 lengths per hair and beard mesh, kept only if the option check
   shows the lengths apart); the sway (`head_motion`).
2. **The owner's notes** (data, shader parameters, hair, garments, designs, palettes; never the body
   or the skeleton, decision 9 — a note that asks for a different build or face is answered as M11
   work unless the orchestrator re-plans).
3. **Hair and beard styles**: `long_braided`, `warrior_tail`, `wild_mane`; the beards `braided` and
   `forked`.
4. **Designs that read in play**: 8 more tattoos (2 per region, among them a full sleeve and a
   shoulder-to-shoulder piece), the war paints `full_face` and `back_hand`, the scars `cheek` and
   `back_lash`; the presets revised.
5. **Garments**: up to 3 new ones (for example a cloak, a kilt, leg wraps, or what the notes ask) and
   1–2 outfits.
6. **The World style**, only if the owner asked for it (§0.6 question 3): `world_style` in the four
   shaders, a Settings row (Realistic by default), `--giant-style`, a test.
7. Cut-list items if time remains: the end-screen portrait; a material pass on the weapons.

P46 renders sheet B's pages in its branch for its own review; the sheet the owner receives is
rendered from the candidate after the gate (§4.2).

**Tests to add:** P42's data tests and P44's option check cover the new content (P46 records the new
floors); `--giant --require` and `--giant-full`. **Test time:** default ≤ 0.1 s; slow +≤ 10 s
(inside P44's option check); gate 0. **Acceptance:** [M10] the hair's second pass reviewed against the
approved close-up; the owner's notes applied or answered; the target catalogue, or the floor plus
what fits with each miss listed; the share within §2.12 by a Web export in its branch (the W26 merge
already excludes `tex_hi/`, and `GIANT_SHARE` is P41's) — and by P45's export of the merged
candidate. **Size:** about 1,600 lines plus data and generated assets. **Cross-lane symbols:** none.

### 3.7 P47 — Ship

- **Wave / lane:** W28, A (alone). **Depends on:** P45, P46, the M10 gate; the owner's approval of
  sheet B for the tag, the play link and the merge to `main`. **Milestone:** M10 (ship).
- **Goal:** as P40 did: the final check on the final code (every scene rebuilt with no diff; every
  tier; `--giant-full`; `--audio`; the soak; `--require --strict-times`); `README.md`,
  `ARCHITECTURE.md` and `DECISIONS.md` consolidated from `docs/systems/P41–P46` and §0.4 (the changed
  contracts of decisions 3 and 8 recorded beside the M0/M1 rows they replace; `CREDITS.md` linked);
  `docs/M10_HANDOFF.md` (the gate table with PASS / PARTIAL / FAIL / NOT RUN and evidence, the owner's
  decisions and approvals, the NOT RUN list); screenshots (`docs/screenshots/m10/`: the creator, the
  giant in the Valley and the world, first person, the stage lineup); the Linux, Windows and Web
  exports, with the Linux export run headless (the soak and an assisted bot run) and once under Xvfb
  with `--skin` (a screenshot, 0 errors) and `pck_files.py` listing `tex_hi/` in the desktop pack; the
  five Chromium checks; version `0.10.0-m10` and the project description; the launcher's notes ("the
  realistic giant and the character creator"). **After the owner's approval**: if they approved with
  notes, apply them (data or parameter changes within about an hour; anything larger becomes an M11
  follow-up) and re-run `--giant` (`--giant-full` if a bake input changed), the default and slow
  tiers, the Web build and the Chromium checks; then the tag, the play link (republished by the
  orchestrator), the pull request to `main` and the merge. **Size:** about 1,200 lines.

---

## 4. The M10 gate, the owner's look approval and the release

### 4.1 The gate review

After the W27 merge (`check.sh --build --slow --gate --giant-full --audio --require --strict-times`,
the soak and the capture tour). As at the M8 gate: one independent review agent per lens; every finding
verified adversarially (reproduced, or dropped); confirmed findings fixed in at most two worktree
lanes at a time, each with a regression test, and at most one lane at a time writing `assets/giant/**`
and its manifest; an audit of the fixes until it comes back dry. Minor confirmed findings that are not
fixed go to `docs/plans/FOLLOWUPS.md` under "From the M10 gate review", each with the package (or
milestone) that owns it. Owner notes on the preview that arrived after P46 finished are applied in a
gate lane (data and parameters) or answered.

| Lens | What the review checks |
| --- | --- |
| 1. The owner's request | Every category they named, at New Game, at the launcher's world start and at shrines: hair and beard styles and colours (with grey), tattoos, war paint, scars, skin tone, eyes, clothing with dyes; presets, Randomize and Undo; the flows (confirm → prologue or skip → creator → Begin; Back keeps the save and asks before discarding; the shrine tab, Keep, Cancel; the checkpoint; Continue; a death reload; the one-time messages); the floor catalogue met and the target met or its misses listed |
| 2. Gameplay unchanged | The full tiers; the code rules; `test_giant_determinism` with its positive controls (`SKIN_STATS` non-zero and different for two looks; grabs, throws and held-visual writes above 0 in the Valley twin); the 120 s seeded soak and the gate's world bot smoke run on the `main` commit of 0.9.0-m9 (in a scratch worktree) and on the candidate give byte-identical `AUTOPILOT_RESULT` lines once wall-time, node-count and memory fields are removed (the soak's `footfalls` field counts Heavy Footfall presses, so it proves the inputs replay; the rig's footfalls are compared through `SKIN_STATS`); no gameplay number in the diff (pivots, arm lengths, hurtboxes, sockets, camera geometry) |
| 3. Animation quality | Tip matching over every player weapon arc at stages 1, 3, 4 and 6 (§2.9's contract, on the exported landmarks); the frames of `test_skinned_rig_render`, `test_skinned_rig_stages` and the capture tour — idle, walk, run, sprint, jump, each weapon family's light and heavy, a block, both dodges, Shoulder Charge, Earthquake, a grab, hold and throw, a stomp, a roar, a self buff, a stagger, a knockback, the death fall, stages 1–6, first person looking down and ahead — reviewed for legs gliding in a frozen stride or stepping in the air, arms through the body on cross-body arcs, visible foot sliding, implausible wrists, the held body away from the hand, open cuts in first person or with the camera pressed close; misses fixed or listed for M11 |
| 4. Saves and migration | The fixtures; unknown and broken looks repaired with their notes in the load message; a look from a later build kept untouched; backup recovery with a look; a 0.10 save opened by the 0.9.0-m9 build (a scratch worktree) keeps its look through Continue and a checkpoint (the creator brief's lab test, re-run); a 0.9 save opened by the candidate gets the default look, its ancestry's mark and the one-time message |
| 5. UI and controls | Pad, keyboard (PageUp/PageDown, Q/E, +/−, Ctrl+Z, Ctrl+Enter) and mouse through every category; the focus never lost; the discard question; Undo; the layout at five sizes; the shrine's seven tabs at level 20; the footer hints; Game view and "Hidden by your clothing"; the Web pointer lock on Begin (`creator_check.mjs`) |
| 6. Web and performance | The pack ≤ 26 MiB and `GIANT_SHARE` ≤ 7.6 MiB (the owner's answer 1, §0.6), parts ≤ 15 MB; the five Chromium checks; ≤ 250 draw calls in every measured view; the skin's CPU; the four stall measures; texture and mesh memory; the Linux export under Xvfb with `--skin` |
| 7. Provenance and determinism of the assets | `--giant-full` bit-exact on the reference toolchain; `--giant` in a fresh worktree with the shared cache emptied; the vendored subset's audit; `PROVENANCE.md` and `CREDITS.md` complete; no copied GPL or Apache code; no hand-edited generated file; no `.import` under `tools/`; scenes rebuild with no diff; `test_ship_docs` passes |
| 8. The look | The owner's notes on the preview and sheet A applied; the hair at the creator's framings against the approved close-up; the options in play (the option check's rear and first-person frames: every design category readable); the giant among soldiers and buildings in the real world; the World style if they asked for it |

### 4.2 The owner's checkpoints

**0. Before W25 — the note** (the orchestrator; `OWNER_SUMMARY.md` beside this plan is its text). It
carries five in-engine frames the research already made (VERIFIED: they exist, revision; viewed,
owner review): `giant_asset/frames2/hair_compare.png` (the in-engine hair and beard,
three variants), `giant_asset/frames/world_thirdperson_medium.png` (the giant among the game's
soldiers at a game-like camera), `creator_lab/creator_lab_sheet.png` and
`creator_lab/frames2/ui_stormborn.png` (the creator's mock-up), `anim_lab/frames/lab_05_heavy_active.png`
(a heavy swing in the real `giant.tscn`), beside the approved renders `test_studio_full34.png` and
`test_outdoor_head.png`; the scope in plain words (the player's giant only; one face and one build;
hair drawn as game cards, not strands; the weapons, soldiers and world unchanged; Web textures at half
resolution unless they raise the budget); the questions of §0.6; and the timeline of this section.

**The hair bar at the W25 merge** (internal; the owner is not asked). P42's rendered suite saves the
long hair and the full beard at the creator's Face and Hair framings on the real model; the merge
record puts them beside the approved close-up and the research's best variant (the right-hand frame of
`hair_compare.png`). If they are no better than that variant (shingle steps on the outline, scalp
showing between the crop's cards), P46's item 1 is confirmed as its first two hours, and the W26 note
to the owner says what they will see and what P46 is doing about it.

**1. After the W26 merge — play it.** The orchestrator builds the W26 tip with `build_web.sh` into a
separate private page (the public 0.9.0-m9 link is untouched; about 19.5 MiB, §2.12), smoke-tests it
with `world_check.mjs` and one creator pass, records a 60–90 s video from the capture tour
(`--write-movie` at 30 fps, cut with ffmpeg; both present here, VERIFIED owner review), and renders
**sheet A** with P44's tool — labelled 1920 px pages from the merged game (the Compatibility renderer
under Xvfb with the game's sun, ambient, sky and fog values):
1. *Our giant in the engine*: the Wanderer at the third-person camera's distance beside the game's real
   soldier and villager scenes on the game's ground; and side by side with the Blender renders the owner
   approved, at the same angles (the studio three-quarter view and the head close-up), so the gap —
   cards against strands, wrap lighting against subsurface scattering — is seen before the content is
   multiplied.
2. *Hair and beards*: every floor style in three colours, from the front and from behind; grey at 0,
   0.5 and 1; the eight presets in full body.
3. *Skin and eyes*: the ten tones; the eye colours in face close-ups.
4. *Designs*: the tattoos by region in two inks, the war paints, the scars and the ancestry marks, each
   also in the stage-1 Game view (what reads in play).
5. *Clothing*: the four outfits in two dye pairs.
6. *Web and desktop*: the creator's face framing at the 512 px and 1024 px tiers.

The owner answers "go on", with notes (P46 applies them as they arrive; late ones go to a gate lane), or
"change the direction" (the orchestrator re-plans P46's items 3–5 before P46 reaches them). Nothing
waits for them.

**2. After the gate — approve it.** **Sheet B** is rendered from the candidate after the gate's fixes
(not before them): the same pages with the target catalogue and the revised presets; the creator at
1280x720, at New Game and at a shrine; the giant in the real game — the Valley, the Kingsgate shelf and
Fort Aldmere's gate — at the third-person camera with soldiers in view; first person at stages 1, 4
and 6; a heavy swing in three frames; the stage 1–6 lineup; the World style if they asked for it. The
release candidate goes to the same private page. **The tag, the play link and the merge to `main`
wait for their answer**: "approve" → P47 finishes; "approve with notes" → P47 applies them (data or
parameters, about an hour; anything larger becomes an M11 follow-up) and re-runs the checks of §3.7;
"not yet" → one fix lane on their notes, then sheet B again.

### 4.3 Release 0.10.0-m10

As M6–M9 §6.6. Version `0.10.0-m10` (`build_web.sh` reads `-m10` and applies the 26 MiB budget the
owner chose, §0.6); the Linux export runs the soak and an assisted bot run headless and one
`--skin` run under Xvfb (a screenshot, 0 errors), and `pck_files.py` lists `tex_hi/` in its pack; the
Windows export is built (not launched); `tools/build_web.sh`, run without `XDG_DATA_HOME`, builds the
`Web` preset and reports the shipped sizes, the parts and `GIANT_SHARE`; `creator_check.mjs`,
`world_check.mjs`, `audio_check.mjs`, `world_start_check.mjs` and `stream_check.mjs --world --audio`
pass in headless Chromium on the release build (the M8 release's list plus the creator's check); the
launcher's notes describe the build. Only after the owner approves sheet B (and after the re-checks of
§3.7 when they approved with notes): the tag `0.10.0-m10`, the play link republished by the
orchestrator, P47's pull request to `main` and its merge.

### 4.4 Owner tasks (NOT RUN here)

The look on their own screens (a real GPU, a real browser) with the usability script's look section
(P46); a 10-minute session — New Game through the creator into the Valley, a change at a shrine,
first person at stage 4 — on desktop and in a browser; frame times and the warm-ups on real hardware;
a real gamepad in the creator. Two decisions are theirs: the Web budget (decided before W25: 26 MiB) and M11's
direction (the recommendation: people near the camera on the same pipeline, §0.5).

---

## 5. Risks and mitigations

| # | Risk | Mitigation |
| --- | --- | --- |
| 1 | **The art-style mismatch**: a realistic giant among low-poly soldiers, houses and trees, most visible up close and in fights | The owner accepted it (§0.2); they see it in the world before W25 (the research frame) and plays it after W26; the giant is lit by the game's own sun, ambient and fog; the World style on request (§0.6); M11 recommended: the people near the camera on the same pipeline (§0.5) |
| 2 | **The expectation gap**: the owner approved Cycles strand renders; the game draws cards, wrap lighting and 512 px maps on the Web | The pre-W25 note shows the in-engine hair now, beside their approved render; the playable link after W26; the hair bar at the W25 merge and the hair's second pass first in P46; the cut list protects hair; the 1024 px desktop tier; the 26 MiB option |
| 3 | **The Web budget is exceeded** | The share measured from W25 on (P41's export, the W26 preview build, P45); `GIANT_SHARE` fails the build over 4.6 MiB; the meshes dominate (1.76 MiB, VERIFIED asset brief), so garments and boots are decimated first, then the hair's LODs dropped (the body's kept), then target content cut in §6.3's order; the 26 MiB option |
| 4 | **Animation quality**: the 7° offset, arms through the body on cross-body arcs, wrist bends, the grab gap, foot sliding, glides and stepping in the air | Tip matching measured over every arc on the exported landmarks; elbow poles per arc side and grip axes per weapon family; the legs' sources gated by the brain's state; the airborne pose and the death clip; the held-visual offset; the capture tour and the gate's frame review; the stomp clip and the rest deferred and listed |
| 5 | **Determinism**: a presentation layer that writes where it should not, or draws from a shared RNG | Write-only by contract and by code-rule tests; the gate suite with positive controls (two looks really drawn, grabs and held-visual writes really exercised); the cross-version soak and bot comparison; Randomize's own RNG; the bots and command-line starts never see the creator |
| 6 | **The asset pipeline is not reproducible elsewhere** | A pinned venv with hashes, shared by every worktree; `--skip-bake` regenerates every output in a fresh worktree in minutes; `--require` makes a missing venv a failure; `--verify` compares sources and the manifest, never `.godot/imported`; a tolerance mode for the Cycles bakes on another CPU; the committed outputs stay authoritative for the game |
| 7 | **The default tier passes 75 s** (it already runs 56–88 s, VERIFIED) | Headroom moved first (P42, ≥ 3 s); the skinned layers off headless; the model and textures held once per process; caps counted per suite; 2 s reserved; `--strict-times` re-runs a slow tier once |
| 8 | **Licences and provenance**: CC0 data inside a third-party wheel, with GPL and Apache code nearby | Data only, audited against the wheel's sha256; `PROVENANCE.md` and `CREDITS.md`; the kit's code is original (the research run read the Apache code only as a reference); bpy builds and is not redistributed; the project's licence stays the owner's choice |
| 9 | **Shader compile stalls** (1.3–2.0 s on the Web's software renderer, VERIFIED creator brief) | The title's warm-up before its buttons enable ("Preparing..."); the title, creator, level and shrine paths measured by `creator_check.mjs`; the loading screen's warm-up if a path stalls; real browsers NOT RUN |
| 10 | **Real GPU and browser costs are unknown**: every measurement ran on a software renderer | Conservative budgets for draw calls, CPU and memory; the owner's tasks (§4.4) |
| 11 | **First-person and pressed-close views**: hollow limbs, floating limbs, seams | Every cut capped and the limbs closed (a mesh test); the head on its own layer; the torso's pressed-close rule decided by a render; per-mesh LODs keep the seam (VERIFIED feasibility review); the rendered first-person checks at every stage |
| 12 | **Save compatibility** with a cached 0.9 web build, a later build or a broken look | Schema 2 kept; the key optional; repair with notes the player sees, never a failed load; a later build's look kept untouched; the gate's cross-version run |
| 13 | **Scope against 2–3 days** | The honest estimate (about 3 days) said to the owner up front; the floor first and the target only after they have played it; the cut list (§6.3); split points in every package |
| 14 | **Merge conflicts in hotspots** | P42's pre-declarations (tested); the single-owner table; one writer at a time for the generated assets, the gate's lanes included |
| 15 | **A busy machine** (the render workflow, any M9 follow-up) | `nice -n 19`, Cycles at 2 threads, one export at a time; the shared bake cache; `--giant-full` only when bake inputs change, at the W27 merge and in P47; per-suite accounting instead of the noisy total |
| 16 | **Patchy or shingled hair cards** (VERIFIED, the research's frames) | The hair bar at the W25 merge; P46's item 1; hair and beard styles last in the cut list; the `length` uniform; the owner's notes |
| 17 | **Morph artefacts** | No shape keys in M10 (decision 10) |
| 18 | **Repository growth** | The 25 MB budget; the CC0 subset trimmed (−3.1 MB raw possible, VERIFIED asset brief); no EXR or bake intermediate committed (the rest maps and the cheap passes are re-baked) |
| 19 | **The headless-off skin hides a bug** from the default tier and the bots | The skin suites force it on; the rendered slow and gate checks; the gate suite runs the soak and a Valley bot with `--skin` and proves it ran; the capture tour; the Linux export under Xvfb with `--skin` |
| 20 | **bpy 5.3.0 changes or disappears upstream** | The venv pinned with hashes and kept in one shared place; the committed outputs keep the game buildable without it |
| 21 | **The W25 lanes meet only at the merge** (`GiantLook` written against a synthetic model; tip matching against the brief's landmarks) | The index format and the landmarks are contracts (§2.5, §2.6); the real-model tests are written in W25 and run at the merge; fix-forward under 50 lines, else revert and re-run the package |
| 22 | **The owner's notes ask for a different body or face** | Decision 9's freeze and decision 10, both said in the pre-W25 note; such a note becomes M11 work unless the orchestrator re-plans (the clips and P43's suites would be redone) |
| 23 | **The private preview shows rough edges before the look pass** | The note says it is a work-in-progress build; the public link stays 0.9.0-m9 until the release |

---

## 6. Estimate: agent-hours and wall-clock days on this machine

### 6.1 Per package

Every estimate in this section is ASSUMED, calibrated on the M6–M9 record quoted in §6.2.

| Item | Agent-hours: central (range) | The long poles |
| --- | --- | --- |
| Before W25 (the orchestrator) | 1.5 (1–2.5) | the re-checks on 0.9.0-m9; the venv's download; the owner's note |
| P41 | 6 (5–8) | porting about 3,870 lines; the three-way split and the caps; nine designs and the packer; `--giant-full` twice; one Web export |
| P42 | 5 (4–6.5) | the sanitize matrix; `GiantLook` on a synthetic model; tip matching over every arc |
| W25 merge (the real-model tests, the hair frames) | 1 | |
| P43 | 6 (4.5–8.5) | the clips; the legs' sources; the modifier's poles and grip axes; six suite rewrites; the determinism suite; the capture tour |
| P44 | 5.5 (4.5–7.5) | the rows and focus of nine categories; Undo and the discard question; the layout at five sizes; the option check; the sheet tool |
| W26 merge (the preview link, the video, sheet A) | 1.5 | |
| P45 | 4 (3–5.5) | two Web exports of about 10 minutes each; five Chromium checks; four stall measures |
| P46 | 5 (3.5–7) | the hair (the asset brief budgets a day of art tuning); the owner's notes (unknown in size); the target content |
| W27 merge (`--gate --giant-full`) | 1.25 | |
| The M10 gate: eight lens reviews, verification, two fix lanes, the audit | 16 (10–24) | |
| Sheet B from the candidate | 0.5 | |
| P47 | 3.5 (2.5–4.5) | the final check (about 45 minutes with `--giant-full`); the exports; the docs |
| After the owner's approval: notes, re-checks, the release | 1.5 (1–2) | |
| **Total** | **≈ 58 agent-hours (43–80)** | |

### 6.2 Wall clock and the critical path

Two lanes, so a wave lasts as long as its longer package plus its merge: before W25 1.5 h; W25 ≈ 7 h
(P41 and the merge); W26 ≈ 7.5 h (P43, the merge, the preview link, the video and sheet A); W27 ≈ 6.25
h (P46 and the merge); the gate ≈ 10 h; sheet B ≈ 0.5 h; P47 ≈ 3.5 h, which runs while the owner looks
at sheet B; after their answer ≈ 1.5 h: **≈ 38 hours of work at full speed**. Two things stretch it: the
machine (4 CPUs) may still be shared with the render workflow after M9 ships (a factor of about
1.1–1.3 on every check, bake and export, ASSUMED), and the release waits for the owner's answer on
sheet B (their notes after W26 never block). **Estimate: about 3 calendar days from the 0.9.0-m9 ship to
the release** if they answer sheet B within about half a day; **2.5 days** at best (a free machine, no
overrun, fast answers); **4 days** with the likely overruns (the hair's quality, the rig on cross-body
arcs, the first-person caps, gate findings). The owner asked for 2–3 days; the note before W25 tells
them this estimate.

Calibration (VERIFIED, revision, git): M6–M9 waves of two packages took about 2–5.5 hours of wall
clock each (W19 and W20 about 2 h each from tag to tag; W22, P38 alone, about 5.3 h); the M6 gate (5
findings) took about 3 hours; the M8 gate (46 findings across a whole open world) took 16.3 hours to
its last fix-up merge and 20.7 hours to its tag. M10's gate surface is far smaller than M8's but adds a
frame review and the owner's loop, hence 10 hours (6–16). M10's packages are smaller in lines than
M8's, but they bake, render and export, and the look has a human in the loop.

**Against the draft**: the draft estimated 38 agent-hours and 2–3 days. The revision adds about 7
agent-hours of package work the reviews found necessary (the head split and the caps, the legs'
sources and two clips, Undo and the discard question, the reading-in-play checks, the positive
controls, the launcher, the per-suite accounting and the shared venv), net of about 2 given back by
dropping the World style and the first-person mask pass; it budgets the gate at the precedent's scale
(16 agent-hours and 10 wall-clock hours instead of 8 and 5); and it adds about 5 hours of
orchestration (the re-checks before W25, the preview link and sheet A, sheet B from the candidate,
the re-checks after the owner's answer).

### 6.3 What fits, and the cut list

**Never cut** (the gate's core): the creator at New Game, at the launcher's world start and at shrines,
with Undo and the discard question; saves, their repair and its messages; the floor catalogue (§2.3);
presets and Randomize; the skinned giant with tip matching, growth, first person with closed cuts, the
run clip, the legs' state gating, the airborne pose and the idle stopping at death, grabs, tints and
flashes; gameplay unchanged and the determinism suite with its positive controls; the asset pipeline
with provenance and `--verify` in any worktree; the Web budget and the five Chromium checks; the
rendered option check with its rear and first-person views; the hair's second pass; the owner's look
approval.

**The cut list**, first to go first:
1. A material pass on the weapons (only if the owner asked for it, §0.6 question 4).
2. The end-screen portrait.
3. The stomp's leg clip (the arms keep today's stomp).
4. Target content, in this order: the third new garment and its outfit; scars 5–6; war paints 3–4;
   tattoos 9–16 (the sleeve and the shoulder piece last); then hair and beard styles, last of all
   content: the forked beard, the wild mane, the warrior tail, and the braided-strand atlas with the
   braided beard and the long braid.
5. The death clip (today's fall stays; the idle still stops).
6. The hair's `length` uniform and its sway.
7. The Game view button (the option check's rear views stay).
8. Ancestry marks (`mark: "auto"` then resolves to nothing; the locked eye colours and skin tone stay).
9. The tab's "(new)" mark (the one-time message stays).

---

## 7. Verification log

**The planning run** read the three briefs, `M6_M9_PLAN.md`, `ARCHITECTURE.md`, `DECISIONS.md`,
`FOLLOWUPS.md`, the system docs P38 and P39f, and the code it cites, and ran four small probes in a
standalone Godot 4.6.3 project in the scratch folder (`<scratchpad>/m10_plan/planner_lab/`, headless,
`nice -n 19`), with the research runs' outputs as inputs:

| Probe | Result (VERIFIED) |
| --- | --- |
| 1. Load and cache-miss reload of the research giant's imported scenes and textures | first load: body and garments 4.4 ms, hair 1.5 ms, the lab's skinned giant with clips 3.3 ms, seven textures 18.5 ms; cache-miss reloads (`CACHE_MODE_IGNORE_DEEP`, median of 5): 3.0 ms, 1.1 ms, 2.5 ms and 16.3 ms |
| 2. Synchronous instancing (instantiate, enter the tree, free; 200 each, two rounds) | an eight-box stand-in 0.027 ms; body, eyes and seven garments 0.15 ms; the same with hair and beards 0.28 ms; the lab's giant with clips 0.13 ms |
| 3. A 256x1024 tiled PNG with the `2d_array_texture` importer (4 vertical slices, VRAM compressed) | a `CompressedTexture2DArray`: 4 layers, 256x256, format 19 (DXT5), mipmaps; accepted by a ShaderMaterial's `sampler2DArray` uniform; a `TextureLayered`, not a `Texture2DArray` |
| 4. The lab's glTF with the `animation_library` importer | an `AnimationLibrary` with `grip` (0.033 s), `idle` (2.000 s) and `walk` (1.067 s), 45 tracks each, loop off; 12,188 bytes imported |
| Also | `rig.game_engine.json` of the CC0 data lists 53 bones; the briefs' only text that `test_ship_docs` would flag is their scratch-folder paths (15 lines) |

**The three reviews** ran their own probes (`<scratchpad>/m10_plan/critic_feas/probe_results.txt`:
DXT crosstalk, LOD seams, edits inside an instance, headless uniforms, the vendored data's import;
`critic_proc/`: an import project and two export runs; `critic_owner/owner_lens_numbers.py`: on-screen
sizes, footfall rates, the hip cut's pitch). Their findings and verdicts are in §8.

**This revision** (2026-11-12, read-only on the repository; no scratch worktree was needed) checked:
- the kit's and the research scripts' sizes (`wc -l`), and that no export, bake or hair script imports
  `giant_pose.py` (`grep`); the four designs and their channels in `tattoo_masks.py`; the bake pass
  times in `giant_asset/logs/bake1024.log` (cheap passes ≈ 139 s, AO 534.6 s, thickness 116.9 s,
  793 s in all);
- in the code at `1c33b8e`: `tools/gd.sh` and `.gitignore` (`.userdata/` per worktree); `check.sh`'s
  75 s warning; the rendered suites' skip on a missing `xvfb-run`; `parse_args`, `start_sandbox`,
  `_clear_session` and `on_level_ready` in `game_session.gd`; the soak's injected inputs and its
  `footfalls` field in `autopilot.gd`; `bot_combat.gd`'s grabs and throws and `run_metrics.gd`'s
  counts; `test_valley_audio_determinism.gd` (150 s twin runs); the walk-phase gate, the leg swing,
  the ability poses and the death fall in `actor_rig.gd`; `speed` in `get_rig_state()`; the jump in
  `combat_controller.gd`; the motor's turn toward movement; `dodge.json` and `shoulder_charge.json`;
  `UiScreen.cancel()`, `ScreenStack`'s cancel handling and `UiNav.page_step`; the camera's single
  hidden layer and `weapon_visuals.gd`'s layer-2 canopy and needles; the title's boot in `main.gd`;
  `SceneKit.own()`; `SaveSlots.read()`'s message and `CharacterState.sanitize()`'s return; the New
  Game tests, `audio_check.mjs`, `world_start_check.mjs`, the launcher's world start and the M8
  release rows in `PERFORMANCE.md`; `.userdata/check/suite_times.txt`; `test_predeclared_m7.gd` and
  M6–M9's P20 test list; `data/tutorial/` records; M9's changes on `pkg/P39f` (`nav_hint()` and the
  files of §1.2);
- the wave and gate times from the tags and merge commits (§6.2);
- the creator lab's palette constants (§2.4's pinned values) and the animation lab's body source
  (`anim_lab/export_test_giant.py` imports the live kit);
- viewed: the in-engine hair frames, the giant among soldiers, the creator mock-up and the approved
  head render;
- ran the owner review's numbers script (the same results).

It did not render a World-style frame: the machine was at a load of 5.5 with two Blender renders and
an M9 gate-tier run, and the plan defers the World style instead (§0.5). The repository's main
checkout and M9's worktrees were not modified.

### Before W25: the re-check on 0.9.0-m9

**14 November 2026**, on the main checkout at `86671d3` (the merged 0.9.0-m9 code, `523b956`, plus this
plan), read-only except for this section and the in-place corrections marked "(re-checked on
0.9.0-m9)"; 178 commits after `1c33b8e`. Every Godot run went through `tools/gd.sh` under `nice -n 19`;
the labs ran in a scratch copy of HEAD (`git archive` plus the import cache), never in the repository.
Evidence: `<scratchpad>/m10/w25/recheck/` (the two default runs, the lab run, the probe logs, the Web
pack's JSON and listing, `diffstat_1c33b8e_HEAD.txt`, `heaviest_default_suites.md`).

**The code facts of "in the code at `1c33b8e`"** (`git diff 1c33b8e HEAD` on each file, then read):

| Fact | The plan said (at `1c33b8e`) | Now (0.9.0-m9) |
| --- | --- | --- |
| `game_session.gd`: `parse_args`, `start_sandbox` clearing the character, `_clear_session`, `on_level_ready` applying a character only on a pending restore | as §0's header | Still true. The file changed in two places only: `_note_respawn_moved` uses `TextUtil.with_the()` (M9 gate), and a comment in `_on_quest_stage_changed` |
| `autopilot.gd`: the soak's injected inputs (light, heavy, block, dodge, `slot_1`, jump, lock, camera, target; no grab) and `footfalls` = `slot_1` presses | as §0 | Still true. Added: `bot_probe()`, `perf_sections()` and the result's `perf.sections` for bot runs (P39), and `_exit_tree()` printing `WORLD_WALK_UNLOAD` in a world walk (P39f, read by `world_check.mjs`) |
| `bot_combat.gd` grabs and throws; `run_metrics.gd` counts both | as §0 | Still true. `bot_combat.gd` +234 lines (P39/M9 gate: Rampart Grip asks the grab, engine throws, ability choice); `run_metrics.gd` leaves every throw out of the ability share through `PlayerGrab.is_throw()`, adds `faction_standing` and the level and place to `load_samples` |
| `actor_rig.gd`: walk phase only in `LOCOMOTION`/`BLOCKING`, the leg swing, no `body_sweep`/`line_pulse` pose, the 0.48π death fall | as §0 | Unchanged file. Still true |
| `combat_controller.gd`: a jump stays in `LOCOMOTION`; the motor turns toward movement; `speed` in `get_rig_state()` | as §0 | Unchanged files (`scripts/combat/combat_controller.gd`, `scripts/actors/player/player_motor.gd`, `giant_player.gd`). Still true |
| `dodge.json` (`data/actions/`), `shoulder_charge.json` | 4.5 m in 0.45 s; 26 m/s for 12 m | Unchanged. Still true |
| `UiScreen.cancel()` closes without asking; `ScreenStack`'s cancel handling; `UiNav.page_step` pad-only | as §0 | Still true (`ui_nav.gd` unchanged; `cancel()` and `handle_cancel()` untouched). M9 added `UiScreen.nav_hint(pad)` (UiNav's line by default; "" hides the footer) and the stack now reads the top screen's `nav_hint()` every frame in `_process`; while any screen is open the HUD hides (`Hud.MenuWatch`) and so does the `hide_under_screens` group (the shrines' floating names) |
| The camera's one hidden layer (2, first person and pressed close); `weapon_visuals.gd`'s canopy and needles on layer 2 | as §0 | Unchanged files. Still true |
| `main.gd`'s title boot (no loading gate) | as §0 | Unchanged. Still true |
| `SceneKit.own()` never owns an instance's children | as §0 | Unchanged. Still true |
| `SaveSlots.read()` reports only dropped ids; `CharacterState.sanitize()` returns data and dropped ids | as §0 | Unchanged files. Still true |
| The New Game tests; `audio_check.mjs` and `world_start_check.mjs` press Enter; the launcher's world start passes `--mode=world` | as §0 | `test_session_flow.gd`, both `.mjs` files and the launcher's start buttons unchanged. `test_title_checkpoint_names.gd` gained M9's checks: the save line's mid-sentence "the" and a new `test_display_names_read_lower_case_mid_sentence` (every pickup, talker, forge, battle and exit line). The 0.9.0-m9 release ran `audio_check.mjs`, `world_start_check.mjs`, `stream_check.mjs --world --audio` and P39f's new `world_check.mjs` (a Continue of a v2 world save, a fast travel and a walk), all OK in their default form (three of them re-run on the quiet machine) |
| `test_predeclared_m7.gd`; `data/tutorial/` | as §0 | Unchanged. Still true |
| `test_valley_audio_determinism` (gate, 150 s twin runs) | as §0 | Unchanged. Still true |
| The base's test tiers | default 56.2–88.4 s; 281 suites, 48,145 checks (P39f) | 291 suites (55 / 154 / 53 / 29), 50,114 checks at P40's final check; default 209 suites, 38,005 checks; see the runs below. Corrected in §0's header and §1.7 |

**The four probes** (`<scratchpad>/m10_plan/planner_lab/proj` copied without its import cache,
re-imported in 5.3 s, each probe run twice; the engine and the research assets are the same, so these
re-measure the machine, not M9):

| Probe | Planner (§7 above) | Re-check, two runs |
| --- | --- | --- |
| 1. First load: body and garments, hair, the lab giant with clips, seven textures | 4.4, 1.5, 3.3, 18.5 ms | 5.8 / 7.2, 1.9 / 2.4, 5.0 / 5.5, 26.0 / 27.6 ms |
| 1. Cache-miss reload, median of 5 | 3.0, 1.1, 2.5, 16.3 ms | 5.1 / 5.1, 1.7 / 1.9, 3.7 / 4.3, 22.8 / 25.1 ms |
| 2. Instantiate + enter tree + free: 8 boxes; body, eyes, 7 garments; with hair; the lab giant | 0.027, 0.15, 0.28, 0.13 ms | 0.030–0.038, 0.16–0.19, 0.34–0.44, 0.15–0.20 ms |
| 3. The 2D-array import | `CompressedTexture2DArray`, 4 layers 256x256, DXT5 (19), mipmaps, accepted by a `sampler2DArray` | the same |
| 4. The `animation_library` import | `grip` 0.033 s, `idle` 2.000 s, `walk` 1.067 s, 45 tracks, loop off | the same |
| `rig.game_engine.json` | 53 bones | 53 bones |

The timings are 1.2–1.6 times the planner's (the machine ran slower than during planning: the
default tier too, below). The conclusions of §1.7 rule 3 stand: a cache miss now costs about 28–30 ms, so the
`preload` and the static texture cache matter more, and instancing stays well under 1 ms.

**The creator brief's shrine fit and save lab**, on HEAD's `shrine_screen.gd`, `ui_screen.gd`,
`title_screen.gd` and save code (the lab's `shrine_screen_tabs.diff`, `appearance_tab.gd` and its two
lab suites in the scratch copy, then the whole default tier there):

- **The seventh tab fits as before**: tabs Rest, Grow, Loadout, Attributes, Talents, Ancestry,
  Appearance; the tab row's minimum width 542 px; the panel at (260, 54), 760x580, inside the room
  above the footer (1280x690); every tab's panel and Leave inside; RB visits all seven. M9's open-tab
  marking (`UiKit.set_tab_open`, same size open or closed) changes none of it.
- **The save lab passes on M9's code** (12 checks, 0 failures): the 887-byte `appearance` block in a
  2,537-byte save survives `write`, `read()` (no message), Continue (apply, capture, normalize), the next
  checkpoint and a death reload; a schema 3 save is refused with the same message and Continue is off.
- **The suites that assert the exact tab list** (the default tier with the seventh tab: 211 suites,
  7 failures, all expected): `test_shrine.test_shrine_screen_rest_and_grow_tabs`,
  `test_shrine_panel_fit.test_every_tab_and_the_ancestry_screen_fit_at_level_20`,
  `test_talent_tab.test_the_talents_and_ancestry_tabs_with_a_pad` (the list, "LB twice from Rest" now
  Ancestry, and a follow-on null) as the brief said, **and one the brief missed**:
  `test_progression_player.test_shrine_loadout_and_attributes_tabs` (`["Rest", "Grow", "Talents"]` gains
  Appearance). That suite is unchanged since `1c33b8e`: the brief's lab ran only the shrine, focus,
  ancestry and choices suites. Added to P44's owned tests (§3.4). In W25 nothing fails: P42's `TABS`
  entry is skipped until P44's `appearance_tab.gd` exists.

**The files of §1.5 and §1.2** (`git diff --stat 1c33b8e HEAD`, every file of §1.5's tables; the list
is `diffstat_1c33b8e_HEAD.txt`). Changed: `game_session.gd` (+10 −2), `screen_stack.gd` (+40 −5),
`title_screen.gd` (+12 −3), `shrine_screen.gd` (+6), `ui_screen.gd` (+6), `autopilot.gd` (+41 −1),
`test_ship_docs.gd` (+86 −2), `test_title_checkpoint_names.gd` (+59 −3), `tools/check.sh` (+3),
`web/launcher.html` (+8 −7), `tools/web/` (5 files, +866 −18: `world_check.mjs`, its test and config are
new; `stream_check.mjs` exports its helpers; `audio_recorder.mjs` counts holes cut at the disarm),
`project.godot` (the version), and the docs (`PERFORMANCE.md`, `USABILITY_SCRIPT.md`, `FOLLOWUPS.md`).
`test_shrine.gd` (+108, M9's tab-marking and shrine-name tests) is not in §1.5 but is P44's in W26.
Every other file is unchanged, and every M10 path (`tools/giant/`, `assets/giant/`, `data/appearance/`,
`giant_model.gd`, `giant_look.gd`, `tip_matching.gd`, `CREDITS.md`) is still absent. No change moves a
hunk §1.5 assigns or collides with one.

**The two default-tier runs** (after an import, one after the other, nothing else running, 4 CPUs):
run 1 **78.3 s** (load 0.06 before, 1.05 after; wall 81.1 s), run 2 **79.8 s** (0.39, 1.39; wall 82.6 s),
both 209 suites, 38,005 checks, 0 failures, `WARNINGS: 0`. Both are over 75 s on a quiet machine; P40
recorded 73.0–73.4 s for the same code about 1.5 hours earlier (07:29–07:52 UTC), and the last twelve recorded runs read
65.8–77.9 s. The five heaviest suites (run 1 / run 2): `test_anchors` 11.03 / 10.89 s (the compile check,
10.3 s of it), `test_tutorial` 5.22 / 5.06 s, `test_data_and_saves` 3.53 / 4.10 s, `test_boss_arena`
2.64 / 2.74 s, `test_growth` 2.52 / 2.82 s. The 30 heaviest, their per-test times (a third run in the
scratch copy with a per-test print) and the move candidates are in
`<scratchpad>/m10/w25/recheck/heaviest_default_suites.md`: the two prompt-queue tests of
`test_tutorial` (about 3.8 s), `test_growth`'s stage-2/3 reach tests (1.8 s), `test_boss_arena`'s ten
seeded charges (1.5 s), `test_schemas_v2`'s untelegraphed-attack warning (0.6–0.9 s, repeated by
`test_ranged_brains`), `test_wolf`'s stage-1 reach (0.7 s), `test_boss_disengage`'s walk to the talker
(0.6 s). The suites of §1.7 rule 2 on the base: `test_growth` 2.52 / 2.82 s, `test_grab_throw` 1.35 /
1.50, `test_weapons` 1.13 / 1.08, `test_session_flow` 0.79 / 0.88, `test_camera_review_fixes` 0.17 /
0.19, `test_rig_merge` 0.10 / 0.09, `test_growth_456` 0.07 / 0.07.

**The Web pack** (`tools/build_web.sh --out=<scratchpad>/m10/w25/recheck/web`, without
`XDG_DATA_HOME`; the folder deleted afterwards, `web_pack.json` and `web_build.log` kept): `index.pck`
17,591,292 B raw, 13,124,494 B gzipped, **17,499,328 B shipped = 16.69 MiB** of 23, in 2 parts of
8,749,664 B; 2,754 packed files, no test content (`pck_files.py --check-no-test`), every record valid
without `data/test`; audio 9.28 MB (55 %). Against the plan's 17,399,456 B (16.59 MiB) at `1c33b8e`:
+99,872 B (+0.10 MiB); against 0.9.0-m9's release, 17,500,048 B: −720 B. Corrected in §2.12's
arithmetic (floor ≈ 19.6, target ≈ 21.2 MiB of the owner's 26).

**The shared venv** (created by the orchestrator, step 3): `$HOME/.cache/giantborn/giant-venv`, 1.2 GB,
with `GIANT_CACHE` at `$HOME/.cache/giantborn/giant-cache`;
`$GIANT_VENV/bin/python -c "import bpy, numpy, scipy, PIL, OpenEXR"` works and reports Python 3.13.18,
bpy 5.3.0, numpy 2.5.4, scipy 1.18.1, Pillow 13.0.0, OpenEXR 3.5.4, the plan's pins. It installed in
45 s from pip's cache (not the 10–15 minutes ASSUMED in §1.2); `pip freeze` is in
`<scratchpad>/m10/venv_record.txt` for P41's pinned requirements.

**What the packages must now do differently:**

- **P42 (§1.7 rule 4, §3.2 design 2):** the base already runs 78–80 s, so moving 3 s is not enough for
  the W25 merge's `--strict-times` (the faster run must be under 75 s with P41's 0.4 s and P42's 0.6 s
  added). Move at least 3 s and as much more as P42's own two runs show is needed, about 6–7 s on the
  re-check's runs, starting from the candidates in `heaviest_default_suites.md`; `test_growth` is on
  rule 2's giant list, so moving its tests changes that list's baseline and must be recorded.
- **P41 (§3.1 item 11):** the base's per-suite times and Web pack are measured here; P41 may cite them
  instead of measuring the base again. Its `check.sh` edits (`--giant`, `--require`, `--strict-times`)
  keep M9's `BUDGET WARNING` / `WARNINGS:` lines (`tests/support/budget_rule.gd`); its `test_ship_docs`
  edit adds `res://tools/giant/mpfb2` to the existing `SKIP_DIRS` (today `["res://builds"]`) and keeps
  P40's handoff and placeholder checks.
- **P44 (§3.4):** update `test_progression_player.test_shrine_loadout_and_attributes_tabs` with the
  three shrine suites (corrected in its owned paths). Its `title_screen.gd` edits keep M9's
  `mid_sentence()` and `describe_save()` line; its rewrite of `test_title_checkpoint_names.gd` keeps
  M9's mid-sentence checks and `test_display_names_read_lower_case_mid_sentence`. `CreatorScreen`'s
  `nav_hint()` is read every frame by the stack, so it returns a cached line. At a shrine the HUD and
  the shrines' names are already hidden while the creator is open (M9).
- **P43 (§1.5's `autopilot.gd` row):** its edits (`--skin`, `--skin-stats`, `SKIN_STATS`) keep P39's
  `perf.sections` and P39f's `WORLD_WALK_UNLOAD`. The seeded Valley bot twin still grabs and throws;
  `run_metrics` now leaves every throw (`PlayerGrab.is_throw()`) out of the ability share.
- **P42 (saves):** `tests/fixtures/saves/v2_world_check_aldmere_shrine.json` (P39f, read by
  `test_world_check_fixture.gd`, the slow `test_world_check_route.gd` and `world_check.mjs`) is one
  more v2 fixture without a look: it must load with the default look and stays unedited.
- **P45 (§3.5):** `world_check.mjs` (P39f) Continues that fixture at the Aldmere shrine, so the
  legacy-save prompt of P42 shows during that check and must not count as an error. `creator_check.mjs`
  can import the server, the statistics and `loadPlaywright()` that `stream_check.mjs` now exports, as
  `world_check.mjs` does.

**Noticed, not an M9 change (for the orchestrator):** §0.6's owner answer 1 (26 MiB; the Web keeps the
1024 px maps) still meets the 23 MiB figures and the Web presets' `tex_hi/*` exclusion in decision 17,
§1.6, §2.12 and §3.1 item 9; the answers say they replace the defaults, and this re-check changed
neither. **Resolved** by the orchestrator in §0.6, "How answer 1 applies": W25 and W26 keep the
exclusion and the 23 MiB budget; P45 applies the 26 MiB budget and the 1024 px Web maps in W27.

---

## 8. Review log

Three reviews of the first draft (`M10_PLAN_v1_before_review.md` beside this file) — feasibility, the
owner and player, process and tests — reported 39 findings. Every finding was checked against the
code, the logs or the reviewer's probe output. All 39 are valid and folded in: 34 as proposed and 5
with a change (feasibility 8 and 14, owner 3, process 4 and 8). Seven of the reviewers' specific
proposals are rejected, each with a one-line reason (rows 1a, 2a, 3a, 3b, 7a, 4a and 8a below).

### 8.1 Feasibility review (14 findings)

| # | Finding | Verdict | Where, or why not |
| --- | --- | --- | --- |
| 1 | `check.sh --giant` cannot regenerate the designs or the pack in a fresh worktree (rest maps in a per-worktree cache, bake outputs not committed) | Accepted | §2.5 `--skip-bake` re-bakes the cheap passes and reads AO and thickness from the committed ORM; `GIANT_CACHE` and `GIANT_VENV` shared; §1.2 before W25 |
| 1a | Proposal: commit the full-resolution bake outputs (≈ 3.5 MB) | Rejected | The cheap re-bake (≈ 2.3 min, VERIFIED log) gives the same coverage without growing the repository toward its 25 MB budget |
| 2 | P41 does not fit one session and sits on the critical path | Accepted | P41 keeps the generated and imported side; the shaders, `GiantLook` and tip matching move to P42 (W25), the sheet tool to P44 (W26); split points in every package |
| 2a | Proposal: run a P41b (bakes, designs, pack, shaders, look) beside P42 in W25 | Rejected | P41b would need P41a's export in the same wave; the split by "generated" against "look" needs only the index contract |
| 2b | Proposal: put P43's mask pass on the cut list | Accepted (dropped) | The layer and mask assertions in `test_skinned_rig` prove the same headless; the frames are reviewed |
| 3 | The determinism trio passes without proving anything | Accepted | `--appearance=` in every mode (P42); `SKIN_STATS` positive controls and a Valley bot twin that grabs and throws (§3.3) |
| 4 | Several designs in one DXT5 layer ghost into each other | Accepted | §2.5's packing rule; `test_design_array.gd` round-trips every layer through the compressor |
| 5 | A SceneKit save drops edits inside an instanced model | Accepted | §2.5: layers and visibility from the index in `_ready`; the rig's nodes created at run time (§2.9); tests reload the scene from disk |
| 6 | `to_look(default) == DEFAULT_LOOK` cannot pass at the W25 merge | Accepted | Both sides in P42; the Wanderer's values pinned in §2.4; compared within 1/255 |
| 7 | A body change in P46 breaks P43's clips; tip matching measured on the lab's body | Accepted | Decision 9's freeze after W25; the landmarks in the index; tip matching re-run on them at the W25 merge |
| 8 | The shader warm-up covers only the title path | Partly accepted | The claim that the preview's variants recompile at a shrine is ASSUMED and doubtful (compiled variants stay while the cached shaders live), so P45 measures the shrine path and warms it behind the loading screen only if it stalls; the title's warm-up now runs before its buttons enable |
| 9 | The giant's Web share is under-counted | Accepted | The Web albedo at 512 px; the share re-computed (§2.12: 2.9 floor, 4.5 target) and measured from W25 (P41), at the W26 preview and by P45 |
| 10 | Godot imports the vendored CC0 data | Accepted | `.gdignore` in `tools/giant/mpfb2/`; a test that no `.import` exists under `tools/` |
| 11 | The rendered-suite time is under-budgeted | Accepted | Grids of small viewports (P44); P43 counts the change in the existing rendered suites; caps from the per-frame cost measured at the W25 merge |
| 12 | "Your giant's look could not be read" cannot reach the player | Accepted | `sanitize` returns notes; `SaveSlots.read()` joins them (P42 owns `read()` in W25) |
| 13 | Headless uniform checks miss a misspelled name | Accepted | `GiantLook.validate()` checks against `get_shader_uniform_list()` (§2.8) |
| 14 | The shrine preview has no defined way to hold the weapon | Accepted, another way | `GiantModel.hand_transform()` (P41) and `TipMatching.idle_grip()` (P42) exist in W25, so P44 needs no cross-lane symbol |

### 8.2 Owner and player review (10 findings)

| # | Finding | Verdict | Where, or why not |
| --- | --- | --- | --- |
| 1 | The owner never sees the giant move or plays the creator before approving; the questions reach them late | Accepted | §4.2: the note before W25 with the research frames and the questions; a private playable link, a video and sheet A after W26; sheet B after the gate, with "not yet" |
| 2 | Hair, which they named, is the weakest asset and the first cut | Accepted | The hair bar at the W25 merge; the Hair framing from behind; P46 starts with the hair; hair and beard styles last in the cut list; the `length` uniform |
| 3 | In motion the body breaks "reads as today" (frozen-stride glides, legs in the air, a plank death, a breathing corpse) | Accepted, with one change | §2.9's legs' sources, the airborne pose, the death clip, the idle stopping at death, the hair sway, the five moves added to the capture tour |
| 3a | Proposal: a skin locomotion clock from ground speed in every grounded state | Rejected | Running legs during a dodge or a knockback would read worse than today's planted stance; the clock runs only while an action's motion moves the giant (Shoulder Charge, lunges) |
| 3b | Proposal: a stomp clip as a required fix | Rejected as required | Today's stomp is drawn by the arms and still reads; the leg clip is cut-list item 3 |
| 4 | Most options do not read where the player looks, and nothing checks it | Accepted | Decision 18; §2.3's design rules and floor changes (`shoulder_bands`); the option check's rear and first-person views; "Hidden by your clothing" and the fade; Game view; Randomize avoids covered regions |
| 5 | The cut list would cut the stage-1 gait (the run clip) | Accepted | The run clip is never cut (§6.3) |
| 6 | One stray press loses the player's work; the swatch rule is ambiguous | Accepted | The discard question, Undo, Y per category, swatches apply on focus, keyboard keys (§2.10), tests in `test_creator_screen` |
| 7 | The render-layer split shows hollow limbs in first person and floating limbs when pressed close | Accepted | Decision 8: three body meshes, capped cuts, the head on layer 3, the torso decided by a render; P41's closed-mesh test |
| 7a | Proposal: a first-person mask test failing on background pixels inside the limbs | Rejected | Arms and legs leave real background between them, so a pixel test cannot tell a hole from a gap; P41's closed-mesh test is exact |
| 8 | The warm-up freezes the title, the play link's first screen | Accepted | "Preparing..." with the buttons enabled after the warm-up (§2.10); the title's worst frame in `creator_check.mjs` |
| 9 | The World style is built and put to the owner without ever being seen | Accepted | Deferred (§0.5); question 3 asks whether they want it; its time goes to the hair |
| 10 | The player is never told when the look becomes changeable, or when a mark appears | Accepted | Two one-time tutorial prompts (§2.11, P42) |

### 8.3 Process and tests review (15 findings)

| # | Finding | Verdict | Where, or why not |
| --- | --- | --- | --- |
| 1 | The tests, web checks and launcher that encode today's New Game are not updated | Accepted | P44 rewrites `test_session_flow` and `test_title_checkpoint_names`; P45 updates `audio_check.mjs` and `world_start_check.mjs`; the launcher's world start passes `--creator`; §4.3's release list restored |
| 2 | The gate trio can pass without testing anything; the `footfalls` claim is wrong | Accepted | §3.3's positive controls; lens 2 corrected (the soak's `footfalls` are Heavy Footfall presses) |
| 3 | `--giant` cannot reach the designs or the packed textures in a fresh worktree | Accepted | As feasibility 1 |
| 4 | The default tier has no headroom and the 75 s rule is judged against noise | Accepted, one change | Per-suite accounting, the 2 s reserve, P42's ≥ 3 s move, `--strict-times` (§1.7) |
| 4a | Proposal: the median of two runs decides | Rejected | With two runs the median is the mean, and this machine's noise only adds time; the faster run decides and both are recorded |
| 5 | Every new check can be skipped silently; the venv's home is not fixed | Accepted | `check.sh --require` at every package's final check, merge and gate; the shared venv created before W25 |
| 6 | P46's content and its verifiers are in the same wave | Accepted | The option check moves to P44 (W26); the `tex_hi/` exclusion and `GIANT_SHARE` to P41 (W25) |
| 7 | The release is not sequenced against the owner's approval | Accepted | Sheet B from the candidate after the gate; re-checks after notes; tag, link and merge only after approval; the Linux export under Xvfb with `--skin` and the pack listing (§3.7, §4.3) |
| 8 | The estimate's gate figure is not calibrated | Accepted, scaled | The gate at 10 h wall (6–16) and 16 agent-hours, the total at about 3 days (§6.2) |
| 8a | Proposal: a 10–16 h floor for the gate | Rejected as a floor | The M6 gate (5 findings) took about 3 h and M10's surface is far smaller than M8's open world; 10 h is the central figure, 16 the upper end |
| 9 | The gate's mechanics do not cover M10's outputs (capture tour, generated assets in two lanes, credits) | Accepted | `capture_m10` (P43); one lane at a time writes `assets/giant/**`; `CREDITS.md` (P41) |
| 10 | Facts read at `1c33b8e` are stale against M9 | Accepted | The re-check before W25 (§1.2); P44 overrides M9's `nav_hint()` and edits neither `screen_stack.gd` nor `ui_screen.gd` |
| 11 | The cross-lane `DEFAULT_LOOK` test fails at the W25 merge | Accepted | As feasibility 6 |
| 12 | The rendered-check caps are guesses, P43's too small | Accepted | P42's suite measures the per-frame cost at the W25 merge; P43's slow cap 45 s set from it; stages 4 and 6 in the gate tier; 320x240 with the render loop off |
| 13 | The save tests miss the future-version and backup cases | Accepted | §2.2's later-build rule; the future fixture; the backup test with a look (P42) |
| 14 | Godot imports the vendored subset; `test_ship_docs` scans it | Accepted | As feasibility 10, and `test_ship_docs` skips the folder (P41 owns the test in W25) |
| 15 | M10's pre-declared registry entries have no test | Accepted | `test_predeclared_m10.gd` (P42); `test_skin_rules` asserts the layers are off at each test's start |
