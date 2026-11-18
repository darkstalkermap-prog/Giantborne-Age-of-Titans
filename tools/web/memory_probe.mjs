#!/usr/bin/env node
// The page's memory while a level loads, with the browser starved (P49; plan M11 §3.2 item 7; the M10
// gate's finding LD-1: the Web build's page grows without bound when the browser is starved of CPU).
// A measuring tool, not a check: it plays the Web build in headless Chromium as creator_check.mjs does
// (Play, the title, Enter, the creator, Ctrl+Enter - or Enter on Continue with --continue), starves the
// browser one of two ways, and records once a second where the memory is:
//   * --throttle=N    the page's main thread slowed N times (the DevTools CPU throttle: the renderer's
//                     main thread only - the GPU process and the audio thread keep their speed);
//   * --pin-cpu=K     every process of the browser put on CPU K (taskset), with --busy=M busy loops beside
//                     them on that CPU: the whole browser starved, as the M10 gate reproduced the growth.
// Every second: the renderer's and the GPU process's resident memory (from /proc, as the checks' memory
// guard reads it), the JS heap (Performance.getMetrics), the WebAssembly memory's size and the counts the
// page's own instruments keep (below). At each --dumps=MB,MB threshold the renderer crosses, and at the
// end, a memory-infra dump (Tracing.requestMemoryDump) gives the renderer's memory by allocator - malloc,
// partition_alloc, v8, blink_gc, gpu, cc, skia, web audio, shared memory - so two dumps say WHICH
// allocator grew between them.
// The page's instruments (an init script; nothing in the game is touched):
//   raf_pending      requestAnimationFrame callbacks asked for and not yet run (a frame queue);
//   worklet_posts / worklet_handled   messages the audio worklet posted to the main thread and the main
//                    thread has handled (their difference: audio blocks waiting in the task queue);
//   chunks_posted    "chunk" messages (mixed audio) the main thread sent to the worklet, and their bytes;
//   gl_calls         WebGL draw calls issued, and bufferData / texImage bytes handed to the GPU process;
//   timers_pending   setTimeout callbacks not yet run.
// It stops at --seconds after Begin, or when the renderer passes --limit-mb (default 2200: the machine
// is shared), kills its own browser and prints MEMORY_PROBE {json}; --json=FILE keeps the samples and
// the dumps. Exit code 0 (2 for a usage error): the verdict is the reader's.
//
// Usage (from the project folder, after tools/build_web.sh):
//   node tools/web/memory_probe.mjs [--build=builds/web] [--throttle=N] [--pin-cpu=K] [--busy=M]
//        [--seconds=120] [--limit-mb=2200] [--dumps=1200,1800] [--args=a,b] [--continue] [--size=640x360]
//        [--timeout-s=600] [--json=FILE]
//   --args=a,b   more game arguments (--no-skin: the box giant; the browser's own --mute-audio is --mute)
//   --mute       start Chromium with --mute-audio (the audio device's sink is a null one)
//   --no-audio-context   the page's AudioContext constructor throws: the engine runs without its
//                    audio driver's worklet (it falls back to no sound) - the audio suspect removed
// Needs Playwright and its Chromium, as the checks do. Linux only (/proc, taskset).

