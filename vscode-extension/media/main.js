// @ts-nocheck
const vscode = acquireVsCodeApi();

const CATS = [
  { key: 'chat', name: 'General', icon: '💬' },
  { key: 'understand', name: 'Understand', icon: '📖' },
  { key: 'plan', name: 'Plan', icon: '🗂️' },
  { key: 'build', name: 'Build & Fix', icon: '🛠️' },
  { key: 'review', name: 'Review & QA', icon: '🔍' },
  { key: 'ops', name: 'Ops & Docs', icon: '📊' },
];
const A = (cmd, cat, icon, title, desc, fields, build, edits) => ({ cmd, cat, icon, title, desc, fields, build, edits });
const one = (name, label, ph, type = 'textarea', optional = false) => ({ name, label, ph, type, optional });

const ACTIONS = [
  A('__chat', 'chat', '💬', 'Ask anything', 'A general question — not tied to this repo. Runs plain Claude (no skill).', [one('q', 'Your question (any topic)', 'Explain the difference between SQS and Kafka…')], v => v.q),
  A('cwk-scan', 'understand', '🧠', 'Scan → Knowledge Base', 'Generate the project Knowledge Base (run once).', [], () => ''),
  A('cwk-rescan', 'understand', '♻️', 'Rescan (update KB)', 'Refresh the KB after code changes.', [], () => ''),
  A('cwk-ask', 'understand', '❓', 'Ask the codebase', 'Plain-language answer + diagram + detail.', [one('q', 'Your question', 'How does the payment flow work?')], v => v.q),
  A('cwk-map', 'understand', '🕸️', 'Dependency map', 'Interactive HTML code graph (opens in browser).', [one('scope', 'Scope (optional)', 'e.g. src/', 'text', true)], v => v.scope || ''),
  A('cwk-system-map', 'understand', '🗺️', 'System map', 'Cross-service map — open the workspace root.', [], () => ''),
  A('cwk-document', 'understand', '📄', 'Document a feature', 'Business↔code doc anyone can follow.', [one('topic', 'Feature / module / entity', 'Orders module', 'text')], v => v.topic),
  A('cwk-discover', 'plan', '💡', 'Sharpen an idea', 'Turn a fuzzy idea into a crisp brief.', [one('idea', 'The idea / problem', 'I want to build…')], v => v.idea),
  A('cwk-plan', 'plan', '📋', 'Plan an epic', 'Epic → features → user stories → sprint plan.', [one('title', 'Epic title', 'Recurring invoices', 'text'), one('desc', 'Description (what & why)', 'Describe the epic…')], v => `${v.title}\n\n${v.desc}`),
  A('cwk-plan-review', 'plan', '🔎', 'Review a plan', 'Multi-lens critique + verdict.', [one('plan', 'The plan / user stories', 'Paste the plan…')], v => v.plan),
  A('cwk-user-story', 'plan', '📝', 'Create user stories', 'Deep-investigate → features + INVEST stories, each AC as granular as possible.', [one('req', 'Requirement / idea (leave blank if using Slack)', 'As a coach I want…', 'textarea', true), one('slack', 'Slack thread / channel URL (optional)', 'https://…slack.com/archives/…', 'text', true)], v => [v.req, v.slack ? ('Slack source: ' + v.slack) : ''].filter(Boolean).join('\n\n')),
  A('cwk-issues', 'plan', '🎫', 'Stories → tracker issues', 'Turn a plan / user stories into GitHub or Jira issues. Previews first — nothing is created without your OK.', [one('src', 'Plan or user-story file (blank = pick the most recent)', 'cwk-sessions/plans/…md', 'text', true), one('target', 'Target project', 'e.g. github NamHT4Devlop/my-repo', 'text', true), one('create', 'Create them for real (otherwise it only writes a preview file)', 'It still shows you every issue and asks before creating anything.', 'checkbox', true)], v => [v.src || '', v.target || '', v.create ? '--create' : ''].filter(Boolean).join(' ')),
  A('cwk-build', 'build', '🏗️', 'Build a feature', '13-step pipeline: plan → code → review → test.', [one('req', 'Requirement', 'Add a forgot-password flow via email OTP')], v => v.req, true),
  A('cwk-fix-bug', 'build', '🐛', 'Fix a bug', 'Triage (code vs config/spec) → root-cause → regression test → minimal fix.', [one('err', 'Error / stack trace, or a QA report (expected vs actual + repro + environment + failing case)', 'Paste the error, or the QA bug report…')], v => v.err, true),
  A('cwk-migrate', 'build', '🔀', 'Migration / deprecation', 'Safe API/DB/event/lib change with rollback.', [one('change', "What's changing", 'Add nullable dueDate column to tasks')], v => v.change, true),
  A('cwk-simplify', 'build', '✨', 'Simplify code', 'Behavior-preserving cleanup; tests stay green.', [one('target', 'File / function (optional)', 'src/foo.ts', 'text', true)], v => v.target || '', true),
  A('cwk-perf', 'build', '⚡', 'Optimize performance', 'Measure-first; prove before/after.', [one('area', 'Slow area / endpoint / query', 'GET /orders is slow')], v => v.area, true),
  A('cwk-observe', 'build', '📡', 'Add observability', 'Structured logs + trace IDs + metrics.', [one('area', 'Service / flow to instrument', 'payments service')], v => v.area, true),
  A('cwk-rails-to-spring', 'build', '🔁', 'Port to another stack', 'Rails+GraphQL → Spring Boot, contract + behavior preserved (golden-test verified).', [one('scope', 'What to port (source → target stack, endpoint set)', 'Rails+GraphQL → Spring Boot/MyBatis; all GraphQL + these 3-5 REST APIs: …')], v => v.scope, true),
  A('cwk-review', 'review', '🔍', 'Review code / PR', 'Two-phase review vs the KB.', [one('target', 'File / PR# (blank = current branch)', 'e.g. #123 or src/foo.ts', 'text', true)], v => v.target || ''),
  A('cwk-qa', 'review', '✅', 'QA test cases', 'User story → new + regression cases.', [one('story', 'User story + acceptance criteria', 'As a…, I want…, so that…')], v => v.story),
  A('cwk-qa-integration', 'review', '🌐', 'Run E2E QA', 'Drive a running app in a browser (needs a URL).', [one('url', 'App URL', 'http://localhost:3000', 'text')], v => v.url),
  A('cwk-security-audit', 'review', '🛡️', 'Security audit', 'Whole-repo OWASP + STRIDE sweep.', [one('scope', 'Scope (optional)', 'e.g. auth module', 'text', true)], v => v.scope || ''),
  A('cwk-design-review', 'review', '🎨', 'Design / a11y review', 'UI/UX + accessibility (URL or components).', [one('target', 'URL or path', 'http://localhost:3000', 'text')], v => v.target),
  A('cwk-pr', 'review', '🔀', 'Prepare / review PR', 'Draft a PR desc, or review a PR#.', [one('pr', 'PR# to review (blank = prepare from branch)', 'e.g. 123', 'text', true)], v => (v.pr ? `review ${v.pr}` : '')),
  A('cwk-drift', 'review', '🧭', 'Docs vs reality check', 'Find where the Knowledge Base, plans and code have drifted apart — read-only.', [one('scope', 'Scope (optional)', 'e.g. orders module (blank = whole repo)', 'text', true), one('fix', 'Also refresh the stale docs it finds (--fix-docs)', 'Asks you first, backs the files up, and only updates the Knowledge Base — never your source code.', 'checkbox', true)], v => [v.scope || '', v.fix ? '--fix-docs' : ''].filter(Boolean).join(' ')),
  A('cwk-splunk-report', 'ops', '🚨', 'Splunk error digest', 'Per-app errors → table → Slack.', [one('args', 'index / env / app / window / Slack URL (blank = it asks)', 'index=app_logs cai_enviroment=prod cai_app=payments 24h')], v => v.args || ''),
  A('cwk-runbook', 'ops', '🛟', 'Operational runbook', 'Health checks, deploy/rollback and incident playbooks a teammate can follow at 2am.', [one('svc', 'Service / scope (blank = it asks)', 'e.g. payments service', 'text', true)], v => v.svc || ''),
  A('cwk-retro', 'ops', '🔄', 'Retrospective', 'What shipped + action items from git history.', [one('window', 'Time window', '7d', 'text')], v => v.window || ''),
  A('cwk-pdf', 'ops', '📑', 'Export to PDF', 'Turn a report/doc into a PDF.', [one('file', 'File to export (.md/.html)', 'cwk-sessions/…/report.md', 'text')], v => v.file),
  A('cwk-skillify', 'ops', '🧩', 'Create a new skill', 'Scaffold a new cwk-* skill (for devs).', [one('spec', 'Name + purpose', 'changelog — generate a release changelog from git')], v => v.spec),
];
const byCmd = c => ACTIONS.find(a => a.cmd === c);

