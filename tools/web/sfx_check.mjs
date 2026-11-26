#!/usr/bin/env node
// The Web sound-effects check (C3): does a swing and a hit make sound in the browser, and how loud is it
// against the music? The Web release in headless Chromium with its sound on, the sandbox driven by the
// seeded autopilot (--mode=sandbox --autoplay=S: the giant walks up to the sandbox's enemies and swings),
// the game printing one AUDIO_CUE line per cue it starts (--audio-trace: the cue, its reason, its bus, the
// distance from the listener and the level the 3D model gives it there).
//
// The page instrument (injected before the engine's scripts):
//   * every AudioContext the engine makes gets a tap on its destination and a recorder worklet on the tap:
//     per 128-frame quantum the audio clock, the sum of squares and the peak of the output;
//   * every AudioBufferSourceNode started (on the web the engine plays every effect as a Web Audio sample:
//     one buffer source per play) is logged on the audio clock with its buffer's length, and the six gains
//     of the engine's per-bus sample node (its left and right among them) are followed, so a sample started
//     at gain zero (a 3D voice the engine never pans) shows as such;
//   * every AUDIO_CUE line is stamped with the audio clock when it is printed.
// The analysis matches the effects' cue lines (bus SFX or UI) to the buffer sources started after them in
// order, and measures the output over each source's first 0.3 s (RMS and peak, dBFS) against the quiet just
// before it. With --mute=Music:Ambience the game mutes those buses (--audio-mute=), so the output is the
// effects alone; without it the music's own level is reported (the RMS over the run's quantum windows that
// hold no effect) beside them.
//
// It prints one SFX_CHECK {json} line and exits 0 when at least --min-swings swings and --min-hits hits each
// sounded (a window at least --min-gain-db over the quiet before it and over SILENT_DBFS), 1 otherwise, 2 for
// a usage error. Its own test: node tools/web/test_sfx_check.mjs (the analysis on made-up recordings).
//
// Usage (from the project folder, after tools/build_web.sh):
//   node tools/web/sfx_check.mjs [--build=builds/web] [--seconds=45] [--mute=Music:Ambience] [--args=a,b]
//        [--min-swings=3] [--min-hits=3] [--min-gain-db=6] [--timeout-s=420] [--json=FILE] [--size=640x360]
// Needs Playwright (PLAYWRIGHT_MODULE, NODE_PATH or /opt/node-tools/node_modules) and its Chromium
// (PLAYWRIGHT_BROWSERS_PATH, default /opt/pw-browsers when that folder exists).

import { startMemoryGuard } from './memory_guard.mjs';
import { createServer } from 'node:http';
import { createRequire } from 'node:module';
import { existsSync, readFileSync, statSync, writeFileSync } from 'node:fs';
import { extname, join, normalize, resolve, sep } from 'node:path';
import { fileURLToPath } from 'node:url';

export const WINDOW_S = 0.3;
export const PRE_S = 0.25;
export const SILENT_DBFS = -70;
const TITLE = 'Giantborn: Age of Titans';

export function parseArgs(argv) {
  const opts = {
    build: 'builds/web', seconds: 45, mute: '', args: '', minSwings: 3, minHits: 3, minGainDb: 6, timeoutS: 420,
    json: '', size: '640x360', engineLog: false,
  };
  for (const arg of argv) {
    const [key, ...rest] = arg.split('=');
    const value = rest.join('=');
    switch (key) {
      case '--build': opts.build = value; break;
      case '--seconds': opts.seconds = Number(value); break;
      case '--mute': opts.mute = value; break;
      case '--args': opts.args = value; break;
      case '--min-swings': opts.minSwings = Number(value); break;
      case '--min-hits': opts.minHits = Number(value); break;
      case '--min-gain-db': opts.minGainDb = Number(value); break;
      case '--timeout-s': opts.timeoutS = Number(value); break;
      case '--json': opts.json = value; break;
      case '--size': opts.size = value; break;
      case '--engine-log': opts.engineLog = true; break;
      default:
        throw new Error(`unknown option ${arg}`);
    }
  }
  return opts;
}

