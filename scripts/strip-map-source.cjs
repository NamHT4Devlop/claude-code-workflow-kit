#!/usr/bin/env node
// strip-map-source.cjs — remove the embedded SOURCE TEXT from a /cwk-map full-index page.
//
//   node scripts/strip-map-source.cjs <in.html> <out.html>
//
// A /cwk-map page built from a provenlens index (skills/cwk-map/references/provenlens-full.cjs)
// carries the whole call graph inside <script id="graph-data"> as gzip+base64 JSON — and, so the
// explorer can show a symbol's body offline, the FULL TEXT of every indexed file under `source`.
// That is fine inside the repository. It is not fine in a KB hub, which is pushed and emailed:
// a hub page must carry symbols, edges and call-site lines, never the company's source.
//
// This keeps everything except `source` (set to {}), marks `stats.sourceStripped = true` so the
// page can say so, and re-packs the block exactly the way pack() did (gzip level 9, base64).
//
// Exit codes:
//   0  stripped and written
//   2  not a full-index page: no graph-data block, or a plain-JSON block (the older sampled
//      viewer, which embeds no source) — nothing is written; the caller copies the page as-is
//   1  any other failure (unreadable input, corrupt block, cannot write)
//
// Zero dependencies: Node's zlib only. The write is atomic (temp file in the same directory,
// then rename), so an interrupted run never leaves a half-written page that still looks whole.
'use strict';
const fs = require('fs');
const path = require('path');
const zlib = require('zlib');

const [inFile, outFile] = process.argv.slice(2);
if (!inFile || !outFile) {
  console.error('usage: strip-map-source.cjs <in.html> <out.html>');
  process.exit(1);
}

let html;
try {
  html = fs.readFileSync(inFile, 'utf8');
} catch (err) {
  console.error(`✗ cannot read ${inFile}: ${err.message}`);
  process.exit(1);
}

// The block is written by build-map.cjs as
//   <script id="graph-data" type="application/octet-stream">BASE64</script>   (full index)
//   <script id="graph-data" type="application/json">{...}</script>            (sampled viewer)
const OPEN = /<script\b[^>]*\bid="graph-data"[^>]*>/;
const open = OPEN.exec(html);
if (!open) {
  console.error(`✗ ${path.basename(inFile)}: no <script id="graph-data"> block — not a /cwk-map page`);
  process.exit(2);
}
const bodyStart = open.index + open[0].length;
const bodyEnd = html.indexOf('</script>', bodyStart);
if (bodyEnd < 0) {
  console.error(`✗ ${path.basename(inFile)}: graph-data block is not closed`);
  process.exit(1);
}
const body = html.slice(bodyStart, bodyEnd);
const trimmed = body.trim();

if (trimmed.startsWith('{') || trimmed.startsWith('[')) {
  console.error(`· ${path.basename(inFile)}: plain-JSON graph-data block (sampled viewer, embeds no source) — copy it unchanged`);
  process.exit(2);
}
if (!/^[A-Za-z0-9+/=\s]+$/.test(trimmed)) {
  console.error(`✗ ${path.basename(inFile)}: graph-data block is neither base64 nor JSON — not the full-index format`);
  process.exit(2);
}

let data;
try {
  data = JSON.parse(zlib.gunzipSync(Buffer.from(trimmed, 'base64')).toString('utf8'));
} catch (err) {
  console.error(`✗ ${path.basename(inFile)}: graph-data block does not gunzip to JSON (${err.message})`);
  process.exit(1);
}
if (!data || typeof data !== 'object' || !Array.isArray(data.syms) || !Array.isArray(data.files)) {
  console.error(`✗ ${path.basename(inFile)}: unpacked block lacks files/syms — not the full-index format`);
  process.exit(2);
}

const hadFiles = data.source && typeof data.source === 'object' ? Object.keys(data.source).length : 0;
data.source = {};
data.stats = data.stats && typeof data.stats === 'object' ? data.stats : {};
data.stats.sourceStripped = true;

// Same packing as provenlens-full.cjs pack(): gzip level 9, base64 — the explorer unpacks it
// with DecompressionStream('gzip') and nothing else.
const packed = zlib.gzipSync(Buffer.from(JSON.stringify(data), 'utf8'), { level: 9 }).toString('base64');
const out = html.slice(0, bodyStart) + packed + html.slice(bodyEnd);

const tmp = path.join(path.dirname(path.resolve(outFile)), `.${path.basename(outFile)}.${process.pid}.tmp`);
try {
  fs.writeFileSync(tmp, out, 'utf8');
  fs.renameSync(tmp, outFile);
} catch (err) {
  try { fs.unlinkSync(tmp); } catch { /* nothing to clean */ }
  console.error(`✗ cannot write ${outFile}: ${err.message}`);
  process.exit(1);
}

const kb = (n) => `${Math.round(n / 1024)} KB`;
console.log(`✔ ${path.basename(outFile)}: source of ${hadFiles} file(s) stripped · ${kb(html.length)} → ${kb(out.length)} · ${data.syms.length} symbols and ${Array.isArray(data.edges) ? data.edges.length : 0} edges kept`);
