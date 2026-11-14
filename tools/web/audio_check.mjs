#!/usr/bin/env node
// The web audio check (P23; plan M6-M9 §3.5, §4.5, decisions 2, 3 and 8): the Web release in headless
// Chromium with its sound on. It serves the build folder on a free port (after checking that the page
// it serves is this game's), opens play.html with
//   * an AudioContext wrapper: every context the engine makes gets a tap on its destination;
//   * an AudioWorklet recorder on that tap: per 128-frame quantum, sound or silence (peak < 1e-4);
//   * a buffer tracker: every createBuffer counts as a registered sample until it is attached to a
//     source node; one attached to a source (Godot plays a copy of the registered buffer each time)
//     counts while that source plays. The live sample bytes are their sum, sampled at every change;
// presses Play, waits for the title's music, presses New Game (Enter: the title's first focus with no
// saved game) and records
//   * sound within 5 s of the Hollow (the zone set's start: the music director prints an AUDIO_MUSIC
//     line under --audio-stats, which the check passes);
//   * no silent run longer than 50 ms in the output during 60 s of the Hollow's music (an underrun
//     of the engine's mixer is a hole: the drone and the bed never rest). The no-threads build mixes
//     streams in the main thread's handler of the driver worklet's "read" messages, so a main
//     thread busy for longer than the worklet holds (at most the stream buffer: output_latency.web
//     200 is 8,192 frames, 185.8 ms) starves it. The check logs every "read" the main thread
//     handles (the driver's own port, wrapped), its long tasks (the Long Tasks API) and its frames
//     (requestAnimationFrame), and places each hole on the page's clock: a hole during which the
//     main thread handled no "read", ended by the first one it handled (within PLACE_TOLERANCE_MS),
//     is the main thread's (software WebGL draws a Valley frame in 100-450 ms on a GPU-less
//     machine); a hole while the mixer was served fails the check, and --strict fails on every
//     hole (a machine with a GPU, whose frames are short);
//   * the peak live sample bytes against the level's registered seconds x 353 KB + 12 MB (a 44.1 kHz
//     stereo float copy of every registered second, plus room for the copies that play);
//   * 0 console errors and no failed request (the page's web fonts are answered empty, so the check
//     needs no network).
// It prints one AUDIO_CHECK {json} line and exits 0 when everything holds (1 otherwise, 2 for a usage
// error). The P23 runs (the release and the forced two-part build) are in docs/systems/P23.md.
// The plan's criterion (M6 gate) is the strict one - no silent run over 50 ms in 60 s of the
// Hollow's music: every report says whether it held ("criterion"), and a default run that passes on
// holes it places on the main thread ends "OK (the plan's criterion NOT MET: ...)", never a bare OK.
// When a run fails - a timeout waiting for the title or the Hollow included - the --json file still
// gets the trace so far (the page's frames, long tasks and driver reads are logged from the page's
// load, not only while the recorder is armed), the page's state (the music marks, the AudioContext's
// state, the launcher's status line) and the last CONSOLE_TAIL console lines, which are printed too.
// Its own test: node tools/web/test_audio_check.mjs (a stub launcher, no build: a timeout's report,
// the criterion met, and holes the main thread explains passing the default check but not --strict).
//
// Usage (from the project folder, after tools/build_web.sh):
//   node tools/web/audio_check.mjs [--build=builds/web] [--args=a,b,...] [--route=R] [--music-s=60]
//        [--registered-s=S] [--size=640x360] [--timeout-s=600] [--json=FILE] [--strict] [--headed]
//   --args=a,b     more game arguments, passed through the launcher (play.html?args=)
//   --route=R      passed to the game as --route=R (the M7 gate runs the check on the world)
//   --registered-s the level's registered sample seconds (default: the Valley's, computed from the
//                  banks and assets/audio/manifest.json as Audio.sample_paths_for does)
//   --size         the browser viewport (default 640x360: SwiftShader's fill stays small)
//   --strict       every hole over 50 ms fails, a long task's too (for a machine with a GPU)
//   --json=FILE    the report, and the trace behind the hole verdicts (the driver's reads, the
//                  long tasks, the frame clock, every hole on the audio clock, the clock references)
//   --replay=FILE  no browser: places the holes of a --json file's trace again and prints them
// Needs Playwright (PLAYWRIGHT_MODULE, NODE_PATH or /opt/node-tools/node_modules) and its Chromium
// (PLAYWRIGHT_BROWSERS_PATH, default /opt/pw-browsers when that folder exists).

