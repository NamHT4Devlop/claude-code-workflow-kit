# Security & Enterprise Notes — `claude-code-workflow-kit`

This document is for a security reviewer evaluating whether to use this toolkit on a
company machine. It describes exactly what the code does, what it does **not** do, and how to
verify it yourself.

## TL;DR
- The analyzer/renderer code is **pure local** (Node `fs` / `path` / `crypto` only). **No `eval`,
  no dynamic `require`, no telemetry, no secrets.** Safe to copy and run locally.
- Exactly **four opt-in components touch the network or a local process** — each only at the
  user's explicit request, never in the background:
  1. `skills/cwk-rails-to-spring/references/shadow-parity.cjs` — sends HTTP requests **only to
     the two `--source`/`--target` endpoints the user passes on the command line** (a parity test
     harness). No other destinations, no telemetry.
  2. The optional **VS Code extension** (`vscode-extension/`) — spawns the **local `claude` CLI**
     (whitelisted commands only); it makes no network calls of its own.
  3. `cwk-splunk-report` (a prompt, not code) — instructs the agent to query Splunk / post to
     Slack using credentials from env/MCP, never hardcoded.
  4. `cwk-triage` (a prompt, not code) — reads a Slack thread, Splunk and (optionally) Rally through
     the connected MCP servers; it posts one reply into that thread or creates one Rally defect only
     after the user's yes in the same turn.
- Generated HTML can load Mermaid/Cytoscape from a CDN at view-time — **eliminated** when the
  bundled `vendor/` libraries are present (default in this repo → fully offline HTML).
- It contains **no credentials**. Nothing phones home. There is no telemetry in this repo.

## What's in the repo
| Type | Files | Risk |
|------|-------|------|
| Skill / command / agent prompts | `skills/`, `commands/`, `agents/` (Markdown) | Instructions for the AI; reviewed below |
| Static code analyzer | `skills/cwk-map/references/graph-builder.js` | Reads source files, builds a graph. `fs`/`path` only |
| HTML renderers | `skills/*/references/html-builder.js` + `render-html.cjs`, `build-map.cjs` | Markdown/graph → HTML. `fs`/`path`/`crypto` only |
| Vendored JS libs | `vendor/mermaid.min.js`, `vendor/cytoscape.min.js` | Upstream OSS, inlined into HTML for offline render |
| Install scripts | `scripts/personal-install.sh`, `scripts/onboard-project.sh`, `scripts/sync-bundles.sh` | Symlink into `~/.claude`; write `.gitignore`/`CLAUDE.md`; copy bundled files |
| Parity harness | `skills/cwk-rails-to-spring/references/shadow-parity.cjs` | **Outbound HTTP — only to the two user-supplied `--source`/`--target` URLs** (opt-in per run) |
| VS Code extension | `vscode-extension/` (TypeScript, proprietary) | **Spawns the local `claude` CLI** (whitelisted skill commands); no network of its own |
| Guard hook | `hooks/file-guard.sh` | the policy files and credential stores stay read-only to the agent. The kit restricts no git command since 4.0.0 |

## Executable-surface audit (verify it yourself)
```bash
# 1) Shell-out / eval / network surface — the ONLY expected matches are:
#      - RegExp .exec(...) string matching (not process execution)
#      - fetch( in skills/cwk-rails-to-spring/references/shadow-parity.cjs (user-supplied endpoints only)
#      - child_process/spawn in vscode-extension/src/extension.ts (spawns the local claude CLI)
grep -rnE "child_process|execSync|spawn|\beval\(|new Function|http\.|https\.|fetch\(|net\.|dns\." \
  --include='*.js' --include='*.cjs' --include='*.sh' --include='*.ts' .

# 2) Real require()s are stdlib + local siblings only:
grep -rnE "require\((['\"])" --include='*.js' --include='*.cjs' .   # fs, path, crypto, ./html-builder, ./graph-builder

# 3) No secrets committed:
grep -rniE "api[_-]?key|secret|password|BEGIN (RSA|PRIVATE)|sk-|ghp_|AKIA[0-9A-Z]{16}" .
#   → only the WORD "secret/token" in review checklists, no actual values.
```
Findings (as audited): no `eval`/`Function`, no dynamic `require`, no hardcoded secrets, no
telemetry. Process/network use is limited to the four opt-in components listed in the TL;DR
(shadow-parity → user-supplied endpoints; the extension → local `claude` CLI; splunk-report and
triage → env/MCP credentials). `graph-builder.js`/`html-builder.js` are readable `tsc` output (not
minified) — provenance: the author's own Auto Spec extension project.

