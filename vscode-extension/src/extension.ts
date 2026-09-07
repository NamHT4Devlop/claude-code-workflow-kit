import * as vscode from 'vscode';
import { spawn, ChildProcess, execFile } from 'child_process';

// Every cwk-* skill is exposed in the UI. The webview may request nothing
// else — the host rejects any command not on this list.
const ALLOWED = new Set([
  'cwk-scan', 'cwk-rescan', 'cwk-ask', 'cwk-map', 'cwk-system-map', 'cwk-document',
  'cwk-discover', 'cwk-plan', 'cwk-plan-review', 'cwk-user-story',
  'cwk-build', 'cwk-fix-bug', 'cwk-migrate', 'cwk-simplify', 'cwk-perf', 'cwk-observe', 'cwk-rails-to-spring',
  'cwk-review', 'cwk-qa', 'cwk-qa-integration', 'cwk-security-audit', 'cwk-design-review', 'cwk-pr', 'cwk-drift',
  'cwk-splunk-report', 'cwk-retro', 'cwk-pdf', 'cwk-skillify', 'cwk-issues', 'cwk-runbook',
]);
// The seven skills that modify source. In readonly mode the host refuses them outright, so hiding
// the cards is a UI convenience rather than the actual control.
const EDITS_CODE = new Set([
  'cwk-build', 'cwk-fix-bug', 'cwk-migrate', 'cwk-simplify', 'cwk-perf', 'cwk-observe',
  'cwk-rails-to-spring',
]);
// The models the UI offers. Anything the webview sends is checked against this before it reaches a
// command line — an unvalidated value would be the only unquoted token in a shell-executed string.
const MODELS = new Set(['', 'haiku', 'sonnet', 'opus']);
const HIST_KEY = 'cwkUi.history';
const HIST_MAX = 40;
// Spend is per machine, not per workspace — globalState, one bucket per day, pruned to SPEND_DAYS.
const SPEND_KEY = 'cwkUi.spend';
const SPEND_DAYS = 60;

export function activate(context: vscode.ExtensionContext) {
  const provider = new SpecKitViewProvider(context);
  context.subscriptions.push(
    vscode.window.registerWebviewViewProvider('cwk.view', provider, {
      webviewOptions: { retainContextWhenHidden: true },
    }),
    vscode.commands.registerCommand('cwk.openApp', () => provider.openApp())
  );
}
export function deactivate() {}

class SpecKitViewProvider implements vscode.WebviewViewProvider {
  private webviews = new Set<vscode.Webview>();       // sidebar view + any app panels — kept in sync
  private procs = new Map<string, ChildProcess>();   // runId → process
  private sessions = new Map<string, string>();       // runId → claude session_id
  private state = new Map<string, any>();             // runId → live state (log/result/status) — survives webview recreation

  constructor(private readonly ctx: vscode.ExtensionContext) {}

  resolveWebviewView(view: vscode.WebviewView) { this.wire(view.webview); }

  // Open the full app experience in the editor area (wide two-pane layout).
  openApp() {
    const panel = vscode.window.createWebviewPanel(
      'cwkApp', 'Workflow Kit', vscode.ViewColumn.Active,
      { enableScripts: true, retainContextWhenHidden: true, localResourceRoots: [vscode.Uri.joinPath(this.ctx.extensionUri, 'media')] }
    );
    panel.iconPath = vscode.Uri.joinPath(this.ctx.extensionUri, 'media', 'icon.svg');
    this.wire(panel.webview);
    panel.onDidDispose(() => this.webviews.delete(panel.webview));
  }

  private wire(webview: vscode.Webview) {
    webview.options = { enableScripts: true, localResourceRoots: [vscode.Uri.joinPath(this.ctx.extensionUri, 'media')] };
    webview.html = this.getHtml(webview);
    webview.onDidReceiveMessage((m: any) => this.handleMessage(m));
    this.webviews.add(webview);
  }

