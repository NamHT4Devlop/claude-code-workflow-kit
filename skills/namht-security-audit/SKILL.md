---
name: namht-security-audit
description: >-
  Run a whole-repo security audit: sweep the codebase for vulnerabilities by
  category (input validation, injection, broken authn/authz & IDOR, secrets &
  crypto, sensitive-data exposure, dependency risk, and AI/LLM-specific issues),
  grounded in the project's review-skills checklist + auth model (KB) + the code
  (entry points = attack surface, blast radius). Use when the user says
  "/security-audit", "security review of the repo", "find vulnerabilities",
  "OWASP audit", "is this secure", or before a release/pentest. Read-only.
---

# namht-security-audit — whole-repo security sweep

A repo-wide security audit (broader than `/namht-review`, which is per-file). It enumerates the
**attack surface**, checks it against a security checklist, and reports prioritized findings with
fixes. Read-only — it does NOT change code (hand fixes to `/namht-fix-bug` or `/namht-build`).

## Inputs & grounding
- **Checklist:** `knowledge-base/review-skills.md` §2 SECURITY + §8 AI/LLM (fallback bundled
  `references/review-skills-universal.md`). Plus project rules (Section 14) if present.
- **Attack surface (KB + code):** find every external entry point — HTTP/gRPC routes,
  message consumers, scheduled jobs, CLI, file/upload handlers, auth flows — via KB
  `03-entry-points.md` / `09-auth-security.md` / `11-api-docs.md` and by reading the
  controllers/handlers. These are where untrusted input enters.
- If no KB, fall back to Grep/Glob (note reduced coverage).

### codelens (optional)
`.codelens/` present → prefer `codelens` over grep for anything about **who calls what**: it resolves
through DI, interfaces, mixins and framework string-bindings (MyBatis · Camel · SQS · Flyway) and
scores every edge. Confirm it with `codelens status`, and run `codelens sync` first if the working
tree has moved since it was built — **a stale index is worse than none, because it looks
authoritative**. If coverage reads low, `codelens doctor` says whether that is a resolver limit or
just an uninstalled dependency; those look identical in the number and are nothing alike in the fix.
No index, no `codelens` command, or a language it does not cover (**Java · Ruby · TS/JS** only) →
fall back to Grep/Glob and write `⚠️ grep-depth only (no codelens index)` in the output. A grep hit
is never a resolved call — do not report it as one. Playbook: `docs/codelens.md`.

**Here:**
- **Attack surface = entry points.** `codelens explore "<controller|handler|listener>"` enumerates
  them with real signatures, including queue consumers that no route table lists.
- **For each sink** (query builder, deserializer, file write, shell-out, template render):
  `codelens callers <sink>` is the taint list — every path that reaches it.
- `codelens path <entry point> <sink>` turns "this looks reachable from user input" into a chain you
  can paste into the finding. An unreachable sink is a lower severity, and now you can prove which.
- Absence of a path is **not** proof of safety: reflection, dynamic dispatch and string-built calls
  are exactly what a graph misses. Say so instead of downgrading on silence.

## Audit categories (cover each; cite file·function·line)
1. **Input validation** — every entry point validates untrusted input at the boundary? whitelist > blacklist?
2. **Injection** — SQL/NoSQL (string-built queries), command, XSS, path traversal, SSRF, template injection.
3. **AuthN / AuthZ** — auth on every protected endpoint; **IDOR** (can a user reach others' resources?);
   role/permission checks at the top; tenant isolation; token expiry/rotation.
4. **Secrets & crypto** — hardcoded secrets/keys, secrets in logs, weak hashing (MD5/SHA1/plain),
   insecure randomness, secrets read from env/secret-manager.
5. **Sensitive-data exposure** — PII/tokens in responses or logs; stack traces to clients; verbose errors.
6. **Dependencies** — known-vulnerable patterns; unpinned versions; recommend an audit
   (`npm audit`/`pip-audit`/`govulncheck`) — note, don't run network installs.
7. **AI/LLM (if the repo calls an LLM)** — prompt injection (user input in system prompt),
   data exfiltration in prompts, unvalidated tool/function-call output, missing output guards.
8. **Misc** — CORS/headers, rate limiting, mass assignment, insecure deserialization, file-upload type/size.

## STRIDE threat model (per trust boundary / data flow)
Beyond the OWASP checklist, run a quick **STRIDE** pass on each major component / trust boundary
(entry point → service → data store; cross-service calls): **S**poofing (identity/auth),
**T**ampering (integrity of data/requests), **R**epudiation (audit trail/logging), **I**nformation
disclosure (leaks), **D**enial of service (resource limits), **E**levation of privilege (authz
bypass). Output a small table — `| Component/flow | STRIDE category | Threat | Mitigation present? |`
— and fold any gaps into Findings.

## Method
1. Enumerate the attack surface (entry points) from the KB + reading the code.
2. For each category, inspect the relevant code (**grep callers** to follow untrusted
   data from entry → sink). Prefer fanning out the **`namht-security-reviewer`** sub-agent on the
   high-risk areas.
3. Rate each finding: severity `[CRITICAL]/[MAJOR]/[MINOR]`, exploitability, and business impact.

## Output (dual-audience; save + render HTML)
Save to `namht-sessions/security/audit-<date>.md`, then render to HTML and open it.
Resolve this skill's `references/` dir first (call it `$SKILL_DIR`): `${CLAUDE_PLUGIN_ROOT}/skills/namht-security-audit/references`
if `CLAUDE_PLUGIN_ROOT` is set, else the `references/` folder next to this SKILL.md, else `$HOME/.claude/skills/namht-security-audit/references`.
```bash
node "$SKILL_DIR/render-html.cjs" <report.md> <report.html> "<repo> — security audit"
# then: open / xdg-open / start  the printed path
```
Requires Node — if absent, keep the `.md`, say HTML was skipped, and give the user the path.

```
# Security Audit — <project> (<date>)
## In plain words            ← overall risk posture, # criticals, are we safe to ship?
## Attack surface            ← entry points enumerated (table)
## Findings                  ← grouped by category:
### [CRITICAL] <title> · file·func·line
> Risk / how it's exploited · business impact
**Vulnerable code:** … **Fix:** … (complete, no placeholders)
## Severity summary          ← table: CRITICAL/MAJOR/MINOR counts by category
## Prioritized remediation   ← ordered fix list (what to do first)
## Out of scope / assumptions
```

## Rules
- **Don't fabricate.** Only report issues you can cite in the code; if a control exists, say so
  ("✅ parameterized queries used in …"). No generic "you should validate input" without a location.
- Read-only — never edit/exploit. Never print real secret values found (mask them; just point to the location).
- Highest-confidence first; mark uncertain items as "verify".
- For each [CRITICAL]/[MAJOR], offer to fix via `/namht-fix-bug`.
