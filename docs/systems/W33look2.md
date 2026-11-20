# W33look2 — the giant's wardrobe, looked at a second time

Milestone M11, part B (the release 0.12.0-m12), before the owner's review of the wardrobe sheets. The second look lane
after `docs/systems/W33look.md`, on `pkg/W33look2` from `346eb54`, with P57 merged in before its last check. Every
frame was drawn by Mesa's llvmpipe under Xvfb (no GPU): before and after captures of the same looks at the creator's
framings in the world's light and the creator's (the wardrobe render probe's `--review --closeups`, the catalogue
render probe's `--review` groups, and scratch probes of single looks: the trophies at the hip, the torcs, the arm
rings, every scar and paint at its framing, the armour at the chest framing, the presets' backs), and the giant at 60
to 200 m at 1920x1080.

## What changed

### 1. The giant beyond 120 m (plan M11 §2.12: at most 4,000 primitives)

At 121 m at 1920x1080 (the giant at stage 1 about 47 px tall in the creator's lens) the Wanderer drew 10,952 primitives
and the fullest look 15,616: the importer's LODs keep every mesh within about a pixel of its shape, and they cannot
reduce hair cards (a card is a strip of quads; its first level of the long hair stood at an error of 0.15 m and was
never taken). M10 met the row (3,920) with the warrior's outfit and the importer's levels of the time.

`tools/giant/far_lods.gd`, run by `tools/giant/part_import.gd` on every part and now on `giant.glb`'s meshes (the shadow
proxy aside), gives each mesh **far levels**, index lists only (the vertices are the mesh's own):

- Every mesh: one far level, the coarsest importer level within `FAR_ERROR_M` (0.3 m) that keeps 2 % of the triangles
  (at least 24; a bead set none), switched on at the key `FAR_KEY` 0.045 - the renderer compares a level's key with
  the distance in pixels, so it shows where the giant is under about 60 px tall (85-100 m at stage 1 at 1920x1080,
  nearer at a smaller window, farther at a larger stage). Where the importer stopped early (the wrapped sandals kept
  a quarter of theirs) the far level is thinned by vertex clustering to about 7 %.
- A hair style or a beard: its own levels instead of the importer's. Every strip (a card, a braid's tube, a tie's
  bead ring) is found from the mesh (rows of one V, columns of rising U) and drawn with the rows that keep its middle
  line within 4 mm (the middle level, key 0.02) or 12 mm with a ring as a triangle, the largest strips first, at most
  280 triangles (the far level).

Measured (`tests/gate/test_giant_far_render.gd`, 1920x1080): **the Wanderer 1,722 primitives and the fullest look
3,121 at 121 m** (1,714 / 3,113 at 151 m, 1,558 / 2,977 at 200 m); the silhouettes at 121 and 151 m within 12 % of
full detail's pixels and 80 % in common (they were compared by eye too: the beard, the belt and the helm stay). The
worst slot look (the garment with the most far triangles in every slot, the heaviest hair and beard, two bead sets,
an accessory in every accessory slot) sums to 3,643 far triangles (`tests/integration/test_giant_far_levels.gd`, its
bound 3,800). At 60 m the middle level of the hair draws (11,458 and 20,644 primitives, 16,348 and 25,178 before).

### 2. What hangs on him

- **Belt trophies** sit on the bare skin and move out along their side (+-X) as far as the garments worn under them
  need (`giant_garment.trophy_push`): their rows in the layering table and their push in their tangents, as the
  rings' (`export_game.add_push_tangents(along=...)`). They hung clear of the fullest wardrobe's envelope - the horn
  half a metre off the hip in the fullest look, on the Bronze Lord, the Highland Herdsman and the Bone Reaver (the
  jaw) in the presets' backs; now none floats. Over braies alone the horn takes 0.13 of its push, over a hauberk 0.56.
- **Torcs** rest tilted on the collarbones (`TORC_TILT`), 4 mm clear of what is under them (`TORC_GAP`): they went round
  the neck level with the chin and read as a bar under the beard and stood off the back of the neck.
- **Arm rings** close round the biceps (t 0.5 of the upper arm) over a 5 % slice, not widened by the neighbouring
  sectors: at t 0.72 the skin bent with the forearm and the rigid ring stood off like a hoop.
- **The belt** was not changed: in these captures it lies on the braies and the tunic; the war belt under a hauberk is
  hidden by it.

### 3. Scars and paint

- Scars (`designs.scar_profile`): a spindle pointed at both ends, its edge feathered over half its half-width and
  wandering a little, its tissue grained; drawn wider (`SCAR_SPREAD`) so they read as much as before; the brow scar a
  third longer either way, the forearm slash longer and broader. The skin shader draws healed tissue paler and pinker
  than the skin and desaturated (it multiplied the skin's red by 1.5: an orange stripe), raised a little with its slope
  limited (the relief cut black grooves beside each scar).
- War paint (`designs.paint_edge`, `paint_body`): the eye band, the full face and the half face end in soft, smeared
  edges (two-scale noise along the skin), fade round the temples where the face turns away (they were cut off by the
  normal), and the paint's thickness varies.

### 4. Armour, the kilt, the caps

- **Metal** (the cloth shader's kind 1) mirrors a sky, the dark ground and a bright horizon tinted by its own colour
  (the scene has no reflections to give it); a little more metallic and glossier. Mail reads as bright rings in the
  creator's light; in the world's light the plate is still dark.
- **Leather** (kind 4, `GiantLook.DETAIL_KIND`): warm and waxed, lifted out of black, sewn in panels with a groove and
  stitches every 17 cm of rest height (on the garments that carry a rest height: those pushed over inner slots). The jerkin and the cuirass read as stitched brown leather in the creator's light.
- **The kilt** reaches the knee, flares more and has thirteen knife pleats round the hips. From behind it still reads as
  wide shorts: a shell pushed along the skin's normals cannot hang between the legs.
- **Caps and helms** close in at the rim (the brow, the temples, the nape) and keep their dome; the iron helm and the
  leather cap sit lower, with no gap under the rim (at least `CAP_RIM_LEAST_M` off so the crop stays under them).

### 5. Backs

- **The loincloth**'s back flap reaches as deep as the front behind the hips' middle and hangs as a panel (hull fill,
  hang): the Bone Reaver's buttocks are covered; the Berserker's (its loincloth in a light dye) are covered on top,
  bare under it.
- **Cloaks**: not changed. The game view runs SecondaryMotion on the cape's chains (`SkinnedRig` attaches it with the
  skinned layers, never headless, and configures the `cape_c/l/r` chains when a cape or cloak is shown); the creator's
  previews and every capture here do not, so a long cloak hangs straight there.

### 6. Hair and beards

- **The circlet braid** goes round at the hairline and over the back of the skull (it was 9.5 cm over the brow, a halo
  level with the top of the hair) and rests on the hair; from behind it still dips into the long hair in places.
- **Beard cards** (tip_thin set: every beard now, `BEARD_SHORT_TIP_THIN` on the short-card ones) narrow to a point at
  the tip; at the creator's framings the change is small - the chops and the chin braid's base still read as patches.

## Tests (new behaviour; nothing loosened)

| Test | What |
| --- | --- |
| `tests/integration/test_giant_far_levels.gd` (new, default) | every mesh's far level, the strands' two levels, the worst slot look's far triangles at most 3,800 |
| `tests/gate/test_giant_far_render.gd` + `tests/support/giant_far_probe.{gd,tscn}` (new, gate, about 12 s) | rendered at 1920x1080: at most 4,000 primitives at 121, 130, 151 and 200 m for the Wanderer and the fullest look; the silhouettes kept; finer at 60 m |
| `tools/giant/test_giant_tools.py` `WardrobeTest` | the trophies' rows and tangents (the horn over braies under half its push, a hauberk pushing it more than twice as far) |
| `tests/unit/test_giant_look.gd` | leather takes kind 4 (was 0: the content moved); a short beard's tips thin by `BEARD_SHORT_TIP_THIN` (was 0) |

## Checks

- **Regeneration**: `build_giant.py --verify --skip-bake`: GIANT VERIFY OK, 88 files bit-exact (136 s). No bake input
  changed. `test_giant_tools.py`: 40 tests OK.
- **The share** (`env -u XDG_DATA_HOME tools/build_web.sh --version=0.12.0-m12`): `PCK_SIZE ... shipped_mb=29.93
  budget_mb=32 parts=3`, `GIANT_SHARE giant_bytes=14850110 shipped=13410812 shipped_mib=12.79 ... cap_mb=13.6` (12.78
  before: the far levels' indices and the trophies' tangents).
- **The rendered suites**: `test_hair_render` (every scar at least its floor: the forearm slash needed its longer,
  broader line), `test_appearance_render`, `test_catalogue_render`, `test_wardrobe_render`, `test_wardrobe_stack_render`
  (worst patch 0.0001), `test_giant_far_render`, `test_design_array` pass.
- **The full check** (`tools/check.sh --build --slow --gate --giant --web-tools --require --strict-times`, on the merged
  head with P57): `TIMES: default 70.2 s | slow 425.2 s | gate 1160.7 s`; `RESULT: 358 suites, 78342 checks, 0 failures`;
  CHECK PASSED. The soak (120 s autoplay): 41 attacks, 33 hits resolved, 4 enemy kills, 2 fence breaks, 7,201 frames,
  0 errors - the baseline.

## Not done (FOLLOWUPS)

The braies' "checker" is the shadow map's steps where the shadow proxy's shadow falls across the shell near the
terminator (not the weave's scale); the kilt and the tunic's skirt as skirts between the legs; the scale coat's
buttocks; the cloaks' hang (hug of the back, the hip roll, the long cloak's board); the hood's cowl; leg wraps' bands
and greaves' plates; toes through the boots' tips; the short beard shell's grey speckle; stubble's orange stain; the
dark patch under the jaw without a beard; the chin key's wedge; the tunic and the shirt alike; plain belts and sash
(stripes); temple spirals; hair from behind, long styles alike, beads behind long hair, scalp blotches, the top knot's
tuft; ragged hems and the slivers at build +-1.
