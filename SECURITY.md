# Security & Enterprise Notes — `claude-code-workflow-kit`

This document is for a security reviewer evaluating whether to use this toolkit on a
company machine. It describes exactly what the code does, what it does **not** do, and how to
verify it yourself.

## TL;DR
- The analyzer/renderer code is **pure local** (Node `fs` / `path` / `crypto` only). **No `eval`,
  no dynamic `require`, no telemetry, no secrets.** Safe to copy and run locally.
- **Every network or process touchpoint is opt-in** — it runs only when you invoke it, never in
  the background:
  1. `skills/cwk-rails-to-spring/references/shadow-parity.cjs` — sends HTTP requests **only to
     the two `--source`/`--target` endpoints the user passes on the command line** (a parity test
     harness). No other destinations, no telemetry.
  2. The optional **VS Code extension** (`vscode-extension/`) — spawns the **local `claude` CLI**
     (whitelisted commands only); it makes no network calls of its own.
  3. `cwk-splunk-report` and `cwk-triage` (prompts, not code) — the agent queries Splunk and reads or
     posts to Slack (triage: also Rally) through the connected MCP servers or env credentials, never
     hardcoded; nothing is posted or created without the user's yes in that turn. `cwk-sre` (a
     prompt) calls AWS through the `aws` CLI and the profile the user names, read-only verbs only.
  4. `scripts/kb-pipeline.sh` runs `claude -p` in the repos you name; `scripts/schedule.sh` writes
     your crontab (after showing the change) so cron runs `claude -p` later.
  5. `scripts/fetch-vendor.sh` downloads the pinned Mermaid/Cytoscape builds (`npm pack` / `curl`
     from cdnjs) and checks them against `vendor/SHA256SUMS`.
  6. `scripts/kb-export.sh` asks `gh` for the hub repository's visibility before writing.
  7. Local processes only: `/cwk-map`, `scripts/onboard-project.sh` and `scripts/kb-pipeline.sh` run
     the `provenlens` CLI; `/cwk-pdf` (`html-to-pdf.sh`) starts a headless Chrome or wkhtmltopdf;
     `scripts/measure-diagrams.cjs` opens its report with `open` / `xdg-open`. The kit ships no
     hooks, so nothing of it runs on a tool call.
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
| Hooks | none (since 6.0.0) | The kit ships no hook and restricts no tool call or git command; the boundary is Claude Code's permission mode plus `permissions.deny` — see [No hooks](#no-hooks-since-600) |

## Executable-surface audit (verify it yourself)
```bash
# 1) Shell-out / eval / network surface — the ONLY expected matches are the touchpoints in the TL;DR:
#      - RegExp .exec(...) string matching (not process execution)
#      - fetch( in skills/cwk-rails-to-spring/references/shadow-parity.cjs (user-supplied endpoints only)
#      - child_process/spawn in vscode-extension/src/extension.ts (the local claude CLI),
#        skills/cwk-map/references/provenlens-*.cjs (the local provenlens CLI),
#        scripts/measure-diagrams.cjs (open / xdg-open), resources/check-mermaid.cjs (a local parse worker)
#      - curl / npm pack in scripts/fetch-vendor.sh, gh in scripts/kb-export.sh,
#        claude -p in scripts/kb-pipeline.sh and scripts/schedule.sh, crontab in scripts/schedule.sh
grep -rnE "child_process|execSync|spawn|\beval\(|new Function|http\.|https\.|fetch\(|net\.|dns\.|curl |npm pack|\bgh |crontab|claude -p|worker_threads" \
  --include='*.js' --include='*.cjs' --include='*.sh' --include='*.ts' --exclude-dir=tests --exclude-dir=node_modules .
#    (tests/ stubs these commands on purpose; they never reach the network)

# 2) Real require()s are stdlib + local siblings only:
grep -rnE "require\((['\"])" --include='*.js' --include='*.cjs' .   # fs, path, crypto, ./html-builder, ./graph-builder

# 3) No secrets committed:
grep -rniE "api[_-]?key|secret|password|BEGIN (RSA|PRIVATE)|sk-|ghp_|AKIA[0-9A-Z]{16}" .
#   → only the WORD "secret/token" in review checklists, no actual values.
```
Findings (as audited): no `eval`/`Function`, no dynamic `require`, no hardcoded secrets, no
telemetry. Process/network use is limited to the opt-in touchpoints listed in the TL;DR. `graph-builder.js`/`html-builder.js` are readable `tsc` output (not
minified) — provenance: the author's own Auto Spec extension project.

## Scripts that write outside this repo

