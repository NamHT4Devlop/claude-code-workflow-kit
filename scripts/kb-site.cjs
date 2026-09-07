#!/usr/bin/env node
/**
 * kb-site.cjs — turn a KB hub (or a single repo's knowledge-base/) into ONE self-contained web page.
 *
 *   node scripts/kb-site.cjs <hub-dir> [output.html]
 *   node scripts/kb-site.cjs ~/kb-hub                  → ~/kb-hub/index.html
 *   node scripts/kb-site.cjs ~/work/taskflow           → a single-project site
 *
 * Why this exists: a hub is a folder of Markdown. Twelve projects times twenty documents is 240
 * files that nobody browses. This renders all of them into one page — project picker on the left,
 * document tabs across the top, search over everything — that opens with a double-click, works
 * offline, and can be handed to someone who will never run a terminal.
 *
 * It reads two folders per project: the Knowledge Base (what the system means) and, when present,
 * the runbooks under cwk-sessions/runbook/ (what to do when it breaks). The second is the half
 * someone searches under pressure, and it lives in a gitignored folder, so leaving it out would put
 * it beyond the reach of the one page built to be findable.
 *
 * Self-contained on purpose: every document, the CSS and (when vendored) Mermaid are inlined, so
 * the file survives being emailed, put on a share drive, or opened on a plane.
 */
const fs = require('fs');
const path = require('path');

// The markdown renderer is shared with render-html.cjs so a doc looks the same in both.
const { markdownToHtml } = require(path.join(__dirname, '..', 'resources', 'html-builder.js'));

const src = process.argv[2];
if (!src || !fs.existsSync(src)) {
  console.error('usage: node kb-site.cjs <hub-dir|repo-dir> [output.html]');
  process.exit(1);
}
const root = path.resolve(src);
const out = process.argv[3] || path.join(root, 'index.html');

// ---------- collect projects ----------
// Two shapes are accepted: a hub (projects/<name>/knowledge-base/) or one repo (knowledge-base/).
const projects = [];
const hubDir = path.join(root, 'projects');
if (fs.existsSync(hubDir) && fs.statSync(hubDir).isDirectory()) {
  for (const name of fs.readdirSync(hubDir).sort()) {
    const kb = path.join(hubDir, name, 'knowledge-base');
    if (fs.existsSync(kb)) {
      projects.push({
        name, kb,
        metaFile: path.join(hubDir, name, '_meta.yml'),
        runbookDir: path.join(hubDir, name, 'runbook'),
        graphFile: path.join(hubDir, name, 'code-graph.html'),
      });
    }
  }
} else if (fs.existsSync(path.join(root, 'knowledge-base'))) {
  const kb = path.join(root, 'knowledge-base');
  projects.push({
    name: path.basename(root),
    kb,
    metaFile: path.join(kb, '_meta.yml'),
    runbookDir: path.join(root, 'cwk-sessions', 'runbook'),
    graphFile: newestMap(path.join(root, 'cwk-sessions', 'maps')),
  });
}
if (!projects.length) {
  console.error(`no Knowledge Base found under ${root}
  expected either  <dir>/projects/<name>/knowledge-base/   (a hub, from kb-export.sh)
             or    <dir>/knowledge-base/                   (a single repo)`);
  process.exit(1);
}

// ---------- read each project's docs + identity ----------
const DAY = 86400000;
const today = new Date();
for (const p of projects) {
  p.meta = parseMeta(p.metaFile) || parseMeta(path.join(p.kb, '_meta.yml')) || {};
  p.docs = [];
  walk(p.kb, p.kb, p.docs);
  // Runbooks live outside the KB, under cwk-sessions/runbook/. They are the other document someone
  // searches under pressure -- "what do we do when X fails" -- and a page holding the KB but not the
  // runbook sends that reader back to the folder they opened this page to avoid. The base is the
  // PARENT of the runbook dir, so every id arrives as `runbook/<file>` and prettyTitle renders it
  // "runbook / <name>": distinguishable from a KB page at a glance in the tab strip and in a hit list.
  p.runbookCount = 0;
  if (p.runbookDir && fs.existsSync(p.runbookDir)) {
    const before = p.docs.length;
    walk(p.runbookDir, path.dirname(p.runbookDir), p.docs);
    p.runbookCount = p.docs.length - before;
  }
  p.docs.sort((a, b) => a.id.localeCompare(b.id, 'en', { numeric: true }));
  const gen = p.meta.generated && /^\d{4}-\d{2}-\d{2}$/.test(p.meta.generated) ? new Date(p.meta.generated + 'T00:00:00') : null;
  p.ageDays = gen ? Math.round((today - gen) / DAY) : null;
  p.stale = p.ageDays != null && p.ageDays > 30;
}

