#!/usr/bin/env node
// The web creator check (P45; plan M10 §3.5 item 2, §2.12 "Shader stalls"): the character creator and the
// realistic giant as a player meets them in the Web release, in headless Chromium, with the keyboard.
// The game runs with --ui-probe (scripts/debug/ui_probe.gd): it prints what the menus show (UI_PROBE
// state lines: the top screen, the focus, the creator's category, ...) and, at each mark, the longest of
// the three frames after it against the median of the forty that follow (UI_PROBE stall lines). The
// check presses the keys a player would and follows those lines; it never reaches into the game.
// Two parts, each in a fresh browser profile:
//   * new_game: Play -> the title; its worst frame until New Game enables (the mark "title"); Enter
//     (New Game, the title's first focus with no saved game) -> the creator (the mark "creator": its first
//     frame); PageDown changes the category; R randomizes it (the look is changed, one step of history);
//     Ctrl+Z undoes it (unchanged again); R once more; a screenshot (creator.png); Ctrl+Enter (Begin) ->
//     the Valley loads (the mark "level": its first frame once the loading screen lets go), the pointer
//     lock asked for while the press still counts as the player's gesture; the first save holds
//     "level": "level.valley" and the look made in the creator; the giant draws the 1024 px maps (the
//     texture tier "hi": the owner's answer 1, plan M10 §0.6); a third-person screenshot (valley.png);
//   * shrine: a world save at a shrine (the fixture of tools/web/world_check.json, a save from before the
//     creator: it has no look) in the page's IndexedDB; Play; Enter (Continue) -> the world; E at the
//     shrine ("Rest at ..."; a step back first when the giant does not face it) -> the shrine screen; Up to
//     the tab buttons and Right until the Appearance tab has the focus, Enter; Down to "Change your look...", Enter -> the creator
//     over the shrine (the mark "shrine_creator": its first frame); a screenshot (shrine_creator.png).
//   * the skin's CPU a frame (the game's --ui-probe-bench: the player's rig - the tree's drive and
//     advance, the skeleton's update and the pose modifier - in a tight loop once a mark's frames are
//     done): in the Valley with the player alone, in the world, and with the creator's preview open over
//     the shrine (two skinned giants in the tree); over 0.35 ms is a MISS (plan M10 §2.12);
//   * 0 console errors (the engine's warnings are listed apart) and no failed request in either part.
// Every stall is judged against the run's own median frame: a mark's first frame may take 3 median frames
// (--stall-ratio; under 25 ms is never a stall). Software WebGL (SwiftShader) is all a GPU-less machine
// has, so by default a stall over that is reported as a MISS and the check passes; --strict fails on it.
// The page's own clock is reported beside the game's: the main thread's time inside each animation frame
// (the engine's whole frame in a no-threads build), its median and its worst per part.
// Prints one CREATOR_CHECK {json} line and exits 0 when everything holds (1 otherwise, 2 for a usage error).
//
// Usage (from the project folder, after tools/build_web.sh):
//   node tools/web/creator_check.mjs [--build=builds/web] [--size=960x540] [--timeout-s=600]
//        [--parts=new_game,shrine] [--fixture=FILE] [--stall-ratio=3] [--strict] [--args=a,b]
//        [--shots=DIR] [--json=FILE] [--headed]
//   --timeout-s    the longest wait for any one step (the engine's start, a level's load)
//   --args=a,b     more game arguments after --ui-probe (the test's stub reads its mode from them)
//   --fixture      the world save for the shrine part (default: tools/web/world_check.json's)
//   --shots=DIR    saves title.png, creator.png, valley.png, world_shrine.png and shrine_creator.png
// Needs Playwright (PLAYWRIGHT_MODULE, NODE_PATH or /opt/node-tools/node_modules) and its Chromium
// (PLAYWRIGHT_BROWSERS_PATH, default /opt/pw-browsers when that folder exists). Its own test is
// tools/web/test_creator_check.mjs (a stub launcher, no engine).

