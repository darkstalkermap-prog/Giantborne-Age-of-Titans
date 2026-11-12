#!/usr/bin/env node
// The web world check's own test (P39f): tools/web/world_check.mjs against a stub launcher in headless
// Chromium - no engine, no build. The stub's play.html, once Play is pressed, makes an AudioContext with a
// stand-in for the no-threads build's mixer (an AudioWorkletNode named godot-processor that sounds only
// while the main thread answers its "read" messages) and prints the title's music mark; on Enter it reads
// the save the check put into the page's IndexedDB (Godot's /userfs, at the slot's path) and prints what
// the game prints on a Continue, a fast travel and a walk: WORLD_WALK_LEVEL (the save's level, respawn
// and stage - or the Valley's New Game when it found no save), WORLD_TRAVEL, the arrival's
// WORLD_WALK_LEVEL, the music's zone marks, WORLD_WALK_START and WORLD_WALK_END, PERF_RESULT and
// AUTOPILOT_RESULT. Its mode is the last word of the check's --travel (world_check.mjs passes it to the
// game as --walk-travel=), e.g. --travel=world.cp.ok:
//   * ok: Continue at the fixture's respawn, the travel, a 64 s walk across a border with no gap in the
//     music - the check passes with a bare OK, the save found where the engine reads it;
//   * stutter: the main thread busy for 150 ms three times during the walk - holes the main thread
//     explains: the default check passes "OK (the plan's audio criterion NOT MET ...)", --strict fails;
//   * short: a walk of 30 s of game time - the check fails (under --walk-min-s);
//   * notravel: no travel is asked for - the check fails;
//   * newgame: the stub ignores the save and starts a New Game in the Valley - the check fails (Continue
//     did not load the fixture);
//   * noborder: the walk stays in one region's music - the check fails;
//   * warning: the engine warns while loading ("WARNING: ..." and its "at:" line, as the web build prints
//     push_warning through console.error) - the default check passes and lists it apart, --strict fails;
//   * error: the engine prints an error - the check fails;
//   * trailing: the main thread is busy for 250 ms in the task that ends the walk (150 ms before its
//     WORLD_WALK_END line, 100 ms after), so the recording ends in a hole no "read" could end - placed on
//     the main thread all the same (cut short by the walk's end), where the M7 gate's placing listed it
//     as a hole elsewhere and failed the default check (the first real world check's walk ended so).
// Prints TEST_WORLD_CHECK with the count of checks and failures; exits 1 on a failure.
//
// Usage (from the project folder): node tools/web/test_world_check.mjs [--keep]
//   --keep   keep the stub folder and the reports (printed)
// Needs what world_check.mjs needs: Playwright and its Chromium. About two minutes.

