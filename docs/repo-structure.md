# claude-code-workflow-kit — repository structure

The folder layout and file names of the kit, and what each area is for. **Structure only — no file
contents.** Generated from `git ls-files` at commit `de28b7c`, 242 tracked files.

Read this to know where a thing lives before you go looking for it, or to recreate the same shape in
another repository.

## The shape in one paragraph

A command is a thin entry point; a **skill** holds the method; an **agent** is a read-only specialist
a skill fans out to. Everything a skill needs at runtime sits beside it in its own `references/`
folder, so a skill stays self-contained when copied on its own. The canonical copy of anything shared
lives in `resources/` and is mirrored into those `references/` folders by a script — the copies are
generated, never hand-edited.

## Top-level areas

| Folder | Holds | Count |
|---|---|---|
| `.claude-plugin/` | Plugin manifest and the local marketplace definition | 2 |
| `commands/` | Slash-command entry points, one Markdown file each | 31 |
| `skills/` | The methodology. One folder per skill: `SKILL.md` plus its `references/` | 30 skills, 130 files |
| `agents/` | Read-only sub-agents the build and review steps call in parallel | 7 |
| `resources/` | Canonical copies of shared files, mirrored into skills by `scripts/sync-bundles.sh` | 9 |
| `scripts/` | Installers, the KB pipeline, the hub builder, diagram tooling, this scaffold | 15 |
| `hooks/` | PreToolUse guardrails and their registration | 3 |
| `tests/` | Self-tests, run by `tests/run.sh` | 13 |
| `docs/` | Setup guides and the reference pages, including this one | 8 |
| `vendor/` | Hash-pinned third-party bundles used offline | 4 |
| `vscode-extension/` | Optional panel that drives the local `claude` CLI | 12 |
| `.github/workflows/` | CI | 1 |

## Full tree

