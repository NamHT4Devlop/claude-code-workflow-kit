#!/usr/bin/env node
/**
 * build-map.cjs — generate an interactive HTML code graph for a project.
 *
 * Uses the bundled multi-language static analyzer (graph-builder.js, pure fs/path)
 * to extract nodes (files/classes/routes) and edges (imports / extends / implements
 * / injects / calls), then injects the data into the Cytoscape viewer template and
 * writes a single self-contained HTML file you open in a browser.
 *
 * Usage:
 *   node build-map.cjs <project-root> [output.html] [mode]
 *     mode = all | files | classes | routes | domain   (default: all)
 *
 * Examples:
 *   node build-map.cjs .                       # → ./cwk-sessions/maps/<name>-<date>.html
 *   node build-map.cjs ../your-project out.html files
 */
const fs = require('fs');
const path = require('path');

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

// Per-build CSP nonce: only <script> tags carrying it may run, so nothing the scanned repository
// contributes (paths, comments, route strings) can ever become a script.
const nonce = crypto.randomBytes(16).toString('base64');

const root = path.resolve(process.argv[2] || '.');
let out = process.argv[3] || '';
let mode = process.argv[4] || 'all';

if (!fs.existsSync(root)) { console.error('✖ project root not found:', root); process.exit(1); }

const { buildGraphData } = require('./graph-builder.js');
const { buildFromProvenlens } = require('./provenlens-graph.cjs');
const { buildFullIndex, pack } = require('./provenlens-full.cjs');
const { LAYER_CONFIG } = require('./graph-builder.js');

console.error('▶ analyzing', root, '(mode:', mode + ')…');

let data = null;

// Whole-index explorer: every symbol, edge, unresolved call and source line, drawn on demand.
// The sampled graph below draws ~400 nodes around the hubs and cannot find anything outside
// them, so it is only the fallback. PROVENLENS_FULL=0 forces the sampled picture.
if (mode === 'all' && process.env.PROVENLENS !== '0' && process.env.PROVENLENS_FULL !== '0') {
  const full = buildFullIndex(root);
  if (full.ok) {
    const st = full.stats;
    console.error(`  using the full provenlens index: ${st.symbols} symbols · ${st.edges} edges · ${st.missed} unresolved · ${st.library} library calls`);
    if (st.skippedSource) console.error(`  note: ${st.skippedSource} files over the size limit or unreadable — no source shown for them`);
    const projectName = path.basename(root);
    const layers = Object.entries(LAYER_CONFIG).map(([id, cfg]) => ({ id, label: cfg.label, color: cfg.color }));
    const tpl = fs.readFileSync(path.join(__dirname, 'explorer-template.html'), 'utf8');
    // base64 is inert in markup; the layer table is ours. Function replacers, as below.
    // __NONCE__ first, so a literal "__NONCE__" inside the untrusted data is never touched.
    let html = tpl
      .replace(/__NONCE__/g, () => nonce)
      .replace(/__PROJECT__/g, () => escapeHtml(projectName))
      .replace('__LAYERS__', () => JSON.stringify(layers))
      // Which viewer built this page. A map is frozen at build time, so when someone reports that a
      // fixed bug is still there, the first question is which build they are looking at.
      .replace('__GRAPH_DATA__', () => pack({ ...full.data, kit: kitVersion() }));
    html = inlineVendored(html);
    const target = out || defaultOut(projectName);
    fs.writeFileSync(target, html, 'utf8');
    console.error(`✔ explorer · ${st.symbols} symbols · ${(Buffer.byteLength(html) / 1e6).toFixed(1)} MB · provenlens (full index)`);
    console.log(target);
    process.exit(0);
  }
  console.error(`  full index not used (${full.why}) → sampled graph`);
}

// A resolved call graph beats an import regex wherever one exists. `domain` mode draws the
// Knowledge Base rather than the code, so it never applies there; PROVENLENS=0 forces the
// regex analyzer for a side-by-side comparison.
if (mode !== 'domain' && process.env.PROVENLENS !== '0') {
  const attempt = buildFromProvenlens(root, { depth: 3, max: 400 });
  if (attempt.ok) {
    data = attempt.data;
    console.error(`  using provenlens: ${data.nodes.length} nodes · ${data.edges.length} resolved edges`);
    const missing = data.metadata.unsupportedLanguages || [];
    if (missing.length) {
      console.error(
        `  note: ${missing.join(', ')} ${missing.length === 1 ? 'is' : 'are'} outside provenlens`
        + ' — those files are not in this graph; say so when you summarise it',
      );
    }
    // `export` seeds from the busiest hubs and stops at a node cap, so this can be a
    // neighbourhood rather than the repository. When a language is indexed and still absent,
    // the picture is not of this codebase, and the whole-repo scan is the honest alternative.
    const absent = data.metadata.indexedButAbsent || [];
    if (absent.length) {
      console.error(
        `  WARNING: ${absent.join(', ')} ${absent.length === 1 ? 'is' : 'are'} indexed but absent`
        + ' from this graph — hub seeding plus the node cap did not reach them.',
      );
      console.error('           Say this in the summary, or re-run with PROVENLENS=0 for a whole-repo scan.');
    } else if (data.metadata.truncated) {
      console.error('  note: the graph hit its node cap — it shows the busiest neighbourhood, not the whole repo');
    }
  } else {
    // Not an error: most repositories have no index, and six of the nine languages this
    // analyzer reads are outside provenlens entirely. Say why, so the choice is visible.
    console.error(`  provenlens not used (${attempt.why}) → static import/inheritance scan`);
  }
}

