#!/usr/bin/env node
// The web stream check (P24a; plan M6-M9 §3.6, §5.3): the world walk in headless Chromium **with
// gameplay** - the giant walking the route with the stick, AI on, 3D on - on the `Web (test)` build.
// It serves the build, opens play.html?args=... (web/launcher.html passes them to the engine),
// presses Play and waits for the run's AUTOPILOT_RESULT, then reports:
//   * frames: the page's requestAnimationFrame intervals while the giant walks (between the walk's
//     WORLD_WALK_START and WORLD_WALK_END lines: p50 / p99 / worst) against the indicative web
//     budget (worst <= 45 ms, p99 <= 25 ms; the brief's 19.6 ms had 3D off and no gameplay), and
//     the engine's own frame times for reference (PerfProbe frame_ms, which the engine caps at
//     8 physics ticks, 133 ms, a frame);
//   * streaming: the work per frame (p50 / p99 / max), loads, unloads, thrash, the most chunks
//     loaded, the least margin to unloaded ground (>= 200 m), the walk's own check failures;
//   * draw calls (rendered: the PerfProbe's per frame), the console errors while the game runs (0
//     wanted; what the page reports while the engine shuts down after the result is listed apart:
//     a player never quits the engine on the web) and the failed requests.
// The P24a run and the M7 gate's (on the real world: --world) are recorded in docs/PERFORMANCE.md.
//
// Usage (from the project folder, after tools/build_web.sh --preset="Web (test)"):
//   node tools/web/stream_check.mjs [--build=builds/web_test] [--level=res://scenes/test/test_world.tscn]
//        [--world] [--route=x:z;x:z;...] [--walk-speed=M] [--laps=N] [--autoplay=S] [--size=WxH]
//        [--timeout-s=S] [--json=FILE] [--strict] [--headed]
//   --world        the real world (--mode=world --new-game; from P25) instead of --level
//   --walk-speed   carry the giant at M m/s instead of walking it (16: the stage-6 sprint case)
//   --size         the browser viewport (default 1280x720)
//   --strict       also fail (exit 1) when the indicative frame budget is missed
// Exit code: 0 when the run reported, the walk finished without check failures and the console
// had no errors (and, with --strict, the frame budget held); 1 otherwise; 2 for a usage error.
// Needs Playwright (the "playwright" package: PLAYWRIGHT_MODULE, NODE_PATH or
// /opt/node-tools/node_modules) and its Chromium (PLAYWRIGHT_BROWSERS_PATH, default /opt/pw-browsers
// when that folder exists). Software WebGL (SwiftShader) is all a GPU-less machine has: its frame
// times are the CPU's rasterising, indicative only.

import { createServer } from 'node:http';
import { createRequire } from 'node:module';
import { existsSync, readFileSync, statSync, writeFileSync } from 'node:fs';
import { extname, join, normalize, resolve, sep } from 'node:path';

const BUDGET_WORST_MS = 45;
const BUDGET_P99_MS = 25;
const MARGIN_REQUIRED_M = 200;

function parseArgs(argv) {
  const opts = {
    build: 'builds/web_test', level: 'res://scenes/test/test_world.tscn', world: false, route: '',
    walkSpeed: '', laps: '', autoplay: 1200, size: '1280x720', timeoutS: 3600, json: '', strict: false,
    headed: false,
  };
  for (const arg of argv) {
    const [key, ...rest] = arg.split('=');
    const value = rest.join('=');
    switch (key) {
      case '--build': opts.build = value; break;
      case '--level': opts.level = value; break;
      case '--world': opts.world = true; break;
      case '--route': opts.route = value; break;
      case '--walk-speed': opts.walkSpeed = value; break;
      case '--laps': opts.laps = value; break;
      case '--autoplay': opts.autoplay = Number(value); break;
      case '--size': opts.size = value; break;
      case '--timeout-s': opts.timeoutS = Number(value); break;
      case '--json': opts.json = value; break;
      case '--strict': opts.strict = true; break;
      case '--headed': opts.headed = true; break;
      case '-h': case '--help':
        console.log(readFileSync(new URL(import.meta.url), 'utf8').split('\n').slice(1, 30).join('\n'));
        process.exit(0);
        break;
      default:
        console.error(`stream_check: unknown option ${arg}`);
        process.exit(2);
    }
  }
  if (!/^\d+x\d+$/.test(opts.size)) {
    console.error('stream_check: --size wants WxH');
    process.exit(2);
  }
  return opts;
}