// The page instrument (runs in the page before the engine).
function instrument() {
  const S = (window.__sfx = { ctx: null, quanta: [], cues: [], sources: [], gains: [], log: [] });
  const REC = `
class SfxRecorder extends AudioWorkletProcessor {
  constructor() { super(); this.buf = []; }
  process(inputs) {
    const inp = inputs[0];
    let ss = 0, peak = 0, n = 0;
    for (const ch of inp) for (let i = 0; i < ch.length; i++) { const v = ch[i]; ss += v * v; n++; const a = Math.abs(v); if (a > peak) peak = a; }
    this.buf.push(currentTime, n ? ss / n : 0, peak);
    if (this.buf.length >= 96) { this.port.postMessage(this.buf); this.buf = []; }
    return true;
  }
}
registerProcessor('sfx-recorder', SfxRecorder);`;
  const OrigAC = window.AudioContext || window.webkitAudioContext;
  const OrigAWN = window.AudioWorkletNode;
  class SfxAudioContext extends OrigAC {
    constructor(...a) {
      super(...a);
      S.ctx = this;
      const tap = this.createGain();
      tap.channelCount = 2;
      tap.channelCountMode = 'explicit';
      this.__tap = tap;
      const url = URL.createObjectURL(new Blob([REC], { type: 'application/javascript' }));
      this.audioWorklet.addModule(url).then(() => {
        const node = new OrigAWN(this, 'sfx-recorder', { numberOfInputs: 1, numberOfOutputs: 0, channelCount: 2, channelCountMode: 'explicit' });
        tap.connect(node);
        node.port.onmessage = (e) => { const b = e.data; for (let i = 0; i < b.length; i += 3) S.quanta.push([b[i], b[i + 1], b[i + 2]]); };
        S.log.push('recorder ready');
      }).catch((e) => S.log.push(`recorder failed ${e}`));
    }
  }
  window.AudioContext = SfxAudioContext;
  if (window.webkitAudioContext) window.webkitAudioContext = SfxAudioContext;
  const origConnect = AudioNode.prototype.connect;
  AudioNode.prototype.connect = function (dest, ...rest) {
    const r = origConnect.call(this, dest, ...rest);
    try {
      if (dest instanceof AudioDestinationNode && this.context.__tap) origConnect.call(this, this.context.__tap);
      if (this instanceof AudioBufferSourceNode && dest && dest.__snb) this.__snb = dest.__snb;
    } catch (e) { /* not ours */ }
    return r;
  };
  // The engine's per-bus sample node: a six-way splitter, then six gains (L, R, SL, SR, C, LFE).
  let pendingGains = null;
  const origSplitter = BaseAudioContext.prototype.createChannelSplitter;
  BaseAudioContext.prototype.createChannelSplitter = function (n, ...rest) {
    const node = origSplitter.call(this, n, ...rest);
    if (n === 6) {
      node.__snb = { id: S.gains.length, g: [] };
      S.gains.push(node.__snb);
      pendingGains = node.__snb;
    }
    return node;
  };
  const origGain = BaseAudioContext.prototype.createGain;
  BaseAudioContext.prototype.createGain = function (...a) {
    const g = origGain.apply(this, a);
    if (pendingGains && pendingGains.g.length < 6) {
      pendingGains.g.push(g.gain);
      if (pendingGains.g.length === 6) pendingGains = null;
    }
    return g;
  };
  const origStart = AudioBufferSourceNode.prototype.start;
  AudioBufferSourceNode.prototype.start = function (...a) {
    const ctx = this.context;
    const rec = { t: ctx.currentTime, dur: this.buffer ? this.buffer.duration : 0, len: this.buffer ? this.buffer.length : 0, rate: this.playbackRate.value };
    const snb = this.__snb;
    const read = () => (snb ? [snb.g[0] ? snb.g[0].value : null, snb.g[1] ? snb.g[1].value : null] : null);
    rec.gain0 = read();
    setTimeout(() => { rec.gain80 = read(); }, 80);
    S.sources.push(rec);
    return origStart.apply(this, a);
  };
  const origLog = console.log.bind(console);
  console.log = (...items) => {
    const text = items.map(String).join(' ');
    if (text.startsWith('AUDIO_CUE ')) {
      try { S.cues.push({ ...JSON.parse(text.slice(10)), ctx_t: S.ctx ? S.ctx.currentTime : null }); } catch (e) { /* skip */ }
    }
    origLog(...items);
  };
}

const dbfs = (x) => (x > 0 ? Math.round(10 * Math.log10(x) * 10) / 10 : -200);
const dbPeak = (x) => (x > 0 ? Math.round(20 * Math.log10(x) * 10) / 10 : -200);