## Scripts that write outside this repo

Most of the kit only reads. Seven scripts do not, and each one is listed here with what it touches,
what stops it going wrong, and where that is pinned by a test. **None of them runs on its own** — you
invoke them.

| Script | Writes to | Guards |
|---|---|---|
| `scripts/personal-install.sh` | `~/.claude/{skills,commands,agents,hooks}` — symlinks | Uninstall removes **only** links that resolve back into this repo; a foreign symlink survives. `CWK_CLAUDE_DIR` overrides the destination so the logic is testable. *(10 cases)* |
| `scripts/onboard-project.sh` | a target repo's `.gitignore`, and `CLAUDE.md` if absent | Whole-line ignore matching (a near-miss line does not count as present); an existing `CLAUDE.md` — root or `.claude/` — is never overwritten. *(14 cases)* |
| `scripts/schedule.sh` | your **crontab** | Only lines carrying its own end-anchored marker; prints the change and asks before writing; refuses to schedule any code-editing skill; escapes `%`, which cron would otherwise read as a newline. *(20 cases, behind a stubbed `crontab`)* |
| `scripts/kb-export.sh` | a hub directory (the KB **and** `cwk-sessions/runbook/`) | Refuses to write into a repo it can see is **public** (a KB is a readable distillation of your source); refuses to overwrite a snapshot taken from a *different* repo with the same folder name; never commits or pushes. *(part of 32 cases)* |
| `scripts/kb-import.sh` | a target repo's `knowledge-base/` | Refuses to overwrite an existing KB without `--force`, and keeps a timestamped backup when forced — `knowledge-base/` is gitignored, so git is not an undo here. Warns when the snapshot's commit is absent from that checkout. |
| `scripts/kb-pipeline.sh` | nothing itself — it invokes `claude -p`, and the skills write `knowledge-base/`, `cwk-sessions/` and `.provenlens/` inside the repos you name | **Never clones**: a URL is rejected as a path, so it can only touch checkouts you already have. Prints the full plan with a per-repo step list, the permission mode in effect and a cost warning, and asks before the first token is spent (`--yes` to skip, `--dry-run` to print only). A step whose output exists is skipped unless `--force`. Defaults to `--permission-mode acceptEdits` rather than `bypassPermissions`: the safe mode is the default and the hammer is opt-in, named in the plan you confirm. *(19 cases, behind stubbed `claude`/`provenlens`)* |
| `scripts/migrate-sessions.sh` | renames `spec-kit-sessions/` → `cwk-sessions/` in a repo | Never overwrites on merge; leaves anything it could not merge in place; `--dry-run`. *(15 cases)* |
| `scripts/audit-log.sh` (and both hooks) | `${CWK_AUDIT_LOG:-~/.claude/cwk-audit.jsonl}`, created `0600` | Appends one JSON line per action or decision: timestamp, user, host, action, cwd, and the key=values the caller passes. Never command text, file contents or secrets; `user:pass@` is stripped from anything URL-shaped. `CWK_AUDIT_LOG=off` disables it; a failure to write never fails the caller. The hooks refuse to let the agent write the log file itself. |

