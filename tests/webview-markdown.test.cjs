#!/usr/bin/env node
// webview-markdown.test.cjs — the webview renders Claude's raw output as HTML, so the mini-markdown
// in media/main.js is security-relevant: model output is untrusted text and must never become live
// markup. These tests pin the escaping and the link scheme.
//
// It loads ONLY the "safe mini-markdown" section of main.js (the rest needs a DOM), by slicing
// between the section banners — so the test breaks loudly if that section is moved or renamed
// rather than silently testing nothing.
const fs = require('fs');
const path = require('path');
const vm = require('vm');

const file = path.join(__dirname, '..', 'vscode-extension', 'media', 'main.js');
const src = fs.readFileSync(file, 'utf8');
const START = '// ---------- safe mini-markdown ----------';
const NEXT = '// ---------- state ----------';
const a = src.indexOf(START), b = src.indexOf(NEXT);
if (a < 0 || b < 0 || b < a) {
  console.error(`  ✗ could not locate the mini-markdown section in ${file}`);
  console.error('    (expected the banners "safe mini-markdown" then "state" — update this test if they moved)');
  process.exit(1);
}
const ctx = { console };
vm.createContext(ctx);
vm.runInContext(src.slice(a, b), ctx);
const { esc, inl, mdToHtml } = ctx;
if (typeof mdToHtml !== 'function') { console.error('  ✗ mdToHtml was not defined by that section'); process.exit(1); }

let pass = 0, fail = 0;
const has = (name, out, needle) => {
  if (out.includes(needle)) { console.log(`  ✓ ${name}`); pass++; }
  else { console.log(`  ✗ ${name}\n      wanted to find: ${needle}\n      in: ${out}`); fail++; }
};
const hasNot = (name, out, needle) => {
  if (!out.includes(needle)) { console.log(`  ✓ ${name}`); pass++; }
  else { console.log(`  ✗ ${name}\n      must NOT contain: ${needle}\n      in: ${out}`); fail++; }
};

console.log('webview-markdown: untrusted output cannot become live markup');
hasNot('a script tag is escaped, not emitted', mdToHtml('<script>alert(1)</script>'), '<script>');
has('…and shows as text',                     mdToHtml('<script>alert(1)</script>'), '&lt;script&gt;');
hasNot('an img onerror payload is escaped',    mdToHtml('<img src=x onerror=alert(1)>'), '<img');
hasNot('raw HTML in a code fence stays inert', mdToHtml('```\n<b>x</b>\n```'), '<b>x</b>');
hasNot('raw HTML inside a table cell is escaped', mdToHtml('| a |\n|---|\n| <b>x</b> |'), '<b>x</b>');
hasNot('html in a heading is escaped',         mdToHtml('# <i>hi</i>'), '<i>hi</i>');

console.log('webview-markdown: links are restricted to http(s)');
has('an https link becomes an anchor',   inl('[ok](https://example.com)'), '<a href="https://example.com">ok</a>');
hasNot('javascript: is NOT linkified',   inl('[x](javascript:alert(1))'), '<a href');
hasNot('data: is NOT linkified',         inl('[x](data:text/html,<b>)'), '<a href');
hasNot('file: is NOT linkified',         inl('[x](file:///etc/passwd)'), '<a href');
hasNot('a quote cannot close the href',   mdToHtml('[d](https://x.test/"onfocus="alert(1))'), '"onfocus=');

console.log('webview-markdown: the formatting people actually rely on still works');
has('heading',       mdToHtml('## Title'), '<h2>Title</h2>');
has('bold',          mdToHtml('**bold**'), '<strong>bold</strong>');
has('inline code',   mdToHtml('`x`'), '<code>x</code>');
has('code fence',    mdToHtml('```\nline\n```'), '<pre class="cb"><code>');
has('bullet list',   mdToHtml('- one\n- two'), '<li>one</li>');
has('table header',  mdToHtml('| A | B |\n|---|---|\n| 1 | 2 |'), '<th>A</th>');
has('table cell',    mdToHtml('| A | B |\n|---|---|\n| 1 | 2 |'), '<td>1</td>');

console.log('webview-markdown: escaping helper');
has('ampersand first (no double-escape)', esc('&<>'), '&amp;&lt;&gt;');

console.log(`webview-markdown: ${pass} passed, ${fail} failed`);
process.exit(fail === 0 ? 0 : 1);
