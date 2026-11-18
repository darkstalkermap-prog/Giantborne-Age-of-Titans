#!/usr/bin/env node
// The web creator check's own test (P45; plan M10 §3.5 item 2): tools/web/creator_check.mjs against a stub
// launcher in headless Chromium - no engine, no build. The stub's play.html prints what the game's
// --ui-probe prints (UI_PROBE state and stall lines) and answers the keys as the game's screens do: Enter on
// the title (New Game with no save, Continue with the save the check put into the page's IndexedDB),
// PageDown, R, Ctrl+Z and Ctrl+Enter in the creator (Begin asks for the pointer lock and writes the first
// save where the engine keeps it), E at the shrine, Up to the shrine's tab buttons and Right along them, Enter on
// "Change your look...". Its mode is the check's --args=--stub=M:
//   * ok: both parts pass with a bare OK; the report holds the four marks, the categories, the Undo, the
//     pointer lock inside the gesture, the texture tier "hi" and the first save with its look;
//   * stall: the creator's first frame takes ten median frames - the default check passes and reports a
//     MISS, --strict fails;
//   * slowskin: the skin's CPU a frame is 0.52 ms in the Valley - reported as a MISS, --strict fails;
//   * noundo: Ctrl+Z changes nothing - the check fails;
//   * nolock: Begin asks for no pointer lock - the check fails;
//   * webtier: the giant draws the 512 px maps - the check fails (tex_hi/ is wanted in the Web pack);
//   * nolook: the first save holds no look - the check fails;
//   * turned: the giant wakes facing away from the shrine (no prompt until it steps back) - the shrine
//     part passes after a step;
//   * warning: the engine warns ("WARNING: ..." and its "at:" line through console.error) - the check
//     passes and lists it apart;
//   * error: the engine prints an error - the check fails;
//   * (M10 gate, LD-1) ok with GIANT_WEB_GUARD_MB=1: the memory guard (memory_guard.mjs) stops the check with a
//     FAILED line naming the renderer's memory; with 0 the guard is off; by default the report holds its limit
//     and the renderer's peak.
// Prints TEST_CREATOR_CHECK with the count of checks and failures; exits 1 on a failure.
//
// Usage (from the project folder): node tools/web/test_creator_check.mjs [--keep]
//   --keep   keep the stub folder and the reports (printed)
// Needs what creator_check.mjs needs: Playwright and its Chromium. About two minutes.

