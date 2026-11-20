# W33body — the giant's proportions

Milestone M11, part B (the release 0.12.0-m12). The owner at checkpoint B: "The proportionality needs to be fixed
especially with the body legs and shoulders they all need to be proportionate that looks natural whether they are
6 foot or 60ft". The orchestrator lifted the M10 body freeze for this lane (`docs/DECISIONS.md`, checkpoint B,
decision 4). On `pkg/W33body` from `dcb23da`.

## Measured

On the human-scale phenotype (`giant_body.BodyData`; the stage-1 model is it scaled to 3.6576 m), the arms hung
straight down from the shoulder joints (the rest pose is an A-pose), the heads by the chin-to-crown height, the head
widths at the ears, the crotch the lowest midline point of the torso:

| Measure | Before | After | Target |
| --- | --- | --- | --- |
| Height in heads | 8.35 | 7.94 | 7.5-8 |
| Legs (crotch to floor) / height | 40.0 % | 47.3 % | 47-50 % |
| Torso (crotch to shoulder joint) / legs | 1.06 | 0.69 | - |
| Shoulders (bideltoid) in head widths | 4.15 | 3.12 | 2.6-2.9 (see below) |
| Shoulders / hips | 1.58 | 1.51 | 1.35-1.45 |
| Neck: chin over the trapezius, heads | 0.05 | 0.21 | about 0.33 |
| Fingertips against mid-thigh, heads (+ above) | +0.70 | +0.23 | 0 |
| Hand (wrist to fingertip), heads | 1.01 | 0.71 | 0.75 |
| Foot length, heads | 1.37 | 1.18 | a little over 1 |
| Build both -1 / both +1: shoulders, head widths | 3.91 / 4.47 | 3.02 / 3.23 | about 2.4 / 3.2 |
| Build both -1 / both +1: legs | 40.7 / 39.3 % | 47.9 / 46.7 % | - |

Silhouette widths from the front at the creator's full framing (the widest at the shoulders over the head with its
hair or helm): the Wanderer 3.36 to 2.48, the Bronze Lord's mantle 2.41 to 1.99, the Huscarl's pauldrons 3.71 to
3.15, the Berserker's mantle 4.29 to 3.16, the Northern Chieftain's furs 3.62 to 2.89 (the bar 3.4).

**Every stage is the same body.** The growth profiles scale the model uniformly (`GiantPreview._apply_stage_scale`,
`ActorRig`: `scale = Vector3.ONE * k`, k the stage's height over 3.6576 m); nothing per stage stretches a bone. The
stage-1 and stage-6 world shots in the captures show it.

## What changed (`tools/giant/kit/giant_body.py`, `PROPORTIONS`, `proportioned()`)

The vendored MakeHuman targets have no limb-length targets, so the morphed mesh (the body, the helpers, the eyes:
every vertex) is reshaped before the joints are read from it, and the skeleton follows: the legs 1.30 times longer and
the torso 0.85 times, the neck 7 cm longer over the shoulders' line and the trapezius drawn down 3.5 cm, the head 1.12
times about the neck joint, the deltoids' and the upper arms' bulk drawn toward the arm's line (0.75), the arms 1.10
times longer from the shoulder with the hands 0.8 times about the wrist, the thighs' outer bulge eased. The model is
then scaled to the stage-1 height as before, so each stage's height is unchanged. The right side's joints are the
left's mirror, so the reshape is symmetric. `giant_parts.BUILD_SHOULDER_EASE` takes 85 % of the build sliders' push
off the shoulders, the upper arms and the trapezius (at +1 they reached 4.5 head widths and buried the neck). Saves are
unchanged: a slider's value is a share of the build push, which now lands on the new body.

**Why the shoulders stay at 3.1 head widths, not 2.6-2.9 (accepted by the owner, 2026-11-20: "Keep as is").** The game's tip matching (`TipMatching`, plan M10 §2.9)
holds the visible weapon within 15 degrees of the tested swing; its arm is the gameplay's (pivot (0.82, 2.9)·k, a
1.5·k arm), unchanged. With the shoulder joints drawn in by 9 cm (2.9 head widths) 73 of 1,004 samples broke it, at
the ends of the light arcs; the joints are now 1 cm narrower than M10's and the shoulders' slimming is in the deltoids'
bulk instead. For the same reason the arms are 1.10 times longer, not more (at 1.16 and 1.22 the grip overshot the
arcs' ends): the fingertips hang a quarter of a head above mid-thigh.

## Fitted to it

- The garments: the waist is the hip joints' height plus `WAIST_OVER_HIP` (it was the M10 body's 1.535 m); a
  cloak's collar band `COLLAR_DROP_M` lower (the longer neck carries the head's weights down); a coat's seat span
  leaves out the hanging arms; the jerkin's hem spans the small of the back over a tunic's band; the cape lets go to
  its chains 0.31 m under the shoulders (0.375); the boots have a toe box (each cross-section's hull, eased) over the
  foot smoothed into one round form (`toe_foot`, lifted to clear the real toes), and over the toes they shade with
  their own smoothed normals where the skin's turn away (`export_game.OWN_NORMAL_EASED`: the skin's pointed into the
  gaps between the toes and drew bright crumples and dark specks, read as tears; folded triangles 468 to 281 of
  2,500, the rest the between-toe faces squeezed to slivers, in `docs/plans/FOLLOWUPS.md`).