/**
 * The most recent code graph a repo has, or ''. /cwk-map writes one file per run into
 * cwk-sessions/maps/, so the newest is the one that describes the current tree.
 */
function newestMap(dir) {
  if (!dir || !fs.existsSync(dir)) return '';
  const files = fs.readdirSync(dir)
    .filter((n) => /\.html$/i.test(n))
    .map((n) => path.join(dir, n))
    .sort((a, b) => fs.statSync(b).mtimeMs - fs.statSync(a).mtimeMs);
  return files[0] || '';
}

function walk(dir, base, acc) {
  for (const e of fs.readdirSync(dir, { withFileTypes: true }).sort((a, b) => a.name.localeCompare(b.name))) {
    const full = path.join(dir, e.name);
    if (e.isDirectory()) { walk(full, base, acc); continue; }
    if (!/\.md$/i.test(e.name)) continue;
    const rel = path.relative(base, full);
    acc.push({ id: rel, title: prettyTitle(rel), html: markdownToHtml(fs.readFileSync(full, 'utf8')) });
  }
}
function prettyTitle(rel) {
  const inModules = rel.includes(path.sep);
  const leaf = rel.split(path.sep).pop().replace(/\.md$/i, '');
  const nice = leaf.replace(/^(\d+)[-_]/, '$1 · ').replace(/[-_]/g, ' ');
  return inModules ? `${rel.split(path.sep)[0]} / ${nice}` : nice;
}
// A deliberately small YAML reader: these files are flat key: value written by this kit.
function parseMeta(f) {
  if (!f || !fs.existsSync(f)) return null;
  const m = {};
  for (const line of fs.readFileSync(f, 'utf8').split('\n')) {
    const mm = line.match(/^([a-z_]+):\s*(.*)$/i);
    if (mm) m[mm[1]] = mm[2].trim();
  }
  return m;
}

// ---------- serialise ----------
// The same escaping build-map.cjs learned the hard way: a `</script>` inside any KB document would
// otherwise close this block early and inject markup into the page.
// The code graph is a separate self-contained page (Cytoscape, its own per-node search), not
// inlined: one of those is a few hundred KB and a hub has one per project. A relative href keeps
// this page's own "email it and it opens" property intact and still puts the graph one click away
// -- it resolves whenever the folder travels together, and the link simply 404s when it does not,
// which is visible rather than silent.
const dataJson = JSON.stringify(projects.map(p => ({
  name: p.name, meta: p.meta, ageDays: p.ageDays, stale: p.stale,
  graph: p.graphFile && fs.existsSync(p.graphFile)
    ? path.relative(path.dirname(path.resolve(out)), p.graphFile).split(path.sep).join('/')
    : '',
  docs: p.docs.map(d => ({ id: d.id, title: d.title, html: d.html })),
})))
  .replace(/</g, '\\u003c').replace(/>/g, '\\u003e')
  .replace(/\u2028/g, '\\u2028').replace(/\u2029/g, '\\u2029');

const nonce = 'n' + Math.random().toString(36).slice(2) + Date.now().toString(36);
let html = page(dataJson, nonce, path.basename(root));
html = inlineMermaid(html, __dirname, nonce);

fs.writeFileSync(out, html, 'utf8');
const docCount = projects.reduce((n, p) => n + p.docs.length, 0);
const runbookCount = projects.reduce((n, p) => n + (p.runbookCount || 0), 0);
console.error(`${projects.length} project(s), ${docCount} document(s)${runbookCount ? ` (incl. ${runbookCount} runbook page(s))` : ''}${projects.some(p => p.stale) ? ' · ⚠ some KBs are over 30 days old' : ''}`);
console.log(out);

