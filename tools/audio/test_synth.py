#!/usr/bin/env python3
"""Tests of the audio generation pipeline (tools/audio/): the synthesis core, the writers, the
encoder's bit-exactness and decoded length, the manifest and the generators' declarations; the
score's loudness measure, phrase writer and loops (P23); the world's families (P28).

    python3 tools/audio/test_synth.py        (exit 0 when every test passes)

tools/check.sh --audio runs it before build_audio.py --verify.
"""

from __future__ import annotations

import os
import sys

sys.dont_write_bytecode = True   # no __pycache__ folders in the repository

for _var in ("OMP_NUM_THREADS", "OPENBLAS_NUM_THREADS", "MKL_NUM_THREADS"):
    os.environ.setdefault(_var, "1")

import json
import math
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))

import numpy as np  # noqa: E402

import build_audio  # noqa: E402
import encode  # noqa: E402
import manifest  # noqa: E402
from synth import ambience as amb  # noqa: E402
from synth import core  # noqa: E402
from synth import music as mus  # noqa: E402

RATE = core.DEFAULT_RATE


def steady_gain(y: np.ndarray, x: np.ndarray) -> float:
    """RMS(y) / RMS(x) over the second half (after the filter settles)."""
    h = len(x) // 2
    return core.rms(y[h:]) / core.rms(x[h:])


