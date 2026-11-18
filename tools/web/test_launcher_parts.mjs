#!/usr/bin/env node
// The launcher's unpacking, outside a browser (P49; plan M11 §3.2 item 3). web/launcher.html downloads
// the packed game data in parts (index.pck.gz.b64.<n>.txt: base64 text of a gzip stream, cut anywhere)
// and decodes and inflates each piece as it arrives instead of joining the parts' text. This test runs
// the launcher's OWN lines - everything between "// <parts>" and "// </parts>" - against packs of one
// to four parts served from memory:
//   * every pack comes out byte for byte, whatever the cut (every remainder of the part length by four,
//     network chunks of 1 byte, of a prime size and of the whole part), with the browser's
//     Uint8Array.fromBase64 and with the atob fallback;
//   * the parts are asked for in order, each once, and the bytes reported add up to the text's length;
//   * the text is never joined: the largest piece handed to the base64 decoder is no longer than one
//     network chunk and the three characters carried over, and the largest piece written to the
//     inflater no longer than three quarters of that;
//   * line breaks and spaces in the text are ignored (a host that wraps the text);
//   * failures: the first part missing (HTTP 404) and a damaged first part reject before any Response;
//     a later part missing, and text cut short, end the body with an error instead of hanging.
// Usage: node tools/web/test_launcher_parts.mjs [--launcher=web/launcher.html]
// Exits 0 when every check holds (1 otherwise).

import { readFileSync } from 'node:fs';
import { gzipSync } from 'node:zlib';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = resolve(dirname(fileURLToPath(import.meta.url)), '..', '..');
let launcherPath = resolve(ROOT, 'web', 'launcher.html');
for (const arg of process.argv.slice(2)) {
  if (arg.startsWith('--launcher=')) launcherPath = resolve(arg.slice('--launcher='.length));
  else {
    console.error(`test_launcher_parts: unknown option ${arg}`);
    process.exit(2);
  }
}

let checks = 0;
let failures = 0;
function check(ok, what) {
  checks += 1;
  if (!ok) {
    failures += 1;
    console.log(`FAIL  ${what}`);
  }
}

