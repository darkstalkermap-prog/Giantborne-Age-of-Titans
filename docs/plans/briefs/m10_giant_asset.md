# M10 brief: the game-ready realistic giant (asset pipeline, customisation shaders, budgets)

Research run of 2026-11-12 on HEAD 1c33b8e (the integration branch), Godot 4.6.3
(Compatibility renderer, Mesa llvmpipe under Xvfb at 1280x720), bpy 5.3.0 in the giant kit's venv.
Every fact is marked **VERIFIED** (I ran it, numbers from logs) or **ASSUMED** (reasoned, not run).
Nothing in the repository or in the worktrees was changed (one measurement script imported
`tools/pck_files.py` from the main checkout and left a `tools/__pycache__/` there for a few minutes;
I deleted it, `git status` is empty again); Godot ran in the scratch worktree `/tmp/m10-asset`
(removed at the end), and every output is under
`<scratchpad>/m10_plan/giant_asset/`
(below: `GA/`).

Contact sheet of the test frames: `GA/giant_asset_contact.png` (frames in `GA/frames/run1/`,
`GA/frames2/`).

---

## 0. Answers in one page

1. **The kit's giant becomes a normal skinned glTF that Godot 4.6.3 imports and draws in the
   Compatibility renderer, with automatic LODs** (VERIFIED). Body = the unsubdivided CC0 hm08 mesh:
   13,380 vertices / 26,756 triangles in Blender, 14,517 vertices after the UV-seam split in Godot;
   skeleton = MPFB2 "game_engine" (53 bones, CC0 weights, 4 influences per vertex); clothing =
   seven separate skinned meshes on the same skeleton; eyes = two 560-triangle spheres.
2. **Customisation without per-player painting works at runtime in one ShaderMaterial** (VERIFIED,
   frames 3, 4, 8): skin tone as a ratio to the bake tone, stubble/scalp/brows tinted by the hair
   colour, four tattoo/war-paint designs per RGBA mask (ink multiply or paint over, colour per
   design), four scar sets per RGBA mask (paler, glossier, relief from the mask gradient), eye
   colour drawn procedurally, clothing dye by parameter, body regions under clothing sunk by a
   bitmask. The same giant instance switched between two looks between two frames.
3. **Hair and beards: alpha-tested or depth-pre-pass-blended cards generated from the kit's strand
   growth** (VERIFIED in Godot). Long hair 310 cards / 5,580 tris, crop 200 / 1,600, full beard 240 /
   3,360, short beard 160 / 1,280; one draw call each. **Alpha to coverage does nothing in this
   renderer** (VERIFIED: pixel-identical with MSAA off/2x/4x), so use the depth-pre-pass blended
   variant (softest edges, works without MSAA, i.e. on the Web). The look is "good game hair cards",
   not the strand renders; the crop style needs more work (patchy).
4. **Skin without SSS: per-channel wrap lighting + a back-light transmission term driven by a baked
   thickness map** (VERIFIED, frames 1-2). Recommended light model 2 of `giant_skin.gdshader`.
5. **Budgets** (VERIFIED from one Web test export, measured as build_web.sh measures: gzip -9 +
   base64): the game at this HEAD ships **17,399,456 bytes = 16.59 MB** (build_web.sh's MB =
   MiB). The full render set adds **+4.04 MB**, a web-lean set **+2.52 MB**, the smallest set
   **+2.16 MB**; meshes alone are **+1.76 MB** (they dominate). Draw calls at the Web preset: 3
   (body + eyes) to 11 (full warrior outfit + hair + beard); the box giant has 8.
6. **The 23 MB budget holds the giant plus a modest creator** (about 6 hair styles, 5 beards, 16
   tattoo designs, 4 scar sets, ~12 garments) at about 21 MB, but leaves little for the rest of M10
   and later character upgrades. **Ask the owner** to raise the Web budget to 26 MB (one more 15 MB
   part is not needed until ~30 MB), or accept 512 px normal/roughness maps on the Web.
7. **Pipeline**: `tools/giant/*.py` under a pinned bpy venv regenerate the glTFs, the hair atlas
   **and the Cycles bakes bit-exactly** run to run (VERIFIED twice each, same machine); Godot's
   re-import is bit-exact for textures but not for `.scn` (random ids), so verify sources. CC0
   input: vendor a 136-file MPFB2 subset (9.96 MB raw, ~4.5 MB compressed in git) under
   `tools/giant/mpfb2/`.

