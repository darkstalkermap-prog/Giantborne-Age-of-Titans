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
import { existsSync, readdirSync, readFileSync, statSync, writeFileSync } from 'node:fs';
import { extname, join, normalize, resolve, sep } from 'node:path';

const TITLE = 'Giantborn: Age of Titans';
const SOUND_WITHIN_S = 5;
const HOLE_MAX_MS = 50;
const BYTES_PER_REGISTERED_S = 353000;
const LIVE_HEADROOM_BYTES = 12000000;
const VALLEY = 'level.valley';
const SILENCE_PEAK = 1e-4;
// A hole's place on the page's clock may be off by this much (the audio clock's mapping to it, the
// output latency, the chunk's way back to the worklet).
const PLACE_TOLERANCE_MS = 35;
// Holes this close together are one stall of the mixer (a sample voice sounded between them).
const MERGE_GAP_MS = 12;

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

// The no-threads driver's stream buffer: output_latency.web (project.godot; the engine's 50 without
// it) in frames at the context's rate, to the closest power of two, as AudioDriverWeb sizes it.
function streamBufferMs(rate) {
  let latency = 50;
  try {
    const m = readFileSync('project.godot', 'utf8').match(/^driver\/output_latency\.web=(\d+)/m);
    if (m) latency = Number(m[1]);
  } catch (e) {
    /* the engine's default */
  }
  const x = latency * rate / 1000;
  const lo = 2 ** Math.floor(Math.log2(x));
  const hi = 2 ** Math.ceil(Math.log2(x));
  return (hi - x > x - lo ? lo : hi) / rate * 1000;
}

const round1 = (x) => (typeof x === 'number' ? Math.round(x * 10) / 10 : null);

// The page frames (the intervals of the frame clock): p50, p95, the longest, how many outlast the
// stream buffer.
function frameStats(times, bufferMs) {
  const d = [];
  for (let i = 1; i < times.length; i++) d.push(times[i] - times[i - 1]);
  const sorted = d.slice().sort((a, b) => a - b);
  const pick = (q) => (sorted.length ? sorted[Math.min(sorted.length - 1, Math.floor(q * sorted.length))] : null);
  return {
    n: d.length, p50_ms: round1(pick(0.5)), p95_ms: round1(pick(0.95)), max_ms: round1(pick(1)),
    over_buffer: d.filter((x) => x > bufferMs).length, buffer_ms: round1(bufferMs),
  };
}

// The main thread's long tasks within [from, to] on the page's clock: how many, p50, the longest,
// the share of the time they took.
function taskStats(tasks, from, to) {
  const d = tasks.filter(([t]) => t >= from && t <= to).map(([, ms]) => ms).sort((a, b) => a - b);
  const busy = d.reduce((a, b) => a + b, 0);
  return {
    n: d.length, p50_ms: round1(d.length ? d[Math.floor(d.length / 2)] : null), max_ms: round1(d.length ? d[d.length - 1] : null),
    busy_share: to > from ? Math.round(busy / (to - from) * 1000) / 1000 : null,
  };
}

// Every hole on the page's clock (the audio clock mapped linearly between the references taken at
// arm and disarm) against the times the main thread handled the driver's "read" messages. A hole
// with no "read" handled inside it (beyond PLACE_TOLERANCE_MS of its ends) and one handled within
// PLACE_TOLERANCE_MS of its end is the main thread's: the worklet ran dry while the main thread
// could not mix, and the first message it handled refilled it. A hole that no "read" ended is
// placed with the holes that follow it within MERGE_GAP_MS (one stall, broken by a moment of a
// sample voice, which Web Audio plays without the mixer). The rest are listed.
function placeHoles(holes, service, armRef, disarmRef, quantumMs) {
  const out = { holes: holes.length, while_unserved: 0, elsewhere: [] };
  const list = (p, ms) => { if (out.elsewhere.length < 50) out.elsewhere.push({ page_s: round1(p), ms: round1(ms) }); };
  if (!armRef || service.length === 0) {
    for (const [t, q] of holes) list(armRef ? (t - armRef.ctx_t) : t, q * quantumMs);
    return out;
  }
  const scale = disarmRef && disarmRef.ctx_t > armRef.ctx_t
    ? (disarmRef.page_ms - armRef.page_ms) / ((disarmRef.ctx_t - armRef.ctx_t) * 1000) : 1;
  const toPage = (t) => armRef.page_ms + (t - armRef.ctx_t) * 1000 * scale;
  // The first index of service at or after x (service is in time order).
  const from = (x) => {
    let lo = 0;
    let hi = service.length;
    while (lo < hi) {
      const mid = (lo + hi) >> 1;
      if (service[mid] < x) lo = mid + 1;
      else hi = mid;
    }
    return lo;
  };
  const unserved = (p0, p1) => {
    const k = from(p0 + PLACE_TOLERANCE_MS);
    const servedInside = k < service.length && service[k] < p1 - PLACE_TOLERANCE_MS;
    const next = from(p1 - PLACE_TOLERANCE_MS);
    return !servedInside && next < service.length && service[next] <= p1 + PLACE_TOLERANCE_MS;
  };
  const spans = holes.map(([t, quanta]) => {
    const p0 = toPage(t);
    return [p0, p0 + quanta * quantumMs];
  });
  let i = 0;
  while (i < spans.length) {
    const [p0, p1] = spans[i];
    let j = i;
    let ok = unserved(p0, p1);
    // A hole that no "read" ended may be one stall with the holes just after it.
    while (!ok && j + 1 < spans.length && spans[j + 1][0] - spans[j][1] <= MERGE_GAP_MS) {
      j++;
      ok = unserved(p0, spans[j][1]);
    }
    if (ok) {
      out.while_unserved += j - i + 1;
      i = j + 1;
    } else {
      list((p0 - armRef.page_ms) / 1000, p1 - p0);
      i++;
    }
  }
  return out;
}

