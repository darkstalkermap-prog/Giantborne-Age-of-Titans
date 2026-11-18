#!/usr/bin/env node
// The web audio check's own test (M6 gate): tools/web/audio_check.mjs against a stub launcher in
// headless Chromium - no engine, no build: a play.html with the game's title that makes an
// AudioContext and, by mode (passed as a game argument, --stub-mode=M), plays a stand-in for the
// no-threads build's mixer (an AudioWorkletNode named godot-processor that sounds only while the
// main thread answers its "read" messages) and prints the music director's AUDIO_MUSIC marks:
//   * stall: never reaches the title's music (a launcher stuck "unpacking", its main thread busy):
//     the check times out and its report still carries the trace since the page's load (marked
//     partial), the page's state (its status line) and the console tail, prints the plan's criterion
//     as NOT MEASURED, and --replay refuses the partial trace;
//   * music: plays without a gap: the criterion is MET and the check ends a bare OK;
//   * stutter: the main thread busy for 150 ms three times in the recorded music (slow frames), so
//     the mixer goes unserved and the music has holes over 50 ms that the main thread explains: the
//     default check passes but ends "OK (the plan's criterion NOT MET ...)", and --strict fails.
//   * late (P49): a title that prints the game's UI_PROBE lines and keeps New Game disabled behind
//     "Preparing..." for 5 s after its music (the title's warm-up on a busy machine): an Enter before
//     that is lost, as in the game. The check waits for the title's state with warming false and its
//     one Enter opens the creator;
//   * lost (P49): an enabled title that swallows the first Enter (a press that fell into a long
//     frame): the check sees no creator and presses again;
//   * dead (P49): an enabled title that never opens the creator: the check says so after its presses
//     instead of pressing Begin at a title and waiting ten minutes for the Hollow's music.
// Before the M6 gate a timed-out run left no trace and a default pass on such holes printed a bare
// OK. Prints TEST_AUDIO_CHECK with the count of checks and failures; exits 1 on a failure.
//
// Usage (from the project folder): node tools/web/test_audio_check.mjs [--keep]
//   --keep   keep the stub folder and the reports (printed)
// Needs what audio_check.mjs needs: Playwright and its Chromium. About three minutes.