import { spawnSync } from 'node:child_process';
import { mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = resolve(dirname(fileURLToPath(import.meta.url)), '..', '..');
const CHECK = join(ROOT, 'tools', 'web', 'world_check.mjs');
const CONFIG = JSON.parse(readFileSync(join(ROOT, 'tools', 'web', 'world_check.json'), 'utf8'));
const FIXTURE = JSON.parse(readFileSync(join(ROOT, CONFIG.fixture), 'utf8'));
const KEEP = process.argv.includes('--keep');

const STUB = `<!doctype html>
<html>
<head><meta charset="utf-8"><title>Giantborn: Age of Titans</title></head>
<body>
<!-- tools/web/test_world_check.mjs's stub launcher (no engine). -->
<div id="status">Stub launcher</div>
<button id="play">Play</button>
<canvas id="game-canvas" tabindex="0" width="64" height="36"></canvas>
<script>
(function () {
  const args = (new URLSearchParams(location.search).get('args') || '').split(',');
  const arg = (name) => { const a = args.find((x) => x.startsWith(name + '=')); return a ? a.slice(name.length + 1) : ''; };
  const travelTo = arg('--walk-travel');
  const mode = travelTo.split('.').pop();
  const say = (tag, data) => console.log(tag + (data === undefined ? '' : ' ' + JSON.stringify(data)));
  const busy = (ms) => { const t = performance.now(); while (performance.now() - t < ms) { /* busy */ } };
  // the save where the engine reads it (Godot's /userfs in IndexedDB)
  const readSave = () => new Promise((ok) => {
    const req = indexedDB.open('/userfs');
    req.onupgradeneeded = () => req.transaction.abort();
    req.onerror = () => ok(null);
    req.onsuccess = () => {
      const db = req.result;
      if (!db.objectStoreNames.contains('FILE_DATA')) { db.close(); ok(null); return; }
      const get = db.transaction('FILE_DATA', 'readonly').objectStore('FILE_DATA')
        .get('/userfs/godot/app_userdata/Giantborn- Age of Titans/saves/valley_1.json');
      get.onsuccess = () => {
        db.close();
        const v = get.result;
        try { ok(v && v.contents ? JSON.parse(new TextDecoder().decode(new Uint8Array(v.contents.buffer))) : null); } catch (e) { ok(null); }
      };
      get.onerror = () => { db.close(); ok(null); };
    };
  });
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
  let continued = false;
  document.getElementById('play').addEventListener('click', async () => {
    const ctx = new AudioContext();
    await ctx.audioWorklet.addModule(URL.createObjectURL(new Blob([DRIVER], { type: 'application/javascript' })));
    const node = new AudioWorkletNode(ctx, 'godot-processor', { numberOfInputs: 0, numberOfOutputs: 1, outputChannelCount: [2] });
    node.port.onmessage = () => node.port.postMessage({ cmd: 'data' });
    node.connect(ctx.destination);
    say('stub: ' + mode);
    setTimeout(() => say('AUDIO_MUSIC', { set: 'music.title', state: 'title' }), 300);
  });
  window.addEventListener('keydown', async (e) => {
    if (e.key !== 'Enter' || continued) return;
    continued = true;
    const save = mode === 'newgame' ? null : await readSave();
    if (!save) {
      say('WORLD_WALK_LEVEL', { level: 'level.valley', respawn: 'valley.shrine.hollow', entered: 'new_game', stage: 1, at: [0, 0], travel: 'pending', travel_to: travelTo });
      setTimeout(() => {
        say('WORLD_WALK_END', { finished: false, ticks: 0, travel_error: 'fast travel to ' + travelTo + ' refused: That place is not on the map.' });
        say('AUTOPILOT_RESULT', { errors: 0, world_walk: { finished: false, travel_error: 'refused', check_failures: ['fast travel to ' + travelTo + ' refused: That place is not on the map.'] } });
      }, 400);
      return;
    }
    const respawn = save.checkpoint.respawn;
    const stage = save.character.growth_stage;
    say('WORLD_WALK_UNLOAD', { mode: 'valley', level: save.level, respawn });
    if (mode === 'warning') {
      console.error("WARNING: Giantborn: the world's starting ring was not ready after 8 s; continuing");
      console.error('   at: push_warning (core/variant/variant_utility.cpp:1034)');
    }
    if (mode === 'error') console.error('ERROR: stub: something broke');
    await new Promise((ok) => setTimeout(ok, 300));
    say('WORLD_WALK_LEVEL', { level: save.level, respawn, entered: 'continue', stage, at: [420, -46.5], travel: 'pending', travel_to: travelTo });
    setTimeout(() => say('AUDIO_MUSIC', { set: 'music.region_aldmere', state: 'zone' }), 200);
    if (mode === 'notravel') {
      setTimeout(() => {
        say('WORLD_WALK_END', { finished: false, ticks: 0 });
        say('AUTOPILOT_RESULT', { errors: 0, world_walk: { finished: false, check_failures: ['the fast travel to ' + travelTo + ' never arrived'] } });
      }, 600);
      return;
    }
    setTimeout(() => {
      say('WORLD_TRAVEL', { from: respawn, to: travelTo, level: save.level, refusals: 0, last_refusal: '', waited_ticks: 30 });
      say('WORLD_WALK_UNLOAD', { mode: 'valley', level: save.level, respawn: travelTo });
    }, 500);
    setTimeout(() => say('WORLD_WALK_LEVEL', { level: save.level, respawn: travelTo, entered: 'fast_travel', stage, at: [300, 340], travel: 'arrived', travel_to: travelTo }), 1500);
    setTimeout(() => say('AUDIO_MUSIC', { set: 'music.region_crownmarch', state: 'zone' }), 1700);
    setTimeout(() => say('WORLD_WALK_START', { route_points: 11, speed_mps: 0, stage }), 2000);
    if (mode !== 'noborder') setTimeout(() => say('AUDIO_MUSIC', { set: 'music.region_drowned_steps', state: 'zone' }), 3500);
    if (mode === 'stutter') for (const t of [2600, 3700, 4700]) setTimeout(() => busy(150), t);
    setTimeout(() => {
      if (mode === 'trailing') busy(150);   // the walk's last frame: the recorder disarms in the stall
      say('WORLD_WALK_END', { finished: true, ticks: 3840 });
      if (mode === 'trailing') busy(100);   // ... which goes on after the line, so no "read" ends the hole
      setTimeout(() => {
        say('PERF_RESULT', { renderer: 'stub', adapter: 'none', quality: 'low', frame_ms: { p50: 16.7, p99: 20, max: 30 },
          draw_calls: { p50: 40, max: 60 }, cpu_tick_ms: { p50: 1, max: 2 } });
        const borders = mode === 'noborder' ? [] : [{ s: 4, region: 'region.drowned_steps', previous: 'region.crownmarch' }];
        say('AUTOPILOT_RESULT', { errors: 0, world_walk: { mode: 'walk', speed_mps: 0, metres: 640, seconds: mode === 'short' ? 30 : 64,
          finished: true, stage, min_margin_m: 251.7, max_loaded: 15, loads: 10, unloads: 4, thrash: 0, work_ms_p50: 0.8,
          work_ms_p99: 5.2, work_ms_max: 9.6, work_ms_over_budget: 3, seam_crossings: 5, stuck_teleports: 0, route_points: 11,
          region_changes: borders, travel_to: travelTo, travel: { to: travelTo, arrival_m: 0 }, travel_error: '',
          streaming: { work_frames: 120, work_ms_over_budget: 3, budget_ms: 4.0, steps_by_kind: { props_add: { n: 9, max_ms: 9.6, total_ms: 40 }, rows: { n: 80, max_ms: 2.1, total_ms: 60 } } },
          check_failures: [] } });
      }, 200);
    }, 5500);
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

const dir = mkdtempSync(join(tmpdir(), 'world_check_test-'));
writeFileSync(join(dir, 'play.html'), STUB);
function run(mode, more = []) {
  const json = join(dir, `${mode}${more.includes('--strict') ? '_strict' : ''}.json`);
  const r = spawnSync(process.execPath, [CHECK, `--build=${dir}`, `--travel=world.cp.${mode}`, '--music-s=3', '--timeout-s=90',
    ...more, `--json=${json}`], { cwd: ROOT, encoding: 'utf8', timeout: 180000 });
  let rep = {};
  try { rep = JSON.parse(readFileSync(json, 'utf8')); } catch (e) { rep = {}; }
  return { code: r.status, out: r.stdout || '', err: r.stderr || '', rep };
}
const respawn = FIXTURE.checkpoint.respawn;

console.log('ok: Continue at the fixture\'s respawn, the travel, a walk across a border with no gap in the music');
{
  const r = run('ok');
  check(r.code === 0, `the check passes (exit ${r.code})`);
  check(r.out.trim().endsWith('world_check: OK'), 'it ends a bare OK');
  check(Array.isArray(r.rep.save_entries) && r.rep.save_entries[r.rep.save_entries.length - 1] === '/userfs/godot/app_userdata/Giantborn- Age of Titans/saves/valley_1.json'
    && r.rep.save_entries.includes('/userfs/godot/app_userdata/Giantborn- Age of Titans/saves'),
    `the fixture went where the engine reads the slot, with its folders (${JSON.stringify(r.rep.save_entries)})`);
  const c = r.rep.continue || {};
  check(c.level === FIXTURE.level && c.respawn === respawn && c.stage === FIXTURE.character.growth_stage,
    `Continue loaded the fixture: ${c.level} at ${c.respawn}, stage ${c.stage}`);
  check(typeof c.load_s === 'number' && c.load_s >= 0.2 && c.load_s < 2, `the Continue's load is timed from the title's unload (${c.load_s} s)`);
  check(c.presses_ignored === 0 && r.rep.enter_presses === 1, `one Enter (${r.rep.enter_presses}), none ignored`);
  const t = r.rep.travel || {};
  check(t.from === respawn && t.to === 'world.cp.ok' && t.arrived && t.arrived.respawn === 'world.cp.ok', `the travel from ${t.from} arrived at ${t.arrived && t.arrived.respawn}`);
  check(typeof t.load_s === 'number' && t.load_s > 0.5 && t.load_s < 2, `the travel's load is timed from the level's unload (${t.load_s} s)`);
  check(Array.isArray(r.rep.console_log) && r.rep.console_log.some((l) => String(l[2]).startsWith('WORLD_TRAVEL')), 'the --json report keeps the console\'s lines');
  check(r.rep.console_errors.length === 0 && r.rep.console_warnings.length === 0, 'no console error or warning');
  check(r.rep.url_args.includes('--save-dir=user://saves') && r.rep.url_args.includes('--mode=title') && r.rep.url_args.includes('--walk-travel=world.cp.ok'),
    `the game gets saving on, the title and the travel (${JSON.stringify(r.rep.url_args)})`);
  check(r.rep.streaming && r.rep.streaming.hitches === 3 && r.rep.streaming.heaviest_steps[0].step === 'props_add',
    `the streaming hitches and the heaviest step (${JSON.stringify(r.rep.streaming && r.rep.streaming.heaviest_steps)})`);
  const a = r.rep.audio || {};
  check(a.criterion && a.criterion.met === true && a.borders >= 1, `the music's criterion is met across ${a.borders} border(s)`);
  check(a.level === 'level.world' && a.registered_s > 100, `the cap is the world's (${a.registered_s} s registered)`);
  check(r.rep.walk && r.rep.walk.region_changes === 1 && r.rep.walk.seconds === 64, 'the walk\'s border and length are reported');
}

