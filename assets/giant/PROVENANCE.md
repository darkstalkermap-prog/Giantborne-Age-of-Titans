# The giant's provenance

Every file in this folder (besides this note and the `.import` settings) is **generated** by the
committed pipeline in `tools/giant/` (`tools/giant/README.md`) and listed in `manifest.json` with the
step that wrote it, the hash of that step's inputs, its sha256 and size, and the toolchain it was
built with. `build_giant.py --verify` regenerates every file into a temporary folder and compares it
with the manifest; `tools/check.sh --giant` runs it in every package that touches the giant. Nothing
here is edited by hand.

## Inputs

- **MakeHuman / MPFB2 data, CC0 1.0** (`tools/giant/mpfb2/`, 137 files; `tools/giant/mpfb2/SOURCE.md`).
  The giant's body is the hm08 base mesh morphed by 122 MakeHuman targets (the kit's `GIANT_MACRO` and
  `GIANT_MODIFIERS`: a heavy-set, very muscular man of about 42, tallest and ideal proportions, with a
  weathered face), scaled to the stage-1 height of 3.6576 m. The skeleton is MPFB2's "game_engine" rig
  (53 bones) built from the morphed body's joint cubes, and the skin weights are its CC0 weights. Four
  more of the same universal muscle-and-weight targets (the giant's own with the muscle, or the weight,
  back at its average) give the build sliders' two directions: their difference from the giant's body,
  projected on each vertex's normal, is stored in the meshes' vertex colour (P48). Six
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
| `giant.glb`, `parts/*.glb` | `tools/giant/kit/export_game.py`, `giant_body.py`, `split.py`, `giant_garment.py`, `giant_hair.py`, `giant_parts.py` | The body split into head, torso and limbs with every cut capped and 16 body regions in the vertex colour; both eyes as low-poly spheres; ten garments (braies and belt from the base mesh's "tights" helper; tunic, jerkin, bracers, boots, furs, cape, leg wraps and pauldron cut from the body surface by bone-weight regions and pushed out along the normals, carrying the body's weights); nine hair and beard styles as cards grown from the kit's strand generator on the scalp and beard masks, their braids built from the same cards. Exported by Blender 5.3 (`bpy`) as one glTF on one armature. Since P48 (M11): `giant.glb` holds the skeleton, the body, the eyes and a shadow proxy (the body decimated to about 2,500 triangles by Blender's decimate modifier, a little inside the skin); every hair, beard and garment mesh is a glTF of its own under `parts/` on the same skeleton. The skeleton has 18 more bones placed by the kit from the body's landmarks (chains for hair, beard and cape); the cards are weighted along their length to them, and the cape, cut from the body's back as before, hangs free on its three chains |
| `giant_clips.glb` | `tools/giant/kit/clips.py` (on the rig that `export_game.py` and `giant_body.py` build) | The idle, walk, run, airborne and death clips and the four one-frame hand poses (grip and open, right and left), every key computed in code on the same 53-bone skeleton: the feet planted from the body's speed, a two-bone solve for the legs, breathing and sway from closed formulas. No motion capture and no outside animation data. Since P48 the library holds 28 clips: the sprint, two turns, the stomp, the landing, the brace, the roar, four flinches, six weapon grips, the two-handed carry and the first-person rest are computed the same way, and a clip that keys a few bones is written with those bones' tracks only |
| `tex/*.png`, `tex_hi/*.png` | `tools/giant/kit/bake.py`, `giant_skin.py`, `skin_textures.py`, `pack.py` | Cycles bakes (1024 px, 2 threads, seed 0) of the kit's procedural skin - colour variation, sun weathering, redness, freckles, pores and furrows from a generated micro-relief tile, wrinkles, veins, knuckles, lips, nails - from the subdivided body onto the base mesh's UVs: albedo at a neutral tone, tangent normal, roughness, ambient occlusion, inside-AO thickness, and the stubble, scalp, brow and lip masks; packed at 512 px (`tex/`) and 1024 px (`tex_hi/`), resized one channel at a time |
| `designs.png` | `tools/giant/kit/designs.py` | The catalogue's 29 designs (16 tattoos, 4 war paints, 6 scars, 3 ancestry marks) drawn as distance fields in 3D on the rest pose from the bake's rest position, normal and region maps, packed into 512 px RGBA layers under the packing rule |
| `hair_atlas.png`, `cloth_weave.png`, `cloth_leather.png`, `cloth_fur.png` | `tools/giant/kit/pack.py` | Strands drawn in numpy (coverage, brightness, strand id, root to tip); tileable weave, leather and fur detail maps (a normal from a height field and an albedo detail) |
| `tex/skin_lut.png`, `tex/curvature.png`, `shell_strands.png`, `cloth_metal.png` (P51, M11) | `tools/giant/kit/pack.py` | The skin's pre-integrated subsurface lookup integrated in numpy from a published six-Gaussian skin diffusion profile (numbers only, no data file); the skin's curvature from the bake's rest position and normal maps; the shell styles' strand cells and a hammered-metal detail map drawn in numpy. Since P51 `pack.py` also grades the baked albedo (`SKIN_GRADE`), the cloth detail maps are 256 px, the crop and the short beard in `parts/` are the skin under their masks (shells, stacked by the game), and the braids are tubes with bead rings, all built by the kit's own code |
| `parts/Garment_*.glb` of the wardrobe, `parts/Accessory_*.glb`, `cloth_mail.png`, `cloth_scale.png` (P54, M11) | `tools/giant/kit/giant_garment.py`, `export_game.py`, `pack.py` | 25 more garments in ten slots (35 in all) cut from the same CC0 body surface by bone-weight regions and pushed out along the normals at their slot's offset, layered by the kit so that the shells of two slots never meet, carrying the body's weights; the plated war belt and the sash are bands like the belt; the long cloak and the fur cloak are the cape's construction carried on below the body's cut; the horned helm's horns and the eight accessories (torcs, a tooth necklace, arm rings, a drinking horn, a beast's jaw) are tubes and cones built in numpy, rigid on one bone each; the mail and scale detail maps are drawn in numpy. No outside mesh, texture or reference image |