import { spawnSync } from 'node:child_process';
import { mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { median, stallOk } from './creator_check.mjs';

const ROOT = resolve(dirname(fileURLToPath(import.meta.url)), '..', '..');
const CHECK = join(ROOT, 'tools', 'web', 'creator_check.mjs');
const KEEP = process.argv.includes('--keep');

const STUB = `<!doctype html>
<html>
<head><meta charset="utf-8"><title>Giantborn: Age of Titans</title></head>
<body>
<!-- tools/web/test_creator_check.mjs's stub launcher (no engine). start(['--', '--mode=world', '--creator']); -->
<div id="status">Stub launcher</div>
<button id="play">Play</button>
<canvas id="game-canvas" tabindex="0" width="64" height="36"></canvas>
<script>
(function () {
  const args = (new URLSearchParams(location.search).get('args') || '').split(',');
  const mode = (args.find((a) => a.startsWith('--stub=')) || '--stub=ok').split('=')[1];
  const SAVE = '/userfs/godot/app_userdata/Giantborn- Age of Titans/saves/valley_1.json';
  const TABS = ['Rest', 'Grow', 'Talents', 'Appearance (new)'];
  const tiers = mode === 'webtier' ? ['web'] : ['hi'];
  let frame = 0;
  let s = { mode: 'title', level: '', loading: false, top: '', warming: false, tab: '', context: '', category: '', changed: false, history: 0,
    focus: '', focus_tab: false, prompt: '', captured: false, tiers: [] };
  const say = (line) => console.log('UI_PROBE ' + JSON.stringify(line));
  const set = (change) => { s = Object.assign({}, s, change); frame += 1; say(Object.assign({ t: 'state', frame }, s)); };
  const bench = (mark, ms, giants) => say({ t: 'bench', mark, skin_ms: ms, batches: 5, runs: 200, giants, modifier_runs: 1000, paused: giants > 1 });
  const stall = (mark, first, med, more) => say(Object.assign({ t: 'stall', mark, first_ms: first, median_ms: med,
    ratio: Math.round(100 * first / med) / 100, frames: 40 }, more || {}));
  const db = (write) => new Promise((ok) => {
    const req = write ? indexedDB.open('/userfs', 21) : indexedDB.open('/userfs');
    req.onupgradeneeded = () => {
      if (!write) { req.transaction.abort(); return; }
      if (!req.result.objectStoreNames.contains('FILE_DATA')) req.result.createObjectStore('FILE_DATA');
    };
    req.onerror = () => ok(null);
    req.onsuccess = () => ok(req.result);
  });
  const readSave = async () => {
    const d = await db(false);
    if (!d) return null;
    if (!d.objectStoreNames.contains('FILE_DATA')) { d.close(); return null; }
    return new Promise((ok) => {
      const get = d.transaction('FILE_DATA', 'readonly').objectStore('FILE_DATA').get(SAVE);
      get.onsuccess = () => { d.close(); ok(get.result && get.result.contents ? get.result : null); };
      get.onerror = () => { d.close(); ok(null); };
    });
  };
  const writeSave = async (doc) => {
    const d = await db(true);
    if (!d) return;
    const tx = d.transaction('FILE_DATA', 'readwrite');
    tx.objectStore('FILE_DATA').put({ timestamp: new Date(), mode: 0o100666,
      contents: new Int8Array(new TextEncoder().encode(JSON.stringify(doc)).buffer) }, SAVE);
    tx.oncomplete = () => d.close();
  };
  // a few animation frames, as an engine's main loop asks for them
  const loop = () => requestAnimationFrame(loop);
  let saved = false;
  document.getElementById('play').addEventListener('click', async () => {
    loop();
    saved = (await readSave()) !== null;
    set({ top: 'title', warming: true });
    setTimeout(() => {
      if (mode === 'error') console.error('ERROR: stub: something broke');
      if (mode === 'warning') {
        console.error('WARNING: stub: something to mention');
        console.error('   at: push_warning (core/variant/variant_utility.cpp:1034)');
      }
      set({ warming: false, focus: saved ? 'Continue' : 'New Game' });
      stall('title', 900, 20, { warmed: true });
    }, 300);
  });
  window.addEventListener('keydown', (e) => {
    const k = e.key;
    if (s.top === 'title' && k === 'Enter') {
      if (s.focus === 'New Game') {
        set({ top: 'creator', context: 'new_game', category: 'Presets', focus: 'Wanderer', tiers });
        if (mode === 'stall') stall('creator', 500, 50, { again: false });
        else stall('creator', 90, 50, { again: false });
      } else {
        set({ mode: 'valley', level: 'level.world', top: '', loading: true, focus: '' });
        setTimeout(() => {
          set({ loading: false, tiers, prompt: mode === 'turned' ? '' : 'Rest at the Aldmere shrine' });
          stall('level', 60, 40, { load_worst_ms: 800, level: 'level.world' });
          bench('level', 0.21, 1);
        }, 300);
      }
    } else if (s.top === 'creator' && s.context === 'new_game') {
      if (k === 'PageDown') set({ category: 'Skin' });
      else if (k === 'r') set({ changed: true, history: s.history + 1 });
      else if (k === 'z' && e.ctrlKey) { if (mode !== 'noundo') set({ changed: s.history > 1, history: Math.max(0, s.history - 1) }); }
      else if (k === 'Enter' && e.ctrlKey) {
        if (mode !== 'nolock') document.getElementById('game-canvas').requestPointerLock();
        set({ mode: 'valley', level: 'level.valley', top: '', loading: true, context: '', category: '', changed: false, history: 0, focus: '', captured: true });
        setTimeout(() => {
          set({ loading: false });
          stall('level', 70, 40, { load_worst_ms: 600, level: 'level.valley' });
          bench('level', mode === 'slowskin' ? 0.52 : 0.24, 1);
          writeSave({ level: 'level.valley', character: mode === 'nolook' ? {} : { appearance: { eyes: 'eyes.blue' } } });
        }, 300);
      }
    } else if (s.level === 'level.world' && s.top === '') {
      if (k === 's') set({ prompt: 'Rest at the Aldmere shrine' });
      else if (k === 'e' && s.prompt !== '') set({ top: 'shrine', tab: 'Rest', focus: 'Rest', focus_tab: false, prompt: '' });
    } else if (s.top === 'shrine') {
      // the Rest tab's own "Rest" button has the focus first; Up reaches the row of tab buttons
      const at = s.focus_tab ? TABS.indexOf(s.focus) : -1;
      if (k === 'ArrowUp' && !s.focus_tab) set({ focus: 'Rest', focus_tab: true });
      else if (k === 'ArrowRight' && at >= 0) set({ focus: TABS[(at + 1) % TABS.length] });
      else if (k === 'Enter' && s.focus_tab && s.focus === 'Appearance (new)') set({ tab: 'Appearance' });
      else if (k === 'ArrowDown' && s.tab === 'Appearance') set({ focus: 'Change your look...', focus_tab: false });
      else if (k === 'Enter' && s.focus === 'Change your look...') {
        set({ top: 'creator', context: 'shrine', category: 'Presets', focus: 'Wanderer', focus_tab: false });
        stall('shrine_creator', 80, 45, { again: false });
        bench('shrine_creator', 0.19, 2);
      }
    }
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

const dir = mkdtempSync(join(tmpdir(), 'creator_check_test-'));
writeFileSync(join(dir, 'play.html'), STUB);
function run(mode, more = [], env = {}) {
  const json = join(dir, `${mode}${more.includes('--strict') ? '_strict' : ''}.json`);
  const r = spawnSync(process.execPath, [CHECK, `--build=${dir}`, `--args=--stub=${mode}`, '--timeout-s=20', '--size=320x180',
    ...more, `--json=${json}`], { cwd: ROOT, encoding: 'utf8', timeout: 240000, env: { ...process.env, ...env } });
  let rep = {};
  try { rep = JSON.parse(readFileSync(json, 'utf8')); } catch (e) { rep = {}; }
  const parts = rep.parts || {};
  return { code: r.status, out: r.stdout || '', err: r.stderr || '', rep, ng: parts.new_game || {}, sh: parts.shrine || {} };
}

console.log('the stall rule');
check(stallOk(60, 40) && stallOk(120, 40) && !stallOk(121, 40), 'a first frame within three median frames is no stall; over them it is one');
check(stallOk(24, 2) && !stallOk(26, 2), 'and under 25 ms never, whatever the ratio');
check(!stallOk(500, 0), 'no median: a long frame is a stall');
check(median([5, 1, 3]) === 3 && median([4, 1, 3, 2]) === 2.5 && median([]) === 0, 'the median');

console.log('ok: New Game through the creator into the Valley; a world save through the shrine into the creator');
{
  const r = run('ok');
  check(r.code === 0, `the check passes (exit ${r.code}): ${JSON.stringify(r.rep.problems)}`);
  check(r.out.trim().endsWith('creator_check: OK (2 budget miss(es) reported: stalls over 3x the median frame or the skin\'s CPU; --strict fails on them)'),
    'it ends OK with the two parts\' title warm-up frames listed as misses, not failures');
  check(r.rep.launcher_world_args === true, 'the launcher\'s open-world start passes --mode=world --creator');
  check(JSON.stringify(r.rep.game_args) === JSON.stringify(['--ui-probe', '--ui-probe-bench', '--stub=ok']), `the game gets --ui-probe and --ui-probe-bench (${JSON.stringify(r.rep.game_args)})`);
  check(r.ng.skin_bench.length === 1 && r.ng.skin_bench[0].skin_ms === 0.24 && r.ng.skin_bench[0].giants === 1, 'the skin\'s CPU in the Valley, the player alone');
  check(r.sh.skin_bench.length === 2 && r.sh.skin_bench[1].mark === 'shrine_creator' && r.sh.skin_bench[1].giants === 2, 'and with the creator\'s preview open at the shrine');
  const st = r.ng.stalls || {};
  check(st.title && st.title.first_ms === 900 && st.title.ok === false && st.title.warmed === true, 'the title\'s worst frame until New Game enables is reported');
  check(st.creator && st.creator.ok === true && st.creator.ratio === 1.8, `the creator's first frame (${JSON.stringify(st.creator)})`);
  check(st.level && st.level.ok === true && st.level.load_worst_ms === 600, 'the Valley\'s first frame, the load\'s worst frame apart');
  check(JSON.stringify(r.ng.categories) === JSON.stringify(['Presets', 'Skin']) && r.ng.undo === true, 'PageDown changed the category; R then Ctrl+Z undid the change');
  check(r.ng.pointer_lock && r.ng.pointer_lock.requests === 1 && r.ng.pointer_lock.in_gesture === true, `Begin asked for the pointer lock inside the gesture (${JSON.stringify(r.ng.pointer_lock)})`);
  check(JSON.stringify(r.ng.level_tiers) === JSON.stringify(['hi']), 'the giant draws the hi tier');
  check(r.ng.first_save && r.ng.first_save.level === 'level.valley' && r.ng.first_save.has_appearance === true, 'the first save holds the Valley and the look');
  check(r.ng.page_frames && r.ng.page_frames.count > 5, `the page's frames are counted (${r.ng.page_frames && r.ng.page_frames.count})`);
  const ss = r.sh.stalls || {};
  check(ss.level && ss.shrine_creator && ss.shrine_creator.ok === true, 'the shrine part reports the world\'s first frame and "Change your look..."');
  check(r.sh.shrine_tries === 1 && r.sh.appearance_tab_button === 'Appearance (new)', `one E at the shrine; the tab's button read "${r.sh.appearance_tab_button}"`);
  check(r.sh.last_state && r.sh.last_state.top === 'creator' && r.sh.last_state.context === 'shrine', 'the creator opened over the shrine');
  check(r.ng.console_errors.length === 0 && r.sh.console_errors.length === 0, 'no console error');
  const mg = r.rep.memory_guard || {};
  check(mg.limit_mb === 3072 && mg.renderer_peak_mb > 0, `the memory guard watched the page's renderer (${JSON.stringify(r.rep.memory_guard)})`);
}