  private handleMessage(m: any) {
    switch (m?.type) {
      case 'check': this.checkClaude(); this.post({ type: 'config', defaultModel: this.cfg().model, mode: this.cfg().mode, language: this.cfg().language }); this.post({ type: 'history', items: this.history() }); this.post({ type: 'restore', runs: Array.from(this.state.values()) }); this.postSpend(); break;
      case 'run': this.start(m); break;
      case 'followup': this.followup(String(m.runId), String(m.text || ''), String(m.sessionId || ''), m.model); break;
      case 'cancel': this.cancel(String(m.runId)); break;
      case 'openReport': this.openReport(String(m.path || '')); break;
      case 'interactive': this.interactive(m); break;
      case 'open': this.openFile(String(m.path || '')); break;
      case 'clearHistory': this.ctx.workspaceState.update(HIST_KEY, []); this.post({ type: 'history', items: [] }); break;
    }
  }

  private post(m: unknown) { for (const w of this.webviews) w.postMessage(m); }
  private cfg() {
    const c = vscode.workspace.getConfiguration('cwkUi');
    return { claudePath: c.get<string>('claudePath', 'claude'), extraArgs: c.get<string[]>('extraArgs', ['--permission-mode', 'bypassPermissions']), usdToVnd: c.get<number>('usdToVnd', 26000), model: c.get<string>('model', 'sonnet'),
      mode: c.get<string>('mode', 'full'), language: c.get<string>('language', 'en') };
  }
  private cwd(): string | undefined { return vscode.workspace.workspaceFolders?.[0]?.uri.fsPath; }

  private checkClaude() {
    const { claudePath } = this.cfg();
    execFile(claudePath, ['--version'], (err, stdout) => {
      // Send a KEY, not a finished sentence: a status born here used to arrive as English and
      // overwrite whatever the webview had translated — so the Vietnamese panel always showed its
      // setup instructions in English, to exactly the non-technical reader who needs them least.
      this.post(err
        ? { type: 'status', ok: false, key: 'cli-missing', arg: claudePath }
        : { type: 'status', ok: true, key: 'cli-ready', arg: String(stdout).trim() });
    });
  }

  // A form field can hold a secret (the Slack webhook of cwk-splunk-report). History is written to
  // VS Code workspace storage in plaintext, so strip anything URL-shaped before persisting it.
  private static readonly SECRET_RE = /(https?:\/\/\S+|xox[abposr]-[A-Za-z0-9-]+|gh[pousr]_[A-Za-z0-9]{16,}|eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+)/gi;
  private scrubValues(values: any): any {
    if (!values || typeof values !== 'object') return values;
    const out: any = {};
    for (const [k, v] of Object.entries(values)) {
      out[k] = (typeof v === 'string' && SpecKitViewProvider.SECRET_RE.test(v)) ? '<redacted — not stored>' : v;
      SpecKitViewProvider.SECRET_RE.lastIndex = 0;   // /g regexes are stateful across .test() calls
    }
    return out;
  }
  // Redacting only the `values` map was not enough: the same secret is inside the prompt we echo
  // into the run log, and follow-up text was never scrubbed at all — and the log is persisted to
  // workspace storage in plaintext. Scrub anything secret-shaped on the way into the log.
  private scrubText(t: string): string {
    const out = String(t).replace(SpecKitViewProvider.SECRET_RE, '<redacted>');
    SpecKitViewProvider.SECRET_RE.lastIndex = 0;
    return out;
  }