// The output's level over [t0, t1): {rms_db, peak_db} from the quanta [t, mean square, peak].
export function levelOver(quanta, t0, t1) {
  let ss = 0, n = 0, peak = 0;
  for (const [t, ms, pk] of quanta) {
    if (t < t0 || t >= t1) continue;
    ss += ms;
    n++;
    if (pk > peak) peak = pk;
  }
  return { rms_db: n ? dbfs(ss / n) : -200, peak_db: dbPeak(peak), quanta: n };
}

// The kind of an effect cue: "swing", "hit" (an impact on a body, a plate, a prop or a guard), "step",
// "other".
export function cueKind(cue) {
  const id = String(cue.cue || '');
  const reason = String(cue.reason || '');
  if (reason === 'swing' || id.startsWith('sfx.swing.')) return 'swing';
  if (reason.startsWith('hit') || reason === 'block' || reason === 'crit' || id.startsWith('sfx.hit.')) return 'hit';
  if (reason === 'step' || id.startsWith('sfx.step.')) return 'step';
  return 'other';
}

// Matches the effect cues to the sources started after them, in order, and measures each.
export function analyse(state, opts) {
  const fx = state.cues.filter((c) => c.bus === 'SFX' || c.bus === 'UI');
  const sources = state.sources.slice().sort((a, b) => a.t - b.t);
  const rows = [];
  let j = 0;
  for (const c of fx) {
    while (j < sources.length && sources[j].t < c.ctx_t - 0.002) j++;
    const s = j < sources.length ? sources[j] : null;
    if (s) j++;
    const at = s ? s.t : c.ctx_t;
    const win = levelOver(state.quanta, at, at + WINDOW_S);
    const pre = levelOver(state.quanta, at - PRE_S, at);
    rows.push({
      cue: c.cue, kind: cueKind(c), reason: c.reason, bus: c.bus, dist_m: c.dist_m, level_db: c.level_db, pitch: c.pitch,
      started: s !== null, start_delay_ms: s ? Math.round((s.t - c.ctx_t) * 1000) : null, source_s: s ? Math.round(s.dur * 1000) / 1000 : null,
      gain_lr: s ? s.gain0 : null, gain_lr_80ms: s ? s.gain80 : null,
      rms_db: win.rms_db, peak_db: win.peak_db, pre_rms_db: pre.rms_db, gain_db: Math.round((win.rms_db - pre.rms_db) * 10) / 10,
    });
  }
  // With the music and the ambience muted the output is the effects alone: a cue sounded when its source
  // started with a gain above zero and the output over its window is above SILENT_DBFS. With them playing,
  // it must also stand --min-gain-db over the quiet before it.
  const gainUp = (r) => !Array.isArray(r.gain_lr_80ms) || Math.max(...r.gain_lr_80ms.map((g) => g || 0)) > 0;
  const sounded = (r) => r.started && gainUp(r) && r.rms_db > SILENT_DBFS
    && (opts.mute ? true : (r.gain_db >= opts.minGainDb || r.pre_rms_db <= SILENT_DBFS));
  const by = (k) => rows.filter((r) => r.kind === k);
  const summary = {};
  for (const k of ['swing', 'hit', 'step', 'other']) {
    const list = by(k);
    const heard = list.filter(sounded);
    const med = (xs) => { const v = xs.slice().sort((a, b) => a - b); return v.length ? v[Math.floor(v.length / 2)] : null; };
    summary[k] = {
      cues: list.length, sounded: heard.length, never_started: list.filter((r) => !r.started).length,
      median_rms_db: med(list.map((r) => r.rms_db)), median_peak_db: med(list.map((r) => r.peak_db)),
      median_model_level_db: med(list.map((r) => r.level_db)),
      zero_gain_at_start: list.filter((r) => Array.isArray(r.gain_lr) && r.gain_lr[0] === 0 && r.gain_lr[1] === 0).length,
    };
  }
  // The rest of the output: quanta not within any effect's window (the music and the ambience).
  const starts = sources.map((s) => [s.t, s.t + Math.max(s.dur, WINDOW_S)]);
  let ss = 0, n = 0;
  let k = 0;
  for (const [t, ms] of state.quanta) {
    while (k < starts.length && starts[k][1] < t) k++;
    let inside = false;
    for (let i = k; i < starts.length && starts[i][0] <= t; i++) if (t < starts[i][1]) { inside = true; break; }
    if (!inside) { ss += ms; n++; }
  }
  summary.bed = { rms_db: n ? dbfs(ss / n) : -200, quanta: n };
  summary.sources_started = sources.length;
  summary.fx_cues = fx.length;
  return { rows, summary };
}

