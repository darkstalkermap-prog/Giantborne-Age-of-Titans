# Audio provenance

Every sound in Giantborn is **original and synthesized** by the generators committed in
`tools/audio/` (Python 3 and numpy, seeded, float64, single-threaded). There are **no recordings
and no third-party samples**: each file is the output of a function of a seed and parameters, and
`assets/audio/manifest.json` records, for every shipped file, the generator module and function,
the seed, a hash of the parameters, the frames, rate and channels, the loop data, the hash of its
master and of the shipped file, and the tool versions it was built with.

**Licence:** the project's licence; the owner chooses it.

## Families

| Family | Generator | Seeds | Files | Built with (reference toolchain) |
| --- | --- | --- | --- | --- |
| Placeholder (the audio engine's four test tones, three-variant test set, test stinger and test bed, 111 KB; P19, replaced by P21 and P23) | `tools/audio/gen_placeholder.py` | 190101-190131 | `placeholder/*.wav`, `placeholder/stinger.ogg`, `placeholder/bed.ogg` | Python 3.13.18, numpy 2.5.3, ffmpeg 6.1.1-3ubuntu5, libvorbis 1.3.7-1build3 |
| Combat (P21, family A impacts and B swings and movement: hits on flesh, armour, wood and stone, the critical accent, blocks, parries, guard breaks, clanks, falling bodies, the giant's swings, dodges, guard and jump) | `tools/audio/gen_combat.py` | 210001-210199 | `sfx/combat/*.wav` (41; metal at 32 kHz) | Python 3.13.18, numpy 2.5.3 |
| Abilities (P21, family D: the stomp and its far version, sweeps, Stone Skin, grabs, Boulder Hurl, Runic Bolt, Mend, Thunder Roar, Titan Surge, throws, bows, barriers, launches and landings, the slow) | `tools/audio/gen_abilities.py` | 211001-211199 | `sfx/abilities/*.wav` (40) | Python 3.13.18, numpy 2.5.3 |
| Steps (P21, family C: the giant at stages 1-3 on soft, hard and wet ground and its cruise steps, people, heavy bodies and their far step, paws) | `tools/audio/gen_steps.py` | 212001-212099 | `sfx/steps/*.wav` (33) | Python 3.13.18, numpy 2.5.3 |
| Voices (P21, family E: formant-synthesized calls, never words - people, the elder, wolves, ogres, the Ogre King and his far roar, the giant, crowds) | `tools/audio/gen_voices.py` | 213001-213199 | `sfx/voices/*.wav` (43) | Python 3.13.18, numpy 2.5.3 |
| Threat (P21, family F: windups by shape, the off-camera sting, the aim lock) | `tools/audio/gen_threat.py` | 214001-214099 | `sfx/threat/*.wav` (9) | Python 3.13.18, numpy 2.5.3 |
| World (P21, family G: cracks, breaks and the far crash, gates opening, shrines, the waystone, growth, the forge, the arena's iron gate, the alarm bell, interactions) | `tools/audio/gen_world.py` | 215001-215199 | `sfx/world/*.wav` (21) | Python 3.13.18, numpy 2.5.3 |
| Interface (P21, family H: blips in the score's key, the refusal buzz, the map's paper, item and equipment touches) | `tools/audio/gen_ui.py` | 216001-216099 | `sfx/ui/*.wav` (22) | Python 3.13.18, numpy 2.5.3 |

The P21 families share the synthesis library `tools/audio/synth/` (`fx.py`: vectorised filters, an
STFT time-varying filter, modal synthesis, grains, echoes, far versions and the finishing every
effect gets; `instruments.py`: impacts by material, swings, footfalls, debris, creaks, bells, FM,
plucks, blips; `voices.py`: a Rosenberg glottal source through moving formants, animal and crowd
calls). Each effect's WAV is its own master; no file is edited after it is rendered. The sound
packages add their rows here (P23 the score and ambience, P28 the world's families).

## What is committed

- **Sound effects and interface cues**: the 16-bit mono WAV masters (22.05 kHz; 32 kHz for bright
  metal), which Godot imports as QOA. They are both the masters and the import source.
- **Music, ambience and stingers**: only the Ogg Vorbis files (libvorbis, bit-exact). Their
  lossless masters are not committed: the generators are the masters (plan M6-M9, decision 4; a
  recorded deviation from the spec's "keep audio masters", because about 60 MB of FLAC would be
  rewritten on every tuning pass). The manifest keeps every master's hash, so a regeneration is
  checked against the masters that were shipped.

## Regenerating

```
python3 tools/audio/build_audio.py                  # render, check, write, encode, rewrite the manifest
python3 tools/audio/build_audio.py --only=placeholder
python3 tools/audio/build_audio.py --verify         # regenerate everything into a temporary folder and
                                                    # compare every master and file hash with the manifest
python3 tools/audio/build_audio.py --budget         # the size arithmetic and registered seconds per level
python3 tools/audio/test_synth.py                   # the pipeline's own tests
tools/check.sh --audio                              # both, then the Godot asset suites
```

`--verify` is exact on the reference toolchain recorded in the manifest (its Python, numpy, ffmpeg
and libvorbis); under other versions it reports the toolchain difference separately from content
differences, since another numpy or encoder may change bytes by itself. After regenerating, import
the project once (`tools/gd.sh --headless --path . --import`) so Godot refreshes its `.import`
files.

## FLAC masters

```
python3 tools/audio/build_audio.py --masters-out=<folder>
```

writes the lossless music and ambience masters as FLAC (`<folder>/<family>/<cue>.flac`) beside the
normal build, for anyone who wants them (the owner may ask for them to be committed instead).

Building or playing the game never needs Python or ffmpeg; only regenerating audio does.