  // ---- spend (per day, machine-wide) ----
  // Answers "what has this panel cost me?" — a per-run chip alone never adds up to a number the
  // user can act on. Local dates, so "today" means the user's today, not UTC.
  private sessionSpend = { usd: 0, runs: 0 };
  private static dayKey(d = new Date()) {
    return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`;
  }
  private spendMap(): Record<string, { usd: number; runs: number }> {
    return this.ctx.globalState.get<Record<string, { usd: number; runs: number }>>(SPEND_KEY, {});
  }
  private addSpend(usd: number) {
    if (!(usd > 0)) return;                       // a 0-cost result must not inflate the run count
    const map = this.spendMap();
    const k = SpecKitViewProvider.dayKey();
    const cur = map[k] || { usd: 0, runs: 0 };
    map[k] = { usd: cur.usd + usd, runs: cur.runs + 1 };
    for (const key of Object.keys(map)) {         // prune old days so globalState can't grow forever
      const age = (Date.now() - new Date(key + 'T00:00:00').getTime()) / 86400000;
      if (!isFinite(age) || age > SPEND_DAYS) delete map[key];
    }
    this.ctx.globalState.update(SPEND_KEY, map);
    this.sessionSpend = { usd: this.sessionSpend.usd + usd, runs: this.sessionSpend.runs + 1 };
    this.postSpend();
  }
  private postSpend() {
    const map = this.spendMap();
    const today = map[SpecKitViewProvider.dayKey()] || { usd: 0, runs: 0 };
    let week = { usd: 0, runs: 0 };
    for (let i = 0; i < 7; i++) {
      const d = new Date(); d.setDate(d.getDate() - i);
      const b = map[SpecKitViewProvider.dayKey(d)];
      if (b) { week.usd += b.usd; week.runs += b.runs; }
    }
    const rate = this.cfg().usdToVnd || 0;
    this.post({ type: 'spend', session: this.sessionSpend, today, week, rate });
  }

  // ---- history (persisted per workspace so it survives reloads) ----
  private history(): any[] { return this.ctx.workspaceState.get<any[]>(HIST_KEY, []); }
  private histUpsert(item: any) {
    const h = this.history().filter(x => x.runId !== item.runId);
    h.unshift(item);
    this.ctx.workspaceState.update(HIST_KEY, h.slice(0, HIST_MAX));
    this.post({ type: 'history', items: this.history() });
  }
  private histPatch(runId: string, patch: any) {
    const h = this.history(); const it = h.find(x => x.runId === runId);
    if (it) { Object.assign(it, patch); this.ctx.workspaceState.update(HIST_KEY, h); this.post({ type: 'history', items: h }); }
  }
  // state/sessions would otherwise grow forever — drop the oldest finished runs beyond HIST_MAX.
  private evict() {
    while (this.state.size > HIST_MAX) {
      let oldest: string | undefined, when = Infinity;
      for (const [id, s] of this.state) { if (s.status !== 'running' && (s.when || 0) < when) { when = s.when || 0; oldest = id; } }
      if (!oldest) break;
      this.state.delete(oldest); this.sessions.delete(oldest);
    }
  }

  // ---- runs ----
  // Read-only mode is enforced here and NOWHERE ELSE is allowed to skip it. Three paths reach the
  // CLI — start(), followup() and interactive() — and each must ask this question, because the CLI
  // runs with --permission-mode bypassPermissions by default: whatever the prompt asks for happens.
  private refusedByReadonly(command: string): string | undefined {
    if (this.cfg().mode !== 'readonly') return undefined;
    if (EDITS_CODE.has(command)) return `"${command}" changes code and this panel is in read-only mode`;
    // Free chat is a raw prompt with no skill, so nothing constrains what it asks the CLI to do —
    // "edit src/foo.ts" in the chat box is a code edit. It must not be reachable in read-only mode.
    if (command === '__chat') return 'free chat can ask for anything, including code edits — it is disabled in read-only mode';
    return undefined;
  }

  private start(m: any) {
    const runId = String(m.runId); const command = String(m.command || '');
    const isChat = command === '__chat';   // free chat: raw prompt, no skill, whitelist bypassed
    if (!isChat && !ALLOWED.has(command)) { this.post({ type: 'log', runId, text: `[blocked: "${command}" is not allowed]` }); this.post({ type: 'done', runId, code: 1 }); return; }
    const refusal = this.refusedByReadonly(command);
    if (refusal) {
      this.post({ type: 'log', runId, text: `[blocked: ${refusal}]` });
      this.post({ type: 'done', runId, code: 1 }); return;
    }
    const cwd = this.cwd() || (isChat ? require('os').homedir() : undefined);
    if (!cwd) { this.post({ type: 'log', runId, text: '[open a project folder first — skills read that project]' }); this.post({ type: 'done', runId, code: 1 }); return; }
    const prompt = isChat ? String(m.args || '').trim() : `/${command} ${String(m.args || '')}`.trim();
    if (isChat && !prompt) { this.post({ type: 'log', runId, text: '[type a question first]' }); this.post({ type: 'done', runId, code: 1 }); return; }
    const model = (m.model !== undefined && m.model !== null) ? String(m.model) : this.cfg().model;
    this.histUpsert({ runId, command, title: m.title || command, values: this.scrubValues(m.values || {}), when: Date.now(), status: 'running', model });
    this.state.set(runId, { runId, command, title: String(m.title || command), log: '', result: '', status: 'running', sessionId: null, report: null, when: Date.now(), model });
    this.evict();
    this.spawnClaude(runId, ['-p', prompt], cwd, `${isChat ? '💬' : '▶'} ${this.scrubText(prompt)}\n(cwd: ${cwd})\n\n`);
  }

  private followup(runId: string, text: string, sessionId?: string, model?: string) {
    if (!text.trim()) return;
    // A follow-up is an unconstrained prompt resumed into the same bypassPermissions session, so it
    // is the widest door in this panel. In read-only mode it stays shut: without this, "now edit
    // src/foo.ts" typed after an innocent /cwk-ask run edits the source, and the read-only .vsix
    // handed to a PM would be a promise the host does not keep.
    if (this.cfg().mode === 'readonly') {
      this.post({ type: 'log', runId, text: '\n[blocked: follow-ups can ask for anything, including code edits — this panel is in read-only mode]' });
      this.post({ type: 'done', runId, code: 1 });
      return;
    }
    const cwd = this.cwd(); if (!cwd) return;
    // A follow-up may pick a DIFFERENT model — the resumed session keeps its full context on disk,
    // so switching model mid-session still "knows" what it was doing.
    if (model !== undefined && model !== null) { const st = this.state.get(runId); if (st) st.model = String(model); }
    // Prefer the id passed from the webview (survives reload — Claude persists sessions on disk),
    // else the in-memory map, else continue the most recent session.
    const sid = (sessionId && sessionId.trim()) ? sessionId.trim() : this.sessions.get(runId);
    if (sid) this.sessions.set(runId, sid);
    const resume = sid ? ['--resume', sid] : ['--continue'];
    this.spawnClaude(runId, ['-p', text, ...resume], cwd, `\n\n────────\n💬 ${this.scrubText(text)}\n\n`);
  }

  private spawnClaude(runId: string, baseArgs: string[], cwd: string, header: string) {
    if (this.procs.has(runId)) { this.post({ type: 'log', runId, text: '[this run is still busy — wait for it or cancel]' }); return; }
    const { claudePath, extraArgs, model: cfgModel } = this.cfg();
    let st = this.state.get(runId);
    if (!st) { st = { runId, command: '', title: runId, log: '', result: '', status: 'running', sessionId: null, report: null, when: Date.now(), model: cfgModel }; this.state.set(runId, st); this.evict(); }
    const model = (st.model !== undefined && st.model !== null) ? st.model : cfgModel;
    const cliArgs = [...baseArgs, '--output-format', 'stream-json', '--verbose', ...(model ? ['--model', model] : []), ...extraArgs];
    st.status = 'running'; st.log += header;
    this.post({ type: 'running', runId, model });
    this.post({ type: 'log', runId, text: header });

    let seen = '', finalText = '', lineBuf = '';
    const emit = (t: string) => { seen += t + '\n'; st.log += t + '\n'; if (st.log.length > 330000) st.log = st.log.slice(-300000); this.post({ type: 'log', runId, text: t }); };
    const feed = (line: string) => { const r = this.handleLine(runId, line, emit); if (r !== undefined) finalText = r; };

    let proc: ChildProcess;
    try { proc = spawn(claudePath, cliArgs, { cwd, stdio: ['ignore', 'pipe', 'pipe'] }); }
    catch (e) { st.status = 'error'; this.post({ type: 'log', runId, text: `[failed to start Claude: ${String(e)}]` }); this.post({ type: 'done', runId, code: 1 }); return; }
    this.procs.set(runId, proc);

    proc.stdout?.on('data', (d: Buffer) => {
      lineBuf += d.toString(); let nl: number;
      while ((nl = lineBuf.indexOf('\n')) >= 0) { const l = lineBuf.slice(0, nl); lineBuf = lineBuf.slice(nl + 1); feed(l); }
    });
    proc.stderr?.on('data', (d: Buffer) => this.post({ type: 'log', runId, text: d.toString() }));
    proc.on('error', (e) => this.post({ type: 'log', runId, text: `[error: ${e.message}]` }));
    proc.on('close', (code) => {
      if (lineBuf.trim()) feed(lineBuf);
      this.procs.delete(runId);
      const cancelled = st.status === 'cancelled';   // set by cancel() — the killed child's exit code (null/143) must not turn it into 'error'
      st.status = cancelled ? 'cancelled' : (code === 0 ? 'done' : (code === 130 ? 'cancelled' : 'error'));
      st.sessionId = this.sessions.get(runId) || st.sessionId;
      if (finalText) { st.result = finalText; this.post({ type: 'result', runId, text: finalText }); }
      const report = this.findReport(seen, finalText, cwd); st.report = report;
      this.post({ type: 'done', runId, code: cancelled ? 130 : (code ?? 1), report });
      this.histPatch(runId, { status: st.status, result: finalText.slice(0, 24000), report, cost: st.cost || 0, tokens: st.usage, log: (st.log || '').slice(-40000) });
    });
  }

  private handleLine(runId: string, line: string, emit: (t: string) => void): string | undefined {
    const s = line.trim(); if (!s) return undefined;
    let ev: any; try { ev = JSON.parse(s); } catch { emit(s); return undefined; }
    if (ev.type === 'system' && ev.subtype === 'init') {
      if (ev.session_id) { this.sessions.set(runId, ev.session_id); const st = this.state.get(runId); if (st) st.sessionId = ev.session_id; this.histPatch(runId, { sessionId: ev.session_id }); this.post({ type: 'session', runId, sessionId: ev.session_id }); }
      emit(`▸ session started · model ${ev.model || '?'} · ${(ev.tools?.length || 0)} tools available`); return undefined;
    }
    if (ev.type === 'assistant' && ev.message?.content) {
      for (const c of ev.message.content) {
        if (c.type === 'text' && c.text?.trim()) { emit(c.text.trim()); this.trackSteps(runId, c.text); }
        else if (c.type === 'tool_use') { emit(`🔧 ${c.name}${this.shortInput(c.input)}`); this.trackFile(runId, c.name, c.input); }
      }
      return undefined;
    }
    if (ev.type === 'user' && ev.message?.content) {
      for (const c of ev.message.content) if (c.type === 'tool_result') emit(`   ↳ ${c.is_error ? 'error' : 'ok'}${this.resultLen(c.content)}`);
      return undefined;
    }
    if (ev.type === 'result') {
      const u = ev.usage || {};
      const usage = { input: u.input_tokens || 0, output: u.output_tokens || 0, cacheCreate: u.cache_creation_input_tokens || 0, cacheRead: u.cache_read_input_tokens || 0 };
      const cost = typeof ev.total_cost_usd === 'number' ? ev.total_cost_usd : 0;
      const st = this.state.get(runId);
      if (st) {
        st.usage = st.usage || { input: 0, output: 0, cacheCreate: 0, cacheRead: 0 };
        st.usage.input += usage.input; st.usage.output += usage.output; st.usage.cacheCreate += usage.cacheCreate; st.usage.cacheRead += usage.cacheRead;
        st.cost = (st.cost || 0) + cost;
      }
      const totalCost = st ? st.cost : cost;
      const rate = this.cfg().usdToVnd || 0;
      const vnd = rate ? Math.round(totalCost * rate) : 0;
      if (st) st.vnd = vnd;
      this.post({ type: 'usage', runId, cost, usage, totalCost, totalUsage: st?.usage || usage, vnd });
      this.addSpend(cost);
      return typeof ev.result === 'string' ? ev.result : undefined;
    }
    return undefined;
  }

  private shortInput(input: any): string {
    if (!input || typeof input !== 'object') return '';
    const pick = input.file_path || input.command || input.pattern || input.description || input.path || input.query || input.url || input.prompt;
    if (!pick) return '';
    const t = String(pick).replace(/\s+/g, ' ').trim();
    return `  ${t.length > 90 ? t.slice(0, 90) + '…' : t}`;
  }
  private resultLen(content: any): string {
    try { const s = typeof content === 'string' ? content : JSON.stringify(content); return s.length ? ` (${s.length} chars)` : ''; } catch { return ''; }
  }

  // ---- live-run insight: which files are being edited + which step the pipeline reached ----
  private trackFile(runId: string, name: string, input: any) {
    if (!input || typeof input !== 'object') return;
    if (!['Edit', 'MultiEdit', 'Write', 'NotebookEdit'].includes(name)) return;
    const path = input.file_path || input.notebook_path; if (!path) return;
    const st = this.state.get(runId); if (!st) return;
    st.files = st.files || [];
    let e = st.files.find((f: any) => f.path === path);
    if (!e) { e = { path, tool: name, edits: [], count: 0 }; st.files.push(e); }
    const clip = (v: any) => { const s = String(v ?? ''); return s.length > 1200 ? s.slice(0, 1200) + '\n… (truncated)' : s; };
    const add = (o: any, n: any) => { e.edits.push({ old: clip(o), new: clip(n) }); e.count++; };
    if (name === 'Edit') add(input.old_string, input.new_string);
    else if (name === 'MultiEdit' && Array.isArray(input.edits)) input.edits.forEach((x: any) => add(x.old_string, x.new_string));
    else if (name === 'Write') { e.tool = 'Write'; add('', input.content); }
    else if (name === 'NotebookEdit') add('', input.new_source);
    if (e.edits.length > 40) e.edits = e.edits.slice(-40);
    this.post({ type: 'file', runId, entry: e });
  }

  private trackSteps(runId: string, text: string) {
    const st = this.state.get(runId); if (!st) return;
    st.steps = st.steps || [];
    const re = /(?:^|\n)\s*#{0,4}\s*Step\s+(\d+)\b[ \t]*(?:[—:\-–][ \t]*(.+))?/gi;
    let m: RegExpExecArray | null, changed = false;
    while ((m = re.exec(text))) {
      const n = parseInt(m[1], 10); if (isNaN(n)) continue;
      const label = (m[2] || '').split('\n')[0].replace(/[*#`]/g, '').trim().slice(0, 44);
      const ex = st.steps.find((s: any) => s.n === n);
      if (ex) { if (label && !ex.label) { ex.label = label; changed = true; } }
      else { st.steps.push({ n, label }); changed = true; }
    }
    if (changed) { st.steps.sort((a: any, b: any) => a.n - b.n); this.post({ type: 'steps', runId, steps: st.steps }); }
  }

  // ---- interactive handoff: run the same skill in a terminal so a dev reviews each diff / approves-rejects ----
  private interactive(m: any) {
    const command = String(m.command || ''); if (!ALLOWED.has(command)) return;
    const refusal = this.refusedByReadonly(command);
    if (refusal) { vscode.window.showWarningMessage(`Read-only mode: ${refusal}`); return; }
    const cwd = this.cwd(); if (!cwd) { vscode.window.showWarningMessage('Open a project folder first — skills read that project.'); return; }
    const { claudePath, model: cfgModel } = this.cfg();
    const model = MODELS.has(String(m.model)) ? String(m.model) : (MODELS.has(cfgModel) ? cfgModel : '');
    const prompt = `/${command} ${String(m.args || '')}`.replace(/\s*\n\s*/g, ' ').trim();
    const q = (s: string) => `'` + s.replace(/'/g, `'\\''`) + `'`;
    // `model` is the one token spliced into a line that a SHELL executes (sendText below), so it is
    // allowlisted above AND quoted here — the other two tokens were already quoted.
    const line = `${q(claudePath)}${model ? ' --model ' + q(model) : ''} ${q(prompt)}`;
    const term = vscode.window.createTerminal({ cwd, name: `Claude ⚡ ${String(m.title || command)}` });
    term.show(true);
    term.sendText(line, true);
  }

  // The webview may name a path, but the host decides whether it is allowed to open it. Without
  // this, a crafted postMessage opens any file on disk — and openReport hands .html straight to the
  // system browser. Everything this panel legitimately opens lives under the workspace.
  private insideWorkspace(abs: string): boolean {
    const cwd = this.cwd(); if (!cwd) return false;
    const path = require('path');
    const rel = path.relative(path.resolve(cwd), path.resolve(abs));
    return rel === '' || (!rel.startsWith('..') && !path.isAbsolute(rel));
  }
  private resolveInWorkspace(p: string): string | undefined {
    if (!p) return undefined;
    const path = require('path');
    if (p.startsWith('~')) p = require('os').homedir() + p.slice(1);
    const cwd = this.cwd();
    const abs = path.isAbsolute(p) ? p : (cwd ? path.resolve(cwd, p) : undefined);
    if (!abs || !this.insideWorkspace(abs)) {
      vscode.window.showWarningMessage(`Refused to open a path outside this workspace: ${p}`);
      return undefined;
    }
    return abs;
  }

  private openFile(p: string) {
    const abs = this.resolveInWorkspace(p); if (!abs) return;
    vscode.window.showTextDocument(vscode.Uri.file(abs), { preview: true })
      .then(undefined, (err) => vscode.window.showWarningMessage(`Cannot open ${abs}: ${err}`));
  }

  private cancel(runId: string) {
    const p = this.procs.get(runId);
    if (!p) return;
    // Mark it and let the process's own 'close' handler post the single terminal event. Posting
    // `done` here (and deleting from procs) used to fire a SECOND done when the child actually
    // exited, and re-opened the busy-guard in between — so a follow-up sent the moment the UI
    // re-enabled could spawn a new process for the same runId, which the dying one then clobbered.
    const st = this.state.get(runId); if (st) st.status = 'cancelled';
    this.post({ type: 'log', runId, text: '\n[cancelling…]' });
    p.kill('SIGTERM');
  }

  private findReport(out: string, finalText: string, cwd: string): string | undefined {
    // Prefer the final answer (the report the skill actually points at), else the LAST
    // path mentioned in the log — early matches are intermediate artifacts.
    // Accept the pre-rename `spec-kit-sessions/` too — old reports must still open.
    const re = /[\w./~-]*(?:cwk|namht|spec-kit)-sessions[\w./-]+\.(?:html|md)/g;
    const last = (s: string) => { const all = s.match(re); return all ? all[all.length - 1] : undefined; };
    let p = last(finalText) || last(out + '\n' + finalText);
    if (!p) return undefined;
    if (p.startsWith('~')) p = require('os').homedir() + p.slice(1);
    if (!p.startsWith('/')) p = require('path').resolve(cwd, p);
    return p;
  }
  private openReport(p: string) {
    const abs = this.resolveInWorkspace(p); if (!abs) return;
    const uri = vscode.Uri.file(abs);
    if (abs.endsWith('.html')) vscode.env.openExternal(uri); else vscode.commands.executeCommand('markdown.showPreview', uri);
  }

  private getHtml(webview: vscode.Webview): string {
    const uri = (f: string) => webview.asWebviewUri(vscode.Uri.joinPath(this.ctx.extensionUri, 'media', f));
    const nonce = String(Date.now()) + Math.random().toString(36).slice(2);
    const csp = `default-src 'none'; style-src ${webview.cspSource}; script-src 'nonce-${nonce}';`;
    return `<!DOCTYPE html><html lang="en"><head>
<meta charset="UTF-8"><meta http-equiv="Content-Security-Policy" content="${csp}">
<link href="${uri('main.css')}" rel="stylesheet"></head><body>
<div id="app"></div><script nonce="${nonce}" src="${uri('i18n.js')}"></script><script nonce="${nonce}" src="${uri('main.js')}"></script></body></html>`;
  }
}