```
claude-code-workflow-kit/
├── .claude-plugin/
│   ├── marketplace.json
│   └── plugin.json
├── .github/
│   └── workflows/
│       └── ci.yml
├── agents/
│   ├── cwk-architecture-reviewer.md
│   ├── cwk-business-consistency-reviewer.md
│   ├── cwk-business-flow-tracer.md
│   ├── cwk-codebase-analyzer.md
│   ├── cwk-impact-detector.md
│   ├── cwk-performance-reviewer.md
│   └── cwk-security-reviewer.md
├── commands/
│   ├── ask.md
│   ├── build.md
│   ├── design-review.md
│   ├── discover.md
│   ├── document.md
│   ├── drift.md
│   ├── fix-bug.md
│   ├── help.md
│   ├── issues.md
│   ├── map.md
│   ├── migrate.md
│   ├── observe.md
│   ├── pdf.md
│   ├── perf.md
│   ├── plan-review.md
│   ├── plan.md
│   ├── pr.md
│   ├── qa-integration.md
│   ├── qa.md
│   ├── rails-to-spring.md
│   ├── rescan.md
│   ├── retro.md
│   ├── review.md
│   ├── runbook.md
│   ├── scan.md
│   ├── security-audit.md
│   ├── simplify.md
│   ├── skillify.md
│   ├── splunk-report.md
│   ├── system-map.md
│   └── user-story.md
├── docs/
│   ├── build-flow.md
│   ├── company-setup-guide.html
│   ├── manual-setup-guide.html
│   ├── provenlens.md
│   ├── repo-structure.md
│   ├── setup-guide.html
│   ├── skill-anatomy.md
│   └── skills-catalog.html
├── hooks/
│   ├── file-guard.sh
│   ├── git-guard.sh
│   └── hooks.json
├── resources/
│   ├── check-mermaid.cjs
│   ├── html-builder.js
│   ├── kb-steps.md
│   ├── provenlens-evidence.md
│   ├── render-html.cjs
│   ├── review-protocol.md
│   ├── review-skills-universal.md
│   ├── review-traps.md
│   └── untrusted-input.md
├── scripts/
│   ├── audit-log.sh
│   ├── check-mermaid.cjs
│   ├── fetch-vendor.sh
│   ├── kb-export.sh
│   ├── kb-import.sh
│   ├── kb-pipeline.sh
│   ├── kb-site.cjs
│   ├── measure-diagrams.cjs
│   ├── migrate-sessions.sh
│   ├── onboard-project.sh
│   ├── personal-install.sh
│   ├── scaffold-cwk.sh
│   ├── schedule.sh
│   ├── strip-map-source.cjs
│   └── sync-bundles.sh
├── skills/
│   ├── cwk-ask/
│   │   ├── references/
│   │   │   ├── html-builder.js
│   │   │   ├── provenlens-evidence.md
│   │   │   ├── render-html.cjs
│   │   │   └── untrusted-input.md
│   │   └── SKILL.md
│   ├── cwk-build/
│   │   ├── references/
│   │   │   ├── provenlens-evidence.md
│   │   │   ├── review-skills-universal.md
│   │   │   └── untrusted-input.md
│   │   └── SKILL.md
│   ├── cwk-design-review/
│   │   ├── references/
│   │   │   ├── html-builder.js
│   │   │   ├── render-html.cjs
│   │   │   └── untrusted-input.md
│   │   └── SKILL.md
│   ├── cwk-discover/
│   │   ├── references/
│   │   │   └── untrusted-input.md
│   │   └── SKILL.md
│   ├── cwk-document/
│   │   ├── references/
│   │   │   ├── check-mermaid.cjs
│   │   │   ├── html-builder.js
│   │   │   ├── provenlens-evidence.md
│   │   │   ├── render-html.cjs
│   │   │   └── untrusted-input.md
│   │   └── SKILL.md
│   ├── cwk-drift/
│   │   ├── references/
│   │   │   ├── html-builder.js
│   │   │   ├── render-html.cjs
│   │   │   └── untrusted-input.md
│   │   └── SKILL.md
│   ├── cwk-fix-bug/
│   │   ├── references/
│   │   │   ├── provenlens-evidence.md
│   │   │   └── untrusted-input.md
│   │   └── SKILL.md
│   ├── cwk-issues/
│   │   ├── references/
│   │   │   ├── html-builder.js
│   │   │   ├── render-html.cjs
│   │   │   └── untrusted-input.md
│   │   └── SKILL.md
│   ├── cwk-map/
│   │   ├── references/
│   │   │   ├── build-map.cjs
│   │   │   ├── explorer-template.html
│   │   │   ├── graph-builder.js
│   │   │   ├── provenlens-full.cjs
│   │   │   ├── provenlens-graph.cjs
│   │   │   ├── untrusted-input.md
│   │   │   └── viewer-template.html
│   │   └── SKILL.md
│   ├── cwk-migrate/
│   │   ├── references/
│   │   │   └── untrusted-input.md
│   │   └── SKILL.md
│   ├── cwk-observe/
│   │   ├── references/
│   │   │   └── untrusted-input.md
│   │   └── SKILL.md
│   ├── cwk-pdf/
│   │   ├── references/
│   │   │   ├── html-builder.js
│   │   │   ├── html-to-pdf.sh
│   │   │   ├── print-fix.cjs
│   │   │   ├── render-html.cjs
│   │   │   └── untrusted-input.md
│   │   └── SKILL.md
│   ├── cwk-perf/
│   │   ├── references/
│   │   │   └── untrusted-input.md
│   │   └── SKILL.md
│   ├── cwk-plan/
│   │   ├── references/
│   │   │   ├── html-builder.js
│   │   │   ├── provenlens-evidence.md
│   │   │   ├── render-html.cjs
│   │   │   └── untrusted-input.md
│   │   └── SKILL.md
│   ├── cwk-plan-review/
│   │   ├── references/
│   │   │   ├── html-builder.js
│   │   │   ├── render-html.cjs
│   │   │   └── untrusted-input.md
│   │   └── SKILL.md
│   ├── cwk-pr/
│   │   ├── references/
│   │   │   ├── html-builder.js
│   │   │   ├── render-html.cjs
│   │   │   ├── review-protocol.md
│   │   │   ├── review-skills-universal.md
│   │   │   ├── review-traps.md
│   │   │   └── untrusted-input.md
│   │   └── SKILL.md
│   ├── cwk-qa/
│   │   ├── references/
│   │   │   ├── html-builder.js
│   │   │   ├── provenlens-evidence.md
│   │   │   ├── render-html.cjs
│   │   │   └── untrusted-input.md
│   │   └── SKILL.md
│   ├── cwk-qa-integration/
│   │   ├── references/
│   │   │   ├── html-builder.js
│   │   │   ├── render-html.cjs
│   │   │   └── untrusted-input.md
│   │   └── SKILL.md
│   ├── cwk-rails-to-spring/
│   │   ├── references/
│   │   │   ├── cases.example.json
│   │   │   ├── html-builder.js
│   │   │   ├── render-html.cjs
│   │   │   ├── shadow-parity.cjs
│   │   │   └── untrusted-input.md
│   │   └── SKILL.md
│   ├── cwk-rescan/
│   │   ├── references/
│   │   │   ├── check-mermaid.cjs
│   │   │   ├── kb-steps.md
│   │   │   ├── review-skills-universal.md
│   │   │   └── untrusted-input.md
│   │   └── SKILL.md
│   ├── cwk-retro/
│   │   ├── references/
│   │   │   ├── html-builder.js
│   │   │   ├── render-html.cjs
│   │   │   └── untrusted-input.md
│   │   └── SKILL.md
│   ├── cwk-review/
│   │   ├── references/
│   │   │   ├── provenlens-evidence.md
│   │   │   ├── review-protocol.md
│   │   │   ├── review-skills-universal.md
│   │   │   ├── review-traps.md
│   │   │   └── untrusted-input.md
│   │   └── SKILL.md
│   ├── cwk-runbook/
│   │   ├── references/
│   │   │   ├── check-mermaid.cjs
│   │   │   ├── html-builder.js
│   │   │   ├── provenlens-evidence.md
│   │   │   ├── render-html.cjs
│   │   │   ├── untrusted-input.md
│   │   │   └── writing-style.md
│   │   └── SKILL.md
│   ├── cwk-scan/
│   │   ├── references/
│   │   │   ├── check-mermaid.cjs
│   │   │   ├── kb-steps.md
│   │   │   ├── review-skills-universal.md
│   │   │   └── untrusted-input.md
│   │   └── SKILL.md
│   ├── cwk-security-audit/
│   │   ├── references/
│   │   │   ├── html-builder.js
│   │   │   ├── render-html.cjs
│   │   │   ├── review-skills-universal.md
│   │   │   └── untrusted-input.md
│   │   └── SKILL.md
│   ├── cwk-simplify/
│   │   ├── references/
│   │   │   └── untrusted-input.md
│   │   └── SKILL.md
│   ├── cwk-skillify/
│   │   ├── references/
│   │   │   └── untrusted-input.md
│   │   └── SKILL.md
│   ├── cwk-splunk-report/
│   │   ├── references/
│   │   │   └── untrusted-input.md
│   │   └── SKILL.md
│   ├── cwk-system-map/
│   │   ├── references/
│   │   │   ├── html-builder.js
│   │   │   ├── render-html.cjs
│   │   │   └── untrusted-input.md
│   │   └── SKILL.md
│   └── cwk-user-story/
│       ├── references/
│       │   ├── html-builder.js
│       │   ├── provenlens-evidence.md
│       │   ├── render-html.cjs
│       │   └── untrusted-input.md
│       └── SKILL.md
├── tests/
│   ├── consistency.test.sh
│   ├── file-guard.test.sh
│   ├── git-guard.test.sh
│   ├── i18n.test.cjs
│   ├── kb-hub.test.sh
│   ├── kb-pipeline.test.sh
│   ├── migrate-sessions.test.sh
│   ├── onboard.test.sh
│   ├── personal-install.test.sh
│   ├── run.sh
│   ├── schedule.test.sh
│   ├── smoke.test.sh
│   └── webview-markdown.test.cjs
├── vendor/
│   ├── README.md
│   ├── SHA256SUMS
│   ├── cytoscape.min.js
│   └── mermaid.min.js
├── vscode-extension/
│   ├── media/
│   │   ├── i18n.js
│   │   ├── icon.svg
│   │   ├── main.css
│   │   └── main.js
│   ├── src/
│   │   └── extension.ts
│   ├── .gitignore
│   ├── .vscodeignore
│   ├── LICENSE
│   ├── README.md
│   ├── package.json
│   ├── tsconfig.json
│   └── yarn.lock
├── .gitignore
├── CHANGELOG.md
├── LICENSE
├── NOTICE
├── README.md
├── SECURITY.md
└── THIRD_PARTY_NOTICES.md
```

