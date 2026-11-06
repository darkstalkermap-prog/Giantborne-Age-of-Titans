# Brief: audio technology for desktop and the single-threaded web build (M6+ planning input)

Scope: how Giantborn gets sound effects, ambience and adaptive music that behave the same on the
Windows desktop build and the single-threaded Web export (the play link), using only audio our own
tools generate. The Valley stays the tutorial; the game then opens into an open world, so music and
ambience must change by region. Everything below was measured on 2026-11-06 in the development
container: Godot 4.6.3-stable (official build `7d41c59c4`), Python 3.13 with numpy 2.5.3, ffmpeg
6.1.1, and the `web_nothreads_release` template driven in Playwright's headless Chromium 153
(`--use-angle=swiftshader --enable-unsafe-swiftshader --ignore-gpu-blocklist
--autoplay-policy=no-user-gesture-required`, pages served by `python -m http.server`). No game file
was changed; the experiments live in a scratch folder outside the repository (§8).

Every statement of fact is marked **VERIFIED** (an experiment here produced it; the experiment is
named) or **ASSUMED** (documentation, reading the shipped engine JavaScript, or reasoning, not
confirmed by a run). Recommendations (§6) are proposals built on the facts they cite.

## 0. The short version

1. **Formats.** SFX: 16-bit mono WAV masters at 22.05 kHz (32 kHz for bright metal), imported by
   Godot as QOA (the 4.6 default): 9.0 KB per second, SNR 22-36 dB. Music and ambience: Ogg Vorbis
   from **libvorbis**, which this ffmpeg has (an earlier note said it did not): 32 kHz stereo q2-q3 is
   10-13 KB/s; ambience beds 4.6-5.5 KB/s at 22.05 kHz. ffmpeg's native `vorbis` encoder is
   unusable for loops (it pads 24-875 frames, so every loop glitches and drifts) and takes only
   stereo. Godot 4.6.3 cannot play Opus. All VERIFIED (§1-§3).
2. **On the web, use both playback types on purpose.** Short one-shot SFX play as **samples**
   (the web default): Web Audio plays them, main-thread stalls do not interrupt them, and 3D
   attenuation, panning, volume, mute, pause, pitch and `max_polyphony` all work. But in sample
   mode **bus effects and the 3D distance filter are silently ignored, loops are not gapless (a
   6-9 ms hole at every loop, and `loop_begin` is ignored), stems drift apart at each loop,
   positions are wrong, and every play copies the whole decoded clip** (§5.2). So **music and
   ambience loops must play as streams** (`playback_type = STREAM`), which the no-threads build
   mixes on the main thread: gapless, effects work, `AudioStreamInteractive` /
   `AudioStreamSynchronized` work, but a main-thread stall longer than the output buffer drops
   audio. With `audio/driver/output_latency.web = 200` no dropout happened for stalls up to 120 ms
   (the default 50 ms dropped audio from 60 ms stalls). All VERIFIED (§5.3).
3. **Adaptive music** = one `AudioStreamSynchronized` per region (2-3 stems, intensity by live
   stem volumes) or plain Ogg stems on separate stream players started in the same frame; region
   and combat changes cross-fade at bar boundaries (`AudioStreamInteractive` does this at the next
   bar, VERIFIED on desktop and web); stingers are one-shots. Same code and same result on both
   platforms (§6.4).