console.log('stutter: three slow frames of 150 ms during the walk');
{
  const r = run('stutter');
  const c = (r.rep.audio || {}).criterion || {};
  check(r.code === 0, `the default check passes on the main thread's holes (exit ${r.code})`);
  check(r.out.includes("world_check: OK (the plan's audio criterion NOT MET:"), 'it ends "OK (the plan\'s audio criterion NOT MET ...)", not a bare OK');
  check(c.met === false && c.holes >= 3, `the criterion is not met (${JSON.stringify(c)})`);
  const s = run('stutter', ['--strict']);
  check(s.code === 1 && /a [\d.]+ ms hole in the music/.test(s.out), `--strict fails on them (exit ${s.code})`);
}

console.log('short: a walk of 30 s of game time');
{
  const r = run('short');
  check(r.code === 1 && r.out.includes('the walk lasted 30 s of game time (at least 60)'), `the check fails (exit ${r.code})`);
}

console.log('notravel: no travel is asked for');
{
  const r = run('notravel');
  check(r.code === 1 && r.out.includes('the fast travel to world.cp.notravel was never asked for'), `the check fails (exit ${r.code})`);
}

console.log('newgame: the save is not read; a New Game starts in the Valley');
{
  const r = run('newgame');
  check(r.code === 1 && r.out.includes(`Continue loaded level.valley at valley.shrine.hollow, not the fixture's ${FIXTURE.level} at ${respawn}`),
    `the check fails (exit ${r.code})`);
}