- The build sliders: a part's cut cap keeps the body's normals on its rim and takes no build push at its centre (at
  -1 the shoulders' caps pushed out along their own faces: spikes); the shadow proxy insets a little more at the
  build's extremes (dark patches at -1); `giant_parts.BUILD_CALF_EASE` takes half the push off the calves (a bulge at
  +1).
- The hair and the beards' cards scale with the head (`giant_hair`: the head's 1.12): the braided moustache and the
  mutton chops drew 50-51 px in the parts check's framing (60), now over it.
- The weapon arm's elbow: `TipMatching.CROSS_POLES` lowered to y -0.07 and `CROSS_BLEND_M` 0.35 m (the elbow crossed
  the middle by 0.15-0.18 m on the new shoulder line); `test_skinned_rig_motion` and `test_giant_motion_render`
  pass.
- The landmarks follow (grips mirrored exactly); the animation brief's shoulder and reach in
  `tests/integration/test_giant_assets.gd` moved to the new body's ((0.404, 2.930, -0.030), 1.307) with the reason.
- The clips are regenerated: the gaits still cover the brain's stride (3.2 m a cycle) with no slide; with the longer
  legs the walk's pelvis drops less.
- A full regeneration (the bake, the designs, the pack, the clips); the freeze fixture re-taken from the new files and
  the body hash in `test_giant_tools.py`.
- The sleeveless vest now covers the back (`set_garment.json`): on the new body it does.

## Checks