4. **Budget.** The play link downloads 14.5 MB today (engine 12.5 MB). Compressed audio does not
   gzip (96-99 %) and base64 adds a third, so each audio MB costs about 1.3 MB of download
   (VERIFIED). Proposal: 3 MB of audio for M6 (download about 18.5 MB), at most 7 MB for the open
   world (about 23.5 MB; the packed `.pck` stays far under the host's 16 MB text-file limit).
5. **Cost.** Web main thread on this container: about 2 ms per second per stream voice, 0.7 ms per
   second per sample voice (plus 345 position messages a second each); registering a 20 s stereo
   clip as a sample costs 41-89 ms and 7.06 MB, a 60 s one 172-185 ms and 21.2 MB (VERIFIED). On
   desktop mixing is on its own thread and a 400 ms main-thread stall leaves no gap; 3D players
   cost 3.2 us each per physics tick (VERIFIED).
6. **Tests can hear audio headless.** The Dummy driver mixes in real time and an
   `AudioEffectCapture` on Master returns the real mix; `AudioStreamPlayback.mix_audio()` renders
   any stream offline at 575-2200x real time. Both VERIFIED, so asset, loop and wiring checks can
   run in the existing headless suite (§6.11).

## 1. Tooling

| Fact | Status (experiment) |
| --- | --- |
| numpy 2.5.3 synthesizes every test sound here (impact, whoosh, wind bed, 96 BPM 20.000 s music loop and its three stems, a stinger, noise, tone, sweep) in 5.9 s; scipy is not installed and is not needed (FFT filters, a state-variable filter, Karplus-Strong plucks, an FFT convolution reverb, loops made seamless by wrapping tails) | VERIFIED (`synth/gen.py`) |
| ffmpeg 6.1.1 encoders: `vorbis` (native, experimental, needs `-strict -2`), **`libvorbis` (present and working)**, `libopus`, `libmp3lame`, `flac`, `adpcm_ima_wav`. There is no QOA encoder or decoder in this ffmpeg | VERIFIED (`ffmpeg -encoders`, an encode with each) |
| The native `vorbis` encoder: refuses mono ("only supports 2 channels"); ignores `-b:a` (the same 397 KB for 64k, 128k and default); honours `-q:a`; `-q:a 0` produces a broken file (SNR 0 dB); decoded length is padded (+48 frames on the 20 s loop, +24 on the 10 s bed, +875 on a 0.7 s whoosh) | VERIFIED (`synth/encode_all.sh`, `synth/analyze.py`) |
| Godot 4.6.3's modules include `vorbis`, `ogg`, `mp3`, `interactive_music`, but no Opus decoder, so Opus files are not an option | VERIFIED (`godot --doctool`, module list) |
| Godot can write WAV itself (`AudioStreamWAV.save_to_wav`, PCM only) and build streams at run time (`AudioStreamWAV.load_from_buffer(bytes, importer_options)`, `AudioStreamOggVorbis.load_from_buffer`, `AudioStreamMP3.load_from_buffer`) | VERIFIED that the methods exist (doctool); not exercised |

## 2. Size per second and quality

Measured on our own signals. SNR is after delay alignment against the 16-bit source; it penalises
perceptual codecs on noise-like sounds, so the 1/3-octave band error (the mean absolute level error
across bands, 40 Hz-16 kHz) and the bandwidth (where the decoded spectrum falls 20 dB under the
source) are listed too. Nobody listened (the container has no speakers): these are spectrum checks.

| Content | Encoding | KB per second | SNR dB | Bandwidth | Band error dB | Decoded length exact? |
| --- | --- | --- | --- | --- | --- | --- |
| Music mix, 44.1 kHz stereo | libvorbis q2 / q3 / q4 | 11.4 / 14.0 / 15.9 | 20.2 / 21.7 / 22.1 | 17.1 / 18.5 / 19.9 kHz | 0.29 / 0.22 / 0.22 | yes (882,000 frames) |
| | native vorbis q2 / q3 / q4 | 8.3 / 10.7 / 12.8 | 15.4 / 18.7 / 19.9 | 17.6 kHz | 0.51 / 0.29 / 0.20 | **no (+48 frames)** |
| | LAME V6 / V4 / CBR 128k | 16.7 / 24.9 / 15.7 | 26.0 / 30.1 / 27.0 | 17.1 / 17.8 / 17.0 kHz | 0.13 / 0.07 / 0.47 | yes |
| | the Opus codec at 64 and 96 kbit/s (not playable in Godot) | 8.6 / 13.0 | 17.4 / 21.1 | 20.6 kHz | 0.22 / 0.09 | yes |
| | Godot QOA (import) | 34.8 | 37.7 | - | 0.01 | yes |
| | FLAC / IMA ADPCM (reference) | 96.1 / 43.4 | lossless / 39.0 | 22.05 kHz | 0 / 0.02 | |
| Music mix, 32 kHz stereo | libvorbis q2 / q3 | 10.3 / 13.1 | | | | |
| Music stems, 32 kHz stereo q2 | drums / pad (simpler than the mix) | 4.7 / 7.7 | | | | |
| Wind bed (noise-like), 44.1 kHz stereo | libvorbis q0 / q3 | 8.1 / 13.5 | 8.7 / 13.7 | 15.5 / 17.6 kHz | 1.36 / 0.73 | yes |
| | native vorbis q3 | 21.2 | 12.1 | 17.6 kHz | 0.38 | no (+24) |
| | Godot QOA | 34.8 | 26.5 | - | 0.03 | yes |
| Wind bed, 22.05 kHz | libvorbis stereo q0 / mono q2 | 5.5 / 4.6 | | | | |
| Impact SFX, mono 1.6 s, 44.1 kHz | libvorbis q2 / q4 | 8.0 / 9.0 | 27.4 / 29.6 | 16.9 / 19.2 kHz | 1.48 / 0.91 | |
| | LAME V4 | 7.6 | 28.1 | 17.5 kHz | 0.95 | |
| | Godot QOA | 17.7 | 36.3 | - | 0.10 | |
| Impact SFX, mono, 22.05 kHz | libvorbis q2 / LAME V4 | 4.9 / 4.6 | 26.9 / 27.8 | 11.0 / 10.3 kHz | 2.66 / 1.60 | |
| | Godot QOA (made at 22.05 kHz / resampled by the importer) | 9.0 / 9.0 | 31.5 / 29.0 | - | 0.17 / 0.26 | |
| Whoosh SFX, mono 0.7 s, 44.1 kHz | Godot QOA | 17.7 | 22.3 | - | 0.73 | |

All rows VERIFIED (`synth/encode_all.sh`, `synth/analyze.py`, `synth/qoa_decode.py`, which decodes
the QOA data Godot stored and was checked byte-exact against Godot's sizes). "-": bandwidth not
measured for QOA (a waveform codec, so the full band is ASSUMED; its band errors are 0.01-0.73 dB). Further facts:

- **Fixed overhead per file** (VERIFIED, `enc3/`): a libvorbis file carries about 3.7 KB of headers
  (a 0.05 s clip is 3,912 bytes), MP3 almost none (1,270 bytes). QOA costs exactly
  `8 + 24 x ceil(frames / 5120) + 8 x ceil(frames / 20)` bytes per channel (matched Godot's data
  sizes to the byte), so for mono 22.05 kHz SFX **QOA is smaller than Ogg below about 0.75 s** and
  larger above it.
- **Godot's import adds little**: Ogg +3 % (`.oggvorbisstr`), MP3 +0.1 %, WAV/QOA +370 bytes
  (VERIFIED, `.godot/imported` sizes).
- **Shipping overhead on the web**: the build ships `index.pck` gzipped and base64-encoded. Ogg,
  MP3 and stereo QOA gzip to 96-99 %, so they ship at 128-132 % of their size; short mono QOA SFX
  ship at 89-103 % (they gzip a little) (VERIFIED, gzip -9 + base64 of each imported file).

## 3. Godot import (4.6.3)

| Fact | Status |
| --- | --- |
| A WAV imports as QOA by default (`compress/mode=2`), with `edit/loop_mode=0` ("Detect From WAV"). Modes: 0 PCM, 1 IMA ADPCM, 2 QOA. QOA is 20.5 % of PCM, IMA ADPCM 25 % | VERIFIED (`.import` files, imported sizes) |
| `force/max_rate` + `force/max_rate_hz=22050` on a 44.1 kHz source gives the same 14,671-byte QOA as a source made at 22.05 kHz (SNR 29.0 vs 31.5 dB) | VERIFIED |
| **Off-by-one on WAV loops**: a forward loop with the default `edit/loop_end=-1` imports as `loop_end = frames - 1`, and playback treats `loop_end` as exclusive, so each loop drops one frame: the period is 881,999 frames instead of 882,000 and the seam's SNR falls from 152 dB to 21 dB on PCM. Setting `edit/loop_end` to the frame count (882,000) gives an exact period and an identical second pass (seam 49 dB PCM, 25.7 dB QOA = the codec's own) | VERIFIED (`render.gd`, `render_le.gd`, `synth/seams.py`) |
| A RIFF `smpl` chunk is detected (loop mode Forward, `loop_end` read from it); a spec-correct inclusive end (frames - 1) inherits the off-by-one, so write `loop_end` in the `.import` instead | VERIFIED |
| Ogg and MP3 import with `loop=false`; `loop`, `loop_offset`, `bpm`, `beat_count`, `bar_beats` are import parameters and show on the stream at run time | VERIFIED |
| Loops through Godot's own decoders (offline renders of 2.5 loops): libvorbis Ogg exact (882,000-frame period, second pass identical, seam SNR = mid SNR); LAME MP3 exact too (consistent with Godot reading the LAME gapless header, ASSUMED); native-vorbis Ogg 882,048-frame period with seam SNR 3.5 / 0.3 dB (a seam glitch that also drifts 1.1 ms per loop) | VERIFIED (`render.gd`, `synth/seams.py`) |
| Every decoder's output is 2 frames late (the resampler's interpolation is the likely cause, ASSUMED) | VERIFIED |

