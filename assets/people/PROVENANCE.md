# The people's provenance

Every file in this folder (besides this note and the `.import` settings) is **generated** by
`tools/giant/build_people.py` (P59, plan M11 §2.8) and listed in `manifest.json` with the step that wrote it,
the hash of that step's inputs, its sha256 and size, and the toolchain it was built with.
`build_people.py --verify` regenerates every file into a temporary folder and compares it with the manifest,
bit for bit; `tools/check.sh --people` runs it (the ambient occlusion read back from the committed maps) and
`--people-full` regenerates every pass. Nothing here is edited by hand.

## Inputs

- **MakeHuman / MPFB2 data, CC0 1.0** (`tools/giant/mpfb2/`: the giant's 137 files of `FILES.sha256` and the
  people's 88 more of `PEOPLE.sha256`; `tools/giant/mpfb2/SOURCE.md`). Every person's body is the hm08 base mesh
  morphed by MakeHuman's macro targets (gender, age, muscle, weight, MakeHuman's ideal proportions in part, a mix
  of the three race targets) and a few of its detail targets for the face, on MPFB2's "game_engine" rig with its
  CC0 weights; the women's macro targets are the same release's (the owner's answer to plan M11 question 6).
  The files are byte-for-byte copies from the folder `anny/data/mpfb2/` of the wheel
  `anny-0.6.2-py3-none-any.whl` (sha256 `bad70bdc2be0dfa9880d60129c3a1339678f08f493184f637dc2825c3e27b8d2`);
  `tools/giant/fetch_mpfb2.py` audits them against it.
- **Nothing else.** No other mesh, image, scan, texture or motion enters the pipeline.

## Generated here

| Files | Derives from the CC0 data | Made by |
| --- | --- | --- |
| `<role>.glb` (soldier, archer, mage, crew, villager, elder): each variant's skinned mesh on its 23-bone skeleton, the five crowd-pose meshes, the far mesh | Yes: the body's shape, skeleton and weights; the garments are the project's shells over that body (`giant_garment.py`) | `kit/people_body.py`, `kit/people_outfit.py` |
| `<role>_albedo.png`, `<role>_normal.png`, `<role>_orm.png` | In part: the normals come from the morphed body and the shells over it, the lips', brows' and nails' places from MPFB2's CC0 region masks; every colour, pattern and the ambient occlusion are the project's code | `kit/people_bake.py` (numpy, and Blender's BVH for the occlusion rays) |
| `people_clips.glb` | The skeleton's rest only (the reference man's); every key is computed | `kit/people_body.py` with `kit/clips.py` |
| `gear.glb` | No: wholly the project's code | `kit/people_outfit.py` (`GEAR`) |
| `manifest.json` | - | `build_people.py` |