Since P56 (M11), the catalogue II: five more hair styles and four more beards in `parts/` grown by the same kit (a top
knot, a side-shaved top, twin braids, long loose hair, a circlet braid; a chin braid, a long forked beard, mutton chops, a
braided moustache), their braids as tubes; three bead sets (`parts/Beads_*.glb`: bone, bronze and silver beads built in
numpy on the braids' anchors); twenty more designs in `designs.png` (tattoos, war paints, scars) drawn as distance
fields like the others; six face shape keys on the head (and copied to the beards, the hairline strips, the shells and the
beads) mixed from the vendored CC0 detail targets already in `tools/giant/mpfb2/` (chin, jaw, nose, brow, forehead,
cheek, head-age, eye-bag and laugh-line targets the giant's own phenotype uses). No new input.

Since B1 (milestone B, functional armour): the Iron set's nasal helm (`parts/Garment_nasal_helm.glb`), a garment cut
from the same CC0 body surface as the iron helm, with a nasal down the bridge of the nose; and the Quarry set's
modelled stone (`parts/Armour_quarry_*.glb`: pauldrons, bracers, greaves and the heart-stone amulet) - flat-topped
slabs with chipped corners and chamfered tops and iron straps and rings, built in numpy by `giant_garment.py`
(`ARMOUR_RIGID`) on the body's own landmarks and surface, each part on the weights of the CC0 body vertex under it.
The cloth shader draws the stone from the hammered-metal detail map already shipped (`cloth_metal.png`). No new
input, no outside mesh, texture or reference image.

The code of `tools/giant/kit/` was written for this project (ported from the project's own M10
research kit); it reads the MakeHuman data's documented formats and rules and copies no third-party
code.

## Tools (not redistributed)

Blender 5.3 as the `bpy` Python module (GPL-3.0-or-later), numpy and scipy (BSD-3-Clause), Pillow
(MIT-CMU) and OpenEXR (BSD-3-Clause) build these files; none of them is part of the game. Their
versions are pinned in `tools/giant/requirements.txt` and recorded in `manifest.json`.

**Licence:** the project's own; the owner chooses it (the CC0 inputs fit any).