import { createServer, get as httpGet } from 'node:http';
import { createRequire } from 'node:module';
import { existsSync, readFileSync, statSync, writeFileSync } from 'node:fs';
import { extname, join, normalize, resolve, sep } from 'node:path';
// The recorder, the hole placing and the statistics live in audio_recorder.mjs (M7 gate: shared with
// stream_check.mjs --audio).
import {
  BYTES_PER_REGISTERED_S, HOLE_MAX_MS, LIVE_HEADROOM_BYTES, SILENCE_PEAK, analyseRecording, frameStats, instrument,
  placeHoles, readRecording, registeredSeconds, serviceStats, streamBufferMs, taskStats,
} from './audio_recorder.mjs';

const TITLE = 'Giantborn: Age of Titans';
const SOUND_WITHIN_S = 5;
const VALLEY = 'level.valley';
// The page's last console lines kept for a failure's report (M6 gate).
const CONSOLE_TAIL = 200;

function parseArgs(argv) {
  const opts = {
    build: 'builds/web', args: '', route: '', musicS: 60, registeredS: null, size: '640x360', timeoutS: 600,
    json: '', strict: false, headed: false, replay: '',
  };
  for (const arg of argv) {
    const [key, ...rest] = arg.split('=');
    const value = rest.join('=');
    switch (key) {
      case '--build': opts.build = value; break;
      case '--args': opts.args = value; break;
      case '--route': opts.route = value; break;
      case '--music-s': opts.musicS = Number(value); break;
      case '--registered-s': opts.registeredS = Number(value); break;
      case '--size': opts.size = value; break;
      case '--timeout-s': opts.timeoutS = Number(value); break;
      case '--json': opts.json = value; break;
      case '--strict': opts.strict = true; break;
      case '--replay': opts.replay = value; break;
      case '--headed': opts.headed = true; break;
      case '-h': case '--help':
        console.log(readFileSync(new URL(import.meta.url), 'utf8').split('\n').slice(1).filter((l, i, all) =>
          all.slice(0, i + 1).every((x) => x.startsWith('//'))).join('\n'));
        process.exit(0);
        break;
      default:
        console.error(`audio_check: unknown option ${arg}`);
        process.exit(2);
    }
  }
  if (!/^\d+x\d+$/.test(opts.size) || !(opts.musicS > 0) || !(opts.timeoutS > 0)) {
    console.error('audio_check: --size wants WxH, --music-s and --timeout-s positive numbers');
    process.exit(2);
  }
  return opts;
}

function loadPlaywright() {
  const require = createRequire(import.meta.url);
  for (const name of [process.env.PLAYWRIGHT_MODULE, 'playwright', '/opt/node-tools/node_modules/playwright']) {
    if (!name) continue;
    try {
      return require(name);
    } catch (e) {
      /* the next place */
    }
  }
  console.error('audio_check: Playwright not found (set PLAYWRIGHT_MODULE or NODE_PATH)');
  process.exit(1);
}

