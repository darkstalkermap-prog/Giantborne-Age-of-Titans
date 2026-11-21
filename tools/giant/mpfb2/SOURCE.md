# The vendored MakeHuman / MPFB2 subset (CC0 1.0)

The 137 files listed in `FILES.sha256` are the part of the MakeHuman / MPFB2 data that the giant
pipeline (`tools/giant/`) reads: the hm08 base mesh (`3dobjs/base.obj`, with its helper geometry and
joint cubes), the 122 morph targets of the giant's phenotype (`targets/**`, chosen by
`kit/mh_data.py`'s `GIANT_MACRO` and `GIANT_MODIFIERS`), the four universal muscle-and-weight targets
the build sliders are measured against (`macrodetails/universal-male-{young,old}-averagemuscle-maxweight`
and `-maxmuscle-averageweight`, `mh_data.BUILD_TARGETS`; P48), the regional modifier table
(`targets/target.json`), the "game_engine" skeleton and its skinning weights
(`rigs/standard/rig.game_engine.json`, `weights.game_engine.json`) and six region mask images
(`textures/mpfb_*.jpg`). `LICENSE.md` is the CC0 1.0 text that ships with the data.

**The people's files (P59, plan M11 §2.8).** The 88 files listed in `PEOPLE.sha256` are more targets of the
same release that only the people pipeline (`tools/giant/build_people.py`) reads, chosen by
`kit/people_roles.py`'s variants: the women's macro targets (`macrodetails/*female*`,
`macrodetails/universal-female-*`, `macrodetails/proportions/female-*` and `breast/female-*`), the owner having
agreed to them (plan M11 §0.6, question 6), more age, muscle and weight combinations of the men's, and the
opposite directions of a few detail targets for the faces. They come from the same wheel, are audited the same
way, and are kept out of `FILES.sha256` so that the giant's inputs hash stays his own. Together 3,874,136 bytes
(the plan's cap for added CC0 targets: 4 MB).

- **Licence:** CC0 1.0 Universal (`LICENSE.md`). The base mesh's header says it "was explicitly
  released as CC0 in september 2020" (copyright holders at the release: Data Collection AB, Joel
  Palmius, Jonas Hauquier); the weights file carries `"license": "CC0"`.
- **Upstream:** MakeHuman (makehumancommunity.org) and MPFB2, the MakeHuman plugin for Blender.
- **Where the copy comes from:** the folder `anny/data/mpfb2/` inside the Python wheel
  `anny-0.6.2-py3-none-any.whl` (the PyPI package `anny` 0.6.2; 47,711,600 bytes, sha256
  `bad70bdc2be0dfa9880d60129c3a1339678f08f493184f637dc2825c3e27b8d2`). Only the data files were
  copied, byte for byte; nothing in the wheel was executed, and none of its code (Apache-2.0) is
  part of this repository.
- **The audit:** `tools/giant/fetch_mpfb2.py` re-reads the wheel, recomputes the list of files the
  kit needs and compares every vendored file with the wheel's copy and with `FILES.sha256` and `PEOPLE.sha256`
  (`--extract` rewrites the folder from the wheel). It is not part of `build_giant.py --verify`,
  which needs no network.
- **Not imported by Godot:** the `.gdignore` beside this file keeps Godot from importing the mesh
  and the images; `tests/unit/test_ship_docs.gd` skips the folder.
