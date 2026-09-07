#!/usr/bin/env node
/**
 * shadow-parity.cjs — parity oracle for cwk-rails-to-spring.
 *
 * Sends the SAME requests to the SOURCE (e.g. Rails) and the TARGET (e.g. Spring Boot),
 * canonicalizes both responses, diffs them, and exits non-zero if any case diverges.
 * Use it as the per-endpoint parity gate and in CI. Node >= 18 (built-in fetch); no dependencies.
 *
 * Usage:
 *   node shadow-parity.cjs cases.json \
 *     --source http://localhost:3000 --target http://localhost:8080 \
 *     [--graphql-path /graphql] [--source-token "$RAILS_TOKEN"] [--target-token "$SPRING_TOKEN"] \
 *     [--max-diff 20] [--json report.json]
 *   (SOURCE_URL / TARGET_URL env vars also work.)
 *   Tokens: prefer SOURCE_TOKEN / TARGET_TOKEN env vars over the --*-token flags for secrets
 *   (argv is visible in ps / shell history / CI logs); env vars win over the flags.
 *
 * cases.json (see cases.example.json):
 *   {
 *     "graphqlPath": "/graphql",
 *     "headers": { "both": {...}, "source": {...}, "target": {...} },   // e.g. auth per side
 *     "ignore": ["**.id", "**.createdAt", "**.updatedAt"],              // redacted before diff
 *     "sortArraysAt": ["data.coaches"],                                 // sort these arrays (order-insensitive)
 *     "cases": [
 *       { "name": "coach by id", "type": "graphql",
 *         "graphql": { "query": "query($id:ID!){ coach(id:$id){ id name metrics } }", "variables": {"id":"1"} },
 *         "ignore": ["data.coach.updatedAt"], "expectStatus": 200 },
 *       { "name": "list tasks", "type": "rest",
 *         "rest": { "method": "GET", "path": "/api/tasks" } }
 *     ]
 *   }
 *
 * Path patterns for `ignore` / `sortArraysAt`: dot-separated; `*` = one segment (incl. array elements),
 * `**` = any number of segments. Examples: `data.coaches.*.updatedAt`, `**.id`, `errors.*.message`.
 */
'use strict';

// ---------- args ----------
const argv = process.argv.slice(2);
const positional = [];
const opt = {};
for (let i = 0; i < argv.length; i++) {
  const a = argv[i];
  if (a.startsWith('--')) opt[a.slice(2)] = (argv[i + 1] && !argv[i + 1].startsWith('--')) ? argv[++i] : true;
  else positional.push(a);
}
const casesPath = positional[0];
if (!casesPath) { console.error('usage: node shadow-parity.cjs cases.json --source <url> --target <url> [--graphql-path /graphql]'); process.exit(2); }

const SOURCE = String(opt.source || process.env.SOURCE_URL || '').replace(/\/+$/, '');
const TARGET = String(opt.target || process.env.TARGET_URL || '').replace(/\/+$/, '');
const isHttpUrl = (u) => /^https?:\/\//i.test(u);
if (!isHttpUrl(SOURCE) || !isHttpUrl(TARGET)) { console.error('error: --source and --target (or SOURCE_URL / TARGET_URL) must be http(s) URLs.'); process.exit(2); }
const MAX_DIFF = parseInt(opt['max-diff'] || '20', 10);
if (!Number.isFinite(MAX_DIFF) || MAX_DIFF < 1) { console.error('error: --max-diff must be a number >= 1.'); process.exit(2); }

const fs = require('fs');
let cfg;
try { cfg = JSON.parse(fs.readFileSync(casesPath, 'utf8')); }
catch (e) { console.error(`error: cannot read ${casesPath}: ${e.message}`); process.exit(2); }
if (Array.isArray(cfg)) cfg = { cases: cfg };
const GQL_PATH = String(opt['graphql-path'] || cfg.graphqlPath || '/graphql');
const cases = cfg.cases || [];
if (!cases.length) { console.error('error: no cases in the file.'); process.exit(2); }

// ---------- path pattern matching ----------
function matchPath(patSegs, segs) {
  const go = (pi, si) => {
    if (pi === patSegs.length) return si === segs.length;
    if (patSegs[pi] === '**') { for (let k = si; k <= segs.length; k++) if (go(pi + 1, k)) return true; return false; }
    if (si >= segs.length) return false;
    if (patSegs[pi] === '*' || patSegs[pi] === segs[si]) return go(pi + 1, si + 1);
    return false;
  };
  return go(0, 0);
}
function matchesAny(patterns, path) {
  const segs = path.split('.');
  return patterns.some(p => matchPath(p.split('.'), segs));
}
const stable = (x) => JSON.stringify(x);

// ---------- canonicalize: sort keys, redact ignored paths, optionally sort arrays ----------
function canonicalize(value, ignore, sortArrays, path = '') {
  if (Array.isArray(value)) {
    let arr = value.map(v => canonicalize(v, ignore, sortArrays, path ? path + '.*' : '*'));
    if (path && matchesAny(sortArrays, path)) arr = [...arr].sort((a, b) => stable(a).localeCompare(stable(b)));
    return arr;
  }
  if (value && typeof value === 'object') {
    const out = {};
    for (const k of Object.keys(value).sort()) {
      const child = path ? path + '.' + k : k;
      out[k] = matchesAny(ignore, child) ? '<redacted>' : canonicalize(value[k], ignore, sortArrays, child);
    }
    return out;
  }
  return value;
}

