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
| Combat (P21, family A impacts and B swings and movement: hits on flesh, armour, wood and stone, the critical accent, blocks, parries, guard breaks, clanks, falling bodies, the giant's swings, dodges, guard and jump) | `tools/audio/gen_combat.py` | 210001-210199 | `sfx/combat/*.wav` (41; metal at 32 kHz) | Python 3.13.18, numpy 2.5.3 |
| Abilities (P21, family D: the stomp and its far version, sweeps, Stone Skin, grabs, Boulder Hurl, Runic Bolt, Mend, Thunder Roar, Titan Surge, throws, bows, barriers, launches and landings, the slow) | `tools/audio/gen_abilities.py` | 211001-211199 | `sfx/abilities/*.wav` (40) | Python 3.13.18, numpy 2.5.3 |
| Steps (P21, family C: the giant at stages 1-3 on soft, hard and wet ground and its cruise steps, people, heavy bodies and their far step, paws) | `tools/audio/gen_steps.py` | 212001-212099 | `sfx/steps/*.wav` (33) | Python 3.13.18, numpy 2.5.3 |
| Voices (P21, family E: formant-synthesized calls, never words - people, the elder, wolves, ogres, the Ogre King and his far roar, the giant, crowds) | `tools/audio/gen_voices.py` | 213001-213199 | `sfx/voices/*.wav` (43) | Python 3.13.18, numpy 2.5.3 |
| Threat (P21, family F: windups by shape, the off-camera sting, the aim lock) | `tools/audio/gen_threat.py` | 214001-214099 | `sfx/threat/*.wav` (9) | Python 3.13.18, numpy 2.5.3 |
| World (P21, family G: cracks, breaks and the far crash, gates opening, shrines, the waystone, growth, the forge, the arena's iron gate, the alarm bell, interactions) | `tools/audio/gen_world.py` | 215001-215199 | `sfx/world/*.wav` (21) | Python 3.13.18, numpy 2.5.3 |
| Interface (P21, family H: blips in the score's key, the refusal buzz, the map's paper, item and equipment touches) | `tools/audio/gen_ui.py` | 216001-216099 | `sfx/ui/*.wav` (22) | Python 3.13.18, numpy 2.5.3 |
| Music (P23, the score: the zone frame's drones - a warm pad, a dark pad with wind, a stone choir with a bell - and nine melody variants on lute, breathy flute and horn written by the seeded phrase writer from one motif per set; the shared danger pulse, combat drums and brass; the title theme's horn choir; the Ogre King's drums, ostinato and phase-2 frenzy in their own frame) | `tools/audio/gen_music.py` | 230001-230032 | `music/{drone,melody,pulse,combat,title,boss}_*.ogg` (19 loops, 1.99 MB; zone frame 30.0 s, the King's 27.69 s) | Python 3.13.18, numpy 2.5.3, ffmpeg 6.1.1-3ubuntu5, libvorbis 1.3.7-1build3 |
| Stingers (P23: growth, level up, victory, quest and quest complete, death, the prologue's end, the three combat intros and the Ogre King's one-bar intro) | `tools/audio/gen_stingers.py` | 231001-231021 | `music/stinger_*.ogg` (11 one-shots, 0.27 MB) | Python 3.13.18, numpy 2.5.3, ffmpeg 6.1.1-3ubuntu5, libvorbis 1.3.7-1build3 |
| Ambience (P23: four 20 s beds - meadow, forest, village, stone - of wind, insects, leaves, murmur, hens, whistles, drips and rumble; the river and the forge fire emitters; 18 spots from larks and crickets to pebble falls and the flush of birds) | `tools/audio/gen_ambience.py` | 232001-232118 | `ambience/bed_*.ogg` (4, stereo), `ambience/{river_loop,forge_fire}.ogg`, `ambience/spot_*.ogg` (18; 0.58 MB in all) | Python 3.13.18, numpy 2.5.3, ffmpeg 6.1.1-3ubuntu5, libvorbis 1.3.7-1build3 |

The P21 families share the synthesis library `tools/audio/synth/` (`fx.py`: vectorised filters, an
STFT time-varying filter, modal synthesis, grains, echoes, far versions and the finishing every
effect gets; `instruments.py`: impacts by material, swings, footfalls, debris, creaks, bells, FM,
plucks, blips; `voices.py`: a Rosenberg glottal source through moving formants, animal and crowd
calls). Each effect's WAV is its own master; no file is edited after it is rendered. The sound
packages add their rows here (P23 the score and ambience, P28 the world's families).

P23 adds `synth/music.py` (MIDI and mode helpers, the zone and boss frames, a seeded modal phrase
writer that writes a set's three variants from one motif, pads, plucks, a breathy flute, brass and
horn, a wavetable choir, bells and drums, loop folding and a circular reverb so every loop is
seamless) and `synth/ambience.py` (looped noise in the frequency domain, wind with gusts, insects,
leaves, murmur, hens, whistles, drips, water and fire, and the spot one-shots). Music, stingers and
ambience are balanced by K-weighted loudness (`core.loudness_lufs`, ITU-R BS.1770 with its gates)
rather than by RMS. The placeholder family P19 shipped for the engine's tests (seeds
190101-190131) was deleted with P23's score, as the plan asks.

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
python3 tools/audio/build_audio.py --only=music     # one family (music, stingers, ambience, combat, ...)
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