---

## 1. What I built (all scratch, reproducible)

| Script (in `GA/scripts/`) | Does | Time (niced, 2 threads, busy box) |
|---|---|---|
| `export_game_giant.py [-- --morphs --out=NAME]` | builds the kit giant at 3.6576 m (stage 1) with the game_engine rig, strips render modifiers, derives 5 garments from the body surface, adds braies + belt (kit), low-poly eyes, region ids in COLOR_0, exports `out/giant_parts.glb` + stats | 1.1 s |
| `bake_body.py -- SIZE AO_SPP [passes]` | Cycles selected-to-active bake from the kit's procedural skin (subdiv 2) onto the hm08 UVs: albedo (neutral tone, no scars, no beard shadow, no scalp tint), tangent normal, roughness, AO, thickness (inside AO), masks, scars, rest position + rest normal EXRs | 1024 px, AO 24 spp: 793 s (AO 535 s) |
| `tattoo_masks.py -- BAKEDIR` | four tattoo / war-paint designs drawn as distance fields in 3D on the rest pose from the position/normal EXRs (seam-free) into `tattoo.png` | ~10 s |
| `pack_textures.py BAKEDIR OUTDIR [size]` | packs albedo, normal, ORM (AO, rough, thickness), masks RGBA, scars RGBA, tattoo RGBA | 2 s |
| `hair_cards.py` | grows guide strands with the kit's growth code on the scalp/beard masks, turns each guide into a card (ribbon tangent to the head, two layers, head-normal shading), writes `out/giant_hair.glb` (4 styles) + `out/hair_atlas.png` (512² RGBA strands) | 3 s |
| `pck_growth.py PCK` | shipped-size growth of asset sets from one test export | 30 s |
| `vendor_subset.py` | size of the minimal CC0 subset | 1 s |

`GA/kit_snapshot/` is a frozen copy of the kit scripts (the render workflow kept editing
`mh_data.py` during this run: 123 vs 122 targets between two builds), with two switches added to
`giant_skin.py` (`beard_shadow`, `scalp_tint`) so the bake leaves those to the shader.

Godot side (copied to `GA/godot_lab/`): `shaders/giant_skin.gdshader`, `giant_hair.gdshader`
(alpha test + dither), `giant_hair_blend.gdshader` (depth pre-pass blend), `giant_hair_a2c.gdshader`
(no effect, see §3), `giant_eye.gdshader`, `giant_cloth.gdshader`; `tools/render_tests.gd` (the
harness: assembles a giant from the two glTFs, grafts the hair meshes onto the body skeleton,
poses, renders, measures), `inspect_glb.gd`, `msaa_test.gd`, `classes.gd`.

---

## 2. Export (task 1)

### 2.1 Body and skeleton — VERIFIED
- Source: the kit's `BodyData` (122 MakeHuman targets: macros + regional modifiers) at human scale,
  scaled to 3.6576 m (x1.4947). The game scales `Visual/Body` by k = height / 3.6576 per stage, so
  this size drops in unchanged; shaders are scale-free (the hide shrink is in model space and
  scales with k).
- **Rig: MPFB2 `rig.game_engine.json` + `weights.game_engine.json`, 53 bones** (pelvis, spine_01-03,
  neck_01, head, clavicle/upperarm/lowerarm/hand, 3 joints x 5 fingers, thigh/calf/foot/ball; no
  face or eye bones). Weights are CC0 (`"license": "CC0"` in the file). Max 6 influences per
  vertex in the source (11 vertices have 6, 597 have 5); the glTF exporter keeps the 4 strongest
  (`export_influence_nb=4`); Godot imports 4 (no 8-weight flag).
- Bone names mirror the common engine mannequin, so Godot 4.6's `TwoBoneIK3D` / `LookAtModifier3D`
  / `AimModifier3D` / `SpringBoneSimulator3D` (all present in 4.6.3, VERIFIED by ClassDB) can drive
  the arm aim the ActorRig computes today (hand on the exact AttackGeometry arc).