## How a skill is laid out

Every skill is a folder under `skills/` with the same two parts:

```
skills/<skill-name>/
├── SKILL.md          the method: when it runs, the steps, the rules, the output shape
└── references/       everything it needs at runtime, beside it
```

The folder name is the skill name and matches its command: `commands/build.md` ↔ `skills/cwk-build/`.
All 30 skills follow this without exception.

## Shared files and their copies

A reader will notice the same filenames repeated across many `references/` folders. That is
deliberate and mechanical: the **canonical copy lives in `resources/`**, and
`scripts/sync-bundles.sh` mirrors it into each skill that declares it. A skill therefore keeps
working when it is copied out on its own, and the copies are regenerated rather than edited.

`scripts/sync-bundles.sh --check` fails when any copy has drifted; CI runs it.

| Canonical file in `resources/` | Mirrored into |
|---|---|
| `untrusted-input.md` | all 30 skills |
| `html-builder.js` + `render-html.cjs` | the 17 skills that render HTML |
| `provenlens-evidence.md` | `cwk-ask`, `cwk-build`, `cwk-document`, `cwk-fix-bug`, `cwk-plan`, `cwk-qa`, `cwk-review`, `cwk-runbook`, `cwk-user-story` |
| `review-skills-universal.md` | `cwk-build`, `cwk-pr`, `cwk-rescan`, `cwk-review`, `cwk-scan`, `cwk-security-audit` |
| `review-protocol.md` + `review-traps.md` | `cwk-pr`, `cwk-review` |
| `check-mermaid.cjs` | `cwk-document`, `cwk-rescan`, `cwk-runbook`, `cwk-scan` |
| `kb-steps.md` | `cwk-rescan`, `cwk-scan` |

