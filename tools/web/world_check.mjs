#!/usr/bin/env node
// The web world check (P39f; plan M6-M9 §3.23, §6.3, §6.6): stream_check.mjs extended to the world as a
// returning player meets it - the Web release in headless Chromium with its sound on:
//   * boot: the page as a player opens it, with a world save already in the browser: the fixture (by
//     default tools/web/world_check.json's, a save the world bot wrote) put into the page's IndexedDB
//     (Godot's /userfs: <app_userdata>/saves/valley_1.json, the entries as the engine's own file system
//     writes them) before Play;
//   * Continue: Play, the title (its music), then Enter - the title's first focus with a saved game is
//     Continue; the world loads at the save's respawn (checked against the fixture: its level, its
//     respawn checkpoint, the giant's stage);
//   * fast travel: the world walk's --walk-travel=<checkpoint> asks for the travel the map's way
//     (Events.travel_requested, "fast_travel") once the level has settled, and the level reloads at the
//     waystone;
//   * the walk: from where the travel put the giant, with the stick, AI on, along the route for at least
//     --walk-min-s of game time and across at least one region border;
// and reports, as stream_check.mjs does for its walk:
//   * the page's frames while the giant walks (requestAnimationFrame intervals between WORLD_WALK_START
//     and WORLD_WALK_END: worst and p99 against the indicative web budget - worst <= 45 ms, p99 <= 25 ms;
//     --strict fails on it) and the engine's own (PerfProbe frame_ms, capped at 133 ms);
//   * the streaming: work per frame p50 / p99 / max, the hitches (work frames over the streamer's 4 ms
//     budget, and the heaviest steps by kind), loads, unloads, thrash, the most chunks loaded and the
//     least margin to unloaded ground (>= 200 m);
//   * the music (audio_recorder.mjs, armed at the walk's start once zone music plays): holes over 50 ms,
//     each placed on the main thread's clock (a hole the main thread explains passes the default check;
//     --strict fails every one), the seconds recorded (>= --music-s), the region borders the music
//     crossed (>= --min-borders) and the peak live sample bytes against level.world's registered seconds
//     x 353 KB + 12 MB;
//   * the Continue's and the travel's load times (the scene left - the game's WORLD_WALK_UNLOAD line - to
//     the walk's WORLD_WALK_LEVEL line on the level loaded), the console errors while the game runs (0
//     wanted; the engine's warnings - "WARNING: ..." lines, which the web build prints as console errors -
//     are listed apart and fail only --strict; lines while the engine quits after the result are listed
//     apart too) and the failed requests.
// Prints WORLD_CHECK {json} and one verdict line: "world_check: OK", "world_check: OK (the plan's audio
// criterion NOT MET: ...)" when every hole over 50 ms was the main thread's, or "world_check: FAILED - ...".
// Exit code 0 when everything held (1 otherwise; 2 for a usage error). Its own test:
// node tools/web/test_world_check.mjs (a stub launcher, no build).
//
// Usage (from the project folder, after tools/build_web.sh - the release takes the check's arguments):
//   node tools/web/world_check.mjs [--build=builds/web] [--config=tools/web/world_check.json]
//        [--fixture=FILE] [--travel=<checkpoint id>] [--route=x:z;x:z;...] [--walk-min-s=60]
//        [--music-s=60] [--min-borders=1] [--registered-s=S] [--autoplay=S] [--size=1280x720]
//        [--timeout-s=S] [--json=FILE] [--strict] [--headed]
//   --config       the defaults: {fixture, travel_to, route [[x, z], ...], walk_min_s, min_borders}
//   --fixture      the save put into the browser (a schema 2 save of level.world)
//   --travel       the visited waystone or shrine the giant fast travels to (the fixture's flags must hold
//                  visited.<id>)
//   --route        the walk's points after the arrival (the walk sets off where the travel put the giant)
//   --walk-min-s   the least game time the walk must last
//   --strict       also fail on the indicative frame budget, on every hole in the music over 50 ms and on
//                  the engine's warnings (for a machine with a GPU)
//   --json         the report and the recording's trace (audio_check.mjs --replay places its holes again)
// Needs Playwright (PLAYWRIGHT_MODULE, NODE_PATH or /opt/node-tools/node_modules) and its Chromium
// (PLAYWRIGHT_BROWSERS_PATH, default /opt/pw-browsers when that folder exists). Software WebGL
// (SwiftShader) is all a GPU-less machine has: its frame times are the CPU's rasterising, indicative only,
// and the no-threads build's mixer waits for every slow frame (the music's holes). There the default verdict is
// indicative and load-dependent: it passes the holes placed on the main thread's stalls (and, since W23, a hole
// the recording's end cut short - audio_recorder.mjs's holes_cut_at_disarm), but with the machine starved the
// browser's audio clock runs unevenly against the page's, so holes can land outside the stalls and fail it (a
// run at a load average of 8-9 did: docs/systems/P39f.md, "Part web"). The run that counts for the gate is
// --strict on a machine with a GPU (docs/USABILITY_SCRIPT.md §11).