class CoreTests(unittest.TestCase):
    def test_seeded_generators_are_deterministic(self):
        a = core.white(1000, core.cue_rng(7))
        b = core.white(1000, core.cue_rng(7))
        c = core.white(1000, core.cue_rng(8))
        self.assertTrue(np.array_equal(a, b))
        self.assertFalse(np.array_equal(a, c))
        self.assertTrue(np.array_equal(core.pink(512, core.cue_rng(3)), core.pink(512, core.cue_rng(3))))

    def test_sine_has_its_frequency(self):
        x = core.sine(440.0, RATE, RATE)
        crossings = int(np.sum((x[:-1] < 0.0) & (x[1:] >= 0.0)))
        self.assertIn(crossings, (439, 440))
        self.assertAlmostEqual(core.rms_db(x), -3.0103, places=2)

    def test_per_sample_frequency_starts_at_the_phase(self):
        f = np.linspace(100.0, 200.0, 1000)
        x = core.sine(f, 1000, RATE, phase=0.25)
        self.assertAlmostEqual(x[0], 1.0, places=9)

    def test_band_limited_waves(self):
        s = core.square(110.0, RATE, RATE, duty=0.25)
        self.assertAlmostEqual(float(np.mean(s)), -0.5, delta=0.02)
        w = core.saw(110.0, RATE, RATE)
        self.assertAlmostEqual(float(np.mean(w)), 0.0, delta=0.02)
        self.assertLess(core.peak(w), 1.2)
        t = core.triangle(110.0, RATE, RATE)
        self.assertAlmostEqual(core.peak(t), 1.0, delta=0.01)

    def test_noise_colours(self):
        for gen in (core.pink, core.brown):
            x = gen(1 << 14, core.cue_rng(11))
            self.assertAlmostEqual(core.rms(x), 1.0, places=6)
            self.assertAlmostEqual(float(np.mean(x)), 0.0, places=9)
        # brown noise has more low end than pink
        p = np.abs(np.fft.rfft(core.pink(1 << 14, core.cue_rng(2))))
        b = np.abs(np.fft.rfft(core.brown(1 << 14, core.cue_rng(2))))
        self.assertGreater(np.sum(b[1:50]) / np.sum(b), np.sum(p[1:50]) / np.sum(p))

    def test_envelopes(self):
        env = core.envelope([(0.0, 0.0), (0.5, 1.0), (1.0, 0.0)], RATE, RATE)
        self.assertAlmostEqual(env[RATE // 2], 1.0, places=3)
        a = core.adsr(RATE, RATE, 0.1, 0.1, 0.5, 0.2)
        self.assertAlmostEqual(a[int(0.5 * RATE)], 0.5, places=3)
        self.assertEqual(a[-1], 0.0)
        d = core.exp_decay(RATE, RATE, 0.1)
        self.assertAlmostEqual(d[int(0.1 * RATE)], math.exp(-1.0), places=3)

    def test_biquad_low_pass_is_3_db_down_at_its_cutoff(self):
        x = core.sine(1000.0, RATE, RATE)
        y = core.biquad(x, core.biquad_coeffs("lowpass", 1000.0, 0.7071, RATE))
        self.assertAlmostEqual(core.gain_to_db(steady_gain(y, x)), -3.01, delta=0.1)
        far = core.sine(8000.0, RATE, RATE)
        self.assertLess(core.gain_to_db(steady_gain(core.biquad(far, core.biquad_coeffs("lowpass", 1000.0, 0.7071, RATE)), far)), -30.0)

    def test_biquad_kinds_and_stereo(self):
        x = core.sine(300.0, 4096, RATE)
        for kind in ("highpass", "bandpass", "notch", "peak", "lowshelf", "highshelf"):
            y = core.biquad(x, core.biquad_coeffs(kind, 500.0, 1.0, RATE, 6.0))
            self.assertEqual(y.shape, x.shape)
            self.assertTrue(np.all(np.isfinite(y)))
        st = core.pan(x, 0.3)
        self.assertEqual(core.biquad(st, core.biquad_coeffs("lowpass", 500.0, 0.7, RATE)).shape, st.shape)
        with self.assertRaises(ValueError):
            core.biquad_coeffs("nope", 100.0, 1.0)

    def test_state_variable_filter(self):
        x = core.sine(1000.0, RATE, RATE)
        y = core.svf(x, 1000.0, 0.7071, RATE, "lowpass")
        self.assertAlmostEqual(core.gain_to_db(steady_gain(y, x)), -3.01, delta=0.15)
        bp = core.svf(x, 1000.0, 2.0, RATE, "bandpass")
        self.assertGreater(steady_gain(bp, x), 0.3)
        hp = core.svf(core.sine(50.0, RATE, RATE), 1000.0, 0.7071, RATE, "highpass")
        self.assertLess(core.rms(hp[RATE // 2:]), 0.01)
        swept = core.svf(core.white(2000, core.cue_rng(1)), np.linspace(200.0, 4000.0, 2000), 1.0, RATE)
        self.assertTrue(np.all(np.isfinite(swept)))

    def test_fft_filter_is_circular_so_loops_stay_seamless(self):
        x = core.white(RATE, core.cue_rng(5))
        y = core.fft_filter(x, RATE, core.band_response(100.0, 2000.0))
        self.assertEqual(y.shape, x.shape)
        tiled = np.concatenate([y, y])
        self.assertEqual(core.check_signal(core.normalize_peak(tiled[:RATE], -3.0), RATE, "loop", True), [])

    def test_fft_convolution_matches_direct_convolution(self):
        rng = core.cue_rng(9)
        a = rng.standard_normal(300)
        b = rng.standard_normal(57)
        self.assertTrue(np.allclose(core.fft_convolve(a, b), np.convolve(a, b), atol=1e-9))

    def test_loop_wrap_folds_the_tail_onto_the_head(self):
        buf = np.zeros(25)
        buf[8:14] = 1.0          # an event crossing the 10-frame loop point
        out = core.loop_wrap(buf, 10)
        self.assertEqual(out.shape, (10,))
        self.assertAlmostEqual(float(np.sum(out)), 6.0)
        self.assertEqual(out[:4].tolist(), [1.0, 1.0, 1.0, 1.0])
        st = core.loop_wrap(np.ones((15, 2)), 10)
        self.assertEqual(st.shape, (10, 2))

    def test_crossfade_loop(self):
        x = core.pink(RATE, core.cue_rng(4))
        y = core.crossfade_loop(x, 2000)
        self.assertEqual(y.shape[0], RATE - 2000)
        self.assertEqual(core.check_signal(core.normalize_peak(y, -6.0), RATE, "loop", True), [])

    def test_normalisation(self):
        x = core.sine(200.0, 4000, RATE) * 0.1
        self.assertAlmostEqual(core.peak_db(core.normalize_peak(x, -6.0)), -6.0, places=6)
        n = core.white(RATE, core.cue_rng(3))
        self.assertAlmostEqual(core.rms_db(core.normalize_rms(n, -20.0, -1.0)), -20.0, places=3)
        capped = core.normalize_rms(n, -3.0, -1.0)
        self.assertLessEqual(core.peak_db(capped), -1.0 + 1e-9)

    def test_checks_find_each_problem(self):
        good = core.normalize_peak(core.sine(220.0, 4000, RATE) * core.adsr(4000, RATE, 0.01, 0.05, 0.5, 0.05), -6.0)
        self.assertEqual(core.check_signal(good, RATE, "sfx", False), [])
        self.assertTrue(any("clipping" in p for p in core.check_signal(good * 4.0, RATE, "sfx", False)))
        self.assertTrue(any("silent" in p for p in core.check_signal(good * 1e-5, RATE, "sfx", False)))
        self.assertTrue(any("DC" in p for p in core.check_signal(good + 0.2, RATE, "sfx", False)))
        long = core.normalize_peak(core.sine(220.0, core.n_frames(2.5, RATE), RATE), -6.0)
        self.assertTrue(any("longer" in p for p in core.check_signal(long, RATE, "sfx", False)))
        ramp = np.linspace(-0.5, 0.5, 4000)
        self.assertTrue(any("seam" in p for p in core.check_signal(ramp, RATE, "loop", True)))

    def test_wav_writers(self):
        x = core.normalize_peak(core.sine(440.0, 1000, RATE), -6.0)
        data = core.wav_bytes_pcm16(x, RATE)
        self.assertEqual(data[:4], b"RIFF")
        self.assertEqual(len(data), 44 + 2000)
        back, rate = core.read_wav_pcm16(data)
        self.assertEqual(rate, RATE)
        self.assertTrue(np.allclose(back[:, 0], x, atol=1.0 / 32767.0))
        self.assertEqual(core.wav_bytes_pcm16(x, RATE), data)
        f32 = core.wav_bytes_f32(core.pan(x, 0.0), RATE)
        self.assertEqual(len(f32), 44 + 1000 * 2 * 4)
        self.assertEqual(int.from_bytes(f32[20:22], "little"), 3)

    @unittest.skipUnless(shutil.which("ffmpeg"), "ffmpeg is not installed")
    def test_flac_export(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "m.flac"
            core.export_flac(core.normalize_peak(core.sine(220.0, 2000, RATE), -3.0), RATE, path)
            self.assertEqual(path.read_bytes()[:4], b"fLaC")


@unittest.skipUnless(encode.available(), "ffmpeg with libvorbis is not installed")
class EncoderTests(unittest.TestCase):
    def test_two_encodes_are_byte_identical_and_exact_in_length(self):
        x = core.normalize_peak(core.fft_filter(core.white(core.n_frames(2.0, RATE), core.cue_rng(1)),
                                                RATE, core.band_response(50.0, 3000.0)), -3.0)
        with tempfile.TemporaryDirectory() as tmp:
            src = Path(tmp) / "m.wav"
            src.write_bytes(core.wav_bytes_f32(x, RATE))
            a = Path(tmp) / "a.ogg"
            b = Path(tmp) / "b.ogg"
            encode.encode_ogg(src, a, 0, RATE, 1)
            encode.encode_ogg(src, b, 0, RATE, 1)
            self.assertEqual(a.read_bytes(), b.read_bytes())
            probe = shutil.which("ffprobe")
            if probe:
                out = subprocess.run([probe, "-v", "error", "-show_entries", "stream=duration_ts",
                                      "-of", "default=nw=1:nk=1", str(a)], capture_output=True, text=True).stdout
                self.assertEqual(int(out.strip()), x.shape[0])

    def test_versions_are_reported(self):
        self.assertNotEqual(encode.ffmpeg_version(), "unknown")
        self.assertNotEqual(encode.libvorbis_version(), "")


class PipelineTests(unittest.TestCase):
    def test_every_generator_declares_valid_cues(self):
        cues = build_audio.collect(None)
        self.assertGreater(len(cues), 0)
        for fam, _module, cue in cues:
            self.assertTrue(str(cue["path"]).startswith("res://assets/audio/"), cue["path"])
            r = build_audio.render(fam, cue)
            self.assertEqual(r["problems"], [], "%s/%s" % (fam, cue["name"]))

    def test_qoa_size_formula(self):
        self.assertEqual(build_audio.qoa_bytes(4410, 1), 8 + 24 * 1 + 8 * 221)
        self.assertEqual(build_audio.qoa_bytes(10240, 2), 2 * (8 + 24 * 2 + 8 * 512))

    def test_params_hash_ignores_key_order(self):
        self.assertEqual(manifest.params_hash({"a": 1, "b": [1, 2]}), manifest.params_hash({"b": [1, 2], "a": 1}))
        self.assertNotEqual(manifest.params_hash({"a": 1}), manifest.params_hash({"a": 2}))

    def test_manifest_compare_separates_toolchain_from_content(self):
        a = {"tools": {"numpy": "1"}, "files": {"x": {"master_hash": "1", "file_hash": "2"}}}
        b = json.loads(json.dumps(a))
        b["tools"]["numpy"] = "2"
        d = manifest.compare(a, b)
        self.assertEqual(len(d["toolchain"]), 1)
        self.assertEqual(d["content"], [])
        b["files"]["x"]["file_hash"] = "3"
        self.assertEqual(len(manifest.compare(a, b)["content"]), 1)

    def test_shipped_manifest_lists_every_generated_file(self):
        doc = manifest.load(build_audio.ROOT)
        paths = {c["path"] for _f, _m, c in build_audio.collect(None)}
        self.assertEqual(set(doc.get("files", {})), paths)


class ScoreTests(unittest.TestCase):
    """P23: the loudness the score and ambience are balanced by, the phrase writer's variants and
    the frames the loops are cut to."""

    def test_loudness_follows_bs1770(self):
        t = np.arange(RATE * 4) / RATE
        tone = np.sin(2.0 * np.pi * 997.0 * t)
        # the standard's calibration: a full-scale 997 Hz sine in one channel reads -3.01 LUFS
        self.assertAlmostEqual(core.loudness_lufs(tone, RATE), -3.01, delta=0.02)
        self.assertAlmostEqual(core.loudness_lufs(np.stack([tone, tone], axis=1), RATE), 0.0, delta=0.02)
        # the gates: silence after the tone does not lower its loudness
        quiet = tone * 0.25
        padded = np.concatenate([quiet, np.zeros(RATE * 4)])
        self.assertAlmostEqual(core.loudness_lufs(padded, RATE), core.loudness_lufs(quiet, RATE), delta=0.2)
        self.assertEqual(core.loudness_lufs(np.zeros(RATE), RATE), -120.0)
        # the K-weighting: a 100 Hz tone reads quieter than a 2 kHz tone of the same level
        low = core.loudness_lufs(np.sin(2.0 * np.pi * 100.0 * t), RATE)
        high = core.loudness_lufs(np.sin(2.0 * np.pi * 2000.0 * t), RATE)
        self.assertGreater(high - low, 3.0)

    def test_normalize_lufs_meets_its_target_under_the_peak_cap(self):
        n = core.normalize_lufs(core.white(RATE * 3, core.cue_rng(5)) * 0.1, RATE, -20.0, -1.0)
        self.assertAlmostEqual(core.loudness_lufs(n, RATE), -20.0, places=6)
        capped = core.normalize_lufs(n, RATE, -2.0, -6.0)
        self.assertLessEqual(core.peak_db(capped), -6.0 + 1e-9)
        self.assertEqual(core.normalize_lufs(np.zeros(100), RATE, -20.0).tolist(), [0.0] * 100)

    def test_melody_variants_fit_the_scheduler(self):
        import gen_music
        for set_name in ("calm", "wild", "ancient"):
            variants = []
            for v in ("a", "b", "c"):
                notes = gen_music.melody_notes(set_name, v)
                self.assertGreater(len(notes), 8, set_name + v)
                # every phrase starts after its segment's downbeat and ends before its last half beat
                self.assertEqual(mus.check_phrases(notes, gen_music.SEGMENT_BEATS), [], set_name + v)
                self.assertTrue(all(0.0 <= b < gen_music.ZONE_BEATS for b, *_rest in notes), set_name + v)
                variants.append(tuple(notes))
            self.assertEqual(len(set(variants)), 3, set_name + ": three different variants")

    def test_ornaments_are_seeded_and_keep_the_segment_edges(self):
        import gen_music
        notes = gen_music.melody_notes("wild", "a")
        a = mus.ornament(notes, core.cue_rng(11), prob=0.6, style="turn")
        b = mus.ornament(notes, core.cue_rng(11), prob=0.6, style="turn")
        self.assertEqual(a, b)
        self.assertGreater(len(a), len(notes))
        self.assertEqual(mus.check_phrases([n[:4] for n in a], gen_music.SEGMENT_BEATS), [])
        self.assertTrue(mus.check_phrases([(0.0, 1.0, 0, 0)], 16), "a note on the downbeat is reported")

    def test_check_phrases_finds_a_note_ringing_into_the_next_segment(self):
        self.assertTrue(mus.check_phrases([(14.0, 2.0, 0, 0)], 16))
        self.assertEqual(mus.check_phrases([(14.0, 1.5, 0, 0)], 16), [])

    def test_the_frames_are_whole_bars(self):
        import gen_music
        self.assertEqual(mus.frames(gen_music.ZONE_BEATS * mus.beat_s(gen_music.ZONE_BPM)), 661500)
        self.assertEqual(mus.frames(gen_music.BOSS_BEATS * mus.beat_s(gen_music.BOSS_BPM)), 610615)
        self.assertEqual(mus.degree_midi(0), 62)           # D4
        self.assertEqual(mus.degree_midi(5), 71)           # the dorian B natural
        self.assertEqual(mus.degree_midi(5, mus.AEOLIAN), 70)
        self.assertEqual(mus.degree_midi(-1), 60)          # C4, the step below

    def test_loop_noise_is_circular(self):
        n = RATE * 2
        for color in ("white", "pink", "brown"):
            x = amb.loop_noise(n, core.cue_rng(21), 200.0, 2000.0, color)
            self.assertEqual(x.shape[0], n)
            self.assertAlmostEqual(core.rms(x), 1.0, places=6)
            steps = np.abs(np.diff(x))
            # the wrap from the last frame to the first is an ordinary step of the noise
            self.assertLessEqual(abs(float(x[0] - x[-1])), float(np.max(steps)), color)


class WorldTests(unittest.TestCase):
    """P28: the world's families - the regions' melodies fit the scheduler, the bosses' frames are
    whole bars of their own tempo, every world cue is the world's (scope, folder, seed range), its
    effects are short enough to play as samples, and the budgets hold by the build's arithmetic."""

    FOLDERS = {"world_music": "res://assets/audio/music/world/",
               "world_ambience": "res://assets/audio/ambience/world/",
               "world_sfx": "res://assets/audio/sfx/world/"}

    def test_the_regions_melody_variants_fit_the_scheduler(self):
        import gen_world_music as W
        for region in W.REGIONS:
            variants = []
            for v in ("a", "b", "c"):
                notes = W.melody_notes(region, v)
                self.assertGreater(len(notes), 4, region + v)
                # every phrase starts after its segment's downbeat and ends before its last half beat
                self.assertEqual(mus.check_phrases(notes, W.SEGMENT_BEATS), [], region + v)
                self.assertTrue(all(0.0 <= b < W.ZONE_BEATS for b, *_rest in notes), region + v)
                variants.append(tuple(notes))
            self.assertEqual(len(set(variants)), 3, region + ": three different variants")

    def test_the_boss_frames_are_whole_bars_of_their_tempo(self):
        import gen_world_music as W
        self.assertEqual(W.ZONE_FRAME, "zone_96")
        self.assertEqual(mus.frames(W.REGIMENT_BEATS * mus.beat_s(W.REGIMENT_BPM)), 567000)
        self.assertEqual(mus.frames(W.MATRIARCH_BEATS * mus.beat_s(W.MATRIARCH_BPM)), 504000)
        self.assertEqual(mus.frames(W.HARROK_BEATS * mus.beat_s(W.HARROK_BPM)), 588000)
        self.assertEqual(W.MATRIARCH_BEATS % W.MATRIARCH_BEATS_PER_BAR, 0)
        self.assertEqual(len({W.REGIMENT_FRAME, W.MATRIARCH_FRAME, W.HARROK_FRAME, W.ZONE_FRAME}), 4)

    def test_every_world_cue_is_the_worlds(self):
        paths = set()
        for fam, folder in self.FOLDERS.items():
            cues = [c for _f, _m, c in build_audio.collect({fam})]
            self.assertGreater(len(cues), 10, fam)
            seeds = [c["seed"] for c in cues]
            self.assertEqual(len(seeds), len(set(seeds)), fam + ": one seed a file")
            for c in cues:
                self.assertEqual(c.get("scope"), "world", c["name"])
                self.assertTrue(c["path"].startswith(folder), c["path"])
                self.assertTrue(280000 <= c["seed"] < 283000, "%s: seed %d" % (c["name"], c["seed"]))
                self.assertNotIn(c["path"], paths)
                paths.add(c["path"])

    def test_the_worlds_effects_are_samples_and_the_budgets_hold(self):
        files = manifest.load(build_audio.ROOT).get("files", {})
        sfx = [e for e in files.values() if e.get("family") == "world_sfx"]
        self.assertGreater(len(sfx), 90)
        for e in sfx:
            self.assertEqual(e["kind"], "sfx")
            self.assertLessEqual(float(e["seconds"]), 2.0)
        _lines, problems = build_audio.budget_report(files, build_audio.ROOT, actual=True)
        self.assertEqual(problems, [])
        world = sum(build_audio.imported_bytes(e) for e in files.values() if e.get("scope") == "world")
        self.assertLessEqual(world, 5.5 * 1048576.0, "the world adds at most 5.5 MB")
        reg = build_audio.registered_seconds(files, build_audio.ROOT)
        self.assertLessEqual(reg["level.world"], 170.0)
        self.assertLessEqual(reg["level.valley"], 110.0)
        # the estimate before encoding (the calibrated rates) is the build's within 1 %
        est = sum(build_audio.estimate_bytes(e) for e in files.values() if e.get("scope") == "world")
        self.assertLess(abs(est - world) / world, 0.01)


if __name__ == "__main__":
    unittest.main(verbosity=1)