console.log('guard: the page\'s renderer is over the memory guard (M10 gate, LD-1)');
{
  const t0 = Date.now();
  const r = run('ok', ['--parts=new_game'], { GIANT_WEB_GUARD_MB: '1' });
  check(r.code === 1 && /creator_check: FAILED - the page's renderer holds \d+ MB of memory \(over the guard's 1 MB\)/.test(r.out),
    `the check stops with a FAILED line naming the memory (exit ${r.code})`);
  check(Date.now() - t0 < 60000 && !r.out.includes('CREATOR_CHECK '), 'at the guard\'s first reading, without running on');
  const off = run('ok', ['--parts=new_game'], { GIANT_WEB_GUARD_MB: '0' });
  check(off.code === 0 && off.rep.memory_guard && off.rep.memory_guard.limit_mb === 0 && off.rep.memory_guard.renderer_peak_mb === 0,
    `GIANT_WEB_GUARD_MB=0 switches the guard off (exit ${off.code})`);
}

console.log('stall: the creator\'s first frame takes ten median frames');
{
  const r = run('stall', ['--parts=new_game']);
  check(r.code === 0 && r.out.includes('MISS: new_game: the creator\'s first frame: 500 ms against a median frame of 50 ms (10x, over 3x)'),
    `the default check passes and reports the miss (exit ${r.code})`);
  const s = run('stall', ['--parts=new_game', '--strict']);
  check(s.code === 1 && s.out.includes('a budget miss (--strict): the creator\'s first frame'), `--strict fails on it (exit ${s.code})`);
  const w = run('stall', ['--parts=new_game', '--stall-ratio=12']);
  check(w.code === 0 && !w.out.includes('the creator\'s first frame: 500 ms'), '--stall-ratio=12 lets it be');
}