if (!data) {
  data = buildGraphData(root, mode);
  data.metadata.source = 'static import/inheritance scan';

  // Auto-simplify very large graphs so the browser stays smooth.
  if (data.nodes.length > 1800 && mode === 'all') {
    console.error(`  ${data.nodes.length} nodes is large → re-running in 'files' mode for readability`);
    mode = 'files';
    data = buildGraphData(root, mode);
    data.metadata.source = 'static import/inheritance scan';
  }
}

const tpl = fs.readFileSync(path.join(__dirname, 'viewer-template.html'), 'utf8');
const projectName = data.metadata.projectName || path.basename(root);
// The graph embeds text taken from the scanned repo (file paths, doc comments, route strings), so it
// is untrusted. Two hazards, both handled here:
//  1. A *string* replacement argument makes `$'`, "$`", `$&`, `$$` expand as replacement patterns —
//     `$'` inserts everything after the match, which drags a real </script> into the data block and
//     ends it early. Function replacers are immune, so always pass a function.
//  2. Escaping only "</" still lets a lone "<" through into HTML context. Neutralise < and > (plus the
//     JS line terminators U+2028/9) as \u escapes — valid JSON, inert in markup.
const graphJson = JSON.stringify(data)
  .replace(/</g, '\\u003c').replace(/>/g, '\\u003e')
  .replace(/\u2028/g, '\\u2028').replace(/\u2029/g, '\\u2029');
let html = tpl
  .replace(/__NONCE__/g, () => nonce) // first: a literal "__NONCE__" inside the untrusted data must stay
  .replace(/__PROJECT__/g, () => escapeHtml(projectName))
  .replace('__GRAPH_DATA__', () => graphJson);
html = inlineVendored(html); // offline: inline Cytoscape from the kit's verified vendor/ if present

// Default output: <root>/cwk-sessions/maps/<name>-<YYYY-MM-DD>.html  (gitignored)
if (!out) out = defaultOut(projectName);
fs.writeFileSync(out, html, 'utf8');

console.error(`✔ ${data.nodes.length} nodes · ${data.edges.length} edges · langs: ${(data.metadata.languages || []).join(', ') || 'n/a'} · ${data.metadata.source}`);
console.log(out); // stdout = the path, so callers can open it

function defaultOut(projectName) {
  const dir = path.join(root, 'cwk-sessions', 'maps');
  fs.mkdirSync(dir, { recursive: true });
  const slug = projectName.toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/^-|-$/g, '') || 'project';
  const target = path.join(dir, `${slug}-${new Date().toISOString().slice(0, 10)}.html`);
  // A map is a self-contained page, frozen at the moment it was built: it carries that day's viewer
  // code and that day's index. Left beside a new one, the old file keeps opening from Finder or from
  // a bookmark and shows the old behaviour — a fixed bug looks unfixed, and a renamed symbol looks
  // present. These are regenerable and gitignored, so the superseded ones go.
  for (const f of fs.readdirSync(dir)) {
    if (!f.startsWith(`${slug}-`) || !f.endsWith('.html')) continue;
    const old = path.join(dir, f);
    if (path.resolve(old) === path.resolve(target)) continue;
    try { fs.unlinkSync(old); console.error(`  superseded: removed ${f}`); } catch { /* leave it */ }
  }
  return target;
}

/** The kit version that built this page, or '' when the manifest cannot be read. */
function kitVersion() {
  try {
    const r = kitRoot();
    if (!r) return '';
    return JSON.parse(fs.readFileSync(path.join(r, '.claude-plugin', 'plugin.json'), 'utf8')).version || '';
  } catch { return ''; }
}

function escapeHtml(s) { return String(s).replace(/[&<>"]/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c])); }

/** Inline cdnjs <script src=…> from the kit's verified vendor/<lib>.min.js (offline); else keep CDN. */
function inlineVendored(html) {
  let out = html.replace(
    /<script\b([^>]*)\bsrc="https:\/\/cdnjs\.cloudflare\.com\/ajax\/libs\/([^/]+)\/[^"]+\.min\.js"([^>]*)><\/script>/gi,
    (m, pre, lib, post) => {
      const v = vendoredLib(lib);
      if (!v.file) {
        if (v.why !== 'absent') console.error(`⚠ not inlining ${v.why}; the page loads ${lib} from the CDN instead`);
        return m;
      }
      const nonce = ((pre + post).match(/nonce="([^"]+)"/) || [])[1];
      const code = fs.readFileSync(v.file, 'utf8').replace(/<\/script/gi, '<\\/script');
      return `<script${nonce ? ` nonce="${nonce}"` : ''}>\n/* vendored ${lib} — offline, no external fetch */\n${code}\n</script>`;
    },
  );
  if (!/src="https:\/\/cdnjs\.cloudflare\.com/i.test(out)) {
    out = out.replace(/\s*https:\/\/cdnjs\.cloudflare\.com/gi, '');
  }
  return out;
}
