# W33look4 — the giant's wardrobe, a fourth look

Milestone M11, part B (the release 0.12.0-m12). The owner looked at the 0.12 preview and asked for one more pass: the
wardrobe must look natural and not clunky. On `pkg/W33look4` from `81eebb1` (the third look lane merged). Every frame
was drawn by Mesa's llvmpipe under Xvfb: the wardrobe sheet (`tools/character_sheet.tscn -- --sheet=b`, b1-b7) before
and after, and a scratch probe of single looks (the cloaks from behind and his right on the Huscarl, the Highland
herdsman, the Wayfarer and alone; the braies from the front close; the beards from the side; the hair from behind; the
chest and armour garments; the boots).

## What changed

### 1. Cloaks fall as one sheet (`giant_garment.build_cape`, `_extend_cloak`, `Wardrobe._cloak_clear`)

From behind the long cloak and the fur cloak showed torn-looking dark notches near the seat and a slit down the
middle, and from the side they stood off as a board. The cut cloth followed the body down to the hips, the cleft of
the buttocks included. Now only the cloth on the shoulders and the upper back is cut from the body; below where it
leaves the back (`hang_below` under the shoulders) a cloak is rows of cloth falling from there to its hem
(`_extend_cloak`, the long cloaks' own extension added), with vertical folds that deepen as it falls and UVs at the
body's density. The falling rows start from the hem's rearmost within a hand either side (no dip at the cleft); the
hanging cloth clears the inner skirts' rows and the braies' seat (`Wardrobe.hang_pts`), each column then standing at
least as far back as any of it above; the long and the fur cloak flare back less. The back's muscles no longer show
below the shoulder blades.

### 2. The braies' front (`flat_front`, `seat_hull`, export `COVER_RAY_OF`)

The nub at the front of the crotch on every preset in braies was the body's groin showing through: the third lane's
seat span left the pelvis region at 94 % covered (under the 97 % that sinks a covered region), and its span pulled the
front of the crotch back between the legs. Now the braies' rays reach 0.25 m for the cover test (the spanned cleft's
skin rays cross it sideways) and the pelvis sinks under them again; the crotch's front keeps its loose place and is
relaxed flat, forward only; the legs are slimmer (looseness 0.015, the back and the sides narrowing faster toward the
knee).

### 3. Beards (`giant_hair.gdshader`, `giant_shell.gdshader`)

- Beard cards: strands drawn across each lock whatever the atlas's mip, a card seen edge-on thinner, less pointed tips,
  locks of more uneven lengths, no darker root (each short card drew its outline on the cheek).
- The short beard: its grey at a little over half the beard's share over every strand, its tips barely lighter, its
  edge thinning out over a wider uneven band (it ended on the mask's line).

### 4. Hair

- The twin braids carry a few short locks combed straight back over the top of the head (`STYLES[...]["cover"]`, their
  own random stream, the style under its 6,000-triangle cap): the locks ran apart to each side and left a ragged scalp
  patch. The scalp under a style takes its hair's shade (`SCALP_SHADE`).
- The crop: its grey is its share over every strand and its strands vary less (it read as a speckled cap).

### 5. The rest of the list

- **Tunic and shirt**: the tunic has a slit at the neck down the breastbone (with its skirt from the third lane and its
  short sleeves); the shirt is long-sleeved and tucked.
- **Jerkin and cuirass**: the jerkin is laced up the front (its two edges stand up as a ridge down the breastbone; an
  opening left the chest uncovered, which the data says it covers); the leather cuirass's lower half is overlapping
  bands. Beard cards seen edge-on keep 65 % of their cover (at 45 % the braided moustache fell under the parts test). Both, the tunic and the vest push and shade along the skin's normals smoothed below
  the shoulders (not over a war belt, which the shell floor guards).
- **Boots** span the gaps between the toes and stand a little further off over them.
- **Plate** is a little less metallic and mirrors more of its sky (near black in the world's light).
- **Cloth dyes** keep 82 % of their saturation and vary a little over the cloth (flat saturated fills).

## Still artificial (the owner's bar)

See `docs/plans/FOLLOWUPS.md`, "From the fourth W33 look lane". In short: the card beards from the side still break
into blocks on the cheeks; the chest garments still show the pectorals faintly; the leg wraps and the greaves are
plain tubes; toes still show at the boots' tips; the hood from behind is a bowl; the top knot is thin; a skirt's front
rows let the thighs through in a stride; the long cloak from the side is still a straight slanted sheet.

## Checks

- **Regeneration**: `build_giant.py --verify --skip-bake`: GIANT VERIFY OK, 88 files bit-exact (115-118 s). No bake
  input changed. `test_giant_tools.py`: 40 tests OK (the shells' 4 mm in four poses, the layering's shares, the hair
  caps).
- **The share** (`env -u XDG_DATA_HOME tools/build_web.sh --version=0.12.0-m12`): `PCK_SIZE ... shipped=31309456
  shipped_mb=29.86 budget_mb=32 parts=3`; `GIANT_SHARE giant_bytes=14799018 shipped=13329516 shipped_mib=12.71 ...
  cap_mb=13.6` (12.75 before).
- **Beyond 120 m** (`test_giant_far_render`): the Wanderer 1,718 primitives and the fullest look 3,084 at 121 m.
- **The full check** on the head (`tools/check.sh --build --slow --gate --giant --web-tools --require
  --strict-times`): `RESULT: 361 suites, 78407 checks, 0 failures`; `TIMES: default 76.4 s | slow 445.1 s | gate
  1235.9 s`, and the strict-times rerun of the default tier 76.3 s: CHECK FAILED on the default tier's 75 s budget
  alone. The base of this lane (`81eebb1`) measured on the same container at the same time: default 77.3 s (the head
  77.4 s, quiet machine): the container is slower after its restart; this lane added no default-tier time. The first
  check had failed `test_giant_look_real` (the jerkin's opening uncovered the chest) and `test_giant_parts_render`
  (the braided moustache 59 px of 60): both fixed before the second.
- **The soak** (120 s autoplay, run on its own since the check stops before it): 41 attacks, 33 hits resolved, 4 enemy
  kills, 2 fence breaks, 7,201 frames, 0 errors - the baseline.
