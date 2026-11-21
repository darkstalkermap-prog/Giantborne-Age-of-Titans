#!/usr/bin/env node
// The web people check (P64; plan M11 §3.17 design 3 and 4, §2.12): the realistic people and creatures as the Web
// release draws them, in headless Chromium. The game runs with --ui-probe (its marks time the first frames: UI_PROBE
// stall lines) and --people-probe (scripts/debug/people_web_probe.gd: PEOPLE_WEB view lines - the view's draw calls
// and primitives, the texture and buffer memory, how many people are skinned, crowd and far, how many brutes and
// wolves hold a skinned slot, and the people's CPU a frame - then a done line, and it quits). Each part in a fresh
// browser profile:
//   * formation: the formation test level (--level=res://scenes/test/formation_test.tscn): the level, then forty
//     soldiers in a block 25 m before the giant (the mark "first_formation"), then a wolf pack - five wolves and a
//     dire wolf 12 m before him (the mark "first_wolf");
//   * town: the village test level (--level=res://scenes/test/village_test.tscn): its townsfolk as they stand.
// Judged (plan §2.12): every view at most 250 draw calls (the Web runs `low`) - a failure; the people's CPU a frame at
// most 2.5 ms, the people's and creatures' texture memory within 10 MB of the level's, each first frame within 3
// median frames (under 25 ms never a stall), the page's renderer process at most 1.4 GB - reported as a MISS (a
// GPU-less machine draws with SwiftShader; --strict fails on them); 0 console errors (the engine's warnings listed
// apart) and no failed request - a failure.
// Prints one PEOPLE_CHECK {json} line and exits 0 when everything holds (1 otherwise, 2 for a usage error).
//
// Usage (from the project folder, after tools/build_web.sh):
//   node tools/web/people_check.mjs [--build=builds/web] [--size=960x540] [--timeout-s=900] [--parts=formation,town]
//        [--strict] [--args=a,b] [--json=FILE] [--shots=DIR] [--headed]
// Needs Playwright (as creator_check.mjs) and its Chromium. Its own test: tools/web/test_people_check.mjs.

