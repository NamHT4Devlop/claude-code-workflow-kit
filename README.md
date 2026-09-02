# namht Kit for Claude Code

A native **Claude Code** port of the author's private Auto Spec VS Code
extension. Same spec-driven workflow — **Requirement → Plan → Code → Review → Test →
Evidence** — plus Knowledge Base generation, codebase Q&A, user stories, dependency mapping,
and business↔code documentation. The difference: it runs on **Claude Code** (your own
tools: file ops, Bash, git, parallel sub-agents) instead of GitHub Copilot / `vscode.lm`.

> **Your existing Knowledge Bases work as-is.** The KBs you generated with the old extension
> are plain Markdown under each repo's `knowledge-base/`. Every command here reads that same
> folder — nothing to migrate or regenerate. Only run `/namht-scan` for brand-new repos.

---

## What's inside

```
nam-claude-skill/
├── .claude-plugin/
│   ├── plugin.json          # plugin manifest
│   └── marketplace.json     # local marketplace (for one-command install)
├── commands/                # 31 slash commands → /namht:build (plugin) or /namht-build (personal), …
├── skills/                  # 30 skills (the methodology — also usable standalone)
│   ├── namht-build/          #   13-step pipeline   (+ bundled review checklist)
│   ├── namht-scan/           #   KB generation       (+ bundled kb-steps spec)
│   ├── namht-rescan/         #   incremental KB update
│   ├── namht-review/         #   two-phase review    (+ bundled review checklist)
│   ├── namht-ask/            #   KB-grounded Q&A
│   ├── namht-plan/           #   PO/BA user stories
│   ├── namht-map/            #   interactive HTML code graph (Cytoscape)
│   └── namht-document/       #   business↔code doc
├── agents/                  # 7 specialist sub-agents (planning + review)
├── resources/               # review-skills-universal.md, kb-steps.md
├── hooks/                   # git-guard.sh + hooks.json (PreToolUse git guardrail)
├── scripts/                 # personal-install.sh, onboard-project.sh, sync-bundles.sh
├── docs/                    # setup guides (HTML) + skill-anatomy.md (the standard skills follow)
│                           #   + codelens.md (the optional call-graph dependency)
├── tests/                   # toolkit self-tests
└── vscode-extension/        # optional VS Code panel that drives the local claude CLI (proprietary)
```