import { existsSync, readFileSync, writeFileSync } from 'node:fs';
import { join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { HOLE_MAX_MS, SILENCE_PEAK, instrument, readRecording } from './audio_recorder.mjs';
import {
  BUDGET_P99_MS, BUDGET_WORST_MS, MARGIN_REQUIRED_M, audioReport, loadPlaywright, serve, summary, verdict,
} from './stream_check.mjs';

const TOOL = 'world_check';
// Godot's web file system (Emscripten IDBFS on /userfs): the database, its store and index, the slot's
// path under user:// (project.godot's name, made safe for a folder: "Giantborn- Age of Titans") and the
// modes of a folder and a file, as the engine writes them (seen in a release build's database).
export const IDB_NAME = '/userfs';
export const IDB_VERSION = 21;
export const IDB_STORE = 'FILE_DATA';
export const USER_DIR = '/userfs/godot/app_userdata/Giantborn- Age of Titans';
export const SAVE_PATH = `${USER_DIR}/saves/valley_1.json`;
const DIR_MODE = 0o40775;
const FILE_MODE = 0o100666;
// The title is given this long to draw once its music plays, before Enter; Enter again when the scene did
// not change this long after the last press (the title was still drawing), at most this many presses.
const TITLE_SETTLE_S = 5;
const ENTER_AGAIN_S = 45;
const ENTER_PRESSES = 3;
// The console lines kept for the --json report (each with its time).
const CONSOLE_KEEP = 600;

function usage(message) {
  console.error(`${TOOL}: ${message}`);
  process.exit(2);
}

function readJson(path, what) {
  try {
    return JSON.parse(readFileSync(path, 'utf8'));
  } catch (e) {
    usage(`${what} ${path} cannot be read (${e && e.message ? e.message : e})`);
    return null;
  }
}

export function parseArgs(argv) {
  const opts = {
    build: 'builds/web', config: 'tools/web/world_check.json', fixture: null, travel: null, route: null,
    walkMinS: null, musicS: 60, minBorders: null, registeredS: null, autoplay: 2400, size: '1280x720',
    timeoutS: 3600, json: '', strict: false, headed: false,
  };
  for (const arg of argv) {
    const [key, ...rest] = arg.split('=');
    const value = rest.join('=');
    switch (key) {
      case '--build': opts.build = value; break;
      case '--config': opts.config = value; break;
      case '--fixture': opts.fixture = value; break;
      case '--travel': opts.travel = value; break;
      case '--route': opts.route = value; break;
      case '--walk-min-s': opts.walkMinS = Number(value); break;
      case '--music-s': opts.musicS = Number(value); break;
      case '--min-borders': opts.minBorders = Number(value); break;
      case '--registered-s': opts.registeredS = Number(value); break;
      case '--autoplay': opts.autoplay = Number(value); break;
      case '--size': opts.size = value; break;
      case '--timeout-s': opts.timeoutS = Number(value); break;
      case '--json': opts.json = value; break;
      case '--strict': opts.strict = true; break;
      case '--headed': opts.headed = true; break;
      case '-h': case '--help':
        console.log(readFileSync(new URL(import.meta.url), 'utf8').split('\n').slice(1).filter((l, i, all) =>
          all.slice(0, i + 1).every((x) => x.startsWith('//'))).join('\n'));
        process.exit(0);
        break;
      default:
        usage(`unknown option ${arg}`);
    }
  }
  const cfg = readJson(opts.config, 'the config');
  if (opts.fixture === null) opts.fixture = String(cfg.fixture || '');
  if (opts.travel === null) opts.travel = String(cfg.travel_to || '');
  if (opts.route === null) opts.route = (cfg.route || []).map((p) => `${p[0]}:${p[1]}`).join(';');
  if (opts.walkMinS === null) opts.walkMinS = Number(cfg.walk_min_s || 60);
  if (opts.minBorders === null) opts.minBorders = Number(cfg.min_borders !== undefined ? cfg.min_borders : 1);
  if (!/^\d+x\d+$/.test(opts.size)) usage('--size wants WxH');
  if (!(opts.musicS > 0) || !(opts.walkMinS > 0) || !(opts.minBorders >= 0) || !(opts.autoplay > 0) || !(opts.timeoutS > 0)
      || (opts.registeredS !== null && !(opts.registeredS >= 0))) {
    usage('--music-s, --walk-min-s, --autoplay and --timeout-s want positive numbers, --min-borders and --registered-s numbers >= 0');
  }
  if (!opts.fixture || !opts.travel || !opts.route) usage('a fixture, a --travel checkpoint and a --route are needed');
  if (opts.route.split(';').filter((p) => /^-?[\d.]+:-?[\d.]+$/.test(p)).length < 2) usage('--route wants two or more x:z points');
  opts.save = readJson(opts.fixture, 'the fixture');
  return opts;
}

// The fixture's place: { level, respawn, stage, schema_version } (what the Continue must load).
export function fixtureSummary(doc) {
  const cp = (doc && doc.checkpoint) || {};
  const ch = (doc && doc.character) || {};
  return { level: doc ? doc.level : undefined, respawn: cp.respawn, stage: ch.growth_stage, character_level: ch.level,
    schema_version: doc ? doc.schema_version : undefined, build_version: doc ? doc.build_version : undefined };
}

// The game's command line (each item one argument; web/launcher.html puts them after "--"): the default
// settings with saving kept on in the player's own slot folder (--no-user-settings alone turns saving off,
// and with it the title's Continue), the title (so Play opens it as for a player), the world walk with its
// travel and route, the music marks.
export function engineArgs(opts) {
  const args = ['--no-user-settings', '--save-dir=user://saves', '--mode=title', '--scenario=world_walk', `--autoplay=${opts.autoplay}`,
    `--walk-travel=${opts.travel}`, `--route=${opts.route}`, '--audio-stats'];
  for (const a of args) {
    if (a.includes(',')) usage(`an engine argument may not hold a comma: ${a}`);
  }
  return args;
}

// Puts `text` into the page's IndexedDB as Godot's /userfs file `path`, with every folder above it, as the
// engine's file system stores them (run in the page, before Play: the engine reads the database once, when
// it starts). Resolves to the entries written.
export function writeSaveInPage({ dbName, version, store, path, text, dirMode, fileMode }) {
  return new Promise((ok, fail) => {
    const req = indexedDB.open(dbName, version);
    req.onupgradeneeded = () => {
      const db = req.result;
      const st = db.objectStoreNames.contains(store) ? req.transaction.objectStore(store) : db.createObjectStore(store);
      if (!st.indexNames.contains('timestamp')) st.createIndex('timestamp', 'timestamp', { unique: false });
    };
    req.onerror = () => fail(new Error(`indexedDB.open: ${req.error}`));
    req.onsuccess = () => {
      const db = req.result;
      const tx = db.transaction(store, 'readwrite');
      const st = tx.objectStore(store);
      const now = new Date();
      const parts = path.split('/').filter((p) => p.length > 0);
      const written = [];
      // the folders under the mount point (/userfs itself is the mount, never an entry)
      for (let i = 2; i < parts.length; i++) {
        const dir = '/' + parts.slice(0, i).join('/');
        st.put({ timestamp: now, mode: dirMode }, dir);
        written.push(dir);
      }
      st.put({ timestamp: now, mode: fileMode, contents: new Int8Array(new TextEncoder().encode(text).buffer) }, path);
      written.push(path);
      tx.oncomplete = () => {
        db.close();
        ok(written);
      };
      tx.onerror = () => fail(new Error(`the save's transaction: ${tx.error}`));
    };
  });
}

// Reads the file at `path` back from the page's IndexedDB (null when it is not there).
export function readSaveInPage({ dbName, store, path }) {
  return new Promise((ok) => {
    const req = indexedDB.open(dbName);
    req.onupgradeneeded = () => req.transaction.abort();
    req.onerror = () => ok(null);
    req.onsuccess = () => {
      const db = req.result;
      if (!db.objectStoreNames.contains(store)) {
        db.close();
        ok(null);
        return;
      }
      const get = db.transaction(store, 'readonly').objectStore(store).get(path);
      get.onsuccess = () => {
        db.close();
        const v = get.result;
        ok(v && v.contents ? new TextDecoder().decode(new Uint8Array(v.contents.buffer, v.contents.byteOffset, v.contents.byteLength)) : null);
      };
      get.onerror = () => {
        db.close();
        ok(null);
      };
    };
  });
}

const sleep = (ms) => new Promise((ok) => setTimeout(ok, ms));
const round1 = (x) => (typeof x === 'number' ? Math.round(x * 10) / 10 : null);

// The engine's warnings among the console's errors (the web build prints push_warning through
// console.error): "WARNING: ..." and the "   at: ..." line that follows it. `lines`: the error lines in
// order; returns { errors, warnings }.
export function splitWarnings(lines) {
  const errors = [];
  const warnings = [];
  let last = errors;
  for (const line of lines) {
    if (/^\s+at: /.test(line)) {
      last.push(line);
      continue;
    }
    last = /^(USER )?WARNING:/.test(line) ? warnings : errors;
    last.push(line);
  }
  return { errors, warnings };
}

async function main() {
  const opts = parseArgs(process.argv.slice(2));
  if (!existsSync(join(opts.build, 'play.html'))) {
    console.error(`${TOOL}: ${opts.build}/play.html is missing: run tools/build_web.sh first`);
    process.exit(1);
  }
  if (!process.env.PLAYWRIGHT_BROWSERS_PATH && existsSync('/opt/pw-browsers')) {
    process.env.PLAYWRIGHT_BROWSERS_PATH = '/opt/pw-browsers';
  }
  const fixture = fixtureSummary(opts.save);
  const { chromium } = loadPlaywright();
  const server = await serve(opts.build);
  const origin = `http://127.0.0.1:${server.address().port}`;
  const args = engineArgs(opts);
  const url = `${origin}/play.html?args=${args.map(encodeURIComponent).join(',')}`;
  const [width, height] = opts.size.split('x').map(Number);
  const browser = await chromium.launch({
    headless: !opts.headed,
    args: ['--use-angle=swiftshader', '--enable-unsafe-swiftshader', '--ignore-gpu-blocklist', '--autoplay-policy=no-user-gesture-required'],
  });
  const page = await browser.newPage({ viewport: { width, height } });
  // The page's frame clock while the giant walks (stream_check.mjs's).
  await page.addInitScript(() => {
    window.__frames = [];
    window.__frameClock = false;
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
      } else if (text.startsWith('WORLD_WALK_END') || text.startsWith('AUTOPILOT_RESULT')) {
        window.__frameClock = false;
      }
      log(...items);
    };
  });
  // The music recorder, armed by the page at the walk's start once zone music plays (stream_check's --audio).
  await page.addInitScript(instrument, {
    silencePeak: SILENCE_PEAK, holeMs: HOLE_MAX_MS, autoArm: { start: 'WORLD_WALK_START', end: 'WORLD_WALK_END' },
  });
  const external = [];
  await page.route((u) => !u.href.startsWith(origin), (route) => {
    external.push(route.request().url());
    const css = route.request().resourceType() === 'stylesheet';
    return route.fulfill({ status: 200, contentType: css ? 'text/css' : 'application/octet-stream', body: '' });
  });
  const started = Date.now();
  const at = () => Math.round((Date.now() - started) / 100) / 10;   // seconds since the start (wall)
  const errors = [];
  const exitErrors = [];
  const failedRequests = [];
  const abortedRequests = [];
  const levels = [];      // WORLD_WALK_LEVEL lines: { ...data, t }
  const unloads = [];     // WORLD_WALK_UNLOAD lines: { ...data, t } (the scene a load leaves)
  const consoleLog = [];  // [t, type, text] (the first CONSOLE_KEEP lines, then the last ones)
  let travelLine = null;  // WORLD_TRAVEL: { ...data, t }
  let titleAt = null;
  let walkStartAt = null;
  let walkEndAt = null;
  let perf = null;
  let result = null;
  let lines = 0;
  const parse = (text, tag) => {
    try {
      return JSON.parse(text.slice(tag.length + 1));
    } catch (e) {
      errors.push(`unreadable ${tag}: ${e}`);
      return {};
    }
  };
  page.on('console', (msg) => {
    const text = msg.text();
    lines += 1;
    consoleLog.push([at(), msg.type(), text.length > 400 ? text.slice(0, 400) + '...' : text]);
    if (consoleLog.length > CONSOLE_KEEP) consoleLog.splice(CONSOLE_KEEP / 2, 1);
    if (msg.type() === 'error') (result === null ? errors : exitErrors).push(text);
    if (text.startsWith('AUDIO_MUSIC ') && titleAt === null && parse(text, 'AUDIO_MUSIC').set === 'music.title') titleAt = at();
    else if (text.startsWith('WORLD_WALK_LEVEL ')) levels.push({ ...parse(text, 'WORLD_WALK_LEVEL'), t: at() });
    else if (text.startsWith('WORLD_WALK_UNLOAD ')) unloads.push({ ...parse(text, 'WORLD_WALK_UNLOAD'), t: at() });
    else if (text.startsWith('WORLD_TRAVEL ')) travelLine = { ...parse(text, 'WORLD_TRAVEL'), t: at() };
    else if (text.startsWith('WORLD_WALK_START')) walkStartAt = at();
    else if (text.startsWith('WORLD_WALK_END')) walkEndAt = at();
    else if (text.startsWith('PERF_RESULT ')) perf = parse(text, 'PERF_RESULT');
    else if (text.startsWith('AUTOPILOT_RESULT ')) result = parse(text, 'AUTOPILOT_RESULT');
  });
  page.on('pageerror', (err) => (result === null ? errors : exitErrors).push(`page error: ${err.message}`));
  page.on('requestfailed', (req) => {
    const why = req.failure() ? req.failure().errorText : 'failed';
    (why === 'net::ERR_ABORTED' ? abortedRequests : failedRequests).push(`${req.url()} (${why})`);
  });
  page.on('response', (res) => { if (res.status() >= 400) failedRequests.push(`${res.url()} (${res.status()})`); });

  const problems = [];
  const report = { url_args: args, build: opts.build, viewport: opts.size, fixture: { path: opts.fixture, ...fixture },
    travel_to: opts.travel, walk_min_s: opts.walkMinS };
  console.log(`${TOOL}: ${url}`);
  await page.goto(url, { waitUntil: 'load' });
  // The returning player's save, before the engine starts (it reads the database once, at its start).
  const saveText = readFileSync(opts.fixture, 'utf8');
  report.save_entries = await page.evaluate(writeSaveInPage, { dbName: IDB_NAME, version: IDB_VERSION, store: IDB_STORE,
    path: SAVE_PATH, text: saveText, dirMode: DIR_MODE, fileMode: FILE_MODE });
  const back = await page.evaluate(readSaveInPage, { dbName: IDB_NAME, store: IDB_STORE, path: SAVE_PATH });
  if (back !== saveText) problems.push('the fixture could not be put into the page\'s IndexedDB');
  const deadline = started + opts.timeoutS * 1000;
  const playAt = at();
  await page.click('#play');
  // The title: its music (or, should it never play, the engine's start and a while to draw), then Enter.
  while (titleAt === null && Date.now() < deadline && result === null) await sleep(250);
  report.play_to_title_s = titleAt !== null ? round1(titleAt - playAt) : null;
  if (titleAt === null) problems.push('the title\'s music never played (no title to Continue from)');
  const pressTimes = [];
  let lastPress = 0;
  if (titleAt !== null) {
    await sleep(TITLE_SETTLE_S * 1000);
    // Enter until the title's scene goes (the Continue's unload line) or a level comes
    while (unloads.length === 0 && levels.length === 0 && Date.now() < deadline && result === null) {
      if (pressTimes.length < ENTER_PRESSES && (pressTimes.length === 0 || Date.now() - lastPress > ENTER_AGAIN_S * 1000)) {
        await page.focus('#game-canvas').catch(() => {});
        await page.keyboard.press('Enter');
        pressTimes.push(at());
        lastPress = Date.now();
      }
      await sleep(250);
    }
  }
  const presses = pressTimes.length;
  report.enter_presses = presses;
  let lastNote = Date.now();
  while (result === null && Date.now() < deadline) {
    await sleep(1000);
    if (Date.now() - lastNote > 60000) {
      lastNote = Date.now();
      console.log(`${TOOL}: ${Math.round((Date.now() - started) / 1000)} s, ${lines} console lines, ${levels.length} level line(s), waiting for AUTOPILOT_RESULT`);
    }
  }
  if (result !== null) await sleep(3000);   // the run quits after its result: its last lines count too
  report.wall_s = at();
  const rafFrames = await page.evaluate(() => window.__frames.slice()).catch(() => []);
  const recording = await readRecording(page).catch((e) => ({ unreadable: String(e && e.message ? e.message : e) }));
  await browser.close();
  server.close();

  // Continue: the first level line, the fixture's level and respawn; the travel; the arrival.
  const cont = levels.find((l) => l.travel === 'pending') || levels[0] || null;
  const arrived = levels.find((l) => l.travel === 'arrived') || null;
  // the scenes left: the title's (the Continue) before the first level line, the first level's (the travel) after it
  const leftTitle = cont ? unloads.filter((u) => u.t <= cont.t).pop() : null;
  const leftLevel = arrived ? unloads.filter((u) => u.t <= arrived.t && (!cont || u.t >= cont.t)).pop() : null;
  const pressed = leftTitle ? pressTimes.filter((p) => p <= leftTitle.t).pop() : null;
  report.continue = cont ? { level: cont.level, respawn: cont.respawn, stage: cont.stage, at: cont.at, entered: cont.entered,
    load_s: leftTitle ? round1(cont.t - leftTitle.t) : null,
    enter_to_control_s: pressed !== null && pressed !== undefined ? round1(cont.t - pressed) : null,
    presses_ignored: pressed !== null && pressed !== undefined ? pressTimes.filter((p) => p < pressed).length : null } : null;
  if (!cont) problems.push(`Continue never loaded a level (${presses} Enter press(es) on the title)`);
  else {
    if (cont.level !== fixture.level || cont.respawn !== fixture.respawn) {
      problems.push(`Continue loaded ${cont.level} at ${cont.respawn}, not the fixture's ${fixture.level} at ${fixture.respawn}`);
    }
    if (fixture.stage !== undefined && cont.stage !== fixture.stage) problems.push(`the giant came back at stage ${cont.stage}, not the fixture's ${fixture.stage}`);
  }
  report.travel = travelLine ? { from: travelLine.from, to: travelLine.to, waited_ticks: travelLine.waited_ticks,
    refusals: travelLine.refusals, last_refusal: travelLine.last_refusal,
    load_s: arrived && leftLevel ? round1(arrived.t - leftLevel.t) : null,
    request_to_control_s: arrived ? round1(arrived.t - travelLine.t) : null } : null;
  if (!travelLine) problems.push(`the fast travel to ${opts.travel} was never asked for`);
  else if (!arrived) problems.push(`the fast travel to ${opts.travel} never arrived`);
  else if (arrived.respawn !== opts.travel) problems.push(`the travel arrived with the respawn at ${arrived.respawn}, not ${opts.travel}`);
  if (arrived) report.travel.arrived = { level: arrived.level, respawn: arrived.respawn, at: arrived.at, stage: arrived.stage };

  // The walk (the game's report), its frames and its streaming.
  const walk = (result && result.world_walk) || {};
  const st = walk.streaming || {};
  const frames = perf && typeof perf.frame_ms === 'object' ? perf.frame_ms : null;
  const raf = summary(rafFrames);
  const heaviest = Object.entries(st.steps_by_kind || {}).map(([k, v]) => ({ step: k, n: v.n, max_ms: v.max_ms }))
    .sort((a, b) => b.max_ms - a.max_ms).slice(0, 4);
  report.raf_frames = raf;
  report.engine_frames = frames;
  report.worst_frame_ms = raf.n ? raf.max : null;
  report.p99_frame_ms = raf.n ? raf.p99 : null;
  report.budget = {
    worst_ms: { limit: BUDGET_WORST_MS, value: report.worst_frame_ms, verdict: verdict(report.worst_frame_ms, BUDGET_WORST_MS) },
    p99_ms: { limit: BUDGET_P99_MS, value: report.p99_frame_ms, verdict: verdict(report.p99_frame_ms, BUDGET_P99_MS) },
  };
  report.renderer = perf ? `${perf.renderer} (${perf.adapter})` : 'N/A';
  report.quality = perf ? perf.quality : 'N/A';
  report.draw_calls = perf && typeof perf.draw_calls === 'object' ? perf.draw_calls : (perf ? perf.draw_calls : null);
  report.walk = {
    mode: walk.mode, metres: walk.metres, seconds: walk.seconds, finished: walk.finished, stage: walk.stage,
    region_changes: (walk.region_changes || []).length, regions: (walk.region_changes || []).map((r) => r.region),
    seam_crossings: walk.seam_crossings, stuck_teleports: walk.stuck_teleports, route_points: walk.route_points,
    check_failures: walk.check_failures || [], wall_s: walkStartAt !== null && walkEndAt !== null ? round1(walkEndAt - walkStartAt) : null,
  };
  report.streaming = {
    work_ms_p50: walk.work_ms_p50, work_ms_p99: walk.work_ms_p99, work_ms_max: walk.work_ms_max, work_frames: st.work_frames,
    hitches: st.work_ms_over_budget, budget_ms: st.budget_ms, heaviest_steps: heaviest, loads: walk.loads, unloads: walk.unloads,
    thrash: walk.thrash, max_loaded: walk.max_loaded, min_margin_m: walk.min_margin_m,
  };
  report.errors_counted_by_game = result ? result.errors : null;
  report.warnings_counted_by_game = result ? result.warnings : null;
  const split = splitWarnings(errors);
  if (!result) problems.push(`no AUTOPILOT_RESULT within ${opts.timeoutS} s`);
  if (result && !walk.finished) problems.push('the walk did not finish');
  if ((walk.check_failures || []).length > 0) problems.push(`walk check failures: ${walk.check_failures.join('; ')}`);
  if (result && walk.finished && !(walk.seconds >= opts.walkMinS)) problems.push(`the walk lasted ${walk.seconds} s of game time (at least ${opts.walkMinS})`);
  if (result && walk.finished && report.walk.region_changes < 1) problems.push('the walk crossed no region border');
  if (typeof walk.min_margin_m === 'number' && walk.min_margin_m >= 0 && walk.min_margin_m < MARGIN_REQUIRED_M) {
    problems.push(`margin ${walk.min_margin_m} m < ${MARGIN_REQUIRED_M} m`);
  }
  if (result && Number(result.errors) > 0) problems.push(`${result.errors} error(s) counted by the game`);
  if (split.errors.length > 0) problems.push(`${split.errors.length} console error(s)`);
  if (opts.strict && split.warnings.length > 0) problems.push(`${split.warnings.length} console warning line(s) (--strict)`);
  if (failedRequests.length > 0) problems.push(`${failedRequests.length} failed request(s)`);
  if (opts.strict) {
    if (report.budget.worst_ms.verdict !== 'PASS') problems.push(`worst frame ${report.worst_frame_ms} ms > ${BUDGET_WORST_MS} ms`);
    if (report.budget.p99_ms.verdict !== 'PASS') problems.push(`p99 frame ${report.p99_frame_ms} ms > ${BUDGET_P99_MS} ms`);
  }
  // The music: stream_check.mjs's --audio report (the world's cap, the borders the music crossed).
  const audio = audioReport(recording, { world: true, level: '', registeredS: opts.registeredS, musicS: opts.musicS,
    strict: opts.strict, minBorders: opts.minBorders }, walk);
  report.audio = audio.report;
  problems.push(...audio.problems);
  report.console_errors = split.errors;
  report.console_warnings = split.warnings;
  report.errors_at_exit = exitErrors;
  report.console_log = consoleLog;
  report.failed_requests = failedRequests;
  report.aborted_requests = abortedRequests.length;
  report.external_requests_answered_empty = external.length;
  report.problems = problems;
  report.ok = problems.length === 0;
  if (opts.json) writeFileSync(opts.json, JSON.stringify(audio.trace ? { ...report, trace: audio.trace } : report, null, 2) + '\n');

  const f = (x) => (typeof x === 'number' ? x.toFixed(1) : 'N/A');
  const s = (x) => (x === null || x === undefined ? 'N/A' : x);
  const c = report.continue || {};
  const t = report.travel || {};
  console.log(`${TOOL}: ${opts.fixture} (${fixture.level} at ${fixture.respawn}, stage ${s(fixture.stage)}) -> Continue -> fast travel to ${opts.travel} -> a walk of ${f(walk.metres)} m in ${f(walk.seconds)} s of game time; ${report.wall_s} s of wall time (${report.renderer}, ${report.quality}, ${opts.size})`);
  console.log(`  boot: Play to the title's music ${s(report.play_to_title_s)} s; Continue (Enter x${presses}, ${s(c.presses_ignored)} ignored) loaded ${s(c.level)} at ${s(c.respawn)}, stage ${s(c.stage)}, in ${s(c.load_s)} s (Enter to control ${s(c.enter_to_control_s)} s); the fast travel from ${s(t.from)} loaded ${s(t.arrived && t.arrived.respawn)} in ${s(t.load_s)} s (request to control ${s(t.request_to_control_s)} s; ${s(t.refusals)} refusal(s) first)`);
  console.log(`  frames while walking (page rAF): p50 ${f(raf.p50)} ms, p99 ${f(raf.p99)} ms [${report.budget.p99_ms.verdict} <= ${BUDGET_P99_MS}], worst ${f(raf.max)} ms [${report.budget.worst_ms.verdict} <= ${BUDGET_WORST_MS}] over ${raf.n} frames (indicative); the engine's (capped at 133 ms): p50 ${f(frames && frames.p50)}, p99 ${f(frames && frames.p99)}, worst ${f(frames && frames.max)} ms`);
  console.log(`  streaming: work p50 ${f(walk.work_ms_p50)} / p99 ${f(walk.work_ms_p99)} / max ${f(walk.work_ms_max)} ms; hitches (work frames over ${s(st.budget_ms)} ms) ${s(st.work_ms_over_budget)} of ${s(st.work_frames)}; heaviest steps ${heaviest.map((h) => `${h.step} ${h.max_ms} ms`).join(', ') || 'N/A'}; loads ${s(walk.loads)}, unloads ${s(walk.unloads)}, thrash ${s(walk.thrash)}, max loaded ${s(walk.max_loaded)}, margin ${f(walk.min_margin_m)} m`);
  console.log(`  the walk: ${report.walk.region_changes} region change(s) (${report.walk.regions.join(' -> ') || 'none'}), ${s(walk.seam_crossings)} seam(s), ${s(walk.stuck_teleports)} stuck teleport(s); draw calls ${report.draw_calls && report.draw_calls.max !== undefined ? `p50 ${report.draw_calls.p50}, max ${report.draw_calls.max}` : JSON.stringify(report.draw_calls)}`);
  const a = report.audio;
  const m = a.music || {};
  const mbs = (b) => (typeof b === 'number' ? (b / 1048576).toFixed(1) : 'N/A');
  console.log(`  music: ${a.music ? `${m.seconds} s across ${a.borders} region border(s) (${a.sets.join(' -> ') || 'no set'}): longest silence ${m.longest_silence_ms} ms (limit ${HOLE_MAX_MS}), runs over 50 ms ${m.silent_runs_over_50_ms} (${m.holes_while_unserved} while the main thread left the mixer unserved - ${m.holes_cut_at_disarm || 0} of them cut short by the walk's end - and ${(m.holes_elsewhere || []).length} otherwise${opts.strict ? '' : '; --strict fails every one'})` : 'not recorded'}`);
  if (a.long_tasks) console.log(`  main thread while walking: ${a.long_tasks.n} long tasks (p50 ${a.long_tasks.p50_ms} ms, longest ${a.long_tasks.max_ms} ms, ${typeof a.long_tasks.busy_share === 'number' ? Math.round(a.long_tasks.busy_share * 100) : '?'} % of the time); the driver's reads ${a.driver && a.driver.watched ? `${a.driver.reads}, longest gap ${a.driver.longest_gap_ms} ms` : 'not seen'}`);
  console.log(`  samples: peak live ${mbs(a.samples && a.samples.peak_live_bytes)} MB (cap ${mbs(a.cap_bytes)} MB = ${a.registered_s} s x 353 KB + 12 MB); console errors ${split.errors.length}, the engine's warning lines ${split.warnings.length}${opts.strict ? '' : ' (--strict fails them)'} (${exitErrors.length} more at exit, not counted); the game's own count: ${s(report.errors_counted_by_game)} error(s), ${s(report.warnings_counted_by_game)} warning(s); failed requests ${failedRequests.length}`);
  for (const e of split.errors.slice(0, 10)) console.log(`    error: ${e}`);
  for (const w of split.warnings.slice(0, 10)) console.log(`    warning: ${w}`);
  for (const e of exitErrors.slice(0, 10)) console.log(`    at exit (not counted): ${e}`);
  for (const r of failedRequests.slice(0, 10)) console.log(`    request: ${r}`);
  const crit = a.criterion || null;
  console.log(`  the plan's criterion (no silent run over ${HOLE_MAX_MS} ms in ${opts.musicS} s of music across a region border): ${crit ? (crit.met ? 'MET' : `NOT MET (${crit.holes} hole(s), the longest ${crit.longest_silence_ms} ms)`) : 'NOT MEASURED'}`);
  console.log(`WORLD_CHECK ${JSON.stringify(report)}`);
  if (report.ok) {
    console.log(crit && !crit.met
      ? `${TOOL}: OK (the plan's audio criterion NOT MET: ${crit.holes} hole(s) over ${HOLE_MAX_MS} ms, every one placed on the main thread; run --strict on a machine with a GPU for the gate)`
      : `${TOOL}: OK`);
  } else {
    console.log(`${TOOL}: FAILED - ${problems.join('; ')}`);
  }
  process.exit(report.ok ? 0 : 1);
}

// Run as a script (not when a test imports the helpers above).
if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  main().catch((e) => {
    console.error(`${TOOL}: ${e && e.stack ? e.stack : e}`);
    process.exit(1);
  });
}