import { startMemoryGuard } from './memory_guard.mjs';
import { existsSync, mkdirSync, writeFileSync } from 'node:fs';
import { join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { loadPlaywright, serve } from './stream_check.mjs';
import { splitWarnings } from './world_check.mjs';

const TOOL = 'people_check';
const UI_TAG = 'UI_PROBE';
const TAG = 'PEOPLE_WEB';
export const PARTS = {
  formation: ['--level=res://scenes/test/formation_test.tscn', '--people-probe=level+formation+wolves'],
  town: ['--level=res://scenes/test/village_test.tscn', '--people-probe=level'],
};
// Plan M11 §2.12.
export const DRAW_CALLS_MAX = 250;
export const PEOPLE_CPU_MS_WEB = 2.5;
export const PEOPLE_TEXTURE_MB = 10;
export const RENDERER_MB = 1400;
export const STALL_RATIO = 3;
export const STALL_FLOOR_MS = 25;

function usage(message) {
  console.error(`${TOOL}: ${message}`);
  process.exit(2);
}

export function parseArgs(argv) {
  const opts = { build: 'builds/web', size: '960x540', timeoutS: 900, parts: Object.keys(PARTS), strict: false, args: '',
    json: '', shots: '', headed: false };
  for (const arg of argv) {
    const [key, ...rest] = arg.split('=');
    const value = rest.join('=');
    switch (key) {
      case '--build': opts.build = value; break;
      case '--size': opts.size = value; break;
      case '--timeout-s': opts.timeoutS = Number(value); break;
      case '--parts': opts.parts = value.split(',').map((x) => x.trim()).filter((x) => x.length > 0); break;
      case '--strict': opts.strict = true; break;
      case '--args': opts.args = value; break;
      case '--json': opts.json = value; break;
      case '--shots': opts.shots = value; break;
      case '--headed': opts.headed = true; break;
      default: usage(`unknown option ${arg}`);
    }
  }
  if (!/^\d+x\d+$/.test(opts.size) || !(opts.timeoutS > 0)) usage('--size wants WxH, --timeout-s a positive number');
  if (opts.parts.length === 0 || opts.parts.some((p) => !(p in PARTS))) usage(`--parts wants a list of ${Object.keys(PARTS).join(', ')}`);
  opts.extra = opts.args.split(',').map((x) => x.trim()).filter((x) => x.length > 0);
  return opts;
}

// The game's arguments for `part` (the probe's and the part's, then --args).
export function gameArgs(part, extra = []) {
  return ['--ui-probe', ...PARTS[part], ...extra];
}

export function stallOk(firstMs, medianMs, ratio = STALL_RATIO) {
  return firstMs <= STALL_FLOOR_MS || (medianMs > 0 && firstMs <= ratio * medianMs);
}

// The budgets of one PEOPLE_WEB view line against the level's own (`base`, the part's first view; null for that
// one): {problems: [...], misses: [...]}.
export function judgeView(view, base) {
  const problems = [];
  const misses = [];
  if (!(view.draw_calls <= DRAW_CALLS_MAX)) problems.push(`${view.view}: ${view.draw_calls} draw calls (at most ${DRAW_CALLS_MAX} at low)`);
  if (view.people_cpu_ms > PEOPLE_CPU_MS_WEB) misses.push(`${view.view}: the people's CPU ${view.people_cpu_ms} ms a frame (at most ${PEOPLE_CPU_MS_WEB} ms on the Web)`);
  if (base && view.texture_mem_mb - base.texture_mem_mb > PEOPLE_TEXTURE_MB) {
    misses.push(`${view.view}: the people's textures ${Math.round((view.texture_mem_mb - base.texture_mem_mb) * 10) / 10} MB over the level's (at most ${PEOPLE_TEXTURE_MB} MB)`);
  }
  return { problems, misses };
}

const sleep = (ms) => new Promise((ok) => setTimeout(ok, ms));
const round1 = (x) => (typeof x === 'number' ? Math.round(x * 10) / 10 : null);

async function runPart(browser, opts, origin, name) {
  const [width, height] = opts.size.split('x').map(Number);
  const context = await browser.newContext({ viewport: { width, height } });
  const page = await context.newPage();
  // the main thread's time inside each animation frame (the engine's whole frame in a no-threads build)
  await page.addInitScript(() => {
    window.__work = [];
    const raf = window.requestAnimationFrame.bind(window);
    window.requestAnimationFrame = (cb) => raf((t) => {
      const t0 = performance.now();
      try { return cb(t); } finally { if (window.__work.length < 20000) window.__work.push([t0, performance.now() - t0]); }
    });
  });
  const seen = { errors: [], failed: [], stalls: {}, views: [], done: null, lines: 0 };
  await page.route((u) => !u.href.startsWith(origin), (route) => route.fulfill({ status: 200, body: '' }));
  const started = Date.now();
  page.on('console', (msg) => {
    const text = msg.text();
    seen.lines += 1;
    if (msg.type() === 'error') seen.errors.push(text);
    for (const tag of [UI_TAG, TAG]) {
      if (!text.startsWith(`${tag} `)) continue;
      let line;
      try {
        line = JSON.parse(text.slice(tag.length + 1));
      } catch (e) {
        seen.errors.push(`unreadable ${tag} line: ${text.slice(0, 200)}`);
        return;
      }
      line.wall_s = round1((Date.now() - started) / 1000);
      if (tag === UI_TAG && line.t === 'stall') seen.stalls[line.mark] = line;
      else if (tag === TAG && line.t === 'view') seen.views.push(line);
      else if (tag === TAG && line.t === 'done') seen.done = line;
    }
  });
  page.on('pageerror', (err) => seen.errors.push(`page error: ${err.message}`));
  page.on('requestfailed', (req) => {
    const why = req.failure() ? req.failure().errorText : 'failed';
    if (why !== 'net::ERR_ABORTED') seen.failed.push(`${req.url()} (${why})`);
  });
  page.on('response', (res) => { if (res.status() >= 400) seen.failed.push(`${res.url()} (${res.status()})`); });
  const args = gameArgs(name, opts.extra);
  await page.goto(`${origin}/play.html?args=${args.map(encodeURIComponent).join(',')}`, { waitUntil: 'load' });
  const end = Date.now() + opts.timeoutS * 1000;
  let shots = 0;
  while (Date.now() < end && !seen.done) {
    if (opts.shots && seen.views.length > shots) {
      await page.screenshot({ path: join(opts.shots, `${name}_${seen.views[shots].view}.png`) }).catch(() => {});
      shots += 1;
    }
    await sleep(250);
  }
  const work = await page.evaluate(() => (window.__work || []).map((w) => w[1])).catch(() => []);
  await context.close();
  return summarizePart(name, seen, work, opts);
}

// A part's report from what the page printed (exported for the test).
export function summarizePart(name, seen, work, opts) {
  const out = { part: name, args: gameArgs(name, opts.extra || []), views: seen.views, stalls: {}, problems: [], misses: [] };
  if (!seen.done) out.problems.push('the probe never finished (no PEOPLE_WEB done line)');
  const base = seen.views.find((v) => v.view === 'level') || null;
  for (const v of seen.views) {
    const j = judgeView(v, v === base ? null : base);
    out.problems.push(...j.problems);
    out.misses.push(...j.misses);
  }
  for (const [mark, s] of Object.entries(seen.stalls)) {
    const ok = stallOk(s.first_ms, s.median_ms);
    out.stalls[mark] = { first_ms: s.first_ms, median_ms: s.median_ms, ratio: s.ratio, ok, load_worst_ms: s.load_worst_ms };
    if (!ok) out.misses.push(`${mark}: its first frame ${s.first_ms} ms is ${s.ratio}x the median frame (${s.median_ms} ms)`);
  }
  for (const mark of name === 'formation' ? ['first_formation', 'first_wolf'] : []) {
    if (seen.done && !(mark in seen.stalls)) out.problems.push(`no "${mark}" mark`);
  }
  const split = splitWarnings(seen.errors);
  out.console_errors = split.errors;
  out.engine_warnings = split.warnings;
  out.failed_requests = seen.failed;
  if (split.errors.length > 0) out.problems.push(`${split.errors.length} console error(s)`);
  if (seen.failed.length > 0) out.problems.push(`${seen.failed.length} failed request(s)`);
  out.page_frames = { count: work.length, median_work_ms: round1(median(work)), worst_work_ms: round1(Math.max(0, ...work)) };
  if (opts.strict) for (const m of out.misses) out.problems.push(`a budget miss (--strict): ${m}`);
  out.ok = out.problems.length === 0;
  return out;
}

export function median(values) {
  if (values.length === 0) return 0;
  const v = values.slice().sort((a, b) => a - b);
  const n = v.length;
  return n % 2 === 1 ? v[(n - 1) / 2] : (v[n / 2 - 1] + v[n / 2]) / 2;
}

async function main() {
  const opts = parseArgs(process.argv.slice(2));
  if (!existsSync(join(opts.build, 'play.html'))) {
    console.error(`${TOOL}: ${opts.build}/play.html is missing: run tools/build_web.sh first`);
    process.exit(1);
  }
  if (opts.shots) mkdirSync(opts.shots, { recursive: true });
  if (!process.env.PLAYWRIGHT_BROWSERS_PATH && existsSync('/opt/pw-browsers')) process.env.PLAYWRIGHT_BROWSERS_PATH = '/opt/pw-browsers';
  const { chromium } = loadPlaywright();
  const server = await serve(opts.build);
  const origin = `http://127.0.0.1:${server.address().port}`;
  const browser = await chromium.launch({
    headless: !opts.headed,
    args: ['--use-angle=swiftshader', '--enable-unsafe-swiftshader', '--ignore-gpu-blocklist', '--autoplay-policy=no-user-gesture-required'],
  });
  const guard = startMemoryGuard(TOOL);
  const started = Date.now();
  console.log(`${TOOL}: ${origin}/play.html (${opts.build}, ${opts.size}; parts: ${opts.parts.join(', ')})`);
  const report = { build: opts.build, viewport: opts.size, strict: opts.strict, parts: {} };
  const problems = [];
  for (const name of opts.parts) {
    const part = await runPart(browser, opts, origin, name);
    report.parts[name] = part;
    for (const p of part.problems) problems.push(`${name}: ${p}`);
  }
  guard.stop();
  await browser.close();
  server.close();
  report.wall_s = round1((Date.now() - started) / 1000);
  report.memory_guard = { limit_mb: guard.limitMb, renderer_peak_mb: guard.peakMb() };
  report.misses = [].concat(...opts.parts.map((n) => report.parts[n].misses.map((m) => `${n}: ${m}`)));
  const peak = report.memory_guard.renderer_peak_mb;
  if (typeof peak === 'number' && peak > RENDERER_MB) report.misses.push(`the renderer's peak ${peak} MB (at most ${RENDERER_MB} MB on a quiet machine)`);
  report.problems = problems;
  report.ok = problems.length === 0;
  if (opts.json) writeFileSync(opts.json, JSON.stringify(report, null, 2) + '\n');
  for (const name of opts.parts) {
    const p = report.parts[name];
    console.log(`  ${name}: ${p.ok ? 'ok' : 'FAILED'}; console errors ${p.console_errors.length}, engine warnings ${p.engine_warnings.length}, failed requests ${p.failed_requests.length}; the page's frames: ${p.page_frames.count}`);
    for (const v of p.views) {
      console.log(`    ${v.view}: ${v.draw_calls} draw calls, ${v.primitives} primitives, textures ${v.texture_mem_mb} MB, buffers ${v.buffer_mem_mb} MB; people skinned ${v.people.skinned}, crowd ${v.people.crowd}, far ${v.people.far}; creatures skinned ${v.others.skinned}, far ${v.others.far}; the people's CPU ${v.people_cpu_ms} ms a frame (${JSON.stringify(v.people_cpu_parts_ms)})`);
    }
    for (const [mark, s] of Object.entries(p.stalls)) console.log(`    ${mark}: first ${s.first_ms} ms, median ${s.median_ms} ms, ${s.ratio}x - ${s.ok ? 'no stall' : 'A STALL'}`);
    for (const e of p.console_errors.slice(0, 10)) console.log(`    error: ${e}`);
  }
  console.log(`  the renderer's peak memory: ${peak} MB`);
  for (const m of report.misses) console.log(`  MISS: ${m}`);
  console.log(`PEOPLE_CHECK ${JSON.stringify(report)}`);
  console.log(report.ok ? `${TOOL}: OK${report.misses.length > 0 ? ` (${report.misses.length} budget miss(es) reported; --strict fails on them)` : ''}`
    : `${TOOL}: FAILED - ${problems.join('; ')}`);
  process.exit(report.ok ? 0 : 1);
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  main().catch((e) => {
    console.error(`${TOOL}: ${e && e.stack ? e.stack : e}`);
    process.exit(1);
  });
}
