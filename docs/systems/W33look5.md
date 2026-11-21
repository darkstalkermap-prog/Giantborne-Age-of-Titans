# W33look5 — the giant's wardrobe, a fifth look

Milestone M11, part B (the release 0.12.0-m12). One more pass on what a player would still call fake ("realistic,
natural, not clunky"), on `pkg/W33look5` from `76e3a7a` (the fourth look lane merged). Every frame was drawn by Mesa's
llvmpipe under Xvfb: the wardrobe sheet (`tools/character_sheet.tscn -- --sheet=b`, b1-b7) before and after, and a
scratch probe of single looks (every card beard from his right, the full beard's cheek close up in both lights, the
short beard, the twin braids and the crop from the front and behind, the cloaks from behind and the side, the braies
from the front).

## What changed

### 1. Card beards' cheek edge (`giant_hair.py`, `giant_hair.gdshader`)

From the side the cheek line of every card beard was a staircase of square blocks: each card's root stood off the
skin as a straight edge, full-width cards ran to the mask's edge, and the locks' shades drew blotches.

- The cards are narrower where the beard's mask thins out (`beard_edge_share`, `BEARD_EDGE_NARROW` 0.4 of their width
  at the edge).
- A row of fine short strands (`BEARD_EDGE`: 150 a beard, 90 on the chops, 60 on the braided moustache; their own
  random stream) grows in the band where the mask ends (and only round a style's own skin), so the cheek goes from the
  beard to stray hairs to skin. The long beards' guides have one point fewer to stay under the 4,000-triangle cap.
- In the shader a beard card's strands fade in one by one over its first 42 % (`BEARD_ROOT_FEATHER`; the hair's 14 %),
  so no card root draws an edge; the locks vary in shade less (0.18).
- The mutton chops' cards are a little wider (the parts test's 60 pixels at its framing).

`test_hair_render`'s scalp measure did not block this: the full beard's scalp share stays within M10's.

### 2. The short beard (`giant_shell.gdshader`, `giant_skin.gdshader`)

Its strands are drawn as short strokes down the face (`BEARD_STROKE`: the strand tile stretched 2.6 times along the
face's UV), and the skin under a beard takes its shade fuller (`BEARD_SKIN_TINT`). Its colour stays as near the card
beards' as `test_skin_world_render` asks (the shell's channels within its tolerance of the card style's in the world's
light): a lift of the shell's saturation or less grey moved its blue channel out of it.

### 3. The crop (`giant_shell.gdshader`)

The crop's strands are strokes too, and behind the head (the mesh's normal facing back) it thins out over the short
beard's wide uneven band instead of ending on the mask's line.

### 4. The twin braids (`giant_hair.py`)

48 wider, longer cover locks over the top of the head (the style's first layer 300 cards, under its 6,000-triangle
cap): from behind the hair no longer ends in a jagged cut.

### 5. Cloaks (`build_cape`, `_extend_cloak`)

- Over the shoulders a cloak's cut cloth ends on a smooth line round the top of the arm (`sh_half`), its boundary eased
  twice as long (a torn-looking top edge where the bone weights stepped).
- A sheet cloak's hem is a smooth uneven curve, a little longer in the middle (square notches).
- From the side the falling sheet goes out over the seat and in a little toward the calves.

### 6. Braies

Half their ease off their outer side (`BRAIES_OUTER_SLIM`) and the sides narrowing faster. The change is small at the
sheet's size: the outer hips' round is mostly the thigh under them.

## Still artificial

See `docs/plans/FOLLOWUPS.md`, "From the fifth W33 look lane".

## Checks

- **Regeneration**: `build_giant.py --verify --skip-bake`: GIANT VERIFY OK, 88 files bit-exact (113 s). No bake input
  changed. `test_giant_tools.py`: 40 tests OK.
- **The share** (`env -u XDG_DATA_HOME tools/build_web.sh --version=0.12.0-m12`): `PCK_SIZE ... shipped=31481932
  shipped_mb=30.02 budget_mb=32 parts=3`; `GIANT_SHARE giant_bytes=14926940 shipped=13502020 shipped_mib=12.88 ...
  cap_mb=13.6` (12.71 before: the beards' edge strands).
- **Beyond 120 m**: the Wanderer 1,642 primitives and the fullest look 3,079 at 121 m.
- **The full check** on the head (`tools/check.sh --build --slow --gate --giant --web-tools --require`, without
  `--strict-times` on this slower container): `TIMES: default 78.3 s | slow 467.2 s | gate 1281.6 s`; `RESULT: 361
  suites, 78405 checks, 0 failures`; CHECK PASSED. The base (`76e3a7a`) the same hour: default 77.3 s. The soak: 41
  attacks, 33 hits resolved, 4 enemy kills, 2 fence breaks, 7,201 frames, 0 errors.

## The body's proportions (measured, not changed)

Measured on the human-scale phenotype (`giant_body.BodyData`, 2.447 m, the stage-1 model 3.6576 m is it scaled
uniformly; every growth stage scales the model uniformly: `GiantPreview._apply_stage_scale` and
`ActorRig` set `scale = Vector3.ONE * k`): 8.35 heads; legs (crotch to floor) 40 % of the height; shoulders 0.79 m,
4.2 head widths, 1.6 times the hips; the chin level with the neck joint (no neck); hanging, the fingertips at the hips
rather than mid-thigh. The build sliders change widths only (shoulders 4.0-4.9 head widths at their ends; legs
39-41 %). Changing the body is outside this lane: the body is frozen (`tools/giant/fixtures/m10_freeze.json`, the
pipeline's tests), a change re-bakes everything and moves the landmarks the game uses (grips, anchors), and the
vendored target subset has no leg- or arm-length targets. See `docs/plans/FOLLOWUPS.md`.