import { spawnSync } from 'node:child_process';
import { mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = resolve(dirname(fileURLToPath(import.meta.url)), '..', '..');
const CHECK = join(ROOT, 'tools', 'web', 'audio_check.mjs');
const KEEP = process.argv.includes('--keep');

const STUB = `<!doctype html>
<html>
<head><meta charset="utf-8"><title>Giantborn: Age of Titans</title></head>
<body>
<!-- tools/web/test_audio_check.mjs's stub launcher (no engine). BUILD: { pckParts: 1 } -->
<div id="status">Stub launcher</div>
<button id="play">Play</button>
<canvas id="game-canvas" tabindex="0" width="64" height="36"></canvas>
<script>
(function () {
  const args = (new URLSearchParams(location.search).get('args') || '').split(',');
  const mode = (args.find((a) => a.startsWith('--stub-mode=')) || '--stub-mode=stall').split('=')[1];
  const status = document.getElementById('status');
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
  document.getElementById('play').addEventListener('click', async () => {
    const ctx = new AudioContext();
    console.log('stub: ' + mode);
    if (mode === 'stall') {
      status.textContent = 'Stub: unpacking forever';
      setInterval(() => busy(80), 100);
      return;
    }
    await ctx.audioWorklet.addModule(URL.createObjectURL(new Blob([DRIVER], { type: 'application/javascript' })));
    const node = new AudioWorkletNode(ctx, 'godot-processor', { numberOfInputs: 0, numberOfOutputs: 1, outputChannelCount: [2] });
    node.port.onmessage = () => node.port.postMessage({ cmd: 'data' });
    node.connect(ctx.destination);
    console.log('AUDIO_MUSIC ' + JSON.stringify({ set: 'music.title', state: 'title' }));
    // New Game (Enter) opens the creator; only Begin (Ctrl+Enter) there starts the Valley's music.
    // P49: the probe modes print the game's UI_PROBE state lines; "late" enables New Game 5 s after the
    // music, "lost" swallows the first Enter on the enabled title, "dead" swallows them all.
    const probe = mode === 'late' || mode === 'lost' || mode === 'dead';
    const say = (state) => console.log('UI_PROBE ' + JSON.stringify(Object.assign({ t: 'state', mode: 'title', level: '', loading: false, tab: '', context: '', category: '' }, state)));
    let enabled = mode !== 'late';
    let swallow = mode === 'lost' ? 1 : (mode === 'dead' ? 1e9 : 0);
    window.__stubEnters = { early: 0, swallowed: 0 };
    if (probe) say({ top: 'title', warming: !enabled });
    if (mode === 'late') setTimeout(() => { enabled = true; say({ top: 'title', warming: false }); }, 5000);
    let creator = false;
    let begun = false;
    window.addEventListener('keydown', (e) => {
      if (e.key !== 'Enter' || begun) return;
      if (!e.ctrlKey) {
        if (creator) return;
        if (!enabled) { window.__stubEnters.early += 1; console.log('stub: Enter before the title enabled'); return; }
        if (swallow > 0) { swallow -= 1; window.__stubEnters.swallowed += 1; console.log('stub: Enter swallowed'); return; }
        creator = true;
        if (probe) say({ top: 'creator', warming: false, context: 'new_game', category: 'Body' });
        return;
      }
      if (!creator) return;
      begun = true;
      console.log('AUDIO_MUSIC ' + JSON.stringify({ set: 'music.stub', state: 'zone' }));
      // Three slow frames inside the check's recording (it arms about 5.5-5.8 s after this mark and
      // records --music-s=4 s), none across its start or end.
      if (mode === 'stutter') for (const at of [6500, 7500, 8500]) setTimeout(() => busy(150), at);
    });
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

function run(args) {
  const r = spawnSync(process.execPath, [CHECK, ...args], { cwd: ROOT, encoding: 'utf8', timeout: 240000 });
  return { code: r.status, out: r.stdout || '', err: r.stderr || '' };
}

function report(file) {
  try {
    return JSON.parse(readFileSync(file, 'utf8'));
  } catch (e) {
    return null;
  }
}

const dir = mkdtempSync(join(tmpdir(), 'audio_check_test-'));
writeFileSync(join(dir, 'play.html'), STUB);
const build = `--build=${dir}`;

console.log('stall: the launcher never reaches the title\'s music (timeout 4 s)');
{
  const json = join(dir, 'stall.json');
  const r = run([build, '--args=--stub-mode=stall', '--timeout-s=4', `--json=${json}`]);
  const rep = report(json) || {};
  const fs = rep.failure_state || {};
  check(r.code === 1, `the check fails (exit ${r.code})`);
  check(r.out.includes('audio_check: FAILED - timed out waiting for the title music'), 'it says what it waited for');
  check(r.out.includes("the plan's criterion (no silent run over 50 ms in 60 s of music): NOT MEASURED"), 'it prints the criterion as not measured');
  check(r.out.includes('stub: stall'), 'it prints the page\'s last console lines');
  check(r.out.includes('status "Stub: unpacking forever"'), 'it prints the launcher\'s status line');
  check(rep.criterion === undefined, 'the report holds no criterion verdict');
  check(fs.status_text === 'Stub: unpacking forever', `the report keeps the page's state (status "${fs.status_text}")`);
  check(fs.context && typeof fs.context.state === 'string', 'the report keeps the AudioContext\'s state');
  check(fs.page_frames && fs.page_frames.n > 0, `the report keeps the page's frames since its load (${fs.page_frames && fs.page_frames.n})`);
  check(fs.long_tasks && fs.long_tasks.n > 0, `the report keeps the main thread's long tasks (${fs.long_tasks && fs.long_tasks.n})`);
  check(rep.trace && rep.trace.partial === true && rep.trace.frames.length > 0, 'the report keeps the trace so far, marked partial');
  check(Array.isArray(rep.console_tail) && rep.console_tail.some((l) => l.includes('stub: stall')), 'the report keeps the console tail');
  const rp = run([`--replay=${json}`]);
  check(rp.code === 2 && rp.err.includes('partial trace'), `--replay refuses the partial trace (exit ${rp.code})`);
}

console.log('music: the stand-in mixer plays without a gap');
{
  const json = join(dir, 'music.json');
  const r = run([build, '--args=--stub-mode=music', '--music-s=3', `--json=${json}`]);
  const rep = report(json) || {};
  const c = rep.criterion || {};
  check(r.code === 0, `the check passes (exit ${r.code})`);
  check(r.out.trim().endsWith('audio_check: OK'), 'it ends a bare OK');
  check(r.out.includes("the plan's criterion (no silent run over 50 ms in 3 s of music): MET"), 'it prints the criterion as met');
  check(c.met === true && c.holes === 0, `the report's criterion is met (${JSON.stringify(c)})`);
  check(typeof c.mode === 'string' && c.mode.startsWith('default'), 'the report names the default mode');
  check(rep.begin_presses === 1 && typeof rep.new_game_to_hollow_s === 'number' && rep.new_game_to_hollow_s >= 4,
    `New Game (Enter) opened the creator and one Begin (Ctrl+Enter) started the Valley (${rep.begin_presses} press(es), ${rep.new_game_to_hollow_s} s)`);
}