- **Regeneration** (`--giant-full`, every bake pass): GIANT VERIFY OK, 88 files bit-exact (222 s);
  `test_giant_tools.py`: 40 tests OK (the freeze re-taken, the shells' 4 mm in four poses, the layering).
- **The share** (`tools/build_web.sh --version=0.12.0-m12`): `PCK_SIZE ... shipped=31748820 shipped_mb=30.28
  budget_mb=32`; `GIANT_SHARE ... shipped=13767408 shipped_mib=13.13 cap_mb=13.6` (12.88 before: the re-baked maps).
- **The far primitives** (`test_giant_far_render`, beyond 120 m): the Wanderer 1,636, the fullest look 2,914 (under
  4,000).
- **The soak** (120 s): 41 attacks, 33 hits resolved, 4 enemy kills, 2 fence breaks, 7,201 frames, 0 errors - the
  baseline, unmoved.
- **The full check** (`--build --slow --gate --giant --giant-full --web-tools --require`): `TIMES: default 74.7 s |
  slow 474.4 s | gate 1246.5 s` (the base `dcb23da`'s default tier the same hour, run as the check runs it: 75.4 s,
  0 failures); `RESULT: 361 suites, 78408 checks, 14 failures`. **Not passed.** Every failure is a rendered check
  that measures the head, a design or the skin in one of the creator's framings (`GiantPreview.FRAMINGS`,
  `ui/screens/creator/giant_preview.gd`), fixed stage-1 points of the M10 body: the chest, the back's designs, the
  shoulders and the arms are 8-15 cm lower now. `test_hair_render` (the back lash, the granite veins, the lightning
  tree, the claw stripes, the chest claws' 4 cm rule, the crop's and the long hair's measures), `test_appearance_render`
  (the claw stripes), `test_skin_tone_render` (the default swatch's drawn tone), `test_skin_world_render` (the
  faces' terminator, the chieftain's beard). The owner approved moving the framings' targets in this lane
  (2026-11-20), but the permission system refused the edit to `ui/screens/creator/giant_preview.gd`; the new heights,
  moved with the landmarks, are in `docs/plans/FOLLOWUPS.md`.
- Fixed since the first full check (21 failures): the weapon arm's elbow (`test_skinned_rig_motion`) and the braided
  moustache and mutton chops (`test_giant_parts_render`).

## W33frame: the creator's close-ups and the rendered checks on the new body

On `pkg/W33frame`, from `d30e7e6` (the framings' targets moved with the landmarks; the owner approved editing
`GiantPreview.FRAMINGS` on 2026-11-20). Each of the 15 failures was traced by drawing the same probe on this tree and
on `dcb23da` (the M10 body, the same code otherwise) and comparing the frames.

**The framings.** The torso, the arms and the hands are smaller at stage 1 on the new body (the legs take more of the
same height): at the chest framing the torso was 0.78 of its M10 width in the frame, the hand 0.8. The chest
(2.4 to 2.0 m, target 2.68), back_design (2.7 to 2.25, 2.62), shoulders (2.6 to 2.3, 3.02: the head was cut), arms
(2.7 to 2.55) and hand framings (1.35 to 1.1) come closer so the subject fills the frame as on the M10 body; every
other framing composes as before (face centred, hair from behind, waist, legs, shins, feet, neck, upper, lower,
hair_close, outfit, head, eyes; looked at side by side with the M10 body's). The arms' and hands' targets in the
table are fallbacks (they aim at the posed arm); they now hold the new body's.

**The designs.** Two real defects, in `tools/giant/kit/designs.py` (designs.png regenerated with `--designs`):

- The strokes "4 cm at stage 1" were 2.7 cm on the human-scale body times M10's 1.4947; the new body is taller at
  human scale (x 1.3594 to stage 1), so every bold stroke drew 3.7 cm. `BOLD` now follows the body's own scale
  (`bold_half`): 4 cm at stage 1 on any body.
- The granite veins were a band of a noise field's value round 0.5; where the lattice fell on the new arms the field's
  median was 0.42, so the band crossed it rarely (352 px in the arms framing against 1,071 on the M10 body; 5,275
  texels against 8,443). They are now the field's median iso-line at an even stroke width (the offset over the
  gradient, in metres): 900 px.

**The probes.** The look probe's chest patch was a fixed stage-1 point (2.78 m), on the collarbones of the new body
(228/168/139 against the swatch's 220/160/131); it follows the landmarks now (217/159/130). The shell check compared
the shell's colour with the whole card style's: the card beards grew with the head (W33body) and their longer tips
over the lit chest lightened the card's mean (the Northern Chieftain's blue 34.8 to 37.1) while in the shell's area
it held (31.4 to 31.1); the card's colour is read in the shell's pixels now.

**References re-derived** (each with its reason beside the number):

- The face's hard steps (`test_skin_world_render.STEP_MAX`): the face's own steps did not change (the Wanderer's in
  the head's rows 125 against 131); the share's denominator did (22,537 skin pixels at the face framing, 29,670 on the
  M10 body, and the upper arms' outlines now inside the frame). Wave-30's subsurface lookup (the hard terminator's
  cause) put back on this tree reads 0.0154 / 0.0217 / 0.0080 against the fixed 0.0106 / 0.0170 / 0.0067; the
  ceilings sit halfway (0.013, 0.0194; the Iron Veteran's 0.0085 stands).
- The claw stripes in the face framing: the cheek's stripes read as before (75 to 78 px), the chest's went under the
  frame with the longer neck (234 to 57): `GATE_A_FRAMED_SHARE` 0.4 of M10's, the marks' option floor 0.0009 (half
  the smallest share, 0.0018; 0.0040 on the M10 body).
- Three hair measures join `KNOWN_MISSES` (they beat M10's on the M10 body): the crop's face scalp share (its front
  edge a pixel above the scalp tint's hairline), the long hair's outline from behind and the long braids' at the face
  (both hang straight past the narrower shoulders and the longer neck). Five others now beat M10's and left the list.

**Checks.** The full check (`--build --slow --gate --giant --web-tools --require`): `TIMES: default 82.6 s | slow 468.7 s | gate 1273.3 s` (the default tier over its 75 s on this machine, a warning, as before), `RESULT: 361 suites, 78409 checks, 0 failures`, GIANT VERIFY OK (88 files bit-exact), CHECK PASSED. The soak (120 s): 41 attacks, 33 hits resolved, 4 enemy kills, 2 fence breaks, 7,201 frames, 0 errors - the baseline, unmoved. The character sheets B1-B7 drawn and looked at (B4, B5, B6 compose; B6's face close-ups are the sheet's own camera, the crown near the top edge). The designs.png grew 561 bytes.
