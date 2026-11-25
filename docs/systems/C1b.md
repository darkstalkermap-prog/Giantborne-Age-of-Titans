# C1b — The land beyond the rim, a look pass (the Hoarfell, the Breach, the act-one finale)

C1 opened the Hoarfell and said honestly what was wrong with it (`docs/systems/C1.md` §6): one flat grey ground,
smooth sheet walls in the Breach, the old kings' works built of plain boxes (the Fallen King read as rubble and a
pillar), a smooth cone for the Hoarcrown, Last Hearth a few specks on bare ground, thin identical scatter, and a
finale in which only the camera moved. C1b is the look pass on `pkg/c1b` from C1's merge (`46fdd2c`); the version
stays **0.16.0-m16**. Nothing of gameplay, balance, quests or saves changed (schema 3), nor the chunk grid or its ids.
Everything is built from the repository's own means: two new world shaders, one cloud shader, the layout's own seeded
shapes, the existing sounds; no texture or sound file was added.

## 1. What changed

### 1.1 The ground beyond the rim (`assets/shaders/frost_ground.gdshader`)

The streamed terrain's material is the frost ground wherever the level names a **frost band** (the world block's new
`frost`: `{"from_z": -905, "full_z": -1000}`, `ChunkStreamer.frost_band`, the level schema's `world.frost`); south of
the band it draws the vertex colours exactly as the plain material it stands in for, so the Old Kingdom is as before
(a level without a band - the Valley, the test world - keeps the plain material). In the band everything is world-space
noise on the height and the slope (no texture, no UV, no new file):

- **the upland**: scree and frozen earth in patches with edges, a cast of the region's own tint, tussock and lichen
  on the flatter ground below the snow line;
- **snow** where the ground is flat enough to hold it: in drifts on the upland (176-260 m), thickening to whole above
  the snow line (300 m), with rock breaking through it on the slopes and flutes down the fall line;
- **rock** on the steep faces: broad tones, streaks down the fall line (gullies and stains, the normal ribbed along
  them), short ledges with their shadow under them, snow caught on the ledges and in the gullies high up;