function loadPlaywright() {
  const require = createRequire(import.meta.url);
  const tries = [process.env.PLAYWRIGHT_MODULE, 'playwright', '/opt/node-tools/node_modules/playwright'];
  for (const name of tries) {
    if (!name) continue;
    try {
      return require(name);
    } catch (e) {
      /* the next place */
    }
  }
  console.error('stream_check: Playwright not found (set PLAYWRIGHT_MODULE or NODE_PATH)');
  process.exit(1);
}

// The engine's command line (each item one argument; web/launcher.html puts them after "--").
function engineArgs(opts) {
  const args = ['--no-user-settings'];
  if (opts.world) args.push('--mode=world', '--new-game');
  else args.push(`--level=${opts.level}`);
  args.push('--scenario=world_walk', `--autoplay=${opts.autoplay}`);
  if (opts.route) args.push(`--route=${opts.route}`);
  if (opts.walkSpeed) args.push(`--walk-speed=${opts.walkSpeed}`);
  if (opts.laps) args.push(`--walk-laps=${opts.laps}`);
  for (const a of args) {
    if (a.includes(',')) {
      console.error(`stream_check: an engine argument may not hold a comma: ${a}`);
      process.exit(2);
    }
  }
  return args;
}

const TYPES = {
  '.html': 'text/html; charset=utf-8', '.js': 'text/javascript', '.wasm': 'application/wasm',
  '.txt': 'text/plain; charset=utf-8', '.jpg': 'image/jpeg', '.png': 'image/png', '.pck': 'application/octet-stream',
};

// A static server for the build folder on 127.0.0.1 (a free port).
function serve(root) {
  const base = resolve(root);
  const server = createServer((req, res) => {
    const path = decodeURIComponent(new URL(req.url, 'http://x').pathname);
    if (path === '/favicon.ico') {
      res.writeHead(204);
      res.end();
      return;
    }
    const file = normalize(join(base, path === '/' ? 'play.html' : path));
    if (!file.startsWith(base + sep) || !existsSync(file) || !statSync(file).isFile()) {
      res.writeHead(404);
      res.end('not found');
      return;
    }
    res.writeHead(200, { 'Content-Type': TYPES[extname(file)] || 'application/octet-stream', 'Cache-Control': 'no-store' });
    res.end(readFileSync(file));
  });
  return new Promise((ok) => server.listen(0, '127.0.0.1', () => ok(server)));
}

function percentile(sorted, p) {
  if (sorted.length === 0) return null;
  const rank = Math.min(sorted.length - 1, Math.max(0, Math.ceil(p / 100 * sorted.length) - 1));
  return sorted[rank];
}

function summary(values) {
  const v = values.filter((x) => Number.isFinite(x)).slice().sort((a, b) => a - b);
  if (v.length === 0) return { n: 0 };
  const r = (x) => Math.round(x * 1000) / 1000;
  const mean = v.reduce((a, b) => a + b, 0) / v.length;
  return { n: v.length, p50: r(percentile(v, 50)), p95: r(percentile(v, 95)), p99: r(percentile(v, 99)), max: r(v[v.length - 1]), mean: r(mean) };
}

function verdict(value, limit) {
  if (typeof value !== 'number') return 'N/A';
  return value <= limit ? 'PASS' : 'MISS';
}