// ---------- i18n ----------
// LANG comes from cwkUi.language via the 'config' message. Keys ARE the English
// strings, so a missing translation shows English rather than a broken placeholder.
let LANG = 'en';
const t = s => (LANG === 'vi' && typeof I18N_VI !== 'undefined' && I18N_VI[s]) || s;

// ---------- safe mini-markdown ----------
function esc(s) { return s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;'); }
function inl(s) { return s.replace(/`([^`]+)`/g, '<code>$1</code>').replace(/\*\*([^*]+)\*\*/g, '<strong>$1</strong>').replace(/\[([^\]]+)\]\((https?:[^)\s]+)\)/g, '<a href="$2">$1</a>'); }
function mdToHtml(md) {
  const L = esc(md || '').split('\n'); let out = ''; let i = 0; let lb = [];
  const flush = () => { if (lb.length) { out += '<ul>' + lb.map(x => '<li>' + inl(x) + '</li>').join('') + '</ul>'; lb = []; } };
  while (i < L.length) {
    const ln = L[i];
    if (/^```/.test(ln)) { flush(); i++; let b = ''; while (i < L.length && !/^```/.test(L[i])) { b += L[i] + '\n'; i++; } i++; out += '<pre class="cb"><code>' + b + '</code></pre>'; continue; }
    if (/^\s*\|.*\|\s*$/.test(ln) && i + 1 < L.length && /^\s*\|[-:\s|]+\|\s*$/.test(L[i + 1])) {
      flush(); const hd = ln.trim().replace(/^\||\|$/g, '').split('|').map(c => c.trim()); i += 2; const rows = [];
      while (i < L.length && /^\s*\|.*\|\s*$/.test(L[i])) { rows.push(L[i].trim().replace(/^\||\|$/g, '').split('|').map(c => c.trim())); i++; }
      out += '<table><thead><tr>' + hd.map(c => '<th>' + inl(c) + '</th>').join('') + '</tr></thead><tbody>' + rows.map(r => '<tr>' + r.map(c => '<td>' + inl(c) + '</td>').join('') + '</tr>').join('') + '</tbody></table>'; continue;
    }
    const h = ln.match(/^(#{1,4})\s+(.*)/); if (h) { flush(); out += `<h${h[1].length}>` + inl(h[2]) + `</h${h[1].length}>`; i++; continue; }
    const li = ln.match(/^\s*[-*]\s+(.*)/); if (li) { lb.push(li[1]); i++; continue; }
    if (/^\s*$/.test(ln)) { flush(); i++; continue; }
    flush(); out += '<p>' + inl(ln) + '</p>'; i++;
  }
  flush(); return out;
}

// ---------- state ----------
const app = document.getElementById('app');
const rid = () => 'r' + Date.now().toString(36) + Math.random().toString(36).slice(2, 6);
let statusMsg = 'Checking Claude Code…', statusOk = null, filter = '', catFilter = '';
let spend = null;   // { session:{usd,runs}, today:{usd,runs}, week:{usd,runs}, rate }
// A per-run chip never adds up to a number you can act on — this is the running total.
function spendEl() {
  if (!spend || !(spend.today.usd > 0 || spend.session.usd > 0)) return null;
  const m = (b) => '$' + (b.usd || 0).toFixed(2) + (spend.rate ? ' ≈ ' + Math.round(b.usd * spend.rate).toLocaleString() + '₫' : '');
  const e = el('div', 'spend', `\u{1F4B0} this session ${m(spend.session)} · today ${m(spend.today)} (${spend.today.runs} runs) · 7d ${m(spend.week)}`);
  e.title = 'API-equivalent value of the runs started from this panel, from Claude\u2019s own result events. '
    + 'Kept per day on this machine for 60 days. On a Team/Enterprise seat you are NOT billed per token \u2014 '
    + 'treat it as usage, not a charge.';
  return e;
}
let history = [];                 // from host (persisted)
const runs = {};                  // runId → { cmd, title, values, status, log, result, sessionId, report, files, steps }
let cur = { view: 'home', runId: null, a: null, values: null };
const el = (t, c, x) => { const e = document.createElement(t); if (c) e.className = c; if (x != null) e.textContent = x; return e; };
const ago = ms => { const s = Math.max(1, Math.round((Date.now() - ms) / 1000)); if (s < 60) return s + 's'; if (s < 3600) return Math.round(s / 60) + 'm'; if (s < 86400) return Math.round(s / 3600) + 'h'; return Math.round(s / 86400) + 'd'; };
const dot = st => st === 'running' ? '🟡' : st === 'done' ? '🟢' : st === 'cancelled' ? '⚪' : '🔴';
const kt = n => (n >= 1000 ? (n / 1000).toFixed(1) + 'k' : String(n || 0));
const costText = r => (r && r.cost != null) ? `💰 $${(r.cost || 0).toFixed(4)}${r.vnd ? ' ≈ ' + r.vnd.toLocaleString() + '₫' : ''} · ${kt(r.usage && r.usage.input)}→${kt(r.usage && r.usage.output)} tok${r.usage && r.usage.cacheRead ? ' · ' + kt(r.usage.cacheRead) + ' cached' : ''}` : '';
// Enter submits, Shift+Enter = newline. Guards IME composition so typing Vietnamese (or any
// language that confirms with Enter) never fires an accidental submit mid-word.
function onEnter(inp, fn) { inp.addEventListener('keydown', e => { if (e.key === 'Enter' && !e.shiftKey && !e.isComposing && e.keyCode !== 229) { e.preventDefault(); fn(); } }); }

// ---------- model picker (per run + per follow-up; the session keeps context across models) ----------
const MODELS = [
  { id: 'haiku', label: 'Haiku', hint: 'cheapest · quick lookups' },
  { id: 'sonnet', label: 'Sonnet', hint: 'balanced · ~5× cheaper than Opus' },
  { id: 'opus', label: 'Opus', hint: 'most capable · priciest' },
  { id: '', label: 'Default', hint: 'your Claude default' },
];
let defaultModel = 'sonnet';
let uiMode = 'full';   // 'readonly' hides the code-editing cards (the host blocks them regardless)
function modelLabel(id) { if (id == null) id = defaultModel; const m = MODELS.find(x => x.id === id); return m ? m.label : (id || 'Default'); }
function modelKey(id) { if (id == null) id = defaultModel; return id || 'default'; }
function modelSelect(selected) {
  const s = el('select', 'field modelsel m-' + modelKey(selected));
  MODELS.forEach(mm => { const o = document.createElement('option'); o.value = mm.id; o.textContent = mm.label + (mm.hint ? ' · ' + mm.hint : ''); if (mm.id === selected) o.selected = true; s.appendChild(o); });
  s.onchange = () => { s.className = 'field modelsel m-' + modelKey(s.value); };
  return s;
}
// compact colored picker (dot + model name) for the follow-up row
function modelPicker(selected) {
  const wrap = el('span', 'modelpick m-' + modelKey(selected));
  wrap.appendChild(el('span', 'mp-dot'));
  const s = el('select', 'mp-sel');
  MODELS.forEach(mm => { const o = document.createElement('option'); o.value = mm.id; o.textContent = mm.label; o.title = mm.hint; if (mm.id === selected) o.selected = true; s.appendChild(o); });
  s.onchange = () => { wrap.className = 'modelpick m-' + modelKey(s.value); };
  wrap.appendChild(s); wrap._select = s;
  return wrap;
}

// ---------- layout: narrow (sidebar) vs wide (app panel) ----------
const WIDE = () => window.innerWidth >= 680;
// Build (wide) or clear (narrow) the shell, return the element to render page content into.
function mount() {
  const wide = WIDE(); document.body.classList.toggle('wide', wide);
  if (wide) {
    let shell = app.querySelector('.shell');
    if (!shell) { app.innerHTML = ''; shell = el('div', 'shell'); shell.appendChild(el('aside', 'rail')); shell.appendChild(el('main', 'content')); app.appendChild(shell); }
    renderRail(shell.querySelector('.rail'));
    const content = shell.querySelector('.content'); content.innerHTML = ''; return content;
  }
  app.innerHTML = ''; return app;
}
function renderRail(rail) {
  rail.innerHTML = '';
  rail.appendChild(el('div', 'brand', '⬡ Workflow Kit'));
  const search = el('input', 'search'); search.type = 'text'; search.placeholder = 'Search…'; search.value = filter;
  search.oninput = () => { filter = search.value.toLowerCase(); refreshContentGrid(); };
  rail.appendChild(search);
  const nv = el('div', 'railnav');
  const mk = (label, icon, active, on) => { const b = el('button', 'railitem' + (active ? ' active' : '')); b.appendChild(el('span', 'ri-ic', icon)); b.appendChild(el('span', null, label)); b.onclick = on; return b; };
  nv.appendChild(mk(t('Home'), '⌂', cur.view === 'home' && !catFilter, () => { catFilter = ''; renderHome(); }));
  CATS.forEach(c => nv.appendChild(mk(t(c.name), c.icon, cur.view === 'home' && catFilter === c.key, () => { catFilter = c.key; if (cur.view !== 'home') renderHome(); else { renderRail(rail); refreshContentGrid(); } })));
  rail.appendChild(nv);
  const running = Object.values(runs).filter(r => r.status === 'running').length;
  const rh = el('div', 'rail-h'); rh.appendChild(el('span', null, 'Recent')); if (running) rh.appendChild(el('span', 'badge', running + ' running')); rail.appendChild(rh);
  const rc = el('div', 'rail-recent');
  (history || []).slice(0, 12).forEach(it => {
    const a = byCmd(it.command); const row = el('button', 'hrow');
    row.appendChild(el('span', 'hic', a ? a.icon : '•'));
    const mid = el('span', 'hmid'); mid.appendChild(el('span', 'ht', it.title || it.command)); mid.appendChild(el('span', 'hmeta', dot(it.status) + ' ' + ago(it.when) + (it.cost ? ' · $' + it.cost.toFixed(3) : ''))); row.appendChild(mid);
    row.onclick = () => reopen(it); rc.appendChild(row);
  });
  if (!history || !history.length) rc.appendChild(el('div', 'muted tiny', 'No runs yet — pick a task.'));
  rail.appendChild(rc);
  const foot = el('div', 'railfoot');
  if (history && history.length) { const clr = el('button', 'link', 'clear history'); clr.onclick = () => vscode.postMessage({ type: 'clearHistory' }); foot.appendChild(clr); }
  foot.appendChild(el('div', 'status ' + (statusOk === false ? 'bad' : statusOk ? 'ok' : ''), statusMsg));
  const sp = spendEl(); if (sp) foot.appendChild(sp);
  rail.appendChild(foot);
}
function heroEl() {
  const h = el('div', 'hero');
  const cat = CATS.find(c => c.key === catFilter);
  h.appendChild(el('div', 'hero-t', cat ? cat.icon + '  ' + cat.name : 'What do you want to do?'));
  h.appendChild(el('div', 'hero-d', cat ? 'Pick a task in this group.' : 'Plan, build, review, or ask about your codebase. Each card runs a Claude Code skill under the hood.'));
  return h;
}
function refreshContentGrid() {
  const content = app.querySelector('.shell .content'); if (!content) return;
  content.innerHTML = ''; content.appendChild(heroEl()); renderGridsInto(content);
}
function nav() {
  const bar = el('div', 'nav');
  const home = el('button', 'navbtn' + (cur.view === 'home' ? ' active' : ''), '⌂ Home'); home.onclick = () => { catFilter = ''; renderHome(); }; bar.appendChild(home);
  const running = Object.values(runs).filter(r => r.status === 'running').length;
  if (running) bar.appendChild(el('span', 'badge', running + ' running'));
  return bar;
}

// ---------- home ----------
function renderHome() {
  cur = { view: 'home', runId: null, a: null, values: null };
  const root = mount();
  if (WIDE()) { root.appendChild(heroEl()); renderGridsInto(root); return; }
  // narrow (sidebar) layout
  root.appendChild(nav());
  const head = el('div', 'head');
  head.appendChild(el('div', 'brand', '⬡ Workflow Kit'));
  head.appendChild(el('div', 'status ' + (statusOk === false ? 'bad' : statusOk ? 'ok' : ''), statusMsg));
  const sp = spendEl(); if (sp) head.appendChild(sp);
  root.appendChild(head);
  if (history.length) {
    const rcw = el('div', 'recent');
    const rhw = el('div', 'recent-h'); rhw.appendChild(el('span', null, t('Recent & running')));
    const clr = el('button', 'link', 'clear'); clr.onclick = () => vscode.postMessage({ type: 'clearHistory' }); rhw.appendChild(clr);
    rcw.appendChild(rhw);
    history.slice(0, 8).forEach(it => {
      const a = byCmd(it.command); const row = el('button', 'hrow');
      row.appendChild(el('span', 'hic', (a ? a.icon : '•')));
      const mid = el('span', 'hmid'); mid.appendChild(el('span', 'ht', it.title || it.command)); mid.appendChild(el('span', 'hmeta', dot(it.status) + ' ' + it.status + ' · ' + ago(it.when) + (it.cost ? ' · $' + it.cost.toFixed(3) : ''))); row.appendChild(mid);
      row.onclick = () => reopen(it); rcw.appendChild(row);
    });
    root.appendChild(rcw);
  }
  const gw = el('div');
  const search = el('input', 'search'); search.type = 'text'; search.placeholder = 'Search actions…'; search.value = filter;
  search.oninput = () => { filter = search.value.toLowerCase(); gw.innerHTML = ''; renderGridsInto(gw); search.focus(); };
  root.appendChild(search);
  root.appendChild(gw); renderGridsInto(gw);
}
function renderGridsInto(wrap) {
  const cats = catFilter ? CATS.filter(c => c.key === catFilter) : CATS;
  let any = false;
  cats.forEach(cat => {
    const items = ACTIONS.filter(a => a.cat === cat.key && !(uiMode === 'readonly' && a.edits) && (!filter || (a.title + ' ' + a.desc + ' ' + a.cmd).toLowerCase().includes(filter)));
    if (!items.length) return; any = true;
    wrap.appendChild(el('div', 'cat', cat.icon + '  ' + t(cat.name)));
    const grid = el('div', 'grid');
    items.forEach(a => {
      const card = el('button', 'card'); const top = el('div', 'card-top');
      top.appendChild(el('span', 'card-ic', a.icon)); if (a.edits) top.appendChild(el('span', 'tag', t('edits code'))); card.appendChild(top);
      card.appendChild(el('div', 'card-t', t(a.title))); card.appendChild(el('div', 'card-d', t(a.desc)));
      card.onclick = () => renderForm(a); grid.appendChild(card);
    });
    wrap.appendChild(grid);
  });
  if (!any) wrap.appendChild(el('p', 'muted', 'No actions match your search.'));
}
function reopen(it) {
  // Rebuild the run from persisted history if it's not live in this session. The
  // sessionId survives reloads (Claude persists sessions on disk) → follow-up resumes it.
  if (!runs[it.runId]) {
    const q0 = it.values ? (Object.keys(it.values).filter(k => k !== '__model').map(k => it.values[k]).filter(Boolean)[0] || '') : '';
    runs[it.runId] = { cmd: it.command, title: it.title || it.command, values: it.values || {},
      status: it.status || 'done', log: it.log || '', result: it.result || '', sessionId: it.sessionId || null, report: it.report || null, files: [], steps: [],
      model: it.model != null ? it.model : (it.values && it.values.__model != null ? it.values.__model : undefined),
      __q: q0,
      // seed turns so a follow-up doesn't hide the original Q&A (renderChat's fallback stops firing once turns is non-empty)
      turns: it.result ? [{ q: q0, a: it.result, status: it.status || 'done' }] : [] };
  }
  openRun(it.runId);
}

// ---------- form ----------
function renderForm(a, values) {
  cur = { view: 'form', runId: null, a, values };
  const root = mount(); root.appendChild(nav());
  root.appendChild(el('h2', null, a.icon + '  ' + a.title));
  root.appendChild(el('p', 'muted', a.desc));
  if (a.edits) root.appendChild(el('div', 'warn', '⚠ This changes code (auto-approve). Review the diff in Source Control afterwards; git-guard still blocks dangerous git.'));
  const inputs = {};
  const mdl = modelSelect(values && values.__model != null ? values.__model : defaultModel);
  const collect = () => { const vals = {}; Object.keys(inputs).forEach(k => { const i = inputs[k]; vals[k] = i.type === 'checkbox' ? (i.checked ? 'yes' : '') : i.value.trim(); }); return vals; };
  const missingRequired = vals => a.fields.some(f => !f.optional && !vals[f.name]);
  const doRun = () => {
    const vals = collect();
    if (missingRequired(vals)) { run.textContent = t('Fill the required field'); setTimeout(() => run.textContent = t('▶  Run'), 1200); return; }
    vals.__model = mdl.value;
    const id = rid();
    const q = (a.build(vals) || a.title || a.cmd);
    runs[id] = { cmd: a.cmd, title: a.title, values: vals, status: 'running', log: '', result: '', sessionId: null, report: null, files: [], steps: [], model: mdl.value, __q: q, turns: [{ q, a: '', status: 'running' }] };
    vscode.postMessage({ type: 'run', runId: id, command: a.cmd, args: (a.build(vals) || '').trim(), title: a.title, values: vals, model: mdl.value });
    openRun(id);
  };
  a.fields.forEach(f => {
    if (f.type === 'checkbox') {          // opt-in toggle (e.g. drift's --fix-docs) — label sits beside the box
      const wrap = el('label', 'flabel checkrow');
      const box = el('input', 'checkfield'); box.type = 'checkbox';
      if (values && values[f.name]) box.checked = true;
      inputs[f.name] = box;
      wrap.appendChild(box); wrap.appendChild(el('span', '', t(f.label)));
      root.appendChild(wrap);
      if (f.ph) root.appendChild(el('p', 'muted tiny', t(f.ph)));
      return;
    }
    root.appendChild(el('label', 'flabel', t(f.label)));
    const inp = f.type === 'textarea' ? el('textarea', 'field') : el('input', 'field'); if (f.type !== 'textarea') inp.type = 'text';
    inp.placeholder = t(f.ph || ''); if (values && values[f.name] != null) inp.value = values[f.name]; inputs[f.name] = inp;
    onEnter(inp, doRun); root.appendChild(inp);
  });
  root.appendChild(el('label', 'flabel', t('Model  ·  cheaper = fewer tokens / lower cost')));
  root.appendChild(mdl);
  const row = el('div', 'formbtns');
  const run = el('button', 'primary', t('▶  Run'));
  run.onclick = doRun;
  row.appendChild(run);
  if (a.edits) {
    const iv = el('button', 'ghost inline-iv', t('⚡ Interactive'));
    iv.title = 'Open a terminal running Claude Code interactively — see each diff and approve / reject / redo, like the official panel.';
    iv.onclick = () => {
      const vals = collect();
      if (missingRequired(vals)) { iv.textContent = t('Fill the required field'); setTimeout(() => iv.textContent = t('⚡ Interactive'), 1200); return; }
      vscode.postMessage({ type: 'interactive', command: a.cmd, args: (a.build(vals) || '').trim(), title: a.title, model: mdl.value });
    };
    row.appendChild(iv);
  }
  root.appendChild(row);
  root.appendChild(el('p', 'muted tiny', t('↵ Enter to run · ⇧ Shift+Enter for a new line') + (a.edits ? t('  ·  ⚡ Interactive = terminal with approve/reject per edit') : '')));
  if (a.fields[0]) setTimeout(() => inputs[a.fields[0].name].focus(), 30);
}

// ---------- run view (per runId; survives navigation) ----------
let logEl, chatEl, thinkingEl, doneEl, toggleBtn, followRow, costEl, auxEl, cancelBtn;
function showView(which) { const act = which === 'activity'; logEl.style.display = act ? 'block' : 'none'; chatEl.style.display = act ? 'none' : 'flex'; toggleBtn.textContent = act ? 'Result' : 'Activity'; }
function lastRunningTurn(r) { if (!r.turns) return null; for (let i = r.turns.length - 1; i >= 0; i--) if (r.turns[i].status === 'running') return r.turns[i]; return null; }
function openRun(id) {
  cur = { view: 'run', runId: id, a: null, values: null }; const r = runs[id]; if (!r) return renderHome();
  const root = mount(); root.appendChild(nav());
  const a = byCmd(r.cmd);
  root.appendChild(el('h2', null, (a ? a.icon + '  ' : '') + r.title));
  const bar = el('div', 'runbar');
  cancelBtn = el('button', 'ghost', t('Cancel')); cancelBtn.onclick = () => vscode.postMessage({ type: 'cancel', runId: id });
  cancelBtn.style.display = r.status === 'running' ? '' : 'none'; bar.appendChild(cancelBtn);
  toggleBtn = el('button', 'ghost', 'Result'); toggleBtn.onclick = () => showView(logEl.style.display === 'none' ? 'activity' : 'result'); bar.appendChild(toggleBtn);
  if (a) { const fb = el('button', 'ghost', '↻ Form'); fb.onclick = () => renderForm(a, r.values); bar.appendChild(fb); }
  doneEl = el('span', 'runstate ' + (r.status === 'running' ? '' : (r.status === 'done' ? 'ok' : 'bad')), '● ' + r.status); bar.appendChild(doneEl);
  costEl = el('span', 'costchip', costText(r)); costEl.title = 'Estimated API-equivalent cost for this run (all turns). Team/Enterprise seats are not billed per token. "cached" = KB context re-read from cache (the hidden token driver).'; bar.appendChild(costEl);
  const modelChip = el('span', 'modelchip m-' + modelKey(r.model), '⚙ ' + modelLabel(r.model)); modelChip.title = 'Model for this session — change it per follow-up below; the session keeps its context across models.'; bar.appendChild(modelChip);
  root.appendChild(bar);
  if (r.report) addReportBtn(r.report);
  auxEl = el('div', 'aux'); root.appendChild(auxEl); renderAux(r);
  chatEl = el('div', 'chat'); root.appendChild(chatEl); renderChat(r);
  logEl = el('pre', 'output'); logEl.textContent = r.log || '(No activity captured for this run. Older runs opened from Recent keep only the final answer + cost + saved log tail; re-run to watch live activity.)'; root.appendChild(logEl);
  showView('result');
  // follow-up (continue the same session as a chat)
  followRow = el('div', 'follow');
  const fi = el('textarea', 'field'); fi.placeholder = 'Ask a follow-up… (Enter to send · Shift+Enter = new line)'; fi.rows = 2; followRow.appendChild(fi);
  const fmdl = modelPicker(r.model != null ? r.model : defaultModel); fmdl.title = 'Model for this follow-up — the session keeps its full context even if you switch model (e.g. Sonnet to plan, Haiku for a cheap follow-up).'; followRow.appendChild(fmdl);
  const send = el('button', 'primary', 'Send'); send.disabled = r.status === 'running';
  const doSend = () => {
    if (send.disabled) return; const t = fi.value.trim(); if (!t) return;
    const mv = fmdl._select.value; fi.value = '';
    runs[id].model = mv; runs[id].status = 'running';
    runs[id].turns = runs[id].turns || []; runs[id].turns.push({ q: t, a: '', status: 'running' });
    if (modelChip) { modelChip.textContent = '⚙ ' + modelLabel(mv); modelChip.className = 'modelchip m-' + modelKey(mv); }
    send.disabled = true; if (doneEl) { doneEl.className = 'runstate'; doneEl.textContent = '● running…'; }
    if (cancelBtn) cancelBtn.style.display = '';
    renderChat(runs[id]); showView('result');
    vscode.postMessage({ type: 'followup', runId: id, text: t, sessionId: runs[id].sessionId, model: mv });
  };
  send.onclick = doSend; onEnter(fi, doSend);
  followRow.appendChild(send);
  root.appendChild(followRow);
}
function addReportBtn(path) { if (!doneEl) return; const b = el('button', 'primary small', t('📄 Report')); b.onclick = () => vscode.postMessage({ type: 'openReport', path }); doneEl.parentElement.appendChild(b); }

// ---------- step bar + changed-files panel (live during a run) ----------
function renderAux(r) {
  if (!auxEl) return; auxEl.innerHTML = '';
  if (r.steps && r.steps.length >= 2) auxEl.appendChild(renderStepBar(r.steps, r.status));
  if (r.files && r.files.length) auxEl.appendChild(renderFilesPanel(r.files));
}
function renderStepBar(steps, status) {
  const wrap = el('div', 'stepbar');
  const maxN = Math.max.apply(null, steps.map(s => s.n));
  const live = status === 'running';
  steps.forEach(s => {
    const active = live && s.n === maxN;
    wrap.appendChild(el('span', 'stepchip ' + (active ? 'active' : 'done'), 'Step ' + s.n + (s.label ? ' · ' + s.label : '')));
  });
  return wrap;
}
function renderFilesPanel(files) {
  const box = el('div', 'files');
  const h = el('div', 'files-h'); h.appendChild(el('span', null, '📝 Files changed')); h.appendChild(el('span', 'files-n', String(files.length))); box.appendChild(h);
  files.forEach(f => {
    const isNew = f.tool === 'Write';
    const row = el('div', 'frow');
    row.appendChild(el('span', 'fic', isNew ? '📄' : '✏️'));
    const nm = el('button', 'fname', f.path.split('/').pop()); nm.title = f.path + ' — click to open';
    nm.onclick = () => vscode.postMessage({ type: 'open', path: f.path }); row.appendChild(nm);
    row.appendChild(el('span', 'fmeta', isNew ? 'new file' : (f.count + (f.count > 1 ? ' edits' : ' edit'))));
    const tg = el('button', 'fdiff', 'diff ▾'); row.appendChild(tg);
    const dbox = el('div', 'fdiffbox'); dbox.style.display = 'none'; dbox.appendChild(renderDiff(f));
    tg.onclick = () => { const open = dbox.style.display === 'none'; dbox.style.display = open ? 'block' : 'none'; tg.textContent = open ? 'diff ▴' : 'diff ▾'; };
    box.appendChild(row); box.appendChild(dbox);
  });
  return box;
}
function renderDiff(f) {
  const wrap = el('div'); const eds = (f.edits || []).slice(-20);
  eds.forEach((e, i) => {
    if (eds.length > 1) wrap.appendChild(el('div', 'edit-h', 'change ' + (i + 1)));
    const pre = el('pre', 'diff');
    const put = (txt, cls, sign) => String(txt).split('\n').slice(0, 80).forEach(ln => { pre.appendChild(el('span', cls, sign + ln)); });
    if (e.old) put(e.old, 'del', '- ');
    if (e.new) put(e.new, 'add', '+ ');
    wrap.appendChild(pre);
  });
  return wrap;
}

// ---------- chat transcript: each question + answer in its own bubble ----------
function renderChat(r) {
  if (!chatEl) return;
  chatEl.innerHTML = ''; thinkingEl = null;
  let turns = r.turns;
  if ((!turns || !turns.length) && r.result) turns = [{ q: r.__q || '', a: r.result, status: 'done' }];
  if (!turns || !turns.length) turns = [{ q: r.__q || '', a: '', status: r.status === 'running' ? 'running' : 'done' }];
  turns.forEach(t => {
    const turn = el('div', 'turn');
    if (t.q) { const qb = el('div', 'bubble question'); qb.appendChild(el('div', 'bubble-h', 'You asked')); qb.appendChild(el('div', 'qtext', t.q)); turn.appendChild(qb); }
    const ab = el('div', 'bubble answer' + (t.status === 'running' ? ' running' : ''));
    ab.appendChild(el('div', 'bubble-h', '⚙ ' + modelLabel(r.model) + ' · answer'));
    const body = el('div', 'result atext');
    if (t.a) body.innerHTML = mdToHtml(t.a);
    else if (t.status === 'running') { const th = el('div', 'thinking'); th.textContent = r._lastLog || 'working…'; body.appendChild(th); thinkingEl = th; }
    else body.appendChild(el('div', 'muted', '(no answer — open Activity for details)'));
    ab.appendChild(body); turn.appendChild(ab); chatEl.appendChild(turn);
  });
  chatEl.scrollTop = chatEl.scrollHeight;
}

// ---------- messages ----------
window.addEventListener('message', ev => {
  const m = ev.data; const id = m.runId;
  if (m.type === 'status') {
    statusOk = m.ok;
    // The host sends a key + one argument; the sentence is assembled here so it can be translated.
    statusMsg = m.key === 'cli-ready' ? t('Claude Code ready') + ' (' + (m.arg || '') + ')'
      : m.key === 'cli-missing' ? t('Claude Code CLI not found') + ' ("' + (m.arg || '') + '"). ' + t('Install it and sign in, or set cwkUi.claudePath.')
      : (m.msg || statusMsg);
    if (cur.view === 'home') renderHome();
    return;
  }
  if (m.type === 'spend') { spend = m; if (cur.view === 'home') renderHome(); return; }
  if (m.type === 'config') { if (m.defaultModel !== undefined) defaultModel = m.defaultModel; if (m.mode) uiMode = m.mode; if (m.language) { LANG = m.language; if (LANG === 'vi') statusMsg = t(statusMsg); } if (cur.view === 'home') renderHome(); return; }
  if (m.type === 'history') { history = m.items || []; if (cur.view === 'home') renderHome(); return; }
  if (m.type === 'restore') { // rebuild live runs (incl. logs) after a webview recreation — background runs are NOT lost
    (m.runs || []).forEach(s => { const ex = runs[s.runId] || {}; runs[s.runId] = { cmd: s.command || ex.cmd || '', title: s.title || ex.title || s.runId, values: ex.values || {}, status: s.status || 'done', log: s.log || ex.log || '', result: s.result || ex.result || '', sessionId: s.sessionId || ex.sessionId || null, report: s.report || ex.report || null, cost: s.cost != null ? s.cost : ex.cost, usage: s.usage || ex.usage, vnd: s.vnd != null ? s.vnd : ex.vnd, files: s.files || ex.files || [], steps: s.steps || ex.steps || [], model: s.model != null ? s.model : ex.model }; });
    if (cur.view === 'home') renderHome(); return;
  }
  if (!id || !runs[id]) { if (id && m.type !== 'status') runs[id] = { cmd: '', title: id, values: {}, status: 'running', log: '', result: '', sessionId: null, report: null, files: [], steps: [] }; }
  const r = runs[id]; if (!r) return;
  if (m.type === 'running') { r.status = 'running'; if (m.model !== undefined) r.model = m.model; }
  else if (m.type === 'log') { r.log += m.text + '\n'; r._lastLog = m.text; if (cur.runId === id) { if (logEl) { logEl.textContent = r.log; logEl.scrollTop = logEl.scrollHeight; } if (thinkingEl) thinkingEl.textContent = m.text; } }
  else if (m.type === 'session') { r.sessionId = m.sessionId; }
  else if (m.type === 'file') { r.files = r.files || []; const i = r.files.findIndex(f => f.path === m.entry.path); if (i >= 0) r.files[i] = m.entry; else r.files.push(m.entry); if (cur.runId === id) renderAux(r); }
  else if (m.type === 'steps') { r.steps = m.steps || []; if (cur.runId === id) renderAux(r); }
  else if (m.type === 'result') { r.result = m.text; const t = lastRunningTurn(r); if (t) { t.a = m.text; t.status = 'done'; } else { r.turns = r.turns || []; r.turns.push({ q: r.__q || '', a: m.text, status: 'done' }); } if (cur.runId === id) renderChat(r); }
  else if (m.type === 'usage') { r.cost = m.totalCost; r.usage = m.totalUsage; r.vnd = m.vnd; if (cur.runId === id && costEl) costEl.textContent = costText(r); }
  else if (m.type === 'done') {
    r.status = m.code === 0 ? 'done' : (m.code === 130 ? 'cancelled' : 'error'); if (m.report) r.report = m.report;
    const t = lastRunningTurn(r); if (t) { t.status = r.status; if (!t.a && r.status !== 'done') t.a = '_(ended without an answer — open **Activity** for details)_'; }
    if (cur.runId === id) {
      if (doneEl) { doneEl.className = 'runstate ' + (m.code === 0 ? 'ok' : 'bad'); doneEl.textContent = '● ' + r.status; }
      if (cancelBtn) cancelBtn.style.display = 'none';
      renderChat(r); showView('result');
      if (costEl) costEl.textContent = costText(r);
      renderAux(r);
      if (r.report) addReportBtn(r.report);
      if (followRow) { const s = followRow.querySelector('button'); if (s) s.disabled = false; }
    }
  }
});

// re-render the current view when crossing the narrow/wide breakpoint
let lastWide = WIDE();
window.addEventListener('resize', () => {
  const w = WIDE(); if (w === lastWide) return; lastWide = w;
  if (cur.view === 'run' && cur.runId) openRun(cur.runId);
  else if (cur.view === 'form' && cur.a) renderForm(cur.a, cur.values);
  else renderHome();
});

vscode.postMessage({ type: 'check' });
renderHome();