console.log('stutter: three slow frames of 150 ms leave the stand-in mixer unserved');
{
  const json = join(dir, 'stutter.json');
  const r = run([build, '--args=--stub-mode=stutter', '--music-s=4', `--json=${json}`]);
  const rep = report(json) || {};
  const c = rep.criterion || {};
  const m = rep.music || {};
  check(r.code === 0, `the default check passes on the main thread's holes (exit ${r.code})`);
  check(r.out.includes("audio_check: OK (the plan's criterion NOT MET:"), 'it ends "OK (the plan\'s criterion NOT MET ...)", not a bare OK');
  check(r.out.includes("the plan's criterion (no silent run over 50 ms in 4 s of music): NOT MET"), 'it prints the criterion as not met');
  check(c.met === false && c.holes >= 3, `the report's criterion is not met: the three slow frames' holes (${JSON.stringify(c)})`);
  check(m.holes_while_unserved === c.holes && (m.holes_elsewhere || []).length === 0,
    `every hole is placed on the main thread (${m.holes_while_unserved} of ${c.holes})`);
  const s = run([build, '--args=--stub-mode=stutter', '--music-s=4', '--strict', `--json=${join(dir, 'strict.json')}`]);
  const sc = (report(join(dir, 'strict.json')) || {}).criterion || {};
  check(s.code === 1 && /audio_check: FAILED - a [\d.]+ ms hole in the music/.test(s.out), `--strict fails on them (exit ${s.code})`);
  check(sc.mode === 'strict' && sc.met === false, 'the strict report names its mode');
}

console.log('late: the title enables New Game 5 s after its music (P49)');
{
  const json = join(dir, 'late.json');
  const r = run([build, '--args=--stub-mode=late', '--music-s=2', `--json=${json}`]);
  const rep = report(json) || {};
  check(r.code === 0, `the check passes (exit ${r.code})`);
  check(rep.ui_probe === true && rep.title_warmed === true, 'it followed the title\'s probe lines and saw it preparing');
  check(typeof rep.title_ready_s === 'number' && rep.title_ready_s >= 4.5, `it waited for the buttons to enable (${rep.title_ready_s} s after the title's music)`);
  check(rep.enter_presses === 1, `one Enter, after the title enabled (${rep.enter_presses})`);
  check(!r.out.includes('stub: Enter before the title enabled'), 'no Enter fell before the title enabled');
  check(rep.begin_presses === 1, `and one Begin started the Valley (${rep.begin_presses})`);
  check((rep.url_args || []).includes('--ui-probe'), 'the game is started with --ui-probe');
}

console.log('lost: an enabled title swallows the first Enter (P49)');
{
  const json = join(dir, 'lost.json');
  const r = run([build, '--args=--stub-mode=lost', '--music-s=2', `--json=${json}`]);
  const rep = report(json) || {};
  check(r.code === 0, `the check passes (exit ${r.code})`);
  check(rep.enter_presses === 2, `it pressed Enter again when no creator opened (${rep.enter_presses} presses)`);
  check(rep.begin_presses === 1, `then one Begin (${rep.begin_presses})`);
}

console.log('dead: an enabled title never opens the creator (P49; timeout 60 s)');
{
  const json = join(dir, 'dead.json');
  const r = run([build, '--args=--stub-mode=dead', '--timeout-s=60', `--json=${json}`]);
  const rep = report(json) || {};
  check(r.code === 1, `the check fails (exit ${r.code})`);
  check(r.out.includes('audio_check: FAILED - New Game did not open the creator after 4 presses of Enter on the enabled title'),
    'it says the title did not open the creator');
  check(rep.enter_presses === 4 && (rep.begin_presses === undefined || rep.begin_presses === 0), `four Enters and no Begin (${rep.enter_presses}, ${rep.begin_presses})`);
}

if (KEEP) console.log(`the stub and the reports: ${dir}`);
else rmSync(dir, { recursive: true, force: true });
console.log(`TEST_AUDIO_CHECK: ${checks} checks, ${failures.length} failures`);
for (const f of failures) console.log(`FAIL  ${f}`);
process.exit(failures.length === 0 ? 0 : 1);
