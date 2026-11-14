# The giant's provenance

Every file in this folder (besides this note and the `.import` settings) is **generated** by the
committed pipeline in `tools/giant/` (`tools/giant/README.md`) and listed in `manifest.json` with the
step that wrote it, the hash of that step's inputs, its sha256 and size, and the toolchain it was
built with. `build_giant.py --verify` regenerates every file into a temporary folder and compares it
with the manifest; `tools/check.sh --giant` runs it in every package that touches the giant. Nothing
here is edited by hand.

## Inputs

- **MakeHuman / MPFB2 data, CC0 1.0** (`tools/giant/mpfb2/`, 133 files; `tools/giant/mpfb2/SOURCE.md`).
  The giant's body is the hm08 base mesh morphed by 122 MakeHuman targets (the kit's `GIANT_MACRO` and
  `GIANT_MODIFIERS`: a heavy-set, very muscular man of about 42, tallest and ideal proportions, with a
  weathered face), scaled to the stage-1 height of 3.6576 m. The skeleton is MPFB2's "game_engine" rig
  (53 bones) built from the morphed body's joint cubes, and the skin weights are its CC0 weights. Six
  MPFB2 region mask images (lips, ears, eyelids, nails, the inside of the mouth) shape the skin's
  detail. The base mesh's own header states that it "was explicitly released as CC0 in september
  2020"; the weights file carries `"license": "CC0"`. The files were copied as data, byte for byte,
  from the folder `anny/data/mpfb2/` of the Python wheel `anny-0.6.2-py3-none-any.whl` (sha256
  `bad70bdc2be0dfa9880d60129c3a1339678f08f493184f637dc2825c3e27b8d2`); none of that wheel's code
  (Apache-2.0) was copied or run, and `tools/giant/fetch_mpfb2.py` audits the copy against the wheel.
- **Nothing else.** No other mesh, image, scan or texture enters the pipeline.

## Generated here (original work of the project)

| Files | Made by | How |
| --- | --- | --- |
| `giant.glb` | `tools/giant/kit/export_game.py`, `giant_body.py`, `split.py`, `giant_garment.py`, `giant_hair.py` | The body split into head, torso and limbs with every cut capped and 16 body regions in the vertex colour; both eyes as low-poly spheres; seven garments (braies and belt from the base mesh's "tights" helper; tunic, jerkin, bracers, boots and furs cut from the body surface by bone-weight regions and pushed out along the normals, carrying the body's weights); four hair and beard styles as cards grown from the kit's strand generator on the scalp and beard masks. Exported by Blender 5.3 (`bpy`) as one glTF on one armature |
| `tex/*.png`, `tex_hi/*.png` | `tools/giant/kit/bake.py`, `giant_skin.py`, `skin_textures.py`, `pack.py` | Cycles bakes (1024 px, 2 threads, seed 0) of the kit's procedural skin - colour variation, sun weathering, redness, freckles, pores and furrows from a generated micro-relief tile, wrinkles, veins, knuckles, lips, nails - from the subdivided body onto the base mesh's UVs: albedo at a neutral tone, tangent normal, roughness, ambient occlusion, inside-AO thickness, and the stubble, scalp, brow and lip masks; packed at 512 px (`tex/`) and 1024 px (`tex_hi/`), resized one channel at a time |
| `designs.png` | `tools/giant/kit/designs.py` | The floor's 17 designs (8 tattoos, 2 war paints, 4 scars, 3 ancestry marks) drawn as distance fields in 3D on the rest pose from the bake's rest position, normal and region maps, packed into 512 px RGBA layers under the packing rule |
| `hair_atlas.png`, `cloth_weave.png`, `cloth_leather.png`, `cloth_fur.png` | `tools/giant/kit/pack.py` | Strands drawn in numpy (coverage, brightness, strand id, root to tip); tileable weave, leather and fur detail maps (a normal from a height field and an albedo detail) |

The code of `tools/giant/kit/` was written for this project (ported from the project's own M10
research kit); it reads the MakeHuman data's documented formats and rules and copies no third-party
code.

## Tools (not redistributed)

Blender 5.3 as the `bpy` Python module (GPL-3.0-or-later), numpy and scipy (BSD-3-Clause), Pillow
(MIT-CMU) and OpenEXR (BSD-3-Clause) build these files; none of them is part of the game. Their
versions are pinned in `tools/giant/requirements.txt` and recorded in `manifest.json`.

**Licence:** the project's own; the owner chooses it (the CC0 inputs fit any).
