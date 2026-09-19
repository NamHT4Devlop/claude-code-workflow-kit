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

function findVendor(start) {
  for (let d = start, i = 0; i < 6; i++) {
    const f = path.join(d, 'vendor', 'mermaid.min.js');
    if (fs.existsSync(f)) return f;
    const up = path.dirname(d);
    if (up === d) break;
    d = up;
  }
  return '';
}
const bundle = findVendor(__dirname);
if (!bundle) {
  console.error('✖ vendor/mermaid.min.js not found — run scripts/fetch-vendor.sh first');
  process.exit(2);
}

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

(async () => {
  let total = 0;
  const failures = [];
  for (const t of targets) {
    if (!fs.existsSync(t)) { quiet.error(`✖ not found: ${t}`); process.exit(2); }
    for (const f of mdFiles(t)) {
      for (const b of blocks(f)) {
        total++;
        try {
          await mermaid.parse(neutralise(b.src));
        } catch (err) {
          failures.push({ where: `${f}:${b.line}`, why: String((err && err.message) || err).split('\n').slice(0, 4).join(' ').replace(/\s+/g, ' ').slice(0, 240) });
        }
      }
    }
  }
  for (const x of failures) quiet.error(`✖ ${x.where}  ${x.why}`);
  console.log(`${total - failures.length}/${total} mermaid diagram(s) parse${failures.length ? `, ${failures.length} fail` : ''}`);
  process.exit(failures.length ? 1 : 0);
})();
