# The giant asset pipeline (`tools/giant/`)

Every file of `assets/giant/` is generated here from the vendored CC0 MakeHuman/MPFB2 subset
(`mpfb2/`, see `mpfb2/SOURCE.md`) by Blender 5.3 (the `bpy` module), numpy, scipy and Pillow. The
generated files are committed; the game never needs the pipeline to build or run. Nothing under
`assets/giant/` is edited by hand: change the code or its parameters here and regenerate.

## The toolchain

The pipeline runs in one virtual environment shared by every worktree, never inside one:

    export GIANT_VENV=$HOME/.cache/giantborn/giant-venv GIANT_CACHE=$HOME/.cache/giantborn/giant-cache
    tools/giant/setup_venv.sh          # Python 3.13 + requirements.txt (pinned with hashes), about 1.2 GB

`GIANT_CACHE` holds the bake cache (content-addressed by the bake's inputs), the skin's micro-relief
tile (under the hash of its generator) and the audited data wheel; `--verify` reads none of it. `requirements.txt` pins the reference toolchain's Linux x86_64 wheels; on that toolchain every
output regenerates bit-exactly.

## Commands

Run under `nice -n 19` with the venv's Python (Cycles uses two threads, `BAKE_THREADS`):

    $GIANT_VENV/bin/python tools/giant/build_giant.py --all            # regenerate everything
    $GIANT_VENV/bin/python tools/giant/build_giant.py --designs        # one step (see --help)
    $GIANT_VENV/bin/python tools/giant/build_giant.py --verify --skip-bake   # what check.sh --giant runs
    $GIANT_VENV/bin/python tools/giant/build_giant.py --verify               # check.sh --giant-full
    $GIANT_VENV/bin/python tools/giant/build_giant.py --budget         # estimated Web share
    $GIANT_VENV/bin/python -B tools/giant/test_giant_tools.py          # the pipeline's tests
    $GIANT_VENV/bin/python tools/giant/fetch_mpfb2.py [--download]     # audit mpfb2/ against the wheel

After a regeneration, run `tools/check.sh --only=giant_model` (import, rebuild
`scenes/player/giant_model.tscn` from the manifest, import) so the scene's index follows the manifest.

## Steps and outputs

| Step | Code | Writes |
| --- | --- | --- |
| `--body`, `--garments`, `--hair` (one step: one glTF) | `kit/export_game.py` with `giant_body`, `split`, `giant_garment`, `giant_hair` | `giant.glb`: `Body_Head`, `Body_Torso`, `Body_Limbs` (the body split at the neck, shoulders and hips, every cut capped, the 16 region ids in `COLOR_0.r`), `Eyes`, `Hair_long_back`, `Hair_crop`, `Beard_full`, `Beard_short`, the garments (`Garment_braies_core`/`_limbs`, `Garment_belt`, `Garment_tunic_core`/`_limbs`, `Garment_jerkin`, `Garment_bracers`, `Garment_boots`, `Garment_furs`); the landmarks and the body's hash go into the manifest |
| `--bake` | `kit/bake.py` (Cycles, 1024 px, 2 threads, seed 0) | into `GIANT_CACHE` only: the cheap passes (albedo, roughness, normal, masks, regions, rest position and normal; about 1 minute here) and the expensive ones (AO, thickness; about 2.5 minutes here, 13 on a busy machine) |
| `--designs` | `kit/designs.py` | `designs.png`: the 17 designs of the floor as 512 x 512 RGBA layers stacked vertically (imported as a 2D texture array) |
| `--pack` | `kit/pack.py` | `tex/` (albedo, normal, ORM, masks at 512 px), `tex_hi/` (normal and ORM at 1024 px), `hair_atlas.png`, `cloth_weave.png`, `cloth_leather.png`, `cloth_fur.png` |
| `--clips` | `kit/clips.py` (P43) | `giant_clips.glb` |

`assets/giant/manifest.json` records every output (step, input hash, sha256, size, whether Cycles
pixels reach it), the toolchain, the bake keys, the body's hash and the giant index that
`tools/builders/giant_model.gd` writes into `scenes/player/giant_model.tscn`.

## Conventions the game relies on (plan M10 §2.5, §2.6)

- The model is built at the stage-1 height, 3.6576 m, facing +Z in the glTF; `GiantModel` turns it.
- Render layers: head, eyes, hair and beards 3; torso and garment cores 2; limbs and limb garment
  parts 1. Every cut loop is capped (region 15) on both sides, so no part is hollow seen from inside.
- Regions are per vertex in `COLOR_0.r = (id + 0.5) / 16`, decoded with `int(COLOR.r * 16.0)` (never
  rounded): 0 scalp, 1 face, 2 neck, 3 chest, 4 belly, 5 upper back, 6 lower back, 7 pelvis, 8 upper
  arm, 9 forearm, 10 hand, 11 thigh, 12 knee, 13 shin, 14 foot, 15 caps.
- The design array's packing rule: within a layer the texels of any region carry at most one design in
  R, G and B plus one in A; the four scars fill a layer of their own (the shader's `scar_layer`). Design
  values are quantized to the S3TC block's levels (0, 1/3, 2/3, 1) so compression keeps them.
- After W25 the body mesh, the skeleton, the regions and the landmarks are frozen for M10 (decision 9):
  the manifest's `body_hash` changes only with an orchestrator's decision.

## Adding content (P43, P46)

New hair or beard styles: `kit/giant_hair.py` `STYLES` and `STYLE_ORDER`. New designs:
`kit/designs.py` `CATALOGUE` and `DRAW` (a function that returns a mask over the bake's texels).
New garments: `kit/giant_garment.py`. Then `build_giant.py --all` (or the affected steps), the scene
rebuild, and `check.sh --giant --require`.
