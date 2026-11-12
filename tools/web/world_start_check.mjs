#!/usr/bin/env node
// The launcher's two start buttons, end to end (plan M6-M9 §6.6; the 0.7.0-m7 release checked them by
// hand, the 0.8.0-m8 release wrote the check down): the Web release in headless Chromium, the page as a
// player opens it (play.html with no ?args=), each part in a fresh browser profile (no saved game):
//   * Play: the engine starts with no game arguments - the title - and writes no save while the title
//     shows; Enter there (New Game, the title's first focus with no saved game) starts the Valley, and
//     the first save holds "level": "level.valley";
//   * Start in the open world: one press only arms the button - its label reads "Press again to start
//     a new game in the open world", it is marked armed, the gate stays and nothing of the engine is
//     fetched; left alone it disarms after 6 s; pressed twice it starts the engine with
//     ['--', '--mode=world'], and the first save holds "level": "level.world" (its checkpoint, the
//     giant's stage and level are reported);
//   * 0 console errors and no failed request in either part.
// The engine's arguments are read where web/launcher.html hands them over: the copy of the export's
// index.js served to the page remembers the configuration the launcher's `new Engine({... args ...})`
// gets (one line added after `this.config = new InternalConfig(initConfig);`; the build's files are not
// changed). The saves are read from the page's IndexedDB (Godot's /userfs file system:
// <app_userdata>/saves/valley_1.json). The page's web fonts are answered empty, so the check needs no
// network.
// Prints one WORLD_START_CHECK {json} line and exits 0 when everything holds (1 otherwise, 2 for a
// usage error). The 0.8.0-m8 release's run is in docs/PERFORMANCE.md ("The 0.8.0-m8 release").
//
// Usage (from the project folder, after tools/build_web.sh):
//   node tools/web/world_start_check.mjs [--build=builds/web] [--size=1280x720] [--settle-s=8]
//        [--timeout-s=300] [--shots=DIR] [--json=FILE] [--headed]
//   --settle-s     seconds the title is given to draw once the engine has started, before Enter
//   --timeout-s    the longest wait for the engine to start and for each part's first save
//   --shots=DIR    also saves title.png (the title, before Enter) and world.png (the open world once
//                  its first save is written) at the viewport's size
//   --json=FILE    the report
// Needs Playwright (PLAYWRIGHT_MODULE, NODE_PATH or /opt/node-tools/node_modules) and its Chromium
// (PLAYWRIGHT_BROWSERS_PATH, default /opt/pw-browsers when that folder exists). Software WebGL
// (SwiftShader) is all a GPU-less machine has: the start and save times are indicative only.

import { createServer } from 'node:http';
import { createRequire } from 'node:module';
import { existsSync, mkdirSync, readFileSync, statSync, writeFileSync } from 'node:fs';
import { extname, join, normalize, resolve, sep } from 'node:path';

const TITLE = 'Giantborn: Age of Titans';
// web/launcher.html: the armed label, the arming's length (worldTimer = setTimeout(disarmWorld, 6000))
// and the open-world start's arguments (start(['--', '--mode=world'])).
const ARMED_LABEL = 'Press again to start a new game in the open world';
const DISARM_MS = 6000;
const WORLD_ARGS = ['--', '--mode=world'];
// A part presses Enter on the title again when no save came this long after the last press (the title
// was still drawing), at most this many times in all.
const ENTER_AGAIN_S = 45;
const ENTER_PRESSES = 3;
// Where the export's index.js builds an engine from the launcher's configuration (Godot 4.6's Engine:
// the constructor the launcher's `new Engine(...)` returns), and the line the served copy adds after it.
const ENGINE_CONFIG_LINE = 'this.config = new InternalConfig(initConfig);';
const ENGINE_HOOK = ' window.__engineArgs = Array.from(this.config.args || []); window.__engineMadeAt = performance.now();';