// The gaps in the main thread's service of the driver (between two handled "read" messages): the
// longest, and how many outlast the stream buffer.
function serviceStats(service, bufferMs) {
  let longest = 0;
  let over = 0;
  for (let i = 1; i < service.length; i++) {
    const g = service[i] - service[i - 1];
    if (g > longest) longest = g;
    if (g > bufferMs) over++;
  }
  return { reads: service.length, longest_gap_ms: round1(longest), gaps_over_buffer: over };
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
      if (m.cmd === 'arm') {
        this.armed = { quanta: 0, silent: 0, run: 0, run_t: 0, longest: 0, runs_over: 0, peak: 0, start_t: currentTime, holes: [] };
      }
      if (m.cmd === 'first_sound_after') this.waitFrom = m.t;
      if (m.cmd === 'disarm') {
        const a = this.armed;
        this.armed = null;
        if (a) {
          a.end_t = currentTime;
          a.sample_rate = sampleRate;
          if (a.run * 128 / sampleRate * 1000 > ${holeMs} && a.holes.length < 4000) a.holes.push([a.run_t, a.run]);
        }
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
        if (a.run === 0) a.run_t = currentTime;
        a.silent++;
        a.run++;
        if (a.run > a.longest) a.longest = a.run;
      } else {
        if (a.run * 128 / sampleRate * 1000 > ${holeMs}) {
          a.runs_over++;
          if (a.holes.length < 4000) a.holes.push([a.run_t, a.run]);
        }
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
  // The driver's worklet (the no-threads build's mixer): every "read" the main thread handles is
  // logged while the recorder is armed (its port's onmessage, set by the engine, is wrapped).
  A.service = [];
  A.driverWatched = false;
  const onmessage = Object.getOwnPropertyDescriptor(MessagePort.prototype, 'onmessage');
  A.watchDriver = (node) => {
    const port = node.port;
    Object.defineProperty(port, 'onmessage', {
      configurable: true,
      get() { return onmessage.get.call(port); },
      set(fn) {
        onmessage.set.call(port, typeof fn !== 'function' ? fn : function (ev) {
          if (A.frameClock && ev && ev.data && ev.data.cmd === 'read' && A.service.length < 400000) A.service.push(now());
          return fn.call(this, ev);
        });
      },
    });
    A.driverWatched = true;
  };
  class CheckWorkletNode extends OrigAWN {
    constructor(ctx, name, ...rest) {
      super(ctx, name, ...rest);
      if (name === 'godot-processor') A.watchDriver(this);
    }
  }
  window.AudioWorkletNode = CheckWorkletNode;
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
  // The page's frame clock: the time of every requestAnimationFrame while the recorder is armed (the
  // engine's main loop is a requestAnimationFrame callback too: an interval is one engine frame).
  A.frames = [];
  A.frameClock = false;
  const tick = (t) => {
    if (A.frameClock && A.frames.length < 100000) A.frames.push(t);
    requestAnimationFrame(tick);
  };
  requestAnimationFrame(tick);
  // The main thread's long tasks (over 50 ms) while the recorder is armed.
  A.tasks = [];
  try {
    new PerformanceObserver((list) => {
      if (!A.frameClock) return;
      for (const e of list.getEntries()) if (A.tasks.length < 100000) A.tasks.push([e.startTime, e.duration]);
    }).observe({ type: 'longtask' });
  } catch (e) {
    A.log.push({ ev: 'no_longtask', err: String(e) });
  }
  // Where the audio clock was on the page's clock (both read in one task).
  A.clockRef = () => { const c = A.ctx(); return c ? { page_ms: now(), ctx_t: c.currentTime } : null; };
  A.arm = () => {
    A.frames = [];
    A.tasks = [];
    A.service = [];
    A.frameClock = true;
    A.armRef = A.clockRef();
    return A.post({ cmd: 'arm' });
  };
  A.disarm = () => {
    A.disarmRef = A.clockRef();
    return A.post({ cmd: 'disarm' });
  };
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
    const state = await page.evaluate(() => {
      const A = window.__audioCheck;
      A.frameClock = false;   // half a second past the disarm: the last hole's frame has ended
      const c = A.ctx();
      return {
        stats: A.rec.stats || null, peakLiveBytes: A.peakLiveBytes, liveBytes: A.liveBytes, registeredBytes: A.registeredBytes,
        peakPlayingBytes: A.peakPlayingBytes, buffersCreated: A.buffersCreated, buffersAttached: A.buffersAttached,
        sourcesStarted: A.sourcesStarted, contexts: A.ctxs.length, log: A.log.slice(0, 20), marks: A.marks,
        ctx: c ? { state: c.state, rate: c.sampleRate, base_latency: c.baseLatency } : null,
        wall_ms: performance.now(), frames: A.frames.slice(), tasks: A.tasks.slice(), service: A.service.slice(),
        driverWatched: A.driverWatched, armRef: A.armRef || null, disarmRef: A.disarmRef || null,
      };
    });
    const s = state.stats;
    if (!s) {
      problems.push('the recorder reported nothing');
    } else {
      const quantumMs = 128 / s.sample_rate * 1000;
      const bufferMs = streamBufferMs(s.sample_rate);
      const placed = placeHoles(s.holes || [], state.service, state.armRef, state.disarmRef, quantumMs);
      report.music = {
        seconds: Math.round((s.end_t - s.start_t) * 10) / 10, wall_s: Math.round((state.wall_ms - t0) / 100) / 10,
        quanta: s.quanta, silent_quanta: s.silent, longest_silence_ms: Math.round(s.longest * quantumMs * 10) / 10,
        silent_runs_over_50_ms: s.runs_over + (s.run * quantumMs > HOLE_MAX_MS ? 1 : 0), peak: Math.round(s.peak * 1000) / 1000,
        holes_while_unserved: placed.while_unserved, holes_elsewhere: placed.elsewhere,
      };
      const until = state.disarmRef ? state.disarmRef.page_ms : state.wall_ms;
      report.page_frames = frameStats(state.frames.filter((t) => t <= until), bufferMs);
      report.long_tasks = taskStats(state.tasks, state.armRef ? state.armRef.page_ms : t0, until);
      report.driver = { watched: state.driverWatched, ...serviceStats(state.service.filter((x) => x <= until), bufferMs) };
      trace = {
        arm: state.armRef, disarm: state.disarmRef, quantum_ms: quantumMs, frames: state.frames, tasks: state.tasks,
        service: state.service, holes: s.holes || [],
      };
      report.strict = opts.strict;
      if (report.music.longest_silence_ms > HOLE_MAX_MS) {
        if (opts.strict) problems.push(`a ${report.music.longest_silence_ms} ms hole in the music`);
        if (placed.elsewhere.length > 0) {
          problems.push(`${placed.elsewhere.length} hole(s) over ${HOLE_MAX_MS} ms not explained by the main thread leaving the mixer unserved (the first ${placed.elsewhere[0].ms} ms at ${placed.elsewhere[0].page_s} s)`);
        }
      }
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
  if (opts.json) writeFileSync(opts.json, JSON.stringify({ ...report, trace }, null, 2) + '\n');
  const m = report.music || {};
  const mbs = (b) => (typeof b === 'number' ? (b / 1048576).toFixed(1) : 'N/A');
  console.log(`audio_check: ${report.parts} pck part(s); the Hollow plays ${report.hollow_set || '?'}; sound ${report.sound_after_hollow_s} s after it; context ${report.context ? report.context.state : '?'} at ${report.context ? report.context.rate : '?'} Hz`);
  console.log(`  music for ${m.seconds} s: longest silence ${m.longest_silence_ms} ms (limit ${HOLE_MAX_MS}), runs over 50 ms ${m.silent_runs_over_50_ms} (${m.holes_while_unserved} while the main thread left the mixer unserved, ${(m.holes_elsewhere || []).length} otherwise${report.strict ? '' : '; --strict fails every one'}), peak ${m.peak}`);
  const pf = report.page_frames || {};
  const lt = report.long_tasks || {};
  const dv = report.driver || {};
  console.log(`  main thread: ${lt.n} long tasks (p50 ${lt.p50_ms} ms, longest ${lt.max_ms} ms, ${typeof lt.busy_share === 'number' ? Math.round(lt.busy_share * 100) : '?'} % of the time); page frames: ${pf.n}, p50 ${pf.p50_ms} ms, p95 ${pf.p95_ms} ms, longest ${pf.max_ms} ms; the driver's reads ${dv.watched ? `${dv.reads}, longest gap ${dv.longest_gap_ms} ms, ${dv.gaps_over_buffer} gaps over the ${pf.buffer_ms} ms stream buffer` : 'not seen'}`);
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