import { spawn, spawnSync } from 'node:child_process';
import { existsSync, writeFileSync } from 'node:fs';
import { join, resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { loadPlaywright, serve } from './stream_check.mjs';
import { descendantsOf, isRenderer, killDescendants, largestRenderer, readProcessTable } from './memory_guard.mjs';
import { IDB_NAME, IDB_STORE, IDB_VERSION, SAVE_PATH, writeSaveInPage } from './world_check.mjs';
import { readFileSync } from 'node:fs';

const TOOL = 'memory_probe';
const ROOT = resolve(dirname(fileURLToPath(import.meta.url)), '..', '..');

function usage(message) {
  console.error(`${TOOL}: ${message}`);
  process.exit(2);
}

export function parseArgs(argv) {
  const opts = { build: 'builds/web', throttle: 1, pinCpu: -1, busy: 0, seconds: 120, limitMb: 2200, dumps: [1200, 1800],
    args: '', cont: false, size: '640x360', timeoutS: 600, json: '', mute: false, noAudioContext: false };
  for (const arg of argv) {
    const [key, ...rest] = arg.split('=');
    const value = rest.join('=');
    switch (key) {
      case '--build': opts.build = value; break;
      case '--throttle': opts.throttle = Number(value); break;
      case '--pin-cpu': opts.pinCpu = Number(value); break;
      case '--busy': opts.busy = Number(value); break;
      case '--seconds': opts.seconds = Number(value); break;
      case '--limit-mb': opts.limitMb = Number(value); break;
      case '--dumps': opts.dumps = value.split(',').filter((x) => x.length).map(Number); break;
      case '--args': opts.args = value; break;
      case '--continue': opts.cont = true; break;
      case '--size': opts.size = value; break;
      case '--timeout-s': opts.timeoutS = Number(value); break;
      case '--json': opts.json = value; break;
      case '--mute': opts.mute = true; break;
      case '--no-audio-context': opts.noAudioContext = true; break;
      default: usage(`unknown option ${arg}`);
    }
  }
  if (!(opts.throttle >= 1) || !(opts.seconds > 0) || !(opts.limitMb > 0) || opts.dumps.some((d) => !(d > 0)) || !/^\d+x\d+$/.test(opts.size)) {
    usage('--throttle wants 1 or more, --seconds and --limit-mb positive numbers, --dumps MB,MB, --size WxH');
  }
  return opts;
}

// A memory-infra dump's events -> { pid: { total_mb, allocators: { name: mb } } } (top-level allocators; a
// name's own size attribute where it has one, else the sum of its children's).
export function allocatorsByProcess(events) {
  const out = {};
  for (const e of events) {
    if (e.ph !== 'v' || !e.args || !e.args.dumps) continue;
    const dumps = e.args.dumps;
    const row = out[e.pid] || (out[e.pid] = { total_mb: 0, allocators: {} });
    if (dumps.process_totals && dumps.process_totals.resident_set_bytes) {
      row.total_mb = Math.round(parseInt(dumps.process_totals.resident_set_bytes, 16) / 1048576);
    }
    const sums = {};
    const own = {};
    for (const [name, node] of Object.entries(dumps.allocators || {})) {
      const size = node.attrs && node.attrs.size ? parseInt(node.attrs.size.value, 16) : 0;
      const parts = name.split('/');
      const top = parts[0];
      if (parts.length === 1) own[top] = size;
      // leaves only: a parent's size already holds its children's
      sums[top] = sums[top] || { leaves: 0, names: new Set() };
      sums[top].names.add(name);
      sums[top].sizes = sums[top].sizes || {};
      sums[top].sizes[name] = size;
    }
    for (const [top, s] of Object.entries(sums)) {
      let mb;
      if (own[top]) mb = own[top] / 1048576;
      else {
        // the second level's nodes (their sizes hold their own children's)
        let total = 0;
        for (const [name, size] of Object.entries(s.sizes)) if (name.split('/').length === 2) total += size;
        mb = total / 1048576;
      }
      if (mb >= 0.5) row.allocators[top] = Math.round(mb * 10) / 10;
    }
  }
  return out;
}

// Installed before the page's scripts: the page's own counts (see the header).
function instruments({ noAudioContext }) {
  const P = (window.__memProbe = { raf_asked: 0, raf_run: 0, worklet_posts: 0, worklet_handled: 0, chunks_posted: 0, chunk_bytes: 0,
    gl_draws: 0, gl_upload_bytes: 0, timers_asked: 0, timers_run: 0, wasm: null, frames: 0 });
  const raf = window.requestAnimationFrame.bind(window);
  window.requestAnimationFrame = (cb) => { P.raf_asked += 1; return raf((t) => { P.raf_run += 1; P.frames += 1; cb(t); }); };
  const st = window.setTimeout.bind(window);
  window.setTimeout = (cb, ms, ...rest) => { P.timers_asked += 1; return st((...a) => { P.timers_run += 1; if (typeof cb === 'function') cb(...a); }, ms, ...rest); };
  if (noAudioContext) {
    const Thrower = function () { throw new Error('memory_probe: no AudioContext in this run'); };
    window.AudioContext = Thrower;
    window.webkitAudioContext = Thrower;
  } else if (typeof AudioWorkletNode === 'function') {
    const Native = AudioWorkletNode;
    window.AudioWorkletNode = class extends Native {
      constructor(ctx, name, options) {
        super(ctx, name, options);
        const port = this.port;
        const post = port.postMessage.bind(port);
        port.postMessage = (msg, transfer) => {
          if (msg && msg.cmd === 'chunk') { P.chunks_posted += 1; P.chunk_bytes += (msg.data && msg.data.byteLength) || 0; }
          return post(msg, transfer);
        };
        let handler = null;
        Object.defineProperty(port, 'onmessage', {
          configurable: true,
          get: () => handler,
          set: (fn) => {
            handler = fn;
            Object.getOwnPropertyDescriptor(MessagePort.prototype, 'onmessage').set.call(port, (ev) => { P.worklet_handled += 1; if (fn) fn(ev); });
          },
        });
      }
    };
  }
  const wrapGl = (proto) => {
    if (!proto) return;
    for (const name of ['drawArrays', 'drawElements', 'drawArraysInstanced', 'drawElementsInstanced']) {
      const orig = proto[name];
      if (orig) proto[name] = function (...a) { P.gl_draws += 1; return orig.apply(this, a); };
    }
    for (const name of ['bufferData', 'bufferSubData', 'texImage2D', 'texSubImage2D', 'texImage3D', 'texSubImage3D', 'compressedTexImage2D', 'compressedTexImage3D']) {
      const orig = proto[name];
      if (orig) proto[name] = function (...a) {
        for (const x of a) if (x && x.byteLength) { P.gl_upload_bytes += x.byteLength; break; }
        return orig.apply(this, a);
      };
    }
  };
  wrapGl(window.WebGL2RenderingContext && WebGL2RenderingContext.prototype);
  const Mem = WebAssembly.Memory;
  WebAssembly.Memory = function (desc) { const m = new Mem(desc); P.wasm = m; return m; };
  WebAssembly.Memory.prototype = Mem.prototype;
  const inst = WebAssembly.instantiate.bind(WebAssembly);
  WebAssembly.instantiate = async (...a) => {
    const r = await inst(...a);
    try {
      const ex = (r.instance || r).exports;
      for (const v of Object.values(ex)) if (v instanceof Mem) P.wasm = v;
    } catch (e) { /* no memory export */ }
    return r;
  };
  const instS = WebAssembly.instantiateStreaming && WebAssembly.instantiateStreaming.bind(WebAssembly);
  if (instS) WebAssembly.instantiateStreaming = async (...a) => {
    const r = await instS(...a);
    try { for (const v of Object.values(r.instance.exports)) if (v instanceof Mem) P.wasm = v; } catch (e) { /* none */ }
    return r;
  };
}

const sleep = (ms) => new Promise((ok) => setTimeout(ok, ms));

async function main() {
  const opts = parseArgs(process.argv.slice(2));
  if (!existsSync(join(opts.build, 'play.html'))) usage(`${opts.build}/play.html is missing: run tools/build_web.sh first`);
  const { chromium } = loadPlaywright();
  const server = await serve(opts.build);
  const origin = `http://127.0.0.1:${server.address().port}`;
  const gameArgs = ['--ui-probe', ...opts.args.split(',').map((x) => x.trim()).filter((x) => x.length)];
  const url = `${origin}/play.html?args=${gameArgs.map(encodeURIComponent).join(',')}`;
  const [width, height] = opts.size.split('x').map(Number);
  const flags = ['--use-angle=swiftshader', '--enable-unsafe-swiftshader', '--ignore-gpu-blocklist', '--autoplay-policy=no-user-gesture-required'];
  if (opts.mute) flags.push('--mute-audio');
  const browser = await chromium.launch({ headless: true, args: flags });
  const busy = [];
  const report = { build: opts.build, url_args: gameArgs, throttle: opts.throttle, pin_cpu: opts.pinCpu, busy: opts.busy, viewport: opts.size,
    mute: opts.mute, no_audio_context: opts.noAudioContext, samples: [], dumps: [], stopped: '' };
  const finish = async (why) => {
    report.stopped = why;
    for (const b of busy) { try { b.kill('SIGKILL'); } catch (e) { /* gone */ } }
    try { await Promise.race([browser.close(), sleep(5000)]); } catch (e) { /* killed below */ }
    killDescendants();
    server.close();
    const s = report.samples;
    const first = s[0] || {};
    const last = s[s.length - 1] || {};
    const brief = { ...report, samples: undefined, dumps: undefined, n: s.length, renderer_mb_first: first.renderer_mb, renderer_mb_last: last.renderer_mb,
      renderer_mb_peak: Math.max(0, ...s.map((x) => x.renderer_mb || 0)), gpu_mb_last: last.gpu_mb, js_heap_mb_last: last.js_heap_mb,
      wasm_mb_last: last.wasm_mb, level_loaded_s: report.level_loaded_s === undefined ? null : report.level_loaded_s,
      dump_summaries: report.dumps.map((d) => ({ at_s: d.at_s, why: d.why, renderer: d.renderer })) };
    console.log(`MEMORY_PROBE ${JSON.stringify(brief)}`);
    if (opts.json) writeFileSync(opts.json, JSON.stringify(report, null, 1) + '\n');
    process.exit(0);
  };
  try {
    const context = await browser.newContext({ viewport: { width, height } });
    const page = await context.newPage();
    await page.addInitScript(instruments, { noAudioContext: opts.noAudioContext });
    const states = [];
    page.on('console', (msg) => {
      const text = msg.text();
      if (!text.startsWith('UI_PROBE ')) return;
      try { const o = JSON.parse(text.slice(9)); if (o.t === 'state') states.push(o); } catch (e) { /* not one */ }
    });
    const cdp = await context.newCDPSession(page);
    await cdp.send('Performance.enable');
    const browserCdp = await browser.newBrowserCDPSession();
    const deadline = Date.now() + opts.timeoutS * 1000;
    const until = async (test, what) => {
      while (!states.some(test)) {
        if (Date.now() > deadline) throw new Error(`timed out waiting for ${what}`);
        await sleep(200);
      }
    };
    console.log(`${TOOL}: ${url}`);
    await page.goto(url, { waitUntil: 'load' });
    if (opts.cont) {
      const cfg = JSON.parse(readFileSync(join(ROOT, 'tools', 'web', 'world_check.json'), 'utf8'));
      const text = readFileSync(join(ROOT, cfg.fixture), 'utf8');
      await page.evaluate(writeSaveInPage, { dbName: IDB_NAME, version: IDB_VERSION, store: IDB_STORE, path: SAVE_PATH, text, dirMode: 0o40775, fileMode: 0o100666 });
    }
    await page.click('#play');
    await until((s) => s.top === 'title' && s.warming === false, 'the title');
    // Starve the browser from here: the title is up, the level's load is what is measured.
    if (opts.throttle > 1) await cdp.send('Emulation.setCPUThrottlingRate', { rate: opts.throttle });
    if (opts.pinCpu >= 0) {
      for (const row of descendantsOf(readProcessTable(), process.pid)) spawnSync('taskset', ['-a', '-cp', String(opts.pinCpu), String(row.pid)]);
      for (let i = 0; i < opts.busy; i++) busy.push(spawn('taskset', ['-c', String(opts.pinCpu), 'sh', '-c', 'while :; do :; done'], { stdio: 'ignore' }));
    }
    await sleep(300);
    await page.focus('#game-canvas').catch(() => {});
    await page.keyboard.press('Enter');
    const t0 = Date.now();
    let begun = opts.cont;
    let dumpsLeft = opts.dumps.slice().sort((a, b) => a - b);
    const dump = async (why) => {
      const events = [];
      const onData = (d) => { for (const e of d.value) events.push(e); };
      browserCdp.on('Tracing.dataCollected', onData);
      try {
        await browserCdp.send('Tracing.start', { transferMode: 'ReportEvents', traceConfig: { includedCategories: ['disabled-by-default-memory-infra'], excludedCategories: ['*'], memoryDumpConfig: { triggers: [] } } });
        await Promise.race([browserCdp.send('Tracing.requestMemoryDump', { levelOfDetail: 'detailed' }), sleep(60000)]);
        const done = new Promise((ok) => browserCdp.once('Tracing.tracingComplete', ok));
        await browserCdp.send('Tracing.end');
        await Promise.race([done, sleep(60000)]);
      } catch (e) {
        report.dumps.push({ at_s: Math.round((Date.now() - t0) / 1000), why, error: String(e && e.message) });
        browserCdp.off('Tracing.dataCollected', onData);
        return;
      }
      browserCdp.off('Tracing.dataCollected', onData);
      const by = allocatorsByProcess(events);
      const table = readProcessTable();
      const top = largestRenderer(table, process.pid);
      report.dumps.push({ at_s: Math.round((Date.now() - t0) / 1000), why, renderer_pid: top ? top.pid : 0, renderer: top ? by[top.pid] || null : null, processes: by });
    };
    for (;;) {
      const at = (Date.now() - t0) / 1000;
      const table = readProcessTable();
      const top = largestRenderer(table, process.pid);
      let gpu = 0;
      for (const row of descendantsOf(table, process.pid)) if (/--type=gpu-process/.test(row.cmd())) gpu = Math.max(gpu, row.rssMb);
      let js = null;
      let own = null;
      try {
        const m = await Promise.race([cdp.send('Performance.getMetrics'), sleep(3000).then(() => null)]);
        if (m) js = Math.round((m.metrics.find((x) => x.name === 'JSHeapUsedSize') || { value: 0 }).value / 1048576);
        own = await Promise.race([page.evaluate(() => {
          const P = window.__memProbe;
          return { raf_pending: P.raf_asked - P.raf_run, frames: P.frames, worklet_handled: P.worklet_handled, chunks_posted: P.chunks_posted,
            chunk_mb: Math.round(P.chunk_bytes / 1048576), gl_draws: P.gl_draws, gl_upload_mb: Math.round(P.gl_upload_bytes / 1048576),
            timers_pending: P.timers_asked - P.timers_run, wasm_mb: P.wasm ? Math.round(P.wasm.buffer.byteLength / 1048576) : null };
        }), sleep(3000).then(() => null)]);
      } catch (e) { /* the page is busy: /proc still answers */ }
      const last = states[states.length - 1] || {};
      const sample = { s: Math.round(at * 10) / 10, renderer_mb: top ? Math.round(top.rssMb) : 0, gpu_mb: Math.round(gpu), js_heap_mb: js,
        top: last.top, loading: last.loading, level: last.level, ...(own || {}) };
      report.samples.push(sample);
      if (!begun && states.some((s) => s.top === 'creator')) {
        begun = true;
        report.creator_s = sample.s;
        await page.focus('#game-canvas').catch(() => {});
        await page.keyboard.press('Control+Enter');
      }
      if (report.level_loaded_s === undefined && states.some((s) => String(s.level || '').startsWith('level.') && s.loading === false && s.top === '')) report.level_loaded_s = sample.s;
      if (dumpsLeft.length && sample.renderer_mb >= dumpsLeft[0]) {
        const mark = dumpsLeft.shift();
        await dump(`the renderer passed ${mark} MB`);
      }
      if (sample.renderer_mb > opts.limitMb) { await dump('the limit'); await finish(`the renderer passed ${opts.limitMb} MB after ${sample.s} s`); }
      if (at > opts.seconds) { await dump('the end'); await finish(`${opts.seconds} s`); }
      await sleep(1000);
    }
  } catch (e) {
    report.error = String((e && e.message) || e);
    await finish(`error: ${report.error}`);
  }
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) main();