function parseArgs(argv) {
  const opts = { build: 'builds/web', size: '1280x720', settleS: 8, timeoutS: 300, shots: '', json: '', headed: false };
  for (const arg of argv) {
    const [key, ...rest] = arg.split('=');
    const value = rest.join('=');
    switch (key) {
      case '--build': opts.build = value; break;
      case '--size': opts.size = value; break;
      case '--settle-s': opts.settleS = Number(value); break;
      case '--timeout-s': opts.timeoutS = Number(value); break;
      case '--shots': opts.shots = value; break;
      case '--json': opts.json = value; break;
      case '--headed': opts.headed = true; break;
      case '-h': case '--help':
        console.log(readFileSync(new URL(import.meta.url), 'utf8').split('\n').slice(1).filter((l, i, all) =>
          all.slice(0, i + 1).every((x) => x.startsWith('//'))).join('\n'));
        process.exit(0);
        break;
      default:
        console.error(`world_start_check: unknown option ${arg}`);
        process.exit(2);
    }
  }
  if (!/^\d+x\d+$/.test(opts.size) || !(opts.settleS >= 0) || !(opts.timeoutS > 0)) {
    console.error('world_start_check: --size wants WxH, --settle-s a number >= 0, --timeout-s a positive number');
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
  console.error('world_start_check: Playwright not found (set PLAYWRIGHT_MODULE or NODE_PATH)');
  process.exit(1);
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

const sleep = (ms) => new Promise((ok) => setTimeout(ok, ms));

// A fresh profile's page on play.html: console errors, failed requests and the engine files it fetches
// are recorded; requests to other hosts (the web fonts) are answered empty.
async function openPage(browser, opts, origin) {
  const [width, height] = opts.size.split('x').map(Number);
  const context = await browser.newContext({ viewport: { width, height } });
  const page = await context.newPage();
  const seen = { errors: [], failed: [], aborted: [], engineFetches: [], external: 0 };
  await page.route((u) => !u.href.startsWith(origin), (route) => {
    seen.external += 1;
    const css = route.request().resourceType() === 'stylesheet';
    return route.fulfill({ status: 200, contentType: css ? 'text/css' : 'application/octet-stream', body: '' });
  });
  page.on('console', (msg) => { if (msg.type() === 'error') seen.errors.push(msg.text()); });
  page.on('pageerror', (err) => seen.errors.push(`page error: ${err.message}`));
  page.on('request', (req) => {
    if (/\/index\.(wasm|pck)\.gz\.b64(\.\d+)?\.txt$/.test(new URL(req.url()).pathname)) seen.engineFetches.push(req.url());
  });
  page.on('requestfailed', (req) => {
    const why = req.failure() ? req.failure().errorText : 'failed';
    (why === 'net::ERR_ABORTED' ? seen.aborted : seen.failed).push(`${req.url()} (${why})`);
  });
  page.on('response', (res) => { if (res.status() >= 400) seen.failed.push(`${res.url()} (${res.status()})`); });
  // The engine's arguments: the served copy of index.js remembers the configuration it is given.
  let hooked = false;
  await page.route(`${origin}/index.js`, async (route) => {
    const response = await route.fetch();
    const text = await response.text();
    hooked = text.split(ENGINE_CONFIG_LINE).length === 2;
    await route.fulfill({ response, body: hooked ? text.replace(ENGINE_CONFIG_LINE, ENGINE_CONFIG_LINE + ENGINE_HOOK) : text });
  });
  await page.goto(`${origin}/play.html`, { waitUntil: 'load' });
  const title = await page.title();
  return { context, page, seen, title, hooked };
}

// The launcher's state: the gate (shown until the engine runs), the canvas, the open-world button.
function launcherState(page) {
  return page.evaluate(() => {
    const world = document.getElementById('play-world');
    return {
      gate_shown: !document.getElementById('gate').hidden,
      canvas_shown: !document.getElementById('game-canvas').hidden,
      playing: document.body.classList.contains('playing'),
      world_label: world ? world.textContent : null,
      world_armed: world ? world.classList.contains('armed') : null,
      world_shown: world ? !world.hidden : null,
      status: document.getElementById('status').textContent,
      engine_args: window.__engineArgs === undefined ? null : window.__engineArgs,
    };
  });
}

// Waits until the engine runs (the launcher hides the gate once Engine.startGame resolves) or the
// launcher reports a failure. Returns the seconds it took, or null.
async function waitForEngine(page, timeoutS) {
  const t0 = Date.now();
  while (Date.now() - t0 < timeoutS * 1000) {
    const s = await launcherState(page);
    if (!s.gate_shown) return Math.round((Date.now() - t0) / 100) / 10;
    if (/could not|cannot|did not|stopped/i.test(s.status)) return null;
    await sleep(250);
  }
  return null;
}

// The saves in the page's IndexedDB (Godot's /userfs): { path: text }. Never creates the database:
// an open that would create it is aborted.
function readSaves(page) {
  return page.evaluate(() => new Promise((ok) => {
    let req;
    try {
      req = indexedDB.open('/userfs');
    } catch (e) {
      ok({});
      return;
    }
    req.onupgradeneeded = () => req.transaction.abort();
    req.onerror = () => ok({});
    req.onblocked = () => ok({});
    req.onsuccess = () => {
      const db = req.result;
      db.onversionchange = () => db.close();
      if (!db.objectStoreNames.contains('FILE_DATA')) {
        db.close();
        ok({});
        return;
      }
      const out = {};
      const cursor = db.transaction('FILE_DATA', 'readonly').objectStore('FILE_DATA').openCursor();
      cursor.onsuccess = () => {
        const c = cursor.result;
        if (!c) {
          db.close();
          ok(out);
          return;
        }
        const key = String(c.key);
        if (/\/saves\/[^/]+\.json$/.test(key) && c.value && c.value.contents) {
          out[key] = new TextDecoder().decode(c.value.contents);
        }
        c.continue();
      };
      cursor.onerror = () => {
        db.close();
        ok(out);
      };
    };
  }));
}

// The save slot's document (saves/valley_1.json), or null while there is none.
async function readSlot(page) {
  const saves = await readSaves(page);
  const path = Object.keys(saves).find((p) => p.endsWith('/saves/valley_1.json'));
  if (!path) return null;
  try {
    return { path, doc: JSON.parse(saves[path]) };
  } catch (e) {
    return { path, doc: null, unreadable: String(e && e.message ? e.message : e) };
  }
}

function saveSummary(slot) {
  if (!slot || !slot.doc) return slot ? { path: slot.path, unreadable: slot.unreadable || 'no document' } : null;
  const d = slot.doc;
  const cp = d.checkpoint || {};
  const ch = d.character || {};
  return {
    path: slot.path, level: d.level, build_version: d.build_version, respawn: cp.respawn, reason: cp.reason,
    growth_stage: ch.growth_stage, character_level: ch.level, world_entered: d.progress ? d.progress.world_entered : undefined,
  };
}

// Waits for the slot's first save that reads as a document (a file caught mid-sync is read again);
// presses Enter again (pressEnter) when none came ENTER_AGAIN_S after the last press. Returns
// { slot, seconds, presses } (slot: the last one seen, null when there was none).
async function waitForSave(page, timeoutS, pressEnter) {
  const t0 = Date.now();
  let presses = pressEnter ? 1 : 0;
  let lastPress = Date.now();
  let last = null;
  while (Date.now() - t0 < timeoutS * 1000) {
    const slot = await readSlot(page);
    if (slot && slot.doc) return { slot, seconds: Math.round((Date.now() - t0) / 100) / 10, presses };
    if (slot) last = slot;
    if (pressEnter && last === null && presses < ENTER_PRESSES && Date.now() - lastPress > ENTER_AGAIN_S * 1000) {
      await page.keyboard.press('Enter');
      presses += 1;
      lastPress = Date.now();
    }
    await sleep(500);
  }
  return { slot: last, seconds: null, presses };
}

// Play: the title, then New Game into the Valley.
async function partPlay(browser, opts, origin) {
  const { context, page, seen, title, hooked } = await openPage(browser, opts, origin);
  const problems = [];
  const out = { page_title: title };
  if (title !== TITLE) problems.push(`the page is "${title}", not ${TITLE}`);
  if (!hooked) problems.push(`index.js has no single "${ENGINE_CONFIG_LINE}" to read the engine's arguments at`);
  await page.click('#play');
  out.engine_start_s = await waitForEngine(page, opts.timeoutS);
  const state = await launcherState(page);
  out.engine_args = state.engine_args;
  if (out.engine_start_s === null) {
    problems.push(`the engine did not start within ${opts.timeoutS} s (status: ${state.status})`);
  } else {
    if (!Array.isArray(state.engine_args) || state.engine_args.length !== 0) {
      problems.push(`Play started the engine with arguments ${JSON.stringify(state.engine_args)} (none wanted: the title)`);
    }
    await sleep(opts.settleS * 1000);
    if (opts.shots) await page.screenshot({ path: join(opts.shots, 'title.png') });
    const atTitle = await readSlot(page);
    out.save_at_title = saveSummary(atTitle);
    if (atTitle) problems.push('a save was written while the title showed');
    await page.keyboard.press('Enter');
    const saved = await waitForSave(page, opts.timeoutS, true);
    out.enter_presses = saved.presses;
    out.first_save_s = saved.seconds;
    out.first_save = saveSummary(saved.slot);
    if (!saved.slot) problems.push(`no save within ${opts.timeoutS} s of Enter on the title`);
    else if (!saved.slot.doc || saved.slot.doc.level !== 'level.valley') {
      problems.push(`the first save after New Game holds level ${JSON.stringify(out.first_save && out.first_save.level)} (level.valley wanted)`);
    }
  }
  await context.close();
  return finish(out, seen, problems);
}

// Start in the open world: one press arms, the arming lapses, two presses start --mode=world.
async function partWorld(browser, opts, origin) {
  const { context, page, seen, title, hooked } = await openPage(browser, opts, origin);
  const problems = [];
  const out = { page_title: title };
  if (!hooked) problems.push(`index.js has no single "${ENGINE_CONFIG_LINE}" to read the engine's arguments at`);
  const before = await launcherState(page);
  out.label = before.world_label;
  await page.click('#play-world');
  await sleep(1500);
  const armed = await launcherState(page);
  out.after_one_press = { label: armed.world_label, armed: armed.world_armed, gate_shown: armed.gate_shown,
    canvas_shown: armed.canvas_shown, engine_started: armed.engine_args !== null, engine_files_fetched: seen.engineFetches.length };
  if (armed.world_label !== ARMED_LABEL || !armed.world_armed) problems.push(`one press: the button reads "${armed.world_label}" (armed ${armed.world_armed})`);
  if (!armed.gate_shown || armed.canvas_shown || armed.playing || armed.engine_args !== null || seen.engineFetches.length > 0) {
    problems.push('one press started the game');
  }
  await sleep(DISARM_MS + 1000 - 1500);
  const lapsed = await launcherState(page);
  out.after_the_arming_lapsed = { label: lapsed.world_label, armed: lapsed.world_armed, engine_started: lapsed.engine_args !== null };
  if (lapsed.world_label !== before.world_label || lapsed.world_armed || lapsed.engine_args !== null) {
    problems.push(`${DISARM_MS / 1000} s after one press the button reads "${lapsed.world_label}" (armed ${lapsed.world_armed}; it should disarm)`);
  }
  await page.click('#play-world');
  const again = await launcherState(page);
  if (!again.world_armed || again.engine_args !== null) problems.push('the press after the arming lapsed did not just arm it again');
  await page.click('#play-world');
  out.engine_start_s = await waitForEngine(page, opts.timeoutS);
  const state = await launcherState(page);
  out.engine_args = state.engine_args;
  if (out.engine_start_s === null) {
    problems.push(`the second press did not start the engine within ${opts.timeoutS} s (status: ${state.status})`);
  } else {
    if (JSON.stringify(state.engine_args) !== JSON.stringify(WORLD_ARGS)) {
      problems.push(`the engine started with ${JSON.stringify(state.engine_args)} (${JSON.stringify(WORLD_ARGS)} wanted)`);
    }
    const saved = await waitForSave(page, opts.timeoutS, false);
    out.first_save_s = saved.seconds;
    out.first_save = saveSummary(saved.slot);
    if (!saved.slot) problems.push(`no save within ${opts.timeoutS} s of the open-world start`);
    else if (!saved.slot.doc || saved.slot.doc.level !== 'level.world') {
      problems.push(`the first save holds level ${JSON.stringify(out.first_save && out.first_save.level)} (level.world wanted)`);
    }
    if (opts.shots && saved.slot) {
      await sleep(2000);
      await page.screenshot({ path: join(opts.shots, 'world.png') });
    }
  }
  await context.close();
  return finish(out, seen, problems);
}

function finish(out, seen, problems) {
  out.console_errors = seen.errors;
  out.failed_requests = seen.failed;
  out.aborted_requests = seen.aborted.length;
  out.external_requests_answered_empty = seen.external;
  if (seen.errors.length > 0) problems.push(`${seen.errors.length} console error(s)`);
  if (seen.failed.length > 0) problems.push(`${seen.failed.length} failed request(s)`);
  out.problems = problems;
  out.ok = problems.length === 0;
  return out;
}

async function main() {
  const opts = parseArgs(process.argv.slice(2));
  if (!existsSync(join(opts.build, 'play.html'))) {
    console.error(`world_start_check: ${opts.build}/play.html is missing: run tools/build_web.sh first`);
    process.exit(1);
  }
  if (opts.shots) mkdirSync(opts.shots, { recursive: true });
  if (!process.env.PLAYWRIGHT_BROWSERS_PATH && existsSync('/opt/pw-browsers')) {
    process.env.PLAYWRIGHT_BROWSERS_PATH = '/opt/pw-browsers';
  }
  const { chromium } = loadPlaywright();
  const server = await serve(opts.build);
  const origin = `http://127.0.0.1:${server.address().port}`;
  const browser = await chromium.launch({
    headless: !opts.headed,
    args: ['--use-angle=swiftshader', '--enable-unsafe-swiftshader', '--ignore-gpu-blocklist', '--autoplay-policy=no-user-gesture-required'],
  });
  const started = Date.now();
  console.log(`world_start_check: ${origin}/play.html (${opts.build}, ${opts.size})`);
  const play = await partPlay(browser, opts, origin);
  const world = await partWorld(browser, opts, origin);
  await browser.close();
  server.close();
  const report = { build: opts.build, viewport: opts.size, wall_s: Math.round((Date.now() - started) / 100) / 10, play, world };
  report.problems = [...play.problems.map((p) => `Play: ${p}`), ...world.problems.map((p) => `open world: ${p}`)];
  report.ok = report.problems.length === 0;
  if (opts.json) writeFileSync(opts.json, JSON.stringify(report, null, 2) + '\n');

  const s = (x) => (x === null || x === undefined ? 'N/A' : x);
  const fs = play.first_save || {};
  console.log(`  Play: the engine started in ${s(play.engine_start_s)} s with arguments ${JSON.stringify(play.engine_args)}; no save while the title showed: ${play.save_at_title ? 'NO' : 'yes'}; Enter (${s(play.enter_presses)} press(es)) -> the first save ${s(play.first_save_s)} s later holds "level": ${JSON.stringify(fs.level)} (respawn ${s(fs.respawn)}); console errors ${play.console_errors.length}, failed requests ${play.failed_requests.length}`);
  const w1 = world.after_one_press || {};
  const wl = world.after_the_arming_lapsed || {};
  const ws = world.first_save || {};
  console.log(`  Start in the open world: one press -> "${s(w1.label)}" (armed ${s(w1.armed)}, gate shown ${s(w1.gate_shown)}, engine started ${s(w1.engine_started)}, engine files fetched ${s(w1.engine_files_fetched)}); ${DISARM_MS / 1000} s later "${s(wl.label)}" (armed ${s(wl.armed)})`);
  console.log(`    two presses -> the engine started in ${s(world.engine_start_s)} s with ${JSON.stringify(world.engine_args)}; the first save ${s(world.first_save_s)} s later holds "level": ${JSON.stringify(ws.level)}, respawn ${s(ws.respawn)}, stage ${s(ws.growth_stage)}, level ${s(ws.character_level)}; console errors ${world.console_errors.length}, failed requests ${world.failed_requests.length}`);
  for (const e of [...play.console_errors, ...world.console_errors].slice(0, 10)) console.log(`    error: ${e}`);
  for (const r of [...play.failed_requests, ...world.failed_requests].slice(0, 10)) console.log(`    request: ${r}`);
  console.log(`WORLD_START_CHECK ${JSON.stringify(report)}`);
  console.log(report.ok ? 'world_start_check: OK' : `world_start_check: FAILED - ${report.problems.join('; ')}`);
  process.exit(report.ok ? 0 : 1);
}

main().catch((e) => {
  console.error(`world_start_check: ${e && e.stack ? e.stack : e}`);
  process.exit(1);
});
