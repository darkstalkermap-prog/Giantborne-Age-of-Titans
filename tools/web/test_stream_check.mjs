#!/usr/bin/env node
// The web stream check's own test for --audio (M7 gate): tools/web/stream_check.mjs --world --audio
// against a stub launcher in headless Chromium - no engine, no build: a play.html that makes an
// AudioContext, plays a stand-in for the no-threads build's mixer (an AudioWorkletNode named
// godot-processor that sounds only while the main thread answers its "read" messages) and prints
// what the game prints on a world walk: the music director's AUDIO_MUSIC marks (a region's set, then
// after a border the next region's), WORLD_WALK_START and WORLD_WALK_END, PERF_RESULT and
// AUTOPILOT_RESULT. By mode (stream_check's --route=M, which the game gets as --route=M):
//   * music: the walk crosses a border with no gap in the music: the recorder arms at the walk's
//     start, disarms at its end, the criterion is MET across one border and the check ends a bare OK;
//   * stutter: the main thread busy for 150 ms three times during the walk: holes over 50 ms that
//     the main thread explains - the default check passes but ends "OK (the plan's audio criterion
//     NOT MET ...)", --strict fails, and audio_check.mjs --replay places the saved trace's holes;
//   * noborder: the walk stays in one region's music: the check fails (no border crossed);
//   * nomusic: no zone music ever plays: the check fails (the recorder never armed).
// Before the M7 gate stream_check.mjs had no recorder and audio_check.mjs could not start in the
// world (it waits for the title's music): the gate's world audio check could not be run.
// Prints TEST_STREAM_CHECK with the count of checks and failures; exits 1 on a failure.
//
// Usage (from the project folder): node tools/web/test_stream_check.mjs [--keep]
//   --keep   keep the stub folder and the reports (printed)
// Needs what stream_check.mjs needs: Playwright and its Chromium. About a minute.

