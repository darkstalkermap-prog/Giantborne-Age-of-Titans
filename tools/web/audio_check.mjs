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
//     of the engine's mixer is a hole: the drone and the bed never rest);
//   * the peak live sample bytes against the level's registered seconds x 353 KB + 12 MB (a 44.1 kHz
//     stereo float copy of every registered second, plus room for the copies that play);
//   * 0 console errors and no failed request (the page's web fonts are answered empty, so the check
//     needs no network).
// It prints one AUDIO_CHECK {json} line and exits 0 when everything holds (1 otherwise, 2 for a usage
// error). The P23 runs (the release and the forced two-part build) are in docs/systems/P23.md.
//
// Usage (from the project folder, after tools/build_web.sh):
//   node tools/web/audio_check.mjs [--build=builds/web] [--args=a,b,...] [--route=R] [--music-s=60]
//        [--registered-s=S] [--size=640x360] [--timeout-s=600] [--json=FILE] [--headed]
//   --args=a,b     more game arguments, passed through the launcher (play.html?args=)
//   --route=R      passed to the game as --route=R (the M7 gate runs the check on the world)
//   --registered-s the level's registered sample seconds (default: the Valley's, computed from the
//                  banks and assets/audio/manifest.json as Audio.sample_paths_for does)
//   --size         the browser viewport (default 640x360: SwiftShader's frames stay short)
// Needs Playwright (PLAYWRIGHT_MODULE, NODE_PATH or /opt/node-tools/node_modules) and its Chromium
// (PLAYWRIGHT_BROWSERS_PATH, default /opt/pw-browsers when that folder exists).

import { createServer, get as httpGet } from 'node:http';
import { createRequire } from 'node:module';
import { existsSync, readdirSync, readFileSync, statSync, writeFileSync } from 'node:fs';
import { extname, join, normalize, resolve, sep } from 'node:path';

const TITLE = 'Giantborn: Age of Titans';
const SOUND_WITHIN_S = 5;
const HOLE_MAX_MS = 50;
const BYTES_PER_REGISTERED_S = 353000;
const LIVE_HEADROOM_BYTES = 12000000;
const VALLEY = 'level.valley';
const SILENCE_PEAK = 1e-4;

