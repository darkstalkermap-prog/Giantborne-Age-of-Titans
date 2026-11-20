# W33look — the giant's wardrobe, looked at again

Milestone M11, part B (the release 0.12.0-m12), before the owner's preview of part two. A look pass over the wardrobe
(P54), the accessories, the hair and the beards (P56), from a review of their capture sheets; built on `pkg/W33look`
from the merged head `b269fb0`, beside the performance lane. Every frame below was drawn by Mesa's llvmpipe under Xvfb
(no GPU) with the wardrobe render probe's review sheets (`tests/support/wardrobe_render_probe.tscn -- --review`) and
a scratch probe of single looks at the creator's framings, in the world's light and the creator's, at stage 1 and at
the stage-6 game camera.

## What changed

### 1. A garment stands off only as far as what is worn under it

P54 built every garment of an outer slot clear of the envelope of *every* garment of every inner slot, so the default
Wanderer's belt stood about 4 cm off his braies (it cleared the tunic, the shirt and the vest at the waist that he does
not wear), an armour flared over a war belt that was not there, and a hauberk's skirt over the kilt's flare.

Now (`tools/giant/kit/giant_garment.py`, `Wardrobe.build`):

- Each garment is built twice: over nothing (its **base**: the slot's own offset, as it sits worn alone) and at P54's
  **full** place (clear of the loosest garment of every inner slot). The mesh is the base.
- Each vertex carries its **push** to the full place along its skin vertex's normal (`Wardrobe._push_field`; a band's
  or a cloak's at least what clears the envelope under it at the skin vertex it stands over), quantized up to 255
  steps of the garment's greatest push: the export writes it in the vertex colour's alpha and the mesh's `push_m` in
  the index. A garment vertex's rest height rides in UV2.x.
- The **layering table** (`Wardrobe._layering`; the index's `layering`): for every outer garment and every inner
  garment it stands over, the least share of its push that keeps it `LAYER_GAP_M` (12 mm; a cloak's hanging cloth 5 cm
  more) clear of the inner one, at five shares of the inner one's own push (0, 0.25 ... 1) and at **six knots of rest
  height** (the thighs, the hips, the waist, the belly, the chest, the shoulders): a shirt under a hauberk pushes its
  chest, braies push a coat's hips. The envelope an outer slot is built against is its inner garments at their whole
  push, every share's envelope at least the smaller shares' (so the table, read at the share at or above, is enough).
- **At runtime** `GiantLook.garment_pushes` takes, for each worn garment from the skin out, the greatest share over the
  garments worn under it, read at the inner garment's greatest share; `apply` sets the cloth shader's `push_m` (the
  knots' shares times the mesh's push_m, an array of six) and `pushed`, only for what changed; the shader eases the
  share between the knots by the vertex's rest height and pushes along the normal. Worn alone a garment draws at its
  base; an index without the table draws every garment at its mesh.
- The shells' distances (the export's `shell_distances`, the test's floor 4 mm in four poses) are measured for every
  pair at the inner garment's no push and full push with the outer one at the shares the table gives it.

Measured: the belt over the braies alone takes at most 0.16 of its push (it took all of it); the tunic over the braies
none; a hauberk over a shirt 0 at the hips, 0.03 at the waist, 0.35 at the chest. The least shell distance in the four
poses: 5.4 mm (leg wraps under boots; the floor 4).

Shaping that came with it: the braies are slimmer (looseness 0.021, folds 0.010 human m) and cinched at the waist
(they spanned the small of the back 4.4 cm off it); shells span the skin's hollows (`Wardrobe.bridge`, 12 neighbour
passes; 40 for the hauberk, the scale coat and the hood); a band's ring bridges the small of the back and the cleft of
the buttocks (`BAND_SECTOR`); a measured envelope fills only its gaps (P54 raised every vertex to its neighbours'
highest: the cleft's envelope stood at the cheeks'); an armour's flare over a belt eases off twice as fast
(`RAMP_SLOPE` 1.6). A band's vertices stand on the skin vertex under them (its weights, build weights and normal),
not the nearest one.

### 2. Mail and scale

- At the game camera the hauberk read as grey plate: the rings and the scales draw larger (`GiantLook.DETAIL_SCALE`:
  mail 56, scale 40 tiles over the body's UVs, the cloth's 96) and deeper (`NORMAL_STRENGTH` 1.1 and 1.0): at stage 6
  the hauberk shows rows of rings.
- The skirts hang: less flare, the back of a coat spans each 2 cm slice's convex hull between the hips and the hem
  (`Wardrobe.hull_fill`: the cleft of the buttocks), then each vertex below the hips stands at least as far back,
  forward or out as the skirt above it in its column (`Wardrobe.hang`).

### 3. Cloaks

The cloaks hang from the shoulder blades as one sheet: each hanging vertex falls from the rearmost cloth above it in a
10 cm column (P54 looked at the hanging cloth only, which began under the blades and stepped off the back), leaving the
back over 12 cm (`ease`), from 18 cm under the shoulders; the hanging cloth keeps its own surface's normal (leaning
back) for its shading and its push, is cleared straight back (not along the skin's normal under the buttocks, which
folded it over itself), and takes the greatest push above it in its column; the middle of the back down to the hem is
in the cut (the cleft left a notch the long cloaks folded from) and the hanging cloth's breadth is smoothed in the
middle. The short cape's flare is halved (it read as a bustle). The chains still take the cloth from 0.375 m under the
shoulders.

### 4. Accessories, beads, the bronze plate, horns, the hood, fur, the circlet

