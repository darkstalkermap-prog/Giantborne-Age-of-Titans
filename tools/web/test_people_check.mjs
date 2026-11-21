#!/usr/bin/env node
// The web people check's own test (P64; plan M11 §3.17): tools/web/people_check.mjs's judgement without an engine.
//   * the helpers: the parts' game arguments, a view over 250 draw calls fails, the people's CPU over 2.5 ms and the
//     people's textures over 10 MB above the level's are misses, a first frame within 3 median frames (or under 25 ms)
//     is no stall, a part without its done line or its two marks fails, a console error fails and a warning does not;
//   * (with a browser; --no-browser skips it) the check against a stub launcher in headless Chromium whose play.html
//     prints what the game's probes print for the part it is asked for: --args=--stub=ok passes, --stub=calls fails
//     on the draw calls, --stub=slow passes with a MISS and fails with --strict.
// Prints TEST_PEOPLE_CHECK with the count of checks and failures; exits 1 on a failure.
//
// Usage (from the project folder): node tools/web/test_people_check.mjs [--no-browser] [--keep]

import { spawnSync } from 'node:child_process';
import { mkdtempSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { gameArgs, judgeView, parseArgs, stallOk, summarizePart } from './people_check.mjs';

const ROOT = resolve(dirname(fileURLToPath(import.meta.url)), '..', '..');
const CHECK = join(ROOT, 'tools', 'web', 'people_check.mjs');
const NO_BROWSER = process.argv.includes('--no-browser');
const KEEP = process.argv.includes('--keep');
let checks = 0;
let failures = 0;

function check(cond, what) {
  checks += 1;
  if (!cond) {
    failures += 1;
    console.log(`  FAIL: ${what}`);
  }
}

const VIEW = { t: 'view', view: 'level', draw_calls: 120, primitives: 40000, texture_mem_mb: 30, buffer_mem_mb: 12,
  people: { skinned: 0, crowd: 0, far: 0 }, others: { skinned: 0, far: 0 }, people_cpu_ms: 0.1, people_cpu_parts_ms: [0, 0, 0, 0] };

function helpers() {
  check(gameArgs('formation').includes('--people-probe=level+formation+wolves') && gameArgs('formation')[0] === '--ui-probe',
    'the formation part runs both probes and its three views');
  check(gameArgs('town', ['--x']).at(-1) === '--x', '--args go last');
  check(parseArgs(['--parts=town']).parts.join() === 'town', '--parts');
  check(judgeView({ ...VIEW, draw_calls: 251 }, null).problems.length === 1, 'over 250 draw calls fails');
  check(judgeView({ ...VIEW, draw_calls: 250 }, null).problems.length === 0, '250 draw calls pass');
  check(judgeView({ ...VIEW, view: 'formation', people_cpu_ms: 2.6 }, VIEW).misses.length === 1, "the people's CPU over 2.5 ms is a miss");
  check(judgeView({ ...VIEW, view: 'formation', texture_mem_mb: 41 }, VIEW).misses.length === 1, "the people's textures over 10 MB are a miss");
  check(judgeView({ ...VIEW, view: 'formation', texture_mem_mb: 39 }, VIEW).misses.length === 0, '9 MB more is none');
  check(stallOk(24, 2) && stallOk(60, 20) && !stallOk(61, 20), 'a stall: over 3 median frames and over 25 ms');
  const stall = (mark, first, med) => ({ t: 'stall', mark, first_ms: first, median_ms: med, ratio: first / med });
  const seen = (over) => ({ errors: [], failed: [], views: [VIEW, { ...VIEW, view: 'formation' }, { ...VIEW, view: 'wolves' }],
    stalls: { first_formation: stall('first_formation', 50, 20), first_wolf: stall('first_wolf', 40, 20) },
    done: { t: 'done' }, ...over });
  check(summarizePart('formation', seen({}), [16, 17], {}).ok, 'a clean part passes');
  check(!summarizePart('formation', seen({ done: null }), [], {}).ok, 'no done line fails');
  check(!summarizePart('formation', seen({ stalls: {} }), [], {}).ok, 'a missing mark fails');
  const warn = summarizePart('formation', seen({ errors: ['WARNING: something', '   at: here'] }), [], {});
  check(warn.ok && warn.engine_warnings.length === 2, 'a warning is listed apart');
  check(!summarizePart('formation', seen({ errors: ['ERROR: broken'] }), [], {}).ok, 'a console error fails');
  const slow = seen({ stalls: { first_formation: stall('first_formation', 200, 20), first_wolf: stall('first_wolf', 40, 20) } });
  check(summarizePart('formation', slow, [], {}).ok && summarizePart('formation', slow, [], {}).misses.length === 1, 'a stall is a miss');
  check(!summarizePart('formation', slow, [], { strict: true }).ok, '--strict fails on it');
}

const STUB = `<!doctype html>
<html><head><meta charset="utf-8"><title>stub</title></head><body><canvas id="game-canvas"></canvas>
<script>
(function () {
  const args = (new URLSearchParams(location.search).get('args') || '').split(',').map(decodeURIComponent);
  const mode = (args.find((a) => a.startsWith('--stub=')) || '--stub=ok').split('=')[1];
  const probe = (args.find((a) => a.startsWith('--people-probe=')) || '--people-probe=level').split('=')[1].split('+');
  const say = (tag, o) => console.log(tag + ' ' + JSON.stringify(o));
  let at = 0;
  const views = [];
  function step() {
    if (at < probe.length) {
      const v = probe[at];
      if (v === 'formation') say('UI_PROBE', { t: 'stall', mark: 'first_formation', first_ms: mode === 'slow' ? 300 : 40, median_ms: 20, ratio: mode === 'slow' ? 15 : 2 });
      if (v === 'wolves') say('UI_PROBE', { t: 'stall', mark: 'first_wolf', first_ms: 30, median_ms: 20, ratio: 1.5 });
      say('PEOPLE_WEB', { t: 'view', view: v, draw_calls: mode === 'calls' && v === 'formation' ? 300 : 100, primitives: 1000,
        texture_mem_mb: 20, buffer_mem_mb: 10, people: { skinned: 16, crowd: 24, far: 0 }, others: { skinned: 6, far: 0 },
        people_cpu_ms: 1.0, people_cpu_parts_ms: [0.5, 0.1, 0.3, 0.1] });
      views.push(v);
      at += 1;
      setTimeout(step, 50);
    } else {
      say('PEOPLE_WEB', { t: 'done', views });
    }
  }
  setTimeout(step, 100);
})();
</script></body></html>
`;

function browserRuns() {
  const dir = mkdtempSync(join(tmpdir(), 'people_check_stub_'));
  writeFileSync(join(dir, 'play.html'), STUB);
  const run = (stub, extra = []) => spawnSync(process.execPath, [CHECK, `--build=${dir}`, '--timeout-s=60', `--args=--stub=${stub}`, ...extra],
    { encoding: 'utf8', cwd: ROOT });
  const ok = run('ok');
  check(ok.status === 0 && /people_check: OK/.test(ok.stdout), `--stub=ok passes (${ok.stdout.slice(-300)}${ok.stderr.slice(-300)})`);
  check(/PEOPLE_CHECK \{/.test(ok.stdout), 'it prints its report');
  const calls = run('calls');
  check(calls.status === 1 && /300 draw calls/.test(calls.stdout), '--stub=calls fails on the draw calls');
  const slow = run('slow', ['--parts=formation']);
  check(slow.status === 0 && /MISS: formation: first_formation/.test(slow.stdout), '--stub=slow passes with a MISS');
  const strict = run('slow', ['--parts=formation', '--strict']);
  check(strict.status === 1, '--strict fails on it');
  if (KEEP) console.log(`  stub: ${dir}`);
  else rmSync(dir, { recursive: true, force: true });
}

helpers();
if (!NO_BROWSER) browserRuns();
console.log(`TEST_PEOPLE_CHECK ${checks} checks, ${failures} failures${NO_BROWSER ? ' (no browser)' : ''}`);
process.exit(failures === 0 ? 0 : 1);