Commands are thin entry points; the **skills** hold the actual methodology and auto-activate
from natural language too (you don't have to type the slash command). The **agents** are the
read-only specialists the build/review steps fan out to in parallel.

---

## Prerequisites

- **Claude Code** installed and working (`claude --version`). Plugins/marketplaces need a
  recent version — if `/plugin` is unknown, update Claude Code first (`claude update` or
  reinstall from the official docs).
- **git** installed (`git --version`) — needed to clone this repo and used by `rescan`/`review`.
- **Access to this repository.** It is **public**, so anyone can clone it — no special access
  needed. The plugin itself needs **no API key** — it runs on your existing Claude Code.
- Paths below use `~/.claude` (macOS/Linux). On **Windows** use `%USERPROFILE%\.claude`
  (PowerShell: `$HOME\.claude`).
- **Windows, read this first.** Option A (plugin) works natively — it is all typed inside
  Claude Code. The shell scripts in `scripts/` and the `hooks/git-guard.sh` hook are **bash**,
  so they need **Git Bash** (ships with Git for Windows) or **WSL**. If you want a pure
  PowerShell install, use **Option B** below — it is plain file copying and needs no bash.
  There is no PowerShell port of `personal-install.sh`: it creates symlinks and merges
  `settings.json`, and shipping an untested installer for a platform I cannot test on would be
  worse than telling you this plainly.

---

## Get the code

Pick a stable location to keep the plugin (so you can update it with `git pull` later):

```bash
# via SSH (recommended if your GitHub uses SSH keys)
git clone git@github.com:NamHT4Devlop/nam-claude-skill.git ~/nam-claude-skill

# or via HTTPS
git clone https://github.com/NamHT4Devlop/nam-claude-skill.git ~/nam-claude-skill
```

Everywhere below, `<PLUGIN_DIR>` means the folder you cloned into (e.g. `~/nam-claude-skill`).
If you keep the files somewhere else, substitute that absolute path.

---

## Install — Option A: as a plugin (recommended)

Best when you want every command available across **all** your repos on a machine, with clean
`/namht:*` namespacing. Run these **inside a Claude Code session** (the `/plugin`
commands are typed into Claude Code, not your shell):

```
/plugin marketplace add ~/nam-claude-skill
/plugin install namht@namht-marketplace
```

- `marketplace add <PLUGIN_DIR>` registers the local marketplace defined in
  `.claude-plugin/marketplace.json`. You can also point it straight at the GitHub repo:
  `/plugin marketplace add NamHT4Devlop/nam-claude-skill` (Claude Code clones it for you; requires
  repo access).
- `install namht@namht-marketplace` installs the plugin named `namht` from that
  marketplace.
- Reload when prompted (or run `/plugin` to manage installed plugins).

After install, commands are namespaced by the plugin (type `/` to see them):
`/namht:scan`, `/namht:rescan`, `/namht:build`, `/namht:fix-bug`, `/namht:review`, `/namht:ask`,
`/namht:plan`, `/namht:map`, `/namht:system-map`, `/namht:document`, `/namht:help`.
The 30 skills and 7 sub-agents load automatically (skills also activate from plain English), and the
**git-guard hook ships with the plugin** (`hooks/hooks.json`) so it's active right after install.
(The personal symlink install — Option C — exposes the same commands as `/namht-build`, etc.)

> **Team install:** commit/host this repo, then each teammate runs the two `/plugin` commands
> above pointing at their clone (or at `NamHT4Devlop/nam-claude-skill`). To pin the plugin for a
> whole project automatically, add it to the project's `.claude/settings.json` under
> `enabledPlugins` / configure a marketplace there (see Claude Code plugin docs).

## Install — Option B: plain skills (no plugin machinery)

Best when you want to **commit the skills into a specific repo** (so collaborators get them on
clone), or you prefer not to use marketplaces.

**B1 — Per project** (only that repo gets the commands/skills):

```bash
# run from the target repo's root
mkdir -p .claude/skills .claude/commands .claude/agents
cp -R <PLUGIN_DIR>/skills/*   .claude/skills/
cp -R <PLUGIN_DIR>/commands/* .claude/commands/
cp -R <PLUGIN_DIR>/agents/*   .claude/agents/
```

**B2 — Per user** (all your repos on this machine):

```bash
mkdir -p ~/.claude/skills ~/.claude/commands ~/.claude/agents
cp -R <PLUGIN_DIR>/skills/*   ~/.claude/skills/
cp -R <PLUGIN_DIR>/commands/* ~/.claude/commands/
cp -R <PLUGIN_DIR>/agents/*   ~/.claude/agents/
```

**B — on Windows (PowerShell, no bash needed):**

```powershell
# per project — run from the target repo's root
New-Item -ItemType Directory -Force .claude\skills, .claude\commands, .claude\agents | Out-Null
Copy-Item -Recurse -Force <PLUGIN_DIR>\skills\*   .claude\skills\
Copy-Item -Recurse -Force <PLUGIN_DIR>\commands\* .claude\commands\
Copy-Item -Recurse -Force <PLUGIN_DIR>\agents\*   .claude\agents\

# per user — same thing into $HOME\.claude
New-Item -ItemType Directory -Force $HOME\.claude\skills, $HOME\.claude\commands, $HOME\.claude\agents | Out-Null
Copy-Item -Recurse -Force <PLUGIN_DIR>\skills\*   $HOME\.claude\skills\
Copy-Item -Recurse -Force <PLUGIN_DIR>\commands\* $HOME\.claude\commands\
Copy-Item -Recurse -Force <PLUGIN_DIR>\agents\*   $HOME\.claude\agents\
```

> The **git-guard hook is not installed by this route** on any platform — Option A ships it with the
> plugin, Option C installs it via the script. On Windows without bash the hook cannot run at all;
> rely on Claude Code's own permission prompts instead, and know that is a weaker guarantee.

**You do NOT need to copy the plugin's `resources/` folder for Option B.** Each skill is
self-contained — it bundles whatever it needs under its own `references/` subfolder, which
comes along automatically with `cp -R skills/*`:
`namht-build`/`namht-review`/`namht-scan`/`namht-rescan` carry the review checklist and/or the
KB-section spec. `resources/` at the repo root is only a canonical copy for the plugin form.

> ⚠️ **Difference from Option A:** as plain skills the slash commands are **not** namespaced —
> they're `/build`, `/review`, `/scan`, etc. If those names clash with other commands you have,
> rename the files in `.claude/commands/` (e.g. `build.md` → `namht-build.md`).

## Install — Option C: personal-only, zero footprint in any repo (just for you)

Use this when the plugin/skills are **for your eyes only** and must never appear in — or be
committed to — any team/project repo. It installs into your home dir via symlinks and routes
all generated artifacts to a machine-wide gitignore.

```bash
# 1) symlink skills/agents/commands into ~/.claude (commands get a namht- prefix)
<PLUGIN_DIR>/scripts/personal-install.sh

# 2) make every namht Kit artifact invisible to git, machine-wide (no per-repo edits)
touch ~/.gitignore_global
printf '%s\n' 'namht-sessions/' 'spec-kit-sessions/' 'knowledge-base/' 'CLAUDE.local.md' >> ~/.gitignore_global
git config --global core.excludesfile ~/.gitignore_global
```

- Commands become `/namht-build`, `/namht-scan`, `/namht-review`, … (prefixed so they don't shadow
  built-ins like `/help`). Skills also auto-activate from plain English.
- Because it's symlinks, `git pull` in `<PLUGIN_DIR>` instantly updates your install.
- The global gitignore means even if you run `/namht-scan` inside a team repo, its
  `knowledge-base/` and `namht-sessions/` stay **local and uncommitted** — nothing leaks.
- **Pick ONE method** — if you use this, do *not* also `/plugin install` the same plugin.
- Uninstall: `<PLUGIN_DIR>/scripts/personal-install.sh uninstall`.

> Note: a global ignore of `knowledge-base/` keeps your KBs private. If a project legitimately
> needs a committed `knowledge-base/`, force-add it there with `git add -f knowledge-base/`.

---

## Verify the install

1. In a Claude Code session, type `/` and confirm the `namht:` commands (Option A) or
   `/build`, `/scan`… (Option B) appear.
2. Run `/namht-help` (or `/help` for plain skills) — it prints all commands **and** checks
   whether the current repo has a `knowledge-base/`.
3. Plugin only: run `/plugin` → you should see **namht** listed as installed/enabled.

## Update to the latest version

- **Option A (plugin):**
  ```bash
  cd <PLUGIN_DIR> && git pull
  ```
  then in Claude Code: `/plugin marketplace update namht-marketplace` (or remove & re-add
  the marketplace, then reinstall). Reload when prompted.
- **Option B (plain skills):** `git pull` in `<PLUGIN_DIR>`, then re-run the `cp -R` commands
  to overwrite the copies.

## Uninstall

- **Option A:** `/plugin uninstall namht` (and optionally
  `/plugin marketplace remove namht-marketplace`).
- **Option B:** delete the copied folders, e.g.
  run `<PLUGIN_DIR>/scripts/personal-install.sh uninstall` (removes only the symlinks that point back to this repo).

## Troubleshooting

| Symptom | Fix |
|---------|-----|
| `/plugin` is not recognized | Update Claude Code; plugins require a recent version. |
| `marketplace add` fails on a path | Pass an **absolute** path to `<PLUGIN_DIR>` and ensure `.claude-plugin/marketplace.json` exists there. |
| `git clone` asks for a password / permission denied | The repo is public — clone the HTTPS URL (no auth needed), or set up an SSH key for the `git@` URL. |
| Commands don't show up | Reload the Claude Code window/session after install; for plain skills, confirm files landed in `.claude/commands` & `.claude/skills`. |
| A command says "no knowledge-base found" | Run `/namht-scan` once in that repo (or reuse an existing `knowledge-base/` folder). |
| Command name clash (Option B) | Rename the files in `.claude/commands/`. |

---

## Recommended setup for a multi-project workspace

If you keep many repos under one parent folder (a "workspace"), follow this separation:

- **Tool = global, from git.** Install once as a plugin (Option A). Update everywhere with one
  `git pull` + marketplace update. Don't copy skills into each repo.
- **Knowledge Base = per project, versioned with the code.** Each repo keeps its own
  `knowledge-base/`; commit it so the team shares it. Refresh with `/namht-rescan`.
- **Operate one project per session.** `cd <project> && claude` so commands read *that*
  project's `knowledge-base/`. The parent workspace is just an organizing folder — don't run
  from the workspace root and expect commands to guess which sub-project you mean. (A true
  **monorepo** — one git repo, many packages — is the opposite: run at the repo root; `scan`
  produces per-module docs under `knowledge-base/modules/`.)
- **Per-project hygiene** — gitignore the generated `namht-sessions/`, and drop a short
  `CLAUDE.md` so every session in that repo knows the KB exists. Automate it:

  ```bash
  # from your clone of this repo
  scripts/onboard-project.sh /path/to/your/project   # idempotent; commits nothing
  ```

  It adds `namht-sessions/` to `.gitignore`, creates a starter `CLAUDE.md` (only if absent),
  and reports whether the project has a KB yet (→ run `/namht-scan` if not).

## Commands

| Command | What it does |
|---------|--------------|
| `/namht-scan` | Generate the Knowledge Base from the codebase (16 docs + `review-skills.md` + per-module docs). Run first on a new repo. |
| `/namht-rescan` | Update the KB incrementally after code changes (git-diff aware). |
| `/namht-build <requirement>` | 13-step pipeline: clarify → plan (impact + business flow) → code → multi-lens review → tests → run tests → evidence → update KB. |
| `/namht-fix-bug <error/stack trace>` | Production hotfix: triage → locate (read the code) → root-cause → failing regression test → minimal surgical fix → verify (tests+build, rollback) → hotfix report + KB update. Does not deploy. |
| `/namht-review [file\|PR#]` | Two-phase review: quality checklist + business consistency vs the KB. Empty arg = current branch vs the default branch (or working-tree diff if uncommitted); accepts a PR #/URL (`gh pr diff`). |
| `/namht-ask <question>` | Q&A grounded in the KB — plain language + Mermaid diagram + technical detail. |
| `/namht-plan <epic>` | PO/BA: Epic → features → impact → user stories (Given/When/Then) → sprint plan. |
| `/namht-issues [plan] [target] [--create]` | Turn a plan / user stories into real tracker issues — GitHub via `gh`, Jira/Linear via a connected MCP. One issue per story, ACs as a checklist, ids kept so re-runs update instead of duplicating. Preview-by-default; creating needs an explicit yes. |
| `/namht-qa <user story>` | QA: user story → test cases covering the **NEW flow + regression for OLD business flows** (Gherkin + manual table + AC↔case traceability). Designs tests; doesn't code them. |
| `/namht-pr [review <PR#>]` | Prepare a PR description from the current branch, or review a GitHub PR (`gh pr diff` → two-phase review + blast radius). Read-only on the remote. |
| `/namht-security-audit [scope]` | Whole-repo security audit: attack surface + injection/authz/IDOR/secrets/exposure/AI, grounded in the KB, with severities + fixes. Read-only. |
| `/namht-drift [scope] [--fix-docs]` | Docs-vs-reality audit of the whole repo: stale KB entries, undocumented behavior, acceptance criteria promised but never shipped, broken architecture invariants. Read-only by default and routes each finding to rescan/build/review; `--fix-docs` additionally offers to refresh the stale **docs** (never source). See [Keeping docs and code from drifting apart](#keeping-docs-and-code-from-drifting-apart). |
| `/namht-map [scope]` | Interactive HTML code graph (Cytoscape): files/classes + imports/DI/inheritance/calls; zoom, click, filter, search. Opens in browser. |
| `/namht-system-map` | **Cross-service** map for a multi-repo microservices workspace: stitches each service's API/integrations into a dependency graph + end-to-end flows (sequence diagrams) + contracts/events + risks. Run at the workspace root. |
| `/namht-document <topic>` | Business↔code field-level technical document for a feature/entity/module. |
| `/namht-discover <idea>` | Discovery before planning: forcing questions, push back on framing, output a sharpened problem brief. |
| `/namht-plan-review <plan>` | Critique a plan before building — Product / Architecture / Risk-QA / DevEx lenses + verdict. |
| `/namht-qa-integration <url>` | Execute E2E/integration QA against a **running app** via a real browser (Claude-in-Chrome); pass/fail + screenshots. |
| `/namht-design-review <url\|path>` | UI/UX + accessibility review via browser screenshots / frontend code; findings + fixes. Read-only. |
| `/namht-pdf <file>` | Export a Markdown/HTML report to PDF (renders Mermaid first; headless Chrome/wkhtmltopdf). |
| `/namht-retro [window]` | Engineering retrospective from git history — shipped, pain, quality signals, action items. |
| `/namht-runbook [service]` | Turn the KB + the repo's real deploy/CI/error-handling config into an **operational runbook**: health checks, deploy and rollback (incl. what rollback does *not* undo), symptom→fix incident playbooks, alerts→action, data recovery. Marks what only a human knows instead of inventing it. |
| `/namht-skillify <name+purpose>` | Scaffold a new `namht-*` skill + command following the conventions (self-extend the kit). |
| `/namht-splunk-report [apps + window]` | Query Splunk for per-app errors over a window (default today), aggregate into one table, and post it to Slack. Read-only on Splunk; credentials from env/MCP, never hardcoded. Needs network. |
| `/namht-user-story <requirement or Slack link>` | Deep-investigate a requirement (or comprehend a Slack thread) → features + INVEST user stories with maximally granular Given/When/Then ACs. |
| `/namht-rails-to-spring <endpoint set>` | Contract-first port to another stack (e.g. Rails+GraphQL → Spring Boot/MyBatis) — golden-test parity per endpoint, strangler cutover. Edits code. |
| `/namht-observe [area]` | Instrument code for observability — structured logs, correlation/trace IDs (HTTP + SQS), metrics, error context; matches the backend field schema. Edits code. |
| `/namht-migrate [change]` | Plan + execute a safe migration/deprecation (API, DB schema, event contract, library) — backward-compatible, staged, with a rollback per step + deprecation window. |
| `/namht-simplify [target]` | Behavior-preserving simplification — remove dead code, flatten nesting, extract/rename, kill duplication; one refactor at a time, tests stay green. |
| `/namht-perf [area]` | Measure-first performance optimization — N+1, indexes, blocking calls, caching, pagination; proves the win with before/after numbers. |
| `/namht-help` | Show all commands + KB status for the current repo. |

**Recommended flow:** `discover` → `plan` → `plan-review` → `qa` (design tests) → `build` →
`qa-integration` (run them) → `review`/`security-audit` → `pr`. Run `scan` once first; `rescan` to
keep the KB fresh, and `drift` every so often to find what `rescan` never heard about.

---

## The Knowledge Base — what `/namht-scan` actually produces

Every other command reads this. It is the difference between an assistant that guesses about your
system and one that cites it.

```
knowledge-base/
├── 01-project-structure.md    07-architecture-diagram.md   13-business-rules.md   ★
├── 02-tech-stack.md           08-database-schema.md        14-integrations.md
├── 03-entry-points.md         09-auth-security.md          15-error-scenarios.md
├── 04-business-domain.md  ★   10-core-flows.md         ★   16-architecture-patterns.md ★
├── 05-domain-model.md     ★   11-api-docs.md               17-async-events.md  (if it uses queues)
├── 06-modules.md              12-conventions.md
├── modules/<module>.md        — per-module deep docs + _index.md
├── review-skills.md           — the universal review checklist + a project-specific Section 14
├── _coverage-report.md        — what was analysed vs sampled, and what was deferred BY NAME
└── _meta.yml                  — project · repo · branch · commit · date · depth · modules
```

★ = the five deep documents. Two of them carry most of the value: **`10-core-flows.md`** (what the
system does, end to end) and **`13-business-rules.md`** (the rules it enforces).

### If your system has a lot of business logic, read this part

```bash
claude "/namht-scan deep"
```

- **Rules and flows get stable ids.** `BR-V2` (Validation #2), `BR-S1` (State), `CF-03` (core flow),
  and so on. `/namht-qa` writes a regression test that says *which* rule it protects; `/namht-build`
  ties an acceptance criterion to one; `/namht-review` cites one in a finding. Ids are **append-only**
  — never renumbered, never reused, and a rule whose code is gone is marked `[REMOVED <date>]` rather
  than deleted, because those ids live on in test names and past reports that a rescan cannot see.
- **Each rule records where it is enforced and how it is tested.** A `NONE` in the test column is a
  finding, not a blank — they roll up into *Under-Enforced Business Rules*, which is usually the most
  valuable page in the whole KB. Read that section first.
- **There is no cap on core flows.** Past ~8, the cross-cutting ones stay in `10-core-flows.md` and
  module-local ones move into `modules/<m>.md` with an index line. Splitting is fine; dropping is not,
  and anything deferred is named in `_coverage-report.md`.
- **The business layer is never sampled**, at any depth. Domain/service code, state machines,
  validators and calculations are read in full; controllers and DTOs get sampled instead, where the
  loss is cosmetic. A sampled business layer produces a KB that *looks* complete and is missing the
  rules everything else depends on.

### Depth is the cost dial

| Depth | What it does | Use it when |
|---|---|---|
| `quick` | Entry points, models and tests, sampled; the five deep docs written from that sample; module docs for the ~5 largest modules | First look at an unfamiliar repo |
| `standard` | All 16 docs, sampling per layer above ~40 files (business layer excluded) | The usual choice |
| `deep` | No sampling at all; a module document for **every** module | A repo you are about to migrate, audit, or build heavily in — **and any business-heavy system** |

Above ~1500 source files the skill proposes `quick` first rather than silently spending an hour of
tokens. Whichever it used is stated at the top of `_coverage-report.md`.

### Keeping it true

```bash
claude "/namht-rescan"      # after code changes — git-diff aware, updates only what moved
claude "/namht-drift"       # every so often — finds what rescan never heard about
```

`rescan` refreshes `_meta.yml`'s commit and date, so a stale KB stops passing itself off as current.
`drift` is the wider check: hand-applied hotfixes, acceptance criteria promised but never built,
architecture invariants quietly broken — see
[Keeping docs and code from drifting apart](#keeping-docs-and-code-from-drifting-apart).

Two checks worth doing right after a first scan:

1. `13-business-rules.md` — how many rules show `NONE` in the test column? That list is your
   untested business logic, ranked by the severity already assigned to each rule.
2. `_coverage-report.md` — is anything under *Flows not yet documented*? Those are the gaps the
   scan knows about; decide whether to spend `deep` on them.

---

## Call-graph awareness — `codelens` (optional)

The Knowledge Base above is what the system **means**. [`codelens`](https://github.com/NamHT4Devlop/codelens)
is what it **does**: a pre-built graph of symbols and who-calls-what, so a skill can ask for the real
callers of a symbol instead of grepping for its name.

Nothing here requires it. **27 of the 30 skills** use it when a `.codelens/` index is present and
fall back to Grep/Glob when it is not — and when they fall back they say so, marking the output
`⚠️ grep-depth only (no codelens index)`. That sentence is the point: a caller list from grep and one
from a resolved call graph are not the same claim, and an impact analysis that hides which one it
used is the kind that gets trusted wrongly.

What changes when the index is there:

| Skill | Without | With |
|---|---|---|
| `/namht-build` | callers counted by grep — including the ones that are only a string match | `codelens impact`; the **>3 callers** approval gate is counted from the graph, and `affected --fail-if-untested` blocks a change no test reaches |
| `/namht-review` · `/namht-pr` | consumers inferred from the diff | `git diff --name-only \| codelens affected` — resolved consumers, with the tests that already cover them |
| `/namht-simplify` | "nothing references it" | `codelens dead`, already filtered against names used in `.erb`/`.vue`/`.html`/`.yml` |
| `/namht-security-audit` | a sink that *looks* reachable | `codelens path <entry point> <sink>` — the chain, pasted into the finding |
| `/namht-system-map` | cross-service edges read out of KB prose | producer ↔ consumer joined on a real queue name or endpoint URI, across repos and languages |
| `/namht-map` | regex import + inheritance scan (9 languages) | resolved call edges with a confidence (Java · Ruby · TS/JS), regex scan kept for the rest |

**Covers Java, Ruby, TypeScript and JavaScript only.** For Python, Go, C#, PHP, Rust or Kotlin the
fallback is the only path, and the skills say so rather than implying coverage they do not have.

Setup is three commands, and it runs fully offline:

```bash
git clone git@github.com:NamHT4Devlop/codelens.git ~/AI-TOOL/codelens && cd ~/AI-TOOL/codelens && yarn install
```

```bash
ln -sf ~/AI-TOOL/codelens/bin/codelens.js ~/.local/bin/codelens && codelens install claude-user
```

```bash
cd /path/to/your/repo && codelens init .
```

The two files bundled into many skills at once carry it too: `resources/review-skills-universal.md`
opens with a **§0 Evidence** section — which command settles which claim, and the rule that a finding
degraded to grep must say so — and `resources/kb-steps.md` makes structural claims come from the
graph where one exists, while forbidding graph output from being pasted into a KB page (a fan-in
number is not a business meaning).

`scripts/onboard-project.sh` adds `.codelens/` to the project's `.gitignore` (it is a rebuildable
cache and must never reach a team repo) and reports the index status. The seven sub-agents in
`agents/` are granted the **read-only MCP tools only** — never `Bash` — so the review specialists
stay read-only. Full detail, including which five skills deliberately opt out and why:
[`docs/codelens.md`](docs/codelens.md).

## Keeping docs and code from drifting apart

Every other command works **one change at a time**. `/namht-build` updates the KB for what it just
touched, `/namht-rescan` updates it for what git shows changed. Neither catches the slow rot: a
hotfix applied by hand, a colleague's merge, a feature that was planned and quietly never built, an
architecture rule broken once "just for now". After a few months the Knowledge Base is confidently
describing software that no longer exists — and every answer built on it is wrong.

`/namht-drift` is the periodic check for exactly that. It audits the whole repo and reports four
kinds of drift:

| | Drift | Question it answers | Fix route |
|---|---|---|---|
| **D1** | Stale doc | The KB describes something the code no longer does | `/namht-rescan` |
| **D2** | Undocumented code | Real behavior no document mentions | `/namht-rescan` |
| **D3** | Unbuilt promise | An AC from a story/plan in `namht-sessions/` that never shipped | `/namht-build` |
| **D4** | Broken invariant | Code violates the documented "DO NOT BREAK" rules | `/namht-review` |

Each finding must cite **`file:line` on one side and the document line on the other**, and state
**which side is wrong** — sub-agents only produce leads; the skill re-verifies every one against the
source before it appears in the report. It ends with a verdict (`CONVERGED` / `DRIFTING` / `STALE`)
and appends a row to `namht-sessions/drift/_journal.md`, so successive runs show whether drift is
growing or shrinking.

**When to run it**

| Moment | Why |
|---|---|
| Before a release or a handover | This is when a wrong document does real damage |
| After a stretch of rushed work (crunch sprint, incident firefighting) | Exactly when drift is created |
| Every ~month, or at each sprint boundary | The journal turns it into a trend instead of a snapshot |
| Before onboarding someone new | They will trust the KB; a wrong KB teaches them the wrong system |
| When `/namht-ask` starts answering *almost* right | That is the symptom of a KB going stale |
| Before a large port or migration | Porting from wrong docs copies the mistake into the new stack |

You don't need it after every task — `/namht-build` already keeps its own footprint documented.

### `--fix-docs` — the one thing it will fix for you

By default `/namht-drift` **changes nothing**: it reports and hands off. With `--fix-docs` it also
offers to close the documentation half of the drift:

```bash
claude "/namht-drift --fix-docs"
```

What that mode will and will not do:

- ✅ Only **D1/D2** findings where the audit concluded **the document** was wrong.
- ✅ Shows the findings and the exact `knowledge-base/` files first, and needs **one explicit yes**
  — a "go" in your original request does not count, because you have not seen the findings yet.
- ✅ **Backs those KB files up** to `namht-sessions/drift/<date>-kb-backup/` before anything is
  written. `knowledge-base/` is normally gitignored, so git is *not* your undo here.
- ✅ Delegates the actual writing to `/namht-rescan` (one owner for KB writes), then **re-verifies**
  each fixed claim and reports what it could not confirm.
- ❌ Never edits **source code** — in any mode, with any flag. That is `/namht-build`'s job.
- ❌ Never auto-resolves **D3** (writing an unbuilt AC into the docs as if shipped) or **D4**
  (relaxing a documented invariant to match the code). Rewriting the rule to match the violation is
  precisely the failure this command exists to catch.
- ❌ Refuses surgical patching when the verdict is `STALE` — a KB that broadly stopped matching the
  codebase needs a full `/namht-rescan`, not fifty patches.

The reason it stops there: when a doc and the code disagree, **you do not yet know which one is
wrong**. Sometimes the doc lags. Sometimes the doc is the agreed intent and the code is the bug.
Auto-rewriting the doc to match the code would turn that bug into "the new spec" and delete the
evidence that anything was ever wrong.

---

## Many repos: telling KBs apart, and sharing them with the team

`knowledge-base/` is called the same thing in every repo. Inside one repo that is fine — it is
unambiguous, every command looks for exactly that path, and renaming it per project would break your
existing KBs, the machine-wide ignore, and every skill at once. The name only becomes a problem the
moment KBs from several projects sit **side by side**. So the fix is not a folder name, it is
**identity inside the KB plus a namespace at collection time**.

**1. Every KB now says who it is.** `/namht-scan` and `/namht-rescan` write
`knowledge-base/_meta.yml`:

```yaml
project: taskflow
repo: git@github.com:acme/taskflow.git
branch: main
commit: 9f2c1ab        # the KB describes THIS revision
generated: 2026-08-13
depth: standard
modules: [auth, orders, billing]
```

`rescan` refreshes `commit`/`generated` — a KB whose meta points at a three-month-old commit is the
one that gets trusted as current. Per-module docs already carry their own name
(`knowledge-base/modules/<module>.md`).

**2. Collect them into one hub repo, namespaced by project:**

```bash
scripts/kb-export.sh ~/kb-hub ~/work/taskflow ~/work/billing ~/work/gateway
```

```
kb-hub/
├── README.md                                  # index: project · branch · commit · exported · files
└── projects/
    ├── taskflow/{_meta.yml, knowledge-base/…}
    ├── billing/{_meta.yml, knowledge-base/…}
    └── gateway/{_meta.yml, knowledge-base/…}
```

Each folder is a **snapshot**, not a live mirror — re-export after a rescan. If a KB predates
`_meta.yml`, the export synthesises its identity from git. Re-exporting replaces a project's
snapshot rather than merging, so a file deleted upstream disappears here too. The script **never
commits or pushes** — you review it yourself.

**3. It is one browsable web page, not a folder of Markdown.** `kb-export.sh` also writes
`<hub>/index.html` — a **single self-contained page**: projects down the left with a freshness badge,
one tab per KB document across the top, Mermaid diagrams drawn, and a search box that covers every
document in every project at once. It opens with a double-click, works offline (no network calls at
all), and survives being emailed or dropped on a share drive. Build or rebuild it any time:

```bash
node scripts/kb-site.cjs ~/kb-hub              # → ~/kb-hub/index.html
node scripts/kb-site.cjs ~/work/taskflow       # also works on a single repo's knowledge-base/
```

A KB older than 30 days gets an amber badge and a banner naming the commit it actually describes —
the point being that a stale KB should not be able to pass itself off as current.

**4. The hub is also readable by the skills — no clone needed.** Two skills detect the
`projects/*/knowledge-base/` layout and work straight from it, which is what makes the hub useful to
someone who is not a developer:

| Run at the hub root | What you get |
|---|---|
| `/namht-system-map` | The cross-service dependency graph + end-to-end flows. Everything it consumes (`11-api-docs`, `14-integrations`, `17-async-events`) is in the hub, so an architect or a new joiner can produce the map **without cloning a single repo**. |
| `/namht-ask "which services validate tenant id?"` | An answer **across projects**, attributing every claim to a project and leading with the contrast between them — usually the interesting part. |

Both are required to state the two limits out loud: a hub has **no source code**, so nothing can be
confirmed against real files, and every project is a **snapshot** at the commit in its `_meta.yml`.
A confident answer drawn from a KB exported four months ago is the failure mode here, so the dates
are printed, not buried.

**5. A teammate pulls the hub and drops one in:**

```bash
scripts/kb-import.sh ~/kb-hub taskflow ~/work/taskflow
```

It refuses to overwrite an existing `knowledge-base/` (use `--force`, which keeps a timestamped
backup — remember `knowledge-base/` is gitignored, so git will not save you), and it warns when the
snapshot's commit is not in that checkout, which usually means the wrong repo.

> ⚠️ **Keep the hub repo private.** A Knowledge Base is a readable distillation of your source:
> business rules, data model, auth model, endpoints. Page for page it is often *more* sensitive than
> the code, and it is far easier to read. `kb-export.sh` refuses to write into a repo it can see is
> public (via `gh`), but that check is a backstop, not a policy — share it only with people who
> already have access to the repos it came from.

---

## Running a skill on a schedule

Two skills are genuinely periodic — the Splunk error digest, and keeping a Knowledge Base fresh —
and `/namht-drift` is worth a monthly run. `scripts/schedule.sh` wires them to cron:

```bash
scripts/schedule.sh add rescan "0 7 * * 1"  ~/work/my-repo          # Mondays 07:00
scripts/schedule.sh add drift  "0 8 1 * *"  ~/work/my-repo          # 1st of the month
scripts/schedule.sh add splunk "30 8 * * *" ~/work/my-repo -- "index=app_logs cai_enviroment=prod 24h"
scripts/schedule.sh list
scripts/schedule.sh remove rescan ~/work/my-repo
```

It edits a persistent system setting, so it is deliberately careful: every line it writes carries a
`# namht-kit:<preset>:<repo>` marker and it only ever adds or removes **its own** lines; it prints
the exact change and asks before writing (`--dry-run` to just look, `--yes` to skip the prompt); and
it **refuses to schedule any skill that edits code** — an unattended source change should not be
something you can set up by accident. Output goes to `~/.claude/logs/namht-<preset>.log`. Note that
an unattended run cannot answer a permission prompt, so a skill that needs one simply fails in the
log rather than hanging.

---

## Tests — what actually stops this kit breaking your machine

```bash
bash tests/run.sh          # everything below, ~20 seconds
```

The suite is weighted toward the parts that can do damage, not the parts that are easy to test:

| Suite | Cases | Why it exists |
|---|---:|---|
| `git-guard.test.sh` | 97 | Every deny rule, every bypass ever found (each reproduced before it was fixed), and the bare-`push`-resolved-from-cwd path against real fixture repos |
| `kb-hub.test.sh` | 32 | Export/import move real Knowledge Bases between repos; also pins the page generator's escaping and CSP |
| `schedule.test.sh` | 20 | Edits your **crontab** — behind a stubbed `crontab`, so the real one is never touched |
| `webview-markdown.test.cjs` | 18 | The panel renders model output as HTML; pins escaping and that only `http(s)` links become links |
| `migrate-sessions.test.sh` | 15 | Renames a folder full of your past work |
| `onboard.test.sh` | 14 | Writes into **other people's repos** (`.gitignore`, `CLAUDE.md`) |
| `personal-install.test.sh` | 10 | The one script that **deletes** from `~/.claude` — including that a foreign symlink survives an uninstall |
| `i18n.test.cjs` | 5 | Catches a card reworded out of its translation, and status text the host sends in English |
| `consistency.test.sh` | 9 groups | Commands ↔ skills ↔ extension ↔ catalog ↔ counts ↔ changelog ↔ the skill-anatomy trailer |

Plus: bundle sync, skill-name == folder, the vendored libraries' pinned hashes, and `node --check` on
the webview scripts (`tsc` only ever parses `src/`, so a syntax error in `media/` would otherwise ship
a blank panel with a green build).

CI runs the same suite, `yarn compile`, and `shellcheck` on every shell file
([`.github/workflows/ci.yml`](.github/workflows/ci.yml)).

**The principle:** a script that touches something outside this repo — your crontab, your `~/.claude`,
another repo's files — does not ship without a test, because its failures are silent. That rule is
newer than the scripts, which is exactly how several of them turned out to have real bugs.

---

## Security & enterprise

See **[SECURITY.md](SECURITY.md)** for the full audit. In short:
- Executable code is **pure local** (`fs`/`path`/`crypto`) — no shell exec, `eval`, dynamic
  `require`, network calls, or secrets. Safe to copy to a company machine.
- **Offline HTML:** with `vendor/` (Mermaid + Cytoscape, bundled) the generated HTML inlines the
  chart libs → **zero external network calls** (air-gapped / strict-proxy safe). Delete `vendor/`
  to get smaller CDN-linked output instead.
- **Change discipline** is built into `namht-build`/`namht-review`: scope-locked, minimal diff,
  no drive-by refactors, verify-and-rollback (don't leave the build broken), confirm before
  destructive/outward actions, never touch secrets.
- **Git guardrail (hard-enforced):** a PreToolUse hook (`hooks/git-guard.sh`) + `permissions.deny`
  allow read/sync-in git (fetch, pull, status, log, diff, show, blame, add, commit, …) **plus
  `push` only to a whitelisted personal remote** (`ALLOW_OWNER_RE`, default `NamHT4Devlop/*`).
  It **blocks** push to any other (team/org) remote, all remote-config mutation, and destructive
  local git (`reset --hard`, `clean -f`, `checkout --`, `rebase`, `branch -D`, …) — even in chained
  commands. See [SECURITY.md](SECURITY.md#git-guardrail-hard-blocked-readsync-in-only).
- The real data-egress is the AI agent reading code (inherent to any AI assistant), fine under a
  company **Team/Enterprise** Claude plan. `knowledge-base/` and `namht-sessions/`
  are gitignored machine-wide.

## How this maps to the original extension

| Auto Spec extension (VS Code + Copilot) | namht Kit for Claude Code |
|-----------------------------------|--------------------------|
| `vscode.lm` calls to Copilot | Claude Code itself (no external API key) |
| `agent-orchestrator` parallel sub-agents | `Task` tool fan-out to the `agents/` specialists |
| Emits ```### FILE:``` code blocks to copy | Applies changes directly with Edit/Write |
| `testCommand` run by the extension | `Bash` runs the project's test command |
| Session outputs in `namht-sessions/` | Same — artifacts saved per run |
| `knowledge-base/` (16 docs + review-skills + modules) | **Identical format — reused as-is** |
| Webview HTML (ask/plan/document) | Markdown + Mermaid; **`map` = interactive Cytoscape HTML** (bundled analyzer) |

### Not ported (and why)
- The VS Code UI bits (Quick Picks, webviews, keybindings, output channel) — Claude Code is
  the UI now. Q&A/plans/docs are returned as Markdown + Mermaid; ask for HTML if you want it.
- Token-budget/throttling/checkpoint-resume plumbing — Claude Code manages context and tools
  natively, so the methodology is preserved without the bespoke machinery.

---

## Notes
- Every command degrades gracefully if a repo has no `knowledge-base/` — it'll read source
  directly and suggest running `/namht-scan`, but results are richer with a KB.
- `build` and `review` enforce the **"Architecture Invariants — DO NOT BREAK"** list from
  `knowledge-base/16-architecture-patterns.md` and the rules in `knowledge-base/review-skills.md`.
- Source of truth for the methodology: the original prompts of the author's private Auto Spec VS Code
  extension (pipeline steps, its `kb-steps` constants, and `review-skills-universal.md`).
- **Slash-command prefix depends on install method:** `/namht-build` (personal symlink install) vs
  `/namht:build` (plugin install) vs `/build` (plain copy). Skills also auto-activate from plain English.
- **Licensing:** MIT — except `vscode-extension/`, which is proprietary (see `vscode-extension/LICENSE`).