Most of the kit only reads. Seven scripts do not, and each one is listed here with what it touches,
what stops it going wrong, and where that is pinned by a test. **None of them runs on its own** — you
invoke them.

| Script | Writes to | Guards |
|---|---|---|
| `scripts/personal-install.sh` | `~/.claude/{skills,commands,agents}` — symlinks; removes the retired guard-hook links in `~/.claude/hooks/` | Uninstall removes **only** links that resolve back into this repo; a foreign symlink survives. `CWK_CLAUDE_DIR` overrides the destination so the logic is testable. *(16 cases)* |
| `scripts/onboard-project.sh` | a target repo's `.gitignore`, and `CLAUDE.md` if absent | Whole-line ignore matching (a near-miss line does not count as present); an existing `CLAUDE.md` — root or `.claude/` — is never overwritten. *(17 cases)* |
| `scripts/schedule.sh` | your **crontab** | Only lines carrying its own end-anchored marker; prints the change and asks before writing; refuses to schedule any code-editing skill; escapes `%`, which cron would otherwise read as a newline. The job line quotes paths POSIX-style (dash-safe) and matches its own entries as plain text, so a path with `|` or `(` cannot touch another repo's job. A job may write only its own output (`knowledge-base/` for rescan, `cwk-sessions/`) and read git — never `acceptEdits`; it carries only the tool folders it needs, and a line over cron's 1000-byte command limit is refused. *(39 cases, behind a stubbed `crontab`)* |
| `scripts/kb-export.sh` | a hub directory (the KB **and** `cwk-sessions/runbook/`) | Refuses to write into a repo it can see is **public** (a KB is a readable distillation of your source), warns on **internal**, and stops when a hub with a remote has a visibility `gh` cannot read unless `--allow-unverified-visibility`; scans every exported text file for secrets; refuses to overwrite a snapshot taken from a *different* repo with the same folder name; never commits or pushes. *(part of 167 cases)* |
| `scripts/kb-import.sh` | a target repo's `knowledge-base/` | Refuses to overwrite an existing KB without `--force`, and keeps a timestamped backup under `cwk-sessions/kb-backups/` when forced — `knowledge-base/` is gitignored, so git is not an undo here. Warns when the snapshot's commit is absent from that checkout. |
| `scripts/kb-pipeline.sh` | nothing itself — it invokes `claude -p`, and the skills write `knowledge-base/`, `cwk-sessions/` and `.provenlens/` inside the repos you name | **Never clones**: a URL is rejected as a path, so it can only touch checkouts you already have. Prints the full plan with a per-repo step list, the permission mode in effect and a cost warning, and asks before the first token is spent (`--yes` to skip, `--dry-run` to print only). A step whose output exists is skipped unless `--force`. Defaults to `--permission-mode acceptEdits` rather than `bypassPermissions`: the safe mode is the default and the hammer is opt-in, named in the plan you confirm. *(32 cases, behind stubbed `claude`/`provenlens`)* |
| `scripts/migrate-sessions.sh` | renames `spec-kit-sessions/` → `cwk-sessions/` in a repo | Never overwrites on merge; leaves anything it could not merge in place; `--dry-run`. *(23 cases)* |
| `scripts/audit-log.sh` | `${CWK_AUDIT_LOG:-~/.claude/cwk-audit.jsonl}`, created `0600` | Appends one JSON line per action or decision: timestamp, user, host, action, cwd, and the key=values the caller passes. Never command text, file contents or secrets; `user:pass@` is stripped from anything URL-shaped. `CWK_AUDIT_LOG=off` disables it; a failure to write never fails the caller. Nothing in the kit stops the agent writing the log file itself — add an `Edit` deny rule for it if that matters (see [No hooks](#no-hooks-since-600)). |

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
  The one exception is the retired guard-hook links in `~/.claude/hooks/` (see [No hooks](#no-hooks-since-600)),
  removed by name and only if they are symlinks. It cannot delete arbitrary files.
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
- Nothing in the kit protects git's own configuration either: `git config` can write
  `~/.gitconfig` and `.git/config`, and the agent's file tools can edit them, unless your
  `permissions.deny` says otherwise (see [No hooks](#no-hooks-since-600) below).

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

## No hooks (since 6.0.0)

Up to 5.x the kit shipped a PreToolUse hook, `hooks/file-guard.sh` (with `hooks/hooks.json` and its
test suite), that refused agent writes to Claude Code's settings, the hooks, `~/.gitconfig`,
`.git/config`, `~/.ssh`, `~/.aws` and the audit log. **It was removed in 6.0.0**, so the kit now ships
**no hooks at all** (the git guard went in 4.0.0). `personal-install.sh` deletes the stale
`~/.claude/hooks/cwk-file-guard.sh` link and warns if `settings.json` still registers the hook; remove
that entry, or every matching tool call fails on a missing file.

Nothing in the kit now stops the agent editing its own policy or credential files. What does is
Claude Code itself: the **permission mode** (every write is a prompt unless the mode or an `allow`
rule says otherwise) and **`permissions.deny`**, which the harness enforces and the model cannot
argue with. A company deploys it from managed settings so a user or the agent cannot drop it; an
individual can put it in `~/.claude/settings.json`:

```jsonc
{ "permissions": { "deny": [
  "Edit(~/.claude/settings.json)", "Edit(~/.claude/settings.local.json)", "Edit(~/.claude.json)",
  "Edit(~/.claude/cwk-audit.jsonl)", "Edit(~/.gitconfig)", "Edit(**/.git/config)", "Edit(**/.git/hooks/**)",
  "Edit(~/.ssh/**)", "Edit(~/.aws/**)", "Edit(~/.config/gh/**)", "Edit(~/.netrc)",
  "Read(~/.ssh/**)", "Read(~/.aws/**)",
  "Bash(rm -rf ~/.claude*)"
] } }
```

An `Edit(…)` rule covers the file-editing tools, not a shell redirection or `sed -i`; a `Bash(…)`
rule matches the command text, so it is coarse and can be worded around. Keep the agent out of
`bypassPermissions`, and treat these rules as the boundary they are — there is no second layer from
this kit behind them.

## Recommended enterprise hardening

The full, concrete version — with the managed-settings JSON, the deny list, the SIEM one-liner and a
checklist a security team can tick — is **`docs/company-setup-guide.html`, Part A**. In one line each:

1. **What it is / is not** — prompts and short scripts; the model reading code is inherent to Claude Code, not added here; no telemetry; the kit's own network and process use is the opt-in list in the TL;DR (cdnjs at view-time only when `vendor/` is absent).
2. **Policy from managed settings** — the kit ships no hooks (since 6.0.0); deploy the permission mode and `permissions.deny` from managed settings (`/Library/Application Support/ClaudeCode/managed-settings.json`, `/etc/claude-code/managed-settings.json`, `C:\Program Files\ClaudeCode\managed-settings.json`) so settings and credential files are protected by rules the user and the agent cannot drop — see [No hooks](#no-hooks-since-600).
3. **Baseline `permissions.deny`** — git rules if you want git restricted (the kit ships no git guard), the `Edit(…)` rules for settings and credential files from the section above, plus `Read(~/.ssh/**)`, `Read(~/.aws/**)`, `Read(**/.env)`, `Read(**/.env.*)`, `Bash(curl *| sh*)`, `Bash(curl *| bash*)`, `Bash(wget *| sh*)`, `Bash(sudo:*)`, `WebFetch`; engineers run `--permission-mode acceptEdits`, readers the panel's `readonly` mode; never `bypassPermissions` on a company machine.
4. **GitHub Enterprise Server** — `gh auth login --hostname`, `HTTPS_PROXY`/`NO_PROXY`, and `vendor/` (verified by `scripts/fetch-vendor.sh --check`) for offline use.
5. **Windows** — the kit's scripts are bash and run under Git Bash/WSL only; the plugin and the `permissions.deny` list work natively (the kit ships no hooks, so there is nothing Windows misses).
6. **Data classification** — every KB carries `classification: public | internal | confidential | restricted` (default `internal`) in `_meta.yml`; the export copies it and the hub page shows it as a badge and a banner; the export secret scan, source stripping (`--with-source` is opt-in) and "never publish a hub of a company repo" govern where KB content may go.
7. **Repository hygiene** — the global gitignore protects one machine; put `knowledge-base/`, `cwk-sessions/`, `.provenlens/` in every team repo's `.gitignore` and refuse them in a pre-commit/CI check.
8. **Audit trail** — `scripts/audit-log.sh` appends JSON lines to `${CWK_AUDIT_LOG:-~/.claude/cwk-audit.jsonl}` (0600; never command text or secrets): scans, rescans, reviews, PR reviews, runbooks, exports, imports, pipelines, onboarding and schedules; ship it with `tail -F … | logger` or a cron copy.
9. **Freshness and depth** — trust a KB only at the `commit`/`generated` in its `_meta.yml`; `/cwk-rescan` on a schedule; `standard` depth samples layers over ~40 files, `deep` reads everything.
10. **Checklist** — the guide ends with the list a security team ticks before approving; pin the kit to a reviewed commit SHA (no release tags are published) and rerun `bash tests/run.sh` on each update.

_Not a substitute for your own security review. This reflects the state of the repo at audit time._
