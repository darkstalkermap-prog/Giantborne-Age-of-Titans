# W33look3 — the giant's wardrobe, looked at a third time

Milestone M11, part B (the release 0.12.0-m12), before the owner's review of the wardrobe sheet. The third look lane
after `docs/systems/W33look.md` and `docs/systems/W33look2.md`, on `pkg/W33look3` from `47a0af6`, with the Gate B
fixes (`6bdf06a`) merged in before its last check. Every frame was drawn by Mesa's llvmpipe under Xvfb (no GPU): the
wardrobe sheet (`tools/character_sheet.tscn -- --sheet=b`, pages b1-b7) before and after, and a scratch probe of single
looks at the creator's framings (the legs and the seat from the front, behind and his right; the paints and the scars
at their framings; the beards from the front and the side; the jaw without a beard at chin 0 and -1; the cloaks from
behind and the side).

## What changed

### 1. Braies as loose wool breeches (`tools/giant/kit/giant_garment.py`: `build_braies`, `drape_breeches`, `seat_hull`)

The braies read as puffy bloomers: ballooned at the hips and thighs, the cleft and cheeks moulded into the cloth from
behind, a quilted grid of bands over them and a hem pulled in like an elastic's. Four causes, four fixes:

- **The weave drew ten times its size.** The braies are cut from MakeHuman's tights helper, whose UVs are about a
  tenth as dense as the body's (0.031 against 0.347 UV a metre): the 96-tile weave's normal map drew as broad bands,
  the "quilted" or "checker" pattern of the earlier reviews. The braies' UVs are scaled to the body's density
  (`BRAIES_UV_SCALE`).
- **The cloth shaded with the skin's normals.** Every garment vertex took the normal of the skin vertex it stands on
  (the push line of the layering); the braies drew the buttocks and the thighs' muscles on cloth that spans them. The
  legs' garments (the innermost slot: nothing pushes them) now export their own normals, averaged over a few rings
  (`export_game.OWN_NORMAL_SLOTS`, `smooth_normals`).
- **The shape.** An even ease gathered into the waistband (no sine bulge mid-thigh); the seat spanned across the cleft
  (each 2 cm slice's convex hull, straight back above the crotch, each leg's hull below it); the back falling straight
  from the seat's fullest and the sides from the hips' widest, narrowing only a little toward the knee; the drape
  relaxed and untangled where it would turn a face over; a few narrow fold lines down each leg; a plain hem.
- **Their skin and their cut.** Each vertex takes the weights of the skin vertex under its place before the drape, and
  the torso / limbs split runs round each thigh under the crotch (`export_game.SPLIT_BY_HEIGHT`): by weights it ran up
  the seat and its cap's fan showed through the spanned cloth.

### 2. Skirts that hang (`Wardrobe.add_skirt`)

A shell pushed along the skin's normals cannot hang between the legs: the kilt read as wide shorts from behind, the
tunic's skirt as briefs (the Iron Veteran), the scale coat showed the buttocks. A skirt is now the hips' shell above
the crotch and rows of cloth hanging from its lower loop to the hem, each column falling from the loop's convex hull
straight down and a little out, never nearer the legs than a margin outside the convex hull of their slice (and of the
inner slots' envelopes over them and the inner skirts' rows), never tucking in under the row above; its own UVs at
the body's density round and down. The rows take their column's weights, eased toward the thigh on their side toward
the hem. Made so: **the kilt** (to the knee, nine knife pleats), **the tunic** (to mid-thigh), **the mail hauberk**
(standing a little more off the seat), **the scale coat**, and **the loincloth** (its band and two flaps: the front a
hand under the crotch, **the back to mid-thigh**: the Berserker is covered behind). A skirt's band spans the seat as a
coat's did; the shirt's hem spans it too (`add_shell(seat_z=...)`).

### 3. War paint and scars (`assets/shaders/giant_skin.gdshader`)

- **Paint** is a pigment smeared on by hand: its border is the design's coverage sampled a little off its place by a
  smooth noise and cut at a noisy level (smeared, uneven), semi-opaque with brush streaks across the face, the skin
  showing at the pores, its tone varying along the strokes, matte (rough, little specular). Chalk is off-white
  (`set_paintcolor.json`); ochre and woad keep their dyes.
- **Scars** draw their coverage's middle as healed tissue (narrower: the feathered edge is a rim), a little paler
  and pinker than the skin, with a thin darker rim; the design array is unchanged, so every floor of `test_hair_render`
  holds (the brow scar at its 4 cm rule, the back lash, the forearm slash, the knuckles).

### 4. Beards, stubble, the jaw