- the detail fades with distance (the ground's grain by 90 m, the ledges' shadow by 180 m) so the far rim does not
  shimmer or read as contour lines; the noise is kept to about twenty value-noise samples a pixel (two-octave sums,
  the grain's relief only near the eye) because the Web's software rasteriser pays for every one.

The far **skyline** (the coarse terrain drawn beyond the loaded chunks) follows: north of the band its baked colours
carry snow on the heights and darker rock on the steep (`world.gd _skyline_color`), and its shader streaks the far
slopes down the fall line (`Skyline.set_frost`).

### 1.2 The Breach

The gorge's walls are the terrain's, so the frost ground's rock is what reads first: streaked faces with ledges
instead of smooth grey sheets. On them, a new colossal style **`breach_wall`** (two elements, the gorge's lower and
upper halves) walks up the gorge and reads each wall's foot and face off the height field: talus heaped at the foot,
slabs fallen from the face, strata ledges jutting up it, split pillars leaning on it - all outside the walkable floor
(35 m from the axis; the floor is 64 m) and none solid; `"map": false` keeps them off the map's picture and
`"clear_m": 1` keeps them from clearing the Stonehold's scenery (the Old Kingdom's chunks and navmeshes are unchanged).
The jaws are fractured slabs now (the layout's worn `block` shape) with their spalls and rubble at the feet, and the
snapped chain across the mouth is real links.

### 1.3 The old kings' works (`tools/world/kinds/colossal.gd`)

Every piece is built of the layout's new **seeded natural shapes** (`WorldLayout.part_faces`: convex hulls of seeded
point sets, the same seed the same triangles): `boulder` (a frost-split stone, one face often split off flat), `block`
(a giant-cut block, its edges worn round, its corners pushed about), `drum` (a column drum worn uneven) and `ellipsoid`
(the statue's rounded masses). Every piece is **weathered**: a part's `weather` goes into its vertex alpha and the chunk's
structures mesh draws with the **frost stone** material (`assets/shaders/frost_stone.gdshader`, `mat_frost_stone.tres`):
snow lying on what faces up, frost-killed lichen in blotches, grime run down the faces, the stone worn uneven, fine
cracks and a roughened normal - all world space. An unweathered part (alpha 1) is drawn exactly as the plain
vertex-colour material, so a chunk's other structures look as before. A weathered part's normals are its own (flat
for a fresh break, `smooth` within the part for the statue's masses, a worn block and every stone - its edges read
rounded and it stores a fifth of a faceted stone's vertices); the other parts keep the smoothing group they had.

- **The Fallen King**: his feet on the stepped plinth, the shins broken (their fracture shards on the breaks); the rest
  of him on his back along the ground for about 120 m - the legs broken off at the shins, knees, thighs, hips and belt
  with its bronze buckle, the chest in its mantle (folds spread under him), the breastplate's ridge, the shoulders;
  one arm along his side with its fist by the hip, the other flung out with the hand open (fingers, a thumb, one
  finger broken off); the head broken off at the neck and rolled aside, face up and turned (brow, hollow eyes, nose,
  cheekbones, moustache, ears, a braided beard); the crown lying on its side apart; rubble round. His solids follow the
  new body (the plinth and shins as in C1; legs, body, head, the flung arm and hand).
- **The Kings' Causeway**: each pier is two pillars of stacked drums, a little out of true, their capitals, a cracked
  lintel with a frieze line, and frost-heaved paving; the three piers differ (`state`): the first standing, the
  second's lintel down across the paving in two pieces, the third toppled - one pillar a stump, its drums and capital
  lying in a line.
- **The chain anchors**: a worn drum of a bollard on its footing, the iron bands with the middle one burst and sprung,
  a worn rune band under the cap, the shackle and ring, and a chain of real links (four bars each, alternately flat and
  on edge) running down into a heap of broken rock.
- **The Rimstone**: the standing stone worn at its top, three carved bands, worn glyphs cut in both broad faces, the
  lesser stones round it, the fifth fallen and broken in two.
- **The cairns** of giant-cut blocks with their stones.

### 1.4 The Hoarcrown and the storm on it

The peaks are hills with **crags** (`features.gd _craggy`): above the rim's top (470 m; every height under that line is
the plain hill's, so the walkable upland and the Hoarwatch are untouched) the height is cut into buttresses and gullies
running down from the summit, twisting as they fall, and broken by value noise - the Hoarcrown seven ridges, the
Sundered Horns five each. On the Hoarcrown stands a **storm** (`world.json` `storms`, `assets/shaders/storm_veil.gdshader`):
sixteen cards of churning cloud round the summit, turned to the camera about the vertical, their noise rising and
swirling, a cold light swelling and fading slowly deep inside them - something stirring on the heights: one mesh under
the world's root, drawn within 1,600 m of the summit whatever chunks are loaded (the Stonehold's north, the Breach, the
Hoarwatch, the finale; beyond, the fog has it and the Old Kingdom's far views keep their draw calls).

### 1.5 Last Hearth (`tools/world/kinds/hearth.gd`, `smoke.gd`)

A hold-outs' camp at a man's scale, so a colossus over it reads as one: a dry-stone **windbreak** round its north and
west (46 m out, hides stretched on posts along it) and a short one round the bonfire, five **hide tents** on poles
among C1's canvas ones, two **woodpiles** under lean-tos, two heaps of **stores** (crates, barrels, sacks under a weighted
tarp), two **drying racks** hung with hides, two **fire pits**, a **lookout** post with its banner, and four columns of
**smoke** (the bonfire, the two pits, the hall's roof) leaning off downwind - CPU particles, three seconds risen when
the chunk streams in (a whole lifetime's preprocess cost the chunk's props step 35 ms on the Web). The hall, the store
and the tents are weathered (an element's `weather`: snow on the roofs). None of it is solid: the camp's people and
their paths are as C1 baked them.

### 1.6 The scatter (`tools/world/scatter.gd`)

The Hoarfell's scenery rules place **merged scatter** (`"merge": true`): every piece its own seeded shape, built into its
chunk's structures mesh (one draw with the chunk's works, as a settlement's merged buildings) instead of a MultiMesh of
one lump: frost-split **boulders**, spills of **scree**, stunted wind-killed **dead trees**, clusters of **ice** shards,
small **cairns**, and the half-buried ribs, spine and skull of **giants' bones**. None is solid (a colossus steps over
them, C1's rule). The Hoarfell's MultiMesh rock and heather are gone (two draws a chunk fewer). The Rimward's camp has
its red banners.

### 1.7 The finale (`cutscene.act_one_finale`)

The cutscene system learned **rockfalls** (`rocks`: `CutsceneRules.rock_at`, a pure function of the tick - seeded rocks
breaking away within a spread, thrown off and falling under gravity, tumbling, each laid on the ground it lands on and
kept there, a puff of dust where it lands; the cutscene schema's `rocks`). The rim visibly breaks: rocks peel off both
walls of the Breach and a 30 m slab falls into the gorge as the camera shakes (with the registered rockfall, huge-fall
and earthquake cues and dust where they break away), more rock rains down the gorge behind the snapped chain, and the
split Horn sheds its rock far off; the last shot closes on the storm over the Hoarcrown. Re-rendered after the frost
ground (C1's video was rendered before the ground's tint).

**DustBurst fixed** on the way: the compatibility renderer (the Web's and llvmpipe's) draws a CPU particle at its mesh's
size and leaves the particle's scale out, so every dust puff - the titans' footfalls and blows, the finale's dust - was a
1 m speck at a titan's scale. The puff's quad is its size now (cached per half metre); the scale only grows it where a
renderer applies it. The smoke columns are built the same way.

### 1.8 The beyond-the-rim walk

`capture_c1.gd`'s walk (`--c1-walk`, about 70 s) now walks the whole gorge to its top (44 s at stage 6's 8.1 m/s),
turns along the Kings' Causeway toward the Fallen King with the camera raised over the upland, then lifts and pans over
the upland to the storm on the Hoarcrown (C1's turned too early and ended facing the rim's wall). Six new tour beats
(`fallen_king_side`, `breach_gorge`, `upland`, `storm`, `hearth_close`, `scatter`).

## 2. Measurements

The same tools as C1, on the package's 4-CPU machine with no GPU, each run alone (`docs/PERFORMANCE.md` "C1b").

| | C1 (`46fdd2c`) | C1b | Budget |
| --- | --- | --- | --- |
| `index.pck` shipped (packed, 4 parts) | 50,183,068 B (47.86 MB) | **51,266,420 B (48.89 MB)** | 56 MB (C1b's aim: under 50) |
| `index.pck` raw | 49,983,444 B | 50,851,100 B | - |
| the page's download (wasm + pck, packed) | 62,711,768 B | **63,795,120 B** (about 64 MB) | - |
| the giant's share / the people's and creatures' | 13.86 / 15.26 MiB | 13.86 / 15.26 MiB | 15.0 / 16.0 MiB |
| the world's registered SFX | 172.86 s | 172.86 s (no sound added) | 175 s |
| the world's data (`test_world_data`: chunks, navmeshes, structures, shared, parts, index, map, skyline) | 3.72 MB | 4.54 MB | 5.0 MB |
| the structures meshes (all chunks) / the largest | 0.30 MB / 65 KB | 1.06 MB / 128 KB (`c4_-2`: the Fallen King) | - |
| the structures' triangles (the builder's count, merged scatter included) | 28,516 | 85,795 | - |
| the static world's draw calls at low (`test_world_build`, 17 views) | at most 40 | at most 40 (the woodcutters' camp 40; the storm drawn within 1,600 m of its summit only) | 40 |

**The Web, the walk through the Breach** (`world_check.mjs` with C1's fixture - the 0.15 build's completed save with
act two begun - the fast travel to the Moot foot and the 952 m walk up the Rim Road and the Breach to the Fallen King,
stage 6, low, 1280x720; three runs while the look was cut down, the last on the shipped content):

| | C1 | C1b (final) |
| --- | --- | --- |
| result | OK | **OK** (the audio criterion not met, every hole on the main thread, as always on software WebGL) |
| draw calls p50 / p95 / max | 34 / 78 / 84 | **36 / 79 / 85** |
| the renderer's peak | 1,044 MB | **1,127 MB** |
| streaming work p50 / p99 / max | 0.7 / 8.9 / 18.5 ms | **0.8 / 15.9 / 17.5 ms** |
| the heaviest steps | nav_request 18.5, request 8.9, nav_load 7.3, decode 6.6 | nav_request 17.5, decode 14.1, rows 14.0, solids 11.9 |
| loads, unloads, thrash, most loaded, margin | 13, 8, 0, 15, 233.6 m | 13, 8, 0, 15, 230.9 m |
| page frames while walking (rAF) p50 | 567 ms | 983 ms |

Draw calls, memory, loads and margin are where C1 left them (+2 / +1 draw calls, +83 MB at the renderer's peak). The
streaming p99 is not: 15.9 ms against 8.9. Its heaviest steps are steps C1b did not touch (a navmesh request, the
heights' decode, the terrain's rows, the solids' batches - plain CPU work over the same data as C1's; no structures,
scatter or props step is among them since the cuts), while the page's frames doubled (567 -> 983 ms p50): SwiftShader
rasterises the frost shaders on the same four CPUs and preempts the main thread inside those steps. The first run, with
three-octave noise, faceted stones and a full smoke preprocess, read p99 16.8 / max 21.4 ms, the second 21.2 / 35.1 ms
(a props step of 35 ms: the smoke's preprocess) - cut to the numbers above. On a GPU the shaders' cost is the GPU's;
this machine cannot measure that (**NOT RUN**, the owner's).

The other Web checks on the final build (the same pack, sha256 `a6615828...`): `world_check.mjs` (its own config, the
Old Kingdom) **OK** (draw calls p50 42 / max 57, work p50 0.8 / p99 9.9 / max 15.6 ms, margin 209.9 m, peak 1,183 MB);
`world_start_check.mjs` **OK** (peak 1,151 MB); `stream_check.mjs --world --walk-stage=8` **OK** (margin 206.6 m, work
p50 0.9 / p99 4.5 / max 5.8 ms, draw calls p50 39 / max 65, peak 774 MB).

**The check.** `nice -n 10 tools/check.sh --build --slow --gate --people --giant --web-tools --require` on `b9ff54f`,
alone: **CHECK PASSED** (10:04-11:13 UTC, 68 m 45 s): every scene rebuilt with no diff (the world builder's output
identical to the committed build, as in the two runs before it and the package's own world builds), `SEAM_CHECK ok: 64
chunks, 112 seams`, `GIANT VERIFY OK` (110 files), `PEOPLE VERIFY OK` (78 files), the Web tools' tests, **417 suites,
88,663 checks, 0 failures** (default 74.1 s, slow 450.6 s, gate 2,394.3 s), the soak with 0 errors. The full runs before
it failed on what they found and were fixed: the world's data at 5.08 MB of its 5.0 and a static view of the Old Kingdom
at 41 draw calls of 40 (the storm drawn from anywhere); then the launcher's download note (63 MB, now 64) and one timing
check (`test_formation_perf`, p95 5.06 ms against 5.0 at a load of 1.44 - it passed in the runs before and after; C1b
changes nothing a formation runs).

## 3. The carried 16 m/s stream check

C1 left the Web's carried 16 m/s stream check failing its 200 m margin at stage 6 and 8 (185 / 187 m). C1b ran the
same check with the 0.15 release's own tool (bb73c37's `stream_check.mjs --world --walk-speed=16 --walk-stage=6`) on the
0.15 release's Web build (`0.15.0-m15`, `index.pck` 49,362,732 bytes raw): **185.3 m, FAILED the same** (work max 5.9 ms,
0 thrash, 15 loaded). It is older than C1 - the carry's 16 m/s against the load ring's geometry on the default route,
nothing of the Hoarfell - so it is recorded in FOLLOWUPS and left as it was.

## 4. What is still weak (judged from the stills and the videos, bluntly)

Better than C1's grey geometry - it now reads as a cold, broken upland with ruins of a giant age - but it is still
clearly a procedural, low-poly world, and it does not yet meet the owner's "realistic and not clunky" bar:

- **The ground is noise on a smooth heightfield.** From a giant's camera it reads as a mottled frozen moor with
  patchy snow; close to it the patches are soft-edged blotches with no real grain, and the snow is flat white paint
  with crisp edges - no depth, no drifts banked against stones or walls, no tracks, no blowing spindrift.
- **The mountains are shading, not shape.** The rim, the Horns and the Hoarcrown read as rock from afar (streaks,
  ledges, snow in the gullies), but their silhouettes are still the smooth rim noise and the hills' profiles: no
  overhang or real cliff (a heightfield cannot hold one), the Hoarcrown is a grooved cone first and a mountain
  second, the Horns are two fingers, and the far skyline beyond the loaded chunks is smooth bluish white.
- **The Breach's walls** are streaked faces with pieces of rock stuck on them: the ledges and leaning pillars help in
  motion, but in a still some ledges float on the face and the face itself is still one smooth sheet under the shading.
- **The works are faceted primitives.** The worn blocks and drums read as old stone and the causeway's three states
  read well; the Fallen King now reads as a statue lying on its back from the side and from above, but his anatomy is
  a mannequin's (ellipsoids and drums), his face is only legible close, and the crown reads as a bronze cog. From the
  C1 tour's own viewpoint a causeway pillar still stands in front of him.
- **Snow is a colour.** Every work wears the same snow on every up-facing face; nothing has snow depth or drifts.
- **Last Hearth** reads as a camp now (windbreak, hide tents, stores, racks, smoke), but C1's hall and store are still
  plain boxes with a roof, six folk are very few for a hold-out, and there is no firelight (no night, no lights).
- **The scatter** is varied but low-poly: the boulders are rounded lumps (each its own now, smooth-shaded to keep their
  vertices few), the dead trees are sticks, the ice shards read as blue crystals, and there is no grass or tussock as
  geometry.
- **The finale** now shows the rim breaking - rocks and a slab peel off the Breach's walls, dust, shake, sound - but the
  rocks are the thrown boulder's one grey mesh and do not break apart, the gorge does not visibly open (it is already
  there), the Horn's split is only rock falling off its face, and the far dust is small.
- **Light** is the world's one sun and flat ambient: no colder, overcast light for the land beyond the rim, so the
  scene stays bright and clean where it should feel bleak.
- **The storm on the Hoarcrown** reads as weather on a peak, not yet as "something vast"; its cold light barely shows
  in daylight.

## Tests

| Suite | Tier | What |
| --- | --- | --- |
| `tests/unit/test_c1b_look.gd` | default | the seeded shapes closed, outward in the other shapes' winding, the same for the same seed (another seed, another stone); the old shapes' triangles as before; a part's weather in its vertex alpha (1 without); every scatter key's pieces weathered, repeatable and a few hundred triangles; the frost band read from the world block and the terrain material it picks (the plain one without a band); the crags leave every height under their line alone and cut gullies above it; the finale's rockfalls (none before their tick, the same at the same tick, falling); the smoke's and the dust's puffs drawn at their size; the Fallen King lying whole (over 100 m, his parts, his eight solids) |
| the world's own gate and default tests (`test_world_build`, `test_world_reachability`, `test_c1_world`, `test_m7_content_rule`, the seams, the rebuild's identical output) | gate, default | unchanged, passing on the new layout (the statue's new solids, the merged scatter, the Breach's dressing) |