function parseArgs(argv) {
  const opts = {
    build: 'builds/web', args: '', route: '', musicS: 60, registeredS: null, size: '640x360', timeoutS: 600,
    json: '', headed: false,
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
      case '--headed': opts.headed = true; break;
      case '-h': case '--help':
        console.log(readFileSync(new URL(import.meta.url), 'utf8').split('\n').slice(1, 36).join('\n'));
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

// The seconds of samples a level registers (Audio.sample_paths_for): every WAV of an SFX or UI cue
// with no `levels`, then of the cues whose `levels` name the level; seconds from the manifest.
function registeredSeconds(level) {
  const manifest = JSON.parse(readFileSync('assets/audio/manifest.json', 'utf8'));
  const files = manifest.files || {};
  const seen = new Set();
  let seconds = 0;
  for (const name of readdirSync('data/audio').sort()) {
    if (!name.startsWith('bank_') || !name.endsWith('.json')) continue;
    const bank = JSON.parse(readFileSync(join('data/audio', name), 'utf8'));
    for (const cue of Object.values(bank.cues || {})) {
      const bus = cue.bus || 'SFX';
      if (bus !== 'SFX' && bus !== 'UI') continue;
      const levels = cue.levels || [];
      if (levels.length > 0 && !levels.includes(level)) continue;
      for (const path of cue.files || []) {
        if (!String(path).endsWith('.wav') || seen.has(path)) continue;
        seen.add(path);
        seconds += Number((files[path] || {}).seconds || 0);
      }
    }
  }
  return Math.round(seconds * 100) / 100;
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

// Injected before the page's scripts (Playwright addInitScript): the AudioContext wrapper, the
// destination tap with the recorder worklet, the buffer tracker and the AUDIO_MUSIC marks.
function instrument({ silencePeak, holeMs }) {
  const A = (window.__audioCheck = {
    ctxs: [], log: [], marks: [], rec: {}, liveBytes: 0, peakLiveBytes: 0, registeredBytes: 0, playingBytes: 0,
    peakPlayingBytes: 0, buffersCreated: 0, buffersAttached: 0, sourcesStarted: 0, firstSound: null,
  });
  const RECORDER = `
class CheckRecorder extends AudioWorkletProcessor {
  constructor() {
    super();
    this.armed = null;
    this.waitFrom = -1;
    this.port.onmessage = (e) => {
      const m = e.data;
      if (m.cmd === 'arm') this.armed = { quanta: 0, silent: 0, run: 0, longest: 0, runs_over: 0, peak: 0, start_t: currentTime };
      if (m.cmd === 'first_sound_after') this.waitFrom = m.t;
      if (m.cmd === 'disarm') {
        const a = this.armed;
        this.armed = null;
        if (a) { a.end_t = currentTime; a.sample_rate = sampleRate; }
        this.port.postMessage({ kind: 'stats', res: a });
      }
    };
  }
  process(inputs) {
    const inp = inputs[0];
    let peak = 0;
    for (const ch of inp) for (let i = 0; i < ch.length; i++) { const v = Math.abs(ch[i]); if (v > peak) peak = v; }
    const silent = inp.length === 0 || peak < ${silencePeak};
    if (this.waitFrom >= 0 && currentTime >= this.waitFrom && !silent) {
      this.port.postMessage({ kind: 'first_sound', t: currentTime, peak });
      this.waitFrom = -1;
    }
    const a = this.armed;
    if (a) {
      a.quanta++;
      if (peak > a.peak) a.peak = peak;
      if (silent) {
        a.silent++;
        a.run++;
        if (a.run > a.longest) a.longest = a.run;
      } else {
        if (a.run * 128 / sampleRate * 1000 > ${holeMs}) a.runs_over++;
        a.run = 0;
      }
    }
    return true;
  }
}
registerProcessor('check-recorder', CheckRecorder);
`;
  const now = () => performance.now();
  const OrigAC = window.AudioContext || window.webkitAudioContext;
  const OrigAWN = window.AudioWorkletNode;
  class CheckAudioContext extends OrigAC {
    constructor(...a) {
      super(...a);
      A.onContext(this);
    }
  }
  window.AudioContext = CheckAudioContext;
  if (window.webkitAudioContext) window.webkitAudioContext = CheckAudioContext;
  A.onContext = (ctx) => {
    A.ctxs.push(ctx);
    const tap = ctx.createGain();
    tap.channelCount = 2;
    tap.channelCountMode = 'explicit';
    ctx.__tap = tap;
    const url = URL.createObjectURL(new Blob([RECORDER], { type: 'application/javascript' }));
    ctx.audioWorklet.addModule(url).then(() => {
      const node = new OrigAWN(ctx, 'check-recorder', { numberOfInputs: 1, numberOfOutputs: 0, channelCount: 2, channelCountMode: 'explicit' });
      tap.connect(node);
      node.port.onmessage = (e) => {
        if (e.data.kind === 'stats') A.rec.stats = e.data.res;
        if (e.data.kind === 'first_sound') A.firstSound = { t: e.data.t, peak: e.data.peak };
      };
      ctx.__rec = node;
      A.log.push({ ev: 'recorder_ready', t: now() });
    }).catch((e) => A.log.push({ ev: 'recorder_failed', err: String(e) }));
    A.log.push({ ev: 'context', rate: ctx.sampleRate, state: ctx.state, t: now() });
    ctx.addEventListener('statechange', () => A.log.push({ ev: 'state', state: ctx.state, t: now() }));
  };
  const origConnect = AudioNode.prototype.connect;
  AudioNode.prototype.connect = function (dest, ...rest) {
    const r = origConnect.call(this, dest, ...rest);
    try {
      if (dest instanceof AudioDestinationNode && this.context.__tap) origConnect.call(this, this.context.__tap);
    } catch (e) { /* not ours to watch */ }
    return r;
  };
  // The buffer tracker.
  const bytesOf = new WeakMap();
  const attached = new WeakSet();
  const update = () => {
    A.liveBytes = A.registeredBytes + A.playingBytes;
    if (A.liveBytes > A.peakLiveBytes) A.peakLiveBytes = A.liveBytes;
    if (A.playingBytes > A.peakPlayingBytes) A.peakPlayingBytes = A.playingBytes;
  };
  const origCreateBuffer = BaseAudioContext.prototype.createBuffer;
  BaseAudioContext.prototype.createBuffer = function (channels, length, rate) {
    const b = origCreateBuffer.call(this, channels, length, rate);
    const bytes = channels * length * 4;
    bytesOf.set(b, bytes);
    A.buffersCreated++;
    A.registeredBytes += bytes;
    update();
    return b;
  };
  const origStart = AudioBufferSourceNode.prototype.start;
  AudioBufferSourceNode.prototype.start = function (...a) {
    const b = this.buffer;
    const bytes = b ? bytesOf.get(b) : undefined;
    A.sourcesStarted++;
    if (bytes !== undefined) {
      if (!attached.has(b)) {
        attached.add(b);
        A.buffersAttached++;
        A.registeredBytes -= bytes;   // a copy made for this source: it counts while the source plays
      }
      A.playingBytes += bytes;
      update();
      let done = false;
      this.addEventListener('ended', () => {
        if (done) return;
        done = true;
        A.playingBytes -= bytes;
        update();
      });
    }
    return origStart.apply(this, a);
  };
  // The music director's AUDIO_MUSIC lines, timed on the page and on the audio clock.
  const origLog = console.log.bind(console);
  console.log = (...items) => {
    const text = items.map(String).join(' ');
    if (text.startsWith('AUDIO_MUSIC ')) {
      let data = {};
      try { data = JSON.parse(text.slice('AUDIO_MUSIC '.length)); } catch (e) { data = { unreadable: text }; }
      const ctx = A.ctxs[A.ctxs.length - 1];
      A.marks.push({ ...data, page_ms: now(), ctx_t: ctx ? ctx.currentTime : null, ctx_state: ctx ? ctx.state : null });
    }
    origLog(...items);
  };
  A.ctx = () => A.ctxs[A.ctxs.length - 1];
  A.post = (msg) => { const c = A.ctx(); if (c && c.__rec) { c.__rec.port.postMessage(msg); return true; } return false; };
}

const sleep = (ms) => new Promise((ok) => setTimeout(ok, ms));

async function main() {
  const opts = parseArgs(process.argv.slice(2));
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
  page.on('console', (msg) => {
    const text = msg.text();
    if (msg.type() === 'error') errors.push(text);
    if (text.startsWith('AUDIO_MUSIC ')) musicLines.push(text);
  });
  page.on('pageerror', (err) => errors.push(`page error: ${err.message}`));
  page.on('requestfailed', (req) => {
    const why = req.failure() ? req.failure().errorText : 'failed';
    if (why !== 'net::ERR_ABORTED') failedRequests.push(`${req.url()} (${why})`);
  });
  page.on('response', (res) => { if (res.status() >= 400) failedRequests.push(`${res.url()} (${res.status()})`); });

  const started = Date.now();
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
    await page.evaluate(() => window.__audioCheck.post({ cmd: 'arm' }));
    const t0 = await page.evaluate(() => performance.now());
    await sleep(opts.musicS * 1000);
    await page.evaluate(() => window.__audioCheck.post({ cmd: 'disarm' }));
    await sleep(500);
    const state = await page.evaluate(() => {
      const A = window.__audioCheck;
      const c = A.ctx();
      return {
        stats: A.rec.stats || null, peakLiveBytes: A.peakLiveBytes, liveBytes: A.liveBytes, registeredBytes: A.registeredBytes,
        peakPlayingBytes: A.peakPlayingBytes, buffersCreated: A.buffersCreated, buffersAttached: A.buffersAttached,
        sourcesStarted: A.sourcesStarted, contexts: A.ctxs.length, log: A.log.slice(0, 20), marks: A.marks,
        ctx: c ? { state: c.state, rate: c.sampleRate, base_latency: c.baseLatency } : null,
        wall_ms: performance.now(),
      };
    });
    const s = state.stats;
    if (!s) {
      problems.push('the recorder reported nothing');
    } else {
      const quantumMs = 128 / s.sample_rate * 1000;
      report.music = {
        seconds: Math.round((s.end_t - s.start_t) * 10) / 10, wall_s: Math.round((state.wall_ms - t0) / 100) / 10,
        quanta: s.quanta, silent_quanta: s.silent, longest_silence_ms: Math.round(s.longest * quantumMs * 10) / 10,
        silent_runs_over_50_ms: s.runs_over + (s.run * quantumMs > HOLE_MAX_MS ? 1 : 0), peak: Math.round(s.peak * 1000) / 1000,
      };
      if (report.music.longest_silence_ms > HOLE_MAX_MS) problems.push(`a ${report.music.longest_silence_ms} ms hole in the music`);
      if (report.music.seconds < opts.musicS * 0.9) problems.push(`the audio clock ran ${report.music.seconds} s of ${opts.musicS} s`);
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
  }
  report.wall_s = Math.round((Date.now() - started) / 100) / 10;
  await browser.close();
  server.close();
  report.console_errors = errors;
  report.failed_requests = failedRequests;
  report.external_requests_answered_empty = external.length;
  if (errors.length > 0) problems.push(`${errors.length} console error(s)`);
  if (failedRequests.length > 0) problems.push(`${failedRequests.length} failed request(s)`);
  report.problems = problems;
  report.ok = problems.length === 0;
  if (opts.json) writeFileSync(opts.json, JSON.stringify(report, null, 2) + '\n');
  const m = report.music || {};
  const mbs = (b) => (typeof b === 'number' ? (b / 1048576).toFixed(1) : 'N/A');
  console.log(`audio_check: ${report.parts} pck part(s); the Hollow plays ${report.hollow_set || '?'}; sound ${report.sound_after_hollow_s} s after it; context ${report.context ? report.context.state : '?'} at ${report.context ? report.context.rate : '?'} Hz`);
  console.log(`  music for ${m.seconds} s: longest silence ${m.longest_silence_ms} ms (limit ${HOLE_MAX_MS}), runs over 50 ms ${m.silent_runs_over_50_ms}, peak ${m.peak}`);
  console.log(`  samples: peak live ${mbs(report.samples && report.samples.peak_live_bytes)} MB (cap ${mbs(capBytes)} MB = ${registeredS} s x 353 KB + 12 MB), copies playing at most ${mbs(report.samples && report.samples.peak_playing_copy_bytes)} MB`);
  console.log(`  console errors ${errors.length}, failed requests ${failedRequests.length}, external requests answered empty ${external.length}, wall ${report.wall_s} s`);
  for (const e of errors.slice(0, 10)) console.log(`    error: ${e}`);
  for (const r of failedRequests.slice(0, 10)) console.log(`    request: ${r}`);
  console.log(`AUDIO_CHECK ${JSON.stringify(report)}`);
  console.log(report.ok ? 'audio_check: OK' : `audio_check: FAILED - ${problems.join('; ')}`);
  process.exit(report.ok ? 0 : 1);
}

main().catch((e) => {
  console.error(`audio_check: ${e && e.stack ? e.stack : e}`);
  process.exit(1);
});
