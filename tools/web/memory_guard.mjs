// The Chromium checks' memory guard (M10 gate, LD-1). Under a starved browser (the whole browser on one
// CPU beside busy loops, or a machine at loads past 10) the single-threaded Web build's level load in
// headless Chromium with software WebGL grows the page's renderer process by 16-58 MB a second without
// end - the 0.9.0-m9 build as the M10 one (docs/PERFORMANCE.md, "The page's memory under a starved
// browser") - until the kernel's OOM killer takes the browser and whatever else shares the machine. A
// loaded page needs 1.0-1.6 GB. So each of the five checks (audio_check, creator_check, stream_check,
// world_check, world_start_check) starts this guard beside its browser: once a second it reads the
// renderer processes among THIS check's own child processes from /proc, and when one holds more than the
// limit it prints
//   <tool>: FAILED - the page's renderer holds N MB of memory (over the guard's L MB) ...
// kills this check's own browser processes (never another run's) and exits 1. A loaded machine gets a
// FAILED line naming the memory instead of an OOM kill of other work.
//   GIANT_WEB_GUARD_MB=<MB>   the limit (default 3072; 0 switches the guard off)
// Without /proc (not Linux) the guard reads nothing and never trips. Its own test is
// tools/web/test_memory_guard.mjs.

import { existsSync, readdirSync, readFileSync } from 'node:fs';

export const GUARD_MB = 3072;
export const GUARD_ENV = 'GIANT_WEB_GUARD_MB';
export const GUARD_INTERVAL_MS = 1000;

// The limit in MB from the environment: the default without the variable or with an unreadable one, 0 = off.
export function guardLimitMb(env = process.env) {
  const text = env[GUARD_ENV];
  if (text === undefined || text === '') return GUARD_MB;
  const n = Number(text);
  return Number.isFinite(n) && n >= 0 ? n : GUARD_MB;
}

// One /proc/<pid>/status text: { ppid, rssMb } (rssMb 0 for a process without VmRSS: a kernel thread, a zombie).
export function parseStatus(text) {
  const ppid = /^PPid:\s*(\d+)/m.exec(text);
  const rss = /^VmRSS:\s*(\d+)\s*kB/m.exec(text);
  return { ppid: ppid ? Number(ppid[1]) : 0, rssMb: rss ? Number(rss[1]) / 1024 : 0 };
}

// The process table from /proc: [{ pid, ppid, rssMb, cmd() }] ([] where there is no /proc).
export function readProcessTable(procRoot = '/proc') {
  if (!existsSync(procRoot)) return [];
  const table = [];
  let names = [];
  try {
    names = readdirSync(procRoot);
  } catch (e) {
    return [];
  }
  for (const name of names) {
    if (!/^\d+$/.test(name)) continue;
    try {
      const { ppid, rssMb } = parseStatus(readFileSync(`${procRoot}/${name}/status`, 'utf8'));
      table.push({ pid: Number(name), ppid, rssMb, cmd: () => {
        try {
          return readFileSync(`${procRoot}/${name}/cmdline`, 'utf8').split('\0').join(' ');
        } catch (e) {
          return '';
        }
      } });
    } catch (e) {
      /* the process ended while it was read */
    }
  }
  return table;
}

// Every process below `rootPid` in `table` (children, their children, ...), the nearest first.
export function descendantsOf(table, rootPid) {
  const out = [];
  let level = [rootPid];
  const seen = new Set(level);
  while (level.length > 0) {
    const next = [];
    for (const row of table) {
      if (level.includes(row.ppid) && !seen.has(row.pid)) {
        seen.add(row.pid);
        next.push(row.pid);
        out.push(row);
      }
    }
    level = next;
  }
  return out;
}

// Chromium's page processes (the game runs in one; the GPU and network processes are not counted).
export const isRenderer = (cmd) => /(^|\s)--type=renderer(\s|$)/.test(cmd);

// The largest renderer below `rootPid`: { pid, rssMb } or null when there is none.
export function largestRenderer(table, rootPid) {
  let best = null;
  for (const row of descendantsOf(table, rootPid)) {
    if (!isRenderer(typeof row.cmd === 'function' ? row.cmd() : String(row.cmd || ''))) continue;
    if (best === null || row.rssMb > best.rssMb) best = { pid: row.pid, rssMb: row.rssMb };
  }
  return best;
}

// True when the guard stops the run: a limit is set and the renderer is over it.
export const overLimit = (rssMb, limitMb) => limitMb > 0 && rssMb > limitMb;

export function failedLine(tool, rssMb, limitMb) {
  return `${tool}: FAILED - the page's renderer holds ${Math.round(rssMb)} MB of memory (over the guard's ${limitMb} MB): `
    + 'the run was stopped before the machine ran out of memory. A loaded page needs 1.0-1.6 GB; the growth is the Web build '
    + `under a starved browser with software WebGL (docs/PERFORMANCE.md) - run the check on a quieter machine (${GUARD_ENV}=<MB> moves the limit, 0 switches it off)`;
}

// Kills every process below `rootPid` (this check's own browser), the deepest first.
export function killDescendants(rootPid = process.pid, table = readProcessTable()) {
  let killed = 0;
  for (const row of descendantsOf(table, rootPid).reverse()) {
    try {
      process.kill(row.pid, 'SIGKILL');
      killed += 1;
    } catch (e) {
      /* already gone */
    }
  }
  return killed;
}

// Starts the guard for `tool`. Options (tests): limitMb, intervalMs, rootPid, readTable and onExceed(rssMb, limitMb)
// in place of "print FAILED, kill the browser, exit 1". Returns { limitMb, peakMb(), tripped(), check(), stop() }.
export function startMemoryGuard(tool, options = {}) {
  const limitMb = options.limitMb !== undefined ? options.limitMb : guardLimitMb();
  const rootPid = options.rootPid !== undefined ? options.rootPid : process.pid;
  const readTable = options.readTable || readProcessTable;
  let peak = 0;
  let tripped = false;
  let timer = null;
  const stop = () => {
    if (timer !== null) clearInterval(timer);
    timer = null;
  };
  const check = () => {
    if (tripped) return true;
    const top = largestRenderer(readTable(), rootPid);
    if (top === null) return false;
    peak = Math.max(peak, top.rssMb);
    if (!overLimit(top.rssMb, limitMb)) return false;
    tripped = true;
    stop();
    if (options.onExceed) {
      options.onExceed(top.rssMb, limitMb);
    } else {
      console.log(failedLine(tool, top.rssMb, limitMb));
      killDescendants(rootPid, readTable());
      process.exit(1);
    }
    return true;
  };
  if (limitMb > 0) {
    timer = setInterval(check, options.intervalMs || GUARD_INTERVAL_MS);
    if (typeof timer.unref === 'function') timer.unref();
  }
  return { limitMb, peakMb: () => Math.round(peak), tripped: () => tripped, check, stop };
}