- **Rings** (torcs, arm rings) shade with their own round normals; the skin's normal, the line of their build push,
  rides in their glTF's tangents (`export_game.add_push_tangents`; the cloth shader's `push_tangent`). A ring sits on
  the bare skin, clears only the chest's and the armour's envelope (`RING_SLOTS`, not a mantle's fur), and moves out
  over a sleeve by its own rows in the layering table: the arm ring no longer stands off like a bar.
- **Bone beads** drew grey-blue under the creator's key light: the bead sets' winding faced inward, so the double-sided
  shader turned their normals in. Fixed in `export_game.bead_object`; bone is warmer and duller (`BONE`).
- **The bronze breastplate** is bronze: a garment may name its own dye (`set_garment.json` `dye`, checked by
  `Appearance.data_errors`), taken before the outfit's dye of its material; a per-slot dye still wins.
- **The horned helm's horns** keep their own normals (they took the scalp's and read flat from behind).
- **The hood** stands off the crown, comes to a point behind the head and covers the ears (the face's opening was
  wide enough to leave them out).
- **Fur** (the cloth shader's kind 3): clumps from the detail map at a third of its scale, a deeper normal, a fuzzier
  rim, a silhouette broken into tufts where it turns from the eye.
- **The circlet braid** takes the farthest point of each slice in its own direction's sector (it stood off the temples
  over the ears).

### 5. The Highland Herdsman

Older, weathered, a full greying beard, a fur cloak over an ochre kilt, a drinking horn: the likest presets in the
rendered grid are now M10's veteran and chieftain (7.5 % of the frame), not the herdsman and the Young Giant (6.9 %).

### 6. The share

- **Parts without the skeleton**: every part's glTF carries the model's whole 71-bone armature; GiantModel takes only
  a part's mesh and its skin. `tools/giant/part_import.gd` (written into every part's `.import` by `build_giant.py`)
  keeps a root and the one skinned MeshInstance3D: about 7.5 KB of imported scene a part, 517 KB in all.
- **The estimate** (`build_giant.py --budget`) counts a part's face keys (about 20 B a glTF vertex a key) and the
  part's file without the skeleton (8 KB), the rates refitted on the imported parts (within 3 % of them).
- What the look added: UV2 on the pushed garments (8 bytes a vertex), the push alpha, the rings' tangents, the
  layering table in the model's index.

## Tests changed (each because the content or the design moved; no floor loosened)

| Test | Change |
| --- | --- |
| `tools/giant/test_giant_tools.py` `WardrobeTest` | new: the layering table (its order, shares within 0-1 and rising with the inner share at every knot, the belt over the braies under 0.5, a shirt pushing a hauberk's chest and not its skirt, the rings' rows and tangents) |
| `tests/unit/test_giant_look.gd` | new: `garment_pushes` and `garment_push_m` on a synthetic table (worn alone none, the step at or above, by knot) |
| `tests/unit/test_appearance_record.gd` | new: a garment's own dye before the outfit's and after the slot's; the every-garment walk expects a garment's own dye where it has one |
| `tests/integration/test_giant_parts.gd` (through `GiantModel.part_cost`) | `part_cost` counts a UV2 (8 bytes a vertex): the garments carry one now |

## Checks

- **The giant's regeneration**: `build_giant.py --verify --skip-bake`: GIANT VERIFY OK, 88 files regenerated bit-exact
  (98-102 s). No bake input changed (the body, its UVs, the skin code, the bake settings, `pack.py`), so `--giant-full`
  was not needed. `test_giant_tools.py`: 40 tests OK (about 4 s).
- **The share** (`env -u XDG_DATA_HOME tools/build_web.sh --version=0.12.0-m12`, the version string unchanged):
  `PCK_SIZE shipped=31383912 shipped_mb=29.93 budget_mb=32 parts=3` (30.44 on the base) and
  `GIANT_SHARE shipped=13405208 shipped_mib=12.78 cap_mb=13.6` (13.31 on the base): 0.53 MiB less - the parts'
  skeletons out (about 0.66), the garments' UV2, push alphas and the layering table in (about 0.13).
  `build_giant.py --budget`: 13.26 MiB estimated (10.78 before: the keys were not counted).
- **The full check** (`tools/check.sh --build --slow --gate --giant --web-tools --require --strict-times`, on the
  lane's last asset commit, beside the other lane's runs, which the lock kept apart): `TIMES: default 66.7 s | slow
  432.6 s | gate 1029.3 s`; `RESULT: 354 suites, 70222 checks, 1 failures` - the known one on the base,
  `test_giant_preview` "a whole look is applied in under 1 ms" (1.101 ms; 1.04-1.08 on the base under the same load). A
  bench of `GiantPreview.apply_look` (60 rounds, the same look): median 1.08-1.09 ms with this lane's GiantLook against
  1.05-1.08 with the base's, the layering lookup about 0.02 ms (cached per index; only changed pushes are set).
- **The soak** (`--autoplay=120`, the check's step, run on its own since the check stops at the failing suite): 41
  attacks, 33 hits resolved, 4 enemy kills, 2 fence breaks, 7,201 frames, 0 errors - the baseline.
- **The rendered suites**: `test_wardrobe_render` (no z-fighting in the fullest look's flat colours),
  `test_catalogue_render` (every preset distinct; the likest now 7.5 %) and `test_giant_parts_render` pass.
- **The fullest slot look**: the shells' least distance over the four poses 5.4 mm (floor 4); mesh buffers 2.01 MB the
  fullest look (budget 4.5).

## Frames

The lane's captures (not committed): the review sheets of every outfit before and after, the single looks (the belt on
the braies, the hauberk over a shirt at the game camera, the cloaks alone and over armour, the rings bare and over a
sleeve, the beads in the creator's light, the hood and the horned helm, fur, the circlet). They are reproduced by
`tests/support/wardrobe_render_probe.tscn -- --review --out=<folder> [--looks=...] [--closeups]`.
