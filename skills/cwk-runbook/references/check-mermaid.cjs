#!/usr/bin/env node
/**
 * check-mermaid.cjs — parse every ```mermaid block in Markdown files and report the ones that fail.
 *
 *   node check-mermaid.cjs <file-or-dir> [more...]   (resources/, scripts/, or a skill's references/)
 *   node scripts/check-mermaid.cjs ~/work/taskflow/knowledge-base
 *
 * Exit 0 when every diagram parses, 1 when any fails (each printed as file:line and the parser's
 * message), 2 when the check could not run at all.
 *
 * Why: a Knowledge Base is judged by its diagrams, and a diagram with a syntax error renders as an
 * error box that nobody notices until they open that page. Checking by eye does not scale past a
 * few dozen; the four benchmark KBs carry close to five hundred.
 *
 * How: the vendored `mermaid.min.js` (the same build the KB pages inline, so the verdict matches
 * what the reader's browser will do) with a do-nothing DOM. `mermaid.parse` only needs the DOM to
 * exist: DOMPurify initialises when `document.nodeType === 9` and checks a handful of constructors
 * with `instanceof`. Nothing is rendered, so nothing real is required. Zero dependencies, like the
 * rest of `scripts/`.
 */
const fs = require('fs');
const path = require('path');

const targets = process.argv.slice(2);
if (!targets.length) {
  console.error('usage: node check-mermaid.cjs <file-or-dir> [more...]');
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
const bundle = vendored.file;

// ---- a DOM that answers everything and does nothing ----
// Tree-walking properties answer null and collections answer empty, or a loop such as
// `while (node.parentNode)` would never end.
const EMPTY = /^(parentNode|parentElement|firstChild|lastChild|nextSibling|previousSibling|firstElementChild|lastElementChild|nextElementSibling|previousElementSibling|ownerDocument|namespaceURI|nodeValue|textContent|innerHTML|outerHTML)$/;
const LISTS = /^(childNodes|children|attributes|classList|styleSheets)$/;
function answer(k) {
  if (k === Symbol.toPrimitive) return () => '';
  if (k === Symbol.iterator) return function* () {};
  if (k === 'then') return undefined;
  if (k === 'length' || k === 'nodeType') return 0;
  if (k === 'nodeName' || k === 'tagName') return '';
  if (EMPTY.test(String(k))) return null;
  if (LISTS.test(String(k))) return [];
  return stub();
}
const stub = () => new Proxy(function () {}, {
  get: (t, k) => answer(k),
  apply: () => stub(),
  construct: () => stub(),
});
globalThis.window = globalThis;
globalThis.addEventListener = () => {};
globalThis.removeEventListener = () => {};
globalThis.document = new Proxy(stub(), { get: (t, k) => (k === 'nodeType' ? 9 : answer(k)) });
if (!globalThis.navigator) globalThis.navigator = { userAgent: 'node' };
for (const n of ['Node', 'Element', 'HTMLElement', 'HTMLFormElement', 'HTMLTemplateElement', 'NamedNodeMap',
  'DocumentFragment', 'Text', 'Comment', 'Document', 'DOMParser', 'NodeFilter', 'HTMLCollection']) {
  if (!globalThis[n]) globalThis[n] = function () {};
}

// Mermaid logs every parse error to the console on its own; keep the report ours.
const quiet = { error: console.error, warn: console.warn };
console.error = () => {};
console.warn = () => {};
let mermaid;
try {
  const m = require(bundle);
  mermaid = m.default || m;
} catch (err) {
  quiet.error(`✖ could not load ${bundle}: ${err.message}`);
  process.exit(2);
}

// ---- collect blocks ----
function mdFiles(p) {
  const st = fs.statSync(p);
  if (st.isFile()) return /\.md$/i.test(p) ? [p] : [];
  const out = [];
  for (const e of fs.readdirSync(p, { withFileTypes: true })) {
    if (e.name.startsWith('.') || e.name === 'node_modules') continue;
    out.push(...mdFiles(path.join(p, e.name)));
  }
  return out;
}
function blocks(file) {
  const lines = fs.readFileSync(file, 'utf8').split('\n');
  const found = [];
  for (let i = 0; i < lines.length; i++) {
    const open = lines[i].match(/^(\s*)```mermaid\s*$/);
    if (!open) continue;
    const indent = open[1].length;
    const start = i + 1;
    const body = [];
    for (i++; i < lines.length && !/^\s*```\s*$/.test(lines[i]); i++) body.push(lines[i].slice(Math.min(indent, lines[i].length - lines[i].trimStart().length)));
    found.push({ line: start, src: body.join('\n') });
  }
  return found;
}

// A `<` inside label text sends DOMPurify into real HTML parsing, which the do-nothing DOM above
// cannot finish (it loops until the heap runs out). In a browser the same diagram parses fine. Label
// text is opaque to Mermaid's grammar, so swapping `<` and `>` for look-alikes there changes nothing
// the parser judges. Arrows (`-->`, `->>`, `<-->`, `<|--`) sit outside quotes and message text and
// are left alone.
function neutralise(src) {
  const swap = (t) => t.replace(/</g, '\u2039').replace(/>/g, '\u203a');
  const seq = /^\s*sequenceDiagram\b/.test(src);
  return src.split('\n').map((line) => {
    let out = line.replace(/"[^"\n]*"/g, swap);
    // Sequence messages are unquoted: `A->>B: text`. Everything after the first colon is text.
    if (seq) out = out.replace(/^([^:]*?(?:->>|-->>|->|-->|-x|--x|-\)|--\)))([^:]*:)(.*)$/, (m, a, b, c) => a + b + swap(c));
    // Notes: `Note over A: text`.
    if (seq) out = out.replace(/^(\s*[Nn]ote\s[^:]*:)(.*)$/, (m, a, b) => a + swap(b));
    return out;
  }).join('\n');
}