- **Orientation: the glTF faces +Z in Godot; the game's actors face -Z** → the builder rotates the
  model 180° about Y under `Visual/Body` (VERIFIED in the frames: front shots needed the camera on +Z).
- Poses: `Skeleton3D.set_bone_pose_rotation` only takes effect once the skeleton is inside the tree
  (VERIFIED: set before `add_child`, the global pose stayed at rest; set after, the elbow moved).
- Body counts in Godot (VERIFIED, `inspect_glb.gd`): 14,517 vertices, 26,756 triangles; vertex
  stream 20 B/vertex, attributes (UV + COLOR) 12 B, skin 16 B = **48 B/vertex; the importer does
  not compress skinned meshes** (format flag clear; `force_disable_compression=false`).

### 2.2 LODs — VERIFIED
Godot's importer (`meshes/generate_lods=true`, default) makes the LODs itself, also for skinned
meshes, and **the Compatibility renderer uses them**. Body chain: 26,756 → 13,378 → 6,688 → 3,344 →
1,672 → 836 → … (11 levels). Giant alone (warrior outfit + long hair + full beard), Web preset,
primitives in frame by camera distance: 4 m 49,594; 8 m 33,416; 15 m 17,830; 30 m 11,592; 60 m
8,718; 120 m 3,352; 240 m 2,722. LODs cost +0.25 MB shipped for the parts file (1.35 vs 1.11 MB);
keep them. No hand-made LODs are needed for the player; rival giants could reuse the same body
(ASSUMED).