function loadPlaywright() {
  const require = createRequire(import.meta.url);
  for (const name of [process.env.PLAYWRIGHT_MODULE, 'playwright', '/opt/node-tools/node_modules/playwright']) {
    if (!name) continue;
    try { return require(name); } catch (e) { /* the next */ }
  }
  throw new Error('Playwright not found');
}

const TYPES = {
  '.html': 'text/html; charset=utf-8', '.js': 'text/javascript', '.wasm': 'application/wasm',
  '.txt': 'text/plain; charset=utf-8', '.jpg': 'image/jpeg', '.png': 'image/png', '.pck': 'application/octet-stream',
};

function serve(root) {
  const base = resolve(root);
  const server = createServer((req, res) => {
    const path = decodeURIComponent(new URL(req.url, 'http://x').pathname);
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

const sleep = (ms) => new Promise((ok) => setTimeout(ok, ms));

async function main() {
  let opts;
  try {
    opts = parseArgs(process.argv.slice(2));
  } catch (e) {
    console.error(`sfx_check: ${e.message}`);
    process.exit(2);
  }
  if (!existsSync(join(opts.build, 'play.html'))) {
    console.error(`sfx_check: ${opts.build}/play.html is missing: run tools/build_web.sh first`);
    process.exit(1);
  }
  if (!process.env.PLAYWRIGHT_BROWSERS_PATH && existsSync('/opt/pw-browsers')) process.env.PLAYWRIGHT_BROWSERS_PATH = '/opt/pw-browsers';
  const { chromium } = loadPlaywright();
  const server = await serve(opts.build);
  const origin = `http://127.0.0.1:${server.address().port}`;
  const html = readFileSync(join(opts.build, 'play.html'), 'utf8');
  if (!html.includes(`<title>${TITLE}</title>`)) {
    server.close();
    console.error(`sfx_check: ${opts.build}/play.html is not ${TITLE}'s page`);
    process.exit(1);
  }
  const args = ['--mode=sandbox', `--autoplay=${opts.seconds}`, '--audio-trace', '--audio-stats'];
  if (opts.mute) args.push(`--audio-mute=${opts.mute}`);
  for (const a of opts.args.split(',').map((x) => x.trim()).filter(Boolean)) args.push(a);
  const url = `${origin}/play.html?args=${args.map(encodeURIComponent).join(',')}`;
  const [width, height] = opts.size.split('x').map(Number);
  const browser = await chromium.launch({ args: ['--use-angle=swiftshader', '--enable-unsafe-swiftshader', '--ignore-gpu-blocklist', '--autoplay-policy=no-user-gesture-required'] });
  const guard = startMemoryGuard('sfx_check');
  const page = await browser.newPage({ viewport: { width, height } });
  await page.addInitScript(instrument);
  await page.route((u) => !u.href.startsWith(origin), (route) => route.fulfill({ status: 200, body: '' }));
  // --engine-log (a diagnosis): the engine's loader is served with each call of its sample-bus and sample-start
  // bindings logged into window.__engineLog (the bus index, the volumes), the build on disk untouched.
  if (opts.engineLog) {
    await page.route(`${origin}/index.js`, (route) => {
      let js = readFileSync(join(opts.build, 'index.js'), 'utf8');
      js = js.replace(/function (_godot_audio_sample_(?:bus_\w+|start|set_volumes_linear))\(([^)]*)\)\{/g, (m, name, params) =>
        `${m}try{(window.__engineLog=window.__engineLog||[]).length<4000&&window.__engineLog.push([${JSON.stringify(name)},` +
        `${name.endsWith('start') ? 'busIndex,Array.from(GodotRuntime.heapSub(HEAPF32,volumePtr,8))' : name.endsWith('volumes_linear') ? 'Array.from(GodotRuntime.heapSub(HEAP32,busesPtr,busesSize)),Array.from(GodotRuntime.heapSub(HEAPF32,volumesPtr,volumesSize)).slice(0,8)' : 'Array.from(arguments)'}])}catch(e){}`);
      route.fulfill({ status: 200, contentType: 'text/javascript', body: js });
    });
  }
  const errors = [];
  let result = null;
  let stats = null;
  // Errors printed after the autopilot's result are the engine's exit-time reports (the web build's quit leaves
  // resources in use); they are counted apart and do not fail the check.
  const exitErrors = [];
  page.on('console', (m) => {
    const t = m.text();
    if (m.type() === 'error') {
      (result === null ? errors : exitErrors).push(t);
      if (result === null) console.log(`  console error: ${t.slice(0, 300)}`);
    }
    if (t.startsWith('AUTOPILOT_RESULT')) result = t;
    if (t.startsWith('AUDIO_STATS ')) stats = t.slice(12);
  });
  page.on('pageerror', (e) => errors.push(`page error: ${e.message}`));
  const started = Date.now();
  const problems = [];
  let state = null;
  try {
    console.log(`sfx_check: ${url}`);
    await page.goto(url, { waitUntil: 'load' });
    await page.click('#play');
    const deadline = started + opts.timeoutS * 1000;
    let lastCues = -1;
    let quiet = 0;
    while (Date.now() < deadline && result === null) {
      await sleep(2000);
      const n = await page.evaluate(() => window.__sfx.cues.length).catch(() => lastCues);
      quiet = n === lastCues ? quiet + 1 : 0;
      lastCues = n;
    }
    await sleep(1500);
    state = await page.evaluate(() => {
      const S = window.__sfx;
      return { engine_log: window.__engineLog || [], cues: S.cues, sources: S.sources, quanta: S.quanta, log: S.log, ctx_state: S.ctx ? S.ctx.state : null, rate: S.ctx ? S.ctx.sampleRate : null };
    });
    if (result === null) problems.push('the autopilot did not finish before the timeout');
  } catch (e) {
    problems.push(String(e && e.message ? e.message : e));
  }
  guard.stop();
  await browser.close();
  server.close();
  const report = { build: opts.build, args, wall_s: Math.round((Date.now() - started) / 100) / 10, console_errors: errors.length,
    exit_errors: exitErrors.length,
    renderer_peak_mb: guard.peakMb(), autopilot: result, audio_stats: stats };
  if (state) {
    const a = analyse(state, opts);
    report.ctx_state = state.ctx_state;
    report.rate = state.rate;
    report.quanta = state.quanta.length;
    report.summary = a.summary;
    if (opts.engineLog) report.engine_log = state.engine_log;
    report.rows = a.rows;
    if (a.summary.swing.sounded < opts.minSwings) problems.push(`${a.summary.swing.sounded} swing(s) sounded of ${a.summary.swing.cues} (want ${opts.minSwings})`);
    if (a.summary.hit.sounded < opts.minHits) problems.push(`${a.summary.hit.sounded} hit(s) sounded of ${a.summary.hit.cues} (want ${opts.minHits})`);
  }
  if (errors.length) problems.push(`${errors.length} console error(s)`);
  report.problems = problems;
  report.ok = problems.length === 0;
  if (opts.json) writeFileSync(opts.json, JSON.stringify(report, null, 2) + '\n');
  if (report.summary) {
    const s = report.summary;
    for (const k of ['swing', 'hit', 'step', 'other']) {
      const x = s[k];
      console.log(`  ${k}: ${x.cues} cue(s), ${x.sounded} sounded, ${x.never_started} never started, ${x.zero_gain_at_start} at zero gain; median output ${x.median_rms_db} dBFS RMS / ${x.median_peak_db} peak; the model's level ${x.median_model_level_db} dB`);
    }
    console.log(`  the rest of the output (music, ambience): ${s.bed.rms_db} dBFS RMS over ${s.bed.quanta} quanta; ${s.sources_started} sample sources for ${s.fx_cues} effect cues`);
  }
  console.log(`SFX_CHECK ${JSON.stringify({ ...report, rows: undefined })}`);
  console.log(report.ok ? 'sfx_check: OK' : `sfx_check: FAILED - ${problems.join('; ')}`);
  process.exit(report.ok ? 0 : 1);
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  main().catch((e) => {
    console.error(`sfx_check: ${e && e.stack ? e.stack : e}`);
    process.exit(1);
  });
}
