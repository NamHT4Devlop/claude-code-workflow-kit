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
 *   node build-map.cjs .                       # → ./namht-sessions/maps/<name>-<date>.html
 *   node build-map.cjs ../your-project out.html files
 */
const fs = require('fs');
const path = require('path');

const root = path.resolve(process.argv[2] || '.');
let out = process.argv[3] || '';
let mode = process.argv[4] || 'all';

if (!fs.existsSync(root)) { console.error('✖ project root not found:', root); process.exit(1); }

const { buildGraphData } = require('./graph-builder.js');
const { buildFromCodelens } = require('./codelens-graph.cjs');

console.error('▶ analyzing', root, '(mode:', mode + ')…');

let data = null;

// A resolved call graph beats an import regex wherever one exists. `domain` mode draws the
// Knowledge Base rather than the code, so it never applies there; CODELENS=0 forces the
// regex analyzer for a side-by-side comparison.
if (mode !== 'domain' && process.env.CODELENS !== '0') {
  const attempt = buildFromCodelens(root, { depth: 3, max: 400 });
  if (attempt.ok) {
    data = attempt.data;
    console.error(`  using codelens: ${data.nodes.length} nodes · ${data.edges.length} resolved edges`);
    const missing = data.metadata.unsupportedLanguages || [];
    if (missing.length) {
      console.error(
        `  note: ${missing.join(', ')} ${missing.length === 1 ? 'is' : 'are'} outside codelens`
        + ' — those files are not in this graph; say so when you summarise it',
      );
    }
  } else {
    // Not an error: most repositories have no index, and six of the nine languages this
    // analyzer reads are outside codelens entirely. Say why, so the choice is visible.
    console.error(`  codelens not used (${attempt.why}) → static import/inheritance scan`);
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
  .replace(/__PROJECT__/g, () => escapeHtml(projectName))
  .replace('__GRAPH_DATA__', () => graphJson);
html = inlineVendored(html, __dirname); // offline: inline Cytoscape from vendor/ if present

// Default output: <root>/namht-sessions/maps/<name>-<YYYY-MM-DD>.html  (gitignored)
if (!out) {
  const dir = path.join(root, 'namht-sessions', 'maps');
  fs.mkdirSync(dir, { recursive: true });
  const slug = projectName.toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/^-|-$/g, '') || 'project';
  out = path.join(dir, `${slug}-${new Date().toISOString().slice(0, 10)}.html`);
}
fs.writeFileSync(out, html, 'utf8');

console.error(`✔ ${data.nodes.length} nodes · ${data.edges.length} edges · langs: ${(data.metadata.languages || []).join(', ') || 'n/a'} · ${data.metadata.source}`);
console.log(out); // stdout = the path, so callers can open it

function escapeHtml(s) { return String(s).replace(/[&<>"]/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c])); }

/** Inline cdnjs <script src=…> from vendor/<lib>.min.js (offline) when available; else keep CDN. */
function inlineVendored(html, dir) {
  // Walk up for vendor/ rather than assuming a depth — this file is run both from the repo and from
  // the copy symlinked into ~/.claude/skills/.
  let vendorDir = '';
  for (let d = dir, i = 0; i < 6; i++) {
    const cand = path.join(d, 'vendor');
    if (fs.existsSync(cand)) { vendorDir = cand; break; }
    const up = path.dirname(d);
    if (up === d) break;
    d = up;
  }
  if (!vendorDir) return html;
  let out = html.replace(
    /<script\b([^>]*)\bsrc="https:\/\/cdnjs\.cloudflare\.com\/ajax\/libs\/([^/]+)\/[^"]+\.min\.js"([^>]*)><\/script>/gi,
    (m, pre, lib, post) => {
      const f = path.join(vendorDir, lib + '.min.js');
      if (!fs.existsSync(f)) return m;
      const nonce = ((pre + post).match(/nonce="([^"]+)"/) || [])[1];
      const code = fs.readFileSync(f, 'utf8').replace(/<\/script/gi, '<\\/script');
      return `<script${nonce ? ` nonce="${nonce}"` : ''}>\n/* vendored ${lib} — offline, no external fetch */\n${code}\n</script>`;
    },
  );
  if (!/src="https:\/\/cdnjs\.cloudflare\.com/i.test(out)) {
    out = out.replace(/\s*https:\/\/cdnjs\.cloudflare\.com/gi, '');
  }
  return out;
}