console.log('slowskin: the skin costs 0.52 ms a frame');
{
  const r = run('slowskin', ['--parts=new_game']);
  check(r.code === 0 && r.out.includes('MISS: new_game: the skin\'s CPU a frame after "level" (1 giant(s)): 0.52 ms (at most 0.35 ms on the Web)'),
    `the default check passes and reports the miss (exit ${r.code})`);
}

console.log('noundo: Ctrl+Z changes nothing');
{
  const r = run('noundo', ['--parts=new_game']);
  check(r.code === 1 && r.out.includes('new_game: Ctrl+Z did not undo the change'), `the check fails (exit ${r.code})`);
}

console.log('nolock: Begin asks for no pointer lock');
{
  const r = run('nolock', ['--parts=new_game']);
  check(r.code === 1 && r.out.includes('new_game: Begin asked for no pointer lock'), `the check fails (exit ${r.code})`);
}

console.log('webtier: the giant draws the 512 px maps');
{
  const r = run('webtier', ['--parts=new_game']);
  check(r.code === 1 && r.out.includes('the giant draws the texture tier ["web"] (hi wanted: tex_hi/ is in the Web pack)'), `the check fails (exit ${r.code})`);
}

console.log('nolook: the first save holds no look');
{
  const r = run('nolook', ['--parts=new_game']);
  check(r.code === 1 && r.out.includes('new_game: the first save holds no look (character.appearance)'), `the check fails (exit ${r.code})`);
}