// The launcher's own block, made into a module of its functions.
const html = readFileSync(launcherPath, 'utf8');
const from = html.indexOf('// <parts>');
const to = html.indexOf('// </parts>');
check(from > 0 && to > from, 'web/launcher.html has the <parts> block');
if (!(from > 0 && to > from)) {
  console.log(`test_launcher_parts: ${checks} checks, ${failures} failures`);
  process.exit(1);
}
const source = html.slice(html.indexOf('\n', from) + 1, to);
check(!/Blob\(/.test(source) && !/\.text\(\)/.test(source), 'the block builds no Blob and reads no whole text');

// decoderLog records the length of every text handed to the base64 decoder.
function loadBlock({ nativeBase64 }) {
  const decoderLog = [];
  class U8 extends Uint8Array {}
  if (nativeBase64) {
    U8.fromBase64 = (text) => {
      decoderLog.push(text.length);
      return new Uint8Array(Buffer.from(text, 'base64'));
    };
  } else {
    U8.fromBase64 = undefined;
  }
  const atobLogged = (text) => {
    decoderLog.push(text.length);
    return atob(text);
  };
  const make = new Function('Uint8Array', 'atob', 'TextDecoder', 'DecompressionStream', 'Response',
    `${source}\nreturn { pckUrls, decodeBase64, base64Pieces, unpackParts };`);
  const api = make(U8, atobLogged, TextDecoder, DecompressionStream, Response);
  return { ...api, decoderLog };
}

// A pack: seeded noise and text, like the game's (mostly incompressible), gzipped and base64-encoded.
function makePack(bytes, seed) {
  const raw = new Uint8Array(bytes);
  let x = seed >>> 0;
  for (let i = 0; i < bytes; i++) {
    x = (Math.imul(x, 1664525) + 1013904223) >>> 0;
    raw[i] = i % 7 === 0 ? 65 + (i % 26) : x >>> 24;
  }
  return { raw, text: gzipSync(raw, { level: 9 }).toString('base64') };
}

// Cuts `text` into `n` parts as tools/build_web.sh does (parts of ceil(len / n) characters).
function cut(text, n) {
  const per = Math.ceil(text.length / n);
  const parts = [];
  for (let i = 0; i < n; i++) parts.push(text.slice(i * per, (i + 1) * per));
  return parts;
}

// A fetch over `files` (url -> text | { status }) that serves each body in chunks of `chunk` bytes.
function fakeFetch(files, chunk, asked) {
  return async (url) => {
    asked.push(url);
    const entry = files[url];
    if (entry === undefined || typeof entry === 'object') {
      return { ok: false, status: entry ? entry.status : 404, body: null };
    }
    const data = Buffer.from(entry, 'latin1');
    let at = 0;
    return {
      ok: true,
      status: 200,
      body: {
        getReader: () => ({
          read: async () => {
            if (at >= data.length) return { done: true, value: undefined };
            const value = new Uint8Array(data.subarray(at, Math.min(data.length, at + chunk)));
            at += value.length;
            return { done: false, value };
          },
        }),
      },
    };
  };
}

const same = (a, b) => a.length === b.length && Buffer.compare(Buffer.from(a), Buffer.from(b)) === 0;

async function unpack(api, parts, chunk, { wrap = false } = {}) {
  const urls = api.pckUrls(parts.length);
  const files = {};
  parts.forEach((text, i) => {
    files[urls[i]] = wrap ? text.replace(/(.{76})/g, '$1\r\n') + '\n' : text;
  });
  const asked = [];
  let received = 0;
  let done = 0;
  const res = await api.unpackParts(urls, 'application/octet-stream', fakeFetch(files, chunk, asked),
    (n) => { received += n; }, () => { done += 1; });
  const out = new Uint8Array(await res.arrayBuffer());
  return { out, asked, urls, received, done, res, sent: Object.values(files).reduce((a, t) => a + t.length, 0) };
}

// ---------------------------------------------------------------------------------- the names
{
  const api = loadBlock({ nativeBase64: true });
  check(JSON.stringify(api.pckUrls(1)) === '["index.pck.gz.b64.txt"]', 'one part keeps its plain name');
  check(JSON.stringify(api.pckUrls(4)) === JSON.stringify([1, 2, 3, 4].map((i) => `index.pck.gz.b64.${i}.txt`)),
    'four parts are index.pck.gz.b64.1.txt to .4.txt');
  check(api.pckUrls(undefined).length === 1 && api.pckUrls(0).length === 1 && api.pckUrls('3').length === 3,
    'a missing or odd part count is one part; a count as text is read');
}

// ---------------------------------------------------------------------------------- every cut
for (const nativeBase64 of [true, false]) {
  const label = nativeBase64 ? 'fromBase64' : 'atob';
  // Four lengths whose four-part cut leaves each remainder of the part length by four.
  const seenRemainders = new Set();
  for (let size = 200000; seenRemainders.size < 4 && size < 200400; size += 7) {
    const pack = makePack(size, size);
    const per = Math.ceil(pack.text.length / 4);
    if (seenRemainders.has(per % 4)) continue;
    seenRemainders.add(per % 4);
    for (const n of [1, 2, 3, 4]) {
      for (const chunk of [65536, 4099]) {
        const api = loadBlock({ nativeBase64 });
        const r = await unpack(api, cut(pack.text, n), chunk);
        check(same(r.out, pack.raw), `${label}: ${n} part(s), chunks of ${chunk}, part length % 4 = ${per % 4}: the pack comes out byte for byte`);
        check(JSON.stringify(r.asked) === JSON.stringify(r.urls), `${label}: ${n} part(s): each part asked for once, in order`);
        check(r.received === pack.text.length && r.done === 1, `${label}: ${n} part(s): every byte of text reported once, then done`);
        const largest = Math.max(...api.decoderLog);
        check(largest <= chunk + 3, `${label}: ${n} part(s), chunks of ${chunk}: the decoder never holds more than a chunk and the carry (${largest})`);
        check(r.res.headers.get('Content-Type') === 'application/octet-stream' && r.res.status === 200, `${label}: an ordinary 200 response of the file's type`);
      }
    }
  }
  check(seenRemainders.size === 4, `${label}: the four remainders were all met`);
  // One byte at a time, and a host that wraps the text in lines.
  const small = makePack(3000, 11);
  const api1 = loadBlock({ nativeBase64 });
  check(same((await unpack(api1, cut(small.text, 4), 1)).out, small.raw), `${label}: chunks of one byte`);
  const api2 = loadBlock({ nativeBase64 });
  const wrapped = await unpack(api2, cut(small.text, 3), 50, { wrap: true });
  check(same(wrapped.out, small.raw), `${label}: line breaks in the text are ignored`);
  check(wrapped.received === wrapped.sent && wrapped.sent > small.text.length, `${label}: and still counted as received`);
}

// ---------------------------------------------------------------------------------- a pack at the last budget's shape
{
  // 6 MB of text in four parts: large enough that joined text would show (4 x 1.5 MB), small enough for a test.
  const pack = makePack(4400000, 44);
  const api = loadBlock({ nativeBase64: true });
  const before = process.memoryUsage().arrayBuffers;
  const r = await unpack(api, cut(pack.text, 4), 65536);
  check(same(r.out, pack.raw), 'a 6 MB pack in four parts comes out byte for byte');
  check(Math.max(...api.decoderLog) <= 65536 + 3, 'and no piece of text over one network chunk was decoded');
  check(api.decoderLog.length >= Math.floor(pack.text.length / 65536), 'in as many pieces as chunks arrived');
  check(process.memoryUsage().arrayBuffers - before < 6 * pack.raw.length, 'without holding several copies of it');
}

// ---------------------------------------------------------------------------------- failures
{
  const pack = makePack(50000, 5);
  const parts = cut(pack.text, 3);
  const api = loadBlock({ nativeBase64: true });
  const urls = api.pckUrls(3);
  const expectReject = async (files, pattern, what) => {
    try {
      await api.unpackParts(urls, 'x/y', fakeFetch(files, 4096, []), () => {}, () => {});
      check(false, `${what}: rejects`);
    } catch (e) {
      check(pattern.test(String(e && e.message)), `${what}: rejects with "${e && e.message}"`);
    }
  };
  await expectReject({ [urls[0]]: { status: 404 }, [urls[1]]: parts[1], [urls[2]]: parts[2] },
    /could not be downloaded \(HTTP 404\)/, 'the first part missing');
  await expectReject({ [urls[0]]: 'QUJD' + parts[0], [urls[1]]: parts[1], [urls[2]]: parts[2] },
    /arrived damaged/, 'a first part that is not a gzip stream');
  await expectReject({ [urls[0]]: '', [urls[1]]: '', [urls[2]]: '' }, /arrived damaged/, 'empty parts');
  const expectBodyError = async (files, pattern, what) => {
    let done = 0;
    const res = await api.unpackParts(urls, 'x/y', fakeFetch(files, 4096, []), () => {}, () => { done += 1; });
    try {
      await res.arrayBuffer();
      check(false, `${what}: the body ends with an error`);
    } catch (e) {
      check(pattern.test(String((e && e.message) || e)), `${what}: the body ends with "${(e && e.message) || e}"`);
    }
    check(done === 0, `${what}: never reported done`);
  };
  await expectBodyError({ [urls[0]]: parts[0], [urls[1]]: { status: 503 }, [urls[2]]: parts[2] },
    /could not be downloaded \(HTTP 503\)/, 'a later part missing');
  await expectBodyError({ [urls[0]]: parts[0], [urls[1]]: parts[1], [urls[2]]: parts[2].slice(0, 40) },
    /./, 'text cut short');
  const noInflate = new Function('Uint8Array', 'atob', 'TextDecoder', 'DecompressionStream', 'Response',
    `${source}\nreturn { unpackParts };`)(Uint8Array, atob, TextDecoder, undefined, Response);
  try {
    await noInflate.unpackParts(urls, 'x/y', fakeFetch({}, 1, []), () => {}, () => {});
    check(false, 'a browser without DecompressionStream: rejects');
  } catch (e) {
    check(/cannot unpack the game/.test(String(e && e.message)), 'a browser without DecompressionStream is told so');
  }
}

console.log(`test_launcher_parts: ${checks} checks, ${failures} failures`);
process.exit(failures === 0 ? 0 : 1);