import { spawnSync } from 'node:child_process';
import { mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = resolve(dirname(fileURLToPath(import.meta.url)), '..', '..');
const CHECK = join(ROOT, 'tools', 'web', 'stream_check.mjs');
const AUDIO_CHECK = join(ROOT, 'tools', 'web', 'audio_check.mjs');
const KEEP = process.argv.includes('--keep');

const STUB = `<!doctype html>
<html>
<head><meta charset="utf-8"><title>Giantborn: Age of Titans</title></head>
<body>
<!-- tools/web/test_stream_check.mjs's stub launcher (no engine). -->
<div id="status">Stub launcher</div>
<button id="play">Play</button>
<canvas id="game-canvas" tabindex="0" width="64" height="36"></canvas>
<script>
(function () {
  const args = (new URLSearchParams(location.search).get('args') || '').split(',');
  // stream_check.mjs passes its --route=R to the game: the stub reads its mode from R.
  const mode = (args.find((a) => a.startsWith('--route=')) || '--route=music').split('=')[1];
  // The main thread drawing a slow frame.
  const busy = (ms) => { const t = performance.now(); while (performance.now() - t < ms) { /* busy */ } };
  // The mixer's stand-in: asks the main thread for every quantum and sounds only while it answers.
  const DRIVER = \`
class StubDriver extends AudioWorkletProcessor {
  constructor() {
    super();
    this.fed = -1;
    this.phase = 0;
    this.port.onmessage = () => { this.fed = currentTime; };
  }
  process(inputs, outputs) {
    this.port.postMessage({ cmd: 'read' });
    const on = this.fed >= 0 && currentTime - this.fed < 0.02;
    const out = outputs[0];
    for (let i = 0; i < out[0].length; i++) {
      const v = on ? 0.1 * Math.sin(this.phase) : 0;
      this.phase += 2 * Math.PI * 220 / sampleRate;
      for (const ch of out) ch[i] = v;
    }
    return true;
  }
}
registerProcessor('godot-processor', StubDriver);\`;
  const say = (line) => console.log(line);
  document.getElementById('play').addEventListener('click', async () => {
    const ctx = new AudioContext();
    await ctx.audioWorklet.addModule(URL.createObjectURL(new Blob([DRIVER], { type: 'application/javascript' })));
    const node = new AudioWorkletNode(ctx, 'godot-processor', { numberOfInputs: 0, numberOfOutputs: 1, outputChannelCount: [2] });
    node.port.onmessage = () => node.port.postMessage({ cmd: 'data' });
    node.connect(ctx.destination);
    say('stub: ' + mode);
    if (mode !== 'nomusic') {
      setTimeout(() => say('AUDIO_MUSIC ' + JSON.stringify({ set: 'music.region_crownmarch', state: 'zone' })), 300);
    }
    setTimeout(() => say('WORLD_WALK_START ' + JSON.stringify({ route_points: 3, speed_mps: 0 })), 600);
    if (mode === 'music' || mode === 'stutter') {
      setTimeout(() => say('AUDIO_MUSIC ' + JSON.stringify({ set: 'music.region_drowned_steps', state: 'zone' })), 2600);
    }
    // Three slow frames inside the walk, none across its start or end.
    if (mode === 'stutter') for (const at of [1700, 2700, 3700]) setTimeout(() => busy(150), at);
    setTimeout(() => {
      say('WORLD_WALK_END ' + JSON.stringify({ finished: true, ticks: 240 }));
      setTimeout(() => {
        say('PERF_RESULT ' + JSON.stringify({ renderer: 'stub', adapter: 'none', quality: 'low',
          frame_ms: { p50: 16.7, p99: 20, max: 30 }, draw_calls: { p50: 10, max: 20 }, cpu_tick_ms: { p50: 1, max: 2 } }));
        say('AUTOPILOT_RESULT ' + JSON.stringify({ errors: 0, world_walk: { mode: 'walk', speed_mps: 0, metres: 40,
          seconds: 4, finished: true, min_margin_m: 300, max_loaded: 9, loads: 9, unloads: 0, thrash: 0,
          check_failures: [], region_changes: mode === 'music' || mode === 'stutter'
            ? [{ s: 2, region: 'region.drowned_steps', previous: 'region.crownmarch' }] : [] } }));
      }, 200);
    }, 4600);
  });
})();
</script>
</body>
</html>
`;

let checks = 0;
const failures = [];
function check(ok, what) {
  checks++;
  if (!ok) failures.push(what);
  console.log(`  ${ok ? 'ok  ' : 'FAIL'} ${what}`);
}

function run(script, args) {
  const r = spawnSync(process.execPath, [script, ...args], { cwd: ROOT, encoding: 'utf8', timeout: 180000 });
  return { code: r.status, out: r.stdout || '', err: r.stderr || '' };
}

function report(file) {
  try {
    return JSON.parse(readFileSync(file, 'utf8'));
  } catch (e) {
    return null;
  }
}

const dir = mkdtempSync(join(tmpdir(), 'stream_check_test-'));
writeFileSync(join(dir, 'play.html'), STUB);
// stream_check.mjs passes --route=R to the game: the stub reads its mode from the route's text.
function checkRun(mode, more = []) {
  const json = join(dir, `${mode}${more.includes('--strict') ? '_strict' : ''}.json`);
  const r = run(CHECK, [`--build=${dir}`, '--world', '--audio', '--music-s=3', '--timeout-s=60',
    `--route=${mode}`, ...more, `--json=${json}`]);
  return { ...r, rep: report(json) || {}, json };
}

console.log('music: the walk crosses a region border with no gap in the music');
{
  const r = checkRun('music');
  const a = r.rep.audio || {};
  const c = a.criterion || {};
  check(r.code === 0, `the check passes (exit ${r.code})`);
  check(r.out.trim().endsWith('stream_check: OK'), 'it ends a bare OK');
  check(r.out.includes("the plan's criterion (no silent run over 50 ms in 3 s of music across a region border): MET"), 'it prints the criterion as met');
  check(c.met === true && c.holes === 0 && c.borders === 1, `the report's criterion is met across one border (${JSON.stringify(c)})`);
  check(Array.isArray(a.sets) && a.sets.join(',') === 'music.region_crownmarch,music.region_drowned_steps',
    `the sets that followed one another while it recorded (${JSON.stringify(a.sets)})`);
  check(a.music && a.music.seconds >= 2.7 && a.music.seconds <= 5, `it recorded the walk, from its start to its end (${a.music && a.music.seconds} s)`);
  check(a.auto && a.auto.armed === true && a.auto.ended === true, 'the recorder armed at the walk\'s start and disarmed at its end');
  check(a.level === 'level.world' && a.registered_s > 100, `the cap is the world's (${a.registered_s} s registered)`);
  check(r.rep.url_args && r.rep.url_args.includes('--audio-stats') && r.rep.url_args.includes('--mode=world'),
    'the game gets --audio-stats and the world\'s arguments');
}

console.log('stutter: three slow frames of 150 ms leave the stand-in mixer unserved during the walk');
{
  const r = checkRun('stutter');
  const a = r.rep.audio || {};
  const c = a.criterion || {};
  const m = a.music || {};
  check(r.code === 0, `the default check passes on the main thread's holes (exit ${r.code})`);
  check(r.out.includes("stream_check: OK (the plan's audio criterion NOT MET:"), 'it ends "OK (the plan\'s audio criterion NOT MET ...)", not a bare OK');
  check(c.met === false && c.holes >= 3, `the report's criterion is not met: the slow frames' holes (${JSON.stringify(c)})`);
  check(m.holes_while_unserved === c.holes && (m.holes_elsewhere || []).length === 0,
    `every hole is placed on the main thread (${m.holes_while_unserved} of ${c.holes})`);
  check(r.rep.trace && Array.isArray(r.rep.trace.holes) && r.rep.trace.holes.length >= 3, 'the --json report keeps the trace');
  const rp = run(AUDIO_CHECK, [`--replay=${r.json}`]);
  check(rp.code === 0 && rp.out.includes('while the main thread left the mixer unserved'), `audio_check.mjs --replay places them again (exit ${rp.code})`);
  const s = checkRun('stutter', ['--strict']);
  check(s.code === 1 && /a [\d.]+ ms hole in the music/.test(s.out), `--strict fails on them (exit ${s.code})`);
  check(((s.rep.audio || {}).criterion || {}).mode === 'strict', 'the strict report names its mode');
}

console.log('noborder: the walk stays in one region\'s music');
{
  const r = checkRun('noborder');
  const a = r.rep.audio || {};
  check(r.code === 1, `the check fails (exit ${r.code})`);
  check(r.out.includes('the recording crossed 0 region border(s), fewer than 1'), 'it says no border was crossed while recording');
  check(a.borders === 0 && (a.criterion || {}).met === true, 'the music itself had no hole');
}

console.log('nomusic: no zone music ever plays');
{
  const r = checkRun('nomusic');
  check(r.code === 1, `the check fails (exit ${r.code})`);
  check(r.out.includes('the recorder never armed (no zone music once the walk set off)'), 'it says the recorder never armed');
  check(r.out.includes("the plan's criterion (no silent run over 50 ms in 3 s of music across a region border): NOT MEASURED"), 'it prints the criterion as not measured');
}

if (KEEP) console.log(`the stub and the reports: ${dir}`);
else rmSync(dir, { recursive: true, force: true });
console.log(`TEST_STREAM_CHECK: ${checks} checks, ${failures.length} failures`);
for (const f of failures) console.log(`FAIL  ${f}`);
process.exit(failures.length === 0 ? 0 : 1);
