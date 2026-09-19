#!/usr/bin/env node
/**
 * render-html.cjs — Markdown → self-contained styled HTML (Mermaid diagrams rendered).
 *
 * Offline-aware: if the kit's `vendor/<lib>.min.js` exists and matches vendor/SHA256SUMS, the CDN <script> tags are
 * INLINED (CSP nonce preserved) so the output makes ZERO external network calls — safe for
 * locked-down enterprise networks / air-gapped machines. If vendor/ is absent, it leaves the
 * CDN reference (works online). Delete vendor/ to opt back into the small CDN-linked output.
 *
 * Usage: node render-html.cjs <input.md> [output.html] [title]   (prints the output path)
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
const { buildDocumentHtml } = require('./html-builder.js');

const mdFile = process.argv[2];
if (!mdFile || !fs.existsSync(mdFile)) {
  console.error('usage: node render-html.cjs <input.md> [output.html] [title]');
  process.exit(1);
}
const out = process.argv[3] || mdFile.replace(/\.md$/i, '') + '.html';
const title = process.argv[4] || path.basename(mdFile).replace(/\.md$/i, '').replace(/[-_]/g, ' ');

let html = buildDocumentHtml(title, fs.readFileSync(mdFile, 'utf8'));
html = inlineVendored(html);

fs.mkdirSync(path.dirname(out), { recursive: true });
fs.writeFileSync(out, html, 'utf8');
console.log(out);

/** Replace cdnjs <script src=…> with the kit's verified vendored lib inline (keeping the CSP nonce). */
function inlineVendored(html) {
  let out = html.replace(
    /<script\b([^>]*)\bsrc="https:\/\/cdnjs\.cloudflare\.com\/ajax\/libs\/([^/]+)\/[^"]+\.min\.js"([^>]*)><\/script>/gi,
    (m, pre, lib, post) => {
      const v = vendoredLib(lib);
      if (!v.file) {
        if (v.why !== 'absent') console.error(`⚠ not inlining ${v.why}; the page loads ${lib} from the CDN instead`);
        return m; // not vendored / not verified → leave CDN
      }
      const nonce = ((pre + post).match(/nonce="([^"]+)"/) || [])[1];
      const code = fs.readFileSync(v.file, 'utf8').replace(/<\/script/gi, '<\\/script');
      return `<script${nonce ? ` nonce="${nonce}"` : ''}>\n/* vendored ${lib} — offline, no external fetch */\n${code}\n</script>`;
    },
  );
  // If no cdnjs <script src> remains, drop cdnjs from the CSP allowlist too → zero external refs.
  if (!/src="https:\/\/cdnjs\.cloudflare\.com/i.test(out)) {
    out = out.replace(/\s*https:\/\/cdnjs\.cloudflare\.com/gi, '');
  }
  return out;
}
