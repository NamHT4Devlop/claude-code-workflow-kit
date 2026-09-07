#!/usr/bin/env node
// i18n.test.cjs — the Vietnamese dictionary is keyed by the English strings themselves, which is
// convenient but rots silently: reword a card in main.js and its translation quietly stops applying,
// leaving a half-Vietnamese panel that still "works". This test makes that failure loud.
//
//   1. every key in the dictionary must still exist in main.js  (no dead translations)
//   2. every card title/description and every field label must have a translation (no half-Vietnamese)
const fs = require('fs');
const path = require('path');
const vm = require('vm');

const media = path.join(__dirname, '..', 'vscode-extension', 'media');
const mainSrc = fs.readFileSync(path.join(media, 'main.js'), 'utf8');
const i18nSrc = fs.readFileSync(path.join(media, 'i18n.js'), 'utf8');

// --- load the dictionary ---
// Both files declare their globals with `const`, which in a classic script is lexical — it never
// lands on the context object. Take the completion value instead of reading a property.
const dictCtx = {}; vm.createContext(dictCtx);
const { VI, SAME } = vm.runInContext(i18nSrc + '\n;({ VI: I18N_VI, SAME: I18N_VI_SAME });', dictCtx);
const same = new Set(SAME || []);
if (!VI || typeof VI !== 'object') { console.error('  ✗ i18n.js did not define I18N_VI'); process.exit(1); }

// --- load CATS + ACTIONS (they only depend on the A/one helpers defined alongside them) ---
const from = mainSrc.indexOf('const CATS = [');
const to = mainSrc.indexOf('const byCmd =');
if (from < 0 || to < 0 || to < from) {
  console.error('  ✗ could not locate CATS…ACTIONS in main.js (update this test if they moved)');
  process.exit(1);
}
const uiCtx = {}; vm.createContext(uiCtx);
const { CATS, ACTIONS } = vm.runInContext(mainSrc.slice(from, to) + '\n;({ CATS, ACTIONS });', uiCtx);

let pass = 0, fail = 0;
const ok = m => { console.log(`  ✓ ${m}`); pass++; };
const bad = m => { console.log(`  ✗ ${m}`); fail++; };

console.log('i18n: no dead translations');
const dead = [...Object.keys(VI), ...same].filter(k => !mainSrc.includes(k));
if (dead.length === 0) ok(`all ${Object.keys(VI).length} keys still appear in main.js`);
else { bad(`${dead.length} translation key(s) no longer exist in main.js — reworded or removed:`); dead.forEach(k => console.log(`      "${k}"`)); }

console.log('i18n: the panel is not half-translated');
const missing = [];
CATS.forEach(c => { if (!VI[c.name] && !same.has(c.name)) missing.push(`category: ${c.name}`); });
ACTIONS.forEach(a => {
  if (!VI[a.title] && !same.has(a.title)) missing.push(`title: ${a.title}`);
  if (!VI[a.desc] && !same.has(a.desc)) missing.push(`desc (${a.cmd}): ${a.desc}`);
  (a.fields || []).forEach(f => { if (!VI[f.label] && !same.has(f.label)) missing.push(`field label (${a.cmd}): ${f.label}`); });
});
if (missing.length === 0) ok(`every category, card and field label has a Vietnamese string (${ACTIONS.length} cards)`);
else { bad(`${missing.length} string(s) have no translation:`); missing.forEach(m => console.log(`      ${m}`)); }

console.log('i18n: translations are actually different text (loanwords must be declared)');
const identical = Object.entries(VI).filter(([k, v]) => k === v);
if (identical.length === 0) ok('no entry translates to itself');
else { bad(`${identical.length} entr(y/ies) map to the same English text:`); identical.forEach(([k]) => console.log(`      "${k}"`)); }

// Strings born in the extension HOST were invisible to this test — it only ever scanned main.js —
// so a Vietnamese panel could show English status text forever with the suite green. The host now
// sends keys; assert that every key it can send is assembled from translatable pieces.
console.log('i18n: host-sent status keys are translatable');
const extSrc = fs.readFileSync(path.join(__dirname, '..', 'vscode-extension', 'src', 'extension.ts'), 'utf8');
const hostKeys = [...extSrc.matchAll(/type:\s*'status'[^}]*?key:\s*'([a-z-]+)'/g)].map(m => m[1]);
if (!hostKeys.length) bad("no status keys found in extension.ts — did the host go back to sending finished sentences?");
else {
  const unhandled = hostKeys.filter(k => !mainSrc.includes(`'${k}'`));
  if (unhandled.length) { bad(`status key(s) the webview never handles: ${unhandled.join(', ')}`); }
  else ok(`all ${hostKeys.length} host status keys are handled in main.js`);
  // and the human-readable pieces those branches translate must exist in the dictionary
  const pieces = ['Claude Code ready', 'Claude Code CLI not found', 'Install it and sign in, or set cwkUi.claudePath.'];
  const missingPieces = pieces.filter(x => !VI[x] && !same.has(x));
  if (missingPieces.length) bad(`status wording with no Vietnamese: ${missingPieces.join(' | ')}`);
  else ok('status wording is translated');
}

console.log(`i18n: ${pass} passed, ${fail} failed`);
process.exit(fail === 0 ? 0 : 1);
