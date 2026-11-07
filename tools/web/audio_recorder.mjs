// The web audio recorder (P23's, shared by tools/web/audio_check.mjs and, since the M7 gate,
// tools/web/stream_check.mjs --audio): the page instrument injected before the game's scripts (an
// AudioContext wrapper with a recorder worklet on a tap of its destination, the buffer tracker of
// the live sample bytes, the AUDIO_MUSIC marks, the frame clock, the long tasks and the driver's
// "read" messages), the placing of every hole in the music on the main thread's clock, the
// statistics, the analysis of a recording against the plan's criterion (no silent run over 50 ms)
// and the level's registered sample seconds (the live-bytes cap). See audio_check.mjs's header for
// what each piece measures and why.

import { readdirSync, readFileSync } from 'node:fs';
import { join } from 'node:path';

export const HOLE_MAX_MS = 50;
export const BYTES_PER_REGISTERED_S = 353000;
export const LIVE_HEADROOM_BYTES = 12000000;
export const SILENCE_PEAK = 1e-4;
// A hole's place on the page's clock may be off by this much (the audio clock's mapping to it, the
// output latency, the chunk's way back to the worklet).
export const PLACE_TOLERANCE_MS = 35;
// Holes this close together are one stall of the mixer (a sample voice sounded between them).
export const MERGE_GAP_MS = 12;

