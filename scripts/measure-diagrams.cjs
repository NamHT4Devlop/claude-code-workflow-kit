#!/usr/bin/env node
/**
 * measure-diagrams.cjs — how wide does each Mermaid diagram ACTUALLY render?
 *
 *   node scripts/measure-diagrams.cjs <file-or-dir> [more...] [--out report.html] [--open]
 *
 * Why this exists: `check-mermaid.cjs` warns by counting nodes, and node count is a weak proxy.
 * Measured across 292 diagrams in two knowledge bases, node count correlates with rendered width
 * at only r = 0.59 — the widest diagram found (5,913px) was never flagged, because its twenty-odd
 * nodes sit side by side rather than stacked. Width is what makes a page unreadable, and width is
 * only known after layout, which needs a browser: Mermaid asks the DOM how wide each label is.
 *
 * So this writes a small self-contained page that renders every diagram and prints a table of
 * `file:line → width × height`, sorted widest first. Open it and read the top of the table; those
 * are the diagrams to split. Nothing is uploaded and nothing runs here — the page is local and the
 * Mermaid bundle is the kit's own vendored, hash-pinned copy.
 *
 * Rules of thumb from the same measurements, for a reader with a ~1100px column:
 *   under 1100px  fits as drawn
 *   1100–2000px   fits once the page stops shrinking it (the KB viewer opens these at full size)
 *   over 3000px   split it: no screen shows this at a readable scale
 *
 * What narrows a diagram, in the order worth trying — each measured on real pages:
 *   1. `direction` on a subgraph. Members that do not link to each other stack into a column
 *      instead of spreading: 2,896px → 1,015px, and 2,503px → 1,526px, nothing else changed.
 *   2. Flipping the chart direction. `LR` is wrong for a long chain but right for a SHALLOW
 *      FAN-OUT, where `TD` puts three or four long labels side by side: 2,008px → 1,489px.
 *   3. Splitting, by branch rather than by size — parallel columns are what make width.
 * What does NOT work: `%%{init: {"flowchart": {"wrappingWidth": …}}}%%` is ignored by the vendored
 * build, with or without `htmlLabels: false`, and composite states in a `stateDiagram-v2` usually
 * render WIDER than the original. When a diagram's width is its label text — render it once with
 * the labels stripped and compare — no restructuring will help, and the honest answer is to leave
 * it: one measured state machine took 94% of its width from transition labels.
 */
const fs = require('fs');
const path = require('path');

const args = process.argv.slice(2);
const targets = [];
let out = '';
let open = false;
for (let i = 0; i < args.length; i++) {
  if (args[i] === '--out') out = args[++i];
  else if (args[i] === '--open') open = true;
  else targets.push(args[i]);
}
if (!targets.length) {
  console.error('usage: node measure-diagrams.cjs <file-or-dir> [more...] [--out report.html] [--open]');
  process.exit(2);
}

// ---- vendored library lookup ----------------------------------------------------------------
// IDENTICAL copy in build-map.cjs, kb-site.cjs, check-mermaid.cjs and render-html.cjs (each file is
// standalone) — change all four together. The bundle is only ever taken from the kit's own vendor/ (the nearest
// ancestor of this file's real path holding both .claude-plugin/plugin.json and vendor/SHA256SUMS),
// never from a scanned repository's vendor/, and its SHA-256 must match the pinned entry before it is
// used — check-mermaid require()s the bundle and the others inline it into every generated page,
// so an unverified one would run as arbitrary code here or in every reader's browser.
const crypto = require('crypto');
function kitRoot() {
  let d;
  try { d = fs.realpathSync(__dirname); } catch { return ''; }
  for (;;) {
    if (fs.existsSync(path.join(d, '.claude-plugin', 'plugin.json')) && fs.existsSync(path.join(d, 'vendor', 'SHA256SUMS'))) return d;
    const up = path.dirname(d);
    if (up === d) return '';
    d = up;
  }
}
/** → { file, why }: `file` is the verified vendor/<lib>.min.js, else '' with `why` = 'absent' (no kit
 *  root or not fetched: silent fallback) or a message naming the file (hash mismatch / no pinned entry). */
function vendoredLib(lib) {
  const root = kitRoot();
  if (!root) return { file: '', why: 'absent' };
  const file = path.join(root, 'vendor', `${lib}.min.js`);
  if (!fs.existsSync(file)) return { file: '', why: 'absent' };
  const sums = fs.readFileSync(path.join(root, 'vendor', 'SHA256SUMS'), 'utf8');
  const want = (sums.match(new RegExp(`^([0-9a-fA-F]{64})\\s+\\*?${lib}\\.min\\.js\\s*$`, 'm')) || [])[1];
  if (!want) return { file: '', why: `${file}: no entry in vendor/SHA256SUMS — see vendor/README.md` };
  const got = crypto.createHash('sha256').update(fs.readFileSync(file)).digest('hex');
  if (got !== want.toLowerCase()) return { file: '', why: `${file}: SHA-256 ${got} does not match vendor/SHA256SUMS (${want.toLowerCase()}) — see vendor/README.md` };
  return { file, why: '' };
}
// ---- end vendored library lookup ------------------------------------------------------------

const vendored = vendoredLib('mermaid');
if (!vendored.file) {
  console.error(vendored.why === 'absent'
    ? '✖ vendor/mermaid.min.js not found in the kit — run scripts/fetch-vendor.sh first'
    : `✖ refusing to load ${vendored.why}`);
  process.exit(2);
}