`scripts/kb-site.cjs` and the other Node generators only read and write inside the directory you
point them at. Their output is a self-contained HTML page: every document is JSON-escaped before it
is embedded (a `</script>` inside a scanned repo's comment must not close the data block), the page
declares a CSP whose `script-src` carries a nonce, and no external host is contacted.

## Data flow & egress
- **KB / analyzer**: 100% local. The `knowledge-base/` never leaves the machine.
- **provenlens** (optional, external tool): also 100% local — it indexes into `.provenlens/` inside
  the repo and makes no network calls of any kind. It is not vendored here; the kit only names
  its commands. The sub-agents are granted its **read-only MCP tools** and never `Bash`, so the
  read-only guarantee in the agent roster is unchanged. Add `.provenlens/` to your gitignore —
  `onboard-project.sh` does it for you — since the index describes the whole codebase.
- **The real egress is the AI agent itself**: when Claude reads code (via `Read`),
  that source enters the LLM context (Anthropic). This is inherent to using
  an AI coding assistant — **not added by this toolkit**. It is acceptable under a company
  **Team/Enterprise** Claude plan (commercial terms; Anthropic does not train on your data by
  default). Confirm your plan tier with your admin.
- **Generated HTML**: graph/markdown data is embedded **inline**. With `vendor/` present, the
  chart library is inlined too → the HTML makes **zero external network requests**. Without
  `vendor/`, it links Mermaid/Cytoscape from `cdnjs.cloudflare.com` at view-time (no data sent;
  may be blocked by a strict proxy). Delete `vendor/` for the small CDN-linked output, keep it
  for offline/air-gapped.

## Install-script safety
- `personal-install.sh` only creates symlinks under `~/.claude/{skills,commands,agents}` and, on
  uninstall, **only removes symlinks whose target points back into this repo** (`case "$SRC"/*`).
  It cannot delete arbitrary files.
- `onboard-project.sh` **writes into a target project** (`.gitignore` += `cwk-sessions/`,
  `knowledge-base/`, `.provenlens/`,
  and a starter `CLAUDE.md` if absent). Do **not** run it on a shared/team repo if you want zero
  footprint — review its diff first.

## Built-in safety behavior (prompts)
- `cwk-build` / `cwk-review` enforce a **change-discipline contract**: scope-locked, minimal
  diff, no drive-by refactors, don't leave the build broken (verify + rollback), confirm before
  destructive/outward actions, never touch secrets.
- `cwk-scan` skips secret files and records that a secret exists, never its value.
- All tool calls (Bash, Edit, installs) remain gated by Claude Code's permission system — the
  user approves them. Use an **untrusted workspace** until you trust a repo.

## Git — not restricted by this kit (since 4.0.0)

Up to 3.x the kit shipped `hooks/git-guard.sh`, a PreToolUse hook that limited pushes and `gh`
writes to a whitelist of owners and hosts and refused destructive local git. **It was removed in
4.0.0.** The kit now places no restriction of its own on git or `gh`: whatever Claude Code's
permission mode allows, the agent may run — including `push` to any remote, `push --force`,
`reset --hard`, `rebase`, `branch -D` and `gh` writes to any repository.

State the consequence plainly, because it is easy to assume otherwise:

- Under `--permission-mode bypassPermissions`, a destructive git command runs **without a prompt**.
  Nothing in the kit stands in front of it.
- The skills still *tell* the agent not to push during a build, not to run destructive git, and to
  undo only with `git stash` or `git apply -R`. That is an instruction the model follows, not a
  control that holds when it does not.
- `hooks/file-guard.sh` (below) deliberately does not inspect git commands, so `git config` can
  write `~/.gitconfig` and `.git/config` even though the file guard lists them as protected.

**If you want git restricted**, Claude Code's own `permissions.deny` does it without this kit, and
unlike a hook it cannot be argued with by the model:

```jsonc
{ "permissions": { "deny": [
  "Bash(git push:*)", "Bash(git reset --hard:*)", "Bash(git clean -f:*)", "Bash(git rebase:*)",
  "Bash(git commit --amend:*)", "Bash(git branch -D:*)", "Bash(git remote set-url:*)"
] } }
```

A deny rule matches the command text, so it is coarser than the retired hook — it cannot allow a
push to one owner and refuse it to another — but it is enforced by the harness, not by the kit.

## File guard (policy and credential files stay read-only)

`hooks/file-guard.sh` runs on `Edit`, `Write`, `MultiEdit`, `NotebookEdit` and `Bash`, and refuses
any write to `~/.claude/settings*.json` and project `.claude/settings*.json`, `~/.claude/hooks/*`,
the kit's own `hooks/` directory, the managed-settings locations, `~/.gitconfig`, `.git/config`,
`.git/hooks/*`, `~/.ssh`, `~/.aws`, `~/.config/gh`, `~/.netrc` and the audit log — through a file
tool, a shell redirection, `sed -i`, `cp`, `mv`, `rm`, `ln`, `chmod` or an interpreter. Reads
(`cat`, `grep`, `jq`, `diff`, `ls`) are allowed. git commands are not inspected (see above).
`tests/file-guard.test.sh` pins **50 cases**. It fails closed without `jq`.

Treat it as **defence in depth, not a security boundary**: it reads the text of one tool call, so it
cannot see inside a script file it is asked to run. An organisation that needs it enforced installs
it read-only from managed settings.

Each deny appends a JSON line to `${CWK_AUDIT_LOG:-~/.claude/cwk-audit.jsonl}` — the decision and
the path, never the command text.

The installer links it to `~/.claude/hooks/cwk-file-guard.sh`; arm it once in
`~/.claude/settings.json`:

```jsonc
{ "hooks": { "PreToolUse": [
  { "matcher": "Bash|Edit|Write|MultiEdit|NotebookEdit", "hooks": [
    { "type": "command", "command": "~/.claude/hooks/cwk-file-guard.sh", "timeout": 10 } ] }
] } }
```

Verify: `printf '{"tool_name":"Write","tool_input":{"file_path":"'"$HOME"'/.claude/settings.json"}}' | ~/.claude/hooks/cwk-file-guard.sh`
→ `"permissionDecision":"deny"`. (A settings change needs a Claude Code reload to go live.)

## Recommended enterprise hardening

The full, concrete version — with the managed-settings JSON, the deny list, the SIEM one-liner and a
checklist a security team can tick — is **`docs/company-setup-guide.html`, Part A**. In one line each:

1. **What it is / is not** — prompts and short scripts; the model reading code is inherent to Claude Code, not added here; no telemetry; the only egress is cdnjs at view-time when `vendor/` is absent.
2. **File guard as policy** — install `hooks/file-guard.sh` root/admin-owned and wire it from managed settings (`/Library/Application Support/ClaudeCode/managed-settings.json`, `/etc/claude-code/managed-settings.json`, `C:\Program Files\ClaudeCode\managed-settings.json`); the limits in the file-guard section above apply.
3. **Baseline `permissions.deny`** — git rules if you want git restricted (the kit ships no git guard), plus `Read(~/.ssh/**)`, `Read(~/.aws/**)`, `Read(**/.env)`, `Read(**/.env.*)`, `Bash(curl *| sh*)`, `Bash(curl *| bash*)`, `Bash(wget *| sh*)`, `Bash(sudo:*)`, `WebFetch`; engineers run `--permission-mode acceptEdits`, readers the panel's `readonly` mode; never `bypassPermissions` on a company machine.
4. **GitHub Enterprise Server** — `gh auth login --hostname`, `HTTPS_PROXY`/`NO_PROXY`, and `vendor/` (verified by `scripts/fetch-vendor.sh --check`) for offline use.
5. **Windows** — the hooks are bash and run under Git Bash/WSL only; a Windows install without them has no guard, only the deny list.
6. **Data classification** — every KB carries `classification: public | internal | confidential | restricted` (default `internal`) in `_meta.yml`; the export copies it and the hub page shows it as a badge and a banner; the export secret scan, source stripping (`--with-source` is opt-in) and "never publish a hub of a company repo" govern where KB content may go.
7. **Repository hygiene** — the global gitignore protects one machine; put `knowledge-base/`, `cwk-sessions/`, `.provenlens/` in every team repo's `.gitignore` and refuse them in a pre-commit/CI check.
8. **Audit trail** — `scripts/audit-log.sh` and both hooks append JSON lines to `${CWK_AUDIT_LOG:-~/.claude/cwk-audit.jsonl}` (0600; never command text or secrets): scans, rescans, reviews, PR reviews, runbooks, exports, imports, pipelines, onboarding, schedules, every hook deny and every allowed push/`gh` write; ship it with `tail -F … | logger` or a cron copy.
9. **Freshness and depth** — trust a KB only at the `commit`/`generated` in its `_meta.yml`; `/cwk-rescan` on a schedule; `standard` depth samples layers over ~40 files, `deep` reads everything.
10. **Checklist** — the guide ends with the list a security team ticks before approving; pin the kit to a reviewed tag and rerun `bash tests/run.sh` on each update.

_Not a substitute for your own security review. This reflects the state of the repo at audit time._