// M10 gate (LD-1): a memory guard (tools/web/memory_guard.mjs) watches the page's renderer process: over about 3 GB
// (GIANT_WEB_GUARD_MB; 0 = off) the run stops with a FAILED line naming the memory instead of taking the machine down.
import { startMemoryGuard } from './memory_guard.mjs';
import { existsSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { loadPlaywright, serve } from './stream_check.mjs';
import { IDB_NAME, IDB_STORE, IDB_VERSION, SAVE_PATH, readSaveInPage, splitWarnings, writeSaveInPage } from './world_check.mjs';

const TOOL = 'creator_check';
const ROOT = resolve(dirname(fileURLToPath(import.meta.url)), '..', '..');
const TITLE = 'Giantborn: Age of Titans';
const TAG = 'UI_PROBE';
// web/launcher.html's open-world start (world_start_check.mjs presses the button; this check reads the
// same arguments from the launcher's text, so the two cannot drift apart).
const WORLD_ARGS = ['--', '--mode=world', '--creator'];
// scripts/debug/ui_probe.gd: STALL_RATIO and STALL_FLOOR_MS.
export const STALL_RATIO = 3;
export const STALL_FLOOR_MS = 25;
// Plan M10 §2.12: the skin's CPU a frame on the Web (the player's giant).
export const SKIN_MS_WEB = 0.35;
// The screens' own words (ui/screens/title_screen.gd, shrine/appearance_tab.gd, scripts/world/shrine.gd).
const NEW_GAME = 'New Game';
const CONTINUE = 'Continue';
const APPEARANCE_TAB = 'Appearance';
const CHANGE_LOOK = 'Change your look...';
const REST_PROMPT = 'Rest';
const DIR_MODE = 0o40775;
const FILE_MODE = 0o100666;
const PARTS = ['new_game', 'shrine'];

function usage(message) {
  console.error(`${TOOL}: ${message}`);
  process.exit(2);
}

export function parseArgs(argv) {
  const opts = { build: 'builds/web', size: '960x540', timeoutS: 600, parts: PARTS.slice(), fixture: '', stallRatio: STALL_RATIO,
    strict: false, args: '', shots: '', json: '', headed: false };
  for (const arg of argv) {
    const [key, ...rest] = arg.split('=');
    const value = rest.join('=');
    switch (key) {
      case '--build': opts.build = value; break;
      case '--size': opts.size = value; break;
      case '--timeout-s': opts.timeoutS = Number(value); break;
      case '--parts': opts.parts = value.split(',').map((x) => x.trim()).filter((x) => x.length > 0); break;
      case '--fixture': opts.fixture = value; break;
      case '--stall-ratio': opts.stallRatio = Number(value); break;
      case '--strict': opts.strict = true; break;
      case '--args': opts.args = value; break;
      case '--shots': opts.shots = value; break;
      case '--json': opts.json = value; break;
      case '--headed': opts.headed = true; break;
      case '-h': case '--help':
        console.log(readFileSync(new URL(import.meta.url), 'utf8').split('\n').slice(1).filter((l, i, all) =>
          all.slice(0, i + 1).every((x) => x.startsWith('//'))).join('\n'));
        process.exit(0);
        break;
      default: usage(`unknown option ${arg}`);
    }
  }
  if (!/^\d+x\d+$/.test(opts.size) || !(opts.timeoutS > 0) || !(opts.stallRatio > 0)) {
    usage('--size wants WxH, --timeout-s and --stall-ratio positive numbers');
  }
  if (opts.parts.length === 0 || opts.parts.some((p) => !PARTS.includes(p))) usage(`--parts wants a list of ${PARTS.join(', ')}`);
  opts.gameArgs = ['--ui-probe', '--ui-probe-bench', ...opts.args.split(',').map((x) => x.trim()).filter((x) => x.length > 0)];
  if (!opts.fixture) {
    const config = JSON.parse(readFileSync(join(ROOT, 'tools', 'web', 'world_check.json'), 'utf8'));
    opts.fixture = join(ROOT, config.fixture);
  }
  return opts;
}

// §2.12: a mark's first frame is no stall within `ratio` median frames (or under the floor).
export function stallOk(firstMs, medianMs, ratio = STALL_RATIO) {
  return firstMs <= STALL_FLOOR_MS || (medianMs > 0 && firstMs <= ratio * medianMs);
}

export function median(values) {
  if (values.length === 0) return 0;
  const v = values.slice().sort((a, b) => a - b);
  const n = v.length;
  return n % 2 === 1 ? v[(n - 1) / 2] : (v[n / 2 - 1] + v[n / 2]) / 2;
}

const sleep = (ms) => new Promise((ok) => setTimeout(ok, ms));
const round1 = (x) => (typeof x === 'number' ? Math.round(x * 10) / 10 : null);

// Runs in the page before anything else: the main thread's time inside each animation frame
// (window.__work: [end, ms]) and every pointer-lock request with whether it came inside a gesture.
// P49: also what each animation frame asked of WebGL that a steady frame does not (window.__glf: [frame's
// end, shaders compiled, programs linked, textures allocated, textures updated in place, framebuffers and
// renderbuffers made], frames with none left out; "megabytes" was dropped for a count of texture updates: the
// engine hands WebGL its whole heap and an offset, so a call's bytes cannot be read from its arguments) and when each UI_PROBE state line was printed
// (window.__states: [page time, top, loading, level]) - so a mark's first frames can be told from the
// frames after them by what they made the renderer do (glOfMark).
function instrument() {
  window.__work = [];
  window.__locks = [];
  window.__glf = [];
  window.__states = [];
  const gl = [0, 0, 0, 0, 0];
  const raf = window.requestAnimationFrame.bind(window);
  window.requestAnimationFrame = (cb) => raf((t) => {
    const t0 = performance.now();
    try {
      return cb(t);
    } finally {
      const t1 = performance.now();
      window.__work.push([t1, t1 - t0]);
      if (window.__work.length > 20000) window.__work.splice(0, 10000);
      if (gl[0] || gl[1] || gl[2] || gl[3] || gl[4]) {
        if (window.__glf.length < 20000) window.__glf.push([t1, gl[0], gl[1], gl[2], gl[3], gl[4]]);
        gl[0] = gl[1] = gl[2] = gl[3] = gl[4] = 0;
      }
    }
  });
  const proto = window.WebGL2RenderingContext && WebGL2RenderingContext.prototype;
  if (proto) {
    const count = (name, slot) => {
      const orig = proto[name];
      if (typeof orig !== 'function') return;
      proto[name] = function (...a) {
        gl[slot] += 1;
        return orig.apply(this, a);
      };
    };
    count('compileShader', 0);
    count('linkProgram', 1);
    for (const name of ['texImage2D', 'texImage3D', 'texStorage2D', 'texStorage3D', 'compressedTexImage2D', 'compressedTexImage3D']) count(name, 2);
    for (const name of ['texSubImage2D', 'texSubImage3D', 'compressedTexSubImage2D', 'compressedTexSubImage3D']) count(name, 3);
    for (const name of ['createFramebuffer', 'renderbufferStorage', 'renderbufferStorageMultisample']) count(name, 4);
  }
  const log = console.log.bind(console);
  console.log = (...items) => {
    const text = items.length === 1 && typeof items[0] === 'string' ? items[0] : '';
    if (text.startsWith('UI_PROBE ') && text.includes('"t":"state"') && window.__states.length < 5000) {
      try {
        const o = JSON.parse(text.slice(9));
        window.__states.push([performance.now(), o.top, o.loading, o.level]);
      } catch (e) { /* not a state line */ }
    }
    log(...items);
  };
  const lock = Element.prototype.requestPointerLock;
  Element.prototype.requestPointerLock = function (...args) {
    const ua = navigator.userActivation;
    window.__locks.push({ at: performance.now(), in_gesture: ua ? ua.isActive : null, element: this.id || this.tagName });
    try {
      const r = lock.apply(this, args);
      if (r && typeof r.catch === 'function') r.catch(() => {});
      return r;
    } catch (e) {
      return undefined;
    }
  };
}

// One part's page: the probe's lines, the console's errors, failed requests; other hosts answered empty.
async function openPart(browser, opts, origin, args) {
  const [width, height] = opts.size.split('x').map(Number);
  const context = await browser.newContext({ viewport: { width, height } });
  const page = await context.newPage();
  await page.addInitScript(instrument);
  const seen = { errors: [], failed: [], aborted: 0, external: 0, states: [], stalls: {}, benches: [], lines: 0 };
  await page.route((u) => !u.href.startsWith(origin), (route) => {
    seen.external += 1;
    const css = route.request().resourceType() === 'stylesheet';
    return route.fulfill({ status: 200, contentType: css ? 'text/css' : 'application/octet-stream', body: '' });
  });
  const started = Date.now();
  page.on('console', (msg) => {
    const text = msg.text();
    seen.lines += 1;
    if (msg.type() === 'error') seen.errors.push(text);
    if (!text.startsWith(`${TAG} `)) return;
    let line;
    try {
      line = JSON.parse(text.slice(TAG.length + 1));
    } catch (e) {
      seen.errors.push(`unreadable ${TAG} line: ${text.slice(0, 200)}`);
      return;
    }
    line.wall_s = round1((Date.now() - started) / 1000);
    if (line.t === 'state') seen.states.push(line);
    else if (line.t === 'stall' && !(line.mark in seen.stalls)) seen.stalls[line.mark] = line;
    else if (line.t === 'bench') seen.benches.push(line);
  });
  page.on('pageerror', (err) => seen.errors.push(`page error: ${err.message}`));
  page.on('requestfailed', (req) => {
    const why = req.failure() ? req.failure().errorText : 'failed';
    if (why === 'net::ERR_ABORTED') seen.aborted += 1;
    else seen.failed.push(`${req.url()} (${why})`);
  });
  page.on('response', (res) => { if (res.status() >= 400) seen.failed.push(`${res.url()} (${res.status()})`); });
  const url = `${origin}/play.html?args=${args.map(encodeURIComponent).join(',')}`;
  await page.goto(url, { waitUntil: 'load' });
  const state = () => (seen.states.length > 0 ? seen.states[seen.states.length - 1] : {});
  // Waits until `test(state)` holds (true) or the step's time is up (false).
  const until = async (test, timeoutS = opts.timeoutS) => {
    const end = Date.now() + timeoutS * 1000;
    while (Date.now() < end) {
      if (test(state())) return true;
      await sleep(100);
    }
    return test(state());
  };
  const stall = async (mark, timeoutS = opts.timeoutS) => {
    const end = Date.now() + timeoutS * 1000;
    while (Date.now() < end && !(mark in seen.stalls)) await sleep(100);
    return seen.stalls[mark] || null;
  };
  const note = (what) => console.log(`  [${round1((Date.now() - started) / 1000)} s] ${what}`);
  const press = async (key) => {
    await page.focus('#game-canvas').catch(() => {});
    await page.keyboard.press(key);
  };
  const shot = async (name) => {
    if (opts.shots) await page.screenshot({ path: join(opts.shots, name) });
  };
  return { context, page, seen, url, state, until, stall, press, shot, note };
}

// P49: of a mark's longest first frame, the share the rendering server spent drawing (0-1; null when the
// probe gave no draw times).
export function drawShare(line) {
  if (!line || !Array.isArray(line.first) || !Array.isArray(line.first_draw) || line.first.length === 0) return null;
  let at = 0;
  for (let i = 1; i < line.first.length; i++) if (line.first[i] > line.first[at]) at = i;
  const whole = line.first[at];
  const draw = line.first_draw[at];
  return whole > 0 && typeof draw === 'number' ? Math.round(Math.min(1, draw / whole) * 100) / 100 : null;
}

// P49: what a mark's first frames asked of WebGL against the frames after them. `work` is the page's
// [frame end, ms] list, `glf` its [frame end, compiles, links, texture allocations, texture updates, framebuffers]
// list (frames with none left out), `at` the page time the mark's state line was printed. Returns
// { first: {...}, steady: {...} }: the sums over the FIRST_FRAMES frames that end after `at` and over the
// STEADY_FRAMES after those (null when the mark's time is not known).
export const FIRST_FRAMES = 3;
export const STEADY_FRAMES = 40;
export function glOfMark(work, glf, at) {
  if (typeof at !== 'number' || !Array.isArray(work)) return null;
  const from = work.findIndex((w) => w[0] >= at);
  if (from < 0) return null;
  const sum = (a, b) => {
    const out = { frames: 0, shaders_compiled: 0, programs_linked: 0, textures_allocated: 0, texture_updates: 0, framebuffers: 0 };
    if (a >= work.length) return out;
    const t0 = a > 0 ? work[a - 1][0] : -Infinity;
    const t1 = work[Math.min(b, work.length) - 1][0];
    out.frames = Math.min(b, work.length) - a;
    for (const f of glf || []) {
      if (f[0] <= t0 || f[0] > t1) continue;
      out.shaders_compiled += f[1];
      out.programs_linked += f[2];
      out.textures_allocated += f[3];
      out.texture_updates += f[4];
      out.framebuffers += f[5];
    }
    return out;
  };
  return { first: sum(from, from + FIRST_FRAMES), steady: sum(from + FIRST_FRAMES, from + FIRST_FRAMES + STEADY_FRAMES) };
}

// The page time of a mark's state line among `states` ([page time, top, loading, level]).
export function markTime(states, mark) {
  const test = {
    creator: (x) => x[1] === 'creator',
    shrine_creator: (x) => x[1] === 'creator',
    level: (x) => typeof x[3] === 'string' && x[3].startsWith('level.') && x[2] === false && x[1] === '',
  }[mark];
  if (!test) return null;
  const hit = (states || []).find(test);
  return hit ? hit[0] : null;
}

// The part's verdict on a mark: its stall line, the miss when it is over the ratio.
function judge(out, misses, problems, mark, line, opts, what) {
  if (!line) {
    problems.push(`${what}: no "${mark}" stall line from the probe`);
    return;
  }
  const ok = stallOk(line.first_ms, line.median_ms, opts.stallRatio);
  out.stalls[mark] = { first_ms: line.first_ms, median_ms: line.median_ms, ratio: line.ratio, frames: line.frames, ok,
    ...(line.load_worst_ms !== undefined ? { load_worst_ms: line.load_worst_ms } : {}),
    ...(line.warmed !== undefined ? { warmed: line.warmed } : {}),
    // P49: the first frames and how much of each the rendering server spent drawing (the probe's "first"
    // and "first_draw": a shader compiled on first use is in the draw, the rest is the frame's scripts),
    // with the steady frames' median draw - which of the two a stall is made of.
    ...(Array.isArray(line.first_draw) ? { first: line.first, first_draw: line.first_draw, median_draw_ms: line.median_draw_ms,
      first_frame_draw_share: drawShare(line) } : {}) };
  const share = drawShare(line);
  if (!ok) misses.push(`${what}: ${line.first_ms} ms against a median frame of ${line.median_ms} ms (${line.ratio}x, over ${opts.stallRatio}x${share === null ? '' : `; ${Math.round(share * 100)} % of that frame was the renderer's draw`})`);
}

async function finish(part, out, problems, misses, opts) {
  const { page, seen, context } = part;
  const work = await page.evaluate(() => window.__work.map((w) => w[1])).catch(() => []);
  // P49: what each mark's first frames made the renderer do (shaders, textures, framebuffers).
  const traced = await page.evaluate(() => ({ work: window.__work, glf: window.__glf, states: window.__states })).catch(() => null);
  if (traced) {
    for (const mark of Object.keys(out.stalls)) {
      const gl = glOfMark(traced.work, traced.glf, markTime(traced.states, mark));
      if (gl) out.stalls[mark].gl = gl;
    }
  }
  // The skin's CPU a frame (--ui-probe-bench: the player's rig in a tight loop when a mark's frames are done).
  out.skin_bench = seen.benches.map((b) => ({ mark: b.mark, skin_ms: b.skin_ms, giants: b.giants, modifier_runs: b.modifier_runs, paused: b.paused }));
  for (const b of out.skin_bench) {
    if (b.skin_ms > SKIN_MS_WEB) misses.push(`the skin's CPU a frame after "${b.mark}" (${b.giants} giant(s)): ${b.skin_ms} ms (at most ${SKIN_MS_WEB} ms on the Web)`);
  }
  out.page_frames = { count: work.length, median_work_ms: round1(median(work)), worst_work_ms: round1(Math.max(0, ...work)) };
  await context.close();
  const split = splitWarnings(seen.errors);
  out.console_errors = split.errors;
  out.engine_warnings = split.warnings;
  out.failed_requests = seen.failed;
  out.console_lines = seen.lines;
  out.last_state = part.state();
  if (split.errors.length > 0) problems.push(`${split.errors.length} console error(s)`);
  if (seen.failed.length > 0) problems.push(`${seen.failed.length} failed request(s)`);
  out.misses = misses;
  if (opts.strict) for (const m of misses) problems.push(`a budget miss (--strict): ${m}`);
  out.problems = problems;
  out.ok = problems.length === 0;
  return out;
}

// Play -> the title -> New Game -> the creator -> Begin -> the Valley.
async function partNewGame(browser, opts, origin) {
  const part = await openPart(browser, opts, origin, opts.gameArgs);
  const { page, state, until, stall, press, shot, note } = part;
  const problems = [];
  const misses = [];
  const out = { url: part.url, stalls: {} };
  const steps = async () => {
    if ((await page.title()) !== TITLE) problems.push(`the page is "${await page.title()}", not ${TITLE}`);
    const t0 = Date.now();
    await page.click('#play');
    if (!(await until((s) => s.top === 'title' && s.warming === false))) return problems.push('the title never came (or never finished preparing)');
    out.play_to_title_s = round1((Date.now() - t0) / 1000);
    note('new_game: the title is ready');
    out.title_warmed = part.seen.states.some((s) => s.top === 'title' && s.warming === true);
    judge(out, misses, problems, 'title', await stall('title'), opts, 'the title\'s worst frame until New Game enables');
    await shot('title.png');
    if (!String(state().focus).startsWith(NEW_GAME)) return problems.push(`the title's focus is "${state().focus}", not ${NEW_GAME}`);
    await press('Enter');
    if (!(await until((s) => s.top === 'creator'))) return problems.push('Enter on New Game did not open the creator');
    out.creator_context = state().context;
    note('new_game: the creator is open');
    if (state().context !== 'new_game') problems.push(`the creator opened for "${state().context}", not a new game`);
    judge(out, misses, problems, 'creator', await stall('creator'), opts, 'the creator\'s first frame');
    out.creator_tiers = state().tiers;
    // a category with the keyboard, a change, Undo
    const first = state().category;
    await press('PageDown');
    if (!(await until((s) => s.top === 'creator' && s.category !== first, 30))) return problems.push(`PageDown left the category at "${first}"`);
    out.categories = [first, state().category];
    await press('r');
    if (!(await until((s) => s.changed === true && s.history >= 1, 30))) return problems.push('R did not change the look');
    await press('Control+z');
    if (!(await until((s) => s.changed === false && s.history === 0, 30))) return problems.push('Ctrl+Z did not undo the change');
    out.undo = true;
    await press('r');
    if (!(await until((s) => s.changed === true, 30))) return problems.push('R did not change the look again');
    await sleep(1500);
    await shot('creator.png');
    // Begin: the Valley loads; the pointer lock is asked for inside the press
    const locksBefore = await page.evaluate(() => window.__locks.length);
    const t1 = Date.now();
    await press('Control+Enter');
    if (!(await until((s) => s.level === 'level.valley' && s.loading === false && s.top === ''))) return problems.push('Begin did not load the Valley');
    out.begin_to_valley_s = round1((Date.now() - t1) / 1000);
    note('new_game: the Valley is loaded');
    const locks = (await page.evaluate(() => window.__locks.slice())).slice(locksBefore);
    out.pointer_lock = { requests: locks.length, in_gesture: locks.length > 0 ? locks[0].in_gesture : null,
      locked: await page.evaluate(() => document.pointerLockElement !== null) };
    if (locks.length === 0) problems.push('Begin asked for no pointer lock');
    else if (locks[0].in_gesture === false) problems.push('Begin asked for the pointer lock outside the player\'s gesture');
    judge(out, misses, problems, 'level', await stall('level'), opts, 'the Valley\'s first frame');
    out.level_tiers = state().tiers;
    if (!(state().tiers || []).includes('hi')) problems.push(`the giant draws the texture tier ${JSON.stringify(state().tiers)} (hi wanted: tex_hi/ is in the Web pack)`);
    await sleep(2500);
    await shot('valley.png');
    // the first save: the Valley, with the look made in the creator
    let text = null;
    const end = Date.now() + 60000;
    while (Date.now() < end && !text) {
      text = await page.evaluate(readSaveInPage, { dbName: IDB_NAME, store: IDB_STORE, path: SAVE_PATH }).catch(() => null);
      if (!text) await sleep(1000);
    }
    let doc = null;
    try {
      doc = text ? JSON.parse(text) : null;
    } catch (e) {
      doc = null;
    }
    const look = doc && doc.character ? doc.character.appearance : null;
    out.first_save = doc ? { level: doc.level, has_appearance: !!look && typeof look === 'object' && Object.keys(look).length > 0 } : null;
    if (!doc) problems.push('no save a minute after the Valley loaded');
    else {
      if (doc.level !== 'level.valley') problems.push(`the first save holds level ${JSON.stringify(doc.level)} (level.valley wanted)`);
      if (!out.first_save.has_appearance) problems.push('the first save holds no look (character.appearance)');
    }
    return null;
  };
  await steps().catch((e) => problems.push(`the part broke: ${e && e.message ? e.message : e}`));
  return finish(part, out, problems, misses, opts);
}

// A world save at a shrine -> Continue -> the shrine's Appearance tab -> "Change your look...".
async function partShrine(browser, opts, origin) {
  const part = await openPart(browser, opts, origin, opts.gameArgs);
  const { page, state, until, stall, press, shot, note } = part;
  const problems = [];
  const misses = [];
  const out = { url: part.url, stalls: {}, fixture: opts.fixture.startsWith(ROOT) ? opts.fixture.slice(ROOT.length + 1) : opts.fixture };
  const steps = async () => {
    const saveText = readFileSync(opts.fixture, 'utf8');
    await page.evaluate(writeSaveInPage, { dbName: IDB_NAME, version: IDB_VERSION, store: IDB_STORE, path: SAVE_PATH, text: saveText,
      dirMode: DIR_MODE, fileMode: FILE_MODE });
    const back = await page.evaluate(readSaveInPage, { dbName: IDB_NAME, store: IDB_STORE, path: SAVE_PATH });
    if (back !== saveText) return problems.push('the fixture could not be put into the page\'s IndexedDB');
    await page.click('#play');
    if (!(await until((s) => s.top === 'title' && s.warming === false))) return problems.push('the title never came (or never finished preparing)');
    judge(out, misses, problems, 'title', await stall('title'), opts, 'the title\'s worst frame until Continue enables');
    if (!String(state().focus).startsWith(CONTINUE)) return problems.push(`the title's focus is "${state().focus}", not ${CONTINUE} (the save was not found)`);
    const t0 = Date.now();
    await press('Enter');
    if (!(await until((s) => s.level === 'level.world' && s.loading === false && s.top === ''))) return problems.push('Continue did not load the world');
    out.continue_to_world_s = round1((Date.now() - t0) / 1000);
    note('shrine: the world is loaded');
    judge(out, misses, problems, 'level', await stall('level'), opts, 'the world\'s first frame on Continue');
    out.level_tiers = state().tiers;
    if (!(state().tiers || []).includes('hi')) problems.push(`the giant draws the texture tier ${JSON.stringify(state().tiers)} (hi wanted)`);
    await shot('world_shrine.png');
    // the shrine: E when the prompt offers the rest; a step back turns a giant that faces away
    let tries = 0;
    while (state().top !== 'shrine' && tries < 20) {
      tries += 1;
      if (String(state().prompt).startsWith(REST_PROMPT)) {
        await press('e');
        await until((s) => s.top === 'shrine', 20);
      } else {
        await page.focus('#game-canvas').catch(() => {});
        await page.keyboard.down('s');
        await sleep(350);
        await page.keyboard.up('s');
        await until((s) => String(s.prompt).startsWith(REST_PROMPT), 4);
      }
    }
    out.shrine_tries = tries;
    note(`shrine: the shrine screen ${state().top === 'shrine' ? 'is open' : 'did not open'} after ${tries} tries`);
    if (state().top !== 'shrine') return problems.push(`the shrine screen never opened (the prompt read "${state().prompt}")`);
    // up from the open tab's rows to the row of tab buttons, then along it
    for (let i = 0; i < 8 && state().focus_tab !== true; i++) {
      await press('ArrowUp');
      await sleep(400);
    }
    for (let i = 0; i < 16 && !(state().focus_tab === true && String(state().focus).startsWith(APPEARANCE_TAB)); i++) {
      await press('ArrowRight');
      await sleep(400);
    }
    if (!(state().focus_tab === true && String(state().focus).startsWith(APPEARANCE_TAB))) return problems.push(`the Appearance tab never took the focus (it is on "${state().focus}")`);
    out.appearance_tab_button = state().focus;
    await press('Enter');
    if (!(await until((s) => s.tab === APPEARANCE_TAB, 30))) return problems.push(`Enter on the tab's button showed the tab "${state().tab}"`);
    for (let i = 0; i < 8 && state().focus !== CHANGE_LOOK; i++) {
      await press('ArrowDown');
      await sleep(400);
    }
    if (state().focus !== CHANGE_LOOK) return problems.push(`"${CHANGE_LOOK}" never took the focus (it is on "${state().focus}")`);
    await press('Enter');
    if (!(await until((s) => s.top === 'creator', 120))) return problems.push(`Enter on "${CHANGE_LOOK}" did not open the creator`);
    if (state().context !== 'shrine') problems.push(`the creator opened for "${state().context}", not the shrine`);
    judge(out, misses, problems, 'shrine_creator', await stall('shrine_creator'), opts, `the first frame of "${CHANGE_LOOK}" at a shrine`);
    await sleep(1500);
    await shot('shrine_creator.png');
    return null;
  };
  await steps().catch((e) => problems.push(`the part broke: ${e && e.message ? e.message : e}`));
  return finish(part, out, problems, misses, opts);
}

async function main() {
  const opts = parseArgs(process.argv.slice(2));
  if (!existsSync(join(opts.build, 'play.html'))) {
    console.error(`${TOOL}: ${opts.build}/play.html is missing: run tools/build_web.sh first`);
    process.exit(1);
  }
  if (opts.parts.includes('shrine') && !existsSync(opts.fixture)) usage(`the fixture ${opts.fixture} is missing`);
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
  const memoryGuard = startMemoryGuard('creator_check');
  const started = Date.now();
  console.log(`${TOOL}: ${origin}/play.html (${opts.build}, ${opts.size}; parts: ${opts.parts.join(', ')})`);
  const report = { build: opts.build, viewport: opts.size, game_args: opts.gameArgs, stall_ratio: opts.stallRatio, strict: opts.strict, parts: {} };
  // The launcher's open-world start hands the creator its arguments (the page's own text).
  const launcher = readFileSync(join(opts.build, 'play.html'), 'utf8');
  report.launcher_world_args = launcher.includes(`start([${WORLD_ARGS.map((a) => `'${a}'`).join(', ')}]);`);
  const problems = [];
  if (!report.launcher_world_args) problems.push(`the launcher's open-world start does not pass ${JSON.stringify(WORLD_ARGS)}`);
  for (const name of opts.parts) {
    const part = name === 'new_game' ? await partNewGame(browser, opts, origin) : await partShrine(browser, opts, origin);
    report.parts[name] = part;
    for (const p of part.problems) problems.push(`${name}: ${p}`);
  }
  memoryGuard.stop();
  await browser.close();
  server.close();
  report.wall_s = round1((Date.now() - started) / 1000);
  report.memory_guard = { limit_mb: memoryGuard.limitMb, renderer_peak_mb: memoryGuard.peakMb() };
  report.misses = [].concat(...opts.parts.map((n) => report.parts[n].misses.map((m) => `${n}: ${m}`)));
  report.problems = problems;
  report.ok = problems.length === 0;
  if (opts.json) writeFileSync(opts.json, JSON.stringify(report, null, 2) + '\n');

  for (const name of opts.parts) {
    const p = report.parts[name];
    console.log(`  ${name}: ${p.ok ? 'ok' : 'FAILED'}; console errors ${p.console_errors.length}, engine warnings ${p.engine_warnings.length}, failed requests ${p.failed_requests.length}; the page's frames: ${p.page_frames.count}, median work ${p.page_frames.median_work_ms} ms, worst ${p.page_frames.worst_work_ms} ms`);
    for (const [mark, s] of Object.entries(p.stalls)) {
      console.log(`    ${mark}: first ${s.first_ms} ms, median ${s.median_ms} ms, ${s.ratio}x${s.load_worst_ms !== undefined ? `, the load's worst frame ${s.load_worst_ms} ms` : ''} - ${s.ok ? 'no stall' : 'A STALL'}`);
      if (s.first_draw) console.log(`      its first frames ${JSON.stringify(s.first)} ms, of which the renderer's draw ${JSON.stringify(s.first_draw)} ms (a steady frame's draw: ${s.median_draw_ms} ms)`);
      if (s.gl) {
        const g = (x) => `${x.shaders_compiled} shaders compiled, ${x.programs_linked} programs linked, ${x.textures_allocated} textures allocated, ${x.texture_updates} updated in place, ${x.framebuffers} framebuffers or renderbuffers made`;
        console.log(`      WebGL in its first ${s.gl.first.frames} frames: ${g(s.gl.first)}; in the ${s.gl.steady.frames} after: ${g(s.gl.steady)}`);
      }
    }
    if (p.pointer_lock) console.log(`    Begin's pointer lock: ${p.pointer_lock.requests} request(s), inside the gesture: ${p.pointer_lock.in_gesture}, locked: ${p.pointer_lock.locked}`);
    for (const b of p.skin_bench) console.log(`    the skin's CPU after "${b.mark}": ${b.skin_ms} ms a frame (${b.giants} giant(s) in the tree, ${b.modifier_runs} modifier runs timed)`);
    if (p.level_tiers) console.log(`    the giant's texture tier in the level: ${JSON.stringify(p.level_tiers)}`);
    for (const e of p.console_errors.slice(0, 10)) console.log(`    error: ${e}`);
    for (const w of p.engine_warnings.slice(0, 6)) console.log(`    warning: ${w}`);
    for (const r of p.failed_requests.slice(0, 10)) console.log(`    request: ${r}`);
  }
  for (const m of report.misses) console.log(`  MISS: ${m}`);
  console.log(`CREATOR_CHECK ${JSON.stringify(report)}`);
  if (report.ok) {
    console.log(report.misses.length > 0
      ? `${TOOL}: OK (${report.misses.length} budget miss(es) reported: stalls over ${opts.stallRatio}x the median frame or the skin's CPU; --strict fails on them)`
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