async function main() {
  const opts = parseArgs(process.argv.slice(2));
  if (!existsSync(join(opts.build, 'play.html'))) {
    console.error(`stream_check: ${opts.build}/play.html is missing: run tools/build_web.sh --preset="Web (test)" first`);
    process.exit(1);
  }
  if (!process.env.PLAYWRIGHT_BROWSERS_PATH && existsSync('/opt/pw-browsers')) {
    process.env.PLAYWRIGHT_BROWSERS_PATH = '/opt/pw-browsers';
  }
  const { chromium } = loadPlaywright();
  const server = await serve(opts.build);
  const port = server.address().port;
  const args = engineArgs(opts);
  const url = `http://127.0.0.1:${port}/play.html?args=${args.map(encodeURIComponent).join(',')}`;
  const [width, height] = opts.size.split('x').map(Number);
  const browser = await chromium.launch({
    headless: !opts.headed,
    args: ['--use-angle=swiftshader', '--enable-unsafe-swiftshader', '--ignore-gpu-blocklist', '--autoplay-policy=no-user-gesture-required'],
  });
  const page = await browser.newPage({ viewport: { width, height } });
  // The page's frame clock: every requestAnimationFrame interval while the giant walks (the engine
  // prints WORLD_WALK_START and WORLD_WALK_END through console.log).
  await page.addInitScript(() => {
    window.__frames = [];
    window.__frameClock = false;
    window.__walkStart = 0;
    let last = 0;
    const tick = (t) => {
      if (window.__frameClock && last > 0) window.__frames.push(t - last);
      last = t;
      requestAnimationFrame(tick);
    };
    requestAnimationFrame(tick);
    const log = console.log.bind(console);
    console.log = (...items) => {
      const text = items.map(String).join(' ');
      if (text.startsWith('WORLD_WALK_START')) {
        window.__frames = [];
        window.__frameClock = true;
        window.__walkStart = performance.now();
      } else if (text.startsWith('WORLD_WALK_END') || text.startsWith('AUTOPILOT_RESULT')) {
        window.__frameClock = false;
      }
      log(...items);
    };
  });
  const errors = [];
  // The autopilot quits the engine after its result; what the page reports while the engine shuts
  // down (a player never quits the engine on the web) is listed apart and does not fail the check.
  const exitErrors = [];
  const failedRequests = [];
  let perf = null;
  let result = null;
  let lines = 0;
  page.on('console', (msg) => {
    const text = msg.text();
    lines += 1;
    if (msg.type() === 'error') (result === null ? errors : exitErrors).push(text);
    if (text.startsWith('PERF_RESULT ')) {
      try { perf = JSON.parse(text.slice('PERF_RESULT '.length)); } catch (e) { errors.push(`unreadable PERF_RESULT: ${e}`); }
    } else if (text.startsWith('AUTOPILOT_RESULT ')) {
      try { result = JSON.parse(text.slice('AUTOPILOT_RESULT '.length)); } catch (e) { errors.push(`unreadable AUTOPILOT_RESULT: ${e}`); }
    }
  });
  page.on('pageerror', (err) => (result === null ? errors : exitErrors).push(`page error: ${err.message}`));
  const abortedRequests = [];
  page.on('requestfailed', (req) => {
    const why = req.failure() ? req.failure().errorText : 'failed';
    // A request the page itself cancels (the launcher's download of a file it then reads another
    // way) is no failure.
    (why === 'net::ERR_ABORTED' ? abortedRequests : failedRequests).push(`${req.url()} (${why})`);
  });
  page.on('response', (res) => { if (res.status() >= 400) failedRequests.push(`${res.url()} (${res.status()})`); });

  const started = Date.now();
  console.log(`stream_check: ${url}`);
  await page.goto(url, { waitUntil: 'load' });
  const playAt = await page.evaluate(() => performance.now());
  await page.click('#play');
  const deadline = started + opts.timeoutS * 1000;
  let lastNote = Date.now();
  while (result === null && Date.now() < deadline) {
    await new Promise((ok) => setTimeout(ok, 1000));
    if (Date.now() - lastNote > 60000) {
      lastNote = Date.now();
      console.log(`stream_check: ${Math.round((Date.now() - started) / 1000)} s, ${lines} console lines, waiting for AUTOPILOT_RESULT`);
    }
  }
  const wallS = (Date.now() - started) / 1000;
  // The run quits after its result: its last lines (anything left at exit) count too.
  if (result !== null) await new Promise((ok) => setTimeout(ok, 3000));
  const rafFrames = await page.evaluate(() => window.__frames.slice());
  const walkStart = await page.evaluate(() => window.__walkStart);
  await browser.close();
  server.close();

  const walk = (result && result.world_walk) || {};
  const frames = perf && typeof perf.frame_ms === 'object' ? perf.frame_ms : null;
  const raf = summary(rafFrames);
  const report = {
    url_args: args,
    wall_s: Math.round(wallS * 10) / 10,
    result: result !== null,
    viewport: opts.size,
    renderer: perf ? `${perf.renderer} (${perf.adapter})` : 'N/A',
    quality: perf ? perf.quality : 'N/A',
    play_to_walk_s: walkStart > 0 ? Math.round((walkStart - playAt) / 100) / 10 : null,
    raf_frames: raf,
    engine_frames: frames,
    worst_frame_ms: raf.n ? raf.max : null,
    p99_frame_ms: raf.n ? raf.p99 : null,
    budget: {
      worst_ms: { limit: BUDGET_WORST_MS, value: raf.n ? raf.max : null, verdict: verdict(raf.n ? raf.max : null, BUDGET_WORST_MS) },
      p99_ms: { limit: BUDGET_P99_MS, value: raf.n ? raf.p99 : null, verdict: verdict(raf.n ? raf.p99 : null, BUDGET_P99_MS) },
    },
    draw_calls: perf && typeof perf.draw_calls === 'object' ? perf.draw_calls : (perf ? perf.draw_calls : null),
    cpu_tick_ms: perf && typeof perf.cpu_tick_ms === 'object' ? perf.cpu_tick_ms : null,
    walk: {
      mode: walk.mode, speed_mps: walk.speed_mps, metres: walk.metres, seconds: walk.seconds,
      finished: walk.finished, min_margin_m: walk.min_margin_m, max_loaded: walk.max_loaded, loads: walk.loads,
      unloads: walk.unloads, thrash: walk.thrash, work_ms_p50: walk.work_ms_p50, work_ms_p99: walk.work_ms_p99,
      work_ms_max: walk.work_ms_max, seam_crossings: walk.seam_crossings, stuck_teleports: walk.stuck_teleports,
      under_terrain_ticks: walk.under_terrain_ticks, check_failures: walk.check_failures || [],
      steps_by_kind: walk.streaming ? walk.streaming.steps_by_kind : null,
    },
    errors_counted_by_game: result ? result.errors : null,
    console_errors: errors,
    errors_at_exit: exitErrors,
    failed_requests: failedRequests,
    aborted_requests: abortedRequests,
  };
  const problems = [];
  if (!result) problems.push(`no AUTOPILOT_RESULT within ${opts.timeoutS} s`);
  if (result && !walk.finished) problems.push('the walk did not finish');
  if ((walk.check_failures || []).length > 0) problems.push(`walk check failures: ${walk.check_failures.join('; ')}`);
  if (typeof walk.min_margin_m === 'number' && walk.min_margin_m < MARGIN_REQUIRED_M) problems.push(`margin ${walk.min_margin_m} m < ${MARGIN_REQUIRED_M} m`);
  if (errors.length > 0) problems.push(`${errors.length} console error(s)`);
  if (failedRequests.length > 0) problems.push(`${failedRequests.length} failed request(s)`);
  if (opts.strict) {
    if (report.budget.worst_ms.verdict !== 'PASS') problems.push(`worst frame ${report.worst_frame_ms} ms > ${BUDGET_WORST_MS} ms`);
    if (report.budget.p99_ms.verdict !== 'PASS') problems.push(`p99 frame ${report.p99_frame_ms} ms > ${BUDGET_P99_MS} ms`);
  }
  report.problems = problems;
  report.ok = problems.length === 0;
  if (opts.json) writeFileSync(opts.json, JSON.stringify(report, null, 2) + '\n');

  const f = (x) => (typeof x === 'number' ? x.toFixed(1) : 'N/A');
  console.log(`stream_check: ${report.walk.mode || '?'} walk of ${f(walk.metres)} m in ${f(walk.seconds)} s of game time, ${report.wall_s} s of wall time (${report.renderer}, ${report.quality}, ${opts.size})`);
  console.log(`  frames while walking (page rAF): p50 ${f(raf.p50)} ms, p99 ${f(raf.p99)} ms [${report.budget.p99_ms.verdict} <= ${BUDGET_P99_MS}], worst ${f(raf.max)} ms [${report.budget.worst_ms.verdict} <= ${BUDGET_WORST_MS}] over ${raf.n} frames (indicative); Play to the walk ${f(report.play_to_walk_s)} s`);
  console.log(`  frames (engine, capped at 133 ms): p50 ${f(frames && frames.p50)} ms, p99 ${f(frames && frames.p99)} ms, worst ${f(frames && frames.max)} ms`);
  console.log(`  streaming: work p50 ${f(walk.work_ms_p50)} / p99 ${f(walk.work_ms_p99)} / max ${f(walk.work_ms_max)} ms, loads ${walk.loads}, unloads ${walk.unloads}, thrash ${walk.thrash}, max loaded ${walk.max_loaded}, margin ${f(walk.min_margin_m)} m`);
  console.log(`  draw calls: ${report.draw_calls && report.draw_calls.max !== undefined ? `p50 ${report.draw_calls.p50}, max ${report.draw_calls.max}` : JSON.stringify(report.draw_calls)}; console errors ${errors.length} (${exitErrors.length} more at exit, not counted); failed requests ${failedRequests.length}`);
  for (const e of errors.slice(0, 10)) console.log(`    error: ${e}`);
  for (const e of exitErrors.slice(0, 10)) console.log(`    at exit (not counted): ${e}`);
  for (const r of failedRequests.slice(0, 10)) console.log(`    request: ${r}`);
  console.log(`STREAM_CHECK ${JSON.stringify(report)}`);
  console.log(report.ok ? 'stream_check: OK' : `stream_check: FAILED - ${problems.join('; ')}`);
  process.exit(report.ok ? 0 : 1);
}

main().catch((e) => {
  console.error(`stream_check: ${e && e.stack ? e.stack : e}`);
  process.exit(1);
});