/** Inline vendor/mermaid.min.js when present so the page makes no network calls. */
function inlineMermaid(h, dir, nce) {
  let vendorDir = '';
  for (let d = dir, i = 0; i < 6; i++) {
    const cand = path.join(d, 'vendor');
    if (fs.existsSync(cand)) { vendorDir = cand; break; }
    const up = path.dirname(d);
    if (up === d) break;
    d = up;
  }
  const f = vendorDir && path.join(vendorDir, 'mermaid.min.js');
  if (!f || !fs.existsSync(f)) return h;   // no vendor → leave the page working, just without diagrams
  const code = fs.readFileSync(f, 'utf8').replace(/<\/script/gi, '<\\/script');
  const tag = `<script nonce="${nce}">\n/* vendored mermaid — offline, no external fetch */\n${code}\n</script>`;
  // MUST use a replacer function: minified code is full of `$&` / `$'` / `` $` ``, and a string
  // replacement would expand those as capture-group patterns — `$'` alone splices the whole rest of
  // the document back in, which renders the bundle as visible text instead of running it.
  return h.replace('<!--MERMAID-->', () => tag);
}

function esc(s) { return String(s).replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c])); }

function page(json, nce, title) {
  return `<!DOCTYPE html><html lang="en"><head>
<meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<!-- style-src deliberately carries NO nonce: per CSP, a nonce makes 'unsafe-inline' be ignored, and
     Mermaid styles every diagram by injecting a <style> element at render time — with a nonce here
     those get blocked and diagrams render unstyled (black boxes, blob arrows). Scripts keep the
     nonce, which is the directive that actually matters: no external or injected script can run. -->
<meta http-equiv="Content-Security-Policy" content="default-src 'none'; style-src 'unsafe-inline'; script-src 'nonce-${nce}'; img-src 'self' data:;">
<title>Knowledge Base — ${esc(title)}</title>
<style nonce="${nce}">
:root{--bg:#0f1420;--panel:#151b2b;--panel2:#1b2233;--line:#2a3348;--fg:#e6e9ef;--dim:#94a0b8;--accent:#6ea8fe;--warn:#e0b341;--bad:#f2777a;--ok:#5fd08a}
*{box-sizing:border-box}
body{margin:0;font:14px/1.65 -apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,sans-serif;background:var(--bg);color:var(--fg);display:flex;height:100vh;overflow:hidden}
/* left rail — projects */
#rail{width:250px;flex:0 0 250px;background:var(--panel);border-right:1px solid var(--line);display:flex;flex-direction:column}
#brand{padding:14px 16px 10px;font-weight:800;letter-spacing:.3px;border-bottom:1px solid var(--line)}
#brand small{display:block;font-weight:400;color:var(--dim);font-size:11px;margin-top:3px}
#search{margin:10px;padding:8px 10px;background:var(--panel2);border:1px solid var(--line);border-radius:8px;color:var(--fg);font:inherit;font-size:13px}
#search:focus{outline:1px solid var(--accent)}
#plist{overflow:auto;padding:4px 8px 12px;flex:1}
a.graphlink{display:block;margin:-2px 0 10px;padding:6px 10px;border:1px dashed var(--line);border-radius:8px;
  color:var(--dim);text-decoration:none;font-size:12px}
a.graphlink:hover{color:var(--fg);border-color:var(--accent)}
.p{width:100%;text-align:left;background:none;border:1px solid transparent;border-radius:8px;color:var(--fg);padding:8px 10px;cursor:pointer;margin-bottom:3px;font:inherit}
.p:hover{background:var(--panel2)}
.p.on{background:var(--panel2);border-color:var(--accent)}
.p b{display:block;font-size:13.5px}
.p span{display:block;font-size:11px;color:var(--dim);margin-top:2px}
.badge{display:inline-block;font-size:10px;padding:1px 6px;border-radius:999px;border:1px solid;margin-left:4px}
.badge.stale{color:var(--warn);border-color:var(--warn)}
.badge.fresh{color:var(--ok);border-color:var(--ok)}
/* main */
#main{flex:1;display:flex;flex-direction:column;min-width:0}
#tabs{display:flex;gap:4px;overflow-x:auto;padding:10px 16px 0;border-bottom:1px solid var(--line);background:var(--panel)}
.t{white-space:nowrap;background:none;border:none;border-bottom:2px solid transparent;color:var(--dim);padding:7px 11px;cursor:pointer;font:inherit;font-size:12.5px;border-radius:6px 6px 0 0}
.t:hover{color:var(--fg);background:var(--panel2)}
.t.on{color:var(--fg);border-bottom-color:var(--accent)}
.t mark{background:var(--accent);color:#0b1020;border-radius:3px;padding:0 2px}
#meta{padding:8px 16px;font-size:11.5px;color:var(--dim);border-bottom:1px solid var(--line);background:var(--panel)}
#meta .w{color:var(--warn)}
#doc{flex:1;overflow:auto;padding:22px 32px 60px;max-width:none}
#doc h1{font-size:24px;margin:.2em 0 .5em} #doc h2{font-size:19px;margin:1.3em 0 .4em;border-bottom:1px solid var(--line);padding-bottom:4px}
#doc h3{font-size:16px;margin:1.1em 0 .3em} #doc h4{font-size:14px;margin:1em 0 .3em}
#doc table{border-collapse:collapse;margin:1em 0;font-size:13px;display:block;overflow-x:auto;max-width:100%}
#doc th,#doc td{border:1px solid var(--line);padding:6px 10px;text-align:left;vertical-align:top}
#doc th{background:var(--panel2)}
#doc code{background:#0b1020;border:1px solid var(--line);padding:.08em .35em;border-radius:4px;font-size:.9em}
#doc pre{background:#0b1020;border:1px solid var(--line);border-radius:8px;padding:12px;overflow:auto}
#doc pre code{border:none;background:none;padding:0}
#doc blockquote{border-left:3px solid var(--accent);margin:1em 0;padding:.1em 0 .1em 14px;color:var(--dim)}
#doc a{color:var(--accent)} #doc li{margin:.2em 0}
/* diagrams — framed, contained, and readable. Mermaid's dark defaults sit badly on this palette
   (grey cluster boxes, near-black nodes, edge labels lost in the background), and it scopes its own
   CSS by svg id, so the overrides below need !important to land. */
figure.dg{margin:1.4em 0;background:#0b1020;border:1px solid var(--line);border-radius:10px;overflow:hidden}
figure.dg .dgbar{display:flex;justify-content:flex-end;gap:6px;padding:6px 8px;border-bottom:1px solid var(--line);background:var(--panel)}
figure.dg .dgbar button{background:var(--panel2);border:1px solid var(--line);color:var(--dim);border-radius:6px;padding:2px 9px;font:inherit;font-size:11.5px;cursor:pointer}
figure.dg .dgbar button:hover{color:var(--fg);border-color:var(--accent)}
/* align-items:flex-start matters: the default stretch squashes a tall diagram to the panel's
   max-height instead of letting it keep its natural size and scroll. */
figure.dg .dgbody{overflow:auto;max-height:74vh;padding:18px;display:flex;justify-content:center;align-items:flex-start}
figure.dg .dgbody > .mermaid{flex:0 0 auto}
#doc .mermaid{background:transparent;margin:0}
#doc .mermaid svg{max-width:100%;height:auto}
/* labels: mermaid puts flowchart text inside foreignObject divs, so target those too */
#doc .mermaid .nodeLabel,#doc .mermaid .edgeLabel,#doc .mermaid .label,#doc .mermaid .cluster-label,
#doc .mermaid .titleText,#doc .mermaid text{fill:var(--fg)!important;color:var(--fg)!important}
#doc .mermaid .edgeLabel{background:var(--bg)!important;border-radius:4px}
#doc .mermaid .edgeLabel foreignObject div,#doc .mermaid .labelBkg{background:transparent!important}
#doc .mermaid .edgeLabel rect,#doc .mermaid .edgeLabel .label rect{fill:var(--bg)!important;opacity:.92}
#doc .mermaid .cluster rect{fill:#131a29!important;stroke:#33405c!important;rx:8;ry:8}
#doc .mermaid .cluster-label,#doc .mermaid .cluster .nodeLabel{font-weight:700!important}
#doc .mermaid .node rect,#doc .mermaid .node polygon,#doc .mermaid .node circle,#doc .mermaid .node path{
  fill:#1e2739!important;stroke:#4a5975!important;stroke-width:1.2px!important}
#doc .mermaid .flowchart-link,#doc .mermaid .messageLine0,#doc .mermaid .messageLine1{stroke:#8ba0c4!important;stroke-width:1.4px!important}
#doc .mermaid marker path,#doc .mermaid .marker{fill:#8ba0c4!important;stroke:#8ba0c4!important}
#doc .mermaid .actor{fill:#1e2739!important;stroke:#4a5975!important}
#doc .mermaid .note,#doc .mermaid .noteText{fill:#2a2340!important}
#doc .mermaid .activation0,#doc .mermaid .activation1,#doc .mermaid .activation2{fill:#2c3a55!important;stroke:#4a5975!important}
/* fullscreen view for the big ones */
#zoom{position:fixed;inset:0;background:#070a12;display:none;z-index:50;flex-direction:column}
#zoom.on{display:flex}
#zoom .zbar{display:flex;justify-content:space-between;align-items:center;padding:10px 16px;border-bottom:1px solid var(--line);background:var(--panel)}
#zoom .zbar button{background:var(--panel2);border:1px solid var(--line);color:var(--fg);border-radius:6px;padding:4px 12px;font:inherit;font-size:12px;cursor:pointer}
#zoom .zbar button:hover{border-color:var(--accent)}
#zoom .zbody{flex:1;overflow:auto;padding:24px;display:flex;justify-content:center;align-items:flex-start}
#zoom svg{max-width:none!important;height:auto}
#empty{color:var(--dim);padding:40px 32px}
@media (max-width:760px){body{flex-direction:column;height:auto;overflow:auto}#rail{width:auto;flex:none;border-right:none;border-bottom:1px solid var(--line)}#plist{max-height:180px}}
</style></head><body>
<div id="rail">
  <div id="brand">⬡ Knowledge Base<small id="sub"></small></div>
  <input id="search" type="search" placeholder="Search every document…" autocomplete="off">
  <div id="plist"></div>
</div>
<div id="main">
  <div id="tabs"></div>
  <div id="meta"></div>
  <div id="doc"><div id="empty">Pick a project.</div></div>
</div>
<div id="zoom"><div class="zbar"><b id="ztitle">Diagram</b><button id="zclose">✕  Close  (Esc)</button></div><div class="zbody" id="zbody"></div></div>
<!--MERMAID-->
<script nonce="${nce}">
const DATA = ${json};
let pi = 0, di = 0, q = '';

const el = (t, c, x) => { const e = document.createElement(t); if (c) e.className = c; if (x != null) e.textContent = x; return e; };
const strip = h => { const d = document.createElement('div'); d.innerHTML = h; return (d.textContent || '').toLowerCase(); };
// Pre-computed once: searching re-parses nothing.
DATA.forEach(p => p.docs.forEach(d => { d._t = strip(d.html); }));

function hits(doc) { return q && doc._t.includes(q); }
function projHits(p) { return q ? p.docs.filter(hits).length : 0; }

function renderRail() {
  const list = document.getElementById('plist'); list.textContent = '';
  DATA.forEach((p, i) => {
    const n = projHits(p);
    if (q && !n) return;                                  // hide projects with no match
    const b = el('button', 'p' + (i === pi ? ' on' : ''));
    const t = el('b', null, p.name);
    if (p.stale) t.appendChild(Object.assign(el('span', 'badge stale', p.ageDays + 'd'), { style: 'display:inline-block' }));
    else if (p.ageDays != null) t.appendChild(Object.assign(el('span', 'badge fresh', p.ageDays + 'd'), { style: 'display:inline-block' }));
    b.appendChild(t);
    b.appendChild(el('span', null, (p.meta.branch ? p.meta.branch + ' · ' : '') + (p.meta.commit || '') + (q ? '  — ' + n + ' match' + (n > 1 ? 'es' : '') : '')));
    b.onclick = () => { pi = i; di = q ? p.docs.findIndex(hits) : 0; if (di < 0) di = 0; render(); };
    list.appendChild(b);
    // The graph answers a different question than the prose does -- "what reaches this symbol" --
    // and it carries its own per-node search, so it is a sibling page rather than another tab.
    if (p.graph) {
      const g = el('a', 'graphlink', '⛓ Code graph — search by node');
      g.href = p.graph;
      g.target = '_blank';
      g.rel = 'noopener';
      list.appendChild(g);
    }
  });
  if (!list.children.length) list.appendChild(el('div', null, q ? 'No project matches.' : 'No projects.'));
  document.getElementById('sub').textContent = DATA.length + ' project' + (DATA.length > 1 ? 's' : '') + ' · ' + DATA.reduce((n, p) => n + p.docs.length, 0) + ' documents';
}

function render() {
  renderRail();
  const p = DATA[pi]; const tabs = document.getElementById('tabs'); tabs.textContent = '';
  p.docs.forEach((d, i) => {
    if (q && !hits(d)) return;
    const b = el('button', 't' + (i === di ? ' on' : ''), d.title);
    if (q && hits(d)) { const m = el('mark', null, '•'); b.appendChild(document.createTextNode(' ')); b.appendChild(m); }
    b.onclick = () => { di = i; render(); };
    tabs.appendChild(b);
  });
  if (!tabs.children.length) tabs.appendChild(el('div', null, 'No document in this project matches.'));

  const m = document.getElementById('meta'); m.textContent = '';
  const bits = [];
  if (p.meta.repo) bits.push(p.meta.repo);
  if (p.meta.branch) bits.push('branch ' + p.meta.branch);
  if (p.meta.commit) bits.push('commit ' + p.meta.commit);
  if (p.meta.generated) bits.push('KB generated ' + p.meta.generated + (p.ageDays != null ? ' (' + p.ageDays + ' days ago)' : ''));
  if (p.meta.exported) bits.push('exported ' + p.meta.exported);
  m.appendChild(document.createTextNode(bits.join('  ·  ')));
  if (p.stale) {
    const w = el('div', 'w', '⚠ This Knowledge Base is ' + p.ageDays + ' days old — it describes commit ' + (p.meta.commit || '?') + ', not necessarily what is deployed. Re-run /cwk-rescan and re-export before relying on it.');
    m.appendChild(w);
  }

  const host = document.getElementById('doc');
  const doc = p.docs[di];
  host.innerHTML = doc ? doc.html : '<div id="empty">Nothing to show.</div>';
  host.scrollTop = 0;
  drawDiagrams(host);
}

// Mermaid blocks arrive as <pre><code class="language-mermaid">. Wrap each one in a framed figure
// with its own scroll area, so a 900px-tall architecture diagram is a contained panel rather than a
// wall you scroll past, and give it an expand button for when you actually need to read it.
function drawDiagrams(host) {
  if (typeof mermaid === 'undefined') return;
  // NOTE: this whole page is emitted from a JS template literal, so no backticks in here.
  // The shared markdown renderer already emits a div.mermaid for a mermaid fence; a
  // pre > code.language-mermaid only shows up if some other renderer produced the HTML.
  // Normalise the second shape into the first, then frame every .mermaid that isn't framed yet.
  host.querySelectorAll('pre > code').forEach(c => {
    if (!/language-mermaid/.test(c.className)) return;
    const d = document.createElement('div'); d.className = 'mermaid'; d.textContent = c.textContent;
    c.parentElement.replaceWith(d);
  });
  host.querySelectorAll('.mermaid').forEach(d => {
    if (d.closest('figure.dg')) return;
    const fig = document.createElement('figure'); fig.className = 'dg';
    const bar = document.createElement('div'); bar.className = 'dgbar';
    const exp = document.createElement('button'); exp.textContent = '⤢  Expand';
    bar.appendChild(exp);
    const body = document.createElement('div'); body.className = 'dgbody';
    d.replaceWith(fig); body.appendChild(d); fig.appendChild(bar); fig.appendChild(body);
    exp.onclick = () => openZoom(d);
  });
  const nodes = host.querySelectorAll('.mermaid');
  if (!nodes.length) return;
  try { mermaid.run({ nodes }); } catch (e) { /* a bad diagram must not blank the page */ }
}

function openZoom(node) {
  const z = document.getElementById('zoom'), body = document.getElementById('zbody');
  const svg = node.querySelector('svg');
  if (!svg) return;
  body.textContent = '';
  const clone = svg.cloneNode(true);
  clone.removeAttribute('style');              // drop mermaid's inline max-width so it can grow
  body.appendChild(clone);
  z.classList.add('on');
}
document.getElementById('zclose').onclick = () => document.getElementById('zoom').classList.remove('on');
document.addEventListener('keydown', e => { if (e.key === 'Escape') document.getElementById('zoom').classList.remove('on'); });

if (typeof mermaid !== 'undefined') {
  // Mermaid's own dark theme assumes a mid-grey page; on #0f1420 its clusters go flat grey and its
  // nodes go near-black. Pin the whole palette to this page instead of overriding a few values.
  mermaid.initialize({
    startOnLoad: false, securityLevel: 'strict', theme: 'base',
    // useMaxWidth:false is deliberate. With it on, mermaid puts width="100%" on the svg, and
    // inside a shrink-to-fit flex item that resolves against an auto width and collapses the
    // diagram to a fraction of its size. Natural pixel dimensions + a scrolling panel instead.
    flowchart: { curve: 'basis', padding: 14, nodeSpacing: 42, rankSpacing: 52, useMaxWidth: false },
    sequence: { useMaxWidth: false, boxMargin: 10, mirrorActors: false },
    themeVariables: {
      darkMode: true, fontFamily: '-apple-system,BlinkMacSystemFont,Segoe UI,Roboto,sans-serif', fontSize: '13px',
      background: '#0b1020', mainBkg: '#1e2739', primaryColor: '#1e2739', primaryBorderColor: '#4a5975',
      primaryTextColor: '#e6e9ef', secondaryColor: '#243049', secondaryBorderColor: '#4a5975',
      tertiaryColor: '#131a29', tertiaryBorderColor: '#33405c',
      lineColor: '#8ba0c4', textColor: '#e6e9ef', titleColor: '#e6e9ef',
      nodeBorder: '#4a5975', clusterBkg: '#131a29', clusterBorder: '#33405c',
      edgeLabelBackground: '#0f1420', labelBackground: '#0f1420', labelBoxBkgColor: '#1e2739',
      labelBoxBorderColor: '#4a5975', labelTextColor: '#e6e9ef',
      actorBkg: '#1e2739', actorBorder: '#4a5975', actorTextColor: '#e6e9ef', actorLineColor: '#4a5975',
      signalColor: '#8ba0c4', signalTextColor: '#e6e9ef',
      noteBkgColor: '#2a2340', noteTextColor: '#e6e9ef', noteBorderColor: '#5b4a86',
      activationBkgColor: '#2c3a55', activationBorderColor: '#4a5975',
      sequenceNumberColor: '#0b1020', altBackground: '#131a29',
      attributeBackgroundColorOdd: '#1e2739', attributeBackgroundColorEven: '#182031',
    },
  });
}

let timer;
document.getElementById('search').addEventListener('input', e => {
  clearTimeout(timer);
  timer = setTimeout(() => {
    q = e.target.value.trim().toLowerCase();
    if (q) {   // jump to the first project/document that matches
      const p = DATA.findIndex(pp => projHits(pp));
      if (p >= 0) { pi = p; const d = DATA[p].docs.findIndex(hits); di = d >= 0 ? d : 0; }
    }
    render();
  }, 140);
});

render();
</script></body></html>`;
}