## 4. Desktop playback (stream mixing on the audio thread)

Headless with the Dummy driver; output measured by an `AudioEffectCapture` on Master (`lab.gd`,
desktop run), unless noted.

| Fact | Status |
| --- | --- |
| The Dummy driver mixes in real time: players advance, `finished` fires (1.60-1.68 s for a 1.6 s clip), the capture returns the mix | VERIFIED |
| `playback_type` default resolves to Stream on desktop. **Forcing `PLAYBACK_TYPE_SAMPLE` on desktop is silent**: a warning ("the driver doesn't support sample playback"), no output, `playing` stays true forever, position 0, `finished` never fires | VERIFIED |
| `can_be_sampled()` is true for `AudioStreamWAV` (PCM, IMA, QOA), `AudioStreamOggVorbis`, `AudioStreamMP3`; false for `AudioStreamRandomizer`, `AudioStreamSynchronized`, `AudioStreamInteractive`, `AudioStreamPlaylist`, `AudioStreamPolyphonic`, `AudioStreamGenerator` | VERIFIED (`render.gd`) |
| Bus effects apply: a 400 Hz low-pass bus took white noise from -10.8 to -29.0 dBFS (HF ratio 1.408 to 0.054); a wet-only reverb bus left a -20 dBFS tail after the sound ended | VERIFIED |
| Bus volume -20 dB gives exactly -20 dB; player `volume_db` -12 gives -12.1 dB; `pitch_scale` 0.5 lowers the content (white noise's HF ratio 1.41 to 0.79) | VERIFIED |
| 3D attenuation (unit_size 10, max_db 3): inverse distance -9.0 / -12.0 / -24.1 / -36.1 dBFS at 2 / 10 / 40 / 160 m (-6 dB per doubling past `unit_size`); logarithmic -9.0 / -12.0 / -39.8 / -67.5 (-20 x ln(d / unit_size) dB). A source 10 m to the right is 6.0 dB louder on the right (default panning strength). `attenuation_filter_cutoff_hz` 1000 at 60 m takes noise's HF ratio from 1.31 to 0.10 | VERIFIED |
| `max_distance` fades rather than cuts: logarithmic, unit 5 m, max 30 m: -59.8 dBFS at 25 m and -76.7 at 29 m (about 18 and 32 dB under the plain curve), silent at 31 m | VERIFIED (`desk_extra.gd`) |
| `max_polyphony` holds: 8 `play()` calls in one frame give 1 voice (-10.5 dBFS) or 4 voices (+1.6 dBFS); 24 impact players started together reach **+17.2 dBFS (clipping)**. Godot adds no limiter | VERIFIED |
| Tree pause silences `PROCESS_MODE_PAUSABLE` players (`stream_paused` turns true) and resumes them; `stream_paused` works too | VERIFIED |
| Three stem players started in one frame report identical positions (2.9751 s, then 3.6252 s) | VERIFIED |
| A 400 ms busy main thread leaves no gap in a streaming tone (longest zero run 1 frame) | VERIFIED (`desk_extra.gd`) |
| Main-thread cost: 128 playing `AudioStreamPlayer3D` nodes add 0.41 ms per physics tick (3.2 us each; `area_mask` makes no difference without Area3Ds); stopped ones cost nothing; 128 plain `AudioStreamPlayer`s add 0.06 ms | VERIFIED (`cost3d.gd`, `--fixed-fps 60`) |
| Offline decode speed, one core: Ogg about 580x real time per stereo stream, MP3 840x, QOA 885x, PCM 2200x | VERIFIED (`render.gd`) |
| `AudioStreamSynchronized` keeps stems sample-aligned (drums-only render matches the drum stem at 33 dB, the codec's SNR) and a stem's `set_sync_stream_volume` takes effect on the next mix while it plays | VERIFIED (`render.gd`, `sync_live.gd`) |
| `AudioStreamInteractive` with `TRANSITION_FROM_TIME_NEXT_BAR`: a switch asked at 3.0 s changed clip at 5.0 s (the next bar at 96 BPM). With `TRANSITION_TO_TIME_SAME_POSITION` from a synchronized clip, the target started at 0, not at the same position; the interactive playback reports position 0 | VERIFIED (`render.gd`, `synth/interactive_check.py`) |
| `AudioStreamRandomizer` draws from the global RNG (`randf()` after `seed(1234)` differs once three randomizer playbacks have started). The simulation uses no global `randf`/`randi` today (grep of `scripts/`, `ui/`, `tools/`, `tests/`) | VERIFIED |

## 5. The single-threaded web export

`index.audio.worklet.js` and `index.audio.position.worklet.js` ship with the no-threads template.
The page measured the real output on the audio thread with an `AudioWorkletProcessor` fed by
everything Godot connects to `ctx.destination` (peak, RMS, balance, silent 128-frame quanta), and
counted Web Audio buffers, sources and main-thread message handlers (§8). Headless Chromium runs
the AudioContext at 44.1 kHz (baseLatency 10 ms) without a device. 0 console errors and 0 warnings
in every run. Real browsers and real speakers: NOT RUN.

### 5.1 What plays

| Fact | Status |
| --- | --- |
| `audio/general/default_playback_type` is 0 (Stream) and `.web` is 1 (Sample): on the web every player left at `PLAYBACK_TYPE_DEFAULT` plays samplable streams as samples | VERIFIED (`lab.gd` env, buffer logs) |
| The driver is `AudioWorklet`; reported output latency 46.4 ms at the default `output_latency.web` (50) and 185.8 ms with `--audio-output-latency 200` | VERIFIED |
| WAV (PCM, IMA, QOA), Ogg and MP3 play in both modes, one-shot and looping: sources start and `finished` fires for sample one-shots (1.60-1.63 s for 1.6 s); the audio-thread recorder heard WAV PCM, QOA and Ogg samples (MP3 and IMA samples were not put through the recorder) | VERIFIED (`lab.gd`, `lab2.gd`-`lab4.gd`) |
| Randomizer, Synchronized, Interactive and Playlist streams play on the web in every mode, as streams (never registered as samples) | VERIFIED |
| `AudioStreamInteractive` on the web switched clip at the next bar (1.9-2.1 s after a request made 3.0 s in, at 96 BPM) | VERIFIED (`lab3.gd`) |
| Sample playback works on Master, on buses from `default_bus_layout.tres` and on a bus added at run time (-9.0 dBFS for a -9 dB tone on each) | VERIFIED (`lab4.gd`) |
| `max_polyphony` 1 / 4 starts 1 / 4 Web Audio sources for 8 `play()` calls; four impacts summed to a peak of 2.09 at the destination's input (6.4 dB over full scale): nothing limits the web mix either | VERIFIED (`lab4.gd`) |
| Bus volume (-20.0 dB), player volume (-12.0 dB), Master volume (-5.9 dB), bus mute and Master mute all apply to samples; `pitch_scale` 2 doubles the pitch | VERIFIED (`lab4.gd`) |
| 3D attenuation and panning apply to samples exactly as on desktop (-9.0 / -12.0 / -39.8 / -67.5 dBFS at 2 / 10 / 40 / 160 m, logarithmic; +6 dB right, then -6 dB after the source moved left while playing) | VERIFIED (`lab4.gd`) |
| Tree pause silences a pausable sample player and resumes it | VERIFIED (`lab4.gd`) |

### 5.2 What silently does not work in sample mode

| Fact | Status |
| --- | --- |
| **Bus effects are ignored**: white noise on a low-pass bus stayed at -10.8 dBFS, HF ratio 1.404 (unfiltered); the same player in stream mode on that bus measured -29.0 dBFS, HF 0.054 | VERIFIED (`lab4.gd`) |
| **The 3D distance filter is ignored** (`attenuation_filter_cutoff_hz` 1000 at 60 m: HF 1.403 in sample mode, 0.098 in stream mode) | VERIFIED (`lab4.gd`) |
| **Loops are not gapless**: a 2.0 s tone loop left 2-3 silent quanta (5.8-8.7 ms) at every loop (4 holes in 8.6 s) and restarted every 2.009-2.011 s instead of 2.000 s; a 10 s Ogg bed had a hole at each loop too. Stream mode: 0 silent quanta | VERIFIED (`lab3.gd`) |
| **`loop_begin` is ignored**: a clip with a 1 s silent intro and `loop_begin` = 1 s replayed the intro on every loop in sample mode (792 silent quanta in 5 s, runs of 1.007 s); stream mode looped the tone only (0 silent) | VERIFIED (`lab3.gd`) |
| Why (code of the shipped `index.js`): a sample never uses `AudioBufferSourceNode.loop`; the main thread's `ended` handler starts a new source from the original offset, with a fresh copy of the whole buffer | ASSUMED (code reading; it matches every measurement above) |
| **A loop restart waits for the main thread**: a 250 ms stall that overlapped a loop point gave a 186 ms hole (64 quanta); stalls elsewhere in the loop left no hole | VERIFIED (`lab2.gd`, both latency settings) |
| **Stems drift at each loop**: three 2 s loops started in one frame started in the same render quantum and restarted together once, then 11.6 ms apart, then spread over 20.3 ms | VERIFIED (`lab3.gd`, source start log) |
| **Positions are unreliable**: `get_playback_position()` of a sample one-shot read 0.003 s after 0.35 s; three sample stems read 1.85 s after 3.0 s (stream mode: 3.02 s); a sample loop does not wrap (8.1 s on a 2 s loop) | VERIFIED (`lab.gd`, `lab3.gd`) |
| **Memory and copies**: a registered sample is stored as stereo float32 at the context's rate whatever the source (a 1.6 s mono 44.1 kHz QOA clip took 0.56 MB = 2 channels x 70,560 frames x 4 bytes; 20 s stereo 7.06 MB; 60 s 21.17 MB; that a 22.05 kHz source is resampled to the context's rate is ASSUMED from the code), and **every `play()` (and every loop restart) allocates another full copy** of the same size | VERIFIED (`createBuffer` log, `lab2.gd`) |
| **Registration and play are main-thread hitches**: `register_stream_as_sample` 2.4-3.4 ms (1.6 s QOA), 26-28 ms (10 s Ogg), 41-45 ms (20 s QOA), 48-89 ms (20 s Ogg), 172-185 ms (60 s Ogg); each later `play()` 0.9-1.5 ms (1.6 s), 7.5-14 ms (20 s), 26-32 ms (60 s). A first `play()` without registration does both (up to 244 ms seen for a 20 s Ogg) | VERIFIED (`lab.gd`, `lab2.gd`) |
| `register_stream_as_sample` is a no-op on desktop (0.01 ms, stays unregistered), so calling it everywhere is safe | VERIFIED |

### 5.3 Stream mode on the web: mixing on the main thread

| Fact | Status |
| --- | --- |
| The no-threads driver mixes inside the main thread's message handler of the AudioWorklet: 345 handler calls per second, each running Godot's mixer | VERIFIED (handler timing) and ASSUMED for the mechanism (code reading) |
| Bus effects and the 3D distance filter work in stream mode on the web, the same numbers as desktop (low-pass -28.8 dBFS, HF 0.054; reverb tail -20.3 dBFS; filter at 60 m -45.6 dBFS) | VERIFIED (`lab.gd`, `lab4.gd`) |
| Stream stems stay aligned (three positions 3.0215 s, then 3.66 s) | VERIFIED (`lab.gd` web) |
| Main-thread stalls vs dropouts (a continuous tone; three stalls per window; silent quanta of 2.9 ms, longest run in brackets): | VERIFIED (`lab2.gd`) |

| Stall | Stream, default latency (46 ms) | Stream, latency 200 (186 ms) | Sample |
| --- | --- | --- | --- |
| 30 ms | 0 | 0 | 2 (the loop hole) |
| 60 ms | 17 (14.5 ms) | 0 | 3 |
| 120 ms | 80 (84 ms) | 0 | 2 |
| 250 ms | 218 (203 ms) | 72 (67 ms) | 64 (186 ms, the stall hit a loop restart) |
| 500 ms | 476 (464 ms) | 332 (322 ms) | 3 |

### 5.4 Cost on the web main thread (this container's CPU, SwiftShader; real machines differ)

| Players looping | Stream: handler ms per second | Sample: handler ms per second (messages per second) | Status |
| --- | --- | --- | --- |
| 0 (4 extra buses, one with reverb) | 14.6 | 16.9 (345) | VERIFIED |
| 16 | 51.3 | 24.8 (5,857) | VERIFIED |
| 48 | 109.4 | 50.9 (16,910) | VERIFIED |

About 2.0 ms per second per stream voice and 0.7 ms per second per sample voice, plus one position
message per render quantum per playing sample (each playing sample has its own position-reporting
AudioWorkletNode: 48 were created in the main run, besides the driver's own). Frames stayed at
16.7 ms (p95 at most 18.1 ms) in every row (VERIFIED, `lab.gd` cost test).

### 5.5 Focus, visibility, the first click

| Fact | Status |
| --- | --- |
| Blurring and refocusing the canvas sends `NOTIFICATION_WM_WINDOW_FOCUS_OUT` / `_IN` to the game; `NOTIFICATION_APPLICATION_FOCUS_OUT` (which `scripts/main.gd` uses to open the pause menu) did not arrive on the web | VERIFIED (`lab.gd` focus phase) |
| A JavaScript `visibilitychange` listener registered from GDScript (`JavaScriptBridge.create_callback`) that sets `AudioServer.set_bus_mute(0, ...)` silenced both a stream player and a sample player at once (352 of 352 quanta silent) and restored them | VERIFIED (`lab3.gd`, with a dispatched event: a headless page cannot really be hidden) |
| A real hidden tab: the browser stops `requestAnimationFrame`, so the game freezes, while Web Audio keeps playing samples until their end and the worklet's messages may keep mixing streams | ASSUMED (headless kept the page visible: 139 frames in 2 s) |
| The launcher starts the engine inside the Play click, so the AudioContext may start; the hot-reload path (`resume()` without a click) would start it suspended until the first input | ASSUMED (code reading of `web/launcher.html` and the engine's `godot_audio_resume`) |
| The launcher can take Godot's AudioContext by wrapping the `AudioContext` constructor before the engine loads (all measurements in this brief came through such a wrapper) | VERIFIED |

## 6. Recommended architecture

### 6.1 Asset formats and rates

| Category | Master | In the game | Rate, channels | Why |
| --- | --- | --- | --- | --- |
| SFX one-shots (impacts, footfalls, swings, voices, UI) | 16-bit WAV, committed | QOA (Godot's default import), `playback_type` left DEFAULT | 22.05 kHz mono; 32 kHz for metal and glass | 9 KB/s; smaller than Ogg under 0.75 s; no encoder needed (§2); samples on the web (§5.1) |
| Ambience beds | generated WAV (not committed) | Ogg, libvorbis q0-q2, `loop=true` | 22.05 kHz stereo (5.5 KB/s) or mono q2 (4.6 KB/s) | gapless only in stream mode (§5.2) |
| Ambience spots (birds, creaks, distant shouts) | WAV, committed | QOA one-shots placed by the ambience director | 22.05 kHz mono | variety without long beds |
| Music stems and stingers | generated WAV (not committed) | Ogg, libvorbis q2-q3, `loop=true` with `bpm`, `beat_count`, `bar_beats` | 32 kHz stereo (stems 5-8 KB/s each) | loops exact (§3) |

If libvorbis is ever missing: LAME MP3 loops are exact in Godot (§3); never ship ffmpeg's native
`vorbis` for loops. WAV loops need `edit/loop_end` set to the frame count (§3).

### 6.2 Size budget (the play link)

Today 14.5 MB (engine 12.53 MB, game data 1.68 MB, `index.js` 0.32 MB: VERIFIED from the launcher's
`BUILD` line). Audio ships at about 1.3x (§2). Proposed caps, checked by a test over the imported
files:

| Scope | Audio (raw) | Download | Rough split |
| --- | --- | --- | --- |
| M6 (Valley tutorial + first open region) | 3 MB | about 18.5 MB | SFX 0.8 MB (70 cues x 2 variants x 0.6 s at 9 KB/s), ambience 0.7 MB (4 beds x 30 s), music 1.5 MB (explore and combat layers of 16 bars, the boss pair, six stingers) |
| Open world (stages 4-6) | 7 MB | about 23.5 MB | about 1 MB per further region (bed, two layers, its creatures) |

The packed `.pck` then stays near 10.8 MB, under the host's 16 MB per-text-file limit (ASSUMED
from `tools/build_web.sh`'s comment). Per-region packs fetched on demand are possible later
(`ProjectSettings.load_resource_pack`, `AudioStreamOggVorbis.load_from_buffer`), ASSUMED, not needed
within this budget. Web memory: registered SFX cost 353 KB per second of audio (stereo float32 at
44.1 kHz) plus one copy per playing voice: 84 s of SFX is about 30 MB (VERIFIED rate, §5.2).

### 6.3 Playback-type policy (one code path for both platforms)

- Never set `PLAYBACK_TYPE_SAMPLE` in code (silent on desktop, §4). SFX players keep DEFAULT.
- Music and ambience loops set `PLAYBACK_TYPE_STREAM` explicitly (desktop's default anyway):
  gapless, positions right, effects available (§5.2, §5.3).
- Set `audio/driver/output_latency.web` to 200 (VERIFIED: no dropout for 120 ms stalls). That
  delay only touches stream voices (ASSUMED: samples bypass the worklet's buffer, and stalls did not
  touch them, VERIFIED), so nothing time-critical may be a stream on the web: no
  `AudioStreamRandomizer` / `Polyphonic` / `Playlist` for SFX (they cannot be samples, §4).
- Keep main-thread stalls under 120 ms while music plays (VERIFIED safe at the 200 setting; a
  250 ms stall dropped 67 ms of audio). P17a already loads a level's enemy scenes with the level;
  a first spawn of a never-loaded scene took 97-152 ms (`docs/PERFORMANCE.md`), so keep
  preloading and spread big loads.
- Register every SFX at level load (`AudioServer.register_stream_as_sample`, about 2 ms per 1.6 s
  clip, VERIFIED) behind the loading frame.

### 6.4 Adaptive music

- **Per region** one `AudioStreamSynchronized` of 2-3 stems (base, pulse, combat) played as a
  stream on the Music bus; intensity = stem volumes eased by the director in `_process` (live
  changes VERIFIED, §4). Alternatively plain Ogg stems on separate stream players started in one
  frame (aligned on both platforms, VERIFIED).
- **Changes** (region, combat start and end, boss phases): `AudioStreamInteractive` clips with
  `TRANSITION_FROM_TIME_NEXT_BAR` + `FADE_CROSS` (VERIFIED on both platforms). Do not rely on
  `TRANSITION_TO_TIME_SAME_POSITION` from a synchronized clip or on the interactive playback's
  position (both VERIFIED wrong, §4); if exact phase matters, cross-fade two synchronized players
  from the director at a bar computed from the base stem's position (stream positions advance
  correctly, VERIFIED).
- **Stingers** (growth, level up, boss defeated, quest stage) are one-shots on the Music bus that
  duck the stems 6-8 dB for their length.
- Inputs come from `Events`: `encounter_activated` / `encounter_cleared`, `boss_engaged`,
  `boss_phase_changed`, `boss_defeated`, `growth_changed`, `level_changed`, `quest_stage_changed`,
  `area_entered`, `slice_completed`, plus a read of the aware-enemy count (as `GameSession` does).

### 6.5 Ambience and regions in the open world

- A region record names its music set, its ambience bed(s) and its spot-sound table; the director
  cross-fades beds and music when the player is 15 m inside a new region (hysteresis), loads the
  next region's streams when it is near, and frees the old ones after the fade.
- Streams avoid the sample registration hitch entirely (the 172-185 ms for 60 s, §5.2; no buffer
  was created for a stream-mode play, VERIFIED); loading an Ogg resource is a file read (ASSUMED
  cheap; on the no-threads web build threaded loads run on the main thread, ASSUMED).
- The Valley keeps its own tutorial set (and its boss music) and is simply the first region.

### 6.6 3D attenuation for giants (3.66-18.90 m tall at stages 1-6) and humans

- **Listener**: an `AudioListener3D` on the camera rig's pivot at the giant's chest, turned with the
  camera, rather than the camera itself (the arm is 6.5 / 9 / 12 m at stages 1-3 and longer
  later), so the giant's own sounds stay present and humans at its feet are near.
- **Curves**: logarithmic attenuation with `max_distance` about 7.4 x `unit_size` (where the curve
  reaches -40 dB; `max_distance` then fades the rest to silence, VERIFIED §4). Each sound names an
  audibility class in data; suggested starting values (unit / max): human step 2 / 15 m, human
  voice or weapon 4 / 30 m, wolf 3 / 22 m, ogre 8 / 60 m, giant footfall 1.5 x height / 11 x
  height (stage 1: 5.5 / 40 m; stage 6: 28 / 210 m), boss and world events 30 / 220 m. ASSUMED
  (tuning values, to be judged by ear).
- **Scale with the player**: multiply unit and max distance of every other source by the player's
  height / 3.66, so a human at 50 m sounds to a stage-6 giant as one at 9.7 m does at stage 1
  (the measured curves follow -20 ln(d / `unit_size`), §4; that they scale exactly with
  `unit_size` is ASSUMED from that formula). Re-apply on `growth_changed`.
- **Muffling with distance** works only for streams (§5.2): set `attenuation_filter_db = 0` and
  bake a low-passed "far" variant of big sounds, chosen by distance when the sound starts, so both
  platforms sound the same. No doppler, no emission angle, no Area3D reverb (effects).

### 6.7 Voices

- One pool owned by the director: 24 `AudioStreamPlayer3D` and 8 `AudioStreamPlayer` (UI, 2D);
  no node per event. 3D players cost 3.2 us per tick each on desktop (VERIFIED), and each web
  sample voice about 0.7 ms per second, a 345-per-second message stream and a buffer copy of its
  length (VERIFIED), so cap the web pool lower (16) if real-browser timing asks for it.
- Per cue: `max_voices` (footfalls 6, impacts 8, swings 4, voices 3), a 40-60 ms retrigger guard,
  a priority, and no start when the computed level is under -45 dB.
- Gain staging, because nothing limits either output (VERIFIED: +17 dBFS on desktop, peak 2.09 on
  the web): SFX masters normalised to -6 dBFS peak, the SFX bus at -6 dB, the voice caps above. A
  desktop-only limiter would make the platforms differ.
- Variants: 2-4 files per cue picked by the director's own `RandomNumberGenerator` with a small
  pitch range (`pitch_scale` works on samples, VERIFIED); never `AudioStreamRandomizer`.

### 6.8 Buses and settings

- `default_bus_layout.tres` generated by a builder (the project's rule: generated, never
  hand-edited): Master; Music; Ambience; SFX; UI; all sending to Master, no effects (they would
  only exist on desktop and on web streams). Layout buses and run-time buses both work for samples
  (VERIFIED).
- Settings (`Settings` DEFAULTS and RANGES, 0..1): `volume_master`, `volume_music`,
  `volume_ambience`, `volume_sfx`, `volume_ui`, applied with `AudioServer.set_bus_volume_linear`;
  `mute_when_unfocused` (default on). Bus volume and mute behave the same for samples and streams
  (VERIFIED).

### 6.9 Focus, pause, the tab

- Mute (or duck to -80 dB over 0.2 s) Master on `NOTIFICATION_APPLICATION_FOCUS_OUT` and on
  `NOTIFICATION_WM_WINDOW_FOCUS_OUT` (the one the web sends, VERIFIED); on the web also from a
  `visibilitychange` callback (VERIFIED mechanism).
- Pausing screens: SFX and ambience players `PROCESS_MODE_PAUSABLE` (silenced by the tree pause in
  both modes, VERIFIED); music `PROCESS_MODE_ALWAYS`, ducked by the director.

### 6.10 Audio stays out of the simulation

- The director is presentation: it listens to `Events` (about 70 signals: `hit_resolved`,
  `attack_clanked`, `area_pulse`, `entity_died`, `staggered`, `object_destroyed`,
  `telegraph_started`, `grab_started`, `growth_changed`, ...) and to `ActorRig.footfall` (already
  emitted per half stride), reads state in `_process`, and never emits gameplay signals, never
  reads `finished` into game logic, never touches `Sim.rng` or the global RNG.
- A test runs the seeded sandbox soak with the director enabled and disabled and compares the two
  `AUTOPILOT_RESULT` lines byte for byte.

### 6.11 Tests headless (the techniques were VERIFIED here; the checks are proposals)

- **Asset checks, offline**: `stream.instantiate_playback()`, `start(0)`, `mix_audio(1.0, n)`
  renders any stream with no driver at 575-2200x real time: not silent, length as declared, loops
  with an exact period (the second pass equals the first), WAV loops with `loop_end` = frames,
  `beat_count x 60 / bpm` = length for music.
- **Wiring, real time**: the Dummy driver mixes and an `AudioEffectCapture` on Master returns the
  mix, so a smoke test can assert that an event produced sound, that a bus volume or the 3D curve
  holds. Real-time, so keep it to a few tolerant checks; assert the rest on the director's log of
  started cues (cue id, bus, voice count, tick), which is deterministic.
- **Policies**: no code sets `PLAYBACK_TYPE_SAMPLE`; every SFX stream has `can_be_sampled()`; every
  music and ambience player sets STREAM; no `AudioStreamRandomizer`; the size cap of §6.2.
- **Web**: the P18 Playwright check gains the destination recorder of §8 (sound after New Game, no
  hole in the music for a minute, `createBuffer` bytes under a cap). Pick a free port and check
  the served page's title first: on a shared machine another job held this lab's first port and
  served a different build.

### 6.12 Generation pipeline

- `tools/audio/` Python 3 + numpy generators (seeded, like `tools/bot_report.py` uses Python), one
  per cue family, writing WAV masters; SFX WAVs are committed as Godot's import source; music and
  ambience masters are rendered and encoded with `ffmpeg -c:a libvorbis` and only the Ogg is
  committed, with the generator, its seed and a manifest (file, frames, rate, loop, bpm, beats,
  hash) that the asset test reads. The spec's "keep audio masters" is met by the generators.
- The owner's Windows machine needs no Python or ffmpeg to build or play the game; only
  regenerating audio does.

## 7. Open points (not settled here)

- Real browsers on real hardware: stall margins, CPU per voice, and whether a real hidden tab keeps
  mixing (ASSUMED in §5.5). Listen to every asset once on speakers: nothing here was heard.
- Freeing a stream unregisters its sample on the web (the engine has
  `godot_audio_sample_unregister_stream`): ASSUMED, not measured; region unloading relies on it.
- The 3D main-thread cost on the web (desktop 3.2 us per voice per tick, VERIFIED): ASSUMED 2-4x
  slower in WebAssembly.
- Why the first web run's analyser-based readings showed silence for every sample-mode voice while
  the audio-thread recorder heard them: those readings were discarded; every sample-mode level in
  this brief comes from the recorder (`lab2.gd` to `lab4.gd`).

## 8. Reproducing

The experiments are in the session's scratch folder (`<scratch>/audio_lab/exp/`, outside the
repository): `synth/gen.py` (the sounds), `synth/encode_all.sh` + `synth/analyze.py` (encoders,
sizes, quality), `synth/qoa_decode.py`, `synth/seams.py`, `synth/interactive_check.py`; the Godot
project `gd/` (`render.gd`, `render_le.gd`, `dump_wav.gd`, `cost3d.gd`, `desk_extra.gd`,
`sync_live.gd`, `lab.gd` / `lab2.gd` / `lab3.gd` / `lab4.gd` with presets Web, Web2, Web3, Web4);
`synth/instrument3.js` (the page instrumentation: AudioContext wrapper, destination tap, recorder
worklet, buffer and source logs, handler timing) and `synth/run_web.js` (server, Chromium, focus
phase); results in `logs/` (`encode_quality.csv`, `qoa_quality.txt`, `seams.txt`,
`lab_desktop.log`, `lab_web_v2.json`, `lab_web2_default.json`, `lab_web2_lat200.json`,
`lab_web3.json`, `lab_web4.json`). Desktop runs: `godot --headless --path gd` (with
`XDG_DATA_HOME` set); exports without `XDG_DATA_HOME`, as the templates live in the default data
folder.