// The seconds of samples a level registers (Audio.sample_paths_for): every WAV of an SFX or UI cue
// with no `levels`, then of the cues whose `levels` name the level; seconds from the manifest.
export function registeredSeconds(level) {
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
export function streamBufferMs(rate) {
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

export const round1 = (x) => (typeof x === 'number' ? Math.round(x * 10) / 10 : null);

// The page frames (the intervals of the frame clock): p50, p95, the longest, how many outlast the
// stream buffer.
export function frameStats(times, bufferMs) {
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
export function taskStats(tasks, from, to) {
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
export function placeHoles(holes, service, armRef, disarmRef, quantumMs) {
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
export function serviceStats(service, bufferMs) {
  let longest = 0;
  let over = 0;
  for (let i = 1; i < service.length; i++) {
    const g = service[i] - service[i - 1];
    if (g > longest) longest = g;
    if (g > bufferMs) over++;
  }
  return { reads: service.length, longest_gap_ms: round1(longest), gaps_over_buffer: over };
}

// Injected before the page's scripts (Playwright addInitScript): the AudioContext wrapper, the
// destination tap with the recorder worklet, the buffer tracker and the AUDIO_MUSIC marks.
export function instrument({ silencePeak, holeMs, autoArm = null }) {
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
    if (A.auto) A.onLine(text);
    origLog(...items);
  };
  // M7 gate (stream_check.mjs --audio): with autoArm = { start, end } the recorder arms itself once the
  // line starting with `start` (WORLD_WALK_START) was printed and a zone-state AUDIO_MUSIC mark seen,
  // and disarms at the line starting with `end` (WORLD_WALK_END) - in the page, at the line itself.
  A.auto = autoArm ? { started: false, armed: false, ended: false, armed_ms: null, ended_ms: null } : null;
  A.onLine = (text) => {
    const s = A.auto;
    if (s.ended) return;
    if (text.startsWith(autoArm.end)) {
      s.ended = true;
      s.ended_ms = now();
      if (s.armed) A.disarm();
      return;
    }
    if (text.startsWith(autoArm.start)) s.started = true;
    A.tryArm();
  };
  A.tryArm = () => {
    const s = A.auto;
    if (!s || s.armed || s.ended || !s.started || !A.marks.some((m) => m.state === 'zone')) return;
    if (A.arm()) {
      s.armed = true;
      s.armed_ms = now();
    } else {
      setTimeout(A.tryArm, 100);   // the recorder's worklet is not ready yet
    }
  };
  A.ctx = () => A.ctxs[A.ctxs.length - 1];
  A.post = (msg) => { const c = A.ctx(); if (c && c.__rec) { c.__rec.port.postMessage(msg); return true; } return false; };
  // The page's frame clock: the time of every requestAnimationFrame while the recorder is armed (the
  // engine's main loop is a requestAnimationFrame callback too: an interval is one engine frame).
  A.frames = [];
  // On from the page's load (M6 gate: a run that times out before the music is armed still has its
  // frames, long tasks and driver reads in the report); arm() starts them afresh for the music.
  A.frameClock = true;
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

// The recorder's state after a disarm, read from the page (the instrument's window.__audioCheck).
export function readRecording(page) {
  return page.evaluate(() => {
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
      auto: A.auto ? { ...A.auto } : null,
    };
  });
}

// A recording against the plan's criterion: { music, page_frames, long_tasks, driver, trace, criterion,
// problems } (music null and one problem when the recorder reported nothing). `t0`: the page time the
// recording was asked for (the long tasks' window when no arm reference was taken); `musicS`: the
// seconds of music wanted; `strict`: every hole over HOLE_MAX_MS fails (else only holes the main
// thread does not explain).
export function analyseRecording(state, { musicS, strict, t0 }) {
  const problems = [];
  const s = state.stats;
  if (!s) {
    problems.push('the recorder reported nothing');
    return { music: null, problems };
  }
  const quantumMs = 128 / s.sample_rate * 1000;
  const bufferMs = streamBufferMs(s.sample_rate);
  const placed = placeHoles(s.holes || [], state.service, state.armRef, state.disarmRef, quantumMs);
  const music = {
    seconds: Math.round((s.end_t - s.start_t) * 10) / 10, wall_s: Math.round((state.wall_ms - t0) / 100) / 10,
    quanta: s.quanta, silent_quanta: s.silent, longest_silence_ms: Math.round(s.longest * quantumMs * 10) / 10,
    silent_runs_over_50_ms: s.runs_over + (s.run * quantumMs > HOLE_MAX_MS ? 1 : 0), peak: Math.round(s.peak * 1000) / 1000,
    holes_while_unserved: placed.while_unserved, holes_elsewhere: placed.elsewhere,
  };
  const until = state.disarmRef ? state.disarmRef.page_ms : state.wall_ms;
  const out = {
    music,
    page_frames: frameStats(state.frames.filter((t) => t <= until), bufferMs),
    long_tasks: taskStats(state.tasks, state.armRef ? state.armRef.page_ms : t0, until),
    driver: { watched: state.driverWatched, ...serviceStats(state.service.filter((x) => x <= until), bufferMs) },
    trace: {
      arm: state.armRef, disarm: state.disarmRef, quantum_ms: quantumMs, frames: state.frames, tasks: state.tasks,
      service: state.service, holes: s.holes || [],
    },
    // The plan's criterion (M6 gate): no silent run over HOLE_MAX_MS in the music at all.
    criterion: {
      hole_max_ms: HOLE_MAX_MS, met: music.longest_silence_ms <= HOLE_MAX_MS,
      holes: music.silent_runs_over_50_ms, longest_silence_ms: music.longest_silence_ms,
      mode: strict ? 'strict' : 'default (holes placed on the main thread pass)',
    },
    problems,
  };
  if (music.longest_silence_ms > HOLE_MAX_MS) {
    if (strict) problems.push(`a ${music.longest_silence_ms} ms hole in the music`);
    if (placed.elsewhere.length > 0) {
      problems.push(`${placed.elsewhere.length} hole(s) over ${HOLE_MAX_MS} ms not explained by the main thread leaving the mixer unserved (the first ${placed.elsewhere[0].ms} ms at ${placed.elsewhere[0].page_s} s)`);
    }
  }
  if (music.seconds < musicS * 0.9) problems.push(`the audio clock ran ${music.seconds} s of ${musicS} s`);
  return out;
}

// The level record whose scene is `scene` (data/**/level_*.json): its id, or '' when none.
export function levelIdForScene(scene) {
  for (const sub of readdirSync('data').sort()) {
    const dir = join('data', sub);
    let names = [];
    try { names = readdirSync(dir); } catch (e) { continue; }
    for (const name of names.sort()) {
      if (!name.startsWith('level_') || !name.endsWith('.json')) continue;
      try {
        const rec = JSON.parse(readFileSync(join(dir, name), 'utf8'));
        if (rec.scene === scene) return String(rec.id || '');
      } catch (e) { /* not a record */ }
    }
  }
  return '';
}