Files that live in exactly one skill and are **not** mirrored — they belong to that skill alone:

| Skill | Its own files |
|---|---|
| `cwk-map` | `build-map.cjs`, `graph-builder.js`, `provenlens-full.cjs`, `provenlens-graph.cjs`, `explorer-template.html`, `viewer-template.html` |
| `cwk-pdf` | `html-to-pdf.sh`, `print-fix.cjs` |
| `cwk-runbook` | `writing-style.md` |
| `cwk-rails-to-spring` | `shadow-parity.cjs`, `cases.example.json` |

## Naming conventions

- **Commands** are named for the verb: `commands/scan.md`, `commands/build.md`. Installed as
  `/cwk:scan` (plugin) or `/cwk-scan` (personal symlink install).
- **Skills** carry the `cwk-` prefix in the folder name: `skills/cwk-scan/`.
- **Agents** carry it too and say what they are: `agents/cwk-security-reviewer.md`.
- **Tests** are `<subject>.test.sh` or `<subject>.test.cjs`, with `tests/run.sh` as the entry point.
- **Scripts** are named for what they do, not for when they run: `kb-export.sh`, `sync-bundles.sh`.

## What is deliberately absent

These paths never appear in the repository, because they are per-machine working output and are
covered by a global gitignore:

```
cwk-sessions/     build, review, runbook and map output
knowledge-base/   the generated Knowledge Base for a scanned repo
.provenlens/      the call-graph index
```

`vendor/` holds third-party bundles with a `SHA256SUMS` file beside them; the tools verify the hash
before loading, so a bundle that does not match is refused rather than used.

## Recreating this shape elsewhere

The minimum that makes the pattern work:

```
<your-repo>/
├── .claude-plugin/plugin.json
├── commands/<verb>.md
├── skills/<prefix>-<verb>/
│   ├── SKILL.md
│   └── references/
├── agents/<prefix>-<role>.md
├── resources/                 canonical copies of anything shared
└── scripts/sync-bundles.sh    mirrors resources/ into skills/*/references/
```

The one rule worth carrying over: **a shared file has exactly one canonical copy, and a script puts
it everywhere else.** Without that, the copies drift and nobody can tell which one is current.

## Creating this structure with one command

`scaffold-cwk.sh` (beside this document) creates the whole tree with every file empty:

```bash
bash scaffold-cwk.sh                      # → ./claude-code-workflow-kit/
bash scaffold-cwk.sh my-docs-project      # → ./my-docs-project/
```

It produces **242 files in 76 directories**, and the paths were diffed against the real repository —
they match exactly.

Nothing is overwritten. Re-running it after you have started filling files in reports
`0 file(s) created, 242 already present` and leaves your work alone, so it is safe to run again when
the structure grows.

To turn the result into a git repository:

```bash
cd claude-code-workflow-kit
git init -b main && git add -A && git commit -m "Scaffold: kit structure"
```

Note that `git add` ignores empty files by default in the sense that it stores them as empty blobs —
they are committed, but a reviewer sees 242 empty files. If you would rather commit only what you
have written, fill the files first and commit in batches.

### Regenerating the script from a real repository

On any machine that has the repository, the script rebuilds itself from the current file list:

```bash
cd <repo> && git ls-files
```

Everything in `scaffold-cwk.sh` between `<<'PATHS'` and `PATHS` is that output verbatim. Replacing
that block regenerates the scaffold for whatever the repository looks like now.
