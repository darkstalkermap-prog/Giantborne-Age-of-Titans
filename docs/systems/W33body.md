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

**Why the shoulders stay at 3.1 head widths, not 2.6-2.9.** The game's tip matching (`TipMatching`, plan M10 §2.9)
holds the visible weapon within 15 degrees of the tested swing; its arm is the gameplay's (pivot (0.82, 2.9)·k, a
1.5·k arm), unchanged. With the shoulder joints drawn in by 9 cm (2.9 head widths) 73 of 1,004 samples broke it, at
the ends of the light arcs; the joints are now 1 cm narrower than M10's and the shoulders' slimming is in the deltoids'
bulk instead. For the same reason the arms are 1.10 times longer, not more (at 1.16 and 1.22 the grip overshot the
arcs' ends): the fingertips hang a quarter of a head above mid-thigh.

## Fitted to it

- The garments: the waist is the hip joints' height plus `WAIST_OVER_HIP` (it was the M10 body's 1.535 m); a
  cloak's collar band `COLLAR_DROP_M` lower (the longer neck carries the head's weights down); a coat's seat span
  leaves out the hanging arms; the jerkin's hem spans the small of the back over a tunic's band; the cape lets go to
  its chains 0.31 m under the shoulders (0.375); the boots have a toe box (each cross-section's hull, eased).
- The landmarks follow (grips mirrored exactly); the animation brief's shoulder and reach in
  `tests/integration/test_giant_assets.gd` moved to the new body's ((0.404, 2.930, -0.030), 1.307) with the reason.
- The clips are regenerated: the gaits still cover the brain's stride (3.2 m a cycle) with no slide; with the longer
  legs the walk's pelvis drops less.
- A full regeneration (the bake, the designs, the pack, the clips); the freeze fixture re-taken from the new files and
  the body hash in `test_giant_tools.py`.
- The sleeveless vest now covers the back (`set_garment.json`): on the new body it does.

## Checks

- **Regeneration** (`--giant-full`, every bake pass): GIANT VERIFY OK, 88 files bit-exact (225 s);
  `test_giant_tools.py`: 40 tests OK (the freeze re-taken, the shells' 4 mm in four poses, the layering).
- **The share**: `PCK_SIZE ... shipped=31616620 shipped_mb=30.15`; `GIANT_SHARE ... shipped=13634556
  shipped_mib=13.00` (12.88 before: the re-baked maps).
- **The soak** (120 s): 41 attacks, 33 hits resolved, 4 enemy kills, 2 fence breaks, 7,201 frames, 0 errors - the
  baseline, unmoved.
- **The full check** (`--build --slow --gate --giant --giant-full --web-tools --require`): `TIMES: default 65.7 s |
  slow 424.9 s | gate 1231.9 s` (the base `dcb23da`'s default tier the same hour: 68.4 s); `RESULT: 361 suites,
  78412 checks, 21 failures`. **Not passed.** The failures:
  - the creator's framings (`GiantPreview.FRAMINGS`, `ui/screens/creator/giant_preview.gd`) are fixed stage-1
    points of the M10 body: the chest, the back's designs, the shoulders and the arms are 8-15 cm lower now, so the
    rendered checks that measure a design or the skin in its framing read less than their floors
    (`test_hair_render`: the back lash, the granite veins, the lightning tree, the claw stripes, the chest claws' 4 cm
    rule, the crop's and the long hair's measures; `test_appearance_render`: the circlet braid, the claw stripes;
    `test_skin_tone_render`: the default swatch's drawn tone; `test_skin_world_render`: the face's terminator, the
    chieftain's beard). This lane may not edit `ui/screens/creator/**`; the framings' new heights, moved with the
    landmarks, are in `docs/plans/FOLLOWUPS.md`.
  - `test_skinned_rig_motion`: the weapon arm's elbow crosses the middle by 0.15-0.18 m at stage 1 (sword, hammer,
    axe) and stage 3 (axe), over its 0.15: the shoulders are 1 cm narrower and the shoulder line lower against the
    gameplay arm.
  - `test_giant_parts_render`: the braided moustache and the mutton chops draw 50-51 pixels in their framing (60).
