#!/usr/bin/env node
// The Web sound-effects check's own test (C3): tools/web/sfx_check.mjs's analysis without a browser - a made-up
// recording of the output (quanta of 128 frames at 44.1 kHz) with effect cues and the sample sources they
// started:
//   * the level over a window, the cue kinds (a swing, a hit, a step);
//   * with the music muted a swing and a hit that made sound count as sounded, one whose source stayed at gain
//     zero (a 3D voice never panned) or whose output is silent does not, a cue with no source never started;
//   * with the music playing a cue must stand --min-gain-db over the quiet before it;
//   * the bed: the output outside every effect's window;
//   * C3b: a near voice's stereo balance and the summary of where the near voices sit.
// Prints TEST_SFX_CHECK with the count of checks and failures; exits 1 on a failure.
//
// Usage (from the project folder): node tools/web/test_sfx_check.mjs [--no-browser]

import { analyse, balanceDb, cueKind, levelOver, panSummary, parseArgs } from './sfx_check.mjs';

let checks = 0;
let failures = 0;
function check(cond, what) {
  checks += 1;
  if (!cond) {
    failures += 1;
    console.log(`  FAIL: ${what}`);
  }
}

const Q = 128 / 44100;
// A recording of `seconds` at a mean square `bed`, with [from, to, ms] spans louder.
function recording(seconds, bed, spans) {
  const out = [];
  for (let t = 0; t < seconds; t += Q) {
    let ms = bed;
    for (const [a, b, v] of spans) if (t >= a && t < b) ms += v;
    out.push([t, ms, Math.sqrt(ms) * 3]);
  }
  return out;
}

const loud = 0.01;   // -20 dBFS RMS
check(Math.abs(levelOver(recording(1, loud, []), 0, 1).rms_db + 20) < 0.2, 'a -20 dBFS recording measures -20 dBFS');
check(levelOver(recording(1, 0, []), 0, 1).rms_db === -200, 'silence measures as none');
check(cueKind({ cue: 'sfx.swing.blunt.light', reason: 'swing' }) === 'swing', 'a swing');
check(cueKind({ cue: 'sfx.hit.flesh.light', reason: 'hit' }) === 'hit', 'a hit on a body');
check(cueKind({ cue: 'sfx.hit.stone', reason: 'hit_plate' }) === 'hit', 'a hit on a titan plate');
check(cueKind({ cue: 'sfx.block.guard', reason: 'block' }) === 'hit', 'a blow on a guard');
check(cueKind({ cue: 'sfx.step.giant_s1.soft', reason: 'step' }) === 'step', 'a footfall');
check(cueKind({ cue: 'sfx.swing.mass.heavy', reason: 'swing_mass' }) === 'swing', "a big giant's swing mass");

const cues = [
  { cue: 'sfx.swing.blunt.light', reason: 'swing', bus: 'SFX', ctx_t: 1.0, level_db: 2.8 },
  { cue: 'sfx.hit.flesh.light', reason: 'hit', bus: 'SFX', ctx_t: 2.0, level_db: 2.4 },
  { cue: 'sfx.swing.blunt.heavy', reason: 'swing', bus: 'SFX', ctx_t: 3.0, level_db: 2.0 },
  { cue: 'sfx.hit.wood', reason: 'hit_prop', bus: 'SFX', ctx_t: 4.0, level_db: 1.0 },
  { cue: 'mus.x', reason: '', bus: 'Music', ctx_t: 4.5 },
];
const sources = [
  { t: 1.05, dur: 0.3, gain0: [0.7, 0.7], gain80: [0.7, 0.7] },
  { t: 2.05, dur: 0.26, gain0: [0.8, 0.8], gain80: [0.8, 0.8] },
  { t: 3.05, dur: 0.44, gain0: [0, 0], gain80: [0, 0] },   // never panned: silent
];
const muted = analyse({ cues, sources, quanta: recording(6, 0, [[1.05, 1.35, loud], [2.05, 2.3, loud]]) },
  parseArgs(['--mute=Music:Ambience']));
const s = muted.summary;
check(s.fx_cues === 4, 'the music cue is not an effect');
check(s.swing.cues === 2 && s.swing.sounded === 1, `one swing of two sounded (${s.swing.sounded})`);
check(s.swing.zero_gain_at_start === 1, 'the never-panned swing is counted at zero gain');
check(s.hit.cues === 2 && s.hit.sounded === 1 && s.hit.never_started === 1, 'one hit sounded, one never started');
check(muted.rows[0].start_delay_ms === 50, 'the source is matched to its cue (50 ms later)');
check(Math.abs(muted.rows[0].rms_db + 20) < 0.5, `the swing's window measures -20 dBFS (${muted.rows[0].rms_db})`);
check(s.bed.rms_db === -200, 'with the music muted the rest is silence');

// With the music playing: a swing 3 dB over the music does not count; one 12 dB over it does.
const bed = 0.001;   // -30 dBFS
const full = analyse({ cues: cues.slice(0, 2), sources: sources.slice(0, 2),
  quanta: recording(6, bed, [[1.05, 1.35, bed], [2.05, 2.3, 0.015]]) }, parseArgs([]));
check(full.summary.swing.sounded === 0, 'a swing 3 dB over the music is not heard');
check(full.summary.hit.sounded === 1, 'a hit 12 dB over the music is');
check(Math.abs(full.summary.bed.rms_db + 30) < 0.5, `the bed measures the music (${full.summary.bed.rms_db})`);

// C3b: a near voice's stereo balance from its gains, and how the near voices sit across the field.
check(balanceDb([1, 1]) === 0, 'equal gains: centred');
check(balanceDb([1, 0.5]) > 5.9 && balanceDb([1, 0.5]) < 6.1, `left twice right: +6 dB (${balanceDb([1, 0.5])})`);
check(balanceDb([0, 1]) === null && balanceDb(null) === null, 'an unknown or silent side: no balance');
const pans = panSummary([{ balance_db: 4 }, { balance_db: -3 }, { balance_db: 0.5 }, { balance_db: null }]);
check(pans.panned_left === 1 && pans.panned_right === 1 && pans.centred === 1 && pans.widest_db === 4,
  `one left, one right, one centred (${JSON.stringify(pans)})`);

let bad = false;
try { parseArgs(['--nonsense']); } catch (e) { bad = true; }
check(bad, 'an unknown option is refused');

console.log(`TEST_SFX_CHECK ${JSON.stringify({ checks, failures })}`);
process.exit(failures === 0 ? 0 : 1);