console.log('noborder: the walk stays in one region\'s music');
{
  const r = run('noborder');
  check(r.code === 1 && r.out.includes('the walk crossed no region border') && r.out.includes('the recording crossed 0 region border(s)'),
    `the check fails (exit ${r.code})`);
}

console.log('warning: the engine warns while the world loads');
{
  const r = run('warning');
  check(r.code === 0 && r.out.trim().endsWith('world_check: OK'), `the default check passes (exit ${r.code})`);
  check(r.rep.console_warnings && r.rep.console_warnings.length === 2 && r.rep.console_errors.length === 0
    && r.out.includes("warning: WARNING: Giantborn: the world's starting ring was not ready after 8 s"), 'the warning and its "at:" line are listed apart');
  const s = run('warning', ['--strict']);
  check(s.code === 1 && s.out.includes('2 console warning line(s) (--strict)'), `--strict fails on it (exit ${s.code})`);
}

console.log('error: the engine prints an error');
{
  const r = run('error');
  check(r.code === 1 && r.out.includes('1 console error(s)') && r.out.includes('error: ERROR: stub: something broke'), `the check fails (exit ${r.code})`);
}

console.log('trailing: the walk ends in a 150 ms frame');
{
  const r = run('trailing');
  const m = (r.rep.audio || {}).music || {};
  check(r.code === 0, `the default check passes (exit ${r.code}): ${JSON.stringify(r.rep.problems)}`);
  check(m.holes_cut_at_disarm === 1 && (m.holes_elsewhere || []).length === 0, `the hole the walk's end cut short is the main thread's (${m.holes_cut_at_disarm} cut, ${(m.holes_elsewhere || []).length} elsewhere)`);
}

if (KEEP) console.log(`the stub and the reports: ${dir}`);
else rmSync(dir, { recursive: true, force: true });
console.log(`TEST_WORLD_CHECK: ${checks} checks, ${failures.length} failures`);
for (const f of failures) console.log(`FAIL  ${f}`);
process.exit(failures.length === 0 ? 0 : 1);