- **The short beard** (a shell) keeps a beard's grey strands near its colour and its tips barely lighter: it read as a
  grey speckled mask (`giant_shell.gdshader`).
- **Stubble** is fine dark points of the beard's colour over the skin (it tinted the lower face orange-red); under a
  beard's cards the skin keeps the beard's shade.
- **The jaw's dark patch** and **the chin key's wedge** were the shadow proxy's hard shadow (the proxy has no face
  keys and a coarse jaw); the neck and the jaw's underside now take a shadow softly (`NECK_SHADOW_SOFT`), and the jaw's
  and the chin's keys fade out down the neck (`export_game.FACE_KEY_NECK_FADE`). (Moving the proxy's jaw in was tried
  and cast a worse patch.)
- **Beard cards** break into locks of their own lengths near the tips and vary a little darker (`giant_hair.gdshader`,
  `BEARD_LOCKS`). Deeper cuts let the skin show through the full beard more than M10's (the hair test's scalp measure),
  so the chops still read as blocks from the side: partly done.

### 5. Cloaks (partly)

The short cape now falls three rows past the seat (it ended in a roll at the hips); the cape's and the long cloak's
folds run from where the cloth leaves the back, deeper and fewer. Below the shoulders the cloaks push and shade along
the skin's normals smoothed over their own mesh. Above that they still use the skin's (the shoulders' garments'
layering reads them; smoothing there brought the raised-arm pose under the shell test's 4 mm), so the upper back's
muscles still show faintly; a cloak's cloth over the shoulders' sides keeps 3 mm more (`CLOAK_ARM_MARGIN_M`).

### 6. Not done

Item 6 of the review (tunic and shirt, jerkin and cuirass alike; leg wraps' bands and greaves' ridge; toes through the
boots' tips; the hood from behind; the twin braids' parting; the top knot; plate in the world's light). The rows are in
`docs/plans/FOLLOWUPS.md`.

## The measure that changed

`export_game.shell_distances` does not measure **a skirt's hanging rows**, as it never measured a cloak's hanging
cloth: they hang over no skin vertex of their own, and mapped onto the nearest they read as standing off the thighs
(and every outer shell over them as intersecting). The builder keeps them clear (above). Every shell pair the test
measures keeps its 4 mm floor in the four poses. A trophy hangs at the skin's widest point at the hip (the skirts'
seats moved the covered ring's widest point behind it).

## Checks

- **Regeneration**: `build_giant.py --verify --skip-bake`: GIANT VERIFY OK, 88 files regenerated bit-exact (118-123
  s). No bake input changed (the design array was drawn again with its own code unchanged). `test_giant_tools.py`: 40
  tests OK; the shells keep their 4 mm in the four poses, the belt over the braies alone takes 0.26 of its push at
  most, a shirt does not push a hauberk's skirt, the trophies move out over the braies.
- **The share** (`env -u XDG_DATA_HOME tools/build_web.sh --version=0.12.0-m12`): `PCK_SIZE ... shipped=31354304
  shipped_mb=29.90 budget_mb=32 parts=3`; `GIANT_SHARE giant_bytes=14827020 shipped=13373132 shipped_mib=12.75 ...
  cap_mb=13.6` (12.79 before). `build_giant.py --budget` estimates 13.24 MiB.
- **Beyond 120 m** (`test_giant_far_render`, 1920x1080): the Wanderer 1,718 primitives and the fullest look 3,105 at
  121 m (1,722 / 3,121 before); the worst slot look's far levels 3,627 triangles (bound 3,800).
- **The full check** on the merged head (`tools/check.sh --build --slow --gate --giant --web-tools --require
  --strict-times`): `TIMES: default 69.6 s | slow 455.8 s | gate 1222.8 s`; `RESULT: 361 suites, 78407 checks, 0
  failures`; CHECK PASSED. The soak: 41 attacks, 33 hits resolved, 4 enemy kills, 2 fence breaks, 7,201 frames, 0
  errors - the baseline. Its first run on the merge failed two rendered suites, fixed before the second:
  `test_giant_parts_render` (the kilt's limbs mesh drew 44 pixels: a split garment's skirt rows now go to its limbs
  mesh) and `test_skin_world_render` (the short beard's blue channel left the card beard's: its grey is now its share
  over every strand, as the cards' blend reads at a distance).
- **No test changed.** `test_hair_render` (every scar at its floor, the full beard's scalp measure), the stack check
  and `test_wardrobe_render` pass.

## Frames

The lane's captures (not committed): the sheet's seven pages before and after, and the scratch probe's single looks
named above (the seat, the skirts, the Berserker's and the Iron Veteran's backs, the paints and scars, the beards and
the jaw, the cloaks).
