#!/usr/bin/env node
/**
 * print-fix.cjs — prepare ANY HTML for a faithful PDF, without touching the user's file.
 *
 * Reads <in.html>, writes <out.html> (a temp copy the converter prints).
 *
 * Three modes, because "keep the original formatting" and "make it dark" are different wishes:
 *   default              → layout fixes + DARK palette (#0f1420). Light backgrounds in the source are
 *                          neutralised, otherwise the forced light text lands on a light card and
 *                          disappears.
 *   PDF_LIGHT=1          → layout fixes + LIGHT palette (white page) — for printing on paper.
 *   PDF_KEEP_COLORS=1    → layout fixes ONLY. Every colour, background and style of the source is
 *                          preserved exactly; use this when the document already looks the way you
 *                          want and you only need it to paginate properly.
 *
 * The layout fixes are always applied: keep diagrams/tables/code blocks whole across pages, never
 * clip wide content (paper has no scrollbars), repeat table headers, and scale an oversized diagram
 * down to fit a page.
 */
'use strict';
const fs = require('fs');
const path = require('path');
const [, , inFile, outFile] = process.argv;
if (!inFile || !outFile) { console.error('usage: print-fix.cjs <in.html> <out.html>'); process.exit(2); }

const MARKER = 'cwk-print-css';

/* Always applied — geometry only, no colours. */
const LAYOUT = `
@page{size:A4;margin:14mm 12mm}
@media print{
  html,body{-webkit-print-color-adjust:exact;print-color-adjust:exact}
  /* a diagram, table, code block, image or quote must never be split across pages */
  .mermaid,table,pre,blockquote,figure,img,svg{break-inside:avoid!important;page-break-inside:avoid!important}
  tr,li{break-inside:avoid;page-break-inside:avoid}
  thead{display:table-header-group}
  h1,h2,h3,h4{break-after:avoid;page-break-after:avoid}
  /* overflow is CUT on paper — shrink or wrap instead of clipping */
  .mermaid,pre,table,div{overflow:visible!important}
  pre{white-space:pre-wrap!important;word-break:break-word}
  .mermaid svg,figure svg,img{width:auto!important;height:auto!important;max-width:100%!important;max-height:170mm!important}
  /* on-screen chrome that means nothing on paper */
  .toolbar,.no-print,nav.toc{display:none!important}
}`;

/* Dark palette. Mermaid bakes its colours into the SVG at render time and scopes its styles by the
   SVG id, so its text/lines can only be corrected with !important from out here. */
const DARK = `
@page{background:#0f1420}
@media print{
  html,body{background:#0f1420!important;color:#e6e9ef!important}
  /* Neutralise light panels from the source: the forced light text would otherwise sit on a light
     card and vanish. Elements that supply their own contrast (code, tables, images) keep theirs. */
  body *:not(pre):not(code):not(kbd):not(samp):not(table):not(th):not(td):not(img):not(svg):not(.mermaid):not(.mermaid *){
    background-color:transparent!important;background-image:none!important}
  h1,h2,h3,h4,h5,h6{color:#f2f4f8!important}
  p,li,span,div,em,strong,dt,dd,figcaption{color:#e6e9ef!important}
  a{color:#9bb0ff!important}
  hr{border-color:#2a3040!important}
  code,kbd,samp{background:#1b2130!important;color:#c9d2ff!important}
  pre{background:#0b1020!important;color:#e2e8f0!important;border:1px solid #2a3040}
  pre code,pre *{background:none!important;color:inherit!important}
  table{border:1px solid #2a3040!important}
  th{background:#4f46e5!important;color:#fff!important}
  td{background:#151b29!important;color:#e6e9ef!important;border-color:#2a3040!important}
  blockquote{border-left:3px solid #4f46e5!important;background:#141a28!important;color:#c3cad8!important}
  .mermaid{background:#141a28!important;border-color:#2a3040!important;padding:8px}
  .mermaid svg text,.mermaid svg .messageText,.mermaid svg .labelText,.mermaid svg .loopText,
  .mermaid svg .noteText,.mermaid svg .titleText,.mermaid svg tspan{fill:#e6e9ef!important}
  .mermaid svg .nodeLabel,.mermaid svg .edgeLabel,.mermaid svg .label{color:#e6e9ef!important;fill:#e6e9ef!important}
  .mermaid svg .edgeLabel rect,.mermaid svg .labelBkg{fill:#141a28!important;opacity:.9}
  .mermaid svg .actor,.mermaid svg .node rect,.mermaid svg .node polygon,.mermaid svg .node circle,
  .mermaid svg .node ellipse{fill:#1f2937!important;stroke:#6366f1!important}
  .mermaid svg line,.mermaid svg .messageLine0,.mermaid svg .messageLine1,.mermaid svg .edgePath path,
  .mermaid svg .flowchart-link,.mermaid svg .actor-line{stroke:#94a3b8!important}
  .mermaid svg marker path,.mermaid svg .arrowheadPath{fill:#94a3b8!important;stroke:#94a3b8!important}
  /* raster diagrams are usually black line-art on white or transparency — they need a light backing */
  img{background:#fff!important;padding:6px;border-radius:8px}
}`;

/* Light palette — a plain white page for paper. */
const LIGHT = `
@media print{
  html,body{background:#fff!important;color:#111!important}
  a{color:#1a4fd0!important}
  .mermaid{background:#fff!important}
}`;

const mode = process.env.PDF_KEEP_COLORS === '1' ? 'keep'
  : process.env.PDF_LIGHT === '1' ? 'light' : 'dark';
const css = `\n<style id="${MARKER}">${LAYOUT}${mode === 'dark' ? DARK : mode === 'light' ? LIGHT : ''}\n</style>`;

let html;
try { html = fs.readFileSync(inFile, 'utf8'); }
catch (e) { console.error(`cannot read ${inFile}: ${e.message}`); process.exit(1); }

/** Insert as late as possible so it wins over the document's own styles. lastIndexOf, because a big
 *  inlined bundle (e.g. mermaid) can contain "</body>" as a string literal. */
function insert(doc, style) {
  let at = doc.lastIndexOf('</body>');
  if (at < 0) at = doc.lastIndexOf('</html>');
  return at >= 0 ? doc.slice(0, at) + style + '\n' + doc.slice(at) : doc + style;
}

/** The copy is printed from a temp directory, so relative images/styles/scripts would resolve against
 *  the wrong folder and render broken. Anchor them to the ORIGINAL file's directory. */
function withBase(doc, originalFile) {
  if (/<base\s/i.test(doc)) return doc;                       // the document sets its own base
  const dir = path.dirname(path.resolve(originalFile));
  const href = 'file://' + dir.split(path.sep).map(encodeURIComponent).join('/') + '/';
  const tag = `<base href="${href}">`;
  const m = doc.match(/<head[^>]*>/i);                        // the first <head> is the real one
  if (m) return doc.slice(0, m.index + m[0].length) + '\n' + tag + doc.slice(m.index + m[0].length);
  return tag + '\n' + doc;
}

// Already carries our stylesheet (HTML this kit generated, or a second pass) → only fix the base URL.
if (html.includes(MARKER)) { fs.writeFileSync(outFile, withBase(html, inFile)); process.exit(0); }

fs.writeFileSync(outFile, withBase(insert(html, css), inFile));