console.log('turned: the giant wakes facing away from the shrine');
{
  const r = run('turned', ['--parts=shrine']);
  check(r.code === 0 && r.sh.shrine_tries === 2, `the shrine part passes after a step back (exit ${r.code}, ${r.sh.shrine_tries} tries)`);
}

console.log('warning: the engine warns');
{
  const r = run('warning', ['--parts=new_game']);
  check(r.code === 0 && r.ng.engine_warnings.length === 2 && r.ng.console_errors.length === 0 && r.out.includes('warning: WARNING: stub: something to mention'),
    `the check passes and lists the warning apart (exit ${r.code})`);
}

console.log('error: the engine prints an error');
{
  const r = run('error', ['--parts=new_game']);
  check(r.code === 1 && r.out.includes('new_game: 1 console error(s)') && r.out.includes('error: ERROR: stub: something broke'), `the check fails (exit ${r.code})`);
}

console.log('usage');
{
  const r = spawnSync(process.execPath, [CHECK, '--parts=moon'], { cwd: ROOT, encoding: 'utf8' });
  check(r.status === 2, `an unknown part is a usage error (exit ${r.status})`);
}

if (KEEP) console.log(`the stub and the reports: ${dir}`);
else rmSync(dir, { recursive: true, force: true });
console.log(`TEST_CREATOR_CHECK: ${checks} checks, ${failures.length} failures`);
for (const f of failures) console.log(`FAIL  ${f}`);
process.exit(failures.length === 0 ? 0 : 1);