// The game's command line (each item one argument; web/launcher.html puts them after "--").
function gameArgs(opts) {
  const args = ['--audio-stats'];
  for (const a of opts.args.split(',').map((x) => x.trim()).filter((x) => x.length > 0)) args.push(a);
  if (opts.route) args.push(`--route=${opts.route}`);
  for (const a of args) {
    if (a.includes(',')) {
      console.error(`audio_check: a game argument may not hold a comma: ${a}`);
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

function fetchText(url) {
  return new Promise((ok, fail) => {
    httpGet(url, (res) => {
      let body = '';
      res.setEncoding('utf8');
      res.on('data', (c) => { body += c; });
      res.on('end', () => ok({ status: res.statusCode, body }));
    }).on('error', fail);
  });
}

const sleep = (ms) => new Promise((ok) => setTimeout(ok, ms));

// --replay: the holes of a saved trace placed again (exit 0 when each is the main thread's).
function replay(file) {
  const saved = JSON.parse(readFileSync(file, 'utf8'));
  const t = saved.trace;
  if (!t || !Array.isArray(t.holes)) {
    console.error(`audio_check: ${file} holds no trace`);
    process.exit(2);
  }
  if (t.partial) {
    console.error(`audio_check: ${file} holds a failed run's partial trace (no music was recorded): see its failure_state and console_tail`);
    process.exit(2);
  }
  const placed = placeHoles(t.holes, t.service || [], t.arm, t.disarm, t.quantum_ms);
  console.log(`audio_check: ${file}: ${placed.holes} hole(s) over ${HOLE_MAX_MS} ms, ${placed.while_unserved} while the main thread left the mixer unserved, ${placed.elsewhere.length} otherwise`);
  for (const e of placed.elsewhere.slice(0, 10)) console.log(`    ${e.ms} ms at ${e.page_s} s`);
  process.exit(placed.elsewhere.length === 0 ? 0 : 1);
}

async function main() {
  const opts = parseArgs(process.argv.slice(2));
  if (opts.replay) replay(opts.replay);
  if (!existsSync(join(opts.build, 'play.html'))) {
    console.error(`audio_check: ${opts.build}/play.html is missing: run tools/build_web.sh first`);
    process.exit(1);
  }
  if (!process.env.PLAYWRIGHT_BROWSERS_PATH && existsSync('/opt/pw-browsers')) {
    process.env.PLAYWRIGHT_BROWSERS_PATH = '/opt/pw-browsers';
  }
  const registeredS = opts.registeredS !== null ? opts.registeredS : registeredSeconds(VALLEY);
  const capBytes = Math.round(registeredS * BYTES_PER_REGISTERED_S + LIVE_HEADROOM_BYTES);
  const { chromium } = loadPlaywright();
  const server = await serve(opts.build);
  const port = server.address().port;
  const origin = `http://127.0.0.1:${port}`;
  // This server, this build: the page it serves must be this game's launcher.
  const probe = await fetchText(`${origin}/play.html`);
  if (probe.status !== 200 || !probe.body.includes(`<title>${TITLE}</title>`)) {
    server.close();
    console.error(`audio_check: ${origin}/play.html is not ${TITLE}'s page (HTTP ${probe.status})`);
    process.exit(1);
  }
  const parts = (probe.body.match(/pckParts: (\d+)/) || [null, '1'])[1];
  const args = gameArgs(opts);
  const url = `${origin}/play.html?args=${args.map(encodeURIComponent).join(',')}`;
  const [width, height] = opts.size.split('x').map(Number);
  const browser = await chromium.launch({
    headless: !opts.headed,
    args: ['--use-angle=swiftshader', '--enable-unsafe-swiftshader', '--ignore-gpu-blocklist'],
  });
  const page = await browser.newPage({ viewport: { width, height } });
  const started = Date.now();
  await page.addInitScript(instrument, { silencePeak: SILENCE_PEAK, holeMs: HOLE_MAX_MS });
  const external = [];
  await page.route((u) => !u.href.startsWith(origin), (route) => {
    external.push(route.request().url());
    const css = route.request().resourceType() === 'stylesheet';
    return route.fulfill({ status: 200, contentType: css ? 'text/css' : 'application/octet-stream', body: '' });
  });
  const errors = [];
  const failedRequests = [];
  const musicLines = [];
  const consoleTail = [];
  page.on('console', (msg) => {
    const text = msg.text();
    if (msg.type() === 'error') errors.push(text);
    if (text.startsWith('AUDIO_MUSIC ')) musicLines.push(text);
    consoleTail.push(`[${Math.round((Date.now() - started) / 100) / 10} s ${msg.type()}] ${text}`);
    if (consoleTail.length > CONSOLE_TAIL) consoleTail.shift();
  });
  page.on('pageerror', (err) => {
    errors.push(`page error: ${err.message}`);
    consoleTail.push(`[${Math.round((Date.now() - started) / 100) / 10} s pageerror] ${err.message}`);
    if (consoleTail.length > CONSOLE_TAIL) consoleTail.shift();
  });
  page.on('requestfailed', (req) => {
    const why = req.failure() ? req.failure().errorText : 'failed';
    if (why !== 'net::ERR_ABORTED') failedRequests.push(`${req.url()} (${why})`);
  });
  page.on('response', (res) => { if (res.status() >= 400) failedRequests.push(`${res.url()} (${res.status()})`); });

  const deadline = started + opts.timeoutS * 1000;
  const marks = () => page.evaluate(() => window.__audioCheck.marks.slice());
  const waitFor = async (what, test, step = 250) => {
    while (Date.now() < deadline) {
      const m = (await marks()).find(test);
      if (m) return m;
      await sleep(step);
    }
    throw new Error(`timed out waiting for ${what}`);
  };
  const problems = [];
  let trace = null;   // the frame clock and the holes, for the --json file
  const report = {
    build: opts.build, parts: Number(parts), url_args: args, viewport: opts.size, title_checked: true,
    registered_s: registeredS, cap_bytes: capBytes,
  };
  try {
    console.log(`audio_check: ${url} (index.pck in ${parts} part${parts === '1' ? '' : 's'})`);
    await page.goto(url, { waitUntil: 'load' });
    const playAt = await page.evaluate(() => performance.now());
    await page.click('#play');
    const title = await waitFor('the title music', (m) => m.set === 'music.title');
    report.play_to_title_s = Math.round((title.page_ms - playAt) / 100) / 10;
    report.title_context_state = title.ctx_state;
    await sleep(1500);
    await page.focus('#game-canvas').catch(() => {});
    await page.keyboard.press('Enter');   // New Game: the title's first focus without a saved game
    const hollow = await waitFor('the Hollow\'s music', (m) => m.state === 'zone');
    report.hollow_set = hollow.set;
    report.new_game_to_hollow_s = Math.round((hollow.page_ms - title.page_ms) / 100) / 10;
    report.hollow_context_state = hollow.ctx_state;
    await page.evaluate((t) => window.__audioCheck.post({ cmd: 'first_sound_after', t }), hollow.ctx_t);
    await sleep(SOUND_WITHIN_S * 1000 + 500);
    const first = await page.evaluate(() => window.__audioCheck.firstSound);
    report.sound_after_hollow_s = first ? Math.round((first.t - hollow.ctx_t) * 1000) / 1000 : null;
    if (!first || first.t - hollow.ctx_t > SOUND_WITHIN_S) problems.push(`no sound within ${SOUND_WITHIN_S} s of the Hollow`);
    // 60 s of the Hollow's music: the longest silent run.
    await page.evaluate(() => window.__audioCheck.arm());
    const t0 = await page.evaluate(() => performance.now());
    await sleep(opts.musicS * 1000);
    await page.evaluate(() => window.__audioCheck.disarm());
    await sleep(500);
    const state = await readRecording(page);
    const rec = analyseRecording(state, { musicS: opts.musicS, strict: opts.strict, t0 });
    problems.push(...rec.problems);
    if (rec.music) {
      report.music = rec.music;
      report.page_frames = rec.page_frames;
      report.long_tasks = rec.long_tasks;
      report.driver = rec.driver;
      trace = rec.trace;
      report.strict = opts.strict;
      report.criterion = rec.criterion;
    }
    report.context = state.ctx;
    report.samples = {
      peak_live_bytes: state.peakLiveBytes, live_bytes_at_end: state.liveBytes, registered_bytes: state.registeredBytes,
      peak_playing_copy_bytes: state.peakPlayingBytes, buffers_created: state.buffersCreated,
      buffers_attached: state.buffersAttached, sources_started: state.sourcesStarted,
    };
    if (state.peakLiveBytes > capBytes) problems.push(`peak live sample bytes ${state.peakLiveBytes} > ${capBytes}`);
    report.music_marks = state.marks.map((m) => ({ set: m.set, state: m.state, context: m.context, ctx_state: m.ctx_state }));
    report.contexts = state.contexts;
  } catch (e) {
    problems.push(String(e && e.message ? e.message : e));
    // M6 gate: what the page was doing when the run gave up (a timeout waiting for the title's or
    // the Hollow's music left no trace before): its state, and the trace logged since its load.
    const snap = await page.evaluate(() => {
      const A = window.__audioCheck;
      if (!A) return null;
      const c = A.ctx();
      const status = document.querySelector('#status, .status, #progress-text, #status-text');
      return {
        marks: A.marks.slice(), log: A.log.slice(0, 50), contexts: A.ctxs.length,
        ctx: c ? { state: c.state, rate: c.sampleRate, current_time: c.currentTime } : null,
        recorder: A.rec.stats || null, driver_watched: A.driverWatched, first_sound: A.firstSound,
        frames: A.frames.slice(-4000), tasks: A.tasks.slice(-2000), service: A.service.slice(-20000),
        page_ms: performance.now(), title: document.title, status_text: status ? status.textContent : null,
        canvas: !!document.querySelector('#game-canvas'),
      };
    }).catch((err) => ({ unavailable: String(err && err.message ? err.message : err) }));
    report.failure_state = snap ? {
      marks: snap.marks, log: snap.log, contexts: snap.contexts, context: snap.ctx, recorder: snap.recorder,
      driver_watched: snap.driver_watched, first_sound: snap.first_sound, page_s: snap.page_ms !== undefined
        ? Math.round(snap.page_ms / 100) / 10 : null, title: snap.title, status_text: snap.status_text,
      canvas: snap.canvas, unavailable: snap.unavailable,
    } : null;
    if (snap && Array.isArray(snap.frames)) {
      const bufferMs = streamBufferMs(snap.ctx && snap.ctx.rate ? snap.ctx.rate : 44100);
      report.failure_state.page_frames = frameStats(snap.frames, bufferMs);
      report.failure_state.long_tasks = taskStats(snap.tasks, snap.frames.length ? snap.frames[0] : 0, snap.page_ms);
      report.failure_state.driver = { watched: snap.driver_watched, ...serviceStats(snap.service, bufferMs) };
      if (trace === null) trace = { frames: snap.frames, tasks: snap.tasks, service: snap.service, holes: [], partial: true };
    }
  }
  report.wall_s = Math.round((Date.now() - started) / 100) / 10;
  report.console_tail = problems.length > 0 ? consoleTail.slice() : consoleTail.slice(-20);
  await browser.close();
  server.close();
  report.console_errors = errors;
  report.failed_requests = failedRequests;
  report.external_requests_answered_empty = external.length;
  if (errors.length > 0) problems.push(`${errors.length} console error(s)`);
  if (failedRequests.length > 0) problems.push(`${failedRequests.length} failed request(s)`);
  report.problems = problems;
  report.ok = problems.length === 0;
  if (opts.json) writeFileSync(opts.json, JSON.stringify({ ...report, trace }, null, 2) + '\n');
  const m = report.music || {};
  const mbs = (b) => (typeof b === 'number' ? (b / 1048576).toFixed(1) : 'N/A');
  console.log(`audio_check: ${report.parts} pck part(s); the Hollow plays ${report.hollow_set || '?'}; sound ${report.sound_after_hollow_s !== undefined && report.sound_after_hollow_s !== null ? `${report.sound_after_hollow_s} s after it` : 'not measured'}; context ${report.context ? report.context.state : '?'} at ${report.context ? report.context.rate : '?'} Hz`);
  if (report.music) {
    console.log(`  music for ${m.seconds} s: longest silence ${m.longest_silence_ms} ms (limit ${HOLE_MAX_MS}), runs over 50 ms ${m.silent_runs_over_50_ms} (${m.holes_while_unserved} while the main thread left the mixer unserved, ${(m.holes_elsewhere || []).length} otherwise${report.strict ? '' : '; --strict fails every one'}), peak ${m.peak}`);
  } else {
    console.log('  music: not measured (the run ended before the recorder was armed)');
  }
  // The music window's clocks, or (a failed run) the clocks logged from the page's load.
  const fsx = report.failure_state || {};
  const pf = report.page_frames || fsx.page_frames || {};
  const lt = report.long_tasks || fsx.long_tasks || {};
  const dv = report.driver || fsx.driver || {};
  if (pf.n !== undefined) {
    console.log(`  main thread${report.page_frames ? '' : ' (since the page loaded)'}: ${lt.n} long tasks (p50 ${lt.p50_ms} ms, longest ${lt.max_ms} ms, ${typeof lt.busy_share === 'number' ? Math.round(lt.busy_share * 100) : '?'} % of the time); page frames: ${pf.n}, p50 ${pf.p50_ms} ms, p95 ${pf.p95_ms} ms, longest ${pf.max_ms} ms; the driver's reads ${dv.watched ? `${dv.reads}, longest gap ${dv.longest_gap_ms} ms, ${dv.gaps_over_buffer} gaps over the ${pf.buffer_ms} ms stream buffer` : 'not seen'}`);
  }
  console.log(`  samples: peak live ${mbs(report.samples && report.samples.peak_live_bytes)} MB (cap ${mbs(capBytes)} MB = ${registeredS} s x 353 KB + 12 MB), copies playing at most ${mbs(report.samples && report.samples.peak_playing_copy_bytes)} MB`);
  console.log(`  console errors ${errors.length}, failed requests ${failedRequests.length}, external requests answered empty ${external.length}, wall ${report.wall_s} s`);
  for (const e of errors.slice(0, 10)) console.log(`    error: ${e}`);
  for (const r of failedRequests.slice(0, 10)) console.log(`    request: ${r}`);
  const crit = report.criterion;
  console.log(`  the plan's criterion (no silent run over ${HOLE_MAX_MS} ms in ${opts.musicS} s of music): ${crit ? (crit.met ? 'MET' : `NOT MET (${crit.holes} hole(s), the longest ${crit.longest_silence_ms} ms)`) : 'NOT MEASURED'}`);
  if (problems.length > 0) {
    console.log(`  the page's last ${Math.min(30, consoleTail.length)} console lines:`);
    for (const line of consoleTail.slice(-30)) console.log(`    ${line}`);
    if (report.failure_state) {
      const fs = report.failure_state;
      console.log(`  the page when it gave up: ${fs.unavailable ? `unavailable (${fs.unavailable})` : `context ${fs.context ? `${fs.context.state} at ${fs.context.current_time} s` : 'none'}, music marks ${(fs.marks || []).map((x) => `${x.set || '?'}/${x.state || '?'}`).join(', ') || 'none'}, status "${fs.status_text || ''}", ${fs.page_frames ? `${fs.page_frames.n} frames (longest ${fs.page_frames.max_ms} ms), ${fs.long_tasks.n} long tasks` : 'no frames'}`}`);
    }
  }
  console.log(`AUDIO_CHECK ${JSON.stringify({ ...report, console_tail: report.console_tail.slice(-20) })}`);
  if (report.ok) {
    console.log(crit && !crit.met
      ? `audio_check: OK (the plan's criterion NOT MET: ${crit.holes} hole(s) over ${HOLE_MAX_MS} ms, every one placed on the main thread; run --strict on a machine with a GPU for the gate)`
      : 'audio_check: OK');
  } else {
    console.log(`audio_check: FAILED - ${problems.join('; ')}`);
  }
  process.exit(report.ok ? 0 : 1);
}

main().catch((e) => {
  console.error(`audio_check: ${e && e.stack ? e.stack : e}`);
  process.exit(1);
});