// Size is not a parse error, but a 40-node LR flowchart renders as a strip nobody reads. Count
// nodes and states with a simple scan and warn (exit code unchanged) so the author can split it.
function sizeWarning(src) {
  const head = (src.trim().split('\n')[0] || '').trim();
  const type = head.split(/\s+/)[0];
  if (/^(flowchart|graph)$/.test(type)) {
    const ids = new Set();
    for (const m of src.matchAll(/(^|[\s>|])([A-Za-z_][A-Za-z0-9_]*)\s*(\[|\(\(|\(|\{|>\[|\[\[|\[\()/g)) ids.add(m[2]);
    for (const m of src.matchAll(/(^|[\s|])([A-Za-z_][A-Za-z0-9_]*)\s*(-->|-\.->|==>|--[^>]*-->)/g)) ids.add(m[2]);
    const n = ids.size, lr = /\b(LR|RL)\b/.test(head);
    if (n > 40) return `flowchart with ${n} nodes — split it (about 25 per diagram reads well)`;
    if (n > 25) return `flowchart with ${n} nodes — consider splitting (about 25 per diagram reads well)`;
    if (lr && n > 10) return `flowchart LR with ${n} nodes renders as a wide strip — use TD or split`;
  } else if (type === 'stateDiagram-v2' || type === 'stateDiagram') {
    const st = new Set();
    for (const m of src.matchAll(/([A-Za-z_][A-Za-z0-9_]*|\[\*\])\s*-->\s*([A-Za-z_][A-Za-z0-9_]*|\[\*\])/g)) { st.add(m[1]); st.add(m[2]); }
    if (st.size > 18) return `state diagram with ${st.size} states — split by entity or phase`;
  } else if (type === 'sequenceDiagram') {
    const parts = new Set();
    for (const m of src.matchAll(/^\s*(participant|actor)\s+([A-Za-z0-9_]+)/gm)) parts.add(m[2]);
    for (const m of src.matchAll(/^\s*([A-Za-z0-9_]+)\s*(->>|-->>|->|-->|-x|--x|-\)|--\))\s*([A-Za-z0-9_]+)/gm)) { parts.add(m[1]); parts.add(m[3]); }
    if (parts.size > 9) return `sequence diagram with ${parts.size} participants — split by phase`;
  } else if (type === 'erDiagram') {
    // Mermaid lays entities side by side and each attribute block is wide, so an ER grows
    // horizontally far faster than a flowchart: eleven entities measured 3,222px, which no screen
    // shows at a readable scale. One ER per aggregate plus a small overview reads; this does not.
    const ents = new Set();
    for (const m of src.matchAll(/^\s*([A-Za-z_][A-Za-z0-9_]*)\s*\{/gm)) ents.add(m[1]);
    for (const m of src.matchAll(/^\s*([A-Za-z_][A-Za-z0-9_]*)\s+[|}o][o|{}]*--[o|{}]+\s+([A-Za-z_][A-Za-z0-9_]*)/gm)) { ents.add(m[1]); ents.add(m[2]); }
    if (ents.size > 12) return `ER diagram with ${ents.size} entities — split it, one per aggregate (it renders wider than any screen)`;
    if (ents.size > 8) return `ER diagram with ${ents.size} entities — consider splitting by aggregate`;
  }
  return '';
}

(async () => {
  let total = 0;
  const failures = [];
  const warnings = [];
  for (const t of targets) {
    if (!fs.existsSync(t)) { quiet.error(`✖ not found: ${t}`); process.exit(2); }
    for (const f of mdFiles(t)) {
      for (const b of blocks(f)) {
        total++;
        const w = sizeWarning(b.src);
        if (w) warnings.push({ where: `${f}:${b.line}`, why: w });
        try {
          await mermaid.parse(neutralise(b.src));
        } catch (err) {
          failures.push({ where: `${f}:${b.line}`, why: String((err && err.message) || err).split('\n').slice(0, 4).join(' ').replace(/\s+/g, ' ').slice(0, 240) });
        }
      }
    }
  }
  for (const x of failures) quiet.error(`✖ ${x.where}  ${x.why}`);
  if (!process.env.MM_QUIET_SIZE) for (const x of warnings) quiet.error(`⚠ ${x.where}  ${x.why}`);
  console.log(`${total - failures.length}/${total} mermaid diagram(s) parse${failures.length ? `, ${failures.length} fail` : ''}${warnings.length ? `, ${warnings.length} oversized (warning)` : ''}`);
  process.exit(failures.length ? 1 : 0);
})();
