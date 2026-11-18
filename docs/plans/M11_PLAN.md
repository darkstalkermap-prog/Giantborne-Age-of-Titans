# Giantborn M11 plan: the giant refined, more customization, realistic NPCs

| Item | Value |
| --- | --- |
| Base | `main` at the 0.10.0-m10 release (`5ff50f0`: the merge of M10, the realistic giant and the character creator). The integration branch continues from it; wave tags continue from `wave-27` |
| Engine | Godot 4.6.3-stable (`7d41c59c4`), GDScript, Compatibility renderer, Jolt, fixed 60 Hz `Sim`. Asset pipeline: Blender 5.3 as the `bpy` 5.3.0 Python module (Python 3.13) in the shared venv `GIANT_VENV`, as M10 left it |
| Targets | Linux and Windows desktop exports and the single-threaded Web export (the play link) |
| Inputs | The owner's request and their three answers of 18 November 2026 (§0.2); `docs/plans/M10_PLAN.md` (structure and conventions); `docs/M10_HANDOFF.md` (what shipped, the gate table, the known limitations); every M11 row of `docs/plans/FOLLOWUPS.md`; `docs/systems/P41.md`-`P46.md`; `docs/ARCHITECTURE.md` §23; `docs/PERFORMANCE.md`'s M10 sections; the code at `5ff50f0`. **No research briefs**: M10 was planned on three research runs with labs; this plan is written from the M10 record and the code, so what it could not run is listed as probes to run before W29 (§1.2) and each carries its fallback |
| Output | 19 packages (P48-P66) in 10 waves (W29-W38, at most two agents at once, at most one of them writing generated assets), three parts each with its own gate, owner checkpoint and release |
| Releases | **Recommended: three, one per part** - `0.11.0-m11` (the giant refined), `0.12.0-m12` (more customization), `0.13.0-m13` (realistic NPCs). The alternative, one release `0.11.0-m11` at the end, is described in §4.4 with what it changes. The owner confirms one (§0.6, question 1) |
| Estimate | About 105 hours of work at full speed, about 182 agent-hours; 15-17 calendar days from the start of W29 (12 at best, 21 with the likely overruns), counted at the pace M10 actually had, not the pace it planned (§6) |

Every fact below is marked **VERIFIED** (read in the repository at `5ff50f0`, "code"; or measured by M10
and recorded in its handoff, system documents or `PERFORMANCE.md`, "M10 record"; or computed here from
such numbers, "derived") or **ASSUMED** (reasoned, not run). Design choices are not facts and carry no
mark. The facts that shape the plan:

- **The download today** (VERIFIED, M10 record: the handoff's §5.5): the page's whole download is
  36,520,414 bytes, of which the packed game data (`index.pck`, gzip then base64) is 23,586,472 bytes
  (22.49 MiB of the 26 MiB budget, two parts of 11,793,236 bytes) and everything else (the packed
  engine, the loader, the worklets, the launcher) 12,933,942 bytes (derived). `tools/build_web.sh`
  counts "MB" as 1,048,576 bytes, caps a part at 15,000,000 bytes, reads the budget from the version's
  `-mN` suffix (26 from m10 on) and caps the giant's files at the budget less 18.4 (VERIFIED, code).
  The launcher downloads the parts in order, joins their text and unpacks it in the browser
  (VERIFIED, code: `web/launcher.html`).
- **The giant's share and what a triangle costs** (VERIFIED, M10 record; the rate derived):
  `GIANT_SHARE` is 5,845,364 bytes shipped (5.57 MiB of 7.6) in 33 files; the two 1024 px maps are
  1.73 MiB of it. The model has 25 meshes and about 82,550 triangles at full detail (the index in
  `assets/giant/manifest.json`: body 27,104, eyes 1,120, five hair meshes 26,464, four beards 12,876,
  twelve garment meshes 14,986). Taking the textures, atlases, designs and clips at about 2.8 MiB
  leaves about 2.7 MiB for the meshes with their LODs and shadow meshes: **about 0.033 MiB shipped per
  1,000 triangles** (ASSUMED split; P48 measures it from a test export). Per 512 px map: albedo 89 KB,
  normal 329 KB, ORM 136 KB; a dense shape key on the 14,517-vertex body about 0.34 MiB.
- **What M10 left open on the giant** (VERIFIED, M10 record: the handoff's §5.2, §5.4, §9 and
  `FOLLOWUPS.md`): in the brain's generic arm poses the weapon sits on the knuckle line and the open
  off hand droops (LC-5); the stomp is drawn with the arms only; a weapon carried past its fit stage
  misses its tested capsule by up to 3.88 radii; run and sprint were never judged from the side; hair,
  braids and the cape follow the head or the back alone and the sway is a shader offset; the fringe
  still reads as cards at the Face framing, the crop has no fringe, the short and the braided beard
  keep wide cards, a beard from behind is the skin's tint alone; the lit skin is warmer than the
  approved renders (chest (222, 151, 115) in the creator's light against (198, 170, 157)) and a swatch
  shows the record's colour, not the colour drawn; the cape is a shell; the cloth details read
  coarsely; designs on the giant's left are framed from his right; the warrior's outfit shows bare
  hips under a faded tunic; a tunic's waist cap shows from above in first person; the creator's
  preview on the Web is drawn at the canvas's size; every style's mesh is resident (5.98 MB of mesh
  buffers against a 6.0 MB row); draw calls at `medium` reach 395 in the Valley walk and 674 in the
  stress arena because each shadow cascade draws the giant's 9-12 meshes again; the creator's first
  frame after New Game sits on the stall rule's line on the Web (2.65-3.5 times the median frame); a
  command-line `--continue` skips the title's warm-up.
- **What M10 left open in the tools** (VERIFIED, M10 record): the Web page's memory grows without
  bound when the browser is starved of CPU while a level loads (also on 0.9.0-m9; not isolated);
  `audio_check.mjs` presses Enter once and can lose it to the title's warm-up; `test_stream_check.mjs`
  fails about one run in three on this machine; `world_check.mjs` maps the audio clock with one
  straight line and fails on a clock step; two checkouts export different bytes for a freshly
  converted scene (random node ids); the normal bake jitters by one texel in some runs; `--verify`'s
  tolerance has never run on another toolchain.
- **The giant's code as it is** (VERIFIED, code): `SkinnedRig extends ActorRig`
  (`scripts/presentation/skinned_rig.gd`, 549 lines) builds an `AnimationPlayer`, an `AnimationTree`
  and a `PoseBrainModifier` (367 lines) at run time, only where something is drawn; the legs' source
  is chosen by the brain's state (dead, airborne, motion, walking, stance); the clips are nine
  computed-keyframe clips from `tools/giant/kit/clips.py` (idle, walk, run, airborne, death and four
  one-frame hand poses; no outside motion data); the skeleton is MPFB2's "game_engine" rig, 53 bones,
  30 of them fingers, no face, eye, hair or cloth bones; every hair and beard card is weighted to
  `head`. The skin shader (`assets/shaders/giant_skin.gdshader`) has its own `light()` with wrap
  lighting and a thickness term, reads the region id from `COLOR.r` and leaves `COLOR.g`, `.b` and
  `.a` unused. `GiantLook` (734 lines) builds one `ShaderMaterial` per mesh and instance.
- **The appearance record as it is** (VERIFIED, code): `character.appearance` with `"v": 1`; an
  outfit is one `outfit.<key>` naming a list of garments (six outfits over ten garments: braies, belt,
  tunic, jerkin, bracers, boots, furs, cape, leg_wraps, pauldron) with two dyes; four tattoo regions,
  one war paint, at most four scars in the record (the shader holds eight scar channels);
  `Appearance.migrate()` exists and does nothing yet; a record whose `v` is above the build's is kept
  untouched and the default look is drawn. Thirteen sets, 99 options, eight presets. The creator's
  rows are swatches, cyclers, sliders and toggles in nine categories (`ui/screens/creator/option_rows.gd`).
- **The CC0 data on hand** (VERIFIED, code: `tools/giant/mpfb2/`): 133 files, of which 122 morph
  targets. The macro targets are male only (young and old, three ethnic bases, muscle and weight,
  height, proportions); there are detail targets for the head, face parts, torso, arms, legs, hands
  and feet. **There is no female macro target and no animal in the vendored subset**, and MakeHuman
  has no quadruped at all: women need more CC0 targets audited from the same wheel
  (`tools/giant/fetch_mpfb2.py`), and horses and wolves cannot come from this data.
- **The NPCs as they are** (VERIFIED, code): every human, ogre, troll and giant NPC is a box rig on
  `ActorRig` (`scripts/presentation/actor_rig.gd`, the same pose brain as the player's), built by
  `tools/builders/{soldier,ranged,formations,siege,npcs,heavy,big}.gd` with one vertex-coloured mesh
  per pivot (a soldier: 6 meshes, so 6 draw calls on its full rig) and one material copied per actor
  by `RigPaint`; beyond 0.45 x `render_lod_m` at `low` it draws one merged rest-pose mesh, beyond
  `render_lod_m` one box. Wolves, dire wolves and the cavalry's horse are box rigs on `QuadrupedRig`
  (222 lines); the rider is boxes merged into the horse's body. A formation's rank and file is drawn
  by `CrowdRenderer` as one `MultiMesh` per pose (hold, brace, advance, flee) from each member scene's
  `Visual/CrowdPoses/<pose>` mesh, with at most 6 members promoted to their own rigs within 20 m x the
  giant's scale. 20 enemy records and 9 NPC records; nine named NPCs share `elder.tscn` or
  `villager.tscn`; `iron_guard` shares `shieldman.tscn`. Heights: people 1.7-2.0 m, the ogre 3.4 m,
  the troll whelp 3.5 m, the troll 5.5 m, the Ogre King 8.5 m, the Troll Matriarch 9 m, the rival
  giant 10 m, Harrok 15 m, the wolf 0.9 m, the dire wolf 1.8 m. The camera has no dialogue framing
  (`scripts/presentation/camera_rig.gd` names no dialogue), so an NPC is only ever seen from the
  giant's own cameras.
- **How large an NPC is on screen** (derived from the M10 record's 260 px for the 3.66 m giant at the
  stage-1 third-person camera, 1280x720): a 1.8 m person beside the giant is about 128 px tall at
  stage 1 and about 58 px beside a stage-6 giant; in first person at stage 1 a person 3 m from the eye
  is about 280 px tall, and a held one fills more. Faces are 10-40 px wide outside the hand.
- **Budgets measured on the M10 release** (VERIFIED, M10 record): draw calls at `low`, the Web's
  preset, at most 152 (the Valley walk), 153 (the stress arena) and 63 (the Web's world walk) against
  250; the giant alone 12; the skin's CPU 0.062-0.072 ms a frame natively and 0.09-0.14 ms on the Web;
  texture memory 4.90 MB of 9; the director keeps at most 12 active combatants; the creator check's
  page peaks at about 1.0-1.1 GB of renderer memory on a quiet machine; the test tiers ran 66.2 s
  (default, cap 75 s), 341.8 s (slow, cap 8 minutes) and 844.6 s (gate, cap 50 minutes) with 330
  suites and 56,119 checks; `check.sh --giant` 71 s and `--giant-full` 197-239 s.
- **How long M10 really took** (VERIFIED, git and the handoff): the owner's answers came on 12
  November, W25 and W26 merged on 14 November, W27, the gate, the approval and the release were on 18
  November: six calendar days for seven packages, against a plan of three. This plan's estimate uses
  that pace.
- **Engine behaviours M10 proved and this plan relies on** (VERIFIED, M10 record): alpha to coverage
  does nothing in the Compatibility renderer; a `sampler2DArray` works on desktop and WebGL 2; LODs
  generated by the importer are used for skinned meshes; nothing set on a node inside an instanced
  scene survives a SceneKit save; modifier results are only visible during `skeleton_updated`; a
  headless `ShaderMaterial` accepts a misspelled uniform silently; the first frame with new shader
  variants stalls 1.3-2.0 s on the Web's software renderer unless warmed up.
- **Engine behaviours this plan assumes and probes before W29** (ASSUMED; §1.2 lists each with its
  fallback): a mesh loaded from a second glTF binds to the model's skeleton by its named skin; a vertex
  shader may push a vertex along its normal by a weight stored in `COLOR.g` and `.b`, and the shadow
  pass follows; `SpringBoneSimulator3D` runs on leaf bone chains in this renderer and on the Web
  within the skin's CPU budget; the cause of the dark patch every exported morph showed between the
  brows; an `AnimationPlayer` seeked by hand can cross-fade two clips; a `MultiMesh` instance's custom
  data reaches a `ShaderMaterial` on the Web; a shell-layered fur shader is affordable at the sizes
  fur is drawn; the launcher can decode four parts without holding the whole text twice.

---

## 0. Scope, the owner's decisions, interpretations and the deferred list

### 0.1 Goal

Three things, in the order the owner chose.

**A. The giant refined.** The player's giant moves and looks better everywhere a player can see it.
Movement: the weapon held through the fist and the off hand alive in every pose; a stomp that lifts
the leg; a run and a sprint that read from the side; turning on the spot with steps; flinches when
hit; blends without pops; hair, beard, braids and a cape that hang and swing on bones; arms and
weapon composed for first person; a weapon carried past its fit stage that reaches as far as the body
honestly can. Graphics: hair that is more than flat cards (shaded as a volume, with strand
highlights, short hair and stubble as shells, braids as geometry, loose strands at the hairline), a
skin tone that matches the approved renders with a cheap subsurface term, eyes with depth and a
direction, scars and marks that read, cloth that reads as cloth, a sharp preview in the browser,
meshes loaded only when a look shows them, and shadows that cost one draw call a cascade.

**B. More customization.** Clothing by slot instead of whole outfits (head, shoulders, chest, armour,
arms, waist, legs, shins, feet, cape) with accessories, about 25 new garments and armour pieces, more
hair and beard styles with braids and beads, more tattoos, paints and scars, two build sliders and -
if a probe allows - six face sliders, jewellery, a metal palette and more dyes, more presets; the
look record at version 2 with a migration that never fails a load; a creator that stays usable with
about twice the options (pages, thumbnails, a filter).

**C. Realistic NPCs.** Everyone and everything on the same CC0 pipeline, in stages: people first
(soldiers, archers, mages, pikemen, shieldmen, bannermen, siege crews, riders and their horses,
villagers, elders and the named characters), then the rival giants and Harrok on the giant's own
body, then ogres, the Ogre King, trolls and the Troll Matriarch as morphs of the humanoid body, and
wolves and dire wolves as procedurally modelled quadrupeds. Variation by build, face, skin, hair,
clothing and armour per faction and role; formations of dozens inside the Web's draw-call and CPU
budgets; corpses, grabs and throws that still read; telegraphs and hit flashes as readable as today.

**What must not change**: anything that plays. The simulation, hit geometry, hurtboxes, capsules,
anchors, sockets, balance, the bots' results and the seeded soak stay exactly as 0.10.0-m10 left them
(§4.1, lens 2). Saves keep schema 2 and every older save loads. Every new asset is generated by
committed tools from audited CC0 inputs or from the project's own procedural code, and regenerates
bit-exactly on the reference toolchain. The whole page download stays under 60 MB.

### 0.2 The owner's words and choices

The request (verbatim):

> "Allow more customization clothing, outfits, designs, etc for your Giant, also improve the graphics and character models for all NPCS to make it look as good as the Giant, and also refine and improve the Giant movements and graphics as well"

Their answers on 18 November 2026:

1. **The browser download may grow to about 60 MB** for the whole page (it is about 36.5 MB now).
2. **NPC scope: everyone and everything** - soldiers, archers, mages, pikemen, shieldmen, bannermen,
   riders and their horses, siege crews, villagers, elders and named characters, plus wolves and dire
   wolves, ogres and the Ogre King, trolls and the Troll Matriarch, rival giants and Harrok. Done in
   stages, people first.
3. **Order**: the giant's movement and graphics first (the NPCs are then built on the improved body
   pipeline), then more customization, then NPCs (people, then rival giants, then beasts and trolls).

What they have not seen and will see before they are asked to approve anything (§4.2): the giant's
new motion in their own hands; slot clothing and the larger creator; a realistic soldier beside the
giant at the size the game camera shows it; a procedurally modelled wolf.

### 0.3 The gates and the packages that prove them

One table per part; each part's gate runs the eight lenses of §4.1 on what that part changed.

**Part A - the giant refined (release `0.11.0-m11`)**

| Requirement | Proven by |
| --- | --- |
| The weapon passes through the closed fist and the off hand does not droop in every generic pose (roar, stomp, self buff, first person at rest); the stomp lifts and plants a leg; a sprint clip distinct from the run; turning on the spot steps; a hit from each of four sides flinches; no pose pops between the legs' sources | P50 (the rig, its suites, the capture tour's side cameras); P48 (the clips); the gate's frame review |
| Hair, beard, braids and the cape hang and swing on bones, never pass through the shoulders at a full head turn, and come to rest | P48 (the bones, the weights, the cape), P50 (the secondary motion), the frame review |
| A weapon carried past its fit stage: the outer half within 1.0 capsule radius of the tested capsule and within 15 degrees at every stage, or the measured miss recorded as a limit of honest reach | P50 (`TipMatching`'s reach extension, `test_tip_matching`) |
| Hair beyond flat cards: volume shading and a two-lobe strand highlight on every style; the crop, stubble and the short beard as shells; braids as geometry; loose strands at the hairline; a beard that exists from behind | P51 (the kit, the shaders), P48 (weights); the rendered hair check against the approved close-up |
| The default skin's lit chest within 12/255 a channel of the approved render's under the creator's light; a subsurface term that softens the terminator; a swatch that shows the colour drawn | P51 (`test_skin_tone_render`) |
| Eyes with a cornea highlight, a limbal ring, a lid shadow and a look direction; every scar and mark above its view floor in the stage-1 rear or first-person view | P51, the option check |
| Meshes on demand: mesh buffers of the fullest look at most 4.5 MB; shadows one draw call a cascade; draw calls at `medium` no higher than 330 in the Valley walk and 620 in the stress arena (from 395 and 674) | P48 (the parts, the shadow proxy), P49 (the measurements) |
| The creator's preview on the Web at up to 1.5 window pixels a canvas pixel within the stall rule, or the measured reason why not; a command-line `--continue` warmed up | P49 |
| Nothing that plays changes; the tools' open rows closed or re-recorded with a reason | P49, P50; lens 2 |

**Part B - more customization (release `0.12.0-m12`)**

| Requirement | Proven by |
| --- | --- |
| Clothing by slot: ten garment slots and three accessory slots, each with "none"; 35 garments and armour pieces; no two shown garments intersect or z-fight in the idle, the walk and a heavy swing | P53 (the record, the look), P54 (the garments, the layering test), P57 (the rendered check) |
| The record at `v` 2; every `v` 1 record migrates to a look that shows exactly the garments, dyes and designs it showed before; a broken, unknown or future record never fails a load | P53 (the migration matrix over every preset and every option, the fixtures); lens 4's cross-version run |
| Two build sliders that change the silhouette in the stage-1 rear view and move no joint by more than 1 mm; face sliders if the probe passes, else one face with the reason recorded | P48 (the channels), P53 (the uniforms), P56 (the face keys), the option check |
| The target catalogue (§2.6) within the giant's share, with the cut list of §6.3 applied in order if it is not | P54, P56, `GIANT_SHARE` |
| The creator stays usable: every option reachable with a pad in at most 4 moves from its category, a filter for the keyboard, thumbnails for garments, hair and designs, the layout whole at 1280x720, Undo over every new row | P55; lens 5 |
| The giant at most 24 draw calls at `low` in the fullest slot look, a typical preset at most 14 | P54, P57 |

**Part C - realistic NPCs (release `0.13.0-m13`)**

| Requirement | Proven by |
| --- | --- |
| Every human enemy and NPC is a skinned, textured body from the people pipeline, driven by the unchanged pose brain; at least two body variants per role (three for soldiers, five for villagers), skin and hair varied, clothing and armour by faction and role; named characters recognisable | P59 (the pipeline), P60, P62 (the scenes and the variation data); the people sheet |
| A formation of 40 in view at `low`: at most 250 draw calls with the giant, at most 16 people skinned at once, the people's CPU at most 2.5 ms a frame on the Web | P60 (the crowd, the caps), P64 (the Web bench, `people_check.mjs`) |
| Riders are people on horses; rival giants and Harrok are the giant's body with their own looks; ogres and trolls are morphs of the humanoid body; wolves and dire wolves are modelled quadrupeds | P61, P62, P63, P64 |
| Corpses stay and cost no skinned slot after two seconds; a grabbed soldier hangs limp in the fist and tumbles when thrown; every telegraphed wind-up differs from idle by its view floor at the game camera; hit flashes and status tints reach every surface, crowd instances included | P60, P64; `test_people_readability` |
| Nothing that plays changes: the soak and the bots byte-identical to 0.10.0-m10 with people skinned or not, with positive controls | P60 (`test_people_determinism`); lens 2 |
| The download at most 60 MB: the pack at most 44 MiB, the people's share at most 12.0 MiB | P59, P64, `build_web.sh` |
| Every people and creature asset regenerates bit-exactly from audited CC0 data or the project's own code | P59, P61, P63 (`--people`, `--people-full`) |

### 0.4 Interpretations and decisions (the ship packages copy these into `DECISIONS.md`)

1. **Three parts in the owner's order, each a release.** The parts depend on each other in one
   direction only (B uses A's pipeline, C uses both), and each is a complete improvement by itself.
   Shipping each when it passes its own gate gets the owner's eyes on real builds three times, keeps
   each gate to the size M10's had, and puts the save migration in players' hands before the largest
   part starts. §4.4 gives the single-release alternative.
2. **The download budget becomes a pack budget of 44 MiB** at the last release, staged 26, 32, 44
   (§2.12 has the arithmetic): the owner's 60 MB less the 12.93 MB that is not the pack leaves 44.89
   MiB; 44 leaves 0.93 MB for the engine and launcher to grow. The plan fills about 40 of it and
   keeps the rest as reserve; filling the budget is not a goal.
3. **Gameplay geometry stays the stylized bodies'.** Capsules, hurtboxes, anchors, grab points,
   weapon pivots, arm lengths and reach bands of every actor stay as the data has them; the realistic
   bodies are presentation, as the player's became in M10. Where a real body cannot reach the tested
   sweep, tip matching applies to NPCs as it does to the player.
4. **The pose brain stays the driver of every actor.** `ActorRig` and `QuadrupedRig` keep computing
   every pose on the frame clock; skinned bodies follow them. No gameplay script reads a skeleton, a
   clip, a model or a look (the code rules of M10 are extended to the new class names).
5. **Clips stay computed keyframes.** No outside motion data: there is no audited CC0 motion set in
   the pipeline, and adding one is a provenance project of its own. The cost is stated in §0.5: the
   motion will be cleaner and richer than M10's, not motion-captured.
6. **The body is unfrozen once, in W29, and frozen again.** P48 adds leaf bones for hair, beard,
   braids and the cape (the 53 body bones keep their names and rest poses), two build weights in the
   body's vertex colour, grip and side landmarks, and exports the styles and garments as separate
   parts. The body's positions, UVs, region ids and bone weights stay bit-identical to M10's (a tool
   test compares them), so no bake input changes and M10's clips still play.
7. **Shape changes: yes for the build, by shader; for the face, by shape key, only if the probe
   passes.** M10 forbade shape changes because a dense shape key costs 0.34 MiB and every exported
   morph showed a dark patch. A build slider as a shape key would have to be repeated on every
   garment (about 1.3 MiB a slider once every garment carries it; ASSUMED from the vertex counts). Instead the pipeline projects the MakeHuman muscle and
   weight targets onto each vertex's normal and stores the two signed weights in `COLOR.g` and `.b`;
   garments, being shells cut from the body, inherit them; the vertex shader pushes the surface out.
   That costs no pack space and no CPU, follows every LOD, and touches no normal map. It moves no
   joint, so landmarks, tip matching and the clips hold. The face is different: face targets move
   vertices sideways and the hair and beard must follow, so the face gets six true shape keys on
   `Body_Head` and the beards (about 0.7 MiB, derived) if the pre-W29 probe finds and removes the
   dark patch; if not, one face stays and the reason is recorded. **Height is never a choice** (it is
   the growth stage).
8. **Hair stays polygons, and becomes more than flat cards**: card normals bent to the head's shape
   so a style shades as one volume; a two-lobe strand highlight along the card's direction; shells
   (stacked offset layers with a strand mask) for the crop, stubble, the short beard, fur trim and
   animal coats; braids as twisted tube geometry with beads; thin loose-strand strips at the
   hairline; hair bones for sway. Strand hair and alpha-to-coverage edges are out of reach (§0.5).
9. **Skin gets a pre-integrated subsurface term**: a 64 px lookup of light wrap by curvature and
   N.L, read in the existing `light()`, with curvature baked into the mask map's spare capacity. No
   screen-space scattering exists in this renderer.
10. **Clothing is by slot, with an over-layer for armour.** Ten garment slots - head, shoulders,
    chest, armour (over the chest), arms, waist, legs, shins, feet, cape - and three accessory slots
    (neck, arm ring, belt). The owner listed nine; "armour" and "shins" are added so that every M10
    outfit maps to slots without losing a garment (§2.5). Each garment is a shell at its slot's
    offset from the skin, so garments of different slots stack without intersecting by construction.
11. **The record goes to `v` 2 and schema 2 is kept.** `Appearance.migrate()` gets its first step. A
    0.10 or 0.11 build that opens a `v` 2 record keeps it untouched and draws the default look, as
    M10 built it to; the release notes say that a look made in 0.12 shows only in 0.12 or later.
12. **NPCs are one mesh and one material each.** A person is built with clothes, armour and hair
    already merged, hidden skin removed, one atlas per role: 1 draw call for the body where the box
    rig costs 6, plus the weapon and a shield. Variation comes from mesh variants per role, a palette
    in the shader (skin, hair, cloth and faction colours by a mask), a visual height of 0.96-1.04 and
    the seed of the actor's entity id - never from `Sim.rng`.
13. **People are skinned only near the giant.** At most 16 people skinned at once; the rest of a
    formation draws as `MultiMesh` instances of realistic meshes baked in each crowd pose, and beyond
    `render_lod_m` as a low far mesh, also instanced. A model is instanced when its actor is
    promoted and pooled afterwards, so headless tests and far actors pay nothing.
14. **Human NPCs get a 23-bone skeleton**: the game_engine rig without its 30 finger bones (fingers
    weighted to the hands, the hands baked half closed). The same bone names as the giant's, so the
    clip generator, the modifier and tip matching serve both.
15. **Rival giants and Harrok reuse the giant's model** at their heights with looks of their own in
    data, on `SkinnedRig` made independent of the player. They cost no new body.
16. **Ogres and trolls are morphs of the humanoid body** with the project's own sculpt functions on
    top of the CC0 targets (a heavier jaw, a lower brow, longer arms, a hunch), re-baked skins, and
    the 23-bone skeleton. The Ogre King and the Troll Matriarch are their kind's body with gear.
17. **Wolves, dire wolves and horses are modelled by the project's own Blender scripts**, because
    MakeHuman has no quadruped (VERIFIED). This is the plan's weakest point and is said so: a
    scripted quadruped will be anatomically plausible and well shaded (a fur shell coat hides much),
    not sculpted. They ship last, behind a look gate of their own, and the cut list keeps the box
    wolves if they do not pass (§6.3).
18. **One asset writer per wave.** The generated trees (`assets/giant/`, `assets/people/`,
    `assets/creatures/`) and their manifests have one writing package per wave and one writing lane
    during a gate, as in M10.
19. **Headless stays cheap.** Skinned layers run only where something is drawn (a display, `--skin`,
    or a test that asks); the default tier and the bots never instance a person's model.
20. **The owner sees each part in their hands before it ships** (§4.2), and the look of each part is
    theirs to approve.
21. **Test tiers as in M10**, with `--require` and `--strict-times` at every merge and each part
    ending no higher in the default tier than 72 s on a quiet machine (§1.7).

### 0.5 Out of scope, and what is honestly out of reach in this engine configuration

Out of reach with the Compatibility renderer, WebGL 2, a single thread and computed keyframes:

- **Strand hair.** No hair strands, no order-independent transparency, no alpha to coverage, no
  temporal antialiasing to hide stochastic alpha. Hair is polygons with a depth pre-pass; M11 makes it
  shade as a volume and breaks its outline, and a close-up at the Face framing will still show that
  it is not strands.
- **Real subsurface scattering, screen-space reflections, ambient occlusion in screen space, contact
  shadows.** The skin's softness is a lookup; the eyes' reflection is a painted highlight.
- **Cloth and hair simulation.** The cape and the hair swing on a few spring bones; they do not
  collide with the body beyond angle limits and will pass through a raised arm or a carried tree.
- **Motion capture quality.** Every clip is computed. Weight shift, anticipation and overlap are
  written as curves, which reads as clean but mechanical next to captured motion.
- **Facial animation.** No face bones. At most a blink and the face sliders as shape keys; no speech,
  no expressions in dialogue.
- **Two-handed grips through a swing**: reachable in only 4-21 % of swing samples (M10 record); the
  off hand joins a two-handed weapon at rest only.
- **A sculpted look for the beasts** (decision 17).
- **Real GPUs and real browsers**: every frame time here is a software renderer's; the owner's
  machines decide (§4.5).

Deferred, each with its reason: world materials, textured terrain, buildings and props (the next
step after people: the realistic bodies will then stand in a low-poly world); realistic weapon meshes
for the player (the owner kept the low-poly weapons in M10; NPC gear is made by the people pipeline,
and a material pass on the player's weapons is cut-list item 2 of Part A if they ask); gameplay
pivots matched to the real skeletons (a balance change); per-stage proportions and a growth tween (a
tween is on Part A's cut list); a free colour picker (palettes stay); a name for the giant; female
giants (the body, its bakes and every garment would double; a later milestone if the owner wants it);
foot placement on slopes for NPCs (the player's is on Part A's cut list).

### 0.6 Questions for the owner, with the defaults the plan proceeds on

Sent before W29 with the note of §4.2. No answer blocks W29.

| # | Question | Default (the plan proceeds on it) | What a different answer changes |
| --- | --- | --- | --- |
| 1 | Three releases, one per part (0.11, 0.12, 0.13), or one release when everything is done? | Three | One: the checkpoints stay as private previews, P52 and P58 shrink to a docs pass, one gate of M8's size at the end, the budget rule is 44 MiB for `-m11` (§4.4) |
| 2 | The download rises in steps - about 40 MB at 0.11, 46.5 MB at 0.12, at most 59.1 MB at 0.13. Is 59.1 MB for the last acceptable as "about 60"? | Yes | A lower cap: the people's variants and atlases are cut first (§6.3) |
| 3 | Build sliders (brawn, girth) and, if the engine allows it cleanly, six face sliders? Height stays the growth stage | Yes to both | No sliders: P53 and P56 drop them (about 6 agent-hours back) |
| 4 | Clothing by slot adds two slots to your list: "armour" over the chest and "shins". Agreed? | Yes | Nine slots only: the jerkin joins "chest", leg wraps join "feet", and two M10 outfits lose a garment on migration |
| 5 | Wolves, dire wolves and horses will be modelled by our own scripts (no free animal body exists in our data). If they do not look good enough beside the people, keep the current box animals for 0.13 and try again later? | Yes, keep the boxes rather than ship a poor wolf | "Ship them anyway", or "use an outside CC0 animal model": the second needs an audited source and adds about a wave |
| 6 | Women among villagers and named characters (Edda, Reeve Tamsin, the ferrywoman) need more CC0 body data from the same source as the giant's. Agreed? | Yes | No: every person is built from the male body, with clothes and hair doing the work |
| 7 | Approve each part's look (the preview and its sheet, §4.2) | - | Notes steer the part's look pass; "not yet" opens one fix lane |

**Answered.** The owner confirmed all the defaults above on 18 November 2026 ("GO"): three releases; 59.1 MB
for the last download; build and face sliders; the two added slots; boxes kept rather than a poor wolf; women
among the people from more CC0 body data. Question 7 is asked at each part's checkpoint.

---

## 1. Execution model and wave schedule

### 1.1 Definition of done for every package

As M10 §1.1, unchanged in its six points: every Godot command through `tools/gd.sh`; heavy processes
under `nice -n 19`, Cycles at 2 threads; `tools/check.sh` with the options the package's changes call
for, `--require` on every final check; shipped data validates; generated files change only through
their tools and manifests; the test budget of §1.7; `docs/systems/<package-id>.md`; commits on
`pkg/<id>` that name the package; no AI product or model names and no absolute scratch-folder paths
in any file. Additions for M11:

1. **Asset packages** add `--giant` (and `--giant-full` when a bake input changed) for
   `assets/giant/`, and from P59 `--people` (the people pipeline's tests, then `build_people.py
   --verify --skip-bake`) and `--people-full` when a people bake input changed.
2. **Every package that changes what is drawn** saves its frames under `user://m11_frames/<id>/` and
   lists in its system doc the frames a reviewer should look at.
3. **Only the ship packages (P52, P58, P66) edit `README.md`, `ARCHITECTURE.md` and `DECISIONS.md`.**
   `PERFORMANCE.md`, `USABILITY_SCRIPT.md`, `CREDITS.md` and `FOLLOWUPS.md` are edited by the packages
   §1.5 names.
4. A package is about 1,200-3,500 new lines including tests and data; each design list is in
   priority order, and a package that passes its size or its time range splits at a numbered item
   and records it.

### 1.2 Branches, worktrees, the wave merge, generated assets, and the probes before W29

Branches, worktrees and the wave merge are M10 §1.2's: each package on `pkg/<id>` in its own worktree
from the integration tip at the start of its wave; merge the first, check; merge the second, import,
full build, import, `check.sh --slow --giant --require --strict-times` (`--people` from W34, `--gate`
at the last wave of each part), the 120 s soak; "Merge wave N", tag `wave-N`. Fix forward only under
about 50 lines.

**Generated outputs.** Three trees, each with its own manifest and its own verifier: `assets/giant/`
(`tools/giant/build_giant.py`), `assets/people/` and `assets/creatures/`
(`tools/giant/build_people.py`, from P59). Exactly one package a wave writes generated assets
(§1.5); during a gate exactly one lane does.

**Before W29** (the orchestrator, about 4 hours). Commit this plan; send the owner the note of §4.2
with the questions of §0.6; then run these probes in a scratch project on the reference toolchain and
record each result in §7 of this plan. Each decides one design point and none blocks W29: where a
probe fails, the package takes the fallback named here.

| # | Probe | Decides | Fallback if it fails |
| --- | --- | --- | --- |
| 1 | A hair mesh exported to its own glTF, loaded at run time and bound to `giant.glb`'s skeleton by named skin; LODs and shadow meshes present | Meshes on demand (P48) | Keep one `giant.glb`; free the unshown meshes' nodes after `_ready` and measure what the server really releases; the 4.5 MB row becomes "measured" |
| 2 | A vertex shader pushing vertices along the normal by `COLOR.g`, `.b` on the body and a garment; the shadow pass; the LODs | Build sliders (decision 7) | Two build shape keys on the body and a reduced garment list (about 2.7 MiB), or no build sliders |
| 3 | A morph exported with and without normals and tangents, imported with and without `ensure_tangents`, to find the dark patch between the brows | Face sliders (decision 7) | One face; P56's item drops |
| 4 | `SpringBoneSimulator3D` on three leaf chains under `head` and four under `spine_03`: the look, the cost natively and in a Web test export | Secondary motion (P50) | The project's own damped-pendulum modifier (about 150 lines), or the shader sway of M10 for the hair and bones for the cape only |
| 5 | A 64 px lookup sampled in `light()` in the Compatibility renderer on desktop GL and WebGL 2 | The subsurface term (P51) | An analytic wrap by curvature without a texture |
| 6 | Twelve shell layers on a 4,400-triangle scalp cap and on a 4,000-triangle animal body: frame cost at 640x360 natively and on the Web | Shells for short hair and fur (P51, P63) | Six layers; or shells on the desktop tier only with cards on the Web |
| 7 | One `AnimationPlayer` per actor seeked by hand with a cross-fade between two clips; its cost for 16 actors of 23 bones natively and on the Web | The people's clip driver (P60) | An `AnimationTree` per promoted actor with the cap lowered to what 2.5 ms buys |
| 8 | A `MultiMesh` with per-instance colour and custom data read by a `ShaderMaterial` (palette row, flash) on the Web | Crowd variation and crowd hit flashes (P60) | One `MultiMesh` per palette row and pose; flashes only on promoted members |
| 9 | The launcher unpacking a 44 MiB pack in four parts: peak memory with the parts decoded one at a time against joined text | The launcher's change (P49) | Keep the join and record the peak; lower the last budget if the peak passes 1.4 GB |
| 10 | A 5,000-triangle clothed person and a 23-bone skeleton in a Web test export: bytes shipped per variant and per 512 px atlas | The people's share (§2.12) | Fewer variants per role, in §6.3's order |

### 1.3 Wave schedule (two lanes; "assets" marks the wave's one asset writer)

| Wave | Lane A | Lane B | Leaves working |
| --- | --- | --- | --- |
| W29 | **P48** The body pipeline II (assets): leaf bones, build weights, landmarks, parts on demand, the shadow proxy, the free cape, the clips II | **P49** Web, tools and performance debts; the M11 pre-declarations | The game plays as 0.10 with the new clips and bones present and unused; meshes load on demand; shadows cost one draw call a cascade; the tools' open rows are closed; the budget rule knows m11-m13 |
| W30 | **P50** The giant's motion | **P51** The giant's look pass II (assets, shaders): hair, skin, eyes, cloth | **Part A plays.** Gate A, then **the owner's checkpoint A** |
| W31 | **P52** Ship `0.11.0-m11` | **P53** The look record v2: slots, sliders, migration, `GiantLook` by slot | 0.11 released after the owner's approval. Every v1 look migrates; the ten M10 garments are worn by slot |
| W32 | **P54** The wardrobe (assets, data): garments and armour by slot, accessories | **P55** The creator II: pages, thumbnails, the filter, slot rows, sliders | Slot clothing with the target garments in a creator that holds them |
| W33 | **P56** The catalogue II (assets, data): hair, beards, braids and beads, designs, face keys, presets | **P57** Web and performance for the wardrobe; the option check and the sheets | **Part B plays.** Gate B, then **checkpoint B** |
| W34 | **P58** Ship `0.12.0-m12` | **P59** The people pipeline (assets): the human generator, roles, atlases, LODs, crowd poses, clips | 0.12 released. `build_people.py --verify` regenerates every person; a soldier's model loads |
| W35 | **P60** `PersonRig`, the crowd and the soldiers | **P61** Mounts and the giants' gear (assets, data) | Soldiers, archers, mages, pikemen, shieldmen, bannermen and siege crews are realistic in play and in formations; the horse and the rival giants' looks exist |
| W36 | **P62** Townsfolk, named characters, riders and the rival giants | **P63** Brutes and wolves (assets) | Every person and both giants are realistic in play. **Checkpoint C1** (a preview and the people sheet; not blocking) |
| W37 | **P64** Brutes and beasts in the game; the Web tiers and performance for people | **P65** The people look pass (assets, data): the owner's notes, variation, the beasts' look gate | **Part C plays.** Gate C, then **checkpoint C** |
| W38 | **P66** Ship `0.13.0-m13` | - | 0.13 released after the owner's approval |

**Why this order.** The owner's order fixes the parts. Inside a part, the lane that writes assets and
the lane that writes code meet through the contracts of §2, as P41 and P42 did. Part A regenerates
the body once at its very start (P48) so that everything after it - the motion, the look, the
wardrobe, the people - builds on the final skeleton and vertex data. A ship package runs beside the
next part's first package (W31, W34): the release is cut from the gate's code and waits only for the
owner, and the next part does not wait for it. In Part C the assets always land one wave before the
code that puts them in scenes, so no code package builds on stand-ins: people (P59, W34) before the
rig (P60, W35); the horse and the giants' gear (P61, W35) before riders and rival giants (P62, W36);
brutes and wolves (P63, W36) before their scenes (P64, W37). The beasts are last so that their
quality risk cannot delay people.

### 1.4 Dependencies

| Package | Depends on (merged earlier) |
| --- | --- |
| P48, P49 | 0.10.0-m10; the probes of §1.2 (their results, not their success) |
| P50 | P48 (bones, clips, landmarks, parts), P49 (the pre-declarations) |
| P51 | P48 (parts, weights), P49 (the budget rule) |
| P52 | P50, P51, Gate A; the owner's approval (for the tag, the play link and the merge) |
| P53 | P48 (the build weights, the index's `slot` field for M10's garments), Gate A's code |
| P54, P55 | P53 |
| P56 | P54 (the index v2, the shells' offsets); P57: P54, P55 |
| P58 | P56, P57, Gate B; the owner's approval |
| P59 | P48 (the kit, the clip generator, the 53-bone names), P51 (the hair and cloth code), Gate B's code |
| P60 | P59; P61: P59 (the kit's people modules), P54 (garment shells for giants' gear) |
| P62 | P60 (the rig, the model, the look), P61 (the horse, the giants' looks); P63: P59, P61 (the quadruped kit) |
| P64 | P62, P63; P65: P62, P63, the owner's notes on checkpoint C1 |
| P66 | P64, P65, Gate C; the owner's approval |

### 1.5 Hotspot policy

M10's three mechanisms stay: registries that are pre-declared and skip missing files, package
anchors, and a single owner per wave for every other shared file. **P49 lands every pre-declaration
of Part A, P53 of Part B, P59 of Part C** (each with a `test_predeclared_m1x.gd`), so later packages
only add files.

| File or tree | Owner by wave |
| --- | --- |
| `tools/giant/kit/**`, `tools/giant/build_giant.py`, `assets/giant/**` | W29 P48; W30 P51; W32 P54; W33 P56; W35 P61 (the giants' gear); gate lanes one at a time |
| `tools/giant/build_people.py`, `tools/giant/kit/people*.py`, `assets/people/**` | W34 P59; W37 P65 |
| `tools/giant/kit/quadruped.py`, `assets/creatures/**` | W35 P61 (the horse); W36 P63; W37 P65 |
| `scripts/presentation/giant_model.gd` | W29 P48; W31 P53 |
| `scripts/presentation/{skinned_rig,pose_brain_modifier,tip_matching}.gd` | W30 P50; W36 P62 (the rig made independent of the player) |
| `scripts/presentation/giant_look.gd`, `assets/shaders/giant_*.gdshader` | W30 P51; W31 P53; W32 P54 (cloth kinds only); W33 P56 |
| `scripts/presentation/{actor_rig,rig_paint}.gd` | W29 P49 (the shadow proxy path); W35 P60 |
| `scripts/presentation/{crowd_renderer,telegraph_visuals,hit_feedback}.gd`, `scripts/actors/enemy_actor.gd` (presentation hooks only) | W30 P50 (`hit_feedback.gd`: the flinch's direction); W35 P60; W37 P64 |
| `scripts/presentation/person_{model,look,rig}.gd` | W35 P60; W37 P64. `skinned_quadruped_rig.gd`: W36 P62; W37 P64 |
| `scripts/presentation/quadruped_rig.gd` | W36 P62 (the horse); W37 P64 |
| `scripts/presentation/camera_rig.gd` | W30 P50 (first person) |
| `scripts/progression/appearance.gd`, `scripts/actors/player/player_appearance.gd`, `scripts/core/schemas/appearance_*`, `scripts/progression/character_state.gd`, `scripts/core/save_slots.gd` | W31 P53 |
| `data/appearance/**` | W31 P53; W32 P54; W33 P56; W35 P61 (`npc_look_*.json`) |
| `data/enemies/*.json`, `data/npcs/*.json` (presentation keys only: `scene`, `render_lod_m`, the new `body`) | W35 P60; W36 P62; W37 P64 |
| `ui/screens/creator/**`, `ui/screens/shrine/appearance_tab.gd` | W29 P49 (`giant_preview.gd`: the pixel scale); W30 P51 (`option_rows.gd`: the swatch's colour); W31 P53 (the smallest change that keeps the creator working on slots); W32 P55; W33 P57 (fixes found by the checks) |
| `tools/builders/{soldier,ranged,formations,siege}.gd` | W35 P60; `npcs.gd`, `siege.gd` (cavalry), `big.gd` (giants) W36 P62; `heavy.gd`, `big.gd` (trolls, dire wolf), `wolf.gd` W37 P64 |
| `tools/build_scenes.gd`, `tools/check.sh` | W29 P49; W34 P59 (`--people`) |
| `tools/build_web.sh`, `tools/pck_files.py`, `export_presets.cfg`, `web/launcher.html`, `tools/web/**` | W29 P49 (the `PEOPLE_SHARE` line included, so that P59 need not touch them); W31 P52; W33 P57; W34 P58; W37 P64; W38 P66 |
| `tools/character_sheet.tscn` and its script, `scripts/debug/capture_m10.gd` (extended, and a new `capture_m11.gd`) | W30 P50 (the tour); W33 P57 (the wardrobe sheet); W37 P64 (the people sheet) |
| `scripts/core/events.gd`, `scripts/core/game_data.gd`, `scripts/core/data_validator.gd`, `tests/support/{reset_hooks,anchors_expected}.gd` | W29 P49; W31 P53; W34 P59 - at anchors afterwards |
| `project.godot` | the ship packages |
| `docs/PERFORMANCE.md` | W29 P49; W30 P50; W33 P57; W35 P60; W37 P64; the ship packages |
| `docs/USABILITY_SCRIPT.md` | W32 P55; W37 P64 |
| `CREDITS.md`, `assets/*/PROVENANCE.md` | the wave's asset writer; the ship packages |
| `docs/plans/FOLLOWUPS.md` | any package, its own section (append only) |

### 1.6 Shared edits inside a wave

The two packages of a wave share no file except `docs/plans/FOLLOWUPS.md`. The crossings that need
care: in W29, P48 owns `giant_model.gd` (the loader of parts) and P49 owns `rig_paint.gd` and
`actor_rig.gd` (the shadow path), and P49 reaches P48's shadow proxy mesh defensively (present or
not; the merge runs the test that needs it). In W30, P50 owns the rig and P51 the look; P51's hair
bones are already in the skeleton, so neither waits. In W32, P54 owns the data and the cloth shader's
kinds, P55 the screens; P55 builds its rows from the sets, so new options appear without an edit.

### 1.7 Test tiers and budgets

The default tier is still the scarce one: 66.2 s of 75 on a quiet machine, with a fifth of noise
between two runs on a busy one (VERIFIED, M10 record).

1. **Caps per package** (default / slow / gate): asset packages 0.3 s / 5 s / 0; P49 0.4 s / 10 s /
   0; P50 0.6 s / 30 s / 4 min; P53 0.8 s / 15 s / 0; P55 0.8 s / 20 s / 0; P57 0.1 s / 10 s / 4 min;
   P60 0.8 s / 30 s / 6 min; P62 0.6 s / 20 s / 2 min; P64 0.4 s / 10 s / 5 min; ship packages 0.
   With the every-script compile check that is at most +2.5 s (A), +3.0 s (B) and +3.6 s (C) on the
   default tier, and +55 s (A), +55 s (B) and +75 s (C) on the slow tier.
2. **Headroom first, three times.** P49, P53 and P59 each move at least as many seconds of the
   heaviest default suites to `tests/slow/` as their part adds (per-suite times from the runner),
   choosing long simulations whose checks other default suites repeat, so each part ends no higher
   than 72 s on a quiet machine.
3. **The slow tier needs room too**: 341.8 s of 480 before M11, and the caps add 185 s. The same
   three packages move slow suites whose ground a gate-tier walkthrough repeats into the gate tier
   (which has 36 minutes of room), so that the slow tier ends no higher than 400 s (A), 430 s (B)
   and 460 s (C); rendered option grids and stage renders go to the gate tier from the start (P57,
   P64).
4. **Per-suite accounting, `--strict-times`, rendered checks under `xvfb-run` at 320x240** as M10
   §1.7 rules 2, 5 and 6.
5. **People cost headless tests nothing by construction** (decision 19): a suite that needs a
   skinned person calls `PersonRig.enable_for_tests()`; `ResetHooks` resets it.

---

## 2. Shared contracts

SI units; data records as in every milestone (`schema_version: 1`, a dotted `id`, a `type`, one record
a file, at most two folder levels under `data/`). Signatures are GDScript 4.6. Everything named in
this section that does not exist at `5ff50f0` is new and is created by the package named as its
owner; nothing here is an engine API unless it is named as one.

### 2.1 Folders and owners

| Folder or file | New or changed contents (owner) |
| --- | --- |
| `tools/giant/kit/` | Changed: `giant_body.py`, `export_game.py`, `split.py` (leaf bones, build weights, landmarks, parts), `giant_garment.py` (the free cape; then slots and shell offsets, P54), `clips.py` (the clips II) (P48); `giant_hair.py`, `giant_skin.py`, `bake.py`, `pack.py`, `skin_textures.py` (P51); `designs.py` (P56). New: `people_body.py`, `people_outfit.py`, `people_roles.py`, `people_bake.py` (P59); `quadruped.py` (P61); `brute.py` (P63) |
| `tools/giant/` | `build_people.py` (the people and creature pipeline; steps `--humans --horse --brutes --wolves --clips --all --verify --skip-bake --budget`), `test_people_tools.py` (P59); more audited CC0 targets under `mpfb2/targets/` with `FILES.sha256` and `SOURCE.md` updated (P59, if the owner agrees to question 6) |
| `assets/giant/` | `giant.glb` (the three body meshes, the eyes, the shadow proxy, on the 71-bone skeleton); `parts/<mesh id>.glb` (one hair, beard, garment or accessory mesh each); `giant_clips.glb` (28 clips); `tex/skin_lut.png`; the maps, atlases and design layers regenerated (P48, P51, P54, P56, P61) |
| `assets/people/` | `<role>.glb` (the role's body variants, its crowd-pose meshes and its far mesh), `<role>_albedo.png`, `<role>_normal.png`, `<role>_orm.png`, `people_clips.glb`, `gear.glb` (weapons, shields, the banner), `manifest.json`, `PROVENANCE.md` (P59; P65) |
| `assets/creatures/` | `horse.glb`, `ogre.glb`, `troll.glb`, `wolf.glb`, their maps, `creature_clips.glb`, `manifest.json`, `PROVENANCE.md` (P61 the horse; P63; P65) |
| `assets/shaders/` | The four `giant_*` shaders changed (P51, P53, P54, P56); `giant_shell.gdshader` (P51); `person.gdshader`, `person_crowd.gdshader` (P60); `fur_shell.gdshader` (P64, from `giant_shell`) |
| `scripts/presentation/` | `secondary_motion.gd` (`SecondaryMotion`, P50); `person_model.gd` (`PersonModel`), `person_look.gd` (`PersonLook`), `person_rig.gd` (`PersonRig extends ActorRig`) (P60); `skinned_quadruped_rig.gd` (`SkinnedQuadrupedRig extends QuadrupedRig`, P62) |
| `scripts/core/schemas/` | `person_role_schema.gd` (P59 declares the path, P60 writes it); `enemy_schema.gd` and `npc_schema.gd` gain the optional `body` key, `appearance_preset_schema.gd` the optional `npc` flag (P60, P61) |
| `data/appearance/` | `set_garment.json`, `set_accessory.json`, `set_bead.json`, `set_metal.json`, `set_build.json`, `set_face.json` and the changed sets and presets (P53, P54, P56); `preset_npc_*.json` (the giants' looks, P61) |
| `data/people/` | `role_<key>.json` (type `person_role`: the model, the variants, the palettes by faction) (P60, P62) |
| `scenes/people/`, `scenes/creatures/` | `<role>_model.tscn`, `<kind>_model.tscn` from the new builder `tools/builders/people_models.gd` (P60; P62, P64 add kinds) |
| `ui/screens/creator/` | `option_grid.gd` (pages of thumbnails), `thumbnail_cache.gd` (P55) |
| `tools/web/` | `people_check.mjs`, `test_people_check.mjs` (P64) |
| `scripts/debug/` | `capture_m11.gd` (the tours of the three parts, P50; extended by P57 and P64) |
| `tests/fixtures/saves/` | `v2_appearance_v2.json`, `v2_appearance_v2_unknown_slot.json`, `v2_appearance_v2_broken.json`, `v2_appearance_v3_future.json`, and M10's four `v2_appearance*.json` kept as the v1 inputs (P53) |
| `docs/screenshots/m11/`, `m12/`, `m13/` | each part's sheet and release shots (the ship packages) |

### 2.2 The body II: bones, vertex data, landmarks and parts (P48)

**What stays bit-identical to M10** (a tool test compares against the M10 manifest's body hash
inputs): the positions, normals, UVs and region ids (`COLOR.r`) of `Body_Head`, `Body_Torso` and
`Body_Limbs`; the 53 game_engine bones' names, parents and rest poses; each body vertex's four
weights. So the bakes' inputs are unchanged and M10's nine clips play as they did.

**Leaf bones** (18, so the skeleton has 71): under `head`, `hair_01`-`hair_03` (the back of the
hair, a tail or a single braid), `hair_l_01`-`hair_l_02` and `hair_r_01`-`hair_r_02` (side locks and
twin braids), `beard_01`-`beard_02`; under `spine_03`, three chains of three for the cape:
`cape_c_01`-`03`, `cape_l_01`-`03`, `cape_r_01`-`03`. No body vertex is weighted to them. Hair and
beard cards are re-weighted along their root-to-tip coordinate (the root stays on `head`), the cape
becomes a free-hanging mesh weighted to its chains (it was a shell on the back).

**Vertex colour**: `COLOR.r` the region id as before; `COLOR.g` the brawn weight and `COLOR.b` the
girth weight, each the MakeHuman muscle or weight target's displacement projected on the vertex
normal, normalized by the largest such displacement and stored as `0.5 + 0.5 x w`; `COLOR.a` is left
at 1 and reserved. Garments, hair roots and beard roots inherit the weights of the body vertex they
were grown from. The largest displacement at stage 1 is written to the index as `build_max_m`.

**Landmarks added to the index**: `grip_r`, `grip_l` (the centre of the closed fist), `grip_axis_r`,
`grip_axis_l` (the handle's direction through it, unit vectors in the hand bone's space), `knuckle_r`,
`knuckle_l`, `toe_l`, `toe_r`; and per design a `side` ("left", "right" or "centre").

**Parts.** `giant.glb` keeps the skeleton, the three body meshes, `Eyes` and a new `ShadowProxy` (the
body at about 2,500 triangles, weighted like the body, drawn only in shadow passes). Every hair,
beard, garment and accessory mesh is exported to `assets/giant/parts/<mesh id>.glb` on the same
skeleton. The index's `meshes[<id>]` gains `"part": "res://assets/giant/parts/<id>.glb"` (absent for
the meshes inside `giant.glb`) and, for garments, `"slot"` and `"shell"` (§2.6).

```gdscript
# scripts/presentation/giant_model.gd (P48 adds)
func ensure_part(id: String) -> MeshInstance3D   # loads and binds the part the first time; null if unknown
func release_unused(shown: Array) -> void          # frees the parts no shown look needs (never the body)
func shadow_proxy() -> MeshInstance3D
```

`GiantLook.apply` calls `ensure_part` for what a look shows and `release_unused` afterwards; the
creator's preview keeps the parts of the open category resident. A part is a shared resource: two
giants showing the same hair load it once. With the shadow proxy present, every other mesh of the
model casts no shadow and the proxy is shadows only (`GeometryInstance3D.cast_shadow`); a shown cape
keeps its own shadow.

### 2.3 Motion: the clips II, the legs' sources, the hands, secondary motion, reach and first person

**The clips** (`tools/giant/kit/clips.py` writes `assets/giant/giant_clips.glb`; all computed, P48).
M10's nine stay. Added: `sprint` (a longer stride and forward lean than `run`, the arms pumping);
`turn_l`, `turn_r` (a 90-degree turn in two steps); `stomp_r` (lift, hold, plant; seeked by the
action's phase fraction); `land` (the knees take the landing); `brace` (the block's stance);
`roar` (the legs set wide, the chest out); `flinch_f`, `flinch_b`, `flinch_l`, `flinch_r` (upper
body, 0.3 s, additive); one-frame grips per family `grip_club`, `grip_sword`, `grip_hammer`,
`grip_axe`, `grip_fist`, `grip_tree`; `carry_two_hand` (the off hand on a two-handed weapon at rest);
`fp_rest` (the arms' rest for first person). 28 clips. The hand clips are exported with the fingers'
tracks only (M10's follow-up). The manifest records each gait's stride and foot slide as M10 did.

**The legs' sources** in `SkinnedRig._drive_tree`, first match wins (new ones in bold): dead;
airborne; **landing** (0.25 s after the floor returns: `land`); **stomp** (an action whose hit shape
is `cylinder_pulse` without morale damage: `stomp_r` seeked by the phase fraction); motion (an
action that moves the giant: `run`, or **`sprint`** above 0.8 of the sprint speed); walking (idle,
walk, run and **sprint** blended by normalized speed on the brain's walk phase); **turning** (the
actor's yaw rate above 60 degrees a second while the brain does not walk: `turn_l` or `turn_r` on a
clock of the yaw travelled); **bracing** (blocking and standing: `brace`); stance. Every change of
source cross-fades over 0.12-0.2 s by the rig's existing easing; a table in P50's system doc lists
each pair's time. Footfall audio stays on the brain; the turn and stomp clips add no footfall event
(the simulation's audio is unchanged; the stomp's sound is the ability's).

**Hit reactions**: the rig's `flash()` already fires on every hit taken. P50 adds an additive
`flinch_*` chosen from the hit's direction in the actor's frame when the hit feedback passes one
(`HitFeedback` reads it from the hit event it already receives), weight by the flash strength, never
during an attack's active window. Presentation only: nothing reads it back.

**The hands.** `WeaponSocket` moves from the knuckle line to the `grip_r` landmark with the weapon's
handle along `grip_axis_r`, in every pose, and the fingers take the family's grip clip; in a tested
swing tip matching still decides the hand's place and aim. The open off hand takes `open_l` blended
with a relaxed curl instead of the bind pose. Acceptance is measured: over the capture tour's
generic poses the handle's axis passes within 0.02 x k m of the fist's centre.

**Reach for a weapon past its fit stage** (`TipMatching`, P50): when the natural grip cannot bring
the outer half into the tested capsule, the solver may protract the clavicle by up to 0.08 x k m,
lean the spine toward the tip by up to 12 degrees and shift the pelvis by up to 0.10 x k m, in that
order, and stops at the first that suffices. M10 measured the capsule starting up to 0.28 x k beyond
the hand's reach; the three together give about 0.41 x k (derived; ASSUMED to read as a lunge, which
the frame review judges). The contract for weapons that fit is unchanged.

**Secondary motion** (`SecondaryMotion`, P50): one object per model that sets up the engine's
`SpringBoneSimulator3D` (a `SkeletonModifier3D`) on the leaf chains a look uses - none when the look
shows no long hair, long beard, braid or cape - with stiffness, drag and gravity per chain from the
index, and angle limits that keep hair off the shoulders and the cape off the legs. It runs on the
frame clock after `PoseBrainModifier`, never headless, and resets on teleports, growth and the
creator's view changes. M10's shader sway stays for cards' tips. If probe 4 fails: the fallback of
§1.2.

**First person** (P50, with `camera_rig.gd`): at rest the arms take `fp_rest`, which brings the
weapon into the lower right of the view; a block raises the forearm into view; the tunic's skirt
part gets a first-person fade like the shoulders' (`giant_first_person.gdshaderinc`) so its waist cap
never shows from above. The camera's geometry does not change.

**Optional, on Part A's cut list**: the head turning toward the lock target (at most 40 degrees, the
neck and head bones); foot placement on slopes for the player (two ray queries a frame from the
frame clock, the pelvis lowered, the ankles pitched); a growth tween.

### 2.4 The giant's shaders II (P51; later owners in §1.5)

Every shader keeps `tint` and `flash`. `GiantLook.validate()` still compares every name it sets with
`get_shader_uniform_list()`.

| Shader | Added or changed uniforms | Meaning |
| --- | --- | --- |
| `giant_skin` | `skin_lut` (sampler2D, 64 px), `curvature_scale`, `sss_strength`; `light_model` gains 3 (pre-integrated); `swatch_gain` is not a uniform: `GiantLook.drawn_tone(option)` returns the colour the creator's swatch shows | The subsurface term: the lookup is read by (N.L, curvature); curvature comes from the mask map's spare range (P51 packs it beside the lips mask) |
| `giant_skin`, `giant_cloth` | `build` (vec2: brawn, girth, each -1 to 1), `build_max_m` | The vertex push of decision 7 (P53 sets them; P48's meshes carry the weights) |
| `giant_hair` | `volume_normal` (0-1: the card's normal blended toward the head-centred normal baked in the mesh), `spec_primary`, `spec_secondary`, `spec_shift_2`, `strand_noise`; `back_fade` no longer hides a beard from behind | Shading as a volume; two highlights along the strand direction, one shifted toward the root and tinted |
| `giant_shell` (new) | `shell_count`, `shell_height_m`, `strand_tex`, `hair_color`, `tip_color`, `grey`, `density` | Short hair, stubble, the short beard and fur trim as stacked layers: the layer index rides in the mesh (the kit duplicates the cap `shell_count` times with the index in UV2), so a style is still one draw call |
| `giant_eye` | `look` (vec2: the iris offset, at most 0.25 of its radius), `cornea_spec`, `limbal`, `lid_shadow` | A highlight, a darker ring, a shadow under the upper lid, a direction (`SkinnedRig` writes `look` toward the lock target or the camera in the creator) |
| `giant_cloth` | `kind` gains metal (a detail map `cloth_metal.png`, a metallic response); `rim` (a soft edge light for wool and fur); the detail maps at 256 px | Cloth that reads as cloth; armour that reads as metal |

Braids are geometry (`giant_hair.py` writes twisted tubes with a baked normal detail and bead
rings), drawn by `giant_hair` with `volume_normal` 0. Loose strands at the hairline are a third,
sparse layer of thin strips on the long styles.

### 2.5 The appearance record v2 and its migration (P53)

```json
"appearance": {
  "v": 2,
  "preset": "appearance_preset.wanderer",
  "skin": "skin.ruddy", "eyes": "eyes.grey_green",
  "build": {"brawn": 0.0, "girth": 0.0},
  "face": {"jaw": 0.0, "chin": 0.0, "nose": 0.0, "brow": 0.0, "cheeks": 0.0, "age": 0.0},
  "hair": {"style": "hair.long_back", "color": "haircolor.chestnut", "grey": 0.12, "beads": "bead.none"},
  "beard": {"style": "beard.full", "color": "", "grey": 0.2, "beads": "bead.none"},
  "tattoos": {"arms": "", "chest": "", "back": "", "face": "", "legs": "", "ink": "ink.woad"},
  "paint": {"face": "", "body": "", "color": "paintcolor.chalk"},
  "scars": [],
  "mark": "auto",
  "outfit": {
    "set": "outfit.wanderer",
    "slots": {"head": {"item": "", "dye": ""}, "shoulders": {"item": "", "dye": ""},
              "chest": {"item": "", "dye": ""}, "armour": {"item": "", "dye": ""},
              "arms": {"item": "", "dye": ""}, "waist": {"item": "garment.belt", "dye": ""},
              "legs": {"item": "garment.braies", "dye": ""}, "shins": {"item": "", "dye": ""},
              "feet": {"item": "", "dye": ""}, "cape": {"item": "", "dye": ""}},
    "accessories": {"neck": "", "arm_ring": "", "belt": ""},
    "dyes": {"cloth": "dye.undyed", "leather": "dye.dark_leather", "metal": "metal.iron"}
  }
}
```

| Key (new or changed against v1) | Allowed values | `Appearance.sanitize` |
| --- | --- | --- |
| `v` | 2 | above 2: the record is kept untouched and the default look drawn, with M10's note; 1: migrated first |
| `build.brawn`, `build.girth` | -1 to 1 | clamped; not a number becomes 0 |
| `face.*` | -1 to 1; the key is ignored by a build without face keys | clamped; unknown sub-keys kept |
| `hair.beads`, `beard.beads` | `bead.<key>`; shown only on styles whose index entry has bead anchors | unknown becomes `bead.none`, reported |
| `tattoos.legs` | a `tattoo.<key>` whose region is `legs`, or "" | as the other regions |
| `paint.face`, `paint.body` | a `paint.<key>` of that region, or "" | unknown or wrong region becomes "", reported |
| `scars` | unique `scar.<key>`, at most 6 | as v1, truncated to 6 |
| `outfit.slots.<slot>.item` | a `garment.<key>` whose `slot` is that slot, or "" | unknown or wrong slot becomes "", reported; a missing slot becomes empty |
| `outfit.slots.<slot>.dye` | a `dye.<key>` or `metal.<key>` that fits the garment's material, or "" for the outfit's dye of that material | unknown becomes "" |
| `outfit.accessories.<slot>` | an `accessory.<key>` of that slot, or "" | unknown becomes "", reported |
| `outfit.dyes.cloth`, `.leather`, `.metal` | `dye.<key>`, `dye.<key>`, `metal.<key>` | the set's default |
| `outfit.set` | `outfit.<key>` or "" (a summary only: "" once the slots differ from the set) | unknown becomes "" |

**The migration** - `Appearance.migrate(record)`, pure, one step, run by `sanitize` before anything
else when `v` is 1 (or missing):

| v1 | v2 |
| --- | --- |
| `outfit.set` naming an outfit of `set_outfit.json` | each of the outfit's garments goes to the slot `set_garment.json` gives it; the M10 mapping is fixed here: braies - legs; belt - waist; tunic - chest; jerkin - armour; bracers - arms; boots - feet; furs - shoulders; pauldron - shoulders; cape - cape; leg_wraps - shins. No M10 outfit names two garments of one slot (VERIFIED against `set_outfit.json`: wanderer, hunter, warrior, chieftain, raider, wayfarer), so nothing is lost; `outfit.set` is kept |
| `outfit.set` unknown | the default outfit's slots, reported as v1 reported it |
| `outfit.primary`, `outfit.secondary` | `dyes.cloth`, `dyes.leather`; `dyes.metal` the default |
| `tattoos.*`, `mark`, `skin`, `eyes`, `hair`, `beard`, `preset` | copied; `tattoos.legs` "", beads `bead.none` |
| `paint.design` | `paint.face` or `paint.body` by the design's region; the other "" |
| `scars` | copied |
| (absent) | `build` and `face` zeros |
| any other key | kept |

Rules, each a test:
- **A migrated record draws what it drew**: for every M10 preset and for a record built from every
  v1 option in turn, `to_look(migrate(r))` shows the same meshes, designs and colours as M10's
  `to_look(r)` (the M10 function is kept in the test as the oracle), new keys aside.
- **Never a failed load**: every M10 fixture, the 26 broken shapes of the M10 gate and their v2
  equivalents load; a broken `slots` block alone becomes the default outfit with a note and leaves the
  rest of the look.
- **Absent stays absent**: a character without a look still captures no key, so every older save,
  fixture and bot run is byte for byte what it was. A v1 record is written back as v2 only when the
  player keeps a look in the creator or the game writes the next checkpoint of a save whose look was
  migrated in memory (the load message says once: "Your giant's clothing is now worn piece by piece;
  nothing was changed.").
- **Older builds**: 0.10 and 0.11 keep a v2 record untouched and draw the default look (M10's rule,
  VERIFIED, code). The gate's lens 4 runs it with the real binaries.
- `SaveSlots.SCHEMA_VERSION` stays 2.

**The look dictionary** (`Appearance.to_look` to `GiantLook.apply`) gains `build` (Vector2), `face`
(Dictionary of floats), `hair_beads`, `beard_beads` (mesh ids or ""), `accessories` (mesh ids),
`garments` as an Array of `{"mesh": id, "dye": Color, "kind": String}` in place of the id list with
two dyes, `paint` as an Array of at most two, and `eye_look` is not part of it (the rig writes it).
`GiantLook.DEFAULT_LOOK` is restated in the new shape by P53 with the Wanderer's values unchanged.

### 2.6 Slots, the index v2 and the target catalogue (P54, P56)

**Slots and shells.** A garment is a shell cut from the body at its slot's offset from the skin, so
two garments of different slots never share a surface:

| Slot | Shell offset at stage 1 (m) | Covers (design regions hidden) | M10 garments | Target adds (P54) |
| --- | --- | --- | --- | --- |
| legs | 0.012 | - | braies | trousers, kilt, loincloth |
| chest | 0.014 | chest, back (by coverage) | tunic | shirt, sleeveless vest, chest wrap |
| shins | 0.020 | - | leg_wraps | greaves |
| feet | 0.024 | - | boots | wrapped sandals |
| arms | 0.022 | arms (by coverage) | bracers | iron vambraces, arm wraps |
| waist | 0.030 | - | belt | plated war belt, sash |
| armour | 0.034 | chest, back | jerkin | mail hauberk, scale coat, leather cuirass, bronze breastplate |
| shoulders | 0.046 | - | furs, pauldron | fur mantle, iron pauldrons, bone spaulders |
| head | 0.020 | face (the full helm only) | - | hood, leather cap, iron helm, horned helm |
| cape | free mesh | back | cape | long cloak, fur cloak |
| neck, arm_ring, belt (accessories) | rigid, on one bone | - | - | three torcs and amulets, three arm rings, two belt trophies |

25 new garments and 8 accessories on top of M10's 10: 35 garments. A head garment declares which
hair styles it hides or cuts (`hides_hair`: "all", "top" or "none"); hair then draws with the
`length` uniform or not at all. P54's tool test measures, for every pair of slots whose regions
overlap, the smallest distance between the two shells over the rest pose and three clip poses
(idle, a walk frame, a raised arm) and fails under 0.004 x k m; its rendered check looks for
z-fighting in the fullest look.

**The index v2**: `meshes[<id>]` gains `part`, `slot`, `shell`, `material` ("cloth", "leather",
"fur", "metal"), `hides_hair`, `bead_anchors` (hair and beards) and `chains` (the leaf chains the
mesh is weighted to); `designs[<id>]` gains `side`; `landmarks` the entries of §2.2; `build_max_m`.

**The target catalogue** (floor: what P53 ships on M10's content; target: after P54 and P56):

| Set | 0.10 | Target | Notes |
| --- | --- | --- | --- |
| garments (`set_garment.json`) | 10 (inside outfits) | 35 in ten slots | the table above |
| outfits (now starting points) | 6 | 12 | each a full set of slots |
| accessories, beads | - | 8, 3 | beads on the braided styles and the braided beards |
| hair | 7 | 12 | top knot, side-shaved with braids, twin braids, long loose, a circlet braid |
| beards | 7 | 11 | chin braid with beads, long forked, mutton chops, a braided moustache |
| tattoos | 16 in four regions | 28 in five | four for the legs, eight more elsewhere |
| war paint | 4 | 8, on face and body at once | |
| scars | 6, four worn | 10, six worn | |
| dyes; metals | 8; - | 14; 5 (iron, steel, bronze, blackened, gilded) | |
| skin, eyes, hair colours, inks, paint colours, marks | 10, 10, 10, 6, 6, 3 | unchanged | the owner's notes may add |
| build; face | - | 2 sliders; 6 sliders (probe 3) | |
| presets | 8 | 14 | the eight revised to slots, six new |

About 190 options against 99. Every design keeps M10's rule (strokes of at least 4 cm at stage 1,
one option per category above the rear or first-person floor). The cut order is §6.3's.

### 2.7 The creator II (P55)

The screen keeps its three doors, its results, Undo, Randomize, Reset, the discard question, Game
view and "Hidden by your clothing" (M10 §2.10). What changes:

- **Categories** (LB and RB, PageUp and PageDown): Presets, Body (skin, build), Face (eyes, face
  sliders), Hair, Beard, Tattoos, War paint, Scars, Clothing, Accessories, Colours (the three dyes
  and per-slot overrides).
- **Clothing** is ten slot rows; a slot row opens its **option grid**: a page of up to 12 thumbnails
  (4 x 3 at 1280x720) with the option's name under the focus, "None" first, LT and RT or the wheel
  for pages, a material filter (All, Cloth, Leather, Fur, Metal) on X or F, and on the keyboard a
  type-to-filter box that matches names. Hair, beard, tattoo and paint cyclers become grids the same
  way. Any option is at most 4 moves from its category for a pad: the slot row, the page, the cell.
- **Outfits** is a row of starting points that fills every slot at once (undoable); "Outfit: custom"
  once a slot differs.
- **Thumbnails** (`ThumbnailCache`): rendered at run time by a second, hidden `GiantPreview` with
  `UPDATE_ONCE` into 96 x 96 textures, one a frame, only for the visible page, cached by option id,
  skin tone and dyes for the screen's life; designs use a flat picture of their own layer and
  channel instead of a render. Nothing is shipped for them. On the Web the first page of a grid
  shows names until its thumbnails arrive; if P57 measures a thumbnail above the stall rule there,
  garment grids on the Web show names with the live preview only.
- **Sliders** step by 0.1 with the pad and snap to 0; the build sliders show the stage-1 rear Game
  view while they have the focus.
- **The shrine's tab** summarises by slot ("Chest: tunic, madder; Armour: mail hauberk, blackened").
- Framing by `side`: a design on the giant's left is framed from his left (M10's follow-up).

### 2.8 The people pipeline (P59; the horse P61; brutes and wolves P63)

**One generator, the giant's kit.** `people_body.py` builds a human from the same CC0 base mesh and
targets as the giant (`mh_data.py`, `giant_body.py`'s morph code), at 1.8 m, on the game_engine rig
reduced to **23 bones** (`Root`, `pelvis`, `spine_01`-`03`, `neck_01`, `head`, and per side
`clavicle`, `upperarm`, `lowerarm`, `hand`, `thigh`, `calf`, `foot`, `ball`; the fingers' weights
folded into the hands, the hands posed half closed). `people_outfit.py` dresses it with the giant's
garment shells and hair code plus role gear, removes skin no garment shows, merges body, clothes,
armour and hair into **one mesh with one UV atlas**, and decimates to the role's budget.
`people_bake.py` bakes one atlas per role (Cycles, seed 0, 2 threads): albedo at 512 px, normal at
256 px, and one 256 px map holding AO, roughness and the palette mask.

**Roles** (`people_roles.py`; each one `assets/people/<role>.glb`):

| Role | Body variants | Used by |
| --- | --- | --- |
| soldier | 3 | `enemy.soldier`; with gear `pikeman`, `shieldman`, `bannerman`, `iron_guard` (a heavier helm and tabard as a fourth variant) |
| archer | 2 | `enemy.archer` |
| mage | 2 | `enemy.mage` |
| crew | 2 | `enemy.siege_crew` |
| rider | 2 | `enemy.cavalry` (seated pose; the horse is a creature) |
| villager | 5 (three men, two women if question 6 is yes) | `npc.villager`, `npc.deserter`, `npc.ferrywoman` |
| elder | 2 | `npc.elder`, `npc.sedge` |
| notable | 5 (Edda, Reeve Tamsin, the herald, the toll captain, Corvane) | the named characters; Corvane at 2.0 m with his own gear |

23 variants of at most 5,000 triangles each with the importer's LODs; per role also **five crowd-pose
meshes** (hold, brace, advance, flee, and `corpse`) of at most 600 triangles baked from the role's
first variant in the clip's pose, and a **far mesh** of at most 150 triangles. A variant differs in
build (the macro targets), face (the detail targets), hair or headgear and small gear; the palette
(skin, hair, cloth, faction colour) is not a variant.

**Palette mask**: the 256 px map's B channel holds four bands (skin, hair, cloth, faction cloth);
`person.gdshader` multiplies the albedo by the band's colour, so one atlas serves every tone and
every faction.

**Clips** (`people_clips.glb`, from `clips.py` with human proportions and the 0.9 m stride of the
soldier's rig): idle, walk, run, flee, brace, cower (civilians), seated (riders), held (limp in a
fist), tumble (thrown), death, and one-frame grips. Brutes reuse the generator with their own
proportions (P63).

**The quadruped kit** (`quadruped.py`, P61; decision 17): a parametric four-legged body built in
Blender from the project's own code - cross-section rings lofted along a spine curve, limbs as
tapered tubes with joint bulges, a head from two lofts and a jaw, ears, a tail - subdivided once,
smoothed, UV-unwrapped by the script, on a 25-bone skeleton (`Root`, `pelvis`, `spine_01`-`02`,
`neck`, `head`, `jaw`, `tail_01`-`02`, and per leg three bones and a foot). Parameters for the horse
(P61), then the wolf and the dire wolf (P63: one mesh, two sizes and two palettes). A procedural
coat: albedo from noise fields along the body's coordinates, and a fur shell (probe 6). Its quality
risk is stated in §5 and its gate is §4.2's checkpoint C1 for the horse and the people look pass for
the wolves.

**Brutes** (`brute.py`, P63): the human body with the CC0 muscle and weight macros at their maximum,
then the project's own vertex functions on named regions - a heavier jaw and brow, a shorter neck, a
hunched upper spine, arms lengthened to the box rigs' proportions (the troll "long-armed"), thicker
hands and feet - at about 9,000 triangles, a skin of its own baked at 512 px (the ogre's hide, the
troll's mossy skin), on the 23-bone skeleton. The Ogre King and the Troll Matriarch are the same
meshes with gear (a crown and a mantle; a bone crown and a hide mantle) at their heights.

**Manifests, verification and provenance**: as the giant's. `build_people.py --verify` regenerates
into a temporary folder and compares with `assets/people/manifest.json` and
`assets/creatures/manifest.json` (bit-exact on the reference toolchain, M10's tolerance for Cycles
maps elsewhere); `--skip-bake` re-bakes the cheap passes and reads AO back from the committed maps;
`check.sh --people` runs the tools' tests and `--verify --skip-bake`, `--people-full` every bake
(budget: 6 and 45 minutes). `PROVENANCE.md` states for each file whether it derives from the CC0
MakeHuman data or wholly from the project's code.

### 2.9 People in the game: `PersonModel`, `PersonLook`, `PersonRig` and the crowd (P60)

```gdscript
class_name PersonRig extends ActorRig          # scripts/presentation/person_rig.gd
const MAX_SKINNED := 16                        # people skinned at once, over all formations and loners
static func enable_for_tests() -> void         # as SkinnedRig's; ResetHooks resets it
static func layers_enabled() -> bool           # the same switch as SkinnedRig.layers_enabled()
static func run_stats() -> Dictionary          # the PEOPLE_STATS line: skinned frames, promotions, variants drawn, crowd instances
func body_spec() -> Dictionary                 # role, variant, palette, height scale: from the record's "body" and the entity id
func skinned() -> bool                         # this actor holds one of the skinned slots now
func visible_weapon_segment() -> Array         # [grip, tip], valid inside `posed`, as SkinnedRig's
signal posed
```

- **The record's `body` key** (optional, in `data/enemies/*.json` and `data/npcs/*.json`):
  `{"role": "person_role.soldier", "variant": "" | "<name>", "palette": {...}, "gear": [...]}`.
  Absent means the scene's own default. A named character names its variant; everyone else gets
  `hash(entity_id) % variants` and a palette row from the role's table for the actor's faction. The
  hash is of the id string: no random stream is read (decision 12).
- **The scene** keeps every gameplay node and the brain's pivots without meshes (as the giant's did
  in M10), `Visual/CrowdPoses/<pose>` and `Visual/LodProxy` now holding the realistic pose and far
  meshes, and `Visual` scripted with `PersonRig`. Node paths that tests name stay where they can; the
  suites that assert box meshes are rewritten by P60 and listed in its system doc.
- **Three levels**, chosen every frame from the distance to the giant, the actor's state and the
  cap: **skinned** (a pooled `PersonModel` under `Visual/Body`, one `AnimationPlayer` seeked from the
  brain's state and walk phase with a 0.15 s cross-fade, and a light modifier that turns the spine
  and places the arms from the brain's arm poses by the same two-bone solve as the giant's; in a
  weapon arc, tip matching); **crowd** (an instance of the role's pose mesh in a `MultiMesh`, as
  `CrowdRenderer` does today, with the palette row and a flash value in the instance's custom data);
  **far** (an instance of the far mesh). Skinned first for the held, the thrown, the staggered, the
  striking and the falling, then by distance, within `MAX_SKINNED`; loners outside formations use
  the same three levels through one shared renderer per level instead of `RigPaint`'s proxies.
- **Corpses**: a death plays skinned (the death clip under the brain's fall); two seconds after the
  fall ends the body becomes a `corpse` crowd instance and frees its slot.
- **Grab and throw**: a held person is always skinned and plays `held` (limp, hanging from the
  grip's anchor), the giant's rig still moving the held `Visual` to its palm as in M10; a thrown one
  plays `tumble` until the projectile system lands it, then the death.
- **Readability**: `person.gdshader` and `person_crowd.gdshader` declare `tint` and `flash`;
  telegraph rings and fans are untouched; a wind-up must change at least 1.5 % of the actor's own
  screen box against its idle at the stage-1 game camera, which `test_people_readability` measures
  for every telegraphed attack of every role.
- **Draw calls**: a skinned person is 1 (the body) + 1 (weapon) + 1 (a shield or a banner) and one
  shadow draw a cascade (the body only); a crowd of any size is one call per role, pose and level.

### 2.10 Giants, riders, brutes and beasts in the game (P62, P64)

- **Rival giants and Harrok** (P62): what in `SkinnedRig` still assumes the player (where the held
  body and the look come from) is put behind the actor's own rig state, the two scenes get
  `Visual/Body/Model` like the player's at k = 10 / 3.6576 and 15 / 3.6576, and their looks come from
  `data/appearance/preset_npc_rival_giant.json` and `preset_npc_harrok.json` (the `npc` flag keeps
  them out of the creator), named by a new optional `appearance` key in their enemy records. Their
  axes stay weapon visuals with a material pass. Tip matching runs on their weapon data and is
  measured as the player's is.
- **Riders** (P62): the cavalry scene's `Visual` becomes a `SkinnedQuadrupedRig` (the horse: the
  `QuadrupedRig` brain driving the 25-bone skeleton - the trot's diagonal pairs to the legs' three
  bones by a two-bone solve, the head, jaw and tail from the brain's pivots) carrying a rider model
  in the `seated` clip on the saddle bone, the lance in the hand. One actor, three draw calls.
- **Brutes** (P64): the ogre, the troll, the whelp, the Ogre King and the Troll Matriarch on
  `PersonRig`'s skinned level only (they are never a crowd), with their own models; the bosses are
  always skinned.
- **Wolves and dire wolves** (P64): `SkinnedQuadrupedRig` with the wolf model, the fur shell, the
  lunge and the jaw snap from the brain; packs beyond the skinned cap draw a far mesh.
- **Caps**: at most 16 people and at most 8 others (giants, brutes, mounts, wolves) skinned at once.

### 2.11 Events, registries, command line and flags

| Kind | Name | Owner |
| --- | --- | --- |
| Registries | `DataValidator.SCHEMA_PATHS` gains `person_role`; `build_scenes.gd BUILDERS` gains `people_models.gd` (before `soldier.gd`); `ResetHooks.AFTER_EACH` gains `PersonRig.reset_for_tests` and `SecondaryMotion.reset_for_tests` | P49 (A's), P53 (B's), P59 (C's), each tested by its `test_predeclared_m1x.gd` |
| Command line | `--skin`, `--no-skin`, `--skin-stats` now also switch and report people (`PEOPLE_STATS`); `--people-cap=N` (tests and benches); `--scenario=capture_m11` with `--part=a`, `b` or `c` | P50, P60 |
| Command line | `--giant-tier=` unchanged; `--people-far` (forces the far level: the fallback view for the sheets) | P60 |
| `tools/check.sh` | `--people`, `--people-full` | P59 |
| `tools/build_web.sh` | the budget by milestone (m11 26, m12 32, m13 on 44); `PEOPLE_SHARE` beside `GIANT_SHARE` (0 until the files exist; its cap applies from m13); parts as needed | P49 |
| Signal | none new: no gameplay event is added | - |
| Flags | `appearance.slots_seen` (the one-time message of §2.5) | P53 |
| Code rules | the M10 rules' word lists gain `PersonRig`, `PersonModel`, `PersonLook`, `SecondaryMotion`, `SkinnedQuadrupedRig`, `body_spec` | P50, P60 |

### 2.12 Budgets

**The download and the pack** (derived from the 0.10.0-m10 release's bytes):

| | Bytes | MiB |
| --- | --- | --- |
| The owner's ceiling for the whole page ("about 60 MB") | 60,000,000 | |
| Everything that is not the pack (36,520,414 - 23,586,472) | 12,933,942 | |
| The most the pack may ship | 47,066,058 | 44.89 |
| **The pack budget at the last release** | 46,137,344 | **44** |
| The page's download at that budget | 59,071,286 (59.07 MB) | |
| Left for the engine, the loader and the launcher to grow | 928,714 | |

| Release | Pack budget (MiB) | Planned pack (MiB) | Parts of at most 15,000,000 bytes | Page download at the budget |
| --- | --- | --- | --- | --- |
| 0.10.0-m10 (today) | 26 | 22.49 | 2 | 36.5 MB (measured) |
| 0.11.0-m11 | 26 | about 24.0 | 2 | at most 40.2 MB |
| 0.12.0-m12 | 32 | about 29.0 | 3 | at most 46.5 MB |
| 0.13.0-m13 | 44 | about 40.2 | 3 planned, 4 at the budget | at most 59.1 MB |

**Shares** (`build_web.sh` fails over any of them; the rule "the giant's cap is the budget less
18.4" already gives the first two rows):

| Share | 0.11 | 0.12 | 0.13 | Planned at 0.13 |
| --- | --- | --- | --- | --- |
| Everything else (code, data, scenes, audio, the world): 16.92 today | 18.4 | 18.4 | 18.4 | about 17.5 |
| `GIANT_SHARE` (`assets/giant/`, the giant's shaders and scenes): 5.57 today | 7.6 | 13.6 | 13.6 | about 12.5 |
| `PEOPLE_SHARE` (`assets/people/`, `assets/creatures/`, their shaders and scenes) | - | - | 12.0 | about 10.2 |
| Total | 26 | 32 | 44 | about 40.2 |

The arithmetic behind the plans (MiB shipped; every line ASSUMED from the rates in the facts above
until P48's and P59's test exports measure them):

- **Part A, +1.5**: 19 more clips with finger-only hand clips 0.25; the hairline strips, the shells
  and braid geometry 0.45; curvature in the mask maps 0.15; cloth detail maps at 256 px and the metal
  map 0.20; the shadow proxy, the free cape, the parts' overhead 0.10; the lookup 0.01; margin 0.34.
- **Part B, +5.0**: 25 garments at about 2,300 triangles (57,500 triangles) 1.9; five hair and four
  beard styles at about 4,200 triangles 1.25; six face keys on the head and beards 0.7; six more
  design layers 0.15; accessories and beads 0.1; hair atlas tiles 0.3; data, screens and scripts
  0.1; margin 0.5.
- **Part C, +10.6** (10.2 the people's share, 0.4 the giants' gear in the giant's share): 23 people
  variants at 5,000 triangles (115,000) 3.8; crowd-pose and far meshes for 8 roles 0.6; 8 role
  atlases and 4 spare at about 0.2 each (albedo 512 px 89 KB, normal 256 px about 82 KB, the third
  map about 34 KB) 2.4; people clips 0.2; the horse 0.4; two brute meshes at 9,000 triangles, their
  gear and two full 512 px skins 1.9; the wolf with its coat 0.4; creature clips 0.1; margin 0.4.

**Everything else**:

| Budget | Value | Checked by |
| --- | --- | --- |
| Draw calls in every measured view at `low` | at most 250 (unchanged; 152-153 today) | P49, P57, P64 (the Valley walk, the stress arena, the world viewpoints, the formation stress) |
| The giant's draw calls at `low` | a typical preset at most 14; the fullest slot look at most 24 (three body meshes, eyes, hair, beard, two bead sets, up to twelve garment meshes, three accessories); shadows one a cascade | P54, P57 |
| Draw calls at `medium` | the Valley walk at most 330, the stress arena at most 620 (395 and 674 today; 250 has never been met at `medium`, where the static world alone draws up to 221, and is not M11's goal) | P49 |
| A person's draw calls | skinned: at most 3 and one shadow draw a cascade; a crowd: one per role, pose and level | P60 |
| Skinned at once | 16 people and 8 others | P60, P64 |
| The giant's CPU a frame with secondary motion | native at most 0.12 ms, Web at most 0.45 ms (0.07 and 0.09-0.14 today) | P50, P57 |
| The people's CPU a frame, 16 skinned and a crowd of 40 | native at most 0.6 ms, Web at most 2.5 ms | P60, P64 |
| The simulation | p95 at most 8 ms a tick, unchanged; no presentation code in `Sim` | lens 2 |
| The giant's primitives | at most 70,000 at 4 m in the fullest slot look; at most 4,000 beyond 120 m | P54, P57 |
| A formation of 40 at 30 m, primitives | at most 95,000 (16 x 5,000 skinned at LOD 0 at worst, 24 x 600 crowd) | P64 |
| Texture memory | the giant at most 9 MB (4.90 today; twelve design layers and the larger atlases about 8); people and creatures in any view at most 10 MB | P57, P64 |
| Mesh buffers | the giant's resident meshes at most 4.5 MB in play (5.98 with all resident today); people and creatures at most 10 MB | P49, P64 |
| The Web page's peak renderer memory, quiet machine | at most 1.4 GB in `creator_check.mjs` and `people_check.mjs` (about 1.0-1.1 today) | P49, P57, P64 |
| Shader stalls | each first frame at most 3 times the median after the warm-ups: the title, the creator, a level, a shrine's creator, the first formation in view, the first wolf | P49, P57, P64 |
| Test tiers | default at most 72 s at each part's end; slow at most 400, 430, 460 s; gate under 50 minutes | every merge |
| Regeneration | `--giant` at most 6 min, `--giant-full` 25; `--people` 6, `--people-full` 45 | P48, P59 |
| Repository growth | at most 12 MB (A), 15 MB (B), 30 MB (C, of which more vendored CC0 targets at most 4 MB) | the asset packages |

### 2.13 Test conventions

M10 §2.13 stands. Added:

- Skinned people are off headless; suites that need them call `PersonRig.enable_for_tests()`, and
  `test_skin_rules` asserts the switch is off at the start of every test.
- Every look check compares against a frame, not a feeling: `test_skin_tone_render` (the chest
  patch against the approved render's values), the hair check (the outline's roughness and the
  share of scalp pixels at the Face and Hair framings against M10's frames), the option check's
  floors, `test_people_readability`, the variation check (two soldiers with different ids differ by
  at least 3 % of their screen box).
- The migration oracle: M10's `to_look` is copied into the test folder as it was at `5ff50f0` and
  never edited.
- Determinism baselines are produced from the tag `0.10.0-m10` in a scratch worktree by the gate,
  not stored.
- The capture tour (`--scenario=capture_m11`) has side, front and three-quarter cameras for every
  motion beat; its frames are the gates' animation evidence.

---

## 3. Package specifications

Each package lists its wave and lane, dependencies, goal, owned paths (exclusive within its wave),
hotspot edits (as the single owner of §1.5 or at its anchors), design in priority order, tests, its
test-time caps (default / slow / gate, §1.7), acceptance and size. Every package also writes
`docs/systems/<id>.md` and passes §1.1. "Cross-lane symbols" are what a package must reach
defensively because its wave partner adds them.

### Part A - the giant refined

### 3.1 P48 - The body pipeline II: leaf bones, build weights, landmarks, parts on demand, the shadow proxy, the free cape and the clips II

- **Wave / lane:** W29, A (the wave's asset writer), parallel with P49. **Depends on:** 0.10.0-m10;
  probes 1, 2 and 10.
- **Goal:** regenerate the giant once so that everything after it builds on the final skeleton and
  vertex data, without changing a pixel of the body or a frame of M10's clips; make styles and
  garments loadable one at a time; give the motion package every clip and landmark it needs.

**Owned paths**: `tools/giant/kit/{giant_body,export_game,split,giant_garment,clips}.py`,
`tools/giant/{build_giant,manifest}.py`, `tools/giant/test_giant_tools.py`; `assets/giant/**`;
`scripts/presentation/giant_model.gd`, `tools/builders/giant_model.gd`,
`scenes/player/giant_model.tscn`; tests `tests/integration/test_giant_assets.gd` (extended),
`tests/integration/test_giant_parts.gd`, `tests/slow/test_giant_parts_render.gd`.

**Hotspot edits**: `assets/giant/PROVENANCE.md`; `docs/plans/FOLLOWUPS.md`.

**Design** (§2.2, §2.3's clip list):
1. **The freeze test first**: a tool test that rebuilds the body and compares positions, normals,
   UVs, region ids, the 53 bones and the weights with M10's (from the committed `giant.glb` at
   `5ff50f0`, read once into a fixture of hashes). Everything below must keep it green.
2. **Leaf bones** and the re-weighting of hair and beard cards along their length; the index's
   `chains`.
3. **Build weights** in `COLOR.g` and `.b` from the muscle and weight macro targets
   (`universal-male-*-maxmuscle-maxweight` against the averages already used), inherited by
   garments and hair roots; `build_max_m`. If probe 2 failed: the fallback of §1.2, decided with the
   orchestrator before this item starts.
4. **Landmarks**: the grips, their axes, knuckles, toes; `side` per design.
5. **Parts**: `giant.glb` and `parts/*.glb`, the manifest's files (13 become about 35), the import
   settings written for each, `GiantModel.ensure_part`, `release_unused`, the shared part cache; the
   builder's index with `part`. If probe 1 failed: the fallback.
6. **`ShadowProxy`** in `giant.glb` (the body decimated to about 2,500 triangles with its weights).
7. **The free cape** on its three chains, closed at the collar, with a rest shape that hangs.
8. **The clips II** (19 new; the hand clips with finger tracks only), each measured as M10's were
   (stride, foot slide, the stomp's plant point under the hip, the turn's 90 degrees).
9. **`--verify`, `--skip-bake` and `--budget`** over the new file list; `check.sh --giant` time.
10. **Measure**: one Web test export for the share and the bytes per 1,000 triangles (the rate
    every later budget uses); mesh buffers with the default look and the fullest look; a part's
    first-load time natively.

**Tests**: the freeze test; no body vertex weighted to a leaf bone; every card's root on `head`;
build weights within 0-1 and symmetric left to right within 2/255; every part loads, binds and
draws (rendered, the slow tier); `release_unused` frees what no look shows and never the body; two
models share a part; M10's nine clips byte-identical in their tracks for the 53 bones; every new
clip's measurements within its row; the index, the manifest and the files agree; the saved scene
reloaded from disk.

**Test time**: 0.3 s / 5 s / 0. **Acceptance:** [A] `check.sh --giant --require` and `--giant-full`
bit-exact in a fresh worktree; the game plays as 0.10 (the full tiers, the soak); mesh buffers of the
fullest look at most 4.5 MB; the share measured. **Size:** about 2,400 new lines (Python 1,500,
GDScript 350, tests 550). **Split point:** item 7 moves to P51 if P48 passes 7 hours.
**Cross-lane symbols:** none.

### 3.2 P49 - Web, tools and performance debts; the M11 pre-declarations

- **Wave / lane:** W29, B, parallel with P48. **Depends on:** 0.10.0-m10; probe 9.
- **Goal:** close or honestly re-record every open tool and Web row of M10 before new work leans on
  them; teach the build the staged budgets; cut the giant's shadow cost; land Part A's registries.

**Owned paths**: `tools/build_web.sh`, `tools/pck_files.py`, `tools/check.sh`, `tools/web/**`,
`web/launcher.html`, `export_presets.cfg`; `scripts/presentation/{rig_paint,actor_rig}.gd` (the
shadow path only); `ui/screens/creator/giant_preview.gd` (`pixel_scale()` only);
`ui/screens/title_screen.gd` and the loading screen (warm-ups only); `scripts/debug/ui_probe.gd`;
tests `tests/unit/test_predeclared_m11.gd`, `tests/integration/test_build_web_budget.gd` (extended),
`tests/slow/test_giant_shadow_proxy.gd`, the `tools/web/test_*.mjs` of each changed check.

**Hotspot edits**: `scripts/core/events.gd` (anchors P50-P66), `tests/support/{reset_hooks,
anchors_expected}.gd`, the moves of §1.7 rules 2 and 3; `docs/PERFORMANCE.md`; `docs/plans/FOLLOWUPS.md`.

**Design**:
1. **Pre-declarations** for Part A and `test_predeclared_m11.gd`; the headroom moves.
2. **The budget rule**: m11 26, m12 32, m13 and later 44; `GIANT_SHARE` as today and `PEOPLE_SHARE`
   (`tools/pck_files.py --people-share`; capped at 12.0 from m13); the report of parts for three and
   four; `test_build_web_budget` for each milestone and for a four-part pack.
3. **The launcher**: decode and inflate the parts as they arrive instead of joining their text
   (probe 9 says whether that is one stream or a part at a time); the download note; a pack of four
   parts tested with `--check-size` and in Chromium.
4. **The shadow proxy path**: when a model has a `ShadowProxy`, the other meshes cast no shadow; the
   measurements at `medium` (the Valley walk, the stress arena) before and after.
5. **Export reproducibility**: make the conversion of text scenes deterministic for the export
   (the builders write stable node ids, or the export cache is cleared and the ids seeded - whichever
   the engine allows; found by trying both), then two checkouts must export the same pack bytes. If
   neither works: the release procedure of 0.10 (publish the checked bytes) becomes a written step.
6. **The checks' flakiness**: `audio_check.mjs` waits for the title's buttons to enable before it
   presses Enter; `world_check.mjs`'s recorder maps the audio clock piecewise (a reference every 10
   s) instead of with one line; `test_stream_check.mjs`'s stub gets a margin that its own noise
   (29-61 ms) cannot cross, with ten consecutive passes as its acceptance.
7. **The memory growth under a starved browser** (LD-1): isolate what allocates (a heap snapshot at
   two points of a level load with the CPU throttled) on 0.10 and on 0.9; fix it if it is the
   game's (an unbounded queue of frames or of audio blocks is the suspicion; ASSUMED), else record
   the engine's behaviour and keep the guard.
8. **The preview on the Web**: measure the creator's frame at `pixel_scale()` 1, 1.5 and 2 in
   Chromium; set the largest that keeps the first frame within the stall rule; `--continue` warms
   the preview's variants on the loading screen; the creator's first frame after New Game measured
   with `first_draw` and brought under 3 times the median, or its cause recorded.
9. **Measure and record**: the default tier's per-suite times at the base; draw calls at `low` and
   `medium`; the page's peak memory.

**Tests**: the registries; the budget rule per milestone; a four-part pack judged; the launcher's
unit test for part-wise decoding (`tools/web/test_launcher_parts.mjs`); shadows: with the proxy the
shadow pass draws one mesh of the giant (the render server's draw count in a still scene); each
changed check's own test.

**Test time**: 0.4 s / 10 s / 0. **Acceptance:** [A] every row of the handoff's §5.4 that names a
tool or the Web is closed or re-recorded with a measured reason; `medium` within §2.12's row; two
checkouts export the same bytes or the written procedure exists; the default and slow tiers have
their headroom. **Size:** about 1,800 new lines. **Cross-lane symbols:** `ShadowProxy` (P48): the
shadow path and its test skip with a note while the model has none; the W29 merge runs them.

### 3.3 P50 - The giant's motion: the hands, the stomp, sprint, turns, flinches, blends, secondary motion, reach and first person

- **Wave / lane:** W30, A, parallel with P51. **Depends on:** P48, P49; probe 4.
- **Goal:** every row of Part A's gate that is motion (§0.3), measured where it can be and filmed
  from the side where it must be judged.

**Owned paths**: `scripts/presentation/{skinned_rig,pose_brain_modifier,tip_matching,
secondary_motion,camera_rig,hit_feedback}.gd`; `scripts/debug/capture_m11.gd`;
`assets/shaders/giant_first_person.gdshaderinc`; tests `tests/integration/test_skinned_rig.gd`
(extended), `tests/unit/test_tip_matching.gd` (extended), `tests/unit/test_skin_rules.gd`
(extended), `tests/integration/test_secondary_motion.gd`, `tests/slow/test_giant_motion_render.gd`,
`tests/gate/test_capture_m11_tour.gd`, `tests/gate/test_giant_determinism.gd` (extended).

**Hotspot edits**: `scripts/debug/autopilot.gd` (the scenario's dispatch); `docs/PERFORMANCE.md`
(the skin's CPU); `docs/plans/FOLLOWUPS.md`.

**Design** (§2.3):
1. **The grip through the fist** and the off hand (LC-5), with the family grips.
2. **The legs' new sources**: landing, stomp, sprint, turning, bracing; the cross-fade table.
3. **Flinches** from the hit direction.
4. **`SecondaryMotion`** and its resets; the fallback if probe 4 failed.
5. **The reach extension** in `TipMatching` and the re-measured contract for every weapon and stage,
   fitted and past fit.
6. **First person**: `fp_rest`, the block's forearm, the skirt's fade.
7. **The capture tour** `capture_m11 --part=a`: each beat from the side, the front and
   three-quarters - idle, walk, run, sprint, a turn each way, a jump and landing, each family's
   light and heavy, the stomp, the roar, a self buff, a block, both dodges, Shoulder Charge, a grab,
   hold and throw, four flinches, the death; stages 1, 4 and 6; first person at rest, blocking and
   looking down.
8. **Cut-list items, in this order if time remains**: the head look; foot placement on slopes; the
   growth tween.

**Tests**: the handle's axis within 0.02 x k of the fist's centre in every generic pose; each source
chosen for its state and no other, with no pop (no bone's rotation changes by more than 25 degrees
between two posed frames outside a teleport); the stomp's foot leaves and meets the ground at the
phase's fractions; turning steps only while the brain does not walk; flinches never in an active
window; secondary chains exist only for looks that use them, rest within 1.5 s, and stay inside
their limits through a full head turn and the heavy swing; tip matching's M10 contract unchanged for
fitted weapons and the new bound for unfitted ones; first person shows no cap at pitches down to -85
degrees at stages 1, 4 and 6; the code rules; the determinism suite with the new stats (secondary
motion frames above 0, flinches above 0).

**Test time**: 0.6 s / 30 s / 4 min. **Acceptance:** [A] the motion rows of §0.3; the skin's CPU
within §2.12; the soak and the Valley twin byte-identical to 0.10 with the skin on and off; the tour
complete with 0 errors. **Size:** about 2,600 new lines. **Split point:** item 6 goes to a gate lane
if P50 passes 8 hours. **Cross-lane symbols:** the hair shader's `volume_normal` and the eye's
`look` (P51): written only when the uniform exists.

### 3.4 P51 - The giant's look pass II: hair beyond cards, the skin's tone and subsurface term, eyes, scars and marks, cloth

- **Wave / lane:** W30, B (the wave's asset writer), parallel with P50. **Depends on:** P48, P49;
  probes 5 and 6.
- **Goal:** every row of Part A's gate that is graphics, each against a frame.

**Owned paths**: `tools/giant/kit/{giant_hair,giant_skin,skin_textures,bake,pack,designs}.py`
(designs: scars and marks only), `tools/giant/build_giant.py`; `assets/giant/**`;
`assets/shaders/giant_{skin,hair,eye,cloth,shell}.gdshader`; `scripts/presentation/giant_look.gd`;
tests `tests/unit/test_giant_look.gd` (extended), `tests/slow/test_giant_shaders.gd` (extended),
`tests/slow/test_skin_tone_render.gd`, `tests/slow/test_hair_render.gd`.

**Hotspot edits**: `ui/screens/creator/option_rows.gd` (the swatch's colour from
`GiantLook.drawn_tone` only); `assets/giant/PROVENANCE.md`; `docs/plans/FOLLOWUPS.md`.

**Design** (§2.4):
1. **Hair shading**: head-centred normals baked into the cards, `volume_normal`, the two-lobe
   highlight, softer card-on-card shadow; applied to every style before any geometry changes, and
   compared with M10's frames.
2. **Hair geometry**: shells for the crop (with a fringe), the stubble mask's replacement at close
   range and the short beard; the braided styles' braids as tubes with bead anchors; the loose
   strand layer on the long styles; the braided and the short beard's wide cards replaced; a beard
   that exists from behind (`back_fade` no longer hides it; the under-jaw cards are closed); a
   coarser last LOD for cards.
3. **The skin**: the bake tone re-derived against the approved renders under the creator's light
   (the chest patch within 12/255 a channel of (198, 170, 157)); curvature baked and packed; the
   lookup; `light_model` 3 on both tiers; `drawn_tone` for the swatches.
4. **Eyes**: the highlight, the limbal ring, the lid shadow, `look`; lashes and fuller brows as a
   few cards in the `Eyes` mesh's draw call.
5. **Scars and marks**: the brow scar and the two thinnest strokes widened to the 4 cm rule; scar
   relief tuned; the option check's floors met by every scar and mark in one of the two views.
6. **Cloth**: the detail maps at 256 px, `rim`, the metal kind (used from P54 on), the dark-leather
   dye lifted so it is not black in shadow; the braies' and the tunic's caps (first person) with
   P50.
7. `--giant-full` (the bake inputs change in item 3).

**Tests**: every uniform `GiantLook` sets is declared; every style renders non-blank on both tiers;
the hair check's two measures better than M10's frames for every style (outline roughness, scalp
share) and the beard visible from behind above a pixel floor; the skin's patch; an eye's highlight
present at the Face framing and its `look` moving the iris; every scar and mark above its floor;
shells one draw call a style.

**Test time**: 0.3 s / 5 s / 0 (its renders extend suites that exist). **Acceptance:** [A] the
graphics rows of §0.3; `--giant-full` bit-exact; the share within 7.6. **Size:** about 2,300 new
lines (Python 1,100, shaders 500, GDScript 250, tests 450). **Split point:** item 6 to a gate lane.
**Cross-lane symbols:** none.

### 3.5 P52 - Ship `0.11.0-m11`

- **Wave / lane:** W31, A, parallel with P53. **Depends on:** Gate A; the owner's approval for the
  tag, the play link and the merge.

As M10's P47: `README.md`, `ARCHITECTURE.md` (§23 revised, a new §24 "The giant refined"),
`DECISIONS.md` (§0.4's decisions that Part A used), `docs/M11_HANDOFF.md` (the spec's §16 items, Gate
A's table, the owner's tasks), `USABILITY_SCRIPT.md`'s motion sheet; the version, the description and
the launcher's notes; the Linux export run headless (the soak, an assisted bot run) and under Xvfb
with `--skin` (the tour, 0 errors); the Windows export built; `build_web.sh` twice with the same
bytes; the five Chromium checks; the screenshots in `docs/screenshots/m11/`; the final check
`check.sh --build --slow --gate --giant-full --audio --require --strict-times`. After the approval:
the tag, the play link, the pull request and its merge. **Size:** docs and release only; no game
code.

### Part B - more customization

### 3.6 P53 - The look record v2: slots, sliders, migration, and `GiantLook` by slot

- **Wave / lane:** W31, B, parallel with P52. **Depends on:** P48, Gate A's code.
- **Goal:** the record, its migration and the look path at version 2, complete and shippable on
  M10's ten garments, so that the wardrobe and the creator II only add content and screens.

**Owned paths**: `scripts/progression/appearance.gd`,
`scripts/actors/player/player_appearance.gd`, `scripts/core/schemas/appearance_{set,preset}_schema.gd`,
`scripts/presentation/{giant_look,giant_model}.gd`, `assets/shaders/giant_{skin,cloth}.gdshader`
(the `build` push); `data/appearance/**` (the six outfits as slot sets, `set_garment.json`,
`set_metal.json`, `set_build.json`, the presets rewritten at `v` 2);
`data/tutorial/appearance_slots.json`; `tests/fixtures/saves/v2_appearance_v2*.json`,
`v2_appearance_v3_future.json`; tests `tests/unit/{test_appearance_record,test_appearance_migration,
test_appearance_schemas,test_giant_look,test_predeclared_m12}.gd`,
`tests/integration/test_appearance_session.gd` (extended), `tests/unit/test_save_migration.gd` and
`test_save_slots.gd` (their own new tests), `tests/support/appearance_v1_oracle.gd`.

**Hotspot edits**: `scripts/progression/character_state.gd`, `scripts/core/save_slots.gd` (the one
note), `scripts/core/game_data.gd` (its anchor), `scripts/core/data_validator.gd`,
`ui/screens/creator/option_rows.gd` and `ui/screens/shrine/appearance_tab.gd` (the smallest change
that keeps today's creator working on slots: the Clothing category shows the six outfits as before
and writes slots); the headroom moves; `docs/plans/FOLLOWUPS.md`.

**Design** (§2.5, §2.6's index fields for M10's garments):
1. **The oracle**: M10's `Appearance` copied into `tests/support/` unchanged.
2. **`migrate`, `sanitize`, `default_record`, `resolve`, `to_look`, `random_record`,
   `summary_lines`, `covered_regions`** at v2; the future-version rule at "above 2".
3. **`GiantLook`** by slot: garments as `{mesh, dye, kind}`, the per-slot dye, `build`, accessories
   and beads (no content yet), `face` (set as blend-shape weights when the mesh has the key, else
   ignored).
4. **The session and saves**: the migration note, the `appearance.slots_seen` flag, absent stays
   absent, a v1 record rewritten only at a kept look or the next checkpoint.
5. **Data**: the sets and presets at v2; the build set.
6. **Pre-declarations for Part B** and the headroom moves.

**Tests**: the migration matrix (every M10 preset; a record per v1 option; the look equal to the
oracle's); every M10 fixture and the 26 broken shapes; v2 fixtures (unknown slot item, wrong slot,
broken `slots`, future `v` 3 kept byte for byte through a checkpoint); `to_look(default)` equals
`DEFAULT_LOOK`; 1,000 random records valid in every scope; the build push moves no landmark (the
skeleton untouched) and changes the rear silhouette (rendered); a save without a look still captures
none; the creator's Undo over a slot change.

**Test time**: 0.8 s / 15 s / 0. **Acceptance:** [B] §0.3's record row; the game plays and saves as
0.11 for a player who changes nothing. **Size:** about 3,000 new lines (GDScript 1,600, data 500,
tests 900). **Split point:** `face` in `GiantLook` moves to P56. **Cross-lane symbols:** none.

### 3.7 P54 - The wardrobe: garments and armour by slot, accessories

- **Wave / lane:** W32, A (the wave's asset writer), parallel with P55. **Depends on:** P53.
- **Goal:** the 25 new garments and 8 accessories of §2.6, each a part on demand, stacking without
  intersection, dyed by material, within the share.

**Owned paths**: `tools/giant/kit/giant_garment.py` (slots, shell offsets, the new builders),
`tools/giant/kit/pack.py` (`cloth_metal.png`), `tools/giant/build_giant.py`; `assets/giant/**`;
`assets/shaders/giant_cloth.gdshader` (kinds); `data/appearance/{set_garment,set_accessory,
set_outfit,set_dye,set_metal}.json` and the presets' outfits; tests in `test_giant_tools.py` (the
shell distances, closed limb parts, caps), `tests/integration/test_giant_assets.gd` (extended),
`tests/slow/test_wardrobe_render.gd`.

**Design**:
1. **Slots and offsets** applied to M10's ten garments first (they move by at most a few
   millimetres; the option check's floors re-measured).
2. **The garments**, in the cut list's reverse order (§6.3, so what is cut last is built first): an
   undergarment for the legs (closing M10's bare-hips row), trousers, the kilt, the hood, the mail
   hauberk, the leather cuirass, iron pauldrons, vambraces, greaves, the long cloak, then the rest.
   Mail and scale are shells with a detail map, not modelled rings.
3. **Head garments and hair**: `hides_hair`, the helms' cut of long styles by `length`.
4. **Accessories**: rigid meshes on one bone each (neck on `spine_03`, arm ring on `upperarm_l`,
   belt trophies on `pelvis`), at most 400 triangles.
5. **Coverage**: each garment's `covers` and coverage per region for "Hidden by your clothing".
6. **Twelve outfits** as slot sets; the dyes and the metal palette, readable in the world's light.
7. `--giant`, the share, the draw calls of the fullest slot look, the mesh buffers.

**Tests**: the shell distance for every overlapping pair in four poses; no open edge on limb parts;
every garment's part loads and draws; every outfit valid; the fullest look at most 24 draw calls and
70,000 primitives; a helm hides or cuts each hair style as its entry says.

**Test time**: 0.3 s / 5 s / 0. **Acceptance:** [B] the garments of §2.6 or the cut list applied in
order with the reason; no intersection found by the test or the rendered check; the share within its
cap. **Size:** about 2,600 new lines (Python 1,700, data 500, tests 400). **Cross-lane symbols:**
none (P55 reads the sets).

### 3.8 P55 - The creator II: pages, thumbnails, the filter, slot rows and sliders

- **Wave / lane:** W32, B, parallel with P54. **Depends on:** P53.
- **Goal:** §2.7: a creator that holds about 190 options and is still quick with a pad.

**Owned paths**: `ui/screens/creator/{creator_screen,option_rows,option_grid,thumbnail_cache,
giant_preview}.gd`, `ui/screens/shrine/appearance_tab.gd`; tests
`tests/integration/{test_creator_screen,test_shrine_appearance}.gd` and `tests/slow/test_creator_mouse.gd` (extended),
`tests/integration/test_creator_grid.gd`, `tests/slow/test_creator_thumbnails.gd`.

**Hotspot edits**: `docs/USABILITY_SCRIPT.md` (the creator sheet revised); `docs/plans/FOLLOWUPS.md`.

**Design**: 1. the eleven categories and the slot rows; 2. `OptionGrid` (pages, focus, "None", the
material filter, the keyboard's filter box, the pad's page keys); 3. `ThumbnailCache` (one a frame,
visible page only, the Web's rule); 4. sliders (build, face, grey) with snap and the rear view; 5.
outfits as starting points, "custom"; the colours category with per-slot overrides; 6. framing by
`side`; 7. the layout at five sizes; the footer's hints; the discard question, Undo and Randomize
over every new row (Randomize dresses by slot and never stacks an armour over a bare chest unless
the outfit it started from did).

**Tests**: every option of every set reachable and applied with the pad, the keyboard and real
mouse events; at most 4 pad moves from a category to any option (computed from the grid's
geometry); the focus never lost through 200 scripted moves; the filter; thumbnails arrive for the
visible page only and never more than one a frame; Undo through 64 changes including grid picks and
sliders; the layout inside the window at 1280x720 to 2560x1440; a later build's record still never
edited in place.

**Test time**: 0.8 s / 20 s / 0. **Acceptance:** [B] §0.3's creator row. **Size:** about 2,900 new
lines. **Split point:** per-slot dye overrides move to P57. **Cross-lane symbols:** P54's new sets:
the rows are built from data, and an empty set shows an empty grid.

### 3.9 P56 - The catalogue II: hair, beards, braids and beads, designs, face keys, presets

- **Wave / lane:** W33, A (the wave's asset writer), parallel with P57. **Depends on:** P54; probe 3.
- **Goal:** the rest of §2.6's target, the owner's notes on checkpoint A applied where they are
  data or parameters, and the face sliders if the probe allows.

**Owned paths**: `tools/giant/kit/{giant_hair,designs,giant_body,export_game}.py` (the face keys
only in the last two), `tools/giant/build_giant.py`; `assets/giant/**`;
`assets/shaders/giant_{hair,skin}.gdshader`; `scripts/presentation/giant_look.gd` (`face`);
`data/appearance/**`; tests `test_giant_tools.py`, `tests/slow/test_design_array.gd` (extended),
`tests/unit/test_appearance_record.gd` (the new options).

**Design**: 1. five hair and four beard styles with bead anchors; three bead sets; 2. twelve
tattoos (four for the legs: regions 11-13), four war paints and the two-paint rule in the packer
(a face paint and a body paint never share a region's area), four scars; the array's layers under
M10's packing rule; 3. **face keys** if probe 3 found the cause: six shape keys on `Body_Head` built
from the vendored detail targets (jaw, chin, nose, brow, cheek, an age blend), copied to every
beard and to the hairline strips, each tested for the dark patch at the Face framing; the freeze
test of P48 extended to "the base shape is unchanged"; if the probe failed, this item is not built
and `set_face.json` is not shipped; 4. fourteen presets; 5. the owner's notes.

**Tests**: every new style renders, sways and takes beads; every design round-trips the compressor
under M10's bounds; every design category keeps an option above its view floor; a face key at +1
and -1 leaves no patch darker than its neighbourhood by more than 8/255 and moves no beard root off
the skin by more than 2 mm; every preset valid and distinct in the rendered grid.

**Test time**: 0.3 s / 5 s / 0. **Acceptance:** [B] the catalogue's row of §0.3. **Size:** about
2,300 new lines. **Cross-lane symbols:** none.

### 3.10 P57 - Web and performance for the wardrobe; the option check and the wardrobe sheet

- **Wave / lane:** W33, B, parallel with P56. **Depends on:** P54, P55.
- **Goal:** Part B inside every budget of §2.12 on the Web and natively, the rendered proof that
  every option shows, and the sheet the owner will look at.

**Owned paths**: `tools/web/creator_check.mjs` and its test, `tools/build_web.sh` (only if a share
line changes), `tools/character_sheet.tscn` and its script, `scripts/debug/capture_m11.gd` (`--part=b`),
`tests/slow/test_appearance_render.gd` (moved to `tests/gate/` and extended to grids per slot),
`tests/gate/test_wardrobe_stack_render.gd`; `ui/screens/creator/**` (fixes its checks find).

**Design**: 1. a Web export and `GIANT_SHARE`; parts loaded on demand in the browser (a part's
first-show stall measured: it must stay under the rule or the creator preloads the open category's
parts); 2. the creator check drives a slot grid, a slider, an outfit and Keep in Chromium; the
thumbnails' cost on the Web decides the Web's rule (§2.7); 3. the option check over every option
of every set, per slot, in its framed view and for designs in the rear or first-person view; 4.
the stack check: 200 random slot looks rendered in three poses with no z-fighting pixels above a
floor; 5. draw calls, primitives, memory, the skin's CPU with twelve garments; 6. the wardrobe sheet
(§4.2) and the tour's part b.

**Test time**: 0.1 s / 10 s / 4 min. **Acceptance:** [B] §2.12's rows for the giant; the Chromium
check passes on the candidate. **Size:** about 1,700 new lines. **Cross-lane symbols:** P56's
options (the checks read the sets).

### 3.11 P58 - Ship `0.12.0-m12`

- **Wave / lane:** W34, A, parallel with P59. As P52, with the save migration's cross-version run
  recorded in the handoff (`docs/M12_HANDOFF.md`), the pack judged at 32 MiB in three parts, the
  screenshots in `docs/screenshots/m12/`, and the release note that a look made in 0.12 shows only in
  0.12 or later.

### Part C - realistic NPCs

### 3.12 P59 - The people pipeline: the human generator, roles, atlases, LODs, crowd poses and clips

- **Wave / lane:** W34, B (the wave's asset writer), parallel with P58. **Depends on:** P48, P51,
  Gate B's code; probe 10; the owner's answer to question 6.
- **Goal:** §2.8 for humans: every role's file generated, verified and measured, with nothing in
  the game using them yet.

**Owned paths**: `tools/giant/build_people.py`, `tools/giant/kit/people_{body,outfit,roles,bake}.py`,
`tools/giant/test_people_tools.py`; `tools/giant/mpfb2/**` (more audited targets, `FILES.sha256`,
`SOURCE.md`) and `tools/giant/fetch_mpfb2.py`; `assets/people/**`; `tools/giant/kit/clips.py` (the
proportions parameter only); tests `tests/integration/test_people_assets.gd`.

**Hotspot edits**: `tools/check.sh` (`--people`, `--people-full`), `tools/build_scenes.gd` (the
builder's line; the registry skips the file until P60 writes it),
`scripts/core/data_validator.gd` (`person_role`), `tests/support/{reset_hooks,anchors_expected}.gd`,
`tests/unit/test_predeclared_m13.gd`, the headroom moves; `CREDITS.md`; `docs/PERFORMANCE.md`.

**Design**: 1. the 23-bone reduction and its weight folding, tested against the giant's skeleton
names; 2. `people_body` (builds, faces, the women's targets after their audit); 3. `people_outfit`
(dress, cull hidden skin, merge, atlas, decimate, LODs) and the roles table; 4. `people_bake` and
the palette mask; 5. crowd-pose meshes, `corpse` and far meshes; `gear.glb`; 6. `people_clips.glb`;
7. the manifest, `--verify`, `--skip-bake`, `--budget`, the check options; 8. provenance; 9. one
Web test export: the people's share and the bytes per variant and atlas.

**Tests**: a variant is one mesh, one surface, at most 5,000 triangles, 23 bones by name, four
weights; no skin triangle under a garment survives; the palette bands decode; every crowd-pose mesh
matches its clip's pose within 1 cm at the joints; `--verify --skip-bake` bit-exact; the audit's
file list equals the vendored files' hashes; the import settings.

**Test time**: 0.3 s / 5 s / 0. **Acceptance:** [C] `check.sh --people --require` and
`--people-full` bit-exact in a fresh worktree within their times; the share measured and within
§2.12's plan, or the variant count cut in §6.3's order. **Size:** about 3,200 new lines (Python
2,500, tests 500, shell and GDScript 200). **Split point:** `notable` and `rider` move to P61.

### 3.13 P60 - `PersonRig`, the crowd and the soldiers

- **Wave / lane:** W35, A, parallel with P61. **Depends on:** P59; probes 7 and 8.
- **Goal:** soldiers, archers, mages, pikemen, shieldmen, bannermen, the iron guard and siege crews
  are realistic in play, alone and in formations, inside the budgets, with gameplay proven unchanged.

**Owned paths**: `scripts/presentation/{person_model,person_look,person_rig,crowd_renderer,
rig_paint,actor_rig,telegraph_visuals,hit_feedback}.gd`; `assets/shaders/{person,person_crowd}.gdshader`;
`scripts/core/schemas/{person_role,enemy,npc}_schema.gd`; `data/people/role_{soldier,archer,mage,
crew}.json`; `tools/builders/{people_models,soldier,ranged,formations,siege}.gd` (the crew) and the
regenerated scenes; tests `tests/unit/test_person_look.gd`, `tests/integration/{test_person_rig,
test_crowd_renderer}.gd` (the second extended), `tests/slow/test_people_render.gd`,
`tests/gate/{test_people_determinism,test_people_readability}.gd`, and the rewrites of the suites
that assert box meshes (found by grep; listed in the system doc).

**Hotspot edits**: `scripts/actors/enemy_actor.gd` (presentation hooks only: the rig's level, the
corpse hand-off; no state the simulation reads), `data/enemies/{soldier,archer,mage,pikeman,
shieldman,bannerman,iron_guard,siege_crew}.json` (`body`; the schema also takes the giants'
`appearance` key that P62 uses); `docs/PERFORMANCE.md`.

**Design** (§2.9): 1. `PersonModel` (the pool, the index), `PersonLook` (variant, palette, height,
gear), the shaders; 2. `PersonRig`: the three levels, the cap, the clip driver, the arm modifier,
tip matching in weapon arcs; 3. the crowd and far levels through `CrowdRenderer` for formations and
a shared renderer for loners, with the palette and the flash per instance; 4. corpses; held and
thrown; 5. the builders and scenes; the banner's flag kept; 6. the determinism suite with positive
controls (`PEOPLE_STATS`: skinned frames, promotions, at least two variants drawn, crowd instances
above 0; the soak, the Valley twin and the formation stress byte-identical to 0.10 with people on
and off); 7. the readability suite; 8. measurements: draw calls, primitives and CPU for a formation
of 40, natively.

**Tests**: as §0.3's rows for people; the cap never exceeded; a held soldier always skinned; a
corpse frees its slot; two ids give two looks and one id always the same; the weapon's outer half
inside the tested capsule for every telegraphed attack of every role (the people's tip-matching
contract); flashes reach crowd instances; headless nothing is instanced.

**Test time**: 0.8 s / 30 s / 6 min. **Acceptance:** [C] the soldiers' part of §0.3; the native
budgets of §2.12. **Size:** about 3,400 new lines. **Split point:** the loners' shared renderer
moves to P62 (loners then keep a skinned or far level only).

### 3.14 P61 - Mounts and the giants' gear: the quadruped kit, the horse, the rival giants' and Harrok's looks

- **Wave / lane:** W35, B (the wave's asset writer), parallel with P60. **Depends on:** P59, P54.
- **Goal:** the first quadruped - the horse - from the project's own kit, judged early; the rival
  giants' garments and looks.

**Owned paths**: `tools/giant/kit/quadruped.py`, `tools/giant/build_people.py` (`--horse`),
`assets/creatures/**`; `tools/giant/kit/giant_garment.py` and `assets/giant/**` (the hide mantle,
the war harness, the braided-beard rings: parts in the giant's tree); `data/appearance/preset_npc_
{rival_giant,harrok}.json`, `scripts/core/schemas/appearance_preset_schema.gd` (`npc`); tests in
`test_people_tools.py` and `tests/integration/test_creature_assets.gd`.

**Design**: 1. `quadruped.py` with the horse's parameters, its skeleton, weights by distance to the
bone chains, the script's UV unwrap, the coat's albedo and a mane and tail as cards with the hair
shader; 2. tack (saddle, bridle, caparison in the faction colour through the palette mask); 3. the
horse's clips are not clips: the `QuadrupedRig` brain drives the bones (P62), so the kit exports
rest poses for the gait's extremes only, as a check; 4. the giants' garments and the two looks; 5.
frames of the horse from the game camera at 10, 30 and 60 m beside a soldier, for the W35 merge's
**beast bar**: if the horse does not read as a horse at 10 m in those frames, the orchestrator
decides between another pass in P63's wave and the cut list before wolves are started.

**Tests**: the mesh is closed and manifold, at most 6,000 triangles, 25 bones; no vertex without a
weight; `--verify` bit-exact; the looks valid and hidden from the creator.

**Test time**: 0.3 s / 5 s / 0. **Acceptance:** [C] the horse's frames recorded and judged at the
merge; the giants' looks draw on the player's model in the sheet tool. **Size:** about 2,400 new
lines.

### 3.15 P62 - Townsfolk, named characters, riders and the rival giants

- **Wave / lane:** W36, A, parallel with P63. **Depends on:** P60, P61.

**Owned paths**: `scripts/presentation/{skinned_quadruped_rig,quadruped_rig,skinned_rig,
pose_brain_modifier,tip_matching}.gd`; `data/people/role_{villager,elder,notable,rider}.json`;
`data/npcs/*.json` and `data/enemies/{cavalry,corvane,rival_giant,harrok}.json` (`body`,
`appearance`); `tools/builders/{npcs,siege,big}.gd` (the cavalry; the giants and Corvane) and their
scenes; tests `tests/integration/{test_named_bodies,test_rider_rig,test_rival_giant_rig}.gd`,
`tests/slow/test_townsfolk_render.gd`, `tests/gate/test_people_determinism.gd` (extended: a world
walk through every town, the Moot test level).

**Design**: 1. villagers, elders and each named character with their variants and palettes (Edda,
Reeve Tamsin, Sedge, the ferrywoman, the herald, the toll captain, the deserter; Corvane at 2.0 m);
civilians' `cower` and flee; 2. `SkinnedQuadrupedRig` and the rider; the lance; 3. `SkinnedRig`
independent of the player; the rival giant and Harrok with their looks, tints and flashes, secondary
motion on, parts shared with the player's model; tip matching measured on their weapon data; 4. the
people sheet's pages for towns, riders and giants; 5. measurements in the six settlements and the
Moot.

**Test time**: 0.6 s / 20 s / 2 min. **Acceptance:** [C] every human scene and both giants realistic
in play; the settlements within 250 draw calls at `low`; the determinism suite passes with them.
**Size:** about 2,800 new lines. **Split point:** Corvane and the toll captain keep a soldier's
variant.

### 3.16 P63 - Brutes and wolves

- **Wave / lane:** W36, B (the wave's asset writer), parallel with P62. **Depends on:** P59, P61,
  the beast bar's decision.

**Owned paths**: `tools/giant/kit/{brute,quadruped}.py`, `tools/giant/build_people.py` (`--brutes`,
`--wolves`), `assets/creatures/**`; tests in `test_people_tools.py`,
`tests/integration/test_creature_assets.gd` (extended).

**Design**: 1. `brute.py`: the ogre and the troll (§2.8), their skins, gear for the king and the
matriarch, the whelp as the troll at 3.5 m with a younger face; 2. the wolf from the quadruped kit
(the dire wolf by scale and palette), its coat and the shell layers' mesh; 3. the brutes' clips from
the clip generator with their proportions (a heavier walk, a two-arm slam's stance, death); 4. far
meshes; 5. frames of each from the game camera beside the giant at stages 1 and 4 for checkpoint
C1.

**Tests**: as P59's and P61's for the new files; the brutes' arms reach the box rigs' reach bands
within 5 % (so tip matching has less to hide).

**Test time**: 0.3 s / 5 s / 0. **Acceptance:** [C] the files generated and verified; the frames for
C1. **Size:** about 2,500 new lines.

### 3.17 P64 - Brutes and beasts in the game; the Web tiers and performance for people

- **Wave / lane:** W37, A, parallel with P65. **Depends on:** P62, P63.

**Owned paths**: `tools/builders/{heavy,big,wolf}.gd` (ogres, trolls, the dire wolf, the wolf) and
their scenes; `data/enemies/{ogre,ogre_king,troll,troll_whelp,troll_matriarch,wolf,dire_wolf}.json`
(`body`); `assets/shaders/fur_shell.gdshader`; `scripts/presentation/{person_rig,
skinned_quadruped_rig,crowd_renderer}.gd`; `tools/web/people_check.mjs` and its test,
`tools/build_web.sh`, `export_presets.cfg`, `web/launcher.html`; the loading screen's warm-up;
`tools/character_sheet.tscn` (the people sheet), `scripts/debug/capture_m11.gd` (`--part=c`); tests
`tests/integration/{test_brute_rig,test_wolf_rig}.gd`, `tests/gate/{test_people_readability,
test_people_determinism}.gd` (extended to the bosses' seeded fights and a wolf pack),
`tests/gate/test_people_render_grid.gd`.

**Design**: 1. the brutes and bosses in their scenes (always skinned; the bosses' phase tints and
telegraphs checked one by one); 2. wolves and dire wolves on `SkinnedQuadrupedRig` with the fur
shell; packs beyond the cap; 3. **the Web**: an export within 44 MiB and `PEOPLE_SHARE`; the people
tier (if the Web bench needs it: 12 skinned instead of 16, six shell layers instead of twelve, set
by the `low` preset, not by the platform); the warm-up of the people's shader variants on the
loading screen; `people_check.mjs` (a formation of 40 in view on the formation test level, a town,
a wolf pack: draw calls, the people's CPU, first frames, memory, 0 console errors); 4. the full
measurements of §2.12 natively and on the Web; 5. the people sheet and the tour's part c.

**Test time**: 0.4 s / 10 s / 5 min. **Acceptance:** [C] §0.3's rows for brutes, beasts, budgets
and the Web. **Size:** about 2,700 new lines. **Split point:** the people tier's switches go to a
gate lane.

### 3.18 P65 - The people look pass: the owner's notes, variation, and the beasts' look gate

- **Wave / lane:** W37, B (the wave's asset writer), parallel with P64. **Depends on:** P62, P63,
  the owner's notes on checkpoint C1.

**Owned paths**: `tools/giant/kit/people_*.py`, `quadruped.py`, `brute.py`,
`tools/giant/build_people.py`; `assets/people/**`, `assets/creatures/**`; `data/people/**` (palettes
only).

**Design**: 1. the owner's notes on C1, as parameters, palettes and gear; 2. faces and hair at the
size they are seen (bolder brows, beards and headgear read at 30-130 px where fine features do
not); 3. faction palettes checked in the world's light (Aldmere, Brannock, Millford, Skarn, the
crown, the raiders) so a formation's side reads at 60 m; 4. the wolves' second pass (silhouette,
the ruff, the eyes' glow kept from the box wolf) and **the beasts' look gate**: the wolf, the dire
wolf and the horse at 10 m and 30 m beside a soldier; if the orchestrator's review, or the owner at
C1, finds one not good enough, that animal ships as its box rig (the scenes keep both paths behind
the record's `body` key) and the row goes to `FOLLOWUPS.md`; 5. LOD and far meshes tuned from P64's
numbers; 6. `--people-full`.

**Test time**: 0.3 s / 5 s / 0. **Acceptance:** [C] the notes applied or answered; the look gate's
decision recorded with its frames; `--people-full` bit-exact. **Size:** about 1,800 new lines.

### 3.19 P66 - Ship `0.13.0-m13`

- **Wave / lane:** W38, alone. As P52 and P58, with `ARCHITECTURE.md`'s new section for people and
  creatures, `docs/M13_HANDOFF.md`, `CREDITS.md` complete for the new CC0 targets, the six Chromium
  checks (M10's five and `people_check.mjs`), the pack judged at 44 MiB with `PEOPLE_SHARE`, the
  launcher's download note, the final check with `--people-full`, and the screenshots in
  `docs/screenshots/m13/`.

---

## 4. The gates, the owner's checkpoints and the releases

### 4.1 The gate review (once per part)

After the part's last wave merge (`check.sh --build --slow --gate --giant-full --audio --require
--strict-times`, with `--people-full` at Gate C; the soak; the capture tour of the part). As at the
M10 gate: independent review agents, two lenses each; every finding verified adversarially by
another agent (reproduced, or dropped); confirmed findings fixed in at most two worktree lanes at a
time, each with a regression test or a rendered comparison, and at most one lane writing generated
assets; an audit of the fixes until it comes back dry. Minor confirmed findings that are not fixed go
to `docs/plans/FOLLOWUPS.md` under "From the M11 gate review" (then M12, M13), each with its owner.

| Lens | Gate A (the giant refined) | Gate B (customization) | Gate C (NPCs) |
| --- | --- | --- | --- |
| 1. The owner's request | Every motion and graphics item they could name from "refine and improve the Giant movements and graphics", seen in the tour and in play | Clothing by slot, armour, accessories, hair and beards with beads, designs, sliders, presets, at New Game, the launcher's world start and shrines | Every kind the owner listed is realistic in play, in the order they chose; nothing they listed is left a box without a recorded decision |
| 2. Gameplay unchanged | The full tiers; the code rules; the 120 s seeded soak, the world bot's smoke run and the Valley twin byte-identical on `0.10.0-m10` (a scratch worktree) and on the candidate once wall-time, node-count and memory fields are removed, with the skin on and off and two looks; `SKIN_STATS` with secondary motion and flinch counts above 0 | The same against 0.10 and 0.11, with a v1 look migrated and a v2 slot look; no gameplay number in the diff | The same with people on and off (`PEOPLE_STATS` above 0: skinned frames, promotions, two variants, crowd instances), plus the formation stress, the three boss fights seeded (`test_bosses_seeded`) and a world walk through every region with AI on; the director's counts, kills, loot and every bot result identical; no data key other than `scene`, `render_lod_m`, `body` and `appearance` changed in any enemy or NPC record |
| 3. Animation quality | The frames of the tour from the side, the front and three-quarters for every beat of §3.3's list; the hands; tip matching fitted and past fit; no pop; hair and cape through a head turn and a heavy swing; first person | The wardrobe in motion: no garment through another or through the body in the walk, the run and a heavy swing; the cloak and the kilt | People: walk, run, flee, brace, a strike of every role with its telegraph, held, thrown, death and corpse; riders; the giants' swings; brutes; the wolf's trot, lunge and snap |
| 4. Saves and migration | 0.10 saves load and play; nothing in the record changed | Every fixture as raw files; the migration oracle; a 0.12 save opened by the 0.10 and 0.11 builds (real binaries) keeps its look bytes through Continue, a checkpoint and a death reload; a 0.10 and a 0.11 save opened by the candidate migrate with the one message; broken, unknown and future records | 0.10-0.12 saves load; a save taken mid-battle on 0.12 reloads with the same members and states |
| 5. UI and controls | The creator unchanged but for swatches that show the drawn colour; the preview's sharpness | Pad, keyboard and mouse through every category, grid, slider and filter; the 4-move rule; the focus; Undo; the layout at five sizes; the shrine's summary; the Web pointer lock | The HUD's lock line, health bars and telegraphs over realistic bodies; nothing in the UI names a role wrongly |
| 6. Web and performance | The pack within 26 MiB and the share within 7.6; the five Chromium checks; draw calls at `low` and `medium`; the skin's CPU; stalls; memory | The pack within 32 MiB in three parts, the share within 13.6; the creator check with grids and thumbnails; parts on demand in the browser; the giant's draw calls | The pack within 44 MiB, `PEOPLE_SHARE` within 12.0, the page at most 60 MB; the six Chromium checks; a formation of 40, a town and a wolf pack within draw calls, CPU, memory and stalls |
| 7. Provenance and determinism of the assets | `--giant-full` bit-exact in a fresh worktree; the freeze test; no hand-edited generated file; scenes rebuild with no diff | The same with every new part; no copied code | `--people-full` bit-exact; the audit of the added CC0 targets against the wheel; `PROVENANCE.md` says for each creature file that it is the project's own geometry; `CREDITS.md` |
| 8. The look | The hair, the skin, the eyes and cloth against the approved renders and M10's frames; the owner's notes | Every option shows (the option check); the stack check; the build sliders in play; the owner's notes | People beside the giant at the game camera's sizes; variation in a formation and a town; faction colours at 60 m; the beasts' look gate; the owner's notes |

### 4.2 The owner's checkpoints

**0. Before W29 - the note.** The plan in plain words: the three parts and their order; what will
not be reached (§0.5, in a paragraph: hair is still polygons, no motion capture, no talking faces,
scripted animals); the download's steps; the questions of §0.6. Nothing waits for the answers.

**A. After Gate A - play it, then approve it.** A private page with the Part A candidate (the
public link stays on 0.10 until the approval); a 90-second video cut from the tour, with the side
views of the walk, run, sprint, a turn, the stomp and a heavy swing next to the same beats recorded
from 0.10; and **the giant sheet**, rendered by the game: (1) hair - every style at the Face and
Hair framings, 0.10 beside the candidate beside the approved close-up; (2) skin - the ten tones
under the creator's light and the world's sun, the default beside the approved render with the
measured patches; (3) eyes, scars and marks at the Face framing and in the stage-1 Game view; (4)
cloth and the cape; (5) the hands - roar, stomp, buff and first person at rest, 0.10 beside the
candidate; (6) hair and cape in a head turn, four frames. Their answer: "approve" - P52 finishes;
"approve with notes" - data and parameters applied in about an hour, the checks of P52 run again,
anything larger goes to P56 (the catalogue II, which owns the look in Part B); "not yet" - one fix
lane, then the sheet again.

**B. After Gate B - play it, then approve it.** The Part B candidate on the private page with a
0.11 save and a 0.10 save ready to continue (so they see their own migrated giant); and **the
wardrobe sheet**: every slot's garments on the default giant; the twelve outfits; the fullest look
from four sides; armour in three metals; the accessories and beads; the new hair and beards; the
new designs by region in the Game view; the build sliders at their ends from behind; the face
sliders if built; the fourteen presets; the creator at 1280x720 on a slot grid. The same three
answers; larger notes go to P65 only if they concern the giant's garments reused by people, else to
`FOLLOWUPS.md`.

**C1. After the W36 merge - look early (not blocking).** A private preview of the W36 build and the
first **people sheet**: a soldier, an archer, a mage, a villager and an elder beside the giant at
the stage-1 and stage-4 game cameras and in first person; a formation of 40 at 30 m and at 80 m; a
rider; the rival giant and Harrok; Brannock's street; and the horse, the ogre, the troll and the
wolf as P61 and P63 made them, labelled "not in the game yet". Their notes steer P65, and their
word on the animals feeds the beasts' look gate.

**C. After Gate C - play it, then approve it.** The Part C candidate; the people sheet from the
gate's code, with the brutes, the bosses and the wolves in play, a held and a thrown soldier, a
battlefield after a fight (corpses), and each telegraphed attack in its wind-up frame. The same
three answers; the tag, the play link and the merge wait for it.

### 4.3 The releases

Each as M10 §4.3: the version (`0.11.0-m11`, `0.12.0-m12`, `0.13.0-m13`; `build_web.sh` reads the
suffix and applies 26, 32 or 44 MiB); the Linux export run headless and under Xvfb with `--skin`;
the Windows export built, not launched; the Web export built twice with the same bytes; the
Chromium checks on the release build; the launcher's notes and its download figure; then, only after
the owner's approval: the tag, the play link republished, the pull request to `main` and its merge.

### 4.4 The alternative: one release

If the owner prefers one release (question 1), nothing in §2 or the packages' designs changes. What
does: the three gates still run (a part's findings are cheapest to fix when the part is fresh) but
only the last produces a tag; checkpoints A and B stay as private previews with their sheets, and
their approvals become "go on"; P52 and P58 shrink to a documentation pass of about an hour each;
the version is `0.11.0-m11` and its budget rule is 44 MiB for `-m11`; Gate C repeats lenses 2, 4 and
6 over all three parts (about 6 more hours); players get nothing for about 16 days and then
everything at once, with a download that jumps from 36.5 MB to about 55 MB in one step. **The plan
recommends three releases**: each part is whole by itself, the owner asked to see each one, the
migration is safer shipped early and alone, and a problem in the scripted animals at the very end
cannot hold back the giant's motion that was finished two weeks earlier.

### 4.5 Owner tasks (NOT RUN here)

For each release: the look on their own screens, a real GPU and a real browser, with that part's
sheet beside it; ten minutes of play (Part A: every weapon family, a sprint, a stomp, first person;
Part B: dress a giant by slot at New Game, change it at a shrine, continue an older save; Part C: a
formation fight, a town, a wolf pack, a boss); frame times and first frames on real hardware, with
`creator_check.mjs --strict` and `people_check.mjs --strict`; a real gamepad in the creator's grids.
Still open from earlier handoffs: a licence for the project and its generated assets, the lossless
audio masters, and `build_giant.py --verify` on a second machine.

---

## 5. Risks and mitigations

| # | Risk | Mitigation |
| --- | --- | --- |
| 1 | **The scripted quadrupeds look poor** beside CC0-derived people: no free animal body exists in the pipeline's data, and a lofted, scripted wolf is the least proven thing in this plan | The horse first, a wave early, with the beast bar at the W35 merge; the owner sees the animals at C1 before they enter the game; a fur shell and the game camera's distance hide much; every animal scene keeps its box path behind the `body` key, so the look gate can ship people without them (§6.3); question 5 offers the owner an audited outside model instead |
| 2 | **"As good as the giant" is read literally.** A person is 60-130 px tall in most play; a 5,000-triangle, 512 px person will look right at that size and plain when held to the eye in first person | The note and C1 show people at the real sizes and in the hand; the highest LOD and the atlas go to what a held body shows (the head, the chest); the notable role gets the triangles first |
| 3 | **Computed animation reads as mechanical**, more so on dozens of people | Curves for weight shift and overlap in the clip generator; per-actor phase and speed offsets from the id; secondary motion on the giant; the owner told plainly (§0.5); a CC0 motion set is a later, separate decision |
| 4 | **The Web cannot afford 16 skinned people and a giant**: every number here comes from a software renderer and a single thread | Probe 7 before W29; the cap is data (`--people-cap`, the `low` preset); crowd and far levels carry formations; `people_check.mjs`; the people tier of P64 |
| 5 | **A probe fails** (parts on demand, the build push, spring bones, the face keys, per-instance data, shells) | Each has its fallback written in §1.2 and its package starts from the result; none blocks a wave |
| 6 | **Body regeneration breaks M10** (bakes, clips, tip matching, first-person caps) | The freeze test before any other work in P48; the 53 bones untouched; `--giant-full`; the full tiers and the tour at the W29 merge |
| 7 | **Garments intersect** once any slot can combine with any other | Shell offsets by slot, by construction; the tool's distance test over every overlapping pair in four poses; the stack check's 200 random looks; armour restricted to one over-layer |
| 8 | **The migration loses or alters a look** | The M10 function kept as an oracle; the matrix over every preset and option; lossless slot mapping checked against the six outfits; the cross-version run with real binaries; absent stays absent |
| 9 | **The download or memory grows faster than planned** (the per-triangle and per-atlas rates are derived, not measured) | P48's and P59's test exports measure the rates in the first wave of Parts A and C; shares fail the build; about 3.8 MiB of reserve under 44; the cut lists; the launcher decodes part by part; the page's peak memory is a budget |
| 10 | **Draw calls rise with slots and with people's shadows** | The giant's shadow proxy; one mesh a person; shadow draws of the body only; crowds one call per role, pose and level; the 250 budget measured in every part |
| 11 | **Determinism**: variation or promotion reads a shared random stream, or a presentation write leaks | Variation from the id's hash; the code rules extended; `test_people_determinism` with positive controls; baselines from the 0.10 tag |
| 12 | **Telegraphs get harder to read** on detailed bodies in dark armour | The readability suite's floor per attack; rings and fans untouched; flashes on crowd instances; faction palettes checked at 60 m |
| 13 | **Tests that name box meshes** break in numbers (the giant needed six suite rewrites; people are in far more suites) | Gameplay nodes and pivots keep their paths; P60 finds the suites by grep first and reports the count before it rewrites; `--people-far` and headless runs touch no model |
| 14 | **The default and slow tiers pass their caps** | Headroom moved three times, before each part adds; rendered grids in the gate tier; per-suite accounting; `--strict-times` |
| 15 | **Hair still disappoints up close** after the pass | Each change measured against M10's frames and the approved close-up; the sheet shows 0.10, the candidate and the render side by side; the limit is said in the note |
| 16 | **Provenance of the added CC0 targets** (women's macros) and of the scripted animals | The same audit against the same wheel, file by file; `PROVENANCE.md` separates CC0-derived from wholly own; no outside animal data unless the owner chooses it and it is audited |
| 17 | **Three gates and three approvals stretch the calendar** | Each gate is M10-sized or smaller; ship packages run beside the next part's first package; no package waits for an approval; §4.4 if the owner prefers one |
| 18 | **The scope against the owner's patience**: about 16 days | Said in the note; three releases put something in their hands about every five days; the cut lists are ordered |
| 19 | **A busy machine** | `nice -n 19`, Cycles at 2 threads, one export at a time, the shared bake cache, `--people-full` only when bake inputs change and at each gate |
| 20 | **Spring bones or shells stall or misbehave on real GPUs** | They are off in the `low` preset if the Web bench says so; the owner's tasks; both have a shader-only fallback already in the game (M10's sway, cards) |

---

## 6. Estimate, what fits, and the cut lists

Every number in this section is ASSUMED, calibrated on M10's record: its packages took 4-8 hours
each, its gate about a day with its fix lanes, and the whole milestone six calendar days against a
plan of three.

### 6.1 Per part

| Item | Agent-hours: central (range) |
| --- | --- |
| Before W29: the probes, the note | 4 (3-6) |
| Part A: P48 7, P49 6, P50 7, P51 7; two merges 2.5; Gate A 12; the sheet and preview 2; P52 3.5 | 47 (36-62) |
| Part B: P53 6.5, P54 7, P55 6.5, P56 6, P57 5; two merges and W31's 3.5; Gate B 12; the sheet 2; P58 3.5 | 52 (40-68) |
| Part C: P59 8, P60 8, P61 6.5, P62 7, P63 7, P64 7, P65 5; four merges 5; C1 2; Gate C 18; the sheet 2; P66 3.5 | 79 (60-105) |
| **Total** | **about 182 agent-hours (139-241)** |

### 6.2 Wall clock

Two lanes, so a wave lasts as long as its longer package plus its merge: ten waves of about 7.5 hours
are 75 hours; the gates about 7, 7 and 11 hours of wall clock; the sheets and previews 4: **about
105 hours of work at full speed**. At M10's real pace - about 6.5 working hours of progress a
calendar day once merges, re-runs on a busy machine and the owner's turnarounds are counted - that is
**15-17 calendar days**: Part A about 4.5 days to its release, Part B about 5, Part C about 7. At
best 12 days (a quiet machine, every probe passing, answers within hours); 21 with the likely
overruns (the quadrupeds, the suite rewrites for people, a gate that finds as much as M8's did).
The owner is told the central figure and that the first release arrives in about five days.

### 6.3 What fits, and the cut lists

**Never cut**: gameplay unchanged with its positive controls; the save migration and its oracle;
provenance and bit-exact regeneration; the Web budgets and checks; the freeze test; the owner's
checkpoints. Per part: A - the grip through the fist, the stomp, sprint, turns, the hair's shading
and the skin's tone; B - slots, the migration, the creator's grids, at least the first ten new
garments; C - soldiers and formations, the caps, corpses and held bodies, the readability suite.

**Part A's cut list**, first to go first: (1) the growth tween; (2) a material pass on the player's
weapons (only if asked); (3) foot placement on slopes; (4) the head look; (5) lashes and fuller
brows; (6) flinches from four sides (one flinch stays); (7) loose strands at the hairline; (8) shells
(the crop keeps denser cards); (9) braids as geometry; (10) the preview's higher resolution on the
Web.

**Part B's cut list**: (1) per-slot dye overrides (the three dyes stay); (2) face sliders; (3) the
keyboard's filter box (pages and the material filter stay); (4) accessories and beads; (5) presets
13-14, outfits 11-12; (6) content in this order - scars 9-10, war paints 7-8, tattoos 23-28, the
fourth and fifth new hair styles, the third and fourth new beards, then garments from the end of
P54's list (bone spaulders, the horned helm, the scale coat, the bronze breastplate, wrapped
sandals, the sash, the chest wrap, arm wraps); (7) thumbnails on the Web; (8) the build sliders.

**Part C's cut list**: (1) the dire wolf and the wolf (their box rigs stay); (2) the horse (the box
horse stays under a realistic rider, or the rider's box too if that reads worse - the look gate
decides); (3) the Troll Matriarch's and the Ogre King's gear (their kind's body at their height);
(4) the troll whelp's own face; (5) variants from the end of the roles table (notable 5 to 3, then
villagers 5 to 3, then the second archer, mage, crew and rider); (6) women among the villagers, if
the audit of the added targets fails; (7) the `corpse` crowd pose (corpses then keep a far mesh);
(8) the loners' shared renderer; (9) trolls and ogres (their box rigs stay) - last, because the
owner named them.

---

## 7. Verification log

What this plan ran or read, and what it did not.

- **Read in full**: `docs/plans/M10_PLAN.md` (structure, contracts and conventions),
  `docs/M10_HANDOFF.md`, the M10 sections of `docs/plans/FOLLOWUPS.md` (from "From P41" to "From the
  0.10.0-m10 release"), `docs/ARCHITECTURE.md` §23, the "Budgets" table of `docs/PERFORMANCE.md`.
- **Read in the code at `5ff50f0`** (each fact marked VERIFIED, code): `tools/build_web.sh` (the
  budget rule, the part cap, the giant's share), `web/launcher.html` (the parts are joined before
  unpacking), `assets/giant/manifest.json` (25 meshes and their triangles, ten garments, the
  landmarks, 13 files), `tools/giant/mpfb2/` (133 files; male macro targets only; no animal),
  `tools/giant/kit/` (the modules and their sizes), `assets/shaders/giant_skin.gdshader` (its
  uniforms, `light()`, `COLOR.r` only), `scripts/presentation/` (`actor_rig`, `skinned_rig`,
  `pose_brain_modifier`, `giant_model`, `giant_look`, `crowd_renderer`, `quadruped_rig`, `rig_paint`),
  `scripts/progression/appearance.gd` (`migrate`, the future-version rule),
  `data/appearance/set_outfit.json` (six outfits; no two garments of one planned slot),
  `data/enemies/` and `data/npcs/` (20 and 9 records, their scenes and heights),
  `tools/builders/` (which builder makes which scene and on which rig), `tools/check.sh` (its
  options), the names and tiers of every existing test this plan extends.
- **Derived here**: the pack budget from the release's bytes; the bytes per 1,000 triangles; the
  on-screen sizes of people; every planned share.
- **Not run**: no probe, no export, no render and no test was run for this plan beyond
  `test_ship_docs` on this file. Every "ASSUMED" above is waiting for the probes of §1.2 or for the
  first package that measures it; their results are recorded here, under this line, before W29.


### The probes before W29 (§1.2): results

Probes 1 and 2 ran in P48's lane and probe 9 in P49's, each before the package built on it (their full
records: `docs/systems/P48.md` and `docs/systems/P49.md`, "Probes"); probes 3-8 and 10 were run by the
orchestrator before W29 in scratch projects outside the repository. Reference toolchain throughout:
Godot 4.6.3, the Compatibility renderer; Blender through the project's `tools/giant/` venv; a 4-CPU
machine shared with other work and with no GPU: native runs on llvmpipe (desktop GL 4.5) under a
virtual display, Web runs a test export (the Web preset) in headless Chromium (WebGL 2 on
SwiftShader). Every timing run started when the 1-minute load was below 3, or after waiting 100 s
(the load is recorded where it was higher). Frame timings on these software devices are indicative
only and are given as ratios with and without the feature, measured in alternating blocks; CPU-side
timings (probes 4 and 7) are real for this machine.

| # | Decides | Verdict | Decision |
| --- | --- | --- | --- |
| 1 | Meshes on demand (P48) | works | `giant.glb` and `parts/<id>.glb`, bound by the named skin; every part's skin equals `giant.glb`'s bind for bind, so the model binds every part with its own one `Skin` |
| 2 | Build sliders (decision 7) | works | Build sliders by vertex shader (`COLOR.g`, `.b`); no build shape keys; the shadow proxy carries the build channels too |
| 3 | Face sliders (decision 7; P56) | works | Face keys built; exported with morph tangents (`export_tangents` and `export_morph_tangent` on) |
| 4 | Secondary motion (P50) | works | `SpringBoneSimulator3D` as planned; `reset()` on teleports, respawns and look changes; colliders only where reachable |
| 5 | The subsurface term (P51) | works | The 64 px lookup in `light()`, `light_model` 3 on both tiers |
| 6 | Shells (P51, P63) | works with limits | Shells never cast shadows; 12 layers on desktop, 6 on the Web, built at load time |
| 7 | The people's clip driver (P60) | works | One `AnimationPlayer` per actor, `seek(phase, false)` + `advance(dt)`, fades by `play(clip, 0.15)` |
| 8 | Crowd variation and flashes (P60) | works | One `MultiMesh` per role, pose and level; palette row and flash in custom data |
| 9 | The launcher's change (P49) | works | One stream, a network chunk at a time, into one `DecompressionStream` |
| 10 | The people's share (§2.12) | works with limits | A variant ships at about 282 KB (275 KiB), not 165 KiB: 19 variants, or lighter variants of about 3,000 triangles; P59's first variant decides |

**Probe 1 - a hair mesh in its own glTF, loaded at run time and bound by named skin (P48).** In a
scratch Godot project on the files the real pipeline wrote (`giant.glb` with the 71-bone skeleton, the
body, the eyes and the shadow proxy; the parts `Hair_long_back.glb`, `Garment_tunic_core.glb` and
`Garment_tunic_limbs.glb`, each with `build_giant.py`'s import settings), the hair's glTF was loaded,
instanced, and its `Mesh` and `Skin` put on a new `MeshInstance3D` under `giant.glb`'s `Skeleton3D`.
Frames of the body alone, with the hair, with the head turned 35 degrees, with `hair_01`-`03` bent 30
degrees each, and from 60 m. Seen: the part's skin has 71 binds, all named (`use_named_skins`); the hair
drew (318 pixels at 640x480 from the front), followed the turned head (332 pixels moved) and its tips
followed the bent chain (391 pixels moved, the roots stayed); the imported meshes have their LODs (2 for
the hair, 9 for the head, 5 for the tunic's core, 8 for the proxy) and still drew at 60 m; a part's read
and bind took 1.1-2.1 ms. `ArrayMesh.shadow_mesh` is empty on every skinned mesh, the body's included,
although `create_shadow_meshes` is on, so there is none to lose. **Verdict: works. Decision:** meshes on
demand as planned; no fallback. Every part's skin turned out equal to `giant.glb`'s bind for bind (the
same armature is exported with each), so the model binds every part with its own one `Skin`.

**Probe 2 - build sliders by vertex shader (decision 7).** A spatial shader with
`VERTEX += NORMAL * dot(COLOR.gb * 2.0 - 1.0, build) * build_max_m` on the three body meshes and both
tunic parts, under a shadowed sun over a ground plane (the proxy hidden, so the pushed meshes cast);
frames at `build` = (0,0), (1,0), (-1,0), (0,1), (0,-1), (1,1), and (0,0) against (1,1) from 60 m. Seen:
the silhouette changed with each slider (1,261-1,816 pixels of the body's box at one slider's end, 2,788
with both at +1); the tunic stayed over the skin (it carries the skin's weights); the shadow followed the
vertex shader (the ground's shadow 605 pixels at rest, 743 with both at +1, 541 with girth at -1); the
LODs followed (41 pixels changed on a figure about 25 pixels tall); the mesh format keeps `COLOR` on the
body, the hair and the garments. **Verdict: works. Decision:** build sliders by vertex shader as planned;
no build shape keys. Consequence: the shadow proxy carries the build channels too and needs the same push
when P53 adds the uniforms (FOLLOWUPS, "From the body pipeline II").

**Probe 3 - the dark patch between the brows (face keys; P56).** `Body_Head` of the shipped `giant.glb`
(4,570 vertices) with four vendored detail targets as shape keys (nose volume, chin prominence, brows
forward, head age), exported from Blender three ways - positions only; positions and morph normals (the
exporter's default); positions, morph normals and morph tangents - each imported with `ensure_tangents`
off and on and with compression forced off and not (12 imports), every key at +1 and -1 rendered at the
Face framing and differenced against the same shape applied to the base mesh (a "patch": the 9 x 9 px
mean of the luminance difference, in 1/255):

| Export | `ensure_tangents` | Darkest patch (1/255) | Where |
| --- | --- | --- | --- |
| positions only | off / on | -39.0 / -38.9 | brows at -1 (normals not morphed) |
| positions + morph normals | off | -22.1 | brows at -1 |
| positions + morph normals | **on (the shipped setting)** | **-89.2** | **brows at +1: a hard dark quad between the brows** |
| positions + morph normals + morph tangents | off / on | -22.0 / -22.0 | brows at -1 |

The cause is the pair "morph normals without morph tangents" imported with `ensure_tangents` on; with
the morph tangents exported it is gone. Compression changed nothing. The remaining -22/255 is a soft,
wide band under both brows at weight -1 only (the linear blend of normals at a negative weight). Size: a
head with four keys imports to 550 KB against 210 KB (about 85 KB a key). **Verdict: works. Decision for
P56:** build the face keys and export them with `export_tangents=True` and `export_morph_tangent=True`
(today `export_game.py` exports with morphs and tangents off, and `giant.glb.import` has
`ensure_tangents=true`: morphs with the exporter's defaults give exactly the failing pair); keep P56's
dark-patch test (local contrast 8/255) and judge the negative-weight band against it - if it fails, clamp
the brow key to 0..+1. The 0.7 MiB row for six face keys is about right for the head alone; the copies on
the beards and the hairline strips come on top.

**Probe 4 - `SpringBoneSimulator3D` (secondary motion; P50).** The shipped giant with leaf chains added
at run time (three under `head`, four 3-bone cape chains under `spine_03`) on card ribbons, a stand-in
for `PoseBrainModifier` before the springs, a sphere and capsules as colliders (head, chest), through a
scripted course (idle, run, abrupt stop, a 70-degree head turn, a spin, a heavy swing, a teleport without
and with `reset()`) at 60 and 20 frames a second. Cost a giant a frame: natively 0.043-0.046 ms springs
off, 0.075-0.082 with colliders, 0.055 without (+0.031-0.037, the colliders about 0.025 of it); on the
Web 0.056-0.065 off, 0.086-0.096 on (+0.030). No NaN; tips deflect up to 47 degrees (cape) and 61-64
(hair) on the run; with colliders a joint enters the chest capsule by at most 0.05 m (0.13 without).
Settle with the clip frozen, to within 2 degrees: 0.40 s after a stop from a run, 0.07 after the head
turn, 0.47 after the spin, 0.33 after the swing; at 20 fps the same look within 8 degrees. A teleport
without `reset()` throws every chain to 90-95 degrees; with `reset()` the first frame is at rest.
**Verdict: works**, inside §2.12's 0.12 / 0.45 ms. **Decision for P50:** the plan's design -
`SpringBoneSimulator3D` for the hair and cape chains, `reset()` on every teleport, respawn and look
change (a test shows the reset), colliders for the head and chest only where a chain can reach them.
**Cape tuning notes:** the probe's values (cape stiffness 0.6, drag 0.45; hair 1.2, 0.35) settled best;
more drag makes this solver slower to settle, not faster (drag x2.5: 1.38 s after the stop, 1.57 after
the spin), so lift the cape less on the run with more gravity, not more drag; the cape lifts to about
45-50 degrees on the run (a flag in wind rather than heavy cloth) and reads as a stiff board, because the
four chains have no cross links - a cross-chain constraint or a cloth-like card layout if that matters.

**Probe 5 - a 64 px lookup sampled in `light()` (the subsurface term; P51).** The shipped head, torso and
limbs with a copy of `giant_skin.gdshader` whose `light()` switches between Lambert, today's wrap, a
64 x 64 lookup (N.L against curvature, pre-integrated from a six-Gaussian skin profile) and an analytic
wrap by curvature; rendered natively and in a Web test export. The lookup is sampled in `light()` on both
tiers (a debug lookup proves it; the images agree within 0.002); frame time with the lookup against the
wrap 1.045 natively and 1.016 on the Web at the face (0.93 and 1.02 at the body: noise); the analytic
model costs the same. The lookup gives the reddish terminator band and keeps the lit side near Lambert's
colour. **Verdict: works. Decision for P51:** the 64 px lookup in `light()`, `light_model` 3 on both
tiers; the analytic model stays a tuning comparison, not a fallback.

**Probe 6 - twelve shell layers (short hair and fur; P51, P63).** A 4,364-triangle scalp cap cut from the
shipped head (skinned to it) and a 4,000-triangle animal body, each with 1, 6 and 12 shells in one mesh
and one `ShaderMaterial` (pushed along the normal, discarded by a strand noise), five views at 640x360,
natively and on the Web. The shells are one draw call a style (plus one a shadow cascade while they cast:
at the game camera's four cascades the scalp's primitives went from 53,270 to 315,110 with shadows, to
105,638 without). The frame with 6 / 12 layers against none at the game distance: natively 1.20 / 1.64
(scalp, no shadows), 1.39 / 1.90 (animal); on the Web 1.12 / 1.32 and 1.19 / 1.39; up to 2.2-2.5 close
up. Twelve layers read as a dense short crop and a coat; six show the scalp at the crown and banding on
the animal; one is not usable. **Verdict: works with limits. Decision for P51 and P63:** shells never cast
shadows (the cap or the body casts); **12 layers on the desktop tier and 6 on the Web**, the stack built
at load time from the cap's or the body's arrays (no shipped bytes for the layers); P63's wolf coat the
same. Measure again on a GPU at the first package's frame check; drop to cards on the Web if the Web's
`low` frame grows by more than 10 % with the shells in view.

**Probe 7 - one `AnimationPlayer` per actor, seeked by hand, with a cross-fade (P60).** 16 actors of 23
bones, each with its own player in manual mode on one library of three clips. `seek(t, true)` gives the
pose at t (worst 0.0007 rad); `seek(t, false)` then `advance(dt)` the pose at t + dt; a cross-fade by
`play(clip, 0.15)` while seeking by hand lands exactly on the hand-driven phase (worst 3 degrees at the
fade's first frame); `seek(t, true)` alone does not move a fade. Cost for 16 actors, best / median ms a
frame: player advanced 0.107 / 0.110 natively and 0.138-0.149 / 0.143-0.160 on the Web; seeked by hand
0.112 / 0.116 and 0.149-0.164 / 0.161-0.168; with a fade always running 0.222 / 0.228 and
0.258-0.261 / 0.270-0.283; an `AnimationTree` 15-70 % more. **Verdict: works. Decision for P60:** one
`AnimationPlayer` per promoted actor in manual mode, `seek(phase, false)` then `advance(dt)` every frame
(never `seek(t, true)` alone), fades by `play(clip, 0.15)`; the cap of 16 stands; a test asserts a fade
completes in its time and lands on the hand-driven phase.

**Probe 8 - a `MultiMesh` with per-instance colour and custom data (P60).** 40 members in one `MultiMesh`
with `use_colors` and `use_custom_data`, a `ShaderMaterial` reading the palette row (`INSTANCE_CUSTOM.x`,
an 8 x 4 palette texture, nearest filtering), the flash (`INSTANCE_CUSTOM.y`) and a tint (`COLOR`), read
back inside the engine through an unshaded variant: 80 of 80 pixel checks right on desktop GL and on
WebGL 2 (worst error 0.016), 0 wrong of 480 with new custom data every frame, 80 of 80 with the whole
buffer in one write; setting the data for 40 members 0.003 ms natively and 0.011 on the Web. (The first
runs' failures were the check's expectation computed in the wrong colour space.) **Verdict: works.
Decision for P60:** one `MultiMesh` per role, pose and level, the palette row and the flash in custom
data and a tint in the instance colour; compute the flash in the albedo's space, and read the frame back
with an unshaded check variant in P60's test.

**Probe 9 - the launcher unpacking a 44 MiB pack in four parts (P49).** A 50,560,000-byte stand-in pack
gzipped and base64-encoded to 44.02 MiB and cut into four parts; three unpackers run in headless Chromium,
three fresh browsers each, the renderer's resident memory read every 20 ms, every output's checksum
matched:

| Unpacker | Peak | Rise | Time |
| --- | --- | --- | --- |
| The joined text (0.10.0-m10) | 407-418 MB | 329-342 MB | 485-527 ms |
| A part at a time | 373-388 MB | 296-311 MB | 504-568 ms |
| **One stream, a network chunk at a time** | **292-303 MB** | **214-225 MB** | **396-399 ms** |

About 100 MB of each rise is the unpacked pack and the buffer it is read into. **Verdict: works**, far
from the 1.4 GB row, so the fallback is not taken. **Decision:** one stream, not a part at a time: each
network chunk decoded as it arrives (the one to three characters past a group of four carried over) and
written into one `DecompressionStream` whose readable side is the response's body; it holds 110-120 MB
less than the join at the last budget and was the fastest.

**Probe 10 - the people's bytes (§2.12).** Four clothed people of 5,000 triangles (6,590 vertices, 23
bones) made from the shipped giant's body, garments and hair, and three atlas sets (albedo 512 px, normal
and the third map 256 px), exported for the Web with the giant's import settings five times with more and
fewer of them (shipped bytes as `build_web.sh` counts them): one variant adds 282,536 bytes, three more
281,976 each; one atlas set 240,384, two more 245,686 each. A variant imports to 192-245 KB and ships at
255-323 KB (mesh data barely compresses; LODs 10 KB of it, shadow meshes nothing measurable). So **a
variant costs about 282 KB (275 KiB) shipped against the 165 KiB planned** (1.7 times) and an atlas set
about 240 KiB against 205; at the plan's counts Part C's people lines come to about 13.0 MiB against 10.2,
over the 12.0 share. **Verdict: works with limits. Decision for §2.12 and P59:** the fallback - fewer
variants per role in §6.3's order (notables 5 to 3, villagers 5 to 3, then the second archer, mage, crew
and rider): **19 variants** bring the lines to about 11.9 MiB with the 0.4 margin; or keep 23 with
**lighter meshes** (about 3,000 triangles and few UV seams: about 43 shipped bytes a vertex). **P59's first
variant decides.** Do not count on dropping LODs or shadow meshes.

**What the probes did not measure**: no timing on a real GPU (the shells' cost is the one decision this
leaves open; P51 re-measures at its first frame check); probe 4 did not see the real cape and hair meshes
P48 exports, nor more than one giant a frame on the Web; probe 3 keyed only `Body_Head` (not the beards
or the hairline strips); probe 6 not at 1280x720 or with anti-aliasing, nor the stack's build time;
probe 7 not the skin's cost of 16 people of 5,000 triangles (P60's formation measurement); probe 10 not
how a person looks at the game camera, nor a 3,000-triangle variant's bytes.