// ---------- diff two canonical values ----------
function diff(a, b, path, out) {
  if (out.length >= MAX_DIFF) return;
  if (stable(a) === stable(b)) return;
  const bothObj = a && b && typeof a === 'object' && typeof b === 'object' && Array.isArray(a) === Array.isArray(b);
  if (bothObj && Array.isArray(a)) {
    if (a.length !== b.length) out.push({ path: `${path}.length`, source: a.length, target: b.length });
    for (let i = 0; i < Math.max(a.length, b.length) && out.length < MAX_DIFF; i++) diff(a[i], b[i], `${path}[${i}]`, out);
  } else if (bothObj) {
    for (const k of new Set([...Object.keys(a), ...Object.keys(b)])) { if (out.length >= MAX_DIFF) break; diff(a[k], b[k], path ? `${path}.${k}` : k, out); }
  } else {
    out.push({ path: path || '(root)', source: a, target: b });
  }
}

// ---------- one request ----------
async function call(base, c, side, headers) {
  const h = Object.assign({}, headers.both || {}, headers[side] || {});
  const token = side === 'source' ? (process.env.SOURCE_TOKEN || opt['source-token']) : (process.env.TARGET_TOKEN || opt['target-token']);
  if (token && typeof token === 'string' && !h.Authorization) h.Authorization = `Bearer ${token}`;
  let url, init;
  if (c.type === 'rest') {
    url = base + (c.rest.path || '/');
    init = { method: c.rest.method || 'GET', headers: h };
    if (c.rest.body != null) { init.headers = Object.assign({ 'content-type': 'application/json' }, h); init.body = typeof c.rest.body === 'string' ? c.rest.body : JSON.stringify(c.rest.body); }
  } else {
    url = base + GQL_PATH;
    init = { method: 'POST', headers: Object.assign({ 'content-type': 'application/json' }, h),
      body: JSON.stringify({ query: c.graphql.query, variables: c.graphql.variables || {}, operationName: c.graphql.operationName || null }) };
  }
  try {
    const res = await fetch(url, init);
    const text = await res.text();
    let body; try { body = JSON.parse(text); } catch { body = text; }
    return { status: res.status, body };
  } catch (e) { return { error: String(e.message || e) }; }
}

// ---------- run ----------
const trunc = (v) => { const s = typeof v === 'string' ? v : JSON.stringify(v); return s == null ? String(s) : (s.length > 160 ? s.slice(0, 160) + '…' : s); };

(async () => {
  const globalIgnore = cfg.ignore || [];
  const globalSort = cfg.sortArraysAt || [];
  const headers = cfg.headers || {};
  const report = [];
  let pass = 0, fail = 0;

  for (const c of cases) {
    const name = c.name || (c.type === 'rest' ? `${c.rest.method} ${c.rest.path}` : 'graphql');
    const [s, t] = await Promise.all([call(SOURCE, c, 'source', headers), call(TARGET, c, 'target', headers)]);
    const ignore = globalIgnore.concat(c.ignore || []);
    const sortArrays = globalSort.concat(c.sortArraysAt || []);
    let ok = true; const reasons = []; const diffs = [];

    if (s.error || t.error) { ok = false; reasons.push(`request error — source: ${s.error || 'ok'} · target: ${t.error || 'ok'}`); }
    else {
      if (!c.ignoreStatus && s.status !== t.status) { ok = false; reasons.push(`status ${s.status} vs ${t.status}`); }
      if (c.expectStatus != null && s.status !== c.expectStatus) { ok = false; reasons.push(`source status ${s.status} != expectStatus ${c.expectStatus}`); }
      const cs = canonicalize(s.body, ignore, sortArrays);
      const ct = canonicalize(t.body, ignore, sortArrays);
      diff(cs, ct, '', diffs);
      if (diffs.length) { ok = false; reasons.push(`${diffs.length}${diffs.length >= MAX_DIFF ? '+' : ''} field diff(s)`); }
    }

    if (ok) { pass++; console.log(`  PASS  ${name}`); }
    else {
      fail++;
      console.log(`  FAIL  ${name}`);
      for (const r of reasons) console.log(`          - ${r}`);
      for (const d of diffs.slice(0, 8)) console.log(`          Δ ${d.path}:  source=${trunc(d.source)}  target=${trunc(d.target)}`);
    }
    report.push({ name, ok, reasons, diffs });
  }

  console.log(`\n${pass}/${cases.length} passed · ${fail} failed  (source=${SOURCE} target=${TARGET})`);
  if (typeof opt.json === 'string') { try { fs.writeFileSync(opt.json, JSON.stringify({ pass, fail, report }, null, 2)); console.log(`report → ${opt.json}`); } catch (e) { console.error(`could not write ${opt.json}: ${e.message}`); } }
  process.exit(fail ? 1 : 0);
})();
