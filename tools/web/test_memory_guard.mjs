#!/usr/bin/env node
// The memory guard's own test (M10 gate, LD-1): tools/web/memory_guard.mjs.
//   * the rules, without a browser: a /proc status text read; the processes below a root; which of them are
//     Chromium's page processes; the largest of those; the limit from GIANT_WEB_GUARD_MB; a guard over a made-up
//     process table trips once, over the limit only, and never for a renderer that is not below its root;
//   * the five checks start it: each of audio_check, creator_check, stream_check, world_check and
//     world_start_check imports the guard, starts it right after its browser and stops it before the browser
//     closes;
//   * live, in headless Chromium (no engine, no build): a page that keeps 16 MB more every 50 ms under a guard of
//     its starting size plus 250 MB - the run ends with exit 1 and "<tool>: FAILED - the page's renderer holds N MB
//     of memory", and the page's process is gone; a page that keeps nothing under the default guard runs on, and
//     the guard reports the renderer it watched (a peak over 0: the guard finds the page's process).
// Prints TEST_MEMORY_GUARD with the count of checks and failures; exits 1 on a failure.
//
// Usage (from the project folder): node tools/web/test_memory_guard.mjs
// Needs what the checks need: Playwright and its Chromium. About ten seconds.

import { spawnSync } from 'node:child_process';
import { existsSync, readFileSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import {
  GUARD_ENV, GUARD_MB, descendantsOf, failedLine, guardLimitMb, isRenderer, largestRenderer, overLimit, parseStatus,
  readProcessTable, startMemoryGuard,
} from './memory_guard.mjs';
import { loadPlaywright } from './stream_check.mjs';

const SELF = fileURLToPath(import.meta.url);
const ROOT = resolve(dirname(SELF), '..', '..');
const TOOL = 'memory_guard_child';
const sleep = (ms) => new Promise((ok) => setTimeout(ok, ms));

// A page that keeps `stepMb` more every 50 ms, up to `capMb` (the test never takes more than that).
const page = (stepMb, capMb) => `data:text/html,<title>guard</title><script>
  const kept = [];
  setInterval(() => { if (${stepMb} > 0 && kept.length * ${stepMb} < ${capMb}) kept.push(new Uint8Array(${stepMb} << 20).fill(1)); }, 50);
</script>`;

// The child: a browser, a page, the guard as a check starts it; exits 0 when the guard never stopped it.
async function child(mode) {
  if (!process.env.PLAYWRIGHT_BROWSERS_PATH && existsSync('/opt/pw-browsers')) process.env.PLAYWRIGHT_BROWSERS_PATH = '/opt/pw-browsers';
  const { chromium } = loadPlaywright();
  const browser = await chromium.launch({ headless: true });
  const tab = await browser.newPage();
  await tab.goto(page(0, 0));
  await sleep(500);
  const first = largestRenderer(readProcessTable(), process.pid);
  console.log(`CHILD_RENDERER ${JSON.stringify(first)}`);
  const leak = mode === 'leak';
  const guard = startMemoryGuard(TOOL, leak ? { limitMb: Math.round((first ? first.rssMb : 100) + 250), intervalMs: 200 } : { intervalMs: 200 });
  if (leak) await tab.goto(page(16, 900));
  await sleep(leak ? 30000 : 1500);
  guard.stop();
  console.log(`CHILD_GUARD ${JSON.stringify({ limit_mb: guard.limitMb, peak_mb: guard.peakMb(), tripped: guard.tripped() })}`);
  await browser.close();
  process.exit(0);
}

if (process.argv[2] === '--child') {
  child(process.argv[3]).catch((e) => {
    console.error(`${TOOL}: ${e && e.stack ? e.stack : e}`);
    process.exit(3);
  });
} else {
  let checks = 0;
  const failures = [];
  const check = (ok, what) => {
    checks++;
    if (!ok) failures.push(what);
    console.log(`  ${ok ? 'ok  ' : 'FAIL'} ${what}`);
  };

  console.log('the rules');
  const st = parseStatus('Name:\tchrome\nPid:\t77\nPPid:\t42\nVmPeak:\t 9000000 kB\nVmRSS:\t 3145728 kB\nRssAnon:\t 3000000 kB\n');
  check(st.ppid === 42 && st.rssMb === 3072, `a status text gives the parent and the resident memory (${JSON.stringify(st)})`);
  check(parseStatus('Name:\tkthreadd\nPPid:\t0\n').rssMb === 0, 'a process without VmRSS counts as 0 MB');
  const R = 'chrome --type=renderer --lang=en-US';
  const table = [
    { pid: 10, ppid: 1, rssMb: 50, cmd: 'node creator_check.mjs' },
    { pid: 11, ppid: 10, rssMb: 200, cmd: 'chrome --headless' },
    { pid: 12, ppid: 11, rssMb: 240, cmd: 'chrome --type=gpu-process' },
    { pid: 13, ppid: 11, rssMb: 900, cmd: () => R },
    { pid: 14, ppid: 11, rssMb: 120, cmd: R },
    { pid: 15, ppid: 13, rssMb: 5, cmd: 'chrome --type=utility' },
    { pid: 20, ppid: 1, rssMb: 80, cmd: 'node other_check.mjs' },
    { pid: 21, ppid: 20, rssMb: 5000, cmd: R },
  ];
  check(JSON.stringify(descendantsOf(table, 10).map((r) => r.pid)) === '[11,12,13,14,15]', 'the processes below a root, the nearest first, and no one else\'s');
  check(isRenderer(R) && !isRenderer('chrome --type=gpu-process') && !isRenderer('chrome --type=renderer-like') && !isRenderer(''), 'Chromium\'s page processes are the --type=renderer ones');
  const top = largestRenderer(table, 10);
  check(top && top.pid === 13 && top.rssMb === 900, `the largest renderer below the root (${JSON.stringify(top)}): another run's 5,000 MB page is not this check's`);
  check(largestRenderer(table, 99) === null, 'no renderer below a root without one');
  check(overLimit(3073, 3072) && !overLimit(3072, 3072) && !overLimit(99999, 0), 'over the limit stops the run; a limit of 0 never does');
  check(guardLimitMb({}) === GUARD_MB && GUARD_MB === 3072 && guardLimitMb({ [GUARD_ENV]: '2048' }) === 2048 && guardLimitMb({ [GUARD_ENV]: '0' }) === 0
    && guardLimitMb({ [GUARD_ENV]: 'lots' }) === GUARD_MB && guardLimitMb({ [GUARD_ENV]: '-5' }) === GUARD_MB, 'the limit: 3072 MB, GIANT_WEB_GUARD_MB moves it, 0 is off, nonsense is the default');
  const line = failedLine('creator_check', 3412.4, 3072);
  check(line.startsWith('creator_check: FAILED - the page\'s renderer holds 3412 MB of memory (over the guard\'s 3072 MB)') && line.includes(GUARD_ENV), 'the FAILED line names the tool, the memory and the limit');
  {
    let rss = 900;
    const calls = [];
    const guard = startMemoryGuard('t', { limitMb: 3072, rootPid: 10, intervalMs: 3600000, onExceed: (mb, limit) => calls.push([mb, limit]),
      readTable: () => table.map((r) => (r.pid === 13 ? { ...r, rssMb: rss } : r)) });
    const a = guard.check();
    rss = 3072;
    const b = guard.check();
    rss = 3500;
    const c = guard.check();
    rss = 4000;
    const d = guard.check();
    check(a === false && b === false && c === true && d === true && JSON.stringify(calls) === '[[3500,3072]]' && guard.tripped() && guard.peakMb() === 3500,
      `a guard trips once, when its own renderer passes the limit (${JSON.stringify(calls)}, peak ${guard.peakMb()} MB)`);
    const off = startMemoryGuard('t', { limitMb: 0, rootPid: 10, onExceed: () => calls.push('off'), readTable: () => table.map((r) => ({ ...r, rssMb: 99999 })) });
    check(off.check() === false && calls.length === 1 && !off.tripped(), 'a guard that is off never trips');
    guard.stop();
    off.stop();
  }

  console.log('the five checks start the guard');
  for (const name of ['audio_check', 'creator_check', 'stream_check', 'world_check', 'world_start_check']) {
    const src = readFileSync(join(ROOT, 'tools', 'web', `${name}.mjs`), 'utf8');
    const launch = src.indexOf('await chromium.launch(');
    const start = src.indexOf(`startMemoryGuard('${name}')`);
    const stop = src.indexOf('memoryGuard.stop();');
    const close = src.indexOf('await browser.close();', stop);
    check(src.includes("import { startMemoryGuard } from './memory_guard.mjs';") && launch > 0 && start > launch && start - launch < 400
      && stop > start && close > stop && close - stop < 60 && src.includes('renderer_peak_mb: memoryGuard.peakMb()'),
      `${name}.mjs starts it beside its browser, stops it before the browser closes and reports the renderer's peak`);
  }

  console.log('live: a page that keeps growing, a page that does not');
  if (readProcessTable().length === 0) {
    console.log('  skipped - no /proc on this machine (the guard reads nothing here)');
  } else {
    const t0 = Date.now();
    const leak = spawnSync(process.execPath, [SELF, '--child', 'leak'], { cwd: ROOT, encoding: 'utf8', timeout: 120000 });
    const out = leak.stdout || '';
    const first = JSON.parse((/CHILD_RENDERER (.*)/.exec(out) || [null, 'null'])[1]);
    const m = /memory_guard_child: FAILED - the page's renderer holds (\d+) MB of memory \(over the guard's (\d+) MB\)/.exec(out);
    check(leak.status === 1 && m !== null && Number(m[1]) > Number(m[2]), `the growing page is stopped with a FAILED line naming the memory (exit ${leak.status}: ${m ? m[0] : out.slice(-300) + (leak.stderr || '').slice(-300)})`);
    check(Date.now() - t0 < 25000 && !out.includes('CHILD_GUARD'), `well before the page's own end (${Math.round((Date.now() - t0) / 100) / 10} s)`);
    check(m !== null && Number(m[1]) < 1500, `long before the machine is in danger (${m ? m[1] : '?'} MB)`);
    // gone: no /proc entry, or a zombie waiting for its reaper (a killed process holds no memory)
    const gone = (pid) => {
      try {
        return /^State:\s*Z/m.test(readFileSync(`/proc/${pid}/status`, 'utf8'));
      } catch (e) {
        return true;
      }
    };
    for (let i = 0; i < 50 && first !== null && !gone(first.pid); i++) await sleep(100);
    check(first !== null && first.pid > 0 && gone(first.pid), `and the page's process is gone (pid ${first ? first.pid : '?'})`);
    const calm = spawnSync(process.execPath, [SELF, '--child', 'calm'], { cwd: ROOT, encoding: 'utf8', timeout: 120000 });
    const g = JSON.parse((/CHILD_GUARD (.*)/.exec(calm.stdout || '') || [null, '{}'])[1]);
    check(calm.status === 0 && g.tripped === false && g.limit_mb === GUARD_MB && g.peak_mb > 0 && g.peak_mb < GUARD_MB,
      `a page that keeps nothing runs on under the default guard, which watched it (exit ${calm.status}, ${JSON.stringify(g)})`);
  }

  console.log(`TEST_MEMORY_GUARD: ${checks} checks, ${failures.length} failures`);
  for (const f of failures) console.log(`FAIL  ${f}`);
  process.exit(failures.length === 0 ? 0 : 1);
}