### 2.3 Clothing as separate skinned meshes — VERIFIED (shapes are first-pass)
Garments are cut from the body surface by bone-weight regions, pushed out along the normals, with
the body's UVs and the body's weights copied per vertex (so they skin exactly like the skin under
them); braies + belt come from the kit (MakeHuman's "tights" helper).

| Mesh | Godot verts | Tris | Note |
|---|---|---|---|
| Giant_body | 14,517 | 26,756 | region id per vertex in COLOR_0.r |
| Giant_eye_L / _R | 315 each | 560 each | pole = gaze; iris drawn in the shader |
| Giant_braies | 551 | 964 | kit garment (no subdivision, no solidify) |
| Giant_belt | 384 | 768 | kit belt, solidified |
| Giant_tunic | 2,300 | 4,272 | torso, short sleeves, skirt to mid-thigh |
| Giant_jerkin | 1,256 | 2,278 | sleeveless leather |
| Giant_bracers | 252 | 400 | forearms |
| Giant_boots | 2,700 | 4,688 | feet + lower shins (dense toes: decimate) |
| Giant_furs | 810 | 1,352 | shoulder mantle, ragged hem |
| **giant_parts.glb** | 23,425 | 42,598 | 1,610,092 B glTF; 1,073,373 B imported |

- Swapping = `visible` per MeshInstance3D (hidden meshes cost no draw call). Covered body regions
  are sunk 3 cm by `hidden_regions` (bit per region id) so skin never pokes through
  (VERIFIED for torso/pelvis/feet under the warrior outfit in the relaxed test pose; under
  animation ASSUMED, to be tested with the rig driver). Region ids: 0 head, 1 neck,
  2 torso_upper, 3 torso_lower, 4 pelvis, 5 upperarm, 6 forearm, 7 hand, 8 thigh, 9 knee, 10 shin,
  11 foot.
- The weave in `giant_cloth.gdshader` (procedural `sin` on the UVs) moirés at distance (frame
  `world_front`); M10 should use a small tileable weave/leather detail texture with mips
  (ASSUMED ~20-40 KB shipped each) and keep the dye as a parameter.
- Cross-file skins work: the hair glTF carries its own armature; its meshes were re-parented under
  the body's `Skeleton3D` and bound by bone name (VERIFIED by the renders). So one glTF per category
  (body, garments, hair, beards) is fine as long as all are exported from the same rest skeleton.

### 2.4 First person — ASSUMED (not built)
One skinned body cannot be split by render layer. Proposal: hair, beard, eyes and the torso
garments on layer 2 (the game's `first_person_hidden`); the body shader gets `fp_hidden_regions`
that discards head/neck/torso fragments in first person (back-face culling already hides the head
from inside).

### 2.5 Shape keys — VERIFIED cost
Four MakeHuman targets exported as glTF shape keys add only 41 KB to the glTF (sparse) but
**+1.42 MB shipped in Godot (≈0.34 MB per key: blend shapes are stored dense per vertex)**. Face or
build sliders therefore belong on a separate head mesh (~3k vertices, ASSUMED ~0.07 MB per key) or
are skipped for M10.

---

## 3. Hair and beards (task 3)

### 3.1 How the cards are made — VERIFIED
`hair_cards.py` reuses the kit (`giant_hair.grow`, the comb flow fields, the scalp/beard masks,
collision against the skin) for a few hundred guides, on the **unsubdivided** surface (on the
subdivided one, cards sat inside the game mesh's skull). Each guide → a ribbon: side =
normal × tangent (lies on the head), width tapering to 45 %, slightly curled towards the head,
UV u = one of 4 atlas columns, v root→tip, normals = the head normal under the card. Two layers
(inner wide/dark, outer long/wispy). All vertices 100 % on `head`. The atlas is drawn in numpy
(512² RGBA: coverage, brightness, strand id for grey strands, root→tip). Colour, sun-bleached tips,
grey fraction and a Kajiya-Kay highlight are shader parameters, so one atlas serves every colour.

| Style | Cards | Tris | Draw calls |
|---|---|---|---|
| Long hair | 310 | 5,580 | 1 |
| Crop | 200 | 1,600 | 1 |
| Full beard | 240 | 3,360 | 1 |
| Short beard | 160 | 1,280 | 1 |
| giant_hair.glb (4 styles + armature) | | 11,820 | 801,672 B glTF, 328,726 B imported |

### 3.2 What renders well here — VERIFIED (frames 5, 8, `frames2/hair_back_medium.png`)
- **Alpha to coverage: no effect in Godot 4.6.3 Compatibility** (a quad with
  `ALPHA_ANTIALIASING_EDGE`: 0 changed pixels with MSAA off/2x/4x, while opaque edges changed on 901
  pixels). Do not plan on it, on desktop or Web (llvmpipe; ASSUMED the same on GPUs since the GL
  state is the engine's).
- Plain alpha test reads as stacked "shingles" with stair-stepped ends; a screen-space dither of
  the cut softens a little; **`depth_prepass_alpha` blending gives the softest result** (opaque
  core writes depth, fringe blends; +2 render-list objects, same draw calls in the counter).
  Recommended for both presets (the Web preset has no MSAA anyway).
- The skin under the cards must take the hair colour: `scalp_tint` and `beard_tint` (masks G and R)
  made the full beard solid and hid most scalp gaps (frame 8). From behind, long hair reads well;
  the front hairline is high (like the kit renders); the grey crop is patchy and needs ~2x cards or
  a painted scalp-hair pass.
- Mip-aware alpha boost keeps cards from thinning far away (derivative-based, no custom mips).
- Optional later: `SpringBoneSimulator3D` (present in 4.6.3) on 2-3 extra hair/beard bones for sway
  (ASSUMED).

### 3.3 Shell / mesh hair — ASSUMED (not built)
A cheap opaque "cap" under the cards (offset scalp, hair-coloured) adds volume for 300-800 tris;
the `scalp_tint` mask already does most of it at game distances, so cards + tint is the plan;
shells are worth it only for very short hair and fur trims.

---

## 4. Textures and customisation (task 2)

### 4.1 Bake set (1024², Cycles, from the kit's procedural skin) — VERIFIED
`albedo.png` (neutral tone 0.69/0.53/0.44 sRGB), `normal.png` (OpenGL, subdivision smoothing +
wrinkles/veins/knuckles; pores are sub-texel at 1024), `orm.png` (R AO 24 spp, G roughness, B inside
AO = thickness), `masks.png` (R beard/stubble area, G scalp, B brows, A lips), `scars.png` (R face
scars, G forearm slash, B chest claws, A knuckle nick), `tattoo.png` (R braided left-arm bands,
G chest triple spiral, B face war paint, A forearm chevrons), plus `restpos.exr` / `restnrm.exr`
(texel → rest position / normal) for any future decal generator. The bake builds the kit body with
its default rig (so the kit's region masks are the renders' masks); the export uses the game_engine
rig on the same mesh and UVs, so the textures fit unchanged. The hm08 UVs are one 0-1 atlas
(head island ≈ 28 % of the area: a face ≈ 300 px wide at 1024). Known flaw: a few normal-map
specks at the nails and 4 torso points (selected-to-active rays; tune cage per region).

### 4.2 Customisation model (all in `giant_skin.gdshader`) — VERIFIED
| Option | How | Data cost |
|---|---|---|
| Skin tone | albedo × (tone / bake tone), sRGB-hinted uniforms | 0 |
| Hair colour on skin | stubble (mask R), scalp (G), brows (B) tinted by `hair_color` | 1 mask texture |
| Tattoos / war paint | 4 designs per RGBA texture, `tattoo_on` per channel, colour per design, `tattoo_paint` 0 = ink in the skin, 1 = paint on top | per sheet of 4: 17 KB shipped at 1024 DXT5, 8 KB at 512 (these sparse designs) |
| Scars | 4 sets per RGBA, paler + glossier + relief from the mask gradient (two extra taps) | 6 KB per sheet |
| Eyes | iris/pupil/limbus drawn from the sphere's UV in `giant_eye.gdshader` | 0 |
| Clothing | visibility per garment, dye per material, `hidden_regions` | 0 + meshes |
| Designs anywhere | drawn in 3D on the rest pose from `restpos.exr` (no UV seams) by a numpy generator | offline only |

Runtime switching is just `set_shader_parameter` (VERIFIED: one instance, parameters swapped
between `custom_A` and `custom_B`). Hit flash and status tint (RigPaint) need two extra uniforms in
each giant shader (ASSUMED, trivial).

### 4.3 Formats and the Web — VERIFIED (shipped = gzip -9 + base64, per file, from the test pck)
| Texture | VRAM-compressed (S3TC/RGTC) | 512 VRAM | WebP lossy (q 0.7) | WebP lossless | Basis Universal |
|---|---|---|---|---|---|
| albedo 1024 RGB | **252 KB** (DXT1) | 89 KB | 62 KB | 672 KB | 809 KB |
| normal 1024 | **1,294 KB** (RGTC) | 329 KB | 61 KB | – | 948 KB |
| ORM 1024 | 521 KB (DXT1) | 136 KB | 124 KB | – | 1,146 KB |
| masks 1024 RGBA | 70 KB (DXT5) | 24 KB | – | 98 KB | – |
| scars / tattoo 1024 | 6 / 17 KB | 3 / 8 KB | – | 2 / 18 KB | – |
| hair atlas 512 | 229 KB (DXT5) | – | – | 314 KB | – |

- **The normal map is the expensive texture** (RGTC barely compresses). 512 RGTC (0.31 MB) is the
  best Web trade; WebP lossy visibly flattened the skin detail (frame 7, middle) and costs 4-8x the
  VRAM (RGBA8); Basis Universal lost on every map here.
- VRAM (Web preset, measured): the 1024 set + 512 atlas = **+7.35 MB texture memory**, meshes
  **+3.04 MB buffer memory**; fine for desktop and WebGL2 (ASSUMED for low-end laptops).
- Desktop exports have no pck budget: keep 1024 there and exclude it from the Web preset with the
  existing `exclude_filter` mechanism + a runtime fallback to the 512 set (ASSUMED design).

---

## 5. Skin without subsurface scattering (task 4) — VERIFIED (frames 1, 2, 6)
- `light_model` 0 Lambert, 1 per-channel wrap ((N·L + w)/(1 + w), w = 0.42/0.20/0.13, red wraps
  furthest), 2 wrap + transmission (`sss_color` × thinness (1 − baked inside AO) × back-light^4,
  plus a rim term). StandardMaterial3D (built-in) looks darker and harder than wrap.
- Model 2 with the corrected thinness lights ears, nose, fingers and silhouettes red when the sun is
  behind, without a glowing torso (my first try used the AO map unflipped: the whole front glowed).
- Roughness ×1.25 over the bake (0.55-0.6) removed the oily look; my GGX in `light()` divides by π.
- A baked SSS lightmap in the albedo was not tried: it would double the dynamic lighting (ASSUMED
  worse than wrap).
- Next to the game: same sun (-48°, -35°), ambient (0.62, 0.64, 0.7) × 0.62, sky colour and fog as
  `world.gd`. At the third-person camera the giant reads clearly and the lighting matches; the
  realism gap to the box soldiers, crates and trees is obvious up close (frame `world_front`), as the
  owner was told.

---

## 6. Budgets and the pipeline (tasks 5 and 6)

### 6.1 Per frame — VERIFIED (Web/low preset; medium = 3x draw calls with 2 shadow splits)
| Giant | Draw calls | Primitives at 7 m |
|---|---|---|
| body + 2 eyes | 3 | 13,518 |
| + hair + beard | 5 | 22,458 |
| + braies + belt | 7 | 24,190 |
| warrior (tunic, jerkin, belt, bracers, boots, furs) + hair + beard | 11 | 36,216 |
| box giant today (8 merged meshes) | 8 | < 200 (ASSUMED from the builder) |
A weapon adds 1 (ASSUMED). Eyes could merge into one mesh (−1).

### 6.2 pck growth — VERIFIED (one Web export of the scratch worktree, `GA/webtest/index.pck`)
Base at this HEAD without giant files: 17,285,179 B raw, **17,399,456 B shipped (16.59 MB)**;
budget 23 MB = 24,117,248 B → 6.41 MB headroom.
| Set | Contents | + shipped | Total |
|---|---|---|---|
| A render set | 1024 VRAM albedo/normal/ORM/masks/scars/tattoo, 512 atlas, parts (LODs), 4 hair styles | +4.04 MB | 20.63 MB |
| B web lean | WebP-lossy albedo, 512 VRAM normal/ORM/masks/scars/tattoo, atlas, parts, hair | +2.52 MB | 19.11 MB |
| C smallest | WebP everywhere, parts without LODs, hair | +2.16 MB | 18.75 MB |
| meshes only | parts (with LODs) + hair | +1.76 MB | |
Per item (shipped): body+eyes+7 garments 1.35 MB (≈61 B/vertex; body ≈0.84, tunic ≈0.13, boots ≈0.16
by vertex share, ASSUMED split); hair glb 0.40 MB for 4 styles (≈35 B/vertex: long ≈0.19, crop
≈0.06, full beard ≈0.11, short beard ≈0.05, ASSUMED split); a shape key 0.34 MB.

**What fits under 23 MB** (from set B, ASSUMED content sizes from the measured rates): 6 hair
styles + 5 beards (+0.75 MB), 4 tattoo sheets = 16 designs (+0.05), 2 more hair atlases for curly /
braided (+0.45), ~6 more garments (+0.6) → ≈ 21 MB, leaving ≈ 2 MB for M10's creator screen, shrine
UI and M9's remaining growth. **Question for the owner**: raise the Web budget to 26 MB (still two
15 MB parts), or keep 23 MB with 512 normal/ORM on the Web and a capped hairstyle list?

### 6.3 Determinism — VERIFIED
- `export_game_giant.py` twice → identical `giant_parts.glb` (sha256 068fd8f5…); `hair_cards.py`
  twice → identical `giant_hair.glb` (12f36025…) and `hair_atlas.png` (34eb041a…).
- Godot re-import: textures bit-identical (`albedo`/`normal` .ctex); imported `.scn` differ by a few
  bytes (random sub-resource ids, 1,073,373 vs 1,073,374 B) → verify the glTF/PNG sources (which are
  what is committed), never `.godot/imported`.
- Cycles bakes: two runs of `bake_body.py -- 512 8` (2 threads, seed 0) gave **bit-identical**
  albedo, normal, roughness, AO (8 spp), masks and scars PNGs, and a third run with **1 thread**
  gave the same albedo, normal and AO bytes (thread-count independent). Other CPUs / bpy builds:
  ASSUMED to need the tolerance check of §6.5.

### 6.4 CC0 data in a fresh checkout — VERIFIED sizes
- Minimal subset the pipeline reads: hm08 `base.obj`, the 122 targets used, `target.json`, the
  game_engine and default rigs + weights, 6 region mask JPEGs, `sss.png`, LICENSE: **136 files,
  9,960,994 B raw, ~4.5 MB compressed** (dropping `sss.png` and the default weights after porting
  `region_masks` to game_engine bone names saves 3.1 MB raw). The full target tree (for every
  MakeHuman slider) is 1,445 files / 37.7 MB: do not vendor it.
- Recommended: **vendor the subset** in `tools/giant/mpfb2/` with its LICENSE and a CREDITS.md entry
  (offline, deterministic, reviewable), plus `tools/giant/fetch_mpfb2.py` that re-extracts it from
  the wheel `anny-0.6.2-py3-none-any.whl` (47,711,600 B, sha256
  `bad70bdc2be0dfa9880d60129c3a1339678f08f493184f637dc2825c3e27b8d2`, VERIFIED on the local copy;
  download URL on PyPI ASSUMED) and diffs it against the vendored copy (audit only).

### 6.5 Committed tools — design (ASSUMED, modelled on the audio pipeline's `--verify`)
```
tools/giant/
  requirements.txt      bpy==5.3.0 numpy==2.5.4 scipy==1.18.1 pillow==13.0.0 OpenEXR==3.5.4 (Python 3.13)
  setup_venv.sh         venv outside the repo (bpy is 927 MB installed), pip install --require-hashes
  mpfb2/ + LICENSE      the CC0 subset (§6.4); fetch_mpfb2.py audits it against the wheel
  kit/                  mh_data, giant_body, giant_skin, giant_hair, giant_garment, node_util, skin_textures
  build_giant.py        --body --garments --hair --bake --tattoos --pack --all --verify
  manifest.json         sha256 of every output + toolchain (python, bpy, numpy, scipy, pillow, CPU flags)
assets/giant/           giant_parts.glb, garments/*.glb, hair/*.glb, tex/*.png (+ .import), tex_hi/ (desktop)
```
- `--verify` regenerates into a temp folder and compares with the manifest: bit-exact on the
  reference toolchain (glTF, atlas, tattoo/scar masks), per-channel tolerance for Cycles bakes on
  another CPU/toolchain (e.g. max |Δ| ≤ 2/255, mean ≤ 0.1/255), reporting TOOLCHAIN DIFFERS vs
  CONTENT DIFFERS like `build_audio.py --verify`.
- `check.sh --giant`: runs `build_giant.py --verify` (skipped with a note when the venv is absent;
  the bake step needs ~13 min at 2 threads, AO dominates: keep it out of the default tier) and a
  Godot suite `tests/integration/test_giant_assets.gd` (53 bones, vertex/triangle caps per mesh,
  texture sizes and import modes, every shader compiles in Compatibility, the customisation
  uniforms exist, the hair meshes bind to the body skeleton by name).

---

## 7. Risks and open points
- Animation is not in this brief: the realistic body needs a driver from ActorRig's (yaw, pitch)
  arm aims to bone rotations (TwoBoneIK3D/AimModifier3D are available); hit sweeps must stay exact.
- Hair quality is "good game cards", far from the strand renders; budget a day of art tuning.
- Garments are surface offsets, first pass; boots are too dense (4,688 tris).
- Godot stores blend shapes dense: no body sliders on the full body mesh.
- Facts measured on llvmpipe; real-GPU frame times on the Web were not measured.

---

## 8. Reproduce
```
G=<scratchpad>
PY=$G/giant/venv/bin/python; GA=$G/m10_plan/giant_asset
nice -n 19 $PY $GA/scripts/export_game_giant.py
nice -n 19 $PY $GA/scripts/hair_cards.py
nice -n 19 $PY $GA/scripts/bake_body.py -- 1024 24
nice -n 19 $PY $GA/scripts/tattoo_masks.py -- $GA/out/bake1024
$PY -I $GA/scripts/pack_textures.py $GA/out/bake1024 <project>/m10lab/giant/tex
# Godot: copy GA/godot_lab/{shaders,tools} to <project>/m10lab/, the glbs to m10lab/giant/, import, then
xvfb-run -a -s "-screen 0 1280x720x24" tools/gd.sh --path . --rendering-driver opengl3 \
  --resolution 1280x720 -s res://m10lab/tools/render_tests.gd -- --quality=low --out=<dir>
python3 $GA/scripts/pck_growth.py <export>/index.pck
```