function mdFiles(p) {
  const st = fs.statSync(p);
  if (st.isFile()) return /\.md$/i.test(p) ? [p] : [];
  const found = [];
  for (const e of fs.readdirSync(p, { withFileTypes: true })) {
    if (e.name.startsWith('.') || e.name === 'node_modules') continue;
    found.push(...mdFiles(path.join(p, e.name)));
  }
  return found;
}
function blocks(file) {
  const lines = fs.readFileSync(file, 'utf8').split('\n');
  const found = [];
  for (let i = 0; i < lines.length; i++) {
    const openFence = lines[i].match(/^(\s*)```mermaid\s*$/);
    if (!openFence) continue;
    const indent = openFence[1].length;
    const start = i + 1;
    const body = [];
    for (i++; i < lines.length && !/^\s*```\s*$/.test(lines[i]); i++) {
      body.push(lines[i].slice(Math.min(indent, lines[i].length - lines[i].trimStart().length)));
    }
    found.push({ file: path.relative(process.cwd(), file), line: start, src: body.join('\n') });
  }
  return found;
}

const diagrams = targets.flatMap(mdFiles).flatMap(blocks);
if (!diagrams.length) {
  console.error('no ```mermaid blocks found in: ' + targets.join(', '));
  process.exit(2);
}

const report = out || path.join(process.cwd(), 'cwk-sessions', 'diagram-widths.html');
fs.mkdirSync(path.dirname(report), { recursive: true });

// The diagrams travel as JSON inside a <script type="application/json">, so no source text is ever
// parsed as HTML or as code.
const page = `<!doctype html>
<html lang="en"><head><meta charset="utf-8">
<title>Diagram widths</title>
<style>
 body{background:#0b0d12;color:#e6e9ef;font:14px system-ui,-apple-system,"Segoe UI",sans-serif;margin:0;padding:24px}
 h1{font-size:18px;margin:0 0 4px} p{color:#8b93a7;margin:0 0 18px}
 table{border-collapse:collapse;width:100%;max-width:1000px} th,td{text-align:left;padding:6px 10px;border-bottom:1px solid #222a3a}
 th{color:#8b93a7;font-weight:600;font-size:12px} td.n{text-align:right;font-variant-numeric:tabular-nums}
 .split{color:#f87171} .wide{color:#facc15} .ok{color:#4ade80} code{color:#9ab}
 #status{color:#8b93a7}
</style></head><body>
<h1>Diagram widths</h1>
<p>Rendered with the same Mermaid build the pages use. Over 3000px cannot be read at any scale — split it.</p>
<div id="status">Rendering…</div>
<table id="t" hidden><thead><tr><th>Where</th><th>Type</th><th class="n">Width</th><th class="n">Height</th><th>Verdict</th></tr></thead><tbody></tbody></table>
<div id="sink" style="position:absolute;left:-99999px;top:0"></div>
<script type="application/json" id="data">${JSON.stringify(diagrams).replace(/</g, '\\u003c')}</script>
<script>${fs.readFileSync(vendored.file, 'utf8')}</script>
<script>
(async function(){
  var list = JSON.parse(document.getElementById('data').textContent);
  mermaid.initialize({ startOnLoad:false, theme:'dark', securityLevel:'strict' });
  var sink = document.getElementById('sink'), rows = [];
  for (var i = 0; i < list.length; i++) {
    var d = list[i], w = 0, h = 0, err = '';
    try {
      var r = await mermaid.render('m' + i, d.src);
      var box = document.createElement('div'); box.innerHTML = r.svg; sink.appendChild(box);
      var vb = (box.querySelector('svg').getAttribute('viewBox') || '').split(/[ ,]+/);
      w = Math.round(parseFloat(vb[2]) || 0); h = Math.round(parseFloat(vb[3]) || 0);
      box.remove();
    } catch (e) { err = String((e && e.message) || e).slice(0, 90); }
    rows.push({ file: d.file, line: d.line, type: (d.src.trim().split('\\n')[0] || '').trim(), w: w, h: h, err: err });
    document.getElementById('status').textContent = 'Rendering… ' + (i + 1) + ' / ' + list.length;
  }
  rows.sort(function(a, b){ return b.w - a.w; });
  var body = document.querySelector('#t tbody');
  rows.forEach(function(r){
    var tr = document.createElement('tr');
    var verdict = r.err ? 'does not render' : r.w > 3000 ? 'split it' : r.w > 2000 ? 'wide' : 'fits';
    var cls = r.err ? 'split' : r.w > 3000 ? 'split' : r.w > 2000 ? 'wide' : 'ok';
    [r.file + ':' + r.line, r.type, r.err ? '—' : r.w, r.err ? '—' : r.h, r.err || verdict].forEach(function(v, i){
      var td = document.createElement('td'); td.textContent = v;
      if (i === 2 || i === 3) td.className = 'n';
      if (i === 4) td.className = cls;
      tr.appendChild(td);
    });
    body.appendChild(tr);
  });
  var over = rows.filter(function(r){ return r.w > 3000; }).length;
  document.getElementById('status').textContent = rows.length + ' diagrams · ' + over + ' over 3000px';
  document.getElementById('t').hidden = false;
})();
</script></body></html>`;

fs.writeFileSync(report, page);
console.log(`${diagrams.length} diagram(s) from ${targets.join(', ')}`);
console.log(report);
console.log('Open it in a browser — widths are measured there, because only a browser knows how wide a label is.');
if (open) {
  const { spawnSync } = require('child_process');
  const cmd = process.platform === 'darwin' ? 'open' : process.platform === 'win32' ? 'start' : 'xdg-open';
  spawnSync(cmd, [report], { stdio: 'ignore' });
}
