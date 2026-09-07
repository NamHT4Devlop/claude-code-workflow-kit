#!/usr/bin/env node
/**
 * render-html.cjs — Markdown → self-contained styled HTML (Mermaid diagrams rendered).
 *
 * Offline-aware: if the repo's `vendor/<lib>.min.js` exists, the CDN <script> tags are
 * INLINED (CSP nonce preserved) so the output makes ZERO external network calls — safe for
 * locked-down enterprise networks / air-gapped machines. If vendor/ is absent, it leaves the
 * CDN reference (works online). Delete vendor/ to opt back into the small CDN-linked output.
 *
 * Usage: node render-html.cjs <input.md> [output.html] [title]   (prints the output path)
 */
const fs = require('fs');
const path = require('path');
const { buildDocumentHtml } = require('./html-builder.js');

const mdFile = process.argv[2];
if (!mdFile || !fs.existsSync(mdFile)) {
  console.error('usage: node render-html.cjs <input.md> [output.html] [title]');
  process.exit(1);
}
const out = process.argv[3] || mdFile.replace(/\.md$/i, '') + '.html';
const title = process.argv[4] || path.basename(mdFile).replace(/\.md$/i, '').replace(/[-_]/g, ' ');

let html = buildDocumentHtml(title, fs.readFileSync(mdFile, 'utf8'));
html = inlineVendored(html, __dirname);

fs.mkdirSync(path.dirname(out), { recursive: true });
fs.writeFileSync(out, html, 'utf8');
console.log(out);

/** Replace cdnjs <script src=…> with the vendored lib inline (keeping the CSP nonce). */
function inlineVendored(html, dir) {
  // This file runs both from resources/ and from the copies in skills/<skill>/references/, which sit
  // at different depths — walk up until a vendor/ turns up instead of assuming a fixed number of levels.
  let vendorDir = '';
  for (let d = dir, i = 0; i < 6; i++) {
    const cand = path.join(d, 'vendor');
    if (fs.existsSync(cand)) { vendorDir = cand; break; }
    const up = path.dirname(d);
    if (up === d) break;
    d = up;
  }
  if (!vendorDir) return html; // no vendor → stay on CDN (online mode)
  let out = html.replace(
    /<script\b([^>]*)\bsrc="https:\/\/cdnjs\.cloudflare\.com\/ajax\/libs\/([^/]+)\/[^"]+\.min\.js"([^>]*)><\/script>/gi,
    (m, pre, lib, post) => {
      const f = path.join(vendorDir, lib + '.min.js');
      if (!fs.existsSync(f)) return m; // that lib isn't vendored → leave CDN
      const nonce = ((pre + post).match(/nonce="([^"]+)"/) || [])[1];
      const code = fs.readFileSync(f, 'utf8').replace(/<\/script/gi, '<\\/script');
      return `<script${nonce ? ` nonce="${nonce}"` : ''}>\n/* vendored ${lib} — offline, no external fetch */\n${code}\n</script>`;
    },
  );
  // If no cdnjs <script src> remains, drop cdnjs from the CSP allowlist too → zero external refs.
  if (!/src="https:\/\/cdnjs\.cloudflare\.com/i.test(out)) {
    out = out.replace(/\s*https:\/\/cdnjs\.cloudflare\.com/gi, '');
  }
  return out;
}
